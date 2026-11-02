--[[ Engine/Ops.lua

  THE PRIMITIVE VERB LIBRARY.

  Every card effect in the 379-card pool is expressed as a list of these ops.
  An op is a plain data table with an `op` field; the rest are arguments.
  Selectors (see Selector.lua) say WHICH entities; ops say WHAT HAPPENS.

    { op="Damage", sel={side="ENEMY",type="MINION"}, amount=1 }

  Adding a card should almost never mean adding an op. If you find yourself
  writing a new op for a single card, first check whether a Conditional plus
  two existing ops expresses it. The whole point of this file is that it stops
  growing around card 80 while the card count keeps climbing.

  Ops that deal damage route through Game:DealDamage so that spell power,
  Divine Shield, armor, PRE_DAMAGE mutation and death queueing all happen in
  one place. Never subtract health directly.
]]
local ADDON, ns = ...
local Selector = ns.Selector

local Ops = {}
ns.Ops = Ops

local H = {}      -- op handlers
Ops.handlers = H

--- Execute a list of ops.
function Ops.Run(game, ops, ctx)
  if not ops then return end
  for _, op in ipairs(ops) do
    local h = H[op.op]
    if not h then
      game:Error(("unknown op %q on card %s"):format(
        tostring(op.op), ctx.source and ctx.source.cardId or "?"))
    else
      h(game, ctx, op)
    end
  end
end

local function sel(game, op, ctx) return Selector.Resolve(game, op.sel, ctx) end

-- Amount can be a literal or a dynamic spec.
local function amount(game, op, ctx)
  local a = op.amount
  if type(a) == "number" then return a end
  if type(a) == "table" then
    if a.count then return #Selector.Resolve(game, a.count, ctx) end
    if a.attackOf then
      local t = Selector.Resolve(game, a.attackOf, ctx)[1]
      return t and t:Attack() or 0
    end
    if a.armorOf then
      local t = Selector.Resolve(game, a.armorOf, ctx)[1]
      return t and t.armor or 0
    end
    if a.healthOf then
      local t = Selector.Resolve(game, a.healthOf, ctx)[1]
      return t and t:Health() or 0
    end
    --[[ Damage TAKEN, not health remaining. Molten Giant reads the hero's
         accumulated damage, which armor does not reduce and healing does. ]]
    if a.damageOf then
      local t = Selector.Resolve(game, a.damageOf, ctx)[1]
      return t and t.damage or 0
    end
    --[[ A rolled range: Crackle's $3-$6, Lightning Storm's $2-$3, Imp-losion's
         $2-$4. Drawn from the shared seeded stream like every other random, so
         both clients roll the same number. The roll happens ONCE per op, not
         once per selected entity -- Lightning Storm deals the same amount to
         every enemy minion, it does not re-roll per minion. ]]
    if a.min and a.max then
      return a.min + game:Random(a.max - a.min + 1) - 1
    end
    --[[ The amount the PREVIOUS op actually used. Imp-losion summons one Imp
         per damage dealt, so the summon has to see the roll the damage made. ]]
    if a.lastAmount then return ctx.lastAmount or 0 end
    --[[ The amount carried by the EVENT being handled, which `dealt` cannot
         reach: a trigger runs with a fresh ctx, so the damage it is reacting to
         was never "the previous op" from its point of view. Mistress of Pain
         and Eye for an Eye both need it. ]]
    if a.payloadAmount then
      return (ctx.payload and ctx.payload.amount) or 0
    end
    if a.costOf then
      local t = Selector.Resolve(game, a.costOf, ctx)[1]
      return t and t:Cost() or 0
    end
    --[[ Subtraction, clamped at zero. "Draw until you have as many cards as
         your opponent" and "draw until they have 3" are both a difference, and
         a negative draw must be no draw rather than a reverse one. ]]
    --[[ Edwin VanCleef: "+2/+2 for each card played EARLIER this turn". The
         counter is incremented by PlayCard BEFORE the combo body runs, so the
         card being played is already in it and must be discounted. ]]
    if a.cardsPlayedEarlierThisTurn then
      return math.max(0, game.players[ctx.controller].cardsPlayedThisTurn - 1)
    end
    if a.sub then
      local x = amount(game, { amount = a.sub[1] }, ctx)
      local y = amount(game, { amount = a.sub[2] }, ctx)
      return math.max(0, x - y)
    end
  end
  return 0
end

--[[ Exposed because auras need the same resolver: the Giants' cost reduction
     is `-count(...)`, recomputed on every rebuild rather than applied once. ]]
Ops.Amount = amount

-- ============================================================ damage / heal

--[[ `ctx.damageKilled` is set for the benefit of the next op in the list:
     Mortal Coil draws only if its 1 damage was lethal, Slam draws only if its
     2 damage was not. It is read by the DamageKilled / DamageSurvived
     conditions.

     Lethality is decided by health reaching zero, NOT by the damage number, so
     a Divine Shield that absorbs the hit correctly counts as a survival --
     which is exactly the Mortal Coil interaction players notice. Deaths are
     still processed at the end of the block as usual; this only records what
     happened. ]]
