--[[ Client/Collection.lua

  WHAT YOU OWN, AND WHAT YOU MAY BUILD WITH IT.

  NO WoW API. Pure model over two plain tables, which ARE the SavedVariables
  shape -- there is no separate serialisation step, because a serialisation step
  is a second representation of the same thing and the two drift. Client/Main
  hands this the saved tables at login and never copies anything.

  ============================================ THE DECISIONS THIS ENCODES

  From docs/03, all settled with the user:

  * THE BASIC SET IS GRANTED, NOT COLLECTED (D0). 43 neutral Basic cards at
    once, plus all ten class Basic cards at creation. They form the starting
    collection and are excluded from later level rewards.
  * CLASS CARDS COME FROM LEVELLING, PACKS ARE NEUTRAL-ONLY (D4). All 34 class
    cards by level 60: 10 Basic at creation, 15 Classic (3-31), 9 Naxx+GvG (36-60).
  * DUST IS CLASSIC-AND-LATER ONLY (D3). Basic cards are never crafted, because
    you already own all of them. A Basic duplicate still disenchants rather than
    vanishing -- "silently destroyed" is the kind of thing players resent.
  * ACCOUNT-WIDE NEUTRALS, PER-CHARACTER CLASS CARDS (D5). A WoW character is
    one class forever, so per-character neutrals would make every alt re-grind
    the same 153 cards. The dust pool follows the neutrals or it would be
    trapped on one character.

  ============================================ ONE RECORD PER CARD

      collection[cardId] = { n = <normal copies>, g = <golden copies> }

  Golden is a COPY OF THE SAME CARD, not a different card: it counts against the
  two-copy deck limit exactly as a normal copy does, and a deck may mix them.
  Storing goldens as a separate id would double the collection's size and make
  every ownership check ask the question twice.

  EXTRA COPIES ARE KEPT, not destroyed. Hearthstone lets you hold a third
  Chillwind Yeti and disenchant it when you feel like it; destroying it on
  arrival would make a drop silently worth nothing. (A PACK is the exception:
  its surplus copy disenchants as it opens and the reveal shows the dust --
  Packs.Open.)
]]
local ADDON, ns = ...

local Collection = {}
Collection.__index = Collection
ns.Collection = Collection

--[[ Hearthstone's own dust values, from the pinned data (`dustHS` on every
     Classic-and-later card). Deviation 7 permits retuning these; nothing has
     been retuned yet, so the multiplier is 1 and changing the economy is a
     one-line data change rather than a hunt through the code. ]]
Collection.DUST_SCALE = 1

--[[ The fallback for a card with no printed dust array -- which is every Basic
     card, because in Hearthstone they can be neither crafted nor disenchanted.
     Only the DISENCHANT side is ever used (D3: a Basic duplicate still dusts);
     crafting a Basic is refused outright, since you already own them all. ]]
local FALLBACK_DUST = {
  FREE      = { craft = nil, craftGolden = nil, de = 5,   deGolden = 50 },
  COMMON    = { craft = nil, craftGolden = nil, de = 5,   deGolden = 50 },
}

-- ========================================================= construction

--[[ `account` and `character` are the two SavedVariables tables, mutated in
     place. Missing sub-tables are created, so a fresh install and an upgrade
     take the same path -- there is no "first run" branch to get wrong. ]]
function Collection.New(account, character, opts)
  opts = opts or {}
  local c = setmetatable({}, Collection)
  c.account   = account or {}
  c.character = character or {}
  c.printed   = opts.printed or ns.PrintedCards or {}

  local a = c.account
  a.cards   = a.cards or {}        -- neutrals: account-wide (D5)
  a.dust    = a.dust or 0
  a.packs   = a.packs or {}
  -- Consolidate legacy unopened packs once; clearing the old keys makes reloads safe.
  a.packs.HEARTHSTONE = (a.packs.HEARTHSTONE or 0) + (a.packs.CLASSIC or 0) + (a.packs.GVG or 0)
  a.packs.CLASSIC, a.packs.GVG = nil, nil
  a.stats   = a.stats or { packsOpened = 0, cardsDropped = 0, dusted = 0, crafted = 0 }

  local ch = c.character
  ch.cards  = ch.cards or {}       -- class cards: per character (D5)
  ch.decks  = ch.decks or {}
  ch.level  = ch.level or 1
  ch.history = ch.history or {}
  return c
