--[[ Client/DeckCode.lua

  HEARTHSTONE DECK CODES: import and export.

  The format is Hearthstone's own ("deckstrings", hearthsim.info/docs/
  deckstrings): base64 of a run of unsigned varints --

      0x00            reserved
      1               version
      format          1 Wild, 2 Standard (we write Wild: these are Legacy cards)
      heroes          count, then hero DBF ids (one)
      single copies   count, then DBF ids, ascending
      two copies      count, then DBF ids, ascending
      n copies        count, then (DBF id, n) pairs

  so a code from this addon pastes straight into Hearthstone, and a code from
  Hearthstone (or any deck site) pastes in here. The text Hearthstone copies
  around the code is accepted too: lines starting with # are ignored, except
  that "### Name" names the deck.

  Cards are named by DBF id (Data/DbfIds.lua, tools/import_dbf_ids.py).
  Today's Hearthstone reprinted these cards under new ids (Core, the Classic
  format); a reprint with the same name and class imports as the 2014 card.
  Anything else -- a card from a later set -- is listed by DBF id as not in
  this game.

  No WoW API (no bit library either: plain arithmetic), so it runs headless.
]]
local ADDON, ns = ...

local DeckCode = {}
ns.DeckCode = DeckCode

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_URL = { ["-"] = 62, ["_"] = 63 }   -- some sites use the URL alphabet
local DECODE = {}
for i = 1, 64 do DECODE[B64:sub(i, i)] = i - 1 end
for k, v in pairs(B64_URL) do DECODE[k] = v end

local function b64encode(bytes)
  local out = {}
  for i = 1, #bytes, 3 do
    local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1 = math.floor(n / 262144) % 64
    local c2 = math.floor(n / 4096) % 64
    local c3 = math.floor(n / 64) % 64
    local c4 = n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

