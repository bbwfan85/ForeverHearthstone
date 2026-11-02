--[[ tests/test_zones.lua -- moving cards BETWEEN zones without playing them.

  Eleven cards do this: "put a Secret from your deck into the battlefield",
  "put a random Demon from your hand into the battlefield", "discard the top 3
  cards of your deck", "put a copy of each friendly minion into your hand".

  Game:MoveToHand only ever handled PLAY -> HAND, because that is all a bounce
  needs. The ops tested here move from ANY zone, and the failure that matters is
  leaving the card in BOTH -- invisible until something iterates the deck and
  finds a minion that is also in hand. Every suite below therefore checks the
  card ARRIVED and that it LEFT.

  Fixtures, verified against the pin:
    CS2_182  Chillwind Yeti     4 mana 4/5 vanilla
    CS2_231  Wisp               0 mana 1/1 vanilla
    NEW1_018 Bloodsail Raider   2 mana 2/3 PIRATE
    EX1_306  Felstalker         2 mana 4/3 DEMON, Battlecry: discard a card
    EX1_289  Ice Barrier        3 mana Mage SECRET
    EX1_006  Alarm-o-Bot        3 mana 0/3
]]
local H = require("tests.harness")

H.suite("zones: MoveToHand pulls a card out of the DECK, not just the board", function(ns, H)
  local g = H.NewGame()
  local p = g.players[1]
  local pirate = H.PutOnDeck(g, 1, "NEW1_018")
  local deckBefore, handBefore = #p.deck, #p.hand

  ns.Ops.Run(g, { { op = "MoveToHand",
                    sel = { side = "FRIENDLY", zone = "DECK", race = "PIRATE",
                            type = "MINION", random = 1 } } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#p.hand, handBefore + 1, "it arrived in hand")
  H.eq(#p.deck, deckBefore - 1, "and LEFT the deck")
  H.eq(p.hand[#p.hand], pirate, "and it is the same entity")
  H.eq(pirate.zone, ns.ZONE.HAND, "its zone says hand")
  local stillInDeck = false
  for _, e in ipairs(p.deck) do if e == pirate then stillInDeck = true end end
  H.notOk(stillInDeck, "it is not in the deck as well")
  H.noEngineErrors(g)
end)

H.suite("zones: MoveToBoard puts a minion into play without playing it", function(ns, H)
  -- Voidcaller. No mana is paid and no battlecry fires, but it IS a summon.
  local g = H.NewGame()
  local p = g.players[1]
  local _, demon = H.Hand(g, 1, "EX1_306")
  local handBefore = #p.hand
  local manaBefore = p.mana

  ns.Ops.Run(g, { { op = "MoveToBoard",
                    sel = { side = "FRIENDLY", zone = "HAND", race = "DEMON",
                            type = "MINION", random = 1 } } },
             { source = H.Hero(g, 1), controller = 1 })
  g.bus:Drain()
  H.eq(#p.board, 1, "it is on the board")
  H.eq(p.board[1], demon, "and it is the same entity")
  H.eq(#p.hand, handBefore - 1, "it left the hand, and nothing else did")
  H.eq(p.mana, manaBefore, "no mana was paid")
  H.noEngineErrors(g)
end)

H.suite("zones: MoveToBoard respects the board cap", function(ns, H)
  local g = H.NewGame()
  local p = g.players[1]
  for _ = 1, ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  local _, demon = H.Hand(g, 1, "EX1_306")
  local handBefore = #p.hand
  ns.Ops.Run(g, { { op = "MoveToBoard",
                    sel = { side = "FRIENDLY", zone = "HAND", race = "DEMON",
                            type = "MINION", random = 1 } } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#p.board, ns.RULES.BOARD_SLOTS, "the board did not overflow")
  H.eq(#p.hand, handBefore, "and the card stayed in hand")
  H.eq(demon.zone, ns.ZONE.HAND, "with its zone intact")
  H.noEngineErrors(g)
end)

H.suite("zones: MoveToSecret finds a Secret CARD sitting in the deck", function(ns, H)
  --[[ Mad Scientist. `secret` in a selector is the secret ZONE; finding a
       Secret in the DECK needs the card PROPERTY instead, which is what
       isSecret is for. Using the zone filter here would describe where the card
       already is rather than what it is, and match nothing. ]]
  local g = H.NewGame()
  local p = g.players[1]
  local sec = H.PutOnDeck(g, 1, "EX1_289")
  H.PutOnDeck(g, 1, "CS2_182")            -- a minion, excluded by type anyway
  H.PutOnDeck(g, 1, "CS2_024")            -- Frostbolt: a SPELL that is NOT a Secret

  --[[ The Frostbolt is the point. Without it, `type=SPELL` alone already
       narrows the deck to the one Secret, and the isSecret filter could be
       doing nothing at all without any test noticing. ]]
  local matches = ns.Selector.Resolve(g,
    { side = "FRIENDLY", zone = "DECK", isSecret = true, type = "SPELL" },
    { controller = 1 })
  H.eq(#matches, 1, "only the Secret matches, not the Frostbolt")
  H.eq(matches[1], sec, "and it is the Ice Barrier")

  ns.Ops.Run(g, { { op = "MoveToSecret",
                    sel = { side = "FRIENDLY", zone = "DECK", isSecret = true,
                            type = "SPELL", random = 1 } } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#p.secrets, 1, "a secret went active")
  H.eq(p.secrets[1], sec, "and it is the Ice Barrier from the deck")
  H.eq(sec.zone, ns.ZONE.SECRET, "its zone says secret")
  H.noEngineErrors(g)
end)

H.suite("zones: MillDeck discards from the TOP, which is where Draw pops from", function(ns, H)
  --[[ The top of the deck is the END of the array. Milling from the front would
       silently discard the bottom, and the cards the player then drew would not
       be the ones they were told they lost. ]]
  local g = H.NewGame()
  local p = g.players[1]
  local top = H.PutOnDeck(g, 1, "CS2_182")
  local nextDown = p.deck[#p.deck - 1]
  local deckBefore, graveBefore = #p.deck, #p.graveyard

  ns.Ops.Run(g, { { op = "MillDeck", count = 1 } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#p.deck, deckBefore - 1, "one card left the deck")
  H.eq(#p.graveyard, graveBefore + 1, "and reached the graveyard")
  H.eq(p.graveyard[#p.graveyard], top, "and it was the TOP card")
  H.eq(p.deck[#p.deck], nextDown, "the next card down is now on top")
  H.noEngineErrors(g)
end)

H.suite("zones: MillDeck on an empty deck stops rather than erroring", function(ns, H)
  local g = H.NewGame()
  local p = g.players[1]
  for i = #p.deck, 1, -1 do table.remove(p.deck, i) end
  ns.Ops.Run(g, { { op = "MillDeck", count = 3 } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#p.deck, 0, "still empty")
  H.noEngineErrors(g)
end)

H.suite("zones: ShuffleCardIn puts a card in the OPPONENT's deck, owned by them", function(ns, H)
  -- Iron Juggernaut. The card must belong to the player whose deck holds it, or
  -- it would draw for the wrong player.
  local g = H.NewGame()
  local foe = g.players[2]
  local before = #foe.deck
  ns.Ops.Run(g, { { op = "ShuffleCardIn", cardId = "CS2_182", side = "ENEMY" } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#foe.deck, before + 1, "their deck grew")
  local found
  for _, e in ipairs(foe.deck) do if e.cardId == "CS2_182" then found = e end end
  H.ok(found, "the card is in there")
  H.eq(found.owner, 2, "and it belongs to THEM, so it draws for them")
  H.noEngineErrors(g)
end)

H.suite("zones: CopyToHand copies the PRINTED card, not the buffed one", function(ns, H)
  --[[ Echo of Medivh copies a Yeti that has been buffed to 6/7 as a plain
       printed 4/5 -- the enchantment does not travel with the copy. ]]
  local g = H.NewGame()
  local p = g.players[1]
  local yeti = H.Put(g, 1, "CS2_182")
  yeti.ench.atk = 2
  yeti.ench.hp = 2
  yeti:RecalcTimed()
  H.eq(g:AttackValue(yeti), 6, "the original is buffed")

  local before = #p.hand
  ns.Ops.Run(g, { { op = "CopyToHand", sel = { side = "FRIENDLY", type = "MINION" } } },
             { source = H.Hero(g, 1), controller = 1 })
  H.eq(#p.hand, before + 1, "one copy arrived")
  local copy = p.hand[#p.hand]
  H.eq(copy.cardId, "CS2_182", "it is a Yeti")
  H.eq(copy:Attack(), copy.printed.atk, "at printed attack, not buffed")
  H.eq(copy:Health(), copy.printed.hp, "and printed health")
  H.noEngineErrors(g)
end)

H.suite("zones: SwapWithHand exchanges the minion for one in hand", function(ns, H)
  -- Alarm-o-Bot. Half a swap would either duplicate the Bot or lose the minion,
  -- so both counts and both zones are checked.
  local g = H.NewGame()
  local p = g.players[1]
  -- The opening hand is filler Wisps, which are minions too -- clear it so the
  -- random pick can only be the Yeti and the assertion means something.
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
  local bot = H.Put(g, 1, "EX1_006")
  local _, yeti = H.Hand(g, 1, "CS2_182")
  local handBefore, boardBefore = #p.hand, #p.board

  ns.Ops.Run(g, { { op = "SwapWithHand",
                    sel = { side = "FRIENDLY", zone = "HAND", type = "MINION",
                            random = 1 } } },
             { source = bot, controller = 1 })
  g.bus:Drain()
  H.eq(#p.board, boardBefore, "the board count is unchanged")
  H.eq(#p.hand, handBefore, "and so is the hand count")
  H.eq(p.board[1], yeti, "the hand minion is now on the board")
  H.eq(bot.zone, ns.ZONE.HAND, "and the Bot is in hand")
  local onBoard = false
  for _, e in ipairs(p.board) do if e == bot then onBoard = true end end
  H.notOk(onBoard, "the Bot is NOT also still on the board")
  H.noEngineErrors(g)
end)
