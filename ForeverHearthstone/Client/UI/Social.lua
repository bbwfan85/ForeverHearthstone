--[[ Client/UI/Social.lua

  THE SOCIAL SCREEN, THE "PLAYER NEARBY" POP-UP, AND THEIR WIRE.

  Client/Social.lua decides everything -- when to beacon, who is near, who to
  announce, how the guild board sorts -- as plain data. This file is the part
  that touches WoW: it says the lines (C_ChatInfo.SendAddonMessage on prefix
  FHNEAR), hears them (CHAT_MSG_ADDON), and draws two things:

    * SOCIAL (the menu's Social plaque, /fh social): the guild's ladder on the
      left, the players near you on the right with a Duel button each, and the
      two switches -- the pop-up, and whether others can see you.
    * THE POP-UP: a small leather panel under where pack drops appear, naming
      up to three players who have just come near, each with its own button.
      It leaves by itself, like a drop toast.

  COST. One frame, four events, one 1-second ticker. The ticker reads the
  player's position once and does a handful of comparisons; nothing here runs
  per frame except the pop-up's own slide while it is on screen. The mouseover
  event returns at once unless the glance fallback is on.

  Everything optional in the API is looked up with rawget and called through
  pcall: this client is Forever (Mainline, interface 16001) and several of the
  calls -- the range-limited addon message most of all -- are unverified there.
  /fh nearby reports what the client turned out to allow.
]]
local ADDON, ns = ...

local Social, W = ns.Social, ns.Widgets
local SocialUI = {}
ns.SocialUI = SocialUI

local ART = "Interface\\AddOns\\ForeverHearthstone\\Art\\"
local CLASS_RGB = {
  DRUID = { 1, .49, .04 }, HUNTER = { .67, .83, .45 }, MAGE = { .25, .78, .92 },
  PALADIN = { .96, .55, .73 }, PRIEST = { 1, 1, 1 }, ROGUE = { 1, .96, .41 },
  SHAMAN = { .14, .55, .95 }, WARLOCK = { .62, .62, .98 }, WARRIOR = { .78, .61, .43 },
}
local GUILD_ROWS, NEAR_ROWS = 8, 8
local WIN_W, WIN_H = 980, 650
local POP_W, POP_ROW_H = 336, 46
local POP_TOP = -196            -- under the drop toast (TOP -100, 84 tall)
local POP_IN, POP_HOLD, POP_OUT = 0.28, 7, 0.45

local function titleCase(s) s = tostring(s or ""); return s:sub(1, 1) .. s:sub(2):lower() end

--- Call a global that may not exist on this client; a secret or an error is nil.
local function opt(name, ...)
  local fn = rawget(_G, name)
  if not fn then return nil end
  local ok, v = pcall(fn, ...)
  if not ok then return nil end
  if ns.Plain then return ns.Plain(v) end
  return v
end

local function wallClock()
  local t = rawget(_G, "time") or (os and os.time)
  return t and t() or 0
end

--- A name as a player reads it: this realm's suffix dropped, another's kept.
local function shown(name)
  name = tostring(name or "?")
  local base, suffix = name:match("^([^%-]+)%-(.+)$")
  if not base then return name end
  local realm = opt("GetNormalizedRealmName")
  if realm and suffix:lower() == tostring(realm):lower() then return base end
  return base .. " " .. suffix
end

-- ================================================================== settings

function SocialUI:DB()
  ForeverHearthstoneDB = ForeverHearthstoneDB or {}
  local d = ForeverHearthstoneDB.social
  if type(d) ~= "table" then d = {}; ForeverHearthstoneDB.social = d end
  if type(d.guilds) ~= "table" then d.guilds = {} end
  return d
end

function SocialUI:PopupEnabled() return self:DB().popup ~= false end
function SocialUI:Visible() return self:DB().visible ~= false end

function SocialUI:SetPopup(on)
  self:DB().popup = on and true or false
  if not on then self:HidePopup(true) end
  self:Refresh(true)
end

function SocialUI:SetVisible(on)
  self:DB().visible = on and true or false
  self:Refresh(true)
end

-- ================================================================== the wire

function SocialUI:Now() return GetTime and GetTime() or 0 end

function SocialUI:Here()
  return self.main and self.main:WorldPosition() or nil
end

function SocialUI:Me()
  local main = self.main
  local ladder = main:Ladder()
  local record = main:Record()
  return { guid = opt("UnitGUID", "player"), class = main:PlayerClass(),
           layer = self.state and self.state.layer,
           rank = ladder.rank, stars = ladder.stars, legend = ladder.legend,
           wins = record.wins, losses = record.losses }
end

--[[ WHICH LAYER WE ARE ON, as far as it can be told: the "zone uid" in the
     GUID of any creature the client shows us
     ("Creature-0-<server>-<instance>-<zone uid>-<npc>-<spawn>"), from whatever
     the player targets, mouses over or has a nameplate for; never a player's
     own pet or guardian, which may have been summoned elsewhere. The number is
     not the same for every creature in a place, so the last few are kept and
     sent together (Social.Layer matches on any one in common). Forgotten on
     changing zone or group, both of which can move you between layers, and
     after ten minutes. ]]
local LAYER_KEEP, LAYER_AGE = 4, 600

function SocialUI:LayerString(now)
  local list = self.layers
  if not list then return nil end
  for i = #list, 1, -1 do
    if now - list[i].at > LAYER_AGE then table.remove(list, i) end
  end
  if #list == 0 then return nil end
  local parts = {}
  for i = 1, #list do parts[i] = list[i].uid end
  return table.concat(parts, ".")
end

function SocialUI:NoteCreature(unit)
  local guid = opt("UnitGUID", unit)
  if type(guid) ~= "string" then return end
  local kind, _, _, _, zoneUid = guid:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-%d+%-%x+$")
  if kind ~= "Creature" and kind ~= "Vehicle" then return end
  if opt("UnitPlayerControlled", unit) then return end
  local now = self:Now()
  local list = self.layers or {}
  self.layers = list
  for i = #list, 1, -1 do
    if list[i].uid == zoneUid then table.remove(list, i) end
  end
  table.insert(list, 1, { uid = zoneUid, at = now })
  while #list > LAYER_KEEP do table.remove(list) end
  local was = self.state.layer
  self.state.layer = self:LayerString(now)
  self.layerZone = self:ZoneKey()
  if was ~= self.state.layer then self.dirty = true end
end

function SocialUI:ForgetLayer()
  self.layers = nil
  if self.state.layer then self.state.layer = nil; self.dirty = true end
end

local function send(raw, channel, target)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return "failed" end
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, Social.PREFIX, raw, channel, target)
  if not ok then return "failed" end
  return ns.Transport.Outcome(result)
