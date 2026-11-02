--[[ tests/test_triggers.lua -- the trigger queue.

  Knife Juggler is the engine's acceptance test. Pinned stats:
    NEW1_019 Knife Juggler     2 mana 3/2  "After you summon a minion, deal 1 damage to a random enemy"
    CS2_237  Starving Buzzard  2 mana 2/1 BEAST  "Whenever you summon a Beast, draw a card"
    EX1_604  Frothing Berserker 3 mana 2/4  "Whenever a minion takes damage, gain +1 Attack"
    EX1_538  Unleash the Hounds 3 mana  "For each enemy minion, summon a 1/1 Hound with Charge"
    EX1_538t Hound 1/1 CHARGE BEAST
]]
local H = require("tests.harness")

H.suite("juggler: throws a knife when you summon", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "NEW1_019")                 -- Juggler already in play
  local hpBefore = H.Hero(g, 2):Health()
  g:Summon("CS2_231", 1, "RIGHTMOST")     -- summon a Wisp
  -- only the enemy hero is available as a target
  H.eq(H.Hero(g, 2):Health(), hpBefore - 1, "one knife hit the enemy hero")
  H.noEngineErrors(g)
end)

H.suite("juggler: does NOT trigger on its own arrival", function(ns, H)
  local g = H.NewGame()
  local hpBefore = H.Hero(g, 2):Health()
  -- Summoning the Juggler itself raises MINION_SUMMONED. It must not throw.
  g:Summon("NEW1_019", 1, "RIGHTMOST")
  H.eq(H.Hero(g, 2):Health(), hpBefore, "no knife on self-summon")
  H.noEngineErrors(g)
end)

H.suite("juggler: only fires for its OWN controller's summons", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "NEW1_019")
  local hpBefore = H.Hero(g, 2):Health()
  g:Summon("CS2_231", 2, "RIGHTMOST")     -- ENEMY summons a minion
  H.eq(H.Hero(g, 2):Health(), hpBefore, "enemy summon does not trigger my Juggler")
  H.noEngineErrors(g)
end)

H.suite("juggler: two jugglers both throw, order-independent", function(ns, H)
  -- Board order must not matter: two Jugglers throw once each regardless of
  -- where they sit, because collection is by play order.
  local function run(insertLeft)
    local g = H.NewGame()
    H.Put(g, 1, "NEW1_019")
    if insertLeft then H.Put(g, 1, "NEW1_019", { index = 1 })
    else H.Put(g, 1, "NEW1_019") end
    H.Put(g, 2, "CS2_119")                -- Oasis Snapjaw 2/7, soaks knives
    local before = g.players[2].board[1]:Health()
    g:Summon("CS2_231", 1, "RIGHTMOST")
    g.bus:Drain()
    local dealt = 0
    for _, e in ipairs(g.players[2].board) do
      dealt = dealt + (e:MaxHealth() - e:Health())
    end
    dealt = dealt + (30 - H.Hero(g, 2):Health())
    return dealt, g
  end
  local a, ga = run(false)
  local b, gb = run(true)
  H.eq(a, 2, "two knives thrown (appended right)")
  H.eq(b, 2, "two knives thrown (inserted left)")
  H.noEngineErrors(ga)
  H.noEngineErrors(gb)
end)

H.suite("juggler: token summons from a spell each trigger a knife", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  H.SetActive(g, 1)
  H.Put(g, 1, "NEW1_019")
  -- three enemy minions -> Unleash summons three Hounds -> three knives
  H.Put(g, 2, "CS2_119")
  H.Put(g, 2, "CS2_119")
  H.Put(g, 2, "CS2_119")
  local idx = H.Hand(g, 1, "EX1_538")
  local ok = g:PlayCard(1, idx)
  H.ok(ok, "Unleash the Hounds played")
  g.bus:Drain()

  local hounds = 0
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "EX1_538t" then hounds = hounds + 1 end
  end
  H.eq(hounds, 3, "one Hound per enemy minion")

  local dealt = (30 - H.Hero(g, 2):Health())
  for _, e in ipairs(g.players[2].board) do
    dealt = dealt + (e:MaxHealth() - e:Health())
  end
  H.eq(dealt, 3, "three knives from three token summons")
  H.noEngineErrors(g)
end)

