-- Match audio prefers locally installed effects and card recordings. Other UI
-- cues resolve named SOUNDKIT entries from the client. User SOUND_PACK entries
-- override generic cues. All playback uses the player's SFX channel.
local ADDON, ns = ...

local Sounds = {}
ns.Sounds = Sounds

--[[ key -> candidate SOUNDKIT names, in preference order.

     Chosen for FUNCTION, not for flavour: a card being placed wants a short
     dry click, a legendary wants a fanfare, the rope wants something with
     urgency. Where the obvious UI sound might not exist under that name, a
     second and third candidate follow it. ]]
Sounds.KEYS = {
  menu_hover = { "IG_MAINMENU_OPTION_CHECKBOX_ON", "IG_MAINMENU_OPTION" },
  menu_click = { "IG_MAINMENU_OPTION", "IG_CHARACTER_INFO_TAB" },
  menu_page = { "IG_ABILITY_PAGE_TURN", "IG_MAINMENU_OPTION" },
  menu_open = { "IG_BACKPACK_OPEN", "IG_MAINMENU_OPTION" },
  --[[ THE MATCH ITSELF.

       These are the keys Choreography actually asks for, and every one of them
       was missing -- the registry defined `play_minion`, `play_spell`, `attack`
       and `impact`, which nothing has ever requested, while PlayMinion asked
       for "summon", Attack asked for "hit" and PlaySpell asked for
       "spell_cast". Silence is a valid render, so nothing failed: a whole match
       simply made no noise, on both sides, and the AI's turn looked broken
       because it was the turn where you noticed.

       tests/test_presentation.lua now asserts that every key the choreography
       requests exists here, which is the only thing that stops the two drifting
       apart again. ]]
  --[[ EVERY LIST ENDS IN A NAME THAT IS CERTAINLY PRESENT.

       These are looked up in the client's own SOUNDKIT table, so a name this
       client does not have costs nothing and the next candidate is tried. But
       a list where NONE of the candidates exists is silent, and silence is a
       valid render -- so a list of nothing but plausible-sounding guesses fails
       quietly and for good. That is what happened: the keys existed, the
       choreography asked for them, and a whole match still made no noise.

       So the evocative candidate comes first and a boring, certainly-present
       one comes last. `/fh sound` plays every key in turn and says which ones
       resolved, which is the only way to turn a guess into a fact. ]]
  summon       = { "IG_CREATURE_NEUTRAL_SELECT", "IG_ABILITY_PAGE_TURN",
                   "IG_MAINMENU_OPTION_CHECKBOX_ON" },
  summon_heavy = { "IG_CREATURE_AGGRO_SELECT", "UI_RAID_BOSS_WHISPER_WARNING",
                   "IG_CHARACTER_INFO_TAB", "IG_MAINMENU_OPTION_CHECKBOX_ON" },
  battlecry    = { "SPELL_SELECT_CLASS_SKILLS", "IG_SPELLBOOK_OPEN",
                   "IG_MAINMENU_OPTION" },
  spell_cast   = { "SPELL_SELECT_CLASS_SKILLS", "IG_SPELLBOOK_OPEN",
                   "IG_CHARACTER_INFO_TAB", "IG_MAINMENU_OPTION" },
  hit          = { "IG_PLAYER_INVITE_DECLINE", "U_CHAT_SCROLL_BUTTON",
                   "IG_MAINMENU_OPTION_CHECKBOX_ON" },
  hit_lethal   = { "UI_RAID_BOSS_WHISPER_WARNING", "IG_QUEST_FAILED",
                   "IG_BACKPACK_OPEN", "IG_MAINMENU_OPTION" },
  minion_death = { "IG_QUEST_FAILED", "IG_MAINMENU_QUIT",
                   "IG_ABILITY_PAGE_TURN", "IG_MAINMENU_OPTION" },

  -- playing cards
  play_minion  = { "IG_MAINMENU_OPTION_CHECKBOX_ON", "U_CHAT_SCROLL_BUTTON" },
  play_spell   = { "SPELL_SELECT_CLASS_SKILLS", "IG_SPELLBOOK_OPEN" },
  card_deal    = { "IG_BACKPACK_COIN_RUB", "U_CHAT_SCROLL_BUTTON" },
  impact       = { "IG_MAINMENU_OPTION_CHECKBOX_ON" },
  attack       = { "IG_PLAYER_INVITE_DECLINE", "UI_RAID_BOSS_WHISPER_WARNING" },

  -- the rope
  rope_start   = { "UI_RAID_BOSS_WHISPER_WARNING", "IG_QUEST_LOG_ABANDON_QUEST" },
  rope_end     = { "IG_QUEST_FAILED", "IG_MAINMENU_QUIT" },

  -- drops, out in the world
  pack_drop    = { "IG_BACKPACK_COIN_RUB", "IG_BACKPACK_OPEN" },
  setcard_drop = { "IG_QUEST_LIST_COMPLETE", "IG_QUEST_LOG_OPEN" },
  golden_drop  = { "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },

  -- opening a pack
  pack_crack   = { "IG_BACKPACK_OPEN", "IG_CHARACTER_INFO_OPEN" },
  card_reveal  = {
    --[[ THE ESCALATION. Five distinct sounds, not one played five times: the
         rise across a pack is most of what makes opening one feel like an
         event, and this is the only way to fake a pitch ramp. ]]
    "IG_MAINMENU_OPTION_CHECKBOX_ON",
    "IG_MAINMENU_OPTION",
    "IG_CHARACTER_INFO_TAB",
    "IG_SPELLBOOK_OPEN",
    "IG_QUEST_LIST_COMPLETE",
  },
  rarity_rare      = { "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
  rarity_epic      = { "UI_EPICLOOT_TOAST", "IG_QUEST_LIST_COMPLETE" },
  rarity_legendary = { "UI_LEGENDARY_LOOT_TOAST", "UI_EPICLOOT_TOAST" },
  legendary        = { "UI_LEGENDARY_LOOT_TOAST", "LEVELUP" },
  golden_reveal    = { "UI_EPICLOOT_TOAST" },
  rarity_tell_rare      = { "IG_MAINMENU_OPTION" },
  rarity_tell_epic      = { "IG_MAINMENU_OPTION" },
  rarity_tell_legendary = { "UI_EPICLOOT_TOAST" },

  -- crafting
  craft      = { "IG_ABILITY_PAGE_TURN", "ITEM_REPAIR" },
  disenchant = { "ITEM_REPAIR", "IG_ABILITY_PAGE_TURN" },
}

--[[ HEARTHSTONE'S OWN INTERFACE SOUNDS (tools/import_ui_sounds.py), which
     beat every SOUNDKIT guess above. A list rotates between recordings.
     `false` is a deliberate silence: a legendary reveal asks for a rarity
     burst AND a fanfare, and Hearthstone has one stinger, which lands on the
     fanfare after the beat of silence. ]]
local UI_DIR = "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\UI\\"

--[[ THE MUTE. Every noise this addon makes passes through playFile or playKit,
     so the board's speaker button (and `/fh mute`) is one saved flag checked
     in one place. Music is gated separately in Main:Music. ]]
function Sounds.Muted()
  local db = _G and rawget(_G, "ForeverHearthstoneDB")
  return type(db) == "table" and db.muted == true
end
function Sounds.SetMuted(muted)
  local db = rawget(_G, "ForeverHearthstoneDB")
  if type(db) == "table" then db.muted = muted and true or nil end
end
--[[ THE VOLUME. PlaySoundFile and PlaySound take no volume, so a sound's
     loudness is its file's and its CHANNEL's. This addon's effects and voices
     play on WoW's Sound Effects channel and its music on the Music channel,
     so the slider sets BOTH -- it moved only Sound Effects at first, and at
     the main menu, where the theme is most of what you hear, it seemed to do
     nothing. These are WoW's own settings (its Sound options show the same
     values), not a second, hidden volume. ]]
local VOLUME_CVAR = "Sound_SFXVolume"
local VOLUME_CVARS = { "Sound_SFXVolume", "Sound_MusicVolume" }
local function getCVar(name)
  local c = rawget(_G, "C_CVar")
  if type(c) == "table" and c.GetCVar then return c.GetCVar(name) end
  local g = rawget(_G, "GetCVar")
  return g and g(name)
end
local function setCVar(name, value)
  local c = rawget(_G, "C_CVar")
  if type(c) == "table" and c.SetCVar then return c.SetCVar(name, value) end
  local g = rawget(_G, "SetCVar")
  if g then return g(name, value) end
end
function Sounds.Volume()
  local v = tonumber(getCVar(VOLUME_CVAR))
  return v and math.max(0, math.min(1, v)) or 1
end
function Sounds.SetVolume(v)
  v = math.max(0, math.min(1, tonumber(v) or 0))
  local db = rawget(_G, "ForeverHearthstoneDB")
  for _, cvar in ipairs(VOLUME_CVARS) do
    if cvar == "Sound_MusicVolume" and type(db) == "table" and db.mutedMusicVolume then
      db.mutedMusicVolume = ("%.2f"):format(v)   -- the level to return to on unmute
    else
      setCVar(cvar, ("%.2f"):format(v))
    end
  end
  return v
end

--[[ MUTING THE MUSIC WITHOUT STOPPING IT. WoW cannot pause music: StopMusic
     and PlayMusic start the track over, so the mute used to cut the theme and
     unmuting began it again from the top. Instead the track keeps playing and
     the Music channel is turned to 0, then back to where it was.

     That is WoW's own setting, so it must never be left at 0 by us: the level
     it had is kept in the saved variables while it is silenced, restored the
     moment our music hands back to the zone's, on logout, and on the next
     login if the client died with it silenced. ]]
function Sounds.SilenceMusic(on)
  local db = rawget(_G, "ForeverHearthstoneDB")
  if type(db) ~= "table" then return end
  if on and not db.mutedMusicVolume then
    db.mutedMusicVolume = tostring(getCVar("Sound_MusicVolume") or "1")
    setCVar("Sound_MusicVolume", "0")
  elseif not on and db.mutedMusicVolume then
    -- if the player set the Music volume in WoW's options meanwhile, theirs wins
    local now = tonumber(getCVar("Sound_MusicVolume") or "0") or 0
    if now <= 0 then setCVar("Sound_MusicVolume", db.mutedMusicVolume) end
    db.mutedMusicVolume = nil
  end
end

-- Returns what PlaySoundFile does (willPlay, handle), or false when muted.
local function playFile(path)
  if Sounds.Muted() or not PlaySoundFile then return false end
  return PlaySoundFile(path, "SFX")
end
local function playKit(id)
  if Sounds.Muted() or not PlaySound then return false end
  return PlaySound(id, "SFX")
end
Sounds.PlayFile = playFile
Sounds.UI_FILES = {
  menu_hover = "menuselect.mp3", menu_click = "menubtnpress.mp3", menu_open = "openmenu.mp3",
  card_hover = "cardhover.mp3",
  -- a soft swish at -18 dBFS; whoosh.ogg is a full-scale sweep (build_draw_sound.py)
  card_deal = "draw.wav",
  your_turn  = "playerturn.mp3", end_turn = "endturn.mp3",
  -- The rope burns out into the turn ending; heropower/bigattack: docs/12.
  rope_end = "endturn.mp3", hero_power = "heropower.mp3", big_hit = "bigattack.mp3",
  -- one continuous burning hiss the length of a rope (tools/build_rope_sound.py)
  rope_burn = "rope-burn.wav",
  pack_crack = "openpack.mp3",
  rarity_rare = "rare.mp3", rarity_epic = "epic.mp3",
  rarity_legendary = false, legendary = "legendary.mp3",
  golden_free = "goldencommon.mp3", golden_common = "goldencommon.mp3",
  golden_rare = "goldenrare.mp3", golden_epic = "goldenepic.mp3",
  golden_legendary = "goldenlegendary.mp3",
  innkeeper = { "innkeeper_1.mp3", "innkeeper_2.mp3", "innkeeper_3.mp3" },
}
--[[ Hearthstone recordings in Art/Sounds/Cards played for a KEY rather than a
     card (tools/import_match_sounds.py). No source carries Hearthstone's rope
     sizzle or its defeat music, so: the rope is announced by the active hero's
     own "Out of Time" line (Board:StartRopeAudio) over a lit fuse; a defeat is
     the losing hero's own death line (Board:PlayHeroDeath) over one of
     Hearthstone's stingers. ]]
local CARDS_DIR = "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Cards\\"
Sounds.CARD_FILES = {
  rope_start = "Fuse_Underlay_Play",
  hero_crack = "UNG_Egg_Cracks", hero_shatter = "GlassShatter_Underlay_Death",
  defeat = "Pegasus_Stinger_Undead1",
  --[[ Victory is a classic-era stinger too, not victory.mp3 -- that is the
       modern game's long track, with the Lich King calling you "champion",
       which is from an expansion this addon does not have. ]]
  victory = "Pegasus_Stinger_Alliance",
  -- a card burned by a full hand catches fire (Hearthstone's fire underlay)
  card_burn = "Fire_Underlay_Play",
}
for key in pairs(Sounds.UI_FILES) do
  Sounds.KEYS[key] = Sounds.KEYS[key] or {}
end
for key in pairs(Sounds.CARD_FILES) do
  Sounds.KEYS[key] = Sounds.KEYS[key] or {}
end
--[[ Played UNDER a key rather than instead of it. A pack reveal keeps its
     rising five-step escalation (docs/06 §6.3 -- the pitch ramp WoW cannot do
     natively) and gains Hearthstone's own card flip beneath every step. ]]
Sounds.UI_LAYERS = { card_reveal = "flipcard.mp3" }

--[[ Resolve a candidate name to whatever PlaySound wants.

     `SOUNDKIT` is the client's own table. A name it does not have returns nil
     and this key stays silent -- which is why a wrong guess here costs nothing,
     and why none of these numbers are written down anywhere in this project. ]]
local function kitId(name)
  local kit = _G and rawget(_G, "SOUNDKIT")
  if type(kit) ~= "table" then return nil end
  return kit[name]
end

-- Presentation-only counters never consume gameplay randomness.
local selections,heroVoices={},{}
local lastVoice = {}   -- hero card id -> GetTime() of its last line
local lastCardHover
function Sounds.ResetMatch()
  selections,heroVoices,lastVoice,lastCardHover={},{},{},nil
end
local function nextChoice(key,count)
  local i=(selections[key] or 0)%count+1
  selections[key]=i
  return i
end
--[[ A minion with no recording of its own lands with Hearthstone's generic
     card-on-table thud; a heavy one adds a wooden impact underneath, so a
     Boulderfist Ogre still lands harder than a Wisp. ]]
local function placementPath(heavy)
  if not heavy then return UI_DIR .. "cardplace.mp3" end
  local i=nextChoice("placement:heavy",5)-1
  return "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Placement\\impactWood_heavy_"..string.format("%03d",i)..".ogg"
end
function Sounds.PlayPlacement(heavy)
  if not PlaySoundFile then return false end
  if heavy then playFile(UI_DIR .. "cardplace.mp3", "SFX") end
  return playFile(placementPath(heavy),"SFX") ~= false
end
function Sounds.PlayHeroAttack(cardId)
  local now=GetTime and GetTime() or 0
  local state=heroVoices[cardId] or {swings=0}
  state.swings=state.swings+1
  heroVoices[cardId]=state
  -- Base heroes have one attack recording. Keep combat effects on every swing,
  -- but speak at most once in three swings and never within twelve seconds.
  if state.last and (state.swings<3 or now-state.last<12) then return false end
  state.last,state.swings=now,0
  return Sounds.PlayCard("attack",cardId)
end

--[[ THE HERO SPEAKS. Emotes, the opening line, "I need more mana" -- the
     voice that makes a Hearthstone board feel inhabited.

     `heroCardId` is whoever is currently the hero (a replaced hero such as
     Lord Jaraxxus has no lines and stays quiet). One line at a time per hero,
     and error lines at most every 1.5s: clicking a sleeping minion five times
     is one "that minion needs a turn to get ready", not a chorus. Emotes are
     deliberate and already rate-limited where they are sent, so `force`
     skips the cooldown. ]]
function Sounds.PlayHero(heroCardId, key, force)
  local lines = ns.HeroVoice and ns.HeroVoice[heroCardId or ""]
  local clip = lines and lines[key]
  if not clip or not PlaySoundFile then return false end
  local now = GetTime and GetTime() or 0
  local last = lastVoice[heroCardId]
  if not force and last and now - last < 1.5 then return false end
  lastVoice[heroCardId] = now
  return playFile("Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Heroes\\" .. clip .. ".wav", "SFX") ~= false
end

-- The base hero of a class, read from printed data rather than written down.
function Sounds.HeroForClass(class)
  return ns.HERO_ID_BY_CLASS and ns.HERO_ID_BY_CLASS[class]
end

--[[ The function Board.lua and the collection screen call.

     Returns: id, isFile
       id     a SOUNDKIT id, or a file path from an asset pack
       isFile true when it is a path and needs PlaySoundFile

     nil means silence, and silence is always acceptable. ]]
function Sounds.For(key, step)
  if not key then return nil end

  -- User-provided generic cues override the installed effect beds.
  local pack = ns.SOUND_PACK
  local fromPack = pack and pack[key]
  if type(fromPack) == "table" then
    fromPack = fromPack[math.min(step or 1, #fromPack)]
  end
  if type(fromPack) == "string" then return fromPack, true end
  if type(fromPack) == "number" then return fromPack, false end
  local recorded = Sounds.CARD_FILES[key]
  if recorded then return CARDS_DIR .. recorded .. ".wav", true end
  local ui = Sounds.UI_FILES[key]
  if ui == false then return nil end
  if type(ui) == "table" then ui = ui[nextChoice("ui:" .. key, #ui)] end
  if ui then return UI_DIR .. ui, true end
  if key=="menu_hover" or key=="menu_click" or key=="menu_page" or key=="menu_open" then
    return "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\"..key..".wav",true
  end

  if key=="summon" or key=="summon_heavy" or key=="play_minion" then return placementPath(key=="summon_heavy"),true end
  local matchCue={summon="summon",summon_heavy="summon",battlecry="spell",
    spell_cast="spell",hit="impact",hit_lethal="impact",minion_death="death",
    play_minion="summon",play_spell="spell",attack="impact",impact="impact",card_deal="card"}
  if matchCue[key] then
    local recorded=ns.MatchRecordings and ns.MatchRecordings[matchCue[key]]
    if recorded then return "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Cards\\"..recorded..".wav",true end
    return "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\"..matchCue[key]..".wav",true
  end
  local candidates = Sounds.KEYS[key]
  if not candidates then return nil end

  --[[ For an escalating key, `step` picks the entry. For every other key the
       list is preference order and step is meaningless, so it is only used when
       the caller supplied one AND the list is long enough to be an escalation.
       Getting this backwards would make every sound in the game the fifth
       candidate of its list. ]]
  if step and #candidates >= 3 and key == "card_reveal" then
    local name = candidates[math.min(step, #candidates)]
    local id = kitId(name)
    if id then return id, false end
  end

  for _, name in ipairs(candidates) do
    local id = kitId(name)
    if id then return id, false end
  end
  local cue = "card"
  if key:find("summon") or key == "play_minion" then cue = "summon"
  elseif key:find("death") or key == "disenchant" then cue = "death"
  elseif key:find("hit") or key == "impact" or key == "attack" then cue = "impact"
  elseif key:find("spell") or key == "battlecry" then cue = "spell"
  elseif key:find("rope") then cue = "rope"
  elseif key:find("pack") then cue = "pack"
  elseif key:find("rarity") or key:find("golden") or key == "legendary" then cue = "reward" end
  return "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\" .. cue .. ".wav", true
end

--[[ Play one. The only function in the project that makes a noise, so the
     "never play over combat at full volume" rule lives in exactly one place:
     everything goes to the SFX channel, which the player already controls with
     WoW's own sliders. Deliberately NOT the Master channel -- an addon that
     ignores the sound options is an addon people uninstall. ]]
function Sounds.Play(key, step)
  local layer = Sounds.UI_LAYERS[key or ""]
  if layer and PlaySoundFile and not (ns.SOUND_PACK and ns.SOUND_PACK[key]) then
    playFile(UI_DIR .. layer, "SFX")
  end
  local id, isFile = Sounds.For(key, step)
  if not id then return false end
  -- the handle comes back so a long sound can be stopped (Sounds.Stop)
  local _, handle
  if isFile then
    if PlaySoundFile then _, handle = playFile(id, "SFX") end
  else
    _, handle = playKit(id)
  end
  return true, handle
end
function Sounds.Stop(handle, fadeMs)
  if handle and StopSound then StopSound(handle, fadeMs or 300) end
end
--[[ Is a started sound still going? True when the client cannot say (no
     C_Sound.IsPlaying), so a caller that relights on false never doubles up. ]]
function Sounds.IsPlaying(handle)
  if not handle then return false end
  local api = rawget(_G, "C_Sound")
  if not (api and api.IsPlaying) then return true end
  return api.IsPlaying(handle) and true or false
end

-- Crossing a grid of buttons should remain a quiet interaction, not a chorus.
local lastMenuHover
function Sounds.PlayMenuHover()
  local now=GetTime and GetTime() or 0
  if lastMenuHover and now>=lastMenuHover and now-lastMenuHover<.12 then return false end
  lastMenuHover=now
  return Sounds.Play("menu_hover")
end

-- Sweeping across a hand ticks once per card, never faster than the eye moves.
function Sounds.PlayCardHover()
  local now=GetTime and GetTime() or 0
  if lastCardHover and now>=lastCardHover and now-lastCardHover<.06 then return false end
  lastCardHover=now
  return Sounds.Play("card_hover")
end

-- Distinct original effect beds cover cards whose historical recording is unavailable.
function Sounds.EffectFor(cardId)
  local card=ns.PrintedCards and ns.PrintedCards[cardId]
  if not card then return "spell" end
  local name=(card.name or ""):lower()
  if card.type == "WEAPON" then return "weapon" end
  --[[ Whole words: "ice" used to match Sacrif-ICE and Noble Sacrif-ICE, and
       "fire" Spit-FIRE-less things; %f is Lua's word frontier. ]]
  local function word(w) return name:find("%f[%a]" .. w .. "%f[%A]") ~= nil end
  if word("frost") or word("frostbolt") or word("freeze") or word("freezing") or word("blizzard")
     or word("ice") or word("icy") then return "frost" end
  if word("fire") or word("fireball") or word("flame") or word("flamestrike") or word("fireblast")
     or word("hellfire") then return "fire" end
  if word("arcane") or word("polymorph") then return "arcane" end
  local class={PRIEST="holy",PALADIN="holy",WARLOCK="shadow",DRUID="nature",SHAMAN="nature",HUNTER="arrow",ROGUE="weapon",WARRIOR="weapon",MAGE="arcane"}
  return class[card.class] or "spell"
end

--[[ HERO POWERS. HearthSFX has no hero-power recordings, so every power used
     to fall through to its class's generic spell underlay (Armor Up clanged
     like a sword). Now: Hearthstone's own hero-power activation, with the
     underlay that matches what the power IS on top. A replaced hero's power
     (Inferno!, a Jaraxxus) keeps the old card-sound path. ]]
Sounds.HERO_POWER_UNDERLAY = {
  CS2_102 = "Armor_Type_A_Play_Underlay",   -- Armor Up!
  CS2_083b = "Dagger_Underlay_Play",        -- Dagger Mastery
  CS2_034 = "fire",   CS1h_001 = "holy",  CS2_101 = "holy",   CS2_056 = "shadow",
  DS1h_292 = "arrow", CS2_049 = "nature", CS2_017 = "nature",
}
function Sounds.PlayHeroPower(cardId)
  local under = Sounds.HERO_POWER_UNDERLAY[cardId or ""]
  if not under then return Sounds.PlayCard("summon", cardId, "spell_cast") end
  Sounds.Play("hero_power")
  local file = ns.MatchRecordings and ns.MatchRecordings[under] or under
  return playFile(CARDS_DIR .. file .. ".wav") ~= false
end

-- Card recordings are installed locally, so playback does not depend on networking.
--[[ A minion's play, attack or death recording runs one to three seconds and
     plays to its end, even when the next card lands over it: Hearthstone never
     cuts a voice line short. (Cutting it when the bot's next action began read
     as audio dropping out.) The handles are kept so Sounds.CutCardAudio can
     silence them all at once. ]]
local cardHandles = {}
local function playCardFile(path)
  local ok, handle = playFile(path)
  if handle then
    cardHandles[#cardHandles + 1] = handle
    -- a line lasts seconds; only the latest few can still be playing
    if #cardHandles > 16 then table.remove(cardHandles, 1) end
  end
  return ok
end
function Sounds.CutCardAudio(fadeMs)
  for _, handle in ipairs(cardHandles) do
    if StopSound then StopSound(handle, fadeMs or 200) end
  end
  cardHandles = {}
end

function Sounds.PlayCard(kind,cardId,fallback)
  local entry=ns.CardSounds and ns.CardSounds[cardId]
  local clip=entry and entry[kind]
  if clip and PlaySoundFile then
    local played=false
    local variants=ns.CardSoundVariants and ns.CardSoundVariants[cardId]
    variants=variants and variants[kind]
    for i,name in ipairs(type(clip)=="table" and clip or {clip}) do
      local options=variants and variants[i]
      if options and #options>0 then name=options[nextChoice(cardId..":"..kind..":"..i,#options)] end
      local ok=playCardFile("Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Cards\\"..name..".wav")
      if ok ~= false then played=true end
    end
    if played then return true end
  end
  local printed=ns.PrintedCards and ns.PrintedCards[cardId]
  -- the classic minions HearthSFX lacks, from Rymedy/hearthstone-web (docs/13)
  local extra=kind=="summon" and ns.CardPlaySounds and ns.CardPlaySounds[cardId]
  if extra and PlaySoundFile then
    local played=false
    for _,name in ipairs(extra) do
      if playCardFile("Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Cards\\"..name) ~= false then played=true end
    end
    if played then Sounds.PlayPlacement((printed and printed.cost or 0)>=5); return true end
  end
  if kind=="summon" and printed and printed.type=="MINION" then
    return Sounds.PlayPlacement((printed.cost or 0)>=5)
  end
  if fallback == "spell_cast" and PlaySoundFile then
    local effect=Sounds.EffectFor(cardId)
    local recorded=ns.MatchRecordings and (ns.MatchRecordings[effect] or ns.MatchRecordings.arcane)
    local file=recorded and ("Cards\\"..recorded) or effect
    return playFile("Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\"..file..".wav","SFX") ~= false
  end
  return fallback and Sounds.Play(fallback) or false
end

--[[ The old name Board.lua called before this file existed. Kept as the single
     entry point so there is one place a sound can come from. ]]
ns.SoundFor = Sounds.For

--[[ Coverage, for `/fh assets`: how many keys this client can actually play.
     The number that says whether the game will have any audio at all. ]]
function Sounds.Coverage()
  local have, total = 0, 0
  for key in pairs(Sounds.KEYS) do
    total = total + 1
    if Sounds.For(key) then have = have + 1 end
  end
  return have, total
end

--[[ The keys a MATCH needs. `/fh sound` walks these, because "37 of 40 keys
     resolve" is not an answer to "why is my game silent" -- the three that do
     not might be every sound a turn makes. ]]
Sounds.MATCH_KEYS = {
  "summon", "summon_heavy", "battlecry", "spell_cast",
  "hit", "hit_lethal", "minion_death", "rope_start", "rope_end",
}

--[[ Report, for each key, which candidate this client actually has -- or that
     none of them resolved. This is the only way to find out: SOUNDKIT is the
     client's own table, we cannot see it from outside the game, and PlaySound
     on a bad id fails silently exactly like a good id playing quietly. ]]
function Sounds.Report(keys)
  local out = {}
  for _, key in ipairs(keys or Sounds.MATCH_KEYS) do
    local found
    for _, name in ipairs(Sounds.KEYS[key] or {}) do
      local kit = _G and rawget(_G, "SOUNDKIT")
      if type(kit) == "table" and kit[name] then found = name break end
    end
    local path, isFile = Sounds.For(key); if isFile then found = path end
    out[#out + 1] = { key = key, name = found }
  end
  return out
end

return Sounds
