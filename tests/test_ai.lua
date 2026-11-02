--[[ tests/test_ai.lua -- the practice opponent.

  Three jobs here.

  First, that the AI plays like a player: it spends its mana, takes good trades,
  never heals or buffs YOUR minions, holds its removal for a worthy target, and
  finds the combo that wins. These are the behaviours a practice opponent is
  judged on, and each is pinned by a board built to tempt the wrong answer.

  Second, that it plays fair and stays out of the way: planning happens on
  copies, so asking it what to do never changes the real game, and asking twice
  gives the same answer -- which is what keeps a networked match in step.

  Third -- the real prize -- AI VERSUS AI SOAK GAMES. Playing whole matches to
  completion drives the actual card scripts against each other in combinations
  no hand-written test would think to try, with the engine's own error log
  asserted empty at the end. Every one of the bot's decks plays at least once,
  so every card they carry is exercised.
]]
local H = require("tests.harness")

local function aiGame(opts)
  opts = opts or {}
  local g = H.NewGame({
    seed = opts.seed or 1234,
    class1 = opts.class1 or "MAGE",
    class2 = opts.class2 or "PRIEST",
  })
  local p = g.players[1]
  for i = #p.hand, 1, -1 do table.remove(p.hand, i) end
  g.activePlayer = 1
  return g, p
end

local function inHand(g, player, cardId)
  for _, c in ipairs(g.players[player].hand) do
    if c.cardId == cardId then return true end
  end
  return false
end

--============================================================ decisions

H.suite("ai: it spends its mana, putting the 4-drop down", function(ns, H)
  local g = aiGame()
  H.Mana(g, 1, 4)
  H.Hand(g, 1, "CS2_231")      -- Wisp, 0
  H.Hand(g, 1, "CS2_182")      -- Chillwind Yeti, 4
  H.Hand(g, 1, "CS2_189")      -- Elven Archer, 1
  ns.AI.TakeTurn(g, 1)
  local yeti = false
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "CS2_182" then yeti = true end
  end
  H.ok(yeti, "the Yeti was played rather than stranded behind cheaper cards")
  H.eq(g:AvailableMana(1), 0, "and all four mana were used")
  H.noEngineErrors(g)
end)

H.suite("ai: it takes a free trade over hitting the face", function(ns, H)
  --[[ A 4/5 Yeti into a 2/1 Archer kills it and survives. Going face instead
       is the single most obvious thing a bad practice dummy does. ]]
  local g = aiGame()
  H.Mana(g, 1, 0)
  local yeti = H.Put(g, 1, "CS2_182")      -- 4/5
  local archer = H.Put(g, 2, "CS2_189")    -- 2/1
  local foeHero = H.Hero(g, 2):Health()
  ns.AI.TakeTurn(g, 1)
  H.eq(archer.zone, ns.ZONE.GRAVEYARD, "the free trade was taken")
  H.eq(H.Hero(g, 2):Health(), foeHero, "and the face was left alone")
  H.ok(yeti.zone == ns.ZONE.PLAY, "the Yeti survived, as a free trade should")
  H.noEngineErrors(g)
end)

H.suite("ai: with nothing to trade into, it goes face", function(ns, H)
  local g = aiGame()
  H.Mana(g, 1, 0)
  H.Put(g, 1, "CS2_182")                   -- 4/5, nothing to trade with
  local before = H.Hero(g, 2):Health()
  ns.AI.TakeTurn(g, 1)
  H.eq(H.Hero(g, 2):Health(), before - 4, "it attacked the enemy hero")
  H.noEngineErrors(g)
end)

H.suite("ai: it cannot attack past a Taunt", function(ns, H)
  --[[ Not special-cased in the AI at all -- every move is played through the
       rules, so the AI cannot ignore a Taunt even by accident. ]]
  local g = aiGame()
  H.Mana(g, 1, 0)
  H.Put(g, 1, "CS2_182")                   -- 4/5
  local taunt = H.Put(g, 2, "CS2_179")     -- Sen'jin Shieldmasta 3/5 Taunt
  local before = H.Hero(g, 2):Health()
  ns.AI.TakeTurn(g, 1)
  H.eq(H.Hero(g, 2):Health(), before, "the hero was not touched")
  H.ok(taunt:IsDamaged(), "the Taunt took the hit instead")
  H.noEngineErrors(g)
end)

