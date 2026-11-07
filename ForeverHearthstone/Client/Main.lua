--[[ Client/Main.lua

  THE ADDON ENTRY POINT, AND THE ONLY OTHER FILE THAT TOUCHES THE WoW API.

  Everything above this is platform-free: Engine/, Client/Assets, Client/FX,
  Client/UI/Layout and Client/Controller all run headless under plain Lua 5.1,
  which is why the whole rules engine and the whole interaction model are
  testable in a terminal. This file and Client/UI/Board.lua are the only places
  that know WoW exists.

  What this does today: wires the board to the controller, and runs either a
  solo practice match against Client/AI.lua or a REAL DUEL against another
  player through Client/Net. The controller does not know which -- it hands a
  finished action to whoever is taking them, and in a duel that is the session,
  which applies it locally and puts it on the wire. That seam is why networking
  did not require rewriting the interaction model.

  MAINLINE, NOT CLASSIC. Forever is WOW_PROJECT_MAINLINE at interface 16001
  (API ~12.1.5). Ported from Retail, never from Classic -- see docs/07. Two
  consequences show up here:
    * COMBAT_LOG_EVENT_UNFILTERED ERRORS ON REGISTRATION. It is not used.
    * C_ChatInfo.PerformEmote replaces the deprecated DoEmote.
  Neither is needed yet, but they are the traps a future edit would walk into.
]]
local ADDON, ns = ...

local Main = {}
ns.Main = Main

-- ============================================================ practice match

--[[ A solo practice match against Client/AI.lua. Also the developer loop: the
     fastest way to see a real board is to start one, and it needs no second
     player, no network and no collection. ]]
--[[ THE CLASS THIS CHARACTER PLAYS.

     A WoW character is one class forever, and the whole collection is built on
     that: Collection:GrantForLevel files class cards under UnitClass("player"),
     and the collection screen shows them. Practice ignored all of it and
     hardcoded MAGE, so a Rogue opened a practice match holding a Mage deck
     while their collection said Rogue -- two different answers to "what am I"
     from one addon.

     The four classes WoW has and Hearthstone does not are mapped onto the
     closest of the nine rather than refused. A Death Knight who cannot start a
     practice match at all is worse served than one who practises as a Warrior,
     and the mapping is stated here rather than being an accident of a fallback
     somewhere. ]]
Main.CLASS_FOR_WOW = {
  DEATHKNIGHT = "WARRIOR",   -- plate, melee, self-sustain
  DEMONHUNTER = "WARLOCK",   -- the demonic half of the fantasy
  MONK        = "ROGUE",     -- unarmoured, fast, combo-shaped
  EVOKER      = "MAGE",      -- ranged elemental damage
}

function Main:PlayerClass()
  local _, class = UnitClass("player")
  if not class then return "MAGE" end
  class = class:upper()
  class = Main.CLASS_FOR_WOW[class] or class
  for _, known in ipairs(ns.CLASSES) do
    if known == class then return class end
  end
  return "MAGE"
end

--[[ Someone to practise against. Deliberately not your own class: a mirror
     match is the one matchup that teaches you nothing about what the other
     eight do. Random, from Main rather than from the engine: math.random may
     never be touched inside a game (it would desync lockstep), but choosing who
     to practise against happens before there is a game. ]]
