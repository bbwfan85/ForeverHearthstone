--[[ tests/test_statecarry.lua -- what each zone move does to a minion's state.

  Player report that started this: "when you copy a card with deathrattle (at
  least if you give it deathrattle with another card) it doesn't copy that
  effect". Game:CopyState carried buffs, damage and Silence across, and quietly
  dropped granted deathrattles and triggers. That is a CLASS of bug, not a
  one-off: any path that moves or rebuilds a minion has to decide, for every
  field the engine stores on it, whether it is carried, reset, kept or cleared --
  and a field nobody decided about is silently wrong.

  So this file makes the decision explicit and checks it two ways:

    1. POLICY: every field on an entity has a row saying what each path does
       to it. A field that appears on any entity without a row FAILS the suite
       ("unclassified field"), so a new field cannot be added without deciding
       how copy, bounce, transform, silence and steal treat it.

    2. MATRIX: every scripted card that changes a minion is played on a Yeti,
       for real, and then each path runs on that Yeti and is checked against
       the same policy. A new card that grants something new is covered the
       day it is scripted, with no test written for it.

  Paths, and the rule each column encodes (hearthstone.wiki.gg/wiki/Copy):
    copy       Faceless / Echoing Ooze / "summon a copy". Copies "all damage and
               enchantments"; granted deathrattles and triggers are enchantments.
               Aura buffs are not carried (they are recomputed where it lands).
    bounce     Leaving play for a hand or deck: Sap, Youthful Brewmaster, Gang
               Up-style shuffles, Alarm-o-Bot itself. A fresh card: printed.
    transform  Polymorph. A different card: everything is the new card's.
    silence    Enchantments, keywords, triggers and deathrattles go; damage stays.
    control    Mind Control. Nothing about the minion changes but whose it is.
    arrive     A card moving FORWARD keeps what it has: played from hand, drawn
               from the deck, swapped in by Alarm-o-Bot. Enchantments on a card
               in hand or deck stay with it (wiki: Copy, "in-hand enchantments");
               its script is attached when it reaches play.

  Values:
    "src"      equals the copied minion's value         (copy only)
    "fresh"    equals a brand-new entity of the result card, in the same zone
    "kept"     unchanged by the path
    "cleared"  nil / false / 0 / a table of those
    { eq = v } exactly v
    "derived"  recomputed from other fields (aura layer) -- checked by test_aura
    "own"      the path's own business (identity, position, turn stamps) --
               asserted by that path's own tests, not here
]]
local H = require("tests.harness")

local PATHS = { "copy", "bounce", "transform", "silence", "control", "arrive" }

