--[[ Client/FX/SpellFX.lua

  WHAT A SPELL LOOKS LIKE.

  Hearthstone gives nearly every spell its own effect: Fireball is a flaming
  ball that streaks at its target, Flamestrike rains fire on their side,
  Holy Nova rings out from your hero, Swipe claws across their board. Until
  this file every spell in the game was the same brief arcane puff.

  This is the DECISION only -- pure data, no WoW API, testable headless like
  the rest of Client/FX. Client/UI/Board.lua draws it (stage:SpellEffect).

  An effect is { kind, school, count, side, heavy, big }:

    kind    bolt      a projectile from the caster to the target
            missiles  `count` small bolts at random enemies (Arcane Missiles)
            beam      a jagged, flickering arc to the target; `count` > 1
                      forks to more enemies (Lightning Bolt, Forked Lightning)
            fan       one blade at every enemy minion at once (Fan of Knives)
            slash     `count` blade strokes across the target (Backstab)
            drain     a bolt out, then the life flowing back (Drain Life)
            sweep     a wave across one side of the board (Swipe, Cleave)
            rain      columns falling onto one side (Flamestrike, Blizzard)
            nova      a ring bursting out from the caster (Holy Nova)
            bloom     a heal rising from the target (Holy Light)
            glow      a buff settling onto the target, or with side = "self"
                      onto every friendly minion (Savage Roar, Bloodlust)
            swirl     motes circling in on the target: a transformation
                      or a mind taken (Polymorph, Hex, Mind Control)
            shield    a ring closing around the target (Power Word: Shield)
            secret    a sigil drawn into the caster's hero (every Secret)
            summon    a flash where new minions appear (Mirror Image)
    school  fire frost arcane holy shadow nature lightning orb (physical)
    side    "foe" / "self" / "all" -- which board a sweep, rain, nova or
            glow covers
    heavy   the impact rings out and shakes the table (SpellFX.Impact)

  Nearly every collectible spell and every basic hero power is mapped by
  hand; anything else is inferred from the card's school and rules text.
]]
local ADDON, ns = ...

local SpellFX = {}
ns.SpellFX = SpellFX

local function e(kind, school, extra)
  local t = { kind = kind, school = school }
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end

