-- Audio audit: what every hero power and spell actually plays, and why.
-- Run from the repo root:  luajit tools/audio_audit.lua > tools/audio-audit.txt
-- Uses the addon's own resolution code (Client/FX/Sounds.lua), not a copy of it.
package.path = "./?.lua;" .. package.path
local H = require("tests.harness")
local ns = H.LoadEngine()
local S = ns.Sounds

local function exists(path)
  local f = io.open((path:gsub("Interface\\AddOns\\", ""):gsub("\\", "/")), "rb")
  if f then f:close() return true end
  return false
end

local lines, missing = {}, 0
local function out(s) lines[#lines + 1] = s end

out("HERO POWERS  (Hearthstone's hero-power activation + the underlay below)")
local powers = {}
for id, p in pairs(ns.PrintedCards) do
  if p.type == "HERO_POWER" and S.HERO_POWER_UNDERLAY[id] then powers[#powers + 1] = id end
end
table.sort(powers)
for _, id in ipairs(powers) do
  local under = S.HERO_POWER_UNDERLAY[id]
  local file = ns.MatchRecordings[under] or under
  local path = "ForeverHearthstone/Art/Sounds/Cards/" .. file .. ".wav"
  local ok = exists(path)
  if not ok then missing = missing + 1 end
  out(("  %-9s %-18s %-38s %s"):format(id, ns.PrintedCards[id].name, file, ok and "" or "MISSING"))
end

out("")
out("SPELLS  (own recording if HearthSFX has one; otherwise the school underlay)")
local spells, bySchool = {}, {}
for id, p in pairs(ns.PrintedCards) do
  if p.collectible and p.type == "SPELL" then spells[#spells + 1] = id end
end
table.sort(spells, function(a, b) return ns.PrintedCards[a].name < ns.PrintedCards[b].name end)
for _, id in ipairs(spells) do
  local p = ns.PrintedCards[id]
  local own = ns.CardSounds[id] and ns.CardSounds[id].summon
  local school = S.EffectFor(id)
  bySchool[school] = (bySchool[school] or 0) + 1
  local file = own and ("own: " .. (type(own) == "table" and own[1] or own)) or (school .. " -> " .. (ns.MatchRecordings[school] or school))
  out(("  %-9s %-28s %-8s %s"):format(id, p.name, p.class, file))
end
out("")
local counts = {}
for school, n in pairs(bySchool) do counts[#counts + 1] = ("%s %d"):format(school, n) end
table.sort(counts)
out("spells by school: " .. table.concat(counts, ", "))
out(("hero-power underlays missing on disk: %d"):format(missing))
print(table.concat(lines, "\n"))
