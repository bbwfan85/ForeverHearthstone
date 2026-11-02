package.path='./?.lua;./?/init.lua;'..package.path
local Lab=require('tests.duel_lab')
local seed=tonumber(arg[1]) or 1
local fault=arg[2] or 'clean'
local difficulty=tonumber(arg[3]) or 2
local output=arg[4] or 'duel-failure.log'
local lab=Lab.new(seed,fault)
local started=os.clock()
local ok,err=xpcall(function()
  if fault=='incompatible' then
    lab.clients[2].ns.Protocol.VERSION=lab.clients[2].ns.Protocol.VERSION+1
    lab.clients[1].session:Challenge('Brann'); lab:settle()
    assert(lab.clients[2].session.abortReason=='version','expected version rejection')
    assert(not lab.clients[1].session.game and not lab.clients[2].session.game,'incompatible match started')
    return
  end
  lab:start()
  if fault=='terminal-loss' then
    lab.dropNextAction=true; lab:action(1,{kind='CONCEDE'})
    assert(lab.injected.loss==1,'final action was not dropped'); return
  end
  if fault=='concede' then lab:action(1,{kind='CONCEDE'}); return end
  if fault=='reload' then
    lab:make(2).session:RequestRejoin('Ayla'); lab:settle(); lab:equal()
  elseif fault=='disconnect' then
    lab.offline=true
    for _=1,100 do lab:tick() end
    lab.offline=false; lab:settle(); lab:equal()
  elseif fault=='pause' then
    lab.clients[1].session:Pause('away'); lab:settle()
    assert(not lab.clients[1].session:LocalAction({kind='END_TURN'}),'paused action accepted')
    lab.clients[1].session:Resume(); lab:settle(); lab:equal()
  end
  for n=1,1800 do
    local g=lab.clients[1].session.game
    if g.over then break end
    local i=lab.clients[1].session.myIndex==g.activePlayer and 1 or 2
    local c=lab.clients[i]
    local a=c.ns.AI.NextAction(c.session.game,c.session.myIndex,nil,{difficulty=difficulty}) or {kind='END_TURN'}
    lab:action(i,a)
  end
  assert(lab.clients[1].session.game.over,'action budget exhausted')
  if fault=='loss' then assert(lab.lost,'loss scenario failed to inject a lost action') end
  if fault=='mixed' then
    for kind,count in pairs(lab.injected) do assert(count>0,'mixed scenario did not inject '..kind) end
  end
end,debug.traceback)
local f=assert(io.open(output,'w'))
f:write(('seed=%d fault=%s difficulty=%d cpu=%.3f actions=%d luaKB=%.1f\n'):format(seed,fault,difficulty,os.clock()-started,#lab.actions,collectgarbage('count')))
f:write(('Replay: luajit tools/duel_lab.lua %d %s %d %s\n'):format(seed,fault,difficulty,output))
f:write(ok and 'PASS\n' or ('FAIL '..tostring(err)..'\n'))
f:write(('injected loss=%d throttle=%d duplicate=%d\n'):format(lab.injected.loss,lab.injected.throttle,lab.injected.duplicate))
f:write(table.concat(lab.trace,'\n')); f:close()
if not ok then
  for i,c in ipairs(lab.clients) do
    local state=assert(io.open(output..'.client'..i,'w'))
    state:write(Lab.state(c.session.game)); state:close()
  end
end
print(('duel seed=%d fault=%s difficulty=%d actions=%d cpu=%.2fs %s'):format(seed,fault,difficulty,#lab.actions,os.clock()-started,ok and 'PASS' or tostring(err)))
os.exit(ok and 0 or 1)
