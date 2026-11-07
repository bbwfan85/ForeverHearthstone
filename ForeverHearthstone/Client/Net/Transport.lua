--[[ Client/Net/Transport.lua

  THE ONLY PART OF NETWORKING THAT TOUCHES WOW.

  Protocol.lua decides what the bytes mean and Session.lua decides what happens
  next. This file does one thing: get a string from here to there, and hand
  arriving strings to the session. It is deliberately thin, because everything
  in it is code that cannot be tested without a client -- so the less of it
  there is, the less of this project is untestable.

  MAINLINE, NOT CLASSIC (docs/07). C_ChatInfo.SendAddonMessage, not the removed
  global SendAddonMessage. The prefix must be registered or nothing arrives, and
  registration is per session, not per login-forever.

  ============================================================ THE THROTTLE

  WoW rate-limits addon messages, and a client that exceeds the limit does not
  get an error -- IT GETS SILENCE. Messages are simply dropped, which in a
  lockstep duel means the other player's board stops moving for no visible
  reason.

  So everything queues and drains on a ticker rather than going out inline. The
  budget below is deliberately conservative: a duel sends a handful of messages
  per turn, and the one time it sends a burst (the 30-card deck, four or five
  chunks) is during the handshake, where a quarter of a second is invisible.

  A dropped message is still survivable -- the sequence numbers and NAK in
  Protocol.lua exist for exactly that -- but recovering costs a round trip, and
  not tripping the throttle in the first place is free.

  =========================================================== ADDRESSING

  WHISPER to a character name. Cross-realm names arrive as "Name-Realm" and must
  be sent back the same way, so the sender string from CHAT_MSG_ADDON is used
  verbatim as the reply address rather than being cleaned up. Tidying it is how
  you build something that works everywhere except connected realms.
]]
local ADDON, ns = ...

local Transport = {}
ns.Transport = Transport

--[[ 16 characters is the cap. Distinctive enough not to collide with another
     addon, short enough that it does not eat the message budget -- the prefix
     is counted separately by the API but is part of the line the server sees. ]]
Transport.PREFIX = "FHDUEL"

--[[ Messages per drain, and how often to drain. 4 per 0.1s is 40/s, well inside
     the limit for whispers, and it clears a chunked deck in under 200ms. ]]
local PER_TICK = 4
local TICK     = 0.1

--[[ WOW'S OWN ALLOWANCE, which is far tighter than PER_TICK: each prefix gets
     a burst of about ten addon messages, refilled at about one a second. Past
     that, SendAddonMessage refuses the line (Enum.SendAddonMessageResult
     .AddonMessageThrottle) and it is simply gone -- this file used to ignore
     the answer, so a lost ACTION was only noticed when the NEXT message
     arrived, often the five-second PING, and an attack landed seconds late
     on the other screen.

     So a refused line now stays at the head of the queue and is tried again
     after THROTTLE_BACKOFF. The bucket below is only an ESTIMATE of that
     allowance and gates nothing but the volatile lines (what the opponent is
     pointing at): they go out only while there is VOLATILE_RESERVE to spare,
     so a hovered card can never spend the message a played card needs. ]]
Transport.BURST, Transport.REGEN = 10, 1
Transport.VOLATILE_RESERVE = 5
Transport.THROTTLE_BACKOFF = 0.5
Transport.MAX_RETRIES = 40      -- ~20 seconds of refusals, then the line is dropped

-- Older clients return boolean; current API returns an enum (all numbers are
-- truthy in Lua, including InvalidPrefix and MaxPrefixes).
function Transport.Registered(result)
  if type(result)=='boolean' then return result end
  local E=rawget(_G,'Enum') and Enum.RegisterAddonMessagePrefixResult
  if E then return result==E.Success or result==E.DuplicatePrefix end
  return result==0 or result==1
end

--[[ What SendAddonMessage's answer means. Mainline returns an
     Enum.SendAddonMessageResult (0 = sent); older clients a boolean. ]]
function Transport.Outcome(result)
  if result == nil or result == true or result == 0 then return "sent" end
  if result == false then return "throttled" end
  local E = rawget(_G, "Enum") and Enum.SendAddonMessageResult
  if E then
    if result == E.AddonMessageThrottle or result == E.ChannelThrottle then return "throttled" end
    if result == E.Success then return "sent" end
    return "failed"
  end
  if result == 3 or result == 8 then return "throttled" end
  return "failed"
