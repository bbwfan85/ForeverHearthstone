-- Load the actual extracted candidate in TOC order, not the source harness list.
local root=assert(arg[1],'usage: luajit tools/package_smoke.lua PATH/ForeverHearthstone')
local Stub=require('tests.wowstub'); Stub.Install(_G)
Stub.units={player={name='PackageTester',class='MAGE',level=60,isPlayer=true}}
Stub.resting=true
ForeverHearthstoneDB={}; ForeverHearthstoneCharDB={}
local toc=assert(io.open(root..'/ForeverHearthstone.toc'))
local ns,files={},0
local version
for line in toc:lines() do
  line=line:gsub('\r',''):match('^%s*(.-)%s*$')
  local v=line:match('^## Version:%s*(.+)$')
  if v then
    version=v
    C_AddOns={GetAddOnMetadata=function(_,key) if key=='Version' then return version end end}
  end
  if line~='' and not line:match('^#') then
    local path=root..'/'..line:gsub('\\','/')
    assert(loadfile(path))('ForeverHearthstone',ns); files=files+1
  end
end
toc:close()
Stub.Fire('ADDON_LOADED','ForeverHearthstone'); Stub.Fire('PLAYER_LOGIN')
assert(ns.Protocol.ADDON_VERSION==version,'packaged version not advertised in handshake')
local m=ns.Main
m:ShowHub(); assert(m.hub:IsShown())
m:StartPractice('MAGE','PRIEST',nil,nil,1)
assert(m.game and m.game:AwaitingMulligan())
assert(m.board and m.board:IsShown())
m:OnIntent({kind='MULLIGAN',indices={}}); Stub.Advance(3)
assert(#m.game.errors==0,table.concat(m.game.errors,';'))
-- Exercise the packaged hover binding with a damaged, buffed board entity.
m.board:SetSnapshot({board={'CS2_182'},foeBoard={},hand={},
  boardStats={{instanceId=77,atk=8,health=2,maxHealth=7,damaged=true}}})
m.board.myMinions[1].frame:GetScript('OnEnter')()
assert(m.board.hoverCard.atk:GetText()=='8' and m.board.hoverCard.hp:GetText()=='2', 'packaged hover uses printed stats')
m.board:HideTooltip()
m:OnMinimapClick('RightButton'); assert(m.collectionUI.frame:IsShown())
local u=m.collectionUI
u:ShowDecks(); u:EditDeck(nil); u:ShowPackRoom()
m.collection:AddPack('CLASSIC',1); u:OpenPack('CLASSIC'); Stub.Advance(2)
u:RevealCard(1); Stub.Advance(.5)
m:Settings(); assert(m.settings:IsShown())
assert(not ns.DevTest.frame and not ns.DevTest.ticker,'developer mode activated at load')
local checked=0
for _,texture in ipairs(Stub.R.textures) do
  local path=rawget(texture,'texture')
  if type(path)=='string' then
    local rel=path:match('^Interface\\AddOns\\ForeverHearthstone\\(.+)$')
    if rel then
      local file=assert(io.open(root..'/'..rel:gsub('\\','/'),'rb'),'missing rendered texture: '..path)
      file:close(); checked=checked+1
    end
  end
end
print(('PASS packaged TOC load: %d files, %d bound textures; menu/practice/mulligan/collection/decks/pack/Settings'):format(files,checked))
