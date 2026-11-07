--[[ tests/test_transport.lua -- the WoW half of networking, against the stub.

  tests/test_net.lua plays whole matches between two sessions with a table for a
  wire, and proves the protocol. It cannot prove that anything reaches WoW.

  This file is the pre-flight for that: the prefix is registered, the right
  event is listened for, outgoing messages are queued and paced rather than
  fired inline, a message from a stranger becomes a challenge and a message
  from a third party during a duel does not. The stub errors on any API that
  does not exist on the Mainline surface, so simply running this proves the
  calls are real ones.

  WHAT IT STILL CANNOT PROVE: that SendAddonMessage delivers. Nothing headless
  can. That is what the beta is for.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

H.suite('transport: prefix registration handles boolean and enum return values',function(ns,H)
  Stub.Install(_G)
  assert(loadfile('ForeverHearthstone/Client/Net/Transport.lua'))('ForeverHearthstone',ns)
  H.ok(ns.Transport.Registered(true)); H.notOk(ns.Transport.Registered(false))
  H.ok(ns.Transport.Registered(0)); H.ok(ns.Transport.Registered(1))
  H.notOk(ns.Transport.Registered(2)); H.notOk(ns.Transport.Registered(3))
  H.notOk(ns.Transport.Registered(nil))
end)

H.suite('transport: stop discards volatile input and retry state before restart', function(ns,H)
  Stub.Install(_G)
  assert(loadfile('ForeverHearthstone/Client/Net/Transport.lua'))('ForeverHearthstone',ns)
  local t=ns.Transport.New(); t:SetPeer('OldPeer'); t.budget=0
  t:Send('0;HOVER;1'); t:Send('1;PING')
  t.retries=12; t.holdUntil=100
  t:Stop()
  H.eq(next(t.volatile),nil); H.eq(#t.queue,0); H.eq(t.peer,nil)
  H.eq(t.retries,0); H.eq(t.holdUntil,nil)
  t:SetPeer('NewPeer'); t:Tick()
  H.eq(Stub.Count('SendAddonMessage'),0,'no stale input reaches a new session')
end)

--[[ The WoW-facing files, in .toc order. The harness cannot load these -- they
     call CreateFrame at load time -- so every stub-backed test loads them by
     hand, and they are listed once here so the list cannot drift between
     tests. ]]
local WOW_FILES = {
  "ForeverHearthstone/Client/Net/Transport.lua",
  "ForeverHearthstone/Client/Rewards.lua",
  "ForeverHearthstone/Client/UI/Widgets.lua",
  "ForeverHearthstone/Client/UI/Board.lua",
  "ForeverHearthstone/Client/Main.lua",
}

local function withAddon(ns, fn)
  -- Each simulated login owns its character; earlier suites may use level 60.
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = {
    player = { name = "Tester", class = "MAGE", isPlayer = true },
    target = { name = "Foe",    class = "PRIEST", isPlayer = true },
  }
  Stub.interactDistance = true

  for _, path in ipairs(WOW_FILES) do
    local chunk = assert(loadfile(path))
    chunk("ForeverHearthstone", ns)
  end
  --[[ Main builds the resolver on ADDON_LOADED and starts listening on
       PLAYER_LOGIN, exactly as it does in game. Driving the real events rather
       than calling the functions is the point -- it proves the events are the
       ones that actually fire. ]]
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")

  -- a fresh session each time; the addon table is a singleton across loads
  ns.Main.session = nil
  ns.Main.mode = nil
  if ns.Main.transport then ns.Main.transport:SetPeer(nil) end
  return fn(ns.Main)
end

local function sentMessages()
  local out = {}
  for _, c in ipairs(Stub.R.calls) do
    if c.what == "SendAddonMessage" then
      out[#out + 1] = { prefix = c.args[1], msg = c.args[2],
                        channel = c.args[3], target = c.args[4] }
    end
  end
  return out
end

--- Deliver a raw line to the addon as if WoW had.
local function arrive(raw, from)
  Stub.Fire("CHAT_MSG_ADDON", ns and ns.Transport and ns.Transport.PREFIX or "FHDUEL",
            raw, "WHISPER", from or "Foe")
end

H.suite("transport: the prefix is registered at login, not at duel time", function(ns, H)
  withAddon(ns, function(Main)
    --[[ If the prefix is not registered, NOTHING ARRIVES and the failure is
         completely silent -- so this assertion is worth more than it looks. And
         registering only when a duel starts would mean you can never be
         challenged, because the challenge is what would have registered it. ]]
    H.ok(Stub.Count("RegisterAddonMessagePrefix") >= 1, "registered")
    H.ok(Main.transport, "and the transport exists before any duel")
  end)
end)

H.suite("transport: it listens for CHAT_MSG_ADDON and nothing forbidden", function(ns, H)
  withAddon(ns, function(Main)
    H.ok(Stub.R.events["CHAT_MSG_ADDON"], "listening for addon messages")
    --[[ COMBAT_LOG_EVENT_UNFILTERED ERRORS ON REGISTRATION in Forever (docs/07).
         Nothing in this addon may ever register it. ]]
    H.eq(Stub.R.events["COMBAT_LOG_EVENT_UNFILTERED"], nil,
         "and NOT the combat log, which errors on registration in Forever")
  end)
end)

H.suite("transport: challenging the target whispers them", function(ns, H)
  withAddon(ns, function(Main)
    H.ok(Main:Challenge(), "challenge accepted locally")
    local sent = sentMessages()
    H.ok(#sent >= 1, "something went out")
    H.eq(sent[1].prefix, ns.Transport.PREFIX, "with our prefix")
    H.eq(sent[1].channel, "WHISPER", "as a whisper")
    H.eq(sent[1].target, "Foe", "to the target")
    H.ok(sent[1].msg:find(";" .. ns.Protocol.KIND.HELLO .. ";", 1, true),
         "and it is a HELLO: " .. tostring(sent[1].msg))
  end)
end)

H.suite("transport: an out-of-range player cannot be challenged", function(ns, H)
  withAddon(ns, function(Main)
    Stub.interactDistance = false
    local before = #sentMessages()
    H.notOk(Main:Challenge(), "refused")
    H.eq(#sentMessages(), before, "and nothing was sent")
    --[[ The duel in the brief happens between two people near each other in the
         world. Range is the half of that a computer can check; sitting is not,
         so it is a prompt rather than a check that silently always passes. ]]
    H.ok(ns.Transport.SIT_PROMPT:find("/sit"), "and sitting is asked for, not asserted")
  end)
end)

H.suite("transport: a stranger's message opens a challenge, not a match", function(ns, H)
  withAddon(ns, function(Main)
    local hello = ("1;%s;%d;%s;%s;%s"):format(ns.Protocol.KIND.HELLO,
      ns.Protocol.VERSION, ns.Protocol.ADDON_VERSION, "PRIEST", "Stranger")
    Stub.Fire("CHAT_MSG_ADDON", ns.Transport.PREFIX, hello, "WHISPER", "Stranger")
    H.ok(Main.session, "a session was opened for them")
    H.eq(Main.session.state, ns.Session.STATE.INVITED, "waiting for the player to answer")
    H.eq(Main.game, nil, "and no game started on its own")
  end)
end)

H.suite("transport: a third party cannot interrupt a duel", function(ns, H)
  withAddon(ns, function(Main)
    Main:Challenge()                      -- now talking to Foe
    local hello = ("1;%s;%d;%s;%s;%s"):format(ns.Protocol.KIND.HELLO,
      ns.Protocol.VERSION, ns.Protocol.ADDON_VERSION, "ROGUE", "Interloper")
    local sessionBefore = Main.session
    Stub.Fire("CHAT_MSG_ADDON", ns.Transport.PREFIX, hello, "WHISPER", "Interloper")
    H.eq(Main.session, sessionBefore, "the duel in progress is untouched")
    H.ok(Main.transport.dropped >= 1, "and the stranger's message was dropped")
  end)
end)

H.suite("transport: another addon's messages are ignored", function(ns, H)
  withAddon(ns, function(Main)
    local before = Main.transport.received
    Stub.Fire("CHAT_MSG_ADDON", "SomeOtherAddon", "1;HI;1;x;MAGE;Bob", "WHISPER", "Bob")
    H.eq(Main.transport.received, before, "not even counted -- the prefix is the filter")
  end)
end)

H.suite("transport: a burst is PACED, not fired all at once", function(ns, H)
  --[[ WoW rate-limits addon messages and gives no error when you exceed it --
       it just drops them. A deck is four or five chunks, so the one burst this
       addon sends is also the one most likely to be silently truncated. ]]
  withAddon(ns, function(Main)
    Main.transport:SetPeer("Foe")
    local before = #sentMessages()
    for i = 1, 12 do Main.transport:Send(("%d;AC;E"):format(i)) end
    local immediately = #sentMessages() - before
    H.ok(immediately < 12, ("only %d of 12 went out immediately"):format(immediately))
    H.ok(immediately >= 1, "but the first did not wait for a tick")

    Stub.Advance(1.0)
    H.eq(#sentMessages() - before, 12, "and the rest drained on the ticker")
  end)
end)

H.suite("transport: nothing is sent to nobody", function(ns, H)
  withAddon(ns, function(Main)
    Main.transport:SetPeer(nil)
    local before = #sentMessages()
    H.notOk(Main.transport:Send("1;AC;E"), "refused without a peer")
    H.eq(#sentMessages(), before, "and SendAddonMessage was never called with a nil target")
  end)
end)

H.suite("transport: the slash commands reach the duel", function(ns, H)
  withAddon(ns, function(Main)
    local slash = _G.SlashCmdList["FOREVERHEARTHSTONE"]
    slash("duel")
    H.ok(Main.session, "/fh duel opened a session")
    H.eq(Main.session.state, ns.Session.STATE.OFFERED, "which is waiting on them")
    slash("concede")
    H.ok(true, "/fh concede with no duel in progress does not error")
  end)
end)

H.suite("transport: the right-click challenge is wired to the Mainline menu API", function(ns, H)
  withAddon(ns, function(Main)
    --[[ Menu.ModifyMenu, NOT UnitPopupButtons -- which is gone in Mainline
         (docs/07). An addon that still uses the old one errors at login. ]]
    H.ok(Stub.menuMods and Stub.menuMods["MENU_UNIT_PLAYER"],
         "the unit menu was extended through Menu.ModifyMenu")
  end)
end)

H.suite("transport: a duel plays through the real board and the real wire", function(ns, H)
  --[[ THE END-TO-END CHECK. Two addon namespaces, each with its own transport,
       whispering to each other through the stub. If this passes, the pieces fit:
       slash command -> session -> transport -> CHAT_MSG_ADDON -> session ->
       controller -> board. ]]
  Stub.Install(_G)
  Stub.resting = true
  Stub.interactDistance = true
  Stub.units = {
    player = { name = "Tester", class = "MAGE", isPlayer = true },
    target = { name = "Foe", class = "PRIEST", isPlayer = true },
  }

  -- The second player is a bare session -- a whole second addon namespace is
  -- not needed to prove the wire works, and this keeps the test readable.
  local theirDeck = ns.Controller.BasicDeck("PRIEST")
  local toThem, toUs = {}, {}
  local them
  them = ns.Session.New({
    name = "Foe", class = "PRIEST", deck = theirDeck, nonce = "theirs",
    send = function(raw) toUs[#toUs + 1] = raw end,
    onEvent = function(event) if event == "CHALLENGED" then them:Accept() end end,
  })

  for _, path in ipairs(WOW_FILES) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  local Main = ns.Main
  Main.session = nil

  local seen = 0
  local function pump()
    for _ = 1, 40 do
      Stub.Advance(0.2)                   -- let the throttle drain
      local sent = sentMessages()
      local moved = false
      while seen < #sent do
        seen = seen + 1
        them:Receive(sent[seen].msg)
        moved = true
      end
      while #toUs > 0 do
        local raw = table.remove(toUs, 1)
        Stub.Fire("CHAT_MSG_ADDON", ns.Transport.PREFIX, raw, "WHISPER", "Foe")
        moved = true
      end
      if not moved and #toUs == 0 and seen >= #sentMessages() then return end
    end
  end

  Main:Challenge()
  pump()
  Main.duelDeckPicker.play:Click(); pump()

  H.ok(Main.game, "a game was built on our side")
  H.ok(them.game, "and on theirs")
  H.eq(Main.game:StateHash(), them.game:StateHash(), "identical state on both")
  H.eq(Main.mode, "duel", "the addon knows it is a duel, not practice")
  H.ok(Main.board and Main.board:IsShown(), "and the board is on screen")

  --[[ BOTH SIDES MULLIGAN FIRST. A duel opens on the mulligan and the engine
       refuses every other action until both players have answered, so a test
       that took a turn without answering was only ever passing in the branch
       where the OTHER side happened to be active. Which branch that was
       depended on the derived seed, and therefore on how much global RNG the
       suites before this one had consumed -- so making the practice opening a
       real coin flip was enough to flip this test into its untested half. ]]
  if Main.game:AwaitingMulligan() then
    Main:OnIntent({ kind = "CONFIRM_MULLIGAN" })
    them:LocalAction({ kind = "MULLIGAN", indices = {} })
    pump()
    H.notOk(Main.game:AwaitingMulligan(), "both sides answered the mulligan")
    H.eq(Main.game:StateHash(), them.game:StateHash(), "identical after the mulligan")
  end

  --[[ Take a turn through the real UI path: the board's end-turn button emits
       an intent, the controller turns it into an action, the session sends it. ]]
  local mine = Main.controller.me
  if Main.game.activePlayer == mine then
    Main:OnIntent({ kind = "END_TURN" })
    pump()
    H.eq(Main.game:StateHash(), them.game:StateHash(), "still identical after a turn")
    H.ok(Main.game.turn > 1, "and the game moved on")
  else
    ns.AI.TakeTurn(them.game, them.game.activePlayer, function(a) return them:LocalAction(a) end)
    them:LocalAction({ kind = "END_TURN" })
    pump()
    H.eq(Main.game:StateHash(), them.game:StateHash(), "their turn arrived and applied identically")
  end
  H.noEngineErrors(Main.game, "our engine")
end)

-- The real Main/Board/Transport on one side and an independent Session on the
-- other. Exercise the same addon message delivery path used by WoW.
local function liveDuel(ns,Main)
  Stub.units.player.level=42; Stub.units.player.guid="Player-Local"
  Stub.units.target.level=58; Stub.units.target.guid="Player-Remote"
  local toA,toB={},{}
  local original=C_ChatInfo.SendAddonMessage
  C_ChatInfo.SendAddonMessage=function(prefix,msg,channel,target)
    original(prefix,msg,channel,target); toB[#toB+1]=msg; return true
  end
  local peer=ns.Session.New({name="Foe",class="PRIEST",level=58,guid="Player-Remote",
    deck=ns.Controller.BasicDeck("PRIEST"),nonce="remote-nonce",
    send=function(raw) toA[#toA+1]=raw end})
  local function pump()
    for i=1,100 do
      Main.transport:Tick()
      if #toA==0 and #toB==0 and #Main.transport.queue==0 then return end
      if #toB>0 then peer:Receive(table.remove(toB,1)) end
      if #toA>0 then Main.transport:OnReceive(table.remove(toA,1),"Foe") end
    end
    error("duel wire did not settle")
  end
  Main:Challenge("Foe"); pump(); peer:Accept(); pump(); Main.duelDeckPicker.play:Click(); pump()
  return peer,pump
end
H.suite("transport: real duel UI requests a mutual end without a forfeit",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    H.eq(Main.mode,"duel"); H.eq(Main.game:StateHash(),peer.game:StateHash())
    H.eq(Main.board.profiles.self.name:GetText(),"Tester")
    H.eq(Main.board.profiles.self.level:GetText(),"Level 42")
    H.eq(Main.board.profiles.self.portrait.portraitUnit,"player")
    H.eq(Main.board.profiles.foe.name:GetText(),"Foe")
    H.eq(Main.board.profiles.foe.level:GetText(),"Level 58")
    H.eq(Main.board.profiles.foe.portrait.portraitUnit,"target")
    H.eq(Main:StartPractice(),false,"cannot replace a live duel with a bot match")
    Main.board.close:Click(); H.ok(Main.board:IsShown()); H.ok(Main.exitDialog:IsShown())
    H.notOk(Main.game.over); Main.exitDialog.cancel:Click(); H.notOk(Main.game.over)
    Main.board:Hide(); H.ok(Main.exitDialog:IsShown())
    Main.exitDialog.confirm:Click(); pump()
    H.notOk(Main.game.over); H.notOk(peer.game.over)
    H.ok(peer.endInvited)
    peer:AnswerEndDuel(true); pump()
    H.eq(Main.session,nil); H.eq(peer.abortReason,"agreed")
    H.notOk(Main.game.winner); H.notOk(peer.game.winner)
    H.eq(Main:Record().wins,0); H.eq(Main:Record().losses,0)
  end)
end)
H.suite("transport: logout (or /reload) pauses the duel; not coming back forfeits it",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Stub.Fire("PLAYER_LOGOUT"); pump()
    H.notOk(peer.game.over,"a reload must not throw the game away")
    H.eq(peer.paused and peer.paused.peer,"left","the other player sees you left the table")
    -- they never come back: the grace period settles it
    for _=1,(ns.Session.GRACE.left+ns.Session.CLAIM_MARGIN)/5+2 do peer:Tick(5) end
    H.ok(peer.game.over,"the game ends")
    H.eq(peer.game.winner,peer.myIndex,"and the player who stayed wins")
  end)
end)
H.suite("transport: hero menu performs a WoW emote and sends one speech event",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    local board=Main.board
    H.eq(board.hero.frame.clickButtons[2],"RightButtonUp","native right clicks are registered")
    local before=Stub.Count("PerformEmote")
    board.hero.frame:Click("RightButton"); H.ok(board.emoteMenu:IsShown())
    board.emoteButtons[3]:Click(); pump()
    H.eq(Stub.Count("PerformEmote"),before+1)
    H.eq(board.speech.self.text:GetText(),"Well met!")
    H.eq(Main.game:StateHash(),peer.game:StateHash())
    Main:OnIntent({kind="EMOTE",index=3}); H.eq(Stub.Count("PerformEmote"),before+1,"cooldown applies")
    peer:Emote(2); pump()
    H.eq(board.speech.foe.text:GetText(),"Well played!")
    H.eq(Stub.Count("PerformEmote"),before+1,"receiving an emote must not emote as us")
    Stub.units.player.level=43; Stub.Fire("UNIT_LEVEL","player"); pump()
    H.eq(peer.peer.level,43); H.eq(board.profiles.self.level:GetText(),"Level 43")
    --[[ Targeting someone else no longer flips their portrait back to the
         class hero: the character's own face, once drawn, stays. ]]
    local face=board.profiles.foe.portrait:GetTexture()
    Stub.units.target.guid="Player-SomeoneElse"; Stub.Fire("PLAYER_TARGET_CHANGED")
    H.eq(board.profiles.foe.portrait:GetTexture(),face,"the opponent keeps their own portrait")
    H.ok(rawget(board.profiles.foe.portrait,"portraitUnit")~=nil,"drawn from their unit, not the class hero")
    H.ok(board.profiles.foe.portrait:GetTexture()~=Main.resolver:Card(ns.HERO_ID_BY_CLASS.PRIEST).icon,
         "and not swapped for the class hero")
  end)
end)
H.suite("transport: same realm short names match qualified replies without accepting other realms",function(ns,H)
  withAddon(ns,function(Main)
    local previous=GetNormalizedRealmName
    GetNormalizedRealmName=function() return "MyRealm" end
    local count=0
    local transport=ns.Transport.New({onMessage=function() count=count+1 end})
    transport:SetPeer("Foe")
    transport:OnReceive("hello","Foe-MyRealm"); H.eq(count,1)
    transport:OnReceive("hello","Foe-OtherRealm"); H.eq(count,1)
    GetNormalizedRealmName=previous
  end)
end)

--============================================================ rematch

-- Like liveDuel, but the remote side is swappable: when it agrees to a
-- rematch it does what Main does -- lets go of the old session and answers the
-- new challenge from a fresh one.
local function rematchDuel(ns,Main)
  ForeverHearthstoneCharDB.record=nil   -- earlier suites' duels counted too
  Stub.units.player.level=42; Stub.units.player.guid="Player-Local"
  Stub.units.target.level=58; Stub.units.target.guid="Player-Remote"
  local toA,toB={},{}
  local original=C_ChatInfo.SendAddonMessage
  C_ChatInfo.SendAddonMessage=function(prefix,msg,channel,target)
    original(prefix,msg,channel,target); toB[#toB+1]=msg; return true
  end
  local remote={events={}}
  local function newPeer(record)
    local s
    s=ns.Session.New({name="Foe",class="PRIEST",level=58,guid="Player-Remote",
      wins=record and record.wins or 3,losses=record and record.losses or 4,
      deck=ns.Controller.BasicDeck("PRIEST"),nonce="remote-nonce-"..(#remote.events),
      send=function(raw) toA[#toA+1]=raw end,
      onEvent=function(event,data)
        remote.events[#remote.events+1]=event
        if event=="CHALLENGED" then s:Accept() end
        if event=="REMATCH_START" and not data.challenger then remote.session=newPeer() end
      end})
    return s
  end
  remote.session=newPeer()
  local function pump()
    for i=1,200 do
      Main.transport:Tick()
      if Main.session and Main.session.state == ns.Session.STATE.SYNC and not Main.session.committed then
        Main.duelDeckPicker.play:Click()
      end
      if #toA==0 and #toB==0 and #Main.transport.queue==0 then return end
      if #toB>0 then remote.session:Receive(table.remove(toB,1)) end
      if #toA>0 then Main.transport:OnReceive(table.remove(toA,1),"Foe") end
    end
    error("duel wire did not settle")
  end
  Main:Challenge("Foe"); pump(); remote.session:Accept(); pump()
  Main.session:LocalAction({kind="MULLIGAN",indices={}})
  remote.session:LocalAction({kind="MULLIGAN",indices={}}); pump()
  return remote,pump
end

H.suite("rematch: the duel record is kept, shown and exchanged",function(ns,H)
  withAddon(ns,function(Main)
    local remote,pump=rematchDuel(ns,Main)
    local panels=Main.board.profiles
    H.eq((panels.self.record:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")),"0 W  0 L")
    H.eq((panels.foe.record:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")),"3 W  4 L","their record came with their HELLO")
    remote.session:Concede(); pump()
    H.eq(Main:Record().wins,1); H.eq(Main:Record().losses,0)
    H.eq((panels.self.record:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")),"1 W  0 L")
    H.eq(remote.session.peer.wins,1,"the new record is sent to them")
    H.eq(ForeverHearthstoneCharDB.record.wins,1,"saved per character")
  end)
end)

H.suite("rematch: asking starts a second duel with the same player",function(ns,H)
  withAddon(ns,function(Main)
    local remote,pump=rematchDuel(ns,Main)
    local first=Main.session
    remote.session:Concede(); pump()
    Stub.Advance(3)
    local panel=Main.board.postGame
    H.ok(panel and panel:IsShown(),"Rematch and Leave appear after the result")
    H.eq(panel.primary.text:GetText(),"Rematch")
    panel.primary:Click(); pump()
    H.eq(Main.board.postGameState,"asked")
    H.ok(table.concat(remote.events,","):find("REMATCH_ASKED",1,true),"they are asked")
    remote.session:AnswerRematch(true); pump()
    H.ok(Main.session~=first,"a fresh session, not the finished one")
    H.eq(Main.mode,"duel"); H.notOk(Main.game.over,"a new game is on")
    H.eq(Main.session.state,ns.Session.STATE.PLAYING)
    H.eq(Main.game:StateHash(),remote.session.game:StateHash(),"both clients agree on the new game")
    H.notOk(Main.board.postGame:IsShown(),"the post-game panel is gone")
    H.ok(Main.session.challenger,"the original challenger challenges again")
  end)
end)

H.suite("rematch: when they ask, Accept agrees and Decline says no",function(ns,H)
  for _,accept in ipairs({true,false}) do
    withAddon(ns,function(Main)
      local remote,pump=rematchDuel(ns,Main)
      local first=Main.session
      Main.session:Concede(); pump()
      remote.session:AskRematch(); pump()
      H.eq(Main.board.postGameState,"invited")
      H.ok(Main.board.postGame.text:GetText():find("would like a rematch",1,true))
      if accept then
        Main.board.postGame.primary:Click(); pump()
        H.ok(Main.session~=first); H.eq(Main.session.state,ns.Session.STATE.PLAYING)
        H.eq(Main.game:StateHash(),remote.session.game:StateHash())
      else
        Main.board.postGame.secondary:Click(); pump()
        H.ok(table.concat(remote.events,","):find("REMATCH_DECLINED",1,true),"they hear the no")
        H.eq(Main.session,first); H.ok(Main.game.over)
        H.eq(Main.board.postGameState,"closed")
      end
    end)
  end
end)

H.suite("rematch: practice replays the same matchup",function(ns,H)
  withAddon(ns,function(Main)
    ForeverHearthstoneCharDB.record=nil
    Main:StartPractice("MAGE","WARRIOR")
    local first=Main.game
    Main.game.players[2].hero.health=0; Main.game.over=true; Main.game.winner=1
    Main.controller:Changed(); Stub.Advance(3)
    H.ok(Main.board.postGame:IsShown())
    Main.board.postGame.primary:Click()
    H.ok(Main.game~=first); H.notOk(Main.game.over)
    H.eq(Main.game.players[2].class,"WARRIOR")
    H.notOk(Main.board.postGame:IsShown())
    H.eq(Main:Record().wins,0,"practice games do not count")
  end)
end)

H.suite("practice: closing a bot game opens the main menu, and it can be resumed", function(ns, H)
  withAddon(ns, function(Main)
    Main:StartPractice("MAGE", "WARRIOR")
    if Main.hub then Main.hub:Hide() end
    Main.board.frame:Hide()
    H.ok(Main.hub and Main.hub:IsShown(), "the /fh main menu is open")
    H.ok(Main.game ~= nil, "and the bot game is kept for Resume Match")
  end)
end)

H.suite("presentation: opponent actions are shown one after another, and long chains speed up", function(ns, H)
  withAddon(ns, function(Main)
    local ran = {}
    local real = Main.RunPlans
    Main.RunPlans = function(self, plans) ran[#ran + 1] = plans.name; return 1.0 end
    Main.presentQueue, Main.presentBusy = {}, false
    Main:PresentRemote({ name = "first" }, true)
    Main:PresentRemote({ name = "second" }, true)
    H.eq(#ran, 1, "the second waits for the first")
    Stub.Advance(1.2)
    H.eq(ran[2], "second", "then plays")
    Main.RunPlans = real
    -- the speed-up itself: a long plan is compressed to the comfort length
    H.ok(ns.Main.FX_MAX_SPEED > 1 and ns.Main.FX_COMFORT > 0)
  end)
end)

H.suite("table: a secret position in an instance is not leaving the table",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    local saved=UnitPosition
    _G.UnitPosition=function() return Stub.Secret(),Stub.Secret(),Stub.Secret(),Stub.Secret() end
    Main:CheckTable(); pump()
    H.eq(Main.session.paused,nil,"an unknown position never pauses the duel")
    _G.UnitPosition=saved
  end)
end)

H.suite("table: zoning into a dungeon mid-duel is leaving the table",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    Stub.units.player.pos={100,100,1}
    local inside=false
    local saved=rawget(_G,"IsInInstance")
    _G.IsInInstance=function() return inside end
    Main:CheckTable(); pump()
    H.eq(Main.session.paused,nil,"sitting in the open world")
    inside=true; Stub.units.player.pos=nil
    Main:CheckTable(); pump()
    H.eq(peer.paused and peer.paused.peer,"away","through a portal is away")
    Main:CheckTable(); pump()
    H.eq(peer.paused and peer.paused.peer,"away","and an unknown position inside does not bring you back")
    _G.IsInInstance=saved
  end)
end)

H.suite("table: a pause notice from the last duel does not carry into the next",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    Stub.units.player.inCombat=true
    Main:CheckTable(); pump()
    H.ok(Main.board.statusPanel:IsShown(),"the notice is up")
    Main.session:Abort("disconnected","gone")
    H.notOk(Main.board.statusPanel:IsShown(),"an ended duel takes its notice with it")
    Main.board:ShowStatus("You left the table -- come back within 60 seconds or forfeit")
    Stub.units.player.inCombat=nil
    peer,pump=liveDuel(ns,Main)
    H.notOk(Main.board.statusPanel:IsShown(),"and a new duel starts without one")
  end)
end)

H.suite("table: dying, fighting or walking away pauses the duel for both players",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    Stub.units.player.pos = { 100, 100, 1 }
    Main:CheckTable()
    H.eq(Main.session.paused, nil, "sitting at the table: no pause")
    Stub.units.player.inCombat = true
    Main:CheckTable(); pump()
    H.eq(peer.paused and peer.paused.peer, "combat", "a fight pauses the duel")
    H.ok(Main.board.statusPanel and Main.board.statusPanel:IsShown(), "and says so on the board")
    Stub.units.player.inCombat = nil
    Main:CheckTable(); pump()
    H.eq(peer.paused, nil, "and it resumes when the fight is over")
    Stub.units.player.pos = { 150, 100, 1 }
    Main:CheckTable(); pump()
    H.eq(peer.paused and peer.paused.peer, "away", "walking fifty yards away pauses it")
    Stub.units.player.pos = { 110, 100, 1 }
    Main:CheckTable(); pump()
    H.eq(peer.paused, nil, "coming back resumes it")
    Stub.units.player.dead = true
    Main:CheckTable(); pump()
    H.eq(peer.paused and peer.paused.peer, "dead", "and so does dying")
    local before = Main.director.elapsed
    Main.clockFrame:GetScript("OnUpdate")(Main.clockFrame, 5)
    H.eq(Main.director.elapsed, before, "the rope stands still while paused")
  end)
end)

H.suite("rejoin: an offer for the duel we remember is taken up; a stranger's is asked about", function(ns, H)
  withAddon(ns, function(Main)
    ForeverHearthstoneCharDB.activeDuel = nil
    Main:OnRejoinOffer("Someone")
    H.ok(table.concat(Stub.R.chat, " "):find("/fh resume", 1, true), "an unknown offer asks the player")
    H.eq(Main.session, nil, "and does nothing by itself")
    ForeverHearthstoneCharDB.activeDuel = { peer = "Foe" }
    Main:OnRejoinOffer("Foe")
    H.ok(Main.session and Main.session.state == ns.Session.STATE.REJOINING, "the remembered duel is rejoined")
  end)
end)

--============================================================ docs/27

H.suite("transport: a line WoW refuses for throttling is kept and sent again", function(ns, H)
  --[[ SendAddonMessage's answer was ignored, so a line refused by WoW's own
       per-prefix allowance was simply gone until a NAK noticed -- attacks
       arrived seconds late. ]]
  withAddon(ns, function(Main)
    local t = Main.transport
    t:SetPeer("Foe")
    local original, refusals, delivered = C_ChatInfo.SendAddonMessage, 3, {}
    C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
      if refusals > 0 then refusals = refusals - 1; return 3 end   -- AddonMessageThrottle
      delivered[#delivered + 1] = msg
      return original(prefix, msg, channel, target)
    end
    t:Send("1;AC;A;4;9;h1x5")
    t:Send("2;AC;E;h2x6")
    H.eq(#delivered, 0, "refused at first")
    Stub.Advance(3)
    C_ChatInfo.SendAddonMessage = original
    H.eq(#delivered, 2, "both lines arrived in the end")
    H.eq(delivered[1], "1;AC;A;4;9;h1x5", "in their order")
    H.eq(t.dropped, 0, "and nothing was thrown away")
  end)
end)

H.suite("transport: hover lines are coalesced and never crowd out the game", function(ns, H)
  withAddon(ns, function(Main)
    local t = Main.transport
    t:SetPeer("Foe")
    t.tokens = ns.Transport.VOLATILE_RESERVE - 1    -- WoW's allowance is nearly spent
    local before = #sentMessages()
    for i = 1, 6 do t:Send(("0;HV;%d;H;e%d"):format(i, i)) end
    H.eq(#sentMessages() - before, 0, "no hover spends the last of the allowance")
    t:Send("1;AC;E;h1x5")
    local sent = sentMessages()
    H.eq(sent[#sent].msg, "1;AC;E;h1x5", "a game action still goes at once")
    Stub.Advance(10)
    local hovers = 0
    for i = before + 1, #sentMessages() do
      if sentMessages()[i].msg:find(";HV;", 1, true) then hovers = hovers + 1 end
    end
    H.eq(hovers, 1, "only the newest hover went, once there was allowance to spare")
  end)
end)

H.suite("transport: a party or raid member can be challenged from their menu", function(ns, H)
  withAddon(ns, function(Main)
    for _, tag in ipairs({ "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND" }) do
      H.ok(Stub.menuMods and Stub.menuMods[tag], tag .. " offers the challenge")
    end
    local made = {}
    local root = { CreateButton = function(_, label, fn) made[#made + 1] = { label = label, fn = fn } end }
    Stub.menuMods["MENU_UNIT_PARTY"](nil, root, { name = "Foe" })
    H.eq(made[1] and made[1].label, "Challenge to Hearthstone", "the entry is there")
    made[1].fn()
    H.eq(Main.session and Main.session.state, ns.Session.STATE.OFFERED, "and it challenges them")
    made = {}
    Stub.menuMods["MENU_UNIT_PARTY"](nil, root, { name = "Tester" })
    H.eq(#made, 0, "but you cannot challenge yourself")
  end)
end)

H.suite("transport: a challenge pops up with Accept and Decline", function(ns, H)
  withAddon(ns, function(Main)
    arrive(ns.Protocol.Encode(1, ns.Protocol.KIND.HELLO, ns.Protocol.VERSION,
      ns.Protocol.ADDON_VERSION, "PRIEST", "Foe", 30, "Player-Remote", 1, 0, 0, "c"), "Foe")
    H.eq(Main.session and Main.session.state, ns.Session.STATE.INVITED, "we were challenged")
    local p = Main.duelPrompt
    H.ok(p and p:IsShown(), "the challenge is on screen, not just in chat")
    H.ok(p.message:GetText():find("Foe", 1, true), "naming who is asking")
    p.yes:Click()
    H.eq(Main.session.state, ns.Session.STATE.SYNC, "Accept accepts")
    H.notOk(p:IsShown(), "and the prompt goes away")
  end)
end)

H.suite("transport: challenging whoever is challenging you accepts them", function(ns, H)
  withAddon(ns, function(Main)
    arrive(ns.Protocol.Encode(1, ns.Protocol.KIND.HELLO, ns.Protocol.VERSION,
      ns.Protocol.ADDON_VERSION, "PRIEST", "Foe", 30, "Player-Remote", 1, 0, 0, "c"), "Foe")
    local asked = Main.session
    Main:Challenge("Foe")
    H.ok(Main.session == asked, "no second, crossing challenge was started")
    H.eq(Main.session.state, ns.Session.STATE.SYNC, "their challenge was answered")
    H.eq(Main.session.challenger, false, "so they stay the challenger")
  end)
end)

H.suite("transport: Concede on the board asks, then forfeits the duel for both", function(ns, H)
  withAddon(ns, function(Main)
    local peer, pump = liveDuel(ns, Main)
    Main.session:LocalAction({ kind = "MULLIGAN", indices = {} })
    peer:LocalAction({ kind = "MULLIGAN", indices = {} }); pump()
    local b = Main.board
    H.ok(b.concede:IsShown(), "the Concede button is up while the duel is on")
    b.concede:Click()
    H.ok(Main.concedeDialog and Main.concedeDialog:IsShown(), "it asks first")
    H.notOk(Main.game.over, "and nothing has happened yet")
    Main.concedeDialog.buttons[1]:Click(); pump()
    H.ok(Main.game.over and peer.game.over, "then both games end")
    H.eq(peer.game.winner, peer.myIndex, "and the opponent wins")
    H.notOk(b.concede:IsShown(), "the button leaves with the game")
  end)
end)

H.suite("transport: your mulligan crosses stay while the opponent decides", function(ns, H)
  withAddon(ns, function(Main)
    local peer, pump = liveDuel(ns, Main)
    Main:OnIntent({ kind = "CLICK_MULLIGAN", handIndex = 1 })
    Main:OnIntent({ kind = "CONFIRM_MULLIGAN" }); pump()
    local snap = Main.controller:Snapshot()
    H.ok(snap.mulligan and snap.mulligan.waiting, "we are waiting for them")
    H.ok(snap.mulligan.marked[1], "the card thrown back still wears its cross")
    H.ok(Main.board.mulliganPool.used[1].cross:IsShown(), "on screen too")
    peer:LocalAction({ kind = "MULLIGAN", indices = {} }); pump()
    snap = Main.controller:Snapshot()
    H.eq(snap.mulligan, nil, "once they choose the game begins")
    H.eq(next(Main.controller.mulliganMarks), nil, "and the marks are cleared")
  end)
end)

--============================================================ docs/28

local function challengeFrom(ns, name, guid)
  arrive(ns.Protocol.Encode(1, ns.Protocol.KIND.HELLO, ns.Protocol.VERSION,
    ns.Protocol.ADDON_VERSION, "PRIEST", name, 30, guid or ("Player-" .. name), 1, 0, 0, "c"), name)
end

H.suite("privacy: a blocked player's challenges never reach you", function(ns, H)
  withAddon(ns, function(Main)
    Main:Block("Troll")
    local chat = #Stub.R.chat
    challengeFrom(ns, "Troll")
    H.eq(Main.session, nil, "no challenge")
    H.notOk(Main.duelPrompt and Main.duelPrompt:IsShown(), "no pop-up")
    H.eq(#Stub.R.chat, chat, "not even a line of chat")
    Main:Unblock("Troll")
    challengeFrom(ns, "Troll")
    H.eq(Main.session and Main.session.state, ns.Session.STATE.INVITED, "unblocked, they can ask again")
  end)
end)

H.suite("privacy: the pop-up's Block declines and blocks in one click", function(ns, H)
  withAddon(ns, function(Main)
    challengeFrom(ns, "Troll")
    Main.duelPrompt.block:Click()
    H.eq(Main.session, nil, "declined")
    H.ok(Main:IsBlocked("Troll"), "and blocked")
    H.ok(ForeverHearthstoneDB.duelPrivacy.blocked.troll, "saved for the account")
  end)
end)

H.suite("privacy: challenges can be friends-only or off", function(ns, H)
  withAddon(ns, function(Main)
    Main:SetChallengePolicy("nobody")
    challengeFrom(ns, "Stranger")
    H.eq(Main.session, nil, "off means off")
    Main:SetChallengePolicy("friends")
    challengeFrom(ns, "Stranger")
    H.eq(Main.session, nil, "a stranger cannot when it is friends only")
    local hadList = rawget(_G, "C_FriendList")
    local hadInfo = rawget(_G, "GetPlayerInfoByGUID")
    _G.C_FriendList = { IsFriend = function(guid) return guid == "Player-Pal" end }
    _G.GetPlayerInfoByGUID = function(guid)
      if guid == "Player-Pal" then return "PRIEST", "PRIEST", "Human", "Human", 2, "Pal", "" end
    end
    -- a stranger quoting the friend's GUID is still a stranger
    challengeFrom(ns, "Impostor", "Player-Pal")
    H.eq(Main.session, nil, "a copied GUID does not make a friend")
    challengeFrom(ns, "Pal", "Player-Pal")
    _G.C_FriendList, _G.GetPlayerInfoByGUID = hadList, hadInfo
    H.eq(Main.session and Main.session.state, ns.Session.STATE.INVITED, "a friend can")
    Main:Decline()
    _G.SlashCmdList["FOREVERHEARTHSTONE"]("challenges anyone")
    H.eq(Main:DuelPrivacy().policy, "anyone", "/fh challenges sets it")
  end)
end)

H.suite("privacy: declining allows an immediate fresh challenge", function(ns, H)
  withAddon(ns, function(Main)
    for i = 1, 4 do
      challengeFrom(ns, "Pest")
      H.eq(Main.session.state, ns.Session.STATE.INVITED)
      Main:Decline()
      H.eq(Main.session, nil)
      H.ok(Main:AllowChallengeFrom("Pest"))
    end
  end)
end)

H.suite("privacy: nobody can push a challenge you are looking at off the screen", function(ns, H)
  withAddon(ns, function(Main)
    challengeFrom(ns, "First")
    local first = Main.session
    challengeFrom(ns, "Second")
    H.ok(Main.session == first, "the first challenge stays")
    H.ok(Main.duelPrompt.message:GetText():find("First", 1, true), "and so does its pop-up")
  end)
end)

--============================================================ docs/29

H.suite("proximity: every way into a duel needs the two players together", function(ns, H)
  withAddon(ns, function(Main)
    -- by name, with nobody of that name anywhere this client can see
    H.notOk(Main:Challenge("Faraway"), "/fh duel Faraway is refused")
    H.eq(Main.session, nil, "and nothing was sent")
    -- by name, standing right there as the target
    Stub.interactDistance = false
    H.notOk(Main:Challenge("Foe"), "a visible player out of trade range is refused")
    Stub.interactDistance = true
    H.ok(Main:Challenge("Foe"), "in range, it goes")
    Main:CancelChallenge()
  end)
end)

H.suite("proximity: an incoming challenge is answered only from beside them", function(ns, H)
  withAddon(ns, function(Main)
    -- they are our target, but out of range: dropped without a word
    Stub.interactDistance = false
    challengeFrom(ns, "Foe")
    H.eq(Main.session, nil, "a far-off challenger is ignored")
    Stub.interactDistance = true
    -- not a unit this client can see: the pop-up shows, Accept asks to target
    challengeFrom(ns, "Unseen")
    H.eq(Main.session and Main.session.state, ns.Session.STATE.INVITED, "the challenge shows")
    Main:Accept()
    H.eq(Main.session.state, ns.Session.STATE.INVITED, "but cannot be accepted until they are targeted")
    H.ok(Main.duelPrompt:IsShown(), "and the pop-up waits")
    Stub.units.target = { name = "Unseen", class = "PRIEST", isPlayer = true }
    Main:Accept()
    H.eq(Main.session.state, ns.Session.STATE.SYNC, "targeted and beside us, it is accepted")
  end)
end)

H.suite("transport: after a finished duel a stranger can still challenge you", function(ns, H)
  withAddon(ns, function(Main)
    local peer, pump = liveDuel(ns, Main)
    Main.session:LocalAction({ kind = "MULLIGAN", indices = {} })
    peer:LocalAction({ kind = "MULLIGAN", indices = {} }); pump()
    Main:ConcedeMatch(); pump()
    H.ok(Main.game.over, "the duel is over")
    Stub.units.focus = { name = "Newcomer", class = "ROGUE", isPlayer = true }
    challengeFrom(ns, "Newcomer")
    H.eq(Main.session and Main.session.peer.name, "Newcomer", "their challenge arrives")
  end)
end)

H.suite("table: the rope leaves with the game, however it ends", function(ns, H)
  withAddon(ns, function(Main)
    local peer, pump = liveDuel(ns, Main)
    Main.session:LocalAction({ kind = "MULLIGAN", indices = {} })
    peer:LocalAction({ kind = "MULLIGAN", indices = {} }); pump()
    local b = Main.board
    b.ropeBurn = 0.5; b.rope.frame:Show()
    Main:ConcedeMatch(); pump()
    b:EndPresentation()
    H.eq(b.ropeBurn, nil, "lethal mid-rope: no rope over the result")
    H.notOk(b.rope.frame:IsShown(), "and none on screen")
  end)
  withAddon(ns, function(Main)
    local peer, pump = liveDuel(ns, Main)
    local b = Main.board
    b.ropeBurn = 0.5; b.rope.frame:Show(); b.presentationLocked = true
    Main.session:Abort("disconnected", "test")
    H.eq(b.ropeBurn, nil, "an aborted duel takes its rope down")
    H.notOk(b.presentationLocked, "and nothing stays locked waiting for a snapshot")
  end)
end)

H.suite("privacy: previous opponents obey Nobody and pending invitations close",function(ns,H)
  withAddon(ns,function(Main)
    challengeFrom(ns,"Foe")
    H.ok(Main.duelPrompt:IsShown())
    Main:SetChallengePolicy("nobody")
    H.notOk(Main.duelPrompt:IsShown())
    local old=Main:NewSession("Foe")
    old.state=ns.Session.STATE.OVER
    Main.freshFrom="Foe"; Main.transport:SetPeer("Foe")
    challengeFrom(ns,"Foe")
    H.eq(Main.session,old)
    H.notOk(Main.duelPrompt:IsShown())
  end)
end)

H.suite("privacy: settings undo an accidental block immediately",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    challengeFrom(ns,"Foe")
    Main:Block("Foe")
    Main:Settings()
    Main.settings.tabs.general:Click()
    H.ok(Main.settings.rows[1]:IsShown())
    H.eq(Main.settings.names[1],"Foe")
    H.eq(Main.settings:GetFrameStrata(),"FULLSCREEN_DIALOG","settings overlays board and menus")
    H.ok(Main.settings.rows[1]:GetFrameLevel()>Main.settings.panel:GetFrameLevel())
    Main.settings.rows[1]:Click()
    H.notOk(Main:IsBlocked("Foe"))
    H.ok(Main:AllowChallengeFrom("Foe"),"unblock clears the decline cooldown too")
    challengeFrom(ns,"Foe")
    H.eq(Main.session.state,ns.Session.STATE.INVITED)
    H.notOk(ForeverHearthstoneDB.debugMessages)
    Main.settings.debug:Click()
    H.ok(ForeverHearthstoneDB.debugMessages)
    Main.settings.debug:Click()
    H.notOk(ForeverHearthstoneDB.debugMessages)
  end)
end)

--[[ Forever characters have a first and last name, and the name a challenge
     arrives under need not be the one UnitName shows for them. The player
     beside you is found by GUID (or by the menu's unit), not by name. ]]
H.suite("proximity: a first-and-last name that differs from the sender still duels",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    Stub.units.target={name="Pagpag Halohalo",class="PRIEST",isPlayer=true,guid="Player-Pagpag"}
    arrive(ns.Protocol.Encode(1,ns.Protocol.KIND.HELLO,ns.Protocol.VERSION,
      ns.Protocol.ADDON_VERSION,"PRIEST","Pagpag Halohalo",30,"Player-Pagpag",1,0,0,"c"),"Pagpag-Realm")
    H.eq(Main.session.state,ns.Session.STATE.INVITED,"we were challenged")
    H.ok(Main:NearEnough("Pagpag-Realm"),"the targeted challenger is found by GUID")
    H.ok(Main:Accept(),"so Accept goes ahead")
    H.eq(Main.session.state,ns.Session.STATE.SYNC)
  end)
end)

--[[ Forever's UnitName gives (first, last), so the challenge goes to
     "Femboy-President" while the answer comes from their real address. The
     challenger recognises it by GUID and talks to that address from then on;
     before, every reply was dropped and the challenge timed out as "no addon". ]]
H.suite("proximity: the answer from another address than the challenge's is recognised",function(ns,H)
  withAddon(ns,function(Main)
    local saved=UnitName
    _G.UnitName=function(u) if u=="target" then return "Femboy","President" end return saved(u) end
    Stub.units.target.guid="Player-Femboy"
    H.ok(Main:Challenge())
    H.eq(Main.transport.peer,"Femboy-President","the challenge went to first-last")
    local function answer(guid,from)
      arrive(ns.Protocol.Encode(1,ns.Protocol.KIND.HELLO,ns.Protocol.VERSION,
        ns.Protocol.ADDON_VERSION,"PRIEST","Femboy",30,guid,1,0,0,"a","","","","",
        Main.session.challengeId),from)
    end
    answer("Player-Stranger","Femboy-Realm")
    H.eq(Main.session.state,ns.Session.STATE.OFFERED,"a HELLO with another GUID is not their answer")
    answer("Player-Femboy","Femboy-Realm")
    H.eq(Main.session.state,ns.Session.STATE.SYNC,"theirs moves us on to choosing a deck")
    H.eq(Main.transport.peer,"Femboy-Realm","and we talk to the address they answered from")
    H.eq(Main.session.peer.name,"Femboy-Realm")
    _G.UnitName=saved
  end)
end)

H.suite("proximity: Forever's first-last reading of UnitName finds the player beside you",function(ns,H)
  withAddon(ns,function(Main)
    local saved=UnitName
    _G.UnitName=function(u) if u=="target" then return "Femboy","President" end return saved(u) end
    H.eq(Main:FindPlayerUnit("Femboy-President"),"target","as first-last")
    H.eq(Main:FindPlayerUnit("Femboy"),"target","and as the plain name a reply comes from")
    H.eq(Main:FindPlayerUnit("Someone"),nil)
    _G.UnitName=saved
  end)
end)

H.suite("proximity: a far challenger is turned away by GUID even when names differ",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    Stub.units.target={name="Pagpag Halohalo",class="PRIEST",isPlayer=true,guid="Player-Pagpag"}
    Stub.interactDistance=false
    arrive(ns.Protocol.Encode(1,ns.Protocol.KIND.HELLO,ns.Protocol.VERSION,
      ns.Protocol.ADDON_VERSION,"PRIEST","Pagpag",30,"Player-Pagpag",1,0,0,"c"),"Pagpag-Realm")
    H.eq(Main.session,nil,"seen standing far off, so no challenge pops up")
  end)
end)

H.suite("proximity: the challenge entry is hidden on your own portrait, not on a namesake's",function(ns,H)
  withAddon(ns,function(Main)
    local made={}
    local root={CreateButton=function(_,label,fn) made[#made+1]=label end}
    Stub.menuMods["MENU_UNIT_PLAYER"](nil,root,{name="Tester",unit="player"})
    H.eq(#made,0,"your own portrait")
    Stub.units.target={name="Tester",class="PRIEST",isPlayer=true,guid="Player-Namesake"}
    Stub.menuMods["MENU_UNIT_PLAYER"](nil,root,{name="Tester",unit="target"})
    H.eq(#made,1,"another character sharing your first name can be challenged")
  end)
end)

H.suite("proximity: a portrait's menu challenges the unit it was opened on",function(ns,H)
  withAddon(ns,function(Main)
    Stub.units.target={name="Pagpag Halohalo",class="PRIEST",isPlayer=true,guid="Player-Pagpag"}
    local made={}
    local root={CreateButton=function(_,label,fn) made[#made+1]={label=label,fn=fn} end}
    Stub.menuMods["MENU_UNIT_PLAYER"](nil,root,{name="Pagpag",unit="target"})
    made[1].fn()
    H.eq(Main.session and Main.session.state,ns.Session.STATE.OFFERED,"the menu's name did not have to match")
    H.eq(Main.session.peer.name,"Pagpag Halohalo","and the challenge goes to the name the game shows")
    Main.session=nil
    made={}
    Stub.menuMods["MENU_UNIT_PLAYER"](nil,root,{name="Someone Else"})
    made[1].fn()
    H.eq(Main.session,nil,"a name nobody nearby has is still refused")
  end)
end)

H.suite("proximity: fresh world coordinates allow acceptance without targeting",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    local saved=UnitPosition
    _G.UnitPosition=function() return 100,100,5,1 end
    local function invite(x,instance)
      arrive(ns.Protocol.Encode(1,ns.Protocol.KIND.HELLO,ns.Protocol.VERSION,
        ns.Protocol.ADDON_VERSION,"PRIEST","Unseen",30,"Player-Unseen",1,0,0,"c",x,100,5,instance),"Unseen")
    end
    invite(105,1)
    H.ok(Main:NearEnough("Unseen"))
    Main.session:ReadPeerPosition(200,100,5,1)
    H.notOk(Main:NearEnough("Unseen"),"fresh but distant")
    Main.session:ReadPeerPosition(105,100,5,2)
    H.notOk(Main:NearEnough("Unseen"),"different instance")
    Main.session:ReadPeerPosition(105,100,5,1)
    Main.session:Tick(6)
    H.notOk(Main:NearEnough("Unseen"),"stale coordinates cannot accept")
    Main.session:ReadPeerPosition(105,100,5,1)
    H.ok(Main:Accept())
    H.eq(Main.session.state,ns.Session.STATE.SYNC)
    _G.UnitPosition=saved
  end)
end)

H.suite("transport: queued decline survives clearing and changing the peer", function(ns,H)
  withAddon(ns,function(Main)
    challengeFrom(ns,"Foe")
    Main.transport.budget=0
    Main:Decline()
    Main.transport:SetPeer("SomeoneElse")
    Main.transport:Tick()
    local sent=sentMessages()
    local last=sent[#sent]
    H.eq(last.target,"Foe")
    H.eq(ns.Protocol.Decode(last.msg).kind,ns.Protocol.KIND.BYE)
  end)
end)

H.suite("transport: blocked challenge receives decline and outgoing popup closes",function(ns,H)
  withAddon(ns,function(Main)
    Main:Block("Foe"); challengeFrom(ns,"Foe"); Main.transport:Tick()
    local sent=sentMessages(); local last=sent[#sent]
    H.eq(last.target,"Foe"); H.eq(ns.Protocol.Decode(last.msg)[1],"declined")
    Main:Unblock("Foe"); Main:Challenge("Foe")
    arrive(ns.Protocol.Encode(0,ns.Protocol.KIND.BYE,"declined",Main.session.challengeId),"Foe")
    H.eq(Main.session,nil); H.notOk(Main.duelPrompt:IsShown())
    H.ok(Stub.R.chat[#Stub.R.chat]:find("declined",1,true))
  end)
end)

H.suite("transport: acceptance opens deck picker on the invited client",function(ns,H)
  withAddon(ns,function(Main)
    challengeFrom(ns,"Foe")
    H.ok(Main:Accept())
    H.ok(Main.duelDeckPicker:IsShown())
    H.eq(Main.duelDeckPicker,Main.hub)
    H.eq(#Main.hub.deckChoices,#Main.collection.character.decks)
    H.ok(Main.hub.diffName:GetText():find("Foe",1,true))
    H.ok(Main.hub.diffName:GetText():find("Priest",1,true))
    H.notOk(Main.session.committed)
    Main.duelDeckPicker.play:Click()
    H.ok(Main.session.committed)
    H.eq(Main.duelDeckPicker.play.text:GetText(),"Waiting...")
  end)
end)

H.suite("transport: repeated accept preserves deck picker and decline notifies peer",function(ns,H)
  withAddon(ns,function(Main)
    challengeFrom(ns,"Foe"); H.ok(Main:Accept())
    H.notOk(Main:Accept()); H.ok(Main.duelDeckPicker:IsShown())
    Main.transport.budget=0
    Main:Decline(); H.eq(Main.session,nil); H.notOk(Main.hub:IsShown()); H.eq(Main.duelDeckPicker,nil)
    Main.transport:Tick()
    local sent=sentMessages(); local msg=ns.Protocol.Decode(sent[#sent].msg)
    H.eq(msg.kind,ns.Protocol.KIND.BYE); H.eq(msg[1],"declined")
  end)
end)

H.suite("transport: decline command cannot discard a playing duel",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    local session=Main.session
    Main:Decline(); pump()
    H.eq(Main.session,session); H.eq(session.state,ns.Session.STATE.PLAYING)
    H.eq(peer.state,ns.Session.STATE.PLAYING)
  end)
end)

H.suite("transport: incoming end request clearly offers consent and can be declined",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    peer:AskEndDuel(); pump()
    local dialog=Main.endDuelDialog
    H.ok(dialog:IsShown())
    H.ok(dialog.message:GetText():find("No win, loss or forfeit",1,true))
    dialog.buttons[2]:Click(); pump()
    H.eq(peer.state,ns.Session.STATE.PLAYING); H.notOk(Main.game.over)
    peer.clock=(peer.clock or 0)+120
    Main.session.clock=(Main.session.clock or 0)+120
    peer:AskEndDuel(); pump()
    H.eq(Main.endDuelDialog,dialog)
    dialog.buttons[1]:Click(); pump()
    H.eq(Main.session,nil); H.eq(peer.abortReason,"agreed")
    H.eq(Main:Record().wins,0); H.eq(Main:Record().losses,0)
  end)
end)

--[[ Agreeing ends our side at once, which clears the transport's peer and
     queue. A "yes" still waiting there -- WoW's allowance spent mid-game --
     was wiped, so the other player was left in a duel nobody was playing. ]]
H.suite("transport: agreeing to end reaches them even when the line is busy",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    peer:AskEndDuel(); pump()
    Main.transport.budget=0                      -- nothing more may go this tick
    Main.endDuelDialog.buttons[1]:Click()
    H.eq(Main.session,nil,"our side has ended")
    pump()
    H.eq(peer.abortReason,"agreed","and their side heard the yes")
    H.ok(Main.agreedDialog and Main.agreedDialog:IsShown(),"we are told it was agreed")
    H.ok(Main.agreedDialog.message:GetText():find("agreed",1,true))
    Main.agreedDialog.buttons[1]:Click()
    H.notOk(Main.agreedDialog:IsShown()); H.notOk(Main.board.frame:IsShown(),"and taken back to the menu")
  end)
end)

H.suite("transport: the player who asked is told the end was agreed",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main:RequestDuelExit(); Main.exitDialog.confirm:Click(); pump()
    peer:AnswerEndDuel(true); pump()
    H.eq(Main.session,nil)
    H.ok(Main.agreedDialog and Main.agreedDialog:IsShown(),"the asker sees it was agreed")
  end)
end)

H.suite("transport: declined end request button counts down and re-enables",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main:RequestDuelExit(); Main.exitDialog.confirm:Click(); pump()
    peer:AnswerEndDuel(false); pump()
    Main:RequestDuelExit()
    H.eq(Main.exitDialog.confirm.text:GetText(),"Ask Again (2:00)")
    Main.exitDialog.confirm:Click(); H.notOk(Main.session.endAsked)
    Main.session.clock=(Main.session.clock or 0)+61
    Main.exitDialog:GetScript("OnUpdate")()
    H.eq(Main.exitDialog.confirm.text:GetText(),"Ask Again (0:59)")
    Main.session.clock=Main.session.clock+59; peer.clock=(peer.clock or 0)+120
    Main.exitDialog:GetScript("OnUpdate")()
    H.eq(Main.exitDialog.confirm.text:GetText(),"Ask to End Duel")
    Main.exitDialog.confirm:Click(); pump(); H.ok(peer.endInvited)
  end)
end)

--================================================ round 1 review (judges)

H.suite("review: a stranger's failed challenge leaves your practice game alone",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    Main:StartPractice("MAGE","WARRIOR")
    local game,controller=Main.game,Main.controller
    challengeFrom(ns,"Foe")
    Main.session:Abort("disconnected","they stopped answering")
    H.eq(Main.mode,"practice"); H.ok(Main.controller==controller,"the practice game keeps its controller")
    H.ok(Main.game==game); H.eq(Main.session,nil)
  end)
end)

H.suite("review: declining after a finished duel does not close the main menu",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    challengeFrom(ns,"Foe"); Main:Accept()   -- the hub became the duel's deck picker once
    Main:Decline()
    Main:ShowHub(); Main.hub.buttons[1]:Click()   -- the practice book
    challengeFrom(ns,"Foe")
    Main:Decline()
    H.ok(Main.hub:IsShown(),"the menu stays open"); H.ok(Main.hub.botMode,"on the page you were on")
  end)
end)

H.suite("review: an old rejoin offer cannot replace the duel being played",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    local live=Main.session
    Main.rejoinOffer="Other"
    Main:Rejoin()
    H.ok(Main.session==live,"the live duel stays")
  end)
end)

H.suite("review: a secret range answer inside an instance does not refuse",function(ns,H)
  withAddon(ns,function(Main)
    local saved=CheckInteractDistance
    _G.CheckInteractDistance=function() return Stub.Secret() end
    H.ok(ns.Transport.InRange("target"),"unknown is not too far")
    _G.CheckInteractDistance=function() return false end
    H.notOk(ns.Transport.InRange("target"),"a plain no still is")
    _G.CheckInteractDistance=saved
  end)
end)

H.suite("review: closing the duel's deck picker calls the duel off",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    challengeFrom(ns,"Foe"); Main:Accept()
    H.ok(Main.hub:IsShown())
    Main.hub:Hide()
    H.eq(Main.session,nil,"no setup left waiting on a hidden picker")
  end)
end)

H.suite("review: the main menu has a Duel entry that explains itself",function(ns,H)
  withAddon(ns,function(Main)
    Stub.units.target=nil
    Main:ShowHub()
    H.ok(Main.hub.duelButton and Main.hub.duelButton:IsShown(),"Duel a Player is on the menu")
    Main.hub.duelButton:Click()
    H.ok(Main.duelHint and Main.duelHint:IsShown(),"with nobody targeted it says how")
    Stub.units.target={name="Foe",class="PRIEST",isPlayer=true,guid="Player-Foe"}
    Main.duelHint:Hide()
    Main.hub.duelButton:Click()
    H.eq(Main.session and Main.session.state,ns.Session.STATE.OFFERED,"with a player targeted it challenges")
  end)
end)

H.suite("review: /fh duel Name challenges the named player, first-last too",function(ns,H)
  withAddon(ns,function(Main)
    local saved=UnitName
    _G.UnitName=function(u) if u=="target" then return "Pagpag","Halohalo" end return saved(u) end
    SlashCmdList["FOREVERHEARTHSTONE"]("duel Pagpag Halohalo")
    H.eq(Main.session and Main.session.state,ns.Session.STATE.OFFERED)
    _G.UnitName=saved
  end)
end)

H.suite("review: a refused move is said on the table, not only in chat",function(ns,H)
  withAddon(ns,function(Main)
    Main:StartPractice("MAGE","WARRIOR")
    local said
    local real=Main.board.ShowSpeech
    Main.board.ShowSpeech=function(b,side,text) said=text; return real(b,side,text) end
    Main.controller.HandleIntent=function(c) c.refusalVoice="mana"; return false,"not enough mana" end
    Main:OnIntent({kind="PLAY",handIndex=1})
    H.eq(said,"I don't have enough mana.")
    Main.board.ShowSpeech=real
  end)
end)

--================================================ round 2 review (judges)

H.suite("review 2: looking at your collection from the duel deck picker keeps the duel",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    challengeFrom(ns,"Foe"); Main:Accept()
    H.eq(Main.session.state,ns.Session.STATE.SYNC)
    Main:SetHubAside()   -- what opening the collection or the pack room does
    H.notOk(Main.hub:IsShown())
    H.ok(Main.session and Main.session.state==ns.Session.STATE.SYNC,"the duel is still being set up")
    Main:ShowDuelDeckPicker()   -- what closing the collection does
    H.ok(Main.hub:IsShown() and Main.hub.duelSession,"and the picker comes back")
  end)
end)

H.suite("review 2: the duel hint does not come back over the next menu",function(ns,H)
  withAddon(ns,function(Main)
    Stub.units.target=nil
    Main:ShowHub(); Main.hub.duelButton:Click()
    H.ok(Main.duelHint:IsShown())
    Main.hub:Hide(); Main:ShowHub()
    H.notOk(Main.duelHint:IsShown(),"closing the menu put it away")
  end)
end)

H.suite("review 2: the match tells you who goes first, Overload owed and the claim button",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    local t=Main.board.mulliganTitle:GetText()
    H.ok(t:find("You go first",1,true) or t:find("The Coin",1,true),"the mulligan says who goes first")
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    local me=Main.game.players[Main.session.myIndex]
    me.pendingOverload=2; Main.controller:Changed()
    H.ok(Main.board.overloadText:IsShown(),"Overload owed shows")
    H.ok(Main.board.overloadText:GetText():find("2",1,true))
    Main.session.stalling=true; Main:UpdateTableStatus()
    H.ok(Main.board.statusAction and Main.board.statusAction:IsShown(),"a staller gets a Claim Victory button")
    H.eq(Main.board.statusAction.text:GetText(),"Claim Victory")
    Main.session.stalling=false; Main:UpdateTableStatus()
    H.notOk(Main.board.statusAction:IsShown(),"and it goes with the notice")
  end)
end)

H.suite("review 2: right-clicking their hero squelches their emotes",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    local said=0
    local real=Main.board.ShowSpeech
    Main.board.ShowSpeech=function(b,side,text) if side=="foe" then said=said+1 end; return real(b,side,text) end
    Main.board.foeHero.frame:GetScript("OnClick")(Main.board.foeHero.frame,"RightButton")
    H.ok(Main.board.squelched)
    Main:OnSessionEvent("EMOTE",{index=1})
    H.eq(said,0,"a squelched emote shows nothing")
    Main.board.ShowSpeech=real
  end)
end)

--================================================ round 3 review: hostile input

H.suite("review 3: a stranger repeating challenges cannot hold back our own lines",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("nobody")
    for _=1,200 do challengeFrom(ns,"Spammer") end
    for i=1,10 do challengeFrom(ns,"Spammer"..i) end
    local declines=0
    for _,r in ipairs(Main.transport.replies or {}) do if r.raw:find(";BY;declined",1,true) then declines=declines+1 end end
    H.ok(declines<=4,("at most a handful of declines wait (%d)"):format(declines))
  end)
end)

H.suite("review 3: a namesake cannot take over an open challenge",function(ns,H)
  withAddon(ns,function(Main)
    Stub.units.target.guid="Player-Foe"
    Main:Challenge()
    arrive(ns.Protocol.Encode(1,ns.Protocol.KIND.PING,"invited"),"Foe-EvilRealm")
    H.eq(Main.transport.peer,"Foe","a ping from another address changes nobody's address")
    arrive(ns.Protocol.Encode(2,ns.Protocol.KIND.HELLO,ns.Protocol.VERSION,ns.Protocol.ADDON_VERSION,
      "PRIEST","Foe",30,"",1,0,0,"a","","","","",Main.session.challengeId),"Foe-EvilRealm")
    H.eq(Main.session.state,ns.Session.STATE.OFFERED,"an acceptance without their GUID is not theirs")
    H.eq(Main.transport.peer,"Foe")
  end)
end)

H.suite("review 3: a namesake's rejoin offer does not pull you into a rejoin",function(ns,H)
  withAddon(ns,function(Main)
    ForeverHearthstoneCharDB.activeDuel={peer="Foe",at=time and time() or 0}
    arrive(ns.Protocol.Encode(0,ns.Protocol.KIND.REJOIN,"Foe"),"Foe-EvilRealm")
    H.notOk(Main.session and Main.session.state==ns.Session.STATE.REJOINING)
  end)
end)

H.suite("review 3: a stranger's line does not wipe a rematch being settled",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session.state=ns.Session.STATE.OVER; Main.session.rematch="invited"
    local s=Main.session
    arrive("1;HI;1;x;PRIEST","Griefer")
    H.ok(Main.session==s,"the finished duel and its rematch stay")
  end)
end)

--================================================ round 4 review: final diff

H.suite("review 4: the claim notice goes when the staller plays on",function(ns,H)
  withAddon(ns,function(Main)
    local peer,pump=liveDuel(ns,Main)
    Main.session:LocalAction({kind="MULLIGAN",indices={}})
    peer:LocalAction({kind="MULLIGAN",indices={}}); pump()
    local s=Main.session
    s.stalling=true; Main:UpdateTableStatus()
    H.ok(Main.board.statusAction:IsShown())
    s.turnPlayer=nil   -- the next tick sees a different active player
    s:Tick(0.1)
    H.notOk(Main.board.statusAction:IsShown(),"the button goes on its own")
  end)
end)

H.suite("review 4: an unanswered rematch does not lock other challengers out",function(ns,H)
  withAddon(ns,function(Main)
    Main:SetChallengePolicy("anyone")
    local peer,pump=liveDuel(ns,Main)
    Main.session.state=ns.Session.STATE.OVER; Main.session.rematch="asked"
    Main:LeaveGame()
    challengeFrom(ns,"Stranger")
    H.eq(Main.session and Main.session.state,ns.Session.STATE.INVITED,"a new challenge gets through")
  end)
end)