SpellFX.CARDS = {
  -- Mage
  CS2_029 = e("bolt", "fire", { heavy = true }),              -- Fireball
  CS2_024 = e("bolt", "frost"),                                -- Frostbolt
  EX1_277 = e("missiles", "arcane", { count = 3 }),            -- Arcane Missiles
  CS2_032 = e("rain", "fire", { side = "foe", heavy = true }), -- Flamestrike
  CS2_028 = e("rain", "frost", { side = "foe" }),              -- Blizzard
  CS2_026 = e("nova", "frost", { side = "foe" }),              -- Frost Nova
  CS2_025 = e("nova", "arcane", { side = "foe" }),             -- Arcane Explosion
  EX1_279 = e("bolt", "fire", { heavy = true, big = true }),   -- Pyroblast
  EX1_275 = e("bolt", "frost"),                                -- Cone of Cold
  CS2_031 = e("bolt", "frost"),                                -- Ice Lance
  CS2_023 = e("glow", "arcane"),                               -- Arcane Intellect
  CS2_022 = e("swirl", "arcane"),                              -- Polymorph
  CS2_027 = e("summon", "arcane"),                             -- Mirror Image
  -- Priest
  CS1_112 = e("nova", "holy", { side = "all" }),               -- Holy Nova
  CS1_130 = e("bolt", "holy"),                                 -- Holy Smite
  DS1_233 = e("bolt", "shadow", { heavy = true }),             -- Mind Blast
  CS2_234 = e("bolt", "shadow"),                               -- Shadow Word: Pain
  EX1_622 = e("bolt", "shadow"),                               -- Shadow Word: Death
  CS2_004 = e("shield", "holy"),                               -- Power Word: Shield
  EX1_621 = e("nova", "holy", { side = "all" }),               -- Circle of Healing
  EX1_624 = e("bolt", "holy"),                                 -- Holy Fire
  CS1_113 = e("swirl", "shadow", { heavy = true }),            -- Mind Control
  -- Paladin
  CS2_093 = e("rain", "holy", { side = "foe" }),               -- Consecration
  CS2_094 = e("bolt", "holy"),                                 -- Hammer of Wrath
  CS2_089 = e("bloom", "holy"),                                -- Holy Light
  CS2_092 = e("glow", "holy"),                                 -- Blessing of Kings
  CS2_087 = e("glow", "holy"),                                 -- Blessing of Might
  EX1_384 = e("missiles", "holy", { count = 8 }),              -- Avenging Wrath
  EX1_354 = e("bloom", "holy"),                                -- Lay on Hands
  EX1_619 = e("nova", "holy", { side = "all" }),               -- Equality
  -- Warlock
  CS2_062 = e("nova", "fire", { side = "all", heavy = true }), -- Hellfire
  CS2_057 = e("bolt", "shadow"),                               -- Shadow Bolt
  EX1_308 = e("bolt", "fire"),                                 -- Soulfire
  EX1_302 = e("bolt", "shadow"),                               -- Mortal Coil
  CS2_061 = e("drain", "shadow"),                              -- Drain Life
  EX1_312 = e("nova", "shadow", { side = "all", heavy = true }), -- Twisting Nether
  CS2_063 = e("glow", "shadow"),                               -- Corruption
  EX1_309 = e("drain", "shadow", { heavy = true }),            -- Siphon Soul
  EX1_303 = e("sweep", "shadow", { side = "foe" }),            -- Shadowflame
  -- Druid
  CS2_008 = e("bolt", "arcane"),                               -- Moonfire
  EX1_173 = e("bolt", "arcane", { heavy = true }),             -- Starfire
  CS2_012 = e("sweep", "nature", { side = "foe" }),            -- Swipe
  EX1_154 = e("bolt", "nature"),                               -- Wrath
  CS2_007 = e("bloom", "nature"),                              -- Healing Touch
  NEW1_007 = e("rain", "arcane", { side = "foe" }),            -- Starfall
  EX1_169 = e("glow", "nature"),                               -- Innervate
  CS2_009 = e("glow", "nature"),                               -- Mark of the Wild
  CS2_011 = e("glow", "nature", { side = "self" }),            -- Savage Roar
  -- Shaman
  EX1_238 = e("beam", "lightning"),                            -- Lightning Bolt
  EX1_259 = e("rain", "lightning", { side = "foe" }),          -- Lightning Storm
  CS2_037 = e("bolt", "frost"),                                -- Frost Shock
  EX1_245 = e("bolt", "nature"),                               -- Earth Shock
  CS2_046 = e("glow", "fire", { side = "self" }),              -- Bloodlust
  EX1_246 = e("swirl", "nature"),                              -- Hex
  EX1_251 = e("beam", "lightning", { count = 2 }),             -- Forked Lightning
  -- Hunter
  DS1_185 = e("bolt", "arcane"),                               -- Arcane Shot
  DS1_183 = e("missiles", "orb", { count = 2 }),               -- Multi-Shot
  EX1_537 = e("bolt", "fire", { heavy = true }),               -- Explosive Shot
  EX1_539 = e("bolt", "nature"),                               -- Kill Command
  CS2_084 = e("glow", "arcane"),                               -- Hunter's Mark
  EX1_538 = e("summon", "nature"),                             -- Unleash the Hounds
  -- Warrior
  EX1_400 = e("nova", "orb", { side = "all" }),                -- Whirlwind
  CS2_108 = e("slash", "orb", { heavy = true }),               -- Execute
  CS2_114 = e("sweep", "orb", { side = "foe" }),               -- Cleave
  EX1_407 = e("nova", "orb", { side = "all", heavy = true }),  -- Brawl
  CS2_105 = e("glow", "orb"),                                  -- Heroic Strike
  EX1_391 = e("slash", "orb"),                                 -- Slam
  -- Rogue
  CS2_072 = e("slash", "orb"),                                 -- Backstab
  EX1_124 = e("slash", "orb", { count = 2, heavy = true }),    -- Eviscerate
  CS2_075 = e("slash", "orb"),                                 -- Sinister Strike
  CS2_233 = e("sweep", "orb", { side = "foe" }),               -- Blade Flurry
  EX1_129 = e("fan", "orb"),                                   -- Fan of Knives
  CS2_076 = e("slash", "shadow", { heavy = true }),            -- Assassinate
  EX1_581 = e("swirl", "shadow"),                              -- Sap
  EX1_278 = e("bolt", "orb"),                                  -- Shiv
  CS2_074 = e("glow", "nature"),                               -- Deadly Poison
  -- ---------------------------------------------- the rest of the pool
  -- Druid
  CS2_005 = e("glow", "nature"),                               -- Claw
  CS2_013 = e("glow", "nature"),                               -- Wild Growth
  EX1_155 = e("glow", "nature"),                               -- Mark of Nature
  EX1_158 = e("glow", "nature", { side = "self" }),            -- Soul of the Forest
  EX1_160 = e("glow", "nature", { side = "self" }),            -- Power of the Wild
  EX1_161 = e("swirl", "nature"),                              -- Naturalize
  EX1_164 = e("glow", "nature"),                               -- Nourish
  EX1_570 = e("glow", "nature"),                               -- Bite
  EX1_571 = e("summon", "nature", { count = 3 }),              -- Force of Nature
  EX1_578 = e("slash", "nature", { heavy = true }),            -- Savagery
  GVG_031 = e("swirl", "nature"),                              -- Recycle
  GVG_033 = e("nova", "nature", { side = "all" }),             -- Tree of Life
  GVG_041 = e("glow", "nature"),                               -- Dark Wispers
  FP1_019 = e("rain", "nature", { side = "all", heavy = true }), -- Poison Seeds
  -- Hunter
  DS1_184 = e("glow", "orb"),                                  -- Tracking
  NEW1_031 = e("summon", "nature"),                            -- Animal Companion
  EX1_544 = e("nova", "fire", { side = "all" }),               -- Flare
  EX1_549 = e("glow", "fire"),                                 -- Bestial Wrath
  EX1_617 = e("missiles", "orb", { count = 1, minions = true, heavy = true }), -- Deadly Shot
  GVG_017 = e("glow", "nature"),                               -- Call Pet
  GVG_026 = e("glow", "shadow", { side = "self" }),            -- Feign Death
  GVG_073 = e("bolt", "orb", { heavy = true }),                -- Cobra Shot
  -- Mage
  GVG_001 = e("missiles", "fire", { count = 1, minions = true, heavy = true }), -- Flamecannon
  GVG_003 = e("swirl", "arcane"),                              -- Unstable Portal
  GVG_005 = e("glow", "arcane", { side = "self" }),            -- Echo of Medivh
  -- Paladin
  EX1_360 = e("swirl", "holy"),                                -- Humility
  EX1_371 = e("shield", "holy"),                               -- Hand of Protection
  EX1_349 = e("glow", "holy"),                                 -- Divine Favor
  EX1_355 = e("glow", "holy"),                                 -- Blessed Champion
  EX1_363 = e("glow", "holy"),                                 -- Blessing of Wisdom
  EX1_365 = e("bolt", "holy", { heavy = true }),               -- Holy Wrath
  GVG_057 = e("bloom", "holy"),                                -- Seal of Light
  GVG_061 = e("summon", "holy", { count = 3 }),                -- Muster for Battle
  -- Priest
  CS2_003 = e("glow", "shadow"),                               -- Mind Vision
  CS2_236 = e("glow", "holy"),                                 -- Divine Spirit
  CS1_129 = e("glow", "holy"),                                 -- Inner Fire
  EX1_332 = e("swirl", "holy"),                                -- Silence
  EX1_334 = e("swirl", "shadow"),                              -- Shadow Madness
  EX1_339 = e("glow", "shadow"),                               -- Thoughtsteal
  EX1_345 = e("summon", "shadow"),                             -- Mindgames
  EX1_625 = e("nova", "shadow", { side = "self", heavy = true }), -- Shadowform
  EX1_626 = e("nova", "holy", { side = "foe" }),               -- Mass Dispel
  GVG_008 = e("nova", "holy", { side = "all", heavy = true }), -- Lightbomb
  GVG_010 = e("glow", "holy"),                                 -- Velen's Chosen
  GVG_012 = e("bloom", "holy"),                                -- Light of the Naaru
  -- Rogue
  CS2_077 = e("glow", "orb"),                                  -- Sprint
  NEW1_004 = e("nova", "shadow", { side = "all" }),            -- Vanish
  CS2_073 = e("glow", "orb"),                                  -- Cold Blood
  EX1_126 = e("slash", "shadow"),                              -- Betrayal
  EX1_128 = e("glow", "shadow", { side = "self" }),            -- Conceal
  EX1_137 = e("slash", "orb"),                                 -- Headcrack
  EX1_144 = e("swirl", "shadow"),                              -- Shadowstep
  EX1_145 = e("glow", "shadow"),                               -- Preparation
  GVG_022 = e("glow", "orb"),                                  -- Tinker's Sharpsword Oil
  GVG_047 = e("missiles", "shadow", { count = 1, minions = true, heavy = true }), -- Sabotage
  -- Shaman
  CS2_039 = e("glow", "lightning"),                            -- Windfury
  CS2_041 = e("bloom", "nature"),                              -- Ancestral Healing
  CS2_045 = e("glow", "nature"),                               -- Rockbiter Weapon
  EX1_244 = e("glow", "nature", { side = "self" }),            -- Totemic Might
  CS2_038 = e("glow", "nature"),                               -- Ancestral Spirit
  CS2_053 = e("glow", "arcane"),                               -- Far Sight
  EX1_241 = e("bolt", "fire", { heavy = true, big = true }),   -- Lava Burst
  EX1_248 = e("summon", "nature", { count = 2 }),              -- Feral Spirit
  GVG_029 = e("summon", "nature", { count = 2 }),              -- Ancestor's Call
  GVG_038 = e("beam", "lightning", { heavy = true }),          -- Crackle
  FP1_025 = e("swirl", "nature"),                              -- Reincarnate
  -- Warlock
  NEW1_003 = e("drain", "shadow"),                             -- Sacrificial Pact
  EX1_316 = e("glow", "shadow"),                               -- Power Overwhelming
  EX1_317 = e("glow", "shadow"),                               -- Sense Demons
  EX1_320 = e("bolt", "shadow"),                               -- Bane of Doom
  EX1_596 = e("bolt", "fire"),                                 -- Demonfire
  GVG_015 = e("bolt", "shadow", { heavy = true }),             -- Darkbomb
  GVG_019 = e("bolt", "shadow", { heavy = true, big = true }), -- Demonheart
  GVG_045 = e("bolt", "fire", { heavy = true }),               -- Imp-losion
  -- Warrior
  CS2_103 = e("glow", "orb"),                                  -- Charge
  EX1_606 = e("shield", "orb"),                                -- Shield Block
  CS2_104 = e("glow", "orb"),                                  -- Rampage
  EX1_392 = e("glow", "orb"),                                  -- Battle Rage
  EX1_408 = e("slash", "orb", { heavy = true }),               -- Mortal Strike
  EX1_409 = e("glow", "orb"),                                  -- Upgrade!
  EX1_410 = e("slash", "orb", { heavy = true }),               -- Shield Slam
  EX1_607 = e("slash", "orb"),                                 -- Inner Rage
  NEW1_036 = e("glow", "orb", { side = "self" }),              -- Commanding Shout
  GVG_050 = e("missiles", "orb", { count = 4, minions = true }), -- Bouncing Blade
  GVG_052 = e("slash", "orb", { heavy = true }),               -- Crush
  -- The nine basic hero powers
  CS2_034 = e("bolt", "fire"),                                 -- Fireblast
  CS1h_001 = e("bloom", "holy"),                               -- Lesser Heal
  DS1h_292 = e("bolt", "orb"),                                 -- Steady Shot
  CS2_056 = e("glow", "shadow"),                               -- Life Tap
  CS2_102 = e("shield", "orb"),                                -- Armor Up!
  CS2_083b = e("glow", "orb"),                                 -- Dagger Mastery
  CS2_101 = e("summon", "holy"),                               -- Reinforce
  CS2_049 = e("summon", "nature"),                             -- Totemic Call
  CS2_017 = e("glow", "nature"),                               -- Shapeshift
}

