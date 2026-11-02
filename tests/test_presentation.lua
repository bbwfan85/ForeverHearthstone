--[[ tests/test_presentation.lua -- does the board actually LOOK like a game?

  The board used to draw your hand, two rows of minions and an End Turn button.
  Layout had been computing rects for both heroes, both hero powers, both
  weapons, the mana crystals, the enemy hand, the deck piles and the rope since
  the day it was written, and Board drew NONE of them -- and the stage stored
  shake and vignette values that nothing read, while `ns.SoundFor` was called
  and had never been defined anywhere, so the whole addon was silent.

  This file is the guard against all of that coming back. It asserts on the real
  widgets, through the real snapshot, against the strict stub.

  WHAT IT STILL CANNOT PROVE: that any of it is PRETTY. That needs the client
  and an eye -- which is also why `/fh icons` exists.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local function withBoard(ns, fn, opts)
  opts = opts or {}
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }

  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  assert(loadfile("ForeverHearthstone/Client/UI/Board.lua"))("ForeverHearthstone", ns)

  local resolver = ns.Resolver.New({
    printed = ns.PrintedCards,
    manifest = ns.GenericArt.Manifest({}),
    palette = {},
  })
  local intents = {}
  local board = ns.Board.Create({
    resolver = resolver,
    width = opts.width or 1280, height = opts.height or 720,
    onIntent = function(i) intents[#intents + 1] = i end,
  })
  return fn(board, intents, resolver)
end

--- A real snapshot from a real game, which is the only kind worth rendering.
local function liveSnapshot(ns, build)
  local g = H.NewGame()
  H.Mana(g, 1, 7)
  if build then build(g) end
  local c = ns.Controller.New({ game = g, player = 1 })
  return c:Snapshot(), g, c
end

--============================================================ the snapshot

H.suite("presentation: the snapshot carries everything the board must draw", function(ns, H)
  local snap = liveSnapshot(ns)
  H.ok(snap.hero and snap.hero.health, "your hero's health")
  H.ok(snap.foeHero and snap.foeHero.health, "and theirs")
  H.ok(snap.heroPower and snap.heroPower.cardId, "your hero power")
  H.ok(snap.foeHeroPower, "and theirs")
  H.ok(snap.deckCount and snap.deckCount > 0, "the deck count")
  H.ok(snap.playable, "which cards are playable")
  H.ok(snap.canAttack, "and which minions can swing")
  H.eq(snap.heroClass, "MAGE", "the class, for the portrait")
end)

H.suite("presentation: playability comes from the RULES, not from the UI", function(ns, H)
  --[[ A card the board lights green must be a card the engine accepts. A UI
       that judges playability for itself eventually disagrees with the rules,
       and the player is the one who finds out. ]]
  local g = H.NewGame()
  local c = ns.Controller.New({ game = g, player = 1 })
  H.Mana(g, 1, 0)
  local i = H.Hand(g, 1, "CS2_029")              -- Fireball, 4 mana
  H.notOk(c:Snapshot().playable[i], "not playable with no mana")
  H.Mana(g, 1, 10)
  H.ok(c:Snapshot().playable[i], "playable with ten")

  --[[ And the two must AGREE: everything marked playable is accepted, and the
       engine is the judge of both. ]]
  local snap = c:Snapshot()
  for idx, flag in pairs(snap.playable) do
    local card = g.players[1].hand[idx]
    H.eq(flag, ns.Targeting.CanPlay(g, card, 1),
         "slot " .. idx .. " agrees with Targeting")
  end
end)

H.suite("presentation: a summoning-sick minion is not shown as ready", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Put(g, 1, "CS2_182", { sick = true })
  H.Put(g, 1, "CS2_182")
  local c = ns.Controller.New({ game = g, player = 1 })
  local snap = c:Snapshot()
  H.notOk(snap.canAttack[1], "the minion that just landed cannot swing")
  H.ok(snap.canAttack[2], "the one that has been there can")
end)

--============================================================ the board

H.suite("presentation: the board draws the heroes, powers, mana and deck", function(ns, H)
  withBoard(ns, function(board)
    local snap = liveSnapshot(ns)
    board:SetSnapshot(snap)

    H.ok(board.hero.frame:IsShown(), "your hero is on screen")
    H.ok(board.foeHero.frame:IsShown(), "so is theirs")
    H.ok(board.heroPower.frame:IsShown(), "your hero power")
    H.eq(board.hero.health:GetText(), tostring(snap.hero.health),
         "and the health shown is the real number")
    H.eq(board.foeHero.health:GetText(), tostring(snap.foeHero.health), "on both sides")
    H.eq(board.deckPip.count, snap.deckCount, "the deck is drawn from the real count")
    H.ok(board.deckPip.back:IsShown(), "as a stack in its slot")
    H.eq(#board.crystalPool.used, math.min(snap.maxMana, 10), "a crystal per mana crystal")
    H.ok(board.manaText:GetText():find("/"), "with a readable total: " .. board.manaText:GetText())
  end)
end)

H.suite("presentation: each match draws one of the boards, the same on both clients", function(ns, H)
  withBoard(ns, function(board)
    local seen, n = {}, #(ns.HearthstoneArt.boards or {})
    for seed = 1, 40 do
      board:SetBoardArt(seed * 7919)
      seen[board.boardIndex] = true
      local first = board.bg:GetTexture()
      board:SetBoardArt(seed * 7919)
      H.eq(board.bg:GetTexture(), first, "a seed always lands on the same board")
    end
    local count = 0
    for _ in pairs(seen) do count = count + 1 end
    H.eq(count, n, ("matches reach all %d boards"):format(n))
  end)
end)

H.suite("presentation: a deck is a stack that thins as you draw, counted on hover", function(ns, H)
  withBoard(ns, function(board)
    local snap = liveSnapshot(ns)
    local function width(n)
      snap.deckCount = n; board:SetSnapshot(snap); board:Relayout()
      return board.deckPip.pages:IsShown() and board.deckPip.pages:GetWidth() or 0
    end
    local full, half, one = width(30), width(15), width(1)
    H.ok(full > half and half > one and one > 0, ("edges thin: %.1f > %.1f > %.1f"):format(full, half, one))
    H.eq(width(0), 0, "an empty deck leaves an empty slot")
    H.notOk(board.deckPip.back:IsShown(), "no card back either")
    snap.deckCount = 26; board:SetSnapshot(snap); board:Relayout()
    board.deckPip.frame:GetScript("OnEnter")()
    H.ok(board.tooltip:IsShown(), "hovering the deck shows its count")
    H.eq(board.tooltip.text:GetText(), "26 cards in your deck")
    board.foeDeckPip.frame:GetScript("OnEnter")()
    H.ok(board.tooltip.text:GetText():find("opponent's deck", 1, true), "and theirs")
    board.foeDeckPip.frame:GetScript("OnLeave")()
    H.notOk(board.tooltip:IsShown(), "and leaving hides it")
  end)
end)

H.suite("presentation: armour is hidden at zero, shown when it matters", function(ns, H)
  --[[ A permanent "0" next to every hero is noise, and noise trains the eye to
       skip the one place the number matters. ]]
  withBoard(ns, function(board)
    local snap, g, c = liveSnapshot(ns)
    board:SetSnapshot(snap)
    H.eq(board.hero.armor:GetText(), "", "no armour, no number")
    g.players[1].hero.armor = 7
    board:SetSnapshot(c:Snapshot())
    H.eq(board.hero.armor:GetText(), "7", "seven armour, a seven")
  end)
end)

H.suite("presentation: the enemy hand is drawn, face down", function(ns, H)
  withBoard(ns, function(board)
    local snap = liveSnapshot(ns)
    board:SetSnapshot(snap)
    H.eq(#board.foeHandPool.used, snap.foeHandCount,
         "a card back per card they hold")
    for _, wdg in ipairs(board.foeHandPool.used) do
      H.ok(wdg.faceDown, "face down")
      H.ok(wdg.back:IsShown(), "with the back covering the face")
      H.notOk(wdg.skin:IsShown(),"front ornaments cannot peek around transparent back corners")
      H.notOk(wdg.art:IsShown()); H.notOk(wdg.gem:IsShown())
    end
  end)
end)

H.suite("presentation: only the green border says whether you can play a card", function(ns, H)
  --[[ Playability used to be a large green rectangle around the whole card. It
       drowned the art, fought the class frame, and answered the question in the
       wrong place: you look at the cost in the corner to ask "can I play this",
       so that is where the answer belongs. The border is now reserved for the
       card you have SELECTED, which is a different fact. ]]
  withBoard(ns, function(board)
    local g = H.NewGame()
    H.SetActive(g, 1)
    H.Mana(g, 1, 1)
    local cheap = H.Hand(g, 1, "CS2_231")        -- Wisp, 0 mana
    local dear  = H.Hand(g, 1, "CS2_029")        -- Fireball, 4 mana
    local c = ns.Controller.New({ game = g, player = 1 })
    board:SetSnapshot(c:Snapshot())

    local affordable = board.handPool.used[cheap]
    local tooDear    = board.handPool.used[dear]

    -- Hearthstone: neither cost is recoloured and neither card is faded
    local dearCost = tooDear.cost.colour
    H.ok(not dearCost or (dearCost[1] == 1 and dearCost[2] == 1),
         "the unaffordable cost keeps its normal colour")
    H.eq(tooDear.frame:GetAlpha(), 1, "the unplayable card is not faded")
    H.notOk(tooDear.glow:IsShown(), "the unplayable card has no green border")

    -- NO border on either: nothing is selected
    H.ok(affordable.glow:IsShown(), "a playable card has a green border")
    H.notOk(tooDear.glow:IsShown(), "nor on an unplayable one")
  end)
end)

H.suite("presentation: the card you SELECTED is the one with a border", function(ns, H)
  withBoard(ns, function(board)
    local g = H.NewGame()
    H.SetActive(g, 1)
    H.Mana(g, 1, 10)
    local a = H.Hand(g, 1, "CS2_231")
    H.Hand(g, 1, "CS2_029")
    local c = ns.Controller.New({ game = g, player = 1 })
    c:HandleIntent({ kind = "CLICK_HAND", handIndex = a })
    board:SetSnapshot(c:Snapshot())
    H.ok(board.handPool.used[a].glow:IsShown(), "the selected card is ringed")
    H.ok(board.handPool.used[a + 1].glow:IsShown(), "other playable cards remain ringed")
  end)
end)

H.suite("presentation: a minion that can attack is ringed, the selected one differently", function(ns, H)
  withBoard(ns, function(board)
    local g = H.NewGame()
    H.SetActive(g, 1)
    H.Put(g, 1, "CS2_182")
    H.Put(g, 1, "CS2_182", { sick = true })
    local c = ns.Controller.New({ game = g, player = 1 })
    board:SetSnapshot(c:Snapshot())
    H.ok(board.boardPool.used[1].glow:IsShown(), "the ready minion is ringed")
    H.notOk(board.boardPool.used[2].glow:IsShown(), "the sick one is not")

    --[[ Selecting it must look DIFFERENT from merely being ready, or you cannot
         tell what you have picked up. ]]
    c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 1 })
    board:SetSnapshot(c:Snapshot())
    H.ok(board.boardPool.used[1].glow:IsShown(), "still ringed once selected")
    local colour = board.boardPool.used[1].glow.colour
    H.ok(colour and colour[1] > 0.9, "and in a different colour")
  end)
end)

H.suite("presentation: the end turn button says whose turn it is", function(ns, H)
  withBoard(ns, function(board)
    local g = H.NewGame()
    local c = ns.Controller.New({ game = g, player = 1 })
    board:SetSnapshot(c:Snapshot())
    H.eq(board.endTurnLabel:GetText(), "END TURN", "yours")
    g:EndTurn(); g.bus:Drain()
    board:SetSnapshot(c:Snapshot())
    H.eq(board.endTurnLabel:GetText(), "ENEMY TURN", "theirs")
  end)
end)

--============================================================ the hand fan

H.suite("presentation: hovering a card lifts it clear of its neighbours", function(ns, H)
  --[[ In a fanned, overlapping hand this is the ONLY way to read the card you
       are pointing at -- and it is the single most recognisable piece of
       Hearthstone's feel. ]]
  withBoard(ns, function(board)
    local g = H.NewGame()
    H.SetActive(g, 1)
    for _ = 1, 6 do H.Hand(g, 1, "CS2_182") end
    local c = ns.Controller.New({ game = g, player = 1 })
    board:SetSnapshot(c:Snapshot())

    local before = board.handPool.used[3].rect
    local level  = board.handPool.used[3].frame:GetFrameLevel()
    board:SetHover(3)
    local after = board.handPool.used[3].rect
    H.ok(after.y > before.y, "the hovered card rises")
    H.ok(after.w > before.w, "and grows")
    H.ok(board.handPool.used[3].frame:GetFrameLevel() > level,
         "and draws over its neighbours")

    board:SetHover(nil)
    H.eq(board.handPool.used[3].rect.y, before.y, "and settles back when you leave")
  end)
end)

H.suite("presentation: a hand card carries hover scripts at all", function(ns, H)
  --[[ The hover lives on the HIT AREA, not on the picture.

       A card that is its own mouse target moves out from under the pointer the
       instant it reacts to being pointed at: lift it, OnLeave fires, it drops
       back under the cursor, OnEnter fires. That loop is what made the hand
       flicker and appear to vanish. The hit area stays at the card's resting
       rect and never moves, so the pointer's relationship to it is stable. ]]
  withBoard(ns, function(board)
    local snap = liveSnapshot(ns)
    board:SetSnapshot(snap)
    local hit = board.handHitPool.used[1]
    local wdg = board.handPool.used[1]
    H.ok(hit.frame:GetScript("OnEnter"), "OnEnter is wired")
    H.ok(hit.frame:GetScript("OnLeave"), "so is OnLeave")
    H.notOk(wdg.frame:GetScript("OnEnter"),
            "and NOT on the picture, which moves when hovered")
    hit.frame:GetScript("OnEnter")(hit.frame)
    H.eq(board.hoverIndex, 1, "and entering actually raises that card")
  end)
end)

H.suite("presentation: hovering does not tear the hand down", function(ns, H)
  --[[ THE BUG. SetHover called Relayout, which releases every pooled widget in
       the hand and re-acquires it -- hiding and re-showing every frame -- and
       then tweened each card to its new place over 0.16s. Dragging the pointer
       across the hand did that once per card. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    local before = board.handPool.used[1]
    local created = board.handPool.created
    board.tweens = {}

    board:SetHover(1)
    H.eq(board.handPool.used[1], before, "the same widget, not a fresh one")
    H.eq(board.handPool.created, created, "nothing new was built")
    H.eq(#board.tweens, 0, "and the hover does not animate -- it must not lag the pointer")
    H.ok(board.handPool.used[1].frame:IsShown(), "the card never went away")

    --[[ The hit area must stay where it was while the picture lifts, or the
         next mouse move leaves a card that is no longer under the cursor. ]]
    local hit = board.handHitPool.used[1]
    H.eq(hit.rect.y, board.handRects[1].y, "the hit area did not move with it")
    H.ok(board:HandRectFor(1).y > board.handRects[1].y, "but the picture did")
  end)
end)

H.suite("presentation: the hand SLIDES when it changes, and SNAPS when resized", function(ns, H)
  --[[ Drawing a card must make the fan slide apart -- a hand that teleports is
       the most obvious way this looked like a spreadsheet. But a RESIZE must
       not animate, or dragging the window leaves every card chasing the cursor
       a sixth of a second behind. ]]
  withBoard(ns, function(board)
    local g = H.NewGame()
    H.SetActive(g, 1)
    for _ = 1, 4 do H.Hand(g, 1, "CS2_182") end
    local c = ns.Controller.New({ game = g, player = 1 })
    board:SetSnapshot(c:Snapshot())
    H.eq(#board.tweens, 0, "the first render does not animate -- there is nowhere to slide from")

    H.Hand(g, 1, "CS2_182")                     -- draw a fifth card
    board:SetSnapshot(c:Snapshot())
    H.ok(#board.tweens > 0, "the fan slides to make room")

    board.tweens = {}
    board.frame:SetSize(1000, 640)              -- a resize
    H.eq(#board.tweens, 0, "a resize snaps instead of chasing the cursor")
  end)
end)

--============================================================ the juice

H.suite("presentation: an impact shakes the board and puts it back EXACTLY", function(ns, H)
  --[[ The rule that matters: the board must return to where the player put it.
       A shake that applied an absolute position would walk the window across
       the screen over a match, which is the worst kind of slow bug. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    --[[ Moved OFF the origin first, deliberately. Anchored at (0,0) an absolute
         shake and a relative one produce identical numbers, and the test proves
         nothing -- which is exactly what a mutation showed. ]]
    board.frame:ClearAllPoints()
    board.frame:SetPoint("CENTER", UIParent, "CENTER", 120, -60)
    local point, rel, relPoint, x0, y0 = board.frame:GetPoint(1)
    H.eq(x0, 120, "the board starts where the player put it")

    board:Stage():Screen():Shake(8)
    board:TickFX(0.05)
    local _, _, _, x1, y1 = board.frame:GetPoint(1)
    H.ok(x1 ~= x0 or y1 ~= y0, "it moved")

    for _ = 1, 40 do board:TickFX(0.02) end
    local p2, r2, rp2, x2, y2 = board.frame:GetPoint(1)
    H.eq(x2, x0, "and came back to exactly where it was")
    H.eq(y2, y0, "on both axes")
    H.eq(p2, point, "with the same anchor point")

    --[[ AND THE NEXT SHAKE MUST FOLLOW THE WINDOW. If the finished shake keeps
         its old anchor, moving the board and taking another hit snaps it back
         to where it used to be -- a genuinely baffling bug, and one a decaying
         amplitude hides until the player drags the window. ]]
    board.frame:ClearAllPoints()
    board.frame:SetPoint("CENTER", UIParent, "CENTER", -300, 200)
    board:Stage():Screen():Shake(6)
    board:TickFX(0.02)
    local _, _, _, x3, y3 = board.frame:GetPoint(1)
    H.ok(math.abs(x3 - (-300)) <= 6, ("it shakes around the NEW position, not the old one (x=%d)"):format(x3))
    H.ok(math.abs(y3 - 200) <= 6, "on both axes")
    for _ = 1, 40 do board:TickFX(0.02) end
    local _, _, _, x4, y4 = board.frame:GetPoint(1)
    H.eq(x4, -300, "and settles where the player left it")
    H.eq(y4, 200, "on both axes")
  end)
end)

H.suite("presentation: a vignette darkens the screen and then clears", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    board:Stage():Screen():Vignette(0.5)
    H.ok(board.vignette:IsShown(), "the vignette is up")
    board:Stage():Screen():Vignette(0)
    H.notOk(board.vignette:IsShown(), "and gone again -- not left invisible on top")
  end)
end)

H.suite("presentation: particles are born, fall and are recycled", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    board:Stage():Particles("burst_gold", 0, 0, 20)
    H.eq(#board.particles.live, 20, "twenty particles")
    local first = board.particles.live[1]
    local y0 = first.y
    board:TickFX(0.05)
    H.ok(first.y ~= y0, "they move")

    for _ = 1, 100 do board:TickFX(0.02) end
    H.eq(#board.particles.live, 0, "and they die")
    H.ok(#board.particles.pool >= 20, "back into the pool, not discarded")

    --[[ A burst is CAPPED. An uncapped particle system is an addon that hangs
         the client the first time something summons seven minions at once. ]]
    for _ = 1, 50 do board:Stage():Particles("burst_gold", 0, 0, 60) end
    H.ok(board.particles.created <= board.particles.max,
         ("created %d, ceiling %d"):format(board.particles.created, board.particles.max))
  end)
end)

H.suite("presentation: the rope is DRAWN, not just decided", function(ns, H)
  --[[ Choreography.Rope has driven a Burn/Urgency handle since long before
       anything listened. Layout computed a rope rect. Nothing rendered it. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    H.notOk(board.rope.frame:IsShown(), "no rope until the turn is nearly up")

    local stage = board:Stage()
    local rope = stage:Toast("rope", {})
    rope:Urgency(1)
    rope:Burn(0.2)
    H.ok(board.rope.frame:IsShown(), "the rope appears")
    --[[ The rope runs ACROSS the middle of the board now, so it shortens along
         its width rather than its height. It used to be a thin vertical strip
         against the right edge, where it read as a progress bar on a piece of
         furniture instead of a deadline crossing your field of view. ]]
    local long = board.rope.fill:GetWidth()
    rope:Burn(0.9)
    H.ok(board.rope.fill:GetWidth() < long, "and burns down as the turn runs out")
    H.eq(board.rope.track,nil,"burned rope has no background bar")
    rope:Burn(1)
    H.notOk(board.rope.fill:IsShown(),"no final one-pixel remnant")
    H.eq(board.rope.spark:GetAlpha(),0,"ember disappears on completion")
    rope:Burn(0)
    H.ok(board.rope.fill:IsShown(),"next turn restores the rope")
    H.eq(board.rope.fill:GetWidth(),board.L.rope.w,"fresh rope spans its full length")

    local calm = board.rope.spark.w
    rope:Urgency(3)
    rope:Burn(0.95)
    local c = board.rope.fill.colour
    -- Hearthstone's rope keeps its colour; its flame grows (docs/24)
    H.ok(not c or (c[1] == 1 and c[2] == 1 and c[3] == 1), "the rope itself is never recoloured")
    H.ok(board.rope.spark.w > calm, "the flame at its end grows as time runs out")
  end)
end)

H.suite("presentation: a drop toast shows the card and then goes away", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    local toast = board:Stage():Toast("setcard", { cardId = "EX1_116", golden = true })
    H.ok(board.toast.frame:IsShown(), "the toast is up")
    H.eq(board.toast.title:GetText(), ns.PrintedCards["EX1_116"].name, "naming the card")
    H.ok(board.toast.sub:GetText():find("Golden", 1, true), "and saying it is golden: " .. board.toast.sub:GetText())

    toast:Alpha(0)
    H.notOk(board.toast.frame:IsShown(),
            "faded out means HIDDEN -- an invisible frame still eats the mouse")
  end)
end)

H.suite("presentation: every choreography runs against the real board", function(ns, H)
  --[[ The end-to-end check. Each sequence, against real frames, to completion.
       This is what proves the stage implements the interface the choreography
       library actually uses rather than a plausible-looking subset. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns))
    local stage = board:Stage()
    for _, name in ipairs({ "PlayMinion", "PlaySpell", "Attack", "PackDropToast",
                            "SetCardDropToast", "PackCrack", "CardReveal",
                            "Craft", "Disenchant", "Rope" }) do
      local ok, err = pcall(function()
        local tl = ns.Choreography[name](stage, {
          cardIndex = 1, slot = 1, count = 5, rarity = "LEGENDARY",
          golden = true, step = 2, seconds = 1, total = 3, bestRarity = "LEGENDARY",
        })
        tl:RunAll(1 / 60)
      end)
      H.ok(ok, name .. " ran against real frames: " .. tostring(err))
    end
    for _ = 1, 60 do board:TickFX(0.02) end
    H.ok(true, "and the fx loop settled without error")
  end)
end)

--============================================================ sound

H.suite("sound: the game can actually make a noise", function(ns, H)
  --[[ THE BUG THIS FILE WAS PARTLY WRITTEN FOR. Board called `ns.SoundFor`,
       which was never defined anywhere in the project, so every sound resolved
       to nil and the whole addon was silent -- guarded by `and`, which is
       exactly the silent-nil pattern docs/08 SS8.8 says to distrust. ]]
  withBoard(ns, function(board)
    H.ok(ns.SoundFor, "ns.SoundFor exists at all")
    board:SetSnapshot(liveSnapshot(ns))
    board:Stage():Sound("pack_crack")
    H.ok(#Stub.R.sounds > 0, "and a sound reached the client")
  end)
end)

H.suite("sound: ids come from the CLIENT's table, never from memory", function(ns, H)
  --[[ SOUNDKIT is WoW's own table of named constants. Looking a name up in it
       is not recall: a right name gives the id the client itself uses, and a
       wrong one gives nil and silence. No sound id is written down anywhere in
       this project. ]]
  local id = ns.Sounds.For("disenchant")
  H.eq(id, _G.SOUNDKIT.ITEM_REPAIR, "the id is the client's own")
  -- ...unless Hearthstone's own recording is installed, which always wins.
  local path, isFile = ns.Sounds.For("pack_crack")
  H.ok(isFile and path:find("Sounds\\UI\\openpack.mp3", 1, true), "Hearthstone's pack opening")

  local src = io.open("ForeverHearthstone/Client/FX/Sounds.lua"):read("*a")
  local bare = src:match("=%s*{%s*%d%d%d+")
  H.eq(bare, nil, "and there is no numeric sound id in the file")
end)

H.suite("sound: a name this client lacks falls through to the next candidate", function(ns, H)
  --[[ The stub deliberately does not model every name the addon asks for, so
       this is a real fallback rather than a hypothetical one. ]]
  H.eq(_G.SOUNDKIT.IG_ABILITY_PAGE_TURN, nil, "the preferred name is absent here")
  H.eq(ns.Sounds.For("craft"), _G.SOUNDKIT.ITEM_REPAIR,
       "so the second candidate is used")
  H.eq(ns.Sounds.For("no_such_key_at_all"), nil, "and an unknown key is simply silent")
end)

H.suite("sound: a pack's five reveals escalate", function(ns, H)
  --[[ WoW cannot pitch-shift, so the Peggle-style rise is faked with an ordered
       list of distinct sounds indexed by reveal number. If they all came back
       the same, opening a pack would be five identical clicks. ]]
  local seen = {}
  for step = 1, 5 do seen[step] = ns.Sounds.For("card_reveal", step) end
  local distinct = {}
  for _, id in pairs(seen) do distinct[id] = true end
  local n = 0
  for _ in pairs(distinct) do n = n + 1 end
  H.ok(n >= 3, ("%d distinct sounds across the five reveals"):format(n))
  H.ok(seen[1] ~= seen[5], "the first and last are not the same")
end)

H.suite("sound: Hearthstone's flip sits under every reveal, and goldens sing by rarity", function(ns, H)
  Stub.Install(_G); ns.Sounds.ResetMatch()
  for step = 1, 5 do ns.Sounds.Play("card_reveal", step) end
  local flips = 0
  for _, s in ipairs(Stub.R.sounds) do
    if s.file and s.file:find("Sounds\\UI\\flipcard.mp3", 1, true) then flips = flips + 1 end
  end
  H.eq(flips, 5, "each of the five reveals flips like Hearthstone's")
  H.eq(#Stub.R.sounds, 10, "and keeps its own escalating note on top")
  for _, rarity in ipairs({"common", "rare", "epic", "legendary"}) do
    local path = ns.Sounds.For("golden_" .. rarity)
    H.ok(path and path:find("golden" .. rarity .. ".mp3", 1, true), "golden " .. rarity .. " has its own stinger")
  end
  H.eq(ns.Sounds.For("golden_free"), ns.Sounds.For("golden_common"), "a Basic card shares the common one")
end)

H.suite("sound: everything plays on the SFX channel", function(ns, H)
  -- An addon that ignores the player's own sound sliders is an addon people
  -- uninstall.
  Stub.Install(_G)
  ns.Sounds.Play("pack_crack")
  H.ok(#Stub.R.sounds > 0, "it played")
  H.eq(Stub.R.sounds[1].channel, "SFX", "on the SFX channel, not Master")
end)

--============================================================ art

H.suite("art: the nine heroes and their powers have icons", function(ns, H)
  --[[ The face across the table and the button you press every turn: the two
       things a player looks at most, and both were question marks. ]]
  local r = ns.Resolver.New({ printed = ns.PrintedCards,
                              manifest = ns.GenericArt.Manifest({}) })
  for class, heroId in pairs(ns.HERO_ID_BY_CLASS) do
    local d = r:Card(heroId)
    H.eq(d.tier, "manifest", class .. "'s hero has bundled Hearthstone art")
    H.eq(d.icon, ns.HearthstoneArt[heroId], "the actual hero illustration")
  end
  for class, powerId in pairs(ns.HERO_POWER_BY_CLASS) do
    local d = r:Card(powerId)
    H.eq(d.icon, ns.HearthstoneArt[powerId],
         class .. "'s hero power has its own")
  end
end)

H.suite("art: a client that CAN verify a texture is believed", function(ns, H)
  --[[ docs/06 says no API can confirm a texture exists, and for SetTexture that
       is true. GetFileIDFromPath may be able to, so it is feature-detected: if
       Forever has it, 20 guesses become 20 facts; if not, nothing changes and a
       human checks with /fh icons. ]]
  Stub.Install(_G)
  H.eq(ns.GenericArt.Probe([[Interface\Icons\Anything]]), nil,
       "with no such API, the answer is UNKNOWN -- not false")

  _G.GetFileIDFromPath = function(path)
    return path:find("classicon_mage") and 12345 or nil
  end
  H.eq(ns.GenericArt.Probe(ns.GenericArt.CANDIDATES.HERO_MAGE), true, "a real path is true")
  H.eq(ns.GenericArt.Probe([[Interface\Icons\NOT_A_REAL_ICON]]), false, "a bad one is false")

  local saved = {}
  local checked, blank, unknown = ns.GenericArt.AutoAudit(saved)
  H.ok(checked > 0, ("%d candidates were settled without a human"):format(checked))
  H.ok(blank > 0, "including the ones this client does not have")
  H.eq(unknown, 0, "and nothing was left for an eye to check")
  H.eq(saved.blank.HERO_MAGE, nil, "the icon that exists was kept")
  _G.GetFileIDFromPath = nil
end)

H.suite("sound: every key the choreography asks for actually exists", function(ns, H)
  --[[ THE BUG THIS IS FOR. Sounds.KEYS defined `play_minion`, `play_spell`,
       `attack` and `impact`. Choreography asked for "summon", "spell_cast",
       "hit" and "minion_death". None of those four names were in the registry,
       so every sound in a match resolved to nil -- and because silence is a
       valid render, nothing failed. A whole game of Hearthstone made no noise
       at all and no test noticed.

       Two lists in two files that must agree, with no mechanical link between
       them, is exactly the shape that drifts. This is the link. ]]
  local requested = {}
  for line in io.lines("ForeverHearthstone/Client/FX/Choreography.lua") do
    for key in line:gmatch('"Sound",%s*"([a-z_]+)"') do
      requested[key] = true
    end
    --[[ Two keys are BUILT from a rarity at runtime -- "rarity_" .. rarity --
         so the literal in the source is only a prefix. Expand them here
         against the rarities the pin actually has. ]]
    for prefix in line:gmatch('"Sound",%s*"([a-z_]+)"%s*%.%.') do
      for _, rarity in ipairs({ "rare", "epic", "legendary" }) do
        requested[prefix .. rarity] = true
      end
    end
  end

  local n, missing = 0, {}
  for key in pairs(requested) do
    --[[ The bare prefix of a built key ("rarity_" before the rarity is
         appended) is not itself a key. No real key ends in an underscore, so
         that is the whole test for it. ]]
    if not key:match("_$") then
      n = n + 1
      if not ns.Sounds.KEYS[key] then missing[#missing + 1] = key end
    end
  end
  table.sort(missing)
  H.ok(n >= 12, "found the choreography's sound keys to check (" .. n .. ")")
  H.eq(table.concat(missing, ","), "", "every requested key is registered")
end)

H.suite("sound: a match can make a noise", function(ns, H)
  --[[ The four that carry a whole game: a minion landing, a spell going off,
       a hit connecting, and something dying. If these are silent the match is
       silent, whatever else resolves. ]]
  for _, key in ipairs({ "summon", "spell_cast", "hit", "minion_death" }) do
    H.ok(ns.Sounds.KEYS[key] and #ns.Sounds.KEYS[key] > 0,
         key .. " has at least one candidate")
  end
end)

H.suite("presentation: your hero is drawn OVER the resting hand", function(ns, H)
  --[[ THE COMPLAINT. The hand and the hero overlap -- they do in Hearthstone
       too -- but the hand was in front, so the fan covered your own portrait
       and with it your health. The alternative was shrinking the cards until
       they fit underneath, which trades a readable hand for a readable number.

       Neither. The furniture draws above the resting hand, and a card you are
       pointing at still comes above everything, because that one you are
       reading on purpose. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns, function(g)
      for _ = 1, 6 do H.Hand(g, 1, "CS2_182") end
    end))
    local resting = board.handPool.used[3]
    H.ok(board.hero.frame:GetFrameLevel() > resting.frame:GetFrameLevel(),
         "the hero is in front of a resting card")
    H.ok(board.heroPower.frame:GetFrameLevel() > resting.frame:GetFrameLevel(),
         "so is the hero power")
    H.ok(board.crystalPool.used[1].frame:GetFrameLevel()
         > resting.frame:GetFrameLevel(), "and the mana")

    board:SetHover(3)
    H.ok(resting.frame:GetFrameLevel() > board.hero.frame:GetFrameLevel(),
         "but the card you are pointing at comes forward")
  end)
end)

H.suite("presentation: a card in hand shows its mana, art and name -- no more", function(ns, H)
  --[[ A hand card is CUT OFF by the bottom edge. You see the gem, the
       illustration and the name; the rules text and the stats are below the
       fold and you read them by hovering. That is what makes a hand look held
       rather than laid out on a shelf.

       It could not be done while the fan was drawn in FRONT of the hero --
       hanging the cards low enough to look right put them over your own health
       -- so this only works because the furniture draws above the resting hand.
       The two are tested together on purpose: undo either and the other
       becomes wrong. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns, function(g)
      for _ = 1, 6 do H.Hand(g, 1, "CS2_182") end
    end))
    local D = ns.Layout.design
    for i, r in ipairs(board.L.handSlots) do
      H.ok(r.y < 0, ("hand card %d hangs off the bottom"):format(i))
      --[[ The arc lifts the middle of the fan, so a centre card shows a
           little more of itself than a card at either end. The floor is what
           matters: no card may be cut above its name. ]]
      local shown = (r.y + r.h) / r.h
      H.ok(shown >= D.HAND_REVEAL - 0.01,
           ("card %d shows at least the resting amount"):format(i))
      H.ok(shown < 0.95,
           ("card %d is still cut off (%d%% shown)"):format(i, math.floor(shown * 100)))
      H.ok(r.y + r.h <= board.L.height, ("and none escapes upward: %d"):format(i))
    end

    --[[ The name has to survive the cut, or the hand is a row of anonymous
         pictures. It sits a little past halfway down the card. ]]
    H.ok(D.HAND_REVEAL > 0.62, "enough of the card is shown to clear the name")
    H.ok(D.HAND_REVEAL < 0.90, "and not so much that it stops looking held")
  end)
end)

H.suite("presentation: hovering lifts a card ENTIRELY into view", function(ns, H)
  --[[ With the resting card cut off, the hover is the only way to read the
       rules text -- so it has to clear the bottom edge, not merely nudge the
       card upward. A lift that leaves the text off-screen makes the rest of
       the card unreachable. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(liveSnapshot(ns, function(g)
      for _ = 1, 5 do H.Hand(g, 1, "CS2_182") end
    end))
    local resting = board.handRects[2]
    H.ok(resting.y < 0, "it starts below the edge")

    board:SetHover(2)
    local lifted = board:HandRectFor(2)
    H.ok(lifted.y >= 0, "and the whole card is on screen once pointed at")
    H.ok(lifted.h > resting.h, "grown, as well as lifted")
    H.ok(lifted.y + lifted.h <= board.L.height, "without leaving the top")
  end)
end)

H.suite("sound: installed fallback cues cover clients with no SOUNDKIT", function(ns,H)
  local previous=_G.SOUNDKIT
  _G.SOUNDKIT={}
  for _, key in ipairs(ns.Sounds.MATCH_KEYS) do
    local path,isFile=ns.Sounds.For(key)
    H.ok(isFile,"fallback is a packaged sound")
    H.ok(path and (path:match("%.wav$") or path:match("%.ogg$") or path:match("%.mp3$")),"a supported audio path exists")
  end
  _G.SOUNDKIT=previous
end)

H.suite("sound: bundled card recordings and distinct spell effects reach SFX",function(ns,H)
  Stub.Install(_G)
  H.ok(ns.Sounds.PlayCard("attack","CS2_182"))
  H.ok(Stub.R.sounds[#Stub.R.sounds].file:find("ChillwindYeti_Attack1.wav",1,true))
  H.eq(Stub.R.sounds[#Stub.R.sounds].channel,"SFX")
  ns.Sounds.PlayCard("summon","CS2_029","spell_cast")
  H.ok(Stub.R.sounds[#Stub.R.sounds].file:find("Fire_Underlay_Play.wav",1,true))
  ns.Sounds.PlayCard("summon","CS2_024","spell_cast")
  H.ok(Stub.R.sounds[#Stub.R.sounds].file:find("IceElemental_Underlay_Play.wav",1,true))
  local id,isFile=ns.Sounds.For("hit")
  H.ok(isFile,"match impact prefers installed audio to menu clicks")
end)

H.suite("sound: a card event plays every recorded layer and no synthetic hit",function(ns,H)
  Stub.Install(_G)
  local id,entry
  for cardId,sounds in pairs(ns.CardSounds) do
    if type(sounds.summon)=="table" and #sounds.summon>1 then id,entry=cardId,sounds.summon; break end
  end
  H.ok(id,"catalog includes multi-layer card events")
  ns.Sounds.PlayCard("summon",id,"summon")
  H.eq(#Stub.R.sounds,#entry,"voice and effect layers both play")
  for i,name in ipairs(entry) do H.ok(Stub.R.sounds[i].file:find(name,1,true)) end
  local path=ns.Sounds.For("hit")
  H.ok(path:find("Sword1_Attack_Underlay",1,true),"attack impact is a recording")
end)

H.suite("sound: Magma Rager lands with Hearthstone's card placement, not armor",function(ns,H)
  Stub.Install(_G); ns.Sounds.ResetMatch()
  ns.Sounds.PlayCard("summon","CS2_118","summon")
  H.ok(Stub.R.sounds[#Stub.R.sounds].file:find("Sounds\\UI\\cardplace.mp3",1,true),
       "an unrecorded minion uses the game's own card-on-table thud")
  H.notOk(ns.MatchRecordings.summon,"armor is not a generic unit sound")
  -- War Golem has no recording either, and is heavy: the thud plus wood beneath.
  local n=#Stub.R.sounds
  ns.Sounds.PlayCard("summon","CS2_186","summon")
  H.eq(#Stub.R.sounds,n+2,"a heavy minion lands on two layers")
  local wood=Stub.R.sounds[#Stub.R.sounds].file
  H.ok(wood:find("Placement\\impactWood_heavy_",1,true))
  ns.Sounds.PlayCard("summon","CS2_186","summon")
  H.ok(Stub.R.sounds[#Stub.R.sounds].file~=wood,"successive heavy landings vary")
end)

H.suite("sound: hero attacks keep effects without spamming one voice line",function(ns,H)
  Stub.Install(_G); ns.Sounds.ResetMatch()
  ns.Sounds.PlayHeroAttack("HERO_06")
  H.eq(#Stub.R.sounds,1)
  ns.Sounds.PlayHeroAttack("HERO_06"); ns.Sounds.PlayHeroAttack("HERO_06")
  H.eq(#Stub.R.sounds,1,"rapid swings do not repeat the same phrase")
  Stub.Advance(13)
  ns.Sounds.PlayHeroAttack("HERO_06")
  H.eq(#Stub.R.sounds,2,"voice returns after enough time and swings")
end)

H.suite("sound: variants rotate within a card event without replacing its identity",function(ns,H)
  Stub.Install(_G); ns.Sounds.ResetMatch()
  local old=ns.CardSoundVariants.CS2_182
  ns.CardSoundVariants.CS2_182={attack={{"first","second"}}}
  ns.Sounds.PlayCard("attack","CS2_182"); ns.Sounds.PlayCard("attack","CS2_182")
  H.ok(Stub.R.sounds[1].file:find("first.wav",1,true))
  H.ok(Stub.R.sounds[2].file:find("second.wav",1,true))
  ns.CardSoundVariants.CS2_182=old
end)
