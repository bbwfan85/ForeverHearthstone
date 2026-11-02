--[[ tests/test_playertimed.lua -- the three player-scoped / deferred duration
     families: cost modifiers, damage clamps, scheduled actions.

  Pinned data (build 7234):
    EX1_145  Preparation        0 mana  next spell this turn costs (3) less
    EX1_612  Kirin Tor Mage     3 mana 4/3  Battlecry: next Secret this turn costs (0)
    NEW1_029 Millhouse Manastorm 2 mana 4/4  Battlecry: enemy spells cost (0) next turn
    FP1_030  Loatheb            5 mana 5/5  Battlecry: enemy spells cost (5) more next turn
    NEW1_036 Commanding Shout   2 mana  your minions can't drop below 1 Health this turn; draw
    EX1_295  Ice Block          3 mana  Secret: prevent fatal damage, hero Immune this turn
    EX1_137  Headcrack          3 mana  2 to enemy hero; Combo: return to hand next turn
    DREAM_05 Nightmare          0 mana  +5/+5, destroy at the start of your next turn
    FP1_013  Kel'Thuzad         8 mana 6/8  end of EACH turn: resummon friendly minions that died
]]
local H = require("tests.harness")

--=========================================================== COST MODIFIERS

H.suite("cost: Preparation discounts the next spell only", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local fireball = ns.Entity.New(g:Printed("CS2_029"), 1)   -- 4 mana
  H.eq(g:CardCost(fireball, 1), 4, "undiscounted")

  local i = H.Hand(g, 1, "EX1_145")                          -- Preparation
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(g:CardCost(fireball, 1), 1, "discounted to 1")

  -- cast a spell: the charge is consumed
  local j = H.Hand(g, 1, "CS2_029")
  local manaBefore = g:AvailableMana(1)
  g:PlayCard(1, j, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(g:AvailableMana(1), manaBefore - 1, "paid the discounted cost")
  H.eq(g:CardCost(fireball, 1), 4, "discount consumed, back to full price")
  H.noEngineErrors(g)
end)

H.suite("cost: Preparation does not discount minions", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_145")
  g:PlayCard(1, i)
  g.bus:Drain()
  local yeti = ns.Entity.New(g:Printed("CS2_182"), 1)        -- 4 mana minion
  H.eq(g:CardCost(yeti, 1), 4, "minions unaffected by a spell discount")
  H.noEngineErrors(g)
end)

H.suite("cost: Preparation expires at end of turn if unused", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_145")
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(#g.players[1].costMods, 1, "modifier active")
  g:EndTurn()
  H.eq(#g.players[1].costMods, 0, "expired unused")
  H.noEngineErrors(g)
end)

H.suite("cost: Kirin Tor Mage makes only the next SECRET free", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_612")                          -- Kirin Tor Mage
  g:PlayCard(1, i)
  g.bus:Drain()

  local iceblock = ns.Entity.New(g:Printed("EX1_295"), 1)    -- a 3-mana secret
  local fireball = ns.Entity.New(g:Printed("CS2_029"), 1)    -- a 4-mana spell
  H.eq(g:CardCost(iceblock, 1), 0, "secret is free")
  H.eq(g:CardCost(fireball, 1), 4, "non-secret spell is unaffected")
  H.noEngineErrors(g)
end)

H.suite("cost: Loatheb taxes the OPPONENT's spells next turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "FP1_030")                          -- Loatheb
  g:PlayCard(1, i)
  g.bus:Drain()

  -- the modifier lives on the AFFECTED player's list
  H.eq(#g.players[2].costMods, 1, "stored on the opponent")
  H.eq(#g.players[1].costMods, 0, "not on the caster")

  local foeSpell = ns.Entity.New(g:Printed("CS2_029"), 2)
  H.eq(g:CardCost(foeSpell, 2), 9, "4 + 5 next turn")
  local mySpell = ns.Entity.New(g:Printed("CS2_029"), 1)
  H.eq(g:CardCost(mySpell, 1), 4, "my own spells untaxed")

  g:EndTurn()                       -- opponent's turn: tax is live
  H.eq(g:CardCost(foeSpell, 2), 9, "still taxed during their turn")
  g:EndTurn()                       -- back to me: expires
  H.eq(g:CardCost(foeSpell, 2), 4, "tax gone once my turn begins")
  H.noEngineErrors(g)
end)

H.suite("cost: Millhouse makes enemy spells free, unlimited uses", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "NEW1_029")                         -- Millhouse
  g:PlayCard(1, i)
  g.bus:Drain()
  local a = ns.Entity.New(g:Printed("CS2_029"), 2)
  H.eq(g:CardCost(a, 2), 0, "first enemy spell free")
  -- no charges: it does not get consumed
  g:ConsumeCostMods(a, 2)
  H.eq(g:CardCost(a, 2), 0, "still free -- unlimited for its duration")
  H.noEngineErrors(g)
end)

H.suite("cost: setTo then delta -- a taxed free secret costs the tax", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local p = g.players[1]
  -- construct both modifiers directly: setTo 0 and +5
  p.costMods[1] = { appliesTo = "SECRET", setTo = 0,
                    expiry = ns.DURATION.END_OF_TURN, turn = g.turn, controller = 1 }
  p.costMods[2] = { appliesTo = "SPELL", amount = 5,
                    expiry = ns.DURATION.END_OF_TURN, turn = g.turn, controller = 1 }
  local secret = ns.Entity.New(g:Printed("EX1_295"), 1)
  -- setTo wins over the base cost, then the delta is added: 0 + 5
  H.eq(g:CardCost(secret, 1), 5, "setTo applied first, then the delta")
  H.noEngineErrors(g)
end)

H.suite("cost: modified cost is visible to the playability check", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  local p = H.Mana(g, 1, 1)                       -- only ONE mana
  local fireball = ns.Entity.New(g:Printed("CS2_029"), 1)     -- 4 mana
  H.notOk(ns.Targeting.CanPlay(g, fireball, 1), "unplayable at 1 mana")

  local i = H.Hand(g, 1, "EX1_145")               -- Preparation, 0 mana
  g:PlayCard(1, i)
  g.bus:Drain()
  H.ok(ns.Targeting.CanPlay(g, fireball, 1), "playable once discounted to 1")
  H.noEngineErrors(g)
end)

--============================================================ DAMAGE CLAMPS

H.suite("clamp: Commanding Shout keeps your minions at 1 health", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")             -- 4/5
  local foe  = H.Put(g, 2, "CS2_182")             -- enemy 4/5, unprotected
  local handBefore = #g.players[1].hand

  local i = H.Hand(g, 1, "NEW1_036")
  g:PlayCard(1, i)
  g.bus:Drain()
  -- H.Hand puts the card in hand (+1), playing it removes it (-1), and its
  -- "Draw a card" adds one (+1). Net +1 against the pre-H.Hand count.
  H.eq(#g.players[1].hand, handBefore + 1, "Commanding Shout drew a card")

  g:DealDamage(yeti, 99, nil, false)
  g:ProcessDeaths()
  H.eq(yeti:Health(), 1, "clamped to 1, not dead")
  H.eq(#g.players[1].board, 1, "still on the board")

  g:DealDamage(foe, 99, nil, false)
  g:ProcessDeaths()
  H.eq(#g.players[2].board, 0, "enemy minion is NOT protected")
  H.noEngineErrors(g)
end)

H.suite("clamp: does not stop DESTROY effects", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "NEW1_036")
  g:PlayCard(1, i)
  g.bus:Drain()
  -- Commanding Shout clamps DAMAGE only; destruction still kills.
  yeti.pendingDestroy = true
  g:ProcessDeaths()
  H.eq(#g.players[1].board, 0, "destroy bypasses the clamp")
  H.noEngineErrors(g)
end)

H.suite("clamp: expires at end of turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "NEW1_036")
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(#g.players[1].damageClamps, 1, "clamp active")
  g:EndTurn()
  H.eq(#g.players[1].damageClamps, 0, "expired")
  g:DealDamage(yeti, 99, nil, false)
  g:ProcessDeaths()
  H.eq(#g.players[1].board, 0, "dies normally next turn")
  H.noEngineErrors(g)
end)

H.suite("clamp: protects MINIONS only -- the hero is still killable", function(ns, H)
  --[[ Commanding Shout says "your minions". If the clamp leaked onto the hero,
       the hero would become unkillable for a turn, which is a game-ending bug
       and completely silent. (Found by mutation testing: removing the minion
       type check failed nothing.) ]]
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "NEW1_036")
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(#g.players[1].damageClamps, 1, "clamp active")

  H.notOk(g:DamageFloorFor(H.Hero(g, 1)), "no floor for the hero")
  g:DealDamage(H.Hero(g, 1), 99, nil, false)
  g:ProcessDeaths()
  H.ok(g.over, "own hero still dies through Commanding Shout")
  H.eq(g.winner, 2, "player 2 wins")
end)

H.suite("iceblock: does NOT fire on your own turn", function(ns, H)
  --[[ No secret triggers on its owner's turn, Ice Block included: a Mage who
       Life Taps or Hellfires themselves to death on their own turn dies (it
       used to be an exception, `anyTurn`; docs/29). ]]
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  local ib = ns.Entity.New(g:Printed("EX1_295"), 1)   -- player 1's OWN Ice Block
  g:PlaySecret(1, ib)
  local hero1 = H.Hero(g, 1)
  hero1.damage = 28                                   -- at 2 health

  g:DealDamage(hero1, 10, nil, false)                 -- self-inflicted, fatal
  g:ProcessDeaths()
  g.bus:Drain()

  H.eq(#g.players[1].secrets, 1, "the Ice Block stays unrevealed")
  H.ok(g.over and g.winner == 2, "and the hero dies")
  H.noEngineErrors(g)
end)

H.suite("iceblock: prevents fatal damage and grants Immune for the turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  -- player 2 arms Ice Block, then player 1 tries to burn them down
  local ib = ns.Entity.New(g:Printed("EX1_295"), 2)
  g:PlaySecret(2, ib)
  local hero2 = H.Hero(g, 2)
  hero2.damage = 26                               -- at 4 health

  local i = H.Hand(g, 1, "CS2_029")               -- Fireball, 6 damage: fatal
  g:PlayCard(1, i, hero2)
  g.bus:Drain()

  H.eq(hero2:Health(), 4, "fatal damage prevented entirely")
  H.eq(#g.players[2].secrets, 0, "Ice Block consumed")
  H.ok(hero2:Has(ns.KEYWORD.IMMUNE), "hero is Immune this turn")
  H.notOk(g.over, "game not over")

  -- further damage this turn does nothing either
  g:DealDamage(hero2, 30, nil, false)
  H.eq(hero2:Health(), 4, "Immune blocks subsequent damage in the same turn")
  H.noEngineErrors(g)
end)

H.suite("iceblock: Immune expires, so next turn is lethal again", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ib = ns.Entity.New(g:Printed("EX1_295"), 2)
  g:PlaySecret(2, ib)
  local hero2 = H.Hero(g, 2)
  hero2.damage = 26
  local i = H.Hand(g, 1, "CS2_029")
  g:PlayCard(1, i, hero2)
  g.bus:Drain()
  H.ok(hero2:Has(ns.KEYWORD.IMMUNE), "Immune now")

  g:EndTurn()                                     -- end of the attacker's turn
  H.notOk(hero2:Has(ns.KEYWORD.IMMUNE), "Immune expired")
  g:DealDamage(hero2, 10, nil, false)
  g:ProcessDeaths()
  H.ok(g.over, "now lethal")
  H.eq(g.winner, 1, "player 1 wins")
end)

H.suite("iceblock: does NOT fire on non-fatal damage", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ib = ns.Entity.New(g:Printed("EX1_295"), 2)
  g:PlaySecret(2, ib)
  local i = H.Hand(g, 1, "CS2_029")               -- 6 damage on a full hero
  g:PlayCard(1, i, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 24, "damage landed normally")
  H.eq(#g.players[2].secrets, 1, "secret still armed")
  H.noEngineErrors(g)
end)

H.suite("secrets: resolve INLINE -- Explosive Trap kills before the attack lands", function(ns, H)
  --[[ Regression test for a real bug. Secrets used to queue their effects, so a
       1-health attacker swinging into Explosive Trap still got to deal its
       damage before dying on the drain. Secrets are part of the triggering
       action and must resolve before it continues. ]]
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  local trap = ns.Entity.New(g:Printed("EX1_610"), 2)
  g:PlaySecret(2, trap)

  local wolfrider = H.Put(g, 1, "CS2_124")        -- 3/1 CHARGE: dies to 2 damage
  local heroBefore = H.Hero(g, 2):Health()
  g:Attack(wolfrider, H.Hero(g, 2))
  g.bus:Drain()

  H.eq(#g.players[1].board, 0, "attacker died to the trap")
  H.eq(H.Hero(g, 2):Health(), heroBefore,
       "and dealt NO damage, because it died before connecting")
  H.noEngineErrors(g)
end)

--========================================================= SCHEDULED ACTIONS

H.suite("schedule: Nightmare buffs now and destroys at the start of your next turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")             -- 4/5
  local i = H.Hand(g, 1, "DREAM_05")
  g:PlayCard(1, i, yeti)
  g.bus:Drain()
  H.eq(yeti:Attack(), 9, "+5/+5 immediately")
  H.eq(yeti:MaxHealth(), 10, "health buffed")
  H.eq(#g.scheduled, 1, "destruction scheduled")

  g:EndTurn()                                     -- opponent's turn
  H.eq(#g.players[1].board, 1, "survives the opponent's turn")
  H.eq(yeti:Attack(), 9, "still buffed")

  g:EndTurn()                                     -- my turn begins: it dies
  H.eq(#g.players[1].board, 0, "destroyed at the start of my next turn")
  H.eq(#g.scheduled, 0, "schedule consumed")
  H.noEngineErrors(g)
end)

H.suite("schedule: Nightmare destroys the minion it buffed, not a later target", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local a = H.Put(g, 1, "CS2_182")
  local b = H.Put(g, 1, "CS2_119")                -- a second minion
  local i = H.Hand(g, 1, "DREAM_05")
  g:PlayCard(1, i, a)                             -- target A
  g.bus:Drain()

  g:EndTurn(); g:EndTurn()
  H.eq(#g.players[1].board, 1, "one minion died")
  H.eq(g.players[1].board[1], b, "the OTHER minion survived -- target was captured")
  H.noEngineErrors(g)
end)

H.suite("schedule: Headcrack returns to hand only with Combo", function(ns, H)
  -- no combo: just 2 damage, nothing scheduled
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_137")
  g:PlayCard(1, i, nil)
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 28, "dealt 2")
  H.eq(#g.scheduled, 0, "no return scheduled without Combo")

  -- with combo: play a cheap card first
  local g2 = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  local a = H.Hand(g2, 1, "CS2_231")              -- Wisp, to enable Combo
  g2:PlayCard(1, a)
  g2.bus:Drain()
  local b = H.Hand(g2, 1, "EX1_137")
  g2:PlayCard(1, b, nil)
  g2.bus:Drain()
  H.eq(H.Hero(g2, 2):Health(), 28, "still dealt 2")
  H.eq(#g2.scheduled, 1, "return scheduled")

  local handBefore = #g2.players[1].hand
  g2:EndTurn(); g2:EndTurn()
  H.eq(#g2.players[1].hand, handBefore + 2, "drew for turn AND got Headcrack back")
  local found = false
  for _, e in ipairs(g2.players[1].hand) do
    if e.cardId == "EX1_137" then found = true end
  end
  H.ok(found, "Headcrack is in hand again")
  H.noEngineErrors(g2)
end)

H.suite("kelthuzad: resummons friendly minions that died this turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  H.Put(g, 1, "FP1_013")                          -- Kel'Thuzad 6/8
  local a = H.Put(g, 1, "CS2_182")                -- Yeti
  local b = H.Put(g, 1, "CS2_231")                -- Wisp
  local foe = H.Put(g, 2, "CS2_182")              -- enemy minion

  a.pendingDestroy = true
  b.pendingDestroy = true
  foe.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  H.eq(#g.players[1].board, 1, "only Kel'Thuzad left mid-turn")
  H.eq(#g.players[2].board, 0, "enemy minion dead")

  g:EndTurn()                                     -- TURN_END fires the trigger
  H.eq(#g.players[1].board, 3, "Kel'Thuzad plus two resummoned minions")
  H.eq(#g.players[2].board, 0, "enemy minion NOT resummoned -- friendly only")
  H.noEngineErrors(g)
end)

H.suite("kelthuzad: the death log resets each turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  local a = H.Put(g, 1, "CS2_182")
  a.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  H.eq(#g.deathLog, 1, "death recorded")

  -- Kel'Thuzad arrives only AFTER the death, and a full turn has passed
  g:EndTurn()
  H.eq(#g.deathLog, 0, "log cleared at the start of the new turn")
  H.Put(g, 1, "FP1_013")
  g:EndTurn(); g:EndTurn()
  local yetis = 0
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "CS2_182" then yetis = yetis + 1 end
  end
  H.eq(yetis, 0, "a minion that died on an earlier turn is not resummoned")
  H.noEngineErrors(g)
end)

H.suite("kelthuzad: respects the seven-slot board cap", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  H.Put(g, 1, "FP1_013")
  -- six minions die; only six slots are free after Kel'Thuzad, so all fit
  local dead = {}
  for i = 1, 6 do dead[i] = H.Put(g, 1, "CS2_231") end
  for _, e in ipairs(dead) do e.pendingDestroy = true end
  g:ProcessDeaths(); g.bus:Drain()
  g:EndTurn()
  H.eq(#g.players[1].board, 7, "board filled to exactly seven")
  H.ok(#g.players[1].board <= ns.RULES.BOARD_SLOTS, "never exceeds the cap")
  H.noEngineErrors(g)
end)

H.suite("schedule: refuses to fire on the turn it was created", function(ns, H)
  --[[ Unit-level test of the `s.turn < self.turn` guard in RunScheduled.
       Unreachable through normal turn flow, since the player filter already
       skips the opponent's intervening BeginTurn -- but if a scheduled action
       ever schedules another, or the call moves, this stops it firing instantly.
       (Found by mutation testing: deleting the guard failed nothing.) ]]
  local g = H.NewGame({ firstPlayer = 1 })
  local fired = 0
  g:Schedule("START_OF_TURN", 1, { { op = "Draw", count = 1 } }, { controller = 1 })
  H.eq(#g.scheduled, 1, "scheduled")

  H.eq(g:RunScheduled("START_OF_TURN", 1), 0, "does not fire on the same turn")
  H.eq(#g.scheduled, 1, "still pending")

  g.turn = g.turn + 1
  H.eq(g:RunScheduled("START_OF_TURN", 1), 1, "fires on a later turn")
  H.eq(#g.scheduled, 0, "consumed")

  -- and never for the wrong player
  g:Schedule("START_OF_TURN", 1, { { op = "Draw", count = 1 } }, { controller = 1 })
  g.turn = g.turn + 1
  H.eq(g:RunScheduled("START_OF_TURN", 2), 0, "player 2's sweep leaves it alone")
  H.eq(#g.scheduled, 1, "still pending")
  H.noEngineErrors(g)
end)

H.suite("kelthuzad: ignores deaths recorded on an earlier turn", function(ns, H)
  --[[ The death log is cleared each BeginTurn, so every entry should already be
       from the current turn -- the `rec.turn == game.turn` filter is belt and
       braces. Tested by injecting a stale entry directly, because otherwise the
       two guards mask each other and neither is really verified.
       (Found by mutation testing: removing the turn filter failed nothing.) ]]
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1)
  H.Put(g, 1, "FP1_013")                      -- Kel'Thuzad

  -- a stale record, as if the log had not been cleared
  g.deathLog[#g.deathLog + 1] =
    { cardId = "CS2_182", controller = 1, turn = g.turn - 1 }
  -- and a current-turn one
  g.deathLog[#g.deathLog + 1] =
    { cardId = "CS2_231", controller = 1, turn = g.turn }

  g:EndTurn()
  local yetis, wisps = 0, 0
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "CS2_182" then yetis = yetis + 1 end
    if e.cardId == "CS2_231" then wisps = wisps + 1 end
  end
  H.eq(wisps, 1, "current-turn death resummoned")
  H.eq(yetis, 0, "stale death ignored")
  H.noEngineErrors(g)
end)

H.suite("cost: an unlimited modifier is never consumed by casting", function(ns, H)
  --[[ Explicit test that ConsumeCostMods only decrements modifiers that HAVE
       charges, and drops them at zero. Preparation (1 charge) must vanish after
       one spell; Loatheb (no charges) must survive any number. ]]
  local g = H.NewGame({ firstPlayer = 1 })
  local p = g.players[1]
  p.costMods[1] = { appliesTo = "SPELL", amount = -3, charges = 1,
                    expiry = ns.DURATION.END_OF_TURN, turn = g.turn, controller = 1 }
  p.costMods[2] = { appliesTo = "SPELL", amount = 1,
                    expiry = ns.DURATION.END_OF_TURN, turn = g.turn, controller = 1 }
  local spell = ns.Entity.New(g:Printed("CS2_029"), 1)        -- 4 mana
  H.eq(g:CardCost(spell, 1), 2, "4 - 3 + 1")

  g:ConsumeCostMods(spell, 1)
  H.eq(#p.costMods, 1, "the 1-charge modifier was dropped")
  H.eq(g:CardCost(spell, 1), 5, "only the unlimited +1 remains")

  g:ConsumeCostMods(spell, 1)
  g:ConsumeCostMods(spell, 1)
  H.eq(#p.costMods, 1, "unlimited modifier survives repeated casts")
  H.eq(g:CardCost(spell, 1), 5, "still applying")
  H.noEngineErrors(g)
end)
