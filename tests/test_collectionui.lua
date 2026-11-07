--[[ tests/test_collectionui.lua -- the out-of-match app.

  Two halves, the same split as the board:

    * the LAYOUT is pure arithmetic, so it is swept across window sizes and
      asserted exactly -- does the grid fit, does the deck panel overlap the
      cards, do five pack cards stay inside a small window.
    * the FRAMES run against the strict stub, which errors on any API that is
      not on the Mainline surface, so building the screen at all proves the
      calls are real.

  What neither can prove is that it LOOKS right. That needs the client.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local SIZES = {
  { 760, 560 }, { 800, 600 }, { 1024, 768 }, { 1280, 720 },
  { 1440, 900 }, { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 },
}

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w
     and a.y < b.y + b.h and b.y < a.y + a.h
end

local function inside(outer, r, slack)
  slack = slack or 0.5
  return r.x >= -slack and r.y >= -slack
     and r.x + r.w <= outer.w + slack and r.y + r.h <= outer.h + slack
end

--============================================================ layout

H.suite("collection ui: every element stays inside the window at any size", function(ns, H)
  local CL = ns.CollectionLayout
  for _, size in ipairs(SIZES) do
    for _, deckOpen in ipairs({ false, true }) do
      local L = CL.Compute({ w = size[1], h = size[2], deckOpen = deckOpen, selected = true })
      local win = { x = 0, y = 0, w = size[1], h = size[2] }
      for _, key in ipairs({ "header", "footer", "grid", "progress", "dust",
                             "prevPage", "nextPage", "openPack", "classTab" }) do
        H.ok(inside(win, L[key]), ("%s fits at %dx%d"):format(key, size[1], size[2]))
      end
      for i, r in ipairs(L.cards) do
        H.ok(inside(win, r), ("card %d fits at %dx%d"):format(i, size[1], size[2]))
      end
    end
  end
end)

H.suite("collection ui: the grid never overlaps the header, footer or deck list", function(ns, H)
  local CL = ns.CollectionLayout
  for _, size in ipairs(SIZES) do
    local L = CL.Compute({ w = size[1], h = size[2], deckOpen = true, selected = true })
    for i, r in ipairs(L.cards) do
      H.notOk(overlaps(r, L.header), ("card %d clear of the header at %dx%d"):format(i, size[1], size[2]))
      H.notOk(overlaps(r, L.footer), ("card %d clear of the footer at %dx%d"):format(i, size[1], size[2]))
      H.notOk(overlaps(r, L.deckPanel), ("card %d clear of the deck list at %dx%d"):format(i, size[1], size[2]))
    end
  end
end)

H.suite("collection ui: cards never overlap each other", function(ns, H)
  local CL = ns.CollectionLayout
  for _, size in ipairs(SIZES) do
    local L = CL.Compute({ w = size[1], h = size[2] })
    for i = 1, #L.cards do
      for j = i + 1, #L.cards do
        H.notOk(overlaps(L.cards[i], L.cards[j]),
                ("cards %d and %d are separate at %dx%d"):format(i, j, size[1], size[2]))
      end
    end
  end
end)

H.suite("collection ui: a card keeps its aspect ratio everywhere", function(ns, H)
  --[[ A stretched card is the single most obvious way a card game looks cheap,
       and it is the failure a solver exists to make impossible. ]]
  local CL = ns.CollectionLayout
  local want = CL.design.CARD_W_OVER_H
  for _, size in ipairs(SIZES) do
    local L = CL.Compute({ w = size[1], h = size[2] })
    for _, r in ipairs(L.cards) do
      local ratio = r.w / r.h
      H.ok(math.abs(ratio - want) < 0.02,
           ("aspect %.3f at %dx%d"):format(ratio, size[1], size[2]))
    end
  end
end)

H.suite("collection ui: a bigger window shows more cards, not bigger ones forever", function(ns, H)
  local CL = ns.CollectionLayout
  local small = CL.Compute({ w = 800, h = 600 })
  local big   = CL.Compute({ w = 2560, h = 1440 })
  H.ok(big.pageSize >= small.pageSize,
       ("%d slots at 800x600, %d at 2560x1440"):format(small.pageSize, big.pageSize))
  H.ok(small.pageSize >= CL.design.MIN_COLS * CL.design.MIN_ROWS,
       "even the smallest window shows a usable page")
end)

H.suite("collection ui: a card never shrinks below the legibility floor", function(ns, H)
  --[[ Without this the solver happily picks the shape with the MOST cards --
       eight columns by four rows at any size -- and the smallest window becomes
       32 unreadable slivers. The floor is what makes "as many as fit" mean "as
       many as fit and can still be read". ]]
  local CL = ns.CollectionLayout
  for _, size in ipairs(SIZES) do
    local L = CL.Compute({ w = size[1], h = size[2], deckOpen = true })
    for _, r in ipairs(L.cards) do
      H.ok(r.w >= CL.design.MIN_CARD_W,
           ("card is %.0fpx wide at %dx%d, floor is %d")
           :format(r.w, size[1], size[2], CL.design.MIN_CARD_W))
    end
  end
end)

H.suite("collection ui: five pack cards fit in the narrowest window", function(ns, H)
  --[[ They shrink rather than overlap. An overlapping reveal hides the art,
       which is the entire point of the moment. ]]
  local CL = ns.CollectionLayout
  for _, size in ipairs(SIZES) do
    local L = CL.Compute({ w = size[1], h = size[2], packOpening = true, packCount = 5 })
    H.eq(#L.packCards, 5, "five slots")
    local win = { x = 0, y = 0, w = size[1], h = size[2] }
    for i, r in ipairs(L.packCards) do
      H.ok(inside(win, r), ("pack card %d fits at %dx%d"):format(i, size[1], size[2]))
      for j = i + 1, 5 do
        H.notOk(overlaps(r, L.packCards[j]), "pack cards do not overlap")
      end
    end
  end
end)

H.suite("collection ui: pack opening takes the whole screen", function(ns, H)
  local CL = ns.CollectionLayout
  local L = CL.Compute({ w = 1280, h = 720, packOpening = true, packCount = 5 })
  H.eq(L.mode, "PACK", "in pack mode")
  H.eq(L.cards, nil, "there is no browsing grid competing with it")
  H.eq(L.deckPanel, nil, "and no deck list")
end)

H.suite("collection ui: paging arithmetic follows the page size", function(ns, H)
  local CL = ns.CollectionLayout
  H.eq(CL.PageCount(0, 24), 1, "an empty collection is still one page")
  H.eq(CL.PageCount(24, 24), 1, "exactly one page")
  H.eq(CL.PageCount(25, 24), 2, "one over spills")
  H.eq(CL.PageOf(25, 24), 2, "and card 25 is on page 2")
  H.eq(CL.PageOf(1, 24), 1, "card 1 is on page 1")
end)

H.suite("collection ui: hit-testing finds the slot under a point", function(ns, H)
  local CL = ns.CollectionLayout
  local L = CL.Compute({ w = 1280, h = 720 })
  local r = L.cards[3]
  H.eq(CL.SlotAt(L, r.x + r.w / 2, r.y + r.h / 2), 3, "the middle of card 3 is card 3")
  H.eq(CL.SlotAt(L, -50, -50), nil, "outside the window is nothing")
end)

--============================================================ browsing

H.suite("collection ui: browsing is sorted by cost, like Hearthstone", function(ns, H)
  local c = ns.Collection.New({}, { class = "MAGE" })
  c:GrantForLevel("MAGE", 60)
  local list = c:Browse({})
  H.ok(#list > 30, ("browsing shows %d cards"):format(#list))
  local last = -1
  for _, e in ipairs(list) do
    H.ok((e.printed.cost or 0) >= last, "costs never go backwards")
    last = e.printed.cost or 0
  end
end)

H.suite("collection ui: the default view is what you OWN", function(ns, H)
  local c = ns.Collection.New({}, { class = "MAGE" })
  c:GrantForLevel("MAGE", 1)
  for _, e in ipairs(c:Browse({})) do
    H.ok(e.owned + e.golden > 0, e.cardId .. " is owned")
  end
  local all = c:Browse({ all = true })
  H.ok(#all > #c:Browse({}), "and the crafting view shows the whole set")
end)

H.suite("collection ui: the deck-builder view hides what cannot go in the deck", function(ns, H)
  local c = ns.Collection.New({}, { class = "MAGE" })
  c:GrantForLevel("MAGE", 60)
  for _, e in ipairs(c:Browse({ playable = "MAGE", all = true })) do
    H.ok(e.printed.class == "MAGE" or e.printed.class == "NEUTRAL",
         e.cardId .. " is playable by a Mage")
  end
end)

H.suite("collection ui: search matches name and text", function(ns, H)
  local c = ns.Collection.New({}, { class = "MAGE" })
  local hits = c:Browse({ all = true, text = "fireball" })
  local found = false
  for _, e in ipairs(hits) do if e.cardId == "CS2_029" then found = true end end
  H.ok(found, "searching for fireball finds Fireball")

  local taunts = c:Browse({ all = true, text = "taunt" })
  H.ok(#taunts > 10, ("and searching text finds %d Taunt cards"):format(#taunts))
end)

H.suite("collection ui: an entry knows whether it can be crafted", function(ns, H)
  local c = ns.Collection.New({}, { class = "MAGE" })
  local function find(list, id)
    for _, e in ipairs(list) do if e.cardId == id then return e end end
  end
  local poor = find(c:Browse({ all = true }), "EX1_116")     -- Leeroy, 1600 dust
  H.notOk(poor.canCraft, "not with no dust")
  c.account.dust = 99999
  local rich = find(c:Browse({ all = true }), "EX1_116")
  H.ok(rich.canCraft, "yes with plenty")
  local basic = find(c:Browse({ all = true }), "CS2_182")    -- Chillwind Yeti, Basic
  H.notOk(basic.craftable, "and a Basic card is never craftable, whatever the dust")
end)

--============================================================ the frames

local WOW_FILES = {
  "ForeverHearthstone/Client/Net/Transport.lua",
  "ForeverHearthstone/Client/Rewards.lua",
  "ForeverHearthstone/Client/UI/Widgets.lua",
  "ForeverHearthstone/Client/UI/Board.lua",
  "ForeverHearthstone/Client/UI/Collection.lua",
  "ForeverHearthstone/Client/Main.lua",
}

local function withUI(ns, fn, opts)
  opts = opts or {}
  Stub.Install(_G)
  Stub.resting = false
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = opts.level or 60 } }
  _G.ForeverHearthstoneDB = {}
  _G.ForeverHearthstoneCharDB = {}
  for _, path in ipairs(WOW_FILES) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  ns.Main.collectionUI = nil
  ns.Main.collection = nil
  ns.Main.rewards = nil
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  return fn(ns.Main, ns)
end

H.suite("collection ui: the screen builds without touching a missing API", function(ns, H)
  --[[ The most valuable assertion in the frame half. The stub errors on any
       unmodelled method, so simply constructing the window proves every call it
       makes exists on the Mainline surface -- including SetResizeBounds rather
       than the removed SetMinResize. ]]
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    H.ok(ui and ui.frame, "the window exists")
    H.ok(ui:IsShown(), "and is on screen")
    H.ok(Stub.Count("SetResizeBounds") >= 1, "sized with the Mainline call")
  end)
end)

H.suite("collection ui: wheel scrolling and page controls share the same position", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection()
    local entries = ui:Entries()
    local cols = ui.L.cols
    ui.frame:GetScript("OnMouseWheel")(ui.frame, -1)
    H.eq(ui.scrollRow, 1, "one wheel notch advances one row")
    H.eq(ui.slots[1].entry.cardId, entries[cols + 1].cardId, "correct first card")
    H.ok(ui.prevButton:IsShown(), "previous page available")
    H.ok(ui.nextButton:IsShown(), "next page available")
    H.notOk(overlaps(ui.L.prevPage,ui.L.pageText),"previous arrow does not cover the counter")
    H.notOk(overlaps(ui.L.nextPage,ui.L.pageText),"next arrow does not cover the counter")
    ui:Scroll(9999)
    H.eq(ui.scrollRow, ui.maxScrollRow, "bottom clamped")
    ui:Scroll(-9999)
    H.eq(ui.scrollRow, 0, "top clamped")
    ui:OnCardClick(ui.slots[1].entry, "LeftButton")
    for _, key in ipairs({ "pageText", "craft", "disenchant" }) do
      H.notOk(overlaps(ui.L.openPack, ui.L[key]), "pack button clear of " .. key)
    end
    ui:CycleFilter()
    H.eq(ui.scrollRow, 0, "filter starts at top")
    ui.closeButton:GetScript("OnClick")()
    H.notOk(ui:IsShown(), "collection closes")
  end)
end)

H.suite("collection ui: disenchant effect stays on selected card after recycling", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection()
    ui.collection:Add("EX1_116", 1)
    ui:Relayout()
    local entries = ui:Entries()
    local index
    for i, entry in ipairs(entries) do if entry.cardId == "EX1_116" then index = i end end
    ui:Scroll(math.max(0, math.floor((index - 2) / ui.L.cols)))
    local chosen
    for i, slot in ipairs(ui.slots) do
      if slot.entry.cardId == "EX1_116" then chosen = slot; H.ok(i > 1, "not first slot") end
    end
    H.ok(chosen, "selected card is visible")
    local r = chosen.widget.rect
    ui:OnCardClick(chosen.entry, "LeftButton")
    ui:DisenchantSelected()
    H.eq(ui.collection:Count("EX1_116"),1,"confirmation is required")
    ui.disenchantDialog.confirm:Click()
    H.eq(ui.collection:Count("EX1_116"), 0, "last copy removed")
    local ghost = ui.effectPool.used[1]
    H.ok(ghost, "independent effect copy")
    H.eq(ghost.descriptor.cardId, "EX1_116", "effect displays selected card")
    H.eq(ghost.rect.x, r.x, "effect starts at selected x")
    H.eq(ghost.rect.y, r.y, "effect starts at selected y")
    ui:Scroll(-9999)
    H.eq(ghost.descriptor.cardId, "EX1_116", "scroll cannot redirect it")
    for _, slot in ipairs(ui.slots) do
      H.notOk(slot.widget == ghost, "ghost is not a recycled grid slot")
      H.eq(slot.widget.frame:GetAlpha(), 1, "unrelated cards remain opaque")
    end
    ui.fxFrame:GetScript("OnUpdate")(ui.fxFrame, 10)
    H.eq(#ui.effectPool.used, 0, "effect copy returned to pool")
    H.notOk(ghost.frame:IsShown(), "no lingering ghost")
  end)
end)

H.suite("collection ui: Basic disenchant is disabled and harmless", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection()
    ui.filter = { text = "Chillwind Yeti" }
    ui:Relayout()
    ui:OnCardClick(ui.slots[1].entry, "LeftButton")
    local before, dust = ui.collection:Count("CS2_182"), ui.collection:Dust()
    ui:DisenchantSelected()
    H.eq(ui.collection:Count("CS2_182"), before, "starter retained")
    H.eq(ui.collection:Dust(), dust, "no free dust")
    H.eq(#ui.effectPool.used, 0, "no false animation")
  end)
end)

H.suite("collection ui: widgets are POOLED across page turns", function(ns, H)
  -- WoW cannot destroy a frame. Browsing 500 cards must not create 500 frames
  -- per page turn.
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    local after1 = Stub.CountFrames()
    for _ = 1, 6 do ui:TurnPage(1) end
    local after2 = Stub.CountFrames()
    H.eq(after2, after1, "six page turns created no new frames")
  end)
end)

H.suite("collection ui: resizing reflows rather than breaking", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    for _, size in ipairs({ { 800, 600 }, { 1920, 1080 }, { 1024, 768 } }) do
      ui.frame:SetSize(size[1], size[2])
      H.ok(ui.L.pageSize > 0, ("a page still has slots at %dx%d"):format(size[1], size[2]))
    end
  end)
end)

H.suite("collection ui: crafting from the screen spends dust and keeps the page", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection.account.dust = 5000
    ui.filter = { all = true }
    ui:Relayout()
    local entry
    for _, e in ipairs(ui:Entries()) do
      if e.canCraft and e.owned == 0 then entry = e break end
    end
    H.ok(entry, "found something worth crafting")
    ui.selected = entry
    ui:CraftSelected()
    H.ok(Main.collection:Count(entry.cardId) > 0, "the card is now owned")
    H.ok(Main.collection:Dust() < 5000, "and dust was spent")
    H.eq(ui.selected, nil, "the stale selection was dropped, not kept")
  end)
end)

H.suite("collection ui: the deck builder refuses an illegal card and says why", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    local deck, index = Main.collection:NewDeck("Test", "MAGE")
    ui:EditDeck(index)

    ui:AddToDeck("CS2_182")                    -- Chillwind Yeti, owned x2
    ui:AddToDeck("CS2_182")
    H.eq(#deck.cards, 2, "two copies went in")
    local before = #Stub.R.chat
    ui:AddToDeck("CS2_182")
    H.eq(#deck.cards, 2, "a third did not")
    H.ok(#Stub.R.chat > before, "and the player was told why")

    ui:RemoveFromDeck("CS2_182")
    H.eq(#deck.cards, 1, "right-clicking takes one back out")
  end)
end)

H.suite("collection ui: a card with no copy left to add greys out in the deck builder", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    local deck, index = Main.collection:NewDeck("Test", "MAGE")
    ui:EditDeck(index)
    local function slotFor(id)
      for _, slot in ipairs(ui.slots) do if slot.entry.cardId == id then return slot end end
    end
    local id
    for _, slot in ipairs(ui.slots) do
      if Main.collection:Count(slot.entry.cardId) > 0 then id = slot.entry.cardId; break end
    end
    H.ok(id, "an owned card is on the page")
    H.notOk(slotFor(id).widget.ghost, "it starts in full colour")
    local room = math.min(Main.collection:Count(id), Main.collection:MaxCopies(id))
    for _ = 1, room - 1 do ui:AddToDeck(id) end
    if room > 1 then H.notOk(slotFor(id).widget.ghost, "a copy still to add keeps it in colour") end
    ui:AddToDeck(id)
    H.ok(slotFor(id).widget.ghost, "the last copy in the deck greys it out")
    ui:RemoveFromDeck(id)
    H.notOk(slotFor(id).widget.ghost, "taking one back out restores it")
    ui:EditDeck(nil)
    H.notOk(slotFor(id) and slotFor(id).widget.ghost, "browsing outside a deck never greys an owned card")
  end)
end)

H.suite("collection ui: a deck is only duelled with once it is legal", function(ns, H)
  withUI(ns, function(Main, ns)
    local deck, index = Main.collection:NewDeck("Half", "MAGE")
    deck.cards = { "CS2_182" }
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("deck use " .. index)
    H.eq(Main.collection.character.activeDeck, 1, "invalid choice preserves the default deck")
    H.ok(table.concat(Stub.R.chat, " "):find("not legal"), "and it says so")

    --[[ The duel deck falls back to the Basic deck rather than refusing to
         start. A duel that will not begin because of a deck problem is a far
         worse experience than one that begins with the starter deck. ]]
    local cards = Main:CurrentDeck("MAGE")
    H.eq(#cards, ns.RULES.DECK_SIZE, "and duelling still gets a legal 30 cards")
  end)
end)

H.suite("collection ui: opening a pack takes over the screen, then gives it back", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("CLASSIC", 1)
    ui:OpenPack("CLASSIC")
    H.ok(ui.pack, "a pack is open")
    H.eq(ui.L.mode, "PACK", "and the screen belongs to it")
    H.eq(#ui.slots, ns.Packs.SIZE, "five cards are on the table")

    for i = 1, ns.Packs.SIZE do
      ui:RevealNext()
      H.eq(ui.packRevealed, i, "revealed " .. i)
    end
    ui:RevealNext()
    H.eq(ui.pack, nil, "one more click closes it")
    H.ok(ui.L.cards, "and the browsing grid is back")
  end)
end)

H.suite("collection ui: a pack card's light -- hover, reveal, golden", function(ns, H)
  --[[ THE REPORT: the rarity background looked like a placeholder (the card
       front's outline glow, stretched into a gold block), and a card flashed
       by itself. Now: a soft card-shaped light, only on hover while face down;
       a flare (and rays for epic/legendary) as it turns; nothing after,
       except a golden card's gold. ]]
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("CLASSIC", 1)
    ui:OpenPack("CLASSIC")
    ui.pack.cards[2].rarity, ui.pack.cards[2].golden = "LEGENDARY", false
    ui.pack.cards[4].rarity, ui.pack.cards[4].golden = "COMMON", true
    ui.pack.cards[5].rarity, ui.pack.cards[5].golden = "EPIC", false
    Stub.Advance(1.5)
    for i = 1, 5 do
      H.notOk(ui.packFx[i].aura:IsShown(), "card " .. i .. " is dark until the pointer is on it")
      H.notOk(ui.slots[i].widget.glow:IsShown(), "and the old outline block is never used")
    end
    local legendary = ui.slots[2].widget.frame
    local before = #Stub.R.sounds
    legendary:GetScript("OnEnter")(legendary)
    local aura = ui.packFx[2].aura
    H.ok(aura:IsShown(), "hovering a face-down card lights it")
    H.ok(aura.colour[1] > .9 and aura.colour[3] < .3, "in the legendary's orange")
    H.ok(aura.texture:find("fx-aura", 1, true), "with the soft card-shaped light")
    H.eq(#Stub.R.sounds, before + 1, "and its rarity's sound")
    legendary:GetScript("OnLeave")(legendary)
    H.notOk(aura:IsShown(), "leaving it puts the light out")
    legendary:GetScript("OnEnter")(legendary); legendary:GetScript("OnLeave")(legendary)
    H.eq(#Stub.R.sounds, before + 2, "the second hover is only the ordinary hover sound")

    ui:RevealCard(2); Stub.Advance(0.5)
    H.ok(ui.packFx[2].rays:IsShown(), "a legendary throws rays as it turns")
    ui:RevealCard(5); Stub.Advance(0.05)
    H.ok(ui.packFx[2].aura:IsShown() or ui.packFx[2].rays:IsShown(),
         "and flipping the next card does not cut its light off")
    Stub.Advance(3)
    H.notOk(ui.packFx[2].aura:IsShown() or ui.packFx[2].rays:IsShown(), "then it fades, leaving nothing")
    ui:RevealCard(4); Stub.Advance(3)
    H.ok(ui.packFx[4].aura:IsShown(), "a golden card keeps a soft gold light")
    ui:RevealCard(1); ui:RevealCard(3); Stub.Advance(3)
    ui:RevealNext()
    for i = 1, 5 do H.notOk(ui.packFx[i].aura:IsShown(), "closing the pack puts every light out") end
  end)
end)

H.suite("collection ui: opening a pack makes a noise, and the reveals escalate", function(ns, H)
  --[[ A pack opening in silence is the one place silence is not acceptable --
       the rising five-note escalation across the reveals is most of what makes
       it an event rather than five cards appearing. ]]
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("CLASSIC", 1)
    local before = #Stub.R.sounds
    ui:OpenPack("CLASSIC")
    Stub.Advance(1.0)
    H.ok(#Stub.R.sounds > before, "the pack cracked audibly")

    local heard = {}
    for i = 1, ns.Packs.SIZE do
      ui:RevealNext()
      Stub.Advance(0.5)
      heard[#heard + 1] = Stub.R.sounds[#Stub.R.sounds]
    end
    local distinct = {}
    for _, snd in ipairs(heard) do if snd then distinct[snd.id or snd.file] = true end end
    local n = 0
    for _ in pairs(distinct) do n = n + 1 end
    H.ok(n >= 2, ("the five reveals were not all the same sound (%d distinct)"):format(n))
  end)
end)

H.suite("collection ui: the fx loop stops when nothing is moving", function(ns, H)
  --[[ An OnUpdate left running for an empty list is the commonest way an addon
       quietly costs frames for the rest of a session. ]]
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("CLASSIC", 1)
    ui:OpenPack("CLASSIC")
    H.ok(ui.fxFrame:GetScript("OnUpdate"), "it runs while the pack opens")
    Stub.Advance(6.0)
    H.eq(ui.fxFrame:GetScript("OnUpdate"), nil, "and stops itself afterwards")
  end)
end)

H.suite("collection ui: the pack reveal runs its choreography here too", function(ns, H)
  --[[ The pack-crack and reveal sequences were written and tested in
       Client/FX long before this screen existed. They run here unchanged
       because this screen provides the same stage interface the board does. ]]
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("GVG", 1)
    ui:OpenPack("GVG")
    H.ok(ui.running and #ui.running > 0, "a timeline is running")
    local ok, err = pcall(function() Stub.Advance(4.0) end)
    H.ok(ok, "and it runs to completion against the real widgets: " .. tostring(err))
  end)
end)

H.suite("collection ui: the icon audit records a human's verdict", function(ns, H)
  --[[ The only verifier this class of data can have is an eye. What the addon
       can do is make using one cheap and then never forget the answer. ]]
  withUI(ns, function(Main, ns)
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("icons")
    H.ok(table.concat(Stub.R.chat, " "):find("icon audit"), "the audit printed")

    _G.SlashCmdList["FOREVERHEARTHSTONE"]("icons blank race_beast")
    H.eq(_G.ForeverHearthstoneDB.art.blank.RACE_BEAST, true, "the verdict was saved")
    local beast = Main.resolver:Card("CS2_172")
    H.eq(Main.resolver:GenericIcon(ns.PrintedCards.CS2_172), ns.GenericArt.CANDIDATES.MINION,
         "the generic fallback changed immediately")
    H.eq(beast.icon, ns.HearthstoneArt.CS2_172, "bundled illustration stays preferred")
  end)
end)

H.suite("collection ui: slash fh opens the hub without starting a match", function(ns,H)
  withUI(ns,function(Main)
    local before=Main.game
    SlashCmdList.FOREVERHEARTHSTONE("")
    H.ok(Main.hub:IsShown())
    H.eq(Main.game,before,"opening the menu does not replace the current game")
    local ui=Main:Collection()
    local entry=ui:Entries()[1]
    H.ok(entry)
    ui:OnCardClick(entry,"RightButton")
    H.ok(ui.inspect.frame:IsShown(),"right-click opens the shared card inspection")
    H.eq(ui.inspect.card.descriptor.id,ui.resolver:Card(entry.cardId).id)
    ui.frame:SetSize(1300,800)
    H.ok(ui.inspect.frame:IsShown(),"inspection survives resize")
  end)
end)

H.suite("collection ui: practice opponents show their class names without a resize",function(ns,H)
  --[[ THE REPORT: "the class names don't appear for playing against a bot
       until I resize the window". The tiles are sized on the main menu while
       hidden, and the client does not reliably send OnSizeChanged to a hidden
       frame, so the name strip (sized only there) stayed zero-sized. Here
       OnSizeChanged never reaches the tiles at all, as in the worst case. ]]
  withUI(ns,function(Main)
    Main:ShowHub(); Stub.Advance(.4)
    local hub=Main.hub
    for _,tile in ipairs(hub.tiles) do
      tile:SetScript("OnSizeChanged",nil)
      tile.classLabel:SetSize(0,0)
      rawset(tile.text,"font",nil)   -- as if its font never took
    end
    hub.buttons[1]:Click()   -- Play Bots
    for _,tile in ipairs(hub.tiles) do
      H.ok(tile:IsShown(),tile.class.." is offered")
      H.ok(tile.classLabel:GetWidth()>0 and tile.classLabel:GetHeight()>0,tile.class.."'s name strip has a size")
      H.ok(tile.text:IsShown() and tile.text:GetText()~="",tile.class.." is named")
      H.eq(tile.text:GetFont(),ns.Fonts.TITLE,tile.class.."'s name is set in the title font")
    end
  end)
end)

H.suite("collection ui: hub resizes and bot selection waits for Play",function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub()
    local hub=Main.hub
    H.ok(hub:IsResizable())
    H.ok(hub:GetScript("OnUpdate"),"visible cabinet animates its entrance and lights")
    Stub.Advance(.4)
    H.eq(hub:GetAlpha(),1,"entrance finishes fully opaque")
    hub:SetSize(800,600)
    H.notOk(hub.homeButton:IsShown(),"the main menu has no Main Menu button")
    hub.buttons[1]:Click()
    H.ok(hub.play:IsShown())
    H.ok(hub.homeButton:IsShown(),"practice has Main Menu, in the corner")
    H.notOk(hub.buttons[6]:IsShown(),"and its close is the corner's too")
    hub.homeButton:Click()
    H.notOk(hub.play:IsShown(),"Main Menu restores the main menu")
    H.ok(hub.buttons[2]:IsShown(),"collection is available again")
    hub.buttons[1]:Click()
    hub.tiles[3]:Click()
    hub.tiles[2]:GetScript("OnLeave")(); hub.tiles[2]:SetEnabledLook(true)   -- both repaint the label
    H.ok(select(1,hub.tiles[2].text:GetTextColor())>.9,"an opponent's name stays light after hovering it")
    H.eq(Main.game,nil,"selection must not start a match")
    local chosen=hub.selectedClass
    hub.play:Click(); hub.play:Click()
    H.eq(Main.game,nil,"a double click on Choose Deck does not start a game")
    H.ok(hub.selectedDeck,"the book opens on a deck already chosen, as Hearthstone's does")
    H.ok(hub.play.enabled,"so Play is one click away")
    Stub.Advance(.5)
    hub.deckChoices[1]:Click(); hub.play:Click()
    H.eq(Main.game.players[2].class,chosen)
    H.notOk(hub:IsShown())
    H.eq(hub:GetScript("OnUpdate"),nil,"hidden cabinet stops all ambient animation")
  end)
end)

H.suite("collection ui: the difficulty slider picks the bot's deck and how well it plays",function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub()
    local hub=Main.hub
    hub:SetSize(1280,720)
    hub.buttons[1]:Click()                                   -- Play Bots
    local slider=hub.diffSlider
    H.ok(slider:IsVisible(),"the difficulty sits on the practice stage")
    H.eq(Main:BotDifficulty(),ns.AI.DEFAULT_DIFFICULTY,"a new install starts at the default")
    H.ok(hub.diffName:GetText():find(ns.AI.DIFFICULTIES[ns.AI.DEFAULT_DIFFICULTY].name),"and names it")
    for _=1,4 do slider:GetScript("OnMouseWheel")(slider,1) end
    H.eq(Main:BotDifficulty(),5,"the wheel steps it up, and stops at Master")
    H.eq(ForeverHearthstoneDB.botDifficulty,5,"saved for the account")
    H.ok(hub.diffName:GetText():find("Master"),"the label follows")
    H.eq(hub.diffBlurb:GetText(),ns.AI.DIFFICULTIES[5].blurb,"with what it means")
    -- a click on the first notch, through the real pointer path
    Stub.CursorOver(slider,12,11)
    slider:GetScript("OnMouseDown")(slider,"LeftButton")
    slider:GetScript("OnMouseUp")(slider,"LeftButton")
    H.eq(Main:BotDifficulty(),1,"clicking the first notch picks Novice")

    Main:SetBotDifficulty(5)
    Main:StartPractice("MAGE","WARRIOR")
    H.eq(Main.botDeck.class,"WARRIOR","the bot brings a deck of its own class")
    H.eq(Main.botDeck.tier,5,"a Master's deck")
    H.eq(Main.botOpts.difficulty,5,"and plays it as a Master")
    H.eq(Main.botOpts.style,Main.botDeck.style,"in the deck's own style")
    local want,have={},{}
    for _,id in ipairs(ns.BotDecks.Expand(Main.botDeck)) do want[id]=(want[id] or 0)+1 end
    local p2=Main.game.players[2]
    for _,zone in ipairs({p2.deck,p2.hand}) do
      for _,e in ipairs(zone) do
        if e.cardId~="GAME_005" then have[e.cardId]=(have[e.cardId] or 0)+1 end
      end
    end
    local same=true
    for id,n in pairs(want) do if have[id]~=n then same=false end end
    for id,n in pairs(have) do if want[id]~=n then same=false end end
    H.ok(same,"its library is exactly that list")
    H.eq(Main.board.profiles.foe.level:GetText(),"Master bot","its nameplate says how hard it is")
    local deck=Main.botDeck
    Main:SetBotDifficulty(1)
    Main:Rematch()
    H.eq(Main.botDeck,deck,"a rematch brings the same deck back")
    H.eq(Main.botOpts.difficulty,5,"at the same difficulty, even if the slider moved since")
  end)
end)

H.suite("collection ui: pack room reveals the chosen card and returns to packs",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    Main.collection:AddPack("CLASSIC",1)
    ui:ShowPackRoom()
    ui.packSet="CLASSIC"; ui:Relayout()
    H.ok(ui.packBack:IsShown())
    ui.packBack:GetScript("OnDragStart")()
    local r=ui.packDropRect
    Stub.CursorOver(ui.frame,r.x+r.w/2,r.y+r.h/2)
    ui.packBack:GetScript("OnDragStop")()
    H.ok(ui.pack)
    H.ok(ui.slots[5].widget.faceDown)
    ui.slots[5].widget.frame:Click()
    H.eq(ui.packRevealed,1)
    H.ok(ui.slots[5].widget.faceDown,"face stays concealed until the flip midpoint")
    Stub.Advance(.15)
    H.notOk(ui.slots[5].widget.faceDown)
    H.ok(ui.slots[1].widget.faceDown)
    ui.frame:SetSize(800,600)
    H.notOk(ui.slots[5].widget.faceDown,"resize preserves the revealed card")
    for i=1,4 do ui:RevealCard(i) end
    ui:RevealNext()
    H.eq(ui.pack,nil)
    H.ok(ui.packBack:IsShown())
    ui:EditDeck(nil)
    H.ok(ui.progressText:IsShown(),"returning to collection restores controls")
  end)
end)

H.suite("collection ui: saved deck browser opens an editable clickable list",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    local deck,index=Main.collection:NewDeck("Test", "MAGE")
    deck.cards={"CS2_182","CS2_182"}
    ui:ShowDecks(); ui.menuItems[index]:Click()
    H.eq(ui.deckIndex,index)
    H.notOk(ui.menuItems[43]:IsShown(),"sparse deck-browser controls cannot remain over the editor")
    H.ok(ui.deckText:IsShown())
    ui.menuItems[1]:Click()
    H.eq(#deck.cards,1)
    ui.frame:SetSize(760,560)
    H.ok(ui.menuItems[1]:IsShown())
  end)
end)

H.suite("collection ui: emotes reach portraits without changing the action stream",function(ns,H)
  withUI(ns,function(Main)
    Main:StartPractice("MAGE","WARRIOR")
    local seq=Main.game.bus.seq
    Main:OnIntent({kind="EMOTE",index=3})
    H.eq(Main.board.speech.self.text:GetText(),"Well met!")
    Main:OnSessionEvent("EMOTE",{index=2})
    H.eq(Main.board.speech.foe.text:GetText(),"Well played!")
    H.eq(Main.game.bus.seq,seq)
  end)
end)

H.suite("collection ui: screenshot and extreme aspect ratios fill both grid axes",function(ns,H)
  local D=ns.CollectionLayout.design
  for _,size in ipairs({{1660,891},{760,560},{760,700},{1280,800},{2560,720},{760,1200},{3840,2160}}) do
    for _,deck in ipairs({false,true}) do
      local L=ns.CollectionLayout.Compute({w=size[1],h=size[2],deckOpen=deck})
      local first,last=L.cards[1],L.cards[#L.cards]
      H.eq(L.cols%2,0,"a whole number of cards on each page -- none across the spine")
      H.ok(L.cols>=4,"at least two cards a page")
      -- centred: the same margin either side of the spread, and above and below
      local left,right=first.x-L.grid.x,L.grid.x+L.grid.w-(last.x+last.w)
      H.ok(math.abs(left-right)<.01,"centred across the spread")
      local top,bottom=L.grid.y+L.grid.h-(first.y+first.h),last.y-L.grid.y
      H.ok(math.abs(top-bottom)<.01,"centred down the page")
      H.ok(L.gapX<=first.w*D.MAX_GAP_X+.01 and L.gapY<=first.h*D.MAX_GAP_Y+.01,
           "leftover room is not poured into the gaps")
      local coverage=#L.cards*first.w*first.h/(L.grid.w*L.grid.h)
      H.ok(coverage>.60,"card faces occupy the collection instead of an empty band")
    end
  end
end)

H.suite("collection ui: pages hold two, three or four cards across -- no skipping",function(ns,H)
  -- The old solver only ever made 2 or 4 cards a page (or 3 across the whole
  -- spread, one on the spine), so the cards jumped between two sizes.
  local seen={}
  for _,h in ipairs({560,700,800,900}) do
    for _,deck in ipairs({false,true}) do
      for w=760,2000,40 do
        local L=ns.CollectionLayout.Compute({w=w,h=h,deckOpen=deck})
        seen[L.cols/2]=true
      end
    end
  end
  for n=2,4 do H.ok(seen[n],n.." cards a page is used") end
  local L=ns.CollectionLayout.Compute({w=1660,h=891,deckOpen=true})
  H.eq(L.cols/2,3,"the deck builder at 1660x891 is three a page")
end)


H.suite("collection ui: search mana and explicit filters compose without losing search",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    ui.search:SetText("taunt")
    H.ok(#ui:Entries()>0)
    for _,e in ipairs(ui:Entries()) do H.ok((e.printed.text or ""):lower():find("taunt",1,true)) end
    ui.manaButtons[3]:Click()
    for _,e in ipairs(ui:Entries()) do H.eq(e.printed.cost,2) end
    ui.classButton:Click(); H.ok(ui.filterMenu:IsShown())
    ui.filterButtons[1]:Click(); ui.ownedButton:Click()
    H.eq(ui.filter.text,"taunt"); H.eq(ui.filter.cost,2); H.ok(ui.filter.all)
    H.notOk(ui.filterMenu:IsShown())
    ui.search:SetText("this will never match any card")
    H.ok(ui.emptyText:IsShown()); H.eq(#ui.slots,0)
    ui.search:SetText(""); ui.manaButtons[3]:Click()
    H.eq(ui.filter.cost,nil); H.ok(#ui.slots>0)
  end)
end)

H.suite("collection ui: resize preserves the browsed card and names stay separate from counts",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection(); ui:Scroll(2)
    local oldIndex=ui.scrollRow*ui.L.cols
    ui.frame:SetSize(1660,891)
    H.ok(ui.scrollRow*ui.L.cols<=oldIndex)
    H.ok(oldIndex<ui.scrollRow*ui.L.cols+ui.L.cols,"the old first card remains in the first row")
    local slot=ui.slots[1]
    H.eq(slot.widget.name:GetText(),slot.widget.descriptor.name)
    H.ok(slot.widget.ownedCount:IsShown())
    local deck,index=Main.collection:NewDeck("Old Name","MAGE")
    ui:EditDeck(index); ui.deckName:SetText("New Name")
    ui.deckName:GetScript("OnEnterPressed")(ui.deckName)
    H.eq(deck.name,"New Name")
  end)
end)

H.suite("collection effects: reveal focuses the chosen card and restores geometry",function(ns,H)
  withUI(ns,function(Main,ns)
    local ui=Main:Collection()
    Main.collection:AddPack("CLASSIC",1); ui:OpenPack("CLASSIC")
    Stub.Advance(2)
    ui.pack.cards[4].rarity="LEGENDARY"
    ui:RevealCard(4)
    local widget=ui.slots[4].widget
    local glow=widget.glow:GetTexture()
    H.ok(widget.faceDown)
    H.notOk(widget.skin:IsShown()); H.notOk(widget.gem:IsShown())
    Stub.Advance(.06)
    H.ok(widget.rect.w<ui.L.packCards[4].w,"flip actually contracts the card")
    Stub.Advance(.07)
    H.notOk(widget.faceDown,"front appears at midpoint")
    H.ok(widget.skin:IsShown()); H.ok(widget.art:IsShown())
    local burst=ns.Widgets.Burst
    local bx,by
    ns.Widgets.Burst=function(p,k,x,y,n) bx,by=x,y; return burst(p,k,x,y,n) end
    Stub.Advance(.13)
    ns.Widgets.Burst=burst
    local r=ui.L.packCards[4]
    H.eq(bx,r.x+r.w/2); H.eq(by,r.y+r.h/2)
    H.eq(widget.glow:GetTexture(),glow,"rarity glow preserves the textured silhouette")
    Stub.Advance(3)
    H.eq(widget.rect.w,r.w); H.eq(widget.rect.x,r.x)
    H.eq(ui.fxFrame:GetScript("OnUpdate"),nil)
    H.notOk(ui.vignette:IsShown())
  end)
end)

H.suite("collection effects: resizing cancels old pack sounds and leaves revealed faces",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    Main.collection:AddPack("CLASSIC",1); ui:OpenPack("CLASSIC")
    ui:RevealCard(3)
    ui.frame:SetSize(1000,700)
    Stub.Advance(0.01)   -- the window's music settles a frame after it opens
    local sounds=#Stub.R.sounds
    H.notOk(ui.slots[3].widget.faceDown)
    Stub.Advance(3)
    H.eq(#Stub.R.sounds,sounds,"cancelled timelines cannot announce stale reveals")
    H.eq(#ui.particles.live,0)
    H.eq(ui.fxFrame:GetScript("OnUpdate"),nil)
  end)
end)

H.suite("menus: hover audio is throttled and disabled buttons remain silent",function(ns,H)
  withUI(ns,function(Main,ns)
    local clicks=0
    local b=ns.Widgets.MenuButton(UIParent,"Test",function() clicks=clicks+1 end)
    local before=#Stub.R.sounds
    b:GetScript("OnEnter")(b); b:GetScript("OnEnter")(b)
    H.eq(#Stub.R.sounds,before+1)
    b:Click(); H.eq(clicks,1); H.eq(#Stub.R.sounds,before+2)
    b:SetEnabledLook(false)
    b:GetScript("OnEnter")(b); b:Click()
    H.eq(clicks,1); H.eq(#Stub.R.sounds,before+2)
    b:SetSize(120,40)
    H.eq(#Stub.R.sounds,before+2,"layout does not play interface sounds")
  end)
end)

H.suite("collection ui: owned toggle preserves Rogue search and mana filters",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    ui.classButton:Click()
    for _,b in ipairs(ui.filterButtons) do if b.text:GetText()=="Rogue" then b:Click(); break end end
    H.eq(ui.filter.class,"ROGUE")
    ui.search:SetText("a"); ui.manaButtons[2]:Click()
    ui.ownedButton:Click(); H.ok(ui.filter.all)
    H.eq(ui.filter.class,"ROGUE"); H.eq(ui.filter.cost,1); H.eq(ui.filter.text,"a")
    ui.ownedButton:Click(); H.notOk(ui.filter.all); H.eq(ui.filter.class,"ROGUE")
  end)
end)
H.suite("collection ui: deck rows preview and deletion works across pages",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection(); local c=Main.collection
    c.character.decks={}
    for i=1,10 do c:NewDeck("Long deck name number "..i,c.character.class) end
    ui.frame:SetSize(760,560); ui:EditDeck(1)
    local entry=ui:Entries()[1]; H.ok(entry)
    c.character.decks[1].cards={entry.cardId}; ui:Relayout()
    local row=ui.menuItems[1]
    H.eq(row.manaLabel:GetText(),tostring(entry.printed.cost or 0))
    row:GetScript("OnEnter")(); H.ok(ui.deckPreview.frame:IsShown())
    row:GetScript("OnLeave")(); H.notOk(ui.deckPreview.frame:IsShown())
    ui:ShowDecks(); ui.menuItems[43]:Click(); H.eq(ui.deckPage,2)
    H.ok(ui.menuItems[21]:IsShown()); ui.menuItems[21]:Click()
    H.eq(#c.character.decks,10,"first click asks for confirmation")
    ui.menuItems[21]:Click(); H.eq(#c.character.decks,9)
    H.eq(c.character.decks[9].name,"Long deck name number 10")
    ui:EditDeck(1); row=ui.menuItems[1]
    H.eq(row.text.font[2],13,"tile recycling restores row text")
    H.eq(row.text.wordWrap,false)
  end)
end)

H.suite("collection ui: search retains keyboard focus through typing and backspace",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection(); ui:Show(); ui.search:SetFocus()
    for _,text in ipairs({"c","ca","car","ca","c",""}) do
      ui.search:SetText(text)
      H.ok(ui.search:HasFocus(),"filter refresh must never hide the focused edit box")
      H.eq(ui.filter.text,text)
    end
    ui.search:GetScript("OnEscapePressed")(ui.search)
    H.notOk(ui.search:HasFocus())
  end)
end)
H.suite("collection ui: header controls and navigation have separate hit regions",function(ns,H)
  for _,size in ipairs(SIZES) do
    local L=ns.CollectionLayout.Compute({w=size[1],h=size[2]})
    local controls={L.search,L.classTab,L.ownedToggle,L.progress,L.dust}
    for _,r in ipairs(L.manaFilters) do controls[#controls+1]=r end
    controls[#controls+1]={x=size[1]-150,y=size[2]-28,w=110,h=26}
    for i,a in ipairs(controls) do for j=i+1,#controls do
      H.notOk(overlaps(a,controls[j]),"header controls are separate")
    end end
  end
end)
H.suite("collection ui: test packs grant once and only valid drops spend packs",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection(); ui:Show(); ui:ShowPackRoom()
    local c=Main.collection; local base=c:TotalPacks(); H.ok(base>=5)
    ui:ShowPackRoom(); H.eq(c:TotalPacks(),base,"test grant does not repeat")
    ui.packBack:Click(); H.eq(c:TotalPacks(),base,"clicks do not open packs")
    ui.packBack:GetScript("OnDragStart")(); Stub.CursorOver(ui.frame,5,5)
    ui.packBack:GetScript("OnDragStop")(); H.eq(c:TotalPacks(),base)
    ui.packBack:GetScript("OnDragStart")()
    local r=ui.packDropRect; Stub.CursorOver(ui.frame,r.x+r.w/2,r.y+r.h/2)
    ui.packBack:GetScript("OnDragStop")(); H.eq(c:TotalPacks(),base-1)
    ui:FinishPackDrag(); H.eq(c:TotalPacks(),base-1,"duplicate stop cannot spend twice")
    H.ok(ui.pack); H.notOk(ui.packBack:IsShown(),"no invisible pack target over the reveal")
    ui:ClosePack(); ui.packBack:GetScript("OnDragStart")(); ui:Hide()
    H.notOk(ui.packDragging); H.notOk(ui.packBack.moving)
    c.account.packs.HEARTHSTONE=0; ui:Show(); ui:ShowPackRoom()
    H.notOk(ui.packBack:IsShown()); H.eq(c:TotalPacks(),0)
  end)
end)
H.suite("collection ui: bot portraits have no combat health frame",function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub(); local hub=Main.hub; hub.buttons[1]:Click()
    for _,size in ipairs({{760,560},{800,600},{1000,680},{1600,900}}) do
      hub:SetSize(size[1],size[2])
      for _,tile in ipairs(hub.tiles) do
        H.ok(tile.text.font[2]>=14); H.ok(tile.text.w>=100); H.ok(tile.text.h>=20)
        for _,texture in ipairs(Stub.R.textures) do
          if texture.parent==tile then
            H.notOk(tostring(texture.texture):find("hero_frame.tga",1,true),"no health tear on selection tiles")
          end
        end
      end
    end
  end)
end)

H.suite("collection ui: default deck is saved once and remains editable",function(ns,H)
  for _,level in ipairs({1,60}) do
    withUI(ns,function(Main)
      local c=Main.collection; H.eq(#c.character.decks,1)
      local deck=c.character.decks[1]
      H.eq(#deck.cards,30); H.ok(c:ValidateDeck(deck))
      deck.name="My renamed starter"; table.remove(deck.cards)
      Main:LoadCollection(); c=Main.collection
      H.eq(#c.character.decks,1); H.eq(c.character.decks[1].name,"My renamed starter")
      H.eq(#c.character.decks[1].cards,29,"reload preserves edits")
      c:DeleteDeck(1); Main:LoadCollection()
      H.eq(#Main.collection.character.decks,0,"a deleted starter is not resurrected")
    end,{level=level})
  end
end)
H.suite("collection ui: bot game uses exactly the chosen saved deck",function(ns,H)
  withUI(ns,function(Main)
    local c=Main.collection
    local deck=c:NewDeck("Neutral test deck","MAGE")
    local ids={}
    for id,p in pairs(ns.PrintedCards) do
      if p.collectible and p.set=="CORE" and p.class=="NEUTRAL" and p.type~="HERO" then ids[#ids+1]=id end
    end
    table.sort(ids)
    for i=1,15 do deck.cards[#deck.cards+1]=ids[i]; deck.cards[#deck.cards+1]=ids[i] end
    H.ok(c:ValidateDeck(deck))
    for i=1,24 do c:NewDeck("Incomplete "..i,"MAGE") end  -- more than one page at any grid
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("practice")
    local hub=Main.hub; H.eq(Main.game,nil)
    hub.play:Click(); hub.play:Click(); H.eq(Main.game,nil,"a double click cannot start a game unseen")
    Stub.Advance(.5)
    local incomplete=hub.deckChoices[3].deck
    hub.deckChoices[3]:Click(); H.ok(hub.selectedDeck~=incomplete,"incomplete decks are disabled")
    hub.deckNext:Click(); H.eq(hub.deckPage,2)
    hub.deckPrev:Click(); hub.deckChoices[2]:Click(); H.eq(hub.selectedDeck,deck)
    hub.play:Click(); H.ok(Main.game)
    local actual={}
    for _,zone in ipairs({Main.game.players[1].hand,Main.game.players[1].deck}) do
      for _,card in ipairs(zone) do if card.cardId~="GAME_005" then actual[card.cardId]=(actual[card.cardId] or 0)+1 end end
    end
    for i=1,15 do H.eq(actual[ids[i]],2,"chosen deck survives shuffle and deal") end
    H.eq(#deck.cards,30,"starting a game does not consume the saved deck")
    Main:ShowHub(); hub.buttons[1]:Click(); hub.play:Click()
    H.eq(hub.selectedDeck,deck,"the next game opens on the deck last played")
  end)
end)

H.suite("collection ui: deck right click offers crafting without removing a card",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection(); local c=Main.collection
    c:Add("CS1_069",1); c.account.dust=10000
    local deck,index=c:NewDeck("Crafting test","MAGE"); deck.cards={"CS1_069"}
    ui:EditDeck(index); ui.menuItems[1]:Click("RightButton")
    H.eq(#deck.cards,1); H.ok(ui.inspect.frame:IsShown())
    H.ok(ui.inspectDust.enabled); H.ok(ui.inspectCraft.enabled)
    local before=c:Dust(); ui.inspectDust:Click()
    H.ok(ui.disenchantDialog:IsShown()); H.eq(c:Count("CS1_069"),1); H.eq(c:Dust(),before)
    ui.disenchantDialog.cancel:Click(); H.eq(c:Count("CS1_069"),1)
    ui:ConfirmDisenchant(); H.eq(c:Count("CS1_069"),1,"cancel discards the request")
    ui.inspectCraft:Click(); H.eq(c:Count("CS1_069"),2)
    ui.menuItems[1]:Click("RightButton"); ui.inspectDust:Click()
    ui.disenchantDialog.confirm:Click(); H.eq(c:Count("CS1_069"),1)
    ui:ConfirmDisenchant(); H.eq(c:Count("CS1_069"),1,"confirmation cannot be repeated")
    H.eq(#deck.cards,1,"crafting does not edit deck contents")
    ui.menuItems[1]:Click(); H.eq(#deck.cards,0,"left click still removes deck entries")
  end)
end)
H.suite("collection ui: golden disenchant confirmation locks the requested card",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection(); local c=Main.collection
    c:Add("EX1_116",1,true); c:Add("EX1_002",1)
    for _,entry in ipairs(c:Browse({all=true})) do if entry.cardId=="EX1_116" then ui.selected=entry end end
    ui:DisenchantSelected()
    H.ok(ui.disenchantDialog.message:GetText():find("GOLDEN",1,true))
    local before=c:Dust(); local dust=c:DustValues("EX1_116").deGolden
    for _,entry in ipairs(c:Browse({all=true})) do if entry.cardId=="EX1_002" then ui.selected=entry end end
    ui.disenchantDialog.confirm:Click()
    H.eq(c:Count("EX1_116"),0); H.eq(c:Count("EX1_002"),1)
    H.eq(c:Dust(),before+dust)
    ui:DisenchantSelected(); ui:Hide(); H.eq(ui.pendingDisenchant,nil)
  end)
end)
H.suite("collection ui: bot labels have opaque panels and resize handles explain dragging",function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub(); local hub=Main.hub; hub.buttons[1]:Click()
    for _,tile in ipairs(hub.tiles) do
      -- the name sits on Hearthstone's dark gold-rimmed name strip (opaque art)
      H.ok(tile.classLabel.plate.pieces[2].texture:find("hs-nameplate",1,true),"name strip art")
      H.ok(tile.classLabel.plate.pieces[2].shown~=false)
      H.eq(tile.text.parent,tile.classLabel)
      H.ok(tile.classLabel:GetFrameLevel()>tile:GetFrameLevel())
    end
    for _,frame in ipairs({hub,Main:Collection().frame}) do
      local grip=frame==hub and hub.grip or Main.collectionUI.grip
      H.ok(grip.tex:GetTexture():find("resize-grip",1,true),"one textured grip, not rotated lines")
      grip:GetScript("OnEnter")(); H.ok(grip.hint:IsShown())
      H.eq(grip.hint:GetText(),"Drag to resize")
      Stub.CursorOver(frame,frame:GetWidth()-4,4)
      grip:GetScript("OnMouseDown")(grip,"LeftButton"); H.ok(grip.drag)
      grip:GetScript("OnMouseUp")(); H.notOk(grip.drag)
      grip:GetScript("OnLeave")(); H.notOk(grip.hint:IsShown())
    end
  end)
end)

--============================================================ hearthstone look

H.suite("collection ui: a two-page spread never puts a card across the spine",function(ns,H)
  for _,size in ipairs(SIZES) do
    for _,deckOpen in ipairs({false,true}) do
      local L=ns.CollectionLayout.Compute({w=size[1],h=size[2],deckOpen=deckOpen})
      if L.spine then
        H.eq(L.cols%2,0,"a spread has an even column count")
        for i,r in ipairs(L.cards) do
          H.notOk(overlaps(r,L.spine),("card %d clear of the fold at %dx%d"):format(i,size[1],size[2]))
        end
      else
        H.eq(#L.pages,1,"an odd column count is a single page")
      end
      for i,t in ipairs(L.pageTitles) do
        for _,r in ipairs(L.cards) do H.notOk(overlaps(t,r),"page title "..i.." clear of the cards") end
      end
    end
  end
end)

H.suite("collection ui: class tabs and the control tray stay separate and on screen",function(ns,H)
  for _,size in ipairs(SIZES) do
    local L=ns.CollectionLayout.Compute({w=size[1],h=size[2],selected=true})
    local win={x=0,y=0,w=size[1],h=size[2]}
    local controls={L.search,L.ownedToggle,L.classTab,L.openPack}
    for _,r in ipairs(L.manaFilters) do controls[#controls+1]=r end
    for i,a in ipairs(controls) do
      H.ok(inside(win,a),"tray control fits"); H.ok(inside(L.footer,{x=a.x-L.footer.x,y=a.y-L.footer.y,w=a.w,h=a.h}),"inside the tray")
      for j=i+1,#controls do H.notOk(overlaps(a,controls[j]),"tray controls are separate") end
    end
    for i,t in ipairs(L.tabs) do
      H.notOk(overlaps(t,L.progress),"tab "..i.." clear of the progress count")
      if L.tabs[i+1] then H.notOk(overlaps(t,L.tabs[i+1]),"tabs are separate") end
    end
    for _,key in ipairs({"prevPage","nextPage"}) do
      for _,r in ipairs(L.cards) do H.notOk(overlaps(L[key],r),key.." does not cover a card") end
    end
  end
end)

H.suite("collection ui: deck rows are Hearthstone tiles with a count only for pairs",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    local deck,index=Main.collection:NewDeck("Tiles","MAGE")
    deck.cards={"CS2_182","CS2_182","CS2_029"}
    ui:EditDeck(index)
    local rows={ui.menuItems[1],ui.menuItems[2]}
    for _,row in ipairs(rows) do
      H.ok(row.tileOverlay:IsShown()); H.ok(row.cardArt:IsShown()); H.ok(row.manaBadge:IsShown())
      local two=row.text:GetText()=="Chillwind Yeti"
      H.eq(row.countBox:IsShown(),two,"count box only for two copies")
    end
    H.ok(ui.deckBanner:IsShown(),"the hero banner heads the list")
    ui:ShowDecks()
    H.notOk(ui.deckBanner:IsShown(),"and leaves with it")
    H.ok(ui.menuItems[1].deckBox.portrait:IsShown(),"saved decks are hero deck boxes")
    ui.menuItems[44]:Click(); H.notOk(ui.deckBrowser,"My Decks leads back to the collection")
    ui:EditDeck(index)
    H.notOk(rawget(ui.menuItems[1],"deckBox").portrait:IsShown(),"a recycled deck box sheds its portrait")
  end)
end)

H.suite("collection ui: practice stage shows whoever is chosen over the Play button",function(ns,H)
  withUI(ns,function(Main,ns)
    Main:ShowHub(); local hub=Main.hub; hub.buttons[1]:Click()
    H.ok(hub.book:IsShown()); H.ok(hub.stage:IsShown())
    hub.tiles[4]:Click()
    H.eq(hub.stagePortrait:GetTexture(),Main.resolver:Card(ns.HERO_ID_BY_CLASS[ns.CLASSES[4]]).icon)
    H.eq(hub.play.text:GetText(),"Choose Deck")
    hub.play:Click()
    H.eq(hub.play.text:GetText(),"Play")
    H.ok(hub.deckChoices[1].deckBox.portrait:IsShown())
    hub.buttons[1]:Click(); hub.buttons[1]:Click()
    H.notOk(hub.book:IsShown(),"the main menu has no practice book")
    H.notOk(hub.stage:IsShown())
  end)
end)

H.suite("resize grip: sizing starts from the frame's own top-left, so nothing jumps",function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub(); local hub=Main.hub
    hub.left=200; hub.bottom=100
    -- room to grow before the screen edge (the default now fills the screen)
    hub:SetSize(1280,720)
    local left,top=hub:GetLeft(),hub:GetTop()
    local w0,h0=hub:GetWidth(),hub:GetHeight()
    -- the press lands a few pixels inside the corner, as a real one does
    Stub.CursorOver(hub,w0-9,9); Stub.mouseDown={LeftButton=true}
    hub.grip:GetScript("OnMouseDown")(hub.grip,"LeftButton")
    local point,rel,relPoint,x,y=hub:GetPoint(1)
    H.eq(point,"TOPLEFT"); H.eq(relPoint,"BOTTOMLEFT")
    H.eq(x,left,"left edge stays put"); H.eq(y,top,"top edge stays put")
    H.ok(hub.grip.drag,"sizing")
    hub.grip:Step()
    H.eq(hub:GetWidth(),w0,"the first frame of a drag does not change the size")
    H.eq(hub:GetHeight(),h0,"-- no snap of the corner to the pointer")
    -- pointer moves 120 right and 40 down (screen y falls)
    Stub.cursor={x=Stub.cursor.x+120,y=Stub.cursor.y-40}
    hub.grip:Step()
    H.eq(hub:GetWidth(),w0+120,"the window follows the pointer across")
    H.eq(hub:GetHeight(),h0+40,"and down")
    H.eq(select(4,hub:GetPoint(1)),left,"top-left corner still held")
    -- dragged far off the bottom-right of the screen: capped at its edges
    Stub.cursor={x=99999,y=-99999}
    hub.grip:Step()
    H.ok(hub:GetLeft()+hub:GetWidth()<=UIParent:GetWidth()+.5,"never past the right edge")
    H.ok(hub:GetHeight()<=top+.5,"never below the bottom edge")
    -- letting go anywhere ends it, even off the grip
    Stub.mouseDown={}; hub.grip:Step(); H.notOk(hub.grip.drag,"released button ends sizing")
    hub.grip:GetScript("OnMouseUp")(hub.grip); H.notOk(hub.grip.drag)
    hub.grip:GetScript("OnMouseDown")(hub.grip,"RightButton"); H.notOk(hub.grip.drag,"only the left button sizes")
  end)
end)

H.suite("match: a second practice game starts with clean, full-size mana crystals",function(ns,H)
  withUI(ns,function(Main)
    -- The Basic Warrior at Novice: a passive player must survive to five mana,
    -- and a Mech Warrior facing nobody can end the game before that.
    local basic=ns.BotDecks.Pick("WARRIOR",1)
    Main:StartPractice("MAGE","WARRIOR",nil,basic,1)
    Main:OnIntent({kind="CONFIRM_MULLIGAN"}); Stub.Advance(3)
    for _=1,6 do Main:OnIntent({kind="END_TURN"}); Stub.Advance(20) end
    H.ok(Main.board.state.maxMana>=5,"game one got some way in")
    Main:StartPractice("MAGE","WARRIOR")
    Main:OnIntent({kind="CONFIRM_MULLIGAN"}); Stub.Advance(3)
    local b=Main.board
    local shown={}
    for _,w in ipairs(b.crystalPool.used) do if w.frame:IsShown() then shown[#shown+1]=w end end
    for _,w in ipairs(b.crystalPool.free) do H.notOk(w.frame:IsShown(),"no crystal left over from game one") end
    H.eq(#shown,b.state.maxMana,"exactly this game's crystals")
    for i,w in ipairs(shown) do
      local r=b.L.manaCrystals[i]
      H.eq(w.frame:GetWidth(),r.w); H.eq(w.frame:GetHeight(),r.h,"full size, square")
    end
  end)
end)

H.suite("collection effects: right-click reads a card you just opened", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("CLASSIC", 1); ui:OpenPack("CLASSIC")
    Stub.Advance(2)
    local click = function(i, button) local f = ui.slots[i].widget.frame; f:GetScript("OnClick")(f, button) end
    click(2, "RightButton")
    H.ok(ui.revealedCards and ui.revealedCards[2], "on a face-down card, right-click flips it")
    H.notOk(ui.inspect.frame:IsShown(), "without opening anything")
    Stub.Advance(1)
    click(2, "RightButton")
    H.ok(ui.inspect.frame:IsShown(), "on a revealed card it shows the card enlarged")
    H.eq(ui.inspect.card.name:GetText(), ui.resolver:Card(ui.pack.cards[2].cardId).name, "the card you clicked")
    H.notOk(ui.inspectCraft:IsShown() or ui.inspectDust:IsShown(), "with no craft or disenchant mid-reveal")
    H.eq(ui.packRevealed, 1, "and reveals nothing else")
    ui.inspect.frame:GetScript("OnClick")(ui.inspect.frame)
    H.notOk(ui.inspect.frame:IsShown(), "a click puts it away")
    for i = 1, #ui.pack.cards do ui:RevealCard(i) end
    Stub.Advance(1)
    click(3, "RightButton")
    H.ok(ui.pack, "after the last card, right-click still reads rather than closing the pack")
  end)
end)

H.suite("collection ui: the speaker sits beside the leftmost button in every room", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection()
    local function anchor() local _, rel = ui.speaker:GetPoint(1); return rel end
    ui:ShowDecks()
    if ui.decksButton:IsShown() then H.eq(anchor(), ui.decksButton, "beside My Decks where it shows") end
    ui:ShowPackRoom()
    H.notOk(ui.decksButton:IsShown(), "the pack room has no My Decks")
    H.eq(anchor(), ui.homeButton, "so the speaker moves up beside Main Menu")
  end)
end)

H.suite("collection ui: crafting says what it costs before you press it", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection()
    local card
    for _, entry in ipairs(Main.collection:Browse({ all = true })) do
      local v = Main.collection:DustValues(entry.cardId)
      if v and v.craftable and entry.owned == 0 and
        (entry.printed.class=="NEUTRAL" or entry.printed.class==Main.collection.character.class) then card = entry; break end
    end
    H.ok(card, "a craftable card we do not own")
    local v = Main.collection:DustValues(card.cardId)
    ui:OnCardClick(card, "RightButton")
    H.eq(ui.inspectCraft.text:GetText(), "Craft " .. v.craft, "the Craft button carries the price")
    H.ok(ui.inspectCost:IsShown() and ui.inspectCost:GetText():find(tostring(v.craft), 1, true),
         "and the line under the card says it, with the dust you have")
    H.ok(ui.inspectCost:GetText():find("short", 1, true) or Main.collection:Dust() >= v.craft,
         "and how short you are")
    H.eq(ui.craftButton.text:GetText(), "Craft " .. v.craft, "the footer's Craft too")
    H.ok(ui.dustButton.text:GetText():find("Disenchant +", 1, true), "Disenchant says what it gives")
  end)
end)

H.suite("collection ui: search reads the text as it is shown, across a keyword", function(ns, H)
  withUI(ns, function(Main)
    local ui = Main:Collection()
    ui.search:SetText("battlecry: deal 1 damage")
    local found = false
    for _, e in ipairs(ui:Entries()) do if e.cardId == "CS2_141" then found = true end end
    H.ok(found, "Ironforge Rifleman is found, though its Battlecry: is set in bold")
  end)
end)

H.suite("menus: Main Menu and close sit in the same corner on every screen", function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub(); Main.hub.buttons[1]:Click()           -- practice
    local ui=Main:Collection(); ui:Show()
    Main:StartPractice("MAGE","WARRIOR")
    for name,corner in pairs({practice=Main.hub.corner,collection=ui.corner,board=Main.board.corner}) do
      local p,rel,rp,x,y=corner.close:GetPoint(1)
      H.eq(p,"TOPRIGHT",name.." close, top right"); H.eq(x,-ns.Widgets.CORNER.inset,name); H.eq(y,-ns.Widgets.CORNER.inset,name)
      local _,left=corner.home:GetPoint(1)
      H.eq(left,corner.close,name.." Main Menu beside close")
      H.ok(corner.home:IsShown(),name.." has Main Menu")
      H.eq(corner.home:GetWidth(),ns.Widgets.CORNER.homeW,name.." all the same size")
    end
  end)
end)

--============================================================ docs/27

H.suite("collection ui: a card just unlocked is never shown greyed", function(ns, H)
  --[[ The card pool is shared with the pages, where unowned cards are grey,
       and a pack card kept that grey. ]]
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    ui.filter.all = true; ui:Relayout()                -- unowned, greyed cards on the page
    local greyed = 0
    for _, w in ipairs(ui.cardPool.used) do if rawget(w, "ghost") then greyed = greyed + 1 end end
    H.ok(greyed > 0, "the page greys what you do not own")
    Main.collection:AddPack("CLASSIC", 1)
    ui:OpenPack("CLASSIC")
    for i = 1, ns.Packs.SIZE do ui:RevealNext() end
    for i, slot in ipairs(ui.slots) do
      H.notOk(rawget(slot.widget, "ghost"), "pack card " .. i .. " is in full colour")
    end
  end)
end)

H.suite("collection ui: a third copy from a pack turns to dust, and the reveal shows it", function(ns, H)
  withUI(ns, function(Main, ns)
    local ui = Main:Collection()
    Main.collection:AddPack("CLASSIC", 1)
    local realGenerate = ns.Packs.Generate
    ns.Packs.Generate = function(set, opts)
      local pack = realGenerate(set, opts)
      pack.cards[1].cardId, pack.cards[1].golden = "CS2_188", false   -- Abusive Sergeant (Classic common)
      for i = 2, #pack.cards do pack.cards[i].golden = false end
      return pack
    end
    Main.collection:Add("CS2_188", 2)                 -- already at the deck limit
    local dustBefore = Main.collection:Dust()
    ui:OpenPack("CLASSIC")
    ns.Packs.Generate = realGenerate
    local card = ui.pack.cards[1]
    H.ok(card.extra, "the pack knows it is a third copy")
    H.eq(card.dust, Main.collection:DustValues("CS2_188").de, "it became a common's dust")
    H.eq(Main.collection:Count("CS2_188"), 2, "and is not kept")
    H.ok(Main.collection:Dust() >= dustBefore + card.dust, "the dust is banked")
    ui:RevealCard(1)
    local label = ui.packExtras and ui.packExtras[1]
    H.ok(label and label:IsShown(), "the reveal says so under the card")
    H.ok(label and label:GetText():find("dust", 1, true), "in words: " .. tostring(label and label:GetText()))
    H.notOk(ui.packStamps[1]:IsShown(), "the card is shown as itself first")
    Stub.Advance(1.2)
    H.ok(ui.packDusted[1], "then it disenchants in front of you")
    H.ok(ui.packStamps[1]:IsShown(), "stamped with what it gave")
    H.eq(ui.packStamps[1]:GetText(), ("+%d Dust"):format(card.dust))
    H.ok(rawget(ui.slots[1].widget, "ghost"), "and greyed")
    for i = 2, ns.Packs.SIZE do
      ui:RevealCard(i)
      if not ui.pack.cards[i].extra then
        H.notOk(ui.packExtras[i]:IsShown(), "a card you can use says nothing")
        H.notOk(ui.packStamps[i]:IsShown(), "and is not stamped")
      end
    end
    ui:ClosePack()
    H.notOk(ui.packExtras[1]:IsShown(), "and it leaves with the pack")
    H.notOk(ui.packStamps[1]:IsShown())
  end)
end)

H.suite("packs: a golden duplicate keeps the golden and dusts a plain copy", function(ns, H)
  withUI(ns, function(Main, ns)
    local c = Main.collection
    c:AddPack("CLASSIC", 1)
    c:Add("CS2_188", 2)
    local realGenerate = ns.Packs.Generate
    ns.Packs.Generate = function(set, opts)
      local pack = realGenerate(set, opts)
      pack.cards[1].cardId, pack.cards[1].golden = "CS2_188", true
      for i = 2, #pack.cards do pack.cards[i].golden = false end
      return pack
    end
    local pack = ns.Packs.Open(c, "CLASSIC", {})
    ns.Packs.Generate = realGenerate
    local normal, golden = c:Owned("CS2_188")
    H.eq(golden, 1, "the golden is kept")
    H.eq(normal, 1, "a plain copy went instead")
    H.ok(pack.cards[1].dustedPlain, "and the reveal knows which")
    H.eq(pack.cards[1].dust, c:DustValues("CS2_188").de, "for a plain copy's dust")
  end)
end)

H.suite("collection ui: the main menu shows this character's wins and losses", function(ns, H)
  withUI(ns, function(Main)
    Main:Record().wins, Main:Record().losses = 7, 3
    Main:PracticeRecord().wins, Main:PracticeRecord().losses = 12, 5
    Main:ShowHub()
    local hub = Main.hub
    H.ok(hub.record:IsShown(), "the record is on the main menu")
    local duels, practice = (hub.recordRows[1].value:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), (hub.recordRows[2].value:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    H.ok(hub.recordRows[1].value:GetText():find("|c", 1, true), "coloured")
    H.eq(duels, "7 W - 3 L", "duels")
    H.eq(practice, "12 W - 5 L", "practice")
    hub.buttons[1]:Click()
    H.notOk(hub.record:IsShown(), "not on the practice screen")
  end)
end)

H.suite("collection ui: difficulty is set with the opponent, not again with the deck", function(ns, H)
  withUI(ns, function(Main)
    Main:ShowHub()
    local hub = Main.hub
    hub.buttons[1]:Click()                           -- Play Bots
    H.ok(hub.diffSlider:IsShown(), "the slider is on the opponent page")
    hub.play:Click()                                 -- Choose Deck
    H.ok(hub.chooseDeck, "now choosing a deck")
    H.notOk(hub.diffSlider:IsShown(), "the slider is gone")
    H.ok(hub.diffName:GetText():find("Against", 1, true), "the stage says who you will face: " .. hub.diffName:GetText())
    hub.buttons[1]:Click()                           -- Back
    H.ok(hub.diffSlider:IsShown(), "and it is back with the opponents")
  end)
end)

--========================================= 0.1.3: the extremes (docs/32)

-- The rect of a frame placed by one point against its parent's TOPLEFT
-- (how the hub places everything), in top-down window coordinates.
local function hubRect(f)
  local p = rawget(f, "points")[1]
  local w, h = f:GetWidth(), f:GetHeight()
  local ax = ({ CENTER = .5, LEFT = 0, RIGHT = 1, TOP = .5, BOTTOM = .5, TOPLEFT = 0 })[p[1]] or .5
  local ay = ({ CENTER = .5, TOP = 0, BOTTOM = 1, TOPLEFT = 0, LEFT = .5, RIGHT = .5 })[p[1]] or .5
  return { x = (p[4] or 0) - w * ax, y = -(p[5] or 0) - h * ay, w = w, h = h }
end

H.suite("0.1.3: the main menu's plaques stay inside a narrow or ultrawide window", function(ns, H)
  withUI(ns, function(Main)
    Main:ShowHub(); Stub.Advance(.4)
    local hub = Main.hub
    for _, size in ipairs({ { 900, 1440 }, { 760, 1400 }, { 2000, 560 }, { 1180, 700 } }) do
      hub:SetSize(size[1], size[2]); hub:Layout()
      local win = { w = size[1], h = size[2] }
      for i, b in ipairs(hub.buttons) do
        H.ok(inside(win, hubRect(b)), ("plaque %d inside %dx%d"):format(i, size[1], size[2]))
      end
      H.notOk(overlaps(hubRect(hub.buttons[5]), hubRect(hub.buttons[6])),
              ("Resume and Close apart at %dx%d"):format(size[1], size[2]))
    end
    hub:SetSize(2000, 560); hub:Layout()
    H.notOk(hub.welcome:IsShown(), "no room under the cabinet: the tagline goes")
    hub:SetSize(1180, 700); hub:Layout()
    H.ok(hub.welcome:IsShown(), "and comes back when there is")
  end)
end)

H.suite("0.1.3: the Challenges plaque is wide enough for every setting", function(ns, H)
  withUI(ns, function(Main)
    Main:ShowHub(); Stub.Advance(.4)
    local hub = Main.hub
    for policy in pairs(Main.CHALLENGE_POLICY_LABEL) do
      ForeverHearthstoneDB.duelPrivacy = { policy = policy }
      Main.DuelPrivacy = function() return { policy = policy } end
      hub:Layout()
      local faceW = ns.Widgets.MenuFaceBox(hub.privacy:GetWidth(), hub.privacy:GetHeight())
      H.ok(hub.privacy.text:GetUnboundedStringWidth() <= faceW,
           policy .. ": the words fit between the end caps")
      H.eq(hub.record:GetWidth(), hub.privacy:GetWidth(), policy .. ": the record card matches it")
    end
  end)
end)

H.suite("0.1.3: a plaque's word is fitted to its stone face, not over its caps", function(ns, H)
  withUI(ns, function(Main)
    local W = ns.Widgets
    for _, size in ipairs({ { 112, 28 }, { 240, 60 }, { 500, 70 } }) do
      local b = W.MenuButton(UIParent, "Main Menu", function() end)
      b:SetSize(size[1], size[2])
      W.ApplyStyle(b.text, "button", 1440)
      local fw = W.MenuFaceBox(size[1], size[2])
      H.ok(b.text:GetUnboundedStringWidth() <= fw + 0.5,
           ("%dx%d: %.0f fits in %.0f"):format(size[1], size[2], b.text:GetUnboundedStringWidth(), fw))
    end
  end)
end)

H.suite("0.1.3: practice deck boxes fill from the top-left of the page", function(ns, H)
  withUI(ns, function(Main)
    Main:ShowHub(); Stub.Advance(.4)
    local hub = Main.hub
    for _, size in ipairs({ { 900, 1440 }, { 2000, 560 } }) do
      hub:SetSize(size[1], size[2]); hub.buttons[1]:Click(); hub.play:Click(); hub:Layout()
      local box = hub.deckChoices[1]
      H.ok(box and box:IsShown(), "the default deck is offered")
      local p = rawget(box, "points")[1]
      local top = -(p[5] or 0)
      H.ok(top < size[2] * .155 + 40, ("first box at the top of the page at %dx%d (%.0f)"):format(size[1], size[2], top))
      H.ok(box:GetHeight() >= 120, ("boxes are a readable size at %dx%d"):format(size[1], size[2]))
      hub.buttons[1]:Click()   -- Back to the opponents
      hub.buttons[1]:Click()   -- and out
    end
  end)
end)

H.suite("0.1.3: My Decks keeps its boxes a readable size in a wide, short window", function(ns, H)
  local W = H.ns.Widgets or ns.Widgets
  withUI(ns, function(Main)
    local W = ns.Widgets
    local rows, cols, bw, bh = W.DeckGrid(1582, 254, 38, 180)
    H.ok(bh >= 150, "one row of large boxes (" .. bh .. ")")
    rows, cols, bw, bh = W.DeckGrid(712, 946, 17, 320)
    H.ok(cols >= 2, "a tall page holds two across")
  end)
end)

H.suite("0.1.3: dealt pack cards stay clear of the room's painted title", function(ns, H)
  local CL = ns.CollectionLayout
  for _, size in ipairs({ { 900, 1440 }, { 2000, 560 }, { 1180, 700 }, { 760, 560 } }) do
    local L = CL.Compute({ w = size[1], h = size[2], packOpening = true, packCount = 5 })
    local room = L.packRoom
    for i, r in ipairs(L.packCards) do
      H.ok(r.y + r.h <= room.y + room.h * .93,
           ("card %d below the plaque at %dx%d"):format(i, size[1], size[2]))
    end
    for i, r in ipairs(L.packLabels) do
      H.ok(r.h <= room.h * .06, ("label %d sized by the room at %dx%d"):format(i, size[1], size[2]))
    end
  end
end)

H.suite("collection ui: class filters use readable labels and keep tab mappings",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    ui:ToggleFilters()
    H.eq(ui.filterButtons[1].text:GetText(),"All Cards")
    for _,class in ipairs(ns.CLASSES) do
      local label=class:sub(1,1)..class:sub(2):lower()
      local found=false
      for _,b in ipairs(ui.filterButtons) do
        if b.text:GetText()==label then b:Click(); H.eq(ui.filter.class,class); found=true; break end
      end
      H.ok(found,label)
    end
    ui.filterButtons[1]:Click(); H.eq(ui.filter.class,nil)
  end)
end)

H.suite("collection ui: Progression and Settings sit below Challenges without covering the record",function(ns,H)
  withUI(ns,function(Main)
    Main:ShowHub()
    local hub=Main.hub
    for _,size in ipairs({{760,560},{1280,720},{1842,672}}) do
      hub:SetSize(size[1],size[2])
      for _,policy in ipairs({"anyone","friends","nobody"}) do
        Main:SetChallengePolicy(policy); hub:Layout()
        local point=hub.settings.points[1]
        H.eq(point[1],"TOPLEFT")
        H.eq(point[2],hub.progression)
        H.eq(point[3],"BOTTOMLEFT")
        H.ok(point[5]<0,"a gap separates Settings from Challenges")
        H.eq(hub.settings:GetWidth(),hub.privacy:GetWidth())
        H.ok(hub.settings:IsShown())
      end
    end
    hub.buttons[1]:Click()
    H.notOk(hub.settings:IsShown(),"the corner stack is hidden on the practice screen")
    H.notOk(hub.progression:IsShown())
    for _,size in ipairs({{760,560},{1280,720},{1842,672}}) do
      hub:SetSize(size[1],size[2]); hub:Layout()
      H.ok(hub.stageHero:GetHeight()+18+8+30+2+18+hub.diffName:GetHeight()+hub.diffSlider:GetHeight()+hub.diffBlurb:GetHeight()+12+hub.play:GetHeight()+18 < hub.stage:GetHeight(),"opponent detail clears difficulty")
    end
    Main:Settings()
    H.eq(Main.settings.message:GetText(),"Settings")
    H.notOk(Main.settings.tabs.track:IsShown())
    Main:RewardHelp()
    H.eq(Main.settings.message:GetText(),"Progression")
    H.ok(Main.settings.tabs.track:IsShown())
    H.notOk(Main.settings.tabs.general:IsShown())

  end)
end)

H.suite("collection ui: minimap always opens collection without the hub or pack room",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    ui:ShowPackRoom()
    Main:ShowHub()
    Main:OnMinimapClick("RightButton")
    H.ok(ui:IsShown()); H.notOk(Main.hub:IsShown()); H.notOk(ui.packRoom)
    H.notOk(ui.deckBrowser); H.eq(ui.pack,nil)
    Main:OnMinimapClick("RightButton"); H.ok(ui:IsShown())
    ui:ShowDecks(); Main:ShowHub(); Main:OnMinimapClick("RightButton")
    H.notOk(ui.deckBrowser); H.notOk(Main.hub:IsShown())
  end)
end)

H.suite("collection ui: other classes are browse-only and excluded from progress",function(ns,H)
  withUI(ns,function(Main)
    local ui=Main:Collection()
    for _,e in ipairs(ui:Entries()) do
      H.ok(e.printed.class=="NEUTRAL" or e.printed.class=="MAGE")
    end
    local owned,total=Main.collection:Progress(function(p) return p.class=="NEUTRAL" or p.class=="MAGE" end)
    H.eq(ui.progressText:GetText(),("Collected %d/%d"):format(owned,total))
    ui.filter.class="WARLOCK"; ui.filter.all=true
    local entry=ui:Entries()[1]; H.ok(entry)
    ui:OnCardClick(entry,"RightButton")
    H.eq(ui.inspectCraft.text:GetText(),"Other class")
    H.ok(ui.inspectCost:GetText():find("excluded from your collection count",1,true))
    local dust=Main.collection:Dust()
    H.notOk(Main.collection:Craft(entry.cardId)); H.eq(Main.collection:Dust(),dust)
    local saved=GameTooltip
    local tip={SetOwner=function() end,SetText=function(self,t) self.text=t end,Show=function() end,Hide=function() end}
    _G.GameTooltip=tip
    ui.inspectCraft:GetScript("OnEnter")()
    H.ok(tip.text:find("Only your class and Neutral",1,true))
    ui.progressHelp:GetScript("OnEnter")()
    H.ok(tip.text:find("Other classes are excluded",1,true))
    ui:ShowPackRoom(); H.notOk(ui.progressHelp:IsShown())
    _G.GameTooltip=saved
    Main:Settings(); H.eq(rawget(Main.settings,"policy"),nil)
    Main:Settings("track")
    H.ok(Main.settings:IsShown())
    H.ok(Main.settings.track:IsShown())
    Main.settings.tabs.odds:Click()
    H.ok(Main.settings.body:GetText():find("Rare 94%",1,true))
    H.ok(Main.settings.body:GetText():find("1.5%",1,true))
    Main.settings.tabs.track:Click()
    Main.settings.track:Scroll(999)
    H.eq(Main.settings.track.columns[5].slots[1].reward.count,5)
    Main.settings.track:Scroll(-999)
    H.eq(Main.settings.track.columns[1].slots[1].reward.count,3)
    Main.settings.tabs.odds:Click()
    local packs=Main.collection:TotalPacks()
    Main.settings.previewDrop:Click()
    H.notOk(Main.settings:IsShown())
    H.ok(Main.worldStage.toastWidget.frame:IsShown())
    H.eq(Main.worldStage.toastWidget.hint:GetText(),"Preview - no pack added")
    H.eq(Main.collection:TotalPacks(),packs)

  end)
end)

H.suite("reward track: scroll bounds current level and tabs preserve progress",function(ns,H)
  withUI(ns,function(Main)
    Main.collection.character.level=17
    Main:RewardHelp()
    local d=Main.settings; local t=d.track
    H.eq(t.first,15); H.eq(t.columns[3].status:GetText(),"YOUR LEVEL")
    t:GetScript("OnMouseWheel")(t,-1); H.eq(t.first,16)
    d.current:Click(); H.eq(t.first,15)
    t:Scroll(999); H.eq(t.first,56); H.eq(t.columns[5].levelText:GetText(),"60")
    d.trackNext:Click(); H.eq(t.first,56)
    t:Scroll(-999); H.eq(t.first,1)
    H.eq(t.columns[1].slots[1].reward.count,3)
    H.eq(t.columns[3].slots[1].reward.kind,"CARD")
    local slot=t.columns[3].slots[1]
    local count=Main.collection:Count(slot.reward.cardId)
    slot.card.frame:GetScript("OnClick")(slot.card.frame,"RightButton")
    H.ok(t.inspect.frame:IsShown()); H.eq(t.inspect.card.descriptor.cardId,slot.reward.cardId)
    H.eq(Main.collection:Count(slot.reward.cardId),count,"inspection grants nothing")
    t.inspect.frame:GetScript("OnClick")(); H.notOk(t.inspect.frame:IsShown())
    H.eq(rawget(t.columns[2],"empty"),nil,"no empty-level commentary")
    H.eq(t.columns[1].levelText.justifyH,"CENTER")
    H.eq(t.columns[1].levelText.justifyV,"MIDDLE")
    d.tabs.odds:Click(); H.notOk(t:IsShown()); H.ok(d.body:IsShown())
    d.tabs.track:Click(); H.eq(t.first,1); H.ok(t:IsShown())
    d:Hide(); Main:RewardHelp(); H.eq(t.first,15)
  end)
end)
