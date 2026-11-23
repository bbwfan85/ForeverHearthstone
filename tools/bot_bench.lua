--[[ tools/bot_bench.lua -- how much stronger is one practice-bot difficulty
     than another?

     luajit tools/bot_bench.lua <A> <B> [games] [tier] [offset] [extraA] [extraB] [bench]

       A, B     skills 1-6 (Novice .. Master, 6 Legend; fractions blend, docs/45)
       games    how many games (default 30); use an even number
       tier     the tier of deck BOTH sides bring (default 4)
       offset   shifts the seeds and class pairings, so several copies can run
                in parallel on different games and be added up
       extraA   profile settings for A only, "k=v,k=v" (w.<weight>=x scales a
                style weight): how Legend's ideas were tried against Master
       extraB   the same for B
       bench    "tierA=n,tierB=n" gives each side its own tier of deck (the
                ladder-realistic spot check: a rank brings its own tier), and
                "mull=0" skips the mulligan (on by default, as in a real game),
                and "real=1" brings what the ladder really deals: a deck picked
                at random from the tier and made a player's copy for that
                side's skill (BotDecks.Personalize), the same for both games
                of a pair; "vary=1" picks any deck of the tier (shared by
                both sides) instead of each class's first

     With one tier, both bots pilot the SAME two decks: A sits in seat 1 on odd
     games and seat 2 on even ones, with the same seed, so over each pair of
     games each bot has played each list from each seat. What is left is play
     skill (and the luck of the draw, which in Hearthstone is a lot -- run 200+
     games before believing a difference of a few points). With tierA/tierB the
     seats still swap, but each side keeps its own tier's deck of each class.

     Not part of the test suite: it is statistics, not a pass/fail fact. The
     numbers are in docs/45 ("Difficulty curve review"). ]]
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = require("tests.harness")
H.LoadEngine()
local ns = H.ns

local A, B = tonumber(arg[1]) or 5, tonumber(arg[2]) or 1
local N = tonumber(arg[3]) or 30
local tier = tonumber(arg[4]) or 4
local offset = tonumber(arg[5]) or 0
local function parse(s)
  local out = {}
  for k, v in (s or ""):gmatch("([%w%.]+)=([^,]+)") do
    local w = k:match("^w%.(.+)$")
    if w then out.wmul = out.wmul or {}; out.wmul[w] = tonumber(v)
    else out[k] = tonumber(v) or (v == "true") or v end
  end
  return out
end
local extraA, extraB, bench = parse(arg[6]), parse(arg[7]), parse(arg[8])
local tierA, tierB = bench.tierA or tier, bench.tierB or tier
local mull = bench.mull ~= 0

-- "log=1": print every move, for reading where a game was won and lost
local function find(g, id)
  for pi = 1, 2 do
    local p = g.players[pi]
    if p.hero.instanceId == id then return p.hero end
    for _, e in ipairs(p.board) do if e.instanceId == id then return e end end
  end
end
local function ent(g, e)
  if not e then return "?" end
  if e.printed.type == "HERO" then return "Hero" .. e.controller end
  return ("%s(%d/%d)"):format(e.printed.name, g:AttackValue(e), e:Health())
