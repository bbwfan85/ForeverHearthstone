--[[ Client/Net/Protocol.lua

  THE WIRE FORMAT. Bytes in, tables out, and nothing else.

  NO WoW API IN THIS FILE. It is pure string work, so every framing decision --
  chunking, sequence numbers, the version handshake, what a malformed message
  does -- is tested headless. Client/Net/Transport.lua is the thin part that
  actually calls C_ChatInfo.SendAddonMessage.

  THE CONSTRAINT THAT SHAPES EVERYTHING HERE

  A WoW addon message carries at most 255 bytes, and the client is free to drop
  messages when the chat throttle is saturated. So the format has to be compact,
  it has to survive being split, and it has to notice a hole rather than apply
  half a turn. Three mechanisms, in order of importance:

    1. SEQUENCE NUMBERS on every message. The receiver tracks what it expects.
       A later message arriving early is HELD, not applied -- in lockstep,
       applying action 7 before action 6 is not "slightly wrong", it is a
       different game.
    2. NAK + RESEND. The sender keeps a short history; a receiver that sees a
       hole asks for the missing sequence numbers by number.
    3. CHUNKING. A body too long for one message is split, and the pieces are
       reassembled before the message is delivered upward. Only the deck list
       actually needs it today (30 card ids is ~270 bytes), but a format that
       cannot grow past 255 bytes is a format that has to be replaced later.

  THE VERSION HANDSHAKE HAS ONE JOB: FAIL CLEARLY

  Two players will eventually sit down with different addon versions, and the
  failure mode must not be a desync twenty turns in. So:

    * HELLO's first three fields are FROZEN FOREVER: protocol, addon version,
      class. A future version may append fields; an old client ignores extras
      rather than failing to parse. That is what makes "your opponent has a
      newer version" a sentence we can say instead of a Lua error.
    * A protocol mismatch is refused at handshake, by both sides, with the two
      version numbers named. Nobody has committed anything at that point.

  ENCODING

      <seq>;<kind>;<field>;<field>...

  Semicolon-separated because no card id, class name or number contains one.
  Player names cannot contain one either (WoW forbids punctuation in names; the
  realm suffix uses '-'). A field that somehow does is REJECTED at encode time
  rather than silently producing a message that parses as something else.
]]
local ADDON, ns = ...

local Protocol = {}
ns.Protocol = Protocol

--[[ Bump ONLY for a change that would make two clients disagree about the
     meaning of a message. Adding a new optional field to the end of a body does
     not qualify; changing field order, or what an existing kind does, does. ]]
-- 2: decks are covered by the seed commitment, per-action hashes, resync and
--    rejoin (docs/13). A version-1 client is told plainly to update.
-- 3: HELLO says whether it is a challenge or an answer, and an ACTION carries
--    its own fingerprint instead of a separate ACTION_HASH from both sides
--    (docs/27). A version-2 client would start the wrong game on crossed
--    challenges and never compare fingerprints, so it is refused.
-- 4: the inbox refuses sequence numbers far ahead of the stream, a NAK names
--    at most MAX_NAK messages, and a win claimed while this side is still
--    playing ends the duel without a result (docs/29). A version-3 client can
--    be told apart but would not agree about claims, so it is refused.
-- 5: the rules changed under lockstep (docs/30: a stealthed minion that deals
--    damage is revealed). Both sides run the engine, so a version-4 client
--    would play a different game and desync; it is refused and told to update.
-- 6: the 0.1.3 rules review (docs/32): Silence, secrets that stop an action,
--    set effects under auras, deaths before "after you cast", and some
--    twenty card fixes. A version-5 client would desync; it is refused.
-- 7: the Fireplace oracle rulings (docs/33): Freeze thawing, Silence keeping
--    Health, Lightspawn, copies taking damage, cost order, Redemption, death
--    reaction order, summon placement, Kezan Mystic. A version-6 client would
--    desync; it is refused.
-- 8: resend requests bypass ordered gaps, including simultaneous packet loss.
Protocol.VERSION = 10

