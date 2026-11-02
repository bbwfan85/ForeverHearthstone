--[[ Client/UI/CollectionLayout.lua

  THE OUT-OF-MATCH SCREEN, SOLVED AS ARITHMETIC.

  Same discipline as Client/UI/Layout.lua and for the same reason: no WoW API,
  no frames, no pixels that are not derived from the window size. The whole
  collection browser, deck builder, crafting panel and pack-opening view are
  laid out here and merely APPLIED by Client/UI/Collection.lua, so every
  question that can be answered without a client is -- does the grid fit, does
  the deck list overlap the cards, do nine rows of cards stay legible at 800x600.

  ONE SCREEN, THREE MODES. Hearthstone separates the collection, the deck
  builder and crafting into different screens. They are the same screen here:
  the same grid of cards, with a deck list that slides in when you are editing
  one and a craft bar that appears when a card is selected. That is fewer
  frames, fewer states, and -- more importantly -- it means the card you just
  crafted is already in front of you in the grid.

  COORDINATE SPACE: origin bottom-left, +x right, +y up, rects are
  { x, y, w, h } with (x,y) at the bottom-left. Identical to Layout.lua, so the
  binding's rect-applying code is the same code.
]]
local ADDON, ns = ...

local CL = {}
ns.CollectionLayout = CL

--[[ Ratios, not pixels. The only magic numbers in the out-of-match UI. ]]
local D = {
  CARD_W_OVER_H = 0.70,      -- identical to the board, so a card is a card

  SIDE_MARGIN   = 0.025,
  HEADER_H      = 0.095,     -- progress, dust, filters
  FOOTER_H      = 0.085,     -- craft / disenchant / page buttons

  DECK_PANEL_W  = 0.235,     -- the deck list, when a deck is open
  GRID_GAP      = 0.16,      -- between cards, as a fraction of card width

  --[[ The grid is SOLVED, not chosen: as many cards as fit while every card
       stays above the legibility floor. Four columns is the minimum useful page
       and eight the most the eye can scan; two rows is a page and four is as
       many as fit before cards stop being cards.

       MIN_CARD_W is the floor that makes the whole thing work. Without it a
       wide window produces enormous cards and FEWER of them, because the card
       size follows the width -- which is the opposite of what a bigger window
       should do. ]]
  MIN_COLS = 2,               -- ALWAYS even: a whole number of cards per page
  MAX_COLS = 16,
  MIN_ROWS = 2,
  MAX_ROWS = 6,
  MIN_CARD_W = 88,
  --[[ The card width the solver aims for (scaled with the window), and how
       much it cares about that against filling the page. Without a target it
       chose on page coverage alone, and near-ties flipped it between shapes
       whose cards differed by 70%: 219px cards at one width, 129px 80px wider. ]]
  TARGET_CARD_W = 130,
  SIZE_WEIGHT   = 0.9,
  --[[ Leftover room is not all poured into the gaps (that spread two cards to
       opposite edges of a page); gaps stop at these and the block is centred. ]]
  MAX_GAP_X = 0.34,          -- of card width
  MAX_GAP_Y = 0.14,          -- of card height

  BOOK_RIM     = 18,          -- the leather cover's carved rim (Widgets MenuPanel edge)
  COUNT_TAB_H  = 16,          -- the owned-count tab hanging under a card (per scale)
  MIN_WINDOW_W = 760,
  MIN_WINDOW_H = 560,
  MAX_WINDOW_W = 3840,
  MAX_WINDOW_H = 2160,

  --[[ Pack opening takes over the whole window: five cards in a row, large,
       with nothing else competing. The moment is the point -- a pack opened in
       a corner of a browser is not an event. ]]
  PACK_CARD_H   = 0.52,      -- of window height
  -- the well in pack-room.tga (x of width, y up of height) and where the five
  -- cards land round it, in window heights (Hearthstone's own reveal)
  PACK_WELL     = { 0.593, 0.483 },   -- of the ROOM (CL.PackRoom), y up
  PACK_ROOM_ASPECT = 1293 / 899,      -- pack-room.tga's source (tools/build_pack_room.py)
  -- The top card stops short of the room's painted "Open Packs" plaque (its
  -- top ~7%): it used to reach 5% from the top and cover it.
  PACK_DEAL     = { { -0.176, -0.20 }, { 0.176, -0.22 }, { -0.306, 0.19 }, { 0, 0.262 }, { 0.325, 0.175 } },
  PACK_CARD_OF_ROOM = 0.31,  -- a dealt card's height, of the room's
  PACK_GAP      = 0.10,      -- of card width
}
CL.design = D

