--[[ tests/test_dsl2.lua -- fixes found by the SECOND authoring round.

  Six engine defects surfaced by authoring cards against the engine rather than by
  reading it. THREE of them were shipping WRONG behaviour rather than merely
  missing behaviour, which makes them the most valuable findings so far:

    1. e.deathrattle was a single slot and SetDeathrattle ASSIGNED to it, so
       granting a deathrattle destroyed any existing one. Ancestral Spirit,
       Poison Seeds and Reincarnate were all quietly broken.
    2. Destroy on a SECRET was completely inert -- ProcessDeaths swept the board
       and the weapon but never the secret zone, so Flare did nothing.
    3. PayloadAttackAtMost read payload.attacker only. MINION_SUMMONED carries
       `entity`, so Warsong Commander's gate was always false and it over-granted
       Charge to every small minion instead of just the new one.
    4. A WEAPON could not host an aura (auraSources iterated the board only).
    5. TakeControl could not hand a minion TO the opponent from the DSL.
    6. Target-shape predicates did not exist, and `sel.target` bypasses every
       selector filter by design, so Count(target +frozen, 1) can never work.
]]
local H = require("tests.harness")

local function run(g, ops, ctx)
  ctx = ctx or { controller = 1 }
  ctx.controller = ctx.controller or 1
  g.bus:Block(function() H.ns.Ops.Run(g, ops, ctx) end)
end

--=========================================================== stacked deathrattles

H.suite("dsl2: granting a deathrattle STACKS, it does not overwrite", function(ns, H)
  local g = H.NewGame()
  local hoarder = H.Put(g, 1, "EX1_096")    -- Loot Hoarder: Deathrattle draw a card
  H.eq(#hoarder.deathrattles, 1, "starts with its own printed deathrattle")

  -- grant a second one, as Ancestral Spirit does
  run(g, { { op = "SetDeathrattle", sel = { self = true },
             ops = { { op = "Summon", cardId = "CS2_231" } } } },
      { controller = 1, source = hoarder })
  H.eq(#hoarder.deathrattles, 2, "now has BOTH, not just the granted one")

  local handBefore = #g.players[1].hand
  hoarder.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].hand, handBefore + 1, "the original draw still fired")
  local wisps = 0
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "CS2_231" then wisps = wisps + 1 end
  end
  H.eq(wisps, 1, "and the granted summon fired too")
  H.noEngineErrors(g)
end)

H.suite("dsl2: silence clears every stacked deathrattle", function(ns, H)
  local g = H.NewGame()
  local hoarder = H.Put(g, 1, "EX1_096")
  run(g, { { op = "SetDeathrattle", sel = { self = true },
             ops = { { op = "Summon", cardId = "CS2_231" } } } },
      { controller = 1, source = hoarder })
  H.eq(#hoarder.deathrattles, 2, "two attached")
  hoarder:Silence()
  H.eq(#hoarder.deathrattles, 0, "silence removed both")

  local handBefore = #g.players[1].hand
  hoarder.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].hand, handBefore, "nothing fired")
  H.noEngineErrors(g)
end)