H.suite("triggers: collected in PLAY order, not board order", function(ns, H)
  --[[ Two identical Jugglers throw identical knives, so ordering is invisible
       from the outside -- a black-box test cannot catch a board-order sort.
       (Found by mutation testing: sorting Bus:Collect by boardIndex passed the
       entire suite.) So this asserts the mechanism directly.

       Hearthstone resolves same-event triggers oldest-first by PLAY order.
       Board position is irrelevant. ]]
  local g = H.NewGame()
  local first  = H.Put(g, 1, "NEW1_019")                  -- played 1st
  local second = H.Put(g, 1, "NEW1_019", { index = 1 })   -- played 2nd, sits LEFT

  H.ok(first.playOrder < second.playOrder, "first was played earlier")
  H.ok(second.boardIndex < first.boardIndex, "but second sits to its left")

  local found = g.bus:Collect(ns.EVENT.MINION_SUMMONED, {})
  H.eq(#found, 2, "both Jugglers collected")
  H.eq(found[1].entity, first,  "older minion resolves first")
  H.eq(found[2].entity, second, "newer minion resolves second")
  H.noEngineErrors(g)
end)

H.suite("triggers: collection spans both players in play order", function(ns, H)
  local g = H.NewGame()
  local mine  = H.Put(g, 1, "NEW1_019")
  local yours = H.Put(g, 2, "NEW1_019")
  local found = g.bus:Collect(ns.EVENT.MINION_SUMMONED, {})
  H.eq(#found, 2, "both sides collected")
  H.eq(found[1].entity, mine,  "my earlier Juggler first")
  H.eq(found[2].entity, yours, "opponent's later Juggler second")
  H.noEngineErrors(g)
end)

H.suite("triggers: deathrattles queue in play order", function(ns, H)
  --[[ Same reasoning: two Loot Hoarders each draw a card, so the order is
       unobservable from the board. Assert the queue directly. ]]
  local g = H.NewGame()
  local first  = H.Put(g, 1, "EX1_096")                   -- played 1st
  local second = H.Put(g, 1, "EX1_096", { index = 1 })    -- played 2nd, sits LEFT
  first.pendingDestroy = true
  second.pendingDestroy = true

  -- Hold the queue open so it can be inspected. At blockDepth 0 every Raise
  -- drains immediately, so the queue would be empty by the time we looked.
  g.bus.queue = {}
  g.bus.blockDepth = 1
  g:ProcessDeaths()
  H.eq(#g.bus.queue, 2, "two deathrattles queued")
  if #g.bus.queue == 2 then
    H.eq(g.bus.queue[1].ctx.source, first,  "older deathrattle queued first")
    H.eq(g.bus.queue[2].ctx.source, second, "newer deathrattle queued second")
  end
  g.bus.blockDepth = 0
  g.bus:Drain()
  H.noEngineErrors(g)
end)

H.suite("buzzard: race filter on the summoned minion", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_237")                  -- Starving Buzzard
  local before = #g.players[1].hand

  g:Summon("CS2_231", 1, "RIGHTMOST")     -- Wisp, no race
  g.bus:Drain()
  H.eq(#g.players[1].hand, before, "non-Beast summon draws nothing")

  g:Summon("CS2_172", 1, "RIGHTMOST")     -- Bloodfen Raptor, BEAST
  g.bus:Drain()
  H.eq(#g.players[1].hand, before + 1, "Beast summon draws a card")
  H.noEngineErrors(g)
end)

H.suite("frothing: one stack per damage instance", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  H.SetActive(g, 1)
  local froth = H.Put(g, 1, "EX1_604")    -- 2/4
  -- three enemy minions; Flamestrike-style AoE should give +3 (one per minion),
  -- and Frothing also counts minions on its OWN side taking damage.
  H.Put(g, 2, "CS2_119")
  H.Put(g, 2, "CS2_119")
  H.Put(g, 2, "CS2_119")
  local idx = H.Hand(g, 1, "CS2_032")     -- Flamestrike, 4 dmg to enemy minions
  g:PlayCard(1, idx)
  g.bus:Drain()
  H.eq(froth:Attack(), 5, "2 base + 3 damage instances")
  H.noEngineErrors(g)
end)

H.suite("frothing: buff is an enchantment, survives the damaged minions dying", function(ns, H)
  local g = H.NewGame()
  local froth = H.Put(g, 1, "EX1_604")
  local wisp = H.Put(g, 2, "CS2_231")     -- 1/1, dies to 1 damage
  g:DealDamage(wisp, 1, nil, false)
  g:ProcessDeaths()
  g.bus:Drain()
  H.eq(#g.players[2].board, 0, "wisp died")
  H.eq(froth:Attack(), 3, "stack persists after the source of the trigger died")
  H.noEngineErrors(g)
end)

H.suite("water elemental: freezes only what IT damaged", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local water = H.Put(g, 1, "CS2_033")    -- 3/6
  local snap  = H.Put(g, 2, "CS2_119")    -- 2/7
  local other = H.Put(g, 2, "CS2_119")    -- 2/7, untouched

  g:Attack(water, snap)
  g.bus:Drain()
  H.ok(snap.frozen, "attacked minion is frozen")
  H.notOk(other.frozen, "bystander is not frozen")
  -- the Elemental also freezes what damages IT? No -- only what it damages.
  H.notOk(water.frozen, "the Elemental itself is not frozen")
  H.noEngineErrors(g)
end)
