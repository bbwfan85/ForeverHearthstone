--[[ tools/skill_probe.lua -- does each bot skill play like its level?

     luajit tools/skill_probe.lua [trials]

  Fixed puzzles, each with one clearly right answer, played `trials` times
  (default 40) at every skill from 1 (Novice / rank 25) to 6 (Legend). The
  board is the same each time; what varies is hidden state the bot cannot
  see (the opponent's hand size and the deck order), which changes its private
  randomness the way a real game would. The table is how often each level
  found the right play. Statistics, not a pass/fail test (docs/45). ]]
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = require("tests.harness")
H.LoadEngine()
local ns = H.ns
local TRIALS = tonumber(arg[1]) or 40

local function setup(trial, class1, class2)
  local g = H.NewGame({ seed = 1000 + trial * 7, class1 = class1 or "MAGE", class2 = class2 or "WARRIOR" })
  local p = g.players[1]
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
  -- what the bot cannot see: the opponent's hand size
  local foe = g.players[2]
  for i = #foe.hand, 1, -1 do table.remove(foe.hand, i) end
  for _ = 1, trial % 8 do g:AddToHand(2, "CS2_231") end
  -- ...and how many cards are left in each deck
  for _ = 1, math.floor(trial / 8) % 9 do table.remove(foe.deck) end
  for _ = 1, math.floor(trial / 72) % 5 do table.remove(p.deck) end
  g.activePlayer = 1
  p.heroPowerUsedThisTurn = true
  return g, p
end

local function onBoard(g, player, id)
  for _, e in ipairs(g.players[player].board) do if e.cardId == id then return e end end
end
local function inHand(g, player, id)
  for _, c in ipairs(g.players[player].hand) do if c.cardId == id then return true end end
end

local PUZZLES = {
  { name = "lethal on board (ignore the bait trade)", run = function(t)
      local g = setup(t)
      H.Mana(g, 1, 0)
      H.Put(g, 1, "CS2_182"); H.Put(g, 1, "CS2_182")     -- two 4/5
      H.Put(g, 2, "CS2_189")                             -- 2/1 bait
      H.Hero(g, 2).damage = 22                           -- 8 left
      return g, function() return g.winner == 1 end
    end },
  { name = "burn the Taunt, swing for lethal", run = function(t)
      local g = setup(t)
      H.Mana(g, 1, 4)
      H.Put(g, 1, "CS2_200"); H.Put(g, 2, "CS2_179")
      H.Hero(g, 2).damage = 24
      H.Hand(g, 1, "CS2_029")
      return g, function() return g.winner == 1 end
    end },
  { name = "Savage Roar combo lethal", run = function(t)
      local g = setup(t, "DRUID")
      H.Mana(g, 1, 3)
      for _ = 1, 3 do H.Put(g, 1, "CS2_231") end
      H.Hero(g, 2).damage = 21
      H.Hand(g, 1, "CS2_011")
      return g, function() return g.winner == 1 end
    end },
  { name = "spend all 5 mana well (Yeti + Archer)", run = function(t)
      local g = setup(t)
      H.Mana(g, 1, 5)
      H.Hand(g, 1, "CS2_189"); H.Hand(g, 1, "CS2_172"); H.Hand(g, 1, "CS2_182")
      return g, function() return g:AvailableMana(1) == 0 and onBoard(g, 1, "CS2_182") ~= nil end
    end },
  { name = "take the free trade", run = function(t)
      local g = setup(t)
      H.Mana(g, 1, 0)
      local yeti = H.Put(g, 1, "CS2_182")
      local archer = H.Put(g, 2, "CS2_189")
      return g, function() return archer.zone == ns.ZONE.GRAVEYARD and yeti.zone == ns.ZONE.PLAY end
    end },
  { name = "hold Fireball, not on a Wisp", run = function(t)
      local g = setup(t)
      H.Mana(g, 1, 4)
      H.Put(g, 2, "CS2_231")
      H.Hand(g, 1, "CS2_029")
      return g, function() return inHand(g, 1, "CS2_029") end
    end },
  { name = "Polymorph the 7/7 threat", run = function(t)
      local g = setup(t)
      H.Mana(g, 1, 4)
      local golem = H.Put(g, 2, "CS2_186")               -- War Golem 7/7
      H.Hero(g, 1).damage = 16                           -- under pressure
      H.Hand(g, 1, "CS2_022"); H.Hand(g, 1, "CS2_119")   -- Polymorph, Oasis Snapjaw
      -- Polymorph transforms the same minion: gone is "no War Golem on the board"
      return g, function() return golem.zone ~= ns.ZONE.PLAY or golem.cardId ~= "CS2_186" end
    end },
}

local SKILLS = { 1, 2, 3, 4, 5, 6 }
local NAMES = { "Novice r25", "Apprentice r19", "Adept r13", "Expert r7", "Master r1", "Legend" }
io.write(("%-40s"):format("puzzle"))
for i in ipairs(SKILLS) do io.write(("%15s"):format(NAMES[i])) end
io.write("\n")
local totals = {}
for _, pz in ipairs(PUZZLES) do
  io.write(("%-40s"):format(pz.name))
  for i, skill in ipairs(SKILLS) do
    local ok = 0
    for t = 1, TRIALS do
      local g, check = pz.run(t)
      ns.AI.ForgetPlan(g)
      ns.AI.TakeTurn(g, 1, nil, { skill = skill, style = "midrange" })
      if check() then ok = ok + 1 end
    end
    totals[i] = (totals[i] or 0) + ok
    io.write(("%14d%%"):format(math.floor(ok * 100 / TRIALS + 0.5)))
  end
  io.write("\n"); io.flush()
end
io.write(("%-40s"):format("ALL"))
for i in ipairs(SKILLS) do io.write(("%14d%%"):format(math.floor(totals[i] * 100 / (TRIALS * #PUZZLES) + 0.5))) end
io.write("\n")
