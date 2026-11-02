--[[ tests/test_weapons.lua -- weapons: equipping, battlecries, durability, buffs.

  Every test here is a REGRESSION for a bug found by authoring cards against the
  engine rather than by reading it. Three genuine engine bugs surfaced, and all
  three were silent -- the cards compiled, loaded, and did nothing:

    1. Game:PlayCard's WEAPON branch equipped the weapon and never ran
       script.battlecry, so Glaivezooka / Coghammer / Perdition's Blade were
       authored-but-dead data.
    2. Selector.orderedCandidates never enumerated player.weapon, so no selector
       could reach the equipped weapon -- "give your weapon +2 Attack" was
       inexpressible.
    3. Entity:MaxHealth floored at 1 for everything and ProcessDeaths scanned only
       the board, so a weapon losing its last durability to an EFFECT (rather than
       to an attack) stayed equipped forever.

  Pinned data:
    CS2_091  Light's Justice     1 mana 1/4  (no text)
    CS2_112  Arcanite Reaper     5 mana 5/2  (no text)
    GVG_043  Glaivezooka         2 mana 2/2  Battlecry: random friendly minion +1 Attack
    GVG_059  Coghammer           3 mana 2/3  Battlecry: random friendly minion Divine Shield + Taunt
    EX1_133  Perdition's Blade   3 mana 2/2  Battlecry: 1 damage; Combo: 2 instead
    EX1_366  Sword of Justice    3 mana 1/5  on summon: +1/+1 and lose 1 Durability
    CS2_074  Deadly Poison       1 mana      Give your weapon +2 Attack
]]
local H = require("tests.harness")

--============================================================== equipping

H.suite("weapon: equipping sets attack and durability from printed data", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "CS2_112")            -- Arcanite Reaper 5/2
  H.ok(g:PlayCard(1, i), "equipped")
  local w = g.players[1].weapon
  H.ok(w, "weapon present")
  H.eq(w:Attack(), 5, "attack from printed data")
  H.eq(w:Health(), 2, "durability from printed data")
  -- and the hero can now swing
  H.eq(g:AttackValue(H.Hero(g, 1)), 5, "hero gains the weapon's attack")
  H.ok(g:CanAttack(H.Hero(g, 1)), "hero can attack with a weapon")
  H.noEngineErrors(g)
end)

H.suite("weapon: equipping a second weapon replaces the first", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_091")))     -- Light's Justice 1/4
  H.eq(g.players[1].weapon:Attack(), 1, "first weapon")
  g:PlayCard(1, (H.Hand(g, 1, "CS2_112")))     -- Arcanite Reaper 5/2
  H.eq(g.players[1].weapon:Attack(), 5, "replaced by the second")
  H.eq(g.players[1].weapon:Health(), 2, "with its own durability")
  H.noEngineErrors(g)
end)

--=================================================== BUG 1: weapon battlecries

