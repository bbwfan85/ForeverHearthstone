--[[ tests/test_cards_finishers.lua -- the last cards, and the engine features
     they each needed.

  These are the ones nothing could express until the very end: hero
  replacement, a hero power that changes, weapon properties that cannot be
  triggers, retargeting a live attack or spell, and a trigger that fires from
  HAND.

  Fixtures, verified against the pin:
    CS2_182  Chillwind Yeti      4 mana 4/5 vanilla
    CS2_231  Wisp                0 mana 1/1 vanilla
    CS2_200  Boulderfist Ogre    6 mana 6/7 vanilla
    CS2_024  Frostbolt           2 mana, 3 damage, needs a target
    EX1_323  Lord Jaraxxus       9 mana; hero EX1_323h 15hp, weapon EX1_323w 3/8
    EX1_625  Shadowform          3 mana; EX1_625t Mind Spike, EX1_625t2 Mind Shatter
    EX1_411  Gorehowl            7 mana 7/1 weapon
    DS1_188  Gladiator's Longbow 7 mana 5/2 weapon
]]
local H = require("tests.harness")

--============================================================ hero replacement

H.suite("finishers: Lord Jaraxxus replaces the hero, the power and the weapon", function(ns, H)
  local g = H.NewGame({ class1 = "WARLOCK" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  local oldHero = H.Hero(g, 1)
  g:DealDamage(oldHero, 12, nil, false)
  g.bus:Drain()
  oldHero.armor = 4        -- set AFTER the damage: armor absorbs first

  local i = H.Hand(g, 1, "EX1_323")
  H.ok(g:PlayCard(1, i), "Jaraxxus resolved")
  g.bus:Drain()

  local hero = H.Hero(g, 1)
  H.eq(hero.cardId, "EX1_323h", "the hero was replaced")
  H.eq(hero:Health(), 15, "at 15 Health, however battered the old one was")
  H.eq(hero.armor, 0, "and the Armor did NOT carry across (it replaces the hero; wiki)")
  H.eq(g.players[1].heroPower.cardId, "EX1_tk33", "INFERNO! is the hero power")
  H.ok(g.players[1].weapon, "Blood Fury was equipped")
  H.eq(g.players[1].weapon.cardId, "EX1_323w", "and it is Blood Fury")
  H.eq(#g.players[1].board, 0, "Jaraxxus himself is NOT left on the board")
  H.noEngineErrors(g)
end)

H.suite("finishers: Shadowform steps through its three states", function(ns, H)
  --[[ Lesser Heal -> Mind Spike -> Mind Shatter, and a third cast does nothing.
       The card is one of the few that reads its own hero power. ]]
  local g = H.NewGame({ class1 = "PRIEST" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  local first = g.players[1].heroPower.cardId
  H.ok(first ~= "EX1_625t", "it starts on Lesser Heal, not Mind Spike")

  H.ok(g:PlayCard(1, H.Hand(g, 1, "EX1_625")))
  g.bus:Drain()
  H.eq(g.players[1].heroPower.cardId, "EX1_625t", "first cast gives Mind Spike")

  H.SetActive(g, 1)
  H.ok(g:PlayCard(1, H.Hand(g, 1, "EX1_625")))
  g.bus:Drain()
  H.eq(g.players[1].heroPower.cardId, "EX1_625t2", "second gives Mind Shatter")

  H.SetActive(g, 1)
  H.ok(g:PlayCard(1, H.Hand(g, 1, "EX1_625")))
  g.bus:Drain()
  H.eq(g.players[1].heroPower.cardId, "EX1_625t2", "a third cast changes nothing")
  H.noEngineErrors(g)
end)

H.suite("finishers: a replaced hero power is ready to use", function(ns, H)
  -- Lesser Heal, then Shadowform, then Mind Spike -- all on one turn, as in Hearthstone.
  local g = H.NewGame({ class1 = "PRIEST" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g.players[1].heroPowerUsedThisTurn = true
  H.ok(g:PlayCard(1, H.Hand(g, 1, "EX1_625")))
  g.bus:Drain()
  H.notOk(g.players[1].heroPowerUsedThisTurn, "the new power has not been used")
  local enemy = H.Hero(g, 2)
  local before = enemy:Health()
  H.ok(g:UseHeroPower(1, enemy), "Mind Spike goes off")
  g.bus:Drain()
  H.eq(enemy:Health(), before - 2, "for 2")
  H.notOk(g:UseHeroPower(1, enemy), "and only once")
  H.noEngineErrors(g)
end)

H.suite("finishers: Lord Jaraxxus can be hurt, and Blood Fury swings", function(ns, H)
  local g = H.NewGame({ class1 = "WARLOCK" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  H.ok(g:PlayCard(1, H.Hand(g, 1, "EX1_323")))
  g.bus:Drain()
  local jax, foe = H.Hero(g, 1), H.Hero(g, 2)
  local foeBefore = foe:Health()
  H.ok(g:Attack(jax, foe), "Jaraxxus attacks with Blood Fury")
  g.bus:Drain()
  H.eq(foe:Health(), foeBefore - 3, "for 3")
  g:DealDamage(jax, 5, nil, false)
  g.bus:Drain()
  H.eq(jax:Health(), 10, "and he takes damage like any hero")
  g:DealDamage(jax, 10, nil, false)
  g.bus:Drain()
  H.ok(g.over and g.winner == 2, "and dies like one")
  H.noEngineErrors(g)
end)

H.suite("rules: a game still going when turn 89 ends is a draw", function(ns, H)
  local g = H.NewGame({})
  g.activePlayer = 1
  g.turn = 88
  g:EndTurn()
  H.notOk(g.over, "turn 89 is still played")
  H.eq(g.turn, 89)
  g:EndTurn()
  H.ok(g.over, "at its end the game is over")
  H.eq(g.winner, 0, "as a draw")
end)

--============================================================ weapons

H.suite("finishers: Gorehowl spends ATTACK on a minion, durability on a hero", function(ns, H)
  --[[ The distinction is the whole card: it clears minions without wearing out,
       but swinging at the face costs durability like any other weapon. ]]
  local g = H.NewGame({ class1 = "WARRIOR" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:EquipWeapon(1, "EX1_411")
  local w = g.players[1].weapon
  H.eq(g:AttackValue(w), 7, "Gorehowl starts at 7 attack")
  H.eq(w:Health(), 1, "with 1 durability")

  local ogre = H.Put(g, 2, "CS2_200")
  g:Attack(H.Hero(g, 1), ogre)
  g.bus:Drain()
  H.ok(g.players[1].weapon, "the weapon survived a minion swing")
  H.eq(g:AttackValue(g.players[1].weapon), 6, "it lost 1 ATTACK")
  H.eq(g.players[1].weapon:Health(), 1, "and no durability")

  H.SetActive(g, 1)
  g:Attack(H.Hero(g, 1), H.Hero(g, 2))
  g.bus:Drain()
  H.notOk(g.players[1].weapon, "a HERO swing spent the last durability instead")
  H.noEngineErrors(g)
end)

H.suite("finishers: Gladiator's Longbow keeps the hero Immune while attacking", function(ns, H)
  --[[ Cannot be a trigger: only secrets resolve inline, so a queued Immune
       would land after the retaliation it is meant to prevent. It is a weapon
       property read inside the exchange, and removed straight after. ]]
  local g = H.NewGame({ class1 = "HUNTER" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:EquipWeapon(1, "DS1_188")
  local hero = H.Hero(g, 1)
  local before = hero:Health()
  local ogre = H.Put(g, 2, "CS2_200")        -- 6/7 hits back hard

  g:Attack(hero, ogre)
  g.bus:Drain()
  H.eq(hero:Health(), before, "the hero took NO retaliation damage")
  H.ok(ogre:IsDamaged(), "while the Ogre took the swing")
  H.notOk(hero:Has(ns.KEYWORD.IMMUNE), "and the Immune did not linger afterwards")
  H.noEngineErrors(g)
end)

H.suite("finishers: an ordinary weapon still takes retaliation", function(ns, H)
  -- The control for the case above: without the property the hero takes damage.
  local g = H.NewGame({ class1 = "WARRIOR" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:EquipWeapon(1, "CS2_106")               -- Fiery War Axe 3/2
  local hero = H.Hero(g, 1)
  local before = hero:Health()
  local ogre = H.Put(g, 2, "CS2_200")
  g:Attack(hero, ogre)
  g.bus:Drain()
  H.eq(hero:Health(), before - 6, "the hero took the Ogre's attack")
  H.noEngineErrors(g)
end)

--============================================================ from the hand

H.suite("finishers: Bolvar grows while held IN HAND", function(ns, H)
  --[[ The only card in the pool that triggers from hand, which is why the scan
       is opt-in rather than walking two ten-card hands on every event. ]]
  local g = H.NewGame({ class1 = "PALADIN" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  local _, bolvar = H.Hand(g, 1, "GVG_063")
  H.eq(bolvar:Attack(), bolvar.printed.atk, "he starts at printed attack")

  local wisp = H.Put(g, 1, "CS2_231")
  g:DealDamage(wisp, 5, nil, false)
  g.bus:Drain()
  H.eq(bolvar:Attack(), bolvar.printed.atk + 1, "a friendly death grew him")

  local theirs = H.Put(g, 2, "CS2_231")
  g:DealDamage(theirs, 5, nil, false)
  g.bus:Drain()
  H.eq(bolvar:Attack(), bolvar.printed.atk + 1, "an ENEMY death did not")

  -- and the growth survives being played
  local idx
  for i, c in ipairs(g.players[1].hand) do if c == bolvar then idx = i end end
  H.ok(g:PlayCard(1, idx), "Bolvar was played")
  g.bus:Drain()
  H.eq(bolvar:Attack(), bolvar.printed.atk + 1, "and kept the attack he earned")
  H.noEngineErrors(g)
end)

--============================================================ retargeting

H.suite("finishers: Misdirection sends the attack somewhere else", function(ns, H)
  local g = H.NewGame({ class1 = "HUNTER" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:PlayCard(1, H.Hand(g, 1, "EX1_533"))     -- arm the secret
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "the secret is armed")

  -- the opponent swings at our hero; something else must take it
  H.SetActive(g, 2)
  local attacker = H.Put(g, 2, "CS2_200")    -- 6/7
  local bystander = H.Put(g, 1, "CS2_200")   -- must be a legal alternative
  local heroBefore = H.Hero(g, 1):Health()
  g:Attack(attacker, H.Hero(g, 1))
  g.bus:Drain()

  H.eq(H.Hero(g, 1):Health(), heroBefore, "the hero was NOT hit")
  --[[ "another RANDOM character", so the blow may land on our own minion or on
       the attacker's own side. Asserting which would be asserting the RNG; what
       the card promises is that it did not land on our hero. ]]
  local landedElsewhere = bystander:IsDamaged()
                          or H.Hero(g, 2):Health() < 30
                          or attacker:IsDamaged()
  H.ok(landedElsewhere, "and it landed on some other character")
  H.eq(#g.players[1].secrets, 0, "and the secret was spent")
  H.noEngineErrors(g)
end)

H.suite("finishers: Spellbender makes a 1/3 the spell's new target", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:PlayCard(1, H.Hand(g, 1, "tt_010"))
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "the secret is armed")

  H.SetActive(g, 2)
  H.Mana(g, 2, 10)
  local mine = H.Put(g, 1, "CS2_200")        -- the intended victim, 6/7
  local j = H.Hand(g, 2, "CS2_024")          -- Frostbolt, 3 damage
  H.ok(g:PlayCard(2, j, mine), "the enemy cast a spell at our minion")
  g.bus:Drain()

  H.notOk(mine:IsDamaged(), "the original target was NOT hit")

  --[[ The Spellbender minion is a 1/3 and Frostbolt deals 3, so it ABSORBS the
       spell and dies -- which is the card working, not failing. Looking for it
       on the board would therefore be looking in the wrong place; it is in the
       graveyard, having done its job. ]]
  local bender
  for _, e in ipairs(g.players[1].graveyard) do
    if e.cardId == "tt_010a" then bender = e end
  end
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "tt_010a" then bender = e end
  end
  H.ok(bender, "the Spellbender minion was summoned and took the spell")
  H.eq(#g.players[1].secrets, 0, "the secret was spent")
  H.noEngineErrors(g)
end)

H.suite("finishers: Spellbender ignores a spell with no minion target", function(ns, H)
  -- "When an enemy casts a spell ON A MINION." Without that test it would burn
  -- on any spell at all, including ones that take no target.
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:PlayCard(1, H.Hand(g, 1, "tt_010"))
  g.bus:Drain()

  H.SetActive(g, 2)
  H.Mana(g, 2, 10)
  local j = H.Hand(g, 2, "CS2_024")
  H.ok(g:PlayCard(2, j, H.Hero(g, 1)), "the enemy cast it at our HERO")
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "the secret is still armed")
  H.noEngineErrors(g)
end)

--============================================================ resurrection

H.suite("finishers: Redemption returns a FRESH copy at 1 Health", function(ns, H)
  --[[ Not the corpse: a dead entity carries its enchantments and a stale aura
       layer, because it is no longer in Aura.allEntities and its layer was
       never cleared. ]]
  local g = H.NewGame({ class1 = "PALADIN" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  g:PlayCard(1, H.Hand(g, 1, "EX1_136"))
  g.bus:Drain()

  local yeti = H.Put(g, 1, "CS2_182")        -- 4/5
  yeti.ench.atk = 3                          -- a buff that must NOT come back
  yeti:RecalcTimed()
  H.SetActive(g, 2)                          -- secrets answer the OPPONENT's turn
  g:DealDamage(yeti, 99, nil, false)
  g.bus:Drain()

  H.eq(#g.players[1].board, 1, "something came back")
  local back = g.players[1].board[1]
  H.eq(back.cardId, "CS2_182", "it is the same card")
  H.eq(back:Health(), 1, "at 1 Health")
  H.eq(back:Attack(), back.printed.atk, "at PRINTED attack, not the buffed one")
  H.notOk(back == yeti, "and it is a fresh entity, not the corpse")
  H.eq(#g.players[1].secrets, 0, "the secret was spent")
  H.noEngineErrors(g)
end)

--============================================================ drawn-card reads

H.suite("finishers: Gnomish Experimenter chickens a drawn MINION only", function(ns, H)
  --[[ A battlecry has no payload, so PayloadIsMinion is always false there --
       it compiles cleanly and the Chicken never appears. The drawn card has to
       be read directly. ]]
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  H.PutOnDeck(g, 1, "CS2_182")               -- a MINION on top
  local i = H.Hand(g, 1, "GVG_092")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  local drawn = g.players[1].hand[#g.players[1].hand]
  H.eq(drawn.cardId, "GVG_092t", "the drawn minion became a Chicken")

  -- a drawn SPELL is left alone
  local g2 = H.NewGame({ class1 = "MAGE" })
  H.Mana(g2, 1, 10)
  g2.activePlayer = 1
  H.PutOnDeck(g2, 1, "CS2_024")              -- a SPELL on top
  local j = H.Hand(g2, 1, "GVG_092")
  H.ok(g2:PlayCard(1, j))
  g2.bus:Drain()
  local drawn2 = g2.players[1].hand[#g2.players[1].hand]
  H.eq(drawn2.cardId, "CS2_024", "the drawn spell was left alone")
  H.noEngineErrors(g2)
end)
