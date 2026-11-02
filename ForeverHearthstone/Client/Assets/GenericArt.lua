--[[ Client/Assets/GenericArt.lua

  THE DOZEN ICONS THAT MAKE THE WHOLE GAME LOOK DELIBERATE.

  683 art slots need filling and nobody is going to author 683 icons. But the
  difference between "every card is a question mark" and "every card has an icon
  that suits its class and type" is almost all of the perceived difference, and
  it is about twenty entries.

  ======================================================= THE HONESTY PROBLEM

  docs/06 sets a hard rule, and it is the right one: NO ICON PATH IN THIS
  PROJECT IS AUTHORED FROM MEMORY. There is no API that can tell us whether a
  texture exists -- SetTexture on a bad path draws nothing and reports success --
  so a wrong path is invisible to the addon and to every test we can write.

  The paths below are therefore CANDIDATES, not facts. They are the vanilla-era
  icon names this kind of art usually lives under, and every one of them may be
  wrong. What makes shipping them acceptable is the other half of this file:
  `/fh icons` puts every candidate on screen at its real size, next to what it
  is for, so a human can see in about thirty seconds which ones are blank and
  tick them off. The result is written to SavedVariables and beats the
  candidates from then on.

  That is the only verification that exists for this class of data: an eye. So
  the job is not to guess well, it is to make checking cheap.

  ======================================================== WHAT IT RESOLVES

  Client/Assets/Resolver.lua looks up generic art in this order:

      generic[TYPE .. "_" .. CLASS]     Spell_MAGE
      generic["RACE_" .. RACE]          RACE_BEAST
      generic[TYPE]                     MINION
      generic[CLASS]                    WARLOCK
      generic.DEFAULT

  So a Mage spell finds a Mage-flavoured icon, a Beast finds a beast, and
  anything unrecognised still lands on something rather than a question mark.
  Twenty entries cover 683 slots.
]]
local ADDON, ns = ...

local GenericArt = {}
ns.GenericArt = GenericArt

local ICON = [[Interface\Icons\]]

--[[ CANDIDATES. Every one of these is unverified -- see the header. The names
     are chosen to be the oldest and most stable form of each icon, because a
     texture that has existed since vanilla is the one most likely to still be
     in Forever's data.

     The value of getting one wrong is small and bounded: that slot falls
     through to the question mark, which is exactly where it would have been
     anyway. ]]
