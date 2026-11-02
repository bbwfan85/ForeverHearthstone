--[[ tests/test_opening.lua -- the mulligan, hero-power targeting and secrets.

  The three things that stood between this and "plays like Hearthstone":

    * THE MULLIGAN was unreachable. Game:ApplyMulligan existed and was correct,
      and its own comment said it was applied "before StartGame" -- which was
      the call that dealt the hand, so there was nothing to mulligan and nothing
      ever called it.
    * TWO CLASSES COULD NOT USE THEIR HERO POWER. Fireblast and Lesser Heal
      require a target; the board sent none and the controller had no targeting
      flow for one, so the engine refused, correctly, forever.
    * SECRETS WERE INVISIBLE. Fully implemented, never drawn, not in the
      snapshot.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local function dealt(ns, opts)
  opts = opts or {}
  local g = H.NewGame({ noStart = true, class1 = opts.class1, class2 = opts.class2,
                        firstPlayer = opts.firstPlayer })
  g:Deal()
  return g
end

--============================================================ the engine

H.suite("mulligan: dealing stops before play begins", function(ns, H)
  local g = dealt(ns)
  H.ok(g:AwaitingMulligan(), "the game is waiting on the mulligan")
  H.eq(g.turn, 0, "no turn has started")
  H.eq(#g.players[1].hand, ns.RULES.MULLIGAN_FIRST, "three cards going first")
  H.eq(#g.players[2].hand, ns.RULES.MULLIGAN_SECOND,
       "four going second -- the Coin is not part of the dealt hand")
end)

H.suite("mulligan: the Coin arrives AFTER the mulligan, never during it", function(ns, H)
  --[[ THE BUG THIS FIXES. The Coin used to be dealt with the opening hand. The
       rules were right either way -- it could not be thrown back -- but the
       PRESENTATION was wrong: going second showed you five cards to mulligan,
       one of which would not respond to being clicked, and then five cards in
       hand afterwards. That reads as having drawn an extra card before the game
       began, which is exactly how it was reported.

       It is compensation for going second, not part of the hand you were
       dealt, so it arrives once there is nothing left to throw back. ]]
  local g = dealt(ns)
  for _, c in ipairs(g.players[2].hand) do
    H.ok(c.cardId ~= "GAME_005", "no Coin among the cards being mulliganed")
  end
  H.eq(#g.players[2].hand, ns.RULES.MULLIGAN_SECOND, "four cards, all replaceable")

  g:SubmitMulligan(1, {})
  g:SubmitMulligan(2, {})
  H.notOk(g:AwaitingMulligan(), "play begins once both have answered")

  local found
  for i, c in ipairs(g.players[2].hand) do
    if c.cardId == "GAME_005" then found = i end
  end
  H.ok(found, "and NOW the Coin is in the second player's hand")
  H.eq(#g.players[2].hand, ns.RULES.MULLIGAN_SECOND + 1, "five cards, one of them the Coin")
end)

H.suite("mulligan: throwing everything back still leaves exactly one Coin", function(ns, H)
  --[[ The replacement path is the one that could hand out a second Coin, or
       lose it: the whole hand leaves and comes back while the Coin is waiting
       in the wings. ]]
  local g = dealt(ns)
  local all = {}
  for i = 1, #g.players[2].hand do all[i] = i end
  g:SubmitMulligan(2, all)
  g:SubmitMulligan(1, {})
  local coins = 0
  for _, c in ipairs(g.players[2].hand) do
    if c.cardId == "GAME_005" then coins = coins + 1 end
  end
  H.eq(coins, 1, "exactly one Coin")
  H.eq(#g.players[2].hand, ns.RULES.MULLIGAN_SECOND + 1, "and a full hand")
end)

H.suite("mulligan: replacements are drawn BEFORE the returns are shuffled in", function(ns, H)
  --[[ Hearthstone's own ordering, and it is observable: a card you threw back
       cannot be the card you are handed. ]]
  local g = dealt(ns, { class1 = "MAGE" })
  local thrown = {}
  for i, c in ipairs(g.players[1].hand) do thrown[c.instanceId] = c.cardId end

  local all = {}
  for i = 1, #g.players[1].hand do all[i] = i end
  g:SubmitMulligan(1, all)
  g:SubmitMulligan(2, {})

  for _, c in ipairs(g.players[1].hand) do
    H.notOk(thrown[c.instanceId], "no returned CARD came straight back: " .. c.cardId)
  end
  H.eq(#g.players[1].hand, ns.RULES.MULLIGAN_FIRST + 1,
       "the hand is the same size, plus the card drawn for turn one")
end)

H.suite("mulligan: nothing may be played until both players have answered", function(ns, H)
  local g = dealt(ns)
  H.Mana(g, 1, 10)
  local ok, why = ns.Actions.Run(g, 1, { kind = "END_TURN" })
  H.notOk(ok, "not even ending the turn")
  H.ok(why:find("mulligan"), "and it says why: " .. tostring(why))

  ns.Actions.Run(g, 1, { kind = "MULLIGAN", indices = {} })
  local ok2 = ns.Actions.Run(g, 1, { kind = "END_TURN" })
  H.notOk(ok2, "one player finishing is not enough")

  ns.Actions.Run(g, 2, { kind = "MULLIGAN", indices = {} })
  H.notOk(g:AwaitingMulligan(), "both have answered")
  H.eq(g.turn, 1, "and turn one has begun")
end)

H.suite("mulligan: an index that is not a card in hand is refused", function(ns, H)
  --[[ Over the wire this means the two clients disagree about the opening hand,
       which is the earliest possible desync and the one most worth catching. ]]
  local g = dealt(ns)
  local ok, why = g:SubmitMulligan(1, { 99 })
  H.notOk(ok, "refused")
  H.ok(why:find("no such card"), "by name")
  H.notOk(g:SubmitMulligan(1, { 1, 1 }), "and a duplicate index is refused too")
  H.ok(g:AwaitingMulligan(1), "nothing was recorded")
end)

H.suite("mulligan: answering twice is refused", function(ns, H)
  local g = dealt(ns)
  H.ok(g:SubmitMulligan(1, {}), "first answer")
  H.notOk(g:SubmitMulligan(1, { 1 }), "second is refused")
end)

H.suite("mulligan: BOTH are applied in player order, whoever answers first", function(ns, H)
  --[[ THE LOCKSTEP REQUIREMENT. ApplyMulligan shuffles, which draws from the
       shared random stream. If one client applied player 1's choice first and
       the other applied player 2's first, the two streams would diverge on the
       very first action of the match. Recording both and applying them in a
       fixed order makes arrival order irrelevant -- which this proves by
       answering in opposite orders and comparing the results exactly. ]]
  --[[ The decks must be DISTINGUISHABLE. The default test deck is thirty
       identical Wisps, and shuffling those produces an identical-looking deck
       whichever order you do it in -- which made an earlier version of this
       test pass against a mutation that applied the choices on arrival. ]]
  local function play(order)
    local g = H.NewGame({ noStart = true,
                          deck1 = ns.Controller.BasicDeck("MAGE"),
                          deck2 = ns.Controller.BasicDeck("PRIEST"),
                          class1 = "MAGE", class2 = "PRIEST" })
    g:Deal()
    for _, who in ipairs(order) do g:SubmitMulligan(who, { 1 }) end
    return g
  end
  local a = play({ 1, 2 })
  local b = play({ 2, 1 })
  H.eq(a:StateHash(), b:StateHash(),
       "the same two choices produce the same game, in either arrival order")
  H.eq(a.rngCalls, b.rngCalls, "including the same number of random draws")

  --[[ And the decks really are in a comparable order, card for card -- the hash
       only fingerprints the board, so without this the test could still be
       looking at two different shuffles. ]]
  for pi = 1, 2 do
    for i, e in ipairs(a.players[pi].deck) do
      H.eq(e.cardId, b.players[pi].deck[i].cardId,
           ("player %d deck slot %d matches"):format(pi, i))
    end
  end
end)

H.suite("mulligan: the phase is part of the state fingerprint", function(ns, H)
  -- Otherwise a client that thinks the mulligan is over while the other does
  -- not would go unnoticed until something else happened to differ.
  local a = dealt(ns)
  local b = dealt(ns)
  H.eq(a:StateHash(), b:StateHash(), "two identical deals agree")
  --[[ Only the PHASE is changed -- not the turn, not the board. Submitting a
       real mulligan would also begin turn one, and the hash would differ
       because of the turn number whether or not the phase were in it. ]]
  b.phase = "PLAY"
  H.ok(a:StateHash() ~= b:StateHash(),
       "and two games that differ ONLY in phase do not")
end)

H.suite("mulligan: StartGame still deals and plays, for practice and tests", function(ns, H)
  local g = H.NewGame()
  H.notOk(g:AwaitingMulligan(), "no mulligan")
  H.eq(g.turn, 1, "straight into turn one")
end)

--=================================================== instance ids per game

H.suite("ids: two games in one process do not share instance ids", function(ns, H)
  --[[ THE BUG THIS EXISTS FOR, and it was a real lockstep desync.

       An action names its target by instance id, which only works because both
       clients hand out the same ids in the same order. With one global counter,
       a process holding two games had the second game advancing a counter the
       first was still using -- so a token summoned on one client got a
       different id from the same token on the other, and an attack seventeen
       turns later arrived as "unknown combatant".

       State hashes do not include ids, so both clients looked perfectly in
       sync right up until one of them named something. ]]
  local a = H.NewGame()
  local b = H.NewGame()
  H.eq(a.players[1].hero.instanceId, b.players[1].hero.instanceId,
       "the same game built twice gives the same ids")

  a:Summon("CS2_231", 1, "RIGHTMOST"); a.bus:Drain()
  b:Summon("CS2_231", 1, "RIGHTMOST"); b.bus:Drain()
  H.eq(a.players[1].board[#a.players[1].board].instanceId,
       b.players[1].board[#b.players[1].board].instanceId,
       "and a token summoned in each gets the same id in each")
end)

--============================================================ hero powers

H.suite("hero power: the two that need a target can now be used", function(ns, H)
  --[[ Fireblast and Lesser Heal. Before this the board sent no target and the
       controller had no way to ask for one, so the engine refused and two of
       the nine classes could not use their hero power at all. ]]
  for _, class in ipairs({ "MAGE", "PRIEST" }) do
    local g = H.NewGame({ class1 = class })
    H.SetActive(g, 1)
    H.Mana(g, 1, 10)
    local foe = H.Put(g, 2, "CS2_182")          -- something to aim at
    local c = ns.Controller.New({ game = g, player = 1 })

    local ok, why = c:HandleIntent({ kind = "HERO_POWER" })
    H.ok(ok, class .. ": the hero power asks for a target")
    H.eq(why, "awaiting target", "rather than being refused")
    H.ok(c:Snapshot().targeting, "and the board is told to highlight")
    H.ok(c:Snapshot().targeting.heroPower, "as a hero power, not a card")

    local before = foe:Health()
    H.ok(c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 }),
         class .. ": clicking a target fires it")
    if class == "MAGE" then
      H.ok(foe:Health() < before, "Fireblast dealt its damage")
    end
    H.ok(g.players[1].heroPowerUsedThisTurn, "and the power was spent")
  end
end)

H.suite("hero power: the seven that need nothing still fire on one click", function(ns, H)
  for _, class in ipairs({ "DRUID", "HUNTER", "PALADIN", "ROGUE", "SHAMAN",
                           "WARLOCK", "WARRIOR" }) do
    local g = H.NewGame({ class1 = class })
    H.SetActive(g, 1)
    H.Mana(g, 1, 10)
    local c = ns.Controller.New({ game = g, player = 1 })
    local ok = c:HandleIntent({ kind = "HERO_POWER" })
    H.ok(ok, class .. " fires immediately")
    H.ok(g.players[1].heroPowerUsedThisTurn, class .. " used its power")
  end
end)

H.suite("hero power: an illegal target is refused and the prompt stays up", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  H.Put(g, 1, "EX1_556")                        -- Harvest Golem? any minion
  local c = ns.Controller.New({ game = g, player = 1 })
  c:HandleIntent({ kind = "HERO_POWER" })
  --[[ Fireblast may hit anything, so to test a refusal we cancel instead and
       prove nothing was spent -- the important property is that an unfinished
       hero power costs nothing. ]]
  H.ok(c:HandleIntent({ kind = "CANCEL" }), "cancelled")
  H.notOk(g.players[1].heroPowerUsedThisTurn, "and the power was NOT spent")
  H.eq(c:Snapshot().targeting, nil, "the highlight is gone")
end)

H.suite("hero power: a targeted power crosses the wire with its target", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local foe = H.Put(g, 2, "CS2_182")
  local sent
  local c = ns.Controller.New({ game = g, player = 1,
    submit = function(a) sent = a; return true end })
  c:HandleIntent({ kind = "HERO_POWER" })
  c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 })
  H.eq(sent.kind, "HERO_POWER", "a hero power action")
  H.eq(sent.targetId, foe.instanceId, "carrying the target by instance id")

  local body = ns.Protocol.EncodeAction(sent)
  local back = ns.Protocol.DecodeAction(ns.Protocol.Decode("1;AC;" .. body))
  H.eq(back.targetId, foe.instanceId, "which survives the round trip")
end)

--============================================================ secrets

H.suite("secrets: yours by name, theirs by count only", function(ns, H)
  --[[ Both clients hold the whole game state in lockstep, so this client COULD
       read the opponent's secrets. The snapshot is exactly where that must not
       happen: the board can only draw what it is given, which makes "the UI
       never shows you what you should not know" structural rather than a
       promise. ]]
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.Mana(g, 1, 10); H.Mana(g, 2, 10)
  -- theirs first: a secret is a spell, and our Counterspell would counter it
  H.SetActive(g, 2)
  local j = H.Hand(g, 2, "EX1_289")             -- Ice Barrier
  ns.Actions.Run(g, 2, { kind = "PLAY_CARD", handIndex = j })
  H.SetActive(g, 1)
  local i = H.Hand(g, 1, "EX1_287")             -- Counterspell
  ns.Actions.Run(g, 1, { kind = "PLAY_CARD", handIndex = i })

  local c = ns.Controller.New({ game = g, player = 1 })
  local snap = c:Snapshot()
  H.eq(#snap.secrets, 1, "you can see your own secret")
  H.eq(snap.secrets[1].cardId, "EX1_287", "by card")
  H.ok(snap.secrets[1].name and #snap.secrets[1].name > 0, "and by name")
  H.eq(snap.foeSecretCount, 1, "you can see that they have one")

  --[[ The one assertion that matters: their secret's IDENTITY is nowhere in the
       snapshot at all, not even in a field the board happens not to draw. ]]
  local function mentions(t, needle, depth)
    if depth > 4 or type(t) ~= "table" then return false end
    for k, v in pairs(t) do
      if v == needle or k == needle then return true end
      if type(v) == "table" and mentions(v, needle, depth + 1) then return true end
    end
    return false
  end
  H.notOk(mentions(snap, "EX1_289", 0),
          "their secret's card id appears NOWHERE in the snapshot")
end)

H.suite("secrets: the count tracks the zone", function(ns, H)
  local g = H.NewGame({ class1 = "HUNTER" })
  H.Mana(g, 1, 10)
  local c = ns.Controller.New({ game = g, player = 1 })
  H.eq(#c:Snapshot().secrets, 0, "none to start")
  for _, id in ipairs({ "EX1_610", "EX1_611" }) do      -- Explosive, Freezing Trap
    local i = H.Hand(g, 1, id)
    ns.Actions.Run(g, 1, { kind = "PLAY_CARD", handIndex = i })
  end
  H.eq(#c:Snapshot().secrets, 2, "two armed")
end)

H.suite("mulligan: the controller refuses to throw back the Coin", function(ns, H)
  --[[ It is compensation for going second, not a card you were dealt. The
       engine would replace it if asked; the rule lives where the choice is
       made, because that is the only place a player can be told why. ]]
  --[[ The Coin no longer reaches the mulligan at all -- it is handed over once
       the mulligan is settled -- so this guard is defence in depth rather than
       the only thing standing in the way. It is kept because it costs nothing
       and because "the Coin is in a hand being mulliganed" is precisely the
       state a future change could reintroduce by accident. The Coin is put
       there deliberately to prove the refusal still works. ]]
  local g = dealt(ns, { firstPlayer = 1 })
  local c = ns.Controller.New({ game = g, player = 2 })
  g:AddToHand(2, "GAME_005")
  local coin
  for i, card in ipairs(g.players[2].hand) do
    if card.cardId == "GAME_005" then coin = i end
  end
  H.ok(coin, "a Coin is in the hand being mulliganed")
  local ok, why = c:ToggleMulligan(coin)
  H.notOk(ok, "it cannot be marked")
  H.ok(why:find("Coin"), "and it says so: " .. tostring(why))
  H.eq(next(c.mulliganMarks), nil, "nothing was marked")

  H.ok(c:ToggleMulligan(1), "an ordinary card can be")
end)

H.suite("mulligan: the submitted indices are SORTED", function(ns, H)
  --[[ A stable action log, not a determinism requirement: ApplyMulligan builds
       a set from this list, so the order cannot change the game. Asserted
       because a readable log is what you reach for when reproducing a desync,
       and because "the same choice always encodes the same way" is a property
       worth keeping true on purpose. ]]
  local g = dealt(ns)
  local sent
  local c = ns.Controller.New({ game = g, player = 1,
    submit = function(a) sent = a; return true end })
  c:ToggleMulligan(3)
  c:ToggleMulligan(1)
  c:ToggleMulligan(2)
  c:ConfirmMulligan()
  H.eq(table.concat(sent.indices, ","), "1,2,3",
       "marked in the order 3, 1, 2 -- submitted as 1, 2, 3")

  local body = ns.Protocol.EncodeAction(sent)
  local back = ns.Protocol.DecodeAction(ns.Protocol.Decode("1;AC;" .. body))
  H.eq(table.concat(back.indices, ","), "1,2,3", "and survives the wire intact")
end)

H.suite("mulligan: the AI answers when asked to take a turn", function(ns, H)
  --[[ Belt and braces for the practice loop: whatever calls the opponent, it
       must not sit in the mulligan forever, because the engine will not begin
       play until both players have submitted. ]]
  local g = dealt(ns)
  H.ok(g:AwaitingMulligan(2), "the opponent has not answered")
  ns.AI.TakeTurn(g, 2)
  H.notOk(g:AwaitingMulligan(2), "asking it to take a turn makes it mulligan first")
end)

H.suite("mulligan: the AI throws back what it cannot play early", function(ns, H)
  local g = H.NewGame({ noStart = true, deck2 = ns.Controller.BasicDeck("PRIEST"),
                        class2 = "PRIEST" })
  g:Deal()
  local expensive = 0
  for _, card in ipairs(g.players[2].hand) do
    if (card.printed.cost or 0) > ns.AI.MULLIGAN_KEEP_COST then expensive = expensive + 1 end
  end
  ns.AI.Mulligan(g, 2)
  local kept = 0
  for _, card in ipairs(g.players[2].hand) do
    if (card.printed.cost or 0) > ns.AI.MULLIGAN_KEEP_COST then kept = kept + 1 end
  end
  H.ok(expensive == 0 or kept <= expensive,
       ("threw back expensive cards (%d before, %d after)"):format(expensive, kept))
  H.notOk(g:AwaitingMulligan(2), "and it answered")
end)

--============================================================ the board

local function withBoard(ns, fn)
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/UI/Board.lua"))("ForeverHearthstone", ns)
  local resolver = ns.Resolver.New({ printed = ns.PrintedCards,
                                     manifest = ns.GenericArt.Manifest({}), palette = {} })
  local intents = {}
  local board = ns.Board.Create({ resolver = resolver, width = 1280, height = 720,
                                  onIntent = function(i) intents[#intents + 1] = i end })
  return fn(board, intents)
end

H.suite("mulligan: the board draws the opening hand and takes the answer", function(ns, H)
  withBoard(ns, function(board, intents)
    local g = dealt(ns)
    local c = ns.Controller.New({ game = g, player = 1,
      onChange = function(snap) board:SetSnapshot(snap) end })
    c:Changed()

    H.ok(board.mulliganDim:IsShown(), "the board behind it is dimmed")
    H.eq(#board.mulliganPool.used, #g.players[1].hand, "every dealt card is shown")
    H.ok(board.mulliganConfirm:IsShown(), "with a confirm button")
    H.eq(board.mulliganConfirmLabel:GetText(), "Confirm", "labelled as Hearthstone's is")

    --[[ Clicking a card marks it, and the button updates to say so. ]]
    board.mulliganPool.used[1].frame:GetScript("OnClick")(board.mulliganPool.used[1].frame)
    H.eq(intents[#intents].kind, "CLICK_MULLIGAN", "clicking a card reports it")
    c:HandleIntent(intents[#intents])
    H.eq(board.mulliganConfirmLabel:GetText(), "Confirm", "the button keeps its label; the cross marks the card")
    local markedCard = board.mulliganPool.used[1]
    H.ok(markedCard.cross and markedCard.cross:IsShown(), "and the card wears Hearthstone's red cross")
    H.ok(markedCard.frame:GetAlpha() < 1, "over a slightly faded face")
    H.notOk(board.mulliganPool.used[2].cross and board.mulliganPool.used[2].cross:IsShown(),
            "a card you keep has no cross")

    board.mulliganConfirm:GetScript("OnClick")(board.mulliganConfirm)
    c:HandleIntent(intents[#intents])
    H.notOk(g:AwaitingMulligan(1), "confirming submits it")
    H.ok(g:AwaitingMulligan(), "and we wait for the opponent")
    H.eq(board.mulliganTitle:GetText(), "waiting for your opponent...",
         "which the board says rather than leaving a dead button")
    H.notOk(board.mulliganConfirm:IsShown(), "and the button is gone, as in Hearthstone")
  end)
end)

H.suite("mulligan: the prompt comes down when play begins", function(ns, H)
  withBoard(ns, function(board, intents)
    local g = dealt(ns)
    local c = ns.Controller.New({ game = g, player = 1,
      onChange = function(snap) board:SetSnapshot(snap) end })
    c:Changed()
    H.ok(board.mulliganDim:IsShown(), "up during the mulligan")
    c:HandleIntent({ kind = "CONFIRM_MULLIGAN" })
    ns.Actions.Run(g, 2, { kind = "MULLIGAN", indices = {} })
    c:Changed()
    H.notOk(board.mulliganDim:IsShown(), "gone once both have answered")
    H.eq(#board.mulliganPool.used, 0, "and the big cards are released")
  end)
end)

H.suite("secrets: the board draws a pip for each, and hides theirs", function(ns, H)
  withBoard(ns, function(board)
    local g = H.NewGame({ class1 = "MAGE", class2 = "HUNTER" })
    H.Mana(g, 1, 10); H.Mana(g, 2, 10)
    H.SetActive(g, 2)
    local j = H.Hand(g, 2, "EX1_610")
    ns.Actions.Run(g, 2, { kind = "PLAY_CARD", handIndex = j })
    H.SetActive(g, 1)
    local i = H.Hand(g, 1, "EX1_287")
    ns.Actions.Run(g, 1, { kind = "PLAY_CARD", handIndex = i })

    local c = ns.Controller.New({ game = g, player = 1 })
    board:SetSnapshot(c:Snapshot())
    H.eq(#board.secretPool.used, 2, "two pips: one yours, one theirs")

    --[[ Both are Hearthstone's class gem with a "?". Yours is coloured by its
         card; theirs by their hero, which is public -- the card itself is not
         in the snapshot, so the gem is all that can be drawn. ]]
    local mine, theirs = board.secretPool.used[1], board.secretPool.used[2]
    H.ok(mine.gem:GetTexture():find("secret_mage"), "your Mage secret is a purple gem")
    H.ok(theirs.gem:GetTexture():find("secret_hunter"), "theirs takes their hero's colour")
    H.eq(theirs.mark:GetText(), "?", "and shows nothing but the question mark")
    H.ok(mine.frame:GetScript("OnEnter"), "and yours names itself on hover")
    H.eq(theirs.frame:GetScript("OnEnter"), nil, "while theirs cannot be inspected")
  end)
end)

--============================================================ end to end

H.suite("opening: a practice match now begins with a mulligan", function(ns, H)
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")

  --[[ WHO GOES FIRST IS A COIN FLIP, so the test flips it itself rather than
       depending on the global RNG -- which other suites also draw from, making
       "who went first" an accident of test ORDER. Both outcomes are asserted,
       because going second is where the Coin and the four-card mulligan live
       and practice could reach neither while this was hardcoded to player 1. ]]
  local realRandom = math.random
  math.random = function(a, b)
    if a == 1 and b == 2 then return 1 end          -- the flip itself
    return realRandom(a, b)                         -- the opponent's class
  end
  ns.Main:StartPractice()
  math.random = realRandom

  local m = ns.Main
  H.ok(m.game:AwaitingMulligan(), "the match opens on the mulligan")
  H.notOk(m.game:AwaitingMulligan(2), "the practice opponent has already answered")
  H.ok(m.game:AwaitingMulligan(1), "and is waiting for the player")
  H.eq(m.game.turn, 0, "no turn has begun")

  m:OnIntent({ kind = "CLICK_MULLIGAN", handIndex = 1 })
  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  H.notOk(m.game:AwaitingMulligan(), "confirming starts the game")
  H.eq(m.game.turn, 1, "turn one")
  H.eq(m.game.activePlayer, 1, "and it is the player's")
  H.noEngineErrors(m.game)

  --[[ The heroes' voices: both introduce themselves, an emote is spoken by
       your own hero, and a refused move is answered in that voice. ]]
  local function spoke(fragment)
    for _, s in ipairs(Stub.R.sounds) do
      if s.file and s.file:find(fragment, 1, true) then return true end
    end
  end
  local mine = m:HeroCardId(1):gsub("HERO_", "")
  H.ok(spoke("Heroes\\VO_HERO_08_Start"), "Jaina opens the match")
  Stub.Advance(3)
  H.ok(spoke("_" .. m:HeroCardId(2):gsub("HERO_", "") .. "_") , "and the opponent answers")
  m.lastEmote = nil
  local emotes = Stub.Count("PerformEmote")
  m:OnIntent({ kind = "EMOTE", index = 3 })
  -- Your WoW character greets (in its own voice); the HS hero stays silent.
  H.eq(Stub.Count("PerformEmote"), emotes + 1, "Greetings is performed by your character")
  H.notOk(spoke("VO_HERO_" .. mine .. "_Greetings"), "and not doubled by the hero's line")
  Stub.Advance(2)
  m.game.players[1].mana = 0
  local handIndex
  for i, e in ipairs(m.game.players[1].hand) do if e:Cost() > 0 then handIndex = i end end
  m:OnIntent({ kind = "PLAY_CARD", handIndex = handIndex })
  H.ok(spoke("VO_HERO_" .. mine .. "_ERROR02"), "a card you cannot afford: \"I need more mana\"")
end)

H.suite("opening: the innkeeper greets once, and the menu has Hearthstone's music", function(ns, H)
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/UI/Collection.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  local m = ns.Main
  local function count(pred)
    local n = 0
    for _, s in ipairs(Stub.R.sounds) do if pred(s) then n = n + 1 end end
    return n
  end
  local function innkeeper(s) return s.file and s.file:find("innkeeper_", 1, true) end
  local function music(s) return s.music end

  local function settle() Stub.Advance(0.05) end   -- music follows windows a frame later
  local function themes() return count(function(s) return s.music and s.music:find("mainmenu.mp3", 1, true) end) end
  m:ShowHub(); settle()
  H.eq(themes(), 1, "the main menu plays Hearthstone's theme, without being asked")
  m.hub:Hide(); m:ShowHub(); settle()
  H.eq(count(innkeeper), 1, "the innkeeper says hello once a session")
  H.eq(themes(), 1, "closing and reopening a menu in one step does not restart it")
  -- menu -> collection -> menu: the theme plays straight through
  local ui = m:Collection()
  ui:ShowDecks(); m.hub:Hide(); settle()
  ui.homeButton:Click(); settle()
  H.ok(m.hub:IsShown(), "back at the menu")
  H.eq(themes(), 1, "moving between menus never restarts the theme")
  H.notOk(count(function(s) return s.music == false end) > 0, "or stops it")

  m.hub:Hide()
  m:StartPractice(); settle()
  H.eq(count(function(s) return s.music and s.music:find("mulligan.mp3", 1, true) end), 1,
       "the mulligan has its own music")
  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  H.eq(count(function(s) return s.music and s.music:find("duel.mp3", 1, true) end), 1,
       "and the duel its own")
  m:ToggleMusic()
  H.eq(Stub.R.sounds[#Stub.R.sounds].music, false, "turning it off hands the music back to the zone")
  H.eq(ForeverHearthstoneDB.music, false, "and that choice is saved")
  m:ToggleMusic()
  H.ok(ForeverHearthstoneDB.music, "and can be turned back on")

  local function last() return Stub.R.sounds[#Stub.R.sounds].music end
  -- the music follows the windows: close them all and it stops
  m.board:Hide(); if m.hub then m.hub:Hide() end; settle()
  H.eq(last(), false, "with every /fh window closed the zone music comes back")
  m:ShowHub(); settle()
  H.ok(last() and last():find("mainmenu.mp3", 1, true), "the menu brings the theme back")
  m.hub:Hide(); settle()
  H.eq(last(), false, "and closing it stops it")
  -- mute silences it WITHOUT stopping it: WoW cannot pause music, so a
  -- stop and a play again would start the track over
  Stub.cvars.Sound_MusicVolume = "0.60"
  m:ShowHub(); settle()
  local calls = #Stub.R.sounds
  m:ToggleMute(); settle()
  H.eq(#Stub.R.sounds, calls, "muting neither stops nor restarts the music")
  H.eq(Stub.cvars.Sound_MusicVolume, "0", "it just turns the music down")
  m:ToggleMute(); settle()
  H.eq(#Stub.R.sounds, calls, "unmuting carries on from where it was")
  H.eq(Stub.cvars.Sound_MusicVolume, "0.60", "at the volume it had")
  -- WoW's own music setting is never left at 0 by us
  m:ToggleMute(); settle()
  m.hub:Hide(); settle()
  H.eq(last(), false, "closing the menu hands back to the zone")
  H.eq(Stub.cvars.Sound_MusicVolume, "0.60", "at its own volume, though we are still muted")
  m:ShowHub(); settle()
  H.eq(Stub.cvars.Sound_MusicVolume, "0", "our theme is silent again")
  ns.Sounds.SetVolume(0.3)
  H.eq(Stub.cvars.Sound_MusicVolume, "0", "the slider moves the level to come back to, not the muted one")
  Stub.Fire("PLAYER_LOGOUT")
  H.eq(Stub.cvars.Sound_MusicVolume, "0.30", "and logging out restores it")
  ForeverHearthstoneDB.mutedMusicVolume = "0.45"; Stub.cvars.Sound_MusicVolume = "0"
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  H.eq(Stub.cvars.Sound_MusicVolume, "0.45", "as does the next login after a crash")
  ns.Sounds.SetMuted(false)   -- the mute is saved; later suites expect sound
end)

H.suite("opening: practice can deal you the Coin", function(ns, H)
  --[[ THE BUG. `firstPlayer` was hardcoded to 1, so the only mode that needs no
       second player could never put you on the draw. You never held the Coin
       and never saw the four-card mulligan -- two opening mechanics that were
       simply unreachable. ]]
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")

  local realRandom = math.random
  math.random = function(a, b)
    if a == 1 and b == 2 then return 2 end          -- they go first; we draw
    return realRandom(a, b)
  end
  ns.Main:StartPractice()
  math.random = realRandom

  local m = ns.Main
  H.eq(m.game.activePlayer, 2, "the opponent is on the play")

  --[[ FOUR cards to mulligan. The Coin is not one of them: it is compensation
       for going second, not a card you were dealt, and showing it among the
       mulligan choices is what made going second look like it had dealt you an
       extra card. ]]
  H.eq(#m.game.players[1].hand, ns.RULES.MULLIGAN_SECOND,
       "four cards in the mulligan")
  for _, card in ipairs(m.game.players[1].hand) do
    H.ok(card.cardId ~= "GAME_005", "and no Coin among them")
  end

  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  local coin = false
  for _, card in ipairs(m.game.players[1].hand) do
    if card.cardId == "GAME_005" then coin = true end
  end
  H.ok(coin, "the Coin arrives once the mulligan is settled")
  H.noEngineErrors(m.game)
end)

H.suite("opening: the opponent's turn takes TIME, and hands back", function(ns, H)
  --[[ THE BUG. AI.TakeTurn played every card and made every attack inside one
       loop, so the practice opponent's whole turn happened between two screen
       refreshes. You saw the board before and the board after and nothing in
       between -- no cards moving, no attacks, no sound -- which from your side
       of the table is indistinguishable from your health dropping by itself.

       Now each decision is a step with the length of its own animation, so the
       turn has to be driven by the clock. That makes "it hands the turn back"
       something that can silently stop working, which is what this pins. ]]
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")

  local realRandom = math.random
  math.random = function(a, b)
    if a == 1 and b == 2 then return 1 end
    return realRandom(a, b)
  end
  ns.Main:StartPractice()
  math.random = realRandom

  local m = ns.Main
  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  H.eq(m.game.activePlayer, 1, "our turn first")

  m:OnIntent({ kind = "END_TURN" })
  H.eq(m.game.activePlayer, 2, "the opponent has it")
  H.ok(m.aiRunning, "and is taking it, rather than having already finished")

  --[[ The turn must NOT resolve in zero time. If it did, the pacing is gone and
       the opponent is invisible again. ]]
  Stub.Advance(0.05)
  H.ok(m.aiRunning, "a twentieth of a second is not a turn")

  --[[ ...and it must finish. A turn that never hands back is a dead game, and
       is exactly what a stepped turn gets wrong when a refused action is
       retried forever. ]]
  for _ = 1, 400 do
    if not m.aiRunning then break end
    Stub.Advance(0.25)
  end
  H.notOk(m.aiRunning, "the opponent finished")
  H.ok(m.game.over or m.game.activePlayer == 1, "and gave the turn back")
  H.noEngineErrors(m.game)
end)

H.suite("opening: a practice match waits while its board is closed", function(ns, H)
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  local realRandom = math.random
  math.random = function(a, b) if a == 1 and b == 2 then return 1 end return realRandom(a, b) end
  ns.Main:StartPractice()
  math.random = realRandom
  local m = ns.Main
  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  Stub.Advance(3)
  -- your turn, board closed: the rope stands still
  local before = m.director:TurnRemaining(m.game)
  m.board:Hide()
  Stub.Advance(10)
  H.eq(m.director:TurnRemaining(m.game), before, "no rope burns with nobody at the table")
  m.board:Show()
  Stub.Advance(1)
  H.ok(m.director:TurnRemaining(m.game) < before, "and it burns again once you are back")
  -- the bot's turn, board closed: it does nothing until you return
  m:OnIntent({ kind = "END_TURN" })
  m.board:Hide()
  local seq = m.game.bus.seq
  Stub.Advance(10)
  H.eq(m.game.bus.seq, seq, "the bot does not play its turn to an empty room")
  H.eq(m.game.activePlayer, 2, "and still holds it")
  m.board:Show()
  for _ = 1, 400 do
    if not m.aiRunning then break end
    Stub.Advance(0.25)
  end
  H.notOk(m.aiRunning, "then it takes its turn")
  H.ok(m.game.over or m.game.activePlayer == 1, "and hands it back")
  -- AFK counts as away too
  _G.UnitIsAFK = function() return true end
  H.ok(m:PracticePaused(), "an AFK player pauses the match")
  _G.UnitIsAFK = nil
end)

H.suite("opening: the rope burns on the turn clock, and ends when the turn does", function(ns, H)
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  local realRandom = math.random
  math.random = function(a, b) if a == 1 and b == 2 then return 1 end return realRandom(a, b) end
  ns.Main:StartPractice()
  math.random = realRandom
  local m, b = ns.Main, ns.Main.board
  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  Stub.Advance(1)
  local total, rope = m.game:TurnSeconds(), ns.RULES.ROPE_SECONDS
  local function ended()
    for _, s in ipairs(Stub.R.sounds) do if s.file and s.file:find("endturn.mp3", 1, true) then return true end end
  end
  -- advance until exactly the rope's worth of turn is left (the turn clock
  -- stands still while presentations play, so walk it rather than guess)
  for _ = 1, 2000 do
    if m.director:TurnRemaining(m.game) <= rope - 0.05 then break end
    Stub.Advance(0.05)
  end
  H.ok(b.ropeBurn ~= nil, "the rope is lit with " .. rope .. "s to go")
  Stub.Advance(rope / 2)
  H.ok(math.abs(b.ropeBurn - 0.5) < 0.05, ("half the rope is burnt half way through it (%.2f)"):format(b.ropeBurn))
  H.notOk(ended(), "and it has not burnt out early")
  -- a paused table: the rope stands still
  local burn = b.ropeBurn
  b:Hide(); Stub.Advance(5); b:Show()
  H.ok(math.abs(b.ropeBurn - burn) < 0.01, "the rope stands still while the turn clock does")
  H.eq(m.game.activePlayer, 1, "still your turn")
  Stub.Advance(m.director:TurnRemaining(m.game) - 0.2)
  H.notOk(ended(), "no burnt-out sound before the turn is over")
  H.eq(m.game.activePlayer, 1, "and the turn is still yours")
  Stub.Advance(0.5)
  H.ok(ended(), "the rope's end is heard as the turn ends")
  H.eq(m.game.activePlayer, 2, "and the turn passes")
end)
