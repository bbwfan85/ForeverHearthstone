--[[ tests/wowstub.lua

  A STRICT MOCK OF THE WOW UI API, so Client/UI/ can run headless.

  WHAT THIS CATCHES (a large fraction of real addon bugs):
    * calling a frame method that does not exist  -> nil-method error in game
    * misspelled event names                     -> handler never fires, silently
    * registering an event and never handling it, or vice versa
    * handler signature mistakes
    * leaking globals
    * arithmetic on a nil size or position
    * creating frames in a loop and never reusing them (pooling bugs)

  WHAT IT CANNOT CATCH: anchoring correctness, strata, appearance, performance.
  Those need the real client. The stub is the pre-flight check, not the flight.

  STRICTNESS IS THE POINT. Any method not explicitly modelled raises an error
  naming the frame type and method, because that is precisely what WoW does and
  precisely the mistake we want to find before launching the game. Widening the
  stub is a deliberate act: if the real API has the method, add it here with the
  right return shape.

  API SURFACE TARGET: Mainline / interface 16001 (see docs/07). That means
  SetResizeBounds, NOT the removed SetMinResize/SetMaxResize; C_ChatInfo.*, not
  the Classic globals.
]]

local Stub = {}

-- Everything the stub creates is recorded here so tests can assert on it.
local function newRecorder()
  return { frames = {}, textures = {}, fontstrings = {}, animations = {},
           events = {}, sounds = {}, timers = {}, calls = {}, chat = {} }
end

local R = newRecorder()
Stub.R = R

