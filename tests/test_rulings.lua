--[[ tests/test_rulings.lua -- rules found by the Fireplace oracle (docs/33).

  Each was a difference between this engine and Fireplace, settled against
  hearthstone.wiki.gg rather than memory, and the engine changed. One suite per
  rule; the wiki page is named in each.

  Fixtures, verified against the pin:
    EX1_335  Lightspawn 0/5        CS2_087  Blessing of Might    CS2_188 Abusive Sergeant
    EX1_162  Dire Wolf Alpha       CS2_024  Frostbolt            EX1_033 Windfury Harpy 4/5
    CS2_033  Water Elemental 3/6   EX1_564  Faceless Manipulator EX1_008 Argent Squire
    FP1_030  Loatheb               EX1_608  Sorcerer's Apprentice CS2_008 Moonfire
    NEW1_029 Millhouse Manastorm   GVG_032  Grove Tender         EX1_136 Redemption
    EX1_556  Harvest Golem 2/3     EX1_562  Onyxia               FP1_019 Poison Seeds
    FP1_018  Duplicate             EX1_096  Loot Hoarder         CS2_182 Chillwind Yeti 4/5
    CS2_231  Wisp                  CS2_029  Fireball             CS2_200 Boulderfist Ogre 6/7
]]
local H = require("tests.harness")

local function play(g, p, id, target, pos, mode)
  local i = H.Hand(g, p, id)
  local ok, why = g:PlayCard(p, i, target, pos, mode)
  g.bus:Drain()
  return ok, why
end

-- ------------------------------------------------ wiki: Lightspawn

