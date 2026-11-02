--[[ Client/FX/Timeline.lua

  CHOREOGRAPHY AS TESTABLE DATA.

  WHY NOT JUST AnimationGroups:

  WoW's AnimationGroups are good at what they do -- a fade, a translate, a scale
  run on the C side, smoothly, with no per-frame Lua. We keep them for exactly
  that. What they are bad at is ORCHESTRATION: "lift the card, arc it to slot 3
  while the board shoves apart, land it 40ms before the impact flash, start the
  glow on the third frame of the flash, and if the minion has Charge overlay a
  second flash". Expressing that in nested OnFinished callbacks is how animation
  code becomes unmaintainable.

  So the split is:
    * TIMELINE (this file)  -- WHEN things happen. Pure logic, no WoW API,
                               fully unit-testable, deterministic.
    * BINDING (Client/UI/)  -- WHAT they do to a frame. Thin, starts/stops
                               AnimationGroups and sets values.

  That means the juice is designed and verified here, in tests, on a machine with
  no WoW installed -- which is the only reason any of it can be trusted before
  the beta lands.

  TIME IS IN SECONDS and advanced by an injected delta, never by GetTime(), so a
  test can step 16ms at a time and assert exact frames.
]]
local ADDON, ns = ...

local Timeline = {}
Timeline.__index = Timeline
ns.Timeline = Timeline

-- =================================================================== easing

--[[ Easing functions take t in [0,1] and return the eased fraction.

     `backOut` overshoots past 1 and settles -- that overshoot is most of what
     makes a card feel like it has weight when it snaps into a slot. `bounceOut`
     and `elasticOut` are for payoff moments (legendary reveal), used sparingly:
     everything bouncing reads as noise rather than emphasis. ]]
local E = {}
Timeline.easing = E

E.linear   = function(t) return t end
E.quadIn   = function(t) return t * t end
E.quadOut  = function(t) return 1 - (1 - t) * (1 - t) end
E.quadInOut= function(t)
  if t < 0.5 then return 2 * t * t end
  return 1 - 2 * (1 - t) * (1 - t)
end
E.cubicIn  = function(t) return t * t * t end
E.cubicOut = function(t) local f = 1 - t; return 1 - f * f * f end
E.cubicInOut = function(t)
  if t < 0.5 then return 4 * t * t * t end
  local f = 2 * t - 2
  return 0.5 * f * f * f + 1
end

-- overshoot: s controls how far past the target it travels
E.backOut = function(t, s)
  s = s or 1.70158
  local f = t - 1
  return 1 + f * f * ((s + 1) * f + s)
end
E.backIn = function(t, s)
  s = s or 1.70158
  return t * t * ((s + 1) * t - s)
end

E.elasticOut = function(t)
  if t == 0 or t == 1 then return t end
  local p = 0.3
  return 2 ^ (-10 * t) * math.sin((t - p / 4) * (2 * math.pi) / p) + 1
end

E.bounceOut = function(t)
  local n, d = 7.5625, 2.75
  if t < 1 / d then return n * t * t end
  if t < 2 / d then t = t - 1.5 / d;  return n * t * t + 0.75 end
  if t < 2.5 / d then t = t - 2.25 / d; return n * t * t + 0.9375 end
  t = t - 2.625 / d
  return n * t * t + 0.984375
end

--- Resolve an easing name or function to a function. Unknown names fall back to
--- linear rather than erroring, so a typo in a choreography degrades gracefully.
function Timeline.Ease(e)
  if type(e) == "function" then return e end
  return E[e or "linear"] or E.linear
end

-- ================================================================= timeline

function Timeline.New(name)
  return setmetatable({
    name = name or "timeline",
    t = 0, duration = 0, running = false, finished = false,
    tracks = {},     -- { at=, dur=, ease=, fn=, fired=, label= }
    fired = {},      -- labels fired, in order -- what tests assert on
    onDone = nil,
  }, Timeline)
end