end

--[[ Which table a card lives in. Asked of the PRINTED class rather than of
     where the card happens to be stored, so a card can never end up in both:
     neutrals are account-wide and class cards are not, and that is a property
     of the card, not of how it arrived. ]]
function Collection:Store(cardId)
  local p = self.printed[cardId]
  if p and p.class and p.class ~= "NEUTRAL" then return self.character.cards end
  return self.account.cards
end

-- ============================================================ ownership

--- Copies owned: normal, golden. Both zero for a card never seen.
function Collection:Owned(cardId)
  local rec = self:Store(cardId)[cardId]
  if not rec then return 0, 0 end
  return rec.n or 0, rec.g or 0
end

--- Total copies, golden included -- the number the deck limit is measured against.
function Collection:Count(cardId)
  local n, g = self:Owned(cardId)
  return n + g
end

function Collection:Has(cardId) return self:Count(cardId) > 0 end

--[[ The most copies of this card a legal deck may hold. Legendaries are one;
     everything else is two. Printed data decides, so it cannot drift. ]]
function Collection:MaxCopies(cardId)
  local p = self.printed[cardId]
  if p and p.rarity == "LEGENDARY" then return ns.RULES.MAX_COPIES_LEG end
  return ns.RULES.MAX_COPIES
end

--[[ Add copies. Returns the record, so a caller can show what it got.

     `golden` adds golden copies instead of normal ones. Nothing is refused
     here -- an extra copy beyond the deck limit is still yours, and is worth
     dust. ]]
function Collection:Add(cardId, n, golden)
  n = n or 1
  if n <= 0 then return nil, "nothing to add" end
  if not self.printed[cardId] then return nil, "no such card: " .. tostring(cardId) end
  local store = self:Store(cardId)
  local rec = store[cardId]
  if not rec then rec = { n = 0, g = 0 }; store[cardId] = rec end
  if golden then rec.g = (rec.g or 0) + n else rec.n = (rec.n or 0) + n end
  return rec
end

--[[ Remove copies, normal first unless `golden` is given.

     NORMAL FIRST is deliberate: disenchanting a duplicate should never quietly
     eat the golden one, which is the drop-only chase version and worth far more
     to the player than to the dust pool. ]]
function Collection:Remove(cardId, n, golden)
  n = n or 1
  local store = self:Store(cardId)
  local rec = store[cardId]
  if not rec then return false, "you do not own that" end
  if golden then
    if (rec.g or 0) < n then return false, "you do not own that many golden copies" end
    rec.g = rec.g - n
  else
    if (rec.n or 0) < n then return false, "you do not own that many" end
    rec.n = rec.n - n
  end
  if (rec.n or 0) <= 0 and (rec.g or 0) <= 0 then store[cardId] = nil end
  return true
end

-- ================================================================= dust

--[[ Dust values for a card: craft, craftGolden, disenchant, disenchantGolden.

     Read from the printed data, never from a table in this file. A card whose
     printed data carries no dust array is Basic, and Basic cannot be crafted --
     so `craft` is nil and the disenchant value falls back, which is the D3
     safety valve rather than an income source. ]]
function Collection:DustValues(cardId)
  local p = self.printed[cardId]
  if not p then return nil end
  local s = Collection.DUST_SCALE
  local d = p.dustHS
  if d then
    return { craft = d[1] * s, craftGolden = d[2] * s,
             de = d[3] * s, deGolden = d[4] * s, craftable = true }
  end
  local f = FALLBACK_DUST[p.rarity] or FALLBACK_DUST.COMMON
  return { craft = nil, craftGolden = nil,
           de = f.de * s, deGolden = f.deGolden * s, craftable = false }
end

function Collection:Dust() return self.account.dust or 0 end

--[[ Craft a card. Goldens are NOT craftable -- deviation 3 makes them drop-only,
     which is what keeps them a chase rather than a purchase. ]]
