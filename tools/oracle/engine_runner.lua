--[[ tools/oracle/engine_runner.lua -- the engine half of the Fireplace oracle.

  Run from the PROJECT ROOT by tools/oracle/oracle.py, never by hand:

      luajit tools/oracle/engine_runner.lua <scenarios.lua>

  <scenarios.lua> is written by oracle.py: `return { {name=..., p1=..., p2=...,
  actions=...}, ... }`, the scenario JSON turned into a Lua literal so this side
  needs no JSON parser. For each scenario it builds the board, plays the
  actions, and prints one line of JSON with the normalised end state. oracle.py
  builds the same snapshot from Fireplace and compares the two.

  The snapshot format is defined twice, here and in oracle.py's fp_snapshot. A
  field added to one must be added to the other, or every scenario "differs".
]]
package.path = "./?.lua;./?/init.lua;" .. package.path
local H = require("tests.harness")
local ns = H.LoadEngine()
local KW = ns.KEYWORD

-- ------------------------------------------------------------------ json out

local function jstr(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
    return ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function isArray(t)
  if next(t) == nil then return true end
  return t[1] ~= nil
end

local function json(v)
  local t = type(v)
  if t == "nil" then return "null"
  elseif t == "boolean" then return v and "true" or "false"
  elseif t == "number" then return tostring(v)
  elseif t == "string" then return jstr(v)
  elseif isArray(v) then
    local parts = {}
    for i, x in ipairs(v) do parts[i] = json(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  else
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = jstr(k) .. ":" .. json(v[k]) end
    return "{" .. table.concat(parts, ",") .. "}"
  end
end

-- ------------------------------------------------------------------ setup

local FILLER = "CS2_231"   -- Wisp: both engines draw it, and it does nothing

local function pnum(s) return s == "p1" and 1 or 2 end

local function setupPlayer(g, i, spec)
  spec = spec or {}
  local p = g.players[i]
  -- The dealt hand and the Coin go away: a scenario states its hand exactly.
  -- Dealt Wisps go back to the deck so both engines keep 30 cards there.
  for _, e in ipairs(p.hand) do
    if e.cardId == FILLER then
      e.zone = ns.ZONE.DECK
      table.insert(p.deck, 1, e)
    end
  end
  p.hand = {}
  -- scenario deck lists top card first; PutOnDeck stacks on top
  local deck = spec.deck or {}
  for k = #deck, 1, -1 do H.PutOnDeck(g, i, deck[k]) end
  for _, id in ipairs(spec.hand or {}) do H.Hand(g, i, id) end
  for _, m in ipairs(spec.board or {}) do
    if type(m) == "string" then m = { id = m } end
    local e = H.Put(g, i, m.id, { sick = m.sick })
    e.damage = m.damage or 0
    if m.frozen then e.frozen = true end
  end
  if spec.weapon then g:EquipWeapon(i, spec.weapon) end
  for _, id in ipairs(spec.secrets or {}) do
    local e = ns.Entity.New(g:Printed(id), i, g.ids)
    if not g:PlaySecret(i, e) then error("could not place secret " .. id) end
  end
  p.hero.damage = 30 - (spec.hp or 30)
  p.hero.armor = spec.armor or 0
  H.Mana(g, i, spec.mana or 10)
  g:RecalcAuras()
end

local function resolve(g, ref)
  if ref == nil then return nil end
  local side, zone, idx = ref:match("^(p[12])%.(%a+)%.?(%d*)$")
  if not side then error("bad ref " .. ref) end
  local p = g.players[pnum(side)]
  if zone == "hero" then return p.hero end
  local list = p[zone]
  local e = list and list[tonumber(idx)]
  if not e then error("ref " .. ref .. " is empty") end
  return e
end

local function act(g, a)
  local me = g.activePlayer
  local ok, why
  if a.play then
    local hi
    for k, e in ipairs(g.players[me].hand) do
      if e.cardId == a.play then hi = k; break end
    end
    if not hi then error("no " .. a.play .. " in hand") end
    -- "choose" names the option card (EX1_166b), not an index: the two
    -- engines list some cards' options in different orders (Dark Wispers).
    local mode
    if a.choose then
      for k, id in ipairs(ns.Targeting.ModesOf(g.players[me].hand[hi]) or {}) do
        if id == a.choose then mode = k end
      end
      if not mode then error(a.play .. " has no option " .. a.choose) end
    end
    ok, why = g:PlayCard(me, hi, resolve(g, a.target), a.pos, mode)
  elseif a.attack then
    ok, why = g:Attack(resolve(g, a.attack), resolve(g, a.at))
  elseif a.power then
    ok, why = g:UseHeroPower(me, resolve(g, a.target))
  elseif a.pick then
    -- Tracking: pick the offered card by id, not by position
    local pc = g.pendingChoice
    local idx
    for k, e in ipairs(pc and pc.cards or {}) do
      if e.cardId == a.pick and not idx then idx = k end
    end
    if not idx then error("no " .. a.pick .. " on offer") end
    ok, why = g:ResolveChoice(me, idx)
  elseif a.end_turn then
    ok, why = g:EndTurn()
    ok = true
  else
    error("unknown action")
  end
  g.bus:Drain()
  return ok
end

-- ----------------------------------------------------------------- snapshot

local function flags(g, e)
  local f = {}
  if e:IsTaunt() then f[#f + 1] = "taunt" end
  if e:Has(KW.DIVINE_SHIELD) then f[#f + 1] = "shield" end
  if e:IsStealth() then f[#f + 1] = "stealth" end
  if e:Has(KW.WINDFURY) then f[#f + 1] = "windfury" end
  if e:IsFrozen() then f[#f + 1] = "frozen" end
  if e.silenced then f[#f + 1] = "silenced" end
  return table.concat(f, ",")
end

local function snapshot(g)
  local out = { over = g.over and true or false }
  for i = 1, 2 do
    local p = g.players[i]
    local s = {}
    s.hero = ("%d+%d"):format(p.hero:Health(), p.hero.armor or 0)
    if i == g.activePlayer then s.hero = s.hero .. (" atk%d"):format(g:AttackValue(p.hero)) end
    s.board = {}
    for k, e in ipairs(p.board) do
      local f = flags(g, e)
      s.board[k] = ("%s %d/%d(%d)%s"):format(e.cardId, g:AttackValue(e), e:Health(),
        e:MaxHealth(), f ~= "" and (" " .. f) or "")
    end
    s.hand = {}
    for k, e in ipairs(p.hand) do s.hand[k] = ("%s(%d)"):format(e.cardId, g:CardCost(e, i)) end
    s.deck = #p.deck
    s.weapon = p.weapon and ("%s %d/%d"):format(p.weapon.cardId, p.weapon:Attack(), p.weapon:Health()) or ""
    s.secrets = {}
    for k, e in ipairs(p.secrets) do s.secrets[k] = e.cardId end
    table.sort(s.secrets)
    s.mana = ("%d/%d"):format(g:AvailableMana(i), p.maxMana)
    local hp = p.heroPower and p.heroPower.cardId or ""
    s.power = (hp == ns.HERO_POWER_BY_CLASS[p.class] and "basic" or hp)
              .. (p.heroPowerUsedThisTurn and " used" or "")
    out["p" .. i] = s
  end
  return out
end

-- --------------------------------------------------------------------- main

local function runOnce(sc, seed)
  local g = H.NewGame({
    seed = seed, firstPlayer = 1,
    class1 = (sc.p1 or {}).class or "MAGE",
    class2 = (sc.p2 or {}).class or "PRIEST",
  })
  setupPlayer(g, 1, sc.p1)
  setupPlayer(g, 2, sc.p2)
  H.SetActive(g, 1)
  -- A refused action is a result, not a failure: the other engine may have
  -- allowed it. Its logged "illegal ..." error is dropped with it. Refused
  -- means "false AND nothing changed": an attack a Secret cancels (Freezing
  -- Trap, Vaporize) also returns false, but it happened.
  local refused = {}
  for k, a in ipairs(sc.actions or {}) do
    if g.over then break end   -- Fireplace stops at game over too
    local nerr = #g.errors
    local before = select(2, g:StateHash())
    if not act(g, a) and select(2, g:StateHash()) == before then
      refused[#refused + 1] = k
      for j = #g.errors, nerr + 1, -1 do g.errors[j] = nil end
    end
  end
  local state = snapshot(g)
  state.refused = refused
  if #g.errors > 0 then error("engine errors: " .. table.concat(g.errors, " | "), 0) end
  return state
end

-- `--scripts`: list every card id the engine has a script for, one per line,
-- for oracle.py's coverage gate. Asking the engine is the only complete list:
-- scripts come from several CSVs and Handwritten.lua.
if arg[1] == "--scripts" then
  for id in pairs(ns.Scripts) do io.write(id, "\n") end
  return
end

local list = dofile(arg[1])
for _, sc in ipairs(list) do
  local res = { name = sc.name }
  local ok, err = pcall(function()
    if sc.random then
      -- a random scenario: one state per seed; oracle.py compares the SETS
      res.states = {}
      for seed = 1, sc.random do res.states[seed] = runOnce(sc, seed) end
    else
      res.state = runOnce(sc, 1)
    end
  end)
  if not ok then res.error = tostring(err) end
  io.write(json(res), "\n")
end