H.suite("dsl2: stacked deathrattles fire in attachment order", function(ns, H)
  local g = H.NewGame()
  local m = H.Put(g, 1, "CS2_231")
  -- two granted deathrattles summoning distinguishable tokens
  run(g, { { op = "SetDeathrattle", sel = { self = true },
             ops = { { op = "Summon", cardId = "CS2_182" } } },
           { op = "SetDeathrattle", sel = { self = true },
             ops = { { op = "Summon", cardId = "CS2_119" } } } },
      { controller = 1, source = m })
  m.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
  local order = {}
  for _, e in ipairs(g.players[1].board) do order[#order + 1] = e.cardId end
  H.eq(table.concat(order, ","), "CS2_182,CS2_119", "fired in the order attached")
  H.noEngineErrors(g)
end)

--============================================================ secret destruction

H.suite("dsl2: a secret can be destroyed", function(ns, H)
  local g = H.NewGame()
  local trap = ns.Entity.New(g:Printed("EX1_610"), 2)   -- Explosive Trap
  g:PlaySecret(2, trap)
  H.eq(#g.players[2].secrets, 1, "armed")

  run(g, { { op = "Destroy", sel = { side = "ENEMY", zone = "SECRET" } } })
  g:ProcessDeaths()
  H.eq(#g.players[2].secrets, 0, "destroyed")
  -- a spent secret is not a minion death and must not enter the death log
  H.eq(#g.deathLog, 0, "not recorded as a minion death")
  H.noEngineErrors(g)
end)

H.suite("dsl2: destroying secrets leaves my own alone", function(ns, H)
  local g = H.NewGame()
  g:PlaySecret(1, ns.Entity.New(g:Printed("EX1_610"), 1))
  g:PlaySecret(2, ns.Entity.New(g:Printed("EX1_554"), 2))
  run(g, { { op = "Destroy", sel = { side = "ENEMY", zone = "SECRET" } } })
  g:ProcessDeaths()
  H.eq(#g.players[1].secrets, 1, "mine survived")
  H.eq(#g.players[2].secrets, 0, "theirs destroyed")
  H.noEngineErrors(g)
end)

--================================================ attack threshold on a summon

H.suite("dsl2: an attack threshold works on a SUMMON event", function(ns, H)
  local g = H.NewGame()
  local host = H.Put(g, 1, "CS2_119")
  ns.Scripts["CS2_119"] = { triggers = { {
    on = ns.EVENT.MINION_SUMMONED,
    cond = { c = "All", of = { { c = "PayloadSummonedByMe" },
                               { c = "PayloadAttackAtMost", max = 3 } } },
    ops = { { op = "GiveKeyword", sel = { payloadEntity = true },
              keywords = { ns.KEYWORD.CHARGE } } } } } }
  g:AttachScript(host)

  g:Summon("CS2_231", 1, "RIGHTMOST")       -- Wisp, 1 attack -> qualifies
  g.bus:Drain()
  local wisp = g.players[1].board[#g.players[1].board]
  H.ok(wisp:Has(ns.KEYWORD.CHARGE), "small minion got Charge")

  g:Summon("CS2_182", 1, "RIGHTMOST")       -- Chillwind Yeti, 4 attack -> must not
  g.bus:Drain()
  local yeti = g.players[1].board[#g.players[1].board]
  H.notOk(yeti:Has(ns.KEYWORD.CHARGE), "big minion did NOT get Charge")
  H.ok(wisp:Has(ns.KEYWORD.CHARGE), "and the earlier one kept it")

  ns.Scripts["CS2_119"] = nil
  H.noEngineErrors(g)
end)

H.suite("dsl2: the threshold still works on an ATTACK event", function(ns, H)
  -- Must not have broken the original use: Freezing Trap-style attacker gating.
  local g = H.NewGame()
  local small = H.Put(g, 1, "CS2_231")      -- 1 attack
  local big   = H.Put(g, 1, "CS2_182")      -- 4 attack
  H.ok(ns.Conditions.Eval(g, { c = "PayloadAttackAtMost", max = 3 },
        { controller = 2, payload = { attacker = small } }), "1 attack passes")
  H.notOk(ns.Conditions.Eval(g, { c = "PayloadAttackAtMost", max = 3 },
        { controller = 2, payload = { attacker = big } }), "4 attack fails")
  H.noEngineErrors(g)
end)

--=================================================================== weapon auras

H.suite("dsl2: a WEAPON can host an aura", function(ns, H)
  local g = H.NewGame({ class1 = "WARRIOR" })
  g:EquipWeapon(1, "CS2_091")               -- Light's Justice 1/4
  local m = H.Put(g, 1, "CS2_231")          -- a 1/1 Wisp to receive it

  ns.Scripts["CS2_091"] = { aura = { sel = { side = "FRIENDLY", type = "MINION" },
                                     atk = 2, hp = 0 } }
  g:RecalcAuras()
  H.eq(m:Attack(), 3, "the weapon's aura reached the minion")

  g:DestroyWeapon(1)
  g:RecalcAuras()
  H.eq(m:Attack(), 1, "and vanished with the weapon")
  ns.Scripts["CS2_091"] = nil
  H.noEngineErrors(g)
end)

H.suite("dsl2: a weapon aura can buff the weapon itself", function(ns, H)
  -- Cogmaster's Wrench: +2 Attack while you have a Mech.
  local g = H.NewGame({ class1 = "ROGUE" })
  g:EquipWeapon(1, "CS2_091")               -- 1 attack
  local w = g.players[1].weapon
  ns.Scripts["CS2_091"] = { aura = { sel = { self = true }, atk = 2, hp = 0 } }
  g:RecalcAuras()
  H.eq(w:Attack(), 3, "weapon buffed itself")
  H.eq(g:AttackValue(H.Hero(g, 1)), 3, "and the hero swings for it")
  ns.Scripts["CS2_091"] = nil
  g:RecalcAuras()
  H.noEngineErrors(g)
end)

H.suite("dsl2: a silenced weapon grants no aura", function(ns, H)
  local g = H.NewGame({ class1 = "ROGUE" })
  g:EquipWeapon(1, "CS2_091")
  local w = g.players[1].weapon
  local m = H.Put(g, 1, "CS2_231")
  ns.Scripts["CS2_091"] = { aura = { sel = { side = "FRIENDLY", type = "MINION" },
                                     atk = 2, hp = 0 } }
  g:RecalcAuras()
  H.eq(m:Attack(), 3, "aura live")
  w.silenced = true
  g:RecalcAuras()
  H.eq(m:Attack(), 1, "silenced weapon contributes nothing")
  ns.Scripts["CS2_091"] = nil
  g:RecalcAuras()
  H.noEngineErrors(g)
end)

--============================================================ TakeControl side

H.suite("dsl2: TakeControl can hand a minion TO the opponent", function(ns, H)
  -- Shadow Madness gives it back at end of turn.
  local g = H.NewGame()
  local m = H.Put(g, 1, "CS2_182")
  H.eq(m.controller, 1, "mine to begin with")
  run(g, { { op = "TakeControl", sel = { self = true }, toEnemy = true } },
      { controller = 1, source = m })
  H.eq(m.controller, 2, "handed to the opponent")
  H.eq(#g.players[1].board, 0, "left my board")
  H.eq(#g.players[2].board, 1, "arrived on theirs")
  H.eq(m.owner, 1, "but I remain the owner")
  H.noEngineErrors(g)
end)

H.suite("dsl2: Shadow Madness -- steal now, return at end of turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local victim = H.Put(g, 2, "CS2_182")
  run(g, { { op = "TakeControl", sel = { target = true } },
           { op = "ScheduleEndOfTurn",
             ops = { { op = "TakeControl", sel = { target = true }, toEnemy = true } } } },
      { controller = 1, target = victim })
  H.eq(victim.controller, 1, "stolen this turn")
  H.eq(#g.players[1].board, 1, "on my board")

  g:EndTurn()
  H.eq(victim.controller, 2, "returned at end of turn")
  H.eq(#g.players[2].board, 1, "back on theirs")
  H.noEngineErrors(g)
end)

--======================================================= target-shape predicates

H.suite("dsl2: target-shape predicates read the target directly", function(ns, H)
  local g = H.NewGame()
  local m = H.Put(g, 2, "CS2_119")          -- 2/7
  local ctx = { controller = 1, target = m }

  H.notOk(ns.Conditions.Eval(g, { c = "TargetIsDamaged" }, ctx), "undamaged")
  g:DealDamage(m, 1, nil, false)
  H.ok(ns.Conditions.Eval(g, { c = "TargetIsDamaged" }, ctx), "now damaged")

  H.notOk(ns.Conditions.Eval(g, { c = "TargetIsFrozen" }, ctx), "not frozen")
  m.frozen = true
  H.ok(ns.Conditions.Eval(g, { c = "TargetIsFrozen" }, ctx), "now frozen")

  H.ok(ns.Conditions.Eval(g, { c = "TargetAlive" }, ctx), "alive")
  m.pendingDestroy = true
  H.notOk(ns.Conditions.Eval(g, { c = "TargetAlive" }, ctx), "not alive once doomed")
  H.noEngineErrors(g)
end)

H.suite("dsl2: TargetHasKeyword distinguishes keywords", function(ns, H)
  local g = H.NewGame()
  local taunt = H.Put(g, 2, "CS2_179")      -- Sen'jin Shieldmasta, TAUNT
  local ctx = { controller = 1, target = taunt }
  H.ok(ns.Conditions.Eval(g, { c = "TargetHasKeyword",
                               keyword = ns.KEYWORD.TAUNT }, ctx), "has Taunt")
  H.notOk(ns.Conditions.Eval(g, { c = "TargetHasKeyword",
                                  keyword = ns.KEYWORD.CHARGE }, ctx), "has no Charge")
  H.noEngineErrors(g)
end)

H.suite("dsl2: a target predicate with no target is false, not an error", function(ns, H)
  local g = H.NewGame()
  local ctx = { controller = 1 }
  for _, c in ipairs({ "TargetIsDamaged", "TargetAlive", "TargetIsFrozen" }) do
    H.notOk(ns.Conditions.Eval(g, { c = c }, ctx), c .. " with no target")
  end
  H.notOk(ns.Conditions.Eval(g, { c = "TargetHasKeyword",
                                  keyword = ns.KEYWORD.TAUNT }, ctx),
          "TargetHasKeyword with no target")
  H.noEngineErrors(g)
end)
