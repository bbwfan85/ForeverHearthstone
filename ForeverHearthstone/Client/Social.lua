--[[ Client/Social.lua

  WHO ELSE IS PLAYING: the players near you, and your guild's ladder.

  Until this file the addon could only talk to one named player at a time (a
  whisper, Client/Net/Transport.lua), so nobody could tell that the stranger
  riding past had it installed. Two things fix that, and both live here as
  plain data with no WoW in them -- the clock, every position and every roll
  are passed in, so all of it runs headless (tests/test_social.lua). The frames
  and the wire are Client/UI/Social.lua.

  ============================================================== NEARBY

  Each client says a short line -- a "card": who I am, my class, my rank and
  roughly where I stand -- on a RANGE-LIMITED distribution (YELL, else SAY), so
  the server itself decides who is near enough to hear it and nothing is
  announced realm-wide. Its own prefix, FHNEAR: clients before this never
  registered it and never see a byte, and it has its own throttle allowance,
  so a beacon can never spend a message a duel needs.

    * One beacon about every 45s while travelling (sooner after 40 yards),
      90s standing still, slower in a crowd.
    * Hearing a NEW player is answered with one beacon a moment later, so two
      riders passing each other both learn of it inside a few seconds.
    * A player is forgotten 200s after they were last heard.

  WHETHER THE CLIENT ALLOWS IT IS NOT KNOWN IN ADVANCE (retail restricts
  SAY/YELL addon messages to instances; Forever is untested), so the code
  finds out for itself: a beacon that is refused, or that we never hear come
  back, moves YELL -> SAY -> "silent", and "silent" turns on the GLANCE
  fallback -- one quiet whisper ("Q") to a player you mouse over or target,
  answered ("A") only by clients that have this. /fh nearby says which.

  ============================================================== THE POP-UP

  Like a pack drop: when someone comes within POPUP_RANGE, a small panel names
  them (the three most recent, then "and N more") with a button to duel. Each
  player is announced once per ANNOUNCE_COOLDOWN, pop-ups keep POPUP_GAP
  apart, and none appears while you are busy (combat, a match, opening packs)
  -- those wait rather than being lost, unless the player has gone by then.

  ============================================================== THE GUILD

  A line on the GUILD distribution ("G": class, rank, stars, record) when asked
  ("R"), kept in saved variables so members who are offline still show at the
  rank they last reported. Self-reported: a friendly board, not a verified one.
]]
local ADDON, ns = ...

local Social = {}
ns.Social = Social

Social.PREFIX  = "FHNEAR"
Social.VERSION = 1

Social.BEACON_MOVING   = 45     -- seconds between beacons while travelling
Social.BEACON_STILL    = 90     -- ... while standing in one place
Social.BEACON_FLOOR    = 15     -- never sooner than this, however far you rode
Social.MOVE_YARDS      = 40     -- this far from the last beacon earns a new one
Social.STILL_YARDS     = 5
Social.CROWD           = 5      -- this many known players doubles the interval
Social.EXPIRE          = 200    -- forget a player this long after their last word
Social.GLANCE_EXPIRE   = 180    -- a glanced player sends no beacons to renew them
Social.REPLY_COOLDOWN  = 60     -- one answering beacon per new player per minute
Social.ECHO_WAIT       = 4      -- our own beacon comes back within this, or did not
Social.ECHO_MISSES     = 2      -- unheard beacons before trying the next channel
Social.REPROBE         = 600    -- a refused channel is tried again this often
--[[ YELL and SAY reach only players in earshot. CHANNEL is the addon's own
     chat channel for the zone you are in ("FHN<map>", joined only if the first
     two are refused -- as they are on Forever, 2026-11-27): everyone in the
     zone hears it, and each client keeps only those within LIST_RANGE. ]]
Social.CHANNELS        = { "YELL", "SAY", "CHANNEL" }
Social.LIST_RANGE      = 300    -- yards: "nearby", for players heard zone-wide

