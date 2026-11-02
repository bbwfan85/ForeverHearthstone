--[[ tests/test_layout.lua -- resolution-independent layout.

  The board has to be playable in a resizable window. These tests sweep the whole
  window-size range and the whole range of game states, asserting the invariants
  that make a layout correct rather than just checking one screenshot-sized case:

    * seven minions per side always fit, at any window size
    * a hand of ten never leaves the window
    * every card keeps its exact aspect ratio
    * nothing that must stay separate ever overlaps
    * sizes grow monotonically with the window
    * the legibility floor is enforced

  None of this needs WoW. Layout.lua is pure arithmetic, which is the reason
  resizing can be trusted before we can see it.
]]
local H = require("tests.harness")

H.suite("layout: enemy fan clears its mana and history stays in the painted rail",function(ns,H)
  for _,size in ipairs({{760,560},{1280,720},{1600,900},{900,1200},{3840,2160}}) do
    for count=1,10 do
      local L=ns.Layout.Compute({width=size[1],height=size[2],foeHandCount=count,foeMaxMana=10})
      for _,r in ipairs(L.foeHandSlots) do
        local right=r.x+r.w/2+math.abs(math.cos(r.rot))*r.w/2+math.abs(math.sin(r.rot))*r.h/2
        H.ok(right<L.foeManaReadout.x,"rotated hand stays left of the mana socket")
      end
      -- the rail is painted on the picture: measured in the picture's rect
      local A=L.art
      for _,r in ipairs(L.historySlots) do
        H.ok(r.x>=A.x+A.w*.11 and r.x+r.w<=A.x+A.w*.15,"inside left rail")
        H.ok(r.y>=A.y+A.h*.32 and r.y+r.h<=A.y+A.h*.72,"inside rail height")
      end
    end
  end
end)

-- A representative sweep: extremes, common 16:9 and 16:10 sizes, and awkward
-- shapes (very wide, very tall, square) that break naive layouts.
local SIZES = {
  { 760, 560 }, { 800, 600 }, { 1024, 768 }, { 1280, 720 }, { 1366, 768 },
  { 1600, 900 }, { 1920, 1080 }, { 2560, 1440 }, { 3840, 2160 },
  { 900, 1400 },   -- portrait
  { 2400, 600 },   -- ultra-wide and short
  { 700, 500 },    -- below minimum, must clamp
  { 5000, 3000 },  -- above maximum, must clamp
}

local function full(ns, w, h)
  return ns.Layout.Compute({
    width = w, height = h,
    handCount = 10, foeHandCount = 10,
    boardCount = 7, foeBoardCount = 7,
    hasWeapon = true, foeHasWeapon = true, maxMana = 10,
  })
end

--============================================================ basic sanity

H.suite("layout: clamps to the legibility floor and ceiling", function(ns, H)
  local minW, minH = ns.Layout.MinSize()
  local maxW, maxH = ns.Layout.MaxSize()
  local L = ns.Layout.Compute({ width = 100, height = 100 })
  H.eq(L.width, minW, "width clamped up to the minimum")
  H.eq(L.height, minH, "height clamped up to the minimum")
  local L2 = ns.Layout.Compute({ width = 99999, height = 99999 })
  H.eq(L2.width, maxW, "width clamped down to the maximum")
  H.eq(L2.height, maxH, "height clamped down to the maximum")
end)

H.suite("layout: computes at every size without error", function(ns, H)
  for _, s in ipairs(SIZES) do
    local ok, L = pcall(full, ns, s[1], s[2])
    H.ok(ok, ("computed at %dx%d"):format(s[1], s[2]))
    if ok then
      H.ok(L.minionW > 0 and L.minionH > 0, ("positive minion size at %dx%d"):format(s[1], s[2]))
      H.ok(L.cardW > 0 and L.cardH > 0, ("positive card size at %dx%d"):format(s[1], s[2]))
    end
  end
end)

--=================================================== the hard constraints

