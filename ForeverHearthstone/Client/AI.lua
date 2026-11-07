--[[ Client/AI.lua

  THE PRACTICE OPPONENT.

  Without this the practice match has nobody on the other side and the addon is
  a board you can play solitaire on. It is also the solo development loop: the
  fastest way to exercise a few hundred card scripts against each other is to
  let two of these play.

  NO WoW API. Like Engine/ and Controller.lua, this runs headless, so the
  opponent's decisions are testable in a terminal.

  IT DECIDES BY TRYING. The first version of this file read the situation off a
  few rules of thumb -- "aim a targeted card at the biggest enemy, or else at
  your own side" -- and that is how it came to heal and buff YOUR minions: a
  heal with no damaged enemy to aim at fell through to "your own side", and "your
  own side" from its seat was the wrong one half the time. No rule of thumb gets
  four hundred cards right.

  So now every candidate move is PLAYED, on a copy of the game (Game:Clone),
  through the same rules and the same card scripts, and the board that comes
  out is scored. Healing your minion makes your board better, so it scores
  badly and is never chosen. Cold Blood then an attack is lethal, so that line
  scores a win and is. Nothing here knows what any card does -- the engine does,
  and the bot simply asks it.

  A WHOLE TURN, NOT ONE MOVE. Combos are sequences whose first step looks bad on
  its own (the Coin, Savage Roar, Power Overwhelming), so moves are searched as
  SEQUENCES: a beam search keeps the few most promising partial turns at each
  step and extends them, and the best complete turn is played. A separate,
  narrower search looks for lethal first, because the move that wins is often
  one a board-minded search would not rank highly.

  IT PLAYS FAIR. The copies it plans on are fogged: its own deck is reshuffled
  (it cannot know its next draw), the random stream is reseeded (it cannot see
  how Arcane Missiles will land), and your secrets are removed (it cannot see
  them). Every decision still becomes an ACTION through Client/Actions.lua, so
  it cannot play a card it cannot afford or attack past a Taunt.

  IT PLAYS ITS DECK. Each bot deck (Client/BotDecks.lua) has a style, and the
  style weighs the evaluation: aggro counts your health as the thing that
  matters, control counts its own health and the board. The DIFFICULTY sets how
  far and how wide it searches, and at the bottom end adds the kind of mistakes
  a new player makes -- a slightly worse trade, a missed lethal -- never the
  kind no player makes.

  THE SUBMIT SEAM. Every turn takes a `submit` function, defaulting to "apply it
  to this game". That is what lets the same opponent drive a NETWORKED session
  in tests/test_net.lua -- its actions go over the wire like anyone else's.

  DETERMINISM. The bot never touches the real game's random stream: all of its
  randomness (sampling, the fog, a Novice's wobble) is derived from the game's
  state into its own copies. Asked twice about the same board it gives the same
  answer, and a networked opponent planning on its own client cannot desync the
  match.
]]
local ADDON, ns = ...

local AI = {}
ns.AI = AI

local MAX_ACTIONS = 40        -- a turn cannot loop forever, whatever happens
local COIN_ID = "GAME_005"
local KW, TYPE = ns.KEYWORD, ns.CARDTYPE

--[[ The default destination for the AI's actions: straight into this game.
     A networked match passes its own, which also puts them on the wire. ]]
function AI.Submitter(game, player)
  return function(action) return ns.Actions.Run(game, player, action) end
end

-- ============================================================ difficulty

--[[ HOW HARD IT TRIES.

     width    partial turns kept at each step of the search
     depth    the longest sequence it will look through in one go
     samples  how many times a move with a random outcome is tried, averaged
     budget   the most simulated moves per decision -- the real cap on cost
     noise    how far a Novice's judgement of each first move can wobble
     lethal   the chance it looks for lethal at all this decision
     reply    how many of its best turns it plays forward through YOUR attacks
              before choosing -- "if I do this, what do they do back?" -- the
              habit that stops a player leaving minions to be traded off

     The deck tier is the same number: the slider picks both at once, so a
     Master brings a Master's deck and plays it like one. ]]
AI.DIFFICULTIES = {
  { name = "Novice",     width = 1, depth = 4,  samples = 1, budget = 80,
    noise = 4.0, lethal = 0.35, lethalBudget = 40,  reply = 0,
    blurb = "Basic decks. Learning the ropes." },
  { name = "Apprentice", width = 2, depth = 5,  samples = 1, budget = 140,
    noise = 2.0, lethal = 0.7,  lethalBudget = 70,  reply = 0,
    blurb = "Budget decks. Makes the odd mistake." },
  { name = "Adept",      width = 3, depth = 6,  samples = 1, budget = 240,
    noise = 0.7, lethal = 1,    lethalBudget = 100, reply = 4,
    blurb = "Solid ladder decks, played soundly." },
  { name = "Expert",     width = 4, depth = 8,  samples = 2, budget = 400,
    noise = 0,   lethal = 1,    lethalBudget = 150, reply = 8,
    blurb = "Strong meta decks. Finds its combos." },
  { name = "Master",     width = 6, depth = 10, samples = 3, budget = 700,
    noise = 0,   lethal = 1,    lethalBudget = 220, reply = 12,
    blurb = "The best decks of the era, played sharply." },
}
AI.DEFAULT_DIFFICULTY = 3

--[[ HOW IT WEIGHS THE BOARD, by deck style.

     face    your hero's health (the lower, the better for it)
     life    its own hero's health
     mine    its minions and weapon
     theirs  your minions and weapon
     cards   cards in hand
     hold    how tightly it holds a spell, per mana of its cost -- an aggro
             deck's burn is for your face, a control deck's removal waits for
             a target worth it ]]
AI.STYLES = {
  aggro    = { face = 1.7, life = 0.75, mine = 0.9, theirs = 1.0,  cards = 0.8, hold = 0.55 },
  midrange = { face = 1.0, life = 1.0,  mine = 1.0, theirs = 1.15, cards = 1.0, hold = 0.9 },
  control  = { face = 0.7, life = 1.3,  mine = 1.0, theirs = 1.3,  cards = 1.2, hold = 1.05 },
}

local function clampDifficulty(d)
  d = tonumber(d) or AI.DEFAULT_DIFFICULTY
  if d ~= d then d = AI.DEFAULT_DIFFICULTY end   -- "nan" is a number to tonumber
  return math.max(1, math.min(#AI.DIFFICULTIES, math.floor(d)))
end
AI.ClampDifficulty = clampDifficulty

--[[ The bot's private random stream: a small LCG seeded from the game's state,
     so the same board always produces the same wobble, and the game's own
     stream is never drawn from. ]]
local function newRand(seed)
  local s = seed % 2147483648
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return math.floor(s / 65536) / 32768
  end
end

local fingerprint

--- Everything one decision needs: difficulty, weights, and its own randomness.
function AI.Profile(opts, game, player)
  opts = opts or {}
  local d = AI.DIFFICULTIES[clampDifficulty(opts.difficulty)]
  local P = {}
  for k, v in pairs(d) do P[k] = v end
  P.style = AI.STYLES[opts.style] and opts.style or "midrange"
  P.W = AI.STYLES[P.style]
  for k, v in pairs(opts) do
    if k ~= "difficulty" and k ~= "style" then P[k] = v end
  end
  -- Planning randomness comes only from what this player can observe;
  -- never from the seed that determines the real shuffle and random outcomes.
  local visible = game and fingerprint(game, player) or ""
  P.salt = (player or 0) * 101
  for i=1,#visible do P.salt=(P.salt*31+visible:byte(i))%100000 end
  P.rand = newRand(P.salt * 17 + 5)
  P.lastYield = 0
  return P
end

-- ============================================================ evaluation

--[[ Does this minion carry text that is still worth something on the board --
     a trigger, an aura, a deathrattle, Spell Damage? A battlecry is spent the
     moment it lands, so it does not count; its effect is already in the board
     it produced. ]]
local function lastingText(g, e)
  if e.silenced then return false end
  if #e.triggers > 0 or #e.deathrattles > 0 then return true end
  if e.printed.spellDamage then return true end
  local s = g:ScriptFor(e.cardId)
  return (s and (s.aura or s.spellMultiplier or s.attacksPerTurn)) and true or false
end

--[[ What one minion is worth to whoever controls it.

     Stats first, with a bonus for being balanced (a 4/4 is worth more than a
     7/1: it survives what kills the 7/1 and still hits hard), then its
     keywords. Temporary attack (Abusive Sergeant, Rockbiter) is left out, since
     it is gone by the time the board is next contested -- its worth shows up in
     the trades it made possible, not in the minion.

     Text is priced by what the card gave up for it: a Knife Juggler costs two
     and is a 3/2, a body a vanilla two-drop would beat, so the difference is
     what its text is worth. ]]
local function minionValue(g, e)
  local hp = e:Health()
  if hp <= 0 or e.pendingDestroy then return 0 end
  local atk = g:AttackValue(e) - ((e.timed and e.timed.atk) or 0)
  if atk < 0 then atk = 0 end
  local v = 1 + atk + hp + 0.5 * math.sqrt(atk * hp)
  if e:Has(KW.TAUNT) then v = v + 1 + 0.15 * hp end
  if e:Has(KW.DIVINE_SHIELD) then v = v + 1 + 0.6 * atk end
  if e:Has(KW.WINDFURY) then v = v + 0.6 * atk end
  if e:Has(KW.STEALTH) then v = v + 0.5 + 0.2 * atk end
  if e:Has(KW.POISONOUS) then v = v + 2.5 end
  if e:Has(KW.CANT_ATTACK) then v = v - 0.8 * atk end
  if e.frozen then v = v - 0.5 * atk end
  if lastingText(g, e) then
    local p = e.printed
    local gap = (p.cost or 0) * 2 + 1 - ((p.atk or 0) + (p.hp or 0))
    if gap > 0 then v = v + math.min(gap, 7) * 0.7 end
  end
  return v
end

local function weaponValue(w)
  local dur = w:Health()
  if dur <= 0 then return 0 end
  return 1 + 0.5 * w:Attack() * dur
end

--[[ What a card in hand is worth, before it is played.

     A minion is worth little in hand -- its value is on the board, so the bot
     wants to play it. A spell is worth more, in proportion to its cost: a
     Fireball held is six damage it can point anywhere later, so spending it on
     a 2/1 is a poor trade and it waits for something worth burning. This one
     asymmetry is most of the difference between a bot that curves out and a
     bot that also holds its removal. How tightly is the deck's style. ]]
local function cardValue(card, W)
  if card.cardId == COIN_ID then return 1.0 end
  local p = card.printed
  local c = math.min(p.cost or 0, 8)
  if p.type == TYPE.MINION then return 1.0 + 0.6 * c end
  return 1.8 + (W and W.hold or 0.9) * c
end

--[[ Health is worth more the less of it there is: the step from 30 to 26 is a
     scratch, the step from 6 to 2 is the game. ]]
local function healthValue(h)
  if h <= 0 then return -20 end
  return 6 * math.sqrt(h)
end

local function effectiveHealth(p)
  return p.hero:Health() + (p.hero.armor or 0)
end

--[[ How much of `attacker`'s board could reach `defender`'s face next turn.

     Frozen characters sit it out; Windfury swings twice. Taunts soak it the way
     a player would spend attackers on them -- the smallest attackers go into
     each Taunt until it would die, and none of that damage reaches the hero. ]]
local function faceDamage(g, attacker, defender)
  local swings = {}
  for _, e in ipairs(attacker.board) do
    if not e.frozen and not e:Has(KW.CANT_ATTACK) then
      local a = g:AttackValue(e) - ((e.timed and e.timed.atk) or 0)
      if a > 0 then
        swings[#swings + 1] = a
        if e:Has(KW.WINDFURY) then swings[#swings + 1] = a end
      end
    end
  end
  local hero = attacker.hero
  if not hero.frozen and attacker.weapon then
    local a = attacker.weapon:Attack()
    if a > 0 then swings[#swings + 1] = a end
  end
  table.sort(swings)
  local first = 1
  for _, t in ipairs(defender.board) do
    if t:IsTaunt() then
      local soak = t:Health()
      while soak > 0 and first <= #swings do
        soak = soak - swings[first]
        first = first + 1
      end
    end
  end
  local total = 0
  for i = first, #swings do total = total + swings[i] end
  return total
end

--[[ THE BOARD, AS ONE NUMBER, from `me`'s side. Higher is better for `me`.

     Exposed so tests can ask "is this position better than that one?" -- which
     is the only question the planner ever asks. ]]
function AI.Evaluate(g, me, W)
  W = W or AI.STYLES.midrange
  if g.over then
    if g.winner == me then return 1e6 end
    if g.winner then return -1e6 end
    return -1e5
  end
  local foe = g:Opponent(me)
  local P, F = g.players[me], g.players[foe]
  local myH, foeH = effectiveHealth(P), effectiveHealth(F)
  local s = W.life * healthValue(myH) - W.face * healthValue(foeH)

  for _, e in ipairs(P.board) do s = s + W.mine * minionValue(g, e) end
  for _, e in ipairs(F.board) do
    local threat = 0
    if not e.frozen and not e:Has(KW.CANT_ATTACK) then
      threat = 0.4 * math.max(0, g:AttackValue(e))
    end
    s = s - W.theirs * (minionValue(g, e) + threat)
  end
  if P.weapon then s = s + W.mine * weaponValue(P.weapon) end
  if F.weapon then s = s - W.theirs * weaponValue(F.weapon) end

  local hand = 0
  for _, c in ipairs(P.hand) do hand = hand + cardValue(c, W) end
  s = s + W.cards * hand - W.cards * 2.2 * #F.hand
  for _, sc in ipairs(P.secrets) do s = s + cardValue(sc, W) + 0.5 end

  -- Mana crystals, both sides: Wild Growth is worth having, and Arcane Golem
  -- handing you one is a real cost.
  s = s + 2.0 * (math.min(P.maxMana or 0, 10) - math.min(F.maxMana or 0, 10))
        - 1.0 * (P.pendingOverload or 0)

  --[[ Danger: could the opponent's board kill it next turn? A player feels
       this before anything else -- it is why they trade instead of racing, and
       drop a Taunt instead of a bigger minion. Within burn range counts too. ]]
  local incoming = faceDamage(g, F, P)
  if incoming >= myH then
    s = s - 25 * W.life
  elseif incoming > myH - 6 then
    s = s - 6 * W.life * (1 - (myH - incoming) / 6)
  end
  -- ...and the same threat pointed the other way is pressure worth having.
  if faceDamage(g, P, F) >= foeH then s = s + 5 * W.face end
  return s
end

--[[ Attack still waiting to be used this turn. Not part of the score -- a turn
     that ends with attackers idle has no use for them -- but part of how the
     search RANKS partial turns, so Savage Roar or a Charge minion survives the
     cut long enough for the attacks that make it worth playing. ]]
local function readyAttack(g, me)
  local total = 0
  local p = g.players[me]
  local function add(e)
    if g:CanAttack(e) then
      total = total + g:AttackValue(e) * math.max(1, g:AttacksAllowed(e) - e.attacksThisTurn)
    end
  end
  add(p.hero)
  for _, e in ipairs(p.board) do add(e) end
  return total
end

-- ============================================================ the copies

--[[ A fingerprint of everything the plan depends on and nothing it must not
     know -- not deck order, not the opponent's secrets, not the random stream.
     Two states with the same fingerprint are the same position as far as the
     bot can tell; that is what de-duplicates the search (attacking with A then
     B lands where B then A does) and what tells a stored plan it is still on
     course. ]]
fingerprint = function(g, me)
  local t = { g.turn, g.activePlayer, g.over and 1 or 0, g.pendingChoice and 1 or 0 }
  local n = #t
  local function put(v) n = n + 1; t[n] = v end
  for pi = 1, 2 do
    local p = g.players[pi]
    local h = p.hero
    put("P"); put(h.instanceId); put(h:Health()); put(h.armor or 0)
    put(h.attacksThisTurn or 0); put(h.frozen and 1 or 0)
    put(p.mana); put(p.maxMana); put(p.tempMana or 0); put(p.lockedMana or 0)
    put(p.pendingOverload or 0); put(p.heroPowerUsedThisTurn and 1 or 0)
    put(#p.deck); put(#p.graveyard)
    if pi == me then put(#p.secrets) end
    put("h")
    if pi == me then for _, c in ipairs(p.hand) do put(c.instanceId) end
    else put(#p.hand) end
    put("b")
    for _, e in ipairs(p.board) do
      put(e.instanceId); put(g:AttackValue(e)); put(e:Health()); put(e.attacksThisTurn or 0)
      put((e.frozen and 1 or 0) + (e:Has(KW.DIVINE_SHIELD) and 2 or 0)
          + (e.silenced and 4 or 0) + (e:Has(KW.TAUNT) and 8 or 0)
          + (e:Has(KW.STEALTH) and 16 or 0))
    end
    if p.weapon then put("w"); put(p.weapon.instanceId); put(p.weapon:Attack()); put(p.weapon:Health()) end
  end
  return table.concat(t, ",")
end
AI.Fingerprint = fingerprint

local function reseed(c, salt)
  c.rngState = ((salt % 100000) * 1103515 + 12345) % 2147483648
end

--[[ The copy the bot plans on: the real position, minus what a player in its
     seat could not know. ]]
local function fogged(game, me, salt)
  local c = game:Clone()
  reseed(c, salt)
  table.sort(c.players[me].deck, function(a,b)
    if a.cardId == b.cardId then return a.instanceId < b.instanceId end
    return a.cardId < b.cardId
  end)
  c:Shuffle(c.players[me].deck)
  local foe = c:Opponent(me)
  -- Unknown cards must not survive into simulations: Mind Vision/Thoughtsteal
  -- otherwise evaluate the opponent's actual hand and deck. Use a public Basic
  -- deck prior, independent of their hidden identities, buffs and ordering.
  local prior = ns.Controller.BasicDeck(c.players[foe].class)
  c.players[foe].deckIds = prior
  for _, zone in ipairs({'hand','deck'}) do
    local cards = c.players[foe][zone]
    for i = 1, #cards do
      local id = prior[((i + salt) % #prior) + 1]
      local e = ns.Entity.New(c:Printed(id), foe, c.ids)
      e.zone = zone == 'hand' and ns.ZONE.HAND or ns.ZONE.DECK
      cards[i] = e
    end
  end
  c.players[foe].secrets = {}
  return c
end
AI.PlanningState = fogged

-- ============================================================ enumerating moves

local adjacencyCache = {}
local function mentionsAdjacency(t, seen)
  if seen[t] then return false end
  seen[t] = true
  for k, v in pairs(t) do
    if k == "adjacent" then return true end
    if type(v) == "table" and mentionsAdjacency(v, seen) then return true end
  end
  return false
end

--[[ Does placement matter for this card? Flametongue Totem and Dire Wolf Alpha
     buff their neighbours and Defender of Argus buffs its own, so for those --
     and for anything played next to them -- every slot is worth trying. For
     everything else a slot is a slot, and trying all seven would multiply the
     search by seven for nothing. ]]
local function usesAdjacency(g, cardId)
  local v = adjacencyCache[cardId]
  if v == nil then
    local s = g:ScriptFor(cardId)
    v = s and mentionsAdjacency(s, {}) or false
    adjacencyCache[cardId] = v
  end
  return v
end

--[[ Every move `me` could make right now, as actions. Moves that are provably
     the same -- two copies of one card in hand, two identical minions swinging
     at the same target -- are offered once. ]]
local function enumerate(g, me, blocked)
  local out = {}
  if g.over or g.activePlayer ~= me or g:AwaitingChoice() then return out end
  local T = ns.Targeting
  local p = g.players[me]

  local adjacentBoard = false
  for _, e in ipairs(p.board) do
    if not e.silenced and usesAdjacency(g, e.cardId) then adjacentBoard = true end
  end

  local seenCard = {}
  for i, card in ipairs(p.hand) do
    local key = "card:" .. card.instanceId
    local sig = card.cardId .. ":" .. g:CardCost(card, me) .. ":"
                .. card.ench.atk .. ":" .. card.ench.hp
    if not (blocked and blocked[key]) and not seenCard[sig] and T.CanPlay(g, card, me) then
      seenCard[sig] = true
      local modes = T.ModesOf(card)
      local modeList = {}
      if modes then
        for m = 1, #modes do
          if T.ModePlayable(g, card, me, m) then modeList[#modeList + 1] = m end
        end
      else
        modeList[1] = false
      end
      local positions = { false }
      if card.printed.type == TYPE.MINION and #p.board > 0
         and (adjacentBoard or usesAdjacency(g, card.cardId)) then
        positions = {}
        for pos = 1, #p.board + 1 do positions[pos] = pos end
      end
      for _, m in ipairs(modeList) do
        local mode = m or nil
        local want = T.WantsTarget(g, card, me, mode)
        local targets = { false }
        if want then
          local legal = T.LegalTargets(g, card, me, mode)
          if #legal > 0 then targets = legal
          elseif want == "required" then targets = {} end
        end
        for _, t in ipairs(targets) do
          for _, pos in ipairs(positions) do
            out[#out + 1] = { kind = "PLAY_CARD", handIndex = i, mode = mode,
                              position = pos or nil,
                              targetId = t and t.instanceId or nil, _key = key }
          end
        end
      end
    end
  end

  local attackers = { p.hero }
  for _, e in ipairs(p.board) do attackers[#attackers + 1] = e end
  local seenAtk = {}
  for _, a in ipairs(attackers) do
    local key = "atk:" .. a.instanceId
    if not (blocked and blocked[key]) and g:CanAttack(a) then
      local sig = "hero"
      if a.printed.type ~= TYPE.HERO then
        sig = table.concat({ a.cardId, g:AttackValue(a), a:Health(), a.attacksThisTurn,
                             a:Has(KW.DIVINE_SHIELD) and 1 or 0, a.silenced and 1 or 0,
                             #a.triggers, #a.deathrattles, a.ench.atk, a.ench.hp }, ":")
      end
      if not seenAtk[sig] then
        seenAtk[sig] = true
        for _, t in ipairs(g:LegalAttackTargets(a)) do
          if g:IsLegalAttack(a, t) then
            out[#out + 1] = { kind = "ATTACK", attackerId = a.instanceId,
                              targetId = t.instanceId, _key = key }
          end
        end
      end
    end
  end

  local hp = p.heroPower
  if hp and not p.heroPowerUsedThisTurn and not (blocked and blocked.power)
     and g:CardCost(hp, me) <= g:AvailableMana(me) then
    if T.NeedsTarget(g, hp, me) then
      for _, t in ipairs(T.LegalTargets(g, hp, me)) do
        out[#out + 1] = { kind = "HERO_POWER", targetId = t.instanceId, _key = "power" }
      end
    else
      out[#out + 1] = { kind = "HERO_POWER", _key = "power" }
    end
  end
  return out
end
AI.Enumerate = enumerate

-- ============================================================ simulating

--[[ Answer a prompt raised mid-resolution (Tracking) by trying each option. ]]
local function bestChoice(g, me, W)
  local pc = g.pendingChoice
  if not pc then return 1 end
  local best, bestScore = 1, nil
  for i = 1, #pc.cards do
    local c = g:Clone()
    local ok, res = pcall(ns.Actions.Run, c, me, { kind = "CHOICE", index = i })
    if ok and res then
      local s = AI.Evaluate(c, me, W)
      if not bestScore or s > bestScore then best, bestScore = i, s end
    end
  end
  return best
end

--[[ Play `action` on a fresh copy of `state`. Nil when the rules refuse it, or
     when the move errors -- a card script failing inside a hypothetical must
     never take the real turn down with it. ]]
local function applyIn(state, me, action, salt, W)
  local c = state:Clone()
  reseed(c, salt)
  local ok, res = pcall(ns.Actions.Run, c, me, action)
  if not ok or not res then return nil end
  local guard = 0
  while c:AwaitingChoice() and c.pendingChoice.player == me and guard < 4 do
    guard = guard + 1
    local idx = bestChoice(c, me, W)
    local ok2, res2 = pcall(ns.Actions.Run, c, me, { kind = "CHOICE", index = idx })
    if not ok2 or not res2 then return nil end
  end
  return c
end

--[[ Try a move and score where it lands. A move that drew on the random
     stream is tried again under other seeds and the scores averaged: judging
     Arcane Missiles by one lucky roll is how a bot comes to rely on luck. ]]
local function simEval(state, me, action, P, salt, scorer)
  local c = applyIn(state, me, action, salt, P.W)
  if not c then return nil, nil, 1 end
  local score = scorer(c)
  local used = 1
  if P.samples > 1 and not c.over and c.rngCalls > state.rngCalls then
    local total = score
    for k = 2, P.samples do
      local c2 = applyIn(state, me, action, salt + k * 7919, P.W)
      if c2 then total = total + scorer(c2); used = used + 1 end
    end
    score = total / used
  end
  return c, score, used
end

local function maybeYield(P, sims)
  if P.yield and sims - P.lastYield >= (P.yieldEvery or 8) then
    P.lastYield = sims
    P.yield()
  end
end

local function append(list, v)
  local out = {}
  for i = 1, #list do out[i] = list[i] end
  out[#out + 1] = v
  return out
end

-- ============================================================ your reply

--[[ HOW YOU WOULD SWING BACK, played out quickly.

     Not a search -- a model of an ordinary player's attacks, so it costs one
     copy rather than hundreds: each of your characters, biggest first, takes a
     trade that is worth it (kills something worth more than it loses), else
     goes face, else hits whatever Taunt is in the way. It does not guess at
     the cards in your hand; it asks only what your board would do to the
     board the bot is about to leave you. ]]
local function opponentSwings(c, foe)
  for _ = 1, 16 do
    if c.over then return end
    local F = c.players[foe]
    local attacker, atk
    local function consider(e)
      if c:CanAttack(e) then
        local a = c:AttackValue(e)
        if not atk or a > atk then attacker, atk = e, a end
      end
    end
    for _, e in ipairs(F.board) do consider(e) end
    consider(F.hero)
    if not attacker then return end

    local pick, pickGain, face
    for _, t in ipairs(c:LegalAttackTargets(attacker)) do
      if t.printed.type == TYPE.HERO then
        face = t
      else
        local kills = atk >= t:Health() and not t:Has(KW.DIVINE_SHIELD)
        local dies = attacker.printed.type ~= TYPE.HERO
                     and c:AttackValue(t) >= attacker:Health()
                     and not attacker:Has(KW.DIVINE_SHIELD)
        local gain = (kills and minionValue(c, t) or -1)
                     - (dies and minionValue(c, attacker) or 0)
        if not pickGain or gain > pickGain then pick, pickGain = t, gain end
      end
    end
    local target = face
    if pick and (pickGain > 0.5 or not face) then target = pick end
    if not target or not c:IsLegalAttack(attacker, target) then
      attacker.attacksThisTurn = 99          -- this copy only; never ask again
    else
      c:Attack(attacker, target)
      c.bus:Drain()
    end
  end
end

--[[ The position after the bot ends its turn here and you swing back. End of
     turn is played for real on the copy, so "this turn" buffs fall away, its
     end-of-turn triggers fire and your start-of-turn ones (Doomsayer) too. ]]
local function afterReply(state, me, W)
  if state.over then return AI.Evaluate(state, me, W) end
  local c = state:Clone()
  local ok = pcall(function()
    c:EndTurn()
    c.bus:Drain()
    if not c.over and c.activePlayer ~= me then opponentSwings(c, c.activePlayer) end
  end)
  if not ok then return AI.Evaluate(state, me, W) end
  return AI.Evaluate(c, me, W)
end

-- ============================================================ searching

--[[ THE BEAM SEARCH.

     From the fogged root, every move is tried; the most promising partial
     turns are kept and every move is tried again from each; and so on. The
     best position seen at ANY depth wins -- including the root itself, which
     is "do nothing more and end the turn", so a move is only ever made when it
     leaves the bot better off.

     `scorer` judges a position, `ranker` orders partial turns for the cut
     (score plus unspent attack, so combos are not pruned before they pay off).
     Terminal positions are never extended: nothing follows a win. ]]
local function beam(root, me, P, blocked, scorer, ranker, width, depth, budget)
  local rootScore = scorer(root)
  local best = { state = root, score = rootScore, actions = {}, fps = {}, noise = 0 }
  local frontier = { best }
  local sims, truncated = 0, false
  --[[ The best few positions seen at any depth, for the reply check below.
       The root is always among them: ending the turn now is a candidate. ]]
  local replies = (ranker and P.reply or 0)
  local top = { best }
  local function remember(k)
    if replies <= 0 then return end
    if #top < replies + 1 then top[#top + 1] = k; return end
    local worst, wi = nil, nil
    for i = 2, #top do
      if not worst or top[i].score < worst then worst, wi = top[i].score, i end
    end
    if k.score > worst then top[wi] = k end
  end
  for d = 1, depth do
    local kids, seen = {}, {}
    for ni, node in ipairs(frontier) do
      local acts = enumerate(node.state, me, d == 1 and blocked or nil)
      for ai, a in ipairs(acts) do
        -- The first step is always searched in full, or the budget could
        -- leave the bot blind to a move it can make right now.
        if d > 1 and sims >= budget then truncated = true; break end
        local child, score, used = simEval(node.state, me, a, P,
                                           P.salt + d * 131 + ni * 17 + ai, scorer)
        sims = sims + used
        maybeYield(P, sims)
        if child then
          local fp = fingerprint(child, me)
          if not seen[fp] then
            seen[fp] = true
            local noise = node.noise
            if d == 1 and P.noise > 0 and ranker then
              noise = P.noise * (P.rand() * 2 - 1)
            end
            kids[#kids + 1] = {
              state = child, actions = append(node.actions, a), fps = append(node.fps, fp),
              score = score + noise, rawScore = score, noise = noise, over = child.over,
              rank = score + noise + (ranker and ranker(child) or 0),
            }
          end
        end
      end
      if truncated then break end
    end
    if #kids == 0 then break end
    for _, k in ipairs(kids) do
      -- a hair of preference for the shorter turn, so a pointless move is
      -- never made just because it scored the same
      -- Difficulty wobble may choose a lesser improvement, but must not turn
      -- wasting a heal/buff into a better turn than passing. Keep setup moves
      -- in the frontier so a temporarily losing combo can still pay off.
      if k.rawScore > rootScore + 0.05 and k.score > best.score + 0.05 then best = k end
      remember(k)
    end
    table.sort(kids, function(a, b) return a.rank > b.rank end)
    frontier = {}
    local keep = (d == 1) and width * 2 or width
    for _, k in ipairs(kids) do
      if #frontier >= keep then break end
      if not k.over then frontier[#frontier + 1] = k end
    end
    if #frontier == 0 or truncated then break end
  end

  --[[ "IF I DO THIS, WHAT DO THEY DO BACK?" The strongest few turns are played
       forward through your attacks and judged on what is left. A turn that
       looks best now but hands you three free trades loses to one that keeps
       its minions out of reach; a turn that leaves you lethal on board loses to
       the one with a Taunt. A win needs no second opinion. ]]
  if replies > 0 and best.score < 1e6 and #top > 1 then
    local pick, pickScore, rootReply
    for i, k in ipairs(top) do
      local raw = afterReply(k.state, me, P.W)
      if i == 1 then rootReply = raw end
      local s = raw + (k.noise or 0)
      maybeYield(P, sims + i * 3)
      if not pickScore or (raw > rootReply + 0.05 and s > pickScore + 0.05) then pick, pickScore = k, s end
    end
    best = pick
  end
  best.complete = not truncated and #best.actions < depth
  best.sims = sims
  return best
end

--[[ LETHAL, looked for first. The board-minded search weighs your face against
     its own board, so it may well prefer a trade to the swing that wins; this
     one cares about nothing but your health and the damage it still has ready,
     and its answer is taken only if it actually ends the game. ]]
local function findLethal(game, me, P, blocked)
  local foe = game:Opponent(me)
  local F = game.players[foe]
  -- Not worth searching when no plausible turn could do it.
  local ceiling = readyAttack(game, me) + 4 * #game.players[me].hand + 6
  if effectiveHealth(F) > ceiling then return nil end

  local root = fogged(game, me, P.salt + 99991)
  local function score(g)
    if g.over then return g.winner == me and 1e9 or -1e9 end
    local taunt = false
    for _, e in ipairs(g.players[foe].board) do
      if e:IsTaunt() then taunt = true; break end
    end
    local s = -10 * effectiveHealth(g.players[foe])
    if not taunt then s = s + 9 * readyAttack(g, me) end
    return s
  end
  local best = beam(root, me, P, blocked, score, nil, 2, 12, P.lethalBudget)
  if best.score >= 1e9 then
    best.complete = true
    return best
  end
  return nil
end

local function think(game, me, P, blocked)
  if P.lethal >= 1 or P.rand() < P.lethal then
    local l = findLethal(game, me, P, blocked)
    if l then return l end
  end
  local W = P.W
  local function score(g) return AI.Evaluate(g, me, W) end
  local function rank(g) return 0.35 * readyAttack(g, me) end
  local root = fogged(game, me, P.salt)
  return beam(root, me, P, blocked, score, rank, P.width, P.depth, P.budget)
end

--[[ Plans are remembered per game, so a turn is thought through once and then
     played step by step. Each step records the fingerprint the game should
     have before it; the moment the real game disagrees -- a draw the fog could
     not know, a random roll, a secret of yours going off -- the rest of the
     plan is dropped and the bot thinks again from where it actually is. ]]
local plans = setmetatable({}, { __mode = "k" })

function AI.ForgetPlan(game) plans[game] = nil end

-- ========================================================== the mulligan

--[[ The practice opponent's mulligan.

     Without this a practice match would sit in the mulligan phase forever,
     because the engine will not begin play until BOTH players have submitted --
     so the AI needing to mulligan is not a nicety, it is what makes a match
     start at all.

     It keeps what a player keeps: its early turns. Everything costing two or
     less stays. A three stays when it has something cheaper to go with it (or
     the Coin to cheat it out) -- one of them, two going second. A four stays
     only going second, only a minion, only beside a two, and never in an aggro
     deck, which wants its cheapest cards and nothing else. The Coin is never
     thrown back -- the engine refuses it. ]]
AI.MULLIGAN_KEEP_COST = 3

function AI.MulliganIndices(game, player, opts)
  local style = (opts and AI.STYLES[opts.style]) and opts.style or "midrange"
  local hand = game.players[player].hand
  local second = game.pendingCoin == player
  local cheap = 0
  for _, c in ipairs(hand) do
    if c.cardId ~= COIN_ID and (c.printed.cost or 0) <= 2 then cheap = cheap + 1 end
  end
  local toss, threes = {}, 0
  for i, card in ipairs(hand) do
    if card.cardId ~= COIN_ID then
      local cost = card.printed.cost or 0
      local keep = false
      if cost <= 2 then
        keep = true
      elseif cost == 3 then
        threes = threes + 1
        keep = (cheap > 0 or second) and threes <= (second and 2 or 1)
      elseif cost == 4 then
        keep = second and cheap > 0 and style ~= "aggro"
               and card.printed.type == TYPE.MINION
      end
      if not keep then toss[#toss + 1] = i end
    end
  end
  -- Sorted for the same reason the controller sorts: a stable action log.
  table.sort(toss)
  return toss
end

function AI.Mulligan(game, player, submit, opts)
  if not game:AwaitingMulligan(player) then return false end
  submit = submit or AI.Submitter(game, player)
  return submit({ kind = "MULLIGAN", indices = AI.MulliganIndices(game, player, opts) })
end

--[[ Answer a decision the engine is waiting on, by trying every option. ]]
function AI.ResolveChoices(game, player, submit, opts)
  submit = submit or AI.Submitter(game, player)
  local P = AI.Profile(opts, game, player)
  local W = P.W
  local guard = 0
  while game:AwaitingChoice() and guard < 8 do
    guard = guard + 1
    local pc = game.pendingChoice
    if pc.player ~= player then return end
    local ok = submit({ kind = "CHOICE", index = bestChoice(fogged(game, player, P.salt), player, W) })
    if not ok then return end      -- never spin on a choice we cannot answer
  end
end

-- ================================================= one decision at a time

--[[ THE NEXT THING THIS OPPONENT WANTS TO DO, as an action, or nil when it is
     finished. Deciding and DOING are separated so the opponent's turn can be
     watched: Client/Main.lua takes one action, lets it animate, and comes back
     for the next. TakeTurn below takes a whole turn at once for the headless
     tests.

     `blocked` holds what the engine has refused this turn, keyed by `_key`, so
     a refused move is never offered again. `opts` carries { difficulty,
     style } and, in the client, { yield, yieldEvery } -- called every few
     simulated moves, so a long think is spread across frames rather than
     freezing one. ]]
function AI.NextAction(game, player, blocked, opts)
  if game.over then return nil end
  if game:AwaitingMulligan(player) then
    return { kind = "MULLIGAN", indices = AI.MulliganIndices(game, player, opts) }
  end
  if game.phase ~= "PLAY" or game.activePlayer ~= player then return nil end

  local P = AI.Profile(opts, game, player)
  --[[ A choice raised mid-resolution is answered before anything else: the
       engine refuses every other action while one is outstanding. ]]
  if game:AwaitingChoice() then
    local pc = game.pendingChoice
    if pc and pc.player == player then
      return { kind = "CHOICE", index = bestChoice(fogged(game, player, P.salt), player, P.W) }
    end
    return nil
  end

  local fp = fingerprint(game, player)
  local stored = plans[game]
  if stored and stored.player == player then
    for i = stored.pos, #stored.steps do
      local step = stored.steps[i]
      if step.fp == fp then
        if not step.action then return nil end         -- the plan ends here
        if not (blocked and blocked[step.action._key]) then
          stored.pos = i
          return step.action
        end
        break
      end
    end
  end

  local best = think(game, player, P, blocked)
  local steps, before = {}, fp
  for i, a in ipairs(best.actions) do
    steps[i] = { fp = before, action = a }
    before = best.fps[i]
  end
  if best.complete then steps[#steps + 1] = { fp = before } end
  plans[game] = { player = player, steps = steps, pos = 1 }
  return steps[1] and steps[1].action or nil
end

-- ============================================================ the turn

--[[ A whole turn at once: every decision NextAction makes, until it has none.

     Bounded by MAX_ACTIONS. A card that refuses to leave the hand -- a bug, a
     cost modifier loop -- would otherwise spin here forever and hang the
     client, and a practice opponent freezing the game is a far worse failure
     than a practice opponent passing its turn. ]]
function AI.TakeTurn(game, player, submit, opts)
  if game.over then return false end
  submit = submit or AI.Submitter(game, player)
  --[[ A turn cannot be taken during the mulligan, and the opponent being stuck
       there is the one thing that would stop a match ever beginning. ]]
  if game:AwaitingMulligan(player) then
    AI.Mulligan(game, player, submit, opts)
    return false
  end
  if game.activePlayer ~= player then return false end
  local blocked = {}
  for _ = 1, MAX_ACTIONS do
    if game.over or game.activePlayer ~= player then break end
    local action = AI.NextAction(game, player, blocked, opts)
    if not action then break end
    local ok = submit(action)
    --[[ A refusal is recorded, never retried: NextAction would otherwise
         choose the same move again and the turn would never end. ]]
    if not ok then
      if not action._key then break end
      blocked[action._key] = true
    end
  end
  return true
end

return AI
