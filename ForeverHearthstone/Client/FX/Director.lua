--[[ Client/FX/Director.lua

  WHAT TO PLAY, AND WHEN.

  Client/FX/Choreography.lua knows how a minion lands, how a pack cracks and how
  the rope burns. Until now nothing decided WHICH of those to play during a
  match, so the whole library sat unused while real games happened in silence.
  This is that decision, and it is pure: no WoW API, no frames, no timers of its
  own -- it is handed actions and elapsed time and returns a plan.

  That means the feel of a turn is testable. "Playing a minion animates the
  minion that was played", "the rope starts fifteen seconds before the turn
  ends, once", "nothing animates on the opponent's private business" are all
  assertions in tests/test_director.lua rather than things you check by staring.

  ========================================================= DRIVEN BY ACTIONS

  The alternative was diffing snapshots: see a new minion, animate it. That is
  worse for a specific reason -- a minion can arrive on the board for half a
  dozen reasons (played, summoned by a deathrattle, copied, resurrected) and the
  diff cannot tell them apart, so it would play the "card from hand" animation
  for a Deathrattle token. Actions say what actually happened.

  ================================================================= THE ROPE

  The rope is the one piece of choreography that needs a CLOCK. Hearthstone
  gives 75 seconds a turn and shows the rope for the last 15; Nozdormu is
  already implemented in the engine (Game:TurnSeconds returns 15 for both
  players while he is out) and has been waiting for something to consume it.

  The timer runs on each client for ITS OWN player's turn. When it expires, that
  client ends its own turn -- which in a duel is an ordinary END_TURN action
  that crosses the wire like any other. Nobody times anybody else's turn, so
  there is nothing to disagree about.
]]
local ADDON, ns = ...

local Director = {}
Director.__index = Director
ns.Director = Director

function Director.New(opts)
  opts = opts or {}
  local d = setmetatable({}, Director)
  d.me      = opts.player or 1
  d.onPlay  = opts.onPlay or function() end      -- (sequenceName, opts)
  d.onExpire = opts.onExpire or function() end   -- the turn ran out
  --[[ Fired whenever the clock restarts. The rope is the only thing on screen
       driven by the clock rather than by the snapshot, so it is the only thing
       that has to be told the clock went back to the start. ]]
  d.onReset = opts.onReset or function() end
  d.turnStarted = nil       -- seconds elapsed in the current turn
  d.turn = nil
  d.ropeShown = false
  return d
end

-- ================================================================ actions

--[[ Decide what an action looks like. Returns a list of plans:

       { sequence = "PlayMinion", opts = { ... } }

     A list rather than one, because a single action can be two beats -- a
     Battlecry that kills something is the play and then the impact -- and
     because returning nothing is a perfectly good answer for an action with no
     visual of its own. ]]
