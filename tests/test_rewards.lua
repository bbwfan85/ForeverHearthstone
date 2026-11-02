--[[ tests/test_rewards.lua -- WoW play turning into cards, against the stub.

  tests/test_collection.lua proves the drop RULES by rolling them a hundred
  thousand times. This proves the WIRING: that the events fire, that the kill is
  classified from the right API calls, that the XP gate is observed rather than
  computed, and that the addon is honest about SavedVariables only reaching disk
  on logout.

  The stub errors on any API that is not on the Mainline surface, so the fact
  that these run at all is most of the value.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local WOW_FILES = {
  "ForeverHearthstone/Client/Net/Transport.lua",
  "ForeverHearthstone/Client/Rewards.lua",
  "ForeverHearthstone/Client/UI/Widgets.lua",
  "ForeverHearthstone/Client/UI/Board.lua",
  "ForeverHearthstone/Client/Main.lua",
}

local function withAddon(ns, fn, opts)
  opts = opts or {}
  Stub.Install(_G)
  Stub.resting = opts.resting or false
  Stub.xp = 1000
  Stub.units = {
    player = { name = "Tester", class = "MAGE", isPlayer = true,
               level = opts.playerLevel or 30 },
    target = { name = "Gnoll", level = opts.mobLevel or 30,
               classification = opts.classification or "normal",
               creatureType = opts.creatureType or "Humanoid" },
  }
  _G.ForeverHearthstoneDB = opts.db or {}
  _G.ForeverHearthstoneCharDB = opts.cdb or {}

  for _, path in ipairs(WOW_FILES) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  local Main = ns.Main
  Main.rewards = nil
  Main.collection = nil
  Main.session = nil
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  return fn(Main, ns)
end

--- Force every eligible kill to pay, so the wiring can be tested without
--- rolling a thousand kills to see one.
local function withCertainDrops(ns, fn)
  local saved = {}
  for k, v in pairs(ns.Drops.RATES) do saved[k] = v end
  ns.Drops.RATES.normal = 100
  ns.Drops.RATES.elite  = 100
  ns.Drops.RATES.boss   = 100
  local ok, err = pcall(fn)
  for k, v in pairs(saved) do ns.Drops.RATES[k] = v end
  if not ok then error(err, 0) end
end

--- Kill the target, then let the XP window elapse.
local function kill(ns, gainXP)
  Stub.Fire("PLAYER_TARGET_DIED")
  if gainXP then
    Stub.xp = Stub.xp + 50
    Stub.Fire("PLAYER_XP_UPDATE")
  end
  Stub.Advance(1.0)
end

H.suite("rewards: an event this client lacks costs one feature, not the addon", function(ns, H)
  --[[ RegisterEvent on an unknown name is a HARD Lua error, which at login
       would take the whole addon down before the player saw anything work.
       Some of these names are genuinely unverified -- ENCOUNTER_STATE_CHANGED
       comes from platform research and has never been confirmed on a running
       client -- so the first real load must survive one of them being wrong. ]]
  withAddon(ns, function(Main, ns)
    H.ok(Main.rewards, "rewards started")
    H.eq(#Main.rewards.missingEvents, 0, "the stub models every event we ask for")

    --[[ Now prove the guard by asking for one that cannot exist. ]]
    local r = ns.Rewards.New({ collection = Main.collection,
                               onPrint = function(msg) Stub.R.chat[#Stub.R.chat+1] = msg end })
    local f = CreateFrame("Frame")
    local ok = pcall(f.RegisterEvent, f, "DEFINITELY_NOT_AN_EVENT")
    H.notOk(ok, "the client really does error on an unknown event")
    local started = pcall(function() r:Start() end)
    H.ok(started, "and starting rewards still does not throw")
  end)
end)

H.suite("rewards: the collection loads and grants at login", function(ns, H)
  withAddon(ns, function(Main)
    H.ok(Main.collection, "a collection exists")
    H.ok(Main.collection:Count("CS2_182") > 0,
         "and the Basic set was granted -- Hearthstone's own starter deck (D0)")
    H.ok(Main.collection:Count("CS2_029") > 0, "including this class's Basic cards")
  end)
end)

H.suite("rewards: a kill that grants XP can pay", function(ns, H)
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      local before = Main.collection:TotalPacks() + select(1, Main.collection:Progress())
      kill(ns, true)
      local after = Main.collection:TotalPacks() + select(1, Main.collection:Progress())
      H.ok(after > before, "something was earned")
    end)
  end)
end)

H.suite("rewards: a grey mob pays nothing, however many you kill", function(ns, H)
  --[[ THE GATE. Without it the optimal farm is a level-60 character cleaving
       level-12 mobs, which is faster per kill than anything level-appropriate.
       The XP is OBSERVED -- no XP event, no drop -- rather than computed from a
       grey-level formula recalled from memory. ]]
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      local before = Main.collection:TotalPacks()
      for _ = 1, 20 do kill(ns, false) end
      H.eq(Main.collection:TotalPacks(), before, "twenty grey kills, nothing earned")
    end)
  end)
end)

H.suite("rewards: at 60 the gate becomes the mob's level", function(ns, H)
  -- Nothing grants XP at max level, so the endgame would otherwise stop paying.
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      --[[ Counted as packs OR cards: a drop is one in five a card, and this
           test is about the GATE, not about which reward came out. ]]
      local function earned()
        return Main.collection:TotalPacks() + select(1, Main.collection:Progress())
      end
      local before = earned()
      kill(ns, false)         -- no XP event at all, and none is expected
      H.ok(earned() > before, "a level-58 mob still pays a 60")
    end)
  end, { playerLevel = 60, mobLevel = 58 })
end)

