--[[ Client/Rewards.lua

  WHERE WOW PLAY TURNS INTO CARDS.

  Client/Drops.lua decides what a kill is worth and Client/Collection.lua owns
  what you have. This file is the part that has to know WoW exists: which events
  mean "you killed something", what kind of something it was, and whether the
  kill counted.

  ============================================ THE COMBAT LOG IS NOT AVAILABLE

  COMBAT_LOG_EVENT_UNFILTERED ERRORS ON REGISTRATION in Forever (docs/07). That
  looked like a problem and turned out to be an improvement: the standalone
  PLAYER_TARGET_DIED and PARTY_KILL events give kill credit directly, without
  parsing a log or deciding whether a GUID was ours.

    PLAYER_TARGET_DIED       your target died -- solo kills
    PARTY_KILL               a group member landed the killing blow
    ENCOUNTER_STATE_CHANGED  boss encounters, for the Naxxramas cards
    PLAYER_LEVEL_UP          class cards

  ======================================================== THE XP GATE

  docs/04 gates drops on the kill awarding XP, which kills the "level 60 farms
  Westfall" strategy using a rule players already understand. But there is no
  "did that grant XP" API.

  So it is OBSERVED rather than computed: remember the player's XP, and when
  something dies, look again a moment later. If it went up, the kill counted.
  The alternative was reciting WoW's grey-level formula from memory, which is
  exactly the kind of recalled data this project refuses to trust -- and it
  would be wrong in whatever way Forever tuned it.

  The delay exists because XP arrives a tick after the death, not with it. A
  kill whose XP never arrives simply does not pay, which is the correct answer
  for a grey mob and a rare, harmless loss for an edge case we have not thought
  of (the alternative failure -- paying for everything -- is the farm we are
  trying to prevent).

  ====================================================== SAVING, HONESTLY

  SavedVariables are written to disk on LOGOUT or /reload, and at no other time.
  A client crash loses everything earned since the last write, and no API can
  force a flush. There is no clever fix, so this does the three honest things:
  it counts what is unwritten, it says so when the number gets big enough to
  hurt, and `/fh save` reloads the UI -- which IS the flush.
]]
local ADDON, ns = ...

local Rewards = {}
ns.Rewards = Rewards

--[[ SECRET VALUES. Midnight's addon disarmament is live in Forever (docs/07),
     and inside instances unit reads -- GUIDs, classification, tap state, even
     levels -- can come back as SECRET values: displayable, but comparing one,
     indexing a table with one or testing it as a boolean is a Lua error. That
     was the "small error in instances". Every unit read on the kill path goes
     through here: a secret answers as the fallback, as if the API were silent.
     issecretvalue is looked up per call, so a client without it reads plain. ]]
function ns.Plain(v, fallback)
  local isSecret = rawget(_G, "issecretvalue")
  if v == nil or (isSecret and isSecret(v)) then return fallback end
  return v
end
local Plain = ns.Plain

--[[ Two events for one death (PLAYER_TARGET_DIED and PARTY_KILL) arrive in the
     same moment. With a GUID they are deduplicated by victim; when the GUID is
     secret there is nothing to key on, so a second kill inside this window is
     taken to be the same one. ]]
local SAME_KILL_WINDOW = 0.25

--[[ How long to wait after a death before deciding whether XP arrived. Long
     enough for the XP event, short enough that the toast still belongs to the
     kill that earned it. ]]
local XP_WINDOW = 0.4

--[[ How many unsaved rewards before the player is told that nothing is on disk
     yet. High enough not to nag, low enough that "you have 20 packs at risk" is
     still a number worth acting on. ]]
local UNSAVED_NAG = 20

function Rewards.New(opts)
  opts = opts or {}
  local r = setmetatable({}, { __index = Rewards })
  r.collection = opts.collection
  r.onReward   = opts.onReward or function() end   -- (reward) -> toast + choreography
  r.onPrint    = opts.onPrint  or function() end
  r.pending    = nil
  r.unsaved    = 0
  return r
end

