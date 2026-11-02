--[[ tests/test_textfit.lua -- text never spills out of its zone, and never "...".

  Hearthstone sets long text smaller; it never truncates a name and never lets
  rules text run into the attack and health badges. Widgets.FitText is the one
  place that guarantees it, and these tests hold every visible label to it:
  a single-line label's UNBOUNDED width fits its box, and wrapped text's
  unclipped height fits its box.

  The stub (tests/wowstub.lua) clips measurements the way WoW does once a box is
  set, which is precisely the trap that left the old shrink loops dead -- so a
  test that measured with GetStringWidth would pass while the game truncated.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local function load(ns)
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true } }
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/UI/Board.lua"))("ForeverHearthstone", ns)
end

local function visible(region)
  local r = region
  while r do
    if rawget(r, "shown") == false then return false end
    r = rawget(r, "parent")
  end
  return true
end

local function size(fs) return (rawget(fs, "font") and fs.font[2]) or 12 end

--- Every visible label with a box and text must fit it, unbounded.
local function auditLabels(H, where)
  local bad = 0
  for _, fs in ipairs(Stub.R.fontstrings) do
    local text = rawget(fs, "text") or ""
    local w, h = rawget(fs, "w") or 0, rawget(fs, "h") or 0
    if text ~= "" and w > 0 and visible(fs) and not text:find("\n") then
      local unbounded = Stub.VisibleLen(text) * size(fs) * 0.5
      if rawget(fs, "wordWrap") == false then
        if unbounded > w + 0.5 then
          bad = bad + 1
          H.ok(false, ("%s: %q (%.0fpx at %dpt) spills its %.0fpx box")
                      :format(where, text, unbounded, size(fs), w))
        end
      elseif h > 0 then
        local lines = math.max(1, math.ceil(unbounded / w))
        local tall = lines * size(fs) * 1.2
        if tall > h + 0.5 then
          bad = bad + 1
          H.ok(false, ("%s: %q needs %.0fpx of height, its box is %.0fpx")
                      :format(where, text, tall, h))
        end
      end
    end
    H.notOk(text:find("%.%.%.$") or text:find("\226\128\166"),
            where .. ": no label is ever truncated to an ellipsis")
  end
  return bad
end

H.suite("textfit: FitText shrinks a long single line instead of truncating", function(ns, H)
  load(ns)
  local f = CreateFrame("Frame")
  local fs = f:CreateFontString(nil, "OVERLAY")
  local used = ns.Widgets.FitText(fs, { text = "Goldshire Footman", w = 80, h = 14,
                                        size = 12, min = 5 })
  H.ok(used < 12, "the size came down")
  H.ok(fs:GetUnboundedStringWidth() <= 80, "and the whole name now fits its box")
  H.eq(fs:GetText(), "Goldshire Footman", "the text itself is untouched")
  H.eq(rawget(fs, "w"), 80, "the box is applied after measuring")
end)

H.suite("textfit: FitText shrinks wrapped text until it fits its height", function(ns, H)
  load(ns)
  local f = CreateFrame("Frame")
  local fs = f:CreateFontString(nil, "OVERLAY")
  local long = "Battlecry: Deal 1 damage to all other characters. Whenever this minion takes damage, draw a card."
  ns.Widgets.FitText(fs, { text = long, w = 90, h = 40, size = 12, min = 3, lines = 6 })
  fs:SetHeight(0)
  H.ok(fs:GetStringHeight() <= 40, "the wrapped text fits the plate")
end)

H.suite("textfit: an auto-fitted label refits when its text or box changes", function(ns, H)
  load(ns)
  local f = CreateFrame("Frame")
  local fs = f:CreateFontString(nil, "OVERLAY")
  fs:SetFont(ns.Fonts.TITLE, 14, "")
  ns.Widgets.AutoFit(fs, { w = 200, h = 20, size = 14 })
  fs:SetText("Short")
  H.eq(fs.font[2], 14, "short text keeps its size")
  fs:SetText("A considerably longer label than the box allows")
  H.ok(fs:GetUnboundedStringWidth() <= 200, "long text shrinks to fit")
  fs:SetSize(400, 20)
  H.ok(fs.font[2] > 7, "a wider box lets it grow back")
  fs:SetFont(ns.Fonts.TITLE, 20, "")
  H.ok(fs:GetUnboundedStringWidth() <= 400, "a new requested size is still fitted")
end)

H.suite("textfit: every card name fits its banner, at hand and zoom sizes", function(ns, H)
  load(ns)
  local resolver = ns.Resolver.New({ printed = ns.PrintedCards, palette = {} })
  local parent = CreateFrame("Frame")
  local w = ns.Widgets.New(parent)
  local worst
  for _, height in ipairs({ 150, 240, 420 }) do
    ns.Widgets.ApplyRect(w, { x = 0, y = 0, w = height * 0.69, h = height })
    for id, card in pairs(ns.PrintedCards) do
      if card.collectible and card.type ~= "HERO" then
        ns.Widgets.SetDescriptor(w, resolver:Card(id))
        local u = w.name:GetUnboundedStringWidth()
        if u > w.nameBox.w + 0.5 then worst = worst or (card.name .. " at " .. height) end
        w.body:SetHeight(0)
        local tall = w.body:GetStringHeight()
        w.body:SetHeight(w.bodyBox.h)
        if tall > w.bodyBox.h + 0.5 then worst = worst or (card.name .. " text at " .. height) end
      end
    end
  end
  H.eq(worst, nil, "every collectible card's name and rules text fit, including Goldshire Footman")
end)

H.suite("textfit: rules text stays above the attack and health badges", function(ns, H)
  load(ns)
  local resolver = ns.Resolver.New({ printed = ns.PrintedCards, palette = {} })
  local parent = CreateFrame("Frame")
  local w = ns.Widgets.New(parent)
  ns.Widgets.ApplyRect(w, { x = 0, y = 0, w = 200, h = 290 })
  ns.Widgets.SetDescriptor(w, resolver:Card("EX1_572"))   -- Ysera: long text
  -- the body is anchored TOP at 0.665h and is 0.18h tall: it ends at 0.845h,
  -- and the badges' tops are at ~0.86h on the 256x512 frame
  local bottom = 0.665 + w.bodyBox.h / 290
  H.ok(bottom <= 0.85, "the text plate ends before the badges begin")
  H.ok(w.bodyBox.w <= 200 * 0.67, "and it is narrower than the frame")
end)

H.suite("textfit: nothing on a busy board spills its box", function(ns, H)
  load(ns)
  local resolver = ns.Resolver.New({ printed = ns.PrintedCards, palette = {} })
  for _, dims in ipairs({ { 1280, 720 }, { 960, 540 }, { 1920, 1080 } }) do
    local board = ns.Board.Create({ resolver = resolver, width = dims[1], height = dims[2],
                                    onIntent = function() end })
    board:SetSnapshot({
      hand = { "CS1_042", "EX1_572", "GVG_110", "EX1_016", "CS2_029", "EX1_620", "NEW1_030" },
      board = { "CS1_042", "EX1_016" }, foeBoard = { "EX1_572" },
      foeHandCount = 5, maxMana = 7, mana = 7,
    })
    board:SetProfiles({ name = "Anexceedinglylongcharactername", level = 60, wins = 120, losses = 99 },
                      { name = "Mage Bot", bot = true })
    auditLabels(H, ("board %dx%d"):format(dims[1], dims[2]))
  end
end)
