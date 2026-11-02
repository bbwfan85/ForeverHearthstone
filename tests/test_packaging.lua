--[[ tests/test_packaging.lua -- does this assemble into an addon WoW can load?

  Everything else in this suite tests behaviour. This tests the thing that makes
  the behaviour reachable at all: the .toc.

  THE FAILURE THIS EXISTS TO CATCH. The test harness has its own load order in
  tests/harness.lua, and the .toc has another. WoW reads only the .toc. So the
  entire suite can be green while the addon fails to load in game, because a
  file was added to the harness and not to the .toc -- or listed in the .toc in
  an order that loads a file before the dependency it captures into a local at
  load time. Nothing else in the project would notice.

  So: the two lists are compared directly, and Main.lua is loaded against the
  strict WoW stub to prove its API calls exist on the Mainline surface.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local TOC = "ForeverHearthstone/ForeverHearthstone.toc"

local function readToc()
  local fh = io.open(TOC, "r")
  if not fh then return nil end
  local meta, files = {}, {}
  for line in fh:lines() do
    line = line:gsub("\r", "")
    local k, v = line:match("^##%s*([^:]+):%s*(.*)$")
    if k then
      meta[k:lower()] = v
    else
      local trimmed = line:match("^%s*(.-)%s*$")
      if trimmed ~= "" and not trimmed:match("^#") then
        -- the .toc uses Windows separators; the harness uses POSIX
        files[#files + 1] = trimmed:gsub("\\", "/")
      end
    end
  end
  fh:close()
  return meta, files
end

H.suite("packaging: the .toc exists and declares the right interface", function(ns, H)
  local meta = readToc()
  H.ok(meta, "the .toc is present -- without it nothing loads at all")
  if not meta then return end
  --[[ Forever is MAINLINE at interface 16001, not Classic. Getting this wrong
       makes the addon show as out of date and load disabled. See docs/07. ]]
  --[[ The TOC may list several interface numbers so the same files load on a
       live retail client for testing. The FIRST is the target -- Forever,
       Mainline, 16001 -- and that is what must not drift. ]]
  local first = tostring(meta["interface"]):match("^%s*(%d+)")
  H.eq(first, "16001", "the target interface is Mainline 16001")
  for extra in tostring(meta["interface"]):gmatch("%d+") do
    H.ok(#extra >= 5, "every listed interface is a real interface number: " .. extra)
  end
  H.ok(meta["title"] and #meta["title"] > 0, "it has a title")
  H.ok(meta["savedvariables"], "and declares its SavedVariables")
end)

H.suite("packaging: every file the .toc lists actually exists", function(ns, H)
  local _, files = readToc()
  H.ok(files and #files > 0, "the .toc lists files")
  for _, rel in ipairs(files or {}) do
    local fh = io.open("ForeverHearthstone/" .. rel, "r")
    H.ok(fh ~= nil, rel .. " exists")
    if fh then fh:close() end
  end
end)

H.suite("packaging: the .toc load order MATCHES the tested load order", function(ns, H)
  --[[ The heart of this file. WoW reads the .toc; the tests read harness.lua.
       If they disagree, a green suite says nothing about whether the addon
       loads -- and the failure in game is a bare Lua error at login with no
       obvious cause. ]]
  local _, tocFiles = readToc()
  if not tocFiles then return end

  -- The harness deliberately does NOT load the two WoW-facing files, because it
  -- has no WoW. Everything else must appear in the same relative order.
  local WOW_ONLY = {
    ["Client/Net/Transport.lua"] = true,
    ["Client/Rewards.lua"] = true,
    ["Client/UI/Widgets.lua"] = true,
    ["Client/UI/Collection.lua"] = true,
    ["Client/UI/Board.lua"] = true,
    ["Client/Main.lua"] = true,
  }

  local tocCore = {}
  for _, rel in ipairs(tocFiles) do
    if not WOW_ONLY[rel] then tocCore[#tocCore + 1] = rel end
  end

  local harnessCore = {}
  for _, path in ipairs(H.LOAD_ORDER) do
    harnessCore[#harnessCore + 1] = path:gsub("^ForeverHearthstone/", "")
  end

  H.eq(#tocCore, #harnessCore,
       "the .toc and the harness load the same NUMBER of files")
  local n = math.min(#tocCore, #harnessCore)
  for i = 1, n do
    H.eq(tocCore[i], harnessCore[i], "load slot " .. i .. " agrees")
  end
  if #tocCore ~= #harnessCore then
    -- name the difference, so the failure says what to add rather than only that
    -- the counts differ
    local inToc = {}
    for _, f in ipairs(tocCore) do inToc[f] = true end
    for _, f in ipairs(harnessCore) do
      H.ok(inToc[f], f .. " is loaded by the tests but MISSING from the .toc")
    end
  end
end)

H.suite("packaging: the WoW-facing files are listed LAST", function(ns, H)
  -- Board and Main capture ns.Controller, ns.Resolver and the engine at load.
  local _, files = readToc()
  if not files then return end
  H.eq(files[#files], "Client/Main.lua", "Main loads last of all")
  local frameFiles = { ["Client/UI/Board.lua"] = true, ["Client/UI/Collection.lua"] = true }
  --[[ Every frame-owning file must come after the platform-free code it
       captures into locals at load time, and before Main, which wires them
       together. ]]
  for i, rel in ipairs(files) do
    if frameFiles[rel] then
      H.ok(i > 1 and i < #files, rel .. " loads after the engine and before Main")
    end
  end
end)

H.suite("packaging: Main.lua loads against the strict stub", function(ns, H)
  --[[ The stub errors on any frame method or event name it does not model, so
       simply loading this file proves every API call it makes exists on the
       Mainline surface -- including that it does NOT register
       COMBAT_LOG_EVENT_UNFILTERED, which errors on registration in Forever. ]]
  Stub.Install(_G)
  Stub.resting = true

  assert(loadfile("ForeverHearthstone/Client/Net/Transport.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/Rewards.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  local chunk = assert(loadfile("ForeverHearthstone/Client/UI/Board.lua"))
  chunk("ForeverHearthstone", ns)
  local mainChunk, err = loadfile("ForeverHearthstone/Client/Main.lua")
  H.ok(mainChunk, "Main.lua parses: " .. tostring(err))
  if not mainChunk then return end
  local ok, ferr = pcall(mainChunk, "ForeverHearthstone", ns)
  H.ok(ok, "Main.lua executes against the stub: " .. tostring(ferr))

  H.ok(_G.SlashCmdList["FOREVERHEARTHSTONE"], "it registered its slash command")
  H.eq(_G.SLASH_FOREVERHEARTHSTONE1, "/fh", "as /fh")
end)

H.suite("packaging: a practice match starts and is playable", function(ns, H)
  --[[ The end-to-end check: from a slash command to a board with cards on it,
       through the real Board, the real Controller and the real engine. If this
       passes, the addon does something when you type /fh. ]]
  Stub.Install(_G)
  Stub.resting = true

  assert(loadfile("ForeverHearthstone/Client/Net/Transport.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/Rewards.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  local chunk = assert(loadfile("ForeverHearthstone/Client/UI/Board.lua"))
  chunk("ForeverHearthstone", ns)
  local mainChunk = assert(loadfile("ForeverHearthstone/Client/Main.lua"))
  mainChunk("ForeverHearthstone", ns)

  -- ADDON_LOADED builds the resolver; the board needs it to render cards.
  local frames = Stub.R.events["ADDON_LOADED"] or {}
  H.ok(#frames > 0, "something listens for ADDON_LOADED")
  for _, f in ipairs(frames) do f:GetScript("OnEvent")(f, "ADDON_LOADED", "ForeverHearthstone") end
  H.ok(ns.Main.resolver, "the asset resolver was built")

  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  Stub.Fire("PLAYER_LOGIN")
  _G.SlashCmdList["FOREVERHEARTHSTONE"]("practice")
  ns.Main.hub.play:Click()
  Stub.Advance(.5)   -- Play ignores the tail of a double click on Choose Deck
  ns.Main.hub.deckChoices[1]:Click()
  ns.Main.hub.play:Click()
  local m = ns.Main
  H.ok(m.game, "a game exists")
  H.ok(m.board, "a board exists")
  H.ok(m.board:IsShown(), "and it is on screen")
  H.ok(m.game.activePlayer == 1 or m.game.activePlayer == 2, "the coin flip chooses a starting player")
  H.ok(m.game:AwaitingMulligan(), "the player chooses an opening hand before either side acts")

  local p = m.game.players[1]
  H.ok(#p.hand > 0, "the player has an opening hand")
  H.ok(#p.deck > 0, "and a deck behind it")
  H.eq(#p.deck + #p.hand, ns.RULES.DECK_SIZE, "which together is a full deck")
  H.noEngineErrors(m.game)
end)

H.suite("packaging: the practice deck is legal for every class", function(ns, H)
  --[[ Built from printed data rather than a hand-written list, so it cannot
       drift from the pin. It must be a legal deck for all nine classes: the
       right size, and no more than two copies of anything. ]]
  for _, class in ipairs({ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
                           "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }) do
    local deck = ns.Controller.BasicDeck(class)
    H.eq(#deck, ns.RULES.DECK_SIZE, class .. " deck is exactly 30 cards")
    local counts, foreign = {}, 0
    for _, id in ipairs(deck) do
      counts[id] = (counts[id] or 0) + 1
      local pr = ns.PrintedCards[id]
      H.ok(pr and pr.collectible, class .. ": " .. tostring(id) .. " is collectible")
      if pr and pr.class ~= class and pr.class ~= "NEUTRAL" then foreign = foreign + 1 end
    end
    H.eq(foreign, 0, class .. " deck has no other class's cards")
    for id, n in pairs(counts) do
      H.ok(n <= 2, class .. ": at most two copies of " .. id .. " (got " .. n .. ")")
    end
  end
end)

H.suite("packaging: the practice deck is deterministic", function(ns, H)
  -- Two clients handed the same class must build the same deck, or the moment
  -- this is used for anything but solo practice the seeds diverge.
  local a = ns.Controller.BasicDeck("MAGE")
  local b = ns.Controller.BasicDeck("MAGE")
  H.eq(#a, #b, "same length")
  for i = 1, #a do H.eq(a[i], b[i], "slot " .. i .. " is the same card") end
end)