function CL.MinSize() return D.MIN_WINDOW_W, D.MIN_WINDOW_H end
function CL.MaxSize() return D.MAX_WINDOW_W, D.MAX_WINDOW_H end

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

--[[ How many columns and rows of cards fit, and how big a card is.

     Solved rather than chosen: pick the most columns that still leave cards
     above the legibility floor, then as many rows as fit in what is left. A
     narrow window gets four big cards a row; a wide one gets eight. ]]
local function shapeFor(gw, gh, cols, rows, spine)
  --[[ The card size is whichever of the two constraints binds: the width
       divided between the columns, or the height divided between the rows. The
       gap is a fraction of the card, so both solve directly rather than
       needing a search. An even column count is split across the two pages of
       the book, so the spine's gutter comes out of the width first. ]]
  if cols % 2 == 0 then gw = gw - (spine or 0) end
  local byWidth  = gw / (cols + (cols - 1) * D.GRID_GAP)
  local byHeight = gh / (rows / D.CARD_W_OVER_H + (rows - 1) * D.GRID_GAP)
  local cw = math.min(byWidth, byHeight)
  return { cols = cols, rows = rows, cw = cw, ch = cw / D.CARD_W_OVER_H,
           gap = cw * D.GRID_GAP, slots = cols * rows }
end

--[[ How many columns and rows of cards fit, and how big a card is.

     Every legal shape is evaluated and the one showing the MOST cards wins,
     with bigger cards as the tie-break. That is the rule that makes a bigger
     window show more of the collection rather than a bigger version of the same
     page -- and it falls out of the search rather than being a special case. ]]
local function gridShape(gw, gh, spine, target)
  local best, bestScore
  --[[ Fill the page, with cards near the target size. Only EVEN column
       counts: the book is always a two-page spread, and an odd count put a
       card across the spine. ]]
  -- Two cards a page at least, as in Hearthstone's book; one a page only
  -- when the window is too small for two to stay legible.
  for _, minCols in ipairs({4, D.MIN_COLS}) do
    for rows=D.MIN_ROWS,D.MAX_ROWS do
      for cols=minCols,D.MAX_COLS,2 do
        local candidate=shapeFor(gw,gh,cols,rows,spine)
        if candidate.cw>=D.MIN_CARD_W then
          local coverage=candidate.slots*candidate.cw*candidate.ch/(gw*gh)
          local score=coverage-D.SIZE_WEIGHT*math.abs(math.log(candidate.cw/target))
          if not bestScore or score>bestScore then best,bestScore=candidate,score end
        end
      end
    end
    if best then break end
  end
  if not best then best=shapeFor(gw,gh,D.MIN_COLS,D.MIN_ROWS,spine) end
  return best
end

--[[ THE PACK ROOM AT ITS OWN SHAPE (docs/24). pack-room.tga is a 1.44:1
     picture; stretched over a 16:9 window it was a quarter too wide. It is
     scaled to the window's height and centred (a wider window gets bands of
     its own wooden edge either side, Collection:PlacePackRoom), and the
     well, the tray and the deal are placed in the room's rect. y is up. ]]
function CL.PackRoom(w, h)
  local rh = h
  local rw = rh * D.PACK_ROOM_ASPECT
  if rw > w then rw = w; rh = rw / D.PACK_ROOM_ASPECT end
  return { x = (w - rw) / 2, y = (h - rh) / 2, w = rw, h = rh }
end

--[[ Compute the whole screen.

     spec = {
       w, h            window size
       deckOpen        a deck is being edited, so the panel is in
       selected        a card is selected, so the craft bar is in
       packOpening     a pack is being revealed: the grid is replaced
       packCount       how many cards in the pack (5)
       cards           how many card slots to lay out (defaults to a full page)
     } ]]
function CL.Compute(spec)
  spec = spec or {}
  local w = math.max(D.MIN_WINDOW_W, spec.w or 1280)
  local h = math.max(D.MIN_WINDOW_H, spec.h or 720)

  local L = { w = w, h = h }
  local scale = math.min(1.35, math.max(1, math.min(w/1180,h/700)))
  local margin = 20*scale
  --[[ Hearthstone's collection: class tabs along the top of the book, the book
       itself, and one dark tray underneath holding search, the mana crystals
       and the view toggles. The top 34px stay clear for Main Menu and close. ]]
  local headerH,footerH=46*scale,44*scale
  L.header=rect(margin,h-headerH-34*scale,w-2*margin,headerH)
  L.footer=rect(margin,12*scale,w-2*margin,footerH)
  local hx,hy,hw,hh=L.header.x,L.header.y,L.header.w,L.header.h
  L.dust=rect(hx+hw-100*scale,hy+(hh-26*scale)/2,100*scale,26*scale)
  L.progress=rect(L.dust.x-156*scale,L.dust.y,150*scale,26*scale)
  -- Class tabs: as many round crests as the caller has, left to right.
  local tabCount=spec.tabCount or 11
  local tabRoom=L.progress.x-hx-12*scale
  local tab=math.min(hh-4*scale,tabRoom/tabCount)
  L.tabs={}
  for i=1,tabCount do L.tabs[i]=rect(hx+(i-1)*tab,hy+(hh-tab)/2,tab-2*scale,tab-2*scale) end

  local fx,fy,fw,fh=L.footer.x,L.footer.y,L.footer.w,L.footer.h
  local rowH=math.min(30*scale,fh-8*scale)
  local ry=fy+(fh-rowH)/2
  local bw=math.max(70,math.min(120*scale,fw*.1))
  local pad=12*scale
  L.search=rect(fx+pad,ry,math.max(110,math.min(260*scale,fw*.2)),rowH)
  L.openPack=rect(fx+fw-pad-bw,ry,bw,rowH)
  L.classTab=rect(L.openPack.x-8*scale-bw*1.2,ry,bw*1.2,rowH)
  L.ownedToggle=rect(L.classTab.x-8*scale-bw,ry,bw,rowH)
  L.manaFilters={}
  local start=L.search.x+L.search.w+12*scale
  local available=L.ownedToggle.x-start-12*scale
  local step=math.min(38*scale,available/8)
  local gem=math.min(step-3,fh-6*scale)
  for i=0,7 do L.manaFilters[i+1]=rect(start+i*step,fy+(fh-gem)/2,gem,gem) end
  -- ---------------------------------------------------------- pack opening

  if spec.packOpening then
    --[[ The pack takes the whole window. No grid, no deck panel, no filters:
         for about four seconds this screen is only the pack. ]]
    local n = spec.packCount or 5
    local ch = h * D.PACK_CARD_H
    local cw = ch * D.CARD_W_OVER_H
    local gap = cw * D.PACK_GAP
    local total = n * cw + (n - 1) * gap
    --[[ Five large cards may not fit side by side in a narrow window. Shrink
         them to fit rather than letting them overlap: an overlapping reveal
         hides the art, which is the entire point of the moment. ]]
    if total > w - margin * 2 then
      local scale = (w - margin * 2) / total
      cw, ch, gap = cw * scale, ch * scale, gap * scale
      total = n * cw + (n - 1) * gap
    end
    local x = (w - total) / 2
    local y = (h - ch) / 2
    L.packCards = {}
    for i = 1, n do
      L.packCards[i] = rect(x + (i - 1) * (cw + gap), y, cw, ch)
    end
    --[[ Five cards dealt round the well, as Hearthstone deals them: three
         above (the middle one highest) and two below, with Done between the
         rows. Offsets are measured on Hearthstone's own reveal, in units of the
         window's height; the well's centre is where pack-room.tga paints it. ]]
    local room = CL.PackRoom(w, h)
    L.packRoom = room
    local cx, cy = room.x + room.w * D.PACK_WELL[1], room.y + room.h * D.PACK_WELL[2]
    if n == 5 then
      ch = math.min(room.h * D.PACK_CARD_OF_ROOM, w * .24); cw = ch * D.CARD_W_OVER_H
      for i, o in ipairs(D.PACK_DEAL) do
        L.packCards[i] = rect(cx + o[1] * room.h - cw / 2, cy + o[2] * room.h - ch / 2, cw, ch)
      end
    end
    L.packHint = rect(margin, (h - ch) / 2 - h * 0.09, w - margin * 2, h * 0.06)
    -- Done, in the middle of the deal; each card's class on a line beneath it
    local bw = math.min(w * .15, 200)
    L.packDone = rect(cx - bw / 2, cy - bw * .16, bw, bw * .32)
    -- sized from the ROOM, not the window: a tall window letterboxes the
    -- room, and "All Classes" came out twice the size of the cards. Even
    -- then it read as a headline beside the card's own name (the in-client
    -- tour, docs/39); it is a caption, about the height of the name banner.
    L.packLabels = {}
    for i, r in ipairs(L.packCards) do
      L.packLabels[i] = rect(r.x - r.w * .25, r.y - room.h * .036, r.w * 1.5, room.h * .03)
    end
    L.mode = "PACK"
    return L
  end

  -- ------------------------------------------------------------- the grid

  --[[ The book sits between the tabs and the tray. Its page-turn arrows hang
       half off its outer edges, as Hearthstone's do, so the book is inset by
       half an arrow on each side to keep them inside the window. ]]
  local arrowW=30*scale
  local bookX = margin + arrowW/2
  local bookR = w - margin - arrowW/2
  if spec.deckOpen then
    local panelW = math.max(208, math.min(320*scale, w * D.DECK_PANEL_W))
    L.deckPanel = rect(w - margin - panelW, L.footer.y + L.footer.h + margin * 0.5,
                       panelW, L.header.y - L.footer.y - L.footer.h - margin)
    bookR = L.deckPanel.x - margin*.5 - arrowW/2
  end
  local bookY = L.footer.y + L.footer.h + margin * 0.5
  L.book=rect(bookX,bookY,bookR-bookX,L.header.y-bookY-margin*.25)

  --[[ Inside the cover: a title band across the top of each page (the class
       being browsed) and a band along the bottom for the page count and the
       crafting buttons. The cards get everything between.

       Everything is measured from INSIDE the carved leather rim (D.BOOK_RIM,
       the MenuPanel's fixed 18px edge). Measured from the cover's outer edge,
       as it was, the page count sat in the rim and was cut in half ("Page 1
       of 20"), and the owned-count tabs hanging under the bottom row landed
       on top of it. The foot band now holds, bottom up: the page count, then
       room for those tabs. ]]
  local rim=D.BOOK_RIM
  local inset,titleH=rim+4*scale,26*scale
  local countBand,tabBand=22*scale,D.COUNT_TAB_H*scale
  local footH=countBand+tabBand
  local b=L.book
  -- Sideways the cards also clear the half of each arrow that hangs inside.
  local side=math.max(inset,arrowW/2+4*scale)
  local gridX,gridY=b.x+side,b.y+rim+2+footH
  local gridW,gridH=b.w-2*side,b.h-2*rim-4-titleH-footH
  local spine=16*scale
  -- The target follows the window's HEIGHT only. Scaled by width as well, it
  -- rose as the window widened and pulled wide windows toward fewer, bigger
  -- cards -- the opposite of what widening the book should do.
  local target = D.TARGET_CARD_W * math.min(1.35, math.max(1, h / 700))
  local shape = gridShape(gridW, gridH, spine, target)
  L.grid = rect(gridX, gridY, gridW, gridH)
  L.cols, L.rows = shape.cols, shape.rows
  L.pageSize = shape.cols * shape.rows

  -- Always a two-page spread (the solver only makes even column counts).
  local spread = shape.cols % 2 == 0
  local perPage = spread and shape.cols/2 or shape.cols
  local pageW = spread and (gridW-spine)/2 or gridW
  L.pages={}
  -- the paper tucks 2px under the rim, so no seam shows between them
  local tuck=rim-2
  if spread then
    L.pages[1]=rect(b.x+tuck,b.y+tuck,b.w/2-tuck,b.h-2*tuck)
    L.pages[2]=rect(b.x+b.w/2,b.y+tuck,b.w/2-tuck,b.h-2*tuck)
    -- The drawn fold is narrower than the gutter, so it never touches a card.
    L.spine=rect(b.x+b.w/2-spine*.3,b.y+tuck,spine*.6,b.h-2*tuck)
  else
    L.pages[1]=rect(b.x+tuck,b.y+tuck,b.w-2*tuck,b.h-2*tuck)
  end
  L.pageTitles={}
  for i,p in ipairs(L.pages) do
    L.pageTitles[i]=rect(p.x+inset,gridY+gridH+2*scale,p.w-2*inset,titleH-4*scale)
  end

  --[[ Cards fill the grid top-left to bottom-right, which is the order a reader
       expects and the order the page index counts in. Left page first, then
       across the spine: a row is one row, read straight across the spread. ]]
  L.cards = {}
  local top = gridY + gridH
  local gapX=perPage>1 and math.min((pageW-perPage*shape.cw)/(perPage-1),shape.cw*D.MAX_GAP_X) or 0
  local gapY=shape.rows>1 and math.min((gridH-shape.rows*shape.ch)/(shape.rows-1),shape.ch*D.MAX_GAP_Y) or 0
  L.gapX,L.gapY=gapX,gapY
  -- what the capped gaps leave over centres the block on each page
  local padX=(pageW-perPage*shape.cw-(perPage-1)*gapX)/2
  local padY=(gridH-shape.rows*shape.ch-(shape.rows-1)*gapY)/2
  top=top-padY
  local n = math.min(spec.cards or L.pageSize, L.pageSize)
  for i = 1, n do
    local row = math.floor((i - 1) / shape.cols)
    local col = (i - 1) % shape.cols
    local page = math.floor(col / perPage)
    local x = gridX + page * (pageW + spine) + padX + (col % perPage) * (shape.cw + gapX)
    L.cards[i] = rect(x, top - (row + 1) * shape.ch - row * gapY, shape.cw, shape.ch)
  end

  -- -------------------------------------------------- page controls

  L.prevPage=rect(b.x-arrowW/2,b.y+b.h/2-arrowW,arrowW,arrowW*2)
  L.nextPage=rect(b.x+b.w-arrowW/2,b.y+b.h/2-arrowW,arrowW,arrowW*2)
  local bandY,bandH=b.y+rim+2,countBand
  -- The page count sits under the first page, clear of the fold.
  local first=L.pages[1]
  L.pageText=rect(first.x+first.w/2-80*scale,bandY,160*scale,bandH)
  if spec.selected then
    local cw=math.min(96*scale,(b.x+b.w-inset-(L.pageText.x+L.pageText.w)-16*scale)/2)
    L.disenchant=rect(b.x+b.w-inset-cw,bandY,cw,bandH)
    L.craft=rect(L.disenchant.x-cw-6*scale,bandY,cw,bandH)
  end

  L.mode = spec.deckOpen and "DECK" or "BROWSE"
  return L
end

--[[ Which grid slot contains a point, or nil. The binding uses this for clicks
     and for drag-and-drop into the deck list, so hit-testing is solved here
     with the layout rather than guessed from frame anchors. ]]
function CL.SlotAt(L, x, y)
  for i, r in ipairs(L.cards or {}) do
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return i end
  end
  return nil
end

--[[ Paging arithmetic, kept next to the layout because the page size IS a
     layout property -- it changes when the window is resized, and a page index
     that survives a resize has to be recomputed from the card index rather than
     stored. ]]
function CL.PageOf(cardIndex, pageSize)
  if pageSize <= 0 then return 1 end
  return math.floor((cardIndex - 1) / pageSize) + 1
end

function CL.PageCount(total, pageSize)
  if pageSize <= 0 then return 1 end
  return math.max(1, math.ceil(total / pageSize))
end

return CL