H.suite("rewards: at 60, someone else's kill on your target pays nothing", function(ns, H)
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      local function earned()
        return Main.collection:TotalPacks() + select(1, Main.collection:Progress())
      end
      Stub.units.target.tapDenied = true
      local before = earned()
      kill(ns, false)
      H.eq(earned(), before, "watching another player's mob die is not a card source")
    end)
  end, { playerLevel = 60, mobLevel = 58 })
end)

H.suite("rewards: killing another player pays nothing", function(ns, H)
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      Stub.units.target.isPlayer = true
      local before = Main.collection:TotalPacks()
      kill(ns, true)
      H.eq(Main.collection:TotalPacks(), before, "ganking is not a card source")
    end)
  end)
end)

H.suite("rewards: a critter pays nothing even with XP", function(ns, H)
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      local before = Main.collection:TotalPacks()
      kill(ns, true)
      H.eq(Main.collection:TotalPacks(), before, "trivial HP, infinite farm, no packs")
    end)
  end, { creatureType = "Critter" })
end)

H.suite("rewards: levelling grants class cards, and says so", function(ns, H)
  withAddon(ns, function(Main, ns)
    local before = 0
    for id, p in pairs(ns.PrintedCards) do
      if p.collectible and p.class == "MAGE" and Main.collection:Count(id) > 0 then
        before = before + 1
      end
    end
    Stub.units.player.level = 40
    Stub.Fire("PLAYER_LEVEL_UP", 40)
    local after = 0
    for id, p in pairs(ns.PrintedCards) do
      if p.collectible and p.class == "MAGE" and Main.collection:Count(id) > 0 then
        after = after + 1
      end
    end
    H.ok(after > before, ("%d class cards at 30, %d at 40"):format(before, after))
  end)
end)

H.suite("rewards: the unsaved warning is told, not hidden", function(ns, H)
  --[[ SavedVariables reach disk on logout or /reload and at NO other time. No
       API can force a flush, so the honest options are to count it, say it, and
       provide the reload. Pretending it is saved is not one of them. ]]
  withAddon(ns, function(Main, ns)
    Main.rewards.unsaved = 25
    Main.rewards:NagIfUnsaved()
    local said = table.concat(Stub.R.chat, " ")
    H.ok(said:find("logout") or said:find("reload"),
         "the player is told where their packs actually are")
  end)
end)