end

function SocialUI:Whisper(raw, name)
  if not name or name == "" then return "failed" end
  return send(raw, "WHISPER", name)
end

--- In a duel, or one being offered either way?
function SocialUI:Duelling()
  local s = self.main.session
  if not s then return false end
  local ST = ns.Session.STATE
  return s:IsActive() or s.state == ST.INVITED or s.state == ST.OFFERED
end

--[[ May this client announce itself right now? Not from inside an instance
     (the duel there is with your group, who are found another way), not while
     away, dead, flying or fighting, and never when the player has asked not
     to be seen or takes challenges only from friends. ]]
function SocialUI:Eligible()
  if not self:Visible() then return false end
  if self.main:DuelPrivacy().policy ~= "anyone" then return false end
  if opt("IsInInstance") then return false end
  if opt("UnitOnTaxi", "player") or opt("UnitIsDeadOrGhost", "player") then return false end
  if opt("UnitIsAFK", "player") or opt("UnitAffectingCombat", "player") then return false end
  if self:Duelling() then return false end
  return true
end

--[[ THE ZONE CHANNEL, the third way to be heard, used only when the client
     refuses YELL and SAY (Forever does). A chat channel of the addon's own,
     one per zone ("FHN<map id>"): joined for this session only
     (JoinTemporaryChannel, so nothing is added to the character's saved
     channels), taken off every chat window so it never prints a line, and
     joined late enough that General and Trade keep their usual numbers.
     Returns the channel's number, or nil and "wait" / "failed". ]]
function SocialUI:ZoneKey()
  local id
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, v = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then id = ns.Plain(v) end
  end
  if not id then
    local here = self:Here()
    id = here and ("i" .. here.instance) or nil
  end
  return id and tostring(id) or nil
end

local function hideFromChat(name)
  local remove = rawget(_G, "ChatFrame_RemoveChannel")
  for i = 1, rawget(_G, "NUM_CHAT_WINDOWS") or 10 do
    local frame = rawget(_G, "ChatFrame" .. i)
    if frame then
      if remove then pcall(remove, frame, name)
      else pcall(function() frame:RemoveChannel(name) end) end
    end
  end
end

function SocialUI:LeaveZoneChannel()
  local name = self.zoneChannel
  if not name then return end
  self.zoneChannel = nil
  local leave = rawget(_G, "LeaveChannelByName")
  if leave then pcall(leave, name) end
end

function SocialUI:ChannelId()
  local now = self:Now()
  if not self:Visible() then self:LeaveZoneChannel(); return nil, "wait" end
  -- inside an instance the last zone's channel is simply kept
  local key = not opt("IsInInstance") and self:ZoneKey()
  local want = key and ("FHN" .. key) or self.zoneChannel
  if not want then return nil, "wait" end
  if self.zoneChannel and self.zoneChannel ~= want then self:LeaveZoneChannel() end
  local id = opt("GetChannelName", want)
  if type(id) == "number" and id > 0 then
    if self.zoneChannel ~= want or not self.zoneHidden then hideFromChat(want); self.zoneHidden = true end
    self.zoneChannel, self.joinTries = want, 0
    return id
  end
  -- not before the game's own channels are in: a channel joined first takes
  -- number 1 and pushes General and Trade down
  if now - (self.startedAt or now) < 20 then return nil, "wait" end
  if now - (self.joinAt or -100) < 10 then return nil, "wait" end
  local join = rawget(_G, "JoinTemporaryChannel") or rawget(_G, "JoinChannelByName")
  if not join or (self.joinTries or 0) >= 3 then return nil, "failed" end
  self.joinAt, self.joinTries, self.zoneHidden = now, (self.joinTries or 0) + 1, nil
  pcall(join, want)
  self.zoneChannel = want
  hideFromChat(want)
  return nil, "wait"
end

function SocialUI:Beacon(now, here)
  local s = self.state
  local channel = s:Channel(now)
  if not channel then return end
  local target
  if channel == "CHANNEL" then
    local id, why = self:ChannelId()
    if not id then
      if why == "failed" then self.lastResult = "CHANNEL: could not join"; s:NoteBeacon(now, here, "failed") end
      return
    end
    target = id
  end
  local outcome = send(Social.Card("B", self:Me(), here), channel, target)
  self.lastResult = channel .. ": " .. outcome
  s:NoteBeacon(now, here, outcome, math.random() * 8)
end

-- ==================================================================== guild

function SocialUI:GuildName()
  if not opt("IsInGuild") then return nil end
  local name = opt("GetGuildInfo", "player")
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

function SocialUI:GuildStore()
  local name = self:GuildName()
  -- /fh nearby test, for a character with no guild to look at
  if not name and self.previewGuild then return self.previewGuild, "Preview" end
  if not name then return nil end
  local guilds = self:DB().guilds
  if type(guilds[name]) ~= "table" then guilds[name] = {} end
  return guilds[name], name
end

--- Our own row, kept current without waiting for the guild channel to echo it.
function SocialUI:KeepSelf()
  local store = self:GuildStore()
  if not store then return end
  local me = self:Me()
  if not me.guid then return end
  local name
  for other, rec in pairs(store) do
    if type(rec) == "table" and rec.guid == me.guid then name = other end
  end
  if not name then
    name = opt("UnitName", "player") or "You"
    local realm = opt("GetNormalizedRealmName")
    if realm and realm ~= "" then name = name .. "-" .. realm end
  end
  Social.GuildMerge(store, name, me, wallClock(), self:Now())
end

function SocialUI:GuildSay()
  if not self:GuildName() then return end
  local me = self:Me()
  self.guildSaid = self:Now()
  self.guildSaidAs = ("%d/%d/%s"):format(me.rank, me.stars, tostring(me.legend))
  send(Social.GuildLine(me), "GUILD")
end

--- Ask the guild who is on the ladder (at most once a minute).
function SocialUI:GuildAsk()
  if not self:GuildName() then return false end
  local now = self:Now()
  if self.guildAsked and now - self.guildAsked < 60 then return false end
  self.guildAsked = now
  send(Social.Encode("R"), "GUILD")
  self:GuildSay()
  return true
end

-- ================================================================== hearing

function SocialUI:Willing(sender, guid)
  if not self:Visible() then return false end
  local policy = self.main:DuelPrivacy().policy
  if policy == "nobody" then return false end
  if policy == "friends" and not self.main:IsFriendly(sender, guid) then return false end
  return true
end

function SocialUI:OnAddon(text, channel, sender)
  local m = Social.Decode(text)
  if not m then return end
  local s, now = self.state, self:Now()
  local mine = m.guid ~= nil and m.guid == opt("UnitGUID", "player")
  local ranged = channel == "YELL" or channel == "SAY" or channel == "CHANNEL"

  if m.kind == "G" or m.kind == "R" then
    if channel ~= "GUILD" then return end
    local store = self:GuildStore()
    if not store then return end
    if m.kind == "G" then
      Social.GuildMerge(store, sender, m, wallClock(), now)
      self.dirty, self.guildDirty = true, true
    elseif not mine then
      -- answered a moment later, each client on its own beat
      if not self.guildSaid or now - self.guildSaid > 10 then
        self.guildReplyAt = now + 0.5 + math.random() * 4
      end
    end
    return
  end

  if mine then
    if ranged then s:NoteEcho() end
    return
  end
  if self.main:IsBlocked(sender) then return end

  if m.kind == "B" then
    if not ranged then return end
    s:NoteEcho()
    local e, isNew = s:Hear(now, sender, m, channel == "CHANNEL" and "zone" or "beacon")
    -- a newcomer near us is answered; one across the zone is not
    if isNew and Social.IsNear(e, self:Here(), s.layer) then s:PlanReply(now, e, 0.5 + math.random() * 1.5) end
    self.dirty = true
  elseif m.kind == "Q" then
    if channel ~= "WHISPER" then return end
    s:Hear(now, sender, m, self:WhisperVia(sender, m))
    self.dirty = true
    -- answered once per asker every few seconds, and only if we would duel them
    self.answered = self.answered or {}
    local at = self.answered[sender]
    if (not at or now - at >= 3) and self:Willing(sender, m.guid) and not opt("IsInInstance") then
      self.answered[sender] = now
      self:Whisper(Social.Card("A", self:Me(), self:Here()), sender)
    end
  elseif m.kind == "A" then
    if channel ~= "WHISPER" then return end
    local e = s:Hear(now, sender, m, self:WhisperVia(sender, m))
    self.dirty = true
    local p = self.pending
    if p and (p.key == e.key or ns.Transport.SameName(p.name, sender)) then
      self.pending = nil
      self:FinishDuel(e)
    end
  elseif m.kind == "K" then
    if channel ~= "WHISPER" then return end
    local key = m.guid or ("name:" .. tostring(sender):lower())
    local e = s.nearby[key]
    if e and self:PopupEnabled() and not self:Busy() and s:MayKnock(now, "in:" .. key) then
      self:ShowPopup({ rows = { e }, more = 0, total = 1, knock = true })
    end
  end
end

--[[ A whispered question or answer usually comes from someone who was looking
     at you, which puts them on your layer. Not when it is the Duel button of a
     player who only knows you from the zone channel: they stay "zone" unless
     we have seen them, and a card naming another layer is never a sighting. ]]
function SocialUI:WhisperVia(sender, m)
  local s = self.state
  local key = m.guid or ("name:" .. tostring(sender):lower())
  local known = s.nearby[key]
  if known then return known.via end       -- a whisper is no new sighting
  return "glance"
end

--[[ THE GLANCE FALLBACK: when beacons are not carried, the one player you
     point at is asked, quietly, whether they play. A client without the addon
     never registered the prefix and sees nothing. ]]
function SocialUI:Glance(unit)
  local s = self.state
  if not s:GlanceMode() or not self:Visible() then return end
  if not opt("UnitExists", unit) or not opt("UnitIsPlayer", unit) then return end
  if opt("UnitIsUnit", unit, "player") then return end
  local mine, theirs = opt("UnitFactionGroup", "player"), opt("UnitFactionGroup", unit)
  if mine and theirs and mine ~= theirs then return end
  local fn = rawget(_G, "UnitName")
  local ok, name, realm = pcall(fn, unit)
  if not ok then return end
  name, realm = ns.Plain(name), ns.Plain(realm)
  if not name then return end
  if realm and realm ~= "" then name = name .. "-" .. realm end
  self:Ask(name, opt("UnitGUID", unit))
end

--[[ Ask one player, by name, whether they play. Also used for anyone whose
     /say, /yell or emote reaches your chat -- they are within earshot by
     definition -- and for your party. Same limits whoever it is: once per
     player per half hour, one question every few seconds. ]]
function SocialUI:Ask(name, guid)
  local s = self.state
  if not s:GlanceMode() or not self:Visible() or opt("IsInInstance") then return false end
  if type(name) ~= "string" or name == "" or type(guid) ~= "string" then return false end
  if guid == opt("UnitGUID", "player") or self.main:IsBlocked(name) then return false end
  if not s:MayGlance(self:Now(), guid) then return false end
  self:Whisper(Social.Card("Q", self:Me(), self:Here()), name)
  return true
end

-- =================================================================== duels

function SocialUI:Say(msg)
  self.status, self.statusAt = msg, self:Now()
  if self.window and self.window:IsShown() then self:Refresh(true)
  elseif msg and msg ~= "" then self.main:Print(msg) end
end

--[[ Duel from a row. Someone the client can see as a unit goes through the
     ordinary challenge and its range check. Anyone else is asked where they
     are standing NOW (their beacon may be most of a minute old), and the
     challenge follows only if that is beside you. ]]
function SocialUI:Duel(entry)
  local main = self.main
  local unit = main:FindPlayerUnit(entry.name, entry.guid)
  if unit then
    local ok, why = main:Challenge(entry.name, unit, entry.guid)
    if ok then self:AfterChallenge() else self:Say(("Could not challenge %s: %s"):format(shown(entry.name), tostring(why or "unknown"))) end
    return ok
  end
  if entry.preview then
    self:Say(("%s is only a preview. Real players nearby appear here the same way."):format(shown(entry.name)))
    return false
  end
  --[[ NOT GATED ON THE LAYER (the owner's call, 2026-11-27: "let them duel
       across layers still until better testing happens"). Without a unit only
       coordinates say they are beside you, and coordinates are the same on
       every layer -- but the layer marks are not yet known to agree between
       two players standing together, and refusing on them would refuse real
       duels. The "~" on the row is the only caution for now. ]]
  if not self:Here() then
    self:Say(("Target %s and press Duel a Player."):format(shown(entry.name)))
    return false
  end
  self.pending = { key = entry.key, name = entry.name, at = self:Now() }
  self:Whisper(Social.Card("Q", self:Me(), self:Here()), entry.name)
  self:Say(("Looking for %s..."):format(shown(entry.name)))
  return true
end

function SocialUI:FinishDuel(entry)
  local main = self.main
  local d = Social.Distance(entry, self:Here())
  if not d then
    self:Say(("Can't tell how far away %s is. Target them and press Duel a Player."):format(shown(entry.name)))
  elseif d > Social.DUEL_RANGE then
    self:Say(("%s is %d yards away. Walk over to them, then press Duel."):format(shown(entry.name), math.floor(d + 0.5)))
  else
    main.vouched = { name = entry.name, untilAt = self:Now() + 3 }
    local ok, why = main:Challenge(entry.name, nil, entry.guid)
    main.vouched = nil
    if ok then self:AfterChallenge() else self:Say(("Could not challenge %s: %s"):format(shown(entry.name), tostring(why or "unknown"))) end
  end
end

function SocialUI:AfterChallenge()
  self.status = nil
  self:HidePopup(true)
  if self.window then self.window:Hide() end
end

function SocialUI:Knock(entry)
  if entry.preview then
    self:Say(("%s is only a preview. Real players nearby appear here the same way."):format(shown(entry.name)))
    return false
  end
  if not self.state:MayKnock(self:Now(), "out:" .. entry.key) then
    self:Say(("You knocked for %s a moment ago."):format(shown(entry.name)))
    return false
  end
  self:Whisper(Social.Encode("K", opt("UnitGUID", "player") or ""), entry.name)
  self:Say(("You knocked for %s. If they want a game they will come over."):format(shown(entry.name)))
  return true
end

--- What a row's button does for this player from here: "Duel" or "Knock".
function SocialUI:ActionFor(entry, here)
  local d = Social.Distance(entry, here)
  if d ~= nil and d > Social.DUEL_RANGE then return "Knock" end
  return "Duel"
end

function SocialUI:Act(entry)
  if self:ActionFor(entry, self:Here()) == "Knock" then return self:Knock(entry) end
  return self:Duel(entry)
end

-- ==================================================================== ticking

--- Anything that should hold a pop-up back rather than talk over it.
function SocialUI:Busy()
  local main = self.main
  if opt("UnitAffectingCombat", "player") then return true end
  if self:Duelling() then return true end
  if main.board and main.board.frame and main.board.frame:IsShown() then return true end
  local ui = main.collectionUI
  if ui and ui.frame and ui.frame:IsShown() then return true end
  return false
end

function SocialUI:Tick()
  local s, now = self.state, self:Now()
  local here = self:Here()
  if s:Expire(now) > 0 then self.dirty = true end
  s:CheckEcho(now)
  if s:ShouldBeacon(now, here, self.beaconCtx) then self:Beacon(now, here) end
  -- on the zone channel: follow the player from zone to zone, and listen even
  -- while not speaking (combat, a duel)
  if s.layer then
    if self.layerZone ~= self:ZoneKey() then self:ForgetLayer()
    else s.layer = self:LayerString(now) end
  end
  if Social.CHANNELS[s.channelIndex] == "CHANNEL" and s.broadcast ~= "refused" then
    self:ChannelId()
  elseif s.broadcast == "refused" then
    self:LeaveZoneChannel()
  end
  -- your party, asked one at a time, when beacons are not doing it for us
  if s:GlanceMode() and opt("IsInGroup") then
    for i = 1, 4 do self:Glance("party" .. i) end
  end
  local near = s:CountNear(here, self.blockedFn)
  if near ~= self.nearCount then self.nearCount = near; self.dirty = true end
  if self.answered and now - (self.answeredSwept or 0) > 300 then
    self.answered, self.answeredSwept = {}, now
  end

  -- the guild: our turn to answer a roll-call, or our rank changed
  if self.guildReplyAt and now >= self.guildReplyAt then
    self.guildReplyAt = nil
    self:GuildSay()
  elseif self.guildSaidAs and (not self.guildSaid or now - self.guildSaid > 30) then
    local me = self.main:Ladder()
    if ("%d/%d/%s"):format(me.rank, me.stars, tostring(me.legend)) ~= self.guildSaidAs then self:GuildSay() end
  end
  if not self.guildAsked and now >= (self.guildAskAt or 0) then self:GuildAsk() end

  if self.pending and now - self.pending.at > 4 then
    local name = self.pending.name
    self.pending = nil
    self:Say(("No answer from %s."):format(shown(name)))
  end

  -- the pop-up; with Social open the list is already in front of the player
  local open = self.window and self.window:IsShown()
  if not (self.popup and self.popup.frame:IsShown()) then
    local due = s:PopupDue(now, here, {
      enabled = self:PopupEnabled(), busy = not open and self:Busy(),
      blocked = function(name) return self.main:IsBlocked(name) end,
    })
    if due and not open then self:ShowPopup(due) end
  end

  if self.dirty or open then self:Refresh() end
end

-- =================================================================== pop-up

local function rowLine(entry, here)
  local d = Social.Distance(entry, here)
  local where = d and (d < 15 and "beside you" or ("%d yd"):format(math.floor(d / 5 + 0.5) * 5)) or "nearby"
  -- "~": heard on the zone channel and not confirmed to be on your layer
  if entry.unsure then where = "~" .. (d and ("%d yd"):format(math.floor(d / 5 + 0.5) * 5) or "nearby") end
  return ("%s  -  %s  -  %s"):format(titleCase(entry.class), ns.Ladder.Label(entry.rank, entry.legend), where)
end

function SocialUI:BuildPopup()
  local p = {}
  local f = CreateFrame("Button", "ForeverHearthstoneNearby", UIParent)
  p.frame = f
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:RegisterForClicks("LeftButtonUp")
  f:SetScript("OnClick", function() self:HidePopup(true); self:Show() end)
  p.bg = f:CreateTexture(nil, "BACKGROUND")
  p.bg:SetAllPoints(); p.bg:SetTexture(ART .. "menu-leather.tga"); p.bg:SetVertexColor(.36, .22, .14, .97)
  -- no glow behind the title: drawn over the leather it showed as a bright
  -- square in the corner (the drop toast's glow sits BEHIND its panel)
  p.rim = W.GoldFrame(f, 8, "BORDER")
  p.title = W.StyledText(f, "header")
  p.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -10); p.title:SetSize(POP_W - 32, 20)
  p.title:SetJustifyH("LEFT"); p.title:SetWordWrap(false)
  p.more = W.StyledText(f, "nameplateSub")
  p.more:SetSize(POP_W - 32, 16); p.more:SetJustifyH("LEFT"); p.more:SetWordWrap(false)
  p.rows = {}
  for i = 1, Social.POPUP_ROWS do
    local r = {}
    r.medal = W.RankMedal(f)
    r.medal:Layout(36, { stars = false })
    r.medal:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -36 - (i - 1) * POP_ROW_H)
    r.name = W.StyledText(f, "label")
    r.name:SetPoint("TOPLEFT", f, "TOPLEFT", 58, -37 - (i - 1) * POP_ROW_H)
    r.name:SetSize(POP_W - 58 - 100, 18); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
    r.sub = W.StyledText(f, "nameplateSub")
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.sub:SetSize(POP_W - 58 - 100, 14); r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
    r.button = W.MenuButton(f, "Duel", function() if r.entry then self:Act(r.entry) end end)
    r.button:SetSize(84, 30)
    r.button:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -39 - (i - 1) * POP_ROW_H)
    r.button:SetFrameLevel(f:GetFrameLevel() + 5)
    p.rows[i] = r
  end
  f:Hide()
  self.popup = p
  return p
end

function SocialUI:ShowPopup(due)
  local p = self.popup or self:BuildPopup()
  local here = self:Here()
  local n = #due.rows
  if n == 0 then return end
  for i, r in ipairs(p.rows) do
    local e = due.rows[i]
    r.entry = e
    r.medal:SetShown(e ~= nil); r.name:SetShown(e ~= nil); r.sub:SetShown(e ~= nil); r.button:SetShown(e ~= nil)
    if e then
      r.medal:Set(e.rank, 0, e.legend)
      local c = CLASS_RGB[e.class] or W.Colors.cream
      r.name:SetText(shown(e.name)); r.name:SetTextColor(c[1], c[2], c[3])
      r.sub:SetText(rowLine(e, here))
      r.button.text:SetText(self:ActionFor(e, here))
    end
  end
  if due.knock then
    p.title:SetText(("%s wants a game!"):format(shown(due.rows[1].name)))
  else
    p.title:SetText(due.total == 1 and "A Hearthstone player is nearby" or "Hearthstone players nearby")
  end
  local h = 36 + n * POP_ROW_H + 6
  if due.more > 0 then
    p.more:ClearAllPoints(); p.more:SetPoint("TOPLEFT", p.frame, "TOPLEFT", 16, -h + 2)
    p.more:SetText(("and %d more - click to see everyone"):format(due.more))
    p.more:Show(); h = h + 20
  else
    p.more:Hide()
  end
  p.frame:SetSize(POP_W, h)
  p.rim:Layout(POP_W, h)
  p.age, p.leaving = 0, nil
  p.frame:SetAlpha(0); p.frame:Show()
  ns.Sounds.Play(due.knock and "menu_open" or "card_deal")
  --[[ In from above with a little overshoot, held, then out the way it came --
       the pack drop's own motion. The clock stops while the pointer is on it,
       so nobody loses the panel while reaching for a button. ]]
  p.frame:SetScript("OnUpdate", function(frame, dt)
    local held = not p.leaving and p.age >= POP_IN and frame:IsMouseOver()
    if not held then p.age = p.age + dt end
    local y, a = 0, 1
    if p.age < POP_IN then
      local v = p.age / POP_IN
      local back = 1 + 2.2 * (v - 1) ^ 3 + 1.2 * (v - 1) ^ 2      -- backOut
      y, a = (1 - back) * 150, v
    elseif p.age > POP_IN + POP_HOLD then
      p.leaving = true
      local v = math.min(1, (p.age - POP_IN - POP_HOLD) / POP_OUT)
      y, a = v * v * 150, 1 - v
      if v >= 1 then self:HidePopup(true); return end
    end
    frame:ClearAllPoints(); frame:SetPoint("TOP", UIParent, "TOP", 0, POP_TOP + y)
    frame:SetAlpha(a)
  end)
end

function SocialUI:HidePopup(now)
  local p = self.popup
  if not p or not p.frame:IsShown() then return end
  if now then
    p.frame:SetScript("OnUpdate", nil); p.frame:Hide()
  elseif not p.leaving then
    p.age = POP_IN + POP_HOLD
  end
end

-- =============================================================== the window

local function makeColumn(parent, x, title)
  local c = {}
  local colW, colH = (WIN_W - 28 * 2 - 20) / 2, 480
  c.w, c.h = colW, colH
  c.frame = W.MenuPanel(parent, "leather")
  c.frame:SetSize(colW, colH); c.frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -68)
  c.frame:SetFrameLevel(parent:GetFrameLevel() + 2)
  c.frame.bg:SetVertexColor(.40, .25, .15, 1)
  c.title = W.StyledText(c.frame, "caption", nil, 620)
  c.title:SetPoint("TOP", c.frame, "TOP", 0, -14); c.title:SetSize(colW - 40, 24)
  c.title:SetWordWrap(false); c.title:SetText(title)
  c.rule = c.frame:CreateTexture(nil, "ARTWORK")
  c.rule:SetColorTexture(1, .80, .42, .35)
  c.rule:SetPoint("TOP", c.frame, "TOP", 0, -44); c.rule:SetSize(colW - 44, 1)
  c.empty = W.StyledText(c.frame, "body")
  c.empty:SetPoint("TOP", c.frame, "TOP", 0, -120); c.empty:SetSize(colW - 80, 160)
  c.empty:SetJustifyH("CENTER"); c.empty:SetJustifyV("TOP"); c.empty:SetWordWrap(true)
  c.foot = W.StyledText(c.frame, "nameplateSub")
  c.foot:SetPoint("BOTTOM", c.frame, "BOTTOM", 0, 16); c.foot:SetSize(colW - 44, 30)
  c.foot:SetJustifyH("CENTER"); c.foot:SetWordWrap(true)
  c.rows = {}
  return c