--[[ The addon's own version, reported in HELLO so a mismatch can be described
     to the player ("they are on 0.2.0, you are on 0.1.0") even when the
     protocol number happens to agree. ]]
Protocol.ADDON_VERSION = "0.2.4"   -- replaced from the .toc at load (Main.lua)

--[[ 255 is the hard cap on an addon message. The margin covers the chunk header
     and leaves room for the prefix and channel bookkeeping the client adds, so
     a message that is legal here is legal on the wire. Deliberately measured in
     BYTES, not characters -- a UTF-8 player name is not one byte per glyph. ]]
Protocol.MAX_MESSAGE = 240
Protocol.MAX_BODY    = 200     -- after the seq/kind header and chunk overhead

--[[ How many sent messages to keep for resends. A NAK can only ever ask for
     something inside this window; older than that is unrecoverable and must
     abort the match rather than guess. 64 is far more than a turn's worth of
     actions, and the whole history is at most ~16 KB. ]]
Protocol.HISTORY = 64

--[[ How far past the next expected message an arrival may be. The sender keeps
     only HISTORY messages for resends, so anything further ahead could never
     have its hole filled -- and without a bound a single hostile line such as
     "1e6;HI" would make the inbox list a million missing numbers. ]]
Protocol.WINDOW  = 256
Protocol.MAX_SEQ = 2147483647
Protocol.MAX_NAK = 32          -- sequence numbers named in one NAK

Protocol.KIND = {
  HELLO   = "HI",   -- protocol + addon version + class + name
  COMMIT  = "CM",   -- hash of my seed nonce
  REVEAL  = "RV",   -- my seed nonce
  DECK    = "DK",   -- my 30 card ids (chunked)
  ACTION  = "AC",   -- a game action
  HASH    = "HS",   -- state fingerprint at a turn boundary
  EMOTE   = "EM",
  PING    = "PI",   -- negotiated liveness check
  PROFILE = "PR",   -- actual WoW level and character GUID
  PAUSE   = "PS",   -- world interruption: I am not at the table
  RESUME  = "RS",
  BYE     = "BY",   -- leaving, with a reason
  NAK     = "NK",   -- resend these sequence numbers
  CHUNK   = "CK",   -- part of a longer message
  END_DUEL = "ED", -- mutual end: ask / yes / no, scoped to challenge
  REMATCH = "RM",   -- after the game: ask / yes / no / ready (Session:AskRematch)
  -- VOLATILE kinds (sent at sequence 0, see Outbox:SendVolatile): never
  -- resent, never ordered, never part of lockstep. Losing one costs nothing.
  ACTION_HASH = "AH",  -- fingerprint after action N (desync caught at the action)
  RESYNC_REQ  = "RQ",  -- "we disagree: send me your log" (to the challenger)
  RESYNC_LOG  = "RL",  -- the challenger's action log, authoritative (chunked)
  REJOIN_BUNDLE = "RB", -- everything a returning player needs to rebuild the game
  HOVER   = "HV",   -- the card I am holding up / what I am aiming at
  POSITION = "XY", -- challenger position while the invitation is open
  REJOIN  = "RJ",   -- "your duel with me is still open" (offered after silence)
  REJOIN_ACCEPT = "RA", -- "I am back; send the bundle"
  STATUS  = "ST",   -- am I at the table: position, dead, in combat (docs/13)
}
Protocol.VOLATILE = { PI = true, BY = true, HV = true, XY = true, ST = true, RJ = true, RA = true, NK = true }

-- ============================================================ encode / decode

local SEP = ";"

--[[ A field that contains the separator would decode as two fields, which is
     the classic way a protocol quietly produces a message that means something
     else. Caught at ENCODE time, where the bug actually is. ]]
local function checkField(v)
  local s = tostring(v)
  if s:find(SEP, 1, true) then
    error("Protocol: field contains the separator: " .. s, 3)
  end
  return s
end

