--[[ Engine/Conditions.lua

  Declarative predicates. Used by Conditional ops, trigger gating, secret
  gating, Combo, Enrage and play requirements.

  A condition is a table with a `c` field:
    { c="Combo" }
    { c="HasMinions", sel={side="FRIENDLY",type="MINION"}, min=1 }
    { c="Not", of={ c="Combo" } }
    { c="All", of={ {c="Combo"}, {c="HasWeapon"} } }
]]
local ADDON, ns = ...
local Selector = ns.Selector

local Conditions = {}
ns.Conditions = Conditions

local C = {}
Conditions.predicates = C

function Conditions.Eval(game, cond, ctx)
  if cond == nil then return true end
  local f = C[cond.c]
  if not f then
    game:Error(("unknown condition %q"):format(tostring(cond.c)))
    return false
  end
  return f(game, ctx, cond) and true or false
end

-- ------------------------------------------------------------- combinators

C.Not = function(game, ctx, cond)
  return not Conditions.Eval(game, cond.of, ctx)
end

C.All = function(game, ctx, cond)
  for _, sub in ipairs(cond.of) do
    if not Conditions.Eval(game, sub, ctx) then return false end
  end
  return true
end

C.Any = function(game, ctx, cond)
  for _, sub in ipairs(cond.of) do
    if Conditions.Eval(game, sub, ctx) then return true end
  end
  return false
end

-- ------------------------------------------------------------- game state

-- Combo: true if the controller has already played a card this turn.
C.Combo = function(game, ctx)
  return game.players[ctx.controller].cardsPlayedThisTurn > 0
end

C.HasWeapon = function(game, ctx, cond)
  local who = ctx.controller
  if cond and cond.side == "ENEMY" then who = game:Opponent(who) end
  return game.players[who].weapon ~= nil
end

C.CountAtLeast = function(game, ctx, cond)
  return #Selector.Resolve(game, cond.sel, ctx) >= (cond.min or 1)
end

C.CountAtMost = function(game, ctx, cond)
  return #Selector.Resolve(game, cond.sel, ctx) <= (cond.max or 0)
end

C.BoardFull = function(game, ctx, cond)
  local who = cond.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  return #game.players[who].board >= ns.RULES.BOARD_SLOTS
end

C.ManaFull = function(game, ctx)
  return game.players[ctx.controller].maxMana >= ns.RULES.MANA_CAP
end

C.SelfDamaged = function(game, ctx)
  return ctx.source and ctx.source:IsDamaged() or false
end

C.TargetHasRace = function(game, ctx, cond)
  return ctx.target and ctx.target.printed.race == cond.race or false
end

-- The target is on the caster's side (Demonfire / Demonheart: only YOUR Demon
-- is empowered; an enemy Demon takes the damage like anything else).
C.TargetIsFriendly = function(game, ctx)
  return ctx.target ~= nil and ctx.target.controller == ctx.controller
end

C.HandNotEmpty = function(game, ctx, cond)
  local who = cond.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  return #game.players[who].hand > 0
end

C.HasOverload = function(game, ctx)
  return game.players[ctx.controller].lockedMana > 0
end

-- Payload-driven: used by secrets, e.g. "when a minion with 3 or less attack
-- attacks". Reads the event payload rather than board state.
--[[ Attack threshold on whichever entity the event is ABOUT.

     Attack events carry `attacker`; summon/play events carry `entity`. Reading
     only `attacker` meant this silently evaluated false on MINION_SUMMONED, so
     Warsong Commander granted Charge to every friendly minion of 3 or less attack
     instead of just the new one. Falling back to `entity` fixes that exactly. ]]
C.PayloadAttackAtMost = function(game, ctx, cond)
  local pl = ctx.payload
  local a = pl and (pl.attacker or pl.entity or pl.card)
  return a and a.Attack and a:Attack() <= cond.max or false
end

C.PayloadAttackAtLeast = function(game, ctx, cond)
  local pl = ctx.payload
  local a = pl and (pl.attacker or pl.entity or pl.card)
  return a and a.Attack and a:Attack() >= (cond.min or 0) or false
end

-- Target-shape predicates. `sel.target` bypasses every selector filter by design
-- (it returns the chosen entity directly), so Count(target +frozen, 1) can never
-- work. These read the target explicitly instead.
C.TargetIsDamaged = function(game, ctx)
  return ctx.target and ctx.target:IsDamaged() or false
end

C.TargetAlive = function(game, ctx)
  local t = ctx.target
  return t ~= nil and t.zone == ns.ZONE.PLAY and not t:IsDead()
end

C.TargetHasKeyword = function(game, ctx, cond)
  return ctx.target and ctx.target:Has(cond.keyword) or false
end