end

local ROW_H, ROW_TOP = 48, 52

local function makeRow(c, i)
  local r = {}
  local y = -ROW_TOP - (i - 1) * ROW_H
  r.strip = c.frame:CreateTexture(nil, "BORDER", nil, 2)
  r.strip:SetPoint("TOPLEFT", c.frame, "TOPLEFT", 16, y); r.strip:SetSize(c.w - 32, ROW_H - 4)
  r.strip:SetColorTexture(1, .86, .6, i % 2 == 1 and .07 or .025)
  r.place = W.StyledText(c.frame, "number")
  r.place:SetPoint("TOPLEFT", c.frame, "TOPLEFT", 18, y - 13); r.place:SetSize(28, 18)
  r.place:SetJustifyH("CENTER"); r.place:SetWordWrap(false)
  r.medal = W.RankMedal(c.frame)
  r.medal:Layout(38, { stars = false })
  r.name = W.StyledText(c.frame, "label")
  r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
  r.sub = W.StyledText(c.frame, "nameplateSub")
  r.sub:SetJustifyH("LEFT"); r.sub:SetWordWrap(false)
  r.right = W.StyledText(c.frame, "label")
  r.right:SetPoint("TOPRIGHT", c.frame, "TOPRIGHT", -26, y - 13); r.right:SetSize(120, 18)
  r.right:SetJustifyH("RIGHT"); r.right:SetWordWrap(false)
  r.y = y
  c.rows[i] = r
  return r