--- Fire a one-shot at `at` seconds. `label` is what tests read.
function Timeline:At(at, label, fn)
  self.tracks[#self.tracks + 1] = { at = at, dur = 0, label = label, fn = fn }
  if at > self.duration then self.duration = at end
  return self
end

--- Interpolate from `at` for `dur` seconds. `fn(v, t)` receives the eased value
--- and the raw fraction. Called at least once at t=0 and exactly once at t=1.
function Timeline:Over(at, dur, ease, label, fn)
  self.tracks[#self.tracks + 1] = {
    at = at, dur = dur, ease = Timeline.Ease(ease), label = label, fn = fn,
  }
  if at + dur > self.duration then self.duration = at + dur end
  return self
end

--- Append a segment starting where the timeline currently ends. Convenience for
--- writing choreographies as a readable sequence rather than absolute offsets.
function Timeline:Then(dur, ease, label, fn)
  return self:Over(self.duration, dur, ease, label, fn)
end

--- Overlap: start `lead` seconds BEFORE the current end. Negative lead delays.
--- Overlapping is what stops a sequence feeling like separate steps.
function Timeline:With(lead, dur, ease, label, fn)
  local at = self.duration - (lead or 0)
  if at < 0 then at = 0 end
  return self:Over(at, dur, ease, label, fn)
end

function Timeline:Start()
  self.running, self.finished, self.t = true, false, 0
  self.fired = {}
  for _, tr in ipairs(self.tracks) do tr.fired = false; tr.done = false end
  return self
end

--[[ Advance by dt. Returns true while still running.

     Ordering within a tick is by track declaration order, not by `at`, so a
     choreography's source order is its tie-break. That keeps it deterministic
     and readable: if two things happen at 0.20s, the one written first runs
     first. ]]
--[[ ONE BROKEN CUE MUST NOT STOP THE SHOW. A track's function runs every
     frame from an OnUpdate; if it throws, the error used to fire again on
     every frame and nothing after it in the timeline ever ran -- including the
     onDone that unlocks the board. So a failing track is reported once
     (through WoW's error handler, which shows it without breaking anything)
     and then dropped, and the rest of the timeline carries on. ]]
local function runTrack(tr, ...)
  local ok, err = pcall(tr.fn, ...)
  if not ok then
    tr.fn = nil
    local handler = rawget(_G, "geterrorhandler")
    if handler then pcall(handler(), ("timeline cue %s: %s"):format(tostring(tr.label), tostring(err))) end
  end
end

function Timeline:Tick(dt)
  if not self.running then return false end
  self.t = self.t + (dt or 0)

  for _, tr in ipairs(self.tracks) do
    if tr.dur == 0 then
      if not tr.fired and self.t >= tr.at then
        tr.fired = true
        self.fired[#self.fired + 1] = tr.label
        if tr.fn then runTrack(tr) end
      end
    else
      local raw = (self.t - tr.at) / tr.dur
      if raw >= 0 and not tr.done then
        if not tr.fired then
          tr.fired = true
          self.fired[#self.fired + 1] = tr.label
          if tr.fn then runTrack(tr, tr.ease(0), 0) end
        end
        if raw >= 1 then
          tr.done = true
          if tr.fn then runTrack(tr, tr.ease(1), 1) end
        else
          if tr.fn then runTrack(tr, tr.ease(raw), raw) end
        end
      end
    end
  end

  if self.t >= self.duration then
    self.running, self.finished = false, true
    if self.onDone then self.onDone() end
  end
  return self.running
end

--- Run to completion in fixed steps. Tests use this; so does a skip button.
function Timeline:RunAll(step)
  step = step or 1 / 60
  self:Start()
  local guard = 0
  while self.running do
    guard = guard + 1
    if guard > 100000 then break end
    self:Tick(step)
  end
  return self.fired
end

--- Did `label` fire before `other`? The core assertion for choreography tests.
function Timeline:FiredBefore(label, other)
  local a, b
  for i, l in ipairs(self.fired) do
    if l == label and not a then a = i end
    if l == other and not b then b = i end
  end
  return a ~= nil and b ~= nil and a < b
end

return Timeline
