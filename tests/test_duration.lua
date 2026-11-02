--[[ tests/test_duration.lua -- timed enchantments.

  Two duration classes, both from the pinned pool:

    END_OF_TURN             "this turn"             13 collectible cards
    START_OF_YOUR_NEXT_TURN "until your next turn"  Conceal, Finicky Cloakfield

  Pinned data used here:
    CS2_045 Rockbiter Weapon   1 mana  friendly character +3 Attack this turn
    CS2_011 Savage Roar        3 mana  your CHARACTERS +2 Attack this turn
    CS2_046 Bloodlust          5 mana  your MINIONS +3 Attack this turn
    CS2_105 Heroic Strike      2 mana  your hero +4 Attack this turn
    CS2_005 Claw               1 mana  hero +2 Attack this turn AND 2 Armor
    EX1_549 Bestial Wrath      1 mana  friendly Beast +2 Attack and Immune this turn
    CS2_188 Abusive Sergeant   1 mana 2/1  Battlecry: a minion +2 Attack this turn
    GVG_011 Shrinkmeister      2 mana 3/2  Battlecry: a minion -2 Attack this turn
    EX1_055 Mana Addict        2 mana 1/3  +2 Attack this turn per spell cast
    EX1_128 Conceal            1 mana  your minions Stealth until your next turn
    CS2_017 Shapeshift  Druid hero power  +1 Attack this turn, +1 Armor
]]
local H = require("tests.harness")

--=================================================== END_OF_TURN ("this turn")

