--[[ Client/FX/Choreography.lua

  THE JUICE, AS DATA.

  Each function here builds a Timeline against a `stage` interface. The stage is
  whatever can actually draw -- Client/UI supplies the real one backed by frames
  and AnimationGroups; tests supply a mock that just records calls. So the FEEL
  of the game (ordering, overlap, timing, escalation) is designed and verified
  headless, and the WoW layer underneath stays dumb.

  THE STAGE INTERFACE (all methods optional -- missing ones are no-ops, so a
  partial UI implementation still runs the whole choreography):

    stage:Card(i)         -> handle with :Pos(x,y) :Scale(s) :Alpha(a)
                             :Rot(radians) :Flip() :Glow(r,g,b,a) :Burst(kind)
    stage:Board()         -> handle with :Shove(slot, amount)
    stage:Hero(side)      -> handle with :Shake(amount) :Flash(r,g,b,a)
    stage:Screen()        -> handle with :Shake(amount) :Vignette(a)
    stage:Sound(key, n)      play sound `key`; n = escalation step
    stage:Toast(kind, data)  transient corner notification
    stage:Particles(kind, x, y, n)

  TIMING PHILOSOPHY -- the numbers below are deliberate, not arbitrary:

    * Nothing important is faster than ~120ms. Below that the eye registers a
      jump, not a motion, and the game feels twitchy rather than weighty.
    * Everything overlaps. A sequence where each beat waits for the last reads as
      a slideshow. `With(lead, ...)` exists for exactly this.
    * Impact comes BEFORE the sound's peak, not after. A frame or two of visual
      lead makes a hit feel like it caused the sound.
    * Escalation is per-reveal, not per-pack. Rising pitch across five cards is
      the single cheapest trick for making a pack feel like an event.

  PEGGLE NOTE: the escalation the brief asks for depends on pitch-shifting, which
  WoW cannot do. So it is faked with an ORDERED LIST of distinct sounds in the
  manifest, indexed by reveal number. Absent entries are silent, and silence is a
  valid render -- same discipline as the icons.
]]
local ADDON, ns = ...
local Timeline = ns.Timeline

local Cho = {}
ns.Choreography = Cho

--[[ Null-object stage: every call is a no-op, so a choreography can run against a
     half-built UI without nil checks scattered through the timings.

     IMPORTANT: this must be null-safe at BOTH levels. Guarding only the stage's
     own methods is not enough -- a stage that implements `Toast` but returns a
     handle without `Shimmer` used to crash. (Found by running the real binding
     against the frame stub: PackDropToast and Rope both broke.) So a returned
     handle is wrapped too, and any method it lacks becomes a no-op that still
     returns the handle so calls can chain. ]]
local NULLH = setmetatable({}, { __index = function() return function() end end })

local function wrapHandle(h)
  if not h then return NULLH end
  return setmetatable({}, {
    __index = function(_, k)
      local fn = h[k]
      if type(fn) == "function" then
        return function(_, ...) return fn(h, ...) end
      end
      -- missing method: no-op that keeps the chain alive
      return function(selfProxy) return selfProxy end
    end,
  })
end

local function H(stage, method, ...)
  if not stage or not stage[method] then return NULLH end
  return wrapHandle(stage[method](stage, ...))
end
local function call(stage, method, ...)
  if stage and stage[method] then stage[method](stage, ...) end
end

-- ============================================================ playing a card

--[[ Play a minion from hand to a board slot.

     Beats: lift -> arc -> board makes room -> land (overshoot) -> impact ->
     glow. The board shove STARTS BEFORE the card lands, which is what sells the
     minion pushing its neighbours apart rather than teleporting between them. ]]