function Director:Plan(game, player, action, before)
  local plans = {}
  if not (game and action) then return plans end
  local kind = action.kind

  if kind == "PLAY_CARD" then
    --[[ The card is already gone from hand by the time this runs, so the card's
         identity comes from the SNAPSHOT TAKEN BEFORE the action. Reading it
         afterwards is how you end up animating whatever slid into that hand
         slot. ]]
    local cardId = before and before.playedCardId
    local printed = cardId and game:Printed(cardId)
    local type = printed and printed.type or "SPELL"
    if type == "MINION" then
      local played = before and before.playedInstanceId and game:EntityById(before.playedInstanceId)
      plans[#plans + 1] = { sequence = "PlayMinion", opts = {
        cardIndex = action.handIndex or 1,
        slot = played and played.boardIndex or action.position or (#game.players[player].board),
        instanceId = before and before.playedInstanceId,
        mine = (player == self.me),
      } }
    else
      plans[#plans + 1] = { sequence = "PlaySpell", opts = {
        cardId = cardId,
        cardIndex = action.handIndex or 1,
        targeted = action.targetId ~= nil,
        targetSide = before and before.targetSide == self.me and "self" or "foe",
        targetIndex = before and before.targetIndex,
        targetIsHero = before and before.targetIsHero,
        mine = (player == self.me),
      } }
    end

  elseif kind == "HERO_POWER" then
    local power = game.players[player].heroPower
    local hunter = power and power.cardId == "DS1h_292"
    local targetSide = before and before.targetSide
    if not targetSide and hunter then targetSide = game:Opponent(player) end
    plans[#plans + 1] = {sequence="HeroPower", opts={mine=player == self.me,
      cardId=power and power.cardId,
      targeted=targetSide ~= nil,
      targetSide=targetSide == self.me and "self" or "foe",
      targetIndex=before and before.targetIndex,
      targetIsHero=(before and before.targetIsHero) or (hunter and not action.targetId)}}
  elseif kind == "ATTACK" then
    --[[ The combatants come from the BEFORE-snapshot for the same reason the
         played card does, and it bites harder here: Game:EntityById searches
         the boards, so anything that died in this attack is already
         unfindable. Looking it up afterwards reports that nobody died, in
         exactly the case where something did. ]]
    local attacker = (before and before.attacker) or game:EntityById(action.attackerId)
    local defender = (before and before.defender) or game:EntityById(action.targetId)

    --[[ WHOSE SIDE OF THE TABLE. An index alone is ambiguous -- board slot 1
         exists on both boards -- and the sequence used to resolve every index
         against the local player's widgets. So an attack made by the practice
         opponent animated one of YOUR minions instead of theirs, and with an
         empty board it animated a card in your hand. From the outside that is
         indistinguishable from nothing happening, which is what an enemy swing
         looked like: the health number moved and nothing else did. ]]
    --[[ Taken from the BEFORE-snapshot, for the same reason the identities
         are: control can change during an attack, and an entity that has left
         play has no side at all. ]]
    local function sideOf(e, remembered)
      local owner = remembered or (e and e.controller)
      if not owner then return nil end
      return (owner == self.me) and "self" or "foe"
    end
    --[[ A hero has a handle of its own and no board index, so the defender
         being a hero has to be said explicitly -- `boardIndex` on a hero is nil
         and would otherwise fall back to slot 1, hitting a minion. ]]
    local heroHit = defender ~= nil and defender.printed
                    and defender.printed.type == ns.CARDTYPE.HERO or false

    local aSide = sideOf(attacker, before and before.attackerSide)
    local dSide = sideOf(defender, before and before.defenderSide)
    plans[#plans + 1] = { sequence = "Attack", opts = {
      attackerSide  = aSide,
      attackerIsHero = attacker and attacker.printed.type == ns.CARDTYPE.HERO or false,
      attackerIndex = (before and before.attackerIndex)
                      or (attacker and attacker.boardIndex) or 1,
      defenderSide  = dSide,
      defenderIndex = (before and before.defenderIndex)
                      or (defender and defender.boardIndex) or 1,
      defenderIsHero = heroHit,
      --[[ The lunge goes UP the table when you swing and DOWN when they do,
           because the two boards are stacked. A sequence that always lunged
           one way had the opponent's minions attacking away from you. The real
           distance is asked of the stage, which is the only thing that knows
           where the two widgets actually are -- this is the fallback. ]]
      dy = (aSide == "foe") and -120 or 120,
      --[[ Whether the attacker died decides whether the sequence ends on an
           impact or on a death. Read AFTER the attack, which is the one thing
           that must not come from the before-snapshot. ]]
      attackerDied = attacker ~= nil and attacker.zone ~= ns.ZONE.PLAY,
      defenderDied = defender ~= nil and defender.zone ~= ns.ZONE.PLAY,
      --[[ A killing blow gets the heavier sound and a bigger shake. ]]
      lethal = defender ~= nil and defender.zone ~= ns.ZONE.PLAY,
      mine = (player == self.me),
    } }

  elseif kind == "END_TURN" then
    --[[ A turn ending is not an animation, but it IS the clock: this is where
         the rope for the next turn is armed. ]]
    self:ResetTurn(game)
  end

  self:PlanTriggers(game, before, plans)
  self:PlanEffects(game, before, plans)
  return plans
end

