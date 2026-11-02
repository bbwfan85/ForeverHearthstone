--[[ Engine/Bus.lua

  EVENT BUS, TRIGGER QUEUE, AND HEARTHSTONE SEQUENCING.

  This file is where fidelity is won or lost. Hearthstone's observable ordering
  rules, which we reproduce:

  1. PLAY ORDER, NOT BOARD ORDER.
     When an event fires, every entity with a matching trigger is collected in
     the order those entities entered play (oldest first), across BOTH players,
     and the collected triggers run FIFO. Board position is irrelevant. Two
     Knife Jugglers throw in the order they were played, not left-to-right.

  2. TRIGGERS DO NOT INTERLEAVE.
     A trigger firing during trigger resolution appends to the queue; it does
     not preempt. This is why Knife Juggler + Unleash the Hounds resolves as
     "all dogs summoned, then all knives" in some cases and alternating in
     others -- the difference is whether the summons are one block or N blocks.
     We model that explicitly with Block().

  3. DEATHS ARE SIMULTANEOUS, PER BLOCK.
     Nothing dies mid-effect. At the end of each block, every entity at <=0
     health is moved to the graveyard together, and their deathrattles queue in
     play order. Then the queue drains, which may cause more deaths, so the
     death phase repeats until stable. This is what makes Abomination chains
     and mutual-destruction trades behave correctly.

  4. SECRETS.
     * fire only in response to the OPPONENT's action
     * fire oldest-first when several match the same event
     * are removed from the secret zone BEFORE their effect runs, so a secret
       cannot re-trigger itself
     * do not fire while their owner is the active player

  5. AURAS ARE NOT EVENTS.
     Auras are recomputed, never "applied". See RecalcAuras. Any board mutation
     marks auras dirty; the recompute happens before the next read. Treating an
     aura as an event that grants a buff is the classic way to end up with a
     permanently +1/+1 minion after its buffer died.
]]
local ADDON, ns = ...
local Ops = ns.Ops

local Bus = {}
ns.Bus = Bus

-- ---------------------------------------------------------------- creation

function Bus.New(game)
  local b = {
    game       = game,
    queue      = {},   -- pending trigger invocations
    blockDepth = 0,
    seq        = 0,    -- monotonic; used for desync detection hashing
    log        = {},   -- ordered event log, hashed for desync checks
    --[[ Triggered abilities as they RESOLVE (Knife Juggler throwing, Ragnaros
         firing), for presentation only: the client pulses the minion and plays
         its trigger recording. Deliberately NOT in `log` -- that is hashed for
         desync detection -- and read by nothing in the engine. ]]
    fired      = {},
  }
  return setmetatable(b, { __index = Bus })
end

-- Entities are stamped with an increasing playOrder as they enter play; this is
-- the canonical tiebreak for trigger ordering.
function Bus:StampPlayOrder(entity)
  self.game.playOrderCounter = (self.game.playOrderCounter or 0) + 1
  entity.playOrder = self.game.playOrderCounter
end

-- ------------------------------------------------------------ trigger scan

