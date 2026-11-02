--[[ Engine/Game.lua

  THE MUTATION SURFACE. Everything in Ops/Bus/Aura calls into here.

  Invariants this file is responsible for:

  * NO WoW API. Loads under standalone Lua 5.1. (Hard rule for all of Engine/.)
  * NO math.random. Game:Random is the ONLY source of randomness in the engine,
    so two clients replaying the same action log from the same seed reach
    identical state. Any direct math.random in Engine/ is a lockstep bug.
    tests/test_determinism.lua asserts this by poisoning math.random.
  * Board arrays are dense 1..N and boardIndex is always in sync. Reindex()
    after every insertion or removal, or adjacency silently breaks.
  * Nothing dies outside ProcessDeaths. Effects set pendingDestroy or push
    health <= 0; the death phase is the single place entities leave the board.
]]
local ADDON, ns = ...
local RULES, ZONE, EVENT, KW, TYPE =
      ns.RULES, ns.ZONE, ns.EVENT, ns.KEYWORD, ns.CARDTYPE
local Entity, Ops, Bus, Aura = ns.Entity, ns.Ops, ns.Bus, ns.Aura

local Game = {}
Game.__index = Game
ns.Game = Game

local COIN_ID = "GAME_005"   -- verified against the pinned build

-- the events whose "whenever" triggers resolve at once (Bus:ResolveQueued)
local ON_PLAY   = { [EVENT.CARD_PLAYED] = true, [EVENT.SPELL_CAST] = true,
                    [EVENT.MINION_PLAYED] = true }
local ON_ATTACK = { [EVENT.ATTACK_DECLARED] = true }

-- ======================================================== deterministic RNG

--[[ 32-bit LCG (glibc constants). Chosen over xorshift because it needs only
     multiply/add/mod within 2^53, which is exactly representable in Lua 5.1's
     doubles on every platform -- no integer overflow, no bit ops, no
     float-rounding divergence between clients. Quality is irrelevant here;
     reproducibility is everything. ]]
local function lcg(state)
  return (state * 1103515245 + 12345) % 2147483648
end

--- Random integer in [1, n]. Returns 0 for n <= 0 so callers can guard.
function Game:Random(n)
  if not n or n <= 0 then return 0 end
  self.rngState = lcg(self.rngState)
  self.rngCalls = self.rngCalls + 1
  -- take high bits: low bits of an LCG are famously non-random
  return (math.floor(self.rngState / 65536) % n) + 1
end

--[[ Commit-reveal seed derivation. Each client picks a secret nonce, exchanges
     a hash of it, then reveals. The shuffle seed is derived from BOTH nonces,
     so neither player can choose a seed that rigs their draws -- they must
     commit before seeing the other's value. This is about the game being fun,
     not security: the honour system covers the rest, exactly as you specified. ]]
function Game.DeriveSeed(nonceA, nonceB)
  local h = 5381
  for _, s in ipairs({ tostring(nonceA), tostring(nonceB) }) do
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483648 end
  end
  return h
end

-- ============================================================ construction

local function newPlayer(index, class, deckIds)
  return {
    index = index, class = class,
    deck = {}, hand = {}, board = {}, graveyard = {}, secrets = {},
    hero = nil, weapon = nil, heroPower = nil,
    mana = 0, maxMana = 0, tempMana = 0,
    lockedMana = 0, pendingOverload = 0,
    fatigue = 0,
    cardsPlayedThisTurn = 0,
    heroPowerUsedThisTurn = false,
    deckIds = deckIds,
    overdrawn = 0,
    --[[ Timed PLAYER-scoped effects. These are not entity enchantments -- they
         belong to the player, not to any card on the board -- but they share the
         same two duration classes and the same sweep, via Game:TimedExpired.

         costMods     "the next spell you cast this turn costs (3) less"
         damageClamps "your minions can't be reduced below 1 Health this turn"

         A modifier that affects the OPPONENT's cards (Loatheb, Millhouse) is
         stored on the AFFECTED player's list, so Game:CardCost only ever reads
         one list. Its `controller` field still names the caster, because that is
         whose "next turn" the expiry refers to. ]]
    costMods = {},
    damageClamps = {},
  }
end

