--[[ Client/Packs.lua

  WHAT IS IN A PACK, AND WHAT A MOB DROPS.

  NO WoW API. The randomness is injected, so every distribution in here is
  testable by rolling ten thousand packs in a terminal rather than by opening
  packs in game and forming an impression.

  ========================================================= WHOSE NUMBERS

  Be clear about which numbers come from where, because this project's first
  rule is that card data is imported and never recalled:

    * THE CARD POOL is printed data. Which cards can be in a Classic pack falls
      out of `set` and `class` on the pinned build; there is no list here.
    * THE ODDS ARE OURS. Hearthstone's real pack odds are not in the vendored
      JSON and are not something to half-remember. Deviation 7 permits a retuned
      economy, so these are chosen numbers, tuned against the completion maths in
      docs/04, and they live in one table so retuning is a data change.

  The one rule taken from Hearthstone rather than invented: EVERY PACK CONTAINS
  AT LEAST ONE RARE OR BETTER. It is the thing that stops a pack ever being
  nothing, and it is worth keeping whatever the rest of the economy does.

  ======================================================= PACKS ARE NEUTRAL

  Decision D4: class cards come from levelling, packs award neutrals only. So
  every query here filters to NEUTRAL, and there is no way to express anything
  else -- a class card in a pack would break the levelling curve rather than be
  a nice surprise.

  One combined Classic, GvG and Naxxramas neutral pack. Legacy pack identifiers
  remain accepted. Class cards are guaranteed level rewards.
]]
local ADDON, ns = ...

local Packs = {}
ns.Packs = Packs

Packs.SIZE = 5

-- One combined pack, with legacy identifiers accepted.
Packs.SETS = {
  HEARTHSTONE = "HEARTHSTONE",
  CLASSIC = "EXPERT1", -- legacy identifier; generation uses the combined pool
  GVG     = "GVG",     -- legacy identifier
}
Packs.BOSS_SET = "NAXX"

--[[ Per-card rarity odds, in percent. OURS, not Hearthstone's (see the header).
     They must sum to 100; a test asserts it, because a table that sums to 97
     silently makes the last entry more likely and nobody would notice. ]]
Packs.ODDS = {
  { rarity = "COMMON",    pct = 71 },
  { rarity = "RARE",      pct = 23 },
  { rarity = "EPIC",      pct =  5 },
  { rarity = "LEGENDARY", pct =  1 },
}

--[[ Chance in percent that a given card comes up golden.

     Goldens are the drop-only chase (deviation 3): never craftable, so this and
     the mob-drop roll are the only two ways one ever exists. Kept low enough
     that a golden is an event -- roughly one per twenty packs. ]]
Packs.GOLDEN_PCT = 1

-- ============================================================== rolling

--[[ A roll is a function returning an integer in [1, n]. Injected rather than
     calling math.random directly: the engine's ban on math.random is about
     lockstep and does not apply here (opening a pack is a solo act), but a
     distribution you cannot seed is a distribution you cannot test. ]]
local function defaultRoll(n) return math.random(1, n) end

function Packs.Roll(rng, n)
  if n <= 0 then return 0 end
  return (rng or defaultRoll)(n)
end

