--[[ tests/test_primitives.lua -- the engine features added to unblock the
     remaining card pool.

  These test the PRIMITIVES, not the cards. Card behaviour is tested per class
  alongside the authored CSVs; what is checked here is that each new selector
  filter, amount form, op and condition does what the DSL promises, because
  every one of them is about to be relied on by a dozen cards at once.

  Fixtures, all verified against the pin:
    CS2_182  Chillwind Yeti       4 mana 4/5 vanilla
    CS2_231  Wisp                 0 mana 1/1 vanilla
    CS2_200  Boulderfist Ogre     6 mana 6/7 vanilla
    CS2_119  Oasis Snapjaw        4 mana 2/7 BEAST
    FP1_024  Voidcaller?          -- not used; see below
    GVG_082  Clockwork Gnome      1 mana 2/1 MECHANICAL, Deathrattle
    EX1_506  Murloc Tidehunter    2 mana 2/1 MURLOC, Battlecry
    CS2_173  Bluegill Warrior     2 mana 2/1 MURLOC, Charge
    CS2_189  Elven Archer         1 mana 1/1 Battlecry
    EX1_011  Voodoo Doctor        1 mana 2/1 Battlecry
]]
local H = require("tests.harness")

--============================================================ selector filters

H.suite("selector: deathrattle filter finds printed AND granted deathrattles", function(ns, H)
  local g = H.NewGame()
  local gnome = H.Put(g, 1, "GVG_082")        -- Clockwork Gnome, printed Deathrattle
  local yeti  = H.Put(g, 1, "CS2_182")        -- no deathrattle
  local found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", type = "MINION", hasDeathrattle = true },
    { source = yeti, controller = 1 })
  H.eq(#found, 1, "only the Gnome matches")
  H.eq(found[1], gnome, "and it is the Gnome")

  -- A GRANTED deathrattle counts too: Scarlet Purifier hits a minion that was
  -- given one by Ancestral Spirit.
  yeti.deathrattles[#yeti.deathrattles + 1] = { { op = "Draw", count = 1 } }
  found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", type = "MINION", hasDeathrattle = true },
    { source = yeti, controller = 1 })
  H.eq(#found, 2, "the granted deathrattle now matches as well")
end)

H.suite("selector: battlecry filter reads printed data, so it works in HAND", function(ns, H)
  --[[ Nerub'ar Weblord taxes Battlecry minions IN HAND, where no script is
       attached yet -- so this filter must read the printed tag, not the live
       entity. That is the whole reason it is separate from the deathrattle one. ]]
  local g = H.NewGame()
  H.Hand(g, 1, "CS2_189")                     -- Elven Archer, Battlecry
  H.Hand(g, 1, "CS2_182")                     -- Chillwind Yeti, vanilla
  local found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", zone = "HAND", type = "MINION", hasBattlecry = true },
    { controller = 1 })
  H.eq(#found, 1, "only the Battlecry minion in hand matches")
  H.eq(found[1].cardId, "CS2_189", "and it is the Elven Archer")
end)

H.suite("selector: negative race excludes, and is not confused with a keyword", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "GVG_082")                      -- Clockwork Gnome, MECHANICAL
  local yeti = H.Put(g, 1, "CS2_182")         -- no race
  local snap = H.Put(g, 1, "CS2_119")         -- BEAST
  local found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", type = "MINION", notRace = "MECHANICAL" },
    { controller = 1 })
  H.eq(#found, 2, "the Mech is excluded")
  H.eq(found[1], yeti, "raceless minions are NOT excluded")
  H.eq(found[2], snap, "and neither is another race")
end)

