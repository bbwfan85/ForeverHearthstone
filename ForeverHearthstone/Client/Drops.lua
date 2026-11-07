--[[ Kill rewards are packs only. Base chances: normal 1.5%, elite 4%,
     rare 5%, boss 12%. First encounter kills and raid bosses guarantee a pack.
     Eligible non-boss kills also receive saved bad-luck protection. ]]
local ADDON, ns = ...

local Drops = {}
ns.Drops = Drops

-- Percent; fractions are fine (rolled per mille).
Drops.RATES = {
  normal = 1.5,
  elite  = 4,
  boss   = 12,    -- dungeon boss (raid bosses and first kills: guaranteed)
  rare   = 5,     -- rare spawn
  critter = 0,
  totem   = 0,    -- totems, pets, guardians and anything else summoned
}

-- Legacy single-card grant helpers retained for old callers; kill rolls never use them.
Drops.BOSS_ODDS = {
  { rarity = "COMMON", pct = 50 }, { rarity = "RARE", pct = 30 },
  { rarity = "EPIC", pct = 12 }, { rarity = "LEGENDARY", pct = 8 },
}

Drops.MAX_LEVEL = 60
Drops.ENDGAME_MIN_MOB_LEVEL = 55

--[[ WoW creature type -> the card race a kill of that type biases toward.

     This is the "kill yetis, get a Yeti" set trigger from the brief, expressed
     as data. Only types whose mapping is unambiguous are listed; everything
     else simply has no bias, which is a much better failure than a wrong one.

     NOTE ON MURLOCS: murlocs in WoW are Humanoid, so there is no creature type
     that names them. That is why Old Murk-Eye's "collect every Murloc" is a
     COLLECTION trigger in Client/Packs and not a kill trigger -- the game
     cannot tell us we killed one.

     UNVERIFIED STRINGS. UnitCreatureType returns LOCALISED text, so these match
     only on an English client. Client/Main passes what the API gave it and a
     miss means no bias, never a wrong card -- so this degrades to "drops still
     happen, they are just not themed" on a French realm. Fixing it properly
     needs the numeric creature type, which the probe is looking for. ]]
Drops.RACE_BY_CREATURE_TYPE = {
  ["Beast"]      = "BEAST",
  ["Dragonkin"]  = "DRAGON",
  ["Demon"]      = "DEMON",
  ["Mechanical"] = "MECHANICAL",
  ["Elemental"]  = "ELEMENTAL",
  ["Totem"]      = "TOTEM",
}

--[[ Creature types that are worth nothing, whatever else is true. Critters are
     the obvious farm; totems, pets and other summons are the less obvious one
     (a Shaman would otherwise drop-farm their own totems). ]]
local WORTHLESS_TYPE = {
  ["Critter"] = true,
  ["Totem"]   = true,
  ["Non-combat Pet"] = true,
}

-- ========================================================= eligibility

--[[ Is this kill worth rolling for at all? Returns false plus the reason, and
     the reason is kept because `/fh drops` prints it -- "why did that not drop"
     is the first question anyone asks about a 1% rate. ]]
function Drops.Eligible(kill)
  kill = kill or {}
  if kill.kind == "critter" or WORTHLESS_TYPE[kill.creatureType or ""]
     or kill.classification == "minus" or kill.classification == "trivial" then
    return false, "critters and summons are worth nothing"
  end
  if kill.summoned then return false, "summons are worth nothing" end

  local level = kill.playerLevel or 1
  if level >= Drops.MAX_LEVEL then
    --[[ At max level nothing grants XP, so the gate has to become something
         else or the endgame stops dropping entirely. Mob level is the closest
         equivalent rule and needs no arithmetic. ]]
    -- a skull ("??", level -1) is always high enough
    local mobLevel = kill.mobLevel or 0
    if mobLevel >= 0 and mobLevel < Drops.ENDGAME_MIN_MOB_LEVEL and kill.kind ~= "boss" then
      return false, "that was too low level to be worth anything at 60"
    end
    return true
  end

  if not kill.grantsXP then
    return false, "grey mobs give no XP, so they give no packs"
  end
  return true
end

-- ============================================================== rolling

-- Roll one eligible kill: nil or one automatically banked pack.
function Drops.Roll(kill, rng)
  kill = kill or {}
  local ok = Drops.Eligible(kill)
  if not ok then return nil end

  local rate = Drops.RATES[kill.kind or "normal"] or 0
  if kill.guaranteed then rate = 100 end
  if rate <= 0 then return nil end
  if ns.Packs.Roll(rng, 1000) > rate * 10 then return nil end

  return { kind = "PACK", set = ns.Packs.SETS.HEARTHSTONE }
end

function Drops.RaceFor(creatureType)
  if not creatureType then return nil end
  return Drops.RACE_BY_CREATURE_TYPE[creatureType]
end

--[[ Turn a rolled reward into an actual change to the collection, and report
     what happened in the shape the toast choreography wants.

     Separate from Roll so the roll can be tested without a collection and the
     banking can be tested without a distribution. ]]
