--[[ tests/test_style.lua -- one palette and one set of text styles (docs/24).

  The screens used to choose a size, colour and outline at every call site,
  and drifted: three body sizes, two dialog faces, titles at three heights.
  These hold the screens to W.Style.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local WOW_FILES = {
  "ForeverHearthstone/Client/Net/Transport.lua",
  "ForeverHearthstone/Client/Rewards.lua",
  "ForeverHearthstone/Client/UI/Widgets.lua",
  "ForeverHearthstone/Client/UI/Board.lua",
  "ForeverHearthstone/Client/UI/Collection.lua",
  "ForeverHearthstone/Client/Main.lua",
}

local function withUI(ns, fn)
  Stub.Install(_G)
  Stub.resting = false
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB = {}
  _G.ForeverHearthstoneCharDB = {}
  for _, path in ipairs(WOW_FILES) do assert(loadfile(path))("ForeverHearthstone", ns) end
  ns.Main.collectionUI = nil; ns.Main.collection = nil; ns.Main.rewards = nil
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  return fn(ns.Main, ns)
end

local function source(path)
  local f = assert(io.open(path, "r")); local s = f:read("*a"); f:close(); return s
end

H.suite("style: the screens name a role instead of choosing a font", function(ns, H)
  --[[ Only Widgets.lua sets faces directly (the roles themselves, and the
       card's own internals). A SetFont(ns.Fonts...) anywhere else is a label
       drifting from the shared style again. ]]
  for _, path in ipairs({ "ForeverHearthstone/Client/Main.lua",
                          "ForeverHearthstone/Client/UI/Collection.lua",
                          "ForeverHearthstone/Client/UI/Board.lua" }) do
    local s = source(path)
    local n = 0
    for _ in s:gmatch("SetFont%(%s*ns%.Fonts") do n = n + 1 end
    H.eq(n, 0, path .. " sets fonts through W.ApplyStyle")
  end
end)

H.suite("style: sizes follow the window between each role's limits", function(ns, H)
  withUI(ns, function(Main, ns)
    local W = ns.Widgets
    for role, st in pairs(W.Style) do
      H.eq(W.StyleSize(role, 720), math.floor(math.max(st.min, math.min(st.max, st.size)) + .5), role .. " at the design height")
      H.ok(W.StyleSize(role, 300) >= st.min, role .. " never below its minimum")
      H.ok(W.StyleSize(role, 4000) <= st.max, role .. " never above its maximum")
      H.ok(W.StyleSize(role, 1080) >= W.StyleSize(role, 720), role .. " grows with the window")
    end
  end)
end)

H.suite("style: the main menu's plaques grow with the window, and keep their caps", function(ns, H)
  withUI(ns, function(Main)
    Main:ShowHub(); local hub = Main.hub
    hub:SetSize(1280, 720); hub:Layout()
    local play = hub.buttons[1]
    local small = play.text.font[2]
    H.eq(play.text.styleRole, "buttonLarge")
    hub:SetSize(1920, 1080); hub:Layout()
    H.ok(play.text.font[2] > small, "the plaque's lettering is larger in a larger window")
    -- a 3-slice: two caps as tall as the plaque, the middle between them
    local l, r = play.caps[1], play.caps[2]
    H.ok(l.shown and r.shown, "both gilded caps drawn")
    H.eq(l.h, play:GetHeight()); H.ok(l.w < play:GetWidth() / 2)
    H.ok(math.abs(play.bg.w - (play:GetWidth() - l.w - r.w)) < .01, "the stone middle spans between the caps")
  end)
end)

H.suite("style: the two confirmation dialogs are the same dialog", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection(); local c = Main.collection
    c:Add("CS1_069", 1)
    for _, e in ipairs(c:Browse({ all = true })) do if e.cardId == "CS1_069" then ui.selected = e end end
    ui:DisenchantSelected()
    local d = ui.disenchantDialog
    H.ok(d and d.message, "a disenchant dialog")
    H.eq(d.message.styleRole, "dialog")
    H.eq(#d.buttons, 2)
    H.eq(d.buttons[1].text:GetText(), "Disenchant")
  end)
end)