H.suite("selector: cardId filter matches one printed card", function(ns, H)
  -- How Feugen asks whether Stalagg died: a graveyard query for one id.
  local g = H.NewGame()
  H.Put(g, 1, "CS2_182")
  local wisp = H.Put(g, 1, "CS2_231")
  local found = ns.Selector.Resolve(g,
    { side = "FRIENDLY", type = "MINION", cardId = "CS2_231" },
    { controller = 1 })
  H.eq(#found, 1, "one match")
  H.eq(found[1], wisp, "and it is the right card")
end)

--============================================================ amount forms

H.suite("amounts: a rolled range stays inside its bounds and uses the seed", function(ns, H)
  --[[ Crackle is $3-$6. The roll must come from the shared stream or the two
       clients disagree about how much damage was dealt, which is a desync in
       the most visible possible place. ]]
  local seen = {}
  for seed = 1, 60 do
    local g = H.NewGame({ seed = seed })
    local ogre = H.Put(g, 2, "CS2_200")
    local n = ns.Ops.Amount(g, { amount = { min = 3, max = 6 } },
                            { source = ogre, controller = 1 })
    H.ok(n >= 3 and n <= 6, "roll " .. n .. " is within 3..6")
    seen[n] = true
  end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  H.eq(distinct, 4, "all four values in 3..6 are reachable")

  -- Same seed, same roll: this is the lockstep guarantee.
  local function roll()
    local g = H.NewGame({ seed = 4242 })
    return ns.Ops.Amount(g, { amount = { min = 2, max = 4 } }, { controller = 1 })
  end
  H.eq(roll(), roll(), "the same seed rolls the same number")
end)

H.suite("amounts: a range is rolled ONCE per op, not once per target", function(ns, H)
  --[[ Lightning Storm deals $2-$3 to ALL enemy minions -- one roll applied to
       every minion, not a separate roll each. Three identical minions must
       therefore end on identical health. ]]
  local g = H.NewGame({ seed = 7 })
  local a = H.Put(g, 2, "CS2_200")
  local b = H.Put(g, 2, "CS2_200")
  local c = H.Put(g, 2, "CS2_200")
  ns.Ops.Run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION" },
                    amount = { min = 2, max = 3 } } },
             { source = H.Hero(g, 1), controller = 1 })
  g.bus:Drain()
  H.eq(a:Health(), b:Health(), "first two took the same damage")
  H.eq(b:Health(), c:Health(), "and so did the third")
  H.ok(a:Health() == 5 or a:Health() == 4, "and it was 2 or 3")
end)

H.suite("amounts: healthOf and damageOf read what they say", function(ns, H)
  local g = H.NewGame()
  local ogre = H.Put(g, 2, "CS2_200")         -- 6/7
  local ctx = { source = ogre, controller = 1 }
  H.eq(ns.Ops.Amount(g, { amount = { healthOf = { self = true } } }, ctx), 7,
       "healthOf is current health")

  local hero = H.Hero(g, 1)
  g:DealDamage(hero, 9, nil, false)
  g.bus:Drain()
  H.eq(ns.Ops.Amount(g, { amount = {
         damageOf = { side = "FRIENDLY", type = "HERO", hero = true } } },
       { source = ogre, controller = 1 }), 9,
       "damageOf is damage TAKEN, which is what Molten Giant reads")
  -- and healing reduces it again
  g:Heal(hero, 4, nil)
  g.bus:Drain()
  H.eq(ns.Ops.Amount(g, { amount = {
         damageOf = { side = "FRIENDLY", type = "HERO", hero = true } } },
       { source = ogre, controller = 1 }), 5, "healing reduces damage taken")
end)

--============================================================ damage outcome

H.suite("damage outcome: killed vs survived, and Divine Shield counts as survived", function(ns, H)
  --[[ Mortal Coil's real trap. A 1-health minion behind a Divine Shield takes
       the hit, loses the shield and LIVES, so no card is drawn -- if the flag
       were set from the damage number instead of the resulting health, this
       would wrongly draw. ]]
  local g = H.NewGame()
  local hero = H.Hero(g, 1)

  local wisp = H.Put(g, 2, "CS2_231")         -- 1/1
  local ctx = { source = hero, controller = 1 }
  ns.Ops.Run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION" }, amount = 1 } }, ctx)
  H.eq(ctx.damageKilled, true, "a lethal hit records a kill")

  local ogre = H.Put(g, 2, "CS2_200")         -- 6/7
  local ctx2 = { source = hero, controller = 1 }
  ns.Ops.Run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION" }, amount = 1 } }, ctx2)
  H.eq(ctx2.damageKilled, false, "a survivable hit records a survival")
  g.bus:Drain()

  local shielded = H.Put(g, 2, "CS2_231")
  shielded.divineShieldUp = true
  shielded.baseKeywords[ns.KEYWORD.DIVINE_SHIELD] = true
  local ctx3 = { source = hero, controller = 1 }
  ns.Ops.Run(g, { { op = "Damage", sel = { side = "ENEMY", type = "MINION",
                                           keyword = ns.KEYWORD.DIVINE_SHIELD },
                    amount = 1 } }, ctx3)
  H.eq(ctx3.damageKilled, false, "Divine Shield absorbed it, so it SURVIVED")
  H.ok(shielded.zone == ns.ZONE.PLAY, "and the minion is still there")
end)