-- Event cues also cover abilities whose source has already died. Freeze slots
-- before resolution so a death cannot redirect its effect to a neighbour.
function Director:PlanEffects(game, before, plans)
  if not (before and before.eventSeq) then return end
  local positions = {}
  for id, pos in pairs(before.effectPositions or {}) do positions[id] = pos end
  for side = 1, 2 do
    for _, row in ipairs({game.players[side].board, game.players[side].graveyard}) do
      for _, e in ipairs(row) do
        if not positions[e.instanceId] then
          positions[e.instanceId] = {side=side, index=e.boardIndex or e.lastBoardIndex,
            cardId=e.cardId}
        end
      end
    end
  end
  local beat = 0
  for _, event in ipairs(game.bus.log) do
    if event.seq > before.eventSeq then
      local kind, id
      if event.event == ns.EVENT.DEATHRATTLE then kind, id = "deathrattle", event.entityId
      elseif event.event == ns.EVENT.SILENCED then kind, id = "silence", event.entityId
      elseif event.event == ns.EVENT.BATTLECRY_RESOLVED then kind, id = "battlecry", event.entityId
      elseif event.event == ns.EVENT.MINION_SUMMONED then
        -- The card played from hand already has its own landing animation.
        if event.entityId ~= before.playedInstanceId then kind, id = "summon", event.entityId end
      elseif event.event == ns.EVENT.DAMAGE_DEALT or event.event == ns.EVENT.HEALED then
        local source = event.src and game:Printed(event.src)
        if source and source.type == ns.CARDTYPE.MINION and not event.isCombat then
          kind, id = event.event == ns.EVENT.HEALED and "heal" or "damage", event.targetId
        end
      end
      local pos = id and positions[id]
      if kind == "battlecry" and pos then
        local script = game:ScriptFor(pos.cardId)
        if not (script and (script.battlecry or script.combo)) then kind = nil end
      end
      if kind and pos then
        plans[#plans+1] = {sequence="AbilityEffect", opts={kind=kind, cardId=pos.cardId, instanceId=id,
          side=pos.side == self.me and "self" or "foe", index=pos.index,
          isHero=pos.isHero, at=0.48 + math.min(beat, 12)*0.10}}
        beat = beat + 1
      end
    end
  end
  for side = 1, 2 do
    for _, e in ipairs(game.players[side].board) do
      local old = before.effectPositions and before.effectPositions[e.instanceId]
      local kind = old and old.cardId ~= e.cardId and "transform"
        or old and old.atk and (old.atk ~= game:AttackValue(e) or old.maxHp ~= e:MaxHealth()) and "buff"
      if kind then
        plans[#plans+1] = {sequence="AbilityEffect",opts={kind=kind,
          side=side==self.me and "self" or "foe", index=old.index, at=0.55}}
      end
    end
  end
end

--[[ TRIGGERED ABILITIES. Every minion whose trigger resolved during this
     action (Knife Juggler's knife, Ragnaros at the end of the turn, Flesheating
     Ghoul growing) gets a beat of its own: the minion pulses, and its trigger
     recording plays where Hearthstone has one. Staggered after the action's own
     beat, and capped, so a board of triggers reads as a ripple, not a blur. ]]
Director.MAX_TRIGGER_BEATS = 4
function Director:PlanTriggers(game, before, plans)
  local fired = game.bus and game.bus.fired
  if not (fired and before and before.firedCount) then return end
  local seen, beats = {}, 0
  for i = before.firedCount + 1, #fired do
    local f = fired[i]
    local e = game:EntityById(f.instanceId)
    local printed = e and e.printed
    if not seen[f.instanceId] and printed and printed.type == ns.CARDTYPE.MINION
       and e.zone == ns.ZONE.PLAY and beats < Director.MAX_TRIGGER_BEATS then
      seen[f.instanceId] = true
      plans[#plans + 1] = { sequence = "MinionTrigger", opts = {
        cardId = f.cardId,
        side = (e.controller == self.me) and "self" or "foe",
        index = e.boardIndex,
        at = 0.30 + 0.16 * beats,
      } }
      beats = beats + 1
    end
  end
end

--[[ What has to be remembered BEFORE an action is applied, because applying it
     destroys the evidence. Small on purpose -- a full snapshot every action
     would be the most expensive thing in the client. ]]
local function historyStats(game, entity)
  if not entity then return nil end
  return { cardId=entity.cardId, instanceId=entity.instanceId,
    atk=game:AttackValue(entity), hp=entity:Health(), maxHp=entity:MaxHealth() }
end

