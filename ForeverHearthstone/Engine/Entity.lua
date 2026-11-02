--[[ Engine/Entity.lua

  THE ATTRIBUTE LAYERING MODEL -- the most important decision in the engine.

  A minion's live stats are never stored as a single number. They are computed
  from four independent layers:

    base      printed values, immutable, straight from PrintedCards.lua
    ench      permanent enchantments (Blessing of Kings, Abusive Sergeant...)
    aura      continuous, RECOMPUTED FROM ZERO on every board change
    damage    damage taken; persists across buffs; NOT an attack/health delta

    attack = base.atk + ench.atk + aura.atk        (floored at 0)
    maxHP  = base.hp  + ench.hp  + aura.hp
    health = maxHP - damage

  Why this and not a single mutable stat block:

  * Auras must be removable without remembering what they gave. Dire Wolf Alpha
    dying, or being silenced, or a neighbour shuffling position, must all
    "un-buff" correctly. Recomputing the aura layer from scratch makes that
    free and impossible to get wrong. A mutable +1/+1 that you have to subtract
    later is how aura bugs happen, and they are the #1 source of desyncs.
  * Silence must clear ench but preserve damage. Hearthstone rule: silencing a
    minion with a health buff can kill it, because maxHP drops below damage.
    Layering gives that behaviour for free.
  * Damage must survive healing/buffing order. A 3/2 that took 1 damage and
    then gets +0/+3 is a 3/4 with 1 damage = 3 current health, not 3/5.

  Aura recalculation is O(sources x targets) with at most 14 minions. That is
  ~200 table reads. Do not optimise this; correctness is worth far more than
  the microseconds, and a stale aura cache is a desync.
]]
local ADDON, ns = ...

local Entity = {}
Entity.__index = Entity
ns.Entity = Entity

--[[ INSTANCE IDS BELONG TO A GAME, NOT TO THE PROCESS.

     An action names its target by instance id, and that only works because both
     clients hand out the same ids in the same order. A single global counter
     breaks that the moment one process holds two games: the second game's
     entities advance a counter the first game is still using, so a token
     summoned on one client gets a different id from the same token on the
     other -- and an attack then names an entity that does not exist over there.

     That is not hypothetical. It is exactly what the two-sessions-in-one-Lua-
     state soak test hit: identical boards, identical state hashes (which do not
     include ids), and an ATTACK that arrived as "unknown combatant" seventeen
     turns in. Two separate WoW clients would not have shown it.

     So the counter is per-game. Game.New makes one and every entity the game
     creates draws from it; the module-level fallback exists only for a caller
     with no game to hand (some tests build a loose entity). ]]
local nextId = 0
local function newInstanceId()
  nextId = nextId + 1
  return nextId
end

--[[ A fresh, independent id source. One per Game.

     A callable TABLE rather than a closure, so its count is plain data: that is
     what lets Game:Clone copy a game and have the copy hand out exactly the ids
     the original would. A closure's counter is an upvalue, and nothing outside
     the closure can read or copy it. ]]
local IdSource = { __call = function(self) self.n = self.n + 1; return self.n end }

function Entity.NewIdSource()
  return setmetatable({ n = 0 }, IdSource)
end

--- Reset the module-level counter. Kept for callers that build loose entities.
function Entity.ResetIds() nextId = 0 end