function Rewards:Start()
  if self.frame then return end
  local f = CreateFrame("Frame")
  self.frame = f
  --[[ EVERY REGISTRATION IS GUARDED.

       RegisterEvent on a name the client does not have is a hard Lua error, and
       an error here would take the whole addon down at login -- on the FIRST
       load, before the player has seen anything work. That is an unacceptable
       way to find out that one event name was wrong.

       And some of these are genuinely unverified: ENCOUNTER_STATE_CHANGED comes
       from the platform research in docs/07 and has never been confirmed on a
       running client, Forever or retail. So a name this client does not have
       costs exactly the feature that needed it (boss drops) and nothing else,
       and it SAYS SO rather than failing silently. ]]
  self.missingEvents = {}
  for _, event in ipairs({
    "PLAYER_TARGET_DIED",       -- solo kill credit
    "PARTY_KILL",               -- group kill credit
    "ENCOUNTER_END",            -- boss kills (success = 1): Naxxramas cards
    "ENCOUNTER_STATE_CHANGED",  -- the older name some clients still carry
    "PLAYER_LEVEL_UP",          -- class cards
    "PLAYER_XP_UPDATE",         -- the XP gate, observed rather than computed
    "PLAYER_LOGOUT",            -- the one moment SavedVariables are written
  }) do
    local ok = pcall(f.RegisterEvent, f, event)
    if not ok then self.missingEvents[#self.missingEvents + 1] = event end
  end
  self.hasEncounterEnd = true
  for _, e in ipairs(self.missingEvents) do if e == "ENCOUNTER_END" then self.hasEncounterEnd = false end end
  if #self.missingEvents > 0 then
    self.onPrint(("this client does not have: %s -- the features using them are off")
                 :format(table.concat(self.missingEvents, ", ")))
  end
  f:SetScript("OnEvent", function(_, event, ...) self:OnEvent(event, ...) end)
  self.xp = UnitXP and UnitXP("player") or 0
end

function Rewards:Stop()
  if not self.frame then return end
  self.frame:UnregisterAllEvents()
  self.frame:SetScript("OnEvent", nil)
  self.frame = nil
end

function Rewards:OnEvent(event, ...)
  local a1 = ...
  if event == "PLAYER_XP_UPDATE" then
    self.xp = UnitXP and UnitXP("player") or self.xp

  elseif event == "PLAYER_TARGET_DIED" then
    self:OnKill("target", UnitGUID and Plain(UnitGUID("target")))

  elseif event == "PARTY_KILL" then
    --[[ (attackerGUID, targetGUID). The victim is named by GUID; it is
         classified through whichever unit token still points at it -- not
         blindly through "target", which may be something else entirely. ]]
    local _, victim = ...
    victim = Plain(victim)
    self:OnKill(self:UnitForGUID(victim), victim)

  elseif event == "ENCOUNTER_END" then
    -- (encounterID, encounterName, difficultyID, groupSize, success)
    local id, _, difficulty, size, success = ...
    if success == 1 or success == true then self:Boss(id, difficulty, size) end

  elseif event == "ENCOUNTER_STATE_CHANGED" then
    -- Only if ENCOUNTER_END is unavailable: its payload is unconfirmed, so
    -- it is used just as "an encounter finished", deduplicated per minute.
    if not self.hasEncounterEnd then self:Boss(nil, nil, nil) end

  elseif event == "PLAYER_LEVEL_UP" then
    self:OnLevelUp(a1)

  elseif event == "PLAYER_LOGOUT" then
    self:OnLogout()
  end
end

--- The unit token that currently points at `guid`, if any.
function Rewards:UnitForGUID(guid)
  if not (guid and UnitGUID) then return nil end
  local units = { "target", "focus", "mouseover", "targettarget" }
  for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
  for _, unit in ipairs(units) do
    if UnitExists and UnitExists(unit) and Plain(UnitGUID(unit)) == guid then return unit end
  end
  return nil
end

--[[ Classify what just died. Everything here is read BEFORE the unit goes away,
     because a dead target stops answering these calls quickly. ]]
function Rewards:Describe(unit)
  local classification = UnitClassification and Plain(UnitClassification(unit), "normal") or "normal"
  local kind = "normal"
  if classification == "worldboss" then kind = "boss"
  elseif classification == "rare" or classification == "rareelite" then kind = "rare"
  elseif classification == "elite" then kind = "elite" end

  local creatureType = UnitCreatureType and Plain(UnitCreatureType(unit)) or nil
  --[[ CRITTERS, THREE WAYS. The creature type is localised (English only), so
       it is backed by the classification -- "minus"/"trivial" is how the
       client marks a critter or a harmless mob in any language -- and, below
       60, by the XP gate: a critter never grants XP. ]]
  if creatureType == "Critter" or classification == "minus" or classification == "trivial" then
    kind = "critter"
  end

  return {
    kind = kind,
    classification = classification,
    creatureType = creatureType,
    mobLevel = (UnitLevel and Plain(UnitLevel(unit))) or 0,
    playerLevel = (UnitLevel and Plain(UnitLevel("player"))) or 1,
    --[[ A player's own pet, a totem or a guardian never pays. Checked by
         reaction to "player"'s controlling relationship rather than by name. ]]
    summoned = (UnitPlayerControlled and Plain(UnitPlayerControlled(unit))) or false,
  }
end

--[[ Something died. Snapshot what it was, then decide in a moment whether it
     granted XP -- which is the gate, and which cannot be known yet.

     ONE KILL, ONE ROLL: a solo kill can raise both PLAYER_TARGET_DIED and
     PARTY_KILL, so each victim GUID is rolled at most once. ]]
function Rewards:OnKill(unit, guid)
  if not unit or not (UnitExists and UnitExists(unit)) then return end
  if UnitIsPlayer and Plain(UnitIsPlayer(unit)) then return end   -- PvP kills pay nothing
  --[[ Someone else's kill. PLAYER_TARGET_DIED fires whenever your TARGET dies,
       whoever killed it; below 60 the XP gate catches that, but at 60 there
       is no XP, so keeping your target on other people's mobs paid drops.
       Tap-denied is WoW's own "not yours or your group's" and still answers
       for a corpse. ]]
  local tapDenied = rawget(_G, "UnitIsTapDenied")
  if tapDenied then
    local ok, denied = pcall(tapDenied, unit)
    if ok and Plain(denied) then return end
  end
  guid = guid or (UnitGUID and Plain(UnitGUID(unit)))
  if guid then
    self.rolled = self.rolled or {}
    if self.rolled[guid] then return end
    self.rolled[guid] = true
    self.rolledCount = (self.rolledCount or 0) + 1
    if self.rolledCount > 500 then self.rolled, self.rolledCount = { [guid] = true }, 1 end
  else
    local now = GetTime and GetTime() or 0
    if self.anonKillAt and now - self.anonKillAt < SAME_KILL_WINDOW then return end
    self.anonKillAt = now
  end
  local kill = self:Describe(unit)
  --[[ A raid or dungeon boss inside an instance is paid by its ENCOUNTER_END
       (Rewards:Boss): its Naxxramas card, guaranteed on a first kill. Rolled
       here as well, a raid boss -- classified "worldboss" -- paid twice.
       Here it counts as the elite it is. ]]
  if kill.kind == "boss" and self.hasEncounterEnd and IsInInstance and IsInInstance() then
    kill.kind = "elite"
  end
  local xpBefore, levelBefore = self.xp, kill.playerLevel

  --[[ At max level nothing grants XP ever again, so waiting to see it arrive
       would mean the endgame never drops. Drops.Eligible switches to a mob-level
       rule there; this just stops asking the question. ]]
  if kill.playerLevel >= ns.Drops.MAX_LEVEL then
    self:Resolve(kill)
    return
  end

  C_Timer.After(XP_WINDOW, function()
    -- a kill that LEVELS you resets UnitXP, so a new level counts as XP gained
    local levelNow = (UnitLevel and UnitLevel("player")) or levelBefore
    kill.grantsXP = levelNow > levelBefore or (self.xp or 0) > (xpBefore or 0)
    self:Resolve(kill)
  end)
end

--[[ A BOSS IS DOWN. Every boss kill rolls for a Naxxramas card; the FIRST kill
     of each encounter on a character, and any raid boss (group larger than
     five), is guaranteed one -- which makes the dungeon circuit to pre-raid
     gear the natural way to fill the adventure. A repeat kill inside one
     minute (both boss events firing) is ignored. ]]
function Rewards:Boss(encounterID, difficulty, size)
  local now = GetTime and GetTime() or 0
  if self.lastBossAt and now - self.lastBossAt < 60 and self.lastBossId == encounterID then return end
  self.lastBossAt, self.lastBossId = now, encounterID
  local ch = self.collection and self.collection.character or {}
  ch.bossKills = ch.bossKills or {}
  local first = encounterID ~= nil and not ch.bossKills[encounterID]
  if encounterID then ch.bossKills[encounterID] = (ch.bossKills[encounterID] or 0) + 1 end
  local kill = {
    kind = "boss",
    playerLevel = (UnitLevel and UnitLevel("player")) or 1,
    mobLevel = (UnitLevel and UnitLevel("player")) or 1,
    grantsXP = true,
    guaranteed = first or (tonumber(size) or 0) > 5,
  }
  self:Resolve(kill)
end

--[[ Roll it, bank it, and tell the player -- in that order, so a reward exists
     before anything animates. The toast is a presentation of something that has
     already happened; if the client dies mid-animation the pack is still
     banked. ]]
function Rewards:Resolve(kill)
  if not self.collection then return end
  -- the bad-luck floor (Drops.DRY_LIMIT), saved with the character
  local ch = self.collection.character
  if ns.Drops.Owed(kill, ch.dryKills) then kill.guaranteed = true end
  local reward = ns.Drops.Roll(kill)
  ch.dryKills = ns.Drops.AfterKill(kill, ch.dryKills, reward)
  if not reward then return end

  local granted = ns.Drops.Grant(self.collection, reward)
  if not granted then return end

  self.unsaved = self.unsaved + 1
  self:NagIfUnsaved()
  self.onReward(granted)
end

--[[ Levelling up grants class cards. It calls the same function as login does,
     because grants are a FUNCTION OF LEVEL and never an event -- a character
     that levelled with the addon disabled must still get its cards. ]]
function Rewards:OnLevelUp(level)
  if not self.collection then return end
  local _, class = UnitClass("player")
  level = level or (UnitLevel and UnitLevel("player"))
  local before = {}
  for id in pairs(ns.PrintedCards) do before[id] = self.collection:Count(id) end
  local granted = self.collection:GrantForLevel(class, level)
  local summary = {}
  local packs = self.collection:GrantPacksForLevel(level or (UnitLevel and UnitLevel("player")))
  if packs > 0 then
    summary[#summary + 1] = tostring(packs) .. (packs == 1 and " pack" or " packs")
    self.unsaved = self.unsaved + packs
    self.onReward({ kind = "PACK", set = ns.Packs.SETS.HEARTHSTONE, total = self.collection:TotalPacks(),
                    count = packs, fromLevel = true })
  end
  for _, id in ipairs(granted) do
    local p = ns.PrintedCards[id]
    summary[#summary + 1] = tostring(self.collection:Count(id) - (before[id] or 0)) .. "x " .. (p and p.name or id)
  end
  if #summary > 0 then
    self.onPrint(("Level %d rewards: %s. Added automatically."):format(level, table.concat(summary, "; ")))
  end
  if #granted == 0 then return end
  self.unsaved = self.unsaved + #granted
  for _, id in ipairs(granted) do
    local p = ns.PrintedCards[id]
    self.onReward({ kind = "CARD", cardId = id, rarity = p and p.rarity or "FREE",
                    fromLevel = true })
  end
end

-- ========================================================== persistence

--[[ SavedVariables are written on logout or /reload and at no other time, so
     everything earned this session lives only in memory. Nothing can force a
     write. What can be done is to stop it being a surprise. ]]
function Rewards:NagIfUnsaved()
  if self.unsaved < UNSAVED_NAG then return end
  if self.nagged then return end
  self.nagged = true
  self:PrintUnsaved()
end

function Rewards:PrintUnsaved()
  self.onPrint(("%d rewards are still only in memory. WoW writes them to disk on logout or /reload -- /fh save reloads your UI to save now.")
               :format(self.unsaved))
end

--[[ The only flush there is. Reloading the UI writes SavedVariables, so this
     is not a workaround for the lack of a save API -- it IS the save API,
     spelled inconveniently. ]]
function Rewards:Save()
  self.unsaved = 0
  self.nagged = false
  if ReloadUI then ReloadUI() end
end

function Rewards:OnLogout()
  --[[ A clean exit writes everything. The flag is what lets the NEXT login tell
       the player that the previous session ended in a crash, rather than
       leaving them to wonder where three packs went. ]]
  if self.db then self.db.cleanExit = true end
  self.unsaved = 0
end

--[[ Called at login with the account table. Returns a message if the last
     session did not end cleanly, so the player is told rather than left to
     notice. ]]
function Rewards:CheckLastSession(db)
  self.db = db
  local dirty = (db.cleanExit == false)
  db.cleanExit = false                -- assume a crash until logout says otherwise
  if not dirty then return nil end
  return "the last session ended without logging out -- anything earned after its last /reload was lost. WoW only writes addon data on logout."
end

return Rewards
