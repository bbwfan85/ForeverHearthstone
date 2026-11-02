--[[ tests/test_partials.lua

  The cards that were flagged PARTIAL in tools/effects (docs/08 §8.5) -- each
  suite is the missing half of that card, so none of them can quietly go
  partial again. Some were already fixed by engine work done since the flag
  was written (deathrattles append; destroyed secrets leave the zone); those
  suites are what proves it.
]]
local H = require("tests.harness")

local function game(opts)
  local g = H.NewGame(opts or { firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  return g
end
local function handCount(g, p) return #g.players[p].hand end

--=========================================================== FP1_019 Poison Seeds

H.suite("partials: Poison Seeds -- a minion's own deathrattle fires too", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "DRUID" })
  H.Put(g, 1, "EX1_096")                          -- Loot Hoarder: Deathrattle: draw
  H.Put(g, 2, "CS2_231"); H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "FP1_019")
  local before = handCount(g, 1)
  H.ok(g:PlayCard(1, i), "cast")
  g.bus:Drain()
  H.board(g, 1, { "FP1_019t 2/2" }, "my Loot Hoarder became a Treant")
  H.board(g, 2, { "FP1_019t 2/2", "FP1_019t 2/2" }, "and each of theirs")
  H.eq(handCount(g, 1), before - 1 + 1, "and the Hoarder's own deathrattle still drew")
  H.noEngineErrors(g)
end)

--=========================================================== FP1_025 Reincarnate

H.suite("partials: Reincarnate -- the deathrattle fires, then it comes back", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "SHAMAN" })
  local hoarder = H.Put(g, 1, "EX1_096")
  local i = H.Hand(g, 1, "FP1_025")
  local before = handCount(g, 1)
  H.ok(g:PlayCard(1, i, hoarder), "cast on my Loot Hoarder")
  g.bus:Drain()
  H.board(g, 1, { "EX1_096 2/1" }, "it is back, at printed stats")
  H.eq(handCount(g, 1), before - 1 + 1, "and its deathrattle drew a card on the way")
  H.noEngineErrors(g)
end)

H.suite("partials: Ancestral Spirit -- keeps the minion's own deathrattle", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "SHAMAN" })
  local hoarder = H.Put(g, 1, "EX1_096")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "CS2_038")), hoarder), "blessed")
  g.bus:Drain()
  local before = handCount(g, 1)
  g:DealDamage(hoarder, 5, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.board(g, 1, { "EX1_096 2/1" }, "it returned")
  H.eq(handCount(g, 1), before + 1, "and drew as it died")
  H.noEngineErrors(g)
end)

--================================================================= EX1_544 Flare

H.suite("partials: Flare -- destroys their secrets, strips Stealth, draws", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "HUNTER", class2 = "MAGE" })
  -- Ice Barrier: not Counterspell, which would (rightly) counter the Flare
  g:PlaySecret(2, ns.Entity.New(g:Printed("EX1_289"), 2, g.ids))
  H.eq(#g.players[2].secrets, 1, "they have a secret")
  local worgen = H.Put(g, 2, "EX1_010")                              -- Worgen Infiltrator, Stealth
  H.ok(worgen:Has(ns.KEYWORD.STEALTH), "and a stealthed minion")
  local i = H.Hand(g, 1, "EX1_544")
  local before = handCount(g, 1)
  H.ok(g:PlayCard(1, i), "Flare")
  g.bus:Drain()
  H.eq(#g.players[2].secrets, 0, "their secret is destroyed")
  H.notOk(worgen:Has(ns.KEYWORD.STEALTH), "the minion is revealed")
  H.eq(handCount(g, 1), before - 1 + 1, "and I drew")
  H.noEngineErrors(g)
end)

--============================================================== EX1_126 Betrayal

H.suite("partials: Betrayal -- the minion deals it, so Spell Damage does not", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "ROGUE" })
  H.Put(g, 1, "CS2_142")                          -- Kobold Geomancer: Spell Damage +1
  H.Put(g, 2, "CS2_200"); local yeti = H.Put(g, 2, "CS2_182"); H.Put(g, 2, "CS2_200")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_126")), yeti), "Betrayal on the Yeti")
  g.bus:Drain()
  H.board(g, 2, { "CS2_200 6/3", "CS2_182 4/5", "CS2_200 6/3" }, "each neighbour took 4, not 5")
  H.noEngineErrors(g)
end)

H.suite("partials: Betrayal -- a Poisonous minion's betrayal kills", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "ROGUE" })
  H.Put(g, 2, "CS2_200"); local cobra = H.Put(g, 2, "EX1_170"); H.Put(g, 2, "CS2_200")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_126")), cobra), "Betrayal on the Emperor Cobra")
  g.bus:Drain()
  H.board(g, 2, { "EX1_170 2/3" }, "both Ogres were poisoned")
  H.noEngineErrors(g)
end)

--========================================================= EX1_558 Harrison Jones

