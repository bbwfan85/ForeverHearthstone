--[[ tests/test_cards_neutral.lua -- behaviour tests for the cards authored in
     tools/effects/cards_neutral.csv.

  One suite per card. See tests/test_chooseone.lua for the house style: name the
  fixture cards and their printed stats in a comment, assert the board with
  H.board, and finish with H.noEngineErrors so an unknown op or selector cannot
  pass silently.

  Fixtures used below, all verified against the pin:
    CS2_231  Wisp                 0 mana 1/1 vanilla
    CS2_182  Chillwind Yeti       4 mana 4/5 vanilla
    CS2_189  Elven Archer         1 mana 1/1 Battlecry
    CS2_196  Razorfen Hunter      3 mana 2/3 Battlecry -> CS2_boar 1/1
    CS2_106  Fiery War Axe        2 mana 3/2 weapon
    GVG_082  Clockwork Gnome      1 mana 2/1 MECHANICAL, Deathrattle
    FP1_002  Haunted Creeper      2 mana 1/2 BEAST, Deathrattle
    EX1_finkle  Finkle Einhorn    3/3 token (The Beast)
    FP1_014t    Thaddius          11/11 token (Stalagg / Feugen)
]]
local H = require("tests.harness")

H.suite("neutral: The Beast -- deathrattle hands Finkle Einhorn to the OPPONENT", function(ns, H)
  local g = H.NewGame()
  local beast = H.Put(g, 1, "EX1_577")
  g.bus:Block(function() g:DealDamage(beast, 99, nil, false) end)
  H.board(g, 1, {}, "the Beast is gone and left nothing behind on your side")
  H.board(g, 2, { "EX1_finkle 3/3" }, "Finkle arrived on the OPPONENT's board")
  H.eq(g.players[2].board[1].controller, 2, "and the opponent controls him")
  H.noEngineErrors(g)
end)

H.suite("neutral: Bloodsail Raider -- gains the Attack of your weapon", function(ns, H)
  -- No weapon: attackOf() of nothing is 0, so the Raider is its printed self.
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "NEW1_018")
  H.ok(g:PlayCard(1, i), "played with no weapon equipped")
  g.bus:Drain()
  H.board(g, 1, { "NEW1_018 2/3" }, "no weapon means no bonus at all")
  H.noEngineErrors(g)

  local g2 = H.NewGame()
  H.Mana(g2, 1, 10)
  g2:EquipWeapon(1, "CS2_106")                 -- Fiery War Axe, 3 Attack
  local j = H.Hand(g2, 1, "NEW1_018")
  H.ok(g2:PlayCard(1, j), "played with the Axe equipped")
  g2.bus:Drain()
  H.board(g2, 1, { "NEW1_018 5/3" }, "the Axe's 3 Attack was added")

  --[[ It is an ENCHANTMENT read once at play time, not an aura that tracks the
       weapon. Losing the Axe afterwards must not shrink the Raider -- which is
       the difference between Buff(attackOf(...)) and an Aura. ]]
  g2:DestroyWeapon(1)
  g2:RecalcAuras()
  H.board(g2, 1, { "NEW1_018 5/3" }, "the buff survives the weapon breaking")
  H.noEngineErrors(g2)
end)

H.suite("neutral: Lil' Exorcist -- +1/+1 for each ENEMY Deathrattle minion", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  H.Put(g, 1, "GVG_082")                       -- your own Deathrattle must NOT count
  H.Put(g, 2, "GVG_082")                       -- Deathrattle
  H.Put(g, 2, "FP1_002")                       -- Deathrattle
  H.Put(g, 2, "CS2_182")                       -- no Deathrattle
  local i = H.Hand(g, 1, "GVG_097")
  H.ok(g:PlayCard(1, i), "Lil' Exorcist resolved")
  g.bus:Drain()
  -- printed 2/3, two enemy Deathrattle minions -> 4/5
  H.board(g, 1, { "GVG_082 2/1", "GVG_097 4/5" }, "two enemy Deathrattles, +2/+2")
  H.ok(g.players[1].board[2]:IsTaunt(), "Taunt is printed and still there")
  H.board(g, 2, { "GVG_082 2/1", "FP1_002 1/2", "CS2_182 4/5" }, "the enemy board is untouched")
  H.noEngineErrors(g)
end)

H.suite("neutral: Lil' Exorcist counts a GRANTED Deathrattle too", function(ns, H)
  --[[ The selector asks the live entity, not the printed card, so a Yeti that
       was handed a deathrattle counts exactly as a Clockwork Gnome does. ]]
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "GVG_097")
  yeti.deathrattles[#yeti.deathrattles + 1] = { { op = "Draw", count = 1 } }
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.board(g, 1, { "GVG_097 3/4" }, "the granted deathrattle was counted")
  H.noEngineErrors(g)
end)

H.suite("neutral: Nerub'ar Weblord -- Battlecry minions cost (2) more in BOTH hands", function(ns, H)
  local g = H.NewGame()
  local weblord = H.Put(g, 1, "FP1_017")
  local _, archer = H.Hand(g, 1, "CS2_189")    -- 1 mana, Battlecry
  local _, yeti   = H.Hand(g, 1, "CS2_182")    -- 4 mana, vanilla
  local _, theirs = H.Hand(g, 2, "CS2_189")    -- the OPPONENT is taxed as well
  g:RecalcAuras()

  H.eq(archer:Cost(), 3, "your Battlecry minion costs 2 more")
  H.eq(yeti:Cost(), 4, "a minion with no Battlecry is untouched")
  H.eq(theirs:Cost(), 3, "the opponent's Battlecry minion is taxed too")

  -- Silencing the source must give the discount straight back: an aura is
  -- recomputed from its sources, never "applied".
  weblord:Silence()
  g:RecalcAuras()
  H.eq(archer:Cost(), 1, "silencing the Weblord lifts the tax")
  H.eq(theirs:Cost(), 1, "on both sides")
  H.noEngineErrors(g)
end)