H.suite("layout: seven minions always fit inside the playfield", function(ns, H)
  --[[ This is the binding constraint on the whole layout. A board of seven is
       legal and common, so if it ever overflows the window the game is broken at
       that size. ]]
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    H.eq(#L.boardSlots, 7, ("seven slots at %dx%d"):format(s[1], s[2]))
    local first, last = L.boardSlots[1], L.boardSlots[7]
    H.ok(first.x >= L.field.x - 0.5,
         ("left minion inside the field at %dx%d"):format(s[1], s[2]))
    H.ok(last.x + last.w <= L.field.x + L.field.w + 0.5,
         ("right minion inside the field at %dx%d"):format(s[1], s[2]))
    -- and they must not overlap each other
    for i = 1, 6 do
      H.notOk(ns.Layout.Overlaps(L.boardSlots[i], L.boardSlots[i + 1]),
              ("minions %d/%d disjoint at %dx%d"):format(i, i + 1, s[1], s[2]))
    end
  end
end)

H.suite("layout: a hand of ten never leaves the window", function(ns, H)
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    H.eq(#L.handSlots, 10, ("ten hand slots at %dx%d"):format(s[1], s[2]))
    for i, r in ipairs(L.handSlots) do
      H.ok(r.x >= -1 and r.x + r.w <= L.width + 1,
           ("hand card %d horizontally inside at %dx%d"):format(i, s[1], s[2]))
    end
  end
end)

H.suite("layout: a crowded hand still reveals enough of every card", function(ns, H)
  --[[ When the hand is full the cards overlap, which is correct -- but you must
       still be able to read the mana cost of every card you hold, or you cannot
       plan a turn. The floor is enforced as a fraction of card width. ]]
  local D = ns.Layout.design
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    H.ok(L.handPitch >= L.cardW * D.HAND_MIN_REVEAL - 0.001,
         ("pitch >= reveal floor at %dx%d (%.1f vs %.1f)")
           :format(s[1], s[2], L.handPitch, L.cardW * D.HAND_MIN_REVEAL))
  end
end)

H.suite("layout: cards keep their exact aspect ratio at every size", function(ns, H)
  -- A stretched card looks broken and is the most visible possible layout bug.
  local D = ns.Layout.design
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    local ac = L.cardW / L.cardH
    local am = L.minionW / L.minionH
    H.ok(math.abs(ac - D.CARD_W_OVER_H) < 1e-6,
         ("hand card aspect exact at %dx%d (%.4f)"):format(s[1], s[2], ac))
    H.ok(math.abs(am - D.MINION_W_OVER_H) < 1e-6,
         ("minion aspect exact at %dx%d (%.4f)"):format(s[1], s[2], am))
  end
end)

H.suite("layout: the two boards never overlap each other", function(ns, H)
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    for i, a in ipairs(L.boardSlots) do
      for j, b in ipairs(L.foeBoardSlots) do
        H.notOk(ns.Layout.Overlaps(a, b),
                ("own minion %d vs foe %d at %dx%d"):format(i, j, s[1], s[2]))
      end
    end
  end
end)

H.suite("layout: secrets sit on their hero's portrait, clear of every minion", function(ns, H)
  local function inside(r, box)
    return r.x >= box.x - 0.5 and r.y >= box.y - 0.5
       and r.x + r.w <= box.x + box.w + 0.5 and r.y + r.h <= box.y + box.h + 0.5
  end
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    for _, side in ipairs({ { L.secrets, L.hero, "own" }, { L.foeSecrets, L.foeHero, "foe" } }) do
      local slots, hero = side[1], side[2]
      H.eq(#slots, ns.RULES.SECRET_SLOTS, "five slots, the zone limit")
      for i, r in ipairs(slots) do
        H.ok(inside(r, hero), ("%s secret %d on the portrait at %dx%d"):format(side[3], i, s[1], s[2]))
        for j = i + 1, #slots do
          H.notOk(ns.Layout.Overlaps(r, slots[j]), ("%s secrets %d/%d apart"):format(side[3], i, j))
        end
        for k, m in ipairs(L.boardSlots) do
          H.notOk(ns.Layout.Overlaps(r, m), ("%s secret %d clear of minion %d"):format(side[3], i, k))
        end
        for k, m in ipairs(L.foeBoardSlots) do
          H.notOk(ns.Layout.Overlaps(r, m), ("%s secret %d clear of foe minion %d"):format(side[3], i, k))
        end
      end
      H.ok(math.abs((slots[1].x + slots[1].w / 2) - (hero.x + hero.w / 2)) < 1, "the first crowns the portrait")
    end
  end
end)

H.suite("layout: heroes never overlap their own board or each other", function(ns, H)
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    H.notOk(ns.Layout.Overlaps(L.hero, L.foeHero),
            ("heroes disjoint at %dx%d"):format(s[1], s[2]))
    for i, m in ipairs(L.boardSlots) do
      H.notOk(ns.Layout.Overlaps(L.hero, m),
              ("own hero vs own minion %d at %dx%d"):format(i, s[1], s[2]))
    end
    for i, m in ipairs(L.foeBoardSlots) do
      H.notOk(ns.Layout.Overlaps(L.foeHero, m),
              ("foe hero vs foe minion %d at %dx%d"):format(i, s[1], s[2]))
    end
  end
end)

H.suite("layout: the end-turn button never covers the playfield", function(ns, H)
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    -- the painted plaque's left bevel overhangs the surface's edge a little,
    -- in the art itself; the live button is cut from that plaque (docs/13)
    H.ok(L.endTurn.x >= L.field.x + L.field.w - L.width * 0.012,
         ("end turn is in the rail at %dx%d"):format(s[1], s[2]))
    for i, m in ipairs(L.boardSlots) do
      H.notOk(ns.Layout.Overlaps(L.endTurn, m),
              ("end turn vs minion %d at %dx%d"):format(i, s[1], s[2]))
    end
    H.ok(ns.Layout.InsideWindow(L, L.endTurn, 1),
         ("end turn inside window at %dx%d"):format(s[1], s[2]))
  end
end)

H.suite("layout: hero power and weapon sit beside the hero, inside the window", function(ns, H)
  for _, s in ipairs(SIZES) do
    local L = full(ns, s[1], s[2])
    H.notOk(ns.Layout.Overlaps(L.hero, L.heroPower),
            ("hero vs power at %dx%d"):format(s[1], s[2]))
    H.ok(L.weapon, "weapon rect present when a weapon is equipped")
    if L.weapon then
      H.notOk(ns.Layout.Overlaps(L.hero, L.weapon),
              ("hero vs weapon at %dx%d"):format(s[1], s[2]))
      H.notOk(ns.Layout.Overlaps(L.weapon, L.heroPower),
              ("weapon vs power at %dx%d"):format(s[1], s[2]))
    end
  end
end)

H.suite("layout: no weapon rect when no weapon is equipped", function(ns, H)
  local L = ns.Layout.Compute({ width = 1280, height = 720, hasWeapon = false })
  H.eq(L.weapon, nil, "absent rather than zero-sized")
end)

--================================================================ scaling

H.suite("layout: element size grows monotonically with the window", function(ns, H)
  --[[ A bigger window must never produce smaller cards. This catches the classic
       bug where one clamp fights another and the layout folds back on itself at
       some intermediate size. ]]
  local prevM, prevC = 0, 0
  for w = 800, 2560, 64 do
    local L = full(ns, w, math.floor(w * 9 / 16))
    H.ok(L.minionW >= prevM - 0.001,
         ("minion width non-decreasing at w=%d (%.2f >= %.2f)"):format(w, L.minionW, prevM))
    H.ok(L.cardW >= prevC - 0.001,
         ("card width non-decreasing at w=%d"):format(w))
    prevM, prevC = L.minionW, L.cardW
  end
end)

H.suite("layout: minion rows stand on the heroes' axis regardless of count", function(ns, H)
  --[[ Hearthstone lines a lone minion up straight above its hero. The painted
       hero sockets sit a hair left of the window's middle, so the rows follow
       the heroes, not the window -- unless a row is too wide to stand there
       inside the field, when it slides only as far as the field's edge. ]]
  for _, size in ipairs({ {760, 560}, {1280, 720}, {1600, 900}, {2560, 1440} }) do
    for n = 1, 7 do
      local L = ns.Layout.Compute({ width = size[1], height = size[2], boardCount = n, foeBoardCount = n })
      H.eq(#L.boardSlots, n, n .. " slots")
      local heroCx = L.hero.x + L.hero.w / 2
      H.ok(math.abs((L.foeHero.x + L.foeHero.w / 2) - heroCx) < 0.5, "both heroes on one axis")
      for _, row in ipairs({ L.boardSlots, L.foeBoardSlots }) do
        local first, last = row[1], row[n]
        local mid = (first.x + last.x + last.w) / 2
        local atEdge = first.x <= L.field.x + 0.5 or last.x + last.w >= L.field.x + L.field.w - 0.5
        H.ok(math.abs(mid - heroCx) < 0.5 or atEdge,
             ("%d minions on the hero's axis at %dx%d (mid %.1f vs hero %.1f)"):format(n, size[1], size[2], mid, heroCx))
      end
      if n == 1 then
        local m = L.boardSlots[1]
        H.ok(math.abs(m.x + m.w / 2 - heroCx) < 0.5, "a lone minion stands straight above its hero")
      end
    end
  end
end)

H.suite("layout: an empty board and empty hand are valid", function(ns, H)
  local L = ns.Layout.Compute({ width = 1280, height = 720,
                                handCount = 0, boardCount = 0,
                                foeHandCount = 0, foeBoardCount = 0 })
  H.eq(#L.boardSlots, 0, "no minion slots")
  H.eq(#L.handSlots, 0, "no hand slots")
  H.eq(#L.dropZones, 1, "still exactly one drop zone -- you must be able to play")
  H.ok(L.hero and L.foeHero, "heroes still laid out")
end)

--============================================================= drop zones

H.suite("layout: the whole friendly row accepts insertion without gaps", function(ns, H)
  for n=0,6 do
    local L = ns.Layout.Compute({width=1600, height=900, boardCount=n})
    local first = L.dropZones[1]
    local last = L.dropZones[#L.dropZones]
    for x=first.x+1,last.x+last.w-1,5 do
      H.ok(ns.Layout.DropIndexAt(L,x,first.y+first.h/2), "continuous insertion surface")
    end
  end
end)

H.suite("layout: there is always one more drop zone than there are minions", function(ns, H)
  --[[ Positional adjacency is real gameplay (Dire Wolf Alpha, Sunfury Protector),
       so the player must be able to insert at either end as well as between. With
       n minions that is n+1 positions. ]]
  for n = 0, 7 do
    local L = ns.Layout.Compute({ width = 1600, height = 900, boardCount = n })
    local expected = n < 7 and (n + 1) or 0
    H.eq(#L.dropZones, expected, ("%d minions -> %d drop zones"):format(n, expected))
  end
end)

H.suite("layout: drop zones are ordered left to right and hit-testable", function(ns, H)
  local L = ns.Layout.Compute({ width = 1600, height = 900, boardCount = 4 })
  for i = 1, #L.dropZones - 1 do
    H.ok(L.dropZones[i].x < L.dropZones[i + 1].x,
         ("zone %d is left of zone %d"):format(i, i + 1))
  end
  -- hit-testing the centre of each zone must return that zone's index
  for i, z in ipairs(L.dropZones) do
    local got = ns.Layout.DropIndexAt(L, z.x + z.w / 2, z.y + z.h / 2)
    H.eq(got, i, ("hit test returns zone %d"):format(i))
  end
  H.eq(ns.Layout.DropIndexAt(L, -500, -500), nil, "outside returns nil")
end)

--=========================================================== mana crystals

H.suite("layout: resizing compacts the hand before shrinking its cards", function(ns, H)
  local wide = ns.Layout.Compute({width=2000,height=1000,handCount=5})
  local compact = ns.Layout.Compute({width=1500,height=1000,handCount=5})
  H.ok(math.abs(wide.cardW-compact.cardW) < 0.001, "keep card size while overlap is available")
  --[[ Widening the window at the same height now changes the hand NOT AT ALL.
       Both the card and the span it is fanned into are derived from the card's
       size, which comes from the window's HEIGHT, so there is nothing for extra
       width to do -- and that is the point: "the way we draw cards should be
       consistent however the stage is resized".

       This assertion used to read `compact.handPitch < wide.handPitch`, which
       was true only because the fan's width was a slice of the gap between the
       table's midline and the mana socket, so every horizontal resize squeezed
       it. That squeeze is the bug this file's newer suites pin. ]]
  H.ok(math.abs(compact.handPitch - wide.handPitch) < 0.001,
       "and extra width alone does not respace it")
  local shorter = ns.Layout.Compute({width=2000,height=800,handCount=5})
  H.ok(shorter.cardW < wide.cardW, "a SHORTER window is what makes cards smaller")

  --[[ THE PROPERTY THIS SUITE IS NAMED FOR is that resizing does not make the
       hand WANDER. It used to be asserted as "the fan is centred on the window
       midline", which is a stronger claim than no-drift and was really pinning
       a different decision: the fan was centred on the midline and then clamped
       to twice its distance from the mana socket, which cost it the whole empty
       left half of the bottom strip.

       The fan slides clear of the socket now instead of shrinking away from it,
       so it sits LEFT of the midline -- which is also where Hearthstone puts
       it. What must still hold is that its position is a pure function of the
       window's shape: at one aspect ratio the centre is the same FRACTION of
       the width at every size, so dragging the window scales the hand rather
       than sliding it about. ]]
  --[[ At a FIXED aspect ratio. The fan's clearance mixes a height-derived term
       (the rotated corner of a card, whose size comes from the window height)
       with width-derived ones, so its position is a function of the window's
       SHAPE as well as its size -- and it has to be, or the corner would not
       clear the socket at every shape. Scaling 16:9 keeps the shape fixed and
       isolates the thing being asserted. Widths start above the point where
       ClampSize would raise the height off the ratio. ]]
  -- (per hand SIZE since docs/24: a short hand sits under the hero, a full
  -- one slides left of the tray -- but neither moves as the window is resized)
  local reference = {}
  for width=1000,2100,40 do
    for n=1,10 do
      local L = ns.Layout.Compute({width=width,height=width*9/16,handCount=n})
      local first,last=L.handSlots[1],L.handSlots[n]
      local centre = (first.x+last.x+last.w)/2 / L.width
      reference[n] = reference[n] or centre
      H.ok(math.abs(centre-reference[n])<0.001,
        ("no resize-induced drift: %d cards, centre %.4f of the width at %d, expected %.4f")
          :format(n, centre, width, reference[n]))
    end
  end
  H.ok(reference[10] < 0.5, "a full hand sits left of the midline, clear of the mana tray")
  local L = ns.Layout.Compute({width=1280,height=720,handCount=3})
  local heroCx = L.hero.x + L.hero.w / 2
  H.ok(math.abs(reference[3] * 1280 - heroCx) < L.cardW * 0.5, "and a short hand sits under the hero, as near as the tray allows")
end)

H.suite("layout: a card is the SAME SIZE however many you are holding", function(ns, H)
  --[[ THE BUG. The fan was confined to a third of the table, so a hand of
       seven already sat on the 30% reveal floor and the solver then shrank the
       CARDS to make ten fit. Drawing a card therefore resized your whole hand
       -- every badge, every piece of text, every icon on it -- which is what
       "resizing can cause issues with various icons, text (mana health attack)"
       and "our system for drawing cards should always be consistent" were
       both describing.

       A card's size may depend on the WINDOW. It must not depend on how many
       cards are next to it. ]]
  for _, s in ipairs({{760,560},{1280,720},{1600,900},{1920,1080},{2560,1440}}) do
    local one = ns.Layout.Compute({width=s[1],height=s[2],handCount=1})
    for n=2,10 do
      local L = ns.Layout.Compute({width=s[1],height=s[2],handCount=n})
      H.ok(math.abs(L.cardW-one.cardW) < 0.001,
        ("%d cards are the same width as one at %dx%d (%.1f vs %.1f)")
          :format(n, s[1], s[2], L.cardW, one.cardW))
      H.ok(math.abs(L.cardH-one.cardH) < 0.001, "and the same height")
    end
  end
end)

H.suite("layout: a full hand leaves a strip of every card worth pointing at",
function(ns, H)
  --[[ THE REPORT: "hovering over some cards with a full hand is impossible."
       The exposed strip of a crowded card is `handPitch` wide, and the floor
       alone does not make it usable -- 30% of a card that the solver has ALSO
       shrunk was 24 pixels at 1280x720. Asserted in pixels, because pixels are
       what you have to hit with a mouse. ]]
  for _, s in ipairs({{760,560},{1280,720},{1920,1080}}) do
    local L = ns.Layout.Compute({width=s[1],height=s[2],handCount=10})
    H.ok(L.handPitch >= 28,
      ("a full hand at %dx%d leaves %.0fpx of each card to point at")
        :format(s[1], s[2], L.handPitch))
  end
end)

H.suite("layout: the hand uses the room that is actually there", function(ns, H)
  --[[ THE REPORT: "the card hand is slightly too narrow." It was much more
       than slightly: a symmetric clamp against an obstacle that is only on one
       side gave the fan 296 of 884 pixels of table at 1280x720. This pins the
       fix by the only measure that matters -- how much of the table a full
       hand spans -- with a floor comfortably under what the solver now gives
       and a ceiling that stops it sprawling into a row. ]]
  for _, s in ipairs({{1280,720},{1600,900},{1920,1080}}) do
    local L = ns.Layout.Compute({width=s[1],height=s[2],handCount=10})
    local span = (L.handSlots[10].x + L.cardW) - L.handSlots[1].x
    local frac = span / L.width
    H.ok(frac > 0.30 and frac < 0.50,
      ("a full hand spans %.0f%% of the window at %dx%d"):format(frac*100, s[1], s[2]))
  end
end)

H.suite("layout: visible hero artwork fits the painted holders at every aspect ratio", function(ns, H)
  for _, size in ipairs({{800,900},{1280,720},{1872,1200},{2400,600}}) do
    local L=ns.Layout.Compute({width=size[1],height=size[2]})
    for _, pair in ipairs({{L.hero,L.heroHolder},{L.foeHero,L.foeHeroHolder}}) do
      local r,holder=pair[1],pair[2]
      H.ok(math.abs(r.x+r.w*14/256-holder.x)<0.001, "visible left edge fits")
      H.ok(math.abs(r.x+r.w*242/256-holder.x-holder.w)<0.001, "visible right edge fits")
      H.eq(r.y,holder.y); H.eq(r.h,holder.h)
    end
  end
end)

H.suite("layout: mana fits the measured artwork and the tilted hand stays clear", function(ns, H)
  for _, size in ipairs({{800,600},{1280,720},{1740,1008},{2560,1080}}) do
    for count=1,10 do
      local L = ns.Layout.Compute({width=size[1],height=size[2],handCount=count,maxMana=10})
      local m, A = L.manaReadout, L.art
      H.ok(math.abs((m.x+m.w/2-A.x)/A.w - 1350/2048) < 0.0001, "count centered on painted blue socket")
      H.ok(math.abs((m.y+m.h/2-A.y)/A.h - 68/1024) < 0.0001, "count aligned to tray center")
      for _, r in ipairs(L.handSlots) do
        local right = r.x+r.w/2 + math.abs(math.cos(r.rot))*r.w/2 + math.abs(math.sin(r.rot))*r.h/2
        H.ok(right < m.x, "even a rotated corner clears the mana socket")
      end
      for _, r in ipairs(L.manaCrystals) do
        H.ok(r.x >= A.x+A.w*1418/2048 and r.x+r.w <= A.x+A.w*1780/2048, "crystal stays inside painted well")
        -- mana_crystal.tga is square; any other ratio squashes the hexagon.
        H.ok(math.abs(r.w/r.h - 1) < 0.001, "crystals keep the art's square proportions")
      end
    end
  end
end)

H.suite("layout: mana crystals match max mana and stay in the window", function(ns, H)
  for _, m in ipairs({ 0, 1, 5, 10 }) do
    local L = ns.Layout.Compute({ width = 1600, height = 900, maxMana = m })
    H.eq(#L.manaCrystals, m, m .. " crystals")
    for i, r in ipairs(L.manaCrystals) do
      H.ok(ns.Layout.InsideWindow(L, r, 2),
           ("crystal %d inside window with maxMana=%d"):format(i, m))
    end
  end
end)

H.suite("layout: mana crystals never exceed the ten-crystal cap", function(ns, H)
  local L = ns.Layout.Compute({ width = 1600, height = 900, maxMana = 99 })
  H.eq(#L.manaCrystals, ns.RULES.MANA_CAP, "capped at the rules constant")
end)

--============================================================= the sweep

H.suite("layout: full invariant sweep across sizes and game states", function(ns, H)
  --[[ The broad net. Every combination of window size and board/hand occupancy,
       asserting the things that must hold everywhere. If a future tweak to the
       design ratios breaks the layout at some awkward size, this is what catches
       it rather than a player at 1366x768. ]]
  local bad = 0
  local checked = 0
  for _, s in ipairs(SIZES) do
    for _, n in ipairs({ 0, 1, 4, 7 }) do
      for _, hn in ipairs({ 0, 1, 5, 10 }) do
        local L = ns.Layout.Compute({
          width = s[1], height = s[2],
          boardCount = n, foeBoardCount = n,
          handCount = hn, foeHandCount = hn,
          hasWeapon = true, maxMana = 10,
        })
        checked = checked + 1
        -- minions inside the field
        for _, r in ipairs(L.boardSlots) do
          if r.x < L.field.x - 1 or r.x + r.w > L.field.x + L.field.w + 1 then bad = bad + 1 end
        end
        -- heroes and rail inside the window
        for _, r in ipairs({ L.hero, L.foeHero, L.endTurn, L.heroPower }) do
          if not ns.Layout.InsideWindow(L, r, 2) then bad = bad + 1 end
        end
        -- hand horizontally inside
        for _, r in ipairs(L.handSlots) do
          if r.x < -1 or r.x + r.w > L.width + 1 then bad = bad + 1 end
        end
        -- aspect preserved
        if math.abs(L.minionW / L.minionH - ns.Layout.design.MINION_W_OVER_H) > 1e-6 then
          bad = bad + 1
        end
      end
    end
  end
  H.ok(checked >= 200, "swept a meaningful number of combinations (" .. checked .. ")")
  H.eq(bad, 0, "zero invariant violations across the sweep")
end)

--=============================================================== choose one

H.suite("layout: the Choose One prompt exists only when a choice is pending", function(ns, H)
  for _, s in ipairs(SIZES) do
    local off = ns.Layout.Compute({ width = s[1], height = s[2], maxMana = 10 })
    H.notOk(off.choosePrompt, "no prompt at " .. s[1] .. "x" .. s[2])
    local on = ns.Layout.Compute({ width = s[1], height = s[2], maxMana = 10,
                                   chooseOne = true })
    H.ok(on.choosePrompt, "prompt at " .. s[1] .. "x" .. s[2])
    H.eq(#on.choosePrompt.cards, 2, "two mode cards at " .. s[1] .. "x" .. s[2])
  end
end)

H.suite("layout: the two mode cards never overlap, and never leave the window", function(ns, H)
  --[[ The prompt is the only element drawn over the board, so nothing else
       constrains it -- if the arithmetic is wrong at some size the two cards
       simply sit on top of each other and the player cannot tell them apart. ]]
  local bad, checked = 0, 0
  for _, s in ipairs(SIZES) do
    for _, n in ipairs({ 0, 7 }) do
      local L = ns.Layout.Compute({
        width = s[1], height = s[2], boardCount = n, foeBoardCount = n,
        handCount = 10, foeHandCount = 10, hasWeapon = true, maxMana = 10,
        chooseOne = true,
      })
      checked = checked + 1
      local P = L.choosePrompt
      local a, b = P.cards[1], P.cards[2]
      if ns.Layout.Overlaps(a, b) then bad = bad + 1 end
      if a.x >= b.x then bad = bad + 1 end          -- ordered left to right
      for _, r in ipairs({ a, b, P.title }) do
        if not ns.Layout.InsideWindow(L, r, 2) then bad = bad + 1 end
        if r.w <= 0 or r.h <= 0 then bad = bad + 1 end
      end
      -- both cards are the same size, and keep the card aspect ratio
      if math.abs(a.w - b.w) > 1e-6 or math.abs(a.h - b.h) > 1e-6 then bad = bad + 1 end
      if math.abs(a.w / a.h - ns.Layout.design.CARD_W_OVER_H) > 1e-6 then bad = bad + 1 end
      -- and they are bigger than a board minion, since reading them is the point
      if a.w <= L.minionW then bad = bad + 1 end
      --[[ The pair plus the gap between them must leave room inside the
           playfield. Layout.Compute has no clamp enforcing this -- it falls out
           of the band ratios -- so THIS is what holds the ratios honest. The
           observed worst case across the whole legal window range is 87%. ]]
      local pairW = (b.x + b.w) - a.x
      if pairW > L.field.w * 0.92 then bad = bad + 1 end
      if b.x <= a.x + a.w then bad = bad + 1 end     -- a real gap between them
    end
  end
  H.eq(bad, 0, "prompt invariants held across " .. checked .. " layouts")
end)

--=================================================================== the fan

H.suite("layout: the hand is a FAN, not a row", function(ns, H)
  --[[ The hand was a straight line of overlapping rectangles, which is a stack
       of cards rather than a hand. A hand is held: the middle rides higher than
       the ends and each card leans away from centre. ]]
  for _, s in ipairs(SIZES) do
    local L = ns.Layout.Compute({ width = s[1], height = s[2], handCount = 9 })
    local slots = L.handSlots
    H.eq(#slots, 9, ("nine cards at %dx%d"):format(s[1], s[2]))

    -- the middle is the highest point, and the two ends are the lowest
    local mid = slots[5].y
    H.ok(mid > slots[1].y, ("middle rides above the left end at %dx%d"):format(s[1], s[2]))
    H.ok(mid > slots[9].y, ("and above the right end at %dx%d"):format(s[1], s[2]))

    -- it rises monotonically to the middle: an arc, not a zigzag
    local rising = true
    for i = 2, 5 do if slots[i].y < slots[i - 1].y - 1e-9 then rising = false end end
    for i = 6, 9 do if slots[i].y > slots[i - 1].y + 1e-9 then rising = false end end
    H.ok(rising, ("one smooth arc at %dx%d"):format(s[1], s[2]))

    -- and they lean away from centre, upright in the middle
    H.ok(slots[1].rot > 0, ("left card leans one way at %dx%d"):format(s[1], s[2]))
    H.ok(slots[9].rot < 0, ("right card leans the other at %dx%d"):format(s[1], s[2]))
    H.ok(math.abs(slots[5].rot) < 1e-9, ("the middle card is upright at %dx%d"):format(s[1], s[2]))
  end
end)

H.suite("layout: one card is flat and upright -- the arc needs no special case", function(ns, H)
  local L = ns.Layout.Compute({ width = 1280, height = 720, handCount = 1 })
  H.eq(#L.handSlots, 1, "one card")
  H.eq(L.handSlots[1].rot, 0, "no lean to speak of")
  local flat = ns.Layout.Compute({ width = 1280, height = 720, handCount = 0 })
  H.eq(#flat.handSlots, 0, "and an empty hand is still empty")
end)

H.suite("layout: the hand runs off the BOTTOM and never off the sides", function(ns, H)
  --[[ The hand deliberately overhangs the bottom edge -- you read the top of a
       card in hand and the rest is below the fold, which is what makes a hand
       feel held rather than laid out on a shelf. So full containment is the
       WRONG invariant here and asserting it would force the cards small.

       What must hold is that enough of every card is on screen to read it, and
       that nothing ever escapes sideways, where there is no fold to hide in. ]]
  for _, s in ipairs(SIZES) do
    local L = ns.Layout.Compute({ width = s[1], height = s[2], handCount = 10 })
    for i, r in ipairs(L.handSlots) do
      H.ok(r.x >= -1 and r.x + r.w <= L.width + 1,
           ("hand card %d stays inside sideways at %dx%d"):format(i, s[1], s[2]))
      local visible = (r.y + r.h) - math.max(r.y, 0)
      H.ok(visible >= r.h * 0.55,
           ("hand card %d is more than half readable at %dx%d"):format(i, s[1], s[2]))
      H.ok(r.y + r.h <= L.height + 1,
           ("hand card %d does not escape upward at %dx%d"):format(i, s[1], s[2]))
    end
  end
end)

--================================================================== the rope

H.suite("layout: the board picture keeps its true shape at every window size", function(ns, H)
  --[[ THE REPORT: the art was squashed into a 16:9 window (docs/13 "Not
       done") -- really, stretched to every window shape. It is scaled to the
       window's height at its true 1.683:1; a narrow window crops only its
       margins, then letterboxes rather than cropping into the deck slots. ]]
  for _, s in ipairs(SIZES) do
    local L = ns.Layout.Compute({ width = s[1], height = s[2], boardCount = 7, foeBoardCount = 7 })
    local A = L.art
    H.ok(math.abs(A.w / A.h - ns.Layout.design.ART_ASPECT) < 1e-6, ("true shape at %dx%d"):format(s[1], s[2]))
    local crop = math.max(0, -A.x) / A.w
    H.ok(crop <= ns.Layout.design.ART_MAX_CROP + 1e-6, ("crops only the margins at %dx%d"):format(s[1], s[2]))
    H.ok(A.y >= -1e-6 and A.y + A.h <= L.height + 1e-6, ("never cropped top or bottom at %dx%d"):format(s[1], s[2]))
    for _, key in ipairs({ "deck", "foeDeck", "endTurn", "hero", "foeHero", "heroPower", "manaReadout" }) do
      H.ok(ns.Layout.InsideWindow(L, L[key], 1), key .. (" on screen at %dx%d"):format(s[1], s[2]))
    end
    for _, r in ipairs(L.historySlots) do H.ok(ns.Layout.InsideWindow(L, r, 1), "history on screen") end
  end
  -- 16:9 fills the height exactly, with a band of curtain either side
  local L = ns.Layout.Compute({ width = 1280, height = 720 })
  H.eq(L.art.h, 720); H.ok(math.abs(L.art.w - 720 * 3840 / 2281) < 1e-6); H.ok(L.art.x > 0)
end)

H.suite("layout: the rope crosses the middle of the board", function(ns, H)
  --[[ It used to be a thin vertical strip against the right edge of the
       playfield, where it read as a progress bar on a piece of furniture. A
       deadline has to cross your field of view. ]]
  for _, s in ipairs(SIZES) do
    local L = ns.Layout.Compute({ width = s[1], height = s[2],
                                  boardCount = 3, foeBoardCount = 3 })
    H.ok(L.rope.w > L.rope.h * 4,
         ("the rope lies along the board at %dx%d"):format(s[1], s[2]))
    H.ok(L.rope.w >= L.field.w * 0.9,
         ("spanning the playfield at %dx%d"):format(s[1], s[2]))
    H.ok(L.rope.x<L.field.x,"rope starts beyond the minion inset")
    H.ok(math.abs(L.rope.x+L.rope.w-(L.endTurn.x-L.art.w*.006))<.001,"rope reaches the turn button frame")
    -- it sits between the two minion rows
    local mid = L.rope.y + L.rope.h / 2
    local mine = L.boardSlots[1]
    local theirs = L.foeBoardSlots[1]
    H.ok(mid > mine.y and mid < theirs.y + theirs.h,
         ("between the two boards at %dx%d"):format(s[1], s[2]))
    H.ok(ns.Layout.InsideWindow(L, L.rope, 1),
         ("and on screen at %dx%d"):format(s[1], s[2]))
  end
end)

