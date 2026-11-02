--[[ Client/UI/Layout.lua

  RESOLUTION-INDEPENDENT LAYOUT SOLVER.

  The board must be playable in a resizable window, so NOTHING may be a hardcoded
  pixel offset. This file takes a window size and a description of what is on the
  table, and returns a rect for every element. It is pure arithmetic: no WoW API,
  no frames, no state. That means the whole layout is unit-testable -- we can
  assert that seven minions always fit, that a hand of ten never leaves the
  window, and that nothing overlaps, at any window size, without launching WoW.

  The frame binding (Client/UI/Board.lua) does nothing but apply these rects.
  Resizing is therefore "recompute and reapply", not a special case.

  COORDINATE SPACE: origin bottom-left of the game window, +x right, +y up, in
  window pixels. Every rect is { x, y, w, h } with (x,y) at its bottom-left. The
  binding converts to SetPoint("BOTTOMLEFT", ...) calls.

  WHY A SOLVER AND NOT ANCHORS: WoW's anchor system could express most of this,
  but not the parts that matter -- fanning a variable-size hand so it always fits,
  shrinking minions when seven are out, and keeping the card aspect ratio exact
  while the window changes shape. Anchors also cannot be tested.
]]
local ADDON, ns = ...

local Layout = {}
ns.Layout = Layout

--[[ Design constants. These are the only magic numbers in the UI, they are all
     RATIOS rather than pixels, and they are gathered here so the whole look can
     be retuned in one place. ]]
--[[ THE DESIGN, AS RATIOS OF THE WINDOW.

     EVERYTHING IS ANCHORED TO THE PLAYING SURFACE.

     The board art is a picture of a table: a pale playing surface with a seam
     down the middle, sitting inside a decorated frame that already has an End
     Turn plaque, two deck slots and two hero alcoves painted on it. The old
     constants were vertical BANDS that divided the window without reference to
     any of that, so the rows, the hands, the heroes and the mana landed
     wherever the arithmetic put them -- below the table, over the scenery, on
     top of the painted furniture. Every "the scaling is off" symptom came from
     that one mismatch.

     So the surface comes first. `tools/fetch_art.py` NORMALISES every board
     texture at import so its painted surface lands exactly on SURFACE below
     (tools/board_calibration.json holds the per-board measurement), which means
     one set of numbers is correct for every board -- including any board added
     later. Everything else is positioned relative to SURFACE rather than to the
     window, so the layout and the picture cannot drift apart.

     Vertical order, bottom to top: your hand (running off the bottom edge, as
     it does in Hearthstone), your hero, your minions, the seam, their minions,
     their hero, their hand (running off the top). ]]
