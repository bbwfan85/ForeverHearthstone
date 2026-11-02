--[[ tests/test_assets.lua -- asset resolution and the guaranteed floor.

  The single most important property under test: a card is ALWAYS renderable.
  683 art slots are needed, no icon path can be verified without the client, and
  SetTexture fails silently on a bad path. So the resolver must never return a
  descriptor that the UI cannot draw, and the game must be fully playable with
  zero valid art.
]]
local H = require("tests.harness")

H.suite("assets: all collectible cards have real packaged TGA illustrations", function(ns, H)
  local manifest = ns.GenericArt.Manifest({})
  local count = 0
  for id, printed in pairs(ns.PrintedCards) do
    if printed.collectible then
      count = count + 1
      H.ok(manifest.cards[id], id .. " has bundled art")
    end
  end
  H.ok(count > 500, "covers the whole collectible set")
  --[[ Every packaged texture, checked on disk and for format. `boards` is a
       LIST rather than a path -- the match board rotation, see
       Client/UI/Board.lua SetBoardArt -- so it is flattened in rather than
       being walked as if it were a single texture. ]]
  local packaged = {}
  for id, path in pairs(ns.HearthstoneArt) do
    if type(path) == "string" then packaged[id] = path end
  end
  local nBoards = 0
  for i, path in ipairs(ns.HearthstoneArt.boards or {}) do
    packaged["board rotation " .. i] = path
    nBoards = nBoards + 1
  end
  H.ok(nBoards >= 1, "at least one board is packaged (" .. nBoards .. ")")
  -- Hearthstone's four launch boards, composited by tools/composite_boards.py
  local rotation = table.concat(ns.HearthstoneArt.boards or {}, "|")
  for _, name in ipairs({ "orgrimmar", "stormwind", "stranglethorn" }) do
    H.ok(rotation:find("board_" .. name .. ".tga", 1, true), name .. " is in the match rotation")
  end
  H.eq(#ns.HearthstoneArt.boards, 3, "only the three clean classic boards are played on")
  H.notOk(rotation:find("pandaria", 1, true), "Pandaria is gone from the rotation")
  H.eq(ns.HearthstoneArt.board_pandaria, nil, "and from the addon entirely")
  H.notOk(rotation:find("orgrimmar_clean", 1, true), "the sketched reference board is not played on")

  for id, path in pairs(packaged) do
    local localPath = path:gsub("Interface\\AddOns\\", ""):gsub("\\", "/")
    local file = io.open(localPath, "rb")
    H.ok(file, id .. " exists on disk")
    if file then
      local header = file:read(18); file:close()
      H.eq(header:byte(3), 2, id .. " is uncompressed truecolor TGA")
      H.ok(header:byte(17) == 24 or header:byte(17) == 32, id .. " is RGB/RGBA")
    end
  end
  local custom = ns.GenericArt.Manifest({cards = {CS2_182 = {icon = "custom"}}})
  H.eq(custom.cards.CS2_182.icon, "custom", "user art still wins")
end)

local MISSING = [[Interface\Icons\INV_Misc_QuestionMark]]

local function R(ns, opts)
  opts = opts or {}
  opts.printed = opts.printed or ns.PrintedCards
  opts.palette = opts.palette or { MAGE = { 0.41, 0.80, 0.94 } }
  return ns.Resolver.New(opts)
end

--==================================================== the guaranteed floor

H.suite("assets: an empty manifest still renders every card legibly", function(ns, H)
  --[[ The whole point. With no manifest at all -- the state the addon ships in
       until someone fills it -- every card must still carry name, cost and stats,
       because those come from printed data rather than from art. ]]
  local r = R(ns)
  local ids = { "CS2_182", "CS2_029", "EX1_162", "GVG_066", "FP1_013" }
  for _, id in ipairs(ids) do
    local d = r:Card(id)
    H.ok(d.legible, id .. " is legible")
    H.ok(d.name and #d.name > 0, id .. " has a name")
    H.ok(d.icon ~= nil, id .. " always has SOME icon path")
    H.ok(d.frameColor and #d.frameColor == 3, id .. " has a frame colour")
    H.ok(d.gemColor and #d.gemColor == 3, id .. " has a rarity gem colour")
  end
  local yeti = r:Card("CS2_182")
  H.eq(yeti.name, "Chillwind Yeti", "name from printed data")
  H.eq(yeti.cost, 4, "cost from printed data")
  H.eq(yeti.atk, 4, "attack from printed data")
  H.eq(yeti.hp, 5, "health from printed data")
end)

H.suite("assets: an unknown card id renders rather than crashing", function(ns, H)
  local r = R(ns)
  local d = r:Card("NOT_A_REAL_CARD")
  H.ok(d.missing, "flagged missing")
  H.ok(d.legible, "still legible")
  H.eq(d.icon, MISSING, "falls back to the question mark")
  H.eq(d.name, "NOT_A_REAL_CARD", "shows the id, which is more useful than an error")
end)

--======================================================== the fallback chain

H.suite("assets: override beats manifest beats generic beats question mark", function(ns, H)
  local base = { generic = { MINION = [[Interface\Icons\GENERIC_MINION]] },
                 cards = { CS2_182 = { icon = [[Interface\Icons\FROM_MANIFEST]] } } }

  -- 1. user override wins
  local r1 = R(ns, { manifest = base,
                     override = { CS2_182 = { icon = [[Interface\Icons\FROM_PACK]] } } })
  local d1 = r1:Card("CS2_182")
  H.eq(d1.icon, [[Interface\Icons\FROM_PACK]], "override wins")
  H.eq(d1.tier, "override", "tier recorded")

  -- 2. shipped manifest next
  local r2 = R(ns, { manifest = base })
  H.eq(r2:Card("CS2_182").icon, [[Interface\Icons\FROM_MANIFEST]], "manifest next")
  H.eq(r2:Card("CS2_182").tier, "manifest", "tier recorded")

  -- 3. generic by type for a card with no entry
  local d3 = r2:Card("CS2_119")          -- Oasis Snapjaw, no manifest entry
  H.eq(d3.icon, [[Interface\Icons\GENERIC_MINION]], "generic by type")
  H.eq(d3.tier, "generic", "tier recorded")

  -- 4. nothing at all
  local r4 = R(ns)
  H.eq(r4:Card("CS2_119").icon, MISSING, "question mark last")
  H.eq(r4:Card("CS2_119").tier, "fallback", "tier recorded")
end)

H.suite("assets: generic lookup prefers type+class over type over class", function(ns, H)
  local m = { generic = {
    SPELL         = [[Interface\Icons\ANY_SPELL]],
    SPELL_MAGE    = [[Interface\Icons\MAGE_SPELL]],
    PRIEST        = [[Interface\Icons\ANY_PRIEST]],
    DEFAULT       = [[Interface\Icons\FALLBACK]],
  } }
  local r = R(ns, { manifest = m })
  -- Fireball is a MAGE SPELL: most specific key wins
  H.eq(r:Card("CS2_029").icon, [[Interface\Icons\MAGE_SPELL]], "type+class most specific")
  -- Holy Smite is a PRIEST spell with no PRIEST_SPELL key -> falls to SPELL
  H.eq(r:Card("CS1_130").icon, [[Interface\Icons\ANY_SPELL]], "type before class")
  -- a Priest MINION has no SPELL key match, so falls to the class key
  H.eq(r:Card("EX1_335").icon, [[Interface\Icons\ANY_PRIEST]], "class when type misses")
end)

H.suite("assets: DEFAULT catches anything the other generics miss", function(ns, H)
  local r = R(ns, { manifest = { generic = { DEFAULT = [[Interface\Icons\CATCHALL]] } } })
  H.eq(r:Card("CS2_182").icon, [[Interface\Icons\CATCHALL]], "neutral minion caught")
  H.eq(r:Card("CS2_029").icon, [[Interface\Icons\CATCHALL]], "mage spell caught")
end)

--=============================================================== 3-D models

H.suite("assets: models are optional and never required", function(ns, H)
  local r = R(ns)
  H.eq(r:Card("CS2_182").model, nil, "no model by default")
  H.ok(r:Card("CS2_182").icon ~= nil, "and the icon still resolves")

  local r2 = R(ns, { manifest = { cards = { CS2_182 = { model = 1234 } } } })
  H.eq(r2:Card("CS2_182").model, 1234, "model supplied by the manifest")

  -- a user pack can override a model just like an icon
  local r3 = R(ns, { manifest = { cards = { CS2_182 = { model = 1234 } } },
                     override = { CS2_182 = { model = 9999 } } })
  H.eq(r3:Card("CS2_182").model, 9999, "override wins for models too")
end)

H.suite("assets: useModels=false suppresses models entirely", function(ns, H)
  -- A player on a weak machine, or one who dislikes the model frames, must be
  -- able to turn them off and still get a complete card.
  local r = R(ns, { useModels = false,
                    manifest = { cards = { CS2_182 = { model = 1234 } } } })
  local d = r:Card("CS2_182")
  H.eq(d.model, nil, "models suppressed")
  H.ok(d.icon ~= nil, "icon still present")
  H.ok(d.legible, "still legible")
end)

--================================================================== colours

H.suite("assets: class colours come from the injected palette", function(ns, H)
  --[[ Class colours are NOT hardcoded -- WoW already knows them and reading the
       client's own values keeps us matching whatever Forever ships rather than
       asserting vanilla hexes from memory. ]]
  local r = R(ns, { palette = { MAGE = { 0.1, 0.2, 0.3 } } })
  local c = r:Card("CS2_029").frameColor          -- Fireball, MAGE
  H.eq(c[1], 0.1, "palette r")
  H.eq(c[2], 0.2, "palette g")
  H.eq(c[3], 0.3, "palette b")

  -- a class absent from the palette falls back rather than erroring
  local d = r:Card("CS1_130")                     -- PRIEST, not in this palette
  H.ok(d.frameColor and #d.frameColor == 3, "missing class still gets a colour")
end)

H.suite("assets: neutral cards use the neutral colour, not a class colour", function(ns, H)
  local r = R(ns, { palette = { MAGE = { 1, 0, 0 } } })
  local n = r:Card("CS2_182").frameColor          -- Chillwind Yeti, NEUTRAL
  H.notOk(n[1] == 1 and n[2] == 0 and n[3] == 0, "did not pick up a class colour")
end)

H.suite("assets: rarity gems are distinct per rarity", function(ns, H)
  local r = R(ns)
  local seen = {}
  for _, id in ipairs({ "CS2_182", "NEW1_019", "EX1_312", "EX1_016" }) do
    local d = r:Card(id)
    local key = table.concat(d.gemColor, ",")
    H.ok(seen[key] == nil,
         (d.rarity or "?") .. " gem colour is distinct (" .. key .. ")")
    seen[key] = d.rarity
  end
end)

--================================================================ coverage

H.suite("assets: coverage report counts real art versus fallbacks", function(ns, H)
  local ids = { "CS2_182", "CS2_029", "EX1_162", "CS2_119" }
  local r = R(ns, {
    manifest = { cards = { CS2_182 = { icon = "A" }, CS2_029 = { icon = "B" } } },
    override = { EX1_162 = { icon = "C" } },
  })
  local n = r:Coverage(ids)
  H.eq(n.total, 4, "four cards checked")
  H.eq(n.override, 1, "one from the user pack")
  H.eq(n.manifest, 2, "two from the shipped manifest")
  H.eq(n.fallback, 1, "one fell through to the question mark")
  H.eq(n.real, 3, "three have real art")
  H.ok(math.abs(n.pct - 75) < 0.01, "75% coverage")
end)

H.suite("assets: an empty manifest reports 0% coverage, not an error", function(ns, H)
  local r = R(ns)
  local n = r:Coverage({ "CS2_182", "CS2_029" })
  H.eq(n.real, 0, "no real art")
  H.eq(n.pct, 0, "0%")
  H.eq(n.fallback, 2, "both fell through")
end)

H.suite("assets: the whole pinned pool resolves without error", function(ns, H)
  --[[ The real smoke test: every collectible card plus every token that can
       appear on the board must produce a legible descriptor. If this passes with
       an empty manifest, the UI cannot be handed an unrenderable card. ]]
  local r = R(ns)
  local n, bad = 0, 0
  for id, c in pairs(ns.PrintedCards) do
    if c.type ~= "ENCHANTMENT" then
      local d = r:Card(id)
      n = n + 1
      if not (d.legible and d.icon and d.name and d.frameColor and d.gemColor) then
        bad = bad + 1
      end
    end
  end
  H.ok(n > 600, "checked the whole pool (" .. n .. " entries)")
  H.eq(bad, 0, "every single one is renderable")
end)