H.suite("rewards: /fh save reloads, because a reload IS the flush", function(ns, H)
  withAddon(ns, function(Main, ns)
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("save")
    H.ok(Stub.Count("ReloadUI") >= 1, "it reloaded the UI")
    H.eq(Main.rewards.unsaved, 0, "and the counter reset")
  end)
end)

H.suite("rewards: a session that ended in a crash is reported at the next login", function(ns, H)
  --[[ The player cannot be given the packs back -- they were never written.
       What they can be given is an explanation, which is the difference between
       a bug report and a shrug. ]]
  local db = { cleanExit = false }
  withAddon(ns, function(Main, ns)
    local said = table.concat(Stub.R.chat, " ")
    H.ok(said:find("without logging out"), "the crash was named: " .. said:sub(1, 120))
  end, { db = db })

  local clean = {}
  withAddon(ns, function(Main, ns)
    Stub.Fire("PLAYER_LOGOUT")
    H.eq(clean.cleanExit, true, "a real logout records that it was clean")
  end, { db = clean })
end)

H.suite("rewards: a newer save file is refused, never rewritten", function(ns, H)
  --[[ A downgrade that eats a collection is unforgivable; one that refuses to
       run is merely annoying. ]]
  withAddon(ns, function(Main, ns)
    H.eq(Main.collection, nil, "the collection was not loaded")
    local said = table.concat(Stub.R.chat, " ")
    H.ok(said:find("NEWER"), "and the player was told why: " .. said:sub(1, 100))
  end, { db = { schema = 99 } })
end)