GenericArt.CANDIDATES = {
  -- the nine classes, for class cards of any type
  DRUID   = ICON .. "ClassIcon_Druid",
  HUNTER  = ICON .. "ClassIcon_Hunter",
  MAGE    = ICON .. "ClassIcon_Mage",
  PALADIN = ICON .. "ClassIcon_Paladin",
  PRIEST  = ICON .. "ClassIcon_Priest",
  ROGUE   = ICON .. "ClassIcon_Rogue",
  SHAMAN  = ICON .. "ClassIcon_Shaman",
  WARLOCK = ICON .. "ClassIcon_Warlock",
  WARRIOR = ICON .. "ClassIcon_Warrior",

  --[[ THE NINE HEROES and their powers. A hero card's type is HERO and its
       class is one of the nine, so the resolver's most specific lookup --
       TYPE_CLASS -- finds these before anything else. That is 18 entries for
       the two things a player looks at most: the face across the table, and the
       button they press every turn. ]]
  HERO_DRUID   = ICON .. "ClassIcon_Druid",
  HERO_HUNTER  = ICON .. "ClassIcon_Hunter",
  HERO_MAGE    = ICON .. "ClassIcon_Mage",
  HERO_PALADIN = ICON .. "ClassIcon_Paladin",
  HERO_PRIEST  = ICON .. "ClassIcon_Priest",
  HERO_ROGUE   = ICON .. "ClassIcon_Rogue",
  HERO_SHAMAN  = ICON .. "ClassIcon_Shaman",
  HERO_WARLOCK = ICON .. "ClassIcon_Warlock",
  HERO_WARRIOR = ICON .. "ClassIcon_Warrior",

  HERO_POWER_DRUID   = ICON .. "Ability_Druid_Maul",
  HERO_POWER_HUNTER  = ICON .. "Ability_Hunter_SteadyShot",
  HERO_POWER_MAGE    = ICON .. "Spell_Fire_FlameBolt",
  HERO_POWER_PALADIN = ICON .. "Spell_Holy_HolyBolt",
  HERO_POWER_PRIEST  = ICON .. "Spell_Holy_Heal",
  HERO_POWER_ROGUE   = ICON .. "Ability_Rogue_Ambush",
  HERO_POWER_SHAMAN  = ICON .. "Spell_Nature_StrengthOfEarthTotem02",
  HERO_POWER_WARLOCK = ICON .. "Spell_Shadow_LifeDrain02",
  HERO_POWER_WARRIOR = ICON .. "Ability_Warrior_DefensiveStance",

  -- card types, for neutrals and for anything the class lookup misses
  MINION      = ICON .. "INV_Misc_GroupLooking",
  SPELL       = ICON .. "Spell_Holy_MagicalSentry",
  WEAPON      = ICON .. "INV_Sword_04",
  HERO_POWER  = ICON .. "Spell_Holy_PowerWordShield",

  -- the races, which is what makes a board READ at a glance
  RACE_BEAST      = ICON .. "Ability_Hunter_Pet_Bear",
  RACE_DEMON      = ICON .. "Spell_Shadow_SummonImp",
  RACE_DRAGON     = ICON .. "INV_Misc_Head_Dragon_01",
  RACE_MURLOC     = ICON .. "INV_Misc_Fish_02",
  RACE_MECHANICAL = ICON .. "INV_Gizmo_01",
  RACE_PIRATE     = ICON .. "INV_Misc_Bandana_01",
  RACE_TOTEM      = ICON .. "Spell_Nature_StrengthOfEarthTotem02",

  --[[ The last resort, and the ONE path in this project that is not a guess:
       WoW's own canonical missing-icon texture. If everything else here is
       wrong, the game still looks like a game rather than a wall of nothing. ]]
  DEFAULT = ICON .. "INV_Misc_QuestionMark",
}

--[[ What each candidate is for, in words, so the audit screen can say "this is
     the icon every Mage card falls back to" rather than showing a path. The
     person checking these is looking at pictures, not at code. ]]
GenericArt.DESCRIBE = {
  MINION = "any minion with no art of its own",
  SPELL  = "any spell with no art of its own",
  WEAPON = "any weapon",
  HERO_POWER = "hero powers",
  DEFAULT = "everything else (WoW's own missing-icon texture)",
}

--[[ Build the manifest the Resolver consumes, with anything the player has
     marked blank REMOVED rather than overridden.

     Removed, not replaced, because the fallback chain already knows what to do
     with a missing entry -- a blank Mage icon should fall through to the type
     icon, not to the question mark. Deleting the wrong entry gets that for
     free. ]]
function GenericArt.Manifest(saved)
  saved = saved or {}
  local blank = saved.blank or {}
  local generic = {}
  for key, path in pairs(GenericArt.CANDIDATES) do
    if not blank[key] then generic[key] = path end
  end
  --[[ A verified path the player supplied by hand wins over our candidate.
       This is the path an asset pack takes as well. ]]
  for key, path in pairs(saved.generic or {}) do generic[key] = path end
  local cards = {}
  for id, path in pairs(ns.HearthstoneArt or {}) do
    if (ns.PrintedCards or {})[id] then cards[id] = { icon = path } end
  end
  for id, entry in pairs(saved.cards or {}) do cards[id] = entry end
  return { generic = generic, cards = cards }
end

--- The default manifest, for a player who has never checked anything.
GenericArt.MANIFEST = nil       -- built lazily below, once ns.RULES exists

-- ======================================================== verification

--[[ CAN THE CLIENT ANSWER "DOES THIS TEXTURE EXIST"?

     docs/06 says no, and for `SetTexture` that is true -- a bad path draws
     nothing and reports success. But two OTHER calls may be able to answer, and
     the probe (APIProbe/) already asks about both:

       GetFileIDFromPath(path)      -> a file id, or nil for a path the client
                                       does not have
       C_Texture.GetAtlasInfo(name) -> atlas data, or nil

     Neither is confirmed on Forever, so BOTH ARE FEATURE-DETECTED. If they are
     there, the audit becomes automatic and 20 guesses become 20 facts. If they
     are not, nothing changes and a human checks with `/fh icons`, exactly as
     before. This never *asserts* that a texture is missing on a client that
     cannot tell us -- it returns nil for "unknown", which is a third answer and
     the honest one. ]]