--- Encode one message. `seq` is the sender's sequence number.
function Protocol.Encode(seq, kind, ...)
  local parts = { checkField(seq), checkField(kind) }
  local n = select("#", ...)
  for i = 1, n do
    local v = select(i, ...)
    --[[ nil in the middle of a field list is how an optional argument arrives.
         It encodes as empty, so field POSITIONS never shift -- a body whose
         meaning depends on how many fields it has cannot be extended later. ]]
    parts[#parts + 1] = (v == nil) and "" or checkField(v)
  end
  return table.concat(parts, SEP)
end

--[[ Decode one message into { seq, kind, [1..n] = fields }.

     Returns nil plus a reason for anything malformed. A garbled message is
     EXPECTED -- other addons share the channel, players run old versions, the
     client truncates -- so this never errors. ]]
function Protocol.Decode(raw)
  if type(raw) ~= "string" or raw == "" then return nil, "empty" end
  local fields = {}
  -- collect fields including trailing empties, which a plain gmatch drops
  local pos = 1
  while true do
    local i = raw:find(SEP, pos, true)
    if not i then fields[#fields + 1] = raw:sub(pos); break end
    fields[#fields + 1] = raw:sub(pos, i - 1)
    pos = i + 1
  end
  if #fields < 2 then return nil, "too few fields" end

  local seq = tonumber(fields[1])
  -- the upper bound also refuses inf and 1e300, which tonumber accepts
  if not seq or seq < 0 or seq > Protocol.MAX_SEQ or seq ~= math.floor(seq) then
    return nil, "bad sequence"
  end
  local kind = fields[2]
  if kind == "" then return nil, "no kind" end

  --[[ The raw line is kept because one message cannot be reconstructed from its
       decoded fields: a CHUNK's fragment is an arbitrary slice of another
       message and contains separators of its own. Splitting it and rejoining
       would lose empty fields at the seam. So chunk reassembly reads the raw
       string past a fixed number of separators instead -- see Collect. ]]
  local msg = { seq = seq, kind = kind, raw = raw }
  for i = 3, #fields do
    local f = fields[i]
    msg[i - 2] = (f ~= "") and f or nil
    msg.n = i - 2
  end
  msg.n = msg.n or 0
  return msg
end

--- Field `i` as a number, or `default`. Every numeric field goes through this,
--- so a corrupt "12x" becomes the default instead of a nil arithmetic error.
function Protocol.Num(msg, i, default)
  local v = msg and msg[i]
  local n = v and tonumber(v)
  if not n then return default end
  return n
end

-- ================================================================== chunking

--[[ Split a too-long message body into wire-sized pieces.

     A chunk is:  <seq>;CK;<groupId>;<index>;<count>;<fragment>

     The group id is the sequence number of the FIRST chunk, which is already
     unique and already known to both sides, so nothing has to allocate ids.
     Each chunk carries its own sequence number, so the ordinary hole detection
     covers a lost fragment without any special case. ]]
function Protocol.Split(seq, kind, body)
  body = body or ""
  --[[ The body is ALREADY a joined field list, so it legitimately contains
       separators and must not go through checkField -- that guard is for a
       single field. The header is built by hand for the same reason. ]]
  local function raw(...)
    return table.concat({ ... }, SEP)
  end
  local whole = raw(seq, kind, body)
  if #whole <= Protocol.MAX_MESSAGE then return { whole }, 1 end

  --[[ Size the fragment from the WORST-CASE header rather than the first one:
       the last chunk's sequence number has more digits than the first, and a
       fragment sized against the first header would overflow at the end of a
       long split. That is a bug that only shows up on long decks. ]]
  local groupId = seq
  local est = math.ceil(#body / 150) + 1
  local headerCost = #raw(seq + est, Protocol.KIND.CHUNK, groupId, est, est, "")
  local room = Protocol.MAX_MESSAGE - headerCost
  if room < 16 then room = 16 end

  --[[ What gets fragmented is KIND AND BODY TOGETHER. Fragmenting the body
       alone would leave the chunks with no record of what message they belong
       to, and the reassembled string would decode as a message whose kind was
       whatever its first field happened to be. ]]
  local payload = kind .. SEP .. body
  local frags = {}
  local i = 1
  while i <= #payload do
    frags[#frags + 1] = payload:sub(i, i + room - 1)
    i = i + room
  end

  local out = {}
  for idx, frag in ipairs(frags) do
    out[idx] = raw(seq + idx - 1, Protocol.KIND.CHUNK, groupId, idx, #frags, frag)
  end
  return out, #frags
end

--[[ Feed a decoded CHUNK message in. Returns the reassembled body once the last
     piece arrives, nil while it is still incomplete.

     `state` is a plain table owned by the caller (one per peer). Partial groups
     live there until they complete; an abandoned group is dropped when the
     session ends, which is the only lifetime that matters -- a half-received
     deck is worthless a second later anyway. ]]
function Protocol.Collect(state, msg)
  local group = tonumber(msg[1])
  local index = tonumber(msg[2])
  local count = tonumber(msg[3])
  if not (group and index and count) then return nil, "bad chunk header" end

  --[[ The fragment is everything past the fifth separator of the RAW line
       (seq;CK;group;index;count;<fragment>). Taking it from the decoded fields
       instead would truncate any fragment that happens to contain a separator,
       which is most of them. ]]
  local frag = ""
  if msg.raw then
    local pos = 1
    for _ = 1, 5 do
      local i = msg.raw:find(SEP, pos, true)
      if not i then return nil, "truncated chunk" end
      pos = i + 1
    end
    frag = msg.raw:sub(pos)
  end
  if index < 1 or index > count or count > 64 then return nil, "chunk out of range" end

  state.groups = state.groups or {}
  local g = state.groups[group]
  if not g then g = { count = count, have = 0, parts = {} }; state.groups[group] = g end
  if g.count ~= count then return nil, "chunk count changed mid-group" end
  if g.parts[index] then return nil end          -- duplicate, already have it
  g.parts[index] = frag
  g.have = g.have + 1
  if g.have < g.count then return nil end

  state.groups[group] = nil
  return table.concat(g.parts)
end

-- ============================================================ commit / reveal

--[[ The same djb2 the engine uses for its state hash and seed derivation.

     This is NOT cryptography and does not pretend to be: a determined opponent
     could brute-force a nonce with a chosen hash. It exists to stop the trivial
     cheat -- seeing the other player's nonce and then picking one that gives
     you the draws you want -- which is the only one that matters between two
     people who chose to sit down together. The honour system covers the rest,
     exactly as the brief says. ]]
--[[ A stronger fingerprint for the seed commitment: two independent 31-bit
     lanes (djb2 and sdbm), 62 bits in all, as hex. Still not cryptography --
     nothing in pure Lua 5.1 without a bit library is -- but brute-forcing a
     nonce AND deck against 62 bits is no longer a lunchtime job. ]]
function Protocol.Hash2(s)
  s = tostring(s)
  local a, b = 5381, 0
  for i = 1, #s do
    local c = s:byte(i)
    a = (a * 33 + c) % 2147483648
    b = (c + b * 65599) % 2147483648
  end
  return ("%08x%08x"):format(a, b)
end

function Protocol.Hash(s)
  s = tostring(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483648 end
  return h
end

-- ========================================================= action encoding

--[[ An action is the smallest thing that can cross the wire and still name a
     game event exactly. Targets are INSTANCE IDS, not board positions, because
     a position means something different the moment either board changes -- and
     instance ids agree on both clients for free: both build the same game from
     the same seed, so Entity.New hands out the same ids in the same order.

     Every numeric field encodes as 0 when absent, so the field count never
     changes and an older decoder cannot mis-align. ]]
local ACTION_VERB = {
  PLAY_CARD  = "P",
  ATTACK     = "A",
  HERO_POWER = "H",
  CHOICE     = "C",
  END_TURN   = "E",
  CONCEDE    = "X",
  MULLIGAN   = "M",
}
Protocol.ACTION_VERB = ACTION_VERB

local VERB_ACTION = {}
for k, v in pairs(ACTION_VERB) do VERB_ACTION[v] = k end
Protocol.VERB_ACTION = VERB_ACTION

--- Turn an action table into the body of an ACTION message.
function Protocol.EncodeAction(a)
  local verb = ACTION_VERB[a and a.kind]
  if not verb then return nil, "unknown action " .. tostring(a and a.kind) end
  if verb == "P" then
    return table.concat({ verb, a.handIndex or 0, a.position or 0,
                          a.mode or 0, a.targetId or 0 }, SEP)
  elseif verb == "A" then
    return table.concat({ verb, a.attackerId or 0, a.targetId or 0 }, SEP)
  elseif verb == "H" then
    return table.concat({ verb, a.targetId or 0 }, SEP)
  elseif verb == "C" then
    return table.concat({ verb, a.index or 0 }, SEP)
  elseif verb == "M" then
    --[[ The thrown-back card indices, comma-separated inside ONE field. A
         separator-joined list would make the body a variable number of fields,
         and a body whose length carries meaning cannot be extended later. ]]
    return table.concat({ verb, table.concat(a.indices or {}, ",") }, SEP)
  end
  return verb
end

--[[ Decode an ACTION message's fields back into an action table. `msg` is the
     decoded message; fields start at 1.

     A zero decodes back to nil rather than 0, because "no target" and "the
     entity with instance id 0" must not be the same thing downstream. ]]
function Protocol.DecodeAction(msg)
  local verb = msg and msg[1]
  local kind = verb and VERB_ACTION[verb]
  if not kind then return nil, "unknown verb " .. tostring(verb) end
  local function n(i)
    local v = Protocol.Num(msg, i, 0)
    if v == 0 then return nil end
    return v
  end
  if kind == "PLAY_CARD" then
    return { kind = kind, handIndex = n(2), position = n(3),
             mode = n(4), targetId = n(5) }
  elseif kind == "ATTACK" then
    return { kind = kind, attackerId = n(2), targetId = n(3) }
  elseif kind == "HERO_POWER" then
    return { kind = kind, targetId = n(2) }
  elseif kind == "CHOICE" then
    return { kind = kind, index = n(2) }
  elseif kind == "MULLIGAN" then
    local indices = {}
    for d in tostring(msg[2] or ""):gmatch("%d+") do
      indices[#indices + 1] = tonumber(d)
    end
    return { kind = kind, indices = indices }
  end
  return { kind = kind }
end

-- ============================================================ version policy

--[[ Is a peer's protocol number one we can play against, and if not, what does
     the player need to be told?

     Returns ok, reason, advice. The ADVICE is the point: "incompatible" on its
     own sends two people to a forum, while "they are on a newer version" tells
     whoever is behind exactly what to do. ]]
function Protocol.CheckVersion(theirProtocol, theirAddon)
  local mine = Protocol.VERSION
  local theirs = tonumber(theirProtocol)
  if not theirs then
    return false, "unreadable", "their addon did not identify itself -- it may not be this addon at all"
  end
  if theirs == mine then return true end
  if theirs > mine then
    return false, "older", ("your Forever Hearthstone is out of date (protocol %d, theirs %d%s) -- update to duel them")
      :format(mine, theirs, theirAddon and (", their version " .. tostring(theirAddon)) or "")
  end
  return false, "newer", ("their Forever Hearthstone is out of date (protocol %d, yours %d%s) -- they need to update")
    :format(theirs, mine, theirAddon and (", their version " .. tostring(theirAddon)) or "")
end

-- ================================================================== outbox

--[[ The send side: sequence numbering plus the resend history, kept here rather
     than in Session so that the retransmit rule is tested on its own.

     `send` is whatever actually puts a string on the wire. It is injected, so
     the tests drive a table and the game drives C_ChatInfo. ]]
local Outbox = {}
Outbox.__index = Outbox
Protocol.Outbox = Outbox

function Outbox.New(send)
  return setmetatable({ send = send, seq = 0, history = {}, sent = 0 }, Outbox)
end

function Outbox:Next() self.seq = self.seq + 1; return self.seq end

--[[ Send a message, splitting it if it is too long. Returns the sequence
     numbers used, so a caller can assert on the framing. ]]
function Outbox:Send(kind, ...)
  local body = table.concat({ ... }, SEP)   -- already-encoded fields
  local seq = self:Next()
  local parts = Protocol.Split(seq, kind, body)
  -- a split consumed extra sequence numbers; account for them
  self.seq = seq + #parts - 1
  local used = {}
  for i, raw in ipairs(parts) do
    local s = seq + i - 1
    used[i] = s
    self.history[s] = raw
    self.history[s - Protocol.HISTORY] = nil
    self.sent = self.sent + 1
    self.send(raw)
  end
  return used
end

--[[ A VOLATILE message: sequence 0, not kept for resends and not counted, so
     it can never open a hole in the ordered stream. For state that is
     superseded by the next message anyway (what the opponent is pointing at,
     where they are standing). Must fit one message; never chunked. ]]
function Outbox:SendVolatile(kind, ...)
  local raw = Protocol.Encode(0, kind, ...)
  if #raw > Protocol.MAX_MESSAGE then return false end
  self.send(raw)
  return true
end

--[[ Resend the named sequence numbers. Anything already dropped from the
     history is reported, because the caller must then abort the match: a hole
     in a lockstep action stream cannot be papered over. ]]
function Outbox:Resend(seqs)
  local lost = {}
  for _, s in ipairs(seqs) do
    local raw = self.history[s]
    if raw then self.send(raw) else lost[#lost + 1] = s end
  end
  return (#lost == 0), lost
end

-- ================================================================== inbox

--[[ The receive side: ordering, hole detection and chunk reassembly.

     Messages are delivered to the caller IN ORDER and exactly once. Everything
     else -- duplicates from a resend, a message from the future, a fragment --
     is absorbed here. ]]
local Inbox = {}
Inbox.__index = Inbox
Protocol.Inbox = Inbox

function Inbox.New()
  return setmetatable({ expected = 1, held = {}, chunks = {}, missing = {} }, Inbox)
end

--[[ Feed a raw wire string in. Returns a list of decoded messages that are now
     ready, in order, and a list of sequence numbers to NAK. A third and fourth
     value report a message that was refused, and whether that refusal is fatal
     to the stream (a chunk group that can never complete).

     The NAK list is returned rather than sent, because deciding to ask again is
     a session-level policy (how often, how many times before giving up) and
     this file does not own policy. ]]
function Inbox:Receive(raw)
  local msg, why = Protocol.Decode(raw)
  if not msg then return {}, {}, why end

  -- a volatile message is delivered at once and never affects ordering
  if msg.seq == 0 and Protocol.VOLATILE[msg.kind] then return { msg }, {} end
  if msg.seq < self.expected then return {}, {} end      -- duplicate
  if msg.seq >= self.expected + Protocol.WINDOW then return {}, {}, "too far ahead" end
  self.held[msg.seq] = msg

  local ready = {}
  while self.held[self.expected] do
    local m = self.held[self.expected]
    self.held[self.expected] = nil
    self.expected = self.expected + 1

    if m.kind == Protocol.KIND.CHUNK then
      local body, bad = Protocol.Collect(self.chunks, m)
      --[[ A malformed or oversized group can never complete, and the message it
           carried is gone for good. Say so, so the session can end the match
           instead of waiting forever for it. ]]
      if bad then return ready, {}, bad, true end
      if body then
        --[[ A reassembled group decodes as an ordinary message. Its own
             sequence number is meaningless by then -- ordering was already
             decided by the chunks -- so it is re-encoded at seq 0 and the
             KIND carries the meaning, exactly as for a short message. ]]
        local inner = Protocol.Decode("0" .. SEP .. body)
        if inner then ready[#ready + 1] = inner end
      end
    else
      ready[#ready + 1] = m
    end
  end

  --[[ Anything still held is sitting behind a hole. Ask for the hole, not for
       everything -- a NAK storm is how a laggy connection becomes a dead one. ]]
  local nak = {}
  local highest = self.expected - 1
  for s in pairs(self.held) do if s > highest then highest = s end end
  for s = self.expected, highest do
    if not self.held[s] then
      nak[#nak + 1] = s
      if #nak >= Protocol.MAX_NAK then break end
    end
  end
  return ready, nak
end

return Protocol
