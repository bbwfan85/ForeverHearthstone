--[[ Client/UI/Board.lua

  THE FRAME BINDING. This is the first file in the project that touches the WoW
  API, and it is deliberately the dumbest one.

  Its whole job is:
    * own a resizable, movable window
    * create and POOL the card widgets
    * ask Layout.lua where everything goes, and put it there
    * expose a `stage` that Choreography.lua can animate
    * turn mouse input into intents (play card at index N, attack X with Y)

  It contains no game rules, no timing decisions, and no layout arithmetic. If you
  find yourself writing a rule or a pixel offset here, it belongs in Engine/ or
  Layout.lua respectively.

  API SURFACE: Mainline / interface 16001. Notably SetResizeBounds, NOT the
  removed SetMinResize/SetMaxResize. See docs/07-PLATFORM-CORRECTION.md.

  POOLING: widgets are created once and reused. WoW cannot destroy a frame, so
  creating one per render leaks for the session. Every acquire goes through the
  pool and every release hides rather than discards.
]]
local ADDON, ns = ...
local Layout = ns.Layout

--[[ The widget library. Card frames, pools, portraits, mana crystals, the rope,
     toasts and the particle system all live in Client/UI/Widgets.lua, so this
     file and the collection screen draw cards with the SAME code -- which is
     the guarantee that a card looks identical in your collection and on the
     table, including how it degrades when its art is missing. ]]
local W = ns.Widgets
local newPool, poolAcquire, poolReleaseAll = W.NewPool, W.Acquire, W.ReleaseAll
local makeCard, cardApplyRect, cardSetDescriptor = W.New, W.ApplyRect, W.SetDescriptor
local ART = "Interface\\AddOns\\ForeverHearthstone\\Art\\"

--[[ Visual randomness has its own generator. Drawing a spell must never
     consume math.random: practice matches are seeded from it, so a volley of
     Arcane Missiles used to change the NEXT game's shuffle. That covers
     everything the board draws: where sprites go, the particles every burst
     throws and the table's shake, not just a spell's aim. ]]
local fxSeed = 12345
local function fxRandom(a, b)
  fxSeed = (fxSeed * 1103515245 + 12345) % 2147483648
  local v = fxSeed / 2147483648
  if a then return a + math.floor(v * (b - a + 1)) end
  return v
end

local Board = {}
Board.__index = Board
ns.Board = Board

--[[ WHAT DRAWS OVER WHAT.

     The hand sits at the bottom of the window and the hero sits in the alcove
     the board art paints just above it, so the two overlap -- in Hearthstone
     they overlap too. What matters is which one is in front.

     It used to be the hand, which meant the fan covered your own hero portrait
     and with it your health. So the FURNITURE -- hero, hero power, weapon, deck
     and mana -- draws above the resting hand, and a card you are actually
     pointing at comes above everything, because that one you are reading on
     purpose. ]]
local HAND_LEVEL      = 10    -- + the card's index
local FURNITURE_LEVEL = 60
local HOVERED_LEVEL   = 120
--[[ Spell sprites and particles. They used to be drawn at the board's own
     level, UNDER the hero portraits and hero powers (FURNITURE_LEVEL), so a
     Fireball to the face, a heal on your hero or a Secret setting vanished
     behind the portrait it was aimed at. Above the furniture and its secret
     pips; still under a hovered or dragged card. ]]
local SPELL_LEVEL     = FURNITURE_LEVEL + 10

-- ============================================================== construction

function Board.Create(opts)
  opts = opts or {}
  local b = setmetatable({}, Board)
  b.opts = opts
  b.resolver = opts.resolver
  b.onIntent = function(intent)
    if b.presentationLocked then return false end
    if (b.snapshot and b.snapshot.over) or (b.pendingSnapshot and b.pendingSnapshot.over) then return false end
    if opts.onIntent then return opts.onIntent(intent) end
  end

  local minW, minH = Layout.MinSize()
  local maxW, maxH = Layout.MaxSize()

  local f = CreateFrame("Frame", "ForeverHearthstoneBoard", UIParent)
  f:SetSize(opts.width or 1280, opts.height or 720)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("FULLSCREEN")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:SetUserPlaced(false)   -- the shared window rect (W.SharedWindow) places it
  --[[ Mainline call. SetMinResize/SetMaxResize were removed in 10.0; using them
       would silently fail on Forever. The bounds come from Layout so the window
       can never be dragged below the legibility floor. ]]
  f:SetResizable(true)
  f:SetResizeBounds(minW, minH, maxW, maxH)
  f:RegisterForDrag("LeftButton")
  --[[ The window moves when dragged by its margins -- never by the play
       surface, which in Hearthstone is something you CLICK: a click on empty
       sand raises a little puff of dust (Board:ClickSurface). ]]
  f:SetScript("OnDragStart", function(self)
    if not b:OnPlaySurface(b:CursorInBoard()) then self:StartMoving() end
  end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then b:ClickSurface(b:CursorInBoard()) end
  end)
  b.frame = f
  -- Dismissal is available even if later board construction fails. The
  -- corner is every window's: close, Main Menu, the speaker (its volume on
  -- hover). Leaving the table outside a live duel lands on the main menu
  -- (Main:RequestDuelExit), so both buttons go there.
  b.corner = W.WindowControls(f, { onHome = function() f:Hide() end, onToggleMute = opts.onToggleMute })
  b.close, b.mute, b.home = b.corner.close, b.corner.speaker, b.corner.home
  b.volume = b.mute.volume
  --[[ CONCEDE, as Hearthstone's options menu offers it, beside Main Menu --
       for a bot game as well as a duel. Main asks before it gives up the
       match; only a game still being played shows it. ]]
  b.concede = W.MenuButton(f, "Concede", function()
    if opts.onConcede then opts.onConcede() end
  end)
  b.concede:SetSize(W.CORNER.homeW, W.CORNER.homeH)
  b.corner:Add(b.concede)
  b.concede:Hide()
  f:SetScript("OnHide",function()
    --[[ Hiding WoW's whole UI (Alt+Z, a cinematic) hides the board with it
         but leaves it SHOWN. That is not leaving the table: no menu, no
         "Leave this duel?" waiting when the UI comes back. The hiss pauses
         and relights on its own. ]]
    if f:IsShown() then b:PauseRopeFuse(); return end
    W.StopShake(b.shake)
    -- leaving the table silences its victory or defeat, however long it runs
    b:StopResultSound()
    --[[ ...and the rope's hiss. The fuse is paused and relit only by TickFX,
         which does not run while the board is hidden, so going to the main
         menu mid-duel left the rope burning in your ears. It lights again
         when you come back, if the rope is still going. ]]
    b:PauseRopeFuse()
    if opts.onClose then opts.onClose() end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "ForeverHearthstoneBoard") end

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.06, 0.05, 0.04, 0.92)
  b.bg = bg
  b:SetBoardArt(nil)

  -- The shared resize grip, bottom-right, same as every other window.
  b.grip = W.ResizeGrip(f, minW, minH, maxW, maxH, function() b:Relayout() end)

  -- Recompute on any size change. OnSizeChanged fires continuously while
  -- dragging the grip, which is exactly what we want: the board reflows live.
  f:SetScript("OnSizeChanged", function() b:Relayout() end)

  b.handPool  = newPool(function(p) return makeCard(p) end)
  b.boardPool = newPool(function(p) local w = makeCard(p); w.inPlay = true; return w end)
  --[[ The hand's mouse targets, separate from its pictures. See
       Widgets.NewHitArea: a card that is its own hit area moves out from under
       the pointer the moment it reacts to being pointed at. ]]
  b.handHitPool = newPool(function(p) return W.NewHitArea(p) end)

  --[[ The Choose One prompt. A dimmer that eats every click behind it, plus a
       pool of exactly two mode cards. The dimmer is a Button rather than a
       Frame so that clicking off the prompt cancels the play instead of
       falling through to the board underneath. ]]
  b.dimmer = CreateFrame("Button", nil, f)
  b.dimmer:EnableMouse(true)
  b.dimmer:SetFrameLevel(300)
  local dt = b.dimmer:CreateTexture(nil, "BACKGROUND")
  dt:SetAllPoints()
  dt:SetColorTexture(0, 0, 0, 0.72)
  b.dimmer:SetScript("OnClick", function()
    b.onIntent({ kind = "CANCEL_MODE" })
  end)
  b.dimmer:Hide()
  b.choosePool = newPool(function(p) return makeCard(p) end)
  -- Prompt lettering floats above the dimmers (300, mulligan 200) that it
  -- captions; on the board frame itself it was dimmed along with the table.
  b.promptLayer = CreateFrame("Frame", nil, f)
  b.promptLayer:SetAllPoints(f); b.promptLayer:SetFrameLevel(330); b.promptLayer:EnableMouse(false)
  b.chooseTitle = b.promptLayer:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(b.chooseTitle, "caption", nil, 18, W.Colors.white)
  b.chooseTitle:SetText("Choose One")
  b.chooseTitle:Hide()

  --[[ THE END TURN BUTTON: the stone plaque painted on the table itself, cut
       from the full-resolution painting along its outline
       (tools/build_turn_button.py), its gold face lit END TURN yellow. It is
       drawn exactly over the painted plaque, and all of it is the click
       target. On their turn the face is the
       drained grey glaze (turn-button-enemy.tga) reading ENEMY TURN; never
       green. ]]
  b.endTurn = CreateFrame("Button", nil, f)
  b.endTurn:EnableMouse(true)
  b.endTurn:SetFrameLevel(120)
  b.endTurn:SetScript("OnClick", function()
    local snap = b.snapshot or {}
    if snap.myTurn and not snap.over and not snap.mulligan then ns.Sounds.Play("end_turn") end
    b.onIntent({ kind = "END_TURN" })
  end)
  b.endTurnBg = b.endTurn:CreateTexture(nil, "ARTWORK")
  b.endTurnBg:SetAllPoints()
  b.endTurnBg:SetTexture(ART .. "turn-button.tga")
  b.endTurnGlow = b.endTurn:CreateTexture(nil, "OVERLAY", nil, -1)
  b.endTurnGlow:SetTexture(ART .. "turn-button.tga")
  b.endTurnGlow:SetBlendMode("ADD")
  b.endTurnGlow:SetAllPoints()
  b.endTurnGlow:SetAlpha(0)
  b.endTurnLabel = b.endTurn:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(b.endTurnLabel, "endTurn", nil, 14)
  b.endTurnLabel:SetPoint("CENTER", b.endTurn, "CENTER", 0, 0)
  b.endTurnLabel:SetText("END TURN")
  W.AutoFit(b.endTurnLabel, { w = 80, h = 16, font = ns.Fonts.TITLE, size = 14, min = 6 })
  b.endTurn:SetScript("OnEnter", function() b:RefreshEndTurn(true) end)
  b.endTurn:SetScript("OnLeave", function() b:RefreshEndTurn(false) end)

  --[[ EVERYTHING THE BOARD WAS MISSING.

       Layout has computed rects for both heroes, both hero powers, both
       weapons, the mana crystals, the enemy hand, the deck piles and the rope
       since the day it was written -- and Board drew NONE of them. A "board"
       was a row of your minions, a row of theirs, and an End Turn button. These
       are the widgets that make it a game of Hearthstone. ]]
  b.hero        = W.NewPortrait(f)
  b.foeHero     = W.NewPortrait(f)
  b.heroPower   = W.NewPortrait(f, "hero_power")
  b.foeHeroPower= W.NewPortrait(f, "hero_power")
  b.weapon      = W.NewPortrait(f, "inplay_weapon")
  b.foeWeapon   = W.NewPortrait(f, "inplay_weapon")
  -- The decks are stacks in the rail's slots; the count shows on hover.
  b.deckPip     = W.NewDeckStack(f)
  b.foeDeckPip  = W.NewDeckStack(f)
  for _, pair in ipairs({ { b.deckPip, "in your deck" }, { b.foeDeckPip, "in your opponent's deck" } }) do
    local deck, where = pair[1], pair[2]
    deck.frame:SetScript("OnEnter", function() b:ShowDeckCount(deck, where) end)
    deck.frame:SetScript("OnLeave", function() b.tooltip:Hide() end)
  end
  for _, part in ipairs({ b.weapon, b.foeWeapon }) do part.frame:Hide() end

  b.hero.frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
  b.hero.frame:SetScript("OnClick", function(_, button)
    if button == "RightButton" then return b:ToggleEmotes() end
    b:TargetClick({ kind = "CLICK_HERO" })
  end)
  --[[ Your hero is an attacker too, whenever it is holding a weapon, so it is
       aimed exactly as a minion is. ]]
  b.hero.frame:SetScript("OnDragStart", function()
    b:BeginTargetDrag({ kind = "CLICK_HERO" })
  end)
  b.hero.frame:SetScript("OnDragStop", function() b:DropOnTarget() end)
  --[[ Right-click their hero to squelch their emotes, as in Hearthstone: a
       defence against someone spamming the wheel. Again to hear them. ]]
  b.foeHero.frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
  b.foeHero.frame:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      -- a right-click that cancelled an aim at their face is only that
      if b.cancelledAt and (GetTime and GetTime() or 0) - b.cancelledAt < 0.5 then return end
      return b:ToggleSquelch()
    end
    b:TargetClick({ kind = "CLICK_FOE_HERO" })
  end)
  --[[ THE HERO POWER IS AIMED BY DRAGGING IT.

       Click-then-click still works, because it has to: a hero power with no
       target (Armor Up, Lesser Heal on no legal target) is a button, and some
       people prefer two clicks. But Fireblast is a thing you drag onto a face,
       and having to click the portrait and then click a target was the one
       interaction in the game that did not match the gesture it is copying.

       The drag START begins the ordinary targeting flow -- the same intent the
       click sends -- so the controller raises the same pending target request
       and the board lights the same legal set. The drag STOP just supplies the
       click that would have followed. No new path through the rules. ]]
  b.heroPower.frame:SetScript("OnClick", function()
    b:TargetClick({ kind = "HERO_POWER" })
  end)
  b.heroPower.frame:SetScript("OnDragStart", function()
    b:BeginTargetDrag({ kind = "HERO_POWER" })
  end)
  b.heroPower.frame:SetScript("OnDragStop", function()
    b:DropOnTarget()
  end)
  for _,widget in ipairs({b.hero,b.foeHero,b.heroPower}) do
    widget.frame:SetScript("OnMouseDown",function() b.suppressTargetClick=nil; b.targetDropConsumed=nil end)
  end

  b.crystalPool = newPool(function(p) return W.NewCrystal(p) end)
  b.foeHandPool = newPool(function(p) return makeCard(p) end)
  --[[ A secret is Hearthstone's class-coloured gem with a "?" on it -- on
       both sides of the table, since even your own are shown as the gem and
       named only on hover. ]]
  b.secretPool  = newPool(function(p)
    local fr = CreateFrame("Button", nil, p)
    fr:EnableMouse(true)
    local gem = fr:CreateTexture(nil, "ARTWORK"); gem:SetAllPoints()
    local mark = fr:CreateFontString(nil, "OVERLAY")
    mark:SetPoint("CENTER", fr, "CENTER", 0, 0)
    W.ApplyStyle(mark, "mark")
    mark:SetText("?")
    return { frame = fr, gem = gem, mark = mark }
  end)

  --[[ THE MULLIGAN. Its own dimmer, so the board behind it is visible but
       untouchable -- a board you can see and click at, which then refuses every
       click, is worse than one you cannot see. ]]
  b.mulliganDim = CreateFrame("Button", nil, f)
  b.mulliganDim:EnableMouse(true)
  b.mulliganDim:SetFrameLevel(200)
  local mdt = b.mulliganDim:CreateTexture(nil, "BACKGROUND")
  mdt:SetAllPoints()
  mdt:SetColorTexture(0, 0, 0, 0.78)
  b.mulliganDim:SetScript("OnClick", function() end)   -- swallow, never fall through
  b.mulliganDim:Hide()
  b.mulliganPool = newPool(function(p) return makeCard(p) end)
  b.mulliganTitle = b.promptLayer:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(b.mulliganTitle, "caption", nil, 18, W.Colors.white)
  b.mulliganTitle:SetShadowOffset(2, -2); b.mulliganTitle:SetShadowColor(0, 0, 0, .9)
  b.mulliganTitle:Hide()
  --[[ The same painted tavern button as Rematch / Main Menu after a game.
       It was a flat amber pill (play-button.tga) stretched to another aspect,
       the one piece of the mulligan that looked like a web page. ]]
  b.mulliganConfirm = W.MenuButton(f, "", function()
    b.onIntent({ kind = "CONFIRM_MULLIGAN" })
  end)
  b.mulliganConfirm:SetFrameLevel(320)
  b.mulliganConfirmBg = b.mulliganConfirm.bg
  b.mulliganConfirmLabel = b.mulliganConfirm.text
  b.mulliganConfirm:Hide()

  --[[ The aiming arrow and the card reader. Both are pure presentation: they
       ask the engine nothing, so they live here rather than behind an intent. ]]
  --[[ THE CARD BEING PLAYED, which is no longer in the hand.

       A play animation runs for a third of a second AFTER the card has left
       your hand -- and the stage used to hand it `handPool.used[handIndex]`,
       which by then is whichever card SLID INTO that slot. So playing a card
       took the next one along and faded it to nothing, and since the fade
       finished after the next relayout it left a live card at zero alpha:
       a card that had simply gone invisible.

       The generation counter cannot help here. The widget it grabs is live and
       current; it is the right frame for the wrong card. So the played card
       gets a frame of its OWN, copied out of the hand before the action is
       applied, and the hand is free to close up behind it. ]]
  b.flyingCard = makeCard(f)
  b.flyingCard.frame:EnableMouse(false)
  b.flyingCard.frame:SetFrameLevel(300)
  b.flyingCard.frame:Hide()

  b.arrow = W.NewArrow(f)
  b.foeArrow = W.NewArrow(f)   -- the opponent's aim, seen (SetOpponentHover)
  b.inspect = W.NewInspect(f)
  b.inspect.frame:SetScript("OnClick", function() b:HideInspect() end)
  b.inspect.frame:EnableMouseWheel(true)
  b.inspect.frame:SetScript("OnMouseWheel",function(_,delta)
    local count=#(b.inspectEffects or {})
    b.inspectOffset=math.max(0,math.min((b.inspectOffset or 0)-delta,math.max(0,count-3)))
    b:RefreshInspectEffects()
  end)

  b.rope = W.NewRope(f)
  b.vignette = W.NewVignette(f)
  b.spellLayer = CreateFrame("Frame", nil, f)
  b.spellLayer:SetAllPoints()
  b.spellLayer:SetFrameLevel(SPELL_LEVEL)
  b.particles = W.NewParticles(b.spellLayer)
  b.shake = W.NewShake(f)
  b.toast = W.NewToast(UIParent)
  b.toast.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -180)

  --[[ The readout sits in the trough at the bottom of the board, which is
       exactly where the hand fans across. A FontString created on the board
       frame draws at the BOARD's level -- underneath every card in the hand --
       so the mana count was being covered by the cards. The crystals were
       fine, because they are frames and were given the furniture level; the
       number was the one piece that was not. ]]
  b.manaHolder = CreateFrame("Frame", nil, f)
  b.manaHolder:SetAllPoints()
  b.manaText = b.manaHolder:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(b.manaText, "number", nil, 14)
  b.foeManaText = b.manaHolder:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(b.foeManaText, "number", nil, 14)
  -- Overload owed NEXT turn, beside each readout: locked crystals only show it once it lands
  b.overloadText = b.manaHolder:CreateFontString(nil, "OVERLAY")
  b.foeOverloadText = b.manaHolder:CreateFontString(nil, "OVERLAY")

  --[[ One OnUpdate for the whole board: particles, the shake, and the tweens
       that make the hand slide instead of teleport. It STOPS ITSELF when
       nothing is moving -- an OnUpdate that runs forever for nothing is the
       most common way an addon costs frames. ]]
  b.tweens = {}
  b.fx = CreateFrame("Frame", nil, f)
  b.fx:SetScript("OnUpdate", function(_, dt) b:TickFX(dt) end)

  b.state = { handCount = 0, boardCount = 0, foeBoardCount = 0,
              foeHandCount = 0, maxMana = 0 }
  b.L = nil
  b.banner = CreateFrame("Frame", nil, f)
  b.banner:SetFrameLevel(400)
  --[[ THE TURN BANNER: Hearthstone's "YOUR TURN" -- big gold lettering that
       swells in over the table, holds and fades. Behind it only a feathered
       haze and two fine gold rules (turn-banner.tga), so it reads on every
       board without a badge pasted over the painted art. Only for YOUR turn:
       Hearthstone announces nothing when the opponent's turn begins (the End
       Turn plaque reads ENEMY TURN), so neither do we. The lettering fills
       the band between the rules (y .27-.73). Animated in TickFX. ]]
  b.banner:SetSize(460, 230)
  b.banner:SetPoint("CENTER", f, "CENTER", 0, 0)
  b.banner.bg = b.banner:CreateTexture(nil, "BACKGROUND")
  b.banner.bg:SetAllPoints(); b.banner.bg:SetTexture(ART .. "turn-banner.tga")
  --[[ THE LIGHT BEHIND IT. Hearthstone's "YOUR TURN" bursts out of a gold
       flare; on the shade and two rules alone it read as bare lettering (the
       in-client tour, docs/39). A soft gold bloom under fanned rays, both
       additive, from the spell-effect textures already shipped. ]]
  b.banner.bloom = b.banner:CreateTexture(nil, "BORDER", nil, 0)
  b.banner.bloom:SetTexture(ART .. "fx-orb.tga"); b.banner.bloom:SetBlendMode("ADD")
  b.banner.bloom:SetVertexColor(1, .72, .22, .85)
  b.banner.bloom:SetPoint("CENTER"); b.banner.bloom:SetSize(460 * 0.95, 230 * 0.7)
  b.banner.rays = b.banner:CreateTexture(nil, "BORDER", nil, 1)
  b.banner.rays:SetTexture(ART .. "fx-rays.tga"); b.banner.rays:SetBlendMode("ADD")
  b.banner.rays:SetVertexColor(1, .82, .38, .55)
  b.banner.rays:SetPoint("CENTER"); b.banner.rays:SetSize(460 * 1.1, 230 * 1.1)
  b.banner.text = b.banner:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(b.banner.text, "banner", nil, 56)
  b.banner.text:SetShadowOffset(3, -3); b.banner.text:SetShadowColor(0, 0, 0, 0.9)
  b.banner.text:SetPoint("CENTER", b.banner, "CENTER", 0, 0)
  b.banner.text:SetJustifyH("CENTER")
  W.AutoFit(b.banner.text, { w = 460 * 0.74, h = 230 * 0.40, font = ns.Fonts.TITLE,
                             size = 56, min = 18, flags = "THICKOUTLINE" })
  b.banner:Hide()

  --[[ THE RESULT, as Hearthstone ends a game (tools/build_result_art.py):
       the table drained to grey; your hero in a gilded arch under a crown,
       laurels, trumpets and blue banners; a wooden plaque across its foot
       reading "Victory!". A defeat keeps the arch and the plaque but not the
       laurels, and the portrait is cracked and drained. ]]
  b.resultDimLayer = CreateFrame("Frame", nil, f)
  b.resultDimLayer:SetAllPoints(f); b.resultDimLayer:SetFrameLevel(398); b.resultDimLayer:EnableMouse(false)
  b.resultDim = b.resultDimLayer:CreateTexture(nil, "OVERLAY")
  b.resultDim:SetAllPoints(b.resultDimLayer); b.resultDim:SetColorTexture(0, 0, 0, 0.35); b.resultDim:Hide()
  local res = CreateFrame("Frame", nil, f)
  res:SetFrameLevel(405); res:EnableMouse(false); res:Hide()
  res.portrait = res:CreateTexture(nil, "ARTWORK")
  res.portraitMask = W.Mask(res, res.portrait, "mask-result-arch")
  res.crack = res:CreateTexture(nil, "ARTWORK", nil, 3)
  res.crack:SetTexture(ART .. "hero-crack.tga")
  res.ornament = res:CreateTexture(nil, "OVERLAY", nil, 0)
  res.ribbon = res:CreateTexture(nil, "OVERLAY", nil, 1)
  res.ribbon:SetTexture(ART .. "result-plaque.tga")
  res.text = res:CreateFontString(nil, "OVERLAY", nil, 7)
  W.ApplyStyle(res.text, "result", nil, 54)
  res.text:SetShadowOffset(2, -2); res.text:SetShadowColor(0, 0, 0, 0.9)
  res.text:SetJustifyH("CENTER")
  W.AutoFit(res.text, { w = 300, h = 60, font = ns.Fonts.TITLE, size = 54, min = 16, flags = "THICKOUTLINE" })
  b.result = res
  b.skulls = {}
  b.skullLayer=CreateFrame("Frame",nil,f)
  b.skullLayer:SetAllPoints(f)
  b.skullLayer:SetFrameLevel(300)
  b.skullLayer:EnableMouse(false)
  for i=1,2 do
    local skull = b.skullLayer:CreateTexture(nil, "OVERLAY", nil, 7)
    -- Hearthstone's own lethal skull, not WoW's raid marker.
    skull:SetTexture(ART .. "skull.tga")
    skull:Hide(); b.skulls[i] = skull
  end
  b.projectiles = {}
  b.hitLabels = {}
  b.history = {}
  b.historyButtons = {}
  for i = 1, 8 do
    local button = CreateFrame("Button", nil, f)
    button:SetFrameLevel(100)
    button:EnableMouse(true)
    --[[ Hearthstone's play-history tile: the card's art in a gilded rim, the
         owner shown by a thin band inside it (red theirs, blue yours), and
         what was done by the game's own badge in the corner -- the attack
         sword, the hero-power ring or the mana gem. No WoW spell icons. ]]
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0.07, 0.04, 0.025, 1)
    button.backing = bg
    button.border = button:CreateTexture(nil, "BORDER")
    button.border:SetPoint("TOPLEFT", 2, -2); button.border:SetPoint("BOTTOMRIGHT", -2, 2)
    button.border:SetColorTexture(0.16, 0.45, 0.75, 1)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 4, -4)
    button.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    button.icon:SetTexCoord(0.14, 0.82, 0.06, 0.92)
    button.rim = ns.Widgets.GoldFrame(button, 5, "ARTWORK")
    button:SetScript("OnSizeChanged", function(_, w, h) button.rim:Layout(w, h) end)
    button.actionIcon = button:CreateTexture(nil, "OVERLAY")
    button.actionIcon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
    button.text = button:CreateFontString(nil, "OVERLAY")
    W.ApplyStyle(button.text, "mark", nil, 10)
    button.text:SetPoint("CENTER"); button.text:SetWidth(80)
    button:SetScript("OnEnter", function()
      local entry = b.history[i]
      if entry then b:ShowHistory(button, entry) end
    end)
    button:SetScript("OnLeave", function() b.tooltip:Hide(); b.historyPreview:Hide() end)
    button:Hide()
    b.historyButtons[i] = button
  end
  b.historyPreview = CreateFrame("Frame", nil, f)
  b.historyPreview:SetFrameLevel(450)
  b.historyPreview:EnableMouse(false)
  b.historyPreview.source = makeCard(b.historyPreview)
  b.historyPreview.target = makeCard(b.historyPreview)
  b.historyPreview.source.frame:EnableMouse(false)
  b.historyPreview.target.frame:EnableMouse(false)
  b.historyPreview:Hide()
  --[[ Hover text is Hearthstone's parchment keyword box (W.HSPanel), not a
       dark slab. Hovering something on the board shows the CARD beside it,
       as Hearthstone does, with a box per keyword it has. ]]
  b.tooltip = W.HSPanel(f)
  b.tooltip:SetFrameLevel(450)
  b.tooltip:EnableMouse(false)
  b.tooltip.text:SetJustifyH("LEFT")
  b.tooltip:Hide()
  b.hoverCard = W.New(f)
  b.hoverCard.frame:SetFrameLevel(455)
  b.hoverCard.frame:EnableMouse(false)
  b.hoverCard.frame:Hide()
  b.keywordPanels = {}
  for _, entry in ipairs({{b.heroPower, "heroPower"}, {b.foeHeroPower, "foeHeroPower"},
                         {b.weapon, "weapon"}, {b.foeWeapon, "foeWeapon"}}) do
    local widget, key = entry[1], entry[2]
    widget.frame:SetScript("OnEnter", function()
      local item = b.snapshot and b.snapshot[key]
      b:ShowDescription(widget.frame, item and item.cardId)
    end)
    widget.frame:SetScript("OnLeave", function() b:HideTooltip() end)
  end
  return b