local D = {
  -- A playing card is taller than it is wide. Every card and minion derives its
  -- height from its width through this, so cards can never be stretched.
  CARD_W_OVER_H   = 0.70,

  --[[ THE PLAYING SURFACE, as fractions of the window. This is the pale area
       the minions stand on, and it is where the board art is normalised to. ]]
  --[[ Measured off the CLEAN ORGRIMMAR BOARD, which is the reference the
       others are normalised to. It is the right reference because it is the
       only one with its sockets empty: bare hero alcoves, an empty mana
       trough, a plaque with no words painted in. We fill those rather than
       drawing a second set of furniture beside them. ]]
  SURFACE_X0      = 0.155,
  SURFACE_X1      = 0.845,
  SURFACE_Y0      = 0.305,
  SURFACE_Y1      = 0.755,
  --[[ The seam is NOT the midpoint of the surface -- the painted line sits a
       little above centre, so your half of the table is deeper than theirs.
       It is its own constant because assuming the midpoint put the rope and the
       row divider in the wrong place by two percent of the window. ]]
  SEAM_Y          = 0.545,
  ROPE_Y          = 549 / 1024, -- painted groove center: row 475 in the board texture

  --[[ The minion rows are narrower than the surface, because the End Turn
       plaque and the deck slots are painted into the frame at the surface's
       right-hand edge and a seventh minion must not end up underneath them. ]]
  --[[ Enough that the seventh minion stops clear of the End Turn plaque, which
       the art paints ACROSS the surface's right-hand edge rather than beside
       it. The layout sweep asserts the two never meet. ]]
  PLAY_INSET      = 0.090,   -- fraction of the surface width, each side

  MINION_W_OVER_H = 1, -- inplay_minion.tga is a square canvas
  BOARD_SLOTS     = 7,
  BOARD_GAP       = 0.09,    -- gap between minions, as a fraction of minion width

  --[[ THE HAND HANGS OFF THE BOTTOM OF THE WINDOW.

       A card in hand shows its mana gem, its art and its name. The rules text
       and the attack/health below them are cut off by the bottom edge, and you
       read them by hovering. That is what makes a hand read as HELD -- cards
       in a fan, most of each one behind the one in front and behind the edge
       of the table -- rather than as a row laid out on a shelf.

       The reason this could not be done before was DRAW ORDER: the fan
       overlapped the hero and was drawn in front of it, so hanging the cards
       low enough to look right put them over your own health. That is fixed
       separately -- the hero, hero power, weapon and mana now draw above the
       resting hand (Board.lua: FURNITURE_LEVEL) -- which frees the hand to sit
       where it belongs.

       HAND_REVEAL is the fraction of a resting card that stays on screen,
       measured to clear the name banner and nothing more. It is a fraction of
       THE CARD, not of the window: the card's height is capped by the fan's
       width on a tall narrow window, and a window fraction would swallow most
       of a small card there. ]]
  --[[ Sized from a real hand of ten on this board, then opened up: the
       measured card was legible but small, and a hand you have to lean in to
       read is worse than one that overlaps a little harder. So the card is
       bigger and LESS of it shows -- the cut moves up, the fan tightens, and
       the top of each card is no higher on screen than it was.

       HAND_REVEAL is the fraction of a resting card above the bottom edge. It
       still clears the name banner, which is the floor: below that the hand is
       a row of anonymous pictures. ]]
  HAND_CARD_H     = 0.215,
  HAND_REVEAL     = 0.70,
  --[[ HOW FAR APART A FULL HAND SITS, as a fraction of ONE CARD'S WIDTH.

       Measured from the reference: with ten cards each sits a little under half
       a card from the last, so every card is mostly behind its neighbour and
       only the gem, a sliver of art and the name show. That overlap is what
       makes it a hand.

       This used to be a fraction of the WINDOW, which is the wrong unit: the
       right span depends on how big a card is, and a card's size is set by the
       window's HEIGHT. On a wide window the same fraction of width was far more
       room than ten cards needed, so they stopped overlapping and spread out
       into a row -- which is exactly how it looked. ]]
  HAND_PITCH_FULL = 0.38,
  --[[ A SHORT HAND OVERLAPS TOO. Held cards always cover part of their
       neighbour: the pitch starts at HAND_PITCH_ONE (a card and most of the
       next) and tightens by HAND_PITCH_STEP per extra card until the fan fills
       its span. A gap between cards (the old 1.10) read as a row laid out on
       the table, and from five cards up it spread the hand to the full width
       ten need, far out to the left of the hero. ]]
  HAND_PITCH_ONE  = 0.82,
  HAND_PITCH_STEP = 0.05,
  HAND_MIN_REVEAL = 0.30,    -- when crowded, at least this much of each card
                             -- stays visible, so every mana cost is readable
  --[[ How close the fan may come to the left edge of the window. It exists
       because the fan is no longer centred on the window -- see the span
       solve in Layout.Compute -- so the left edge is a real bound rather than
       a consequence of symmetry. ]]
  HAND_MARGIN     = 0.02,
  --[[ The FAN. A hand is held in one hand, so it arcs and the cards lean.
       HAND_ARC is the centre card's lift as a fraction of card width;
       HAND_LEAN is the outermost card's tilt in radians. Both are damped by how
       wide the hand actually is (see fanHand), so a hand of two is nearly flat
       and a hand of ten is a proper fan. ]]
  HAND_ARC        = 0.13,
  HAND_LEAN       = 0.22,

  --[[ THEIR HAND, face down, running off the top edge the way yours runs off
       the bottom. ]]
  FOE_HAND_H      = 0.150,
  FOE_HAND_TOP    = 1.045,   -- top edge of the cards, above the window

  --[[ HEROES SIT IN THE PAINTED ALCOVES. The alcove is an arch, wider relative
       to its height than a card, so its size is two measurements rather than
       one plus the card ratio -- deriving it from CARD_W_OVER_H drew a portrait
       narrower than the hole it sits in. ]]
  HERO_HOLDER_X0  = 912 / 2048,
  HERO_HOLDER_X1  = 1112 / 2048,
  HERO_HOLDER_Y0  = (1024 - 871) / 1024,
  HERO_HOLDER_Y1  = (1024 - 695) / 1024,
  FOE_HOLDER_Y0   = (1024 - 258) / 1024,
  FOE_HOLDER_Y1   = (1024 - 87) / 1024,
  POWER_SCALE     = 0.62,    -- hero power height relative to the hero
  POWER_GAP       = 0.018,   -- fraction of window width, hero to hero power

  --[[ THE RIGHT-HAND FURNITURE, painted into the frame: two deck slots and the
       End Turn plaque. These are measured from the normalised art, so the live
       controls sit ON the painted ones rather than beside them. ]]
  DECK_CX         = 0.873,
  DECK_W          = 0.039,
  DECK_H          = 0.135,
  DECK_DY         = 0.138,   -- each deck slot, above/below the seam
  --[[ The plaque is centred on the seam. Placed FROM the seam rather than from
       the window, so it stays on the painting if the surface is ever retuned. ]]
  -- The painted End Turn plaque, its dark outline included, measured on the
  -- full-resolution painting by tools/build_turn_button.py (px 3013,957 -
  -- 3354,1133 of 3840x2281). The live button is cut from that very plaque,
  -- so it is drawn exactly on it, at its own 1.94:1.
  ENDTURN_CX      = 0.8290,
  ENDTURN_DY      = -0.0031,
  ENDTURN_W       = 0.0888,
  ENDTURN_H       = 0.0772,

  --[[ MANA, bottom right, in the strip between your hero power and the edge --
       which is where Hearthstone puts it and where the eye already goes to ask
       "can I afford this". ]]
  --[[ The mana trough, painted into the bottom edge of the board. Ten crystals
       sized to fill it, which is why the tray is measured rather than the
       crystal: the crystals are however wide a tenth of the trough is. ]]
  --[[ THE BLUE LOZENGE PAINTED INTO THE TROUGH IS THE READOUT, NOT A CRYSTAL.

       That was the mistake: it is much larger than a crystal, so treating it as
       one made ten of them span half the board. It is the socket the "7/10"
       goes in -- the reference screenshot has exactly this pill with "10/10"
       written in it, and the crystals in a row to its RIGHT.

       So the numbers go in the lozenge and the crystals fill the trough beyond
       it, which also stops the row running underneath the hand. ]]
  -- Measured in the installed 2048x1024 orgrimmar_clean texture:
  -- readout centered at (1350, 956), crystal well x=1418..1780.
  MANA_READOUT_CX = 1350 / 2048,
  MANA_READOUT_W  = 92 / 2048,
  MANA_X0         = 1418 / 2048,
  MANA_X1         = 1780 / 2048,
  MANA_CY         = 68 / 1024,
  MANA_H          = 28 / 1024,

  --[[ THE PICTURE KEEPS ITS SHAPE (docs/24). The board textures are stored
       at 2048x1024, but that is only a power-of-two canvas: the table they
       show is 1.683:1 (the reference, org_clean_board.jpg, is 3840x2281, and
       tools/fetch_art.py normalises every board onto its crop). Stretched to
       the window, the table was right only at about 16:9 -- a 4:3 window
       squashed the alcoves, a wide one pulled them into ovals. Now the whole
       picture is scaled to the window's HEIGHT at its true shape and centred.
       A wider window gets bands beside it, filled from the picture's own
       outermost strip of curtain (Board:FitBoardArt); a narrower one crops
       the curtain margins, but no further than ART_MAX_CROP of each side --
       past that are the deck slots and the history tray -- and is then
       letterboxed. Every painted socket below is a fraction of the PICTURE,
       mapped through `art` in Compute. ]]
  ART_ASPECT      = 3840 / 2281,
  ART_MAX_CROP    = 0.085,

  -- Legibility floor. Below this the text on a card cannot be read, so the
  -- window refuses to go smaller. The binding feeds these to SetResizeBounds.
  MIN_WINDOW_W    = 760,
  MIN_WINDOW_H    = 560,
  MAX_WINDOW_W    = 3840,
  MAX_WINDOW_H    = 2160,
}
Layout.design = D