-- Collect every trigger matching `event`, in play order across both players.
function Bus:Collect(event, payload)
  local found = {}
  for pi = 1, 2 do
    local p = self.game.players[pi]
    local zones = { p.board, { p.hero }, p.weapon and { p.weapon } or {} }
    for _, zone in ipairs(zones) do
      --[[ No `silenced` test: Silence empties `triggers`, so whatever is on
           the list was given AFTER it (Blessing of Wisdom on a silenced
           minion) and must fire. ]]
      for _, e in ipairs(zone) do
        if e then
          for _, t in ipairs(e.triggers or {}) do
            if t.on == event then
              found[#found + 1] = { entity = e, trig = t, order = e.playOrder or 0 }
            end
          end
        end
      end
    end

    --[[ Cards that trigger from HAND. Bolvar Fordragon grows while he is held,
         and nothing else in the pool does.

         OPT-IN, via `inHand` on the trigger, rather than scanning hands for
         every event -- two ten-card hands walked on every raise is real work
         for one card, and the trigger has to be attached to a hand card anyway,
         which AttachScript does not do. So the entity is found by reading the
         script here instead. ]]
    for _, e in ipairs(p.hand) do
      if not e.silenced then
        local script = self.game:ScriptFor(e.cardId)
        for _, t in ipairs((script and script.triggers) or {}) do
          if t.on == event and t.inHand then
            found[#found + 1] = { entity = e, trig = t, order = e.playOrder or 0 }
          end
        end
      end
    end
  end
  table.sort(found, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.entity.instanceId < b.entity.instanceId
  end)
  return found
end

--[[ Secrets matching `event`, oldest first.

     Normally a secret only answers the OPPONENT's action, which is why the
     default scan is the non-active player's zone.

     A secret may declare `anyTurn` to fire regardless of whose turn it is. No
     card in the pinned pool does: in Hearthstone NO secret triggers on its
     owner's turn -- Ice Block does not save you from your own Hellfire, and
     Redemption does not catch a minion that dies attacking (docs/29). ]]
function Bus:CollectSecrets(event, payload)
  local out = {}
  local active = self.game.activePlayer
  for pi = 1, 2 do
    for _, s in ipairs(self.game.players[pi].secrets) do
      local spec = s.script and s.script.secret
      if spec and spec.on == event then
        if pi ~= active or spec.anyTurn then out[#out + 1] = s end
      end
    end
  end
  -- Now that both zones can contribute, scanning p1-then-p2 is not "oldest
  -- first" any more. Sort by play order so two clients reveal in the same order.
  table.sort(out, function(a, b)
    local ao, bo = a.playOrder or 0, b.playOrder or 0
    if ao ~= bo then return ao < bo end
    return a.instanceId < b.instanceId
  end)
  return out
end

-- ------------------------------------------------------------------ raise

--- Raise an event. Returns the (possibly mutated) payload.
-- PRE_* events may set payload.cancelled = true; callers must honour it.
function Bus:Raise(event, payload)
  payload = payload or {}
  self.seq = self.seq + 1
  self.log[#self.log + 1] = { seq = self.seq, event = event,
                              src = payload.source and payload.source.cardId,
                              targetId = payload.target and payload.target.instanceId,
                              targetCardId = payload.target and payload.target.cardId,
                              healthAfter = (event == ns.EVENT.DAMAGE_DEALT or event == ns.EVENT.HEALED)
                                and payload.target and payload.target:Health() or nil,
                              armorAfter = (event == ns.EVENT.DAMAGE_DEALT or event == ns.EVENT.HEALED)
                                and payload.target and (payload.target.armor or 0) or nil,
                              amount = payload.amount,
                              -- Presentation only; direct combat already has an impact animation.
                              isCombat = payload.isCombat,
                              player = payload.player,
                              entityId = payload.entity and payload.entity.instanceId,
                              burned = payload.burned,
                              -- what was burned, for the client to show (a
                              -- revealed card: Hearthstone shows both players)
                              cardId = (payload.burned or event == ns.EVENT.CARD_BURNED)
                                and (payload.cardId or (payload.entity and payload.entity.cardId)) or nil }

  --[[ SECRETS RESOLVE INLINE, not on the queue.

       This matters and I got it wrong first time round. A secret is part of the
       triggering action, not a reaction queued behind it:

         * Explosive Trap must be able to KILL the attacker before the attack
           connects. If its damage waits for the drain, a 1-health attacker
           still gets to swing.
         * Ice Block's Immune must apply before any further damage in the SAME
           action. Arcane Missiles can hit the hero three times; cancelling the
           fatal missile is not enough if missile three then lands.

       So: reveal, set cancellation, run the ops immediately, and settle deaths --
       all before Raise returns to its caller. blockDepth stays raised throughout
       so nested events queue normally rather than recursing. ]]
  --[[ Once a secret has stopped the action -- Counterspell countered the
       spell, Freezing Trap bounced the attacker, Explosive Trap killed it --
       there is nothing left for the next secret to answer. Spellbender must not
       summon for a countered spell, and a Freezing Trap must not be spent on a
       corpse. ]]
  local function stopped()
    if payload.cancelled then return true end
    local a = payload.attacker
    if a and (a.zone ~= ns.ZONE.PLAY or a:IsDead()) then return true end
    return false
  end
  --[[ A death is not an action to interrupt: nothing can be stopped, so an
       on-death Secret (Redemption, Avenge, Duplicate) is queued by
       Game:ProcessDeaths beside the deathrattles, in play order, rather than
       jumping ahead of them here. ]]
  local secrets = payload.deferSecrets and {} or self:CollectSecrets(event, payload)
  for _, s in ipairs(secrets) do
    if stopped() then break end
    local spec = s.script.secret
    -- a secret is a spell: Explosive Trap and Snipe get Spell Damage
    local ctx  = { source = s, controller = s.controller,
                   target = payload.target, payload = payload, isSpell = true }
    if (not spec.cond) or ns.Conditions.Eval(self.game, spec.cond, ctx) then
      self.game:RevealSecret(s)              -- removes from zone BEFORE running
      if spec.cancels then payload.cancelled = true end
      self.blockDepth = self.blockDepth + 1
      Ops.Run(self.game, spec.ops, ctx)
      self.game:RecalcAuras()
      self.game:ProcessDeaths()
      self.blockDepth = self.blockDepth - 1
      if spec.exclusive then break end       -- only one such secret per event
    end
  end

  for _, f in ipairs(self:Collect(event, payload)) do
    --[[ A trigger granted "for the caster" (Blessing of Wisdom) acts for the
         player who granted it, not for whoever controls the minion now. ]]
    local ctx = { source = f.entity, controller = f.trig.owner or f.entity.controller,
                  target = payload.target, payload = payload }
    if (not f.trig.cond) or ns.Conditions.Eval(self.game, f.trig.cond, ctx) then
      self.queue[#self.queue + 1] = { ops = f.trig.ops, ctx = ctx, payload = payload, trigger = true,
                                      event = event }
    end
  end

  -- If we are inside a block, let the block drain us. Otherwise drain now.
  if self.blockDepth == 0 then self:Drain() end
  return payload
end

--[[ Resolve, now and in order, the queued triggers raised by `events` -- and
     only those. Hearthstone's "whenever" triggers belong to the phase they
     were raised in: Violet Teacher's Apprentice is on the board before Savage
     Roar resolves, Truesilver heals before the swing lands. Everything else
     queued (Knife Juggler's "after you summon", deathrattles) keeps waiting for
     the end of the block. ]]
function Bus:ResolveQueued(events)
  local now, later = {}, {}
  for _, item in ipairs(self.queue) do
    if item.trigger and item.event and events[item.event] then now[#now + 1] = item
    else later[#later + 1] = item end
  end
  if #now == 0 then return end
  self.queue = later
  for _, item in ipairs(now) do
    local src = item.ctx and item.ctx.source
    if src then
      self.fired[#self.fired + 1] = { instanceId = src.instanceId, cardId = src.cardId,
                                      controller = src.controller }
    end
    self.blockDepth = self.blockDepth + 1
    Ops.Run(self.game, item.ops, item.ctx)
    self.blockDepth = self.blockDepth - 1
  end
  self.game:RecalcAuras()
end

-- ------------------------------------------------------------------ blocks

--[[ A "block" is one indivisible game action: playing a card, an attack, a
     hero power, a single trigger's effect. Deaths and queued triggers resolve
     at the end of a block, not in the middle of it.

     Use Block() around anything that should be atomic:
       bus:Block(function() ... end)
]]
function Bus:Block(fn)
  self.blockDepth = self.blockDepth + 1
  local ok, err = pcall(fn)
  self.blockDepth = self.blockDepth - 1
  if not ok then self.game:Error("block error: " .. tostring(err)) end
  if self.blockDepth == 0 then self:Drain() end
end

--- Drain the trigger queue, running death phases until the board is stable.
function Bus:Drain()
  if self.draining then return end
  self.draining = true
  local ok, err = pcall(self.DrainInner, self)
  self.draining = false
  if not ok then error(err, 0) end
end

function Bus:DrainInner()
  local guard = 0
  repeat
    guard = guard + 1
    if guard > 200 then
      self.game:Error("trigger queue did not converge -- aborting drain")
      self.queue = {}
      return
    end

    -- run everything currently queued (new entries append and run next pass)
    local batch = self.queue
    self.queue = {}
    for _, item in ipairs(batch) do
      local src = item.trigger and item.ctx and item.ctx.source
      if src then
        self.fired[#self.fired + 1] = { instanceId = src.instanceId, cardId = src.cardId,
                                        controller = src.controller }
      end
      if item.secret then
        self:RunDeferredSecret(item)
      else
        self.blockDepth = self.blockDepth + 1
        Ops.Run(self.game, item.ops, item.ctx)
        self.blockDepth = self.blockDepth - 1
      end
    end

    self.game:RecalcAuras()
    local died = self.game:ProcessDeaths()   -- queues deathrattles
  until #self.queue == 0 and not died
end

--[[ An on-death Secret queued by Game:ProcessDeaths. It is checked when its
     turn comes, not when it was queued: a Secret already spent on an earlier
     death in the same phase (Duplicate copies only the first) is gone. ]]
function Bus:RunDeferredSecret(item)
  local s = item.secret
  if s.zone ~= ns.ZONE.SECRET then return end
  local spec = s.script and s.script.secret
  if not spec then return end
  local ctx = { source = s, controller = s.controller, target = item.payload.target,
                payload = item.payload, isSpell = true }
  if spec.cond and not ns.Conditions.Eval(self.game, spec.cond, ctx) then return end
  self.game:RevealSecret(s)
  self.blockDepth = self.blockDepth + 1
  Ops.Run(self.game, spec.ops, ctx)
  self.blockDepth = self.blockDepth - 1
end

-- ------------------------------------------------- desync detection support

-- A cheap order-sensitive hash of the event log. Both clients compute this at
-- each turn boundary and exchange it; a mismatch means desync. See Net design.
function Bus:StateHash()
  local h = 5381
  for _, r in ipairs(self.log) do
    local s = r.event .. "|" .. tostring(r.src)
    for i = 1, #s do
      h = (h * 33 + s:byte(i)) % 2147483647
    end
  end
  return h
end

return Bus
