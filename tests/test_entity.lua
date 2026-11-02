--[[ tests/test_entity.lua -- attribute layering.

  Every stat line asserted here was read from the pinned data:
    CS2_182 Chillwind Yeti     4 mana 4/5
    CS2_172 Bloodfen Raptor    2 mana 3/2  BEAST
    EX1_393 Amani Berserker    2 mana 2/3  Enrage +3 Attack
    CS2_231 Wisp               0 mana 1/1
]]
local H = require("tests.harness")

H.suite("entity: buffs stack on printed base", function(ns, H)
  local g = H.NewGame()
  local yeti = H.Put(g, 1, "CS2_182")
  H.eq(yeti:Attack(), 4, "printed attack")
  H.eq(yeti:MaxHealth(), 5, "printed health")

  yeti:AddEnchantment(2, 2)
  H.eq(yeti:Attack(), 6, "buffed attack")
  H.eq(yeti:MaxHealth(), 7, "buffed maxHP")
  H.eq(yeti:Health(), 7, "buffed current health")
  H.noEngineErrors(g)
end)

H.suite("entity: damage is independent of buffs", function(ns, H)
  local g = H.NewGame()
  -- A 3/2 that takes 1 damage then gains +0/+3 is a 3/5 with 1 damage = 4
  -- health. NOT 5. This is the ordering bug that a single mutable stat causes.
  local raptor = H.Put(g, 1, "CS2_172")
  g:DealDamage(raptor, 1, nil, false)
  H.eq(raptor:Health(), 1, "health after 1 damage")

  raptor:AddEnchantment(0, 3)
  H.eq(raptor:MaxHealth(), 5, "maxHP after +0/+3")
  H.eq(raptor:Health(), 4, "health keeps the damage")
  H.noEngineErrors(g)
end)

H.suite("entity: silence clears buffs and keeps current health when it fits", function(ns, H)
  local g = H.NewGame()
  local yeti = H.Put(g, 1, "CS2_182")
  yeti:AddEnchantment(2, 2)          -- 6/7
  g:DealDamage(yeti, 3, nil, false)  -- 6/4
  H.eq(yeti:Health(), 4, "health before silence")

  yeti:Silence()
  -- Health is lowered only if it is above the new maximum
  -- (hearthstone.wiki.gg/wiki/Health): 4 fits under 5, so it stays 4.
  H.eq(yeti:Attack(), 4, "attack after silence")
  H.eq(yeti:MaxHealth(), 5, "maxHP after silence")
  H.eq(yeti:Health(), 4, "current health kept")
  H.noEngineErrors(g)
end)

H.suite("entity: silence never kills a health-buffed minion", function(ns, H)
  local g = H.NewGame()
  -- It used to: maxHP 5 against 6 damage. Losing maximum Health lowers
  -- current Health only down to the new maximum, and "does not count as
  -- damage" -- so this Yeti is a 4/3, not a corpse.
  local yeti = H.Put(g, 1, "CS2_182")
  yeti:AddEnchantment(0, 4)          -- 4/9
  g:DealDamage(yeti, 6, nil, false)  -- 4/3
  yeti:Silence()
  H.notOk(yeti:IsDead(), "alive after silence")
  H.eq(yeti:Health(), 3, "still at 3 health")
  H.eq(yeti:MaxHealth(), 5, "of 5")
  g:ProcessDeaths()
  H.eq(#g.players[1].board, 1, "still on the board")
  H.noEngineErrors(g)
end)

H.suite("entity: silence lowers health that is above the new maximum", function(ns, H)
  local g = H.NewGame()
  local yeti = H.Put(g, 1, "CS2_182")
  yeti:AddEnchantment(0, 4)          -- 4/9, undamaged
  yeti:Silence()
  H.eq(yeti:Health(), 5, "full 9 drops to the new maximum of 5")
  H.notOk(yeti:IsDamaged(), "and it is not damaged")
  H.noEngineErrors(g)
end)

H.suite("entity: attack floors at zero, never negative", function(ns, H)
  local g = H.NewGame()
  local wisp = H.Put(g, 1, "CS2_231")     -- 1/1
  wisp:AddEnchantment(-5, 0)
  H.eq(wisp:Attack(), 0, "attack floored at 0")
  H.notOk(g:CanAttack(wisp), "0-attack minion cannot attack")
  H.noEngineErrors(g)
end)

H.suite("entity: enrage is a self-aura, not a one-shot trigger", function(ns, H)
  local g = H.NewGame()
  -- Amani Berserker 2/3, "Enrage: +3 Attack".
  local amani = H.Put(g, 1, "EX1_393")
  H.eq(amani:Attack(), 2, "unenraged attack")

  g:DealDamage(amani, 1, nil, false)
  H.eq(amani:Attack(), 5, "enraged attack")
  H.eq(amani:Health(), 2, "health while enraged")
  H.ok(amani.enraged, "enraged flag set")

  -- Healing must switch it OFF. A one-shot +3 on DAMAGE_DEALT would not, and
  -- the bug stays invisible until someone plays a healer.
  g:Heal(amani, 1, nil)
  H.eq(amani:Attack(), 2, "attack drops when healed to full")
  H.notOk(amani.enraged, "enraged flag cleared")
  H.noEngineErrors(g)
end)

H.suite("entity: silence removes enrage", function(ns, H)
  local g = H.NewGame()
  local amani = H.Put(g, 1, "EX1_393")
  g:DealDamage(amani, 1, nil, false)
  H.eq(amani:Attack(), 5, "enraged")
  amani:Silence()
  g:RecalcAuras()
  H.eq(amani:Attack(), 2, "silence removes the enrage bonus")
  H.noEngineErrors(g)
end)