H.suite("rulings: Lightspawn ignores Attack buffs", function(ns, H)
  local g = H.NewGame({ class1 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ls = H.Put(g, 1, "EX1_335")
  H.ok(play(g, 1, "CS2_087", ls), "Blessing of Might lands")
  H.eq(ls:Attack(), 5, "and does nothing: Attack is its Health")
  H.ok(play(g, 1, "CS2_188", ls), "Abusive Sergeant lands")
  H.eq(ls:Attack(), 5, "nor does a this-turn buff")
  H.ok(play(g, 1, "EX1_162", nil, 2), "Dire Wolf Alpha beside it")
  H.eq(g:AttackValue(ls), 5, "nor an aura")
  g:DealDamage(ls, 2, nil, false); g.bus:Drain()
  H.eq(ls:Attack(), 3, "Health changes still move it")
  H.noEngineErrors(g)
end)

H.suite("rulings: Lightspawn reads printed 0 in hand and after Silence", function(ns, H)
  local g = H.NewGame()
  local _, card = H.Hand(g, 1, "EX1_335")
  H.eq(card:Attack(), 0, "printed 0 in hand")
  local ls = H.Put(g, 1, "EX1_335")
  ls:AddEnchantment(2, 0)
  ls:Silence()
  H.eq(ls:Attack(), 0, "silenced: printed 0, and the buff is gone with it")
  H.noEngineErrors(g)
end)

-- --------------------------------------------------- wiki: Freeze

H.suite("rulings: frozen on your own turn before attacking thaws tonight", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  H.ok(play(g, 1, "CS2_024", yeti), "Frostbolt my own Yeti")
  H.ok(yeti.frozen, "frozen")
  g:EndTurn()
  H.notOk(yeti.frozen, "it lost this turn's attack, so it thaws at the end of it")
  H.noEngineErrors(g)
end)

H.suite("rulings: frozen after using its attack stays frozen a turn", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  H.ok(g:Attack(yeti, H.Hero(g, 2)), "swings"); g.bus:Drain()
  H.ok(play(g, 1, "CS2_024", yeti), "then Frostbolt")
  g:EndTurn()
  H.ok(yeti.frozen, "still frozen through the opponent's turn")
  g:EndTurn()
  H.ok(yeti.frozen, "and through my next turn's start")
  g:EndTurn()
  H.notOk(yeti.frozen, "thaws at the end of that turn")
  H.noEngineErrors(g)
end)

H.suite("rulings: a Windfury minion frozen by its first swing thaws tonight", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local harpy = H.Put(g, 1, "EX1_033")
  local water = H.Put(g, 2, "CS2_033")
  H.ok(g:Attack(harpy, water), "attacks the Water Elemental"); g.bus:Drain()
  H.ok(harpy.frozen, "frozen by it")
  g:EndTurn()
  H.notOk(harpy.frozen, "it still had an attack, so it thaws at the end of the turn")
  H.noEngineErrors(g)
end)

H.suite("rulings: frozen during the opponent's turn misses one turn", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  H.ok(play(g, 2, "CS2_024", yeti), "the opponent freezes my Yeti")
  g:EndTurn()                       -- into my turn
  H.ok(yeti.frozen, "frozen on my turn")
  H.notOk(g:CanAttack(yeti), "cannot attack")
  g:EndTurn()
  H.notOk(yeti.frozen, "thawed at the end of my turn")
  H.noEngineErrors(g)
end)

-- ---------------------------------------------- wiki: Copy / Faceless

H.suite("rulings: Faceless copies damage", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ogre = H.Put(g, 2, "CS2_200")
  g:DealDamage(ogre, 3, nil, false); g.bus:Drain()
  H.ok(play(g, 1, "EX1_564", ogre), "Faceless on a 6/4 Ogre")
  H.board(g, 1, { "CS2_200 6/4" }, "the copy is a 6/4 too")
  H.noEngineErrors(g)
end)

H.suite("rulings: a copy of a popped Divine Shield has no shield at all", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local wisp = H.Put(g, 1, "CS2_231")
  local squire = H.Put(g, 2, "EX1_008")
  H.ok(g:Attack(wisp, squire), "pop the shield"); g.bus:Drain()
  H.ok(play(g, 1, "EX1_564", squire), "copy the Squire")
  local copy = g.players[1].board[1]
  H.eq(copy.cardId, "EX1_008", "a Squire")
  H.notOk(copy.divineShieldUp, "no working shield")
  H.notOk(copy:Has(ns.KEYWORD.DIVINE_SHIELD), "and no keyword for the board or the AI to show")
  H.noEngineErrors(g)
end)

-- ------------------------------------------------- wiki: Mana cost

H.suite("rulings: cost floors at zero only after every modifier", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 2, "EX1_608")                       -- their Apprentice: Moonfire at (-1)
  local _, moon = H.Hand(g, 2, "CS2_008")
  H.ok(play(g, 1, "FP1_030"), "Loatheb")
  H.eq(g:CardCost(moon, 2), 4, "(-1) + 5 = (4), not (5)")
  H.noEngineErrors(g)
end)

H.suite("rulings: Apprentice after Loatheb still discounts", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local _, moon = H.Hand(g, 2, "CS2_008")
  H.ok(play(g, 1, "FP1_030"), "Loatheb")
  g:EndTurn(); H.Mana(g, 2, 10)
  H.ok(play(g, 2, "EX1_608"), "then an Apprentice")
  H.eq(g:CardCost(moon, 2), 4, "0 + 5 - 1 = (4)")
  H.noEngineErrors(g)
end)

H.suite("rulings: 'costs (0)' and '+5' apply in the order they were made", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local _, fb = H.Hand(g, 2, "CS2_029")
  H.ok(play(g, 1, "NEW1_029"), "Millhouse: their spells cost (0)")
  H.ok(play(g, 1, "FP1_030"), "then Loatheb: +5")
  H.eq(g:CardCost(fb, 2), 5, "0 then +5 = (5)")

  local g2 = H.NewGame()
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  local _, fb2 = H.Hand(g2, 2, "CS2_029")
  H.ok(play(g2, 1, "FP1_030"), "Loatheb first")
  H.ok(play(g2, 1, "NEW1_029"), "then Millhouse")
  H.eq(g2:CardCost(fb2, 2), 0, "+5 then set to 0 = (0)")
  H.noEngineErrors(g); H.noEngineErrors(g2)
end)

-- ----------------------------------------------- wiki: Grove Tender

H.suite("rulings: Gift of Mana gives filled crystals", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 5); H.Mana(g, 2, 5)
  local modes = ns.Targeting.ModesOf(g:Printed("GVG_032") and { printed = g:Printed("GVG_032") })
  local m
  for k, id in ipairs(modes) do if id == "GVG_032a" then m = k end end
  H.ok(play(g, 1, "GVG_032", nil, nil, m), "Grove Tender, Gift of Mana")
  H.eq(g.players[1].maxMana, 6, "a sixth crystal")
  H.eq(g:AvailableMana(1), 3, "filled: 5 - 3 + 1")
  H.eq(g:AvailableMana(2), 6, "the opponent's is filled too")
  H.noEngineErrors(g)
end)

-- ------------------------------------------------- wiki: Redemption

