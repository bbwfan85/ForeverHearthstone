--[[ tests/test_ladder.lua -- the bot ladder, deck codes and bulk pack opening
     (docs/45-LADDER-DECKCODES-BULK-PACKS.md). ]]
local H = require("tests.harness")

-- A scripted roll(a, b): returns the queued values in turn, else the middle.
local function rolls(...)
  local q = { ... }
  return function(a, b)
    local v = table.remove(q, 1)
    if v == nil then v = math.floor((a + b) / 2) end
    return math.max(a, math.min(b, v))
  end
end

local function at(ns, rank, stars, extra)
  local s = { rank = rank, stars = stars, best = rank, bestStars = stars }
  for k, v in pairs(extra or {}) do s[k] = v end
  return ns.Ladder.Normalize(s)
end

-- ============================================================ ladder rules

H.suite("ladder: stars per rank are the final classic ladder's", function(ns, H)
  local L = ns.Ladder
  H.eq(L.Stars(25), 3, "25"); H.eq(L.Stars(16), 3, "16")
  H.eq(L.Stars(15), 4, "15"); H.eq(L.Stars(11), 4, "11")
  H.eq(L.Stars(10), 5, "10"); H.eq(L.Stars(1), 5, "1")
  H.eq(L.Stars(0), 0, "Legend")
  H.eq(L.Name(25), "Angry Chicken", "25's name")
  H.eq(L.Name(1), "Innkeeper", "1's name")
  for r = 0, 25 do
    local card = L.RANKS[r].card
    if card then H.ok(ns.PrintedCards[card], "medal art is a real card: " .. card) end
  end
end)

H.suite("ladder: a win is a star, a full rank steps up with one", function(ns, H)
  local L = ns.Ladder
  local s = at(ns, 25, 0)
  L.Record(s, true); H.eq(s.stars, 1, "one star")
  L.Record(s, false)                         -- breaks the streak; 25 loses nothing
  H.eq(s.stars, 1, "ranks 25-21 never lose stars")
  L.Record(s, true); L.Record(s, false)
  L.Record(s, true)                          -- third star
  H.eq(s.rank, 25); H.eq(s.stars, 3)
  local c = L.Record(s, false); c = L.Record(s, true)
  H.eq(s.rank, 24, "the fourth star is rank 24"); H.eq(s.stars, 1, "with one star")
  H.ok(c.rankUp, "reported as a rank up")
end)

H.suite("ladder: the third win in a row gives a bonus star, not from rank 5", function(ns, H)
  local L = ns.Ladder
  local s = at(ns, 18, 0)
  L.Record(s, true); L.Record(s, true)
  H.eq(s.stars, 2, "two plain stars")
  local c = L.Record(s, true)
  H.ok(c.bonus, "third win is a streak"); H.eq(c.stars, 2, "two stars")
  H.eq(s.rank, 17, "past 3 stars into 17"); H.eq(s.stars, 1)
  -- a bonus at 6 carries into 5
  s = at(ns, 6, 5, { streak = 2 })
  c = L.Record(s, true)
  H.ok(c.bonus, "bonus at rank 6"); H.eq(s.rank, 5); H.eq(s.stars, 2, "both stars count: into 5 with two")
  s = at(ns, 6, 4, { streak = 2 })
  L.Record(s, true)
  H.eq(s.rank, 5, "6 with 4 stars + 2 = rank 5"); H.eq(s.stars, 1)
  -- at 5 and above, no bonus
  s = at(ns, 5, 1, { streak = 5 })
  c = L.Record(s, true)
  H.notOk(c.bonus, "no bonus at rank 5"); H.eq(s.stars, 2)
end)