end

local function showRow(r, on)
  for _, k in ipairs({ "strip", "place", "medal", "name", "sub", "right" }) do r[k]:SetShown(on) end
  if r.button then r.button:SetShown(on) end
end

function SocialUI:BuildWindow()
  local d
  d = W.Dialog(UIParent, "ForeverHearthstoneSocial", { { "Close", function() d:Hide() end } },
               { w = WIN_W, h = WIN_H, paper = true })
  d:SetFrameStrata("FULLSCREEN_DIALOG")
  d.message:ClearAllPoints(); d.message:SetPoint("TOP", d.panel, "TOP", 0, -22)
  d.message:SetSize(WIN_W - 80, 34); W.ApplyStyle(d.message, "pageTitle", nil, 28)
  d.message:SetText("Social")
  self.window = d

  local colW = (WIN_W - 28 * 2 - 20) / 2
  local g = makeColumn(d.panel, 28, "Guild Ladder")
  local n = makeColumn(d.panel, 28 + colW + 20, "Players Nearby")
  self.guildCol, self.nearCol = g, n
  self.guildPage = 1

  for i = 1, GUILD_ROWS do
    local r = makeRow(g, i)
    r.medal:SetPoint("TOPLEFT", g.frame, "TOPLEFT", 50, r.y - 3)
    r.name:SetPoint("TOPLEFT", g.frame, "TOPLEFT", 98, r.y - 6); r.name:SetSize(colW - 98 - 150, 18)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2); r.sub:SetSize(colW - 98 - 150, 14)
  end
  for i = 1, NEAR_ROWS do
    local r = makeRow(n, i)
    r.place:Hide()
    r.medal:SetPoint("TOPLEFT", n.frame, "TOPLEFT", 22, r.y - 3)
    r.name:SetPoint("TOPLEFT", n.frame, "TOPLEFT", 70, r.y - 6); r.name:SetSize(colW - 70 - 128, 18)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2); r.sub:SetSize(colW - 70 - 128, 14)
    r.right:Hide()
    r.button = W.MenuButton(n.frame, "Duel", function() if r.entry then self:Act(r.entry) end end)
    r.button:SetSize(96, 32); r.button:SetPoint("TOPRIGHT", n.frame, "TOPRIGHT", -22, r.y - 6)
    r.button:SetFrameLevel(n.frame:GetFrameLevel() + 4)
  end

  -- the guild board turns its pages with the book's arrows
  g.prev = W.MenuButton(g.frame, "", function() self.guildPage = self.guildPage - 1; self:Refresh(true) end)
  g.next = W.MenuButton(g.frame, "", function() self.guildPage = self.guildPage + 1; self:Refresh(true) end)
  for i, b in ipairs({ g.prev, g.next }) do
    b.bg:SetTexture(ART .. "page-arrow.tga")
    if i == 1 then b.bg:SetTexCoord(1, 0, 0, 1) else b.bg:SetTexCoord(0, 1, 0, 1) end
    b:SetSize(22, 36); b:SetFrameLevel(g.frame:GetFrameLevel() + 4)
    b:SetPoint("BOTTOM", g.frame, "BOTTOM", i == 1 and -(colW / 2 - 30) or (colW / 2 - 30), 12)
  end

  -- the two switches, either side of Close
  d.popupToggle = W.MenuButton(d.panel, "", function() self:SetPopup(not self:PopupEnabled()) end)
  d.visibleToggle = W.MenuButton(d.panel, "", function() self:SetVisible(not self:Visible()) end)
  for i, b in ipairs({ d.popupToggle, d.visibleToggle }) do
    b:SetSize(300, 36); b:SetFrameLevel(d:GetFrameLevel() + 10)
    if i == 1 then b:SetPoint("BOTTOMLEFT", d.panel, "BOTTOMLEFT", 28, 26)
    else b:SetPoint("BOTTOMRIGHT", d.panel, "BOTTOMRIGHT", -28, 26) end
  end
  d:HookScript("OnShow", function() ns.Sounds.Play("menu_open") end)
  d:Hide()
  return d