-- Sounds.EffectFor's audio schools, as visual ones.
local SCHOOL_OF = { fire = "fire", frost = "frost", arcane = "arcane", holy = "holy",
                    shadow = "shadow", nature = "nature", arrow = "orb", weapon = "orb", spell = "arcane" }

-- A Secret glows in its class's colour, as Hearthstone's question marks do.
SpellFX.SECRET_SCHOOL = { MAGE = "arcane", HUNTER = "nature", PALADIN = "holy" }

--[[ The effect for a card. `targeted` says whether this cast has a target,
     which is what separates a bolt from an area effect when inferring. ]]
function SpellFX.For(cardId, targeted)
  local fixed = cardId and SpellFX.CARDS[cardId]
  if fixed then return fixed end
  local printed = ns.PrintedCards and cardId and ns.PrintedCards[cardId]
  local school = SCHOOL_OF[ns.Sounds and ns.Sounds.EffectFor and ns.Sounds.EffectFor(cardId) or "spell"] or "arcane"
  local text = (printed and printed.text or ""):lower():gsub("<[^>]+>", "")
  if text:find("^%s*secret:") then
    return e("secret", SpellFX.SECRET_SCHOOL[printed.class] or school)
  end
  if targeted then
    if text:find("^%s*restore") then return e("bloom", school) end
    if text:find("transform") or text:find("gain control") then return e("swirl", school) end
    if text:find("deal") or text:find("destroy") then return e("bolt", school) end
    return e("glow", school)
  end
  if text:find("all enemy minions") or text:find("all enemies") or text:find("enemy characters") then
    return e("rain", school, { side = "foe" })
  end
  if text:find("all minions") or text:find("all characters") then
    return e("nova", school, { side = "all" })
  end
  if text:find("random enemy minion") then
    return e("missiles", school, { count = 1, minions = true })
  end
  if text:find("summon") then return e("summon", school) end
  if text:find("restore") then return e("bloom", school) end
  if text:find("your minions") or text:find("your characters") then
    return e("glow", school, { side = "self" })
  end
  return e("glow", school)