C.TargetIsFrozen = function(game, ctx)
  return ctx.target and ctx.target.frozen == true or false
end

C.PayloadIsMinion = function(game, ctx)
  local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
  return e and e.printed.type == ns.CARDTYPE.MINION or false
end

C.PayloadIsSpell = function(game, ctx)
  local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
  return e and e.printed.type == ns.CARDTYPE.SPELL or false
end

C.PayloadTargetIsHero = function(game, ctx)
  local t = ctx.payload and (ctx.payload.defender or ctx.payload.target)
  return t and t.printed.type == ns.CARDTYPE.HERO or false
end

--[[ Did the event's subject belong to the trigger's controller?
     "After YOU summon a minion" (Knife Juggler) vs "after a minion is summoned".
     PayloadIsMine is the general form; PayloadSummonedByMe is kept as a
     summon-flavoured alias because it reads better on summon triggers. ]]
C.PayloadIsMine = function(game, ctx)
  local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
  if e and e.controller then return e.controller == ctx.controller end
  -- some payloads carry only a player index (SPELL_CAST, TURN_BEGIN)
  return ctx.payload and ctx.payload.player == ctx.controller or false
end
C.PayloadSummonedByMe = C.PayloadIsMine

-- Guard against a trigger firing on its own arrival.
C.PayloadIsSelf = function(game, ctx)
  local e = ctx.payload and ctx.payload.entity
  return e and ctx.source and e.instanceId == ctx.source.instanceId or false
end

-- Attack-event predicates. PRE_ATTACK/ATTACK_* payloads carry attacker and
-- defender, NOT entity, so PayloadIsMinion does not apply to them.
C.PayloadAttackerIsMinion = function(game, ctx)
  local a = ctx.payload and ctx.payload.attacker
  return a and a.printed.type == ns.CARDTYPE.MINION or false
end

C.PayloadAttackerIsEnemy = function(game, ctx)
  local a = ctx.payload and ctx.payload.attacker
  return a and a.controller ~= ctx.controller or false
end

-- Race filter on the event's subject: "whenever you summon a Beast".
C.PayloadHasRace = function(game, ctx, cond)
  local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
  return e and e.printed.race == cond.race or false
end