Social.POPUP_RANGE       = 80     -- yards: near enough to be worth saying
Social.POPUP_GAP         = 120    -- seconds between two pop-ups
Social.ANNOUNCE_COOLDOWN = 1200   -- one announcement per player per 20 minutes
Social.POPUP_ROWS        = 3
Social.DUEL_RANGE        = 14     -- Transport's 11 yards and a little for a stale fix
Social.KNOCK_COOLDOWN    = 30
Social.GLANCE_COOLDOWN   = 1800   -- ask a given player once per half hour
Social.GLANCE_GAP        = 3      -- and at most one question every few seconds

Social.GUILD_KEEP_DAYS   = 60
Social.GUILD_MAX         = 300
Social.GUILD_ONLINE      = 900    -- heard this recently: shown as online

local KINDS = { B = true, Q = true, A = true, K = true, G = true, R = true }
Social.KIND = { BEACON = "B", QUERY = "Q", ANSWER = "A", KNOCK = "K", GUILD = "G", ROSTER = "R" }

-- ================================================================ the wire

local function int(v, lo, hi)
  local n = tonumber(v)
  if not n or n ~= n then return nil end
  n = math.floor(n + 0.5)
  if n < lo or n > hi then return nil end
  return n
end

local function knownClass(c)
  return type(c) == "string" and ns.HERO_ID_BY_CLASS ~= nil and ns.HERO_ID_BY_CLASS[c] ~= nil
end

local function cleanGuid(g)
  if type(g) ~= "string" or g == "" or #g > 48 or g:find("[^%w%-]") then return nil end
  return g
end