function Cho.PlayMinion(stage, opts)
  local card  = H(stage, "Card", opts.cardIndex or 1)
  local board = H(stage, "Board")
  local slot  = opts.slot or 1
  local from  = opts.from or { x = 0, y = -200 }
  local to    = opts.to   or { x = 0, y = 0 }
  if stage and stage.PlayDestination then
    local destination = stage:PlayDestination(slot, opts.mine)
    if destination then from = { x = 0, y = 0 }; to = destination end
  end

  local tl = Timeline.New("PlayMinion")

  -- 1. lift out of the hand, slight scale up: "picked up"
  tl:Over(0, 0.12, "quadOut", "lift", function(v)
    card:Scale(1.0 + 0.18 * v)
    card:Alpha(1)
  end)

  -- 2. arc to the slot. Horizontal eases out, vertical overshoots -- a straight
  --    lerp here is the single most common reason card games feel cheap.
  tl:Over(0.10, 0.26, "cubicOut", "arc", function(v)
    card:Pos(from.x + (to.x - from.x) * v, from.y + (to.y - from.y) * v)
  end)
  tl:Over(0.10, 0.26, "linear", "arc_rot", function(v)
    card:Rot((1 - v) * (opts.tilt or 0.12))
  end)

  -- 3. neighbours make room, overlapping the arc
  tl:Over(0.18, 0.20, "quadOut", "board_shove", function(v)
    board:Shove(slot, v, opts.mine)
  end)

  -- 4. land with an overshoot, then settle
  tl:Over(0.36, 0.16, "backOut", "land", function(v)
    if not (stage and stage.MorphMinion) then card:Scale(1.18 - 0.18 * v) end
  end)
  tl:Over(0.28, 0.18, "quadOut", "portrait", function(v)
    call(stage,"MorphMinion",v,slot,opts.mine,opts.instanceId)
  end)

  -- 5. impact: particles and shake fire a frame BEFORE the sound
  tl:At(0.46, "impact", function()
    if stage and stage.LandingImpact then stage:LandingImpact()
    else call(stage, "Particles", "summon_dust", to.x, to.y, 12) end
    call(stage,"Impact")
    H(stage, "Screen"):Shake(opts.heavy and 1.5 or 0.25)
  end)
  tl:At(0.48, "impact_sound", function()
    call(stage, "Sound", opts.heavy and "summon_heavy" or "summon")
  end)

  -- 6. keyword glow, if the minion arrives with something worth announcing
  if opts.glow then
    tl:Over(0.48, 0.30, "quadOut", "glow", function(v)
      local c = opts.glow
      card:Glow(c[1], c[2], c[3], v * (c[4] or 0.8))
    end)
  end

  -- 7. battlecry gets its own beat AFTER the landing, so cause reads before
  --    effect. A battlecry that fires during the arc looks like a bug.
  if opts.battlecry then
    tl:At(0.56, "battlecry", function() call(stage, "Sound", "battlecry") end)
  end

  return tl
end

--- Cast a spell: card rises, burns away, effect lands on the target.
function Cho.HeroPower(stage, opts)
  local tl = Timeline.New("HeroPower")
  tl:At(0, "power", function()
    if stage and stage.PowerSound then stage:PowerSound(opts.mine) else call(stage,"Sound","spell_cast") end
    -- The power's own effect (Fireblast's flame, Lesser Heal's bloom) when the
    -- stage can draw one; otherwise the generic bolt.
    if stage and stage.SpellEffect then
      local o = {}; for k, v in pairs(opts) do o[k] = v end; o.power = true
      stage:SpellEffect(o)
    else
      call(stage, "Projectile", opts.mine, opts.targetSide, opts.targetIndex, opts.targetIsHero, opts.targeted, true)
    end
  end)
  tl:At(0.32,"impact",function() call(stage,"Impact") end)
  return tl
end

function Cho.PlaySpell(stage, opts)
  local card = H(stage, "Card", opts.cardIndex or 1)
  local tl = Timeline.New("PlaySpell")

  tl:Over(0, 0.14, "quadOut", "rise", function(v)
    card:Scale(1 + 0.25 * v)
    card:Pos(0, (opts.mine == false and -60 or 60) * v)
  end)
  tl:Over(0.14, 0.18, "quadIn", "burn", function(v)
    card:Alpha(1 - v)
    card:Glow(1, 0.85, 0.35, 1 - v)
  end)
  -- Each spell's own effect (Client/FX/SpellFX.lua) where the stage draws
  -- them; a stage without SpellEffect keeps the generic bolt and puff.
  local drawn = stage and stage.SpellEffect ~= nil
  tl:At(0.12, "projectile", function()
    if drawn then stage:SpellEffect(opts)
    elseif opts.targeted then
      call(stage, "Projectile", opts.mine, opts.targetSide, opts.targetIndex, opts.targetIsHero, true)
    end
  end)
  tl:At(0.20, "cast_sound", function() call(stage, "Sound", "spell_cast") end)
  -- the effect lands while the card is still dissolving: overlap, not sequence
  tl:At(0.26, "effect", function()
    if not opts.targeted then
      call(stage,"Impact")
      if not drawn then call(stage, "Particles", opts.effect or "arcane", opts.tx or 0, opts.ty or 0, 20) end
    end
    if opts.heavy then H(stage, "Screen"):Shake(2) end
  end)
  if opts.targeted then tl:At(0.43,"damage",function() call(stage,"Impact") end) end
  if opts.heavy then
    tl:Over(0.26, 0.24, "quadOut", "vignette", function(v)
      H(stage, "Screen"):Vignette(0.35 * (1 - v))
    end)
  end
  return tl