--[[ Ice Block: "when your hero takes fatal damage".
     Reads the PRE_DAMAGE payload, so it sees the amount BEFORE it is applied and
     can cancel it. Armor absorbs first, so "fatal" means the damage still
     reaching health is at least the hero's current health. ]]
C.PayloadFatalToMyHero = function(game, ctx)
  local pl = ctx.payload
  local t = pl and pl.target
  if not t then return false end
  if t.printed.type ~= ns.CARDTYPE.HERO then return false end
  if t.controller ~= ctx.controller then return false end
  local reaching = (pl.amount or 0) - (t.armor or 0)
  return reaching >= t:Health()
end

-- Was the event caused BY this entity? Water Elemental freezes only characters
-- IT damaged, not everything that takes damage.
C.PayloadSourceIsSelf = function(game, ctx)
  local s = ctx.payload and ctx.payload.source
  return s and ctx.source and s.instanceId == ctx.source.instanceId or false
end

--[[ The outcome of the damage the PREVIOUS op dealt. Mortal Coil draws only if
     its 1 damage killed; Slam draws only if its 2 damage did not.

     Both read `ctx.damageKilled`, which H.Damage sets from the target's health
     rather than from the damage number -- so a Divine Shield that absorbs the
     hit counts as a survival, which is the interaction players actually notice.
     Unset (no damage op ran) is false for both, so a malformed script draws
     nothing rather than drawing always. ]]
C.DamageKilled = function(game, ctx)
  return ctx.damageKilled == true
end

C.DamageSurvived = function(game, ctx)
  return ctx.damageKilled == false
end

--[[ Mortal Strike: "If you have 12 or less Health, deal $6 instead." Reads the
     CASTER's hero, not the target. ]]
C.MyHeroHealthAtMost = function(game, ctx, cond)
  local hero = game.players[ctx.controller].hero
  return hero and hero:Health() <= (cond.n or 0) or false
end

--[[ "At the end of YOUR turn" / "on your turn". TURN_END and TURN_BEGIN fire
     for both players, so a trigger that should only act on its owner's turn has
     to say so. Without this, Fel Cannon shot on the opponent's turn too.

     Also unblocks Floating Watcher, which docs/08 lists as deliberately PARTIAL
     for exactly this missing condition. ]]
C.MyTurn = function(game, ctx)
  return game.activePlayer == ctx.controller
end

--[[ Predicates about the card or entity an event is ABOUT, for cards that
     react to a property rather than to an identity. Each one has a
     board-side twin already (Selector's hasDeathrattle, Game:IsSecret); these
     ask the same question of the payload. ]]
C.PayloadHasDeathrattle = function(game, ctx)
  local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
  if not e then return false end
  if e.deathrattles and #e.deathrattles > 0 then return true end
  for _, t in ipairs(e.printed.scriptTags or {}) do
    if t == "DEATHRATTLE" then return true end
  end
  return false
end

C.PayloadIsSecret = function(game, ctx)
  local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
  return e and game:IsSecret(e.printed) or false
end

--[[ Unbound Elemental: "whenever you play a card with Overload". Overload is a
     PRINTED field on the card being played. Note this is NOT the existing
     HasOverload, which reads the player's currently locked mana -- that is last
     turn's lock, a different question entirely. ]]
C.PayloadHasOverload = function(game, ctx)
  local e = ctx.payload and (ctx.payload.card or ctx.payload.entity)
  return e and (e.printed.overload or 0) > 0 or false
end

-- Foe Reaper 4000: was THIS minion the attacker?
C.PayloadAttackerIsSelf = function(game, ctx)
  local a = ctx.payload and ctx.payload.attacker
  return a and ctx.source and a.instanceId == ctx.source.instanceId or false
end

--[[ Nat Pagle's 50%. Drawn from Game:Random -- the seeded, shared stream -- so
     both clients agree on the coin flip. Using math.random here would desync
     lockstep, and a test poisons math.random specifically to catch that. ]]
C.Chance = function(game, ctx, cond)
  return game:Random(100) <= (cond.pct or 50)
end

-- Gazlowe: "whenever you cast a 1-mana spell". Reads the card's cost as cast.
C.PayloadCostAtMost = function(game, ctx, cond)
  local e = ctx.payload and (ctx.payload.card or ctx.payload.entity)
  return e and e.Cost and e:Cost() <= (cond.max or 0) or false
end

--[[ Eye for an Eye: "when YOUR hero takes damage". PayloadTargetIsHero tests
     the shape but not the ownership, and a secret does fire on the opponent's
     turn -- including when they damage their own hero, which must not arm it. ]]
C.PayloadTargetIsMyHero = function(game, ctx)
  local t = ctx.payload and (ctx.payload.target or ctx.payload.defender)
  if not t then return false end
  return t.printed.type == ns.CARDTYPE.HERO and t.controller == ctx.controller
end

--[[ Gallywix: "whenever your opponent casts a spell, gain a copy of it and
     give them a Coin". Without an identity test the Coin it hands over is
     itself a spell, so the opponent playing it re-triggers Gallywix into an
     unbounded coin engine. A cost test is not a substitute -- it would also
     exclude Innervate, Backstab and Preparation. ]]
C.PayloadCardIs = function(game, ctx, cond)
  local e = ctx.payload and (ctx.payload.card or ctx.payload.entity)
  return e and e.cardId == cond.cardId or false
end

--[[ Shadowform is a three-state card: Lesser Heal -> Mind Spike -> Mind
     Shatter, and a third cast does nothing. It needs to read which hero power
     it currently has. ]]
C.HeroPowerIs = function(game, ctx, cond)
  local hp = game.players[ctx.controller].heroPower
  return hp and hp.cardId == cond.cardId or false
end

--[[ Gnomish Experimenter: "Draw a card. If it's a minion, transform it into a
     Chicken." A battlecry has no payload, so PayloadIsMinion is always false
     there -- using it would compile cleanly and the Chicken would never appear.
     This reads the card the previous op actually drew. ]]
C.LastDrawnIsMinion = function(game, ctx)
  local e = ctx.lastDrawn
  return e and e.printed.type == ns.CARDTYPE.MINION or false
end

-- Call Pet: "If it's a Beast, it costs (4) less."
C.LastDrawnIsBeast = function(game, ctx)
  local e = ctx.lastDrawn
  return e and e.printed.race == "BEAST" or false
end

-- Pint-Sized Summoner: only the FIRST minion you play each turn is cheaper.
C.NoMinionPlayedThisTurn = function(game, ctx)
  return (game.players[ctx.controller].minionsPlayedThisTurn or 0) == 0
end

-- Feugen and Stalagg: a minion that actually DIED this game on your side.
C.DiedThisGame = function(game, ctx, cond)
  local d = game.diedThisGame
  return d and d[ctx.controller] and d[ctx.controller][cond.cardId] or false
end

--[[ Spellbender: "When an enemy casts a spell ON A MINION." Without the target
     test the secret fires on every enemy spell, including ones that take no
     target at all, and is wasted. ]]
C.PayloadSpellHasMinionTarget = function(game, ctx)
  local t = ctx.payload and ctx.payload.target
  return t and t.printed.type == ns.CARDTYPE.MINION or false
end

return Conditions