function Collection:Craft(cardId)
  local v = self:DustValues(cardId)
  if not v then return false, "no such card" end
  if not v.craftable then
    return false, "Basic cards are granted, not crafted -- you already own them"
  end
  local p = self.printed[cardId]
  if p.class ~= "NEUTRAL" and p.class ~= self.character.class then
    return false, "that is another class's card"
  end
  if self:Count(cardId) >= self:MaxCopies(cardId) then
    return false, "you already have the most copies a deck can hold"
  end
  if self:Dust() < v.craft then
    return false, ("not enough dust: %d of %d"):format(self:Dust(), v.craft)
  end
  self.account.dust = self:Dust() - v.craft
  self:Add(cardId, 1)
  self.account.stats.crafted = (self.account.stats.crafted or 0) + 1
  return true, v.craft
end

--[[ Disenchant one copy. Golden copies are worth far more and are never taken
     unless asked for by name. ]]
function Collection:Disenchant(cardId, golden)
  local allowed, reason = self:CanDisenchant(cardId, golden)
  if not allowed then return false, reason end
  local v = self:DustValues(cardId)
  if not v then return false, "no such card" end
  local ok, why = self:Remove(cardId, 1, golden)
  if not ok then return false, why end
  local gained = golden and v.deGolden or v.de
  self.account.dust = self:Dust() + gained
  self.account.stats.dusted = (self.account.stats.dusted or 0) + 1
  return true, gained
end

--[[ Copies that no deck could ever use -- the third Yeti, the second copy of a
     legendary. This is what a "disenchant extras" button acts on, and it never
     touches a golden unless the normal copies alone already exceed the limit. ]]
function Collection:CanDisenchant(cardId, golden)
  local p = self.printed[cardId]
  if not p or not p.collectible then return false, "no such collectible card" end
  local normal, gold = self:Owned(cardId)
  if (golden and gold or normal) <= 0 then return false, "you do not own that copy" end
  if not golden and p.set == "CORE" then
    return false, "Basic cards are granted free and cannot be disenchanted"
  end
  if not golden and p.class == self.character.class then
    local basic, classic, late = Collection.GrantsAtLevel(self.character.level or 1)
    local remaining = { BASIC = basic, CLASSIC = classic, LATE = late }
    for _, entry in ipairs(self:ClassCurve(p.class)) do
      remaining[entry.band] = remaining[entry.band] - 1
      if entry.id == cardId and remaining[entry.band] >= 0 and normal <= self:MaxCopies(cardId) then
        return false, "Keep your free level-granted copies; only extra copies can be disenchanted"
      end
    end
  end
  return true
end

function Collection:Extras()
  local out = {}
  local function scan(store)
    for id, rec in pairs(store) do
      local max = self:MaxCopies(id)
      local total = (rec.n or 0) + (rec.g or 0)
      if total > max then
        --[[ Spend normals first: the golden copy is the one worth keeping, and
             a player who disenchants "extras" does not mean the golden one. ]]
        local surplus = total - max
        local fromNormal = math.min(surplus, rec.n or 0)
        out[#out + 1] = { cardId = id, normal = fromNormal,
                          golden = surplus - fromNormal }
      end
    end
  end
  scan(self.account.cards)
  scan(self.character.cards)
  table.sort(out, function(a, b) return a.cardId < b.cardId end)
  return out
end

-- ============================================================== packs

local function packKey(set)
  if set == "CLASSIC" or set == "GVG" then return "HEARTHSTONE" end
  return set
end
function Collection:PackCount(set) return (self.account.packs[packKey(set)] or 0) end

function Collection:AddPack(set, n)
  set = packKey(set)
  self.account.packs[set] = self:PackCount(set) + (n or 1)
  return self.account.packs[set]
end

function Collection:TakePack(set)
  set = packKey(set)
  local have = self:PackCount(set)
  if have <= 0 then return false, "you have no " .. tostring(set) .. " packs" end
  self.account.packs[set] = have - 1
  self.account.stats.packsOpened = (self.account.stats.packsOpened or 0) + 1
  return true
end

function Collection:TotalPacks()
  local n = 0
  for _, count in pairs(self.account.packs) do n = n + count end
  return n
end

-- =========================================================== progression

--[[ The card-grant curve (docs/03 D4 and docs/04).

       level  1      43 neutral Basic, granted outright
       level  1      all 10 class Basic cards, part of the starting collection
       3-31   15 class Classic cards, one every two levels
       36-60  9 class Naxx + GvG cards, one every three levels

     Two copies of each, which is what Hearthstone grants and what makes the
     starter deck buildable immediately. No Basic card is legendary, so this can
     never produce an illegal collection. ]]
