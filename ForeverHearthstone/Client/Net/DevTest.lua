-- Opt-in protocol smoke test. No frames, timers or messages until explicit pair.
-- Separate prefix/session: never challenges through normal gameplay or grants rewards.
local _,ns=...
local Dev={PREFIX='FHLAB1'}
ns.DevTest=Dev
function Dev:Note(text)
  self.trace=self.trace or {}
  if #self.trace>=500 then table.remove(self.trace,1) end
  self.trace[#self.trace+1]=tostring(text)
end
function Dev:Stop()
  if self.ticker then self.ticker:Cancel(); self.ticker=nil end
  if self.frame then self.frame:UnregisterEvent('CHAT_MSG_ADDON'); self.frame:SetScript('OnEvent',nil); self.frame=nil end
  if self.transport then self.transport:Stop() end
  self.peer=nil; self.paired=nil; self.session=nil; self.running=nil
end
function Dev:Pair(peer,code)
  self:Stop()
  if not peer or not peer:find('-',1,true) or not code or not code:match('^%w%w%w%w%w%w+$') or #code>24 then
    return false,'Use /fh dev pair Name-Realm sharedcode (6-24 letters/digits). Both peers must opt in.'
  end
  if not ns.Transport.Registered(C_ChatInfo.RegisterAddonMessagePrefix(self.PREFIX)) then return false,'Test prefix registration refused' end
  self.peer,self.code,self.age,self.trace=peer,code,0,{}
  self.lastPair,self.lastMove=nil,nil
  local name,realm=UnitName('player')
  realm=realm or (GetNormalizedRealmName and GetNormalizedRealmName())
  if not name or not realm then self:Stop(); return false,'Player name/realm API unavailable' end
  name=name..'-'..realm
  self.transport=ns.Transport.New({onMessage=function(raw) self.session:Receive(raw) end,
    onFault=function(err) self:Note('FAULT '..err); self.running=nil end})
  self.transport:SetPeer(peer)
  self.transport.Put=function(_,raw)
    self:Note('SEND '..raw)
    return ns.Transport.Outcome(C_ChatInfo.SendAddonMessage(self.PREFIX,raw,'WHISPER',peer))
  end
  self.session=ns.Session.New({name=name,class='MAGE',deck=ns.Controller.BasicDeck('MAGE'),
    nonce=code..':'..name,send=function(raw) self.transport:Send(raw) end,
    onEvent=function(event) self:Note('EVENT '..event) end})
  self.frame=CreateFrame('Frame'); self.frame:RegisterEvent('CHAT_MSG_ADDON')
  self.frame:SetScript('OnEvent',function(_,_,prefix,raw,channel,sender)
    if prefix~=self.PREFIX or channel~='WHISPER' or not ns.Transport.SameName(sender,self.peer) then return end
    if raw=='PAIR:'..self.code then
      self.transport:Put('ACK:'..self.code)
    elseif raw=='ACK:'..self.code then
      self.paired=true; self:Note('PAIRED '..sender)
    elseif self.paired then
      self:Note('RECV '..raw); self.transport:OnReceive(raw,sender)
      if self.session.state==ns.Session.STATE.INVITED then self.session:Accept(); self.running=true end
    end
  end)
  self.ticker=C_Timer.NewTicker(.1,function()
    self.age=self.age+.1
    if self.age>600 then self:Note('STOP time limit'); self:Stop(); return end
    self.transport:Tick(); self.session:Tick(.1)
    if not self.paired then
      if self.age>60 then self:Note('STOP pairing timeout'); self:Stop(); return end
      if not self.lastPair or self.age-self.lastPair>=2 then
        self.lastPair=self.age; self.transport:Put('PAIR:'..self.code)
      end
      return
    end
    if self.running and self.session.state==ns.Session.STATE.PLAYING
      and (not self.lastMove or self.age-self.lastMove>=2) then
      self.lastMove=self.age
      local g=self.session.game; local me=self.session.myIndex
      local action
      if g:AwaitingMulligan(me) then action={kind='MULLIGAN',indices={}}
      elseif g.phase=='PLAY' and g.activePlayer==me then
        action={kind=g.turn>=8 and 'CONCEDE' or 'END_TURN'}
      end
      if action then
        local ok,why=self.session:LocalAction(action)
        self:Note('ACTION '..action.kind..' '..tostring(ok)..' '..tostring(why))
        if not ok then self.running=nil end
      end
    end
  end)
  return true,'Pairing only with '..peer..'; run /fh dev start on ONE client after both report PAIRED.'
end
function Dev:Command(text)
  local cmd,rest=text:match('^(%S+)%s*(.-)$')
  local ok,message
  if cmd=='pair' then
    local peer,code=rest:match('^(%S+)%s+(%S+)$'); ok,message=self:Pair(peer,code)
  elseif cmd=='stop' then self:Stop(); message='Developer test stopped.'
  elseif cmd=='start' then
    if not self.paired then message='Both peers must pair first.'
    else ok,message=self.session:Challenge(self.peer); self.running=ok; message=message or 'Script started.' end
  elseif cmd=='trace' then for _,line in ipairs(self.trace or {}) do ns.Main:Print(line) end; return
  else
    message='Developer test: '..tostring(self.session and self.session.state or 'disabled')..' paired='..tostring(self.paired or false)
    if self.session and self.session.game then message=message..' hash='..self.session.game:StateHash() end
  end
  ns.Main:Print(message)
end
