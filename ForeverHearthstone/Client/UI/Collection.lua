--[[ Client/UI/Collection.lua

  THE OUT-OF-MATCH APP: collection, deck builder, crafting, pack opening.

  Same shape as Client/UI/Board.lua and for the same reasons. It owns frames,
  pools widgets, asks CollectionLayout.lua where everything goes, and reports
  what the player did. It contains no economy rules -- what a card costs, what
  may go in a deck, what is in a pack -- because all of that lives in
  Client/Collection.lua and Client/Packs.lua, where it is tested headless.

  THREE MODES, ONE SCREEN (see CollectionLayout's header): browsing, editing a
  deck, and opening a pack. The grid of cards is the same grid throughout, which
  is why a card you just crafted is already in front of you.

  CARDS ARE DRAWN BY ns.CardWidget -- literally the board's own card code. A
  card therefore looks the same here as it does on the table, including how it
  degrades when its art is missing.

  POOLING: WoW cannot destroy a frame. Every widget is acquired from a pool and
  released back, never discarded, or browsing 500 cards leaks 500 frames per
  page turn.
]]
local ADDON, ns = ...
local CL = ns.CollectionLayout
local W = ns.Widgets
local CardWidget = ns.CardWidget

local CollectionUI = {}
CollectionUI.__index = CollectionUI
ns.CollectionUI = CollectionUI

-- a label in one of the shared text roles (W.Style)
local function fs(parent, role, justify)
  local t = W.StyledText(parent, role)
  t:SetJustifyH(justify or "LEFT")
  return t
end

local makeButton = W.MenuButton
local ART = "Interface\\AddOns\\ForeverHearthstone\\Art\\"
-- A card's deck-list strip (Art/DeckTile). ONE place builds the path:
-- tools/package_release.py rewrites it to the packaged .jpg and checks it
-- found exactly one.
local function deckTilePath(id) return ART .. "DeckTile\\" .. id .. ".tga" end

--[[ A round Hearthstone button drawn from one texture -- a class crest or a
     mana crystal -- with a soft glow behind it when it is the one chosen. ]]
local function iconButton(parent, texture, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:EnableMouse(true); b:RegisterForClicks("LeftButtonUp")
  b.glow = b:CreateTexture(nil, "BACKGROUND")
  b.glow:SetTexture(ART .. "crest-glow.tga"); b.glow:SetBlendMode("ADD")
  b.glow:SetVertexColor(1, .8, .35, .95)
  b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -8, 8); b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 8, -8)
  b.glow:Hide()
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexture(texture)
  b.text = b:CreateFontString(nil, "OVERLAY"); b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
  W.ApplyStyle(b.text, "number")
  function b:SetChosen(chosen, dimmed)
    self.chosen, self.dimmed = chosen, dimmed
    self.glow:SetShown(chosen == true)
    local v = dimmed and .62 or 1
    self.icon:SetVertexColor(v, v, v, 1)
  end
  b:SetScript("OnClick", function()
    if ns.Sounds then ns.Sounds.Play("menu_click") end
    onClick()
  end)
  b:SetScript("OnEnter", function()
    b.icon:SetVertexColor(1, 1, 1, 1)
    if ns.Sounds then ns.Sounds.PlayMenuHover() end
  end)
  b:SetScript("OnLeave", function() b:SetChosen(b.chosen, b.dimmed) end)
  return b
end

-- ============================================================ construction

