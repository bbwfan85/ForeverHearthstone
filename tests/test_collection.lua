--[[ tests/test_collection.lua -- what you own, what drops, what is in a pack.

  Two kinds of test in here, and the second kind is the reason this file is
  worth having: the ordinary behavioural ones, and DISTRIBUTION tests that roll
  tens of thousands of packs and kills. A 1% drop rate cannot be checked by
  playing; it can be checked exactly by rolling it a hundred thousand times with
  a seeded generator, which takes a few milliseconds here.

  The seeded roller below is the same LCG the engine uses, for the same reason:
  reproducibility. A distribution test that fails intermittently is worse than
  no test at all, because it teaches you to re-run until it passes.
]]
local H = require("tests.harness")

--[[ A seeded roll(n) -> [1, n]. Reproducible: the same seed gives the same
     sequence, so a failure here can be reproduced exactly.

     NOT the engine's LCG, deliberately. Game:Random is a 32-bit LCG chosen for
     reproducibility across machines rather than for quality, and measuring it
     shows what that costs: 100,000 consecutive draws of "is d100 <= 3" come out
     at 3.3%, not 3.0%, because consecutive draws of the same modulus are
     structured. That is invisible in a card game, where draws are interleaved
     at many different moduli and nobody rolls the same thing 100,000 times --
     but it is fatal to a test that exists to measure a 1% rate. So the
     distribution tests use the interpreter's own generator, seeded. ]]
local function seededRng(seed)
  math.randomseed(seed or 1)
  return function(n)
    if n <= 0 then return 0 end
    return math.random(1, n)
  end
end

local function newCollection(ns, class)
  local account, character = {}, { class = class or "MAGE" }
  return ns.Collection.New(account, character), account, character
end

--=========================================================== ownership

H.suite("collection: a golden copy is the SAME card, not another one", function(ns, H)
  --[[ It counts against the two-copy deck limit exactly as a normal copy does.
       Storing goldens under a separate id would double the collection and make
       every ownership check ask the question twice. ]]
  local c = newCollection(ns)
  c:Add("CS2_182", 1)                       -- Chillwind Yeti
  c:Add("CS2_182", 1, true)                 -- and a golden one
  local n, g = c:Owned("CS2_182")
  H.eq(n, 1, "one normal")
  H.eq(g, 1, "one golden")
  H.eq(c:Count("CS2_182"), 2, "which is two copies for deck purposes")
  local deck = { class = "MAGE", cards = { "CS2_182", "CS2_182" } }
  H.notOk(c:CanAdd(deck, "CS2_182"), "so a third is refused")
end)

H.suite("collection: an unknown card cannot be added", function(ns, H)
  local c = newCollection(ns)
  local rec, why = c:Add("NOT_A_REAL_CARD")
  H.eq(rec, nil, "refused")
  H.ok(why and why:find("no such card"), "and says so")
end)

H.suite("collection: neutrals are account-wide, class cards are not", function(ns, H)
  --[[ Decision D5. A WoW character is one class forever, so per-character
       neutrals would make every alt re-grind the same 153 cards before it could
       build anything at all. ]]
  local account = {}
  local mage   = ns.Collection.New(account, { class = "MAGE" })
  mage:Add("CS2_182", 2)          -- Chillwind Yeti, neutral
  mage:Add("CS2_029", 2)          -- Fireball, MAGE

  local priest = ns.Collection.New(account, { class = "PRIEST" })
  H.eq(priest:Count("CS2_182"), 2, "the alt sees the neutral")
  H.eq(priest:Count("CS2_029"), 0, "but not the Mage's class card")
end)

H.suite("collection: removing takes the normal copy before the golden", function(ns, H)
  -- The golden is the drop-only chase version; eating it silently would be the
  -- worst possible default.
  local c = newCollection(ns)
  c:Add("CS2_182", 1); c:Add("CS2_182", 1, true)
  c:Remove("CS2_182", 1)
  local n, g = c:Owned("CS2_182")
  H.eq(n, 0, "the normal one went")
  H.eq(g, 1, "the golden one stayed")
end)

--=========================================================== dust

H.suite("collection: dust values come from the PIN, not from a table here", function(ns, H)
  local c = newCollection(ns)
  local v = c:DustValues("EX1_116")              -- Leeroy Jenkins, LEGENDARY
  H.ok(v and v.craftable, "a Classic legendary is craftable")
  H.eq(v.craft, ns.PrintedCards["EX1_116"].dustHS[1], "craft value is the printed one")
  H.eq(v.de, ns.PrintedCards["EX1_116"].dustHS[3], "and so is the disenchant value")
end)

H.suite("collection: free Basic cards cannot be crafted or disenchanted", function(ns, H)
  local c = newCollection(ns)
  local ok, why = c:Craft("CS1_042")             -- Goldshire Footman, Basic
  H.notOk(ok, "crafting a Basic is refused")
  H.ok(why:find("granted"), "and explains why: " .. tostring(why))

  c:Add("CS1_042", 1)
  local before = c:Dust()
  local ok2, reason = c:Disenchant("CS1_042")
  H.notOk(ok2, "free copies cannot be disenchanted")
  H.ok(reason:find("free"), "explains the protection")
  H.eq(c:Dust(), before, "no dust gained")
  H.eq(c:Count("CS1_042"), 1, "card retained")
end)

H.suite("collection: crafting spends dust and refuses when short", function(ns, H)
  local c, account = newCollection(ns)
  local cost = c:DustValues("EX1_116").craft
  account.dust = cost - 1
  local ok, why = c:Craft("EX1_116")
  H.notOk(ok, "one dust short is short")
  H.ok(why:find("not enough dust"), "and says so")

  account.dust = cost
  H.ok(c:Craft("EX1_116"), "with exactly enough it crafts")
  H.eq(c:Dust(), 0, "spending all of it")
  H.eq(c:Count("EX1_116"), 1, "and the card arrives")
  H.notOk(c:Craft("EX1_116"), "a second legendary is refused -- a deck can hold one")
end)

H.suite("collection: login repairs missing Basics without farming class grants", function(ns, H)
  local c = newCollection(ns)
  c:GrantForLevel("MAGE", 60)
  c:Remove("CS2_182", 2)
  H.eq(c:Count("CS2_182"), 0, "simulate old starter disenchant")
  local dust = c:Dust()
  c:GrantForLevel("MAGE", 60)
  H.eq(c:Count("CS2_182"), 2, "free starters repaired")
  H.eq(c:Dust(), dust, "earned dust left alone")
  local id
  for _, entry in ipairs(c:ClassCurve("MAGE")) do
    if entry.band == "CLASSIC" and c:Count(entry.id) > 0 then id = entry.id; break end
  end
  H.ok(id, "has a free Classic class grant")
  H.notOk(c:Disenchant(id), "cannot dust and regrant starter copies")
  c:Add(id, 1)
  H.ok(c:Disenchant(id), "earned extra may still be disenchanted")
  H.notOk(c:Disenchant(id), "stops at protected copy count")
end)

H.suite("collection: goldens are never craftable", function(ns, H)
  -- Deviation 3: drop-only is what keeps them a chase rather than a purchase.
  local c = newCollection(ns)
  c.account.dust = 999999
  H.ok(c:Craft("CS2_231"), "a Classic common crafts")   -- Wisp, EXPERT1
  local n, g = c:Owned("CS2_231")
  H.eq(n, 1, "as a normal copy")
  H.eq(g, 0, "and there is no golden path at all")
end)

H.suite("collection: you cannot craft another class's card", function(ns, H)
  local c = newCollection(ns, "MAGE")
  c.account.dust = 999999
  local ok, why = c:Craft("EX1_354")             -- Lay on Hands, PALADIN
  H.notOk(ok, "refused")
  H.ok(why:find("another class"), "by class, not by dust")
end)

H.suite("collection: extras are the copies no deck could use", function(ns, H)
  local c = newCollection(ns)
  c:Add("CS2_182", 3)                    -- three Yetis: one too many
  c:Add("EX1_116", 1)                    -- one legendary: exactly right
  c:Add("CS2_231", 2)                    -- two Wisps: fine
  local extras = c:Extras()
  H.eq(#extras, 1, "one card has extras")
  H.eq(extras[1].cardId, "CS2_182", "the Yeti")
  H.eq(extras[1].normal, 1, "one spare copy")

  c:Add("EX1_116", 1, true)              -- a second, GOLDEN legendary
  extras = c:Extras()
  local found
  for _, e in ipairs(extras) do if e.cardId == "EX1_116" then found = e end end
  H.ok(found, "the legendary now has a spare")
  H.eq(found.normal, 1, "and it is the NORMAL one that is spare, not the golden")
  H.eq(found.golden, 0, "the golden copy is never the extra")
end)

--=========================================================== progression

H.suite("collection: the Basic set is granted, not collected", function(ns, H)
  --[[ Decision D0, and the best outcome available: this is Hearthstone's own
       starter-deck mechanism, so it is a ZERO-deviation answer. ]]
  local c = newCollection(ns, "MAGE")
  c:GrantForLevel("MAGE", 1)
  local neutralBasics = 0
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.set == "CORE" and p.class == "NEUTRAL" and p.type ~= "HERO" then
      neutralBasics = neutralBasics + 1
      H.ok(c:Count(id) >= 2, p.name .. " was granted")
    end
  end
  H.eq(neutralBasics, 43, "all 43 neutral Basic cards, as the pin says")
end)

H.suite("collection: a level-1 character can build a legal 30-card deck", function(ns, H)
  --[[ The proof that D0 is playable: 43 neutral Basic cards is 86 deck slots at
       the two-copy limit, and you need 30. ]]
  local c = newCollection(ns, "MAGE")
  c:GrantForLevel("MAGE", 1)
  local deck = { class = "MAGE", cards = {} }
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.set == "CORE" and p.class == "NEUTRAL" then
      for _ = 1, 2 do
        if #deck.cards < ns.RULES.DECK_SIZE and c:CanAdd(deck, id) then
          deck.cards[#deck.cards + 1] = id
        end
      end
    end
  end
  H.eq(#deck.cards, 30, "thirty cards from Basic neutrals alone")
  local ok, errs = c:ValidateDeck(deck, "MAGE")
  H.ok(ok, "and it is legal: " .. table.concat(errs or {}, "; "))
end)

H.suite("collection: all 34 class cards have arrived by level 60", function(ns, H)
  --[[ The curve from docs/04: 10 Basic by 10, 15 Classic by 40, 9 Naxx+GvG by
       60. It must come out exactly, for every class, or the levelling design
       does not close. ]]
  for _, class in ipairs(ns.CLASSES) do
    local c = ns.Collection.New({}, { class = class })
    c:GrantForLevel(class, 60)
    local owned = 0
    for id, p in pairs(ns.PrintedCards) do
      if p.collectible and p.class == class and p.type ~= "HERO" and c:Count(id) > 0 then
        owned = owned + 1
      end
    end
    H.eq(owned, 34, class .. " has all 34 class cards at 60")
  end
end)

H.suite("collection: grants are a function of LEVEL, never an event", function(ns, H)
  --[[ A character that levelled while the addon was uninstalled must catch up
       the next time it logs in. Anything driven by a level-up event alone
       silently loses cards, and the player has no way to notice. ]]
  local c = newCollection(ns, "DRUID")
  c:GrantForLevel("DRUID", 1)
  local atOne = select(1, c:Progress())
  c:GrantForLevel("DRUID", 32)          -- jumped 31 levels with the addon off
  local at32 = select(1, c:Progress())
  H.ok(at32 > atOne, "the missed levels were granted on the next login")

  local granted = c:GrantForLevel("DRUID", 32)
  H.eq(#granted, 0, "and running it again grants nothing -- it is idempotent")
end)

H.suite("collection: class cards arrive playable-first, legendaries last", function(ns, H)
  --[[ docs/03 D4's front-load rule: a level-20 character should have its core
       removal, not only vanilla minions. The authored per-class utility table
       is still owed by the user, so this asserts the PROPERTY the placeholder
       ordering guarantees, not a specific list. ]]
  local c = newCollection(ns, "PALADIN")
  c:GrantForLevel("PALADIN", 30)
  local legendaries = 0
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.class == "PALADIN" and p.rarity == "LEGENDARY" and c:Count(id) > 0 then
      legendaries = legendaries + 1
    end
  end
  H.eq(legendaries, 0, "no class legendary before level 30")
  c:GrantForLevel("PALADIN", 60)
  local late = 0
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.class == "PALADIN" and p.rarity == "LEGENDARY" and c:Count(id) > 0 then
      late = late + 1
    end
  end
  H.ok(late > 0, "but they have arrived by 60")
end)

--=========================================================== decks

H.suite("collection: a deck you cannot afford is refused", function(ns, H)
  local c = newCollection(ns, "MAGE")
  c:GrantForLevel("MAGE", 1)
  local deck = { class = "MAGE", cards = {} }
  for i = 1, 30 do deck.cards[i] = "EX1_116" end      -- 30 Leeroys you do not own
  local ok, errs = c:ValidateDeck(deck, "MAGE")
  H.notOk(ok, "refused")
  local joined = table.concat(errs, " | ")
  H.ok(joined:find("you own 0"), "because you do not own them: " .. joined)
  H.ok(joined:find("too many copies"), "and because one is the legendary limit")
end)

H.suite("collection: a deck may not hold another class's cards", function(ns, H)
  local c = newCollection(ns, "MAGE")
  c:GrantForLevel("MAGE", 60)
  local deck = { class = "MAGE", cards = { "EX1_354" } }
  local ok, errs = c:ValidateDeck(deck, "MAGE")
  H.notOk(ok, "refused")
  H.ok(table.concat(errs, " "):find("PALADIN"), "naming the class it belongs to")
end)

H.suite("collection: CanAdd says WHY, because the builder has to show it", function(ns, H)
  local c = newCollection(ns, "MAGE")
  c:GrantForLevel("MAGE", 60)
  local deck = { class = "MAGE", cards = {} }

  local ok, why = c:CanAdd(deck, "EX1_354")
  H.notOk(ok, "another class")
  H.eq(why, "another class", "named as such")

  c:Add("EX1_116", 1)
  deck.cards = { "EX1_116" }
  local ok2, why2 = c:CanAdd(deck, "EX1_116")
  H.notOk(ok2, "a second legendary")
  H.ok(why2:find("legendary"), "named as such: " .. tostring(why2))

  deck.cards = {}
  for i = 1, 30 do deck.cards[i] = "CS2_231" end
  local ok3, why3 = c:CanAdd(deck, "CS2_182")
  H.notOk(ok3, "a full deck")
  H.eq(why3, "deck is full", "named as such")
end)

H.suite("collection: the active deck is dropped if it stops being legal", function(ns, H)
  --[[ A deck can become illegal after it was built -- disenchant a card out
       from under it -- and discovering that at the start of a duel is much
       worse than discovering it here. ]]
  local c = newCollection(ns, "MAGE")
  c:GrantForLevel("MAGE", 1)
  local deck = c:NewDeck("Basic", "MAGE")
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.set == "CORE" and p.class == "NEUTRAL" then
      for _ = 1, 2 do
        if #deck.cards < 30 and c:CanAdd(deck, id) then deck.cards[#deck.cards + 1] = id end
      end
    end
  end
  c.character.activeDeck = 1
  H.ok(c:ActiveDeck(), "a legal deck is returned")

  table.remove(deck.cards)
  local active, broken = c:ActiveDeck()
  H.eq(active, nil, "a 29-card deck is not returned")
  H.ok(broken, "but it is handed back so the player can be told which one")
end)

--=========================================================== packs

H.suite("packs: the odds table sums to 100", function(ns, H)
  --[[ A table summing to 97 silently makes the last entry more likely, and
       nobody would ever notice by playing. ]]
  local total = 0
  for _, o in ipairs(ns.Packs.ODDS) do total = total + o.pct end
  H.eq(total, 100, "rarity odds total 100%")
end)

H.suite("packs: a pack is five neutral cards from the combined sets", function(ns, H)
  local pack = ns.Packs.Generate("CLASSIC", { rng = seededRng(7) })
  H.eq(#pack.cards, 5, "five cards")
  for _, c in ipairs(pack.cards) do
    local p = ns.PrintedCards[c.cardId]
    H.eq(p.class, "NEUTRAL", p.name .. " is neutral -- packs never award class cards (D4)")
    H.ok(p.set == "EXPERT1" or p.set == "GVG" or p.set == "NAXX", p.name .. " is from a pack set")
    H.ok(p.collectible, p.name .. " is collectible")
  end
end)

H.suite("packs: legacy GvG packs draw from the combined pool", function(ns, H)
  local pack = ns.Packs.Generate("GVG", { rng = seededRng(11) })
  for _, c in ipairs(pack.cards) do
    local set=ns.PrintedCards[c.cardId].set
    H.ok(set == "GVG" or set == "EXPERT1" or set == "NAXX", "from the combined pool")
  end
  H.eq(ns.Packs.SETS.NAXX, nil,
       "and Naxxramas is NOT a pack type -- 21 neutrals is too shallow a pool (docs/04)")
end)

H.suite("packs: every pack contains a rare or better", function(ns, H)
  --[[ Hearthstone's one pack rule worth keeping whatever else the economy
       does: a pack is never nothing. Rolled 2,000 times, because a guarantee
       that holds "usually" is not a guarantee. ]]
  local rng = seededRng(99)
  local ORDER = { COMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }
  local worst = 99
  for _ = 1, 2000 do
    local pack = ns.Packs.Generate("CLASSIC", { rng = rng })
    local best = 0
    for _, c in ipairs(pack.cards) do best = math.max(best, ORDER[c.rarity] or 0) end
    worst = math.min(worst, best)
  end
  H.ok(worst >= ORDER.RARE, "the worst pack in 2,000 still held a rare or better")
end)

H.suite("packs: resting changes nothing about a pack", function(ns, H)
  -- the old rested bonus (epic floor, +25 dust) is gone: packs open as Hearthstone's do
  local c = newCollection(ns)
  c:AddPack("CLASSIC", 1)
  local dustBefore = c:Dust()
  local pack = ns.Packs.Open(c, "CLASSIC", { rng = seededRng(3), rested = true })
  H.eq(pack.restedDust, nil, "no dust for opening it rested")
  local gained = 0
  for _, card in ipairs(pack.cards) do gained = gained + (card.dust or 0) end
  H.eq(c:Dust(), dustBefore + gained, "only duplicates turn into dust")
  H.eq(ns.Packs.RESTED_DUST, nil)
end)

H.suite("packs: opening banks the cards and spends the pack", function(ns, H)
  local c = newCollection(ns)
  c:AddPack("CLASSIC", 1)
  local pack = ns.Packs.Open(c, "CLASSIC", { rng = seededRng(5) })
  H.ok(pack, "opened")
  H.eq(c:PackCount("CLASSIC"), 0, "the pack is spent")
  for _, card in ipairs(pack.cards) do
    H.ok(c:Count(card.cardId) > 0, card.cardId .. " is in the collection")
  end
  H.eq(c.account.stats.packsOpened, 1, "and it was counted")

  local nothing, why = ns.Packs.Open(c, "CLASSIC", { rng = seededRng(5) })
  H.eq(nothing, nil, "a second open with no packs is refused")
  H.ok(why:find("no HEARTHSTONE packs"), "and says so")
end)

H.suite("packs: the legendary tell points at the real card", function(ns, H)
  --[[ In Hearthstone the anticipation IS the pleasure -- the reveal is over in
       300ms. A tell that pointed at a random card would be a lie the player
       eventually notices. ]]
  local rng = seededRng(42)
  for _ = 1, 200 do
    local pack = ns.Packs.Generate("CLASSIC", { rng = rng })
    local told = pack.cards[pack.tellIndex]
    H.eq(told.rarity, pack.bestRarity, "the glowing card is the best one in the pack")
  end
end)

H.suite("packs: promo cards never turn up in a pack", function(ns, H)
  -- They have their own acquisition paths (docs/03 D1); a lottery ticket in a
  -- pack would replace the chase rather than add to it.
  for _, set in ipairs({ "EXPERT1", "GVG" }) do
    for _, rarity in ipairs({ "COMMON", "RARE", "EPIC", "LEGENDARY" }) do
      for _, id in ipairs(ns.Packs.Pool(set, rarity)) do
        H.notOk(ns.PrintedCards[id].unobtainable, id .. " is obtainable")
      end
    end
  end
end)

--=========================================================== drops

H.suite("drops: grey mobs are worth nothing", function(ns, H)
  --[[ THE GATE THIS FILE INSISTS ON. Without it the optimal farm is a level-60
       character cleaving level-12 mobs, which is faster per kill than anything
       level-appropriate. ]]
  local ok, why = ns.Drops.Eligible({ kind = "normal", playerLevel = 60 - 1, grantsXP = false })
  H.notOk(ok, "no XP, no packs")
  H.ok(why:find("XP"), "and it says why, because that is the first question asked")
  H.ok(ns.Drops.Eligible({ kind = "normal", playerLevel = 30, grantsXP = true }),
       "an XP-granting kill is eligible")
end)

H.suite("drops: at 60 the gate becomes mob level", function(ns, H)
  -- Nothing grants XP at max level, so the rule has to become something else or
  -- the endgame stops dropping entirely.
  H.notOk(ns.Drops.Eligible({ kind = "normal", playerLevel = 60, mobLevel = 20 }),
          "a level-20 mob is worth nothing to a 60")
  H.ok(ns.Drops.Eligible({ kind = "normal", playerLevel = 60, mobLevel = 58 }),
       "a level-58 one is")
  H.ok(ns.Drops.Eligible({ kind = "boss", playerLevel = 60, mobLevel = 1 }),
       "and a boss always is, whatever level it reports")
end)

H.suite("drops: critters, totems and summons are worth nothing", function(ns, H)
  H.notOk(ns.Drops.Eligible({ kind = "critter", playerLevel = 10, grantsXP = true }),
          "critters: trivial HP, infinite farm")
  H.notOk(ns.Drops.Eligible({ kind = "normal", creatureType = "Totem",
                              playerLevel = 10, grantsXP = true }),
          "totems -- or a Shaman drop-farms their own")
  H.notOk(ns.Drops.Eligible({ kind = "normal", summoned = true,
                              playerLevel = 10, grantsXP = true }),
          "and anything summoned")
end)

H.suite("drops: the rate is the rate, over a hundred thousand kills", function(ns, H)
  --[[ The only honest way to check a 1.5% rate. 100,000 seeded kills, asserted
       within a tolerance wide enough never to flake and narrow enough to catch
       a rate that is actually 2%. ]]
  local rng = seededRng(2024)
  local kill = { kind = "normal", playerLevel = 30, grantsXP = true }
  local hits = 0
  for _ = 1, 100000 do
    if ns.Drops.Roll(kill, rng) then hits = hits + 1 end
  end
  local pct = hits / 1000
  H.ok(pct > 1.33 and pct < 1.67, ("normal mobs dropped %.2f%% of the time"):format(pct))

  local elite = { kind = "elite", playerLevel = 30, grantsXP = true }
  hits = 0
  for _ = 1, 100000 do
    if ns.Drops.Roll(elite, rng) then hits = hits + 1 end
  end
  pct = hits / 1000
  H.ok(pct > 3.6 and pct < 4.4, ("elites dropped %.2f%% of the time"):format(pct))

  H.ok(math.abs(ns.Drops.KillsPerReward("normal") - 66.7) < 0.1, "about 67 kills a reward, as tuned (docs/13)")
end)

H.suite("drops: a boss is the Naxxramas source", function(ns, H)
  --[[ docs/04. This is what gives the 5% boss rate a purpose beyond being a
       better mob, and it fits a WoW addon far better than a third pack icon for
       a 21-card pool. ]]
  local rng = seededRng(17)
  local kill = { kind = "boss", playerLevel = 60, mobLevel = 63 }
  local seen = 0
  for _ = 1, 400 do
    local r = ns.Drops.Roll(kill, rng)
    if r then
      H.eq(r.kind, "PACK", "boss rewards are packs")
      H.eq(r.set, "HEARTHSTONE", "combined pack")
      seen = seen + 1
    end
  end
  H.ok(seen > 0, ("bosses dropped %d times in 400"):format(seen))
end)

H.suite("drops: what you kill biases what you get", function(ns, H)
  --[[ "Kill yetis, get a Yeti" from the brief, expressed as data rather than a
       list of special cases: the creature type maps to a card race. ]]
  H.eq(ns.Drops.RaceFor("Beast"), "BEAST", "beasts map to Beasts")
  H.eq(ns.Drops.RaceFor("Dragonkin"), "DRAGON", "dragonkin to Dragons")
  H.eq(ns.Drops.RaceFor("Humanoid"), nil,
       "and an ambiguous type has NO bias rather than a wrong one")

  local c = newCollection(ns)
  local rng = seededRng(5150)
  local beasts, total = 0, 0
  for _ = 1, 200 do
    local got = ns.Drops.Grant(c, { kind = "CARD", set = "EXPERT1", race = "BEAST" }, rng)
    if got then
      total = total + 1
      if ns.PrintedCards[got.cardId].race == "BEAST" then beasts = beasts + 1 end
    end
  end
  H.ok(total > 0, "cards dropped")
  H.ok(beasts > total * 0.8, ("%d of %d were Beasts"):format(beasts, total))
end)

H.suite("drops: granting a card completes a collection trigger", function(ns, H)
  --[[ Old Murk-Eye's real Hearthstone condition is "collect every Murloc",
       which maps exactly onto this recreation (docs/03 D1). Note it is a
       COLLECTION trigger and not a kill trigger, because murlocs in WoW are
       Humanoid -- no creature type could ever name them. ]]
  local c = newCollection(ns)
  local murlocs = {}
  for id, p in pairs(ns.PrintedCards) do
    if p.collectible and p.race == "MURLOC" and id ~= "EX1_062" then murlocs[#murlocs+1] = id end
  end
  table.sort(murlocs)
  H.ok(#murlocs > 0, ("the pool has %d other Murlocs"):format(#murlocs))

  for i = 1, #murlocs - 1 do c:Add(murlocs[i], 1) end
  H.eq(#ns.Packs.CheckTriggers(c), 0, "one Murloc short grants nothing")
  c:Add(murlocs[#murlocs], 1)
  local granted = ns.Packs.CheckTriggers(c)
  H.eq(#granted, 1, "the last one grants the reward")
  H.eq(granted[1], "EX1_062", "which is Old Murk-Eye")
  H.eq(#ns.Packs.CheckTriggers(c), 0, "and it is never granted twice")
end)

H.suite("drops: a rolled reward becomes a real change to the collection", function(ns, H)
  local c = newCollection(ns)
  local got = ns.Drops.Grant(c, { kind = "PACK", set = "CLASSIC" })
  H.eq(got.kind, "PACK", "a pack was banked")
  H.eq(c:PackCount("CLASSIC"), 1, "and it is there to open")
  H.eq(got.total, 1, "the toast knows how many you now have")

  local card = ns.Drops.Grant(c, { kind = "CARD", set = "EXPERT1" }, seededRng(8))
  H.eq(card.kind, "CARD", "a card arrived")
  H.ok(c:Count(card.cardId) > 0, "and is in the collection")
end)

H.suite("packs: migration preserves unopened packs exactly once",function(ns,H)
  local account={packs={CLASSIC=3,GVG=4,HEARTHSTONE=2}}
  local c=ns.Collection.New(account,{class="ROGUE"})
  H.eq(c:TotalPacks(),9); H.eq(c:PackCount("HEARTHSTONE"),9)
  c=ns.Collection.New(account,{class="ROGUE"})
  H.eq(c:TotalPacks(),9,"reload does not migrate twice")
  H.ok(ns.Packs.Open(c,"HEARTHSTONE",{rng=seededRng(13)}))
  H.eq(c:TotalPacks(),8); H.eq(c.account.stats.packsOpened,1)
  c:AddPack("GVG",1); H.eq(c:TotalPacks(),9,"legacy rewards enter the same stack")
  local seen={}
  for i=1,100 do
    local pack=ns.Packs.Generate("HEARTHSTONE",{rng=seededRng(i)})
    for _,card in ipairs(pack.cards) do seen[ns.PrintedCards[card.cardId].set]=true end
  end
  H.ok(seen.EXPERT1 and seen.GVG,"both sets appear")
  H.ok(seen.NAXX,"Naxxramas neutrals are obtainable in packs")
end)
H.suite("collection: deleting a deck preserves later active deck identity",function(ns,H)
  local c=newCollection(ns)
  c:NewDeck("First"); local second=c:NewDeck("Second")
  c.character.activeDeck=2
  H.ok(c:DeleteDeck(1)); H.eq(c.character.activeDeck,1)
  H.eq(c.character.decks[c.character.activeDeck],second)
  c:DeleteDeck(1); H.eq(c.character.activeDeck,nil)
end)

H.suite("reward track: every class milestone matches actual level grants",function(ns,H)
  for _,class in ipairs(ns.CLASSES) do
    local c=ns.Collection.New({}, {class=class})
    local track=c:LevelRewardTrack(class)
    H.eq(#track,60)
    for level,row in ipairs(track) do
      local expected={}
      for _,r in ipairs(row.rewards) do
        if r.kind=="CARD" then expected[r.cardId]=r.count end
      end
      local got={}
      for _,id in ipairs(c:GrantForLevel(class,level)) do
        if ns.PrintedCards[id].class==class and ns.PrintedCards[id].set~="CORE" then got[id]=c:Count(id) end
      end
      for id,count in pairs(expected) do H.eq(got[id],count) end
      for id,count in pairs(got) do H.eq(expected[id],count) end
      local packs=c:GrantPacksForLevel(level)
      local shown=0; for _,r in ipairs(row.rewards) do if r.kind=="PACK" then shown=shown+r.count end end
      H.eq(shown,packs)
      H.ok(#row.rewards<=3,"visible slots hold every reward")
    end
  end
end)

H.suite("reward track: starter decks never contain future class unlocks",function(ns,H)
  for _,class in ipairs(ns.CLASSES) do
    for level=1,60 do
      local c=ns.Collection.New({}, {class=class})
      c:GrantForLevel(class,level)
      local deck=c:EnsureDefaultDeck(class)
      H.ok(deck); H.ok(c:ValidateDeck(deck))
      local unlocked={}
      for _,row in ipairs(c:LevelRewardTrack(class)) do
        if row.level<=level then for _,r in ipairs(row.rewards) do if r.cardId then unlocked[r.cardId]=true end end end
      end
      for _,id in ipairs(deck.cards) do
        local p=ns.PrintedCards[id]
        H.eq(p.set,"CORE","starter contains Basic cards only")
        H.ok(c:Count(id)>=2,"every starter card is available from creation")
      end
    end
  end
end)

H.suite("progression: starter Basics never reappear as level unlocks",function(ns,H)
  for _,class in ipairs(ns.CLASSES) do
    local c=ns.Collection.New({}, {class=class})
    c:GrantForLevel(class,1)
    local deck=c:EnsureDefaultDeck(class)
    local starting={}; for id in pairs(c.character.cards) do starting[id]=true end
    local basic=0; for _ in pairs(starting) do basic=basic+1 end
    H.eq(basic,10)
    local total=0
    for _,row in ipairs(c:LevelRewardTrack(class)) do
      for _,r in ipairs(row.rewards) do
        if r.cardId then H.notOk(starting[r.cardId]); total=total+1 end
      end
    end
    H.eq(total,24,"24 distinct non-starter unlocks")
    H.eq(#c:GrantForLevel(class,2),0)
    H.eq(#c:GrantForLevel(class,3),1)
    H.eq(#c:GrantForLevel(class,3),0,"no duplicate grants")
    H.ok(c:ValidateDeck(deck))
  end
end)

H.suite("progression: existing cards survive catch-up without duplicate copies",function(ns,H)
  local c=ns.Collection.New({}, {class="ROGUE"})
  local curve=c:ClassCurve("ROGUE")
  local seen={BASIC=0,CLASSIC=0,LATE=0}
  -- Reconstruct the former level-17 entitlement: 10 Basics and 4 Classics.
  for _,entry in ipairs(curve) do
    seen[entry.band]=seen[entry.band]+1
    if entry.band=="BASIC" or (entry.band=="CLASSIC" and seen.CLASSIC<=4) then c:Add(entry.id,c:MaxCopies(entry.id)) end
  end
  c:Add("EX1_613",1) -- previously earned or crafted ahead of the new schedule
  local before={}; for id in pairs(c.character.cards) do before[id]=c:Count(id) end
  c:GrantForLevel("ROGUE",17)
  for id,count in pairs(before) do H.ok(c:Count(id)>=count,"no owned cards removed") end
  local b,classic,late=ns.Collection.GrantsAtLevel(17)
  H.eq(b,10); H.eq(classic,8); H.eq(late,0)
  H.eq(#c:GrantForLevel("ROGUE",17),0)
  local _,at31=ns.Collection.GrantsAtLevel(31); H.eq(at31,15)
  local _,_,at36=ns.Collection.GrantsAtLevel(36); H.eq(at36,1)
  local _,_,at60=ns.Collection.GrantsAtLevel(60); H.eq(at60,9)
end)

H.suite("drops: every successful kill reward is a pack", function(ns,H)
  for _,kind in ipairs({"normal","elite","rare","boss"}) do
    local c=ns.Collection.New({}, {})
    for i=1,200 do
      local reward=ns.Drops.Roll({kind=kind,playerLevel=60,mobLevel=60,guaranteed=true},seededRng(i))
      H.eq(reward.kind,"PACK")
      ns.Drops.Grant(c,reward,seededRng(i))
    end
    H.eq(c:TotalPacks(),200)
    H.eq(c.account.stats.cardsDropped,0)
  end
end)