H.suite("damage outcome: an unset flag draws nothing rather than always", function(ns, H)
  -- A malformed script with no damage op must fail closed.
  local g = H.NewGame()
  local ctx = { source = H.Hero(g, 1), controller = 1 }
  H.notOk(ns.Conditions.Eval(g, { c = "DamageKilled" }, ctx), "killed is false")
  H.notOk(ns.Conditions.Eval(g, { c = "DamageSurvived" }, ctx), "survived is false too")
end)

--============================================================ stat arithmetic

H.suite("stats: doubling ADDS the current value, it does not multiply forever", function(ns, H)
  --[[ Divine Spirit on a 6/7 makes it 6/14 by adding 7. Doubling twice gives
       6/28, and a later change does not re-double -- it is an enchantment of a
       value read once, which is what makes Divine Spirit into Inner Fire work. ]]
  local g = H.NewGame()
  local ogre = H.Put(g, 2, "CS2_200")         -- 6/7
  local ctx = { source = H.Hero(g, 1), controller = 1, target = ogre }
  ns.Ops.Run(g, { { op = "DoubleHealth", sel = { target = true } } }, ctx)
  H.eq(ogre:Health(), 14, "health doubled once")
  ns.Ops.Run(g, { { op = "DoubleHealth", sel = { target = true } } }, ctx)
  H.eq(ogre:Health(), 28, "and again")

  ns.Ops.Run(g, { { op = "DoubleAttack", sel = { target = true } } }, ctx)
  H.eq(g:AttackValue(ogre), 12, "attack doubled")
  H.eq(ogre:Health(), 28, "and health was not touched")
end)

H.suite("stats: doubling health on a DAMAGED minion doubles current health", function(ns, H)
  -- A 6/7 that has taken 4 is at 3; Divine Spirit makes it 6/6 with 4 damage
  -- still on it, i.e. current health 6 -- not 14.
  local g = H.NewGame()
  local ogre = H.Put(g, 2, "CS2_200")
  g:DealDamage(ogre, 4, nil, false)
  g.bus:Drain()
  H.eq(ogre:Health(), 3, "damaged to 3")
  ns.Ops.Run(g, { { op = "DoubleHealth", sel = { target = true } } },
             { source = H.Hero(g, 1), controller = 1, target = ogre })
  H.eq(ogre:Health(), 6, "doubled from 3, not from 7")
end)

H.suite("stats: SwapHealth moves health and clears the damage with it", function(ns, H)
  --[[ Vol'jin swaps CURRENT health. A damaged minion that swaps into a bigger
       body comes out at full health -- the damage does not follow it. ]]
  local g = H.NewGame()
  local voljin = H.Put(g, 1, "GVG_014")       -- 6/2
  local ogre   = H.Put(g, 2, "CS2_200")       -- 6/7
  g:DealDamage(ogre, 3, nil, false)
  g.bus:Drain()
  H.eq(ogre:Health(), 4, "the Ogre is at 4")

  ns.Ops.Run(g, { { op = "SwapHealth", sel = { target = true } } },
             { source = voljin, controller = 1, target = ogre })
  H.eq(voljin:Health(), 4, "Vol'jin took the Ogre's current health")
  H.eq(ogre:Health(), 2, "and the Ogre took Vol'jin's")
  H.eq(voljin.damage, 0, "no damage carried across")
  H.eq(ogre.damage, 0, "on either side")
  H.eq(g:AttackValue(voljin), 6, "attack is untouched")
  H.eq(g:AttackValue(ogre), 6, "on both")
end)

H.suite("stats: SwapHealth is right when the SOURCE is damaged too", function(ns, H)
  --[[ With an undamaged source, reading Health() and MaxHealth() give the same
       answer, so that case cannot tell a correct implementation from one that
       leaves the damaged side short by its damage. Both sides are damaged here
       precisely so it can. ]]
  local g = H.NewGame()
  local voljin = H.Put(g, 1, "GVG_014")       -- 6/2
  local ogre   = H.Put(g, 2, "CS2_200")       -- 6/7
  g:DealDamage(voljin, 1, nil, false)         -- -> 1
  g:DealDamage(ogre, 3, nil, false)           -- -> 4
  g.bus:Drain()
  H.eq(voljin:Health(), 1, "Vol'jin is at 1")
  H.eq(ogre:Health(), 4, "the Ogre is at 4")

  ns.Ops.Run(g, { { op = "SwapHealth", sel = { target = true } } },
             { source = voljin, controller = 1, target = ogre })
  H.eq(voljin:Health(), 4, "Vol'jin took the Ogre's 4")
  H.eq(ogre:Health(), 1, "and the Ogre took Vol'jin's 1")
  H.eq(voljin:MaxHealth(), 4, "max health moved with it")
  H.eq(ogre:MaxHealth(), 1, "on both sides")
  H.noEngineErrors(g)
end)