function Layout.MinSize() return D.MIN_WINDOW_W, D.MIN_WINDOW_H end
function Layout.MaxSize() return D.MAX_WINDOW_W, D.MAX_WINDOW_H end

-- Clamp a requested window size into the legible range. The binding calls this
-- before applying a user drag, so a resize can never produce an unreadable board.
function Layout.ClampSize(w, h)
  if w < D.MIN_WINDOW_W then w = D.MIN_WINDOW_W end
  if h < D.MIN_WINDOW_H then h = D.MIN_WINDOW_H end
  if w > D.MAX_WINDOW_W then w = D.MAX_WINDOW_W end
  if h > D.MAX_WINDOW_H then h = D.MAX_WINDOW_H end
  return w, h
end

local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

--[[ Lay out a row of `n` items of width `iw`, centred on `cx`, with `gap`
     between them. Returns a list of x positions (left edges).

     The row is always centred, which is what makes a board with three minions
     look deliberate rather than left-aligned with a hole. ]]
local function centredRow(n, iw, gap, cx)
  local out = {}
  if n <= 0 then return out end
  local total = n * iw + (n - 1) * gap
  local x = cx - total / 2
  for i = 1, n do
    out[i] = x + (i - 1) * (iw + gap)
  end
  return out
end

--[[ Fan a hand of `n` cards into `avail` width.

     Cards keep their full width and OVERLAP when the hand is large -- the
     Hearthstone behaviour, and the only way ten cards fit without becoming
     unreadable slivers. `HAND_MIN_REVEAL` guarantees enough of each card stays
     visible to read its mana cost, which is the one thing you must be able to
     see on a card you are not hovering.

     Returns the list of left edges plus the pitch actually used. ]]
local function fanHand(n, cw, avail, cx, arc)
  if n <= 0 then return {}, 0, {}, {} end
  local idealPitch = cw * math.max(D.HAND_PITCH_FULL,
                                  D.HAND_PITCH_ONE - D.HAND_PITCH_STEP * (n - 1))
  local pitch = idealPitch
  if n > 1 then
    local needed = (n - 1) * idealPitch + cw
    if needed > avail then
      -- compress: distribute the remaining space, but never below the floor
      pitch = (avail - cw) / (n - 1)
      local floorPitch = cw * D.HAND_MIN_REVEAL
      if pitch < floorPitch then pitch = floorPitch end
    end
  end
  local total = (n - 1) * pitch + cw
  local x = cx - total / 2
  local out, dy, rot = {}, {}, {}

  --[[ THE ARC. Positions alone give a straight row of overlapping rectangles,
       which is a stack of cards, not a hand. A hand is held: the middle rides
       higher than the ends and each card leans away from centre.

       `t` runs -1..1 across the hand, so the shape is one parabola and one
       line rather than a per-card table, and it is correct for one card (flat
       and upright) without a special case.

       Both the lift and the lean scale with how WIDE the hand is, not with how
       many cards are in it: two cards held far apart barely lean, ten crowded
       together lean hard, which is what a real fan does. ]]
  local spread = (n > 1) and (total / cw) or 0
  local lift = (arc or D.HAND_ARC) * cw * math.min(1, spread / 8)
  local lean = D.HAND_LEAN * math.min(1, spread / 8)
  for i = 1, n do
    out[i] = x + (i - 1) * pitch
    local t = (n > 1) and ((i - 1) / (n - 1) * 2 - 1) or 0
    dy[i]  = lift * (1 - t * t)      -- highest in the middle, level at the ends
    rot[i] = -lean * t               -- leans away from centre, upright in it
  end
  return out, pitch, dy, rot
end