function CollectionUI.Create(opts)
  opts = opts or {}
  local u = setmetatable({}, CollectionUI)
  u.collection = opts.collection
  u.resolver   = opts.resolver
  -- said in chat AND on the window: chat is behind it ("deck is full", "crafted ...")
  local printer = opts.onPrint or function() end
  u.onPrint    = function(msg) printer(msg); u:Toast(msg) end
  u.page       = 1
  u.scrollRow  = 0
  u.filter     = {}
  u.selected   = nil
  u.deckIndex  = nil

  local f = CreateFrame("Frame", "ForeverHearthstoneCollection", UIParent)
  u.frame = f
  local w, h = opts.width or 1280, opts.height or 720
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  -- the same strata as the main menu, so the two windows behave as one app
  f:SetFrameStrata("FULLSCREEN")
  f:SetMovable(true)
  f:SetResizable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(s) s:StartMoving() end)
  f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
  f:SetResizeBounds(CL.MinSize())      -- Mainline: NOT the removed SetMinResize
  local minW, minH = CL.MinSize()
  local maxW, maxH = CL.MaxSize()
  f:SetResizeBounds(minW, minH, maxW, maxH)

  f.bg = f:CreateTexture(nil, "BACKGROUND", nil, -2)
  f.bg:SetAllPoints()
  f.bg:SetTexture("Interface\\AddOns\\ForeverHearthstone\\Art\\tavern-cabinet.tga")
  f.bg:SetVertexColor(.55,.48,.4,1)
  --[[ Hearthstone's collection is a BOOK on the table: a leather cover with a
       carved rim, two parchment pages with a shadowed spine, class crests along
       the top and a dark tray of controls underneath. ]]
  u.tray=W.TrayPanel(f)
  u.bookPanel=W.MenuPanel(f,"leather")
  u.bookPanel.bg:SetVertexColor(.42,.24,.14,1)
  u.sidebarPanel=W.TrayPanel(f)
  for _,panel in ipairs({u.tray,u.bookPanel,u.sidebarPanel}) do panel:SetFrameLevel(f:GetFrameLevel()) end
  --[[ Hearthstone's Open Packs room, whole (tools/build_pack_room.py): the
       purple tray your packs wait in, the wooden frame with its painted
       "Open Packs" plaque, and the stone well. Opening a pack darkens it. ]]
  --[[ Behind the pack room, the whole frame in near-black, ANCHORED to its
       corners rather than sized: the room and its bands are sized from the
       last layout, and a window whose size WoW had not reported yet left a
       strip of the tavern showing under them (reported with a screenshot). ]]
  u.packBackdrop=f:CreateTexture(nil,"BACKGROUND",nil,0)
  u.packBackdrop:SetAllPoints(); u.packBackdrop:SetColorTexture(0.025,0.02,0.022,1); u.packBackdrop:Hide()
  u.packScene=f:CreateTexture(nil,"BACKGROUND",nil,1)
  u.packScene:SetTexture(ART.."pack-room.tga"); u.packScene:Hide()
  u.packDim=f:CreateTexture(nil,"BACKGROUND",nil,2)
  u.packDim:SetColorTexture(0,0,0,.62); u.packDim:Hide()
  u.packLabels={}
  u.pages = {}
  for i=1,2 do
    local paper=f:CreateTexture(nil,"BACKGROUND",nil,1)
    paper:SetTexture(ART.."menu-parchment.tga")
    paper:SetVertexColor(1,.96,.86,1)
    u.pages[i]=paper
  end
  -- The fold: a dark strip with each page's shadow falling away from it.
  u.bookSpine=f:CreateTexture(nil,"BACKGROUND",nil,4)
  u.bookSpine:SetTexture(ART.."menu-leather.tga"); u.bookSpine:SetVertexColor(.3,.16,.09,1)
  u.bookSpine:Hide()
  u.spineShade={}
  for i=1,2 do
    local shade=f:CreateTexture(nil,"BACKGROUND",nil,3)
    shade:SetTexture(ART.."page-shade.tga")
    if i==1 then shade:SetTexCoord(1,0,0,1) else shade:SetTexCoord(0,1,0,1) end
    shade:Hide(); u.spineShade[i]=shade
  end
  u.pageTitles={}
  for i=1,2 do
    local t=fs(f,"pageTitle","CENTER"); t:Hide()
    u.pageTitles[i]=t
  end
  u.tabs={}

  u.grip = W.ResizeGrip(f, CL.MinSize())

  u.cardPool = CardWidget.NewPool(function(parent) return CardWidget.New(parent) end)
  --[[ The burst that goes off when a pack cracks and when a legendary turns
       over. Pooled and capped, like the board's. ]]
  u.particles = W.NewParticles(f)

  u.progressText = fs(f, "header")
  u.progressHelp = CreateFrame("Frame",nil,f)
  u.progressHelp:EnableMouse(true)
  u.progressHelp:SetScript("OnEnter",function()
    if GameTooltip then
      GameTooltip:SetOwner(u.progressHelp,"ANCHOR_RIGHT")
      GameTooltip:SetText("Collection total: your class and Neutral cards. Other classes are excluded, even when browsing their class filter.")
      GameTooltip:Show()
    end
  end)
  u.progressHelp:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  u.dustText     = fs(f, "header")
  --[[ The count and the dust sat straight on the table art, which is busy
       and light enough to swallow them. A dark nameplate strip behind the
       pair, as Hearthstone keeps its currency on a plate. Textures on the
       main frame so they stay under the text; the anchor only positions them. ]]
  u.statsAnchor = CreateFrame("Frame", nil, f)
  u.statsPlate  = W.NamePlate(f, "ARTWORK")
  u.statsPlate:SetShown(false)
  u.pageText     = fs(f, "pageText", "CENTER")
  u.hintText     = fs(f, "subtitle", "CENTER")
  u.deckText     = fs(f, "header")
  u.deckText:SetJustifyV("TOP")
  u.deckHint=fs(f,"pageText","CENTER"); u.deckHint:Hide()
  -- the screen's name on the shared stone plaque (My Decks)
  u.titlePlaque=W.TitlePlaque(f); u.titlePlaque:Hide()
  -- Labels inside fixed zones shrink to stay inside them (Widgets.FitText).
  for _, t in ipairs({u.progressText, u.dustText, u.pageText, u.deckText}) do
    W.AutoFit(t, { w = 100, h = 20, font = ns.Fonts.TITLE, size = 14, min = 7 })
  end
  for _, t in ipairs({u.hintText, u.deckHint}) do
    W.AutoFit(t, { w = 100, h = 40, font = ns.Fonts.TITLE, size = 14, min = 8, lines = 3 })
  end
  u.deckName=CreateFrame("EditBox",nil,f)
  u.deckName:SetAutoFocus(false)
  -- set once, in its final face: the deck's name on its banner
  u.deckName:SetFont(W.StyleFont("label"), 16, "OUTLINE"); u.deckName:SetTextColor(1,.96,.86,1)
  u.deckName:SetText(""); u.deckName:Hide()
  u.deckName:EnableMouse(true)
  u.deckName:SetScript("OnEditFocusLost",function(box)
    local deck=u:CurrentDeck(); local name=box:GetText():match("^%s*(.-)%s*$")
    if deck and name~="" then deck.name=name:sub(1,36) end
  end)
  u.deckName:SetScript("OnEnterPressed",function(box)
    local deck=u:CurrentDeck(); local name=box:GetText():match("^%s*(.-)%s*$")
    if deck and name~="" then deck.name=name:sub(1,36) end
    box:ClearFocus(); u:Relayout()
  end)
  u.deckName:SetScript("OnEscapePressed",function(box) box:ClearFocus(); u:Relayout() end)
  -- the name is editable, which nothing about a banner says on its own
  u.deckName:SetScript("OnEnter",function(box)
    if GameTooltip then GameTooltip:SetOwner(box,"ANCHOR_TOP"); GameTooltip:SetText("Click to rename this deck"); GameTooltip:Show() end
  end)
  u.deckName:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  u.emptyText=fs(f,"pageTitle","CENTER")
  u.emptyText:SetText("No cards match these filters"); u.emptyText:Hide()
  u.search=CreateFrame("EditBox",nil,f)
  u.search:SetAutoFocus(false); u.search:SetFont(W.StyleFont("bodyInk"), W.StyleSize("bodyInk"), "")
  u.search:EnableMouse(true)
  u.search:SetTextInsets(10,10,0,0)
  u.search.bg=u.search:CreateTexture(nil,"BACKGROUND"); u.search.bg:SetAllPoints()
  u.search.bg:SetTexture(ART.."menu-parchment.tga")
  u.search.rim=W.GoldFrame(u.search,6,"BORDER")
  u.search:SetScript("OnSizeChanged",function(_,w,h) u.search.rim:Layout(w,h) end)
  u.search:SetTextColor(.2,.12,.06,1); u.search:SetText("")
  -- the placeholder in the same face as what you type, only fainter
  u.searchHint=fs(u.search,"bodyInk"); u.searchHint:SetPoint("LEFT",u.search,"LEFT",10,0)
  W.ApplyStyle(u.searchHint,"bodyInk",nil,nil,{.42,.32,.22})
  u.searchHint:SetText("Search cards")
  u.search:SetScript("OnTextChanged",function(box)
    u.filter.text=box:GetText(); u.scrollRow=0; u:Relayout()
  end)
  u.search:SetScript("OnEscapePressed",function(box) box:ClearFocus() end)
  u.search:SetScript("OnEnterPressed",function(box) box:ClearFocus() end)
  u.manaButtons={}
  -- Hearthstone's mana crystals, 0 to 7+, as the cost filter.
  for cost=0,7 do
    local value=cost
    local button=iconButton(f,ART.."mana_crystal.tga",function()
      if u.filter.cost==value then u.filter.cost=nil else u.filter.cost=value end
      u.scrollRow=0; u:Relayout()
    end)
    button.text:SetText(cost==7 and "7+" or tostring(cost))
    -- measured in run 4: the digit sat ~1.3px low in a 35px crystal (docs/39)
    button.text:ClearAllPoints()
    button.text:SetPoint("CENTER",button,"CENTER",0,0)
    button:HookScript("OnSizeChanged",function(_,_,h)
      button.text:ClearAllPoints()
      button.text:SetPoint("CENTER",button,"CENTER",(h or 0)*W.CRYSTAL_DIGIT.filterX,(h or 0)*W.CRYSTAL_DIGIT.filterY)
    end)
    u.manaButtons[#u.manaButtons+1]=button
  end

  -- Page turns are the gold arrows on the book's edges.
  u.prevButton = makeButton(f, "", function() u:TurnPage(-1) end)
  u.nextButton = makeButton(f, "", function() u:TurnPage(1) end)
  for i,b in ipairs({u.prevButton,u.nextButton}) do
    b.bg:SetTexture(ART.."page-arrow.tga")
    if i==1 then b.bg:SetTexCoord(1,0,0,1) else b.bg:SetTexCoord(0,1,0,1) end
    b:SetFrameLevel(f:GetFrameLevel()+30)
  end
  u.craftButton = makeButton(f, "Craft", function() u:CraftSelected() end)
  u.dustButton  = makeButton(f, "Disenchant", function() u:DisenchantSelected() end)
  u.packButton  = makeButton(f, "Packs", function() u:ShowPackRoom() end)
  u.ownedButton = makeButton(f, "Owned", function()
    u.filter.all=not u.filter.all; u.scrollRow=0; u:Relayout()
  end)
  u.classButton = makeButton(f, "All classes", function() u:ToggleFilters() end)
  if UISpecialFrames then table.insert(UISpecialFrames, "ForeverHearthstoneCollection") end
  f:EnableMouseWheel(true)
  f:SetScript("OnMouseWheel", function(_, delta) u:Scroll(-delta) end)
  u.inspect = W.NewInspect(f)
  u.inspect.frame:SetFrameLevel(300)
  u.inspect.frame:SetScript("OnClick", function() u.inspect.frame:Hide() end)
  -- the footer's own Craft/Disenchant come back when the card is put down
  u.inspect.frame:HookScript("OnHide", function() u.inspectingCard = nil; if u.frame:IsShown() then u:Relayout() end end)
  u.inspectCraft = makeButton(u.inspect.frame, "Craft", function() u:CraftSelected(); u.inspect.frame:Hide() end)
  u.inspectDust = makeButton(u.inspect.frame, "Disenchant", function() u:DisenchantSelected() end)
  -- while editing a deck: this card on the deck's box, or back to the automatic pick
  u.inspectArt = makeButton(u.inspect.frame, "Use as Deck Art", function() u:ToggleDeckArt() end)
  u.inspectArt:Hide()
  -- what crafting it would cost, and what you have, under the enlarged card
  u.inspectCost = W.StyledText(u.inspect.frame, "dialog")
  for i, button in ipairs({u.inspectCraft, u.inspectDust, u.inspectArt}) do
    button:SetFrameLevel(470)
    button:SetSize(170, 36)
    button:SetPoint("CENTER", u.inspect.frame, "CENTER", (i-1.5)*155, -230)
  end
  -- every window's corner: close, Main Menu, My Decks here, the speaker
  u.corner = W.WindowControls(f, {
    onHome = function() u:Hide(); if ns.Main then ns.Main:ShowHub() end end,
    onToggleMute = ns.Main and function() ns.Main:ToggleMute() end or nil,
  })
  u.closeButton, u.homeButton, u.speaker = u.corner.close, u.corner.home, u.corner.speaker
  u.effectPool = CardWidget.NewPool(function(parent) return CardWidget.New(parent) end)
  u.decksButton=makeButton(f,"My Decks",function() u:ShowDecks() end)
  u.decksButton:SetSize(W.CORNER.homeW,W.CORNER.homeH)
  u.corner:Add(u.decksButton)

  f:SetScript("OnSizeChanged", function() u:Relayout() end)
  f:SetScript("OnHide",function()
    u.packDragging=nil
    if u.disenchantDialog then u.disenchantDialog:Hide() end
    if u.craftDialog then u.craftDialog:Hide() end   -- never re-armed on the next open
    if u.packBack then u.packBack:StopMovingOrSizing() end
    u:StopFX()
  end)
  --[[ Built hidden. The screen is created on first use and then kept, so
       opening it is a Show rather than a build -- but creating it must not put
       it on screen, or `/fh collection` would toggle it straight back off. ]]
  f:Hide()
  u:Relayout()
  return u
end

function CollectionUI:Show()
  if not self.frame:IsShown() then ns.Sounds.Play("menu_page") end
  self.frame:Show(); self:Relayout()
end
function CollectionUI:Hide() self:StopFX(); self.frame:Hide() end
function CollectionUI:IsShown() return self.frame:IsShown() end
function CollectionUI:Toggle()
  if self:IsShown() then self:Hide() else self:Show() end
end

-- ================================================================ layout

local function place(widget, r, parent)
  widget:ClearAllPoints()
  widget:SetSize(math.max(1, r.w), math.max(1, r.h))
  widget:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", r.x, r.y)
end

--[[ The entries currently being browsed. Recomputed rather than cached, because
     every operation that could change it (craft, disenchant, open a pack) is a
     player action and none of them happen sixty times a second. ]]
function CollectionUI:Entries()
  if not self.collection then return {} end
  local filter = {}
  for k, v in pairs(self.filter) do filter[k] = v end
  if self.deckIndex or not filter.class then
    --[[ While editing a deck the grid shows only what may legally go IN it:
         this class plus neutrals. Showing cards that cannot be added is how a
         deck builder wastes the player's clicks. ]]
    filter.playable = self.collection.character.class
  end
  return self.collection:Browse(filter)
end

function CollectionUI:Relayout()
  self.progressHelp:Hide()
  self:StopFX(true)
  if self.inspect and self.inspect.frame:IsShown() then
    --[[ Redraw what is being READ: a pack card shown with InspectCard stayed
         itself, not the browser's old selection with live Craft/Disenchant. ]]
    local shown = self.inspectingCard
    if shown then self:InspectCard(shown.cardId, shown.golden)
    elseif self.selected then self:InspectSelected() else self.inspect.frame:Hide() end
  end
  local f = self.frame
  local w, h = f:GetWidth(), f:GetHeight()
  W.RestyleAll(f, h)
  self.titlePlaque:Hide()
  local entries = self:Entries()
  if self.deckPreview then self.deckPreview.frame:Hide() end
  self:HideMenuItems(not (self.packRoom or self.deckBrowser or self.pack or self.bulk))
  self:HideBulk()

  if self.bulk then self:LayoutBulk(); return end
  if self.packRoom and not self.pack then self:LayoutPackRoom(); return end
  if self.deckBrowser then self:LayoutDecks(); return end
  if self.pack then
    self:LayoutPack(w, h)
    return
  end

  local tabs = self:TabSpecs()
  local L = CL.Compute({ w = w, h = h, deckOpen = self.deckIndex ~= nil,
                         selected = self.selected ~= nil, tabCount = #tabs })
  if self.L and self.L.cols and self.L.cols~=L.cols then
    self.scrollRow=math.floor((self.scrollRow or 0)*self.L.cols/L.cols)
  end
  self.L = L
  place(self.tray,L.footer,f); self.tray:Show()
  place(self.bookPanel,L.book,f); self.bookPanel:Show()
  place(self.search,L.search,f); self.search:Show()
  if self.search:GetText()=="" then self.searchHint:Show() else self.searchHint:Hide() end
  for i,button in ipairs(self.manaButtons) do
    place(button,L.manaFilters[i],f); button:Show()
    W.ApplyStyle(button.text,"number",h,math.max(11,L.manaFilters[i].h*.42))
    button:SetChosen(self.filter.cost==i-1, self.filter.cost~=nil and self.filter.cost~=i-1)
  end
  self:LayoutTabs(tabs, L)
  for _, control in ipairs({self.packButton,self.classButton,self.progressText,self.dustText,self.pageText}) do control:Show() end
  self.statsPlate:SetShown(true)
  self:LayoutPages(L.pages, L.spine, self:PageTitle())
  local pages = CL.PageCount(#entries, L.pageSize)
  if self.page > pages then self.page = pages end
  if self.page < 1 then self.page = 1 end

  CardWidget.ReleaseAll(self.cardPool)
  self.slots = {}
  self.maxScrollRow = math.max(0, math.ceil(#entries / L.cols) - L.rows)
  self.scrollRow = math.max(0, math.min(self.scrollRow or 0, self.maxScrollRow))
  local first = self.scrollRow * L.cols
  self.page=math.floor(self.scrollRow/L.rows)+1
  for i = 1, L.pageSize do
    local entry = entries[first + i]
    local r = L.cards[i]
    if entry and r then
      local widget = CardWidget.Acquire(self.cardPool, f)
      CardWidget.ApplyRect(widget, r)
      CardWidget.SetDescriptor(widget, self.resolver:Card(entry.cardId))
      self:DecorateSlot(widget, entry)
      widget.frame:SetScript("OnEnter",function()
        widget.glow:SetVertexColor(1,.86,.45,.8); widget.glow:Show()
        if ns.Sounds then ns.Sounds.PlayMenuHover() end
      end)
      widget.frame:SetScript("OnLeave",function() self:DecorateSlot(widget,entry) end)
      widget.frame:SetScript("OnClick", function(_, button)
        self:OnCardClick(entry, button)
      end)
      widget.frame:EnableMouseWheel(true)
      widget.frame:SetScript("OnMouseWheel", function(_, delta) self:Scroll(-delta) end)
      self.slots[i] = { widget = widget, entry = entry }
    end
  end

  place(self.progressText, L.progress, f)
  place(self.dustText, L.dust, f)
  do
    local padX, padY = L.dust.h * 0.9, L.dust.h * 0.12
    local plate = { x = L.progress.x - padX, y = L.dust.y - padY,
                    w = L.dust.x + L.dust.w - L.progress.x + padX * 1.6, h = L.dust.h + padY * 2 }
    place(self.statsAnchor, plate, f)
    self.statsPlate:Layout(plate.w, plate.h, self.statsAnchor)
  end
  place(self.pageText, L.pageText, f)
  place(self.prevButton, L.prevPage, f)
  place(self.nextButton, L.nextPage, f)
  place(self.packButton, L.openPack, f)
  place(self.classButton, L.classTab, f)
  place(self.ownedButton,L.ownedToggle,f); self.ownedButton:Show()
  self.ownedButton.text:SetText(self.filter.all and "All cards" or "Owned")
  self.decksButton:Show()

  --[[ Not while a card is being inspected: the inspect view has its own pair,
       and the footer's showed through its dim as a second, smaller one (the
       in-client tour, docs/39). ]]
  if L.craft and not self.inspect.frame:IsShown() then
    self.craftButton:Show(); self.dustButton:Show()
    place(self.craftButton, L.craft, f)
    place(self.dustButton, L.disenchant, f)
    local entry = self.selected
    self.craftButton:SetEnabledLook(entry and entry.canCraft or false)
    self:LabelCraftButtons(entry, self.craftButton, self.dustButton)
    self.dustButton:SetEnabledLook(entry and self.collection:CanDisenchant(
      entry.cardId, entry.owned == 0 and entry.golden > 0) or false)
  else
    self.craftButton:Hide(); self.dustButton:Hide()
  end

  if L.deckPanel then
    place(self.sidebarPanel,L.deckPanel,f); self.sidebarPanel:Show()
    self:LayoutDeckRows(L.deckPanel)
  else
    self.deckText:Hide()
  end
  self.hintText:Hide()
  if #entries==0 then place(self.emptyText,L.grid,f); self.emptyText:Show() end

  local owned, total, golden = self.collection:Progress(function(p)
    return p.class=="NEUTRAL" or p.class==self.collection.character.class
  end)
  self.progressText:SetText(("Collected %d/%d"):format(owned, total))
  place(self.progressHelp,L.progress,f); self.progressHelp:Show()
  self.dustText:SetText(("Dust %d"):format(self.collection:Dust()))
  self.dustText:SetJustifyH("RIGHT"); self.progressText:SetJustifyH("RIGHT")
  local totalPages=math.max(1,math.ceil(math.ceil(#entries/L.cols)/L.rows))
  self.pageText:SetText(("Page %d of %d"):format(math.min(totalPages,self.page),totalPages))

  self.prevButton:SetEnabledLook(self.scrollRow>0)
  self.nextButton:SetEnabledLook(self.scrollRow<self.maxScrollRow)
  self.packButton:SetEnabledLook(true)
  self.packButton.text:SetText(("Packs (%d)"):format(self.collection:TotalPacks()))
  self.prevButton:Show(); self.nextButton:Show()
end

--[[ The book's pages: one or two sheets of parchment, the fold between them,
     and the class name across the top of each page. `pages` are rects; a nil
     spine means a single page. ]]
function CollectionUI:LayoutPages(pages, spine, title)
  local f=self.frame
  for i,paper in ipairs(self.pages) do
    local r=pages and pages[i]
    paper:SetShown(r~=nil); if r then place(paper,r,f) end
    local t=self.pageTitles[i]
    local band=self.L and self.L.pageTitles and self.L.pageTitles[i]
    if r and band and title then
      place(t,band,f); t:SetText(title); W.ApplyStyle(t,"pageTitle",nil,math.min(W.StyleSize("pageTitle",f:GetHeight()),band.h*.85)); t:Show()
    else t:Hide() end
  end
  self.bookSpine:SetShown(spine~=nil)
  for i,shade in ipairs(self.spineShade) do
    shade:SetShown(spine~=nil)
    if spine then
      local sw=math.min(90,pages[1].w*.18)
      place(shade,{x=i==1 and spine.x-sw or spine.x+spine.w,y=spine.y,w=sw,h=spine.h},f)
    end
  end
  if spine then place(self.bookSpine,spine,f) end
end

--[[ The class crests along the top of the book. Browsing shows every class;
     building a deck shows only what may go in it. ]]
function CollectionUI:LayoutTabs(tabs, L)
  for i,spec in ipairs(tabs) do
    local b=self.tabs[i]
    if not b then
      b=iconButton(self.frame,nil,function() self:SetFilter(self.tabs[i].filterIndex) end)
      self.tabs[i]=b
    end
    b.icon:SetTexture(ART.."class-"..spec.icon..".tga")
    b.filterIndex=spec.index
    place(b,L.tabs[i],self.frame); b:Show()
    local current=(self.filterIndex or 1)==spec.index
    b:SetChosen(current, not current)
  end
  for i=#tabs+1,#self.tabs do self.tabs[i]:Hide() end
end

function CollectionUI:HideMenuItems(keepSearch)
  if not keepSearch then self.search:Hide() end
  if self.filterMenu then self.filterMenu:Hide() end
  for _,panel in ipairs({self.tray,self.bookPanel,self.sidebarPanel,self.emptyText,self.decksButton,self.deckName,self.deckHint,self.ownedButton}) do panel:Hide() end
  for _,button in ipairs(self.manaButtons or {}) do button:Hide() end
  for _,button in ipairs(self.tabs or {}) do button:Hide() end
  if self.deckBanner then self.deckBanner:Hide() end
  self.packScene:Hide(); self.packDim:Hide(); self:HidePackRoomBands()
  if self.packDone then self.packDone:Hide() end
  for _,t in ipairs(self.packLabels or {}) do t:Hide() end
  for _,t in ipairs(self.packExtras or {}) do t:Hide() end
  for _,t in ipairs(self.packStamps or {}) do t:Hide() end
  self.bookSpine:Hide()
  for _,t in ipairs(self.spineShade or {}) do t:Hide() end
  for _,t in ipairs(self.pageTitles or {}) do t:Hide() end
  for _, b in pairs(self.menuItems or {}) do b:Hide() end
  if self.packBack then
    self.packBack:StopMovingOrSizing(); self.packDragging=nil; self.packBack:Hide()
  end
  if self.packDropHint then self.packDropHint:Hide() end
  for _,paper in ipairs(self.pages or {}) do paper:Hide() end
end

function CollectionUI:MenuItem(index, label, action, x, y, w, h)
  self.menuItems = self.menuItems or {}
  local b = self.menuItems[index]
  if not b then
    b = makeButton(self.frame, "", function(_,button) if b.action then b.action(button) end end)
    self.menuItems[index] = b
  end
  -- A recycled button may have been a deck box, a deck row or an arrow.
  W.ClearDeckBox(b)
  b.bg:SetTexture(ART.."tavern-button.tga")
  b:RegisterForClicks("LeftButtonUp")
  b.action = action; b.text:SetText(label); b.onDisabledClick = nil
  b.text:SetWordWrap(false)
  for _,key in ipairs({"cardArt","artFade","tileOverlay","countBox","manaBadge","manaLabel","countLabel","roundIcon"}) do
    if rawget(b,key) then b[key]:Hide() end
  end
  b:SetScript("OnEnter",nil); b:SetScript("OnLeave",nil)
  b.text:ClearAllPoints(); b.text:SetPoint("CENTER"); b.text:SetJustifyH("CENTER")
  W.ApplyStyle(b.text,"button",self.frame:GetHeight())
  b:EnableMouseWheel(false); b:SetScript("OnMouseWheel",nil)
  b:SetEnabledLook(true)
  b:ClearAllPoints(); b:SetSize(w,h)
  b:SetPoint("TOPLEFT", self.frame, "TOPLEFT", math.floor(x+.5),math.floor(y+.5))
  b.text:SetSize(W.MenuFaceBox(w,h)); b:Show()
  return b
end

--[[ The deck being built, as Hearthstone lists it: the hero's banner with the
     deck's name on it, one tile per card -- mana crystal, name, the card's art
     fading in from the right, a count when there are two -- and the card count
     over Done / Use Deck at the foot of the tray. ]]
function CollectionUI:LayoutDeckRows(r)
  local deck=self:CurrentDeck()
  local f=self.frame
  local counts,ids={},{}
  for _,id in ipairs(deck.cards) do
    if not counts[id] then counts[id]=0; ids[#ids+1]=id end
    counts[id]=counts[id]+1
  end
  table.sort(ids,function(a,b)
    local pa,pb=ns.PrintedCards[a],ns.PrintedCards[b]
    if pa.cost ~= pb.cost then return (pa.cost or 0)<(pb.cost or 0) end
    return pa.name<pb.name
  end)
  self.sidebarPanel:EnableMouseWheel(true)
  self.sidebarPanel:SetScript("OnMouseWheel",function(_,delta) self.deckScroll=(self.deckScroll or 0)-delta; self:Relayout() end)

  -- The banner: the class hero's portrait, framed, with the editable name.
  local bannerH=math.min(64,r.h*.14)
  if not self.deckBanner then
    local banner=CreateFrame("Frame",nil,f)
    banner.art=banner:CreateTexture(nil,"BACKGROUND"); banner.art:SetAllPoints()
    banner.shade=banner:CreateTexture(nil,"BORDER"); banner.shade:SetAllPoints()
    banner.shade:SetTexture(ART.."page-shade.tga"); banner.shade:SetVertexColor(0,0,0,1)
    banner.rim=W.GoldFrame(banner,8,"ARTWORK")
    self.deckBanner=banner
  end
  local banner=self.deckBanner
  banner:SetFrameLevel(self.sidebarPanel:GetFrameLevel()+2)
  place(banner,{x=r.x+6,y=r.y+r.h-6-bannerH,w=r.w-12,h=bannerH},f)
  -- the deck's own art, as on its box in the deck list
  banner.art:SetTexture(self.resolver:Card(W.DeckArtCard(deck)).icon)
  banner.art:SetTexCoord(0,1,.16,.16+math.min(.84,bannerH/(r.w-12)))
  banner.rim:Layout(r.w-12,bannerH); banner:Show()
  place(self.deckName,{x=r.x+18,y=r.y+r.h-6-bannerH/2-12,w=r.w-36,h=24},f)
  self.deckName:SetFrameLevel(banner:GetFrameLevel()+2)
  self.deckName:SetText(deck.name or "Deck"); self.deckName:Show()
  self.deckName:SetTextInsets(0,0,0,0)

  local footH=36
  -- the Copy Deck Code plaque has a row of its own above the footer, and the
  -- card count sits above that: they overlapped (reported with a screenshot)
  local codeH=32
  local rowH=30
  local listTop=r.h-bannerH-14
  local visible=math.max(1,math.floor((listTop-footH-codeH-46)/rowH))
  self.deckScroll=math.max(0,math.min(self.deckScroll or 0,math.max(0,#ids-visible)))
  place(self.deckText,{x=r.x+10,y=r.y+footH+codeH+20,w=r.w-20,h=22},f)
  self.deckText:SetJustifyH("CENTER")
  --[[ A full deck that is still not legal says WHY, in red, where its count
       is: a card disenchanted out from under it used to leave "30/30" and a
       Use Deck button that silently did nothing. ]]
  local legal, problems = self.collection:ValidateDeck(deck)
  local why = (not legal and #deck.cards >= 30 and problems and problems[1]) or nil
  self.deckText:SetText(why and ("|cffff7055" .. why:gsub("^%l", string.upper) .. "|r")
    or (#deck.cards .. "/30 cards" .. (#ids>visible and "  -  scroll for more" or ""))); self.deckText:Show()
  if #ids==0 then
    place(self.deckHint,{x=r.x+16,y=r.y+r.h*.35,w=r.w-32,h=80},f)
    W.ApplyStyle(self.deckHint,"body",f:GetHeight())
    self.deckHint:SetText("Build your deck\n\nClick a card to add it.\nClick a deck entry to remove it."); self.deckHint:Show()
  end
  local top=-(f:GetHeight()-r.y-r.h)
  for slot=1,visible do
    local id=ids[slot+self.deckScroll]
    if id then
      local p=ns.PrintedCards[id]
      local row=self:MenuItem(slot,p.name,
        function(button)
          if button=="RightButton" then
            for _,entry in ipairs(self.collection:Browse({all=true})) do
              if entry.cardId==id then self:OnCardClick(entry,"RightButton"); break end
            end
          else self:RemoveFromDeck(id) end
        end,r.x+8,top-bannerH-12-(slot-1)*rowH,r.w-16,rowH-2)
      local rw=r.w-16
      row:RegisterForClicks("LeftButtonUp","RightButtonUp")
      row.bg:SetColorTexture(.07,.05,.04,1)
      if not rawget(row,"tileOverlay") then
        row.cardArt=row:CreateTexture(nil,"BORDER")
        -- the art melts into the dark at its left, as Hearthstone's strips do
        row.artFade=row:CreateTexture(nil,"BORDER",nil,1)
        row.tileOverlay=row:CreateTexture(nil,"ARTWORK",nil,1)
        row.tileOverlay:SetTexture(ART.."deck-tile.tga"); row.tileOverlay:SetAllPoints()
        row.countBox=row:CreateTexture(nil,"ARTWORK",nil,2)
        row.countBox:SetTexture(ART.."count-box.tga")
        row.manaBadge=row:CreateTexture(nil,"ARTWORK",nil,3)
        row.manaBadge:SetTexture(ART.."mana_crystal.tga")
        row.manaLabel=fs(row,"number","CENTER")
        row.countLabel=fs(row,"count","CENTER")
      end
      -- The art strip: the upper middle of the square art, where the subject is.
      local artW=rw*.62
      row.cardArt:ClearAllPoints(); row.cardArt:SetPoint("RIGHT",row,"RIGHT",-3,0)
      row.cardArt:SetSize(artW,rowH-8)
      if ns.DeckTiles and ns.DeckTiles[id] then
        --[[ Hearthstone's own deck-list strip for the card
             (tools/import_deck_tiles.py): 256x59 in a 256x64 file, cropped
             top and bottom evenly to the row's shape. ]]
        row.cardArt:SetTexture(deckTilePath(id))
        local keep=math.min(1,(256/math.max(1,artW/(rowH-8)))/59)
        local v0=(1-keep)/2*59/64
        row.cardArt:SetTexCoord(0,1,v0,v0+keep*59/64)
      else
        row.cardArt:SetTexture(self.resolver:Card(id).icon)
        row.cardArt:SetTexCoord(W.ArtCoords(id,artW,rowH-8,{.1,.9,.12,.7}))
      end
      row.cardArt:SetAlpha(1); row.cardArt:Show()
      --[[ THE IN-CLIENT TOUR (docs/39): the strip began at a hard vertical
           edge, the crystal's left side ran under the row's rounded rim, and
           a thin digit sat on the crystal's white facet, barely legible. ]]
      row.artFade:ClearAllPoints(); row.artFade:SetPoint("LEFT",row.cardArt,"LEFT",0,0)
      row.artFade:SetSize(artW*.4,rowH-8)
      row.artFade:SetColorTexture(1,1,1,1)
      local mk=rawget(_G,"CreateColor")
      if mk and row.artFade.SetGradient then
        row.artFade:SetGradient("HORIZONTAL",mk(.07,.05,.04,1),mk(.07,.05,.04,0))
        row.artFade:Show()
      else row.artFade:Hide() end
      row.tileOverlay:Show()
      row.manaBadge:ClearAllPoints(); row.manaBadge:SetPoint("LEFT",row,"LEFT",4,0)
      row.manaBadge:SetSize(rowH-2,rowH-2); row.manaBadge:Show()
      --[[ MEASURED, NOT GUESSED: in run 4's screenshot the digit sat 3.5px left
           of the crystal's centre at rowH 30 (the Vollkorn glyph box plus a
           -1 nudge). W.CRYSTAL_DIGIT holds the correction as a fraction of
           the crystal, so it holds at every size. ]]
      local cs=rowH-2
      row.manaLabel:ClearAllPoints()
      row.manaLabel:SetPoint("CENTER",row.manaBadge,"CENTER",cs*W.CRYSTAL_DIGIT.tileX,cs*W.CRYSTAL_DIGIT.tileY)
      row.manaLabel:SetSize(rowH,rowH)
      W.ApplyStyle(row.manaLabel,"gemDigit",nil,math.floor(rowH*.6))
      row.manaLabel:SetText(tostring(p.cost or 0)); row.manaLabel:Show()
      local two=counts[id]>1
      row.countBox:ClearAllPoints(); row.countBox:SetPoint("RIGHT",row,"RIGHT",-2,0)
      row.countBox:SetSize(20,rowH-6); row.countBox:SetShown(two)
      row.countLabel:ClearAllPoints(); row.countLabel:SetPoint("CENTER",row.countBox,"CENTER",0,0); row.countLabel:SetSize(20,rowH-6)
      row.countLabel:SetText(two and tostring(counts[id]) or ""); row.countLabel:SetShown(two)
      row.textColor=p.rarity=="LEGENDARY" and {1,.72,.24} or {1,1,1}
      row.text:ClearAllPoints(); row.text:SetPoint("LEFT",row,"LEFT",rowH+8,0); row.text:SetJustifyH("LEFT")
      W.ApplyStyle(row.text,"label",nil,13,row.textColor)
      row.text:SetSize(rw-rowH-30,rowH-6); row.text:SetText(p.name)
      row:SetEnabledLook(true)
      row:SetScript("OnMouseDown",nil); row:SetScript("OnMouseUp",nil)
      row:SetScript("OnEnter",function()
        row.bg:SetColorTexture(.2,.15,.08,1)
        if not self.deckPreview then self.deckPreview=CardWidget.New(f) end
        local ch=math.min(380,f:GetHeight()-100)
        CardWidget.ApplyRect(self.deckPreview,{x=r.x-ch*.7-12,y=math.max(24,math.min(r.y+r.h-ch,f:GetHeight()-ch-24)),w=ch*.7,h=ch})
        CardWidget.SetDescriptor(self.deckPreview,self.resolver:Card(id))
        self.deckPreview.frame:SetFrameLevel(280); self.deckPreview.frame:EnableMouse(false); self.deckPreview.frame:Show()
      end)
      row:SetScript("OnLeave",function()
        row.bg:SetColorTexture(.07,.05,.04,1)
        if self.deckPreview then self.deckPreview.frame:Hide() end
      end)
      row:EnableMouseWheel(true)
      row:SetScript("OnMouseWheel",function(_,delta) self.deckScroll=self.deckScroll-delta; self:Relayout() end)
    end
  end
  local by=-(f:GetHeight()-r.y-footH-8)
  local bw=(r.w-28)/3
  self:MenuItem(visible+1,"Done",function() self:ShowDecks() end,
    r.x+8,by,bw,footH)
  -- a variant without rebuilding 30 cards: the copy opens for editing
  self:MenuItem(visible+3,"Copy",function()
    local _,index=self.collection:CopyDeck(self.deckIndex)
    if index then self.onPrint(("copied \"%s\"."):format(deck.name or "Deck")); self:EditDeck(index) end
  end,r.x+14+bw,by,bw,footH)
  -- Hearthstone's deck code, to paste into Hearthstone or share (docs/45):
  -- a slim plaque above the footer, as wide as the tray
  local code=self:MenuItem(visible+4,"Copy Deck Code",function() self:ShowDeckCode("export",deck) end,
    r.x+8,-(f:GetHeight()-r.y-footH-codeH-14),r.w-16,codeH)
  code:SetEnabledLook(#(deck.cards or {})>0)
  local valid,problems=self.collection:ValidateDeck(deck)
  local use=self:MenuItem(visible+2,"Use Deck",function()
    self.collection.character.activeDeck=self.deckIndex
    self.onPrint(("duelling with \"%s\"."):format(deck.name or "Deck"))
    self:ShowDecks()
  end,r.x+20+2*bw,by,bw,footH)
  use:SetEnabledLook(valid)
  -- pressed while not legal: say why instead of doing nothing
  use.onDisabledClick=not valid and function()
    self.onPrint(problems and problems[1] or "this deck is not legal yet")
  end or nil
end

-- ============================================================ deck codes

--[[ IMPORT AND EXPORT, with Hearthstone's own deck codes (Client/DeckCode.lua).

     WoW gives an addon no clipboard. A code goes out as text already selected
     in a box, so Ctrl+C copies it; one comes in pasted into the same box with
     Ctrl+V. Hearthstone's whole copied text pastes too (its "###" name and
     "#" lines are read and skipped).

     An import is read before anything is saved: the deck's class must be this
     character's, and the cards it lacks are listed with what crafting them
     costs. "Craft & Save" crafts every missing card when the dust covers all
     of it; "Save" keeps the copies you own, and the deck builder finishes it. ]]
local CODE_W, CODE_H = 580, 440          -- the dialog's panel
local BOX_W, BOX_H = 520, 210            -- the code box (scrolls inside)

function CollectionUI:DeckCodeDialog()
  if self.codeDialog then return self.codeDialog end
  local d
  d = W.Dialog(self.frame, "ForeverHearthstoneDeckCode", {
    { "", function() if d.onPrimary then d.onPrimary() end end },
    { "", function() if d.onSecondary then d.onSecondary() end end },
    { "Cancel", function() d:Hide() end },
  }, { paper = true, w = CODE_W, h = CODE_H })
  d.title = fs(d.panel, "pageTitle", "CENTER")
  d.title:SetPoint("TOP", d.panel, "TOP", 0, -24); d.title:SetSize(CODE_W - 60, 32)
  d.title:SetWordWrap(false)
  -- two lines of instructions, wrapped, never cut off with "..."
  d.message:ClearAllPoints(); d.message:SetPoint("TOP", d.title, "BOTTOM", 0, -6)
  d.message:SetSize(BOX_W, 46); d.message:SetWordWrap(true)
  W.ApplyStyle(d.message, "dialog", nil, 14, W.Colors.inkBody)
  --[[ The text lives in a box that SCROLLS: a deck's code with its card list
       is thirty-odd lines, and a bare multi-line edit box simply ran out of
       its frame and over the buttons (reported with a screenshot). ]]
  d.scroll = CreateFrame("ScrollFrame", nil, d.panel)
  d.scroll:SetSize(BOX_W - 16, BOX_H - 16)
  d.scroll:SetFrameLevel(d.panel:GetFrameLevel() + 4)
  d.frameBox = CreateFrame("Frame", nil, d.panel)
  d.frameBox:SetSize(BOX_W, BOX_H)
  d.frameBox:SetFrameLevel(d.panel:GetFrameLevel() + 3)
  d.frameBox.bg = d.frameBox:CreateTexture(nil, "BACKGROUND"); d.frameBox.bg:SetAllPoints()
  d.frameBox.bg:SetColorTexture(1, .97, .88, .92)
  d.frameBox.rim = W.GoldFrame(d.frameBox, 6, "BORDER")
  d.frameBox.rim:Layout(BOX_W, BOX_H)
  d.box = CreateFrame("EditBox", nil, d.scroll)
  d.box:SetMultiLine(true); d.box:SetAutoFocus(false); d.box:SetMaxLetters(4000)
  d.box:SetFont(W.StyleFont("bodyInk"), 12, ""); d.box:SetTextColor(.2, .12, .06, 1)
  d.box:SetWidth(BOX_W - 24); d.box:SetHeight(BOX_H - 16)
  d.scroll:SetScrollChild(d.box)
  d.scroll:EnableMouseWheel(true)
  d.scroll:SetScript("OnMouseWheel", function(sf, delta)
    local range = sf:GetVerticalScrollRange() or 0
    sf:SetVerticalScroll(math.max(0, math.min(range, (sf:GetVerticalScroll() or 0) - delta * 36)))
  end)
  d.box:SetScript("OnEscapePressed", function() d:Hide() end)
  -- an exported code stays exactly as written: typing over it re-selects it
  d.box:SetScript("OnTextChanged", function(box, user)
    if user and d.mode == "export" and d.exported and box:GetText() ~= d.exported then
      box:SetText(d.exported); box:HighlightText()
    end
  end)
  -- clicking anywhere on the box puts the cursor in it
  d.frameBox:EnableMouse(true)
  d.frameBox:SetScript("OnMouseDown", function() d.box:SetFocus() end)
  d.list = fs(d.panel, "bodyInk", "LEFT")
  d.list:SetJustifyV("TOP"); d.list:SetWordWrap(true)
  W.ApplyStyle(d.list, "bodyInk", nil, 13)
  self.codeDialog = d
  return d
end

local function codePlace(d, boxH, listH)
  d.frameBox:ClearAllPoints(); d.frameBox:SetPoint("TOP", d.message, "BOTTOM", 0, -6)
  d.scroll:ClearAllPoints(); d.scroll:SetPoint("TOPLEFT", d.frameBox, "TOPLEFT", 10, -8)
  d.frameBox:SetShown(boxH > 0); d.scroll:SetShown(boxH > 0); d.box:SetShown(boxH > 0)
  d.scroll:SetVerticalScroll(0)
  d.list:ClearAllPoints(); d.list:SetPoint("TOP", d.message, "BOTTOM", 0, -6)
  d.list:SetSize(BOX_W - 20, listH); d.list:SetShown(listH > 0)
end

-- The dialog's buttons for this step: { label, action, enabled, whyNot } or
-- nil for none; the ones shown are centred as a row with Close/Cancel.
local function setButtons(d, primary, secondary)
  for i = 1, 2 do
    local spec = (i == 1) and primary or secondary
    local b = d.buttons[i]
    b:SetShown(spec ~= nil)
    if spec then
      b.text:SetText(spec[1]); b:SetEnabledLook(spec[3] ~= false)
      b.onDisabledClick = spec[4]
    end
  end
  d.onPrimary = primary and primary[2]
  d.onSecondary = secondary and secondary[2]
  local shown = {}
  for _, b in ipairs(d.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
  local bw = (#shown >= 3) and 168 or 190
  for i, b in ipairs(shown) do
    b:ClearAllPoints()
    b:SetPoint("BOTTOM", d.panel, "BOTTOM", (i - (#shown + 1) / 2) * (bw + 12), 24)
    b:SetSize(bw, 42)
    W.ApplyStyle(b.text, "button", nil, 15)
  end
end

function CollectionUI:ShowDeckCode(mode, deck)
  local d = self:DeckCodeDialog()
  self:HideImportView(); d.importState = nil; d.message:Show()
  d.mode, d.exported = mode, nil
  d.buttons[3]:Show(); d.buttons[3].text:SetText(mode == "export" and "Close" or "Cancel")
  if mode == "export" then
    local text, err = ns.DeckCode.Export(deck)
    d.title:SetText("Deck Code")
    if not text then
      d.message:SetText("This deck cannot be written as a code: " .. tostring(err))
      codePlace(d, 0, 0); setButtons(d, nil, nil); d:Show(); return
    end
    d.exported = text
    d.message:SetText("The code is selected: press Ctrl+C to copy it.\nPaste it into Hearthstone, a deck site, or a friend's Import Deck.")
    codePlace(d, 1, 0)
    setButtons(d, nil, nil)
    d:Show()
    d.box:SetText(text); d.box:SetFocus(); d.box:HighlightText(); d.box:SetCursorPosition(0)
    d.box:HighlightText()
    return
  end
  d.title:SetText("Import Deck")
  d.message:SetText("Click the box, paste a Hearthstone deck code with Ctrl+V,\nthen press Import.")
  codePlace(d, 1, 0)
  d.box:SetText("")
  setButtons(d, { "Import", function() self:ReadDeckCode(d.box:GetText()) end }, nil)
  d:Show()
  d.box:SetFocus()
end

--[[ THE IMPORT RESULT (judged 4/10 as "monochrome"; redesigned to the judge's
     layout, docs/45). Over the same parchment dialog:

       title     the deck's name, gold on a dark plaque
       summary   "29 / 30 cards owned" over a green progress bar; your dust,
                 and what crafting the rest needs (green when you have it)
       warning   red strip, only when the code held cards this game does not
                 have (sets after Goblins vs Gnomes) -- they were left out
       rows      one per missing card, as the deck list draws a card: rarity
                 bar, mana crystal, the card's strip art fading into the dark
                 under its name, "x2", the dust it costs, and its own Craft
                 button (or why it cannot be crafted). A crafted row says
                 Owned. The wheel scrolls past six.
       footer    Craft All & Save (when it can), Save Owned, Cancel ]]
local RARITY_RGB = { COMMON = { .62, .62, .62 }, FREE = { .8, .8, .8 }, RARE = { .24, .55, 1 },
                     EPIC = { .69, .3, 1 }, LEGENDARY = { 1, .54, .12 } }
local IMPORT_ROWS, IMPORT_ROW_H = 5, 40

local function commas(n)
  local s = tostring(math.floor(n or 0))
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

function CollectionUI:ImportView()
  local d = self.codeDialog
  if rawget(d, "view") then return d.view end
  local v = {}
  local P = d.panel
  -- the title plaque
  v.titleBar = CreateFrame("Frame", nil, P)
  v.titleBar:SetFrameLevel(P:GetFrameLevel() + 5)
  v.titleBar.plate = W.NamePlate(v.titleBar, "BACKGROUND")
  v.title = v.titleBar:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(v.title, "heroName", nil, 22, { 1, .84, .36 })
  v.title:SetJustifyH("CENTER"); v.title:SetWordWrap(false)
  -- the summary strip
  v.summary = CreateFrame("Frame", nil, P)
  v.summary:SetFrameLevel(P:GetFrameLevel() + 4)
  v.summary.bg = v.summary:CreateTexture(nil, "BACKGROUND"); v.summary.bg:SetAllPoints()
  v.summary.bg:SetColorTexture(.85, .78, .6, 1)
  v.summary.rim = W.GoldFrame(v.summary, 4, "BORDER")
  v.owned = fs(v.summary, "bodyInk", "LEFT")
  W.ApplyStyle(v.owned, "bodyInk", nil, 14, { .23, .14, .06 })
  v.barBack = v.summary:CreateTexture(nil, "ARTWORK", nil, 1); v.barBack:SetColorTexture(.72, .64, .48, 1)
  v.barFill = v.summary:CreateTexture(nil, "ARTWORK", nil, 2); v.barFill:SetColorTexture(.35, .66, .2, 1)
  v.dust = fs(v.summary, "bodyInk", "RIGHT")
  W.ApplyStyle(v.dust, "bodyInk", nil, 15, { .18, .44, .84 })
  v.need = fs(v.summary, "bodyInk", "RIGHT")
  W.ApplyStyle(v.need, "bodyInk", nil, 12, { .62, .11, .07 })
  -- the warning strip
  v.warn = CreateFrame("Frame", nil, P)
  v.warn:SetFrameLevel(P:GetFrameLevel() + 4)
  v.warn.bg = v.warn:CreateTexture(nil, "BACKGROUND"); v.warn.bg:SetAllPoints()
  v.warn.bg:SetColorTexture(.35, .1, .07, .9)
  v.warn.edge = v.warn:CreateTexture(nil, "BORDER"); v.warn.edge:SetPoint("TOPLEFT"); v.warn.edge:SetPoint("BOTTOMLEFT")
  v.warn.edge:SetWidth(4); v.warn.edge:SetColorTexture(.89, .34, .23, 1)
  v.warnText = fs(v.warn, "body", "LEFT")
  W.ApplyStyle(v.warnText, "body", nil, 13, { 1, .88, .78 })
  v.warnText:SetWordWrap(true)
  -- the column heads
  v.headL = fs(P, "bodyInk", "LEFT"); v.headR = fs(P, "bodyInk", "RIGHT")
  for _, h in ipairs({ v.headL, v.headR }) do W.ApplyStyle(h, "bodyInk", nil, 11, { .48, .35, .2 }) end
  v.headL:SetText("MISSING CARDS"); v.headR:SetText("CRAFT")
  v.empty = fs(P, "bodyInk", "CENTER")
  W.ApplyStyle(v.empty, "dialog", nil, 16, { .24, .48, .16 })
  v.rows = {}
  for i = 1, IMPORT_ROWS do
    local r = CreateFrame("Frame", nil, P)
    r:SetFrameLevel(P:GetFrameLevel() + 4)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta)
      local st = rawget(d, "importState")
      if st then st.scroll = math.max(0, math.min(st.maxScroll, st.scroll - delta)); self:DrawImport() end
    end)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
    r.bar = r:CreateTexture(nil, "BORDER"); r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(4)
    r.tile = CreateFrame("Frame", nil, r)
    r.tile.bg = r.tile:CreateTexture(nil, "BACKGROUND"); r.tile.bg:SetAllPoints(); r.tile.bg:SetColorTexture(.07, .05, .04, 1)
    r.art = r.tile:CreateTexture(nil, "BORDER")
    r.fade = r.tile:CreateTexture(nil, "BORDER", nil, 1)
    r.gem = r.tile:CreateTexture(nil, "ARTWORK", nil, 3); r.gem:SetTexture(ART .. "mana_crystal.tga")
    r.cost = fs(r.tile, "number", "CENTER")
    r.name = fs(r.tile, "label", "LEFT"); r.name:SetWordWrap(false)
    r.count = fs(r, "count", "CENTER")
    r.price = fs(r, "bodyInk", "RIGHT"); r.price:SetWordWrap(false)
    r.craft = W.MenuButton(r, "Craft", function() local f = rawget(r, "onCraft"); if f then f() end end)
    r.craft:SetFrameLevel(r:GetFrameLevel() + 3)
    v.rows[i] = r
  end
  d.view = v
  return v
end

function CollectionUI:HideImportView()
  local d = self.codeDialog
  local v = d and rawget(d, "view")
  if not v then return end
  for _, x in ipairs({ v.titleBar, v.summary, v.warn, v.headL, v.headR, v.empty }) do x:Hide() end
  for _, r in ipairs(v.rows) do r:Hide() end
  d.title:Show()
end

function CollectionUI:ReadDeckCode(text)
  local d = self:DeckCodeDialog()
  local decoded, why = ns.DeckCode.Decode(text)
  if not decoded then
    d.message:SetText("|cff8a1c0c" .. why .. "|r\nPaste a Hearthstone deck code with Ctrl+V, then press Import.")
    return
  end
  local mine = self.collection.character.class
  local function title(c) return c and (c:sub(1, 1) .. c:sub(2):lower()) or "?" end
  if decoded.class and decoded.class ~= mine then
    d.message:SetText(("|cff8a1c0cThat is a %s deck.|r Your character can only build %s decks.")
      :format(title(decoded.class), title(mine)))
    return
  end
  d.importState = { decoded = decoded, scroll = 0, maxScroll = 0 }
  self:DrawImport()
end

function CollectionUI:DrawImport()
  local d = self.codeDialog
  local st = rawget(d, "importState")
  if not st then return end
  local decoded = st.decoded
  local plan = ns.DeckCode.Plan(self.collection, decoded)
  -- the rows: every card that was missing when the code was read stays
  -- listed, so a crafted one can say Owned
  st.listed = st.listed or {}
  for _, row in ipairs(plan.rows) do
    if row.missing > 0 and not st.listed[row.id] then
      st.listed[row.id] = true; st.order = st.order or {}; st.order[#st.order + 1] = row.id
    end
  end
  st.order = st.order or {}
  local byId = {}
  for _, row in ipairs(plan.rows) do byId[row.id] = row end
  local v = self:ImportView()
  local P = d.panel
  local W0, X0 = 532, 24
  d.message:Hide(); codePlace(d, 0, 0); d.title:Hide()

  -- title
  v.titleBar:ClearAllPoints(); v.titleBar:SetPoint("TOP", P, "TOP", 0, -14); v.titleBar:SetSize(330, 38)
  v.titleBar.plate:Layout(330, 38)
  v.title:ClearAllPoints(); v.title:SetPoint("CENTER", v.titleBar, "CENTER", 0, 1); v.title:SetSize(300, 30)
  v.title:SetText(decoded.name or "Imported Deck"); v.titleBar:Show()

  -- summary
  local total = #decoded.cards
  local owned = total - plan.missing
  v.summary:ClearAllPoints(); v.summary:SetPoint("TOPLEFT", P, "TOPLEFT", X0, -60); v.summary:SetSize(W0, 40)
  v.summary.rim:Layout(W0, 40)
  v.owned:ClearAllPoints(); v.owned:SetPoint("TOPLEFT", v.summary, "TOPLEFT", 12, -6); v.owned:SetSize(260, 16)
  v.owned:SetText(("%d / %d cards owned"):format(owned, math.max(30, total)))
  v.barBack:ClearAllPoints(); v.barBack:SetPoint("TOPLEFT", v.summary, "TOPLEFT", 12, -25); v.barBack:SetSize(220, 8)
  v.barFill:ClearAllPoints(); v.barFill:SetPoint("TOPLEFT", v.barBack, "TOPLEFT", 0, 0)
  v.barFill:SetSize(math.max(1, 220 * owned / math.max(30, total)), 8)
  v.dust:ClearAllPoints(); v.dust:SetPoint("TOPRIGHT", v.summary, "TOPRIGHT", -12, -5); v.dust:SetSize(240, 16)
  v.dust:SetText(("Dust: %s"):format(commas(plan.have)))
  v.need:ClearAllPoints(); v.need:SetPoint("TOPRIGHT", v.summary, "TOPRIGHT", -12, -22); v.need:SetSize(240, 14)
  if plan.dust > 0 then
    v.need:SetText(("Crafting the rest: %s"):format(commas(plan.dust)))
    if plan.dust <= plan.have then v.need:SetTextColor(.24, .54, .16) else v.need:SetTextColor(.62, .11, .07) end
    v.need:Show()
  else v.need:Hide() end
  v.summary:Show()

  -- warning
  local top = -106
  local unknown = 0
  for _, u in ipairs(plan.unknown) do unknown = unknown + u.n end
  if unknown > 0 then
    v.warn:ClearAllPoints(); v.warn:SetPoint("TOPLEFT", P, "TOPLEFT", X0, top); v.warn:SetSize(W0, 32)
    v.warnText:ClearAllPoints(); v.warnText:SetPoint("LEFT", v.warn, "LEFT", 14, 0); v.warnText:SetSize(W0 - 24, 30)
    v.warnText:SetText(("|cffffb347Warning:|r %d card%s %s from sets after Goblins vs Gnomes and %s left out. The deck has %d cards.")
      :format(unknown, unknown == 1 and "" or "s", unknown == 1 and "is" or "are", unknown == 1 and "was" or "were", total))
    v.warn:Show()
    top = top - 38
  else v.warn:Hide() end

  -- the rows
  v.headL:ClearAllPoints(); v.headL:SetPoint("TOPLEFT", P, "TOPLEFT", X0 + 8, top - 2); v.headL:SetSize(200, 14)
  v.headR:ClearAllPoints(); v.headR:SetPoint("TOPRIGHT", P, "TOPLEFT", X0 + W0 - 8, top - 2); v.headR:SetSize(200, 14)
  local listTop = top - 18
  local fit = math.max(1, math.min(IMPORT_ROWS, math.floor((CODE_H - 74 + listTop) / (IMPORT_ROW_H + 2))))
  st.maxScroll = math.max(0, #st.order - fit)
  st.scroll = math.max(0, math.min(st.maxScroll, st.scroll))
  v.headR:SetText(#st.order > fit and "CRAFT   (scroll for more)" or "CRAFT")
  local shownHeads = #st.order > 0
  v.headL:SetShown(shownHeads); v.headR:SetShown(shownHeads)
  for i, r in ipairs(v.rows) do
    local id = st.order[st.scroll + i]
    local row = id and byId[id]
    if i <= fit and row then
      local p = self.collection.printed[id] or {}
      r:ClearAllPoints(); r:SetPoint("TOPLEFT", P, "TOPLEFT", X0, listTop - (i - 1) * (IMPORT_ROW_H + 2))
      r:SetSize(W0, IMPORT_ROW_H)
      local alt = (i % 2 == 0)
      local done = row.missing == 0
      if done then r.bg:SetColorTexture(.9, .95, .82, 1)
      elseif alt then r.bg:SetColorTexture(.91, .85, .7, 1) else r.bg:SetColorTexture(.94, .89, .75, 1) end
      local rc = RARITY_RGB[p.rarity] or RARITY_RGB.COMMON
      r.bar:SetColorTexture(rc[1], rc[2], rc[3], 1)
      -- the tile: crystal, name over the strip art fading into the dark
      local tw, th = 260, IMPORT_ROW_H - 6
      r.tile:ClearAllPoints(); r.tile:SetPoint("LEFT", r, "LEFT", 10, 0); r.tile:SetSize(tw, th)
      local artW = tw * .6
      r.art:ClearAllPoints(); r.art:SetPoint("RIGHT", r.tile, "RIGHT", 0, 0); r.art:SetSize(artW, th)
      if ns.DeckTiles and ns.DeckTiles[id] then
        r.art:SetTexture(deckTilePath(id))
        local keep = math.min(1, (256 / math.max(1, artW / th)) / 59)
        local v0 = (1 - keep) / 2 * 59 / 64
        r.art:SetTexCoord(0, 1, v0, v0 + keep * 59 / 64)
      else
        r.art:SetTexture(self.resolver:Card(id).icon)
        r.art:SetTexCoord(W.ArtCoords(id, artW, th, { .1, .9, .12, .7 }))
      end
      r.fade:ClearAllPoints(); r.fade:SetPoint("LEFT", r.art, "LEFT", 0, 0); r.fade:SetSize(artW * .45, th)
      r.fade:SetColorTexture(1, 1, 1, 1)
      local mk = rawget(_G, "CreateColor")
      if mk and r.fade.SetGradient then
        r.fade:SetGradient("HORIZONTAL", mk(.07, .05, .04, 1), mk(.07, .05, .04, 0)); r.fade:Show()
      else r.fade:Hide() end
      r.gem:ClearAllPoints(); r.gem:SetPoint("LEFT", r.tile, "LEFT", 2, 0); r.gem:SetSize(th, th)
      r.cost:ClearAllPoints()
      r.cost:SetPoint("CENTER", r.gem, "CENTER", th * W.CRYSTAL_DIGIT.tileX, th * W.CRYSTAL_DIGIT.tileY)
      r.cost:SetSize(th, th); W.ApplyStyle(r.cost, "gemDigit", nil, math.floor(th * .58))
      r.cost:SetText(tostring(p.cost or 0))
      r.name:ClearAllPoints(); r.name:SetPoint("LEFT", r.tile, "LEFT", th + 6, 0); r.name:SetSize(tw - th - 10, th)
      W.ApplyStyle(r.name, "label", nil, 13, p.rarity == "LEGENDARY" and { 1, .72, .24 } or { 1, 1, 1 })
      r.name:SetText(p.name or id)
      -- how many
      r.count:ClearAllPoints(); r.count:SetPoint("LEFT", r, "LEFT", 276, 0); r.count:SetSize(30, th)
      W.ApplyStyle(r.count, "count", nil, 14, { .23, .14, .06 })
      r.count:SetText(done and "" or ("x" .. row.missing))
      -- what it costs, or why it cannot be made
      r.price:ClearAllPoints(); r.price:SetPoint("RIGHT", r, "RIGHT", -112, 0); r.price:SetSize(150, th)
      if done then
        W.ApplyStyle(r.price, "bodyInk", nil, 14, { .24, .54, .16 }); r.price:SetText("Owned")
        r.craft:Hide()
      elseif row.craft then
        local affordable = row.craft <= plan.have
        W.ApplyStyle(r.price, "bodyInk", nil, 14, affordable and { .18, .44, .84 } or { .62, .11, .07 })
        r.price:SetText(("%s dust"):format(commas(row.craft * row.missing)))
        r.craft:ClearAllPoints(); r.craft:SetPoint("RIGHT", r, "RIGHT", -6, 0); r.craft:SetSize(100, 30)
        r.craft.text:SetText(row.missing > 1 and "Craft 1" or "Craft")
        W.ApplyStyle(r.craft.text, "button", nil, 13)
        r.craft:SetEnabledLook(affordable)
        r.craft.onDisabledClick = function()
          self.onPrint(("not enough dust: %d of %d"):format(plan.have, row.craft))
        end
        r.onCraft = function()
          local ok, result = self.collection:Craft(id)
          if not ok then self.onPrint(result); return end
          self.onPrint(("crafted %s for %d dust."):format(p.name or id, result))
          if ns.Sounds then ns.Sounds.Play("craft") end
          self:DrawImport()
        end
        r.craft:Show()
      else
        W.ApplyStyle(r.price, "bodyInk", nil, 12, { .48, .35, .2 })
        r.price:SetText(row.why or "")
        r.craft:Hide()
      end
      r:Show()
    else
      r:Hide()
    end
  end
  if #st.order == 0 then
    v.empty:ClearAllPoints(); v.empty:SetPoint("TOP", P, "TOP", 0, listTop - 30); v.empty:SetSize(W0, 40)
    v.empty:SetText("You own every card in this deck!"); v.empty:Show()
  else v.empty:Hide() end

  -- the footer
  local function save(craft)
    if craft then
      local made, spent = ns.DeckCode.CraftMissing(self.collection, plan)
      if made > 0 then self.onPrint(("crafted %d card%s for %d dust."):format(made, made == 1 and "" or "s", spent)) end
    end
    local deckSaved, left, index = ns.DeckCode.Save(self.collection, decoded)
    d:Hide()
    if not deckSaved then self.onPrint(left or "could not save the deck"); return end
    self.onPrint(("imported \"%s\"%s."):format(deckSaved.name,
      left > 0 and (" -- %d card%s still to add"):format(left, left == 1 and "" or "s") or ""))
    if index then self:EditDeck(index) else self:ShowDecks() end
  end
  local craftable = plan.missing - plan.uncraftable
  if plan.missing == 0 then
    setButtons(d, { "Save Deck", function() save(false) end }, nil)
  else
    local why = (plan.uncraftable > 0) and "Some missing cards cannot be crafted (see the list)."
      or ("You have %d dust; crafting needs %d."):format(plan.have, plan.dust)
    setButtons(d,
      { ("Craft All (%s)"):format(commas(plan.dust)), function() save(true) end, plan.canCraftAll and craftable > 0,
        function() self.onPrint(why) end },
      { "Save Owned", function() save(false) end })
  end
end

function CollectionUI:ClearBrowser()
  CardWidget.ReleaseAll(self.cardPool); self.slots = {}
  for _, b in ipairs({self.prevButton,self.nextButton,self.craftButton,self.dustButton,
    self.packButton,self.classButton,self.progressText,self.dustText,self.pageText,self.deckText}) do b:Hide() end
  self.statsPlate:SetShown(false)
  self.hintText:ClearAllPoints(); self.hintText:SetSize(self.frame:GetWidth()*.85,70)
  self.hintText:SetPoint("TOP",self.frame,"TOP",0,-45); self.hintText:Show()
  self.titlePlaque:Hide()
end

function CollectionUI:ShowPackRoom()
  self.deckBrowser = nil; self.packRoom = true; self.bulk = nil; self.bulkPlay = nil
  self.selected = nil   -- the browser's selection has no business in the pack room
  self:Relayout()
end

-- Only dropping in the opening well spends a pack. Cancelling or dropping
-- elsewhere returns the stack to the shelf without changing the inventory.
function CollectionUI:FinishPackDrag()
  if not self.packDragging then return end
  self.packDragging=nil
  self.packBack:StopMovingOrSizing()
  local x,y=GetCursorPosition()
  local scale=self.frame:GetEffectiveScale()
  x=x/scale-self.frame:GetLeft(); y=y/scale-self.frame:GetBottom()
  local r=self.packDropRect
  if r and x>=r.x and x<=r.x+r.w and y>=r.y and y<=r.y+r.h then
    self:OpenPack("HEARTHSTONE")
  else self:Relayout() end
end

--[[ The room at its own shape (CL.PackRoom), letterboxed by W.EdgeBands
     where the window is wider or taller. Stretching the outermost 0.6% of the
     picture across the gap smeared its frame into streaks -- reported with a
     screenshot. Returns the room's rect. ]]
function CollectionUI:PlacePackRoom(w, h)
  local room = CL.PackRoom(w, h)
  place(self.packScene, room, self.frame); self.packScene:Show()
  self.packBackdrop:Show()
  self.packScene:SetTexCoord(0, 1, 0, 1)
  self.packBands = self.packBands or W.EdgeBands(self.frame, ART .. "pack-room.tga", 1, { plainTop = true })
  self.packBands:Place(w, h, room, { l = 0, r = 1, t = 0, b = 1 })
  return room
end

function CollectionUI:HidePackRoomBands()
  if self.packBands then self.packBands:Hide() end
  self.packBackdrop:Hide()
end

function CollectionUI:LayoutPackRoom()
  self:ClearBrowser()
  local w,h = self.frame:GetWidth(),self.frame:GetHeight()
  -- the room paints its own "Open Packs" plaque
  self.hintText:Hide()
  self.packSet="HEARTHSTONE"
  local room=self:PlacePackRoom(w,h)
  -- the well: a circle round the centre pack-room.tga paints it at
  local well=CL.design.PACK_WELL
  local cx,cy,rad=room.x+room.w*well[1],room.y+room.h*well[2],room.h*.27
  self.packDropRect={x=cx-rad,y=cy-rad,w=rad*2,h=rad*2}
  if not self.packBack then
    local back = CreateFrame("Button",nil,self.frame); self.packBack=back
    back:EnableMouse(true); back:SetMovable(true); back:RegisterForDrag("LeftButton")
    back:SetFrameLevel(self.frame:GetFrameLevel()+20)
    local tex = back:CreateTexture(nil,"ARTWORK"); tex:SetAllPoints()
    tex:SetTexture(ART.."menu-pack.tga")
    back.count=fs(back,"heroName","CENTER")
    back.count:SetPoint("BOTTOM",back,"BOTTOM",0,6); back.count:SetSize(100,32)
    back:SetScript("OnDragStart",function()
      if self.collection:PackCount("HEARTHSTONE")<=0 then return end
      self.packDragging=true; back:StartMoving()
    end)
    back:SetScript("OnDragStop",function() self:FinishPackDrag() end)
    self.packDropHint=fs(self.frame,"caption","CENTER")
  end
  local count=self.collection:PackCount("HEARTHSTONE")
  -- the packs stand on the purple tray (x .008-.158 of the room)
  local trayX,trayW=room.x+room.w*.008,room.w*.150
  local ph=math.min(room.h*.30,trayW*.92*208/150); local pw=ph*150/208
  local trayY=room.y+room.h*.50
  place(self.packBack,{x=trayX+(trayW-pw)/2,y=trayY-ph/2,w=pw,h=ph},self.frame)
  self.packBack:SetAlpha(1); self.packBack.count:SetText("x"..count)
  self.packBack:SetShown(count>0)
  place(self.deckHint,{x=trayX+trayW*.06,y=trayY-ph/2-room.h*.14,w=trayW*.88,h=room.h*.12},self.frame)
  W.ApplyStyle(self.deckHint,"body",h)
  self.deckHint:SetText(count>0 and "Classic + GvG + Naxx\n5 cards per pack" or "No packs yet.\nPacks come from levelling and\nfrom creatures that give experience.")
  self.deckHint:Show()
  -- centred under the well, on the stone
  self.packDropHint:SetJustifyH("CENTER")
  place(self.packDropHint,{x=cx-room.w*.25,y=cy-rad-room.h*.075,w=room.w*.5,h=room.h*.06},self.frame)
  self.packDropHint:SetText(count>0 and "Drag a pack into the well" or "No packs left")
  self.packDropHint:Show()
  --[[ OPEN SEVERAL AT ONCE (Hearthstone's bulk opening, up to 40): a plaque
       under the tray's stack with - and + either side, there whenever two or
       more packs wait. The wheel over it steps the number too. ]]
  if count>=2 then
    local maxN=math.min(count,ns.Packs.BULK_MAX)
    self.bulkCount=math.max(2,math.min(maxN,self.bulkCount or math.min(maxN,10)))
    local bh=math.max(28,math.min(44,room.h*.055))
    local bw=trayW*.62
    local bx=trayX+(trayW-bw)/2
    local byTop=h-(trayY+ph/2)-bh-room.h*.012   -- just above the stack
    local open=self:MenuItem(50,("Open %d"):format(self.bulkCount),function() self:OpenBulk(self.bulkCount) end,
      bx,-(h-(trayY-ph/2)+room.h*.012),bw,bh)
    open:SetFrameLevel(self.frame:GetFrameLevel()+22)
    open:EnableMouseWheel(true)
    open:SetScript("OnMouseWheel",function(_,delta)
      self.bulkCount=math.max(2,math.min(maxN,self.bulkCount+delta)); self:Relayout()
    end)
    local sw=bh
    for i,spec in ipairs({{51,"-",-1,bx-sw-4},{52,"+",1,bx+bw+4}}) do
      local step=self:MenuItem(spec[1],spec[2],function()
        local by=(IsShiftKeyDown and IsShiftKeyDown()) and 5 or 1
        self.bulkCount=math.max(2,math.min(maxN,self.bulkCount+spec[3]*by)); self:Relayout()
      end,spec[4],-(h-(trayY-ph/2)+room.h*.012),sw,bh)
      step:SetFrameLevel(self.frame:GetFrameLevel()+22)
      step:SetEnabledLook(i==1 and self.bulkCount>2 or i==2 and self.bulkCount<maxN)
      W.ApplyStyle(step.text,"buttonLarge",h)
    end
    self.deckHint:SetText("Classic + GvG + Naxx\n5 cards per pack\nOr open up to "..maxN.." at once")
  end
end

-- ============================================================ bulk opening

--[[ The result of opening many packs at once, Hearthstone-style: every card
     you got on the table at once, the best first -- legendaries, then epics,
     rares, commons; golden before plain; NEW before ones you had -- one card
     per kind with how many came ("x2"). A duplicate that became dust is
     greyed with its dust on it, as the single reveal leaves it. A summary
     across the top counts each rarity and the dust. ]]
--[[ OPENING SEVERAL: each pack plays its own crack and reveal, one after
     another, by itself -- the cards turn over without a click, the best card
     of each pack last, an epic or legendary holding a beat longer -- and the
     summary of everything comes at the end. Skip jumps straight there; Next
     Pack moves on early. The cards are banked before any of it plays
     (Packs.OpenMany), so stopping half way loses nothing. ]]
function CollectionUI:OpenBulk(n)
  local result, why = ns.Packs.OpenMany(self.collection, "HEARTHSTONE", n)
  if not result then self.onPrint(why); return end
  self.onPrint(("opening %d packs."):format(result.packs))
  self.bulkPlay = { result = result, index = 0 }
  self:BulkNextPack()
end

-- seconds after each card turns, by rarity: brisk for commons, a held
-- breath for the good ones ("a bit too slowly", reported)
CollectionUI.BULK_FLIP = { COMMON = 0.24, FREE = 0.24, RARE = 0.4, EPIC = 0.85, LEGENDARY = 1.4 }
local BULK_RANK = { FREE = 0, COMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }

function CollectionUI:BulkNextPack()
  local bp = self.bulkPlay
  if not bp then return end
  bp.index = bp.index + 1
  local pack = bp.result.packList[bp.index]
  if not pack then return self:FinishBulk() end
  self.pack = pack
  self.packRevealed = 0
  self.revealedCards = {}
  self.packDusted = {}
  self.packTold, self.packHover = {}, nil
  self:HidePackLights()
  self:Relayout()
  self:PlayPackFX(pack)
  -- the order they turn: plainest first, the best (the one that glowed) last
  local order = {}
  for i in ipairs(pack.cards) do order[#order + 1] = i end
  table.sort(order, function(a, b)
    if a == pack.tellIndex then return false end
    if b == pack.tellIndex then return true end
    local ra, rb = BULK_RANK[pack.cards[a].rarity] or 0, BULK_RANK[pack.cards[b].rarity] or 0
    if ra ~= rb then return ra < rb end
    return a < b
  end)
  local tl = ns.Timeline.New("BulkPack")
  local t = 0.8                                     -- the crack and the deal
  for k, i in ipairs(order) do
    tl:At(t, "flip_" .. k, function()
      if self.bulkPlay == bp and self.pack == pack then self:RevealCard(i) end
    end)
    t = t + (CollectionUI.BULK_FLIP[pack.cards[i].rarity] or 0.42)
  end
  local best = pack.cards[pack.tellIndex] and pack.cards[pack.tellIndex].rarity
  t = t + ((best == "LEGENDARY") and 1.0 or (best == "EPIC") and 0.5 or 0.3)
  tl:At(t, "next_pack", function()
    if self.bulkPlay == bp and self.pack == pack then self:BulkNextPack() end
  end)
  -- a timeline with a cleanup survives the relayouts each flip makes
  tl.cleanup = function() end
  self:Run(tl)
end

--- Everything at once: the summary of the packs just played.
function CollectionUI:FinishBulk()
  local bp = self.bulkPlay
  if not bp then return end
  self.bulkPlay = nil
  self:StopFX()
  self:HidePackLights()
  self.pack, self.revealedCards, self.packRevealed = nil, nil, 0
  self.bulk, self.bulkPage = bp.result, 1
  if ns.Sounds then ns.Sounds.Play("menu_page") end
  self:Relayout()
end

function CollectionUI:CloseBulk()
  self.bulk = nil
  self:HideBulk()
  self:Relayout()
end

function CollectionUI:HideBulk()
  for _, t in ipairs(self.bulkTags or {}) do t.count:Hide(); t.badge:Hide(); t.stamp:Hide() end
  if self.bulkSummary then self.bulkSummary:Hide() end
  if self.bulkSkip then self.bulkSkip:Hide(); self.bulkCounter:Hide() end
end

--- The grid for `n` cards in an area: rows and columns that keep cards large.
function CollectionUI.BulkGrid(areaW, areaH, n)
  local best
  for rows = 1, 4 do
    local gapY = areaH * 0.05
    local ch = (areaH - (rows - 1) * gapY) / rows / 1.18      -- room for the tags below
    local cw = ch * 0.70
    local gap = cw * 0.16
    local cols = math.max(1, math.floor((areaW + gap) / (cw + gap)))
    local per = cols * rows
    local pages = math.ceil(n / per)
    -- fewest pages, then the largest cards
    local score = pages * 1000 - cw
    if cw >= 70 and (not best or score < best.score) then
      best = { rows = rows, cols = cols, cw = cw, ch = ch, gap = gap, gapY = gapY, per = per, score = score }
    end
  end
  return best
end

local BULK_RARITY = {
  { "LEGENDARY", "Legendary", "ffff8000" }, { "EPIC", "Epic", "ffc070ff" },
  { "RARE", "Rare", "ff5aa0ff" }, { "COMMON", "Common", "ffffffff" },
}

function CollectionUI:LayoutBulk()
  self:ClearBrowser()
  local f, bulk = self.frame, self.bulk
  local w, h = f:GetWidth(), f:GetHeight()
  self:PlacePackRoom(w, h)
  place(self.packDim, { x = 0, y = 0, w = w, h = h }, f); self.packDim:Show()
  self.titlePlaque:Show()
  self.titlePlaque:Place(w / 2, math.max(26, h * .058), math.max(34, math.min(56, h * .07)),
    ("Your %d Packs"):format(bulk.packs))
  -- the summary under the plaque
  if not self.bulkSummary then
    self.bulkSummary = fs(f, "caption", "CENTER")
    self.bulkSummary:SetWordWrap(false)
  end
  local parts = {}
  for _, r in ipairs(BULK_RARITY) do
    local n = bulk.summary[r[1]] or 0
    if n > 0 then parts[#parts + 1] = ("|c%s%d %s|r"):format(r[3], n, r[2]) end
  end
  local golden = 0
  for _, c in ipairs(bulk.cards) do if c.golden then golden = golden + 1 end end
  if golden > 0 then parts[#parts + 1] = ("|cffffd100%d Golden|r"):format(golden) end
  if bulk.dust > 0 then parts[#parts + 1] = ("|cff9fd8ff+%d Dust|r"):format(bulk.dust) end
  local sumH = math.max(20, h * .04)
  place(self.bulkSummary, { x = w * .05, y = h - h * .115 - sumH, w = w * .9, h = sumH }, f)
  W.ApplyStyle(self.bulkSummary, "caption", h)
  self.bulkSummary:SetText(table.concat(parts, "   "))
  self.bulkSummary:Show()

  -- the cards
  local area = { x = w * .06, y = h * .14, w = w * .88, h = h * .66 }
  local g = CollectionUI.BulkGrid(area.w, area.h, #bulk.distinct)
  local pages = math.max(1, math.ceil(#bulk.distinct / g.per))
  self.bulkPage = math.max(1, math.min(self.bulkPage or 1, pages))
  local first = (self.bulkPage - 1) * g.per
  local onPage = math.min(g.per, #bulk.distinct - first)
  local rowsUsed = math.ceil(onPage / g.cols)
  local blockH = rowsUsed * g.ch * 1.18 + (rowsUsed - 1) * g.gapY
  local top = area.y + area.h - (area.h - blockH) / 2
  CardWidget.ReleaseAll(self.cardPool)
  self.slots = {}
  self.bulkTags = self.bulkTags or {}
  for i = 1, onPage do
    local e = bulk.distinct[first + i]
    local row, col = math.floor((i - 1) / g.cols), (i - 1) % g.cols
    local inRow = math.min(g.cols, onPage - row * g.cols)
    local rowW = inRow * g.cw + (inRow - 1) * g.gap
    local x = area.x + (area.w - rowW) / 2 + col * (g.cw + g.gap)
    local y = top - row * (g.ch * 1.18 + g.gapY) - g.ch
    local r = { x = x, y = y, w = g.cw, h = g.ch }
    local widget = CardWidget.Acquire(self.cardPool, f)
    if widget.ownedCount then widget.ownedCount:Hide(); widget.ownedPlate:Hide() end
    CardWidget.ApplyRect(widget, r)
    local d = self.resolver:Card(e.cardId)
    if e.golden then
      local copy = {}; for k, v in pairs(d) do copy[k] = v end; copy.golden = true; d = copy
    end
    CardWidget.SetDescriptor(widget, d)
    widget.frame:SetFrameLevel(f:GetFrameLevel() + 6)
    -- every copy went to dust: you did not really get it
    W.SetGhost(widget, e.dusted ~= nil and e.dusted >= e.copies)
    local light = CollectionUI.RARITY_LIGHT[e.rarity]
    if (e.rarity == "LEGENDARY" or e.rarity == "EPIC") and light then
      widget.glow:SetVertexColor(light[1], light[2], light[3], .9); widget.glow:Show()
    else
      widget.glow:Hide()
    end
    widget.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget.frame:SetScript("OnClick", function() self:InspectCard(e.cardId, e.golden) end)
    widget.frame:SetScript("OnEnter", function() if ns.Sounds then ns.Sounds.PlayMenuHover() end end)
    widget.frame:SetScript("OnLeave", nil)
    widget.frame:EnableMouseWheel(true)
    widget.frame:SetScript("OnMouseWheel", function(_, delta)
      self.bulkPage = math.max(1, math.min(pages, self.bulkPage - delta)); self:Relayout()
    end)
    self.slots[i] = { widget = widget, entry = e }
    local t = self.bulkTags[i]
    if not self.bulkLayer then
      -- the tags ride above the cards (which are frames of their own)
      self.bulkLayer = CreateFrame("Frame", nil, f)
      self.bulkLayer:SetAllPoints(); self.bulkLayer:EnableMouse(false)
    end
    self.bulkLayer:SetFrameLevel(f:GetFrameLevel() + 14)
    if not t then
      local L = self.bulkLayer
      t = { count = fs(L, "reveal", "CENTER"), badge = fs(L, "reveal", "CENTER"), stamp = fs(L, "reveal", "CENTER") }
      for _, v in pairs(t) do v:SetWordWrap(false) end
      self.bulkTags[i] = t
    end
    local tagH = g.ch * .13
    place(t.count, { x = x - g.cw * .1, y = y - tagH * 1.05, w = g.cw * 1.2, h = tagH }, f)
    W.ApplyStyle(t.count, "reveal", nil, math.max(10, math.floor(tagH * .78)))
    local label = e.new and "|cffffd24aNEW|r" or ""
    if e.copies > 1 then label = label .. (label ~= "" and "  " or "") .. ("x%d"):format(e.copies) end
    t.count:SetText(label); t.count:SetShown(label ~= "")
    t.badge:Hide()
    if e.dust > 0 then
      place(t.stamp, { x = x - g.cw * .1, y = y + g.ch * .38, w = g.cw * 1.2, h = g.ch * .2 }, f)
      W.ApplyStyle(t.stamp, "reveal", nil, math.max(10, math.floor(g.ch * .13)))
      t.stamp:SetText(("+%d Dust"):format(e.dust)); t.stamp:SetTextColor(.62, .86, 1, 1)
      t.stamp:Show()
    else
      t.stamp:Hide()
    end
  end
  for i = onPage + 1, #self.bulkTags do
    local t = self.bulkTags[i]; t.count:Hide(); t.badge:Hide(); t.stamp:Hide()
  end
  -- page arrows either side, Done beneath
  local aw = math.max(28, math.min(40, w * .03))
  local ay = -(h - area.y - area.h / 2 - aw)
  for i, spec in ipairs({ { 53, area.x - aw * 1.2, -1 }, { 54, area.x + area.w + aw * .2, 1 } }) do
    local arrow = self:MenuItem(spec[1], "", function()
      self.bulkPage = math.max(1, math.min(pages, self.bulkPage + spec[3])); self:Relayout()
    end, spec[2], ay, aw, aw * 2)
    arrow.bg:SetTexture(ART .. "page-arrow.tga")
    if i == 1 then arrow.bg:SetTexCoord(1, 0, 0, 1) else arrow.bg:SetTexCoord(0, 1, 0, 1) end
    arrow:SetFrameLevel(f:GetFrameLevel() + 20)
    arrow:SetShown(pages > 1)
    arrow:SetEnabledLook(i == 1 and self.bulkPage > 1 or i == 2 and self.bulkPage < pages)
  end
  local bw, bh = math.min(w * .18, 240), math.min(50, h * .075)
  local done = self:MenuItem(55, "Done", function() self:CloseBulk() end, w / 2 - bw / 2, -(h - h * .035 - bh), bw, bh)
  done:SetFrameLevel(f:GetFrameLevel() + 20)
  if pages > 1 then
    local pt = self:MenuItem(56, ("Page %d of %d"):format(self.bulkPage, pages), function() end,
      w / 2 + bw / 2 + 12, -(h - h * .035 - bh), bw * .8, bh)
    pt:SetEnabledLook(true); pt.action = nil
    pt:SetFrameLevel(f:GetFrameLevel() + 20)
  end
  for _, b in ipairs({ self.prevButton, self.nextButton, self.craftButton,
                       self.dustButton, self.packButton, self.classButton }) do
    b:Hide()
  end
  self.progressText:Hide(); self.dustText:Hide(); self.pageText:Hide()
  self.statsPlate:SetShown(false)
  self.deckText:Hide()
end

function CollectionUI:ShowDecks()
  self.pack=nil; self.revealedCards=nil; self.bulk=nil; self.bulkPlay=nil
  self.packRoom=nil; self.deckBrowser=true; self:Relayout()
end

--[[ MY DECKS: the saved decks as Hearthstone shows them -- deck boxes, each the
     class hero framed in gold with the deck's name on a banner, laid out on a
     page of the book. Six to a page, turned with the book's gold arrows. ]]
function CollectionUI:LayoutDecks()
  self:ClearBrowser()
  local f=self.frame
  local w,h=f:GetWidth(),f:GetHeight()
  local book={x=w*.07,y=h*.15,w=w*.86,h=h*.70}
  place(self.bookPanel,book,f); self.bookPanel:Show()
  self:LayoutPages({{x=book.x+8,y=book.y+8,w=book.w-16,h=book.h-16}},nil,nil)
  self.hintText:Hide()
  self.titlePlaque:Show()
  self.titlePlaque:Place(w/2,math.max(26,h*.058),math.max(34,math.min(56,h*.07)),"My Decks")
  local decks=self.collection.character.decks

  --[[ Deck boxes in two rows, as many across as the page holds, filled from
       the TOP-LEFT like a page of the collection. It was a centred block of
       three, so a single deck sat alone a third of the way across a mostly
       empty page. The block as a whole is centred, so a full page is
       balanced; a part-filled one reads left to right from the corner. ]]
  --[[ ...and as many ROWS as keep the boxes large (W.DeckGrid). Two rows were
       fixed, so a wide, short window drew boxes too small for their names;
       now it gets one row of large ones. The block's top sits at the top of
       the page. ]]
  local pad,gap=math.max(28,book.w*.04),math.max(14,book.w*.022)
  local innerW,innerH=book.w-2*pad,book.h-2*pad
  local rows,cols,bw,bh=W.DeckGrid(innerW,innerH,gap,math.max(180,math.min(320,h*.32)))
  local perPage=cols*rows
  local pages=math.max(1,math.ceil(#decks/perPage))
  self.deckPage=math.max(1,math.min(self.deckPage or 1,pages))
  local gx=book.x+(book.w-(cols*bw+(cols-1)*gap))/2
  local gy=(h-book.y-book.h)+pad
  local active=self.collection.character.activeDeck
  for slot=1,perPage do
    local index=(self.deckPage-1)*perPage+slot; local deck=decks[index]
    if deck then
      local x,y=gx+((slot-1)%cols)*(bw+gap),gy+math.floor((slot-1)/cols)*(bh+gap)
      local box=self:MenuItem(slot,"",function() self:EditDeck(index) end,x,-y,bw,bh)
      local valid=self.collection:ValidateDeck(deck)
      W.StyleDeckBox(box,{
        portrait=self.resolver:Card(W.DeckArtCard(deck)).icon,
        name=deck.name or "Deck",
        detail=valid and "30/30 cards" or (#deck.cards.."/30 cards"),
        detailColor=valid and W.Colors.count or {1,.45,.35},
        selected=active==index,
      })
      local confirming=self.deleteDeckIndex==index
      local del=self:MenuItem(20+slot,confirming and "Sure?" or "",function()
        if self.deleteDeckIndex==index then
          self.collection:DeleteDeck(index); self.deleteDeckIndex=nil; self.deckIndex=nil
        else self.deleteDeckIndex=index end
        self:Relayout()
      end,x+bw-(confirming and 62 or 26)-4,-(y+4),confirming and 62 or 26,26)
      del:SetFrameLevel(box:GetFrameLevel()+6)
      del.textColor=W.Colors.danger
      W.ApplyStyle(del.text,"button",nil,12,W.Colors.danger)
      if not confirming then
        -- the same small gilded round button with a drawn cross as every
        -- window's close, not a letter on a plaque
        del.bg:SetTexture(ART.."hs-round.tga"); del.bg:SetTexCoord(0,1,0,1)
        if not rawget(del,"roundIcon") then
          del.roundIcon=del:CreateTexture(nil,"OVERLAY")
          del.roundIcon:SetTexture(ART.."close-x.tga"); del.roundIcon:SetPoint("CENTER")
        end
        del.roundIcon:SetSize(15,15); del.roundIcon:Show()
      end
    end
  end
  if #decks==0 then
    place(self.deckHint,{x=book.x,y=book.y+book.h*.4,w=book.w,h=60},f)
    W.ApplyStyle(self.deckHint,"pageText",h); self.deckHint:SetText("No decks yet.\nPress New Deck to start one.")
    self.deckHint:Show()
  end
  -- Collection | New Deck | Import Deck, centred under the book
  local bw3,bh3=math.min(w*.2,260),math.min(50,h*.08)
  local x0=w/2-bw3*1.5-12
  self:MenuItem(44,"Collection",function() self:EditDeck(nil) end,
    x0,-(h-book.y+12),bw3,bh3)
  self:MenuItem(41,"New Deck",function()
    local _,index=self.collection:NewDeck("New Deck",self.collection.character.class)
    if index then self:EditDeck(index) end
  end,x0+bw3+12,-(h-book.y+12),bw3,bh3)
  -- paste a Hearthstone deck code (docs/45)
  self:MenuItem(45,"Import Deck",function() self:ShowDeckCode("import") end,
    x0+2*(bw3+12),-(h-book.y+12),bw3,bh3)
  -- The page arrows hang off the book's edges, like the collection's.
  local aw=math.max(28,math.min(40,w*.03))
  local ay=-(h-book.y-book.h/2-aw)
  for i,spec in ipairs({{42,book.x-aw/2,-1},{43,book.x+book.w-aw/2,1}}) do
    local arrow=self:MenuItem(spec[1],"",function() self.deckPage=self.deckPage+spec[3]; self:Relayout() end,spec[2],ay,aw,aw*2)
    arrow.bg:SetTexture(ART.."page-arrow.tga")
    if i==1 then arrow.bg:SetTexCoord(1,0,0,1) else arrow.bg:SetTexCoord(0,1,0,1) end
    arrow:SetFrameLevel(self.bookPanel:GetFrameLevel()+10)
    arrow:SetEnabledLook(i==1 and self.deckPage>1 or i==2 and self.deckPage<pages)
  end
end

--[[ What a card slot says beyond the card itself: how many you own, whether it
     is a spare, and whether it is selected.

     Unowned cards are DIMMED rather than hidden in the crafting view, because
     seeing what you are missing is the whole reason to browse the set. ]]
function CollectionUI:DecorateSlot(widget, entry)
  local count = entry.owned + entry.golden
  local label = (count > 0) and ("x" .. count) or ""
  if entry.golden > 0 then label = label .. " |cffffd100G|r" end
  if entry.extra then label = label .. " spare" end
  -- the tab is sized to what shows, not to the colour codes in the string
  local shown = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  widget.name:SetText(widget.descriptor.name or "")
  -- The count hangs under the card on a small dark tab, as Hearthstone's does.
  if not widget.ownedCount then
    widget.ownedPlate=widget.frame:CreateTexture(nil,"OVERLAY",nil,-1)
    widget.ownedPlate:SetTexture(ART.."count-box.tga")
    widget.ownedCount=fs(widget.frame,"count","CENTER")
  end
  -- the tab follows the card's size (it hangs into the book's foot band,
  -- CollectionLayout COUNT_TAB_H)
  local cardH=widget.frame:GetHeight()
  local tabH=math.max(15,math.min(22,cardH*.085))
  local size=math.floor(tabH*.66)
  local plateW=math.max(tabH*1.7,#shown*size*.62+tabH*.8)
  widget.ownedPlate:ClearAllPoints(); widget.ownedPlate:SetPoint("TOP",widget.frame,"BOTTOM",0,tabH*.22)
  widget.ownedPlate:SetSize(plateW,tabH); widget.ownedPlate:SetShown(label~="")
  widget.ownedCount:ClearAllPoints(); widget.ownedCount:SetPoint("CENTER",widget.ownedPlate,"CENTER",0,0)
  widget.ownedCount:SetSize(plateW,tabH)
  W.ApplyStyle(widget.ownedCount,"count",nil,size)
  widget.ownedCount:SetText(label); widget.ownedCount:Show()
  --[[ While editing a deck, a card with no copy left to add greys out as in
       Hearthstone: every owned copy is in the deck, or it is at the limit
       (two, one for a legendary). A full deck greys nothing -- that is a
       deck limit, not this card's. ]]
  local spent = false
  local deck = self:CurrentDeck()
  if deck and count > 0 then
    local used = 0
    for _, id in ipairs(deck.cards or {}) do if id == entry.cardId then used = used + 1 end end
    spent = used >= math.min(self.collection:Count(entry.cardId), self.collection:MaxCopies(entry.cardId))
  end
  W.SetGhost(widget, count == 0 or spent)
  if self.selected and self.selected.cardId == entry.cardId then
    widget.glow:Show()
    widget.glow:SetVertexColor(1, 0.9, 0.4, 0.6)
  else
    widget.glow:Hide()
  end
end

-- ============================================================== actions

-- Left-click adds to a deck; left-clicking a deck row removes a copy.
-- Right-click always inspects the card and exposes crafting actions.
function CollectionUI:OnCardClick(entry, button)
  if button == "RightButton" then
    self.selected = entry
    self:Relayout()
    self:InspectSelected()
    return
  end
  if self.deckIndex then
    self:AddToDeck(entry.cardId)
    return
  end
  if self.selected and self.selected.cardId == entry.cardId then
    self.selected = nil
  else
    self.selected = entry
  end
  self:Relayout()
end

function CollectionUI:InspectSelected()
  local entry = self.selected
  if not entry then return end
  self.inspectingCard = nil
  local w, h = self.frame:GetWidth(), self.frame:GetHeight()
  local ch = math.min(h * 0.70, 440)
  CardWidget.SetDescriptor(self.inspect.card, self.resolver:Card(entry.cardId))
  CardWidget.ApplyRect(self.inspect.card, {x=(w-ch*0.7)/2,y=(h-ch)/2,w=ch*0.7,h=ch})
  self.inspectCraft:Show(); self.inspectDust:Show()
  self.craftButton:Hide(); self.dustButton:Hide()
  self.inspectCraft:SetEnabledLook(entry.canCraft)
  self.inspectDust:SetEnabledLook(self.collection:CanDisenchant(entry.cardId, entry.owned == 0 and entry.golden > 0))
  local caption = self:LabelCraftButtons(entry, self.inspectCraft, self.inspectDust)
  local buttons = {self.inspectCraft,self.inspectDust}
  -- a card in the deck being edited can be chosen to stand for it
  local deck = self:CurrentDeck()
  local inDeck = false
  for _, id in ipairs(deck and deck.cards or {}) do if id == entry.cardId then inDeck = true; break end end
  self.inspectArt:SetShown(inDeck)
  if inDeck then
    self.inspectArt.text:SetText(deck.art == entry.cardId and "Automatic Art" or "Use as Deck Art")
    buttons[3] = self.inspectArt
  end
  for i, button in ipairs(buttons) do
    button:ClearAllPoints()
    button:SetPoint("CENTER", self.inspect.frame, "CENTER", (i-(#buttons+1)/2)*185, -ch/2-25)
  end
  self.inspectCost:ClearAllPoints()
  self.inspectCost:SetPoint("TOP", self.inspect.frame, "CENTER", 0, -ch/2-48)
  self.inspectCost:SetText(caption); self.inspectCost:Show()
  W.InspectKeywords(self.inspect, entry.cardId)
  self.inspect.frame:Show()
end

--[[ WHAT IT COSTS. Craft says its price and Disenchant what it gives, on the
     buttons themselves, and the enlarged card adds a line with the dust you
     have -- you should not have to press Craft to learn you cannot afford it.
     Returns that line. ]]
function CollectionUI:LabelCraftButtons(entry, craft, dust)
  local otherClass=entry and entry.printed.class~="NEUTRAL"
    and entry.printed.class~=self.collection.character.class
  local restriction="Only your class and Neutral cards can be crafted. Other classes are excluded from your collection count."
  craft:SetScript("OnEnter",function()
    if otherClass and GameTooltip then
      GameTooltip:SetOwner(craft,"ANCHOR_RIGHT"); GameTooltip:SetText(restriction); GameTooltip:Show()
    end
  end)
  craft:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
  local v = entry and self.collection:DustValues(entry.cardId)
  local have = self.collection:Dust()
  if not v then
    craft.text:SetText("Craft"); dust.text:SetText("Disenchant"); return ""
  end
  local golden = entry.owned == 0 and entry.golden > 0
  local gain = golden and v.deGolden or v.de
  dust.text:SetText(("Disenchant +%d"):format(gain))
  if otherClass then
    craft.text:SetText("Other class"); craft:SetEnabledLook(false)
    return restriction
  end
  if not v.craftable then
    craft.text:SetText("Craft")
    return "Basic cards are granted, not crafted"
  end
  craft.text:SetText(("Craft %d"):format(v.craft))
  if have >= v.craft then
    return ("Crafting costs %d dust -- you have %d"):format(v.craft, have)
  end
  return ("Crafting costs %d dust -- you have %d (%d short)"):format(v.craft, have, v.craft - have)
end

--[[ The enlarged card alone, for a card that is being SHOWN rather than
     managed -- one just pulled from a pack. No craft or disenchant: the
     reveal is not the place to dust what you just opened. Click to close. ]]
function CollectionUI:InspectCard(cardId, golden)
  self.inspectingCard = { cardId = cardId, golden = golden }
  local w, h = self.frame:GetWidth(), self.frame:GetHeight()
  local ch = math.min(h * 0.70, 440)
  local d = self.resolver:Card(cardId)
  if golden then
    local copy = {}; for k, v in pairs(d) do copy[k] = v end; copy.golden = true; d = copy
  end
  CardWidget.SetDescriptor(self.inspect.card, d)
  CardWidget.ApplyRect(self.inspect.card, {x=(w-ch*0.7)/2,y=(h-ch)/2,w=ch*0.7,h=ch})
  self.inspectCraft:Hide(); self.inspectDust:Hide(); self.inspectArt:Hide(); self.inspectCost:Hide()
  W.InspectKeywords(self.inspect, cardId)
  self.inspect.frame:Show()
end

function CollectionUI:TurnPage(delta)
  self.page = self.page + delta
  self.scrollRow = math.max(0, (self.scrollRow or 0) + delta * (self.L and self.L.rows or 1))
  self:Relayout()
end

function CollectionUI:Scroll(rows)
  if self.pack then return end
  self.scrollRow = math.max(0, math.min((self.scrollRow or 0) + rows, self.maxScrollRow or 0))
  self:Relayout()
end

--[[ The filter cycles through the states a collector actually uses: everything
     you own, your class, neutrals, and the whole set including what you do not
     have (which is the crafting view). ]]
local FILTERS = {
  { label = "All Cards", filter = {} },
  { label = "My class",  filter = { class = "SELF" } },
  { label = "Neutral",   filter = { class = "NEUTRAL" } },
  { label = "Golden",    filter = { golden = true } },
}

for _, class in ipairs(ns.CLASSES) do
  FILTERS[#FILTERS + 1] = {label=class:sub(1,1)..class:sub(2):lower(), filter={class=class}}
end

local FILTER_INDEX = {}
for i, entry in ipairs(FILTERS) do FILTER_INDEX[entry.filter.class or entry.label] = i end

-- Which class crests the book shows, each naming the FILTERS entry it selects.
function CollectionUI:TabSpecs()
  if self.deckIndex then
    local class = self.collection and self.collection.character.class or "NEUTRAL"
    return { { index = 1, icon = "all" }, { index = 2, icon = class:lower() },
             { index = 3, icon = "neutral" } }
  end
  local tabs = { { index = 1, icon = "all" } }
  for _, class in ipairs(ns.CLASSES) do
    tabs[#tabs + 1] = { index = FILTER_INDEX[class], icon = class:lower() }
  end
  tabs[#tabs + 1] = { index = 3, icon = "neutral" }
  return tabs
end

local function titleCase(s)
  return (s:lower():gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- The heading printed across the top of each page: what is being browsed.
function CollectionUI:PageTitle()
  local entry = FILTERS[self.filterIndex or 1]
  if entry.label == "My class" then
    return titleCase(self.collection and self.collection.character.class or "My class")
  end
  return titleCase(entry.label)
end

function CollectionUI:CycleFilter()
  self:SetFilter(((self.filterIndex or 1) % #FILTERS) + 1)
end

function CollectionUI:ToggleFilters()
  if self.filterMenu and self.filterMenu:IsShown() then self.filterMenu:Hide(); return end
  if not self.filterMenu then
    self.filterMenu=W.MenuPanel(self.frame,"leather")
    self.filterMenu:SetFrameLevel(250)
    self.filterButtons={}
    for i,entry in ipairs(FILTERS) do
      local index=i
      local b=makeButton(self.filterMenu,entry.label,function() self:SetFilter(index) end)
      b:SetSize(138,28); self.filterButtons[i]=b
    end
  end
  local count=self.deckIndex and 4 or #FILTERS
  self.filterMenu:SetSize(300,math.ceil(count/2)*32+16)
  self.filterMenu:ClearAllPoints(); self.filterMenu:SetPoint("TOPRIGHT",self.classButton,"BOTTOMRIGHT",0,-4)
  for i,b in ipairs(self.filterButtons) do
    b:ClearAllPoints(); b:SetPoint("TOPLEFT",self.filterMenu,"TOPLEFT",10+((i-1)%2)*142,-8-math.floor((i-1)/2)*32)
    b:SetShown(i<=count)
  end
  self.filterMenu:Show()
end

function CollectionUI:SetFilter(index)
  self.filterIndex=index
  local f = FILTERS[self.filterIndex]
  local filter = {}
  for k, v in pairs(f.filter) do filter[k] = v end
  if filter.class == "SELF" then filter.class = self.collection.character.class end
  filter.text=self.filter.text; filter.cost=self.filter.cost; filter.all=self.filter.all
  self.filter = filter
  self.page = 1
  self.scrollRow = 0
  self.classButton.text:SetText(f.label)
  self:Relayout()
end

--[[ An Epic or Legendary is 400 or 1600 dust, and disenchanting it again
     gives back a quarter: one stray click there is asked about first. ]]
CollectionUI.CONFIRM_CRAFT_AT = 400
function CollectionUI:CraftSelected(confirmed)
  local entry = self.selected
  if not entry then return end
  local v = self.collection:DustValues(entry.cardId)
  if not confirmed and entry.canCraft and v and v.craft and v.craft >= CollectionUI.CONFIRM_CRAFT_AT
     and self.collection:Dust() >= v.craft then
    if not self.craftDialog then
      local dialog
      dialog = W.Dialog(self.frame, "ForeverHearthstoneCraftConfirm", {
        { "Craft", function() dialog:Hide(); self:CraftSelected(true) end },
        { "Cancel", function() dialog:Hide() end },
      }, { paper = true })
      self.craftDialog = dialog
    end
    for _, p in ipairs(self.inspect.keywordPanels or {}) do p:Hide() end
    self.craftDialog.message:SetText(("Craft %s for %d dust?\n\nYou have %d. Disenchanting it later gives back %d.")
      :format(entry.printed.name, v.craft, self.collection:Dust(), v.de or 0))
    self.craftDialog:Show()
    return
  end
  local ok, result = self.collection:Craft(entry.cardId)
  if not ok then self.onPrint(result); return end
  self.onPrint(("crafted %s for %d dust."):format(entry.printed.name, result))
  self:PlayCraftFX(entry)
  --[[ Re-select from the fresh list: the entry table the player clicked is a
       snapshot, and after crafting its counts are out of date. Keeping the
       stale one is how a screen shows "you own 0" of a card you just made. ]]
  self.selected = nil
  self:Relayout()
end

function CollectionUI:DisenchantSelected()
  local entry=self.selected
  if not entry then return end
  local golden=(entry.owned==0 and entry.golden>0)
  local allowed,why=self.collection:CanDisenchant(entry.cardId,golden)
  if not allowed then self.onPrint(why); return end
  if not self.disenchantDialog then
    local dialog
    dialog=W.Dialog(self.frame,"ForeverHearthstoneDisenchantConfirm",{
      {"Disenchant",function() self:ConfirmDisenchant() end},
      {"Cancel",function() dialog:Hide() end},
    },{paper=true})
    self.disenchantDialog=dialog
    dialog.confirm,dialog.cancel=dialog.buttons[1],dialog.buttons[2]
    dialog:SetScript("OnHide",function()
      self.pendingDisenchant=nil
      -- the card's keyword notes return if it is still being read
      if self.inspect.frame:IsShown() and self.selected then W.InspectKeywords(self.inspect,self.selected.cardId) end
    end)
  end
  --[[ The inspected card's keyword notes drew ABOVE this dialog's dim in the
       client (the in-client tour, docs/39), though their frame level is below
       it. They are only notes on the card being read; they step aside. ]]
  for _,p in ipairs(self.inspect.keywordPanels or {}) do p:Hide() end
  local values=self.collection:DustValues(entry.cardId)
  self.pendingDisenchant={entry=entry,golden=golden}
  -- decks that would be left needing this copy, named before it goes
  local left=self.collection:Count(entry.cardId)-1
  local hurt={}
  for _,d in ipairs(self.collection.character.decks or {}) do
    local used=0
    for _,id in ipairs(d.cards or {}) do if id==entry.cardId then used=used+1 end end
    if used>left then hurt[#hurt+1]=d.name or "Deck" end
  end
  local warning=#hurt>0 and ("\n|cffff7055Used in: "..table.concat(hurt,", ").." -- it will be incomplete.|r") or ""
  self.disenchantDialog.message:SetText("Disenchant 1 "..(golden and "GOLDEN " or "")..entry.printed.name.."?\n\nReceive "..(golden and values.deGolden or values.de).." dust.\nThis removes one copy from your collection."..warning)
  self.disenchantDialog:Show()
end

function CollectionUI:ConfirmDisenchant()
  local pending=self.pendingDisenchant
  if not pending then return end
  self.disenchantDialog:Hide()
  local entry=pending.entry
  -- Revalidate the specific copy confirmed, never whatever is now selected.
  local ok,result=self.collection:Disenchant(entry.cardId,pending.golden)
  if not ok then self.onPrint(result); return end
  self.onPrint(("disenchanted %s for %d dust."):format(entry.printed.name,result))
  self:PlayDisenchantFX(entry)
  self.selected=nil; self.inspect.frame:Hide(); self:Relayout()
end

-- ============================================================ deck editing

function CollectionUI:EditDeck(index)
  self.pack=nil; self.revealedCards=nil; self.bulk=nil; self.bulkPlay=nil
  self.deckBrowser = nil
  self.packRoom = nil
  self:HideMenuItems()
  local decks = self.collection.character.decks
  if index and not decks[index] then self.onPrint("no such deck."); return end
  self.deckIndex = index
  self.deckScroll = 0
  self.filter.class = nil
  self.selected = nil
  self.page = 1
  self.scrollRow = 0
  self:Relayout()
end

function CollectionUI:CurrentDeck()
  return self.deckIndex and self.collection.character.decks[self.deckIndex] or nil
end

function CollectionUI:AddToDeck(cardId)
  local deck = self:CurrentDeck()
  if not deck then return end
  local ok, why = self.collection:CanAdd(deck, cardId)
  if not ok then self.onPrint(why); return end
  deck.cards[#deck.cards + 1] = cardId
  self:Relayout()
end

--- The inspected card on the deck's box -- or, if it already is, back to the
--- automatic pick.
--[[ A notice across the top of the window for a few seconds: the reply to
     something the player just did, where they are looking. ]]
CollectionUI.TOAST_SECONDS = 3
function CollectionUI:Toast(text)
  if not (self.frame and text and text ~= "") then return end
  local p = self.toast
  if not p then
    p = W.HSPanel(self.frame)
    p:SetFrameLevel(520)
    p:EnableMouse(false)
    self.toast = p
  end
  p:SetContent(nil, (tostring(text):gsub("^%l", string.upper)), math.floor(math.min(460, self.frame:GetWidth() * .42)))
  p:ClearAllPoints()
  p:SetPoint("TOP", self.frame, "TOP", 0, -self.frame:GetHeight() * .12)
  p:Show()
  self.toastSerial = (self.toastSerial or 0) + 1
  local serial = self.toastSerial
  if C_Timer and C_Timer.After then
    C_Timer.After(CollectionUI.TOAST_SECONDS, function()
      if self.toastSerial == serial then p:Hide() end
    end)
  end
end

function CollectionUI:ToggleDeckArt()
  local deck, entry = self:CurrentDeck(), self.selected
  if not (deck and entry) then return end
  local ok, why = self.collection:SetDeckArt(deck, deck.art ~= entry.cardId and entry.cardId or nil)
  if not ok then self.onPrint(why); return end
  self:Relayout()   -- redraws the open inspect view too, with the button's new label
end

function CollectionUI:RemoveFromDeck(cardId)
  local deck = self:CurrentDeck()
  if not deck then return end
  for i = #deck.cards, 1, -1 do
    if deck.cards[i] == cardId then
      table.remove(deck.cards, i)
      self:Relayout()
      return
    end
  end
end

--[[ The deck list as text, grouped and counted the way Hearthstone shows it:
     one line per distinct card, sorted by cost, with a count when you hold two.
     Built as a string rather than as widgets because a 30-line list of text is
     one frame instead of thirty. ]]
function CollectionUI:DeckSummary()
  local deck = self:CurrentDeck()
  if not deck then return "" end
  local counts, order = {}, {}
  for _, id in ipairs(deck.cards) do
    if not counts[id] then counts[id] = 0; order[#order + 1] = id end
    counts[id] = counts[id] + 1
  end
  table.sort(order, function(a, b)
    local pa, pb = ns.PrintedCards[a], ns.PrintedCards[b]
    if (pa.cost or 0) ~= (pb.cost or 0) then return (pa.cost or 0) < (pb.cost or 0) end
    return (pa.name or a) < (pb.name or b)
  end)
  local lines = { ("|cffffd100%s|r  %d/%d"):format(deck.name or "Deck",
                                                   #deck.cards, ns.RULES.DECK_SIZE) }
  for _, id in ipairs(order) do
    local p = ns.PrintedCards[id]
    lines[#lines + 1] = ("(%d) %s%s"):format(p.cost or 0, p.name or id,
                                             counts[id] > 1 and ("  x" .. counts[id]) or "")
  end
  local ok, errors = self.collection:ValidateDeck(deck)
  if not ok and #deck.cards >= ns.RULES.DECK_SIZE then
    lines[#lines + 1] = "|cffff5555" .. errors[1] .. "|r"
  end
  return table.concat(lines, "\n")
end

-- =========================================================== pack opening

--[[ Open a pack and take over the screen with it.

     The contents are generated and banked BEFORE anything animates (see
     Client/Packs.lua): the reveal is a presentation of something that has
     already happened, so a disconnect halfway through costs an animation, not a
     pack. ]]
function CollectionUI:OpenPack(set)
  local explicitSet = set ~= nil
  set = set or "HEARTHSTONE"
  if not explicitSet and self.collection:PackCount(set) <= 0 then
    --[[ Fall through to whichever type they DO have, rather than refusing: the
         button says "Open Pack" and the player does not care which. ]]
    for other in pairs(ns.Packs.SETS) do
      if self.collection:PackCount(other) > 0 then set = other break end
    end
  end
  local pack, why = ns.Packs.Open(self.collection, set)
  if not pack then self.onPrint(why); return end

  self.pack = pack
  self.packRevealed = 0
  self.revealedCards = {}
  self.packDusted = {}
  self.packTold, self.packHover = {}, nil
  self:HidePackLights()
  self:Relayout()
  self:PlayPackFX(pack)
end

--[[ THE LIGHT BEHIND A PACK CARD. Each of the five has a soft glow in its
     own shape (fx-aura, 1.5x the card) and a sunburst (fx-rays), both white
     and tinted by rarity, on a layer between the room and the cards. They
     used to borrow the card widget's own glow -- the card FRONT's outline,
     stretched into a hard gold block round a face-down back.

     Hearthstone's rules for it: a face-down card glows in its rarity's
     colour only while the pointer is over it, with its rarity's sound the
     first time; it flares as it turns (CardReveal); a golden card keeps a
     soft gold light afterwards; nothing else keeps one. ]]
CollectionUI.RARITY_LIGHT = { COMMON = { .75, .85, 1, .35 }, FREE = { .75, .85, 1, .35 },
  RARE = { .3, .6, 1, .9 }, EPIC = { .7, .3, 1, .9 }, LEGENDARY = { 1, .65, .15, .95 } }
local GOLDEN_LIGHT = { 1, .82, .3, .45 }

function CollectionUI:PackLight(i)
  self.packFx = self.packFx or {}
  local fx = self.packFx[i]
  if not fx then
    if not self.packFxLayer then
      self.packFxLayer = CreateFrame("Frame", nil, self.frame)
      self.packFxLayer:SetAllPoints()
    end
    fx = { rays = self.packFxLayer:CreateTexture(nil, "BORDER"),
           aura = self.packFxLayer:CreateTexture(nil, "ARTWORK") }
    fx.rays:SetTexture(ART .. "fx-rays.tga"); fx.aura:SetTexture(ART .. "fx-aura.tga")
    for _, t in ipairs({ fx.rays, fx.aura }) do t:SetBlendMode("ADD"); t:Hide() end
    self.packFx[i] = fx
  end
  return fx
end

function CollectionUI:SetPackLight(fx, c, a)
  if not c or (a or 0) <= 0 then fx.aura:Hide(); return end
  fx.aura:SetVertexColor(c[1], c[2], c[3], a); fx.aura:Show()
end

function CollectionUI:HidePackLights()
  for _, fx in ipairs(self.packFx or {}) do fx.aura:Hide(); fx.rays:Hide(); fx.until_ = nil end
end

function CollectionUI:LayoutPack(w, h)
  self:PlacePackRoom(w,h)
  place(self.packDim,{x=0,y=0,w=w,h=h},self.frame); self.packDim:Show()
  local L = CL.Compute({ w = w, h = h, packOpening = true, packCount = #self.pack.cards })
  self.L = L
  CardWidget.ReleaseAll(self.cardPool)
  self.slots = {}
  for i, card in ipairs(self.pack.cards) do
    local widget = CardWidget.Acquire(self.cardPool, self.frame)
    if widget.ownedCount then widget.ownedCount:Hide(); widget.ownedPlate:Hide() end
    --[[ The pool is shared with the collection's pages, where a card you do
         not own is greyed. A pack card took that grey with it -- so a card
         you had just unlocked could come up looking unowned. ]]
    W.SetGhost(widget, false)
    CardWidget.ApplyRect(widget, L.packCards[i])
    local r = L.packCards[i]
    local fx = self:PackLight(i)
    self.packFxLayer:SetFrameLevel(self.frame:GetFrameLevel() + 2)
    widget.frame:SetFrameLevel(self.frame:GetFrameLevel() + 6)
    fx.aura:ClearAllPoints(); fx.aura:SetSize(r.w * 1.5, r.h * 1.5)
    fx.aura:SetPoint("CENTER", self.frame, "BOTTOMLEFT", r.x + r.w / 2, r.y + r.h / 2)
    fx.cx, fx.cy, fx.size = r.x + r.w / 2, r.y + r.h / 2, math.max(r.w, r.h) * 2.6
    widget.glow:Hide()
    if (self.revealedCards and self.revealedCards[i]) or (not self.revealedCards and i <= self.packRevealed) then
      CardWidget.SetDescriptor(widget, self.resolver:Card(card.cardId))
      -- a reveal still flaring keeps its light; a relayout must not cut it off
      if not (fx.until_ and GetTime() < fx.until_) then
        self:SetPackLight(fx, card.golden and GOLDEN_LIGHT or nil, GOLDEN_LIGHT[4])
        fx.rays:Hide()
      end
    else
      --[[ Face down. A blank back rather than a card with its text hidden,
           because the anticipation only works if there is genuinely nothing to
           read yet. ]]
      CardWidget.SetDescriptor(widget, {
        name = "", text = "", type = "MINION",
        frameColor = { 0.25, 0.22, 0.35 }, gemColor = { 0.2, 0.2, 0.25 },
      })
      CardWidget.SetFaceDown(widget, true)
      if not self.packHover or self.packHover ~= i then self:SetPackLight(fx, nil) end
      fx.rays:Hide()
    end
    widget.frame:SetScript("OnEnter",function()
      if self.revealedCards and self.revealedCards[i] then return end
      self.packHover = i
      local c = CollectionUI.RARITY_LIGHT[card.rarity] or CollectionUI.RARITY_LIGHT.COMMON
      self:SetPackLight(fx, c, c[4])
      -- its rarity's sound, once per card, as Hearthstone does on the hover
      self.packTold = self.packTold or {}
      local tell = card.rarity and card.rarity ~= "COMMON" and card.rarity ~= "FREE"
      if ns.Sounds then
        if tell and not self.packTold[i] then ns.Sounds.Play("rarity_tell_" .. card.rarity:lower())
        else ns.Sounds.PlayMenuHover() end
      end
      if tell then self.packTold[i] = true end
    end)
    widget.frame:SetScript("OnLeave",function()
      if self.packHover == i then self.packHover = nil end
      if not (self.revealedCards and self.revealedCards[i]) then self:SetPackLight(fx, nil) end
    end)
    widget.frame:EnableMouseWheel(false)
    widget.frame:SetScript("OnMouseWheel",nil)
    --[[ Right-click reads a revealed card up close, as it does everywhere
         else; on a face-down one it is just another way to flip it. ]]
    widget.frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget.frame:SetScript("OnClick", function(_, button)
      if button == "RightButton" and self.revealedCards and self.revealedCards[i] then
        return self:InspectCard(card.cardId, card.golden)
      end
      self:RevealCard(i)
    end)
    self.slots[i] = { widget = widget, card = card }
  end

  -- Hearthstone says nothing while you choose; each card's class appears
  -- beneath it as it turns, and Done in the middle once all five have
  self.hintText:Hide()
  for i, card in ipairs(self.pack.cards) do
    local label = self.packLabels[i]
    if not label then
      label = fs(self:PackTextLayer(), "reveal", "CENTER")
      W.AutoFit(label, { w = 120, h = 26, font = ns.Fonts.TITLE, size = 22, min = 9, flags = "THICKOUTLINE" })
      label:SetShadowOffset(0, 0); label:SetShadowColor(.2, .5, 1, 1)
      self.packLabels[i] = label
    end
    local r = L.packLabels[i]
    place(label, r, self.frame)
    W.SetFitBox(label, r.w, r.h, math.max(10, math.floor(r.h * .78)))
    label:SetText(self:PackClassName(card.cardId))
    local revealed = self.revealedCards and self.revealedCards[i] and true or false
    label:SetShown(revealed)
    --[[ AN EXTRA COPY SAYS SO. A third common (a second legendary) cannot go
         in a deck; it is still kept, and it is worth dust. Under the class
         name, in the warning colour, with what disenchanting it gives. ]]
    self.packExtras = self.packExtras or {}
    local extra = self.packExtras[i]
    if not extra then
      extra = fs(self:PackTextLayer(), "caption", "CENTER")
      W.AutoFit(extra, { w = 120, h = 20, font = ns.Fonts.TITLE, size = 15, min = 8, flags = "OUTLINE" })
      self.packExtras[i] = extra
    end
    if revealed and card.dust then
      place(extra, { x = r.x - r.w * .15, y = r.y - r.h * .95, w = r.w * 1.3, h = r.h * .8 }, self.frame)
      W.SetFitBox(extra, r.w * 1.3, r.h * .8, math.max(9, math.floor(r.h * .55)))
      extra:SetText(card.dustedPlain and "Duplicate - a plain copy became dust"
                    or "Duplicate - turned into dust")
      extra:SetTextColor(.55, .82, 1, 1)
      extra:Show()
    elseif revealed and card.extra then
      local v = self.collection:DustValues(card.cardId)
      local gain = v and (card.golden and v.deGolden or v.de)
      place(extra, { x = r.x - r.w * .15, y = r.y - r.h * .95, w = r.w * 1.3, h = r.h * .8 }, self.frame)
      W.SetFitBox(extra, r.w * 1.3, r.h * .8, math.max(9, math.floor(r.h * .55)))
      extra:SetText(gain and ("Extra copy - disenchant for %d dust"):format(gain) or "Extra copy")
      extra:SetTextColor(1, .62, .3, 1)
      extra:Show()
    else
      extra:Hide()
    end
    --[[ ...and once its dust has blown off (DustPackCard), the card stays
         greyed under a "+N" stamp, so a glance at the five says which one you
         did not really get. A golden that pushed out a plain copy is still
         yours, and stays in colour. ]]
    self.packStamps = self.packStamps or {}
    local stamp = self.packStamps[i]
    if not stamp then
      stamp = fs(self:PackTextLayer(), "reveal", "CENTER")
      W.AutoFit(stamp, { w = 120, h = 40, font = ns.Fonts.NUMBER, size = 30, min = 10, flags = "THICKOUTLINE" })
      self.packStamps[i] = stamp
    end
    local dusted = revealed and card.dust and self.packDusted and self.packDusted[i]
    if dusted then
      if not card.dustedPlain then W.SetGhost(self.slots[i].widget, true) end
      local c = L.packCards[i]
      place(stamp, { x = c.x - c.w * .1, y = c.y + c.h * .38, w = c.w * 1.2, h = c.h * .24 }, self.frame)
      W.SetFitBox(stamp, c.w * 1.2, c.h * .24, math.max(12, math.floor(c.h * .17)))
      stamp:SetText(("+%d Dust"):format(card.dust))
      stamp:SetTextColor(.62, .86, 1, 1)
      stamp:Show()
    else
      stamp:Hide()
    end
  end
  if not self.packDone then
    self.packDone = makeButton(self.frame, "Done", function()
      if self.bulkPlay then self:BulkNextPack() else self:ClosePack() end
    end)
    self.packDone:SetFrameLevel(self.frame:GetFrameLevel() + 30)
  end
  place(self.packDone, L.packDone, self.frame)
  W.ApplyStyle(self.packDone.text, "button", nil, math.max(12, math.floor(L.packDone.h * .45)))
  self.packDone.text:SetText(self.bulkPlay and (self.bulkPlay.index < self.bulkPlay.result.packs and "Next Pack" or "See All") or "Done")
  self.packDone:SetShown(self.packRevealed >= #self.pack.cards)
  -- opening several: which pack this is, and a way straight to the summary
  if self.bulkPlay then
    if not self.bulkSkip then
      self.bulkSkip = makeButton(self.frame, "Skip to All Cards", function() self:FinishBulk() end)
      self.bulkCounter = fs(self.frame, "caption", "CENTER")
    end
    local w, h = self.frame:GetWidth(), self.frame:GetHeight()
    local bw, bh = math.min(w * .2, 250), math.max(30, math.min(46, h * .065))
    place(self.bulkSkip, { x = w - bw - 20, y = 20, w = bw, h = bh }, self.frame)
    self.bulkSkip:SetFrameLevel(self.frame:GetFrameLevel() + 30)
    W.ApplyStyle(self.bulkSkip.text, "button", nil, math.max(12, math.floor(bh * .42)))
    self.bulkSkip:Show()
    place(self.bulkCounter, { x = w * .3, y = h - h * .06 - 30, w = w * .4, h = 30 }, self.frame)
    W.ApplyStyle(self.bulkCounter, "caption", h)
    self.bulkCounter:SetText(("Pack %d of %d"):format(self.bulkPlay.index, self.bulkPlay.result.packs))
    self.bulkCounter:Show()
  end
  for _, b in ipairs({ self.prevButton, self.nextButton, self.craftButton,
                       self.dustButton, self.packButton, self.classButton }) do
    b:Hide()
  end
  self.progressText:Hide(); self.dustText:Hide(); self.pageText:Hide()
  self.statsPlate:SetShown(false)
  self.deckText:Hide()
end

-- "All Classes" for a neutral card, else the class, as the pack reveal says it
function CollectionUI:PackClassName(cardId)
  local p = ns.PrintedCards[cardId] or {}
  local class = p.class or "NEUTRAL"
  if class == "NEUTRAL" then return "All Classes" end
  return class:sub(1, 1) .. class:sub(2):lower()
end

function CollectionUI:RevealNext()
  if not self.pack then return end
  if self.packRevealed >= #self.pack.cards then
    self:ClosePack()
    return
  end
  for i=1,#self.pack.cards do
    if not (self.revealedCards and self.revealedCards[i]) then return self:RevealCard(i) end
  end
end

function CollectionUI:RevealCard(index)
  if not self.pack then return end
  if self.packRevealed >= #self.pack.cards then return self:ClosePack() end
  self.revealedCards = self.revealedCards or {}
  if self.revealedCards[index] or not self.pack.cards[index] then return end
  self.revealedCards[index]=true; self.packRevealed=self.packRevealed+1
  --[[ The relayout a flip makes must not cancel the reveals already running:
       it did, so turning the next card froze the last one's light half-lit
       and cut its sound. (A resize still cancels -- everything moves.) ]]
  self.keepFX = true
  self:Relayout()
  self.keepFX = nil
  CardWidget.SetFaceDown(self.slots[index].widget, true)
  self:PlayRevealFX(self.pack.cards[index], index)
  --[[ A duplicate is shown for a moment as what it is, then disenchants in
       front of you -- the same crack and dust as the Disenchant button. ]]
  if self.pack.cards[index].dust then
    local pack = self.pack
    -- after the rarity's own glow has had its moment (Choreography.CardReveal)
    local after = ({ EPIC = 1.2, LEGENDARY = 1.7 })[self.pack.cards[index].rarity] or 0.9
    local wait = ns.Timeline.New("PackDuplicate")
    wait:At(after, "dust", function()
      if self.pack == pack then self:DustPackCard(index) end
    end)
    self:Run(wait)
  end
end

function CollectionUI:DustPackCard(index)
  local slot = self.slots and self.slots[index]
  local card = self.pack and self.pack.cards[index]
  if not (slot and card) or self.packDusted[index] then return end
  self.packDusted[index] = true
  local ghost = CardWidget.Acquire(self.effectPool, self.frame)
  local r = slot.widget.rect
  CardWidget.ApplyRect(ghost, r)
  CardWidget.SetDescriptor(ghost, self.resolver:Card(card.cardId))
  ghost.frame:SetFrameLevel(self.frame:GetFrameLevel() + 12)
  ghost.frame:EnableMouse(false)
  local tl = ns.Choreography.Disenchant(self:Stage({ { widget = ghost } }, { cards = { r } }), { cardIndex = 1 })
  tl.cleanup = function()
    ghost.frame:Hide()
    for i, w in ipairs(self.effectPool.used) do
      if w == ghost then table.remove(self.effectPool.used, i); break end
    end
    self.effectPool.free[#self.effectPool.free + 1] = ghost
  end
  self:Run(tl)
  self.keepFX = true
  self:Relayout()
  self.keepFX = nil
end

--[[ The reveal's words -- class, "Duplicate", "+5 Dust" -- on a layer above
     the cards. On the window itself they sat under the card frames, so a
     stamp across a dusted card showed only round its edges ("+ ...st",
     reported with a screenshot). ]]
function CollectionUI:PackTextLayer()
  if not self.packTextLayer then
    self.packTextLayer = CreateFrame("Frame", nil, self.frame)
    self.packTextLayer:SetAllPoints(); self.packTextLayer:EnableMouse(false)
  end
  self.packTextLayer:SetFrameLevel(self.frame:GetFrameLevel() + 16)
  return self.packTextLayer
end

function CollectionUI:ClosePack()
  -- opening several, "done with this pack" is the next one
  if self.bulkPlay then return self:BulkNextPack() end
  self:HidePackLights()
  self.pack = nil
  self.revealedCards = nil
  self.packRevealed = 0
  for _, b in ipairs({ self.prevButton, self.nextButton, self.packButton,
                       self.classButton }) do
    b:Show()
  end
  self.progressText:Show(); self.dustText:Show(); self.pageText:Show()
  self:Relayout()
end

-- ============================================================ the stage

--[[ The choreography stage for this screen.

     The same interface Client/UI/Board.lua provides, so the pack-crack, reveal,
     craft and disenchant sequences -- which were written and tested long before
     this screen existed -- run here unchanged. Every method is optional by
     design, so a missing one degrades to no animation rather than an error. ]]
function CollectionUI:Stage(fixedSlots, fixedLayout, focusIndex)
  local u = self
  local epoch=self.fxEpoch
  local function active() return epoch==u.fxEpoch or (fixedLayout and not fixedLayout.packCards) end
  local generations={}
  for i,slot in ipairs(fixedSlots or {}) do generations[i]=slot.widget.gen end
  local function handleFor(index)
    if index==0 then
      local h={}
      function h:Scale(v) if active() and u.packShell then u.packShell:SetScale(v) end return h end
      function h:Alpha(v)
        if active() and u.packShell then
          u.packShell:SetAlpha(v)
          if v<=0 then u.packShell:Hide() end
        end
        return h
      end
      return h
    end
    local slots = fixedSlots or u.slots
    local slot = slots and slots[index]
    local frame = slot and slot.widget and slot.widget.frame
    local h = {}
    local function valid() return active() and frame and (not fixedSlots or slot.widget.gen==generations[index]) end
    local function rect()
      local layout=fixedLayout or u.L
      return layout and ((layout.packCards or layout.cards or {})[index])
    end
    function h:Pos(x,y)
      if not valid() then return h end
      local r=rect()
      if r then CardWidget.ApplyRect(slot.widget,r) end
      return h
    end
    function h:Scale(s,sy)
      if not valid() then return h end
      local r=rect()
      if r then
        local sx=math.max(.01,s or 1); sy=math.max(.01,sy or sx)
        CardWidget.ApplyRect(slot.widget,{x=r.x+r.w*(1-sx)/2,y=r.y+r.h*(1-sy)/2,w=r.w*sx,h=r.h*sy})
      end
      return h
    end
    function h:Alpha(a) if valid() then frame:SetAlpha(a or 1) end return h end
    -- a pack card's light (u.packFx) belongs to its place in the pack, not
    -- to the widget, so it keeps flaring across the relayout the next flip
    -- makes; anywhere else the widget's own glow is used
    local fx = fixedLayout and fixedLayout.packCards and u.pack and u.packFx and u.packFx[index]
    function h:Glow(r, g, b, a)
      if fx then
        if active() then u:SetPackLight(fx, { r, g, b }, a) end
        return h
      end
      local tex = slot and slot.widget and slot.widget.glow
      if tex and valid() then
        if (a or 0) <= 0 then tex:Hide() else tex:Show(); tex:SetVertexColor(r, g, b, a) end
      end
      return h
    end
    --[[ The sunburst behind an epic or legendary card: swells in, turns
         slowly, fades. `v` runs 0..1 over the beat. ]]
    function h:Rays(r, g, b, v, scale)
      if not (fx and active()) then return h end
      v = math.max(0, math.min(1, v or 0))
      local a = v < 0.15 and v / 0.15 or (1 - v) / 0.85
      if a <= 0 or v >= 1 then fx.rays:Hide(); return h end
      local size = (fx.size or 300) * (scale or 1) * (0.55 + 0.45 * math.min(1, v * 3))
      fx.rays:ClearAllPoints(); fx.rays:SetSize(size, size)
      fx.rays:SetPoint("CENTER", u.frame, "BOTTOMLEFT", fx.cx or 0, fx.cy or 0)
      fx.rays:SetRotation(v * 1.1)
      fx.rays:SetVertexColor(r, g, b, a * 0.9); fx.rays:Show()
      return h
    end
    function h:Flip()
      if valid() and slot.card then
        CardWidget.SetFaceDown(slot.widget,false)
        CardWidget.SetDescriptor(slot.widget,u.resolver:Card(slot.card.cardId))
      end
      return h
    end
    function h:Rot() return h end
    function h:Burst() return h end
    return h
  end

  return {
    Card = function(_, i) return handleFor(i) end,
    Screen = function()
      local h = {}
      function h:Shake(amount)
        if active() then
          u.shake=u.shake or W.NewShake(u.frame)
          W.Shake(u.shake,math.min(5,amount or 0))
        end
        return h
      end
      function h:Vignette(alpha)
        if active() then
          u.vignette=u.vignette or W.NewVignette(u.frame)
          W.SetVignette(u.vignette,alpha)
        end
        return h
      end
      return h
    end,
    --[[ A pack opening in silence is the one place silence is NOT acceptable --
         the rising five-note escalation across the reveals is most of what
         makes it an event (docs/06). Client/FX/Sounds resolves the keys through
         the client's own SOUNDKIT table; a name this client lacks still falls
         back to quiet. ]]
    Sound = function(_, key, step) if active() then ns.Sounds.Play(key, step) end end,
    Particles = function(_, kind, x, y, n)
      if not active() then return end
      local f = u.frame
      local r = fixedLayout and (fixedLayout.packCards or fixedLayout.cards or {})[focusIndex or (not fixedLayout.packCards and 1 or 0)]
      W.Burst(u.particles, kind, (r and r.x + r.w / 2 or f:GetWidth() / 2) + (x or 0),
              (r and r.y + r.h / 2 or f:GetHeight() / 2) + (y or 0), n or 12)
    end,
    Toast = function()
      local h = {}
      return setmetatable(h, { __index = function() return function() return h end end })
    end,
  }
end

--[[ Run a timeline. One OnUpdate drives every animation on this screen; the
     timelines themselves are pure data with a Tick, which is why the feel of
     the pack opening could be designed and tested before this file existed. ]]
-- Navigation and resizing finish cosmetic work immediately. Stored rewards and
-- revealed-card state are independent from timelines, so nothing can be lost.
function CollectionUI:StopFX(preserveCopies)
  if preserveCopies and self.keepFX then return end
  self.fxEpoch=(self.fxEpoch or 0)+1
  local keep={}
  for _,t in ipairs(self.running or {}) do
    if preserveCopies and t.cleanup then keep[#keep+1]=t
    elseif t.cleanup then t.cleanup(); t.cleanup=nil end
  end
  self.running=keep
  if self.fxFrame and #keep==0 then self.fxFrame:SetScript("OnUpdate",nil) end
  if self.particles then W.ClearParticles(self.particles) end
  if self.shake then W.TickShake(self.shake,1) end
  if self.vignette then W.SetVignette(self.vignette,0) end
  if self.packShell then self.packShell:Hide() end
end

function CollectionUI:Run(tl)
  if not tl then return end
  self.running = self.running or {}
  self.running[#self.running + 1] = tl
  tl:Start()
  if not self.fxFrame then self.fxFrame = CreateFrame("Frame", nil, self.frame) end
  self.fxFrame:SetScript("OnUpdate", function(_, dt)
    local list, alive, kept = self.running, {}, {}
    for _, t in ipairs(list) do
      if t:Tick(dt) then alive[#alive + 1] = t; kept[t] = true
      elseif t.cleanup then t.cleanup(); t.cleanup = nil end
    end
    --[[ A timeline can start new ones while it ticks -- the next pack of a
         bulk opening is begun from the last one's timeline -- and a relayout
         in between swaps self.running for a fresh list. Those were dropped
         when this list replaced it, so pack 2 froze half-cracked
         (reported: "just does one"). Keep whatever was started meanwhile. ]]
    if self.running ~= list then
      for _, t in ipairs(self.running) do
        if not kept[t] then alive[#alive + 1] = t; kept[t] = true end
      end
    end
    self.running = alive
    local particles = W.TickParticles(self.particles, dt)
    --[[ Stop when NOTHING is moving, particles included. An OnUpdate left
         running for an empty list is the commonest way an addon costs frames. ]]
    local shaking=self.shake and W.TickShake(self.shake,dt)
    if #alive == 0 and particles == 0 and not shaking then self.fxFrame:SetScript("OnUpdate", nil) end
  end)
end

function CollectionUI:PlayPackFX(pack)
  if not self.packShell then
    self.packShell=CreateFrame("Frame",nil,self.frame)
    self.packShell:SetFrameLevel(220)
    local art=self.packShell:CreateTexture(nil,"ARTWORK")
    art:SetAllPoints(); art:SetTexture("Interface\\AddOns\\ForeverHearthstone\\Art\\menu-pack.tga")
  end
  self.packShell:ClearAllPoints(); self.packShell:SetPoint("CENTER",self.frame,"CENTER")
  self.packShell:SetSize(self.frame:GetHeight()*.27,self.frame:GetHeight()*.37)
  self.packShell:SetScale(1); self.packShell:SetAlpha(1); self.packShell:Show()
  for _,slot in ipairs(self.slots) do slot.widget.frame:SetAlpha(0) end
  self:Run(ns.Choreography.PackCrack(self:Stage(self.slots,self.L), {
    count = #pack.cards, bestRarity = pack.bestRarity, tellIndex = pack.tellIndex,
  }))
end

function CollectionUI:PlayRevealFX(card, step)
  local fx = self.packFx and self.packFx[step]
  if fx then fx.until_ = GetTime() + 2.2 end   -- the flare outlives the next relayout
  self:Run(ns.Choreography.CardReveal(self:Stage(self.slots,self.L,step), {
    cardIndex = step, rarity = card.rarity, golden = card.golden, step = step,
  }))
end

function CollectionUI:PlayCraftFX(entry)
  self:PlaySelectedFX(entry, ns.Choreography.Craft)
end

function CollectionUI:PlayDisenchantFX(entry)
  self:PlaySelectedFX(entry, ns.Choreography.Disenchant)
end

-- Animate a separate copy at the selected card's position. Refreshing or
-- scrolling the grid must never redirect an effect onto a recycled widget.
function CollectionUI:PlaySelectedFX(entry, sequence)
  for _, slot in ipairs(self.slots or {}) do
    if slot.entry and slot.entry.cardId == entry.cardId then
      local ghost = CardWidget.Acquire(self.effectPool, self.frame)
      local r = slot.widget.rect
      CardWidget.ApplyRect(ghost, r)
      CardWidget.SetDescriptor(ghost, self.resolver:Card(entry.cardId))
      ghost.frame:SetFrameLevel(200)
      ghost.frame:EnableMouse(false)
      local stage = self:Stage({ { widget = ghost } }, { cards = { r } })
      local tl = sequence(stage, { cardIndex = 1 })
      tl.cleanup = function()
        ghost.frame:Hide()
        for i, w in ipairs(self.effectPool.used) do
          if w == ghost then table.remove(self.effectPool.used, i); break end
        end
        self.effectPool.free[#self.effectPool.free + 1] = ghost
      end
      self:Run(tl)
      return
    end
  end
end

return CollectionUI
