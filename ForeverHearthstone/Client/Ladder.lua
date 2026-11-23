--[[ Client/Ladder.lua

  THE BOT LADDER: Hearthstone's ranked ladder, played against the bots.

  The rules are the classic ladder's in its final form, before the 2020
  Leagues revamp (hearthstone.wiki.gg/wiki/Ranked/2013-2020, read
  2026-11-22). See docs/45-LADDER-DECKCODES-BULK-PACKS.md.

    * Ranks 25 (Angry Chicken) to 1 (Innkeeper), then Legend. The new-player
      ranks 50-26 (2018) are left out: this is the 2014 game, whose ladder
      starts at 25.
    * Stars per rank: 3 at ranks 25-16, 4 at 15-11, 5 at 10-1 (Feb 2019).
    * A win gives a star. A win that follows two ranked wins in a row gives a
      bonus star, below rank 5. A bonus earned at rank 6 can carry you into 5.
    * Filling a rank's stars and winning again moves you up with one star. At
      rank 1 that win is Legend.
    * A loss takes a star at rank 20 and above. Ranks 25-21 never lose stars.
      A loss at 0 stars drops you a rank, one star short of that rank's full.
    * Milestones at 20, 15, 10 and 5: once reached you never fall below them.
      Legend, once reached, is kept.
    * NO SEASONS. Hearthstone reset everyone each month; here a rank is yours
      to keep -- the owner's call (2026-11-23): "you shouldn't lose your
      rank". The record (wins, losses) is the ladder's whole history.

  WHO YOU MEET. Opponents are matched near your rank, and a bot's rank sets
  both halves of how good it is: the deck it brings (Client/BotDecks.lua tiers)
  and how hard it thinks (AI.SkillProfile). Ladder.Skill maps rank 25 to 1.0
  (a Novice with a Basic deck) and rank 1 to 5.0 (a Master with a top deck);
  Legend climbs past Master towards AI.LEGEND as the legend number falls.

  No WoW API here: every random roll is passed in, so the
  whole ladder runs headless (tests/test_ladder.lua).
]]
local ADDON, ns = ...

local Ladder = {}
ns.Ladder = Ladder

Ladder.LEGEND = 0
Ladder.BOTTOM = 25
Ladder.MILESTONES = { 20, 15, 10, 5 }
Ladder.STREAK_BONUS_BELOW = 5   -- the bonus star stops at rank 5