--- @param ids optional id source (see Entity.NewIdSource); the game supplies its own
function Entity.New(printed, controller, ids)
  local e = setmetatable({}, Entity)
  e.instanceId  = (ids or newInstanceId)()
  e.cardId      = printed.id
  e.printed     = printed
  e.controller  = controller          -- player index 1 or 2
  e.owner       = controller          -- original owner; Mind Control changes controller only
  e.zone        = ns.ZONE.DECK
  e.boardIndex  = nil                 -- 1..7, left to right; drives adjacency

  e.base = { atk = printed.atk or 0, hp = printed.hp or 0, cost = printed.cost or 0,
             dur = printed.dur }
  e.ench = { atk = 0, hp = 0, cost = 0 }
  e.aura = { atk = 0, hp = 0, cost = 0 }
  e.timed = { atk = 0, hp = 0, cost = 0 }   -- expiring buffs; see timedEnch below
  e.damage = 0
  e.armor  = 0                        -- heroes only

  --[[ Timed enchantments ("+2 Attack this turn", "Stealth until your next
       turn"). Stored as a LIST, not a single slot, because they stack -- two
       Abusive Sergeants on one minion is +4 attack this turn, and each must
       expire on its own schedule.

       The `timed` layer above is REBUILT FROM THIS LIST, never mutated directly,
       for the same reason auras are: removing a buff by subtracting what you
       think you added is how you end up with a permanently buffed minion. ]]
  e.timedEnch = {}      -- { {atk=,hp=,keywords=,expiry=,turn=,controller=}, ... }

  -- keyword flags: four layers, same reasoning as stats
  e.baseKeywords = {}
  e.enchKeywords = {}
  e.auraKeywords = {}
  e.timedKeywords = {}
  for _, k in ipairs(printed.keywords or {}) do e.baseKeywords[k] = true end

  e.silenced       = false
  e.attacksThisTurn= 0
  e.summonedTurn   = nil              -- for summoning sickness
  e.pendingDestroy = false
  e.divineShieldUp = e.baseKeywords[ns.KEYWORD.DIVINE_SHIELD] or false
  e.enraged        = false
  e.triggers       = {}               -- populated from the effect script
  --[[ A LIST, not a slot. Ancestral Spirit / Reincarnate / Poison Seeds GRANT a
       deathrattle, and a minion may already have one -- assigning would silently
       destroy the original, which is both wrong and invisible. ]]
  e.deathrattles   = {}
  return e
end

-- ---------------------------------------------------------------- stats

function Entity:Attack()
  --[[ Lightspawn: "Attack is always equal to its Health." Not a buff on top of
       the layers -- the layers are ignored. Blessing of Might, Abusive
       Sergeant and Dire Wolf Alpha all land and do nothing; only Health
       changes move it (hearthstone.wiki.gg/wiki/Lightspawn). Silence ends it,
       and in hand it is the printed 0. ]]
  if self.attackIsHealth and not self.silenced and self.zone == ns.ZONE.PLAY then
    return self:Health()
  end
  local a = self.base.atk + self.ench.atk + self.aura.atk + self.timed.atk
  return a < 0 and 0 or a
end

function Entity:MaxHealth()
  local h = self.base.hp + self.ench.hp + self.aura.hp + self.timed.hp
  --[[ The floor-at-1 is a MINION rule: no debuff takes a minion below 1 maximum
       health. A WEAPON's health layer is its durability, and 0 durability means
       broken -- so weapons are deliberately exempt, or Sword of Justice-style
       durability loss could never break anything. ]]
  if self.printed and self.printed.type == "WEAPON" then
    return h < 0 and 0 or h
  end
  return h < 1 and 1 or h
end

function Entity:Health() return self:MaxHealth() - self.damage end

--[[ The card's own cost layers, NOT floored. Hearthstone keeps a hidden cost
     with no lower limit and floors only once every modifier is in: a Moonfire
     under Sorcerer's Apprentice is at (-1), so Loatheb's +5 makes it (4), not
     (5). Game:CardCost adds the player's modifiers to this and floors last. ]]
function Entity:RawCost()
  return self.base.cost + self.ench.cost + self.aura.cost + self.timed.cost
end

function Entity:Cost()
  local c = self:RawCost()
  return c < 0 and 0 or c
end

function Entity:IsDamaged() return self.damage > 0 end
function Entity:IsDead()    return self:Health() <= 0 or self.pendingDestroy end

-- ------------------------------------------------------------- keywords

--[[ Silence empties the base, enchantment and timed keyword layers (see
     Entity:Silence), so nothing here needs to ask whether the minion is
     silenced. It used to return aura keywords only while `silenced` was set,
     which meant a silenced minion could never GAIN a keyword again: Sunfury
     Protector's Taunt, Conceal's Stealth and Argent Protector's Divine Shield
     all landed and did nothing. ]]
function Entity:Has(kw)
  return self.baseKeywords[kw] or self.enchKeywords[kw]
      or self.auraKeywords[kw] or self.timedKeywords[kw] or false
end

function Entity:IsTaunt()  return self:Has(ns.KEYWORD.TAUNT) end
function Entity:IsStealth()return self:Has(ns.KEYWORD.STEALTH) end
function Entity:IsFrozen() return self.frozen == true end

function Entity:IsElusive()
  return self:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_SPELLS)
end

-- Can this entity attack right now?
function Entity:CanAttack(turn)
  if self.zone ~= ns.ZONE.PLAY then return false end
  if self:Has(ns.KEYWORD.CANT_ATTACK) then return false end
  if self.frozen then return false end
  if self:Attack() <= 0 then return false end
  -- summoning sickness: cannot attack the turn it was summoned, unless Charge
  if self.printed.type == ns.CARDTYPE.MINION
     and self.summonedTurn == turn
     and not self:Has(ns.KEYWORD.CHARGE) then
    return false
  end
  local allowed = self:Has(ns.KEYWORD.WINDFURY) and 2 or 1
  return self.attacksThisTurn < allowed
end

-- ------------------------------------------------------- mutation helpers

-- Permanent buff. Positive hp raises maxHP without healing existing damage,
-- which is the Hearthstone behaviour.
function Entity:AddEnchantment(datk, dhp, keywords, source)
  self.enchantmentSources = self.enchantmentSources or {}
  self.enchantmentSources[#self.enchantmentSources + 1] = {
    atk=datk or 0, hp=dhp or 0, keywords=keywords, source=source,
  }
  self.ench.atk = self.ench.atk + (datk or 0)
  self.ench.hp  = self.ench.hp  + (dhp or 0)
  for _, k in ipairs(keywords or {}) do self.enchKeywords[k] = true end
end

function Entity:SetEnchantmentStat(key, value, source)
  self.enchantmentSources = self.enchantmentSources or {}
  for _,x in ipairs(self.enchantmentSources) do x[key]=nil end
  self.enchantmentSources[#self.enchantmentSources+1] = {[key]=value,source=source}
  self.ench[key]=value
end

--[[ A SET effect (Equality, Humility, Hunter's Mark, Redemption's 1 Health)
     overrides every enchantment that came before it -- permanent and this-turn
     buffs alike -- but NOT auras: those come from other minions and are
     applied on top. Equality under a Stormwind Champion leaves 1/2 minions, as
     in Hearthstone; subtracting the aura here used to leave them 1/1. ]]
function Entity:SetStat(key, value, source)
  self:SetEnchantmentStat(key, value - self.base[key], source)
  for _, x in ipairs(self.timedEnch) do x[key] = 0 end
  self:RecalcTimed()
end

function Entity:CopyEnchantmentSources(other)
  self.enchantmentSources={}
  for _,entry in ipairs(other.enchantmentSources or {}) do
    local copy={}; for k,v in pairs(entry) do copy[k]=v end
    self.enchantmentSources[#self.enchantmentSources+1]=copy
  end
end

function Entity:ForgetKeywordSource(keyword)
  for _,list in ipairs({self.enchantmentSources or {},self.timedEnch}) do
    for _,entry in ipairs(list) do
      local kept={}
      for _,k in ipairs(entry.keywords or {}) do if k~=keyword then kept[#kept+1]=k end end
      entry.keywords=kept
    end
  end
  self:RecalcTimed()
end

-- ------------------------------------------------------ timed enchantments

--[[ Add an expiring buff.
     @param expiry  ns.DURATION.END_OF_TURN            -- "this turn"
                    ns.DURATION.START_OF_YOUR_NEXT_TURN -- "until your next turn"
     @param turn        the game turn it was applied on
     @param controller  whose "next turn" the second form refers to

     Negative values are fine and used: Shrinkmeister gives -2 Attack this turn.
     Attack floors at 0 in Entity:Attack, so a -2 on a 1-attack minion reads 0
     rather than going negative. ]]
function Entity:AddTimedEnchantment(atk, hp, keywords, expiry, turn, controller, source)
  self.timedEnch[#self.timedEnch + 1] = {
    atk = atk or 0, hp = hp or 0, keywords = keywords,
    expiry = expiry, turn = turn, controller = controller, source = source,
  }
  self:RecalcTimed()
end

--- Rebuild the timed layer from the list. Always from zero.
function Entity:RecalcTimed()
  local t = { atk = 0, hp = 0, cost = 0 }
  local kw = {}
  for _, x in ipairs(self.timedEnch) do
    t.atk = t.atk + (x.atk or 0)
    t.hp  = t.hp  + (x.hp  or 0)
    t.cost = t.cost + (x.cost or 0)
    for _, k in ipairs(x.keywords or {}) do kw[k] = true end
  end
  self.timed = t
  self.timedKeywords = kw
end

--[[ Drop every timed enchantment for which `pred(entry)` is true.
     Returns how many were removed, so the caller knows whether to run a death
     phase -- an expiring HEALTH buff can kill, exactly as silence can. ]]
function Entity:ExpireTimed(pred)
  local kept, removed = {}, 0
  for _, x in ipairs(self.timedEnch) do
    if pred(x) then removed = removed + 1 else kept[#kept + 1] = x end
  end
  if removed > 0 then
    self.timedEnch = kept
    self:RecalcTimed()
  end
  return removed
end

-- Silence: clear ench layer, keywords, triggers, deathrattle. Damage stays.
-- If maxHP now sits at or below damage taken, the minion dies in the next
-- death phase -- correct, and emergent rather than special-cased.
function Entity:Silence()
  --[[ Losing Health buffs NEVER kills: "when a minion's maximum Health is
       reduced, its current Health is only reduced if it exceeds the new
       maximum" (hearthstone.wiki.gg/wiki/Health). A Blessing of Kings Yeti
       at 8/3 is a 4/3 after Silence, not a corpse. Aura.Recalc already did
       this for auras; Silence took the enchantments and kept the damage. ]]
  local maxBefore = self:MaxHealth()
  self.silenced   = true
  -- printed keywords go too (Taunt, Divine Shield, Stealth, Can't Attack);
  -- keywords given AFTER the silence live in the other layers and count
  self.baseKeywords = {}
  self.enchGen    = (self.enchGen or 0) + 1   -- ends Corruption-style schedules
  self.spellDamageBonus = nil
  self.ench       = { atk = 0, hp = 0, cost = 0 }
  self.enchKeywords = {}
  -- timed buffs are enchantments too, so silence removes them as well
  self.timedEnch  = {}
  self.timed      = { atk = 0, hp = 0, cost = 0 }
  self.timedKeywords = {}
  self.triggers   = {}
  self.deathrattles = {}
  self.frozen     = false
  self.divineShieldUp = false
  self.enraged    = false
  -- The aura layer is untouched here, so MaxHealth is already the new maximum.
  -- Lost maximum is soaked by the damage first (the Aura.Recalc rule); a GAINED
  -- maximum -- a Reversing-Switched 7/6 Ogre silenced back to 6/7 -- raises
  -- current Health with it, and the damage is kept.
  local lost = maxBefore - self:MaxHealth()
  if lost > 0 then self.damage = math.max(0, self.damage - lost) end
end

function Entity:ClearAuraLayer()
  self.auraSources = {}
  self.aura = { atk = 0, hp = 0, cost = 0 }
  self.auraKeywords = {}
end

-- Detached, readable provenance for the card inspector. Never expose entities.
function Entity:EffectDescriptions()
  local lines = {}
  local function name(id)
    local p = id and ns.PrintedCards[id]
    return p and p.name or id or "Effect"
  end
  local function describe(x, suffix, layer)
    local parts = {}
    if (x.atk or 0) ~= 0 then parts[#parts+1] = string.format("%+d Attack", x.atk) end
    if (x.hp or 0) ~= 0 then parts[#parts+1] = string.format("%+d Health", x.hp) end
    if (x.cost or 0) ~= 0 then parts[#parts+1] = string.format("%+d Cost", x.cost) end
    for _, k in ipairs(x.keywords or {}) do
      if layer[k] and self:Has(k) and (k ~= ns.KEYWORD.DIVINE_SHIELD or self.divineShieldUp) then
        parts[#parts+1] = k:gsub("_", " "):lower()
      end
    end
    if #parts > 0 then lines[#lines+1] = name(x.source) .. ": " .. table.concat(parts, ", ") .. (suffix or "") end
  end
  if not self.silenced then
    describe({source=self.cardId, keywords=self.printed.keywords}, " (printed)", self.baseKeywords)
    for _, x in ipairs(self.enchantmentSources or {}) do describe(x, "", self.enchKeywords) end
    for _, x in ipairs(self.timedEnch) do
      describe(x, x.expiry == ns.DURATION.END_OF_TURN and " (this turn)" or " (until your next turn)", self.timedKeywords)
    end
  else lines[#lines+1] = "Silenced" end
  for _, x in ipairs(self.auraSources or {}) do describe(x, " (aura)", self.auraKeywords) end
  if self.frozen then lines[#lines+1] = "Frozen" end
  if self.damage > 0 then lines[#lines+1] = tostring(self.damage) .. " damage taken" end
  return lines
end

function Entity:Snapshot()
  return { instanceId = self.instanceId, cardId = self.cardId,
           atk = self:Attack(), hp = self:Health(), zone = self.zone,
           boardIndex = self.boardIndex, controller = self.controller }
end

return Entity