end

--[[ WHO A BEAT IS ABOUT.

     `stage:Card(i)` indexes the HAND. A minion needs a side as well as an
     index, because "board minion 1" is a different widget depending on whose
     board it is -- and the attack sequence used Card() for both, so an enemy
     attack animated one of YOUR minions, or, with an empty board, one of your
     hand cards. Heroes have their own handle and no index at all. ]]
local function actor(stage, side, index, isHero)
  if isHero then return H(stage, "Hero", side or "foe") end
  if side then return H(stage, "Minion", side, index or 1) end
  return H(stage, "Card", index or 1)
end

--[[ A THING DYING.

     Hearthstone does not fade a dead minion out, it breaks it: the portrait
     bursts, the board shakes, and the pieces are gone before you have finished
     reading them. A fade reads as a rendering glitch -- something disappearing
     for no reason -- which is exactly what a minion quietly vanishing at 30%
     alpha looked like.

     Added to `tl` at `at` so a death can overlap the recoil it caused rather
     than queueing behind it. ]]
local function deathBeat(tl, stage, who, at, label, heavy)
  tl:At(at, label .. "_burst", function()
    who:Burst("shatter")
    call(stage, "Particles", "shatter", 0, 0, heavy and 26 or 16)
    H(stage, "Screen"):Shake(heavy and 7 or 3.5)
  end)
  tl:Over(at, 0.30, "quadIn", label, function(v)
    --[[ Puffs UP before it goes, rather than shrinking away. The scale-up is
         what makes it read as breaking apart instead of receding. ]]
    who:Scale(1 + 0.35 * v)
    who:Alpha(1 - v)
    who:Glow(1, 0.85, 0.6, (1 - v) * 0.7)
  end)
  tl:At(at + 0.04, label .. "_sound", function()
    call(stage, "Sound", "minion_death")
  end)
end

--[[ A MINION'S TRIGGER FIRED. It swells and glows gold for a moment and
     plays its trigger recording (stage:TriggerSound), so a Knife Juggler's
     knife or Ragnaros's shot visibly comes FROM that minion. `at` staggers
     several triggers after the action that set them off. ]]
function Cho.AbilityEffect(stage, opts)
  -- Capture coordinates now, before Impact redraws and reuses board widgets.
  local point = stage and stage.EffectPoint and stage:EffectPoint(opts)
  local tl = Timeline.New("AbilityEffect")
  tl:At(opts.at or 0.48, "ability", function()
    if point then call(stage, "AbilityBurst", point, opts.kind) end
    if opts.kind == "deathrattle" then
      call(stage, "Sound", "minion_death")
      call(stage, "TriggerSound", opts.cardId)
    elseif opts.kind == "battlecry" then call(stage, "Sound", "battlecry") end
    call(stage, "Impact")
  end)
  return tl
end

function Cho.MinionTrigger(stage, opts)
  local who = actor(stage, opts.side or "self", opts.index or 1, false)
  local at = opts.at or 0.3
  local tl = Timeline.New("MinionTrigger")
  tl:At(at, "trigger", function()
    call(stage, "TriggerSound", opts.cardId)
    who:Burst("hit_spark")
  end)
  tl:Over(at, 0.32, "quadOut", "pulse", function(v)
    local swell = math.sin(math.pi * v)
    who:Scale(1 + 0.12 * swell)
    who:Glow(1, 0.82, 0.3, 0.9 * swell)
  end)
  return tl
end