function Director.Before(game, player, action)
  if not (game and action) then return nil end
  local before = Director.BeforeAction(game, player, action)
  --[[ Where the bus's list of resolved triggers stands, so the plan can show
       exactly the triggers THIS action set off -- including an END_TURN's,
       which is where end-of-turn and start-of-turn triggers fire. ]]
  before = before or { eventSeq = game.bus and game.bus.seq }
  before.firedCount = game.bus and game.bus.fired and #game.bus.fired or 0
  before.effectPositions = {}
  for side = 1, 2 do
    local p = game.players[side]
    before.effectPositions[p.hero.instanceId] = {side=side, isHero=true, cardId=p.hero.cardId}
    for _, e in ipairs(p.board) do
      before.effectPositions[e.instanceId] = {side=side, index=e.boardIndex, cardId=e.cardId,
        atk=game:AttackValue(e), maxHp=e:MaxHealth()}
    end
  end
  local played = action.kind == "PLAY_CARD" and game.players[player].hand[action.handIndex]
  before.playedInstanceId = played and played.instanceId
  local source = action.kind == "ATTACK" and game:EntityById(action.attackerId)
    or action.kind == "PLAY_CARD" and game.players[player].hand[action.handIndex]
  before.sourceStats = historyStats(game, source)
  before.targetStats = historyStats(game, action.targetId and game:EntityById(action.targetId))
  before.historyEntities = { sourceStats=source,
    targetStats=action.targetId and game:EntityById(action.targetId) }
  return before
end

function Director.BeforeAction(game, player, action)
  if action.kind == "PLAY_CARD" or action.kind == "HERO_POWER" then
    local card = game.players[player].hand[action.handIndex]
    local target = action.targetId and game:EntityById(action.targetId)
    if not target and action.kind == "HERO_POWER" and game.players[player].heroPower.cardId == "DS1h_292" then
      target = game.players[game:Opponent(player)].hero
    end
    return { eventSeq=game.bus.seq, playedCardId = card and card.cardId,
      targetCardId=target and target.cardId,
      targetId=target and target.instanceId,
      targetSide=target and target.controller, targetIndex=target and target.boardIndex,
      targetIsHero=target and target.printed.type == ns.CARDTYPE.HERO }
  elseif action.kind == "ATTACK" then
    --[[ THE POSITIONS ARE EVIDENCE TOO, and they are destroyed by the attack.

         This used to keep only the two entities and read `boardIndex` off them
         afterwards. But a minion that dies swinging has been taken off the
         board by then, so its boardIndex is nil -- and the plan fell back to
         slot 1. Every trade where the attacker died therefore animated the
         LEFTMOST minion instead, which from the outside looks exactly like that
         minion attacking a second time.

         Surviving minions are no better off: a death anywhere in the row
         reindexes everything to its right, so the indices read afterwards
         belong to whoever slid into those slots. ]]
    local attacker = game:EntityById(action.attackerId)
    local defender = game:EntityById(action.targetId)
    return {
      eventSeq=game.bus.seq,
      attacker = attacker, defender = defender,
      attackerIndex = attacker and attacker.boardIndex or nil,
      defenderIndex = defender and defender.boardIndex or nil,
      attackerSide  = attacker and attacker.controller or nil,
      defenderSide  = defender and defender.controller or nil,
    }
  end
  return nil
end

function Director.Outcomes(game, before)
  local outcomes = {}
  if not before then return outcomes end
  -- Plain values survive later damage, buffs, deaths and reuse of board slots.
  for _, key in ipairs({"sourceStats", "targetStats"}) do
    local old = before[key]
    outcomes[key] = old and historyStats(game, game:EntityById(old.instanceId)
      or before.historyEntities and before.historyEntities[key]) or nil
  end
  for _,e in ipairs(game.bus.log) do
    if e.seq > (before.eventSeq or game.bus.seq) and
      (e.event == ns.EVENT.DAMAGE_DEALT or e.event == ns.EVENT.HEALED) then
      outcomes[#outcomes+1] = {targetId=e.targetId, cardId=e.targetCardId,
        amount=e.amount, health=e.healthAfter, armor=e.armorAfter,
        heal=e.event == ns.EVENT.HEALED}
    end
  end
  return outcomes
