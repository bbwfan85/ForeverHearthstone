--[[ Engine/CardPool.lua

  QUERIES OVER THE COLLECTIBLE CARD POOL.

  A dozen cards generate a card that was never in anyone's deck -- "a random
  Beast", "a random 2-Cost minion", "a random legendary minion", "a random
  weapon". They all need the same thing: the set of collectible cards matching
  a filter, in a fixed order, so that a seeded roll picks the same card on both
  clients.

  DETERMINISM IS THE WHOLE POINT OF THIS FILE.

  `ns.PrintedCards` is a hash table, and Lua's `pairs()` order is unspecified --
  it can differ between two runs of the SAME build, let alone between two
  machines. Feeding a pairs() walk to the RNG would desync lockstep immediately
  and intermittently, which is the worst kind of bug to find. So every query
  sorts by card id before anything random touches it, and the sorted result is
  cached, because the printed pool never changes at runtime.

  WHAT COUNTS AS "THE POOL"

  Hearthstone generates from COLLECTIBLE cards only: a random minion can be
  Chillwind Yeti but never a Panther token, even though tokens are minions in
  the same data file. `collectible` is printed data, so that falls out of the
  pin rather than being a list anyone maintains. Hero cards and hero powers are
  excluded for the same reason -- they are not collectible.
]]
local ADDON, ns = ...

local CardPool = {}
ns.CardPool = CardPool

-- filter signature -> sorted id list. The pool is immutable, so this never
-- needs invalidating.
local cache = {}

local function key(f)
  return table.concat({
    f.type or "", f.race or "", f.rarity or "",
    f.cost == nil and "" or tostring(f.cost),
    f.class or "",
  }, "|")
end

local function matches(p, f)
  if f.type   and p.type   ~= f.type   then return false end
  if f.race   and p.race   ~= f.race   then return false end
  if f.rarity and p.rarity ~= f.rarity then return false end
  if f.class  and p.class  ~= f.class  then return false end
  if f.cost   and (p.cost or 0) ~= f.cost then return false end
  return true
end

--[[ All collectible card ids matching `filter`, sorted by id.

     `filter` = { type=, race=, rarity=, cost=, class= }, all optional and
     ANDed. Returns a shared, cached table -- callers must NOT modify it. ]]
function CardPool.Query(filter)
  filter = filter or {}
  local k = key(filter)
  local hit = cache[k]
  if hit then return hit end

  local out = {}
  for id, p in pairs(ns.PrintedCards or {}) do
    --[[ Unobtainable promo/reward cards are collectible in the data but have no
         acquisition path in this recreation (see docs/04). They are still real
         Hearthstone cards and DO appear in Hearthstone's generation pools, so
         they stay in. ]]
    if p.collectible and matches(p, filter) then
      out[#out + 1] = id
    end
  end
  table.sort(out)          -- THE determinism guarantee; see the header
  cache[k] = out
  return out
end

--- One random matching card id, drawn from the game's seeded stream, or nil.
function CardPool.Random(game, filter)
  local ids = CardPool.Query(filter)
  if #ids == 0 then return nil end
  return ids[game:Random(#ids)]
end

--[[ N DISTINCT random matching ids. Neptulon adds four Murlocs and they may
     repeat in Hearthstone, so callers that want repeats call Random N times;
     this is for the cases that must not repeat. Returns fewer than n if the
     pool is smaller. ]]
function CardPool.RandomDistinct(game, filter, n)
  local ids = CardPool.Query(filter)
  local pool = {}
  for i, id in ipairs(ids) do pool[i] = id end
  local out = {}
  for _ = 1, math.min(n, #pool) do
    local i = game:Random(#pool)
    out[#out + 1] = pool[i]
    table.remove(pool, i)
  end
  return out
end

--- Size of a filtered pool. Used by tests to prove a filter is not empty.
function CardPool.Count(filter) return #CardPool.Query(filter) end

--- Drop the cache. Tests that stub PrintedCards need this; nothing else should.
function CardPool.ResetCache() cache = {} end

return CardPool
