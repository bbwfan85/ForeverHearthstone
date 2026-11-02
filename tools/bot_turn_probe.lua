-- Headless check that a practice bot takes its turns with the full UI loaded
-- (the report "the bot never takes its turn"). luajit tools/bot_turn_probe.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local H=require('tests.harness'); local ns=H.LoadEngine()
local Stub=require('tests.wowstub'); Stub.Install(_G)
Stub.units={player={name='Probe',class='ROGUE',isPlayer=true,level=60}}
ForeverHearthstoneDB={}; ForeverHearthstoneCharDB={}
for _,path in ipairs({'Net/Transport','Rewards','UI/Widgets','UI/Board','UI/Collection','Main'}) do
 assert(loadfile('ForeverHearthstone/Client/'..path..'.lua'))('ForeverHearthstone',ns)
end
Stub.Fire('ADDON_LOADED','ForeverHearthstone'); Stub.Fire('PLAYER_LOGIN')
local errors = {}
local M = ns.Main
M:StartPractice('ROGUE','MAGE')
M.board.frame:SetSize(1280,720)
M:OnIntent({kind='CONFIRM_MULLIGAN'})
for i=1,40 do Stub.Advance(0.25) end
for turn=1,6 do
  local g=M.game
  if g.activePlayer==1 then
    local ok,err=pcall(function() M:OnIntent({kind='END_TURN'}) end)
    if not ok then errors[#errors+1]=err end
  end
  local waited=0
  while M.game.activePlayer~=1 and waited<60 and not M.game.over do
    local ok,err=pcall(Stub.Advance,0.25); waited=waited+0.25
    if not ok then errors[#errors+1]=err; break end
  end
  print(('turn %d: active=%s waited=%.1fs locked=%s aiRunning=%s over=%s'):format(
    g.turn, tostring(M.game.activePlayer), waited, tostring(M.board.presentationLocked), tostring(M.aiRunning), tostring(M.game.over)))
end
for _,e in ipairs(errors) do print('ERROR', e) end
