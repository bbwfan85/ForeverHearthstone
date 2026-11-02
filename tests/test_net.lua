--[[ tests/test_net.lua -- the wire format and the duel state machine.

  THE POINT OF THIS FILE: two sessions are wired to each other and play a whole
  match in a terminal. No WoW, no second person, no network. That is possible
  only because Protocol and Session import no WoW API, and it is the only way to
  have any confidence in a protocol before there is someone to sit down with.

  What is deliberately NOT tested here: that C_ChatInfo.SendAddonMessage
  actually delivers anything. That is Transport's job and the stub's, and no
  amount of headless testing can confirm it -- see tests/test_ui.lua for the
  same split.
]]
local H = require("tests.harness")

-- A pair of sessions with a wire between them. `drop` lets a test lose
-- messages, which is the failure the sequence numbers exist for.
local function pair(ns, opts)
  opts = opts or {}
  local wire = { a = {}, b = {}, lost = {}, log = {} }
  local A, B
  local function link(name, to)
    return function(raw)
      wire.log[#wire.log + 1] = { from = name, raw = raw }
      if opts.drop and opts.drop(name, raw) then
        wire.lost[#wire.lost + 1] = raw
        return
      end
      to[#to + 1] = raw
    end
  end

  local events = { a = {}, b = {} }
  local function rec(t) return function(e, d) t[#t + 1] = { event = e, data = d } end end

  A = ns.Session.New({
    send = link("a", wire.b), onEvent = rec(events.a),
    name = "Ayla", class = opts.classA or "MAGE", level=opts.levelA, guid=opts.guidA,
    deck = ns.Controller.BasicDeck(opts.classA or "MAGE"),
    nonce = "nonce-a",
  })
  B = ns.Session.New({
    send = link("b", wire.a), onEvent = rec(events.b),
    name = "Brann", class = opts.classB or "PRIEST", level=opts.levelB, guid=opts.guidB,
    deck = ns.Controller.BasicDeck(opts.classB or "PRIEST"),
    nonce = "nonce-b",
  })

  -- Deliver everything queued, in order, until both queues are empty.
  local function pump(limit)
    for _ = 1, (limit or 200) do
      if #wire.a == 0 and #wire.b == 0 then return end
      if #wire.a > 0 then A:Receive(table.remove(wire.a, 1)) end
      if #wire.b > 0 then B:Receive(table.remove(wire.b, 1)) end
    end
  end

  return A, B, pump, events, wire
end

--[[ Connect two sessions AND get through the mulligan, which is now the first
     thing that happens in a duel: the engine will not begin play until both
     players have submitted, so a test that skips it is a test of a game that
     never started. ]]
local function connect(ns, opts)
  local A, B, pump, events, wire = pair(ns, opts)
  A:Challenge("Brann")
  pump()
  B:Accept()
  pump()
  if not (opts and opts.stopAtMulligan) then
    A:LocalAction({ kind = "MULLIGAN", indices = {} })
    B:LocalAction({ kind = "MULLIGAN", indices = {} })
    pump()
  end
  return A, B, pump, events, wire
end

--[[ Build a raw wire line whose BODY is already a joined field list. Protocol
     .Encode deliberately refuses a field containing a separator, so a test that
     wants to forge a multi-field body has to assemble it the way the Outbox
     does. Injected at the receiver's next expected sequence number, or it would
     be held as a message from the future and never delivered. ]]
local function inject(session, kind, body)
  if kind == H.ns.Protocol.KIND.BYE then body = body .. ";" .. (session.challengeId or "") end
  session:Receive(("%d;%s;%s"):format(session.inbox.expected, kind, body))
end

local function eventsOf(list, name)
  local out = {}
  for _, e in ipairs(list) do if e.event == name then out[#out + 1] = e.data end end
  return out
end

--============================================================ wire format

H.suite("net: a message round-trips through encode and decode", function(ns, H)
  local P = ns.Protocol
  local raw = P.Encode(7, "AC", "P", 3, 0, 1)
  local m = P.Decode(raw)
  H.ok(m, "decoded")
  H.eq(m.seq, 7, "sequence survives")
  H.eq(m.kind, "AC", "kind survives")
  H.eq(m[1], "P", "first field")
  H.eq(P.Num(m, 2), 3, "numbers come back as numbers")
end)

H.suite("net: an absent field keeps its POSITION", function(ns, H)
  --[[ The thing that makes a format extensible. If nil collapsed the field
       list, every optional argument would shift the meaning of everything after
       it, and a card played with no target would decode as one played with a
       target of whatever came next. ]]
  local P = ns.Protocol
  local m = P.Decode(P.Encode(1, "AC", "P", 3, nil, nil, 42))
  H.eq(m[1], "P", "verb")
  H.eq(P.Num(m, 2), 3, "hand index")
  H.eq(m[3], nil, "the empty field is nil")
  H.eq(P.Num(m, 5), 42, "and the field AFTER the gaps is still in slot 5")
end)

H.suite("net: garbage decodes to nil rather than erroring", function(ns, H)
  --[[ Other addons share the channel and players run old versions, so a message
       we cannot read is an expected event, not an exception. ]]
  local P = ns.Protocol
  for _, bad in ipairs({ "", "nonsense", ";;", "x;AC;1", "-4;AC" }) do
    local m, why = P.Decode(bad)
    H.ok(m == nil, ("%q is rejected"):format(bad))
    H.ok(why ~= nil, "with a reason")
  end
  H.eq(P.Decode(nil), nil, "even nil")
end)

H.suite("net: a field containing the separator is refused at ENCODE time", function(ns, H)
  -- Caught where the bug is, rather than producing a message that parses as
  -- something else on the far side.
  local P = ns.Protocol
  local ok = pcall(P.Encode, 1, "HI", "Bad;Name")
  H.notOk(ok, "encoding raises rather than corrupting the message")
end)

H.suite("net: every message fits in a WoW addon message", function(ns, H)
  local P = ns.Protocol
  local deck = ns.Controller.BasicDeck("MAGE")
  local sent = {}
  local out = P.Outbox.New(function(raw) sent[#sent + 1] = raw end)
  out:Send(P.KIND.DECK, table.concat(deck, ";"))
  H.ok(#sent > 1, "a 30-card deck does not fit in one message, so it was split")
  for _, raw in ipairs(sent) do
    H.ok(#raw <= P.MAX_MESSAGE, ("chunk is %d bytes, within the cap"):format(#raw))
  end
end)

H.suite("net: a split message reassembles into the SAME message", function(ns, H)
  local P = ns.Protocol
  local deck = ns.Controller.BasicDeck("DRUID")
  local inbox = P.Inbox.New()
  local ready = {}
  local out = P.Outbox.New(function(raw)
    for _, m in ipairs((inbox:Receive(raw))) do ready[#ready + 1] = m end
  end)
  out:Send(P.KIND.DECK, table.concat(deck, ";"))

  H.eq(#ready, 1, "the fragments deliver exactly one message")
  local m = ready[1]
  H.eq(m.kind, P.KIND.DECK, "and it still knows what KIND it is")
  H.eq(m.n, #deck, "with every card id present")
  for i = 1, #deck do H.eq(m[i], deck[i], "card " .. i .. " survived the split") end
end)

H.suite("net: a fragment containing separators survives", function(ns, H)
  --[[ The bug this exists to prevent: reassembling from the DECODED fields
       instead of the raw line truncates every fragment at its first separator,
       which is most of them, and the failure only appears for long messages. ]]
  local P = ns.Protocol
  local body = {}
  for i = 1, 60 do body[i] = "FIELD_" .. i end
  local joined = table.concat(body, ";")
  local inbox, ready = P.Inbox.New(), {}
  local out = P.Outbox.New(function(raw)
    for _, m in ipairs((inbox:Receive(raw))) do ready[#ready + 1] = m end
  end)
  out:Send("DK", joined)
  H.eq(#ready, 1, "one message out")
  H.eq(ready[1].n, 60, "all sixty fields, not just the ones before a seam")
  H.eq(ready[1][60], "FIELD_60", "including the last")
end)

--============================================================ ordering

H.suite("net: a message from the future is HELD, not applied", function(ns, H)
  local P = ns.Protocol
  local inbox = P.Inbox.New()
  local ready = inbox:Receive(P.Encode(3, "AC", "E"))
  H.eq(#ready, 0, "sequence 3 waits for 1 and 2")
  local ready2, nak = inbox:Receive(P.Encode(2, "AC", "E"))
  H.eq(#ready2, 0, "and still waits for 1")
  H.eq(#nak, 1, "asks for exactly the hole")
  H.eq(nak[1], 1, "which is message 1")
  local ready3 = inbox:Receive(P.Encode(1, "AC", "E"))
  H.eq(#ready3, 3, "when 1 lands, all three deliver at once")
  H.eq(ready3[1].seq, 1, "in order")
  H.eq(ready3[3].seq, 3, "to the end")
end)

H.suite("net: a duplicate is delivered exactly once", function(ns, H)
  local P = ns.Protocol
  local inbox = P.Inbox.New()
  H.eq(#inbox:Receive(P.Encode(1, "AC", "E")), 1, "first copy delivers")
  H.eq(#inbox:Receive(P.Encode(1, "AC", "E")), 0, "the resend does not")
end)

H.suite("net: a NAK gets the missing message back", function(ns, H)
  local P = ns.Protocol
  local sent = {}
  local out = P.Outbox.New(function(raw) sent[#sent + 1] = raw end)
  out:Send("AC", "E")
  out:Send("AC", "E")
  local first = sent[1]
  local ok = out:Resend({ 1 })
  H.ok(ok, "the sender still had it")
  H.eq(sent[#sent], first, "and sent the same bytes again")

  local ok2, lost = out:Resend({ 999 })
  H.notOk(ok2, "something outside the history cannot be resent")
  H.eq(lost[1], 999, "and it says which")
end)

--============================================================ versions

H.suite("net: an incompatible protocol is refused with ADVICE", function(ns, H)
  local P = ns.Protocol
  local ok = P.CheckVersion(P.VERSION, "0.1.0")
  H.ok(ok, "the same protocol is fine")

  local ok2, why, advice = P.CheckVersion(P.VERSION + 1, "9.9.9")
  H.notOk(ok2, "a newer peer is refused")
  H.eq(why, "older", "we are the old one")
  H.ok(advice:find("out of date"), "and the player is told what to do: " .. tostring(advice))

  local ok3, why3, advice3 = P.CheckVersion(P.VERSION - 1, "0.0.1")
  H.notOk(ok3, "an older peer is refused too")
  H.eq(why3, "newer", "they are the old one")
  H.ok(advice3:find("they need to update"), "and it says so: " .. tostring(advice3))

  local ok4, why4 = P.CheckVersion("not a number")
  H.notOk(ok4, "and something that is not this addon at all")
  H.eq(why4, "unreadable", "is named as such")
end)

H.suite("net: version mismatch aborts BEFORE anything is committed", function(ns, H)
  local A, B, pump, events = pair(ns)
  -- forge a HELLO from a future protocol
  B:Receive(ns.Protocol.Encode(1, ns.Protocol.KIND.HELLO,
                               ns.Protocol.VERSION + 5, "9.9.9", "MAGE", "Ayla"))
  local aborted = eventsOf(events.b, "ABORTED")
  H.eq(#aborted, 1, "the session aborted")
  H.eq(aborted[1].reason, "version", "naming the version")
  H.eq(B.game, nil, "and no game was ever built")
  H.eq(B.state, B.STATE.ABORTED, "state is terminal")
end)

--============================================================ the handshake

H.suite("net: a challenge is offered, not auto-accepted", function(ns, H)
  local A, B, pump, events = pair(ns)
  A:Challenge("Brann")
  pump()
  H.eq(B.state, B.STATE.INVITED, "the challenged side waits for its player")
  H.eq(#eventsOf(events.b, "CHALLENGED"), 1, "and raises the prompt")
  H.eq(B.game, nil, "nothing has started")
  --[[ An addon that accepted duels on the player's behalf would be a griefing
       tool the moment anyone noticed, so this is a rule and not a preference. ]]
end)

H.suite("net: declining ends it cleanly on both sides", function(ns, H)
  local A, B, pump, events = pair(ns)
  A:Challenge("Brann")
  pump()
  B:Decline("busy")
  pump()
  H.eq(B.state, B.STATE.IDLE, "the decliner is free again")
  H.eq(A.state, A.STATE.IDLE, "and so is the challenger")
  H.eq(#eventsOf(events.a, "DECLINED"), 1, "who is told")
end)

H.suite("net: accepting builds the SAME game on both clients", function(ns, H)
  local A, B, pump, events = connect(ns)
  H.notOk(A.game:AwaitingMulligan(), "the mulligan is done")
  H.eq(A.state, A.STATE.PLAYING, "challenger is playing")
  H.eq(B.state, B.STATE.PLAYING, "and so is the challenged")
  H.ok(A.game and B.game, "both built a game")
  H.eq(A.seed, B.seed, "from the same seed")
  H.eq(A.game:StateHash(), B.game:StateHash(), "reaching an identical state")
  --[[ The challenger is player 1 on BOTH clients. Nothing negotiates this; if
       it were negotiated it would be one more thing that can disagree. ]]
  H.eq(A.myIndex, 1, "challenger is player 1")
  H.eq(B.myIndex, 2, "challenged is player 2")
  H.eq(A.game.activePlayer, B.game.activePlayer, "and they agree whose turn it is")
end)

H.suite("net: neither player can choose the shuffle", function(ns, H)
  --[[ Commit-reveal. The seed depends on both nonces, and each side is holding
       the other's commitment before it reveals -- so a client that picks its
       nonce after seeing the other's is caught. ]]
  local A, B, pump, events = pair(ns)
  A:Challenge("Brann"); pump(); B:Accept(); pump()
  local honest = A.seed

  -- now replay with B cheating: it commits to one nonce and reveals another
  local A2, B2, pump2, events2 = pair(ns)
  A2:Challenge("Brann"); pump2()
  B2:Accept()                    -- B's commitment is on the wire...
  B2.nonce = "a-different-nonce" -- ...and then B changes its mind
  pump2()
  local aborted = eventsOf(events2.a, "ABORTED")
  H.ok(#aborted >= 1, "the honest client noticed")
  H.eq(aborted[1].reason, "cheat", "and named it for what it is")
  H.ok(honest ~= nil, "meanwhile the honest pair agreed a seed")

  -- and the deck is covered too: stacking it after seeing the seed is caught
  local A3, B3, pump3, events3 = pair(ns)
  A3:Challenge("Brann"); pump3()
  B3:Accept()
  local stacked = {}
  for i = #B3.me.deck, 1, -1 do stacked[#stacked + 1] = B3.me.deck[i] end
  B3.me.deck = stacked
  pump3()
  local aborted3 = eventsOf(events3.a, "ABORTED")
  H.eq(aborted3[1] and aborted3[1].reason, "cheat", "a deck swapped after committing is refused")
end)

H.suite("net: a deck that is not 30 legal cards is refused", function(ns, H)
  local A, B, pump = pair(ns)
  A:Challenge("Brann"); pump(); B:Accept(); pump()
  local events = {}
  local C = ns.Session.New({ send = function() end,
                             onEvent = function(e, d) events[#events+1] = {e,d} end,
                             deck = ns.Controller.BasicDeck("MAGE") })
  C.state = C.STATE.SYNC
  inject(C, ns.Protocol.KIND.DECK, "CS2_231;CS2_231")
  H.eq(C.state, C.STATE.ABORTED, "a short deck aborts")

  local D = ns.Session.New({ send = function() end, onEvent = function() end,
                             deck = ns.Controller.BasicDeck("MAGE") })
  D.state = D.STATE.SYNC
  local ids = {}
  for i = 1, 30 do ids[i] = (i == 7) and "NOT_A_CARD" or "CS2_231" end
  inject(D, ns.Protocol.KIND.DECK, table.concat(ids, ";"))
  H.eq(D.state, D.STATE.ABORTED, "and so does a card this addon does not know")
end)

--============================================================ playing

H.suite("net: an action taken here happens there", function(ns, H)
  local A, B, pump = connect(ns)
  local active = A.game.activePlayer
  local mover  = (active == A.myIndex) and A or B
  local other  = (mover == A) and B or A

  H.ok(mover:LocalAction({ kind = "END_TURN" }), "the active player ends the turn")
  pump()
  H.eq(A.game.turn, B.game.turn, "both clients advanced the turn")
  H.eq(A.game.activePlayer, B.game.activePlayer, "and agree whose it is now")
  H.eq(A.game:StateHash(), B.game:StateHash(), "with identical state")
  H.ok(other.game ~= nil, "the far side applied it rather than being told a board")
end)

H.suite("net: a whole match plays out and both sides agree throughout", function(ns, H)
  --[[ THE TEST THIS FILE EXISTS FOR. Two sessions, the practice AI driving both
       of them through the ordinary action path, playing until someone wins --
       with the state fingerprint compared at every single turn. ]]
  local A, B, pump = connect(ns, { classA = "WARRIOR", classB = "SHAMAN" })
  local turns = 0
  while A.state == A.STATE.PLAYING and turns < 120 do
    local mover = (A.game.activePlayer == A.myIndex) and A or B
    --[[ The AI decides against the mover's OWN game object -- which is the
         honest simulation of two players, each looking at their own client. ]]
    ns.AI.TakeTurn(mover.game, mover.game.activePlayer, function(action)
      return mover:LocalAction(action)
    end)
    pump()
    if A.state ~= A.STATE.PLAYING then break end
    mover:LocalAction({ kind = "END_TURN" })
    pump()
    turns = turns + 1
    H.eq(A.game:StateHash(), B.game:StateHash(), "turn " .. turns .. ": states agree")
  end
  H.ok(turns > 3, "the match ran for a meaningful number of turns (" .. turns .. ")")
  H.noEngineErrors(A.game, "challenger's engine")
  H.noEngineErrors(B.game, "challenged's engine")
  H.eq(A.game.winner, B.game.winner, "and both agree who won")
end)

H.suite("net: a dropped message is recovered by NAK, not by guessing", function(ns, H)
  local dropped = false
  local A, B, pump = connect(ns, {
    drop = function(from, raw)
      -- lose exactly one ACTION from A, once the match is under way
      if from == "a" and not dropped and raw:find(";AC;", 1, true) then
        dropped = true
        return true
      end
      return false
    end,
  })
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  if mover ~= A then A, B = B, A end   -- make sure the dropper is the one acting
  local m = (A.game.activePlayer == A.myIndex) and A or B

  m:LocalAction({ kind = "END_TURN" })
  pump()
  -- The NAK from B asks for the hole; A resends; B catches up.
  pump()
  if dropped then
    H.eq(A.game:StateHash(), B.game:StateHash(), "the two clients converged again")
    H.eq(A.state, A.STATE.PLAYING, "and the match continued")
  else
    H.ok(true, "no action crossed in this configuration; nothing to recover")
  end
end)

H.suite("net: an ILLEGAL remote action asks the challenger for the truth", function(ns, H)
  --[[ If their client thought that was legal and ours does not, the two states
       may have diverged. The challenger is authoritative: the other client
       rebuilds from the challenger's action log, and only if that still
       disagrees does the duel end. ]]
  local A, B, pump, events = connect(ns)
  local body = ns.Protocol.EncodeAction({ kind = "PLAY_CARD", handIndex = 99 })
  inject(B, ns.Protocol.KIND.ACTION, body)   -- B is not the challenger
  A.out.seq = A.out.seq + 1   -- the forgery used a number from A's stream
  pump()
  H.eq(#eventsOf(events.b, "RESYNCING"), 1, "B asked for the challenger's log")
  H.eq(#eventsOf(events.b, "RESYNCED"), 1, "rebuilt from it")
  H.eq(#eventsOf(events.b, "ABORTED"), 0, "and the duel goes on")
  H.eq(A.game:StateHash(), B.game:StateHash(), "with both clients agreeing")
end)

H.suite("net: a diverged client is resynced from the challenger's log", function(ns, H)
  local A, B, pump, events = connect(ns)
  -- Reach into one client and change the game behind the protocol's back --
  -- exactly what a real desync looks like from the outside.
  B.game.players[1].hero.damage = B.game.players[1].hero.damage + 3
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  mover:LocalAction({ kind = "END_TURN" })
  pump()
  H.eq(#eventsOf(events.b, "RESYNCED"), 1, "the non-challenger rebuilt its game")
  H.eq(A.game:StateHash(), B.game:StateHash(), "and agrees again")
  H.eq(A.state, A.STATE.PLAYING, "the match continued")
  H.eq(B.game.players[1].hero.damage, A.game.players[1].hero.damage, "with the challenger's truth")
end)

H.suite("net: a divergence the log cannot explain still ends the duel, named", function(ns, H)
  local A, B, pump, events = connect(ns)
  -- the CHALLENGER is the corrupted one: its own log replays to a different
  -- state than it holds, so nothing can be agreed
  A.game.players[2].hero.damage = A.game.players[2].hero.damage + 4
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  mover:LocalAction({ kind = "END_TURN" })
  pump()
  local d = eventsOf(events.b, "ABORTED")[1]
  H.ok(d, "the duel ended")
  H.eq(d and d.reason, "desync", "named as a desync")
  H.ok(d and d.detail:find("action"), "naming where it happened: " .. tostring(d and d.detail))
end)

H.suite("net: the opponent's deck is checked here too", function(ns, H)
  local V = ns.Session.ValidateRemoteDeck
  local ok = V(ns.Controller.BasicDeck("MAGE"), "MAGE")
  H.ok(ok, "a legal deck passes")
  local bad = ns.Controller.BasicDeck("MAGE")
  bad[1] = "CS2_106"   -- Fiery War Axe, a warrior card
  H.notOk(V(bad, "MAGE"), "another class's card is refused")
  local three = ns.Controller.BasicDeck("MAGE")
  three[1], three[2], three[3] = "CS2_029", "CS2_029", "CS2_029"
  H.notOk(V(three, "MAGE"), "three copies are refused")
end)

H.suite("net: conceding ends the match for both players", function(ns, H)
  local A, B, pump, events = connect(ns)
  local loser = (A.game.activePlayer == A.myIndex) and A or B
  local winner = (loser == A) and B or A
  loser:Concede()
  pump()
  H.ok(A.game.over and B.game.over, "the game is over on both clients")
  H.eq(A.game.winner, B.game.winner, "and they agree who won")
  H.eq(A.game.winner, winner.myIndex, "which is the player who did not concede")
  H.eq(loser.state, loser.STATE.OVER, "the session finished normally")
end)

H.suite("net: leaving mid-match is a forfeit, not a cancelled match", function(ns, H)
  -- Otherwise quitting is the correct play whenever you are losing.
  local A, B, pump, events = connect(ns)
  inject(B, ns.Protocol.KIND.BYE, "logout")
  local ff = eventsOf(events.b, "FORFEIT")
  H.eq(#ff, 1, "the remaining player is told it was a forfeit")
  H.eq(B.state, B.STATE.OVER, "and the session is over, not idle")
end)

H.suite("net: an emote is NOT part of the action stream", function(ns, H)
  --[[ Emotes change no game state. Putting them in lockstep would make a
       dropped emote a desync, which is an absurd way to lose a match. ]]
  local A, B, pump, events = connect(ns)
  local before = A.game:StateHash()
  A:Emote(3)
  pump()
  H.eq(A.game:StateHash(), before, "state did not move")
  local got = eventsOf(events.b, "EMOTE")
  H.eq(#got, 1, "but it arrived")
  H.eq(got[1].index, 3, "with the right emote")
end)

H.suite("net: a paused duel refuses actions until it resumes", function(ns, H)
  local A, B, pump, events = connect(ns)
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  mover:Pause("in combat")
  pump()
  H.eq(#eventsOf((mover == A) and events.b or events.a, "PAUSED"), 1,
       "the other player is told, rather than watching a frozen board")
  local ok, why = mover:LocalAction({ kind = "END_TURN" })
  H.notOk(ok, "nothing may be played while paused")
  H.ok(why and why:find("paused"), "and it says why")
  mover:Resume()
  pump()
  H.ok(mover:LocalAction({ kind = "END_TURN" }), "resuming restores play")
end)

H.suite("net: an unknown message kind is ignored, not fatal", function(ns, H)
  --[[ This is what lets a LATER version add a message kind without breaking
       this one. Without it, every addition is a forced upgrade for both
       players on the same day. ]]
  local A, B, pump = connect(ns)
  local before = A.game:StateHash()
  inject(A, "ZZ", "whatever;they;want")
  H.eq(A.state, A.STATE.PLAYING, "still playing")
  H.eq(A.game:StateHash(), before, "and nothing moved")
end)

--============================================================ the action layer

H.suite("actions: one path applies a play for anyone", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1)
  local i = H.Hand(g, 1, "CS2_231")     -- Wisp
  local ok = ns.Actions.Run(g, 1, { kind = "PLAY_CARD", handIndex = i })
  H.ok(ok, "played")
  H.board(g, 1, { "CS2_231 1/1" }, "the Wisp is on the board")
end)

H.suite("actions: acting out of turn is refused wherever it comes from", function(ns, H)
  local g = H.NewGame()
  local i = H.Hand(g, 2, "CS2_231")
  local ok, why = ns.Actions.Run(g, 2, { kind = "PLAY_CARD", handIndex = i })
  H.notOk(ok, "player 2 cannot act on player 1's turn")
  H.eq(why, "not your turn", "and says why")
end)

H.suite("actions: you cannot swing someone else's minion", function(ns, H)
  --[[ IsLegalAttack answers "can this hit that", not "is this yours to swing".
       Over the wire those are different questions, and only one of them is
       about the rules of combat. ]]
  local g = H.NewGame()
  local mine  = H.Put(g, 1, "CS2_231")
  local theirs = H.Put(g, 2, "CS2_231")
  local ok, why = ns.Actions.Run(g, 1,
    { kind = "ATTACK", attackerId = theirs.instanceId, targetId = mine.instanceId })
  H.notOk(ok, "refused")
  H.eq(why, "not your minion", "by ownership, not by legality")
end)

H.suite("actions: a target that does not exist is refused, never guessed", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1)
  local i = H.Hand(g, 1, "CS2_029")     -- Fireball, needs a target
  local ok, why = ns.Actions.Run(g, 1, { kind = "PLAY_CARD", handIndex = i, targetId = 99999 })
  H.notOk(ok, "refused")
  H.eq(why, "unknown target", "rather than falling back to some other character")
end)

H.suite("actions: nothing but the answer happens while a choice is pending", function(ns, H)
  local g = H.NewGame({ deck1 = { "DS1_184" } })    -- Tracking
  H.Mana(g, 1)
  local i = H.Hand(g, 1, "DS1_184")
  ns.Actions.Run(g, 1, { kind = "PLAY_CARD", handIndex = i })
  H.ok(g:AwaitingChoice(), "Tracking is waiting for an answer")
  local ok, why = ns.Actions.Run(g, 1, { kind = "END_TURN" })
  H.notOk(ok, "the turn cannot be ended around it")
  H.eq(why, "a choice is pending", "and says so")
  H.ok(ns.Actions.Run(g, 1, { kind = "CHOICE", index = 1 }), "answering works")
  H.ok(ns.Actions.Run(g, 1, { kind = "END_TURN" }), "and then play resumes")
end)

H.suite("actions: conceding hands the win over without killing the hero", function(ns, H)
  local g = H.NewGame()
  local before = g.players[1].hero:Health()
  H.ok(ns.Actions.Run(g, 1, { kind = "CONCEDE" }), "conceded")
  H.ok(g.over, "the game is over")
  H.eq(g.winner, 2, "the other player won")
  H.eq(g.players[1].hero:Health(), before,
       "the hero did not take damage -- nothing may trigger off a concede")
end)

H.suite("actions: an entity lookup only finds what an action may name", function(ns, H)
  --[[ A lookup that could return a card in hand would turn a corrupt id into a
       silently wrong play instead of a refusal. ]]
  local g = H.NewGame()
  local m = H.Put(g, 1, "CS2_231")
  H.eq(g:EntityById(m.instanceId), m, "a minion on the board is found")
  H.eq(g:EntityById(g.players[2].hero.instanceId), g.players[2].hero, "so is a hero")
  local _, inHand = H.Hand(g, 1, "CS2_231")
  H.eq(g:EntityById(inHand.instanceId), nil, "a card in hand is NOT a target")
  H.eq(g:EntityById(nil), nil, "and nil finds nothing")
end)

H.suite("net: leaving during mulligan or pause finishes both games",function(ns,H)
  for _,opening in ipairs({true,false}) do
    local A,B,pump=connect(ns,{stopAtMulligan=opening})
    A:Pause("away"); pump(); A:Leave("closed"); pump()
    H.eq(A.state,A.STATE.OVER); H.eq(B.state,B.STATE.OVER)
    H.ok(A.game.over and B.game.over); H.eq(A.game.winner,B.game.winner)
    H.eq(B.game.winner,B.myIndex); H.eq(A.game:StateHash(),B.game:StateHash())
  end
end)
H.suite("net: standalone goodbye finishes the game and duplicate goodbye is harmless",function(ns,H)
  local A,B,pump,events=connect(ns,{stopAtMulligan=true})
  inject(B,ns.Protocol.KIND.BYE,"logout")
  H.ok(B.game.over); H.eq(B.game.winner,B.myIndex)
  inject(B,ns.Protocol.KIND.BYE,"logout")
  H.eq(B.state,B.STATE.OVER); H.eq(#eventsOf(events.b,"FORFEIT"),1)
end)
H.suite("net: profiles exchange actual levels and identity without changing game state",function(ns,H)
  local A,B,pump=connect(ns,{levelA=23,levelB=58,guidA="Player-A",guidB="Player-B"})
  H.eq(A.peer.level,58); H.eq(B.peer.level,23); H.eq(A.peer.guid,"Player-B")
  local hash=A.game:StateHash()
  B:Send(ns.Protocol.KIND.PROFILE,59,"Player-B"); pump()
  H.eq(A.peer.level,59); H.eq(A.game:StateHash(),hash)
end)
H.suite("net: keepalive preserves idle duels; silence pauses, then settles fairly",function(ns,H)
  local A,B,pump,events,wire=connect(ns)
  for i=1,24 do A:Tick(5); B:Tick(5); pump() end
  H.eq(A.state,A.STATE.PLAYING); H.eq(B.state,B.STATE.PLAYING)
  -- B goes silent
  A:Tick(ns.Session.PROBLEM_AFTER)
  H.eq(#eventsOf(events.a,"CONNECTION_PROBLEM"),1,"a connection problem is shown")
  local offered=false
  for _,raw in ipairs(wire.b) do if raw:find(";RJ;",1,true) then offered=true end end
  H.ok(offered,"and the silent player is offered a rejoin")
  for k in pairs(wire.b) do wire.b[k] = nil end
  if A.game.activePlayer==B.myIndex then
    -- their turn: their silence is costing the game, so it is ours after the timeout
    A:Tick(ns.Session.CONNECTION_TIMEOUT)
    H.eq(A.state,A.STATE.OVER,"the waiting player wins on the silent player's turn")
    H.eq(A.game.winner,A.myIndex)
  else
    -- our own turn: we may play on; with no word at all it ends with no winner
    A:Tick(ns.Session.CONNECTION_TIMEOUT)
    H.eq(A.state,A.STATE.PLAYING,"no win is claimed on your own turn")
    A:Tick(ns.Session.ABANDON_AFTER)
    H.eq(A.state,A.STATE.ABORTED); H.eq(A.abortReason,"disconnected")
    H.eq(A.game.winner,nil,"and nobody is handed a win")
  end
end)

H.suite("net: a split network can never give both players the win",function(ns,H)
  local A,B,pump,events=connect(ns)
  -- nothing crosses in either direction any more
  for _=1,20 do A:Tick(10); B:Tick(10) end
  local winsA = A.game.over and A.game.winner==A.myIndex
  local winsB = B.game.over and B.game.winner==B.myIndex
  H.ok(not (winsA and winsB),"at most one side claims")
end)

H.suite("net: a player who leaves the table forfeits after the grace period",function(ns,H)
  local A,B,pump,events=connect(ns)
  A:Pause("away"); pump()
  H.ok(B.paused and B.paused.peer=="away","the other side sees the pause")
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  H.notOk(mover:LocalAction({kind="END_TURN"}),"nobody can act while paused")
  A:Tick(ns.Session.GRACE.away - 1); B:Tick(ns.Session.GRACE.away - 1); pump()
  H.eq(A.state,A.STATE.PLAYING,"inside the grace period nothing happens")
  A:Resume(); pump()
  H.eq(B.paused,nil,"coming back resumes")
  A:Pause("dead"); pump()
  A:Tick(ns.Session.GRACE.dead + 1); pump()
  H.ok(A.game.over and B.game.over,"not back in time: the match is over")
  H.eq(B.game.winner,B.myIndex,"and the player who stayed wins")
  H.eq(#eventsOf(events.a,"TIMED_OUT"),1)
end)

H.suite("net: a stalling opponent can be beaten by claiming the win",function(ns,H)
  local A,B,pump,events=connect(ns)
  local waiter = (A.game.activePlayer == A.myIndex) and B or A
  local ev = waiter==A and events.a or events.b
  H.notOk(waiter:ClaimVictory(),"not while they still have time")
  for _=1,26 do waiter:Tick(5); (waiter==A and B or A):Tick(5); pump() end
  H.eq(#eventsOf(ev,"STALLING"),1,"a turn far past the rope is flagged")
  H.ok(waiter:ClaimVictory(),"and the win can be claimed")
  pump()
  H.ok(A.game.over and B.game.over,"both clients end the game")
  H.eq(A.game.winner, B.game.winner)
end)

H.suite("net: a player who reloads mid-duel rejoins by replay",function(ns,H)
  local A,B,pump,events,wire=connect(ns)
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  mover:LocalAction({kind="END_TURN"}); pump()
  local hash = A.game:StateHash()
  -- B's client reloads: its session is gone. A notices the silence and offers.
  A:Tick(ns.Session.PROBLEM_AFTER)
  for k in pairs(wire.b) do wire.b[k] = nil end
  local evB2 = {}
  local B2
  B2 = ns.Session.New({ send = function(raw) wire.a[#wire.a+1]=raw end,
    onEvent = function(e,d) evB2[#evB2+1]={event=e,data=d} end,
    name = "Brann", class = "PRIEST", deck = ns.Controller.BasicDeck("PRIEST"), nonce = "fresh" })
  B2:RequestRejoin("Ayla")
  for _=1,50 do
    if #wire.a==0 and #wire.b==0 then break end
    if #wire.a>0 then A:Receive(table.remove(wire.a,1)) end
    if #wire.b>0 then B2:Receive(table.remove(wire.b,1)) end
  end
  H.eq(B2.state, B2.STATE.PLAYING, "the returning player is back in the duel")
  H.eq(B2.game:StateHash(), hash, "in exactly the same game")
  H.eq(B2.myIndex, B.myIndex, "in the same seat")
  H.eq(B2.challengeId, A.challengeId, "rejoin preserves the invitation identity for later cancellation")
  H.ok(eventsOf(evB2,"START")[1].resumed, "announced as a resumed match")
  H.eq(#eventsOf(events.a,"CONNECTION_RESTORED"),1)
  -- and play continues on the new stream
  local next = (A.game.activePlayer == A.myIndex) and A or B2
  H.ok(next:LocalAction({kind="END_TURN"}),"the next action goes through")
  for _=1,50 do
    if #wire.a==0 and #wire.b==0 then break end
    if #wire.a>0 then A:Receive(table.remove(wire.a,1)) end
    if #wire.b>0 then B2:Receive(table.remove(wire.b,1)) end
  end
  H.eq(A.game:StateHash(), B2.game:StateHash(), "and both clients still agree")
end)

H.suite("net: heartbeat recovers a dropped final action",function(ns,H)
  local dropped=false
  local A,B,pump=connect(ns,{drop=function(name,raw)
    if not dropped and raw:find(";AC;E",1,true) then dropped=true; return true end
  end})
  local active=A.game.activePlayer==A.myIndex and A or B
  H.ok(active:LocalAction({kind="END_TURN"})); pump()
  H.ok(dropped)
  A:Tick(5); B:Tick(5); pump()
  H.eq(A.game:StateHash(),B.game:StateHash()); H.eq(A.state,A.STATE.PLAYING)
end)

H.suite("net: the opponent's hover is volatile -- delivered, rate-limited, never in lockstep", function(ns, H)
  local A, B, pump, events = connect(ns)
  local seqBefore = A.out.seq
  H.ok(A:SendHover(2, "b1", "E"), "a hover goes out")
  pump()
  local got = eventsOf(events.b, "HOVER")
  H.eq(#got, 1, "and arrives")
  H.eq(got[1].handIndex, 2); H.eq(got[1].sourceId, "b1"); H.eq(got[1].targetId, "E")
  H.eq(A.out.seq, seqBefore, "without consuming a sequence number")
  H.notOk(A:SendHover(2, "b1", "E"), "an unchanged hover is not re-sent")
  H.notOk(A:SendHover(3, "", ""), "a change inside the rate window waits")
  A:Tick(0.5); pump()
  got = eventsOf(events.b, "HOVER")
  H.eq(got[#got].handIndex, 3, "and is sent when the window opens")
  -- lockstep carries on untouched
  local g = A.game
  local active = g.activePlayer == 1 and A or B
  H.ok(active:LocalAction({ kind = "END_TURN" }), "an ordinary action still goes through")
  pump()
  H.eq(A.game:StateHash(), B.game:StateHash(), "and both clients agree")
  H.eq(#eventsOf(events.a, "ABORTED") + #eventsOf(events.b, "ABORTED"), 0, "nothing aborted")
  H.notOk(A:SendHover(1, "x;y", "E"), "a malformed code is refused")
end)

H.suite("net: a battlecry's placing slot travels as a hover source only", function(ns, H)
  local A, B, pump, events = connect(ns)
  H.ok(A:SendHover(0, "s3", "E"), "a placed minion's aim goes out")
  pump()
  local got = eventsOf(events.b, "HOVER")
  H.eq(got[#got].sourceId, "s3", "and arrives as the slot")
  A:Tick(1)
  H.notOk(A:SendHover(0, "H", "s3"), "but a slot is never a target")
end)

--============================================================ docs/27

H.suite("net: two players who challenge each other at once play ONE game", function(ns, H)
  --[[ THE REPORT: both players duelled each other, the game started at once,
       and each thought it was their turn -- one played a card the other never
       saw. Each client had read the other's challenge as an ACCEPT, so both
       were the challenger: both player 1, each with its own nonce first. ]]
  local A, B, pump, events = pair(ns)
  A:Challenge("Brann")
  B:Challenge("Ayla")          -- before A's HELLO has arrived
  pump()
  H.eq(A.state, A.STATE.PLAYING, "A is playing")
  H.eq(B.state, B.STATE.PLAYING, "B is playing")
  H.ok(A.challenger ~= B.challenger, "exactly one of them is the challenger")
  H.ok(A.myIndex ~= B.myIndex, "and they sit in different seats")
  H.eq(A.seed, B.seed, "on the same seed")
  H.eq(A.game:StateHash(), B.game:StateHash(), "so it is the same game")
  local crossed = 0
  for _, side in ipairs({ events.a, events.b }) do
    for _, e in ipairs(eventsOf(side, "ACCEPTED")) do if e.crossed then crossed = crossed + 1 end end
  end
  H.eq(crossed, 1, "and the side that yielded is told the challenges crossed")
  -- and it stays in step once it is played
  A:LocalAction({ kind = "MULLIGAN", indices = {} })
  B:LocalAction({ kind = "MULLIGAN", indices = {} })
  pump()
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  local other = mover == A and B or A
  H.notOk(other.game.activePlayer == other.myIndex, "only one of them thinks it is their turn")
  mover:LocalAction({ kind = "END_TURN" })
  pump()
  H.eq(A.game:StateHash(), B.game:StateHash(), "a turn later they still agree")
end)

H.suite("net: the challenge is kept by the same side whichever way round", function(ns, H)
  local me, peer = { name = "Ayla", guid = "Player-1" }, { name = "Brann", guid = "Player-2" }
  H.ok(ns.Session.KeepsChallenge(me, peer) ~= ns.Session.KeepsChallenge(peer, me),
       "exactly one side keeps it")
  local a, b = { name = "Ayla" }, { name = "Brann" }
  H.ok(ns.Session.KeepsChallenge(a, b) ~= ns.Session.KeepsChallenge(b, a), "names break the tie without GUIDs")
end)

H.suite("net: an action is ONE message, its fingerprint riding inside it", function(ns, H)
  --[[ Attacks arrived late in duels. Every action cost three addon messages
       (the action plus an ACTION_HASH from each client) and WoW allows about
       one a second once its burst is spent. ]]
  local A, B, pump, events, wire = connect(ns)
  local mover = (A.game.activePlayer == A.myIndex) and A or B
  local from = mover == A and "a" or "b"
  local before = #wire.log
  mover:LocalAction({ kind = "END_TURN" })
  pump()
  local actions, hashes, total = 0, 0, 0
  for i = before + 1, #wire.log do
    local e = wire.log[i]
    total = total + 1
    if e.raw:find(";AC;", 1, true) then actions = actions + 1 end
    if e.raw:find(";AH;", 1, true) or e.raw:find(";HS;", 1, true) then hashes = hashes + 1 end
  end
  H.eq(actions, 1, "the action went out once")
  H.eq(hashes, 0, "and no fingerprint message followed it, from either side")
  H.eq(total, 1, "ending a turn is a single message on the wire")
  local line = wire.log[before + 1].raw
  H.ok(line:match(";h%d+x%d+$"), "the action carries its index and fingerprint: " .. line)
  H.eq(A.game:StateHash(), B.game:StateHash(), "and both sides agree")
end)

H.suite("net: the CHALLENGER noticing a divergence sends its log unasked", function(ns, H)
  --[[ Only the receiver of an action compares fingerprints now, so the
       challenger can be the one that notices. It does not wait to be asked. ]]
  local A, B, pump, events = connect(ns)
  if B.game.activePlayer ~= B.myIndex then
    A:LocalAction({ kind = "END_TURN" })
    pump()
  end
  -- corrupt the non-challenger, then let IT act: A is the one that notices
  B.game.players[1].hero.damage = B.game.players[1].hero.damage + 3
  B:LocalAction({ kind = "END_TURN" })
  pump()
  H.eq(#eventsOf(events.a, "RESYNCING"), 1, "the challenger noticed")
  H.eq(#eventsOf(events.b, "RESYNCED"), 1, "the non-challenger was rebuilt from its log")
  H.eq(A.game:StateHash(), B.game:StateHash(), "and agrees again")
  H.eq(#eventsOf(events.b, "ABORTED"), 0, "without ending the duel")
end)

H.suite("net: a challenge can be withdrawn, and the other side is told", function(ns, H)
  local A, B, pump, events = pair(ns)
  A:Challenge("Brann")
  pump()
  H.eq(B.state, B.STATE.INVITED, "B was asked")
  H.ok(A:Cancel(), "A withdraws")
  pump()
  H.eq(A.state, A.STATE.IDLE, "A is free again")
  local d = eventsOf(events.b, "DECLINED")[1]
  H.eq(d and d.reason, "cancelled", "B hears it was withdrawn, not declined")
  H.notOk(B:Accept(), "and there is nothing left to accept")
end)

--============================================================ docs/29

H.suite("net: a hostile sequence number cannot hang the inbox", function(ns, H)
  local P = ns.Protocol
  local inbox = P.Inbox.New()
  for _, seq in ipairs({ "1e300", "inf", "1e6", "99999999999" }) do
    local ready, nak = inbox:Receive(seq .. ";AC;E")
    H.eq(#ready, 0, seq .. " delivers nothing")
    H.eq(#nak, 0, seq .. " asks for nothing")
  end
  local ready, nak = inbox:Receive(P.Encode(200, "AC", "E"))
  H.eq(#ready, 0, "a message inside the window is held")
  H.ok(#nak <= P.MAX_NAK, "and one NAK names at most MAX_NAK holes")
  H.eq(#inbox:Receive(P.Encode(1, "AC", "E")), 1, "the stream still works afterwards")
end)

H.suite("net: a chunk group that can never complete ends the stream", function(ns, H)
  local P = ns.Protocol
  local inbox = P.Inbox.New()
  local _, _, why, fatal = inbox:Receive("1;" .. P.KIND.CHUNK .. ";1;1;65;xx")
  H.ok(fatal, "65 chunks is refused as fatal: " .. tostring(why))
end)

H.suite("net: hiccups spread over a long duel do not add up to an abort", function(ns, H)
  local A, B, pump, events, wire = connect(ns)
  for _ = 1, 40 do
    -- lose one line, then let the next reveal the hole and the NAK fill it
    local mover = (A.game.activePlayer == A.myIndex) and A or B
    local other = mover == A and B or A
    mover:Send(ns.Protocol.KIND.PING)
    local q = mover == A and wire.b or wire.a
    table.remove(q)
    mover:Send(ns.Protocol.KIND.PING)
    pump()
    H.ok(other.state ~= other.STATE.ABORTED, "still playing")
  end
  H.ok(A.state == A.STATE.PLAYING and B.state == B.STATE.PLAYING, "forty hiccups later, both are playing")
end)

H.suite("net: a win claimed while this side is still playing gives nobody a loss", function(ns, H)
  local A, B, pump, events = connect(ns)
  B:Send(ns.Protocol.KIND.BYE, "claimed")
  pump()
  H.notOk(A.game.over and A.game.winner == B.myIndex, "A did not just concede")
  H.eq(A.state, A.STATE.ABORTED, "the duel ends with no result")
end)

H.suite("net: re-sending PAUSE does not hold the table forever", function(ns, H)
  local A, B, pump, events = connect(ns)
  B:Pause("away"); pump()
  for _ = 1, 20 do
    A:Tick(5); B:Send(ns.Protocol.KIND.PAUSE, "combat"); pump()
    if A.game.over then break end
  end
  H.ok(A.game.over, "the grace ran from when they first left")
  H.eq(A.game.winner, A.myIndex, "and the player who stayed wins")
end)

H.suite("net: a deck with holes, or a class that does not exist, is refused", function(ns, H)
  H.notOk(ns.Session.ValidateRemoteDeck({ "CS2_029" }, "NOT_A_CLASS"), "an unknown class")
  local A, B, pump, events = pair(ns)
  local s = ns.Session.New({ name = "X", class = "MAGE", deck = ns.Controller.BasicDeck("MAGE") })
  s.peer.name = "Troll"
  s:Receive(ns.Protocol.Encode(1, ns.Protocol.KIND.HELLO, ns.Protocol.VERSION, "x", "NOT_A_CLASS", "Troll"))
  H.eq(s.state, s.STATE.ABORTED, "a challenge from a class that does not exist ends there")
end)

H.suite("net: the name shown is the sender's, never what the message claims", function(ns, H)
  local s = ns.Session.New({ name = "X", class = "MAGE", deck = ns.Controller.BasicDeck("MAGE") })
  s.peer.name = "RealSender"
  s:Receive(ns.Protocol.Encode(1, ns.Protocol.KIND.HELLO, ns.Protocol.VERSION, "x", "PRIEST", "YourGuildMaster"))
  H.eq(s.peer.name, "RealSender", "the transport's name stands")
  H.eq(ns.Session.Plain("|cffff0000Evil|r"), "cffff0000Evilr", "and escape codes are stripped from peer text")
end)

H.suite("net: hover coalescing cancels stale aims and clears immediately",function(ns,H)
  local A,B,pump,events=connect(ns)
  A:SendHover(0,"b1","E",0); pump()
  A:SendHover(0,"b1","e1",.01)
  A:SendHover(0,"b1","E",.02)
  A:Tick(.3); pump()
  local got=eventsOf(events.b,"HOVER")
  H.eq(#got,1,"returning to the last state cancels the queued detour")
  A:SendHover(0,"b1","e1",.31)
  H.ok(A:SendHover(0,"","",.32),"clear bypasses the throttle")
  pump(); A:Tick(.5); pump()
  got=eventsOf(events.b,"HOVER")
  H.eq(got[#got].sourceId,"")
  H.eq(got[#got].targetId,"")
  local count=#got
  B:Receive(ns.Protocol.Encode(0,ns.Protocol.KIND.HOVER,0,"b1","E",1,B.game.turn,B.game.bus.seq))
  H.eq(#eventsOf(events.b,"HOVER"),count,"older packets cannot resurrect the arrow")
  B:Receive(ns.Protocol.Encode(0,ns.Protocol.KIND.HOVER,0,"b1","E",99,B.game.turn-1,B.game.bus.seq))
  H.eq(#eventsOf(events.b,"HOVER"),count,"old turn aim is discarded")
end)

H.suite("net: invitation coordinates refresh only while offering",function(ns,H)
  local A,B,pump=pair(ns)
  local x=10
  A.getPosition=function() return {x=x,y=20,z=0,instance=1} end
  A:Challenge("Brann"); pump()
  H.eq(B.peer.position.x,10)
  x=30; A:Tick(1); pump()
  H.eq(B.peer.position.x,30)
  B:Accept(); pump()
  x=50; A:Tick(1); pump()
  H.eq(B.peer.position.x,30,"coordinates stop after accepting")
end)

H.suite("net: position messages cannot alias another protocol kind",function(ns,H)
  local seen={}
  for name,code in pairs(ns.Protocol.KIND) do
    H.eq(seen[code],nil,"unique message kind "..name)
    seen[code]=name
  end
end)

H.suite("net: rejoining peers can restart their hover sequence",function(ns,H)
  local A,B,pump,events=connect(ns)
  A.peerHoverSerial=100
  A:Receive(ns.Protocol.Encode(0,ns.Protocol.KIND.REJOIN_ACCEPT,"Brann"))
  H.eq(A.peerHoverSerial,nil)
  A:Receive(ns.Protocol.Encode(0,ns.Protocol.KIND.HOVER,0,"b1","E",1,A.game.turn,A.game.bus.seq))
  H.eq(#eventsOf(events.a,"HOVER"),1)
end)

H.suite("net: both players select decks after acceptance before starting", function(ns,H)
  local a,b,pump = pair(ns)
  a.me.deck, b.me.deck = nil,nil
  a:Challenge("Brann"); pump()
  a:Tick(25)
  H.eq(a.state, a.STATE.OFFERED, "addon receipt is distinct from acceptance")
  b:Accept(); pump()
  H.eq(a.state,a.STATE.SYNC); H.eq(b.state,b.STATE.SYNC)
  H.notOk(a.game); H.notOk(b.game)
  H.ok(b:ChooseDeck(ns.Controller.BasicDeck("PRIEST"))); pump()
  H.notOk(a.game); H.notOk(b.revealed, "no reveal before both decks are committed")
  H.ok(a:ChooseDeck(ns.Controller.BasicDeck("MAGE"))); pump()
  H.eq(a.state,a.STATE.PLAYING); H.eq(b.state,b.STATE.PLAYING)
  H.eq(a.game:StateHash(),b.game:StateHash())
end)

H.suite("net: missing addon response times out and declines once", function(ns,H)
  local a,b,pump,events = pair(ns)
  a:Challenge("Brann")
  a:Tick(20); a:Tick(20)
  H.eq(a.state,a.STATE.IDLE)
  H.eq(#eventsOf(events.a,"DECLINED"),1)
  H.eq(eventsOf(events.a,"DECLINED")[1].reason,"noaddon")
end)

H.suite("net: setup recovers a lost receipt and waits while both players choose",function(ns,H)
  local lost=false
  local a,b,pump = pair(ns,{drop=function(from,raw)
    local msg=ns.Protocol.Decode(raw)
    if from=="b" and msg.kind==ns.Protocol.KIND.PING and not lost then lost=true; return true end
  end})
  a.me.deck,b.me.deck=nil,nil
  a:Challenge("Brann"); pump()
  for i=1,6 do a:Tick(5); b:Tick(5); pump() end
  H.eq(a.state,a.STATE.OFFERED); H.ok(a.peer.present)
  b:Accept(); pump()
  for i=1,24 do a:Tick(5); b:Tick(5); pump() end
  H.eq(a.state,a.STATE.SYNC); H.eq(b.state,b.STATE.SYNC)
  a:Tick(ns.Session.SETUP_TIMEOUT)
  H.eq(a.state,a.STATE.ABORTED); H.eq(a.abortReason,"disconnected")
end)

H.suite("net: setup heartbeat recovers lost acceptance and deck exchange",function(ns,H)
  for _,kind in ipairs({ns.Protocol.KIND.HELLO, ns.Protocol.KIND.COMMIT, ns.Protocol.KIND.DECK, ns.Protocol.KIND.CHUNK}) do
    local lost=false
    local a,b,pump = pair(ns,{drop=function(from,raw)
      local msg=ns.Protocol.Decode(raw)
      if from=="b" and msg.kind==kind and not lost then lost=true; return true end
    end})
    a.me.deck,b.me.deck=nil,nil
    a:Challenge("Brann"); pump(); b:Accept(); pump()
    for i=1,8 do
      if a.state==a.STATE.SYNC and not a.committed then a:ChooseDeck(ns.Controller.BasicDeck("MAGE")) end
      if b.state==b.STATE.SYNC and not b.committed then b:ChooseDeck(ns.Controller.BasicDeck("PRIEST")) end
      a:Tick(5); b:Tick(5); pump()
    end
    H.eq(a.state,a.STATE.PLAYING); H.eq(b.state,b.STATE.PLAYING)
    H.eq(a.game:StateHash(),b.game:StateHash())
  end
end)

H.suite("net: a delayed decline from a previous invitation cannot cancel a new duel",function(ns,H)
  local a,b,pump = pair(ns)
  a:Challenge("Brann"); pump(); b:Accept(); pump()
  a:Receive(ns.Protocol.Encode(0,ns.Protocol.KIND.BYE,"declined","previous-invitation"))
  H.eq(a.state,a.STATE.PLAYING); H.notOk(a.game.over)
  b:Leave("declined"); pump()
  H.eq(a.state,a.STATE.OVER)
end)

H.suite("net: mutual end requires consent and a current challenge",function(ns,H)
  local a,b,pump=connect(ns)
  b:Send(ns.Protocol.KIND.END_DUEL,"yes",b.challengeId); pump()
  H.eq(a.state,ns.Session.STATE.PLAYING)
  a:AskEndDuel(); pump(); H.ok(b.endInvited)
  b:AnswerEndDuel(false); pump()
  H.eq(a.state,ns.Session.STATE.PLAYING); H.notOk(a.endAsked)
  H.eq(a:EndRequestRemaining(),120)
  H.notOk(a:AskEndDuel())
  a:Send(ns.Protocol.KIND.END_DUEL,"ask",a.challengeId); pump()
  H.notOk(b.endInvited,"receiver also enforces the cooldown")
  a.clock=(a.clock or 0)+119; b.clock=(b.clock or 0)+119
  H.eq(a:EndRequestRemaining(),1); H.notOk(a:AskEndDuel())
  a.clock=a.clock+1; b.clock=b.clock+1
  H.ok(a:AskEndDuel()); pump(); b:AnswerEndDuel(true); pump()
  H.eq(a.abortReason,"agreed"); H.eq(b.abortReason,"agreed")
  H.notOk(a.game.winner); H.notOk(b.game.winner)
end)
