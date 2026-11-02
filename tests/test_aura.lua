--[[ tests/test_aura.lua -- continuous aura recalculation.

  Pinned stats used here:
    EX1_162 Dire Wolf Alpha  2 mana 2/2 BEAST  "Adjacent minions have +1 Attack"
    DS1_175 Timber Wolf      1 mana 1/1 BEAST  "Your other Beasts have +1 Attack"
    CS2_172 Bloodfen Raptor  2 mana 3/2 BEAST
    CS2_231 Wisp             0 mana 1/1 (no race)
]]
local H = require("tests.harness")

H.suite("aura: Dire Wolf Alpha buffs both neighbours only", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231")            -- slot 1
  H.Put(g, 1, "EX1_162")            -- slot 2, the wolf
  H.Put(g, 1, "CS2_231")            -- slot 3
  H.Put(g, 1, "CS2_231")            -- slot 4, NOT adjacent
  H.board(g, 1, { "CS2_231 2/1", "EX1_162 2/2", "CS2_231 2/1", "CS2_231 1/1" },
          "adjacent buffed, distant untouched")
  H.noEngineErrors(g)
end)

H.suite("aura: wolf dying removes the buff with no bookkeeping", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231")
  local wolf = H.Put(g, 1, "EX1_162")
  H.Put(g, 1, "CS2_231")
  H.board(g, 1, { "CS2_231 2/1", "EX1_162 2/2", "CS2_231 2/1" }, "buffed")

  wolf.pendingDestroy = true
  g:ProcessDeaths()
  H.board(g, 1, { "CS2_231 1/1", "CS2_231 1/1" }, "buff gone when source dies")
  H.noEngineErrors(g)
end)

H.suite("aura: silencing the source drops its aura", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231")
  local wolf = H.Put(g, 1, "EX1_162")
  H.Put(g, 1, "CS2_231")
  wolf:Silence()
  g:RecalcAuras()
  H.board(g, 1, { "CS2_231 1/1", "EX1_162 2/2", "CS2_231 1/1" },
          "silenced source grants nothing")
  H.noEngineErrors(g)
end)

H.suite("aura: adjacency follows board position, not play order", function(ns, H)
  local g = H.NewGame()
  local wolf = H.Put(g, 1, "EX1_162")          -- slot 1
  H.Put(g, 1, "CS2_231")                       -- slot 2 (adjacent)
  -- insert a Wisp to the LEFT of the wolf; it becomes adjacent even though it
  -- was played last
  H.Put(g, 1, "CS2_231", { index = 1 })
  H.eq(wolf.boardIndex, 2, "wolf shifted right")
  H.board(g, 1, { "CS2_231 2/1", "EX1_162 2/2", "CS2_231 2/1" },
          "both neighbours buffed after insertion")
  H.noEngineErrors(g)
end)

H.suite("aura: Timber Wolf excludes itself but stacks with another", function(ns, H)
  local g = H.NewGame()
  -- Two Timber Wolves: each buffs the OTHER (exclude SELF), so both are 2/1.
  H.Put(g, 1, "DS1_175")
  H.Put(g, 1, "DS1_175")
  H.board(g, 1, { "DS1_175 2/1", "DS1_175 2/1" }, "wolves buff each other")

  -- a Beast gets +2 (one from each wolf); a non-Beast gets nothing
  H.Put(g, 1, "CS2_172")      -- Bloodfen Raptor 3/2 BEAST -> 5/2
  H.Put(g, 1, "CS2_231")      -- Wisp 1/1, no race -> unchanged
  H.board(g, 1, { "DS1_175 2/1", "DS1_175 2/1", "CS2_172 5/2", "CS2_231 1/1" },
          "race filter and stacking")
  H.noEngineErrors(g)
end)

H.suite("aura: auras do not cross to the enemy board", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "DS1_175")      -- friendly-only aura
  H.Put(g, 2, "CS2_172")      -- enemy Beast
  H.board(g, 2, { "CS2_172 3/2" }, "enemy Beast unbuffed")
  H.noEngineErrors(g)
end)

H.suite("aura: rebuild is idempotent", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231")
  H.Put(g, 1, "EX1_162")
  -- Recalculating repeatedly must not accumulate. This is the single most
  -- important property of the rebuild-from-zero model.
  for _ = 1, 25 do g:RecalcAuras() end
  H.board(g, 1, { "CS2_231 2/1", "EX1_162 2/2" }, "no accumulation after 25 recalcs")
  H.noEngineErrors(g)
end)

H.suite("aura: enchantment survives the aura source dying", function(ns, H)
  local g = H.NewGame()
  local wisp = H.Put(g, 1, "CS2_231")
  local wolf = H.Put(g, 1, "EX1_162")
  wisp:AddEnchantment(1, 1)                  -- permanent +1/+1
  H.eq(wisp:Attack(), 3, "ench + aura")      -- 1 base + 1 ench + 1 aura
  wolf.pendingDestroy = true
  g:ProcessDeaths()
  H.eq(wisp:Attack(), 2, "aura gone, enchantment stays")
  H.eq(wisp:MaxHealth(), 2, "health enchantment stays")
  H.noEngineErrors(g)
end)
