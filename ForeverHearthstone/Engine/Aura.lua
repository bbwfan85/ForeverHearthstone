--[[ Engine/Aura.lua

  CONTINUOUS AURA RECALCULATION.

  An aura is declared on a card, never "applied" by an effect:

    aura = { sel = {adjacent="SELF", type="MINION"}, atk = 1 }        -- Dire Wolf Alpha
    aura = { sel = {side="FRIENDLY", type="MINION", race="BEAST",
                    exclude="SELF"}, atk = 1 }                        -- Timber Wolf
    aura = { sel = {side="FRIENDLY", zone="HAND", type="SPELL"}, cost = -1 }
                                                                      -- Sorcerer's Apprentice

  RecalcAuras zeroes every entity's aura layer and rebuilds it from every live
  aura source. It runs after any board mutation. Because it always rebuilds from
  zero, there is no such thing as a stale or orphaned aura buff -- the entire
  class of "minion kept its +1/+1 after the buffer died" bugs cannot occur.

  Ordering: sources are applied in play order so that aura-on-aura stacking is
  deterministic across both clients.

  Enrage is modelled here too, because it is functionally a self-aura gated on
  a condition (damaged) rather than a one-shot trigger. Healing an enraged
  minion must remove the bonus, which the rebuild-from-zero model gives free.
]]
local ADDON, ns = ...
local Selector = ns.Selector
local Ops = ns.Ops          -- loads before this file; see harness LOAD_ORDER

local Aura = {}
ns.Aura = Aura