--[[ The rank names, and the card whose art each medal shows (the classic
     medals are each a minion's portrait). The Innkeeper is no card; its medal
     shows the tavern's hearth. Legend wears Deathwing. ]]
Ladder.RANKS = {
  [25] = { name = "Angry Chicken",         card = "EX1_009" },
  [24] = { name = "Leper Gnome",           card = "EX1_029" },
  [23] = { name = "Argent Squire",         card = "EX1_008" },
  [22] = { name = "Murloc Raider",         card = "CS2_168" },
  [21] = { name = "Southsea Deckhand",     card = "CS2_146" },
  [20] = { name = "Shieldbearer",          card = "EX1_405" },
  [19] = { name = "Novice Engineer",       card = "EX1_015" },
  [18] = { name = "Sorcerer's Apprentice", card = "EX1_608" },
  [17] = { name = "Tauren Warrior",        card = "EX1_390" },
  [16] = { name = "Questing Adventurer",   card = "EX1_044" },
  [15] = { name = "Silvermoon Guardian",   card = "EX1_023" },
  [14] = { name = "Raid Leader",           card = "CS2_122" },
  [13] = { name = "Dread Corsair",         card = "NEW1_022" },
  [12] = { name = "Warsong Commander",     card = "EX1_084" },
  [11] = { name = "Big Game Hunter",       card = "EX1_005" },
  [10] = { name = "Ogre Magi",             card = "CS2_197" },
  [9]  = { name = "Silver Hand Knight",    card = "CS2_151" },
  [8]  = { name = "Frostwolf Warlord",     card = "CS2_226" },
  [7]  = { name = "Sunwalker",             card = "EX1_032" },
  [6]  = { name = "Ancient of War",        card = "EX1_178" },
  [5]  = { name = "Sea Giant",             card = "EX1_586" },
  [4]  = { name = "Mountain Giant",        card = "EX1_105" },
  [3]  = { name = "Molten Giant",          card = "EX1_620" },
  [2]  = { name = "The Black Knight",      card = "EX1_002" },
  [1]  = { name = "Innkeeper",             card = nil },
  [0]  = { name = "Legend",                card = "NEW1_030" },
}

--- Stars a rank holds when full (Legend holds none).
function Ladder.Stars(rank)
  if rank == nil or rank <= 0 then return 0 end
  if rank >= 16 then return 3 end
  if rank >= 11 then return 4 end
  return 5
end

local function clampRank(r)
  r = math.floor(tonumber(r) or Ladder.BOTTOM)
  return math.max(0, math.min(Ladder.BOTTOM, r))
end

--[[ A fresh or loaded ladder record, repaired. Saved variables are user files,
     so every field is checked rather than trusted. ]]
function Ladder.Normalize(s)
  s = type(s) == "table" and s or {}
  s.rank = clampRank(s.rank)
  s.stars = math.max(0, math.min(Ladder.Stars(s.rank), math.floor(tonumber(s.stars) or 0)))
  s.streak = math.max(0, math.floor(tonumber(s.streak) or 0))
  s.best = clampRank(s.best or s.rank)
  if s.best > s.rank then s.best = s.rank end
  s.bestStars = math.max(0, math.floor(tonumber(s.bestStars) or 0))
  if s.best == s.rank and s.bestStars < s.stars then s.bestStars = s.stars end
  s.everBest = clampRank(s.everBest or s.best)
  if s.everBest > s.best then s.everBest = s.best end
  s.wins = math.max(0, math.floor(tonumber(s.wins) or 0))
  s.losses = math.max(0, math.floor(tonumber(s.losses) or 0))
  if s.rank == 0 then
    s.legend = math.max(1, math.floor(tonumber(s.legend) or 5000))
  else
    s.legend = nil
  end
  if s.bestLegend ~= nil then s.bestLegend = math.max(1, math.floor(tonumber(s.bestLegend) or 1)) end
  return s
end

--- A standing as one number: higher is better (Legend is above every rank).
function Ladder.Standing(rank, stars)
  local total = 0
  for r = Ladder.BOTTOM, (rank or 25) + 1, -1 do total = total + Ladder.Stars(r) end
  return total + (stars or 0)
end

--- The lowest rank this record may fall to (its best milestone reached).
function Ladder.Floor(s)
  if s.rank == 0 then return 0 end
  -- the best milestone reached: walk them from the top (5) down
  for i = #Ladder.MILESTONES, 1, -1 do
    local m = Ladder.MILESTONES[i]
    if s.best <= m then return m end
  end
  return Ladder.BOTTOM
end

local function noteBest(s)
  if s.rank < s.best or (s.rank == s.best and s.stars > s.bestStars) then
    s.best, s.bestStars = s.rank, s.stars
  end
  if s.rank < s.everBest then s.everBest = s.rank end
  if s.rank == 0 and (not s.bestLegend or s.legend < s.bestLegend) then s.bestLegend = s.legend end
end

-- `roll(a, b)` is an integer in [a, b]; math.random in game, a stub in tests.
local function defaultRoll(a, b) return math.random(a, b) end

--[[ Legend's number. Entering Legend lands you in the low thousands; each win
     climbs a share of the way up, each loss slips a little. A bot ladder has
     no region to rank against, so this is the ladder's own feel of it. ]]
function Ladder.EnterLegend(roll)
  roll = roll or defaultRoll
  return 1500 + roll(0, 1500)
end

local function legendAfter(n, won)
  if won then return math.max(1, n - math.max(1, math.floor(n * 0.08))) end
  return n + math.max(3, math.floor(n * 0.05))
end

--[[ One ranked game's result. Returns what changed, for the post-game screen:
     { won, before = {rank, stars, legend}, after = {...}, stars = +n/-n,
       bonus = true when a streak star was given, rankUp, rankDown, legend,
       floor = true when a milestone held you } ]]
function Ladder.Record(s, won, roll)
  Ladder.Normalize(s)
  local out = { won = won and true or false,
                before = { rank = s.rank, stars = s.stars, legend = s.legend } }
  if won then
    s.wins = s.wins + 1
    s.streak = s.streak + 1
    if s.rank == 0 then
      s.legend = legendAfter(s.legend, true)
    else
      local gain = 1
      if s.streak >= 3 and s.rank > Ladder.STREAK_BONUS_BELOW then
        gain = 2; out.bonus = true
      end
      out.stars = 0
      for _ = 1, gain do
        if s.rank == 0 then break end
        out.stars = out.stars + 1
        s.stars = s.stars + 1
        if s.stars > Ladder.Stars(s.rank) then
          if s.rank == 1 then
            s.rank, s.stars = 0, 0
            s.legend = Ladder.EnterLegend(roll)
            out.legend = true
          else
            s.rank, s.stars = s.rank - 1, 1
          end
          out.rankUp = true
        end
      end
    end
  else
    s.losses = s.losses + 1
    s.streak = 0
    if s.rank == 0 then
      s.legend = legendAfter(s.legend, false)
    elseif s.rank > 20 then
      out.stars = 0                          -- ranks 25-21 never lose stars
    elseif s.stars > 0 then
      s.stars = s.stars - 1; out.stars = -1
    elseif s.rank < Ladder.Floor(s) then
      s.rank = s.rank + 1
      s.stars = Ladder.Stars(s.rank) - 1
      out.stars = -1; out.rankDown = true
    else
      out.stars = 0; out.floor = true        -- a milestone holds you
    end
  end
  noteBest(s)
  out.after = { rank = s.rank, stars = s.stars, legend = s.legend }
  return out
end

-- ============================================================ opponents

--[[ How good a ladder bot is, as a continuous skill: 1.0 at rank 25, 5.0 at
     rank 1, then Legend from 5.4 up to 6.0 (AI.LEGEND) as its number falls to
     the top 100. ]]
function Ladder.Skill(rank, legend)
  rank = clampRank(rank)
  if rank == 0 then
    local n = math.max(1, tonumber(legend) or 5000)
    local t = math.max(0, math.min(1, (math.log(3000) - math.log(n)) / (math.log(3000) - math.log(100))))
    return 5.4 + 0.6 * t
  end
  return 1 + (Ladder.BOTTOM - rank) * 4 / (Ladder.BOTTOM - 1)
end

--[[ An opponent for this record: a rank within one of yours (stars as well),
     the skill that rank plays at, and the deck tier it brings -- the skill
     rounded up or down by its fraction, so rank 13 (skill 3.0) is a tier-3
     deck and rank 12 brings tier 3 two times in three and tier 4 the third. ]]
function Ladder.Opponent(s, roll)
  roll = roll or defaultRoll
  Ladder.Normalize(s)
  local foe = {}
  if s.rank == 0 then
    foe.rank = 0
    foe.legend = math.max(1, s.legend + roll(-math.max(5, math.floor(s.legend * 0.15)),
                                              math.max(5, math.floor(s.legend * 0.15))))
    foe.stars = 0
  else
    foe.rank = math.max(1, math.min(Ladder.BOTTOM, s.rank + roll(-1, 1)))
    foe.stars = roll(0, Ladder.Stars(foe.rank))
  end
  foe.skill = Ladder.Skill(foe.rank, foe.legend)
  local whole = math.floor(foe.skill)
  local frac = foe.skill - whole
  local tier = whole + ((roll(1, 1000) <= frac * 1000) and 1 or 0)
  foe.deckTier = math.max(1, math.min(ns.BotDecks and ns.BotDecks.TIERS or 5, tier))
  return foe
end

-- ============================================================ words

function Ladder.Name(rank) return (Ladder.RANKS[clampRank(rank)] or {}).name end

--- "Rank 14" or "Legend 1,204" (or plain "Legend" without a number).
function Ladder.Label(rank, legend)
  rank = clampRank(rank)
  if rank == 0 then
    if not legend then return "Legend" end
    local n = tostring(math.floor(legend))
    n = n:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return "Legend " .. n
  end
  return "Rank " .. rank
end

--- The single line a post-game screen shows for a result.
function Ladder.Describe(change)
  local a = change.after
  if change.legend then return "You reached Legend!" end
  if a.rank == 0 then
    local b = change.before.legend or a.legend
    return ("Legend %s (%s%d)"):format(Ladder.Label(0, a.legend):sub(8),
      a.legend <= b and "+" or "-", math.abs(b - a.legend))
  end
  if change.rankUp then return ("Rank %d: %s!"):format(a.rank, Ladder.Name(a.rank)) end
  if change.rankDown then return ("Down to rank %d"):format(a.rank) end
  if change.floor then return ("Rank %d holds: a milestone"):format(a.rank) end
  if change.bonus then return "Win streak! Bonus star" end
  if change.won then return ("Rank %d: star %d of %d"):format(a.rank, a.stars, Ladder.Stars(a.rank)) end
  if (change.stars or 0) == 0 then
    -- say why, or a player at rank 24 cannot tell protection from a bug
    if a.rank > 20 then return ("Rank %d: no stars lost (ranks 25-21 never lose stars)"):format(a.rank) end
    return ("Rank %d: no stars lost"):format(a.rank)
  end
  return ("Rank %d: lost a star"):format(a.rank)
end

--[[ THE POST-GAME MEDAL, step by step (Board:ShowLadderResult). From the
     standing before the game to the one after, one star at a time, as the
     classic ladder's rank screen played it:
       { rank, stars, legend, kind, star }
     kind: "gain" (star `star` lights), "rankup" (a new medal, its first star
     lit), "legend", "lose" (star `star` goes dark), "rankdown", "hold"
     (nothing moves: ranks 25-21 or a milestone), "legendmove" (the number). ]]
function Ladder.Steps(change)
  local b, a = change.before, change.after
  local steps = {}
  if b.rank == 0 then
    steps[1] = { rank = 0, stars = 0, legend = a.legend, kind = "legendmove" }
    return steps
  end
  local r, s = b.rank, b.stars
  if change.won then
    for _ = 1, (change.stars or 0) do
      s = s + 1
      if s > Ladder.Stars(r) then
        if r == 1 then
          steps[#steps + 1] = { rank = 0, stars = 0, legend = a.legend, kind = "legend" }
          break
        end
        r, s = r - 1, 1
        steps[#steps + 1] = { rank = r, stars = s, kind = "rankup", star = 1 }
      else
        steps[#steps + 1] = { rank = r, stars = s, kind = "gain", star = s }
      end
    end
  elseif (change.stars or 0) < 0 then
    if change.rankDown then
      steps[1] = { rank = a.rank, stars = a.stars, kind = "rankdown" }
    else
      steps[1] = { rank = r, stars = s - 1, kind = "lose", star = s }
    end
  end
  if #steps == 0 then steps[1] = { rank = a.rank, stars = a.stars, legend = a.legend, kind = "hold" } end
  return steps
end

return Ladder