--[[ A HERO IS DESTROYED.

     Hearthstone does not fade the losing hero: the portrait cracks, glows from
     inside while the cracks spread, then bursts into pieces with a heavy
     boom -- and only then does Victory or Defeat appear. Played by the board
     for ANY cause of death (a swing, Fireball, fatigue), which is why it is
     not part of Attack. ~1.4s; the board holds the result banner until it ends.

     stage:Hero(side) -> handle with :Crack(amount 0..1) :Shatter() :Flash() ]]
function Cho.HeroDeath(stage, opts)
  local side = opts and opts.side or "foe"
  local hero = H(stage, "Hero", side)
  local tl = Timeline.New("HeroDeath")
  tl:At(0, "crack", function()
    hero:Crack(0.3)
    call(stage, "Sound", "hero_crack")
    H(stage, "Screen"):Shake(2)
  end)
  tl:At(0.08, "voice", function() call(stage, "ActorSound", "death", side, nil, true) end)
  tl:Over(0.05, 0.85, "quadIn", "cracking", function(v)
    hero:Crack(0.3 + 0.7 * v)
    hero:Flash(1, 0.75, 0.3, 0.2 + 0.6 * v)
    if v > 0.5 then H(stage, "Screen"):Shake(1 + 3 * v) end
  end)
  tl:At(0.9, "shatter", function()
    hero:Shatter()
    hero:Flash(1, 0.8, 0.4, 0)
    call(stage, "Sound", "hero_shatter")
    call(stage, "Sound", "big_hit")
    hero:Burst("shatter")
    H(stage, "Screen"):Shake(9)
  end)
  tl:Over(0.9, 0.5, "quadOut", "flash", function(v)
    H(stage, "Screen"):Vignette(0.4 * (1 - v))
  end)
  return tl
end

--[[ Attack: wind up, lunge, impact, recoil -- and then whatever died.

     opts:
       attackerSide/attackerIndex   "self" or "foe", plus the board slot
       defenderSide/defenderIndex   same for what is being hit
       defenderIsHero               a hero has a handle and no index
       attackerDied / defenderDied  drive the death beats

     The sides are the whole point. Without them every attack in the game --
     including every one the practice opponent made -- animated a widget on
     YOUR side of the table, which is why an enemy swing looked like nothing at
     all happening while your health silently dropped. ]]
function Cho.Attack(stage, opts)
  local a = actor(stage, opts.attackerSide, opts.attackerIndex, opts.attackerIsHero)
  local d = actor(stage, opts.defenderSide, opts.defenderIndex, opts.defenderIsHero)
  local tl = Timeline.New("Attack")
  tl:At(0,"attack_voice",function()
    call(stage,"ActorSound","attack",opts.attackerSide,opts.attackerIndex,opts.attackerIsHero)
  end)
  --[[ THE LUNGE GOES AT THE THING IT IS HITTING.

       This used to be a fixed offset straight up or down, so a minion attacking
       across the board lunged at empty table and one going face stopped short
       of the hero. The stage is asked for the real distance -- it is the only
       thing that knows where the widgets are -- and the fixed offset stays as
       the fallback for a stage that cannot answer, which is what the mock in
       tests/test_fx.lua is.

       It travels most of the way rather than all of it: an attacker that lands
       exactly on its target covers the thing it is meant to be hitting, and the
       hit reads better as a meeting than as an overlap. ]]
  local dx, dy = opts.dx or 0, opts.dy or 120
  if stage and stage.Delta then
    local rdx, rdy = stage:Delta(opts.attackerSide, opts.attackerIndex,
                                 opts.defenderSide, opts.defenderIndex,
                                 opts.defenderIsHero, opts.attackerIsHero)
    if rdx then dx, dy = rdx * 0.72, rdy * 0.72 end
  end

  tl:Over(0, 0.10, "quadOut", "windup", function(v)
    a:Pos(-dx * 0.18 * v, -dy * 0.18 * v)     -- pull back away from the target
  end)
  tl:Over(0.10, 0.12, "cubicIn", "lunge", function(v)
    a:Pos(dx * (-0.18 + 1.18 * v), dy * (-0.18 + 1.18 * v))
  end)
  tl:At(0.21, "impact", function()
    call(stage,"Impact")
    call(stage, "Particles", "hit_spark", opts.tx or 0, opts.ty or 0, 10)
    H(stage, "Screen"):Shake(opts.lethal and 6 or 3)
    call(stage, "Sound", opts.lethal and "hit_lethal" or "hit")
    --[[ The DEFENDER flinches. A hit where only the attacker moves reads as the
         attacker having a seizure next to an indifferent target. ]]
    d:Burst("impact")
  end)
  tl:Over(0.21, 0.16, "quadOut", "flinch", function(v)
    d:Pos(dx * 0.10 * (1 - v), dy * 0.10 * (1 - v))
  end)
  tl:Over(0.22, 0.18, "quadOut", "recoil", function(v)
    a:Pos(dx * (1 - v), dy * (1 - v))
  end)

  --[[ Deaths overlap the recoil. The defender goes first even when both die,
       because the defender dying is the consequence of the hit and the
       attacker dying is the consequence of the trade. ]]
  -- A hero's death is its own sequence (HeroDeath, run by the board whatever
  -- killed it), so a lethal swing at the face ends on the impact.
  if opts.defenderDied and not opts.defenderIsHero then
    tl:At(0.32,"defender_voice",function() call(stage,"ActorSound","death",opts.defenderSide,opts.defenderIndex,opts.defenderIsHero) end)
    deathBeat(tl, stage, d, 0.28, "death", opts.defenderIsHero)
  end
  if opts.attackerDied and not opts.attackerIsHero then
    tl:At(0.38,"attacker_voice",function() call(stage,"ActorSound","death",opts.attackerSide,opts.attackerIndex,opts.attackerIsHero) end)
    deathBeat(tl, stage, a, 0.34, "attacker_death", false)
  end
  return tl
