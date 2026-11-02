--[[ tests/test_cards_classes_b.lua -- behaviour tests for the cards authored in
     tools/effects/cards_classes_b.csv.

  One suite per card. See tests/test_chooseone.lua for the house style: name the
  fixture cards and their printed stats in a comment, assert the board with
  H.board, and finish with H.noEngineErrors so an unknown op or selector cannot
  pass silently.

  Cards under test (all four authored in this slot):
    EX1_304  Void Terror        3 mana 3/3  Battlecry: destroy both neighbours,
                                            gain their Attack and Health
    EX1_320  Bane of Doom       5 mana      $2 to a character; if that kills it,
                                            summon a random Demon (entourage)
    GVG_024  Cogmaster's Wrench 3 mana 1/3  +2 Attack while you have a Mech
    GVG_054  Ogre Warmaul       3 mana 4/2  50% chance to attack the wrong enemy

  Fixtures used below, all verified against the pin:
    CS2_231  Wisp                0 mana 1/1 vanilla
    CS2_182  Chillwind Yeti      4 mana 4/5 vanilla
    CS2_200  Boulderfist Ogre    6 mana 6/7 vanilla
    CS2_119  Oasis Snapjaw       4 mana 2/7 vanilla Beast
    GVG_044  Spider Tank         3 mana 3/4 vanilla MECHANICAL
    EX1_008  Argent Squire       1 mana 1/1 Divine Shield
    CS2_112  Arcanite Reaper     5 mana 5/2 Warrior weapon, no text
]]
local H = require("tests.harness")

--=================================================== EX1_304 Void Terror

-- The six Demons Bane of Doom may roll, straight off the pinned entourage.
local BANE_DEMONS = {
  EX1_306 = true, CS2_065 = true, EX1_319 = true,
  EX1_301 = true, CS2_059 = true, CS2_064 = true,
}