end
local function side(g, pi)
  local p, t = g.players[pi], {}
  for _, e in ipairs(p.board) do t[#t + 1] = ent(g, e) end
  local h = {}
  for _, c in ipairs(p.hand) do h[#h + 1] = c.printed.name end
  return ("P%d %d+%d mana %d/%d board{%s}%s hand{%s}"):format(pi, p.hero:Health(), p.hero.armor or 0,
    p.mana, p.maxMana, table.concat(t, ", "),
    p.weapon and (" wpn " .. p.weapon:Attack() .. "/" .. p.weapon:Health()) or "", table.concat(h, ", "))
end
local function describe(g, me, a)
  if a.kind == "PLAY_CARD" then
    local c = g.players[me].hand[a.handIndex]
    return "PLAY " .. (c and c.printed.name or "?") .. (a.targetId and (" -> " .. ent(g, find(g, a.targetId))) or "")
  elseif a.kind == "ATTACK" then
    return "ATTACK " .. ent(g, find(g, a.attackerId)) .. " -> " .. ent(g, find(g, a.targetId))
  elseif a.kind == "HERO_POWER" then
    return "POWER" .. (a.targetId and (" -> " .. ent(g, find(g, a.targetId))) or "")
  end
  return a.kind
end

local winsA, draws, t0 = 0, 0, os.clock()
local errors, unfinished = 0, 0
local classes = ns.BotDecks.Classes()
for i = 1, N do
  -- Both games in a seat-swapped pair must use the same classes AND seed.
  local pair = math.floor((i + 1) / 2)
  local c1 = classes[(pair - 1 + offset) % #classes + 1]
  local c2 = classes[(pair * 4 + offset * 2) % #classes + 1]
  local aSeat = (i % 2 == 1) and 1 or 2
  local t1 = (aSeat == 1) and tierA or tierB
  local t2 = (aSeat == 2) and tierA or tierB
  local d1, d2
  -- the same rolls for both games of a pair, so each side keeps its copy
  local function rolls(salt)
    local s = (pair * 7919 + offset * 104729 + salt) % 2147483648
    return function(a, b)
      s = (s * 1103515245 + 12345) % 2147483648
      return a + math.floor(s / 65536) % (b - a + 1)
    end
  end
  if bench.vary == 1 then
    -- any deck of the tier, not only the first: both games of a pair share it
    d1, d2 = ns.BotDecks.Pick(c1, t1, rolls(5)), ns.BotDecks.Pick(c2, t2, rolls(7))
  elseif bench.real == 1 then
    -- the tier's deck by class (shared when the tiers are), then each side's
    -- own copy of it for its skill
    local skill1 = (aSeat == 1) and A or B
    local skill2 = (aSeat == 2) and A or B
    d1 = ns.BotDecks.Personalize(ns.BotDecks.Pick(c1, t1, rolls(5)), skill1,
                                 rolls(aSeat == 1 and 11 or 23))
    d2 = ns.BotDecks.Personalize(ns.BotDecks.Pick(c2, t2, rolls(7)), skill2,
                                 rolls(aSeat == 2 and 13 or 29))
  else
    d1, d2 = ns.BotDecks.Pick(c1, t1), ns.BotDecks.Pick(c2, t2)
  end
  local decks = { d1, d2 }
  local seed = 1000 + offset * 997 + pair
  local g = ns.Game.New({ seed = seed, firstPlayer = 1,
    players = { { class = d1.class, deck = ns.BotDecks.Expand(d1) },
                { class = d2.class, deck = ns.BotDecks.Expand(d2) } } })
  local opts = {}
  -- a skill (AI.SkillProfile): 1-5 are the slider's levels, 6 Legend, fractions blend
  opts[aSeat] = { skill = A, style = decks[aSeat].style }
  for k, v in pairs(extraA) do opts[aSeat][k] = v end
  opts[3 - aSeat] = { skill = B, style = decks[3 - aSeat].style }
  for k, v in pairs(extraB) do opts[3 - aSeat][k] = v end
  if mull then
    g:Deal()
    for p = 1, 2 do ns.AI.Mulligan(g, p, nil, opts[p]) end
  else
    g:StartGame()
  end
  g.bus:Drain()
  for _ = 1, 150 do
    if g.over then break end
    local me = g.activePlayer
    local submit
    if bench.log == 1 then
      print(("-- turn %d %s"):format(g.turn, me == aSeat and "A" or "B"))
      print("   " .. side(g, me)); print("   " .. side(g, 3 - me))
      submit = function(a)
        local d = describe(g, me, a)
        local ok = ns.Actions.Run(g, me, a)
        print("   > " .. d .. (ok and "" or " (refused)"))
        return ok
      end
    end
    ns.AI.TakeTurn(g, me, submit, opts[me])
    if g.over then break end
    g:EndTurn(); g.bus:Drain()
  end
  if g.winner == aSeat then winsA = winsA + 1 elseif not g.winner then draws = draws + 1 end
  if #g.errors > 0 then errors=errors+#g.errors; print("engine error: " .. g.errors[1]) end
  if not g.over then unfinished=unfinished+1 end
  print(('game=%d pair=%d seed=%d classes=%s/%s Aseat=%d winner=%s turns=%d'):format(
    i,pair,seed,d1.class,d2.class,aSeat,tostring(g.winner),g.turn))
end
local name = function(d) return ns.AI.DIFFICULTIES[d] and ns.AI.DIFFICULTIES[d].name or tostring(d) end
print(("%s vs %s, tier %s/%s decks: %s won %d/%d (%.0f%%), %d drawn, %.1fs"):format(
  name(A), name(B), tostring(tierA), tostring(tierB), name(A), winsA, N, 100 * winsA / N, draws, os.clock() - t0))
print(('engine errors=%d unfinished=%d'):format(errors,unfinished))
if errors>0 or unfinished>0 then os.exit(1) end