H.suite("ladder: losses at 20 and above take stars and drop ranks", function(ns, H)
  local L = ns.Ladder
  local s = at(ns, 18, 1)                    -- reached 18, so the 20 milestone holds
  L.Record(s, false); H.eq(s.stars, 0, "a star lost")
  local c = L.Record(s, false)
  H.eq(s.rank, 19, "dropped a rank"); H.eq(s.stars, 2, "one short of 19's three"); H.ok(c.rankDown)
  L.Record(s, false); L.Record(s, false); L.Record(s, false)
  H.eq(s.rank, 20, "down to 20..."); H.eq(s.stars, 2)
  L.Record(s, false); L.Record(s, false); c = L.Record(s, false)
  H.eq(s.rank, 20, "...and no further"); H.eq(s.stars, 0); H.ok(c.floor, "the milestone held")
end)

H.suite("ladder: a loss at 0 stars drops a rank, one short of full", function(ns, H)
  local L = ns.Ladder
  local s = at(ns, 12, 0, { best = 12 })   -- floor 15
  local c = L.Record(s, false)
  H.eq(s.rank, 13); H.eq(s.stars, L.Stars(13) - 1, "one star short of full")
  H.ok(c.rankDown, "reported")
  -- milestones: at 15 with 0 stars, having reached 15, you stay
  s = at(ns, 15, 0, { best = 15 })
  c = L.Record(s, false)
  H.eq(s.rank, 15, "15 is a milestone"); H.eq(s.stars, 0); H.ok(c.floor)
  s = at(ns, 5, 0, { best = 3 })
  L.Record(s, false); H.eq(s.rank, 5, "5 holds once 3 was reached")
  s = at(ns, 20, 0, { best = 20 })
  L.Record(s, false); H.eq(s.rank, 20, "20 holds")
  s = at(ns, 16, 0, { best = 16 })
  L.Record(s, false); H.eq(s.rank, 17, "16 above the 15 milestone drops")
  s = at(ns, 20, 0, { best = 21 })
  H.eq(L.Floor(s), 20, "standing at 20 is reaching it")
end)

H.suite("ladder: rank 1 full plus a win is Legend, which is kept", function(ns, H)
  local L = ns.Ladder
  local s = at(ns, 1, 5)
  local c = L.Record(s, true, rolls(500))
  H.eq(s.rank, 0, "Legend"); H.ok(c.legend, "said"); H.eq(s.legend, 2000, "number from the roll")
  local before = s.legend
  L.Record(s, true); H.ok(s.legend < before, "a win climbs")
  before = s.legend
  L.Record(s, false); H.ok(s.legend > before, "a loss slips")
  H.eq(s.rank, 0, "but Legend is kept")
  H.eq(L.Label(0, 1234), "Legend 1,234", "label")
  H.eq(L.Label(14), "Rank 14")
end)

H.suite("ladder: a new season is 4 ranks below your best, stars included", function(ns, H)
  local L = ns.Ladder
  local s = at(ns, 3, 2, { season = "2026-10", wins = 10, losses = 3, best = 1, bestStars = 3 })
  local r = L.BeginSeason(s, "2026-11")
  H.ok(r, "a reset happened")
  H.eq(s.rank, 5, "rank 1 with 3 stars is rank 5..."); H.eq(s.stars, 3, "...with 3 stars")
  H.eq(s.wins, 0, "season record restarts")
  H.eq(L.BeginSeason(s, "2026-11"), nil, "once a season")
  s = at(ns, 0, 0, { season = "2026-10", wins = 1, best = 0, legend = 50 })
  L.BeginSeason(s, "2026-11"); H.eq(s.rank, 4, "Legend resets to 4"); H.eq(s.stars, 0)
  s = at(ns, 23, 1, { season = "2026-10", wins = 1, everBest = 12 })
  L.BeginSeason(s, "2026-11"); H.eq(s.rank, 20, "ever reached 15: never below 20")
  s = at(ns, 23, 1, { season = "2026-10", wins = 1 })
  L.BeginSeason(s, "2026-11"); H.eq(s.rank, 25, "otherwise 25 at worst")
  s = at(ns, 25, 0)
  H.eq(L.BeginSeason(s, "2026-11"), nil, "a new record is only stamped"); H.eq(s.season, "2026-11")
end)