H.suite("neutral: Hobgoblin -- a PLAYED 1-Attack minion gets +2/+2", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  H.Put(g, 1, "GVG_104")                       -- Hobgoblin 2/3

  local i = H.Hand(g, 1, "CS2_231")            -- Wisp 1/1: exactly 1 Attack
  H.ok(g:PlayCard(1, i), "Wisp played")
  g.bus:Drain()

  local j = H.Hand(g, 1, "CS2_182")            -- Yeti 4/5: too big
  H.ok(g:PlayCard(1, j), "Yeti played")
  g.bus:Drain()

  --[[ "play", not "summon": Razorfen Hunter's 1/1 Boar arrives by battlecry and
       must NOT be buffed. Trigger on MINION_SUMMONED and this assertion goes
       red, which is the whole reason it is here. ]]
  local k = H.Hand(g, 1, "CS2_196")
  H.ok(g:PlayCard(1, k), "Razorfen Hunter played")
  g.bus:Drain()

  H.board(g, 1, { "GVG_104 2/3", "CS2_231 3/3", "CS2_182 4/5", "CS2_196 2/3", "CS2_boar 1/1" },
          "only the played 1-Attack minion grew")
  H.noEngineErrors(g)
end)

H.suite("neutral: Hobgoblin ignores the OPPONENT's 1-Attack minions", function(ns, H)
  local g = H.NewGame({ firstPlayer = 2 })
  H.Mana(g, 2, 10)
  H.Put(g, 1, "GVG_104")
  local i = H.Hand(g, 2, "CS2_231")
  H.ok(g:PlayCard(2, i), "the opponent plays a Wisp")
  g.bus:Drain()
  H.board(g, 2, { "CS2_231 1/1" }, "their Wisp is left alone")
  H.noEngineErrors(g)
end)

H.suite("neutral: Stalagg -- Thaddius only once Feugen has also died", function(ns, H)
  local g = H.NewGame()
  local stalagg = H.Put(g, 1, "FP1_014")
  g.bus:Block(function() g:DealDamage(stalagg, 99, nil, false) end)
  H.board(g, 1, {}, "Stalagg died alone, so no Thaddius")

  local feugen = H.Put(g, 1, "FP1_015")
  g.bus:Block(function() g:DealDamage(feugen, 99, nil, false) end)
  H.board(g, 1, { "FP1_014t 11/11" }, "Feugen followed him, so Thaddius arrives")
  H.noEngineErrors(g)
end)

H.suite("neutral: Feugen -- the same rule, in the other order", function(ns, H)
  local g = H.NewGame()
  local feugen = H.Put(g, 1, "FP1_015")
  g.bus:Block(function() g:DealDamage(feugen, 99, nil, false) end)
  H.board(g, 1, {}, "Feugen died alone, so no Thaddius")

  local stalagg = H.Put(g, 1, "FP1_014")
  g.bus:Block(function() g:DealDamage(stalagg, 99, nil, false) end)
  H.board(g, 1, { "FP1_014t 11/11" }, "Stalagg followed him, so Thaddius arrives")
  H.noEngineErrors(g)
end)

H.suite("neutral: Stalagg and Feugen dying together summon ONE Thaddius", function(ns, H)
  --[[ Both deathrattles queue in the same batch and both see the other in the
       graveyard, so the literal reading of the card text would summon two.
       Hearthstone summons one. ]]
  local g = H.NewGame()
  local a = H.Put(g, 1, "FP1_014")
  local b = H.Put(g, 1, "FP1_015")
  g.bus:Block(function()
    g:DealDamage(a, 99, nil, false)
    g:DealDamage(b, 99, nil, false)
  end)
  H.board(g, 1, { "FP1_014t 11/11" }, "exactly one Thaddius")
  H.noEngineErrors(g)
end)

H.suite("neutral: the OPPONENT's Feugen does not wake your Stalagg", function(ns, H)
  local g = H.NewGame()
  local theirs = H.Put(g, 2, "FP1_015")
  g.bus:Block(function() g:DealDamage(theirs, 99, nil, false) end)
  H.board(g, 2, {}, "their Feugen died")

  local stalagg = H.Put(g, 1, "FP1_014")
  g.bus:Block(function() g:DealDamage(stalagg, 99, nil, false) end)
  H.board(g, 1, {}, "your Stalagg gets nothing from it")
  H.board(g, 2, {}, "and neither do they")
  H.noEngineErrors(g)
end)

--============================================================ round 2: the
--   cards unblocked by the zone-movement, pool-generation and OneOf primitives.
--
--   Extra fixtures, all verified against the pin:
--     EX1_116t Whelp              1/1 token -- Leeroy's OWN, not ds1_whelptoken
--     EX1_tk29 Devilsaur          5/5 token   EX1_tk28 Squirrel 1/1 token
--     EX1_289  Ice Barrier        3 mana MAGE Secret
--     CS2_023  Arcane Intellect   3 mana MAGE spell, not a Secret
--     CS2_027  Mirror Image       1 mana MAGE spell, no target
--     GAME_005 The Coin           0 mana spell
--     CS2_200  Boulderfist Ogre   6 mana 6/7 vanilla

H.suite("neutral: Leeroy Jenkins -- two Whelps for the opponent, empty board and all", function(ns, H)
  --[[ The EMPTY enemy board is the case that used to crash: Leeroy's own board
       index was applied to the opponent's board, inserting past the end of a
       zero-length table and leaving a hole Game:Reindex died on. ]]
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  H.board(g, 2, {}, "the opponent's board starts EMPTY")
  local i = H.Hand(g, 1, "EX1_116")
  H.ok(g:PlayCard(1, i), "Leeroy resolved")
  g.bus:Drain()
  H.board(g, 1, { "EX1_116 6/2" }, "Leeroy is on your board")
  H.board(g, 2, { "EX1_116t 1/1", "EX1_116t 1/1" }, "and two Whelps on theirs")
  H.eq(g.players[2].board[1].controller, 2, "the opponent controls them")
  local leeroy = g.players[1].board[1]
  H.ok(leeroy:Has(ns.KEYWORD.CHARGE), "Charge is printed data")
  H.ok(g:CanAttack(leeroy), "so he can swing the turn he lands")
  H.noEngineErrors(g)
end)

H.suite("neutral: Leeroy's Whelps go rightmost on an occupied enemy board", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_231")                       -- pushes Leeroy to index 2
  H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "EX1_116")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.board(g, 2, { "CS2_182 4/5", "EX1_116t 1/1", "EX1_116t 1/1" },
          "the Yeti keeps its slot and the Whelps land to its right")
  H.noEngineErrors(g)
end)