H.suite("rewards: /fh open opens a banked pack and shows what was in it", function(ns, H)
  withAddon(ns, function(Main, ns)
    Main.collection:AddPack("CLASSIC", 1)
    local before = Main.collection:PackCount("CLASSIC")
    local chatBefore = #Stub.R.chat
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("open classic")
    H.eq(Main.collection:PackCount("CLASSIC"), before - 1, "the pack was spent")
    H.ok(#Stub.R.chat >= chatBefore + ns.Packs.SIZE, "and all five cards were named")
  end)
end)

H.suite("rewards: opening with no packs says so rather than failing", function(ns, H)
  withAddon(ns, function(Main, ns)
    -- a new character is granted packs (docs/13); spend them first
    Main.collection.account.packs.HEARTHSTONE = 0
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("open gvg")
    H.ok(table.concat(Stub.R.chat, " "):find("no HEARTHSTONE packs"), "told, not crashed")
  end)
end)

H.suite("rewards: a drop plays its choreography with no board on screen", function(ns, H)
  --[[ A drop happens in the open world, usually mid-fight, with no card game on
       screen at all. That is the NORMAL case, so the toast has to run against
       nothing -- which is what Choreography's null-safe stage is for. ]]
  withAddon(ns, function(Main, ns)
    H.eq(Main.board, nil, "no board exists")
    withCertainDrops(ns, function()
      local ok, err = pcall(kill, ns, true)
      H.ok(ok, "the drop toast ran anyway: " .. tostring(err))
    end)
    H.ok(Main.toastPlaying, "and a timeline is actually running")
    --[[ AND IT MUST BE VISIBLE. Driving the toast into a null stage would run
         the whole sequence perfectly and show the player nothing, which is
         exactly what happened before there was a world stage. ]]
    H.ok(Main.worldStage, "a stage was made for it")
    H.ok(Main.worldStage.toastWidget.frame:IsShown(), "and the toast is on screen")
    Stub.Advance(5.0)          -- let it finish; nothing should error
    H.notOk(Main.worldStage.toastWidget.frame:IsShown(),
            "then it leaves on its own, without being clicked")
  end)
end)

--============================================================ generic art

H.suite("art: the generic manifest covers every card in the pool", function(ns, H)
  --[[ The point of ~20 entries: 683 art slots and not one question mark, so the
       game looks deliberate rather than unfinished. ]]
  local r = ns.Resolver.New({ printed = ns.PrintedCards,
                              manifest = ns.GenericArt.Manifest({}) })
  local fallbacks = {}
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible then
      local d = r:Card(id)
      if d.tier == "fallback" then fallbacks[#fallbacks + 1] = id end
    end
  end
  H.eq(#fallbacks, 0, "no collectible card falls through to the question mark")
end)

H.suite("art: a card's race beats its type", function(ns, H)
  -- A row of Beasts that all look like beasts reads instantly; a row of
  -- identical generic minions reads as nothing.
  local r = ns.Resolver.New({ printed = ns.PrintedCards,
                              manifest = ns.GenericArt.Manifest({}) })
  r.manifest.cards = {} -- Exercise fallback without the bundled illustrations.
  local beast = r:Card("CS2_172")                 -- Bloodfen Raptor, BEAST
  H.eq(beast.icon, ns.GenericArt.CANDIDATES.RACE_BEAST, "a Beast gets the beast icon")
  local plain = r:Card("CS2_182")                 -- Chillwind Yeti, no race
  H.eq(plain.icon, ns.GenericArt.CANDIDATES.MINION, "a raceless minion gets the minion icon")
end)

H.suite("art: an icon marked blank is DELETED, so the chain falls through", function(ns, H)
  --[[ Not replaced with the question mark: a blank Mage icon should fall
       through to the minion icon, which is what deleting the entry does for
       free. ]]
  local saved = {}
  ns.GenericArt.Mark(saved, "RACE_BEAST", false)
  local r = ns.Resolver.New({ printed = ns.PrintedCards,
                              manifest = ns.GenericArt.Manifest(saved) })
  r.manifest.cards = {}
  local beast = r:Card("CS2_172")
  H.eq(beast.icon, ns.GenericArt.CANDIDATES.MINION,
       "the beast falls through to the minion icon, not to a question mark")
  H.eq(beast.tier, "generic", "and is still a generic hit")
end)

H.suite("art: the audit knows what has been checked and what has not", function(ns, H)
  local saved = {}
  local checked, total, blank = ns.GenericArt.AuditProgress(saved)
  H.eq(checked, 0, "nothing checked to begin with")
  H.ok(total >= 15, ("%d candidates to check"):format(total))
  ns.GenericArt.Mark(saved, "MINION", true)
  ns.GenericArt.Mark(saved, "RACE_PIRATE", false)
  checked, total, blank = ns.GenericArt.AuditProgress(saved)
  H.eq(checked, 2, "two checked")
  H.eq(blank, 1, "one of which was blank")

  local list = ns.GenericArt.AuditList(saved)
  H.ok(#list == total, "the list is the whole set")
  for _, e in ipairs(list) do
    H.ok(e.describe and #e.describe > 0, e.key .. " says what it is for in words")
  end
end)

H.suite("art: a hand-supplied path beats our guess", function(ns, H)
  local saved = { generic = { MINION = [[Interface\Icons\MY_OWN_ICON]] } }
  local m = ns.GenericArt.Manifest(saved)
  H.eq(m.generic.MINION, [[Interface\Icons\MY_OWN_ICON]], "the player's path wins")
  H.eq(m.generic.SPELL, ns.GenericArt.CANDIDATES.SPELL, "and the rest are untouched")
end)

H.suite("vault: the collection survives logout sealed, and comes back at login", function(ns, H)
  local db, cdb = {}, {}
  withAddon(ns, function(Main)
    Main.collection:AddPack("HEARTHSTONE", 7)
    Main.collection.account.dust = 777
    Stub.Fire("PLAYER_LOGOUT")
  end, { db = db, cdb = cdb })
  H.ok(db.vault and db.vault.sig, "the account data went to disk sealed")
  H.eq(db.dust, nil, "with no plain copy to edit")
  db.dust = 99999   -- a Notepad edit
  withAddon(ns, function(Main)
    H.eq(Main.collection:Dust(), 777, "the next login has the real dust")
    H.ok(Main.collection:TotalPacks() >= 7, "and the packs")
  end, { db = db, cdb = cdb })
end)

--============================================================ docs/28

H.suite("rewards: a drop is shown on screen even after a match has been played", function(ns, H)
  --[[ The board is kept, hidden, after your first match, and drops used its
       stage whenever it existed -- so every later drop toasted inside a
       hidden window. ]]
  withAddon(ns, function(Main, ns)
    Main:StartPractice("MAGE", "WARRIOR")
    Main.board:Hide()
    withCertainDrops(ns, function() kill(ns, true) end)
    H.ok(Main.worldStage and Main.worldStage.toastWidget.frame:IsShown(), "the toast is on the screen")
    H.notOk(Main.board.toast.frame:IsShown(), "not in the hidden board")
    local t = Main.worldStage.toastWidget
    H.ok((t.title:GetText() or "") ~= "" and (t.sub:GetText() or "") ~= "", "it says what dropped")
  end)
end)

H.suite("rewards: several drops at once are shown one after another", function(ns, H)
  withAddon(ns, function(Main, ns)
    Main:OnReward({ kind = "PACK", set = "HEARTHSTONE", total = 4 })
    Main:OnReward({ kind = "CARD", cardId = "CS2_182", rarity = "COMMON" })
    local t = Main.worldStage.toastWidget
    H.ok(t.title:GetText():find("pack", 1, true), "the pack first: " .. t.title:GetText())
    H.eq(#Main.toastQueue, 1, "the card waits its turn")
    Stub.Advance(3.8)
    H.eq(t.title:GetText(), ns.PrintedCards["CS2_182"].name, "then the card")
    Stub.Advance(6)
    H.notOk(t.frame:IsShown(), "and then both are gone")
  end)
end)

H.suite("rewards: clicking a pack toast opens the pack room", function(ns, H)
  withAddon(ns, function(Main, ns)
    Main:OnReward({ kind = "PACK", set = "HEARTHSTONE", total = 2 })
    Main.worldStage.toastWidget.frame:Click()
    H.ok(Main.collectionUI and Main.collectionUI:IsShown(), "the collection opened")
    H.ok(Main.collectionUI.packRoom, "at the packs")
  end)
end)

H.suite("rewards: a raid boss inside an instance pays its Naxxramas card once", function(ns, H)
  withAddon(ns, function(Main, ns)
    _G.IsInInstance = function() return true, "raid" end
    local calls = {}
    local realRoll = ns.Drops.Roll
    ns.Drops.Roll = function(k, ...) calls[#calls + 1] = k.kind; return nil end
    Stub.Fire("PLAYER_TARGET_DIED")
    Stub.Advance(1)
    ns.Drops.Roll = realRoll
    _G.IsInInstance = nil
    H.eq(calls[1], "elite", "the kill itself counts as an elite; ENCOUNTER_END pays the boss")
  end, { playerLevel = 60, mobLevel = -1, classification = "worldboss" })
end)

H.suite("rewards: the bad-luck floor is kept with the character", function(ns, H)
  withAddon(ns, function(Main, ns)
    local ch = Main.collection.character
    ch.dryKills = ns.Drops.DRY_LIMIT
    local packs = Main.collection:TotalPacks()
    local cards = Main.collection.account.stats.cardsDropped or 0
    kill(ns, true)
    H.eq(ch.dryKills, 0, "the owed drop paid and the dry spell reset")
    H.ok(Main.collection:TotalPacks() > packs or (Main.collection.account.stats.cardsDropped or 0) > cards,
         "something dropped")
  end)
end)

H.suite("rewards: late installation grants all level 60 milestones once",function(ns,H)
  withAddon(ns,function(Main)
    local c=Main.collection
    H.eq(c:TotalPacks(),16)
    for _,entry in ipairs(c:ClassCurve("MAGE")) do
      H.ok(c:Count(entry.id)>0,entry.id.." granted at installation")
    end
    H.eq(#c:GrantForLevel("MAGE",60),0)
    H.eq(c:GrantPacksForLevel(60),0)
    H.eq(c:TotalPacks(),16)
  end,{playerLevel=60})
end)

H.suite("practice: a mismatched supplied deck cannot put Jaraxxus in a Mage deck",function(ns,H)
  withAddon(ns,function(Main)
    Main:StartPractice("MAGE","MAGE",nil,ns.BotDecks.Pick("WARLOCK",5),5)
    H.eq(Main.botDeck.class,"MAGE")
    local p=Main.game.players[2]
    H.eq(p.class,"MAGE")
    for _,zone in ipairs({p.deck,p.hand}) do
      for _,e in ipairs(zone) do
        H.ok(e.printed.class=="MAGE" or e.printed.class=="NEUTRAL")
      end
    end
  end)
end)

H.suite("rewards: level milestone packs have a visible toast and level reward summary",function(ns,H)
  withAddon(ns,function(Main)
    local before=Main.collection:TotalPacks()
    local chat=#Stub.R.chat
    Main.rewards:OnLevelUp(30)
    H.eq(Main.collection:TotalPacks(),before+2)
    H.ok(Main.worldStage.toastWidget.frame:IsShown())
    H.eq(Main.worldStage.toastKind,"pack")
    H.eq(Main.worldStage.toastWidget.title:GetText(),"Level reward: 2 packs!")
    H.eq(#Stub.R.chat,chat+1,"level rewards are printed automatically")
    Stub.Advance(15)
    Main.rewards:OnLevelUp(31)
    H.eq(Main.collection:TotalPacks(),before+2,"non-milestone level grants no pack")
    ForeverHearthstoneDB.debugMessages=true
    Main:Debug("diagnostic")
    H.eq(#Stub.R.chat,chat+3)
  end,{playerLevel=29})
end)

H.suite("rewards: pack drops bank and announce without a click",function(ns,H)
  withAddon(ns,function(Main)
    local before=Main.collection:TotalPacks()
    withCertainDrops(ns,function()
      Main.rewards:Resolve({kind="normal",playerLevel=60,mobLevel=60})
    end)
    H.eq(Main.collection:TotalPacks(),before+1)
    H.ok(Main.worldStage.toastWidget.frame:IsShown())
    H.eq(Main.worldStage.toastWidget.hint:GetText(),"Added automatically")
    H.ok(table.concat(Stub.R.chat," "):find("Pack found! Added automatically",1,true))
    Stub.Advance(15)
    H.eq(Main.collection:TotalPacks(),before+1,"dismissing the toast never spends the pack")
  end)
end)

H.suite("rewards: a kill inside an instance, where unit reads are secret", function(ns, H)
  --[[ Midnight's disarmament (live in Forever) answers unit reads in instances
       with secret values. Indexing rolled[] with a secret GUID, or comparing a
       secret classification, was the reported "small error in instances". The
       kill must still pay -- once, though both kill events fire for it. ]]
  withAddon(ns, function(Main, ns)
    withCertainDrops(ns, function()
      local t = Stub.units.target
      t.guid, t.classification, t.level = Stub.Secret(), Stub.Secret(), Stub.Secret()
      t.tapDenied, t.isPlayer, t.creatureType = Stub.Secret(), Stub.Secret(), Stub.Secret()
      local function earned()
        return Main.collection:TotalPacks() + select(1, Main.collection:Progress())
      end
      local before = earned()
      local ok, err = pcall(function()
        Stub.Fire("PLAYER_TARGET_DIED")
        Stub.Fire("PARTY_KILL", "Player-1-0001", Stub.Secret())
        Stub.xp = Stub.xp + 50
        Stub.Fire("PLAYER_XP_UPDATE")
        Stub.Advance(1.0)
      end)
      H.ok(ok, "no error from secret unit reads: " .. tostring(err))
      H.eq(earned(), before + 1, "the kill paid exactly once, with nothing to key on")
      for k in pairs(Main.rewards.rolled or {}) do
        H.notOk(issecretvalue(k), "a secret never becomes a table key")
      end

      kill(ns, true)
      H.eq(earned(), before + 2, "the next kill, a moment later, is its own")
    end)
  end)
end)
