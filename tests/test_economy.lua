--[[ tests/test_economy.lua -- does the drop economy hit its target? (docs/13)

  THE TARGET: a character that has levelled 1-60 and then farmed its pre-raid
  best-in-slot has "the cards it wants" -- most of the pack pool, a good share
  of the legendaries (the rest craftable), and most of Naxxramas -- without the
  collection being handed over.

  THE PROFILE, stated so it can be argued with: ~12,000 XP-granting normal
  kills and ~4,000 elites (open-world elites plus dungeon trash) on the way to
  and through 60, 300 dungeon boss kills of which ~45 are first kills, plus the
  starter and milestone packs. Extras are disenchanted and the dust crafts the
  cheapest missing cards first.

  Runs the REAL rules: Drops.Roll, Drops.Grant, Packs.Open and the Collection,
  seeded, over several characters, and asserts on the median.
]]
local H = require("tests.harness")

local function lcg(seed)
  local s = seed
  return function(n) s = (s * 1103515245 + 12345) % 2147483648; return math.floor(s / 2147483648 * n) + 1 end
end

local function character(ns, seed)
  local rng = lcg(seed)
  local c = ns.Collection.New({}, {}, {})
  c:GrantPacksForLevel(60)
  local function kills(kind, n, extra)
    for _ = 1, n do
      local k = { kind = kind, playerLevel = 40, grantsXP = true }
      if extra then for a, b in pairs(extra) do k[a] = b end end
      local r = ns.Drops.Roll(k, rng)
      if r then ns.Drops.Grant(c, r, rng) end
    end
  end
  kills("normal", 12000)
  kills("elite", 4000)
  kills("boss", 45, { guaranteed = true })
  kills("boss", 255)
  while c:TotalPacks() > 0 do ns.Packs.Open(c, "HEARTHSTONE", { rng = rng }) end
  -- disenchant extras, then craft the cheapest missing cards
  for id, rec in pairs(c.account.cards) do
    local max = c:MaxCopies(id)
    while (rec.n or 0) + (rec.g or 0) > max and c:CanDisenchant(id, (rec.n or 0) == 0) do
      if not c:Disenchant(id, (rec.n or 0) == 0) then break end
    end
  end
  local pool = ns.Packs.Pool("HEARTHSTONE")
  local missing = {}
  for _, id in ipairs(pool) do if not c:Has(id) then missing[#missing + 1] = id end end
  table.sort(missing, function(a, b)
    local ca, cb = c:DustValues(a).craft or 1e9, c:DustValues(b).craft or 1e9
    if ca ~= cb then return ca < cb end
    return a < b
  end)
  for _, id in ipairs(missing) do c:Craft(id) end
  local have, legend, legendTotal = 0, 0, 0
  for _, id in ipairs(pool) do
    if c:Has(id) then have = have + 1 end
    if ns.PrintedCards[id].rarity == "LEGENDARY" then
      legendTotal = legendTotal + 1
      if c:Has(id) then legend = legend + 1 end
    end
  end
  local naxx, naxxHave = ns.Packs.Pool("NAXX"), 0
  for _, id in ipairs(naxx) do if c:Has(id) then naxxHave = naxxHave + 1 end end
  return have / #pool, legend / legendTotal, naxxHave / #naxx
end

H.suite("economy: level 60 with pre-raid gear farmed has the cards it wants", function(ns, H)
  local a, b, n = {}, {}, {}
  for i = 1, 7 do
    local x, y, z = character(ns, i * 7919)
    a[#a + 1], b[#b + 1], n[#n + 1] = x, y, z
  end
  local function median(t) table.sort(t); return t[math.ceil(#t / 2)] end
  local distinct, legend, naxx = median(a), median(b), median(n)
  H.ok(distinct >= 0.90, ("%.0f%% of the pack pool owned (want >= 90%%)"):format(distinct * 100))
  H.ok(distinct < 1.0 or legend < 1.0, "but the collection is not simply handed over")
  H.ok(legend >= 0.60, ("%.0f%% of its legendaries (want >= 60%%)"):format(legend * 100))
  H.ok(naxx >= 0.80, ("%.0f%% of Naxxramas (want >= 80%%)"):format(naxx * 100))
end)

H.suite("economy: a new character is started with packs, and milestones pay once", function(ns, H)
  local c = ns.Collection.New({}, {}, {})
  H.eq(c:GrantPacksForLevel(1), 3, "three packs to begin with")
  H.eq(c:GrantPacksForLevel(1), 0, "and not again")
  H.eq(c:GrantPacksForLevel(25), 2, "levels 10 and 20 each pay one")
  H.eq(c:GrantPacksForLevel(60), 11, "30, 40, 50 pay two each and 60 pays five")
  H.eq(c:GrantPacksForLevel(60), 0, "never twice")
  H.eq(c:TotalPacks(), 16)
end)

H.suite("economy: nothing can be farmed that should not be", function(ns, H)
  local E = ns.Drops.Eligible
  H.notOk(E({ kind = "normal", classification = "minus", playerLevel = 20, grantsXP = true }),
          "a critter in any language: the client marks it 'minus'")
  H.notOk(E({ kind = "normal", creatureType = "Critter", playerLevel = 20, grantsXP = true }), "a Critter")
  H.notOk(E({ kind = "normal", playerLevel = 30, grantsXP = false }), "a grey mob gives nothing below 60")
  H.notOk(E({ kind = "normal", summoned = true, playerLevel = 30, grantsXP = true }), "your own pet or totem")
  H.notOk(E({ kind = "normal", playerLevel = 60, mobLevel = 12 }), "a level 60 in Westfall")
  H.ok(E({ kind = "elite", playerLevel = 60, mobLevel = -1 }), "a skull-level boss at 60 does pay")
  H.ok(E({ kind = "normal", playerLevel = 60, mobLevel = 58 }), "and so does level-appropriate endgame play")
  local rng = lcg(5)
  for _ = 1, 50 do
    local r = ns.Drops.Roll({ kind = "boss", guaranteed = true, playerLevel = 30, grantsXP = true }, rng)
    H.ok(r and r.kind == "PACK" and r.set == "HEARTHSTONE", "a first boss kill always grants a pack")
  end
end)

--============================================================ docs/28

H.suite("economy: a boss card is never one you already have enough of", function(ns, H)
  --[[ Naxxramas comes only from bosses, and a spare from a boss was a wasted
       kill: the old single re-roll left the sixth legendary taking several
       times as many kills as the first. Every boss card is now one you can
       use, so the 21 cards (36 copies) take exactly 36 boss cards. ]]
  local rng = lcg(31)
  local c = ns.Collection.New({}, {}, {})
  local naxx = ns.Packs.Pool("NAXX")
  local copies = 0
  for _, id in ipairs(naxx) do copies = copies + c:MaxCopies(id) end
  H.eq(copies, 36, "a full Naxxramas set is 36 copies")
  for i = 1, copies do
    local card = ns.Drops.BossCard(rng, c)
    H.ok(card and c:Count(card.cardId) < c:MaxCopies(card.cardId), "boss card " .. i .. " is one you can use")
    if card then c:Add(card.cardId, 1, false) end
  end
  for _, id in ipairs(naxx) do H.eq(c:Count(id), c:MaxCopies(id), id .. " is complete") end
  H.eq(ns.Drops.BossCard(rng, c), nil, "and a complete set has nothing left to give")
end)

H.suite("economy: a boss after Naxxramas is complete pays a pack", function(ns, H)
  local rng = lcg(9)
  local c = ns.Collection.New({}, {}, {})
  for _, id in ipairs(ns.Packs.Pool("NAXX")) do c:Add(id, c:MaxCopies(id), false) end
  local before = c:TotalPacks()
  local got = ns.Drops.Grant(c, { kind = "CARD", set = "NAXX", boss = true }, rng)
  H.eq(got and got.kind, "PACK", "a pack instead of a spare")
  H.eq(c:TotalPacks(), before + 1, "and it is banked")
end)

H.suite("economy: bad luck has a floor, and the floor is not a faucet", function(ns, H)
  local rng = lcg(77)
  local dry, drops, longest, run = 0, 0, 0, 0
  local N = 60000
  for _ = 1, N do
    local k = { kind = "normal", playerLevel = 30, grantsXP = true }
    if ns.Drops.Owed(k, dry) then k.guaranteed = true end
    local r = ns.Drops.Roll(k, rng)
    dry = ns.Drops.AfterKill(k, dry, r)
    if r then drops = drops + 1; run = 0 else run = run + 1; longest = math.max(longest, run) end
  end
  H.ok(longest <= 150, ("never more than 150 kills without a drop (longest %d)"):format(longest))
  local per = N / drops
  H.ok(per > 50 and per < 64, ("still about one drop per %.0f kills"):format(per))
  H.eq(ns.Drops.AfterKill({ kind = "normal", playerLevel = 30, grantsXP = false }, 10, nil), 10,
       "a kill that could never pay does not count toward it")
  H.notOk(ns.Drops.Owed({ kind = "boss", playerLevel = 30, grantsXP = true }, 1e9),
          "bosses have their own rules")
end)
