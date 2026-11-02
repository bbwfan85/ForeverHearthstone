--[[ tools/bot_bench.lua -- how much stronger is one practice-bot difficulty
     than another?

     luajit tools/bot_bench.lua <A> <B> [games] [tier] [offset]

       A, B     difficulties 1-5 (Novice .. Master)
       games    how many games (default 30); use an even number
       tier     the tier of deck BOTH sides bring (default 4)
       offset   shifts the seeds and class pairings, so several copies can run
                in parallel on different games and be added up

     Both bots pilot the SAME two decks: A sits in seat 1 on odd games and seat
     2 on even ones, with the same seed, so over each pair of games each bot has
     played each list from each seat. What is left is play skill (and the luck
     of the draw, which in Hearthstone is a lot -- run 100+ games before
     believing a difference of a few points).

     Not part of the test suite: it is statistics, not a pass/fail fact. The
     numbers it produced for the difficulty rework are in docs/26. ]]
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = require("tests.harness")
H.LoadEngine()
local ns = H.ns

local A, B = tonumber(arg[1]) or 5, tonumber(arg[2]) or 1
local N = tonumber(arg[3]) or 30
local tier = tonumber(arg[4]) or 4
local offset = tonumber(arg[5]) or 0

local winsA, draws, t0 = 0, 0, os.clock()
local errors, unfinished = 0, 0
local classes = ns.BotDecks.Classes()
for i = 1, N do
  -- Both games in a seat-swapped pair must use the same decks AND seed.
  local pair = math.floor((i + 1) / 2)
  local d1 = ns.BotDecks.Pick(classes[(pair - 1 + offset) % #classes + 1], tier)
  local d2 = ns.BotDecks.Pick(classes[(pair * 4 + offset * 2) % #classes + 1], tier)
  local aSeat = (i % 2 == 1) and 1 or 2
  local decks = { d1, d2 }
  local g = ns.Game.New({ seed = 1000 + offset * 997 + math.floor((i + 1) / 2), firstPlayer = 1,
    players = { { class = d1.class, deck = ns.BotDecks.Expand(d1) },
                { class = d2.class, deck = ns.BotDecks.Expand(d2) } } })
  g:StartGame(); g.bus:Drain()
  local opts = {}
  opts[aSeat] = { difficulty = A, style = decks[aSeat].style }
  opts[3 - aSeat] = { difficulty = B, style = decks[3 - aSeat].style }
  for _ = 1, 150 do
    if g.over then break end
    ns.AI.TakeTurn(g, g.activePlayer, nil, opts[g.activePlayer])
    if g.over then break end
    g:EndTurn(); g.bus:Drain()
  end
  if g.winner == aSeat then winsA = winsA + 1 elseif not g.winner then draws = draws + 1 end
  if #g.errors > 0 then errors=errors+#g.errors; print("engine error: " .. g.errors[1]) end
  if not g.over then unfinished=unfinished+1 end
  print(('game=%d pair=%d seed=%d classes=%s/%s Aseat=%d winner=%s turns=%d'):format(
    i,pair,1000+offset*997+pair,d1.class,d2.class,aSeat,tostring(g.winner),g.turn))
end
local name = function(d) return ns.AI.DIFFICULTIES[d] and ns.AI.DIFFICULTIES[d].name or tostring(d) end
print(("%s vs %s, tier %d decks: %s won %d/%d (%.0f%%), %d drawn, %.1fs"):format(
  name(A), name(B), tier, name(A), winsA, N, 100 * winsA / N, draws, os.clock() - t0))
print(('engine errors=%d unfinished=%d'):format(errors,unfinished))
if errors>0 or unfinished>0 then os.exit(1) end