-- field              copy       bounce     transform  silence    control arrive
local P = {
  instanceId     = { "own",     "kept",    "kept",    "kept",    "kept", "kept"    },
  cardId         = { "src",     "fresh",   "fresh",   "kept",    "kept", "kept"    },
  printed        = { "src",     "fresh",   "fresh",   "kept",    "kept", "kept"    },
  controller     = { "own",     "own",     "kept",    "kept",    "own", "kept"    },
  owner          = { "own",     "own",     "kept",    "kept",    "kept", "kept"    },
  zone           = { "own",     "own",     "kept",    "kept",    "kept", "own"     },
  boardIndex     = { "own",     "own",     "kept",    "kept",    "own", "own"     },
  lastBoardIndex = { "own",     "own",     "own",     "own",     "own", "own"     },
  playOrder      = { "own",     "kept",    "kept",    "kept",    "kept", "own"     },
  base           = { "src",     "fresh",   "fresh",   "kept",    "kept", "kept"    },
  ench           = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  enchKeywords   = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  enchantmentSources = { "src", "fresh",   "fresh",   "cleared", "kept", "kept"    },
  timed          = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  timedEnch      = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  timedKeywords  = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  baseKeywords   = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  divineShieldUp = { "src",     "fresh",   "fresh",   "cleared", "kept", "kept"    },
  triggers       = { "src",     "fresh",   "fresh",   "cleared", "kept", "fresh"   },
  deathrattles   = { "src",     "fresh",   "fresh",   "cleared", "kept", "fresh"   },
  spellDamageBonus = { "src",   "cleared", "cleared", "cleared", "kept", "kept"    },
  attackIsHealth = { "src",     "fresh",   "fresh",   "own",     "kept", "fresh"   },
  silenced       = { "src",     "fresh",   "fresh",   { eq = true }, "kept", "kept" },
  -- damage is carried by a copy; Silence's soak rule is test_rulings' business
  damage         = { "src",     "fresh",   "fresh",   "own",     "kept", "kept"    },
  armor          = { "cleared", "cleared", "cleared", "kept",    "kept", "kept"    },
  --[[ Frozen is a status, not an enchantment, and the wiki's Copy page names
       only damage and enchantments: a copy arrives unfrozen. A transformed
       minion is a new minion and is not Frozen either. ]]
  frozen         = { "cleared", "cleared", "cleared", "cleared", "kept", "kept"    },
  pendingDestroy = { "cleared", "cleared", "cleared", "kept",    "kept", "kept"    },
  -- a copy is a new arrival; Mind Control makes the stolen minion sick
  attacksThisTurn = { "cleared", "cleared", "kept",   "kept",    "cleared", "kept"    },
  summonedTurn   = { "own",     "cleared", "kept",    "kept",    "own", "own"     },
  -- bookkeeping: a generation counter and three derived layers
  enchGen        = { "own",     "own",     "own",     "own",     "own", "own"     },
  aura           = { "derived", "derived", "derived", "derived", "derived", "derived" },
  auraKeywords   = { "derived", "derived", "derived", "derived", "derived", "derived" },
  auraSources    = { "derived", "derived", "derived", "derived", "derived", "derived" },
  enraged        = { "derived", "derived", "derived", "derived", "derived", "derived" },
}

-- -------------------------------------------------------------- comparison

-- Absent, false and an empty list mean the same thing to every reader.
local function blank(v) return v == nil or v == false or (type(v) == "table" and next(v) == nil) end

local function deepEq(a, b, seen)
  if a == b then return true end
  if blank(a) and blank(b) then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not deepEq(v, b[k], seen) then return false end end
  for k, v in pairs(b) do if a[k] == nil and not blank(v) then return false end end
  return true
end

local function cleared(v)
  if v == nil or v == false or v == 0 then return true end
  if type(v) ~= "table" then return false end
  for _, x in pairs(v) do if not cleared(x) then return false end end
  return true
end