end

-- ================================================================== the rope

--[[ Start the clock for a new turn. Called when the turn number changes, from
     either side, so it also covers a turn that ended because the opponent
     played rather than because we did. ]]
function Director:ResetTurn(game)
  self.turn = game and game.turn
  self.phase = game and game.phase
  self.elapsed = 0
  self.ropeShown = false
  --[[ Must be cleared with the rest of the clock. Leaving it set means the
       turn-expiry fires once in the whole match and every later turn runs
       forever -- which looks exactly like the timer not being wired at all. ]]
  self.expired = false
  --[[ AND THE ROPE HAS TO COME DOWN. It is driven by a running timeline, not by
       the snapshot, so nothing else ever told it the turn was over: it burned
       to the end, stayed on screen fully burnt, and sat there through the
       opponent's turn and into the next one. A deadline that is still showing
       after the deadline passed is worse than no deadline at all. ]]
  self.onReset()
end

-- Both players see the active turn's rope. Only the active player's client
-- owns expiry; the other side observes the resulting network action.
function Director:Tick(game, dt)
  local plans = {}
  if not game or game.over then return plans end
  --[[ A phase change resets the clock exactly as a turn change does. Without
       it the mulligan's elapsed time would be carried straight into turn one,
       which arrives already part-burnt. ]]
  if game.turn ~= self.turn or game.phase ~= self.phase then self:ResetTurn(game) end

  --[[ THE MULLIGAN HAS ITS OWN CLOCK, and it is deliberately NOT gated on
       whose turn it is.

       Both players mulligan at once, so `activePlayer` says nothing about it --
       the player going second was never the active player during the mulligan
       and so never had a clock running at all. And when the clock did run, it
       called onExpire with no argument, the caller sent END_TURN, and the
       controller refused it because a mulligan was outstanding. The rope burned
       all the way down and then nothing happened.

       `what` tells the caller which deadline passed, so the answer can be the
       right one: confirm the mulligan, not end a turn that has not started. ]]
  local mulliganing = game.AwaitingMulligan and game:AwaitingMulligan(self.me)
  if not mulliganing and game.AwaitingMulligan and game:AwaitingMulligan() then return plans end
  local total, what
  if mulliganing then
    total, what = ns.RULES.MULLIGAN_SECONDS, "mulligan"
  else
    total, what = game:TurnSeconds(), "turn"
  end

  self.elapsed = (self.elapsed or 0) + (dt or 0)
  local ropeAt = total - math.min(ns.RULES.ROPE_SECONDS, total)
  local remaining = total - self.elapsed

  if not self.ropeShown and self.elapsed >= ropeAt then
    self.ropeShown = true
    --[[ The rope's length is whatever is actually left, not a constant. With
         Nozdormu out the whole turn is 15 seconds, so the rope IS the turn --
         which is exactly the card's text, and the first time anything has
         consumed Game:TurnSeconds. ]]
    plans[#plans + 1] = { sequence = "Rope", opts = { seconds = math.max(0.1, remaining) } }
  end

  if remaining <= 0 and not self.expired then
    self.expired = true
    --[[ The client whose deadline it is answers it ITSELF. In a duel that is an
         ordinary action which crosses the wire like any other, so the two
         clients cannot disagree about whether the rope ran out. ]]
    if mulliganing or game.activePlayer == self.me then self.onExpire(what) end
  end
  return plans
end

function Director:TurnRemaining(game)
  if not game then return nil end
  if game.AwaitingMulligan and game:AwaitingMulligan(self.me) then
    return math.max(0, ns.RULES.MULLIGAN_SECONDS - (self.elapsed or 0))
  end
  return math.max(0, game:TurnSeconds() - (self.elapsed or 0))
end

--[[ Hand a plan list to the choreography library and the stage. Kept here so
     the caller is one line and the name-to-function mapping exists once --
     a plan naming a sequence that does not exist is then a single nil check
     rather than a crash in an OnUpdate. ]]
function Director.Run(plans, stage, run)
  for _, plan in ipairs(plans or {}) do
    local sequence = ns.Choreography[plan.sequence]
    if sequence then
      local tl = sequence(stage, plan.opts or {})
      if tl and run then run(tl) end
    end
  end
end

return Director
