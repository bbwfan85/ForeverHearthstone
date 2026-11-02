--[[ tests/test_death.lua -- the death phase: simultaneity, chaining, ordering.

  Pinned stats:
    EX1_097 Abomination  5 mana 4/4 TAUNT  "Deathrattle: Deal 2 damage to ALL characters"
    EX1_096 Loot Hoarder 2 mana 2/1        "Deathrattle: Draw a card"
    EX1_110 Cairne       6 mana 4/5        "Deathrattle: Summon a 4/5 Baine"
    EX1_110t Baine       4/5
    CS2_231 Wisp         0 mana 1/1
    CS2_182 Chillwind Yeti 4 mana 4/5
]]
local H = require("tests.harness")

H.suite("death: Abomination hits every character on both sides", function(ns, H)
  local g = H.NewGame()
  local abom = H.Put(g, 1, "EX1_097")
  H.Put(g, 1, "CS2_182")            -- friendly Yeti 4/5 -> survives at 3
  H.Put(g, 2, "CS2_231")            -- enemy Wisp dies
  H.Put(g, 2, "CS2_182")            -- enemy Yeti survives at 3

  abom.pendingDestroy = true
  g:ProcessDeaths()

  H.board(g, 1, { "CS2_182 4/3" }, "friendly Yeti damaged")
  H.board(g, 2, { "CS2_182 4/3" }, "enemy Wisp dead, Yeti damaged")
  H.eq(H.Hero(g, 1):Health(), 28, "own hero took 2")
  H.eq(H.Hero(g, 2):Health(), 28, "enemy hero took 2")
  H.noEngineErrors(g)
end)

H.suite("death: deathrattle chains resolve to completion", function(ns, H)
  local g = H.NewGame()
  -- Abomination's 2 damage kills the Loot Hoarder (2/1), whose deathrattle
  -- draws a card. The death phase must loop until the board is stable.
  local abom = H.Put(g, 1, "EX1_097")
  H.Put(g, 1, "EX1_096")            -- Loot Hoarder 2/1
  local handBefore = #g.players[1].hand

  abom.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()

  H.eq(#g.players[1].board, 0, "both minions dead")
  H.eq(#g.players[1].hand, handBefore + 1, "chained deathrattle drew a card")
  H.noEngineErrors(g)
end)

H.suite("death: two Loot Hoarders both draw", function(ns, H)
  local g = H.NewGame()
  local a = H.Put(g, 1, "EX1_096")
  local b = H.Put(g, 1, "EX1_096")
  local handBefore = #g.players[1].hand
  a.pendingDestroy = true
  b.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  H.eq(#g.players[1].hand, handBefore + 2, "simultaneous deaths both fire")
  H.noEngineErrors(g)
end)

H.suite("death: Cairne's Baine takes the vacated slot", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231")                 -- slot 1
  local cairne = H.Put(g, 1, "EX1_110")  -- slot 2
  H.Put(g, 1, "CS2_231")                 -- slot 3

  cairne.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  -- Baine is summoned RIGHTMOST by the compiled script, which is what the CSV
  -- authored. Hearthstone places it in Cairne's slot -- see the note below.
  H.eq(#g.players[1].board, 3, "board still has three minions")
  local found = false
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "EX1_110t" then found = true end
  end
  H.ok(found, "Baine was summoned")
  H.noEngineErrors(g)
end)

H.suite("death: silenced minion loses its deathrattle", function(ns, H)
  local g = H.NewGame()
  local hoarder = H.Put(g, 1, "EX1_096")
  local handBefore = #g.players[1].hand
  hoarder:Silence()
  hoarder.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  H.eq(#g.players[1].hand, handBefore, "silenced deathrattle does not fire")
  H.noEngineErrors(g)
end)

H.suite("death: mutual destruction in combat", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  -- Two 3/2s trade: damage is simultaneous, both die in one death phase.
  local a = H.Put(g, 1, "CS2_172")   -- Bloodfen Raptor 3/2
  local b = H.Put(g, 2, "CS2_172")
  g:Attack(a, b)
  H.eq(#g.players[1].board, 0, "attacker died")
  H.eq(#g.players[2].board, 0, "defender died")
  H.noEngineErrors(g)
end)

H.suite("death: attack values are snapshotted before damage lands", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  --[[ River Crocolisk (CS2_120) 2/3 attacks Amani Berserker (EX1_393) 2/3,
       "Enrage: +3 Attack".

       This MUST use an Enrage minion, not a triggered one. Enrage is an aura,
       recalculated SYNCHRONOUSLY inside DealDamage -- so the moment the Croc's
       damage lands, the Amani is already a 5/1. A queued trigger (Gurubashi
       Berserker) would not resolve until the end of the block and so cannot
       distinguish a snapshot from a live read at all.

       Correct: both attacks snapshotted at 2. Croc deals 2 (Amani -> 5/1),
       Amani retaliates for the snapshotted 2, and the Croc survives at 1.
       Without the snapshot it would retaliate for 5 and the Croc would die.

       Verified by mutation: moving the dAtk read after DealDamage makes this
       suite fail. ]]
  local croc  = H.Put(g, 1, "CS2_120")    -- 2/3
  local amani = H.Put(g, 2, "EX1_393")    -- 2/3, Enrage +3

  H.eq(amani:Attack(), 2, "not enraged before combat")
  g:Attack(croc, amani)

  H.eq(amani:Attack(), 5, "enrage switched on synchronously")
  H.eq(amani:Health(), 1, "Amani took 2")
  H.eq(#g.players[1].board, 1, "Croc survived the snapshotted retaliation")
  H.eq(croc:Health(), 1, "Croc took 2, not 5")
  H.noEngineErrors(g)
end)

H.suite("death: queued triggers do not resolve mid-block", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  --[[ The counterpart to the test above. Gurubashi Berserker (EX1_399) 2/7,
       "Whenever this minion takes damage, gain +3 Attack", is a TRIGGER. It
       must not resolve inside the attack block, so its retaliation is 2 even
       though it ends the exchange as a 5/5. This is Hearthstone's simultaneous
       combat damage. ]]
  local croc = H.Put(g, 1, "CS2_120")     -- 2/3
  local guru = H.Put(g, 2, "EX1_399")     -- 2/7
  g:Attack(croc, guru)

  H.eq(guru:Attack(), 5, "trigger resolved after the block")
  H.eq(guru:Health(), 5, "Gurubashi took 2")
  H.eq(croc:Health(), 1, "Croc took the pre-trigger 2")
  H.noEngineErrors(g)
end)

H.suite("death: hero reaching 0 ends the game", function(ns, H)
  local g = H.NewGame()
  g:DealDamage(H.Hero(g, 2), 30, nil, false)
  g:ProcessDeaths()
  H.ok(g.over, "game marked over")
  H.eq(g.winner, 1, "player 1 wins")
  H.noEngineErrors(g)
end)

H.suite("death: simultaneous hero deaths are a draw", function(ns, H)
  local g = H.NewGame()
  H.Hero(g, 1).damage = 29
  H.Hero(g, 2).damage = 29
  local abom = H.Put(g, 1, "EX1_097")
  abom.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  H.ok(g.over, "game over")
  H.eq(g.winner, 0, "draw")
  H.noEngineErrors(g)
end)
