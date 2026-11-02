--[[ tests/test_release013.lua -- the rules review before 0.1.3 (docs/32).

  One suite per bug found. Each was reproduced against the engine before it was
  fixed, and each of these fails without its fix.
]]
local H = require("tests.harness")

-- Card ids by name, so a test reads as the card it is about.
local byName
local function ID(name)
  if not byName then
    byName = {}
    -- collectible first, then anything that is not a Naxxramas boss-fight copy
    local function rank(id, c)
      return (c.collectible and 4 or 0) + (id:find("^NAX") and 0 or 2)
             + (c.type == "HERO" and 0 or 1)
    end
    local ids = {}
    for id in pairs(H.ns.PrintedCards) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
      local c, cur = H.ns.PrintedCards[id], byName[H.ns.PrintedCards[id].name]
      if not cur or rank(id, c) > rank(cur, H.ns.PrintedCards[cur]) then
        byName[c.name] = id
      end
    end
  end
  return assert(byName[name], "no card named " .. name)
end

local function armSecret(g, player, name)
  local e = H.ns.Entity.New(g:Printed(ID(name)), player, g.ids)
  g:PlaySecret(player, e)
  return e
end

local function play(g, player, name, target, position)
  local i, e = H.Hand(g, player, ID(name))
  local ok, why = g:PlayCard(player, i, target, position)
  g.bus:Drain()
  return ok, e, why
end

local function count(g, player, name)
  local n = 0
  for _, e in ipairs(g.players[player].board) do
    if e.cardId == ID(name) then n = n + 1 end
  end
  return n
end

-- ------------------------------------------------------------- keywords

H.suite("0.1.3: a bounced Argent Squire has its Divine Shield back", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local squire = H.Put(g, 1, ID("Argent Squire"))
  g:DealDamage(squire, 1, nil, false); g.bus:Drain()
  H.ok(not squire.divineShieldUp, "the shield popped")
  H.ok(play(g, 1, "Youthful Brewmaster", squire), "Brewmaster bounced it")
  H.eq(squire.zone, ns.ZONE.HAND, "in hand")
  local idx
  for i, c in ipairs(g.players[1].hand) do if c == squire then idx = i end end
  H.ok(g:PlayCard(1, idx)); g.bus:Drain()
  H.ok(squire.divineShieldUp and squire:Has(ns.KEYWORD.DIVINE_SHIELD), "replayed with its shield")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: a Worgen Infiltrator sent back by Freezing Trap is Stealthed again", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  armSecret(g, 2, "Freezing Trap")
  local worgen = H.Put(g, 1, ID("Worgen Infiltrator"))
  g:Attack(worgen, H.Hero(g, 2)); g.bus:Drain()
  H.eq(worgen.zone, ns.ZONE.HAND, "the trap bounced it")
  H.ok(worgen:Has(ns.KEYWORD.STEALTH), "a fresh card: Stealth is printed")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: a silenced minion can gain keywords again", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Silence", yeti), "silenced")
  H.ok(yeti.silenced, "flagged")
  H.ok(play(g, 1, "Sunfury Protector", nil, 2), "Sunfury beside it")
  H.ok(yeti:IsTaunt(), "Taunt given after the Silence counts")
  H.ok(play(g, 1, "Argent Protector", yeti), "Argent Protector on it")
  H.ok(yeti:Has(ns.KEYWORD.DIVINE_SHIELD) and yeti.divineShieldUp, "and so does Divine Shield")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Silence still removes printed keywords", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local rag = H.Put(g, 1, ID("Ragnaros the Firelord"))
  local goldshire = H.Put(g, 1, ID("Goldshire Footman"))
  H.ok(play(g, 1, "Silence", goldshire)); H.ok(not goldshire:IsTaunt(), "Taunt gone")
  H.ok(play(g, 1, "Silence", rag)); H.ok(rag:CanAttack(g.turn), "Ragnaros may attack once silenced")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: a trigger granted after Silence fires (Blessing of Wisdom)", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Silence", yeti))
  H.ok(play(g, 1, "Blessing of Wisdom", yeti))
  local hand = #g.players[1].hand
  g:Attack(yeti, H.Hero(g, 2)); g.bus:Drain()
  H.eq(#g.players[1].hand, hand + 1, "the attack drew a card")
  H.noEngineErrors(g)
end)

-- --------------------------------------------------------------- secrets