function GenericArt.Probe(path)
  if type(path) ~= "string" then return nil end
  local getId = _G and rawget(_G, "GetFileIDFromPath")
  if type(getId) == "function" then
    local ok, id = pcall(getId, path:lower())
    if ok then return (id ~= nil and id ~= 0) end
  end
  local ctex = _G and rawget(_G, "C_Texture")
  if type(ctex) == "table" and type(ctex.GetAtlasInfo) == "function" then
    --[[ Only meaningful for atlas NAMES, not file paths. A path will simply
         come back nil here, which is why this is a second opinion rather than
         the answer. ]]
    local ok, info = pcall(ctex.GetAtlasInfo, path)
    if ok and info then return true end
  end
  return nil          -- unknown: this client cannot tell us
end

--[[ Verify every candidate the client can verify, and record the results.

     Returns checked, blank, unknown. The unknown ones are what `/fh icons`
     exists for -- and on a client with `GetFileIDFromPath`, that list is
     empty and nobody has to look at anything. ]]
function GenericArt.AutoAudit(saved)
  saved = saved or {}
  local checked, blank, unknown = 0, 0, 0
  for key, path in pairs(GenericArt.CANDIDATES) do
    local exists = GenericArt.Probe((saved.generic or {})[key] or path)
    if exists == nil then
      unknown = unknown + 1
    else
      GenericArt.Mark(saved, key, exists)
      checked = checked + 1
      if not exists then blank = blank + 1 end
    end
  end
  return checked, blank, unknown
end

--[[ Class colours, read from WoW rather than asserted.

     RAID_CLASS_COLORS is the client's own table, so this matches whatever
     Forever ships instead of hardcoding vanilla hexes from memory -- the same
     discipline as the icons, applied to something that CAN be read. ]]
function GenericArt.Palette()
  local out = {}
  local src = _G and rawget(_G, "RAID_CLASS_COLORS")
  if not src then return out end
  for _, class in ipairs(ns.CLASSES or {}) do
    local c = src[class]
    if c then out[class] = { c.r, c.g, c.b } end
  end
  return out
end

--[[ The audit list: every candidate, with its key, its path, what it is for,
     and whether the player has already marked it blank. Sorted, so the screen
     is the same shape every time it opens. ]]
function GenericArt.AuditList(saved)
  saved = saved or {}
  local blank = saved.blank or {}
  local out = {}
  for key, path in pairs(GenericArt.CANDIDATES) do
    out[#out + 1] = {
      key = key, path = (saved.generic or {})[key] or path,
      describe = GenericArt.DESCRIBE[key]
                 or (key:match("^RACE_") and ("every " .. key:sub(6):lower()))
                 or ("every " .. key:lower() .. " card"),
      blank = blank[key] or false,
      verified = (saved.verified or {})[key] or false,
    }
  end
  table.sort(out, function(a, b) return a.key < b.key end)
  return out
end

--[[ Record a human's verdict on one candidate. This is the only source of
     truth about whether an icon exists, because it is the only one that
     involved an eye. ]]
function GenericArt.Mark(saved, key, exists)
  saved.blank = saved.blank or {}
  saved.verified = saved.verified or {}
  saved.blank[key] = (not exists) or nil
  saved.verified[key] = true
  return saved
end

--[[ How much of the audit has been done, for the nag in `/fh assets`. An
     unchecked candidate is not a problem -- it is just unknown, and saying so
     is better than implying the art is fine. ]]
function GenericArt.AuditProgress(saved)
  local list = GenericArt.AuditList(saved)
  local checked, blank = 0, 0
  for _, entry in ipairs(list) do
    if entry.verified then checked = checked + 1 end
    if entry.blank then blank = blank + 1 end
  end
  return checked, #list, blank
end

GenericArt.MANIFEST = GenericArt.Manifest({})

return GenericArt