-- Collect all entities that can host an aura layer, in deterministic order.
local function allEntities(game)
  local out = {}
  for pi = 1, 2 do
    local p = game.players[pi]
    for _, e in ipairs(p.board) do out[#out + 1] = e end
    for _, e in ipairs(p.hand)  do out[#out + 1] = e end
    if p.hero   then out[#out + 1] = p.hero end
    if p.weapon then out[#out + 1] = p.weapon end
  end
  return out
end

-- Live aura sources, in play order.
local function auraSources(game)
  local out = {}
  for pi = 1, 2 do
    --[[ The equipped weapon can host an aura too (Cogmaster's Wrench: +2 Attack
         while you have a Mech). This used to iterate the board alone, so a weapon
         aura was silently inert. Weapons are considered first so their play order
         stamp still decides ordering via the sort below. ]]
    local w = game.players[pi].weapon
    if w and not w.silenced then
      local ws = game:ScriptFor(w.cardId)
      if ws and ws.aura then out[#out + 1] = { entity = w, spec = ws.aura } end
    end
    --[[ A card in HAND can host an aura, but ONLY over itself. That is what the
         Giants are: Mountain Giant costs (1) less for each other card in your
         hand, and it does so while sitting in that hand, where no other aura
         has any business reaching.

         Restricting hand sources to `sel.self` is what keeps this narrow. Were
         every hand card a full aura source, Sorcerer's Apprentice would
         discount your spells from HAND -- which is emphatically not the card. ]]
    for _, e in ipairs(game.players[pi].hand) do
      local script = game:ScriptFor(e.cardId)
      --[[ ...and only over its own COST. The stat layers must stay out of it:
           Lightspawn's "Attack is always equal to its Health" is a self-aura
           too, and without this restriction it renders as a 5/5 in hand instead
           of the printed 0/5. A card in hand has a cost that matters and stats
           that are only a picture. ]]
      if script and script.aura and script.aura.sel and script.aura.sel.self
         and script.aura.cost and not e.silenced then
        out[#out + 1] = { entity = e, spec = { sel = script.aura.sel,
                                               cost = script.aura.cost,
                                               cond = script.aura.cond } }
      end
    end

    for _, e in ipairs(game.players[pi].board) do
      local script = game:ScriptFor(e.cardId)
      if script and script.aura and not e.silenced then
        out[#out + 1] = { entity = e, spec = script.aura }
      end
      if script and script.enrage and not e.silenced then
        out[#out + 1] = { entity = e, spec = script.enrage, enrage = true }
      end
    end
  end
  table.sort(out, function(a, b)
    local ao, bo = a.entity.playOrder or 0, b.entity.playOrder or 0
    if ao ~= bo then return ao < bo end
    return a.entity.instanceId < b.entity.instanceId
  end)
  return out
end

function Aura.Recalc(game)
  local ents = allEntities(game)
  local hadHp = {}
  for _, e in ipairs(ents) do
    hadHp[e] = e.aura and e.aura.hp or 0
    e:ClearAuraLayer()
  end

  for _, src in ipairs(auraSources(game)) do
    local e, spec = src.entity, src.spec
    -- Enrage only contributes while the host is damaged.
    -- NOTE: no `goto` -- WoW ships Lua 5.1, where goto/labels do not exist.
    local active = (not src.enrage) or e:IsDamaged()
    --[[ Conditional auras: the aura applies only while its condition holds
         (Cogmaster is +2 Attack only while you have a weapon). Because the aura
         layer is rebuilt from zero on every recalculation, a condition going
         false simply stops contributing -- there is nothing to un-apply. ]]
    if active and src.spec.cond then
      active = ns.Conditions.Eval(game, src.spec.cond,
                                  { source = e, controller = e.controller })
    end
    if active then
      local ctx = { source = e, controller = e.controller }
      local targets = src.enrage and { e } or Selector.Resolve(game, spec.sel, ctx)
      --[[ A magnitude may be DYNAMIC rather than a fixed number: Mountain Giant
           costs (1) less for each other card in your hand, Old Murk-Eye has +1
           Attack for each other Murloc. Because the whole aura layer is rebuilt
           from zero on every recalculation, a dynamic magnitude needs no
           invalidation machinery at all -- it is simply re-read, so the Giant's
           cost tracks the hand as cards are drawn and played.

           `sign` is carried separately because the DSL writes the reduction as
           `-count(...)`, and a count cannot itself be negative. ]]
      local function mag(v)
        if type(v) == "table" then
          local n = Ops.Amount(game, { amount = v }, ctx)
          return v.negate and -n or n
        end
        return v or 0
      end
      local datk, dhp, dcost = mag(spec.atk), mag(spec.hp), mag(spec.cost)
      for _, t in ipairs(targets) do
        --[[ "Costs (2) less, but not less than (1)" (Summoning Portal): the
             reduction stops at the floor, and never raises a card that
             already costs less (a Wisp stays 0). Sources apply in play order,
             so a later discount still stacks past it. ]]
        local dc = dcost
        if spec.costFloor and dc < 0 then
          local before = t.base.cost + t.ench.cost + t.aura.cost + t.timed.cost
          dc = math.min(0, math.max(dc, spec.costFloor - before))
        end
        t.auraSources[#t.auraSources+1] = {source=e.cardId, atk=datk, hp=dhp, cost=dc, keywords=spec.keywords}
        t.aura.atk  = t.aura.atk  + datk
        t.aura.hp   = t.aura.hp   + dhp
        t.aura.cost = t.aura.cost + dc
        for _, k in ipairs(spec.keywords or {}) do t.auraKeywords[k] = true end
      end
    end
  end

  --[[ Mal'Ganis: "Your hero is Immune." A second, fixed aura beside his +2/+2
       on Demons, declared as a script property. On the hero's aura layer, so it
       ends the moment Mal'Ganis dies or is silenced. ]]
  for pi = 1, 2 do
    local p = game.players[pi]
    for _, e in ipairs(p.board) do
      local s = not e.silenced and game:ScriptFor(e.cardId)
      if s and s.heroImmune and p.hero then
        p.hero.auraKeywords[ns.KEYWORD.IMMUNE] = true
      end
    end
  end

  --[[ LOSING AN AURA'S HEALTH NEVER KILLS. Hearthstone keeps current Health
       unless it is above the new maximum: a damaged 1/1 held at 1/2 by
       Stormwind Champion is a 1/1 at full Health when the Champion dies, not
       a corpse. Damage is soaked by the lost Health first. (Losing an
       ENCHANTMENT -- Silence -- is different and can kill; that is not here.) ]]
  for _, e in ipairs(ents) do
    local lost = (hadHp[e] or 0) - e.aura.hp
    if lost > 0 and (e.damage or 0) > 0 then
      e.damage = math.max(0, e.damage - lost)
    end
  end

  -- Enrage bookkeeping for UI/animation hooks only; not a gameplay source.
  for _, e in ipairs(ents) do
    local script = game:ScriptFor(e.cardId)
    e.enraged = (script and script.enrage and e:IsDamaged() and not e.silenced) or false
  end
end

return Aura