local function b64decode(s)
  s = s:gsub("=+$", "")
  local bytes, acc, bits = {}, 0, 0
  for i = 1, #s do
    local v = DECODE[s:sub(i, i)]
    if not v then return nil end
    acc = acc * 64 + v; bits = bits + 6
    if bits >= 8 then
      bits = bits - 8
      local p = 2 ^ bits
      bytes[#bytes + 1] = math.floor(acc / p)
      acc = acc % p
    end
  end
  return bytes
end

local function putVarint(out, n)
  repeat
    local b = n % 128
    n = math.floor(n / 128)
    out[#out + 1] = (n > 0) and (b + 128) or b
  until n == 0
end

local function reader(bytes)
  local i = 1
  return function()
    local n, mul = 0, 1
    for _ = 1, 6 do
      local b = bytes[i]
      if b == nil then error("deck code ended early", 0) end
      i = i + 1
      n = n + (b % 128) * mul
      if b < 128 then return n end
      mul = mul * 128
    end
    error("deck code has a malformed number", 0)
  end, function() return i > #bytes end
end

local function dbfIds() return ns.DbfIds or {} end

-- ============================================================ export

--- The bare code for a deck { class, cards = {ids} }.
function DeckCode.Encode(deck)
  local D = dbfIds()
  local counts = {}
  for _, id in ipairs(deck.cards or {}) do
    local dbf = D.byCard and D.byCard[id]
    if not dbf then return nil, "no Hearthstone id for " .. tostring(id) end
    counts[dbf] = (counts[dbf] or 0) + 1
  end
  local ones, twos, many = {}, {}, {}
  for dbf, n in pairs(counts) do
    if n == 1 then ones[#ones + 1] = dbf
    elseif n == 2 then twos[#twos + 1] = dbf
    else many[#many + 1] = dbf end
  end
  table.sort(ones); table.sort(twos); table.sort(many)
  local hero = D.heroFor and D.heroFor[deck.class]
  if not hero then return nil, "no hero for class " .. tostring(deck.class) end
  local out = { 0 }
  putVarint(out, 1)        -- version
  putVarint(out, 1)        -- Wild
  putVarint(out, 1); putVarint(out, hero)
  putVarint(out, #ones); for _, d in ipairs(ones) do putVarint(out, d) end
  putVarint(out, #twos); for _, d in ipairs(twos) do putVarint(out, d) end
  putVarint(out, #many)
  for _, d in ipairs(many) do putVarint(out, d); putVarint(out, counts[d]) end
  return b64encode(out)
end

local function titleCase(s) return s:sub(1, 1) .. s:sub(2):lower() end

--[[ What Hearthstone puts on the clipboard: the name, class and format, the
     card list by cost, the code, and how to use it. ]]
function DeckCode.Export(deck)
  local code, err = DeckCode.Encode(deck)
  if not code then return nil, err end
  local printed = ns.PrintedCards or {}
  local counts, ids = {}, {}
  for _, id in ipairs(deck.cards or {}) do
    if not counts[id] then ids[#ids + 1] = id end
    counts[id] = (counts[id] or 0) + 1
  end
  table.sort(ids, function(a, b)
    local pa, pb = printed[a] or {}, printed[b] or {}
    if (pa.cost or 0) ~= (pb.cost or 0) then return (pa.cost or 0) < (pb.cost or 0) end
    return (pa.name or a) < (pb.name or b)
  end)
  local lines = { "### " .. ((deck.name and deck.name ~= "") and deck.name or (titleCase(deck.class) .. " Deck")),
                  "# Class: " .. titleCase(deck.class),
                  "# Format: Wild",
                  "#" }
  for _, id in ipairs(ids) do
    local p = printed[id] or {}
    lines[#lines + 1] = ("# %dx (%d) %s"):format(counts[id], p.cost or 0, p.name or id)
  end
  lines[#lines + 1] = "#"
  lines[#lines + 1] = code
  lines[#lines + 1] = "#"
  lines[#lines + 1] = "# To use this deck, copy it to your clipboard and create a new deck in Hearthstone"
  return table.concat(lines, "\n"), code
end

-- ============================================================ import

--[[ Read pasted text. Returns
       { name, class, cards = {ids}, unknown = { {dbf, n}... }, format }
     or nil and a reason a player can act on. The class comes from the hero;
     a hero we do not know (a newer hero portrait) falls back to the class of
     the deck's class cards. ]]
function DeckCode.Decode(text)
  if type(text) ~= "string" then return nil, "Paste a deck code first." end
  local name, code
  for line in (text .. "\n"):gmatch("([^\r\n]*)[\r\n]") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line:sub(1, 3) == "###" and not name and not code then
      name = line:sub(4):gsub("^%s+", "")
    elseif line ~= "" and line:sub(1, 1) ~= "#" and not code then
      code = line:match("^(%S+)")
    end
  end
  if not code then return nil, "No deck code found in that text." end
  local bytes = b64decode(code)
  if not bytes or #bytes < 3 then return nil, "That is not a Hearthstone deck code." end
  local D = dbfIds()
  local ok, result = pcall(function()
    local read, done = reader(bytes)
    if read() ~= 0 then error("That is not a Hearthstone deck code.", 0) end
    local version = read()
    if version ~= 1 then error("Unsupported deck code version " .. version .. ".", 0) end
    local r = { format = read(), cards = {}, unknown = {}, name = name }
    local heroes = read()
    if heroes > 4 then error("That is not a Hearthstone deck code.", 0) end
    for _ = 1, heroes do
      local h = read()
      r.class = r.class or (D.hero and D.hero[h])
      r.heroDbf = r.heroDbf or h
    end
    local function add(dbf, n)
      if n < 1 or n > 30 then error("That deck code has an impossible card count.", 0) end
      local id = D.card and D.card[dbf]
      if id then
        for _ = 1, n do r.cards[#r.cards + 1] = id end
      else
        r.unknown[#r.unknown + 1] = { dbf = dbf, n = n }
      end
    end
    for _ = 1, read() do add(read(), 1) end
    for _ = 1, read() do add(read(), 2) end
    if not done() then
      for _ = 1, read() do local d = read(); add(d, read()) end
    end
    return r
  end)
  if not ok then return nil, tostring(result) end
  if #result.cards + #result.unknown == 0 then return nil, "That deck code has no cards." end
  if not result.class then
    local printed = ns.PrintedCards or {}
    for _, id in ipairs(result.cards) do
      local c = printed[id] and printed[id].class
      if c and c ~= "NEUTRAL" then result.class = c; break end
    end
  end
  table.sort(result.cards)
  return result
end

-- ============================================================ what you're missing

--[[ How an imported deck meets a collection. One row per distinct card:
       { id, want, have, missing, craft = dust per copy or nil, why = reason
         it cannot be crafted }
     plus the totals: missing copies, the dust to craft every craftable one,
     and whether all of it can be crafted now. ]]
function DeckCode.Plan(collection, decoded)
  local rows, byId = {}, {}
  for _, id in ipairs(decoded.cards) do
    local row = byId[id]
    if not row then
      row = { id = id, want = 0 }
      byId[id] = row; rows[#rows + 1] = row
    end
    row.want = row.want + 1
  end
  local plan = { rows = rows, missing = 0, dust = 0, uncraftable = 0,
                 unknown = decoded.unknown or {}, class = decoded.class }
  local printed = collection.printed
  for _, row in ipairs(rows) do
    local p = printed[row.id] or {}
    row.name, row.cost, row.rarity = p.name or row.id, p.cost or 0, p.rarity
    local limit = collection:MaxCopies(row.id)
    if row.want > limit then row.over = row.want - limit; row.want = limit end
    row.have = math.min(row.want, collection:Count(row.id))
    row.missing = row.want - row.have
    if row.missing > 0 then
      plan.missing = plan.missing + row.missing
      local v = collection:DustValues(row.id)
      if p.class ~= "NEUTRAL" and p.class ~= collection.character.class then
        row.why = "another class's card"
      elseif p.unobtainable then
        row.why = "cannot be obtained"
      elseif not (v and v.craftable) then
        row.why = "Basic: unlocked by levelling"
      else
        row.craft = v.craft
        plan.dust = plan.dust + v.craft * row.missing
      end
      if row.why then plan.uncraftable = plan.uncraftable + row.missing end
    end
  end
  table.sort(rows, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    return a.name < b.name
  end)
  plan.have = collection:Dust()
  plan.canCraftAll = plan.missing > 0 and plan.uncraftable == 0 and plan.dust <= plan.have
  plan.complete = plan.missing == 0 and #plan.unknown == 0 and #decoded.cards == ns.RULES.DECK_SIZE
  return plan
end

--[[ Craft every craftable missing copy, cheapest first, stopping at the first
     the dust cannot cover. Returns crafted copies and the dust spent. ]]
function DeckCode.CraftMissing(collection, plan)
  local made, spent = 0, 0
  local order = {}
  for _, row in ipairs(plan.rows) do
    if row.craft and row.missing > 0 then order[#order + 1] = row end
  end
  table.sort(order, function(a, b) return a.craft < b.craft end)
  for _, row in ipairs(order) do
    for _ = 1, row.missing do
      local ok, cost = collection:Craft(row.id)
      if not ok then return made, spent, cost end
      made, spent = made + 1, spent + cost
    end
  end
  return made, spent
end

--[[ Save the imported deck as a new deck of this character's, holding the
     copies the collection can back: a deck in the builder never lists a card
     you do not own (Collection:CanAdd's rule), so a deck saved short of a few
     cards is simply unfinished, and the builder's own "complete this deck"
     fills it like any other. Craft first (CraftMissing) to save it whole.
     Returns the deck and how many copies were left out. ]]
function DeckCode.Save(collection, decoded)
  local name = decoded.name
  if not name or name == "" then name = "Imported Deck" end
  local deck, index = collection:NewDeck(name:sub(1, 24), collection.character.class)
  if not deck then return nil, "Could not make a new deck." end
  local used, left = {}, 0
  for _, id in ipairs(decoded.cards) do
    local p = collection.printed[id]
    local n = used[id] or 0
    if p and (p.class == "NEUTRAL" or p.class == deck.class) and n < collection:Count(id)
       and n < collection:MaxCopies(id) and #deck.cards < ns.RULES.DECK_SIZE then
      deck.cards[#deck.cards + 1] = id
      used[id] = n + 1
    else
      left = left + 1
    end
  end
  return deck, left, index
end

return DeckCode
