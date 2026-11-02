--[[ Client/BotDecks.lua

  THE PRACTICE BOT'S DECKS.

  Seven per class, drawn from the decks people actually played across the three
  eras this addon pins: Basic/Classic, Naxxramas and Goblins vs Gnomes. Each has
  a TIER, 1 to 5, which is how strong the list is -- a Basic starter at 1, a
  budget list at 2, a sound ladder deck at 3, a strong meta deck at 4, and the
  list that topped the ladder at 5. The difficulty slider picks the tier.

  Each deck also carries a STYLE -- aggro, midrange or control -- and that is not
  flavour: Client/AI.lua weighs the board by it. An aggro list values your hero's
  health far more than its own; a control list values its life and the board.
  Piloting Face Hunter like Control Warrior is how a bot "plays its deck wrong",
  and the style is what stops it.

  LEGALITY. Every list is a legal Hearthstone deck -- thirty cards, two copies at
  most, one of each legendary, only the class's own cards and neutrals -- and
  tests/test_ai.lua holds every one of them to that, against the pinned card
  data, so a typo'd id or a thirty-first card fails the suite rather than a match.

  NO WoW API. Loads headless with the engine.
]]
local ADDON, ns = ...

local BotDecks = {}
ns.BotDecks = BotDecks

BotDecks.TIERS = 5

--[[ Decks are written as { id = copies } so a list reads like a decklist and a
     count is one number to check. Expand sorts the ids, so the deck handed to
     the game is the same on every client and every run. ]]
