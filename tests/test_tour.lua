--[[ tests/test_tour.lua -- the developer screenshot tour (FHTour/), headless.

  The tour runs inside the real client, where a broken scene costs a whole
  restart-and-reload round trip to discover. Here every scene runs against the
  stub first: none may error, the self-playing match must actually play, and --
  the part that matters most -- the player's saved collection must come out
  exactly as it went in, however many packs the tour opened.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local function serialize(v, seen)
  if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. serialize(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

H.suite("tour: every scene runs, the match plays, the collection is untouched", function(ns, H)
  Stub.Install(_G)
  Stub.xp = 1000
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB, _G.FHTourDB = {}, {}, nil
  _G.Screenshot = function() Stub.Fire("SCREENSHOT_SUCCEEDED") end
  _G.time, _G.date = rawget(_G, "time") or os.time, rawget(_G, "date") or os.date   -- WoW globals
  for _, path in ipairs({ "Net/Transport", "Rewards", "UI/Widgets", "UI/Board", "UI/Collection", "Main" }) do
    assert(loadfile("ForeverHearthstone/Client/" .. path .. ".lua"))("ForeverHearthstone", ns)
  end
  assert(loadfile("FHTour/Config.lua"))()
  assert(loadfile("FHTour/Tour.lua"))()
  local Main = ns.Main
  Main.rewards, Main.collection, Main.session = nil, nil, nil

  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  local db, cdb = ForeverHearthstoneDB, ForeverHearthstoneCharDB
  local before = serialize(db) .. serialize(cdb)
  local packs = Main.collection:TotalPacks()

  -- run 1 in the client: the hub's deck book stayed drawn over the whole match
  local hubOverMatch, shoot = false, FHTour.Shoot
  FHTour.Shoot = function(self, name, done)
    if name:find("^live%-") and Main.hub and Main.hub:IsShown() then hubOverMatch = true end
    return shoot(self, name, done)
  end

  for _ = 1, 6000 do
    Stub.Advance(0.1)
    if FHTour.finished then break end
  end
  H.ok(FHTour.finished, "the tour finished inside its watchdog")
  for _, e in ipairs(FHTour.errors) do H.ok(false, ("%s: %s"):format(e.where, e.err)) end
  local names = {}
  for _, s in ipairs(FHTour.shots) do names[s.name] = true end
  for _, want in ipairs({ "hub", "collection", "pack-reveal-all", "settings-odds", "toast-card",
                          "board-states", "match-postgame", "live-01" }) do
    H.ok(names[want], "photographed " .. want)
  end
  H.ok(#FHTour.shots >= 40, ("%d photographs"):format(#FHTour.shots))
  H.notOk(hubOverMatch, "the menu is closed while the match is photographed")
  FHTour.Shoot = shoot

  H.ok(ForeverHearthstoneDB == db and ForeverHearthstoneCharDB == cdb, "the original tables are back")
  H.eq(serialize(db) .. serialize(cdb), before, "and not one field of them changed")
  H.eq(Main.collection:TotalPacks(), packs, "the pack the tour opened was the sandbox's")
  H.eq(FHTourDB.lastRun, FHTOUR_RUN, "the run is recorded, so a plain /reload does not repeat it")

  -- a /reload without a bump does nothing
  FHTour.finished = nil
  FHTour_Attach(ns, Main)
  Stub.Advance(10)
  H.ok(not FHTour.running, "no second run without a new FHTOUR_RUN")
  _G.Screenshot = nil
end)