H.Damage = function(game, ctx, op)
  local n = amount(game, op, ctx)
  --[[ `dealt` must be the amount AFTER spell power, not the raw roll: with a
       Kobold Geomancer out, Imp-losion rolling 3 deals 4 and must summon 4.
       Not the amount finally APPLIED, though -- Imp-losion into a Divine Shield
       still summons its Imps. ]]
  --[[ `from`: the damage is dealt BY that minion, not by the spell (Betrayal),
       so Spell Damage does not scale it and the dealer's Poisonous applies. ]]
  local source, isSpell = ctx.source, ctx.isSpell
  if op.from then
    source = Selector.Resolve(game, op.from, ctx)[1]
    if not source then return end
    isSpell = false
  end
  ctx.lastAmount = game:ScaleSpellDamage(n, source, isSpell)
  local killed, any = false, false
  for _, e in ipairs(sel(game, op, ctx)) do
    any = true
    game:DealDamage(e, n, source, isSpell)
    if e:Health() <= 0 then killed = true end
  end
  if any then ctx.damageKilled = killed end
end

--[[ Arcane Missiles / Avenging Wrath: N separate 1-damage hits, each re-rolling
     its target. A distinct op because re-rolling between hits is observable --
     a target can die mid-volley and the next missile must pick from the
     survivors, so resolving against an up-front snapshot is wrong.

     SPELL SCALING APPLIES TO THE COUNT, NOT THE HITS. Prophet Velen turns
     Arcane Missiles into 6 missiles of 1 damage, not 3 missiles of 2. So we
     scale n here and then pass isSpell=false per hit, or the multiplier would
     be applied twice. Arcane Missiles is ImmuneToSpellpower, so Spell Damage +N
     correctly does not add missiles. ]]
H.DamageRandomSplit = function(game, ctx, op)
  local n = amount(game, op, ctx)
  local per = op.per or 1
  if ctx.isSpell and ctx.source then
    local owner = ctx.source.controller
    --[[ Spell Damage adds MISSILES. ImmuneToSpellpower (Arcane Missiles,
         Avenging Wrath) is Hearthstone's way of stopping each 1-damage hit
         from being boosted as well -- which the per-hit isSpell=false below
         already does. It never stopped the count: +1 Spell Damage makes
         Arcane Missiles four missiles. A hero power (Rain of Fire) adds none. ]]
    if not game.IsHeroPower(ctx.source) then
      n = n + game:SpellPower(owner)
    end
    n = n * game:SpellMultiplier(owner)
  end
  --[[ Nothing dies mid-volley: deaths wait for the end of the block, as they
       do everywhere else. A character already at 0 is simply no longer a
       candidate, which is Hearthstone's "mortally wounded" rule -- and it is
       what lets Arcane Missiles or Madder Bomber kill BOTH heroes for a draw
       instead of ending the game on the first. ]]
  for _ = 1, n do
    local pool = {}
    for _, e in ipairs(Selector.Resolve(game, op.sel, ctx)) do
      if not e:IsDead() then pool[#pool + 1] = e end
    end
    if #pool == 0 then break end
    local pick = pool[game:Random(#pool)]
    game:DealDamage(pick, per, ctx.source, false)   -- already scaled above
  end
end

H.Heal = function(game, ctx, op)
  local n = amount(game, op, ctx)
  for _, e in ipairs(sel(game, op, ctx)) do game:Heal(e, n, ctx.source) end
end

H.SetHealth = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    --[[ A HERO's REMAINING Health is set (Alexstrasza): its maximum stays 30,
         so it can be healed back up. A minion's Health is set outright
         (Hunter's Mark, Repentance). ]]
    if e.printed.type == ns.CARDTYPE.HERO then
      e.damage = math.max(0, e:MaxHealth() - op.value)
    else
      e:SetStat("hp", op.value, ctx.source and ctx.source.cardId)
      e.damage = 0
    end
  end
end

H.GainArmor = function(game, ctx, op)
  local n = amount(game, op, ctx)
  for _, e in ipairs(sel(game, op, ctx)) do
    e.armor = e.armor + n
    -- Siege Engine reacts to gaining Armor; nothing raised an event for it.
    if n > 0 then
      game.bus:Raise(ns.EVENT.ARMOR_GAINED,
                     { entity = e, player = e.controller, amount = n })
    end
  end
end

--[[ Felguard: "Destroy one of your Mana Crystals". The compiler refuses
     Mana(-1) and names this card, because GainManaCrystal loops upward and a
     negative count silently does nothing. Losing a crystal also has to take the
     unspent mana with it when the crystal has not been used yet. ]]
H.LoseManaCrystal = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  local p = game.players[who]
  for _ = 1, (op.count or 1) do
    if p.maxMana <= 0 then break end
    p.maxMana = p.maxMana - 1
    if p.mana > p.maxMana then p.mana = p.maxMana end
  end
end

-- =================================================================== buffs

--[[ Buff. With `duration` set it becomes a timed enchantment that expires on
     its own; without, it is permanent. One op rather than two, because the only
     difference is how long it lasts.

     Negative values are legitimate: Shrinkmeister is Buff(-2, 0) this turn. ]]
H.Buff = function(game, ctx, op)
  --[[ atk/hp may be a literal OR a dynamic spec, so both go through the same
       resolver that `amount` uses. Bloodsail Raider gains your weapon's attack;
       Void Terror eats its neighbours' stats. Resolved ONCE before the loop, so
       every target in one op gets the same value -- otherwise a count-based buff
       would change as the loop mutated the board. ]]
  local datk = type(op.atk) == "table" and amount(game, { amount = op.atk }, ctx) or (op.atk or 0)
  local dhp  = type(op.hp)  == "table" and amount(game, { amount = op.hp  }, ctx) or (op.hp  or 0)
  for _, e in ipairs(sel(game, op, ctx)) do
    if op.duration then
      e:AddTimedEnchantment(datk, dhp, op.keywords,
                            op.duration, game.turn, ctx.controller, ctx.source and ctx.source.cardId)
    else
      e:AddEnchantment(datk, dhp, op.keywords, ctx.source and ctx.source.cardId)
    end
    if op.keywords then
      for _, k in ipairs(op.keywords) do
        if k == ns.KEYWORD.DIVINE_SHIELD then e.divineShieldUp = true end
      end
    end
  end
end

H.SetAttack = function(game, ctx, op)
  local v = type(op.value) == "table"
            and amount(game, { amount = op.value }, ctx) or op.value
  for _, e in ipairs(sel(game, op, ctx)) do
    e:SetStat("atk", v, ctx.source and ctx.source.cardId)
  end
end

--[[ Inner Fire (CS1_129): "Change a minion's Attack to be equal to its Health."

     Reads CURRENT health and pins attack there as an enchantment. Because it is
     an enchantment and not an aura, later damage or healing does NOT move the
     attack again -- which is the Hearthstone behaviour, and the reason this
     cannot be expressed as SetAttack with a static value. ]]
H.SetAttackToHealth = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    e:SetStat("atk", e:Health(), ctx.source and ctx.source.cardId)
  end
end

--[[ Reversing Switch (PART_006): "Swap a minion's Attack and Health."

     Expressed as enchantment deltas so that Silence undoes the swap, and with
     damage cleared because the new health IS the target value rather than a
     maximum to then subtract damage from.

     Edge case: swapping a 0-attack minion (Shieldbearer 0/4) gives it 0 health,
     and it dies. Entity:MaxHealth floors at 1, so that death has to be made
     explicit via pendingDestroy rather than falling out of the arithmetic.

     Unverified: whether Hearthstone swaps against CURRENT or MAXIMUM health for
     an already-damaged minion. Implemented against current health. Flagged for
     the fidelity pass. ]]
H.SwapAttackHealth = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    local a, h = e:Attack(), e:Health()
    e:SetEnchantmentStat("atk", h - e.base.atk - e.aura.atk, ctx.source and ctx.source.cardId)
    e:SetEnchantmentStat("hp", a - e.base.hp - e.aura.hp, ctx.source and ctx.source.cardId)
    e.damage   = 0
    if a <= 0 then e.pendingDestroy = true end
  end
end

-- As with Buff, an optional `duration` makes the keyword expire. Conceal and
-- Finicky Cloakfield grant Stealth until your next turn this way.
--[[ Doubling is an ENCHANTMENT of the current value, not a multiplier that
     keeps applying. Divine Spirit on a 3/4 makes it 3/8 by adding 4; a later
     -2 health effect leaves 3/6, it does not re-double. Reading the current
     value and adding it is therefore the faithful model, and it is what makes
     Divine Spirit into Divine Spirit into Inner Fire behave correctly. ]]
H.DoubleAttack = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    e:AddEnchantment(e:Attack(), 0, nil, ctx.source and ctx.source.cardId)
    e:RecalcTimed()
  end
  game:RecalcAuras()
end

H.DoubleHealth = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    e:AddEnchantment(0, e:Health(), nil, ctx.source and ctx.source.cardId)
    e:RecalcTimed()
  end
  game:RecalcAuras()
end

--[[ Vol'jin swaps CURRENT health with another minion. Damage travels with the
     swap in Hearthstone -- a damaged 6/2 that swaps into a 4/9's body is a 6/9
     at full health -- so this moves the resulting health and clears damage
     rather than moving the damage counters. ]]
H.SwapHealth = function(game, ctx, op)
  local targets = sel(game, op, ctx)
  local a = ctx.source
  local b = targets[1]
  if not a or not b or a == b then return end
  local ha, hb = a:Health(), b:Health()
  --[[ The enchantment layer moves MAX health, and damage is being cleared, so
       each side's new max must be set to the other's old CURRENT health. Going
       via Health() here instead of MaxHealth() silently leaves the damaged side
       short by exactly the damage it had taken. ]]
  a.ench.hp = a.ench.hp + (hb - a:MaxHealth())
  b.ench.hp = b.ench.hp + (ha - b:MaxHealth())
  a.damage, b.damage = 0, 0
  a:RecalcTimed(); b:RecalcTimed()
  game:RecalcAuras()
end

H.GiveKeyword = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    if op.duration then
      e:AddTimedEnchantment(0, 0, op.keywords, op.duration, game.turn, ctx.controller, ctx.source and ctx.source.cardId)
    else
      e:AddEnchantment(0, 0, op.keywords, ctx.source and ctx.source.cardId)
    end
    for _, k in ipairs(op.keywords) do
      if k == ns.KEYWORD.DIVINE_SHIELD then e.divineShieldUp = true end
    end
  end
end

--[[ Strip a keyword. Needed by Blood Knight (eat every Divine Shield) and Flare
     (remove Stealth from all enemy minions). Clears every layer a keyword can
     live in EXCEPT auras, which are recomputed from their sources and would come
     straight back -- matching Hearthstone, where silencing the source is the only
     way to remove an aura-granted keyword. ]]
H.RemoveKeyword = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    for _, k in ipairs(op.keywords) do
      e.baseKeywords[k] = nil
      e:ForgetKeywordSource(k)
      e.enchKeywords[k] = nil
      e.timedKeywords[k] = nil
      for _, t in ipairs(e.timedEnch) do
        if t.keywords then
          local kept = {}
          for _, tk in ipairs(t.keywords) do if tk ~= k then kept[#kept+1] = tk end end
          t.keywords = kept
        end
      end
      if k == ns.KEYWORD.DIVINE_SHIELD then e.divineShieldUp = false end
    end
    e:RecalcTimed()
  end
  game:RecalcAuras()
end

H.Freeze = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do e.frozen = true end
end

H.Silence = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    e:Silence()
    game.bus:Raise(ns.EVENT.SILENCED, { entity = e })
  end
end

--[[ Brawl: "Destroy all minions except one (chosen randomly)". The selector
     grammar can pick N at random but has no way to name the REST, and doing it
     as two ops would let the survivor be destroyed by the first.

     The survivor is drawn from the shared stream, so both clients keep the same
     minion. With one or zero minions nothing is destroyed, which matches the
     printed REQ_MINIMUM_TOTAL_MINIONS of 2. ]]
H.DestroyAllButOneRandom = function(game, ctx, op)
  local all = sel(game, op, ctx)
  if #all <= 1 then return end
  local keep = all[game:Random(#all)]
  for _, e in ipairs(all) do
    if e ~= keep then e.pendingDestroy = true end
  end
end

--[[ Bouncing Blade: "Deal 1 damage to a random minion. Repeat until a minion
     dies." A loop whose exit is a condition rather than a count.

     `maxIter` is not a nicety. A board where nothing can die -- every minion
     Immune, or healed between hits -- would spin forever and hang the client,
     so the loop is bounded the same way Bus:Drain is, and gives up rather than
     locking up. ]]
--[[ Bouncing Blade on a board where nothing can die (Commanding Shout, Ice
     Block's Immune) stops after 80 bounces, as Hearthstone's does. Reaching the
     cap is a legal outcome of the card, not an engine fault. ]]
H.RepeatUntil = function(game, ctx, op)
  local limit = op.maxIter or 80
  for _ = 1, limit do
    Ops.Run(game, op.ops, ctx)
    if ns.Conditions.Eval(game, op.cond, ctx) then return end
  end
end

--[[ Settle deaths NOW, in the middle of an effect: the minions a previous op
     destroyed leave the board (their deathrattles queue as usual). Mimiron's
     Head destroys three Mechs and summons V-07-TR-0N into the room they left;
     Reincarnate destroys a minion and returns it. ]]
H.SettleDeaths = function(game, ctx, op)
  game:RecalcAuras()
  game:ProcessDeaths()
end

--[[ Poison Seeds: "Destroy all minions and summon 2/2 Treants to replace
     them." The Treants come AFTER every death has settled, deathrattles
     included -- "any Deathrattles will still activate before Treants are
     summoned" (hearthstone.wiki.gg/wiki/Poison_Seeds) -- one per destroyed
     minion, on its side, at the right end. It used to grant each minion a
     Treant deathrattle, so the Treants interleaved with the real deathrattles
     and took the dead minions' slots. ]]
H.DestroyAndReplace = function(game, ctx, op)
  local per = { 0, 0 }
  for _, e in ipairs(sel(game, op, ctx)) do
    if e.zone == ns.ZONE.PLAY and not e.pendingDestroy then
      per[e.controller] = per[e.controller] + 1
    end
    e.pendingDestroy = true
  end
  game:RecalcAuras()
  game:ProcessDeaths()
  -- inside a spell the deathrattles are only QUEUED; they must resolve first
  game.bus:Drain()
  for pi = 1, 2 do
    for _ = 1, per[pi] do game:Summon(op.cardId, pi, "RIGHTMOST", ctx.source) end
  end
end

--[[ "That card costs (N) less": an enchantment on the card itself (Far
     Sight, Call Pet), so it travels with the card and discounts nothing else. ]]
H.ChangeCost = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    e:SetEnchantmentStat("cost", e.ench.cost + op.amount, ctx.source and ctx.source.cardId)
  end
  game:RecalcAuras()
end

--[[ Destroy a card that is sitting in a HAND. Game:ProcessDeaths only scans the
     board, weapons and secrets, so `Destroy` is inert there -- which left the
     Burrowing Mine sitting in the drawer's hand after it exploded. ]]
H.DestroyInHand = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    if e.zone == ns.ZONE.HAND then
      local p = game.players[e.controller]
      for i = 1, #p.hand do
        if p.hand[i] == e then
          table.remove(p.hand, i)
          e.zone = ns.ZONE.GRAVEYARD
          p.graveyard[#p.graveyard + 1] = e
          break
        end
      end
    end
  end
  game:RecalcAuras()
end

--[[ Ancient Mage: "Give adjacent minions Spell Damage +1." A granted bonus in
     its own field, read by Game:SpellPower alongside the printed one. Silence
     drops it because SpellPower skips silenced minions. ]]
H.GiveSpellDamage = function(game, ctx, op)
  local n = amount(game, op, ctx)
  for _, e in ipairs(sel(game, op, ctx)) do
    e.spellDamageBonus = (e.spellDamageBonus or 0) + n
  end
end

--[[ Faceless Manipulator: "Choose a minion and become a copy of it." Transform
     takes a literal card id; this takes a SELECTOR, so the destination is
     whatever the player picked.

     It copies the printed card, which is what Hearthstone's Faceless does --
     a Faceless copying a buffed 6/7 Yeti becomes a 4/5 Yeti... except it does
     not: Hearthstone copies the minion's CURRENT stats. So the enchantment
     layer is copied across after the transform. ]]
H.BecomeCopy = function(game, ctx, op)
  local src = sel(game, op, ctx)[1]
  local me = ctx.source
  if not src or not me or src == me then return end
  game:Transform(me, src.cardId)
  game:CopyState(src, me)
  game:RecalcAuras()
end

--[[ Kezan Mystic: "Take control of a random enemy Secret." Game:ChangeController
     early-returns on anything not in PLAY, so it could never move a secret --
     the card selected correctly and then silently did nothing.

     A secret that duplicates one the thief already has is destroyed rather than
     stolen, which is the same rule PlaySecret enforces everywhere else. ]]
H.StealSecret = function(game, ctx, op)
  local me = ctx.controller
  local picked
  if op.sel and op.sel.random then
    --[[ "If the randomly selected Secret is the same as one the controlling
         player already has active, the Mystic will attempt to pick another.
         If no available Secrets remain, the Mystic will instead destroy a
         random Secret" (hearthstone.wiki.gg/wiki/Kezan_Mystic). It used to
         roll among all of them, so half the time it destroyed a duplicate
         while a stealable Secret sat right there. ]]
    local all = {}
    for k, v in pairs(op.sel) do all[k] = v end
    all.random = nil
    local pool = sel(game, { sel = all }, ctx)
    local mine = {}
    for _, s in ipairs(game.players[me].secrets) do mine[s.cardId] = true end
    local fresh = {}
    for _, s in ipairs(pool) do if not mine[s.cardId] then fresh[#fresh + 1] = s end end
    local from = #fresh > 0 and fresh or pool
    picked = #from > 0 and { from[game:Random(#from)] } or {}
  end
  for _, sec in ipairs(picked or sel(game, op, ctx)) do
    if sec.zone == ns.ZONE.SECRET then
      local from = game.players[sec.controller]
      for i = 1, #from.secrets do
        if from.secrets[i] == sec then table.remove(from.secrets, i); break end
      end
      sec.controller = me
      sec.owner = me
      sec.zone = ns.ZONE.GRAVEYARD          -- PlaySecret re-homes it
      if not game:PlaySecret(me, sec) then
        local p = game.players[me]
        p.graveyard[#p.graveyard + 1] = sec
      end
    end
  end
end

H.SetHeroPower = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  game:SetHeroPower(who, op.cardId)
end

H.ReplaceHero = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  game:ReplaceHero(who, op.cardId, op.heroPowerId)
  --[[ Jaraxxus is a MINION card, so playing him puts a 3/15 on the board and
       THEN runs this battlecry. He becomes the hero, so the minion must leave --
       and quietly, not by dying: a death would fire deathrattles, feed
       Deathlord and Baron Rivendare, and count for every "when a minion dies"
       trigger on the board. In Hearthstone he transforms. ]]
  local me = ctx.source
  if me and me.zone == ns.ZONE.PLAY then
    game:RemoveFromBoard(me)
    me.zone = ns.ZONE.GRAVEYARD
    local p = game.players[me.controller]
    p.graveyard[#p.graveyard + 1] = me
    game:RecalcAuras()
  end
end

--[[ Redemption: "return it to life with 1 Health". The corpse is NOT reused --
     it carries the dead minion's enchantments and a stale aura layer, since a
     dead entity is no longer in Aura.allEntities and never had its layer
     cleared. A fresh printed copy is summoned instead, then DAMAGED down to 1
     Health: "Redemption only sets a minion's current Health to 1, not its
     maximum Health", and the minion "counts as damaged for the purposes of
     abilities like Enrage" (hearthstone.wiki.gg/wiki/Redemption). It used to
     set maximum Health to 1, an undamaged 2/1 Harvest Golem that no heal
     could raise. ]]
--[[ `toController`: the minion comes back on the side of whoever controlled it
     when it died (Reincarnate on an enemy minion returns it to THEM). ]]
H.Resurrect = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _, e in ipairs(sel(game, op, ctx)) do
    if e.printed.type == ns.CARDTYPE.MINION then
      local born = game:Summon(e.cardId, op.toController and e.controller or who, nil, ctx.source)
      if born and op.health then
        born.damage = math.max(0, born:MaxHealth() - op.health)
        game:RecalcAuras()
      end
      ctx.lastSummoned = born or ctx.lastSummoned
    end
  end
end

--[[ Tracking: "Look at the top three cards of your deck. Draw one and discard
     the others."

     The cards leave the DECK immediately and sit in the offer, which is what
     Hearthstone does -- while you are looking at them they are not in the deck,
     so nothing in between can draw or steal them. Game:ResolveChoice then puts
     the chosen one in hand and the rest in the graveyard. ]]
H.LookAtTop = function(game, ctx, op)
  local p = game.players[ctx.controller]
  local taken = {}
  for _ = 1, (op.count or 3) do
    local e = table.remove(p.deck)        -- top of deck is the END of the array
    if not e then break end
    e.zone = ns.ZONE.SETASIDE
    taken[#taken + 1] = e
  end
  if #taken == 0 then return end
  --[[ With a single card left there is nothing to choose between, so it goes
       straight to hand rather than raising a prompt with one option. ]]
  if #taken == 1 then
    game:OfferChoice(ctx.controller, op.kind or "LOOK_AT_TOP", taken)
    game:ResolveChoice(ctx.controller, 1)
    return
  end
  game:OfferChoice(ctx.controller, op.kind or "LOOK_AT_TOP", taken)
end

-- ================================================================ retargeting

--[[ Move an attack, or a spell, onto a different character.

     Both only work from inside a SECRET, and that is not a limitation so much
     as the definition: secrets resolve INLINE inside the raise that triggered
     them, so the payload they mutate is still the one the caller is about to
     read. An ordinary trigger is queued and would run after the damage.

     Misdirection and Noble Sacrifice move an attack; Spellbender moves a spell. ]]
H.RetargetAttack = function(game, ctx, op)
  local pl = ctx.payload
  if not pl then return end
  local to = sel(game, op, ctx)[1]
  if not to then return end
  if to.zone ~= ns.ZONE.PLAY and to.printed.type ~= ns.CARDTYPE.HERO then return end
  pl.defender = to
  pl.target   = to
end

H.RetargetSpell = function(game, ctx, op)
  local pl = ctx.payload
  if not pl then return end
  local to = sel(game, op, ctx)[1]
  if not to then return end
  pl.target = to
end

--[[ Feign Death: "Trigger all Deathrattles on your minions" -- without killing
     them. The deathrattle runs with the minion as its own source, exactly as it
     would on death, so a Loot Hoarder draws and a Harvest Golem summons. ]]
H.TriggerDeathrattles = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    -- Baron Rivendare doubles these as well: it doubles the TRIGGERING
    for _ = 1, game:DeathrattleMultiplier(e.controller) do
      for _, ops in ipairs(e.deathrattles or {}) do
        Ops.Run(game, ops, { source = e, controller = e.controller })
      end
    end
  end
end

-- ==================================================== movement between zones

--[[ Eleven cards move a card from one zone to another without playing it:
     "put a Secret from your deck into the battlefield", "put a random Demon
     from your hand into the battlefield", "discard the top 3 cards of your
     deck".

     Game:MoveToHand only handles PLAY -> HAND, because that is all a bounce
     needs. These move from ANY zone, so they start by plucking the entity out
     of whichever list currently holds it. Getting that wrong leaves the card in
     two zones at once, which is invisible until something iterates the deck and
     finds a minion that is also on the board. ]]
local function removeFrom(list, e)
  for i = 1, #list do
    if list[i] == e then table.remove(list, i); return true end
  end
  return false
end

local function pluckFrom(p, e)
  if e.zone == ns.ZONE.HAND      then return removeFrom(p.hand, e) end
  if e.zone == ns.ZONE.DECK      then return removeFrom(p.deck, e) end
  if e.zone == ns.ZONE.SECRET    then return removeFrom(p.secrets, e) end
  if e.zone == ns.ZONE.GRAVEYARD then return removeFrom(p.graveyard, e) end
  return false
end

-- A card sits in its controller's lists; the owner's are searched as a fallback.
local function pluck(game, e)
  if e.zone == ns.ZONE.PLAY then game:RemoveFromBoard(e); return true end
  if pluckFrom(game.players[e.controller], e) then return true end
  return e.owner ~= e.controller and pluckFrom(game.players[e.owner], e) or false
end

H.MoveToHand = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    local side = e.controller
    local p = game.players[side]
    if pluck(game, e) then
      game:ResetToPrinted(e)
      if #p.hand >= ns.RULES.HAND_LIMIT then
        -- a full hand BURNS the card, exactly as an over-cap draw does
        e.zone = ns.ZONE.GRAVEYARD
        p.graveyard[#p.graveyard + 1] = e
        game.bus:Raise(ns.EVENT.CARD_BURNED, { player = side, entity = e })
      else
        e.zone = ns.ZONE.HAND
        e.owner = side
        p.hand[#p.hand + 1] = e
      end
    end
  end
  game:RecalcAuras()
end

--[[ Put a card straight onto the battlefield from wherever it is. Deathlord and
     Voidcaller both do this, and it is NOT a play: no mana, no battlecry.
     Summoning triggers DO fire, because the minion is being summoned. ]]
H.MoveToBoard = function(game, ctx, op)
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _, e in ipairs(sel(game, op, ctx)) do
    local p = game.players[side]
    if #p.board < ns.RULES.BOARD_SLOTS and e.printed.type == ns.CARDTYPE.MINION
       and pluck(game, e) then
      game:ResetToPrinted(e)
      e.zone = ns.ZONE.PLAY
      e.controller = side
      e.summonedTurn = game.turn
      game:AttachScript(e)       -- ResetToPrinted leaves a card script-less
      game.bus:StampPlayOrder(e)
      p.board[#p.board + 1] = e
      game:Reindex(side)
      game:RecalcAuras()
      game.bus:Raise(ns.EVENT.MINION_SUMMONED, { entity = e, player = side })
    end
  end
end

--[[ Mad Scientist: "put a Secret from your deck into the battlefield". It goes
     into the secret zone, and PlaySecret enforces the real rule that a duplicate
     of an already-active secret is refused. ]]
H.MoveToSecret = function(game, ctx, op)
  --[[ Mad Scientist only ever picks a Secret that CAN go into play: one that
       is not already active, into a zone with room. Rolling first and then
       refusing the duplicate threw the card away (it left the deck for the
       graveyard). So the pool is filtered before the random pick, and a full
       zone moves nothing. ]]
  local picks = sel(game, op, ctx)
  if op.sel and op.sel.random then
    local plain = {}
    for k, v in pairs(op.sel) do if k ~= "random" then plain[k] = v end end
    local pool = {}
    for _, e in ipairs(Selector.Resolve(game, plain, ctx)) do
      local secrets = game.players[e.controller].secrets
      local ok = #secrets < ns.RULES.SECRET_SLOTS
      for _, s in ipairs(secrets) do if s.cardId == e.cardId then ok = false end end
      if ok then pool[#pool + 1] = e end
    end
    picks = {}
    for _ = 1, math.min(op.sel.random, #pool) do
      picks[#picks + 1] = table.remove(pool, game:Random(#pool))
    end
  end
  for _, e in ipairs(picks) do
    if game:IsSecret(e.printed) and pluck(game, e) then
      game:ResetToPrinted(e)
      e.owner = e.controller
      if not game:PlaySecret(e.controller, e) then
        e.zone = ns.ZONE.GRAVEYARD
        local p = game.players[e.controller]
        p.graveyard[#p.graveyard + 1] = e
      end
    end
  end
end

--[[ Fel Reaver: "discard the top 3 cards of your deck". The top of the deck is
     the END of the array -- Game:Draw pops from there -- so milling has to take
     from the end too, or it silently discards from the bottom and the deck the
     player then draws is not the one they lost. ]]
H.MillDeck = function(game, ctx, op)
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  local p = game.players[side]
  for _ = 1, (op.count or 1) do
    local e = table.remove(p.deck)
    if not e then break end
    e.zone = ns.ZONE.GRAVEYARD
    p.graveyard[#p.graveyard + 1] = e
  end
end

--[[ Iron Juggernaut shuffles a specific card into the OPPONENT's deck. The card
     is created fresh from printed data rather than moved, so its owner is the
     player whose deck it lands in and it draws for them. ]]
H.ShuffleCardIn = function(game, ctx, op)
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  local pr = game:Printed(op.cardId)
  if not pr then game:Error("ShuffleCardIn unknown card: " .. tostring(op.cardId)); return end
  local p = game.players[side]
  for _ = 1, (op.count or 1) do
    local e = ns.Entity.New(pr, side, game.ids)
    e.zone = ns.ZONE.DECK
    p.deck[#p.deck + 1] = e
  end
  game:Shuffle(p.deck)
end

--[[ Copy a card INTO HAND rather than onto the board. Duplicate, Echo of
     Medivh, Thoughtsteal and Gallywix all do this. The copy is made from
     PRINTED data, so a buffed minion copies as its printed self -- which is
     what Echo of Medivh does in Hearthstone. ]]
H.CopyToHand = function(game, ctx, op)
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _, e in ipairs(sel(game, op, ctx)) do
    for _ = 1, (op.count or 1) do
      game:AddToHand(side, e.cardId)
    end
  end
end

--[[ Alarm-o-Bot: "swap this minion with a random one in your hand". Two moves
     that must both succeed or neither does -- half a swap would either
     duplicate the Bot or lose the minion. ]]
H.SwapWithHand = function(game, ctx, op)
  local me = ctx.source
  if not me or me.zone ~= ns.ZONE.PLAY then return end
  local picks = sel(game, op, ctx)
  local other = picks[1]
  if not other or other.zone ~= ns.ZONE.HAND then return end

  local p = game.players[me.controller]
  local slot = me.boardIndex
  if not pluck(game, other) then return end
  if not pluck(game, me) then
    -- put the hand card back; nothing has moved yet on the board side
    other.zone = ns.ZONE.HAND
    local oh = game.players[other.controller].hand
    oh[#oh + 1] = other
    return
  end

  game:ResetToPrinted(me)
  me.zone = ns.ZONE.HAND
  me.owner = me.controller
  local ph = game.players[me.controller]
  ph.hand[#ph.hand + 1] = me

  game:ResetToPrinted(other)
  other.zone = ns.ZONE.PLAY
  other.controller = p == game.players[1] and 1 or 2
  other.summonedTurn = game.turn
  game:AttachScript(other)   -- ResetToPrinted leaves a card script-less
  game.bus:StampPlayOrder(other)
  table.insert(p.board, math.min(slot or (#p.board + 1), #p.board + 1), other)
  game:Reindex(other.controller)
  game:RecalcAuras()
  game.bus:Raise(ns.EVENT.MINION_SUMMONED, { entity = other, player = other.controller })
end

-- ================================================ generated-from-pool cards

--[[ Cards that create a card that was never in a deck. The filter is resolved
     by Engine/CardPool.lua, which sorts before rolling so both clients generate
     the same card -- see that file's header.

     `op.poolCost = "TARGET"` makes the filter's cost follow the chosen target,
     which is Recombobulator's "a random minion with the same Cost". ]]
local function poolFilter(game, ctx, op)
  local f = {}
  for k, v in pairs(op.pool or {}) do f[k] = v end
  if op.poolCost == "TARGET" then
    local t = ctx.target
    if not t then return nil end
    f.cost = t:Cost()
  end
  return f
end

H.AddRandomCard = function(game, ctx, op)
  local f = poolFilter(game, ctx, op)
  if not f then return end
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _ = 1, (op.count or 1) do
    local id = ns.CardPool.Random(game, f)
    if id then
      local e = game:AddToHand(side, id)
      --[[ Unstable Portal's "It costs (3) less" rides along with the generated
           card as an enchantment on that copy, so it survives being shuffled
           around and does not discount anything else. ]]
      if e and op.costDelta then
        e:SetEnchantmentStat("cost", e.ench.cost + op.costDelta, ctx.source and ctx.source.cardId)
        game:RecalcAuras()
      end
    end
  end
end

H.SummonRandom = function(game, ctx, op)
  local f = poolFilter(game, ctx, op)
  if not f then return end
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _ = 1, (op.count or 1) do
    local id = ns.CardPool.Random(game, f)
    if id then game:Summon(id, side, nil, ctx.source) end
  end
end

H.TransformRandom = function(game, ctx, op)
  local f = poolFilter(game, ctx, op)
  if not f then return end
  for _, e in ipairs(sel(game, op, ctx)) do
    local id = ns.CardPool.Random(game, f)
    if id then game:Transform(e, id) end
  end
end

H.EquipRandom = function(game, ctx, op)
  local f = poolFilter(game, ctx, op) or {}
  f.type = ns.CARDTYPE.WEAPON
  local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  local id = ns.CardPool.Random(game, f)
  if id then game:EquipWeapon(side, id) end
end

--[[ Pick ONE of several op branches at random: Tinkmaster Overspark's Devilsaur
     or Squirrel, Enhance-o Mechano's Windfury or Taunt or Divine Shield. The
     roll is one draw from the shared stream, so both clients take the same
     branch. Distinct from Repeat/ForEach, which run every branch. ]]
H.OneOf = function(game, ctx, op)
  local branches = op.branches or {}
  if #branches == 0 then return end
  Ops.Run(game, branches[game:Random(#branches)], ctx)
end

-- ============================================================ board changes

H.Summon = function(game, ctx, op)
  local count = op.count or 1
  local side  = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for k = 1, count do
    local id = op.cardId
    if op.fromEntourage then
      local ent = ctx.source.printed.entourage
      --[[ `unique` draws only from entourage members NOT already on the board.
           Totemic Call never gives you a Totem you already have, which is what
           makes its REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY reachable at all -- while
           the power repeats, all four can never be out.

           NOT the default: Bane of Doom summons a random Demon from a six-card
           entourage, and repeats there are perfectly correct. ]]
      if ent and op.uniqueEntourage then
        local onBoard = {}
        for _, e in ipairs(game.players[side].board) do onBoard[e.cardId] = true end
        local avail = {}
        for _, eid in ipairs(ent) do
          if not onBoard[eid] then avail[#avail + 1] = eid end
        end
        ent = avail
      end
      id = (ent and #ent > 0) and ent[game:Random(#ent)] or nil
    end
    if id then
      --[[ Remembered so the NEXT op can name it: Noble Sacrifice summons a
           Defender and then redirects the attack onto it, and nothing else in
           the selector grammar can say "the thing I just made". ]]
      --[[ `alternate`: right of the source, then left, then right... Onyxia's
           Whelps flank her ("alternating first on the right side, then on the
           left side", hearthstone.wiki.gg/wiki/Onyxia); they used to pile up
           on her right. A left summon takes the source's own slot, which
           pushes the source one to the right. ]]
      local pos = op.position or "RIGHT_OF_SOURCE"
      local src = ctx.source
      if op.alternate and k % 2 == 0 and src and src.boardIndex
         and src.zone == ns.ZONE.PLAY and src.controller == side then
        pos = src.boardIndex
      end
      ctx.lastSummoned = game:Summon(id, side, pos, ctx.source)
              or ctx.lastSummoned
    end
  end
end

H.Destroy = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do e.pendingDestroy = true end
end

H.ReturnToHand = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    game:MoveToHand(e)
    -- set after the move: arriving in hand resets the card to its printed self
    if op.cost and e.zone == ns.ZONE.HAND then
      e.ench.cost = e.ench.cost + op.cost
      e.enchantmentSources[#e.enchantmentSources + 1] = { cost = op.cost, source = ctx.source and ctx.source.cardId }
    end
  end
end

H.TakeControl = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    local to = op.toEnemy and game:Opponent(ctx.controller) or ctx.controller
    if e.zone == ns.ZONE.PLAY and e.controller ~= to then
      if #game.players[to].board >= ns.RULES.BOARD_SLOTS then
        --[[ No room on the receiving side: Hearthstone destroys the minion
             (Shadow Madness handing back to a full board). It used to stay
             borrowed for good. ]]
        e.pendingDestroy = true
      else
        game:ChangeController(e, to)
        -- `ready`: may attack this turn, without being given Charge
        if op.ready then e.summonedTurn = -1 end
      end
    end
  end
end

H.Transform = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do game:Transform(e, op.cardId) end
end

-- op.fromPrinted = true copies the card's PRINTED stats, ignoring live buffs.
-- Mirror Entity does this: mirroring a buffed 5/6 Yeti gives a 4/5.
H.CopyToBoard = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    local side = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
    if op.fromPrinted then
      game:Summon(e.cardId, side, op.position or "RIGHTMOST", ctx.source)
    else
      game:SummonCopy(e, side, ctx.source)
    end
  end
end

-- ================================================================== cards

H.Draw = function(game, ctx, op)
  --[[ A literal `count` and a dynamic `amount` are different things. A dynamic
       amount of 0 must draw NOTHING -- Battle Rage with no damaged minions draws
       no cards -- so it must not be coerced up to 1. Only a missing count does. ]]
  local n
  if op.amount ~= nil then n = amount(game, op, ctx)
  else n = op.count or 1 end
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _ = 1, n do ctx.lastDrawn = game:Draw(who) end
end

H.AddCardToHand = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _ = 1, (op.count or 1) do
    local id = op.cardId
    if op.fromEntourage then
      local ent = ctx.source.printed.entourage
      id = ent and ent[game:Random(#ent)]
    end
    if id then game:AddToHand(who, id) end
  end
end

H.Discard = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  for _ = 1, (op.count or 1) do game:DiscardRandom(who) end
end

H.CopyOpponentHandCard = function(game, ctx, op)
  local foe  = game:Opponent(ctx.controller)
  local hand = game.players[foe].hand
  if #hand > 0 then
    game:AddToHand(ctx.controller, hand[game:Random(#hand)].cardId)
  end
end

H.ShuffleIntoDeck = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do game:ShuffleIn(e) end
end

-- =================================================================== mana

H.GainManaCrystal = function(game, ctx, op)
  -- Arcane Golem gives the crystal to the OPPONENT, so this must honour op.side.
  -- It previously hardcoded ctx.controller, which would have handed the caster a
  -- free crystal instead -- wrong, and wrong in the caster's favour.
  local who = (op.side == "ENEMY") and game:Opponent(ctx.controller) or ctx.controller
  local p = game.players[who]
  if op.temporary then
    -- never past 10 to spend: the Coin or Innervate at 10 mana gives nothing
    local room = math.max(0, ns.RULES.MANA_CAP - (p.mana + p.tempMana))
    p.tempMana = p.tempMana + math.min(op.count or 1, room)
  else
    game:GainManaCrystal(who, op.count or 1, op.empty)
  end
end

--[[ DO NOT USE for ordinary overload cards. Game:PlayCard applies
     printed.overload automatically, so scripting it as well double-counts.
     This op exists only for a hypothetical card that gains overload
     conditionally; nothing in the pinned pool needs it. The compiler rejects
     Overload() in the CSV for exactly this reason. ]]
H.Overload = function(game, ctx, op)
  local p = game.players[ctx.controller]
  p.pendingOverload = p.pendingOverload + (op.count or 1)
end

-- ================================================================ weapons

H.EquipWeapon = function(game, ctx, op)
  game:EquipWeapon(ctx.controller, op.cardId)
end

H.DestroyWeapon = function(game, ctx, op)
  local who = op.side == "ENEMY" and game:Opponent(ctx.controller) or ctx.controller
  game:DestroyWeapon(who)
end

-- ============================================================ control flow

H.Conditional = function(game, ctx, op)
  if ns.Conditions.Eval(game, op.cond, ctx) then
    Ops.Run(game, op.thenOps, ctx)
  else
    Ops.Run(game, op.elseOps, ctx)
  end
end

H.Repeat = function(game, ctx, op)
  for _ = 1, amount(game, op, ctx) do Ops.Run(game, op.ops, ctx) end
end

-- Run ops once per selected entity, with ctx.target rebound to that entity.
H.ForEach = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    local sub = setmetatable({ target = e }, { __index = ctx })
    Ops.Run(game, op.ops, sub)
  end
end

H.AddTrigger = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    -- `forCaster`: the ops run for whoever granted it (Bus:Raise reads `owner`)
    e.triggers[#e.triggers + 1] = { on = op.on, ops = op.ops, cond = op.cond,
                                    owner = op.forCaster and ctx.controller or nil }
  end
end

--[[ APPENDS rather than assigns. A minion granted a deathrattle may already have
     one (Ancestral Spirit on a Loot Hoarder), and overwriting it loses the
     original silently. Hearthstone stacks them; so do we. ]]
H.SetDeathrattle = function(game, ctx, op)
  for _, e in ipairs(sel(game, op, ctx)) do
    e.deathrattles[#e.deathrattles + 1] = op.ops
  end
end

-- ========================================== player-scoped timed modifiers

--[[ Cost modifier. Stored on the AFFECTED player so Game:CardCost reads one
     list, but tagged with the caster as `controller` because that is whose
     "next turn" an until-next-turn expiry refers to.

       op.side      "SELF" (default) or "ENEMY" -- whose cards are affected
       op.appliesTo "SPELL" | "SECRET" | "MINION" | nil (all)
       op.amount    delta, e.g. -3 (Preparation) or +5 (Loatheb)
       op.setTo     absolute override, e.g. 0 (Kirin Tor Mage, Millhouse)
       op.charges   consumed after N matching plays; nil = unlimited
       op.duration  ns.DURATION.* ]]
H.AddCostMod = function(game, ctx, op)
  local affected = (op.side == "ENEMY")
      and game:Opponent(ctx.controller) or ctx.controller
  local list = game.players[affected].costMods
  list[#list + 1] = {
    appliesTo = op.appliesTo, amount = op.amount, setTo = op.setTo,
    charges = op.charges,
    expiry = op.duration, turn = game.turn, controller = ctx.controller,
  }
end

--[[ Damage floor (Commanding Shout). Stored on the player whose minions are
     protected. Only damage is clamped; destroy effects still kill. ]]
H.AddDamageClamp = function(game, ctx, op)
  local affected = (op.side == "ENEMY")
      and game:Opponent(ctx.controller) or ctx.controller
  local list = game.players[affected].damageClamps
  list[#list + 1] = {
    minHealth = op.minHealth or 1,
    expiry = op.duration, turn = game.turn, controller = ctx.controller,
  }
end

-- ============================================================== scheduling

--[[ Defer ops to the start of the controller's next turn.

     The context is CAPTURED, including ctx.target by reference, so Nightmare
     destroys the minion it buffed rather than whatever happens to be targeted
     when the schedule fires. ]]
--[[ Fire at the END of the CURRENT turn, once. Distinct from ScheduleNextTurn,
     which fires at the start of your NEXT turn -- a full opponent turn later.
     Echoing Ooze ("summon a copy at end of turn") and Power Overwhelming ("then
     it dies" at end of turn) need this shorter fuse. ]]
H.ScheduleEndOfTurn = function(game, ctx, op)
  game:Schedule("END_OF_TURN", ctx.controller, op.ops, {
    source = ctx.source, controller = ctx.controller, target = ctx.target,
  })
end

H.ScheduleNextTurn = function(game, ctx, op)
  game:Schedule("START_OF_TURN", ctx.controller, op.ops, {
    source = ctx.source, controller = ctx.controller, target = ctx.target,
  })
end

--[[ Kel'Thuzad: "At the end of each turn, summon all friendly minions that died
     this turn." Reads game.deathLog, which is appended in death order by
     ProcessDeaths and cleared at the start of every turn -- so the iteration
     order is deterministic and identical on both clients. ]]
H.ResummonDiedThisTurn = function(game, ctx, op)
  local side = ctx.controller
  for _, rec in ipairs(game.deathLog) do
    if rec.controller == side and rec.turn == game.turn then
      game:Summon(rec.cardId, side, "RIGHTMOST", ctx.source)
    end
  end
end

return Ops
