--[[ tests/test_table.lua -- the board as a PLAYING SURFACE, driven by a mouse.

  WHAT THIS EXISTS FOR. `GetCursorPosition` was never stubbed, so
  `Board:CursorInBoard` took its `if not GetCursorPosition then return nil end`
  early exit in every test that had ever run. Every drop therefore resolved as
  "dropped on nothing" and snapped back -- which means the entire
  drag-and-drop half of the interface, the half a player actually uses, had no
  coverage at all. Playing a card, choosing where a minion lands, aiming a
  spell and declaring an attack were all untested gestures.

  The stub has a pointer now (`Stub.CursorOver`), and this file drives the game
  the way a person does: pick a card up, move the mouse, let go.

  THE INVARIANT AT THE HEART OF IT. After the dust settles, everything the
  snapshot says exists must be ON SCREEN. Not merely laid out -- shown, opaque,
  and the right size. "My cards disappeared until I resized the window" is
  exactly this invariant failing, and a resize repairing it is the tell: the
  relayout is correct and something stopped it running.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

--============================================================ the whole app

--[[ Boot the addon as PLAYER_LOGIN does, start a practice match, and settle
     the mulligan. `secondPlayer` puts us on the draw, which is the only way to
     be dealt the Coin. ]]
local function app(ns, opts)
  opts = opts or {}
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = { player = { name = "Tester", class = opts.class or "MAGE",
                            isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua",
                          "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua",
                          "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")

  --[[ The flip is real randomness, and other suites draw from the same stream,
       so who goes first would otherwise be an accident of test ORDER. ]]
  local realRandom = math.random
  math.random = function(a, b)
    if a == 1 and b == 2 then return opts.secondPlayer and 2 or 1 end
    return realRandom(a, b)
  end
  ns.Main:StartPractice()
  math.random = realRandom

  local m = ns.Main
  if opts.beforeConfirm then opts.beforeConfirm(m) end
  m:OnIntent({ kind = "CONFIRM_MULLIGAN" })
  return m, m.board
end

--- Let every timer, animation and opponent step finish. Returns false if the
--- board is still busy after a generous wait, which is itself a failure.
local function settle(m, seconds)
  for _ = 1, math.floor((seconds or 12) / 0.05) do
    if not (m.aiRunning or (m.board and m.board.presentationLocked)) then
      Stub.Advance(0.2)              -- and a beat past the last animation
      if not (m.aiRunning or m.board.presentationLocked) then return true end
    end
    Stub.Advance(0.05)
  end
  return not (m.aiRunning or m.board.presentationLocked)
end

--- Hand the turn back to us, however many opponent turns that takes.
local function ourTurn(m)
  for _ = 1, 400 do
    if m.game.activePlayer == 1 and not m.aiRunning
       and not m.board.presentationLocked then return true end
    Stub.Advance(0.05)
  end
  return false
end

--[[ THE INVARIANT. Everything the snapshot says is on the table must be drawn:
     shown, opaque, and with a real size. A widget left at alpha 0 by an
     animation that outlived its card is a card that has silently vanished, and
     it is invisible to any test that only asks where things are. ]]
local function everythingVisible(H, m, where)
  local b = m.board
  local ns = H.ns
  local snap = b.snapshot or {}
  --[[ EXACTLY ONE ALPHA IS LEGITIMATE for a card at rest: full. Hearthstone
       never fades a card you cannot play (it just gets no green border), so
       anything below 1 is a card some animation faded and nothing put back. ]]
  local function check(list, n, what)
    H.eq(#list, n, where .. ": " .. what .. " -- a widget per card")
    for i, w in ipairs(list) do
      local a = w.frame:GetAlpha()
      H.ok(w.frame:IsShown(), where .. ": " .. what .. " " .. i .. " is shown")
      H.ok(a >= 0.999,
           where .. ": " .. what .. " " .. i ..
           " is fully opaque, not a ghost (alpha "
           .. tostring(a) .. ")")
      H.ok(w.frame:GetWidth() > 1 and w.frame:GetHeight() > 1,
           where .. ": " .. what .. " " .. i .. " has a size")
    end
  end
  check(b.handPool.used,  #(snap.hand or {}),     "your hand")
  check(b.boardPool.used, #(snap.board or {}) + #(snap.foeBoard or {}), "the boards")
  H.ok(b.hero.frame:IsShown(),       where .. ": your hero is drawn")
  H.ok(b.foeHero.frame:IsShown(),    where .. ": their hero is drawn")
  H.ok(b.heroPower.frame:IsShown(),  where .. ": your hero power is drawn")
  H.ok(b.manaText:IsShown(),         where .. ": the mana readout is drawn")
end

--============================================================ the gestures

--- Put the pointer over the first drop zone -- the middle of your own board.
local function overOwnBoard(b)
  local z = b.L.dropZones[1]
  Stub.CursorOver(b.frame, z.x + z.w / 2, z.y + z.h / 2)
end

--- Pick a hand card up and let go wherever the pointer is.
local function dragHandCard(b, i)
  local hit = b.handHitPool.used[i]
  if not hit then return false end
  hit.frame:GetScript("OnDragStart")(hit.frame)
  hit.frame:GetScript("OnDragStop")(hit.frame)
  return true
end

local function indexInHand(m, cardId)
  for i, c in ipairs(m.game.players[1].hand) do
    if c.cardId == cardId then return i end
  end
end

--============================================================ the Coin

H.suite("table: the pointer exists at all, so a drop can land", function(ns, H)
  --[[ The assertion that unlocks every other one in this file. Without a
       cursor, `CursorInBoard` returns nil and every drop in the game resolves
       as "dropped on nothing". ]]
  local m, b = app(ns)
  H.ok(ourTurn(m), "our turn")
  overOwnBoard(b)
  local x, y = b:CursorInBoard()
  H.ok(x and y, "the board can see the pointer")
  H.ok(ns.Layout.DropIndexAt(b.L, x, y), "and it is over a drop zone")
  Stub.CursorOver(nil)
  H.eq(b:CursorInBoard(), nil, "and off the board it sees nothing")
end)

H.suite("table: dragging the Coin out gives you the mana", function(ns, H)
  --[[ THE REPORT: "I used my mana coin, all my cards disappeared visually and
       I didn't get a mana -- my mana didn't render as 2/1." The mana half was
       Data: the Coin had no effect script (tests/test_tokens.lua). This is the
       BOARD half -- that the readout says so. ]]
  local m, b = app(ns, { secondPlayer = true })
  H.ok(ourTurn(m), "our turn")
  local coin = indexInHand(m, "GAME_005")
  H.ok(coin, "we were dealt the Coin for going second")

  H.eq(b.manaText:GetText(), "1/1", "one mana before")
  overOwnBoard(b)
  H.ok(dragHandCard(b, coin), "the Coin is dragged onto the table")
  H.ok(settle(m), "and the board settles")

  H.eq(b.manaText:GetText(), "2/1", "TWO available of one crystal")
  everythingVisible(H, m, "after the Coin")
end)

--========================================================== playing a minion

H.suite("table: dragging a minion out plays it, and nothing vanishes",
function(ns, H)
  local m, b = app(ns)
  H.ok(ourTurn(m), "our turn")
  --[[ Something cheap enough to play on turn one, put in hand directly so the
       test does not depend on the shuffle. ]]
  H.Hand(m.game, 1, "CS2_231")               -- Wisp, 0 mana
  m.controller:Changed()
  local wisp = indexInHand(m, "CS2_231")
  H.ok(wisp, "the Wisp is in hand")
  local handBefore = #m.game.players[1].hand

  overOwnBoard(b)
  H.ok(dragHandCard(b, wisp), "dragged onto the board")
  H.ok(settle(m), "the board settles")

  H.eq(#m.game.players[1].hand, handBefore - 1, "the card left the hand")
  H.eq(#m.game.players[1].board, 1, "and is on the board")
  everythingVisible(H, m, "after a minion lands")
end)

--=========================================================== attacking

H.suite("table: dragging a minion at a face attacks with it", function(ns, H)
  --[[ THE REPORT: "if I click and drag a unit on the board it can cause things
       to disappear -- units or cards -- until I force resize it." ]]
  local m, b = app(ns)
  H.ok(ourTurn(m), "our turn")
  H.Put(m.game, 1, "CS2_182")                 -- a Yeti that is not summoning sick
  m.controller:Changed()
  H.eq(#b.myMinions, 1, "it is drawn")

  local foeHealthBefore = m.game.players[2].hero:Health()
  local wdg = b.myMinions[1]
  Stub.CursorOver(b.frame, b.L.foeHero.x + b.L.foeHero.w / 2,
                           b.L.foeHero.y + b.L.foeHero.h / 2)
  wdg.frame:GetScript("OnDragStart")(wdg.frame)
  wdg.frame:GetScript("OnDragStop")(wdg.frame)
  H.ok(settle(m), "the board settles")

  H.eq(m.game.players[2].hero:Health(), foeHealthBefore - 4, "the Yeti swung")
  everythingVisible(H, m, "after an attack")
end)

H.suite("table: dragging a minion that CANNOT attack leaves the board intact",
function(ns, H)
  --[[ The refused gesture is the one that broke things: the play is turned
       down, nothing redraws, and whatever the drag did to the widget stays
       done. A refusal must leave the table exactly as it found it. ]]
  local m, b = app(ns)
  H.ok(ourTurn(m), "our turn")
  H.Put(m.game, 1, "CS2_231", { sick = true })   -- summoning sick: cannot swing
  m.controller:Changed()

  local wdg = b.myMinions[1]
  Stub.CursorOver(b.frame, b.L.foeHero.x + b.L.foeHero.w / 2,
                           b.L.foeHero.y + b.L.foeHero.h / 2)
  wdg.frame:GetScript("OnDragStart")(wdg.frame)
  wdg.frame:GetScript("OnDragStop")(wdg.frame)
  H.ok(settle(m), "the board settles")
  everythingVisible(H, m, "after a refused attack")
end)

--=========================================================== the hero power

H.suite("table: dragging the hero power leaves the hand where it was",
function(ns, H)
  --[[ THE REPORT: "sometimes pressing the hero power ability -- maybe click and
       dragging it -- our hand becomes invisible." ]]
  local m, b = app(ns, { class = "MAGE" })
  H.ok(ourTurn(m), "our turn")
  while m.game.players[1].maxMana < 2 do
    m:OnIntent({ kind = "END_TURN" })
    H.ok(ourTurn(m), "round trip")
  end
  everythingVisible(H, m, "before the hero power")

  local hp = b.heroPower.frame
  Stub.CursorOver(b.frame, b.L.foeHero.x + b.L.foeHero.w / 2,
                           b.L.foeHero.y + b.L.foeHero.h / 2)
  hp:GetScript("OnDragStart")(hp)
  hp:GetScript("OnDragStop")(hp)
  H.ok(settle(m), "the board settles")
  everythingVisible(H, m, "after Fireblast is dragged onto a face")
end)

H.suite("table: a hero power aimed at nothing puts the hand back", function(ns, H)
  --[[ The cancel path. An aim released over empty table cancels, and the
       cancel must redraw -- this is the one that leaves a hand mid-gesture. ]]
  local m, b = app(ns, { class = "MAGE" })
  H.ok(ourTurn(m), "our turn")
  while m.game.players[1].maxMana < 2 do
    m:OnIntent({ kind = "END_TURN" })
    H.ok(ourTurn(m), "round trip")
  end

  local hp = b.heroPower.frame
  Stub.CursorOver(nil)                       -- released off the board entirely
  hp:GetScript("OnDragStart")(hp)
  hp:GetScript("OnDragStop")(hp)
  H.ok(settle(m), "the board settles")
  everythingVisible(H, m, "after a cancelled hero power")
end)

--===================================================== a whole match, watched

H.suite("table: nothing ever vanishes over a whole practice match",
function(ns, H)
  --[[ THE SOAK. Every bug in this family showed up mid-match after some
       ordinary action, and none of them were reproducible on demand -- so the
       test plays a real game with a real opponent and checks the invariant at
       every settled moment, which is the only way to catch "sometimes".

       This is the same instrument that found the instance-id desync: a long
       run asserting something boring. ]]
  local m, b = app(ns)
  local turns = 0
  for _ = 1, 24 do
    if m.game.over then break end
    if not ourTurn(m) then break end
    turns = turns + 1
    everythingVisible(H, m, "turn " .. turns .. " start")

    --[[ Play whatever is affordable, by dragging it, exactly as a person
         would -- and let each one settle before the next. ]]
    for _ = 1, 4 do
      local snap = b.snapshot or {}
      local playable
      for i = 1, #(snap.hand or {}) do
        if snap.playable and snap.playable[i] then playable = i break end
      end
      if not playable then break end
      overOwnBoard(b)
      if not dragHandCard(b, playable) then break end
      if not settle(m) then break end
      everythingVisible(H, m, "turn " .. turns .. " after a play")
    end

    --[[ ...and swing with everything that can, at the enemy face. ]]
    for _ = 1, 7 do
      local snap = b.snapshot or {}
      local ready
      for i = 1, #(snap.board or {}) do
        if snap.canAttack and snap.canAttack[i] then ready = i break end
      end
      if not ready or not b.myMinions[ready] then break end
      Stub.CursorOver(b.frame, b.L.foeHero.x + b.L.foeHero.w / 2,
                               b.L.foeHero.y + b.L.foeHero.h / 2)
      local wdg = b.myMinions[ready]
      wdg.frame:GetScript("OnDragStart")(wdg.frame)
      wdg.frame:GetScript("OnDragStop")(wdg.frame)
      if not settle(m) then break end
      if m.game.over then break end
      everythingVisible(H, m, "turn " .. turns .. " after an attack")
    end

    if m.game.over then break end
    m:OnIntent({ kind = "END_TURN" })
  end
  H.ok(turns >= 4, "we got at least four turns in, got " .. turns)
  H.noEngineErrors(m.game)
end)

H.suite("table: going second cannot advance turns during mulligan",function(ns,H)
  local m,b=app(ns,{secondPlayer=true,beforeConfirm=function(m)
    m:OnIntent({kind="CLICK_MULLIGAN",handIndex=1})
    m:RunOpponentIfNeeded()
    Stub.Advance(3)
    H.eq(m.game.phase,"MULLIGAN")
    H.eq(m.game.players[1].maxMana,0)
    H.eq(m.game.players[2].maxMana,0)
    H.notOk(m.aiRunning)
  end})
  H.ok(ourTurn(m))
  H.eq(m.game.players[1].maxMana,1,"first turn has one crystal")
  H.eq(m.game:AvailableMana(1),1,"Coin is not automatically spent")
end)

H.suite("table: rope expiry waits for the current animation and ends once",function(ns,H)
  local m,b=app(ns)
  H.ok(ourTurn(m))
  local turn=m.game.turn
  b:BeginPresentation()
  -- the animation allowance for this turn is already used up (docs/13)
  m.lockedTurn, m.lockedSpent = m.game.turn, ns.Main.LOCKED_ALLOWANCE
  m.director.elapsed=m.game:TurnSeconds()-.01
  m.clockFrame:GetScript("OnUpdate")(m.clockFrame,.02)
  H.eq(m.game.turn,turn,"cannot end while action is resolving")
  H.ok(m.pendingTurnExpiry,"expiry is retained rather than lost")
  b:EndPresentation()
  m.clockFrame:GetScript("OnUpdate")(m.clockFrame,.01)
  H.ok(m.game.turn>turn,"deadline is applied after the animation")
  H.eq(m.pendingTurnExpiry,nil,"one expiry only")
end)

H.suite("table: your own animations do not burn your turn, up to an allowance",function(ns,H)
  local m,b=app(ns)
  H.ok(ourTurn(m))
  local before=m.director.elapsed
  b:BeginPresentation()
  m.clockFrame:GetScript("OnUpdate")(m.clockFrame,5)
  H.eq(m.director.elapsed,before,"five seconds of animation cost nothing")
  m.clockFrame:GetScript("OnUpdate")(m.clockFrame,ns.Main.LOCKED_ALLOWANCE)
  m.clockFrame:GetScript("OnUpdate")(m.clockFrame,1)
  H.ok(m.director.elapsed>before,"but a turn cannot hide behind them forever")
  b:EndPresentation()
end)

--============================================================ docs/27

H.suite("table: Concede ends a bot game as a loss, asked first, counted once", function(ns, H)
  local m, b = app(ns)
  H.ok(settle(m))
  H.ok(b.concede:IsShown(), "Concede is in the corner during the game")
  b.concede:Click()
  H.ok(m.concedeDialog:IsShown(), "it asks before giving up")
  m.concedeDialog.buttons[2]:Click()
  H.notOk(m.game.over, "Keep Playing keeps playing")
  b.concede:Click(); m.concedeDialog.buttons[1]:Click()
  H.ok(m.game.over, "Concede concedes")
  H.eq(m.game.winner, 2, "and the bot wins")
  settle(m)
  H.eq(m:PracticeRecord().losses, 1, "the practice record counts it once")
  H.eq(m:PracticeRecord().wins, 0)
  H.eq(m:Record().losses, 0, "and the duel record is untouched")
  H.notOk(b.concede:IsShown(), "the button is gone once the game is over")
end)