end

-- ==================================================================== fx

--[[ Advance everything that moves by itself. Returns true while anything is
     still animating, which is what lets the OnUpdate go quiet. ]]
function Board:TickFX(dt)
  self.shineAge = (self.shineAge or 0) + dt
  for _,w in ipairs(self.handWidgets or {}) do
    w.glow:SetAlpha(0.9 + 0.1 * math.sin(self.shineAge * 2.4)^2)
  end
  for _,w in ipairs(self.myMinions or {}) do
    w.glow:SetAlpha(0.9 + 0.1 * math.sin(self.shineAge * 2.4)^2)
  end
  for _, skull in ipairs(self.skulls) do skull:Hide() end
  local snap = self.snapshot or {}
  if self.L and not self.presentationLocked and not snap.over and (snap.selectedIndex or snap.heroSelected) then
    local x,y = self:CursorInBoard()
    local target = x and self:TargetAt(x,y)
    local st = target and target.kind == "CLICK_FOE_BOARD" and (snap.foeBoardStats or {})[target.boardIndex]
    local id = st and st.instanceId or (target and target.kind == "CLICK_FOE_HERO" and snap.foeHeroId)
    local preview = id and snap.combatPreview and snap.combatPreview[id]
    if preview then
      local a = snap.heroSelected and self.L.hero or self.L.boardSlots[snap.selectedIndex]
      local d = st and self.L.foeBoardSlots[target.boardIndex] or self.L.foeHero
      for i, item in ipairs({{a,preview.attackerDies},{d,preview.defenderDies}}) do
        if item[1] and item[2] then
          local r, skull = item[1], self.skulls[i]
          skull:ClearAllPoints(); skull:SetSize(r.w*0.65, r.w*0.65)
          skull:SetPoint("CENTER", self.frame, "BOTTOMLEFT", r.x+r.w/2,r.y+r.h/2)
          skull:Show()
        end
      end
    end
  end
  for i = #self.projectiles, 1, -1 do
    local p = self.projectiles[i]
    p.age = p.age + dt
    local t = math.min(1, p.age / 0.3)
    W.Burst(self.particles, "arcane", p.x+(p.tx-p.x)*t, p.y+(p.ty-p.y)*t, t < 1 and 2 or 16, fxRandom)
    if t >= 1 then self:PresentImpact(); table.remove(self.projectiles, i) end
  end
  for _, hit in ipairs(self.hitLabels) do
    if hit.active then
      hit.age = hit.age + dt
      hit.frame:ClearAllPoints()
      hit.frame:SetPoint("CENTER", self.frame, "BOTTOMLEFT", hit.x, hit.y + hit.age*30)
      hit.frame:SetAlpha(math.max(0, 1-hit.age/1.1))
      if hit.age >= 1.1 then hit.active = false; hit.frame:Hide() end
    end
  end
  if self.bannerStart and self.banner:IsShown() then
    -- Swell in over 0.2s, hold, then fade over the last 0.3s (turn banners).
    local age = GetTime() - self.bannerStart
    local grow = math.max(0, math.min(1, age / 0.2))
    local alpha = grow
    if self.bannerUntil then
      alpha = math.min(alpha, math.max(0, (self.bannerUntil - GetTime()) / 0.3))
    end
    self.banner:SetScale(math.max(0.01, (self.bannerSize or 1) * (0.6 + 0.4 * (1 - (1 - grow) ^ 3))))
    self.banner:SetAlpha(alpha)
  end
  if self.resultStart and self.result:IsShown() then
    local now = GetTime()
    local age = now - self.resultStart
    local grow = math.max(0, math.min(1, age / 0.35))
    self.resultDim:SetAlpha(grow)
    self.result:SetScale(math.max(0.01, 0.55 + 0.45 * (1 - (1 - grow) ^ 3)))
    self.result:SetAlpha(grow)
  end
  if self.ropeAudioEpoch ~= nil then self:TickRopeAudio() end
  if self.timelines and #self.timelines > 0 then
    local alive = {}
    for _, tl in ipairs(self.timelines) do if tl:Tick(dt) then alive[#alive + 1] = tl end end
    self.timelines = alive
  end
  if self.shards and #self.shards > 0 then self:TickShards(dt) end
  if self.sprites and #self.sprites > 0 then self:TickSprites(dt) end
  if self.resultSoundAt and GetTime() >= self.resultSoundAt then
    self.resultSoundAt = nil
    self.resultHandle = select(2, ns.Sounds.Play(self.resultSound)); self.resultSound = nil
  end
  if self.postGameAt and GetTime() >= self.postGameAt then
    self.postGameAt = nil
    if not self.postGameState then self:SetPostGame("ready") end
  end
  if self.bannerUntil and GetTime() >= self.bannerUntil then
    self.banner:Hide(); self.bannerUntil = nil
  end
  if not self.dropPreview then
    self.dropPreview = self.fx:CreateTexture(nil, "OVERLAY")
    self.dropPreview:SetColorTexture(0.2, 1, 0.4, 0.8)
  end
  self.dropPreview:Hide()
  self:ClearPlacementPreview()
  if self.dragging and self.L then
    local x, y = self:CursorInBoard()
    local draggingSnap = self.snapshot or {}
    local needsTarget = draggingSnap.handNeedsTarget and draggingSnap.handNeedsTarget[self.dragging.handIndex]
    local draggingId = draggingSnap.hand and draggingSnap.hand[self.dragging.handIndex]
    local draggingCard = draggingId and ns.PrintedCards[draggingId]
    needsTarget = needsTarget and draggingCard and draggingCard.type == "SPELL"
    self.dragAiming = x and needsTarget and
      (Layout.Contains(self.L.field,x,y) or self:TargetAt(x,y)) or false
    if self.dragAiming then
      -- Held up beside your hero while you aim it, as Hearthstone does,
      -- rather than dropped back into the hand half-transparent.
      cardApplyRect(self.dragging, self:SpellHoldRect())
      self.dragging.frame:SetAlpha(1)
      self.dragging.frame:SetFrameLevel(200)
    elseif x then
      self.dragging.frame:SetAlpha(1)
      local cw, ch = self.L.cardW * Board.HOVER_SCALE, self.L.cardH * Board.HOVER_SCALE
      cardApplyRect(self.dragging, {x=x-cw/2,y=y-ch/2,w=cw,h=ch,rot=0})
      self.dragging.frame:SetFrameLevel(200)
    end
    local index = x and Layout.DropIndexAt(self.L, x, y)
    local snap = self.snapshot or {}
    local id = snap.hand and snap.hand[self.dragging.handIndex]
    local printed = id and ns.PrintedCards[id]
    local minion = printed and printed.type == "MINION"
    local valid = x and snap.playable and snap.playable[self.dragging.handIndex]
      and ((minion and index) or (not minion and (Layout.Contains(self.L.field, x, y) or self:TargetAt(x,y))))
    if valid and snap.handNeedsTarget and snap.handNeedsTarget[self.dragging.handIndex] then
      local target = self:TargetAt(x, y)
      local stats = target and ((target.kind == "CLICK_BOARD" and snap.boardStats)
        or (target.kind == "CLICK_FOE_BOARD" and snap.foeBoardStats))
      local entityId = stats and stats[target.boardIndex] and stats[target.boardIndex].instanceId
      if target and target.kind == "CLICK_HERO" then entityId = snap.heroId end
      if target and target.kind == "CLICK_FOE_HERO" then entityId = snap.foeHeroId end
      local legal = snap.handLegalTargets and snap.handLegalTargets[self.dragging.handIndex]
      valid = entityId and legal and legal[entityId]
    end
    self.dragging.glow:SetVertexColor(0.15, 0.55, 1, 0.9)
    if valid then self.dragging.glow:Show() else self.dragging.glow:Hide() end
    if valid and index and minion and not snap.targeting then
      self:ShowPlacementGhost(id, index, .5)
    end
  elseif self.L then
    --[[ A MINION WAITING ON ITS BATTLECRY stands in the slot it was dropped
         into while you aim, as Hearthstone's does -- nothing is committed yet,
         so it is the same ghost the drag drew, at full strength, and the card
         it came from is hidden until the aim finishes or is called off. ]]
    local pendingSlot, id = self:PendingMinionSlot()
    if pendingSlot then
      self:ShowPlacementGhost(id, pendingSlot, 1)
      local handIndex = (self.snapshot or {}).targeting.handIndex
      local wdg = self.handWidgets and self.handWidgets[handIndex]
      if wdg then wdg.frame:SetAlpha(0); self.placementHiddenHand = wdg end
    end
  end
  local busy = false
  if W.TickShake(self.shake, dt, fxRandom) then busy = true end
  if W.TickParticles(self.particles, dt) > 0 then busy = true end

  local keep = {}
  for _, t in ipairs(self.tweens) do
    if W.TickTween(t, dt, function(widget, r)
      cardApplyRect(widget, r)
    end) then
      keep[#keep + 1] = t
      busy = true
    end
  end
  self.tweens = keep
  if self.mulliganDealAt and self:TickMulliganDeal() then busy = true end
  if self.puffs and self:TickPuffs(dt) then busy = true end
  self:TickThinking()
  if self.foeHover and GetTime() - self.foeHover.at > 3 then self:ClearOpponentHover() end
  if self.burns and #self.burns > 0 and self:TickBurns(dt) then busy = true end

  --[[ The aiming arrow follows the POINTER, so it has to be redrawn every
       frame for as long as something is being aimed -- and the fx loop has to
       stay awake while it is. ]]
  if self:UpdateArrow() then busy = true end

  --[[ RIGHT-CLICK CALLS OFF AN AIM IN PROGRESS.

       This is the universal "no" in Hearthstone: you pick up a Fireball,
       change your mind, and right-click to put it down. Without it the only
       way out of a targeting prompt was to find somewhere harmless to drop it,
       and dropping "somewhere harmless" on a board full of legal targets is
       not a thing you can reliably do.

       It is polled rather than bound to a script because the gesture happens
       DURING a drag: the left button is held, so the card's own click handler
       is not going to fire, and a frame that captured the right button would
       have to sit over the entire board to catch it. IsMouseButtonDown is the
       one reading that works mid-drag. ]]
  if self:PollCancel() then busy = true end

  --[[ The rope is driven by the Director's clock through the stage, not from
       here; this only keeps its spark alive while it is visible. ]]
  if self.ropeBurn and self.ropeBurn > 0 and self.ropeBurn < 1 then busy = true end
  self.fxBusy = busy
  return busy
end

--[[ Move a card widget to a rect, sliding rather than snapping when it was
     already somewhere sensible.

     THE THING THIS FIXES: every relayout used to snap every card to its new
     place, so drawing a card made the whole hand jump. Hearthstone's hand
     slides apart to make room, and that motion is most of the difference
     between "a card game" and "a table of rectangles". ]]
function Board:PlaceCard(widget, r, animate)
  local from = widget.rect
  if animate and from and (from.x ~= r.x or from.y ~= r.y or from.w ~= r.w) then
    self.tweens[#self.tweens + 1] = W.NewTween(widget, from, r, 0.16)
    widget.rect = r
    return
  end
  cardApplyRect(widget, r)
end

-- ================================================================== state

--[[ Feed a snapshot of the game. Deliberately a SNAPSHOT, not the live game
     object: the UI must not be able to mutate engine state, and a snapshot is
     also what arrives over the wire for the spectator view. ]]
function Board:PresentImpact(snap)
  snap = snap or self.pendingSnapshot
  local previous = self.snapshot
  if not snap or not previous or not self.L then return end
  for _, event in ipairs(snap.presentationEvents or {}) do
    if event.seq > math.max(previous.eventSeq or 0, self.presentedEventSeq or 0) then
      local r, widget
      if event.targetId == previous.heroId then r,widget = self.L.hero,self.hero
      elseif event.targetId == previous.foeHeroId then r,widget = self.L.foeHero,self.foeHero
      else
        for _, pair in ipairs({{previous.boardStats, self.L.boardSlots,self.myMinions}, {previous.foeBoardStats, self.L.foeBoardSlots,self.foeMinions}}) do
          for i, st in ipairs(pair[1] or {}) do
            if st.instanceId == event.targetId then r,widget = pair[2][i],pair[3][i]; break end
          end
        end
      end
      if event.fatigue then
        local mine = event.targetId == previous.heroId
        self:ShowSpeech(mine and "self" or "foe",
          "Fatigue!\nOut of cards — " .. tostring(event.amount) .. " damage")
        if ns.Sounds then
          ns.Sounds.Play("hit")
          -- The hero who ran dry says so, once per match.
          self.outOfCards = self.outOfCards or {}
          local hero = mine and previous.hero or previous.foeHero
          if hero and not self.outOfCards[event.targetId] then
            self.outOfCards[event.targetId] = true
            ns.Sounds.PlayHero(hero.cardId, "no_cards", true)
          end
        end
      elseif r then self:ShowHit(r, event.amount, event.heal) end
      if widget and event.healthAfter ~= nil then
        local healthLabel=widget.hp or widget.health
        healthLabel:SetText(tostring(math.max(0,event.healthAfter)))
        healthLabel:SetTextColor(1,event.heal and 1 or .3,event.heal and 1 or .3,1)
        if widget.armor then
          widget.armor:SetText((event.armorAfter or 0)>0 and tostring(event.armorAfter) or "")
          if (event.armorAfter or 0)>0 then widget.armorBadge:Show() else widget.armorBadge:Hide() end
        end
      end
      self.presentedEventSeq = event.seq
    end
  end
end

function Board:SetSnapshot(snap)
  if self.presentationLocked then self.pendingSnapshot = snap; return end
  local previous = self.snapshot
  if previous and (snap.eventSeq or 0) < (previous.eventSeq or 0) then previous = nil; self.presentedEventSeq=nil end
  self:PresentImpact(snap)
  self.snapshot = snap
  if snap.over then
    self.dragging,self.dragAiming,self.hoverIndex=nil,nil,nil
    W.HideArrow(self.arrow)
  end
  if self.concede and self.concede:IsShown() == (snap.over and true or false) then
    self.concede:SetShown(not snap.over); self.corner:Arrange()
  end
  self.state.handCount     = #(snap.hand or {})
  self.state.boardCount    = #(snap.board or {})
  self.state.foeBoardCount = #(snap.foeBoard or {})
  self.state.foeHandCount  = snap.foeHandCount or 0
  self.state.maxMana       = snap.maxMana or 0
  self.state.foeMaxMana    = snap.foeMaxMana or 0
  self.state.hasWeapon     = snap.hasWeapon
  self.state.foeHasWeapon  = snap.foeHasWeapon
  --[[ `snap.chooseOne` is the pending choice, put there by whoever owns the
       engine: { handIndex, position, options = Targeting.ModeOptions(...) }.
       The board never asks the engine anything itself -- it renders what the
       snapshot says and emits the choice back as an intent. ]]
  self.state.chooseOne     = snap.chooseOne
  self.state.mulligan      = snap.mulligan
  --[[ The board has changed under the enlarged card, and it may no longer be
       there at all -- a minion you were reading can die while you read it. ]]
  self:HideInspect()
  if self.foeHover and (snap.myTurn or snap.over or (previous and
      (previous.myTurn ~= snap.myTurn or previous.eventSeq ~= snap.eventSeq))) then
    self.foeHover = nil; W.HideArrow(self.foeArrow)
  end
  self:Relayout()
  self:RefreshDescription()
  self:UpdateArrow()
  if self.foeHover then self:DrawOpponentArrow() end
  if previous and not snap.mulligan then
    local foeDraws = 0
    for _,event in ipairs(snap.drawEvents or {}) do
      if event.seq > (previous.eventSeq or 0) then
        if event.mine then
          for i,st in ipairs(snap.handStats or {}) do
            if st.instanceId == event.entityId then
              self:AnimateDraw(self.handWidgets[i],self.L.deck,{entityId=event.entityId})
              break
            end
          end
        else foeDraws = foeDraws + 1 end
      end
    end
    for i=math.max(1,#self.foeHandPool.used-foeDraws+1),#self.foeHandPool.used do
      self:AnimateDraw(self.foeHandPool.used[i],self.L.foeDeck,{foeIndex=i})
    end
    -- Overdrawn and overflowing cards burn where both players can see them.
    local k = 0
    for _, event in ipairs(snap.burnEvents or {}) do
      if event.seq > (previous.eventSeq or 0) and event.seq > (self.lastBurnSeq or 0) then
        self.lastBurnSeq = event.seq
        local stood = event.entityId and self.boardOrigins and self.boardOrigins[event.entityId]
        self:BurnCard(event.cardId, event.mine, k * 0.5, stood)
        -- "My hand is too full!" -- once, from the hero whose card burned
        local hero = event.mine and snap.hero or snap.foeHero
        if k == 0 and hero and hero.cardId then ns.Sounds.PlayHero(hero.cardId, "full_hand", true) end
        k = k + 1
      end
    end
  end
  if snap.over then
    -- the clock stops with the game: no rope, no hiss over the result
    self:ClearRope()
    self.banner:Hide(); self.bannerUntil = nil
    local won = snap.winner == (snap.player or 1)
    self:ShowResult(snap.winner == 0 and "draw" or (won and "victory" or "defeat"), snap)
    -- Rematch / Main Menu, once the result (and any hero's destruction) has played.
    if (not previous or not previous.over) and not self.postGameState then
      self.postGameAt = (GetTime and GetTime() or 0) + 2.4
    end
    if previous and not previous.over and snap.winner ~= 0 then
      self.resultSound = won and "victory" or "defeat"
    end
    if not previous or not previous.over then
      -- Whatever killed it, a dead hero cracks and explodes (Cho.HeroDeath),
      -- and the result waits for the explosion.
      local exploded = false
      for _, pair in ipairs({{snap.hero, "self"}, {snap.foeHero, "foe"}}) do
        if pair[1] and pair[1].health <= 0 then
          self:PlayHeroDeath(pair[2]); exploded = true
        end
      end
      if exploded then self.resultStart = (GetTime and GetTime() or 0) + 1.3 end
      -- Victory / defeat sound with the result, after any explosion.
      if self.resultSound then
        self.resultSoundAt = (GetTime and GetTime() or 0) + (exploded and 1.3 or 0)
      end
    end
  elseif previous and not snap.mulligan
         and (previous.myTurn ~= snap.myTurn or previous.mulligan) then
    -- Also once the mulligan closes: the first turn is announced like any other.
    if snap.myTurn then
      self.banner.text:SetText("YOUR TURN")
      self:ShowBanner(1, 1.6, 0)
      ns.Sounds.Play("your_turn")
    else
      self.banner:Hide(); self.bannerUntil = nil
    end
  elseif previous and previous.over then self.banner:Hide(); self:HideResult() end
end

--[[ A CARD BURNED BY A FULL HAND. As in Hearthstone it comes off the deck
     face up, hangs beside the hand long enough to read, then catches and
     burns away -- for either player's overdraw, so you see what they lost.
     Also for a card returned to, or discovered into, a full hand.

     `from` is the board slot of a minion bounced into a full hand (Vanish,
     Sap, Youthful Brewmaster). It used to blink out of its slot while a card
     flew from the DECK, which read as an unrelated overdraw: now the minion
     lifts off the board face up, as its card, and burns. ]]
Board.BURN_FLY, Board.BURN_HOLD, Board.BURN_FADE = 0.45, 1.1, 0.8
function Board:BurnCard(cardId, mine, delay, from)
  if not (self.L and self.resolver and cardId) then return end
  self.burns = self.burns or {}
  self.burnPool = self.burnPool or {}
  local w
  for _, c in ipairs(self.burnPool) do if not c.burning then w = c; break end end
  if not w then
    w = W.New(self.frame); w.frame:EnableMouse(false)
    self.burnPool[#self.burnPool + 1] = w
  end
  cardSetDescriptor(w, self.resolver:Card(cardId))
  local H0, W0 = self.frame:GetHeight(), self.frame:GetWidth()
  local ch = math.floor(H0 * 0.30); local cw = math.floor(ch * Layout.design.CARD_W_OVER_H)
  local deck = mine and self.L.deck or self.L.foeDeck
  local to = { x = W0 * 0.66 - cw / 2, y = mine and H0 * 0.22 or H0 * 0.62, w = cw, h = ch }
  w.burning = true
  w.frame:SetFrameLevel(420)
  w.art:SetVertexColor(1, 1, 1, 1)
  local start = from or deck
  start = { x = start.x, y = start.y, w = start.w, h = start.h }
  cardApplyRect(w, start)
  W.SetFaceDown(w, not from)
  -- a bounced minion waits its turn to burn where it stood, never a gap
  w.frame:SetAlpha(1); w.frame:SetShown(from and true or false)
  self.burns[#self.burns + 1] = { w = w, age = -(delay or 0), from = start,
                                  to = to, mine = mine, bounced = from and true or nil }
end

function Board:TickBurns(dt)
  local alive = {}
  for _, b in ipairs(self.burns) do
    b.age = b.age + dt
    local w = b.w
    if b.age >= 0 then
      w.frame:Show()
      if not b.sounded then b.sounded = true; ns.Sounds.Play("card_deal") end
      if b.age < Board.BURN_FLY then
        local p = b.age / Board.BURN_FLY
        local e = 1 - (1 - p) * (1 - p)
        local f, t = b.from, b.to
        cardApplyRect(w, { x = f.x + (t.x - f.x) * e, y = f.y + (t.y - f.y) * e,
                           w = f.w + (t.w - f.w) * e, h = f.h + (t.h - f.h) * e })
        if w.faceDown and p > 0.5 then W.SetFaceDown(w, false) end
      elseif b.age < Board.BURN_FLY + Board.BURN_HOLD then
        if w.faceDown then W.SetFaceDown(w, false) end
        if not b.placed then b.placed = true; cardApplyRect(w, b.to) end
      else
        local p = (b.age - Board.BURN_FLY - Board.BURN_HOLD) / Board.BURN_FADE
        if not b.lit then
          b.lit = true
          ns.Sounds.Play("card_burn")
        end
        -- scorch towards ember orange then char, shrinking into the flames
        local r = b.to
        w.art:SetVertexColor(1, 1 - 0.55 * p, 1 - 0.85 * p, 1)
        w.frame:SetAlpha(math.max(0, 1 - p))
        if self.particles then
          W.Burst(self.particles, "fire", r.x + r.w * (0.2 + 0.6 * fxRandom()),
                  r.y + r.h * (0.15 + 0.7 * (1 - p)), 2, fxRandom)
        end
        if p >= 1 then w.burning = false; w.frame:Hide() end
      end
    end
    if w.burning then alive[#alive + 1] = b end
  end
  self.burns = alive
  return #alive > 0
end

function Board:AnimateDraw(widget, deck, identity, duration)
  if not widget or not deck then return end
  local to = widget.rect
  local from = {x=deck.x,y=deck.y,w=deck.w,h=deck.h,rot=deck.rot or 0,lean=to.lean}
  for i=#self.tweens,1,-1 do
    if self.tweens[i].w == widget then table.remove(self.tweens,i) end
  end
  cardApplyRect(widget,from)
  local tween = W.NewTween(widget,from,to,duration or 0.5)
  tween.draw = identity
  -- a draw is heard, as in Hearthstone (once per card, not on re-attach) --
  -- but three cards drawn at once are one sound, not three stacked
  local now = GetTime and GetTime() or 0
  if not (identity and identity.silent) and now - (self.lastDealSound or -1) > 0.08 then
    self.lastDealSound = now
    ns.Sounds.Play("card_deal")
  end
  self.tweens[#self.tweens+1] = tween
end

function Board:ShowHit(r, amount, heal)
  if not amount or amount <= 0 then return end
  local slot
  for _, item in ipairs(self.hitLabels) do if not item.active then slot = item; break end end
  if not slot then
    if #self.hitLabels >= 32 then return end
    local frame = CreateFrame("Frame", nil, self.frame)
    frame:SetSize(64, 64); frame:SetFrameLevel(250)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetTexture("Interface\\AddOns\\ForeverHearthstone\\Art\\hit-splat.tga")
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetPoint("CENTER"); W.ApplyStyle(label, "number", nil, 28)
    slot = {frame=frame, label=label, background=background}; self.hitLabels[#self.hitLabels+1] = slot
  end
  slot.active, slot.age, slot.x, slot.y = true, 0, r.x+r.w/2, r.y+r.h/2
  slot.label:SetText((heal and "+" or "-") .. tostring(amount))
  slot.label:SetTextColor(1, 1, 1, 1)
  -- Hearthstone's own damage starburst and healing bloom.
  slot.background:SetTexture(ART .. (heal and "healing" or "damage") .. ".tga")
  slot.background:SetVertexColor(1, 1, 1, 1)
  local size = math.max(40, math.min(80, self.frame:GetHeight()*0.075))
  slot.frame:SetSize(size,size)
  -- the digit grows with the splat, under Hearthstone's heavy edge (docs/39)
  W.ApplyStyle(slot.label, "gemDigit", nil, math.floor(size * 0.46))
  slot.label:SetTextColor(1, 1, 1, 1)
  slot.frame:ClearAllPoints()
  slot.frame:SetPoint("CENTER", self.frame, "BOTTOMLEFT", slot.x, slot.y)
  slot.frame:SetAlpha(1); slot.frame:Show()
end

-- Show the medallion at `size` (of the board-relative base) for `duration`
-- seconds, or until cleared when duration is nil (a result).
function Board:ShowBanner(size, duration, lift)
  local now = GetTime and GetTime() or 0
  local h = self.frame:GetHeight()
  self.bannerSize = size * math.max(0.7, math.min(1.6, h / 720))
  -- A result sits a little high, leaving room for Rematch / Leave beneath it.
  -- (Offsets are in the banner's own scaled units.)
  self.bannerLift = (lift or 0) * h
  self.banner:ClearAllPoints()
  self.banner:SetPoint("CENTER", self.frame, "CENTER", 0, self.bannerLift / self.bannerSize)
  self.bannerStart = now
  self.bannerUntil = duration and now + duration or nil
  self.banner:SetScale(self.bannerSize * 0.6); self.banner:SetAlpha(0)
  self.banner:Show()
end

--[[ AFTER THE GAME: Rematch and Leave, under the result.

     state   "ready"     Rematch | Leave
             "asked"     waiting for them to answer
             "invited"   "<name> would like a rematch"   Accept | Decline
             "declined"  they said no                    Leave
             "closed"    you said no                     Leave
             "starting"  agreed; the new game is on its way
             nil         hidden
     The buttons call back into Main (opts.onRematch / onDeclineRematch /
     onLeave): the board's own intents are blocked once a game is over. ]]
-- Where the art sits in result-ornament.tga (Art/result-art.json).
Board.RESULT_ART = {
  aspect = 1.0441,                             -- width / height
  window = { 0.3352, 0.1735, 0.6676, 0.5941 }, -- the portrait's arch
  plaque = { 0.2000, 0.5971, 0.8070, 0.7632 },
  -- the square hero art (HERO_xx.tga) cropped to the arch's aspect: its face
  heroCoords = { 0.150, 0.807, 0.098, 0.895 },
  --[[ The defeat frame (result-frame.tga) is a plainer arch with a WIDER
       opening -- measured from its alpha: x .250-.750, y .119-.595 -- and the
       victory box left the art short of its left side (the in-client tour,
       docs/39). Its own box, and a crop of the same face at that shape. ]]
  defeatWindow = { 0.2500, 0.1191, 0.7500, 0.5947 },
  defeatCoords = { 0.040, 0.960, 0.040, 0.915 },
  --[[ The portrait runs this far under the ornament on every side. The
       opening's rim is anti-aliased, and an exact fit let slivers of the
       hero art's own pale edge show at the arch's foot. ]]
  bleed = 0.012,
}
function Board:ShowResult(kind, snap)
  local res = self.result
  local A = Board.RESULT_ART
  local w, h = self.frame:GetWidth(), self.frame:GetHeight()
  -- about three quarters of the table's height, a little above centre so
  -- Rematch / Main Menu fit beneath the banners
  local oh = math.floor(math.min(h * 0.74, w * 0.62 / A.aspect))
  local ow = math.floor(oh * A.aspect)
  res:ClearAllPoints()
  res:SetSize(ow, oh)
  res:SetPoint("CENTER", self.frame, "CENTER", 0, h * 0.10)
  local function place(tex, box)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", res, "TOPLEFT", box[1] * ow, -box[2] * oh)
    tex:SetSize((box[3] - box[1]) * ow, (box[4] - box[2]) * oh)
  end
  local hero = self.hero and self.hero.art
  res.portrait:SetTexture(hero and hero:GetTexture() or nil)
  local defeatArt = kind ~= "victory"
  res.portrait:SetTexCoord(unpack(defeatArt and A.defeatCoords or A.heroCoords))
  local win, bl = defeatArt and A.defeatWindow or A.window, A.bleed
  place(res.portrait, { win[1] - bl, win[2] - bl, win[3] + bl, win[4] + bl })
  res.crack:ClearAllPoints(); res.crack:SetAllPoints(res.portrait)
  local defeat = kind == "defeat"
  if res.portrait.SetDesaturated then res.portrait:SetDesaturated(defeat) end
  res.portrait:SetVertexColor(defeat and .72 or 1, defeat and .72 or 1, defeat and .76 or 1)
  res.crack:SetShown(defeat)
  -- a defeat keeps the arch but has nothing to celebrate
  res.ornament:SetTexture(ART .. (kind == "victory" and "result-ornament.tga" or "result-frame.tga"))
  res.ornament:ClearAllPoints(); res.ornament:SetAllPoints(res)
  place(res.ribbon, A.plaque)
  local rw, rh = (A.plaque[3] - A.plaque[1]) * ow, (A.plaque[4] - A.plaque[2]) * oh
  -- Hearthstone's lettering: white, black-edged, on the planks
  res.text:ClearAllPoints()
  res.text:SetPoint("CENTER", res.ribbon, "CENTER", 0, rh * 0.02)
  W.SetFitBox(res.text, rw * 0.66, rh * 0.52, math.max(18, math.floor(rh * 0.46)))
  res.text:SetText(kind == "draw" and "Draw" or (defeat and "Defeat" or "Victory!"))
  res.text:SetTextColor(1, 1, 1, 1)
  if self.bg.SetDesaturated then self.bg:SetDesaturated(true) end
  for _, band in ipairs(self.bgBands or {}) do band:SetDesaturated(true) end
  self:DrainTable(true)
  if not res:IsShown() or not self.resultStart then
    self.resultStart = GetTime and GetTime() or 0
    res:SetScale(0.55); res:SetAlpha(0)
  end
  self.resultKind = kind
  res:Show()
  self.resultDim:Show()
end

--[[ THE WHOLE TABLE DRAINS, NOT JUST THE CLOTH. Only the board texture went
     grey, so the minions, the hand, both heroes and every gem sat in full
     colour on a grey table (the in-client tour, docs/39). Everything on the
     board except the result itself is desaturated, and exactly what this
     changed is put back -- a texture that was already grey for its own reason
     (a spent hero power) stays as it was. ]]
function Board:DrainTable(on)
  if not on then
    for _, r in ipairs(self.drained or {}) do pcall(r.SetDesaturated, r, false) end
    self.drained = nil
    return
  end
  if self.drained then return end
  local drained, skip = {}, { [self.result] = true, [self.resultDimLayer] = true }
  if self.postGame then skip[self.postGame] = true end
  local function walk(fr)
    if skip[fr] then return end
    for _, r in ipairs({ fr:GetRegions() }) do
      if r:GetObjectType() == "Texture" and not r:IsDesaturated() then
        r:SetDesaturated(true); drained[#drained + 1] = r
      end
    end
    for _, c in ipairs({ fr:GetChildren() }) do walk(c) end
  end
  pcall(walk, self.frame)
  self.drained = drained
end

function Board:HideResult()
  self:DrainTable(false)
  self.result:Hide(); self.resultDim:Hide()
  if self.bg.SetDesaturated then self.bg:SetDesaturated(false) end
  for _, band in ipairs(self.bgBands or {}) do band:SetDesaturated(false) end
end

--[[ AFTER THE GAME: two matching tavern buttons under the result ribbon --
     Rematch (Accept, when asked) and Main Menu (Decline, when asked) -- with
     any message ("Waiting for Thrall...") in plain lettering above them. The
     same button the main menu uses, so the whole addon has one button. ]]
function Board:SetPostGame(state, name)
  self.postGameState = state
  self.postGameName = name
  if not state then
    if self.postGame then self.postGame:Hide() end
    return
  end
  if not self.postGame then
    local p = CreateFrame("Frame", nil, self.frame)
    p:SetFrameLevel(460); p:EnableMouse(false)
    p.text = p:CreateFontString(nil, "OVERLAY")
    W.ApplyStyle(p.text, "label", nil, 17, W.Colors.bodyLight)
    p.text:SetShadowOffset(1, -1); p.text:SetShadowColor(0, 0, 0, .9)
    W.AutoFit(p.text, { w = 300, h = 22, font = ns.Fonts.TITLE, size = 17, min = 9, flags = "OUTLINE" })
    p.primary = W.MenuButton(p, "Rematch", function()
      local o = self.opts or {}
      if o.onRematch then o.onRematch() end
    end)
    p.secondary = W.MenuButton(p, "Main Menu", function()
      local o = self.opts or {}
      if self.postGameState == "invited" then
        if o.onDeclineRematch then o.onDeclineRematch() end
      elseif o.onLeave then o.onLeave() else self.frame:Hide() end
    end)
    for _, b in ipairs({ p.primary, p.secondary }) do b:SetFrameLevel(470) end
    self.postGame = p
  end
  local p = self.postGame
  local who = tostring(name or "Your opponent")
  local message = ({
    -- "ready": the line Main left about the result (the record, why it ended)
    ready = self.postGameNote or "", asked = "Waiting for " .. who .. "...",
    invited = who .. " would like a rematch!", declined = who .. " declined the rematch.",
    closed = "Rematch declined.", starting = "Starting the rematch...",
  })[state] or ""
  p.text:SetText(message)
  p.primary.text:SetText(state == "invited" and "Accept" or "Rematch")
  p.secondary.text:SetText(state == "invited" and "Decline" or "Main Menu")
  p.primary:SetShown(state ~= "declined" and state ~= "closed" and state ~= "starting")
  p.primary:SetEnabledLook(state == "ready" or state == "invited")
  p.secondary:SetShown(state ~= "starting")
  -- Under the result: it is centred 10% above the middle and 74% of the
  -- height tall, so its banners end at about -0.27h.
  local w, h = self.frame:GetWidth(), self.frame:GetHeight()
  local bw = math.floor(math.max(150, math.min(230, w * 0.16)))
  local bh = math.floor(math.max(40, math.min(56, h * 0.062)))
  local gap = math.floor(bw * 0.12)
  p:ClearAllPoints(); p:SetSize(bw * 2 + gap, bh + 30)
  p:SetPoint("TOP", self.frame, "CENTER", 0, -h * 0.265)
  p.text:ClearAllPoints(); p.text:SetPoint("TOP", p, "TOP", 0, 0)
  W.SetFitBox(p.text, bw * 2 + gap, 22)
  local shownPrimary = p.primary:IsShown()
  p.primary:ClearAllPoints(); p.primary:SetSize(bw, bh)
  p.secondary:ClearAllPoints(); p.secondary:SetSize(bw, bh)
  if shownPrimary then
    p.primary:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
    p.secondary:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  else
    p.secondary:SetPoint("BOTTOM", p, "BOTTOM", 0, 0)
  end
  for _, b in ipairs({ p.primary, p.secondary }) do
    W.ApplyStyle(b.text, "button", nil, math.max(13, math.floor(bh * 0.40)))
  end
  p:Show()
end

-- ========================================================== spell effects

--[[ A SPRITE: one textured, additive glow (fx-<school>.tga) that flies from
     (x0,y0) to (x1,y1) over `dur` seconds, bowing up by `arc`, growing from s0
     to s1, fading per `fade` ("out", "inout" or solid), optionally shedding a
     trail of school-coloured particles, and calling onArrive(x, y) when it
     lands. `delay` staggers a volley. Pooled; ticked in TickFX.

     `shape` draws one of the white shapes instead (fx-ring, fx-streak,
     fx-spark), tinted the school's colour. `rot` turns it (radians), `spin`
     keeps turning it, `orient` points it along its flight, `flicker` makes
     it strobe (lightning) and `alpha` dims it (a soft halo under a core). ]]
function Board:SpawnSprite(o)
  self.sprites = self.sprites or {}
  self.spritePool = self.spritePool or {}
  local t = table.remove(self.spritePool) or self.spellLayer:CreateTexture(nil, "OVERLAY", nil, 4)
  t:SetTexture(ART .. "fx-" .. (o.shape or o.school or "orb") .. ".tga")
  t:SetBlendMode("ADD")
  local c = o.shape and ns.SpellFX and ns.SpellFX.COLOURS[o.school or "orb"]
  if c then t:SetVertexColor(c[1], c[2], c[3], 1) else t:SetVertexColor(1, 1, 1, 1) end
  t:SetRotation(o.rot or 0)
  t:Hide()
  o.tex, o.age = t, -(o.delay or 0)
  self.sprites[#self.sprites + 1] = o
  return o
end

function Board:TickSprites(dt)
  for i = #self.sprites, 1, -1 do
    local o = self.sprites[i]
    o.age = o.age + dt
    if o.age >= 0 then
      local t = math.min(1, o.age / math.max(0.01, o.dur))
      local x = o.x0 + (o.x1 - o.x0) * t
      local y = o.y0 + (o.y1 - o.y0) * t + (o.arc or 0) * 4 * t * (1 - t)
      local size = o.s0 + (o.s1 - o.s0) * t
      o.tex:ClearAllPoints()
      o.tex:SetSize(size * (o.aspect or 1), size)
      o.tex:SetPoint("CENTER", self.frame, "BOTTOMLEFT", x, y)
      if o.orient then
        -- along the flight, bow included (the arc's slope at t)
        local dy = (o.y1 - o.y0) + (o.arc or 0) * 4 * (1 - 2 * t)
        o.tex:SetRotation(math.atan2(dy, o.x1 - o.x0))
      elseif o.spin then
        o.tex:SetRotation((o.rot or 0) + o.spin * o.age)
      end
      local alpha = o.fade == "out" and (1 - t) or o.fade == "inout" and math.sin(math.pi * t) or 1
      if o.flicker then alpha = alpha * (0.35 + 0.65 * fxRandom()) end
      alpha = alpha * (o.alpha or 1)
      o.tex:SetAlpha(alpha)
      o.tex:Show()
      if o.trail then
        o.trailAcc = (o.trailAcc or 0) + dt
        if o.trailAcc >= 0.025 then o.trailAcc = 0; W.Burst(self.particles, o.school, x, y, 1, fxRandom) end
      end
      if t >= 1 then
        o.tex:Hide(); table.remove(self.sprites, i)
        self.spritePool[#self.spritePool + 1] = o.tex
        if o.onArrive then o.onArrive(x, y) end
      end
    end
  end
end

function Board:ClearSprites()
  self.spritePool = self.spritePool or {}
  for _, o in ipairs(self.sprites or {}) do
    o.tex:Hide(); self.spritePool[#self.spritePool + 1] = o.tex
  end
  self.sprites = {}
end

--[[ Lay out one spell effect. opts come from the choreography: cardId, mine,
     targeted, targetSide/targetIndex/targetIsHero, power (a hero power). ]]
function Board:SpellEffect(opts)
  local L = self.L
  if not (L and ns.SpellFX) then return false end
  local spec = ns.SpellFX.For(opts.cardId, opts.targeted)
  local impact = ns.SpellFX.Impact(spec)
  local mine = opts.mine ~= false
  local scale = L.scale or 1
  local school = spec.school or "arcane"
  local function center(r) return r.x + r.w / 2, r.y + r.h / 2 end
  --[[ Every spell launches from its caster's HERO, as in Hearthstone: the
       played card is shown and burns away, but the Fireball leaves the
       portrait. (It used to leave the card, mid-flight.) ]]
  local casterRect = mine and L.hero or L.foeHero
  local sx, sy = center(casterRect)
  local function slotsOf(side)
    local rows = {}
    local function add(list) for _, r in ipairs(list or {}) do rows[#rows + 1] = r end end
    if side == "foe" or side == "all" then add(mine and L.foeBoardSlots or L.boardSlots) end
    if side == "self" or side == "all" then add(mine and L.boardSlots or L.foeBoardSlots) end
    return rows
  end
  local function targetRect()
    if not opts.targeted then return nil end
    if opts.targetIsHero then return opts.targetSide == "self" and L.hero or L.foeHero end
    local list = opts.targetSide == "self" and L.boardSlots or L.foeBoardSlots
    return list[opts.targetIndex or 1]
  end
  local function burst(x, y, n) W.Burst(self.particles, school, x, y, n, fxRandom) end
  local function flash(x, y, s0, s1, dur, delay)
    self:SpawnSprite({ school = school, x0 = x, y0 = y, x1 = x, y1 = y, dur = dur or 0.35,
                       s0 = s0, s1 = s1, fade = "out", delay = delay })
  end
  local function ring(x, y, s0, s1, dur, delay)
    self:SpawnSprite({ school = school, shape = "ring", x0 = x, y0 = y, x1 = x, y1 = y,
                       dur = dur or 0.4, s0 = s0, s1 = s1, fade = "out", delay = delay })
  end
  --[[ Where a blow lands: sparks, a flash, and for a heavy spell a shockwave
       ring and the table shaking -- at the moment of arrival. ]]
  local function land(x, y, size, sparks)
    burst(x, y, sparks or impact.sparks)
    flash(x, y, 40 * scale, size, 0.35)
    if impact.ring then ring(x, y, 30 * scale, size * 1.3, 0.45) end
    if impact.shake > 0 and self.shake then W.Shake(self.shake, impact.shake) end
  end
  local kind = spec.kind
  local tr = targetRect()
  local enemyHero = mine and L.foeHero or L.hero
  local ownHero = mine and L.hero or L.foeHero

  if kind == "bolt" then
    local tx, ty = center(tr or enemyHero)
    local big = spec.big and 1.5 or 1
    self:SpawnSprite({ school = school, x0 = sx, y0 = sy, x1 = tx, y1 = ty,
      dur = spec.heavy and 0.32 or 0.28, s0 = 90 * scale * big, s1 = 115 * scale * big,
      arc = 50 * scale, trail = true,
      onArrive = function(x, y) land(x, y, (spec.heavy and 260 or 200) * scale * big) end })
  elseif kind == "missiles" then
    local pool = {}
    if not spec.minions then pool[1] = enemyHero end
    for _, r in ipairs(slotsOf("foe")) do pool[#pool + 1] = r end
    if #pool == 0 then pool[1] = enemyHero end
    for i = 1, spec.count or 3 do
      local r = pool[fxRandom(1, #pool)]
      local tx, ty = center(r)
      local heavy = spec.heavy
      self:SpawnSprite({ school = school, x0 = sx, y0 = sy, x1 = tx, y1 = ty, dur = heavy and 0.32 or 0.26,
        s0 = (heavy and 85 or 55) * scale, s1 = (heavy and 105 or 64) * scale,
        arc = (30 + 40 * (i % 3)) * scale, trail = true, delay = (i - 1) * 0.12,
        onArrive = function(x, y)
          if heavy then land(x, y, r.w * 1.6)
          else burst(x, y, 10); flash(x, y, 20 * scale, 80 * scale, 0.25) end
        end })
    end
  elseif kind == "beam" then
    --[[ Lightning: the arc is a chain of streaks between jittered points,
         redrawn twice with fresh jitter so it crackles rather than sits. ]]
    local targets = { tr or enemyHero }
    if (spec.count or 1) > 1 then
      local pool = slotsOf("foe")
      for _ = 2, spec.count do
        if #pool == 0 then break end
        targets[#targets + 1] = table.remove(pool, fxRandom(1, #pool))
      end
    end
    for n, r in ipairs(targets) do
      local tx, ty = center(r)
      for pass = 0, 1 do
        local segs = 6
        local px, py = sx, sy
        local dx, dy = tx - sx, ty - sy
        local len = math.max(1, math.sqrt(dx * dx + dy * dy))
        local nx, ny = -dy / len, dx / len
        for k = 1, segs do
          local f = k / segs
          local j = k < segs and (fxRandom() - 0.5) * 60 * scale or 0
          local qx, qy = sx + dx * f + nx * j, sy + dy * f + ny * j
          local mx, my = (px + qx) / 2, (py + qy) / 2
          local sl = math.sqrt((qx - px) ^ 2 + (qy - py) ^ 2)
          local rot, delay = math.atan2(qy - py, qx - px), (n - 1) * 0.08 + pass * 0.13 + k * 0.012
          self:SpawnSprite({ school = school, shape = "streak", x0 = mx, y0 = my, x1 = mx, y1 = my,
            dur = 0.16, s0 = 40 * scale, s1 = 34 * scale, aspect = math.max(1, sl * 1.15 / (40 * scale)),
            rot = rot, flicker = true, delay = delay })
          if pass == 0 then  -- the soft glow the bolt lights the air with
            self:SpawnSprite({ school = school, shape = "streak", x0 = mx, y0 = my, x1 = mx, y1 = my,
              dur = 0.3, s0 = 110 * scale, s1 = 90 * scale, aspect = math.max(1, sl * 1.4 / (110 * scale)),
              rot = rot, fade = "out", alpha = 0.45, delay = delay })
          end
          px, py = qx, qy
        end
      end
      self:SpawnSprite({ school = school, x0 = tx, y0 = ty, x1 = tx, y1 = ty, dur = 0.01,
        s0 = 1, s1 = 1, delay = (n - 1) * 0.08 + 0.1,
        onArrive = function(x, y) land(x, y, r.w * 1.6) end })
    end
  elseif kind == "fan" then
    local rows = slotsOf("foe")
    for i, r in ipairs(rows) do
      local tx, ty = center(r)
      local hx, hy = center(ownHero)
      self:SpawnSprite({ school = school, shape = "streak", x0 = hx, y0 = hy, x1 = tx, y1 = ty,
        dur = 0.22, s0 = 22 * scale, s1 = 22 * scale, aspect = 3.5, orient = true, delay = 0.02 * i,
        onArrive = function(x, y) burst(x, y, 8); flash(x, y, 20 * scale, r.w * 1.1, 0.25) end })
    end
    local hx, hy = center(ownHero)
    ring(hx, hy, 40 * scale, 220 * scale, 0.35)
  elseif kind == "slash" then
    local r = tr or enemyHero
    local cx, cy = center(r)
    local reach = r.w * 1.4
    for i = 1, spec.count or 1 do
      -- down-left to up-right, then the second stroke crossing it
      local dir = (i % 2 == 1) and 1 or -1
      local rot = dir * math.pi / 4
      local ox, oy = math.cos(rot) * reach / 2, math.sin(rot) * reach / 2
      -- the cut it leaves behind, fading after the blade has passed
      self:SpawnSprite({ school = school, shape = "streak", x0 = cx, y0 = cy, x1 = cx, y1 = cy,
        dur = 0.35, s0 = 44 * scale, s1 = 30 * scale, aspect = reach * 1.1 / (44 * scale), rot = rot,
        fade = "out", delay = (i - 1) * 0.14 + 0.1 })
      self:SpawnSprite({ school = school, shape = "streak", x0 = cx - ox, y0 = cy - oy,
        x1 = cx + ox * 0.3, y1 = cy + oy * 0.3, dur = 0.14, s0 = 56 * scale, s1 = 64 * scale,
        aspect = reach / (56 * scale), rot = rot, delay = (i - 1) * 0.14,
        onArrive = i == (spec.count or 1) and function() land(cx, cy, r.w * 1.5) end or function()
          burst(cx, cy, 10) end })
    end
  elseif kind == "drain" then
    local r = tr or enemyHero
    local tx, ty = center(r)
    local hx, hy = center(ownHero)
    self:SpawnSprite({ school = school, x0 = sx, y0 = sy, x1 = tx, y1 = ty, dur = 0.28,
      s0 = 80 * scale, s1 = 100 * scale, arc = 40 * scale, trail = true,
      onArrive = function(x, y)
        land(x, y, r.w * 1.5)
        -- the life flowing home: a thread of motes back to the caster
        for k = 1, 6 do
          self:SpawnSprite({ school = "holy", shape = "spark", x0 = x, y0 = y, x1 = hx, y1 = hy,
            dur = 0.4, s0 = 26 * scale, s1 = 18 * scale, arc = (k % 2 == 0 and 1 or -1) * 30 * scale,
            delay = 0.05 * k, spin = 5,
            onArrive = k == 6 and function(ax, ay) W.Burst(self.particles, "holy", ax, ay, 10, fxRandom) end or nil })
        end
      end })
  elseif kind == "sweep" then
    local rows = slotsOf(spec.side or "foe")
    local band = rows[1] or enemyHero
    local y = band.y + band.h / 2
    local x0 = L.field and L.field.x or 0
    local x1 = L.field and (L.field.x + L.field.w) or self.frame:GetWidth()
    self:SpawnSprite({ school = school, x0 = x0, y0 = y, x1 = x1, y1 = y, dur = 0.42,
      s0 = band.h * 0.9, s1 = band.h * 1.1, aspect = 1.6, fade = "inout", trail = true })
    -- the claw's edge: a bright streak leading the wave
    self:SpawnSprite({ school = school, shape = "streak", x0 = x0, y0 = y, x1 = x1, y1 = y, dur = 0.42,
      s0 = band.h * 0.35, s1 = band.h * 0.35, aspect = 4, fade = "inout" })
    for _, r in ipairs(rows) do
      local cx, cy = center(r)
      local delay = 0.42 * math.max(0, math.min(1, (cx - x0) / math.max(1, x1 - x0)))
      flash(cx, cy, 30 * scale, r.w * 1.4, 0.3, delay)
    end
  elseif kind == "rain" then
    local rows = slotsOf(spec.side or "foe")
    if #rows == 0 then rows = { enemyHero } end
    local top = self.frame:GetHeight()
    for i, r in ipairs(rows) do
      local cx, cy = center(r)
      local delay = 0.05 * i + fxRandom() * 0.12
      self:SpawnSprite({ school = school, x0 = cx - 30 * scale, y0 = top, x1 = cx, y1 = cy,
        dur = 0.24, s0 = 95 * scale, s1 = 125 * scale, trail = true, delay = delay,
        onArrive = function(x, y) burst(x, y, 16); flash(x, y, 30 * scale, r.w * 1.5, 0.35) end })
    end
    if spec.heavy then
      local cy = rows[1].y + rows[1].h / 2
      local cx = self.frame:GetWidth() / 2
      self:SpawnSprite({ school = school, x0 = cx, y0 = cy, x1 = cx, y1 = cy, dur = 0.6,
        s0 = 100 * scale, s1 = self.frame:GetWidth() * 0.8, aspect = 2.2, fade = "out", delay = 0.25 })
      self:SpawnSprite({ school = school, x0 = cx, y0 = cy, x1 = cx, y1 = cy, dur = 0.01, s0 = 1, s1 = 1,
        delay = 0.25, onArrive = function() if self.shake then W.Shake(self.shake, impact.shake) end end })
    end
  elseif kind == "nova" then
    local hx, hy = center(ownHero)
    self:SpawnSprite({ school = school, x0 = hx, y0 = hy, x1 = hx, y1 = hy, dur = 0.55,
      s0 = 40 * scale, s1 = self.frame:GetWidth() * 1.1, fade = "out" })
    ring(hx, hy, 40 * scale, self.frame:GetWidth() * 0.9, 0.5)
    if spec.heavy then
      ring(hx, hy, 40 * scale, self.frame:GetWidth() * 0.6, 0.5, 0.1)
      if self.shake then W.Shake(self.shake, impact.shake) end
    end
    for _, r in ipairs(slotsOf(spec.side or "all")) do
      local cx, cy = center(r)
      flash(cx, cy, 30 * scale, r.w * 1.3, 0.3, 0.18)
    end
    if spec.side ~= "self" then
      local ex, ey = center(enemyHero)
      flash(ex, ey, 30 * scale, enemyHero.w * 1.3, 0.3, 0.22)
    end
  elseif kind == "bloom" then
    local r = tr or ownHero
    local cx, cy = center(r)
    for i = 1, 6 do
      local ox = (i - 3.5) * r.w * 0.14
      self:SpawnSprite({ school = school, x0 = cx + ox, y0 = cy - r.h * 0.35, x1 = cx + ox * 0.6,
        y1 = cy + r.h * 0.55, dur = 0.55, s0 = 26 * scale, s1 = 14 * scale, fade = "inout",
        delay = 0.05 * i })
      self:SpawnSprite({ school = school, shape = "spark", x0 = cx - ox * 0.8, y0 = cy - r.h * 0.2,
        x1 = cx - ox * 0.5, y1 = cy + r.h * 0.7, dur = 0.7, s0 = 22 * scale, s1 = 10 * scale,
        fade = "inout", spin = 3, delay = 0.08 + 0.06 * i })
    end
    flash(cx, cy, r.w * 0.6, r.w * 1.5, 0.55)
  elseif kind == "swirl" then
    --[[ Motes orbiting the target and closing in, then a pop: the thing that
         was there is not what is there now. ]]
    local r = tr or ownHero
    local cx, cy = center(r)
    local radius = r.w * 0.8
    for k = 0, 7 do
      local a0 = k / 8 * math.pi * 2
      local a1 = a0 + math.pi * 1.5
      self:SpawnSprite({ school = school, shape = "spark",
        x0 = cx + math.cos(a0) * radius, y0 = cy + math.sin(a0) * radius,
        x1 = cx + math.cos(a1) * radius * 0.1, y1 = cy + math.sin(a1) * radius * 0.1,
        dur = 0.45, s0 = 30 * scale, s1 = 16 * scale, arc = (k % 2 == 0 and 1 or -1) * radius * 0.6,
        spin = 8, delay = 0.02 * k })
    end
    self:SpawnSprite({ school = school, x0 = cx, y0 = cy, x1 = cx, y1 = cy, dur = 0.01, s0 = 1, s1 = 1,
      delay = 0.47, onArrive = function(x, y) land(x, y, r.w * 1.6, 20) end })
  elseif kind == "shield" then
    local r = tr or ownHero
    local cx, cy = center(r)
    local size = math.max(r.w, r.h) * 1.15
    ring(cx, cy, size * 2, size, 0.35)
    self:SpawnSprite({ school = school, shape = "ring", x0 = cx, y0 = cy, x1 = cx, y1 = cy,
      dur = 0.5, s0 = size, s1 = size * 1.05, fade = "inout", delay = 0.3 })
    flash(cx, cy, size * 0.4, size, 0.4, 0.3)
    for k = 1, 4 do
      local a = k / 4 * math.pi * 2 + math.pi / 4
      self:SpawnSprite({ school = school, shape = "spark", x0 = cx + math.cos(a) * size / 2,
        y0 = cy + math.sin(a) * size / 2, x1 = cx + math.cos(a) * size / 2, y1 = cy + math.sin(a) * size / 2,
        dur = 0.4, s0 = 10 * scale, s1 = 34 * scale, fade = "inout", delay = 0.3 + 0.04 * k })
    end
  elseif kind == "secret" then
    --[[ A sigil drawn from the card into the hero: a spinning ring shrinking
         onto the portrait, where Hearthstone keeps its question marks. ]]
    local hx, hy = center(ownHero)
    local ty = hy + ownHero.h * 0.4
    -- the one effect that starts from the CARD: a Secret is the card itself
    -- going up into the portrait, not something the hero throws
    if not opts.power and self.flying and self.flyingCard.rect then sx, sy = center(self.flyingCard.rect) end
    self:SpawnSprite({ school = school, shape = "ring", x0 = sx, y0 = sy, x1 = hx, y1 = ty,
      dur = 0.45, s0 = 200 * scale, s1 = 40 * scale, spin = 6,
      onArrive = function(x, y)
        burst(x, y, 18); flash(x, y, 30 * scale, 130 * scale, 0.4)
        ring(x, y, 30 * scale, 160 * scale, 0.4)
      end })
    self:SpawnSprite({ school = school, x0 = sx, y0 = sy, x1 = hx, y1 = ty,
      dur = 0.45, s0 = 120 * scale, s1 = 60 * scale })
    self:SpawnSprite({ school = school, shape = "spark", x0 = sx, y0 = sy, x1 = hx, y1 = ty,
      dur = 0.45, s0 = 90 * scale, s1 = 44 * scale, spin = -4 })
  elseif kind == "summon" then
    --[[ One flash per minion, at the right end of the board where they land. ]]
    local rows = slotsOf("self")
    local last = rows[#rows]
    local n = spec.count or 1
    for k = 1, n do
      local cx, cy
      if last then
        cx, cy = center(last)
        cx = cx + last.w * 1.05 * (k - (n > 1 and 0 or 1))
        if L.field then cx = math.min(cx, L.field.x + L.field.w - last.w / 2) end
      else
        local field = L.field or { x = 0, w = self.frame:GetWidth() }
        local hx, hy = center(ownHero)
        cx, cy = field.x + field.w * k / (n + 1), hy + ownHero.h * 1.3 * (mine and 1 or -1)
      end
      local w = last and last.w or 90 * scale
      flash(cx, cy, 30 * scale, w * 2, 0.45, 0.07 * (k - 1))
      ring(cx, cy, 20 * scale, w * 1.6, 0.45, 0.07 * (k - 1))
      burst(cx, cy, 12)
    end
  else -- glow
    local list = spec.side == "self" and slotsOf("self") or {}
    if #list == 0 then list = { tr or ownHero } end
    for k, r in ipairs(list) do
      local cx, cy = center(r)
      self:SpawnSprite({ school = school, x0 = cx, y0 = cy + r.h * 0.5, x1 = cx, y1 = cy, dur = 0.55,
        s0 = r.w * 1.8, s1 = r.w * 0.9, fade = "inout", delay = 0.04 * (k - 1) })
      for j = 1, 3 do
        self:SpawnSprite({ school = school, shape = "spark", x0 = cx + (j - 2) * r.w * 0.3,
          y0 = cy + r.h * 0.6, x1 = cx + (j - 2) * r.w * 0.15, y1 = cy, dur = 0.5,
          s0 = 24 * scale, s1 = 12 * scale, fade = "inout", spin = 4, delay = 0.04 * (k - 1) + 0.05 * j })
      end
      burst(cx, cy, 14)
    end
  end
  return true
end

-- ============================================================ hero death

--[[ Choreography run by the board itself rather than by Main, for moments the
     board discovers from a snapshot (a hero at 0 health) instead of from an
     action. Ticked in TickFX; cleared by ResetMatch. ]]
function Board:RunTimeline(tl)
  if not tl then return end
  self.timelines = self.timelines or {}
  tl:Start()
  self.timelines[#self.timelines + 1] = tl
end

function Board:PlayHeroDeath(side)
  if not ns.Choreography or not ns.Choreography.HeroDeath then return end
  -- the dying hero's own last words (HeroVoice "death"), under the shatter
  local snap = self.snapshot or {}
  local hero = side == "foe" and snap.foeHero or snap.hero
  if hero and hero.cardId then ns.Sounds.PlayHero(hero.cardId, "death", true) end
  self:RunTimeline(ns.Choreography.HeroDeath(self:Stage(), { side = side }))
end

function Board:CrackHero(side, amount)
  local widget = side == "foe" and self.foeHero or self.hero
  local r = widget and widget.rect
  if not r then return end
  self.cracks = self.cracks or {}
  local crack = self.cracks[side]
  if not crack then
    crack = W.Unsnap(widget.frame:CreateTexture(nil, "OVERLAY", nil, 6))
    crack:SetTexture(ART .. "hero-crack.tga")
    self.cracks[side] = crack
  end
  local size = math.min(r.w, r.h) * 0.92
  crack:ClearAllPoints(); crack:SetSize(size, size)
  crack:SetPoint("CENTER", widget.frame, "CENTER", 0, r.h * 0.04)
  crack:SetAlpha(math.max(0, math.min(1, amount or 0)))
  crack:Show()
end

--[[ Twelve pieces of the portrait's own art, each a cell of a 4x3 grid,
     flung outward from the centre with gravity and a fade. Pieces are plain
     textures (no rotation: SetRotation would discard the cell's texcoords). ]]
Board.SHARD_COLS, Board.SHARD_ROWS = 4, 3
function Board:ShatterHero(side)
  local widget = side == "foe" and self.foeHero or self.hero
  local r = widget and widget.rect
  if not r then return end
  if self.cracks and self.cracks[side] then self.cracks[side]:Hide() end
  local texture = widget.art and widget.art:GetTexture()
  widget.frame:SetAlpha(0)
  self.shattered = self.shattered or {}
  self.shattered[side] = true
  self.shards = self.shards or {}
  self.shardPool = self.shardPool or {}
  local cols, rows = Board.SHARD_COLS, Board.SHARD_ROWS
  local size = math.min(r.w, r.h) * 0.8
  local x0, y0 = r.x + r.w / 2 - size / 2, r.y + r.h / 2 - size / 2
  local cw, ch = size / cols, size / rows
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local t = table.remove(self.shardPool) or self.fx:CreateTexture(nil, "OVERLAY", nil, 5)
      if texture then t:SetTexture(texture) else t:SetColorTexture(.6, .5, .4, 1) end
      t:SetTexCoord(col / cols, (col + 1) / cols, row / rows, (row + 1) / rows)
      t:SetSize(cw, ch); t:SetAlpha(1); t:Show()
      local cx, cy = x0 + (col + 0.5) * cw, y0 + size - (row + 0.5) * ch
      local dx, dy = cx - (r.x + r.w / 2), cy - (r.y + r.h / 2)
      local len = math.max(1, math.sqrt(dx * dx + dy * dy))
      local speed = 260 + 80 * ((row * cols + col) % 3)
      self.shards[#self.shards + 1] = { tex = t, x = cx, y = cy, w = cw, h = ch, age = 0,
        vx = dx / len * speed, vy = dy / len * speed + 140 }
    end
  end
  W.Burst(self.particles, "shatter", r.x + r.w / 2, r.y + r.h / 2, 40, fxRandom)
end

function Board:TickShards(dt)
  for i = #(self.shards or {}), 1, -1 do
    local p = self.shards[i]
    p.age = p.age + dt
    p.vy = p.vy - 900 * dt
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    local life = 1.1
    p.tex:ClearAllPoints()
    p.tex:SetPoint("CENTER", self.frame, "BOTTOMLEFT", p.x, p.y)
    local grow = 1 + 0.3 * math.min(1, p.age / life)
    p.tex:SetSize(p.w * grow, p.h * grow)
    p.tex:SetAlpha(math.max(0, 1 - p.age / life))
    if p.age >= life then
      p.tex:Hide(); table.remove(self.shards, i)
      self.shardPool[#self.shardPool + 1] = p.tex
    end
  end
end

function Board:ClearHeroDeath()
  self.timelines = {}
  self.shattered = {}
  for _, crack in pairs(self.cracks or {}) do crack:Hide() end
  for _, p in ipairs(self.shards or {}) do
    p.tex:Hide(); self.shardPool[#self.shardPool + 1] = p.tex
  end
  self.shards = {}
end

function Board:StopResultSound()
  self.resultSoundAt, self.resultSound = nil, nil
  ns.Sounds.Stop(self.resultHandle); self.resultHandle = nil
end

function Board:RefreshMute() W.RefreshSpeakers() end

function Board:ResetMatch()
  if self.emoteMenu then self.emoteMenu:Hide() end
  -- whatever an interrupted animation left behind goes too
  self:ClearRope()
  W.StopShake(self.shake)
  W.SetVignette(self.vignette, 0)
  for _,bubble in pairs(self.speech or {}) do bubble:Hide(); bubble:SetScript("OnUpdate",nil) end
  ns.Sounds.ResetMatch()
  for _, b in ipairs(self.burns or {}) do b.w.burning = false; b.w.frame:Hide() end
  self.burns, self.lastBurnSeq = {}, nil
  self:ClearPlacementPreview()
  self.presentedEventSeq = nil
  self.presentationLocked, self.pendingSnapshot, self.snapshot = false, nil, nil
  self:EndPlayAnimation()
  self.history, self.projectiles, self.tweens = {}, {}, {}
  self.outOfCards = nil
  self.bannerUntil = nil; self.banner:Hide(); self:HideTooltip()
  self:HideResult(); self.resultStart = nil; self.resultKind = nil
  self.postGameAt = nil; self.postGameNote = nil; self:SetPostGame(nil)
  self.resultSoundAt, self.resultSound = nil, nil; self:StopResultSound(); self:ClearHeroDeath(); self:ClearSprites()
  self.historyPreview:Hide()
  self.dragging, self.hoverIndex = nil, nil
  self.hero.frame:SetAlpha(1); self.foeHero.frame:SetAlpha(1)
  for _, button in ipairs(self.historyButtons) do button:Hide() end
  for _, hit in ipairs(self.hitLabels) do hit.active=false; hit.frame:Hide() end
end

local function isSecretCard(cardId)
  local printed = cardId and ns.PrintedCards[cardId]
  for _, tag in ipairs(printed and printed.scriptTags or {}) do
    if tag == "SECRET" then return true end
  end
  return false
end

local function historyCardStats(widget, stats)
  if not stats then return end
  widget.atk:SetText(tostring(stats.atk))
  widget.hp:SetText(tostring(math.max(0, stats.hp)))
  local printed = ns.PrintedCards[stats.cardId] or {}
  if stats.atk > (printed.atk or 0) then widget.atk:SetTextColor(.3,1,.3,1)
  elseif stats.atk < (printed.atk or 0) then widget.atk:SetTextColor(1,.3,.3,1)
  else widget.atk:SetTextColor(1,1,1,1) end
  if stats.hp < stats.maxHp then widget.hp:SetTextColor(1,.3,.3,1)
  elseif stats.maxHp > (printed.hp or 0) then widget.hp:SetTextColor(.3,1,.3,1)
  else widget.hp:SetTextColor(1,1,1,1) end
end

function Board:ShowHistory(anchor, entry)
  local preview = self.historyPreview
  preview:Hide()
  self:HideTooltip()
  local sourceCard = entry.cardId and ns.PrintedCards[entry.cardId]
  local targetCard = entry.targetCardId and ns.PrintedCards[entry.targetCardId]
  local results, grouped, order = {}, {}, {}
  local battlecry = false
  for _,tag in ipairs(sourceCard and sourceCard.scriptTags or {}) do
    if tag == "BATTLECRY" then battlecry = true end
  end
  local verb = entry.kind == "ATTACK" and "Attack" or entry.kind == "HERO_POWER" and "Hero Power"
    or sourceCard and sourceCard.type == "SPELL" and "Spell"
    or battlecry and "Battlecry"
    or sourceCard and sourceCard.type == "WEAPON" and "Equip" or "Summon"
  local heading = (entry.opponent and "Enemy" or "You") .. " · " .. verb
  if not sourceCard then heading = entry.label or heading end
  if entry.sourceStats and sourceCard and sourceCard.type == "MINION" then
    results[#results+1] = (entry.kind == "ATTACK" and "Attacker " or "Summoned ")
      .. entry.sourceStats.atk .. "/" .. math.max(0,entry.sourceStats.hp)
  end
  if entry.targetStats and targetCard and targetCard.type == "MINION" then
    results[#results+1] = "Target " .. entry.targetStats.atk .. "/" .. math.max(0,entry.targetStats.hp)
  end
  for i,outcome in ipairs(entry.outcomes or {}) do
    local key = tostring(outcome.targetId or outcome.cardId or i)..":"..tostring(outcome.heal or false)
    local row = grouped[key]
    if not row then row={cardId=outcome.cardId,amount=0,heal=outcome.heal}; grouped[key]=row; order[#order+1]=row end
    row.amount=row.amount+(outcome.amount or 0); row.health=outcome.health; row.armor=outcome.armor
  end
  for i=1,math.min(4,#order) do
    local row=order[i]
    local card=ns.PrintedCards[row.cardId]
    results[#results+1]=(card and card.name or "Target")..": "..(row.heal and "+" or "-")
      ..row.amount.." -> "..math.max(0,row.health or 0).." health"
      ..((row.armor or 0)>0 and (" + "..row.armor.." armor") or "")
  end
  if #order>4 then results[#results+1]="+"..(#order-4).." more effects" end
  self.tooltip.text:SetJustifyH("LEFT")
  self.tooltip:SetContent(heading, (sourceCard and sourceCard.name or "")
    .. (targetCard and (" -> " .. targetCard.name) or "")
    .. (#results>0 and ("\n" .. table.concat(results,"\n")) or ""), 280)
  self.tooltip:ClearAllPoints()
  self.tooltip:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
  self.tooltip:Show()
  if not entry.cardId then return end
  local h = math.min(self.frame:GetHeight()*0.36, 280)
  local w = h * Layout.design.CARD_W_OVER_H
  preview:SetSize(w*2+16,h)
  preview:ClearAllPoints()
  local x = self.frame:GetWidth()*0.16
  local y = math.max(12, math.min(self.frame:GetHeight()-h-48, (anchor.historyY or 0)-h/2))
  preview:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x, y)
  self.tooltip:ClearAllPoints()
  self.tooltip:SetPoint("BOTTOMLEFT", preview, "TOPLEFT", 0, 4)
  cardSetDescriptor(preview.source, self.resolver:Card(entry.cardId))
  historyCardStats(preview.source, entry.sourceStats)
  cardApplyRect(preview.source, {x=0,y=0,w=w,h=h})
  preview.source.frame:Show()
  if entry.targetCardId then
    cardSetDescriptor(preview.target, self.resolver:Card(entry.targetCardId))
    historyCardStats(preview.target, entry.targetStats)
    cardApplyRect(preview.target, {x=w+16,y=0,w=w,h=h})
    for _,outcome in ipairs(entry.outcomes or {}) do
      if not entry.targetStats and outcome.targetId and outcome.targetId == entry.targetId and outcome.health ~= nil then
        preview.target.hp:SetText(tostring(math.max(0,outcome.health)))
        preview.target.hp:SetTextColor(1,.3,.3,1)
      end
    end
    preview.target.frame:Show()
  else preview.target.frame:Hide() end
  preview:Show()
end

-- The corner badge on a history tile, cropped to its ink: {file, l, r, t, b}.
local HISTORY_BADGES = {
  ATTACK = {"hero_attack.tga", 0, .27, .72, 1},
  HERO_POWER = {"hero_power.tga", .06, .94, .02, .98},
  PLAY_CARD = {"mana_crystal.tga", .04, .98, .02, 1},
}

function Board:AddHistory(cardId, label, opponent, action, before, outcomes)
  if action and action.kind ~= "PLAY_CARD" and action.kind ~= "HERO_POWER" and action.kind ~= "ATTACK" then return end
  if opponent and isSecretCard(cardId) then cardId = nil; label = "Enemy: Secret" end
  local target = cardId and before and (before.targetCardId or (before.defender and before.defender.cardId))
  table.insert(self.history, 1, {cardId=cardId, label=label, opponent=opponent, targetCardId=target,
    sourceStats=cardId and before and (action and action.kind == "ATTACK" and before.sourceStats
      or outcomes and outcomes.sourceStats or before.sourceStats),
    targetStats=cardId and (outcomes and outcomes.targetStats or before and before.targetStats),
    targetId=before and (before.targetId or (before.defender and before.defender.instanceId)),
    outcomes=cardId and outcomes or {}, kind=action and action.kind or "PLAY_CARD"})
  if #self.history > 8 then table.remove(self.history) end
  for i, button in ipairs(self.historyButtons) do
    local entry = self.history[i]
    if entry then
      local descriptor = entry.cardId and self.resolver:Card(entry.cardId)
      button.icon:SetTexture(descriptor and descriptor.icon or (ns.HearthstoneArt or {}).cardback)
      button.text:SetText(descriptor and "" or "?")
      local badge = HISTORY_BADGES[entry.kind] or HISTORY_BADGES.PLAY_CARD
      button.actionIcon:SetTexture(ART .. badge[1])
      button.actionIcon:SetTexCoord(badge[2], badge[3], badge[4], badge[5])
      if entry.opponent then button.border:SetColorTexture(0.75,0.18,0.10,1)
      else button.border:SetColorTexture(0.16,0.45,0.75,1) end
      button:Show()
    else button:Hide() end
  end
  self:LayoutHistory()
end

function Board:LayoutHistory()
  if not self.L then return end
  local count=math.max(1,#self.history)
  for i,button in ipairs(self.historyButtons) do
    local r=self.L.historySlots[math.min(8,8-count+i)]
    button:ClearAllPoints()
    button:SetPoint("BOTTOMLEFT",self.frame,"BOTTOMLEFT",r.x,r.y)
    button:SetSize(r.w,r.h)
    button.historyY=r.y+r.h/2
    button.text:SetWidth(r.w-4)
    button.actionIcon:SetSize(r.w*.4,r.h*.4)
  end
end

function Board:Relayout()
  if self.presentationLocked then return end
  local boardOrigins={}
  for _,row in ipairs({self.myMinions or {},self.foeMinions or {}}) do
    for _,widget in ipairs(row) do
      if widget.boardIdentity then boardOrigins[widget.boardIdentity]=widget.rect end
    end
  end
  -- kept for a minion that leaves the board without dying (BurnCard)
  self.boardOrigins=boardOrigins
  local handOrigins={}
  for _,widget in ipairs(self.handWidgets or {}) do
    local key=widget.handIdentity
    if key then handOrigins[key]=widget.rect end
  end
  --[[ Taken down AFTER the origins are read, so a battlecry minion that was
       standing in as a ghost lands from where it stood; and BEFORE the rebuild,
       or the next tick would put the stepped-aside rects back onto widgets
       that no longer hold the same minions. ]]
  self:ClearPlacementPreview()
  local draws = {}
  for _,t in ipairs(self.tweens or {}) do
    if t.draw and t.age < t.dur then
      draws[#draws+1] = {identity=t.draw,from=t.w.rect,remaining=t.dur-t.age}
    end
  end
  self.tweens = {}
  local f = self.frame
  local w, h = f:GetWidth(), f:GetHeight()
  if not w or not h or w <= 0 or h <= 0 then return end
  local cornerW, cornerH
  if self.corner and self.corner.Extent then cornerW, cornerH = self.corner:Extent() end

  local L = Layout.Compute({
    width = w, height = h,
    handCount     = self.state.mulligan and 0 or self.state.handCount,
    foeHandCount  = self.state.foeHandCount,
    boardCount    = self.state.boardCount,
    foeBoardCount = self.state.foeBoardCount,
    hasWeapon     = self.state.hasWeapon,
    foeHasWeapon  = self.state.foeHasWeapon,
    maxMana       = self.state.maxMana,
    foeMaxMana    = self.state.foeMaxMana,
    chooseOne     = self.state.chooseOne ~= nil,
    chooseCount   = self.state.chooseOne
                    and #(self.state.chooseOne.options or {}) or nil,
    mulligan      = self.state.mulligan ~= nil,
    mulliganCount = self.state.mulligan
                    and #(self.state.mulligan.hand or {}) or nil,
    cornerW       = cornerW,
    cornerH       = cornerH,
  })
  local sizeChanged = (self.lastW ~= w or self.lastH ~= h)
  self.lastW, self.lastH = w, h
  self.L = L
  -- a stage made before this layout moves nothing now (stage:Board)
  self.layoutEpoch = (self.layoutEpoch or 0) + 1
  self:FitBoardArt(L)
  self:LayoutProfiles()
  self:LayoutHistory()
  if sizeChanged and self.resultKind and self.result:IsShown() then self:ShowResult(self.resultKind) end
  if sizeChanged and self.postGameState and self.postGame and self.postGame:IsShown() then
    self:SetPostGame(self.postGameState, self.postGameName)
  end

  self.releasingWidgets = true
  poolReleaseAll(self.handPool, true)
  poolReleaseAll(self.handHitPool, true)
  poolReleaseAll(self.boardPool, true)
  poolReleaseAll(self.choosePool, true)
  poolReleaseAll(self.crystalPool, true)
  poolReleaseAll(self.foeHandPool, true)
  poolReleaseAll(self.secretPool, true)
  poolReleaseAll(self.mulliganPool, true)
  self.releasingWidgets = false

  local snap = self.snapshot or {}

  --[[ A resize must NOT animate: dragging the window would leave every card
       chasing the cursor a sixth of a second behind. Cards slide when the game
       changes, not when the furniture does. ]]
  local animate = not sizeChanged

  --[[ ------------------------------------------------------------ YOUR HAND

       Two frames per card: the PICTURE, which lifts and grows and slides, and
       the HIT AREA, which sits at the card's resting place and never moves.
       The hover used to live on the picture, so pointing at a card moved it
       away from the pointer and the card flickered between its two states.

       The resting rects are kept on the board because the hover is re-applied
       from them without a relayout -- releasing and re-acquiring every widget
       in the middle of a mouse gesture is the other half of why the hand
       appeared to jump. ]]
  self.handWidgets, self.handRects = {}, {}
  for i, r in ipairs(L.handSlots) do
    local wdg = poolAcquire(self.handPool, f)
    local identity=snap.handStats and snap.handStats[i] and snap.handStats[i].instanceId
    if identity and handOrigins[identity] then cardApplyRect(wdg,handOrigins[identity]) end
    wdg.handIdentity=identity
    if self.resolver and snap.hand and snap.hand[i] then
      local descriptor = self.resolver:Card(snap.hand[i])
      local stats = snap.handStats and snap.handStats[i]
      if stats and stats.rulesText then descriptor.text = stats.rulesText end
      cardSetDescriptor(wdg, descriptor)
    end
    W.SetFaceDown(wdg, false)
    --[[ The picture never takes the mouse. Everything that reacts to the
         pointer is on the hit area below. ]]
    wdg.frame:EnableMouse(false)
    wdg.frame:SetScript("OnEnter", nil)
    wdg.frame:SetScript("OnLeave", nil)
    wdg.frame:SetScript("OnDragStart", nil)
    wdg.frame:SetScript("OnDragStop", nil)
    wdg.frame:SetScript("OnClick", nil)
    wdg.handIndex = i
    self.handWidgets[i] = wdg
    --[[ `lean` is the room the card's frame needs for its tilt, and `rot` is
         the tilt itself. Both travel on the rect so the widget layer applies
         them together -- a card given a rotation without the room for it turns
         inside its own rectangle and loses its corners. ]]
    r.lean = W.LeanInset(r.h / r.w)
    self.handRects[i]   = r
    self:PlaceCard(wdg, self:HandRectFor(i), animate)

    local playable = not snap.over and snap.playable and snap.playable[i]
    W.SetPlayable(wdg, playable, snap.affordable and snap.affordable[i])
    if snap.handCost and snap.handCost[i] then wdg.cost:SetText(tostring(snap.handCost[i])) end
    local handStats = snap.handStats and snap.handStats[i]
    if handStats and wdg.descriptor and wdg.descriptor.type == "MINION" then
      wdg.atk:SetText(tostring(handStats.atk))
      wdg.hp:SetText(tostring(handStats.health))
    end
    if not snap.over and (playable or snap.selectedHand == i) then
      wdg.glow:Show()
      if snap.selectedHand == i then wdg.glow:SetVertexColor(1, 0.95, 0.45, 0.8)
      -- Hearthstone's gold: playing it now triggers its Combo or condition
      elseif snap.poweredUp and snap.poweredUp[i] then wdg.glow:SetVertexColor(1, 0.72, 0.05, 1)
      else wdg.glow:SetVertexColor(0.08, 1, 0.12, 1) end
    else
      wdg.glow:Hide()
    end

    --[[ The hovered card draws over everything; otherwise later cards draw over
         earlier ones, which is what makes a fan look like a fan. ]]
    wdg.frame:SetFrameLevel(self.hoverIndex == i and HOVERED_LEVEL
                                                  or (HAND_LEVEL + i))

    --[[ The hit area. It stays at the RESTING rect even while the picture is
         lifted, so the pointer keeps the card it is pointing at until it
         actually leaves the place that card came from. Later cards overlap
         earlier ones, so later hit areas win. ]]
    local hit = poolAcquire(self.handHitPool, f)
    W.ApplyHitArea(hit, r, f, 70 + i)
    hit.frame:EnableMouse(not snap.over)
    hit.frame:SetScript("OnEnter", function() self:SetHover(i) end)
    hit.frame:SetScript("OnLeave", function() self:SetHover(nil) end)
    hit.frame:SetScript("OnDragStart", function() self:BeginDrag(wdg) end)
    hit.frame:SetScript("OnDragStop",  function() self:EndDrag(wdg) end)
    --[[ RIGHT-CLICK READS, LEFT-CLICK SELECTS. Reading a card is pure
         presentation -- it asks the engine nothing and changes nothing -- so it
         never becomes an intent and can never be refused. ]]
    hit.frame:SetScript("OnMouseDown", function(_, button)
      if button == "LeftButton" then self.suppressHandClick = nil end
    end)
    hit.frame:SetScript("OnClick", function(_, button)
      if self.cancelledDrag or self.suppressHandClick then return end
      if button == "RightButton" then
        return self:ShowInspect(snap.hand and snap.hand[i], snap.handStats and snap.handStats[i],
                                snap.handCost and snap.handCost[i])
      end
      self.onIntent({ kind = "CLICK_HAND", handIndex = i, button = button })
    end)
  end

  --[[ ----------------------------------------------------------- the boards

       Both boards draw from ONE pool, so `boardPool.used` is your minions
       followed by theirs and an index into it means nothing on its own. The FX
       layer needs to address "their minion 3", so the two sides are recorded
       separately here and the stage looks them up by side. ]]
  self.myMinions, self.foeMinions = {}, {}
  for i, r in ipairs(L.boardSlots) do
    local wdg = poolAcquire(self.boardPool, f)
    self.myMinions[i] = wdg
    local identity=snap.boardStats and snap.boardStats[i] and snap.boardStats[i].instanceId
    wdg.boardIdentity=identity
    if identity and boardOrigins[identity] then cardApplyRect(wdg,boardOrigins[identity])
    elseif identity then cardApplyRect(wdg,r) end
    if self.resolver and snap.board and snap.board[i] then
      cardSetDescriptor(wdg, self.resolver:Card(snap.board[i]))
    end
    --[[ The descriptor is the card as PRINTED. This is the minion as it is
         right now -- damage taken, buffs applied, frozen, silenced. Without it
         the board showed a 3/2 Yeti that was actually a 4/1, so damage you had
         just dealt appeared not to have landed. ]]
    W.SetLiveStats(wdg, snap.boardStats and snap.boardStats[i])
    W.SetFaceDown(wdg, false)
    self:PlaceCard(wdg, r, animate)

    --[[ READY TO ATTACK. Hearthstone rings every minion that can still swing,
         and without it you have to remember which of seven minions has already
         gone. The selected attacker is marked differently again. ]]
    if not snap.over and snap.selectedIndex == i then
      wdg.glow:Show(); wdg.glow:SetVertexColor(1.0, 0.95, 0.4, 0.75)
    elseif not snap.over and snap.canAttack and snap.canAttack[i] then
      wdg.glow:Show(); wdg.glow:SetVertexColor(0.08, 1, 0.12, 1)
    else
      wdg.glow:Hide()
    end

    wdg.frame:SetScript("OnEnter", function()
      self:ShowDescription(wdg.frame, snap.board and snap.board[i], snap.boardStats and snap.boardStats[i])
    end)
    wdg.frame:SetScript("OnLeave", function() self:HideTooltip() end)
    wdg.boardIndex = i
    wdg.frame:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        return self:ShowInspect(snap.board and snap.board[i],
                                snap.boardStats and snap.boardStats[i])
      end
      self:TargetClick({ kind = "CLICK_BOARD", boardIndex = i, button = button })
    end)
    --[[ DRAG A MINION AT WHAT IT SHOULD HIT. Declaring an attack is aiming,
         and aiming is a drag -- click-then-click was the only way to do it,
         which is neither the gesture the game copies nor the one anybody
         tries first. The drag START selects the attacker through the ordinary
         intent, so there is no second path through the rules. ]]
    wdg.frame:SetScript("OnDragStart", function()
      self:BeginTargetDrag({ kind = "CLICK_BOARD", boardIndex = i })
    end)
    wdg.frame:SetScript("OnDragStop", function() self:DropOnTarget() end)
    wdg.frame:SetScript("OnMouseDown",function() self.suppressTargetClick=nil; self.targetDropConsumed=nil end)
  end

  for i, r in ipairs(L.foeBoardSlots) do
    local wdg = poolAcquire(self.boardPool, f)
    self.foeMinions[i] = wdg
    local identity=snap.foeBoardStats and snap.foeBoardStats[i] and snap.foeBoardStats[i].instanceId
    wdg.boardIdentity=identity
    if identity and boardOrigins[identity] then cardApplyRect(wdg,boardOrigins[identity])
    elseif identity then cardApplyRect(wdg,r) end
    if self.resolver and snap.foeBoard and snap.foeBoard[i] then
      cardSetDescriptor(wdg, self.resolver:Card(snap.foeBoard[i]))
    end
    W.SetLiveStats(wdg, snap.foeBoardStats and snap.foeBoardStats[i])
    W.SetFaceDown(wdg, false)
    self:PlaceCard(wdg, r, animate)

    --[[ A LEGAL TARGET is lit red while you are aiming something. The snapshot
         carries the legal set as instance ids; the board only has positions, so
         it lights the whole enemy board when targeting is live and lets the
         engine refuse the illegal ones -- which it does, with a reason. ]]
    local targetId = snap.foeBoardStats and snap.foeBoardStats[i] and snap.foeBoardStats[i].instanceId
    local legal = false
    for _, id in ipairs(snap.targeting and snap.targeting.legal or {}) do
      if id == targetId then legal = true; break end
    end
    if legal then
      wdg.glow:Show(); wdg.glow:SetVertexColor(1.0, 0.35, 0.3, 0.45)
    else
      wdg.glow:Hide()
    end

    wdg.frame:SetScript("OnEnter", function()
      self:ShowDescription(wdg.frame, snap.foeBoard and snap.foeBoard[i], snap.foeBoardStats and snap.foeBoardStats[i])
    end)
    wdg.frame:SetScript("OnLeave", function() self:HideTooltip() end)
    wdg.frame:SetScript("OnMouseDown",function() self.suppressTargetClick=nil; self.targetDropConsumed=nil end)
    wdg.foeBoardIndex = i
    wdg.frame:SetScript("OnClick", function(_, button)
      if button == "RightButton" then
        return self:ShowInspect(snap.foeBoard and snap.foeBoard[i],
                                snap.foeBoardStats and snap.foeBoardStats[i])
      end
      self:TargetClick({ kind = "CLICK_FOE_BOARD", boardIndex = i, button = button })
    end)
  end

  --[[ THE ENEMY HAND, face down. Without it there is no sense of a person on
       the other side holding something -- and the count is real information a
       player uses constantly. ]]
  for i, r in ipairs(L.foeHandSlots) do
    local wdg = poolAcquire(self.foeHandPool, f)
    local fh = self.foeHover
    if fh and fh.handIndex == i then
      -- the card your opponent is holding up drops toward the table
      r = { x = r.x, y = r.y - r.h * 0.28, w = r.w, h = r.h, rot = r.rot, lean = r.lean }
    end
    cardApplyRect(wdg, r)
    W.SetFaceDown(wdg, true)
    wdg.frame:SetFrameLevel(fh and fh.handIndex == i and HOVERED_LEVEL or (5 + i))
    wdg.frame:EnableMouse(false)
  end

  -- ---------------------------------------------------- heroes and powers
  local res = self.resolver
  local function art(cardId)
    if not (res and cardId) then return nil end
    local d = res:Card(cardId)
    return d and d.icon, d and d.frameColor
  end

  --[[ Above the resting hand: see FURNITURE_LEVEL. Without this the fan covers
       the hero portrait, and the first thing it covers is your health. ]]
  for _, part in ipairs({ self.hero, self.foeHero, self.heroPower,
                          self.foeHeroPower, self.weapon, self.foeWeapon,
                          self.deckPip, self.foeDeckPip }) do
    part.frame:SetFrameLevel(FURNITURE_LEVEL)
  end
  self.manaHolder:SetFrameLevel(FURNITURE_LEVEL)

  W.ApplyPortrait(self.hero, L.hero, f)
  local heroIcon, heroColor = art(snap.hero and snap.hero.cardId)
  W.SetPortrait(self.hero, snap.hero, heroIcon, heroColor)

  W.ApplyPortrait(self.foeHero, L.foeHero, f)
  local foeIcon, foeColor = art(snap.foeHero and snap.foeHero.cardId)
  W.SetPortrait(self.foeHero, snap.foeHero, foeIcon, foeColor)
  --[[ The enemy hero is lit while you are aiming, because "can I go face" is
       the question a targeting prompt is usually about. ]]
  if snap.targeting then
    self.foeHero.glow:Show(); self.foeHero.glow:SetVertexColor(1, 0.35, 0.3, 0.45)
  else
    self.foeHero.glow:Hide()
  end

  --[[ YOUR HERO LIGHTS UP WHEN IT CAN SWING -- which it can, whenever it is
       holding a weapon. Nothing ever drew this, so a Rogue who had just
       equipped a dagger had no indication that their portrait was now an
       attacker, and no reason to try clicking it. ]]
  if not snap.over and snap.heroSelected then
    self.hero.glow:Show(); self.hero.glow:SetVertexColor(1.0, 0.95, 0.4, 0.75)
  elseif not snap.over and snap.heroCanAttack then
    self.hero.glow:Show(); self.hero.glow:SetVertexColor(0.08, 1, 0.12, 1)
  else
    self.hero.glow:Hide()
  end

  W.ApplyPortrait(self.heroPower, L.heroPower, f)
  local hpIcon = art(snap.heroPower and snap.heroPower.cardId)
  W.SetPortrait(self.heroPower, nil, hpIcon,
                (snap.heroPower and snap.heroPower.usable) and { 0.4, 1, 0.5 } or { 0.4, 0.4, 0.45 })
  W.FitPowerArt(self.heroPower, snap.heroPower and snap.heroPower.cardId)
  W.PlacePowerCost(self.heroPower, L.heroPower)
  self.heroPower.armor:SetText(snap.heroPower and tostring(snap.heroPower.cost or 2) or "")
  --[[ A used hero power TURNS OVER, not hidden: the spent token is still part
       of the board you are reading, showing its reverse face as it does in
       Hearthstone. ]]
  W.SetPowerSpent(self.heroPower, snap.heroPower and snap.heroPower.used)
  if not snap.over and snap.heroPower and snap.heroPower.usable then
    self.heroPower.glow:Show(); self.heroPower.glow:SetVertexColor(0.08, 1, 0.12, 1)
  else
    self.heroPower.glow:Hide()
  end

  W.ApplyPortrait(self.foeHeroPower, L.foeHeroPower, f)
  W.SetPortrait(self.foeHeroPower, nil, art(snap.foeHeroPower and snap.foeHeroPower.cardId),
                { 0.4, 0.4, 0.45 })
  W.FitPowerArt(self.foeHeroPower, snap.foeHeroPower and snap.foeHeroPower.cardId)
  --[[ THEIR POWER COSTS SOMETHING TOO. Your own power has carried its cost
       badge since it was drawn; theirs was an icon with an empty socket, which
       read as a power that costs nothing. Same placement, from the same rect,
       so the two sides of the table agree. ]]
  W.PlacePowerCost(self.foeHeroPower, L.foeHeroPower)
  self.foeHeroPower.armor:SetText(
    snap.foeHeroPower and tostring(snap.foeHeroPower.cost or 2) or "")
  --[[ Dimmed once they have spent it, exactly as yours is -- "have they still
       got their hero power this turn" is a question you ask constantly. ]]
  W.SetPowerSpent(self.foeHeroPower, snap.foeHeroPower and snap.foeHeroPower.used)

  if L.weapon and snap.weapon then
    self.weapon.frame:Show()
    W.ApplyPortrait(self.weapon, L.weapon, f)
    W.SetPortrait(self.weapon, { health = snap.weapon.health, atk = snap.weapon.atk },
                  art(snap.weapon.cardId), { 0.75, 0.7, 0.45 })
  else
    self.weapon.frame:Hide()
  end
  if L.foeWeapon and snap.foeWeapon then
    self.foeWeapon.frame:Show()
    W.ApplyPortrait(self.foeWeapon, L.foeWeapon, f)
    W.SetPortrait(self.foeWeapon, { health = snap.foeWeapon.health, atk = snap.foeWeapon.atk },
                  art(snap.foeWeapon.cardId), { 0.75, 0.7, 0.45 })
  else
    self.foeWeapon.frame:Hide()
  end

  -- ------------------------------------------------------- deck and mana
  W.ApplyDeckStack(self.deckPip, L.deck, f, snap.deckCount or 0)
  W.ApplyDeckStack(self.foeDeckPip, L.foeDeck, f, snap.foeDeckCount or 0)

  --[[ MANA. Ten crystals: filled, spent, or locked by Overload. Overload gets
       its own colour rather than simply being missing, because "why do I have
       less mana than last turn" is exactly the question the board should answer
       before it is asked. ]]
  local available = snap.mana or 0
  local locked = snap.lockedMana or 0
  for i, r in ipairs(L.manaCrystals) do
    local crystal = poolAcquire(self.crystalPool, f)
    crystal.frame:SetFrameLevel(FURNITURE_LEVEL)
    local state = "spent"
    if i <= available then state = "full"
    elseif i > (self.state.maxMana - locked) then state = "locked" end
    W.ApplyCrystal(crystal, r, f, state)
  end
  --[[ THEIR TRAY, along the top. Same pool, same crystal widget, same states:
       it is the same tray seen from the other side. Overload shows there too,
       because "why did they only have four" is a question about their board
       that you can answer by looking at it. ]]
  local foeAvailable = snap.foeMana or 0
  if L.foeManaReadout then
    local m = L.foeManaReadout
    local size = W.ApplyStyle(self.foeManaText, "number", nil, math.max(8, math.floor(m.h * 0.82)))
    self.foeManaText:ClearAllPoints()
    self.foeManaText:SetPoint("CENTER", f, "BOTTOMLEFT", m.x + m.w / 2, m.y + m.h / 2 - size * W.DIGIT_RISE)
    self.foeManaText:SetText(("%d/%d"):format(foeAvailable, self.state.foeMaxMana or 0))
    self.foeManaText:Show()
  else
    self.foeManaText:Hide()
  end

  --[[ The numbers go in the lozenge the board paints for them. It is there
       whether or not any crystals are drawn, so "0/10" on turn zero still has
       somewhere to be. ]]
  if L.manaReadout then
    local m = L.manaReadout
    -- lowered by the digit rise, or "10/10" rides high in its pill
    local size = W.ApplyStyle(self.manaText, "number", nil, math.max(8, math.floor(m.h * 0.82)))
    self.manaText:ClearAllPoints()
    self.manaText:SetPoint("CENTER", f, "BOTTOMLEFT", m.x + m.w / 2, m.y + m.h / 2 - size * W.DIGIT_RISE)
    self.manaText:SetText(("%d/%d"):format(available, self.state.maxMana))
    self.manaText:Show()
  else
    self.manaText:Hide()
  end
  local function owed(text, n, r, above)
    if not (r and n and n > 0) then text:Hide(); return end
    W.ApplyStyle(text, "caption", nil, math.max(9, math.floor(r.h * 0.6)), { 1, .55, .3 })
    text:ClearAllPoints()
    text:SetPoint(above and "BOTTOM" or "TOP", f, "BOTTOMLEFT", r.x + r.w / 2, above and (r.y + r.h + 2) or (r.y - 2))
    text:SetText(("Overloaded: %d next turn"):format(n))
    text:Show()
  end
  owed(self.overloadText, snap.pendingOverload, L.manaReadout, true)
  owed(self.foeOverloadText, snap.foePendingOverload, L.foeManaReadout, false)

  -- --------------------------------------------------------- end turn
  local e = L.endTurn
  -- exactly over the painted plaque (a hair larger, so its antialiased rim
  -- never shows); all of it is clickable
  local bw, bh = e.w * Board.END_TURN_COVER[1], e.h * Board.END_TURN_COVER[2]
  self.endTurn:ClearAllPoints()
  self.endTurn:SetSize(bw, bh)
  self.endTurn:SetPoint("CENTER", f, "BOTTOMLEFT", e.x + e.w / 2, e.y + e.h / 2)
  -- the lettering fills the glazed face (turn-button.tga: x .12-.86, y .21-.79)
  W.SetFitBox(self.endTurnLabel, bw * 0.58, bh * 0.40, math.max(7, math.floor(bh * 0.30)))
  self:RefreshEndTurn(false)

  -- ------------------------------------------------------------- the rope
  W.ApplyRope(self.rope, L.rope, f, self.ropeBurn or 0, self.ropeUrgency or 1)
  if self.ropeBurn then self.rope.frame:Show() else self.rope.frame:Hide() end

  -- A hero that has shattered stays gone through resizes (not before: it is
  -- still on screen, cracking, until HeroDeath breaks it).
  local shattered = self.shattered or {}
  if snap.over then
    if shattered.self then self.hero.frame:SetAlpha(0) end
    if shattered.foe then self.foeHero.frame:SetAlpha(0) end
  end
  self:LayoutSecrets(L, snap)
  self:LayoutChoosePrompt(L)
  self:LayoutMulligan(L, snap)
  -- Keep reused mouse frames visible throughout layout; hiding a frame during
  -- a drag can release mouse capture and fire OnLeave inside the rebuild.
  self.releasingWidgets = true
  for _, pool in ipairs({self.handPool,self.handHitPool,self.boardPool,self.choosePool,
                        self.crystalPool,self.foeHandPool,self.secretPool,self.mulliganPool}) do
    for _, widget in ipairs(pool.free) do widget.frame:Hide() end
  end
  self.releasingWidgets = false
  for _,draw in ipairs(draws) do
    local widget
    if draw.identity.foeIndex then widget=self.foeHandPool.used[draw.identity.foeIndex]
    else
      for i,st in ipairs(snap.handStats or {}) do
        if st.instanceId == draw.identity.entityId then widget=self.handWidgets[i]; break end
      end
    end
    draw.identity.silent = true   -- re-attached after a relayout: already heard
    self:AnimateDraw(widget,draw.from,draw.identity,draw.remaining)
  end
end

--[[ How the End Turn button looks right now: yellow and live on your turn,
     dimmed on theirs, brighter under the pointer. Never green -- a green
     "nothing left to do" state lit up on turn one before you had looked at
     your hand, and read as the game ending your turn for you. ]]
Board.END_TURN_COVER = { 1.02, 1.03 }   -- button size over the painted plaque
function Board:RefreshEndTurn(hovered)
  local snap = self.snapshot or {}
  local live = snap.myTurn and not snap.over
  local e = self.L and self.L.endTurn
  if not e then return end
  if snap.over then
    self.endTurnLabel:SetText(snap.winner == 0 and "DRAW" or "GAME OVER")
  elseif snap.myTurn then
    self.endTurnLabel:SetText("END TURN")
  else
    self.endTurnLabel:SetText("ENEMY TURN")
  end
  self.endTurnState = live and "yellow" or "grey"
  self.endTurnBg:SetTexture(ART .. (live and "turn-button.tga" or "turn-button-enemy.tga"))
  self.endTurnBg:SetVertexColor(1, 1, 1)
  self.endTurnBg:SetAlpha(1)
  self.endTurnGlow:SetAlpha(live and hovered and .22 or 0)
  self.endTurnHovered = hovered and true or false
  -- black on the yellow glaze, as in Hearthstone; a softer black on the grey
  if live then self.endTurnLabel:SetTextColor(.04, .03, .01, 1)
  else self.endTurnLabel:SetTextColor(.13, .12, .10, 1) end
  self.endTurnLabel:SetAlpha(1)
  self.endTurn:SetAlpha(1)
  self.endTurn:EnableMouse(live and true or false)
end

--[[ SECRETS, above each hero.

     YOURS BY NAME, THEIRS AS A COUNT. The snapshot deliberately does not carry
     what the opponent's secrets are -- both clients hold the whole game state
     in lockstep, so the place that decides what you may see is the snapshot,
     and the board can only draw what it is given. A pip with no name is
     therefore not a rendering choice here; it is all the information that
     exists on this side of the boundary. ]]
local SECRET_GEMS = { HUNTER = "secret_hunter", MAGE = "secret_mage", PALADIN = "secret_paladin" }
local function secretGem(pip, r, parent, class)
  local fr = pip.frame
  fr:ClearAllPoints()
  -- Square, centred in the laid-out slot, so the gem never stretches.
  local s = math.min(r.w, r.h)
  fr:SetSize(s, s)
  fr:SetPoint("CENTER", parent, "BOTTOMLEFT", r.x + r.w / 2, r.y + r.h / 2)
  pip.gem:SetTexture(ART .. (SECRET_GEMS[class or ""] or "secret_sheathed") .. ".tga")
  W.ApplyStyle(pip.mark, "mark", nil, math.max(8, math.floor(s * 0.55)))
  -- Set into the portrait's rim, so above the hero furniture it sits on.
  fr:SetFrameLevel(FURNITURE_LEVEL + 5)
end

function Board:LayoutSecrets(L, snap)
  local f = self.frame
  local function classOf(cardId)
    local p = cardId and ns.PrintedCards and ns.PrintedCards[cardId]
    return p and p.class
  end
  for i, secret in ipairs(snap.secrets or {}) do
    local r = L.secrets[i]
    if r then
      local pip = poolAcquire(self.secretPool, f)
      secretGem(pip, r, f, classOf(secret.cardId))
      --[[ The name on hover, because five identical pips tell you nothing about
           which of your own secrets is which. ]]
      pip.frame:SetScript("OnEnter", function() self:ShowSecretName(secret) end)
      pip.frame:SetScript("OnLeave", function() self:ShowSecretName(nil) end)
    end
  end
  for i = 1, (snap.foeSecretCount or 0) do
    local r = L.foeSecrets[i]
    if r then
      local pip = poolAcquire(self.secretPool, f)
      --[[ No name: this is the one thing on the board that is deliberately
           unreadable, and it is unreadable because the snapshot does not carry
           it. The COLOUR is public -- it is their hero's class. ]]
      secretGem(pip, r, f, classOf(snap.foeHero and snap.foeHero.cardId))
      pip.frame:SetScript("OnEnter", nil)
      pip.frame:SetScript("OnLeave", nil)
    end
  end
end

function Board:ShowSecretName(secret)
  self.mulliganTitle:ClearAllPoints()
  if not secret then
    if not self.state.mulligan then self.mulliganTitle:Hide() end
    return
  end
  self.mulliganTitle:SetPoint("BOTTOM", self.hero.frame, "TOP", 0, 26)
  self.mulliganTitle:SetText(secret.name)
  self.mulliganTitle:Show()
end

--[[ THE MULLIGAN PROMPT.

     The opening hand, big, with the cards you have marked for replacement
     dimmed and crossed. Everything else is behind a dimmer that swallows
     clicks, because nothing else may be done until this is confirmed.

     Marked cards are DIMMED rather than hidden, and the confirm button says
     what it will do -- "Keep 3" or "Replace 2" -- so the decision is legible
     without counting the cards. ]]
Board.DEAL_STAGGER = 0.22    -- seconds between dealt cards
Board.DEAL_TIME = 0.45       -- deck to slot

--[[ Move every mulligan card along its deal. Returns true while any card is
     still travelling (so the fx loop stays awake). ]]
function Board:TickMulliganDeal()
  if not (self.mulliganDealAt and self.L and self.L.deck) then return false end
  local now = GetTime and GetTime() or 0
  local deck = self.L.deck
  local moving = false
  for _, wdg in ipairs(self.mulliganPool.used) do
    local i, r = wdg.mulliganIndex, wdg.mulliganRest
    local at = i and self.mulliganDealAt[i]
    if at and r then
      local p = (now - at) / Board.DEAL_TIME
      if p < 0 then
        wdg.frame:Hide(); moving = true
      else
        wdg.frame:Show()
        if not self.mulliganSounded[i] then
          self.mulliganSounded[i] = true
          ns.Sounds.Play("card_deal")
        end
        if p < 1 then
          moving = true
          local e = 1 - (1 - p) * (1 - p)
          cardApplyRect(wdg, { x = deck.x + (r.x - deck.x) * e, y = deck.y + (r.y - deck.y) * e,
                               w = deck.w + (r.w - deck.w) * e, h = deck.h + (r.h - deck.h) * e })
          local down = p < 0.55
          if (wdg.faceDown or false) ~= down then W.SetFaceDown(wdg, down) end
          if wdg.cross then wdg.cross:SetShown(not down and wdg.crossWanted or false) end
        elseif wdg.dealing then
          cardApplyRect(wdg, r)
          if wdg.faceDown then W.SetFaceDown(wdg, false) end
          if wdg.cross then wdg.cross:SetShown(wdg.crossWanted or false) end
        end
        wdg.dealing = p < 1
      end
    end
  end
  return moving
end

function Board:LayoutMulligan(L, snap)
  local m = snap.mulligan
  if not (m and L.mulligan) then
    self.mulliganDim:Hide()
    self.mulliganConfirm:Hide()
    if not self.hoverSecret then self.mulliganTitle:Hide() end
    self.mulliganCards, self.mulliganDealAt, self.mulliganSounded = nil, nil, nil
    return
  end
  --[[ THE DEAL. Hearthstone deals the opening hand -- and any replacements
       after the mulligan -- card by card from the deck, each with the draw
       sound, turning face up on the way. A card is dealt when it first
       appears at its position (or a different card replaces it there); the
       deal is staggered, and TickFX keeps the cards moving. ]]
  local now = GetTime and GetTime() or 0
  self.mulliganCards = self.mulliganCards or {}
  self.mulliganDealAt = self.mulliganDealAt or {}
  self.mulliganSounded = self.mulliganSounded or {}
  for i, cardId in ipairs(m.hand) do
    if self.mulliganCards[i] ~= cardId then
      self.mulliganCards[i] = cardId
      local at = math.max(now + 0.05, (self.mulliganNextDeal or 0))
      self.mulliganDealAt[i] = at
      self.mulliganSounded[i] = nil
      self.mulliganNextDeal = at + Board.DEAL_STAGGER
    end
  end
  local f = self.frame
  local ml = L.mulligan

  self.mulliganDim:ClearAllPoints()
  self.mulliganDim:SetSize(ml.dim.w, ml.dim.h)
  self.mulliganDim:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ml.dim.x, ml.dim.y)
  self.mulliganDim:Show()

  local marked = 0
  for i, cardId in ipairs(m.hand) do
    local r = ml.cards[i]
    if r then
      local wdg = poolAcquire(self.mulliganPool, f)
      cardApplyRect(wdg, r)
      if self.resolver then cardSetDescriptor(wdg, self.resolver:Card(cardId)) end
      wdg.frame:SetFrameLevel(300)
      wdg.mulliganIndex, wdg.mulliganRest = i, r
      local isMarked = m.marked[i]
      if isMarked then marked = marked + 1 end
      --[[ A card you are throwing back wears Hearthstone's red cross, and
           stays readable underneath it -- you are still deciding. ]]
      if not wdg.cross then
        wdg.cross = W.Unsnap(wdg.frame:CreateTexture(nil, "OVERLAY", nil, 7))
        wdg.cross:SetTexture(ART .. "inhand_mulligan.tga")
        wdg.cross:SetAllPoints(wdg.skin)
      end
      wdg.frame:SetAlpha(isMarked and 0.8 or 1)
      wdg.crossWanted = isMarked and true or false
      if isMarked then
        wdg.cross:Show()
        wdg.glow:Show(); wdg.glow:SetVertexColor(1, 0.25, 0.2, 0.55)
      else
        wdg.cross:Hide()
        wdg.glow:Hide()
      end
      --[[ The Coin is in the hand and cannot be thrown back, so it does not
           respond -- the engine refuses it, and a card that visibly does
           nothing when clicked says so better than an error message would. ]]
      local isCoin = (cardId == "GAME_005")
      wdg.frame:SetScript("OnClick", function()
        if not isCoin then self.onIntent({ kind = "CLICK_MULLIGAN", handIndex = i }) end
      end)
    end
  end

  self:TickMulliganDeal()

  self.mulliganTitle:ClearAllPoints()
  self.mulliganTitle:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ml.title.x, ml.title.y)
  self.mulliganTitle:SetWidth(ml.title.w)
  -- who goes first, said where the hand is chosen: The Coin is not a hint everyone reads
  self.mulliganTitle:SetText(m.waiting
    and "Waiting for your opponent..."
    or (snap.goesFirst and "You go first -- choose cards to replace"
        or "You go second and get The Coin -- choose cards to replace"))
  self.mulliganTitle:Show()

  self.mulliganConfirm:ClearAllPoints()
  self.mulliganConfirm:SetSize(ml.confirm.w, ml.confirm.h)
  self.mulliganConfirm:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", ml.confirm.x, ml.confirm.y)
  W.SetFitBox(self.mulliganConfirmLabel, ml.confirm.w * 0.80, ml.confirm.h * 0.5,
              math.max(12, math.floor(ml.confirm.h * 0.40)))
  -- Hearthstone's button reads "Confirm" whatever is marked (the red crosses
  -- say what goes back), and it leaves once pressed: while the opponent
  -- decides, only the heading speaks.
  self.mulliganConfirmLabel:SetText("Confirm")
  self.mulliganConfirm:SetEnabledLook(true)
  self.mulliganConfirm:SetShown(not m.waiting)
end

--[[ Where a hand card actually sits: its resting rect, or the lifted one when
     it is the card being pointed at.

     A RESTING CARD IS CUT OFF BY THE BOTTOM EDGE -- you see its mana, art and
     name and nothing else. So the hover has a job beyond emphasis: it is the
     only way to read the rules text, and it has to lift the card ENTIRELY into
     view rather than merely nudging it. It is pulled up until it clears the
     bottom edge and grown, which is both the Hearthstone gesture and the only
     one that answers "what does this card actually do".

     Moving the picture this far is safe only because the hit area stayed
     behind, at the resting rect, so the pointer does not lose the card it is
     pointing at the instant the card reacts. ]]
Board.HOVER_SCALE = 1.22

function Board:HandRectFor(i)
  local r = self.handRects and self.handRects[i]
  if not r then return nil end
  if self.hoverIndex ~= i then return r end
  local w = r.w * Board.HOVER_SCALE
  local h = r.h * Board.HOVER_SCALE
  local height = (self.L and self.L.height) or self.frame:GetHeight()
  --[[ Clear of the bottom edge by a hair, so the whole card is readable. Never
       BELOW where it was resting, or hovering the bottom of a very tall window
       would push a card down. ]]
  local y = math.max(r.y, height * 0.012)
  --[[ THE CARD YOU ARE READING STANDS UP STRAIGHT. It keeps its frame padding
       so it does not change size as it rights itself, but the tilt goes: a
       card being read is a card held out flat, and the upright cost and name
       stop disagreeing with a leaning picture. ]]
  return { x = r.x - (w - r.w) / 2, y = y, w = w, h = h,
           rot = 0, lean = r.lean }
end

--[[ Hover state.

     THIS USED TO CALL Relayout. A relayout releases every pooled widget in the
     hand and re-acquires it -- hiding and re-showing the frames mid-gesture --
     and then tweened each card to its new place over 0.16s. Moving the pointer
     across a hand therefore tore the whole hand down and rebuilt it once per
     card, which is what "the cards disappear" was.

     Now it moves the pictures and nothing else, instantly: a hover must never
     lag the pointer, and nothing about the hand's CONTENTS has changed. ]]
function Board:SetHover(index)
  if self.presentationLocked or (self.snapshot or {}).over then return end
  if self.releasingWidgets then return end
  if self.hoverIndex == index then return end
  local old=self.hoverIndex
  self.hoverIndex = index
  if index then ns.Sounds.PlayCardHover() end
  local keep={}
  for _,t in ipairs(self.tweens) do
    if t.w.handIndex ~= old and t.w.handIndex ~= index then keep[#keep+1]=t end
  end
  self.tweens=keep
  self:ApplyHover()
  self:ReportHover()
end

function Board:ApplyHover()
  for i, wdg in ipairs(self.handWidgets or {}) do
    local rect = self:HandRectFor(i)
    local moving=false
    for _,t in ipairs(self.tweens) do if t.w==wdg then moving=true; break end end
    if rect and not moving then
      cardApplyRect(wdg, rect)
      wdg.frame:SetFrameLevel(self.hoverIndex == i and HOVERED_LEVEL
                                                    or (HAND_LEVEL + i))
    end
  end
end

--[[ Draw the Choose One prompt, or take it down.

     Each option renders as a full card from the MODE's own printed data, so it
     carries the mode's real name and rules text with no art and no per-card
     authoring -- the same floor every other card has. An option the engine
     marked unplayable is dimmed and does not respond, rather than being hidden:
     seeing that the Panther is unavailable because the board is full is the
     information the player needs to make the other choice. ]]
function Board:LayoutChoosePrompt(L)
  local pending = self.state.chooseOne
  if not pending or not L.choosePrompt then
    self.dimmer:Hide()
    self.chooseTitle:Hide()
    return
  end
  local f = self.frame
  local P = L.choosePrompt

  self.dimmer:ClearAllPoints()
  self.dimmer:SetSize(P.dim.w, P.dim.h)
  self.dimmer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", P.dim.x, P.dim.y)
  self.dimmer:Show()

  self.chooseTitle:ClearAllPoints()
  W.ApplyStyle(self.chooseTitle, "caption", nil, math.max(8, math.floor(P.title.h)), W.Colors.white)
  self.chooseTitle:SetPoint("BOTTOM", f, "BOTTOMLEFT",
                            P.title.x + P.title.w / 2, P.title.y)
  self.chooseTitle:Show()

  local options = pending.options or {}
  for i, r in ipairs(P.cards) do
    local opt = options[i]
    if opt then
      local wdg = poolAcquire(self.choosePool, f)
      cardApplyRect(wdg, r)
      if self.resolver then
        cardSetDescriptor(wdg, self.resolver:Card(opt.cardId))
        -- the mode's text with Spell Damage, as the card in hand shows it
        if opt.liveText then W.SetLiveStats(wdg, { rulesText = opt.liveText }) end
      end
      -- above the dimmer, which sits at 300
      wdg.frame:SetFrameLevel(310 + i)
      -- Hearthstone: an option you cannot choose has no glow; it is not faded.
      wdg.frame:SetAlpha(1)
      if opt.playable then
        wdg.glow:Show(); wdg.glow:SetVertexColor(0.08, 1, 0.12, 1)
      else
        wdg.glow:Hide()
      end
      wdg.frame:SetScript("OnDragStart", nil)
      wdg.frame:SetScript("OnDragStop", nil)
      wdg.chooseMode = i
      wdg.frame:SetScript("OnClick", function()
        if not opt.playable then return end
        self.onIntent({
          kind      = "PLAY_CARD",
          handIndex = pending.handIndex,
          position  = pending.position,
          mode      = i,
        })
      end)
    end
  end
end

-- ============================================================ drag and drop

function Board:ClearPlacementPreview()
  if self.placementGhost then self.placementGhost.frame:Hide() end
  for i,r in ipairs(self.placementOrigins or {}) do
    if self.myMinions[i] then cardApplyRect(self.myMinions[i],r) end
  end
  self.placementOrigins=nil
  if self.placementHiddenHand then
    self.placementHiddenHand.frame:SetAlpha(1)
    self.placementHiddenHand = nil
  end
end

--[[ Draw `id` as a minion standing in board slot `index`, with the minions
     already there stepped aside to make room. Undone by ClearPlacementPreview,
     which the fx tick runs every frame before drawing it again. ]]
function Board:ShowPlacementGhost(id, index, alpha)
  local layout=Layout.Compute({width=self.frame:GetWidth(),height=self.frame:GetHeight(),
    boardCount=#self.myMinions+1,foeBoardCount=self.state.foeBoardCount})
  if not self.placementGhost then
    self.placementGhost=makeCard(self.frame)
    self.placementGhost.frame:EnableMouse(false)
    self.placementGhost.frame:SetFrameLevel(170)
  end
  local ghost=self.placementGhost
  ghost.inPlay=true
  ghost.cardId=id
  cardSetDescriptor(ghost,self.resolver:Card(id))
  cardApplyRect(ghost,layout.boardSlots[index])
  ghost.glow:Hide(); ghost.frame:SetAlpha(alpha); ghost.frame:Show()
  self.placementOrigins={}
  for i,widget in ipairs(self.myMinions) do
    self.placementOrigins[i]=widget.rect
    cardApplyRect(widget,layout.boardSlots[i<index and i or i+1])
  end
  return layout.boardSlots[index]
end

--[[ Is a MINION from the hand waiting on a target? Returns the board slot it
     will land in (the drop position, else the right-hand end, which is where
     the engine puts an unpositioned minion) and its card id. ]]
function Board:PendingMinionSlot()
  local snap = self.snapshot or {}
  local t = snap.targeting
  if not t or t.heroPower or not t.handIndex then return nil end
  local id = snap.hand and snap.hand[t.handIndex]
  local printed = id and ns.PrintedCards[id]
  if not (printed and printed.type == "MINION") then return nil end
  local count = #(self.myMinions or {})
  local slot = t.position or (count + 1)
  if slot < 1 or slot > count + 1 then slot = count + 1 end
  return slot, id
end

function Board:BeginDrag(wdg)
  if self.presentationLocked or (self.snapshot or {}).over then return false end
  local snap=self.snapshot or {}
  if snap.playable and not snap.playable[wdg.handIndex] then return false end
  self.cancelledDrag = nil
  self.targetDropConsumed=nil
  self.suppressHandClick = nil
  self.dragging = wdg
  wdg.frame:SetFrameLevel(200)
  if wdg.glow then wdg.glow:Show() end
end

--[[ Drop resolution asks Layout for the insertion index, so the UI never decides
     board order itself -- positional adjacency is real gameplay and the geometry
     that governs it lives in one tested place. ]]
function Board:EndDrag(wdg)
  self:ClearPlacementPreview()
  if self.presentationLocked or (self.snapshot or {}).over then self.dragging=nil; self.dragAiming=nil; W.HideArrow(self.arrow); return false end
  if self.cancelledDrag == wdg then
    self.cancelledDrag = nil
    self.suppressHandClick = true
    W.HideArrow(self.arrow)
    return false
  end
  W.HideArrow(self.arrow)
  local L = self.L
  self.dragging = nil
  self.dragAiming = nil
  wdg.frame:SetAlpha(1)
  if self.dropPreview then self.dropPreview:Hide() end
  if wdg.glow then wdg.glow:Hide() end
  if not L then return end

  --[[ ALREADY AIMING: this drag is supplying the target.

       A card whose play is waiting on a target has no drop zone to land in --
       a targeted spell never reaches the board -- so the old code found no
       zone and snapped it back, and the only way to aim anything was to click
       the card and then click the target. Dropping it on the thing you want
       to hit is the gesture the game is copying. ]]
  local snap = self.snapshot or {}
  if snap.targeting then return self:DropOnTarget() end

  local x, y = self:CursorInBoard()

  --[[ Either row accepts placement onto our board. Resolve placement before
       targeting; a minion's battlecry is aimed separately after placement. ]]
  local idx = x and Layout.DropIndexAt(L, x, y) or nil
  local id = snap.hand and snap.hand[wdg.handIndex]
  local printed = id and ns.PrintedCards[id]
  local minion = printed and printed.type == "MINION"
  if (minion and idx) or (not minion and x and Layout.Contains(L.field, x, y)) then
    self.onIntent({ kind = "PLAY_CARD", handIndex = wdg.handIndex, position = minion and idx or nil })
    --[[ A MINION THAT THEN ASKS FOR A TARGET is a battlecry being aimed. The
         drop was a PLACE, not a target -- the slot under the pointer may well
         hold one of your own minions -- so the prompt is left up for the next
         click, and a right-click puts the card back in your hand. ]]
    if minion and (self.snapshot or {}).targeting then
      W.HideArrow(self.arrow)
      return true
    end
    local target = self:TargetAt(x, y)
    if target and (self.snapshot or {}).targeting then self.onIntent(target) end
    if (self.snapshot or {}).targeting then self.onIntent({kind="CANCEL"}) end
    W.HideArrow(self.arrow)
    return true
  end

  --[[ DROPPED ON SOMETHING. One gesture plays the card and aims it: the play
       is started, and if it turns out to want a target this drop is the click
       that supplies it.

       The snapshot is re-read in between rather than assumed, because starting
       the play is what decides whether a target is wanted at all -- a Choose
       One raises its mode prompt first and is NOT awaiting a target yet, and
       firing the drop into it would answer a question nobody had asked. ]]
  local target = x and self:TargetAt(x, y) or nil
  if target then
    self.onIntent({ kind = "PLAY_CARD", handIndex = wdg.handIndex })
    -- a minion's battlecry is aimed after it lands, exactly as above
    if minion and (self.snapshot or {}).targeting then
      W.HideArrow(self.arrow)
      return true
    end
    if (self.snapshot or {}).targeting then self.onIntent(target) end
    if (self.snapshot or {}).targeting then self.onIntent({kind="CANCEL"}) end
    W.HideArrow(self.arrow)
    return true
  end

  self:Relayout()      -- dropped on nothing: snap back
  return false
end

--[[ WHAT IS UNDER THE POINTER, as the intent that clicking it would send.

     The board reports POSITIONS, never entities -- an index is all that can
     safely cross the wire -- so this returns exactly the same intent shape the
     click handlers do. A drop is therefore indistinguishable from a click by
     the time it reaches the controller, which is why dragging needs no second
     path through the rules and cannot diverge from clicking.

     Enemies are tested before friendlies because an aimed effect is nearly
     always pointed at them, and the two hero portraits cannot overlap anyway. ]]
function Board:TargetAt(x, y)
  local L = self.L
  if not L then return nil end
  for i, r in ipairs(L.foeBoardSlots) do
    if Layout.Contains(r, x, y) then
      return { kind = "CLICK_FOE_BOARD", boardIndex = i }
    end
  end
  for i, r in ipairs(L.boardSlots) do
    if Layout.Contains(r, x, y) then
      return { kind = "CLICK_BOARD", boardIndex = i }
    end
  end
  if L.foeHero and Layout.Contains(L.foeHero, x, y) then
    return { kind = "CLICK_FOE_HERO" }
  end
  if L.hero and Layout.Contains(L.hero, x, y) then
    return { kind = "CLICK_HERO" }
  end
  return nil
end

--[[ Is an aim outstanding, in any of the forms it takes? ]]
function Board:Aiming()
  local snap = self.snapshot or {}
  return (snap.targeting or snap.selectedIndex or snap.heroSelected
          or self.dragging) and true or false
end

--[[ Watch for the right button while something is being aimed.

     Edge-triggered: the cancel fires once when the button goes down, not on
     every frame it is held, or a single click would cancel the aim and then
     keep cancelling whatever the player did next. ]]
function Board:PollCancel()
  local aiming = self:Aiming()
  if not aiming then
    self.rightWasDown = false
    return false
  end
  local down = IsMouseButtonDown and IsMouseButtonDown("RightButton") or false
  if down and not self.rightWasDown then
    self.rightWasDown = true
    self.cancelledAt = GetTime and GetTime() or 0   -- the same click's release is not a squelch
    self.cancelledDrag = self.dragging
    if self.dragging then self.dragging.frame:SetAlpha(1) end
    W.HideArrow(self.arrow)
    if self.dropPreview then self.dropPreview:Hide() end
    self.dragging = nil
    self.dragAiming = nil
    self.onIntent({ kind = "CANCEL" })
    self:Relayout()
  elseif not down then
    self.rightWasDown = false
  end
  return true
end

--[[ Finish an aiming drag. Only acts while the snapshot says a target is
     genuinely outstanding: a hero power that needed no target has already
     fired by now, and sending a stray click after it would select an attacker
     the player never picked. ]]
function Board:TargetClick(intent)
  if self.suppressTargetClick then self.suppressTargetClick=nil; return false end
  self.targetDropConsumed=nil
  return self.onIntent(intent)
end

function Board:BeginTargetDrag(intent)
  if self.presentationLocked or (self.snapshot or {}).over then return false end
  self.targetDropConsumed=nil
  self.suppressTargetClick=true
  return self.onIntent(intent)
end

function Board:DropOnTarget()
  if self.presentationLocked or self.targetDropConsumed then return false end
  self.targetDropConsumed=true
  W.HideArrow(self.arrow)
  local snap = self.snapshot or {}
  --[[ THREE THINGS COUNT AS AN OUTSTANDING AIM: a card or hero power waiting
       for a target, and a declared attacker waiting for something to hit. They
       are the same gesture and they finish the same way -- the only difference
       is which intent the click becomes, and the controller already knows. ]]
  local aiming = snap.targeting or snap.selectedIndex or snap.heroSelected
  if not aiming then
    self:Relayout()
    return false
  end
  local x, y = self:CursorInBoard()
  local intent = x and self:TargetAt(x, y) or nil
  if not intent then
    --[[ Released over nothing. The pending aim is cancelled rather than left
         hanging, because a targeting prompt you did not know was still up eats
         your next click somewhere else entirely. ]]
    self.onIntent({ kind = "CANCEL" })
    return false
  end
  self.onIntent(intent)
  return true
end

--- Cursor position in board-local coordinates, or nil if outside.
--[[ Is (x, y) on the sand -- the play surface -- rather than the table's rim,
     the corner scenery, or the margins? Heroes, cards, powers and the End Turn
     plaque are frames of their own and take their clicks before the board
     sees them, so only the bare surface reaches here. ]]
function Board:OnPlaySurface(x, y)
  local fr = x and self.L and self.L.field
  if not fr then return false end
  return x >= fr.x and x <= fr.x + fr.w and y >= fr.y and y <= fr.y + fr.h
end

--[[ HEARTHSTONE'S CLICK PUFF: a soft ring of dust where you clicked the empty
     board, however often you click. Pooled and capped, so spam-clicking never
     grows the frame count. ]]
Board.MAX_PUFFS = 8
function Board:ClickSurface(x, y)
  if not self:OnPlaySurface(x, y) then return false end
  self.puffs = self.puffs or {}
  local p
  for _, q in ipairs(self.puffs) do if not q.active then p = q; break end end
  if not p then
    if #self.puffs >= Board.MAX_PUFFS then
      -- recycle the oldest
      table.sort(self.puffs, function(a, c) return a.age > c.age end)
      p = self.puffs[1]
    else
      p = {}
      p.layer = self.puffLayer
      if not p.layer then
        self.puffLayer = CreateFrame("Frame", nil, self.frame)
        self.puffLayer:SetAllPoints(self.frame); self.puffLayer:SetFrameLevel(95)
        self.puffLayer:EnableMouse(false)
        p.layer = self.puffLayer
      end
      p.tex = p.layer:CreateTexture(nil, "OVERLAY")
      p.tex:SetTexture(ART .. "fx-dust.tga")
      p.ring = p.layer:CreateTexture(nil, "OVERLAY")
      p.ring:SetTexture(ART .. "fx-dust.tga")
      self.puffs[#self.puffs + 1] = p
    end
  end
  p.x, p.y, p.age, p.active = x, y, 0, true
  p.rot = fxRandom() * math.pi * 2
  p.size = math.max(40, math.min(96, (self.frame:GetHeight() or 720) * 0.085))
  self:TickPuffs(0)
  return true
end

Board.PUFF_TIME = 0.55
--[[ A LONG THINK. When the opponent has done nothing for THINK_AFTER seconds
     of their turn, their hero mutters one of Hearthstone's "Thinking" lines --
     once a turn, as the Innkeeper's heroes do. Any action resets the wait. ]]
Board.THINK_AFTER = 25
function Board:TickThinking()
  local snap = self.snapshot
  if not snap or snap.myTurn or snap.over or snap.mulligan then self.thinkSince = nil; return end
  local now = GetTime and GetTime() or 0
  local key = (snap.eventSeq or 0)
  if self.thinkKey ~= key then self.thinkKey, self.thinkSince = key, now; return end
  if not self.thinkSince or self.thoughtTurn == snap.turn then return end
  if now - self.thinkSince >= Board.THINK_AFTER then
    self.thoughtTurn = snap.turn
    local hero = snap.foeHero
    local pick = "thinking" .. fxRandom(1, 3)
    if hero and hero.cardId then ns.Sounds.PlayHero(hero.cardId, pick, true) end
  end
end

function Board:TickPuffs(dt)
  local any = false
  for _, p in ipairs(self.puffs or {}) do
    if p.active then
      p.age = p.age + dt
      local t = p.age / Board.PUFF_TIME
      if t >= 1 then
        p.active = false; p.tex:Hide(); p.ring:Hide()
      else
        any = true
        local e = 1 - (1 - t) ^ 3
        local s1, s2 = p.size * (0.45 + 0.75 * e), p.size * (0.3 + 1.1 * e)
        p.tex:ClearAllPoints(); p.tex:SetPoint("CENTER", self.frame, "BOTTOMLEFT", p.x, p.y + 4 * e)
        p.tex:SetSize(s1, s1 * 0.8); p.tex:SetAlpha(0.75 * (1 - t))
        p.ring:ClearAllPoints(); p.ring:SetPoint("CENTER", self.frame, "BOTTOMLEFT", p.x, p.y)
        p.ring:SetSize(s2, s2 * 0.55); p.ring:SetAlpha(0.45 * (1 - t) ^ 1.5)
        if p.tex.SetRotation then p.tex:SetRotation(p.rot + t * 0.6) end
        p.tex:Show(); p.ring:Show()
      end
    end
  end
  return any
end

function Board:CursorInBoard()
  local f = self.frame
  local scale = f:GetEffectiveScale()
  if not GetCursorPosition then return nil end
  local cx, cy = GetCursorPosition()
  if not cx then return nil end
  local x = cx / scale - f:GetLeft()
  local y = cy / scale - f:GetBottom()
  if x < 0 or y < 0 or x > f:GetWidth() or y > f:GetHeight() then return nil end
  return x, y
end

-- ============================================================== the stage

--[[ The `stage` that Choreography.lua animates against. Every method returns a
     handle with the setters the choreographies call. This is the ONLY place the
     tested choreography data meets real frames -- and because every stage method
     is optional on the choreography side, a gap here degrades to a no-op rather
     than an error. ]]
function Board:Stage()
  local b = self
  local stage = {}
  local soundSnapshot=b.snapshot or {}
  local resolvedSnapshot=b.pendingSnapshot
  local playedSoundId=b.flyingCardId
  function stage:Impact() b:PresentImpact() end

  --[[ An animation handle is bound to the widget AS IT IS NOW.

       Choreography runs over hundreds of milliseconds and holds this handle the
       whole time. The widget underneath is pooled, so it can be released and
       reissued as a different card mid-animation -- and then the death fade of
       something that died half a second ago fades whatever is in that frame
       now. That is what "cards disappear for a bit" during attacks and deaths
       was, and it is also why cards were sometimes simply invisible: a fade
       that finished after the reissue left alpha at zero on a live card.

       Capturing the generation turns every such write into a no-op. ]]
  local function handleFor(widget)
    local frame = widget and widget.frame
    local gen = widget and widget.gen
    local h = {}
    local function live() return widget ~= nil and widget.gen == gen end
    local base=widget and widget.rect
    local ox,oy,scale,rotation=0,0,1,widget and widget.lean or 0
    local function applyCard()
      if not (live() and base and widget.cost) then return false end
      frame:SetScale(1)
      cardApplyRect(widget,{x=base.x+ox-base.w*(scale-1)/2,y=base.y+oy-base.h*(scale-1)/2,
        w=base.w*scale,h=base.h*scale,rot=rotation,lean=base.lean})
      return true
    end
    function h:Pos(x, y)
      if not frame or not live() then return h end
      ox,oy=x or 0,y or 0
      if applyCard() then return h end
      local r = widget.rect
      --[[ Offsets are RELATIVE to where the layout put the widget. A
           choreography that set an absolute position would fight the solver and
           leave cards wherever the animation stopped.

           The frame of a card that can lean is larger than the card, so its
           corner sits `padX/padY` outside -- applied here too, or nudging a
           card also shifts it by the padding. ]]
      frame:ClearAllPoints()
      frame:SetPoint("BOTTOMLEFT", b.frame, "BOTTOMLEFT",
                     (r and r.x or 0) - (widget.padX or 0) + (x or 0),
                     (r and r.y or 0) - (widget.padY or 0) + (y or 0))
      return h
    end
    function h:Scale(sx)
      scale=math.max(.01,sx or 1)
      if applyCard() then return h end
      if frame and live() then frame:SetScale(math.max(0.01, sx or 1)) end
      return h
    end
    function h:Alpha(a)
      if frame and live() then frame:SetAlpha(a or 1) end
      return h
    end
    function h:Rot(r)
      rotation=r or 0
      if applyCard() then return h end
      --[[ A frame cannot rotate, but its textures can. Rotating the art alone
           is most of the read of a card tilting as it is played. ]]
      if live() and widget.art and widget.art.SetRotation then
        if widget.anim then W.SetLean(widget, r or 0) end
      end
      return h
    end
    function h:Flip()
      if live() then W.SetFaceDown(widget, not widget.faceDown) end
      return h
    end
    function h:Glow(r, g, bl, a)
      if live() and widget.glow then
        if (a or 0) <= 0.01 then widget.glow:Hide()
        else widget.glow:Show(); widget.glow:SetVertexColor(r, g, bl, a) end
      end
      return h
    end
    function h:Burst(kind)
      local r = live() and widget.rect or nil
      if r then
        W.Burst(b.particles, kind or "impact", r.x + r.w / 2, r.y + r.h / 2, 14, fxRandom)
      end
      return h
    end
    return h
  end

  --[[ THE CARD AN ANIMATION IS ABOUT.

       For a play, that is the card that has just LEFT the hand, so it is the
       flying copy rather than a hand slot -- see b.flyingCard. Reading the hand
       here is what made cards go invisible: by the time the animation runs, the
       slot holds the next card along, and the play's fade-out was landing on
       it.

       Falls back to the hand slot when nothing is in flight, which is what a
       choreography played outside a match (the collection, a pack) wants. ]]
  function stage:Card(i)
    if b.flying then return handleFor(b.flyingCard) end
    return handleFor(b.handPool.used[i])
  end

  function stage:PlayDestination(slot, mine)
    local from = b.flying and b.flyingCard.rect
    if not from then return nil end
    local count = mine == false and b.state.foeBoardCount or b.state.boardCount
    local layout = Layout.Compute({ width = b.frame:GetWidth(), height = b.frame:GetHeight(),
      boardCount = resolvedSnapshot and #resolvedSnapshot.board or
        (mine == false and b.state.boardCount or math.min(7,count + 1)),
      foeBoardCount = resolvedSnapshot and #resolvedSnapshot.foeBoard or
        (mine == false and math.min(7,count + 1) or b.state.foeBoardCount) })
    local row = mine == false and layout.foeBoardSlots or layout.boardSlots
    local to = row[math.max(1, math.min(slot, #row))]
    if not to then return nil end
    b.playLanding = to
    return { x = to.x + to.w / 2 - from.x - from.w / 2,
             y = to.y + to.h / 2 - from.y - from.h / 2 }
  end

  function stage:MorphMinion(v,slot,mine,instanceId)
    local r=b.playLanding
    if not r or not b.flying then return end
    if not b.summonPortrait then
      b.summonPortrait=makeCard(b.frame)
      b.summonPortrait.frame:EnableMouse(false)
      b.summonPortrait.frame:SetFrameLevel(220)
    end
    local w=b.summonPortrait
    w.inPlay=true
    cardSetDescriptor(w,b.flyingCard.descriptor)
    local snap=resolvedSnapshot or {}
    local stats=mine == false and snap.foeBoardStats or snap.boardStats
    local live
    for _,entry in ipairs(stats or {}) do
      if instanceId and entry.instanceId == instanceId then live=entry; break end
    end
    -- Never borrow a token's stats when a battlecry changes the row.
    local ids=mine == false and snap.foeBoard or snap.board
    if not instanceId and ids and ids[slot]==b.flyingCardId then live=stats and stats[slot] end
    W.SetLiveStats(w,live)
    local scale=1+0.12*(1-v)
    cardApplyRect(w,{x=r.x-r.w*(scale-1)/2,y=r.y-r.h*(scale-1)/2,w=r.w*scale,h=r.h*scale})
    w.glow:Hide(); w.frame:SetAlpha(v); w.frame:Show()
    b.flyingCard.frame:SetAlpha(1-v)
  end

  function stage:LandingImpact()
    local r=b.playLanding
    if r then W.Burst(b.particles,"summon_dust",r.x+r.w/2,r.y+r.h/2,12,fxRandom) end
  end

  --[[ A minion on a specific board. `side` is "self" or "foe"; the index is the
       board slot, left to right, exactly as the engine numbers it. ]]
  function stage:Minion(side, i)
    local list = (side == "foe") and b.foeMinions or b.myMinions
    return handleFor(list and list[i])
  end

  --[[ HOW FAR IT IS FROM THE ATTACKER TO WHAT IT IS HITTING.

       The attack sequence used to lunge a fixed 120 pixels straight up or down,
       because the choreography is pure and has no idea where anything is. So a
       minion attacking the far end of the enemy board lunged at empty table,
       and one attacking the hero lunged past it. Asking the stage is the only
       way to get the real geometry, and it is the stage's business: it is the
       one thing in the project that knows where the widgets ended up. ]]
  function stage:Delta(aSide, aIdx, dSide, dIdx, dIsHero, aIsHero)
    local function rectFor(side, idx, isHero)
      if isHero then
        local hero = (side == "foe") and b.foeHero or b.hero
        return hero and hero.rect
      end
      local list = (side == "foe") and b.foeMinions or b.myMinions
      local wdg = list and list[idx]
      return wdg and wdg.rect
    end
    local a = rectFor(aSide, aIdx, aIsHero)
    local d = rectFor(dSide, dIdx, dIsHero)
    if not (a and d) then return nil end
    return (d.x + d.w / 2) - (a.x + a.w / 2),
           (d.y + d.h / 2) - (a.y + a.h / 2)
  end

  --[[ The board as it stood when this stage was made -- before the action's
       own snapshot lands. ]]
  local stagedCounts = { mine = b.state.boardCount or 0, foe = b.state.foeBoardCount or 0 }
  local stagedLayout = b.layoutEpoch
  function stage:Board()
    local h = {}
    --[[ THE SHOVE: neighbours slide apart to make room for a minion landing
         between them. `amount` runs 0..1 over the beat, so the offset is
         applied live rather than by relayout.

         THE ROW IT MAKES ROOM IN IS FIXED WHEN THE STAGE IS MADE. It was
         recomputed on every beat from the board's live count -- and once the
         play's own snapshot had been laid out (a long battlecry, a Gnomish
         Inventor's draw, can outlast the presentation lock), that count
         already included the new minion, so the last beats pushed the row
         apart for an eighth minion that did not exist and left it off
         centre. A shove after the board has been laid out again does
         nothing: the layout already put everyone where they belong. ]]
    local starts, row = {}, nil
    function h:Shove(slot, amount, mine)
      if b.layoutEpoch ~= stagedLayout then return h end
      local used = (mine == false and b.foeMinions or b.myMinions) or {}
      if not row then
        local L=Layout.Compute({width=b.frame:GetWidth(),height=b.frame:GetHeight(),
          boardCount=resolvedSnapshot and #resolvedSnapshot.board or math.min(7,stagedCounts.mine+(mine == false and 0 or 1)),
          foeBoardCount=resolvedSnapshot and #resolvedSnapshot.foeBoard or math.min(7,stagedCounts.foe+(mine == false and 1 or 0))})
        row=mine == false and L.foeBoardSlots or L.boardSlots
      end
      for i, wdg in ipairs(used) do
        starts[i]=starts[i] or wdg.rect
        local targetIndex=i<(slot or 1) and i or i+1
        local oldStats=mine == false and soundSnapshot.foeBoardStats or soundSnapshot.boardStats
        local newStats=resolvedSnapshot and (mine == false and resolvedSnapshot.foeBoardStats or resolvedSnapshot.boardStats)
        if oldStats and oldStats[i] and newStats then
          targetIndex=nil
          for j,entry in ipairs(newStats) do
            if entry.instanceId==oldStats[i].instanceId then targetIndex=j; break end
          end
        end
        local r,to = starts[i],targetIndex and row[targetIndex]
        if r and to then
          cardApplyRect(wdg,{x=r.x+(to.x-r.x)*amount,y=r.y+(to.y-r.y)*amount,
            w=r.w+(to.w-r.w)*amount,h=r.h+(to.h-r.h)*amount})
        end
      end
      return h
    end
    return h
  end

  function stage:Screen()
    local h = {}
    function h:Shake(amount) W.Shake(b.shake, amount or 0); return h end
    function h:Vignette(a) W.SetVignette(b.vignette, a or 0); return h end
    return h
  end

  function stage:Hero(side)
    --[[ Hero impacts land on a real portrait now. `side` is "self" or "foe";
         anything else is the player, which is the safer default -- a stray hit
         marker on your own hero is noticed and fixed, one on nobody is not. ]]
    local widget = (side == "foe") and b.foeHero or b.hero
    local h = handleFor(widget)
    function h:Shake(amount) W.Shake(b.shake, amount or 0); return h end
    function h:Flash(r, g, bl, a)
      if widget and widget.glow then
        if (a or 0) <= 0.01 then widget.glow:Hide()
        else widget.glow:Show(); widget.glow:SetVertexColor(r, g, bl, a) end
      end
      return h
    end
    -- Cracks spreading over the portrait (HeroDeath), 0..1.
    function h:Crack(amount) b:CrackHero(side, amount); return h end
    -- The portrait bursts into pieces of itself and is gone.
    function h:Shatter() b:ShatterHero(side); return h end
    return h
  end

  --[[ THE ROPE AND THE TOASTS. Choreography has driven Burn/Urgency and
       Shimmer/Count since before anything drew them; these are the frames that
       finally listen. ]]
  function stage:Toast(kind, data)
    local h = {}
    if kind == "rope" then
      --[[ Bound to the turn this rope was lit for. When the turn ends the epoch
           moves on and the timeline still running behind it writes to nothing,
           instead of showing the rope again on the very next frame. ]]
      local epoch = b.ropeEpoch or 0
      function h:Burn(v)
        if (b.ropeEpoch or 0) ~= epoch then return h end
        b.ropeBurn = v
        if b.L then W.ApplyRope(b.rope, b.L.rope, b.frame, v, b.ropeUrgency or 1) end
        b.rope.frame:Show()
        return h
      end
      function h:Urgency(level)
        if (b.ropeEpoch or 0) ~= epoch then return h end
        b.ropeUrgency = level
        return h
      end
      function h:Pos() return h end
      function h:Alpha() return h end
      return setmetatable(h, { __index = function() return function() return h end end })
    end

    local t = b.toast
    t.frame:Show()
    W.FillToast(t, kind, data, b.resolver)
    function h:Pos(x, y)
      t.frame:ClearAllPoints()
      t.frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24 + (x or 0), -180 + (y or 0))
      return h
    end
    function h:Alpha(a)
      a = a or 1
      t.frame:SetAlpha(a)
      --[[ Hidden when faded out, SHOWN when faded in. Hiding only was a real
           bug: every slide-in starts at alpha 0, so the toast hid itself on the
           first frame of its own arrival and never came back. And a toast left
           invisible rather than hidden still eats the mouse where it sits,
           which is a baffling thing to hit in the middle of a fight. ]]
      if a <= 0.02 then t.frame:Hide() else t.frame:Show() end
      return h
    end
    function h:Shimmer(v) t.shine:SetAlpha((v or 0) * 0.5); return h end
    function h:Count(n)
      if kind == "pack" then t.sub:SetText(("%d pack%s waiting"):format(n or 1, (n or 1) == 1 and "" or "s")) end
      return h
    end
    return setmetatable(h, { __index = function() return function() return h end end })
  end

  function stage:EffectPoint(opts)
    if not b.L then return nil end
    -- New tokens have no position in the old layout. Use their resolved
    -- identity and row size, including battlecries which fill the board.
    if opts.instanceId and resolvedSnapshot and not opts.isHero then
      local old=opts.side=="self" and soundSnapshot.boardStats or soundSnapshot.foeBoardStats
      local existed=false
      for _,e in ipairs(old or {}) do if e.instanceId==opts.instanceId then existed=true; break end end
      if not existed then
        local stats=opts.side=="self" and resolvedSnapshot.boardStats or resolvedSnapshot.foeBoardStats
        for i,e in ipairs(stats or {}) do
          if e.instanceId==opts.instanceId then
            local layout=Layout.Compute({width=b.frame:GetWidth(),height=b.frame:GetHeight(),
              boardCount=#resolvedSnapshot.board,foeBoardCount=#resolvedSnapshot.foeBoard})
            local r=(opts.side=="self" and layout.boardSlots or layout.foeBoardSlots)[i]
            if r then return {x=r.x+r.w/2,y=r.y+r.h/2} end
          end
        end
      end
    end
    local r
    if opts.isHero then r = opts.side == "self" and b.L.hero or b.L.foeHero
    else r = (opts.side == "self" and b.L.boardSlots or b.L.foeBoardSlots)[opts.index or 1] end
    r = r or b.L.field
    return {x=r.x+r.w/2, y=r.y+r.h/2}
  end

  function stage:AbilityBurst(point, kind)
    local schools = {deathrattle="fire", damage="hit_spark", heal="holy",
      summon="summon_dust", silence="arcane", battlecry="golden_sparkle",
      buff="holy", transform="arcane"}
    W.Burst(b.particles, schools[kind] or "arcane", point.x, point.y, 24, fxRandom)
  end

  function stage:Projectile(mine, side, index, isHero, targeted, fromHero)
    if not b.L or #b.projectiles >= 8 then return end
    local source = mine and b.L.heroPower or b.L.foeHeroPower
    if fromHero then source = mine and b.L.hero or b.L.foeHero
    elseif b.flying and b.flyingCard.rect then source = b.flyingCard.rect end
    local dest
    if targeted then
      if isHero then dest = side == "self" and b.L.hero or b.L.foeHero
      else dest = (side == "self" and b.L.boardSlots or b.L.foeBoardSlots)[index or 1] end
    end
    dest = dest or b.L.field
    b.projectiles[#b.projectiles+1] = {age=0, x=source.x+source.w/2, y=source.y+source.h/2,
      tx=dest.x+dest.w/2, ty=dest.y+dest.h/2}
  end

  function stage:Sound(key, step)
    -- The rope's fuse runs for as long as the rope does (see StartRopeAudio),
    -- and the burn-out cue belongs to the rope that was lit, not a later turn.
    if key == "rope_start" then return b:StartRopeAudio() end
    if key == "rope_end" then
      if b.ropeAudioEpoch ~= nil and b.ropeAudioEpoch == (b.ropeEpoch or 0) then
        b:StopRopeAudio()
        -- the burn-out cue only for someone looking at the table
        if b.frame:IsShown() then return ns.Sounds.Play("rope_end") end
      end
      return
    end
    if key == "summon" or key == "summon_heavy" or key == "spell_cast" then
      return ns.Sounds.PlayCard("summon",playedSoundId,key)
    end
    return ns.Sounds.Play(key, step)
  end
  -- A minion's trigger recording, if Hearthstone has one (Ragnaros does);
  -- otherwise the pulse carries it silently.
  function stage:TriggerSound(cardId)
    local entry = cardId and ns.CardSounds and ns.CardSounds[cardId]
    if entry and entry.trigger then return ns.Sounds.PlayCard("trigger", cardId) end
  end
  function stage:PowerSound(mine)
    local power=mine == false and soundSnapshot.foeHeroPower or soundSnapshot.heroPower
    return ns.Sounds.PlayHeroPower(power and power.cardId)
  end
  function stage:ActorSound(kind,side,index,isHero,fallback)
    local row=side == "foe" and soundSnapshot.foeBoard or soundSnapshot.board
    local hero=side == "foe" and soundSnapshot.foeHero or soundSnapshot.hero
    local id=isHero and hero and hero.cardId or row and row[index or 1]
    if isHero and kind=="attack" and id then return ns.Sounds.PlayHeroAttack(id) end
    return ns.Sounds.PlayCard(kind,id,fallback)
  end

  --[[ THE SPELL'S OWN EFFECT (Client/FX/SpellFX.lua decides which): a
       fireball streaking at its target, fire raining on their side, a holy
       ring bursting out from your hero. Drawn with the board's sprite pool;
       the damage numbers still land on the choreography's Impact beat. ]]
  function stage:SpellEffect(opts)
    return b:SpellEffect(opts or {})
  end

  function stage:Particles(kind, x, y, n)
    --[[ Coordinates arrive relative to the middle of the action; the burst is
         centred on the board when the choreography does not say where. ]]
    local cw, ch = b.frame:GetWidth() / 2, b.frame:GetHeight() / 2
    W.Burst(b.particles, kind, cw + (x or 0), ch + (y or 0), n or 12, fxRandom)
  end

  return stage
end

--[[ WHICH TABLE THIS MATCH IS PLAYED ON.

     Hearthstone picks a board at the start of every match, and playing every
     game of your life on one table is the single cheapest thing that makes a
     card game feel like software rather than a place.

     THE BOARDS ARE DISCOVERED, NOT LISTED. `Art/boardN.tga` files are
     registered by tools/fetch_art.py into `HearthstoneArt.boards`; whatever is
     actually installed is what is drawn, and an installation with one board --
     or none, which falls back to the flat colour underneath -- is a correct
     installation rather than a broken one. That is the same rule every other
     asset in this addon follows: there is no API that can tell us a texture
     path exists, so absent art must degrade rather than fail.

     `seed` picks it. In a duel both clients pass the match's agreed seed, so
     the two players are looking at the same table -- which they would notice
     immediately if they were not, and which no amount of care in the renderer
     could fix after the fact. ]]
--[[ LOAD THE MATCH'S ART UP FRONT (Main:MatchArtIds lists it). The client
     reads a texture from disk the first time it is drawn, so a card that
     arrived on the table unseen -- a Polymorph's Sheep -- showed the bare
     table where its portrait belonged until the file had loaded. Each art is
     drawn once here, 2px wide and all but transparent, and kept for the
     match so the client keeps it loaded. ]]
Board.PREFETCH_MAX = 160
Board.PREFETCH_TEXT_MAX = 200   -- baked name + rules bands (two per card)
function Board:PrefetchArt(cardIds)
  if not self.resolver then return 0 end
  if not self.prefetch then
    self.prefetch = CreateFrame("Frame", nil, self.frame)
    self.prefetch:SetSize(2, 2)
    self.prefetch:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 0, 0)
    self.prefetchTex = {}
  end
  -- one texture per distinct art, reused match to match
  local seen, n = {}, 0
  local function keep(path)
    if type(path) ~= "string" or seen[path] then return end
    seen[path] = true; n = n + 1
    local t = self.prefetchTex[n]
    if not t then
      t = self.prefetch:CreateTexture(nil, "BACKGROUND"); t:SetAllPoints(); t:SetAlpha(0.01)
      self.prefetchTex[n] = t
    end
    t:SetTexture(path); t:Show()
  end
  for _, id in ipairs(cardIds or {}) do
    if n < Board.PREFETCH_MAX then keep(self.resolver:Card(id).icon) end
  end
  local art = n
  --[[ And each card's baked name and rules text (docs/24), so a card drawn
       for the first time does not show a bare banner for a moment. ]]
  for _, id in ipairs(cardIds or {}) do
    if n >= art + Board.PREFETCH_TEXT_MAX then break end
    local namePath, textPath = W.CardTextPaths(id)
    keep(namePath); keep(textPath)
  end
  for i = n + 1, #self.prefetchTex do self.prefetchTex[i]:Hide() end
  return art
end

function Board:SetBoardArt(seed)
  local art = ns.HearthstoneArt or {}
  local boards = art.boards
  local chosen
  if type(boards) == "table" and #boards > 0 then
    --[[ Deterministic from the seed, not math.random: the engine may never see
         math.random, and a duel needs both sides to land on the same index. ]]
    local i = (math.floor(math.abs(seed or 0)) % #boards) + 1
    chosen = boards[i]
    self.boardIndex = i
  else
    chosen = art.board
    self.boardIndex = chosen and 1 or nil
  end
  if chosen then
    self.bg:SetTexture(chosen)
  else
    self.bg:SetColorTexture(0.06, 0.05, 0.04, 0.92)
  end
  for _, band in ipairs(self.bgBands or {}) do
    if chosen then band:SetTexture(chosen) else band:SetColorTexture(0.06, 0.05, 0.04, 0.92) end
  end
  self.boardArt = chosen
  if self.L then self:FitBoardArt(self.L) end
  return chosen
end

--[[ THE PICTURE AT ITS OWN SHAPE (Layout: ART_ASPECT, `L.art`). The part of
     the picture inside the window is drawn with the matching texcoords; if
     the picture is narrower or shorter than the window, each band beside or
     above and below it shows the picture's neighbouring strip MIRRORED, so
     the table and curtain carry on, and a shade darkens it toward the
     window's edge. (Stretching the outermost row instead smeared the corner
     scenery into streaks in a tall window -- reported with a screenshot.) ]]
local W_EDGE = 0.06     -- as W.EDGE_MIRROR: the mirrored strip, of the picture's width
function Board:FitBoardArt(L)
  local art = L and L.art
  if not art then return end
  local W, H = L.width, L.height
  local x0, y0 = math.max(0, art.x), math.max(0, art.y)
  local x1, y1 = math.min(W, art.x + art.w), math.min(H, art.y + art.h)
  local u0, u1 = (x0 - art.x) / art.w, (x1 - art.x) / art.w
  -- texcoords run DOWN from the top; the layout runs up from the bottom
  local v0, v1 = 1 - (y1 - art.y) / art.h, 1 - (y0 - art.y) / art.h
  local bg = self.bg
  bg:ClearAllPoints()
  bg:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", x0, y0)
  bg:SetSize(math.max(1, x1 - x0), math.max(1, y1 - y0))
  if self.boardArt then bg:SetTexCoord(u0, u1, v0, v1) end
  if not self.bgBands then
    self.bgBands, self.bgShades = {}, {}
    for i = 1, 4 do
      local t = self.frame:CreateTexture(nil, "BACKGROUND", nil, -2)
      if self.boardArt then t:SetTexture(self.boardArt) else t:SetColorTexture(0.06, 0.05, 0.04, 0.92) end
      self.bgBands[i] = t
      local s = self.frame:CreateTexture(nil, "BACKGROUND", nil, -1)
      s:SetTexture(ART .. "page-shade.tga"); s:SetVertexColor(0, 0, 0, 1)
      self.bgShades[i] = s
    end
  end
  --[[ Beside the picture: a strip of its curtain margin, MIRRORED AT ITS OWN
       SCALE so it meets the edge seamlessly, fading out, then near-black --
       the letterbox the menus use (W.EdgeBands). The strip used to be
       stretched across the whole gap: at 2000 wide, 40 texture pixels filled
       350 screen pixels under a black shade, a dark smeared block with a hard
       edge (reported with a screenshot).
       Above and below: the plain table wood from the picture's centre, the
       thin band above its top rim and below its bottom one (a mirror there
       repeated the rim and the mana pill). ]]
  local sw = math.min(x0, art.w * W_EDGE)
  local du = sw / art.w
  if not self.bgFills then
    self.bgFills = {}
    for i = 1, 2 do
      local t = self.frame:CreateTexture(nil, "BACKGROUND", nil, -2)
      t:SetColorTexture(0.025, 0.02, 0.022, 1)
      self.bgFills[i] = t
    end
  end
  for i, fill in ipairs(self.bgFills) do
    local fx, fw = (i == 1) and 0 or (x1 + sw), x0 - sw
    if i == 2 then fw = W - x1 - sw end
    if fw >= 1 and y1 - y0 >= 1 then
      fill:ClearAllPoints(); fill:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", fx, y0)
      fill:SetSize(fw, y1 - y0); fill:Show()
    else fill:Hide() end
  end
  local bands = {
    -- x, y, w, h, then texcoords, then the shade's corners (page-shade.tga is dark at u=0)
    { x0 - sw, y0, sw, y1 - y0, u0 + du, u0, v0, v1, { 0, 0, 0, 1, 1, 0, 1, 1 } },          -- left
    { x1, y0, sw, y1 - y0, u1, u1 - du, v0, v1, { 1, 0, 1, 1, 0, 0, 0, 1 } },               -- right
    { 0, y1, W, H - y1, 0.44, 0.56, 0.0, 0.012, { 0, 1, 1, 1, 0, 0, 1, 0 } },                 -- above
    { 0, 0, W, y0, 0.44, 0.56, 0.988, 1.0, { 1, 0, 0, 0, 1, 1, 0, 1 } },                      -- below
  }
  for i, b in ipairs(bands) do
    local t, s = self.bgBands[i], self.bgShades[i]
    if b[3] >= 1 and b[4] >= 1 then
      for _, r in ipairs({ t, s }) do
        r:ClearAllPoints(); r:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", b[1], b[2])
        r:SetSize(b[3], b[4]); r:Show()
      end
      if self.boardArt then t:SetTexCoord(b[5], b[6], b[7], b[8]) end
      s:SetTexCoord(unpack(b[9]))
    else
      t:Hide(); s:Hide()
    end
  end
end

--[[ THE ROPE'S FUSE: one continuous burning hiss (rope-burn.wav, as long as
     a rope), started when the rope is lit and stopped the moment it is
     cleared. It used to re-light a 4.3s fuse recording every 4.1s -- a strike,
     a sizzle and a fade, over and over -- so the rope "kept replaying" instead
     of burning. While the turn clock stands still the hiss stops, and it lights
     again when the clock moves on. ]]
function Board:StartRopeAudio()
  self:StopRopeAudio()
  --[[ Hearthstone's rope is announced by the hero whose time is running out:
       their "Out of Time" line (HeroVoice "time"), heard by both players. ]]
  local snap = self.snapshot or {}
  local hero = snap.myTurn and snap.hero or snap.foeHero
  if hero and hero.cardId and self.frame:IsShown() then ns.Sounds.PlayHero(hero.cardId, "time", true) end
  self.ropeAudioEpoch = self.ropeEpoch or 0
  -- lit while you are away from the table: quiet until you come back
  if self.frame:IsShown() then self:PlayRopeFuse() else self.ropeFusePaused = true end
end

function Board:PauseRopeFuse()
  if self.ropeAudioEpoch == nil or self.ropeFusePaused then return end
  ns.Sounds.Stop(self.ropeFuseHandle, 250)
  self.ropeFuseHandle, self.ropeFusePaused = nil, true
end

function Board:PlayRopeFuse()
  local _, handle = ns.Sounds.PlayFile(ns.Sounds.For("rope_burn"))
  self.ropeFuseHandle, self.ropeFusePaused = handle, nil
  self.ropeFuseRetry = (GetTime and GetTime() or 0) + 0.5
end

function Board:TickRopeAudio()
  if self.ropeAudioEpoch == nil then return end
  if self.ropeAudioEpoch ~= (self.ropeEpoch or 0) then return self:StopRopeAudio() end
  local quiet = self.ropeHalted or not self.frame:IsShown() or ns.Sounds.Muted()
  if quiet and not self.ropeFusePaused then
    self:PauseRopeFuse()
  elseif not quiet and self.ropeFusePaused then
    self:PlayRopeFuse()
  elseif not quiet and not ns.Sounds.IsPlaying(self.ropeFuseHandle)
         and (GetTime and GetTime() or 0) >= (self.ropeFuseRetry or 0) then
    --[[ THE FUSE WENT OUT UNDER US. With "Sound in Background" off, WoW drops
         a sound started while alt-tabbed (and stops one playing), and gives an
         addon no focus event to say so -- so a rope lit while you were away
         was silent when you came back. Asking whether it still plays, twice a
         second, relights it within half a second of your return. ]]
    self:PlayRopeFuse()
  end
end

function Board:StopRopeAudio()
  ns.Sounds.Stop(self.ropeFuseHandle, 250)
  self.ropeFuseHandle, self.ropeAudioEpoch, self.ropeFusePaused = nil, nil, nil
end

--[[ Take the rope down and forget the burn.

     THE BUG THIS EXISTS FOR, TWICE OVER. Hiding the rope was not enough: the
     rope is driven by a TIMELINE that runs for the length of the turn, and that
     timeline does not stop when the turn does. It kept calling Burn on the next
     frame, which set the value again and called Show again -- so the rope came
     straight back, stayed fully burnt, and sat there through the opponent's
     turn and into the next one.

     So the rope belongs to an EPOCH. Clearing it bumps the number; the handle
     the timeline is holding captured the old one and becomes a no-op. Same
     shape as the pooled-widget generation counter, and for the same reason: an
     animation outliving the thing it animates. ]]
function Board:ClearRope()
  self:StopRopeAudio()
  self.ropeBurn = nil
  self.ropeUrgency = nil
  self.ropeEpoch = (self.ropeEpoch or 0) + 1
  if self.rope then self.rope.frame:Hide() end
end

--[[ Lift a card out of the hand so it can be animated after it has gone.

     Called BEFORE the action is applied, because that is the last moment the
     card is still in the hand to be copied. Everything about the copy -- its
     art, its size, where it is on screen -- is taken from the hand widget it
     replaces, so the animation starts exactly where the card was. ]]
function Board:BeginPresentation()
  self:ClearPlacementPreview()
  self.dragging,self.dragAiming,self.hoverIndex=nil,nil,nil
  W.HideArrow(self.arrow)
  self.presentationLocked = true
  --[[ Anything still sliding lands where it was going. Dropping the tweens
       froze it part-way -- a spell cast just after a death left the survivors
       half across the gap, and aimed the spell at where they had stopped. ]]
  for _, t in ipairs(self.tweens) do
    if t.w and t.to then cardApplyRect(t.w, t.to) end
  end
  self.tweens = {}
end

function Board:EndPresentation()
  self:EndPlayAnimation()
  self.presentationLocked = false
  local snap = self.pendingSnapshot or self.snapshot
  self.pendingSnapshot = nil
  if snap then self:SetSnapshot(snap) end
end

function Board:BeginPlayAnimation(handIndex, opponentCardId)
  local snap = self.snapshot or {}
  if snap.over then return false end
  local cardId = opponentCardId or (snap.hand and snap.hand[handIndex])
  local from = opponentCardId and self.L and self.L.foeHandSlots[1]
    or (self.handWidgets and self.handWidgets[handIndex] and self.handWidgets[handIndex].rect)
    or (self.handRects and self.handRects[handIndex])
  if not (cardId and from and self.resolver) then return false end
  --[[ A MINION ALREADY STANDING ON THE BOARD AS A GHOST -- one whose
       battlecry you have just aimed -- is played from where it stands. It
       used to fly out of the hand all over again, so the card you had
       already put down seemed to be played twice. ]]
  local ghost = not opponentCardId and self.placementGhost
  local fromGhost = ghost and ghost.frame:IsShown() and ghost.cardId == cardId and ghost.rect
  if fromGhost then from = fromGhost end
  self.flyingCard.gen = (self.flyingCard.gen or 0) + 1
  self.flyingCard.inPlay = fromGhost and true or false

  cardApplyRect(self.flyingCard, { x = from.x, y = from.y,
                                   w = from.w, h = from.h, lean = from.lean })
  cardSetDescriptor(self.flyingCard, self.resolver:Card(cardId))
  W.SetFaceDown(self.flyingCard, opponentCardId and isSecretCard(cardId) or false)
  self.flyingCard.frame:SetAlpha(1)
  self.flyingCard.frame:SetScale(1)
  self.flyingCard.frame:Show()
  self.flyingCardId = cardId
  self.flying = true
  self.flyingSource = opponentCardId and self.foeHandPool.used[1] or self.handWidgets[handIndex]
  if self.flyingSource then self.flyingSource.frame:Hide() end
  return true
end

--[[ Put it away once the animation is done with it. A copy left on screen is
     a card nobody can click sitting on top of the board. ]]
function Board:EndPlayAnimation()
  self.flyingCardId=nil
  self.playLanding=nil
  if self.summonPortrait then self.summonPortrait.frame:Hide() end
  if self.flyingSource then self.flyingSource.frame:Show(); self.flyingSource = nil end
  self.flying = false
  if self.flyingCard then
    self.flyingCard.gen = (self.flyingCard.gen or 0) + 1
    self.flyingCard.anim:Stop()
    self.flyingCard.frame:Hide()
  end
end

--[[ ------------------------------------------------------- READING A CARD

     Right-click enlarges whatever is under the pointer. A board minion is too
     small to read its own rules text at any reasonable window size, so without
     this "what does that do" could only be answered from memory.

     It takes a card id and the live stats, so an inspected minion shows what it
     IS -- a damaged, buffed 6/2 -- rather than what it was printed as. ]]
--[[ A deck's count, on hover -- the stack itself carries no number, as in
     Hearthstone. To the LEFT, because the decks sit on the board's right edge. ]]
function Board:ShowDeckCount(deck, where)
  local n = deck.count or 0
  self:HideTooltip()
  self.tooltip.text:SetJustifyH("CENTER")
  -- an empty deck says what the next draw costs (fatigue: 1, then 2, ...)
  local snap = self.snapshot or {}
  local hit = deck == self.foeDeckPip and snap.foeNextFatigue or snap.nextFatigue
  self.tooltip:SetContent(nil, n == 0 and ("No cards " .. where .. (hit and ("\nNext draw: %d fatigue damage"):format(hit) or ""))
    or (("%d card%s %s"):format(n, n == 1 and "" or "s", where)), 200)
  self.tooltip:ClearAllPoints()
  self.tooltip:SetPoint("RIGHT", deck.frame, "LEFT", -8, 0)
  self.tooltip:Show()
end

--[[ Hearthstone's keyword reminders, shown in a box beside a hovered card and
     beside a right-clicked one (W.KEYWORDS, shared with the collection). ]]
Board.KEYWORDS = W.KEYWORDS
Board.KeywordsOf = W.KeywordsOf

--[[ THE TABLE STATUS: a parchment notice across the top of the board while the
     duel is paused, the connection is in trouble, or the opponent is stalling.
     nil clears it. ]]
function Board:ShowStatus(text, action)
  --[[ `action` = { label, onClick }: the notice's one thing to do (Claim
       Victory over a staller), a button under it -- "/fh claim" in a line of
       text was a dead end for anyone who does not type commands. ]]
  if self.statusAction then self.statusAction:Hide() end
  if not text or text == "" then
    if self.statusPanel then self.statusPanel:Hide() end
    return
  end
  if not self.statusPanel then
    self.statusPanel = W.HSPanel(self.frame)
    self.statusPanel:SetFrameLevel(480)
    self.statusPanel:EnableMouse(false)
  end
  local p = self.statusPanel
  p:SetContent(nil, text, math.floor(math.min(460, self.frame:GetWidth() * 0.42)))
  p:ClearAllPoints()
  p:SetPoint("TOP", self.frame, "TOP", 0, -self.frame:GetHeight() * 0.28)
  p:Show()
  if action then
    local b = self.statusAction
    if not b then
      b = W.MenuButton(self.frame, action.label, function() if b.onAction then b.onAction() end end)
      b:SetFrameLevel(490); b:SetSize(190, 38)
      self.statusAction = b
    end
    b.text:SetText(action.label); b.onAction = action.onClick
    b:ClearAllPoints(); b:SetPoint("TOP", p, "BOTTOM", 0, -6)
    b:Show()
  end
end

function Board:HideTooltip()
  self.hoverBoardEntity, self.hoverHasLiveStats = nil, nil
  self.tooltip:Hide()
  if self.hoverCard then self.hoverCard.frame:Hide() end
  for _, p in ipairs(self.keywordPanels or {}) do p:Hide() end
end

function Board:ShowDescription(anchor, cardId, stats)
  local card = cardId and ns.PrintedCards[cardId]
  self:HideTooltip()
  if not card then return end
  self.hoverBoardEntity = stats and stats.instanceId
  self.hoverHasLiveStats = stats ~= nil
  --[[ The card itself, big enough to read, beside what was hovered: on the
       right unless that would leave the window, then on the left. ]]
  local W0, H0 = self.frame:GetWidth(), self.frame:GetHeight()
  local ch = math.floor(math.min(H0 * 0.42, 320))
  local cw = math.floor(ch * Layout.design.CARD_W_OVER_H)
  local left, bottom = 0, 0
  if anchor.GetLeft and anchor:GetLeft() and self.frame:GetLeft() then
    left = anchor:GetLeft() - self.frame:GetLeft()
    bottom = anchor:GetBottom() - self.frame:GetBottom()
  end
  local aw, ah = anchor:GetWidth() or 0, anchor:GetHeight() or 0
  local x = left + aw + 10
  if x + cw + 230 > W0 then x = left - cw - 10 end
  local y = math.max(8, math.min(H0 - ch - 8, bottom + ah / 2 - ch / 2))
  local shown = false
  if self.resolver then
    local hc = self.hoverCard
    cardSetDescriptor(hc, self.resolver:Card(cardId))
    W.SetLiveStats(hc, stats)
    cardApplyRect(hc, { x = x, y = y, w = cw, h = ch })
    hc.frame:SetFrameLevel(455)
    hc.frame:Show()
    shown = true
  end
  -- keyword boxes stacked beside the card, or the name and text if no card art
  local kws = Board.KeywordsOf(card)
  local kx = (x > left) and (x + cw + 6) or (x - 206)
  local ky = y + ch
  if not shown then
    kws = { { card.name, (card.text or ""):gsub("<[^>]+>", "") } }
  end
  for i, kw in ipairs(kws) do
    local p = self.keywordPanels[i]
    if not p then
      p = W.HSPanel(self.frame); p:SetFrameLevel(452); p:EnableMouse(false)
      self.keywordPanels[i] = p
    end
    p:SetContent(kw[1], kw[2], 200)
    ky = ky - p:GetHeight()
    p:ClearAllPoints(); p:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", kx, ky)
    ky = ky - 4
    p:Show()
  end
  -- the tooltip carries the card's name and rules text for anything reading
  -- it (and for screen readers of the frame tree); it is the first keyword
  -- box's slot when a card has none
  self.tooltip.text:SetJustifyH("CENTER")
  local text = (card.text or ""):gsub("<[^>]+>", "")
  if stats then text = text .. ("\nAttack: %s   Health: %s"):format(tostring(stats.atk or 0), tostring(stats.health or 0)) end
  self.tooltip:SetContent(card.name, text, 200)
  if #kws == 0 and not shown then self.tooltip:Show() end
  self.tooltipCardId = cardId
end

-- A resolved action may damage, buff, transform, move or remove the minion
-- under an open preview. Follow its entity ID, never a reused board slot.
function Board:RefreshDescription()
  if not self.hoverHasLiveStats then return end
  local id, snap = self.hoverBoardEntity, self.snapshot or {}
  if id then
    for _, side in ipairs({{snap.board,snap.boardStats,self.myMinions},
                            {snap.foeBoard,snap.foeBoardStats,self.foeMinions}}) do
      for i, stats in ipairs(side[2] or {}) do
        if stats.instanceId == id and side[1] and side[3] and side[3][i] then
          self:ShowDescription(side[3][i].frame, side[1][i], stats)
          return
        end
      end
    end
  end
  self:HideTooltip()
end

function Board:ShowInspect(cardId, stats, cost)
  if not (cardId and self.resolver and self.L) then return end
  local identity = stats and stats.instanceId or cardId
  if self.inspectIdentity == identity then return self:HideInspect() end
  local L = self.L
  local h = math.min(self.frame:GetHeight() * 0.62, self.frame:GetWidth() * 0.34)
  local w = h * Layout.design.CARD_W_OVER_H
  cardApplyRect(self.inspect.card, {
    x = (self.frame:GetWidth() - w) / 2,
    y = (self.frame:GetHeight() - h) / 2,
    w = w, h = h,
  })
  cardSetDescriptor(self.inspect.card, self.resolver:Card(cardId))
  W.SetLiveStats(self.inspect.card, stats)
  -- a card from hand keeps the cost it has now (Sorcerer's Apprentice, Loatheb, ...)
  if cost then self.inspect.card.cost:SetText(tostring(cost)) end
  self.inspect.effects:ClearAllPoints()
  self.inspect.effects:SetPoint("TOPLEFT", self.inspect.card.frame, "TOPRIGHT", 16, -20)
  self.inspect.effects:SetSize(math.max(100, (self.frame:GetWidth()-w)/2-30), h-40)
  self.inspectEffects = stats and stats.effects or {}
  self.inspectOffset = 0
  self:RefreshInspectEffects()
  W.InspectKeywords(self.inspect, cardId)
  self.inspectCard = cardId
  self.inspectIdentity = identity
  self.inspect.frame:Show()
end

function Board:RefreshInspectEffects()
  local effects=self.inspectEffects or {}
  local first=(self.inspectOffset or 0)+1
  local shown={}
  for i=first,math.min(#effects,first+2) do shown[#shown+1]=effects[i] end
  local heading=#effects>3 and ("Active effects " .. first .. "–" .. math.min(#effects,first+2) .. "/" .. #effects .. "\nMouse wheel to scroll") or "Active effects"
  self.inspect.effects:SetText(heading .. "\n\n" .. (#shown>0 and table.concat(shown,"\n\n") or "No added effects"))
end

--[[ What each emote SAYS, in the bubble and on its plaque. Your WoW character
     performs the matching emote in the world, in their own voice, so the words
     are what that emote actually is -- the old Hearthstone names ("Sorry",
     "Oops", "Threaten") promised an apology and got a train whistle, a spit and
     a roar. Short, and in the tavern's voice. ]]
Board.EMOTES = {"Thank you!", "Well played!", "Well met!", "Choo choo!", "Ptooey!", "RAWR!"}
-- ...and the WoW emote each one is (voiced where WoW voices it).
Board.WOW_EMOTES = {"THANK", "CONGRATULATE", "HELLO", "TRAIN", "SPIT", "ROAR"}

--[[ THE PLAYERS' NAME TAGS. Hearthstone keeps who you are playing small and
     out of the way in the left margin: a round portrait medallion and a dark
     name tag with a gold hairline. (These were 240x74 red leather panels --
     more board furniture than the heroes had.) The WoW level and duel record
     sit under the name in small type. ]]
function Board:SetProfiles(mine, peer)
  self.profileData={self=mine,foe=peer}
  self.profiles=self.profiles or {}
  for _,side in ipairs({"self","foe"}) do
    local data=self.profileData[side]
    local panel=self.profiles[side]
    if not panel then
      panel=CreateFrame("Frame",nil,self.frame)
      panel:SetFrameLevel(150); panel:EnableMouse(false)
      panel.plate=panel:CreateTexture(nil,"BACKGROUND")
      panel.plate:SetTexture(ART.."hs-nameplate.tga")
      --[[ The medallion is BEHIND the face. hs-round.tga is a solid gilded
           disc, not a hollow ring: drawn on top (sublevel 2, as it was) it
           covered the character's portrait completely, leaving an empty
           brown circle where your character should be. ]]
      panel.ring=panel:CreateTexture(nil,"ARTWORK",nil,-1)
      panel.ring:SetTexture(ART.."hs-round.tga")
      panel.portrait=panel:CreateTexture(nil,"ARTWORK",nil,1)
      panel.portraitMask=W.Mask(panel,panel.portrait,"mask-oval")
      panel.name=panel:CreateFontString(nil,"OVERLAY")
      W.ApplyStyle(panel.name,"nameplate",nil,13); panel.name:SetJustifyH("LEFT"); panel.name:SetWordWrap(false)
      panel.name:SetShadowOffset(1,-1); panel.name:SetShadowColor(0,0,0,.9)
      panel.level=panel:CreateFontString(nil,"OVERLAY")
      W.ApplyStyle(panel.level,"nameplateSub",nil,10); panel.level:SetJustifyH("LEFT")
      -- Duel record: wins and losses against real players.
      panel.record=panel:CreateFontString(nil,"OVERLAY")
      W.ApplyStyle(panel.record,"nameplateSub",nil,10,W.Colors.count); panel.record:SetJustifyH("LEFT")
      W.AutoFit(panel.name,{w=100,h=16,font=ns.Fonts.TITLE,size=13,min=5})
      W.AutoFit(panel.level,{w=100,h=12,font=ns.Fonts.BODY,size=10,min=6})
      W.AutoFit(panel.record,{w=100,h=12,font=ns.Fonts.BODY,size=10,min=6})
      self.profiles[side]=panel
    end
    if data then
      panel.name:SetText(data.name or "Opponent")
      local level = data.bot and (data.botLabel or "Practice bot")
        or (data.level and data.level>0 and ("Level "..data.level) or "")
      if data.bot then panel.record:SetText("")
      elseif data.wins then panel.record:SetText(W.RecordText(data.wins, data.losses))
      else panel.record:SetText("") end
      panel.level:SetText(level)
      --[[ THE CHARACTER'S OWN FACE, ONCE SEEN, STAYS. It can only be drawn
           from a unit token (target, party1...), and the opponent stops being
           one the moment you target something else -- so it used to flip back
           to their class's hero every time your target changed. The class
           hero is only for an opponent never seen as a unit. ]]
      local who = data.guid or data.name
      if data.unit and SetPortraitTexture then
        SetPortraitTexture(panel.portrait,data.unit)
        panel.portraitOf = who
      elseif not (who and rawget(panel, "portraitOf") == who) then
        panel.portrait:SetTexture(data.icon)
        panel.portraitOf = nil
      end
      panel:Show()
    else panel:Hide() end
  end
  self:LayoutProfiles()
end

function Board:LayoutProfiles()
  if not self.profiles then return end
  local w,h=self.frame:GetWidth(),self.frame:GetHeight()
  local ph=math.floor(math.max(34,math.min(46,h*.056)))
  local width=math.floor(math.max(120,math.min(170,w*.13)))
  for side,panel in pairs(self.profiles) do
    panel:ClearAllPoints(); panel:SetSize(width,ph)
    panel:SetPoint(side=="self" and "BOTTOMLEFT" or "TOPLEFT",self.frame,side=="self" and "BOTTOMLEFT" or "TOPLEFT",10,side=="self" and 10 or -10)
    panel.ring:ClearAllPoints(); panel.ring:SetPoint("LEFT",panel,"LEFT",0,0); panel.ring:SetSize(ph,ph)
    panel.portrait:ClearAllPoints(); panel.portrait:SetPoint("CENTER",panel.ring,"CENTER",0,0)
    panel.portrait:SetSize(ph*.74,ph*.74)
    panel.plate:ClearAllPoints(); panel.plate:SetPoint("LEFT",panel,"LEFT",ph*.55,0)
    panel.plate:SetSize(width-ph*.55,ph*.78)
    local tx, tw = ph*1.05, width-ph*1.05-8
    local hasSub = (panel.level:GetText() or "")~="" or (panel.record:GetText() or "")~=""
    panel.name:ClearAllPoints()
    panel.name:SetPoint("LEFT",panel,"LEFT",tx,hasSub and ph*.13 or 0)
    panel.name:SetSize(tw,ph*.34)
    panel.level:ClearAllPoints(); panel.level:SetPoint("LEFT",panel,"LEFT",tx,-ph*.18)
    panel.level:SetSize(tw*.55,ph*.26)
    panel.record:ClearAllPoints(); panel.record:SetPoint("RIGHT",panel,"RIGHT",-8,-ph*.18)
    panel.record:SetSize(tw*.45,ph*.26); panel.record:SetJustifyH("RIGHT")
  end
end

--[[ WHAT A HERO SAYS: Hearthstone's white speech balloon, its tail pointing
     back at the hero who spoke, black words centred in the round of it. Yours
     rises up and to the right of your portrait; the opponent's hangs down and
     to the right of theirs (the same art flipped). It pops in, holds, and
     fades, as the game's does. Sized from the portrait, so it scales with
     the table. speech-bubble.tga: tools/build_speech_bubble.py. ]]
-- The balloon's round body in its 512x256 canvas (tools/build_speech_bubble.py).
Board.SPEECH_BODY = { x0 = 34/512, y0 = 10/256, x1 = 502/512, y1 = 190/256 }
local SPEECH_HOLD, SPEECH_POP, SPEECH_FADE = 3, 0.12, 0.25
function Board:ToggleSquelch()
  self.squelched = not self.squelched
  self:ShowSpeech("self", self.squelched and "Opponent's emotes squelched." or "Opponent's emotes on.")
end

function Board:ShowSpeech(side, text)
  self.speech = self.speech or {}
  local bubble = self.speech[side]
  local foe = side == "foe"
  if not bubble then
    bubble = CreateFrame("Frame", nil, self.frame)
    bubble:EnableMouse(false); bubble:SetFrameLevel(410)
    bubble.bg = bubble:CreateTexture(nil, "BACKGROUND")
    bubble.bg:SetAllPoints()
    bubble.bg:SetTexture(ART .. "speech-bubble.tga")
    -- the opponent's tail points up at their portrait: flipped top to bottom
    if foe then bubble.bg:SetTexCoord(0, 1, 1, 0) else bubble.bg:SetTexCoord(0, 1, 0, 1) end
    bubble.text = bubble:CreateFontString(nil, "OVERLAY")
    W.ApplyStyle(bubble.text, "speech", nil, 16)
    bubble.text:SetJustifyH("CENTER"); bubble.text:SetJustifyV("MIDDLE")
    bubble.text:SetWordWrap(true)
    self.speech[side] = bubble
  end
  local hero = (foe and self.foeHero or self.hero).frame
  local hh = math.max(60, hero:GetHeight() or 100)
  local bh = hh * 0.95
  local bw = bh * 2
  bubble:ClearAllPoints(); bubble:SetSize(bw, bh)
  -- the tail's tip (bottom-left corner, or top-left when flipped) sits on the
  -- portrait's upper (lower) right shoulder
  if foe then
    bubble:SetPoint("TOPLEFT", hero, "BOTTOMRIGHT", -hh * 0.18, hh * 0.40)
  else
    bubble:SetPoint("BOTTOMLEFT", hero, "TOPRIGHT", -hh * 0.18, -hh * 0.40)
  end
  -- words in the round of the balloon, clear of its rim
  local B = Board.SPEECH_BODY
  local tw, th = bw * (B.x1 - B.x0) * 0.74, bh * (B.y1 - B.y0) * 0.62
  local cx = bw * (B.x0 + B.x1) / 2
  local cy = foe and bh * (1 - (B.y0 + B.y1) / 2) or bh * (B.y0 + B.y1) / 2
  bubble.text:ClearAllPoints()
  bubble.text:SetPoint("CENTER", bubble, "TOPLEFT", cx, -cy)
  W.FitText(bubble.text, { text = text, w = tw, h = th, font = ns.Fonts.BODY,
                           size = math.max(10, math.floor(bh * 0.19)), min = 8, lines = 3 })
  bubble.text:SetTextColor(0.06, 0.05, 0.04, 1)
  bubble:SetScale(0.6); bubble:SetAlpha(1); bubble:Show()
  local age = 0
  bubble:SetScript("OnUpdate", function(_, dt)
    age = age + dt
    if age >= SPEECH_HOLD then bubble:Hide(); bubble:SetScript("OnUpdate", nil); return end
    local pop = math.min(1, age / SPEECH_POP)
    bubble:SetScale(math.max(0.01, 0.6 + 0.4 * (1 - (1 - pop) ^ 3)))
    bubble:SetAlpha(math.min(1, (SPEECH_HOLD - age) / SPEECH_FADE))
  end)
end

--[[ THE EMOTE WHEEL. Hearthstone opens its emotes AROUND your portrait --
     three plaques down each side -- not as a menu floating above it. Clicking
     anywhere else closes it (the catcher behind the plaques). ]]
Board.EMOTE_SLOTS = {                -- in units of the hero's width/height
  { -0.98, 0.42 }, { -1.10, 0.04 }, { -0.98, -0.34 },   -- thank, congratulate, hello
  {  0.98, 0.42 }, {  1.10, 0.04 }, {  0.98, -0.34 },   -- train, spit, roar
}
function Board:ToggleEmotes()
  if (self.snapshot or {}).over then return end
  if self.emoteMenu and self.emoteMenu:IsShown() then self.emoteMenu:Hide(); return end
  if not self.emoteMenu then
    local menu = CreateFrame("Button", nil, self.frame)
    self.emoteMenu = menu; menu:SetAllPoints(self.frame); menu:SetFrameLevel(420)
    menu:EnableMouse(true); menu:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    menu:SetScript("OnClick", function() menu:Hide() end)
    self.emoteButtons = {}
    for i, label in ipairs(Board.EMOTES) do
      local index = i
      local button = W.MenuButton(menu, label, function()
        menu:Hide(); self.onIntent({kind="EMOTE", index=index})
      end)
      button.bg:SetTexture(ART .. "emote-plaque.tga"); button.bg:SetTexCoord(0, 1, 0, 1)
      button:SetFrameLevel(430)
      self.emoteButtons[i] = button
    end
  end
  -- Sized and placed from the portrait every time: the board may have resized.
  local hr = self.L and self.L.hero
  local hw, hh = hr and hr.w or 120, hr and hr.h or 120
  local cx, cy = hr and hr.x + hr.w / 2 or self.frame:GetWidth() / 2, hr and hr.y + hr.h / 2 or 120
  local s = math.min(hw, hh)   -- the portrait is no longer square once the board keeps its shape
  local bw, bh = math.max(96, s * 0.95), math.max(30, s * 0.30)
  for i, button in ipairs(self.emoteButtons) do
    local slot = Board.EMOTE_SLOTS[i]
    button:ClearAllPoints(); button:SetSize(bw, bh)
    button:SetPoint("CENTER", self.frame, "BOTTOMLEFT", cx + slot[1] * hw, cy + slot[2] * hh)
    W.ApplyStyle(button.text, "button", nil, math.max(11, math.min(15, bh * 0.42)))
  end
  self.emoteMenu:Show()
end

function Board:HideInspect()
  self.inspectCard = nil
  self.inspectIdentity = nil
  if self.inspect then self.inspect.frame:Hide() end
end

--[[ --------------------------------------------------------- THE ARROW

     Where the aim starts. Targeting a spell starts at the card in your hand;
     a hero power at the hero power; an attack at the attacker. Returns nil when
     nothing is being aimed, which is what takes the arrow down. ]]
-- Where a targeted spell is held while it is aimed: beside your hero.
function Board:SpellHoldRect()
  local L = self.L
  local cw, ch = L.cardW * 1.15, L.cardH * 1.15
  local x = math.max(8, L.hero.x - cw - L.hero.w * 0.25)
  return { x = x, y = L.hero.y + L.hero.h / 2 - ch / 2 + L.hero.h * 0.35, w = cw, h = ch, rot = 0 }
end

function Board:ArrowOrigin()
  local snap, L = self.snapshot or {}, self.L
  if not L then return nil end
  local t = snap.targeting
  if t then
    if t.heroPower then return L.heroPower end
    -- A battlecry is aimed from the minion, standing where it will land.
    local slot = self:PendingMinionSlot()
    if slot then
      local layout = Layout.Compute({ width = self.frame:GetWidth(), height = self.frame:GetHeight(),
        boardCount = #self.myMinions + 1, foeBoardCount = self.state.foeBoardCount })
      return layout.boardSlots[slot]
    end
    -- A spell is cast by your hero: Hearthstone's arrow comes out of it.
    return L.hero
  end
  --[[ An attack is aimed too, and it is the aim people miss most: you click a
       minion and then have to remember that it is waiting for a target. ]]
  if snap.heroSelected then return L.hero end
  if snap.selectedIndex and L.boardSlots[snap.selectedIndex] then
    return L.boardSlots[snap.selectedIndex]
  end
  --[[ And a card being dragged out of the hand, which is an aim in progress
       even before the engine has been asked anything. ]]
  if self.dragging and self.dragAiming then return L.hero end
  return nil
end

function Board:UpdateArrow()
  self:ReportHover()
  if self.presentationLocked or (self.snapshot or {}).over then W.HideArrow(self.arrow); return false end
  local from = self:ArrowOrigin()
  if not from then
    W.HideArrow(self.arrow)
    return false
  end
  local x, y = self:CursorInBoard()
  if not x then
    W.HideArrow(self.arrow)
    return false
  end
  W.ApplyArrow(self.arrow, from.x + from.w / 2, from.y + from.h / 2, x, y,
               self.frame, (self.L and self.L.scale or 1), self:ArrowTarget(x, y))
  return true
end

--[[ WHAT THE OPPONENT SEES OF YOU: the card you hold up and your aim, as
     seat-relative codes rather than entity ids -- "H" your hero, "P" your hero
     power, "b3" your third minion, "s3" a battlecry minion being placed into
     slot 3, "E"/"e2" theirs, "" nothing -- so the other
     client just mirrors them onto its own layout. Main sends it (throttled). ]]
function Board:HoverState()
  local snap = self.snapshot or {}
  if self.presentationLocked or snap.over then return 0,"","" end
  local hand = self.hoverIndex or (self.dragging and self.dragging.handIndex) or 0
  local src, dst = "", ""
  local t = snap.targeting
  if t then
    local slot = self:PendingMinionSlot()
    src = t.heroPower and "P" or (slot and "s" .. slot) or "H"
  elseif snap.heroSelected then src = "H"
  elseif snap.selectedIndex then src = "b" .. snap.selectedIndex
  elseif self.dragging and self.dragAiming then src = "H" end
  if src ~= "" then
    local x, y = self:CursorInBoard()
    local target = x and self:TargetAt(x, y)
    if target and self:ArrowTarget(x,y) then
      if target.kind == "CLICK_BOARD" then dst = "b" .. target.boardIndex
      elseif target.kind == "CLICK_FOE_BOARD" then dst = "e" .. target.boardIndex
      elseif target.kind == "CLICK_HERO" then dst = "H"
      elseif target.kind == "CLICK_FOE_HERO" then dst = "E" end
    end
  end
  return hand, src, dst
end

function Board:ReportHover()
  local cb = self.opts and self.opts.onHover
  if not cb or not (self.snapshot or {}).myTurn then return end
  cb(self:HoverState())
end

--[[ The OPPONENT's hover, mirrored: their "b2" is our foe slot 2, their "E"
     is our hero. The lifted card drops from their hand; the arrow is red over
     our side, green over theirs, as their own arrow would be. Cleared on any
     game snapshot that changes the turn, and after three silent seconds. ]]
function Board:SetOpponentHover(handIndex, src, dst)
  local L = self.L
  if not L then return end
  handIndex = tonumber(handIndex) or 0
  local prevHand = self.foeHover and self.foeHover.handIndex or 0
  self.foeHover = { handIndex = handIndex, src = src or "", dst = dst or "",
                    at = GetTime and GetTime() or 0 }
  if prevHand ~= handIndex then self:Relayout() end
  self:DrawOpponentArrow()
end

function Board:OpponentRect(code, targetSide)
  local L = self.L
  if not code or code == "" then return nil end
  local kind, n = code:sub(1, 1), tonumber(code:sub(2))
  if kind == "H" then return L.foeHero, false
  elseif kind == "P" then return L.foeHeroPower, false
  elseif kind == "b" then return n and L.foeBoardSlots[n], false
  --[[ A minion they are placing into slot n while they aim its battlecry.
       It is not on their board yet, so the slot is found in the layout their
       board WILL have: one more minion, with theirs stepped aside. ]]
  elseif kind == "s" then
    if not n then return nil end
    local layout = Layout.Compute({ width = self.frame:GetWidth(), height = self.frame:GetHeight(),
      boardCount = self.state.boardCount, foeBoardCount = (self.state.foeBoardCount or 0) + 1 })
    return layout.foeBoardSlots[n], false
  elseif kind == "E" then return L.hero, true
  elseif kind == "e" then return n and L.boardSlots[n], true end
end

function Board:DrawOpponentArrow()
  local fh = self.foeHover
  local from = fh and self:OpponentRect(fh.src)
  if not from or (self.snapshot or {}).myTurn then W.HideArrow(self.foeArrow); return end
  local to, onUs = self:OpponentRect(fh.dst)
  -- No target means no remote aim; a made-up endpoint at the seam looked
  -- like a lingering attack even after the opponent stopped hovering.
  if not to then W.HideArrow(self.foeArrow); return end
  local x, y
  if to then x, y = to.x + to.w / 2, to.y + to.h / 2
  else x, y = from.x + from.w / 2, (self.L.seam or (self.frame:GetHeight() / 2)) end
  W.ApplyArrow(self.foeArrow, from.x + from.w / 2, from.y + from.h / 2, x, y, self.frame,
               self.L.scale or 1, to and { x = to.x, y = to.y, w = to.w, h = to.h, friendly = not onUs } or nil)
end

function Board:ClearOpponentHover()
  local had = self.foeHover and self.foeHover.handIndex or 0
  self.foeHover = nil
  W.HideArrow(self.foeArrow)
  if had ~= 0 then self:Relayout() end
end

--[[ The LEGAL target under the pointer, if there is one, for the arrow's
     crosshair and colour: { x, y, w, h, friendly }. Legality comes from the
     snapshot in whichever form the aim takes -- a spell or hero power's
     `targeting.legal`, a dragged card's `handLegalTargets`, or an attack's
     `combatPreview` (one entry per legal defender). ]]
function Board:ArrowTarget(x, y)
  local snap, L = self.snapshot or {}, self.L
  local target = L and self:TargetAt(x, y)
  if not target then return nil end
  local kind, id, rect = target.kind, nil, nil
  if kind == "CLICK_BOARD" then
    local st = (snap.boardStats or {})[target.boardIndex]
    id, rect = st and st.instanceId, L.boardSlots[target.boardIndex]
  elseif kind == "CLICK_FOE_BOARD" then
    local st = (snap.foeBoardStats or {})[target.boardIndex]
    id, rect = st and st.instanceId, L.foeBoardSlots[target.boardIndex]
  elseif kind == "CLICK_HERO" then id, rect = snap.heroId, L.hero
  elseif kind == "CLICK_FOE_HERO" then id, rect = snap.foeHeroId, L.foeHero end
  if not (id and rect) then return nil end
  local legal = false
  if snap.targeting then
    for _, l in ipairs(snap.targeting.legal or {}) do if l == id then legal = true end end
  elseif self.dragging and self.dragAiming then
    local set = snap.handLegalTargets and snap.handLegalTargets[self.dragging.handIndex]
    legal = set and set[id] and true or false
  elseif snap.selectedIndex or snap.heroSelected then
    legal = snap.combatPreview ~= nil and snap.combatPreview[id] ~= nil
  end
  if not legal then return nil end
  return { x = rect.x, y = rect.y, w = rect.w, h = rect.h,
           friendly = kind == "CLICK_BOARD" or kind == "CLICK_HERO" }
end

function Board:Show() self.frame:Show() end
function Board:Hide() self.frame:Hide() end
function Board:IsShown() return self.frame:IsShown() end

--- Frames created so far. Tests assert this stops growing, proving the pools work.
function Board:FrameCount()
  return self.handPool.created + self.boardPool.created
end

return Board
