--[[ Client/Net/Session.lua

  THE DUEL, AS A STATE MACHINE. This is what makes it the game in the brief
  rather than solitaire.

  NO WoW API IN THIS FILE. The transport is injected, so two sessions can be
  wired to each other in a test and play a whole match in a terminal -- which is
  exactly what tests/test_net.lua does, and it is the only way to be confident
  about a protocol before there is a second person to sit down with.

  ================================================================ THE CHOICE

  LOCKSTEP WITH A SHARED SEED, not an authoritative client. Both clients run the
  whole game; only ACTIONS cross the wire.

  Why, given the alternative was one client owning the state and sending the
  other a board to draw:

    * The engine is already deterministic and TESTED to be
      (tests/test_determinism.lua poisons math.random to prove it). Lockstep is
      the design that gets paid for that work; an authoritative client throws it
      away.
    * An action is a handful of bytes. A board is not. With a 255-byte message
      limit and a throttled chat channel, sending state after every effect is
      the design that runs out of budget first -- Mind Control alone rewrites
      most of both boards.
    * Every rule then runs on both machines, so a bug cannot be one-sided. A
      desync is DETECTED (state hashes are exchanged at every turn boundary)
      rather than silently rendered, and a detected desync is a bug report.
    * Recovery is cheap: an action log plus a seed replays the entire match.

  THE COST, STATED PLAINLY: both clients hold the full game state, including the
  opponent's hand and deck. A modified addon could read them. There is no fix
  for that in a peer-to-peer addon -- an authoritative client has the same
  problem the moment the authority is the other player's machine. What CAN be
  removed is the cheat that social pressure cannot see, so it is: the shuffle
  seed is derived by commit-reveal, and neither player can choose their draws.
  The rest is the honour system, between two people who chose to sit down
  together, which is what the brief asks for.

  ================================================================= THE FLOW

    A (challenger)                         B (challenged)
    -------------------------------------  ----------------------------------
    HELLO   proto, version, class, name ->
                                        <- HELLO   (or BYE if incompatible)
    COMMIT  hash(nonceA)                ->
                                        <- COMMIT  hash(nonceB)
    REVEAL  nonceA                      ->
                                        <- REVEAL  nonceB
        both derive seed = f(nonceA, nonceB); A is player 1 on BOTH clients
    DECK    30 ids (chunked)            ->
                                        <- DECK
        both build the identical Game and start it
    ACTION  ...                        <->  ACTION  ...
    HASH    turn, fingerprint          <->  HASH

  Versions are checked before anything is committed to, so an incompatible pair
  costs one message each and produces a sentence the player can act on.

  ORDERING IS NOT NEGOTIATED. The challenger is player 1 on both clients, and
  who takes the first turn falls out of the seed -- which neither side chose.
  That removes a round trip and a whole class of "we disagree about whose turn
  it is" bugs.
]]
local ADDON, ns = ...
local Protocol = ns.Protocol
local KIND = Protocol.KIND

local Session = {}
Session.__index = Session
ns.Session = Session

--[[ States. The machine only ever moves forward, except into ABORTED, which
     any state can reach and none can leave -- a session that has failed is
     never repaired in place, it is thrown away and a new one is made. ]]
Session.STATE = {
  IDLE     = "IDLE",       -- nothing happening
  OFFERED  = "OFFERED",    -- we challenged someone and are waiting
  INVITED  = "INVITED",    -- someone challenged us; the player must answer
  SYNC     = "SYNC",       -- handshake agreed; exchanging seed and decks
  PLAYING  = "PLAYING",
  OVER     = "OVER",       -- finished normally (win, loss, concede)
  ABORTED  = "ABORTED",    -- desync, incompatible version, peer vanished
  REJOINING = "REJOINING", -- we came back (reload, disconnect): awaiting the bundle
}
local S = Session.STATE

--[[ Create a session. Nothing is sent until Challenge or Accept.

     opts.send      function(rawString)  -- puts one message on the wire
     opts.onEvent   function(event, data)
     opts.name      our character name (for display on the far side)
     opts.class     our WoW class -- which is also our Hearthstone class
     opts.deck      30 card ids
     opts.nonce     our secret seed contribution; generated if absent
     opts.onAction  optional: called for every action applied, either side ]]
function Session.New(opts)
  opts = opts or {}
  local s = setmetatable({}, Session)
  s.state    = S.IDLE
  s.sendFn   = opts.send or function() end
  s.out      = Protocol.Outbox.New(s.sendFn)
  s.inbox    = Protocol.Inbox.New()
  s.onEvent  = opts.onEvent or function() end
  s.onAction = opts.onAction
  --[[ Called with (player, action) BEFORE an action is applied, from either
       side. The animation layer needs it: playing a card destroys the evidence
       of which card it was, so whatever wants to animate it has to look
       first. ]]
  s.onBeforeAction = opts.onBeforeAction
  s.onRejectedAction = opts.onRejectedAction
  s.getPosition = opts.getPosition
  s.me       = { name = opts.name or "you", class = opts.class or "MAGE",
                 deck = opts.deck, level=opts.level, guid=opts.guid,
                 wins = opts.wins, losses = opts.losses }
  s.peer     = {}
  s.nonce    = opts.nonce or tostring(math.floor((opts.now or 0) * 1000) + 1)
  s.hashes   = {}          -- turn -> our own fingerprint, for late comparison
  s.peerHash = {}          -- turn -> theirs, for early arrival
  s.naks     = 0
  s.paused   = nil
  s.log      = {}          -- every applied action, both sides, in order
  s.actionHashes = {}      -- action index -> our fingerprint after it
  s.peerActionHashes = {}  -- action index -> theirs
  return s
end

local function emit(s, event, data)
  s.onEvent(event, data or {})
end

--[[ Every failure funnels through here so there is exactly one place that ends
     a session, and exactly one event the UI has to handle. `fatal` distinguishes
     "we stopped playing" from "the game finished". ]]
--[[ Reasons the other side already knows about, or caused: everything else is
     something only THIS side saw (a desync, a fault, a lost stream), and the
     other client must hear of it -- or it plays on alone and, once our line
     goes quiet on our turn, is handed a win for a bug. ]]
local ABORT_SHARED = { agreed = true, version = true, aborted = true }

--[[ BYE "aborted" is new in 1.0.4. An older client reads any BYE it does not
     know, mid-game, as the sender forfeiting -- so it is only said to a peer
     whose HELLO says it understands it. Anyone else gets the old silence. ]]