H.suite("neutral: Secretkeeper -- grows on EITHER player's Secret", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "EX1_080")
  local i = H.Hand(g, 1, "EX1_289")            -- Ice Barrier
  H.ok(g:PlayCard(1, i), "you played a Secret")
  g.bus:Drain()
  H.board(g, 1, { "EX1_080 2/3" }, "Secretkeeper grew")

  -- An ordinary spell must do nothing: the trigger is on CARD_PLAYED, so
  -- without PayloadIsSecret it would fire on everything.
  H.SetActive(g, 1)
  local j = H.Hand(g, 1, "CS2_023")            -- Arcane Intellect, not a Secret
  H.ok(g:PlayCard(1, j))
  g.bus:Drain()
  H.board(g, 1, { "EX1_080 2/3" }, "a plain spell left it alone")

  -- ...and the OPPONENT's Secret counts too. "Whenever a Secret is played".
  g.activePlayer = 2
  H.Mana(g, 2, 10)
  local k = H.Hand(g, 2, "EX1_289")
  H.ok(g:PlayCard(2, k), "the opponent played a Secret")
  g.bus:Drain()
  H.board(g, 1, { "EX1_080 3/4" }, "Secretkeeper grew again")
  H.noEngineErrors(g)
end)

H.suite("neutral: Undertaker -- grows on YOUR Deathrattle minions, however they arrive", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local taker = H.Put(g, 1, "FP1_028")
  local i = H.Hand(g, 1, "GVG_082")            -- Clockwork Gnome, Deathrattle
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.eq(taker:Attack(), 2, "a played Deathrattle minion grew it")
  H.eq(taker:Health(), 3, "in both directions")

  local j = H.Hand(g, 1, "CS2_182")            -- Yeti, no Deathrattle
  H.ok(g:PlayCard(1, j))
  g.bus:Drain()
  H.eq(taker:Attack(), 2, "a vanilla minion did nothing")

  -- "whenever you SUMMON", so a token that never passed through hand counts.
  g:Summon("GVG_082", 1, nil, nil)
  g.bus:Drain()
  H.eq(taker:Attack(), 3, "a summoned Deathrattle minion counts too")

  -- ...but only yours.
  g:Summon("GVG_082", 2, nil, nil)
  g.bus:Drain()
  H.eq(taker:Attack(), 3, "the opponent's does not")
  H.noEngineErrors(g)
end)

