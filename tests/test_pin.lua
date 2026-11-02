--[[ tests/test_pin.lua -- PATCH PIN CANARIES.

  The whole "no card stat is ever recalled" guarantee rests on the pin being
  what we think it is. These tests assert the identity of the pinned build using
  cards whose stats CHANGED across builds, so an accidental re-pin fails loudly
  instead of silently shifting the balance of the game.

  Pinned: build 7234 = Basic + Classic + Naxxramas + Goblins vs Gnomes,
  carrying the GvG-era balance patch.

  If you deliberately re-pin, update this file in the same commit. That is the
  point: changing the balance of the game should require touching a file called
  test_pin.lua.
]]
local H = require("tests.harness")

H.suite("pin: build identity", function(ns, H)
  H.eq(ns.PATCH_BUILD, 7234, "pinned build")
  H.ok(ns.DATA_SHA256 and #ns.DATA_SHA256 == 64, "source hash recorded")
end)

H.suite("pin: GvG-era nerfs are present", function(ns, H)
  local P = ns.PrintedCards
  -- Starving Buzzard: 2 mana 2/1 pre-nerf -> 5 mana 3/2. The single biggest
  -- balance change between the two candidate pins.
  H.eq(P["CS2_237"].cost, 5, "Starving Buzzard cost")
  H.eq(P["CS2_237"].atk,  3, "Starving Buzzard attack")
  H.eq(P["CS2_237"].hp,   2, "Starving Buzzard health")

  H.eq(P["EX1_116"].cost, 5, "Leeroy Jenkins cost (was 4)")
  H.eq(P["EX1_095"].cost, 6, "Gadgetzan Auctioneer cost (was 5)")
  H.eq(P["EX1_308"].cost, 1, "Soulfire cost (was 0)")
  H.eq(P["EX1_544"].cost, 2, "Flare cost (was 1)")

  -- Unleash the Hounds stayed at 3 through this patch -- the reason we never
  -- considered the 2-mana launch build.
  H.eq(P["EX1_538"].cost, 3, "Unleash the Hounds cost")
end)

H.suite("pin: Adrenaline Rush was removed from the game", function(ns, H)
  -- EXPERT1 drops 246 -> 245 at this build. If this card reappears, the pin
  -- has moved backwards.
  local found = false
  for id, c in pairs(ns.PrintedCards) do
    if c.name == "Adrenaline Rush" then found = true end
  end
  H.notOk(found, "Adrenaline Rush absent")
end)

H.suite("pin: all four sets present with expected counts", function(ns, H)
  --[[ Must filter on the explicit `collectible` flag, not on set. Tokens share
       set values with real cards -- Silver Hand Recruit is set=CORE -- so
       counting by set alone inflates every total. (Found by this test failing:
       the importer was not emitting a collectible flag at all.) ]]
  local n = { CORE = 0, EXPERT1 = 0, NAXX = 0, GVG = 0, PROMO = 0, REWARD = 0 }
  for _, c in pairs(ns.PrintedCards) do
    if n[c.set] ~= nil and c.collectible and c.type ~= "HERO" then
      n[c.set] = n[c.set] + 1
    end
  end
  H.eq(n.CORE,    133, "Basic set size")
  H.eq(n.EXPERT1, 245, "Classic set size")
  H.eq(n.NAXX,     30, "Naxxramas set size")
  H.eq(n.GVG,     123, "GvG set size")
  H.eq(n.CORE + n.EXPERT1 + n.NAXX + n.GVG, 531, "total collectible pool")
end)

H.suite("pin: class card counts are symmetric across all nine classes", function(ns, H)
  --[[ The levelling curve depends on every class having the same number of
       cards. 10 Basic + 15 Classic + 1 Naxx + 8 GvG = 34 per class, which is
       what makes the 1-60 grant schedule work. Rogue lost its 16th Classic card
       (Adrenaline Rush) at this build, which is what made the counts line up. ]]
  local SETS = { CORE = true, EXPERT1 = true, NAXX = true, GVG = true }
  local per = {}
  for _, c in pairs(ns.PrintedCards) do
    if c.collectible and c.type ~= "HERO"
       and c.class and c.class ~= "NEUTRAL" and SETS[c.set] then
      per[c.class] = (per[c.class] or 0) + 1
    end
  end
  for _, cl in ipairs(ns.CLASSES) do
    H.eq(per[cl], 34, cl .. " total class cards")
  end
end)

H.suite("pin: GvG additions the engine must handle", function(ns, H)
  local P = ns.PrintedCards
  -- MECHANICAL is a new race; it must arrive as plain data.
  local mechs = 0
  for _, c in pairs(P) do
    if c.race == "MECHANICAL" and c.set == "GVG" and c.rarity then mechs = mechs + 1 end
  end
  H.ok(mechs >= 40, "Mech race imported (" .. mechs .. " GvG mechs)")

  -- Spare Parts ride on the printed entourage field, which the existing
  -- Summon/AddCardToHand fromEntourage path already consumes.
  H.ok(P["GVG_082"] ~= nil, "Clockwork Gnome present")
  local gnome = P["GVG_082"]
  if gnome then
    H.ok(gnome.entourage and #gnome.entourage == 7, "seven Spare Parts in entourage")
  end

  -- The two genuinely new mechanics, one card each. Both are known gaps with
  -- engine work outstanding; these assertions document that they exist so the
  -- gap cannot be forgotten.
  H.ok(ns.HasPrintedKeyword(P["GVG_066"], "FORGETFUL"), "Dunemaul Shaman is FORGETFUL")
  H.ok(P["GVG_007"] ~= nil, "Flame Leviathan present (TOPDECK, not yet supported)")
end)