H.suite("duration: a this-turn buff expires when the turn ends", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")          -- 4/5
  local i = H.Hand(g, 1, "CS2_045")            -- Rockbiter Weapon
  g:PlayCard(1, i, yeti)
  g.bus:Drain()
  H.eq(yeti:Attack(), 7, "buffed to 7 this turn")

  g:EndTurn()
  H.eq(yeti:Attack(), 4, "back to printed attack next turn")
  H.eq(#yeti.timedEnch, 0, "the timed entry was removed, not just zeroed")
  H.noEngineErrors(g)
end)

H.suite("duration: this-turn buffs STACK and expire together", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  -- two Abusive Sergeants on the same minion is +4, not +2. This is why the
  -- timed layer is a LIST and not a single slot.
  for _ = 1, 2 do
    local i = H.Hand(g, 1, "CS2_188")
    g:PlayCard(1, i, yeti)
    g.bus:Drain()
  end
  H.eq(#yeti.timedEnch, 2, "two separate timed entries")
  H.eq(yeti:Attack(), 8, "4 + 2 + 2")

  g:EndTurn()
  H.eq(yeti:Attack(), 4, "both expired")
  H.noEngineErrors(g)
end)

H.suite("duration: negative timed buffs work and floor at zero", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  -- Shrinkmeister gives -2 Attack this turn. On a 1-attack Wisp the result must
  -- read 0, not -1.
  local wisp = H.Put(g, 1, "CS2_231")          -- 1/1
  local i = H.Hand(g, 1, "GVG_011")
  g:PlayCard(1, i, wisp)
  g.bus:Drain()
  H.eq(wisp:Attack(), 0, "floored at 0, not negative")
  H.notOk(g:CanAttack(wisp), "and cannot attack at 0")

  g:EndTurn()
  H.eq(wisp:Attack(), 1, "debuff expired")
  H.noEngineErrors(g)
end)

H.suite("duration: Savage Roar hits characters, Bloodlust only minions", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  local hero = H.Hero(g, 1)

  local i = H.Hand(g, 1, "CS2_011")            -- Savage Roar
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(yeti:Attack(), 6, "minion buffed")
  H.eq(g:AttackValue(hero), 2, "hero buffed too -- 'characters' includes the hero")

  g:EndTurn(); g:EndTurn()                     -- back to player 1
  H.Mana(g, 1, 10)
  local j = H.Hand(g, 1, "CS2_046")            -- Bloodlust
  g:PlayCard(1, j)
  g.bus:Drain()
  H.eq(yeti:Attack(), 7, "minion buffed by 3")
  H.eq(g:AttackValue(hero), 0, "hero NOT buffed -- 'minions' excludes the hero")
  H.noEngineErrors(g)
end)

H.suite("duration: Claw's attack expires but its armor is permanent", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local hero = H.Hero(g, 1)
  local i = H.Hand(g, 1, "CS2_005")            -- Claw
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(g:AttackValue(hero), 2, "hero has 2 attack this turn")
  H.eq(hero.armor, 2, "and 2 armor")

  g:EndTurn()
  H.eq(g:AttackValue(hero), 0, "attack expired")
  H.eq(hero.armor, 2, "armor did NOT expire")
  H.noEngineErrors(g)
end)

H.suite("duration: Heroic Strike lets the hero actually swing", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local hero = H.Hero(g, 1)
  H.notOk(g:CanAttack(hero), "bare hero cannot attack")

  local i = H.Hand(g, 1, "CS2_105")            -- Heroic Strike, +4
  g:PlayCard(1, i)
  g.bus:Drain()
  H.ok(g:CanAttack(hero), "hero can attack with a timed buff")
  g:Attack(hero, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 26, "dealt 4")
  H.noEngineErrors(g)
end)

H.suite("duration: a timed KEYWORD works and expires (Bestial Wrath Immune)", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local raptor = H.Put(g, 1, "CS2_172")        -- Bloodfen Raptor 3/2 BEAST
  local i = H.Hand(g, 1, "EX1_549")            -- Bestial Wrath
  g:PlayCard(1, i, raptor)
  g.bus:Drain()

  H.eq(raptor:Attack(), 5, "+2 attack")
  H.ok(raptor:Has(ns.KEYWORD.IMMUNE), "Immune this turn")
  g:DealDamage(raptor, 10, nil, false)
  H.eq(raptor:Health(), 2, "Immune prevented all damage")

  g:EndTurn()
  H.eq(raptor:Attack(), 3, "attack expired")
  H.notOk(raptor:Has(ns.KEYWORD.IMMUNE), "Immune expired")
  g:DealDamage(raptor, 1, nil, false)
  H.eq(raptor:Health(), 1, "damage lands once Immune is gone")
  H.noEngineErrors(g)
end)

H.suite("duration: Mana Addict stacks once per spell, resets next turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local addict = H.Put(g, 1, "EX1_055")        -- 1/3
  H.eq(addict:Attack(), 1, "base attack")

  for _ = 1, 3 do
    local i = H.Hand(g, 1, "CS2_008")          -- Moonfire, 0 mana-ish cheap spell
    g:PlayCard(1, i, H.Hero(g, 2))
    g.bus:Drain()
  end
  H.eq(addict:Attack(), 7, "1 + 2 per spell x3")
  H.eq(#addict.timedEnch, 3, "three timed entries")

  g:EndTurn()
  H.eq(addict:Attack(), 1, "all expired")
  H.noEngineErrors(g)
end)

H.suite("duration: Druid hero power buffs this turn and armors permanently", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local hero = H.Hero(g, 1)
  local ok = g:UseHeroPower(1)
  g.bus:Drain()
  H.ok(ok, "Shapeshift used")
  H.eq(g:AttackValue(hero), 1, "+1 attack this turn")
  H.eq(hero.armor, 1, "+1 armor")

  g:EndTurn()
  H.eq(g:AttackValue(hero), 0, "attack expired")
  H.eq(hero.armor, 1, "armor kept")
  H.noEngineErrors(g)
end)

--========================================== START_OF_YOUR_NEXT_TURN

H.suite("duration: Conceal survives the opponent's whole turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "EX1_128")            -- Conceal
  g:PlayCard(1, i)
  g.bus:Drain()
  H.ok(yeti:IsStealth(), "stealthed on the turn it was cast")

  g:EndTurn()                                   -- opponent's turn
  H.ok(yeti:IsStealth(), "STILL stealthed through the opponent's turn")
  -- which is the whole point: the opponent cannot target it
  local fireball = ns.Entity.New(g:Printed("CS2_029"), 2)
  H.notOk(ns.Targeting.IsLegalTarget(g, fireball, 2, yeti),
          "opponent cannot target a stealthed minion")

  g:EndTurn()                                   -- back to player 1
  H.notOk(yeti:IsStealth(), "stealth dropped at the start of my next turn")
  H.noEngineErrors(g)
end)

H.suite("duration: until-next-turn does not expire on the OPPONENT's turn begin", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "EX1_128")
  g:PlayCard(1, i)
  g.bus:Drain()
  local appliedTurn = g.turn

  g:EndTurn()
  H.eq(g.turn, appliedTurn + 1, "one turn later")
  H.eq(#yeti.timedEnch, 1, "entry survived the opponent's BeginTurn sweep")
  g:EndTurn()
  H.eq(#yeti.timedEnch, 0, "removed on my own BeginTurn")
  H.noEngineErrors(g)
end)

H.suite("duration: the two players' timers are independent", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local mine  = H.Put(g, 1, "CS2_182")
  local yours = H.Put(g, 2, "CS2_182")
  -- P1 grants itself an until-next-turn buff, P2 gets a this-turn buff later
  mine:AddTimedEnchantment(1, 0, nil, ns.DURATION.START_OF_YOUR_NEXT_TURN, g.turn, 1)
  g:EndTurn()                                   -- P2's turn
  yours:AddTimedEnchantment(5, 0, nil, ns.DURATION.END_OF_TURN, g.turn, 2)
  H.eq(mine:Attack(), 5, "P1 buff still live")
  H.eq(yours:Attack(), 9, "P2 buff live")

  g:EndTurn()                                   -- P1's turn: P1's buff expires
  H.eq(yours:Attack(), 4, "P2's this-turn buff expired at end of P2's turn")
  H.eq(mine:Attack(), 4, "P1's until-next-turn buff expired on P1's begin")
  H.noEngineErrors(g)
end)

--=========================================================== interactions

H.suite("duration: silence removes timed buffs", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "CS2_045")            -- Rockbiter +3
  g:PlayCard(1, i, yeti)
  g.bus:Drain()
  H.eq(yeti:Attack(), 7, "buffed")

  yeti:Silence()
  H.eq(yeti:Attack(), 4, "timed buff removed by silence")
  H.eq(#yeti.timedEnch, 0, "timed list cleared")
  H.noEngineErrors(g)
end)

H.suite("duration: bouncing to hand strips timed buffs", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  yeti:AddTimedEnchantment(3, 0, nil, ns.DURATION.END_OF_TURN, g.turn, 1)
  H.eq(yeti:Attack(), 7, "buffed")

  g:MoveToHand(yeti)
  H.eq(#yeti.timedEnch, 0, "timed buffs stripped on bounce")
  H.eq(yeti:Attack(), 4, "back to printed stats in hand")
  H.noEngineErrors(g)
end)

H.suite("duration: transform discards timed buffs", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local yeti = H.Put(g, 1, "CS2_182")
  yeti:AddTimedEnchantment(3, 0, nil, ns.DURATION.END_OF_TURN, g.turn, 1)
  g:Transform(yeti, "CS2_tk1")                 -- Sheep 1/1
  H.eq(#yeti.timedEnch, 0, "timed buffs gone")
  H.eq(yeti:Attack(), 1, "is a plain Sheep")
  H.noEngineErrors(g)
end)

H.suite("duration: an expiring HEALTH buff kills IMMEDIATELY", function(ns, H)
  --[[ Nothing in the pinned pool grants timed health, but the system must not
       quietly do the wrong thing if one ever does -- the same rule as silence:
       if max health drops to or below damage taken, the minion dies.

       Calls ExpireEndOfTurn DIRECTLY rather than going through EndTurn. Via
       EndTurn the death gets cleaned up incidentally by the next BeginTurn's
       drain, so the test would pass even with no death phase in ExpireTimed --
       leaving a corpse on the board in between, visible to anything that reads
       it. (Found by mutation testing: removing ProcessDeaths from ExpireTimed
       failed nothing.) ]]
  local g = H.NewGame({ firstPlayer = 1 })
  local yeti = H.Put(g, 1, "CS2_182")          -- 4/5
  yeti:AddTimedEnchantment(0, 4, nil, ns.DURATION.END_OF_TURN, g.turn, 1)
  H.eq(yeti:MaxHealth(), 9, "buffed to 9 health")
  g:DealDamage(yeti, 6, nil, false)
  H.eq(yeti:Health(), 3, "alive at 3")

  local removed = g:ExpireEndOfTurn()           -- maxHP back to 5, damage 6
  H.eq(removed, 1, "one entry expired")
  H.eq(#g.players[1].board, 0, "dead and OFF THE BOARD at expiry, not later")
  H.noEngineErrors(g)
end)

H.suite("duration: expiry predicate refuses to fire on the turn it was applied", function(ns, H)
  --[[ Tests the `x.turn < self.turn` guard in ExpireStartOfTurn directly.

       The guard is unreachable through normal turn flow, because the sweep runs
       in BeginTurn and a buff applied during a turn is always at least two turns
       from its controller's next BeginTurn. (Found by mutation testing: deleting
       the guard failed nothing.) It is kept as insurance -- if the sweep is ever
       moved after TURN_BEGIN, a TURN_BEGIN trigger granting "until your next
       turn" would otherwise expire instantly. So it is tested at the unit level
       rather than left as unverified defensive code. ]]
  local g = H.NewGame({ firstPlayer = 1 })
  local yeti = H.Put(g, 1, "CS2_182")
  yeti:AddTimedEnchantment(2, 0, nil, ns.DURATION.START_OF_YOUR_NEXT_TURN, g.turn, 1)
  H.eq(yeti:Attack(), 6, "buff live")

  -- same turn, same controller: must NOT expire
  local removed = g:ExpireStartOfTurn(1)
  H.eq(removed, 0, "not expired on the turn it was applied")
  H.eq(yeti:Attack(), 6, "still buffed")

  -- a later turn: now it goes
  g.turn = g.turn + 1
  H.eq(g:ExpireStartOfTurn(1), 1, "expired on a later turn")
  H.eq(yeti:Attack(), 4, "buff gone")

  -- and never for the wrong controller
  yeti:AddTimedEnchantment(2, 0, nil, ns.DURATION.START_OF_YOUR_NEXT_TURN, g.turn, 1)
  g.turn = g.turn + 1
  H.eq(g:ExpireStartOfTurn(2), 0, "player 2's sweep leaves player 1's buff alone")
  H.eq(yeti:Attack(), 6, "still buffed")
  H.noEngineErrors(g)
end)

H.suite("duration: permanent and timed buffs coexist on one minion", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")          -- 4/5
  yeti:AddEnchantment(2, 2)                     -- permanent +2/+2 -> 6/7
  local i = H.Hand(g, 1, "CS2_045")            -- timed +3
  g:PlayCard(1, i, yeti)
  g.bus:Drain()
  H.eq(yeti:Attack(), 9, "4 + 2 permanent + 3 timed")
  H.eq(yeti:MaxHealth(), 7, "health from the permanent buff")

  g:EndTurn()
  H.eq(yeti:Attack(), 6, "only the timed part expired")
  H.eq(yeti:MaxHealth(), 7, "permanent health intact")
  H.noEngineErrors(g)
end)

H.suite("duration: timed buffs stack with auras", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local wisp = H.Put(g, 1, "CS2_231")          -- 1/1
  H.Put(g, 1, "EX1_162")                        -- Dire Wolf Alpha, +1 adjacent
  H.eq(wisp:Attack(), 2, "aura applied")
  wisp:AddTimedEnchantment(3, 0, nil, ns.DURATION.END_OF_TURN, g.turn, 1)
  H.eq(wisp:Attack(), 5, "1 base + 1 aura + 3 timed")

  g:EndTurn()
  H.eq(wisp:Attack(), 2, "timed gone, aura remains")
  H.noEngineErrors(g)
end)