end

function SocialUI:Show()
  if not self.main then return end
  local d = self.window or self:BuildWindow()
  d.panel:SetScale(math.max(.1, math.min(1, (UIParent:GetWidth() - 32) / WIN_W, (UIParent:GetHeight() - 32) / WIN_H)))
  self:HidePopup(true)
  self:GuildAsk()
  d:Show()
  self:Refresh(true)
end

function SocialUI:Toggle()
  if self.window and self.window:IsShown() then self.window:Hide() else self:Show() end
end

--- How many players are near, for the menu's plaque.
function SocialUI:Count()
  if not self.state then return 0 end
  return self.state:CountNear(self:Here(), self.blockedFn)
end

--[[ Redraw whatever is on screen. Called once a second while Social is open
     (distances move) and whenever something arrived; with the window closed
     it only keeps the menu's "Social (2)" current. ]]
function SocialUI:Refresh(force)
  self.dirty = nil
  local main = self.main
  if not main then return end
  local hub = main.hub
  local plaque = hub and rawget(hub, "social")
  if plaque and hub:IsShown() then
    local n = self:Count()
    local label = n > 0 and ("Social (%d nearby)"):format(n) or "Social"
    if plaque.text:GetText() ~= label then plaque.text:SetText(label) end
  end
  local d = self.window
  if not (d and d:IsShown()) then return end
  local now, here = self:Now(), self:Here()

  -- the board only changes when someone reports in; the nearby list's
  -- distances change as you walk, so that half is redrawn every second
  if force or self.guildDirty then self:RefreshGuild(now) end
  self:RefreshNearby(now, here)
  d.popupToggle.text:SetText("Nearby pop-up: " .. (self:PopupEnabled() and "On" or "Off"))
  d.visibleToggle.text:SetText("Visible to nearby players: " .. (self:Visible() and "On" or "Off"))
end

function SocialUI:RefreshGuild(now)
  self.guildDirty = nil
  local g = self.guildCol
  local store, guildName = self:GuildStore()
  local list = {}
  if store then
    self:KeepSelf()
    list = Social.GuildList(store, now, opt("UnitGUID", "player"))
  end
  g.title:SetText(guildName and ("Guild Ladder - " .. guildName) or "Guild Ladder")
  local pages = math.max(1, math.ceil(#list / GUILD_ROWS))
  self.guildPage = math.max(1, math.min(self.guildPage or 1, pages))
  for i, r in ipairs(g.rows) do
    local at = (self.guildPage - 1) * GUILD_ROWS + i
    local m = list[at]
    showRow(r, m ~= nil)
    if m then
      local c = CLASS_RGB[m.class] or W.Colors.cream
      local dim = (m.online or m.me) and 1 or .5
      r.place:SetText(tostring(at))
      r.medal:Set(m.rank, m.stars, m.legend); r.medal:SetAlpha(dim)
      r.name:SetText(shown(m.name) .. (m.me and "  (you)" or ""))
      r.name:SetTextColor(c[1], c[2], c[3]); r.name:SetAlpha(dim)
      r.sub:SetText(titleCase(m.class) .. ((m.online or m.me) and "" or "  -  offline"))
      r.sub:SetAlpha(dim)
      r.right:SetText(ns.Ladder.Label(m.rank, m.legend)); r.right:SetAlpha(dim)
      r.strip:SetColorTexture(1, .86, .6, m.me and .16 or (i % 2 == 1 and .07 or .025))
    end
  end
  g.prev:SetShown(pages > 1); g.next:SetShown(pages > 1)
  g.prev:SetEnabledLook(self.guildPage > 1); g.next:SetEnabledLook(self.guildPage < pages)
  g.empty:SetShown(#list <= (store and 1 or 0))
  if not store then
    g.empty:SetText("You are not in a guild.\n\nJoin one and its members who play Forever Hearthstone appear here, best rank first.")
  else
    g.empty:ClearAllPoints(); g.empty:SetPoint("TOP", g.frame, "TOP", 0, -150)
    g.empty:SetText("No guildmates have reported a rank yet.\n\nThey appear here as they log in with Forever Hearthstone.")
  end
  g.foot:SetText(pages > 1 and ("Page %d of %d"):format(self.guildPage, pages)
    or (#list > 1 and "Ranks are earned on the bot ladder." or ""))
end

function SocialUI:RefreshNearby(now, here)
  local main = self.main
  local n = self.nearCol
  local near = self.state:List(here, function(name) return main:IsBlocked(name) end)
  for i, r in ipairs(n.rows) do
    local e = near[i]
    r.entry = e
    showRow(r, e ~= nil)
    r.place:Hide(); r.right:Hide()
    if e then
      local c = CLASS_RGB[e.class] or W.Colors.cream
      r.medal:Set(e.rank, 0, e.legend)
      r.name:SetText(shown(e.name)); r.name:SetTextColor(c[1], c[2], c[3])
      r.sub:SetText(rowLine(e, here))
      local action = self:ActionFor(e, here)
      if r.button.text:GetText() ~= action then r.button.text:SetText(action) end
    end
  end
  n.empty:SetShown(#near == 0)
  local s = self.state
  if #near == 0 then
    n.empty:SetText(not self:Visible()
      and "You are hidden from nearby players, so they are hidden from you too.\n\nTurn on \"Visible to nearby players\" below to find games."
      or (s:GlanceMode()
        and "Nobody yet.\n\nPlayers with Forever Hearthstone appear here when you point at them, group with them, or hear them speak or emote nearby."
        or "Nobody nearby is playing right now.\n\nPlayers with Forever Hearthstone appear here as you pass them in the world."))
  end
  local foot = ""
  if self.status and now - (self.statusAt or 0) < 12 then foot = self.status
  elseif #near > NEAR_ROWS then foot = ("and %d more nearby"):format(#near - NEAR_ROWS)
  elseif #near > 0 then
    local unsure = false
    for _, e in ipairs(near) do unsure = unsure or e.unsure end
    foot = unsure and "~ means not confirmed on your layer. If you can't see them, they may be on another one."
      or "Duel challenges a player beside you. Knock invites one further off to come over."
  end
  n.foot:SetText(foot)
end

--[[ /fh nearby test: what the pop-up and the lists look like, without a
     second player. Made-up travellers and guildmates, on this screen only --
     nothing is sent, nothing is saved, and they fade like anyone else. ]]
function SocialUI:Preview()
  local s, now, here = self.state, self:Now(), self:Here() or { x = 0, y = 0, instance = 0 }
  local cast = { { "Ysera", "DRUID", 4, 6 }, { "Brann", "HUNTER", 14, 35 }, { "Sylvanas", "ROGUE", 0, 62 },
                 { "Uther", "PALADIN", 9, 70 }, { "Thrall", "SHAMAN", 21, 76 } }
  for i, c in ipairs(cast) do
    local e = s:Hear(now + i * 0.01, c[1], { guid = "Preview-" .. i, class = c[2], rank = c[3],
      legend = c[3] == 0 and 318 or nil, x = here.x + c[4], y = here.y, instance = here.instance }, "beacon")
    e.preview = true
    s.announced[e.key] = nil
  end
  s.lastPopup = nil
  self.previewGuild = {
    ["Tirion"] = { guid = "Preview-G1", class = "PALADIN", rank = 0, legend = 41, heard = now, seen = 0 },
    ["Jaina"] = { guid = "Preview-G2", class = "MAGE", rank = 2, stars = 3, heard = now, seen = 0 },
    ["Rexxar"] = { guid = "Preview-G3", class = "HUNTER", rank = 7, stars = 1, seen = 0 },
    ["Garrosh"] = { guid = "Preview-G4", class = "WARRIOR", rank = 13, stars = 2, heard = now, seen = 0 },
    ["Anduin"] = { guid = "Preview-G5", class = "PRIEST", rank = 19, stars = 0, seen = 0 },
  }
  if self.window then self.window:Hide() end
  local due = s:PopupDue(now + 1, here, { enabled = true })
  if due then self:ShowPopup(due) end
  self.dirty, self.guildDirty = true, true
end

--- /fh nearby: what the client turned out to allow, in one line.
function SocialUI:Report()
  local s = self.state
  if not s then return "nearby: not started." end
  local how = ({
    unknown = "not confirmed yet",
    ok = "working",
    silent = "not carried by this client - asking players you point at, hear or group with instead",
    refused = "refused by this client - asking players you point at, hear or group with instead",
  })[s.broadcast] or s.broadcast
  local ch = Social.CHANNELS[s.channelIndex]
  local via = ({ YELL = "in earshot (yell)", SAY = "in earshot (say)",
                 CHANNEL = "zone channel " .. tostring(self.zoneChannel or "not joined") })[ch] or tostring(ch)
  local off = {}
  for _, name in ipairs(Social.CHANNELS) do
    if s.dead[name] then off[#off + 1] = name:lower() .. " refused"
    elseif s.deaf[name] then off[#off + 1] = name:lower() .. " unheard" end
  end
  return ("nearby: broadcast %s, %s%s (last %s). Layer %s. %d sent, %d heard, %d player%s near. Pop-up %s, visible %s.")
    :format(how, via, #off > 0 and ("; " .. table.concat(off, ", ")) or "", tostring(self.lastResult or "none"),
            s.layer and ("marks " .. tostring(s.layer):gsub("%.", ", ")) or "unknown (target or mouse over any creature)",
            s.sent, s.heard, self:Count(), self:Count() == 1 and "" or "s",
            self:PopupEnabled() and "on" or "off", self:Visible() and "on" or "off")
end

-- ==================================================================== start

function SocialUI:Start(main)
  if self.frame then return end
  self.main = main
  self.state = Social.New()
  self.beaconCtx = { eligible = function() return self:Eligible() end }
  local db = self:DB()
  for _, store in pairs(db.guilds) do
    if type(store) == "table" then Social.GuildPrune(store, wallClock()) end
  end
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, Social.PREFIX)
  end
  local f = CreateFrame("Frame")
  self.frame = f
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
  f:RegisterEvent("PLAYER_TARGET_CHANGED")
  -- anyone you can hear is near: their name is all these are read for
  for _, e in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE" }) do
    pcall(f.RegisterEvent, f, e)
  end
  -- creatures the client shows us say which layer we are on (NoteCreature)
  pcall(f.RegisterEvent, f, "NAME_PLATE_UNIT_ADDED")
  pcall(f.RegisterEvent, f, "GROUP_ROSTER_UPDATE")
  self.startedAt = self:Now()
  self.blockedFn = function(name) return main:IsBlocked(name) end
  f:SetScript("OnEvent", function(_, event, prefix, text, channel, sender, ...)
    if event == "CHAT_MSG_ADDON" then
      if prefix ~= Social.PREFIX then return end
      local ok, err = pcall(self.OnAddon, self, text, channel, sender)
      if not ok and not self.faulted then self.faulted = true; main:Debug("social: " .. tostring(err)) end
      return
    elseif event == "GROUP_ROSTER_UPDATE" then
      self:ForgetLayer(); return      -- joining a group can move you to its layer
    elseif event == "NAME_PLATE_UNIT_ADDED" then
      pcall(self.NoteCreature, self, prefix); return
    end
    local unit = event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or (event == "PLAYER_TARGET_CHANGED" and "target") or nil
    if unit then pcall(self.NoteCreature, self, unit) end
    if not self.state:GlanceMode() then
      return
    elseif unit then
      pcall(self.Glance, self, unit)
    else
      -- a chat line: (text, playerName, ..., guid in twelfth place)
      local guid = select(8, ...)
      pcall(self.Ask, self, ns.Plain(text), ns.Plain(guid))
    end
  end)
  -- the first beacon and the guild roll-call wait for the world to settle
  local now = self:Now()
  self.state.lastBeaconAt = now - Social.BEACON_MOVING + 6 + math.random() * 6
  self.guildAskAt = now + 10 + math.random() * 8
  self.ticker = C_Timer.NewTicker(1, function()
    local ok, err = pcall(self.Tick, self)
    if not ok and not self.faulted then self.faulted = true; main:Debug("social: " .. tostring(err)) end
  end)
end

return SocialUI