end

-- ================================================== pack drop on a mob kill

--[[ THE ON-KILL PACK DROP.

     This one has a hard constraint the rest do not: it fires in the OPEN WORLD,
     while the player is fighting. It must be noticeable and then get out of the
     way. It must never take focus, never play over combat sounds loudly, and
     never cover the action bar or nameplates.

     So: a corner toast, a short flourish, ~2.5s total, no screen shake, no
     vignette, no click required. The pack is banked silently; opening it is a
     separate deliberate act at the player's choosing, which is what makes the
     opening a moment rather than an interruption. ]]
function Cho.PackDropToast(stage, opts)
  local tl = Timeline.New("PackDropToast")
  local t = H(stage, "Toast", "pack", opts)

  -- slide in from the edge with an overshoot: reads as "arrived", not "appeared"
  tl:Over(0, 0.28, "backOut", "slide_in", function(v)
    t:Pos(0, (1 - v) * 180)
    t:Alpha(v)
  end)
  tl:At(0.10, "drop_sound", function()
    -- deliberately a soft chime, not a fanfare: this fires mid-combat
    call(stage, "Sound", "pack_drop")
  end)
  -- a single sparkle pass over the pack icon
  tl:Over(0.28, 0.45, "quadInOut", "shimmer", function(v)
    t:Shimmer(v)
  end)
  -- the banked-pack counter ticks up, so the reward is legible at a glance
  tl:At(0.34, "counter", function() t:Count(opts.total or 1) end)

  -- hold long enough to be read mid-fight, then leave without being asked
  tl:Over(3.00, 0.45, "quadIn", "slide_out", function(v)
    t:Pos(0, v * 180)
    t:Alpha(1 - v)
  end)
  return tl
end

--[[ A set-trigger drop (kill yetis -> Yeti card) is louder than a pack, because
     it is rarer and tied to what the player just did. Still no screen shake. ]]
function Cho.SetCardDropToast(stage, opts)
  local tl = Timeline.New("SetCardDropToast")
  local t = H(stage, "Toast", "setcard", opts)
  tl:Over(0, 0.30, "backOut", "slide_in", function(v)
    t:Pos(0, (1 - v) * 180); t:Alpha(v)
  end)
  tl:At(0.12, "drop_sound", function() call(stage, "Sound", "setcard_drop") end)
  tl:At(0.32, "card_flourish", function()
    call(stage, "Particles", "card_motes", 0, 0, 10)
  end)
  if opts.golden then
    tl:At(0.40, "golden_flourish", function()
      call(stage, "Particles", "golden_sparkle", 0, 0, 18)
      call(stage, "Sound", "golden_drop")
    end)
  end
  tl:Over(3.60, 0.45, "quadIn", "slide_out", function(v)
    t:Pos(0, v * 180); t:Alpha(1 - v)
  end)
  return tl