--- One rarity, drawn from ODDS. `floor` forces a minimum rarity.
function Packs.RollRarity(rng, floor)
  local r = Packs.Roll(rng, 100)
  local acc = 0
  local picked = Packs.ODDS[#Packs.ODDS].rarity
  for _, o in ipairs(Packs.ODDS) do
    acc = acc + o.pct
    if r <= acc then picked = o.rarity break end
  end
  if floor then
    local order = { COMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }
    if (order[picked] or 1) < (order[floor] or 1) then return floor end
  end
  return picked
end

--[[ Every neutral collectible id in a set at a rarity, sorted.

     Sorted for the same reason Engine/CardPool sorts: pairs() order is
     unspecified, so an unsorted pool fed to a roll gives a different card on
     two machines from the same seed. Nothing here is lockstep, but a pack you
     cannot reproduce is a pack you cannot debug. Cached -- the pool is
     immutable. ]]
local poolCache = {}
function Packs.Pool(set, rarity, race)
  local key = tostring(set) .. "|" .. tostring(rarity) .. "|" .. tostring(race)
  if poolCache[key] then return poolCache[key] end
  local out = {}
  for id, p in pairs(ns.PrintedCards or {}) do
    if p.collectible and p.class == "NEUTRAL" and p.type ~= "HERO"
       and (not set or p.set == set or (set == "HEARTHSTONE" and (p.set == "EXPERT1" or p.set == "GVG" or p.set == "NAXX")))
       and (not rarity or p.rarity == rarity)
       and (not race or p.race == race)
       --[[ The four promo/reward cards have their own acquisition paths
            (docs/03 D1) and must never turn up in a pack, or the chase is
            replaced by a lottery ticket. ]]
       and not p.unobtainable then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  poolCache[key] = out
  return out
end

function Packs.ResetPoolCache() poolCache = {} end

--[[ One card of a given rarity from a set, or nil if that pool is empty. A
     rarity with no cards is possible in a small set, and returning nil rather
     than substituting silently is what lets the caller re-roll visibly. ]]
function Packs.RandomCard(rng, set, rarity, race)
  local pool = Packs.Pool(set, rarity, race)
  if #pool == 0 then return nil end
  return pool[Packs.Roll(rng, #pool)]
end

-- ============================================================== opening

--[[ Generate the contents of one pack. Does NOT touch the collection -- that is
     Open's job -- so the contents can be generated, animated, and only then
     banked, which is the order the reveal choreography needs.

     Returns a list of { cardId, rarity, golden } plus a summary the pack-crack
     choreography reads: the best rarity in the pack decides whether the
     face-down cards get the legendary tell, and which one glows. ]]
function Packs.Generate(set, opts)
  opts = opts or {}
  local rng = opts.rng
  local printedSet = (set == "CLASSIC" or set == "GVG") and "HEARTHSTONE" or Packs.SETS[set]
  if not printedSet then return nil, "no such pack: " .. tostring(set) end

  local cards = {}
  --[[ THE GUARANTEED SLOT. Hearthstone's one rule worth keeping: a pack is
       never nothing. (Opening while rested once raised this floor to epic and
       paid 25 dust; removed 2026-09-26 so packs open as Hearthstone's do.) ]]
  local guaranteedIndex = Packs.Roll(rng, Packs.SIZE)

  for i = 1, Packs.SIZE do
    local floor = (i == guaranteedIndex) and "RARE" or nil
    local rarity = Packs.RollRarity(rng, floor)
    local id = Packs.RandomCard(rng, printedSet, rarity)
    --[[ Empty pool for that rarity: step down rather than produce a short pack.
         A four-card pack is a bug report; a common instead of an epic is a
         shrug. ]]
    if not id then
      for _, fallback in ipairs({ "RARE", "COMMON", "EPIC", "LEGENDARY" }) do
        id = Packs.RandomCard(rng, printedSet, fallback)
        if id then rarity = fallback break end
      end
    end
    if id then
      cards[#cards + 1] = {
        cardId = id, rarity = rarity,
        golden = Packs.Roll(rng, 100) <= Packs.GOLDEN_PCT,
      }
    end
  end

  local ORDER = { FREE = 0, COMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }
  local best, bestIndex = "COMMON", 1
  for i, c in ipairs(cards) do
    if (ORDER[c.rarity] or 0) > (ORDER[best] or 0) then best, bestIndex = c.rarity, i end
  end
  return {
    set = set, cards = cards,
    bestRarity = best,
    --[[ Which face-down card glows before it is flipped. In Hearthstone that
         anticipation is most of the pleasure -- the reveal itself is over in
         300ms -- so the tell points at the real card rather than a random one. ]]
    tellIndex = bestIndex,
  }
end

--[[ Open a banked pack: spend it, generate it, and put the cards in the
     collection.

     The contents are returned before anything animates, because the reveal is a
     presentation of a result that has already happened. Animating first and
     banking afterwards would mean a disconnect mid-reveal loses the pack. ]]
function Packs.Open(collection, set, opts)
  opts = opts or {}
  local ok, why = collection:TakePack(set)
  if not ok then return nil, why end

  local pack, err = Packs.Generate(set, opts)
  if not pack then
    collection:AddPack(set, 1)         -- put it back; nothing was opened
    return nil, err
  end

  for _, c in ipairs(pack.cards) do
    collection:Add(c.cardId, 1, c.golden)
    --[[ A COPY NO DECK CAN USE BECOMES DUST AS THE PACK OPENS -- the third
         common, the second legendary. Kept, it only sat in the collection
         waiting to be disenchanted by hand, and the reveal could not say
         clearly what you had got. A golden is never the one dusted while a
         plain copy can go instead: goldens are the drop-only chase. `dust`
         is what it became, for the reveal; `extra` still marks the card. ]]
    if collection:Count(c.cardId) > collection:MaxCopies(c.cardId) then
      c.extra = true
      local plain = collection:Owned(c.cardId)
      local golden = c.golden and plain <= 0
      local ok, gained = collection:Disenchant(c.cardId, golden)
      if ok then c.dust, c.dustedPlain = gained, c.golden and not golden end
    else
      c.extra = false
    end
  end

  return pack
end

-- ======================================================== mob card drops

--[[ A single card from the world, rather than a pack.

     `race` biases the card toward what you killed -- kill beasts, get a Beast
     card -- which is the "set trigger" from the brief expressed as data instead
     of a list of special cases. If that race has no neutral cards in the set,
     the bias simply does not apply rather than failing. ]]
function Packs.DropCard(rng, opts)
  opts = opts or {}
  local set = opts.set or Packs.SETS.CLASSIC
  local rarity = Packs.RollRarity(rng)
  local id = opts.race and Packs.RandomCard(rng, set, rarity, opts.race)
  if not id then id = Packs.RandomCard(rng, set, rarity) end
  if not id then return nil end
  return {
    cardId = id, rarity = rarity,
    golden = opts.golden or (Packs.Roll(rng, 100) <= Packs.GOLDEN_PCT),
  }
end

-- ================================================== collection triggers

--[[ OLD MURK-EYE. Its real Hearthstone condition is "collect every Murloc",
     which maps exactly onto this recreation (docs/03 D1) -- and note that it is
     a COLLECTION trigger, not a kill trigger, because murlocs in WoW are
     Humanoid and a kill trigger could never name them.

     Written as a table so the other three promo cards can join it when their
     rare-spawn drop tables exist. Each entry is a condition over the
     collection, checked after anything is added. ]]
Packs.COLLECTION_TRIGGERS = {
  {
    cardId = "EX1_062",                  -- Old Murk-Eye
    describe = "collect every Murloc",
    met = function(collection)
      for id, p in pairs(collection.printed) do
        if p.collectible and p.race == "MURLOC" and id ~= "EX1_062" then
          if collection:Count(id) == 0 then return false end
        end
      end
      return true
    end,
  },
}

--[[ Check every collection trigger and grant what has been earned. Returns the
     ids granted, so the caller can raise the (louder) set-card toast.

     Idempotent -- a trigger whose card you already hold grants nothing -- so
     this is safe to call after every single card that arrives. ]]
function Packs.CheckTriggers(collection)
  local granted = {}
  for _, t in ipairs(Packs.COLLECTION_TRIGGERS) do
    if collection:Count(t.cardId) == 0 and t.met(collection) then
      collection:Add(t.cardId, 1)
      granted[#granted + 1] = t.cardId
    end
  end
  return granted
end

return Packs
