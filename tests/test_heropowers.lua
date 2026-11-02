--[[ tests/test_heropowers.lua -- the nine class hero powers, and the last
     three cards.

  EIGHT OF THE NINE HERO POWERS WERE UNAUTHORED and silently did nothing in
  every single game. `Game:UseHeroPower` runs `if script and script.heroPower`,
  so a missing script is not an error -- and hero powers are not collectible, so
  the coverage report never counted them and could not report them missing. One
  power per class is in every match ever played; this is the kind of gap that
  hides precisely because it is everywhere.

  Hero powers also went through no targeting at all. Six of the nine carry
  printed requirements, so Fireblast could be aimed at nothing, Reinforce worked
  with a full board, and Totemic Call kept summoning after all four Totems were
  out.

  The three cards at the end are the last three in the pool, each of which
  needed one of those gaps closed first.
]]
local H = require("tests.harness")

local function powerGame(class)
  local g = H.NewGame({ class1 = class, class2 = "PRIEST" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  return g
end

--============================================================ every power

H.suite("heropower: every class has a hero power WITH A SCRIPT", function(ns, H)
  --[[ The assertion that would have caught this on day one. It is cheap, and
       eight of nine were failing it silently. ]]
  local g = H.NewGame()
  for class, id in pairs(ns.HERO_POWER_BY_CLASS) do
    H.ok(g:Printed(id), class .. "'s hero power " .. id .. " is a real card")
    H.ok(g:ScriptFor(id), class .. "'s hero power " .. id .. " HAS A SCRIPT")
  end
end)

H.suite("heropower: Fireblast deals 1 to whatever it is aimed at", function(ns, H)
  local g = powerGame("MAGE")
  local ogre = H.Put(g, 2, "CS2_200")
  H.ok(g:UseHeroPower(1, ogre), "used")
  g.bus:Drain()
  H.eq(ogre:Health(), 6, "the minion took 1")
  H.noEngineErrors(g)
end)

H.suite("heropower: a power needing a target is refused without one", function(ns, H)
  -- Fireblast carries REQ_TARGET_TO_PLAY. UseHeroPower validated nothing at all
  -- before, so it could be fired into empty space.
  local g = powerGame("MAGE")
  local ok, why = g:UseHeroPower(1, nil)
  H.notOk(ok, "refused")
  H.eq(why, "target required", "and says why")
  H.notOk(g.players[1].heroPowerUsedThisTurn, "and it was NOT spent")
  H.noEngineErrors(g)
end)

H.suite("heropower: Lesser Heal restores 2, and Auchenai turns it to damage", function(ns, H)
  local g = powerGame("PRIEST")
  local ogre = H.Put(g, 1, "CS2_200")
  g:DealDamage(ogre, 4, nil, false)
  g.bus:Drain()
  H.eq(ogre:Health(), 3, "damaged to 3")
  H.ok(g:UseHeroPower(1, ogre), "used")
  g.bus:Drain()
  H.eq(ogre:Health(), 5, "healed by 2")

  -- ...and with Auchenai Soulpriest out it damages instead
  H.SetActive(g, 1)
  H.Put(g, 1, "EX1_591")
  H.ok(g:UseHeroPower(1, ogre), "used again")
  g.bus:Drain()
  H.eq(ogre:Health(), 3, "the heal became 2 damage")
  H.noEngineErrors(g)
end)

H.suite("heropower: Reinforce summons a Recruit and respects a full board", function(ns, H)
  local g = powerGame("PALADIN")
  H.ok(g:UseHeroPower(1), "used")
  g.bus:Drain()
  H.eq(#g.players[1].board, 1, "a minion arrived")
  H.eq(g.players[1].board[1].cardId, "CS2_101t", "a Silver Hand Recruit")

  -- REQ_NUM_MINION_SLOTS: refused once the board is full
  H.SetActive(g, 1)
  while #g.players[1].board < ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  local ok, why = g:UseHeroPower(1)
  H.notOk(ok, "refused with a full board")
  H.eq(why, "REQ_NUM_MINION_SLOTS", "naming the printed requirement")
  H.noEngineErrors(g)
end)

H.suite("heropower: Armor Up! gains 2 armor and raises the armor event", function(ns, H)
  local g = powerGame("WARRIOR")
  H.Put(g, 1, "GVG_086")                      -- Siege Engine reacts to it
  local engine = g.players[1].board[1]
  H.ok(g:UseHeroPower(1), "used")
  g.bus:Drain()
  H.eq(H.Hero(g, 1).armor, 2, "2 armor")
  H.eq(engine:Attack(), engine.printed.atk + 1, "and Siege Engine grew by 1")
  H.noEngineErrors(g)
end)

H.suite("heropower: Life Tap draws FIRST, then takes the damage", function(ns, H)
  --[[ The order is observable: a Life Tap that kills you still drew the card,
       and Ice Block can save you in between. ]]
  local g = powerGame("WARLOCK")
  local before = #g.players[1].hand
  local hp = H.Hero(g, 1):Health()
  H.ok(g:UseHeroPower(1), "used")
  g.bus:Drain()
  H.eq(#g.players[1].hand, before + 1, "a card was drawn")
  H.eq(H.Hero(g, 1):Health(), hp - 2, "and 2 damage taken")
  H.noEngineErrors(g)
end)

H.suite("heropower: Dagger Mastery equips a 1/2 Wicked Knife", function(ns, H)
  local g = powerGame("ROGUE")
  H.ok(g:UseHeroPower(1), "used")
  g.bus:Drain()
  local w = g.players[1].weapon
  H.ok(w, "a weapon was equipped")
  H.eq(w.cardId, "CS2_082", "it is the Wicked Knife")
  H.noEngineErrors(g)
end)

H.suite("heropower: Shapeshift gives +1 attack this turn and 1 armor", function(ns, H)
  local g = powerGame("DRUID")
  H.ok(g:UseHeroPower(1), "used")
  g.bus:Drain()
  H.eq(g:AttackValue(H.Hero(g, 1)), 1, "the hero can swing for 1")
  H.eq(H.Hero(g, 1).armor, 1, "and gained 1 armor")
  H.noEngineErrors(g)
end)

H.suite("heropower: Totemic Call stops once all four Totems are out", function(ns, H)
  --[[ REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY, one of the three requirements that
       appear only on HERO_POWER cards and were reaching the fail-closed
       branch. ]]
  local g = powerGame("SHAMAN")
  local ent = g:Printed("CS2_049").entourage
  H.eq(#ent, 4, "four Totems in the printed entourage")

  for _ = 1, 4 do
    H.SetActive(g, 1)
    H.ok(g:UseHeroPower(1), "a Totem was summoned")
    g.bus:Drain()
  end
  H.eq(#g.players[1].board, 4, "four Totems are out")
  local seen = {}
  for _, e in ipairs(g.players[1].board) do seen[e.cardId] = true end
  local distinct = 0
  for _ in pairs(seen) do distinct = distinct + 1 end
  H.eq(distinct, 4, "and they are all DIFFERENT -- it never repeats one")

  H.SetActive(g, 1)
  local ok, why = g:UseHeroPower(1)
  H.notOk(ok, "a fifth use is refused")
  H.eq(why, "REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY", "naming the printed requirement")
  H.noEngineErrors(g)
end)

--============================================================ Steady Shot

H.suite("heropower: Steady Shot hits the enemy hero untargeted", function(ns, H)
  local g = powerGame("HUNTER")
  local before = H.Hero(g, 2):Health()
  H.ok(g:UseHeroPower(1), "used with no target")
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), before - 2, "the enemy hero took 2")
  H.noEngineErrors(g)
end)

H.suite("finishers: Steamwheedle Sniper lets Steady Shot hit minions", function(ns, H)
  --[[ The card is one line of data read by REQ_MINION_OR_ENEMY_HERO. Without a
       Sniper out, a minion is simply not a legal target. ]]
  local g = powerGame("HUNTER")
  local ogre = H.Put(g, 2, "CS2_200")
  local hp = g.players[1].heroPower

  H.notOk(ns.Targeting.IsLegalTarget(g, hp, 1, ogre),
          "without a Sniper, a minion is NOT a legal target")
  local ok, why = g:UseHeroPower(1, ogre)
  H.notOk(ok, "so aiming at one is refused")
  H.eq(why, "illegal target", "and says why")

  H.Put(g, 1, "GVG_087")                      -- Steamwheedle Sniper
  H.ok(ns.Targeting.IsLegalTarget(g, hp, 1, ogre),
       "with a Sniper out, the minion becomes legal")
  H.SetActive(g, 1)
  H.ok(g:UseHeroPower(1, ogre), "and the power fires at it")
  g.bus:Drain()
  H.eq(ogre:Health(), 5, "the minion took 2")
  H.noEngineErrors(g)
end)

H.suite("finishers: a silenced Sniper stops granting it", function(ns, H)
  local g = powerGame("HUNTER")
  local ogre = H.Put(g, 2, "CS2_200")
  local sniper = H.Put(g, 1, "GVG_087")
  local hp = g.players[1].heroPower
  H.ok(ns.Targeting.IsLegalTarget(g, hp, 1, ogre), "granted while it lives")
  sniper:Silence()
  g:RecalcAuras()
  H.notOk(ns.Targeting.IsLegalTarget(g, hp, 1, ogre), "and gone once silenced")
  H.noEngineErrors(g)
end)

--============================================================ Tracking

H.suite("finishers: Tracking offers the top three and keeps one", function(ns, H)
  --[[ The only card in the pool that stops MID-RESOLUTION to ask. The three
       cards leave the deck immediately, which is what Hearthstone does: while
       you are looking at them, nothing else can draw or steal them. ]]
  local g = powerGame("HUNTER")
  local p = g.players[1]
  -- stack three known, distinguishable cards on top
  H.PutOnDeck(g, 1, "CS2_200")
  H.PutOnDeck(g, 1, "CS2_182")
  H.PutOnDeck(g, 1, "CS2_106")
  local deckBefore, handBefore = #p.deck, #p.hand
  local graveBefore = #p.graveyard

  H.ok(g:PlayCard(1, H.Hand(g, 1, "DS1_184")), "Tracking resolved")
  g.bus:Drain()

  H.ok(g:AwaitingChoice(), "the game is waiting on a choice")
  H.eq(#g.pendingChoice.cards, 3, "offering three cards")
  H.eq(g.pendingChoice.player, 1, "to the caster")
  H.eq(#p.deck, deckBefore - 3, "and all three have LEFT the deck")

  -- nothing may be done until it is answered
  local ok, why = g:PlayCard(1, 1)
  H.notOk(ok, "no other card may be played meanwhile")
  H.eq(why, "a choice is pending", "and says why")

  H.ok(g:ResolveChoice(1, 2), "the second is chosen")
  H.notOk(g:AwaitingChoice(), "the choice is over")
  -- +1 Tracking added, -1 played, +1 kept
  H.eq(#p.hand, handBefore + 1, "one card reached hand")
  H.eq(p.hand[#p.hand].cardId, "CS2_182", "and it is the one chosen")
  H.eq(#p.graveyard, graveBefore + 3, "Tracking plus the two discards")
  H.noEngineErrors(g)
end)

H.suite("finishers: an out-of-range choice is refused, not clamped", function(ns, H)
  --[[ Clamping would quietly take a different card than the player picked, and
       across the wire two clients would clamp the same way only by luck. ]]
  local g = powerGame("HUNTER")
  H.ok(g:PlayCard(1, H.Hand(g, 1, "DS1_184")))
  g.bus:Drain()
  for _, bad in ipairs({ 0, 4, -1 }) do
    local ok, why = g:ResolveChoice(1, bad)
    H.notOk(ok, "index " .. bad .. " is refused")
    H.eq(why, "invalid choice", "and says why")
  end
  H.ok(g:AwaitingChoice(), "the choice is still outstanding")
  H.notOk(g:ResolveChoice(2, 1), "and the opponent cannot answer it")
  H.noEngineErrors(g)
end)

H.suite("finishers: Tracking on a thin deck offers what is there", function(ns, H)
  local g = powerGame("HUNTER")
  local p = g.players[1]
  for i = #p.deck, 1, -1 do table.remove(p.deck, i) end
  H.PutOnDeck(g, 1, "CS2_182")
  H.PutOnDeck(g, 1, "CS2_200")

  H.ok(g:PlayCard(1, H.Hand(g, 1, "DS1_184")))
  g.bus:Drain()
  H.ok(g:AwaitingChoice(), "it still asks")
  H.eq(#g.pendingChoice.cards, 2, "with only the two cards that existed")
  H.ok(g:ResolveChoice(1, 1))
  H.eq(#p.deck, 0, "the deck is empty")
  H.noEngineErrors(g)
end)

H.suite("finishers: ending the turn abandons an unanswered choice", function(ns, H)
  -- Walking away from the prompt declines it; the cards are already out of the
  -- deck, so they are discarded and the card was still spent.
  local g = powerGame("HUNTER")
  local p = g.players[1]
  H.ok(g:PlayCard(1, H.Hand(g, 1, "DS1_184")))
  g.bus:Drain()
  H.ok(g:AwaitingChoice(), "a choice is outstanding")
  local graveBefore = #p.graveyard

  g:EndTurn()
  g.bus:Drain()
  H.notOk(g:AwaitingChoice(), "the choice did not survive the turn")
  H.eq(#p.graveyard, graveBefore + 3, "all three were discarded")
  H.noEngineErrors(g)
end)

--============================================================ Nozdormu

H.suite("finishers: Nozdormu cuts the turn to 15 seconds for BOTH players", function(ns, H)
  --[[ PARTIAL, and deliberately so. The RULE is expressed and readable, but
       NOTHING COUNTS DOWN YET: the rope choreography exists in Client/FX and is
       not driven by anything. This suite pins the rule; the timer that consumes
       it is client work still to come. ]]
  local g = H.NewGame()
  H.eq(g:TurnSeconds(), ns.RULES.TURN_SECONDS, "a normal turn is the default")

  local noz = H.Put(g, 1, "EX1_560")
  H.eq(g:TurnSeconds(), 15, "Nozdormu cuts it to 15")

  -- it is a property of the GAME, not of its controller
  local g2 = H.NewGame()
  H.Put(g2, 2, "EX1_560")
  H.eq(g2:TurnSeconds(), 15, "and it applies from either side of the board")

  noz:Silence()
  g:RecalcAuras()
  H.eq(g:TurnSeconds(), ns.RULES.TURN_SECONDS, "silencing it gives the time back")
  H.noEngineErrors(g)
end)

H.suite("heropower: Spell Damage boosts spells but not powers or battlecries",function(ns,H)
  local g=powerGame("MAGE")
  H.Put(g,1,"CS2_142") -- Kobold Geomancer
  local hero=g.players[2].hero
  H.ok(g:UseHeroPower(1,hero)); g.bus:Drain()
  H.eq(hero:Health(),29)
  H.Mana(g,1,10)
  H.ok(ns.Actions.Run(g,1,{kind="PLAY_CARD",handIndex=H.Hand(g,1,"CS2_189"),targetId=hero.instanceId}))
  H.eq(hero:Health(),28,"Elven Archer battlecry remains one damage")
  H.ok(ns.Actions.Run(g,1,{kind="PLAY_CARD",handIndex=H.Hand(g,1,"CS2_029"),targetId=hero.instanceId}))
  H.eq(hero:Health(),21,"Fireball gets the Spell Damage bonus")
end)