local function snap(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local c = {}; seen[v] = c
  for k, x in pairs(v) do c[k] = snap(x, seen) end
  return c
end

local function snapEntity(e)
  local s = {}
  for k, v in pairs(e) do s[k] = (k == "printed") and v or snap(v) end
  return s
end

local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts, n = {}, 0
  for k, x in pairs(v) do
    n = n + 1
    if n > 6 then parts[#parts + 1] = "..."; break end
    parts[#parts + 1] = tostring(k) .. "=" .. (type(x) == "table" and "{..}" or tostring(x))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

--[[ Check one path's result against the policy column. `before` is a
     snapshot taken just before the path ran, `src` the copied minion (copy
     only) and `fresh` a brand-new entity of the result card in the result zone.
     Returns a list of problems rather than asserting, so a matrix run can name
     the card. ]]
local function check(col, result, before, src, fresh)
  local bad = {}
  local keys = {}
  for _, t in ipairs({ result, before or {}, src or {}, fresh }) do
    for k in pairs(t) do keys[k] = true end
  end
  for k in pairs(keys) do
    local row = P[k]
    if not row then
      bad[#bad + 1] = ("unclassified field '%s' -- add a row to the policy in "
        .. "tests/test_statecarry.lua and decide what every path does with it"):format(k)
    else
      local rule, v, want, ok = row[col], result[k], nil, true
      if rule == "src" then want = src[k]; ok = deepEq(v, want)
      elseif rule == "fresh" then want = fresh[k]; ok = deepEq(v, want)
      elseif rule == "kept" then want = before[k]; ok = deepEq(v, want)
      elseif rule == "cleared" then want = "cleared"; ok = cleared(v)
      elseif type(rule) == "table" then want = rule.eq; ok = (v == rule.eq) end
      if not ok then
        bad[#bad + 1] = ("%s.%s: %s rule wants %s, got %s")
          :format(PATHS[col], k, type(rule) == "table" and "eq" or rule, show(want), show(v))
      end
    end
  end
  table.sort(bad)
  return bad
end

-- ------------------------------------------------------------------ paths

local SHEEP = "CS2_tk1"

-- A brand-new entity of `cardId` standing where a path's result stands.
local function freshIn(zone, cardId)
  local g0 = H.NewGame()
  if zone == "HAND" then return select(2, H.Hand(g0, 1, cardId)) end
  if zone == "DECK" then return H.PutOnDeck(g0, 1, cardId) end
  local e = H.Put(g0, 1, cardId)
  g0:RecalcAuras()
  return e
end

-- Alarm-o-Bot's own ops, run with `me` as the swapper (Ops.SwapWithHand).
local function alarmSwap(g, me)
  local ops = H.ns.Scripts["EX1_006"].triggers[1].ops
  H.ns.Ops.Run(g, ops, { source = me, controller = me.controller })
  g.bus:Drain()
end

--[[ Each runner takes a freshly built (g, e) and returns the problem list.
     `build` is called once per path, so every path starts from the same state:
     the setups are seeded and deterministic. ]]
local RUN = {}

RUN.copy = function(build)
  local problems = {}
  -- Echoing Ooze / Mirror-style summon
  local g, e = build()
  local c = g:SummonCopy(e, e.controller, nil)
  if not c then return { "copy: SummonCopy made nothing" } end
  for _, p in ipairs(check(1, c, nil, e, freshIn("PLAY", e.cardId))) do
    problems[#problems + 1] = "summon-copy " .. p
  end
  -- Faceless Manipulator: the same state, through Transform + CopyState
  g, e = build()
  H.Mana(g, e.controller, 10)
  local i, faceless = H.Hand(g, e.controller, "EX1_564")
  local ok, why = g:PlayCard(e.controller, i, e)
  g.bus:Drain()
  if not ok then return { "faceless: could not play: " .. tostring(why) } end
  for _, p in ipairs(check(1, faceless, nil, e, freshIn("PLAY", e.cardId))) do
    problems[#problems + 1] = "faceless " .. p
  end
  return problems
end

RUN.bounce = function(build)
  local g, e = build()
  local before = snapEntity(e)
  g:MoveToHand(e)
  if e.zone ~= H.ns.ZONE.HAND then return { "bounce: did not reach hand" } end
  return check(2, e, before, nil, freshIn("HAND", e.cardId))
end

RUN.transform = function(build)
  local g, e = build()
  local before = snapEntity(e)
  g:Transform(e, SHEEP)
  return check(3, e, before, nil, freshIn("PLAY", SHEEP))
end

RUN.silence = function(build)
  local g, e = build()
  local before = snapEntity(e)
  e:Silence(); g:RecalcAuras()
  return check(4, e, before, nil, freshIn("PLAY", e.cardId))
end

RUN.control = function(build)
  local g, e = build()
  local before = snapEntity(e)
  g:ChangeController(e, g:Opponent(e.controller))
  return check(5, e, before, nil, freshIn("PLAY", e.cardId))
end

-- Leaving play for the deck (Gang Up, Malorne, Kingsman-style shuffles).
RUN.shuffle = function(build)
  local g, e = build()
  local before = snapEntity(e)
  g:ShuffleIn(e)
  if e.zone ~= H.ns.ZONE.DECK then return { "shuffle: did not reach deck" } end
  local out = {}
  for _, p in ipairs(check(2, e, before, nil, freshIn("DECK", e.cardId))) do out[#out + 1] = "shuffle " .. p end
  return out
end

-- Alarm-o-Bot's swap, from the side of the minion that LEAVES play.
RUN.swapout = function(build)
  local g, e = build()
  local hand = g.players[e.controller].hand
  for i = #hand, 1, -1 do table.remove(hand, i) end
  H.Hand(g, e.controller, "CS2_231")
  local before = snapEntity(e)
  alarmSwap(g, e)
  if e.zone ~= H.ns.ZONE.HAND then return { "swapout: did not reach hand" } end
  local out = {}
  for _, p in ipairs(check(2, e, before, nil, freshIn("HAND", e.cardId))) do out[#out + 1] = "swapout " .. p end
  return out
end

local BOARD_RUNS = { "copy", "bounce", "shuffle", "swapout", "transform", "silence", "control" }

local function runAll(build)
  local all = {}
  for _, name in ipairs(BOARD_RUNS) do
    for _, p in ipairs(RUN[name](build)) do all[#all + 1] = p end
  end
  return all
end

--[[ The forward moves. `buildHand` returns (g, e) with e an enchanted card in
     player 1's hand; `buildDeck` the same with e on top of the deck. ]]
local function runArrive(buildHand, buildDeck)
  local out = {}
  local function add(tag, list) for _, p in ipairs(list) do out[#out + 1] = tag .. " " .. p end end

  local g, e = buildHand()
  local before = snapEntity(e)
  local idx; for i, c in ipairs(g.players[1].hand) do if c == e then idx = i end end
  local ok, why = g:PlayCard(1, idx)
  g.bus:Drain()
  if not ok or e.zone ~= H.ns.ZONE.PLAY then
    out[#out + 1] = "play: did not reach play: " .. tostring(why)
  else
    add("play", check(6, e, before, nil, freshIn("PLAY", e.cardId)))
  end

  g, e = buildHand()
  local hand = g.players[1].hand
  for i = #hand, 1, -1 do if hand[i] ~= e then table.remove(hand, i) end end
  local bot = H.Put(g, 1, "EX1_006")
  before = snapEntity(e)
  alarmSwap(g, bot)
  if e.zone ~= H.ns.ZONE.PLAY then
    out[#out + 1] = "swapin: did not reach play"
  else
    add("swapin", check(6, e, before, nil, freshIn("PLAY", e.cardId)))
  end

  g, e = buildDeck()
  before = snapEntity(e)
  g:Draw(1)
  if e.zone ~= H.ns.ZONE.HAND then
    out[#out + 1] = "draw: did not reach hand"
  else
    add("draw", check(6, e, before, nil, freshIn("HAND", e.cardId)))
  end
  return out
end

local function report(H, problems, what)
  if #problems == 0 then H.ok(true, what) return end
  local shown = {}
  for i = 1, math.min(#problems, 12) do shown[i] = "      " .. problems[i] end
  if #problems > 12 then shown[#shown + 1] = ("      ... and %d more"):format(#problems - 12) end
  H.ok(false, what .. "\n" .. table.concat(shown, "\n"))
end

-- ------------------------------------------------- 1. synthetic loaded minion

local function play(g, p, id, target)
  local i = H.Hand(g, p, id)
  local ok, why = g:PlayCard(p, i, target)
  g.bus:Drain()
  assert(ok, ("setup: %s did not play: %s"):format(id, tostring(why)))
end

--[[ One minion carrying every kind of state the engine can put on a minion,
     each from a real card where one exists, so "src" and "fresh" can never be
     equal by accident. ]]
local function loaded(cardId)
  return function()
    local ns = H.ns
    local g = H.NewGame({ class1 = "PALADIN" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local e = H.Put(g, 1, cardId)
    play(g, 1, "CS2_092", e)           -- Blessing of Kings: +4/+4 enchantment
    play(g, 1, "CS2_188", e)           -- Abusive Sergeant: +2 Attack this turn
    play(g, 1, "EX1_363", e)           -- Blessing of Wisdom: granted trigger
    H.Mana(g, 1, 10)
    play(g, 1, "CS2_038", e)           -- Ancestral Spirit: granted deathrattle
    e:AddEnchantment(0, 0, { ns.KEYWORD.WINDFURY }, "TEST")   -- granted keyword
    e.damage = 1
    e.spellDamageBonus = 1
    e.frozen = true
    e.attacksThisTurn = 1
    g:RecalcAuras()
    return g, e
  end
end

for _, base in ipairs({
  { "EX1_032", "Sunwalker (printed Taunt + Divine Shield)" },
  { "EX1_335", "Lightspawn (attack-is-health script)" },
  { "EX1_096", "Loot Hoarder (printed deathrattle)" },
  { "EX1_008", "Argent Squire with its shield popped" },
}) do
  H.suite("statecarry: every path honours the policy -- " .. base[2], function(ns, H)
    local build = loaded(base[1])
    if base[1] == "EX1_008" then
      local inner = build
      build = function()
        local g, e = inner()
        e.divineShieldUp = false
        e.baseKeywords[ns.KEYWORD.DIVINE_SHIELD] = nil
        return g, e
      end
    end
    report(H, runAll(build), "copy / bounce / shuffle / swap / transform / silence / control")
  end)
end

-- A card with enchantments sitting in hand or on top of the deck.
local function enchantCard(e)
  local ns = H.ns
  e:AddEnchantment(1, 1, { ns.KEYWORD.TAUNT }, "TEST")
  e:SetEnchantmentStat("cost", -1, "TEST")
end

for _, id in ipairs({ "EX1_032", "EX1_335", "EX1_096", "CS2_182" }) do
  H.suite("statecarry: an enchanted card keeps it moving forward -- " .. id, function(ns, H)
    local function buildHand()
      local g = H.NewGame({ class1 = "PALADIN" })
      H.SetActive(g, 1); H.Mana(g, 1, 10)
      local _, e = H.Hand(g, 1, id)
      enchantCard(e); g:RecalcAuras()
      return g, e
    end
    local function buildDeck()
      local g = H.NewGame({ class1 = "PALADIN" })
      H.SetActive(g, 1); H.Mana(g, 1, 10)
      local e = H.PutOnDeck(g, 1, id)
      enchantCard(e)
      return g, e
    end
    report(H, runArrive(buildHand, buildDeck), "play / Alarm-o-Bot swap-in / draw")
  end)
end

-- ------------------------------------------- 2. every scripted card, for real

--[[ Play a card at a Yeti and return a builder for the resulting state, or nil
     when the card did not change the Yeti (or could not be played on it): then
     there is nothing to carry and nothing to check. ]]
local YETI = "CS2_182"

local function caseFor(cardId, mode)
  local pr = H.ns.PrintedCards[cardId]
  local function build()
    local g = H.NewGame({ class1 = (pr.class ~= "NEUTRAL" and pr.class) or "MAGE", seed = 777 })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local yeti = H.Put(g, 1, YETI)
    local before = snapEntity(yeti)
    local i = H.Hand(g, 1, cardId)
    local ok = g:PlayCard(1, i, yeti, nil, mode)
    if not ok then ok = g:PlayCard(1, i, nil, nil, mode) end
    if ok then g.bus:Drain() end
    return g, yeti, ok, before
  end
  local g, yeti, ok, before = build()
  if not ok or #g.errors > 0 or g.over then return nil end
  if yeti.zone ~= H.ns.ZONE.PLAY or yeti.controller ~= 1 then return nil end
  local changed = false
  for k, row in pairs(P) do
    if row[1] == "src" and not deepEq(yeti[k], before[k]) then changed = true; break end
  end
  if not changed then return nil end
  return function() local g2, y2 = build(); return g2, y2 end
end

H.suite("statecarry: every card that changes a minion survives every path", function(ns, H)
  local ids = {}
  for id in pairs(ns.Scripts or {}) do
    local pr = ns.PrintedCards[id]
    if pr and pr.collectible and (pr.type == "SPELL" or pr.type == "MINION") then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  local covered, problems = 0, {}
  for _, id in ipairs(ids) do
    local modes = ns.Targeting.ModesOf(H.ns.Entity.New(ns.PrintedCards[id], 1))
    for _, mode in ipairs(modes and { 1, 2 } or { false }) do
      local build = caseFor(id, mode or nil)
      if build then
        covered = covered + 1
        for _, p in ipairs(runAll(build)) do
          problems[#problems + 1] = ("%s (%s%s): %s"):format(
            id, ns.PrintedCards[id].name, mode and (" mode " .. mode) or "", p)
        end
      end
    end
  end
  --[[ A floor, not an exact count: if the harness stopped being able to play
       cards, every case would be skipped and the suite would pass vacuously. ]]
  H.ok(covered >= 25, ("at least 25 cards change a minion (found %d)"):format(covered))
  report(H, problems, ("%d minion-changing cards through every path"):format(covered))
end)

-- ---------------------------------------------- 3. copies made INTO a hand

--[[ "If a card is copied from play to a hand, the copy does not retain
     enchantments" -- but hand-to-hand and deck-to-hand copies DO
     (hearthstone.wiki.gg/wiki/Copy). Mind Vision copying a card the opponent
     had discounted keeps the discount. ]]
H.suite("statecarry: Mind Vision keeps a hand card's enchantments", function(ns, H)
  local g = H.NewGame({ class1 = "PRIEST" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  for i = #g.players[2].hand, 1, -1 do table.remove(g.players[2].hand, i) end
  local _, theirs = H.Hand(g, 2, YETI)
  theirs:SetEnchantmentStat("cost", -3, "EX1_tk") ; g:RecalcAuras()
  H.eq(theirs:Cost(), 1, "their Yeti costs (1)")
  local before = #g.players[1].hand
  local i = H.Hand(g, 1, "CS2_003")
  H.ok(g:PlayCard(1, i)); g.bus:Drain()
  local hand = g.players[1].hand
  H.eq(#hand, before + 1, "Mind Vision added a card")
  local mine = hand[#hand]
  H.eq(mine.cardId, YETI, "a Yeti")
  H.eq(mine:Cost(), 1, "still costing (1)")
  H.ok(mine ~= theirs, "a separate entity")
  theirs:SetEnchantmentStat("cost", 0, "X"); g:RecalcAuras()
  H.eq(mine:Cost(), 1, "and not sharing their card's enchantment table")
  H.noEngineErrors(g)
end)

H.suite("statecarry: a copy from PLAY to hand is the printed card", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, YETI)
  yeti:AddEnchantment(4, 4, nil, "CS2_092"); g:RecalcAuras()
  local i = H.Hand(g, 1, "GVG_005")    -- Echo of Medivh
  H.ok(g:PlayCard(1, i)); g.bus:Drain()
  local hand = g.players[1].hand
  local copy = hand[#hand]
  H.eq(copy.cardId, YETI, "a Yeti")
  H.eq(copy:Attack(), 4, "printed Attack")
  H.eq(#(copy.enchantmentSources or {}), 0, "no enchantments")
  H.noEngineErrors(g)
end)

-- --------------------------------------------------- 4. Echoing Ooze timing

--[[ "If Power Overwhelming is cast on Echoing Ooze before the end of the turn,
     the Ooze's copy will not die at the end of your turn" (wiki: Echoing Ooze).
     The copy is made DURING the end of turn and so misses that turn's
     end-of-turn triggers, its inherited Power Overwhelming included. ]]
H.suite("statecarry: Echoing Ooze's Power Overwhelmed copy outlives this turn", function(ns, H)
  local g = H.NewGame({ class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "FP1_003")
  H.ok(g:PlayCard(1, i)); g.bus:Drain()
  local ooze = g.players[1].board[1]
  i = H.Hand(g, 1, "EX1_316")
  H.ok(g:PlayCard(1, i, ooze)); g.bus:Drain()
  g:EndTurn(); g.bus:Drain()
  H.eq(#g.players[1].board, 1, "the original died, the copy did not")
  H.eq(#g.players[1].board[1].triggers, 1, "the copy still carries Power Overwhelming")
  g:EndTurn(); g.bus:Drain()
  H.eq(#g.players[1].board, 0, "and dies at the end of the next turn")
  H.noEngineErrors(g)
end)