H.suite("0.1.3: Spellbender does not fire for a countered spell", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  armSecret(g, 2, "Counterspell")
  armSecret(g, 2, "Spellbender")
  local yeti = H.Put(g, 2, ID("Chillwind Yeti"))
  play(g, 1, "Frostbolt", yeti)
  H.eq(yeti:Health(), 5, "countered")
  H.eq(#g.players[2].secrets, 1, "Spellbender stays armed")
  H.eq(#g.players[2].board, 1, "and summoned nothing")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Explosive Trap kills the attacker; Freezing Trap stays armed", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  armSecret(g, 2, "Explosive Trap")
  armSecret(g, 2, "Freezing Trap")
  local wisp = H.Put(g, 1, ID("Wisp"))
  g:Attack(wisp, H.Hero(g, 2)); g.bus:Drain()
  H.ok(wisp.zone ~= ns.ZONE.PLAY, "the trap killed it")
  H.eq(#g.players[2].secrets, 1, "Freezing Trap was not spent on a corpse")
  H.eq(H.Hero(g, 2):Health(), 30, "and the dead Wisp never hit")
  H.noEngineErrors(g)
end)

-- ------------------------------------------------------------ set effects

H.suite("0.1.3: Equality under Stormwind Champion leaves 1/2 minions", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, ID("Stormwind Champion"))
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Equality"))
  H.eq(yeti:MaxHealth(), 2, "1, then +1 from the aura")
  H.eq(yeti:Attack(), 5, "attack untouched")
end)

H.suite("0.1.3: Humility under Raid Leader leaves 2 Attack; it overrides a this-turn buff", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, ID("Raid Leader"))
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Abusive Sergeant", yeti))
  H.eq(yeti:Attack(), 7, "4 +1 aura +2 this turn")
  H.ok(play(g, 1, "Humility", yeti))
  H.eq(yeti:Attack(), 2, "set to 1, aura on top, Sergeant's buff overridden")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Shadowstep returns the minion costing (2) less", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Shadowstep", yeti))
  H.eq(yeti.zone, ns.ZONE.HAND, "in hand")
  H.eq(yeti:Cost(), 2, "4 - 2")
  H.noEngineErrors(g)
end)

-- ---------------------------------------------------------------- timing