--============================================================ dynamic auras

H.suite("auras: a dynamic magnitude is re-read on every rebuild", function(ns, H)
  --[[ Mountain Giant. Because the aura layer is rebuilt from zero, the cost
       simply tracks the hand -- there is nothing to invalidate. ]]
  local g = H.NewGame()
  local p = g.players[1]
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end

  local _, giant = H.Hand(g, 1, "EX1_105")    -- Mountain Giant, printed cost 12
  g:RecalcAuras()
  H.eq(giant:Cost(), 12, "alone in hand it costs full price")

  for _ = 1, 4 do H.Hand(g, 1, "CS2_231") end
  g:RecalcAuras()
  H.eq(giant:Cost(), 8, "four other cards in hand take four off")

  table.remove(p.hand)
  g:RecalcAuras()
  H.eq(giant:Cost(), 9, "playing one puts a point back")

  -- and it never goes below zero, even at a full ten-card hand
  while #p.hand < ns.RULES.HAND_LIMIT do H.Hand(g, 1, "CS2_231") end
  g:RecalcAuras()
  H.ok(giant:Cost() >= 0, "cost never goes negative")
end)

H.suite("auras: a hand-hosted aura reaches ONLY its own card", function(ns, H)
  --[[ The Giants are allowed to discount themselves from hand. Nothing else in
       hand may project an aura at all -- if hand cards were general aura
       sources, Sorcerer's Apprentice would discount your spells while still
       sitting in your hand, which is not the card. ]]
  local g = H.NewGame()
  local p = g.players[1]
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end

  local _, giant = H.Hand(g, 1, "EX1_105")    -- Mountain Giant, a self-cost aura
  local _, yeti  = H.Hand(g, 1, "CS2_182")    -- printed cost 4
  local _, wisp  = H.Hand(g, 1, "CS2_231")    -- printed cost 0
  g:RecalcAuras()
  H.eq(yeti:Cost(), 4, "the Giant's aura did not touch another card in hand")
  H.eq(wisp:Cost(), 0, "nor a second one")
  H.eq(giant:Cost(), 10, "while the Giant itself is discounted by the two")

  -- and a NON-self aura sitting in hand must project nothing at all
  local _, apprentice = H.Hand(g, 1, "EX1_608")   -- Sorcerer's Apprentice
  local _, bolt = H.Hand(g, 1, "CS2_024")         -- Frostbolt, printed cost 2
  g:RecalcAuras()
  H.eq(bolt:Cost(), 2, "a spell is NOT discounted by an Apprentice still in hand")
  H.noEngineErrors(g)
end)

H.suite("auras: Old Murk-Eye counts other Murlocs on BOTH sides", function(ns, H)
  local g = H.NewGame()
  local murkeye = H.Put(g, 1, "EX1_062")      -- 2/4 Charge
  g:RecalcAuras()
  H.eq(g:AttackValue(murkeye), 2, "alone it is a 2/4")

  H.Put(g, 1, "CS2_173")                      -- friendly Murloc
  g:RecalcAuras()
  H.eq(g:AttackValue(murkeye), 3, "+1 for a friendly Murloc")

  H.Put(g, 2, "CS2_173")                      -- enemy Murloc
  g:RecalcAuras()
  H.eq(g:AttackValue(murkeye), 4, "+1 for an ENEMY Murloc too")

  H.Put(g, 1, "CS2_182")                      -- not a Murloc
  g:RecalcAuras()
  H.eq(g:AttackValue(murkeye), 4, "a non-Murloc adds nothing")
end)

H.suite("auras: Molten Giant tracks damage taken, and healing puts it back", function(ns, H)
  local g = H.NewGame()
  local _, giant = H.Hand(g, 1, "EX1_620")    -- printed cost 20
  g:RecalcAuras()
  H.eq(giant:Cost(), 20, "undamaged it costs 20")

  g:DealDamage(H.Hero(g, 1), 12, nil, false)
  g.bus:Drain()
  g:RecalcAuras()
  H.eq(giant:Cost(), 8, "twelve damage takes twelve off")

  g:Heal(H.Hero(g, 1), 5, nil)
  g.bus:Drain()
  g:RecalcAuras()
  H.eq(giant:Cost(), 13, "healing five puts five back")
end)