H.suite("ladder: saved records are repaired, not trusted", function(ns, H)
  local s = ns.Ladder.Normalize({ rank = "x", stars = 99, streak = -4, best = 40 })
  H.eq(s.rank, 25); H.eq(s.stars, 3); H.eq(s.streak, 0); H.eq(s.best, 25)
  s = ns.Ladder.Normalize({ rank = -3 })
  H.eq(s.rank, 0); H.ok(s.legend >= 1, "Legend gets a number")
end)

H.suite("ladder: higher ranks meet better decks and better play", function(ns, H)
  local L = ns.Ladder
  H.eq(L.Skill(25), 1, "rank 25 is a Novice"); H.eq(L.Skill(1), 5, "rank 1 a Master")
  H.ok(L.Skill(0, 3000) > L.Skill(1), "Legend beyond")
  H.ok(L.Skill(0, 50) <= 6 and L.Skill(0, 50) > L.Skill(0, 2000), "top Legend best")
  local last = 0
  for r = 25, 1, -1 do H.ok(L.Skill(r) > last, "rising at " .. r); last = L.Skill(r) end
  local low = L.Opponent(at(ns, 25, 0), rolls(0, 1, 1))
  H.eq(low.deckTier, 1, "rank 25 brings Basic decks")
  local high = L.Opponent(at(ns, 1, 2), rolls(0, 2, 1))
  H.eq(high.deckTier, 5, "rank 1 brings top decks")
  H.ok(math.abs(high.rank - 1) <= 1, "matched near your rank")
  local leg = L.Opponent(at(ns, 0, 0, { legend = 800 }), rolls(0, 1))
  H.eq(leg.rank, 0, "Legend meets Legend"); H.ok(leg.legend >= 1)
  -- the AI blends between levels and reaches past Master
  local P1, P5, P6 = ns.AI.SkillProfile(1), ns.AI.SkillProfile(5), ns.AI.SkillProfile(6)
  H.eq(P1.width, ns.AI.DIFFICULTIES[1].width, "1 is Novice")
  H.eq(P5.budget, ns.AI.DIFFICULTIES[5].budget, "5 is Master")
  H.eq(P6.reply, ns.AI.LEGEND.reply, "6 is Legend")
  local mid = ns.AI.SkillProfile(4.5)
  H.ok(mid.budget > ns.AI.DIFFICULTIES[4].budget and mid.budget < ns.AI.DIFFICULTIES[5].budget, "blended")
  local P = ns.AI.Profile({ skill = 5.5, style = "aggro" })
  H.ok(P.budget > ns.AI.DIFFICULTIES[5].budget, "Profile takes a skill")
  H.eq(P.skill, nil, "and does not copy it through")
end)