local function twoCopies(col, ids)
  local granted = {}
  for _, id in ipairs(ids) do
    local want = col:MaxCopies(id)
    local have = col:Count(id)
    if have < want then
      col:Add(id, want - have)
      granted[#granted + 1] = id
    end
  end
  return granted
end

--[[ Every collectible id in a set for a class, sorted. Sorted because the grant
     order must be the same on every character and every machine -- pairs() order
     is unspecified, and a curve that differs between two characters of the same
     class is a bug nobody would ever reproduce. ]]
function Collection:IdsIn(set, class)
  local out = {}
  for id, p in pairs(self.printed) do
    if p.collectible and p.set == set and p.class == class and p.type ~= "HERO" then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

--[[ THE ORDER CLASS CARDS ARRIVE IN.

     docs/03 D4 asks for an ordering by DECK UTILITY rather than rarity or cost,
     so a level-20 character has its core removal and not only vanilla minions,
     with the class legendaries landing in the 30-40 band. That table is authored
     data the user still owes us (it is on the open-decisions list), so this is
     the placeholder: commons and rares first, epics next, legendaries last, and
     cheap before expensive within each band.

     It is a reasonable approximation -- class legendaries do land late and cheap
     removal does land early -- and it is ONE function, so replacing it with the
     authored table later is a data change and nothing else moves. ]]
local RARITY_ORDER = { FREE = 1, COMMON = 2, RARE = 3, EPIC = 4, LEGENDARY = 5 }

function Collection:UtilityOrder(ids)
  local out = {}
  for i, id in ipairs(ids) do out[i] = id end
  table.sort(out, function(a, b)
    local pa, pb = self.printed[a], self.printed[b]
    local ra = RARITY_ORDER[pa.rarity] or 9
    local rb = RARITY_ORDER[pb.rarity] or 9
    if ra ~= rb then return ra < rb end
    if (pa.cost or 0) ~= (pb.cost or 0) then return (pa.cost or 0) < (pb.cost or 0) end
    return a < b      -- ids last, so the order is total and deterministic
  end)
  return out
end

--[[ The full ordered list of class cards for a class: Basic, then Classic, then
     Naxx and GvG. Cached per class because it is pure printed data. ]]
local curveCache = {}
function Collection:ClassCurve(class)
  if curveCache[class] then return curveCache[class] end
  local basic = self:IdsIn("CORE", class)          -- printed order is fine: all free
  table.sort(basic)
  local classic = self:UtilityOrder(self:IdsIn("EXPERT1", class))
  local late = {}
  for _, id in ipairs(self:IdsIn("NAXX", class)) do late[#late + 1] = id end
  for _, id in ipairs(self:IdsIn("GVG", class)) do late[#late + 1] = id end
  late = self:UtilityOrder(late)

  local curve = {}
  for _, id in ipairs(basic)   do curve[#curve + 1] = { id = id, band = "BASIC" } end
  for _, id in ipairs(classic) do curve[#curve + 1] = { id = id, band = "CLASSIC" } end
  for _, id in ipairs(late)    do curve[#curve + 1] = { id = id, band = "LATE" } end
  curveCache[class] = curve
  return curve
end

--- Drop the curve cache. Tests that stub the printed pool need this.
function Collection.ResetCurveCache() curveCache = {} end

--[[ How many class cards a character of this level should have.
     Revised progression: all Basics at creation, Classic at 3,5,...31,
     then Naxx/GvG at 36,39,...60. Existing ownership is never removed.

     Expressed as a function of level rather than a table of levels, so the
     three bands stay visibly the three bands from the design doc. A character
     that levelled past a grant while the addon was uninstalled gets everything
     it is owed the next time this runs -- grants are a FUNCTION of level, never
     an event, which is the only version that cannot lose a card. ]]
function Collection.GrantsAtLevel(level)
  level = math.max(1, math.min(60, level or 1))
  -- Basics are the starting collection, never later level rewards.
  local basic = 10
  local classic = math.min(15, math.max(0, math.floor((level-1)/2)))
  local late = math.min(9, math.max(0, math.floor((level-33)/3)))
  return basic, classic, late
end

--[[ Bring a character's class cards up to date for its level, and grant the
     neutral Basic set if it has not been granted.

     Returns the list of newly granted card ids, which is what the level-up
     toast shows. Idempotent: calling it twice grants nothing the second time,
     so it is safe to run on every login, and that is how a character that
     levelled with the addon disabled catches up. ]]
function Collection:GrantForLevel(class, level)
  self.character.class = class or self.character.class
  --[[ The level WoW reports, not the saved one: the saved number is a line in a
       text file, and trusting the larger of the two let an edit to "60" grant
       every class card. Grants are idempotent, so nothing is taken back. ]]
  self.character.level = level or self.character.level or 1
  class = self.character.class
  local granted = {}

  --[[ The 43 neutral Basic cards, granted once and account-wide. This is the
       whole of D0: Hearthstone's starter deck is simply "you own the Basic
       set", which is why those cards have no dust value. ]]
  do
    local ids = {}
    for id, p in pairs(self.printed) do
      if p.collectible and p.set == "CORE" and p.class == "NEUTRAL" and p.type ~= "HERO" then
        ids[#ids + 1] = id
      end
    end
    table.sort(ids)
    for _, id in ipairs(twoCopies(self, ids)) do granted[#granted + 1] = id end
    self.account.basicsGranted = true
  end

  if not class then return granted end
  local nBasic, nClassic, nLate = Collection.GrantsAtLevel(self.character.level)
  local curve = self:ClassCurve(class)
  local counts = { BASIC = nBasic, CLASSIC = nClassic, LATE = nLate }
  local seen = { BASIC = 0, CLASSIC = 0, LATE = 0 }
  local want = {}
  for _, entry in ipairs(curve) do
    seen[entry.band] = seen[entry.band] + 1
    if seen[entry.band] <= (counts[entry.band] or 0) then want[#want + 1] = entry.id end
  end
  for _, id in ipairs(twoCopies(self, want)) do granted[#granted + 1] = id end
  return granted
end

-- ================================================================ decks

--[[ Deck validation, in one place, for the same reason actions are applied in
     one place: the deck builder greys out an illegal card, and the duel must
     refuse it too. If those are two pieces of code, one of them is wrong.

     Rules, all Hearthstone's:
       * exactly 30 cards
       * at most two copies of a card, one of a legendary
       * no other class's cards
       * and OURS: you must own the copies you are using ]]
--[[ GUARANTEED PACKS (docs/13). A new character opens with three, and the
     level milestones add more -- the steady drip that complements the 1.5%
     mob drops, so a character is never wholly at the mercy of the roll. Like
     class cards these are a FUNCTION of level: a character that reached a
     milestone with the addon disabled gets it at next login, and nothing is
     ever granted twice (character.packMilestones). ]]
Collection.PACK_MILESTONES = {
  { level = 1,  packs = 3, why = "a new character" },
  { level = 10, packs = 1 }, { level = 20, packs = 1 }, { level = 30, packs = 2 },
  { level = 40, packs = 2 }, { level = 50, packs = 2 }, { level = 60, packs = 5 },
}

-- The same curve and milestones that grant rewards drive the visual track.
function Collection:LevelRewardTrack(class)
  local track, previous = {}, { BASIC=10, CLASSIC=0, LATE=0 }
  local curve = self:ClassCurve(class or self.character.class)
  for level=1,60 do
    local row={level=level,starter=level==1,rewards={}}
    for _,m in ipairs(Collection.PACK_MILESTONES) do
      if m.level==level then row.rewards[#row.rewards+1]={kind="PACK",count=m.packs} end
    end
    local b,c,l=Collection.GrantsAtLevel(level)
    local after,seen={BASIC=b,CLASSIC=c,LATE=l},{BASIC=0,CLASSIC=0,LATE=0}
    for _,entry in ipairs(curve) do
      seen[entry.band]=seen[entry.band]+1
      if seen[entry.band]>previous[entry.band] and seen[entry.band]<=after[entry.band] then
        row.rewards[#row.rewards+1]={kind="CARD",cardId=entry.id,
          count=self.printed[entry.id].rarity=="LEGENDARY" and 1 or 2}
      end
    end
    previous=after; track[level]=row
  end
  return track
end

--- Returns the number of packs granted and a list of { level, packs, why }.
function Collection:GrantPacksForLevel(level)
  level = level or self.character.level or 1
  local ch = self.character
  ch.packMilestones = ch.packMilestones or {}
  local total, list = 0, {}
  for _, m in ipairs(Collection.PACK_MILESTONES) do
    if level >= m.level and not ch.packMilestones[m.level] then
      ch.packMilestones[m.level] = true
      self:AddPack(ns.Packs.SETS.HEARTHSTONE, m.packs)
      total = total + m.packs
      list[#list + 1] = { level = m.level, packs = m.packs, why = m.why }
    end
  end
  return total, list
end

function Collection:ValidateDeck(deck, class)
  class = class or (deck and deck.class) or self.character.class
  local cards = (deck and deck.cards) or deck or {}
  local errors = {}
  local counts = {}

  for _, id in ipairs(cards) do
    local p = self.printed[id]
    if not p then
      errors[#errors + 1] = "unknown card: " .. tostring(id)
    else
      counts[id] = (counts[id] or 0) + 1
      if p.class ~= "NEUTRAL" and p.class ~= class then
        errors[#errors + 1] = ("%s is a %s card"):format(p.name, tostring(p.class))
      end
    end
  end
  for id, n in pairs(counts) do
    local p = self.printed[id]
    local max = self:MaxCopies(id)
    if n > max then
      errors[#errors + 1] = ("too many copies of %s (%d, limit %d)"):format(p.name, n, max)
    end
    local owned = self:Count(id)
    if n > owned then
      errors[#errors + 1] = ("you own %d of %s, not %d"):format(owned, p.name, n)
    end
  end
  if #cards ~= ns.RULES.DECK_SIZE then
    errors[#errors + 1] = ("%d cards, needs %d"):format(#cards, ns.RULES.DECK_SIZE)
  end
  return #errors == 0, errors
end

--[[ May one more copy of this card go into this deck? The deck builder asks
     this per card to decide what to grey out, so it answers WHY rather than
     just no -- "you own 1" and "legendary" are different messages and the
     player needs the right one. ]]
function Collection:CanAdd(deck, cardId)
  local p = self.printed[cardId]
  if not p then return false, "unknown card" end
  local class = deck.class or self.character.class
  if p.class ~= "NEUTRAL" and p.class ~= class then return false, "another class" end
  local used = 0
  for _, id in ipairs(deck.cards or {}) do if id == cardId then used = used + 1 end end
  if #(deck.cards or {}) >= ns.RULES.DECK_SIZE then return false, "deck is full" end
  local max = self:MaxCopies(cardId)
  if used >= max then
    return false, (max == 1) and "only one copy of a legendary" or "limit two copies"
  end
  if used >= self:Count(cardId) then return false, "you do not own another copy" end
  return true
end

-- Install the starter once without changing existing decks or the active choice.
-- All Basic class cards belong to the starting collection; use owned copies only.
function Collection:EnsureDefaultDeck(class)
  if self.character.defaultDeckAdded then return end
  local cards,counts={},{}
  local function add(id)
    if #cards>=ns.RULES.DECK_SIZE then return end
    if (counts[id] or 0)>=math.min(self:Count(id),self:MaxCopies(id)) then return end
    cards[#cards+1]=id; counts[id]=(counts[id] or 0)+1
  end
  for _,id in ipairs(ns.Controller.BasicDeck(class)) do add(id) end
  local ids={}
  for id,p in pairs(self.printed) do
    if p.collectible and p.set=="CORE" and p.type~="HERO" and (p.class==class or p.class=="NEUTRAL") then ids[#ids+1]=id end
  end
  table.sort(ids)
  for _,id in ipairs(ids) do add(id); add(id) end
  local deck={name="Default "..class:sub(1,1)..class:sub(2):lower(),class=class,cards=cards}
  if not self:ValidateDeck(deck) then return end
  self.character.decks[#self.character.decks+1]=deck
  self.character.defaultDeckAdded=true
  if not self.character.activeDeck then self.character.activeDeck=#self.character.decks end
  return deck
end

function Collection:NewDeck(name, class)
  local deck = { name = name or "New Deck",
                 class = class or self.character.class, cards = {} }
  self.character.decks[#self.character.decks + 1] = deck
  return deck, #self.character.decks
end

function Collection:DeleteDeck(index)
  if not self.character.decks[index] then return false, "no such deck" end
  table.remove(self.character.decks, index)
  if self.character.activeDeck == index then self.character.activeDeck = nil
  elseif self.character.activeDeck and self.character.activeDeck > index then
    self.character.activeDeck = self.character.activeDeck - 1
  end
  return true
end

--[[ The deck this character duels with: the chosen one if it is still legal,
     otherwise nil so the caller can fall back. A deck can become illegal after
     it was built -- a card disenchanted out from under it -- and discovering
     that at the start of a duel is much worse than discovering it here. ]]
function Collection:ActiveDeck()
  local idx = self.character.activeDeck
  local deck = idx and self.character.decks[idx]
  if not deck then return nil end
  local ok = self:ValidateDeck(deck)
  if not ok then return nil, deck end
  return deck
end

-- =============================================================== browsing

--[[ THE LIST THE COLLECTION SCREEN DRAWS.

     Pure, so the question "what does the Mage filter show at 3 mana" is
     answerable in a test rather than by scrolling. Returns entries carrying
     everything a card slot needs, so the binding does no lookups of its own:

       { cardId, printed, owned, golden, max, extra, craftable, canCraft }

     SORT ORDER IS HEARTHSTONE'S: by mana cost, then by name. Every player who
     has used the real collection expects the 2-drops together, and any other
     order makes deck building slower for no gain. ]]
function Collection:Browse(filter)
  filter = filter or {}
  local out = {}
  for id, p in pairs(self.printed) do
    if p.collectible and p.type ~= "HERO" then
      local owned, golden = self:Owned(id)
      local keep = true
      --[[ "Owned" is the DEFAULT view, as in Hearthstone: the collection is
           what you have. Everything else is browsing the set, which is what the
           crafting view wants. ]]
      if filter.ownedOnly ~= false and not filter.all then
        keep = (owned + golden) > 0
      end
      if keep and filter.class then
        keep = (p.class == filter.class) or (filter.class == "NEUTRAL" and p.class == "NEUTRAL")
      end
      if keep and filter.playable then
        --[[ The deck-builder view: this class's cards and neutrals, nothing
             else, because nothing else can go in the deck. ]]
        keep = (p.class == filter.playable) or (p.class == "NEUTRAL")
      end
      if keep and filter.cost then
        keep = (filter.cost >= 7) and ((p.cost or 0) >= 7) or ((p.cost or 0) == filter.cost)
      end
      if keep and filter.set then keep = p.set == filter.set end
      if keep and filter.rarity then keep = p.rarity == filter.rarity end
      if keep and filter.text and filter.text ~= "" then
        local needle = filter.text:lower()
        keep = (p.name and p.name:lower():find(needle, 1, true) ~= nil)
            or (p.text and p.text:gsub("<[^>]+>", ""):lower():find(needle, 1, true) ~= nil)
      end
      if keep and filter.golden then keep = golden > 0 end

      if keep then
        local v = self:DustValues(id)
        out[#out + 1] = {
          cardId = id, printed = p,
          owned = owned, golden = golden,
          max = self:MaxCopies(id),
          extra = (owned + golden) > self:MaxCopies(id),
          craftable = v and v.craftable or false,
          craftCost = v and v.craft or nil,
          canCraft = (v and v.craftable and v.craft <= self:Dust()
                      and (owned + golden) < self:MaxCopies(id)
                      and (p.class == "NEUTRAL" or p.class == self.character.class)) or false,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    local ca, cb = a.printed.cost or 0, b.printed.cost or 0
    if ca ~= cb then return ca < cb end
    local na, nb = a.printed.name or a.cardId, b.printed.name or b.cardId
    if na ~= nb then return na < nb end
    return a.cardId < b.cardId          -- total order: two cards share a name
  end)
  return out
end

-- ============================================================= reporting

--[[ Completion, for the collection screen's header. Counts DISTINCT cards, not
     copies, because "412 of 531" is the number a collector thinks in. ]]
function Collection:Progress(filter)
  local total, owned, golden = 0, 0, 0
  for id, p in pairs(self.printed) do
    if p.collectible and p.type ~= "HERO" and (not filter or filter(p)) then
      total = total + 1
      local n, g = self:Owned(id)
      if n + g > 0 then owned = owned + 1 end
      if g > 0 then golden = golden + 1 end
    end
  end
  return owned, total, golden
end

return Collection