function Main:PracticeOpponentFor(myClass)
  local pool = {}
  for _, c in ipairs(ns.CLASSES) do
    if c ~= myClass then pool[#pool + 1] = c end
  end
  return pool[(math.random(1, #pool))] or "PRIEST"
end

--[[ THE PRACTICE BOT'S DIFFICULTY, 1 (Novice) to 5 (Master).

     One number sets both halves of how hard a bot is: the deck it brings
     (Client/BotDecks.lua, tier for tier) and how hard it thinks
     (AI.DIFFICULTIES). Saved for the account, like the volume: it is a
     preference about practice, not about a character. ]]
function Main:BotDifficulty()
  local db = rawget(_G, "ForeverHearthstoneDB")
  return ns.AI.ClampDifficulty(db and db.botDifficulty or ns.AI.DEFAULT_DIFFICULTY)
end

function Main:SetBotDifficulty(d)
  d = ns.AI.ClampDifficulty(d)
  ForeverHearthstoneDB = ForeverHearthstoneDB or {}
  ForeverHearthstoneDB.botDifficulty = d
  return d
end

function Main:StartPractice(myClass, foeClass, selectedDeck, foeDeck, difficulty)
  if self.session and self.session:IsActive() then
    self:Print("Finish or concede your player duel before starting a bot game."); return false
  end
  if self.agreedDialog then self.agreedDialog:Hide() end   -- a duel's ending is not this game's
  if selectedDeck then
    local found=false
    for _,deck in ipairs(self.collection and self.collection.character.decks or {}) do
      if deck==selectedDeck then found=true end
    end
    if not found or selectedDeck.class~=self:PlayerClass() or not self.collection:ValidateDeck(selectedDeck) then
      self:Print("Choose a complete, valid deck before playing."); return false
    end
    myClass=selectedDeck.class
  end
  self.lastEmote = nil
  self.running = {}
  self.presentQueue, self.presentBusy = {}, false
  if self.fxFrame then self.fxFrame:SetScript("OnUpdate", nil) end
  if self.board then self.board:ResetMatch() end
  myClass  = myClass  or self:PlayerClass()
  foeClass = foeClass or self:PracticeOpponentFor(myClass)
  -- A supplied/rematch deck must belong to the displayed opponent.
  if foeDeck and foeDeck.class ~= foeClass then foeDeck = nil end
  --[[ The bot's deck: one of its class's seven, at the chosen difficulty's
       tier. Picked with math.random for the same reason the class is -- before
       the game exists -- and kept for a rematch, as Hearthstone keeps the
       opponent you just played. ]]
  difficulty = ns.AI.ClampDifficulty(difficulty or self:BotDifficulty())
  foeDeck = foeDeck or ns.BotDecks.Pick(foeClass, difficulty, math.random)
  self.botOpts = { difficulty = difficulty, style = foeDeck and foeDeck.style or "midrange" }
  self.botDeck = foeDeck
  self.aiThink = nil
  local myDeck = ns.Controller.BasicDeck(myClass)
  local saved = self.collection and self.collection:ActiveDeck()
  if saved and saved.class == myClass and self.collection:ValidateDeck(saved) then myDeck = saved.cards end
  if selectedDeck then myDeck=selectedDeck.cards end

  --[[ WHO GOES FIRST IS A COIN FLIP.

       It was hardcoded to player 1, so practice was always "you are on the
       play" -- you never went second, never held the Coin, and never saw the
       four-card mulligan. Two of the game's opening mechanics were unreachable
       from the only mode that does not need a second person.

       math.random is correct here and nowhere near the engine: this is chosen
       BEFORE the game exists, and the result is passed in as configuration. ]]
  local game = ns.Game.New({
    seed = math.floor(GetTime() * 1000) % 2147483647,
    firstPlayer = math.random(1, 2),
    players = {
      { class = myClass,  deck = myDeck },
      { class = foeClass, deck = foeDeck and ns.BotDecks.Expand(foeDeck)
                                  or ns.Controller.BasicDeck(foeClass) },
    },
  })
  --[[ Deal and stop. The practice match begins with a mulligan exactly as a
       duel does -- it is the first thing that happens in a game of Hearthstone,
       and practising without it would be practising something else. ]]
  game:Deal()
  game.bus:Drain()

  self.game = game
  self.mode = "practice"
  -- What Rematch replays: the same matchup, the same decks, the same bot.
  self.lastPractice = { my = myClass, foe = foeClass, deck = selectedDeck,
                        foeDeck = foeDeck, difficulty = difficulty }
  self:StartDirector(game, 1)
  self.controller = ns.Controller.New({
    game = game,
    player = 1,
    submit = self:Animated(game, 1, function(action)
      return ns.Actions.Run(game, 1, action)
    end),
    onChange = function(snap)
      if self.board then self.board:SetSnapshot(snap) end
      -- a win on your own turn never reaches the bot's step, which said it
      if game.over and self.game == game then self:AnnounceResult() end
    end,
  })

  if not self.board then
    self.board = ns.Board.Create({
      resolver = self.resolver,
      onIntent = function(intent) self:OnIntent(intent) end,
      onToggleMute = function() self:ToggleMute() end,
      onRematch = function() self:Rematch() end,
      onDeclineRematch = function() self:DeclineRematch() end,
      onLeave = function() self:LeaveGame() end,
      onClose = function() self:RequestDuelExit() end,
      onConcede = function() self:ConfirmConcede() end,
      -- in a duel, what you hold up and aim at is shown to the opponent
      onHover = function(hand, src, dst)
        if self.mode == "duel" and self.session then
          self.session:SendHover(hand, src, dst)
        end
      end,
    })
  end
  self:WatchBoard()
  --[[ A new match, a new table. The board frame is built once and reused for
       every game, so this cannot live in Board.Create -- doing it there gave
       every match of the session the same board. ]]
  self.board:SetBoardArt(game.seed)
  self.board:PrefetchArt(self:MatchArtIds(game))
  self:RefreshProfiles()
  self.board:Show()
  --[[ The opponent mulligans immediately. The engine will not begin play until
       BOTH players have submitted, so without this the practice match would sit
       in the mulligan phase forever. It is not stepped: there is nothing to
       watch, and the player is looking at their own mulligan. ]]
  self.aiRunning = false
  ns.AI.Mulligan(game, 2, self:Animated(game, 2, function(action)
    return ns.Actions.Run(game, 2, action)
  end), self.botOpts)
  self.controller:Changed()
  self:PlayOpeningLines(1)
  self:SyncMusic()
  return true
end

--[[ Every intent the board can raise arrives here. The controller decides what
     it means; this only reports refusals, because a refusal is normal (an
     illegal target, a card that costs too much) and the player needs to know
     why rather than have the click vanish. ]]
function Main:OnIntent(intent)
  if intent.kind == "EMOTE" then
    local label = ns.Board.EMOTES[intent.index]
    if not label or not self.board or not self.game or self.game.over then return end
    if self.lastEmote and GetTime()-self.lastEmote < 2 then return end
    if self.mode ~= "practice" and self.session then
      local ok = self.session:Emote(intent.index); if not ok then return end
    end
    self.lastEmote = GetTime()
    self.board:ShowSpeech("self", label)
    --[[ No Hearthstone hero line: your WoW character performs the emote and
         speaks it in their own voice. Board.WOW_EMOTES maps each to a voiced
         WoW emote, or a fun one where WoW has no voiced match. ]]
    if C_ChatInfo and C_ChatInfo.PerformEmote then
      local target=self.mode=="duel" and self.session and self.session.peer.name or nil
      local ok=C_ChatInfo.PerformEmote(ns.Board.WOW_EMOTES[intent.index],target)
      if ok==false then self:Print("WoW could not perform that emote right now.") end
    end
    return
  end
  if not self.controller then return end
  local wasMulligan = self.game and self.game:AwaitingMulligan()
  local ok, why = self.controller:HandleIntent(intent)
  --[[ A refusal is said ON THE TABLE, in your hero's words, as Hearthstone's
       is -- chat sits behind the window. Your hero also says it aloud. What
       has no line goes to chat, except clicks that simply did nothing. ]]
  if not ok then
    local voice = self.controller:RefusalVoice(why)
    if voice then ns.Sounds.PlayHero(self:HeroCardId(self.controller.me), voice) end
    local line = voice and Main.REFUSAL_LINES[voice]
    if line and self.board then self.board:ShowSpeech("self", line)
    elseif why and not Main.QUIET_REFUSALS[why] then self:Print(why) end
  end

  --[[ Confirming the mulligan is what starts the game, so the clock only begins
       there -- not when the board appeared. ]]
  if wasMulligan and self.game and not self.game:AwaitingMulligan() and self.director then
    self.director:ResetTurn(self.game)
  end
  if wasMulligan then self:SyncMusic() end

  self:RunOpponentIfNeeded()
end

--[[ THE OPPONENT TAKES ITS TURN WHERE YOU CAN SEE IT.

     This used to call AI.TakeTurn, which plays every card and makes every
     attack inside one loop. The whole turn therefore happened between two
     screen refreshes: the board before, the board after, and nothing in
     between -- no cards moving, no attacks, no sound. From the other side of
     the table that is indistinguishable from the opponent doing nothing while
     your health drops by itself, which is exactly what it looked like.

     So the turn is STEPPED. One decision, then a pause long enough to watch
     the animation it caused, then the next.

     THE PAUSE IS THE ANIMATION'S OWN LENGTH. Choreography timelines already
     know how long they run, so the step waits for the one it just started
     rather than for a number picked here -- a Play is a different length from
     an Attack and the turn should breathe accordingly. AI_STEP_MIN is the
     floor for an action with NO visual at all (a hero power, a card the
     choreography has no beat for); without it those would resolve instantly
     and the turn would still blur past in exactly the places nothing was drawn
     to explain it.

     The whole thing is driven by C_Timer.After chained to itself rather than by
     an OnUpdate, because the natural unit here is "and then, a moment later",
     not "every frame". ]]
Main.AI_STEP_MIN = 0.55        -- an action with nothing to watch still takes time
Main.AI_STEP_BEAT = 0.25       -- a breath after the animation, before the next
Main.AI_TURN_END_SECONDS = 0.6

function Main:RunOpponentIfNeeded()
  --[[ Only in practice. In a duel the opponent is a person, and running the AI
       would play their turn for them on our client only -- which is a desync
       manufactured by the addon itself. ]]
  if self.mode ~= "practice" then return end
  local g = self.game
  if not g or g.over or g.phase ~= "PLAY" or g.activePlayer == 1 then return end
  --[[ Re-entry guard. Every step redraws, and a redraw can reach back here;
       without this the opponent would start a second turn on top of its
       first. ]]
  if self.aiRunning then return end
  self.aiRunning = true
  self.aiBlocked = {}
  self:StepOpponent()
end

--[[ THE BOT THINKS WITHOUT FREEZING THE GAME.

     A Master looks at several hundred hypothetical moves before it commits to
     a turn, and run in one go that is a visible hitch -- the whole client
     stops for as long as the bot is deciding. So the decision runs in a
     coroutine that yields every AI_THINK_SLICE simulated moves, and is resumed
     a frame at a time: the board keeps animating, the rope keeps burning, and
     the bot simply takes a moment, as a player does.

     Most steps need no thinking at all -- the turn was planned once and is
     being played out -- so the first resume usually finishes on the spot and
     the step carries straight on. Returns action, stillThinking. ]]
Main.AI_THINK_SLICE = 12

function Main:BotDecide(g, foe)
  local t = self.aiThink
  if t and t.game == g and t.done then
    self.aiThink = nil
    return t.action, false
  end
  if t and t.game == g then return nil, true end

  local opts = {}
  for k, v in pairs(self.botOpts or {}) do opts[k] = v end
  opts.yield, opts.yieldEvery = coroutine.yield, Main.AI_THINK_SLICE
  local blocked = self.aiBlocked
  t = { game = g, sync = true }
  t.co = coroutine.create(function() return ns.AI.NextAction(g, foe, blocked, opts) end)
  self.aiThink = t
  local function pump()
    if self.aiThink ~= t then return end          -- abandoned: a new match, or left
    local ok, result = coroutine.resume(t.co)
    if not ok then
      --[[ A think that errors ends the bot's turn rather than the match: it
           answers "nothing to do", and the error is reported once. ]]
      if not self.botErrorShown then
        self.botErrorShown = true
        self:Print("the practice bot hit an error while thinking (please report this):\n"
                   .. tostring(result))
      end
      t.done, t.action = true, nil
    elseif coroutine.status(t.co) == "dead" then
      t.done, t.action = true, result
    end
    if t.done then
      if not t.sync then self:StepOpponent() end
    else
      self:AfterDelay(0, pump)
    end
  end
  pump()
  t.sync = false
  if t.done then
    self.aiThink = nil
    return t.action, false
  end
  return nil, true
end

--[[ A STEP THAT FAILS MUST NOT END THE BOT'S TURN FOREVER. The step runs in
     a C_Timer callback; an error there (in the animation, the history, a
     widget) stopped the chain silently -- the client hides script errors by
     default -- and left the board's presentation lock on, so the bot sat on
     "Enemy Turn" for good. Now the error is printed once, the lock is
     released, the action is marked refused, and the turn carries on. ]]
--[[ Run `fn`, reporting an error once instead of letting it escape. Used where
     an escaping error would strand the board: a click or a remote action whose
     presentation throws must still end in EndPresentation. Returns true when
     `fn` finished. ]]
function Main:Guarded(fn)
  local ok, err = xpcall(fn, function(e)
    local ds = rawget(_G, "debugstack")
    return tostring(e) .. (ds and ("\n" .. ds(2, 6, 0)) or "")
  end)
  if ok then return true end
  if not self.guardErrorShown then
    self.guardErrorShown = true
    self:Print("something went wrong showing that move (please report this):\n" .. err)
  end
  return false
end

function Main:StepOpponent()
  local ok, err = xpcall(function() return self:StepOpponentUnsafe() end,
    function(e)
      local ds = rawget(_G, "debugstack")
      return tostring(e) .. (ds and ("\n" .. ds(2, 6, 0)) or "")
    end)
  if ok then return end
  if not self.botErrorShown then
    self.botErrorShown = true
    self:Print("the practice bot hit an error and skipped a move (please report this):\n" .. err)
  end
  if self.board and self.board.presentationLocked then
    pcall(function() self.board:EndPresentation() end)
  end
  local action = self.aiStepAction
  if action and action._key and self.aiBlocked then self.aiBlocked[action._key] = true end
  self.aiStepAction = nil
  self.aiFailures = (self.aiFailures or 0) + 1
  local g = self.game
  if self.aiFailures > 8 and g and not g.over and g.activePlayer ~= 1 then
    -- nothing it tries works: hand the turn back rather than stall
    self.aiFailures = 0
    pcall(function() g:EndTurn(); g.bus:Drain() end)
    self.aiRunning = false
    if self.controller then pcall(function() self.controller:Changed() end) end
    return
  end
  self:AfterDelay(0.3, function() self:StepOpponent() end)
end

function Main:StepOpponentUnsafe()
  local g = self.game
  if not g or self.mode ~= "practice" then self.aiRunning = false; return end
  -- nobody is watching: the bot waits for you, as the rope does
  if self:PracticePaused() then
    self:AfterDelay(0.5, function() self:StepOpponent() end)
    return
  end
  local foe = g.activePlayer

  if g.over or g.phase ~= "PLAY" or foe == 1 then
    self.aiRunning = false
    self.controller:Changed()
    if g.over then self:AnnounceResult() end
    return
  end

  local action, thinking = self:BotDecide(g, foe)
  if thinking then return end      -- the think resumes this step when it is done
  self.aiStepAction = action
  if action then
    -- a minion's recording plays out over the next action, as in Hearthstone
    --[[ The opponent's moves animate exactly as yours do -- same wrapper, same
         director, same choreography. A board where only your own plays have
         weight reads as a bug. ]]
    local ok, why = self:Animated(g, foe, function(a)
      return ns.Actions.Run(g, foe, a)
    end)(action)
    --[[ Refused only because something is still animating (the tail of your
         turn, a death still fading): the move is fine, the moment is not. It
         used to be recorded as ILLEGAL, so the bot abandoned its best play
         and could sit out a turn it had every reason to take. ]]
    if not ok and why == "animation in progress" then
      self:AfterDelay(0.2, function() self:StepOpponent() end)
      return
    end
    local shown = self.lastShown or 0
    --[[ A refusal is recorded rather than retried. NextAction is stateless, so
         it would choose the same refused action again on the very next step and
         the opponent's turn would never end. ]]
    if not ok and action._key then self.aiBlocked[action._key] = true end
    self.controller:Changed()
    local wait = math.max(Main.AI_STEP_MIN, (shown or 0) + Main.AI_STEP_BEAT)
    self.aiFailures = 0
    self:AfterDelay(wait, function() self:StepOpponent() end)
    return
  end

  --[[ Nothing left to do: hand the turn back, after a beat so the last
       animation is not cut off by the turn change. ]]
  self:AfterDelay(Main.AI_TURN_END_SECONDS, function()
    local game = self.game
    if not game or game.over or game.phase ~= "PLAY" or game.activePlayer == 1 then
      self.aiRunning = false
      if self.controller then self.controller:Changed() end
      if game and game.over then self:AnnounceResult() end
      return
    end
    game:EndTurn()
    game.bus:Drain()
    self.aiRunning = false
    self.controller:Changed()
    if game.over then self:AnnounceResult() end
  end)
end

--[[ Whoever is that player's hero right now -- a replaced hero (Lord
     Jaraxxus) has no voice lines and simply stays quiet. ]]
function Main:HeroCardId(player)
  local g = self.game
  local p = g and player and g.players[player]
  return p and p.hero and p.hero.cardId
end

--[[ THE HEROES INTRODUCE THEMSELVES, yours first and then theirs, as the match
     opens. Against your own hero the reply is the mirror line. ]]
function Main:PlayOpeningLines(me)
  local g = self.game
  if not (g and me) then return end
  local mine, theirs = self:HeroCardId(me), self:HeroCardId(g:Opponent(me))
  ns.Sounds.PlayHero(mine, "start", true)
  self:AfterDelay(2.8, function()
    if self.game == g then
      ns.Sounds.PlayHero(theirs, mine == theirs and "mirror_start" or "start", true)
    end
  end)
end

--[[ MUSIC, OPT-IN (`/fh music`). Hearthstone's own tracks for the menu, the
     mulligan and the duel. Off by default, per docs/06 §6.3: the zone music
     is part of the place you chose to sit down in, and replacing it is the
     player's call. PlayMusic replaces it; StopMusic hands it back. ]]
local MUSIC_DIR = "Interface\\AddOns\\ForeverHearthstone\\Art\\Sounds\\Music\\"
function Main:Music(track)
  local db = rawget(_G, "ForeverHearthstoneDB")
  --[[ On unless turned off (`/fh music`): the tavern's theme at the main
       menu is most of what makes it Hearthstone's. (It was opt-in, so it had
       never been heard.) The mute silences it without stopping it
       (Sounds.SilenceMusic), so unmuting carries on where it was. ]]
  if track and not (db and db.music ~= false) then track = nil end
  if track ~= self.musicTrack then
    self.musicTrack = track
    if track then
      if PlayMusic then PlayMusic(MUSIC_DIR .. track .. ".mp3") end
    elseif StopMusic then
      StopMusic()
    end
  end
  -- silent only while OUR track plays: the zone's music keeps its volume
  ns.Sounds.SilenceMusic(ns.Sounds.Muted() and self.musicTrack ~= nil)
end

-- The table's music follows the match: the mulligan, then the duel, then silence.
-- The board's showing and hiding choose the music, as the menu's do.
function Main:WatchBoard()
  if not self.board or self.board.musicWatched then return end
  self.board.musicWatched = true
  self.board.frame:HookScript("OnShow", function() self:SyncMusicSoon() end)
  self.board.frame:HookScript("OnHide", function() self:SyncMusicSoon() end)
end

--[[ Windows swap in two steps -- the collection hides, THEN the menu shows --
     and for that instant nothing is open, which stopped the theme and started
     it again on every trip between menus. A window's show or hide therefore
     decides the music once things have settled, on the next frame. ]]
function Main:SyncMusicSoon()
  if self.musicPending then return end
  self.musicPending = true
  local function settle() self.musicPending = nil; self:SyncMusic() end
  if C_Timer and C_Timer.After then C_Timer.After(0, settle) else settle() end
end

--[[ WHICH TRACK, IF ANY. Music plays only while one of this addon's windows
     is open: the board plays the match (mulligan, then duel) while a game is
     on; the main menu and the collection play the tavern theme. Close them
     all and WoW's own zone music comes back -- the theme used to keep going
     after /fh was closed. Every window's show and hide calls this. ]]
--[[ EVERY CARD THIS MATCH CAN PUT ON THE TABLE: both decks and hands, the
     heroes and their powers, and -- one and two steps out -- every card
     their scripts name (a Polymorph's Sheep, a Hex's Frog, summoned tokens,
     equipped weapons) and every printed entourage (Spare Parts, Power
     Chords, Animal Companions). Board:PrefetchArt loads their art at the
     start, because the client loads a texture from disk the first time it is
     drawn: a Sheep appearing for the first time showed the bare table where
     its portrait should be until the file had loaded. ]]
function Main:MatchArtIds(game)
  local ids, seen, frontier = {}, {}, {}
  local function add(id)
    if type(id) == "string" and not seen[id] and ns.PrintedCards[id] then
      seen[id] = true; ids[#ids + 1] = id; frontier[#frontier + 1] = id
    end
  end
  if not game then return ids end
  for pi = 1, 2 do
    local p = game.players[pi]
    for _, zone in ipairs({ p.deck, p.hand, p.board }) do
      for _, e in ipairs(zone or {}) do add(e.cardId) end
    end
    add(p.hero and p.hero.cardId); add(p.heroPower and p.heroPower.cardId)
  end
  local function walk(t, depth)
    if type(t) ~= "table" or depth > 12 then return end
    for k, v in pairs(t) do
      if (k == "cardId" or k == "heroPower") and type(v) == "string" then add(v)
      elseif type(v) == "table" then walk(v, depth + 1) end
    end
  end
  for _ = 1, 2 do                       -- tokens that make tokens (Imp Master's Imp...)
    local batch = frontier; frontier = {}
    for _, id in ipairs(batch) do
      for _, ent in ipairs(ns.PrintedCards[id].entourage or {}) do add(ent) end
      walk(ns.Scripts and ns.Scripts[id], 0)
    end
  end
  return ids
end

function Main:SyncMusic()
  local g = self.game
  local track
  if self.board and self.board:IsShown() then
    if g and not g.over then track = g:AwaitingMulligan() and "mulligan" or "duel" end
  elseif (self.hub and self.hub:IsShown()) or (self.collectionUI and self.collectionUI:IsShown()) then
    track = "mainmenu"
  end
  self:Music(track)
end

function Main:ToggleMusic()
  ForeverHearthstoneDB.music = ForeverHearthstoneDB.music == false
  self:Print(ForeverHearthstoneDB.music and "Hearthstone music on." or "Hearthstone music off; zone music restored.")
  if ForeverHearthstoneDB.music then
    self:SyncMusic()
  else
    self:Music(nil)
  end
  ns.Widgets.RefreshSpeakers()   -- every screen's music button
end

--[[ Mute everything this addon plays: effects, voices and music. The board's
     speaker button and `/fh mute` both land here; the flag is saved, so a
     muted table stays muted after a reload. ]]
function Main:ToggleMute()
  local muted = not ns.Sounds.Muted()
  ns.Sounds.SetMuted(muted)
  --[[ What is already playing stops too: a voice line or the rope's fifteen
       seconds of hiss carrying on after you pressed mute reads as the button
       not working. The rope's fuse pauses (Board:TickRopeAudio) and comes
       back if you unmute while it is still burning. ]]
  if muted then
    ns.Sounds.CutCardAudio(100)
    if self.board and self.board.PauseRopeFuse then self.board:PauseRopeFuse() end
  end
  -- the music keeps playing either way; only its volume changes
  self:SyncMusic()
  ns.Widgets.RefreshSpeakers()
  self:Print(muted and "Hearthstone sound muted." or "Hearthstone sound on.")
end

--[[ A practice game's result: said once, and counted in the practice record
     the main menu shows (Main:PracticeRecord). It is reached from the bot's
     step, from your own winning blow and from Concede, so it guards itself. ]]
function Main:AnnounceResult()
  local g = self.game
  if not (g and g.over) or self.announcedGame == g then return end
  self.announcedGame = g
  self:Music(nil)
  if self.concedeDialog then self.concedeDialog:Hide() end
  local won = g.winner == 1
  if g.winner == nil then won = g.players[2].hero:Health() <= 0 end
  self:Debug(g.winner == 0 and "a draw." or (won and "you win." or "you lose."))
  if self.mode == "practice" and g.winner ~= 0 then
    local record = self:PracticeRecord()
    if won then record.wins = record.wins + 1 else record.losses = record.losses + 1 end
    -- what the game counted for, under the result
    if self.board then
      self.board.postGameNote = ("Practice record: %d-%d"):format(record.wins, record.losses)
      if self.board.postGameState == "ready" then self.board:SetPostGame("ready") end
    end
  end
end

--[[ "And then, a moment later." C_Timer is the Mainline API; the fallback keeps
     the addon working if it is ever absent, by simply doing the thing now --
     which is the old behaviour, and is correct if unwatchable. ]]
function Main:AfterDelay(seconds, fn)
  local match = self.game
  local callback = fn
  fn = function() if self.game == match then callback() end end
  if C_Timer and C_Timer.After then
    C_Timer.After(seconds, fn)
  else
    fn()
  end
end



-- ============================================================= the juice

--[[ WIRING THE ANIMATIONS.

     Client/FX has had a tested choreography library since long before there was
     a match to play it in. Client/FX/Director.lua decides which sequence an
     action deserves; this runs it against the board's stage and drives the
     clock that the rope burns on.

     The whole of it is four functions, because all the hard parts -- timing,
     overlap, escalation, what the rope does at two thirds -- were designed and
     tested headless. ]]
function Main:StartDirector(game, player)
  self.director = ns.Director.New({
    player = player,
    onReset = function()
      self.pendingTurnExpiry=nil
      self.ropeTimeline=nil
      if self.board then self.board:ClearRope() end
    end,
    onExpire = function(what)
      if not self.controller then return end
      --[[ THE MULLIGAN HAS ITS OWN DEADLINE, AND IT IS NOT A TURN.

           The clock used to send END_TURN whatever had run out. During the
           mulligan the controller refuses that -- "choose which cards to throw
           back first" -- so the rope burned down, the timer fired, the refusal
           was swallowed, and absolutely nothing happened. You sat in front of
           an expired mulligan forever.

           Running out of time means you keep what you have, which is what
           Hearthstone does and the only answer that cannot cost you a card you
           had marked. It goes through the ordinary intent path, so in a duel it
           is the same MULLIGAN action that would have crossed the wire had you
           pressed the button. ]]
      if what == "mulligan" then
        self:OnIntent({ kind = "CONFIRM_MULLIGAN" })
      else
        --[[ The turn ran out. This client ends its OWN turn, through the
             ordinary intent path -- so in a duel it is an END_TURN action that
             crosses the wire like any other and the two clients cannot
             disagree about whether the rope ran out. ]]
        self.pendingTurnExpiry={game=self.game,turn=self.game.turn,player=self.game.activePlayer}
      end
    end,
  })
  self.director:ResetTurn(game)
  if not self.clockFrame then self.clockFrame = CreateFrame("Frame") end
  self.clockFrame:SetScript("OnUpdate", function(_, dt)
    if not (self.game and self.director) or self.game.over then return end
    local halted = self:ClockHalted()
    local step = self:ClockStep(dt)
    local plans, rope = {}, nil
    for _, plan in ipairs(self.director:Tick(self.game, step) or {}) do
      if plan.sequence == "Rope" then rope = plan else plans[#plans + 1] = plan end
    end
    self:RunPlans(plans)
    if rope then self:StartRope(rope) end
    self:TickRope(step, halted)
    local pending=self.pendingTurnExpiry
    if pending and (pending.game~=self.game or pending.turn~=self.game.turn or pending.player~=self.game.activePlayer) then
      self.pendingTurnExpiry=nil
    elseif pending and not halted and not (self.board and self.board.presentationLocked) then
      self.pendingTurnExpiry=nil
      self:OnIntent({kind="END_TURN"})
    end
  end)
end

--[[ WHEN THE TURN CLOCK STANDS STILL (docs/13).

     * While the duel is paused -- a player stepped away, died, is in combat --
       or the connection is in trouble: nobody can act, so nobody's rope burns.
     * While YOUR OWN presentation is playing on your turn, up to
       LOCKED_ALLOWANCE seconds a turn: a long chain (a Knife Juggler under a
       Fan of Knives) or a slow machine must not eat the time you have to
       think. Hearthstone's server resolves instantly and its client animates
       quickly; this is the equivalent allowance for a client that has to do
       both. The opponent sees their rope stand still too, so the two clients'
       ropes agree. ]]
Main.LOCKED_ALLOWANCE = 20
--[[ A PRACTICE MATCH WAITS FOR YOU. Close the board (the menu keeps the game
     for Resume Match) or go AFK and it stops: no rope burning down, no bot
     playing its turn to an empty room. WoW cannot tell an addon the game
     window lost focus, so an alt-tab only pauses once WoW flags you AFK. ]]
function Main:PracticePaused()
  if self.mode ~= "practice" then return false end
  -- VISIBLE, not shown: with WoW's UI hidden (Alt+Z) the board is still
  -- "shown", and the bot played on to nobody
  if not (self.board and self.board.frame:IsVisible()) then return true end
  local afk = rawget(_G, "UnitIsAFK")
  return afk and afk("player") and true or false
end

function Main:ClockHalted()
  if self.mode == "practice" then return self:PracticePaused() end
  local s = self.mode == "duel" and self.session
  return s and (s.paused ~= nil or s.connectionProblem) and true or false
end

function Main:ClockStep(dt)
  if self:ClockHalted() then return 0 end
  local g = self.game
  if g and self.board and self.board.presentationLocked then
    if self.lockedTurn ~= g.turn then self.lockedTurn, self.lockedSpent = g.turn, 0 end
    if (self.lockedSpent or 0) < Main.LOCKED_ALLOWANCE then
      self.lockedSpent = (self.lockedSpent or 0) + dt
      return 0
    end
  end
  return dt
end

--[[ THE ROPE RUNS ON THE TURN CLOCK, NOT ON THE FRAME CLOCK.

     It used to be handed to RunPlans like any animation -- and RunPlans speeds
     long animations up to keep a match brisk (FX_COMFORT). The rope is fifteen
     seconds long, so it always got the full 2.5x: it burned out, and its end
     sound played, six seconds in, while the turn itself ran nine seconds more.
     And a timeline ticks on frame time, so whenever the turn clock stood still
     (your own long animation, a paused duel, a paused practice match) the rope
     kept burning anyway.

     So the rope's timeline gets its own slot, never sped up, and is advanced by
     exactly the step the director's clock takes: burn, end sound and expiry
     are the same clock. ]]
function Main:StartRope(plan)
  local stage = self.board and self.board:Stage()
  if not stage then return end
  self.ropeTimeline = nil
  ns.Director.Run({ plan }, stage, function(tl) tl:Start(); self.ropeTimeline = tl end)
end
function Main:TickRope(step, halted)
  --[[ The HISS stops only when the game is really paused. The clock also
       stands still while your own play animates (LOCKED_ALLOWANCE), and the
       fuse going quiet every time a minion landed read as the rope stopping. ]]
  if self.board then self.board.ropeHalted = halted and true or false end
  local tl = self.ropeTimeline
  if tl and not tl:Tick(step or 0) then self.ropeTimeline = nil end
end

function Main:StopDirector()
  self.ropeTimeline = nil
  if self.clockFrame then self.clockFrame:SetScript("OnUpdate", nil) end
  self.director = nil
end

--[[ Run a plan list and report HOW LONG it will take to watch.

     The duration matters because the practice opponent's turn is paced by it:
     one action, wait for what it looks like, then the next. A timeline knows
     its own length, so nothing has to guess. ]]
--[[ LONG CHAINS PLAY FASTER, NEVER LONGER. Hearthstone keeps a turn moving
     however much happens in it: a Knife Juggler and a Fan of Knives are one
     action on the wire (lockstep sends inputs, not outcomes), but a long
     presentation is played quicker. Anything longer than FX_COMFORT seconds
     is sped up to fit, up to FX_MAX_SPEED; a queue of opponent actions
     waiting behind it speeds things up too (Main:PresentRemote). Returns the
     WALL-CLOCK duration. ]]
Main.FX_COMFORT, Main.FX_MAX_SPEED = 2.6, 2.5
function Main:RunPlans(plans)
  if not plans or #plans == 0 then return 0 end
  local stage = self.board and self.board:Stage() or nil
  local longest = 0
  local timelines = {}
  ns.Director.Run(plans, stage, function(tl)
    if tl.duration and tl.duration > longest then longest = tl.duration end
    timelines[#timelines + 1] = tl
  end)
  local queued = self.presentQueue and #self.presentQueue or 0
  local speed = math.max(1, longest / Main.FX_COMFORT, 1 + 0.5 * queued)
  speed = math.min(Main.FX_MAX_SPEED, speed)
  for _, tl in ipairs(timelines) do
    tl.speed = speed
    self:RunTimeline(tl)
  end
  return longest / speed
end

--[[ THE OPPONENT'S ACTIONS, ONE AT A TIME. Their actions are applied to the
     game the moment they arrive (lockstep order is the engine's), but each is
     SHOWN only after the previous one has finished, so a fast opponent's turn
     plays as a sequence rather than a pile-up. ]]
function Main:PresentRemote(plans, locking)
  self.presentQueue = self.presentQueue or {}
  if self.presentBusy then
    self.presentQueue[#self.presentQueue + 1] = { plans = plans, locking = locking }
    return
  end
  local duration = self:RunPlans(plans)
  if not locking then return end
  self.presentBusy = true
  local board = self.board
  self:AfterDelay(duration + 0.05, function()
    self.presentBusy = false
    local nextUp = table.remove(self.presentQueue, 1)
    if nextUp then
      self:PresentRemote(nextUp.plans, nextUp.locking)
    elseif board then
      board:EndPlayAnimation()
      board:EndPresentation()
    end
  end)
end

--[[ Wrap a submit function so that every action it accepts is also ANIMATED.

     The wrapper looks at the game before the action and plans from what it saw,
     because applying the action destroys the evidence -- by the time a card is
     played it is no longer in the hand, and reading the hand slot afterwards
     animates whatever slid into it. ]]
function Main:Animated(game, player, apply)
  return function(action)
    if game.over then return false,"game over" end
    if self.board and self.board.presentationLocked then return false, "animation in progress" end
    local before = ns.Director.Before(game, player, action)
    --[[ Lift the played card out of the hand FIRST. It is about to stop being
         in the hand, and the animation that follows runs for a third of a
         second after that -- long enough for the hand to have closed up and
         put a different card in the slot the animation is pointed at. ]]
    local flying = false
    if self.board and action.kind == "PLAY_CARD" then
      flying = self.board:BeginPlayAnimation(action.handIndex,
        player ~= self.controller.me and before and before.playedCardId or nil)
    end
    local presenting = self.board and (action.kind == "ATTACK" or action.kind == "PLAY_CARD" or action.kind == "HERO_POWER")
    if presenting then self.board:BeginPresentation() end
    --[[ Guarded: an error in the rules or the presentation used to leave the
         board locked for good -- every click refused, and the rope's End Turn
         waiting forever for an unlock that never came. The unlock below is
         now always scheduled. ]]
    local ok, why = false, "error"
    self:Guarded(function() ok, why = apply(action) end)
    if flying and not ok then self.board:EndPlayAnimation() end
    --[[ `lastShown` rather than a second return value: this function IS the
         controller's submit, and its second result is the refusal REASON that
         the UI prints. Overloading it would trade a message the player reads
         for a number only the pacing cares about. ]]
    self.lastShown = 0
    self:Guarded(function()
      if ok and self.board then
        local cardId = before and before.playedCardId
        if action.kind == "HERO_POWER" then cardId = game.players[player].heroPower.cardId end
        if action.kind == "ATTACK" and before and before.attacker then cardId = before.attacker.cardId end
        self.board:AddHistory(cardId, (player == self.controller.me and "You: " or "Enemy: ") .. action.kind:lower():gsub("_", " "), player ~= self.controller.me, action, before, ns.Director.Outcomes(self.game or game, before))
      end
      if ok and self.director then
        self.lastShown = self:RunPlans(self.director:Plan(game, player, action, before))
      end
    end)
    --[[ Put the flying copy away once its animation has had its time. A copy
         left on screen is a card nobody can click sitting over the board. ]]
    if flying and not presenting then
      local board = self.board
      self:AfterDelay(math.max(0.05, self.lastShown + 0.05),
                      function() board:EndPlayAnimation() end)
    end
    if presenting then
      local board = self.board
      self:AfterDelay(ok and math.max(0.05, self.lastShown + 0.05) or 0,
        function() board:EndPresentation() end)
    end
    return ok, why
  end
end

-- ================================================================ the duel

--[[ A REAL MATCH AGAINST A REAL PERSON. This is the feature the whole project
     is for; everything above it is the practice range.

     The transport exists for the whole session, not just during a duel,
     because a challenge has to be able to ARRIVE. An addon that only listens
     while it is already duelling can never be challenged. ]]
-- "Femboy-President", "Femboy President", "Femboy-Realm": the same first name
local function sameFirstName(a, b)
  local function first(n) return tostring(n or ""):lower():match("^[^%s%-]+") end
  return first(a) ~= nil and first(a) == first(b)
end

function Main:EnsureTransport()
  if self.transport then return self.transport end
  self.transport = ns.Transport.New({
    onError = function(err) self:Print(err) end,
    --[[ A message that raised an error mid-handling: the duel's state can no
         longer be trusted, so it ends -- once, with a line to say why. ]]
    onFault = function(err, sender)
      if self.session and self.session.state ~= ns.Session.STATE.ABORTED then
        self.session:Abort("protocol", "a message from " .. tostring(sender) .. " could not be handled")
      end
      if not self.faultReported then
        self.faultReported = true
        self:Print("internal error handling a duel message: " .. tostring(err))
      end
    end,
    --[[ After a finished duel the transport still listens to that opponent (a
         rematch is negotiated there); a stranger's challenge must still get
         through, or nobody else could challenge you until a reload. ]]
    strangersWelcome = function()
      return not (self.session and (self.session:IsActive()
        or self.session.state == ns.Session.STATE.INVITED
        or self.session.state == ns.Session.STATE.OFFERED
        or self.session.state == ns.Session.STATE.REJOINING))
    end,
    --[[ Our challenge's answer, from an address other than the one we sent it
         to (Transport:OnReceive). Only their ACCEPTANCE moves the duel to that
         address, and only when it carries the GUID of the player we
         challenged -- a first name alone let anyone sharing it take the
         challenge over. Their "invited" ping or a decline is still heard
         ("deliver"), but changes nobody's address. ]]
    claim = function(raw, sender)
      local s = self.session
      if not (s and s.state == ns.Session.STATE.OFFERED) then return false end
      local m = ns.Protocol.Decode(raw)
      if not m then return false end
      if not sameFirstName(sender, s.peer.name) then return false end
      local want = s.peer.expectGuid
      if want == "" then want = nil end
      if m.kind == ns.Protocol.KIND.HELLO then
        if want then
          if m[6] ~= want then return false end
        end
        s.peer.name = sender
        return "adopt"
      end
      if m.kind == ns.Protocol.KIND.PING or m.kind == ns.Protocol.KIND.BYE then return "deliver" end
      return false
    end,
    onTick=function(dt)
      if self.session then self.session:Tick(dt) end
      self:TableTick(dt)
    end,
    onMessage = function(raw, sender, fromStranger)
      -- Privacy applies to a previous opponent too, not just strangers.
      local incoming = ns.Protocol.Decode(raw)
      if incoming and incoming.kind == ns.Protocol.KIND.HELLO
         and not (self.session and (self.session:IsActive() or self.session.state == ns.Session.STATE.OFFERED))
         and not self.autoAccept and not self.pendingAutoAccept
         and not self:AllowChallengeFrom(sender, incoming[6]) then
        --[[ A refused challenge is answered -- but not endlessly. Every answer
             went ahead of our own duel's lines, so a stranger repeating
             challenges could hold back everything we sent. So one decline per
             player per half minute (enough to close their pop-up, blocked or
             not), and only a handful may wait at once. ]]
        local now = GetTime and GetTime() or 0
        self.declinedAt = self.declinedAt or {}
        local key = tostring(sender):lower()
        if now - (self.declinedAt[key] or -math.huge) < 30 then return end
        local waiting = 0
        for _, r in ipairs(self.transport.replies or {}) do
          if r.raw:find(";BY;declined", 1, true) then waiting = waiting + 1 end
        end
        if waiting >= 4 then return end
        self.declinedAt[key] = now
        self.transport:SendTo(ns.Protocol.Encode(0, ns.Protocol.KIND.BYE, "declined", incoming[15] or ""), sender)
        return
      end
      --[[ After a game the finished session keeps its peer (a rematch is
           negotiated on it), so a NEW challenge from that same player would
           land in the old session's inbox and be dropped as a duplicate.
           `freshFrom` names the one peer whose next HELLO starts a new
           session; for an agreed rematch it is also accepted for you. ]]
      if not fromStranger and self.freshFrom and ns.Transport.SameName(sender, self.freshFrom)
         and self.session and not self.session:IsActive() then
        local message=ns.Protocol.Decode(raw)
        if message and message.kind==ns.Protocol.KIND.HELLO then
          self.freshFrom=nil
          self:NewSession(sender)
          self.autoAccept, self.pendingAutoAccept = nil, self.autoAccept
        end
      elseif fromStranger then
        --[[ Someone we are not talking to sent something. The only thing that
             may be is the start of a challenge, and it is only honoured when
             there is no duel already in progress -- otherwise a third party
             could interrupt a match. ]]
        if self.session and self.session:IsActive() then return end
        local message=ns.Protocol.Decode(raw)
        if message and message.kind==ns.Protocol.KIND.REJOIN then
          self:OnRejoinOffer(sender)
          return
        end
        if not message or message.kind~=ns.Protocol.KIND.HELLO then return end
        --[[ A finished duel whose rematch is still being settled is not given
             up for a stranger's line -- one garbage HELLO used to wipe it --
             and a challenge has to name a class this game has. ]]
        local old = self.session
        local settling = { asked = true, invited = true, agreed = true }
        -- only while that post-game board is still up: a board closed any way
        -- at all has given its rematch up
        if old and old.state == ns.Session.STATE.OVER and settling[old.rematch or ""]
           and self.board and self.board.frame:IsShown() then return end
        if not ns.Session.KnownClass(message[3]) then return end
        -- who may challenge you (Main:AllowChallengeFrom); the rest are ignored in silence
        if not self:AllowChallengeFrom(sender, message[6]) then return end
        -- someone this client can see standing far off cannot be challenging
        -- you from beside you: dropped in silence, like any refused challenge
        --[[ The GUID in a challenge is the challenger's own claim: quoting a
             bystander's would pass the range check as them. So a unit found
             by GUID counts only when its first name is the sender's too. ]]
        local unit = self:FindPlayerUnit(sender)
        if not unit then
          local byGuid = self:FindPlayerUnit(nil, message[6])
          if byGuid and sameFirstName(ns.Plain(UnitName(byGuid)), sender) then unit = byGuid end
        end
        if unit and not ns.Transport.InRange(unit) then return end
        self:NewSession(sender)
        self.transport:SetPeer(sender)
      end
      if self.session then self.session:Receive(raw) end
    end,
  })
  self.transport:Start()
  return self.transport
end

--[[ Build a session for a duel with `peerName`.

     The nonce is our half of the shuffle seed. It is generated HERE, in the
     WoW-facing file, from the clock and math.random on purpose: the engine may
     never touch math.random (it would desync lockstep), but a nonce must be
     unpredictable and is not part of the simulation. ]]
--- A character's vault is keyed to the character, so it cannot be copied onto another.
function Main.VaultSalt()
  return "character|" .. tostring(UnitGUID and UnitGUID("player") or "")
end

function Main:NewSession(peerName)
  local class = self:PlayerClass()
  local record = self:Record()
  local session = ns.Session.New({
    name  = UnitName("player"),
    wins = record.wins, losses = record.losses,
    level = UnitLevel("player"), guid = UnitGUID("player"),
    class = class,
    getPosition = function() return self:WorldPosition() end,
    deck  = nil, -- selected by each player after acceptance
    nonce = ("%d-%d"):format(math.floor(GetTime() * 1000), math.random(1, 1000000)),
    send  = function(raw) self:EnsureTransport():Send(raw) end,
    onEvent = function(event, data) self:OnSessionEvent(event, data) end,
    --[[ Both sides animate through the same two hooks, so the opponent's turn
         has the same weight as yours -- and the "look before it is applied"
         rule holds for a remote action exactly as it does for a local one. ]]
    onBeforeAction = function(player, action)
      if self.game then
        self.pendingBefore = ns.Director.Before(self.game, player, action)
        if self.board and (action.kind == "ATTACK" or action.kind == "PLAY_CARD" or action.kind == "HERO_POWER") then
          if action.kind == "PLAY_CARD" then
            self.board:BeginPlayAnimation(action.handIndex,
              player ~= self.controller.me and self.pendingBefore.playedCardId or nil)
          end
          self.board:BeginPresentation()
        end
      end
    end,
    onAction = function(player, action)
      -- see Main:Guarded: a presentation error must not leave the board locked
      local fine = self:Guarded(function()
      if self.board then
        local before = self.pendingBefore
        local cardId = before and before.playedCardId
        if action.kind == "HERO_POWER" then cardId = self.game.players[player].heroPower.cardId end
        if action.kind == "ATTACK" and before and before.attacker then cardId = before.attacker.cardId end
        self.board:AddHistory(cardId, (player == self.controller.me and "You: " or "Enemy: ") .. action.kind:lower():gsub("_", " "), player ~= self.controller.me, action, before, self.game and ns.Director.Outcomes(self.game, before))
      end
      if self.director then
        self:PresentRemote(self.director:Plan(self.game, player, action, self.pendingBefore),
                           self.board and self.board.presentationLocked)
      end
      end)
      self.pendingBefore = nil
      if not fine and self.board then
        self.board:EndPlayAnimation()
        self.board:EndPresentation()
      end
    end,
    onRejectedAction = function()
      self.pendingBefore = nil
      if self.board then
        self.board:EndPlayAnimation()
        self.board:EndPresentation()
      end
    end,
  })
  --[[ Who they are is who the transport heard, never the name a challenge
       claims: Block, the decline cooldown and the pop-up all key on this. ]]
  session.peer.name = peerName
  self.session = session
  return self.session
end

--[[ The deck this character duels with. Until the deck builder exists this is
     the Basic deck for the class, built from printed data -- a legal, playable
     deck for all nine classes that cannot drift from the pin. ]]
--[[ The deck this character duels with: the chosen deck if it is still legal,
     otherwise the Basic deck for the class.

     The fallback is not a nicety. A deck can stop being legal after it was
     built -- a card disenchanted out from under it -- and a duel that refuses
     to start because of it would be a far worse experience than one that starts
     with the starter deck and says so. ]]
function Main:CurrentDeck(class)
  if not class then local _, c = UnitClass("player"); class = c end
  class = class or "MAGE"
  if self.collection then
    local deck, broken = self.collection:ActiveDeck()
    if deck then return deck.cards end
    if broken then
      self:Print(("your deck \"%s\" is no longer legal -- duelling with the Basic deck.")
                 :format(tostring(broken.name)))
    end
  end
  return ns.Controller.BasicDeck(class)
end

--[[ Challenge whoever is targeted (or a named character).

     The range check is a real gate, not a courtesy: the brief's duel happens
     between two people near each other in the world. What it CANNOT check is
     whether they are sitting -- there is no such API -- so that is a prompt and
     the players police it, which is the honest version of the rule. ]]
local function sameCharacter(a, b)
  local function short(n) return (tostring(n or ""):lower():gsub("%-.*$", "")) end
  return short(a) ~= "" and short(a) == short(b)
end

--[[ PROXIMITY, ON EVERY PATH. Duels are only between players standing next to
     each other, however the challenge starts -- the target, /fh duel Name, the
     right-click menu, a rematch -- and however it is answered.

     Range needs a unit token (CheckInteractDistance cannot take a name), so the
     other player has to be one: your target, focus or mouseover, in your party
     or raid, or showing a nameplate. Someone who is none of those is not
     somewhere this client can see, and "target them" is the way forward.

     The character GUID is tried before the name. Forever characters have a
     first and last name, and the name a challenge arrives under need not be
     the one UnitName shows for the character beside you -- so matching by
     name alone turned away a player you were targeting. ]]
function Main:FindPlayerUnit(name, guid)
  if guid == "" then guid = nil end
  if (not name or name == "") and not guid then return nil end
  local units = { "target", "focus", "mouseover", "targettarget", "focustarget" }
  for i = 1, 4 do units[#units + 1] = "party" .. i end
  for i = 1, 40 do units[#units + 1] = "raid" .. i end
  for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
  if C_NamePlate and C_NamePlate.GetNamePlates then
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if ok and plates then
      for _, plate in ipairs(plates) do
        if plate.namePlateUnitToken then units[#units+1] = plate.namePlateUnitToken end
      end
    end
  end
  for _, unit in ipairs(units) do
    -- ns.Plain: in instances another player's name can be secret (Rewards.lua)
    if UnitExists(unit) and ns.Plain(UnitIsPlayer(unit)) then
      if guid and ns.Plain(UnitGUID(unit)) == guid then return unit end
      local n, realm = UnitName(unit)
      n, realm = ns.Plain(n), ns.Plain(realm)
      if n and name then
        -- the second value is a realm elsewhere, a last name on Forever: try both
        if ns.Transport.SameName(n, name) then return unit end
        if realm and realm ~= "" and ns.Transport.SameName(n .. "-" .. realm, name) then return unit end
        -- typed as Forever shows it: "First Last"
        if realm and realm ~= "" and ns.Transport.SameName(n .. " " .. realm, name) then return unit end
      end
    end
  end
  return nil
end

function Main:WorldPosition()
  if not UnitPosition then return nil end
  local ok, x, y, z, instance = pcall(UnitPosition,"player")
  if not ok or type(x)~="number" or type(y)~="number" or type(z)~="number" or type(instance)~="number" then return nil end
  for _,v in ipairs({x,y,z,instance}) do
    if issecretvalue and issecretvalue(v) then return nil end
    if v ~= v or math.abs(v)>1e7 then return nil end
  end
  return {x=x,y=y,z=z,instance=instance}
end

--- Is `name` close enough to sit down with? Returns ok, the reason if not.
function Main:NearEnough(name, guid)
  local s = self.session
  -- the player we are in a session with sent their GUID in their HELLO
  if not guid and s and ns.Transport.SameName(s.peer.name, name) then guid = s.peer.guid end
  local unit = self:FindPlayerUnit(name, guid)
  if not unit then
    local here = self:WorldPosition()
    local there = s and ns.Transport.SameName(s.peer.name,name) and s.peer.position
    if s and s.state == ns.Session.STATE.INVITED and here and there
       and (s.clock or 0) - there.at <= 5 then
      local d2 = (here.x-there.x)^2 + (here.y-there.y)^2 + (here.z-there.z)^2
      if here.instance == there.instance and d2 <= ns.Transport.DUEL_RANGE_YARDS^2 then return true end
      return false, "too far away to sit down together"
    end
    return false, ("can't find %s nearby -- stand next to them and target them"):format(tostring(name))
  end
  local ok, why = ns.Transport.InRange(unit)
  if not ok then return false, why or "too far away to sit down together" end
  return true
end

--- `unit` and `guid` come from a right-click menu: the unit it was opened on
--- is the player, whatever name the menu carries.
function Main:Challenge(name, unit, guid)
  if self.session and self.session:IsActive() then
    local why = "you are already in a duel. /fh concede to leave it."
    self:Print(why)
    return false, why
  end
  if unit and not (UnitExists(unit) and ns.Plain(UnitIsPlayer(unit))) then unit = nil end
  if name and not unit then
    local near, why = self:NearEnough(name, guid)
    if not near then self:Print(why); return false, why end
  else
    unit = unit or "target"
    local ok, why = ns.Transport.InRange(unit)
    if not ok then self:Print(why or "no target"); return false, why or "no target" end
    --[[ Whisper the name the game shows for that unit: it is what /fh duel
         has always sent to, and it reaches Forever's first-and-last names. ]]
    local realm
    local shown, shownRealm = UnitName(unit)
    shown, shownRealm = ns.Plain(shown), ns.Plain(shownRealm)
    if shown then name, realm = shown, shownRealm end
    if not name then self:Print("no target"); return false, "no target" end
    -- a player from another realm is whispered as Name-Realm, or not at all
    if realm and realm ~= "" then name = name .. "-" .. realm end
  end
  --[[ Challenging the player who is already challenging you is answering
       them. Starting a second challenge instead threw theirs away and, once
       the two crossed, left both clients thinking they were player 1. ]]
  local s = self.session
  local sameGuid = unit and s and s.peer.guid and s.peer.guid ~= ""
                   and ns.Plain(UnitGUID(unit)) == s.peer.guid
  if s and s.state == ns.Session.STATE.INVITED and (sameGuid or sameCharacter(s.peer.name, name)) then
    self:Accept()
    return true
  end

  self:EnsureTransport():SetPeer(name)
  self.freshFrom, self.autoAccept = nil, nil   -- their reply belongs to THIS session
  local session = self:NewSession(name)
  -- who we challenged, for recognising their answer from another address
  local seen = unit or self:FindPlayerUnit(name, guid)
  session.peer.expectGuid = guid or (seen and ns.Plain(UnitGUID(seen))) or nil
  session:Challenge(name)
  self:Debug(("challenged %s. %s"):format(name, ns.Transport.SIT_PROMPT))
  self:ShowDuelPrompt("offered", { name = name })
  return true
end

Main.REFUSAL_LINES = {
  mana = "I don't have enough mana.",
  full_board = "I can't have any more minions.",
  taunt = "A minion with Taunt is in the way.",
  target = "I can't target that.",
  cant_play = "I can't play that.",
  summon_sick = "That minion needs a turn to get ready.",
  minion_attacked = "That minion has already attacked.",
  hero_attacked = "I already attacked this turn.",
  need_weapon = "I need a weapon to attack.",
  generic = "I can't do that.",
}
-- clicks that did nothing, which a player does not need explained
Main.QUIET_REFUSALS = { ["not your turn"] = true, ["nothing selected"] = true, ["no game"] = true,
                        ["no intent"] = true, ["animation in progress"] = true }

--[[ THE MENU'S DUEL. Duelling is the point of the addon, and it lived only in
     /fh duel and a portrait's right-click menu. With a player targeted this
     challenges them; otherwise -- or when they are out of reach -- it says how,
     on the window, where chat behind it would not be seen. ]]
function Main:DuelFromMenu()
  local hint = "Stand next to another player who has Forever Hearthstone, target them, then press Duel a Player.\n\nYou can also right-click their portrait and choose Challenge to Hearthstone."
  local targeted = UnitExists and UnitExists("target") and ns.Plain(UnitIsPlayer("target"))
                   and not (UnitIsUnit and ns.Plain(UnitIsUnit("target", "player")))
  local ok, why = false, nil
  if targeted then ok, why = self:Challenge() end
  if ok then return true end
  local hub = self.hub
  if not hub then return false end
  local d = self.duelHint
  if not d then
    d = ns.Widgets.Dialog(hub, nil, { { "OK", function() d:Hide() end } }, { paper = true, h = 250 })
    -- never left armed under the hub for its next opening (over the deck picker)
    hub:HookScript("OnHide", function() d:Hide() end)
    self.duelHint = d
  end
  local reason = why and (tostring(why):gsub("%.$", ""))
  d.message:SetText(targeted and reason and (("Could not challenge them: %s.\n\n"):format(reason) .. hint) or hint)
  d:Show()
  return false
end

function Main:Accept()
  if not self.session then self:HideDuelPrompt(); self:Print("nobody has challenged you."); return end
  if self.session.state ~= ns.Session.STATE.INVITED then
    self:Print("There is no pending invitation to accept.")
    return false
  end
  -- the one who answers must be beside the challenger too; the pop-up stays up
  local near, whyFar = self:NearEnough(self.session.peer.name)
  if not near then self:Print(whyFar); return false end
  self:HideDuelPrompt()
  local ok, why = self.session:Accept()
  if not ok then self:Print(why) end
  return ok and true or false
end

function Main:Decline()
  local s = self.session
  if not s then self:HideDuelPrompt(); return end
  if s.state == ns.Session.STATE.INVITED then s:Decline("declined")
  elseif s.state == ns.Session.STATE.OFFERED then s:Cancel()
  elseif s.state == ns.Session.STATE.SYNC then s:Leave("declined")
  else self:Print("Use Concede to leave a game in progress."); return end
  self:HideDuelPrompt()
  self.session = nil
  if self.transport then self.transport:SetPeer(nil) end
end

--[[ NOT BEING SPAMMED. Anyone standing next to you can challenge you, which is
     the point -- and, for a streamer with a crowd, the problem. So:

       * WHO MAY CHALLENGE YOU: anyone (the default), friends and group only
         (WoW friends, Battle.net friends, your guild, your party or raid), or
         nobody. /fh challenges, or the button on the main menu.
       * BLOCK: the challenge pop-up's Block button, /fh block Name. Saved for
         the account; /fh unblock Name undoes it. WoW's own ignore list counts
         as blocked too.
       * DECLINING ends this invitation; the player may challenge again.
         Block is the explicit choice to prevent future invitations.
       * ONE AT A TIME: while a challenge is on screen, nobody else's can
         arrive (the transport listens only to that player).

     Refused challenges receive a decline so the challenger can close the prompt. ]]
Main.CHALLENGE_POLICIES = { "anyone", "friends", "nobody" }
Main.CHALLENGE_POLICY_LABEL = { anyone = "Anyone", friends = "Friends & group", nobody = "Nobody" }
Main.DECLINE_COOLDOWN, Main.DECLINES_TO_SILENCE = 120, 3

local function shortName(name) return (tostring(name or ""):lower():gsub("%-.*$", "")) end

function Main:DuelPrivacy()
  ForeverHearthstoneDB = ForeverHearthstoneDB or {}
  local p = ForeverHearthstoneDB.duelPrivacy or {}
  ForeverHearthstoneDB.duelPrivacy = p
  p.policy = p.policy or "anyone"
  p.blocked = p.blocked or {}
  return p
end

function Main:SetChallengePolicy(policy)
  local valid = false
  for _, v in ipairs(Main.CHALLENGE_POLICIES) do if v == policy then valid = true end end
  if not valid then return false end
  self:DuelPrivacy().policy = policy
  if self.session and self.session.state == ns.Session.STATE.INVITED
     and not self:AllowChallengeFrom(self.session.peer.name, self.session.peer.guid) then
    self:Decline()
  end
  self:Print(("challenges: %s."):format(({ anyone = "anyone nearby may challenge you",
    friends = "only friends, guildmates and your group may challenge you",
    nobody = "nobody can challenge you -- you can still challenge others" })[policy]))
  if self.hub and self.hub:IsShown() then self.hub:Layout() end
  return true
end

function Main:IsBlocked(name)
  local key = shortName(name)
  if key == "" then return false end
  if self:DuelPrivacy().blocked[key] then return true end
  if self.silenced and self.silenced[key] then return true end
  if C_FriendList and C_FriendList.IsIgnored then
    local ok, ignored = pcall(C_FriendList.IsIgnored, name)
    if ok and ignored then return true end
  end
  return false
end

function Main:Block(name)
  local key = shortName(name)
  if key == "" then self:Print("block whom? /fh block Name"); return end
  self:DuelPrivacy().blocked[key] = name
  self:Print(("%s can no longer challenge you. /fh unblock %s to undo."):format(name, name))
  local s = self.session
  if s and s.state == ns.Session.STATE.INVITED and shortName(s.peer.name) == key then self:Decline() end
end

function Main:Unblock(name)
  local key = shortName(name)
  local blocked = self:DuelPrivacy().blocked
  if not blocked[key] and not (self.silenced and self.silenced[key]) then
    self:Print(("%s was not blocked."):format(tostring(name))); return
  end
  blocked[key] = nil
  if self.silenced then self.silenced[key] = nil end
  if self.declines then self.declines[key] = nil end
  if self.declinedAt then self.declinedAt[key] = nil end
  self:Print(self:IsBlocked(name)
    and ("%s is unblocked here, but still on your WoW ignore list."):format(tostring(name))
    or ("%s is unblocked. Your challenge policy still applies."):format(tostring(name)))
end

--- Friends, Battle.net friends, guildmates and your party or raid.
function Main:IsFriendly(name, guid)
  local function try(fn, ...)
    if not fn then return false end
    local ok, v = pcall(fn, ...)
    return ok and v and true or false
  end
  --[[ The GUID came in the challenge itself, so it is only their say-so. It is
       used only when WoW's own record of that GUID names the sender --
       otherwise copying a friend's GUID would walk straight past this. ]]
  if guid and guid ~= "" then
    local ok, _, _, _, _, _, gname = pcall(rawget(_G, "GetPlayerInfoByGUID") or function() end, guid)
    if not (ok and gname and shortName(gname) == shortName(name)) then guid = nil end
  end
  if guid and guid ~= "" then
    if C_FriendList and try(C_FriendList.IsFriend, guid) then return true end
    if C_BattleNet and try(C_BattleNet.GetAccountInfoByGUID, guid) then return true end
    if try(rawget(_G, "IsGuildMember"), guid) then return true end
  end
  if try(rawget(_G, "UnitInParty"), name) or try(rawget(_G, "UnitInRaid"), name) then return true end
  local short = shortName(name)
  if short ~= "" and try(rawget(_G, "UnitInParty"), short) then return true end
  return false
end

function Main:AllowChallengeFrom(sender, guid)
  if self:IsBlocked(sender) then return false, "blocked" end
  local key = shortName(sender)
  local at = self.declinedAt and self.declinedAt[key]
  if at and GetTime() - at < Main.DECLINE_COOLDOWN then return false, "declined recently" end
  local policy = self:DuelPrivacy().policy
  if policy == "nobody" then return false, "challenges are off" end
  if policy == "friends" and not self:IsFriendly(sender, guid) then return false, "friends only" end
  return true
end

function Main:NoteDeclined(name)
  local key = shortName(name)
  if key == "" then return end
  self.declinedAt = self.declinedAt or {}
  self.declines = self.declines or {}
  self.declinedAt[key] = GetTime()
  self.declines[key] = (self.declines[key] or 0) + 1
  if self.declines[key] >= Main.DECLINES_TO_SILENCE then
    self.silenced = self.silenced or {}
    self.silenced[key] = true
    self:Print(("%s's challenges are ignored until you log out (/fh block %s to make it permanent).")
               :format(tostring(name), tostring(name)))
  end
end

--[[ The hub put aside for another screen, not closed: while it is the duel's
     deck picker, hiding it to look at your collection must not call the duel
     off (its OnHide), and the picker returns when the collection closes. ]]
function Main:SetHubAside()
  if not (self.hub and self.hub:IsShown()) then return end
  self.hubAside = true
  self.hub:Hide()
  self.hubAside = nil
end

--- Withdraw our own challenge before it is answered.
function Main:CancelChallenge()
  self:HideDuelPrompt()
  local s = self.session
  if not (s and s.state == ns.Session.STATE.OFFERED) then return end
  s:Cancel()
  self.session = nil
  if self.transport then self.transport:SetPeer(nil) end
  self:Print("challenge withdrawn.")
end

--[[ THE CHALLENGE, ON SCREEN. A challenge used to be one line of chat and a
     slash command to answer it, easily scrolled away in a busy city. It is a
     small leather panel at the top of the screen now: who is asking and
     Accept / Decline -- or, for your own challenge, who you are waiting for and
     Cancel. The slash commands still work. ]]
function Main:ShowDuelPrompt(kind, data)
  local W = ns.Widgets
  local p = self.duelPrompt
  if not p then
    p = W.MenuPanel(UIParent, "leather")
    p:SetFrameStrata("FULLSCREEN_DIALOG"); p:SetSize(380, 132)
    p:SetPoint("TOP", UIParent, "TOP", 0, -140)
    p:EnableMouse(true); p:SetMovable(true); p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", function() p:StartMoving() end)
    p:SetScript("OnDragStop", function() p:StopMovingOrSizing() end)
    p.message = W.StyledText(p, "dialog")
    p.message:SetSize(340, 58); p.message:SetPoint("TOP", p, "TOP", 0, -16)
    p.message:SetJustifyH("CENTER"); p.message:SetJustifyV("MIDDLE"); p.message:SetWordWrap(true)
    p.yes = W.MenuButton(p, "Accept", function() p.onYes() end)
    p.no = W.MenuButton(p, "Decline", function() p.onNo() end)
    -- decline AND never hear from them again (Main:Block)
    p.block = W.MenuButton(p, "Block", function()
      local s = self.session
      local who = s and s.peer and s.peer.name
      self:Decline()
      if who then self:Block(who) end
    end)
    for _, b in ipairs({ p.yes, p.no, p.block }) do b:SetSize(112, 36); b:SetFrameLevel(p:GetFrameLevel() + 5) end
    W.LayoutMenuPanel(p)
    self.duelPrompt = p
  end
  local who = tostring(data and data.name or "Someone")
  p.yes:ClearAllPoints(); p.no:ClearAllPoints(); p.block:ClearAllPoints()
  if kind == "invited" then
    local class = data and data.class and (tostring(data.class):sub(1, 1) .. tostring(data.class):sub(2):lower()) or nil
    p.message:SetText(("%s%s challenges you to Hearthstone!"):format(who, class and (" (" .. class .. ")") or ""))
    p.yes.text:SetText("Accept"); p.no.text:SetText("Decline")
    p.onYes = function() self:Accept() end
    p.onNo = function() self:Decline() end
    p.no:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
    p.yes:SetPoint("RIGHT", p.no, "LEFT", -8, 0); p.yes:Show()
    p.block:SetPoint("LEFT", p.no, "RIGHT", 8, 0); p.block:Show()
    ns.Sounds.Play("menu_open")
  else
    p.message:SetText(("Waiting for %s to accept your challenge..."):format(who))
    p.no.text:SetText("Cancel")
    p.onNo = function() self:CancelChallenge() end
    p.yes:Hide(); p.block:Hide()
    p.no:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
  end
  p.kind = kind
  p:Show()
end

function Main:ShowDuelDeckPicker()
  local s = self.session
  if not s or s.state ~= ns.Session.STATE.SYNC or s.committed then return end
  self:ShowHub()
  local f = self.hub
  f.duelSession=s
  f.botMode, f.chooseDeck, f.selectedDeck = true, true, false
  f.selectedClass=s.peer.class or "MAGE"
  f.deckPage, f.deckOpenedAt=1,GetTime()
  self.duelDeckPicker=f
  f:Layout()
end

function Main:HideDuelPrompt()
  if self.duelPrompt then self.duelPrompt:Hide() end
  --[[ The hub is only the duel's deck picker while a duel is choosing decks.
       Keyed on that, not on having once been it: after the first duel every
       decline elsewhere closed the main menu under the player. ]]
  local f = self.duelDeckPicker
  if f and f.duelSession then f:Hide(); f.duelSession=false; f.botMode=false end
  self.duelDeckPicker = nil
end

--[[ Everything the duel can tell us. This is the whole UI of networking: a
     handful of lines of chat, because the board itself does not change -- it is
     rendering a game, and a game is a game whoever takes the other turns. ]]
function Main:OnSessionEvent(event, data)
  if event == "CHALLENGED" and self.pendingAutoAccept then
    -- The rematch both players already agreed to: no second question --
    -- unless they have walked off, when it is asked like any challenge.
    self.pendingAutoAccept = nil
    if not self:Accept() then self:ShowDuelPrompt("invited", data) end

  elseif event == "CHALLENGED" then
    self:Debug(("%s (%s) challenges you to Hearthstone. /fh accept or /fh decline.")
               :format(tostring(data.name), tostring(data.class)))
    self:ShowDuelPrompt("invited", data)

  elseif event == "ACCEPTED" then
    self:HideDuelPrompt()
    self:ShowDuelDeckPicker()
    if data.crossed then
      self:Debug(("you and %s challenged each other -- the duel is on."):format(tostring(data.name)))
    else
      self:Debug(("%s accepted."):format(tostring(data.name)))
    end

  elseif event == "DECLINED" then
    self:HideDuelPrompt()
    local who = tostring(self.session and self.session.peer.name or "they")
    if data.reason == "noaddon" then self:Print(("Could not challenge %s: no response from the Forever Hearthstone addon. They may not have it installed or enabled."):format(who))
    elseif data.reason == "cancelled" then self:Print(("%s withdrew the challenge."):format(who))
    elseif data.reason == "version" then self:Print(("%s cannot duel you: your addon versions differ."):format(who))
    else self:Print(("%s declined."):format(who)) end
    self.session = nil
    if self.transport then self.transport:SetPeer(nil) end

  elseif event == "START" then
    self:HideDuelPrompt()
    self:BeginDuel(data)

  elseif event == "RESYNCING" then
    self:Print("the two games disagree -- putting them back in step from the challenger's game...")

  elseif event == "RESYNCED" then
    self:BeginDuel(data)

  elseif event == "REMOTE_ACTION" then
    if self.controller then self.controller:Changed() end
    self:SyncMusic()

  elseif event == "PROFILE" then
    self:RefreshProfiles()

  elseif event == "EMOTE" then
    local index = tonumber(data.index)
    local label = ns.Board.EMOTES[index]
    if label and self.board and not self.board.squelched then
      -- Their character emotes (and speaks) in the world; this is the bubble.
      self.board:ShowSpeech("foe", label)
    end

  elseif event == "HOVER" then
    if self.board then self.board:SetOpponentHover(data.handIndex, data.sourceId, data.targetId) end
  elseif event == "PAUSED" then
    self:Print(data.who == "peer"
      and ("your opponent %s -- the duel is paused"):format(Main.AWAY_TEXT[data.reason] or "stepped away")
      or "you stepped away -- the duel is paused")
    self:UpdateTableStatus()

  elseif event == "RESUMED" then
    self:Print("the duel resumes.")
    self:UpdateTableStatus()

  elseif event == "CONNECTION_PROBLEM" then
    self:Print(("no word from %s -- the duel is paused while they reconnect."):format(tostring(data.name)))
    self:UpdateTableStatus()

  elseif event == "CONNECTION_RESTORED" then
    self:Print(data.rejoined and "your opponent is back -- the duel continues." or "connection restored.")
    self:UpdateTableStatus()

  elseif event == "TIMED_OUT" then
    self:Print("you were away from the table too long -- the duel is forfeited.")

  elseif event == "STALL_CLEARED" then
    self:UpdateTableStatus()

  elseif event == "STALLING" then
    self:Print(("%s has run far past the rope. Press Claim Victory on the board to take the win."):format(tostring(data.name)))
    self:UpdateTableStatus()

  elseif event == "OVER" then
    if ForeverHearthstoneCharDB then ForeverHearthstoneCharDB.activeDuel = nil end
    if self.exitDialog then self.exitDialog:Hide() end
    if self.endDuelDialog then self.endDuelDialog:Hide() end
    if self.concedeDialog then self.concedeDialog:Hide() end
    if self.board then self.board:ShowStatus(nil) end   -- nobody is away from a finished game
    self:Music(nil)
    self:Print((data.winner == data.me) and "you win." or "you lose.")
    -- The duel record, once per game. Practice games do not count.
    local session = self.session
    if session and not session.recorded and data.winner and data.winner ~= 0 then
      session.recorded = true
      local record = self:Record()
      if data.winner == data.me then record.wins = record.wins + 1
      else record.losses = record.losses + 1 end
      session:Send(ns.Protocol.KIND.PROFILE, UnitLevel("player"), UnitGUID("player") or "",
                   record.wins, record.losses)
    end
    -- under the result: why it ended, if it was not played out, and the record
    if self.board then
      local record = self:Record()
      self.board.postGameNote = ((self.resultReason and (self.resultReason .. "  ")) or "")
        .. ("Duel record: %d-%d"):format(record.wins, record.losses)
      if self.board.postGameState == "ready" then self.board:SetPostGame("ready") end
    end
    self.resultReason = nil
    self.freshFrom = self.transport and self.transport.peer
    if self.controller then self.controller:Changed() end
    self:RefreshProfiles()

  elseif event == "REMATCH_ASKED" then
    self:Print(("%s would like a rematch."):format(tostring(data.name)))
    if self.board then self.board:SetPostGame("invited", data.name) end

  elseif event == "REMATCH_DECLINED" then
    self:Print(("%s declined the rematch."):format(tostring(data.name)))
    if self.board then self.board:SetPostGame("declined", data.name) end

  elseif event == "REMATCH_START" then
    if self.board then self.board:SetPostGame("starting", data.name) end
    local peer = self.transport and self.transport.peer
    if data.challenger then
      -- Same roles as the first game: the original challenger asks again.
      self:Challenge(peer)
    else
      self.freshFrom, self.autoAccept = peer, true
    end

  elseif event == "FORFEIT" then
    local who = tostring(self.session and self.session.peer.name or "Your opponent")
    if data.by == "me" then
      self:Print("your opponent claimed the win.")
      self.resultReason = who .. " claimed the win."
    elseif data.claimed then
      local why = tostring(data.reason or "they are gone")
      self:Print(("%s -- you win."):format(why))
      self.resultReason = (why:gsub("^%l", string.upper)) .. "."
    else
      self:Print("your opponent left the duel -- you win.")
      self.resultReason = who .. " left the duel."
    end
    if self.board then self.board:ShowStatus(nil) end

  elseif event == "END_SENT" then
    self:Print("End-duel request sent. Keep playing until your opponent agrees.")
  elseif event == "END_ASKED" then
    local d=self.endDuelDialog
    if not d then
      d=ns.Widgets.Dialog(self.board.frame,nil,{
        {"Agree to End",function() d:Hide(); if self.session==d.session then d.session:AnswerEndDuel(true) end end},
        {"Keep Playing",function() d:Hide(); if self.session==d.session then d.session:AnswerEndDuel(false) end end},
      })
      self.endDuelDialog=d
    end
    d.session=self.session
    d.message:SetText(tostring(data.name).." asks to end the duel.\n\nNo win, loss or forfeit. End only if you agree.")
    d:Show()
  elseif event == "END_DECLINED" then
    self:Print("Your opponent wants to keep playing. You can ask again in 2 minutes.")
  elseif event == "ABORTED" then
    self:HideDuelPrompt()
    if ForeverHearthstoneCharDB then ForeverHearthstoneCharDB.activeDuel = nil end
    --[[ Say what happened AND what it means. "desync" on its own is a word
         nobody outside this project can act on. ]]
    --[[ Only a duel that is ON THE TABLE takes the table down with it. A
         challenge that failed before it started (a stranger's wrong version,
         a setup that timed out) used to stop whatever was being played --
         a practice game left frozen, its controller gone. ]]
    local owned = self.mode == "duel" and self.session and self.game ~= nil
                  and self.session.game == self.game
    if not owned then
      self:Print("the duel could not start: " .. tostring(data.detail or data.reason))
      self.session = nil
      if self.transport then self.transport:SetPeer(nil) end
      return
    end
    self:Print(data.reason == "agreed" and "the duel ended by agreement -- nothing recorded."
               or ("the duel ended: " .. tostring(data.detail or data.reason)))
    self:StopDirector()
    self.controller=nil; self.running={}
    -- queued animations of a duel that is over would play on its board
    self.presentQueue, self.presentBusy = {}, false
    if self.fxFrame then self.fxFrame:SetScript("OnUpdate",nil) end
    if self.exitDialog then self.exitDialog:Hide() end
    if self.endDuelDialog then self.endDuelDialog:Hide() end
    if self.concedeDialog then self.concedeDialog:Hide() end
    self:Music(nil)
    if self.board then
      --[[ Nothing is coming to finish what was on screen: the rope, a locked
           presentation and anything an animation left half-done all go, and
           the board says why it stopped. ]]
      self.board:ClearRope()
      self.board:ShowStatus(nil)   -- a pause notice must not outlive the duel
      self.board:EndPresentation()
      ns.Widgets.StopShake(self.board.shake)
      ns.Widgets.SetVignette(self.board.vignette, 0)
      self.board.concede:Hide()
      self.board:ShowSpeech("foe",data.reason=="agreed" and "Duel ended by agreement" or "Duel interrupted")
      --[[ An agreed end is a decision both players made, not a fault: say so
           on the table, then take both back to the menu. ]]
      if data.reason=="agreed" then
        local d=self.agreedDialog
        if not d then
          d=ns.Widgets.Dialog(self.board.frame,nil,{
            {"Back to Menu",function() d:Hide(); self:LeaveGame() end},
          },{paper=true})
          -- closing the board any other way must not leave it up for the next match
          self.board.frame:HookScript("OnHide",function() d:Hide() end)
          self.agreedDialog=d
        end
        d.message:SetText("You both agreed to end the duel.\n\nNo win, loss or forfeit was recorded.")
        d:Show()
      end
    end
    self.session = nil
    if self.transport then self.transport:SetPeer(nil) end
  end
end

function Main:BeginDuel(data)
  self.freshFrom, self.autoAccept, self.pendingAutoAccept = nil, nil, nil
  self.rejoinOffer = nil   -- an offer from before this duel is not about it
  if self.agreedDialog then self.agreedDialog:Hide() end   -- the last duel's ending is not this one's
  self.resultReason = nil
  if self.board and not data.resumed then self.board.squelched = nil end   -- a new opponent is heard
  if not data.resumed then self.tableAnchor = nil end
  -- a notice left from the last duel ("you left the table") is not about this one
  if self.board then self.board:ShowStatus(nil) end
  self.running = {}
  self.presentQueue, self.presentBusy = {}, false
  if self.fxFrame then self.fxFrame:SetScript("OnUpdate", nil) end
  if self.board then self.board:ResetMatch() end
  self.game = data.game
  self.mode = "duel"
  self.lastEmote=nil
  self:StartDirector(data.game, data.me)
  local session = self.session
  self.controller = ns.Controller.New({
    game   = data.game,
    player = data.me,
    --[[ THE ONE LINE THAT MAKES IT A DUEL. Every decided action goes to the
         session, which applies it here and sends it there. ]]
    submit = function(action)
      if self.board and self.board.presentationLocked then return false, "animation in progress" end
      return session:LocalAction(action)
    end,
    onChange = function(snap)
      if self.board then self.board:SetSnapshot(snap) end
    end,
  })
  if not self.board then
    self.board = ns.Board.Create({
      resolver = self.resolver,
      onIntent = function(intent) self:OnIntent(intent) end,
      onToggleMute = function() self:ToggleMute() end,
      onRematch = function() self:Rematch() end,
      onDeclineRematch = function() self:DeclineRematch() end,
      onLeave = function() self:LeaveGame() end,
      onClose = function() self:RequestDuelExit() end,
      onConcede = function() self:ConfirmConcede() end,
      -- in a duel, what you hold up and aim at is shown to the opponent
      onHover = function(hand, src, dst)
        if self.mode == "duel" and self.session then
          self.session:SendHover(hand, src, dst)
        end
      end,
    })
  end
  self:WatchBoard()
  --[[ Both clients derive the board from the match's agreed seed, so the two
       players are sitting at the same table. ]]
  self.board:SetBoardArt(data.game and data.game.seed)
  self.board:PrefetchArt(self:MatchArtIds(data.game))
  self:RefreshProfiles()
  self.board:Show()
  self.controller:Changed()
  self:SyncMusic()
  if data.resumed then
    -- a resync or a rejoin: the same match, rebuilt; no introductions
    self:Print("the duel is back in step -- play on.")
    return
  end
  --[[ Remember the open duel, so that after a /reload (which writes this to
       disk) a rejoin offer from the same opponent is accepted by itself. ]]
  if ForeverHearthstoneCharDB then
    ForeverHearthstoneCharDB.activeDuel = { peer = data.peer and data.peer.name, at = time and time() or 0 }
  end
  self:PlayOpeningLines(data.me)
  self:Debug("mulligan: click the cards you want to replace, then confirm.")
  self:Debug(("duel started against %s. %s goes first.")
             :format(tostring(data.peer and data.peer.name or "?"),
                     data.first == data.me and "you" or "they"))
end

-- ================================================= staying at the table

--[[ Main watches the WORLD; the session owns the rules (grace periods, the
     forfeit, the claim). You are away from the table if you are dead, in
     combat, or more than TABLE_RANGE yards from where you sat down -- your
     OWN movement, measured against your own starting spot, so it needs no
     report from the other player and works anywhere UnitPosition answers
     (it does not in instances, where only death and combat count). ]]
Main.TABLE_RANGE, Main.TABLE_RETURN = 30, 25
function Main:TableTick(dt)
  self.tableAge = (self.tableAge or 0) + (dt or 0)
  if self.tableAge < 1 then return end
  self.tableAge = 0
  self:CheckTable()
end

function Main:WhyAway()
  if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return "dead" end
  if (UnitAffectingCombat and UnitAffectingCombat("player")) then return "combat" end
  local y, x, z, map = nil, nil, nil, nil
  if UnitPosition then y, x, z, map = UnitPosition("player") end
  -- in an instance the position can be secret: unknown, so only death and combat count
  y, x, map = ns.Plain(y), ns.Plain(x), ns.Plain(map)
  local current = self.session and self.session.paused and self.session.paused.me
  local inside = IsInInstance and ns.Plain(IsInInstance()) and true or false
  if self.tableAnchor and self.tableAnchor.inside == false and inside then
    -- sat down in the open world and zoned into a dungeon: that is leaving
    return "away"
  end
  if type(y) == "number" and type(x) == "number" then
    if not self.tableAnchor then self.tableAnchor = { x = x, y = y, map = map, inside = inside } end
    -- another continent or instance: its coordinates are another frame entirely
    if self.tableAnchor.map and map and map ~= self.tableAnchor.map then return "away" end
    local d = math.sqrt((x - self.tableAnchor.x) ^ 2 + (y - self.tableAnchor.y) ^ 2)
    if d > Main.TABLE_RANGE or (current == "away" and d > Main.TABLE_RETURN) then return "away" end
  elseif current == "away" then
    return "away"   -- nothing says they came back, so they have not
  end
  return nil
end

function Main:CheckTable()
  local s = self.mode == "duel" and self.session
  if not (s and s.state == ns.Session.STATE.PLAYING) then return end
  local want = self:WhyAway()
  local current = s.paused and s.paused.me
  if want and want ~= current then
    s:Pause(want)
    self:UpdateTableStatus()
  elseif not want and current and current ~= "left" then
    s:Resume()
    self:UpdateTableStatus()
  end
end

Main.AWAY_TEXT = { away = "left the table", combat = "is in combat", dead = "has died",
                   left = "left the game" }
function Main:UpdateTableStatus()
  local s = self.session
  if not (self.board and s) then return end
  local p = s.paused
  local text, action
  if p and p.me then
    local what = (Main.AWAY_TEXT[p.me] or "left the table"):gsub("^is ", "are ")
    what = what:gsub("^has ", "have ")
    text = ("You %s -- come back within %d seconds or forfeit"):format(what, s:Grace(p.me))
  elseif p and p.peer then
    text = ("%s %s -- the duel is paused"):format(tostring(s.peer.name or "Your opponent"),
      Main.AWAY_TEXT[p.peer] or "stepped away")
  elseif s.connectionProblem then
    text = ("Connection problem with %s -- waiting..."):format(tostring(s.peer.name or "your opponent"))
  elseif s.stalling then
    text = ("%s's turn is long overdue. You can claim the win."):format(tostring(s.peer.name or "Your opponent"))
    action = { label = "Claim Victory", onClick = function()
      local ok, why
      if self.session then ok, why = self.session:ClaimVictory() end
      if not ok and why then self:Print("you cannot claim the win: " .. tostring(why)) end
    end }
  end
  self.board:ShowStatus(text, action)
end

--[[ A REJOIN OFFER from someone we are not talking to: our duel with them
     survived our reload or disconnect on their side. Accepted by itself if it
     is the duel we remember being in (written to disk on /reload); otherwise
     the player is asked. ]]
function Main:OnRejoinOffer(sender)
  local open = ForeverHearthstoneCharDB and ForeverHearthstoneCharDB.activeDuel
  --[[ The other side gives up on a silent duel after Session.ABANDON_AFTER, so
       a remembered duel older than twice that is gone: forget it rather than
       walking back into it the next time that player happens to be nearby. ]]
  if open and time and (time() - (open.at or 0)) > 2 * ns.Session.ABANDON_AFTER then
    ForeverHearthstoneCharDB.activeDuel, open = nil, nil
  end
  --[[ The whole address, realm included: comparing only what comes before
       "-" let anyone sharing your opponent's first name pull you into a
       rejoin with them. ]]
  if open and ns.Transport.SameName(open.peer, sender) then return self:Rejoin(sender) end
  -- anyone else's offer is a stranger's message, and obeys who may challenge you
  if not self:AllowChallengeFrom(sender) then return end
  if self.rejoinOffer ~= sender then
    self.rejoinOffer = sender
    self:Print(("%s is holding your duel open. /fh resume to rejoin it."):format(tostring(sender)))
  end
end

function Main:Rejoin(sender)
  -- an old offer must not silently replace the duel being played now
  if self.session and self.session:IsActive() then
    self:Print("you are already in a duel. /fh concede to leave it first.")
    return
  end
  sender = sender or self.rejoinOffer
  if not sender then self:Print("no duel is waiting for you."); return end
  self.rejoinOffer = nil
  self:EnsureTransport()
  self:NewSession(sender)
  self.transport:SetPeer(sender)
  self.session:RequestRejoin(sender)
  self:Print(("rejoining your duel with %s..."):format(tostring(sender)))
end

function Main:RequestDuelExit()
  --[[ Closing the board outside a live duel -- a bot game, or any finished
       match -- takes you to the /fh main menu rather than leaving you in
       the world with nothing open. A bot game in progress is kept, so the
       menu's Resume Match brings it back. ]]
  if self.mode~="duel" or not self.session or self.session.state~=ns.Session.STATE.PLAYING then
    if not self.leavingToHub then self:ShowHub() end
    return
  end
  self.board:Show()
  if not self.exitDialog then
    local dialog
    dialog=ns.Widgets.Dialog(self.board.frame,"ForeverHearthstoneExitDuel",{
      {"Ask to End Duel",function()
        dialog:Hide()
        if self.session then self.session:AskEndDuel() end
      end},
      {"Keep Playing",function() dialog:Hide() end},
    })
    self.exitDialog=dialog
    dialog.confirm,dialog.cancel=dialog.buttons[1],dialog.buttons[2]
    dialog.message:SetText("Ask your opponent to end this duel?\n\nBoth players must agree. No win, loss or forfeit.\nKeep playing until they respond.")
  end
  local function refresh()
    local s=self.session
    local remaining=s and s:EndRequestRemaining() or 0
    local pending=s and s.endAsked
    self.exitDialog.confirm.text:SetText(pending and "Request Pending" or (remaining>0
      and ("Ask Again (%d:%02d)"):format(math.floor(remaining/60),remaining%60) or "Ask to End Duel"))
    self.exitDialog.confirm:SetEnabledLook(s and s.state==ns.Session.STATE.PLAYING and not pending and remaining==0)
  end
  self.exitDialog:SetScript("OnUpdate",refresh)
  self.exitDialog:SetScript("OnHide",function(d) d:SetScript("OnUpdate",nil) end)
  refresh()
  self.exitDialog:Show()
end

function Main:RefreshProfiles()
  if not self.board or not self.game then return end
  local ownClass=self:PlayerClass()
  local mine={name=UnitName("player"),level=UnitLevel("player"),unit="player",
    icon=self.resolver:Card(ns.HERO_ID_BY_CLASS[ownClass]).icon}
  local record=self:Record()
  mine.wins, mine.losses = record.wins, record.losses
  local peer
  if self.mode=="duel" and self.session then
    local remote=self.session.peer
    peer={name=remote.name,guid=remote.guid,level=remote.level,wins=remote.wins,losses=remote.losses,
      icon=self.resolver:Card(ns.HERO_ID_BY_CLASS[remote.class or "MAGE"]).icon}
    local units={"target","focus"}
    for i=1,4 do units[#units+1]="party"..i end
    for i=1,40 do units[#units+1]="raid"..i end
    -- the player beside you usually has a nameplate even when not targeted
    units[#units+1]="mouseover"
    for i=1,40 do units[#units+1]="nameplate"..i end
    for _,unit in ipairs(units) do
      if remote.guid and remote.guid~="" and UnitExists(unit) and ns.Plain(UnitGUID(unit))==remote.guid then
        peer.unit=unit; peer.level=ns.Plain(UnitLevel(unit),peer.level); break
      end
    end
  else
    local class=self.game.players[2].class
    local level=ns.AI.DIFFICULTIES[(self.botOpts and self.botOpts.difficulty) or self:BotDifficulty()]
    peer={name=class:sub(1,1)..class:sub(2):lower().." Bot",bot=true,
      botLabel=level and (level.name.." bot") or nil,
      icon=self.resolver:Card(ns.HERO_ID_BY_CLASS[class]).icon}
  end
  self.board:SetProfiles(mine,peer)
end

-- This character's duel record (real players only), saved per character.
function Main:Record()
  local ch = rawget(_G, "ForeverHearthstoneCharDB") or {}
  ch.record = ch.record or { wins = 0, losses = 0 }
  return ch.record
end

-- ...and against the practice bots, kept apart so it never pads the duel record.
function Main:PracticeRecord()
  local ch = rawget(_G, "ForeverHearthstoneCharDB") or {}
  ch.practiceRecord = ch.practiceRecord or { wins = 0, losses = 0 }
  return ch.practiceRecord
end

--[[ After the game. Practice replays the same matchup at once; a duel asks the
     other player, who sees "X would like a rematch" and may accept or decline.
     Pressing Rematch when they have already asked is accepting. ]]
function Main:Rematch()
  if self.mode == "practice" then
    local last = self.lastPractice or {}
    self:StartPractice(last.my, last.foe, last.deck, last.foeDeck, last.difficulty)
  elseif self.session then
    local ok, why = self.session:AskRematch()
    if not ok then self:Print(why); return end
    if self.board and self.session.rematch == "asked" then
      self.board:SetPostGame("asked", self.session.peer.name)
    end
  end
end

function Main:DeclineRematch()
  if self.session then self.session:AnswerRematch(false) end
  if self.board then self.board:SetPostGame("closed") end
end

function Main:LeaveGame()
  if self.session and self.session.rematch == "invited" then self.session:AnswerRematch(false) end
  --[[ Walking away from a rematch we asked for, or one agreed but never
       started, gives it up here: left settling, it turned every later
       challenger away in silence until a reload. ]]
  if self.session and (self.session.rematch == "asked" or self.session.rematch == "agreed") then
    self.session.rematch = "refused"
  end
  self.leavingToHub = true
  if self.board then self.board:Hide() end
  self.leavingToHub = false
  self:ShowHub()
end

function Main:Concede()
  if not (self.session and self.session.state == ns.Session.STATE.PLAYING) then
    -- a practice game on the board concedes like its button does
    if self.mode == "practice" and self.game and not self.game.over then return self:ConcedeMatch() end
    self:Print("no game in progress.")
    return
  end
  ns.Sounds.PlayHero(self:HeroCardId(self.controller and self.controller.me), "concede", true)
  self.session:Concede()
end

--[[ THE BOARD'S CONCEDE BUTTON: asked once, then the match is given up --
     through the session in a duel (the other client is told), straight to
     the engine against a bot. Either way it ends as a loss on the board. ]]
function Main:ConcedeMatch()
  if self.mode == "duel" then return self:Concede() end
  local g = self.game
  if not (g and not g.over and self.controller) then return end
  ns.Sounds.PlayHero(self:HeroCardId(self.controller.me), "concede", true)
  self.aiThink = nil
  local ok, why = ns.Actions.Run(g, self.controller.me, { kind = "CONCEDE" })
  if not ok then self:Print(why); return end
  self.controller:Changed()
  self:AnnounceResult()
end

function Main:ConfirmConcede()
  if not (self.board and self.game and not self.game.over) then return end
  if not self.concedeDialog then
    local dialog
    dialog = ns.Widgets.Dialog(self.board.frame, "ForeverHearthstoneConcede", {
      { "Concede", function() dialog:Hide(); self:ConcedeMatch() end },
      { "Keep Playing", function() dialog:Hide() end },
    })
    dialog.message:SetText("Concede this match?\n\nIt counts as a loss.")
    self.concedeDialog = dialog
  end
  self.concedeDialog:Show()
end


-- ========================================================= the collection

--[[ THE SAVED DATA, AND WHAT IT IS WORTH.

     Two tables, matching decision D5: the account one holds neutrals, dust and
     packs, because a WoW character is one class forever and per-character
     neutrals would make every alt re-grind the same 153 cards. The character
     one holds class cards, decks and match history.

     `schema` exists so a later change can migrate rather than guess. It is
     written on first use and checked on every load; an UNKNOWN (newer) schema
     refuses to touch the data rather than rewriting something it does not
     understand, because a downgrade that eats a collection is unforgivable and
     a downgrade that refuses to run is merely annoying. ]]
Main.SCHEMA = 1

function Main:LoadCollection()
  local db, cdb = ForeverHearthstoneDB, ForeverHearthstoneCharDB
  db.schema = tonumber(db.schema) or Main.SCHEMA
  if db.schema > Main.SCHEMA then
    self:Print(("your saved collection was written by a NEWER version (schema %d, this addon reads %d). It has been left untouched -- update the addon.")
               :format(db.schema, Main.SCHEMA))
    self.schemaLocked = true
    return nil
  end

  --[[ Open the sealed collection (Client/Vault.lua): it replaces any plain
       copy in the file, so hand-edited card counts are ignored. ]]
  if ns.Vault then
    for _, problem in ipairs(ns.Vault.Restore(db, cdb, Main.VaultSalt())) do
      self:Print(problem.unsealed
        and ("your %s collection file held cards with no seal beside them; they were set aside."):format(problem.what)
        or problem.restored
        and ("your %s collection file was modified outside the game; restored from the last good copy."):format(problem.what)
        or ("your %s collection file was modified outside the game and could not be restored."):format(problem.what))
    end
  end
  -- the character's GUID keys its pack milestones in the account file (Collection:GrantPacksForLevel)
  self.collection = ns.Collection.New(db, cdb, { characterKey = ns.Plain(UnitGUID and UnitGUID("player")) })

  --[[ Grants are a FUNCTION of level, applied on every login. A character that
       levelled with the addon disabled catches up here; one that did not gets
       nothing, because the function is idempotent. ]]
  local class = self:PlayerClass()
  local level = UnitLevel and UnitLevel("player") or 1
  local granted = self.collection:GrantForLevel(class, level)
  self.collection:EnsureDefaultDeck(class)
  -- the first login ever: what this is and how to start, before anything it was given
  if not ForeverHearthstoneDB.seenWelcome then
    ForeverHearthstoneDB.seenWelcome = true
    self:Print("welcome! Click the minimap button or type /fh to open the main menu.")
    self:Print("packs come from levelling and from killing creatures that give experience -- bosses always pay one the first time you beat them.")
    self:Print("to duel, stand next to a player who has the addon, target them and press Duel a Player.")
  end
  if #granted > 0 then
    -- said aloud: a character that levelled before installing is owed these
    self:Print(level <= 1 and ("your starting collection: %d cards. /fh collection to see them."):format(#granted)
               or ("%d new cards for reaching level %d. /fh collection to see them."):format(#granted, level))
  end
  local packs = self.collection:GrantPacksForLevel(level)
  if packs > 0 then
    self:Print(("%d Hearthstone pack%s for your character's progress. /fh open to open one.")
               :format(packs, packs == 1 and "" or "s"))
  end
  return self.collection
end

--[[ Kill detection, level grants and the unsaved-rewards warning. Everything
     it decides comes from Client/Drops.lua; this only supplies the events. ]]
function Main:StartRewards()
  if self.rewards or not self.collection then return end
  self.rewards = ns.Rewards.New({
    collection = self.collection,
    onPrint = function(msg) self:Print(msg) end,
    onReward = function(reward) self:OnReward(reward) end,
  })
  self.rewards:Start()
  local warning = self.rewards:CheckLastSession(ForeverHearthstoneDB)
  if warning then self:Print(warning) end
end

--[[ Something dropped. The toast is the CHOREOGRAPHY from Client/FX, played
     against whatever stage is available -- so the feel of a drop was designed
     and tested before any of this existed, and this only decides which sequence
     and hands it the facts. ]]
function Main:OnReward(reward)
  -- the menu's "Open Packs (N)" counts what is waiting
  if reward.kind == "PACK" and self.hub and self.hub:IsShown() then self.hub:Layout() end
  if reward.kind == "PACK" then
    self:PlayDropToast(ns.Choreography.PackDropToast, {
      set = reward.set, total = reward.total, fromLevel = reward.fromLevel, count=reward.count,
    })
    if not reward.fromLevel then
      local n = reward.total or 1
      self:Print(("pack found! %d pack%s waiting -- /fh open to open them."):format(n, n == 1 and "" or "s"))
    end
  else
    local printed = ns.PrintedCards[reward.cardId]
    local name = printed and printed.name or reward.cardId
    self:PlayDropToast(ns.Choreography.SetCardDropToast, {
      cardId = reward.cardId, golden = reward.golden, rarity = reward.rarity,
      set = reward.set, extra = reward.extra,
    })
    self:Debug(("%s%s%s"):format(reward.golden and "GOLDEN " or "", name,
               reward.extra and " (a spare -- worth dust)" or ""))
    if reward.triggered then
      for _, id in ipairs(reward.triggered) do
        local pr = ns.PrintedCards[id]
        self:Debug(("you completed a set: %s is yours."):format(pr and pr.name or id))
      end
    end
  end
end

--[[ Run a choreography against the board's stage when there is a board, and
     against nothing when there is not.

     A drop happens in the OPEN WORLD, usually mid-fight, with no card game on
     screen at all -- so "nothing" is the normal case and has to be a first-class
     one. Choreography is null-safe by construction (every stage method is
     optional), which is exactly why it can be driven from here. ]]
function Main:PlayToast(sequence, opts)
  --[[ When there IS no board -- which is the normal case for a drop, since it
       happens mid-fight out in the world -- the toast gets its own small stage
       on UIParent rather than being driven into a null object and never
       appearing at all. ]]
  --[[ Never the board's stage, even when a board exists: /fh open with a
       paused practice game behind it drove the pack animation into that
       game's hand cards and left them strewn across the table. ]]
  self:RunTimeline(sequence(self:WorldStage(), opts or {}))
end

--- The toast stage on UIParent, made once -- always with its click, whichever
--- path made it first.
function Main:WorldStage()
  if not self.worldStage then
    self.worldStage = ns.Widgets.NewToastStage(self)
    self.worldStage.toastWidget.frame:SetScript("OnClick", function()
      if self.worldStage.toastKind == "pack" then self:OpenPackRoom() end
    end)
  end
  return self.worldStage
end

--[[ A DROP'S TOAST, ON THE SCREEN. Drops always use the world stage on
     UIParent. They used to use the board's stage whenever a board existed --
     and the board is kept (hidden) after your first match, so every drop
     after that played its toast inside a hidden window and nobody saw it.

     Toasts wait their turn: a level-up that grants a pack and three class
     cards shows four toasts one after another, not one overwriting the next.
     They run on their own frame, so starting a match does not cut one off.
     Clicking a pack toast opens the pack room. ]]
Main.TOAST_GAP = 0.15
function Main:PlayDropToast(sequence, opts)
  self.toastQueue = self.toastQueue or {}
  self.toastQueue[#self.toastQueue + 1] = { sequence = sequence, opts = opts or {} }
  if not self.toastPlaying then self:NextDropToast() end
end

function Main:NextDropToast()
  local nextUp = table.remove(self.toastQueue or {}, 1)
  if not nextUp then self.toastPlaying = nil; return end
  local stage = self:WorldStage()
  stage.toastKind = nextUp.sequence == ns.Choreography.PackDropToast and "pack" or "card"
  local tl = nextUp.sequence(stage, nextUp.opts)
  if not tl then return self:NextDropToast() end
  self.toastPlaying = tl
  tl:Start()
  if not self.toastFrame then self.toastFrame = CreateFrame("Frame") end
  local gap = 0
  self.toastFrame:SetScript("OnUpdate", function(frame, dt)
    local particles = stage:Tick(dt)
    if self.toastPlaying and not self.toastPlaying:Tick(dt) then
      self.toastPlaying = false
    end
    if self.toastPlaying == false then
      gap = gap + dt
      if gap >= Main.TOAST_GAP and #(self.toastQueue or {}) > 0 then
        frame:SetScript("OnUpdate", nil); return self:NextDropToast()
      end
      if #(self.toastQueue or {}) == 0 and particles == 0 then
        self.toastPlaying = nil; frame:SetScript("OnUpdate", nil)
      end
    end
  end)
end

-- The pack room, from anywhere (the drop toast, the minimap).
function Main:OpenPackRoom()
  if not self.collection then return end
  local ok = pcall(function()
    if not self.collectionUI then self:Collection() end
    self:SetHubAside()
    self.collectionUI:Show()
    self.collectionUI:ShowPackRoom()
  end)
  if not ok then self:Print("/fh open opens a pack.") end
end

--[[ Drive a timeline off an OnUpdate. The timelines are pure data with a Tick
     function, so this is the only place in the project that needs a frame to
     make the animations move. ]]
function Main:RunTimeline(tl)
  if not tl then return end
  if not self.fxFrame then self.fxFrame = CreateFrame("Frame") end
  local running = self.running or {}
  self.running = running
  running[#running + 1] = tl
  tl:Start()
  self.fxFrame:SetScript("OnUpdate", function(_, dt)
    local alive = {}
    for _, t in ipairs(running) do
      if t:Tick(dt * (t.speed or 1)) then alive[#alive + 1] = t end
    end
    self.running = alive
    running = alive
    local particles = self.worldStage and self.worldStage:Tick(dt) or 0
    if #alive == 0 and particles == 0 then self.fxFrame:SetScript("OnUpdate", nil) end
  end)
end

--[[ Open one banked pack, reveal it, and bank the cards.

     The contents are generated and stored FIRST and animated afterwards: the
     reveal is a presentation of something that has already happened, so a
     disconnect halfway through costs a pretty animation and not a pack. ]]
function Main:OpenPack(set)
  if not self.collection then self:Print("no collection loaded."); return end
  set = (set or "hearthstone"):upper()
  if not ns.Packs.SETS[set] then
    self:Print("Hearthstone packs contain Classic, GvG and Naxxramas neutral cards.")
    return
  end
  local pack, why = ns.Packs.Open(self.collection, set)
  if not pack then self:Print(why); return end
  if self.rewards then self.rewards.unsaved = self.rewards.unsaved + ns.Packs.SIZE end

  self:PlayToast(ns.Choreography.PackCrack, {
    count = #pack.cards, bestRarity = pack.bestRarity, tellIndex = pack.tellIndex,
  })
  for i, card in ipairs(pack.cards) do
    local printed = ns.PrintedCards[card.cardId]
    self:Print(("%d. %s%s%s%s"):format(i,
      card.golden and "|cffffd100GOLDEN|r " or "",
      printed and printed.name or card.cardId,
      card.rarity ~= "COMMON" and (" (" .. card.rarity:lower() .. ")") or "",
      card.dust and (" -- duplicate, turned into %d dust"):format(card.dust)
        or card.extra and " -- spare" or ""))
  end
  local triggered = ns.Packs.CheckTriggers(self.collection)
  for _, id in ipairs(triggered) do
    local pr = ns.PrintedCards[id]
    self:Print(("you completed a set: %s is yours."):format(pr and pr.name or id))
  end
end


-- ==================================================== the out-of-match app

--[[ The collection screen: browsing, the deck builder, crafting and pack
     opening, all on one window (see Client/UI/CollectionLayout.lua).

     Built on first use rather than at login. It is a large frame and most
     sessions never open it, and a frame that is never created costs nothing. ]]
function Main:Collection(openCollection)
  if not self.collection then self:Print("no collection loaded."); return end
  if not self.collectionUI then
    self.collectionUI = ns.CollectionUI.Create({
      collection = self.collection,
      resolver   = self.resolver,
      onPrint    = function(msg) self:Print(msg) end,
    })
    self.collectionUI.frame:HookScript("OnShow", function() self:SyncMusicSoon() end)
    self.collectionUI.frame:HookScript("OnHide", function()
      self:SyncMusicSoon()
      -- stepped out of the duel's deck picker to look at decks: back to it
      local s = self.session
      if s and s.state == ns.Session.STATE.SYNC and not s.committed
         and not (self.hub and self.hub:IsShown()) then
        self:ShowDuelDeckPicker()
      end
    end)
  end
  if openCollection then
    self:SetHubAside()
    self.collectionUI:StopFX()
    self.collectionUI:EditDeck(nil)
    self.collectionUI:Show()
  else self.collectionUI:Toggle() end
  return self.collectionUI
end

--[[ Open a deck for editing, creating one if the player named a new name.

     A character may keep several decks; which one it duels with is
     `activeDeck`, and it is chosen explicitly rather than being "the last one
     you touched" -- editing a deck and then discovering you duelled with it
     half-built is a bad surprise. ]]
function Main:Deck(arg)
  if not self.collection then self:Print("no collection loaded."); return end
  local decks = self.collection.character.decks
  arg = arg and arg:match("^%s*(.-)%s*$") or ""

  if arg == "" then
    if #decks == 0 then
      self:Print("no decks yet. /fh deck new <name> to start one.")
      return
    end
    for i, deck in ipairs(decks) do
      local ok = self.collection:ValidateDeck(deck)
      self:Print(("%d. %s  %d/%d  %s%s"):format(i, deck.name, #deck.cards,
        ns.RULES.DECK_SIZE, ok and "|cff55ff55legal|r" or "|cffff5555incomplete|r",
        self.collection.character.activeDeck == i and "  (duelling with this one)" or ""))
    end
    self:Print("/fh deck <n> to edit, /fh deck use <n> to duel with it.")
    return
  end

  local newName = arg:match("^new%s+(.+)$")
  if newName then
    local _, class = UnitClass("player")
    local _, index = self.collection:NewDeck(newName, class)
    self:Print(("created \"%s\". Opening the builder."):format(newName))
    self:Collection()
    if not self.collectionUI:IsShown() then self.collectionUI:Show() end
    self.collectionUI:EditDeck(index)
    return
  end

  local use = tonumber(arg:match("^use%s+(%d+)$"))
  if use then
    if not decks[use] then self:Print("no such deck."); return end
    local ok, errors = self.collection:ValidateDeck(decks[use])
    if not ok then
      self:Print(("that deck is not legal yet: %s"):format(errors[1]))
      return
    end
    self.collection.character.activeDeck = use
    self:Print(("duelling with \"%s\" from now on."):format(decks[use].name))
    return
  end

  local index = tonumber(arg)
  if index and decks[index] then
    self:Collection()
    if not self.collectionUI:IsShown() then self.collectionUI:Show() end
    self.collectionUI:EditDeck(index)
    return
  end
  self:Print("/fh deck | deck new <name> | deck <n> | deck use <n>")
end

--[[ THE ICON AUDIT.

     Every generic icon path in this addon is a CANDIDATE, because there is no
     API that can tell us whether a texture exists -- SetTexture on a bad path
     draws nothing and reports success. So the only possible verifier is an eye,
     and this is the screen that makes using one cheap: every candidate at real
     size, next to what it is for.

     Text form here; the grid is drawn by the collection window when it is open,
     which is where the icons are actually visible at size. ]]
function Main:IconAudit()
  local saved = ForeverHearthstoneDB.art or {}
  ForeverHearthstoneDB.art = saved
  local checked, total, blank = ns.GenericArt.AuditProgress(saved)
  self:Print(("icon audit: %d of %d checked, %d marked blank."):format(checked, total, blank))
  for _, entry in ipairs(ns.GenericArt.AuditList(saved)) do
    self:Print(("%s |T%s:20|t  %s%s"):format(entry.key, entry.path, entry.describe,
      entry.blank and "  |cffff5555(blank)|r" or (entry.verified and "  |cff55ff55(ok)|r" or "")))
  end
  self:Print("if a square above is empty, that icon does not exist: /fh icons blank <KEY>")
end

--[[ Record a verdict. This is the only source of truth about whether an icon
     exists, because it is the only one that involved a human looking at it. ]]
function Main:MarkIcon(key, exists)
  local saved = ForeverHearthstoneDB.art or {}
  ForeverHearthstoneDB.art = saved
  if not ns.GenericArt.CANDIDATES[key] then
    self:Print("no such icon key: " .. tostring(key))
    return
  end
  ns.GenericArt.Mark(saved, key, exists)
  --[[ Rebuild the resolver so the change takes effect without a reload. A
       blank entry is DELETED rather than replaced, so the fallback chain
       handles it -- see Client/Assets/GenericArt.lua. ]]
  self.resolver = ns.Resolver.New({
    printed  = ns.PrintedCards,
    manifest = ns.GenericArt.Manifest(saved),
    override = ForeverHearthstoneDB.assetOverrides or {},
    palette  = ns.GenericArt.Palette(),
  })
  if self.collectionUI then self.collectionUI.resolver = self.resolver end
  if self.board then self.board.resolver = self.resolver end
  self:Print(("%s marked %s."):format(key, exists and "present" or "blank"))
end

--[[ The collection as text. The real screen is Client/UI/Collection.lua; this
     stays because it works when a frame does not, and because "how far am I"
     is a question worth being able to answer from a login screen. ]]
function Main:PrintCollection()
  local c = self.collection
  if not c then self:Print("no collection loaded."); return end
  local owned, total, golden = c:Progress()
  self:Print(("collection: %d of %d cards (%d golden), %d dust")
             :format(owned, total, golden, c:Dust()))
  local packs = {}
  for set, n in pairs(c.account.packs) do
    if n > 0 then packs[#packs + 1] = ("%s x%d"):format(set:lower(), n) end
  end
  table.sort(packs)
  self:Print(#packs > 0 and ("packs: %d waiting -- /fh open"):format(c:TotalPacks())
                        or "packs: none yet. Kill things.")
  if self.rewards and self.rewards.unsaved > 0 then
    self.rewards:PrintUnsaved()
  end
end

function Main:Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff44d9e6Forever Hearthstone|r: " .. tostring(msg))
  end
end

function Main:Debug(msg)
  if ForeverHearthstoneDB and ForeverHearthstoneDB.debugMessages then self:Print(msg) end
end

function Main:Settings(view)
  local W=ns.Widgets
  ForeverHearthstoneDB=ForeverHearthstoneDB or {}
  if not self.settings then
    local d=W.Dialog(UIParent,"ForeverHearthstoneSettings",{
      {"Close",function() self.settings:Hide() end}}, {w=860,h=800,paper=true})
    self.settings=d; d:SetFrameStrata("FULLSCREEN_DIALOG")
    d.view="track"; d.page=1
    --[[ Hearthstone's parchment popup: a large inked heading, dark text. It was
         a red panel with small light WoW-style lettering (docs/39). ]]
    d.message:SetSize(790,40); W.ApplyStyle(d.message,"pageTitle",nil,26)
    d.message:SetText("Hearthstone Settings")
    d.tabs={}
    for i,spec in ipairs({{"Level Rewards","track"},{"Pack & Drop Odds","odds"},{"General","general"}}) do
      local tab=W.MenuButton(d.panel,spec[1],function() self:Settings(spec[2]) end)
      tab:SetSize(235,36); tab:SetPoint("TOP",d.panel,"TOP",(i-2)*248,-63)
      d.tabs[spec[2]]=tab
    end
    d.subtitle=W.StyledText(d.panel,"bodyInk"); d.subtitle:SetSize(790,38)
    d.subtitle:SetPoint("TOP",d.panel,"TOP",0,-108); d.subtitle:SetJustifyH("CENTER"); d.subtitle:SetWordWrap(true)
    d.body=W.StyledText(d.panel,"bodyInk"); d.body:SetSize(770,440)
    d.body:SetPoint("TOP",d.panel,"TOP",0,-163); d.body:SetJustifyH("LEFT"); d.body:SetJustifyV("TOP"); d.body:SetWordWrap(true)
    d.track=W.RewardTrack(d.panel,self.resolver,true); d.track:SetPoint("TOP",d.panel,"TOP",0,-155)
    d.trackPrev=W.MenuButton(d.panel,"< Earlier",function() d.track:Scroll(-1) end)
    d.trackNext=W.MenuButton(d.panel,"Later >",function() d.track:Scroll(1) end)
    d.current=W.MenuButton(d.panel,"Your Level",function() d.track:Scroll(d.track.current-2-d.track.first) end)
    for i,button in ipairs({d.trackPrev,d.current,d.trackNext}) do
      button:SetSize(160,32); button:SetPoint("BOTTOM",d.panel,"BOTTOM",(i-2)*245,77)
    end
    d.track.onScroll=function() d.trackPrev:SetEnabledLook(d.track.first>1); d.trackNext:SetEnabledLook(d.track.first<56) end
    d.previewDrop=W.MenuButton(d.panel,"Preview Pack Drop",function()
      d:Hide()
      self:PlayDropToast(ns.Choreography.PackDropToast, {
        set=ns.Packs.SETS.HEARTHSTONE, total=self.collection:TotalPacks(), preview=true,
      })
      self:Print("Pack drop preview - no pack was added.")
    end)
    d.previewDrop:SetSize(260,36); d.previewDrop:SetPoint("BOTTOM",d.panel,"BOTTOM",0,90)
    d.previewDrop:SetFrameLevel(d.panel:GetFrameLevel()+10)
    d.debug=W.MenuButton(d.panel,"",function()
      ForeverHearthstoneDB.debugMessages=not ForeverHearthstoneDB.debugMessages; self:Settings("general") end)
    d.debug:SetSize(380,32); d.debug:SetPoint("TOP",d.panel,"TOP",0,-170)
    d.blockTitle=W.StyledText(d.panel,"pageText"); d.blockTitle:SetSize(600,26); d.blockTitle:SetPoint("TOP",d.panel,"TOP",0,-222)
    d.rows={}
    for i=1,4 do
      local row=W.MenuButton(d.panel,"",function()
        local name=d.names[(d.page-1)*4+i]; if name then self:Unblock(name); self:Settings("general") end end)
      row:SetSize(380,32); row:SetPoint("TOP",d.panel,"TOP",0,-260-(i-1)*40); d.rows[i]=row
    end
    d.prev=W.MenuButton(d.panel,"Previous",function() d.page=d.page-1; self:Settings("general") end)
    d.next=W.MenuButton(d.panel,"Next",function() d.page=d.page+1; self:Settings("general") end)
    d.prev:SetSize(150,32); d.prev:SetPoint("TOP",d.panel,"TOP",-100,-440)
    d.next:SetSize(150,32); d.next:SetPoint("TOP",d.panel,"TOP",100,-440)
    for _,tab in pairs(d.tabs) do tab:SetFrameLevel(d.panel:GetFrameLevel()+10) end
    for _,button in ipairs({d.trackPrev,d.trackNext,d.current,d.debug,d.prev,d.next,unpack(d.rows)}) do button:SetFrameLevel(d.panel:GetFrameLevel()+10) end
  end
  local d=self.settings
  local opening=not d:IsShown() or #d.track.rows==0
  d.view=view or "general"
  local track,odds,general=d.view=="track",d.view=="odds",d.view=="general"
  d.panel:SetScale(math.max(.1,math.min(1,(UIParent:GetWidth()-32)/860,(UIParent:GetHeight()-32)/800)))
  d.message:SetText(general and "Settings" or "Progression")
  for key,tab in pairs(d.tabs) do
    tab:SetShown(not general and key~="general")
    tab:SetEnabledLook(key~=d.view)
    -- the page you are on reads as chosen, not as disabled (docs/39); the
    -- others stay clickable, a shade quieter
    tab:SetAlpha(key==d.view and 1 or .72)
    if key~="general" then
      tab:ClearAllPoints(); tab:SetPoint("TOP",d.panel,"TOP",key=="track" and -124 or 124,-63)
    end
  end
  d.track:SetShown(track); d.body:SetShown(odds)
  d.trackPrev:SetShown(track); d.trackNext:SetShown(track); d.current:SetShown(track)
  d.previewDrop:SetShown(odds)
  d.debug:SetShown(general); d.blockTitle:SetShown(general)
  if not track and d.track.inspect then d.track.inspect.frame:Hide() end
  d.subtitle:SetText(track and ("Level %d / 60 - All Basic cards are available from the start. The track shows new class cards and packs. Right-click cards to inspect."):format(self.collection.character.level or 1)
    or (odds and "Pack contents and kill rewards - chance-based drops" or "Chat preferences and blocked players"))
  local lines={}
  if odds then
    lines[#lines+1]="Classic, GvG + Naxxramas: 5 neutral cards per pack. At least one Rare or better. Class cards come from guaranteed level rewards."
    local odds={}
    for _,o in ipairs(ns.Packs.ODDS) do odds[#odds+1]=o.rarity:lower().." "..o.pct.."%" end
    lines[#lines+1]="Four ordinary slots: "..table.concat(odds,", ").."."
    local rare,epic,legend=0,0,0
    for _,o in ipairs(ns.Packs.ODDS) do
      if o.rarity=="COMMON" or o.rarity=="RARE" then rare=rare+o.pct
      elseif o.rarity=="EPIC" then epic=o.pct else legend=o.pct end
    end
    lines[#lines+1]=("Guaranteed slot: Rare %g%%, Epic %g%%, Legendary %g%%. Each card independently has a %g%% golden chance. These are this addon's odds."):format(rare,epic,legend,ns.Packs.GOLDEN_PCT)
    local r=ns.Drops.RATES
    lines[#lines+1]=("Pack chance per eligible kill: normal %g%%, elite %g%%, rare spawn %g%%. All kill rewards are packs, never single cards."):format(r.normal,r.elite,r.rare)
    lines[#lines+1]=("Dungeon bosses: %g%% for a pack; first encounter kills and raid bosses guarantee one. Kills must grant XP; at level 60, non-boss mobs must be level 55+. Bad-luck protection can increase reward chances."):format(r.boss)
  elseif track then
    d.track:SetRewards(self.collection:LevelRewardTrack(self:PlayerClass()),self.collection.character.level or 1,not opening and d.track.first or nil)
  end
  d.body:SetText(table.concat(lines,"\n\n"))
  d.debug.text:SetText("Extra chat messages: "..(ForeverHearthstoneDB.debugMessages and "On" or "Off"))
  local names,seen={},{}
  for key,name in pairs(self:DuelPrivacy().blocked) do names[#names+1]=name; seen[key]=true end
  for key in pairs(self.silenced or {}) do if not seen[key] then names[#names+1]=key end end
  table.sort(names); d.names=names; d.page=math.max(1,math.min(d.page,math.ceil(#names/4)))
  d.blockTitle:SetText(#names==0 and "No players blocked" or "Blocked players - click to unblock")
  for i,row in ipairs(d.rows) do local name=names[(d.page-1)*4+i]; row.text:SetText(name and ("Unblock "..name) or ""); row:SetShown(general and name~=nil) end
  d.prev:SetShown(general and d.page>1); d.next:SetShown(general and d.page*4<#names)
  --[[ General holds a toggle and the blocked list; at the progression size it
       was an 860x800 slab of empty red (the in-client tour, docs/39). It is
       sized to what it holds: the list, its pager, then Close. ]]
  if general then
    d.panel:SetSize(660, #names==0 and 340 or (#names<=4 and 480 or 540))
  else
    d.panel:SetSize(860, 800)
  end
  d:Show()
end

function Main:RewardHelp(view)
  self:Settings(view or "track")
end

--[[ Right-click a nearby player -> "Challenge to Hearthstone".

     Menu.ModifyMenu is the Mainline 11.0+ API; UnitPopupButtons, which every
     older addon used, is GONE (docs/07). Wrapped in pcall because a menu tag
     Forever happens not to have must not take the rest of the addon down with
     it -- the slash command is the path that always works. ]]
--[[ Every menu a friendly player's name opens: a stranger (PLAYER), a party
     or raid member -- their frames open PARTY / RAID_PLAYER, not PLAYER,
     which is why a groupmate had no Challenge entry -- a friend, and a name
     in chat. ]]
Main.CHALLENGE_MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER",
                         "MENU_UNIT_RAID", "MENU_UNIT_FRIEND", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER",
                         "MENU_UNIT_COMMUNITIES_MEMBER" }
function Main:AddContextMenu()
  if self.menuAdded or not Menu or not Menu.ModifyMenu then return end
  self.menuAdded = true
  local function add(owner, root, contextData)
    if not root or not root.CreateButton then return end
    local name = contextData and contextData.name
    if not name or name == "" then return end
    -- a portrait's menu knows its unit; a name in chat may know the GUID
    local unit, guid = contextData.unit, ns.Plain(contextData.guid)
    --[[ Is it you? By unit or GUID when the menu has one: on Forever two
         characters can share a first name, which is all the name test sees. ]]
    local mine = ns.Plain(UnitGUID("player"))
    if unit and UnitExists(unit) and UnitIsUnit then
      if ns.Plain(UnitIsUnit(unit, "player")) then return end
    elseif guid and mine then
      if guid == mine then return end
    elseif sameCharacter(name, UnitName("player")) then
      return
    end
    -- a player on another realm is addressed as Name-Realm
    local server = contextData.server
    if server and server ~= "" and not name:find("-", 1, true) then name = name .. "-" .. server:gsub("%s", "") end
    root:CreateButton("Challenge to Hearthstone", function() Main:Challenge(name, unit, guid) end)
  end
  for _, tag in ipairs(Main.CHALLENGE_MENUS) do pcall(Menu.ModifyMenu, tag, add) end
end

-- ============================================================ bootstrap

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("UNIT_PORTRAIT_UPDATE")
f:RegisterEvent("UNIT_LEVEL")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event, arg1)
  if event=="PLAYER_LOGOUT" then
    ns.Sounds.SilenceMusic(false)   -- never leave WoW's music at 0
    -- the collection is sealed as it goes to disk (Client/Vault.lua), below
    --[[ PLAYER_LOGOUT fires for /reload as well as a real logout, and the two
         cannot be told apart here. So a duel in progress is PAUSED ("left"),
         not forfeited: a reload comes back and rejoins (Session:RequestRejoin),
         a real logout does not, and the grace period then settles it exactly
         as for a player who walked away. A duel still being set up is left. ]]
    -- sealed FIRST, so nothing after it that fails can leave the collection unsealed
    if Main.collection and ns.Vault and not Main.schemaLocked then
      ns.Vault.Store(ForeverHearthstoneDB, ForeverHearthstoneCharDB, Main.VaultSalt())
    end
    if Main.session then
      if Main.session.state == ns.Session.STATE.PLAYING then
        Main.session:Pause("left")
      else
        Main.session:Leave("logout")
      end
      --[[ The last chance to say it: a throttle backoff from a moment ago must
           not hold the pause or the BYE back until after the client is gone. ]]
      if Main.transport then Main.transport.holdUntil = nil; Main.transport:Tick() end
    end
  elseif event=="PLAYER_TARGET_CHANGED" or event=="UNIT_PORTRAIT_UPDATE" or event=="UNIT_LEVEL" or event=="GROUP_ROSTER_UPDATE" then
    Main:RefreshProfiles()
    if event=="UNIT_LEVEL" and arg1=="player" and Main.session and Main.session:IsActive() then
      Main.session.me.level=UnitLevel("player")
      local record=Main:Record()
      Main.session:Send(ns.Protocol.KIND.PROFILE,UnitLevel("player"),UnitGUID("player") or "",record.wins,record.losses)
    end
  elseif event == "ADDON_LOADED" and arg1 == ADDON then
    --[[ SavedVariables only exist once this fires for THIS addon. They are also
         only flushed on logout or /reload, so a client crash loses the session
         -- mitigating that is its own piece (docs/08 SS8.6). ]]
    ForeverHearthstoneDB = ForeverHearthstoneDB or {}
    ForeverHearthstoneCharDB = ForeverHearthstoneCharDB or {}
    -- the version other players are told is the one in the .toc, so a release
    -- build reports its release number, not the source tree's
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or rawget(_G, "GetAddOnMetadata")
    local okMeta, version = pcall(getMeta or function() end, ADDON, "Version")
    if okMeta and type(version) == "string" and version ~= "" then ns.Protocol.ADDON_VERSION = version end
    -- a client that died while our music was muted left WoW's music at 0
    ns.Sounds.SilenceMusic(false)

    --[[ The asset manifest ships EMPTY and that is correct. Every card renders
         complete and legible from printed data alone, so art is an enhancement
         rather than a dependency -- there is no API that can tell us whether a
         texture path exists, and SetTexture fails silently. See docs/06. ]]
    Main.resolver = ns.Resolver.New({
      printed  = ns.PrintedCards,
      --[[ The generic candidates, minus anything a human has marked blank, with
           a user asset pack layered on top. See Client/Assets/GenericArt.lua. ]]
      manifest = ForeverHearthstoneDB.assetManifest
                 or ns.GenericArt.Manifest(ForeverHearthstoneDB.art or {}),
      override = ForeverHearthstoneDB.assetOverrides or {},
      palette  = ns.GenericArt.Palette(),
    })

  elseif event == "PLAYER_LOGIN" then
    --[[ Listening starts at login, not when a duel starts. An addon that only
         listens while it is already duelling can never be challenged. ]]
    Main:EnsureTransport()
    Main:AddContextMenu()
    Main:CreateMinimapButton()
    --[[ The collection needs UnitClass and UnitLevel, which are not reliable
         until PLAYER_LOGIN -- ADDON_LOADED fires before the player exists. ]]
    Main:LoadCollection()
    Main:StartRewards()
    -- the developer screenshot tour (FHTour/, never packaged), when installed
    local tour = rawget(_G, "FHTour_Attach")
    if tour then pcall(tour, ns, Main) end

    --[[ Verify what the client is able to verify. On a client with
         GetFileIDFromPath this turns 20 guessed icon paths into 20 facts and
         nobody has to look at anything; on one without it, nothing happens and
         `/fh icons` is still there. Either way it runs once, at login. ]]
    ForeverHearthstoneDB.art = ForeverHearthstoneDB.art or {}
    local checked, blank, unknown = ns.GenericArt.AutoAudit(ForeverHearthstoneDB.art)
    if checked > 0 then
      Main.resolver = ns.Resolver.New({
        printed  = ns.PrintedCards,
        manifest = ns.GenericArt.Manifest(ForeverHearthstoneDB.art),
        override = ForeverHearthstoneDB.assetOverrides or {},
        palette  = ns.GenericArt.Palette(),
      })
      if blank > 0 then
        Main:Print(("art: %d of %d generic icons are missing on this client and were dropped.")
                   :format(blank, checked))
      end
    end
    Main:Debug("loaded. Click the minimap button (or /fh) for the main menu, /fh duel to challenge your target.")
  end
end)

function Main:ShowHub()
  if not self.hub then
    local f = CreateFrame("Frame", "ForeverHearthstoneHub", UIParent)
    self.hub = f
    f.duelSession=false
    f:SetSize(1280, 720); f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN"); f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() f:StartMoving() end)
    f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    -- the same floor as the collection and the board: the three windows share
    -- one rect, and a larger floor here grew the window on every trip to it
    f.grip = ns.Widgets.ResizeGrip(f, ns.CollectionLayout.MinSize())
    -- every window's corner: close, Main Menu (practice only -- this IS the
    -- main menu otherwise), the speaker and its volume slider
    f.corner = ns.Widgets.WindowControls(f, {
      onHome = function()
        if f.duelSession then self:Decline(); return end
        f.botMode, f.chooseDeck, f.selectedDeck = false, false, false
        ns.Sounds.Play("menu_page"); f:Layout()
      end,
      onToggleMute = function() self:ToggleMute() end,
    })
    f.speaker, f.homeButton = f.corner.speaker, f.corner.home
    local ART = "Interface\\AddOns\\ForeverHearthstone\\Art\\"
    local W = ns.Widgets
    local bg = f:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints()
    bg:SetTexture(ART.."tavern-cabinet.tga")
    f.bg = bg
    -- a window wider than the cabinet can crop is letterboxed
    f.bgBands = W.EdgeBands(f, ART.."tavern-cabinet.tga", -2)
    -- Practice draws its own scene over the cabinet; the cabinet's crest sits
    -- just above the book, so a shade falls from the top edge to keep it from
    -- peeking out half-covered (page-shade.tga turned on its side: dark at
    -- the top, clear by the book's middle).
    -- Two layers: the file's darkest edge is only 60% opaque.
    f.practiceShades={}
    for i=1,2 do
      local shade=f:CreateTexture(nil,"BACKGROUND",nil,i)
      shade:SetTexture(ART.."page-shade.tga")
      shade:SetTexCoord(0,1, 1,1, 0,0, 1,0)
      shade:SetVertexColor(0,0,0,1)
      shade:SetPoint("TOPLEFT",f,"TOPLEFT",0,0)
      shade:Hide()
      f.practiceShades[i]=shade
    end
    --[[ PRACTICE, laid out as Hearthstone's Play screen: a book on the left
         holding the choices (nine opponents, then your decks), and a stage on
         the right showing the chosen hero large, over the big amber Play
         button. The cabinet behind dims so the two read as one screen. ]]
    f.book=W.MenuPanel(f,"leather"); f.book.bg:SetVertexColor(.42,.24,.14,1)
    f.bookPage=f.book:CreateTexture(nil,"BORDER",nil,-1)
    f.bookPage:SetTexture(ART.."menu-parchment.tga"); f.bookPage:SetVertexColor(1,.96,.86,1)
    f.stage=W.TrayPanel(f)
    for _,panel in ipairs({f.book,f.stage}) do panel:SetFrameLevel(f:GetFrameLevel()); panel:Hide() end
    f.stageHero=CreateFrame("Frame",nil,f.stage)
    f.stagePortrait=f.stageHero:CreateTexture(nil,"ARTWORK"); f.stagePortrait:SetAllPoints()
    f.stageRim=W.GoldFrame(f.stageHero,14,"OVERLAY")
    f.stageName=W.StyledText(f.stage,"heroName")
    f.stageName:SetWordWrap(false)
    f.stageDetail=W.StyledText(f.stage,"body")
    f.stageDetail:SetWordWrap(false)
    --[[ HOW HARD THE BOT IS: a five-notch slider over the Play button, its
         name above and what it means below. One setting for both the deck
         the bot brings and how well it plays it (Main:BotDifficulty). ]]
    f.diffName=W.StyledText(f.stage,"label")
    f.diffName:SetWordWrap(false)
    f.diffBlurb=W.StyledText(f.stage,"body")
    f.diffBlurb:SetWordWrap(false)
    f.diffSlider=W.StepSlider(f.stage,{
      steps=#ns.AI.DIFFICULTIES,
      get=function() return self:BotDifficulty() end,
      set=function(i) self:SetBotDifficulty(i); ns.Sounds.Play("menu_click"); f:Layout() end,
    })
    -- Practice names itself on the stone plaque every screen shares; the main
    -- menu is Hearthstone's box itself and carries no title (docs/24).
    local title = W.TitlePlaque(f)
    f.title = title
    f.buttons, f.tiles, f.botMode = {}, {}, false
    f.chooseDeck, f.selectedDeck, f.deckPage, f.lastDeck, f.deckOpenedAt = false, false, 1, false, 0
    local function collection()
      if not self.collectionUI then self:Collection() end
      self.collectionUI.packRoom = nil
      self.collectionUI:Show(); f:Hide()
      return self.collectionUI
    end
    local function button(label, action)
      local b = ns.Widgets.MenuButton(f, label, action)
      f.buttons[#f.buttons+1] = b
      return b
    end
    local caption = W.StyledText(f, "caption")
    caption:SetText("Choose an opponent")
    button("Play Bots", function() if f.duelSession then self:Decline(); return end; if f.botMode and f.chooseDeck then f.chooseDeck=false
      else f.botMode=not f.botMode end
      f.selectedDeck=false; f.deckPage=1; ns.Sounds.Play("menu_page"); f:Layout() end)
    button("My Collection", function() collection():EditDeck(nil) end)
    button("My Decks", function() collection():ShowDecks() end)
    button("Open Packs", function() collection():ShowPackRoom() end)
    button("Resume Match", function() if self.board then self.board:Show(); f:Hide() end end)
    button("Close", function() f:Hide() end)
    -- last in the list (callers and tests index the others), fifth plaque on screen
    f.duelButton = button("Duel a Player", function() self:DuelFromMenu() end)
    local function heroArt(class) return self.resolver:Card(ns.HERO_ID_BY_CLASS[class]).icon end
    local function deckArt(deck) return self.resolver:Card(ns.Widgets.DeckArtCard(deck)).icon end
    local function titleCase(s) return s:sub(1,1)..s:sub(2):lower() end
    f.selectedClass = ns.CLASSES[1]
    -- The nine opponents: each hero's portrait in a gold rim over its name.
    for i, class in ipairs(ns.CLASSES) do
      local chosen = class
      local tile = W.MenuButton(f, class, function()
        f.selectedClass = chosen; f:Layout()
      end)
      tile.class = class
      tile.selection=tile:CreateTexture(nil,"BACKGROUND",nil,-2)
      tile.selection:SetTexture(ART.."crest-glow.tga"); tile.selection:SetBlendMode("ADD")
      tile.selection:SetVertexColor(1,.78,.3,.95)
      local portrait = tile:CreateTexture(nil, "BACKGROUND", nil, 2)
      portrait:SetTexture(heroArt(class))
      tile.portrait=portrait
      tile.rim=W.GoldFrame(tile,9,"ARTWORK")
      tile.bg:Hide()
      tile.text:Hide()
      local label=CreateFrame("Frame",nil,tile)
      label:SetFrameLevel(tile:GetFrameLevel()+3)
      label:SetPoint("BOTTOM",tile,"BOTTOM",0,4)
      -- the hero's name on Hearthstone's dark, gold-rimmed name strip
      label.plate=W.NamePlate(label,"BACKGROUND")
      tile.classLabel=label
      tile.text=label:CreateFontString(nil,"OVERLAY")
      tile.text:SetPoint("CENTER",label,"CENTER",0,0)
      tile.text:SetWordWrap(false)
      ns.Widgets.AutoFit(tile.text,{w=80,h=20,font=ns.Fonts.TITLE,size=15,min=8,flags="OUTLINE"})
      -- light lettering on the name strip: without this the button's hover
      -- feedback repainted it the plaque's dark brown, unreadable on black
      tile.textColor=W.Colors.cream
      W.ApplyStyle(tile.text,"label",nil,15,W.Colors.cream)
      tile.text:SetText(titleCase(class))
      tile.label=tile.text
      --[[ Laid out by the gallery itself (f:Layout calls this) as well as on
           resize. The tiles are sized on the main menu while still hidden,
           and the client does not reliably send OnSizeChanged to a hidden
           frame -- so the name strip kept a zero size, which WoW does not
           draw, and the class names only appeared after a resize. Fitting
           the name again here also re-applies its font each time the
           gallery is shown. ]]
      function tile:Fit(w,h)
        ns.Widgets.LayoutMenuPanel(tile); tile.rim:Layout(w,h)
        local lh=math.max(26,math.min(36,h*.17))
        tile.text:SetSize(w-24,lh*.8); label:SetSize(w-8,lh); label.plate:Layout(w-8,lh)
        portrait:ClearAllPoints(); portrait:SetPoint("TOPLEFT",tile,"TOPLEFT",4,-4)
        portrait:SetSize(math.max(1,w-8),math.max(1,h-8))
        -- Square art cropped to the tile, keeping the face.
        local a=(w-8)/math.max(1,h-8)
        if a<1 then portrait:SetTexCoord((1-a)/2,(1+a)/2,0,1) else portrait:SetTexCoord(0,1,.06,math.min(1,.06+1/a)) end
        tile.selection:ClearAllPoints()
        tile.selection:SetPoint("TOPLEFT",tile,"TOPLEFT",-w*.2,h*.16)
        tile.selection:SetPoint("BOTTOMRIGHT",tile,"BOTTOMRIGHT",w*.2,-h*.16)
      end
      tile:SetScript("OnSizeChanged",function(_,w,h) tile:Fit(w,h) end)
      f.tiles[i] = tile
    end
    f.play = W.StylePlayButton(W.MenuButton(f, "Play", function()
      if not self.collection then self:Print("Your collection is not available yet."); return end
      if not f.chooseDeck then
        f.chooseDeck=true; f.selectedDeck=false; f.deckPage=1; f.deckOpenedAt=GetTime(); f:Layout(); return
      end
      -- A deck is already chosen when the book opens, and Play sits where
      -- Choose Deck was: a double click must not start a game unseen.
      if not f.duelSession and GetTime()-(f.deckOpenedAt or 0)<.4 then return end
      if f.duelSession then
        local session=f.duelSession
        if self.session~=session or session.committed then return end
        local deck=f.selectedDeck
        if not deck or deck.class~=self:PlayerClass() or not self.collection:ValidateDeck(deck) then f:Layout(); return end
        local ok,why=session:ChooseDeck(deck.cards)
        if not ok then self:Print(why or "Could not select that deck.") end
        if f.duelSession then f:Layout() end
        return
      end
      if not f.selectedDeck then return end
      if self:StartPractice(nil, f.selectedClass, f.selectedDeck)~=false then
        f.lastDeck=f.selectedDeck
        f.selectedDeck=false; f.chooseDeck=false; f.botMode=false; f:Hide()
      else f.selectedDeck=false; f:Layout() end
    end), 26)
    f.deckChoices={}
    f.deckPrev=W.MenuButton(f,"",function() f.deckPage=f.deckPage-1; f:Layout() end)
    f.deckNext=W.MenuButton(f,"",function() f.deckPage=f.deckPage+1; f:Layout() end)
    for i,b in ipairs({f.deckPrev,f.deckNext}) do
      b.bg:SetTexture(ART.."page-arrow.tga")
      if i==1 then b.bg:SetTexCoord(1,0,0,1) else b.bg:SetTexCoord(0,1,0,1) end
    end
    f.welcome = W.StyledText(f, "subtitle")
    f.welcome:SetText("Pull up a chair by the hearth")
    f.record = W.HSPanel(f)
    f.record:EnableMouse(false); f.record:SetFrameLevel(f:GetFrameLevel() + 20)
    --[[ Two rows on one axis: each label ends just left of the card's centre
         line and each W - L starts just right of it, so the figures line up
         and the block sits in the middle. As one centred string the rows were
         different lengths and the numbers wandered. ]]
    f.recordRows = {}
    for i = 1, 2 do
      local label, value = W.StyledText(f.record, "tooltipBody"), W.StyledText(f.record, "tooltipBody")
      label:SetJustifyH("RIGHT"); value:SetJustifyH("LEFT")
      label:SetWordWrap(false); value:SetWordWrap(false)
      f.recordRows[i] = { label = label, value = value }
    end
    -- who may challenge you, one click to change (Main:AllowChallengeFrom)
    f.privacy = W.MenuButton(f, "", function()
      local p = self:DuelPrivacy().policy
      local list, nextPolicy = Main.CHALLENGE_POLICIES, Main.CHALLENGE_POLICIES[1]
      for i, v in ipairs(list) do if v == p then nextPolicy = list[i % #list + 1] end end
      self:SetChallengePolicy(nextPolicy)
      f:Layout()
    end)
    f.privacy:SetFrameLevel(f:GetFrameLevel() + 20)
    f.progression = W.MenuButton(f,"Progression",function() self:RewardHelp() end)
    f.progression:SetSize(190,30); f.progression:SetPoint("TOPLEFT",f.privacy,"BOTTOMLEFT",0,-6)
    f.progression:SetFrameLevel(f:GetFrameLevel()+20)
    f.settings = W.MenuButton(f,"Settings",function() self:Settings("general") end)
    f.settings:SetSize(190,30); f.settings:SetPoint("TOPLEFT",f.progression,"BOTTOMLEFT",0,-6)
    f.settings:SetFrameLevel(f:GetFrameLevel()+20)
    local function place(region,x,top,w,h)
      region:ClearAllPoints(); region:SetSize(math.max(1,w),math.max(1,h))
      region:SetPoint("TOPLEFT",f,"TOPLEFT",x,-top)
    end
    --[[ The cabinet keeps its shape (W.CoverTexture), so everything painted
         into it -- the plaques' slots, the crest, the candles -- is placed in
         the ART's coordinates and mapped through the crop. At 16:9 the crop
         takes a sliver of table from the top and more from the bottom, never
         the cabinet. ]]
    local CABINET_W,CABINET_H=1536,1024
    --[[ At most this much of the cabinet's height may be cropped away. A wide,
         short window used to crop the cabinet's foot -- and the bottom plaque,
         Resume and Close with it -- off the bottom of the window (reported
         with a screenshot). Past this aspect the cabinet is drawn narrower
         than the window, centred, and letterboxed (W.EdgeBands). ]]
    local CABINET_KEEP=.85
    local EDGE,PAIR_GAP=12,12   -- the menu's plaques keep this far from the window's edge
    function f:Layout()
      local w,h = self:GetWidth(),self:GetHeight()
      W.RestyleAll(self,h)
      local artW=math.min(w,h*CABINET_W/CABINET_H/CABINET_KEEP)
      local ax=(w-artW)/2
      self.bg:ClearAllPoints(); self.bg:SetPoint("TOPLEFT",self,"TOPLEFT",ax,0); self.bg:SetSize(artW,h)
      local crop=W.CoverTexture(self.bg,artW,h,CABINET_W,CABINET_H,1,1,.3)
      local spanW,spanH=W.CoverSpan(crop)
      local function at(fx,fy) local x,y=W.CoverPoint(crop,fx,fy); return x+ax,y end
      self.bgBands:Place(w,h,{x=ax,y=0,w=artW,h=h},{l=crop.l,r=crop.r,t=crop.t,b=crop.b})
      for _,shade in ipairs(self.practiceShades) do shade:SetSize(w,h*.7); shade:SetShown(self.botMode==true) end
      local picking=self.botMode and self.chooseDeck
      self.bg:SetVertexColor(self.botMode and .5 or 1,self.botMode and .45 or 1,self.botMode and .4 or 1,1)
      self.bgBands:SetVertexColor(self.botMode and .5 or 1,self.botMode and .45 or 1,self.botMode and .4 or 1,1)
      title:SetShown(self.botMode==true)
      if self.botMode then title:Place(w/2,math.max(26,h*.058),math.max(34,math.min(56,h*.07)),self.duelSession and "Duel" or "Practice") end
      -- Main menu: four plaques in the cabinet, Resume and Close beneath.
      -- Practice keeps only Back (from the decks to the opponents), under the
      -- book; Main Menu and close are in the corner, as on every screen.
      self.homeButton:SetShown(self.botMode==true)
      for i,b in ipairs(self.buttons) do
        b:ClearAllPoints()
        b:SetShown(not self.botMode or (i==1 and self.chooseDeck==true))
        if self.botMode then
          b:SetSize(w*.2,h*.064)
          b:SetPoint("CENTER",self,"TOPLEFT",w*.04+w*.56/2,-h*.935)
          W.ApplyStyle(b.text,"button",h)
        elseif i<=4 or b==self.duelButton then
          -- the five plaques sit in the cabinet's oval (Duel a Player is fifth)
          local slot=(b==self.duelButton) and 5 or i
          local x,y=at(.5,.34+(slot-1)*.0875)
          b:SetSize(math.min(spanW*.35,w-2*EDGE),spanH*.08)
          b:SetPoint("CENTER",self,"TOPLEFT",x,-y)
          W.ApplyStyle(b.text,"buttonLarge",h)
        else
          --[[ Resume and Close on the cabinet's foot. A narrow window crops
               the cabinet's sides, and these two sit out towards them: placed
               in the art alone they ran off both edges of the window
               (reported with a screenshot). So they keep to the window, and
               narrow to share it when they must. ]]
          local x,y=at(.5+(i==5 and -1 or 1)*.125,.81)
          local bw=math.min(spanW*.22,(w-2*EDGE-PAIR_GAP)/2)
          if i==5 then x=math.max(x,EDGE+bw/2) else x=math.min(x,w-EDGE-bw/2) end
          b:SetSize(bw,spanH*.068)
          b:SetPoint("CENTER",self,"TOPLEFT",x,-y)
          W.ApplyStyle(b.text,"button",h)
        end
      end
      self.buttons[1].text:SetText(self.duelSession and "Cancel Duel" or (self.botMode and "Back" or "Play Bots"))
      -- what is waiting, on the plaque itself
      local waiting = ns.Main.collection and ns.Main.collection:TotalPacks() or 0
      self.buttons[4].text:SetText(waiting > 0 and ("Open Packs (%d)"):format(waiting) or "Open Packs")

      -- The book (left) and the stage (right).
      local bx,by,bw,bh=w*.04,h*.155,w*.56,h*.72
      local sx,sw=w*.63,w*.33
      place(self.book,bx,by,bw,bh); self.book:SetShown(self.botMode==true)
      self.bookPage:ClearAllPoints(); self.bookPage:SetPoint("TOPLEFT",self.book,"TOPLEFT",10,-10)
      self.bookPage:SetSize(bw-20,bh-20)
      place(self.stage,sx,by,sw,bh); self.stage:SetShown(self.botMode==true)
      caption:SetText(picking and "Choose your deck" or "Choose an opponent")
      caption:ClearAllPoints(); caption:SetPoint("BOTTOM",self,"TOPLEFT",bx+bw/2,-by+2)
      W.ApplyStyle(caption,"caption",h)

      -- Opponents: a 3x3 gallery on the page.
      local pad,gap=math.max(16,bw*.035),math.max(8,bw*.02)
      local tileW=(bw-2*pad-2*gap)/3
      local tileH=(bh-2*pad-2*gap)/3
      for i,tile in ipairs(self.tiles) do
        place(tile,bx+pad+((i-1)%3)*(tileW+gap),by+pad+math.floor((i-1)/3)*(tileH+gap),tileW,tileH)
        tile:SetFrameLevel(self.book:GetFrameLevel()+2); tile.classLabel:SetFrameLevel(tile:GetFrameLevel()+3)
        tile:SetShown(self.botMode == true and not self.chooseDeck)
        if tile:IsShown() then tile:Fit(tileW,tileH) end
        tile.selection:SetShown(tile.class==self.selectedClass)
        tile.rim:SetVertexColor(1,tile.class==self.selectedClass and 1 or .88,tile.class==self.selectedClass and .7 or .78)
      end

      -- Decks: six deck boxes to a page, turned with the book's arrows.
      for _,b in ipairs(self.deckChoices) do b:Hide() end
      self.deckPrev:Hide(); self.deckNext:Hide()
      local decks={}
      if picking then
        decks=ns.Main.collection.character.decks
        --[[ The page's grid: rows and columns chosen for the page's shape
             (W.DeckGrid), filled from the top-left. A fixed 3x2 block centred
             on the page left one deck floating half-way down a tall window, or
             in the middle of a wide one. ]]
        local rows,cols,boxW,boxH=W.DeckGrid(bw-2*pad,bh-2*pad,gap,math.max(170,math.min(300,h*.3)))
        local perPage=rows*cols
        local pages=math.max(1,math.ceil(#decks/perPage))
        if #decks==0 then caption:SetText("Create a deck in My Decks to play") end
        self.deckPage=math.max(1,math.min(self.deckPage or 1,pages))
        local selectedValid=false
        for _,deck in ipairs(decks) do
          if deck==self.selectedDeck and deck.class==ns.Main:PlayerClass() and ns.Main.collection:ValidateDeck(deck) then selectedValid=true end
        end
        if not selectedValid then self.selectedDeck=false end
        -- Hearthstone opens the deck book on a deck already chosen, so Play is
        -- one click away: the one you last played, else your duel deck, else
        -- the first deck that is ready.
        if not self.selectedDeck then
          local function ready(deck)
            return deck and deck.class==ns.Main:PlayerClass() and ns.Main.collection:ValidateDeck(deck) and deck or nil
          end
          local pick=nil
          for _,deck in ipairs(decks) do if deck==self.lastDeck then pick=ready(deck) end end
          pick=pick or ready(ns.Main.collection:ActiveDeck())
          for _,deck in ipairs(decks) do pick=pick or ready(deck) end
          if pick then
            self.selectedDeck=pick
            for i,deck in ipairs(decks) do if deck==pick then self.deckPage=math.ceil(i/perPage) end end
          end
        end
        local gx=bx+(bw-(cols*boxW+(cols-1)*gap))/2
        local gy=by+pad
        for slot=1,perPage do
          local deck=decks[(self.deckPage-1)*perPage+slot]
          if deck then
            local b=self.deckChoices[slot]
            if not b then
              b=W.MenuButton(self,"",function()
                if self.duelSession and self.duelSession.committed then return end
                local deck=self.deckChoices[slot].deck
                -- Choosing a deck is answered by its hero, as in Hearthstone.
                if self.selectedDeck~=deck and deck.class then
                  ns.Sounds.PlayHero(ns.Sounds.HeroForClass(deck.class),"picked",true)
                end
                self.selectedDeck=deck; self:Layout() end)
              self.deckChoices[slot]=b
            end
            b.deck=deck
            local valid=deck.class==ns.Main:PlayerClass() and ns.Main.collection:ValidateDeck(deck)
            place(b,gx+((slot-1)%cols)*(boxW+gap),gy+math.floor((slot-1)/cols)*(boxH+gap),boxW,boxH)
            b:SetFrameLevel(self.book:GetFrameLevel()+2)
            b:SetEnabledLook(valid and not (self.duelSession and self.duelSession.committed)); b:SetAlpha(valid and 1 or .7)
            W.StyleDeckBox(b,{portrait=deckArt(deck),name=deck.name,
              detail=#deck.cards.."/30"..(valid and " cards" or " - not ready"),
              detailColor=valid and W.Colors.count or {1,.45,.35},selected=self.selectedDeck==deck})
            b:Show()
          end
        end
        local aw=math.max(26,math.min(38,w*.03))
        for i,b in ipairs({self.deckPrev,self.deckNext}) do
          place(b,i==1 and bx-aw/2 or bx+bw-aw/2,by+bh/2-aw,aw,aw*2)
          b:SetFrameLevel(self.book:GetFrameLevel()+10)
          b:SetShown(pages>1)
        end
        self.deckPrev:SetEnabledLook(self.deckPage>1); self.deckNext:SetEnabledLook(self.deckPage<pages)
      end

      -- The stage: whoever you are about to play, large, over the Play button.
      local stageClass=picking and ns.Main:PlayerClass() or self.selectedClass
      local inner=sw-36
      local playH=math.min(70,bh*.13)
      -- Portrait, then name, detail, the difficulty and the Play button
      -- stacked beneath it.
      self.diffSlider:Layout(math.min(inner,260))
      local diffH=picking and ((select(2,self.diffName:GetFont()) or 14)*2.5+10)
        or ((select(2,self.diffName:GetFont()) or 14)*2.5+self.diffSlider:GetHeight()
          +(select(2,self.diffBlurb:GetFont()) or 14)*2.5+12)
      local ph=math.min(inner*1.2,bh-18-8-30-2-18-14-playH-18-diffH)
      local pw=math.min(inner,ph/1.2)
      self.stageHero:ClearAllPoints(); self.stageHero:SetSize(pw,ph)
      self.stageHero:SetPoint("TOP",self.stage,"TOP",0,-18)
      self.stagePortrait:SetTexture(heroArt(stageClass))
      local a=pw/ph; self.stagePortrait:SetTexCoord((1-a)/2,(1+a)/2,0,1)
      self.stageRim:Layout(pw,ph)
      self.stageName:ClearAllPoints(); self.stageName:SetPoint("TOP",self.stageHero,"BOTTOM",0,-8)
      self.stageName:SetSize(inner,30); self.stageName:SetText(titleCase(stageClass))
      self.stageDetail:ClearAllPoints(); self.stageDetail:SetPoint("TOP",self.stageName,"BOTTOM",0,-2)
      self.stageDetail:SetSize(inner,18)
      self.stageDetail:SetText(picking and (self.selectedDeck and self.selectedDeck.name or "Pick a deck from the book")
        or "Your opponent")
      place(self.play,sx+18,by+bh-18-playH,inner,playH)
      self.play:SetFrameLevel(self.stage:GetFrameLevel()+5)
      --[[ The difficulty, stacked up from the Play button. It is chosen WITH
           the opponent: once you are picking your deck the slider goes, and
           the stage just says who you will face -- a slider still live on the
           deck page read as a second, separate choice. ]]
      local level=ns.AI.DIFFICULTIES[ns.Main:BotDifficulty()]
      self.diffBlurb:ClearAllPoints(); self.diffBlurb:SetPoint("BOTTOM",self.play,"TOP",0,8)
      -- captions WRAP onto a second line rather than end in "...": a narrow
      -- stage cut "The best decks of the era" and "Against: Master Mage bot"
      self.diffBlurb:SetWordWrap(true)
      self.diffBlurb:SetSize(inner,(select(2,self.diffBlurb:GetFont()) or 14)*2.5)
      self.diffBlurb:SetText(level.blurb)
      self.diffSlider:ClearAllPoints(); self.diffSlider:SetPoint("BOTTOM",self.diffBlurb,"TOP",0,2)
      self.diffSlider:Layout(math.min(inner,260))
      self.diffSlider:SetShown(self.botMode==true and not picking)
      self.diffName:ClearAllPoints()
      if picking then
        self.diffName:SetPoint("BOTTOM",self.play,"TOP",0,10)
        self.diffName:SetText(self.duelSession and ("Against: "..tostring(self.duelSession.peer.name).." ("..titleCase(self.duelSession.peer.class)..")") or ("Against: %s %s bot"):format(level.name,titleCase(self.selectedClass)))
      else
        self.diffName:SetPoint("BOTTOM",self.diffSlider,"TOP",0,2)
        self.diffName:SetText("Difficulty: "..level.name)
      end
      self.diffName:SetWordWrap(true)
      self.diffName:SetSize(inner,select(2,self.diffName:GetFont())*2.5)
      self.diffBlurb:SetShown(self.botMode==true and not picking)
      self.play.text:SetText(self.duelSession and (self.duelSession.committed and "Waiting..." or "Ready") or (picking and "Play" or "Choose Deck"))
      W.ApplyStyle(self.play.text,"playButton",h*(picking and 1.08 or .85))
      self.play:SetEnabledLook(not (self.duelSession and self.duelSession.committed) and (not picking or self.selectedDeck~=false))
      self.play:SetShown(self.botMode == true)
      self.progression:SetShown(not self.botMode)
      self.settings:SetShown(not self.botMode)
      if self.botMode then caption:Show(); self.welcome:Hide(); self.record:Hide(); self.privacy:Hide()
      else
        --[[ The tagline sits on the cloth under the cabinet. In a wide, short
             window that cloth is cropped away, and the line was pushed up onto
             the cabinet's foot beside Resume and Close; it is flavour, so it
             simply goes. ]]
        caption:Hide()
        local _,fy=at(.5,.935)
        fy=math.min(h-18,fy)
        local _,footY=at(.5,.81)
        local clear=fy-(footY+spanH*.068/2)>=self.welcome:GetStringHeight()+8
        self.welcome:SetShown(clear)
        self.welcome:ClearAllPoints(); self.welcome:SetPoint("CENTER",self,"TOPLEFT",ax+artW/2,-fy)
        -- this character's record, on a parchment card in the top-left corner
        local duel,practice=ns.Main:Record(),ns.Main:PracticeRecord()
        --[[ The Challenges plaque is as wide as its words ("Friends & group"
             ran into its gold end caps at 190), and the record card above it
             matches it so the two stay flush. ]]
        local policy=ns.Main:DuelPrivacy().policy
        self.privacy:SetSize(600,30)
        self.privacy.text:SetText("Challenges: "..(Main.CHALLENGE_POLICY_LABEL[policy] or policy))
        W.ApplyStyle(self.privacy.text,"button",nil,12)
        local faceW=W.MenuFaceBox(600,30)
        local capsW=600-faceW
        local recordW=math.max(190,math.ceil(self.privacy.text:GetStringWidth()+capsW+16))
        local rowH=17
        self.record:SetContent("Your Record",nil,recordW,rowH*2)
        local rowY=-(14+self.record.title:GetStringHeight()+4)
        for i,row in ipairs({{"Duels:",duel},{"Practice:",practice}}) do
          local r=self.recordRows[i]
          r.label:SetText(row[1]); r.value:SetText(W.RecordText(row[2].wins,row[2].losses,true," - "))
          r.label:ClearAllPoints(); r.label:SetSize(recordW/2-18,rowH)
          r.label:SetPoint("TOPRIGHT",self.record,"TOP",-3,rowY)
          r.value:ClearAllPoints(); r.value:SetSize(recordW/2-12,rowH)
          r.value:SetPoint("TOPLEFT",self.record,"TOP",3,rowY)
          rowY=rowY-rowH
        end
        self.record:ClearAllPoints(); self.record:SetPoint("TOPLEFT",self,"TOPLEFT",14,-14)
        self.record:Show()
        self.privacy:ClearAllPoints(); self.privacy:SetSize(recordW,30)
        self.privacy:SetPoint("TOPLEFT",self.record,"BOTTOMLEFT",0,-6)
        self.privacy:Show()
        self.progression:SetSize(recordW,30)
        self.settings:SetSize(recordW,30)
      end
      self.buttons[5]:SetEnabledLook(ns.Main.board ~= nil)
    end
    f:SetScript("OnSizeChanged", function() f:Layout() end)
    f:HookScript("OnShow",function()
      f.enterAge=0; f.lightTick=0; f:SetAlpha(.2); ns.Sounds.Play("menu_open")
      -- The innkeeper welcomes you once a session, as Hearthstone's does.
      if not ns.Main.greeted then ns.Main.greeted=true; ns.Sounds.Play("innkeeper") end
      ns.Main:SyncMusicSoon()
      f:SetScript("OnUpdate",function(_,dt)
        f.enterAge=f.enterAge+dt
        f:SetAlpha(math.min(1,.2+f.enterAge/.3))
        if f.enterAge>=.3 then f:SetScript("OnUpdate",nil) end
      end)
    end)
    f:SetScript("OnHide",function()
      f:SetScript("OnUpdate",nil); f:SetAlpha(1)
      ns.Main:SyncMusicSoon()
      --[[ Closed (Esc, the corner) while it was the duel's deck picker and no
           deck was chosen: the duel is called off, said so -- left as it was,
           both players waited on a picker nobody could see. ]]
      local s=f.duelSession
      if s and s==ns.Main.session and s.state==ns.Session.STATE.SYNC and not s.committed
         and not ns.Main.hubAside then
        ns.Main:Print("you closed the deck picker, so the duel was called off.")
        ns.Main:Decline()
      end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, "ForeverHearthstoneHub") end
    f:Hide() -- Ensure the first opening uses the same entrance as later visits.
  end
  self.hub:Layout(); self.hub:Show()
end

--[[ THE MINIMAP BUTTON, so nobody has to remember /fh.

     The Hearthstone medallion (tools/build_minimap_icon.py) in WoW's own round
     minimap border, like every other addon's. Left-click opens the main menu
     (or brings back a hidden match), right-click the collection; drag it
     round the rim. Its angle and whether it is shown are account-wide
     (ForeverHearthstoneDB.minimap). `/fh minimap` hides and shows it. ]]
Main.MINIMAP_DEFAULT_ANGLE = 200          -- degrees, lower left of the map

--[[ Where the button sits for an angle, as an offset from the map's centre.
     A round map puts it on the rim; a square one (GetMinimapShape) on the
     square's edge, so it does not float inside the corners. ]]
function Main.MinimapOffset(angle, radius, square)
  local rad = math.rad(angle or Main.MINIMAP_DEFAULT_ANGLE)
  local x, y = math.cos(rad), math.sin(rad)
  if square then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = x / m, y / m
  end
  return x * radius, y * radius
end

function Main:MinimapSettings()
  ForeverHearthstoneDB = ForeverHearthstoneDB or {}
  ForeverHearthstoneDB.minimap = ForeverHearthstoneDB.minimap or {}
  return ForeverHearthstoneDB.minimap
end

-- Left-click: back to the match if one is hidden, otherwise the main menu.
function Main:OnMinimapClick(button)
  if button == "RightButton" then
    local ok = pcall(function() self:Collection(true) end)
    if not ok then self:PrintCollection() end
    return
  end
  if self.board and self.board.frame and not self.board.frame:IsShown()
     and self.game and not self.game.over then
    self.board:Show()
  elseif self.hub and self.hub:IsShown() then
    self.hub:Hide()
  else
    self:ShowHub()
  end
end

function Main:PlaceMinimapButton()
  local b = self.minimapButton
  if not b or not Minimap then return end
  local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
  local radius = (Minimap:GetWidth() or 140) / 2 + (square and 8 or 5)
  local x, y = Main.MinimapOffset(self:MinimapSettings().angle, radius, square)
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function Main:CreateMinimapButton()
  if self.minimapButton or not Minimap then return self.minimapButton end
  local b = CreateFrame("Button", "ForeverHearthstoneMinimapButton", Minimap)
  self.minimapButton = b
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\AddOns\\ForeverHearthstone\\Art\\minimap-icon.tga")
  icon:SetSize(20, 20); icon:SetPoint("TOPLEFT", 7, -5)
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53); border:SetPoint("TOPLEFT")

  b:SetScript("OnClick", function(_, button) self:OnMinimapClick(button) end)
  b:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -6) end)
  b:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -5) end)
  b:SetScript("OnEnter", function()
    if not GameTooltip then return end
    GameTooltip:SetOwner(b, "ANCHOR_LEFT")
    GameTooltip:SetText("Forever Hearthstone")
    GameTooltip:AddLine("Left-click: main menu", 1, 1, 1)
    GameTooltip:AddLine("Right-click: collection", 1, 1, 1)
    GameTooltip:AddLine("Drag: move this button", .7, .7, .7)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- dragging follows the cursor round the rim
  b:SetScript("OnDragStart", function()
    b:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      if not (mx and cx and scale and scale > 0) then return end
      self:MinimapSettings().angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
      self:PlaceMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function() b:SetScript("OnUpdate", nil) end)

  self:PlaceMinimapButton()
  if self:MinimapSettings().hide then b:Hide() else b:Show() end
  return b
end

function Main:ToggleMinimapButton()
  local s = self:MinimapSettings()
  s.hide = not s.hide or nil
  local b = self:CreateMinimapButton()
  if b then if s.hide then b:Hide() else b:Show() end end
  self:Print(s.hide and "minimap button hidden -- /fh minimap brings it back."
                     or "minimap button shown.")
end

-- The retail Addon Compartment (the dropdown by the minimap) calls this by
-- name, from the .toc's AddonCompartmentFunc.
function ForeverHearthstone_OnAddonCompartmentClick(_, button)
  Main:OnMinimapClick(button)
end

SLASH_FOREVERHEARTHSTONE1 = "/fh"
SLASH_FOREVERHEARTHSTONE2 = "/foreverhearthstone"
SlashCmdList["FOREVERHEARTHSTONE"] = function(msg)
  local dev = (msg or ''):match('^%s*dev%s+(.+)$')
  if dev then ns.DevTest:Command(dev); return end
  local raw = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")   -- names keep their case
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "" then
    Main:ShowHub()

  elseif msg == "practice" then
    Main:ShowHub()
    Main.hub.botMode=true; Main.hub.chooseDeck=false; Main.hub.selectedDeck=false; Main.hub:Layout()

  elseif msg:match("^difficulty") then
    -- /fh difficulty            what it is now
    -- /fh difficulty 4          set it by number...
    -- /fh difficulty expert     ...or by name
    local arg = msg:match("^difficulty%s+(%S+)")
    if arg then
      local n = tonumber(arg)
      for i, d in ipairs(ns.AI.DIFFICULTIES) do
        if d.name:lower() == arg then n = i end
      end
      -- 9 is not a difficulty: say so, rather than quietly choosing Master
      if not n or n ~= n or n < 1 or n > #ns.AI.DIFFICULTIES then
        Main:Print("difficulty is 1-5 or a name: novice, apprentice, adept, expert, master.")
        return
      end
      Main:SetBotDifficulty(n)
      if Main.hub and Main.hub:IsShown() then Main.hub:Layout() end
    end
    local d = ns.AI.DIFFICULTIES[Main:BotDifficulty()]
    Main:Print(("practice bots: %s (%d/5) -- %s"):format(d.name, Main:BotDifficulty(), d.blurb))

  elseif msg == "hide" then
    if Main.board then Main.board:Hide() end

  elseif msg == "show" then
    if Main.board then Main.board:Show() else Main:Print("no match in progress.") end

  elseif msg == "duel" or msg == "challenge" then
    Main:Challenge()

  elseif msg:match("^duel%s") or msg:match("^challenge%s") then
    --[[ /fh duel Name (or "First Last" on Forever). The character beside you
         is challenged as the game shows them -- the address /fh duel has
         always used -- once the name has found them. ]]
    local name = raw:match("^%S+%s+(.+)$")
    local unit = name and Main:FindPlayerUnit(name)
    Main:Challenge(name, unit)

  elseif msg == "accept" then
    Main:Accept()

  elseif msg == "decline" then
    Main:Decline()

  elseif msg:match("^challenges") then
    -- /fh challenges [anyone | friends | off]: who may challenge you
    local arg = msg:match("^challenges%s+(%S+)")
    if arg == "off" or arg == "none" then arg = "nobody" end
    if arg == "friend" then arg = "friends" end
    if not arg then
      local p = Main:DuelPrivacy().policy
      Main:Print(("who may challenge you: %s. /fh challenges anyone | friends | off")
                 :format(Main.CHALLENGE_POLICY_LABEL[p] or p))
    elseif not Main:SetChallengePolicy(arg) then
      Main:Print("/fh challenges anyone | friends | off")
    end

  elseif msg:match("^block%s") then
    Main:Block(msg:match("^block%s+(%S+)"))

  elseif msg:match("^unblock%s") then
    Main:Unblock(msg:match("^unblock%s+(%S+)"))

  elseif msg == "blocked" then
    local names = {}
    for _, name in pairs(Main:DuelPrivacy().blocked) do names[#names + 1] = name end
    table.sort(names)
    Main:Print(#names == 0 and "nobody is blocked." or ("blocked: " .. table.concat(names, ", ")))

  elseif msg == "claim" then
    if not Main.session then Main:Print("no duel in progress.")
    else
      local ok, why = Main.session:ClaimVictory()
      if not ok then Main:Print("you cannot claim the win: " .. tostring(why)) end
    end

  elseif msg == "resume" then
    Main:Rejoin()

  elseif msg == "concede" then
    Main:Concede()

  elseif msg == "minimap" then
    Main:ToggleMinimapButton()

  elseif msg == "settings" or msg == "options" then
    Main:Settings()
  elseif msg:match("^debug") then
    ForeverHearthstoneDB = ForeverHearthstoneDB or {}
    local value = msg:match("^debug%s+(%S+)")
    if value == "on" then ForeverHearthstoneDB.debugMessages=true
    elseif value == "off" then ForeverHearthstoneDB.debugMessages=false end
    Main:Print("extra chat messages: "..(ForeverHearthstoneDB.debugMessages and "on" or "off")..". /fh debug on|off")
  elseif msg == "music" then
    Main:ToggleMusic()
  elseif msg == "mute" then
    Main:ToggleMute()

  elseif msg == "collection" or msg == "cards" then
    --[[ The screen, with the text report as the fallback: a frame can fail to
         build for reasons a slash command cannot, and "how far am I" should
         always be answerable. ]]
    local ok = pcall(function() Main:Collection() end)
    if not ok then Main:PrintCollection() end

  elseif msg:match("^deck") then
    Main:Deck(raw:match("^%S+%s*(.*)$"))   -- original case: "/fh deck new My Mage"

  elseif msg == "progress" then
    Main:PrintCollection()

  elseif msg:match("^icons") then
    local verdict, key = msg:match("^icons%s+(%S+)%s+(%S+)$")
    if verdict == "blank" then Main:MarkIcon(key:upper(), false)
    elseif verdict == "ok" then Main:MarkIcon(key:upper(), true)
    else Main:IconAudit() end

  elseif msg == "open" then
    Main:OpenPackRoom()   -- the reveal room, as the menu opens it

  elseif msg:match("^open") then
    Main:OpenPack(msg:match("^open%s+(%S+)") or "classic")

  elseif msg == "save" then
    if Main.rewards then Main.rewards:Save() end

  elseif msg == "drops" then
    for _, kind in ipairs({ "normal", "elite", "boss", "rare" }) do
      local per = ns.Drops.KillsPerReward(kind)
      Main:Print(("%-7s %g%%  ~%d kills each"):format(kind, ns.Drops.RATES[kind], math.floor((per or 0) + 0.5)))
    end
    Main:Print("first kill of each dungeon boss, and every raid boss: a guaranteed pack")
    local ms = {}
    for _, m in ipairs(ns.Collection.PACK_MILESTONES) do ms[#ms + 1] = ("%d:%d"):format(m.level, m.packs) end
    Main:Print("guaranteed packs by level -- " .. table.concat(ms, "  "))

  elseif msg:match("^sound") then
    --[[ WHY THE GAME IS SILENT, answered on the client that is being silent.

         Sounds resolve through SOUNDKIT, the client's OWN table of named
         constants, which cannot be read from outside the game -- so whether a
         candidate name exists is not a thing this project can know. It plays
         each match sound in turn and prints which candidate it used, so one
         command turns the whole question into a list of facts. ]]
    local report = ns.Sounds.Report()
    local silent = 0
    for i, entry in ipairs(report) do
      if entry.name then
        Main:Print(("%-13s |cff55ff55%s|r"):format(entry.key, entry.name))
      else
        silent = silent + 1
        Main:Print(("%-13s |cffff5555no candidate exists on this client|r")
                   :format(entry.key))
      end
      --[[ Staggered, or nine sounds fired in one frame are one noise. ]]
      if C_Timer and C_Timer.After then
        C_Timer.After(i * 0.45, function() ns.Sounds.Play(entry.key) end)
      else
        ns.Sounds.Play(entry.key)
      end
    end
    if silent > 0 then
      Main:Print(("%d of %d match sounds cannot play here. Tell the author these names.")
                 :format(silent, #report))
    else
      Main:Print("every match sound resolves -- you should have heard nine.")
    end

  elseif msg == "assets" then
    -- How many of the 683 art slots are filled, by tier -- and whether the
    -- game can make any noise at all.
    if Main.resolver then
      local st = Main.resolver.stats or {}
      Main:Print(("art: manifest %d, generic %d, fallback %d, override %d")
        :format(st.manifest or 0, st.generic or 0, st.fallback or 0, st.override or 0))
      local checked, total, blank = ns.GenericArt.AuditProgress(ForeverHearthstoneDB.art or {})
      Main:Print(("generic icons: %d of %d verified, %d blank -- /fh icons to check the rest")
        :format(checked, total, blank))
    end
    local have, total = ns.Sounds.Coverage()
    Main:Print(("sound: %d of %d keys resolve on this client%s")
      :format(have, total, have == 0 and " -- the game will be silent" or ""))

  elseif msg == "rewards" then
    Main:RewardHelp()   -- the Progression window: what each level and kill gives

  elseif msg == "help dev" then
    Main:Print("diagnostics: /fh save | icons | assets | sound | debug | progress (collection counts)")

  else
    -- every command a player uses; diagnostics under /fh help dev
    Main:Print("commands: /fh (main menu) | practice | difficulty [1-5] | collection | open | rewards | drops")
    Main:Print("  decks: /fh deck | deck new <name> | deck <n> | deck use <n>")
    Main:Print("  duels: /fh duel [name] | accept | decline | concede | claim | resume")
    Main:Print("  who may challenge you: /fh challenges anyone|friends|off | block <name> | unblock <name> | blocked")
    Main:Print("  window: /fh show | hide | settings | music | mute | minimap   (/fh help dev for diagnostics)")
  end
end

return Main
