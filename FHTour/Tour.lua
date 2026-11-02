--[[ FHTour/Tour.lua -- every screen, photographed by the real client.

  The offline previews (tools/collection_preview.*) draw the frame tree with
  Pillow, which is why "a lot of things are just slightly off in game" never
  showed up in them: they cannot know WoW's fonts, wrapping, filtering or UI
  scale. This walks the same scenes inside the client and calls Screenshot()
  at each, so what gets judged is exactly what a player sees.

  DEVELOPER ONLY. It is its own addon folder, never packaged
  (tools/package_release.py ships ForeverHearthstone/ alone), and the main
  addon only hands it the namespace if it happens to be installed.

  ============================================================ THE SANDBOX

  The scenes open packs, build twelve decks and disenchant a card. None of
  that may touch the player's collection, so the tour runs against deep copies
  of both SavedVariables tables and a Collection built on them; the originals
  are never handed to anything. They are put back at the end, and ALSO on
  PLAYER_LOGOUT -- a /reload mid-tour writes whatever the globals hold, and
  that must be the untouched originals.

  ============================================================ FOREVER

  Retail is the test client; Forever is the target, and its API is most but
  not all of Mainline. Everything here that is not the addon's own code is
  looked up with rawget and skipped if absent, so the tour degrades on a
  client that lacks something instead of erroring.
]]
local Tour = { shots = {}, errors = {} }
FHTour = Tour

local MAX_SECONDS = 9 * 60        -- watchdog: the sandbox is always restored
local LIVE_SHOTS = 14             -- photographs of the self-playing match
local LIVE_SECONDS = 240

local function after(sec, fn) C_Timer.After(sec, fn) end

local function deepcopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local t = {}
  seen[v] = t
  for k, x in pairs(v) do t[deepcopy(k, seen)] = deepcopy(x, seen) end
  return t
end

function Tour:Say(msg) print("|cff66ccffFHTour|r " .. msg) end