end

function Transport.New(opts)
  opts = opts or {}
  local t = setmetatable({}, { __index = Transport })
  t.queue    = {}
  t.volatile = {}            -- kind -> newest volatile line; only the latest matters
  t.tokens   = Transport.BURST
  t.clock    = 0
  t.retries  = 0
  t.onMessage = opts.onMessage or function() end   -- (raw, sender)
  t.onError   = opts.onError   or function() end
  --[[ Called when handling a message raised a Lua error. A line from another
       player must never become an error pop-up on this one; the owner decides
       what to do with the duel (Main ends it). ]]
  t.onFault   = opts.onFault   or t.onError
  t.strangersWelcome = opts.strangersWelcome
  --[[ (raw, sender) -> true when a line from an address we are not talking to
       is the player we challenged answering from their real one (OnReceive). ]]
  t.claim = opts.claim
  t.onTick=opts.onTick
  t.peer      = nil          -- who we are talking to, verbatim from the wire
  t.sent, t.received, t.dropped = 0, 0, 0
  --[[ Messages we may still send before the next tick. Refilled by the ticker,
       spent by every send. Without a budget, "send the first one immediately so
       a single message does not wait" degenerates into "send everything
       immediately", because each send empties the queue again -- which is
       exactly the throttle trip this class exists to avoid. ]]
  t.budget = PER_TICK
  return t
end

--[[ Register the prefix and start listening. Separate from New so the object
     can exist before there is a WoW to talk to -- which is what lets a test
     construct one against the stub. ]]
function Transport:Start()
  if self.frame then return end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    --[[ If this fails, nothing will ever arrive and the failure is completely
         silent. It is worth saying so out loud rather than discovering it as
         "duels do not work". ]]
    local ok = C_ChatInfo.RegisterAddonMessagePrefix(Transport.PREFIX)
    if not Transport.Registered(ok) then
      self.onError("could not register the addon message prefix -- duels will not work")
    end
  end

  local f = CreateFrame("Frame")
  self.frame = f
  f:RegisterEvent("CHAT_MSG_ADDON")
  --[[ Not COMBAT_LOG_EVENT_UNFILTERED, which ERRORS ON REGISTRATION in Forever
       (docs/07). Nothing here needs it; the note is for whoever edits next. ]]
  f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
    if event ~= "CHAT_MSG_ADDON" then return end
    if prefix ~= Transport.PREFIX then return end
    self:OnReceive(text, sender)
  end)

  self.ticker = C_Timer.NewTicker(TICK, function() self:Tick() end)
end

function Transport:Stop()
  if self.ticker then self.ticker:Cancel(); self.ticker = nil end
  if self.frame then
    self.frame:UnregisterEvent("CHAT_MSG_ADDON")
    self.frame:SetScript("OnEvent", nil)
    self.frame = nil
  end
  self.queue = {}
  self.volatile = {}
  self.retries = 0
  self.holdUntil = nil
  self.peer = nil
  self.replies = {}
end

--[[ Point the transport at a character. The name is stored exactly as given --
     "Name-Realm" for a connected realm -- because that is the only form that
     addresses them reliably. ]]
function Transport:SetPeer(name)
  if self.peer~=name then self.queue={}; self.volatile={}; self.retries=0 end
  self.peer = name
end