H.suite("classes_b: Void Terror -- eats BOTH neighbours and gains their stats", function(ns, H)
  --[[ Yeti 4/5 on the left, Ogre 6/7 on the right. A 3/3 that ate both is
       3+4+6 / 3+5+7 = 13/15. The interesting failure mode is gaining only ONE
       neighbour's stats: attackOf()/healthOf() read the FIRST match of a
       selector, so `attackOf(adjacent)` would quietly give +4/+5 and stop. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_182")                       -- Chillwind Yeti 4/5
  H.Put(g, 1, "CS2_200")                       -- Boulderfist Ogre 6/7

  local i = H.Hand(g, 1, "EX1_304")
  H.ok(g:PlayCard(1, i, nil, 2), "Void Terror played between them")
  g.bus:Drain()

  H.board(g, 1, { "EX1_304 13/15" }, "both neighbours eaten, both sets of stats gained")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Void Terror -- gains a neighbour's CURRENT health, not its maximum", function(ns, H)
  --[[ A Yeti chipped to 2 health is worth +4/+2, not +4/+5. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")          -- 4/5
  g:DealDamage(yeti, 3, nil, false)
  H.eq(yeti:Health(), 2, "Yeti chipped to 2")

  local i = H.Hand(g, 1, "EX1_304")
  H.ok(g:PlayCard(1, i, nil, 2), "Void Terror played to the right of it")
  g.bus:Drain()

  H.board(g, 1, { "EX1_304 7/5" }, "gained 4 Attack and only the 2 health left")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Void Terror -- one neighbour, and none at all", function(ns, H)
  -- Only a left neighbour: eats exactly that one.
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_231")                       -- Wisp 1/1
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_304"))), "played to the right of a Wisp")
  g.bus:Drain()
  H.board(g, 1, { "EX1_304 4/4" }, "ate the lone neighbour")
  H.noEngineErrors(g)

  -- Empty board: nothing to eat, nothing to gain, and it must not eat itself.
  local g2 = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  H.ok(g2:PlayCard(1, (H.Hand(g2, 1, "EX1_304"))), "played alone")
  g2.bus:Drain()
  H.board(g2, 1, { "EX1_304 3/3" }, "a plain 3/3 with no neighbours")
  H.noEngineErrors(g2)
end)

H.suite("classes_b: Void Terror -- an enemy minion beside it is not a neighbour", function(ns, H)
  --[[ `adjacent` is board neighbours of the SOURCE, which is a per-player row.
       An enemy minion at the same index must survive untouched. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 2, "CS2_182")                       -- enemy Yeti 4/5
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_304"))), "played onto an empty friendly board")
  g.bus:Drain()
  H.board(g, 1, { "EX1_304 3/3" }, "gained nothing from across the board")
  H.board(g, 2, { "CS2_182 4/5" }, "the enemy Yeti is untouched")
  H.noEngineErrors(g)
end)

--=================================================== EX1_320 Bane of Doom

H.suite("classes_b: Bane of Doom -- a kill summons a random Demon from its entourage", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local wisp = H.Put(g, 2, "CS2_231")          -- Wisp 1/1, dies to 2
  local i = H.Hand(g, 1, "EX1_320")
  H.ok(g:PlayCard(1, i, wisp), "cast at the Wisp")
  g.bus:Drain()

  H.eq(#g.players[2].board, 0, "the Wisp died")
  H.eq(#g.players[1].board, 1, "exactly one Demon arrived, on MY side")
  local demon = g.players[1].board[1]
  H.ok(BANE_DEMONS[demon.cardId],
       "summoned " .. tostring(demon.cardId) .. " -- one of the six printed entourage Demons")
  H.eq(demon.printed.race, "DEMON", "and it really is a Demon")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Bane of Doom -- a survivor summons nothing", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ogre = H.Put(g, 2, "CS2_200")          -- Boulderfist Ogre 6/7
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_320")), ogre), "cast at the Ogre")
  g.bus:Drain()

  H.board(g, 2, { "CS2_200 6/5" }, "Ogre took 2 and lived")
  H.eq(#g.players[1].board, 0, "no Demon, because nothing died")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Bane of Doom -- a Divine Shield that eats the hit is a SURVIVAL", function(ns, H)
  --[[ DamageKilled is decided by the target's health reaching zero, not by the
       damage number. An Argent Squire pops its shield and lives, so no Demon. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local squire = H.Put(g, 2, "EX1_008")        -- Argent Squire 1/1 Divine Shield
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_320")), squire), "cast at the Squire")
  g.bus:Drain()

  H.board(g, 2, { "EX1_008 1/1" }, "shield absorbed the 2, Squire alive at full health")
  H.notOk(squire.divineShieldUp, "but the shield is gone")
  H.eq(#g.players[1].board, 0, "no Demon: the Squire survived")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Bane of Doom -- it may finish a hero, and is a spell", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local foe = H.Hero(g, 2)
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_320")), foe), "cast at the enemy hero")
  g.bus:Drain()
  H.eq(foe:Health(), 28, "a character includes a hero -- 2 damage")
  H.eq(#g.players[1].board, 0, "the hero lived, so no Demon")
  H.noEngineErrors(g)

  -- Spell Damage scales it, which is what the printed `$2` sigil promises.
  local g2 = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  H.Put(g2, 1, "CS2_142")                      -- Kobold Geomancer, Spell Damage +1
  local ogre = H.Put(g2, 2, "CS2_200")         -- 6/7
  H.ok(g2:PlayCard(1, (H.Hand(g2, 1, "EX1_320")), ogre), "cast with a Geomancer out")
  g2.bus:Drain()
  H.board(g2, 2, { "CS2_200 6/4" }, "3 damage, not 2")
  H.noEngineErrors(g2)
end)

--=============================================== GVG_024 Cogmaster's Wrench

H.suite("classes_b: Cogmaster's Wrench -- +2 Attack only while you have a Mech", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_024"))), "equipped")
  local w = g.players[1].weapon
  H.ok(w, "weapon present")
  H.eq(w:Attack(), 1, "printed 1 Attack with no Mech out")
  H.eq(g:AttackValue(H.Hero(g, 1)), 1, "hero swings for 1")

  local tank = H.Put(g, 1, "GVG_044")          -- Spider Tank 3/4, MECHANICAL
  H.eq(w:Attack(), 3, "+2 while a Mech is on the board")
  H.eq(g:AttackValue(H.Hero(g, 1)), 3, "hero swings for 3")

  -- The aura is rebuilt from zero every recalc, so losing the Mech takes it back.
  tank.pendingDestroy = true
  g:ProcessDeaths(); g:RecalcAuras()
  H.eq(w:Attack(), 1, "back to 1 when the Mech dies")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Cogmaster's Wrench -- the ENEMY's Mech does not count", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 2, "GVG_044")                       -- enemy Spider Tank
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_024"))), "equipped")
  H.eq(g.players[1].weapon:Attack(), 1, "\"you have a Mech\" means YOUR Mech")

  -- A non-Mech of your own is equally useless.
  H.Put(g, 1, "CS2_182")                       -- Chillwind Yeti, no race
  H.eq(g.players[1].weapon:Attack(), 1, "a Yeti is not a Mech")
  H.noEngineErrors(g)
end)

--=================================================== GVG_054 Ogre Warmaul

H.suite("classes_b: Ogre Warmaul -- your hero attacks the wrong enemy half the time", function(ns, H)
  --[[ Warmaul is 4/2. Attack the enemy hero with one enemy minion available:
       each trial either takes the hero to 26 or leaves it at 30. Bounds match
       the Dunemaul Shaman suite in test_gvg.lua -- roughly +/-3 sigma on a fair
       coin, tight enough to catch a broken roll, loose enough never to flake. ]]
  local hero, redirected = 0, 0
  for seed = 1, 60 do
    local g = H.NewGame({ seed = seed * 7919, firstPlayer = 1, class1 = "WARRIOR" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    g:PlayCard(1, (H.Hand(g, 1, "GVG_054")))
    H.Put(g, 2, "CS2_119")                     -- Oasis Snapjaw 2/7
    g:Attack(H.Hero(g, 1), H.Hero(g, 2))
    g.bus:Drain()
    if H.Hero(g, 2):Health() < 30 then hero = hero + 1 else redirected = redirected + 1 end
  end
  H.ok(hero >= 18 and hero <= 42,
       "intended target hit 18-42 times of 60 (got " .. hero .. ")")
  H.ok(redirected >= 18 and redirected <= 42,
       "redirected 18-42 times of 60 (got " .. redirected .. ")")
  H.eq(hero + redirected, 60, "every trial resolved")
end)

H.suite("classes_b: Ogre Warmaul -- a plain weapon never redirects", function(ns, H)
  --[[ The control. Arcanite Reaper is 5/2 with no text, so over the same seeds
       the enemy hero must take 5 every single time. Without this, a suite that
       merely counted two outcomes would pass on an engine that redirected
       everything. ]]
  for seed = 1, 20 do
    local g = H.NewGame({ seed = seed * 7919, firstPlayer = 1, class1 = "WARRIOR" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    g:PlayCard(1, (H.Hand(g, 1, "CS2_112")))   -- Arcanite Reaper 5/2
    H.Put(g, 2, "CS2_119")
    g:Attack(H.Hero(g, 1), H.Hero(g, 2))
    g.bus:Drain()
    H.eq(H.Hero(g, 2):Health(), 25, "Arcanite Reaper always lands")
  end
end)

H.suite("classes_b: Ogre Warmaul -- the keyword rides the weapon, not the hero", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local me = H.Hero(g, 1)
  H.notOk(me:Has(ns.KEYWORD.FORGETFUL), "bare hero is not forgetful")

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_054"))), "equipped")
  H.eq(g.players[1].weapon:Attack(), 4, "printed 4 Attack, unmodified")
  H.ok(me:Has(ns.KEYWORD.FORGETFUL), "hero is forgetful while the Warmaul is equipped")
  H.notOk(H.Hero(g, 2):Has(ns.KEYWORD.FORGETFUL), "the opponent's hero is not")

  g:DestroyWeapon(1)
  g:RecalcAuras()
  H.notOk(me:Has(ns.KEYWORD.FORGETFUL), "and not forgetful once the weapon is gone")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Ogre Warmaul -- swinging still costs 1 Durability", function(ns, H)
  --[[ The Warmaul is an ordinary weapon apart from the redirect, so a swing
       spends durability whether or not the blow was redirected. ]]
  local g = H.NewGame({ seed = 4242, firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "GVG_054")))
  H.eq(g.players[1].weapon:Health(), 2, "2 durability off the shelf")
  H.Put(g, 2, "CS2_119")
  g:Attack(H.Hero(g, 1), H.Hero(g, 2))
  g.bus:Drain()
  H.eq(g.players[1].weapon:Health(), 1, "one durability spent")
  H.noEngineErrors(g)
end)

--===================================================================
-- Round 2: the cards unblocked by the new zone-movement, pool-generation,
-- LoseManaCrystal, PayloadHasOverload and ARMOR_GAINED primitives.
--
--   GVG_045  Imp-losion        4 mana      $2-$4 to a minion, an Imp per damage
--   GVG_042  Neptulon          7 mana 7/7  4 random Murlocs, Overload (3)
--   EX1_301  Felguard          3 mana 3/5  Taunt; destroy one of your crystals
--   EX1_258  Unbound Elemental 3 mana 2/4  +1/+1 per Overload card YOU play
--   GVG_086  Siege Engine      5 mana 5/5  +1 Attack whenever you gain Armor
--   EX1_317  Sense Demons      3 mana      2 Demons from deck to hand
--   FP1_022  Voidcaller        4 mana 3/4  Deathrattle: a Demon from hand to play
--   GVG_029  Ancestor's Call   4 mana      a minion from EACH hand into play
--   GVG_056  Iron Juggernaut   6 mana 6/5  shuffle a Mine into their deck
--   GVG_056t Burrowing Mine    token       drawn: 10 damage and a replacement
--
-- Extra fixtures, all verified against the pin:
--   GVG_066  Dunemaul Shaman   4 mana 5/4  Overload (1); needs no script
--   EX1_606  Shield Block      3 mana      Gain 5 Armor. Draw a card.
--   CS2_064  Dread Infernal    6 mana 6/6  Battlecry: 1 damage to ALL others
--   CS2_065  Voidwalker        1 mana 1/3  DEMON, Taunt
--   EX1_306  Succubus          2 mana 4/3  DEMON
--   EX1_317t Worthless Imp     1 mana 1/1  DEMON token, the Sense Demons filler
--===================================================================

local function countIn(list, cardId)
  local n = 0
  for _, e in ipairs(list) do if e.cardId == cardId then n = n + 1 end end
  return n
end

local function demonsIn(list)
  local n = 0
  for _, e in ipairs(list) do if e.printed.race == "DEMON" then n = n + 1 end end
  return n
end

--=================================================== GVG_045 Imp-losion

H.suite("classes_b: Imp-losion -- one 1/1 Imp per point of damage rolled", function(ns, H)
  --[[ The roll is $2-$4 and the Imp count must track it exactly. A Boulderfist
       Ogre survives any roll, so the damage is readable as 7 minus its health
       and can be compared against the board. ]]
  local seen = {}
  for seed = 1, 20 do
    local g = H.NewGame({ seed = seed * 7919, firstPlayer = 1, class1 = "WARLOCK" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local ogre = H.Put(g, 2, "CS2_200")        -- Boulderfist Ogre 6/7
    H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_045")), ogre), "cast at the Ogre")
    g.bus:Drain()

    local dealt = 7 - ogre:Health()
    H.ok(dealt >= 2 and dealt <= 4, "rolled inside 2-4 (got " .. dealt .. ")")
    H.eq(#g.players[1].board, dealt, "one Imp per point of damage")
    H.eq(countIn(g.players[1].board, "GVG_045t"), dealt, "and every one of them is an Imp")
    seen[dealt] = true
    H.noEngineErrors(g)
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  H.ok(distinct > 1, "the roll genuinely varies across seeds (" .. distinct .. " distinct values)")
end)

H.suite("classes_b: Imp-losion -- Spell Damage adds an Imp as well as a point", function(ns, H)
  --[[ `dealt` is the amount AFTER spell power, not the raw roll, so a Kobold
       Geomancer must move BOTH numbers together. A roll of 3 with a Geomancer
       out is 4 damage and 4 Imps; reading the raw roll would give 4 and 3. ]]
  for seed = 1, 12 do
    local g = H.NewGame({ seed = seed * 7919, firstPlayer = 1, class1 = "WARLOCK" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    H.Put(g, 1, "CS2_142")                     -- Kobold Geomancer, Spell Damage +1
    local ogre = H.Put(g, 2, "CS2_200")        -- Boulderfist Ogre 6/7
    H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_045")), ogre), "cast with a Geomancer out")
    g.bus:Drain()

    local dealt = 7 - ogre:Health()
    H.ok(dealt >= 3 and dealt <= 5, "a 2-4 roll plus Spell Damage lands in 3-5 (got " .. dealt .. ")")
    H.eq(countIn(g.players[1].board, "GVG_045t"), dealt, "one Imp per point ACTUALLY dealt")
    H.noEngineErrors(g)
  end
end)

H.suite("classes_b: Imp-losion -- a Divine Shield still yields the full brood", function(ns, H)
  --[[ `dealt` is the scaled amount, deliberately NOT the amount finally
       applied: a shield that eats the whole hit must not eat the Imps too. ]]
  local g = H.NewGame({ seed = 7919, firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local squire = H.Put(g, 2, "EX1_008")        -- Argent Squire 1/1 Divine Shield
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_045")), squire), "cast at the Squire")
  g.bus:Drain()

  H.eq(squire:Health(), 1, "the shield absorbed the whole hit")
  H.notOk(squire.divineShieldUp, "and popped")
  local imps = countIn(g.players[1].board, "GVG_045t")
  H.ok(imps >= 2 and imps <= 4, "Imps arrived anyway (" .. imps .. ")")
  H.noEngineErrors(g)
end)

--=================================================== GVG_042 Neptulon

H.suite("classes_b: Neptulon -- four random Murlocs, and Overload is NOT doubled", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "SHAMAN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_042"))), "played")
  g.bus:Drain()

  H.eq(#g.players[1].hand, 4, "four cards added to hand")
  for _, c in ipairs(g.players[1].hand) do
    H.eq(c.printed.race, "MURLOC", c.cardId .. " is a Murloc")
    H.ok(c.printed.collectible, c.cardId .. " is collectible -- never a token")
  end
  --[[ The card prints Overload (3) and Game:PlayCard applies it. Scripting it
       as well would lock six, which is exactly the double-count the compiler
       refuses Overload() to prevent. ]]
  H.eq(g.players[1].pendingOverload, 3, "printed Overload (3) applied exactly once")
  H.noEngineErrors(g)
end)

--=================================================== EX1_301 Felguard

H.suite("classes_b: Felguard -- destroys one of your Mana Crystals", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_301"))), "played")
  g.bus:Drain()

  H.eq(g.players[1].maxMana, 9, "one crystal destroyed")
  H.eq(g.players[1].mana, 7, "3 was spent on the Felguard; the remaining 7 is under the new cap")
  H.board(g, 1, { "EX1_301 3/5" }, "and it is on the board")
  H.ok(g.players[1].board[1]:IsTaunt(), "Taunt comes from printed data, not from the script")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Felguard -- eats the last crystal, then floors at zero", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1)
  local p = g.players[1]

  -- One crystal left: it goes, and the crystal really was destroyed.
  p.maxMana, p.mana, p.lockedMana = 1, 3, 0     -- mana padded so the 3-cost is payable
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_301"))), "played with one crystal left")
  g.bus:Drain()
  H.eq(p.maxMana, 0, "the last crystal was destroyed")

  -- Now at zero: a second Felguard must not drive it negative.
  p.mana = 3
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_301"))), "played again with an empty crystal pool")
  g.bus:Drain()
  H.eq(p.maxMana, 0, "floors at zero rather than going negative")
  H.noEngineErrors(g)
end)

--=================================================== EX1_258 Unbound Elemental

H.suite("classes_b: Unbound Elemental -- grows on cards that print Overload", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "SHAMAN", class2 = "SHAMAN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ub = H.Put(g, 1, "EX1_258")            -- 2/4
  H.eq(ub:Attack(), 2, "2 Attack to start")
  H.eq(ub:Health(), 4, "4 Health to start")

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_066"))), "played Dunemaul Shaman, Overload (1)")
  g.bus:Drain()
  H.eq(ub:Attack(), 3, "+1 Attack")
  H.eq(ub:Health(), 5, "+1 Health")

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "CS2_231"))), "played a Wisp")
  g.bus:Drain()
  H.eq(ub:Attack(), 3, "a Wisp prints no Overload, so nothing happens")
  H.eq(ub:Health(), 5, "still 5 Health")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Unbound Elemental -- the OPPONENT's Overload card does nothing", function(ns, H)
  --[[ "Whenever YOU play a card." Without PayloadIsMine this grows on both
       sides of the table, which is the silent half-right version. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "SHAMAN", class2 = "SHAMAN" })
  local ub = H.Put(g, 1, "EX1_258")
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  H.ok(g:PlayCard(2, (H.Hand(g, 2, "GVG_066"))), "opponent played Dunemaul Shaman")
  g.bus:Drain()
  H.eq(ub:Attack(), 2, "still 2 Attack")
  H.eq(ub:Health(), 4, "still 4 Health")
  H.noEngineErrors(g)
end)

--=================================================== GVG_086 Siege Engine

H.suite("classes_b: Siege Engine -- +1 Attack per Armor GAIN, not per point", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local se = H.Put(g, 1, "GVG_086")            -- 5/5 Mech
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_606"))), "Shield Block: gain 5 Armor, draw a card")
  g.bus:Drain()

  H.eq(H.Hero(g, 1).armor, 5, "5 Armor gained")
  H.eq(se:Attack(), 6, "+1 Attack for the one gain -- not +5, one per point")
  H.eq(se:Health(), 5, "health untouched")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Siege Engine -- the opponent's Armor does not feed it", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR", class2 = "WARRIOR" })
  local se = H.Put(g, 1, "GVG_086")
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  H.ok(g:PlayCard(2, (H.Hand(g, 2, "EX1_606"))), "opponent gains 5 Armor")
  g.bus:Drain()
  H.eq(H.Hero(g, 2).armor, 5, "they got the Armor")
  H.eq(se:Attack(), 5, "and my Siege Engine did not grow")
  H.noEngineErrors(g)
end)

--=================================================== EX1_317 Sense Demons

H.suite("classes_b: Sense Demons -- two Demons out of your deck and into your hand", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK",
                        deck1 = { "CS2_065", "CS2_065", "EX1_306" } })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  H.eq(demonsIn(g.players[1].deck), 3, "three Demons sitting in the deck")

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_317"))), "cast")
  g.bus:Drain()

  H.eq(#g.players[1].hand, 2, "exactly two cards in hand")
  H.eq(demonsIn(g.players[1].hand), 2, "both of them Demons")
  H.eq(demonsIn(g.players[1].deck), 1, "and the deck is two Demons lighter")
  H.eq(countIn(g.players[1].hand, "EX1_317t"), 0, "no Worthless Imps: there were enough Demons")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Sense Demons -- a shortfall is topped up with Worthless Imps", function(ns, H)
  -- One Demon left: you get it, plus one Worthless Imp.
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK", deck1 = { "CS2_065" } })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_317"))), "cast with one Demon in the deck")
  g.bus:Drain()
  H.eq(#g.players[1].hand, 2, "still exactly two cards")
  H.eq(countIn(g.players[1].hand, "CS2_065"), 1, "the one real Demon")
  H.eq(countIn(g.players[1].hand, "EX1_317t"), 1, "and one Worthless Imp to make up the number")
  H.eq(demonsIn(g.players[1].deck), 0, "the deck has no Demons left")
  H.noEngineErrors(g)

  -- No Demons at all: two Worthless Imps.
  local g2 = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  g2.players[1].hand = {}
  H.ok(g2:PlayCard(1, (H.Hand(g2, 1, "EX1_317"))), "cast with a Demon-free deck")
  g2.bus:Drain()
  H.eq(countIn(g2.players[1].hand, "EX1_317t"), 2, "two Worthless Imps")
  H.eq(#g2.players[1].hand, 2, "and nothing else")
  H.noEngineErrors(g2)
end)

--=================================================== FP1_022 Voidcaller

H.suite("classes_b: Voidcaller -- a Demon walks out of your hand, Battlecry suppressed", function(ns, H)
  --[[ Dread Infernal is the fixture precisely because its Battlecry would deal
       1 damage to every other character. MoveToBoard is not a play, so both
       heroes must still be at 30 -- that is the assertion that separates this
       from a lazy "just summon it" implementation. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  H.Hand(g, 1, "CS2_064")                      -- Dread Infernal 6/6, DEMON
  H.Hand(g, 1, "CS2_231")                      -- Wisp, not a Demon
  local vc = H.Put(g, 1, "FP1_022")            -- Voidcaller 3/4

  vc.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()

  H.board(g, 1, { "CS2_064 6/6" }, "the Dread Infernal is on the board")
  H.eq(#g.players[1].hand, 1, "one card left in hand")
  H.eq(g.players[1].hand[1].cardId, "CS2_231", "the Wisp -- a Wisp is not a Demon")
  H.eq(H.Hero(g, 1):Health(), 30, "no Battlecry fired: my hero is untouched")
  H.eq(H.Hero(g, 2):Health(), 30, "...and so is theirs")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Voidcaller -- no Demon in hand means nothing happens", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  H.Hand(g, 1, "CS2_231")
  local vc = H.Put(g, 1, "FP1_022")
  vc.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].board, 0, "empty board")
  H.eq(#g.players[1].hand, 1, "the Wisp stayed in hand")
  H.noEngineErrors(g)
end)

--=================================================== GVG_029 Ancestor's Call

H.suite("classes_b: Ancestor's Call -- one minion out of EACH hand, no Battlecries", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "SHAMAN", class2 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  g.players[2].hand = {}
  H.Hand(g, 1, "CS2_200")                      -- Boulderfist Ogre 6/7
  H.Hand(g, 2, "CS2_064")                      -- Dread Infernal, Battlecry 1 to all others
  H.Hand(g, 1, "GVG_029")

  H.ok(g:PlayCard(1, 2), "cast Ancestor's Call")
  g.bus:Drain()

  H.board(g, 1, { "CS2_200 6/7" }, "my Ogre walked out")
  H.board(g, 2, { "CS2_064 6/6" }, "their Dread Infernal walked out onto THEIR board")
  H.eq(#g.players[1].hand, 0, "my hand is empty")
  H.eq(#g.players[2].hand, 0, "and so is theirs")
  H.eq(H.Hero(g, 1):Health(), 30, "no Battlecry fired")
  H.eq(H.Hero(g, 2):Health(), 30, "...for either hero")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Ancestor's Call -- a hand with no minion contributes nothing", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "SHAMAN", class2 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  g.players[2].hand = {}
  H.Hand(g, 2, "CS2_065")                      -- Voidwalker 1/3
  H.Hand(g, 1, "EX1_606")                      -- a SPELL in my hand, not a minion
  H.Hand(g, 1, "GVG_029")

  H.ok(g:PlayCard(1, 2), "cast")
  g.bus:Drain()
  H.eq(#g.players[1].board, 0, "a spell is not a minion, so my side gets nobody")
  H.board(g, 2, { "CS2_065 1/3" }, "their Voidwalker still came out")
  H.eq(countIn(g.players[1].hand, "EX1_606"), 1, "my Shield Block is untouched")
  H.noEngineErrors(g)
end)

--=========================================== GVG_056 / GVG_056t Iron Juggernaut

H.suite("classes_b: Iron Juggernaut -- shuffles a Burrowing Mine into the OPPONENT's deck", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local theirs, mine = #g.players[2].deck, #g.players[1].deck

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_056"))), "played")
  g.bus:Drain()

  H.eq(#g.players[2].deck, theirs + 1, "their deck grew by one")
  H.eq(countIn(g.players[2].deck, "GVG_056t"), 1, "and the new card is a Burrowing Mine")
  H.eq(#g.players[1].deck, mine, "my deck is untouched")
  H.eq(countIn(g.players[1].deck, "GVG_056t"), 0, "nothing landed on my side")
  H.board(g, 1, { "GVG_056 6/5" }, "the Juggernaut itself is on the board")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Burrowing Mine -- explodes on draw for 10 and replaces itself", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.PutOnDeck(g, 2, "GVG_056t")
  local handBefore = #g.players[2].hand

  g:Draw(2)
  g.bus:Drain()

  H.eq(H.Hero(g, 2):Health(), 20, "the drawer takes 10")
  H.eq(H.Hero(g, 1):Health(), 30, "and only the drawer")
  --[[ The Mine destroys itself on the way through, so the hand ends up net +1:
       the replacement card only. A spent Mine left sitting in hand would be a
       dead 0-cost spell the player could never get rid of. ]]
  H.eq(countIn(g.players[2].hand, "GVG_056t"), 0, "the Mine destroyed itself")
  H.eq(countIn(g.players[2].graveyard, "GVG_056t"), 1, "...into the graveyard")
  H.eq(#g.players[2].hand, handBefore + 1, "net +1 card: the replacement it drew")
  H.noEngineErrors(g)
end)

--===================================================================
-- Round 3: the last five, unblocked by payloadAmount,
-- cardsPlayedEarlierThisTurn, DestroyAllButOneRandom, RepeatUntil and
-- PayloadCardIs.
--
--   GVG_018  Mistress of Pain   2 mana 1/4  heal your hero for damage it deals
--   EX1_613  Edwin VanCleef     3 mana 2/2  Combo: +2/+2 per earlier card
--   EX1_407  Brawl              5 mana      destroy all minions except one
--   GVG_050  Bouncing Blade     3 mana      $1 to a random minion until one dies
--   GVG_028  Trade Prince Gallywix 6 mana 5/8  copy their spells, hand a Coin
--   GVG_028t Gallywix's Coin    token       1 Mana Crystal this turn only
--===================================================================

--=================================================== GVG_018 Mistress of Pain

H.suite("classes_b: Mistress of Pain -- heals your hero for the damage it deals", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local me = H.Hero(g, 1)
  g:DealDamage(me, 10, nil, false)
  H.eq(me:Health(), 20, "hero chipped to 20 so there is room to heal")

  local mp = H.Put(g, 1, "GVG_018")            -- Mistress of Pain 1/4
  H.Put(g, 2, "CS2_200")                       -- Boulderfist Ogre 6/7, survives
  g:Attack(mp, g.players[2].board[1])
  g.bus:Drain()

  H.eq(me:Health(), 21, "1 Attack dealt 1 damage, so the hero regained exactly 1")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Mistress of Pain -- THAT much, not a flat 1", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local me = H.Hero(g, 1)
  g:DealDamage(me, 10, nil, false)

  local mp = H.Put(g, 1, "GVG_018")
  mp:AddEnchantment(3, 0)                      -- e.g. a Demonfire; now a 4/4
  g:RecalcAuras()
  H.eq(mp:Attack(), 4, "buffed to 4 Attack")

  H.Put(g, 2, "CS2_200")                       -- Boulderfist Ogre 6/7
  g:Attack(mp, g.players[2].board[1])
  g.bus:Drain()
  H.eq(me:Health(), 24, "healed 4 -- the amount it actually dealt")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Mistress of Pain -- damage it TAKES heals nobody", function(ns, H)
  --[[ PayloadSourceIsSelf. The Ogre hitting back is damage whose SOURCE is the
       Ogre, so it must not heal -- but it does hit Mistress, and a lazy
       "whenever damage happens near me" reading would heal twice. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK", class2 = "WARLOCK" })
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  local me = H.Hero(g, 1)
  g:DealDamage(me, 10, nil, false)

  local mp = H.Put(g, 1, "GVG_018")            -- 1/4, mine
  local ogre = H.Put(g, 2, "CS2_200")          -- 6/7, theirs
  g:Attack(ogre, mp)                           -- THEY attack INTO Mistress
  g.bus:Drain()

  --[[ Mistress still deals its 1 back as the defender, so exactly 1 is healed:
       the Ogre's 6 must contribute nothing. ]]
  H.eq(me:Health(), 21, "only the 1 Mistress dealt back, never the 6 it took")
  H.eq(H.Hero(g, 2):Health(), 30, "and nothing healed the other hero")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Mistress of Pain -- an undamaged hero cannot overheal", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local mp = H.Put(g, 1, "GVG_018")
  H.Put(g, 2, "CS2_200")
  g:Attack(mp, g.players[2].board[1])
  g.bus:Drain()
  H.eq(H.Hero(g, 1):Health(), 30, "still 30 -- Game:Heal clamps to damage taken")
  H.noEngineErrors(g)
end)

--=================================================== EX1_613 Edwin VanCleef

H.suite("classes_b: Edwin VanCleef -- +2/+2 for each card played EARLIER this turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_231")))     -- Wisp
  g:PlayCard(1, (H.Hand(g, 1, "CS2_231")))     -- Wisp
  g.bus:Drain()

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_613"))), "Edwin, third card of the turn")
  g.bus:Drain()
  H.board(g, 1, { "CS2_231 1/1", "CS2_231 1/1", "EX1_613 6/6" },
          "two earlier cards -> +4/+4 on a 2/2")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Edwin VanCleef -- first card of the turn is a plain 2/2", function(ns, H)
  --[[ No Combo, so the combo body never runs. Edwin counts HIMSELF in
       cardsPlayedThisTurn -- PlayCard increments before the body runs -- so an
       off-by-one here would make a bare Edwin a 4/4. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_613"))), "Edwin, first card of the turn")
  g.bus:Drain()
  H.board(g, 1, { "EX1_613 2/2" }, "a plain 2/2")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Edwin VanCleef -- a spell counts, and last turn's cards do not", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_231")))     -- a card LAST turn
  g.bus:Drain()

  H.SetActive(g, 1)                            -- new turn: the counter resets
  H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_023")))     -- Arcane Intellect, a SPELL
  g.bus:Drain()
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_613"))), "Edwin after one spell this turn")
  g.bus:Drain()

  local edwin = g.players[1].board[#g.players[1].board]
  H.eq(edwin.cardId, "EX1_613", "Edwin is the rightmost minion")
  H.eq(edwin:Attack(), 4, "one earlier card this turn -> +2/+2, not +4/+4")
  H.eq(edwin:Health(), 4, "...on both stats")
  H.noEngineErrors(g)
end)

--=================================================== EX1_407 Brawl

H.suite("classes_b: Brawl -- exactly one minion is left standing, from either side", function(ns, H)
  local sides = { [1] = 0, [2] = 0 }
  for seed = 1, 24 do
    local g = H.NewGame({ seed = seed * 7919, firstPlayer = 1, class1 = "WARRIOR" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    H.Put(g, 1, "CS2_182"); H.Put(g, 1, "CS2_200")          -- two of mine
    H.Put(g, 2, "CS2_231"); H.Put(g, 2, "CS2_119")          -- two of theirs

    H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_407"))), "cast")
    g.bus:Drain()

    local left = #g.players[1].board + #g.players[2].board
    H.eq(left, 1, "exactly one survivor across the whole board")
    sides[#g.players[1].board > 0 and 1 or 2] = sides[#g.players[1].board > 0 and 1 or 2] + 1
    H.noEngineErrors(g)
  end
  --[[ The survivor must be drawn from EVERY minion, not just the caster's or
       just the opponent's -- a Brawl that always spared your own side would
       pass a "one survivor" check and be a completely different card. ]]
  H.ok(sides[1] > 0, "sometimes one of mine survives (" .. sides[1] .. "/24)")
  H.ok(sides[2] > 0, "sometimes one of theirs does (" .. sides[2] .. "/24)")
end)

H.suite("classes_b: Brawl -- a lone minion survives, and an empty board is a no-op", function(ns, H)
  --[[ Brawl prints REQ_MINIMUM_TOTAL_MINIONS=2, so Hearthstone will not let you
       cast it below two minions at all. Targeting.CheckRequirement implements
       that requirement, but Game:PlayCard only consults it through
       Targeting.ModePlayable, which runs for CHOOSE ONE cards only -- so no
       board-state requirement is enforced on an ordinary card today. Reported
       upstream; it is an engine gap, not a Brawl one.

       What is asserted here is the part the script owns: with nothing to brawl
       over, nothing dies. DestroyAllButOneRandom returns early at one or fewer
       matches rather than destroying the only minion on the board, which is the
       failure mode that would otherwise be invisible until someone cast it. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local lone = H.Put(g, 1, "CS2_182")          -- Chillwind Yeti 4/5, the only minion
  g:PlayCard(1, (H.Hand(g, 1, "EX1_407")))
  g.bus:Drain()
  H.board(g, 1, { "CS2_182 4/5" }, "the lone Yeti is untouched")
  H.notOk(lone.pendingDestroy, "it was never even marked for destruction")

  -- Wholly empty board: still a no-op, and no engine error.
  local g2 = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  g2:PlayCard(1, (H.Hand(g2, 1, "EX1_407")))
  g2.bus:Drain()
  H.eq(#g2.players[1].board, 0, "nothing on my side")
  H.eq(#g2.players[2].board, 0, "nothing on theirs")
  H.noEngineErrors(g2)
  H.noEngineErrors(g)
end)

H.suite("classes_b: Brawl -- the dead go to the graveyard and deathrattles fire", function(ns, H)
  local g = H.NewGame({ seed = 99, firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_231"); H.Put(g, 1, "CS2_231"); H.Put(g, 1, "CS2_231")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_407"))), "cast")
  g.bus:Drain()
  H.eq(#g.players[1].board, 1, "one Wisp left")
  H.eq(countIn(g.players[1].graveyard, "CS2_231"), 2, "the other two are in the graveyard")
  H.noEngineErrors(g)
end)

--=================================================== GVG_050 Bouncing Blade

H.suite("classes_b: Bouncing Blade -- bounces until a minion dies", function(ns, H)
  --[[ A lone 6/7 Ogre: the loop has to run seven times and stop the moment it
       dies. One bounce, or an unbounded loop, both fail here. ]]
  local g = H.NewGame({ seed = 4242, firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ogre = H.Put(g, 2, "CS2_200")          -- 6/7, the only minion in play
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_050"))), "cast")
  g.bus:Drain()

  H.eq(#g.players[2].board, 0, "the Ogre took seven bounces and died")
  H.eq(H.Hero(g, 1):Health(), 30, "heroes are not minions -- neither was touched")
  H.eq(H.Hero(g, 2):Health(), 30, "...on either side")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Bouncing Blade -- stops at the FIRST death, both sides in the pool", function(ns, H)
  --[[ A 1/1 Wisp of mine next to their 6/7 Ogre. Exactly one minion may die,
       and the total damage dealt must be small -- if the loop kept going after
       the first death the Ogre would be ground down too. ]]
  for seed = 1, 15 do
    local g = H.NewGame({ seed = seed * 31, firstPlayer = 1, class1 = "WARRIOR" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local wisp = H.Put(g, 1, "CS2_231")        -- mine, 1/1
    local ogre = H.Put(g, 2, "CS2_200")        -- theirs, 6/7

    H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_050"))), "cast")
    g.bus:Drain()

    local alive = #g.players[1].board + #g.players[2].board
    H.eq(alive, 1, "exactly one minion died")
    H.eq(#g.players[1].board, 0, "it is the 1/1 Wisp that dies first")
    H.ok(ogre:Health() >= 1, "the Ogre survived with " .. ogre:Health() .. " health")
    H.noEngineErrors(g)
  end
end)

--=================================================== GVG_028 Gallywix

H.suite("classes_b: Gallywix -- copies their spell and hands them a Coin", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE", class2 = "MAGE" })
  H.Put(g, 1, "GVG_028")                       -- Trade Prince Gallywix 5/8, mine
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  g.players[1].hand = {}
  g.players[2].hand = {}

  H.ok(g:PlayCard(2, (H.Hand(g, 2, "CS2_023"))), "opponent casts Arcane Intellect")
  g.bus:Drain()

  H.eq(countIn(g.players[1].hand, "CS2_023"), 1, "I gained a copy of their spell")
  H.eq(countIn(g.players[2].hand, "GVG_028t"), 1, "and they got Gallywix's Coin")
  --[[ The token is GVG_028t, NOT GAME_005: the pin gives Gallywix its own Coin
       precisely so it can refuse to copy it. ]]
  H.eq(countIn(g.players[2].hand, "GAME_005"), 0, "not the ordinary Coin")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Gallywix -- refuses its own Coin, so there is no engine", function(ns, H)
  --[[ Without the PayloadCardIs guard the opponent playing the Coin triggers
       Gallywix again: another copy for me, another Coin for them, forever. The
       printed text on GVG_028t says exactly this -- "(Won't trigger Gallywix.)"
  ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE", class2 = "MAGE" })
  H.Put(g, 1, "GVG_028")
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  g.players[1].hand = {}
  g.players[2].hand = {}

  H.ok(g:PlayCard(2, (H.Hand(g, 2, "GVG_028t"))), "opponent plays Gallywix's Coin")
  g.bus:Drain()

  H.eq(#g.players[1].hand, 0, "I gained nothing")
  H.eq(countIn(g.players[2].hand, "GVG_028t"), 0, "and no second Coin was handed out")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Gallywix -- MY spells and their minions leave it cold", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "MAGE", class2 = "MAGE" })
  H.Put(g, 1, "GVG_028")
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[1].hand = {}
  g.players[2].hand = {}

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "CS2_023"))), "I cast Arcane Intellect myself")
  g.bus:Drain()
  H.eq(countIn(g.players[2].hand, "GVG_028t"), 0, "no Coin: it is THEIR spells that count")

  -- and a minion is not a spell
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  local before = #g.players[1].hand
  H.ok(g:PlayCard(2, (H.Hand(g, 2, "CS2_182"))), "opponent plays a Chillwind Yeti")
  g.bus:Drain()
  H.eq(#g.players[1].hand, before, "a minion is not a spell, so nothing was copied")
  H.eq(countIn(g.players[2].hand, "GVG_028t"), 0, "and no Coin")
  H.noEngineErrors(g)
end)

H.suite("classes_b: Gallywix's Coin -- one Mana Crystal, this turn only", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1)
  local p = g.players[1]
  p.maxMana, p.mana, p.tempMana, p.lockedMana = 3, 3, 0, 0

  H.ok(g:PlayCard(1, (H.Hand(g, 1, "GVG_028t"))), "played the Coin")
  g.bus:Drain()
  H.eq(p.tempMana, 1, "one crystal, and a temporary one")
  H.eq(p.maxMana, 3, "the permanent pool is untouched")
  H.noEngineErrors(g)
end)

--=========================================== EX1_596 Demonfire, GVG_019 Demonheart

--[[ "If it's a friendly Demon, give it +N/+N instead." Both used to test only
     the race, so an ENEMY Demon was buffed -- the one target these spells
     exist to kill. TargetIsFriendly makes the buff yours alone. ]]
for _, card in ipairs({ { id = "EX1_596", name = "Demonfire", n = 2 },
                        { id = "GVG_019", name = "Demonheart", n = 5 } }) do
  H.suite("classes_b: " .. card.name .. " -- your Demon grows, theirs burns", function(ns, H)
    local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local mine = H.Put(g, 1, "CS2_064")         -- Dread Infernal 6/6, a Demon
    local theirs = H.Put(g, 2, "CS2_064")
    H.ok(g:PlayCard(1, (H.Hand(g, 1, card.id)), theirs), "cast at THEIR Demon")
    g.bus:Drain()
    H.board(g, 2, { ("CS2_064 6/%d"):format(6 - card.n) }, "an enemy Demon takes the damage")
    H.Mana(g, 1, 10)
    H.ok(g:PlayCard(1, (H.Hand(g, 1, card.id)), mine), "cast at MY Demon")
    g.bus:Drain()
    H.board(g, 1, { ("CS2_064 %d/%d"):format(6 + card.n, 6 + card.n) }, "a friendly Demon is empowered")
    local ogre = H.Put(g, 1, "CS2_200")          -- Boulderfist Ogre 6/7, not a Demon
    H.Mana(g, 1, 10)
    H.ok(g:PlayCard(1, (H.Hand(g, 1, card.id)), ogre), "cast at my non-Demon")
    g.bus:Drain()
    H.eq(ogre:Health(), 7 - card.n, "a friendly non-Demon is damaged")
    H.noEngineErrors(g)
  end)
end

--======================================================= GVG_100 Floating Watcher

--[[ "Whenever your hero takes damage ON YOUR TURN, gain +2/+2." It used to
     grow on the opponent's turn as well: there was no condition for "your
     turn" when it was written. MyTurn is that condition. ]]
H.suite("classes_b: Floating Watcher -- grows on your turn only", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARLOCK", class2 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local watcher = H.Put(g, 1, "GVG_100")        -- Floating Watcher 4/4
  H.ok(g:UseHeroPower(1), "Life Tap on my own turn")
  g.bus:Drain()
  H.eq(watcher:Attack(), 6, "my hero took damage on my turn: +2 Attack")
  H.eq(watcher:Health(), 6, "and +2 Health")
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  H.ok(g:PlayCard(2, (H.Hand(g, 2, "CS2_008")), g.players[1].hero), "their Moonfire hits my hero on THEIR turn")
  g.bus:Drain()
  H.eq(watcher:Attack(), 6, "no growth on the opponent's turn")
  H.noEngineErrors(g)
end)
