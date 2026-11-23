--[[ Client/BotNames.lua

  NAMES FOR LADDER OPPONENTS (docs/45). A ladder bot is named like a player,
  in its class's flavour and its rank's style:

    ranks 25-16   new players:  playful handles with numbers -- Pyrokid42,
                                xBladeBoy, MurlocLover7
    ranks 15-6    climbers:     a root and a title -- FrostWarden, ShadeRunner
    ranks 5-1     contenders:   one crafted word -- Frostbinder, Nightvein
    Legend        the top:      short, clean tags -- Vael, Kroth, Ysra

  Every name is invented: none is a real player's (no professional or
  streamer handles). Pure Lua, no WoW API; the roll is passed in.
]]
local ADDON, ns = ...

local BotNames = {}
ns.BotNames = BotNames

-- Per class: roots (the class's flavour), titles (climbers), crafted words
-- (contenders), and Legend tags.
BotNames.CLASSES = {
  MAGE = {
    roots = { "Pyro", "Frost", "Arcane", "Blink", "Ember", "Rune", "Sheep", "Mana", "Flame", "Ice" },
    titles = { "Weaver", "Warden", "Caller", "Scholar", "Drift", "Storm", "Spark", "Sage" },
    crafted = { "Frostbinder", "Emberwake", "Runesight", "Spellvane", "Glacius", "Pyrelight", "Aethis", "Starquill" },
    legend = { "Vael", "Isen", "Kyra", "Oriel", "Thessa", "Quill", "Solis", "Wynn", "Aster", "Riel" },
  },
  WARRIOR = {
    roots = { "Axe", "Shield", "Rage", "Brawl", "Iron", "Grom", "Bash", "War", "Steel", "Slam" },
    titles = { "Breaker", "Guard", "Fist", "Hammer", "Wall", "Crusher", "Brand", "Blade" },
    crafted = { "Ironhide", "Shieldwall", "Bloodfang", "Warborn", "Stonebrow", "Gorehelm", "Battlescar", "Axebrand" },
    legend = { "Kroth", "Garn", "Brakka", "Torv", "Ulda", "Rask", "Hrolf", "Dagna", "Moru", "Vane" },
  },
  HUNTER = {
    roots = { "Arrow", "Beast", "Hawk", "Trap", "Wolf", "Hound", "Bow", "Hunt", "Snake", "Raptor" },
    titles = { "Tracker", "Stalker", "Shot", "Ranger", "Fang", "Call", "Eye", "Trail" },
    crafted = { "Swiftarrow", "Wildmane", "Hawkeye", "Thornstep", "Duskfang", "Longshot", "Packleader", "Huntwind" },
    legend = { "Ash", "Kael", "Rhen", "Sable", "Tarn", "Vix", "Lark", "Fenn", "Orrin", "Kestra" },
  },
  PALADIN = {
    roots = { "Light", "Holy", "Divine", "Bless", "Silver", "Dawn", "Shield", "Judge", "Lord", "Sun" },
    titles = { "Bringer", "Oath", "Hand", "Guard", "Vow", "Knight", "Crest", "Grace" },
    crafted = { "Dawnshield", "Lightsworn", "Silverhand", "Sunvow", "Brightoath", "Valorheart", "Truthbearer", "Haloguard" },
    legend = { "Aurel", "Seren", "Talin", "Liora", "Cael", "Brannoch", "Elda", "Halric", "Iona", "Varric" },
  },
  PRIEST = {
    roots = { "Shadow", "Halo", "Mind", "Heal", "Faith", "Psy", "Prayer", "Soul", "Void", "Grace" },
    titles = { "Mender", "Whisper", "Voice", "Seer", "Light", "Veil", "Chant", "Ward" },
    crafted = { "Soulmender", "Voidwhisper", "Mindveil", "Graceborn", "Lightchant", "Shadesong", "Hallowmind", "Psalmweaver" },
    legend = { "Ysra", "Noct", "Elun", "Sorin", "Mara", "Vesp", "Calyx", "Ilse", "Theron", "Auda" },
  },
  ROGUE = {
    roots = { "Blade", "Shade", "Sneak", "Dagger", "Combo", "Poison", "Shiv", "Stab", "Gold", "Cut" },
    titles = { "Runner", "Step", "Edge", "Strike", "Cloak", "Fingers", "Shadow", "Knife" },
    crafted = { "Nightvein", "Quickblade", "Silentstep", "Duskdagger", "Shadowcut", "Coinflip", "Venomkiss", "Backstab" },
    legend = { "Vex", "Nyx", "Rook", "Sly", "Kade", "Wren", "Corvo", "Jinx", "Talon", "Mire" },
  },
  SHAMAN = {
    roots = { "Totem", "Storm", "Earth", "Bolt", "Wind", "Spirit", "Lava", "Tide", "Hex", "Thunder" },
    titles = { "Caller", "Speaker", "Shaper", "Fury", "Walker", "Song", "Root", "Surge" },
    crafted = { "Stormcaller", "Earthsong", "Tidebinder", "Thunderhoof", "Lavaborn", "Windspeaker", "Spiritroot", "Hexbolt" },
    legend = { "Thrae", "Oro", "Kesh", "Vola", "Duru", "Zan", "Akona", "Raku", "Tuli", "Mesa" },
  },
  WARLOCK = {
    roots = { "Fel", "Doom", "Hex", "Void", "Soul", "Demon", "Dark", "Curse", "Gul", "Imp" },
    titles = { "Binder", "Caller", "Pact", "Flame", "Lord", "Brand", "Shard", "Seal" },
    crafted = { "Felbinder", "Soulshard", "Doomcaller", "Hexblood", "Voidpact", "Darkbrand", "Infernus", "Shadowseal" },
    legend = { "Malk", "Zeth", "Varo", "Kazr", "Morr", "Ixa", "Vile", "Sorrow", "Nekra", "Hask" },
  },
  DRUID = {
    roots = { "Leaf", "Moon", "Claw", "Grove", "Star", "Bark", "Wild", "Root", "Bear", "Thorn" },
    titles = { "Keeper", "Heart", "Shaper", "Bloom", "Walker", "Song", "Guard", "Branch" },
    crafted = { "Moonbloom", "Wildheart", "Thornkeeper", "Starbark", "Grovewarden", "Rootshaper", "Clawmoon", "Leafsong" },
    legend = { "Faen", "Sylva", "Oren", "Ilyr", "Tavi", "Bryn", "Moss", "Rowan", "Elowen", "Thane" },
  },
}

-- New players' playful wrappers around a root.
local NEW_STYLES = {
  function(r, n) return r .. "kid" .. n end,
  function(r, n) return "x" .. r .. "x" end,
  function(r, n) return r .. "Lover" .. n end,
  function(r, n) return "Lil" .. r end,
  function(r, n) return r .. "Noob" .. n end,
  function(r, n) return r .. "Fan" .. n end,
  function(r, n) return "Mr" .. r .. n end,
  function(r, n) return r .. "y" .. n end,
}

local function defaultRoll(a, b) return math.random(a, b) end
local function pick(list, roll) return list[roll(1, #list)] end

--- The band a rank names in: "new", "climber", "contender" or "legend".
function BotNames.Band(rank)
  rank = tonumber(rank) or 25
  if rank <= 0 then return "legend" end
  if rank <= 5 then return "contender" end
  if rank <= 15 then return "climber" end
  return "new"
end

--[[ A name for a ladder opponent of `class` at `rank`. Names longer than 16
     characters are shortened from the end, so a tag always fits the plate. ]]
function BotNames.Pick(class, rank, roll)
  roll = roll or defaultRoll
  local c = BotNames.CLASSES[class] or BotNames.CLASSES.MAGE
  local band = BotNames.Band(rank)
  local name
  if band == "legend" then
    name = pick(c.legend, roll)
  elseif band == "contender" then
    name = pick(c.crafted, roll)
  elseif band == "climber" then
    name = pick(c.roots, roll) .. pick(c.titles, roll)
  else
    local style = NEW_STYLES[roll(1, #NEW_STYLES)]
    name = style(pick(c.roots, roll), roll(2, 99))
  end
  return name:sub(1, 16)
end

return BotNames