--[[ A volatile line (sequence 0: Protocol's Outbox:SendVolatile) is state
     that the next one supersedes, so only the newest of each kind waits. ]]
local function volatileKind(raw)
  -- Sequence-free recovery requests are essential traffic, not hover updates.
  if raw:match('^0;NK;') then return nil end
  return raw:match("^0;(%w+)")
end

-- Terminal replies retain their destination after SetPeer clears a finished invitation.
function Transport:SendTo(raw, peer)
  self.replies = self.replies or {}
  self.replies[#self.replies + 1] = {raw=raw, peer=peer}
  if self.budget > 0 then self:Drain(1) end
  return true
end

--[[ Agreeing to end the duel (END_DUEL "yes") is the last thing this side
     says: the session ends at once, and that clears the peer and the queue.
     So the yes -- and every line still queued ahead of it, or it would wait
     behind a hole nobody will fill -- moves to the replies, which keep their
     destination. It stays sequenced: an unsequenced ED is not one 1.0.3 reads. ]]
local function agreesToEnd(raw)
  return raw:match("^%d+;ED;yes;") or raw:match("^%d+;ED;yes$")
end

function Transport:Send(raw)
  if raw:match("^%d+;BY;") and self.peer then return self:SendTo(raw:gsub("^%d+;", "0;"), self.peer) end
  if agreesToEnd(raw) and self.peer then
    self.replies = self.replies or {}
    for _, line in ipairs(self.queue) do self.replies[#self.replies + 1] = {raw=line, peer=self.peer} end
    self.queue = {}
    return self:SendTo(raw, self.peer)
  end
  if not self.peer then self.dropped = self.dropped + 1; return false end
  local kind = volatileKind(raw)
  if kind then
    self.volatile[kind] = raw
  else
    self.queue[#self.queue + 1] = raw
  end
  --[[ Spend from this tick's budget so a lone message -- a challenge, a
       concede -- does not wait for the ticker. A burst runs the budget out and
       the remainder paces. ]]
  if self.budget > 0 then self:Drain(1) end
  return true
end

--- One tick of the throttle: refill the budget, then send what it allows.
function Transport:Tick()
  self.clock = self.clock + TICK
  self.tokens = math.min(Transport.BURST, self.tokens + Transport.REGEN * TICK)
  self.budget = PER_TICK
  self:Drain(PER_TICK)
  if self.onTick then self.onTick(TICK) end
end

function Transport:Put(raw, peer)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "sent" end
  return Transport.Outcome(C_ChatInfo.SendAddonMessage(Transport.PREFIX, raw, "WHISPER", peer or self.peer))
end

function Transport:Drain(n)
  if self.holdUntil and self.clock < self.holdUntil then return end
  self.holdUntil = nil
  for _ = 1, (n or PER_TICK) do
    if self.budget <= 0 then return end
    local reply = self.replies and self.replies[1]
    local raw = reply and reply.raw or self.queue[1]
    if not raw then break end
    local outcome = self:Put(raw, reply and reply.peer)
    self.budget = self.budget - 1
    if outcome == "throttled" and self.retries < Transport.MAX_RETRIES then
      -- WoW's allowance is spent: keep the line and try it again shortly
      self.retries = self.retries + 1
      self.tokens = 0
      self.holdUntil = self.clock + Transport.THROTTLE_BACKOFF
      return
    end
    table.remove(reply and self.replies or self.queue, 1)
    self.retries = 0
    self.tokens = math.max(0, self.tokens - 1)
    if outcome == "sent" then self.sent = self.sent + 1 else self.dropped = self.dropped + 1 end
  end
  -- Volatile lines last, and only from the spare allowance.
  if #self.queue > 0 then return end
  for kind, raw in pairs(self.volatile) do
    if self.budget <= 0 or self.tokens < Transport.VOLATILE_RESERVE then return end
    self.volatile[kind] = nil
    local outcome = self:Put(raw)
    self.budget = self.budget - 1
    self.tokens = math.max(0, self.tokens - 1)
    if outcome == "sent" then self.sent = self.sent + 1 else self.dropped = self.dropped + 1 end
  end
end

--[[ Something arrived. Two filters before it reaches the session:

     1. it must be from the person we are duelling. Anything else is either a
        stranger's challenge or noise, and a lockstep stream must not accept
        actions from a third party.
     2. an unsolicited message from someone new is only allowed to be the START
        of a duel. Everything else from a stranger is discarded in silence. ]]
local function normalizedName(name)
  name=tostring(name or ""):lower():gsub("%s","")
  if not name:find("-",1,true) then
    local realm=GetNormalizedRealmName and GetNormalizedRealmName()
    if realm and realm~="" then name=name.."-"..realm:lower():gsub("%s","") end
  end
  return name
end
--- Do two names (either with or without a realm) name the same character?
function Transport.SameName(a, b)
  if a == nil or b == nil then return false end
  return normalizedName(a) == normalizedName(b)
end

function Transport:Deliver(raw, sender, fromStranger)
  local ok, err = pcall(self.onMessage, raw, sender, fromStranger)
  if not ok then
    self.faults = (self.faults or 0) + 1
    self.onFault(tostring(err), sender)
  end
end

function Transport:OnReceive(raw, sender)
  self.received = self.received + 1
  if self.peer and normalizedName(sender) == normalizedName(self.peer) then
    self:Deliver(raw, sender)
    return
  end
  if not self.peer or (self.strangersWelcome and self.strangersWelcome()) then
    self:Deliver(raw, sender, true)   -- `true`: from someone we are not yet talking to
    return
  end
  --[[ The address a challenge went to need not be the one the answer comes
       from: Forever's UnitName gives a first and last name, and "First-Last"
       reaches them but their replies arrive as their real address. Once the
       owner recognises the player, that address is the peer from then on. ]]
  local claimed = self.claim and self.claim(raw, sender)
  if claimed then
    if claimed ~= "deliver" then self.peer = sender end   -- "deliver": heard, not re-addressed
    self:Deliver(raw, sender)
    return
  end
  self.dropped = self.dropped + 1
end

-- ======================================================== the duel gate

--[[ PROXIMITY. The brief's rule is that a duel happens between two people
     sitting near each other in the world, and proximity is the half of that a
     computer can actually check.

     CheckInteractDistance(unit, 2) is trade range, roughly 11 yards -- close
     enough that the two players are visibly together, far enough that they do
     not have to stand inside each other. It works on strangers, which matters:
     the people this feature is for are not in your group.

     UnitDistanceSquared is the fallback, and it is a fallback rather than the
     primary because it is restricted in instances and returns a second value
     saying whether it could answer at all.

     UNVERIFIED ON FOREVER. Both calls exist on Mainline, and the probe checks
     them; until someone runs it on the beta this is the best available guess
     rather than a fact. The failure is graceful either way -- if neither call
     can answer, the gate opens and the players police it themselves, which is
     the same honour system the rest of the duel runs on. ]]
Transport.DUEL_RANGE_YARDS = 11

-- a secret answer (inside instances) reads as no answer -- ns.Plain, Rewards.lua
local function plain(v)
  if ns.Plain then return ns.Plain(v) end
  return v
end

function Transport.InRange(unit)
  unit = unit or "target"
  if not UnitExists(unit) then return false, "target a player standing next to you first, or /fh duel Name" end
  --[[ A SECRET answer (inside instances) is no answer: only a plain false
       refuses. Treating secret as "no" made two players standing together in
       a dungeon unable to duel at all. ]]
  local isSecret = rawget(_G, "issecretvalue") or function() return false end
  local isPlayer = UnitIsPlayer(unit)
  if not isSecret(isPlayer) and not isPlayer then return false, "that is not a player" end

  if CheckInteractDistance then
    local ok = CheckInteractDistance(unit, 2)     -- 2 = trade range
    if not isSecret(ok) then
      if ok then return true end
      return false, "too far away to sit down together"
    end
  end

  if UnitDistanceSquared then
    local d2, valid = UnitDistanceSquared(unit)
    d2, valid = plain(d2), plain(valid)
    if valid and d2 then
      local r = Transport.DUEL_RANGE_YARDS
      if d2 <= r * r then return true end
      return false, "too far away to sit down together"
    end
  end

  --[[ Nothing could answer. Open the gate rather than refusing a duel the
       players can see is legitimate -- a range check that fails closed on an
       API that is merely unavailable is a feature that appears broken. ]]
  return true, nil, "unverified"
end

--[[ SITTING. There is no IsSitting() on Mainline -- the probe looks for one and
     nothing in the API surface reports a character's sit state, own or other.

     So this is NOT enforced, and pretending otherwise would mean inventing a
     check that silently always passes. It is a prompt instead: both players are
     told to sit, and whether they do is between them. That is the honest
     version of a rule the platform cannot see, and it costs nothing -- people
     who have gone to the trouble of standing next to each other to play cards
     are not the population that needs enforcing. ]]
Transport.SIT_PROMPT = "sit down with them: /sit -- it is the table, not a rule the addon can check"

return Transport