H.suite("rulings: Redemption returns a minion damaged down to 1", function(ns, H)
  local g = H.NewGame({ class2 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local golem = H.Put(g, 2, "EX1_556")
  local sec = ns.Entity.New(g:Printed("EX1_136"), 2, g.ids)
  H.ok(g:PlaySecret(2, sec), "Redemption up")
  H.ok(play(g, 1, "CS2_029", golem), "Fireball the Golem")
  local back
  for _, e in ipairs(g.players[2].board) do if e.cardId == "EX1_556" then back = e end end
  H.ok(back, "the Golem came back")
  H.eq(back:Health(), 1, "at 1 Health")
  H.eq(back:MaxHealth(), 3, "of its full 3")
  H.ok(back:IsDamaged(), "and it counts as damaged (Enrage would be on)")
  H.noEngineErrors(g)
end)

-- ---------------------------------------------------- wiki: Onyxia

H.suite("rulings: Onyxia's Whelps alternate right and left", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_231"); H.Put(g, 1, "CS2_231")
  H.ok(play(g, 1, "EX1_562", nil, 2), "Onyxia between the Wisps")
  local ids = {}
  for i, e in ipairs(g.players[1].board) do ids[i] = e.cardId end
  H.eq(table.concat(ids, " "),
       "CS2_231 ds1_whelptoken ds1_whelptoken EX1_562 ds1_whelptoken ds1_whelptoken CS2_231",
       "two Whelps each side")
  H.noEngineErrors(g)
end)

-- ---------------------------------------------- wiki: Poison Seeds

H.suite("rulings: Poison Seeds' Treants come after the deathrattles", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_182"); H.Put(g, 1, "EX1_556")
  H.Put(g, 2, "CS2_200")
  H.ok(play(g, 1, "FP1_019"), "Poison Seeds")
  H.board(g, 1, { "skele21 2/1", "FP1_019t 2/2", "FP1_019t 2/2" },
          "Damaged Golem first, then a Treant per dead minion on the right")
  H.board(g, 2, { "FP1_019t 2/2" }, "one Treant for them")
  H.noEngineErrors(g)
end)

-- ----------------------------- death reactions resolve in play order

H.suite("rulings: a Loot Hoarder played before Duplicate draws first", function(ns, H)
  local g = H.NewGame({ class2 = "MAGE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local hoarder = H.Put(g, 2, "EX1_096")
  H.PutOnDeck(g, 2, "CS2_182")
  local sec = ns.Entity.New(g:Printed("FP1_018"), 2, g.ids)
  H.ok(g:PlaySecret(2, sec), "Duplicate, played after the Hoarder")
  local before = #g.players[2].hand
  H.ok(play(g, 1, "CS2_029", hoarder), "Fireball the Hoarder")
  local hand = g.players[2].hand
  H.eq(#hand, before + 3, "a draw and two copies")
  H.eq(hand[before + 1].cardId, "CS2_182", "the deathrattle's draw comes first")
  H.eq(hand[before + 2].cardId, "EX1_096", "then Duplicate's copies")
  H.noEngineErrors(g)
end)

-- ------------------------------------------------ wiki: Kezan Mystic

H.suite("rulings: Kezan Mystic passes over a Secret you already have", function(ns, H)
  for seed = 1, 20 do
    local g = H.NewGame({ seed = seed, class2 = "MAGE" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local function sec(p, id) local e = ns.Entity.New(g:Printed(id), p, g.ids); g:PlaySecret(p, e) end
    sec(1, "EX1_289"); sec(2, "EX1_289"); sec(2, "EX1_287")
    H.ok(play(g, 1, "GVG_074"), "Kezan Mystic")
    local mine = {}
    for _, s in ipairs(g.players[1].secrets) do mine[#mine + 1] = s.cardId end
    H.eq(table.concat(mine, ","), "EX1_289,EX1_287", "seed " .. seed .. ": steals the Counterspell")
    H.eq(#g.players[2].secrets, 1, "and leaves them their Ice Barrier")
    H.noEngineErrors(g)
  end
end)

H.suite("rulings: Kezan Mystic destroys a Secret when all are duplicates", function(ns, H)
  local g = H.NewGame({ class2 = "MAGE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local function sec(p, id) local e = ns.Entity.New(g:Printed(id), p, g.ids); g:PlaySecret(p, e) end
  sec(1, "EX1_289"); sec(2, "EX1_289")
  H.ok(play(g, 1, "GVG_074"), "Kezan Mystic")
  H.eq(#g.players[1].secrets, 1, "I still have one Ice Barrier")
  H.eq(#g.players[2].secrets, 0, "theirs was destroyed")
  H.noEngineErrors(g)
end)

-- ------------------------------------------ wiki: Health (gained max)

H.suite("rulings: Silence that RAISES maximum Health raises Health too", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ogre = H.Put(g, 1, "CS2_200")                 -- 6/7
  H.ok(play(g, 1, "PART_006", ogre), "Reversing Switch: 7/6")
  H.eq(ogre:Health(), 6, "6 Health")
  ogre:Silence()
  H.eq(ogre:Attack(), 6, "back to 6 Attack")
  H.eq(ogre:Health(), 7, "and 7 Health, not a damaged 6/7")
  H.noEngineErrors(g)
end)

-- ---------------------------------------- wiki: Soul of the Forest

H.suite("rulings: Soul of the Forest's Treants arrive on the far right", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local wisp = H.Put(g, 1, "CS2_231")
  H.Put(g, 1, "CS2_182")
  H.ok(play(g, 1, "EX1_158"), "Soul of the Forest")
  H.ok(play(g, 1, "CS2_029", wisp), "Fireball the left Wisp")
  H.board(g, 1, { "CS2_182 4/5", "EX1_158t 2/2" }, "the Treant is right of the Yeti, not in the Wisp's slot")
  H.noEngineErrors(g)
end)

-- ------------------------------------------------ wiki: Dr. Boom

H.suite("rulings: Dr. Boom's Boom Bots flank him", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(play(g, 1, "GVG_110"), "Dr. Boom")
  local ids = {}
  for i, e in ipairs(g.players[1].board) do ids[i] = e.cardId end
  H.eq(table.concat(ids, " "), "GVG_110t GVG_110 GVG_110t", "one each side")
  H.noEngineErrors(g)
end)