H.suite("weapon: a weapon BATTLECRY actually runs", function(ns, H)
  --[[ Regression. PlayCard's WEAPON branch used to equip and stop, so this
       battlecry never fired and the card was silently inert. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local minion = H.Put(g, 1, "CS2_182")        -- Chillwind Yeti 4/5
  H.eq(minion:Attack(), 4, "unbuffed")

  local i = H.Hand(g, 1, "GVG_043")            -- Glaivezooka
  H.ok(g:PlayCard(1, i), "played")
  g.bus:Drain()

  H.eq(g.players[1].weapon:Attack(), 2, "weapon equipped")
  H.eq(minion:Attack(), 5, "battlecry gave the minion +1 Attack")
  H.noEngineErrors(g)
end)

H.suite("weapon: Coghammer's battlecry grants keywords", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local minion = H.Put(g, 1, "CS2_182")
  H.notOk(minion:IsTaunt(), "no taunt to begin with")

  g:PlayCard(1, (H.Hand(g, 1, "GVG_059")))
  g.bus:Drain()
  H.ok(minion:IsTaunt(), "gained Taunt")
  H.ok(minion:Has(ns.KEYWORD.DIVINE_SHIELD), "gained Divine Shield")
  H.ok(minion.divineShieldUp, "and the shield is actually up")
  H.noEngineErrors(g)
end)

H.suite("weapon: a weapon COMBO replaces its battlecry", function(ns, H)
  -- Perdition's Blade: 1 damage normally, 2 with Combo.
  local function play(withCombo)
    local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
    H.SetActive(g, 1); H.Mana(g, 1, 10)
    local victim = H.Put(g, 2, "CS2_119")      -- Oasis Snapjaw 2/7
    if withCombo then
      g:PlayCard(1, (H.Hand(g, 1, "CS2_231"))) -- a Wisp first, to enable Combo
      g.bus:Drain()
    end
    g:PlayCard(1, (H.Hand(g, 1, "EX1_133")), victim)
    g.bus:Drain()
    return victim:Health(), g
  end
  local plain, g1 = play(false)
  local combo, g2 = play(true)
  H.eq(plain, 6, "1 damage without Combo")
  H.eq(combo, 5, "2 damage with Combo")
  H.noEngineErrors(g1)
  H.noEngineErrors(g2)
end)

--============================================ BUG 2: weapons are selectable

H.suite("weapon: a selector can reach the equipped weapon", function(ns, H)
  --[[ Regression. orderedCandidates never enumerated player.weapon, so
       `friendly.weapon` matched nothing and every weapon-buff card was
       inexpressible. Deadly Poison is the canonical case. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_091")))     -- Light's Justice 1/4
  g.bus:Drain()

  local found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", type = "WEAPON" }, { controller = 1 })
  H.eq(#found, 1, "the weapon is reachable")
  H.eq(found[1], g.players[1].weapon, "and it is the right entity")

  -- asking for type=WEAPON must imply the weapon zone, so authors need not know
  -- that weapons are not in the PLAY zone
  local none = ns.Selector.Resolve(g,
    { side = "ENEMY", type = "WEAPON" }, { controller = 1 })
  H.eq(#none, 0, "the opponent has no weapon")
  H.noEngineErrors(g)
end)

H.suite("weapon: buffing the weapon raises the hero's attack", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_091")))     -- 1 attack
  g.bus:Drain()
  H.eq(g:AttackValue(H.Hero(g, 1)), 1, "hero attack from the weapon")

  local w = g.players[1].weapon
  w:AddEnchantment(2, 0)                        -- as Deadly Poison would
  H.eq(w:Attack(), 3, "weapon buffed")
  H.eq(g:AttackValue(H.Hero(g, 1)), 3, "and the hero swings for 3")
  H.noEngineErrors(g)
end)

H.suite("weapon: a weapon selector does not accidentally match minions", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_182")
  H.Put(g, 1, "CS2_119")
  g:PlayCard(1, (H.Hand(g, 1, "CS2_091")))
  g.bus:Drain()
  local found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", type = "WEAPON" }, { controller = 1 })
  H.eq(#found, 1, "exactly the weapon, not the two minions")
  H.noEngineErrors(g)
end)

--=========================================== BUG 3: durability and breakage

H.suite("weapon: attacking costs one durability, and 0 breaks it", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_112")))     -- Arcanite Reaper 5/2
  g.bus:Drain()
  local hero = H.Hero(g, 1)

  g:Attack(hero, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(g.players[1].weapon:Health(), 1, "one durability spent")

  H.SetActive(g, 1)
  g:Attack(hero, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(g.players[1].weapon, nil, "weapon broke at zero durability")
  H.eq(g:AttackValue(hero), 0, "hero attack back to zero")
  H.noEngineErrors(g)
end)

H.suite("weapon: losing durability to an EFFECT also breaks it", function(ns, H)
  --[[ Regression for the subtlest of the three. MaxHealth floored at 1 for every
       entity type and ProcessDeaths scanned only the board, so a weapon reduced to
       0 durability by an effect (Sword of Justice's own trigger) stayed equipped
       forever at an impossible durability. ]]
  local g = H.NewGame({ firstPlayer = 1, class1 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_091")))     -- Light's Justice 1/4
  g.bus:Drain()
  local w = g.players[1].weapon
  H.eq(w:Health(), 4, "four durability")

  -- strip durability the way an effect would, not by attacking
  w:AddEnchantment(0, -4)
  H.eq(w:MaxHealth(), 0, "weapons are exempt from the floor-at-1")
  g:ProcessDeaths()
  H.eq(g.players[1].weapon, nil, "broke immediately")
  H.noEngineErrors(g)
end)

H.suite("weapon: a MINION is still floored at 1 maximum health", function(ns, H)
  -- The floor exemption must be weapon-only; minions keep the Hearthstone rule.
  local g = H.NewGame()
  local m = H.Put(g, 1, "CS2_182")             -- 4/5
  m:AddEnchantment(0, -99)
  H.eq(m:MaxHealth(), 1, "minion maximum health floored at 1, not 0")
  H.noEngineErrors(g)
end)

H.suite("weapon: Sword of Justice buffs a summon and spends durability", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "EX1_366")))     -- Sword of Justice 1/5
  g.bus:Drain()
  local w = g.players[1].weapon
  H.eq(w:Health(), 5, "five durability")

  g:Summon("CS2_231", 1, "RIGHTMOST")          -- a Wisp
  g.bus:Drain()
  local wisp = g.players[1].board[#g.players[1].board]
  H.eq(wisp:Attack(), 2, "Wisp buffed to 2 attack")
  H.eq(wisp:MaxHealth(), 2, "and 2 health")
  H.eq(g.players[1].weapon:Health(), 4, "one durability spent by the trigger")
  H.noEngineErrors(g)
end)

H.suite("weapon: Sword of Justice eventually breaks itself", function(ns, H)
  -- Five summons should consume all five durability and break the weapon, which
  -- was impossible before the floor and death-scan fixes.
  local g = H.NewGame({ firstPlayer = 1, class1 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "EX1_366")))
  g.bus:Drain()
  for _ = 1, 5 do
    g:Summon("CS2_231", 1, "RIGHTMOST")
    g.bus:Drain()
  end
  H.eq(g.players[1].weapon, nil, "spent all five durability and broke")
  H.noEngineErrors(g)
end)

H.suite("weapon: destroying a weapon clears the hero's attack", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1, class1 = "WARRIOR" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:PlayCard(1, (H.Hand(g, 1, "CS2_112")))
  g.bus:Drain()
  H.eq(g:AttackValue(H.Hero(g, 1)), 5, "armed")
  g:DestroyWeapon(1)
  H.eq(g.players[1].weapon, nil, "disarmed")
  H.eq(g:AttackValue(H.Hero(g, 1)), 0, "hero attack gone")
  H.notOk(g:CanAttack(H.Hero(g, 1)), "and cannot attack")
  H.noEngineErrors(g)
end)