end

-- ============================================================= pack opening

--[[ PACK OPENING -- the deliberate moment.

     Structure, matching Hearthstone's shape:
       1. the pack sits centre, breathing, waiting for a click
       2. crack: burst, and five cards fan out FACE DOWN
       3. the player flips them, individually or all at once
       4. each flip escalates the audio one step
       5. rarity drives the reveal burst; legendary gets the full payoff

     The anticipation is the important bit of feel, and in Hearthstone it is
     the PLAYER's: a face-down card glows in its rarity's colour (with its
     rarity's sound) while the pointer is over it, and never on its own. This
     used to pulse the best card three times as the pack landed, which read
     as a card flashing by itself. The hover glow lives with the screen
     (CollectionUI:LayoutPack); the pack's `tellIndex` is still where it
     points. ]]
function Cho.PackCrack(stage, opts)
  local tl = Timeline.New("PackCrack")
  local pack = H(stage, "Card", 0)          -- index 0 is the pack itself
  local n = opts.count or 5

  -- wind up: the pack pulls in slightly before bursting outward
  tl:Over(0, 0.14, "quadIn", "squash", function(v)
    pack:Scale(1 - 0.12 * v)
  end)
  tl:At(0.14, "crack", function()
    call(stage, "Sound", "pack_crack")
    call(stage, "Particles", "pack_burst", 0, 0, 40)
    H(stage, "Screen"):Shake(5)
  end)
  tl:Over(0.14, 0.18, "quadOut", "pack_vanish", function(v)
    pack:Scale(0.88 + 0.6 * v)
    pack:Alpha(1 - v)
  end)

  -- five cards fan out, staggered so they read as five objects not one blur
  for i = 1, n do
    local delay = 0.16 + (i - 1) * 0.055
    local spread = (i - (n + 1) / 2)
    tl:Over(delay, 0.34, "backOut", "deal_" .. i, function(v)
      local c = H(stage, "Card", i)
      c:Pos(spread * 130 * v, -10 * v)
      c:Rot(spread * 0.07 * v)
      c:Scale(0.6 + 0.4 * v)
      c:Alpha(v)
    end)
    tl:At(delay + 0.02, "deal_sound_" .. i, function()
      call(stage, "Sound", "card_deal", i)
    end)
  end

  return tl
end

--[[ One card flipping over. `step` is the reveal index 1..5 and drives the audio
     escalation; `rarity` drives the payoff. ]]
function Cho.CardReveal(stage, opts)
  local tl = Timeline.New("CardReveal")
  local c = H(stage, "Card", opts.cardIndex or 1)
  local rarity = opts.rarity or "COMMON"
  local step = opts.step or 1

  -- the flip: squash to zero width, swap the face, expand back
  tl:Over(0, 0.11, "quadIn", "flip_out", function(v) c:Scale(1 - v, 1) end)
  tl:At(0.11, "swap_face", function() c:Flip() end)
  tl:Over(0.11, 0.15, "backOut", "flip_in", function(v) c:Scale(v, 1) end)

  -- escalating pitch, faked as an ordered sound list indexed by reveal number
  tl:At(0.12, "reveal_sound", function() call(stage, "Sound", "card_reveal", step) end)

  local BURST = {
    FREE      = nil,
    COMMON    = nil,
    RARE      = { kind = "burst_blue",   shake = 2, hold = 0.35 },
    EPIC      = { kind = "burst_purple", shake = 4, hold = 0.50 },
    LEGENDARY = { kind = "burst_gold",   shake = 8, hold = 0.90 },
  }
  local b = BURST[rarity]
  if b then
    tl:At(0.24, "burst", function()
      call(stage, "Particles", b.kind, 0, 0, rarity == "LEGENDARY" and 60 or 25)
      H(stage, "Screen"):Shake(b.shake)
      -- a golden card has its own stinger (below) INSTEAD of the plain one
      if not opts.golden then call(stage, "Sound", "rarity_" .. string.lower(rarity)) end
    end)
    local g = (rarity == "LEGENDARY") and { 1, 0.75, 0.2 }
           or (rarity == "EPIC")      and { 0.7, 0.3, 1 }
           or { 0.3, 0.6, 1 }
    -- the card's own light flares and fades as it turns
    tl:Over(0.24, b.hold + 0.3, "quadOut", "rarity_glow", function(v)
      c:Glow(g[1], g[2], g[3], (1 - v) * 0.95)
    end)
    -- epic and legendary throw rays of light out from behind it
    if rarity ~= "RARE" then
      tl:Over(0.2, b.hold + 0.7, "linear", "rarity_rays", function(v)
        c:Rays(g[1], g[2], g[3], v, rarity == "LEGENDARY" and 1.35 or 1)
      end)
    end
  end

  -- LEGENDARY gets the full treatment: vignette, sustained shake, a beat of
  -- silence before the sound. The pause is what makes it land.
  if rarity == "LEGENDARY" then
    tl:Over(0.24, 0.70, "quadOut", "legendary_vignette", function(v)
      H(stage, "Screen"):Vignette(0.5 * (1 - v))
    end)
    if not opts.golden then
      tl:At(0.30, "legendary_fanfare", function() call(stage, "Sound", "legendary") end)
    end
  end

  -- golden cards animate regardless of rarity: they are the drop-only chase
  if opts.golden then
    tl:Over(0.24, 1.10, "linear", "golden_shine", function(v)
      c:Glow(1, 0.9, 0.4, (math.sin(v * math.pi * 4) * 0.5 + 0.5) * 0.7)
    end)
    -- Hearthstone's golden stinger is one per rarity.
    tl:At(0.26, "golden_sound", function()
      call(stage, "Sound", "golden_" .. string.lower(rarity))
    end)
  end
  return tl
end

-- ================================================================ crafting

function Cho.Craft(stage, opts)
  local tl = Timeline.New("Craft")
  local c = H(stage, "Card", opts.cardIndex or 1)
  tl:Over(0, 0.35, "quadInOut", "dust_gather", function(v)
    call(stage, "Particles", "dust_inflow", 0, 0, math.floor(30 * v))
    c:Glow(0.45, 0.8, 1, v * 0.9)
  end)
  tl:At(0.35, "forge", function()
    call(stage, "Sound", "craft")
    H(stage, "Screen"):Shake(3)
  end)
  tl:Over(0.35, 0.30, "backOut", "materialise", function(v) c:Scale(0.5 + 0.5 * v) end)
  tl:Over(0.45, 0.40, "quadOut", "settle", function(v) c:Glow(0.45, 0.8, 1, (1 - v) * 0.9) end)
  return tl
end

function Cho.Disenchant(stage, opts)
  local tl = Timeline.New("Disenchant")
  local c = H(stage, "Card", opts.cardIndex or 1)
  tl:Over(0, 0.22, "quadIn", "crack", function(v) c:Scale(1 - 0.1 * v) end)
  tl:At(0.22, "shatter", function()
    call(stage, "Particles", "shatter", 0, 0, 35)
    call(stage, "Sound", "disenchant")
  end)
  tl:Over(0.22, 0.30, "quadOut", "dissolve", function(v) c:Alpha(1 - v) end)
  tl:Over(0.30, 0.40, "quadOut", "dust_out", function(v)
    call(stage, "Particles", "dust_outflow", 0, 0, math.floor(25 * (1 - v)))
  end)
  return tl
end

-- ================================================================= the rope

--[[ Turn timer. The rope is a burn, not a bar -- it exists to raise pressure.
     Escalation is in three stages so the player feels the deadline arriving
     rather than reading a number. ]]
function Cho.Rope(stage, opts)
  local tl = Timeline.New("Rope")
  local dur = opts.seconds or ns.RULES.ROPE_SECONDS
  local rope = H(stage, "Toast", "rope", opts)
  tl:At(0, "rope_appear", function() call(stage, "Sound", "rope_start") end)
  tl:Over(0, dur, "linear", "burn", function(v)
    rope:Burn(v)
    if v > 0.66 then rope:Urgency(3)
    elseif v > 0.33 then rope:Urgency(2)
    else rope:Urgency(1) end
  end)
  tl:At(dur, "rope_end", function() call(stage, "Sound", "rope_end") end)
  return tl
end

return Cho