local function rec(what, ...)
  R.calls[#R.calls + 1] = { what = what, args = { ... } }
end

-- ------------------------------------------------------------ strict objects

--[[ Build an object whose methods are `methods`, and which errors informatively
     on anything else. `kind` appears in the error so a failure names the widget
     type that lacked the method. ]]
local function strict(kind, methods, self)
  self = self or {}
  self.__kind = kind
  return setmetatable(self, {
    __index = function(t, k)
      local m = methods[k]
      if m then return m end
      error(("%s has no method %q -- if the real Mainline API has it, add it to tests/wowstub.lua")
            :format(kind, tostring(k)), 3)
    end,
  })
end

-- ------------------------------------------------------------------ textures

local textureMethods = {}
local function newTexture(parent, layer)
  local t = { parent = parent, layer = layer, shown = true,
              w = 0, h = 0, points = {}, colour = nil, texture = nil, atlas = nil }
  R.textures[#R.textures + 1] = t
  local regions = type(parent) == "table" and rawget(parent, "regions")
  if regions then regions[#regions + 1] = t end
  return strict("Texture", textureMethods, t)
end

textureMethods.SetTexture     = function(s, p)
  -- A solid colour is not a vertex tint: giving the texture a file replaces it.
  if p and rawget(s, "solid") then s.solid = false; s.colour = nil end
  s.texture = p; rec("Texture:SetTexture", p); return s
end
--[[ rawget, because the strict metatable treats an ABSENT field as a missing
     method and errors. A texture that was never given a path is the normal case
     -- it is exactly what "this card has no art" looks like -- so asking must
     return nil rather than blowing up. ]]
textureMethods.GetTexture     = function(s) return rawget(s, "texture") end
textureMethods.SetAtlas       = function(s, a) s.atlas = a; rec("Texture:SetAtlas", a); return s end
textureMethods.GetAtlas       = function(s) return s.atlas end
textureMethods.SetTexCoord    = function(s, ...) s.texcoord = { ... }; return s end
textureMethods.SetVertexColor = function(s, r, g, b, a) s.colour = { r, g, b, a }; return s end
textureMethods.GetVertexColor = function(s) local c = s.colour or {1,1,1,1}; return c[1],c[2],c[3],c[4] end
textureMethods.SetColorTexture= function(s, r, g, b, a) s.colour = { r, g, b, a }; s.solid = true; return s end
textureMethods.SetAllPoints   = function(s, rel) s.allPoints = rel or true; return s end
textureMethods.SetPoint       = function(s, ...) s.points[#s.points+1] = { ... }; return s end
textureMethods.ClearAllPoints = function(s) s.points = {}; s.allPoints = nil; return s end
textureMethods.SetSize        = function(s, w, h) s.w, s.h = w, h; return s end
textureMethods.SetWidth       = function(s, w) s.w = w; return s end
textureMethods.SetHeight      = function(s, h) s.h = h; return s end
textureMethods.GetWidth       = function(s) return s.w end
textureMethods.GetHeight      = function(s) return s.h end
textureMethods.Show           = function(s) s.shown = true; return s end
textureMethods.Hide           = function(s) s.shown = false; return s end
textureMethods.SetShown       = function(s, v) s.shown = not not v; return s end
textureMethods.IsShown        = function(s) return s.shown end
textureMethods.SetAlpha       = function(s, a) s.alpha = a; return s end
textureMethods.GetAlpha       = function(s) return s.alpha or 1 end
textureMethods.SetDrawLayer   = function(s, l) s.layer = l; return s end
textureMethods.SetRotation    = function(s, r) s.rotation = r; return s end
textureMethods.SetBlendMode   = function(s, m) s.blend = m; return s end
textureMethods.SetDesaturated = function(s, d) s.desaturated = d; return s end
textureMethods.IsDesaturated = function(s) return rawget(s, "desaturated") and true or false end
textureMethods.AddMaskTexture = function(s, m) s.mask = m; return s end
textureMethods.SetSnapToPixelGrid = function(s, v) s.snap = v; return s end
textureMethods.SetTexelSnappingBias = function(s, v) s.snapBias = v; return s end
textureMethods.GetObjectType  = function() return "Texture" end
textureMethods.SetVertexOffset = function(s, i, x, y) s.vertices = rawget(s, "vertices") or {}; s.vertices[i] = {x,y}; return s end

-- --------------------------------------------------------------- fontstrings

local fsMethods = {}
local function newFontString(parent, layer)
  local f = { parent = parent, layer = layer, text = "", shown = true, points = {} }
  R.fontstrings[#R.fontstrings + 1] = f
  local regions = type(parent) == "table" and rawget(parent, "regions")
  if regions then regions[#regions + 1] = f end
  return strict("FontString", fsMethods, f)
end

fsMethods.SetText        = function(s, t)
  assert(rawget(s, "font"), "FontString:SetText(): Font not set")
  s.text = tostring(t or ""); return s
end
fsMethods.GetText        = function(s) return s.text end
fsMethods.GetParent      = function(s) return rawget(s, "parent") end
fsMethods.GetObjectType  = function() return "FontString" end
fsMethods.SetFormattedText = function(s, fmt, ...) s.text = fmt:format(...); return s end
fsMethods.SetFont        = function(s, f, h, fl) s.font = { f, h, fl }; return s end
fsMethods.GetFont        = function(s) local f = s.font or {"Fonts\\FRIZQT__.TTF", 12, ""}; return f[1],f[2],f[3] end
fsMethods.SetTextColor   = function(s, r, g, b, a) s.colour = { r, g, b, a }; return s end
-- In the client a FontString's alpha is part of its text colour: after
-- SetAlpha(0), GetTextColor reads back alpha 0. Modelled so code that copies a
-- hidden label's colour is caught here, not in game.
fsMethods.GetTextColor = function(s) local c = rawget(s, "colour") or {1, 1, 1, 1}; return c[1], c[2], c[3], (c[4] or 1) * (rawget(s, "alpha") or 1) end
fsMethods.SetJustifyH    = function(s, j) s.justifyH = j; return s end
fsMethods.GetJustifyH    = function(s) return s.justifyH or "CENTER" end
fsMethods.SetJustifyV    = function(s, j) s.justifyV = j; return s end
fsMethods.SetPoint       = function(s, ...) s.points[#s.points+1] = { ... }; return s end
fsMethods.ClearAllPoints = function(s) s.points = {}; return s end
fsMethods.GetPoint       = function(s, i) local p = s.points[i or 1]; if p then return unpack(p) end end
fsMethods.SetAllPoints   = function(s, rel) s.allPoints = rel or true; return s end
fsMethods.SetSize        = function(s, w, h) s.w, s.h = w, h; return s end
fsMethods.SetWidth       = function(s, w) s.w = w; return s end
fsMethods.SetHeight      = function(s, h) s.h = h; return s end
--[[ A deterministic glyph model: each character is 0.5 of the font size wide
     and a line is 1.2 sizes tall. Like WoW, once a width is set the measured
     width is CLIPPED to it and a set height clips the measured height -- which
     is exactly the trap that made the old shrink-to-fit loops dead code, so the
     stub must reproduce it for tests/test_textfit.lua to mean anything. ]]
local function fsSize(s) return (rawget(s,"font") and s.font[2]) or 12 end
--[[ Characters the client actually draws: colour codes (|cAARRGGBB, |r) take
     no room, and an inline texture (|T...|t) is counted as one glyph. ]]
local function visibleLen(text)
  text = tostring(text or "")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "#")
  return #text
end
Stub.VisibleLen = visibleLen
local function fsUnbounded(s) return visibleLen(s.text) * fsSize(s) * 0.5 end
fsMethods.GetUnboundedStringWidth = function(s) return fsUnbounded(s) end
fsMethods.GetStringWidth = function(s)
  local u = fsUnbounded(s)
  if (rawget(s,"w") or 0) > 0 then return math.min(u, s.w) end
  return u
end
fsMethods.GetStringHeight = function(s)
  if s.text == "" then return 0 end
  local lines = 1
  if rawget(s,"wordWrap") ~= false and (rawget(s,"w") or 0) > 0 then
    lines = math.max(1, math.ceil(fsUnbounded(s) / s.w))
  end
  local hgt = lines * fsSize(s) * 1.2
  if (rawget(s,"h") or 0) > 0 then return math.min(hgt, s.h) end
  return hgt
end
fsMethods.SetMaxLines    = function(s, n) s.maxLines = n; return s end
fsMethods.GetWidth       = function(s) return rawget(s,"w") or fsUnbounded(s) end
fsMethods.GetHeight      = function(s) return rawget(s,"h") or fsSize(s) * 1.2 end
fsMethods.Show           = function(s) s.shown = true; return s end
fsMethods.Hide           = function(s) s.shown = false; return s end
fsMethods.SetShown       = function(s, v) s.shown = not not v; return s end
fsMethods.IsShown        = function(s) return s.shown end
fsMethods.SetAlpha       = function(s, a) s.alpha = a; return s end
--[[ Region:GetAlpha exists on Mainline for every region type, FontStrings
     included. It was missing here, so asserting on a hidden label errored in
     the test rather than in the game -- which is the stub working, but only
     once someone tried. ]]
fsMethods.GetAlpha       = function(s) return rawget(s, "alpha") or 1 end
fsMethods.SetShadowOffset= function(s) return s end
fsMethods.SetShadowColor = function(s) return s end
fsMethods.SetWordWrap    = function(s, w) s.wordWrap = w; return s end

-- ---------------------------------------------------------------- animations

local animMethods, groupMethods = {}, {}
local function newAnimation(group, kind)
  local a = { group = group, kind = kind }
  R.animations[#R.animations + 1] = a
  return strict("Animation<" .. kind .. ">", animMethods, a)
end
animMethods.SetDuration   = function(s, d) s.duration = d; return s end
animMethods.GetDuration   = function(s) return s.duration or 0 end
animMethods.SetOrder      = function(s, o) s.order = o; return s end
animMethods.SetStartDelay = function(s, d) s.startDelay = d; return s end
animMethods.SetSmoothing  = function(s, m) s.smoothing = m; return s end
animMethods.SetOffset     = function(s, x, y) s.offset = { x, y }; return s end
animMethods.SetScale      = function(s, x, y) s.scale = { x, y }; return s end
animMethods.SetFromAlpha  = function(s, a) s.fromAlpha = a; return s end
animMethods.SetToAlpha    = function(s, a) s.toAlpha = a; return s end
animMethods.SetDegrees    = function(s, d) s.degrees = d; return s end
animMethods.SetEndDelay   = function(s, d) s.endDelay = d; return s end
animMethods.SetOrigin     = function(s, ...) s.origin = {...}; return s end
animMethods.SetScript     = function(s, e, fn) s.scripts = s.scripts or {}; s.scripts[e] = fn; return s end

local function newAnimGroup(parent)
  local g = { parent = parent, animations = {}, playing = false, scripts = {} }
  return strict("AnimationGroup", groupMethods, g)
end
groupMethods.CreateAnimation = function(s, kind)
  local a = newAnimation(s, kind)
  s.animations[#s.animations + 1] = a
  return a
end
groupMethods.Play       = function(s) s.playing = true; rec("AnimGroup:Play"); return s end
groupMethods.Stop       = function(s) s.playing = false; rec("AnimGroup:Stop"); return s end
groupMethods.Finish     = function(s) s.playing = false; return s end
groupMethods.IsPlaying  = function(s) return s.playing end
groupMethods.SetLooping = function(s, l) s.looping = l; return s end
groupMethods.GetLooping = function(s) return s.looping end
groupMethods.SetScript  = function(s, e, fn) s.scripts[e] = fn; return s end
groupMethods.GetScript  = function(s, e) return s.scripts[e] end

-- -------------------------------------------------------------------- frames

local frameMethods = {}

local function newFrame(kind, name, parent, template)
  local f = {
    __frameKind = kind, name = name, parent = parent, template = template,
    w = 0, h = 0, shown = true, alpha = 1, scale = 1,
    points = {}, scripts = {}, registered = {}, children = {}, regions = {},
    strata = "MEDIUM", level = 1,
    -- Screen-space fields read by GetLeft/GetBottom. They must EXIST, because
    -- strict() routes any missing key through __index and would error on a plain
    -- data read. The stub places frames at the origin; tests that care about
    -- absolute position set these directly.
    left = 0, bottom = 0,
    resizable = false, movable = false, mouseEnabled = false,
    resizeBounds = nil, userPlaced = false, clamped = false,
  }
  R.frames[#R.frames + 1] = f
  if parent and parent.children then parent.children[#parent.children + 1] = f end
  return strict("Frame<" .. kind .. ">", frameMethods, f)
end

-- geometry
frameMethods.SetPoint        = function(s, ...) s.points[#s.points+1] = { ... }; return s end
frameMethods.SetAllPoints    = function(s, rel) s.allPoints = rel or true; return s end
frameMethods.ClearAllPoints  = function(s) s.points = {}; s.allPoints = nil; return s end
frameMethods.GetNumPoints    = function(s) return #s.points end
frameMethods.GetPoint        = function(s, i) local p = s.points[i or 1]; if p then return unpack(p) end end
--[[ SetSize FIRES OnSizeChanged, exactly as WoW does. Without this, every test
     that resizes a window and then asserts it reflowed was passing on a stale
     layout -- which is how "the hand must not animate on a resize" survived a
     mutation that made it animate on every resize. ]]
frameMethods.SetSize         = function(s, w, h)
  local changed = (s.w ~= w or s.h ~= h)
  s.w, s.h = w, h
  if changed and s.scripts and s.scripts.OnSizeChanged then
    s.scripts.OnSizeChanged(s, w, h)
  end
  return s
end
frameMethods.SetWidth        = function(s, w) s.w = w; return s end
frameMethods.SetHeight       = function(s, h) s.h = h; return s end
frameMethods.GetWidth        = function(s) return s.w end
frameMethods.GetHeight       = function(s) return s.h end
frameMethods.GetSize         = function(s) return s.w, s.h end
frameMethods.GetLeft         = function(s) return s.left or 0 end
frameMethods.GetBottom       = function(s) return s.bottom or 0 end
frameMethods.GetTop          = function(s) return (s.bottom or 0) + s.h end
frameMethods.GetRight        = function(s) return (s.left or 0) + s.w end
frameMethods.GetCenter       = function(s) return (s.left or 0) + s.w/2, (s.bottom or 0) + s.h/2 end
frameMethods.GetRect         = function(s) return s.left or 0, s.bottom or 0, s.w, s.h end
frameMethods.GetEffectiveScale= function(s) return s.scale end

-- visibility / hierarchy
frameMethods.Show            = function(s)
  local changed=not s.shown; s.shown=true
  if changed and s.scripts and s.scripts.OnShow then s.scripts.OnShow(s) end
  return s
end
frameMethods.Hide            = function(s)
  local changed=s.shown; s.shown=false
  if s.__frameKind=="EditBox" then s.hasFocus=false end
  if changed and s.scripts and s.scripts.OnHide then s.scripts.OnHide(s) end
  return s
end
frameMethods.IsShown         = function(s) return s.shown end
frameMethods.IsVisible       = function(s) return s.shown end
frameMethods.SetShown        = function(s, v) s.shown = not not v; return s end
frameMethods.SetParent       = function(s, p) s.parent = p; return s end
frameMethods.GetParent       = function(s) return rawget(s, "parent") end
frameMethods.GetObjectType   = function(s) return s.__frameKind end
frameMethods.GetChildren     = function(s) return unpack(s.children) end
-- the textures and font strings drawn on this frame, as WoW returns them
frameMethods.GetRegions      = function(s) return unpack(rawget(s, "regions") or {}) end
frameMethods.SetAlpha        = function(s, a) s.alpha = a; return s end
frameMethods.GetAlpha        = function(s) return s.alpha end
frameMethods.SetScale        = function(s, v) s.scale = v; return s end
frameMethods.GetScale        = function(s) return s.scale end
frameMethods.SetFrameStrata  = function(s, v) s.strata = v; return s end
frameMethods.GetFrameStrata  = function(s) return s.strata end
frameMethods.SetFrameLevel   = function(s, v) s.level = v; return s end
frameMethods.GetFrameLevel   = function(s) return s.level end
frameMethods.SetToplevel     = function(s, v) s.toplevel = v; return s end
frameMethods.Raise           = function(s) s.raised = true; return s end
frameMethods.GetName         = function(s) return s.name end

-- content
frameMethods.CreateTexture    = function(s, n, layer) return newTexture(s, layer) end
frameMethods.CreateMaskTexture = function(s) return newTexture(s, "MASK") end
frameMethods.CreateFontString = function(s, n, layer) return newFontString(s, layer) end
frameMethods.CreateAnimationGroup = function(s) return newAnimGroup(s) end

-- interaction
frameMethods.EnableMouse      = function(s, v) s.mouseEnabled = not not v; return s end
frameMethods.IsMouseEnabled   = function(s) return s.mouseEnabled end
frameMethods.EnableMouseWheel = function(s, v) s.wheelEnabled = not not v; return s end
-- IsMouseOver: tests set `mouseOver` on a frame to put the pointer over it
frameMethods.IsMouseOver      = function(s) return rawget(s, "mouseOver") == true end
frameMethods.SetMovable       = function(s, v) s.movable = not not v; return s end
frameMethods.IsMovable        = function(s) return s.movable end
frameMethods.SetResizable     = function(s, v) s.resizable = not not v; return s end
frameMethods.IsResizable      = function(s) return s.resizable end
--[[ Mainline only. SetMinResize/SetMaxResize were REMOVED in 10.0, so they are
     deliberately absent from this stub: calling them must fail here exactly as it
     would in game. ]]
frameMethods.SetResizeBounds  = function(s, minW, minH, maxW, maxH)
  s.resizeBounds = { minW, minH, maxW, maxH }; rec("SetResizeBounds", minW, minH, maxW, maxH); return s
end
frameMethods.GetResizeBounds  = function(s)
  local b = s.resizeBounds; if b then return b[1], b[2], b[3], b[4] end
end
frameMethods.SetClampedToScreen = function(s, v) s.clamped = not not v; return s end
frameMethods.SetUserPlaced    = function(s, v) s.userPlaced = not not v; return s end
frameMethods.IsUserPlaced     = function(s) return s.userPlaced end
frameMethods.SetDontSavePosition = function(s, v) s.dontSave = not not v; return s end
frameMethods.RegisterForDrag  = function(s, ...) s.dragButtons = { ... }; return s end
frameMethods.RegisterForClicks= function(s, ...) s.clickButtons = { ... }; return s end
frameMethods.StartMoving      = function(s) s.moving = true; rec("StartMoving"); return s end
frameMethods.StartSizing      = function(s, point) s.sizing = point or true; rec("StartSizing", point); return s end
frameMethods.StopMovingOrSizing = function(s) s.moving, s.sizing = false, false; rec("StopMovingOrSizing"); return s end
frameMethods.SetHitRectInsets = function(s) return s end
frameMethods.SetPropagateMouseClicks = function(s, v) s.propagate = v; return s end

-- scripts and events
frameMethods.SetScript = function(s, e, fn) s.scripts[e] = fn; return s end
frameMethods.GetScript = function(s, e) return s.scripts[e] end
frameMethods.HookScript= function(s, e, fn)
  local prev = s.scripts[e]
  s.scripts[e] = function(...) if prev then prev(...) end fn(...) end
  return s
end
frameMethods.RegisterEvent = function(s, e)
  --[[ Event names are checked against a known-good list. A typo here is otherwise
       invisible: WoW silently never fires, and you spend an hour wondering why a
       handler does not run. ]]
  if not Stub.KNOWN_EVENTS[e] then
    error(("RegisterEvent: unknown event %q -- typo, or add it to wowstub KNOWN_EVENTS"):format(e), 3)
  end
  s.registered[e] = true
  R.events[e] = R.events[e] or {}
  R.events[e][#R.events[e] + 1] = s
  return s
end
frameMethods.UnregisterEvent = function(s, e) s.registered[e] = nil; return s end
frameMethods.UnregisterAllEvents = function(s) s.registered = {}; return s end
frameMethods.IsEventRegistered = function(s, e) return s.registered[e] == true end

-- Model / PlayerModel extras, used for creature-model card art
frameMethods.SetModel        = function(s, m) s.model = m; return s end
frameMethods.SetDisplayInfo  = function(s, id) s.displayInfo = id; rec("SetDisplayInfo", id); return s end
frameMethods.SetCreature     = function(s, id) s.creature = id; return s end
frameMethods.SetUnit         = function(s, u) s.unit = u; return s end
frameMethods.SetCamDistanceScale = function(s, v) s.camScale = v; return s end
frameMethods.SetRotation     = function(s, r) s.rotation = r; return s end
frameMethods.SetPortraitZoom = function(s, z) s.portraitZoom = z; return s end
frameMethods.ClearModel      = function(s) s.displayInfo = nil; return s end
frameMethods.SetFacing       = function(s, f) s.facing = f; return s end

-- Button extras
frameMethods.SetAutoFocus = function(s,v) s.autoFocus=v end
frameMethods.ClearFocus = function(s) s.hasFocus=false end
frameMethods.SetFocus = function(s) s.hasFocus=true end
frameMethods.HasFocus = function(s) return s.hasFocus==true end
frameMethods.SetFont = function(s,...) s.font={...} end
frameMethods.SetTextInsets = function(s,...) s.textInsets={...} end
frameMethods.SetTextColor = function(s,...) s.textColor={...} end
frameMethods.SetText         = function(s, t)
  local changed=rawget(s,"text")~=t; s.text=t
  if changed and s.__frameKind=="EditBox" and s.scripts.OnTextChanged then s.scripts.OnTextChanged(s,false) end
  return s
end
frameMethods.GetText         = function(s) return s.text end
frameMethods.SetNormalTexture= function(s, t) s.normalTexture = t; return s end
frameMethods.SetHighlightTexture = function(s, t) s.highlightTexture = t; return s end
frameMethods.SetPushedTexture= function(s, t) s.pushedTexture = t; return s end
frameMethods.SetDisabledTexture = function(s, t) s.disabledTexture = t; return s end
frameMethods.GetFontString   = function(s)
  s.__fs = s.__fs or newFontString(s, "OVERLAY"); return s.__fs
end
frameMethods.Enable          = function(s) s.enabled = true; return s end
frameMethods.Disable         = function(s) s.enabled = false; return s end
frameMethods.IsEnabled       = function(s) return s.enabled ~= false end
frameMethods.Click           = function(s, button)
  local fn = s.scripts.OnClick
  if fn then fn(s, button or "LeftButton") end
  return s
end

-- ------------------------------------------------------------- known events

--[[ Only events this project actually uses, plus the Mainline death/encounter
     events from docs/07. Registering anything else is treated as a typo. ]]
Stub.KNOWN_EVENTS = {}
for _, e in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD",
  "PLAYER_TARGET_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_LEVEL", "GROUP_ROSTER_UPDATE",
  "VARIABLES_LOADED",
  -- kill / drop detection (Mainline: see docs/07)
  "UNIT_DIED", "PLAYER_TARGET_DIED", "PARTY_KILL",
  "ENCOUNTER_STATE_CHANGED", "ENCOUNTER_END", "ENCOUNTER_START", "BOSS_KILL",
  "COMBAT_LOG_EVENT_INTERNAL_UNFILTERED",
  "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "CHAT_MSG_COMBAT_XP_GAIN",
  -- world interruption
  "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_DEAD",
  "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST",
  "PLAYER_CONTROL_GAINED", "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING",
  "PLAYER_UPDATE_RESTING", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
  -- networking
  "CHAT_MSG_ADDON", "CHAT_MSG_SYSTEM", "CHAT_MSG_WHISPER",
  "GROUP_ROSTER_UPDATE", "PARTY_INVITE_REQUEST",
  -- ui
  "MODIFIER_STATE_CHANGED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
}) do Stub.KNOWN_EVENTS[e] = true end

-- ------------------------------------------------------------------ install

--[[ SECRET VALUES. Midnight's disarmament is live in Forever (docs/07): inside
     instances unit reads can answer with a secret -- displayable, but an error
     to index, concatenate, order or call. A userdata models that; what plain
     Lua 5.1 cannot model (a secret as a table key, or compared to a string)
     the tests check by looking for secrets where they must never end up. ]]
Stub.secrets = setmetatable({}, { __mode = "k" })
function Stub.Secret()
  local p = newproxy(true)
  local mt = getmetatable(p)
  local function refuse() error("attempt to use a secret value", 2) end
  mt.__index, mt.__newindex, mt.__concat, mt.__len = refuse, refuse, refuse, refuse
  mt.__lt, mt.__le, mt.__eq, mt.__call = refuse, refuse, refuse, refuse
  mt.__tostring = function() return "<secret>" end
  Stub.secrets[p] = true
  return p
end

function Stub.Install(env)
  env = env or _G
  env.issecretvalue = function(v) return v ~= nil and Stub.secrets[v] == true end
  R = newRecorder()
  Stub.R = R
  --[[ The pointer starts OFF the board. A cursor left over from a previous
       suite would make a drop land somewhere nobody aimed it. ]]
  Stub.cursor = nil
  Stub.mouseDown = nil

  env.UIParent = newFrame("Frame", "UIParent", nil, nil)
  env.UIParent:SetSize(1920, 1080)
  -- the round minimap, top right, as the default UI has it
  env.Minimap = newFrame("Frame", "Minimap", env.UIParent, nil)
  env.Minimap:SetSize(140, 140)
  env.Minimap.left, env.Minimap.bottom = 1760, 920
  env.GetMinimapShape = nil

  env.CreateFrame = function(kind, name, parent, template)
    local f = newFrame(kind or "Frame", name, parent or env.UIParent, template)
    rec("CreateFrame", kind, name, template)
    if name then env[name] = f end
    return f
  end

  -- time / timers
  local now = 0
  env.GetTime = function() return now end
  --[[ Advance the clock, firing timers IN ORDER and letting a timer that
       re-arms itself fire again before the window closes. Collecting the due
       list once and firing it would make a repeating ticker fire exactly once
       per Advance however long the window -- which silently understates every
       throttle and retry in the addon. ]]
  --[[ Advancing the clock also DRIVES OnUpdate, in 1/60 slices.

       Every animation in this addon runs on an OnUpdate -- the timelines, the
       particles, the shake, the hand tweens. Until this existed, Stub.Advance
       fired timers only, so no test had ever run an animation through the real
       frame path: a toast could be "played" for five seconds and still be
       sitting on screen at full alpha, because nothing had ticked it.

       Timers still fire at their exact due time, interleaved with the slices,
       so a C_Timer.After inside an OnUpdate behaves as it does in game. ]]
  local FRAME_STEP = 1 / 60
  Stub.Advance = function(dt)
    local target = now + dt
    local guard = 0
    while now < target - 1e-9 and guard < 100000 do
      guard = guard + 1
      local sliceEnd = math.min(now + FRAME_STEP, target)

      -- any timer due before the end of this slice fires first, in order
      while true do
        local idx, at
        for i, t in ipairs(R.timers) do
          if t.at <= sliceEnd and (not at or t.at < at) then idx, at = i, t.at end
        end
        if not idx then break end
        local t = table.remove(R.timers, idx)
        now = t.at
        t.fn()
      end

      local slice = sliceEnd - now
      now = sliceEnd
      for _, f in ipairs(R.frames) do
        local fn = f.scripts and f.scripts.OnUpdate
        if fn and f.shown ~= false then fn(f, slice > 0 and slice or FRAME_STEP) end
      end
    end
    now = target
  end
  --[[ Read by Board:PollCancel, which watches for a right-click DURING a drag
       -- the one moment no click handler can fire, because the left button is
       already held. Settable so a test can hold the button down. ]]
  env.IsMouseButtonDown = function(button)
    return Stub.mouseDown and Stub.mouseDown[button or "LeftButton"] or false
  end

  --[[ THE POINTER. Board:CursorInBoard reads this, and every drop in the game
       -- playing a card, choosing where a minion lands, aiming a spell, and
       declaring an attack -- resolves through it.

       It was not stubbed, so `if not GetCursorPosition then return nil end`
       took the early exit in every test that had ever run, and the whole
       drag-and-drop half of the interface was UNREACHABLE from the suite.
       Every drop test was really asserting that a drop over nothing snaps
       back.

       Coordinates are in SCREEN space and scaled, exactly as the real call
       returns them, so the division by GetEffectiveScale on the other side is
       exercised rather than bypassed. `Stub.CursorOver(frame, x, y)` puts the
       pointer at a board-local point without a test having to do that sum. ]]
  env.GetCursorPosition = function()
    local c = Stub.cursor
    if not c then return nil end
    return c.x, c.y
  end

  --[[ Client settings. Only what the addon touches: the SFX channel volume
       behind the board's slider. Stored per install, as strings, as WoW does. ]]
  Stub.cvars = { Sound_SFXVolume = "1.0" }
  env.C_CVar = {
    GetCVar = function(name) return Stub.cvars[name] end,
    SetCVar = function(name, value) Stub.cvars[name] = tostring(value); rec("SetCVar", name, value); return true end,
  }

  env.C_Timer = {
    After = function(delay, fn)
      R.timers[#R.timers + 1] = { at = now + delay, fn = fn }
    end,
    --[[ A REAL repeating ticker, not a stub that never fires. Client/Net's
         send throttle drains on one of these, so a ticker that did nothing
         would make the throttle untestable -- and an untested throttle is how
         addon messages get silently dropped in game. Re-arms after each firing
         and stops when cancelled. ]]
    NewTicker = function(interval, fn)
      local h = { cancelled = false, interval = interval, fires = 0 }
      h.Cancel = function() h.cancelled = true end
      local function arm()
        R.timers[#R.timers + 1] = { at = now + (interval or 0), fn = function()
          if h.cancelled then return end
          h.fires = h.fires + 1
          fn(h)
          arm()
        end }
      end
      arm()
      return h
    end,
  }

  --[[ Chat output and slash commands, used by Client/Main.lua. Recorded rather
       than printed, so a test can assert what the addon told the player. ]]
  env.DEFAULT_CHAT_FRAME = {
    AddMessage = function(self, msg) R.chat[#R.chat + 1] = msg end,
  }
  env.SlashCmdList = {}

  --[[ SOUNDKIT: the client's own table of named sound constants.

       Client/FX/Sounds.lua looks names up here rather than hardcoding numeric
       ids, which is the same discipline as reading RAID_CLASS_COLORS instead of
       asserting class hexes. This stub deliberately models only SOME of the
       names the addon asks for, so the tests exercise the fallback -- a name
       this client does not have must fall through to the next candidate and,
       failing that, to silence. ]]
  env.SOUNDKIT = {
    IG_MAINMENU_OPTION_CHECKBOX_ON = 856,
    IG_MAINMENU_OPTION             = 857,
    IG_CHARACTER_INFO_TAB          = 841,
    IG_SPELLBOOK_OPEN              = 829,
    IG_QUEST_LIST_COMPLETE         = 878,
    IG_BACKPACK_OPEN               = 862,
    IG_BACKPACK_COIN_RUB           = 863,
    UI_EPICLOOT_TOAST              = 31578,
    UI_RAID_BOSS_WHISPER_WARNING   = 37666,
    ITEM_REPAIR                    = 1187,
    LEVELUP                        = 888,
    -- deliberately ABSENT: UI_LEGENDARY_LOOT_TOAST, SPELL_SELECT_CLASS_SKILLS,
    -- IG_QUEST_FAILED and others, so the fallback chain is under test.
  }

  -- audio: record only, never actually play
  env.PlaySound     = function(id, ch) R.sounds[#R.sounds+1] = { id = id, channel = ch } end
  env.PlaySoundFile = function(p, ch)  R.sounds[#R.sounds+1] = { file = p, channel = ch }; return true, 1 end
  env.StopSound = function(handle, fade) rec("StopSound", handle); R.stopped = (R.stopped or 0) + 1 end
  env.PlayMusic     = function(p) R.sounds[#R.sounds+1] = { music = p } end
  env.StopMusic     = function() R.sounds[#R.sounds+1] = { music = false } end

  -- chat / addon messaging (Mainline surface)
  env.C_ChatInfo = {
    SendAddonMessage = function(prefix, msg, channel, target)
      rec("SendAddonMessage", prefix, msg, channel, target)
      return true
    end,
    RegisterAddonMessagePrefix = function(p) rec("RegisterAddonMessagePrefix", p); return true end,
    IsAddonMessagePrefixRegistered = function() return true end,
    PerformEmote = function(token) rec("PerformEmote", token); return true end,
  }

  -- unit / world queries used by the duel gate
  env.IsResting             = function() return Stub.resting == true end
  env.UnitExists            = function(u) return Stub.units and Stub.units[u] ~= nil end
  env.UnitName              = function(u) local x = Stub.units and Stub.units[u]; return x and x.name end
  env.UnitClass             = function(u) local x = Stub.units and Stub.units[u]; return x and x.class, x and x.class end
  env.UnitIsPlayer          = function(u) local x = Stub.units and Stub.units[u]; return x and x.isPlayer end
  env.UnitIsTapDenied       = function(u) local x = Stub.units and Stub.units[u]; return x and x.tapDenied or false end
  env.UnitIsDeadOrGhost     = function(u) local x = Stub.units and Stub.units[u]; return x and x.dead end
  env.UnitAffectingCombat   = function(u) local x = Stub.units and Stub.units[u]; return x and x.inCombat end
  -- Mainline: world position in yards (y, x, z, instanceID); nil in instances
  env.UnitPosition          = function(u) local x = Stub.units and Stub.units[u]
    if x and x.pos then return x.pos[2], x.pos[1], 0, x.pos[3] or 0 end end
  env.UnitIsVisible         = function(u) return Stub.units and Stub.units[u] ~= nil end
  -- own movement speed (0 standing on a moving boat); nil = not reported
  env.GetUnitSpeed          = function(u) local x = Stub.units and Stub.units[u]; return x and x.speed end
  env.UnitOnTaxi            = function(u) local x = Stub.units and Stub.units[u]; return x and x.onTaxi or false end
  env.CheckInteractDistance = function(u, i) return Stub.interactDistance ~= false end
  env.UnitDistanceSquared   = function(u) return Stub.distanceSquared or 0, true end
  env.SetPortraitTexture = function(texture,unit) texture.portraitUnit=unit; rec("SetPortraitTexture",unit) end
  env.UnitGUID              = function(u) local x = Stub.units and Stub.units[u]; return x and x.guid end
  env.UnitIsUnit            = function(a, b) local x = Stub.units and Stub.units[a]
    return x ~= nil and x == (Stub.units and Stub.units[b]) end
  --[[ Kill classification and the XP gate (Client/Rewards.lua). Values come
       from Stub.units so a test can say "a level 40 elite Beast died" without
       any of this knowing what a drop is. ]]
  env.UnitLevel             = function(u) local x = Stub.units and Stub.units[u]; return (x and x.level) or 1 end
  env.UnitClassification    = function(u) local x = Stub.units and Stub.units[u]; return (x and x.classification) or "normal" end
  env.UnitCreatureType      = function(u) local x = Stub.units and Stub.units[u]; return x and x.creatureType end
  env.UnitPlayerControlled  = function(u) local x = Stub.units and Stub.units[u]; return (x and x.playerControlled) or false end
  env.UnitXP                = function(u) return Stub.xp or 0 end
  env.UnitXPMax             = function(u) return Stub.xpMax or 1000 end
  --[[ Reloading the UI is the ONLY way to flush SavedVariables, so the addon
       calls it deliberately for /fh save. Recorded rather than performed. ]]
  env.ReloadUI              = function() rec("ReloadUI") end
  env.GetLocale             = function() return "enUS" end
  env.GetBuildInfo          = function() return "12.1.5", "69893", "2026-09-17", 160105 end
  env.WOW_PROJECT_ID        = 1
  env.WOW_PROJECT_MAINLINE  = 1

  env.RAID_CLASS_COLORS = {
    MAGE   = { r = 0.41, g = 0.80, b = 0.94 },
    PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
    DRUID  = { r = 1.00, g = 0.49, b = 0.04 },
    WARRIOR= { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE  = { r = 1.00, g = 0.96, b = 0.41 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
    PALADIN= { r = 0.96, g = 0.55, b = 0.73 },
    WARLOCK= { r = 0.53, g = 0.53, b = 0.93 },
  }

  -- Menu API (Mainline 11.0+ replacement for UnitPopupButtons)
  env.Menu = {
    ModifyMenu = function(tag, fn) rec("Menu.ModifyMenu", tag); Stub.menuMods = Stub.menuMods or {}; Stub.menuMods[tag] = fn end,
  }

  Stub.env = env
  return Stub
end

--- Fire an event at every frame registered for it, as WoW would.
--[[ Put the pointer at a point expressed in `frame`'s own coordinates, which
     is how Layout and Board talk about positions. Pass no frame to lift the
     pointer off the screen entirely, which is what "dropped on nothing" is. ]]
function Stub.CursorOver(frame, x, y)
  if not frame then Stub.cursor = nil; return end
  local scale = frame:GetEffectiveScale()
  Stub.cursor = { x = (frame:GetLeft() + x) * scale,
                  y = (frame:GetBottom() + y) * scale }
end

function Stub.Fire(event, ...)
  local list = R.events[event]
  if not list then return 0 end
  local n = 0
  for _, f in ipairs(list) do
    if f.registered[event] and f.scripts.OnEvent then
      f.scripts.OnEvent(f, event, ...)
      n = n + 1
    end
  end
  return n
end

--- Count frames of a given kind. Used to prove frames are POOLED and not leaked.
function Stub.CountFrames(kind)
  local n = 0
  for _, f in ipairs(R.frames) do
    if not kind or f.__frameKind == kind then n = n + 1 end
  end
  return n
end

function Stub.Count(what)
  local n = 0
  for _, c in ipairs(R.calls) do if c.what == what then n = n + 1 end end
  return n
end

function Stub.Reset() R = newRecorder(); Stub.R = R end

return Stub
