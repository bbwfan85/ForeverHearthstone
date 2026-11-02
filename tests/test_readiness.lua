local H=require('tests.harness')
local Stub=require('tests.wowstub')

H.suite('readiness: lost terminal action recovers without heartbeat echo',function(ns,H)
  local lab=require('tests.duel_lab').new(31,'clean')
  lab:start(); lab.dropNextAction=true
  lab:action(1,{kind='CONCEDE'})
  H.eq(lab.injected.loss,1)
  H.eq(lab.clients[1].session.state,'OVER'); H.eq(lab.clients[2].session.state,'OVER')
  local a,b=lab.clients[1].session.out.seq,lab.clients[2].session.out.seq
  for _=1,150 do lab:tick() end
  H.eq(lab.clients[1].session.out.seq,a,'no terminal echo loop')
  H.eq(lab.clients[2].session.out.seq,b,'no terminal echo loop')
end)

H.suite('readiness: paired developer script completes on two simulated API endpoints',function(ns,H)
  local Lab=require('tests.duel_lab')
  local lab=Lab.new(77)
  local wire={}
  for i,c in ipairs(lab.clients) do
    c.env.UnitName=function() return c.name end
    c.env.GetNormalizedRealmName=function() return 'Realm' end
    c.env.C_ChatInfo={RegisterAddonMessagePrefix=function() return true end,
      SendAddonMessage=function(prefix,raw,channel,peer)
        wire[#wire+1]={from=i,to=3-i,prefix=prefix,raw=raw,channel=channel}; return 0
      end}
    c.env.CreateFrame=function()
      return {RegisterEvent=function() end,UnregisterEvent=function() end,
        SetScript=function(f,_,fn) f.handler=fn end}
    end
    c.env.C_Timer={NewTicker=function(_,fn)
      return {fn=fn,Cancel=function(t) t.cancelled=true end}
    end}
    H.ok(c.ns.DevTest:Pair(lab.clients[3-i].name..'-Realm','sharedcode'))
  end
  local function tick()
    for _,c in ipairs(lab.clients) do local t=c.ns.DevTest.ticker; if t and not t.cancelled then t.fn() end end
    local pending=wire; wire={}
    for _,m in ipairs(pending) do
      local d=lab.clients[m.to].ns.DevTest
      d.frame.handler(d.frame,'CHAT_MSG_ADDON',m.prefix,m.raw,m.channel,lab.clients[m.from].name..'-Realm')
    end
  end
  for _=1,50 do tick() end
  local a,b=lab.clients[1].ns.DevTest,lab.clients[2].ns.DevTest
  H.ok(a.paired and b.paired)
  H.ok(a.session:Challenge(a.peer)); a.running=true
  for _=1,600 do tick() end
  H.eq(a.session.state,'OVER'); H.eq(b.session.state,'OVER')
  H.eq(Lab.state(a.session.game),Lab.state(b.session.game))
  a:Stop(); b:Stop()
end)

H.suite('readiness: simultaneous bidirectional loss recovers without a NAK deadlock',function(ns,H)
  local lab=require('tests.duel_lab').new(19,'disconnect')
  H.ok(lab.clients[1].ns.Game~=lab.clients[2].ns.Game,'engine namespaces isolated')
  lab:start(); lab.offline=true
  for _=1,100 do lab:tick() end
  lab.offline=false
  local i=lab.clients[1].session.myIndex==lab.clients[1].session.game.activePlayer and 1 or 2
  lab:action(i,{kind='END_TURN'})
  lab:equal()
end)

H.suite('readiness: developer pairing is off by default and rejects strangers',function(ns,H)
  Stub.Install(_G)
  assert(loadfile('ForeverHearthstone/Client/Net/Transport.lua'))('ForeverHearthstone',ns)
  assert(loadfile('ForeverHearthstone/Client/Net/DevTest.lua'))('ForeverHearthstone',ns)
  local d=ns.DevTest
  H.eq(d.frame,nil); H.eq(d.ticker,nil); H.eq(Stub.Count('SendAddonMessage'),0)
  H.notOk(d:Pair('MissingRealm','abcdef'))
  Stub.units={player={name='Local',class='MAGE'}}
  local realmAPI=GetNormalizedRealmName
  _G.GetNormalizedRealmName=function() return 'Realm' end
  H.ok(d:Pair('Tester-Realm','abcdef'))
  _G.GetNormalizedRealmName=realmAPI
  local receive=d.frame:GetScript('OnEvent')
  receive(d.frame,'CHAT_MSG_ADDON',d.PREFIX,'ACK:abcdef','WHISPER','Stranger-Realm')
  H.notOk(d.paired)
  receive(d.frame,'CHAT_MSG_ADDON',d.PREFIX,'ACK:wrong','WHISPER','Tester-Realm')
  H.notOk(d.paired)
  receive(d.frame,'CHAT_MSG_ADDON',d.PREFIX,'ACK:abcdef','WHISPER','Tester-Realm')
  H.ok(d.paired)
  d:Stop(); H.eq(d.ticker,nil); H.eq(d.frame,nil); H.eq(d.peer,nil)
end)

H.suite('readiness: every board capacity and insertion position preserves identity',function(ns,H)
  for side=1,2 do for count=0,7 do for pos=1,count+1 do
    local g=H.NewGame()
    for _=1,count do H.Put(g,side,'CS2_231') end
    local e=g:Summon('EX1_096',side,pos) -- deathrattle: Loot Hoarder
    g.bus:Drain()
    H.eq(#g.players[side].board,math.min(7,count+1))
    if count==7 then H.eq(e,nil,'full board rejects summon')
    else
      H.eq(g.players[side].board[pos],e,'requested insertion')
      H.eq(g:EntityById(e.instanceId),e)
      local ids={}
      for index,card in ipairs(g.players[side].board) do
        H.eq(card.boardIndex,index); H.notOk(ids[card.instanceId]); ids[card.instanceId]=true
      end
      local before=#g.players[side].deck
      e.damage=100; g:ProcessDeaths(); g.bus:Drain()
      H.eq(#g.players[side].deck,before-1,'exactly one deathrattle draw')
      H.eq(#g.players[side].board,count)
    end
    H.noEngineErrors(g)
  end end end
end)

H.suite('readiness: fresh and missed level grants survive repeated saved-table reconstruction',function(ns,H)
  local serialize=require('tests.duel_lab').state
  for _,class in ipairs(ns.BotDecks.Classes()) do
    for _,level in ipairs({1,3,10,11,20,39,41,57,60}) do
      local account,ch={}, {class=class}
      local c=ns.Collection.New(account,ch)
      c:GrantForLevel(class,level); c:GrantPacksForLevel(level)
      local expected=serialize({account,ch})
      for _=1,3 do
        c=ns.Collection.New(account,ch)
        c:GrantForLevel(class,level); c:GrantPacksForLevel(level)
        H.eq(serialize({account,ch}),expected,'repeat login '..class..' '..level)
      end
    end
  end
end)

H.suite('readiness: interrupted pack presentation cannot spend or grant twice',function(ns,H)
  local serialize=require('tests.duel_lab').state
  local account,ch={}, {class='MAGE'}
  local c=ns.Collection.New(account,ch); c:AddPack('HEARTHSTONE',40)
  for seed=1,40 do
    local state=seed
    local rng=function(n) state=(state*48271)%2147483647; return state%n+1 end
    local before=c:TotalPacks()
    local pack=ns.Packs.Open(c,'HEARTHSTONE',{rng=rng})
    H.ok(pack); H.eq(c:TotalPacks(),before-1)
    local expected=serialize({account,ch})
    -- Reload from the in-memory SavedVariables after banking, before any reveal.
    c=ns.Collection.New(account,ch)
    H.eq(serialize({account,ch}),expected,'banked result survives reconstruction')
  end
  H.eq(c:TotalPacks(),0); H.eq(ns.Packs.Open(c,'HEARTHSTONE'),nil)
end)

H.suite('readiness: bot planning hides opponent hand deck and random stream',function(ns,H)
  local g=H.NewGame({class1='PRIEST'})
  local other=g:Clone()
  for _,zone in ipairs({'hand','deck'}) do
    for _,e in ipairs(other.players[2][zone]) do
      e.cardId='EX1_298'; e.printed=other:Printed('EX1_298'); e.damage=99
    end
  end
  other.rngState=17; other.rngCalls=999
  local a,b=ns.AI.PlanningState(g,1,23),ns.AI.PlanningState(other,1,23)
  for _,zone in ipairs({'hand','deck'}) do
    for i,e in ipairs(a.players[2][zone]) do
      H.eq(e.cardId,b.players[2][zone][i].cardId,'unknown identity independent')
      H.eq(e.damage,b.players[2][zone][i].damage,'unknown buffs independent')
    end
  end
  H.eq(a.rngState,b.rngState,'planning random stream independent')
  H.eq(ns.AI.Profile({},g,1).salt,ns.AI.Profile({},other,1).salt)
  H.eq(g.players[2].hand[1].cardId,'CS2_231','real game untouched')
end)

H.suite('readiness: navigation reuse across resolutions and UI scales',function(ns,H)
  Stub.Install(_G)
  Stub.units={player={name='Tester',class='MAGE',isPlayer=true,level=60}}
  ForeverHearthstoneDB={}; ForeverHearthstoneCharDB={}
  for _,file in ipairs({'Net/Transport','Rewards','UI/Widgets','UI/Board','UI/Collection','Main'}) do
    assert(loadfile('ForeverHearthstone/Client/'..file..'.lua'))('ForeverHearthstone',ns)
  end
  Stub.Fire('ADDON_LOADED','ForeverHearthstone'); Stub.Fire('PLAYER_LOGIN')
  local m=ns.Main
  local function cycle(w,h,scale)
    UIParent:SetSize(w,h); UIParent:SetScale(scale)
    m:ShowHub(); H.ok(m.hub:IsShown())
    m:OnMinimapClick('RightButton')
    local u=m.collectionUI
    H.ok(u.frame:IsShown()); H.notOk(m.hub:IsShown())
    u:ShowDecks(); u:EditDeck(nil); u:ShowPackRoom()
    m:Settings(); H.ok(m.settings:IsShown()); m.settings:Hide()
    u:Hide(); m:ShowHub(); H.notOk(u.frame:IsShown())
    m:OnMinimapClick('LeftButton'); H.notOk(m.hub:IsShown())
    Stub.Advance(.2)
  end
  --[[ Warm up at EVERY size first: windows open scaled to the screen
       (docs/39), so a bigger screen shows more cards per page and builds
       those widgets once. What must not grow is repeated navigation. ]]
  local sizes={{1280,720,1},{800,600,.7},{1920,1080,1},{2560,1440,1.25}}
  for _,s in ipairs(sizes) do cycle(unpack(s)) end
  local frames,textures=#Stub.R.frames,#Stub.R.textures
  for _,s in ipairs(sizes) do
    for _=1,10 do cycle(unpack(s)) end
  end
  H.eq(#Stub.R.frames,frames,'navigation frame count bounded after warmup')
  H.eq(#Stub.R.textures,textures,'navigation texture count bounded after warmup')
end)
