-- GENERATED FILE -- DO NOT EDIT BY HAND.
-- Regenerate with: python tools/import_cards.py
-- Source: HearthstoneJSON build 7234 (enUS)
-- Patch pinned: 7234 (Basic + Classic + Naxxramas + Goblins vs Gnomes)
-- Source sha256: 89bdbe45a8f4e4732c0937778a3d2f0de17f9fb6d01c1a9321f065ef844e18db

local ADDON, ns = ...
ns.PATCH_BUILD = 7234
ns.PATCH_LABEL = "7234 (Basic + Classic + Naxxramas + Goblins vs Gnomes)"
ns.DATA_SHA256 = "89bdbe45a8f4e4732c0937778a3d2f0de17f9fb6d01c1a9321f065ef844e18db"

-- Printed (immutable) card data. Effect logic lives in Data/Effects/.
local P = {}
ns.PrintedCards = P

-- === COLLECTIBLE POOL (535) ===
P["CS2_005"]={id="CS2_005",name="Claw",type="SPELL",set="CORE",rarity="FREE",class="DRUID",cost=1,text="Give your hero +2 Attack this turn and 2 Armor.",collectible=true}
P["CS2_007"]={id="CS2_007",name="Healing Touch",type="SPELL",set="CORE",rarity="FREE",class="DRUID",cost=3,reqs={REQ_TARGET_TO_PLAY=0},text="Restore 8 Health.",collectible=true}
P["CS2_008"]={id="CS2_008",name="Moonfire",type="SPELL",set="CORE",rarity="COMMON",class="DRUID",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 1 damage.",collectible=true}
P["CS2_009"]={id="CS2_009",name="Mark of the Wild",type="SPELL",set="CORE",rarity="FREE",class="DRUID",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion <b>Taunt</b> and +2/+2. (+2 Attack/+2 Health)",collectible=true}
P["CS2_011"]={id="CS2_011",name="Savage Roar",type="SPELL",set="CORE",rarity="COMMON",class="DRUID",cost=3,text="Give your characters +2 Attack this turn.",collectible=true}
P["CS2_012"]={id="CS2_012",name="Swipe",type="SPELL",set="CORE",rarity="COMMON",class="DRUID",cost=4,reqs={REQ_ENEMY_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 4 damage to an enemy and 1 damage to all other enemies.",collectible=true}
P["CS2_013"]={id="CS2_013",name="Wild Growth",type="SPELL",set="CORE",rarity="FREE",class="DRUID",cost=2,text="Gain an empty Mana Crystal.",collectible=true}
P["CS2_232"]={id="CS2_232",name="Ironbark Protector",type="MINION",set="CORE",rarity="COMMON",class="DRUID",cost=8,atk=8,hp=8,keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["EX1_169"]={id="EX1_169",name="Innervate",type="SPELL",set="CORE",rarity="FREE",class="DRUID",cost=0,text="Gain 2 Mana Crystals this turn only.",collectible=true}
P["EX1_173"]={id="EX1_173",name="Starfire",type="SPELL",set="CORE",rarity="COMMON",class="DRUID",cost=6,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 5 damage. Draw a card.",collectible=true}
P["CS2_084"]={id="CS2_084",name="Hunter's Mark",type="SPELL",set="CORE",rarity="COMMON",class="HUNTER",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Change a minion's Health to 1.",collectible=true}
P["CS2_237"]={id="CS2_237",name="Starving Buzzard",type="MINION",set="CORE",rarity="COMMON",class="HUNTER",cost=5,atk=3,hp=2,race="BEAST",text="Whenever you summon a Beast, draw a card.",collectible=true}
P["DS1_070"]={id="DS1_070",name="Houndmaster",type="MINION",set="CORE",rarity="FREE",class="HUNTER",cost=4,atk=4,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_WITH_RACE=20},text="<b>Battlecry:</b> Give a friendly Beast +2/+2 and <b>Taunt</b>.",collectible=true}
P["DS1_175"]={id="DS1_175",name="Timber Wolf",type="MINION",set="CORE",rarity="FREE",class="HUNTER",cost=1,atk=1,hp=1,race="BEAST",scriptTags={"AURA"},text="Your other Beasts have +1 Attack.",collectible=true}
P["DS1_178"]={id="DS1_178",name="Tundra Rhino",type="MINION",set="CORE",rarity="COMMON",class="HUNTER",cost=5,atk=2,hp=5,race="BEAST",text="Your Beasts have <b>Charge</b>.",collectible=true}
P["DS1_183"]={id="DS1_183",name="Multi-Shot",type="SPELL",set="CORE",rarity="FREE",class="HUNTER",cost=4,reqs={REQ_MINIMUM_ENEMY_MINIONS=2},text="Deal 3 damage to two random enemy minions.",collectible=true}
P["DS1_184"]={id="DS1_184",name="Tracking",type="SPELL",set="CORE",rarity="FREE",class="HUNTER",cost=1,text="Look at the top three cards of your deck. Draw one and discard the others.",collectible=true}
P["DS1_185"]={id="DS1_185",name="Arcane Shot",type="SPELL",set="CORE",rarity="FREE",class="HUNTER",cost=1,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 2 damage.",collectible=true}
P["EX1_539"]={id="EX1_539",name="Kill Command",type="SPELL",set="CORE",rarity="COMMON",class="HUNTER",cost=3,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 3 damage. If you have a Beast, deal 5 damage instead.",collectible=true}
P["NEW1_031"]={id="NEW1_031",name="Animal Companion",type="SPELL",set="CORE",rarity="COMMON",class="HUNTER",cost=3,entourage={"NEW1_032","NEW1_033","NEW1_034"},reqs={REQ_NUM_MINION_SLOTS=1},text="Summon a random Beast Companion.",collectible=true}
P["CS2_022"]={id="CS2_022",name="Polymorph",type="SPELL",set="CORE",rarity="FREE",class="MAGE",cost=4,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Transform a minion into a 1/1 Sheep.",collectible=true}
P["CS2_023"]={id="CS2_023",name="Arcane Intellect",type="SPELL",set="CORE",rarity="FREE",class="MAGE",cost=3,text="Draw 2 cards.",collectible=true}
P["CS2_024"]={id="CS2_024",name="Frostbolt",type="SPELL",set="CORE",rarity="COMMON",class="MAGE",cost=2,scriptTags={"FREEZE"},reqs={REQ_TARGET_TO_PLAY=0},text="Deal 3 damage to a character and <b>Freeze</b> it.",collectible=true}
P["CS2_025"]={id="CS2_025",name="Arcane Explosion",type="SPELL",set="CORE",rarity="FREE",class="MAGE",cost=2,text="Deal 1 damage to all enemy minions.",collectible=true}
P["CS2_026"]={id="CS2_026",name="Frost Nova",type="SPELL",set="CORE",rarity="COMMON",class="MAGE",cost=3,scriptTags={"FREEZE"},text="<b>Freeze</b> all enemy minions.",collectible=true}
P["CS2_027"]={id="CS2_027",name="Mirror Image",type="SPELL",set="CORE",rarity="COMMON",class="MAGE",cost=1,reqs={REQ_NUM_MINION_SLOTS=1},text="Summon two 0/2 minions with <b>Taunt</b>.",collectible=true}
P["CS2_029"]={id="CS2_029",name="Fireball",type="SPELL",set="CORE",rarity="FREE",class="MAGE",cost=4,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 6 damage.",collectible=true}
P["CS2_032"]={id="CS2_032",name="Flamestrike",type="SPELL",set="CORE",rarity="COMMON",class="MAGE",cost=7,text="Deal 4 damage to all enemy minions.",collectible=true}
P["CS2_033"]={id="CS2_033",name="Water Elemental",type="MINION",set="CORE",rarity="COMMON",class="MAGE",cost=4,atk=3,hp=6,scriptTags={"FREEZE"},text="<b>Freeze</b> any character damaged by this minion.",collectible=true}
P["EX1_277"]={id="EX1_277",name="Arcane Missiles",type="SPELL",set="CORE",rarity="FREE",class="MAGE",cost=1,keywords={"ImmuneToSpellpower"},text="Deal 3 damage randomly split among enemy characters.",collectible=true}
P["CS1_042"]={id="CS1_042",name="Goldshire Footman",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=2,keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_118"]={id="CS2_118",name="Magma Rager",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=3,atk=5,hp=1,text=nil,collectible=true}
P["CS2_119"]={id="CS2_119",name="Oasis Snapjaw",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=4,atk=2,hp=7,race="BEAST",text=nil,collectible=true}
P["CS2_120"]={id="CS2_120",name="River Crocolisk",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=2,atk=2,hp=3,race="BEAST",text=nil,collectible=true}
P["CS2_121"]={id="CS2_121",name="Frostwolf Grunt",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=2,keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_122"]={id="CS2_122",name="Raid Leader",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=3,atk=2,hp=2,scriptTags={"AURA"},text="Your other minions have +1 Attack.",collectible=true}
P["CS2_124"]={id="CS2_124",name="Wolfrider",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=3,atk=3,hp=1,keywords={"CHARGE"},text="<b>Charge</b>",collectible=true}
P["CS2_125"]={id="CS2_125",name="Ironfur Grizzly",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=3,race="BEAST",keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_127"]={id="CS2_127",name="Silverback Patriarch",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=3,atk=1,hp=4,race="BEAST",keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_131"]={id="CS2_131",name="Stormwind Knight",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=4,atk=2,hp=5,keywords={"CHARGE"},text="<b>Charge</b>",collectible=true}
P["CS2_141"]={id="CS2_141",name="Ironforge Rifleman",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=3,atk=2,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Deal 1 damage.",collectible=true}
P["CS2_142"]={id="CS2_142",name="Kobold Geomancer",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=2,spellDamage=1,text="<b>Spell Damage +1</b>",collectible=true}
P["CS2_147"]={id="CS2_147",name="Gnomish Inventor",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=4,atk=2,hp=4,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Draw a card.",collectible=true}
P["CS2_150"]={id="CS2_150",name="Stormpike Commando",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=5,atk=4,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Deal 2 damage.",collectible=true}
P["CS2_155"]={id="CS2_155",name="Archmage",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=6,atk=4,hp=7,spellDamage=1,text="<b>Spell Damage +1</b>",collectible=true}
P["CS2_162"]={id="CS2_162",name="Lord of the Arena",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=6,atk=6,hp=5,keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_168"]={id="CS2_168",name="Murloc Raider",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=1,atk=2,hp=1,race="MURLOC",text=nil,collectible=true}
P["CS2_171"]={id="CS2_171",name="Stonetusk Boar",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,race="BEAST",keywords={"CHARGE"},text="<b>Charge</b>",collectible=true}
P["CS2_172"]={id="CS2_172",name="Bloodfen Raptor",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=2,atk=3,hp=2,race="BEAST",text=nil,collectible=true}
P["CS2_173"]={id="CS2_173",name="Bluegill Warrior",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=1,race="MURLOC",keywords={"CHARGE"},text="<b>Charge</b>",collectible=true}
P["CS2_179"]={id="CS2_179",name="Sen'jin Shieldmasta",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=4,atk=3,hp=5,keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_182"]={id="CS2_182",name="Chillwind Yeti",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=5,text=nil,collectible=true}
P["CS2_186"]={id="CS2_186",name="War Golem",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=7,atk=7,hp=7,text=nil,collectible=true}
P["CS2_187"]={id="CS2_187",name="Booty Bay Bodyguard",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=5,atk=5,hp=4,keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["CS2_189"]={id="CS2_189",name="Elven Archer",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,scriptTags={"BATTLECRY"},reqs={REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Deal 1 damage.",collectible=true}
P["CS2_196"]={id="CS2_196",name="Razorfen Hunter",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=3,atk=2,hp=3,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Summon a 1/1 Boar.",collectible=true}
P["CS2_197"]={id="CS2_197",name="Ogre Magi",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=4,spellDamage=1,text="<b>Spell Damage +1</b>",collectible=true}
P["CS2_200"]={id="CS2_200",name="Boulderfist Ogre",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=6,atk=6,hp=7,text=nil,collectible=true}
P["CS2_201"]={id="CS2_201",name="Core Hound",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=7,atk=9,hp=5,race="BEAST",text=nil,collectible=true}
P["CS2_213"]={id="CS2_213",name="Reckless Rocketeer",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=6,atk=5,hp=2,keywords={"CHARGE"},text="<b>Charge</b>",collectible=true}
P["CS2_222"]={id="CS2_222",name="Stormwind Champion",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=7,atk=6,hp=6,scriptTags={"AURA"},text="Your other minions have +1/+1.",collectible=true}
P["CS2_226"]={id="CS2_226",name="Frostwolf Warlord",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=5,atk=4,hp=4,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Gain +1/+1 for each other friendly minion on the battlefield.",collectible=true}
P["DS1_055"]={id="DS1_055",name="Darkscale Healer",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=5,atk=4,hp=5,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Restore 2 Health to all friendly characters.",collectible=true}
P["EX1_011"]={id="EX1_011",name="Voodoo Doctor",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=1,atk=2,hp=1,scriptTags={"BATTLECRY"},reqs={REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Restore 2 Health.",collectible=true}
P["EX1_015"]={id="EX1_015",name="Novice Engineer",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=2,atk=1,hp=1,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Draw a card.",collectible=true}
P["EX1_019"]={id="EX1_019",name="Shattered Sun Cleric",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Give a friendly minion +1/+1.",collectible=true}
P["EX1_025"]={id="EX1_025",name="Dragonling Mechanic",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=4,atk=2,hp=4,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Summon a 2/1 Mechanical Dragonling.",collectible=true}
P["EX1_066"]={id="EX1_066",name="Acidic Swamp Ooze",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=2,atk=3,hp=2,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Destroy your opponent's weapon.",collectible=true}
P["EX1_399"]={id="EX1_399",name="Gurubashi Berserker",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=5,atk=2,hp=7,text="Whenever this minion takes damage, gain +3 Attack.",collectible=true}
P["EX1_506"]={id="EX1_506",name="Murloc Tidehunter",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=1,race="MURLOC",scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Summon a 1/1 Murloc Scout.",collectible=true}
P["EX1_508"]={id="EX1_508",name="Grimscale Oracle",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,race="MURLOC",scriptTags={"AURA"},text="ALL other Murlocs have +1 Attack.",collectible=true}
P["EX1_582"]={id="EX1_582",name="Dalaran Mage",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=3,atk=1,hp=4,spellDamage=1,text="<b>Spell Damage +1</b>",collectible=true}
P["EX1_593"]={id="EX1_593",name="Nightblade",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=5,atk=4,hp=4,scriptTags={"BATTLECRY"},text="<b>Battlecry: </b>Deal 3 damage to the enemy hero.",collectible=true}
P["CS2_087"]={id="CS2_087",name="Blessing of Might",type="SPELL",set="CORE",rarity="FREE",class="PALADIN",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +3 Attack.",collectible=true}
P["CS2_088"]={id="CS2_088",name="Guardian of Kings",type="MINION",set="CORE",rarity="COMMON",class="PALADIN",cost=7,atk=5,hp=6,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Restore 6 Health to your hero.",collectible=true}
P["CS2_089"]={id="CS2_089",name="Holy Light",type="SPELL",set="CORE",rarity="FREE",class="PALADIN",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="Restore 6 Health.",collectible=true}
P["CS2_091"]={id="CS2_091",name="Light's Justice",type="WEAPON",set="CORE",rarity="FREE",class="PALADIN",cost=1,atk=1,dur=4,text=nil,collectible=true}
P["CS2_092"]={id="CS2_092",name="Blessing of Kings",type="SPELL",set="CORE",rarity="COMMON",class="PALADIN",cost=4,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +4/+4. (+4 Attack/+4 Health)",collectible=true}
P["CS2_093"]={id="CS2_093",name="Consecration",type="SPELL",set="CORE",rarity="COMMON",class="PALADIN",cost=4,text="Deal 2 damage to all enemies.",collectible=true}
P["CS2_094"]={id="CS2_094",name="Hammer of Wrath",type="SPELL",set="CORE",rarity="FREE",class="PALADIN",cost=4,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 3 damage. Draw a card.",collectible=true}
P["CS2_097"]={id="CS2_097",name="Truesilver Champion",type="WEAPON",set="CORE",rarity="COMMON",class="PALADIN",cost=4,atk=4,dur=2,text="Whenever your hero attacks, restore 2 Health to it.",collectible=true}
P["EX1_360"]={id="EX1_360",name="Humility",type="SPELL",set="CORE",rarity="COMMON",class="PALADIN",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Change a minion's Attack to 1.",collectible=true}
P["EX1_371"]={id="EX1_371",name="Hand of Protection",type="SPELL",set="CORE",rarity="FREE",class="PALADIN",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion <b>Divine Shield</b>.",collectible=true}
P["CS1_112"]={id="CS1_112",name="Holy Nova",type="SPELL",set="CORE",rarity="COMMON",class="PRIEST",cost=5,text="Deal 2 damage to all enemies. Restore 2 Health to all friendly characters.",collectible=true}
P["CS1_113"]={id="CS1_113",name="Mind Control",type="SPELL",set="CORE",rarity="COMMON",class="PRIEST",cost=10,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_NUM_MINION_SLOTS=1,REQ_TARGET_TO_PLAY=0},text="Take control of an enemy minion.",collectible=true}
P["CS1_130"]={id="CS1_130",name="Holy Smite",type="SPELL",set="CORE",rarity="FREE",class="PRIEST",cost=1,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 2 damage.",collectible=true}
P["CS2_003"]={id="CS2_003",name="Mind Vision",type="SPELL",set="CORE",rarity="COMMON",class="PRIEST",cost=1,text="Put a copy of a random card in your opponent's hand into your hand.",collectible=true}
P["CS2_004"]={id="CS2_004",name="Power Word: Shield",type="SPELL",set="CORE",rarity="FREE",class="PRIEST",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +2 Health. Draw a card.",collectible=true}
P["CS2_234"]={id="CS2_234",name="Shadow Word: Pain",type="SPELL",set="CORE",rarity="FREE",class="PRIEST",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_MAX_ATTACK=3,REQ_TARGET_TO_PLAY=0},text="Destroy a minion with 3 or less Attack.",collectible=true}
P["CS2_235"]={id="CS2_235",name="Northshire Cleric",type="MINION",set="CORE",rarity="FREE",class="PRIEST",cost=1,atk=1,hp=3,text="Whenever a minion is healed, draw a card.",collectible=true}
P["CS2_236"]={id="CS2_236",name="Divine Spirit",type="SPELL",set="CORE",rarity="COMMON",class="PRIEST",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Double a minion's Health.",collectible=true}
P["DS1_233"]={id="DS1_233",name="Mind Blast",type="SPELL",set="CORE",rarity="FREE",class="PRIEST",cost=2,text="Deal 5 damage to the enemy hero.",collectible=true}
P["EX1_622"]={id="EX1_622",name="Shadow Word: Death",type="SPELL",set="CORE",rarity="COMMON",class="PRIEST",cost=3,reqs={REQ_MINION_TARGET=0,REQ_TARGET_MIN_ATTACK=5,REQ_TARGET_TO_PLAY=0},text="Destroy a minion with an Attack of 5 or more.",collectible=true}
P["CS2_072"]={id="CS2_072",name="Backstab",type="SPELL",set="CORE",rarity="FREE",class="ROGUE",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0,REQ_UNDAMAGED_TARGET=0},text="Deal 2 damage to an undamaged minion.",collectible=true}
P["CS2_074"]={id="CS2_074",name="Deadly Poison",type="SPELL",set="CORE",rarity="FREE",class="ROGUE",cost=1,reqs={REQ_WEAPON_EQUIPPED=0},text="Give your weapon +2 Attack.",collectible=true}
P["CS2_075"]={id="CS2_075",name="Sinister Strike",type="SPELL",set="CORE",rarity="FREE",class="ROGUE",cost=1,text="Deal 3 damage to the enemy hero.",collectible=true}
P["CS2_076"]={id="CS2_076",name="Assassinate",type="SPELL",set="CORE",rarity="FREE",class="ROGUE",cost=5,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy an enemy minion.",collectible=true}
P["CS2_077"]={id="CS2_077",name="Sprint",type="SPELL",set="CORE",rarity="COMMON",class="ROGUE",cost=7,text="Draw 4 cards.",collectible=true}
P["CS2_080"]={id="CS2_080",name="Assassin's Blade",type="WEAPON",set="CORE",rarity="COMMON",class="ROGUE",cost=5,atk=3,dur=4,text=nil,collectible=true}
P["EX1_129"]={id="EX1_129",name="Fan of Knives",type="SPELL",set="CORE",rarity="COMMON",class="ROGUE",cost=3,text="Deal 1 damage to all enemy minions. Draw a card.",collectible=true}
P["EX1_278"]={id="EX1_278",name="Shiv",type="SPELL",set="CORE",rarity="COMMON",class="ROGUE",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 1 damage. Draw a card.",collectible=true}
P["EX1_581"]={id="EX1_581",name="Sap",type="SPELL",set="CORE",rarity="FREE",class="ROGUE",cost=2,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Return an enemy minion to your opponent's hand.",collectible=true}
P["NEW1_004"]={id="NEW1_004",name="Vanish",type="SPELL",set="CORE",rarity="COMMON",class="ROGUE",cost=6,text="Return all minions to their owner's hand.",collectible=true}
P["CS2_037"]={id="CS2_037",name="Frost Shock",type="SPELL",set="CORE",rarity="FREE",class="SHAMAN",cost=1,scriptTags={"FREEZE"},reqs={REQ_ENEMY_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 1 damage to an enemy character and <b>Freeze</b> it.",collectible=true}
P["CS2_039"]={id="CS2_039",name="Windfury",type="SPELL",set="CORE",rarity="FREE",class="SHAMAN",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion <b>Windfury</b>.",collectible=true}
P["CS2_041"]={id="CS2_041",name="Ancestral Healing",type="SPELL",set="CORE",rarity="FREE",class="SHAMAN",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Restore a minion to full Health and give it <b>Taunt</b>.",collectible=true}
P["CS2_042"]={id="CS2_042",name="Fire Elemental",type="MINION",set="CORE",rarity="COMMON",class="SHAMAN",cost=6,atk=6,hp=5,scriptTags={"BATTLECRY"},reqs={REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Deal 3 damage.",collectible=true}
P["CS2_045"]={id="CS2_045",name="Rockbiter Weapon",type="SPELL",set="CORE",rarity="FREE",class="SHAMAN",cost=1,reqs={REQ_FRIENDLY_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a friendly character +3 Attack this turn.",collectible=true}
P["CS2_046"]={id="CS2_046",name="Bloodlust",type="SPELL",set="CORE",rarity="COMMON",class="SHAMAN",cost=5,text="Give your minions +3 Attack this turn.",collectible=true}
P["EX1_244"]={id="EX1_244",name="Totemic Might",type="SPELL",set="CORE",rarity="COMMON",class="SHAMAN",cost=0,text="Give your Totems +2 Health.",collectible=true}
P["EX1_246"]={id="EX1_246",name="Hex",type="SPELL",set="CORE",rarity="FREE",class="SHAMAN",cost=3,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Transform a minion into a 0/1 Frog with <b>Taunt</b>.",collectible=true}
P["EX1_565"]={id="EX1_565",name="Flametongue Totem",type="MINION",set="CORE",rarity="COMMON",class="SHAMAN",cost=2,atk=0,hp=3,race="TOTEM",scriptTags={"ADJACENT_BUFF","AURA"},text="Adjacent minions have +2 Attack.",collectible=true}
P["EX1_587"]={id="EX1_587",name="Windspeaker",type="MINION",set="CORE",rarity="COMMON",class="SHAMAN",cost=4,atk=3,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},text="<b>Battlecry:</b> Give a friendly minion <b>Windfury</b>.",collectible=true}
P["CS2_057"]={id="CS2_057",name="Shadow Bolt",type="SPELL",set="CORE",rarity="FREE",class="WARLOCK",cost=3,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 4 damage to a minion.",collectible=true}
P["CS2_061"]={id="CS2_061",name="Drain Life",type="SPELL",set="CORE",rarity="FREE",class="WARLOCK",cost=3,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 2 damage. Restore 2 Health to your hero.",collectible=true}
P["CS2_062"]={id="CS2_062",name="Hellfire",type="SPELL",set="CORE",rarity="FREE",class="WARLOCK",cost=4,text="Deal 3 damage to ALL characters.",collectible=true}
P["CS2_063"]={id="CS2_063",name="Corruption",type="SPELL",set="CORE",rarity="COMMON",class="WARLOCK",cost=1,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Choose an enemy minion. At the start of your turn, destroy it.",collectible=true}
P["CS2_064"]={id="CS2_064",name="Dread Infernal",type="MINION",set="CORE",rarity="COMMON",class="WARLOCK",cost=6,atk=6,hp=6,race="DEMON",scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Deal 1 damage to ALL other characters.",collectible=true}
P["CS2_065"]={id="CS2_065",name="Voidwalker",type="MINION",set="CORE",rarity="FREE",class="WARLOCK",cost=1,atk=1,hp=3,race="DEMON",keywords={"TAUNT"},text="<b>Taunt</b>",collectible=true}
P["EX1_302"]={id="EX1_302",name="Mortal Coil",type="SPELL",set="CORE",rarity="COMMON",class="WARLOCK",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 1 damage to a minion. If that kills it, draw a card.",collectible=true}
P["EX1_306"]={id="EX1_306",name="Succubus",type="MINION",set="CORE",rarity="FREE",class="WARLOCK",cost=2,atk=4,hp=3,race="DEMON",scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Discard a random card.",collectible=true}
P["EX1_308"]={id="EX1_308",name="Soulfire",type="SPELL",set="CORE",rarity="COMMON",class="WARLOCK",cost=1,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 4 damage. Discard a random card.",collectible=true}
P["NEW1_003"]={id="NEW1_003",name="Sacrificial Pact",type="SPELL",set="CORE",rarity="COMMON",class="WARLOCK",cost=0,reqs={REQ_TARGET_TO_PLAY=0,REQ_TARGET_WITH_RACE=15},text="Destroy a Demon. Restore 5 Health to your hero.",collectible=true}
P["CS2_103"]={id="CS2_103",name="Charge",type="SPELL",set="CORE",rarity="FREE",class="WARRIOR",cost=3,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a friendly minion +2 Attack and <b>Charge</b>.",collectible=true}
P["CS2_105"]={id="CS2_105",name="Heroic Strike",type="SPELL",set="CORE",rarity="FREE",class="WARRIOR",cost=2,text="Give your hero +4 Attack this turn.",collectible=true}
P["CS2_106"]={id="CS2_106",name="Fiery War Axe",type="WEAPON",set="CORE",rarity="FREE",class="WARRIOR",cost=2,atk=3,dur=2,text=nil,collectible=true}
P["CS2_108"]={id="CS2_108",name="Execute",type="SPELL",set="CORE",rarity="FREE",class="WARRIOR",cost=1,reqs={REQ_DAMAGED_TARGET=0,REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy a damaged enemy minion.",collectible=true}
P["CS2_112"]={id="CS2_112",name="Arcanite Reaper",type="WEAPON",set="CORE",rarity="COMMON",class="WARRIOR",cost=5,atk=5,dur=2,text=nil,collectible=true}
P["CS2_114"]={id="CS2_114",name="Cleave",type="SPELL",set="CORE",rarity="COMMON",class="WARRIOR",cost=2,reqs={REQ_MINIMUM_ENEMY_MINIONS=2},text="Deal 2 damage to two random enemy minions.",collectible=true}
P["EX1_084"]={id="EX1_084",name="Warsong Commander",type="MINION",set="CORE",rarity="FREE",class="WARRIOR",cost=3,atk=2,hp=3,text="Whenever you summon a minion with 3 or less Attack, give it <b>Charge</b>.",collectible=true}
P["EX1_400"]={id="EX1_400",name="Whirlwind",type="SPELL",set="CORE",rarity="COMMON",class="WARRIOR",cost=1,text="Deal 1 damage to ALL minions.",collectible=true}
P["EX1_606"]={id="EX1_606",name="Shield Block",type="SPELL",set="CORE",rarity="COMMON",class="WARRIOR",cost=3,text="Gain 5 Armor. Draw a card.",collectible=true}
P["NEW1_011"]={id="NEW1_011",name="Kor'kron Elite",type="MINION",set="CORE",rarity="COMMON",class="WARRIOR",cost=4,atk=4,hp=3,keywords={"CHARGE"},text="<b>Charge</b>",collectible=true}
P["EX1_154"]={id="EX1_154",name="Wrath",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=2,chooseOne={"EX1_154a","EX1_154b"},dustHS={40,400,5,50},text="<b>Choose One</b> - Deal 3 damage to a minion; or 1 damage and draw a card.",collectible=true}
P["EX1_155"]={id="EX1_155",name="Mark of Nature",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=3,chooseOne={"EX1_155a","EX1_155b"},dustHS={40,400,5,50},text="<b>Choose One</b> - Give a minion +4 Attack; or +4 Health and <b>Taunt</b>.",collectible=true}
P["EX1_158"]={id="EX1_158",name="Soul of the Forest",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=4,dustHS={40,400,5,50},text="Give your minions \"<b>Deathrattle:</b> Summon a 2/2 Treant.\"",collectible=true}
P["EX1_160"]={id="EX1_160",name="Power of the Wild",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=2,chooseOne={"EX1_160b","EX1_160a"},dustHS={40,400,5,50},text="<b>Choose One</b> - Give your minions +1/+1; or Summon a 3/2 Panther.",collectible=true}
P["EX1_161"]={id="EX1_161",name="Naturalize",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Destroy a minion. Your opponent draws 2 cards.",collectible=true}
P["EX1_164"]={id="EX1_164",name="Nourish",type="SPELL",set="EXPERT1",rarity="RARE",class="DRUID",cost=5,chooseOne={"EX1_164a","EX1_164b"},dustHS={100,800,20,100},text="<b>Choose One</b> - Gain 2 Mana Crystals; or Draw 3 cards.",collectible=true}
P["EX1_165"]={id="EX1_165",name="Druid of the Claw",type="MINION",set="EXPERT1",rarity="COMMON",class="DRUID",cost=5,atk=4,hp=4,chooseOne={"EX1_165a","EX1_165b"},dustHS={40,400,5,50},text="<b>Choose One -</b> <b>Charge</b>; or +2 Health and <b>Taunt</b>.",collectible=true}
P["EX1_166"]={id="EX1_166",name="Keeper of the Grove",type="MINION",set="EXPERT1",rarity="RARE",class="DRUID",cost=4,atk=2,hp=4,chooseOne={"EX1_166a","EX1_166b"},dustHS={100,800,20,100},text="<b>Choose One</b> - Deal 2 damage; or <b>Silence</b> a minion.",collectible=true}
P["EX1_178"]={id="EX1_178",name="Ancient of War",type="MINION",set="EXPERT1",rarity="EPIC",class="DRUID",cost=7,atk=5,hp=5,chooseOne={"EX1_178b","EX1_178a"},dustHS={400,1600,100,400},text="<b>Choose One</b> - +5 Attack; or +5 Health and <b>Taunt</b>.",collectible=true}
P["EX1_570"]={id="EX1_570",name="Bite",type="SPELL",set="EXPERT1",rarity="RARE",class="DRUID",cost=4,dustHS={100,800,20,100},text="Give your hero +4 Attack this turn and 4 Armor.",collectible=true}
P["EX1_571"]={id="EX1_571",name="Force of Nature",type="SPELL",set="EXPERT1",rarity="EPIC",class="DRUID",cost=6,reqs={REQ_NUM_MINION_SLOTS=1},dustHS={400,1600,100,400},text="Summon three 2/2 Treants with <b>Charge</b> that die at the end of the turn.",collectible=true}
P["EX1_573"]={id="EX1_573",name="Cenarius",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="DRUID",cost=9,atk=5,hp=8,chooseOne={"EX1_573a","EX1_573b"},dustHS={1600,3200,400,1600},text="<b>Choose One</b> - Give your other minions +2/+2; or Summon two 2/2 Treants with <b>Taunt</b>.",collectible=true}
P["EX1_578"]={id="EX1_578",name="Savagery",type="SPELL",set="EXPERT1",rarity="RARE",class="DRUID",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Deal damage equal to your hero's Attack to a minion.",collectible=true}
P["NEW1_007"]={id="NEW1_007",name="Starfall",type="SPELL",set="EXPERT1",rarity="RARE",class="DRUID",cost=5,chooseOne={"NEW1_007b","NEW1_007a"},dustHS={100,800,20,100},text="<b>Choose One -</b> Deal 5 damage to a minion; or 2 damage to all enemy minions.",collectible=true}
P["NEW1_008"]={id="NEW1_008",name="Ancient of Lore",type="MINION",set="EXPERT1",rarity="EPIC",class="DRUID",cost=7,atk=5,hp=5,chooseOne={"NEW1_008a","NEW1_008b"},dustHS={400,1600,100,400},text="<b>Choose One -</b> Draw 2 cards; or Restore 5 Health.",collectible=true}
P["DS1_188"]={id="DS1_188",name="Gladiator's Longbow",type="WEAPON",set="EXPERT1",rarity="EPIC",class="HUNTER",cost=7,atk=5,dur=2,dustHS={400,1600,100,400},text="Your hero is <b>Immune</b> while attacking.",collectible=true}
P["EX1_531"]={id="EX1_531",name="Scavenging Hyena",type="MINION",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=2,atk=2,hp=2,race="BEAST",dustHS={40,400,5,50},text="Whenever a friendly Beast dies, gain +2/+1.",collectible=true}
P["EX1_533"]={id="EX1_533",name="Misdirection",type="SPELL",set="EXPERT1",rarity="RARE",class="HUNTER",cost=2,scriptTags={"SECRET"},dustHS={100,800,20,100},text="<b>Secret:</b> When a character attacks your hero, instead he attacks another random character.",collectible=true}
P["EX1_534"]={id="EX1_534",name="Savannah Highmane",type="MINION",set="EXPERT1",rarity="RARE",class="HUNTER",cost=6,atk=6,hp=5,race="BEAST",scriptTags={"DEATHRATTLE"},dustHS={100,800,20,100},text="<b>Deathrattle:</b> Summon two 2/2 Hyenas.",collectible=true}
P["EX1_536"]={id="EX1_536",name="Eaglehorn Bow",type="WEAPON",set="EXPERT1",rarity="RARE",class="HUNTER",cost=3,atk=3,dur=2,dustHS={100,800,20,100},text="Whenever a friendly <b>Secret</b> is revealed, gain +1 Durability.",collectible=true}
P["EX1_537"]={id="EX1_537",name="Explosive Shot",type="SPELL",set="EXPERT1",rarity="RARE",class="HUNTER",cost=5,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Deal 5 damage to a minion and 2 damage to adjacent ones.",collectible=true}
P["EX1_538"]={id="EX1_538",name="Unleash the Hounds",type="SPELL",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=3,reqs={REQ_MINIMUM_ENEMY_MINIONS=1,REQ_NUM_MINION_SLOTS=1},dustHS={40,400,5,50},text="For each enemy minion, summon a 1/1 Hound with <b>Charge</b>.",collectible=true}
P["EX1_543"]={id="EX1_543",name="King Krush",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="HUNTER",cost=9,atk=8,hp=8,race="BEAST",keywords={"CHARGE"},dustHS={1600,3200,400,1600},text="<b>Charge</b>",collectible=true}
P["EX1_544"]={id="EX1_544",name="Flare",type="SPELL",set="EXPERT1",rarity="RARE",class="HUNTER",cost=2,dustHS={100,800,20,100},text="All minions lose <b>Stealth</b>. Destroy all enemy <b>Secrets</b>. Draw a card.",collectible=true}
P["EX1_549"]={id="EX1_549",name="Bestial Wrath",type="SPELL",set="EXPERT1",rarity="EPIC",class="HUNTER",cost=1,reqs={REQ_FRIENDLY_TARGET=0,REQ_TARGET_TO_PLAY=0,REQ_TARGET_WITH_RACE=20},dustHS={400,1600,100,400},text="Give a friendly Beast +2 Attack and <b>Immune</b> this turn.",collectible=true}
P["EX1_554"]={id="EX1_554",name="Snake Trap",type="SPELL",set="EXPERT1",rarity="EPIC",class="HUNTER",cost=2,scriptTags={"SECRET"},dustHS={400,1600,100,400},text="<b>Secret:</b> When one of your minions is attacked, summon three 1/1 Snakes.",collectible=true}
P["EX1_609"]={id="EX1_609",name="Snipe",type="SPELL",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=2,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When your opponent plays a minion, deal 4 damage to it.",collectible=true}
P["EX1_610"]={id="EX1_610",name="Explosive Trap",type="SPELL",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=2,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When your hero is attacked, deal 2 damage to all enemies.",collectible=true}
P["EX1_611"]={id="EX1_611",name="Freezing Trap",type="SPELL",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=2,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When an enemy minion attacks, return it to its owner's hand and it costs (2) more.",collectible=true}
P["EX1_617"]={id="EX1_617",name="Deadly Shot",type="SPELL",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=3,reqs={REQ_MINIMUM_ENEMY_MINIONS=1},dustHS={40,400,5,50},text="Destroy a random enemy minion.",collectible=true}
P["CS2_028"]={id="CS2_028",name="Blizzard",type="SPELL",set="EXPERT1",rarity="RARE",class="MAGE",cost=6,scriptTags={"FREEZE"},dustHS={100,800,20,100},text="Deal 2 damage to all enemy minions and <b>Freeze</b> them.",collectible=true}
P["CS2_031"]={id="CS2_031",name="Ice Lance",type="SPELL",set="EXPERT1",rarity="COMMON",class="MAGE",cost=1,scriptTags={"FREEZE"},reqs={REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="<b>Freeze</b> a character. If it was already <b>Frozen</b>, deal 4 damage instead.",collectible=true}
P["EX1_274"]={id="EX1_274",name="Ethereal Arcanist",type="MINION",set="EXPERT1",rarity="RARE",class="MAGE",cost=4,atk=3,hp=3,dustHS={100,800,20,100},text="If you control a <b>Secret</b> at the end of your turn, gain +2/+2.",collectible=true}
P["EX1_275"]={id="EX1_275",name="Cone of Cold",type="SPELL",set="EXPERT1",rarity="COMMON",class="MAGE",cost=4,scriptTags={"FREEZE"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="<b>Freeze</b> a minion and the minions next to it, and deal 1 damage to them.",collectible=true}
P["EX1_279"]={id="EX1_279",name="Pyroblast",type="SPELL",set="EXPERT1",rarity="EPIC",class="MAGE",cost=10,reqs={REQ_TARGET_TO_PLAY=0},dustHS={400,1600,100,400},text="Deal 10 damage.",collectible=true}
P["EX1_287"]={id="EX1_287",name="Counterspell",type="SPELL",set="EXPERT1",rarity="RARE",class="MAGE",cost=3,scriptTags={"SECRET"},dustHS={100,800,20,100},text="<b>Secret:</b> When your opponent casts a spell, <b>Counter</b> it.",collectible=true}
P["EX1_289"]={id="EX1_289",name="Ice Barrier",type="SPELL",set="EXPERT1",rarity="COMMON",class="MAGE",cost=3,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When your hero is attacked, gain 8 Armor.",collectible=true}
P["EX1_294"]={id="EX1_294",name="Mirror Entity",type="SPELL",set="EXPERT1",rarity="COMMON",class="MAGE",cost=3,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When your opponent plays a minion, summon a copy of it.",collectible=true}
P["EX1_295"]={id="EX1_295",name="Ice Block",type="SPELL",set="EXPERT1",rarity="EPIC",class="MAGE",cost=3,scriptTags={"SECRET"},dustHS={400,1600,100,400},text="<b>Secret:</b> When your hero takes fatal damage, prevent it and become <b>Immune</b> this turn.",collectible=true}
P["EX1_559"]={id="EX1_559",name="Archmage Antonidas",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="MAGE",cost=7,atk=5,hp=7,dustHS={1600,3200,400,1600},text="Whenever you cast a spell, add a 'Fireball' spell to your hand.",collectible=true}
P["EX1_594"]={id="EX1_594",name="Vaporize",type="SPELL",set="EXPERT1",rarity="RARE",class="MAGE",cost=3,scriptTags={"SECRET"},dustHS={100,800,20,100},text="<b>Secret:</b> When a minion attacks your hero, destroy it.",collectible=true}
P["EX1_608"]={id="EX1_608",name="Sorcerer's Apprentice",type="MINION",set="EXPERT1",rarity="COMMON",class="MAGE",cost=2,atk=3,hp=2,scriptTags={"AURA"},dustHS={40,400,5,50},text="Your spells cost (1) less.",collectible=true}
P["EX1_612"]={id="EX1_612",name="Kirin Tor Mage",type="MINION",set="EXPERT1",rarity="RARE",class="MAGE",cost=3,atk=4,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> The next <b>Secret</b> you play this turn costs (0).",collectible=true}
P["NEW1_012"]={id="NEW1_012",name="Mana Wyrm",type="MINION",set="EXPERT1",rarity="COMMON",class="MAGE",cost=1,atk=1,hp=3,dustHS={40,400,5,50},text="Whenever you cast a spell, gain +1 Attack.",collectible=true}
P["tt_010"]={id="tt_010",name="Spellbender",type="SPELL",set="EXPERT1",rarity="EPIC",class="MAGE",cost=3,scriptTags={"SECRET"},dustHS={400,1600,100,400},text="<b>Secret:</b> When an enemy casts a spell on a minion, summon a 1/3 as the new target.",collectible=true}
P["CS1_069"]={id="CS1_069",name="Fen Creeper",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=5,atk=3,hp=6,keywords={"TAUNT"},dustHS={40,400,5,50},text="<b>Taunt</b>",collectible=true}
P["CS2_117"]={id="CS2_117",name="Earthen Ring Farseer",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Restore 3 Health.",collectible=true}
P["CS2_146"]={id="CS2_146",name="Southsea Deckhand",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,race="PIRATE",dustHS={40,400,5,50},text="Has <b>Charge</b> while you have a weapon equipped.",collectible=true}
P["CS2_151"]={id="CS2_151",name="Silver Hand Knight",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=5,atk=4,hp=4,scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Summon a 2/2 Squire.",collectible=true}
P["CS2_161"]={id="CS2_161",name="Ravenholdt Assassin",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=7,atk=7,hp=5,keywords={"STEALTH"},dustHS={100,800,20,100},text="<b>Stealth</b>",collectible=true}
P["CS2_169"]={id="CS2_169",name="Young Dragonhawk",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,race="BEAST",keywords={"WINDFURY"},dustHS={40,400,5,50},text="<b>Windfury</b>",collectible=true}
P["CS2_181"]={id="CS2_181",name="Injured Blademaster",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=4,hp=7,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Deal 4 damage to HIMSELF.",collectible=true}
P["CS2_188"]={id="CS2_188",name="Abusive Sergeant",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Give a minion +2 Attack this turn.",collectible=true}
P["CS2_203"]={id="CS2_203",name="Ironbeak Owl",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=1,race="BEAST",scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> <b>Silence</b> a minion.",collectible=true}
P["CS2_221"]={id="CS2_221",name="Spiteful Smith",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=5,atk=4,hp=6,scriptTags={"ENRAGED"},dustHS={40,400,5,50},text="<b>Enrage:</b> Your weapon has +2 Attack.",collectible=true}
P["CS2_227"]={id="CS2_227",name="Venture Co. Mercenary",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=5,atk=7,hp=6,scriptTags={"AURA"},dustHS={40,400,5,50},text="Your minions cost (3) more.",collectible=true}
P["CS2_231"]={id="CS2_231",name="Wisp",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=0,atk=1,hp=1,dustHS={40,400,5,50},text=nil,collectible=true}
P["EX1_001"]={id="EX1_001",name="Lightwarden",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=1,hp=2,dustHS={100,800,20,100},text="Whenever a character is healed, gain +2 Attack.",collectible=true}
P["EX1_002"]={id="EX1_002",name="The Black Knight",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=4,hp=5,scriptTags={"BATTLECRY"},reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_MUST_TARGET_TAUNTER=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Destroy an enemy minion with <b>Taunt</b>.",collectible=true}
P["EX1_004"]={id="EX1_004",name="Young Priestess",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=2,hp=1,dustHS={100,800,20,100},text="At the end of your turn, give another random friendly minion +1 Health.",collectible=true}
P["EX1_005"]={id="EX1_005",name="Big Game Hunter",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=3,atk=4,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_MIN_ATTACK=7},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Destroy a minion with an Attack of 7 or more.",collectible=true}
P["EX1_006"]={id="EX1_006",name="Alarm-o-Bot",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=0,hp=3,race="MECHANICAL",dustHS={100,800,20,100},text="At the start of your turn, swap this minion with a random one in your hand.",collectible=true}
P["EX1_007"]={id="EX1_007",name="Acolyte of Pain",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=1,hp=3,dustHS={40,400,5,50},text="Whenever this minion takes damage, draw a card.",collectible=true}
P["EX1_008"]={id="EX1_008",name="Argent Squire",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,keywords={"DIVINE_SHIELD"},dustHS={40,400,5,50},text="<b>Divine Shield</b>",collectible=true}
P["EX1_009"]={id="EX1_009",name="Angry Chicken",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=1,hp=1,race="BEAST",scriptTags={"ENRAGED"},dustHS={100,800,20,100},text="<b>Enrage:</b> +5 Attack.",collectible=true}
P["EX1_010"]={id="EX1_010",name="Worgen Infiltrator",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,keywords={"STEALTH"},dustHS={40,400,5,50},text="<b>Stealth</b>",collectible=true}
P["EX1_012"]={id="EX1_012",name="Bloodmage Thalnos",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=1,hp=1,spellDamage=1,scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Spell Damage +1</b>. <b>Deathrattle:</b> Draw a card.",collectible=true}
P["EX1_014"]={id="EX1_014",name="King Mukla",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=3,atk=5,hp=5,race="BEAST",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Give your opponent 2 Bananas.",collectible=true}
P["EX1_016"]={id="EX1_016",name="Sylvanas Windrunner",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=5,hp=5,scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Deathrattle:</b> Take control of a random enemy minion.",collectible=true}
P["EX1_017"]={id="EX1_017",name="Jungle Panther",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=4,hp=2,race="BEAST",keywords={"STEALTH"},dustHS={40,400,5,50},text="<b>Stealth</b>",collectible=true}
P["EX1_020"]={id="EX1_020",name="Scarlet Crusader",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=1,keywords={"DIVINE_SHIELD"},dustHS={40,400,5,50},text="<b>Divine Shield</b>",collectible=true}
P["EX1_021"]={id="EX1_021",name="Thrallmar Farseer",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=2,hp=3,keywords={"WINDFURY"},dustHS={40,400,5,50},text="<b>Windfury</b>",collectible=true}
P["EX1_023"]={id="EX1_023",name="Silvermoon Guardian",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=3,hp=3,keywords={"DIVINE_SHIELD"},dustHS={40,400,5,50},text="<b>Divine Shield</b>",collectible=true}
P["EX1_028"]={id="EX1_028",name="Stranglethorn Tiger",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=5,atk=5,hp=5,race="BEAST",keywords={"STEALTH"},dustHS={40,400,5,50},text="<b>Stealth</b>",collectible=true}
P["EX1_029"]={id="EX1_029",name="Leper Gnome",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Deal 2 damage to the enemy hero.",collectible=true}
P["EX1_032"]={id="EX1_032",name="Sunwalker",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=6,atk=4,hp=5,keywords={"DIVINE_SHIELD","TAUNT"},dustHS={100,800,20,100},text="<b>Taunt</b>. <b>Divine Shield</b>",collectible=true}
P["EX1_033"]={id="EX1_033",name="Windfury Harpy",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=6,atk=4,hp=5,keywords={"WINDFURY"},dustHS={40,400,5,50},text="<b>Windfury</b>",collectible=true}
P["EX1_043"]={id="EX1_043",name="Twilight Drake",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=4,atk=4,hp=1,race="DRAGON",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Gain +1 Health for each card in your hand.",collectible=true}
P["EX1_044"]={id="EX1_044",name="Questing Adventurer",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=2,dustHS={100,800,20,100},text="Whenever you play a card, gain +1/+1.",collectible=true}
P["EX1_045"]={id="EX1_045",name="Ancient Watcher",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=4,hp=5,keywords={"CANT_ATTACK"},dustHS={100,800,20,100},text="Can't Attack.",collectible=true}
P["EX1_046"]={id="EX1_046",name="Dark Iron Dwarf",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=4,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Give a minion +2 Attack this turn.",collectible=true}
P["EX1_048"]={id="EX1_048",name="Spellbreaker",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> <b>Silence</b> a minion.",collectible=true}
P["EX1_049"]={id="EX1_049",name="Youthful Brewmaster",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=3,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Return a friendly minion from the battlefield to your hand.",collectible=true}
P["EX1_050"]={id="EX1_050",name="Coldlight Oracle",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=2,race="MURLOC",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Each player draws 2 cards.",collectible=true}
P["EX1_055"]={id="EX1_055",name="Mana Addict",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=1,hp=3,dustHS={100,800,20,100},text="Whenever you cast a spell, gain +2 Attack this turn.",collectible=true}
P["EX1_057"]={id="EX1_057",name="Ancient Brewmaster",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=5,hp=4,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Return a friendly minion from the battlefield to your hand.",collectible=true}
P["EX1_058"]={id="EX1_058",name="Sunfury Protector",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=2,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Give adjacent minions <b>Taunt</b>.",collectible=true}
P["EX1_059"]={id="EX1_059",name="Crazed Alchemist",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=2,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={100,800,20,100},text="<b>Battlecry:</b> Swap the Attack and Health of a minion.",collectible=true}
P["EX1_067"]={id="EX1_067",name="Argent Commander",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=6,atk=4,hp=2,keywords={"CHARGE","DIVINE_SHIELD"},dustHS={100,800,20,100},text="<b>Charge</b>, <b>Divine Shield</b>",collectible=true}
P["EX1_076"]={id="EX1_076",name="Pint-Sized Summoner",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=2,hp=2,scriptTags={"AURA"},dustHS={100,800,20,100},text="The first minion you play each turn costs (1) less.",collectible=true}
P["EX1_080"]={id="EX1_080",name="Secretkeeper",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=1,hp=2,dustHS={100,800,20,100},text="Whenever a <b>Secret</b> is played, gain +1/+1.",collectible=true}
P["EX1_082"]={id="EX1_082",name="Mad Bomber",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=3,hp=2,scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Deal 3 damage randomly split between all other characters.",collectible=true}
P["EX1_083"]={id="EX1_083",name="Tinkmaster Overspark",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=3,atk=3,hp=3,scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Transform another random minion into a 5/5 Devilsaur or a 1/1 Squirrel.",collectible=true}
P["EX1_085"]={id="EX1_085",name="Mind Control Tech",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=3,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> If your opponent has 4 or more minions, take control of one at random.",collectible=true}
P["EX1_089"]={id="EX1_089",name="Arcane Golem",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=4,hp=2,keywords={"CHARGE"},scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Charge</b>. <b>Battlecry:</b> Give your opponent a Mana Crystal.",collectible=true}
P["EX1_093"]={id="EX1_093",name="Defender of Argus",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=4,atk=2,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Give adjacent minions +1/+1 and <b>Taunt</b>.",collectible=true}
P["EX1_095"]={id="EX1_095",name="Gadgetzan Auctioneer",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=6,atk=4,hp=4,dustHS={100,800,20,100},text="Whenever you cast a spell, draw a card.",collectible=true}
P["EX1_096"]={id="EX1_096",name="Loot Hoarder",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=1,scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Draw a card.",collectible=true}
P["EX1_097"]={id="EX1_097",name="Abomination",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=5,atk=4,hp=4,keywords={"TAUNT"},scriptTags={"DEATHRATTLE"},dustHS={100,800,20,100},text="<b>Taunt</b>. <b>Deathrattle:</b> Deal 2 damage to ALL characters.",collectible=true}
P["EX1_100"]={id="EX1_100",name="Lorewalker Cho",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=0,hp=4,dustHS={1600,3200,400,1600},text="Whenever a player casts a spell, put a copy into the other player’s hand.",collectible=true}
P["EX1_102"]={id="EX1_102",name="Demolisher",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=1,hp=4,race="MECHANICAL",dustHS={100,800,20,100},text="At the start of your turn, deal 2 damage to a random enemy.",collectible=true}
P["EX1_103"]={id="EX1_103",name="Coldlight Seer",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=3,race="MURLOC",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Give ALL other Murlocs +2 Health.",collectible=true}
P["EX1_105"]={id="EX1_105",name="Mountain Giant",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=12,atk=8,hp=8,dustHS={400,1600,100,400},text="Costs (1) less for each other card in your hand.",collectible=true}
P["EX1_110"]={id="EX1_110",name="Cairne Bloodhoof",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=4,hp=5,scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Deathrattle:</b> Summon a 4/5 Baine Bloodhoof.",collectible=true}
P["EX1_116"]={id="EX1_116",name="Leeroy Jenkins",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=6,hp=2,keywords={"CHARGE"},scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Charge</b>. <b>Battlecry:</b> Summon two 1/1 Whelps for your opponent.",collectible=true}
P["EX1_162"]={id="EX1_162",name="Dire Wolf Alpha",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=2,race="BEAST",scriptTags={"ADJACENT_BUFF","AURA"},dustHS={40,400,5,50},text="Adjacent minions have +1 Attack.",collectible=true}
P["EX1_170"]={id="EX1_170",name="Emperor Cobra",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=3,race="BEAST",keywords={"POISONOUS"},dustHS={100,800,20,100},text="Destroy any minion damaged by this minion.",collectible=true}
P["EX1_249"]={id="EX1_249",name="Baron Geddon",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=7,atk=7,hp=5,dustHS={1600,3200,400,1600},text="At the end of your turn, deal 2 damage to ALL other characters.",collectible=true}
P["EX1_283"]={id="EX1_283",name="Frost Elemental",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=6,atk=5,hp=5,scriptTags={"BATTLECRY","FREEZE"},reqs={REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> <b>Freeze</b> a character.",collectible=true}
P["EX1_284"]={id="EX1_284",name="Azure Drake",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=5,atk=4,hp=4,race="DRAGON",spellDamage=1,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Spell Damage +1</b>. <b>Battlecry:</b> Draw a card.",collectible=true}
P["EX1_298"]={id="EX1_298",name="Ragnaros the Firelord",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=8,atk=8,hp=8,keywords={"CANT_ATTACK"},dustHS={1600,3200,400,1600},text="Can't Attack. At the end of your turn, deal 8 damage to a random enemy.",collectible=true}
P["EX1_390"]={id="EX1_390",name="Tauren Warrior",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=2,hp=3,keywords={"TAUNT"},scriptTags={"ENRAGED"},dustHS={40,400,5,50},text="<b>Taunt</b>. <b>Enrage:</b> +3 Attack",collectible=true}
P["EX1_393"]={id="EX1_393",name="Amani Berserker",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=3,scriptTags={"ENRAGED"},dustHS={40,400,5,50},text="<b>Enrage:</b> +3 Attack",collectible=true}
P["EX1_396"]={id="EX1_396",name="Mogu'shan Warden",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=1,hp=7,keywords={"TAUNT"},dustHS={40,400,5,50},text="<b>Taunt</b>",collectible=true}
P["EX1_405"]={id="EX1_405",name="Shieldbearer",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=0,hp=4,keywords={"TAUNT"},dustHS={40,400,5,50},text="<b>Taunt</b>",collectible=true}
P["EX1_412"]={id="EX1_412",name="Raging Worgen",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=3,scriptTags={"ENRAGED"},dustHS={40,400,5,50},text="<b>Enrage:</b> <b>Windfury</b> and +1 Attack",collectible=true}
P["EX1_507"]={id="EX1_507",name="Murloc Warleader",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=3,atk=3,hp=3,race="MURLOC",scriptTags={"AURA"},dustHS={400,1600,100,400},text="ALL other Murlocs have +2/+1.",collectible=true}
P["EX1_509"]={id="EX1_509",name="Murloc Tidecaller",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=1,hp=2,race="MURLOC",dustHS={100,800,20,100},text="Whenever a Murloc is summoned, gain +1 Attack.",collectible=true}
P["EX1_556"]={id="EX1_556",name="Harvest Golem",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=2,hp=3,race="MECHANICAL",scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Summon a 2/1 Damaged Golem.",collectible=true}
P["EX1_557"]={id="EX1_557",name="Nat Pagle",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=0,hp=4,dustHS={1600,3200,400,1600},text="At the start of your turn, you have a 50% chance to draw an extra card.",collectible=true}
P["EX1_558"]={id="EX1_558",name="Harrison Jones",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=5,hp=4,scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Destroy your opponent's weapon and draw cards equal to its Durability.",collectible=true}
P["EX1_560"]={id="EX1_560",name="Nozdormu",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=8,hp=8,race="DRAGON",dustHS={1600,3200,400,1600},text="Players only have 15 seconds to take their turns.",collectible=true}
P["EX1_561"]={id="EX1_561",name="Alexstrasza",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=8,hp=8,race="DRAGON",scriptTags={"BATTLECRY"},reqs={REQ_HERO_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Set a hero's remaining Health to 15.",collectible=true}
P["EX1_562"]={id="EX1_562",name="Onyxia",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=8,hp=8,race="DRAGON",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Summon 1/1 Whelps until your side of the battlefield is full.",collectible=true}
P["EX1_563"]={id="EX1_563",name="Malygos",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=4,hp=12,race="DRAGON",spellDamage=5,dustHS={1600,3200,400,1600},text="<b>Spell Damage +5</b>",collectible=true}
P["EX1_564"]={id="EX1_564",name="Faceless Manipulator",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=5,atk=3,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Choose a minion and become a copy of it.",collectible=true}
P["EX1_572"]={id="EX1_572",name="Ysera",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=4,hp=12,race="DRAGON",entourage={"DREAM_01","DREAM_02","DREAM_03","DREAM_04","DREAM_05"},dustHS={1600,3200,400,1600},text="At the end of your turn, draw a Dream Card.",collectible=true}
P["EX1_577"]={id="EX1_577",name="The Beast",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=9,hp=7,race="BEAST",scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Deathrattle:</b> Summon a 3/3 Finkle Einhorn for your opponent.",collectible=true}
P["EX1_583"]={id="EX1_583",name="Priestess of Elune",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=6,atk=5,hp=4,scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Restore 4 Health to your hero.",collectible=true}
P["EX1_584"]={id="EX1_584",name="Ancient Mage",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=4,atk=2,hp=5,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Give adjacent minions <b>Spell Damage +1</b>.",collectible=true}
P["EX1_586"]={id="EX1_586",name="Sea Giant",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=10,atk=8,hp=8,dustHS={400,1600,100,400},text="Costs (1) less for each other minion on the battlefield.",collectible=true}
P["EX1_590"]={id="EX1_590",name="Blood Knight",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=3,atk=3,hp=3,scriptTags={"BATTLECRY"},dustHS={400,1600,100,400},text="<b>Battlecry:</b> All minions lose <b>Divine Shield</b>. Gain +3/+3 for each Shield lost.",collectible=true}
P["EX1_595"]={id="EX1_595",name="Cult Master",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=2,dustHS={40,400,5,50},text="Whenever one of your other minions dies, draw a card.",collectible=true}
P["EX1_597"]={id="EX1_597",name="Imp Master",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=3,atk=1,hp=5,dustHS={100,800,20,100},text="At the end of your turn, deal 1 damage to this minion and summon a 1/1 Imp.",collectible=true}
P["EX1_614"]={id="EX1_614",name="Illidan Stormrage",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=7,hp=5,race="DEMON",dustHS={1600,3200,400,1600},text="Whenever you play a card, summon a 2/1 Flame of Azzinoth.",collectible=true}
P["EX1_616"]={id="EX1_616",name="Mana Wraith",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=2,hp=2,scriptTags={"AURA"},dustHS={100,800,20,100},text="ALL minions cost (1) more.",collectible=true}
P["EX1_620"]={id="EX1_620",name="Molten Giant",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=20,atk=8,hp=8,dustHS={400,1600,100,400},text="Costs (1) less for each damage your hero has taken.",collectible=true}
P["NEW1_017"]={id="NEW1_017",name="Hungry Crab",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=1,atk=1,hp=2,race="BEAST",scriptTags={"BATTLECRY"},reqs={REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_WITH_RACE=14},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Destroy a Murloc and gain +2/+2.",collectible=true}
P["NEW1_018"]={id="NEW1_018",name="Bloodsail Raider",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=3,race="PIRATE",scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Gain Attack equal to the Attack of your weapon.",collectible=true}
P["NEW1_019"]={id="NEW1_019",name="Knife Juggler",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=3,hp=2,dustHS={100,800,20,100},text="After you summon a minion, deal 1 damage to a random enemy.",collectible=true}
P["NEW1_020"]={id="NEW1_020",name="Wild Pyromancer",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=3,hp=2,dustHS={100,800,20,100},text="After you cast a spell, deal 1 damage to ALL minions.",collectible=true}
P["NEW1_021"]={id="NEW1_021",name="Doomsayer",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=2,atk=0,hp=7,dustHS={400,1600,100,400},text="At the start of your turn, destroy ALL minions.",collectible=true}
P["NEW1_022"]={id="NEW1_022",name="Dread Corsair",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=4,atk=3,hp=3,race="PIRATE",keywords={"TAUNT"},dustHS={40,400,5,50},text="<b>Taunt.</b> Costs (1) less per Attack of your weapon.",collectible=true}
P["NEW1_023"]={id="NEW1_023",name="Faerie Dragon",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=2,atk=3,hp=2,race="DRAGON",keywords={"CANT_BE_TARGETED_BY_HERO_POWERS","CANT_BE_TARGETED_BY_SPELLS"},dustHS={40,400,5,50},text="Can't be targeted by spells or Hero Powers.",collectible=true}
P["NEW1_024"]={id="NEW1_024",name="Captain Greenskin",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=5,hp=4,race="PIRATE",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Give your weapon +1/+1.",collectible=true}
P["NEW1_025"]={id="NEW1_025",name="Bloodsail Corsair",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=1,hp=2,race="PIRATE",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Remove 1 Durability from your opponent's weapon.",collectible=true}
P["NEW1_026"]={id="NEW1_026",name="Violet Teacher",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=4,atk=3,hp=5,dustHS={100,800,20,100},text="Whenever you cast a spell, summon a 1/1 Violet Apprentice.",collectible=true}
P["NEW1_027"]={id="NEW1_027",name="Southsea Captain",type="MINION",set="EXPERT1",rarity="EPIC",class="NEUTRAL",cost=3,atk=3,hp=3,race="PIRATE",scriptTags={"AURA"},dustHS={400,1600,100,400},text="Your other Pirates have +1/+1.",collectible=true}
P["NEW1_029"]={id="NEW1_029",name="Millhouse Manastorm",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=4,hp=4,scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Enemy spells cost (0) next turn.",collectible=true}
P["NEW1_030"]={id="NEW1_030",name="Deathwing",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=10,atk=12,hp=12,race="DRAGON",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Destroy all other minions and discard your hand.",collectible=true}
P["NEW1_037"]={id="NEW1_037",name="Master Swordsmith",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=2,atk=1,hp=3,dustHS={100,800,20,100},text="At the end of your turn, give another random friendly minion +1 Attack.",collectible=true}
P["NEW1_038"]={id="NEW1_038",name="Gruul",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=8,atk=7,hp=7,dustHS={1600,3200,400,1600},text="At the end of each turn, gain +1/+1 .",collectible=true}
P["NEW1_040"]={id="NEW1_040",name="Hogger",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=4,hp=4,dustHS={1600,3200,400,1600},text="At the end of your turn, summon a 2/2 Gnoll with <b>Taunt</b>.",collectible=true}
P["NEW1_041"]={id="NEW1_041",name="Stampeding Kodo",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=5,atk=3,hp=5,race="BEAST",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Destroy a random enemy minion with 2 or less Attack.",collectible=true}
P["tt_004"]={id="tt_004",name="Flesheating Ghoul",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=3,atk=2,hp=3,dustHS={40,400,5,50},text="Whenever a minion dies, gain +1 Attack.",collectible=true}
P["EX1_130"]={id="EX1_130",name="Noble Sacrifice",type="SPELL",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=1,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When an enemy attacks, summon a 2/1 Defender as the new target.",collectible=true}
P["EX1_132"]={id="EX1_132",name="Eye for an Eye",type="SPELL",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=1,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When your hero takes damage, deal that much damage to the enemy hero.",collectible=true}
P["EX1_136"]={id="EX1_136",name="Redemption",type="SPELL",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=1,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When one of your minions dies, return it to life with 1 Health.",collectible=true}
P["EX1_349"]={id="EX1_349",name="Divine Favor",type="SPELL",set="EXPERT1",rarity="RARE",class="PALADIN",cost=3,dustHS={100,800,20,100},text="Draw cards until you have as many in hand as your opponent.",collectible=true}
P["EX1_354"]={id="EX1_354",name="Lay on Hands",type="SPELL",set="EXPERT1",rarity="EPIC",class="PALADIN",cost=8,reqs={REQ_TARGET_TO_PLAY=0},dustHS={400,1600,100,400},text="Restore 8 Health. Draw 3 cards.",collectible=true}
P["EX1_355"]={id="EX1_355",name="Blessed Champion",type="SPELL",set="EXPERT1",rarity="RARE",class="PALADIN",cost=5,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Double a minion's Attack.",collectible=true}
P["EX1_362"]={id="EX1_362",name="Argent Protector",type="MINION",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=2,atk=2,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Give a friendly minion <b>Divine Shield</b>.",collectible=true}
P["EX1_363"]={id="EX1_363",name="Blessing of Wisdom",type="SPELL",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Choose a minion. Whenever it attacks, draw a card.",collectible=true}
P["EX1_365"]={id="EX1_365",name="Holy Wrath",type="SPELL",set="EXPERT1",rarity="RARE",class="PALADIN",cost=5,reqs={REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Draw a card and deal damage equal to its cost.",collectible=true}
P["EX1_366"]={id="EX1_366",name="Sword of Justice",type="WEAPON",set="EXPERT1",rarity="EPIC",class="PALADIN",cost=3,atk=1,dur=5,dustHS={400,1600,100,400},text="Whenever you summon a minion, give it +1/+1 and this loses 1 Durability.",collectible=true}
P["EX1_379"]={id="EX1_379",name="Repentance",type="SPELL",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=1,scriptTags={"SECRET"},dustHS={40,400,5,50},text="<b>Secret:</b> When your opponent plays a minion, reduce its Health to 1.",collectible=true}
P["EX1_382"]={id="EX1_382",name="Aldor Peacekeeper",type="MINION",set="EXPERT1",rarity="RARE",class="PALADIN",cost=3,atk=3,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={100,800,20,100},text="<b>Battlecry:</b> Change an enemy minion's Attack to 1.",collectible=true}
P["EX1_383"]={id="EX1_383",name="Tirion Fordring",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="PALADIN",cost=8,atk=6,hp=6,keywords={"DIVINE_SHIELD","TAUNT"},scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Divine Shield</b>. <b>Taunt</b>. <b>Deathrattle:</b> Equip a 5/3 Ashbringer.",collectible=true}
P["EX1_384"]={id="EX1_384",name="Avenging Wrath",type="SPELL",set="EXPERT1",rarity="EPIC",class="PALADIN",cost=6,keywords={"ImmuneToSpellpower"},dustHS={400,1600,100,400},text="Deal 8 damage randomly split among enemy characters.",collectible=true}
P["EX1_619"]={id="EX1_619",name="Equality",type="SPELL",set="EXPERT1",rarity="RARE",class="PALADIN",cost=2,dustHS={100,800,20,100},text="Change the Health of ALL minions to 1.",collectible=true}
P["CS1_129"]={id="CS1_129",name="Inner Fire",type="SPELL",set="EXPERT1",rarity="COMMON",class="PRIEST",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Change a minion's Attack to be equal to its Health.",collectible=true}
P["EX1_091"]={id="EX1_091",name="Cabal Shadow Priest",type="MINION",set="EXPERT1",rarity="EPIC",class="PRIEST",cost=6,atk=4,hp=5,scriptTags={"BATTLECRY"},reqs={REQ_ENEMY_TARGET=0,REQ_MINION_CAP_IF_TARGET_AVAILABLE=2,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_MAX_ATTACK=2},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Take control of an enemy minion that has 2 or less Attack.",collectible=true}
P["EX1_332"]={id="EX1_332",name="Silence",type="SPELL",set="EXPERT1",rarity="COMMON",class="PRIEST",cost=0,scriptTags={"SILENCE"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="<b>Silence</b> a minion.",collectible=true}
P["EX1_334"]={id="EX1_334",name="Shadow Madness",type="SPELL",set="EXPERT1",rarity="RARE",class="PRIEST",cost=4,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_NUM_MINION_SLOTS=1,REQ_TARGET_MAX_ATTACK=3,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Gain control of an enemy minion with 3 or less Attack until end of turn.",collectible=true}
P["EX1_335"]={id="EX1_335",name="Lightspawn",type="MINION",set="EXPERT1",rarity="COMMON",class="PRIEST",cost=4,atk=0,hp=5,dustHS={40,400,5,50},text="This minion's Attack is always equal to its Health.",collectible=true}
P["EX1_339"]={id="EX1_339",name="Thoughtsteal",type="SPELL",set="EXPERT1",rarity="COMMON",class="PRIEST",cost=3,dustHS={40,400,5,50},text="Copy 2 cards from your opponent's deck and put them into your hand.",collectible=true}
P["EX1_341"]={id="EX1_341",name="Lightwell",type="MINION",set="EXPERT1",rarity="RARE",class="PRIEST",cost=2,atk=0,hp=5,dustHS={100,800,20,100},text="At the start of your turn, restore 3 Health to a damaged friendly character.",collectible=true}
P["EX1_345"]={id="EX1_345",name="Mindgames",type="SPELL",set="EXPERT1",rarity="EPIC",class="PRIEST",cost=4,reqs={REQ_NUM_MINION_SLOTS=1},dustHS={400,1600,100,400},text="Put a copy of a random minion from your opponent's deck into the battlefield.",collectible=true}
P["EX1_350"]={id="EX1_350",name="Prophet Velen",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="PRIEST",cost=7,atk=7,hp=7,dustHS={1600,3200,400,1600},text="Double the damage and healing of your spells and Hero Power.",collectible=true}
P["EX1_591"]={id="EX1_591",name="Auchenai Soulpriest",type="MINION",set="EXPERT1",rarity="RARE",class="PRIEST",cost=4,atk=3,hp=5,scriptTags={"AURA"},dustHS={100,800,20,100},text="Your cards and powers that restore Health now deal damage instead.",collectible=true}
P["EX1_621"]={id="EX1_621",name="Circle of Healing",type="SPELL",set="EXPERT1",rarity="COMMON",class="PRIEST",cost=0,dustHS={40,400,5,50},text="Restore 4 Health to ALL minions.",collectible=true}
P["EX1_623"]={id="EX1_623",name="Temple Enforcer",type="MINION",set="EXPERT1",rarity="COMMON",class="PRIEST",cost=6,atk=6,hp=6,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Give a friendly minion +3 Health.",collectible=true}
P["EX1_624"]={id="EX1_624",name="Holy Fire",type="SPELL",set="EXPERT1",rarity="RARE",class="PRIEST",cost=6,reqs={REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Deal 5 damage. Restore 5 Health to your hero.",collectible=true}
P["EX1_625"]={id="EX1_625",name="Shadowform",type="SPELL",set="EXPERT1",rarity="EPIC",class="PRIEST",cost=3,dustHS={400,1600,100,400},text="Your Hero Power becomes 'Deal 2 damage'. If already in Shadowform: 3 damage.",collectible=true}
P["EX1_626"]={id="EX1_626",name="Mass Dispel",type="SPELL",set="EXPERT1",rarity="RARE",class="PRIEST",cost=4,scriptTags={"SILENCE"},dustHS={100,800,20,100},text="<b>Silence</b> all enemy minions. Draw a card.",collectible=true}
P["CS2_073"]={id="CS2_073",name="Cold Blood",type="SPELL",set="EXPERT1",rarity="COMMON",class="ROGUE",cost=1,scriptTags={"COMBO"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Give a minion +2 Attack. <b>Combo:</b> +4 Attack instead.",collectible=true}
P["CS2_233"]={id="CS2_233",name="Blade Flurry",type="SPELL",set="EXPERT1",rarity="RARE",class="ROGUE",cost=2,reqs={REQ_WEAPON_EQUIPPED=0},dustHS={100,800,20,100},text="Destroy your weapon and deal its damage to all enemies.",collectible=true}
P["EX1_124"]={id="EX1_124",name="Eviscerate",type="SPELL",set="EXPERT1",rarity="COMMON",class="ROGUE",cost=2,scriptTags={"COMBO"},reqs={REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 2 damage. <b>Combo:</b> Deal 4 damage instead.",collectible=true}
P["EX1_126"]={id="EX1_126",name="Betrayal",type="SPELL",set="EXPERT1",rarity="COMMON",class="ROGUE",cost=2,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Force an enemy minion to deal its damage to the minions next to it.",collectible=true}
P["EX1_128"]={id="EX1_128",name="Conceal",type="SPELL",set="EXPERT1",rarity="COMMON",class="ROGUE",cost=1,dustHS={40,400,5,50},text="Give your minions <b>Stealth</b> until your next turn.",collectible=true}
P["EX1_131"]={id="EX1_131",name="Defias Ringleader",type="MINION",set="EXPERT1",rarity="COMMON",class="ROGUE",cost=2,atk=2,hp=2,scriptTags={"COMBO"},dustHS={40,400,5,50},text="<b>Combo:</b> Summon a 2/1 Defias Bandit.",collectible=true}
P["EX1_133"]={id="EX1_133",name="Perdition's Blade",type="WEAPON",set="EXPERT1",rarity="RARE",class="ROGUE",cost=3,atk=2,dur=2,scriptTags={"BATTLECRY","COMBO"},reqs={REQ_TARGET_IF_AVAILABLE=0},dustHS={100,800,20,100},text="<b>Battlecry:</b> Deal 1 damage. <b>Combo:</b> Deal 2 instead.",collectible=true}
P["EX1_134"]={id="EX1_134",name="SI:7 Agent",type="MINION",set="EXPERT1",rarity="RARE",class="ROGUE",cost=3,atk=3,hp=3,scriptTags={"COMBO"},reqs={REQ_TARGET_FOR_COMBO=0},dustHS={100,800,20,100},text="<b>Combo:</b> Deal 2 damage.",collectible=true}
P["EX1_137"]={id="EX1_137",name="Headcrack",type="SPELL",set="EXPERT1",rarity="RARE",class="ROGUE",cost=3,scriptTags={"COMBO"},dustHS={100,800,20,100},text="Deal 2 damage to the enemy hero. <b>Combo:</b> Return this to your hand next turn.",collectible=true}
P["EX1_144"]={id="EX1_144",name="Shadowstep",type="SPELL",set="EXPERT1",rarity="COMMON",class="ROGUE",cost=0,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Return a friendly minion to your hand. It costs (2) less.",collectible=true}
P["EX1_145"]={id="EX1_145",name="Preparation",type="SPELL",set="EXPERT1",rarity="EPIC",class="ROGUE",cost=0,dustHS={400,1600,100,400},text="The next spell you cast this turn costs (3) less.",collectible=true}
P["EX1_522"]={id="EX1_522",name="Patient Assassin",type="MINION",set="EXPERT1",rarity="EPIC",class="ROGUE",cost=2,atk=1,hp=1,keywords={"POISONOUS","STEALTH"},dustHS={400,1600,100,400},text="<b>Stealth</b>. Destroy any minion damaged by this minion.",collectible=true}
P["EX1_613"]={id="EX1_613",name="Edwin VanCleef",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="ROGUE",cost=3,atk=2,hp=2,scriptTags={"COMBO"},dustHS={1600,3200,400,1600},text="<b>Combo:</b> Gain +2/+2 for each card played earlier this turn.",collectible=true}
P["NEW1_005"]={id="NEW1_005",name="Kidnapper",type="MINION",set="EXPERT1",rarity="EPIC",class="ROGUE",cost=6,atk=5,hp=3,scriptTags={"COMBO"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_FOR_COMBO=0},dustHS={400,1600,100,400},text="<b>Combo:</b> Return a minion to its owner's hand.",collectible=true}
P["NEW1_014"]={id="NEW1_014",name="Master of Disguise",type="MINION",set="EXPERT1",rarity="RARE",class="ROGUE",cost=4,atk=4,hp=4,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={100,800,20,100},text="<b>Battlecry:</b> Give a friendly minion <b>Stealth</b>.",collectible=true}
P["CS2_038"]={id="CS2_038",name="Ancestral Spirit",type="SPELL",set="EXPERT1",rarity="RARE",class="SHAMAN",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Give a minion \"<b>Deathrattle:</b> Resummon this minion.\"",collectible=true}
P["CS2_053"]={id="CS2_053",name="Far Sight",type="SPELL",set="EXPERT1",rarity="EPIC",class="SHAMAN",cost=3,dustHS={400,1600,100,400},text="Draw a card. That card costs (3) less.",collectible=true}
P["EX1_238"]={id="EX1_238",name="Lightning Bolt",type="SPELL",set="EXPERT1",rarity="COMMON",class="SHAMAN",cost=1,overload=1,reqs={REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 3 damage. <b>Overload:</b> (1)",collectible=true}
P["EX1_241"]={id="EX1_241",name="Lava Burst",type="SPELL",set="EXPERT1",rarity="RARE",class="SHAMAN",cost=3,overload=2,reqs={REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Deal 5 damage. <b>Overload:</b> (2)",collectible=true}
P["EX1_243"]={id="EX1_243",name="Dust Devil",type="MINION",set="EXPERT1",rarity="COMMON",class="SHAMAN",cost=1,atk=3,hp=1,overload=2,keywords={"WINDFURY"},dustHS={40,400,5,50},text="<b>Windfury</b>. <b>Overload:</b> (2)",collectible=true}
P["EX1_245"]={id="EX1_245",name="Earth Shock",type="SPELL",set="EXPERT1",rarity="COMMON",class="SHAMAN",cost=1,scriptTags={"SILENCE"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="<b>Silence</b> a minion, then deal 1 damage to it.",collectible=true}
P["EX1_247"]={id="EX1_247",name="Stormforged Axe",type="WEAPON",set="EXPERT1",rarity="COMMON",class="SHAMAN",cost=2,atk=2,dur=3,overload=1,dustHS={40,400,5,50},text="<b>Overload:</b> (1)",collectible=true}
P["EX1_248"]={id="EX1_248",name="Feral Spirit",type="SPELL",set="EXPERT1",rarity="RARE",class="SHAMAN",cost=3,overload=2,reqs={REQ_NUM_MINION_SLOTS=1},dustHS={100,800,20,100},text="Summon two 2/3 Spirit Wolves with <b>Taunt</b>. <b>Overload:</b> (2)",collectible=true}
P["EX1_250"]={id="EX1_250",name="Earth Elemental",type="MINION",set="EXPERT1",rarity="EPIC",class="SHAMAN",cost=5,atk=7,hp=8,overload=3,keywords={"TAUNT"},dustHS={400,1600,100,400},text="<b>Taunt</b>. <b>Overload:</b> (3)",collectible=true}
P["EX1_251"]={id="EX1_251",name="Forked Lightning",type="SPELL",set="EXPERT1",rarity="COMMON",class="SHAMAN",cost=1,overload=2,reqs={REQ_MINIMUM_ENEMY_MINIONS=2},dustHS={40,400,5,50},text="Deal 2 damage to 2 random enemy minions. <b>Overload:</b> (2)",collectible=true}
P["EX1_258"]={id="EX1_258",name="Unbound Elemental",type="MINION",set="EXPERT1",rarity="COMMON",class="SHAMAN",cost=3,atk=2,hp=4,dustHS={40,400,5,50},text="Whenever you play a card with <b>Overload</b>, gain +1/+1.",collectible=true}
P["EX1_259"]={id="EX1_259",name="Lightning Storm",type="SPELL",set="EXPERT1",rarity="RARE",class="SHAMAN",cost=3,overload=2,dustHS={100,800,20,100},text="Deal 2-3 damage to all enemy minions. <b>Overload:</b> (2)",collectible=true}
P["EX1_567"]={id="EX1_567",name="Doomhammer",type="WEAPON",set="EXPERT1",rarity="EPIC",class="SHAMAN",cost=5,atk=2,dur=8,overload=2,keywords={"WINDFURY"},dustHS={400,1600,100,400},text="<b>Windfury, Overload:</b> (2)",collectible=true}
P["EX1_575"]={id="EX1_575",name="Mana Tide Totem",type="MINION",set="EXPERT1",rarity="RARE",class="SHAMAN",cost=3,atk=0,hp=3,race="TOTEM",dustHS={100,800,20,100},text="At the end of your turn, draw a card.",collectible=true}
P["NEW1_010"]={id="NEW1_010",name="Al'Akir the Windlord",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="SHAMAN",cost=8,atk=3,hp=5,keywords={"CHARGE","DIVINE_SHIELD","TAUNT","WINDFURY"},dustHS={1600,3200,400,1600},text="<b>Windfury, Charge, Divine Shield, Taunt</b>",collectible=true}
P["CS2_059"]={id="CS2_059",name="Blood Imp",type="MINION",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=1,atk=0,hp=1,race="DEMON",keywords={"STEALTH"},dustHS={40,400,5,50},text="<b>Stealth</b>. At the end of your turn, give another random friendly minion +1 Health.",collectible=true}
P["EX1_301"]={id="EX1_301",name="Felguard",type="MINION",set="EXPERT1",rarity="RARE",class="WARLOCK",cost=3,atk=3,hp=5,race="DEMON",keywords={"TAUNT"},scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Taunt</b>. <b>Battlecry:</b> Destroy one of your Mana Crystals.",collectible=true}
P["EX1_303"]={id="EX1_303",name="Shadowflame",type="SPELL",set="EXPERT1",rarity="RARE",class="WARLOCK",cost=4,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Destroy a friendly minion and deal its Attack damage to all enemy minions.",collectible=true}
P["EX1_304"]={id="EX1_304",name="Void Terror",type="MINION",set="EXPERT1",rarity="RARE",class="WARLOCK",cost=3,atk=3,hp=3,race="DEMON",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Destroy the minions on either side of this minion and gain their Attack and Health.",collectible=true}
P["EX1_309"]={id="EX1_309",name="Siphon Soul",type="SPELL",set="EXPERT1",rarity="RARE",class="WARLOCK",cost=6,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Destroy a minion. Restore 3 Health to your hero.",collectible=true}
P["EX1_310"]={id="EX1_310",name="Doomguard",type="MINION",set="EXPERT1",rarity="RARE",class="WARLOCK",cost=5,atk=5,hp=7,race="DEMON",keywords={"CHARGE"},scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Charge</b>. <b>Battlecry:</b> Discard two random cards.",collectible=true}
P["EX1_312"]={id="EX1_312",name="Twisting Nether",type="SPELL",set="EXPERT1",rarity="EPIC",class="WARLOCK",cost=8,dustHS={400,1600,100,400},text="Destroy all minions.",collectible=true}
P["EX1_313"]={id="EX1_313",name="Pit Lord",type="MINION",set="EXPERT1",rarity="EPIC",class="WARLOCK",cost=4,atk=5,hp=6,race="DEMON",scriptTags={"BATTLECRY"},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Deal 5 damage to your hero.",collectible=true}
P["EX1_315"]={id="EX1_315",name="Summoning Portal",type="MINION",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=4,atk=0,hp=4,scriptTags={"AURA"},dustHS={40,400,5,50},text="Your minions cost (2) less, but not less than (1).",collectible=true}
P["EX1_316"]={id="EX1_316",name="Power Overwhelming",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=1,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Give a friendly minion +4/+4 until end of turn. Then, it dies. Horribly.",collectible=true}
P["EX1_317"]={id="EX1_317",name="Sense Demons",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=3,dustHS={40,400,5,50},text="Put 2 random Demons from your deck into your hand.",collectible=true}
P["EX1_319"]={id="EX1_319",name="Flame Imp",type="MINION",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=1,atk=3,hp=2,race="DEMON",scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Deal 3 damage to your hero.",collectible=true}
P["EX1_320"]={id="EX1_320",name="Bane of Doom",type="SPELL",set="EXPERT1",rarity="EPIC",class="WARLOCK",cost=5,entourage={"EX1_306","CS2_065","EX1_319","EX1_301","CS2_059","CS2_064"},reqs={REQ_TARGET_TO_PLAY=0},dustHS={400,1600,100,400},text="Deal 2 damage to a character. If that kills it, summon a random Demon.",collectible=true}
P["EX1_323"]={id="EX1_323",name="Lord Jaraxxus",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="WARLOCK",cost=9,atk=3,hp=15,race="DEMON",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Destroy your hero and replace it with Lord Jaraxxus.",collectible=true}
P["EX1_596"]={id="EX1_596",name="Demonfire",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 2 damage to a minion. If it’s a friendly Demon, give it +2/+2 instead.",collectible=true}
P["CS2_104"]={id="CS2_104",name="Rampage",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARRIOR",cost=2,reqs={REQ_DAMAGED_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Give a damaged minion +3/+3.",collectible=true}
P["EX1_391"]={id="EX1_391",name="Slam",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARRIOR",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 2 damage to a minion. If it survives, draw a card.",collectible=true}
P["EX1_392"]={id="EX1_392",name="Battle Rage",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARRIOR",cost=2,reqs={REQ_MINION_TARGET=0},dustHS={40,400,5,50},text="Draw a card for each damaged friendly character.",collectible=true}
P["EX1_398"]={id="EX1_398",name="Arathi Weaponsmith",type="MINION",set="EXPERT1",rarity="COMMON",class="WARRIOR",cost=4,atk=3,hp=3,scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Equip a 2/2 weapon.",collectible=true}
P["EX1_402"]={id="EX1_402",name="Armorsmith",type="MINION",set="EXPERT1",rarity="RARE",class="WARRIOR",cost=2,atk=1,hp=4,dustHS={100,800,20,100},text="Whenever a friendly minion takes damage, gain 1 Armor.",collectible=true}
P["EX1_407"]={id="EX1_407",name="Brawl",type="SPELL",set="EXPERT1",rarity="EPIC",class="WARRIOR",cost=5,reqs={REQ_MINIMUM_TOTAL_MINIONS=2},dustHS={400,1600,100,400},text="Destroy all minions except one. (chosen randomly)",collectible=true}
P["EX1_408"]={id="EX1_408",name="Mortal Strike",type="SPELL",set="EXPERT1",rarity="RARE",class="WARRIOR",cost=4,reqs={REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Deal 4 damage. If you have 12 or less Health, deal 6 instead.",collectible=true}
P["EX1_409"]={id="EX1_409",name="Upgrade!",type="SPELL",set="EXPERT1",rarity="RARE",class="WARRIOR",cost=1,dustHS={100,800,20,100},text="If you have a weapon, give it +1/+1. Otherwise equip a 1/3 weapon.",collectible=true}
P["EX1_410"]={id="EX1_410",name="Shield Slam",type="SPELL",set="EXPERT1",rarity="EPIC",class="WARRIOR",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={400,1600,100,400},text="Deal 1 damage to a minion for each Armor you have.",collectible=true}
P["EX1_411"]={id="EX1_411",name="Gorehowl",type="WEAPON",set="EXPERT1",rarity="EPIC",class="WARRIOR",cost=7,atk=7,dur=1,dustHS={400,1600,100,400},text="Attacking a minion costs 1 Attack instead of 1 Durability.",collectible=true}
P["EX1_414"]={id="EX1_414",name="Grommash Hellscream",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="WARRIOR",cost=8,atk=4,hp=9,keywords={"CHARGE"},scriptTags={"ENRAGED"},dustHS={1600,3200,400,1600},text="<b>Charge</b> <b>Enrage:</b> +6 Attack",collectible=true}
P["EX1_603"]={id="EX1_603",name="Cruel Taskmaster",type="MINION",set="EXPERT1",rarity="COMMON",class="WARRIOR",cost=2,atk=2,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_NONSELF_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Deal 1 damage to a minion and give it +2 Attack.",collectible=true}
P["EX1_604"]={id="EX1_604",name="Frothing Berserker",type="MINION",set="EXPERT1",rarity="RARE",class="WARRIOR",cost=3,atk=2,hp=4,dustHS={100,800,20,100},text="Whenever a minion takes damage, gain +1 Attack.",collectible=true}
P["EX1_607"]={id="EX1_607",name="Inner Rage",type="SPELL",set="EXPERT1",rarity="COMMON",class="WARRIOR",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 1 damage to a minion and give it +2 Attack.",collectible=true}
P["NEW1_036"]={id="NEW1_036",name="Commanding Shout",type="SPELL",set="EXPERT1",rarity="RARE",class="WARRIOR",cost=2,dustHS={100,800,20,100},text="Your minions can't be reduced below 1 Health this turn. Draw a card.",collectible=true}
P["GVG_030"]={id="GVG_030",name="Anodized Robo Cub",type="MINION",set="GVG",rarity="COMMON",class="DRUID",cost=2,atk=2,hp=2,race="MECHANICAL",chooseOne={"GVG_030a","GVG_030b"},keywords={"TAUNT"},dustHS={40,400,5,50},text="<b>Taunt</b>. <b>Choose One -</b> +1 Attack; or +1 Health.",collectible=true}
P["GVG_031"]={id="GVG_031",name="Recycle",type="SPELL",set="GVG",rarity="RARE",class="DRUID",cost=6,reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Shuffle an enemy minion into your opponent's deck.",collectible=true}
P["GVG_032"]={id="GVG_032",name="Grove Tender",type="MINION",set="GVG",rarity="RARE",class="DRUID",cost=3,atk=2,hp=4,chooseOne={"GVG_032a","GVG_032b"},dustHS={100,800,20,100},text="<b>Choose One -</b> Give each player a Mana Crystal; or Each player draws a card.",collectible=true}
P["GVG_033"]={id="GVG_033",name="Tree of Life",type="SPELL",set="GVG",rarity="EPIC",class="DRUID",cost=9,dustHS={400,1600,100,400},text="Restore all characters to full Health.",collectible=true}
P["GVG_034"]={id="GVG_034",name="Mech-Bear-Cat",type="MINION",set="GVG",rarity="RARE",class="DRUID",cost=6,atk=7,hp=6,race="MECHANICAL",entourage={"PART_007","PART_006","PART_005","PART_001","PART_003","PART_002","PART_004"},dustHS={100,800,20,100},text="Whenever this minion takes damage, add a <b>Spare Part</b> card to your hand.",collectible=true}
P["GVG_035"]={id="GVG_035",name="Malorne",type="MINION",set="GVG",rarity="LEGENDARY",class="DRUID",cost=7,atk=9,hp=7,race="BEAST",scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Deathrattle:</b> Shuffle this minion into your deck.",collectible=true}
P["GVG_041"]={id="GVG_041",name="Dark Wispers",type="SPELL",set="GVG",rarity="EPIC",class="DRUID",cost=6,chooseOne={"GVG_041b","GVG_041a"},dustHS={400,1600,100,400},text="<b>Choose One -</b> Summon 5 Wisps; or Give a minion +5/+5 and <b>Taunt</b>.",collectible=true}
P["GVG_080"]={id="GVG_080",name="Druid of the Fang",type="MINION",set="GVG",rarity="COMMON",class="DRUID",cost=5,atk=4,hp=4,scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> If you have a Beast, transform this minion into a 7/7.",collectible=true}
P["GVG_017"]={id="GVG_017",name="Call Pet",type="SPELL",set="GVG",rarity="RARE",class="HUNTER",cost=2,dustHS={100,800,20,100},text="Draw a card. If it's a Beast, it costs (4) less.",collectible=true}
P["GVG_026"]={id="GVG_026",name="Feign Death",type="SPELL",set="GVG",rarity="EPIC",class="HUNTER",cost=2,dustHS={400,1600,100,400},text="Trigger all <b>Deathrattles</b> on your minions.",collectible=true}
P["GVG_043"]={id="GVG_043",name="Glaivezooka",type="WEAPON",set="GVG",rarity="COMMON",class="HUNTER",cost=2,atk=2,dur=2,scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Give a random friendly minion +1 Attack.",collectible=true}
P["GVG_046"]={id="GVG_046",name="King of Beasts",type="MINION",set="GVG",rarity="RARE",class="HUNTER",cost=5,atk=2,hp=6,race="BEAST",keywords={"TAUNT"},scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Taunt</b>. <b>Battlecry:</b> Gain +1 Attack for each other Beast you have.",collectible=true}
P["GVG_048"]={id="GVG_048",name="Metaltooth Leaper",type="MINION",set="GVG",rarity="RARE",class="HUNTER",cost=3,atk=3,hp=3,race="MECHANICAL",scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry</b>: Give your other Mechs +2 Attack.",collectible=true}
P["GVG_049"]={id="GVG_049",name="Gahz'rilla",type="MINION",set="GVG",rarity="LEGENDARY",class="HUNTER",cost=7,atk=6,hp=9,race="BEAST",dustHS={1600,3200,400,1600},text="Whenever this minion takes damage, double its Attack.",collectible=true}
P["GVG_073"]={id="GVG_073",name="Cobra Shot",type="SPELL",set="GVG",rarity="COMMON",class="HUNTER",cost=5,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 3 damage to a minion and the enemy hero.",collectible=true}
P["GVG_087"]={id="GVG_087",name="Steamwheedle Sniper",type="MINION",set="GVG",rarity="EPIC",class="HUNTER",cost=2,atk=2,hp=3,dustHS={400,1600,100,400},text="Your Hero Power can target minions.",collectible=true}
P["GVG_001"]={id="GVG_001",name="Flamecannon",type="SPELL",set="GVG",rarity="COMMON",class="MAGE",cost=2,reqs={REQ_MINIMUM_ENEMY_MINIONS=1},dustHS={40,400,5,50},text="Deal 4 damage to a random enemy minion.",collectible=true}
P["GVG_002"]={id="GVG_002",name="Snowchugger",type="MINION",set="GVG",rarity="COMMON",class="MAGE",cost=2,atk=2,hp=3,race="MECHANICAL",scriptTags={"FREEZE"},dustHS={40,400,5,50},text="<b>Freeze</b> any character damaged by this minion.",collectible=true}
P["GVG_003"]={id="GVG_003",name="Unstable Portal",type="SPELL",set="GVG",rarity="RARE",class="MAGE",cost=2,dustHS={100,800,20,100},text="Add a random minion to your hand. It costs (3) less.",collectible=true}
P["GVG_004"]={id="GVG_004",name="Goblin Blastmage",type="MINION",set="GVG",rarity="RARE",class="MAGE",cost=4,atk=5,hp=4,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> If you have a Mech, deal 4 damage randomly split among all enemies.",collectible=true}
P["GVG_005"]={id="GVG_005",name="Echo of Medivh",type="SPELL",set="GVG",rarity="EPIC",class="MAGE",cost=4,dustHS={400,1600,100,400},text="Put a copy of each friendly minion into your hand.",collectible=true}
P["GVG_007"]={id="GVG_007",name="Flame Leviathan",type="MINION",set="GVG",rarity="LEGENDARY",class="MAGE",cost=7,atk=7,hp=7,race="MECHANICAL",dustHS={1600,3200,400,1600},text="When you draw this, deal 2 damage to all characters.",collectible=true}
P["GVG_122"]={id="GVG_122",name="Wee Spellstopper",type="MINION",set="GVG",rarity="EPIC",class="MAGE",cost=4,atk=2,hp=5,scriptTags={"AURA"},dustHS={400,1600,100,400},text="Adjacent minions can't be targeted by spells or Hero Powers.",collectible=true}
P["GVG_123"]={id="GVG_123",name="Soot Spewer",type="MINION",set="GVG",rarity="RARE",class="MAGE",cost=3,atk=3,hp=3,race="MECHANICAL",spellDamage=1,dustHS={100,800,20,100},text="<b>Spell Damage +1</b>",collectible=true}
P["GVG_006"]={id="GVG_006",name="Mechwarper",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=3,race="MECHANICAL",scriptTags={"AURA"},dustHS={40,400,5,50},text="Your Mechs cost (1) less.",collectible=true}
P["GVG_013"]={id="GVG_013",name="Cogmaster",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=2,scriptTags={"AURA"},dustHS={40,400,5,50},text="Has +2 Attack while you have a Mech.",collectible=true}
P["GVG_016"]={id="GVG_016",name="Fel Reaver",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=5,atk=8,hp=8,race="MECHANICAL",dustHS={400,1600,100,400},text="Whenever your opponent plays a card, discard the top 3 cards of your deck.",collectible=true}
P["GVG_044"]={id="GVG_044",name="Spider Tank",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=4,race="MECHANICAL",dustHS={40,400,5,50},text=nil,collectible=true}
P["GVG_064"]={id="GVG_064",name="Puddlestomper",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=3,hp=2,race="MURLOC",dustHS={40,400,5,50},text=nil,collectible=true}
P["GVG_065"]={id="GVG_065",name="Ogre Brute",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=3,atk=4,hp=4,dustHS={40,400,5,50},text="50% chance to attack the wrong enemy.",collectible=true}
P["GVG_067"]={id="GVG_067",name="Stonesplinter Trogg",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=3,dustHS={40,400,5,50},text="Whenever your opponent casts a spell, gain +1 Attack.",collectible=true}
P["GVG_068"]={id="GVG_068",name="Burly Rockjaw Trogg",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=4,atk=3,hp=5,dustHS={40,400,5,50},text="Whenever your opponent casts a spell, gain +2 Attack.",collectible=true}
P["GVG_069"]={id="GVG_069",name="Antique Healbot",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=5,atk=3,hp=3,race="MECHANICAL",scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> Restore 8 Health to your hero.",collectible=true}
P["GVG_070"]={id="GVG_070",name="Salty Dog",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=5,atk=7,hp=4,race="PIRATE",dustHS={40,400,5,50},text=nil,collectible=true}
P["GVG_071"]={id="GVG_071",name="Lost Tallstrider",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=4,atk=5,hp=4,race="BEAST",dustHS={40,400,5,50},text=nil,collectible=true}
P["GVG_074"]={id="GVG_074",name="Kezan Mystic",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=4,atk=4,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Take control of a random enemy <b>Secret</b>.",collectible=true}
P["GVG_075"]={id="GVG_075",name="Ship's Cannon",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=3,dustHS={40,400,5,50},text="Whenever you summon a Pirate, deal 2 damage to a random enemy.",collectible=true}
P["GVG_076"]={id="GVG_076",name="Explosive Sheep",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=1,race="MECHANICAL",scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Deal 2 damage to all minions.",collectible=true}
P["GVG_078"]={id="GVG_078",name="Mechanical Yeti",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=5,race="MECHANICAL",entourage={"PART_001","PART_003","PART_006","PART_007","PART_004","PART_005","PART_002"},scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Give each player a <b>Spare Part.</b>",collectible=true}
P["GVG_079"]={id="GVG_079",name="Force-Tank MAX",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=8,atk=7,hp=7,race="MECHANICAL",keywords={"DIVINE_SHIELD"},dustHS={40,400,5,50},text="<b>Divine Shield</b>",collectible=true}
P["GVG_081"]={id="GVG_081",name="Gilblin Stalker",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=3,keywords={"STEALTH"},dustHS={40,400,5,50},text="<b>Stealth</b>",collectible=true}
P["GVG_082"]={id="GVG_082",name="Clockwork Gnome",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,race="MECHANICAL",entourage={"PART_003","PART_001","PART_007","PART_006","PART_005","PART_002","PART_004"},scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Add a <b>Spare Part</b> card to your hand.",collectible=true}
P["GVG_084"]={id="GVG_084",name="Flying Machine",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=3,atk=1,hp=4,race="MECHANICAL",keywords={"WINDFURY"},dustHS={40,400,5,50},text="<b>Windfury</b>",collectible=true}
P["GVG_085"]={id="GVG_085",name="Annoy-o-Tron",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=2,race="MECHANICAL",keywords={"DIVINE_SHIELD","TAUNT"},dustHS={40,400,5,50},text="<b>Taunt</b> <b>Divine Shield</b>",collectible=true}
P["GVG_089"]={id="GVG_089",name="Illuminator",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=4,dustHS={100,800,20,100},text="If you control a <b>Secret</b> at the end of your turn, restore 4 health to your hero.",collectible=true}
P["GVG_090"]={id="GVG_090",name="Madder Bomber",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=5,atk=5,hp=4,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Deal 6 damage randomly split between all other characters.",collectible=true}
P["GVG_091"]={id="GVG_091",name="Arcane Nullifier X-21",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=4,atk=2,hp=5,race="MECHANICAL",keywords={"CANT_BE_TARGETED_BY_HERO_POWERS","CANT_BE_TARGETED_BY_SPELLS","TAUNT"},dustHS={100,800,20,100},text="<b>Taunt</b> Can't be targeted by spells or Hero Powers.",collectible=true}
P["GVG_092"]={id="GVG_092",name="Gnomish Experimenter",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=3,atk=3,hp=2,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Draw a card. If it's a minion, transform it into a Chicken.",collectible=true}
P["GVG_093"]={id="GVG_093",name="Target Dummy",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=0,atk=0,hp=2,race="MECHANICAL",keywords={"TAUNT"},dustHS={100,800,20,100},text="<b>Taunt</b>",collectible=true}
P["GVG_094"]={id="GVG_094",name="Jeeves",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=4,atk=1,hp=4,race="MECHANICAL",dustHS={100,800,20,100},text="At the end of each player's turn, that player draws until they have 3 cards.",collectible=true}
P["GVG_095"]={id="GVG_095",name="Goblin Sapper",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=4,scriptTags={"AURA"},dustHS={100,800,20,100},text="Has +4 Attack while your opponent has 6 or more cards in hand.",collectible=true}
P["GVG_096"]={id="GVG_096",name="Piloted Shredder",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=3,race="MECHANICAL",scriptTags={"DEATHRATTLE"},dustHS={40,400,5,50},text="<b>Deathrattle:</b> Summon a random 2-Cost minion.",collectible=true}
P["GVG_097"]={id="GVG_097",name="Lil' Exorcist",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=3,keywords={"TAUNT"},scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Taunt</b> <b>Battlecry:</b> Gain +1/+1 for each enemy <b>Deathrattle</b> minion.",collectible=true}
P["GVG_098"]={id="GVG_098",name="Gnomeregan Infantry",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=3,atk=1,hp=4,keywords={"CHARGE","TAUNT"},dustHS={40,400,5,50},text="<b>Charge</b> <b>Taunt</b>",collectible=true}
P["GVG_099"]={id="GVG_099",name="Bomb Lobber",type="MINION",set="GVG",rarity="RARE",class="NEUTRAL",cost=5,atk=3,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Deal 4 damage to a random enemy minion.",collectible=true}
P["GVG_102"]={id="GVG_102",name="Tinkertown Technician",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=3,atk=3,hp=3,entourage={"PART_007","PART_006","PART_003","PART_001","PART_004","PART_002","PART_005"},scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry:</b> If you have a Mech, gain +1/+1 and add a <b>Spare Part</b> to your hand.",collectible=true}
P["GVG_103"]={id="GVG_103",name="Micro Machine",type="MINION",set="GVG",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=2,race="MECHANICAL",dustHS={40,400,5,50},text="At the start of each turn, gain +1 Attack.",collectible=true}
P["GVG_104"]={id="GVG_104",name="Hobgoblin",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=3,atk=2,hp=3,dustHS={400,1600,100,400},text="Whenever you play a 1-Attack minion, give it +2/+2.",collectible=true}
P["GVG_105"]={id="GVG_105",name="Piloted Sky Golem",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=6,atk=6,hp=4,race="MECHANICAL",scriptTags={"DEATHRATTLE"},dustHS={400,1600,100,400},text="<b>Deathrattle:</b> Summon a random 4-Cost minion.",collectible=true}
P["GVG_106"]={id="GVG_106",name="Junkbot",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=5,atk=1,hp=5,race="MECHANICAL",dustHS={400,1600,100,400},text="Whenever a friendly Mech dies, gain +2/+2.",collectible=true}
P["GVG_107"]={id="GVG_107",name="Enhance-o Mechano",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=4,atk=3,hp=2,race="MECHANICAL",scriptTags={"BATTLECRY"},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Give your other minions <b>Windfury</b>, <b>Taunt</b>, or <b>Divine Shield</b>. (at random)",collectible=true}
P["GVG_108"]={id="GVG_108",name="Recombobulator",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=2,atk=3,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Transform a friendly minion into a random minion with the same Cost.",collectible=true}
P["GVG_109"]={id="GVG_109",name="Mini-Mage",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=4,atk=4,hp=1,spellDamage=1,keywords={"STEALTH"},dustHS={400,1600,100,400},text="<b>Stealth</b> <b>Spell Damage +1</b>",collectible=true}
P["GVG_110"]={id="GVG_110",name="Dr. Boom",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=7,atk=7,hp=7,scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry</b>: Summon two 1/1 Boom Bots. WARNING: Bots may explode.",collectible=true}
P["GVG_111"]={id="GVG_111",name="Mimiron's Head",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=4,hp=5,race="MECHANICAL",dustHS={1600,3200,400,1600},text="At the start of your turn, if you have at least 3 Mechs, destroy them all and form V-07-TR-0N.",collectible=true}
P["GVG_112"]={id="GVG_112",name="Mogor the Ogre",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=7,hp=6,dustHS={1600,3200,400,1600},text="All minions have a 50% chance to attack the wrong enemy.",collectible=true}
P["GVG_113"]={id="GVG_113",name="Foe Reaper 4000",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=8,atk=6,hp=9,race="MECHANICAL",dustHS={1600,3200,400,1600},text="Also damages the minions next to whomever he attacks.",collectible=true}
P["GVG_114"]={id="GVG_114",name="Sneed's Old Shredder",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=8,atk=5,hp=7,race="MECHANICAL",scriptTags={"DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Deathrattle:</b> Summon a random legendary minion.",collectible=true}
P["GVG_115"]={id="GVG_115",name="Toshley",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=5,hp=7,entourage={"PART_003","PART_006","PART_007","PART_001","PART_004","PART_005","PART_002"},scriptTags={"BATTLECRY","DEATHRATTLE"},dustHS={1600,3200,400,1600},text="<b>Battlecry and Deathrattle:</b> Add a <b>Spare Part</b> card to your hand.",collectible=true}
P["GVG_116"]={id="GVG_116",name="Mekgineer Thermaplugg",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=9,hp=7,race="MECHANICAL",dustHS={1600,3200,400,1600},text="Whenever an enemy minion dies, summon a Leper Gnome.",collectible=true}
P["GVG_117"]={id="GVG_117",name="Gazlowe",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=3,hp=6,dustHS={1600,3200,400,1600},text="Whenever you cast a 1-mana spell, add a random Mech to your hand.",collectible=true}
P["GVG_118"]={id="GVG_118",name="Troggzor the Earthinator",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=7,atk=6,hp=6,dustHS={1600,3200,400,1600},text="Whenever your opponent casts a spell, summon a Burly Rockjaw Trogg.",collectible=true}
P["GVG_119"]={id="GVG_119",name="Blingtron 3000",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=3,hp=4,race="MECHANICAL",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Equip a random weapon for each player.",collectible=true}
P["GVG_120"]={id="GVG_120",name="Hemet Nesingwary",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=6,hp=3,scriptTags={"BATTLECRY"},reqs={REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_WITH_RACE=20},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Destroy a Beast.",collectible=true}
P["GVG_121"]={id="GVG_121",name="Clockwork Giant",type="MINION",set="GVG",rarity="EPIC",class="NEUTRAL",cost=12,atk=8,hp=8,race="MECHANICAL",dustHS={400,1600,100,400},text="Costs (1) less for each card in your opponent's hand.",collectible=true}
P["GVG_057"]={id="GVG_057",name="Seal of Light",type="SPELL",set="GVG",rarity="COMMON",class="PALADIN",cost=2,keywords={"ImmuneToSpellpower"},dustHS={40,400,5,50},text="Restore 4 Health to your hero and gain +2 Attack this turn.",collectible=true}
P["GVG_058"]={id="GVG_058",name="Shielded Minibot",type="MINION",set="GVG",rarity="COMMON",class="PALADIN",cost=2,atk=2,hp=2,race="MECHANICAL",keywords={"DIVINE_SHIELD"},dustHS={40,400,5,50},text="<b>Divine Shield</b>",collectible=true}
P["GVG_059"]={id="GVG_059",name="Coghammer",type="WEAPON",set="GVG",rarity="EPIC",class="PALADIN",cost=3,atk=2,dur=3,scriptTags={"BATTLECRY"},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Give a random friendly minion <b>Divine Shield</b> and <b>Taunt</b>.",collectible=true}
P["GVG_060"]={id="GVG_060",name="Quartermaster",type="MINION",set="GVG",rarity="EPIC",class="PALADIN",cost=5,atk=2,hp=5,scriptTags={"BATTLECRY"},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Give your Silver Hand Recruits +2/+2.",collectible=true}
P["GVG_061"]={id="GVG_061",name="Muster for Battle",type="SPELL",set="GVG",rarity="RARE",class="PALADIN",cost=3,dustHS={100,800,20,100},text="Summon three 1/1 Silver Hand Recruits. Equip a 1/4 Weapon.",collectible=true}
P["GVG_062"]={id="GVG_062",name="Cobalt Guardian",type="MINION",set="GVG",rarity="RARE",class="PALADIN",cost=5,atk=6,hp=3,race="MECHANICAL",dustHS={100,800,20,100},text="Whenever you summon a Mech, gain <b>Divine Shield</b>.",collectible=true}
P["GVG_063"]={id="GVG_063",name="Bolvar Fordragon",type="MINION",set="GVG",rarity="LEGENDARY",class="PALADIN",cost=5,atk=1,hp=7,dustHS={1600,3200,400,1600},text="Whenever a friendly minion dies while this is in your hand, gain +1 Attack.",collectible=true}
P["GVG_101"]={id="GVG_101",name="Scarlet Purifier",type="MINION",set="GVG",rarity="RARE",class="PALADIN",cost=3,atk=4,hp=3,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry</b>: Deal 2 damage to all minions with <b>Deathrattle</b>.",collectible=true}
P["GVG_008"]={id="GVG_008",name="Lightbomb",type="SPELL",set="GVG",rarity="EPIC",class="PRIEST",cost=6,dustHS={400,1600,100,400},text="Deal damage to each minion equal to its Attack.",collectible=true}
P["GVG_009"]={id="GVG_009",name="Shadowbomber",type="MINION",set="GVG",rarity="EPIC",class="PRIEST",cost=1,atk=2,hp=1,scriptTags={"BATTLECRY"},dustHS={400,1600,100,400},text="<b>Battlecry:</b> Deal 3 damage to each hero.",collectible=true}
P["GVG_010"]={id="GVG_010",name="Velen's Chosen",type="SPELL",set="GVG",rarity="COMMON",class="PRIEST",cost=3,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Give a minion +2/+4 and <b>Spell Damage +1</b>.",collectible=true}
P["GVG_011"]={id="GVG_011",name="Shrinkmeister",type="MINION",set="GVG",rarity="COMMON",class="PRIEST",cost=2,atk=3,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={40,400,5,50},text="<b>Battlecry:</b> Give a minion -2 Attack this turn.",collectible=true}
P["GVG_012"]={id="GVG_012",name="Light of the Naaru",type="SPELL",set="GVG",rarity="RARE",class="PRIEST",cost=1,reqs={REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Restore 3 Health. If the target is still damaged, summon a Lightwarden.",collectible=true}
P["GVG_014"]={id="GVG_014",name="Vol'jin",type="MINION",set="GVG",rarity="LEGENDARY",class="PRIEST",cost=5,atk=6,hp=2,scriptTags={"BATTLECRY"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Swap Health with another minion.",collectible=true}
P["GVG_072"]={id="GVG_072",name="Shadowboxer",type="MINION",set="GVG",rarity="RARE",class="PRIEST",cost=2,atk=2,hp=3,race="MECHANICAL",dustHS={100,800,20,100},text="Whenever a character is healed, deal 1 damage to a random enemy.",collectible=true}
P["GVG_083"]={id="GVG_083",name="Upgraded Repair Bot",type="MINION",set="GVG",rarity="RARE",class="PRIEST",cost=5,atk=5,hp=5,race="MECHANICAL",scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_WITH_RACE=17},dustHS={100,800,20,100},text="<b>Battlecry:</b> Give a friendly Mech +4 Health.",collectible=true}
P["GVG_022"]={id="GVG_022",name="Tinker's Sharpsword Oil",type="SPELL",set="GVG",rarity="COMMON",class="ROGUE",cost=4,scriptTags={"COMBO"},reqs={REQ_MINION_TARGET=0},dustHS={40,400,5,50},text="Give your weapon +3 Attack. <b>Combo:</b> Give a random friendly minion +3 Attack.",collectible=true}
P["GVG_023"]={id="GVG_023",name="Goblin Auto-Barber",type="MINION",set="GVG",rarity="COMMON",class="ROGUE",cost=2,atk=3,hp=2,race="MECHANICAL",scriptTags={"BATTLECRY"},dustHS={40,400,5,50},text="<b>Battlecry</b>: Give your weapon +1 Attack.",collectible=true}
P["GVG_024"]={id="GVG_024",name="Cogmaster's Wrench",type="WEAPON",set="GVG",rarity="EPIC",class="ROGUE",cost=3,atk=1,dur=3,scriptTags={"AURA"},dustHS={400,1600,100,400},text="Has +2 Attack while you have a Mech.",collectible=true}
P["GVG_025"]={id="GVG_025",name="One-eyed Cheat",type="MINION",set="GVG",rarity="RARE",class="ROGUE",cost=2,atk=4,hp=1,race="PIRATE",dustHS={100,800,20,100},text="Whenever you summon a Pirate, gain <b>Stealth</b>.",collectible=true}
P["GVG_027"]={id="GVG_027",name="Iron Sensei",type="MINION",set="GVG",rarity="RARE",class="ROGUE",cost=3,atk=2,hp=2,race="MECHANICAL",dustHS={100,800,20,100},text="At the end of your turn, give another friendly Mech +2/+2.",collectible=true}
P["GVG_028"]={id="GVG_028",name="Trade Prince Gallywix",type="MINION",set="GVG",rarity="LEGENDARY",class="ROGUE",cost=6,atk=5,hp=8,dustHS={1600,3200,400,1600},text="Whenever your opponent casts a spell, gain a copy of it and give them a Coin.",collectible=true}
P["GVG_047"]={id="GVG_047",name="Sabotage",type="SPELL",set="GVG",rarity="EPIC",class="ROGUE",cost=4,scriptTags={"COMBO"},reqs={REQ_ENEMY_TARGET=0,REQ_MINION_TARGET=0},dustHS={400,1600,100,400},text="Destroy a random enemy minion. <b>Combo</b>: And your opponent's weapon.",collectible=true}
P["GVG_088"]={id="GVG_088",name="Ogre Ninja",type="MINION",set="GVG",rarity="RARE",class="ROGUE",cost=5,atk=6,hp=6,keywords={"STEALTH"},dustHS={100,800,20,100},text="<b>Stealth</b> 50% chance to attack the wrong enemy.",collectible=true}
P["GVG_029"]={id="GVG_029",name="Ancestor's Call",type="SPELL",set="GVG",rarity="EPIC",class="SHAMAN",cost=4,dustHS={400,1600,100,400},text="Put a random minion from each player's hand into the battlefield.",collectible=true}
P["GVG_036"]={id="GVG_036",name="Powermace",type="WEAPON",set="GVG",rarity="RARE",class="SHAMAN",cost=3,atk=3,dur=2,scriptTags={"DEATHRATTLE"},dustHS={100,800,20,100},text="<b>Deathrattle</b>: Give a random friendly Mech +2/+2.",collectible=true}
P["GVG_037"]={id="GVG_037",name="Whirling Zap-o-matic",type="MINION",set="GVG",rarity="COMMON",class="SHAMAN",cost=2,atk=3,hp=2,race="MECHANICAL",keywords={"WINDFURY"},dustHS={40,400,5,50},text="<b>Windfury</b>",collectible=true}
P["GVG_038"]={id="GVG_038",name="Crackle",type="SPELL",set="GVG",rarity="COMMON",class="SHAMAN",cost=2,overload=1,reqs={REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 3-6 damage. <b>Overload: (1)</b>",collectible=true}
P["GVG_039"]={id="GVG_039",name="Vitality Totem",type="MINION",set="GVG",rarity="RARE",class="SHAMAN",cost=2,atk=0,hp=3,race="TOTEM",dustHS={100,800,20,100},text="At the end of your turn, restore 4 Health to your hero.",collectible=true}
P["GVG_040"]={id="GVG_040",name="Siltfin Spiritwalker",type="MINION",set="GVG",rarity="EPIC",class="SHAMAN",cost=4,atk=2,hp=5,race="MURLOC",overload=1,dustHS={400,1600,100,400},text="Whenever another friendly Murloc dies, draw a card. <b>Overload</b>: (1)",collectible=true}
P["GVG_042"]={id="GVG_042",name="Neptulon",type="MINION",set="GVG",rarity="LEGENDARY",class="SHAMAN",cost=7,atk=7,hp=7,overload=3,scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Add 4 random Murlocs to your hand. <b>Overload: (3)</b>",collectible=true}
P["GVG_066"]={id="GVG_066",name="Dunemaul Shaman",type="MINION",set="GVG",rarity="RARE",class="SHAMAN",cost=4,atk=5,hp=4,overload=1,keywords={"FORGETFUL","WINDFURY"},dustHS={100,800,20,100},text="<b>Windfury, Overload: (1)</b> 50% chance to attack the wrong enemy.",collectible=true}
P["GVG_015"]={id="GVG_015",name="Darkbomb",type="SPELL",set="GVG",rarity="COMMON",class="WARLOCK",cost=2,reqs={REQ_TARGET_TO_PLAY=0},dustHS={40,400,5,50},text="Deal 3 damage.",collectible=true}
P["GVG_018"]={id="GVG_018",name="Mistress of Pain",type="MINION",set="GVG",rarity="RARE",class="WARLOCK",cost=2,atk=1,hp=4,race="DEMON",dustHS={100,800,20,100},text="Whenever this minion deals damage, restore that much Health to your hero.",collectible=true}
P["GVG_019"]={id="GVG_019",name="Demonheart",type="SPELL",set="GVG",rarity="EPIC",class="WARLOCK",cost=5,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={400,1600,100,400},text="Deal 5 damage to a minion. If it's a friendly Demon, give it +5/+5 instead.",collectible=true}
P["GVG_020"]={id="GVG_020",name="Fel Cannon",type="MINION",set="GVG",rarity="RARE",class="WARLOCK",cost=4,atk=3,hp=5,race="MECHANICAL",dustHS={100,800,20,100},text="At the end of your turn, deal 2 damage to a non-Mech minion.",collectible=true}
P["GVG_021"]={id="GVG_021",name="Mal'Ganis",type="MINION",set="GVG",rarity="LEGENDARY",class="WARLOCK",cost=9,atk=9,hp=7,race="DEMON",scriptTags={"AURA"},dustHS={1600,3200,400,1600},text="Your other Demons have +2/+2. Your hero is <b>Immune</b>.",collectible=true}
P["GVG_045"]={id="GVG_045",name="Imp-losion",type="SPELL",set="GVG",rarity="RARE",class="WARLOCK",cost=4,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={100,800,20,100},text="Deal 2-4 damage to a minion. Summon a 1/1 Imp for each damage dealt.",collectible=true}
P["GVG_077"]={id="GVG_077",name="Anima Golem",type="MINION",set="GVG",rarity="EPIC",class="WARLOCK",cost=6,atk=9,hp=9,race="MECHANICAL",dustHS={400,1600,100,400},text="At the end of each turn, destroy this minion if it's your only one.",collectible=true}
P["GVG_100"]={id="GVG_100",name="Floating Watcher",type="MINION",set="GVG",rarity="COMMON",class="WARLOCK",cost=5,atk=4,hp=4,race="DEMON",dustHS={40,400,5,50},text="Whenever your hero takes damage on your turn, gain +2/+2.",collectible=true}
P["GVG_050"]={id="GVG_050",name="Bouncing Blade",type="SPELL",set="GVG",rarity="EPIC",class="WARRIOR",cost=3,reqs={REQ_MINIMUM_TOTAL_MINIONS=1},dustHS={400,1600,100,400},text="Deal 1 damage to a random minion. Repeat until a minion dies.",collectible=true}
P["GVG_051"]={id="GVG_051",name="Warbot",type="MINION",set="GVG",rarity="COMMON",class="WARRIOR",cost=1,atk=1,hp=3,race="MECHANICAL",scriptTags={"ENRAGED"},dustHS={40,400,5,50},text="<b>Enrage:</b> +1 Attack.",collectible=true}
P["GVG_052"]={id="GVG_052",name="Crush",type="SPELL",set="GVG",rarity="EPIC",class="WARRIOR",cost=7,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},dustHS={400,1600,100,400},text="Destroy a minion. If you have a damaged minion, this costs (4) less.",collectible=true}
P["GVG_053"]={id="GVG_053",name="Shieldmaiden",type="MINION",set="GVG",rarity="RARE",class="WARRIOR",cost=6,atk=5,hp=5,scriptTags={"BATTLECRY"},dustHS={100,800,20,100},text="<b>Battlecry:</b> Gain 5 Armor.",collectible=true}
P["GVG_054"]={id="GVG_054",name="Ogre Warmaul",type="WEAPON",set="GVG",rarity="COMMON",class="WARRIOR",cost=3,atk=4,dur=2,dustHS={40,400,5,50},text="50% chance to attack the wrong enemy.",collectible=true}
P["GVG_055"]={id="GVG_055",name="Screwjank Clunker",type="MINION",set="GVG",rarity="RARE",class="WARRIOR",cost=4,atk=2,hp=5,race="MECHANICAL",scriptTags={"BATTLECRY"},reqs={REQ_FRIENDLY_TARGET=0,REQ_TARGET_IF_AVAILABLE=0,REQ_TARGET_WITH_RACE=17},dustHS={100,800,20,100},text="<b>Battlecry</b>: Give a friendly Mech +2/+2.",collectible=true}
P["GVG_056"]={id="GVG_056",name="Iron Juggernaut",type="MINION",set="GVG",rarity="LEGENDARY",class="WARRIOR",cost=6,atk=6,hp=5,race="MECHANICAL",scriptTags={"BATTLECRY"},dustHS={1600,3200,400,1600},text="<b>Battlecry:</b> Shuffle a Mine into your opponent's deck. When drawn, it explodes for 10 damage.",collectible=true}
P["GVG_086"]={id="GVG_086",name="Siege Engine",type="MINION",set="GVG",rarity="RARE",class="WARRIOR",cost=5,atk=5,hp=5,race="MECHANICAL",dustHS={100,800,20,100},text="Whenever you gain Armor, give this minion +1 Attack.",collectible=true}
P["FP1_019"]={id="FP1_019",name="Poison Seeds",type="SPELL",set="NAXX",rarity="COMMON",class="DRUID",cost=4,text="Destroy all minions and summon 2/2 Treants to replace them.",collectible=true}
P["FP1_011"]={id="FP1_011",name="Webspinner",type="MINION",set="NAXX",rarity="COMMON",class="HUNTER",cost=1,atk=1,hp=1,race="BEAST",scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Add a random Beast card to your hand.",collectible=true}
P["FP1_018"]={id="FP1_018",name="Duplicate",type="SPELL",set="NAXX",rarity="COMMON",class="MAGE",cost=3,scriptTags={"SECRET"},text="<b>Secret:</b> When a friendly minion dies, put 2 copies of it into your hand.",collectible=true}
P["FP1_001"]={id="FP1_001",name="Zombie Chow",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=3,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Restore 5 Health to the enemy hero.",collectible=true}
P["FP1_002"]={id="FP1_002",name="Haunted Creeper",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=2,race="BEAST",scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Summon two 1/1 Spectral Spiders.",collectible=true}
P["FP1_003"]={id="FP1_003",name="Echoing Ooze",type="MINION",set="NAXX",rarity="EPIC",class="NEUTRAL",cost=2,atk=1,hp=2,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Summon an exact copy of this minion at the end of the turn.",collectible=true}
P["FP1_004"]={id="FP1_004",name="Mad Scientist",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=2,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Put a <b>Secret</b> from your deck into the battlefield.",collectible=true}
P["FP1_005"]={id="FP1_005",name="Shade of Naxxramas",type="MINION",set="NAXX",rarity="EPIC",class="NEUTRAL",cost=3,atk=2,hp=2,keywords={"STEALTH"},text="<b>Stealth.</b> At the start of your turn, gain +1/+1.",collectible=true}
P["FP1_007"]={id="FP1_007",name="Nerubian Egg",type="MINION",set="NAXX",rarity="RARE",class="NEUTRAL",cost=2,atk=0,hp=2,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Summon a 4/4 Nerubian.",collectible=true}
P["FP1_008"]={id="FP1_008",name="Spectral Knight",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=5,atk=4,hp=6,keywords={"CANT_BE_TARGETED_BY_HERO_POWERS","CANT_BE_TARGETED_BY_SPELLS"},text="Can't be targeted by spells or Hero Powers.",collectible=true}
P["FP1_009"]={id="FP1_009",name="Deathlord",type="MINION",set="NAXX",rarity="RARE",class="NEUTRAL",cost=3,atk=2,hp=8,keywords={"TAUNT"},scriptTags={"DEATHRATTLE"},text="<b>Taunt. Deathrattle:</b> Your opponent puts a minion from their deck into the battlefield.",collectible=true}
P["FP1_010"]={id="FP1_010",name="Maexxna",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=2,hp=8,race="BEAST",keywords={"POISONOUS"},text="Destroy any minion damaged by this minion.",collectible=true}
P["FP1_012"]={id="FP1_012",name="Sludge Belcher",type="MINION",set="NAXX",rarity="RARE",class="NEUTRAL",cost=5,atk=3,hp=5,keywords={"TAUNT"},scriptTags={"DEATHRATTLE"},text="<b>Taunt. Deathrattle:</b> Summon a 1/2 Slime with <b>Taunt</b>.",collectible=true}
P["FP1_013"]={id="FP1_013",name="Kel'Thuzad",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=8,atk=6,hp=8,text="At the end of each turn, summon all friendly minions that died this turn.",collectible=true}
P["FP1_014"]={id="FP1_014",name="Stalagg",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=7,hp=4,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> If Feugen also died this game, summon Thaddius.",collectible=true}
P["FP1_015"]={id="FP1_015",name="Feugen",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=4,hp=7,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> If Stalagg also died this game, summon Thaddius.",collectible=true}
P["FP1_016"]={id="FP1_016",name="Wailing Soul",type="MINION",set="NAXX",rarity="RARE",class="NEUTRAL",cost=4,atk=3,hp=5,scriptTags={"BATTLECRY"},text="<b>Battlecry: Silence</b> your other minions.",collectible=true}
P["FP1_017"]={id="FP1_017",name="Nerub'ar Weblord",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=4,scriptTags={"AURA"},text="Minions with <b>Battlecry</b> cost (2) more.",collectible=true}
P["FP1_024"]={id="FP1_024",name="Unstable Ghoul",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=3,keywords={"TAUNT"},scriptTags={"DEATHRATTLE"},text="<b>Taunt</b>. <b>Deathrattle:</b> Deal 1 damage to all minions.",collectible=true}
P["FP1_027"]={id="FP1_027",name="Stoneskin Gargoyle",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=3,atk=1,hp=4,text="At the start of your turn, restore this minion to full Health.",collectible=true}
P["FP1_028"]={id="FP1_028",name="Undertaker",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=2,text="Whenever you summon a minion with <b>Deathrattle</b>, gain +1/+1.",collectible=true}
P["FP1_029"]={id="FP1_029",name="Dancing Swords",type="MINION",set="NAXX",rarity="COMMON",class="NEUTRAL",cost=3,atk=4,hp=4,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Your opponent draws a card.",collectible=true}
P["FP1_030"]={id="FP1_030",name="Loatheb",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=5,hp=5,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Enemy spells cost (5) more next turn.",collectible=true}
P["FP1_031"]={id="FP1_031",name="Baron Rivendare",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=4,atk=1,hp=7,scriptTags={"AURA"},text="Your minions trigger their <b>Deathrattles</b> twice.",collectible=true}
P["FP1_020"]={id="FP1_020",name="Avenge",type="SPELL",set="NAXX",rarity="COMMON",class="PALADIN",cost=1,scriptTags={"SECRET"},text="<b>Secret:</b> When one of your minions dies, give a random friendly minion +3/+2.",collectible=true}
P["FP1_023"]={id="FP1_023",name="Dark Cultist",type="MINION",set="NAXX",rarity="COMMON",class="PRIEST",cost=3,atk=3,hp=4,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Give a random friendly minion +3 Health.",collectible=true}
P["FP1_026"]={id="FP1_026",name="Anub'ar Ambusher",type="MINION",set="NAXX",rarity="COMMON",class="ROGUE",cost=4,atk=5,hp=5,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Return a random friendly minion to your hand.",collectible=true}
P["FP1_025"]={id="FP1_025",name="Reincarnate",type="SPELL",set="NAXX",rarity="COMMON",class="SHAMAN",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy a minion, then return it to life with full Health.",collectible=true}
P["FP1_022"]={id="FP1_022",name="Voidcaller",type="MINION",set="NAXX",rarity="COMMON",class="WARLOCK",cost=4,atk=3,hp=4,race="DEMON",scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Put a random Demon from your hand into the battlefield.",collectible=true}
P["FP1_021"]={id="FP1_021",name="Death's Bite",type="WEAPON",set="NAXX",rarity="COMMON",class="WARRIOR",cost=4,atk=4,dur=2,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Deal 1 damage to all minions.",collectible=true}
P["EX1_112"]={id="EX1_112",name="Gelbin Mekkatorque",type="MINION",set="PROMO",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=6,hp=6,entourage={"Mekka1","Mekka2","Mekka3","Mekka4"},scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Summon an AWESOME invention.",collectible=true,unobtainable=true}
P["PRO_001"]={id="PRO_001",name="Elite Tauren Chieftain",type="MINION",set="PROMO",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=5,hp=5,entourage={"PRO_001a","PRO_001b","PRO_001c"},scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Give both players the power to ROCK! (with a Power Chord card)",collectible=true,unobtainable=true}
P["EX1_062"]={id="EX1_062",name="Old Murk-Eye",type="MINION",set="REWARD",rarity="LEGENDARY",class="NEUTRAL",cost=4,atk=2,hp=4,race="MURLOC",keywords={"CHARGE"},text="<b>Charge</b>. Has +1 Attack for each other Murloc on the battlefield.",collectible=true,unobtainable=true}
P["NEW1_016"]={id="NEW1_016",name="Captain's Parrot",type="MINION",set="REWARD",rarity="EPIC",class="NEUTRAL",cost=2,atk=1,hp=1,race="BEAST",scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Put a random Pirate from your deck into your hand.",collectible=true,unobtainable=true}

-- === HERO PORTRAITS (48) ===
P["EX1_323h"]={id="EX1_323h",name="Lord Jaraxxus",type="HERO",set="EXPERT1",rarity="LEGENDARY",class="WARLOCK",hp=15,race="DEMON",text=nil}
P["HERO_01"]={id="HERO_01",name="Garrosh Hellscream",type="HERO",set="CORE",rarity="FREE",class="WARRIOR",hp=30,text=nil,collectible=true}
P["HERO_02"]={id="HERO_02",name="Thrall",type="HERO",set="CORE",rarity="FREE",class="SHAMAN",hp=30,text=nil,collectible=true}
P["HERO_03"]={id="HERO_03",name="Valeera Sanguinar",type="HERO",set="CORE",rarity="FREE",class="ROGUE",hp=30,text=nil,collectible=true}
P["HERO_04"]={id="HERO_04",name="Uther Lightbringer",type="HERO",set="CORE",rarity="FREE",class="PALADIN",hp=30,text=nil,collectible=true}
P["HERO_05"]={id="HERO_05",name="Rexxar",type="HERO",set="CORE",rarity="FREE",class="HUNTER",hp=30,text=nil,collectible=true}
P["HERO_06"]={id="HERO_06",name="Malfurion Stormrage",type="HERO",set="CORE",rarity="FREE",class="DRUID",hp=30,text=nil,collectible=true}
P["HERO_07"]={id="HERO_07",name="Gul'dan",type="HERO",set="CORE",rarity="FREE",class="WARLOCK",hp=30,text=nil,collectible=true}
P["HERO_08"]={id="HERO_08",name="Jaina Proudmoore",type="HERO",set="CORE",rarity="FREE",class="MAGE",hp=30,text=nil,collectible=true}
P["HERO_09"]={id="HERO_09",name="Anduin Wrynn",type="HERO",set="CORE",rarity="FREE",class="PRIEST",hp=30,text=nil,collectible=true}
P["NAX10_01"]={id="NAX10_01",name="Patchwerk",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX10_01H"]={id="NAX10_01H",name="Patchwerk",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX11_01"]={id="NAX11_01",name="Grobbulus",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX11_01H"]={id="NAX11_01H",name="Grobbulus",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX12_01"]={id="NAX12_01",name="Gluth",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX12_01H"]={id="NAX12_01H",name="Gluth",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX13_01"]={id="NAX13_01",name="Thaddius",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX13_01H"]={id="NAX13_01H",name="Thaddius",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX14_01"]={id="NAX14_01",name="Sapphiron",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX14_01H"]={id="NAX14_01H",name="Sapphiron",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX15_01"]={id="NAX15_01",name="Kel'Thuzad",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX15_01H"]={id="NAX15_01H",name="Kel'Thuzad",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX1_01"]={id="NAX1_01",name="Anub'Rekhan",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,reqs={REQ_NUM_MINION_SLOTS=1},text=nil}
P["NAX1h_01"]={id="NAX1h_01",name="Anub'Rekhan",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,reqs={REQ_NUM_MINION_SLOTS=1},text=nil}
P["NAX2_01"]={id="NAX2_01",name="Grand Widow Faerlina",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX2_01H"]={id="NAX2_01H",name="Grand Widow Faerlina",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX3_01"]={id="NAX3_01",name="Maexxna",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX3_01H"]={id="NAX3_01H",name="Maexxna",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX4_01"]={id="NAX4_01",name="Noth the Plaguebringer",type="HERO",set="NAXX",rarity="FREE",class="MAGE",hp=30,text=nil}
P["NAX4_01H"]={id="NAX4_01H",name="Noth the Plaguebringer",type="HERO",set="NAXX",rarity="FREE",class="MAGE",hp=45,text=nil}
P["NAX5_01"]={id="NAX5_01",name="Heigan the Unclean",type="HERO",set="NAXX",rarity="FREE",class="WARLOCK",hp=30,text=nil}
P["NAX5_01H"]={id="NAX5_01H",name="Heigan the Unclean",type="HERO",set="NAXX",rarity="FREE",class="WARLOCK",hp=45,text=nil}
P["NAX6_01"]={id="NAX6_01",name="Loatheb",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=75,text=nil}
P["NAX6_01H"]={id="NAX6_01H",name="Loatheb",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=99,text=nil}
P["NAX7_01"]={id="NAX7_01",name="Instructor Razuvious",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=40,text=nil}
P["NAX7_01H"]={id="NAX7_01H",name="Instructor Razuvious",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=55,text=nil}
P["NAX8_01"]={id="NAX8_01",name="Gothik the Harvester",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=30,text=nil}
P["NAX8_01H"]={id="NAX8_01H",name="Gothik the Harvester",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=45,text=nil}
P["NAX9_01"]={id="NAX9_01",name="Baron Rivendare",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=7,text=nil}
P["NAX9_01H"]={id="NAX9_01H",name="Baron Rivendare",type="HERO",set="NAXX",rarity="FREE",class="NEUTRAL",hp=14,text=nil}
P["TU4a_001"]={id="TU4a_001",name="Hogger",type="HERO",set="MISSIONS",rarity="COMMON",class="NEUTRAL",hp=10,text=nil}
P["TU4a_006"]={id="TU4a_006",name="Jaina Proudmoore",type="HERO",set="MISSIONS",rarity="COMMON",class="MAGE",hp=27,text=nil}
P["TU4b_001"]={id="TU4b_001",name="Millhouse Manastorm",type="HERO",set="MISSIONS",rarity="COMMON",class="MAGE",hp=20,text=nil}
P["TU4c_001"]={id="TU4c_001",name="King Mukla",type="HERO",set="MISSIONS",rarity="COMMON",class="NEUTRAL",hp=26,text=nil}
P["TU4d_001"]={id="TU4d_001",name="Hemet Nesingwary",type="HERO",set="MISSIONS",rarity="COMMON",class="HUNTER",hp=20,text=nil}
P["TU4e_001"]={id="TU4e_001",name="Illidan Stormrage",type="HERO",set="MISSIONS",rarity="FREE",class="HUNTER",hp=30,text=nil}
P["TU4f_001"]={id="TU4f_001",name="Lorewalker Cho",type="HERO",set="MISSIONS",rarity="FREE",class="NEUTRAL",hp=25,text=nil}
P["XXX_040"]={id="XXX_040",name="Hogger",type="HERO",set="CHEAT",rarity="FREE",class="WARRIOR",hp=10,text=nil}

-- === HERO POWERS (43) ===
P["CS1h_001"]={id="CS1h_001",name="Lesser Heal",type="HERO_POWER",set="CORE",rarity="FREE",class="PRIEST",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Restore 2 Health."}
P["CS2_017"]={id="CS2_017",name="Shapeshift",type="HERO_POWER",set="CORE",rarity="FREE",class="DRUID",cost=2,text="<b>Hero Power</b> +1 Attack this turn. +1 Armor."}
P["CS2_034"]={id="CS2_034",name="Fireblast",type="HERO_POWER",set="CORE",rarity="FREE",class="MAGE",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Deal 1 damage."}
P["CS2_049"]={id="CS2_049",name="Totemic Call",type="HERO_POWER",set="CORE",rarity="FREE",class="SHAMAN",cost=2,entourage={"CS2_050","CS2_051","CS2_052","NEW1_009"},reqs={REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY=0,REQ_NUM_MINION_SLOTS=1},text="<b>Hero Power</b> Summon a random Totem."}
P["CS2_056"]={id="CS2_056",name="Life Tap",type="HERO_POWER",set="CORE",rarity="FREE",class="WARLOCK",cost=2,text="<b>Hero Power</b> Draw a card and take 2 damage."}
P["CS2_083b"]={id="CS2_083b",name="Dagger Mastery",type="HERO_POWER",set="CORE",rarity="FREE",class="ROGUE",cost=2,text="<b>Hero Power</b> Equip a 1/2 Dagger."}
P["CS2_101"]={id="CS2_101",name="Reinforce",type="HERO_POWER",set="CORE",rarity="FREE",class="PALADIN",cost=2,reqs={REQ_NUM_MINION_SLOTS=1},text="<b>Hero Power</b> Summon a 1/1 Silver Hand Recruit."}
P["CS2_102"]={id="CS2_102",name="Armor Up!",type="HERO_POWER",set="CORE",rarity="FREE",class="WARRIOR",cost=2,text="<b>Hero Power</b> Gain 2 Armor."}
P["DS1h_292"]={id="DS1h_292",name="Steady Shot",type="HERO_POWER",set="CORE",rarity="FREE",class="HUNTER",cost=2,reqs={REQ_MINION_OR_ENEMY_HERO=0,REQ_STEADY_SHOT=0},text="<b>Hero Power</b> Deal 2 damage to the enemy hero."}
P["EX1_625t"]={id="EX1_625t",name="Mind Spike",type="HERO_POWER",set="EXPERT1",rarity="FREE",class="PRIEST",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Deal 2 damage."}
P["EX1_625t2"]={id="EX1_625t2",name="Mind Shatter",type="HERO_POWER",set="EXPERT1",rarity="FREE",class="PRIEST",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Deal 3 damage."}
P["EX1_tk33"]={id="EX1_tk33",name="INFERNO!",type="HERO_POWER",set="EXPERT1",rarity="FREE",class="WARLOCK",cost=2,reqs={REQ_NUM_MINION_SLOTS=1},text="<b>Hero Power</b> Summon a 6/6 Infernal."}
P["NAX10_03"]={id="NAX10_03",name="Hateful Strike",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=4,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Destroy a minion."}
P["NAX10_03H"]={id="NAX10_03H",name="Hateful Strike",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=4,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Destroy a minion."}
P["NAX11_02"]={id="NAX11_02",name="Poison Cloud",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,text="<b>Hero Power</b> Deal 1 damage to all minions. If any die, summon a slime."}
P["NAX11_02H"]={id="NAX11_02H",name="Poison Cloud",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Hero Power</b> Deal 2 damage to all enemies. If any die, summon a slime."}
P["NAX12_02"]={id="NAX12_02",name="Decimate",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,reqs={REQ_MINIMUM_ENEMY_MINIONS=1},text="<b>Hero Power</b> Change the Health of all minions to 1."}
P["NAX12_02H"]={id="NAX12_02H",name="Decimate",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,reqs={REQ_MINIMUM_ENEMY_MINIONS=1},text="<b>Hero Power</b> Change the Health of enemy minions to 1."}
P["NAX13_02"]={id="NAX13_02",name="Polarity Shift",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Hero Power</b> Swap the Attack and Health of all minions."}
P["NAX14_02"]={id="NAX14_02",name="Frost Breath",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Hero Power</b> Destroy all enemy minions that aren't <b>Frozen</b>."}
P["NAX15_02"]={id="NAX15_02",name="Frost Blast",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,scriptTags={"FREEZE"},text="<b>Hero Power</b> Deal 2 damage to the enemy hero and <b>Freeze</b> it."}
P["NAX15_02H"]={id="NAX15_02H",name="Frost Blast",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,scriptTags={"FREEZE"},text="<b>Hero Power</b> Deal 3 damage to the enemy hero and <b>Freeze</b> it."}
P["NAX15_04"]={id="NAX15_04",name="Chains",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=8,text="<b>Hero Power</b> Take control of a random enemy minion until end of turn."}
P["NAX15_04H"]={id="NAX15_04H",name="Chains",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=8,text="<b>Hero Power</b> Take control of a random enemy minion."}
P["NAX1_04"]={id="NAX1_04",name="Skitter",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,reqs={REQ_NUM_MINION_SLOTS=1},text="<b>Hero Power</b> Summon a 3/1 Nerubian."}
P["NAX1h_04"]={id="NAX1h_04",name="Skitter",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,text="<b>Hero Power</b> Summon a 4/4 Nerubian."}
P["NAX2_03"]={id="NAX2_03",name="Rain of Fire",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,keywords={"ImmuneToSpellpower"},text="<b>Hero Power</b> Fire a missile for each card in your opponent's hand."}
P["NAX2_03H"]={id="NAX2_03H",name="Rain of Fire",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,keywords={"ImmuneToSpellpower"},text="<b>Hero Power</b> Fire a missile for each card in your opponent's hand."}
P["NAX3_02"]={id="NAX3_02",name="Web Wrap",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,reqs={REQ_MINIMUM_ENEMY_MINIONS=1},text="<b>Hero Power</b> Return a random enemy minion to your opponent's hand."}
P["NAX3_02H"]={id="NAX3_02H",name="Web Wrap",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Hero Power</b> Return 2 random enemy minions to your opponent's hand."}
P["NAX4_04"]={id="NAX4_04",name="Raise Dead",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Passive Hero Power</b> Whenever an enemy dies, raise a 1/1 Skeleton."}
P["NAX4_04H"]={id="NAX4_04H",name="Raise Dead",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Passive Hero Power</b> Whenever an enemy dies, raise a 5/5 Skeleton."}
P["NAX5_02"]={id="NAX5_02",name="Eruption",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_MINIMUM_ENEMY_MINIONS=1},text="<b>Hero Power</b> Deal 2 damage to the left-most enemy minion."}
P["NAX5_02H"]={id="NAX5_02H",name="Eruption",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,reqs={REQ_MINIMUM_ENEMY_MINIONS=0},text="<b>Hero Power</b> Deal 3 damage to the left-most enemy minion."}
P["NAX6_02"]={id="NAX6_02",name="Necrotic Aura",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,text="<b>Hero Power</b> Deal 3 damage to the enemy hero."}
P["NAX6_02H"]={id="NAX6_02H",name="Necrotic Aura",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,text="<b>Hero Power</b> Deal 3 damage to the enemy hero."}
P["NAX7_03"]={id="NAX7_03",name="Unbalancing Strike",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,reqs={REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Deal 3 damage."}
P["NAX7_03H"]={id="NAX7_03H",name="Unbalancing Strike",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Deal 4 damage."}
P["NAX8_02"]={id="NAX8_02",name="Harvest",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,text="<b>Hero Power</b> Draw a card."}
P["NAX8_02H"]={id="NAX8_02H",name="Harvest",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,text="<b>Hero Power</b> Draw a card. Gain a Mana Crystal."}
P["NAX9_06"]={id="NAX9_06",name="Unholy Shadow",type="HERO_POWER",set="NAXX",rarity="FREE",class="NEUTRAL",cost=5,text="<b>Hero Power</b> Draw 2 cards."}
P["TU4d_003"]={id="TU4d_003",name="Shotgun Blast",type="HERO_POWER",set="MISSIONS",rarity="COMMON",class="HUNTER",cost=2,reqs={REQ_ENEMY_TARGET=0,REQ_TARGET_TO_PLAY=0},text="<b>Hero Power</b> Deal 1 damage."}
P["TU4e_002"]={id="TU4e_002",name="Flames of Azzinoth",type="HERO_POWER",set="MISSIONS",rarity="FREE",class="NEUTRAL",cost=2,reqs={REQ_NUM_MINION_SLOTS=2},text="<b>Hero Power</b> Summon two 2/1 minions."}

-- === TOKENS / GENERATED (437) -- summon & transform targets ===
P["CRED_01"]={id="CRED_01",name="Jason Chayes",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=7,hp=6,text="<b>Enrage:</b> Just kidding! He never Enrages."}
P["CRED_02"]={id="CRED_02",name="Eric Dodds",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=5,hp=5,text="<b>Battlecry:</b> Summon a 2/2 Pirate and destroy all Ninjas."}
P["CRED_03"]={id="CRED_03",name="Bob Fitch",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=3,atk=2,hp=4,text="<b>Super Taunt</b> (EVERY character must attack this minion.)"}
P["CRED_04"]={id="CRED_04",name="Steven Gabriel",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=1,atk=3,hp=3,text="<b>Battlecry:</b> Summon a frothy beverage."}
P["CRED_05"]={id="CRED_05",name="Kyle Harrison",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=3,atk=5,hp=4,text="3 for a 5/4? That's a good deal!"}
P["CRED_06"]={id="CRED_06",name="Derek Sakamoto",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=1,atk=3,hp=1,text="The notorious Footclapper."}
P["CRED_07"]={id="CRED_07",name="Zwick",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=2,hp=2,text="<b>Battlecry:</b> Complain about bacon prices."}
P["CRED_08"]={id="CRED_08",name="Ben Brode",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=3,atk=4,hp=1,text="Your volume can't be reduced below maximum."}
P["CRED_09"]={id="CRED_09",name="Ben Thompson",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=6,atk=4,hp=7,text="<b>Battlecry:</b> Draw some cards. With a pen."}
P["CRED_10"]={id="CRED_10",name="Michael Schweitzer",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=2,hp=2,text="<b>C-C-C-COMBO:</b> Destroy a minion."}
P["CRED_11"]={id="CRED_11",name="Jay Baxter",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=4,atk=1,hp=4,text="<b>Battlecry:</b> Summon FIVE random Inventions."}
P["CRED_12"]={id="CRED_12",name="Rachelle Davis",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=1,hp=2,text="<b>Battlecry:</b> Draw TWO cards. She's not a novice engineer."}
P["CRED_13"]={id="CRED_13",name="Brian Schwab",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=10,atk=10,hp=10,text="At the end of your turn, give a random minion +1 Attack."}
P["CRED_14"]={id="CRED_14",name="Yong Woo",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=3,hp=2,text="Your other minions have +3 Attack and <b>Charge</b>."}
P["CRED_15"]={id="CRED_15",name="Andy Brock",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=1,atk=1,hp=3,text="Can't be <b>Silenced. Divine Shield, Stealth.</b>"}
P["CRED_16"]={id="CRED_16",name="Hamilton Chu",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=7,atk=9,hp=5,text="Was successfully NOT part of the problem! ...most of the time."}
P["CRED_17"]={id="CRED_17",name="Rob Pardo",type="MINION",set="CREDITS",rarity="LEGENDARY",class="NEUTRAL",cost=9,atk=9,hp=9,text="You can't start a game without this minion in your deck."}
P["CS1_113e"]={id="CS1_113e",name="Mind Control",type="ENCHANTMENT",set="CORE",rarity="COMMON",class="PRIEST",text="This minion has switched controllers."}
P["CS1_129e"]={id="CS1_129e",name="Inner Fire",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PRIEST",text="This minion's Attack is equal to its Health."}
P["CS2_004e"]={id="CS2_004e",name="Power Word: Shield",type="ENCHANTMENT",set="CORE",rarity="FREE",class="PRIEST",text="+2 Health."}
P["CS2_005o"]={id="CS2_005o",name="Claw",type="ENCHANTMENT",set="CORE",rarity="FREE",class="DRUID",text="+2 Attack this turn."}
P["CS2_009e"]={id="CS2_009e",name="Mark of the Wild",type="ENCHANTMENT",set="CORE",rarity="FREE",class="DRUID",text="This minion has +2/+2 and <b>Taunt</b>."}
P["CS2_011o"]={id="CS2_011o",name="Savage Roar",type="ENCHANTMENT",set="CORE",rarity="FREE",class="DRUID",text="+2 Attack this turn."}
P["CS2_013t"]={id="CS2_013t",name="Excess Mana",type="SPELL",set="CORE",rarity="FREE",class="DRUID",cost=0,text="Draw a card. (You can only have 10 Mana in your tray.)"}
P["CS2_017o"]={id="CS2_017o",name="Claws",type="ENCHANTMENT",set="CORE",rarity="FREE",class="DRUID",text="Your hero has +1 Attack this turn."}
P["CS2_022e"]={id="CS2_022e",name="Polymorph",type="ENCHANTMENT",set="CORE",rarity="COMMON",class="MAGE",text="This minion has been transformed into a 1/1 Sheep."}
P["CS2_038e"]={id="CS2_038e",name="Ancestral Spirit",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="SHAMAN",text="<b>Deathrattle:</b> Resummon this minion."}
P["CS2_041e"]={id="CS2_041e",name="Ancestral Infusion",type="ENCHANTMENT",set="CORE",rarity="FREE",class="SHAMAN",keywords={"TAUNT"},text="Taunt."}
P["CS2_045e"]={id="CS2_045e",name="Rockbiter Weapon",type="ENCHANTMENT",set="CORE",rarity="FREE",class="SHAMAN",text="This character has +3 Attack this turn."}
P["CS2_046e"]={id="CS2_046e",name="Bloodlust",type="ENCHANTMENT",set="CORE",rarity="FREE",class="SHAMAN",text="+3 Attack this turn."}
P["CS2_050"]={id="CS2_050",name="Searing Totem",type="MINION",set="CORE",rarity="FREE",class="SHAMAN",cost=1,atk=1,hp=1,race="TOTEM",text=nil}
P["CS2_051"]={id="CS2_051",name="Stoneclaw Totem",type="MINION",set="CORE",rarity="FREE",class="SHAMAN",cost=1,atk=0,hp=2,race="TOTEM",keywords={"TAUNT"},text="<b>Taunt</b>"}
P["CS2_052"]={id="CS2_052",name="Wrath of Air Totem",type="MINION",set="CORE",rarity="FREE",class="SHAMAN",cost=1,atk=0,hp=2,race="TOTEM",spellDamage=1,text="<b>Spell Damage +1</b>"}
P["CS2_053e"]={id="CS2_053e",name="Far Sight",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="SHAMAN",text="One of your cards costs (3) less."}
P["CS2_059o"]={id="CS2_059o",name="Blood Pact",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARLOCK",text="Increased Health."}
P["CS2_063e"]={id="CS2_063e",name="Corruption",type="ENCHANTMENT",set="CORE",rarity="FREE",class="WARLOCK",text="At the start of the corrupting player's turn, destroy this minion."}
P["CS2_073e"]={id="CS2_073e",name="Cold Blood",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="ROGUE",text="+2 Attack."}
P["CS2_073e2"]={id="CS2_073e2",name="Cold Blood",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="ROGUE",text="+4 Attack."}
P["CS2_074e"]={id="CS2_074e",name="Deadly Poison",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="+2 Attack."}
P["CS2_082"]={id="CS2_082",name="Wicked Knife",type="WEAPON",set="CORE",rarity="FREE",class="ROGUE",cost=1,atk=1,dur=2,text=nil}
P["CS2_083e"]={id="CS2_083e",name="Sharpened",type="ENCHANTMENT",set="CORE",rarity="FREE",class="ROGUE",text="+1 Attack this turn."}
P["CS2_084e"]={id="CS2_084e",name="Hunter's Mark",type="ENCHANTMENT",set="CORE",rarity="FREE",class="HUNTER",text="This minion has 1 Health."}
P["CS2_087e"]={id="CS2_087e",name="Blessing of Might",type="ENCHANTMENT",set="CORE",rarity="FREE",class="PALADIN",text="+3 Attack."}
P["CS2_092e"]={id="CS2_092e",name="Blessing of Kings",type="ENCHANTMENT",set="CORE",rarity="FREE",class="PALADIN",text="+4/+4."}
P["CS2_101t"]={id="CS2_101t",name="Silver Hand Recruit",type="MINION",set="CORE",rarity="FREE",class="PALADIN",cost=1,atk=1,hp=1,text=nil}
P["CS2_103e2"]={id="CS2_103e2",name="Charge",type="ENCHANTMENT",set="CORE",rarity="FREE",class="WARRIOR",text="+2 Attack and <b>Charge</b>."}
P["CS2_104e"]={id="CS2_104e",name="Rampage",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="+3/+3."}
P["CS2_105e"]={id="CS2_105e",name="Heroic Strike",type="ENCHANTMENT",set="CORE",rarity="FREE",class="WARRIOR",text="+4 Attack this turn."}
P["CS2_122e"]={id="CS2_122e",name="Enhanced",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Raid Leader is granting this minion +1 Attack."}
P["CS2_146o"]={id="CS2_146o",name="Sharpened",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+1 Durability."}
P["CS2_152"]={id="CS2_152",name="Squire",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=2,dustHS={40,400,5,50},text=nil}
P["CS2_181e"]={id="CS2_181e",name="Full Strength",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="This minion has +2 Attack."}
P["CS2_188o"]={id="CS2_188o",name="'Inspired'",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="This minion has +2 Attack this turn."}
P["CS2_221e"]={id="CS2_221e",name="Sharp!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+2 Attack from Spiteful Smith."}
P["CS2_222o"]={id="CS2_222o",name="Might of Stormwind",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Has +1/+1."}
P["CS2_226e"]={id="CS2_226e",name="Frostwolf Banner",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Increased stats."}
P["CS2_236e"]={id="CS2_236e",name="Divine Spirit",type="ENCHANTMENT",set="CORE",rarity="FREE",class="PRIEST",text="This minion has double Health."}
P["CS2_boar"]={id="CS2_boar",name="Boar",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,race="BEAST",text=nil}
P["CS2_mirror"]={id="CS2_mirror",name="Mirror Image",type="MINION",set="CORE",rarity="COMMON",class="MAGE",cost=0,atk=0,hp=2,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["CS2_tk1"]={id="CS2_tk1",name="Sheep",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=0,atk=1,hp=1,race="BEAST",text=nil}
P["DREAM_01"]={id="DREAM_01",name="Laughing Sister",type="MINION",set="EXPERT1",rarity="FREE",class="DREAM",cost=3,atk=3,hp=5,keywords={"CANT_BE_TARGETED_BY_HERO_POWERS","CANT_BE_TARGETED_BY_SPELLS"},text="Can't be targeted by spells or Hero Powers."}
P["DREAM_02"]={id="DREAM_02",name="Ysera Awakens",type="SPELL",set="EXPERT1",rarity="FREE",class="DREAM",cost=2,text="Deal 5 damage to all characters except Ysera."}
P["DREAM_03"]={id="DREAM_03",name="Emerald Drake",type="MINION",set="EXPERT1",rarity="FREE",class="DREAM",cost=4,atk=7,hp=6,race="DRAGON",text=nil}
P["DREAM_04"]={id="DREAM_04",name="Dream",type="SPELL",set="EXPERT1",rarity="FREE",class="DREAM",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Return a minion to its owner's hand."}
P["DREAM_05"]={id="DREAM_05",name="Nightmare",type="SPELL",set="EXPERT1",rarity="FREE",class="DREAM",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +5/+5. At the start of your next turn, destroy it."}
P["DREAM_05e"]={id="DREAM_05e",name="Nightmare",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="This minion has +5/+5, but will be destroyed soon."}
P["DS1_070o"]={id="DS1_070o",name="Master's Presence",type="ENCHANTMENT",set="CORE",rarity="FREE",class="HUNTER",text="+2/+2 and <b>Taunt</b>."}
P["DS1_175o"]={id="DS1_175o",name="Furious Howl",type="ENCHANTMENT",set="CORE",rarity="FREE",class="HUNTER",text="This Beast has +1 Attack from Timber Wolf."}
P["DS1_178e"]={id="DS1_178e",name="Charge",type="ENCHANTMENT",set="CORE",rarity="FREE",class="HUNTER",text="Tundra Rhino grants <b>Charge</b>."}
P["EX1_001e"]={id="EX1_001e",name="Warded",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["EX1_004e"]={id="EX1_004e",name="Elune's Grace",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Health."}
P["EX1_014t"]={id="EX1_014t",name="Bananas",type="SPELL",set="EXPERT1",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +1/+1."}
P["EX1_014te"]={id="EX1_014te",name="Bananas",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Has +1/+1."}
P["EX1_019e"]={id="EX1_019e",name="Cleric's Blessing",type="ENCHANTMENT",set="CORE",rarity="FREE",class="PRIEST",text="+1/+1."}
P["EX1_025t"]={id="EX1_025t",name="Mechanical Dragonling",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,race="MECHANICAL",text=nil}
P["EX1_043e"]={id="EX1_043e",name="Hour of Twilight",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Health."}
P["EX1_044e"]={id="EX1_044e",name="Level Up!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Attack and Health."}
P["EX1_046e"]={id="EX1_046e",name="Tempered",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+2 Attack this turn."}
P["EX1_055o"]={id="EX1_055o",name="Empowered",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Mana Addict has increased Attack."}
P["EX1_059e"]={id="EX1_059e",name="Experiments!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Attack and Health have been swapped by Crazed Alchemist."}
P["EX1_080o"]={id="EX1_080o",name="Keeping Secrets",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased stats."}
P["EX1_084e"]={id="EX1_084e",name="Charge",type="ENCHANTMENT",set="CORE",rarity="FREE",class="WARRIOR",text="This minion has <b>Charge</b>."}
P["EX1_093e"]={id="EX1_093e",name="Hand of Argus",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+1/+1 and <b>Taunt</b>."}
P["EX1_103e"]={id="EX1_103e",name="Mrghlglhal",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+2 Health."}
P["EX1_110t"]={id="EX1_110t",name="Baine Bloodhoof",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=4,atk=4,hp=5,dustHS={1600,3200,400,1600},text=nil}
P["EX1_116t"]={id="EX1_116t",name="Whelp",type="MINION",set="EXPERT1",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,race="DRAGON",text=nil}
P["EX1_128e"]={id="EX1_128e",name="Concealed",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="ROGUE",text="Stealthed until your next turn."}
P["EX1_130a"]={id="EX1_130a",name="Defender",type="MINION",set="EXPERT1",rarity="COMMON",class="PALADIN",cost=1,atk=2,hp=1,dustHS={40,400,5,50},text=nil}
P["EX1_131t"]={id="EX1_131t",name="Defias Bandit",type="MINION",set="EXPERT1",rarity="FREE",class="ROGUE",cost=1,atk=2,hp=1,text=nil}
P["EX1_145o"]={id="EX1_145o",name="Preparation",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="ROGUE",text="The next spell you cast this turn costs (3) less."}
P["EX1_154a"]={id="EX1_154a",name="Wrath",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 3 damage to a minion."}
P["EX1_154b"]={id="EX1_154b",name="Wrath",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 1 damage to a minion. Draw a card."}
P["EX1_155a"]={id="EX1_155a",name="Mark of Nature",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="+4 Attack."}
P["EX1_155ae"]={id="EX1_155ae",name="Mark of Nature",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="This minion has +4 Attack."}
P["EX1_155b"]={id="EX1_155b",name="Mark of Nature",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="+4 Health and <b>Taunt</b>."}
P["EX1_155be"]={id="EX1_155be",name="Mark of Nature",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="This minion has +4 Health and <b>Taunt</b>."}
P["EX1_158e"]={id="EX1_158e",name="Soul of the Forest",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="Deathrattle: Summon a 2/2 Treant."}
P["EX1_158t"]={id="EX1_158t",name="Treant",type="MINION",set="EXPERT1",rarity="FREE",class="DRUID",cost=1,atk=2,hp=2,text=nil}
P["EX1_160a"]={id="EX1_160a",name="Summon a Panther",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_NUM_MINION_SLOTS=1},text="Summon a 3/2 Panther."}
P["EX1_160b"]={id="EX1_160b",name="Leader of the Pack",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Give your minions +1/+1."}
P["EX1_160be"]={id="EX1_160be",name="Leader of the Pack",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="+1/+1"}
P["EX1_160t"]={id="EX1_160t",name="Panther",type="MINION",set="EXPERT1",rarity="COMMON",class="DRUID",cost=2,atk=3,hp=2,race="BEAST",dustHS={40,400,5,50},text=nil}
P["EX1_161o"]={id="EX1_161o",name="Demoralizing Roar",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="This minion has -3 Attack this turn."}
P["EX1_162o"]={id="EX1_162o",name="Strength of the Pack",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Dire Wolf Alpha is granting +1 Attack to this minion."}
P["EX1_164a"]={id="EX1_164a",name="Nourish",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Gain 2 Mana Crystals."}
P["EX1_164b"]={id="EX1_164b",name="Nourish",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Draw 3 cards."}
P["EX1_165a"]={id="EX1_165a",name="Cat Form",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=0,dustHS={40,400,5,50},text="<b>Charge</b>"}
P["EX1_165b"]={id="EX1_165b",name="Bear Form",type="SPELL",set="EXPERT1",rarity="COMMON",class="DRUID",cost=0,dustHS={40,400,5,50},text="+2 Health and <b>Taunt</b>."}
P["EX1_165t1"]={id="EX1_165t1",name="Druid of the Claw",type="MINION",set="EXPERT1",rarity="COMMON",class="DRUID",cost=5,atk=4,hp=4,race="BEAST",keywords={"CHARGE"},dustHS={40,400,5,50},text="<b>Charge</b>"}
P["EX1_165t2"]={id="EX1_165t2",name="Druid of the Claw",type="MINION",set="EXPERT1",rarity="COMMON",class="DRUID",cost=5,atk=4,hp=6,race="BEAST",keywords={"TAUNT"},dustHS={40,400,5,50},text="<b>Taunt</b>"}
P["EX1_166a"]={id="EX1_166a",name="Moonfire",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 2 damage."}
P["EX1_166b"]={id="EX1_166b",name="Dispel",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,scriptTags={"SILENCE"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="<b>Silence</b> a minion."}
P["EX1_178a"]={id="EX1_178a",name="Rooted",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="+5 Health and <b>Taunt</b>."}
P["EX1_178ae"]={id="EX1_178ae",name="Rooted",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="+5 Health and <b>Taunt</b>."}
P["EX1_178b"]={id="EX1_178b",name="Uproot",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="+5 Attack."}
P["EX1_178be"]={id="EX1_178be",name="Uprooted",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="+5 Attack."}
P["EX1_244e"]={id="EX1_244e",name="Totemic Might",type="ENCHANTMENT",set="CORE",rarity="FREE",class="SHAMAN",text="+2 Health."}
P["EX1_246e"]={id="EX1_246e",name="Hexxed",type="ENCHANTMENT",set="CORE",rarity="FREE",class="SHAMAN",text="This minion has been transformed!"}
P["EX1_258e"]={id="EX1_258e",name="Overloading",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="SHAMAN",text="Increased stats."}
P["EX1_274e"]={id="EX1_274e",name="Raw Power!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="MAGE",text="Increased stats."}
P["EX1_295o"]={id="EX1_295o",name="Ice Block",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="MAGE",text="Your hero is <b>Immune</b> this turn."}
P["EX1_304e"]={id="EX1_304e",name="Consume",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARLOCK",text="Increased stats."}
P["EX1_316e"]={id="EX1_316e",name="Power Overwhelming",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARLOCK",text="This minion has +4/+4, but will die a horrible death at the end of the turn."}
P["EX1_317t"]={id="EX1_317t",name="Worthless Imp",type="MINION",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=1,atk=1,hp=1,race="DEMON",dustHS={40,400,5,50},text="You are out of demons! At least there are always imps..."}
P["EX1_323w"]={id="EX1_323w",name="Blood Fury",type="WEAPON",set="EXPERT1",rarity="FREE",class="WARLOCK",cost=3,atk=3,dur=8,text=nil}
P["EX1_334e"]={id="EX1_334e",name="Dark Command",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PRIEST",text="This minion has switched controllers this turn."}
P["EX1_345t"]={id="EX1_345t",name="Shadow of Nothing",type="MINION",set="EXPERT1",rarity="EPIC",class="PRIEST",cost=0,atk=0,hp=1,dustHS={400,1600,100,400},text="Mindgames whiffed! Your opponent had no minions!"}
P["EX1_355e"]={id="EX1_355e",name="Blessed Champion",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="This minion's Attack has been doubled."}
P["EX1_360e"]={id="EX1_360e",name="Humility",type="ENCHANTMENT",set="CORE",rarity="FREE",class="PALADIN",text="Attack has been changed to 1."}
P["EX1_363e"]={id="EX1_363e",name="Blessing of Wisdom",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="When this minion attacks, the player who blessed it draws a card."}
P["EX1_363e2"]={id="EX1_363e2",name="Blessing of Wisdom",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="When this minion attacks, the enemy player draws a card."}
P["EX1_366e"]={id="EX1_366e",name="Justice Served",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="Has +1/+1."}
P["EX1_379e"]={id="EX1_379e",name="Repentance",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="Health reduced to 1."}
P["EX1_382e"]={id="EX1_382e",name="Stand Down!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="Attack changed to 1."}
P["EX1_383t"]={id="EX1_383t",name="Ashbringer",type="WEAPON",set="EXPERT1",rarity="LEGENDARY",class="PALADIN",cost=5,atk=5,dur=3,dustHS={1600,3200,400,1600},text=nil}
P["EX1_398t"]={id="EX1_398t",name="Battle Axe",type="WEAPON",set="EXPERT1",rarity="FREE",class="WARRIOR",cost=1,atk=2,dur=2,text=nil}
P["EX1_399e"]={id="EX1_399e",name="Berserking",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="This minion has increased Attack."}
P["EX1_409e"]={id="EX1_409e",name="Upgraded",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="+1 Attack and +1 Durability."}
P["EX1_409t"]={id="EX1_409t",name="Heavy Axe",type="WEAPON",set="EXPERT1",rarity="FREE",class="WARRIOR",cost=1,atk=1,dur=3,text=nil}
P["EX1_411e"]={id="EX1_411e",name="Bloodrage",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="No durability loss."}
P["EX1_411e2"]={id="EX1_411e2",name="Needs Sharpening",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="Decreased Attack."}
P["EX1_506a"]={id="EX1_506a",name="Murloc Scout",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=0,atk=1,hp=1,race="MURLOC",text=nil}
P["EX1_507e"]={id="EX1_507e",name="Mrgglaargl!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Murloc Warleader is granting +2/+1."}
P["EX1_508o"]={id="EX1_508o",name="Mlarggragllabl!",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="This Murloc has +1 Attack."}
P["EX1_509e"]={id="EX1_509e",name="Blarghghl",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["EX1_531e"]={id="EX1_531e",name="Well Fed",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="HUNTER",text="Increased Attack and Health."}
P["EX1_534t"]={id="EX1_534t",name="Hyena",type="MINION",set="EXPERT1",rarity="RARE",class="HUNTER",cost=2,atk=2,hp=2,race="BEAST",dustHS={100,800,20,100},text=nil}
P["EX1_536e"]={id="EX1_536e",name="Upgraded",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="HUNTER",text="Increased Durability."}
P["EX1_538t"]={id="EX1_538t",name="Hound",type="MINION",set="EXPERT1",rarity="FREE",class="HUNTER",cost=1,atk=1,hp=1,race="BEAST",keywords={"CHARGE"},text="<b>Charge</b>"}
P["EX1_549o"]={id="EX1_549o",name="Bestial Wrath",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="HUNTER",text="+2 Attack and <b>Immune</b> this turn."}
P["EX1_554t"]={id="EX1_554t",name="Snake",type="MINION",set="EXPERT1",rarity="COMMON",class="HUNTER",cost=0,atk=1,hp=1,race="BEAST",dustHS={40,400,5,50},text=nil}
P["EX1_561e"]={id="EX1_561e",name="Alexstrasza's Fire",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Health set to 15."}
P["EX1_565o"]={id="EX1_565o",name="Flametongue",type="ENCHANTMENT",set="CORE",rarity="FREE",class="SHAMAN",text="+2 Attack from Flametongue Totem."}
P["EX1_570e"]={id="EX1_570e",name="Bite",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+4 Attack this turn."}
P["EX1_573a"]={id="EX1_573a",name="Demigod's Favor",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Give your other minions +2/+2."}
P["EX1_573ae"]={id="EX1_573ae",name="Demigod's Favor",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="DRUID",text="+2/+2."}
P["EX1_573b"]={id="EX1_573b",name="Shan'do's Lesson",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Summon two 2/2 Treants with <b>Taunt</b>."}
P["EX1_573t"]={id="EX1_573t",name="Treant",type="MINION",set="EXPERT1",rarity="FREE",class="DRUID",cost=1,atk=2,hp=2,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["EX1_584e"]={id="EX1_584e",name="Teachings of the Kirin Tor",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="<b>Spell Damage +1</b>."}
P["EX1_590e"]={id="EX1_590e",name="Shadows of M'uru",type="ENCHANTMENT",set="EXPERT1",rarity="COMMON",class="NEUTRAL",text="This minion has consumed Divine Shields and has increased Attack and Health."}
P["EX1_596e"]={id="EX1_596e",name="Demonfire",type="ENCHANTMENT",set="EXPERT1",rarity="COMMON",class="WARLOCK",text="This Demon has +2/+2."}
P["EX1_598"]={id="EX1_598",name="Imp",type="MINION",set="EXPERT1",rarity="RARE",class="NEUTRAL",cost=1,atk=1,hp=1,race="DEMON",dustHS={100,800,20,100},text=nil}
P["EX1_603e"]={id="EX1_603e",name="Whipped Into Shape",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="+2 Attack."}
P["EX1_604o"]={id="EX1_604o",name="Berserk",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="Increased Attack."}
P["EX1_607e"]={id="EX1_607e",name="Inner Rage",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="+2 Attack."}
P["EX1_611e"]={id="EX1_611e",name="Trapped",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="HUNTER",text="Will be <b>Frozen</b> again at the start of the next turn."}
P["EX1_612o"]={id="EX1_612o",name="Power of the Kirin Tor",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="MAGE",text="Your next Secret costs (0)."}
P["EX1_613e"]={id="EX1_613e",name="VanCleef's Vengeance",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="ROGUE",text="This minion has increased Attack and Health."}
P["EX1_614t"]={id="EX1_614t",name="Flame of Azzinoth",type="MINION",set="EXPERT1",rarity="FREE",class="NEUTRAL",cost=1,atk=2,hp=1,text=nil}
P["EX1_619e"]={id="EX1_619e",name="Equality",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PALADIN",text="Health changed to 1."}
P["EX1_623e"]={id="EX1_623e",name="Infusion",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="PRIEST",text="+3 Health."}
P["EX1_finkle"]={id="EX1_finkle",name="Finkle Einhorn",type="MINION",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",cost=2,atk=3,hp=3,dustHS={1600,3200,400,1600},text=nil}
P["EX1_tk11"]={id="EX1_tk11",name="Spirit Wolf",type="MINION",set="EXPERT1",rarity="RARE",class="SHAMAN",cost=2,atk=2,hp=3,keywords={"TAUNT"},dustHS={100,800,20,100},text="<b>Taunt</b>"}
P["EX1_tk28"]={id="EX1_tk28",name="Squirrel",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,race="BEAST",dustHS={40,400,5,50},text=nil}
P["EX1_tk29"]={id="EX1_tk29",name="Devilsaur",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=5,atk=5,hp=5,race="BEAST",dustHS={40,400,5,50},text=nil}
P["EX1_tk31"]={id="EX1_tk31",name="Mind Controlling",type="ENCHANTMENT",set="EXPERT1",rarity="COMMON",class="PRIEST",text=nil}
P["EX1_tk34"]={id="EX1_tk34",name="Infernal",type="MINION",set="EXPERT1",rarity="COMMON",class="WARLOCK",cost=6,atk=6,hp=6,race="DEMON",dustHS={40,400,5,50},text=nil}
P["EX1_tk9"]={id="EX1_tk9",name="Treant",type="MINION",set="EXPERT1",rarity="COMMON",class="DRUID",cost=1,atk=2,hp=2,keywords={"CHARGE"},dustHS={40,400,5,50},text="<b>Charge</b>. At the end of the turn, destroy this minion."}
P["FP1_002t"]={id="FP1_002t",name="Spectral Spider",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,text=nil}
P["FP1_005e"]={id="FP1_005e",name="Consume",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Increased stats."}
P["FP1_006"]={id="FP1_006",name="Deathcharger",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=2,hp=3,keywords={"CHARGE"},scriptTags={"DEATHRATTLE"},text="<b>Charge. Deathrattle:</b> Deal 3 damage to your hero."}
P["FP1_007t"]={id="FP1_007t",name="Nerubian",type="MINION",set="NAXX",rarity="RARE",class="NEUTRAL",cost=3,atk=4,hp=4,text=nil}
P["FP1_012t"]={id="FP1_012t",name="Slime",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=2,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["FP1_014t"]={id="FP1_014t",name="Thaddius",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=10,atk=11,hp=11,text=nil}
P["FP1_019t"]={id="FP1_019t",name="Treant",type="MINION",set="NAXX",rarity="FREE",class="DRUID",cost=1,atk=2,hp=2,text=nil}
P["FP1_020e"]={id="FP1_020e",name="Vengeance",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="PALADIN",text="+3/+2."}
P["FP1_023e"]={id="FP1_023e",name="Power of the Ziggurat",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="PRIEST",text="+3 Health."}
P["FP1_028e"]={id="FP1_028e",name="Darkness Calls",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Increased stats."}
P["FP1_030e"]={id="FP1_030e",name="Necrotic Aura",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Your spells cost (5) more this turn."}
P["GAME_001"]={id="GAME_001",name="Luck of the Coin",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Going second grants you increased Health."}
P["GAME_002"]={id="GAME_002",name="Avatar of the Coin",type="MINION",set="CORE",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text="You lost the coin flip, but gained a friend."}
P["GAME_003"]={id="GAME_003",name="Coin's Vengeance",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Going second makes your first minion stronger."}
P["GAME_003e"]={id="GAME_003e",name="Coin's Vengence",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Going second makes your first minion stronger."}
P["GAME_004"]={id="GAME_004",name="AFK",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text="Your turns are shorter."}
P["GAME_005"]={id="GAME_005",name="The Coin",type="SPELL",set="CORE",rarity="FREE",class="NEUTRAL",cost=0,text="Gain 1 Mana Crystal this turn only."}
P["GAME_005e"]={id="GAME_005e",name="The Coin",type="ENCHANTMENT",set="CORE",rarity="FREE",class="NEUTRAL",text=nil}
P["GAME_006"]={id="GAME_006",name="NOOOOOOOOOOOO",type="SPELL",set="CORE",rarity="FREE",class="NEUTRAL",cost=2,text="Somehow, the card you USED to have has been deleted. Here, have this one instead!"}
P["GVG_010b"]={id="GVG_010b",name="Velen's Chosen",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+2/+4 and <b>Spell Damage +1</b>."}
P["GVG_011a"]={id="GVG_011a",name="Shrink Ray",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="-2 Attack this turn."}
P["GVG_014a"]={id="GVG_014a",name="Shadowed",type="ENCHANTMENT",set="GVG",rarity="FREE",class="PRIEST",text="Health was swapped."}
P["GVG_019e"]={id="GVG_019e",name="Demonheart",type="ENCHANTMENT",set="GVG",rarity="FREE",class="WARLOCK",text="+5/+5."}
P["GVG_021e"]={id="GVG_021e",name="Grasp of Mal'Ganis",type="ENCHANTMENT",set="GVG",rarity="FREE",class="WARLOCK",text="Mal'Ganis is granting +2/+2."}
P["GVG_022a"]={id="GVG_022a",name="Tinker's Sharpsword Oil",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+3 Attack."}
P["GVG_022b"]={id="GVG_022b",name="Tinker's Sharpsword Oil",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+3 Attack."}
P["GVG_023a"]={id="GVG_023a",name="Extra Sharp",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+1 Attack."}
P["GVG_027e"]={id="GVG_027e",name="Ironed Out",type="ENCHANTMENT",set="GVG",rarity="FREE",class="ROGUE",text="Increased stats."}
P["GVG_028t"]={id="GVG_028t",name="Gallywix's Coin",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=0,text="Gain 1 Mana Crystal this turn only. (Won't trigger Gallywix.)"}
P["GVG_030a"]={id="GVG_030a",name="Attack Mode",type="SPELL",set="GVG",rarity="FREE",class="DRUID",cost=0,text="+1 Attack."}
P["GVG_030ae"]={id="GVG_030ae",name="Attack Mode",type="ENCHANTMENT",set="GVG",rarity="FREE",class="DRUID",text="+1 Attack."}
P["GVG_030b"]={id="GVG_030b",name="Tank Mode",type="SPELL",set="GVG",rarity="FREE",class="DRUID",cost=0,text="+1 Health."}
P["GVG_030be"]={id="GVG_030be",name="Tank Mode",type="ENCHANTMENT",set="GVG",rarity="FREE",class="DRUID",text="+1 Health."}
P["GVG_032a"]={id="GVG_032a",name="Gift of Mana",type="SPELL",set="GVG",rarity="FREE",class="DRUID",cost=0,text="Give each player a Mana Crystal."}
P["GVG_032b"]={id="GVG_032b",name="Gift of Cards",type="SPELL",set="GVG",rarity="FREE",class="DRUID",cost=0,text="Each player draws a card."}
P["GVG_036e"]={id="GVG_036e",name="Powered",type="ENCHANTMENT",set="GVG",rarity="FREE",class="SHAMAN",text="+2/+2."}
P["GVG_041a"]={id="GVG_041a",name="Dark Wispers",type="SPELL",set="GVG",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="+5/+5 and <b>Taunt</b>."}
P["GVG_041b"]={id="GVG_041b",name="Dark Wispers",type="SPELL",set="GVG",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_NUM_MINION_SLOTS=1},text="Summon 5 Wisps."}
P["GVG_041c"]={id="GVG_041c",name="Dark Wispers",type="ENCHANTMENT",set="GVG",rarity="FREE",class="DRUID",text="+5/+5 and <b>Taunt</b>."}
P["GVG_043e"]={id="GVG_043e",name="Glaivezooka",type="ENCHANTMENT",set="GVG",rarity="FREE",class="HUNTER",text="+1 Attack."}
P["GVG_045t"]={id="GVG_045t",name="Imp",type="MINION",set="GVG",rarity="FREE",class="WARLOCK",cost=1,atk=1,hp=1,race="DEMON",text=nil}
P["GVG_046e"]={id="GVG_046e",name="The King",type="ENCHANTMENT",set="GVG",rarity="FREE",class="HUNTER",text="Increased Attack."}
P["GVG_048e"]={id="GVG_048e",name="Metal Teeth",type="ENCHANTMENT",set="GVG",rarity="FREE",class="HUNTER",text="+2 Attack."}
P["GVG_049e"]={id="GVG_049e",name="Might of Zul'Farrak",type="ENCHANTMENT",set="GVG",rarity="FREE",class="HUNTER",text="Multiplying Attack."}
P["GVG_055e"]={id="GVG_055e",name="Screwy Jank",type="ENCHANTMENT",set="GVG",rarity="FREE",class="WARRIOR",reqs={REQ_FRIENDLY_TARGET=0},text="+2/+2."}
P["GVG_056t"]={id="GVG_056t",name="Burrowing Mine",type="SPELL",set="GVG",rarity="FREE",class="WARRIOR",cost=0,keywords={"ImmuneToSpellpower"},text="When you draw this, it explodes. You take 10 damage and draw a card."}
P["GVG_057a"]={id="GVG_057a",name="Seal of Light",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+2 Attack this turn."}
P["GVG_060e"]={id="GVG_060e",name="Well Equipped",type="ENCHANTMENT",set="GVG",rarity="FREE",class="PALADIN",text="+2/+2."}
P["GVG_063a"]={id="GVG_063a",name="Retribution",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="Increased Attack"}
P["GVG_067a"]={id="GVG_067a",name="Metabolized Magic",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",scriptTags={"AURA"},text="Increased Attack."}
P["GVG_068a"]={id="GVG_068a",name="Metabolized Magic",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",scriptTags={"AURA"},text="Increased Attack."}
P["GVG_069a"]={id="GVG_069a",name="Repairs!",type="ENCHANTMENT",set="GVG",rarity="FREE",class="PRIEST",text="+4 Health."}
P["GVG_076a"]={id="GVG_076a",name="Pistons",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["GVG_080t"]={id="GVG_080t",name="Druid of the Fang",type="MINION",set="GVG",rarity="FREE",class="DRUID",cost=5,atk=7,hp=7,race="BEAST",text=nil}
P["GVG_086e"]={id="GVG_086e",name="Armor Plated",type="ENCHANTMENT",set="GVG",rarity="FREE",class="WARRIOR",text="Increased Attack."}
P["GVG_092t"]={id="GVG_092t",name="Chicken",type="MINION",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,race="BEAST",text=nil}
P["GVG_100e"]={id="GVG_100e",name="Brow Furrow",type="ENCHANTMENT",set="GVG",rarity="FREE",class="WARLOCK",text="Increased stats."}
P["GVG_101e"]={id="GVG_101e",name="Pure",type="ENCHANTMENT",set="GVG",rarity="FREE",class="PALADIN",text="Increased Stats."}
P["GVG_102e"]={id="GVG_102e",name="Might of Tinkertown",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+1/+1."}
P["GVG_104a"]={id="GVG_104a",name="HERE, TAKE BUFF.",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+2/+2."}
P["GVG_106e"]={id="GVG_106e",name="Junked Up",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="Increased stats."}
P["GVG_110t"]={id="GVG_110t",name="Boom Bot",type="MINION",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,race="MECHANICAL",scriptTags={"DEATHRATTLE"},text="<b>Deathrattle</b>: Deal 1-4 damage to a random enemy."}
P["GVG_111t"]={id="GVG_111t",name="V-07-TR-0N",type="MINION",set="GVG",rarity="LEGENDARY",class="NEUTRAL",cost=8,atk=4,hp=8,race="MECHANICAL",keywords={"CHARGE"},dustHS={1600,3200,400,1600},text="<b>Charge</b> <b>Mega-Windfury</b> (Can attack four times a turn.)"}
P["GVG_123e"]={id="GVG_123e",name="Overclocked",type="ENCHANTMENT",set="GVG",rarity="FREE",class="MAGE",spellDamage=2,text="Spell Damage +2."}
P["Mekka1"]={id="Mekka1",name="Homing Chicken",type="MINION",set="PROMO",rarity="COMMON",class="NEUTRAL",cost=1,atk=0,hp=1,race="MECHANICAL",text="At the start of your turn, destroy this minion and draw 3 cards."}
P["Mekka2"]={id="Mekka2",name="Repair Bot",type="MINION",set="PROMO",rarity="COMMON",class="NEUTRAL",cost=1,atk=0,hp=3,race="MECHANICAL",text="At the end of your turn, restore 6 Health to a damaged character."}
P["Mekka3"]={id="Mekka3",name="Emboldener 3000",type="MINION",set="PROMO",rarity="COMMON",class="NEUTRAL",cost=1,atk=0,hp=4,race="MECHANICAL",text="At the end of your turn, give a random minion +1/+1."}
P["Mekka3e"]={id="Mekka3e",name="Emboldened!",type="ENCHANTMENT",set="PROMO",rarity="FREE",class="NEUTRAL",text="Increased Stats."}
P["Mekka4"]={id="Mekka4",name="Poultryizer",type="MINION",set="PROMO",rarity="COMMON",class="NEUTRAL",cost=1,atk=0,hp=3,race="MECHANICAL",text="At the start of your turn, transform a random minion into a 1/1 Chicken."}
P["Mekka4e"]={id="Mekka4e",name="Transformed",type="ENCHANTMENT",set="PROMO",rarity="FREE",class="NEUTRAL",text="Has been transformed into a chicken!"}
P["Mekka4t"]={id="Mekka4t",name="Chicken",type="MINION",set="PROMO",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,race="BEAST",text="Hey Chicken!"}
P["NAX10_02"]={id="NAX10_02",name="Hook",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=5,dur=8,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Put this weapon into your hand."}
P["NAX10_02H"]={id="NAX10_02H",name="Hook",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=4,dur=8,keywords={"WINDFURY"},scriptTags={"DEATHRATTLE"},text="<b>Windfury</b> <b>Deathrattle:</b> Put this weapon into your hand."}
P["NAX11_03"]={id="NAX11_03",name="Fallout Slime",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=2,hp=2,text=nil}
P["NAX11_04"]={id="NAX11_04",name="Mutating Injection",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +4/+4 and <b>Taunt</b>."}
P["NAX11_04e"]={id="NAX11_04e",name="Mutating Injection",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="+4/+4 and <b>Taunt</b>."}
P["NAX12_02e"]={id="NAX12_02e",name="Decimate",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Health changed to 1."}
P["NAX12_03"]={id="NAX12_03",name="Jaws",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=1,dur=5,text="Whenever a minion with <b>Deathrattle</b> dies, gain +2 Attack."}
P["NAX12_03H"]={id="NAX12_03H",name="Jaws",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=3,dur=5,text="Whenever a minion with <b>Deathrattle</b> dies, gain +2 Attack."}
P["NAX12_03e"]={id="NAX12_03e",name="Extra Teeth",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["NAX12_04"]={id="NAX12_04",name="Enrage",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,text="Give your hero +6 Attack this turn."}
P["NAX12_04e"]={id="NAX12_04e",name="Enrage",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="+6 Attack this turn."}
P["NAX13_02e"]={id="NAX13_02e",name="Polarity",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Attack and Health swapped."}
P["NAX13_03"]={id="NAX13_03",name="Supercharge",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,text="Give your minions +2 Health."}
P["NAX13_03e"]={id="NAX13_03e",name="Supercharged",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="+2 Health."}
P["NAX13_04H"]={id="NAX13_04H",name="Feugen",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=4,hp=7,text=nil}
P["NAX13_05H"]={id="NAX13_05H",name="Stalagg",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=5,atk=7,hp=4,text=nil}
P["NAX14_03"]={id="NAX14_03",name="Frozen Champion",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=5,atk=2,hp=10,scriptTags={"AURA"},text="Permanently Frozen. Adjacent minions are Immune to Frost Breath."}
P["NAX14_04"]={id="NAX14_04",name="Pure Cold",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=5,scriptTags={"FREEZE"},text="Deal 8 damage to the enemy hero, and <b>Freeze</b> it."}
P["NAX15_01He"]={id="NAX15_01He",name="Interloper!",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text=nil}
P["NAX15_01e"]={id="NAX15_01e",name="Interloper!",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text=nil}
P["NAX15_03n"]={id="NAX15_03n",name="Guardian of Icecrown",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=4,atk=3,hp=3,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["NAX15_03t"]={id="NAX15_03t",name="Guardian of Icecrown",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=4,atk=5,hp=5,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["NAX15_04a"]={id="NAX15_04a",name="Slave of Kel'Thuzad",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="MINE!"}
P["NAX15_05"]={id="NAX15_05",name="Mr. Bigglesworth",type="MINION",set="NAXX",rarity="LEGENDARY",class="NEUTRAL",cost=0,atk=1,hp=1,race="BEAST",text="This is Kel'Thuzad's kitty."}
P["NAX1_03"]={id="NAX1_03",name="Nerubian",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,atk=3,hp=1,text=nil}
P["NAX1_05"]={id="NAX1_05",name="Locust Swarm",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=7,text="Deal 3 damage to all enemy minions. Restore 3 Health to your hero."}
P["NAX1h_03"]={id="NAX1h_03",name="Nerubian",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,atk=4,hp=4,text=nil}
P["NAX2_05"]={id="NAX2_05",name="Worshipper",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=1,hp=4,scriptTags={"AURA"},text="Your hero has +1 Attack on your turn."}
P["NAX2_05H"]={id="NAX2_05H",name="Worshipper",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=2,hp=4,scriptTags={"AURA"},text="Your hero has +3 Attack on your turn."}
P["NAX3_03"]={id="NAX3_03",name="Necrotic Poison",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy a minion."}
P["NAX4_03"]={id="NAX4_03",name="Skeleton",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,text=nil}
P["NAX4_03H"]={id="NAX4_03H",name="Skeleton",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=5,atk=5,hp=5,text=nil}
P["NAX4_05"]={id="NAX4_05",name="Plague",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=6,text="Destroy all non-Skeleton minions."}
P["NAX5_03"]={id="NAX5_03",name="Mindpocalypse",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,text="Both players draw 2 cards and gain a Mana Crystal."}
P["NAX6_03"]={id="NAX6_03",name="Deathbloom",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=4,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 5 damage to a minion. Summon a Spore."}
P["NAX6_03t"]={id="NAX6_03t",name="Spore",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=0,atk=0,hp=1,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Give all enemy minions +8 Attack."}
P["NAX6_03te"]={id="NAX6_03te",name="Fungal Growth",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["NAX6_04"]={id="NAX6_04",name="Sporeburst",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,text="Deal 1 damage to all enemy minions. Summon a Spore."}
P["NAX7_02"]={id="NAX7_02",name="Understudy",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=2,atk=0,hp=7,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["NAX7_04"]={id="NAX7_04",name="Massive Runeblade",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=5,dur=2,text="Deals double damage to heroes."}
P["NAX7_04H"]={id="NAX7_04H",name="Massive Runeblade",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=10,dur=2,text="Deals double damage to heroes."}
P["NAX7_05"]={id="NAX7_05",name="Mind Control Crystal",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,text="Activate the Crystal to control the Understudies!"}
P["NAX8_03"]={id="NAX8_03",name="Unrelenting Trainee",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=2,hp=2,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Summon a Spectral Trainee for your opponent."}
P["NAX8_03t"]={id="NAX8_03t",name="Spectral Trainee",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=1,atk=0,hp=2,text="At the start of your turn, deal 1 damage to your hero."}
P["NAX8_04"]={id="NAX8_04",name="Unrelenting Warrior",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=3,hp=4,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Summon a Spectral Warrior for your opponent."}
P["NAX8_04t"]={id="NAX8_04t",name="Spectral Warrior",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=0,hp=4,text="At the start of your turn, deal 1 damage to your hero."}
P["NAX8_05"]={id="NAX8_05",name="Unrelenting Rider",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=6,atk=5,hp=6,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Summon a Spectral Rider for your opponent."}
P["NAX8_05t"]={id="NAX8_05t",name="Spectral Rider",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=5,atk=0,hp=6,text="At the start of your turn, deal 1 damage to your hero."}
P["NAX9_02"]={id="NAX9_02",name="Lady Blaumeux",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=1,hp=7,text="Your hero is <b>Immune</b>."}
P["NAX9_02H"]={id="NAX9_02H",name="Lady Blaumeux",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=2,hp=7,text="Your hero is <b>Immune</b>."}
P["NAX9_03"]={id="NAX9_03",name="Thane Korth'azz",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=1,hp=7,text="Your hero is <b>Immune</b>."}
P["NAX9_03H"]={id="NAX9_03H",name="Thane Korth'azz",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=2,hp=7,text="Your hero is <b>Immune</b>."}
P["NAX9_04"]={id="NAX9_04",name="Sir Zeliek",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=1,hp=7,text="Your hero is <b>Immune</b>."}
P["NAX9_04H"]={id="NAX9_04H",name="Sir Zeliek",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=2,hp=7,text="Your hero is <b>Immune</b>."}
P["NAX9_05"]={id="NAX9_05",name="Runeblade",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=1,dur=3,text="Has +3 Attack if the other Horsemen are dead."}
P["NAX9_05H"]={id="NAX9_05H",name="Runeblade",type="WEAPON",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=2,dur=3,text="Has +6 Attack if the other Horsemen are dead."}
P["NAX9_07"]={id="NAX9_07",name="Mark of the Horsemen",type="SPELL",set="NAXX",rarity="FREE",class="NEUTRAL",cost=5,text="Give your minions and your weapon +1/+1."}
P["NAX9_07e"]={id="NAX9_07e",name="Mark of the Horsemen",type="ENCHANTMENT",set="NAXX",rarity="FREE",class="NEUTRAL",text="+1/+1."}
P["NAXM_001"]={id="NAXM_001",name="Necroknight",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=4,atk=5,hp=6,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Destroy the minions next to this one as well."}
P["NAXM_002"]={id="NAXM_002",name="Skeletal Smith",type="MINION",set="NAXX",rarity="FREE",class="NEUTRAL",cost=3,atk=4,hp=3,scriptTags={"DEATHRATTLE"},text="<b>Deathrattle:</b> Destroy your opponent's weapon."}
P["NEW1_007a"]={id="NEW1_007a",name="Starfall",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Deal 2 damage to all enemy minions."}
P["NEW1_007b"]={id="NEW1_007b",name="Starfall",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 5 damage to a minion."}
P["NEW1_008a"]={id="NEW1_008a",name="Ancient Teachings",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,text="Draw 2 cards."}
P["NEW1_008b"]={id="NEW1_008b",name="Ancient Secrets",type="SPELL",set="EXPERT1",rarity="FREE",class="DRUID",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Restore 5 Health."}
P["NEW1_009"]={id="NEW1_009",name="Healing Totem",type="MINION",set="CORE",rarity="FREE",class="SHAMAN",cost=1,atk=0,hp=2,race="TOTEM",text="At the end of your turn, restore 1 Health to all friendly minions."}
P["NEW1_012o"]={id="NEW1_012o",name="Mana Gorged",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="MAGE",text="Increased attack."}
P["NEW1_017e"]={id="NEW1_017e",name="Full Belly",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+2/+2. Full of Murloc."}
P["NEW1_018e"]={id="NEW1_018e",name="Treasure Crazed",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["NEW1_024o"]={id="NEW1_024o",name="Greenskin's Command",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="+1/+1."}
P["NEW1_025e"]={id="NEW1_025e",name="Bolstered",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Health."}
P["NEW1_026t"]={id="NEW1_026t",name="Violet Apprentice",type="MINION",set="EXPERT1",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text=nil}
P["NEW1_027e"]={id="NEW1_027e",name="Yarrr!",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Southsea Captain is granting +1/+1."}
P["NEW1_029t"]={id="NEW1_029t",name="Kill Millhouse!",type="ENCHANTMENT",set="EXPERT1",rarity="LEGENDARY",class="NEUTRAL",text="Spells cost (0) this turn!"}
P["NEW1_032"]={id="NEW1_032",name="Misha",type="MINION",set="CORE",rarity="COMMON",class="HUNTER",cost=3,atk=4,hp=4,race="BEAST",keywords={"TAUNT"},text="<b>Taunt</b>"}
P["NEW1_033"]={id="NEW1_033",name="Leokk",type="MINION",set="CORE",rarity="COMMON",class="HUNTER",cost=3,atk=2,hp=4,race="BEAST",text="Other friendly minions have +1 Attack."}
P["NEW1_033o"]={id="NEW1_033o",name="Eye In The Sky",type="ENCHANTMENT",set="CORE",rarity="FREE",class="HUNTER",text="Leokk is granting this minion +1 Attack."}
P["NEW1_034"]={id="NEW1_034",name="Huffer",type="MINION",set="CORE",rarity="COMMON",class="HUNTER",cost=3,atk=4,hp=2,race="BEAST",keywords={"CHARGE"},text="<b>Charge</b>"}
P["NEW1_036e"]={id="NEW1_036e",name="Commanding Shout",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="Can't be reduced below 1 Health this turn."}
P["NEW1_036e2"]={id="NEW1_036e2",name="Commanding Shout",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="WARRIOR",text="Your minions can't be reduced below 1 Health this turn."}
P["NEW1_037e"]={id="NEW1_037e",name="Equipped",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["NEW1_038o"]={id="NEW1_038o",name="Growth",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Gruul is growing..."}
P["NEW1_040t"]={id="NEW1_040t",name="Gnoll",type="MINION",set="EXPERT1",rarity="FREE",class="NEUTRAL",cost=2,atk=2,hp=2,keywords={"TAUNT"},text="<b>Taunt</b>"}
P["PART_001"]={id="PART_001",name="Armor Plating",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +1 Health."}
P["PART_001e"]={id="PART_001e",name="Armor Plating",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+1 Health."}
P["PART_002"]={id="PART_002",name="Time Rewinder",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Return a friendly minion to your hand."}
P["PART_003"]={id="PART_003",name="Rusty Horn",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion <b>Taunt</b>."}
P["PART_004"]={id="PART_004",name="Finicky Cloakfield",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a friendly minion <b>Stealth</b> until your next turn."}
P["PART_004e"]={id="PART_004e",name="Cloaked",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="Stealthed until your next turn."}
P["PART_005"]={id="PART_005",name="Emergency Coolant",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,scriptTags={"FREEZE"},reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="<b>Freeze</b> a minion."}
P["PART_006"]={id="PART_006",name="Reversing Switch",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Swap a minion's Attack and Health."}
P["PART_006a"]={id="PART_006a",name="Switched",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="Attack and Health have been swapped by Reversing Switch."}
P["PART_007"]={id="PART_007",name="Whirling Blades",type="SPELL",set="GVG",rarity="FREE",class="NEUTRAL",cost=1,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a minion +1 Attack."}
P["PART_007e"]={id="PART_007e",name="Whirling Blades",type="ENCHANTMENT",set="GVG",rarity="FREE",class="NEUTRAL",text="+1 Attack."}
P["PRO_001a"]={id="PRO_001a",name="I Am Murloc",type="SPELL",set="PROMO",rarity="FREE",class="NEUTRAL",cost=4,reqs={REQ_NUM_MINION_SLOTS=1},text="Summon three, four, or five 1/1 Murlocs."}
P["PRO_001at"]={id="PRO_001at",name="Murloc",type="MINION",set="PROMO",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,race="MURLOC",text=nil}
P["PRO_001b"]={id="PRO_001b",name="Rogues Do It...",type="SPELL",set="PROMO",rarity="FREE",class="NEUTRAL",cost=4,reqs={REQ_TARGET_TO_PLAY=0},text="Deal 4 damage. Draw a card."}
P["PRO_001c"]={id="PRO_001c",name="Power of the Horde",type="SPELL",set="PROMO",rarity="FREE",class="NEUTRAL",cost=4,entourage={"CS2_121","EX1_021","EX1_023","EX1_110","EX1_390","CS2_179"},reqs={REQ_NUM_MINION_SLOTS=1},text="Summon a random Horde Warrior."}
P["PlaceholderCard"]={id="PlaceholderCard",name="Placeholder Card",type="MINION",set="NONE",rarity="EPIC",class="MAGE",cost=9,atk=6,hp=8,text="Battlecry: Someone remembers to publish this card."}
P["TU4a_002"]={id="TU4a_002",name="Riverpaw Gnoll",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,text=nil}
P["TU4a_003"]={id="TU4a_003",name="Gnoll",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,text=nil}
P["TU4a_004"]={id="TU4a_004",name="Hogger SMASH!",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=3,reqs={REQ_ENEMY_TARGET=0,REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 4 damage."}
P["TU4a_005"]={id="TU4a_005",name="Massive Gnoll",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=4,atk=5,hp=2,text=nil}
P["TU4c_002"]={id="TU4c_002",name="Barrel Toss",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,reqs={REQ_ENEMY_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Deal 2 damage."}
P["TU4c_003"]={id="TU4c_003",name="Barrel",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=0,atk=0,hp=2,scriptTags={"DEATHRATTLE"},text="Is something in this barrel?"}
P["TU4c_004"]={id="TU4c_004",name="Stomp",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=2,text="Deal 2 damage to all enemies."}
P["TU4c_005"]={id="TU4c_005",name="Hidden Gnome",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=2,atk=1,hp=3,text="Was hiding in a barrel!"}
P["TU4c_006"]={id="TU4c_006",name="Bananas",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,reqs={REQ_FRIENDLY_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a friendly minion +1/+1. (+1 Attack/+1 Health)"}
P["TU4c_006e"]={id="TU4c_006e",name="Bananas",type="ENCHANTMENT",set="MISSIONS",rarity="FREE",class="NEUTRAL",text="This minion has +1/+1. (+1 Attack/+1 Health)"}
P["TU4c_007"]={id="TU4c_007",name="Mukla's Big Brother",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=6,atk=10,hp=10,text="So strong! And only 6 Mana?!"}
P["TU4c_008"]={id="TU4c_008",name="Will of Mukla",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=3,text="Restore 8 Health."}
P["TU4c_008e"]={id="TU4c_008e",name="Might of Mukla",type="ENCHANTMENT",set="MISSIONS",rarity="FREE",class="NEUTRAL",text="King Mukla has +8 Attack this turn."}
P["TU4d_002"]={id="TU4d_002",name="Crazed Hunter",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,text=nil}
P["TU4e_002t"]={id="TU4e_002t",name="Flame of Azzinoth",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,text=nil}
P["TU4e_003"]={id="TU4e_003",name="Naga Myrmidon",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,text="<b></b>"}
P["TU4e_004"]={id="TU4e_004",name="Warglaive of Azzinoth",type="WEAPON",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,dur=2,text=nil}
P["TU4e_005"]={id="TU4e_005",name="Flame Burst",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=3,text="Shoot 5 missiles at random enemies for 1 damage each."}
P["TU4e_007"]={id="TU4e_007",name="Dual Warglaives",type="WEAPON",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=6,atk=4,dur=2,text=nil}
P["TU4f_002"]={id="TU4f_002",name="Pandaren Scout",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,text=nil}
P["TU4f_003"]={id="TU4f_003",name="Shado-Pan Monk",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=2,atk=2,hp=2,text=nil}
P["TU4f_004"]={id="TU4f_004",name="Legacy of the Emperor",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=3,text="Give your minions +2/+2. (+2 Attack/+2 Health)"}
P["TU4f_004o"]={id="TU4f_004o",name="Legacy of the Emperor",type="ENCHANTMENT",set="MISSIONS",rarity="FREE",class="NEUTRAL",text="Has +2/+2. (+2 Attack/+2 Health)"}
P["TU4f_005"]={id="TU4f_005",name="Brewmaster",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=4,atk=4,hp=4,text=nil}
P["TU4f_006"]={id="TU4f_006",name="Transcendence",type="SPELL",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,text="Until you kill Cho's minions, he can't be attacked."}
P["TU4f_006o"]={id="TU4f_006o",name="Transcendence",type="ENCHANTMENT",set="MISSIONS",rarity="FREE",class="NEUTRAL",text="Until you kill Cho's minions, he can't be attacked."}
P["TU4f_007"]={id="TU4f_007",name="Crazy Monkey",type="MINION",set="MISSIONS",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=2,scriptTags={"BATTLECRY"},text="<b>Battlecry:</b> Throw Bananas."}
P["XXX_001"]={id="XXX_001",name="Damage 1",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,keywords={"ImmuneToSpellpower"},reqs={REQ_TARGET_TO_PLAY=0},text="Deal 1 damage."}
P["XXX_002"]={id="XXX_002",name="Damage 5",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,keywords={"ImmuneToSpellpower"},reqs={REQ_TARGET_TO_PLAY=0},text="Deal 5 damage."}
P["XXX_003"]={id="XXX_003",name="Restore 1",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Restore 1 Health to a character."}
P["XXX_004"]={id="XXX_004",name="Restore 5",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Restore 5 Health to a character."}
P["XXX_005"]={id="XXX_005",name="Destroy",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Destroy a minion or hero."}
P["XXX_006"]={id="XXX_006",name="Break Weapon",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy a hero's weapon."}
P["XXX_007"]={id="XXX_007",name="Enable for Attack",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Give a character Charge and make him able to attack!"}
P["XXX_008"]={id="XXX_008",name="Freeze",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,scriptTags={"FREEZE"},reqs={REQ_TARGET_TO_PLAY=0},text="<b>Freeze</b> a character."}
P["XXX_009"]={id="XXX_009",name="Enchant",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Enchant a minion with an empty enchant."}
P["XXX_009e"]={id="XXX_009e",name="Empty Enchant",type="ENCHANTMENT",set="CHEAT",rarity="COMMON",class="NEUTRAL",text="This enchantment does nothing."}
P["XXX_010"]={id="XXX_010",name="Silence - debug",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Remove all enchantments and powers from a minion."}
P["XXX_011"]={id="XXX_011",name="Summon a random Secret",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Summon a secret from your deck."}
P["XXX_012"]={id="XXX_012",name="Bounce",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Return a minion to its owner's hand."}
P["XXX_013"]={id="XXX_013",name="Discard",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Choose a hero. That hero's controller discards his hand."}
P["XXX_014"]={id="XXX_014",name="Mill 10",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Put 10 cards from a hero's deck into his graveyard."}
P["XXX_015"]={id="XXX_015",name="Crash",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Crash the game."}
P["XXX_016"]={id="XXX_016",name="Snake Ball",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Summon five 1/1 snakes."}
P["XXX_017"]={id="XXX_017",name="Draw 3 Cards",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Draw 3 cards."}
P["XXX_018"]={id="XXX_018",name="Destroy All Minions",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Destroy all minions."}
P["XXX_019"]={id="XXX_019",name="Molasses",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="You can take as long as you want on your turn."}
P["XXX_020"]={id="XXX_020",name="Damage all but 1",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,keywords={"ImmuneToSpellpower"},reqs={REQ_TARGET_TO_PLAY=0},text="Set the Health of a character to 1."}
P["XXX_021"]={id="XXX_021",name="Restore All Health",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Restore all Health to a character."}
P["XXX_022"]={id="XXX_022",name="Free Cards",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Your cards cost (0) for the rest of the game."}
P["XXX_022e"]={id="XXX_022e",name="Free Cards",type="ENCHANTMENT",set="CHEAT",rarity="FREE",class="NEUTRAL",text="Your cards cost (0) for the rest of the game."}
P["XXX_023"]={id="XXX_023",name="Destroy All Heroes",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Destroy all heroes."}
P["XXX_024"]={id="XXX_024",name="Damage Reflector",type="MINION",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,atk=3,hp=10,text="Whenever this minion takes damage, deal 1 damage to ALL other characters."}
P["XXX_025"]={id="XXX_025",name="Do Nothing",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="This does nothing."}
P["XXX_026"]={id="XXX_026",name="Enable Emotes",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Enable emotes for your VS.AI game. (not in tutorials, though)"}
P["XXX_027"]={id="XXX_027",name="Server Crash",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Crash the Server. DON'T BE A FOOL."}
P["XXX_028"]={id="XXX_028",name="Reveal Hand",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text=nil}
P["XXX_029"]={id="XXX_029",name="Opponent Concede",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Force your opponent to concede."}
P["XXX_030"]={id="XXX_030",name="Opponent Disconnect",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Force your opponnet to disconnect."}
P["XXX_039"]={id="XXX_039",name="Become Hogger",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Become Hogger for Video Recording."}
P["XXX_041"]={id="XXX_041",name="Destroy Hero Power",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy a player's Hero Power."}
P["XXX_042"]={id="XXX_042",name="Hand to Deck",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Shuffle a player's hand into his deck."}
P["XXX_043"]={id="XXX_043",name="Mill 30",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Put 30 cards from a hero's deck into his graveyard."}
P["XXX_044"]={id="XXX_044",name="Hand Swapper Minion",type="MINION",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,atk=5,hp=5,text="<b>Battlecry:</b> Discard 3 cards, then draw 3 cards."}
P["XXX_045"]={id="XXX_045",name="Steal Card",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Steal a random card from your opponent."}
P["XXX_046"]={id="XXX_046",name="Force AI to Use Hero Power",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,text="Force the AI to use their Hero Power every turn from now on."}
P["XXX_047"]={id="XXX_047",name="Destroy Deck",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Delete an opponent's deck"}
P["XXX_048"]={id="XXX_048",name="-1 Durability",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a player's weapon -1 Durability."}
P["XXX_049"]={id="XXX_049",name="Destroy all Mana",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Destroy all of a player's Mana Crystals."}
P["XXX_050"]={id="XXX_050",name="Destroy a Mana Crystal",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Pick a player and destroy one of his Mana Crystals."}
P["XXX_051"]={id="XXX_051",name="Make Immune",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Permanently make a character <b>Immune</b>."}
P["XXX_052"]={id="XXX_052",name="Grant Mega-Windfury",type="SPELL",set="CHEAT",rarity="COMMON",class="NEUTRAL",cost=0,reqs={REQ_TARGET_TO_PLAY=0},text="Give a minion <b>Mega-Windfury</b>."}
P["XXX_053"]={id="XXX_053",name="Armor",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Give your Hero +100 Armor"}
P["XXX_054"]={id="XXX_054",name="Weapon Buff",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Give your Weapon +100/+100"}
P["XXX_054e"]={id="XXX_054e",name="Weapon Buff Enchant",type="ENCHANTMENT",set="CHEAT",rarity="FREE",class="NEUTRAL",text=nil}
P["XXX_055"]={id="XXX_055",name="1000 Stats",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,reqs={REQ_MINION_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Give a Minion +1000/+1000"}
P["XXX_055e"]={id="XXX_055e",name="1000 Stats Enchant",type="ENCHANTMENT",set="CHEAT",rarity="FREE",class="NEUTRAL",text=nil}
P["XXX_056"]={id="XXX_056",name="Silence Destroy",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,text="Silence and Destroy ALL Minions."}
P["XXX_057"]={id="XXX_057",name="Destroy Secrets",type="SPELL",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,reqs={REQ_HERO_TARGET=0,REQ_TARGET_TO_PLAY=0},text="Choose a hero. Destroy all <b>Secrets</b> controlled by that hero."}
P["XXX_095"]={id="XXX_095",name="AI Buddy - All Charge!",type="MINION",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text="Spawn into play to give all minions <b>Charge</b>."}
P["XXX_096"]={id="XXX_096",name="AI Buddy - Damage Own Hero 5",type="MINION",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text="Spawn into play to smack your own hero for 5."}
P["XXX_097"]={id="XXX_097",name="AI Buddy - Destroy Minions",type="MINION",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text="Spawn into play to destroy all minions."}
P["XXX_098"]={id="XXX_098",name="AI Buddy - No Deck/Hand",type="MINION",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text="Spawn into play to destroy the AI's Hand and Deck."}
P["XXX_099"]={id="XXX_099",name="AI Helper Buddy",type="MINION",set="CHEAT",rarity="FREE",class="NEUTRAL",cost=0,atk=1,hp=1,text="Get the AI ready for testing."}
P["ds1_whelptoken"]={id="ds1_whelptoken",name="Whelp",type="MINION",set="EXPERT1",rarity="FREE",class="NEUTRAL",cost=1,atk=1,hp=1,race="DRAGON",text=nil}
P["hexfrog"]={id="hexfrog",name="Frog",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=0,atk=0,hp=1,race="BEAST",keywords={"TAUNT"},text="<b>Taunt</b>"}
P["skele11"]={id="skele11",name="Skeleton",type="MINION",set="CORE",rarity="COMMON",class="NEUTRAL",cost=1,atk=1,hp=1,text="<b></b>"}
P["skele21"]={id="skele21",name="Damaged Golem",type="MINION",set="EXPERT1",rarity="COMMON",class="NEUTRAL",cost=1,atk=2,hp=1,race="MECHANICAL",dustHS={40,400,5,50},text=nil}
P["tt_004o"]={id="tt_004o",name="Cannibalize",type="ENCHANTMENT",set="EXPERT1",rarity="FREE",class="NEUTRAL",text="Increased Attack."}
P["tt_010a"]={id="tt_010a",name="Spellbender",type="MINION",set="EXPERT1",rarity="EPIC",class="MAGE",cost=0,atk=1,hp=3,dustHS={400,1600,100,400},text=nil}

