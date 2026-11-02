--[[----------------------------------------------------------------------------
APIProbe -- a read-only API surface probe for the Forever Hearthstone project.

WHAT IT DOES
  Inspects the client's API surface and reports, per subsystem, which functions,
  globals and namespaces exist without exercising experimental APIs. Writes the
  structured result to SavedVariables and a short summary to chat.

WHAT IT DOES NOT DO
  No gameplay automation. No messages to other players. No CVar or setting
  changes. No writes outside its own SavedVariables. Active frame-template,
  event, keyboard, network and emote experiments are disabled. No login autorun.

Lua 5.1 dialect: no goto, no //, no bitwise operators.
Every probe is wrapped so that a missing API is a RESULT, never an error.
------------------------------------------------------------------------------]]

local ADDON_NAME = ...
if type(ADDON_NAME) ~= "string" then ADDON_NAME = "APIProbe" end

local VERSION      = "1.0"
local TAG          = "|cff33ff99APIProbe|r "
local C_BAD        = "|cffff3030"
local C_OK         = "|cff30ff30"
local C_DIM        = "|cff909090"
local C_R          = "|r"

-- Our own addon-message prefix. Registering a prefix generates no traffic.
local PROBE_PREFIX = "FHAPIPRB"

-- Texture paths used for the "can a bad path be detected" question.
local TEX_GOOD     = "Interface\\Icons\\INV_Misc_QuestionMark"
local TEX_BOGUS    = "Interface\\Icons\\APIPROBE_NO_SUCH_FILE_9Z9Z9Z"
local ATLAS_GOOD   = "UI-HUD-ActionBar-IconFrame"
local ATLAS_BOGUS  = "APIPROBE-NO-SUCH-ATLAS-9Z9Z9Z"

--==============================================================================
-- 0. Tiny utilities
--==============================================================================

-- Lua 5.1 / LuaJIT: unpack is a global. Guard anyway.
local unpack = _G.unpack or (type(table) == "table" and table.unpack)

local function say(msg)
  local line = TAG .. tostring(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, line)
  else
    print(line)
  end
end

local function fmt(pattern, ...)
  local ok, s = pcall(string.format, pattern, ...)
  if ok then return s end
  return tostring(pattern)
end

-- Readable one-line rendering of any value, safe against __tostring errors.
local function tostr(v)
  local t = type(v)
  if v == nil then return "nil" end
  if t == "string" then return '"' .. v .. '"' end
  if t == "number" or t == "boolean" then return tostring(v) end
  if t == "table" then
    local ok, s = pcall(tostring, v)
    return ok and ("table: " .. tostring(s):gsub("^table: ", "")) or "table"
  end
  local ok, s = pcall(tostring, v)
  return ok and tostring(s) or t
end

-- Unquoted rendering, for values we already know are strings (env fields).
local function plain(v)
  if v == nil then return "?" end
  local ok, s = pcall(tostring, v)
  return ok and s or "?"
end

-- Render a varargs result list as "true, 42, nil".
local function tostrList(n, ...)
  if n == 0 then return "(no return value)" end
  local parts = {}
  for i = 1, n do
    parts[i] = tostr((select(i, ...)))
  end
  return table.concat(parts, ", ")
end

-- Resolve a dotted path ("C_ChatInfo.SendAddonMessage") off the global table.
-- Returns value, errorString. A nil value with no error means "not present".
local function safeGet(path)
  local ok, res = pcall(function()
    local cur = _G
    for part in string.gmatch(path, "[^%.]+") do
      if type(cur) ~= "table" and type(cur) ~= "userdata" then return nil end
      cur = cur[part]
      if cur == nil then return nil end
    end
    return cur
  end)
  if ok then return res, nil end
  return nil, tostring(res)
end

-- Arity, honestly. WoW's Lua 5.1 debug.getinfo has no nparams field (that is
-- 5.2+), and C functions never expose one, so most answers here are a category
-- rather than a number. We never guess.
local function fnArity(fn)
  if type(fn) ~= "function" then return nil end
  local dbg = _G.debug
  if type(dbg) ~= "table" or type(dbg.getinfo) ~= "function" then
    return "arity unknown (debug.getinfo unavailable)"
  end
  local ok, info = pcall(dbg.getinfo, fn, "uS")
  if not ok or type(info) ~= "table" then
    return "arity unknown (debug.getinfo blocked)"
  end
  if info.what == "C" or info.source == "=[C]" then
    return "C function (arity not introspectable)"
  end
  local n = info.nparams
  if type(n) ~= "number" then
    return "Lua function (nparams unavailable in this Lua)"
  end
  if info.isvararg then return fmt("Lua function, %d param(s) + vararg", n) end
  return fmt("Lua function, %d param(s)", n)
end

-- Call something and describe the outcome without ever propagating an error.
-- Return values are captured with select("#", ...) so that a trailing nil is
-- still reported as a returned nil rather than silently dropped.
local function tryCall(fn, ...)
  if type(fn) ~= "function" then
    return false, "not a function (" .. type(fn) .. ")"
  end
  local nargs = select("#", ...)
  local args  = { ... }
  local nret, rets
  local ok, err = pcall(function()
    local function grab(...)
      nret = select("#", ...)
      rets = { ... }
    end
    grab(fn(unpack(args, 1, nargs)))
  end)
  if not ok then return false, tostring(err) end
  nret = nret or 0
  rets = rets or {}
  return true, tostrList(nret, unpack(rets, 1, nret))
end

-- Call a method on an object: tryMethod(obj, "SetResizable", true)
local function tryMethod(obj, method, ...)
  if obj == nil then return false, "no object to call on" end
  local fn
  local okIndex, err = pcall(function() fn = obj[method] end)
  if not okIndex then return false, "index failed: " .. tostring(err) end
  if type(fn) ~= "function" then
    return false, "method missing (" .. type(fn) .. ")"
  end
  return tryCall(fn, obj, ...)
end

local function hasMethod(obj, method)
  if obj == nil then return false, "no object" end
  local fn
  local okIndex = pcall(function() fn = obj[method] end)
  if not okIndex then return false, "index failed" end
  return type(fn) == "function", type(fn)
end

local function sortedKeys(t)
  local keys = {}
  pcall(function()
    for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  end)
  table.sort(keys)
  return keys
end

--==============================================================================
-- 1. Result model
--==============================================================================

local Run -- rebuilt from scratch on every probe pass

local function newRun()
  return {
    version     = VERSION,
    groups      = {},   -- ordered list
    groupByName = {},
    criticals   = {},
    notes       = {},
    extra       = {},   -- namespace dumps, global scans, deep-probe output
    totalProbes = 0,
  }
end