--[[ Compute the full layout.

     spec = {
       width, height,              -- window size in pixels (required)
       handCount    = 0..10,       -- cards in the player's hand
       foeHandCount = 0..10,
       boardCount   = 0..7,        -- player's minions
       foeBoardCount= 0..7,
       hasWeapon    = bool, foeHasWeapon = bool,
       maxMana      = 0..10,
       foeMaxMana   = 0..10,       -- their tray, mirrored along the top
     }

     Returns a flat table of named rects plus `scale`, `cardW`, `minionW`. ]]
function Layout.Compute(spec)
  local W, H = Layout.ClampSize(spec.width or D.MIN_WINDOW_W,
                               spec.height or D.MIN_WINDOW_H)

  --[[ THE PICTURE'S RECT in the window (see ART_ASPECT). tx/ty map a
       fraction of the picture (x from the left, y from the BOTTOM) to window
       pixels; aw/ah size a fraction of it. ]]
  local artH = H
  local artW = artH * D.ART_ASPECT
  local widest = W / (1 - 2 * D.ART_MAX_CROP)
  if artW > widest then artW = widest; artH = artW / D.ART_ASPECT end
  local artX, artY = (W - artW) / 2, (H - artH) / 2
  local function tx(f) return artX + f * artW end
  local function ty(f) return artY + f * artH end
  local function aw(f) return f * artW end
  local function ah(f) return f * artH end

  --[[ THE SURFACE. Every other rect is placed relative to this, so the layout
       and the board picture move together by construction. ]]
  local sx0, sx1 = tx(D.SURFACE_X0), tx(D.SURFACE_X1)
  local sy0, sy1 = ty(D.SURFACE_Y0), ty(D.SURFACE_Y1)
  local surfaceW = sx1 - sx0
  --[[ The seam is measured, not assumed to be the midpoint: the painted line
       sits above centre, so your half of the table is deeper than theirs. ]]
  local seam = ty(D.SEAM_Y)
  local cx = (sx0 + sx1) / 2

  -- the part of the surface minions may stand on: clear of the painted
  -- End Turn plaque and deck slots at the right-hand edge
  local inset  = surfaceW * D.PLAY_INSET
  local fieldX = sx0 + inset
  local fieldW = surfaceW - inset * 2

  --[[ Minion size is the binding constraint: seven must always fit across the
       play area. Derive width from that, then height from the aspect ratio,
       then clamp by the row height so a very wide, short window does not
       produce minions taller than the half of the surface they stand on. ]]
  local slotPitch = fieldW / D.BOARD_SLOTS
  local minionW   = slotPitch / (1 + D.BOARD_GAP)
  local minionH   = minionW / D.MINION_W_OVER_H
  --[[ The two rows are DIFFERENT DEPTHS, because the seam is not the midpoint.
       Minions are one size on both sides, so the shallower row is what the
       size has to fit -- sizing to the average left the top row's minions
       standing off the back edge of the table. ]]
  local myRowH  = seam - sy0
  local foeRowH = math.min(sy1, ty(D.FOE_HOLDER_Y0 - 0.01)) - seam
  local bandFit = math.min(myRowH, foeRowH) * 0.94
  if minionH > bandFit then
    minionH = bandFit
    minionW = minionH * D.MINION_W_OVER_H
  end
  local boardGap = minionW * D.BOARD_GAP

  --[[ Hand cards are drawn larger than board minions: they are what you read.

       The height is what the design wants; the WIDTH is then capped so that a
       full hand of ten still fits inside the fan's span at the minimum reveal.
       Without the cap a tall, narrow window produced cards wide enough that ten
       of them overflowed the window sideways even fully overlapped -- the
       legibility floor and the window edge were both hard constraints and
       nothing reconciled them. Shrinking the cards is the only give there is. ]]
  local cardH = H * D.HAND_CARD_H
  local cardW = cardH * D.CARD_W_OVER_H

  --[[ The fan is given exactly the room a full hand needs at the measured
       overlap -- derived from the card, so it is correct at any window shape --
       and then clamped to the table, because a hand wider than the board it is
       being played onto is worse than a slightly tighter fan. ]]
  local span = math.min(cardW * (1 + (ns.RULES.HAND_LIMIT - 1) * D.HAND_PITCH_FULL),
                        surfaceW)
  local manaLeft = tx(D.MANA_READOUT_CX - D.MANA_READOUT_W / 2)
  local cornerRoom = cardH * math.sin(D.HAND_LEAN) / 2 + aw(0.008)

  --[[ THE FAN IS SLID CLEAR OF THE MANA TRAY, NOT SHRUNK TO AVOID IT.

       THE BUG THIS FIXES, and it is most of what was wrong with the hand.
       The fan used to be centred on the table's midline and then clamped to
         span = 2 * (manaLeft - cx - cornerRoom)
       -- twice the gap between the centre and the mana socket. That is a
       SYMMETRIC clamp on an ASYMMETRIC obstacle: the tray is on the right, so
       reserving the same room on the left threw away the entire left half of
       the bottom strip, which is empty. At 1280x720 the hand got 296 of the
       884 pixels of table, a third of the room it should have.

       The cost compounded. Ten cards had to fit in that third, so they hit
       the 30% reveal FLOOR at seven cards and the solver then shrank the
       cards themselves -- so drawing a card made your whole hand smaller, the
       text and badges on it re-sized, and a crowded hand left 24-pixel slivers
       that were genuinely hard to point at. "The hand is too narrow",
       "resizing breaks the icons and text" and "hovering a card with a full
       hand is impossible" were all this one line.

       So the span stays the width a full hand WANTS, and the fan's centre
       moves left until its rotated corner clears the socket. That is also
       where Hearthstone puts it: the hand sits left of the mana crystals,
       not symmetrically around them.

       The span is only narrowed if the fan cannot fit between the two bounds
       even after sliding -- which needs a very wide tray or a very small
       window, and is the one case where there is genuinely no room. ]]
  local rightLimit = manaLeft - cornerRoom
  --[[ ...and clear of your profile plate in the bottom-left corner
       (Board:LayoutProfiles: 10px in, 120..170 wide). In a tall window the
       picture overhangs the window's sides, so nothing else stopped the fan
       running over your name (reported with a screenshot). Only as far as
       the fan can move without narrowing: at the smallest window a full hand
       needs that corner more than the plate does. ]]
  local plateRight = 10 + math.max(120, math.min(170, W * .13))
  local leftLimit  = W * D.HAND_MARGIN + cornerRoom
  leftLimit = math.max(leftLimit, math.min(plateRight + cornerRoom, rightLimit - span))
  span = math.min(span, rightLimit - leftLimit)
  local handCx = cx
  if handCx + span / 2 > rightLimit then handCx = rightLimit - span / 2 end
  if handCx - span / 2 < leftLimit  then handCx = leftLimit  + span / 2 end

  --[[ Cards keep their size unless the span genuinely cannot hold a full hand
       at the reveal floor. With the fan no longer confined to a third of the
       table this is now the rare case rather than the ordinary one, which is
       what makes a card the same size however many you are holding. ]]
  local handCount = math.max(1, math.min(spec.handCount or 0, ns.RULES.HAND_LIMIT))
  local widest = span / (1 + (handCount - 1) * D.HAND_MIN_REVEAL)
  if cardW > widest then
    cardW = widest
    cardH = cardW / D.CARD_W_OVER_H
  end

  local L = {
    width = W, height = H,
    art = rect(artX, artY, artW, artH),
    cardW = cardW, cardH = cardH,
    minionW = minionW, minionH = minionH,
    -- a single scalar the FX layer uses to size particles and shake amplitude
    scale = minionW / (D.MIN_WINDOW_W / D.BOARD_SLOTS),
    --[[ `field` is the PLAY AREA, not the whole window. The tests use it to
         assert that nothing interactive strays onto the minion rows. ]]
    field = rect(fieldX, sy0, fieldW, sy1 - sy0),
    surface = rect(sx0, sy0, surfaceW, sy1 - sy0),
    seam = seam,
  }

  -- ---- the two minion rows, one either side of the seam
  L.boardSlots, L.foeBoardSlots = {}, {}
  local n    = math.max(0, math.min(spec.boardCount or 0, D.BOARD_SLOTS))
  local nFoe = math.max(0, math.min(spec.foeBoardCount or 0, D.BOARD_SLOTS))
  local selfY = sy0  + (myRowH  - minionH) / 2
  local foeY  = seam + (foeRowH - minionH) / 2
  --[[ Both rows share the heroes' axis, as in Hearthstone: a lone minion
       stands straight above (or below) its hero. The painted hero sockets sit
       a hair left of the window's middle (HERO_HOLDER_X0/X1), so centring the
       rows on the window put every minion visibly off its hero. ]]
  --   A row too wide to stand on that axis inside the playfield (a full
  --   board spans it edge to edge) slides only as far as the field allows.
  local heroCx = tx((D.HERO_HOLDER_X0 + D.HERO_HOLDER_X1) / 2)
  local function rowCentre(count)
    local half = (count * minionW + math.max(0, count - 1) * boardGap) / 2
    return math.max(fieldX + half, math.min(fieldX + fieldW - half, heroCx))
  end
  for i, x in ipairs(centredRow(n, minionW, boardGap, rowCentre(n))) do
    L.boardSlots[i] = rect(x, selfY, minionW, minionH)
  end
  for i, x in ipairs(centredRow(nFoe, minionW, boardGap, rowCentre(nFoe))) do
    L.foeBoardSlots[i] = rect(x, foeY, minionW, minionH)
  end

  --[[ Drop zones: where a dragged card may be released to insert at position i.
       There is always one more zone than there are minions (you can insert at
       either end), which is what makes positional adjacency playable at all.

       They span both rows so dropping over the enemy's sand also plays the
       card. The insertion index always refers to the friendly board. ]]
  L.dropZones = {}
  -- Either half of the sand accepts a play; x still selects our insertion slot.
  local zoneY, zoneH = sy0, sy1 - sy0
  if n < D.BOARD_SLOTS then
    local left = sx0
    for i = 1, n + 1 do
      local right = i <= n and (L.boardSlots[i].x + minionW / 2) or sx1
      L.dropZones[i] = rect(left, zoneY, right - left, zoneH)
      left = right
    end
  end

  -- ---- heroes, hero powers, weapons: in the alcoves outside the surface
  -- Holder bounds are measured on the actual 2048x1024 board. The hero
  -- texture has 14 transparent pixels on each side of its 256px canvas.
  -- Fit its visible edges, not its transparent canvas, to those holders.
  local holderWidth = aw(D.HERO_HOLDER_X1 - D.HERO_HOLDER_X0)
  L.heroHolder = rect(tx(D.HERO_HOLDER_X0), ty(D.HERO_HOLDER_Y0),
    holderWidth, ah(D.HERO_HOLDER_Y1-D.HERO_HOLDER_Y0))
  L.foeHeroHolder = rect(tx(D.HERO_HOLDER_X0), ty(D.FOE_HOLDER_Y0),
    holderWidth, ah(D.FOE_HOLDER_Y1-D.FOE_HOLDER_Y0))
  local function portraitRect(holder)
    return rect(holder.x-holder.w*14/228, holder.y, holder.w*256/228, holder.h)
  end
  L.hero, L.foeHero = portraitRect(L.heroHolder), portraitRect(L.foeHeroHolder)
  local heroH, heroW = L.hero.h, L.hero.w

  local ph = heroH * D.POWER_SCALE
  local pw = ph
  local pgap = aw(D.POWER_GAP)
  -- Measured power sockets in the colored Orgrimmar reference. The texture
  -- includes margins, so place its whole canvas rather than the visible disc.
  local powerW,powerH=aw(.080),ah(.142)
  L.heroPower=rect(tx(.59)-powerW/2,ty(.225)-powerH/2,powerW,powerH)
  L.foeHeroPower=rect(tx(.59)-powerW/2,ty(.817)-powerH/2,powerW,powerH)

  if spec.hasWeapon then
    L.weapon = rect(L.hero.x - pgap - pw, L.hero.y + (heroH - ph) / 2, pw, ph)
  end
  if spec.foeHasWeapon then
    L.foeWeapon = rect(L.foeHero.x - pgap - pw, L.foeHero.y + (heroH - ph) / 2, pw, ph)
  end

  --[[ ---- HANDS. Yours runs off the bottom edge and theirs off the top, which
       is what makes them read as held rather than displayed. `span` was worked
       out with the card size above: it is the room a full hand needs at the
       measured overlap, not a slice of the window. ]]
  L.handSlots = {}
  local hn = math.max(0, math.min(spec.handCount or 0, ns.RULES.HAND_LIMIT))
  -- Reserve the readout socket, including the card's rotated upper corner.
  -- The available span already reserves the mana socket on both sides.
  local xs, pitch, dys, rots = fanHand(hn, cardW, span, handCx)
  --[[ A SHORT HAND SITS UNDER YOUR HERO. The span above is the room a FULL
       hand needs, slid left of the mana tray; a hand of three or four was
       centred on that slid span and so sat well left of your hero -- far to
       the left in a narrow window (reported with a screenshot). The cards
       actually held are centred on the hero's axis, and moved only as far as
       the mana tray and the window's edge require. ]]
  if hn > 0 then
    local total = (hn - 1) * pitch + cardW
    local want = math.max(leftLimit + total / 2, math.min(rightLimit - total / 2, heroCx))
    local shift = want - (xs[1] + total / 2)
    for i = 1, #xs do xs[i] = xs[i] + shift end
    handCx = want
  end
  L.handPitch = pitch
  L.handCx = handCx
  for i, x in ipairs(xs) do
    L.handSlots[i] = rect(x, -cardH * (1 - D.HAND_REVEAL) + (dys[i] or 0),
                          cardW, cardH)
    L.handSlots[i].rot = rots[i] or 0
  end

  L.foeHandSlots = {}
  local fhn = math.max(0, math.min(spec.foeHandCount or 0, ns.RULES.HAND_LIMIT))
  local fcH = math.min(H * D.FOE_HAND_H,
    aw(0.38) / ((1 + 9*D.HAND_MIN_REVEAL) * D.CARD_W_OVER_H))
  local fcW = fcH * D.CARD_W_OVER_H
  --[[ Their hand arcs the other way: it hangs from the top of the screen, so
       the middle dips toward you rather than lifting away. ]]
  --[[ Their hand is centred on the TABLE, not on yours: there is no mana tray
       along the top edge to slide clear of, so the obstacle that moves your
       fan does not exist for theirs. ]]
  -- Keep the entire rotated fan left of the enemy's painted mana socket.
  local foeFanRight = tx(0.615)
  local foeFanSpan = math.min(span * 0.8, aw(0.38))
  local fxs, _, fdys, frots = fanHand(fhn, fcW, foeFanSpan, foeFanRight - foeFanSpan/2 - fcH*0.08)

  --[[ THEIR HAND IS LIFTED CLEAR OF THEIR PORTRAIT.

       THE BUG: the enemy hand hung to `FOE_HAND_TOP - FOE_HAND_H` = 0.895 of
       the window and the enemy hero's alcove reaches 0.915, so the portrait
       covered the bottom fifth of the middle three or four cards -- and the
       portrait is FURNITURE, which draws above a resting hand by design, so it
       won every time. The hand you are meant to be counting was the one thing
       hidden behind the face.

       DERIVED from the holder rather than nudged as a constant, so it stays
       true if the alcove ever moves: the lowest the cards may hang is a hair
       above the top of the alcove. ]]
  local foeHandFloor = L.foeHeroHolder.y + L.foeHeroHolder.h + H * 0.004
  for i, x in ipairs(fxs) do
    local y = H * D.FOE_HAND_TOP - fcH - (fdys[i] or 0)
    L.foeHandSlots[i] = rect(x, math.max(y, foeHandFloor + math.abs(math.sin(frots[i] or 0))*fcW/2), fcW, fcH)
    L.foeHandSlots[i].rot = -(frots[i] or 0)
  end
  --[[ CLEAR OF THE CORNER. In a tall window the picture is letterboxed and
       their hand hangs from the top of the WINDOW, where the corner row
       (music, speaker, Concede, Main Menu, close) lives -- the fan covered it
       (reported with a screenshot). Where a card reaches into that corner, the
       whole fan drops below the row. ]]
  if spec.cornerW and spec.cornerH then
    local cornerX, cornerY = W - spec.cornerW, H - spec.cornerH - H * 0.006
    local drop = 0
    for _, r in ipairs(L.foeHandSlots) do
      local reach = math.abs(math.sin(r.rot or 0)) * r.h / 2
      if r.x + r.w + reach > cornerX and r.y + r.h + reach > cornerY then
        drop = math.max(drop, r.y + r.h + reach - cornerY)
      end
    end
    for _, r in ipairs(L.foeHandSlots) do r.y = r.y - drop end
  end

  --[[ ---- THE PAINTED FURNITURE: deck slots and the End Turn plaque.

       These sit ON the art rather than beside it. The board texture already
       draws a plaque and two card-back slots at these positions -- normalised
       there by tools/fetch_art.py -- so a live control anywhere else would be
       a second, contradictory copy of a thing the table already has. ]]
  --[[ The deck slot is painted as a card seen edge-on -- tall and narrow, not
       a card's aspect -- so it is sized from its own measurement rather than
       from CARD_W_OVER_H, which would leave a wide pip spilling over it. ]]
  local deckW, deckH = aw(D.DECK_W), ah(D.DECK_H)
  L.deck    = rect(tx(D.DECK_CX) - deckW / 2, seam - ah(D.DECK_DY) - deckH / 2, deckW, deckH)
  L.foeDeck = rect(tx(D.DECK_CX) - deckW / 2, seam + ah(D.DECK_DY) - deckH / 2, deckW, deckH)

  local etW, etH = aw(D.ENDTURN_W), ah(D.ENDTURN_H)
  L.endTurn = rect(tx(D.ENDTURN_CX) - etW / 2,
                   seam + ah(D.ENDTURN_DY) - etH / 2, etW, etH)

  --[[ ---- MANA, bottom right. Ten crystals in the strip beside your hero
       power, sized to fill it, so "can I afford this" is answered where the
       eye already is. ]]
  local maxMana = math.max(0, math.min(spec.maxMana or 0, ns.RULES.MANA_CAP))
  L.manaCrystals = {}
  local manaW = aw(D.MANA_X1 - D.MANA_X0) / ns.RULES.MANA_CAP
  --[[ The crystal art is a square hexagon with a margin round it, so a
       crystal is SQUARE (a narrower rect squashed the hexagon) and as wide as
       its slot in the trough, which is what makes the row of gems fill it. ]]
  local crystalH = math.min(manaW * 0.98, ah(D.MANA_H) * 1.3)
  local crystalW = crystalH
  for i = 1, maxMana do
    L.manaCrystals[i] = rect(tx(D.MANA_X0) + (i - 1) * manaW
                               + (manaW - crystalW) / 2,
                             ty(D.MANA_CY) - crystalH / 2, crystalW, crystalH)
  end
  --[[ The socket the numbers go in, whether or not any crystals are drawn --
       "0/10" on turn zero still belongs somewhere. ]]
  L.manaReadout = rect(tx(D.MANA_READOUT_CX - D.MANA_READOUT_W / 2),
                       ty(D.MANA_CY - D.MANA_H / 2),
                       aw(D.MANA_READOUT_W), ah(D.MANA_H))

  --[[ ---- THEIR MANA, mirrored along the top.

       It was not drawn at all, and it is not decoration: how much mana the
       opponent has is the single number that decides whether it is safe to
       commit to the board. Playing without it is playing blind, and every
       other client shows it.

       Mirrored about the window's midline rather than given its own constants,
       because it IS the same tray seen from the other side of the table. The
       board art paints no well up there -- it is a one-sided picture -- so the
       crystals carry themselves, which they already do when there is no art at
       all. ]]
  local foeMax = math.max(0, math.min(spec.foeMaxMana or 0, ns.RULES.MANA_CAP))
  L.foeManaCrystals = {}
  for i = 1, foeMax do
    local r = L.manaCrystals[i] or rect(tx(D.MANA_X0) + (i - 1) * manaW
                                          + (manaW - crystalW) / 2,
                                        ty(D.MANA_CY) - crystalH / 2,
                                        crystalW, crystalH)
    L.foeManaCrystals[i] = rect(r.x, 2 * artY + artH - r.y - r.h, r.w, r.h)
  end
  L.foeManaReadout = rect(L.manaReadout.x, 2 * artY + artH - L.manaReadout.y - L.manaReadout.h,
                          L.manaReadout.w, L.manaReadout.h)
  -- Top socket is painted higher than a mirror of the bottom trough.
  L.foeManaReadout.y = ty(1 - 42/1024) - L.foeManaReadout.h/2
  L.foeManaReadout.x = tx(1324/2048) - L.foeManaReadout.w/2
  for _, r in ipairs(L.foeManaCrystals) do
    r.y = ty(1 - 42/1024) - r.h/2
  end
  L.historySlots = {}
  local historySize = math.min(aw(0.029), ah(0.043))
  for i = 1, 8 do
    L.historySlots[i] = rect(tx(0.128) - historySize/2,
      ty(0.33) + (i-1) * ah(0.048), historySize, historySize)
  end

  --[[ ---- THE ROPE, ACROSS THE SEAM.

       Hearthstone lays it along the centre line between the two boards and
       burns it toward the End Turn button, so it crosses your field of view:
       you cannot be looking at the board and not see it. The seam is where the
       art already draws a line, so the rope lies in the picture's own groove. ]]
  -- The rope spans the table, independent of the inset used to fit minions.
  --[[ The rope's thickness, of the picture's height. It was 0.014 of a rect
       whose texture is mostly transparent, so it drew about 0.6%: a thread
       (reported: "the rope should be thicker"). ]]
  local ropeH = ah(0.02)
  local ropeStart=sx0+aw(0.008)
  local ropeEnd=L.endTurn.x-aw(0.006)
  L.rope = rect(ropeStart, ty(D.ROPE_Y) - ropeH / 2, ropeEnd-ropeStart, ropeH)

  --[[ ---- SECRETS, as a row of small pips beside each hero.

       Hearthstone puts them over the hero because that is what they defend, and
       because a secret has to be visible without competing with the board -- a
       secret drawn as a card would read as an eighth minion. Five slots, the
       zone limit.

       Yours show what they are; theirs show only that they exist. That
       distinction is made in the snapshot, not here -- the layout has no
       opinion about what a pip contains. ]]
  --[[ They sit ON THE PORTRAIT'S TOP RIM, as Hearthstone's do: the first at
       the crown and each later one alternating outward and a little lower,
       following the arch. Inside the hero frame they cannot touch the front
       rank of minions -- a row laid across the table's near edge did, which is
       the one place on the board that must stay unambiguous. ]]
  local secW = minionW * 0.26
  L.secrets, L.foeSecrets = {}, {}
  local ARC = { 0, -1, 1, -2, 2 }
  local function rim(hero, i)
    local k = ARC[i] or 0
    local cx = hero.x + hero.w / 2 + k * secW * 1.08
    local cy = hero.y + hero.h - secW * 0.55 - math.abs(k) * secW * 0.30
    return rect(cx - secW / 2, cy - secW / 2, secW, secW)
  end
  for i = 1, ns.RULES.SECRET_SLOTS do
    L.secrets[i]    = rim(L.hero, i)
    L.foeSecrets[i] = rim(L.foeHero, i)
  end

  --[[ ---- the Choose One prompt
       Present only when the caller says a choice is pending. Mode cards,
       centred on the surface, drawn larger than a hand card because the whole
       decision is reading them -- each is a real card rendered from the mode's
       own printed name and text.

       Sized from the SURFACE the rest of the board uses, so it tracks every
       window size without a second set of constants, and clamped to the play
       area so the cards can never collide or spill out of the window. ]]
  if spec.chooseOne then
    local pad     = minionW * 0.35
    local promptH = math.min((sy1 - sy0) * 0.86, H * 0.42)
    local promptW = promptH * D.CARD_W_OVER_H
    --[[ Two options for Choose One, three for Tracking. Narrowed if the row
         would not fit -- three cards at the two-card width overflow a small
         window, and this clamp is what the layout sweep proves is reachable. ]]
    local count = math.max(2, math.min(spec.chooseCount or 2, 4))
    local rowW = promptW * count + pad * (count - 1)
    if rowW > fieldW - pad * 2 then
      promptW = (fieldW - pad * 2 - pad * (count - 1)) / count
      promptH = promptW / D.CARD_W_OVER_H
    end
    local pxs = centredRow(count, promptW, pad, cx)
    local cy = seam - promptH / 2
    local cards = {}
    for i = 1, count do cards[i] = rect(pxs[i], cy, promptW, promptH) end
    L.choosePrompt = {
      dim   = rect(0, 0, W, H),
      cards = cards,
      title = rect(fieldX, cy + promptH + pad * 0.3, fieldW, promptH * 0.14),
    }
  end

  --[[ ---- THE MULLIGAN.

       The opening hand, dealt across the middle of the screen, larger than a
       hand card because the entire decision is reading them. Everything else is
       behind a dimmer: nothing else may be done until it is confirmed, and a
       board you can see but not touch invites clicking at it.

       Three or four cards (four when you are going second and hold the Coin,
       which cannot be thrown back), so the row is sized from the count. ]]
  if spec.mulligan then
    local count = math.max(1, math.min(spec.mulliganCount or 3, ns.RULES.HAND_LIMIT))
    local pad = minionW * 0.28
    local mH = H * 0.42
    local mW = mH * D.CARD_W_OVER_H
    local rowW = mW * count + pad * (count - 1)
    if rowW > fieldW - pad * 2 then
      mW = (fieldW - pad * 2 - pad * (count - 1)) / count
      mH = mW / D.CARD_W_OVER_H
    end
    local mxs = centredRow(count, mW, pad, cx)
    local cy = H / 2 - mH * 0.45
    local cards = {}
    for i = 1, count do cards[i] = rect(mxs[i], cy, mW, mH) end
    -- the tavern button (Widgets.MenuButton), the size of the post-game pair
    -- (Board:SetPostGame) so the two moments look like one game
    local btnW = math.floor(math.max(150, math.min(230, W * 0.16)))
    local btnH = math.floor(math.max(40, math.min(56, H * 0.062)))
    L.mulligan = {
      dim     = rect(0, 0, W, H),
      cards   = cards,
      title   = rect(fieldX, cy + mH + pad * 0.5, fieldW, mH * 0.12),
      confirm = rect(cx - btnW / 2, cy - btnH - pad * 1.1, btnW, btnH),
    }
  end

  return L
end

-- ------------------------------------------------------------------ helpers

function Layout.Contains(r, x, y)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

function Layout.Overlaps(a, b)
  return not (a.x + a.w <= b.x or b.x + b.w <= a.x
           or a.y + a.h <= b.y or b.y + b.h <= a.y)
end

--- Which drop zone is the pointer over? Returns the insertion index, or nil.
function Layout.DropIndexAt(L, x, y)
  for i, z in ipairs(L.dropZones) do
    if Layout.Contains(z, x, y) then return i end
  end
  return nil
end

--- Is a rect fully inside the window? Used by the tests to prove nothing escapes.
function Layout.InsideWindow(L, r, slack)
  slack = slack or 0
  return r.x >= -slack and r.y >= -slack
     and r.x + r.w <= L.width + slack
     and r.y + r.h <= L.height + slack
end

return Layout