end

--[[ HOW AN EFFECT LANDS. A heavy spell rings out and shakes the table the
     moment it hits -- not on a fixed beat of the cast, which is what used to
     make Pyroblast's shake (when it happened at all) arrive before the ball.
     `shake` is Widgets.Shake's amplitude in pixels; `ring` an expanding
     shockwave (fx-ring); `sparks` the particle count thrown out. ]]
function SpellFX.Impact(spec)
  spec = spec or {}
  local heavy, big = spec.heavy and true or false, spec.big and true or false
  return {
    shake = big and 7 or heavy and 4 or 0,
    ring = heavy or big,
    sparks = big and 40 or heavy and 28 or 16,
  }
end

--[[ HOW EACH SCHOOL'S PARTICLES MOVE (Widgets.Burst reads this by kind).
     One gravity for everything made every spell's sparks the same falling
     confetti; each element has its own weight:

       gravity  px/s^2, positive falls, negative rises
       speed    { min, max } launch speed
       life     { min, max } seconds
       grow     size multiplier reached at the end of life (smoke swells)
       spark    drawn with the four-point sparkle (fx-spark) instead of a glow ]]
SpellFX.MOTION = {
  fire      = { gravity = -150, speed = { 30, 110 },  life = { 0.45, 0.85 }, grow = 0.4 },
  frost     = { gravity = 420,  speed = { 70, 180 },  life = { 0.40, 0.70 }, spark = true },
  arcane    = { gravity = 30,   speed = { 50, 150 },  life = { 0.45, 0.80 }, spark = true },
  holy      = { gravity = -70,  speed = { 25, 95 },   life = { 0.60, 1.00 }, spark = true },
  shadow    = { gravity = -80,  speed = { 20, 70 },   life = { 0.70, 1.10 }, grow = 2.2 },
  nature    = { gravity = 110,  speed = { 30, 90 },   life = { 0.70, 1.10 } },
  lightning = { gravity = 0,    speed = { 140, 280 }, life = { 0.15, 0.35 }, spark = true },
  -- the pack reveal's rarity bursts: glints that drift up and linger
  burst_blue   = { gravity = -60, speed = { 60, 200 },  life = { 0.6, 1.1 }, spark = true },
  burst_purple = { gravity = -60, speed = { 70, 230 },  life = { 0.7, 1.2 }, spark = true },
  burst_gold   = { gravity = -50, speed = { 80, 280 },  life = { 0.8, 1.5 }, spark = true },
}

-- Particle colours per school (Widgets.W.Burst kinds carry the same names).
SpellFX.COLOURS = {
  fire = { 1, 0.55, 0.15 }, frost = { 0.55, 0.85, 1 }, arcane = { 0.8, 0.45, 1 },
  holy = { 1, 0.9, 0.5 }, shadow = { 0.6, 0.25, 0.9 }, nature = { 0.45, 0.95, 0.35 },
  lightning = { 0.65, 0.8, 1 }, orb = { 1, 0.95, 0.8 },
}

return SpellFX