--- "B;1;<guid>;MAGE;12;;-8913;563;0" -- every field a number or a token.
function Social.Encode(kind, ...)
  local parts = { kind, tostring(Social.VERSION) }
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    parts[#parts + 1] = v == nil and "" or tostring(v)
  end
  return table.concat(parts, ";")
end

--[[ A card: what B, Q and A all carry. `me` = { guid, class, rank, legend },
     `here` = { x, y, instance } or nil (no fix, or deliberately withheld). ]]
function Social.Card(kind, me, here)
  return Social.Encode(kind, me.guid or "", me.class or "", me.rank or 25, me.legend or "",
    here and math.floor(here.x + 0.5) or "", here and math.floor(here.y + 0.5) or "",
    here and here.instance or "", me.layer or "")
end

function Social.GuildLine(me)
  return Social.Encode("G", me.guid or "", me.class or "", me.rank or 25, me.stars or 0,
    me.legend or "", me.wins or 0, me.losses or 0)
end

--[[ A line from another player's client, so nothing in it is trusted: unknown
     kinds, a future version, a class this game does not have or a rank off the
     ladder all read as "no message". ]]
function Social.Decode(raw)
  if type(raw) ~= "string" or #raw > 200 then return nil end
  local f = {}
  for field in (raw .. ";"):gmatch("([^;]*);") do f[#f + 1] = field end
  local kind = f[1]
  if not KINDS[kind] then return nil end
  if tonumber(f[2]) ~= Social.VERSION then return nil end
  local m = { kind = kind }
  if kind == "R" then return m end
  m.guid = cleanGuid(f[3])
  if kind == "K" then return m end
  if not knownClass(f[4]) then return nil end
  m.class = f[4]
  m.rank = int(f[5], 0, 25)
  if not m.rank then return nil end
  if kind == "G" then
    m.stars = int(f[6], 0, 5) or 0
    m.legend = m.rank == 0 and int(f[7], 1, 9999999) or nil
    m.wins = int(f[8], 0, 9999999) or 0
    m.losses = int(f[9], 0, 9999999) or 0
    return m
  end
  m.legend = m.rank == 0 and int(f[6], 1, 9999999) or nil
  local x, y, inst = int(f[7], -1e7, 1e7), int(f[8], -1e7, 1e7), int(f[9], -1e7, 1e7)
  if x and y and inst then m.x, m.y, m.instance = x, y, inst end
  -- which copy ("layer") of the zone they are on, when their client can tell
  if type(f[10]) == "string" and f[10] ~= "" and #f[10] <= 16 and not f[10]:find("[^%w]") then
    m.layer = f[10]
  end
  return m
end

-- ================================================================== nearby

local function keyOf(sender, guid)
  return guid or ("name:" .. tostring(sender or ""):lower())
end

function Social.New()
  local s = setmetatable({}, { __index = Social })
  s.nearby = {}        -- key -> entry
  s.count = 0
  s.announced = {}     -- key -> when their pop-up was shown
  s.replied = {}       -- key -> when we last answered their arrival
  s.asked = {}         -- guid -> when we last glanced at them
  s.knocks = {}        -- key -> when they last knocked / we last knocked
  s.channelIndex = 1
  s.dead, s.deaf = {}, {}   -- distribution -> when it was found refused / unheard
  s.broadcast = "unknown"   -- unknown | ok | silent | refused
  s.misses = 0
  s.sent, s.heard = 0, 0
  return s
end

--- Yards between an entry and `here`, or nil when either has no fix.
function Social.Distance(entry, here)
  if not (entry and here and entry.x and here.x) then return nil end
  if entry.instance ~= here.instance then return nil end
  local dx, dy = entry.x - here.x, entry.y - here.y
  return math.sqrt(dx * dx + dy * dy)
end

--[[ A card arrived from `sender`. `via` is "beacon" (heard on the range-limited
     channel) or "glance" (a whispered question or its answer). Returns the
     entry and whether this player is new to us. ]]
function Social:Hear(now, sender, m, via)
  local key = keyOf(sender, m.guid)
  local e = self.nearby[key]
  local isNew = e == nil
  if isNew then
    e = { key = key, firstHeard = now }
    self.nearby[key] = e
    self.count = self.count + 1
  end
  e.name, e.guid = sender, m.guid
  e.class, e.rank, e.legend = m.class, m.rank, m.legend
  e.x, e.y, e.instance = m.x, m.y, m.instance
  e.layer = m.layer
  e.heardAt = now
  -- "beacon": in earshot. "zone": somewhere in this zone. "glance": you
  -- looked at them. The latest word on where they are is the one kept.
  e.via = via
  self.heard = self.heard + 1
  return e, isNew
end

function Social:Forget(key)
  if self.nearby[key] then self.nearby[key] = nil; self.count = self.count - 1 end
end

--- Drop everyone not heard from lately. Returns how many went.
function Social:Expire(now)
  local gone = 0
  for key, e in pairs(self.nearby) do
    local keep = e.via == "glance" and Social.GLANCE_EXPIRE or Social.EXPIRE
    if now - e.heardAt > keep then
      self.nearby[key] = nil; self.count = self.count - 1; gone = gone + 1
    end
  end
  -- the small memories too, so a long session does not grow them without end
  for _, t in ipairs({ self.announced, self.replied, self.asked, self.knocks }) do
    for key, at in pairs(t) do
      if now - at > Social.GLANCE_COOLDOWN + Social.ANNOUNCE_COOLDOWN then t[key] = nil end
    end
  end
  return gone
end

--[[ LAYERS. A busy zone runs as several copies, and a chat channel spans all
     of them: a player at your exact coordinates may be on another copy, where
     you cannot see them. So a player heard on the zone channel is "same" only
     when both clients could read their layer and the two agree, "other" when
     they disagree, and "unknown" when either could not tell (a client may hide
     it). Anyone heard in earshot or looked at is on your layer by definition. ]]
function Social.Layer(e, mine)
  if e.via ~= "zone" then return "same" end
  if e.layer and mine then return e.layer == mine and "same" or "other" end
  return "unknown"
end

--- Is this player near, as opposed to merely in the same zone (or on
--- another layer of it)?
function Social.IsNear(e, here, mine)
  if e.via ~= "zone" then return true end        -- in earshot, or on your screen
  local d = Social.Distance(e, here)
  return d ~= nil and d <= Social.LIST_RANGE and Social.Layer(e, mine) ~= "other"
end

--[[ Everyone near, nearest first; players with no fix after those with one,
     most recently met first. `blocked(name)` leaves a player out. ]]
function Social:List(here, blocked)
  local out = {}
  for _, e in pairs(self.nearby) do
    if not (blocked and blocked(e.name)) and Social.IsNear(e, here, self.layer) then
      e.distance = Social.Distance(e, here)
      e.unsure = Social.Layer(e, self.layer) == "unknown"
      out[#out + 1] = e
    end
  end
  table.sort(out, function(a, b)
    if (a.distance ~= nil) ~= (b.distance ~= nil) then return a.distance ~= nil end
    if a.distance and a.distance ~= b.distance then return a.distance < b.distance end
    if a.firstHeard ~= b.firstHeard then return a.firstHeard > b.firstHeard end
    return tostring(a.name) < tostring(b.name)
  end)
  return out
end

--- How many players are near (the menu's count), without building the list.
function Social:CountNear(here, blocked)
  local n = 0
  for _, e in pairs(self.nearby) do
    if Social.IsNear(e, here, self.layer) and not (blocked and blocked(e.name)) then n = n + 1 end
  end
  return n
end

--- Can this player be challenged from here, as far as their card says?
function Social.InDuelRange(entry, here)
  local d = Social.Distance(entry, here)
  return d ~= nil and d <= Social.DUEL_RANGE
end

-- ================================================================== beacons

--[[ The distribution to say a beacon on, or nil while every one is refused.
     Tried in order; one the client REFUSES is "dead" and one that accepted
     the line but never brought it back is "deaf", each for REPROBE seconds.
     With nothing better left, a deaf one is still used (a client that delivers
     to others but not to the sender looks the same) and the state is "silent";
     with every one dead it is "refused". Either turns the glance fallback on. ]]
function Social:Channel(now)
  local fallback
  for i, ch in ipairs(Social.CHANNELS) do
    local dead, deaf = self.dead[ch], self.deaf[ch]
    if dead and now - dead >= Social.REPROBE then self.dead[ch] = nil; dead = nil end
    if deaf and now - deaf >= Social.REPROBE then self.deaf[ch] = nil; deaf = nil end
    if not dead then
      if not deaf then
        if self.channelIndex ~= i then
          self.channelIndex, self.misses, self.echoDue = i, 0, nil
          self.broadcast = "unknown"
        end
        return ch
      end
      fallback = fallback or i
    end
  end
  if fallback then
    self.channelIndex, self.broadcast = fallback, "silent"
    return Social.CHANNELS[fallback]
  end
  self.broadcast = "refused"
  return nil
end

--[[ Is it time? `ctx.eligible` is the glue's verdict on everything WoW knows
     (outdoors, alive, not in a duel, willing to be seen) -- a value, or a
     function asked only once the clock says a beacon is due, so the dozen API
     calls behind it run a few times a minute, not every tick. `here` may be nil. ]]
function Social:ShouldBeacon(now, here, ctx)
  if not ctx then return false end
  if not self:Due(now, here) then return false end
  local eligible = ctx.eligible
  if type(eligible) == "function" then eligible = eligible() end
  return eligible and true or false
end

function Social:Due(now, here)
  if not self:Channel(now) then return false end
  if not self.lastBeaconAt then return true end
  -- an answer to a newcomer, but never two beacons inside five seconds: a
  -- crowd arriving together is answered together
  if self.replyAt and now >= self.replyAt and now - self.lastBeaconAt >= 5 then return true end
  local elapsed = now - self.lastBeaconAt
  if elapsed < Social.BEACON_FLOOR then return false end
  local moved
  if here and self.lastBeaconPos and here.instance == self.lastBeaconPos.instance then
    local dx, dy = here.x - self.lastBeaconPos.x, here.y - self.lastBeaconPos.y
    moved = math.sqrt(dx * dx + dy * dy)
  end
  if moved and moved >= Social.MOVE_YARDS then return true end
  local interval = (moved and moved <= Social.STILL_YARDS) and Social.BEACON_STILL or Social.BEACON_MOVING
  if self.count >= Social.CROWD then interval = interval * 2 end
  return elapsed >= interval + (self.jitter or 0)
end

--[[ A beacon went out (or was refused). `outcome` is Transport.Outcome's word:
     "sent", "throttled" or "failed". `jitter` (seconds) spreads the next one so
     a crowd does not all speak on the same beat. ]]
function Social:NoteBeacon(now, here, outcome, jitter)
  self.replyAt = nil
  if outcome == "throttled" then
    self.lastBeaconAt = now      -- wait a full floor before asking again
    return
  end
  local ch = Social.CHANNELS[self.channelIndex]
  if outcome == "failed" then
    self.dead[ch] = now
    self.lastBeaconAt = nil      -- the next distribution is tried at once
    self:Channel(now)
    return
  end
  self.sent = self.sent + 1
  self.lastBeaconAt, self.lastBeaconPos, self.jitter = now, here, jitter or 0
  if self.broadcast ~= "ok" then self.echoDue = now + Social.ECHO_WAIT end
end

--- Anything heard on the beacon distribution -- ours coming back, or anyone's
--- -- proves it carries.
function Social:NoteEcho()
  self.broadcast, self.misses, self.echoDue = "ok", 0, nil
  self.deaf[Social.CHANNELS[self.channelIndex]] = nil
end

--- Our beacon never came back. Twice running, and the distribution is deaf.
function Social:CheckEcho(now)
  if not self.echoDue or now < self.echoDue then return end
  self.echoDue = nil
  if self.broadcast == "ok" then return end
  self.misses = self.misses + 1
  if self.misses < Social.ECHO_MISSES then return end
  self.misses = 0
  local was = self.channelIndex
  self.deaf[Social.CHANNELS[was]] = now
  self:Channel(now)
  if self.channelIndex ~= was then self.lastBeaconAt = nil end
end

--- Mouse-over questions are only asked while beacons are not known to work.
function Social:GlanceMode()
  return self.broadcast == "silent" or self.broadcast == "refused"
end

--- A new player's beacon is answered with one of ours, shortly (`delay`).
function Social:PlanReply(now, entry, delay)
  local at = self.replied[entry.key]
  if at and now - at < Social.REPLY_COOLDOWN then return false end
  self.replied[entry.key] = now
  local when = now + (delay or 1)
  if not self.replyAt or when < self.replyAt then self.replyAt = when end
  return true
end

--- May we whisper a glance question to this player now?
function Social:MayGlance(now, guid)
  if not guid or not self:GlanceMode() then return false end
  if self.nearby[guid] then return false end
  if self.lastGlance and now - self.lastGlance < Social.GLANCE_GAP then return false end
  local at = self.asked[guid]
  if at and now - at < Social.GLANCE_COOLDOWN then return false end
  self.asked[guid], self.lastGlance = now, now
  return true
end

--- One knock per player per KNOCK_COOLDOWN, either way.
function Social:MayKnock(now, key)
  local at = self.knocks[key]
  if at and now - at < Social.KNOCK_COOLDOWN then return false end
  self.knocks[key] = now
  return true
end

-- =================================================================== pop-up

local function inPopupRange(e, here, mine)
  if e.via == "glance" then return true end      -- you were looking at them
  local d = Social.Distance(e, here)
  return d ~= nil and d <= Social.POPUP_RANGE and Social.Layer(e, mine) ~= "other"
end

--[[ Who should be announced now, if anyone. `ctx`:
       enabled  the player wants pop-ups
       busy     combat, a match or the pack room -- wait, do not lose them
       blocked  function(name) -> true to leave a player out
     Returns { rows = {up to POPUP_ROWS entries, most recent first}, more = N }
     and marks those players announced, or nil. ]]
function Social:PopupDue(now, here, ctx)
  ctx = ctx or {}
  if not ctx.enabled or ctx.busy then return nil end
  if self.lastPopup and now - self.lastPopup < Social.POPUP_GAP then return nil end
  local fresh = {}
  for key, e in pairs(self.nearby) do
    local at = self.announced[key]
    if (not at or now - at >= Social.ANNOUNCE_COOLDOWN)
       and not (ctx.blocked and ctx.blocked(e.name))
       and inPopupRange(e, here, self.layer) then
      e.distance = Social.Distance(e, here)
      e.unsure = Social.Layer(e, self.layer) == "unknown"
      fresh[#fresh + 1] = e
    end
  end
  if #fresh == 0 then return nil end
  table.sort(fresh, function(a, b)
    if a.firstHeard ~= b.firstHeard then return a.firstHeard > b.firstHeard end
    return tostring(a.name) < tostring(b.name)
  end)
  local rows = {}
  for i, e in ipairs(fresh) do
    self.announced[e.key] = now
    if i <= Social.POPUP_ROWS then rows[i] = e end
  end
  self.lastPopup = now
  return { rows = rows, more = math.max(0, #fresh - Social.POPUP_ROWS), total = #fresh }
end

-- ==================================================================== guild

local function standing(rec)
  if rec.rank == 0 then return 1e6 - math.min(999999, rec.legend or 999999) end
  return ns.Ladder and ns.Ladder.Standing(rec.rank, rec.stars) or (25 - rec.rank)
end

--[[ Keep what a guildmate reported. `store` is the saved table for one guild
     (name -> record); `wall` is the calendar clock (time()), which is what
     survives a logout; `now` is this session's clock, for "online". ]]
function Social.GuildMerge(store, name, m, wall, now)
  if type(name) ~= "string" or name == "" then return nil end
  -- one row per character: a name that changed form (Forever's first and
  -- last names) must not leave the old row beside the new one
  if m.guid then
    for other, r in pairs(store) do
      if other ~= name and type(r) == "table" and r.guid == m.guid then store[other] = nil end
    end
  end
  local rec = store[name] or {}
  rec.guid = m.guid
  rec.class = m.class
  rec.rank, rec.stars, rec.legend = m.rank, m.stars or 0, m.legend
  rec.wins, rec.losses = m.wins or 0, m.losses or 0
  rec.seen = wall
  rec.heard = now
  store[name] = rec
  return rec
end

--- Forget members not heard from in GUILD_KEEP_DAYS, and the stalest past the cap.
function Social.GuildPrune(store, wall)
  local names = {}
  for name, rec in pairs(store) do
    if type(rec) ~= "table" or type(rec.seen) ~= "number"
       or wall - rec.seen > Social.GUILD_KEEP_DAYS * 86400 then
      store[name] = nil
    else
      rec.heard = nil            -- "online" is this session's, never a saved fact
      names[#names + 1] = name
    end
  end
  if #names > Social.GUILD_MAX then
    table.sort(names, function(a, b) return store[a].seen > store[b].seen end)
    for i = Social.GUILD_MAX + 1, #names do store[names[i]] = nil end
  end
end

--[[ The board: best first. Legend above everyone (a lower Legend number is
     better), then by rank and stars, then by name so the order never shuffles.
     Each row: { name, class, rank, stars, legend, wins, losses, online, me }. ]]
function Social.GuildList(store, now, myGuid)
  local out = {}
  for name, rec in pairs(store) do
    if type(rec) == "table" and knownClass(rec.class) and int(rec.rank, 0, 25) then
      out[#out + 1] = {
        name = name, class = rec.class, rank = rec.rank, stars = rec.stars or 0,
        legend = rec.legend, wins = rec.wins or 0, losses = rec.losses or 0,
        online = rec.heard ~= nil and now ~= nil and now - rec.heard <= Social.GUILD_ONLINE,
        me = myGuid ~= nil and rec.guid == myGuid,
      }
    end
  end
  table.sort(out, function(a, b)
    local sa, sb = standing(a), standing(b)
    if sa ~= sb then return sa > sb end
    return a.name < b.name
  end)
  return out
end

return Social
