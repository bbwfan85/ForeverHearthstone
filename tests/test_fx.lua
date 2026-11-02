--[[ tests/test_fx.lua -- easing, timeline, and choreography.

  These tests are the reason the visual layer can be trusted before the beta
  lands. The choreographies run against a MOCK STAGE that records every call, so
  ordering, overlap, timing and escalation are all verified on a machine with no
  WoW installed. What cannot be tested here is whether a frame looks good -- only
  that the right things happen in the right order at the right times.
]]
local H = require("tests.harness")

-- ------------------------------------------------------------- mock stage

local function MockStage()
  local s = { calls = {}, sounds = {}, particles = {}, handles = {} }
  local function rec(what, ...)
    s.calls[#s.calls + 1] = { what = what, args = { ... } }
  end
  local function handle(tag)
    if s.handles[tag] then return s.handles[tag] end
    -- `last` is a SEPARATE table. Storing recorded values as h[name] would
    -- overwrite the method with a number on the first call.
    local h = { tag = tag, log = {}, last = {} }
    local function m(name)
      return function(_, ...)
        h.log[#h.log + 1] = name
        rec(tag .. ":" .. name, ...)
        h.last[name] = select(1, ...)
        return h
      end
    end
    for _, name in ipairs({ "Pos", "Scale", "Alpha", "Rot", "Flip", "Glow",
                            "Burst", "Shove", "Shake", "Flash", "Vignette",
                            "Shimmer", "Count", "Burn", "Urgency", "Rays" }) do
      h[name] = m(name)
    end
    s.handles[tag] = h
    return h
  end
  s.Card      = function(_, i) return handle("Card" .. tostring(i)) end
  s.Board     = function()     return handle("Board") end
  s.Hero      = function(_, x) return handle("Hero" .. tostring(x)) end
  s.Screen    = function()     return handle("Screen") end
  s.Toast     = function(_, k) return handle("Toast:" .. tostring(k)) end
  s.Sound     = function(_, key, n)
    s.sounds[#s.sounds + 1] = { key = key, step = n }; rec("Sound", key, n)
  end
  s.Particles = function(_, kind, x, y, n)
    s.particles[#s.particles + 1] = { kind = kind, n = n }; rec("Particles", kind, n)
  end
  function s:Count(what)
    local n = 0
    for _, c in ipairs(self.calls) do if c.what == what then n = n + 1 end end
    return n
  end
  function s:SoundKeys()
    local t = {}
    for i, x in ipairs(self.sounds) do t[i] = x.key end
    return table.concat(t, ",")
  end
  return s
end

--================================================================== easing

H.suite("fx: easing functions are well-formed", function(ns, H)
  local E = ns.Timeline.easing
  for _, name in ipairs({ "linear", "quadIn", "quadOut", "quadInOut",
                          "cubicIn", "cubicOut", "cubicInOut", "bounceOut" }) do
    H.eq(E[name](0), 0, name .. " starts at 0")
    local one = E[name](1)
    H.ok(math.abs(one - 1) < 1e-6, name .. " ends at 1 (got " .. one .. ")")
  end
  -- monotonic easings must never go backwards
  local prev = -1
  for i = 0, 20 do
    local v = E.quadOut(i / 20)
    H.ok(v >= prev - 1e-9, "quadOut is monotonic")
    prev = v
  end
end)

H.suite("fx: backOut overshoots past 1 then settles", function(ns, H)
  local E = ns.Timeline.easing
  -- The overshoot is the whole point: it is what gives a card weight when it
  -- lands. If this ever returns <= 1 everywhere, the snap has been lost.
  local peak = 0
  for i = 0, 100 do
    local v = E.backOut(i / 100)
    if v > peak then peak = v end
  end
  H.ok(peak > 1.02, "overshoots (peak " .. string.format("%.3f", peak) .. ")")
  H.ok(math.abs(E.backOut(1) - 1) < 1e-6, "settles exactly on 1")
end)

H.suite("fx: unknown easing name degrades to linear, never errors", function(ns, H)
  local f = ns.Timeline.Ease("nonexistent_easing")
  H.eq(f(0.5), 0.5, "fell back to linear")
end)

--================================================================ timeline

H.suite("fx: timeline fires one-shots in time order", function(ns, H)
  local tl = ns.Timeline.New("t")
  tl:At(0.30, "c"):At(0.10, "a"):At(0.20, "b")
  local fired = tl:RunAll(1 / 240)
  H.eq(table.concat(fired, ","), "a,b,c", "fired in time order despite declaration order")
end)

H.suite("fx: interpolation hits exactly 0 and exactly 1", function(ns, H)
  local seen = {}
  local tl = ns.Timeline.New("t")
  tl:Over(0, 0.25, "linear", "move", function(v) seen[#seen + 1] = v end)
  tl:RunAll(1 / 60)
  H.eq(seen[1], 0, "first sample is exactly 0")
  H.eq(seen[#seen], 1, "last sample is exactly 1")
  H.ok(#seen > 5, "sampled repeatedly in between (" .. #seen .. " samples)")
end)

H.suite("fx: duration is the furthest end, and Then appends", function(ns, H)
  local tl = ns.Timeline.New("t")
  tl:Over(0, 0.2, "linear", "a", function() end)
  tl:Then(0.3, "linear", "b", function() end)
  H.ok(math.abs(tl.duration - 0.5) < 1e-9, "duration 0.5 after Then")
  tl:At(0.9, "late")
  H.ok(math.abs(tl.duration - 0.9) < 1e-9, "duration follows the furthest beat")
end)

H.suite("fx: With(lead) actually overlaps rather than sequencing", function(ns, H)
  local tl = ns.Timeline.New("t")
  tl:Over(0, 0.40, "linear", "first", function() end)
  tl:With(0.15, 0.30, "linear", "second", function() end)
  -- second must start before first ends, or the sequence reads as a slideshow
  local secondStart
  for _, tr in ipairs(tl.tracks) do
    if tr.label == "second" then secondStart = tr.at end
  end
  H.ok(math.abs(secondStart - 0.25) < 1e-9, "second starts at 0.25, mid-first")
  H.ok(secondStart < 0.40, "genuinely overlapping")
end)

H.suite("fx: a timeline is deterministic across step sizes", function(ns, H)
  local function run(step)
    local tl = ns.Timeline.New("t")
    tl:At(0.1, "a"):At(0.2, "b"):At(0.3, "c")
    return table.concat(tl:RunAll(step), ",")
  end
  H.eq(run(1 / 60), "a,b,c", "60fps")
  H.eq(run(1 / 30), "a,b,c", "30fps -- same order")
  H.eq(run(1 / 144), "a,b,c", "144fps -- same order")
end)

--=========================================================== playing a card

H.suite("fx: PlayMinion -- board makes room BEFORE the card lands", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.PlayMinion(s, { cardIndex = 1, slot = 3,
                                             from = { x = -200, y = -180 },
                                             to = { x = 60, y = 0 } })
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("lift", "arc"),         "lift precedes the arc")
  H.ok(tl:FiredBefore("board_shove", "land"), "neighbours part before it lands")
  H.ok(tl:FiredBefore("land", "impact"),      "lands before impact")
  H.ok(tl:FiredBefore("impact", "impact_sound"),
       "visual impact leads the sound -- makes the hit feel causal")
  H.ok(s:Count("Board:Shove") > 1, "shove was interpolated, not snapped")

  -- The impact must actually be felt. (Found by mutation testing: zeroing the
  -- shake failed nothing, so "big visual payoffs on swings" was unverified.)
  local shake = 0
  for _, c in ipairs(s.calls) do
    if c.what == "Screen:Shake" then shake = math.max(shake, c.args[1] or 0) end
  end
  H.ok(shake > 0, "landing shakes the screen (" .. shake .. ")")
end)

H.suite("fx: a heavy minion lands harder than a light one", function(ns, H)
  local function land(heavy)
    local s = MockStage()
    ns.Choreography.PlayMinion(s, { heavy = heavy }):RunAll(1 / 120)
    local shake, snd = 0, nil
    for _, c in ipairs(s.calls) do
      if c.what == "Screen:Shake" then shake = math.max(shake, c.args[1] or 0) end
    end
    for _, x in ipairs(s.sounds) do if x.key:find("summon") then snd = x.key end end
    return shake, snd
  end
  local lightShake, lightSnd = land(false)
  local heavyShake, heavySnd = land(true)
  H.ok(lightShake > 0, "a normal minion still registers")
  H.ok(heavyShake > lightShake, "a heavy minion shakes harder")
  H.eq(lightSnd, "summon", "normal summon sound")
  H.eq(heavySnd, "summon_heavy", "heavy summon sound")
end)

H.suite("fx: PlayMinion -- battlecry resolves after the landing", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.PlayMinion(s, { battlecry = true,
                                             glow = { 1, 0.8, 0.2, 0.9 } })
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("land", "battlecry"),
       "cause reads before effect -- a battlecry mid-arc looks like a bug")
  H.ok(tl:FiredBefore("impact", "battlecry"), "after impact too")
  H.ok(s:Count("Card1:Glow") > 1, "keyword glow ramped")
end)

H.suite("fx: PlaySpell -- effect lands while the card is still dissolving", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.PlaySpell(s, { heavy = true })
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("rise", "burn"), "rises then burns")
  H.ok(tl:FiredBefore("burn", "effect"), "burn starts before the effect lands")
  -- overlap check: the burn track must still be running when effect fires
  local burnEnd, effectAt
  for _, tr in ipairs(tl.tracks) do
    if tr.label == "burn" then burnEnd = tr.at + tr.dur end
    if tr.label == "effect" then effectAt = tr.at end
  end
  H.ok(effectAt < burnEnd, "effect overlaps the dissolve rather than following it")
end)

H.suite("fx: Attack -- wind-up precedes the lunge", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.Attack(s, { dx = 0, dy = 140, lethal = true })
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("windup", "lunge"), "winds up first")
  H.ok(tl:FiredBefore("lunge", "impact"), "then connects")
  H.ok(tl:FiredBefore("impact", "recoil"), "then recoils")
  H.eq(s.sounds[1].key, "hit_lethal", "lethal hit uses the heavier sound")
end)

--===================================================== the on-kill pack drop

H.suite("fx: PackDropToast is brief, quiet and self-dismissing", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.PackDropToast(s, { total = 3 })
  tl:RunAll(1 / 120)

  -- It fires mid-combat in the open world, so it must not take focus.
  H.ok(tl.duration < 3.6, "under 3.6s total (" .. string.format("%.2f", tl.duration) .. ")")
  H.eq(s:Count("Screen:Shake"), 0, "NO screen shake -- player is fighting")
  H.eq(s:Count("Screen:Vignette"), 0, "no vignette")
  H.ok(tl:FiredBefore("slide_in", "counter"), "arrives before the counter ticks")
  H.ok(tl:FiredBefore("counter", "slide_out"), "and leaves on its own")
  H.eq(s:SoundKeys(), "pack_drop", "exactly one soft sound, no fanfare")
end)

H.suite("fx: a golden set-card drop is louder than a pack, still no shake", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.SetCardDropToast(s, { golden = true })
  tl:RunAll(1 / 120)
  H.eq(s:Count("Screen:Shake"), 0, "still no shake in the open world")
  H.ok(tl:FiredBefore("card_flourish", "golden_flourish"), "golden beat comes after")
  H.eq(s:SoundKeys(), "setcard_drop,golden_drop", "golden adds a sound")
  H.ok(tl.duration > ns.Choreography.PackDropToast(MockStage(), {}).duration,
       "lingers longer than a pack toast -- it is rarer")
end)

--============================================================= pack opening

H.suite("fx: PackCrack deals five cards, staggered", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.PackCrack(s, { count = 5 })
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("squash", "crack"), "winds up before bursting")
  for i = 1, 5 do
    H.ok(tl:FiredBefore("crack", "deal_" .. i), "card " .. i .. " deals after the crack")
  end
  -- staggered, not simultaneous: five objects, not one blur
  local t1, t5
  for _, tr in ipairs(tl.tracks) do
    if tr.label == "deal_1" then t1 = tr.at end
    if tr.label == "deal_5" then t5 = tr.at end
  end
  H.ok(t5 > t1, "cards are staggered")
  H.ok(t5 - t1 > 0.15, "stagger is perceptible (" .. string.format("%.2f", t5 - t1) .. "s)")
  H.eq(s:Count("Sound"), 6, "one crack + five deal sounds")
end)

H.suite("fx: no face-down card lights up on its own", function(ns, H)
  --[[ THE REPORT: "one of them (you're not even hovering) seems to flash a
       couple of times". The crack used to pulse the best card's glow three
       times. In Hearthstone the rarity shows only while you hover a card
       (CollectionUI:LayoutPack), so the crack has no glow beat at all. ]]
  for _, best in ipairs({ "COMMON", "RARE", "EPIC", "LEGENDARY" }) do
    local s = MockStage()
    local tl = ns.Choreography.PackCrack(s, { count = 5, bestRarity = best, tellIndex = 3 })
    tl:RunAll(1 / 120)
    local glows = 0
    for i = 1, 5 do glows = glows + s:Count("Card" .. i .. ":Glow") end
    H.eq(glows, 0, "a pack with a " .. best .. " flashes nothing unprompted")
    H.notOk(s:SoundKeys():find("rarity_tell", 1, true), "and plays no tell of its own")
  end
end)

H.suite("fx: epic and legendary throw rays as they turn; rare flares only", function(ns, H)
  local function rays(rarity)
    local s = MockStage()
    ns.Choreography.CardReveal(s, { rarity = rarity, step = 1 }):RunAll(1 / 120)
    return s:Count("Card1:Rays"), s:Count("Card1:Glow")
  end
  local rr, rg = rays("RARE"); local er = rays("EPIC"); local lr = rays("LEGENDARY"); local cr, cg = rays("COMMON")
  H.eq(rr, 0, "a rare has no rays"); H.ok(rg > 0, "but flares")
  H.ok(er > 0 and lr > 0, "epic and legendary have rays")
  H.eq(cr + cg, 0, "a common just turns over")
end)

H.suite("fx: reveal audio escalates across the five cards", function(ns, H)
  --[[ Peggle-style escalation. WoW cannot pitch-shift, so it is an ordered list
       of sounds indexed by reveal number. What is verified here is that the
       escalation STEP is passed through and increases. ]]
  local steps = {}
  for i = 1, 5 do
    local s = MockStage()
    ns.Choreography.CardReveal(s, { step = i, rarity = "COMMON" }):RunAll(1 / 120)
    for _, snd in ipairs(s.sounds) do
      if snd.key == "card_reveal" then steps[#steps + 1] = snd.step end
    end
  end
  H.eq(table.concat(steps, ","), "1,2,3,4,5", "escalation step rises per reveal")
end)

H.suite("fx: rarity drives the reveal payoff", function(ns, H)
  local function reveal(rarity)
    local s = MockStage()
    ns.Choreography.CardReveal(s, { rarity = rarity, step = 1 }):RunAll(1 / 120)
    local shake = 0
    for _, c in ipairs(s.calls) do
      if c.what == "Screen:Shake" then shake = math.max(shake, c.args[1] or 0) end
    end
    return s, shake
  end
  local sc, shC = reveal("COMMON")
  local sr, shR = reveal("RARE")
  local se, shE = reveal("EPIC")
  local sl, shL = reveal("LEGENDARY")

  H.eq(shC, 0, "common does not shake the screen")
  H.ok(shR > 0,     "rare does")
  H.ok(shE > shR,   "epic shakes harder than rare")
  H.ok(shL > shE,   "legendary hardest of all")
  H.eq(sc:Count("Particles"), 0, "common has no burst")
  H.ok(sl:Count("Particles") > 0, "legendary bursts")
  H.eq(sl:Count("Screen:Vignette") > 0, true, "legendary vignettes; nothing else does")
  H.eq(se:Count("Screen:Vignette"), 0, "epic does not vignette")
end)

H.suite("fx: legendary pauses before its fanfare", function(ns, H)
  -- The beat of silence between the burst and the sound is what makes it land.
  local s = MockStage()
  local tl = ns.Choreography.CardReveal(s, { rarity = "LEGENDARY", step = 5 })
  tl:RunAll(1 / 240)
  local burstAt, fanfareAt
  for _, tr in ipairs(tl.tracks) do
    if tr.label == "burst" then burstAt = tr.at end
    if tr.label == "legendary_fanfare" then fanfareAt = tr.at end
  end
  H.ok(fanfareAt > burstAt, "fanfare follows the burst")
  H.ok(fanfareAt - burstAt >= 0.05, "with a perceptible gap")
end)

H.suite("fx: the flip swaps the face at the midpoint, not the start", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.CardReveal(s, { rarity = "COMMON" })
  tl:RunAll(1 / 240)
  H.ok(tl:FiredBefore("flip_out", "swap_face"), "squashes before swapping")
  H.ok(tl:FiredBefore("swap_face", "flip_in"), "swaps before expanding")
  H.eq(s:Count("Card1:Flip"), 1, "the face swaps exactly once")
end)

H.suite("fx: golden cards shine regardless of rarity", function(ns, H)
  local s = MockStage()
  ns.Choreography.CardReveal(s, { rarity = "COMMON", golden = true, step = 1 })
    :RunAll(1 / 120)
  H.ok(s:Count("Card1:Glow") > 10, "golden shimmer runs even on a common")
  local keys = s:SoundKeys()
  H.ok(keys:find("golden_common", 1, true) ~= nil, "Hearthstone's golden stinger for its rarity")
end)

--============================================================== other moments

H.suite("fx: crafting gathers dust before it forges", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.Craft(s, {})
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("dust_gather", "forge"), "dust flows in first")
  H.ok(tl:FiredBefore("forge", "materialise"), "then the card forms")
end)

H.suite("fx: disenchant shatters then releases dust", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.Disenchant(s, {})
  tl:RunAll(1 / 120)
  H.ok(tl:FiredBefore("crack", "shatter"), "cracks before shattering")
  H.ok(tl:FiredBefore("shatter", "dust_out"), "dust leaves after the shatter")
end)

H.suite("fx: the rope escalates in three stages", function(ns, H)
  local s = MockStage()
  local tl = ns.Choreography.Rope(s, { seconds = 15 })
  tl:RunAll(1 / 60)
  local levels = {}
  for _, c in ipairs(s.calls) do
    if c.what == "Toast:rope:Urgency" then levels[c.args[1]] = true end
  end
  H.ok(levels[1] and levels[2] and levels[3], "all three urgency stages reached")
  H.ok(tl:FiredBefore("rope_appear", "rope_end"), "starts before it ends")
  H.ok(math.abs(tl.duration - 15) < 0.01, "matches the configured rope length")
end)

H.suite("fx: choreographies survive a stage that implements nothing", function(ns, H)
  --[[ A half-built UI must not crash the game. Every stage method is optional,
       so a choreography run against an empty table is a no-op, not an error. ]]
  local empty = {}
  local ok = true
  for _, fn in ipairs({ "PlayMinion", "PlaySpell", "Attack", "PackDropToast",
                        "SetCardDropToast", "PackCrack", "CardReveal",
                        "Craft", "Disenchant", "Rope" }) do
    local good = pcall(function()
      ns.Choreography[fn](empty, { count = 5, rarity = "LEGENDARY", seconds = 2 })
        :RunAll(1 / 60)
    end)
    if not good then ok = false; H.ok(false, fn .. " crashed on an empty stage") end
  end
  H.ok(ok, "all ten choreographies ran against a stage with no methods")
end)

H.suite("fx: choreographies survive a PARTIALLY implemented stage", function(ns, H)
  --[[ The gap the "implements nothing" test missed, and the real binding hit.

       An empty stage was safe because H() returned the null handle. But a stage
       that HAS `Toast` and returns a handle WITHOUT `Shimmer` crashed, because
       only stage-level methods were guarded, not the handles they return.
       (Found by running the real frame binding against the WoW stub:
       PackDropToast and Rope both broke.)

       So: a stage whose every method returns a bare empty table must still run
       every choreography. ]]
  local partial = {}
  for _, m in ipairs({ "Card", "Board", "Hero", "Screen", "Toast" }) do
    partial[m] = function() return {} end       -- handle with NO methods at all
  end
  partial.Sound = function() end
  partial.Particles = function() end

  local ok = true
  for _, fn in ipairs({ "PlayMinion", "PlaySpell", "Attack", "PackDropToast",
                        "SetCardDropToast", "PackCrack", "CardReveal",
                        "Craft", "Disenchant", "Rope" }) do
    local good, err = pcall(function()
      ns.Choreography[fn](partial, { count = 5, rarity = "LEGENDARY", seconds = 2,
                                     glow = { 1, 1, 1, 1 }, golden = true })
        :RunAll(1 / 60)
    end)
    if not good then
      ok = false
      H.ok(false, fn .. " crashed on a partial stage: " .. tostring(err))
    end
  end
  H.ok(ok, "all ten choreographies survived handles with no methods")
end)

H.suite("fx: a partial handle still chains", function(ns, H)
  -- Choreographies chain calls (c:Scale(1):Alpha(1)). A no-op stand-in must
  -- return something chainable or the second call indexes nil.
  local stage = { Card = function() return { Scale = function(s, v) s.scaled = v; return s end } end }
  local ok = pcall(function()
    ns.Choreography.PlayMinion(stage, { glow = { 1, 1, 1, 1 } }):RunAll(1 / 60)
  end)
  H.ok(ok, "mixed present/absent methods chain without error")
end)

H.suite("fx: targeted spells emit one projectile without an untargeted burst", function(ns,H)
  for _,targeted in ipairs({true,false}) do
    local projectiles,bursts=0,0
    local stage={Projectile=function() projectiles=projectiles+1 end,
      Particles=function() bursts=bursts+1 end}
    ns.Choreography.PlaySpell(stage,{targeted=targeted}):RunAll(1/120)
    H.eq(projectiles,targeted and 1 or 0)
    H.eq(bursts,targeted and 0 or 1)
  end
end)
