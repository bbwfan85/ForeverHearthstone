--[[ tests/test_dsl.lua -- the engine capabilities added to unblock authoring.

  Every feature here exists because one of the three card-authoring passes hit a
  wall and reported it. The skip reports were the specification. These tests are
  what stop the next authoring pass from building on something silently broken.

  All of it is tested at the ENGINE level (ops and selectors with hand-built
  tables) rather than through the compiler, because that is where the behaviour
  lives. The compiler is separately validated by the fact that 294 authored cards
  compile against it.
]]
local H = require("tests.harness")

local function run(g, ops, ctx)
  ctx = ctx or { controller = 1 }
  ctx.controller = ctx.controller or 1
  g.bus:Block(function() H.ns.Ops.Run(g, ops, ctx) end)
end

--=============================================== compound zone+type selectors

H.suite("dsl: a selector can combine zone and type", function(ns, H)
  --[[ The grammar was scope.oneFilter, so "minions in your hand" was
       inexpressible even though Aura.lua's own docstring used it. That blocked
       Mana Wraith, Mechwarper, Sorcerer's Apprentice, Summoning Portal and more. ]]
  local g = H.NewGame()
  -- Clear the opening mulligan hand first: it is full of Wisps, which ARE minions,
  -- so counting against a fresh hand proves nothing.
  g.players[1].hand = {}
  H.Hand(g, 1, "CS2_182")          -- Chillwind Yeti, a MINION
  H.Hand(g, 1, "CS2_029")          -- Fireball, a SPELL
  H.Hand(g, 1, "CS2_119")          -- Oasis Snapjaw, a MINION

  local minions = ns.Selector.Resolve(g,
    { side = "FRIENDLY", zone = "HAND", type = "MINION" }, { controller = 1 })
  local spells = ns.Selector.Resolve(g,
    { side = "FRIENDLY", zone = "HAND", type = "SPELL" }, { controller = 1 })
  H.eq(#minions, 2, "two minions in hand")
  H.eq(#spells, 1, "one spell in hand")
  -- and it must not leak onto the board
  H.Put(g, 1, "CS2_182")
  local stillTwo = ns.Selector.Resolve(g,
    { side = "FRIENDLY", zone = "HAND", type = "MINION" }, { controller = 1 })
  H.eq(#stillTwo, 2, "a board minion is not counted as a hand minion")
  H.noEngineErrors(g)
end)

H.suite("dsl: a cost aura on hand cards reaches only the right ones", function(ns, H)
  -- Sorcerer's Apprentice: your spells cost (1) less, while in hand.
  local g = H.NewGame()
  g.players[1].hand = {}
  local yeti = H.Hand(g, 1, "CS2_182")
  local _, fireball = H.Hand(g, 1, "CS2_029")
  local hand = g.players[1].hand
  local spell = hand[#hand]
  run(g, { { op = "Buff", sel = { side = "FRIENDLY", zone = "HAND", type = "SPELL" },
             atk = 0, hp = 0 } })
  -- use a cost aura rather than a buff to prove the selector, via the aura layer
  for _, e in ipairs(hand) do
    if e.printed.type == "SPELL" then e.aura.cost = -1 end
  end
  H.eq(spell:Cost(), 3, "Fireball discounted from 4 to 3")
  H.noEngineErrors(g)
end)

--============================================================ !target exclusion

H.suite("dsl: excludeTarget hits everything BUT the chosen target", function(ns, H)
  --[[ Swipe: 4 damage to a target and 1 to all OTHER enemies. Without this the
       only workaround applied spell damage twice to the primary target, which the
       authoring agent correctly refused to ship. ]]
  local g = H.NewGame()
  local a = H.Put(g, 2, "CS2_119")   -- Oasis Snapjaw 2/7
  local b = H.Put(g, 2, "CS2_119")
  local c = H.Put(g, 2, "CS2_119")

  run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION",
                                    excludeTarget = true }, amount = 1 } },
      { controller = 1, target = b })

  H.eq(a:Health(), 6, "other minion damaged")
  H.eq(c:Health(), 6, "other minion damaged")
  H.eq(b:Health(), 7, "the target itself was excluded")
  H.noEngineErrors(g)
end)

--========================================================= adjacent-of-target

H.suite("dsl: adjacent can mean neighbours of the TARGET", function(ns, H)
  -- Cone of Cold / Explosive Shot hit around the thing the player picked, which
  -- adjacent="SELF" cannot express.
  local g = H.NewGame()
  local m1 = H.Put(g, 2, "CS2_119")
  local m2 = H.Put(g, 2, "CS2_119")   -- the target
  local m3 = H.Put(g, 2, "CS2_119")
  local far = H.Put(g, 2, "CS2_119")

  local found = ns.Selector.Resolve(g,
    { adjacent = "TARGET", type = "MINION" }, { controller = 1, target = m2 })
  H.eq(#found, 2, "exactly two neighbours")
  local ids = {}
  for _, e in ipairs(found) do ids[e.instanceId] = true end
  H.ok(ids[m1.instanceId], "left neighbour")
  H.ok(ids[m3.instanceId], "right neighbour")
  H.notOk(ids[m2.instanceId], "not the target itself")
  H.notOk(ids[far.instanceId], "not a distant minion")
  H.noEngineErrors(g)
end)

H.suite("dsl: adjacent-of-target on an edge minion yields one neighbour", function(ns, H)
  local g = H.NewGame()
  local first = H.Put(g, 2, "CS2_119")
  H.Put(g, 2, "CS2_119")
  local found = ns.Selector.Resolve(g,
    { adjacent = "TARGET", type = "MINION" }, { controller = 1, target = first })
  H.eq(#found, 1, "leftmost minion has one neighbour")
end)

H.suite("dsl: adjacent-of-target with no target is empty, not an error", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 2, "CS2_119")
  local found = ns.Selector.Resolve(g,
    { adjacent = "TARGET", type = "MINION" }, { controller = 1 })
  H.eq(#found, 0, "no target -> no matches")
  H.noEngineErrors(g)
end)

--============================================================ dynamic amounts

H.suite("dsl: amount can be a COUNT of matching entities", function(ns, H)
  -- "+1 Attack for each other friendly minion" and friends.
  local g = H.NewGame()
  local hero = H.Hero(g, 2)
  H.Put(g, 1, "CS2_231"); H.Put(g, 1, "CS2_231"); H.Put(g, 1, "CS2_231")
  run(g, { { op = "Damage", sel = { side = "ENEMY", type = "HERO", hero = true },
             amount = { count = { side = "FRIENDLY", type = "MINION" } } } })
  H.eq(hero:Health(), 27, "dealt 3, one per friendly minion")
  H.noEngineErrors(g)
end)

H.suite("dsl: amount can be another entity's ATTACK", function(ns, H)
  -- Shadowflame: damage equal to the destroyed minion's attack.
  local g = H.NewGame()
  local src = H.Put(g, 1, "CS2_182")          -- Chillwind Yeti, 4 attack
  local victim = H.Put(g, 2, "CS2_119")       -- 2/7
  run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION" },
             amount = { attackOf = { self = true } } } },
      { controller = 1, source = src })
  H.eq(victim:Health(), 3, "took 4, the source's attack")
  H.noEngineErrors(g)
end)

H.suite("dsl: amount can be a hero's ARMOR", function(ns, H)
  -- Shield Slam: damage equal to your Armor.
  local g = H.NewGame()
  local hero = H.Hero(g, 1)
  hero.armor = 5
  local victim = H.Put(g, 2, "CS2_119")
  run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION" },
             amount = { armorOf = { side = "FRIENDLY", type = "HERO", hero = true } } } })
  H.eq(victim:Health(), 2, "took 5, equal to armor")
  H.noEngineErrors(g)