local function G(name, note)
  local g = { name = name, note = note, probes = {}, pass = 0, fail = 0, info = 0 }
  Run.groups[#Run.groups + 1] = g
  Run.groupByName[name] = g
  return g
end

-- status: "present" | "missing" | "error"
-- expect: "present" | "missing" | "error" | "unknown"  (default "present")
local function record(g, rec)
  rec.expect = rec.expect or "present"
  if rec.expect == "unknown" then
    rec.verdict = "INFO"
    g.info = g.info + 1
  elseif rec.status == rec.expect then
    rec.verdict = "PASS"
    g.pass = g.pass + 1
  else
    rec.verdict = "FAIL"
    g.fail = g.fail + 1
    if rec.critical then
      Run.criticals[#Run.criticals + 1] =
        fmt("%s / %s -> %s (expected %s)", g.name, rec.name, rec.status, rec.expect)
    end
  end
  g.probes[#g.probes + 1] = rec
  Run.totalProbes = Run.totalProbes + 1
  return rec
end

local function note(text)
  Run.notes[#Run.notes + 1] = tostring(text)
end

--==============================================================================
-- 2. Generic probe kinds
--==============================================================================

-- Existence (and arity) of a global or dotted path.
local function probeValue(g, path, opts)
  opts = opts or {}
  local val, err = safeGet(path)
  local status, detail, arity
  if err then
    status, detail = "error", err
  elseif val == nil then
    status, detail = "missing", "not present in _G"
  else
    status = "present"
    detail = "type=" .. type(val)
    if type(val) == "function" then arity = fnArity(val) end
    if opts.wantType and type(val) ~= opts.wantType then
      detail = detail .. fmt(" (WARNING: expected %s)", opts.wantType)
    end
  end
  return record(g, {
    name     = path,
    kind     = "value",
    status   = status,
    detail   = detail,
    arity    = arity,
    expect   = opts.expect,
    critical = opts.critical,
    note     = opts.note,
  })
end

-- Existence of a method on a live object.
local function probeMethod(g, label, obj, method, opts)
  opts = opts or {}
  local ok, kind = hasMethod(obj, method)
  return record(g, {
    name     = label .. ":" .. method .. "()",
    kind     = "method",
    status   = ok and "present" or "missing",
    detail   = ok and "callable method" or ("absent (" .. tostring(kind) .. ")"),
    arity    = ok and (function()
                  local fn
                  pcall(function() fn = obj[method] end)
                  return fnArity(fn)
                end)() or nil,
    expect   = opts.expect,
    critical = opts.critical,
    note     = opts.note,
  })
end

-- Existence AND actually calling it, on our own throwaway object.
local function probeMethodCall(g, label, obj, method, opts, ...)
  opts = opts or {}
  local exists = hasMethod(obj, method)
  if not exists then
    return record(g, {
      name     = label .. ":" .. method .. "()",
      kind     = "method+call",
      status   = "missing",
      detail   = "absent, not called",
      expect   = opts.expect,
      critical = opts.critical,
      note     = opts.note,
    })
  end
  local ok, res = tryMethod(obj, method, ...)
  return record(g, {
    name     = label .. ":" .. method .. "()",
    kind     = "method+call",
    status   = ok and "present" or "error",
    detail   = ok and ("called ok -> " .. res) or ("call raised: " .. res),
    expect   = opts.expect,
    critical = opts.critical,
    note     = opts.note,
  })
end

-- Can this event be registered without raising? Registers on a scratch frame
-- and immediately unregisters; no handler is ever attached, so nothing runs.
local probeFrame

local function probeEvent(g, event, opts)
  opts = opts or {}
  if not probeFrame then
    return record(g, {
      name = "event " .. event, kind = "event", status = "error",
      detail = "no scratch frame (CreateFrame unavailable)",
      expect = opts.expect, critical = opts.critical, note = opts.note,
    })
  end
  local ok, err = pcall(probeFrame.RegisterEvent, probeFrame, event)
  local status, detail
  if ok then
    local registered = false
    local okQ, q = pcall(probeFrame.IsEventRegistered, probeFrame, event)
    if okQ then registered = (q and true or false) end
    pcall(probeFrame.UnregisterEvent, probeFrame, event)
    if registered then
      status, detail = "present", "RegisterEvent ok, IsEventRegistered=true"
    else
      status = "error"
      detail = "RegisterEvent did not raise but IsEventRegistered=false " ..
               "(event name accepted but not actually hooked)"
    end
  else
    status = "error"
    detail = "RegisterEvent raised: " .. tostring(err)
  end
  return record(g, {
    name = "event " .. event, kind = "event", status = status, detail = detail,
    expect = opts.expect, critical = opts.critical, note = opts.note,
  })
end

-- Can CreateFrame produce this frame type / template?
local function probeFrameType(g, frameType, template, opts)
  opts = opts or {}
  local label = template
    and fmt('CreateFrame("%s", nil, UIParent, "%s")', frameType, template)
    or  fmt('CreateFrame("%s")', frameType)
  if type(CreateFrame) ~= "function" then
    return record(g, {
      name = label, kind = "frametype", status = "error",
      detail = "CreateFrame itself is missing",
      expect = opts.expect, critical = opts.critical,
    })
  end
  local ok, res = pcall(CreateFrame, frameType, nil, template and UIParent or nil, template)
  local status, detail
  if ok and res then
    status = "present"
    local objType = "?"
    local okT, t = pcall(function() return res:GetObjectType() end)
    if okT then objType = tostring(t) end
    detail = "created ok, GetObjectType=" .. objType
    pcall(function() res:Hide() end)
  elseif ok then
    status, detail = "error", "CreateFrame returned nil without raising"
  else
    status, detail = "missing", "CreateFrame raised: " .. tostring(res)
  end
  return record(g, {
    name = label, kind = "frametype", status = status, detail = detail,
    expect = opts.expect, critical = opts.critical, note = opts.note,
  })
end

--==============================================================================
-- 3. The probe passes
--==============================================================================

local function probeEnvironment()
  local g = G("ENVIRONMENT", "which client actually ran this")
  local env = {}

  local version, build, buildDate, toc
  local ok = pcall(function()
    version, build, buildDate, toc = GetBuildInfo()
  end)
  env.gameVersion      = ok and tostring(version) or "GetBuildInfo failed"
  env.buildNumber      = ok and tostring(build) or "?"
  env.buildDate        = ok and tostring(buildDate) or "?"
  env.interfaceVersion = ok and tostring(toc) or "?"

  -- Which project is this really? Do not trust a name, compare the constants.
  local pid = _G.WOW_PROJECT_ID
  env.WOW_PROJECT_ID = tostr(pid)
  local constants = {
    "WOW_PROJECT_MAINLINE", "WOW_PROJECT_CLASSIC",
    "WOW_PROJECT_BURNING_CRUSADE_CLASSIC", "WOW_PROJECT_WRATH_CLASSIC",
    "WOW_PROJECT_CATACLYSM_CLASSIC", "WOW_PROJECT_MISTS_CLASSIC",
  }
  env.projectConstants = {}
  env.projectMatch = "NO MATCH among known constants"
  for _, name in ipairs(constants) do
    local v = _G[name]
    env.projectConstants[name] = tostr(v)
    if v ~= nil and pid ~= nil and v == pid then
      env.projectMatch = name
    end
  end

  env.locale = "?"
  pcall(function() env.locale = tostring(GetLocale()) end)
  env.realm = "?"
  pcall(function() env.realm = tostring(GetRealmName()) end)
  env.addonVersion = VERSION
  env.probedAt = "?"
  pcall(function()
    if type(_G.date) == "function" then
      env.probedAt = tostring(_G.date("%Y-%m-%d %H:%M:%S"))
    end
  end)
  pcall(function()
    if type(_G.time) == "function" then env.probedAtEpoch = _G.time() end
  end)

  -- Lua dialect fingerprint. Presence/absence of these tells us the version
  -- more reliably than _VERSION alone.
  env.lua = {
    _VERSION         = plain(_G._VERSION),
    jit              = type(_G.jit) == "table" and plain(_G.jit.version) or "no jit table",
    loadstring       = type(_G.loadstring),
    load             = type(_G.load),
    setfenv          = type(_G.setfenv),          -- 5.1 only
    unpack           = type(_G.unpack),           -- 5.1 global
    table_unpack     = type(table) == "table" and type(table.unpack) or "no table",
    bit_library       = type(_G.bit),             -- WoW ships a bit library
    coroutine        = type(_G.coroutine),
    os_time          = type(_G.os) == "table" and type(_G.os.time) or "no os",
    debug_getinfo    = type(_G.debug) == "table" and type(_G.debug.getinfo) or "no debug",
    string_split     = type(_G.string) == "table" and type(_G.string.split) or "no string",
    securecall       = type(_G.securecall),
    issecurevariable = type(_G.issecurevariable),
  }
  Run.env = env

  -- Recorded as probes too, so the environment participates in the count.
  probeValue(g, "GetBuildInfo")
  probeValue(g, "WOW_PROJECT_ID", { wantType = "number" })
  probeValue(g, "WOW_PROJECT_MAINLINE", { wantType = "number" })
  probeValue(g, "GetLocale")
  probeValue(g, "C_AddOns", { wantType = "table" })
  probeValue(g, "C_AddOns.GetAddOnMetadata")

  if env.projectMatch ~= "WOW_PROJECT_MAINLINE" then
    note(fmt("WOW_PROJECT_ID (%s) does not equal WOW_PROJECT_MAINLINE -- " ..
             "matched %s instead. Results do NOT describe a Mainline client.",
             env.WOW_PROJECT_ID, env.projectMatch))
  end
end

local function probeNetworking()
  local g = G("NETWORKING", "lockstep transport (docs/07 section 3)")

  probeValue(g, "C_ChatInfo", { wantType = "table", critical = true })
  probeValue(g, "C_ChatInfo.SendAddonMessage", { critical = true })
  probeValue(g, "C_ChatInfo.SendAddonMessageLogged")
  probeValue(g, "C_ChatInfo.RegisterAddonMessagePrefix", { critical = true })
  probeValue(g, "C_ChatInfo.IsAddonMessagePrefixRegistered")
  probeValue(g, "C_ChatInfo.GetRegisteredAddonMessagePrefixes")

  probeEvent(g, "CHAT_MSG_ADDON", { critical = true })
  probeEvent(g, "CHAT_MSG_ADDON_LOGGED")
  probeEvent(g, "BN_CHAT_MSG_ADDON")

  -- Functional round trip: register our prefix, then ask whether it took.
  -- This produces NO network traffic.
  local reg = safeGet("C_ChatInfo.RegisterAddonMessagePrefix")
  local isReg = safeGet("C_ChatInfo.IsAddonMessagePrefixRegistered")
  local okReg, regRes = tryCall(reg, PROBE_PREFIX)
  record(g, {
    name = "prefix registration round trip",
    kind = "behaviour",
    status = okReg and "present" or "error",
    detail = okReg and ("RegisterAddonMessagePrefix(\"" .. PROBE_PREFIX ..
                        "\") -> " .. regRes) or ("raised: " .. regRes),
    critical = true,
  })
  if type(isReg) == "function" then
    local okQ, qRes = tryCall(isReg, PROBE_PREFIX)
    record(g, {
      name = "IsAddonMessagePrefixRegistered confirms our prefix",
      kind = "behaviour",
      status = okQ and "present" or "error",
      detail = okQ and ("-> " .. qRes) or ("raised: " .. qRes),
    })
  end

  -- Length limit / rate limit constants, if the client exposes any.
  local limitNames = {
    "C_ChatInfo.MAX_ADDON_MESSAGE_LENGTH",
    "C_ChatInfo.GetAddonMessageLimit",
    "ADDON_MESSAGE_PREFIX_MAX_LENGTH",
    "MAX_ADDON_MESSAGE_LENGTH",
    "C_ChatInfo.MAX_ADDON_MESSAGE_PREFIX_LENGTH",
  }
  for _, n in ipairs(limitNames) do
    probeValue(g, n, { expect = "unknown" })
  end

  note("Addon-message LENGTH LIMIT is not measured in the default pass, " ..
       "because measuring it means sending messages. Run '/apiprobe net' to " ..
       "measure it with self-whispers (no other player receives anything).")
  note("Whether addon whispers reach a NON-GROUP player cannot be tested " ..
       "without messaging someone else, which this addon will not do. Test it " ..
       "manually with a friend, or infer it from the C_ChatInfo docs.")
end

local function probeKillDetection()
  local g = G("KILL DETECTION", "the collection loop -- CRITICAL")

  -- Expected to raise on Mainline (docs/07 section 7.3).
  probeEvent(g, "COMBAT_LOG_EVENT_UNFILTERED", { expect = "unknown" })
  probeEvent(g, "COMBAT_LOG_EVENT", { expect = "unknown" })
  probeEvent(g, "COMBAT_LOG_EVENT_INTERNAL_UNFILTERED", { expect = "unknown" })

  -- The standalone death events the corrected design depends on.
  probeEvent(g, "UNIT_DIED", { critical = true })
  probeEvent(g, "PLAYER_TARGET_DIED", { critical = true })
  probeEvent(g, "PARTY_KILL", { critical = true })
  probeEvent(g, "ENCOUNTER_STATE_CHANGED", { critical = true })
  probeEvent(g, "BOSS_KILL")
  probeEvent(g, "ENCOUNTER_START")
  probeEvent(g, "ENCOUNTER_END")

  -- Secondary / corroborating signals.
  probeEvent(g, "PLAYER_LEVEL_UP")
  probeEvent(g, "CHAT_MSG_COMBAT_XP_GAIN")
  probeEvent(g, "PLAYER_XP_UPDATE")
  probeEvent(g, "CHAT_MSG_LOOT")
  probeEvent(g, "PLAYER_REGEN_DISABLED")
  probeEvent(g, "PLAYER_REGEN_ENABLED")

  -- Sources conflict on this one (docs/07 section 7.3, flagged conflict).
  probeValue(g, "CombatLogGetCurrentEventInfo", { expect = "unknown",
    note = "12.0.0 wiki says it remains; forever-addon-kit lists it as gone. " ..
           "Unresolved before this run." })
  probeValue(g, "CombatLogGetCurrentEventInfoForUnit", { expect = "unknown" })
  probeValue(g, "C_CombatLog", { expect = "unknown" })
  probeValue(g, "C_CombatLog.GetCurrentEventInfo", { expect = "unknown" })

  -- GUID plumbing we would need if we ever parse a death event payload.
  probeValue(g, "UnitGUID")
  probeValue(g, "GetPlayerInfoByGUID", { expect = "unknown" })
  probeValue(g, "strsplit", { expect = "unknown" })
end

local function probeEmotes()
  local g = G("EMOTES", "duel flavour; must not spam")

  probeValue(g, "C_ChatInfo.PerformEmote", { note = "Mainline replacement for DoEmote" })
  probeValue(g, "DoEmote", { expect = "unknown", note = "deprecated on Mainline" })
  probeValue(g, "C_ChatInfo.CanPlayerPerformEmote", { expect = "unknown" })
  probeValue(g, "EmoteList", { expect = "unknown" })

  -- Passive hardware-event / protection signal: IsSecureCmd tells us whether a
  -- slash command is treated as protected, without our calling the emote.
  probeValue(g, "IsSecureCmd", { expect = "unknown" })
  local isSecureCmd = safeGet("IsSecureCmd")
  if type(isSecureCmd) == "function" then
    for _, cmd in ipairs({ "/emote", "/dance", "/e", "/me" }) do
      local ok, res = tryCall(isSecureCmd, cmd)
      record(g, {
        name = fmt('IsSecureCmd("%s")', cmd),
        kind = "behaviour",
        status = ok and "present" or "error",
        detail = ok and ("-> " .. res) or ("raised: " .. res),
        expect = "unknown",
      })
    end
  end

  probeValue(g, "InCombatLockdown")
  probeValue(g, "IsModifierKeyDown", { expect = "unknown",
    note = "adjacent hardware-input check" })

  note("Emote functions are NOT invoked in the default pass: an emote is " ..
       "visible to other players, so calling one is not passive. Run " ..
       "'/apiprobe emote' to call them with a deliberately INVALID emote " ..
       "token, which produces no chat output but does reveal whether the " ..
       "call is protected (needs a hardware event) or merely rejected.")
end

local function probeContextMenu()
  local g = G("CONTEXT MENU", 'right-click player -> "Challenge"')

  probeValue(g, "Menu", { wantType = "table" })
  probeValue(g, "Menu.ModifyMenu")
  probeValue(g, "Menu.GetManager", { expect = "unknown" })
  probeValue(g, "MenuUtil", { expect = "unknown" })
  probeValue(g, "MenuUtil.CreateContextMenu", { expect = "unknown" })
  probeValue(g, "MenuUtil.CreateButtonMenu", { expect = "unknown" })
  probeValue(g, "MenuResponse", { expect = "unknown" })

  -- The Classic approach, expected to be gone.
  probeValue(g, "UnitPopupButtons", { expect = "missing" })
  probeValue(g, "UnitPopupShown", { expect = "missing" })
  probeValue(g, "UnitPopupMenus", { expect = "missing" })
  probeValue(g, "UnitPopup_ShowMenu", { expect = "missing" })

  -- Older dropdown plumbing, useful to know either way.
  probeValue(g, "ToggleDropDownMenu", { expect = "unknown" })
  probeValue(g, "UIDropDownMenu_Initialize", { expect = "unknown" })
  probeValue(g, "EasyMenu", { expect = "unknown" })
end

local function probeFramesAndResize()
  local g = G("FRAMES + RESIZE", "resizable windowed game board")

  probeValue(g, "CreateFrame", { critical = true })
  probeValue(g, "UIParent", { wantType = "table", critical = true })

  probeFrameType(g, "Frame", nil, { critical = true })
  probeFrameType(g, "Button", nil, { critical = true })
  probeFrameType(g, "Model", nil)
  probeFrameType(g, "PlayerModel", nil)
  probeFrameType(g, "Cooldown", nil)
  probeFrameType(g, "StatusBar", nil)
  probeFrameType(g, "ScrollFrame", nil)
  probeFrameType(g, "EditBox", nil)
  probeFrameType(g, "Slider", nil)
  probeFrameType(g, "CheckButton", nil)
  probeFrameType(g, "GameTooltip", nil)
  probeFrameType(g, "SimpleHTML", nil)
  probeFrameType(g, "MessageFrame", nil)

  -- Templates the layout layer would like to lean on.
  probeFrameType(g, "Frame", "BackdropTemplate")
  probeFrameType(g, "Frame", "ResizeLayoutFrame")
  probeFrameType(g, "Frame", "VerticalLayoutFrame", { expect = "unknown" })
  probeFrameType(g, "Frame", "HorizontalLayoutFrame", { expect = "unknown" })
  probeFrameType(g, "Frame", "TooltipBackdropTemplate", { expect = "unknown" })
  probeFrameType(g, "Button", "UIPanelButtonTemplate", { expect = "unknown" })
  probeFrameType(g, "Frame", "PortraitFrameTemplate", { expect = "unknown" })
  probeFrameType(g, "Frame", "APIPROBE_NO_SUCH_TEMPLATE", { expect = "missing",
    note = "control: proves a bogus template is actually rejected" })

  -- Live frame to call sizing methods on. Hidden, parented to UIParent,
  -- never shown, never saved.
  local f
  if type(CreateFrame) == "function" then
    local ok, res = pcall(CreateFrame, "Frame", nil, UIParent)
    if ok then f = res end
    if f then pcall(function() f:Hide(); f:SetSize(200, 200) end) end
  end

  probeMethodCall(g, "Frame", f, "SetResizable", { critical = true }, true)
  probeMethodCall(g, "Frame", f, "IsResizable", nil)
  probeMethodCall(g, "Frame", f, "SetResizeBounds", { critical = true }, 200, 150, 1600, 1200)
  probeMethodCall(g, "Frame", f, "GetResizeBounds", nil)
  probeMethod(g,     "Frame", f, "SetMinResize", { expect = "missing",
    note = "removed in 10.x; SetResizeBounds replaces it" })
  probeMethod(g,     "Frame", f, "SetMaxResize", { expect = "missing" })
  probeMethod(g,     "Frame", f, "StartSizing", {
    note = "existence only -- calling it begins a live drag-size loop" })
  probeMethodCall(g, "Frame", f, "StopMovingOrSizing", nil)
  probeMethodCall(g, "Frame", f, "SetMovable", nil, true)
  probeMethodCall(g, "Frame", f, "SetClampedToScreen", nil, true)
  probeMethodCall(g, "Frame", f, "SetScale", nil, 1.0)
  probeMethodCall(g, "Frame", f, "SetUserPlaced", nil, false)
  probeMethodCall(g, "Frame", f, "IsUserPlaced", nil)
  probeMethodCall(g, "Frame", f, "RegisterForDrag", nil, "LeftButton")
  probeMethodCall(g, "Frame", f, "SetFrameStrata", nil, "DIALOG")
  probeMethodCall(g, "Frame", f, "SetFrameLevel", nil, 10)
  probeMethodCall(g, "Frame", f, "EnableMouse", nil, true)
  probeMethodCall(g, "Frame", f, "EnableMouseWheel", nil, true)
  probeMethodCall(g, "Frame", f, "SetPropagateKeyboardInput", nil, false)
  probeMethodCall(g, "Frame", f, "SetHitRectInsets", nil, 0, 0, 0, 0)
  probeMethodCall(g, "Frame", f, "SetIgnoreParentScale", nil, false)
  probeMethodCall(g, "Frame", f, "CreateTexture", { critical = true })
  probeMethodCall(g, "Frame", f, "CreateFontString", { critical = true })
  probeMethod(g,     "Frame", f, "SetBackdrop", { expect = "unknown",
    note = "plain Frame only; BackdropTemplate adds it" })

  -- Does BackdropTemplate really bring SetBackdrop with it?
  if type(CreateFrame) == "function" then
    local okBd, bd = pcall(CreateFrame, "Frame", nil, UIParent, "BackdropTemplate")
    if okBd and bd then
      pcall(function() bd:Hide() end)
      probeMethod(g, "BackdropTemplate Frame", bd, "SetBackdrop", { expect = "unknown" })
      probeMethod(g, "BackdropTemplate Frame", bd, "SetBackdropColor", { expect = "unknown" })
    end
  end

  Run.scratchFrame = f
end

local function probeAnimation()
  local g = G("ANIMATION", "docs/06 section 6.4 -- AnimationGroups under Timeline")

  local f = Run.scratchFrame
  probeMethod(g, "Frame", f, "CreateAnimationGroup", { critical = true })

  local ag
  if f then
    local ok, res = pcall(function() return f:CreateAnimationGroup() end)
    if ok then ag = res end
  end
  record(g, {
    name = "frame:CreateAnimationGroup() returns an object",
    kind = "behaviour",
    status = ag and "present" or "error",
    detail = ag and "AnimationGroup created" or "no AnimationGroup returned",
    critical = true,
  })

  if ag then
    probeMethodCall(g, "AnimationGroup", ag, "SetLooping", nil, "NONE")
    probeMethodCall(g, "AnimationGroup", ag, "IsPlaying", nil)
    probeMethodCall(g, "AnimationGroup", ag, "SetToFinalAlpha", nil, true)
    probeMethod(g,     "AnimationGroup", ag, "Play")
    probeMethod(g,     "AnimationGroup", ag, "Stop")
    probeMethod(g,     "AnimationGroup", ag, "Finish")
    probeMethod(g,     "AnimationGroup", ag, "SetScript")
    probeMethod(g,     "AnimationGroup", ag, "SetAnimationSpeedMultiplier", { expect = "unknown" })
    probeMethod(g,     "AnimationGroup", ag, "SetSmoothProgress", { expect = "unknown" })
    probeMethod(g,     "AnimationGroup", ag, "GetProgress", { expect = "unknown" })

    for _, kind in ipairs({ "Translation", "Scale", "Alpha", "Rotation",
                            "Path", "LineScale", "LineTranslation",
                            "TextureCoordTranslation", "VertexColor",
                            "FlipBook", "APIPROBE_NO_SUCH_ANIM" }) do
      local okA, anim = pcall(function() return ag:CreateAnimation(kind) end)
      local expect = (kind == "APIPROBE_NO_SUCH_ANIM") and "missing" or nil
      if kind == "Path" or kind == "LineScale" or kind == "LineTranslation"
         or kind == "TextureCoordTranslation" or kind == "VertexColor"
         or kind == "FlipBook" then
        expect = "unknown"
      end
      record(g, {
        name   = fmt('ag:CreateAnimation("%s")', kind),
        kind   = "animation",
        status = (okA and anim) and "present" or "missing",
        detail = (okA and anim) and "created ok"
                 or ("rejected: " .. tostring(anim)),
        expect = expect,
        critical = (kind == "Translation" or kind == "Alpha" or kind == "Scale"),
      })

      -- Easing / smoothing lives on the individual animation.
      if okA and anim and kind == "Translation" then
        probeMethodCall(g, "Animation", anim, "SetDuration", nil, 0.2)
        probeMethodCall(g, "Animation", anim, "SetOrder", nil, 1)
        probeMethodCall(g, "Animation", anim, "SetStartDelay", nil, 0.05)
        probeMethodCall(g, "Animation", anim, "SetOffset", nil, 10, 10)
        probeMethodCall(g, "Animation", anim, "SetSmoothing", nil, "OUT")
        probeMethod(g,     "Animation", anim, "SetSmoothProgress", { expect = "unknown",
          note = "needed if we drive easing ourselves from Timeline.lua" })
        probeMethod(g,     "Animation", anim, "GetSmoothProgress", { expect = "unknown" })
        probeMethod(g,     "Animation", anim, "SetScript")
        -- backOut overshoot (docs/06 timing rules) has no native easing name;
        -- confirm which smoothing names the client accepts.
        for _, sm in ipairs({ "NONE", "IN", "OUT", "IN_OUT", "OUT_IN",
                              "APIPROBE_NO_SUCH_EASING" }) do
          local okS, errS = pcall(function() anim:SetSmoothing(sm) end)
          record(g, {
            name   = fmt('Animation:SetSmoothing("%s")', sm),
            kind   = "behaviour",
            status = okS and "present" or "missing",
            detail = okS and "accepted" or ("rejected: " .. tostring(errS)),
            expect = (sm == "APIPROBE_NO_SUCH_EASING") and "missing" or "unknown",
          })
        end
      end
    end
  end

  probeValue(g, "C_Timer.After", { critical = true,
    note = "Timeline.lua needs a frame-independent tick" })
  probeValue(g, "GetTime")
  probeValue(g, "GetTimePreciseSec", { expect = "unknown" })
end

local function probeAudio()
  local g = G("AUDIO", "docs/06 section 6.3 -- expect NO pitch control")

  probeValue(g, "PlaySoundFile")
  probeValue(g, "PlaySound")
  probeValue(g, "PlayMusic")
  probeValue(g, "StopMusic")
  probeValue(g, "StopSound", { expect = "unknown" })
  probeValue(g, "MuteSoundFile", { expect = "unknown" })
  probeValue(g, "UnmuteSoundFile", { expect = "unknown" })
  probeValue(g, "C_Sound", { expect = "unknown" })
  probeValue(g, "C_Sound.IsPlaying", { expect = "unknown" })
  probeValue(g, "SOUNDKIT", { expect = "unknown" })

  -- Does the audio API report failure for a bad path? Calling with a
  -- deliberately bogus path is silent -- nothing plays -- and it answers the
  -- same question the texture group asks.
  local psf = safeGet("PlaySoundFile")
  if type(psf) == "function" then
    local okB, resB = tryCall(psf, "Interface\\APIPROBE_NO_SUCH_SOUND.ogg", "SFX")
    record(g, {
      name = "PlaySoundFile(bogus path) return value",
      kind = "behaviour",
      status = okB and "present" or "error",
      detail = okB and ("-> " .. resB .. "  (a false/nil here means bad audio " ..
                        "paths ARE detectable)")
               or ("raised: " .. resB),
      expect = "unknown",
    })
  end
  local ps = safeGet("PlaySound")
  if type(ps) == "function" then
    local okB, resB = tryCall(ps, 1, "SFX")
    record(g, {
      name = "PlaySound(bogus soundkit id 1) return value",
      kind = "behaviour",
      status = okB and "present" or "error",
      detail = okB and ("-> " .. resB) or ("raised: " .. resB),
      expect = "unknown",
    })
  end

  -- Pitch / volume. We look for them; we do NOT call SetCVar.
  for _, n in ipairs({ "SetSoundPitch", "SetSoundVolume", "C_Sound.SetPitch",
                       "C_Sound.SetVolume", "C_Sound.PlaySoundWithPitch",
                       "GetSoundScaledVolume", "SetSoundScaledVolume" }) do
    probeValue(g, n, { expect = "missing",
      note = "confirming absence -- docs/06 says no pitch control exists" })
  end
  probeValue(g, "SetCVar", { expect = "unknown",
    note = "EXISTENCE ONLY. This addon never calls SetCVar; audio ducking via " ..
           "Sound_MusicVolume is explicitly rejected in docs/06 section 6.3." })

  local snd = safeGet("C_Sound")
  if type(snd) == "table" then
    Run.extra.C_Sound_keys = sortedKeys(snd)
  end
end

local function probeTextures()
  local g = G("TEXTURES", "docs/06 -- is a BAD PATH detectable at all?")

  local f = Run.scratchFrame
  local tex
  if f then
    local ok, res = pcall(function() return f:CreateTexture(nil, "ARTWORK") end)
    if ok then tex = res end
  end
  record(g, {
    name = "frame:CreateTexture() returns a texture",
    kind = "behaviour",
    status = tex and "present" or "error",
    detail = tex and "texture created" or "no texture object",
    critical = true,
  })

  if tex then
    probeMethod(g,     "Texture", tex, "SetTexture", { critical = true })
    probeMethod(g,     "Texture", tex, "SetAtlas")
    probeMethodCall(g, "Texture", tex, "SetTexCoord", { critical = true }, 0, 1, 0, 1)
    probeMethodCall(g, "Texture", tex, "SetVertexColor", nil, 1, 1, 1, 1)
    probeMethodCall(g, "Texture", tex, "SetColorTexture", nil, 0, 0, 0, 0.5)
    probeMethodCall(g, "Texture", tex, "SetDesaturated", nil, false)
    probeMethodCall(g, "Texture", tex, "SetBlendMode", nil, "BLEND")
    probeMethodCall(g, "Texture", tex, "SetRotation", nil, 0)
    probeMethod(g,     "Texture", tex, "GetTexture")
    probeMethod(g,     "Texture", tex, "GetAtlas", { expect = "unknown" })
    probeMethod(g,     "Texture", tex, "GetTextureFileID", { expect = "unknown" })
    probeMethod(g,     "Texture", tex, "IsObjectLoaded", { expect = "unknown" })
    probeMethod(g,     "Texture", tex, "SetSnapToPixelGrid", { expect = "unknown" })
    probeMethod(g,     "Texture", tex, "SetTexelSnappingBias", { expect = "unknown" })
    -- Baked card text (docs/24) draws a small band image on a card-sized
    -- region with texcoords outside 0..1; it relies on edge CLAMP so the
    -- transparent border fills the rest. The wrap arguments must be accepted.
    probeMethodCall(g, "Texture", tex, "SetTexture", { expect = "unknown" },
      [[Interface\AddOns\ForeverHearthstone\Art\gem.tga]], "CLAMP", "CLAMP")
    probeMethodCall(g, "Texture", tex, "SetTexCoord", nil, -0.5, 1.5, -0.5, 1.5)
  end

  -- Hand cards lean; text on them is either live FontStrings or baked
  -- textures. These say which live-text controls exist on Forever.
  local fs
  if f then
    local ok, res = pcall(function() return f:CreateFontString(nil, "OVERLAY") end)
    if ok then fs = res end
  end
  if fs then
    probeMethod(g, "FontString", fs, "SetRotation", { expect = "unknown" })
    probeMethod(g, "FontString", fs, "SetSnapToPixelGrid", { expect = "unknown" })
    probeMethod(g, "FontString", fs, "SetTexelSnappingBias", { expect = "unknown" })
  end

  probeValue(g, "C_Texture", { wantType = "table" })
  probeValue(g, "C_Texture.GetAtlasInfo")
  probeValue(g, "C_Texture.GetAtlasElementID", { expect = "unknown" })
  probeValue(g, "GetAtlasInfo", { expect = "unknown",
    note = "old global form; C_Texture.GetAtlasInfo is the modern one" })
  probeValue(g, "GetFileIDFromPath", { expect = "unknown",
    note = "if this exists and returns nil for a bad path, our whole " ..
           "'paths are unverifiable' assumption is WRONG (in a good way)" })
  probeValue(g, "C_FileSystem", { expect = "unknown" })

  local ctex = safeGet("C_Texture")
  if type(ctex) == "table" then Run.extra.C_Texture_keys = sortedKeys(ctex) end

  ---------------------------------------------------------------------------
  -- The load test: gather every observable signal for a KNOWN-GOOD path and a
  -- DELIBERATELY BOGUS one, then say whether anything at all differs.
  ---------------------------------------------------------------------------
  local signals = { "GetTexture", "GetAtlas", "GetTextureFileID", "IsObjectLoaded" }
  local probeOnePath = function(path)
    local out = { path = path }
    if not tex then out.error = "no texture object"; return out end
    local okSet, setRes = tryMethod(tex, "SetTexture", path)
    out.setRaised   = not okSet
    out.setReturned = setRes
    for _, s in ipairs(signals) do
      if hasMethod(tex, s) then
        local ok, res = tryMethod(tex, s)
        out[s] = ok and res or ("raised: " .. res)
      else
        out[s] = "method absent"
      end
    end
    local gfip = safeGet("GetFileIDFromPath")
    if type(gfip) == "function" then
      local ok, res = tryCall(gfip, path)
      out.GetFileIDFromPath = ok and res or ("raised: " .. res)
    else
      out.GetFileIDFromPath = "function absent"
    end
    return out
  end

  local good  = probeOnePath(TEX_GOOD)
  local bogus = probeOnePath(TEX_BOGUS)
  pcall(function() tex:SetTexture(nil) end)
  Run.extra.textureLoadTest = { good = good, bogus = bogus }

  local differing = {}
  for _, k in ipairs({ "setRaised", "setReturned", "GetTexture", "GetAtlas",
                       "GetTextureFileID", "IsObjectLoaded", "GetFileIDFromPath" }) do
    local a, b = tostr(good[k]), tostr(bogus[k])
    -- GetTexture echoes back whatever string we set, so it always differs and
    -- proves nothing about whether the FILE exists. Exclude it explicitly.
    if k ~= "GetTexture" and a ~= b then
      differing[#differing + 1] = fmt("%s: good=%s bogus=%s", k, a, b)
    end
  end
  Run.extra.textureLoadTest.differingSignals = differing
  local distinguishable = (#differing > 0)
  record(g, {
    name = "FILE PATH validity detectable? (good vs bogus Interface\\Icons path)",
    kind = "behaviour",
    status = distinguishable and "present" or "missing",
    detail = distinguishable
      and ("YES -- differing signals: " .. table.concat(differing, " | "))
      or  ("NO -- every signal identical for a real and a fake path. " ..
           "GetTexture merely echoes the string we passed in, so it is " ..
           "excluded. This CONFIRMS docs/06: a bad icon path is invisible to " ..
           "the addon, which is why Resolver.lua's guaranteed floor exists."),
    expect = "unknown",
  })

  ---------------------------------------------------------------------------
  -- Atlases, by contrast, may well be verifiable -- which would matter a lot
  -- for the zero-art default tier (docs/07 section 7.3).
  ---------------------------------------------------------------------------
  local getAtlasInfo = safeGet("C_Texture.GetAtlasInfo")
  local atlasGoodRes, atlasBogusRes = "function absent", "function absent"
  if type(getAtlasInfo) == "function" then
    local okG, rG = pcall(getAtlasInfo, ATLAS_GOOD)
    local okB, rB = pcall(getAtlasInfo, ATLAS_BOGUS)
    atlasGoodRes  = okG and (type(rG) == "table" and "table (atlas found)" or tostr(rG))
                    or ("raised: " .. tostring(rG))
    atlasBogusRes = okB and (type(rB) == "table" and "table (UNEXPECTED: bogus atlas found)" or tostr(rB))
                    or ("raised: " .. tostring(rB))
  end
  Run.extra.atlasTest = {
    good = ATLAS_GOOD, goodResult = atlasGoodRes,
    bogus = ATLAS_BOGUS, bogusResult = atlasBogusRes,
  }
  local atlasDistinguishable = (atlasGoodRes ~= atlasBogusRes)
    and (type(getAtlasInfo) == "function")
  record(g, {
    name = "ATLAS name validity detectable? (C_Texture.GetAtlasInfo good vs bogus)",
    kind = "behaviour",
    status = atlasDistinguishable and "present" or "missing",
    detail = fmt("good=%s ; bogus=%s%s", atlasGoodRes, atlasBogusRes,
      atlasDistinguishable and
        "  -> YES, atlas names ARE verifiable at runtime, unlike file paths. " ..
        "Prefer atlases over Interface\\Icons paths wherever the art allows."
        or "  -> not distinguishable"),
    expect = "unknown",
  })

  if tex then
    local okA, errA = pcall(function() tex:SetAtlas(ATLAS_BOGUS) end)
    record(g, {
      name = "Texture:SetAtlas(bogus atlas) behaviour",
      kind = "behaviour",
      status = okA and "present" or "error",
      detail = okA and "silently accepted (no error)" or ("raised: " .. tostring(errA)),
      expect = "unknown",
    })
    pcall(function() tex:SetTexture(nil) end)
  end
end

local function probeProximity()
  local g = G("PROXIMITY + SITTING", "the duel gate -- expect NO sitting API")

  probeValue(g, "CheckInteractDistance")
  probeValue(g, "UnitDistanceSquared")
  probeValue(g, "UnitIsVisible")
  probeValue(g, "IsResting")
  probeValue(g, "UnitAffectingCombat")
  probeValue(g, "UnitIsDeadOrGhost")
  probeValue(g, "UnitExists")
  probeValue(g, "UnitIsPlayer")
  probeValue(g, "UnitIsUnit")
  probeValue(g, "UnitName")
  probeValue(g, "UnitFullName", { expect = "unknown" })
  probeValue(g, "UnitPosition", { expect = "unknown" })
  probeValue(g, "UnitInRange", { expect = "unknown" })
  probeValue(g, "C_Map.GetPlayerMapPosition", { expect = "unknown" })
  probeValue(g, "GetUnitSpeed", { expect = "unknown" })
  probeValue(g, "UnitOnTaxi", { expect = "unknown" })
  probeValue(g, "UnitInVehicle", { expect = "unknown" })
  probeValue(g, "IsMounted", { expect = "unknown" })
  probeValue(g, "IsFlying", { expect = "unknown" })
  probeValue(g, "IsSwimming", { expect = "unknown" })
  probeValue(g, "IsFalling", { expect = "unknown" })
  probeValue(g, "IsStealthed", { expect = "unknown" })

  -- Actually call the safe read-only ones on "player" and record what we get.
  local calls = {
    { "CheckInteractDistance", { "player", 1 } },
    { "UnitDistanceSquared",   { "player" } },
    { "UnitIsVisible",         { "player" } },
    { "IsResting",             {} },
    { "UnitAffectingCombat",   { "player" } },
    { "UnitIsDeadOrGhost",     { "player" } },
    { "GetUnitSpeed",          { "player" } },
    { "UnitPosition",          { "player" } },
  }
  for _, c in ipairs(calls) do
    local fn = safeGet(c[1])
    if type(fn) == "function" then
      local ok, res = tryCall(fn, unpack(c[2]))
      record(g, {
        name = fmt("%s(%s) live value", c[1], table.concat(
          (function() local s = {} for i, v in ipairs(c[2]) do s[i] = tostr(v) end return s end)(), ", ")),
        kind = "behaviour",
        status = ok and "present" or "error",
        detail = ok and ("-> " .. res) or ("raised: " .. res),
        expect = "unknown",
      })
    end
  end

  ---------------------------------------------------------------------------
  -- Sitting. Every plausible name, then a brute-force scan of _G, so the
  -- answer is "we looked everywhere" rather than "we could not think of one".
  ---------------------------------------------------------------------------
  local sittingCandidates = {
    "IsSitting", "UnitIsSitting", "UnitSitting", "GetUnitStandState",
    "UnitStandState", "UnitStandStateValue", "GetStandState",
    "C_PlayerInfo.IsSitting", "C_PlayerInfo.GetSitState",
    "C_UnitAuras.GetSittingState", "UnitChairState", "IsSeated", "UnitIsSeated",
    "GetUnitAnimation", "UnitAnimationState",
  }
  for _, n in ipairs(sittingCandidates) do
    probeValue(g, n, { expect = "missing",
      note = "candidate sitting-state API; absence is the expected result" })
  end
  -- The one sitting-related function that does exist is write-only.
  probeValue(g, "SitStandOrDescendStart", { expect = "unknown",
    note = "TOGGLES sit/stand; it does not report state, and this addon " ..
           "never calls it (that would move the player)" })

  local scan, scanOk = {}, false
  scanOk = pcall(function()
    for k, v in pairs(_G) do
      if type(k) == "string" then
        if string.find(k, "Sit") or string.find(k, "StandState")
           or string.find(k, "Chair") or string.find(k, "Seated") then
          scan[#scan + 1] = k .. " (" .. type(v) .. ")"
        end
      end
    end
  end)
  table.sort(scan)
  Run.extra.sittingGlobalScan = { ok = scanOk, matches = scan,
    patterns = "Sit / StandState / Chair / Seated over all of _G" }
  record(g, {
    name = "brute-force _G scan for any sitting-state API",
    kind = "behaviour",
    status = "present",
    detail = fmt("%d global name(s) matched Sit/StandState/Chair/Seated: %s",
      #scan, (#scan > 0) and table.concat(scan, ", ") or "(none)"),
    expect = "unknown",
  })

  note("SITTING: tried " .. #sittingCandidates .. " candidate API names plus a " ..
       "full _G name scan. If nothing readable turned up, the duel gate must " ..
       "use an explicit accept prompt (both players opt in) rather than " ..
       "detecting that someone sat down.")
end

local function probePersistence()
  local g = G("PERSISTENCE", "SavedVariables + crash mitigation timers")

  -- SavedVariables tables are created by the client before PLAYER_LOGIN if the
  -- .toc declares them. Finding a PREVIOUS run in them proves a round trip.
  local svOk   = (type(_G.APIProbeDB) == "table")
  local svcOk  = (type(_G.APIProbeCharDB) == "table")
  record(g, {
    name = "SavedVariables (APIProbeDB) table available",
    kind = "behaviour",
    status = svOk and "present" or "missing",
    detail = svOk and "global table present after load" or "global is " .. type(_G.APIProbeDB),
    critical = true,
  })
  record(g, {
    name = "SavedVariablesPerCharacter (APIProbeCharDB) table available",
    kind = "behaviour",
    status = svcOk and "present" or "missing",
    detail = svcOk and "global table present after load" or "global is " .. type(_G.APIProbeCharDB),
  })
  local priorAcct = svOk and _G.APIProbeDB.runCount or nil
  local priorChar = svcOk and _G.APIProbeCharDB.runCount or nil
  record(g, {
    name = "SavedVariables actually round-tripped from disk",
    kind = "behaviour",
    status = (type(priorAcct) == "number" and priorAcct > 0) and "present" or "missing",
    detail = fmt("previous account-wide runCount=%s, per-character runCount=%s " ..
                 "(0/nil on a first ever run -- re-run after a /reload to " ..
                 "turn this into a real answer)", tostr(priorAcct), tostr(priorChar)),
    expect = "unknown",
  })

  probeValue(g, "C_Timer", { wantType = "table", critical = true })
  probeValue(g, "C_Timer.After", { critical = true })
  probeValue(g, "C_Timer.NewTicker", { critical = true })
  probeValue(g, "C_Timer.NewTimer", { expect = "unknown" })
  probeValue(g, "C_AddOns.SaveAddOnAndCVarSettings", { expect = "unknown",
    note = "if present this could flush SavedVariables without a full reload, " ..
           "which is exactly the crash-mitigation hook docs/07 item 7 wants" })
  probeValue(g, "SaveBindings", { expect = "unknown" })
  probeValue(g, "C_CVar", { expect = "unknown",
    note = "EXISTENCE ONLY -- never written by this addon" })
  probeEvent(g, "PLAYER_LOGOUT")
  probeEvent(g, "PLAYER_LEAVING_WORLD")
  probeEvent(g, "ADDON_LOADED")
  probeEvent(g, "PLAYER_LOGIN")
  probeEvent(g, "PLAYER_ENTERING_WORLD")

  -- Live timer test. Both callbacks write a flag that lands in the saved file,
  -- so the NEXT run (and the file itself) shows whether they actually fired.
  local after = safeGet("C_Timer.After")
  if type(after) == "function" then
    local ok, err = pcall(after, 0.2, function()
      if type(_G.APIProbeDB) == "table" and type(_G.APIProbeDB.last) == "table" then
        _G.APIProbeDB.last.timerAfterFired = true
      end
    end)
    record(g, {
      name = "C_Timer.After(0.2, cb) scheduled",
      kind = "behaviour",
      status = ok and "present" or "error",
      detail = ok and "scheduled; look for last.timerAfterFired=true in the saved file"
               or ("raised: " .. tostring(err)),
      critical = true,
    })
  end
  local newTicker = safeGet("C_Timer.NewTicker")
  if type(newTicker) == "function" then
    local ticks = 0
    local ok, handle = pcall(newTicker, 0.1, function(h)
      ticks = ticks + 1
      if type(_G.APIProbeDB) == "table" and type(_G.APIProbeDB.last) == "table" then
        _G.APIProbeDB.last.tickerTicks = ticks
      end
      if ticks >= 3 and h and h.Cancel then pcall(h.Cancel, h) end
    end, 3)
    record(g, {
      name = "C_Timer.NewTicker(0.1, cb, 3) created",
      kind = "behaviour",
      status = (ok and handle) and "present" or "error",
      detail = (ok and handle)
        and "ticker created with an iteration cap; look for last.tickerTicks in the saved file"
        or ("failed: " .. tostring(handle)),
      critical = true,
    })
  end
end

local function probeRemovedGlobals()
  local g = G("REMOVED CLASSIC GLOBALS", "compat layer must not reference these")
  local removed = {
    "GetItemInfo", "GetSpellInfo", "UnitAura", "GetTalentInfo",
    "GetMerchantItemInfo", "GetItemCount", "GetSpellCooldown",
    "UnitBuff", "UnitDebuff", "GetContainerItemInfo",
  }
  for _, n in ipairs(removed) do
    probeValue(g, n, { expect = "missing",
      note = "Classic-era global; docs/07 section 7.3 says avoid regardless" })
  end
  -- And the modern replacements, so the compat layer knows what to use.
  for _, n in ipairs({ "C_Item.GetItemInfo", "C_Spell.GetSpellInfo",
                       "C_UnitAuras.GetAuraDataByIndex", "C_Container.GetContainerItemInfo",
                       "C_MerchantFrame" }) do
    probeValue(g, n, { expect = "unknown", note = "modern replacement" })
  end
end

local function probeNamespaceDumps()
  local g = G("NAMESPACE DUMPS", "full key lists saved for offline diffing")
  for _, ns in ipairs({ "C_ChatInfo", "C_Timer", "C_Texture", "C_Sound",
                        "Menu", "MenuUtil", "C_AddOns", "C_UnitAuras" }) do
    local t = safeGet(ns)
    if type(t) == "table" then
      local keys = sortedKeys(t)
      Run.extra[ns .. "_keys"] = keys
      record(g, {
        name = ns .. " key list captured",
        kind = "dump",
        status = "present",
        detail = fmt("%d keys", #keys),
        expect = "unknown",
      })
    else
      record(g, {
        name = ns .. " key list captured",
        kind = "dump",
        status = "missing",
        detail = "namespace is " .. type(t),
        expect = "unknown",
      })
    end
  end
  -- A rough census of how many C_* namespaces this client has (docs/07 says
  -- Forever should have around 269).
  local count, names = 0, {}
  pcall(function()
    for k, v in pairs(_G) do
      if type(k) == "string" and type(v) == "table" and string.sub(k, 1, 2) == "C_" then
        count = count + 1
        names[#names + 1] = k
      end
    end
  end)
  table.sort(names)
  Run.extra.C_namespaceCount = count
  Run.extra.C_namespaceNames = names
  record(g, {
    name = "C_* namespace census",
    kind = "dump",
    status = "present",
    detail = fmt("%d C_* namespaces (docs/07 expects ~269 on Forever)", count),
    expect = "unknown",
  })
end

--==============================================================================
-- 4. Opt-in probes (these are the only ones with any outward effect)
--==============================================================================

-- Measures the addon-message length limit using WHISPERS TO OURSELVES.
-- No other player receives anything. Spaced out to avoid the rate limiter.
local function deepProbeNetwork()
  local send = safeGet("C_ChatInfo.SendAddonMessage")
  if type(send) ~= "function" then
    say(C_BAD .. "C_ChatInfo.SendAddonMessage is missing; nothing to measure." .. C_R)
    return
  end
  local me
  pcall(function() me = UnitName("player") end)
  if type(me) ~= "string" or me == "" then
    say(C_BAD .. "Could not resolve your own name; aborting." .. C_R)
    return
  end
  local ladder = { 16, 64, 128, 200, 240, 250, 255, 256, 300, 500, 1000 }
  local results = {}
  Run.extra.deepNetwork = { target = "self-whisper", ladder = ladder, results = results }
  if type(_G.APIProbeDB) == "table" and type(_G.APIProbeDB.last) == "table" then
    _G.APIProbeDB.last.extra = _G.APIProbeDB.last.extra or {}
    _G.APIProbeDB.last.extra.deepNetwork = Run.extra.deepNetwork
  end
  say("Measuring addon-message length limit with self-whispers " ..
      "(" .. #ladder .. " messages, ~0.5s apart). No one else receives these.")
  local after = safeGet("C_Timer.After")
  for i, len in ipairs(ladder) do
    local fire = function()
      local ok, res = tryCall(send, PROBE_PREFIX, string.rep("x", len), "WHISPER", me)
      results[#results + 1] = fmt("len=%d -> %s", len, ok and res or ("raised: " .. res))
      if i == #ladder then
        say("Length ladder complete. Full results are in SavedVariables under " ..
            "last.extra.deepNetwork. /reload to flush the file.")
        for _, line in ipairs(results) do say(C_DIM .. "  " .. line .. C_R) end
      end
    end
    if type(after) == "function" then
      pcall(after, 0.5 * i, fire)
    else
      fire()
    end
  end
end

-- Calls the emote functions with a DELIBERATELY INVALID emote token. An invalid
-- token produces no chat output and no world-visible action; what it does
-- reveal is whether the call is protected (needs a hardware event) or merely
-- rejected as an unknown emote.
local function deepProbeEmote()
  local out = {}
  Run.extra.deepEmote = out
  if type(_G.APIProbeDB) == "table" and type(_G.APIProbeDB.last) == "table" then
    _G.APIProbeDB.last.extra = _G.APIProbeDB.last.extra or {}
    _G.APIProbeDB.last.extra.deepEmote = out
  end
  local token = "APIPROBE_NOT_A_REAL_EMOTE"
  local targets = { "C_ChatInfo.PerformEmote", "DoEmote" }
  for _, path in ipairs(targets) do
    local fn = safeGet(path)
    if type(fn) ~= "function" then
      out[#out + 1] = path .. " -> not present"
    else
      local ok, res = tryCall(fn, token)
      local verdict
      if ok then
        verdict = "callable from addon code, invalid token accepted silently -> " .. res
      elseif string.find(tostring(res), "ADDON_ACTION_BLOCKED")
          or string.find(tostring(res), "protected")
          or string.find(tostring(res), "Interface action failed") then
        verdict = "PROTECTED -- needs a hardware event: " .. res
      else
        verdict = "raised (probably just an unknown-emote rejection): " .. res
      end
      out[#out + 1] = path .. " -> " .. verdict
    end
  end
  say("Emote callability (invalid token, nothing shown to other players):")
  for _, line in ipairs(out) do say(C_DIM .. "  " .. line .. C_R) end
  say("Saved under last.extra.deepEmote. /reload to flush the file.")
end

--==============================================================================
-- 5. Reporting
--==============================================================================

local function buildPasteLines()
  local L = {}
  local function add(s) L[#L + 1] = s end
  local e = Run.env or {}
  add("=== APIProbe " .. VERSION .. " report ===")
  add(fmt("client        : %s build %s (%s)", plain(e.gameVersion),
          plain(e.buildNumber), plain(e.buildDate)))
  add(fmt("interface ver : %s   <- select(4, GetBuildInfo())", plain(e.interfaceVersion)))
  add(fmt("WOW_PROJECT_ID: %s  ==  %s", plain(e.WOW_PROJECT_ID), plain(e.projectMatch)))
  add(fmt("locale        : %s   realm: %s", plain(e.locale), plain(e.realm)))
  add(fmt("lua           : %s  (jit: %s)",
          plain(e.lua and e.lua._VERSION), plain(e.lua and e.lua.jit)))
  add(fmt("run at        : %s   (run #%s on this account)",
          plain(e.probedAt), plain(_G.APIProbeDB and _G.APIProbeDB.runCount)))
  add(fmt("probes        : %d across %d groups", Run.totalProbes, #Run.groups))
  add("")
  for _, g in ipairs(Run.groups) do
    add(fmt("--- %s  [pass %d / fail %d / info %d]  %s",
            g.name, g.pass, g.fail, g.info, g.note or ""))
    for _, p in ipairs(g.probes) do
      local line = fmt("  [%-4s] %-22s %s", p.verdict, p.status, p.name)
      add(line)
      if p.arity then add("           arity : " .. p.arity) end
      if p.detail then add("           detail: " .. p.detail) end
      if p.note then add("           note  : " .. p.note) end
    end
    add("")
  end
  if #Run.criticals > 0 then
    add("!!! CRITICAL FAILURES !!!")
    for _, c in ipairs(Run.criticals) do add("  " .. c) end
    add("")
  end
  if #Run.notes > 0 then
    add("--- NOTES ---")
    for _, n in ipairs(Run.notes) do add("  * " .. n) end
    add("")
  end
  add("=== end of report ===")
  return L
end

local function printSummary()
  local e = Run.env or {}
  local totalPass, totalFail = 0, 0
  for _, g in ipairs(Run.groups) do
    totalPass = totalPass + g.pass
    totalFail = totalFail + g.fail
  end
  say(fmt("v%s | %s build %s | iface %s | %s | %s", VERSION,
          plain(e.gameVersion), plain(e.buildNumber), plain(e.interfaceVersion),
          plain(e.projectMatch), plain(e.locale)))
  say(fmt("%d probes in %d groups: %s%d pass%s, %s%d unexpected%s",
          Run.totalProbes, #Run.groups, C_OK, totalPass, C_R,
          (totalFail > 0) and C_BAD or C_DIM, totalFail, C_R))
  -- Two groups per line, so the whole summary stays around a dozen lines.
  local function cell(g)
    if not g then return "" end
    local colour = (g.fail > 0) and C_BAD or C_OK
    local score
    if g.pass + g.fail == 0 then
      score = fmt("%d info", g.info)
    else
      score = fmt("%d/%d", g.pass, g.pass + g.fail)
    end
    return fmt("%s%-23s %-7s%s", colour, g.name, score, C_R)
  end
  local i = 1
  while i <= #Run.groups do
    say("  " .. cell(Run.groups[i]) .. "  " .. cell(Run.groups[i + 1]))
    i = i + 2
  end
  if #Run.criticals > 0 then
    say(C_BAD .. "!! CRITICAL: " .. #Run.criticals .. " must-have item(s) failed !!" .. C_R)
    for i, c in ipairs(Run.criticals) do
      if i <= 6 then say(C_BAD .. "  " .. c .. C_R) end
    end
    if #Run.criticals > 6 then
      say(C_BAD .. fmt("  ...and %d more, see the saved file.", #Run.criticals - 6) .. C_R)
    end
  else
    say(C_OK .. "No critical item missing." .. C_R)
  end
  say(C_DIM .. "Full report saved. Type /reload, then copy APIProbe.lua from " ..
      "WTF/Account/<ACCOUNT>/SavedVariables/. /apiprobe help for more." .. C_R)
end

local function persist()
  if type(_G.APIProbeDB) ~= "table" then _G.APIProbeDB = {} end
  local db = _G.APIProbeDB
  db.runCount = (type(db.runCount) == "number" and db.runCount or 0) + 1
  db.probeVersion = VERSION

  -- Strip the lookup table and the live frame; SavedVariables must hold plain data.
  local groups = {}
  for i, g in ipairs(Run.groups) do
    local probes = {}
    for j, p in ipairs(g.probes) do
      probes[j] = { name = p.name, kind = p.kind, status = p.status,
                    expect = p.expect, verdict = p.verdict, detail = p.detail,
                    arity = p.arity, note = p.note, critical = p.critical or nil }
    end
    groups[i] = { name = g.name, note = g.note, pass = g.pass, fail = g.fail,
                  info = g.info, probes = probes }
  end

  db.last = {
    probeVersion = VERSION,
    runIndex     = db.runCount,
    env          = Run.env,
    totalProbes  = Run.totalProbes,
    groups       = groups,
    criticals    = Run.criticals,
    notes        = Run.notes,
    extra        = Run.extra,
    paste        = buildPasteLines(),
  }

  if type(_G.APIProbeCharDB) ~= "table" then _G.APIProbeCharDB = {} end
  local cdb = _G.APIProbeCharDB
  cdb.runCount = (type(cdb.runCount) == "number" and cdb.runCount or 0) + 1
  cdb.lastSummary = {
    probeVersion = VERSION,
    interfaceVersion = Run.env and Run.env.interfaceVersion,
    buildNumber = Run.env and Run.env.buildNumber,
    projectMatch = Run.env and Run.env.projectMatch,
    totalProbes = Run.totalProbes,
    criticalCount = #Run.criticals,
  }
end

local function runAll()
  Run = newRun()

  -- Scratch frame for event registration. Never shown, no handlers attached.
  if type(CreateFrame) == "function" then
    local ok, f = pcall(CreateFrame, "Frame", nil, UIParent)
    if ok then probeFrame = f end
    if probeFrame then pcall(function() probeFrame:Hide() end) end
  end

  local passes = {
    -- Live diagnostics inspect values only. Experimental calls and Blizzard
    -- templates can taint the UI even when errors are caught with pcall.
    probeEnvironment, probeRemovedGlobals,
    probeNamespaceDumps,
  }
  for _, pass in ipairs(passes) do
    local ok, err = pcall(pass)
    if not ok then
      note("PROBE PASS ITSELF FAILED: " .. tostring(err))
      say(C_BAD .. "a probe pass errored (recorded in notes): " .. tostring(err) .. C_R)
    end
  end

  pcall(persist)
  pcall(printSummary)
end

local function dumpToChat()
  if not Run or not Run.env then say("No results yet; run /apiprobe first."); return end
  local lines = buildPasteLines()
  say(fmt("dumping %d lines -- the saved file is easier to copy from.", #lines))
  for _, l in ipairs(lines) do
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
      pcall(DEFAULT_CHAT_FRAME.AddMessage, DEFAULT_CHAT_FRAME, l)
    else
      print(l)
    end
  end
end

--==============================================================================
-- 6. Slash command + autorun
--==============================================================================

local function showHelp()
  say("commands:")
  say(C_DIM .. "  /apiprobe        re-run the passive probe (no side effects)" .. C_R)
  say(C_DIM .. "  /apiprobe full   dump the whole report into chat" .. C_R)
  say(C_DIM .. "  Active template, network and emote probes are disabled for live-client safety." .. C_R)
  say(C_DIM .. "  /reload then copy WTF/Account/<ACCOUNT>/SavedVariables/APIProbe.lua" .. C_R)
end

SLASH_APIPROBE1 = "/apiprobe"
SLASH_APIPROBE2 = "/apip"
SlashCmdList = SlashCmdList or {}
SlashCmdList["APIPROBE"] = function(msg)
  local arg = string.lower(tostring(msg or ""))
  arg = string.gsub(arg, "^%s*(.-)%s*$", "%1")
  if arg == "" or arg == "run" then
    runAll()
  elseif arg == "full" or arg == "dump" then
    dumpToChat()
  elseif arg == "net" or arg == "network" then
    say("Active network probes are disabled in the live-client diagnostic.")
  elseif arg == "emote" or arg == "emotes" then
    say("Active emote probes are disabled in the live-client diagnostic.")
  else
    showHelp()
  end
end

local hasAutoRun = false
local loader
if type(CreateFrame) == "function" then
  local ok, f = pcall(CreateFrame, "Frame")
  if ok then loader = f end
end
if loader then
  loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" and not hasAutoRun then
      hasAutoRun = true
      say("loaded; /apiprobe runs the read-only inventory when requested.")
      pcall(function() self:UnregisterAllEvents() end)
    end
  end)
  pcall(loader.RegisterEvent, loader, "PLAYER_LOGIN")
else
  -- No CreateFrame at all: still give the user something via the slash command.
  say("could not create a loader frame; run /apiprobe manually.")
end

-- Expose for debugging / other tooling. Read-only by convention.
_G.APIProbe = {
  version = VERSION,
  Run = function() runAll(); return Run end,
  GetLastRun = function() return Run end,
  Lines = function() return buildPasteLines() end,
}
