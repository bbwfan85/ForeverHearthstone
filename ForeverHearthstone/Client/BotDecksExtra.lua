-- GENERATED FILE -- DO NOT EDIT BY HAND.
-- Regenerate with: python tools/build_bot_decks.py (source: tools/bot-decks-extra.txt)
-- More ladder decks, so every class has several at every tier (docs/45).
local ADDON, ns = ...
local add = ns.BotDecks.Add
add("MAGE", 1, "aggro", "Basic Aggro Mage", {
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_029"] = 2, -- Fireball
  ["CS2_033"] = 2, -- Water Elemental
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_142"] = 2, -- Kobold Geomancer
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_200"] = 1, -- Boulderfist Ogre
  ["CS2_222"] = 1, -- Stormwind Champion
  ["EX1_277"] = 2, -- Arcane Missiles
  ["EX1_582"] = 2, -- Dalaran Mage
})
add("MAGE", 1, "control", "Basic Control Mage", {
  ["CS2_022"] = 2, -- Polymorph
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_025"] = 2, -- Arcane Explosion
  ["CS2_026"] = 2, -- Frost Nova
  ["CS2_029"] = 2, -- Fireball
  ["CS2_032"] = 2, -- Flamestrike
  ["CS2_033"] = 2, -- Water Elemental
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_155"] = 2, -- Archmage
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_222"] = 1, -- Stormwind Champion
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
})
add("MAGE", 2, "control", "Budget Freeze Mage", {
  ["CS2_022"] = 1, -- Polymorph
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_026"] = 2, -- Frost Nova
  ["CS2_028"] = 2, -- Blizzard
  ["CS2_029"] = 2, -- Fireball
  ["CS2_031"] = 2, -- Ice Lance
  ["CS2_032"] = 1, -- Flamestrike
  ["CS2_033"] = 2, -- Water Elemental
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_096"] = 2, -- Loot Hoarder
  ["EX1_275"] = 1, -- Cone of Cold
  ["EX1_289"] = 2, -- Ice Barrier
  ["EX1_295"] = 1, -- Ice Block
  ["FP1_004"] = 2, -- Mad Scientist
  ["NEW1_021"] = 2, -- Doomsayer
})
add("MAGE", 2, "midrange", "Budget Spell Mage", {
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_027"] = 2, -- Mirror Image
  ["CS2_029"] = 2, -- Fireball
  ["CS2_032"] = 2, -- Flamestrike
  ["CS2_033"] = 2, -- Water Elemental
  ["EX1_274"] = 2, -- Ethereal Arcanist
  ["EX1_277"] = 2, -- Arcane Missiles
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_287"] = 1, -- Counterspell
  ["EX1_294"] = 1, -- Mirror Entity
  ["EX1_608"] = 2, -- Sorcerer's Apprentice
  ["EX1_612"] = 2, -- Kirin Tor Mage
  ["GVG_001"] = 2, -- Flamecannon
  ["GVG_003"] = 2, -- Unstable Portal
  ["NEW1_012"] = 2, -- Mana Wyrm
})
add("MAGE", 3, "midrange", "Mech Giants Mage", {
  ["CS2_022"] = 2, -- Polymorph
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_029"] = 2, -- Fireball
  ["CS2_032"] = 1, -- Flamestrike
  ["CS2_033"] = 2, -- Water Elemental
  ["EX1_105"] = 2, -- Mountain Giant
  ["GVG_002"] = 2, -- Snowchugger
  ["GVG_003"] = 2, -- Unstable Portal
  ["GVG_004"] = 2, -- Goblin Blastmage
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_082"] = 2, -- Clockwork Gnome
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_012"] = 2, -- Mana Wyrm
})
add("MAGE", 4, "control", "Antonidas Freeze Mage", {
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_026"] = 2, -- Frost Nova
  ["CS2_028"] = 2, -- Blizzard
  ["CS2_029"] = 2, -- Fireball
  ["CS2_031"] = 2, -- Ice Lance
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_012"] = 1, -- Bloodmage Thalnos
  ["EX1_015"] = 1, -- Novice Engineer
  ["EX1_096"] = 2, -- Loot Hoarder
  ["EX1_275"] = 1, -- Cone of Cold
  ["EX1_289"] = 2, -- Ice Barrier
  ["EX1_295"] = 2, -- Ice Block
  ["EX1_559"] = 1, -- Archmage Antonidas
  ["EX1_561"] = 1, -- Alexstrasza
  ["FP1_004"] = 2, -- Mad Scientist
  ["GVG_069"] = 1, -- Antique Healbot
  ["NEW1_021"] = 2, -- Doomsayer
})
add("MAGE", 5, "aggro", "Legend Mech Mage", {
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_029"] = 2, -- Fireball
  ["EX1_277"] = 2, -- Arcane Missiles
  ["GVG_001"] = 2, -- Flamecannon
  ["GVG_002"] = 2, -- Snowchugger
  ["GVG_003"] = 2, -- Unstable Portal
  ["GVG_004"] = 2, -- Goblin Blastmage
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_016"] = 1, -- Fel Reaver
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_082"] = 2, -- Clockwork Gnome
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_102"] = 1, -- Tinkertown Technician
  ["GVG_105"] = 1, -- Piloted Sky Golem
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_012"] = 2, -- Mana Wyrm
})
add("MAGE", 5, "control", "Control Mage", {
  ["CS2_022"] = 2, -- Polymorph
  ["CS2_023"] = 2, -- Arcane Intellect
  ["CS2_024"] = 2, -- Frostbolt
  ["CS2_028"] = 2, -- Blizzard
  ["CS2_029"] = 2, -- Fireball
  ["CS2_032"] = 2, -- Flamestrike
  ["CS2_033"] = 2, -- Water Elemental
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_289"] = 2, -- Ice Barrier
  ["EX1_294"] = 1, -- Mirror Entity
  ["EX1_295"] = 1, -- Ice Block
  ["EX1_298"] = 1, -- Ragnaros the Firelord
  ["EX1_561"] = 1, -- Alexstrasza
  ["FP1_004"] = 2, -- Mad Scientist
  ["FP1_012"] = 2, -- Sludge Belcher
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
})
add("HUNTER", 1, "midrange", "Basic Beast Hunter", {
  ["CS2_084"] = 1, -- Hunter's Mark
  ["CS2_119"] = 2, -- Oasis Snapjaw
  ["CS2_120"] = 2, -- River Crocolisk
  ["CS2_125"] = 2, -- Ironfur Grizzly
  ["CS2_127"] = 2, -- Silverback Patriarch
  ["CS2_171"] = 1, -- Stonetusk Boar
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_201"] = 2, -- Core Hound
  ["CS2_237"] = 2, -- Starving Buzzard
  ["DS1_070"] = 2, -- Houndmaster
  ["DS1_175"] = 2, -- Timber Wolf
  ["DS1_178"] = 2, -- Tundra Rhino
  ["DS1_183"] = 2, -- Multi-Shot
  ["DS1_185"] = 2, -- Arcane Shot
  ["EX1_539"] = 2, -- Kill Command
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 1, "aggro", "Basic Rush Hunter", {
  ["CS2_084"] = 2, -- Hunter's Mark
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_171"] = 2, -- Stonetusk Boar
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_196"] = 2, -- Razorfen Hunter
  ["CS2_213"] = 2, -- Reckless Rocketeer
  ["DS1_070"] = 2, -- Houndmaster
  ["DS1_175"] = 2, -- Timber Wolf
  ["DS1_184"] = 2, -- Tracking
  ["DS1_185"] = 2, -- Arcane Shot
  ["EX1_539"] = 2, -- Kill Command
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 2, "midrange", "Budget Trap Hunter", {
  ["CS2_084"] = 1, -- Hunter's Mark
  ["DS1_070"] = 2, -- Houndmaster
  ["DS1_183"] = 2, -- Multi-Shot
  ["DS1_185"] = 1, -- Arcane Shot
  ["EX1_531"] = 2, -- Scavenging Hyena
  ["EX1_536"] = 2, -- Eaglehorn Bow
  ["EX1_538"] = 2, -- Unleash the Hounds
  ["EX1_539"] = 2, -- Kill Command
  ["EX1_554"] = 2, -- Snake Trap
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_610"] = 2, -- Explosive Trap
  ["EX1_611"] = 2, -- Freezing Trap
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_004"] = 2, -- Mad Scientist
  ["FP1_011"] = 2, -- Webspinner
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 2, "aggro", "Budget Mech Hunter", {
  ["DS1_070"] = 2, -- Houndmaster
  ["DS1_185"] = 2, -- Arcane Shot
  ["EX1_536"] = 2, -- Eaglehorn Bow
  ["EX1_539"] = 2, -- Kill Command
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_610"] = 2, -- Explosive Trap
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_013"] = 2, -- Cogmaster
  ["GVG_043"] = 2, -- Glaivezooka
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_048"] = 2, -- Metaltooth Leaper
  ["GVG_082"] = 2, -- Clockwork Gnome
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 3, "midrange", "Naxx Midrange Hunter", {
  ["CS2_084"] = 1, -- Hunter's Mark
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["DS1_070"] = 2, -- Houndmaster
  ["EX1_110"] = 1, -- Cairne Bloodhoof
  ["EX1_534"] = 2, -- Savannah Highmane
  ["EX1_536"] = 2, -- Eaglehorn Bow
  ["EX1_538"] = 1, -- Unleash the Hounds
  ["EX1_539"] = 2, -- Kill Command
  ["EX1_544"] = 1, -- Flare
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_610"] = 1, -- Explosive Trap
  ["EX1_611"] = 1, -- Freezing Trap
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_004"] = 2, -- Mad Scientist
  ["FP1_011"] = 2, -- Webspinner
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_030"] = 1, -- Loatheb
  ["NEW1_019"] = 2, -- Knife Juggler
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 4, "midrange", "Gahz'rilla Hunter", {
  ["CS2_084"] = 2, -- Hunter's Mark
  ["DS1_070"] = 2, -- Houndmaster
  ["EX1_534"] = 2, -- Savannah Highmane
  ["EX1_536"] = 2, -- Eaglehorn Bow
  ["EX1_538"] = 1, -- Unleash the Hounds
  ["EX1_539"] = 2, -- Kill Command
  ["EX1_610"] = 1, -- Explosive Trap
  ["EX1_611"] = 2, -- Freezing Trap
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_004"] = 2, -- Mad Scientist
  ["FP1_011"] = 2, -- Webspinner
  ["FP1_012"] = 2, -- Sludge Belcher
  ["GVG_043"] = 1, -- Glaivezooka
  ["GVG_049"] = 1, -- Gahz'rilla
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 5, "midrange", "Legend Midrange Hunter", {
  ["CS2_084"] = 1, -- Hunter's Mark
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["DS1_070"] = 2, -- Houndmaster
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_534"] = 2, -- Savannah Highmane
  ["EX1_536"] = 2, -- Eaglehorn Bow
  ["EX1_538"] = 1, -- Unleash the Hounds
  ["EX1_539"] = 2, -- Kill Command
  ["EX1_610"] = 1, -- Explosive Trap
  ["EX1_611"] = 2, -- Freezing Trap
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_004"] = 2, -- Mad Scientist
  ["FP1_011"] = 2, -- Webspinner
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_043"] = 1, -- Glaivezooka
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_019"] = 2, -- Knife Juggler
  ["NEW1_031"] = 2, -- Animal Companion
})
add("HUNTER", 5, "aggro", "Legend Undertaker Hunter", {
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_188"] = 1, -- Abusive Sergeant
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_089"] = 2, -- Arcane Golem
  ["EX1_116"] = 1, -- Leeroy Jenkins
  ["EX1_536"] = 2, -- Eaglehorn Bow
  ["EX1_538"] = 2, -- Unleash the Hounds
  ["EX1_539"] = 2, -- Kill Command
  ["EX1_610"] = 1, -- Explosive Trap
  ["EX1_611"] = 1, -- Freezing Trap
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_004"] = 2, -- Mad Scientist
  ["FP1_011"] = 2, -- Webspinner
  ["FP1_028"] = 2, -- Undertaker
  ["GVG_043"] = 2, -- Glaivezooka
  ["NEW1_019"] = 2, -- Knife Juggler
  ["NEW1_031"] = 2, -- Animal Companion
})
add("WARRIOR", 1, "aggro", "Basic Charge Warrior", {
  ["CS2_103"] = 2, -- Charge
  ["CS2_105"] = 2, -- Heroic Strike
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_112"] = 2, -- Arcanite Reaper
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_131"] = 2, -- Stormwind Knight
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_171"] = 2, -- Stonetusk Boar
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_173"] = 2, -- Bluegill Warrior
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_213"] = 2, -- Reckless Rocketeer
  ["EX1_084"] = 2, -- Warsong Commander
  ["NEW1_011"] = 2, -- Kor'kron Elite
})
add("WARRIOR", 1, "control", "Basic Control Warrior", {
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 2, -- Execute
  ["CS2_112"] = 2, -- Arcanite Reaper
  ["CS2_114"] = 2, -- Cleave
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_162"] = 2, -- Lord of the Arena
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_222"] = 1, -- Stormwind Champion
  ["CS2_226"] = 2, -- Frostwolf Warlord
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_399"] = 2, -- Gurubashi Berserker
  ["EX1_400"] = 2, -- Whirlwind
  ["EX1_606"] = 2, -- Shield Block
  ["NEW1_011"] = 2, -- Kor'kron Elite
})
add("WARRIOR", 2, "aggro", "Budget Frothing Warrior", {
  ["CS2_105"] = 2, -- Heroic Strike
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 1, -- Execute
  ["CS2_112"] = 2, -- Arcanite Reaper
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_084"] = 1, -- Warsong Commander
  ["EX1_392"] = 1, -- Battle Rage
  ["EX1_393"] = 2, -- Amani Berserker
  ["EX1_398"] = 2, -- Arathi Weaponsmith
  ["EX1_400"] = 1, -- Whirlwind
  ["EX1_402"] = 2, -- Armorsmith
  ["EX1_603"] = 2, -- Cruel Taskmaster
  ["EX1_604"] = 2, -- Frothing Berserker
  ["EX1_607"] = 2, -- Inner Rage
  ["FP1_021"] = 2, -- Death's Bite
  ["FP1_024"] = 2, -- Unstable Ghoul
  ["NEW1_011"] = 2, -- Kor'kron Elite
})
add("WARRIOR", 2, "control", "Budget Taunt Warrior", {
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 2, -- Execute
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_402"] = 2, -- Armorsmith
  ["EX1_407"] = 1, -- Brawl
  ["EX1_410"] = 2, -- Shield Slam
  ["EX1_411"] = 1, -- Gorehowl
  ["EX1_603"] = 1, -- Cruel Taskmaster
  ["EX1_606"] = 2, -- Shield Block
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_021"] = 2, -- Death's Bite
  ["FP1_024"] = 2, -- Unstable Ghoul
  ["GVG_053"] = 2, -- Shieldmaiden
  ["GVG_069"] = 1, -- Antique Healbot
})
add("WARRIOR", 3, "aggro", "Worgen Combo Warrior", {
  ["CS2_103"] = 2, -- Charge
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 2, -- Execute
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_391"] = 2, -- Slam
  ["EX1_392"] = 2, -- Battle Rage
  ["EX1_400"] = 2, -- Whirlwind
  ["EX1_402"] = 2, -- Armorsmith
  ["EX1_412"] = 2, -- Raging Worgen
  ["EX1_603"] = 2, -- Cruel Taskmaster
  ["EX1_604"] = 2, -- Frothing Berserker
  ["EX1_606"] = 2, -- Shield Block
  ["EX1_607"] = 2, -- Inner Rage
  ["FP1_021"] = 1, -- Death's Bite
  ["FP1_024"] = 2, -- Unstable Ghoul
  ["NEW1_036"] = 1, -- Commanding Shout
})
add("WARRIOR", 4, "control", "Ysera Control Warrior", {
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 2, -- Execute
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_249"] = 1, -- Baron Geddon
  ["EX1_391"] = 1, -- Slam
  ["EX1_402"] = 2, -- Armorsmith
  ["EX1_407"] = 2, -- Brawl
  ["EX1_410"] = 2, -- Shield Slam
  ["EX1_414"] = 1, -- Grommash Hellscream
  ["EX1_558"] = 1, -- Harrison Jones
  ["EX1_561"] = 1, -- Alexstrasza
  ["EX1_572"] = 1, -- Ysera
  ["EX1_603"] = 1, -- Cruel Taskmaster
  ["EX1_606"] = 2, -- Shield Block
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_021"] = 2, -- Death's Bite
  ["GVG_053"] = 2, -- Shieldmaiden
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_110"] = 1, -- Dr. Boom
})
add("WARRIOR", 5, "aggro", "Legend Mech Warrior", {
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 1, -- Execute
  ["EX1_409"] = 1, -- Upgrade!
  ["EX1_556"] = 2, -- Harvest Golem
  ["FP1_021"] = 2, -- Death's Bite
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_013"] = 2, -- Cogmaster
  ["GVG_016"] = 2, -- Fel Reaver
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_051"] = 2, -- Warbot
  ["GVG_055"] = 2, -- Screwjank Clunker
  ["GVG_056"] = 1, -- Iron Juggernaut
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_105"] = 2, -- Piloted Sky Golem
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_011"] = 2, -- Kor'kron Elite
})
add("WARRIOR", 5, "control", "Deathlord Fatigue Warrior", {
  ["CS2_106"] = 2, -- Fiery War Axe
  ["CS2_108"] = 2, -- Execute
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_110"] = 1, -- Cairne Bloodhoof
  ["EX1_249"] = 1, -- Baron Geddon
  ["EX1_402"] = 2, -- Armorsmith
  ["EX1_407"] = 2, -- Brawl
  ["EX1_410"] = 2, -- Shield Slam
  ["EX1_414"] = 1, -- Grommash Hellscream
  ["EX1_558"] = 1, -- Harrison Jones
  ["EX1_606"] = 2, -- Shield Block
  ["FP1_009"] = 2, -- Deathlord
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_021"] = 2, -- Death's Bite
  ["GVG_053"] = 2, -- Shieldmaiden
  ["GVG_069"] = 2, -- Antique Healbot
})
add("PALADIN", 1, "aggro", "Basic Aggro Paladin", {
  ["CS2_087"] = 2, -- Blessing of Might
  ["CS2_091"] = 2, -- Light's Justice
  ["CS2_092"] = 2, -- Blessing of Kings
  ["CS2_094"] = 2, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_131"] = 2, -- Stormwind Knight
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_213"] = 2, -- Reckless Rocketeer
  ["CS2_222"] = 2, -- Stormwind Champion
})
add("PALADIN", 1, "control", "Basic Control Paladin", {
  ["CS2_088"] = 2, -- Guardian of Kings
  ["CS2_089"] = 2, -- Holy Light
  ["CS2_091"] = 1, -- Light's Justice
  ["CS2_092"] = 2, -- Blessing of Kings
  ["CS2_093"] = 2, -- Consecration
  ["CS2_094"] = 2, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_162"] = 2, -- Lord of the Arena
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_222"] = 2, -- Stormwind Champion
  ["DS1_055"] = 2, -- Darkscale Healer
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_360"] = 2, -- Humility
})
add("PALADIN", 2, "aggro", "Budget Divine Favor Paladin", {
  ["CS2_087"] = 2, -- Blessing of Might
  ["CS2_092"] = 2, -- Blessing of Kings
  ["CS2_097"] = 2, -- Truesilver Champion
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_188"] = 2, -- Abusive Sergeant
  ["EX1_008"] = 2, -- Argent Squire
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_089"] = 2, -- Arcane Golem
  ["EX1_349"] = 2, -- Divine Favor
  ["EX1_362"] = 2, -- Argent Protector
  ["EX1_556"] = 2, -- Harvest Golem
  ["FP1_002"] = 2, -- Haunted Creeper
  ["GVG_058"] = 2, -- Shielded Minibot
  ["GVG_061"] = 2, -- Muster for Battle
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("PALADIN", 2, "control", "Budget Control Paladin", {
  ["CS2_088"] = 2, -- Guardian of Kings
  ["CS2_089"] = 1, -- Holy Light
  ["CS2_093"] = 2, -- Consecration
  ["CS2_094"] = 2, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["CS2_117"] = 2, -- Earthen Ring Farseer
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_354"] = 1, -- Lay on Hands
  ["EX1_382"] = 2, -- Aldor Peacekeeper
  ["EX1_384"] = 1, -- Avenging Wrath
  ["EX1_556"] = 1, -- Harvest Golem
  ["EX1_619"] = 2, -- Equality
  ["FP1_012"] = 2, -- Sludge Belcher
  ["NEW1_020"] = 2, -- Wild Pyromancer
})
add("PALADIN", 3, "midrange", "Shielded Minibot Paladin", {
  ["CS2_093"] = 2, -- Consecration
  ["CS2_094"] = 1, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_130"] = 1, -- Noble Sacrifice
  ["EX1_382"] = 2, -- Aldor Peacekeeper
  ["EX1_384"] = 1, -- Avenging Wrath
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_619"] = 2, -- Equality
  ["FP1_012"] = 2, -- Sludge Belcher
  ["GVG_058"] = 2, -- Shielded Minibot
  ["GVG_059"] = 1, -- Coghammer
  ["GVG_060"] = 2, -- Quartermaster
  ["GVG_061"] = 2, -- Muster for Battle
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("PALADIN", 4, "control", "Tirion Control Paladin", {
  ["CS2_088"] = 1, -- Guardian of Kings
  ["CS2_093"] = 2, -- Consecration
  ["CS2_094"] = 1, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_007"] = 2, -- Acolyte of Pain
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_093"] = 1, -- Defender of Argus
  ["EX1_110"] = 1, -- Cairne Bloodhoof
  ["EX1_298"] = 1, -- Ragnaros the Firelord
  ["EX1_354"] = 1, -- Lay on Hands
  ["EX1_382"] = 2, -- Aldor Peacekeeper
  ["EX1_383"] = 1, -- Tirion Fordring
  ["EX1_384"] = 1, -- Avenging Wrath
  ["EX1_558"] = 1, -- Harrison Jones
  ["EX1_572"] = 1, -- Ysera
  ["EX1_619"] = 2, -- Equality
  ["FP1_012"] = 2, -- Sludge Belcher
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_020"] = 2, -- Wild Pyromancer
  ["NEW1_021"] = 1, -- Doomsayer
})
add("PALADIN", 5, "midrange", "Legend Midrange Paladin", {
  ["CS2_093"] = 2, -- Consecration
  ["CS2_094"] = 1, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_382"] = 2, -- Aldor Peacekeeper
  ["EX1_383"] = 1, -- Tirion Fordring
  ["EX1_384"] = 1, -- Avenging Wrath
  ["EX1_619"] = 1, -- Equality
  ["FP1_001"] = 1, -- Zombie Chow
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_058"] = 2, -- Shielded Minibot
  ["GVG_059"] = 1, -- Coghammer
  ["GVG_060"] = 2, -- Quartermaster
  ["GVG_061"] = 2, -- Muster for Battle
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_019"] = 1, -- Knife Juggler
})
add("PALADIN", 5, "aggro", "Legend Aggro Paladin", {
  ["CS2_087"] = 1, -- Blessing of Might
  ["CS2_092"] = 2, -- Blessing of Kings
  ["CS2_094"] = 1, -- Hammer of Wrath
  ["CS2_097"] = 2, -- Truesilver Champion
  ["CS2_188"] = 1, -- Abusive Sergeant
  ["EX1_008"] = 2, -- Argent Squire
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_089"] = 2, -- Arcane Golem
  ["EX1_116"] = 1, -- Leeroy Jenkins
  ["EX1_349"] = 2, -- Divine Favor
  ["EX1_362"] = 2, -- Argent Protector
  ["EX1_384"] = 1, -- Avenging Wrath
  ["GVG_058"] = 2, -- Shielded Minibot
  ["GVG_059"] = 1, -- Coghammer
  ["GVG_061"] = 2, -- Muster for Battle
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("PRIEST", 1, "midrange", "Basic Divine Spirit Priest", {
  ["CS1_112"] = 2, -- Holy Nova
  ["CS1_113"] = 1, -- Mind Control
  ["CS1_130"] = 2, -- Holy Smite
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_120"] = 2, -- River Crocolisk
  ["CS2_142"] = 2, -- Kobold Geomancer
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_234"] = 2, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["CS2_236"] = 2, -- Divine Spirit
  ["DS1_233"] = 1, -- Mind Blast
  ["EX1_019"] = 2, -- Shattered Sun Cleric
  ["EX1_622"] = 2, -- Shadow Word: Death
})
add("PRIEST", 1, "aggro", "Basic Mind Blast Priest", {
  ["CS1_130"] = 2, -- Holy Smite
  ["CS2_003"] = 1, -- Mind Vision
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_142"] = 2, -- Kobold Geomancer
  ["CS2_150"] = 2, -- Stormpike Commando
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_213"] = 2, -- Reckless Rocketeer
  ["CS2_234"] = 2, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["CS2_236"] = 1, -- Divine Spirit
  ["DS1_233"] = 2, -- Mind Blast
  ["EX1_582"] = 2, -- Dalaran Mage
})
add("PRIEST", 2, "control", "Budget Control Priest", {
  ["CS1_112"] = 2, -- Holy Nova
  ["CS1_113"] = 1, -- Mind Control
  ["CS1_130"] = 1, -- Holy Smite
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_181"] = 2, -- Injured Blademaster
  ["CS2_234"] = 2, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["EX1_335"] = 2, -- Lightspawn
  ["EX1_339"] = 2, -- Thoughtsteal
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_591"] = 2, -- Auchenai Soulpriest
  ["EX1_621"] = 1, -- Circle of Healing
  ["EX1_622"] = 2, -- Shadow Word: Death
  ["FP1_001"] = 1, -- Zombie Chow
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_023"] = 2, -- Dark Cultist
  ["NEW1_020"] = 2, -- Wild Pyromancer
})
add("PRIEST", 2, "midrange", "Budget Velen's Chosen Priest", {
  ["CS1_113"] = 1, -- Mind Control
  ["CS1_130"] = 1, -- Holy Smite
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_234"] = 2, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["DS1_233"] = 1, -- Mind Blast
  ["EX1_335"] = 2, -- Lightspawn
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_622"] = 2, -- Shadow Word: Death
  ["EX1_624"] = 1, -- Holy Fire
  ["FP1_001"] = 2, -- Zombie Chow
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_023"] = 2, -- Dark Cultist
  ["GVG_010"] = 2, -- Velen's Chosen
  ["GVG_072"] = 2, -- Shadowboxer
  ["GVG_096"] = 2, -- Piloted Shredder
})
add("PRIEST", 3, "control", "Lightbomb Priest", {
  ["CS1_112"] = 1, -- Holy Nova
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_181"] = 1, -- Injured Blademaster
  ["CS2_234"] = 1, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_091"] = 1, -- Cabal Shadow Priest
  ["EX1_339"] = 1, -- Thoughtsteal
  ["EX1_591"] = 2, -- Auchenai Soulpriest
  ["EX1_621"] = 1, -- Circle of Healing
  ["EX1_622"] = 2, -- Shadow Word: Death
  ["FP1_001"] = 2, -- Zombie Chow
  ["FP1_009"] = 2, -- Deathlord
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_023"] = 2, -- Dark Cultist
  ["GVG_008"] = 2, -- Lightbomb
  ["GVG_010"] = 1, -- Velen's Chosen
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_020"] = 1, -- Wild Pyromancer
})
add("PRIEST", 4, "control", "Vol'jin Priest", {
  ["CS1_112"] = 1, -- Holy Nova
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_181"] = 1, -- Injured Blademaster
  ["CS2_234"] = 2, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_091"] = 1, -- Cabal Shadow Priest
  ["EX1_339"] = 1, -- Thoughtsteal
  ["EX1_591"] = 1, -- Auchenai Soulpriest
  ["EX1_621"] = 1, -- Circle of Healing
  ["EX1_622"] = 2, -- Shadow Word: Death
  ["FP1_001"] = 2, -- Zombie Chow
  ["FP1_009"] = 2, -- Deathlord
  ["FP1_013"] = 1, -- Kel'Thuzad
  ["FP1_023"] = 2, -- Dark Cultist
  ["GVG_008"] = 1, -- Lightbomb
  ["GVG_010"] = 2, -- Velen's Chosen
  ["GVG_014"] = 1, -- Vol'jin
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
})
add("PRIEST", 5, "control", "Legend Lightbomb Priest", {
  ["CS1_112"] = 1, -- Holy Nova
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_234"] = 1, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_091"] = 1, -- Cabal Shadow Priest
  ["EX1_339"] = 1, -- Thoughtsteal
  ["EX1_572"] = 1, -- Ysera
  ["EX1_591"] = 2, -- Auchenai Soulpriest
  ["EX1_621"] = 1, -- Circle of Healing
  ["EX1_622"] = 2, -- Shadow Word: Death
  ["FP1_001"] = 2, -- Zombie Chow
  ["FP1_009"] = 2, -- Deathlord
  ["FP1_023"] = 2, -- Dark Cultist
  ["GVG_008"] = 2, -- Lightbomb
  ["GVG_010"] = 2, -- Velen's Chosen
  ["GVG_014"] = 1, -- Vol'jin
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 1, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_020"] = 1, -- Wild Pyromancer
})
add("PRIEST", 5, "midrange", "Legend Inner Fire Priest", {
  ["CS1_129"] = 2, -- Inner Fire
  ["CS1_130"] = 1, -- Holy Smite
  ["CS2_004"] = 2, -- Power Word: Shield
  ["CS2_181"] = 1, -- Injured Blademaster
  ["CS2_234"] = 1, -- Shadow Word: Pain
  ["CS2_235"] = 2, -- Northshire Cleric
  ["CS2_236"] = 2, -- Divine Spirit
  ["DS1_233"] = 2, -- Mind Blast
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_335"] = 2, -- Lightspawn
  ["EX1_350"] = 1, -- Prophet Velen
  ["EX1_591"] = 1, -- Auchenai Soulpriest
  ["EX1_622"] = 1, -- Shadow Word: Death
  ["FP1_001"] = 2, -- Zombie Chow
  ["FP1_023"] = 2, -- Dark Cultist
  ["GVG_010"] = 2, -- Velen's Chosen
  ["GVG_072"] = 2, -- Shadowboxer
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
})
add("ROGUE", 1, "aggro", "Basic Aggro Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_074"] = 2, -- Deadly Poison
  ["CS2_075"] = 2, -- Sinister Strike
  ["CS2_080"] = 1, -- Assassin's Blade
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_131"] = 2, -- Stormwind Knight
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_196"] = 2, -- Razorfen Hunter
  ["CS2_213"] = 2, -- Reckless Rocketeer
  ["EX1_019"] = 2, -- Shattered Sun Cleric
  ["EX1_278"] = 1, -- Shiv
})
add("ROGUE", 1, "midrange", "Basic Tempo Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_074"] = 2, -- Deadly Poison
  ["CS2_076"] = 2, -- Assassinate
  ["CS2_080"] = 1, -- Assassin's Blade
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_129"] = 2, -- Fan of Knives
  ["EX1_278"] = 2, -- Shiv
  ["EX1_581"] = 2, -- Sap
  ["EX1_582"] = 2, -- Dalaran Mage
  ["EX1_593"] = 2, -- Nightblade
})
add("ROGUE", 2, "midrange", "Budget Miracle Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_073"] = 2, -- Cold Blood
  ["CS2_074"] = 2, -- Deadly Poison
  ["CS2_076"] = 1, -- Assassinate
  ["CS2_117"] = 1, -- Earthen Ring Farseer
  ["CS2_233"] = 1, -- Blade Flurry
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_096"] = 2, -- Loot Hoarder
  ["EX1_124"] = 2, -- Eviscerate
  ["EX1_128"] = 2, -- Conceal
  ["EX1_129"] = 2, -- Fan of Knives
  ["EX1_131"] = 2, -- Defias Ringleader
  ["EX1_134"] = 2, -- SI:7 Agent
  ["EX1_145"] = 2, -- Preparation
  ["EX1_278"] = 2, -- Shiv
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_581"] = 1, -- Sap
})
add("ROGUE", 2, "aggro", "Budget Combo Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_073"] = 2, -- Cold Blood
  ["CS2_074"] = 2, -- Deadly Poison
  ["CS2_080"] = 2, -- Assassin's Blade
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_146"] = 2, -- Southsea Deckhand
  ["CS2_233"] = 1, -- Blade Flurry
  ["EX1_008"] = 2, -- Argent Squire
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_089"] = 2, -- Arcane Golem
  ["EX1_124"] = 2, -- Eviscerate
  ["EX1_131"] = 2, -- Defias Ringleader
  ["EX1_134"] = 2, -- SI:7 Agent
  ["EX1_581"] = 1, -- Sap
  ["NEW1_018"] = 2, -- Bloodsail Raider
  ["NEW1_022"] = 2, -- Dread Corsair
})
add("ROGUE", 3, "midrange", "Naxx Tempo Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_074"] = 2, -- Deadly Poison
  ["CS2_117"] = 1, -- Earthen Ring Farseer
  ["CS2_233"] = 1, -- Blade Flurry
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_046"] = 2, -- Dark Iron Dwarf
  ["EX1_096"] = 2, -- Loot Hoarder
  ["EX1_110"] = 1, -- Cairne Bloodhoof
  ["EX1_124"] = 2, -- Eviscerate
  ["EX1_129"] = 1, -- Fan of Knives
  ["EX1_134"] = 2, -- SI:7 Agent
  ["EX1_145"] = 1, -- Preparation
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_581"] = 2, -- Sap
  ["EX1_613"] = 1, -- Edwin VanCleef
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
})
add("ROGUE", 4, "midrange", "Malygos Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_075"] = 2, -- Sinister Strike
  ["CS2_077"] = 1, -- Sprint
  ["CS2_117"] = 1, -- Earthen Ring Farseer
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_012"] = 1, -- Bloodmage Thalnos
  ["EX1_015"] = 1, -- Novice Engineer
  ["EX1_095"] = 2, -- Gadgetzan Auctioneer
  ["EX1_096"] = 2, -- Loot Hoarder
  ["EX1_124"] = 2, -- Eviscerate
  ["EX1_128"] = 1, -- Conceal
  ["EX1_129"] = 2, -- Fan of Knives
  ["EX1_134"] = 2, -- SI:7 Agent
  ["EX1_145"] = 2, -- Preparation
  ["EX1_278"] = 2, -- Shiv
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_563"] = 1, -- Malygos
  ["EX1_581"] = 1, -- Sap
  ["GVG_069"] = 1, -- Antique Healbot
  ["NEW1_004"] = 1, -- Vanish
})
add("ROGUE", 5, "midrange", "Legend Miracle Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_073"] = 2, -- Cold Blood
  ["CS2_074"] = 1, -- Deadly Poison
  ["CS2_117"] = 1, -- Earthen Ring Farseer
  ["CS2_233"] = 1, -- Blade Flurry
  ["EX1_012"] = 1, -- Bloodmage Thalnos
  ["EX1_095"] = 2, -- Gadgetzan Auctioneer
  ["EX1_096"] = 2, -- Loot Hoarder
  ["EX1_116"] = 1, -- Leeroy Jenkins
  ["EX1_124"] = 2, -- Eviscerate
  ["EX1_128"] = 2, -- Conceal
  ["EX1_129"] = 2, -- Fan of Knives
  ["EX1_134"] = 2, -- SI:7 Agent
  ["EX1_145"] = 2, -- Preparation
  ["EX1_278"] = 1, -- Shiv
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_581"] = 1, -- Sap
  ["EX1_613"] = 1, -- Edwin VanCleef
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 1, -- Piloted Shredder
})
add("ROGUE", 5, "aggro", "Legend Mech Rogue", {
  ["CS2_072"] = 2, -- Backstab
  ["CS2_074"] = 1, -- Deadly Poison
  ["CS2_233"] = 1, -- Blade Flurry
  ["EX1_124"] = 2, -- Eviscerate
  ["EX1_134"] = 2, -- SI:7 Agent
  ["EX1_556"] = 2, -- Harvest Golem
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_013"] = 2, -- Cogmaster
  ["GVG_016"] = 1, -- Fel Reaver
  ["GVG_022"] = 2, -- Tinker's Sharpsword Oil
  ["GVG_023"] = 2, -- Goblin Auto-Barber
  ["GVG_027"] = 1, -- Iron Sensei
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_082"] = 1, -- Clockwork Gnome
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_102"] = 1, -- Tinkertown Technician
  ["GVG_105"] = 1, -- Piloted Sky Golem
  ["GVG_110"] = 1, -- Dr. Boom
})
add("SHAMAN", 1, "aggro", "Basic Bloodlust Shaman", {
  ["CS2_037"] = 1, -- Frost Shock
  ["CS2_045"] = 2, -- Rockbiter Weapon
  ["CS2_046"] = 2, -- Bloodlust
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_196"] = 2, -- Razorfen Hunter
  ["CS2_222"] = 1, -- Stormwind Champion
  ["EX1_025"] = 2, -- Dragonling Mechanic
  ["EX1_246"] = 2, -- Hex
  ["EX1_506"] = 2, -- Murloc Tidehunter
  ["EX1_565"] = 2, -- Flametongue Totem
})
add("SHAMAN", 1, "control", "Basic Control Shaman", {
  ["CS2_037"] = 2, -- Frost Shock
  ["CS2_042"] = 2, -- Fire Elemental
  ["CS2_045"] = 1, -- Rockbiter Weapon
  ["CS2_142"] = 2, -- Kobold Geomancer
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_155"] = 2, -- Archmage
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_187"] = 2, -- Booty Bay Bodyguard
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_222"] = 1, -- Stormwind Champion
  ["CS2_226"] = 2, -- Frostwolf Warlord
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_246"] = 2, -- Hex
  ["EX1_565"] = 2, -- Flametongue Totem
  ["EX1_587"] = 1, -- Windspeaker
})
add("SHAMAN", 2, "midrange", "Budget Overload Shaman", {
  ["CS2_042"] = 2, -- Fire Elemental
  ["CS2_045"] = 2, -- Rockbiter Weapon
  ["CS2_117"] = 2, -- Earthen Ring Farseer
  ["EX1_238"] = 2, -- Lightning Bolt
  ["EX1_241"] = 1, -- Lava Burst
  ["EX1_245"] = 2, -- Earth Shock
  ["EX1_246"] = 2, -- Hex
  ["EX1_247"] = 1, -- Stormforged Axe
  ["EX1_248"] = 2, -- Feral Spirit
  ["EX1_258"] = 2, -- Unbound Elemental
  ["EX1_259"] = 2, -- Lightning Storm
  ["EX1_284"] = 1, -- Azure Drake
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_565"] = 2, -- Flametongue Totem
  ["EX1_575"] = 1, -- Mana Tide Totem
  ["FP1_002"] = 2, -- Haunted Creeper
  ["GVG_038"] = 2, -- Crackle
})
add("SHAMAN", 2, "aggro", "Budget Burn Shaman", {
  ["CS2_039"] = 1, -- Windfury
  ["CS2_045"] = 2, -- Rockbiter Weapon
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_188"] = 1, -- Abusive Sergeant
  ["EX1_008"] = 2, -- Argent Squire
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_089"] = 2, -- Arcane Golem
  ["EX1_238"] = 2, -- Lightning Bolt
  ["EX1_241"] = 2, -- Lava Burst
  ["EX1_243"] = 2, -- Dust Devil
  ["EX1_245"] = 1, -- Earth Shock
  ["EX1_247"] = 2, -- Stormforged Axe
  ["EX1_248"] = 2, -- Feral Spirit
  ["EX1_565"] = 2, -- Flametongue Totem
  ["EX1_567"] = 1, -- Doomhammer
  ["GVG_038"] = 2, -- Crackle
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("SHAMAN", 3, "control", "Control Shaman", {
  ["CS2_037"] = 1, -- Frost Shock
  ["CS2_042"] = 2, -- Fire Elemental
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_110"] = 1, -- Cairne Bloodhoof
  ["EX1_238"] = 2, -- Lightning Bolt
  ["EX1_245"] = 2, -- Earth Shock
  ["EX1_246"] = 2, -- Hex
  ["EX1_248"] = 2, -- Feral Spirit
  ["EX1_250"] = 1, -- Earth Elemental
  ["EX1_259"] = 2, -- Lightning Storm
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_298"] = 1, -- Ragnaros the Firelord
  ["EX1_565"] = 2, -- Flametongue Totem
  ["EX1_575"] = 2, -- Mana Tide Totem
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_012"] = 2, -- Sludge Belcher
  ["GVG_069"] = 1, -- Antique Healbot
  ["NEW1_010"] = 1, -- Al'Akir the Windlord
})
add("SHAMAN", 4, "midrange", "Vitality Totem Shaman", {
  ["CS2_042"] = 2, -- Fire Elemental
  ["CS2_045"] = 1, -- Rockbiter Weapon
  ["EX1_012"] = 1, -- Bloodmage Thalnos
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_238"] = 2, -- Lightning Bolt
  ["EX1_241"] = 1, -- Lava Burst
  ["EX1_245"] = 1, -- Earth Shock
  ["EX1_246"] = 2, -- Hex
  ["EX1_248"] = 2, -- Feral Spirit
  ["EX1_259"] = 1, -- Lightning Storm
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_565"] = 2, -- Flametongue Totem
  ["EX1_575"] = 2, -- Mana Tide Totem
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_038"] = 2, -- Crackle
  ["GVG_039"] = 1, -- Vitality Totem
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
})
add("SHAMAN", 5, "aggro", "Legend Mech Shaman", {
  ["CS2_045"] = 2, -- Rockbiter Weapon
  ["CS2_046"] = 1, -- Bloodlust
  ["EX1_238"] = 2, -- Lightning Bolt
  ["EX1_248"] = 2, -- Feral Spirit
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_565"] = 2, -- Flametongue Totem
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_013"] = 2, -- Cogmaster
  ["GVG_036"] = 2, -- Powermace
  ["GVG_037"] = 2, -- Whirling Zap-o-matic
  ["GVG_038"] = 2, -- Crackle
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_082"] = 1, -- Clockwork Gnome
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_105"] = 1, -- Piloted Sky Golem
  ["GVG_110"] = 1, -- Dr. Boom
})
add("SHAMAN", 5, "midrange", "Legend Totem Shaman", {
  ["CS2_042"] = 2, -- Fire Elemental
  ["CS2_045"] = 1, -- Rockbiter Weapon
  ["EX1_012"] = 1, -- Bloodmage Thalnos
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_238"] = 2, -- Lightning Bolt
  ["EX1_245"] = 1, -- Earth Shock
  ["EX1_246"] = 2, -- Hex
  ["EX1_248"] = 2, -- Feral Spirit
  ["EX1_250"] = 1, -- Earth Elemental
  ["EX1_259"] = 2, -- Lightning Storm
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_565"] = 2, -- Flametongue Totem
  ["EX1_575"] = 2, -- Mana Tide Totem
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_038"] = 1, -- Crackle
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_010"] = 1, -- Al'Akir the Windlord
})
add("WARLOCK", 1, "aggro", "Basic Zoo Warlock", {
  ["CS2_057"] = 2, -- Shadow Bolt
  ["CS2_065"] = 2, -- Voidwalker
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_196"] = 2, -- Razorfen Hunter
  ["CS2_213"] = 2, -- Reckless Rocketeer
  ["CS2_222"] = 2, -- Stormwind Champion
  ["EX1_019"] = 2, -- Shattered Sun Cleric
  ["EX1_302"] = 2, -- Mortal Coil
  ["EX1_308"] = 2, -- Soulfire
})
add("WARLOCK", 1, "control", "Basic Control Warlock", {
  ["CS2_057"] = 2, -- Shadow Bolt
  ["CS2_061"] = 2, -- Drain Life
  ["CS2_062"] = 2, -- Hellfire
  ["CS2_063"] = 1, -- Corruption
  ["CS2_064"] = 2, -- Dread Infernal
  ["CS2_065"] = 2, -- Voidwalker
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_155"] = 2, -- Archmage
  ["CS2_162"] = 2, -- Lord of the Arena
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["DS1_055"] = 2, -- Darkscale Healer
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_302"] = 2, -- Mortal Coil
})
add("WARLOCK", 2, "aggro", "Budget Demon Zoo", {
  ["CS2_065"] = 2, -- Voidwalker
  ["CS2_188"] = 2, -- Abusive Sergeant
  ["EX1_020"] = 2, -- Scarlet Crusader
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_162"] = 2, -- Dire Wolf Alpha
  ["EX1_302"] = 1, -- Mortal Coil
  ["EX1_308"] = 2, -- Soulfire
  ["EX1_310"] = 1, -- Doomguard
  ["EX1_316"] = 2, -- Power Overwhelming
  ["EX1_319"] = 2, -- Flame Imp
  ["EX1_556"] = 2, -- Harvest Golem
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_007"] = 2, -- Nerubian Egg
  ["GVG_045"] = 2, -- Imp-losion
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("WARLOCK", 2, "control", "Budget Giants Warlock", {
  ["CS2_057"] = 2, -- Shadow Bolt
  ["CS2_062"] = 2, -- Hellfire
  ["CS2_117"] = 2, -- Earthen Ring Farseer
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_043"] = 2, -- Twilight Drake
  ["EX1_045"] = 2, -- Ancient Watcher
  ["EX1_058"] = 2, -- Sunfury Protector
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_105"] = 2, -- Mountain Giant
  ["EX1_302"] = 2, -- Mortal Coil
  ["EX1_303"] = 2, -- Shadowflame
  ["EX1_308"] = 1, -- Soulfire
  ["EX1_309"] = 1, -- Siphon Soul
  ["EX1_620"] = 2, -- Molten Giant
  ["FP1_012"] = 2, -- Sludge Belcher
  ["GVG_069"] = 1, -- Antique Healbot
})
add("WARLOCK", 3, "aggro", "GvG Zoo", {
  ["CS2_065"] = 2, -- Voidwalker
  ["CS2_188"] = 1, -- Abusive Sergeant
  ["EX1_008"] = 2, -- Argent Squire
  ["EX1_046"] = 2, -- Dark Iron Dwarf
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_162"] = 1, -- Dire Wolf Alpha
  ["EX1_308"] = 2, -- Soulfire
  ["EX1_310"] = 2, -- Doomguard
  ["EX1_316"] = 2, -- Power Overwhelming
  ["EX1_319"] = 2, -- Flame Imp
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_007"] = 2, -- Nerubian Egg
  ["GVG_015"] = 2, -- Darkbomb
  ["GVG_045"] = 2, -- Imp-losion
  ["GVG_096"] = 2, -- Piloted Shredder
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("WARLOCK", 4, "control", "Mal'Ganis Handlock", {
  ["CS2_062"] = 2, -- Hellfire
  ["CS2_117"] = 2, -- Earthen Ring Farseer
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_043"] = 2, -- Twilight Drake
  ["EX1_045"] = 2, -- Ancient Watcher
  ["EX1_058"] = 2, -- Sunfury Protector
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_105"] = 2, -- Mountain Giant
  ["EX1_302"] = 2, -- Mortal Coil
  ["EX1_303"] = 1, -- Shadowflame
  ["EX1_309"] = 1, -- Siphon Soul
  ["EX1_323"] = 1, -- Lord Jaraxxus
  ["EX1_620"] = 2, -- Molten Giant
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_015"] = 2, -- Darkbomb
  ["GVG_021"] = 1, -- Mal'Ganis
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_110"] = 1, -- Dr. Boom
})
add("WARLOCK", 5, "control", "Legend Handlock", {
  ["CS2_062"] = 2, -- Hellfire
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_043"] = 2, -- Twilight Drake
  ["EX1_045"] = 2, -- Ancient Watcher
  ["EX1_058"] = 2, -- Sunfury Protector
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_105"] = 2, -- Mountain Giant
  ["EX1_302"] = 2, -- Mortal Coil
  ["EX1_303"] = 1, -- Shadowflame
  ["EX1_309"] = 1, -- Siphon Soul
  ["EX1_323"] = 1, -- Lord Jaraxxus
  ["EX1_620"] = 2, -- Molten Giant
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_015"] = 2, -- Darkbomb
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_110"] = 1, -- Dr. Boom
})
add("WARLOCK", 5, "aggro", "Legend Demon Zoo", {
  ["CS2_065"] = 2, -- Voidwalker
  ["CS2_188"] = 1, -- Abusive Sergeant
  ["EX1_029"] = 1, -- Leper Gnome
  ["EX1_046"] = 2, -- Dark Iron Dwarf
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_308"] = 2, -- Soulfire
  ["EX1_310"] = 2, -- Doomguard
  ["EX1_316"] = 1, -- Power Overwhelming
  ["EX1_319"] = 2, -- Flame Imp
  ["EX1_586"] = 1, -- Sea Giant
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_007"] = 1, -- Nerubian Egg
  ["FP1_022"] = 2, -- Voidcaller
  ["GVG_015"] = 1, -- Darkbomb
  ["GVG_021"] = 1, -- Mal'Ganis
  ["GVG_045"] = 2, -- Imp-losion
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("DRUID", 1, "aggro", "Basic Aggro Druid", {
  ["CS2_005"] = 2, -- Claw
  ["CS2_008"] = 2, -- Moonfire
  ["CS2_009"] = 2, -- Mark of the Wild
  ["CS2_011"] = 2, -- Savage Roar
  ["CS2_122"] = 2, -- Raid Leader
  ["CS2_124"] = 2, -- Wolfrider
  ["CS2_125"] = 2, -- Ironfur Grizzly
  ["CS2_131"] = 2, -- Stormwind Knight
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_168"] = 2, -- Murloc Raider
  ["CS2_172"] = 2, -- Bloodfen Raptor
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_189"] = 2, -- Elven Archer
  ["CS2_222"] = 2, -- Stormwind Champion
  ["EX1_169"] = 2, -- Innervate
})
add("DRUID", 1, "control", "Basic Ramp Druid", {
  ["CS2_007"] = 1, -- Healing Touch
  ["CS2_008"] = 1, -- Moonfire
  ["CS2_012"] = 2, -- Swipe
  ["CS2_013"] = 2, -- Wild Growth
  ["CS2_147"] = 2, -- Gnomish Inventor
  ["CS2_155"] = 2, -- Archmage
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_182"] = 2, -- Chillwind Yeti
  ["CS2_186"] = 2, -- War Golem
  ["CS2_200"] = 2, -- Boulderfist Ogre
  ["CS2_201"] = 2, -- Core Hound
  ["CS2_222"] = 1, -- Stormwind Champion
  ["CS2_232"] = 2, -- Ironbark Protector
  ["EX1_015"] = 2, -- Novice Engineer
  ["EX1_066"] = 1, -- Acidic Swamp Ooze
  ["EX1_169"] = 2, -- Innervate
  ["EX1_173"] = 2, -- Starfire
})
add("DRUID", 2, "control", "Budget Ramp Druid", {
  ["CS2_012"] = 2, -- Swipe
  ["CS2_013"] = 2, -- Wild Growth
  ["CS2_117"] = 2, -- Earthen Ring Farseer
  ["CS2_179"] = 2, -- Sen'jin Shieldmasta
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["CS2_232"] = 1, -- Ironbark Protector
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_154"] = 2, -- Wrath
  ["EX1_165"] = 2, -- Druid of the Claw
  ["EX1_166"] = 2, -- Keeper of the Grove
  ["EX1_169"] = 2, -- Innervate
  ["EX1_173"] = 1, -- Starfire
  ["EX1_178"] = 1, -- Ancient of War
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_556"] = 2, -- Harvest Golem
  ["FP1_001"] = 1, -- Zombie Chow
  ["FP1_012"] = 2, -- Sludge Belcher
  ["NEW1_008"] = 2, -- Ancient of Lore
})
add("DRUID", 2, "aggro", "Budget Force Druid", {
  ["CS2_009"] = 2, -- Mark of the Wild
  ["CS2_011"] = 2, -- Savage Roar
  ["CS2_012"] = 1, -- Swipe
  ["EX1_019"] = 2, -- Shattered Sun Cleric
  ["EX1_029"] = 2, -- Leper Gnome
  ["EX1_093"] = 2, -- Defender of Argus
  ["EX1_154"] = 2, -- Wrath
  ["EX1_160"] = 2, -- Power of the Wild
  ["EX1_162"] = 2, -- Dire Wolf Alpha
  ["EX1_165"] = 2, -- Druid of the Claw
  ["EX1_166"] = 2, -- Keeper of the Grove
  ["EX1_169"] = 2, -- Innervate
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_571"] = 1, -- Force of Nature
  ["FP1_002"] = 2, -- Haunted Creeper
  ["NEW1_019"] = 2, -- Knife Juggler
})
add("DRUID", 3, "midrange", "Naxx Druid", {
  ["CS2_011"] = 1, -- Savage Roar
  ["CS2_012"] = 2, -- Swipe
  ["CS2_013"] = 2, -- Wild Growth
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_110"] = 1, -- Cairne Bloodhoof
  ["EX1_154"] = 2, -- Wrath
  ["EX1_165"] = 2, -- Druid of the Claw
  ["EX1_166"] = 2, -- Keeper of the Grove
  ["EX1_169"] = 2, -- Innervate
  ["EX1_178"] = 1, -- Ancient of War
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_571"] = 1, -- Force of Nature
  ["FP1_001"] = 1, -- Zombie Chow
  ["FP1_002"] = 2, -- Haunted Creeper
  ["FP1_012"] = 2, -- Sludge Belcher
  ["FP1_030"] = 1, -- Loatheb
  ["NEW1_008"] = 2, -- Ancient of Lore
})
add("DRUID", 4, "control", "GvG Ramp Druid", {
  ["CS2_011"] = 1, -- Savage Roar
  ["CS2_012"] = 2, -- Swipe
  ["CS2_013"] = 2, -- Wild Growth
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_154"] = 2, -- Wrath
  ["EX1_165"] = 2, -- Druid of the Claw
  ["EX1_166"] = 2, -- Keeper of the Grove
  ["EX1_169"] = 2, -- Innervate
  ["EX1_173"] = 1, -- Starfire
  ["EX1_178"] = 1, -- Ancient of War
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_298"] = 1, -- Ragnaros the Firelord
  ["EX1_571"] = 1, -- Force of Nature
  ["FP1_001"] = 2, -- Zombie Chow
  ["GVG_069"] = 1, -- Antique Healbot
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_008"] = 2, -- Ancient of Lore
})
add("DRUID", 5, "control", "Legend Ramp Druid", {
  ["CS2_011"] = 1, -- Savage Roar
  ["CS2_012"] = 2, -- Swipe
  ["CS2_013"] = 2, -- Wild Growth
  ["CS2_203"] = 1, -- Ironbeak Owl
  ["EX1_005"] = 1, -- Big Game Hunter
  ["EX1_016"] = 1, -- Sylvanas Windrunner
  ["EX1_154"] = 2, -- Wrath
  ["EX1_165"] = 2, -- Druid of the Claw
  ["EX1_166"] = 2, -- Keeper of the Grove
  ["EX1_169"] = 2, -- Innervate
  ["EX1_178"] = 1, -- Ancient of War
  ["EX1_284"] = 2, -- Azure Drake
  ["EX1_558"] = 1, -- Harrison Jones
  ["EX1_571"] = 1, -- Force of Nature
  ["EX1_572"] = 1, -- Ysera
  ["FP1_001"] = 2, -- Zombie Chow
  ["FP1_030"] = 1, -- Loatheb
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_110"] = 1, -- Dr. Boom
  ["NEW1_008"] = 2, -- Ancient of Lore
})
add("DRUID", 5, "aggro", "Legend Mech Druid", {
  ["CS2_011"] = 2, -- Savage Roar
  ["CS2_012"] = 1, -- Swipe
  ["EX1_154"] = 2, -- Wrath
  ["EX1_165"] = 2, -- Druid of the Claw
  ["EX1_166"] = 2, -- Keeper of the Grove
  ["EX1_169"] = 2, -- Innervate
  ["EX1_556"] = 2, -- Harvest Golem
  ["EX1_571"] = 2, -- Force of Nature
  ["GVG_006"] = 2, -- Mechwarper
  ["GVG_016"] = 1, -- Fel Reaver
  ["GVG_034"] = 2, -- Mech-Bear-Cat
  ["GVG_044"] = 2, -- Spider Tank
  ["GVG_080"] = 2, -- Druid of the Fang
  ["GVG_085"] = 2, -- Annoy-o-Tron
  ["GVG_096"] = 2, -- Piloted Shredder
  ["GVG_105"] = 1, -- Piloted Sky Golem
  ["GVG_110"] = 1, -- Dr. Boom
})
