--[[ tests/test_rules.lua -- the recreated Hearthstone rules.

  Pinned data used here:
    GAME_005 The Coin            0 mana  "Gain 1 Mana Crystal this turn only"
    CS2_171  Stonetusk Boar      1 mana 1/1 CHARGE
    CS2_179  Sen'jin Shieldmasta 4 mana 3/5 TAUNT
    EX1_033  Windfury Harpy      6 mana 4/5 WINDFURY
    EX1_008  Argent Squire       1 mana 1/1 DIVINE_SHIELD
    EX1_045  Ancient Watcher     2 mana 4/5 CANT_ATTACK
    NEW1_023 Faerie Dragon       2 mana 3/2 CANT_BE_TARGETED_BY_SPELLS
    CS2_142  Kobold Geomancer    2 mana 2/2 Spell Damage +1
    EX1_563  Malygos             9 mana 4/12 Spell Damage +5
    EX1_350  Prophet Velen       7 mana 7/7 spellMultiplier 2
    CS2_029  Fireball            4 mana, 6 damage
    CS1_113  Mind Control       10 mana, REQ_ENEMY_TARGET + REQ_NUM_MINION_SLOTS
]]
local H = require("tests.harness")

H.suite("rules: opening hands are 3 and 4 plus The Coin", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.eq(#g.players[1].hand, 3 + 1, "first player: 3 mulligan + 1 turn-1 draw")
  H.eq(#g.players[2].hand, 4 + 1, "second player: 4 mulligan + The Coin")
  local hasCoin = false
  for _, e in ipairs(g.players[2].hand) do
    if e.cardId == "GAME_005" then hasCoin = true end
  end
  H.ok(hasCoin, "second player holds The Coin")
  H.noEngineErrors(g)
end)

H.suite("rules: mana ramps by one and caps at ten", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.eq(g.players[1].maxMana, 1, "turn 1 gives one crystal")
  for _ = 1, 30 do g:EndTurn() end
  H.ok(g.players[1].maxMana <= 10, "player 1 capped at 10")
  H.ok(g.players[2].maxMana <= 10, "player 2 capped at 10")
  H.eq(g.players[1].maxMana, 10, "reached the cap")
  H.noEngineErrors(g)
end)

H.suite("rules: fatigue starts at 1 and increments", function(ns, H)
  local g = H.NewGame({ noStart = true, deck1 = {}, deck2 = {} })
  -- empty both decks, then draw repeatedly
  g.players[1].deck = {}
  local hero = H.Hero(g, 1)
  H.eq(hero:Health(), 30, "full health")
  g:Draw(1); H.eq(hero:Health(), 29, "first fatigue is 1")
  g:Draw(1); H.eq(hero:Health(), 27, "second fatigue is 2")
  g:Draw(1); H.eq(hero:Health(), 24, "third fatigue is 3")
  g:Draw(1); H.eq(hero:Health(), 20, "fourth fatigue is 4")
  H.noEngineErrors(g)
end)

H.suite("rules: hand caps at ten and overdraw burns the card", function(ns, H)
  local g = H.NewGame()
  local p = g.players[1]
  while #p.hand < 10 do g:AddToHand(1, "CS2_231") end
  H.eq(#p.hand, 10, "hand full")
  local deckBefore = #p.deck
  local graveBefore = #p.graveyard
  g:Draw(1)
  H.eq(#p.hand, 10, "hand did not grow")
  H.eq(#p.deck, deckBefore - 1, "the card left the deck")
  H.eq(#p.graveyard, graveBefore + 1, "the card was burned to the graveyard")
  H.eq(p.overdrawn, 1, "overdraw counted")
  H.noEngineErrors(g)
end)

H.suite("rules: summoning sickness, and Charge bypasses it", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local fresh = H.Put(g, 1, "CS2_182", { sick = true })   -- Yeti, just arrived
  H.notOk(g:CanAttack(fresh), "fresh minion cannot attack")

  local boar = H.Put(g, 1, "CS2_171", { sick = true })    -- Stonetusk Boar, CHARGE
  H.ok(g:CanAttack(boar), "Charge minion can attack immediately")
  H.noEngineErrors(g)
end)

H.suite("rules: Taunt forces attacks onto the taunter", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local attacker = H.Put(g, 1, "CS2_119")     -- Oasis Snapjaw
  local taunt = H.Put(g, 2, "CS2_179")        -- Sen'jin Shieldmasta, TAUNT
  local plain = H.Put(g, 2, "CS2_231")        -- Wisp

  local legal = g:LegalAttackTargets(attacker)
  H.eq(#legal, 1, "only the taunter is legal")
  H.eq(legal[1], taunt, "the taunter")
  H.notOk(g:IsLegalAttack(attacker, plain), "cannot hit the non-taunt minion")
  H.notOk(g:IsLegalAttack(attacker, H.Hero(g, 2)), "cannot hit the hero")
  H.ok(g:IsLegalAttack(attacker, taunt), "can hit the taunter")

  -- With the taunter gone, the hero opens up again.
  taunt.pendingDestroy = true
  g:ProcessDeaths()
  H.ok(g:IsLegalAttack(attacker, H.Hero(g, 2)), "hero attackable once taunt is gone")
  H.noEngineErrors(g)
end)

H.suite("rules: Windfury allows exactly two attacks", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local harpy = H.Put(g, 1, "EX1_033")        -- Windfury Harpy 4/5
  H.Put(g, 2, "CS2_119")                      -- Oasis Snapjaw 2/7 soak

  H.ok(g:CanAttack(harpy), "first attack allowed")
  g:Attack(harpy, g.players[2].board[1])
  H.ok(g:CanAttack(harpy), "second attack allowed")
  g:Attack(harpy, g.players[2].board[1])
  H.notOk(g:CanAttack(harpy), "third attack refused")
  H.eq(harpy.attacksThisTurn, 2, "two attacks recorded")
  H.noEngineErrors(g)
end)

H.suite("rules: Divine Shield absorbs one hit entirely", function(ns, H)
  local g = H.NewGame()
  local squire = H.Put(g, 1, "EX1_008")       -- Argent Squire 1/1 DIVINE_SHIELD
  H.ok(squire.divineShieldUp, "shield up")
  g:DealDamage(squire, 6, nil, false)
  H.eq(squire:Health(), 1, "took no damage through the shield")
  H.notOk(squire.divineShieldUp, "shield popped")
  g:DealDamage(squire, 1, nil, false)
  H.eq(squire:Health(), 0, "second hit lands")
  H.noEngineErrors(g)
end)

H.suite("rules: CANT_ATTACK and stat floors", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local watcher = H.Put(g, 1, "EX1_045")      -- Ancient Watcher 4/5 CANT_ATTACK
  H.notOk(g:CanAttack(watcher), "Ancient Watcher cannot attack")
  H.noEngineErrors(g)
end)

H.suite("rules: board is capped at seven", function(ns, H)
  local g = H.NewGame()
  for _ = 1, 7 do g:Summon("CS2_231", 1, "RIGHTMOST") end
  H.eq(#g.players[1].board, 7, "seven minions")
  local eighth = g:Summon("CS2_231", 1, "RIGHTMOST")
  H.notOk(eighth, "eighth summon refused")
  H.eq(#g.players[1].board, 7, "still seven")
  H.noEngineErrors(g)
end)

H.suite("rules: spell damage adds, Velen multiplies", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)

  -- plain Fireball: 6
  local t1 = H.Put(g, 2, "EX1_563")            -- Malygos 4/12 as a damage sponge
  local i1 = H.Hand(g, 1, "CS2_029")
  g:PlayCard(1, i1, t1)
  g.bus:Drain()
  H.eq(t1:Health(), 6, "Fireball dealt 6")

  -- with Kobold Geomancer (+1): 7
  local g2 = H.NewGame()
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  H.Put(g2, 1, "CS2_142")                      -- Kobold Geomancer, Spell Damage +1
  local t2 = H.Put(g2, 2, "EX1_563")
  local i2 = H.Hand(g2, 1, "CS2_029")
  g2:PlayCard(1, i2, t2)
  g2.bus:Drain()
  H.eq(t2:Health(), 5, "Fireball dealt 7 with Spell Damage +1")

  -- with Prophet Velen (x2): 12
  local g3 = H.NewGame()
  H.SetActive(g3, 1); H.Mana(g3, 1, 10)
  H.Put(g3, 1, "EX1_350")                      -- Prophet Velen
  local t3 = H.Put(g3, 2, "EX1_563")
  local i3 = H.Hand(g3, 1, "CS2_029")
  g3:PlayCard(1, i3, t3)
  g3.bus:Drain()
  H.eq(t3:Health(), 0, "Fireball dealt 12 with Velen")
  H.noEngineErrors(g)
end)

H.suite("rules: Faerie Dragon cannot be targeted by any spell", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local dragon = H.Put(g, 2, "NEW1_023")       -- CANT_BE_TARGETED_BY_SPELLS
  local fireball = ns.Entity.New(g:Printed("CS2_029"), 1)

  H.notOk(ns.Targeting.IsLegalTarget(g, fireball, 1, dragon),
          "enemy spell cannot target it")
  -- nor by its owner's: "can't be targeted by spells" means any spell
  local mine = H.Put(g, 1, "NEW1_023")
  H.notOk(ns.Targeting.IsLegalTarget(g, fireball, 1, mine),
          "own Faerie Dragon is not targetable either")
  H.noEngineErrors(g)
end)

H.suite("rules: Mind Control needs a free board slot", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  for _ = 1, 7 do H.Put(g, 1, "CS2_231") end   -- own board full
  local victim = H.Put(g, 2, "CS2_182")
  local mc = ns.Entity.New(g:Printed("CS1_113"), 1)
  local can, why = ns.Targeting.CanPlay(g, mc, 1)
  H.notOk(can, "Mind Control unplayable with a full board")
  H.noEngineErrors(g)
end)

H.suite("rules: Mind Control steals, and the minion is summoning-sick", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local victim = H.Put(g, 2, "CS2_182")        -- Chillwind Yeti
  local idx = H.Hand(g, 1, "CS1_113")          -- Mind Control
  local ok = g:PlayCard(1, idx, victim)
  g.bus:Drain()

  H.ok(ok, "Mind Control resolved")
  H.eq(#g.players[2].board, 0, "left the enemy board")
  H.eq(#g.players[1].board, 1, "joined my board")
  H.eq(victim.controller, 1, "controller changed")
  H.eq(victim.owner, 2, "owner unchanged")
  H.notOk(g:CanAttack(victim), "stolen minion is summoning-sick this turn")
  H.noEngineErrors(g)
end)

H.suite("rules: overload locks mana on the following turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local p = g.players[1]
  p.pendingOverload = 2
  g:EndTurn()      -- to p2
  g:EndTurn()      -- back to p1
  H.eq(p.lockedMana, 2, "two crystals locked")
  H.eq(p.mana, p.maxMana - 2, "available mana reduced")
  g:EndTurn(); g:EndTurn()
  H.eq(p.lockedMana, 0, "lock cleared next turn")
  H.noEngineErrors(g)
end)

H.suite("rules: frozen misses exactly one of its own turns", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local minion = H.Put(g, 1, "CS2_182")
  -- freeze during the OPPONENT's turn
  g:EndTurn()                       -- now p2's turn
  minion.frozen = true
  g:EndTurn()                       -- back to p1: BeginTurn marks it for thaw
  H.ok(minion.frozen, "still frozen on the turn it should miss")
  H.notOk(g:CanAttack(minion), "cannot attack while frozen")
  g:EndTurn()                       -- p1 ends: thaws
  H.notOk(minion.frozen, "thawed at the end of its controller's turn")
  H.noEngineErrors(g)
end)

H.suite("rules: a hero NEVER strikes back, weapon or no weapon", function(ns, H)
  --[[ THE BUG. A hero's attack value comes from the weapon it holds, and the
       exchange used that value as retaliation -- so a Rogue who equipped a
       dagger cut every minion that attacked their face, killing 1-health
       attackers outright, for as long as the weapon was equipped.

       Retaliation belongs to MINIONS. A held weapon swings when its owner
       chooses to attack with it; it does not cut people who walk into it. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local wisp = H.Put(g, 1, "CS2_231")            -- 1/1, about to go face
  wisp.summonedTurn = 0
  g:EquipWeapon(2, "CS2_082")                    -- Wicked Knife, 1/2, on THEM
  local foeHero = H.Hero(g, 2)
  H.ok(g:AttackValue(foeHero) > 0, "their hero is armed")

  local before = foeHero:Health()
  g:Attack(wisp, foeHero)
  g.bus:Drain()

  H.eq(foeHero:Health(), before - 1, "the Wisp got its hit in")
  H.ok(wisp.zone == ns.ZONE.PLAY, "and the Wisp is still alive")
  H.eq(wisp:Health(), 1, "untouched -- the hero did not swing back")
end)

H.suite("rules: attacking INTO a minion still trades", function(ns, H)
  --[[ The other side of the same rule, and the one that must not break: a
       minion defending is not retaliating, it is a minion hitting back. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local a = H.Put(g, 1, "CS2_231")               -- 1/1
  a.summonedTurn = 0
  local d = H.Put(g, 2, "CS2_182")               -- 4/5
  g:Attack(a, d)
  g.bus:Drain()
  H.ok(a:IsDead() or a.zone ~= ns.ZONE.PLAY, "the Wisp died to the Yeti")
  H.eq(d:Health(), 4, "and the Yeti took its one damage")
end)

H.suite("rules: a hero attacking a minion still takes the minion's damage", function(ns, H)
  --[[ Same rule, read from the other end: the hero is the attacker here, and
       the MINION is hitting back because it is a minion. Getting this wrong in
       the other direction would make armed heroes untouchable. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  g:EquipWeapon(1, "CS2_082")                    -- Wicked Knife, 1 attack
  local hero = H.Hero(g, 1)
  local yeti = H.Put(g, 2, "CS2_182")            -- 4/5
  local before = hero:Health()
  g:Attack(hero, yeti)
  g.bus:Drain()
  H.eq(yeti:Health(), 4, "the hero's weapon landed")
  H.eq(hero:Health(), before - 4, "and the Yeti hit the hero for four")
end)

H.suite("rules: fatigue consumes armor and a later empty draw can end the game",function(ns,H)
  local g=H.NewGame()
  local p=g.players[1]
  p.deck={}; p.hero.armor=1; p.hero.damage=29
  g.bus:Block(function() g:Draw(1) end)
  H.eq(p.hero.armor,0); H.eq(p.hero:Health(),1); H.notOk(g.over)
  g.bus:Block(function() g:Draw(1) end)
  H.ok(g.over); H.eq(g.winner,2)
end)

--[[ A bounced or shuffled minion goes to whoever CONTROLS it, not to the player
     it started with. Reported: Sapping a minion the opponent had Mind-Controlled
     put it back in the Sapping player's own hand. ]]
local function stolen(g)
  H.SetActive(g, 2)
  H.Mana(g, 2, 10)
  local yeti = H.Put(g, 1, "CS2_182")         -- my Yeti ...
  local mc = H.Hand(g, 2, "CS1_113")
  H.ok(g:PlayCard(2, mc, yeti), "... Mind-Controlled by them")
  g.bus:Drain()
  H.eq(yeti.controller, 2, "they control it")
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  return yeti
end

local function holds(g, player, e)
  for _, c in ipairs(g.players[player].hand) do if c == e then return true end end
  return false
end

H.suite("rules: Sap on a stolen minion returns it to the thief's hand", function(ns, H)
  local g = H.NewGame()
  local yeti = stolen(g)
  local sap = H.Hand(g, 1, "EX1_581")
  H.ok(g:PlayCard(1, sap, yeti), "Sap resolved")
  g.bus:Drain()
  H.ok(holds(g, 2, yeti), "in their hand")
  H.notOk(holds(g, 1, yeti), "not mine")
  H.eq(yeti.controller, 2, "and theirs to play")
  H.noEngineErrors(g)
end)

H.suite("rules: Vanish sends each stolen minion to its controller's hand", function(ns, H)
  local g = H.NewGame()
  local yeti = stolen(g)
  local mine = H.Put(g, 1, "CS2_119")
  local v = H.Hand(g, 1, "NEW1_004")
  H.ok(g:PlayCard(1, v), "Vanish resolved")
  g.bus:Drain()
  H.ok(holds(g, 2, yeti), "the stolen Yeti to them")
  H.ok(holds(g, 1, mine), "my own minion to me")
  H.noEngineErrors(g)
end)

H.suite("rules: Freezing Trap bounces a stolen attacker to its controller", function(ns, H)
  local g = H.NewGame()
  -- I steal their Snapjaw, then attack into their Freezing Trap
  H.SetActive(g, 2)
  H.Mana(g, 2, 10)
  local trap = H.Hand(g, 2, "EX1_611")
  H.ok(g:PlayCard(2, trap), "they armed Freezing Trap")
  g.bus:Drain()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local snap = H.Put(g, 2, "CS2_119")
  local mc = H.Hand(g, 1, "CS1_113")
  H.ok(g:PlayCard(1, mc, snap), "I stole it")
  g.bus:Drain()
  snap.summonedTurn = nil
  g:Attack(snap, H.Hero(g, 2))
  g.bus:Drain()
  H.ok(holds(g, 1, snap), "back to MY hand, the controller's")
  H.notOk(holds(g, 2, snap), "not theirs")
  H.noEngineErrors(g)
end)

H.suite("rules: Shadow Madness then Brewmaster keeps the stolen card", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local victim = H.Put(g, 2, "CS2_120")        -- River Crocolisk, 2 attack
  local sm = H.Hand(g, 1, "EX1_334")
  H.ok(g:PlayCard(1, sm, victim), "Shadow Madness resolved")
  g.bus:Drain()
  local bm = H.Hand(g, 1, "EX1_049")
  H.ok(g:PlayCard(1, bm, victim), "Brewmaster returned it")
  g.bus:Drain()
  H.ok(holds(g, 1, victim), "into MY hand")
  g:EndTurn()
  g.bus:Drain()
  H.ok(holds(g, 1, victim), "and it stays there when the madness ends")
  H.eq(#g.players[2].board, 0, "nothing reappears on their board")
  H.noEngineErrors(g)
end)

H.suite("rules: a stealthed minion cannot be attacked", function(ns, H)
  --[[ Found by the practice bot, which swung at a Worgen Infiltrator the turn
       it came down. Spells always respected Stealth (Targeting.lua); attacks
       did not, because LegalAttackTargets offered every enemy minion. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local yeti = H.Put(g, 1, "CS2_182")
  local worgen = H.Put(g, 2, "EX1_010")          -- Worgen Infiltrator, Stealth
  H.notOk(g:IsLegalAttack(yeti, worgen), "the stealthed Worgen cannot be attacked")
  H.ok(g:IsLegalAttack(yeti, H.Hero(g, 2)), "the hero still can")
  worgen.baseKeywords[ns.KEYWORD.STEALTH] = nil
  H.ok(g:IsLegalAttack(yeti, worgen), "once revealed, it can")
end)

H.suite("rules: a stealthed Taunt does not taunt", function(ns, H)
  --[[ Stealth wins over Taunt in Hearthstone: Conceal on a Sen'jin hides it,
       and while hidden it guards nothing -- the face is open. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local yeti = H.Put(g, 1, "CS2_182")
  local senjin = H.Put(g, 2, "CS2_179")          -- Sen'jin Shieldmasta, Taunt
  H.notOk(g:IsLegalAttack(yeti, H.Hero(g, 2)), "the Taunt guards the hero")
  senjin.enchKeywords[ns.KEYWORD.STEALTH] = true
  H.ok(g:IsLegalAttack(yeti, H.Hero(g, 2)), "stealthed, it guards nothing")
  H.notOk(g:IsLegalAttack(yeti, senjin), "and cannot itself be attacked")
end)

H.suite("rules: Nerubian Egg needs positive attack and loses permission when its buff ends",function(ns,H)
  local g=H.NewGame()
  local egg=H.Put(g,1,"FP1_007")
  local action={kind="ATTACK",attackerId=egg.instanceId,targetId=g.players[2].hero.instanceId}
  H.notOk(ns.Actions.Run(g,1,action))
  egg.ench.atk=2
  H.ok(g:CanAttack(egg))
  H.ok(ns.Actions.Run(g,1,action))
  egg.attacksThisTurn=0; egg.ench.atk=0
  H.notOk(g:CanAttack(egg))
  H.notOk(ns.Actions.Run(g,1,action))
end)