function Drops.Grant(collection, reward, rng)
  if not reward then return nil end
  if reward.kind == "PACK" then
    collection:AddPack(reward.set, 1)
    collection.account.stats.cardsDropped = collection.account.stats.cardsDropped or 0
    return { kind = "PACK", set = reward.set, total = collection:TotalPacks() }
  end

  local card
  if reward.boss then
    card = Drops.BossCard(rng, collection, reward.golden)
    if not card then
      -- every Naxxramas card is complete: the boss pays a pack instead
      return Drops.Grant(collection, { kind = "PACK", set = ns.Packs.SETS.HEARTHSTONE, naxxDone = true }, rng)
    end
  else
    card = ns.Packs.DropCard(rng, { set = reward.set, race = reward.race,
                                    golden = reward.golden })
  end
  if not card then return nil end
  collection:Add(card.cardId, 1, card.golden)
  collection.account.stats.cardsDropped = (collection.account.stats.cardsDropped or 0) + 1

  --[[ A card arriving can complete a collection trigger -- the last Murloc
       grants Old Murk-Eye. Checked here rather than on a timer, so the reward
       lands in the same moment as the kill that earned it. ]]
  local triggered = ns.Packs.CheckTriggers(collection)
  return { kind = "CARD", cardId = card.cardId, rarity = card.rarity,
           golden = card.golden, set = reward.set,
           extra = collection:Count(card.cardId) > collection:MaxCopies(card.cardId),
           triggered = (#triggered > 0) and triggered or nil }
end

--[[ Expected kills per pack, for the tuning conversation. Printed by
     `/fh drops` so the rate can be argued about with a number rather than a
     feeling. ]]
function Drops.KillsPerReward(kind)
  local rate = Drops.RATES[kind or "normal"] or 0
  if rate <= 0 then return nil end
  return 100 / rate
end

--[[ One Naxxramas card on the boss odds, WITH DUPLICATE PROTECTION.

     The adventure is 21 neutral cards (nine commons, four rares, two epics,
     six legendaries: 36 copies for a full set). Packs carry it too now (the
     combined pool, Packs.lua), but bosses are where it is aimed: a boss card
     is never one you already hold the maximum of:
     the roll picks the rarity, then a card of that rarity you can still use.
     If that rarity is complete it moves to the nearest one that is not,
     rarer first. This used to re-roll ONCE and then hand over the spare
     anyway, so the sixth legendary took on average several times as many
     boss kills as the first five.

     Returns nil once every Naxxramas card is complete; the caller then pays
     a pack instead (Drops.Grant), so a boss is never worth nothing. ]]
local RARITY_STEPS = { "COMMON", "RARE", "EPIC", "LEGENDARY" }
function Drops.BossCard(rng, collection, golden)
  local r, acc, rarity = ns.Packs.Roll(rng, 100), 0, "COMMON"
  for _, o in ipairs(Drops.BOSS_ODDS) do
    acc = acc + o.pct
    if r <= acc then rarity = o.rarity; break end
  end
  local function usable(rar)
    local out = {}
    for _, id in ipairs(ns.Packs.Pool(ns.Packs.BOSS_SET, rar)) do
      if not collection or collection:Count(id) < collection:MaxCopies(id) then out[#out + 1] = id end
    end
    return out
  end
  local at = 1
  for i, name in ipairs(RARITY_STEPS) do if name == rarity then at = i end end
  -- the rolled rarity, then one step rarer, one step commoner, two rarer...
  local order = { at }
  for d = 1, #RARITY_STEPS do
    if at + d <= #RARITY_STEPS then order[#order + 1] = at + d end
    if at - d >= 1 then order[#order + 1] = at - d end
  end
  for _, i in ipairs(order) do
    local pool = usable(RARITY_STEPS[i])
    if #pool > 0 then
      return { cardId = pool[ns.Packs.Roll(rng, #pool)], rarity = RARITY_STEPS[i], golden = golden or false }
    end
  end
  return nil
end

--[[ BAD LUCK HAS A FLOOR. At 1.5% a kill, one player in ten goes 150 kills
     without a drop -- an evening of levelling with nothing to show. So every
     eligible kill that pays nothing adds its drop chance to a dry spell, and
     once the dry spell reaches DRY_LIMIT (150 normal kills' worth; an elite
     counts for its higher rate) the next eligible kill pays. Any drop resets
     it. It is saved per character. On average it adds about a tenth to the
     drop rate; what it removes is the long drought. ]]
Drops.DRY_LIMIT = 150 * 1.5

--- Is this kill owed a drop by the bad-luck floor? `dry` is the saved spell.
function Drops.Owed(kill, dry)
  if not kill or kill.kind == "boss" then return false end
  return (dry or 0) >= Drops.DRY_LIMIT and Drops.Eligible(kill) and true or false
end

--- The dry spell after this kill: reset by a reward, else grown by its chance.
function Drops.AfterKill(kill, dry, reward)
  if reward then return 0 end
  if not kill or kill.kind == "boss" or not Drops.Eligible(kill) then return dry or 0 end
  return (dry or 0) + (Drops.RATES[kill.kind or "normal"] or 0)
end

return Drops