--============================================================ MyTurn

H.suite("conditions: MyTurn distinguishes the two turn-end events", function(ns, H)
  local g = H.NewGame()
  local cannon = H.Put(g, 1, "GVG_020")
  local ctx = { source = cannon, controller = 1 }
  g.activePlayer = 1
  H.ok(ns.Conditions.Eval(g, { c = "MyTurn" }, ctx), "true on its owner's turn")
  g.activePlayer = 2
  H.notOk(ns.Conditions.Eval(g, { c = "MyTurn" }, ctx), "false on the opponent's")
end)

--============================================================ card pool

H.suite("cardpool: queries are sorted, so a seeded roll is reproducible", function(ns, H)
  --[[ THE critical property of Engine/CardPool.lua. ns.PrintedCards is a hash
       table and Lua's pairs() order is unspecified -- it can differ between two
       runs of the same build. If a query fed pairs() order to the RNG, two
       clients would generate DIFFERENT cards from the same seed, intermittently.
       So: the list must be sorted, and the same seed must produce the same card. ]]
  local ids = ns.CardPool.Query({ type = "MINION" })
  H.ok(#ids > 100, "the minion pool is large (" .. #ids .. ")")
  local sorted = true
  for i = 2, #ids do
    if ids[i - 1] >= ids[i] then sorted = false break end
  end
  H.ok(sorted, "the pool is strictly sorted by id")

  local function pick(seed)
    local g = H.NewGame({ seed = seed })
    return ns.CardPool.Random(g, { type = "MINION" })
  end
  H.eq(pick(31337), pick(31337), "the same seed picks the same card")
  local a, b = pick(1), pick(2)
  H.ok(a ~= nil and b ~= nil, "both rolls produced a card")
end)

H.suite("cardpool: only COLLECTIBLE cards are generated, never tokens", function(ns, H)
  --[[ A random minion can be a Chillwind Yeti but never a Panther token, even
       though both are minions in the same data file. ]]
  local ids = ns.CardPool.Query({ type = "MINION" })
  local seen = {}
  for _, id in ipairs(ids) do
    seen[id] = true
    H.ok(ns.PrintedCards[id].collectible, id .. " is collectible")
  end
  H.notOk(seen["EX1_160t"], "the Panther token is not in the pool")
  H.notOk(seen["EX1_573t"], "nor the Treant token")
  H.notOk(seen["CS2_231"] == nil, "but Wisp, which IS collectible, is")
end)

H.suite("cardpool: filters mean what they say", function(ns, H)
  local beasts = ns.CardPool.Query({ type = "MINION", race = "BEAST" })
  H.ok(#beasts > 5, "there are Beasts (" .. #beasts .. ")")
  for _, id in ipairs(beasts) do
    H.eq(ns.PrintedCards[id].race, "BEAST", id .. " is a Beast")
    H.eq(ns.PrintedCards[id].type, "MINION", id .. " is a minion")
  end

  local twos = ns.CardPool.Query({ type = "MINION", cost = 2 })
  H.ok(#twos > 5, "there are 2-cost minions (" .. #twos .. ")")
  for _, id in ipairs(twos) do
    H.eq(ns.PrintedCards[id].cost, 2, id .. " costs 2")
  end

  local legends = ns.CardPool.Query({ type = "MINION", rarity = "LEGENDARY" })
  H.ok(#legends > 5, "there are legendary minions (" .. #legends .. ")")
  for _, id in ipairs(legends) do
    H.eq(ns.PrintedCards[id].rarity, "LEGENDARY", id .. " is legendary")
  end

  local weapons = ns.CardPool.Query({ type = "WEAPON" })
  H.ok(#weapons > 3, "there are weapons (" .. #weapons .. ")")
  for _, id in ipairs(weapons) do
    H.eq(ns.PrintedCards[id].type, "WEAPON", id .. " is a weapon")
  end
end)

H.suite("cardpool: an empty pool yields nothing rather than erroring", function(ns, H)
  -- Fail closed: a filter nothing matches must not crash a card mid-resolution.
  local g = H.NewGame()
  H.eq(ns.CardPool.Count({ type = "MINION", cost = 99 }), 0, "no 99-cost minions")
  H.eq(ns.CardPool.Random(g, { type = "MINION", cost = 99 }), nil, "and no roll")
  H.noEngineErrors(g)
end)

H.suite("cardpool ops: generated cards land where they should", function(ns, H)
  local g = H.NewGame()
  local ctx = { source = H.Hero(g, 1), controller = 1 }

  local before = #g.players[1].hand
  ns.Ops.Run(g, { { op = "AddRandomCard", pool = { type = "MINION", race = "BEAST" } } }, ctx)
  H.eq(#g.players[1].hand, before + 1, "a card arrived in hand")
  local card = g.players[1].hand[#g.players[1].hand]
  H.eq(card.printed.race, "BEAST", "and it is a Beast")

  ns.Ops.Run(g, { { op = "SummonRandom", pool = { type = "MINION", cost = 2 } } }, ctx)
  g.bus:Drain()
  H.eq(#g.players[1].board, 1, "a minion was summoned")
  H.eq(g.players[1].board[1].printed.cost, 2, "and it costs 2")

  ns.Ops.Run(g, { { op = "EquipRandom", pool = {} } }, ctx)
  H.ok(g.players[1].weapon, "a weapon was equipped")
  H.eq(g.players[1].weapon.printed.type, "WEAPON", "and it is a weapon")
  H.noEngineErrors(g)
end)

H.suite("cardpool ops: a generated card can carry a cost discount", function(ns, H)
  -- Unstable Portal: "Add a random minion to your hand. It costs (3) less."
  local g = H.NewGame()
  local ctx = { source = H.Hero(g, 1), controller = 1 }
  ns.Ops.Run(g, { { op = "AddRandomCard", pool = { type = "MINION" }, costDelta = -3 } }, ctx)
  local card = g.players[1].hand[#g.players[1].hand]
  H.eq(card:Cost(), math.max(0, (card.printed.cost or 0) - 3),
       "the generated copy is three cheaper")
  -- and it discounts only THAT copy
  local other = select(2, H.Hand(g, 1, card.cardId))
  H.eq(other:Cost(), card.printed.cost, "another copy is full price")
  H.noEngineErrors(g)
end)

H.suite("cardpool ops: TransformRandom can follow the target's cost", function(ns, H)
  -- Recombobulator: "a random minion with the same Cost".
  local g = H.NewGame()
  local yeti = H.Put(g, 1, "CS2_182")          -- Chillwind Yeti, cost 4
  ns.Ops.Run(g, { { op = "TransformRandom", sel = { target = true },
                    pool = { type = "MINION" }, poolCost = "TARGET" } },
             { source = H.Hero(g, 1), controller = 1, target = yeti })
  g.bus:Drain()
  H.eq(g.players[1].board[1].printed.cost, 4, "it became another 4-cost minion")
  H.noEngineErrors(g)
end)

H.suite("cardpool ops: OneOf runs exactly one branch", function(ns, H)
  local g = H.NewGame()
  local hero2 = H.Hero(g, 2)
  local before = hero2:Health()
  ns.Ops.Run(g, { { op = "OneOf", branches = {
      { { op = "Damage", sel = { side = "ENEMY", hero = true, type = "HERO" }, amount = 1 } },
      { { op = "Damage", sel = { side = "ENEMY", hero = true, type = "HERO" }, amount = 2 } },
    } } }, { source = H.Hero(g, 1), controller = 1 })
  g.bus:Drain()
  local dealt = before - hero2:Health()
  H.ok(dealt == 1 or dealt == 2, "exactly one branch ran (dealt " .. dealt .. ")")

  -- both branches must be reachable across seeds
  local seen = {}
  for seed = 1, 40 do
    local gg = H.NewGame({ seed = seed })
    local h = H.Hero(gg, 2)
    local b = h:Health()
    ns.Ops.Run(gg, { { op = "OneOf", branches = {
        { { op = "Damage", sel = { side = "ENEMY", hero = true, type = "HERO" }, amount = 1 } },
        { { op = "Damage", sel = { side = "ENEMY", hero = true, type = "HERO" }, amount = 2 } },
      } } }, { source = H.Hero(gg, 1), controller = 1 })
    gg.bus:Drain()
    seen[b - h:Health()] = true
  end
  H.ok(seen[1] and seen[2], "both branches are reachable")
end)

--============================================================ summon position

H.suite("summon: summoning onto the OPPONENT's board does not use YOUR index", function(ns, H)
  --[[ Leeroy Jenkins summons two Whelps for the opponent. Ops.Summon always
       asks for "right of the source", and Game:ResolvePosition read the
       SOURCE's board index and applied it to the DESTINATION board, unclamped.
       On an empty enemy board that meant table.insert(board, 2, e) into a
       zero-length table, leaving a hole that Reindex then crashed on -- so the
       Whelps never arrived at all.

       "Right of the source" only means anything on the source's own board, so
       a cross-board summon now falls through to rightmost. ]]
  --[[ Driven at the OP level rather than by playing Leeroy, so this holds for
       every cross-board summon and does not depend on which cards happen to be
       authored. ]]
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231")
  local src = H.Put(g, 1, "CS2_231")        -- source sits at index 2...
  H.eq(src.boardIndex, 2, "the source is at index 2 on ITS board")
  H.eq(#g.players[2].board, 0, "...while the enemy board is EMPTY -- the crash case")

  ns.Ops.Run(g, { { op = "Summon", cardId = "EX1_116t", count = 2, side = "ENEMY" } },
             { source = src, controller = 1 })
  g.bus:Drain()
  H.eq(#g.players[2].board, 2, "both Whelps arrived for the opponent")
  H.eq(g.players[2].board[1].cardId, "EX1_116t", "and they are Whelps")
  H.eq(g.players[2].board[2].cardId, "EX1_116t", "both of them")
  for idx, e in ipairs(g.players[2].board) do
    H.eq(e.boardIndex, idx, "board index " .. idx .. " is intact, not a hole")
  end
  H.noEngineErrors(g)
end)

H.suite("summon: right-of-source still holds on the summoner's OWN board", function(ns, H)
  -- The fix must not flatten normal positional summons to rightmost.
  local g = H.NewGame()
  local left  = H.Put(g, 1, "CS2_182")
  local src   = H.Put(g, 1, "CS2_119")
  local right = H.Put(g, 1, "CS2_200")
  ns.Ops.Run(g, { { op = "Summon", cardId = "CS2_231" } },
             { source = src, controller = 1 })
  g.bus:Drain()
  H.eq(#g.players[1].board, 4, "the token arrived")
  H.eq(g.players[1].board[3].cardId, "CS2_231",
       "immediately to the RIGHT of the source, not at the end")
  H.eq(g.players[1].board[4], right, "and the old right-hand minion shifted along")
  H.noEngineErrors(g)
end)

--============================================================ later additions

H.suite("auras: a hand self-aura moves COST only, never the stat layers", function(ns, H)
  --[[ The Giants need a hand card to discount ITSELF, so hand cards are aura
       sources -- but only over cost. Lightspawn is why: its "Attack is always
       equal to its Health" is a self-aura too, and without this restriction the
       card reads as a 5/5 in hand instead of its printed 0/5.

       The aura is injected here rather than borrowed from an authored card, so
       the rule is tested rather than one card's spelling of it. ]]
  local g = H.NewGame()
  local p = g.players[1]
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
  local _, yeti = H.Hand(g, 1, "CS2_182")          -- printed 4/5, cost 4

  --[[ The injected aura carries cost AND stats deliberately. With only stats,
       the early-out in auraSources hides the projection, and with only cost the
       projection hides the early-out -- each guard masks the other and neither
       is really tested. Carrying both exercises the projection, which is the
       authoritative one. ]]
  local saved = ns.Scripts["CS2_182"]
  ns.Scripts["CS2_182"] = { aura = { sel = { self = true },
                                     cost = -2, atk = 5, hp = 5 } }
  g:RecalcAuras()
  H.eq(yeti:Cost(), yeti.printed.cost - 2, "the COST half of the aura applies")
  H.eq(yeti:Attack(), yeti.printed.atk, "but the stat half does NOT, in hand")
  H.eq(yeti:Health(), yeti.printed.hp, "on either stat")

  -- ...while on the BOARD the same aura moves the stats as normal.
  ns.Scripts["CS2_231"] = { aura = { sel = { self = true }, atk = 5, hp = 5 } }
  local wisp = H.Put(g, 1, "CS2_231")
  g:RecalcAuras()
  H.eq(wisp:Attack(), wisp.printed.atk + 5, "a board self-aura DOES move attack")
  ns.Scripts["CS2_231"] = nil

  ns.Scripts["CS2_182"] = saved
  g:RecalcAuras()
  H.eq(yeti:Cost(), yeti.printed.cost, "and restoring puts it back")
  H.noEngineErrors(g)
end)

H.suite("events: gaining Armor raises ARMOR_GAINED with the amount", function(ns, H)
  -- Siege Engine reacts to it; nothing raised an armor event before it existed.
  local g = H.NewGame()
  -- The bus has no subscribe API, so spy by wrapping Raise for this test.
  local seen = {}
  local realRaise = g.bus.Raise
  g.bus.Raise = function(self, ev, pl)
    if ev == ns.EVENT.ARMOR_GAINED then seen[#seen + 1] = pl end
    return realRaise(self, ev, pl)
  end

  ns.Ops.Run(g, { { op = "GainArmor",
                    sel = { side = "FRIENDLY", type = "HERO", hero = true },
                    amount = 3 } },
             { source = H.Hero(g, 1), controller = 1 })
  g.bus:Drain()
  H.eq(#seen, 1, "one armor event")
  H.eq(seen[1].amount, 3, "carrying the amount")
  H.eq(seen[1].player, 1, "and the player")
  H.eq(H.Hero(g, 1).armor, 3, "and the armor actually landed")

  -- a zero gain must not raise a spurious event
  ns.Ops.Run(g, { { op = "GainArmor",
                    sel = { side = "FRIENDLY", type = "HERO", hero = true },
                    amount = 0 } },
             { source = H.Hero(g, 1), controller = 1 })
  g.bus:Drain()
  H.eq(#seen, 1, "gaining nothing raises nothing")
  g.bus.Raise = realRaise
  H.noEngineErrors(g)
end)

H.suite("amounts: payloadAmount reads the EVENT, which `dealt` cannot", function(ns, H)
  --[[ Mistress of Pain heals for the damage it just dealt. A trigger runs with
       a FRESH ctx, so from its point of view that damage was never "the
       previous op" -- `dealt` is empty there and only the payload knows. ]]
  local g = H.NewGame()
  local ctx = { source = H.Hero(g, 1), controller = 1,
                payload = { amount = 7 } }
  H.eq(ns.Ops.Amount(g, { amount = { payloadAmount = true } }, ctx), 7,
       "it reads the payload's amount")
  H.eq(ns.Ops.Amount(g, { amount = { lastAmount = true } }, ctx), 0,
       "while `dealt` sees nothing, which is the whole reason it exists")
  H.eq(ns.Ops.Amount(g, { amount = { payloadAmount = true } },
                     { source = H.Hero(g, 1), controller = 1 }), 0,
       "and with no payload at all it is zero, not an error")
  H.noEngineErrors(g)
end)

--============================================== board-state play requirements

H.suite("play reqs: board-state requirements are enforced ON THE WAY IN", function(ns, H)
  --[[ Brawl carries REQ_MINIMUM_TOTAL_MINIONS = 2 in printed data. That was
       checked only by Targeting.CanPlay -- which the UI uses to GREY A CARD OUT
       -- and by nothing on the path into the engine.

       So the rule held for a human clicking a greyed card, and failed for
       everything else: the practice AI, a replayed action, and anything
       arriving over the wire could play Brawl into a single minion. That is
       exactly the shape of bug that shows up as a desync rather than as a
       visible mistake. ]]
  local g = H.NewGame({ class1 = "WARRIOR" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  H.Put(g, 1, "CS2_182")                 -- ONE minion in total, across both sides
  local i = H.Hand(g, 1, "EX1_407")      -- Brawl
  local card = g.players[1].hand[i]
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana

  H.notOk(ns.Targeting.CanPlay(g, card, 1), "the UI would grey it out...")
  local ok, why = g:PlayCard(1, i)
  H.notOk(ok, "...and the ENGINE refuses it too")
  H.eq(why, "REQ_MINIMUM_TOTAL_MINIONS", "naming the printed requirement")
  H.eq(#g.players[1].hand, handBefore, "the card stayed in hand")
  H.eq(g.players[1].mana, manaBefore, "and no mana was spent")

  -- with a second minion out it becomes legal
  H.Put(g, 2, "CS2_231")
  H.ok(ns.Targeting.CanPlay(g, card, 1), "a second minion makes it playable")
  H.ok(g:PlayCard(1, i), "and it plays")
  g.bus:Drain()
  H.eq(#g.players[1].board + #g.players[2].board, 1, "Brawl left exactly one")
  H.noEngineErrors(g)
end)

H.suite("play reqs: a card needing a free board slot is refused when full", function(ns, H)
  -- REQ_NUM_MINION_SLOTS, the same gap seen through a different requirement.
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  for _ = 1, ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  local i = H.Hand(g, 1, "EX1_160")      -- Power of the Wild; Panther mode needs a slot
  local ok, why = g:PlayCard(1, i, nil, nil, 2)
  H.notOk(ok, "the Panther mode is refused with a full board")
  H.eq(why, "REQ_NUM_MINION_SLOTS", "naming the printed requirement")
  H.ok(g:PlayCard(1, i, nil, nil, 1), "while the other mode is fine")
  H.noEngineErrors(g)
end)