--- Create a game. Does not start it -- call StartGame after mulligan choices.
-- @param cfg { seed, players = { {class=, deck={cardIds}}, {...} }, firstPlayer= }
function Game.New(cfg)
  local g = setmetatable({}, Game)
  --[[ Kept as well as consumed. The shuffle needs the evolving state, but
       anything that must LOOK the same on both clients -- which board the match
       is played on -- needs the original agreed seed, and reading rngState
       after a single draw would give the two clients different answers. ]]
  g.seed = cfg.seed or 0
  g.rngState = (cfg.seed or 0) % 2147483648
  g.rngCalls = 0
  g.playOrderCounter = 0
  g.turn = 0
  g.activePlayer = cfg.firstPlayer or 1
  g.over = false
  g.winner = nil
  --[[ "MULLIGAN" between Deal and both submissions, "PLAY" afterwards. Part of
       the state hash, so a client that thinks the mulligan is over while the
       other does not is caught immediately rather than three turns later. ]]
  g.phase = "SETUP"
  g.mulliganChoice = nil
  g.errors = {}
  g.scheduled = {}
  --[[ Minions that died during the CURRENT turn, in death order. Cleared at the
       start of every turn. Kel'Thuzad reads it at TURN_END. This is a turn-scoped
       log rather than a timed record, so it is not part of the sweep. ]]
  g.deathLog = {}
  g.players = {}
  --[[ This game's own id counter. Two games in one process therefore hand out
       ids independently, and two clients running the same seeded game hand out
       the SAME ids -- which is what makes an action able to name a target. ]]
  g.ids = Entity.NewIdSource()

  for i = 1, 2 do
    local pc = cfg.players[i]
    g.players[i] = newPlayer(i, pc.class, pc.deck)
  end

  g.bus = Bus.New(g)

  -- heroes and hero powers
  for i = 1, 2 do
    local p = g.players[i]
    local heroCard = g:Printed(ns.HERO_ID_BY_CLASS and ns.HERO_ID_BY_CLASS[p.class])
    p.hero = Entity.New(heroCard or { id = "HERO_" .. p.class, type = TYPE.HERO,
                                      hp = RULES.START_HEALTH, atk = 0 }, i, g.ids)
    p.hero.base.hp = RULES.START_HEALTH
    p.hero.zone = ZONE.PLAY
    p.hero.playOrder = 0
    local hpId = ns.HERO_POWER_BY_CLASS[p.class]
    if hpId then
      p.heroPower = Entity.New(g:Printed(hpId), i, g.ids)
      p.heroPower.zone = ZONE.HERO_POWER
    end
    -- build deck entities in the listed order, then shuffle deterministically
    for _, cid in ipairs(p.deckIds or {}) do
      local pr = g:Printed(cid)
      if pr then
        local e = Entity.New(pr, i, g.ids)
        e.zone = ZONE.DECK
        p.deck[#p.deck + 1] = e
      else
        g:Error("deck references unknown card id: " .. tostring(cid))
      end
    end
    g:Shuffle(p.deck)
  end
  return g
end

function Game:Printed(cardId)
  if not cardId then return nil end
  return ns.PrintedCards and ns.PrintedCards[cardId] or nil
end

function Game:ScriptFor(cardId)
  return ns.Scripts and ns.Scripts[cardId] or nil
end

function Game:Opponent(p) return p == 1 and 2 or 1 end

function Game:Error(msg)
  self.errors[#self.errors + 1] = msg
  if ns.STRICT then error(msg, 2) end
end

--- Fisher-Yates using the shared stream. Both clients produce the same order.
function Game:Shuffle(t)
  for i = #t, 2, -1 do
    local j = self:Random(i)
    t[i], t[j] = t[j], t[i]
  end
end

-- =================================================================== start

--[[ THE OPENING, IN THREE PARTS.

     Hearthstone's start is: deal, mulligan, begin. The old API could not
     express that -- ApplyMulligan's own comment said it was applied "before"
     StartGame, and StartGame was what dealt the hand, so there was nothing to
     mulligan. That is why nothing ever called it.

     Now: Deal(), then both players submit, then the game begins by itself. ]]
function Game:Deal()
  local first, second = self.activePlayer, self:Opponent(self.activePlayer)
  --[[ The opening hand is DEALT, not drawn: no draw event, and no "when you
       draw this" effect -- a Flame Leviathan in the opening hand used to burn
       both heroes before the mulligan. ]]
  for pi, n in pairs({ [first] = RULES.MULLIGAN_FIRST, [second] = RULES.MULLIGAN_SECOND }) do
    local p = self.players[pi]
    for _ = 1, n do
      local e = table.remove(p.deck)
      if e then e.zone = ZONE.HAND; p.hand[#p.hand + 1] = e end
    end
  end
  --[[ THE COIN ARRIVES AFTER THE MULLIGAN, not before.

       It used to be dealt with the opening hand. The rules were right either
       way -- the mulligan refuses to throw it back -- but the PRESENTATION was
       wrong and it read as a bug: going second showed you five cards to
       mulligan, one of which would not respond, and then five cards in hand
       afterwards. That looks exactly like having drawn an extra card before the
       game started, which is what it was reported as.

       Hearthstone adds it once the mulligan is settled, so you mulligan the
       four you were dealt and the Coin appears with them. Held here and given
       out in StartAfterMulligan. ]]
  self.pendingCoin = second
  self.turn = 0
  self.phase = "MULLIGAN"
  self.mulliganChoice = {}
  return self
end

--- Begin play. Called automatically once both mulligans are in.
function Game:StartAfterMulligan()
  self.phase = "PLAY"
  --[[ The Coin, now that there is nothing left to throw back. It is not part of
       the dealt hand -- it is compensation for going second -- so this is the
       first moment it can exist without being offered as a mulligan choice. ]]
  if self.pendingCoin then
    self:AddToHand(self.pendingCoin, COIN_ID)
    self.pendingCoin = nil
  end
  self:RecalcAuras()
  self.bus:Raise(EVENT.GAME_START, {})
  self:BeginTurn()
  return self
end

--[[ Deal and begin immediately, with no mulligan. This is the practice/test
     entry point and the behaviour every existing test expects. ]]
function Game:StartGame()
  self:Deal()
  self.phase = "PLAY"
  --[[ No mulligan to wait for, so the Coin is handed over immediately. ]]
  if self.pendingCoin then
    self:AddToHand(self.pendingCoin, COIN_ID)
    self.pendingCoin = nil
  end
  self.mulliganChoice = nil
  self:RecalcAuras()
  self.bus:Raise(EVENT.GAME_START, {})
  self:BeginTurn()
  return self
end

function Game:AwaitingMulligan(player)
  if self.phase ~= "MULLIGAN" then return false end
  if not player then return true end
  return self.mulliganChoice[player] == nil
end

--[[ Record one player's mulligan. Both are recorded BEFORE either is applied,
     and then they are applied IN PLAYER ORDER.

     THAT ORDERING IS A LOCKSTEP REQUIREMENT, not tidiness. ApplyMulligan
     shuffles, which draws from the shared random stream -- so if one client
     applied player 1's choice first and the other applied player 2's first, the
     two streams would diverge on the very first action of the match and every
     shuffle, discover and random target afterwards would differ. Recording both
     and applying them in a fixed order makes arrival order irrelevant. ]]
function Game:SubmitMulligan(player, handIndices)
  if self.phase ~= "MULLIGAN" then return false, "not the mulligan" end
  if player ~= 1 and player ~= 2 then return false, "no such player" end
  if self.mulliganChoice[player] then return false, "already mulliganed" end

  local hand = self.players[player].hand
  local seen, clean = {}, {}
  for _, i in ipairs(handIndices or {}) do
    --[[ An index that is not a card in hand is refused rather than ignored: over
         the wire it means the two clients disagree about the opening hand, which
         is the earliest possible desync and the one most worth catching. ]]
    if type(i) ~= "number" or not hand[i] then return false, "no such card in hand" end
    if seen[i] then return false, "duplicate index" end
    seen[i] = true
    clean[#clean + 1] = i
  end
  self.mulliganChoice[player] = clean

  if self.mulliganChoice[1] and self.mulliganChoice[2] then
    for pi = 1, 2 do self:ApplyMulligan(pi, self.mulliganChoice[pi]) end
    self:StartAfterMulligan()
  end
  return true
end

--[[ Mulligan: the player picks indices to replace. Hearthstone draws the
     replacements FIRST and only then shuffles the returned cards back, so a
     returned card cannot be immediately redrawn. Order matters and is
     observable, so it is reproduced exactly. ]]
function Game:ApplyMulligan(player, handIndices)
  local p = self.players[player]
  local returning, replacements = {}, {}
  local drop = {}
  for _, i in ipairs(handIndices) do drop[i] = true end
  for i = #p.hand, 1, -1 do
    if drop[i] then
      returning[#returning + 1] = table.remove(p.hand, i)
    end
  end
  for _ = 1, #returning do
    local e = table.remove(p.deck)
    if e then replacements[#replacements + 1] = e end
  end
  for _, e in ipairs(returning) do
    e.zone = ZONE.DECK
    p.deck[#p.deck + 1] = e
  end
  self:Shuffle(p.deck)
  for _, e in ipairs(replacements) do
    e.zone = ZONE.HAND
    p.hand[#p.hand + 1] = e
  end
end

-- ========================================================== turn structure

function Game:BeginTurn()
  self.turn = self.turn + 1
  local p = self.players[self.activePlayer]

  -- mana: gain a crystal (capped), then unlock last turn's overload
  if p.maxMana < RULES.MANA_CAP then p.maxMana = p.maxMana + 1 end
  p.lockedMana = p.pendingOverload
  p.pendingOverload = 0
  p.mana = p.maxMana - p.lockedMana
  if p.mana < 0 then p.mana = 0 end
  p.tempMana = 0
  p.cardsPlayedThisTurn = 0
  p.minionsPlayedThisTurn = 0
  p.heroPowerUsedThisTurn = false

  -- reset attack counters; mark frozen characters for thaw at end of this turn
  for _, e in ipairs(p.board) do e.attacksThisTurn = 0 end
  p.hero.attacksThisTurn = 0

  -- the death log is per-turn; Kel'Thuzad has already read last turn's at
  -- TURN_END, so it resets here
  self.deathLog = {}

  -- "until your next turn" buffs drop now, BEFORE the turn's events, so the
  -- player sees the board they are about to act on (Conceal's Stealth is gone
  -- before they pick attacks).
  self:ExpireStartOfTurn(self.activePlayer)

  -- deferred actions due at the start of this player's turn (Nightmare's
  -- destroy, Headcrack's return to hand)
  self:RunScheduled("START_OF_TURN", self.activePlayer)

  self:RecalcAuras()
  self.bus:Raise(EVENT.TURN_BEGIN, { player = self.activePlayer })
  self:Draw(self.activePlayer)
  self:ProcessDeaths()     -- fatigue may have killed the hero
end

--[[ Ending the turn ABANDONS an unanswered choice rather than carrying it into
     the opponent's turn. A player who walks away from a Tracking prompt has
     effectively declined it, and the cards are already out of the deck, so they
     go to the graveyard -- the card was still spent. ]]
function Game:EndTurn()
  if self.pendingChoice then
    local pc = self.pendingChoice
    self.pendingChoice = nil
    local p = self.players[pc.player]
    for _, e in ipairs(pc.cards) do
      e.zone = ZONE.GRAVEYARD
      p.graveyard[#p.graveyard + 1] = e
    end
  end
  return self:EndTurnInner()
end

function Game:EndTurnInner()
  local p = self.players[self.activePlayer]
  self.bus:Raise(EVENT.TURN_END, { player = self.activePlayer })

  --[[ FROZEN THAWS at the end of its controller's turn unless it had used up
       its attacks (hearthstone.wiki.gg/wiki/Freeze): Freeze costs the NEXT
       attack. So a minion frozen during the opponent's turn misses one turn
       and thaws at the end of it; one frozen on your own turn before it swung
       loses THIS turn's attack and thaws tonight; one frozen after using all
       its attacks stays frozen through your next turn. A Windfury minion frozen
       by its first swing still had an attack, so it thaws tonight too.
       A minion that could not attack at all this turn (summoning sick) had no
       attack to lose, so it keeps the Freeze. This used to keep ANY character
       frozen on its own turn through the next one. ]]
  local function thaw(e)
    if not e.frozen then return end
    local sick = e.printed.type == TYPE.MINION
                 and e.summonedTurn == self.turn and not e:Has(KW.CHARGE)
    if not sick and (e.attacksThisTurn or 0) < self:AttacksAllowed(e) then
      e.frozen = false
      e.thawAtEndOfTurn = nil
    end
  end
  for _, e in ipairs(p.board) do thaw(e) end
  thaw(p.hero)

  --[[ End-of-turn schedules fire BEFORE the "this turn" sweep, so a scheduled
       action can still see the buffs that are about to expire (Power Overwhelming
       destroys a minion that is still +4/+4 at that moment).

       Unlike start-of-turn schedules these fire on the SAME turn they were
       created, so RunScheduled's `turn < self.turn` guard would block them
       forever -- hence the explicit sameTurn flag. ]]
  self:RunScheduled("END_OF_TURN", self.activePlayer, true)

  -- "this turn" buffs expire here, after TURN_END triggers have had their say.
  self:ExpireEndOfTurn()

  p.tempMana = 0
  if not self.over and self.turn >= RULES.TURN_LIMIT then
    self.over = true
    self.winner = 0
    self.bus:Raise(EVENT.GAME_OVER, { winner = 0, turnLimit = true })
    return
  end
  self.activePlayer = self:Opponent(self.activePlayer)
  if not self.over then self:BeginTurn() end
end

--[[ Every entity that can carry a timed enchantment, in deterministic order.
     Hand and deck are included because a buff can follow a bounced minion, and
     leaving them out would let an expired buff come back with the card. ]]
function Game:AllTimedHosts()
  local out = {}
  for pi = 1, 2 do
    local p = self.players[pi]
    for _, e in ipairs(p.board) do out[#out + 1] = e end
    for _, e in ipairs(p.hand)  do out[#out + 1] = e end
    if p.hero   then out[#out + 1] = p.hero end
    if p.weapon then out[#out + 1] = p.weapon end
  end
  return out
end

--[[ THE ONE TIMING RULE, shared by every timed record in the engine: entity
     enchantments, player cost modifiers, player damage clamps and scheduled
     actions. Written once so the four cannot drift apart.

     `when` is the sweep point: ns.DURATION.END_OF_TURN for the end-of-turn
     sweep, ns.DURATION.START_OF_YOUR_NEXT_TURN for the begin-turn sweep.

     For the begin-turn sweep, `x.turn < self.turn` means a record can never
     expire on the turn it was created, and the controller test means the
     opponent's intervening BeginTurn is skipped. Applied on turn T by player P,
     P's next BeginTurn is turn T+2. ]]
function Game:TimedExpired(x, when, player)
  if x.expiry ~= when then return false end
  if when == ns.DURATION.END_OF_TURN then return true end
  return x.controller == player and (x.turn or 0) < self.turn
end

--- Filter a plain list of timed records in place. Returns how many were dropped.
local function sweepList(game, list, when, player)
  local kept, removed = {}, 0
  for _, x in ipairs(list) do
    if game:TimedExpired(x, when, player) then removed = removed + 1
    else kept[#kept + 1] = x end
  end
  if removed > 0 then
    for i = #list, 1, -1 do list[i] = nil end
    for i, x in ipairs(kept) do list[i] = x end
  end
  return removed
end

--[[ Expire everything due at `when`, then settle the board.

     An expiring HEALTH buff can kill, exactly as Silence can, so this runs a
     death phase afterwards. Nothing in the pinned pool grants timed health, but
     the system must not quietly do the wrong thing if one ever does. ]]
function Game:ExpireTimedAt(when, player)
  local pred = function(x) return self:TimedExpired(x, when, player) end
  local removed = 0
  for _, e in ipairs(self:AllTimedHosts()) do
    removed = removed + e:ExpireTimed(pred)
  end
  -- player-scoped lists share the same rule
  for pi = 1, 2 do
    local p = self.players[pi]
    removed = removed + sweepList(self, p.costMods, when, player)
    removed = removed + sweepList(self, p.damageClamps, when, player)
  end
  if removed > 0 then
    self:RecalcAuras()
    self:ProcessDeaths()
    self.bus:Drain()
  end
  return removed
end

--- "this turn" effects: expire when the current turn ends, whoever's turn it is.
function Game:ExpireEndOfTurn()
  return self:ExpireTimedAt(ns.DURATION.END_OF_TURN, nil)
end

--- "until your next turn" effects: expire at the start of the applier's next turn.
function Game:ExpireStartOfTurn(player)
  return self:ExpireTimedAt(ns.DURATION.START_OF_YOUR_NEXT_TURN, player)
end

-- ======================================================== cost modifiers

--- Is a secret? Factored out so PlayCard and the cost filter agree.
function Game:IsSecret(printed)
  for _, k in ipairs(printed.scriptTags or {}) do
    if k == "SECRET" then return true end
  end
  return false
end

function Game:CostModApplies(m, card)
  local t = card.printed.type
  if m.appliesTo == "SPELL"  then return t == TYPE.SPELL end
  if m.appliesTo == "SECRET" then
    return t == TYPE.SPELL and self:IsSecret(card.printed)
  end
  if m.appliesTo == "MINION" then return t == TYPE.MINION end
  return true
end

--[[ The cost actually charged: the card's own cost layers, then the controlling
     player's cost modifiers, IN THE ORDER THEY WERE CREATED, floored at 0 only
     at the very end (hearthstone.wiki.gg/wiki/Mana_cost: the minimum "is only
     enforced after all other cost modifications have been taken into
     account").

     Order matters only for `setTo` (Kirin Tor Mage, Millhouse -> "costs (0)"):
     Millhouse then Loatheb is 0 + 5 = 5, Loatheb then Millhouse is 0. A
     discount below zero is kept: Apprentice's -1 on a Moonfire still cancels
     one of Loatheb's +5. ]]
function Game:CardCost(card, player)
  player = player or card.controller
  local p = self.players[player]
  local c = card:RawCost()
  for _, m in ipairs(p.costMods) do
    if self:CostModApplies(m, card) then
      if m.setTo then c = m.setTo end
      c = c + (m.amount or 0)
    end
  end
  return c < 0 and 0 or c
end

--[[ Spend one charge of each modifier that applied, dropping exhausted ones.
     Preparation is "the NEXT spell", so it is consumed by casting -- including
     when that spell is then countered, because the cost was paid. Modifiers with
     no `charges` (Loatheb, Millhouse) are unlimited for their duration. ]]
function Game:ConsumeCostMods(card, player)
  local p = self.players[player]
  local kept = {}
  for _, m in ipairs(p.costMods) do
    local keep = true
    if m.charges and self:CostModApplies(m, card) then
      m.charges = m.charges - 1
      if m.charges <= 0 then keep = false end
    end
    if keep then kept[#kept + 1] = m end
  end
  p.costMods = kept
end

-- ======================================================== damage clamps

--[[ Commanding Shout: "Your minions can't be reduced below 1 Health this turn."
     Returns the health floor for `target`, or nil. Only damage is clamped --
     destroy effects still kill, which is the Hearthstone behaviour. ]]
function Game:DamageFloorFor(target)
  if target.printed.type ~= TYPE.MINION then return nil end
  local floor = nil
  for _, c in ipairs(self.players[target.controller].damageClamps) do
    if floor == nil or (c.minHealth or 1) > floor then floor = c.minHealth or 1 end
  end
  return floor
end

-- ====================================================== scheduled actions

--[[ Deferred actions that fire at a future turn boundary. Three cards need this:
     Nightmare (destroy at the start of your next turn), Headcrack (return to
     hand next turn), and it is the natural home for anything similar later.

     The captured ctx holds the ORIGINAL target by reference, so Nightmare
     destroys the minion it buffed rather than whatever is targeted later. ]]
--[[ A schedule aimed at a TARGET (Corruption, Nightmare, Shadow Madness) is an
     enchantment on that minion. Silence removes it, and so does the minion
     leaving play -- a Corrupted minion Sapped back to hand used to be marked
     for death and die the moment it was played again. The target's
     generation, bumped by Silence and by every reset to printed, says whether
     the minion it was aimed at is still the same one. ]]
function Game:Schedule(at, player, ops, ctx)
  local t = ctx and ctx.target
  self.scheduled[#self.scheduled + 1] = {
    at = at, player = player, turn = self.turn, ops = ops, ctx = ctx,
    targetGen = t and (t.enchGen or 0) or nil,
  }
end

local function scheduleStillHolds(s)
  local t = s.ctx and s.ctx.target
  if not t or s.targetGen == nil then return true end
  return t.zone == ZONE.PLAY and (t.enchGen or 0) == s.targetGen
end

--- @param sameTurn  allow entries created on the CURRENT turn to fire (end-of-turn
---                  schedules need this; start-of-turn ones must never have it)
function Game:RunScheduled(at, player, sameTurn)
  local due, keep = {}, {}
  for _, s in ipairs(self.scheduled) do
    local isDue = s.at == at
      and (s.player == nil or s.player == player)
      and (sameTurn or (s.turn or 0) < self.turn)
    if isDue then due[#due + 1] = s else keep[#keep + 1] = s end
  end
  self.scheduled = keep
  for _, s in ipairs(due) do
    if scheduleStillHolds(s) then
      self.bus:Block(function() Ops.Run(self, s.ops, s.ctx) end)
    end
  end
  return #due
end

-- ==================================================================== mana

function Game:AvailableMana(player)
  local p = self.players[player]
  return p.mana + p.tempMana
end

function Game:SpendMana(player, n)
  local p = self.players[player]
  local fromTemp = math.min(p.tempMana, n)
  p.tempMana = p.tempMana - fromTemp
  p.mana = p.mana - (n - fromTemp)
  if p.mana < 0 then p.mana = 0 end
end

function Game:GainManaCrystal(player, n, empty)
  local p = self.players[player]
  for _ = 1, (n or 1) do
    if p.maxMana < RULES.MANA_CAP then
      p.maxMana = p.maxMana + 1
      if not empty then p.mana = p.mana + 1 end
    end
  end
  self.bus:Raise(EVENT.MANA_GAINED, { player = player })
end

-- ============================================================ card movement

--[[ TOPDECK -- "when you draw this" effects.

     Implemented as a targeted hook on the card being drawn, NOT as a deck scan
     in Bus:Collect. Two reasons:

       * cost: Bus:Collect runs on every event. Scanning up to 30 deck cards
         each time, to serve one card in the whole pool, is absurd.
       * semantics: a card in the deck must NOT react to arbitrary events. Only
         the draw of that specific card matters, so the hook belongs where the
         draw happens.

     Only Flame Leviathan (GVG_007) has this in the pinned pool. If a future
     re-pin brings several on-draw cards, this generalises to a DECK-zone
     trigger scan -- but it would still be gated on the drawn entity. ]]
function Game:FireOnDraw(e)
  local s = self:ScriptFor(e.cardId)
  if not (s and s.onDraw) then return end
  local ctx = { source = e, controller = e.controller }
  self.bus:Block(function() Ops.Run(self, s.onDraw.ops, ctx) end)
end

function Game:Draw(player)
  local p = self.players[player]
  if #p.deck == 0 then
    -- fatigue: starts at 1 and increments with every subsequent empty draw
    p.fatigue = p.fatigue + 1
    self.bus:Raise(EVENT.FATIGUE, { player = player, amount = p.fatigue })
    --[[ No death phase here: a draw inside an effect is part of that effect,
         and deaths wait for its end. Settling here ended the game on the
         first fatigue kill, so an effect that fatigued BOTH heroes to death
         (Gift of Cards, Coldlight Oracle) gave a win instead of a draw. The
         turn-start draw settles its own deaths in BeginTurn. ]]
    self:DealDamage(p.hero, p.fatigue, nil, false)
    return nil
  end
  local e = table.remove(p.deck)
  if #p.hand >= RULES.HAND_LIMIT then
    -- overdraw: the card is revealed and destroyed, not returned to the deck.
    -- An on-draw effect STILL fires -- the card was drawn, then burned.
    e.zone = ZONE.GRAVEYARD
    p.graveyard[#p.graveyard + 1] = e
    p.overdrawn = p.overdrawn + 1
    self.bus:Raise(EVENT.CARD_DRAWN, { player = player, entity = e, burned = true })
    self:FireOnDraw(e)
    return nil
  end
  e.zone = ZONE.HAND
  p.hand[#p.hand + 1] = e
  self.bus:Raise(EVENT.CARD_DRAWN, { player = player, entity = e })
  self:FireOnDraw(e)
  return e
end

function Game:AddToHand(player, cardId)
  local p = self.players[player]
  local pr = self:Printed(cardId)
  if not pr then self:Error("AddToHand unknown card: " .. tostring(cardId)); return end
  if #p.hand >= RULES.HAND_LIMIT then
    p.overdrawn = p.overdrawn + 1
    self.bus:Raise(EVENT.CARD_BURNED, { player = player, cardId = cardId })
    return nil
  end
  local e = Entity.New(pr, player, self.ids)
  e.zone = ZONE.HAND
  p.hand[#p.hand + 1] = e
  return e
end

function Game:DiscardRandom(player)
  local p = self.players[player]
  if #p.hand == 0 then return end
  local i = self:Random(#p.hand)
  local e = table.remove(p.hand, i)
  e.zone = ZONE.GRAVEYARD
  p.graveyard[#p.graveyard + 1] = e
  self.bus:Raise(EVENT.CARD_DISCARDED, { player = player, entity = e })
end

--[[ Return a board entity to its CONTROLLER's hand, reset to printed state.
     "Return it to its owner's hand" means whoever holds it now: in Hearthstone
     a Sapped Mind-Controlled minion goes to the hand of the player who stole
     it, which is the whole point of Shadow Madness + Youthful Brewmaster.
     `owner` only records where the card started. ]]
function Game:MoveToHand(e)
  if e.zone ~= ZONE.PLAY then return end
  local side = e.controller
  self:RemoveFromBoard(e)
  local p = self.players[side]
  if #p.hand >= RULES.HAND_LIMIT then
    e.zone = ZONE.GRAVEYARD
    p.graveyard[#p.graveyard + 1] = e
    self.bus:Raise(EVENT.CARD_BURNED, { player = side, entity = e })
    return
  end
  self:ResetToPrinted(e)
  e.zone = ZONE.HAND
  e.owner = side
  p.hand[#p.hand + 1] = e
end

function Game:ShuffleIn(e)
  --[[ Already in the deck: nothing to do. Malorne under Baron Rivendare runs
       its deathrattle twice, and the second run used to add the SAME card to
       the deck a second time. ]]
  if e.zone == ZONE.DECK then return end
  local side = e.controller
  local p = self.players[side]
  if e.zone == ZONE.PLAY then self:RemoveFromBoard(e)
  else
    -- a dead minion is in the graveyard list; it must leave it
    for _, list in ipairs({ p.graveyard, p.hand }) do
      for i = #list, 1, -1 do if list[i] == e then table.remove(list, i) end end
    end
  end
  e.owner = side
  self:ResetToPrinted(e)
  e.zone = ZONE.DECK
  p.deck[#p.deck + 1] = e
  self:Shuffle(p.deck)
end

--- Strip all game-state mutation, returning the entity to its printed values.
function Game:ResetToPrinted(e)
  e.enchantmentSources = {}
  e.ench = { atk = 0, hp = 0, cost = 0 }
  e:ClearAuraLayer()
  e.enchKeywords = {}
  e.timedEnch = {}
  e.timed = { atk = 0, hp = 0, cost = 0 }
  e.timedKeywords = {}
  e.damage = 0
  e.silenced = false
  e.frozen = false
  e.thawAtEndOfTurn = nil
  e.pendingDestroy = false
  e.spellDamageBonus = nil     -- an Ancient Mage's gift does not survive a bounce
  e.enchGen = (e.enchGen or 0) + 1
  e.attacksThisTurn = 0
  e.summonedTurn = nil
  e.enraged = false
  --[[ Printed keywords are rebuilt from the card. A popped Divine Shield and
       a Stealth broken by attacking are removed from this layer for good while
       the minion is in play -- but a bounced Argent Squire or a shuffled Worgen
       Infiltrator is a fresh card and gets them back. ]]
  e.baseKeywords = {}
  for _, k in ipairs(e.printed.keywords or {}) do e.baseKeywords[k] = true end
  e.divineShieldUp = e.baseKeywords[KW.DIVINE_SHIELD] or false
  --[[ No script is attached here. A card in hand or deck carries none, and
       every path back into play (PlayCard, MoveToBoard, SwapWithHand) attaches
       it itself -- attaching here as well gave a bounced Loot Hoarder two
       deathrattles. ]]
  e.triggers = {}
  e.deathrattles = {}
end

-- ================================================================== board

function Game:Reindex(player)
  local b = self.players[player].board
  for i = 1, #b do b[i].boardIndex = i end
end

function Game:RemoveFromBoard(e)
  local b = self.players[e.controller].board
  for i = 1, #b do
    if b[i] == e then table.remove(b, i); break end
  end
  e.boardIndex = nil
  self:Reindex(e.controller)
end

--- Resolve a position spec to an insertion index in the target board.
function Game:ResolvePosition(player, position, source)
  local b = self.players[player].board
  if position == "REPLACE_SOURCE" and source and source.lastBoardIndex then
    return math.min(source.lastBoardIndex, #b + 1)
  elseif position == "RIGHT_OF_SOURCE" and source and not source.boardIndex
         and source.lastBoardIndex and source.controller == player then
    --[[ A deathrattle's source has left the board: its summons take the slot
         it died in (Cairne's Baine, Harvest Golem's Damaged Golem), not the
         far right. Several summons line up left to right from that slot, in
         the order they were made. ]]
    local idx = math.min(source.lastBoardIndex, #b + 1)
    source.lastBoardIndex = idx + 1
    return idx
  elseif position == "RIGHT_OF_SOURCE" and source and source.boardIndex then
    --[[ "Right of the source" only means anything on the source's OWN board.
         Leeroy Jenkins summons two Whelps for the OPPONENT: reading his board
         index and applying it to their board returned an index past the end of
         a possibly-empty table, and the unclamped table.insert then left a hole
         that Game:Reindex crashed on -- so the Whelps never arrived at all.

         The Beast only escaped this because a deathrattle's source is already
         off the board and has no boardIndex. ]]
    if source.controller == player then
      return math.min(source.boardIndex + 1, #b + 1)
    end
    return #b + 1
  elseif type(position) == "number" then
    return math.max(1, math.min(position, #b + 1))
  end
  return #b + 1   -- RIGHTMOST
end

--- Attach the hand-authored script's triggers/deathrattle to a live entity.
function Game:AttachScript(e)
  local s = self:ScriptFor(e.cardId)
  e.attackIsHealth = s and s.attackEqualsHealth or nil
  if not s then return end
  if s.triggers then
    for _, t in ipairs(s.triggers) do
      -- a HAND trigger (Bolvar) is read from the script by Bus:Collect while
      -- the card is held; in play it must do nothing
      if not t.inHand then
        e.triggers[#e.triggers + 1] = { on = t.on, cond = t.cond, ops = t.ops }
      end
    end
  end
  if s.deathrattle then e.deathrattles[#e.deathrattles + 1] = s.deathrattle.ops end
end

--- Put a minion onto the board. The single entry point for every summon,
--- whether from hand, a deathrattle, a token or a copy effect.
--[[ The entity most recently put onto the board or drawn. Noble Sacrifice
     summons a Defender and then redirects the attack ONTO it, Redemption
     resurrects a minion and then sets its health to 1, Holy Wrath draws a card
     and then deals its cost -- none of which can name the thing they just made
     without this. Cleared per op-list rather than per game so a stale value can
     never be read by an unrelated card. ]]
function Game:Summon(cardId, player, position, source)
  local p = self.players[player]
  if #p.board >= RULES.BOARD_SLOTS then return nil end
  local pr = self:Printed(cardId)
  if not pr then self:Error("Summon unknown card: " .. tostring(cardId)); return nil end

  local e = Entity.New(pr, player, self.ids)
  e.zone = ZONE.PLAY
  e.summonedTurn = self.turn
  self:AttachScript(e)
  self.bus:StampPlayOrder(e)

  local idx = self:ResolvePosition(player, position, source)
  table.insert(p.board, idx, e)
  self:Reindex(player)
  self:RecalcAuras()

  self.bus:Raise(EVENT.MINION_SUMMONED, { entity = e, player = player, source = source })
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
  return e
end

--- Copy a LIVE entity including its current buffs (Faceless Manipulator-style).
--- Mirror Entity uses Summon with fromPrinted instead -- see Ops.CopyToBoard.
function Game:SummonCopy(src, player, source)
  -- Echoing Ooze's copy stands beside the original, not at the far end
  local pos = (src.zone == ZONE.PLAY and src.controller == player and src.boardIndex)
              and src.boardIndex + 1 or "RIGHTMOST"
  local e = self:Summon(src.cardId, player, pos, source)
  if not e then return nil end
  self:CopyState(src, e)
  self:RecalcAuras()
  return e
end

--[[ What a copy of a live minion takes with it (Faceless Manipulator, Echoing
     Ooze): its enchantments, this-turn buffs, DAMAGE, whether its Divine
     Shield is still up, Silence, and any granted Spell Damage. "When Copying
     living minions, this includes Copying all damage and enchantments"
     (hearthstone.wiki.gg/wiki/Copy): a Yeti at 4/2 copies as a 4/2. A popped
     Argent Squire copies without a shield -- the keyword too, not only the
     flag, or the board and the AI show a shield that damage goes straight
     through. A silenced Stormwind Champion copies silenced. ]]
function Game:CopyState(src, e)
  e:CopyEnchantmentSources(src)
  e.ench.atk = src.ench.atk
  e.ench.hp  = src.ench.hp
  for k, v in pairs(src.enchKeywords or {}) do e.enchKeywords[k] = v end
  e.timedEnch = {}
  for _, x in ipairs(src.timedEnch or {}) do
    local copy = {}; for k, v in pairs(x) do copy[k] = v end
    e.timedEnch[#e.timedEnch + 1] = copy
  end
  e:RecalcTimed()
  e.spellDamageBonus = src.spellDamageBonus
  if src.silenced then
    e.silenced = true
    e.baseKeywords = {}
    e.triggers, e.deathrattles = {}, {}
  end
  e.divineShieldUp = src.divineShieldUp and e:Has(KW.DIVINE_SHIELD) or false
  if not e.divineShieldUp then
    e.baseKeywords[KW.DIVINE_SHIELD] = nil
    e.enchKeywords[KW.DIVINE_SHIELD] = nil
  end
  e.damage = src.damage or 0
end

--[[ Transform (Polymorph, Hex). The entity keeps its board slot and instanceId
     but becomes a different card entirely: damage, enchantments, triggers and
     deathrattle are all discarded. Critically it does NOT re-raise
     MINION_SUMMONED -- a polymorphed minion was not summoned, so Knife Juggler
     must not throw. ]]
function Game:Transform(e, cardId)
  local pr = self:Printed(cardId)
  if not pr then self:Error("Transform unknown card: " .. tostring(cardId)); return end
  e.printed = pr
  e.cardId  = pr.id
  e.base = { atk = pr.atk or 0, hp = pr.hp or 0, cost = pr.cost or 0, dur = pr.dur }
  e.baseKeywords = {}
  for _, k in ipairs(pr.keywords or {}) do e.baseKeywords[k] = true end
  e.enchantmentSources = {}
  e.ench = { atk = 0, hp = 0, cost = 0 }
  e.enchKeywords = {}
  e.timedEnch = {}
  e.timed = { atk = 0, hp = 0, cost = 0 }
  e.timedKeywords = {}
  e.damage = 0
  e.silenced = false
  --[[ A transformed minion is a new minion: no longer Frozen, no longer
       marked for death, no Ancient Mage bonus, and no Corruption waiting. ]]
  e.frozen, e.thawAtEndOfTurn, e.pendingDestroy = false, nil, false
  e.spellDamageBonus = nil
  e.enchGen = (e.enchGen or 0) + 1
  e.triggers = {}
  e.deathrattles = {}
  e.divineShieldUp = e.baseKeywords[KW.DIVINE_SHIELD] or false
  self:AttachScript(e)
  self:RecalcAuras()
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
end

--[[ Change controller (Mind Control, Sylvanas, Shadow Madness).
     * moves boards, appended rightmost on the new side
     * `owner` is untouched -- only `controller` changes. Zone moves (bounce,
       shuffle, death) follow the controller, as in Hearthstone
     * playOrder is preserved, so trigger ordering stays stable
     * the minion is summoning-sick on arrival: it cannot attack this turn
       unless it has Charge
     * both aura fields are recomputed, since it left one and entered another ]]
function Game:ChangeController(e, toPlayer)
  if e.zone ~= ZONE.PLAY or e.controller == toPlayer then return end
  local dest = self.players[toPlayer]
  if #dest.board >= RULES.BOARD_SLOTS then return end
  self:RemoveFromBoard(e)
  e.controller = toPlayer
  e.summonedTurn = self.turn
  e.attacksThisTurn = 0
  dest.board[#dest.board + 1] = e
  self:Reindex(toPlayer)
  self:RecalcAuras()
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
end

function Game:RecalcAuras() Aura.Recalc(self) end

-- ================================================================= weapons

function Game:EquipWeapon(player, cardId)
  local p = self.players[player]
  local pr = self:Printed(cardId)
  if not pr then self:Error("EquipWeapon unknown card: " .. tostring(cardId)); return end
  if p.weapon then self:DestroyWeapon(player) end
  local w = Entity.New(pr, player, self.ids)
  w.zone = ZONE.WEAPON
  w.base.hp = pr.dur or 0      -- durability is tracked in the health layer
  self:AttachScript(w)
  self.bus:StampPlayOrder(w)
  p.weapon = w
  self:RecalcAuras()
end

function Game:DestroyWeapon(player)
  local p = self.players[player]
  if not p.weapon then return end
  local w = p.weapon
  p.weapon = nil
  w.zone = ZONE.GRAVEYARD
  p.graveyard[#p.graveyard + 1] = w
  -- weapons can have deathrattles in the vanilla set; honour them
  for _, ops in ipairs(w.deathrattles or {}) do
    self.bus.queue[#self.bus.queue + 1] = {
      ops = ops,
      ctx = { source = w, controller = w.controller },
    }
  end
  self:RecalcAuras()
end

-- ================================================================== combat

--- Effective attack, including the equipped weapon for heroes.
function Game:AttackValue(e)
  local a = e:Attack()
  if e.printed.type == TYPE.HERO then
    local w = self.players[e.controller].weapon
    if w then a = a + w:Attack() end
  end
  return a
end

function Game:CanAttack(e)
  if self.over then return false end
  if e.controller ~= self.activePlayer then return false end
  if e.frozen then return false end
  if e:Has(KW.CANT_ATTACK) then return false end
  if self:AttackValue(e) <= 0 then return false end
  if e.printed.type == TYPE.MINION then
    if e.zone ~= ZONE.PLAY then return false end
    if e.summonedTurn == self.turn and not e:Has(KW.CHARGE) then return false end
  end
  return e.attacksThisTurn < self:AttacksAllowed(e)
end

--[[ HOW MANY TIMES THIS CHARACTER MAY SWING THIS TURN.

     One, two with Windfury -- and FOUR for Mega-Windfury, which exists on
     exactly one card and is printed in its TEXT and nowhere else. The vendored
     data gives V-07-TR-0N only CHARGE, so no importer could derive it; the
     card's effect script declares `attacksPerTurn` instead, which is the same
     mechanism Prophet Velen uses to declare a rule the DSL cannot express.

     THE BUG THIS FIXES: this was `Windfury and 2 or 1`, so the eight-mana
     four-attack finisher you assemble three Mechs to earn swung twice.

     A declared count WINS over Windfury rather than adding to it: Mega-Windfury
     replaces Windfury in Hearthstone, and a V-07-TR-0N given Windfury by
     Rockbiter Weapon still attacks four times, not six. ]]
function Game:AttacksAllowed(e)
  local s = self:ScriptFor(e.cardId)
  --[[ Silence removes Mega-Windfury, exactly as it removes Windfury: it is a
       keyword on the body, not a printed stat. ]]
  if s and s.attacksPerTurn and not e.silenced then return s.attacksPerTurn end
  --[[ A hero swings with its weapon's keywords: Doomhammer's Windfury is
       printed on the weapon, not the hero, and the hero attacked once. ]]
  if e.printed.type == TYPE.HERO then
    local w = self.players[e.controller].weapon
    if w and w:Has(KW.WINDFURY) then return 2 end
  end
  return e:Has(KW.WINDFURY) and 2 or 1
end

--[[ Taunt: if the defending side has any Taunt minion, only those (and not the
     hero) are legal attack targets.

     STEALTH HIDES A MINION FROM ATTACKS, not only from spells. Targeting.lua
     always refused to aim a spell at a stealthed enemy, but this list offered
     them to attackers -- so a Worgen Infiltrator or a Concealed board could be
     swung at the turn it hid, by the player and the practice bot alike. And a
     minion with both keywords imposes no Taunt while it is stealthed: Stealth
     wins in Hearthstone, which is why Conceal on a Taunt opens the way to the
     face until the Taunt next attacks. ]]
function Game:LegalAttackTargets(attacker)
  local foe = self:Opponent(attacker.controller)
  local p = self.players[foe]
  local taunts = {}
  for _, e in ipairs(p.board) do
    if e:IsTaunt() and not e:IsStealth() then taunts[#taunts + 1] = e end
  end
  if #taunts > 0 then return taunts end
  local out = {}
  for _, e in ipairs(p.board) do
    if not e:IsStealth() then out[#out + 1] = e end
  end
  out[#out + 1] = p.hero
  return out
end

function Game:IsLegalAttack(attacker, defender)
  if not self:CanAttack(attacker) then return false, "cannot attack" end
  if defender.controller == attacker.controller then return false, "friendly target" end
  for _, t in ipairs(self:LegalAttackTargets(attacker)) do
    if t == defender then return true end
  end
  return false, "taunt"
end

--[[ FORGETFUL -- "50% chance to attack the wrong enemy."

     Only Dunemaul Shaman (GVG_066) has this in the pinned pool.

     Two deliberate choices, both worth knowing about:

     1. THE REDIRECT IGNORES TAUNT. Legality is checked against the player's
        CHOSEN target first, so Taunt is still enforced on the declaration. The
        roll then reassigns to any other enemy character, Taunt or not. That is
        how Hearthstone's redirects behave -- they are not a second attack
        declaration, they are the same attack landing somewhere else.

     2. THE ROLL HAPPENS BEFORE PRE_ATTACK. So secrets see the FINAL target: a
        Dunemaul that gets redirected off the hero does not trigger Explosive
        Trap. The alternative ordering (secrets first, then redirect) would let
        a secret fire for an attack that never happened.
        I am not certain which order Hearthstone uses here. Flagged for the
        fidelity pass rather than asserted -- the choice is isolated to these
        few lines, so reversing it is trivial.

     Randomness routes through Game:Random, and the candidate list is built in
     board order then hero, so both clients redirect identically. ]]
function Game:ApplyForgetful(attacker, defender)
  if not attacker:Has(KW.FORGETFUL) then return defender end
  local foe = self:Opponent(attacker.controller)
  local p = self.players[foe]
  local alt = {}
  for _, e in ipairs(p.board) do
    if e ~= defender then alt[#alt + 1] = e end
  end
  if p.hero ~= defender then alt[#alt + 1] = p.hero end
  if #alt == 0 then return defender end            -- nowhere else to go
  if self:Random(2) ~= 1 then return defender end  -- 50%: hit the right one
  return alt[self:Random(#alt)]
end

--[[ Stealth is lost for good, from every layer that granted it. ]]
function Game.BreakStealth(e)
  e.enchKeywords[KW.STEALTH] = nil
  e:ForgetKeywordSource(KW.STEALTH)
  e.baseKeywords[KW.STEALTH] = nil
end

function Game:Attack(attacker, defender)
  if self:AwaitingChoice() then
    self:Error("attack while a choice is pending")
    return false
  end
  local ok, why = self:IsLegalAttack(attacker, defender)
  if not ok then self:Error("illegal attack: " .. tostring(why)); return false end

  -- Redirect AFTER legality (so Taunt gated the declaration) and BEFORE
  -- PRE_ATTACK (so secrets see where the blow actually lands).
  defender = self:ApplyForgetful(attacker, defender)

  local cancelled = false
  self.bus:Block(function()
    -- Attacking breaks Stealth before anything else observes the board.
    Game.BreakStealth(attacker)

    local payload = self.bus:Raise(EVENT.PRE_ATTACK, {
      attacker = attacker, defender = defender, target = defender,
    })
    --[[ RETARGETING. Misdirection and Noble Sacrifice move an attack to a
         different character, and a secret resolves INLINE inside this Raise --
         so the redirected defender is sitting in the payload by the time we get
         here. The defender must therefore be RE-READ rather than trusted from
         before the raise; reading the local was why no secret could ever move
         an attack.

         Read before the liveness checks below, so a redirect onto a legal
         character rescues an attack whose original defender the secret removed. ]]
    if payload.defender and payload.defender ~= defender then
      defender = payload.defender
    end
    -- Freezing Trap / Explosive Trap resolve here. The attack is abandoned if a
    -- secret cancelled it, or if either party left play or died in the process.
    if payload.cancelled or attacker.zone ~= ZONE.PLAY
       or (defender.zone ~= ZONE.PLAY and defender.printed.type ~= TYPE.HERO)
       or attacker:IsDead() then
      cancelled = true
      return
    end

    attacker.attacksThisTurn = attacker.attacksThisTurn + 1
    self.bus:Raise(EVENT.ATTACK_DECLARED, { attacker = attacker, defender = defender })
    -- "whenever this attacks" happens before the blow (Truesilver's heal)
    self.bus:ResolveQueued(ON_ATTACK)
    if attacker.zone ~= ZONE.PLAY or attacker:IsDead() then cancelled = true; return end

    -- Damage is simultaneous. Snapshot both attack values BEFORE either lands,
    -- so a minion reduced to 0 attack by the exchange still dealt full damage.
    local aAtk = self:AttackValue(attacker)
    local dAtk = self:AttackValue(defender)

    --[[ A HERO NEVER STRIKES BACK.

         Retaliation is a property of MINIONS: two minions trade because both
         have weapons in hand, so to speak. A hero's attack value comes from the
         weapon it is holding, and a held weapon only swings when its owner
         chooses to attack with it -- it does not cut anyone who walks into it.

         THE BUG THIS FIXES: a Rogue who equipped a dagger took a 1-damage
         counter-hit onto every minion that attacked their face, killing 1-health
         attackers outright, for as long as the weapon was equipped. It is also
         one of the few ways this engine could produce a board state that simply
         cannot occur in Hearthstone.

         Checked on the DEFENDER only. A hero attacking a minion still takes the
         minion's damage, which is the same rule seen from the other side: the
         minion is not retaliating, it is being attacked and hitting back
         because IT is a minion. ]]
    if defender.printed.type == TYPE.HERO then dAtk = 0 end

    --[[ Gladiator's Longbow: "Your hero is Immune while attacking." It cannot
         be a trigger -- only SECRETS resolve inline, and an ordinary trigger is
         queued behind this whole exchange, so the Immune would land after the
         retaliation it is supposed to prevent. So it is a weapon property read
         here, applied around the damage and removed immediately after.

         Removed unconditionally afterwards, including when the attack killed
         the hero's own weapon mid-exchange, or the hero would stay Immune. ]]
    local immuneFromWeapon = false
    if attacker.printed.type == TYPE.HERO then
      local w = self.players[attacker.controller].weapon
      local ws = w and self:ScriptFor(w.cardId)
      if ws and ws.immuneWhileAttacking then
        immuneFromWeapon = not attacker:Has(KW.IMMUNE)
        attacker.enchKeywords[KW.IMMUNE] = true
      end
    end

    self:DealDamage(defender, aAtk, attacker, false, true)
    if dAtk > 0 then self:DealDamage(attacker, dAtk, defender, false, true) end
    if immuneFromWeapon then attacker.enchKeywords[KW.IMMUNE] = nil end

    if attacker.printed.type == TYPE.HERO then
      local w = self.players[attacker.controller].weapon
      if w then
        --[[ Gorehowl: "Attacking a minion costs 1 Attack instead of 1
             Durability." A per-weapon property declared on its script rather
             than a branch naming the card, so the rule generalises.

             Only against a MINION. Gorehowl swung at a hero spends durability
             like any other weapon, which is the detail that makes it a
             minion-clearing weapon rather than an infinite one. ]]
        local ws = self:ScriptFor(w.cardId)
        local spendsAttack = ws and ws.weaponAttackCost
                             and defender.printed.type == TYPE.MINION
        if spendsAttack then
          w.ench.atk = w.ench.atk - 1
          if self:AttackValue(w) <= 0 then self:DestroyWeapon(attacker.controller) end
        else
          w.damage = w.damage + 1
          if w:Health() <= 0 then self:DestroyWeapon(attacker.controller) end
        end
      end
    end

    if defender.printed.type == TYPE.HERO then
      self.bus:Raise(EVENT.HERO_ATTACKED, { attacker = attacker, defender = defender })
    end
    self.bus:Raise(EVENT.ATTACK_RESOLVED, { attacker = attacker, defender = defender })
  end)
  return not cancelled
end

-- ========================================================= damage and heal

--- Friendly spell power: sum of printed spellDamage across minions in play.
function Game:SpellPower(player)
  local n = 0
  for _, e in ipairs(self.players[player].board) do
    --[[ Printed Spell Damage plus any GRANTED by an effect. Ancient Mage
         gives its neighbours Spell Damage +1, and reading only the printed
         field meant nothing an effect did could ever move it. Silence takes
         the printed amount away and clears the granted one; a bonus granted
         after the Silence (Velen's Chosen) counts. ]]
    if not e.silenced then n = n + (e.printed.spellDamage or 0) end
    n = n + (e.spellDamageBonus or 0)
  end
  return n
end

--[[ How many times a player's deathrattles fire. Declared as data
     (`deathrattleMultiplier` on a script) rather than by naming Baron
     Rivendare here, so the rule generalises. The HIGHEST multiplier wins rather
     than multiplying, which is what Hearthstone does with two Barons. ]]
function Game:DeathrattleMultiplier(player)
  local m = 1
  for _, e in ipairs(self.players[player].board) do
    if not e.silenced then
      local s = self:ScriptFor(e.cardId)
      if s and s.deathrattleMultiplier and s.deathrattleMultiplier > m then
        m = s.deathrattleMultiplier
      end
    end
  end
  return m
end

--[[ Auchenai Soulpriest: "Your cards and powers that restore Health now deal
     damage instead." Declared as data on the minion, like the two multipliers
     above, and read by Game:Heal. ]]
--[[ Steamwheedle Sniper: "Your Hero Power can target minions." Declared as
     data on the minion, like the other read-by-the-engine properties, and read
     by Targeting's REQ_MINION_OR_ENEMY_HERO. ]]
function Game:HeroPowerTargetsMinions(player)
  for _, e in ipairs(self.players[player].board) do
    if not e.silenced then
      local s = self:ScriptFor(e.cardId)
      if s and s.heroPowerTargetsMinions then return true end
    end
  end
  return false
end

--[[ Seconds a turn lasts. Nozdormu cuts it to 15 for BOTH players, so this is
     a property of the GAME rather than of a player.

     The countdown and the rope are client work: Client/FX/Director.lua reads
     this to time them. ]]
function Game:TurnSeconds()
  local n = RULES.TURN_SECONDS
  for pi = 1, 2 do
    for _, e in ipairs(self.players[pi].board) do
      if not e.silenced then
        local s = self:ScriptFor(e.cardId)
        if s and s.turnSeconds and s.turnSeconds < n then n = s.turnSeconds end
      end
    end
  end
  return n
end

function Game:HealsDealDamage(player)
  for _, e in ipairs(self.players[player].board) do
    if not e.silenced then
      local s = self:ScriptFor(e.cardId)
      if s and s.healsDealDamage then return true end
    end
  end
  return false
end

--- Prophet Velen doubles spell and hero-power damage AND healing. Declared by
--- the card's script rather than hardcoded, so the rule generalises.
function Game:SpellMultiplier(player)
  local m = 1
  for _, e in ipairs(self.players[player].board) do
    if not e.silenced then
      local s = self:ScriptFor(e.cardId)
      if s and s.spellMultiplier then m = m * s.spellMultiplier end
    end
  end
  return m
end

--[[ Spell power and the Velen multiplier, as one step.

     Split out of DealDamage because Imp-losion has to see the SCALED amount:
     it summons an Imp for each damage dealt, so with a Kobold Geomancer out a
     roll of 3 must deal 4 AND summon 4. Reading the raw roll gave 4 damage and
     3 Imps -- right in the obvious place, wrong in the one that matters.

     ImmuneToSpellpower is a property of the SOURCE CARD (Arcane Missiles
     carries it), never of the target -- getting that backwards is an easy and
     invisible mistake. It suppresses Spell Damage +N but NOT Prophet Velen,
     which doubles regardless. ]]
function Game:ScaleSpellDamage(amount, source, isSpell)
  if not (isSpell and source) then return amount end
  local owner = source.controller
  --[[ Hero powers get Velen but never Spell Damage: Fireblast with a Kobold
       Geomancer out still deals 1. ]]
  if not ns.HasPrintedKeyword(source.printed, KW.ImmuneToSpellpower)
     and not Game.IsHeroPower(source) then
    amount = amount + self:SpellPower(owner)
  end
  return amount * self:SpellMultiplier(owner)
end

--[[ The single damage funnel. Order of operations, which is observable:
       1. spell power and Velen multiplier (spells / hero powers only)
       2. PRE_DAMAGE, which listeners may mutate or zero
       3. Immune ignores everything
       4. Divine Shield absorbs the whole hit and pops
       5. hero armor absorbs before health
       6. Poisonous marks the survivor for destruction
       7. DAMAGE_DEALT, then the caller's block ends and deaths process
]]
function Game:DealDamage(target, amount, source, isSpell, isCombat)
  if not target or amount <= 0 or self.over then return 0 end
  if target.zone ~= ZONE.PLAY then return 0 end

  --[[ Spell scaling. ImmuneToSpellpower is a property of the SOURCE CARD
       (Arcane Missiles carries it), never of the target -- getting that
       backwards is an easy and invisible mistake. It suppresses Spell Damage
       +N but NOT Prophet Velen, which doubles regardless.

       Callers that already applied spell scaling at a higher level (see
       Ops.DamageRandomSplit, which scales the missile COUNT) pass
       isSpell=false for the individual hits to avoid double-dipping. ]]
  amount = self:ScaleSpellDamage(amount, source, isSpell)

  local payload = self.bus:Raise(EVENT.PRE_DAMAGE, {
    target = target, amount = amount, source = source, isSpell = isSpell,
  })
  amount = payload.amount or 0
  if amount <= 0 or payload.cancelled then return 0 end

  if target:Has(KW.IMMUNE) then return 0 end

  --[[ A minion that deals damage in any way loses Stealth, not only by
       attacking: Knife Juggler's knives, Ragnaros's end-of-turn shot under
       Conceal. A hit into Divine Shield still counts; one into Immune or
       cancelled outright does not. ]]
  if source and source ~= target and source.zone == ZONE.PLAY
     and source.printed and source.printed.type == TYPE.MINION and source:IsStealth() then
    Game.BreakStealth(source)
    self:RecalcAuras()
  end

  if target.divineShieldUp then
    target.divineShieldUp = false
    target.enchKeywords[KW.DIVINE_SHIELD] = nil
    target:ForgetKeywordSource(KW.DIVINE_SHIELD)
    target.baseKeywords[KW.DIVINE_SHIELD] = nil
    self:RecalcAuras()
    return 0
  end

  local dealt = amount
  if target.printed.type == TYPE.HERO and target.armor > 0 then
    local absorbed = math.min(target.armor, amount)
    target.armor = target.armor - absorbed
    amount = amount - absorbed
  end
  -- Commanding Shout-style floor, applied last so Divine Shield and armor have
  -- already had their say.
  local floor = self:DamageFloorFor(target)
  if floor then
    local maxDamage = target:Health() - floor
    if maxDamage < 0 then maxDamage = 0 end
    if amount > maxDamage then amount = maxDamage end
  end

  target.damage = target.damage + amount

  if source and source:Has(KW.POISONOUS)
     and target.printed.type == TYPE.MINION and amount > 0 then
    target.pendingDestroy = true
  end

  self:RecalcAuras()   -- enrage may have switched on
  self.bus:Raise(EVENT.DAMAGE_DEALT, {
    target = target, entity = target, amount = dealt, source = source, isSpell = isSpell,
    isCombat = isCombat,
  })
  return dealt
end

--- Is this entity a hero power card?
function Game.IsHeroPower(e)
  return e ~= nil and e.printed ~= nil and e.printed.type == TYPE.HERO_POWER
end

--[[ "Restore to full" is written as an amount of 99 or more. What it restores
     is the missing Health, and that is also what it becomes under Auchenai --
     an undamaged Stoneskin Gargoyle hurts itself for nothing, not for 99. ]]
Game.FULL_HEAL = 99

function Game:Heal(target, amount, source)
  if not target or amount <= 0 then return 0 end
  local full = amount >= Game.FULL_HEAL
  if full then
    amount = target.damage or 0
    if amount <= 0 then return 0 end
  end
  if source and self.players[source.controller] then
    --[[ Velen doubles healing from spells and hero powers only -- not a
         Lightwell, a Healing Totem or Truesilver Champion. ]]
    local t = source.printed and source.printed.type
    if not full and (t == TYPE.SPELL or t == TYPE.HERO_POWER) then
      amount = amount * self:SpellMultiplier(source.controller)
    end
    --[[ Auchenai Soulpriest turns the heal into damage. It is routed through
         DealDamage rather than subtracted here, so Divine Shield, Immune,
         armor and the death queue all behave -- a heal-as-damage that killed a
         minion had to be a real death, not a health edit. ]]
    if self:HealsDealDamage(source.controller) then
      return self:DealDamage(target, amount, source, false)
    end
  end
  local healed = math.min(amount, target.damage)
  target.damage = target.damage - healed
  if healed > 0 then
    self:RecalcAuras()   -- enrage may have switched off
    self.bus:Raise(EVENT.HEALED, { target = target, amount = healed, source = source })
  end
  return healed
end

-- ============================================================ death phase

--[[ Move everything dead to the graveyard SIMULTANEOUSLY, then queue
     deathrattles in play order. Returns true if anything died, so Bus:Drain
     knows to loop. Nothing else in the engine removes a dead entity. ]]
function Game:ProcessDeaths()
  local dead = {}
  for pi = 1, 2 do
    for _, e in ipairs(self.players[pi].board) do
      if e:IsDead() then dead[#dead + 1] = e end
    end
    --[[ Weapons break when durability runs out, and durability IS the weapon's
         health layer. This used to be missed entirely: ProcessDeaths scanned only
         the board, so a weapon losing its last point of durability to an effect
         (rather than to an attack) stayed equipped forever. Weapons are destroyed
         through DestroyWeapon rather than added to `dead`, because they do not
         enter the board graveyard as minions do. ]]
    local w = self.players[pi].weapon
    if w and w:Health() <= 0 then
      self:DestroyWeapon(pi)
    end
    --[[ Secrets live in their own zone, so a Destroy op marking one pendingDestroy
         used to be completely inert (Flare). Sweep them here; they are removed
         rather than added to `dead`, because a spent secret does not die as a
         minion does and must not fire a deathrattle. ]]
    local secrets = self.players[pi].secrets
    for si = #secrets, 1, -1 do
      if secrets[si].pendingDestroy then
        local sec = table.remove(secrets, si)
        sec.zone = ZONE.GRAVEYARD
        self.players[pi].graveyard[#self.players[pi].graveyard + 1] = sec
      end
    end
  end
  if #dead == 0 then
    self:CheckGameOver()
    return false
  end

  table.sort(dead, function(a, b)
    local ao, bo = a.playOrder or 0, b.playOrder or 0
    if ao ~= bo then return ao < bo end
    return a.instanceId < b.instanceId
  end)

  -- every slot is read before any minion leaves, so each is where it stood
  for _, e in ipairs(dead) do
    e.lastBoardIndex = e.boardIndex     -- a deathrattle summons into this slot
  end
  for _, e in ipairs(dead) do
    self:RemoveFromBoard(e)
    e.zone = ZONE.GRAVEYARD
    local p = self.players[e.controller]
    p.graveyard[#p.graveyard + 1] = e
    -- turn-scoped death log, in death order, for Kel'Thuzad
    if e.printed.type == TYPE.MINION then
      self.deathLog[#self.deathLog + 1] = {
        cardId = e.cardId, controller = e.controller, turn = self.turn,
      }
      -- for the whole game (Feugen and Stalagg): the graveyard also holds
      -- milled and burned cards, which never died
      self.diedThisGame = self.diedThisGame or { {}, {} }
      self.diedThisGame[e.controller][e.cardId] = true
    end
  end

  self:RecalcAuras()

  --[[ ALL the deaths are announced, and all their deathrattles queued in play
       order, before ANY of them resolves. Raised with no block open, each
       MINION_DIED used to drain on the spot: the first minion's deathrattle
       (and everything it caused) finished before the second one's was even
       queued. ]]
  self.bus.blockDepth = self.bus.blockDepth + 1
  for _, e in ipairs(dead) do
    local first = #self.bus.queue + 1
    local died = { entity = e, player = e.controller, deferSecrets = true }
    self.bus:Raise(EVENT.MINION_DIED, died)
    for _, sec in ipairs(self.bus:CollectSecrets(EVENT.MINION_DIED, died)) do
      self.bus.queue[#self.bus.queue + 1] = { secret = sec, payload = died,
                                             ctx = { source = sec, controller = sec.controller } }
    end
    -- A silenced minion has none: Entity:Silence clears the list.
    if #e.deathrattles > 0 then
      --[[ Baron Rivendare: "Your minions trigger their Deathrattles twice."
           Declared as data on the Baron rather than special-cased here, exactly
           like Prophet Velen's spellMultiplier, so the rule generalises and two
           Barons do not stack into four (Hearthstone's do not either -- the
           highest multiplier wins). ]]
      local times = self:DeathrattleMultiplier(e.controller)
      for _ = 1, times do
        for _, ops in ipairs(e.deathrattles) do
          self.bus.queue[#self.bus.queue + 1] = {
            ops = ops,
            ctx = { source = e, controller = e.controller },
          }
        end
      end
      self.bus:Raise(EVENT.DEATHRATTLE, { entity = e })
    end
    --[[ ONE DEATH'S REACTIONS RESOLVE IN PLAY ORDER of their sources: the
         dead minion's own deathrattle, "whenever a minion dies" triggers
         (Cult Master) and on-death Secrets (Duplicate, Redemption, Avenge).
         A Loot Hoarder played before Duplicate draws before Duplicate copies
         it. Duplicate used to go first always -- Secrets resolved inline,
         ahead of everything queued. ]]
    local slice = {}
    for i = first, #self.bus.queue do slice[#slice + 1] = { item = self.bus.queue[i], i = i } end
    table.sort(slice, function(a, b)
      local sa, sb = a.item.ctx and a.item.ctx.source, b.item.ctx and b.item.ctx.source
      local oa, ob = sa and sa.playOrder or 0, sb and sb.playOrder or 0
      if oa ~= ob then return oa < ob end
      return a.i < b.i
    end)
    for k, x in ipairs(slice) do self.bus.queue[first + k - 1] = x.item end
  end

  self.bus:Raise(EVENT.BOARD_CHANGED, {})
  self.bus.blockDepth = self.bus.blockDepth - 1
  self:CheckGameOver()
  if self.bus.blockDepth == 0 and not self.bus.draining then self.bus:Drain() end
  return true
end

function Game:CheckGameOver()
  if self.over then return true end
  -- IsDead, not Health: a destroyed hero (Sacrificial Pact on Lord Jaraxxus)
  -- is marked for destruction rather than damaged
  local d1 = self.players[1].hero:IsDead()
  local d2 = self.players[2].hero:IsDead()
  if not (d1 or d2) then return false end
  self.over = true
  if d1 and d2 then self.winner = 0          -- draw
  elseif d1 then self.winner = 2
  else self.winner = 1 end
  self.bus:Raise(EVENT.GAME_OVER, { winner = self.winner })
  return true
end

--[[ Concede. Hearthstone models this as the conceding hero simply dying, and so
     does this: everything that watches for the end of a game -- GAME_OVER, the
     winner field, the match history, the end-of-match choreography -- then
     happens on exactly one path instead of two.

     It does NOT raise a death or run deathrattles. The hero is not killed by
     damage, and a Warlock whose hero "died" must not hand the opponent a
     trigger nobody played. ]]
function Game:Concede(player)
  if self.over then return false, "already over" end
  if player ~= 1 and player ~= 2 then return false, "no such player" end
  self.conceded = player
  self.over = true
  self.winner = self:Opponent(player)
  self.bus:Raise(EVENT.GAME_OVER, { winner = self.winner, conceded = player })
  return true
end

-- ================================================================== secrets

function Game:PlaySecret(player, e)
  local p = self.players[player]
  if #p.secrets >= RULES.SECRET_SLOTS then return false end
  -- Hearthstone forbids two copies of the same secret in the zone at once.
  for _, s in ipairs(p.secrets) do
    if s.cardId == e.cardId then return false end
  end
  e.zone = ZONE.SECRET
  e.script = self:ScriptFor(e.cardId)
  self.bus:StampPlayOrder(e)
  p.secrets[#p.secrets + 1] = e
  return true
end

function Game:RevealSecret(s)
  local p = self.players[s.controller]
  for i = 1, #p.secrets do
    if p.secrets[i] == s then table.remove(p.secrets, i); break end
  end
  s.zone = ZONE.GRAVEYARD
  p.graveyard[#p.graveyard + 1] = s
  self.bus:Raise(EVENT.SECRET_REVEALED, { entity = s, player = s.controller })
end

-- ========================================================== player choices

--[[ A DECISION TAKEN MID-RESOLUTION.

  Tracking is the only card in the pool that stops to ask: "look at the top
  three cards of your deck, draw one and discard the others". The Choose One
  mode is decided BEFORE the card is played, so it is an argument to PlayCard;
  this is different -- the options do not exist until the card has begun
  resolving.

  So the card leaves a `pendingChoice` behind and the rest happens when the
  answer arrives. The three cards are removed from the deck IMMEDIATELY, which
  is what Hearthstone does: they are gone from the deck while you look at them,
  so a Thoughtsteal in between cannot see them.

  ACTIONS ARE REFUSED WHILE A CHOICE IS OUTSTANDING. Hearthstone stops the game
  to ask, and allowing plays in between would let a player act on information
  the opponent's client has not been told about yet -- which across the wire is
  a desync waiting to happen.

  Like the Choose One mode, the answer is a plain index: one byte in a lockstep
  frame, and both clients apply it identically. ]]

--- Is a decision outstanding? Every action path consults this.
function Game:AwaitingChoice()
  return self.pendingChoice ~= nil
end

--[[ Offer `entities` to `player` as a choice. They are already out of their
     old zone by the time this is called. ]]
function Game:OfferChoice(player, kind, entities)
  self.pendingChoice = { player = player, kind = kind, cards = entities }
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
end

--[[ Answer it. `index` picks from the offered list; everything else is
     discarded. Returns ok, reason.

     An out-of-range index is REFUSED rather than clamped: a clamp would quietly
     take a different card than the player chose, and across the wire the two
     clients would clamp the same way only by luck. ]]
function Game:ResolveChoice(player, index)
  local pc = self.pendingChoice
  if not pc then return false, "no choice pending" end
  if pc.player ~= player then return false, "not your choice" end
  if type(index) ~= "number" or index < 1 or index > #pc.cards then
    return false, "invalid choice"
  end

  self.pendingChoice = nil
  local p = self.players[player]
  for i, e in ipairs(pc.cards) do
    if i == index then
      if #p.hand >= RULES.HAND_LIMIT then
        -- a full hand burns the chosen card, exactly as an over-cap draw does
        e.zone = ZONE.GRAVEYARD
        p.graveyard[#p.graveyard + 1] = e
        self.bus:Raise(EVENT.CARD_BURNED, { player = player, entity = e })
      else
        e.zone = ZONE.HAND
        e.controller = player
        e.owner = player
        p.hand[#p.hand + 1] = e
      end
    else
      e.zone = ZONE.GRAVEYARD
      p.graveyard[#p.graveyard + 1] = e
    end
  end
  self:RecalcAuras()
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
  return true
end

-- ============================================================== playing cards

--[[ Play a card from hand. Returns ok, reason.

     `mode` is the Choose One selection: 1 or 2, indexing the card's printed
     `chooseOne` list in display order. It is required for a Choose One card and
     refused on any other, because a mode arriving on a card that has no modes
     means the caller got the card wrong and silently dropping it would play
     something other than what was chosen.

     The mode is decided BEFORE anything happens -- it has to be, since the
     mode's requirements decide what may be targeted -- so a rejected play
     leaves the hand untouched exactly as any other illegal play does. ]]
function Game:PlayCard(player, handIndex, target, position, mode)
  if self.over then return false, "game over" end
  if self:AwaitingChoice() then return false, "a choice is pending" end
  if player ~= self.activePlayer then return false, "not your turn" end
  local p = self.players[player]
  local card = p.hand[handIndex]
  if not card then return false, "no such card" end

  local modes = ns.Targeting.ModesOf(card)
  if modes then
    if mode ~= 1 and mode ~= 2 then return false, "mode required" end
  elseif mode ~= nil then
    return false, "card has no modes"
  end

  --[[ BOARD-STATE PLAY REQUIREMENTS, for every card and not only Choose One
       ones. Brawl's REQ_MINIMUM_TOTAL_MINIONS, Betrayal's
       REQ_MINIMUM_ENEMY_MINIONS, Upgrade!'s REQ_WEAPON_EQUIPPED and the seven
       REQ_NUM_MINION_SLOTS cards all live in printed data and were checked
       ONLY by Targeting.CanPlay -- which the UI uses to grey a card out, and
       which nothing on the way in ever consulted.

       So the rule held for a human clicking a greyed card and failed for
       everything else: the AI, a replayed action, and anything arriving over
       the wire could play Brawl into a single minion. Checked here, it holds
       for all of them.

       With mode = nil this reads the card's own requirements, so the Choose One
       path is the same call rather than a special case. ]]
  local playable, why = ns.Targeting.ModePlayable(self, card, player, mode)
  if not playable then return false, why end

  local cost = self:CardCost(card, player)
  if cost > self:AvailableMana(player) then return false, "not enough mana" end
  if card.printed.type == TYPE.MINION and #p.board >= RULES.BOARD_SLOTS then
    return false, "board full"
  end
  if ns.Targeting.NeedsTarget(self, card, player, mode) then
    if not target then return false, "target required" end
    if not ns.Targeting.IsLegalTarget(self, card, player, target, mode) then
      return false, "illegal target"
    end
  --[[ An "if available" battlecry may go untargeted, but a target it IS given
       must still be legal -- otherwise Big Game Hunter arriving over the wire
       could be aimed at a 2-attack minion and nothing here would notice. ]]
  elseif target and ns.Targeting.WantsTarget(self, card, player, mode)
     and not ns.Targeting.IsLegalTarget(self, card, player, target, mode) then
    return false, "illegal target"
  end

  table.remove(p.hand, handIndex)
  self:SpendMana(player, cost)
  self:ConsumeCostMods(card, player)

  --[[ Overload is PRINTED data, not a scripted effect. 9 vanilla cards plus the
       GvG Shaman cards carry it, and it applies on play like part of the cost --
       including when the card is then countered, exactly as spent mana is not
       refunded. Scripts must never declare overload; if they do, it double-counts. ]]
  if card.printed.overload then
    p.pendingOverload = p.pendingOverload + card.printed.overload
  end

  --[[ The chosen mode's script REPLACES the parent's, and nothing else about
       playing the card changes. That single substitution is the whole mechanic:
       Keeper of the Grove stays a minion whose mode runs as its battlecry, and
       Wrath stays a spell whose mode runs as its spell -- so Wrath's damage is
       boosted by Spell Damage and Moonfire's is not, which is exactly what the
       printed `$` sigil on one text and not the other says should happen.

       The parent card itself must therefore carry no script; the compiler
       rejects one, so this cannot silently pick the wrong body. ]]
  local script = self:ScriptFor(modes and modes[mode] or card.cardId)
  card.chosenMode = mode          -- for the log, the replay and the UI
  local isCombo = p.cardsPlayedThisTurn > 0
  p.cardsPlayedThisTurn = p.cardsPlayedThisTurn + 1

  self.bus:Block(function()
    local pre = self.bus:Raise(EVENT.PRE_CARD_PLAYED, {
      player = player, card = card, entity = card, target = target,
    })
    -- Counterspell: the card is countered but the mana is still spent.
    if pre.cancelled then
      card.zone = ZONE.GRAVEYARD
      p.graveyard[#p.graveyard + 1] = card
      return
    end

    local ctx = { source = card, controller = player, target = target }

    if card.printed.type == TYPE.MINION then
      p.minionsPlayedThisTurn = (p.minionsPlayedThisTurn or 0) + 1   -- Pint-Sized Summoner
      card.zone = ZONE.PLAY
      card.summonedTurn = self.turn
      self:AttachScript(card)
      self.bus:StampPlayOrder(card)
      local idx = position and math.max(1, math.min(position, #p.board + 1)) or (#p.board + 1)
      table.insert(p.board, idx, card)
      self:Reindex(player)
      self:RecalcAuras()

      self.bus:Raise(EVENT.MINION_SUMMONED, { entity = card, player = player })
      self.bus:Raise(EVENT.MINION_PLAYED,   { entity = card, player = player })
      self.bus:Raise(EVENT.CARD_PLAYED,     { player = player, card = card, entity = card })
      -- "whenever you play" (Questing Adventurer, Hobgoblin) before the battlecry
      self.bus:ResolveQueued(ON_PLAY)

      -- Combo replaces the battlecry when a card was already played this turn.
      if script then
        if isCombo and script.combo then
          Ops.Run(self, script.combo.ops, ctx)
        elseif script.battlecry then
          if ns.Conditions.Eval(self, script.battlecry.cond, ctx) then
            Ops.Run(self, script.battlecry.ops, ctx)
          end
        end
        self.bus:Raise(EVENT.BATTLECRY_RESOLVED, { entity = card })
      end
      if card.zone == ZONE.PLAY then
        self.bus:Raise(EVENT.AFTER_MINION_PLAYED, { entity = card, player = player })
      end

    elseif card.printed.type == TYPE.WEAPON then
      self:EquipWeapon(player, card.cardId)
      self.bus:Raise(EVENT.CARD_PLAYED, { player = player, card = card, entity = card })
      --[[ Weapons have battlecries too (Glaivezooka, Coghammer, Perdition's
           Blade). This branch used to equip and stop, so those scripts were dead
           data -- authored, compiled, and silently never run. The battlecry must
           resolve AFTER the weapon is equipped, because some of them read or buff
           the equipped weapon.

           ctx.source is the freshly equipped weapon entity, not the hand card, so
           `self` selectors refer to the thing now in the weapon slot. ]]
      local equipped = p.weapon
      if script and equipped then
        local wctx = { source = equipped, controller = player, target = target }
        if isCombo and script.combo then
          Ops.Run(self, script.combo.ops, wctx)
        elseif script.battlecry then
          if ns.Conditions.Eval(self, script.battlecry.cond, wctx) then
            Ops.Run(self, script.battlecry.ops, wctx)
          end
        end
        self.bus:Raise(EVENT.BATTLECRY_RESOLVED, { entity = equipped })
      end

    elseif card.printed.type == TYPE.SPELL then
      if self:IsSecret(card.printed) then
        --[[ A secret is a spell being cast: Counterspell can stop it, and Mana
             Wyrm, Auctioneer, Violet Teacher and the rest see it. ]]
        self.bus:Raise(EVENT.CARD_PLAYED, { player = player, card = card, entity = card })
        local spellCast = self.bus:Raise(EVENT.SPELL_CAST, {
          player = player, card = card, entity = card,
        })
        self.bus:ResolveQueued(ON_PLAY)
        if spellCast.cancelled or not self:PlaySecret(player, card) then
          card.zone = ZONE.GRAVEYARD
          p.graveyard[#p.graveyard + 1] = card
        end
      else
        self.bus:Raise(EVENT.CARD_PLAYED, { player = player, card = card, entity = card })
        local spellCast = self.bus:Raise(EVENT.SPELL_CAST, {
          player = player, card = card, entity = card, target = target,
        })
        --[[ SPELL RETARGETING. Spellbender summons a minion and makes the
             spell hit that instead, and a secret resolves INLINE inside the
             raise above -- so the redirected target is already sitting in the
             payload. Re-read it rather than trusting the local, exactly as
             Game:Attack re-reads its defender. ]]
        if spellCast.target and spellCast.target ~= target then
          target = spellCast.target
          ctx.target = target
        end
        --[[ "Whenever you cast a spell" resolves BEFORE the spell: Violet
             Teacher's Apprentice is there for Savage Roar, the Auctioneer draws
             first. A countered spell still counts as cast. ]]
        self.bus:ResolveQueued(ON_PLAY)
        if not spellCast.cancelled then
          ctx.isSpell = true
          if script then
            if isCombo and script.combo then Ops.Run(self, script.combo.ops, ctx)
            elseif script.spell then Ops.Run(self, script.spell.ops, ctx) end
          end
          --[[ The spell's deaths come before "after you cast a spell": a Wild
               Pyromancer the spell killed does not fire, and one that lives
               pings the Damaged Golem a Harvest Golem left behind (the
               deathrattle is queued ahead of the Pyromancer). ]]
          self:RecalcAuras()
          self:ProcessDeaths()
          self.bus:Raise(EVENT.SPELL_RESOLVED, { player = player, card = card, entity = card })
        end
        card.zone = ZONE.GRAVEYARD
        p.graveyard[#p.graveyard + 1] = card
      end
    end
  end)

  return true
end

--[[ Replace a player's hero power. Shadowform swaps Lesser Heal for Mind Spike
     and then Mind Spike for Mind Shatter; Jaraxxus installs INFERNO! alongside
     a new hero.

     The new power is READY. In Hearthstone a replaced hero power is a new card
     that has not been used: Shadowform after a Lesser Heal still lets you Mind
     Spike that turn, and Jaraxxus's INFERNO! is usable the turn he lands. (This
     used to keep the flag; docs/29.) ]]
function Game:SetHeroPower(player, cardId)
  local pr = self:Printed(cardId)
  if not pr then self:Error("SetHeroPower unknown card: " .. tostring(cardId)); return false end
  local p = self.players[player]
  local hp = Entity.New(pr, player, self.ids)
  hp.zone = ZONE.HERO_POWER
  p.heroPower = hp
  p.heroPowerUsedThisTurn = false
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
  return true
end

--[[ Replace a player's HERO. Lord Jaraxxus destroys your hero and becomes one:
     a fresh 15-health hero entity, a new hero power, and a weapon.

     NOTHING on the old hero carries over: not its damage (Jaraxxus arrives at
     15), not its Armor, not its Freeze. Jaraxxus "is considered to replace the
     previous hero. As a result, any modifiers affecting the previous hero will
     not be transferred. This includes Armor and the Frozen state"
     (hearthstone.wiki.gg, Lord Jaraxxus (Classic)). Armor used to be kept. ]]
function Game:ReplaceHero(player, heroCardId, heroPowerCardId)
  local pr = self:Printed(heroCardId)
  if not pr then self:Error("ReplaceHero unknown hero: " .. tostring(heroCardId)); return false end
  local p = self.players[player]
  local old = p.hero
  local hero = Entity.New(pr, player, self.ids)
  --[[ In PLAY, like the hero it replaces (Game.New). ZONE.HERO here made
       DealDamage and Attack treat Jaraxxus as absent: he could not be hurt
       and Blood Fury never swung. ]]
  hero.zone = ZONE.PLAY
  hero.playOrder = 0
  hero.armor = 0
  p.hero = hero
  if heroPowerCardId then self:SetHeroPower(player, heroPowerCardId) end
  self:RecalcAuras()
  self.bus:Raise(EVENT.BOARD_CHANGED, {})
  return true
end

function Game:UseHeroPower(player, target)
  if self.over then return false, "game over" end
  if self:AwaitingChoice() then return false, "a choice is pending" end
  if player ~= self.activePlayer then return false, "not your turn" end
  local p = self.players[player]
  if p.heroPowerUsedThisTurn then return false, "already used" end
  local hp = p.heroPower
  if not hp then return false, "no hero power" end
  local cost = hp:Cost()
  if cost > self:AvailableMana(player) then return false, "not enough mana" end

  --[[ HERO POWERS GO THROUGH TARGETING TOO. This used to validate no target at
       all, so Fireblast and Lesser Heal could be aimed at nothing, Reinforce
       could be used with a full board, and Totemic Call kept working after all
       four Totems were out. Six of the nine powers carry printed requirements.

       Same call the UI greys out with, so the rule holds identically for a
       click, for the practice AI, and for anything arriving over the wire. ]]
  local ok, why = ns.Targeting.ModePlayable(self, hp, player, nil)
  if not ok then return false, why end
  if ns.Targeting.NeedsTarget(self, hp, player) then
    if not target then return false, "target required" end
  end
  if target and not ns.Targeting.IsLegalTarget(self, hp, player, target) then
    return false, "illegal target"
  end

  self:SpendMana(player, cost)
  p.heroPowerUsedThisTurn = true
  local script = self:ScriptFor(hp.cardId)
  self.bus:Block(function()
    if script and script.heroPower then
      Ops.Run(self, script.heroPower.ops,
              { source = hp, controller = player, target = target, isSpell = true })
    end
  end)
  return true
end

-- ============================================================ introspection

--[[ Find a character by instance id.

     THIS IS WHAT LETS AN ACTION CROSS THE WIRE. A board position means
     something different the moment either board changes, so an action names its
     target by instance id -- and the ids agree on both clients for free,
     because both build the same game from the same seed and Entity.New hands
     them out in the same order.

     Deliberately searches only what an action may legally name: the two heroes
     and the two boards. A card in hand, in a deck, or in a graveyard is not a
     target any action can choose, and a lookup that could return one would turn
     a corrupt id into a silently wrong play rather than a refusal. ]]
function Game:EntityById(id)
  if not id then return nil end
  for pi = 1, 2 do
    local p = self.players[pi]
    if p.hero and p.hero.instanceId == id then return p.hero end
    for _, e in ipairs(p.board) do
      if e.instanceId == id then return e end
    end
  end
  return nil
end

--- Compact, order-sensitive state fingerprint. Exchanged at turn boundaries to
--- detect desync between the two clients. Deliberately includes board ORDER.
function Game:StateHash()
  local parts = { tostring(self.turn), tostring(self.activePlayer),
                  tostring(self.rngCalls), tostring(self.phase or "PLAY") }
  for pi = 1, 2 do
    local p = self.players[pi]
    parts[#parts + 1] = ("H%d:%d:%d"):format(pi, p.hero:Health(), p.hero.armor)
    parts[#parts + 1] = ("M%d:%d:%d:%d"):format(pi, p.mana, p.maxMana, p.lockedMana)
    parts[#parts + 1] = ("C%d:%d:%d:%d"):format(pi, #p.hand, #p.deck, #p.secrets)
    for _, e in ipairs(p.board) do
      parts[#parts + 1] = ("%s/%d/%d"):format(e.cardId, self:AttackValue(e), e:Health())
    end
  end
  local s = table.concat(parts, "|")
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483648 end
  return h, s
end

-- ================================================================== cloning

--[[ A COMPLETE, INDEPENDENT COPY OF THE GAME -- the practice bot's "what if".

  Client/AI.lua decides by trying: it plays a candidate move on a copy, through
  the same rules and the same card scripts, and looks at the board that comes
  out. That is the only honest way to know that Holy Light on an ENEMY minion
  helps the enemy, or that Cold Blood then an attack is lethal -- no reading of
  card text gets every one of four hundred cards right, and the engine already
  does.

  WHAT IS SHARED, NOT COPIED. Printed card data and effect scripts never change
  during a game (a script mutated per game would leak between games anyway), so
  every table reachable from ns.PrintedCards and ns.Scripts is referenced, not
  duplicated. Metatables are shared as well: they hold methods, not state.

  WHAT IS DROPPED. The bus's event log and presentation list are for hashing
  and animation; a copy that nobody draws or hashes starts them empty, which is
  most of the cost of a late-game copy otherwise.

  Cycles and aliasing survive: an entity reached twice (a board slot, an aura's
  source, a scheduled op's context) is copied ONCE and both references point at
  the copy, exactly as they point at one entity in the original. ]]
local sharedTables

local function markShared(t, seen)
  if seen[t] then return end
  seen[t] = true
  for k, v in pairs(t) do
    if type(k) == "table" then markShared(k, seen) end
    if type(v) == "table" then markShared(v, seen) end
  end
end

local function sharedSet()
  if not sharedTables then
    sharedTables = {}
    markShared(ns.PrintedCards or {}, sharedTables)
    markShared(ns.Scripts or {}, sharedTables)
  end
  return sharedTables
end

-- Hot: the practice bot copies a game hundreds of times per decision.
local type, next, getmetatable, setmetatable = type, next, getmetatable, setmetatable

local function copy(v, memo, shared)
  local c = {}
  memo[v] = c
  for k, x in next, v do
    if type(k) == "table" and not shared[k] then k = memo[k] or copy(k, memo, shared) end
    if type(x) == "table" and not shared[x] then x = memo[x] or copy(x, memo, shared) end
    c[k] = x
  end
  local mt = getmetatable(v)
  if mt then setmetatable(c, mt) end
  return c
end

function Game:Clone()
  local shared = sharedSet()
  local memo = {}
  -- Pre-seed the parts that are deliberately NOT carried over.
  local bus = self.bus
  local log, fired, errors = bus.log, bus.fired, self.errors
  memo[log], memo[fired], memo[errors] = {}, {}, {}
  local c = copy(self, memo, shared)
  return c
end

return Game