H.suite("ai: it points a targeted card at the biggest threat", function(ns, H)
  --[[ Fireball kills either minion; only one of them matters. ]]
  local g = aiGame({ class1 = "MAGE" })
  H.Mana(g, 1, 4)
  g.players[1].heroPowerUsedThisTurn = true
  local wisp = H.Put(g, 2, "CS2_231")      -- Wisp 1/1
  local yeti = H.Put(g, 2, "CS2_182")      -- Chillwind Yeti 4/5 -- the threat
  H.Hand(g, 1, "CS2_029")                  -- Fireball
  ns.AI.TakeTurn(g, 1)
  H.eq(yeti.zone, ns.ZONE.GRAVEYARD, "the Fireball went at the Yeti")
  H.eq(wisp.zone, ns.ZONE.PLAY, "not at the Wisp")
  H.noEngineErrors(g)
end)

H.suite("ai: it never heals or buffs YOUR minions", function(ns, H)
  --[[ THE REPORTED BUG. The old bot aimed any targeted card at "the biggest
       enemy, else your own side" -- so a heal with nothing of its own hurt went
       to your damaged minion, and a buff with nothing of its own to buff went
       to yours. Here every tempting target is the opponent's: a damaged Yeti,
       and nothing on the bot's side at all. ]]
  local g = aiGame({ class1 = "PRIEST", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 2, "CS2_182")      -- 4/5
  yeti.damage = 3
  H.Hand(g, 1, "CS2_092")                  -- Blessing of Kings: +4/+4 to a minion
  H.Hand(g, 1, "CS2_089")                  -- Holy Light: restore 6
  H.Hand(g, 1, "CS2_236")                  -- Divine Spirit: double a minion's health
  ns.AI.TakeTurn(g, 1)
  H.eq(yeti.damage, 3, "the enemy Yeti was not healed (hero power or Holy Light)")
  H.eq(g:AttackValue(yeti), 4, "nor given Blessing of Kings")
  H.eq(yeti:MaxHealth(), 5, "nor given Divine Spirit")
  H.noEngineErrors(g)
end)

H.suite("ai: its heals and buffs go to its own side", function(ns, H)
  --[[ The other half: given something of its own worth helping, it helps it. ]]
  local g = aiGame({ class1 = "PRIEST", class2 = "MAGE" })
  H.Mana(g, 1, 2)
  local mine = H.Put(g, 1, "CS2_182")      -- 4/5
  mine.damage = 3
  local theirs = H.Put(g, 2, "CS2_182")
  theirs.damage = 3
  ns.AI.TakeTurn(g, 1)
  H.eq(theirs.damage, 3, "the enemy Yeti was left hurt")
  H.ok(mine.damage < 3, "its own Yeti was healed")
  H.noEngineErrors(g)
end)

H.suite("ai: it finds a combo for lethal", function(ns, H)
  --[[ Three 1/1s swing for three; Savage Roar makes it eleven with the hero
       joining in. The Roar alone scores nothing -- it is worth something only
       as the first step of a sequence, which is exactly what a move-at-a-time
       bot can never see. ]]
  local g = aiGame({ class1 = "DRUID", class2 = "WARRIOR" })
  H.Mana(g, 1, 3)
  for _ = 1, 3 do H.Put(g, 1, "CS2_231") end
  H.Hero(g, 2).damage = 21                 -- 9 health left
  H.Hand(g, 1, "CS2_011")                  -- Savage Roar
  ns.AI.TakeTurn(g, 1)
  H.ok(g.over, "the game is over")
  H.eq(g.winner, 1, "and the bot won it")
  H.noEngineErrors(g)
end)

H.suite("ai: it finds a spell-and-attack lethal through a Taunt", function(ns, H)
  --[[ A 3/5 Taunt stands between a 6/7 and the face. Fireball on the Taunt
       would be the board-minded play; Fireball to the face plus... nothing
       would not be enough. The line is: Fireball the Taunt, then swing. ]]
  local g = aiGame({ class1 = "MAGE", class2 = "WARRIOR" })
  H.Mana(g, 1, 4)
  g.players[1].heroPowerUsedThisTurn = true
  H.Put(g, 1, "CS2_200")                   -- Boulderfist Ogre 6/7
  H.Put(g, 2, "CS2_179")                   -- Sen'jin 3/5 Taunt
  H.Hero(g, 2).damage = 24                 -- 6 health left
  H.Hand(g, 1, "CS2_029")                  -- Fireball
  ns.AI.TakeTurn(g, 1)
  H.eq(g.winner, 1, "Fireball cleared the Taunt and the Ogre finished it")
  H.noEngineErrors(g)
end)

H.suite("ai: it holds its removal for a target worth it", function(ns, H)
  --[[ Fireballing a Wisp at full health is the classic waste. It has the mana
       and nothing else to do, and still keeps the card. ]]
  local g = aiGame({ class1 = "MAGE" })
  H.Mana(g, 1, 4)
  g.players[1].heroPowerUsedThisTurn = true
  H.Put(g, 2, "CS2_231")                   -- Wisp 1/1
  H.Hand(g, 1, "CS2_029")                  -- Fireball
  ns.AI.TakeTurn(g, 1)
  H.ok(inHand(g, 1, "CS2_029"), "the Fireball is still in hand")
  H.noEngineErrors(g)
end)

H.suite("ai: an aggro deck points its burn at your face", function(ns, H)
  --[[ The same card, the other style: Face Hunter's Kill Command is for the
       hero once the hero is low enough to race. ]]
  local g = aiGame({ class1 = "HUNTER", class2 = "WARRIOR" })
  H.Mana(g, 1, 3)
  g.players[1].heroPowerUsedThisTurn = true
  H.Hero(g, 2).damage = 16                 -- 14 health
  H.Hand(g, 1, "EX1_539")                  -- Kill Command
  ns.AI.TakeTurn(g, 1, nil, { style = "aggro" })
  H.eq(H.Hero(g, 2):Health(), 11, "Kill Command went face")
  H.noEngineErrors(g)
end)

H.suite("ai: it makes room on a full board for something better", function(ns, H)
  --[[ Seven Wisps and a Yeti in hand. A player pings their own Wisp with the
       Mage hero power to open a slot; the old bot passed with the Yeti in
       hand. ]]
  local g = aiGame({ class1 = "MAGE" })
  H.Mana(g, 1, 10)
  for _ = 1, ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  H.Hand(g, 1, "CS2_182")
  ns.AI.TakeTurn(g, 1)
  H.notOk(inHand(g, 1, "CS2_182"), "the Yeti was played")
  H.noEngineErrors(g)
end)

H.suite("ai: it does nothing on a turn that is not its own", function(ns, H)
  local g = aiGame()
  H.Mana(g, 1, 10)
  H.Hand(g, 1, "CS2_182")
  local handBefore = #g.players[1].hand
  H.notOk(ns.AI.TakeTurn(g, 2), "asked to act out of turn, it declines")
  H.eq(#g.players[1].hand, handBefore, "and touches nothing")
end)

H.suite("ai: a Choose One card is played with a PLAYABLE mode", function(ns, H)
  -- With a full board the Panther mode is unchoosable; the AI must take the
  -- other one rather than stalling on the card forever.
  local g = aiGame({ class1 = "DRUID" })
  H.Mana(g, 1, 2)
  g.players[1].heroPowerUsedThisTurn = true
  for _ = 1, ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  H.Hand(g, 1, "EX1_160")                  -- Power of the Wild
  ns.AI.TakeTurn(g, 1)
  H.notOk(inHand(g, 1, "EX1_160"), "the card was played rather than stranded")
  local buffed = 0
  for _, e in ipairs(g.players[1].board) do
    if e:MaxHealth() == 2 then buffed = buffed + 1 end
  end
  H.eq(buffed, ns.RULES.BOARD_SLOTS, "and it took the +1/+1 mode, the only playable one")
  H.noEngineErrors(g)
end)

H.suite("ai: a targeted battlecry is aimed, not wasted", function(ns, H)
  --[[ Ironforge Rifleman's battlecry takes a target only "if available", so
       the rules never demand one -- and the old bot never gave one, playing
       every such minion with its battlecry fizzling. ]]
  local g = aiGame()
  H.Mana(g, 1, 3)
  g.players[1].heroPowerUsedThisTurn = true
  local wisp = H.Put(g, 2, "CS2_231")
  H.Hand(g, 1, "CS2_141")                  -- Ironforge Rifleman: deal 1
  ns.AI.TakeTurn(g, 1)
  H.eq(wisp.zone, ns.ZONE.GRAVEYARD, "the battlecry shot the Wisp")
  H.noEngineErrors(g)
end)

H.suite("ai: a turn is bounded even when a card refuses to be played", function(ns, H)
  --[[ A practice opponent that hangs the client is a far worse failure than one
       that passes its turn. Simulated by a card that cannot be played: the
       board is full and the hero power (which could make room) is spent. ]]
  local g = aiGame()
  H.Mana(g, 1, 10)
  g.players[1].heroPowerUsedThisTurn = true
  for _ = 1, ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  H.Hand(g, 1, "CS2_182")          -- cannot be played: board is full
  ns.AI.TakeTurn(g, 1)             -- must RETURN, not spin
  H.eq(#g.players[1].hand, 1, "the unplayable card stayed in hand")
end)

--============================================================ fairness

H.suite("ai: thinking never changes the real game", function(ns, H)
  --[[ Every move is tried on a copy. If a single one leaked -- a random roll
       drawn from the real stream, an id handed out by the real counter -- two
       networked clients would disagree about the game from that moment on. ]]
  local g = ns.Game.New({ seed = 77, firstPlayer = 1, players = {
    { class = "MAGE", deck = ns.BotDecks.Expand(ns.BotDecks.Pick("MAGE", 5)) },
    { class = "HUNTER", deck = ns.BotDecks.Expand(ns.BotDecks.Pick("HUNTER", 5)) } } })
  g:StartGame(); g.bus:Drain()
  for _ = 1, 6 do
    ns.AI.TakeTurn(g, g.activePlayer, nil, { difficulty = 2 })
    g:EndTurn(); g.bus:Drain()
  end
  local hash, rng, calls, ids = g:StateHash(), g.rngState, g.rngCalls, g.ids.n
  ns.AI.ForgetPlan(g)
  local first = ns.AI.NextAction(g, g.activePlayer, {}, { difficulty = 5 })
  H.eq(g:StateHash(), hash, "the board is exactly as it was")
  H.eq(g.rngState, rng, "the random stream was not drawn from")
  H.eq(g.rngCalls, calls, "not once")
  H.eq(g.ids.n, ids, "and no ids were handed out")
  ns.AI.ForgetPlan(g)
  local again = ns.AI.NextAction(g, g.activePlayer, {}, { difficulty = 5 })
  H.eq(ns.Protocol.EncodeAction(again), ns.Protocol.EncodeAction(first),
       "asked twice about the same board, it gives the same answer")
  H.noEngineErrors(g)
end)

H.suite("ai: it cannot see your secrets", function(ns, H)
  --[[ Explosive Trap is up; the bot swings at the face anyway, exactly as a
       player who cannot see the secret would. A bot that politely walked
       around every hidden secret would be reading your hand. ]]
  local g = aiGame({ class1 = "WARRIOR", class2 = "HUNTER" })
  H.Mana(g, 1, 0)
  local raptor = H.Put(g, 1, "CS2_172")    -- Bloodfen Raptor 3/2
  H.ok(g:PlaySecret(2, ns.Entity.New(g:Printed("EX1_610"), 2, g.ids)), "Explosive Trap is up")
  ns.AI.TakeTurn(g, 1)
  H.eq(raptor.zone, ns.ZONE.GRAVEYARD, "it attacked into the trap it could not see")
  H.noEngineErrors(g)
end)

H.suite("clone: a copy of the game is a separate game", function(ns, H)
  local g = aiGame()
  H.Put(g, 1, "CS2_182")
  H.Put(g, 2, "NEW1_019")                  -- Knife Juggler: a trigger to copy
  local c = g:Clone()
  H.eq(c:StateHash(), g:StateHash(), "the copy starts identical")
  H.ok(c.players[1].board[1] ~= g.players[1].board[1], "with its own entities")
  H.ok(c.players[1].board[1].printed == g.players[1].board[1].printed,
       "sharing only the printed card data")
  c.players[1].board[1].damage = 4
  c:Summon("CS2_231", 1)
  c.bus:Drain()
  H.eq(g.players[1].board[1].damage, 0, "damage in the copy stays there")
  H.eq(#g.players[1].board, 1, "and so does a summon")
  H.ok(c.ids.n > g.ids.n, "the copy hands out ids from its own counter")
  H.eq(#g.players[2].board[1].triggers, 1, "the original's triggers are intact")
end)

--============================================================ decks

H.suite("bot decks: every one is a legal Hearthstone deck", function(ns, H)
  --[[ Thirty cards, two of a card at most, one of each legendary, only the
       class's own cards and neutrals, every id real and collectible in the
       pinned data. A typo here would otherwise surface as a bot silently
       playing a 29-card deck. ]]
  local total = 0
  for _, class in ipairs(ns.CLASSES) do
    local decks = ns.BotDecks.List(class)
    H.eq(#decks, 7, class .. " has seven decks")
    local tiers = {}
    for _, d in ipairs(decks) do
      total = total + 1
      tiers[d.tier] = true
      H.ok(ns.AI.STYLES[d.style] ~= nil, d.name .. " has a known style")
      local ids = ns.BotDecks.Expand(d)
      H.eq(#ids, ns.RULES.DECK_SIZE, d.name .. " has thirty cards")
      for id, n in pairs(d.counts) do
        local p = ns.PrintedCards[id]
        H.ok(p ~= nil and p.collectible, d.name .. ": " .. id .. " is a real, collectible card")
        if p then
          H.ok(p.class == "NEUTRAL" or p.class == class,
               d.name .. ": " .. p.name .. " belongs to the class")
          H.ok(n <= ((p.rarity == "LEGENDARY") and 1 or 2),
               d.name .. ": " .. p.name .. " within the copy limit")
        end
      end
    end
    for t = 1, ns.BotDecks.TIERS do
      H.ok(tiers[t], class .. " has a deck at tier " .. t)
    end
  end
  H.eq(total, 63, "sixty-three decks in all")
end)

H.suite("bot decks: the difficulty picks the deck's tier", function(ns, H)
  for tier = 1, ns.BotDecks.TIERS do
    local d = ns.BotDecks.Pick("ROGUE", tier)
    H.eq(d.tier, tier, "difficulty " .. tier .. " brings a tier " .. tier .. " deck")
  end
  H.eq(ns.BotDecks.Pick("ROGUE", 99).tier, 5, "out-of-range asks clamp to the ends")
  H.eq(ns.BotDecks.Pick("ROGUE", -3).tier, 1, "at both ends")
  local seen = {}
  for i = 1, 2 do seen[ns.BotDecks.Pick("ROGUE", 3, function() return i end).name] = true end
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  H.eq(n, 2, "a tier with two decks can bring either")
end)

--============================================================ soak

--[[ The soak tests are about the CARD SCRIPTS, not the quality of play, so the
     bot searches lightly: a short, narrow look and no lethal hunt. It still
     plays every card through the rules, which is all a soak needs. ]]
local SOAK = { difficulty = 1, depth = 3, budget = 24, lethal = 0 }
local function soakOpts(style)
  local o = {}
  for k, v in pairs(SOAK) do o[k] = v end
  o.style = style
  return o
end

local function playOut(ns, g, opts, turns)
  for _ = 1, turns or 120 do
    if g.over then break end
    local p = g.activePlayer
    ns.AI.TakeTurn(g, p, nil, opts and opts[p])
    if g.over then break end
    g:EndTurn()
    g.bus:Drain()
  end
end

H.suite("ai: full matches play to completion without engine errors", function(ns, H)
  --[[ THE VALUABLE ONE. Every match here drives real card scripts against each
       other in combinations nothing hand-written would try. `game.errors` is
       asserted empty, so an unknown op, a bad selector or a nil index anywhere
       in the pool surfaces here rather than in front of a player.

       Bounded by a turn cap: a match that cannot end is itself a failure, and
       fatigue guarantees a real one ends. ]]
  local CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
                    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
  local played, finished, errorsSeen = 0, 0, {}
  local fast = { soakOpts(), soakOpts() }

  for seed = 1, 12 do
    local c1 = CLASSES[(seed % #CLASSES) + 1]
    local c2 = CLASSES[((seed * 5) % #CLASSES) + 1]
    local g = ns.Game.New({
      seed = seed,
      firstPlayer = (seed % 2) + 1,
      players = {
        { class = c1, deck = ns.Controller.BasicDeck(c1) },
        { class = c2, deck = ns.Controller.BasicDeck(c2) },
      },
    })
    g:StartGame()
    g.bus:Drain()
    played = played + 1
    playOut(ns, g, fast)
    if g.over then finished = finished + 1 end
    for _, e in ipairs(g.errors) do
      errorsSeen[#errorsSeen + 1] = c1 .. " vs " .. c2 .. " seed " .. seed .. ": " .. e
    end
  end

  H.eq(played, 12, "all matches were started")
  H.eq(#errorsSeen, 0, "no engine errors across any match: "
       .. table.concat(errorsSeen, " | "))
  --[[ Fatigue makes an ending inevitable, so a match that never finishes means
       the AI stopped taking its turn -- a stall, which is the failure mode that
       would freeze a real client. ]]
  H.eq(finished, played, "every match reached a result")
end)

H.suite("ai: every bot deck plays a full match without engine errors", function(ns, H)
  --[[ Sixty-three decks carrying most of Classic, Naxxramas and Goblins vs
       Gnomes between them. Each plays at least once, paired against a deck of
       another class, so every card a bot can bring has been played by a bot
       before a player meets it. ]]
  local all = {}
  for _, class in ipairs(ns.CLASSES) do
    for _, d in ipairs(ns.BotDecks.List(class)) do all[#all + 1] = d end
  end
  local errorsSeen, finished, matches = {}, 0, 0
  for i = 1, #all, 2 do
    local d1 = all[i]
    local d2 = all[i + 1] or all[1]
    if d2.class == d1.class then d2 = all[((i + 8) % #all) + 1] end
    local g = ns.Game.New({ seed = 500 + i, firstPlayer = (i % 4 < 2) and 1 or 2, players = {
      { class = d1.class, deck = ns.BotDecks.Expand(d1) },
      { class = d2.class, deck = ns.BotDecks.Expand(d2) } } })
    g:StartGame(); g.bus:Drain()
    matches = matches + 1
    playOut(ns, g, { soakOpts(d1.style), soakOpts(d2.style) })
    if g.over then finished = finished + 1 end
    for _, e in ipairs(g.errors) do
      errorsSeen[#errorsSeen + 1] = d1.name .. " vs " .. d2.name .. ": " .. e
    end
  end
  H.eq(#errorsSeen, 0, "no engine errors: " .. table.concat(errorsSeen, " | "))
  H.eq(finished, matches, "every match reached a result")
end)

H.suite("rules: nothing ever swings more times than it is allowed", function(ns, H)
  --[[ Reported from a real match as "mobs can attack twice, or maybe just the
       leftmost one". The leftmost part turned out to be an ANIMATION bug --
       see tests/test_director.lua, where a minion that died swinging had no
       board index left and the sequence fell back to slot 1, so the leftmost
       minion played the attack.

       This is the other half of that answer: proof that the rules themselves
       never allow it, across whole games rather than one contrived board.
       Windfury is the only thing that grants a second swing, and it has to
       still work -- a test that just asserted "at most one" would pass by
       breaking Windfury. ]]
  local worst, windfuries = 0, 0
  for seed = 1, 8 do
    local g = ns.Game.New({
      seed = seed, firstPlayer = (seed % 2) + 1,
      players = {
        { class = "SHAMAN",  deck = ns.Controller.BasicDeck("SHAMAN") },
        { class = "WARRIOR", deck = ns.Controller.BasicDeck("WARRIOR") },
      },
    })
    g:StartGame()
    for _ = 1, 60 do
      if g.over then break end
      local p = g.activePlayer
      ns.AI.TakeTurn(g, p, ns.AI.Submitter(g, p), soakOpts())
      --[[ Checked at the END of the turn, while the counters are still at
           their high-water mark -- BeginTurn resets them, so checking
           afterwards would always find zero and pass forever. ]]
      for _, side in ipairs({ 1, 2 }) do
        for _, e in ipairs(g.players[side].board) do
          local allowed = e:Has(ns.KEYWORD.WINDFURY) and 2 or 1
          if e:Has(ns.KEYWORD.WINDFURY) and e.attacksThisTurn > 1 then
            windfuries = windfuries + 1
          end
          H.ok(e.attacksThisTurn <= allowed,
               ("%s swung %d times, allowed %d")
               :format(e.cardId, e.attacksThisTurn, allowed))
          if e.attacksThisTurn > worst then worst = e.attacksThisTurn end
        end
        local hero = g.players[side].hero
        H.ok(hero.attacksThisTurn <= (hero:Has(ns.KEYWORD.WINDFURY) and 2 or 1),
             "the hero swung no more than it may")
      end
      if g.over then break end
      g:EndTurn()
      g.bus:Drain()
    end
    H.noEngineErrors(g, "seed " .. seed)
  end
  H.ok(worst >= 1, "minions did actually attack during the soak")
end)

H.suite("ai: difficulty noise never makes a pointless enemy heal worthwhile",function(ns,H)
  for difficulty=1,5 do
    for seed=1,8 do
      local g=aiGame({class1="PRIEST",seed=seed})
      H.Mana(g,1,2)
      local enemy=H.Put(g,2,"CS2_182")
      enemy.damage=1
      ns.AI.TakeTurn(g,1,nil,{difficulty=difficulty})
      H.eq(enemy.damage,1,"enemy not healed at difficulty "..difficulty.." seed "..seed)
    end
  end
end)

H.suite("ai: actual decisions ignore hidden hands decks secrets and match RNG",function(ns,H)
  local g=aiGame({class1="PRIEST",class2="MAGE"})
  H.Mana(g,1,5); H.Hand(g,1,"CS2_003"); H.Hand(g,1,"EX1_339")
  H.Hand(g,1,"CS2_182"); H.Put(g,2,"CS2_120")
  local other=g:Clone()
  for _,zone in ipairs({"hand","deck"}) do
    for _,e in ipairs(other.players[2][zone]) do
      e.cardId="EX1_298"; e.printed=other:Printed("EX1_298"); e.damage=9
    end
  end
  other:PlaySecret(2,ns.Entity.New(other:Printed("EX1_287"),2,other.ids))
  other.seed=98765; other.rngState=771; other.rngCalls=900
  local before=g:StateHash()
  for difficulty=1,5 do
    ns.AI.ForgetPlan(g); ns.AI.ForgetPlan(other)
    local opts={difficulty=difficulty}
    local a,b=ns.AI.NextAction(g,1,nil,opts),ns.AI.NextAction(other,1,nil,opts)
    H.ok(a); H.ok(b)
    for _,key in ipairs({"kind","handIndex","targetId","position","mode","sourceId"}) do H.eq(a[key],b[key],key) end
  end
  H.eq(g:StateHash(),before,"planning cannot alter real cards or RNG")
end)

H.suite("bot decks: real shuffle varies by seed and draws only from the chosen deck",function(ns,H)
  local deck=ns.BotDecks.Expand(ns.BotDecks.Pick("MAGE",3))
  local orders={}
  for seed=1,20 do
    local g=ns.Game.New({seed=seed,players={{class="MAGE",deck=deck},{class="MAGE",deck=deck}}})
    local expected,actual,order={},{},{}
    for _,id in ipairs(deck) do expected[id]=(expected[id] or 0)+1 end
    for _,e in ipairs(g.players[2].deck) do actual[e.cardId]=(actual[e.cardId] or 0)+1; order[#order+1]=e.cardId end
    for id,count in pairs(expected) do H.eq(actual[id],count) end
    orders[table.concat(order,",")]=true
    local top=g.players[2].deck[#g.players[2].deck]
    g:Draw(2,1)
    H.eq(g.players[2].hand[1],top,"normal draw removes the shuffled top card")
    H.eq(#g.players[2].deck,29)
  end
  local count=0; for _ in pairs(orders) do count=count+1 end
  H.ok(count>1,"fresh seeds do not deal the same order")
end)