H.suite("0.1.3: Wild Pyromancer pings the Golem left by a Harvest Golem the spell killed", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, ID("Wild Pyromancer"))
  local golem = H.Put(g, 2, ID("Harvest Golem"))
  g:DealDamage(golem, 2, nil, false)
  H.ok(play(g, 1, "Frostbolt", golem))
  -- the 2/1 Damaged Golem arrives first, and the Pyromancer's ping kills it
  H.eq(#g.players[2].board, 0, "nothing left standing")
  local golems = 0
  for _, e in ipairs(g.players[2].graveyard) do
    if e.cardId == ID("Damaged Golem") then golems = golems + 1 end
  end
  H.eq(golems, 1, "the Damaged Golem arrived and was pinged")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: a Wild Pyromancer killed by the spell does not fire", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local pyro = H.Put(g, 1, ID("Wild Pyromancer"))
  local yeti = H.Put(g, 2, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Frostbolt", pyro))
  H.ok(pyro.zone ~= ns.ZONE.PLAY, "dead")
  H.eq(yeti:Health(), 5, "no ping")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: random picks skip minions that are already dying", function(ns, H)
  for seed = 1, 20 do
    local g = H.NewGame({ seed = seed }); H.SetActive(g, 1)
    local doomed = H.Put(g, 2, ID("Chillwind Yeti"))
    local other = H.Put(g, 2, ID("Chillwind Yeti"))
    doomed.pendingDestroy = true
    local picks = ns.Selector.Resolve(g, { side = "ENEMY", type = "MINION", random = 1 },
                                      { controller = 1 })
    H.ok(picks[1] == other, "seed " .. seed .. ": never the dying one")
  end
end)

-- ------------------------------------------------------- scripts attached

H.suite("0.1.3: a bounced Loot Hoarder has one deathrattle, not two", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local hoarder = H.Put(g, 1, ID("Loot Hoarder"))
  H.ok(play(g, 1, "Youthful Brewmaster", hoarder))
  local idx
  for i, c in ipairs(g.players[1].hand) do if c == hoarder then idx = i end end
  H.ok(g:PlayCard(1, idx)); g.bus:Drain()
  H.eq(#hoarder.deathrattles, 1, "one deathrattle")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Screwjank Clunker can target a friendly Mech", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local golem = H.Put(g, 1, ID("Harvest Golem"))
  H.ok(play(g, 1, "Screwjank Clunker", golem), "played onto the Mech")
  H.eq(golem:Attack(), 4, "+2/+2")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Bolvar grows in hand, not on the board", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  local bolvar = H.Put(g, 1, ID("Bolvar Fordragon"))
  local wisp = H.Put(g, 1, ID("Wisp"))
  wisp.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  H.eq(bolvar:Attack(), 1, "still 1 Attack on the board")
end)

H.suite("0.1.3: Mimiron's Head on a full board still makes V-07-TR-0N", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 2)
  H.Put(g, 1, ID("Mimiron's Head"))
  H.Put(g, 1, ID("Harvest Golem")); H.Put(g, 1, ID("Harvest Golem"))
  for _ = 1, 4 do H.Put(g, 1, ID("Wisp")) end
  g:EndTurn(); g.bus:Drain()
  H.eq(count(g, 1, "V-07-TR-0N"), 1, "V-07-TR-0N arrived")
  H.noEngineErrors(g)
end)

-- ------------------------------------------------------------------ draws

H.suite("0.1.3: Coldlight Oracle fatiguing both heroes to death is a draw", function(ns, H)
  local g = H.NewGame({ deckSize = 0 }); H.SetActive(g, 1); H.Mana(g, 1, 10)
  for pi = 1, 2 do
    g.players[pi].deck = {}
    H.Hero(g, pi).damage = 29
  end
  play(g, 1, "Coldlight Oracle")
  H.ok(g.over, "over")
  H.eq(g.winner, 0, "a draw")
end)

H.suite("0.1.3: Flame Leviathan in the opening hand does nothing", function(ns, H)
  local ids = {}
  for i = 1, 30 do ids[i] = ID("Flame Leviathan") end
  local g = H.NewGame({ deck1 = ids, noStart = true })
  g:Deal()
  H.eq(H.Hero(g, 1):Health(), 30, "no damage from the deal")
  H.eq(H.Hero(g, 2):Health(), 30, "none to the opponent either")
end)

-- ------------------------------------------------------------ card text

H.suite("0.1.3: Mal'Ganis makes your hero Immune", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  local mal = H.Put(g, 1, ID("Mal'Ganis"))
  g:DealDamage(H.Hero(g, 1), 5, nil, false)
  H.eq(H.Hero(g, 1):Health(), 30, "Immune")
  mal.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  g:DealDamage(H.Hero(g, 1), 5, nil, false)
  H.eq(H.Hero(g, 1):Health(), 25, "not after he dies")
end)

H.suite("0.1.3: Velen's Chosen gives Spell Damage +1", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Velen's Chosen", yeti))
  H.eq(g:SpellPower(1), 1, "+1")
end)

H.suite("0.1.3: Crush costs (4) less with a damaged friendly minion", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  local _, crush = H.Hand(g, 1, ID("Crush"))
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  g:RecalcAuras()
  H.eq(crush:Cost(), 7, "7 while nothing is damaged")
  g:DealDamage(yeti, 1, nil, false); g:RecalcAuras()
  H.eq(crush:Cost(), 3, "3 with a damaged minion")
end)

H.suite("0.1.3: Call Pet discounts a drawn Beast by (4)", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local beast = H.PutOnDeck(g, 1, ID("Savannah Highmane"))
  H.ok(play(g, 1, "Call Pet"))
  H.eq(beast.zone, ns.ZONE.HAND, "drawn")
  H.eq(beast:Cost(), 2, "6 - 4")
end)

H.suite("0.1.3: Far Sight's card costs (3) less", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.PutOnDeck(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Far Sight"))
  H.eq(yeti:Cost(), 1, "4 - 3")
end)

H.suite("0.1.3: Sabotage's combo destroys the enemy weapon", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  g:EquipWeapon(2, ID("Fiery War Axe"))
  H.Put(g, 2, ID("Chillwind Yeti"))
  play(g, 1, "Wisp")
  H.ok(play(g, 1, "Sabotage"))
  H.ok(g.players[2].weapon == nil, "the weapon is gone")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Reincarnate under Baron Rivendare returns one minion", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, ID("Baron Rivendare"))
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Reincarnate", yeti))
  H.eq(count(g, 1, "Chillwind Yeti"), 1, "one Yeti back")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Reincarnate on an enemy minion returns it to them", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 2, ID("Chillwind Yeti"))
  g:DealDamage(yeti, 3, nil, false)
  H.ok(play(g, 1, "Reincarnate", yeti))
  H.eq(count(g, 2, "Chillwind Yeti"), 1, "on their side")
  H.eq(g.players[2].board[1]:Health(), 5, "at full Health")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Feign Death doubles under Baron Rivendare", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, ID("Baron Rivendare"))
  H.Put(g, 1, ID("Loot Hoarder"))
  local hand = #g.players[1].hand
  H.ok(play(g, 1, "Feign Death"))
  H.eq(#g.players[1].hand, hand + 2, "two draws")
end)

H.suite("0.1.3: Malorne under Baron goes into the deck once", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  H.Put(g, 1, ID("Baron Rivendare"))
  local malorne = H.Put(g, 1, ID("Malorne"))
  local deck = #g.players[1].deck
  malorne.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].deck, deck + 1, "one card added")
  for _, e in ipairs(g.players[1].graveyard) do
    H.ok(e ~= malorne, "and it left the graveyard")
  end
end)

H.suite("0.1.3: Mad Scientist skips a Secret already in play", function(ns, H)
  local g = H.NewGame({ class1 = "HUNTER" }); H.SetActive(g, 2)
  armSecret(g, 1, "Explosive Trap")
  H.PutOnDeck(g, 1, ID("Explosive Trap"))
  local snake = H.PutOnDeck(g, 1, ID("Snake Trap"))
  local sci = H.Put(g, 1, ID("Mad Scientist"))
  sci.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].secrets, 2, "a second Secret went up")
  H.eq(snake.zone, ns.ZONE.SECRET, "the one that could")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Healing Totem heals at the end of your turn", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  H.Put(g, 1, ID("Healing Totem"))
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  g:DealDamage(yeti, 2, nil, false)
  g:EndTurn(); g.bus:Drain()
  H.eq(yeti:Health(), 4, "healed 1")