function Session:PeerReadsAborted()
  local have = {}
  for n in tostring(self.peer.version or ""):gmatch("%d+") do have[#have + 1] = tonumber(n) end
  if #have == 0 then return false end
  for i, want in ipairs({ 1, 0, 4 }) do
    local v = have[i] or 0
    if v ~= want then return v > want end
  end
  return true
end

function Session:Abort(reason, detail)
  if self.state == S.ABORTED or self.state == S.OVER then return end
  if not ABORT_SHARED[reason] and self.state ~= S.IDLE and self:PeerReadsAborted() then
    self:Send(KIND.BYE, "aborted")   -- before the state changes: Send refuses once ABORTED
  end
  self.state = S.ABORTED
  self.abortReason = reason
  emit(self, "ABORTED", { reason = reason, detail = detail })
end

function Session:Send(kind, ...)
  if self.state == S.ABORTED then return end
  --[[ A BYE is unsequenced. It took a sequence number once, and the transport
       sends every BYE at 0 -- so the number was never delivered, and
       everything said after it (the result's PROFILE, a rematch) waited
       forever behind that hole. ]]
  if kind == KIND.BYE then return self.out:SendVolatile(kind, (...), self.challengeId or "") end
  return self.out:Send(kind, ...)
end

function Session:SendVolatile(kind, ...)
  if self.state == S.ABORTED then return end
  return self.out:SendVolatile(kind, ...)
end

--[[ THE OPPONENT'S HANDS, SEEN. Hearthstone shows which card your opponent
     is holding up and where their arrow points. That is presentation only, so
     it travels as a volatile message: at most HOVER_RATE per second and only
     when it changes, and a lost one is simply replaced by the next. Fields:
     hand index lifted (0 = none), arrow source and target as seat-relative
     codes (Board:HoverState: "H", "P", "b3", "E", "e2", "" = none), plus
     "s3" as a SOURCE only: a minion being placed into slot 3 while its
     battlecry is aimed. Only the slot travels -- the card is still in hand, and
     the opponent's hand is hidden.
     A card in hand is identified by its SLOT, never its id -- the opponent's
     hand is hidden. ]]
Session.HOVER_RATE = 4
function Session:SendHover(handIndex, sourceId, targetId, now)
  if self.state ~= S.PLAYING then return false end
  if self.game and self.game:AwaitingMulligan() then return false end
  sourceId, targetId = tostring(sourceId or ""), tostring(targetId or "")
  if not sourceId:match("^[HPbsEe]?%d*$") or not targetId:match("^[HPbEe]?%d*$") then return false end
  local key = ("%d:%s:%s"):format(handIndex or 0, sourceId, targetId)
  if key == "0::" and not self.lastHoverKey then self.lastHoverKey=key; return false end
  now = now or self.clock or 0
  -- Returning to the last sent state cancels a different throttled update.
  if key == self.lastHoverKey then
    self.pendingHover = nil
    if key == "0::" or now - (self.lastHoverAt or now) < 1 then return false end
  end
  local clearing = (handIndex or 0) == 0 and sourceId == "" and targetId == ""
  if not clearing and self.lastHoverAt and now - self.lastHoverAt < 1 / Session.HOVER_RATE then
    self.pendingHover = { handIndex, sourceId, targetId }
    return false
  end
  self.lastHoverKey, self.lastHoverAt, self.pendingHover = key, now, nil
  self.hoverSerial = (self.hoverSerial or 0) + 1
  self:SendVolatile(KIND.HOVER, handIndex or 0, sourceId, targetId, self.hoverSerial,
    self.game and self.game.turn or 0, self.game and self.game.bus.seq or 0)
  return true
end

function Session:IsActive()
  return self.state == S.PLAYING or self.state == S.SYNC
end

-- ============================================================== handshake

--[[ Challenge a named player. The name is the transport's business -- this only
     records that we are the challenger, which decides that we are player 1. ]]
--[[ HELLO's tenth field says which HELLO it is: "c", a challenge, or "a", the
     answer to one. Without it a challenge that crossed ours on the wire read
     as their ACCEPTING ours, so both clients went on as the challenger --
     both player 1, each with its own nonce first -- and started two different
     games that each believed was the duel. ]]
function Session:SendHello(role)
  local pos = self.getPosition and self.getPosition() or {}
  self:Send(KIND.HELLO, Protocol.VERSION, Protocol.ADDON_VERSION,
            self.me.class, self.me.name, self.me.level or 0, self.me.guid or "", 1,
            self.me.wins or 0, self.me.losses or 0, role,
            pos.x or "", pos.y or "", pos.z or "", pos.instance or "", self.challengeId or "")
end

function Session:ReadPeerPosition(x, y, z, instance)
  x, y, z, instance = tonumber(x), tonumber(y), tonumber(z), tonumber(instance)
  for _,value in ipairs({x or false,y or false,z or false,instance or false}) do
    if type(value) ~= "number" or value ~= value or math.abs(value) > 1e7 then
      self.peer.position = nil; return
    end
  end
  self.peer.position = {x=x,y=y,z=z,instance=instance,at=self.clock or 0}
end

function Session:Challenge(peerName)
  if self.state ~= S.IDLE then return false, "already in a session" end
  self.challenger = true
  self.challengeId = self.nonce
  self.peer.name = peerName
  self.state = S.OFFERED
  self.offeredAt = self.clock or 0
  self:SendHello("c")
  return true
end

--[[ Accept a challenge we received. Deliberately a separate call from the HELLO
     that produced the INVITED state: a duel request is not something an addon
     may answer on the player's behalf. ]]
function Session:Accept()
  if self.state ~= S.INVITED then return false, "nothing to accept" end
  self.challenger = false
  self.state = S.SYNC
  self:SendHello("a")
  self:SendCommit()
  emit(self, "ACCEPTED", { name = self.peer.name })
  return true
end

--[[ TWO PLAYERS WHO CHALLENGED EACH OTHER AT ONCE both meant yes, so the duel
     goes ahead -- but exactly one of them may be the challenger. Both clients
     settle it the same way without a round trip: the lower character GUID
     (the name, if either has none) keeps the challenge, and the other side
     answers it as though it had pressed Accept. ]]
function Session.KeepsChallenge(me, peer)
  local function key(p)
    local guid = tostring(p.guid or "")
    if guid ~= "" then return "g" .. guid end
    return "n" .. tostring(p.name or ""):lower()
  end
  local mine, theirs = key(me), key(peer)
  if mine:sub(1, 1) ~= theirs:sub(1, 1) then
    mine, theirs = "n" .. tostring(me.name or ""):lower(), "n" .. tostring(peer.name or ""):lower()
  end
  return mine < theirs
end

--- Withdraw a challenge nobody has answered yet.
function Session:Cancel()
  if self.state ~= S.OFFERED then return false, "no challenge to withdraw" end
  self:Send(KIND.BYE, "cancelled")
  self.state = S.IDLE
  return true
end

function Session:Decline(reason)
  if self.state ~= S.INVITED then return false, "nothing to decline" end
  self:Send(KIND.BYE, reason or "declined")
  self.state = S.IDLE
  return true
end

--[[ THE COMMITMENT COVERS THE DECK. It used to be the nonce alone, and the deck
     travelled with the reveal -- so a modified client could hold its deck back,
     read the other nonce, compute the shuffle and stack its deck to suit. Now
     the commitment is to nonce AND deck; both are checked when they arrive
     (Session:TryStart). ]]
local function deckKey(deck) return table.concat(deck or {}, ",") end
Session.DeckKey = deckKey

function Session:SendCommit()
  if self.committed or not self.me.deck or self.state ~= S.SYNC then return end
  self.committed = true
  self:Send(KIND.COMMIT, Protocol.Hash2(self.nonce .. "|" .. deckKey(self.me.deck)))
end

function Session:ChooseDeck(deck)
  if self.state ~= S.SYNC or self.committed then return false end
  local ok, why = Session.ValidateRemoteDeck(deck, self.me.class)
  if not ok or #deck ~= ns.RULES.DECK_SIZE then return false, why or "Choose a complete deck." end
  self.me.deck = {}
  for i, id in ipairs(deck) do self.me.deck[i] = id end
  self:SendCommit()
  self:RevealDeck()
  return true
end

function Session:RevealDeck()
  if self.committed and self.peer.commit and not self.revealed then
    self.revealed = true
    self:Send(KIND.REVEAL, self.nonce)
    self:SendDeck()
  end
end

--[[ Both nonces are in. Derive the seed, build the identical game on both
     clients, and start it.

     The nonces are combined in CHALLENGER-FIRST order rather than in arrival
     order, because arrival order differs between the two machines and the seed
     must not. ]]
function Session:TryStart()
  if self.state ~= S.SYNC then return end
  if not (self.peer.nonce and self.peer.deck and self.me.deck) then return end

  if Protocol.Hash2(self.peer.nonce .. "|" .. deckKey(self.peer.deck)) ~= self.peer.commit then
    --[[ Their revealed nonce or deck does not match what they committed to.
         That is not a transport fault -- it is the only thing in this protocol
         that can only be a modified client -- so it is named as such. ]]
    self:Abort("cheat", "their client changed its shuffle seed or deck after committing to it")
    return
  end
  local a, b = self.nonce, self.peer.nonce
  if not self.challenger then a, b = b, a end
  local seed = ns.Game.DeriveSeed(a, b)

  local myIndex   = self.challenger and 1 or 2
  local peerIndex = 3 - myIndex
  local players = {}
  players[myIndex]   = { class = self.me.class,   deck = self.me.deck }
  players[peerIndex] = { class = self.peer.class, deck = self.peer.deck }

  --[[ Who goes first is derived from the seed, so neither player chose it and
       neither had to be told. Player 1 on a coin that neither side flipped. ]]
  local first = (seed % 2) + 1

  --[[ Everything needed to rebuild this game from nothing: the seed, the
       seats and the decks. With the action log that is the whole match -- the
       basis of resync (a desync) and rejoin (a reload or disconnect). ]]
  self.config = { seed = seed, first = first, players = players,
                  nonces = { a, b } }
  local game = Session.BuildGame(self.config)

  self.seed = seed
  self.game = game
  self.myIndex = myIndex
  self.peerIndex = peerIndex
  self.state = S.PLAYING
  emit(self, "START", { game = game, me = myIndex, first = first,
                        seed = seed, peer = self.peer })
end

--[[ DEAL, do not start. A duel begins with a mulligan: both players choose at
     once, each sends a MULLIGAN action, and the engine begins play by itself
     once both have arrived -- applying them in player order, so arrival order
     cannot desync the shuffle. ]]
function Session.BuildGame(config)
  local game = ns.Game.New({ seed = config.seed, firstPlayer = config.first, players = config.players })
  game:Deal()
  game.bus:Drain()
  return game
end

--- Rebuild a game from its config and an action log. nil + reason if refused.
function Session.Replay(config, log)
  local game = Session.BuildGame(config)
  for i, entry in ipairs(log) do
    local ok, why = ns.Actions.Apply(game, entry.player, entry.action)
    if not ok then return nil, ("action %d refused on replay: %s"):format(i, tostring(why)) end
    game.bus:Drain()
  end
  return game
end

-- ================================================================= actions

--[[ Apply an action to the game, from either side.

     One code path for both, on purpose. The local player's action has already
     been through the Controller's interaction model (mode prompt, targeting);
     the remote's arrives with those decisions already made. What must NOT
     differ is the rules check -- if a remote action is refused, the two clients
     have already disagreed about the state, and continuing would render a game
     the other player is not in. So a refusal is a DESYNC, not a shrug. ]]
function Session:ApplyAction(player, a)
  local g = self.game
  if not g then return false, "no game" end
  if self.onBeforeAction then self.onBeforeAction(player, a) end
  local ok, why = ns.Actions.Apply(g, player, a)
  if ok then
    g.bus:Drain()
    self.log[#self.log + 1] = { player = player, action = a }
    if self.onAction then self.onAction(player, a) end
  elseif self.onRejectedAction then
    self.onRejectedAction(player, a, why)
  end
  return ok, why
end

--[[ The local player did something. Apply it here first -- so an illegal action
     is refused locally and never reaches the wire -- then send it.

     Order matters: applying before sending means the two clients apply actions
     in the same order relative to each other's, because each client only ever
     originates actions on its own turn. ]]
function Session:LocalAction(a)
  if self.state ~= S.PLAYING then return false, "not playing" end
  if self.paused and a.kind~="CONCEDE" then return false, "the duel is paused" end
  --[[ Nothing is played while the two games are being put back in step: the
       other side drops incoming actions until then, so an action taken now
       was lost from one game and kept in the other. ]]
  if self.resyncing and a.kind~="CONCEDE" then return false, "the duel is resyncing" end
  local body, err = Protocol.EncodeAction(a)
  if not body then return false, err end

  local ok, why = self:ApplyAction(self.myIndex, a)
  if not ok then return false, why end

  --[[ THE FINGERPRINT RIDES WITH THE ACTION, as a last "h<hash>" field that
       DecodeAction never reads. It used to be a message of its own, from BOTH
       clients, after every action -- three messages where one does, against a
       WoW allowance of about one addon message a second once its burst is
       spent. Running that dry is what made attacks arrive late. ]]
  local n = #self.log
  self.actionHashes[n] = (self.game:StateHash())
  self:Send(KIND.ACTION, body, ("h%dx%s"):format(n, tostring(self.actionHashes[n])))
  self:AfterAction()
  return true
end

--[[ The fingerprint an ACTION message carries (its last field): the sender's
     log index and its hash there, or nil. The INDEX travels too, because the
     two logs need not agree on order while both players mulligan at once --
     index against index is what both sides can compare. ]]
function Session.CarriedHash(msg)
  local last = msg and msg.n and msg[msg.n]
  local n, h = tostring(last or ""):match("^h(%d+)x(%d+)$")
  if not n then return nil end
  return tonumber(n), tonumber(h)
end

--[[ After any action, from either side: fingerprint the game and compare it
     with the one the other client sent with the action. A fingerprint after
     EVERY action, not only at turn boundaries, so a disagreement is caught at
     the action that caused it -- while a resync is cheap and nobody has played
     on into a game that does not exist. Only the RECEIVER compares, so nothing
     goes back on the wire; either side can then set the resync going
     (Session:Disagree). ]]
function Session:AfterAction()
  local g = self.game
  if not g then return end
  local n = #self.log
  if n > 0 and not self.actionHashes[n] and self.state == S.PLAYING then
    self.actionHashes[n] = (g:StateHash())
  end
  if n > 0 then self:CheckActionHash(n) end
  if g.over then
    if self.state == S.PLAYING then
      self.state = S.OVER
      emit(self, "OVER", { winner = g.winner, me = self.myIndex })
    end
    return
  end
end

--[[ Compare fingerprints for a turn once BOTH are known. They can arrive in
     either order -- a fast opponent's hash for turn 5 can land before we have
     finished turn 4 -- so this is called from both sides and does nothing until
     the pair exists. ]]
function Session:CheckHash(turn)
  local mine, theirs = self.hashes[turn], self.peerHash[turn]
  if mine and theirs and mine ~= theirs then
    self:Disagree(("state diverged on turn %d (ours %d, theirs %d)"):format(turn, mine, theirs))
  end
end

function Session:CheckActionHash(n)
  local mine, theirs = self.actionHashes[n], self.peerActionHashes[n]
  if mine and theirs and mine ~= theirs then
    self:Disagree(("state diverged after action %d (ours %d, theirs %d)"):format(n, mine, theirs))
  end
end

--[[ A DISAGREEMENT. The challenger is authoritative: the other client
     rebuilds the game from the challenger's action log, the agreed seed and
     the decks, and compares. Matching, play simply continues on the rebuilt
     game (RESYNCED); still different, the duel ends as before -- a desync is a
     bug report, and a second attempt would only repeat it.

     Whichever side noticed starts it: the other client asks for the log, and
     the challenger, noticing first, simply sends it. ]]
Session.MAX_RESYNCS = 2
function Session:Disagree(detail)
  if self.state ~= S.PLAYING then return end
  if self.resyncing then return end
  self.resyncs = (self.resyncs or 0) + 1
  if self.resyncs > Session.MAX_RESYNCS then
    self:Abort("desync", detail .. " -- and resyncing did not fix it")
    return
  end
  self.resyncDetail = detail
  if self.challenger then
    self:SendResyncLog()
  else
    self.resyncing = true
    self:Send(KIND.RESYNC_REQ, #self.log)
  end
  emit(self, "RESYNCING", { detail = detail })
end

--[[ The log on the wire: each entry "player,verb,field,..." (the action's own
     fields with commas for separators), entries joined by "~". ]]
local function encodeLog(log)
  local parts = {}
  for _, e in ipairs(log) do
    local body = Protocol.EncodeAction(e.action)
    parts[#parts + 1] = e.player .. "," .. tostring(body):gsub(";", ",")
  end
  return table.concat(parts, "~")
end

local function decodeLog(text)
  local log = {}
  for entry in tostring(text or ""):gmatch("[^~]+") do
    local player, rest = entry:match("^(%d+),(.*)$")
    if not player then return nil, "malformed log entry" end
    local fields = { seq = 0, kind = KIND.ACTION }
    local n = 0
    for f in (rest .. ","):gmatch("([^,]*),") do n = n + 1; fields[n] = f end
    fields.n = n
    local a, err = Protocol.DecodeAction(fields)
    if not a then return nil, err end
    log[#log + 1] = { player = tonumber(player), action = a }
  end
  return log
end
Session.EncodeLog, Session.DecodeLog = encodeLog, decodeLog

--- The challenger's side of a resync: its whole log and its fingerprint.
function Session:SendResyncLog()
  self:Send(KIND.RESYNC_LOG, #self.log, (self.game:StateHash()), encodeLog(self.log))
end

--- Swap in a rebuilt game (resync or rejoin) and tell the UI.
function Session:AdoptGame(game, log, event)
  self.game = game
  self.log = log
  self.actionHashes, self.peerActionHashes = {}, {}
  self.hashes, self.peerHash = {}, {}
  self.lastHashedTurn = game.turn
  self.resyncing = false
  emit(self, event, { game = game, me = self.myIndex, seed = self.seed, peer = self.peer,
                      first = self.config and self.config.first, resumed = true })
end

function Session:Concede()
  if self.state ~= S.PLAYING then return false, "not playing" end
  return self:LocalAction({ kind = "CONCEDE" })
end

--[[ Emotes are their own message rather than an action, because they must not
     enter the action stream: they change no game state, and putting them in
     lockstep would make a dropped emote a desync. ]]
function Session:Emote(index)
  if self.state ~= S.PLAYING then return false, "not playing" end
  self:Send(KIND.EMOTE, index)
  return true
end

--[[ REMATCH, negotiated on the finished session's own message stream.

     ask   -> the other player sees "X would like a rematch" (REMATCH_ASKED)
     yes   -> agreed;  no -> REMATCH_DECLINED
     Both asking at once counts as both agreeing.

     Once agreed, the ORIGINAL challenger challenges again, so the roles are
     the same as the first game. It must not do so until the other side has
     let go of this session -- its inbox would drop the new stream's first
     message as a duplicate -- so the other side sends "ready" as its last
     word on this session, and the challenger starts only on receiving it.
     REMATCH_START {challenger} tells Main which half it plays. ]]
function Session:AskRematch()
  if self.state ~= S.OVER then return false, "the game is not over" end
  if self.rematch == "invited" then return self:AnswerRematch(true) end
  if self.rematch then return false, "already asked" end
  self.rematch = "asked"
  self:Send(KIND.REMATCH, "ask")
  return true
end

function Session:AnswerRematch(yes)
  if self.rematch ~= "invited" then return false, "nobody asked for a rematch" end
  self:Send(KIND.REMATCH, yes and "yes" or "no")
  if yes then self:RematchAgreed() else self.rematch = "refused" end
  return true
end

function Session:RematchAgreed()
  self.rematch = "agreed"
  if not self.challenger then
    self:Send(KIND.REMATCH, "ready")
    emit(self, "REMATCH_START", { challenger = false, name = self.peer.name })
  end
end

--[[ World interruption. The full policy (mob aggro, death, disconnect, standing
     up) is its own piece; what belongs HERE is only the wire half: tell the
     other player, and refuse local actions while either side is away, so the
     two clients cannot drift apart while one of them is fighting for its life. ]]
function Session:Pause(reason)
  if self.state ~= S.PLAYING then return false, "not playing" end
  if self.paused and self.paused.me == (reason or "away") then return true end
  self:Send(KIND.PAUSE, reason or "away")
  self.paused = self.paused or {}
  self.paused.me = reason or "away"
  --[[ The grace runs from when you FIRST left, as the other client counts it
       (handlers[KIND.PAUSE]): a change of reason must not restart only ours. ]]
  self.paused.meSince = self.paused.meSince or self.clock or 0
  emit(self, "PAUSED", { who = "me", reason = reason })
  return true
end

function Session:Resume()
  if not (self.paused and self.paused.me) then return false, "not paused" end
  self:Send(KIND.RESUME)
  self.paused.me, self.paused.meSince = nil, nil
  if not self.paused.peer then self.paused = nil end
  emit(self, "RESUMED", { who = "me" })
  return true
end

-- ================================================================ receive

--[[ One raw wire string from the transport. Everything about ordering,
     duplicates and reassembly is the Inbox's job; this handles meaning. ]]
function Session:Receive(raw)
  if self.state == S.ABORTED then return end
  local ready, nak, refused, fatal = self.inbox:Receive(raw)
  if fatal then
    self:Abort("lost", "a message arrived that could not be put back together (" .. tostring(refused) .. ")")
    return
  end

  --[[ The count is per hole, not per match: a long duel over a line WoW
       throttles now and then must not add its hiccups up to an abort. ]]
  if #nak == 0 then self.naks = 0 end
  --[[ While rejoining, a line from the host's OLD stream (a heartbeat sent just
       before it read our acceptance) is not a hole in the new one; asking for
       its "missing" predecessors made the host abort. The bundle starts the
       stream that counts (handlers[KIND.REJOIN_BUNDLE]). ]]
  if self.state == S.REJOINING then nak = {} end
  if #nak > 0 then
    --[[ Ask for the hole. A NAK that is itself lost is covered by the next
         message arriving and producing the same list again, so there is no
         retry timer -- but an endless loop of them means the peer cannot serve
         the resend, and at that point the match is over. ]]
    self.naks = self.naks + 1
    if self.naks > 32 then
      self:Abort("lost", "too many missing messages -- the connection is not carrying the duel")
      return
    end
    -- Recovery must bypass sequence gaps in BOTH directions. An ordered NAK
    -- can itself wait behind the packet it is asking the other peer to resend.
    self:SendVolatile(KIND.NAK, table.concat(nak, ","))
  end

  if #ready > 0 and self.connectionProblem then
    self.connectionProblem = false
    emit(self, "CONNECTION_RESTORED", {})
  end
  for _, msg in ipairs(ready) do
    self.silentFor=0
    self:Handle(msg)
    if self.state == S.ABORTED then return end
  end
end

local handlers = {}

handlers[KIND.ACTION_HASH] = function(s, msg)
  local n, h = Protocol.Num(msg, 1), Protocol.Num(msg, 2)
  if not (n and h) then return end
  s.peerActionHashes[n] = h
  s:CheckActionHash(n)
end

-- The challenger answers a resync request with its log and its fingerprint.
handlers[KIND.RESYNC_REQ] = function(s)
  if not s.challenger or s.state ~= S.PLAYING then return end
  s:SendResyncLog()
  -- the challenger's own game stands; it simply waits for the others to agree
  s.resyncing = false
end

handlers[KIND.RESYNC_LOG] = function(s, msg)
  if s.challenger or s.state ~= S.PLAYING then return end
  local count, hash = Protocol.Num(msg, 1), Protocol.Num(msg, 2)
  local log, err = decodeLog(msg[3])
  if not (log and count == #log) then
    s:Abort("desync", (s.resyncDetail or "state diverged") .. " -- and their log was unreadable: " .. tostring(err))
    return
  end
  local game, why = Session.Replay(s.config, log)
  if not game or (game:StateHash()) ~= hash then
    s:Abort("desync", (s.resyncDetail or "state diverged") .. " -- and replaying their log did not agree"
            .. (why and (": " .. why) or ""))
    return
  end
  s:AdoptGame(game, log, "RESYNCED")
end

handlers[KIND.HOVER] = function(s, msg)
  if s.state ~= S.PLAYING then return end
  local serial, turn, eventSeq = tonumber(msg[4]), tonumber(msg[5]), tonumber(msg[6])
  if serial then
    if serial <= (s.peerHoverSerial or 0) then return end
    s.peerHoverSerial = serial
  end
  if s.game and ((turn and turn ~= s.game.turn) or (eventSeq and eventSeq ~= s.game.bus.seq)) then return end
  local src, dst = tostring(msg[2] or ""), tostring(msg[3] or "")
  if not src:match("^[HPbsEe]?%d*$") or not dst:match("^[HPbEe]?%d*$") then return end
  emit(s, "HOVER", { handIndex = tonumber(msg[1]) or 0, sourceId = src, targetId = dst })
end

handlers[KIND.POSITION] = function(s, msg)
  if s.state == S.INVITED then s:ReadPeerPosition(msg[1],msg[2],msg[3],msg[4]) end
end

function Session:Handle(msg)
  local h = handlers[msg.kind]
  if not h then return end     -- unknown kinds are ignored, not fatal: that is
                               -- what lets a newer peer add messages safely
  h(self, msg)
end

handlers[KIND.HELLO] = function(s, msg)
  if s.state == S.IDLE then s.challengeId = msg[15] end
  local proto, version = msg[1], msg[2]
  local class, name = msg[3], msg[4]
  local ok, why, advice = Protocol.CheckVersion(proto, version)
  if not ok then
    s:Send(KIND.BYE, "version")
    s:Abort("version", advice)
    return
  end
  if not Session.KnownClass(class) then
    s:Send(KIND.BYE, "version")
    s:Abort("version", "their addon sent a challenge this version cannot read")
    return
  end
  s.peer.class   = class
  --[[ The name the transport saw them send from is the truth; the one in the
       message is only their say-so. It is used only when there is nothing
       better, and never with WoW's escape codes in it. ]]
  s.peer.name    = s.peer.name or Session.Plain(name)
  s.peer.version = Session.Plain(version)
  s.peer.level=tonumber(msg[5]); s.peer.guid=msg[6]
  s.peer.heartbeat=tonumber(msg[7])==1
  s.peer.wins, s.peer.losses = tonumber(msg[8]), tonumber(msg[9])
  s:ReadPeerPosition(msg[11], msg[12], msg[13], msg[14])

  if s.state == S.IDLE then
    --[[ An unsolicited HELLO is an incoming challenge. The player answers it --
         Accept/Decline -- because an addon that auto-accepted duels would be a
         griefing tool the moment anyone noticed. ]]
    s.state = S.INVITED
    s:Send(KIND.PING, "invited")
    emit(s, "CHALLENGED", { name = s.peer.name, class = class, version = version })
  elseif s.state == S.OFFERED and msg[10] == "c" then
    --[[ Not an answer: their own challenge, sent before ours arrived. One of
         us keeps the challenge and the other answers it (KeepsChallenge). The
         keeper does nothing here -- the other side's "a" is on its way. ]]
    if Session.KeepsChallenge(s.me, s.peer) then return end
    s.challengeId = msg[15]
    s.challenger = false
    s.state = S.SYNC
    s:SendHello("a")
    s:SendCommit()
    emit(s, "ACCEPTED", { name = s.peer.name, class = class, crossed = true })
  elseif s.state == S.OFFERED then
    -- they answered our challenge: proceed to the seed exchange
    s.state = S.SYNC
    s:SendCommit()
    emit(s, "ACCEPTED", { name = s.peer.name, class = class })
  end
end

handlers[KIND.COMMIT] = function(s, msg)
  if s.state ~= S.SYNC then return end
  s.peer.commit = msg[1]
  s:SendCommit()                      -- no-op if we already did
  --[[ Reveal only AFTER we hold their commitment. Revealing first would let a
       modified client pick its nonce to suit our revealed one, which is the
       exact cheat commit-reveal exists to prevent. ]]
  s:RevealDeck()
end

handlers[KIND.REVEAL] = function(s, msg)
  if s.state ~= S.SYNC then return end
  local nonce = msg[1]
  if not nonce then return end
  if not s.peer.commit then
    s:Abort("cheat", "their client revealed a seed it never committed to")
    return
  end
  -- checked against the commitment with the deck, in TryStart
  s.peer.nonce = nonce
  s:TryStart()
end

handlers[KIND.DECK] = function(s, msg)
  if s.state ~= S.SYNC then return end
  local ids = {}
  -- an empty field is a hole, and #/ipairs disagree about holes: count them all
  for i = 1, (msg.n or 0) do
    if msg[i] then ids[#ids + 1] = msg[i] end
  end
  if #ids ~= ns.RULES.DECK_SIZE or (msg.n or 0) ~= #ids then
    s:Abort("deck", ("their deck arrived with %d cards, not %d")
                    :format(msg.n or 0, ns.RULES.DECK_SIZE))
    return
  end
  local ok, why = Session.ValidateRemoteDeck(ids, s.peer.class)
  if not ok then s:Abort("deck", why); return end
  s.peer.deck = ids
  s:TryStart()
end

--[[ THE OPPONENT'S DECK IS CHECKED HERE TOO, not only by their own client:
     thirty known, collectible, obtainable cards, of their class or neutral,
     no more than two of any (one of a legendary). What we cannot check is
     their COLLECTION -- that lives on their machine -- which is the one part
     of this left on the honour system (plus a tamper-evident vault, docs/13). ]]
function Session.ValidateRemoteDeck(ids, class)
  if class and not Session.KnownClass(class) then
    return false, "their client named a class this addon does not know: " .. tostring(class)
  end
  local counts = {}
  for _, id in ipairs(ids) do
    local p = ns.PrintedCards[id]
    if not p then return false, "their deck contains a card this addon does not know: " .. tostring(id) end
    if not p.collectible or p.unobtainable or p.type == "HERO" then
      return false, "their deck contains a card no one can own: " .. tostring(p.name or id)
    end
    if class and p.class and p.class ~= "NEUTRAL" and p.class ~= class then
      return false, ("their %s deck contains a %s card: %s"):format(tostring(class):lower(),
                    tostring(p.class):lower(), tostring(p.name or id))
    end
    counts[id] = (counts[id] or 0) + 1
    local max = p.rarity == "LEGENDARY" and ns.RULES.MAX_COPIES_LEG or ns.RULES.MAX_COPIES
    if counts[id] > max then
      return false, ("their deck has %d copies of %s"):format(counts[id], tostring(p.name or id))
    end
  end
  return true
end

--- Text another player sent, made safe to print: no |c colours, |T textures
--- or |H links, and a sane length.
function Session.Plain(text)
  if text == nil then return nil end
  return (tostring(text):gsub("|", ""):sub(1, 48))
end

--- A class a hero exists for. Anything else would reach the engine as
--- "HERO_<nonsense>" and fail there instead of here.
function Session.KnownClass(class)
  return type(class) == "string" and ns.HERO_ID_BY_CLASS ~= nil and ns.HERO_ID_BY_CLASS[class] ~= nil
end

handlers[KIND.ACTION] = function(s, msg)
  if s.state ~= S.PLAYING then return end
  local a, err = Protocol.DecodeAction(msg)
  if not a then s:Abort("protocol", err); return end
  if s.resyncing then return end    -- the rebuilt game will include it
  local ok, why = s:ApplyAction(s.peerIndex, a)
  if not ok then
    --[[ THE IMPORTANT BRANCH. A remote action the rules refuse means the two
         clients already disagree about the state -- the opponent's client
         thought this was legal. Rendering on regardless shows a game the other
         player is not playing, so the authoritative log is asked for. ]]
    s:Disagree(("their action was illegal here (%s): %s"):format(tostring(a.kind), tostring(why)))
    return
  end
  local n, h = Session.CarriedHash(msg)
  if n then s.peerActionHashes[n] = h end
  s:AfterAction()
  if n and n ~= #s.log then s:CheckActionHash(n) end
  emit(s, "REMOTE_ACTION", { action = a })
end

handlers[KIND.HASH] = function(s, msg)
  local turn = Protocol.Num(msg, 1)
  local h    = Protocol.Num(msg, 2)
  if not (turn and h) then return end
  s.peerHash[turn] = h
  s:CheckHash(turn)
end

handlers[KIND.REMATCH] = function(s, msg)
  if s.state ~= S.OVER then return end
  local verb = msg[1]
  if verb == "ask" then
    if s.rematch == "asked" then
      s:Send(KIND.REMATCH, "yes"); s:RematchAgreed()
    elseif not s.rematch then
      s.rematch = "invited"
      emit(s, "REMATCH_ASKED", { name = s.peer.name })
    end
  elseif verb == "yes" and s.rematch == "asked" then
    s:RematchAgreed()
  elseif verb == "no" and s.rematch == "asked" then
    s.rematch = "refused"
    emit(s, "REMATCH_DECLINED", { name = s.peer.name })
  elseif verb == "ready" and s.challenger and s.rematch == "agreed" then
    s.rematch = "started"
    emit(s, "REMATCH_START", { challenger = true, name = s.peer.name })
  end
end

Session.END_REQUEST_COOLDOWN = 120

function Session:EndRequestRemaining()
  return math.max(0, math.ceil((self.endRequestAfter or 0) - (self.clock or 0)))
end

-- Agreement ends the session without a concede action or a recorded result.
function Session:AskEndDuel()
  if self.state~=S.PLAYING or self.endAsked or self:EndRequestRemaining()>0 then return false end
  self.endAsked=true
  self:Send(KIND.END_DUEL,"ask",self.challengeId)
  emit(self,"END_SENT")
  return true
end

function Session:AnswerEndDuel(agree)
  if self.state~=S.PLAYING or not self.endInvited then return false end
  self.endInvited=nil
  if not agree then self.peerEndRequestAfter=(self.clock or 0)+Session.END_REQUEST_COOLDOWN end
  self:Send(KIND.END_DUEL,agree and "yes" or "no",self.challengeId)
  --[[ If the yes is lost, the asker would wait, and on our turn claim a win
       over a duel we both agreed to end. The BYE behind it (sent after, and
       kept in order) turns that silence into "no result". ]]
  if agree and self:PeerReadsAborted() then self:Send(KIND.BYE,"aborted") end
  if agree then self:Abort("agreed","Both players agreed to end the duel. No win, loss or forfeit.") end
  return true
end

handlers[KIND.END_DUEL] = function(s,msg)
  if s.state~=S.PLAYING or msg[2]~=s.challengeId then return end
  if msg[1]=="ask" and not s.endInvited and (s.clock or 0)>=(s.peerEndRequestAfter or 0) then
    s.endInvited=true
    emit(s,"END_ASKED",{name=s.peer.name})
  elseif msg[1]=="yes" and s.endAsked then
    s:Abort("agreed","Both players agreed to end the duel. No win, loss or forfeit.")
  elseif msg[1]=="no" and s.endAsked then
    s.endAsked=nil
    s.endRequestAfter=(s.clock or 0)+Session.END_REQUEST_COOLDOWN
    emit(s,"END_DECLINED")
  end
end

handlers[KIND.EMOTE] = function(s, msg)
  emit(s, "EMOTE", { index = Protocol.Num(msg, 1, 0) })
end

handlers[KIND.PAUSE] = function(s, msg)
  s.paused = s.paused or {}
  s.paused.peer = msg[1] or "away"
  --[[ The grace runs from when they FIRST left. A repeated PAUSE, or one that
       only changes the reason (combat, then away), must not restart it --
       otherwise re-sending PAUSE would hold the table forever. ]]
  s.paused.peerSince = s.paused.peerSince or s.clock or 0
  emit(s, "PAUSED", { who = "peer", reason = s.paused.peer })
end

handlers[KIND.RESUME] = function(s, msg)
  if s.paused then
    s.paused.peer, s.paused.peerSince = nil, nil
    if not s.paused.me then s.paused = nil end
  end
  emit(s, "RESUMED", { who = "peer" })
end

handlers[KIND.NAK] = function(s, msg)
  local seqs = {}
  --[[ A number we never sent is not ours to resend: it is a request about our
       stream from before a rejoin reset it. Ignored, never a reason to abort. ]]
  for n in tostring(msg[1] or ""):gmatch("%d+") do
    local seq = tonumber(n)
    if seq >= 1 and seq <= (s.out.seq or 0) then seqs[#seqs + 1] = seq end   -- 0 is never a sequence
  end
  -- one NAK asks for at most one hole's worth; it cannot flood our queue
  for i = #seqs, Protocol.MAX_NAK + 1, -1 do seqs[i] = nil end
  local ok, lost = s.out:Resend(seqs)
  if not ok then
    s:Abort("lost", ("they asked for message %s, which is older than anything kept")
                    :format(tostring(lost[1])))
  end
end

handlers[KIND.PING] = function(s, msg)
  if s.state == S.OFFERED and msg[1] == "invited" then s.peer.present = true end
  -- The final action can be lost. A finished sender no longer ticks PINGs,
  -- so answer a still-playing peer's heartbeat with a later ordered sequence:
  -- that reveals the hole and lets ordinary NAK recovery resend the result.
  -- Mark replies to prevent two finished peers echoing them forever.
  local now=s.clock or 0
  if s.state==S.OVER and msg[1]~='over'
    and (not s.lastFinalPing or now-s.lastFinalPing>=Session.HEARTBEAT_INTERVAL) then
    s.lastFinalPing=now
    s:Send(KIND.PING,'over')
  end
end
handlers[KIND.PROFILE] = function(s,msg)
  s.peer.level=tonumber(msg[1]); s.peer.guid=msg[2]
  if msg[3] then s.peer.wins, s.peer.losses = tonumber(msg[3]), tonumber(msg[4]) end
  emit(s,"PROFILE",s.peer)
end
handlers[KIND.BYE] = function(s, msg)
  if s.state==S.OVER or s.state==S.ABORTED then return end
  local reason = msg[1] or "left"
  if s.challengeId and reason ~= "version" and msg[2] ~= s.challengeId then return end
  if reason == "aborted" then
    -- their client ended it over something only it saw: nobody won
    if s.state ~= S.IDLE then
      s:Abort("aborted", "the other player's client had to end the duel -- no result recorded")
    end
  elseif s.state == S.PLAYING and reason == "claimed" and not s:ClaimIsFair() then
    --[[ A claim this side cannot account for: we are here, talking, and it is
         not our turn running long. Nobody is handed a loss by one message. ]]
    s:Abort("disconnected", "they claimed the win, but the duel was still on here -- no result recorded")
  elseif s.state == S.PLAYING and reason == "claimed" then
    --[[ They claimed the win from our absence or our stalled turn. Agree,
         so both clients record the same result: our hero concedes. ]]
    s:ApplyAction(s.myIndex,{kind="CONCEDE"})
    emit(s,"FORFEIT",{by="me",reason="claimed"})
    s:AfterAction()
  elseif s.state == S.PLAYING then
    s:ApplyAction(s.peerIndex,{kind="CONCEDE"})
    emit(s,"FORFEIT",{by="peer",reason=reason})
    s:AfterAction()
  else
    s.state=S.IDLE; emit(s,"DECLINED",{reason=reason})
  end
end

--[[ A hover that arrived inside the rate limit is sent once the window opens,
     so the opponent always ends up seeing where you finally settled. ]]
function Session:FlushHover(now)
  local p = self.pendingHover
  if not p or self.state ~= S.PLAYING then return end
  if self.lastHoverAt and now - self.lastHoverAt < 1 / Session.HOVER_RATE then return end
  self.pendingHover = nil
  self.lastHoverKey = nil
  self:SendHover(p[1], p[2], p[3], now)
end

--[[ STAYING AT THE TABLE (docs/13: pause, then forfeit).

     A player who steps away, dies or is pulled into combat PAUSES the duel
     (Main decides that from the world and calls Pause). While paused nobody
     can act, and the rope stands still. A pause has a grace period; if the
     player is not back by then, their own client forfeits for them, and if it
     does not (a crash, a hard disconnect) the other client claims the win a
     little later.

     SILENCE is different: it cannot say which side lost its connection. After
     PROBLEM_AFTER seconds both sides show "connection problem" and the silent
     side is offered a rejoin; after CONNECTION_TIMEOUT the waiting player wins
     only if it is the SILENT player's turn -- so a clean network split can
     never hand both players a win -- and on your own turn you may play on
     until ABANDON_AFTER, when the duel ends with no winner. ]]
Session.SETUP_TIMEOUT = 45
Session.ADDON_TIMEOUT = 20
Session.HEARTBEAT_INTERVAL = 5
Session.PROBLEM_AFTER      = 10
Session.CONNECTION_TIMEOUT = 120
Session.ABANDON_AFTER      = 300
Session.REJOIN_EVERY       = 5
Session.REJOIN_TIMEOUT     = 30
Session.GRACE = { away = 60, combat = 60, dead = 180, left = 90 }
Session.CLAIM_MARGIN = 15
--[[ STALLING. A connected opponent whose turn has run TURN + STALL_GRACE
     seconds without ending (their client should have ended it at the rope)
     can be beaten by claiming the win. ]]
Session.STALL_GRACE = 45

function Session:Grace(reason)
  return Session.GRACE[reason or "away"] or Session.GRACE.away
end

function Session:Tick(dt)
  self.clock=(self.clock or 0)+dt
  if self.state == S.OFFERED and not self.peer.present and self.clock - (self.offeredAt or 0) >= Session.ADDON_TIMEOUT then
    self:Send(KIND.BYE, "cancelled")
    self.state = S.IDLE
    emit(self, "DECLINED", {reason="noaddon"})
    return
  end
  if self.state == S.OFFERED and self.getPosition
     and self.clock - (self.lastPositionAt or -1) >= 1 then
    self.lastPositionAt = self.clock
    local pos = self.getPosition() or {}
    self:SendVolatile(KIND.POSITION,pos.x or "",pos.y or "",pos.z or "",pos.instance or "")
  end
  if self.state == S.OFFERED or self.state == S.INVITED or self.state == S.SYNC then
    self.silentFor = (self.silentFor or 0) + dt
    self.setupPingAge = (self.setupPingAge or 0) + dt
    if self.silentFor >= Session.SETUP_TIMEOUT and (self.state ~= S.OFFERED or self.peer.present) then
      self:Send(KIND.BYE, "cancelled")
      self:Abort("disconnected", "The other player stopped responding before the duel started. Challenge them again when they are back.")
      return
    end
    if self.setupPingAge >= Session.HEARTBEAT_INTERVAL then
      self.setupPingAge = 0
      -- Ordered heartbeats also expose a lost acceptance, commitment or deck chunk.
      self:Send(KIND.PING, self.state == S.INVITED and "invited" or "setup")
    end
    return
  end
  --[[ Waiting for the duel back. Our REJOIN_ACCEPT is one volatile line; if it
       was lost, their next offer is answered again (handlers[KIND.REJOIN]),
       and if nothing comes at all we stop waiting -- a client stuck here
       could not be challenged by anyone until a reload. ]]
  if self.state == S.REJOINING then
    self.rejoinWait = (self.rejoinWait or 0) + dt
    if self.rejoinWait >= Session.REJOIN_TIMEOUT then
      self:Abort("rejoin", "the duel could not be resumed -- the other player did not answer")
    end
    return
  end
  if self.state==S.PLAYING then self:FlushHover(self.clock) end
  if self.state~=S.PLAYING then return end
  local now = self.clock

  -- pauses and their grace periods
  local p = self.paused
  --[[ BOTH AWAY (two players pulled into the same fight): each client used
       to forfeit for its own player and ignore the other's forfeit, so each
       recorded a loss and the boards named different winners. Nobody wins a
       table both players left; the BYE from Abort ends the other side too. ]]
  local mineOut = p and p.me and now - (p.meSince or now) > self:Grace(p.me)
  local theirsOut = p and p.peer and now - (p.peerSince or now) > self:Grace(p.peer) + Session.CLAIM_MARGIN
  if (mineOut or theirsOut) and p.me and p.peer then
    self:Abort("away", "you were both away from the table too long -- no result recorded")
    return
  end
  if mineOut then
    emit(self, "TIMED_OUT", { who = "me", reason = p.me })
    self:Leave("away")
    return
  end
  if theirsOut then
    self:ClaimWin("they did not come back to the table")
    return
  end

  -- stalling: the turn clock runs only while the table is whole and talking
  local g = self.game
  if g and g.activePlayer ~= self.turnPlayer then
    local wasStalling = self.stalling
    self.turnPlayer, self.turnStart, self.stalling = g.activePlayer, now, false
    -- they played on after all: the claim notice must go with it
    if wasStalling then emit(self, "STALL_CLEARED", { name = self.peer.name }) end
  end
  if p or self.connectionProblem then self.turnStart = (self.turnStart or now) + dt end
  if g and g.activePlayer == self.peerIndex and not self.stalling and self.turnStart
     and now - self.turnStart > (g.TurnSeconds and g:TurnSeconds() or 75) + Session.STALL_GRACE then
    self.stalling = true
    emit(self, "STALLING", { name = self.peer.name })
  end

  if not self.peer.heartbeat then return end
  self.silentFor=(self.silentFor or 0)+dt
  self.pingAge=(self.pingAge or 0)+dt
  if self.silentFor >= Session.PROBLEM_AFTER and not self.connectionProblem then
    self.connectionProblem = true
    self.rejoinAge = Session.REJOIN_EVERY
    emit(self, "CONNECTION_PROBLEM", { name = self.peer.name })
  end
  if self.connectionProblem then
    -- if they reloaded, their client no longer knows this duel: offer it
    self.rejoinAge = (self.rejoinAge or 0) + dt
    if self.rejoinAge >= Session.REJOIN_EVERY then
      self.rejoinAge = 0
      self.rejoinOffered = true   -- an acceptance is only honoured while this is open
      self:SendVolatile(KIND.REJOIN, self.peer.name or "")
    end
  end
  if self.silentFor >= Session.CONNECTION_TIMEOUT and g and g.activePlayer == self.peerIndex then
    self:ClaimWin("they disconnected")
    return
  end
  if self.silentFor >= Session.ABANDON_AFTER then
    self:Abort("disconnected",("No response from the other player for %d seconds. Duel interrupted; no winner awarded.")
               :format(Session.ABANDON_AFTER))
    return
  end
  if self.pingAge>=Session.HEARTBEAT_INTERVAL then
    self.pingAge=0; self:Send(KIND.PING)
  end
end

--[[ WIN BY THE OTHER PLAYER'S ABSENCE: their hero concedes on OUR client. The
     BYE goes out in case they are still listening, so their client agrees. ]]
function Session:ClaimWin(reason)
  if self.state ~= S.PLAYING or not self.game then return false end
  self:ApplyAction(self.peerIndex, { kind = "CONCEDE" })
  emit(self, "FORFEIT", { by = "peer", reason = reason, claimed = true })
  self:Send(KIND.BYE, "claimed")
  self:AfterAction()
  return true
end

--[[ Could the other player fairly have claimed the win from here? Only if we
     are away from the table, our own turn has run past the rope, or we have
     already noticed the line going quiet (so they may have heard nothing). ]]
function Session:ClaimIsFair()
  if self.paused and self.paused.me then return true end
  if self.connectionProblem then return true end
  local g = self.game
  if g and g.activePlayer == self.myIndex and self.turnStart
     and (self.clock or 0) - self.turnStart > (g.TurnSeconds and g:TurnSeconds() or 75) then
    return true
  end
  return false
end

--- The waiting player's answer to a stalling opponent (Main's "Claim victory").
function Session:ClaimVictory()
  if not self.stalling then return false, "they still have time" end
  return self:ClaimWin("they stopped taking their turn")
end

-- ================================================================ rejoin

--[[ WE ARE BACK. After a /reload or a disconnect this client no longer holds
     the duel; the other client still does, and offers it (REJOIN). Accepting
     sends REJOIN_ACCEPT (volatile: our stream starts afresh at 1, and theirs
     is reset to match), and they answer with everything needed to rebuild the
     match: seats, seed, classes, decks and the action log. The game is replayed
     and checked against their fingerprint before play resumes. ]]
function Session:RequestRejoin(peerName)
  self.peer.name = peerName or self.peer.name
  self.state = S.REJOINING
  self.rejoinWait = 0
  self.acceptedAt = self.clock or 0
  self:SendVolatile(KIND.REJOIN_ACCEPT, self.me.name or "")
  return true
end

--[[ Still offering the duel, so our acceptance may have been lost: say yes
     again -- but not to the offer that was already on its way when the first
     yes landed. Waiting longer than an offer's interval also keeps an older
     host, which answers every acceptance, from resetting a resumed duel. ]]
Session.REACCEPT_AFTER = 8
handlers[KIND.REJOIN] = function(s)
  if s.state ~= S.REJOINING then return end
  local now = s.clock or 0
  if now - (s.acceptedAt or -math.huge) < Session.REACCEPT_AFTER then return end
  s.acceptedAt = now
  s:SendVolatile(KIND.REJOIN_ACCEPT, s.me.name or "")
end

handlers[KIND.REJOIN_ACCEPT] = function(s)
  if s.state ~= S.PLAYING or not s.config then return end
  --[[ Only an answer to an offer that is still open: the first acceptance
       closes it. A second one (it crossed our next offer) reset both streams
       under a duel that had already resumed, and the two sides drifted apart
       in silence. (Not keyed on connectionProblem: Receive clears that the
       moment the acceptance itself arrives.) ]]
  if not s.rejoinOffered then return end
  s.rejoinOffered = nil
  -- The returning client starts its volatile hover counter over as well.
  s.peerHoverSerial = nil
  -- they are back at the table
  if s.paused and s.paused.peer then
    s.paused.peer, s.paused.peerSince = nil, nil
    if not s.paused.me then s.paused = nil end
    emit(s, "RESUMED", { who = "peer" })
  end
  -- a fresh stream in both directions
  s.out = Protocol.Outbox.New(s.sendFn)
  s.inbox = Protocol.Inbox.New()
  local c = s.config
  local p1, p2 = c.players[1], c.players[2]
  s:Send(KIND.REJOIN_BUNDLE, s.peerIndex, c.seed, c.first, p1.class, p2.class,
         deckKey(p1.deck), deckKey(p2.deck), (s.game:StateHash()), encodeLog(s.log), s.challengeId or "")
  s.silentFor = 0
  if s.connectionProblem then
    s.connectionProblem = false
    emit(s, "CONNECTION_RESTORED", { rejoined = true })
  end
end

handlers[KIND.REJOIN_BUNDLE] = function(s, msg)
  if s.state ~= S.REJOINING then return end
  local seat, seed, first = Protocol.Num(msg, 1), Protocol.Num(msg, 2), Protocol.Num(msg, 3)
  local function ids(text) local t = {} for id in tostring(text or ""):gmatch("[^,]+") do t[#t + 1] = id end return t end
  local players = { { class = msg[4], deck = ids(msg[6]) }, { class = msg[5], deck = ids(msg[7]) } }
  local hash = Protocol.Num(msg, 8)
  local log, err = decodeLog(msg[9])
  if not (seat and seed and first and log) then
    s:Abort("rejoin", "the rejoin bundle was unreadable: " .. tostring(err)); return
  end
  --[[ The bundle is the other player's word about both seats. Hold it to the
       same rules as a fresh duel: real seats, real classes, legal decks. ]]
  if (seat ~= 1 and seat ~= 2) or (first ~= 1 and first ~= 2) then
    s:Abort("rejoin", "the rejoin bundle named a seat that does not exist"); return
  end
  for i = 1, 2 do
    local pl = players[i]
    local ok, why = Session.ValidateRemoteDeck(pl.deck, pl.class)
    if ok and #pl.deck ~= ns.RULES.DECK_SIZE then ok, why = false, "a deck was not 30 cards" end
    if not ok then s:Abort("rejoin", "the rejoin bundle was not a legal duel: " .. tostring(why)); return end
  end
  local config = { seed = seed, first = first, players = players }
  local game, why = Session.Replay(config, log)
  if not game or (game:StateHash()) ~= hash then
    s:Abort("rejoin", "the rebuilt duel did not match theirs" .. (why and (": " .. why) or "")); return
  end
  s.challengeId = msg[10]
  -- anything held from the host's old stream belongs to a duel that is gone
  s.inbox.held, s.inbox.missing = {}, {}
  s.config, s.seed = config, seed
  s.myIndex, s.peerIndex = seat, 3 - seat
  s.challenger = seat == 1
  s.peer.class = players[3 - seat].class
  s.peer.heartbeat = true
  s.state = S.PLAYING
  s:AdoptGame(game, log, "START")
end

--- Send our deck. Chunked by the Outbox; 30 ids do not fit in one message.
function Session:SendDeck()
  if self.deckSent or not self.me.deck then return end
  self.deckSent = true
  self:Send(KIND.DECK, table.concat(self.me.deck, ";"))
end

--[[ Leave. Used by /fh concede's confirmation, by logout, and by the world
     interruption policy when a grace period expires. ]]
function Session:Leave(reason)
  if self.state == S.PLAYING then
    self:Concede()
  end
  self:Send(KIND.BYE, reason or "left")
  if self.state ~= S.OVER then self.state = S.IDLE end
end

return Session
