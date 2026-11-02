--[[ tools/layout_preview.lua -- dump a computed layout as JSON.

  WHY THIS EXISTS. Layout.lua is pure arithmetic and the tests prove its
  invariants (nothing overlaps, nothing leaves the window, seven minions always
  fit). What they cannot prove is whether the result lines up with the BOARD
  ART, which is a picture of a table with a playing surface, hero sockets, deck
  slots and an End Turn plaque already painted on it.

  Checking that by launching WoW and squinting is the slowest loop in this
  project. This dumps the solver's output so tools/layout_preview.py can draw it
  straight onto the board texture, which turns "the hand sits too low" into
  something you can see in a second without a client.

      lua tools/layout_preview.lua 1600 900 > layout.json

  It loads ONLY the platform-free files, exactly as tests/harness.lua does, so
  it stays runnable in a terminal.
]]
package.path = "./?.lua;" .. package.path

local ns = {}
for _, path in ipairs({
  "ForeverHearthstone/Engine/Enums.lua",
  "ForeverHearthstone/Client/UI/Layout.lua",
}) do
  assert(loadfile(path))("ForeverHearthstone", ns)
end

local W = tonumber(arg[1]) or 1600
local H = tonumber(arg[2]) or 900

local L = ns.Layout.Compute({
  width = W, height = H,
  handCount     = tonumber(arg[3]) or 7,
  foeHandCount  = 6,
  boardCount    = tonumber(arg[4]) or 5,
  foeBoardCount = 4,
  hasWeapon = true, foeHasWeapon = false,
  maxMana = 7,
  foeMaxMana = 7,
})

-- A deliberately tiny JSON writer: this is a developer tool, the shapes are
-- known, and a dependency here would make the tool harder to run than the
-- thing it is inspecting.
local out = {}
local function num(v) return string.format("%.3f", v) end
local function rect(r)
  return ("{\"x\":%s,\"y\":%s,\"w\":%s,\"h\":%s,\"rot\":%s}"):format(num(r.x), num(r.y), num(r.w), num(r.h), num(r.rot or 0))
end

local function emit(name, r)
  if type(r) ~= "table" then return end
  if r.x then
    out[#out + 1] = ("\"%s\":%s"):format(name, rect(r))
  else
    local parts = {}
    for i, sub in ipairs(r) do parts[i] = rect(sub) end
    if #parts > 0 then
      out[#out + 1] = ("\"%s\":[%s]"):format(name, table.concat(parts, ","))
    end
  end
end

for _, name in ipairs({
  "field", "hero", "foeHero", "heroPower", "foeHeroPower", "weapon", "foeWeapon",
  "deck", "foeDeck", "endTurn", "rope", "manaReadout", "foeManaReadout",
}) do emit(name, L[name]) end
for _, name in ipairs({
  "boardSlots", "foeBoardSlots", "handSlots", "foeHandSlots", "manaCrystals",
  "secrets", "foeSecrets", "dropZones", "historySlots", "foeManaCrystals",
}) do emit(name, L[name]) end

print(("{\"width\":%d,\"height\":%d,%s}"):format(W, H, table.concat(out, ",")))