function Tour:Fail(where, err)
  self.errors[#self.errors + 1] = { where = where, err = tostring(err) }
  self:Say(("|cffff6060%s failed:|r %s"):format(where, tostring(err)))
end

-- ============================================================ sandbox

function Tour:Point(collection)
  local M = self.Main
  M.collection = collection
  if M.rewards then M.rewards.collection = collection end
  if M.collectionUI then M.collectionUI.collection = collection end
end

function Tour:EnterSandbox()
  local M = self.Main
  self.saved = { db = ForeverHearthstoneDB, cdb = ForeverHearthstoneCharDB,
                 collection = M.collection, paused = M.PracticePaused }
  ForeverHearthstoneDB = deepcopy(self.saved.db or {})
  ForeverHearthstoneCharDB = deepcopy(self.saved.cdb or {})
  self:Point(self.ns.Collection.New(ForeverHearthstoneDB, ForeverHearthstoneCharDB))
end

function Tour:LeaveSandbox()
  local s = self.saved
  if not s then return end
  self.saved = nil
  local M = self.Main
  ForeverHearthstoneDB, ForeverHearthstoneCharDB = s.db, s.cdb
  M.PracticePaused = s.paused
  self:Point(s.collection)
  if M.hub then M.hub.botMode, M.hub.chooseDeck, M.hub.selectedDeck = false, false, false end
end

-- hide every window the tour opened, so each scene starts from the world
function Tour:Clear()
  local M = self.Main
  pcall(function() if M.collectionUI then M.collectionUI:Hide() end end)
  pcall(function() if M.hub then M.hub:Hide() end end)
  pcall(function() if M.settings then M.settings:Hide() end end)
  pcall(function() if M.board then M.board:HideTooltip(); M.board:Hide() end end)
end

-- ============================================================ the camera

function Tour:Allowed(name)
  local only = rawget(_G, "FHTOUR_ONLY")
  if type(only) ~= "table" then return true end
  for _, part in ipairs(only) do
    if name:find(part, 1, true) then return true end
  end
  return false
end

--[[ THE LABEL. WoW names a screenshot by its timestamp, and the manifest only
     reaches disk at the NEXT reload, so each photograph carries its own name:
     a strip of squares in the top-left corner -- a magenta marker, then 16
     bits of Tour.Hash(name), white for 1 -- shown only for the capture.
     tools/tour_collect.py reads it back and paints the strip out before
     anything is judged. ]]
Tour.LABEL_PX, Tour.LABEL_BITS = 10, 16

function Tour.Hash(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 65521 end
  return h
end

function Tour:Label(name)
  if not self.label then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("TOOLTIP"); f:SetFrameLevel(9000)
    f.squares = {}
    for i = 0, Tour.LABEL_BITS do
      f.squares[i] = f:CreateTexture(nil, "OVERLAY")
    end
    self.label = f
  end
  local f = self.label
  local _, physH = 0, 0
  if GetPhysicalScreenSize then _, physH = GetPhysicalScreenSize() end
  local unitsH = UIParent:GetHeight()
  local px = (physH and physH > 0 and unitsH and unitsH > 0) and (unitsH / physH) or 1
  local side = Tour.LABEL_PX * px
  f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
  f:SetSize(side * (Tour.LABEL_BITS + 1), side)
  local h = Tour.Hash(name)
  for i = 0, Tour.LABEL_BITS do
    local t = f.squares[i]
    t:ClearAllPoints(); t:SetSize(side, side)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", i * side, 0)
    if i == 0 then t:SetColorTexture(1, 0, 1, 1)
    else
      local bit = math.floor(h / 2 ^ (Tour.LABEL_BITS - i)) % 2
      t:SetColorTexture(bit, bit, bit, 1)
    end
  end
  f:Show()
end

function Tour:Shoot(name, done)
  local shot = rawget(_G, "Screenshot")
  if not shot or not self:Allowed(name) then return done() end
  -- the previous capture's "Screen captured" line must not be in this one
  local status = rawget(_G, "ActionStatus")
  if status and status.Hide then pcall(status.Hide, status) end
  local entry = { i = #self.shots + 1, name = name, at = date("%m%d%y_%H%M%S"), time = time() }
  self.shots[#self.shots + 1] = entry
  self.waiting = { entry = entry, done = done }
  pcall(function() self:Label(name) end)
  shot()
  after(5, function()
    if self.waiting and self.waiting.entry == entry then self:Captured(false) end
  end)
end

function Tour:Captured(ok)
  local w = self.waiting
  if not w then return end
  self.waiting = nil
  w.entry.ok = ok
  if self.label then self.label:Hide() end
  after(0.35, w.done)
end

-- ============================================================ the run

--[[ A scene is { name, fn, wait, pre }: wait `pre`, run fn, let it settle for
     `wait`, photograph it as `name`. A scene without a name only sets up. A
     scene with `live` runs its own loop and calls back when finished. ]]
function Tour:Play(scenes, i)
  if self.finished then return end
  local s = scenes[i]
  if not s then return self:Finish() end
  local nextScene = function() self:Play(scenes, i + 1) end
  after(s.pre or 0, function()
    if self.finished then return end
    if s.live then
      local ok, err = pcall(s.live, nextScene)
      if not ok then self:Fail(s.name or "live", err); nextScene() end
      return
    end
    local ok, err = pcall(s.fn)
    if not ok then self:Fail(s.name or ("setup " .. i), err) end
    after(s.wait or 0.6, function()
      if self.finished then return end
      if s.name and ok then self:Shoot(s.name, nextScene) else nextScene() end
    end)
  end)
end

function Tour:Start(manual)
  if self.running then return self:Say("already running.") end
  local M = self.Main
  if not (M and M.collection) then return self:Say("no collection loaded; nothing to photograph.") end
  if M.session and M.session.IsActive and M.session:IsActive() then
    return self:Say("finish your duel first.")
  end
  self.running, self.finished = true, false
  self.shots, self.errors = {}, {}
  self.run = rawget(_G, "FHTOUR_RUN")
  self.startedAt = time()
  self:Say(("run %s: photographing every screen. Hands off for a few minutes."):format(tostring(self.run)))
  local ok, err = pcall(function() self:EnterSandbox() end)
  if not ok then self.running = false; return self:Fail("sandbox", err) end
  self:Clear()
  after(MAX_SECONDS, function()
    if self.running and self.startedAt and time() - self.startedAt >= MAX_SECONDS - 1 then
      self:Fail("watchdog", "tour exceeded " .. MAX_SECONDS .. "s")
      self:Finish()
    end
  end)
  self:Play(self:Scenes(), 1)
end

function Tour:Finish()
  if self.finished then return end
  self.finished = true
  local M = self.Main
  pcall(function() if M.game and not M.game.over then M:ConcedeMatch() end end)
  self:Clear()
  pcall(function() self:LeaveSandbox() end)
  self.running = false
  FHTourDB = FHTourDB or {}
  FHTourDB.lastRun = self.run
  FHTourDB.runs = FHTourDB.runs or {}
  FHTourDB.runs[tostring(self.run)] = {
    run = self.run, started = self.startedAt, finished = time(),
    build = { GetBuildInfo and GetBuildInfo() },
    screen = { GetPhysicalScreenSize and GetPhysicalScreenSize() },
    uiScale = UIParent and UIParent:GetEffectiveScale(),
    shots = self.shots, errors = self.errors,
  }
  self:Say(("done: %d screenshots, %d errors. /reload saves the manifest.")
           :format(#self.shots, #self.errors))
end

-- ============================================================ the scenes

function Tour:Scenes()
  local ns, M = self.ns, self.Main
  local class = M:PlayerClass()
  local ui, deckIndex, b
  local function board() b = M.board; return b end

  local S = {}
  local function add(name, fn, wait, pre) S[#S + 1] = { name = name, fn = fn, wait = wait, pre = pre } end

  -- ---------------------------------------------------------- menus
  add("hub", function() M:ShowHub() end, 1.2)
  add("practice-new", function() M.hub.buttons[1]:Click() end, 0.8)
  add("practice-decks", function() M.hub.play:Click() end, 0.8)
  add("collection", function() M.hub:Hide(); ui = M:Collection(true) end, 2.0)
  add("collection-page-two", function() ui:TurnPage(1) end, 1.5)
  add("deck-edit", function()
    local deck
    deck, deckIndex = M.collection:NewDeck("Tour Deck", class)
    for _, entry in ipairs(ui:Entries()) do
      if #deck.cards < 24 then deck.cards[#deck.cards + 1] = entry.cardId end
    end
    ui:EditDeck(deckIndex)
  end, 1.5)
  add("deck-hover", function() ui.menuItems[1]:GetScript("OnEnter")(ui.menuItems[1]) end, 0.6)
  add(nil, function() ui.menuItems[1]:GetScript("OnLeave")(ui.menuItems[1]) end, 0.1)
  add("decks-browser", function()
    -- real players' decks differ, so these do too: a few class/neutral
    -- non-Basic cards each, which is what gives a deck box its own face
    local pool = {}
    for _, e in ipairs(M.collection:Browse({ all = true })) do
      local p = ns.PrintedCards[e.cardId]
      if p and (p.class == class or p.class == "NEUTRAL") and p.rarity ~= "FREE" then pool[#pool + 1] = e.cardId end
    end
    for i = 2, 12 do
      local d = M.collection:NewDeck("Tour deck number " .. i, class)
      for k = 0, 4 do
        local id = #pool > 0 and pool[((i * 37 + k * 11) % #pool) + 1]
        if id then d.cards[#d.cards + 1] = id end
      end
    end
    ui:ShowDecks()
  end, 1.0)
  add("pack-room", function() ui:ShowPackRoom() end, 1.5)
  add("pack-open-start", function()
    M.collection:AddPack("CLASSIC", 1)
    ui:OpenPack("CLASSIC")
    -- a real legendary in slot 4, so the legendary shots show one
    local c = ui.pack.cards[4]
    c.cardId, c.rarity, c.golden = "EX1_016", "LEGENDARY", false
    ui:Relayout()
  end, 0.4)
  add("pack-open-landed", function() end, 1.8)
  add("pack-hover-legendary", function()
    local slot = ui.slots and ui.slots[4]
    local fr = slot and slot.widget and slot.widget.frame
    local enter = fr and fr.GetScript and fr:GetScript("OnEnter")
    if enter then enter(fr) end
  end, 0.8)
  add("pack-reveal-legendary", function() ui:RevealCard(4) end, 0.35)
  add("pack-reveal-legendary-settled", function() end, 1.2)
  add("pack-reveal-all", function()
    for i = 1, 5 do if i ~= 4 then ui:RevealCard(i) end end
  end, 1.6)
  add("disenchant-confirm", function()
    ui:Show(); ui:EditDeck(deckIndex)
    M.collection:Add("EX1_116", 1)
    for _, entry in ipairs(M.collection:Browse({ all = true })) do
      if entry.cardId == "EX1_116" then ui:OnCardClick(entry, "RightButton"); break end
    end
    ui:DisenchantSelected()
  end, 0.8)
  add(nil, function()
    if ui.disenchantDialog then ui.disenchantDialog:Hide() end
    ui.selected = nil
    if ui.inspect then ui.inspect.frame:Hide() end
    ui:Hide()
  end, 0.2)
  add("settings-track", function() M:Settings("track") end, 1.0)
  add("settings-odds", function() M:Settings("odds") end, 0.8)
  add("settings-general", function() M:Settings("general") end, 0.8)
  add(nil, function() M.settings:Hide() end, 0.2)

  -- ---------------------------------------------------------- world toasts
  add("toast-pack", function()
    M.toastQueue = {}; M.toastPlaying = nil
    M:OnReward({ kind = "PACK", set = "HEARTHSTONE", total = 3 })
  end, 1.0)
  add("toast-card", function()
    M:OnReward({ kind = "CARD", cardId = "FP1_031", rarity = "LEGENDARY", set = "NAXX" })
  end, 1.0, 4.5)

  -- ---------------------------------------------------------- the table, posed
  --[[ A real practice match is started for the board, then held still
       (PracticePaused) while scripted snapshots are painted on it -- the same
       states tools/collection_preview.lua poses, so offline and live compare. ]]
  --[[ Matches start the way a player starts one: Play Bots, Play (the deck
       book opens with a deck chosen), Play again. Calling StartPractice
       directly left the hub's deck book drawn over the whole match in run 1. ]]
  local function fromHub(name, pre)
    add(nil, function()
      self:Clear(); M:ShowHub()
      M.hub.botMode, M.hub.chooseDeck, M.hub.selectedDeck = false, false, false
      M.hub:Layout(); M.hub.buttons[1]:Click()
    end, 0.8, pre)
    add(nil, function() M.hub.play:Click() end, 0.8)
    add(name, function() M.hub.play:Click() end, 3.0)
  end
  fromHub("board-mulligan", 4.0)
  add(nil, function()
    M:OnIntent({ kind = "CONFIRM_MULLIGAN" })
    M.PracticePaused = function() return true end
  end, 2.5)
  local function settle() if b.emoteMenu then b.emoteMenu:Hide() end; b.banner:Hide() end
  add("board-states", function()
    board():SetSnapshot({hand={'EX1_298','CS2_182','NEW1_030'},board={'EX1_298','CS2_179','EX1_012','CS2_182'},
      foeBoard={'EX1_559','CS2_231','EX1_593','EX1_390'},foeHandCount=4,maxMana=10,mana=10,foeMaxMana=10,myTurn=true,player=1,
      boardStats={{atk=8,health=8,frozen=true},{atk=0,health=3,taunt=true,divineShield=true},
       {atk=4,health=4,deathrattle=true},{atk=4,health=5,sleeping=true,trigger=true}},
      foeBoardStats={{atk=1,health=7,trigger=true,stealth=true},{atk=1,health=1,silenced=true},
       {atk=4,health=4,immune=true},{atk=4,health=2,enraged=true,damaged=true}},
      deckCount=30,foeDeckCount=6,hero={cardId='HERO_03',health=30,armor=0,atk=0},foeHero={cardId='HERO_08',health=22,frozen=true},
      heroPower={cardId='CS2_083b',cost=2,used=true},foeHeroPower={cardId='CS2_034',cost=2},
      secrets={{cardId='EX1_287',name='Counterspell'}},foeSecretCount=2})
  end, 3.0)
  add(nil, settle, 0.3)
  add("board-hero-power-tooltip", function() b:ShowDescription(b.foeHeroPower.frame, "CS2_034") end, 0.6)
  add(nil, function() b:HideTooltip() end, 0.1)
  add("board-full-hand", function()
    b:SetSnapshot({hand={'EX1_298','CS2_182','NEW1_030','CS2_029','CS2_032','EX1_277','CS2_179','EX1_012','CS2_231','EX1_593'},
      board={'CS2_182','CS2_179','EX1_012','CS2_231','EX1_593','EX1_390','EX1_298'},
      foeBoard={'EX1_559','CS2_231','EX1_593','EX1_390','CS2_182','CS2_179','EX1_012'},foeHandCount=10,maxMana=10,mana=3,foeMaxMana=10,myTurn=true,player=1,
      deckCount=4,foeDeckCount=0,hero={cardId='HERO_03',health=7,armor=5},foeHero={cardId='HERO_08',health=1},
      heroPower={cardId='CS2_083b',cost=2},foeHeroPower={cardId='CS2_034',cost=2}})
  end, 3.0)
  add(nil, settle, 0.3)
  local base={hand={'CS2_029','CS2_032','EX1_277'},board={'CS2_182','CS2_179'},foeBoard={'EX1_559','CS2_231','EX1_593'},
    foeHandCount=4,maxMana=7,mana=7,myTurn=false,player=1,deckCount=20,foeDeckCount=20,
    boardStats={{instanceId=11,atk=4,health=5},{instanceId=12,atk=0,health=3}},
    foeBoardStats={{instanceId=21,atk=1,health=7},{instanceId=22,atk=1,health=1},{instanceId=23,atk=4,health=4}},
    hero={cardId='HERO_08',health=30},foeHero={cardId='HERO_01',health=18},heroId=1,foeHeroId=2,foeMaxMana=7,
    heroPower={cardId='CS2_034',cost=2},foeHeroPower={cardId='CS2_102',cost=2}}
  local function snap(extra)
    local s = {}
    for k, v in pairs(base) do s[k] = v end
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
  end
  -- your turn with 7 mana: every card in hand is playable and glows, as in play
  local mine = { myTurn = true, playable = { true, true, true }, affordable = { true, true, true } }
  add("match-turn-banner", function()
    b:ResetMatch(); b:SetSnapshot(snap()); b:SetSnapshot(snap(mine))
  end, 0.35)
  add("match-turn-banner-settled", function() end, 0.6)
  add("match-emotes", function() b:ToggleEmotes() end, 1.6)
  add(nil, function() b.emoteMenu:Hide() end, 0.2)
  add("match-spells", function()
    b:SpellEffect({ cardId = "CS2_032", mine = true })
    b:SpellEffect({ cardId = "CS2_029", mine = true, targeted = true, targetSide = "foe", targetIsHero = true })
  end, 0.2)
  add("match-holy-nova", function() b:SpellEffect({ cardId = "CS1_112", mine = true }) end, 0.25, 1.0)
  add("match-hero-cracking", function()
    b:SetSnapshot(snap({ myTurn = true, over = true, winner = 1, foeHero = { cardId = "HERO_01", health = 0 } }))
  end, 0.6, 1.0)
  add("match-hero-shatter", function() end, 0.55)
  add("match-postgame", function() end, 2.2)
  add("board-minion-hover", function()
    b:ResetMatch()
    b:SetSnapshot({hand={},board={'CS2_182'},foeBoard={},myTurn=true,boardStats={{instanceId=77,atk=8,health=2,maxHealth=7,damaged=true}},
      hero={cardId='HERO_08',health=30},foeHero={cardId='HERO_01',health=30},maxMana=5,mana=5,foeMaxMana=5,
      heroPower={cardId='CS2_034',cost=2},foeHeroPower={cardId='CS2_102',cost=2}})
  end, 1.5)
  add("board-minion-hover-tip", function() b.myMinions[1].frame:GetScript("OnEnter")(b.myMinions[1].frame) end, 0.6)
  add(nil, function()
    b:HideTooltip()
    M.PracticePaused = self.saved.paused
    pcall(function() M:ConcedeMatch() end)
    b:Hide()
  end, 1.0)

  -- ---------------------------------------------------------- a real match
  fromHub(nil, 1.0)
  S[#S + 1] = { name = "live", live = function(done) self:LiveMatch(done) end }
  return S
end

--[[ THE MATCH PLAYS ITSELF. The bot already plays player 2; player 1 is
     driven by the same AI through the same Animated wrapper the bot uses, so
     every move animates as a click would. Photographs land at seeded-random
     moments, which is what "random game moments" means without making two
     runs incomparable. ]]
function Tour:LiveMatch(done)
  local ns, M = self.ns, self.Main
  local rng = (FHTOUR_RUN or 1) * 7919
  local function rand(lo, hi) rng = (rng * 1103515245 + 12345) % 2147483648; return lo + (rng % 1000) / 1000 * (hi - lo) end
  local started, shots, nextShot, blocked, ended = time(), 0, GetTime() + 3.5, {}, nil
  local opts = { difficulty = M:BotDifficulty() }
  local ticker
  local function finish()
    if ticker then ticker:Cancel(); ticker = nil end
    done()
  end
  ticker = C_Timer.NewTicker(0.6, function()
    if self.finished then return finish() end
    local g = M.game
    if not g then return finish() end
    if g.over then
      if not ended then
        ended = GetTime()
        after(1.6, function() self:Shoot("live-result", function()
          after(2.5, function() self:Shoot("live-result-settled", finish) end) end) end)
      end
      return
    end
    if self.waiting then return end
    if GetTime() >= nextShot and shots < LIVE_SHOTS then
      shots = shots + 1
      nextShot = GetTime() + rand(4, 9)
      self:Shoot(("live-%02d"):format(shots), function() end)
      return
    end
    if time() - started > LIVE_SECONDS or (shots >= LIVE_SHOTS and GetTime() >= nextShot) then
      pcall(function() M:ConcedeMatch() end)
      return
    end
    if M.board and M.board.presentationLocked then return end
    if g:AwaitingMulligan(1) then M:OnIntent({ kind = "CONFIRM_MULLIGAN" }); return end
    if g.phase ~= "PLAY" or g.activePlayer ~= 1 then blocked = {}; return end
    local ok, action = pcall(ns.AI.NextAction, g, 1, blocked, opts)
    if not ok then self:Fail("live AI", action); action = nil end
    if action then
      local done2, why = M:Animated(g, 1, function(a) return ns.Actions.Run(g, 1, a) end)(action)
      if not done2 and why ~= "animation in progress" and action._key then blocked[action._key] = true end
      M.controller:Changed()
    else
      M:OnIntent({ kind = "END_TURN" })
    end
  end)
end

-- ============================================================ wiring

local f = CreateFrame("Frame")
for _, e in ipairs({ "SCREENSHOT_SUCCEEDED", "SCREENSHOT_FAILED", "PLAYER_LOGOUT" }) do
  pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
  if event == "SCREENSHOT_SUCCEEDED" then Tour:Captured(true)
  elseif event == "SCREENSHOT_FAILED" then Tour:Captured(false)
  elseif event == "PLAYER_LOGOUT" then pcall(function() Tour:LeaveSandbox() end) end
end)

--[[ Called by Client/Main.lua at PLAYER_LOGIN when this addon is present. ]]
function FHTour_Attach(ns, Main)
  Tour.ns, Tour.Main = ns, Main
  FHTourDB = FHTourDB or {}
  if rawget(_G, "FHTOUR_RUN") and FHTourDB.lastRun ~= FHTOUR_RUN then
    after(6, function() Tour:Start(false) end)
  end
end

SLASH_FHTOUR1 = "/fhtour"
SlashCmdList.FHTOUR = function(msg)
  msg = (msg or ""):lower()
  if msg == "stop" then Tour:Fail("stopped", "by /fhtour stop"); Tour:Finish()
  else Tour:Start(true) end
end