end)

H.suite("0.1.3: Leokk gives other friendly minions +1 Attack", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  local leokk = H.Put(g, 1, ID("Leokk"))
  local yeti = H.Put(g, 1, ID("Chillwind Yeti"))
  H.eq(yeti:Attack(), 5, "+1")
  H.eq(leokk:Attack(), 2, "not itself")
end)

H.suite("0.1.3: Ysera Awakens spares Ysera; Dream returns a minion", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local ysera = H.Put(g, 1, ID("Ysera"))
  local yeti = H.Put(g, 2, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Ysera Awakens"))
  H.eq(ysera:Health(), 12, "Ysera untouched")
  H.ok(yeti.zone ~= ns.ZONE.PLAY, "the Yeti took 5 and died")
  H.eq(H.Hero(g, 1):Health(), 25, "heroes hit")
  local y2 = H.Put(g, 2, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Dream", y2))
  H.eq(y2.zone, ns.ZONE.HAND, "Dream returned it")
  H.noEngineErrors(g)
end)

H.suite("0.1.3: Starving Buzzard and Warsong Commander do not trigger on themselves", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local hand = #g.players[1].hand
  local _, buzz = play(g, 1, "Starving Buzzard")
  H.eq(#g.players[1].hand, hand, "no draw for itself")
  local _, war = play(g, 1, "Warsong Commander")
  H.ok(not war:Has(ns.KEYWORD.CHARGE), "no Charge for itself")
  local _, wisp = play(g, 1, "Wisp")
  H.ok(wisp:Has(ns.KEYWORD.CHARGE), "others still get it")
end)

H.suite("0.1.3: Sacrificial Pact kills Lord Jaraxxus", function(ns, H)
  local g = H.NewGame({ class2 = "WARLOCK" }); H.SetActive(g, 2); H.Mana(g, 2, 10)
  H.ok(play(g, 2, "Lord Jaraxxus"), "Jaraxxus played")
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(play(g, 1, "Sacrificial Pact", H.Hero(g, 2)), "aimed at the Demon hero")
  H.ok(g.over and g.winner == 1, "the game is won")
end)

H.suite("0.1.3: Shadowflame cannot target a hero", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  local _, card = H.Hand(g, 1, ID("Shadowflame"))
  H.Put(g, 1, ID("Chillwind Yeti"))
  for _, t in ipairs(ns.Targeting.LegalTargets(g, card, 1)) do
    H.ok(t.printed.type == ns.CARDTYPE.MINION, "only minions")
  end
end)

H.suite("0.1.3: Lightning Storm rolls for each minion", function(ns, H)
  local differed = false
  for seed = 1, 20 do
    local g = H.NewGame({ seed = seed }); H.SetActive(g, 1); H.Mana(g, 1, 10)
    local a = H.Put(g, 2, ID("Chillwind Yeti"))
    local b = H.Put(g, 2, ID("Chillwind Yeti"))
    local c = H.Put(g, 2, ID("Chillwind Yeti"))
    play(g, 1, "Lightning Storm")
    for _, e in ipairs({ a, b, c }) do
      local d = 5 - e:Health()
      H.ok(d == 2 or d == 3, "2 or 3")
    end
    if a:Health() ~= b:Health() or b:Health() ~= c:Health() then differed = true end
  end
  H.ok(differed, "the rolls differ across minions")
end)

H.suite("0.1.3: Pint-Sized Summoner discounts only the first minion each turn", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  local _, yeti = H.Hand(g, 1, ID("Chillwind Yeti"))
  H.ok(play(g, 1, "Pint-Sized Summoner"))
  g:RecalcAuras()
  H.eq(yeti:Cost(), 4, "Pint-Sized was this turn's first minion")
  g:EndTurn(); g:EndTurn(); g.bus:Drain()
  H.eq(yeti:Cost(), 3, "next turn the first minion costs (1) less")
end)

H.suite("0.1.3: Cabal Shadow Priest has no target with six minions out", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  for _ = 1, 6 do H.Put(g, 1, ID("Wisp")) end
  local wisp = H.Put(g, 2, ID("Wisp"))
  local _, cabal = H.Hand(g, 1, ID("Cabal Shadow Priest"))
  H.eq(#ns.Targeting.LegalTargets(g, cabal, 1), 0, "nothing to steal into")
  local i
  for k, c in ipairs(g.players[1].hand) do if c == cabal then i = k end end
  H.ok(g:PlayCard(1, i)); g.bus:Drain()
  H.eq(wisp.zone, ns.ZONE.PLAY, "the Wisp is untouched")
end)

H.suite("0.1.3: Kidnapper's combo with no minions still lets it be played", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(play(g, 1, "The Coin"), "combo live")
  H.ok(play(g, 1, "Kidnapper"), "played with nothing to take")
end)

H.suite("0.1.3: Mindgames with no minion in their deck makes Shadow of Nothing", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1); H.Mana(g, 1, 10)
  g.players[2].deck = {}
  H.ok(play(g, 1, "Mindgames"))
  H.eq(count(g, 1, "Shadow of Nothing"), 1, "whiffed")
end)

H.suite("0.1.3: Feugen counts only a Stalagg that died, not one milled", function(ns, H)
  local g = H.NewGame(); H.SetActive(g, 1)
  local stalagg = H.ns.Entity.New(g:Printed(ID("Stalagg")), 1, g.ids)
  stalagg.zone = ns.ZONE.GRAVEYARD
  g.players[1].graveyard[#g.players[1].graveyard + 1] = stalagg
  local feugen = H.Put(g, 1, ID("Feugen"))
  feugen.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  H.eq(count(g, 1, "Thaddius"), 0, "a milled Stalagg does not count")
  local s2 = H.Put(g, 1, ID("Stalagg"))
  s2.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  H.eq(count(g, 1, "Thaddius"), 1, "now both have died")
end)

-- ------------------------------------------------------------ robustness

H.suite("0.1.3: a timeline cue that throws is dropped; the rest still runs", function(ns, H)
  local tl = ns.Timeline.New("t")
  local calls, after, done = 0, false, false
  tl:Over(0, 0.2, "linear", "broken", function() calls = calls + 1; error("boom") end)
  tl:At(0.3, "after", function() after = true end)
  tl.onDone = function() done = true end
  tl:RunAll(1 / 60)
  H.eq(calls, 1, "the broken cue ran once, not every frame")
  H.ok(after, "the next cue still fired")
  H.ok(done, "and the timeline finished")
end)
