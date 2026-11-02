--[[ tests/test_determinism.lua -- lockstep safety.

  These are the tests that protect the networking layer. If they pass, two
  clients replaying the same action log from the same seed reach byte-identical
  state, which is what makes lockstep viable over a 255-byte channel: you send
  the actions, not the board.

  The most important one poisons math.random. Any engine code that reaches for
  it instead of Game:Random is a desync waiting for a busy board, and it would
  otherwise be invisible in single-client testing.
]]
local H = require("tests.harness")

H.suite("determinism: identical seeds produce identical shuffles", function(ns, H)
  local a = H.NewGame({ seed = 99991 })
  local b = H.NewGame({ seed = 99991 })
  local ha, sa = a:StateHash()
  local hb, sb = b:StateHash()
  H.eq(ha, hb, "state hash matches")
  H.eq(sa, sb, "state fingerprint matches")

  -- and the drawn cards are in the same order
  local ka, kb = {}, {}
  for i, e in ipairs(a.players[1].hand) do ka[i] = e.cardId end
  for i, e in ipairs(b.players[1].hand) do kb[i] = e.cardId end
  H.eq(table.concat(ka, ","), table.concat(kb, ","), "same opening hand")
end)

H.suite("determinism: different seeds diverge", function(ns, H)
  local a = H.NewGame({ seed = 1 })
  local b = H.NewGame({ seed = 2 })
  -- Not a strict requirement of correctness, but if these ever match the RNG
  -- is not actually consuming the seed.
  H.notOk(a.rngState == b.rngState, "rng state differs")
end)

H.suite("determinism: the same action log replays identically", function(ns, H)
  local function play(seed)
    local g = H.NewGame({ seed = seed })
    H.SetActive(g, 1)
    H.Mana(g, 1, 10)
    -- a sequence with several random decision points
    H.Put(g, 1, "NEW1_019")               -- Knife Juggler
    H.Put(g, 2, "CS2_119")
    H.Put(g, 2, "CS2_119")
    H.Put(g, 2, "CS2_231")
    g:Summon("CS2_231", 1, "RIGHTMOST")   -- knife at a random enemy
    g.bus:Drain()
    local i = H.Hand(g, 1, "EX1_277")     -- Arcane Missiles: 3 random hits
    g:PlayCard(1, i)
    g.bus:Drain()
    local j = H.Hand(g, 1, "EX1_538")     -- Unleash the Hounds
    g:PlayCard(1, j)
    g.bus:Drain()
    return g
  end
  local a, b = play(4242), play(4242)
  local ha, sa = a:StateHash()
  local hb, sb = b:StateHash()
  H.eq(sa, sb, "fingerprints identical after a randomised sequence")
  H.eq(ha, hb, "hashes identical")
  H.eq(a.rngCalls, b.rngCalls, "same number of RNG draws")
  H.ok(a.rngCalls > 4, "the sequence actually consumed randomness")
  H.noEngineErrors(a)
  H.noEngineErrors(b)
end)

H.suite("determinism: engine never calls math.random", function(ns, H)
  --[[ Poison the global. Every randomised path in the engine must route through
       Game:Random so that both clients draw from the same seeded stream in the
       same order. A stray math.random would work perfectly in solo testing and
       desync the moment two players had a busy board. ]]
  local realRandom, realSeed = math.random, math.randomseed
  local violations = 0
  math.random = function(...) violations = violations + 1; return 1 end
  math.randomseed = function() violations = violations + 1 end

  local ok, err = pcall(function()
    local g = H.NewGame({ seed = 7 })
    H.SetActive(g, 1)
    H.Mana(g, 1, 10)
    H.Put(g, 1, "NEW1_019")
    H.Put(g, 2, "CS2_119")
    H.Put(g, 2, "CS2_231")
    g:Summon("CS2_172", 1, "RIGHTMOST")
    g.bus:Drain()
    local i = H.Hand(g, 1, "EX1_277")
    g:PlayCard(1, i)
    g.bus:Drain()
    -- random target selection, random discard, shuffle, entourage
    local j = H.Hand(g, 1, "NEW1_031")    -- Animal Companion, random entourage
    g:PlayCard(1, j)
    g.bus:Drain()
    g:DiscardRandom(1)
    for _ = 1, 5 do g:Draw(1) end
    g:EndTurn()
  end)

  math.random, math.randomseed = realRandom, realSeed
  H.ok(ok, "engine ran without error: " .. tostring(err))
  H.eq(violations, 0, "math.random was never called")
end)

H.suite("determinism: selector candidate order is stable", function(ns, H)
  --[[ Selector.Resolve must build its candidate list in a fixed order before
       RNG touches it. If it ever iterated a hash table with pairs(), the order
       would be unspecified and could differ between clients even with the same
       seed. Resolving the same selector repeatedly must give the same order. ]]
  local g = H.NewGame({ seed = 55 })
  for _ = 1, 5 do H.Put(g, 2, "CS2_119") end
  local sel = { side = "ENEMY", type = "MINION" }
  local ctx = { controller = 1 }
  local first = {}
  for i, e in ipairs(ns.Selector.Resolve(g, sel, ctx)) do first[i] = e.instanceId end
  for _ = 1, 20 do
    local got = {}
    for i, e in ipairs(ns.Selector.Resolve(g, sel, ctx)) do got[i] = e.instanceId end
    H.eq(table.concat(got, ","), table.concat(first, ","), "stable candidate order")
  end
end)

H.suite("determinism: commit-reveal seed depends on both nonces", function(ns, H)
  local Game = ns.Game
  local s1 = Game.DeriveSeed("alice-nonce", "bob-nonce")
  local s2 = Game.DeriveSeed("alice-nonce", "bob-nonce")
  H.eq(s1, s2, "derivation is deterministic")

  local s3 = Game.DeriveSeed("alice-nonce", "bob-OTHER")
  H.notOk(s1 == s3, "changing one nonce changes the seed")
  local s4 = Game.DeriveSeed("bob-nonce", "alice-nonce")
  H.notOk(s1 == s4, "order matters, so neither side can mirror the other")
end)

H.suite("determinism: state hash is sensitive to board ORDER", function(ns, H)
  -- Positional adjacency is real gameplay, so two boards with the same minions
  -- in a different order are NOT the same state and must not hash alike.
  local a = H.NewGame({ seed = 3 })
  H.Put(a, 1, "CS2_182"); H.Put(a, 1, "CS2_231")
  local b = H.NewGame({ seed = 3 })
  H.Put(b, 1, "CS2_231"); H.Put(b, 1, "CS2_182")
  local ha = a:StateHash()
  local hb = b:StateHash()
  H.notOk(ha == hb, "different board order hashes differently")
end)