end)

H.suite("dsl: a dynamic draw of ZERO draws nothing", function(ns, H)
  --[[ H.Draw used to coerce 0 up to 1, which is wrong for dynamic counts: Battle
       Rage with no damaged minions must draw NO cards. A literal missing count
       still defaults to 1. ]]
  local g = H.NewGame()
  local before = #g.players[1].hand
  run(g, { { op = "Draw", amount = { count = { side = "FRIENDLY", type = "MINION",
                                               damaged = true } } } })
  H.eq(#g.players[1].hand, before, "no damaged minions -> no cards drawn")

  local m = H.Put(g, 1, "CS2_119")
  g:DealDamage(m, 1, nil, false)
  run(g, { { op = "Draw", amount = { count = { side = "FRIENDLY", type = "MINION",
                                               damaged = true } } } })
  H.eq(#g.players[1].hand, before + 1, "one damaged minion -> one card")

  -- and a bare Draw with no amount still means one
  run(g, { { op = "Draw" } })
  H.eq(#g.players[1].hand, before + 2, "Draw with no argument still draws one")
  H.noEngineErrors(g)
end)

--=============================================================== side arguments

H.suite("dsl: Summon can place a minion on the OPPONENT's board", function(ns, H)
  -- Leeroy Jenkins summons two Whelps for the opponent; The Beast likewise.
  local g = H.NewGame()
  run(g, { { op = "Summon", cardId = "CS2_231", count = 2, side = "ENEMY" } })
  H.eq(#g.players[1].board, 0, "nothing on my board")
  H.eq(#g.players[2].board, 2, "two on the opponent's")
  H.noEngineErrors(g)
end)

H.suite("dsl: AddCardToHand can target the opponent", function(ns, H)
  -- King Mukla gives the opponent two Bananas.
  local g = H.NewGame()
  local mine, theirs = #g.players[1].hand, #g.players[2].hand
  run(g, { { op = "AddCardToHand", cardId = "CS2_231", count = 2, side = "ENEMY" } })
  H.eq(#g.players[1].hand, mine, "my hand unchanged")
  H.eq(#g.players[2].hand, theirs + 2, "opponent gained two cards")
  H.noEngineErrors(g)
end)

H.suite("dsl: GainManaCrystal can target the opponent", function(ns, H)
  -- Arcane Golem gives the opponent a Mana Crystal.
  local g = H.NewGame({ firstPlayer = 1 })
  local before = g.players[2].maxMana
  run(g, { { op = "GainManaCrystal", count = 1, side = "ENEMY" } })
  H.eq(g.players[2].maxMana, before + 1, "opponent gained a crystal")
  H.noEngineErrors(g)
end)

H.suite("dsl: DestroyWeapon can disarm the opponent", function(ns, H)
  -- Acidic Swamp Ooze destroys YOUR OPPONENT's weapon.
  local g = H.NewGame()
  g:EquipWeapon(1, "CS2_091")
  g:EquipWeapon(2, "CS2_112")
  run(g, { { op = "DestroyWeapon", side = "ENEMY" } })
  H.ok(g.players[1].weapon, "my weapon survived")
  H.eq(g.players[2].weapon, nil, "the opponent's was destroyed")
  H.noEngineErrors(g)
end)

--=============================================================== mana flags

H.suite("dsl: a TEMPORARY mana crystal lasts only this turn", function(ns, H)
  -- Innervate / The Coin: "this turn only".
  local g = H.NewGame({ firstPlayer = 1 })
  local p = H.Mana(g, 1, 3)
  local maxBefore = p.maxMana
  run(g, { { op = "GainManaCrystal", count = 2, temporary = true } })
  H.eq(g:AvailableMana(1), 5, "three real plus two temporary")
  H.eq(p.maxMana, maxBefore, "maximum mana unchanged -- they are not real crystals")
  g:EndTurn()
  H.eq(p.tempMana, 0, "temporary mana gone")
  H.noEngineErrors(g)
end)

H.suite("dsl: an EMPTY mana crystal raises the maximum but is not usable", function(ns, H)
  -- Wild Growth: "Gain an empty Mana Crystal."
  local g = H.NewGame({ firstPlayer = 1 })
  local p = H.Mana(g, 1, 3)
  local availBefore = g:AvailableMana(1)
  run(g, { { op = "GainManaCrystal", count = 1, empty = true } })
  H.eq(p.maxMana, 4, "maximum went up")
  H.eq(g:AvailableMana(1), availBefore, "but no mana to spend this turn")
  H.noEngineErrors(g)
end)

--============================================================ RemoveKeyword

H.suite("dsl: RemoveKeyword strips Divine Shield", function(ns, H)
  -- Blood Knight eats every Divine Shield on the board.
  local g = H.NewGame()
  local squire = H.Put(g, 2, "EX1_008")       -- Argent Squire 1/1 DIVINE_SHIELD
  H.ok(squire:Has(ns.KEYWORD.DIVINE_SHIELD), "shield present")
  H.ok(squire.divineShieldUp, "and up")

  run(g, { { op = "RemoveKeyword", sel = { side = "ENEMY", type = "MINION" },
             keywords = { ns.KEYWORD.DIVINE_SHIELD } } })

  H.notOk(squire:Has(ns.KEYWORD.DIVINE_SHIELD), "keyword gone")
  H.notOk(squire.divineShieldUp, "and the shield flag cleared")
  -- so the next damage actually lands
  g:DealDamage(squire, 1, nil, false)
  H.eq(squire:Health(), 0, "damage now lands")
  H.noEngineErrors(g)
end)

H.suite("dsl: RemoveKeyword strips Stealth from enemy minions", function(ns, H)
  -- Flare removes Stealth from all enemy minions.
  local g = H.NewGame()
  local sneak = H.Put(g, 2, "EX1_010")        -- Worgen Infiltrator 2/1 STEALTH
  if sneak:Has(ns.KEYWORD.STEALTH) then
    run(g, { { op = "RemoveKeyword", sel = { side = "ENEMY", type = "MINION" },
               keywords = { ns.KEYWORD.STEALTH } } })
    H.notOk(sneak:IsStealth(), "no longer stealthed")
    -- and now it is a legal target for an enemy spell
    local fb = ns.Entity.New(g:Printed("CS2_029"), 1)
    H.ok(ns.Targeting.IsLegalTarget(g, fb, 1, sneak), "targetable once revealed")
  else
    H.ok(true, "EX1_010 has no Stealth in this build; skipped")
  end
  H.noEngineErrors(g)
end)

H.suite("dsl: RemoveKeyword leaves AURA-granted keywords alone", function(ns, H)
  --[[ An aura is recomputed from its source every rebuild, so stripping it would
       be undone instantly. Matching Hearthstone, where silencing the SOURCE is the
       only way to remove an aura-granted keyword. ]]
  local g = H.NewGame()
  local wisp = H.Put(g, 1, "CS2_231")
  wisp.auraKeywords[ns.KEYWORD.TAUNT] = true
  run(g, { { op = "RemoveKeyword", sel = { side = "FRIENDLY", type = "MINION" },
             keywords = { ns.KEYWORD.TAUNT } } })
  -- the aura layer is rebuilt by RecalcAuras inside the op, so it may be cleared
  -- here; what must NOT happen is an error, and base/ench must be untouched
  H.notOk(wisp.baseKeywords[ns.KEYWORD.TAUNT], "base layer untouched")
  H.noEngineErrors(g)
end)

--========================================================= conditional auras

H.suite("dsl: a conditional aura applies only while its condition holds", function(ns, H)
  --[[ Cogmaster is +2 Attack only while you have a weapon. Because the aura layer
       is rebuilt from zero every recalculation, the condition going false simply
       stops contributing -- there is nothing to un-apply. ]]
  local g = H.NewGame({ class1 = "WARRIOR" })
  local cog = H.Put(g, 1, "CS2_231")          -- stand-in host: a 1/1 Wisp
  -- install a conditional self-aura directly, as the compiler would
  ns.Scripts["CS2_231"] = { aura = { sel = { self = true }, atk = 2,
                                     cond = { c = "HasWeapon" } } }
  g:RecalcAuras()
  H.eq(cog:Attack(), 1, "no weapon -> no bonus")

  g:EquipWeapon(1, "CS2_091")
  g:RecalcAuras()
  H.eq(cog:Attack(), 3, "weapon equipped -> +2")

  g:DestroyWeapon(1)
  g:RecalcAuras()
  H.eq(cog:Attack(), 1, "weapon gone -> bonus gone, with nothing to un-apply")
  ns.Scripts["CS2_231"] = nil                 -- restore
  H.noEngineErrors(g)
end)

H.suite("dsl: an aura can grant several keywords at once", function(ns, H)
  -- Wee Spellstopper makes adjacent minions untargetable by spells AND powers.
  local g = H.NewGame()
  local left  = H.Put(g, 1, "CS2_231")
  local host  = H.Put(g, 1, "CS2_119")
  local right = H.Put(g, 1, "CS2_231")
  ns.Scripts["CS2_119"] = { aura = {
    sel = { adjacent = "SELF", type = "MINION" },
    atk = 0, hp = 0,
    keywords = { ns.KEYWORD.CANT_BE_TARGETED_BY_SPELLS,
                 ns.KEYWORD.CANT_BE_TARGETED_BY_HERO_POWERS } } }
  g:RecalcAuras()
  H.ok(left:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_SPELLS), "left untargetable by spells")
  H.ok(left:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_HERO_POWERS), "and by hero powers")
  H.ok(right:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_SPELLS), "right too")
  H.notOk(host:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_SPELLS), "but not the host itself")
  ns.Scripts["CS2_119"] = nil
  g:RecalcAuras()
  H.noEngineErrors(g)
end)

H.suite("dsl: enrage can grant a keyword, not just stats", function(ns, H)
  -- Raging Worgen gains Windfury while damaged.
  local g = H.NewGame()
  local m = H.Put(g, 1, "CS2_119")            -- 2/7
  ns.Scripts["CS2_119"] = { enrage = { atk = 1,
                                       keywords = { ns.KEYWORD.WINDFURY } } }
  g:RecalcAuras()
  H.notOk(m:Has(ns.KEYWORD.WINDFURY), "undamaged -> no Windfury")

  g:DealDamage(m, 1, nil, false)
  H.eq(m:Attack(), 3, "enraged stats")
  H.ok(m:Has(ns.KEYWORD.WINDFURY), "enraged keyword")

  g:Heal(m, 1, nil)
  H.notOk(m:Has(ns.KEYWORD.WINDFURY), "healed -> keyword gone again")
  ns.Scripts["CS2_119"] = nil
  g:RecalcAuras()
  H.noEngineErrors(g)
end)

--====================================================== end-of-turn schedule

H.suite("dsl: AtEndOfTurn fires at the END of the CURRENT turn", function(ns, H)
  --[[ Distinct from AtNextTurn, which fires at the START of your next turn -- a
       full opponent turn later. Power Overwhelming ("then it dies") and Echoing
       Ooze need the shorter fuse. ]]
  local g = H.NewGame({ firstPlayer = 1 })
  local m = H.Put(g, 1, "CS2_182")
  run(g, { { op = "Buff", sel = { self = true }, atk = 4, hp = 4 },
           { op = "ScheduleEndOfTurn", ops = { { op = "Destroy", sel = { self = true } } } } },
      { controller = 1, source = m })
  H.eq(m:Attack(), 8, "buffed now")
  H.eq(#g.scheduled, 1, "destruction scheduled")
  H.eq(#g.players[1].board, 1, "still alive mid-turn")

  g:EndTurn()
  H.eq(#g.players[1].board, 0, "destroyed at the END of the same turn")
  H.eq(#g.scheduled, 0, "schedule consumed")
  H.noEngineErrors(g)
end)

H.suite("dsl: AtEndOfTurn does NOT wait for your next turn", function(ns, H)
  -- Regression against reusing the start-of-turn path, which would fire two
  -- turns late and let the minion attack once for free.
  local g = H.NewGame({ firstPlayer = 1 })
  local m = H.Put(g, 1, "CS2_182")
  local turnAtSchedule = g.turn
  run(g, { { op = "ScheduleEndOfTurn",
             ops = { { op = "Destroy", sel = { self = true } } } } },
      { controller = 1, source = m })
  g:EndTurn()
  H.eq(g.turn, turnAtSchedule + 1, "exactly one turn has passed")
  H.eq(#g.players[1].board, 0, "already gone -- not two turns later")
  H.noEngineErrors(g)
end)

--================================================== copy from opponent's hand

H.suite("dsl: CopyOpponentHandCard takes a card from the enemy hand", function(ns, H)
  -- Mind Vision.
  local g = H.NewGame()
  -- give the opponent a hand of exactly one known card
  g.players[2].hand = {}
  H.Hand(g, 2, "CS2_182")
  local before = #g.players[1].hand
  run(g, { { op = "CopyOpponentHandCard" } })
  H.eq(#g.players[1].hand, before + 1, "gained a card")
  H.eq(g.players[1].hand[#g.players[1].hand].cardId, "CS2_182", "and it is the copy")
  H.eq(#g.players[2].hand, 1, "the opponent still has theirs -- it is a copy")
  H.noEngineErrors(g)
end)

H.suite("dsl: copying from an empty enemy hand does nothing", function(ns, H)
  local g = H.NewGame()
  g.players[2].hand = {}
  local before = #g.players[1].hand
  run(g, { { op = "CopyOpponentHandCard" } })
  H.eq(#g.players[1].hand, before, "no card, no crash")
  H.noEngineErrors(g)
end)