local LISTS = {}
local function deck(class, tier, style, name, cards)
  LISTS[class] = LISTS[class] or {}
  local list = LISTS[class]
  list[#list + 1] = { class = class, tier = tier, style = style, name = name, counts = cards }
end

-- ================================================================== DRUID

deck("DRUID", 1, "midrange", "Basic Druid", {
  CS2_008 = 2, -- Moonfire
  CS2_005 = 2, -- Claw
  CS2_009 = 2, -- Mark of the Wild
  CS2_013 = 2, -- Wild Growth
  CS2_007 = 1, -- Healing Touch
  CS2_011 = 2, -- Savage Roar
  CS2_012 = 2, -- Swipe
  EX1_173 = 2, -- Starfire
  CS2_232 = 2, -- Ironbark Protector
  CS2_120 = 2, -- River Crocolisk
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_125 = 2, -- Ironfur Grizzly
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_147 = 2, -- Gnomish Inventor
  CS2_200 = 1, -- Boulderfist Ogre
})

deck("DRUID", 2, "midrange", "Budget Token Druid", {
  EX1_169 = 2, -- Innervate
  EX1_154 = 2, -- Wrath
  EX1_160 = 2, -- Power of the Wild
  CS2_009 = 2, -- Mark of the Wild
  CS2_011 = 2, -- Savage Roar
  CS2_012 = 2, -- Swipe
  FP1_002 = 2, -- Haunted Creeper
  NEW1_019 = 2, -- Knife Juggler
  EX1_556 = 2, -- Harvest Golem
  EX1_025 = 2, -- Dragonling Mechanic
  NEW1_026 = 2, -- Violet Teacher
  EX1_093 = 2, -- Defender of Argus
  EX1_096 = 2, -- Loot Hoarder
  EX1_173 = 2, -- Starfire
  EX1_165 = 2, -- Druid of the Claw
})

deck("DRUID", 3, "control", "Ramp Druid", {
  EX1_169 = 2, -- Innervate
  CS2_013 = 2, -- Wild Growth
  EX1_154 = 2, -- Wrath
  CS2_012 = 2, -- Swipe
  EX1_166 = 2, -- Keeper of the Grove
  FP1_001 = 2, -- Zombie Chow
  EX1_165 = 2, -- Druid of the Claw
  NEW1_008 = 2, -- Ancient of Lore
  EX1_178 = 2, -- Ancient of War
  FP1_012 = 2, -- Sludge Belcher
  EX1_571 = 2, -- Force of Nature
  NEW1_007 = 1, -- Starfall
  EX1_284 = 1, -- Azure Drake
  GVG_096 = 1, -- Piloted Shredder
  EX1_558 = 1, -- Harrison Jones
  EX1_573 = 1, -- Cenarius
  EX1_298 = 1, -- Ragnaros the Firelord
  EX1_572 = 1, -- Ysera
  EX1_016 = 1, -- Sylvanas Windrunner
})

deck("DRUID", 3, "aggro", "Mech Druid", {
  EX1_169 = 2, -- Innervate
  EX1_154 = 2, -- Wrath
  GVG_030 = 2, -- Anodized Robo Cub
  GVG_082 = 2, -- Clockwork Gnome
  GVG_006 = 2, -- Mechwarper
  GVG_085 = 2, -- Annoy-o-Tron
  GVG_044 = 2, -- Spider Tank
  CS2_012 = 2, -- Swipe
  EX1_166 = 2, -- Keeper of the Grove
  GVG_096 = 2, -- Piloted Shredder
  GVG_080 = 2, -- Druid of the Fang
  GVG_034 = 2, -- Mech-Bear-Cat
  GVG_105 = 2, -- Piloted Sky Golem
  CS2_011 = 1, -- Savage Roar
  EX1_571 = 1, -- Force of Nature
  EX1_165 = 1, -- Druid of the Claw
  GVG_110 = 1, -- Dr. Boom
})

deck("DRUID", 4, "midrange", "Token Druid", {
  EX1_169 = 2, -- Innervate
  EX1_154 = 2, -- Wrath
  EX1_160 = 2, -- Power of the Wild
  CS2_011 = 2, -- Savage Roar
  EX1_158 = 2, -- Soul of the Forest
  EX1_571 = 2, -- Force of Nature
  NEW1_026 = 2, -- Violet Teacher
  FP1_002 = 2, -- Haunted Creeper
  EX1_166 = 2, -- Keeper of the Grove
  CS2_012 = 2, -- Swipe
  NEW1_019 = 2, -- Knife Juggler
  GVG_096 = 2, -- Piloted Shredder
  EX1_093 = 2, -- Defender of Argus
  FP1_003 = 1, -- Echoing Ooze
  EX1_597 = 1, -- Imp Master
  EX1_573 = 1, -- Cenarius
  GVG_110 = 1, -- Dr. Boom
})

deck("DRUID", 4, "midrange", "Midrange Druid", {
  EX1_169 = 2, -- Innervate
  CS2_013 = 2, -- Wild Growth
  EX1_154 = 2, -- Wrath
  CS2_012 = 2, -- Swipe
  EX1_166 = 2, -- Keeper of the Grove
  CS2_011 = 2, -- Savage Roar
  EX1_571 = 2, -- Force of Nature
  EX1_165 = 2, -- Druid of the Claw
  NEW1_008 = 2, -- Ancient of Lore
  FP1_012 = 2, -- Sludge Belcher
  EX1_284 = 2, -- Azure Drake
  FP1_001 = 2, -- Zombie Chow
  EX1_178 = 1, -- Ancient of War
  EX1_005 = 1, -- Big Game Hunter
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_298 = 1, -- Ragnaros the Firelord
  EX1_573 = 1, -- Cenarius
  EX1_558 = 1, -- Harrison Jones
})

deck("DRUID", 5, "midrange", "Combo Druid", {
  EX1_169 = 2, -- Innervate
  CS2_013 = 2, -- Wild Growth
  EX1_154 = 2, -- Wrath
  CS2_012 = 2, -- Swipe
  EX1_166 = 2, -- Keeper of the Grove
  CS2_011 = 2, -- Savage Roar
  EX1_571 = 2, -- Force of Nature
  EX1_165 = 2, -- Druid of the Claw
  NEW1_008 = 2, -- Ancient of Lore
  GVG_096 = 2, -- Piloted Shredder
  FP1_001 = 2, -- Zombie Chow
  FP1_012 = 1, -- Sludge Belcher
  EX1_178 = 1, -- Ancient of War
  EX1_005 = 1, -- Big Game Hunter
  GVG_110 = 1, -- Dr. Boom
  EX1_016 = 1, -- Sylvanas Windrunner
  FP1_030 = 1, -- Loatheb
  EX1_558 = 1, -- Harrison Jones
  EX1_573 = 1, -- Cenarius
})

-- ================================================================= HUNTER

deck("HUNTER", 1, "aggro", "Basic Hunter", {
  DS1_185 = 2, -- Arcane Shot
  DS1_175 = 2, -- Timber Wolf
  DS1_184 = 1, -- Tracking
  CS2_084 = 1, -- Hunter's Mark
  NEW1_031 = 2, -- Animal Companion
  EX1_539 = 2, -- Kill Command
  DS1_070 = 2, -- Houndmaster
  DS1_183 = 2, -- Multi-Shot
  CS2_237 = 1, -- Starving Buzzard
  DS1_178 = 2, -- Tundra Rhino
  CS2_171 = 2, -- Stonetusk Boar
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_120 = 2, -- River Crocolisk
  CS2_196 = 2, -- Razorfen Hunter
  CS2_124 = 2, -- Wolfrider
  CS2_182 = 2, -- Chillwind Yeti
  CS2_201 = 1, -- Core Hound
})

deck("HUNTER", 2, "aggro", "Budget Face Hunter", {
  CS2_188 = 2, -- Abusive Sergeant
  EX1_029 = 2, -- Leper Gnome
  EX1_010 = 2, -- Worgen Infiltrator
  EX1_008 = 2, -- Argent Squire
  CS2_171 = 2, -- Stonetusk Boar
  NEW1_019 = 2, -- Knife Juggler
  EX1_610 = 2, -- Explosive Trap
  DS1_185 = 2, -- Arcane Shot
  EX1_531 = 2, -- Scavenging Hyena
  EX1_536 = 2, -- Eaglehorn Bow
  NEW1_031 = 2, -- Animal Companion
  EX1_539 = 2, -- Kill Command
  EX1_538 = 2, -- Unleash the Hounds
  CS2_124 = 2, -- Wolfrider
  EX1_089 = 2, -- Arcane Golem
})

deck("HUNTER", 3, "midrange", "Beast Hunter", {
  DS1_175 = 2, -- Timber Wolf
  FP1_011 = 2, -- Webspinner
  EX1_531 = 2, -- Scavenging Hyena
  CS2_203 = 2, -- Ironbeak Owl
  EX1_162 = 2, -- Dire Wolf Alpha
  CS2_120 = 2, -- River Crocolisk
  NEW1_031 = 2, -- Animal Companion
  EX1_539 = 2, -- Kill Command
  EX1_538 = 2, -- Unleash the Hounds
  DS1_070 = 2, -- Houndmaster
  CS2_119 = 2, -- Oasis Snapjaw
  CS2_237 = 2, -- Starving Buzzard
  EX1_534 = 2, -- Savannah Highmane
  DS1_178 = 1, -- Tundra Rhino
  EX1_028 = 1, -- Stranglethorn Tiger
  GVG_046 = 1, -- King of Beasts
  EX1_543 = 1, -- King Krush
})

deck("HUNTER", 3, "aggro", "Undertaker Hunter", {
  FP1_028 = 2, -- Undertaker
  CS2_188 = 2, -- Abusive Sergeant
  EX1_029 = 2, -- Leper Gnome
  FP1_011 = 2, -- Webspinner
  CS2_084 = 1, -- Hunter's Mark
  FP1_002 = 2, -- Haunted Creeper
  FP1_004 = 2, -- Mad Scientist
  EX1_096 = 2, -- Loot Hoarder
  NEW1_019 = 2, -- Knife Juggler
  EX1_610 = 1, -- Explosive Trap
  EX1_611 = 1, -- Freezing Trap
  EX1_536 = 2, -- Eaglehorn Bow
  EX1_538 = 2, -- Unleash the Hounds
  EX1_539 = 2, -- Kill Command
  NEW1_031 = 2, -- Animal Companion
  EX1_534 = 2, -- Savannah Highmane
  EX1_116 = 1, -- Leeroy Jenkins
})

deck("HUNTER", 4, "midrange", "Midrange Hunter", {
  FP1_011 = 2, -- Webspinner
  CS2_084 = 1, -- Hunter's Mark
  DS1_184 = 1, -- Tracking
  FP1_004 = 2, -- Mad Scientist
  FP1_002 = 2, -- Haunted Creeper
  NEW1_019 = 2, -- Knife Juggler
  EX1_611 = 1, -- Freezing Trap
  EX1_610 = 1, -- Explosive Trap
  CS2_203 = 1, -- Ironbeak Owl
  EX1_536 = 2, -- Eaglehorn Bow
  NEW1_031 = 2, -- Animal Companion
  EX1_539 = 2, -- Kill Command
  EX1_538 = 1, -- Unleash the Hounds
  EX1_617 = 1, -- Deadly Shot
  DS1_070 = 2, -- Houndmaster
  GVG_096 = 2, -- Piloted Shredder
  EX1_534 = 2, -- Savannah Highmane
  EX1_016 = 1, -- Sylvanas Windrunner
  FP1_030 = 1, -- Loatheb
  GVG_110 = 1, -- Dr. Boom
})

deck("HUNTER", 4, "aggro", "Hybrid Hunter", {
  EX1_029 = 2, -- Leper Gnome
  FP1_011 = 2, -- Webspinner
  CS2_084 = 1, -- Hunter's Mark
  FP1_004 = 2, -- Mad Scientist
  FP1_002 = 2, -- Haunted Creeper
  NEW1_019 = 2, -- Knife Juggler
  EX1_610 = 2, -- Explosive Trap
  EX1_536 = 2, -- Eaglehorn Bow
  EX1_089 = 2, -- Arcane Golem
  NEW1_031 = 2, -- Animal Companion
  EX1_539 = 2, -- Kill Command
  EX1_538 = 2, -- Unleash the Hounds
  GVG_096 = 2, -- Piloted Shredder
  EX1_534 = 2, -- Savannah Highmane
  EX1_116 = 1, -- Leeroy Jenkins
  FP1_030 = 1, -- Loatheb
  GVG_110 = 1, -- Dr. Boom
})

deck("HUNTER", 5, "aggro", "Face Hunter", {
  CS2_188 = 2, -- Abusive Sergeant
  EX1_029 = 2, -- Leper Gnome
  EX1_010 = 2, -- Worgen Infiltrator
  CS2_084 = 1, -- Hunter's Mark
  EX1_610 = 2, -- Explosive Trap
  EX1_611 = 1, -- Freezing Trap
  GVG_043 = 1, -- Glaivezooka
  FP1_002 = 2, -- Haunted Creeper
  NEW1_019 = 2, -- Knife Juggler
  FP1_004 = 2, -- Mad Scientist
  EX1_536 = 2, -- Eaglehorn Bow
  NEW1_031 = 2, -- Animal Companion
  EX1_539 = 2, -- Kill Command
  EX1_538 = 2, -- Unleash the Hounds
  EX1_089 = 2, -- Arcane Golem
  CS2_124 = 2, -- Wolfrider
  EX1_116 = 1, -- Leeroy Jenkins
})

-- =================================================================== MAGE

deck("MAGE", 1, "midrange", "Basic Mage", {
  EX1_277 = 2, -- Arcane Missiles
  CS2_027 = 1, -- Mirror Image
  CS2_025 = 2, -- Arcane Explosion
  CS2_024 = 2, -- Frostbolt
  CS2_023 = 2, -- Arcane Intellect
  CS2_029 = 2, -- Fireball
  CS2_022 = 2, -- Polymorph
  CS2_033 = 2, -- Water Elemental
  CS2_032 = 1, -- Flamestrike
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_120 = 2, -- River Crocolisk
  CS2_142 = 2, -- Kobold Geomancer
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_200 = 2, -- Boulderfist Ogre
  CS2_147 = 2, -- Gnomish Inventor
})

deck("MAGE", 2, "midrange", "Budget Tempo Mage", {
  NEW1_012 = 2, -- Mana Wyrm
  EX1_277 = 2, -- Arcane Missiles
  CS2_027 = 2, -- Mirror Image
  CS2_024 = 2, -- Frostbolt
  EX1_608 = 2, -- Sorcerer's Apprentice
  CS2_023 = 2, -- Arcane Intellect
  CS2_029 = 2, -- Fireball
  CS2_022 = 2, -- Polymorph
  CS2_033 = 2, -- Water Elemental
  CS2_032 = 1, -- Flamestrike
  EX1_066 = 1, -- Acidic Swamp Ooze
  CS2_172 = 2, -- Bloodfen Raptor
  EX1_096 = 2, -- Loot Hoarder
  EX1_556 = 2, -- Harvest Golem
  CS2_182 = 2, -- Chillwind Yeti
  GVG_044 = 2, -- Spider Tank
})

deck("MAGE", 3, "aggro", "Budget Mech Mage", {
  GVG_082 = 2, -- Clockwork Gnome
  GVG_013 = 2, -- Cogmaster
  GVG_006 = 2, -- Mechwarper
  GVG_085 = 2, -- Annoy-o-Tron
  GVG_002 = 2, -- Snowchugger
  GVG_044 = 2, -- Spider Tank
  EX1_277 = 2, -- Arcane Missiles
  CS2_024 = 2, -- Frostbolt
  GVG_001 = 2, -- Flamecannon
  GVG_076 = 2, -- Explosive Sheep
  EX1_556 = 2, -- Harvest Golem
  GVG_102 = 2, -- Tinkertown Technician
  GVG_004 = 2, -- Goblin Blastmage
  CS2_029 = 2, -- Fireball
  GVG_078 = 2, -- Mechanical Yeti
})

deck("MAGE", 3, "midrange", "Classic Tempo Mage", {
  NEW1_012 = 2, -- Mana Wyrm
  EX1_277 = 1, -- Arcane Missiles
  CS2_027 = 1, -- Mirror Image
  CS2_024 = 2, -- Frostbolt
  EX1_608 = 2, -- Sorcerer's Apprentice
  CS2_023 = 2, -- Arcane Intellect
  EX1_287 = 1, -- Counterspell
  EX1_294 = 1, -- Mirror Entity
  EX1_612 = 2, -- Kirin Tor Mage
  CS2_029 = 2, -- Fireball
  CS2_033 = 2, -- Water Elemental
  CS2_022 = 1, -- Polymorph
  CS2_032 = 1, -- Flamestrike
  EX1_066 = 1, -- Acidic Swamp Ooze
  EX1_012 = 1, -- Bloodmage Thalnos
  EX1_096 = 2, -- Loot Hoarder
  EX1_005 = 1, -- Big Game Hunter
  CS2_182 = 2, -- Chillwind Yeti
  EX1_284 = 2, -- Azure Drake
  EX1_559 = 1, -- Archmage Antonidas
})

deck("MAGE", 4, "control", "Freeze Mage", {
  CS2_031 = 2, -- Ice Lance
  CS2_027 = 2, -- Mirror Image
  CS2_024 = 2, -- Frostbolt
  CS2_023 = 2, -- Arcane Intellect
  EX1_289 = 2, -- Ice Barrier
  EX1_295 = 2, -- Ice Block
  CS2_026 = 2, -- Frost Nova
  EX1_275 = 1, -- Cone of Cold
  CS2_029 = 2, -- Fireball
  CS2_028 = 2, -- Blizzard
  CS2_032 = 1, -- Flamestrike
  EX1_279 = 1, -- Pyroblast
  NEW1_021 = 2, -- Doomsayer
  EX1_096 = 2, -- Loot Hoarder
  EX1_007 = 2, -- Acolyte of Pain
  EX1_012 = 1, -- Bloodmage Thalnos
  EX1_559 = 1, -- Archmage Antonidas
  EX1_561 = 1, -- Alexstrasza
})

deck("MAGE", 4, "aggro", "Mech Mage", {
  GVG_082 = 2, -- Clockwork Gnome
  GVG_013 = 2, -- Cogmaster
  GVG_006 = 2, -- Mechwarper
  GVG_085 = 2, -- Annoy-o-Tron
  GVG_002 = 2, -- Snowchugger
  GVG_003 = 2, -- Unstable Portal
  GVG_044 = 2, -- Spider Tank
  CS2_027 = 1, -- Mirror Image
  CS2_024 = 2, -- Frostbolt
  GVG_001 = 1, -- Flamecannon
  GVG_004 = 2, -- Goblin Blastmage
  GVG_096 = 2, -- Piloted Shredder
  GVG_102 = 2, -- Tinkertown Technician
  CS2_029 = 2, -- Fireball
  GVG_105 = 1, -- Piloted Sky Golem
  FP1_030 = 1, -- Loatheb
  GVG_110 = 1, -- Dr. Boom
  GVG_114 = 1, -- Sneed's Old Shredder
})

deck("MAGE", 5, "midrange", "Tempo Mage", {
  NEW1_012 = 2, -- Mana Wyrm
  CS2_027 = 1, -- Mirror Image
  EX1_277 = 2, -- Arcane Missiles
  CS2_024 = 2, -- Frostbolt
  GVG_003 = 2, -- Unstable Portal
  EX1_608 = 2, -- Sorcerer's Apprentice
  CS2_023 = 2, -- Arcane Intellect
  EX1_294 = 1, -- Mirror Entity
  GVG_001 = 1, -- Flamecannon
  FP1_004 = 2, -- Mad Scientist
  EX1_012 = 1, -- Bloodmage Thalnos
  CS2_029 = 2, -- Fireball
  CS2_022 = 1, -- Polymorph
  EX1_612 = 1, -- Kirin Tor Mage
  CS2_033 = 1, -- Water Elemental
  GVG_096 = 2, -- Piloted Shredder
  EX1_284 = 2, -- Azure Drake
  FP1_030 = 1, -- Loatheb
  EX1_559 = 1, -- Archmage Antonidas
  GVG_110 = 1, -- Dr. Boom
})

-- ================================================================ PALADIN

deck("PALADIN", 1, "midrange", "Basic Paladin", {
  CS2_087 = 2, -- Blessing of Might
  EX1_371 = 1, -- Hand of Protection
  CS2_091 = 2, -- Light's Justice
  CS2_089 = 1, -- Holy Light
  CS2_092 = 2, -- Blessing of Kings
  CS2_093 = 2, -- Consecration
  CS2_094 = 2, -- Hammer of Wrath
  CS2_097 = 2, -- Truesilver Champion
  CS2_088 = 2, -- Guardian of Kings
  CS2_120 = 2, -- River Crocolisk
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_125 = 2, -- Ironfur Grizzly
  CS2_196 = 2, -- Razorfen Hunter
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_200 = 1, -- Boulderfist Ogre
  CS2_222 = 1, -- Stormwind Champion
})

deck("PALADIN", 2, "aggro", "Budget Aggro Paladin", {
  EX1_008 = 2, -- Argent Squire
  EX1_029 = 2, -- Leper Gnome
  CS2_188 = 2, -- Abusive Sergeant
  CS2_087 = 2, -- Blessing of Might
  EX1_362 = 2, -- Argent Protector
  NEW1_019 = 2, -- Knife Juggler
  GVG_058 = 2, -- Shielded Minibot
  EX1_349 = 2, -- Divine Favor
  GVG_061 = 2, -- Muster for Battle
  EX1_019 = 2, -- Shattered Sun Cleric
  EX1_089 = 2, -- Arcane Golem
  CS2_124 = 2, -- Wolfrider
  CS2_092 = 2, -- Blessing of Kings
  CS2_097 = 2, -- Truesilver Champion
  CS2_093 = 1, -- Consecration
  CS2_094 = 1, -- Hammer of Wrath
})

deck("PALADIN", 3, "midrange", "Budget Midrange Paladin", {
  FP1_001 = 2, -- Zombie Chow
  GVG_058 = 2, -- Shielded Minibot
  GVG_061 = 2, -- Muster for Battle
  NEW1_019 = 2, -- Knife Juggler
  EX1_619 = 1, -- Equality
  NEW1_020 = 1, -- Wild Pyromancer
  EX1_382 = 2, -- Aldor Peacekeeper
  CS2_097 = 2, -- Truesilver Champion
  CS2_093 = 2, -- Consecration
  CS2_094 = 2, -- Hammer of Wrath
  GVG_044 = 2, -- Spider Tank
  GVG_096 = 2, -- Piloted Shredder
  EX1_093 = 1, -- Defender of Argus
  CS2_092 = 2, -- Blessing of Kings
  FP1_012 = 2, -- Sludge Belcher
  CS2_088 = 2, -- Guardian of Kings
  CS2_222 = 1, -- Stormwind Champion
})

deck("PALADIN", 3, "control", "Classic Control Paladin", {
  EX1_360 = 1, -- Humility
  EX1_619 = 2, -- Equality
  NEW1_020 = 2, -- Wild Pyromancer
  EX1_382 = 2, -- Aldor Peacekeeper
  CS2_093 = 2, -- Consecration
  CS2_097 = 2, -- Truesilver Champion
  CS2_094 = 2, -- Hammer of Wrath
  EX1_007 = 2, -- Acolyte of Pain
  CS2_117 = 2, -- Earthen Ring Farseer
  EX1_093 = 2, -- Defender of Argus
  EX1_005 = 1, -- Big Game Hunter
  EX1_284 = 1, -- Azure Drake
  EX1_032 = 1, -- Sunwalker
  EX1_067 = 1, -- Argent Commander
  CS2_088 = 1, -- Guardian of Kings
  EX1_354 = 1, -- Lay on Hands
  EX1_558 = 1, -- Harrison Jones
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_110 = 1, -- Cairne Bloodhoof
  EX1_383 = 1, -- Tirion Fordring
  EX1_298 = 1, -- Ragnaros the Firelord
})

deck("PALADIN", 4, "aggro", "Aggro Paladin", {
  EX1_008 = 2, -- Argent Squire
  EX1_029 = 2, -- Leper Gnome
  CS2_188 = 2, -- Abusive Sergeant
  CS2_087 = 1, -- Blessing of Might
  EX1_362 = 2, -- Argent Protector
  GVG_058 = 2, -- Shielded Minibot
  NEW1_019 = 2, -- Knife Juggler
  FP1_002 = 2, -- Haunted Creeper
  GVG_061 = 2, -- Muster for Battle
  EX1_349 = 2, -- Divine Favor
  GVG_059 = 2, -- Coghammer
  EX1_089 = 2, -- Arcane Golem
  CS2_092 = 2, -- Blessing of Kings
  CS2_097 = 2, -- Truesilver Champion
  CS2_094 = 1, -- Hammer of Wrath
  EX1_384 = 1, -- Avenging Wrath
  EX1_116 = 1, -- Leeroy Jenkins
})

deck("PALADIN", 4, "midrange", "Midrange Paladin", {
  FP1_001 = 2, -- Zombie Chow
  GVG_058 = 2, -- Shielded Minibot
  GVG_061 = 2, -- Muster for Battle
  NEW1_019 = 2, -- Knife Juggler
  EX1_619 = 1, -- Equality
  NEW1_020 = 1, -- Wild Pyromancer
  EX1_382 = 2, -- Aldor Peacekeeper
  GVG_059 = 1, -- Coghammer
  CS2_097 = 2, -- Truesilver Champion
  CS2_093 = 2, -- Consecration
  CS2_094 = 1, -- Hammer of Wrath
  EX1_005 = 1, -- Big Game Hunter
  GVG_096 = 2, -- Piloted Shredder
  EX1_093 = 1, -- Defender of Argus
  GVG_060 = 1, -- Quartermaster
  FP1_012 = 2, -- Sludge Belcher
  EX1_016 = 1, -- Sylvanas Windrunner
  FP1_030 = 1, -- Loatheb
  EX1_354 = 1, -- Lay on Hands
  GVG_110 = 1, -- Dr. Boom
  EX1_383 = 1, -- Tirion Fordring
})

deck("PALADIN", 5, "control", "Control Paladin", {
  EX1_619 = 2, -- Equality
  NEW1_020 = 2, -- Wild Pyromancer
  FP1_001 = 2, -- Zombie Chow
  EX1_382 = 2, -- Aldor Peacekeeper
  CS2_093 = 2, -- Consecration
  CS2_097 = 2, -- Truesilver Champion
  GVG_061 = 1, -- Muster for Battle
  CS2_094 = 1, -- Hammer of Wrath
  EX1_005 = 1, -- Big Game Hunter
  GVG_096 = 1, -- Piloted Shredder
  EX1_093 = 1, -- Defender of Argus
  GVG_069 = 1, -- Antique Healbot
  GVG_060 = 1, -- Quartermaster
  FP1_012 = 2, -- Sludge Belcher
  EX1_016 = 1, -- Sylvanas Windrunner
  FP1_030 = 1, -- Loatheb
  EX1_110 = 1, -- Cairne Bloodhoof
  EX1_354 = 1, -- Lay on Hands
  GVG_110 = 1, -- Dr. Boom
  EX1_383 = 1, -- Tirion Fordring
  EX1_298 = 1, -- Ragnaros the Firelord
  FP1_013 = 1, -- Kel'Thuzad
  EX1_572 = 1, -- Ysera
})

-- ================================================================= PRIEST

deck("PRIEST", 1, "control", "Basic Priest", {
  CS1_130 = 2, -- Holy Smite
  CS2_235 = 2, -- Northshire Cleric
  CS2_004 = 2, -- Power Word: Shield
  DS1_233 = 1, -- Mind Blast
  CS2_234 = 2, -- Shadow Word: Pain
  CS2_236 = 1, -- Divine Spirit
  EX1_622 = 2, -- Shadow Word: Death
  CS1_112 = 2, -- Holy Nova
  CS1_113 = 1, -- Mind Control
  CS2_120 = 2, -- River Crocolisk
  CS2_172 = 2, -- Bloodfen Raptor
  EX1_019 = 2, -- Shattered Sun Cleric
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_182 = 2, -- Chillwind Yeti
  CS2_147 = 2, -- Gnomish Inventor
  CS2_200 = 2, -- Boulderfist Ogre
  DS1_055 = 1, -- Darkscale Healer
})

deck("PRIEST", 2, "midrange", "Budget Priest", {
  CS2_235 = 2, -- Northshire Cleric
  CS2_004 = 2, -- Power Word: Shield
  CS1_130 = 2, -- Holy Smite
  CS2_234 = 2, -- Shadow Word: Pain
  CS1_129 = 2, -- Inner Fire
  CS2_236 = 2, -- Divine Spirit
  FP1_023 = 2, -- Dark Cultist
  EX1_622 = 2, -- Shadow Word: Death
  CS1_112 = 2, -- Holy Nova
  EX1_621 = 1, -- Circle of Healing
  EX1_591 = 1, -- Auchenai Soulpriest
  EX1_339 = 1, -- Thoughtsteal
  CS1_113 = 1, -- Mind Control
  CS2_181 = 2, -- Injured Blademaster
  CS2_117 = 2, -- Earthen Ring Farseer
  EX1_096 = 2, -- Loot Hoarder
  EX1_556 = 2, -- Harvest Golem
})

deck("PRIEST", 3, "midrange", "Velen Burst Priest", {
  CS2_235 = 2, -- Northshire Cleric
  CS1_130 = 2, -- Holy Smite
  CS2_004 = 2, -- Power Word: Shield
  DS1_233 = 2, -- Mind Blast
  CS2_234 = 2, -- Shadow Word: Pain
  EX1_622 = 2, -- Shadow Word: Death
  FP1_023 = 2, -- Dark Cultist
  GVG_010 = 2, -- Velen's Chosen
  CS1_112 = 2, -- Holy Nova
  EX1_591 = 2, -- Auchenai Soulpriest
  EX1_339 = 1, -- Thoughtsteal
  EX1_350 = 1, -- Prophet Velen
  EX1_096 = 2, -- Loot Hoarder
  EX1_556 = 2, -- Harvest Golem
  CS2_142 = 2, -- Kobold Geomancer
  EX1_284 = 2, -- Azure Drake
})

deck("PRIEST", 3, "control", "Classic Control Priest", {
  EX1_621 = 1, -- Circle of Healing
  CS2_004 = 2, -- Power Word: Shield
  CS2_235 = 2, -- Northshire Cleric
  CS2_234 = 2, -- Shadow Word: Pain
  NEW1_020 = 2, -- Wild Pyromancer
  EX1_591 = 2, -- Auchenai Soulpriest
  EX1_622 = 2, -- Shadow Word: Death
  CS1_112 = 2, -- Holy Nova
  EX1_339 = 1, -- Thoughtsteal
  EX1_007 = 2, -- Acolyte of Pain
  CS2_181 = 2, -- Injured Blademaster
  EX1_091 = 2, -- Cabal Shadow Priest
  EX1_005 = 1, -- Big Game Hunter
  EX1_284 = 1, -- Azure Drake
  EX1_624 = 1, -- Holy Fire
  EX1_623 = 1, -- Temple Enforcer
  CS1_113 = 1, -- Mind Control
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_110 = 1, -- Cairne Bloodhoof
  EX1_298 = 1, -- Ragnaros the Firelord
})

deck("PRIEST", 4, "control", "Naxx Control Priest", {
  EX1_621 = 1, -- Circle of Healing
  CS2_004 = 2, -- Power Word: Shield
  CS2_235 = 2, -- Northshire Cleric
  FP1_001 = 2, -- Zombie Chow
  CS2_234 = 1, -- Shadow Word: Pain
  NEW1_020 = 2, -- Wild Pyromancer
  EX1_591 = 2, -- Auchenai Soulpriest
  EX1_622 = 2, -- Shadow Word: Death
  CS1_112 = 1, -- Holy Nova
  EX1_339 = 1, -- Thoughtsteal
  FP1_009 = 2, -- Deathlord
  CS2_181 = 2, -- Injured Blademaster
  FP1_012 = 2, -- Sludge Belcher
  EX1_091 = 2, -- Cabal Shadow Priest
  EX1_624 = 1, -- Holy Fire
  CS1_113 = 1, -- Mind Control
  EX1_016 = 1, -- Sylvanas Windrunner
  FP1_030 = 1, -- Loatheb
  EX1_298 = 1, -- Ragnaros the Firelord
  FP1_013 = 1, -- Kel'Thuzad
})

deck("PRIEST", 4, "midrange", "Shadow Madness Priest", {
  CS2_235 = 2, -- Northshire Cleric
  CS2_004 = 2, -- Power Word: Shield
  CS1_130 = 1, -- Holy Smite
  NEW1_020 = 2, -- Wild Pyromancer
  CS2_234 = 1, -- Shadow Word: Pain
  EX1_622 = 2, -- Shadow Word: Death
  GVG_010 = 2, -- Velen's Chosen
  EX1_334 = 2, -- Shadow Madness
  EX1_591 = 1, -- Auchenai Soulpriest
  CS1_112 = 2, -- Holy Nova
  FP1_001 = 2, -- Zombie Chow
  FP1_009 = 2, -- Deathlord
  GVG_096 = 2, -- Piloted Shredder
  EX1_284 = 2, -- Azure Drake
  EX1_091 = 1, -- Cabal Shadow Priest
  GVG_014 = 1, -- Vol'jin
  EX1_016 = 1, -- Sylvanas Windrunner
  GVG_110 = 1, -- Dr. Boom
  FP1_030 = 1, -- Loatheb
})

deck("PRIEST", 5, "control", "Control Priest", {
  EX1_621 = 1, -- Circle of Healing
  CS2_004 = 2, -- Power Word: Shield
  CS2_235 = 2, -- Northshire Cleric
  FP1_001 = 2, -- Zombie Chow
  CS2_234 = 1, -- Shadow Word: Pain
  GVG_010 = 2, -- Velen's Chosen
  EX1_622 = 2, -- Shadow Word: Death
  NEW1_020 = 2, -- Wild Pyromancer
  EX1_591 = 2, -- Auchenai Soulpriest
  CS1_112 = 1, -- Holy Nova
  FP1_009 = 2, -- Deathlord
  CS2_181 = 2, -- Injured Blademaster
  GVG_008 = 2, -- Lightbomb
  EX1_091 = 2, -- Cabal Shadow Priest
  FP1_012 = 1, -- Sludge Belcher
  GVG_014 = 1, -- Vol'jin
  EX1_016 = 1, -- Sylvanas Windrunner
  GVG_110 = 1, -- Dr. Boom
  EX1_298 = 1, -- Ragnaros the Firelord
})

-- ================================================================== ROGUE

deck("ROGUE", 1, "midrange", "Basic Rogue", {
  CS2_072 = 2, -- Backstab
  CS2_074 = 2, -- Deadly Poison
  CS2_075 = 2, -- Sinister Strike
  EX1_581 = 2, -- Sap
  EX1_129 = 2, -- Fan of Knives
  CS2_076 = 2, -- Assassinate
  CS2_080 = 2, -- Assassin's Blade
  CS2_077 = 1, -- Sprint
  NEW1_004 = 1, -- Vanish
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_120 = 2, -- River Crocolisk
  CS2_196 = 2, -- Razorfen Hunter
  CS2_124 = 2, -- Wolfrider
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_150 = 2, -- Stormpike Commando
})

deck("ROGUE", 2, "aggro", "Pirate Rogue", {
  CS2_146 = 2, -- Southsea Deckhand
  NEW1_018 = 2, -- Bloodsail Raider
  NEW1_022 = 2, -- Dread Corsair
  CS2_072 = 2, -- Backstab
  CS2_074 = 2, -- Deadly Poison
  CS2_073 = 2, -- Cold Blood
  EX1_124 = 2, -- Eviscerate
  EX1_581 = 1, -- Sap
  EX1_278 = 1, -- Shiv
  EX1_134 = 2, -- SI:7 Agent
  EX1_131 = 2, -- Defias Ringleader
  CS2_080 = 2, -- Assassin's Blade
  EX1_129 = 2, -- Fan of Knives
  EX1_029 = 2, -- Leper Gnome
  EX1_096 = 2, -- Loot Hoarder
  CS2_124 = 2, -- Wolfrider
})

deck("ROGUE", 3, "aggro", "Mech Rogue", {
  GVG_013 = 2, -- Cogmaster
  GVG_023 = 2, -- Goblin Auto-Barber
  GVG_024 = 2, -- Cogmaster's Wrench
  GVG_006 = 2, -- Mechwarper
  GVG_085 = 2, -- Annoy-o-Tron
  GVG_044 = 2, -- Spider Tank
  GVG_022 = 2, -- Tinker's Sharpsword Oil
  CS2_072 = 2, -- Backstab
  CS2_233 = 2, -- Blade Flurry
  GVG_027 = 2, -- Iron Sensei
  EX1_134 = 2, -- SI:7 Agent
  EX1_124 = 2, -- Eviscerate
  EX1_581 = 1, -- Sap
  GVG_096 = 2, -- Piloted Shredder
  EX1_556 = 2, -- Harvest Golem
  GVG_110 = 1, -- Dr. Boom
})

deck("ROGUE", 3, "midrange", "Deathrattle Rogue", {
  CS2_072 = 2, -- Backstab
  CS2_074 = 2, -- Deadly Poison
  EX1_144 = 1, -- Shadowstep
  FP1_028 = 2, -- Undertaker
  FP1_002 = 2, -- Haunted Creeper
  EX1_096 = 2, -- Loot Hoarder
  EX1_134 = 2, -- SI:7 Agent
  EX1_124 = 2, -- Eviscerate
  EX1_581 = 1, -- Sap
  EX1_129 = 1, -- Fan of Knives
  EX1_556 = 2, -- Harvest Golem
  FP1_026 = 2, -- Anub'ar Ambusher
  FP1_012 = 2, -- Sludge Belcher
  EX1_284 = 2, -- Azure Drake
  FP1_031 = 1, -- Baron Rivendare
  FP1_015 = 1, -- Feugen
  FP1_014 = 1, -- Stalagg
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_110 = 1, -- Cairne Bloodhoof
})

deck("ROGUE", 4, "midrange", "Miracle Rogue", {
  CS2_072 = 2, -- Backstab
  EX1_145 = 2, -- Preparation
  CS2_073 = 2, -- Cold Blood
  EX1_128 = 2, -- Conceal
  CS2_074 = 2, -- Deadly Poison
  EX1_124 = 2, -- Eviscerate
  EX1_581 = 2, -- Sap
  EX1_278 = 2, -- Shiv
  EX1_129 = 2, -- Fan of Knives
  EX1_134 = 2, -- SI:7 Agent
  CS2_117 = 2, -- Earthen Ring Farseer
  EX1_095 = 2, -- Gadgetzan Auctioneer
  EX1_284 = 2, -- Azure Drake
  EX1_096 = 1, -- Loot Hoarder
  EX1_012 = 1, -- Bloodmage Thalnos
  EX1_613 = 1, -- Edwin VanCleef
  EX1_116 = 1, -- Leeroy Jenkins
})

deck("ROGUE", 4, "aggro", "Tempo Rogue", {
  CS2_072 = 2, -- Backstab
  CS2_074 = 2, -- Deadly Poison
  CS2_073 = 2, -- Cold Blood
  EX1_124 = 2, -- Eviscerate
  EX1_134 = 2, -- SI:7 Agent
  EX1_131 = 2, -- Defias Ringleader
  EX1_129 = 1, -- Fan of Knives
  EX1_581 = 1, -- Sap
  EX1_137 = 1, -- Headcrack
  NEW1_019 = 2, -- Knife Juggler
  EX1_096 = 2, -- Loot Hoarder
  CS2_117 = 2, -- Earthen Ring Farseer
  GVG_096 = 2, -- Piloted Shredder
  EX1_284 = 2, -- Azure Drake
  EX1_116 = 1, -- Leeroy Jenkins
  EX1_613 = 1, -- Edwin VanCleef
  FP1_030 = 1, -- Loatheb
  EX1_558 = 1, -- Harrison Jones
  GVG_110 = 1, -- Dr. Boom
})

deck("ROGUE", 5, "midrange", "Oil Rogue", {
  CS2_072 = 2, -- Backstab
  EX1_145 = 1, -- Preparation
  CS2_073 = 1, -- Cold Blood
  CS2_074 = 2, -- Deadly Poison
  EX1_278 = 1, -- Shiv
  CS2_233 = 2, -- Blade Flurry
  EX1_124 = 2, -- Eviscerate
  EX1_581 = 1, -- Sap
  GVG_023 = 2, -- Goblin Auto-Barber
  EX1_134 = 2, -- SI:7 Agent
  EX1_129 = 2, -- Fan of Knives
  GVG_022 = 2, -- Tinker's Sharpsword Oil
  CS2_077 = 1, -- Sprint
  GVG_096 = 2, -- Piloted Shredder
  NEW1_026 = 2, -- Violet Teacher
  EX1_284 = 2, -- Azure Drake
  EX1_012 = 1, -- Bloodmage Thalnos
  FP1_030 = 1, -- Loatheb
  GVG_110 = 1, -- Dr. Boom
})

-- ================================================================= SHAMAN

deck("SHAMAN", 1, "midrange", "Basic Shaman", {
  CS2_037 = 2, -- Frost Shock
  CS2_045 = 2, -- Rockbiter Weapon
  EX1_565 = 2, -- Flametongue Totem
  CS2_039 = 1, -- Windfury
  EX1_246 = 2, -- Hex
  EX1_587 = 1, -- Windspeaker
  CS2_046 = 1, -- Bloodlust
  CS2_042 = 2, -- Fire Elemental
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_120 = 2, -- River Crocolisk
  CS2_196 = 2, -- Razorfen Hunter
  CS2_125 = 2, -- Ironfur Grizzly
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_182 = 2, -- Chillwind Yeti
  CS2_147 = 2, -- Gnomish Inventor
  CS2_200 = 2, -- Boulderfist Ogre
  EX1_506 = 1, -- Murloc Tidehunter
})

deck("SHAMAN", 2, "midrange", "Budget Totem Shaman", {
  EX1_245 = 2, -- Earth Shock
  EX1_238 = 2, -- Lightning Bolt
  CS2_045 = 2, -- Rockbiter Weapon
  GVG_038 = 2, -- Crackle
  EX1_565 = 2, -- Flametongue Totem
  EX1_247 = 2, -- Stormforged Axe
  EX1_248 = 2, -- Feral Spirit
  EX1_246 = 2, -- Hex
  EX1_259 = 2, -- Lightning Storm
  EX1_258 = 2, -- Unbound Elemental
  CS2_042 = 2, -- Fire Elemental
  CS2_117 = 2, -- Earthen Ring Farseer
  EX1_556 = 2, -- Harvest Golem
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
})

deck("SHAMAN", 3, "aggro", "Mech Shaman", {
  GVG_082 = 2, -- Clockwork Gnome
  GVG_013 = 2, -- Cogmaster
  GVG_006 = 2, -- Mechwarper
  GVG_085 = 2, -- Annoy-o-Tron
  CS2_045 = 2, -- Rockbiter Weapon
  EX1_238 = 2, -- Lightning Bolt
  GVG_038 = 2, -- Crackle
  GVG_037 = 2, -- Whirling Zap-o-matic
  EX1_565 = 2, -- Flametongue Totem
  GVG_044 = 2, -- Spider Tank
  GVG_036 = 2, -- Powermace
  EX1_556 = 2, -- Harvest Golem
  GVG_096 = 2, -- Piloted Shredder
  GVG_016 = 2, -- Fel Reaver
  EX1_567 = 1, -- Doomhammer
  GVG_110 = 1, -- Dr. Boom
})

deck("SHAMAN", 3, "midrange", "Classic Midrange Shaman", {
  EX1_245 = 1, -- Earth Shock
  EX1_238 = 2, -- Lightning Bolt
  CS2_045 = 2, -- Rockbiter Weapon
  GVG_038 = 1, -- Crackle
  EX1_565 = 2, -- Flametongue Totem
  EX1_248 = 2, -- Feral Spirit
  EX1_246 = 2, -- Hex
  EX1_259 = 2, -- Lightning Storm
  EX1_575 = 1, -- Mana Tide Totem
  CS2_117 = 2, -- Earthen Ring Farseer
  EX1_556 = 2, -- Harvest Golem
  EX1_093 = 2, -- Defender of Argus
  EX1_005 = 1, -- Big Game Hunter
  EX1_284 = 2, -- Azure Drake
  CS2_042 = 2, -- Fire Elemental
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_110 = 1, -- Cairne Bloodhoof
  EX1_298 = 1, -- Ragnaros the Firelord
  NEW1_010 = 1, -- Al'Akir the Windlord
})

deck("SHAMAN", 4, "aggro", "Doomhammer Aggro", {
  EX1_029 = 2, -- Leper Gnome
  EX1_008 = 2, -- Argent Squire
  CS2_045 = 2, -- Rockbiter Weapon
  EX1_238 = 2, -- Lightning Bolt
  GVG_038 = 2, -- Crackle
  EX1_247 = 1, -- Stormforged Axe
  EX1_565 = 2, -- Flametongue Totem
  NEW1_019 = 2, -- Knife Juggler
  EX1_243 = 2, -- Dust Devil
  EX1_248 = 2, -- Feral Spirit
  EX1_258 = 2, -- Unbound Elemental
  EX1_241 = 2, -- Lava Burst
  CS2_124 = 2, -- Wolfrider
  EX1_089 = 2, -- Arcane Golem
  EX1_567 = 1, -- Doomhammer
  EX1_116 = 1, -- Leeroy Jenkins
  NEW1_010 = 1, -- Al'Akir the Windlord
})

deck("SHAMAN", 4, "midrange", "Naxx Midrange Shaman", {
  EX1_245 = 1, -- Earth Shock
  EX1_238 = 2, -- Lightning Bolt
  CS2_045 = 1, -- Rockbiter Weapon
  EX1_565 = 2, -- Flametongue Totem
  FP1_002 = 2, -- Haunted Creeper
  EX1_248 = 2, -- Feral Spirit
  EX1_246 = 2, -- Hex
  EX1_259 = 2, -- Lightning Storm
  EX1_575 = 1, -- Mana Tide Totem
  CS2_117 = 1, -- Earthen Ring Farseer
  EX1_005 = 1, -- Big Game Hunter
  EX1_093 = 2, -- Defender of Argus
  EX1_284 = 2, -- Azure Drake
  FP1_012 = 2, -- Sludge Belcher
  CS2_042 = 2, -- Fire Elemental
  FP1_030 = 1, -- Loatheb
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_110 = 1, -- Cairne Bloodhoof
  EX1_298 = 1, -- Ragnaros the Firelord
  NEW1_010 = 1, -- Al'Akir the Windlord
})

deck("SHAMAN", 5, "midrange", "Midrange Shaman", {
  EX1_245 = 1, -- Earth Shock
  EX1_238 = 2, -- Lightning Bolt
  CS2_045 = 1, -- Rockbiter Weapon
  FP1_001 = 2, -- Zombie Chow
  EX1_565 = 2, -- Flametongue Totem
  EX1_248 = 2, -- Feral Spirit
  EX1_246 = 2, -- Hex
  EX1_259 = 1, -- Lightning Storm
  EX1_575 = 1, -- Mana Tide Totem
  EX1_241 = 1, -- Lava Burst
  EX1_005 = 1, -- Big Game Hunter
  EX1_093 = 1, -- Defender of Argus
  GVG_096 = 2, -- Piloted Shredder
  EX1_284 = 2, -- Azure Drake
  FP1_012 = 2, -- Sludge Belcher
  CS2_042 = 2, -- Fire Elemental
  FP1_030 = 1, -- Loatheb
  EX1_016 = 1, -- Sylvanas Windrunner
  GVG_110 = 1, -- Dr. Boom
  EX1_298 = 1, -- Ragnaros the Firelord
  NEW1_010 = 1, -- Al'Akir the Windlord
})

-- ================================================================ WARLOCK

deck("WARLOCK", 1, "midrange", "Basic Warlock", {
  EX1_302 = 2, -- Mortal Coil
  EX1_308 = 2, -- Soulfire
  CS2_065 = 2, -- Voidwalker
  EX1_306 = 2, -- Succubus
  CS2_061 = 2, -- Drain Life
  CS2_057 = 2, -- Shadow Bolt
  CS2_062 = 2, -- Hellfire
  CS2_064 = 1, -- Dread Infernal
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_120 = 2, -- River Crocolisk
  CS2_142 = 2, -- Kobold Geomancer
  CS2_196 = 2, -- Razorfen Hunter
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
  CS2_200 = 2, -- Boulderfist Ogre
  CS2_222 = 1, -- Stormwind Champion
})

deck("WARLOCK", 2, "aggro", "Budget Zoo", {
  EX1_319 = 2, -- Flame Imp
  CS2_065 = 2, -- Voidwalker
  EX1_316 = 2, -- Power Overwhelming
  EX1_308 = 2, -- Soulfire
  EX1_302 = 2, -- Mortal Coil
  CS2_188 = 2, -- Abusive Sergeant
  EX1_008 = 2, -- Argent Squire
  EX1_029 = 2, -- Leper Gnome
  NEW1_019 = 2, -- Knife Juggler
  EX1_162 = 2, -- Dire Wolf Alpha
  EX1_556 = 2, -- Harvest Golem
  EX1_019 = 2, -- Shattered Sun Cleric
  EX1_046 = 2, -- Dark Iron Dwarf
  EX1_093 = 2, -- Defender of Argus
  EX1_310 = 2, -- Doomguard
})

deck("WARLOCK", 3, "aggro", "Naxx Zoo", {
  EX1_319 = 2, -- Flame Imp
  CS2_065 = 2, -- Voidwalker
  EX1_316 = 2, -- Power Overwhelming
  EX1_308 = 2, -- Soulfire
  CS2_188 = 1, -- Abusive Sergeant
  EX1_008 = 2, -- Argent Squire
  FP1_001 = 2, -- Zombie Chow
  FP1_007 = 2, -- Nerubian Egg
  FP1_002 = 2, -- Haunted Creeper
  NEW1_019 = 2, -- Knife Juggler
  EX1_162 = 2, -- Dire Wolf Alpha
  EX1_556 = 2, -- Harvest Golem
  EX1_019 = 1, -- Shattered Sun Cleric
  EX1_046 = 1, -- Dark Iron Dwarf
  EX1_093 = 2, -- Defender of Argus
  EX1_310 = 2, -- Doomguard
  FP1_030 = 1, -- Loatheb
})

deck("WARLOCK", 3, "control", "Budget Handlock", {
  EX1_302 = 2, -- Mortal Coil
  EX1_316 = 1, -- Power Overwhelming
  EX1_045 = 2, -- Ancient Watcher
  EX1_058 = 2, -- Sunfury Protector
  CS2_057 = 2, -- Shadow Bolt
  EX1_304 = 1, -- Void Terror
  CS2_062 = 2, -- Hellfire
  EX1_303 = 2, -- Shadowflame
  EX1_309 = 1, -- Siphon Soul
  EX1_043 = 2, -- Twilight Drake
  EX1_093 = 2, -- Defender of Argus
  CS2_117 = 2, -- Earthen Ring Farseer
  CS2_179 = 2, -- Sen'jin Shieldmasta
  EX1_005 = 1, -- Big Game Hunter
  EX1_564 = 1, -- Faceless Manipulator
  CS2_064 = 1, -- Dread Infernal
  EX1_105 = 2, -- Mountain Giant
  EX1_620 = 2, -- Molten Giant
})

deck("WARLOCK", 4, "control", "Handlock", {
  EX1_302 = 2, -- Mortal Coil
  EX1_316 = 1, -- Power Overwhelming
  EX1_045 = 2, -- Ancient Watcher
  EX1_058 = 2, -- Sunfury Protector
  CS2_057 = 2, -- Shadow Bolt
  CS2_062 = 2, -- Hellfire
  EX1_303 = 2, -- Shadowflame
  EX1_309 = 1, -- Siphon Soul
  EX1_043 = 2, -- Twilight Drake
  EX1_093 = 2, -- Defender of Argus
  CS2_117 = 2, -- Earthen Ring Farseer
  GVG_069 = 2, -- Antique Healbot
  EX1_005 = 1, -- Big Game Hunter
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_116 = 1, -- Leeroy Jenkins
  EX1_323 = 1, -- Lord Jaraxxus
  EX1_105 = 2, -- Mountain Giant
  EX1_620 = 2, -- Molten Giant
})

deck("WARLOCK", 4, "control", "Demonlock", {
  EX1_302 = 2, -- Mortal Coil
  CS2_065 = 2, -- Voidwalker
  GVG_015 = 2, -- Darkbomb
  GVG_045 = 2, -- Imp-losion
  FP1_001 = 2, -- Zombie Chow
  FP1_022 = 2, -- Voidcaller
  CS2_062 = 2, -- Hellfire
  EX1_309 = 1, -- Siphon Soul
  EX1_005 = 1, -- Big Game Hunter
  GVG_096 = 2, -- Piloted Shredder
  GVG_069 = 1, -- Antique Healbot
  FP1_012 = 2, -- Sludge Belcher
  GVG_100 = 2, -- Floating Watcher
  EX1_310 = 2, -- Doomguard
  CS2_064 = 1, -- Dread Infernal
  EX1_016 = 1, -- Sylvanas Windrunner
  GVG_110 = 1, -- Dr. Boom
  EX1_323 = 1, -- Lord Jaraxxus
  GVG_021 = 1, -- Mal'Ganis
})

deck("WARLOCK", 5, "aggro", "Zoo", {
  EX1_319 = 2, -- Flame Imp
  CS2_065 = 2, -- Voidwalker
  EX1_316 = 1, -- Power Overwhelming
  EX1_308 = 2, -- Soulfire
  EX1_302 = 1, -- Mortal Coil
  CS2_188 = 1, -- Abusive Sergeant
  GVG_015 = 1, -- Darkbomb
  FP1_007 = 2, -- Nerubian Egg
  FP1_002 = 2, -- Haunted Creeper
  NEW1_019 = 2, -- Knife Juggler
  EX1_162 = 2, -- Dire Wolf Alpha
  GVG_045 = 2, -- Imp-losion
  EX1_556 = 1, -- Harvest Golem
  EX1_304 = 1, -- Void Terror
  GVG_096 = 2, -- Piloted Shredder
  EX1_093 = 2, -- Defender of Argus
  EX1_310 = 2, -- Doomguard
  FP1_030 = 1, -- Loatheb
  GVG_110 = 1, -- Dr. Boom
})

-- ================================================================ WARRIOR

deck("WARRIOR", 1, "midrange", "Basic Warrior", {
  CS2_108 = 2, -- Execute
  EX1_400 = 2, -- Whirlwind
  CS2_114 = 2, -- Cleave
  CS2_106 = 2, -- Fiery War Axe
  CS2_105 = 2, -- Heroic Strike
  CS2_103 = 1, -- Charge
  EX1_606 = 2, -- Shield Block
  EX1_084 = 1, -- Warsong Commander
  NEW1_011 = 2, -- Kor'kron Elite
  CS2_112 = 2, -- Arcanite Reaper
  CS2_172 = 2, -- Bloodfen Raptor
  CS2_120 = 2, -- River Crocolisk
  CS2_124 = 2, -- Wolfrider
  CS2_196 = 2, -- Razorfen Hunter
  CS2_182 = 2, -- Chillwind Yeti
  CS2_179 = 2, -- Sen'jin Shieldmasta
})

deck("WARRIOR", 2, "aggro", "Budget Aggro Warrior", {
  CS2_106 = 2, -- Fiery War Axe
  CS2_105 = 2, -- Heroic Strike
  EX1_409 = 2, -- Upgrade!
  EX1_603 = 2, -- Cruel Taskmaster
  EX1_604 = 2, -- Frothing Berserker
  NEW1_011 = 2, -- Kor'kron Elite
  CS2_112 = 2, -- Arcanite Reaper
  CS2_103 = 2, -- Charge
  EX1_029 = 2, -- Leper Gnome
  EX1_008 = 2, -- Argent Squire
  EX1_393 = 2, -- Amani Berserker
  CS2_124 = 2, -- Wolfrider
  EX1_412 = 2, -- Raging Worgen
  EX1_398 = 2, -- Arathi Weaponsmith
  NEW1_022 = 2, -- Dread Corsair
})

deck("WARRIOR", 3, "control", "Budget Control Warrior", {
  CS2_106 = 2, -- Fiery War Axe
  CS2_108 = 2, -- Execute
  EX1_410 = 2, -- Shield Slam
  EX1_400 = 1, -- Whirlwind
  EX1_391 = 2, -- Slam
  EX1_402 = 2, -- Armorsmith
  EX1_603 = 2, -- Cruel Taskmaster
  EX1_606 = 2, -- Shield Block
  FP1_021 = 2, -- Death's Bite
  EX1_407 = 1, -- Brawl
  EX1_007 = 2, -- Acolyte of Pain
  CS2_117 = 2, -- Earthen Ring Farseer
  CS2_179 = 2, -- Sen'jin Shieldmasta
  EX1_284 = 1, -- Azure Drake
  GVG_053 = 2, -- Shieldmaiden
  FP1_012 = 2, -- Sludge Belcher
  EX1_411 = 1, -- Gorehowl
})

deck("WARRIOR", 3, "aggro", "Mech Warrior", {
  GVG_051 = 2, -- Warbot
  GVG_013 = 2, -- Cogmaster
  GVG_006 = 2, -- Mechwarper
  GVG_085 = 2, -- Annoy-o-Tron
  CS2_106 = 2, -- Fiery War Axe
  CS2_108 = 2, -- Execute
  GVG_055 = 2, -- Screwjank Clunker
  GVG_044 = 2, -- Spider Tank
  GVG_102 = 2, -- Tinkertown Technician
  EX1_556 = 2, -- Harvest Golem
  FP1_021 = 2, -- Death's Bite
  GVG_096 = 2, -- Piloted Shredder
  GVG_078 = 2, -- Mechanical Yeti
  GVG_086 = 2, -- Siege Engine
  NEW1_011 = 1, -- Kor'kron Elite
  GVG_110 = 1, -- Dr. Boom
})

deck("WARRIOR", 4, "control", "Control Warrior", {
  CS2_106 = 2, -- Fiery War Axe
  CS2_108 = 2, -- Execute
  EX1_410 = 2, -- Shield Slam
  EX1_391 = 2, -- Slam
  EX1_402 = 2, -- Armorsmith
  EX1_603 = 2, -- Cruel Taskmaster
  EX1_606 = 2, -- Shield Block
  FP1_021 = 2, -- Death's Bite
  EX1_407 = 2, -- Brawl
  EX1_007 = 2, -- Acolyte of Pain
  EX1_005 = 1, -- Big Game Hunter
  FP1_012 = 2, -- Sludge Belcher
  EX1_411 = 1, -- Gorehowl
  EX1_558 = 1, -- Harrison Jones
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_249 = 1, -- Baron Geddon
  EX1_298 = 1, -- Ragnaros the Firelord
  EX1_414 = 1, -- Grommash Hellscream
  EX1_561 = 1, -- Alexstrasza
})

deck("WARRIOR", 4, "aggro", "Face Warrior", {
  EX1_409 = 2, -- Upgrade!
  CS2_106 = 2, -- Fiery War Axe
  CS2_105 = 2, -- Heroic Strike
  EX1_029 = 2, -- Leper Gnome
  NEW1_018 = 2, -- Bloodsail Raider
  EX1_603 = 2, -- Cruel Taskmaster
  EX1_604 = 2, -- Frothing Berserker
  CS2_124 = 2, -- Wolfrider
  NEW1_027 = 1, -- Southsea Captain
  CS2_103 = 1, -- Charge
  NEW1_022 = 2, -- Dread Corsair
  NEW1_011 = 2, -- Kor'kron Elite
  EX1_408 = 2, -- Mortal Strike
  FP1_021 = 2, -- Death's Bite
  CS2_112 = 2, -- Arcanite Reaper
  EX1_116 = 1, -- Leeroy Jenkins
  EX1_414 = 1, -- Grommash Hellscream
})

deck("WARRIOR", 5, "control", "Legend Control Warrior", {
  CS2_106 = 2, -- Fiery War Axe
  CS2_108 = 2, -- Execute
  EX1_410 = 2, -- Shield Slam
  EX1_391 = 1, -- Slam
  EX1_402 = 2, -- Armorsmith
  EX1_603 = 1, -- Cruel Taskmaster
  EX1_606 = 2, -- Shield Block
  FP1_021 = 2, -- Death's Bite
  EX1_407 = 2, -- Brawl
  EX1_007 = 2, -- Acolyte of Pain
  EX1_005 = 1, -- Big Game Hunter
  GVG_053 = 2, -- Shieldmaiden
  FP1_012 = 2, -- Sludge Belcher
  EX1_558 = 1, -- Harrison Jones
  EX1_016 = 1, -- Sylvanas Windrunner
  EX1_249 = 1, -- Baron Geddon
  GVG_110 = 1, -- Dr. Boom
  EX1_298 = 1, -- Ragnaros the Firelord
  EX1_414 = 1, -- Grommash Hellscream
  EX1_561 = 1, -- Alexstrasza
})

-- ============================================================== the API

--- A deck's thirty ids, sorted: the same list on every client and every run.
function BotDecks.Expand(d)
  local ids = {}
  for id in pairs(d.counts) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for _, id in ipairs(ids) do
    for _ = 1, d.counts[id] do out[#out + 1] = id end
  end
  return out
end

--- Every deck for a class, weakest first.
function BotDecks.List(class)
  local out = {}
  for _, d in ipairs(LISTS[class] or {}) do out[#out + 1] = d end
  table.sort(out, function(a, b)
    if a.tier ~= b.tier then return a.tier < b.tier end
    return a.name < b.name
  end)
  return out
end

--- Every class with decks.
function BotDecks.Classes()
  local out = {}
  for class in pairs(LISTS) do out[#out + 1] = class end
  table.sort(out)
  return out
end

--[[ The deck the bot brings for `class` at difficulty `tier`.

     Every deck of that exact tier is a candidate; with none, the nearest tier
     (weaker preferred on a tie, so a gap in the lists never makes the bot
     harder than was asked for). `roll(1, n)` picks among candidates: the
     caller passes math.random, which is safe here because the deck is chosen
     before the game exists -- exactly like choosing the opponent's class. With
     no roll the first candidate is taken, which tests rely on. ]]
function BotDecks.Pick(class, tier, roll)
  local list = LISTS[class]
  if not list or #list == 0 then return nil end
  tier = math.max(1, math.min(BotDecks.TIERS, tier or 3))
  local best
  for _, d in ipairs(list) do
    local dist = math.abs(d.tier - tier) * 2 + (d.tier > tier and 1 or 0)
    if not best or dist < best then best = dist end
  end
  local pool = {}
  for _, d in ipairs(BotDecks.List(class)) do
    local dist = math.abs(d.tier - tier) * 2 + (d.tier > tier and 1 or 0)
    if dist == best then pool[#pool + 1] = d end
  end
  local i = roll and roll(1, #pool) or 1
  return pool[math.max(1, math.min(#pool, i or 1))]
end

return BotDecks
