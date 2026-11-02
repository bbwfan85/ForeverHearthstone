-- Two isolated Lua 5.1 addon namespaces; only the WoW message API is simulated.
local H = require('tests.harness')
local Lab = {}
local function client(name, send)
  local env = setmetatable({}, {__index = _G})
  env._G = env
  env.C_ChatInfo = {SendAddonMessage = send}
  local ns = {}
  for _, path in ipairs(H.LOAD_ORDER) do
    setfenv(assert(loadfile(path)), env)('ForeverHearthstone', ns)
  end
  setfenv(assert(loadfile('ForeverHearthstone/Client/Net/Transport.lua')), env)('ForeverHearthstone', ns)
  return {ns = ns, env = env, name = name}
end

-- Canonical graph encoding: compare all mutable engine fields, including hidden
-- zones, IDs, RNG, triggers and pending choices, rather than the wire's small hash.
-- Functions/metatables are code, not state. Bus.game cycles are encoded as refs.
function Lab.state(game)
  local seen, serial = {}, 0
  local function encode(v)
    local t = type(v)
    if t == 'function' then return '<code>' end
    if t ~= 'table' then return t .. ':' .. tostring(v) end
    if seen[v] then return '@' .. seen[v] end
    serial = serial + 1; seen[v] = serial
    local keys, out = {}, {}
    for k in pairs(v) do assert(type(k) ~= 'table', 'table key needs canonicalization'); keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a)<tostring(b) end)
    for _, k in ipairs(keys) do out[#out+1] = encode(k)..'='..encode(v[k]) end
    return '{'..table.concat(out, ',')..'}'
  end
  return encode(game)
end

function Lab.new(seed, fault)
  local lab = {seed=seed, fault=fault or 'clean', clock=0, wire={}, trace={}, actions={}, clients={},
    injected={loss=0,throttle=0,duplicate=0}, buckets={}, packets=0}
  function lab:record(s) self.trace[#self.trace+1]=('%.1f %s'):format(self.clock,s) end
  function lab:make(i)
    local c = client(i==1 and 'Ayla' or 'Brann', function(prefix, raw, channel, peer)
      self:record('SEND '..i..' '..raw)
      if self.dropNextAction and raw:find(';AC;',1,true) then
        self.dropNextAction=nil; self.injected.loss=self.injected.loss+1
        self:record('DROP requested action'); return 0
      end
      if self.fault=='mixed' then
        local b=self.buckets[i] or {tokens=3,at=self.clock}
        b.tokens=math.min(3,b.tokens+self.clock-b.at); b.at=self.clock; self.buckets[i]=b
        if b.tokens<1 then
          self.injected.throttle=self.injected.throttle+1; self:record('THROTTLE '..i); return 3
        end
        b.tokens=b.tokens-1
        self.packets=self.packets+1
        if (raw:find(';AC;',1,true) or raw:find(';PI;',1,true)) and (self.packets+self.seed)%11==0 then
          self.injected.loss=self.injected.loss+1; self:record('DROP mixed '..i); return 0
        end
      end
      if self.offline then self:record('DROP disconnected'); return 0 end
      if self.fault=='loss' and not self.lost and raw:find(';AC;',1,true) then
        self.lost=true; self:record('DROP once'); return 0
      end
      local delay = self.fault=='clean' and 0 or .1+((#raw+self.seed)%4)*.1
      self.wire[#self.wire+1]={at=self.clock+delay,to=3-i,from=i,raw=raw}
      if self.fault=='duplicate' or (self.fault=='mixed' and (self.packets+self.seed)%5==0) then
        self.injected.duplicate=self.injected.duplicate+1
        self.wire[#self.wire+1]={at=self.clock+delay+.7,to=3-i,from=i,raw=raw}
      end
      return 0
    end)
    self.clients[i]=c
    c.transport=c.ns.Transport.New({onMessage=function(raw) c.session:Receive(raw) end,
      onFault=function(e) error(e) end})
    c.transport:SetPeer(i==1 and 'Brann' or 'Ayla')
    local classes={'MAGE','PRIEST'}
    c.session=c.ns.Session.New({name=c.name,class=classes[i],nonce=tostring(self.seed)..':'..i,
      deck=c.ns.Controller.BasicDeck(classes[i]),send=function(raw) c.transport:Send(raw) end,
      onEvent=function(e) self:record('EVENT '..i..' '..e) end})
    return c
  end
  lab:make(1); lab:make(2)
  function lab:tick()
    self.clock=self.clock+.1
    for _,c in ipairs(self.clients) do c.transport:Tick(); c.session:Tick(.1) end
    local pending=self.wire; self.wire={}
    for _,m in ipairs(pending) do
      if m.at<=self.clock then
        self:record('RECV '..m.to..' '..m.raw)
        self.clients[m.to].transport:OnReceive(m.raw,self.clients[m.from].name)
      else self.wire[#self.wire+1]=m end
    end
  end
  function lab:settle()
    for _=1,200 do
      self:tick()
      local a,b=self.clients[1],self.clients[2]
      if #self.wire==0 and #a.transport.queue==0 and #b.transport.queue==0 then
        local ga,gb=a.session.game,b.session.game
        if not ga and not gb then return end
        if ga and gb and Lab.state(ga)==Lab.state(gb) then return end
      end
    end
    error('did not settle: divergence or unrecovered network gap')
  end
  function lab:equal()
    local a,b=self.clients[1].session,self.clients[2].session
    assert(a.state==b.state,'session states differ: '..a.state..'/'..b.state)
    assert(Lab.state(a.game)==Lab.state(b.game),'authoritative state differs')
    assert(#a.game.errors==0 and #b.game.errors==0,'engine errors')
  end
  function lab:action(i,a)
    self.actions[#self.actions+1]=i..' '..assert(self.clients[i].ns.Protocol.EncodeAction(a))
    self:record('ACTION '..self.actions[#self.actions])
    local ok,why=self.clients[i].session:LocalAction(a); assert(ok,why)
    self:settle(); self:equal()
  end
  function lab:start()
    assert(self.clients[1].session:Challenge('Brann')); self:settle()
    assert(self.clients[2].session:Accept()); self:settle(); self:equal()
    self:action(1,{kind='MULLIGAN',indices={1}})
    self:action(2,{kind='MULLIGAN',indices={}})
  end
  return lab
end
return Lab