H.suite("partials: Harrison Jones -- destroys the weapon and draws its Durability", function(ns, H)
  local g = game({ firstPlayer = 1 })
  g:EquipWeapon(2, "CS2_106")                     -- Fiery War Axe, 2 Durability
  local i = H.Hand(g, 1, "EX1_558")
  local before = handCount(g, 1)
  H.ok(g:PlayCard(1, i), "Harrison Jones")
  g.bus:Drain()
  H.eq(g.players[2].weapon, nil, "their weapon is gone")
  H.eq(handCount(g, 1), before - 1 + 2, "and I drew 2, one per Durability")
  local g2 = game({ firstPlayer = 1 })
  local j = H.Hand(g2, 1, "EX1_558"); local before2 = handCount(g2, 1)
  H.ok(g2:PlayCard(1, j), "no weapon to break")
  g2.bus:Drain()
  H.eq(handCount(g2, 1), before2 - 1, "draws nothing")
  H.noEngineErrors(g); H.noEngineErrors(g2)
end)

--====================================== GVG_078 Mechanical Yeti, PRO_001 E.T.C.

local function each(g, before1, before2, prefix, what)
  H.eq(handCount(g, 1), before1 + 1, what .. ": I get one")
  H.eq(handCount(g, 2), before2 + 1, what .. ": and so does my opponent")
  for p = 1, 2 do
    local last = g.players[p].hand[#g.players[p].hand]
    H.ok(last and last.cardId:find(prefix, 1, true) == 1, what .. " -- player " .. p .. " got " .. tostring(last and last.cardId))
  end
end

H.suite("partials: Mechanical Yeti -- EACH player gets a Spare Part", function(ns, H)
  local g = game({ firstPlayer = 1 })
  local yeti = H.Put(g, 1, "GVG_078")
  local b1, b2 = handCount(g, 1), handCount(g, 2)
  g:DealDamage(yeti, 9, nil, false); g:ProcessDeaths(); g.bus:Drain()
  each(g, b1, b2, "PART_", "Mechanical Yeti")
  H.noEngineErrors(g)
end)

H.suite("partials: Elite Tauren Chieftain -- EACH player gets a Power Chord", function(ns, H)
  local g = game({ firstPlayer = 1 })
  local i = H.Hand(g, 1, "PRO_001")
  local b1, b2 = handCount(g, 1) - 1, handCount(g, 2)
  H.ok(g:PlayCard(1, i), "E.T.C. played")
  g.bus:Drain()
  each(g, b1, b2, "PRO_001", "Elite Tauren Chieftain")
  H.noEngineErrors(g)
end)

--====================================================== EX1_315 Summoning Portal

H.suite("partials: Summoning Portal -- (2) less, but not less than (1)", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "WARLOCK" })
  local cards = {}
  for _, id in ipairs({ "CS2_231", "EX1_509", "EX1_531", "CS2_182" }) do
    local i = H.Hand(g, 1, id); cards[id] = g.players[1].hand[i]
  end
  H.Put(g, 1, "EX1_315")
  g:RecalcAuras()
  H.eq(g:CardCost(cards.CS2_182, 1), 2, "Yeti 4 -> 2")
  H.eq(g:CardCost(cards.EX1_531, 1), 1, "a 2-cost stops at 1, not 0")
  H.eq(g:CardCost(cards.EX1_509, 1), 1, "a 1-cost stays 1")
  H.eq(g:CardCost(cards.CS2_231, 1), 0, "and a 0-cost is never raised")
  H.Put(g, 1, "EX1_315")                          -- a second Portal
  g:RecalcAuras()
  H.eq(g:CardCost(cards.CS2_182, 1), 1, "two Portals: Yeti 4 -> 2 -> 1, the floor again")
  H.noEngineErrors(g)
end)

--======================================================= EX1_334 Shadow Madness

H.suite("partials: Shadow Madness -- a Silence does not stop the stolen minion attacking", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "PRIEST" })
  local yeti = H.Put(g, 2, "CS2_120")             -- River Crocolisk 2/3
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_334")), yeti), "stolen")
  g.bus:Drain()
  H.notOk(yeti:Has(ns.KEYWORD.CHARGE), "it is not given Charge")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_332")), yeti), "and silenced")
  g.bus:Drain()
  H.ok(g:CanAttack(yeti), "it can still attack this turn")
  H.noEngineErrors(g)
end)

H.suite("partials: Shadow Madness -- no room to go home, it is destroyed", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "PRIEST" })
  local stolen = H.Put(g, 2, "CS2_120")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_334")), stolen), "stolen")
  g.bus:Drain()
  for _ = 1, 7 do H.Put(g, 2, "CS2_231") end       -- their board fills up meanwhile
  g:EndTurn(); g.bus:Drain()
  H.eq(stolen.zone, ns.ZONE.GRAVEYARD, "it could not go back, so it died")
  H.eq(#g.players[1].board, 0, "it did not stay with me either")
  H.noEngineErrors(g)
end)

--=================================================== EX1_363 Blessing of Wisdom

H.suite("partials: Blessing of Wisdom on an ENEMY minion -- the caster draws", function(ns, H)
  local g = game({ firstPlayer = 1, class1 = "PALADIN" })
  local theirs = H.Put(g, 2, "CS2_182")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_363")), theirs), "blessed their Yeti")
  g.bus:Drain()
  H.SetActive(g, 2)
  local mine, foe = handCount(g, 1), handCount(g, 2)
  g:Attack(theirs, H.Hero(g, 1)); g.bus:Drain()
  H.eq(handCount(g, 1), mine + 1, "their Yeti attacked and I drew")
  H.eq(handCount(g, 2), foe, "they did not")
  H.noEngineErrors(g)
end)