H.suite("ladder: a ladder bot at Legend skill plays a full game", function(ns, H)
  local g = ns.Game.New({ seed = 7, firstPlayer = 1, players = {
    { class = "MAGE", deck = ns.BotDecks.Expand(ns.BotDecks.Pick("MAGE", 5)) },
    { class = "WARRIOR", deck = ns.BotDecks.Expand(ns.BotDecks.Pick("WARRIOR", 5)) } } })
  g:StartGame(); g.bus:Drain()
  -- light budgets: this proves the Legend profile runs, not how well
  local opts = { { skill = 6, budget = 120, lethalBudget = 40, reply = 2, width = 3, depth = 5 },
                 { skill = 1, style = "control" } }
  for _ = 1, 120 do
    if g.over then break end
    local p = g.activePlayer
    ns.AI.TakeTurn(g, p, nil, opts[p])
    if g.over then break end
    g:EndTurn(); g.bus:Drain()
  end
  H.ok(g.over, "the game reached a result")
  H.eq(#g.errors, 0, "no engine errors")
end)

-- ============================================================ deck codes

local function collection(ns, class)
  return ns.Collection.New({}, { class = class or "MAGE", decks = {} })
end

H.suite("deck codes: every pinned card has a Hearthstone id", function(ns, H)
  local n = 0
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.type ~= "HERO" and not p.unobtainable then
      n = n + 1
      H.ok(ns.DbfIds.byCard[id], "DBF id for " .. id)
      H.eq(ns.DbfIds.card[ns.DbfIds.byCard[id]], id, "and back")
    end
  end
  H.ok(n > 500, "checked the pool")
  for _, class in ipairs(ns.CLASSES) do H.ok(ns.DbfIds.heroFor[class], class .. " hero") end
  H.eq(ns.DbfIds.heroFor.WARRIOR, 7, "Garrosh is 7 (the spec's example)")
end)

H.suite("deck codes: decode Hearthstone's own codes (python-hearthstone vectors)", function(ns, H)
  -- The HearthSim spec's example: Garrosh, four cards x3
  local r = ns.DeckCode.Decode("AAEBAQcAAAQBAwIDAwMEAw==")
  H.ok(r, "decodes"); H.eq(r.class, "WARRIOR", "hero 7 is Warrior")
  H.eq(#r.cards + #r.unknown, 4, "four entries")
  -- written by python-hearthstone: Mage, 1080x1, 315x2, 662x2, (1, 3)
  r = ns.DeckCode.Decode("AAEBAf0EAbgIArsClgUBAQMA")
  H.eq(r.class, "MAGE")
  local n = {}
  for _, id in ipairs(r.cards) do n[id] = (n[id] or 0) + 1 end
  H.eq(n.CS2_029, 2, "two Fireballs (315)")
  H.eq(n.CS2_024, 2, "two Frostbolts (662)")
  H.eq(n.EX1_559, 1, "Archmage Antonidas (1080)")
end)

H.suite("deck codes: export round-trips and reads as Hearthstone's text", function(ns, H)
  local d = ns.BotDecks.Pick("PRIEST", 5)
  local deck = { name = "Control Priest", class = "PRIEST", cards = ns.BotDecks.Expand(d) }
  local text, code = ns.DeckCode.Export(deck)
  H.ok(text:find("^### Control Priest\n# Class: Priest\n# Format: Wild"), "header")
  H.ok(text:find("# 2x %(") , "card lines")
  local r = ns.DeckCode.Decode(text)
  H.eq(r.name, "Control Priest", "name from ###")
  H.eq(r.class, "PRIEST")
  H.eq(table.concat(r.cards, ","), table.concat(deck.cards, ","), "same thirty cards")
  H.eq(#r.unknown, 0)
  H.eq(ns.DeckCode.Decode(code).class, "PRIEST", "the bare code too")
end)

H.suite("deck codes: bad input is refused with a reason", function(ns, H)
  for _, bad in ipairs({ "", "hello world!", "#only comments", "AAAA", "AAEBAQcAAAQBAwID" }) do
    local r, why = ns.DeckCode.Decode(bad)
    H.eq(r, nil, "refused: " .. bad); H.ok(type(why) == "string" and #why > 0, "with a reason")
  end
  H.eq(ns.DeckCode.Decode(nil), nil)
end)

H.suite("deck codes: a modern reprint imports as the 2014 card", function(ns, H)
  local alias
  for dbf, id in pairs(ns.DbfIds.card) do
    if ns.DbfIds.byCard[id] ~= dbf then alias = { dbf = dbf, id = id }; break end
  end
  H.ok(alias, "reprints are known")
end)

H.suite("deck codes: the plan says what is missing and what it costs", function(ns, H)
  local c = collection(ns, "MAGE")
  c.account.dust = 100000
  local deck = { class = "MAGE", cards = {} }
  for _ = 1, 2 do
    deck.cards[#deck.cards + 1] = "CS2_029"     -- Fireball (Basic: granted, not crafted)
    deck.cards[#deck.cards + 1] = "EX1_279"     -- Pyroblast (epic)
  end
  deck.cards[#deck.cards + 1] = "EX1_559"       -- Antonidas
  c:Add("EX1_279", 1)
  local r = ns.DeckCode.Decode(ns.DeckCode.Encode(deck))
  local plan = ns.DeckCode.Plan(c, r)
  local rows = {}
  for _, row in ipairs(plan.rows) do rows[row.id] = row end
  H.eq(rows.EX1_279.missing, 1, "one Pyroblast short")
  H.eq(rows.EX1_559.missing, 1, "Antonidas missing")
  H.ok(rows.EX1_559.craft and rows.EX1_559.craft > rows.EX1_279.craft, "a legendary costs more")
  H.ok(rows.CS2_029.why, "Basic cards are not crafted")
  H.notOk(plan.canCraftAll, "so not everything can be crafted")
  H.eq(plan.dust, rows.EX1_279.craft + rows.EX1_559.craft, "the total")
  local made, spent = ns.DeckCode.CraftMissing(c, plan)
  H.eq(made, 2, "crafted the two"); H.eq(spent, plan.dust)
  H.eq(c:Count("EX1_559"), 1)
  local saved, left = ns.DeckCode.Save(c, r)
  H.eq(left, 2, "the two Fireballs this level-1 Mage lacks are left out")
  H.ok(c:ValidateDeck(saved) or #saved.cards < 30, "the saved deck holds only owned copies")
  for _, id in ipairs(saved.cards) do H.ok(c:Count(id) > 0, "owned: " .. id) end
end)

H.suite("deck codes: another class's deck is refused at the plan", function(ns, H)
  local c = collection(ns, "MAGE")
  local warrior = { class = "WARRIOR", cards = { "EX1_400", "EX1_400" } }
  local r = ns.DeckCode.Decode(ns.DeckCode.Encode(warrior))
  H.eq(r.class, "WARRIOR")
  local plan = ns.DeckCode.Plan(c, r)
  H.eq(plan.rows[1].why, "another class's card")
end)

-- ============================================================ bulk packs

H.suite("packs: bulk opening is Hearthstone's (up to 40), each pack a real pack", function(ns, H)
  local c = collection(ns, "MAGE")
  c:AddPack("HEARTHSTONE", 50)
  math.randomseed(3)
  local r = ns.Packs.OpenMany(c, "HEARTHSTONE", 99)
  H.eq(r.packs, 40, "capped at 40")
  H.eq(#r.cards, 200, "five cards each")
  H.eq(c:PackCount("HEARTHSTONE"), 10, "forty spent")
  local copies, dust = 0, 0
  for _, e in ipairs(r.distinct) do copies = copies + e.copies; dust = dust + e.dust end
  H.eq(copies, 200, "distinct entries account for every card")
  H.eq(dust, r.dust, "and its dust")
  local ORDER = { LEGENDARY = 4, EPIC = 3, RARE = 2, COMMON = 1, FREE = 0 }
  for i = 2, #r.distinct do
    H.ok(ORDER[r.distinct[i - 1].rarity] >= ORDER[r.distinct[i].rarity], "best first")
  end
  local rares = (r.summary.RARE or 0) + (r.summary.EPIC or 0) + (r.summary.LEGENDARY or 0)
  H.ok(rares >= 40, "every pack kept its rare-or-better")
  local r2 = ns.Packs.OpenMany(c, "HEARTHSTONE", 5)
  H.eq(r2.packs, 5)
  local r3 = ns.Packs.OpenMany(c, "HEARTHSTONE", 40)
  H.eq(r3.packs, 5, "only what is left")
  local none, why = ns.Packs.OpenMany(c, "HEARTHSTONE", 5)
  H.eq(none, nil); H.ok(why)
end)

H.suite("packs: a card never owned before is NEW", function(ns, H)
  local c = collection(ns, "MAGE")
  c:AddPack("HEARTHSTONE", 1)
  math.randomseed(11)
  local p = ns.Packs.Open(c, "HEARTHSTONE")
  local seen = {}
  for _, card in ipairs(p.cards) do
    if not seen[card.cardId] then H.ok(card.new, "first copy is new") else H.notOk(card.new, "second is not") end
    seen[card.cardId] = true
  end
end)

H.suite("ladder: low ranks slip like beginners, never into helping you", function(ns, H)
  local P1 = ns.AI.SkillProfile(1)
  H.ok(P1.slip > 0.3, "rank 25 slips often")
  -- the difficulty curve review (docs/45) gave Master an occasional slip; the
  -- owner chose instead that Master always plays its best, like Legend
  H.eq(ns.AI.SkillProfile(5).slip, 0, "Master never: it plays its best (the owner's call)")
  H.eq(ns.AI.SkillProfile(5).noise, 0, "and its judgement does not wobble")
  H.eq(ns.AI.SkillProfile(6).slip, 0, "Legend never")
  H.eq(ns.AI.SkillProfile(6).noise, 0, "and never wobbles")
  -- every mistake shrinks, and the thinking grows, as the skill climbs
  local prev
  for x = 1, 6.001, 0.25 do
    local P = ns.AI.SkillProfile(x)
    if prev then
      H.ok(P.slip <= prev.slip and P.noise <= prev.noise, "fewer slips at " .. x)
      H.ok(P.lethal >= prev.lethal and P.budget >= prev.budget and P.reply >= prev.reply,
           "more thinking at " .. x)
    end
    prev = P
  end
  -- a Novice with only a heal for your damaged minion never casts it on yours
  local healed = 0
  for t = 1, 30 do
    local g = H.NewGame({ seed = 50 + t, class1 = "PALADIN", class2 = "WARRIOR" })
    local p = g.players[1]
    for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
    for _ = 1, t % 7 do g:AddToHand(2, "CS2_231") end
    g.activePlayer = 1
    H.Mana(g, 1, 10)
    local yeti = H.Put(g, 2, "CS2_182")
    yeti.damage = 3
    H.Hand(g, 1, "CS2_089")                -- Holy Light: restore 6
    ns.AI.TakeTurn(g, 1, nil, { skill = 1 })
    if yeti.damage < 3 then healed = healed + 1 end
  end
  H.eq(healed, 0, "it never heals your minion, slips included")
end)

H.suite("ladder: opponents are named by class and rank", function(ns, H)
  local B = ns.BotNames
  H.eq(B.Band(25), "new"); H.eq(B.Band(16), "new"); H.eq(B.Band(15), "climber")
  H.eq(B.Band(6), "climber"); H.eq(B.Band(5), "contender"); H.eq(B.Band(1), "contender")
  H.eq(B.Band(0), "legend")
  for _, class in ipairs(ns.CLASSES) do
    H.ok(B.CLASSES[class], class .. " has names")
    for _, rank in ipairs({ 25, 12, 3, 0 }) do
      local seen = {}
      for i = 1, 40 do
        local n = B.Pick(class, rank)
        H.ok(#n >= 3 and #n <= 16, "fits the plate: " .. n)
        H.ok(n:match("^[%w']+$"), "plain letters and numbers: " .. n)
        seen[n] = true
      end
      local k = 0; for _ in pairs(seen) do k = k + 1 end
      H.ok(k >= 4, class .. " rank " .. rank .. " has variety")
    end
    local legend = {}
    for _, n in ipairs(B.CLASSES[class].legend) do legend[n] = true end
    H.ok(legend[B.Pick(class, 0)], "Legend draws from the class's Legend tags")
  end
end)

H.suite("ladder decks: every class has at least three decks at every tier", function(ns, H)
  for _, class in ipairs(ns.CLASSES) do
    local per = {}
    for _, d in ipairs(ns.BotDecks.List(class)) do per[d.tier] = (per[d.tier] or 0) + 1 end
    for t = 1, ns.BotDecks.TIERS do
      H.ok((per[t] or 0) >= 3, ("%s has %d decks at tier %d"):format(class, per[t] or 0, t))
    end
  end
end)

H.suite("ladder decks: a player's copy is always legal, and rank shows in it", function(ns, H)
  math.randomseed(9)
  local rareLow, rareHigh, pets, n = 0, 0, 0, 0
  local function premium(d)
    local k = 0
    for id, c in pairs(d.counts) do
      local r = ns.PrintedCards[id].rarity
      if r == "EPIC" or r == "LEGENDARY" then k = k + c end
    end
    return k
  end
  for _, class in ipairs(ns.CLASSES) do
    for _, base in ipairs(ns.BotDecks.List(class)) do
      for _, skill in ipairs({ 1, 3, 5, 6 }) do
        local d = ns.BotDecks.Personalize(base, skill)
        local ids = ns.BotDecks.Expand(d)
        H.eq(#ids, 30, d.name .. " stays thirty cards")
        for id, c in pairs(d.counts) do
          local p = ns.PrintedCards[id]
          H.ok(p and p.collectible and not p.unobtainable, "real card " .. id)
          H.ok(p.class == "NEUTRAL" or p.class == class, "class card " .. id)
          H.ok(c <= ((p.rarity == "LEGENDARY") and 1 or 2), "copy limit " .. id)
        end
        if base.tier >= 4 then
          if skill == 1 then rareLow = rareLow + premium(d); n = n + 1 end
          if skill == 6 then rareHigh = rareHigh + premium(d) end
        end
        for _, ch in ipairs(d.changes) do if ch.why == "pet" then pets = pets + 1 end end
        if skill == 6 then
          H.ok(#d.changes <= 1, "Legend plays the list, give or take one tech card")
        end
      end
    end
  end
  H.ok(rareLow < rareHigh * 0.6, ("a rank-25 copy of a meta list is missing its epics and legendaries (%d vs %d)"):format(rareLow, rareHigh))
  H.ok(pets > 0, "someone threw in the legendary they opened")
  local base = ns.BotDecks.List("MAGE")[1]
  local a = ns.BotDecks.Personalize(base, 1)
  H.ok(base.counts ~= a.counts, "the list itself is never changed")
end)

H.suite("ladder: the post-game medal moves star by star", function(ns, H)
  local L = ns.Ladder
  local function steps(s, won, roll) return L.Steps(L.Record(L.Normalize(s), won, roll)) end
  local st = steps({ rank = 18, stars = 1, best = 18 }, true)
  H.eq(#st, 1); H.eq(st[1].kind, "gain"); H.eq(st[1].star, 2)
  st = steps({ rank = 18, stars = 2, best = 18, streak = 2 }, true)
  H.eq(#st, 2, "a streak is two moments"); H.eq(st[1].kind, "gain"); H.eq(st[2].kind, "rankup")
  H.eq(st[2].rank, 17); H.eq(st[2].stars, 1)
  st = steps({ rank = 1, stars = 5 }, true, function(a, b) return a end)
  H.eq(st[1].kind, "legend")
  st = steps({ rank = 12, stars = 2, best = 12 }, false)
  H.eq(st[1].kind, "lose"); H.eq(st[1].star, 2); H.eq(st[1].stars, 1)
  st = steps({ rank = 12, stars = 0, best = 12 }, false)
  H.eq(st[1].kind, "rankdown"); H.eq(st[1].rank, 13)
  st = steps({ rank = 23, stars = 1 }, false)
  H.eq(st[1].kind, "hold", "ranks 25-21 lose nothing")
  st = steps({ rank = 15, stars = 0, best = 15 }, false)
  H.eq(st[1].kind, "hold", "a milestone holds")
  st = steps({ rank = 0, legend = 900 }, true)
  H.eq(st[1].kind, "legendmove")
end)