H.suite("neutral: Fel Reaver -- the opponent plays a card, YOUR deck loses three", function(ns, H)
  local g = H.NewGame({ firstPlayer = 2 })
  H.Mana(g, 2, 10)
  H.Put(g, 1, "GVG_016")
  local mine, theirs = g.players[1], g.players[2]
  local deckBefore, graveBefore = #mine.deck, #mine.graveyard
  local theirDeck = #theirs.deck

  local i = H.Hand(g, 2, "CS2_231")
  H.ok(g:PlayCard(2, i), "the opponent played a Wisp")
  g.bus:Drain()
  H.eq(#mine.deck, deckBefore - 3, "your deck lost its top three")
  H.eq(#mine.graveyard, graveBefore + 3, "and they went to your graveyard")
  H.eq(#theirs.deck, theirDeck, "their deck is untouched")

  -- Your own plays must not mill you: the condition is `not PayloadIsMine`.
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local before = #mine.deck
  local j = H.Hand(g, 1, "CS2_231")
  H.ok(g:PlayCard(1, j), "you played a Wisp")
  g.bus:Drain()
  H.eq(#mine.deck, before, "your own card cost you nothing")
  H.noEngineErrors(g)
end)

H.suite("neutral: Captain's Parrot -- a Pirate MOVES from deck to hand", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local p = g.players[1]
  local raider = H.PutOnDeck(g, 1, "NEW1_018")  -- the only Pirate in a Wisp deck
  local deckBefore, handBefore = #p.deck, #p.hand

  local i = H.Hand(g, 1, "NEW1_016")
  H.ok(g:PlayCard(1, i), "the Parrot resolved")
  g.bus:Drain()
  -- hand: +1 Parrot added, -1 played, +1 Raider = net +1
  H.eq(#p.hand, handBefore + 1, "a card arrived in hand")
  H.eq(#p.deck, deckBefore - 1, "and it LEFT the deck -- moved, not copied")
  H.eq(raider.zone, ns.ZONE.HAND, "the Raider itself is the card in hand")
  local found = false
  for _, e in ipairs(p.hand) do if e == raider then found = true end end
  H.ok(found, "and it is really there")
  H.noEngineErrors(g)
end)

H.suite("neutral: Captain's Parrot with no Pirate in the deck does nothing", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local p = g.players[1]
  local deckBefore = #p.deck
  local i = H.Hand(g, 1, "NEW1_016")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.eq(#p.deck, deckBefore, "an all-Wisp deck gives up nothing")
  H.noEngineErrors(g)
end)

H.suite("neutral: Mad Scientist -- a Secret leaves the DECK and goes live", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  local p = g.players[1]
  local barrier = H.PutOnDeck(g, 1, "EX1_289")
  local deckBefore = #p.deck
  local sci = H.Put(g, 1, "FP1_004")
  g.bus:Block(function() g:DealDamage(sci, 99, nil, false) end)

  H.eq(#p.secrets, 1, "a Secret went active")
  H.eq(p.secrets[1], barrier, "and it is the Ice Barrier from the deck")
  H.eq(barrier.zone, ns.ZONE.SECRET, "its zone says so")
  H.eq(#p.deck, deckBefore - 1, "the deck is one shorter -- no mana was paid")
  H.board(g, 1, {}, "the Scientist itself is gone")
  H.noEngineErrors(g)
end)

H.suite("neutral: Deathlord -- the OPPONENT's deck fills the OPPONENT's board", function(ns, H)
  local g = H.NewGame()
  local theirs = g.players[2]
  -- A controlled deck: the harness filler is Wisps, which are minions too, so
  -- leaving them in would make "which minion came out" meaningless.
  for i = #theirs.deck, 1, -1 do table.remove(theirs.deck, i) end
  local yeti = H.PutOnDeck(g, 2, "CS2_182")

  local lord = H.Put(g, 1, "FP1_009")
  g.bus:Block(function() g:DealDamage(lord, 99, nil, false) end)

  H.board(g, 2, { "CS2_182 4/5" }, "the Yeti walked out of their deck onto their board")
  H.eq(yeti.controller, 2, "they control it")
  H.eq(#theirs.deck, 0, "and it left the deck")
  H.board(g, 1, {}, "nothing landed on your side")
  H.noEngineErrors(g)
end)

H.suite("neutral: Alarm-o-Bot -- swaps itself for a minion in hand at YOUR turn start", function(ns, H)
  local g = H.NewGame({ firstPlayer = 2 })
  local p = g.players[1]
  local bot = H.Put(g, 1, "EX1_006")
  -- The opening hand is filler Wisps, which are minions: clear it so the random
  -- pick can only be the Yeti and the assertion means something.
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
  local _, yeti = H.Hand(g, 1, "CS2_182")

  g:EndTurn()                                  -- their turn ends, yours begins
  g.bus:Drain()
  H.board(g, 1, { "CS2_182 4/5" }, "the Yeti came out of hand into the Bot's slot")
  H.eq(yeti.zone, ns.ZONE.PLAY, "and it really is that Yeti")
  H.eq(bot.zone, ns.ZONE.HAND, "while the Bot went to hand")
  H.noEngineErrors(g)
end)

H.suite("neutral: Alarm-o-Bot sits still on the OPPONENT's turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  local p = g.players[1]
  local bot = H.Put(g, 1, "EX1_006")
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
  H.Hand(g, 1, "CS2_182")

  g:EndTurn()                                  -- your turn ends, THEIRS begins
  g.bus:Drain()
  H.board(g, 1, { "EX1_006 0/3" }, "the Bot is still on the board")
  H.eq(bot.zone, ns.ZONE.PLAY, "TURN_BEGIN fires for both players, PayloadIsMine gates it")
  H.noEngineErrors(g)
end)

--============================================================ the random ones
--
--   Everything below rolls from the shared seeded stream, so a single game
--   proves almost nothing: it would pass just as happily against a hardcoded
--   answer. These sweep a range of seeds and assert the PROPERTY that must hold
--   for every roll, plus that more than one outcome is reachable.

H.suite("neutral: Tinkmaster Overspark -- a Devilsaur OR a Squirrel, never himself", function(ns, H)
  local seen, errs, keptSelf = {}, 0, true
  for s = 1, 30 do
    local g = H.NewGame({ seed = s * 613 })
    H.Mana(g, 1, 10)
    H.Put(g, 2, "CS2_182")
    local i = H.Hand(g, 1, "EX1_083")
    g:PlayCard(1, i)
    g.bus:Drain()
    errs = errs + #g.errors
    seen[g.players[2].board[1].cardId] = true
    if g.players[1].board[1].cardId ~= "EX1_083" then keptSelf = false end
  end
  H.eq(errs, 0, "no engine errors across 30 seeds")
  H.ok(seen["EX1_tk29"], "the 5/5 Devilsaur turns up")
  H.ok(seen["EX1_tk28"], "the 1/1 Squirrel turns up")
  H.notOk(seen["CS2_182"], "the Yeti is always transformed into one of the two")
  H.ok(keptSelf, "and Tinkmaster never transforms HIMSELF -- `!self`")
end)

H.suite("neutral: Tinkmaster alone on the board transforms nothing", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_083")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.board(g, 1, { "EX1_083 3/3" }, "with no other minion there is nothing to hit")
  H.noEngineErrors(g)
end)

H.suite("neutral: Nat Pagle -- sometimes an extra card, on YOUR turn only", function(ns, H)
  local function turn(seed)
    local g = H.NewGame({ firstPlayer = 2, seed = seed })
    H.Put(g, 1, "EX1_557")
    local before = #g.players[1].deck
    g:EndTurn()                                -- their turn ends, yours begins
    g.bus:Drain()
    return before - #g.players[1].deck, #g.errors
  end
  local counts, errs = {}, 0
  for s = 1, 40 do
    local drawn, e = turn(s * 271)
    errs = errs + e
    counts[drawn] = (counts[drawn] or 0) + 1
  end
  H.eq(errs, 0, "no engine errors across 40 turns")
  H.ok((counts[1] or 0) > 0, "some turns draw only the normal card")
  H.ok((counts[2] or 0) > 0, "and some draw an extra one")
  H.eq((counts[1] or 0) + (counts[2] or 0), 40, "and it is never anything else")

  -- The roll must come from the SEEDED stream, or lockstep desyncs.
  local a = turn(4242)
  local b = turn(4242)
  H.eq(a, b, "the same seed flips the same way")
end)

H.suite("neutral: Nat Pagle never draws on the OPPONENT's turn", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.Put(g, 1, "EX1_557")
  local before = #g.players[1].deck
  g:EndTurn()                                  -- your turn ends, THEIRS begins
  g.bus:Drain()
  H.eq(#g.players[1].deck, before, "your deck is untouched")
  H.noEngineErrors(g)
end)

--[[ The three "summon a random minion" deathrattles. The shape is identical;
     only the pool filter differs, which is exactly what each one is asserting. ]]
local function randomDeathrattle(H, cardId, check, label)
  local bad, seen, errs = nil, {}, 0
  for s = 1, 15 do
    local g = H.NewGame({ seed = s * 977 })
    local host = H.Put(g, 1, cardId)
    g.bus:Block(function() g:DealDamage(host, 99, nil, false) end)
    errs = errs + #g.errors
    local made = g.players[1].board[1]
    if not made then
      bad = "nothing was summoned"
    else
      local pr = g:Printed(made.cardId)
      seen[made.cardId] = true
      if pr.type ~= "MINION"  then bad = made.cardId .. " is not a minion" end
      if not pr.collectible   then bad = made.cardId .. " is not collectible" end
      local why = check(pr)
      if why then bad = made.cardId .. " " .. why end
    end
  end
  H.eq(bad, nil, label)
  H.eq(errs, 0, "and no engine errors")
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  H.ok(n > 1, "and the roll is genuinely varied (" .. n .. " different minions)")
end

H.suite("neutral: Piloted Shredder -- deathrattle summons a random 2-Cost minion", function(ns, H)
  randomDeathrattle(H, "GVG_096",
    function(pr) if pr.cost ~= 2 then return "does not cost 2" end end,
    "every roll was a collectible 2-Cost minion")
end)

H.suite("neutral: Piloted Sky Golem -- deathrattle summons a random 4-Cost minion", function(ns, H)
  randomDeathrattle(H, "GVG_105",
    function(pr) if pr.cost ~= 4 then return "does not cost 4" end end,
    "every roll was a collectible 4-Cost minion")
end)

H.suite("neutral: Sneed's Old Shredder -- deathrattle summons a random LEGENDARY", function(ns, H)
  randomDeathrattle(H, "GVG_114",
    function(pr) if pr.rarity ~= "LEGENDARY" then return "is not legendary" end end,
    "every roll was a collectible legendary minion")
end)

H.suite("neutral: Enhance-o Mechano -- each OTHER minion rolls its OWN keyword", function(ns, H)
  local TRIO = { ns.KEYWORD.WINDFURY, ns.KEYWORD.TAUNT, ns.KEYWORD.DIVINE_SHIELD }
  local function which(e)
    local got, n = nil, 0
    for _, k in ipairs(TRIO) do if e:Has(k) then n = n + 1; got = k end end
    return got, n
  end
  local bad, differed, errs = nil, false, 0
  for s = 1, 25 do
    local g = H.NewGame({ seed = s * 1049 })
    H.Mana(g, 1, 10)
    local wisp = H.Put(g, 1, "CS2_231")
    local yeti = H.Put(g, 1, "CS2_182")
    local i = H.Hand(g, 1, "GVG_107")
    g:PlayCard(1, i)
    g.bus:Drain()
    errs = errs + #g.errors
    local ka, na = which(wisp)
    local kb, nb = which(yeti)
    local _,  nm = which(g.players[1].board[3])
    if na ~= 1 then bad = "the Wisp got " .. na .. " keywords, not exactly one" end
    if nb ~= 1 then bad = "the Yeti got " .. nb .. " keywords, not exactly one" end
    if nm ~= 0 then bad = "Enhance-o Mechano buffed ITSELF" end
    if ka ~= kb then differed = true end
  end
  H.eq(bad, nil, "every other minion got exactly one of the three")
  H.eq(errs, 0, "and no engine errors")
  --[[ THE assertion that separates ForEach-around-OneOf from OneOf-around-
       ForEach: one roll for the whole board would make these always equal. ]]
  H.ok(differed, "two minions can roll DIFFERENT keywords -- each rolls its own")
end)

H.suite("neutral: Recombobulator -- rerolls the target at ITS cost, not a fixed one", function(ns, H)
  local function reroll(hostId, wantCost)
    local bad, changed, errs = nil, false, 0
    for s = 1, 15 do
      local g = H.NewGame({ seed = s * 4099 })
      H.Mana(g, 1, 10)
      local victim = H.Put(g, 1, hostId)
      local bystander = H.Put(g, 1, "CS2_231")
      local i = H.Hand(g, 1, "GVG_108")
      g:PlayCard(1, i, victim)
      g.bus:Drain()
      errs = errs + #g.errors
      local pr = g:Printed(victim.cardId)
      if pr.cost ~= wantCost then bad = victim.cardId .. " does not cost " .. wantCost end
      if pr.type ~= "MINION" or not pr.collectible then
        bad = victim.cardId .. " is not a collectible minion"
      end
      if bystander.cardId ~= "CS2_231" then bad = "the untargeted Wisp was rerolled too" end
      if victim.cardId ~= hostId then changed = true end
    end
    return bad, changed, errs
  end

  local bad, changed, errs = reroll("CS2_182", 4)     -- Chillwind Yeti, 4 mana
  H.eq(bad, nil, "a 4-cost target always became another 4-cost minion")
  H.ok(changed, "and it really does reroll")
  H.eq(errs, 0, "no engine errors")

  bad, changed, errs = reroll("CS2_200", 6)           -- Boulderfist Ogre, 6 mana
  H.eq(bad, nil, "a 6-cost target always became another 6-cost minion")
  H.ok(changed, "and that one rerolls too")
  H.eq(errs, 0, "still no engine errors")
end)

H.suite("neutral: Foe Reaper 4000 -- splashes the minions flanking his victim", function(ns, H)
  local g = H.NewGame()
  local reaper = H.Put(g, 1, "GVG_113")        -- 6/9
  H.Put(g, 2, "CS2_200")                       -- Boulderfist Ogre 6/7
  local mid = H.Put(g, 2, "CS2_200")
  H.Put(g, 2, "CS2_200")

  g:Attack(reaper, mid)
  g.bus:Drain()
  H.board(g, 2, { "CS2_200 6/1", "CS2_200 6/1", "CS2_200 6/1" },
          "the victim took 6 and so did both neighbours")
  H.board(g, 1, { "GVG_113 6/3" }, "and the Ogre hit back for 6")
  H.noEngineErrors(g)
end)

H.suite("neutral: Foe Reaper splashes even when the blow KILLS his victim", function(ns, H)
  --[[ The queued trigger runs before ProcessDeaths, so the dead defender is
       still in its board slot and its neighbours are still reachable. Move the
       splash after the death phase and this goes red. ]]
  local g = H.NewGame()
  local reaper = H.Put(g, 1, "GVG_113")
  H.Put(g, 2, "CS2_200")
  local yeti = H.Put(g, 2, "CS2_182")          -- 4/5: dies to the 6
  H.Put(g, 2, "CS2_200")

  g:Attack(reaper, yeti)
  g.bus:Drain()
  H.board(g, 2, { "CS2_200 6/1", "CS2_200 6/1" }, "the Yeti died and both Ogres were splashed")
  H.board(g, 1, { "GVG_113 6/5" }, "the Yeti hit back for 4 on its way out")
  H.noEngineErrors(g)
end)

H.suite("neutral: Foe Reaper going face splashes nothing", function(ns, H)
  local g = H.NewGame()
  local reaper = H.Put(g, 1, "GVG_113")
  H.Put(g, 2, "CS2_200")
  H.Put(g, 2, "CS2_200")

  g:Attack(reaper, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 30 - 6, "the hero took the hit")
  H.board(g, 2, { "CS2_200 6/7", "CS2_200 6/7" }, "a hero has no neighbours")
  H.noEngineErrors(g)
end)

H.suite("neutral: Foe Reaper does NOT splash when he is the one ATTACKED", function(ns, H)
  -- "the minions next to whomever HE attacks" -- PayloadAttackerIsSelf, not
  -- merely "an attack happened".
  local g = H.NewGame({ firstPlayer = 2 })
  H.Put(g, 1, "GVG_113")
  local neighbour = H.Put(g, 1, "CS2_200")     -- sits right of the Reaper
  local ogre = H.Put(g, 2, "CS2_200")

  g:Attack(ogre, g.players[1].board[1])
  g.bus:Drain()
  H.board(g, 1, { "GVG_113 6/3", "CS2_200 6/7" },
          "the Reaper took 6 and his neighbour was left alone")
  H.eq(neighbour:Health(), 7, "no splash on the defending side")
  H.noEngineErrors(g)
end)

H.suite("neutral: Gazlowe -- a 1-mana spell, and ONLY a 1-mana spell, pays a Mech", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "GVG_117")
  local p = g.players[1]

  local before = #p.hand
  local i = H.Hand(g, 1, "CS2_027")            -- Mirror Image, 1 mana
  H.ok(g:PlayCard(1, i), "cast a 1-mana spell")
  g.bus:Drain()
  -- +1 added, -1 played, +1 Mech = net +1
  H.eq(#p.hand, before + 1, "a card arrived in hand")
  local got = g:Printed(p.hand[#p.hand].cardId)
  H.eq(got.race, "MECHANICAL", "and it is a Mech")
  H.eq(got.type, "MINION", "a Mech MINION")
  H.ok(got.collectible, "from the collectible pool")

  --[[ The Coin costs 0. PayloadCostAtMost(1) on its own would fire on it, which
       is why the condition pins the lower bound as well. ]]
  H.SetActive(g, 1)
  before = #p.hand
  local j = H.Hand(g, 1, "GAME_005")
  H.ok(g:PlayCard(1, j), "played The Coin")
  g.bus:Drain()
  H.eq(#p.hand, before, "a 0-mana spell pays nothing")

  H.SetActive(g, 1)
  before = #p.hand
  local k = H.Hand(g, 1, "CS2_025")            -- Arcane Explosion, 2 mana
  H.ok(g:PlayCard(1, k), "cast a 2-mana spell")
  g.bus:Drain()
  H.eq(#p.hand, before, "and neither does a 2-mana one")
  H.noEngineErrors(g)
end)

H.suite("neutral: Gazlowe ignores the OPPONENT's 1-mana spells", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE", firstPlayer = 2 })
  H.Mana(g, 2, 10)
  H.Put(g, 1, "GVG_117")
  local before = #g.players[1].hand
  local i = H.Hand(g, 2, "CS2_027")
  H.ok(g:PlayCard(2, i), "they cast a 1-mana spell")
  g.bus:Drain()
  H.eq(#g.players[1].hand, before, "your hand did not grow")
  H.noEngineErrors(g)
end)

H.suite("neutral: Blingtron 3000 -- a random weapon for EACH player", function(ns, H)
  local bad, differed, errs = nil, false, 0
  for s = 1, 20 do
    local g = H.NewGame({ seed = s * 1571 })
    H.Mana(g, 1, 10)
    local i = H.Hand(g, 1, "GVG_119")
    g:PlayCard(1, i)
    g.bus:Drain()
    errs = errs + #g.errors
    local mine, theirs = g.players[1].weapon, g.players[2].weapon
    if not mine   then bad = "you got no weapon" end
    if not theirs then bad = "the opponent got no weapon" end
    if mine and theirs then
      for _, w in ipairs({ mine, theirs }) do
        local pr = g:Printed(w.cardId)
        if pr.type ~= "WEAPON"  then bad = w.cardId .. " is not a weapon" end
        if not pr.collectible   then bad = w.cardId .. " is not collectible" end
      end
      if mine.cardId ~= theirs.cardId then differed = true end
    end
  end
  H.eq(bad, nil, "both players are armed on every roll")
  H.eq(errs, 0, "and no engine errors")
  H.ok(differed, "the two rolls are independent -- they are not always the same weapon")
end)

H.suite("neutral: Blingtron replaces a weapon you already had", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  g:EquipWeapon(1, "CS2_106")                  -- Fiery War Axe
  H.eq(g.players[1].weapon.cardId, "CS2_106", "the Axe is equipped")
  local i = H.Hand(g, 1, "GVG_119")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.ok(g.players[1].weapon, "you still have a weapon afterwards")
  H.ok(g.players[2].weapon, "and so do they")
  H.eq(#g.players[1].board, 1, "only Blingtron is on the board")
  H.noEngineErrors(g)
end)

--============================================================ the two that
--   turned out to be expressible after all, with no new primitive: Cho by
--   putting the side-choice inside an If/else, Jeeves by unrolling the
--   draw-up-to-three because the amount DSL has no subtraction.

H.suite("neutral: Lorewalker Cho -- the copy goes to the OTHER player", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "EX1_100")
  local mine, theirs = g.players[1], g.players[2]

  local mineBefore, theirsBefore = #mine.hand, #theirs.hand
  local i = H.Hand(g, 1, "CS2_023")            -- Arcane Intellect: draw 2
  H.ok(g:PlayCard(1, i), "you cast a spell")
  g.bus:Drain()
  H.eq(#theirs.hand, theirsBefore + 1, "the OPPONENT got the copy")
  H.eq(theirs.hand[#theirs.hand].cardId, "CS2_023", "and it is the spell you cast")
  -- +1 added, -1 played, +2 drawn = net +2. A third would mean Cho copied it
  -- back to the caster as well.
  H.eq(#mine.hand, mineBefore + 2, "the caster gets no copy of their own spell")

  -- ...and it works the other way round, with Cho still on YOUR board.
  g.activePlayer = 2
  H.Mana(g, 2, 10)
  mineBefore = #mine.hand
  local j = H.Hand(g, 2, "CS2_023")
  H.ok(g:PlayCard(2, j), "they cast a spell")
  g.bus:Drain()
  H.eq(#mine.hand, mineBefore + 1, "YOU got the copy")
  H.eq(mine.hand[#mine.hand].cardId, "CS2_023", "and it is their spell")

  -- A minion is not a spell.
  H.SetActive(g, 1)
  theirsBefore = #theirs.hand
  local k = H.Hand(g, 1, "CS2_182")
  H.ok(g:PlayCard(1, k), "you played a minion")
  g.bus:Drain()
  H.eq(#theirs.hand, theirsBefore, "and nothing was copied")
  H.noEngineErrors(g)
end)

H.suite("neutral: Lorewalker Cho copies a Secret too", function(ns, H)
  --[[ A Secret is a SPELL in printed data, but Game:PlayCard never raises
       SPELL_CAST for one -- it goes straight to the secret zone. Hooking
       CARD_PLAYED + PayloadIsSpell is what keeps Secrets in scope. ]]
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "EX1_100")
  local theirs = g.players[2]
  local before = #theirs.hand
  local i = H.Hand(g, 1, "EX1_289")            -- Ice Barrier
  H.ok(g:PlayCard(1, i), "you played a Secret")
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "the Secret went live for you")
  H.eq(#theirs.hand, before + 1, "and a copy went to the opponent")
  H.eq(theirs.hand[#theirs.hand].cardId, "EX1_289", "the same Secret")
  H.noEngineErrors(g)
end)

H.suite("neutral: Jeeves -- at each turn end THAT player draws up to three", function(ns, H)
  local g = H.NewGame()
  local mine, theirs = g.players[1], g.players[2]
  H.Put(g, 1, "GVG_094")
  local function setHand(p, n)
    for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
    for _ = 1, n do H.Hand(g, p.index, "CS2_231") end
  end

  setHand(mine, 1)
  setHand(theirs, 1)
  g:EndTurn()                                  -- YOUR turn ends
  g.bus:Drain()
  H.eq(#mine.hand, 3, "you were topped up to three")
  -- their BeginTurn drew them one; Jeeves must NOT have topped them up as well
  H.eq(#theirs.hand, 2, "the opponent only took their normal draw")

  setHand(mine, 1)
  setHand(theirs, 1)
  g:EndTurn()                                  -- THEIR turn ends
  g.bus:Drain()
  H.eq(#theirs.hand, 3, "they were topped up to three")
  H.eq(#mine.hand, 2, "and you only took your normal draw")
  H.noEngineErrors(g)
end)

H.suite("neutral: Jeeves draws nothing for a hand already past three", function(ns, H)
  local g = H.NewGame()
  local mine = g.players[1]
  H.Put(g, 1, "GVG_094")
  for i = #mine.hand, 1, -1 do table.remove(mine.hand, i) end
  for _ = 1, 5 do H.Hand(g, 1, "CS2_231") end
  local deckBefore = #mine.deck

  g:EndTurn()
  g.bus:Drain()
  H.eq(#mine.hand, 5, "a hand of five is left alone")
  H.eq(#mine.deck, deckBefore, "and not one card left the deck")
  H.noEngineErrors(g)
end)

--============================================================ round 3: the
--   four unblocked by GiveSpellDamage, the `property` hook, BecomeCopy and
--   StealSecret.
--
--   Extra fixtures:
--     EX1_029  Leper Gnome        1 mana 2/1, Deathrattle: 2 to the enemy hero
--     CS2_179  Sen'jin Shieldmasta 4 mana 3/5 Taunt
--     CS2_024  Frostbolt          2 mana MAGE spell, $3 damage and Freeze

H.suite("neutral: Faceless Manipulator -- becomes the CURRENT minion, not the printed one", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 2, "CS2_182")          -- printed 4/5
  yeti:AddEnchantment(2, 2)
  g:RecalcAuras()
  H.board(g, 2, { "CS2_182 6/7" }, "their Yeti is buffed to 6/7")

  local i, faceless = H.Hand(g, 1, "EX1_564")
  H.ok(g:PlayCard(1, i, yeti), "Faceless resolved")
  g.bus:Drain()
  H.board(g, 1, { "CS2_182 6/7" }, "it copied the 6/7, not the printed 4/5")
  H.eq(g.players[1].board[1], faceless, "and it is the same entity, transformed in place")
  H.board(g, 2, { "CS2_182 6/7" }, "the original is untouched")
  H.noEngineErrors(g)
end)

H.suite("neutral: Faceless Manipulator copies keywords and Deathrattles", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1, 10)
  local taunter = H.Put(g, 2, "CS2_179")       -- Sen'jin Shieldmasta, Taunt
  local i = H.Hand(g, 1, "EX1_564")
  H.ok(g:PlayCard(1, i, taunter))
  g.bus:Drain()
  local copy = g.players[1].board[1]
  H.eq(copy.cardId, "CS2_179", "it became a Sen'jin Shieldmasta")
  H.ok(copy:IsTaunt(), "with the printed Taunt")

  --[[ The copied deathrattle is re-homed to the COPIER: a Faceless that became
       a Leper Gnome hits the other hero, not its own. ]]
  local g2 = H.NewGame()
  H.Mana(g2, 1, 10)
  local gnome = H.Put(g2, 2, "EX1_029")
  local j = H.Hand(g2, 1, "EX1_564")
  H.ok(g2:PlayCard(1, j, gnome))
  g2.bus:Drain()
  local mine = g2.players[1].board[1]
  H.eq(mine.cardId, "EX1_029", "it became a Leper Gnome")
  g2.bus:Block(function() g2:DealDamage(mine, 99, nil, false) end)
  H.eq(H.Hero(g2, 2):Health(), 30 - 2, "and the copied deathrattle hit THEIR hero")
  H.eq(H.Hero(g2, 1):Health(), 30, "not yours")
  H.noEngineErrors(g2)
end)

H.suite("neutral: Ancient Mage -- Spell Damage +1 to the two it lands between", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.Mana(g, 1, 10)
  local left  = H.Put(g, 1, "CS2_231")
  local right = H.Put(g, 1, "CS2_231")
  local far   = H.Put(g, 1, "CS2_231")
  local i, mage = H.Hand(g, 1, "EX1_584")
  H.ok(g:PlayCard(1, i, nil, 2), "the Mage landed in slot 2")
  g.bus:Drain()
  H.eq(g.players[1].board[2], mage, "board reads Wisp, Mage, Wisp, Wisp")

  H.eq(left.spellDamageBonus, 1, "the Wisp on its left got Spell Damage +1")
  H.eq(right.spellDamageBonus, 1, "and the one on its right")
  H.notOk(far.spellDamageBonus, "the Wisp further along got nothing")
  H.notOk(mage.spellDamageBonus, "and the Mage itself got nothing")
  H.eq(g:SpellPower(1), 2, "so your Spell Damage totals +2")

  local ogre = H.Put(g, 2, "CS2_200")          -- 6/7
  local j = H.Hand(g, 1, "CS2_024")            -- Frostbolt, $3
  H.ok(g:PlayCard(1, j, ogre))
  g.bus:Drain()
  H.eq(ogre:Health(), 7 - 5, "Frostbolt dealt 3 + 2 -- a GRANTED bonus really scales spells")
  H.noEngineErrors(g)
end)

H.suite("neutral: Ancient Mage with nothing beside it gives nothing away", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_584")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.eq(g:SpellPower(1), 0, "no neighbours, no bonus")
  H.noEngineErrors(g)
end)

H.suite("neutral: Baron Rivendare -- your Deathrattles fire twice", function(ns, H)
  local g = H.NewGame()
  local gnome = H.Put(g, 1, "EX1_029")         -- Leper Gnome: 2 to the enemy hero
  g.bus:Block(function() g:DealDamage(gnome, 99, nil, false) end)
  H.eq(H.Hero(g, 2):Health(), 30 - 2, "without the Baron it fires once")
  H.noEngineErrors(g)

  local g2 = H.NewGame()
  H.Put(g2, 1, "FP1_031")
  local gnome2 = H.Put(g2, 1, "EX1_029")
  g2.bus:Block(function() g2:DealDamage(gnome2, 99, nil, false) end)
  H.eq(H.Hero(g2, 2):Health(), 30 - 4, "with the Baron out it fires twice")
  H.noEngineErrors(g2)
end)

H.suite("neutral: two Barons are still twice, not four times", function(ns, H)
  -- The highest multiplier wins rather than multiplying, which is Hearthstone.
  local g = H.NewGame()
  H.Put(g, 1, "FP1_031")
  H.Put(g, 1, "FP1_031")
  local gnome = H.Put(g, 1, "EX1_029")
  g.bus:Block(function() g:DealDamage(gnome, 99, nil, false) end)
  H.eq(H.Hero(g, 2):Health(), 30 - 4, "still two triggers, not four")
  H.noEngineErrors(g)
end)

H.suite("neutral: Baron Rivendare does nothing for the OPPONENT's Deathrattles", function(ns, H)
  -- "YOUR minions". The multiplier is read per player from that player's board.
  local g = H.NewGame()
  H.Put(g, 1, "FP1_031")
  local theirs = H.Put(g, 2, "EX1_029")        -- their Gnome hits YOUR hero
  g.bus:Block(function() g:DealDamage(theirs, 99, nil, false) end)
  H.eq(H.Hero(g, 1):Health(), 30 - 2, "their deathrattle fired once")
  H.noEngineErrors(g)
end)

H.suite("neutral: silencing the Baron takes the doubling with it", function(ns, H)
  local g = H.NewGame()
  local baron = H.Put(g, 1, "FP1_031")
  local gnome = H.Put(g, 1, "EX1_029")
  baron:Silence()
  g:RecalcAuras()
  g.bus:Block(function() g:DealDamage(gnome, 99, nil, false) end)
  H.eq(H.Hero(g, 2):Health(), 30 - 2, "a silenced Baron doubles nothing")
  H.noEngineErrors(g)
end)

H.suite("neutral: Kezan Mystic -- steals an enemy Secret, and it then works for YOU", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE", firstPlayer = 2 })
  H.Mana(g, 2, 10)
  local i = H.Hand(g, 2, "EX1_289")            -- Ice Barrier: 8 Armor when attacked
  H.ok(g:PlayCard(2, i), "they armed a Secret")
  g.bus:Drain()
  H.eq(#g.players[2].secrets, 1, "it is live on their side")

  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local j = H.Hand(g, 1, "GVG_074")
  H.ok(g:PlayCard(1, j), "Kezan Mystic resolved")
  g.bus:Drain()
  H.eq(#g.players[2].secrets, 0, "their secret zone is empty")
  H.eq(#g.players[1].secrets, 1, "and yours holds it")
  local stolen = g.players[1].secrets[1]
  H.eq(stolen.cardId, "EX1_289", "the Ice Barrier")
  H.eq(stolen.controller, 1, "under your control")
  H.eq(stolen.owner, 1, "and re-homed, so it does not bounce back to them")

  --[[ The real proof of ownership: a secret answers the OPPONENT's action, so
       this one must now fire when THEY attack YOUR hero, and the armor must
       land on YOUR hero. ]]
  H.SetActive(g, 2)
  local ogre = H.Put(g, 2, "CS2_200")
  g:Attack(ogre, H.Hero(g, 1))
  g.bus:Drain()
  H.eq(H.Hero(g, 1).armor, 8 - 6, "your hero gained 8 Armor and the 6 came off it")
  H.eq(H.Hero(g, 1):Health(), 30, "so no health was lost")
  H.eq(H.Hero(g, 2).armor, 0, "and they got nothing")
  H.eq(#g.players[1].secrets, 0, "the secret was spent")
  H.noEngineErrors(g)
end)

H.suite("neutral: a stolen Secret you already have is destroyed, not doubled up", function(ns, H)
  --[[ Hearthstone forbids two copies of the same Secret in one zone, which is
       the rule PlaySecret enforces for every other route in. ]]
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE", firstPlayer = 2 })
  H.Mana(g, 2, 10)
  local i = H.Hand(g, 2, "EX1_289")
  H.ok(g:PlayCard(2, i), "they play Ice Barrier")
  g.bus:Drain()

  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local j = H.Hand(g, 1, "EX1_289")
  H.ok(g:PlayCard(1, j), "you play your own Ice Barrier")
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "one each")

  H.SetActive(g, 1)
  local graveBefore = #g.players[1].graveyard
  local k = H.Hand(g, 1, "GVG_074")
  H.ok(g:PlayCard(1, k), "Kezan Mystic resolved")
  g.bus:Drain()
  H.eq(#g.players[2].secrets, 0, "theirs is gone either way")
  H.eq(#g.players[1].secrets, 1, "and yours did NOT become two")
  H.eq(#g.players[1].graveyard, graveBefore + 1, "the stolen duplicate went to your graveyard")
  H.noEngineErrors(g)
end)

H.suite("neutral: Kezan Mystic with no enemy Secret is just a minion", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "GVG_074")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.board(g, 1, { "GVG_074 4/3" }, "he lands with nothing to steal")
  H.eq(#g.players[1].secrets, 0, "and no secret appeared from nowhere")
  H.noEngineErrors(g)
end)
