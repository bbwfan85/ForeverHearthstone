--[[ Client/Controller.lua

  THE GLUE BETWEEN THE BOARD AND THE ENGINE.

  Board.lua turns mouse input into INTENTS and renders SNAPSHOTS. Game.lua
  enforces the rules. Nothing joined them: the Choose One work made that gap
  explicit -- the board emits PLAY_CARD with no mode, and something has to
  notice a mode is needed, raise the prompt, and re-issue the play.

  This is that something. It owns the Game, converts intents into engine calls,
  and produces the snapshot the board renders.

  NO WoW API IN THIS FILE. It lives under Client/ but imports nothing from the
  platform, exactly like Client/Assets and Client/FX, so the whole interaction
  model -- targeting, the mode prompt, attacking, ending a turn -- is testable
  headless. Client/Main.lua is the thin WoW-facing part.

  THE INTERACTION MODEL

  Playing a card can need up to two extra decisions, and they are taken in the
  order Hearthstone takes them:

      click/drag a card
        -> if it is Choose One and no mode is chosen yet:  MODE PROMPT
        -> if the chosen mode (or the card) takes a target: TARGETING
        -> play

  The mode comes first because the MODE decides what may be targeted: Keeper of
  the Grove's Moonfire may hit a hero and its Dispel may not, so asking for a
  target before the mode is chosen cannot know what is legal.

  Nothing is committed until the last decision is made. A cancel at any point
  leaves the hand untouched, because the engine is not called until then.
]]
local ADDON, ns = ...

local Controller = {}
Controller.__index = Controller
ns.Controller = Controller

function Controller.New(opts)
  opts = opts or {}
  local c = setmetatable({}, Controller)
  c.game     = opts.game
  c.me       = opts.player or 1
  c.onChange = opts.onChange or function() end
  c.pending  = nil        -- a play waiting on a mode and/or a target
  c.selected = nil        -- a minion picked as an attacker
  --[[ Cards marked to throw back, by hand index. Held here and not in the
       engine because a mulligan is not decided until it is confirmed -- the
       player toggles cards until they are happy, and nothing crosses the wire
       or touches the game until then. ]]
  c.mulliganMarks = {}

  --[[ WHERE A DECIDED ACTION GOES.

       The controller's job ends the moment every decision has been made: it
       builds an ACTION (Client/Actions.lua) and hands it over. In a practice
       match that means straight into the engine. In a duel it means
       Session:LocalAction, which applies it locally AND puts it on the wire.

       That seam is the whole reason networking did not require rewriting the
       interaction model: the controller does not know, and must not know,
       whether there is a second person on the other side. ]]
  c.submit = opts.submit or function(action)
    return ns.Actions.Run(c.game, c.me, action)
  end
  return c
end

--[[ Hand a finished action to whoever is taking them, then redraw. Every
     mutation in this file goes through here -- there is no second path that
     touches the game, because a second path is how the local player ends up
     playing by different rules from the wire. ]]
function Controller:Submit(action)
  local ok, why = self.submit(action)
  self.pending = nil
  self:Changed()
  return ok, why
end

-- ============================================================ snapshot

local function idsOf(list)
  local out = {}
  for i, e in ipairs(list or {}) do out[i] = e.cardId end
  return out
end

--[[ The board renders from this and nothing else. It is deliberately a flat
     table of ids and counts rather than live entities: the UI must not be able
     to mutate engine state, and this is also the shape that will go over the
     wire for the spectator view. ]]
-- Match damage amounts only; costs, draws, targets and Overload remain printed.
function Controller.SpellText(game, card)
  if card.printed.type ~= "SPELL" then return nil end
  local text = card.printed.text or ""
  --[[ A spell that hands you a new Hero Power (Shadowform) quotes ITS numbers:
       hero powers take no Spell Damage, so scaling them told the player a
       Mind Spike would hit harder than it does. ]]
  if text:find("Hero Power", 1, true) then return text end
  -- Prophet Velen doubles a spell's healing as well as its damage
  local mult = game:SpellMultiplier(card.controller)
  if mult ~= 1 then
    text = text:gsub("([Rr]estore )(%d+)", function(word, n) return word .. tostring(tonumber(n) * mult) end)
  end
  local function scale(n)
    if text:find("damage randomly split", 1, true) then
      return tostring((tonumber(n) + game:SpellPower(card.controller)) * game:SpellMultiplier(card.controller))
    end
    return tostring(game:ScaleSpellDamage(tonumber(n), card, true))
  end
  text = text:gsub("(%d+)([%d%s%-]*)( damage)", function(lo, rest, tail)
    if rest:match("^%s*%-%s*%d+$") then
      return scale(lo) .. rest:gsub("%d+", scale) .. tail
    end
    if rest == "" then return scale(lo) .. tail end
    return lo .. rest .. tail
  end)
  -- Mortal Strike's second number: "deal 6 instead" names no damage word
  return (text:gsub("([Dd]eal )(%d+)( instead)", function(word, n, tail) return word .. scale(n) .. tail end))
end

function Controller:Snapshot()
  local g = self.game
  if not g then return {} end
  local me  = g.players[self.me]
  local foe = g.players[g:Opponent(self.me)]

  --[[ A character, as the board draws it. Heroes and weapons are entities like
       any other, but the board must never hold one -- it holds numbers. ]]
  local function character(e)
    if not e then return nil end
    return {
      cardId = e.cardId, atk = g:AttackValue(e), health = e:Health(),
      maxHealth = e:MaxHealth(), armor = e.armor or 0,
      dur = e.printed and e.printed.dur and (e:MaxHealth()) or nil,
      frozen = e.frozen or false,
      immune = e:Has(ns.KEYWORD.IMMUNE),
    }
  end

  --[[ WHAT A MINION IS RIGHT NOW.

       `idsOf` gives the board as card ids, and a card id is PRINTED data --
       the 3/2 it was printed as, forever. So a minion that had taken two
       damage, or been buffed, or frozen, or silenced, still drew its printed
       stats: you hit something for three and the number under it did not move.
       The board was rendering the card, not the creature.

       These are the live numbers, read through the same calls the rules use, so
       a minion showing 4 attack is a minion that hits for 4. Kept parallel to
       `board` rather than replacing it, because the ids are what the resolver
       needs for art and text. ]]
  local function liveStats(list)
    local out = {}
    for i, e in ipairs(list or {}) do
      out[i] = {
        rulesText = Controller.SpellText(g, e),
        instanceId   = e.instanceId,
        effects      = e:EffectDescriptions(),
        atk          = g:AttackValue(e),
        health       = e:Health(),
        maxHealth    = e:MaxHealth(),
        damaged      = e:IsDamaged(),
        taunt        = e:IsTaunt(),
        divineShield = e:Has(ns.KEYWORD.DIVINE_SHIELD),
        stealth      = e:IsStealth(),
        frozen       = e:IsFrozen(),
        silenced     = e.silenced or false,
        sleeping     = e.summonedTurn == g.turn and not e:Has(ns.KEYWORD.CHARGE),
        exhausted    = e.attacksThisTurn >= g:AttacksAllowed(e),
        -- What Hearthstone marks on the portrait itself: the skull under a
        -- Deathrattle, the bolt under a triggered effect, the red rim of an
        -- active Enrage, and the Immune and can't-be-targeted sheens. Silence
        -- empties the lists, so a silenced minion loses its icons with them.
        deathrattle  = #(e.deathrattles or {}) > 0,
        trigger      = #(e.triggers or {}) > 0,
        enraged      = e.enraged or false,
        immune       = e:Has(ns.KEYWORD.IMMUNE),
        elusive      = e:IsElusive(),
      }
    end
    return out
  end

  local snap = {
    hand         = idsOf(me.hand),
    board        = idsOf(me.board),
    foeBoard     = idsOf(foe.board),
    boardStats   = liveStats(me.board),
    handStats    = liveStats(me.hand),
    foeBoardStats= liveStats(foe.board),
    foeHandCount = #foe.hand,
    maxMana      = me.maxMana,
    mana         = g:AvailableMana(self.me),
    lockedMana   = me.lockedMana or 0,
    --[[ THEIR MANA. Public information in Hearthstone and nowhere in this
         snapshot until now, so the board could not draw it and the player had
         to count turns to know what they could be hit with. It is safe to send
         -- unlike their hand, which is why that is a COUNT and this is not. ]]
    foeMaxMana    = foe.maxMana,
    foeMana       = g:AvailableMana(g:Opponent(self.me)),
    foeLockedMana = foe.lockedMana or 0,
    -- Overload owed NEXT turn, and the next fatigue hit: both public, both
    -- things a player should not have to remember
    pendingOverload    = me.pendingOverload or 0,
    foePendingOverload = foe.pendingOverload or 0,
    nextFatigue        = (me.fatigue or 0) + 1,
    foeNextFatigue     = (foe.fatigue or 0) + 1,
    -- during the mulligan the active player is the one who goes first
    goesFirst    = g.activePlayer == self.me,
    hasWeapon    = me.weapon ~= nil,
    foeHasWeapon = foe.weapon ~= nil,
    myTurn       = (g.activePlayer == self.me),
    over         = g.over,
    winner       = g.winner,
    player       = self.me,

    --[[ Everything below is what the board needs to look like Hearthstone
         rather than like a list of minions: the two heroes, the hero powers,
         the weapons, the deck piles, and -- the two that matter most for how
         the game FEELS -- which cards are playable right now and which minions
         can attack.

         They are computed HERE, through the same Targeting calls the rules use,
         so a card the board lights up green is a card the engine will accept.
         A UI that decides playability for itself is a UI that eventually
         disagrees with the rules. ]]
    heroId    = me.hero and me.hero.instanceId,
    foeHeroId = foe.hero and foe.hero.instanceId,
    hero      = character(me.hero),
    foeHero   = character(foe.hero),
    weapon    = character(me.weapon),
    foeWeapon = character(foe.weapon),
    deckCount    = #me.deck,
    turn         = g.turn,
    foeDeckCount = #foe.deck,
    heroClass    = me.class,
    foeClass     = foe.class,
  }

  snap.presentationEvents = {}
  snap.drawEvents = {}
  snap.burnEvents = {}
  for i = math.max(1, #g.bus.log - 63), #g.bus.log do
    local event = g.bus.log[i]
    if (event.event == ns.EVENT.CARD_DRAWN and event.burned) or event.event == ns.EVENT.CARD_BURNED then
      -- a burned card is revealed to both players, as in Hearthstone
      snap.burnEvents[#snap.burnEvents+1] = {seq=event.seq, mine=event.player == self.me,
        cardId=event.cardId, drawn=event.event == ns.EVENT.CARD_DRAWN,
        -- a minion bounced into a full hand burns from where it stood
        entityId=event.entityId}
    end
    if event.event == ns.EVENT.CARD_DRAWN and not event.burned then
      snap.drawEvents[#snap.drawEvents+1] = {seq=event.seq,
        mine=event.player == self.me,
        entityId=event.player == self.me and event.entityId or nil}
    end
    if event.event == ns.EVENT.FATIGUE then
      snap.presentationEvents[#snap.presentationEvents+1] = {
        seq=event.seq, fatigue=true, amount=event.amount,
        targetId=g.players[event.player].hero.instanceId,
      }
    end
    if event.event == ns.EVENT.DAMAGE_DEALT or event.event == ns.EVENT.HEALED then
      snap.presentationEvents[#snap.presentationEvents+1] = {
        seq=event.seq, targetId=event.targetId, amount=event.amount,
        targetCardId=event.targetCardId, healthAfter=event.healthAfter, armorAfter=event.armorAfter,
        heal=event.event == ns.EVENT.HEALED,
      }
    end
  end
  snap.eventSeq = g.bus.seq
  if me.heroPower then
    snap.heroPower = {
      cardId = me.heroPower.cardId,
      cost   = g:CardCost(me.heroPower, self.me),
      used   = me.heroPowerUsedThisTurn or false,
      usable = (g.activePlayer == self.me) and not me.heroPowerUsedThisTurn
               and g:CardCost(me.heroPower, self.me) <= g:AvailableMana(self.me)
               and ns.Targeting.CanPlay(g, me.heroPower, self.me),
    }
  end
  if foe.heroPower then
    --[[ Their power's COST and whether they have spent it this turn. Both were
         missing, so the board drew their hero power as a bare icon with an
         empty cost badge -- "the mana cost for the enemy power ability doesn't
         work". `usable` is deliberately NOT sent: that would need their hand
         and their targets, and it is not information you are owed. ]]
    snap.foeHeroPower = {
      cardId = foe.heroPower.cardId,
      cost   = g:CardCost(foe.heroPower, g:Opponent(self.me)),
      used   = foe.heroPowerUsedThisTurn or false,
    }
  end

  -- which hand cards are playable right now (the green glow)
  snap.playable = {}
  for i, card in ipairs(me.hand) do
    snap.playable[i] = (g.activePlayer == self.me)
                       and ns.Targeting.CanPlay(g, card, self.me) or false
  end
  -- and which of those would do their extra thing now (the gold glow)
  snap.poweredUp = {}
  for i, card in ipairs(me.hand) do
    snap.poweredUp[i] = snap.playable[i] and ns.Targeting.PoweredUp(g, card, self.me) or false
  end
  snap.handNeedsTarget = {}
  snap.handLegalTargets = {}
  for i, card in ipairs(me.hand) do
    snap.handNeedsTarget[i] = ns.Targeting.NeedsTarget(g, card, self.me)
    local legal = {}
    for _, e in ipairs(ns.Targeting.LegalTargets(g, card, self.me) or {}) do
      legal[e.instanceId] = true
    end
    snap.handLegalTargets[i] = legal
  end
  snap.handCost = {}
  for i, card in ipairs(me.hand) do
    snap.handCost[i] = g:CardCost(card, self.me)
  end
  --[[ The card the player has clicked but not yet placed. It is held here and
       not in the engine for the same reason a mulligan mark is: nothing has
       happened yet, and nothing may cross the wire until it does. ]]
  snap.selectedHand = self.selectedHand

  --[[ CAN YOU AFFORD IT. Separate from `playable`, which also covers "no legal
       target" and "the board is full" -- the mana gem answers the cost
       question alone, because that is the question the gem is. ]]
  snap.affordable = {}
  for i, card in ipairs(me.hand) do
    snap.affordable[i] = (g:CardCost(card, self.me) <= g:AvailableMana(self.me))
  end

  -- which of your minions can swing (the attack-ready glow)
  snap.canAttack = {}
  for i, e in ipairs(me.board) do
    snap.canAttack[i] = g:CanAttack(e) or false
  end
  --[[ And your HERO, when it is holding a weapon. Without this the one piece
       of feedback that says "you have an attack available" was missing from
       the only attacker that is not a minion. ]]
  snap.heroCanAttack = me.hero and g:CanAttack(me.hero) or false

  snap.combatPreview = {}
  if self.selected and g:CanAttack(self.selected) then
    local attacker = self.selected
    local function dies(target, source, damage)
      if damage <= 0 or target:Has(ns.KEYWORD.DIVINE_SHIELD) or target:Has(ns.KEYWORD.IMMUNE) then return false end
      if target.printed.type == ns.CARDTYPE.MINION and source:Has(ns.KEYWORD.POISONOUS) then return true end
      return damage >= target:Health() + (target.armor or 0)
    end
    for _, defender in ipairs(g:LegalAttackTargets(attacker)) do
      local retaliation = defender.printed.type == ns.CARDTYPE.HERO and 0 or g:AttackValue(defender)
      snap.combatPreview[defender.instanceId] = {
        attackerDies=dies(attacker, defender, retaliation),
        defenderDies=dies(defender, attacker, g:AttackValue(attacker)),
      }
    end
  end

  -- the thing currently picked as an attacker, so the board can mark it
  if self.selected then
    if self.selected == me.hero then
      snap.heroSelected = true
    else
      for i, e in ipairs(me.board) do
        if e == self.selected then snap.selectedIndex = i break end
      end
    end
  end

  -- A pending mode choice becomes the prompt the board draws.
  local p = self.pending
  if p and p.options then
    snap.chooseOne = {
      handIndex = p.handIndex,
      position  = p.position,
      options   = p.options,
    }
  end
  --[[ A pending target request becomes the highlight set. `position` rides
       along so a minion waiting on its battlecry can be drawn standing in the
       slot it was dropped into while it aims. ]]
  if p and p.awaitingTarget then
    snap.targeting = { handIndex = p.handIndex, legal = p.legalTargetIds,
                       heroPower = p.heroPower or nil, position = p.position }
  end

  --[[ SECRETS.

       Yours by name; theirs as a COUNT ONLY. Both clients hold the whole game
       state in lockstep, so this client could read the opponent's secrets --
       and the snapshot is exactly where that must not happen. The board can
       only draw what the snapshot carries, so leaving them out is what makes
       "the UI never shows you what you should not know" a structural property
       rather than a promise. ]]
  snap.secrets = {}
  for i, e in ipairs(me.secrets) do
    local printed = g:Printed(e.cardId)
    snap.secrets[i] = { cardId = e.cardId,
                        name = printed and printed.name or e.cardId,
                        -- the live numbers, as on the card in hand (Explosive Trap with Spell Damage)
                        text = Controller.SpellText(g, e) or (printed and printed.text) or "" }
  end
  snap.foeSecretCount = #foe.secrets

  --[[ THE MULLIGAN. Both players choose at once, so this is not a turn and
       `myTurn` says nothing about it. ]]
  if g:AwaitingMulligan() then
    if not self.openingHand then self.openingHand = idsOf(me.hand) end
    local marked = {}
    for i in pairs(self.mulliganMarks) do marked[i] = true end
    snap.mulligan = {
      hand = self.openingHand,
      marked = marked,
      --[[ True once we have submitted and are waiting for them. The board draws
           this as "waiting for your opponent" rather than leaving a dead
           confirm button the player will click again. ]]
      waiting = not g:AwaitingMulligan(self.me),
      coin = (g.activePlayer ~= self.me),
    }
  else
    self.openingHand = nil
    self.mulliganMarks = {}
  end

  --[[ A choice raised MID-RESOLUTION (Tracking). Unlike the Choose One prompt,
       this one is not a pending play the controller is holding -- the card has
       already resolved this far and the engine is waiting. It renders through
       the same prompt, so the board needs one shape for both. ]]
  local pc = g.pendingChoice
  if pc and pc.player == self.me then
    local options = {}
    for i, e in ipairs(pc.cards) do
      local printed = g:Printed(e.cardId)
      options[i] = {
        mode = i, cardId = e.cardId,
        name = printed and printed.name or e.cardId,
        text = printed and printed.text or "",
        playable = true,
      }
    end
    snap.chooseOne = { kind = pc.kind, choice = true, options = options }
  end
  return snap
end

function Controller:Changed() self.onChange(self:Snapshot()) end

-- ============================================================ helpers

--[[ Resolve a click to the entity it names. The board reports positions, not
     entities, on purpose -- an index is all that can safely cross the wire. ]]
function Controller:EntityAt(kind, index)
  local g = self.game
  local foe = g:Opponent(self.me)
  if kind == "CLICK_BOARD"     then return g.players[self.me].board[index] end
  if kind == "CLICK_FOE_BOARD" then return g.players[foe].board[index] end
  if kind == "CLICK_HERO"      then return g.players[self.me].hero end
  if kind == "CLICK_FOE_HERO"  then return g.players[foe].hero end
  return nil
end

local function instanceIds(list)
  local out = {}
  for i, e in ipairs(list) do out[i] = e.instanceId end
  return out
end

--[[ Begin, or continue, playing the card in `handIndex`. Called on the first
     click and again after each decision, so the same function decides what is
     still outstanding rather than the decision points each knowing the next. ]]
function Controller:BeginPlay(handIndex, position, mode)
  local g = self.game
  local card = g.players[self.me].hand[handIndex]
  if not card then return false, "no such card" end

  local T = ns.Targeting
  local modes = T.ModesOf(card)

  -- 1. a Choose One card needs its mode before anything else
  if modes and not mode then
    self.pending = {
      handIndex = handIndex, position = position,
      options   = T.ModeOptions(g, card, self.me),
    }
    --[[ Each mode card's text with Spell Damage in it, as the card in hand shows
         it: Starfall read 6 and 3 in hand and 5 and 2 in the prompt. Only for a
         SPELL being played: a minion's modes are battlecries, which take no
         Spell Damage and no Velen (Keeper of the Grove still deals 2). ]]
    for _, opt in ipairs(self.pending.options or {}) do
      local printed = g:Printed(opt.cardId)
      if printed and printed.type == "SPELL" and card.printed.type == "SPELL" then
        local ok, text = pcall(Controller.SpellText, g, { printed = printed, controller = self.me, cardId = opt.cardId })
        if ok and text and text ~= printed.text then opt.liveText = text end
      end
    end
    self:Changed()
    return true, "awaiting mode"
  end

  --[[ 2. then a target, if the card or the chosen mode takes one.

       WantsTarget, not NeedsTarget: a battlecry printed "if available"
       (Ironforge Rifleman, Big Game Hunter, Shattered Sun Cleric) MUST be aimed
       when anything can be aimed at. Asking NeedsTarget alone committed those
       with no target and their battlecry did nothing. When nothing is legal the
       minion is simply played, as Hearthstone plays it. ]]
  local want = T.WantsTarget(g, card, self.me, mode)
  if want then
    local legal = T.LegalTargets(g, card, self.me, mode)
    if #legal == 0 and want == "optional" then
      return self:Commit(handIndex, position, mode, nil)
    end
    if #legal == 0 then
      self.pending = nil
      self:Changed()
      return false, "no legal target"
    end
    self.pending = {
      handIndex = handIndex, position = position, mode = mode,
      awaitingTarget = true, legalTargetIds = instanceIds(legal),
    }
    self:Changed()
    return true, "awaiting target"
  end

  return self:Commit(handIndex, position, mode, nil)
end

function Controller:Commit(handIndex, position, mode, target)
  return self:Submit({
    kind = "PLAY_CARD", handIndex = handIndex, position = position,
    mode = mode, targetId = target and target.instanceId or nil,
  })
end

-- ========================================================== the mulligan

--[[ Mark or unmark a card for replacement. Nothing is committed -- the player
     toggles until they are happy, and the game is only told on confirm. ]]
function Controller:ToggleMulligan(handIndex)
  local g = self.game
  if not g:AwaitingMulligan(self.me) then return false, "not mulliganing" end
  local hand = g.players[self.me].hand
  if not handIndex or not hand[handIndex] then return false, "no such card" end
  --[[ The Coin cannot be thrown back. It is not part of the dealt hand -- it is
       compensation for going second -- and offering it would be offering
       something the rules will refuse. ]]
  if hand[handIndex].cardId == "GAME_005" then return false, "the Coin stays" end
  if self.mulliganMarks[handIndex] then
    self.mulliganMarks[handIndex] = nil
  else
    self.mulliganMarks[handIndex] = true
  end
  self:Changed()
  return true
end

--[[ Commit. Keeping everything is a perfectly ordinary mulligan and needs no
     special case -- an empty index list is a valid action. ]]
function Controller:ConfirmMulligan()
  local g = self.game
  if not g:AwaitingMulligan(self.me) then return false, "already done" end
  local indices = {}
  for i in pairs(self.mulliganMarks) do indices[#indices + 1] = i end
  --[[ Sorted so that the same choice always encodes to the same bytes.

       NOT for determinism: Game:ApplyMulligan builds a SET from this list and
       iterates the hand itself, so the order here cannot change the outcome and
       two clients cannot disagree because of it. (A mutation removing this sort
       was correctly not caught by any behavioural test -- it changes nothing
       observable about the game.) What it buys is a stable action log, which is
       worth one line when the log is the thing you read to reproduce a
       desync. ]]
  table.sort(indices)
  --[[ The marks STAY until the mulligan is over. They were cleared here, so
       while you waited for your opponent the cards you had thrown back showed
       without their crosses, as though you had kept them. The next snapshot
       after both have chosen clears them (Snapshot). ]]
  return self:Submit({ kind = "MULLIGAN", indices = indices })
end

-- ========================================================= the hero power

--[[ Using the hero power goes through the SAME targeting flow a card does.

     THE BUG THIS FIXES: Fireblast and Lesser Heal require a target, the board's
     hero power button sent none, and there was no way to supply one -- so two
     of the nine classes could not use their hero power at all through the UI.
     The engine was right to refuse; nothing ever asked it correctly. ]]
function Controller:BeginHeroPower(targetId)
  local g = self.game
  local hp = g.players[self.me].heroPower
  if not hp then return false, "no hero power" end

  local T = ns.Targeting
  if not targetId and T.NeedsTarget(g, hp, self.me) then
    local legal = T.LegalTargets(g, hp, self.me)
    if #legal == 0 then
      self.pending = nil
      self:Changed()
      return false, "no legal target"
    end
    self.pending = {
      heroPower = true, awaitingTarget = true,
      legalTargetIds = instanceIds(legal),
    }
    self:Changed()
    return true, "awaiting target"
  end
  return self:Submit({ kind = "HERO_POWER", targetId = targetId })
end

-- ============================================================ intents

--[[ One entry point for everything the board can report. Returns ok, reason --
     a refusal is normal (an illegal target, a card that costs too much) and is
     reported rather than thrown, because the UI wants to say why. ]]
--[[ WHICH OF THE HERO'S ERROR LINES A REFUSAL IS.

     Hearthstone answers an illegal move with the hero's own voice ("I need
     more mana", "a taunt minion is in the way") and the categories are the
     ones the recordings are labelled with (Client/Assets/HeroVoice.lua). Most
     refusals map by their reason alone; the attack refusals need the board, so
     HandleIntent records those where it can still see the attacker. ]]
local REFUSAL_VOICE = {
  ["not enough mana"] = "mana",
  ["board full"]      = "full_board",
  ["taunt"]           = "taunt",
  ["illegal target"]  = "target",
  ["no legal target"] = "target",
  ["target required"] = "target",
  ["unknown target"]  = "target",
  ["friendly target"] = "target",
  ["already used"]    = "cant_play",
  ["no playable mode"]= "cant_play",
}

function Controller:WhyNoAttack(e)
  local g = self.game
  if e.printed.type == ns.CARDTYPE.MINION and e.summonedTurn == g.turn
     and not e:Has(ns.KEYWORD.CHARGE) then
    return "summon_sick"
  end
  if e.attacksThisTurn > 0 and e.attacksThisTurn >= g:AttacksAllowed(e) then
    return e.printed.type == ns.CARDTYPE.MINION and "minion_attacked" or "hero_attacked"
  end
  if e.printed.type ~= ns.CARDTYPE.MINION and g:AttackValue(e) <= 0 then
    return "need_weapon"
  end
  return "generic"
end

-- Read once: the voice belongs to the refusal that just happened.
function Controller:RefusalVoice(why)
  local voice = self.refusalVoice or REFUSAL_VOICE[why or ""]
  self.refusalVoice = nil
  return voice
end

function Controller:HandleIntent(intent)
  self.refusalVoice = nil
  local g = self.game
  if not g then return false, "no game" end
  local kind = intent and intent.kind
  if not kind then return false, "no intent" end

  if kind == "CANCEL_MODE" or kind == "CANCEL" then
    self.pending = nil
    self.selected = nil
    self.selectedHand = nil
    self:Changed()
    return true
  end

  --[[ The mulligan comes before everything, including the game-over check:
       nothing else may be done while it is outstanding, and the engine refuses
       it anyway (Client/Actions.lua). ]]
  if kind == "CLICK_MULLIGAN" then
    return self:ToggleMulligan(intent.handIndex)
  end
  if kind == "CONFIRM_MULLIGAN" then
    return self:ConfirmMulligan()
  end
  if g:AwaitingMulligan(self.me) then
    return false, "choose which cards to throw back first"
  end

  if g.over then return false, "game over" end

  if kind == "END_TURN" then
    if g.activePlayer ~= self.me then return false, "not your turn" end
    self.pending, self.selected = nil, nil
    return self:Submit({ kind = "END_TURN" })
  end

  --[[ A PLAY_CARD carrying a mode, while the ENGINE is waiting on a choice, is
       the board answering that choice -- it renders through the same prompt and
       reports the same intent. Checked before the ordinary play path, because
       nothing may be played until the choice is answered. ]]
  if g:AwaitingChoice() then
    if kind == "PLAY_CARD" and intent.mode then
      return self:Submit({ kind = "CHOICE", index = intent.mode })
    end
    return false, "a choice is pending"
  end

  if kind == "PLAY_CARD" then
    if g.activePlayer ~= self.me then return false, "not your turn" end
    return self:BeginPlay(intent.handIndex, intent.position, intent.mode)
  end

  --[[ A click means different things depending on what is outstanding, and the
       order of these branches IS the interaction model: a pending target
       consumes the next click, otherwise a click selects an attacker or
       declares an attack. ]]
  if kind == "CLICK_BOARD" or kind == "CLICK_FOE_BOARD"
     or kind == "CLICK_HERO" or kind == "CLICK_FOE_HERO" then
    local e = self:EntityAt(kind, intent.boardIndex)
    if not e then return false, "nothing there" end

    local p = self.pending
    if p and p.awaitingTarget then
      --[[ A pending hero power consumes the click exactly as a pending card
           does -- same branch, same legality check, same refusal. ]]
      local source = p.heroPower and g.players[self.me].heroPower
                     or g.players[self.me].hand[p.handIndex]
      if not source then self.pending = nil; return false, "card is gone" end
      if not ns.Targeting.IsLegalTarget(g, source, self.me, e, p.mode) then
        return false, "illegal target"
      end
      if p.heroPower then
        return self:Submit({ kind = "HERO_POWER", targetId = e.instanceId })
      end
      return self:Commit(p.handIndex, p.position, p.mode, e)
    end

    if g.activePlayer ~= self.me then return false, "not your turn" end

    --[[ A SELECTED HAND CARD IS WAITING TO BE PUT SOMEWHERE. Clicking the
         board is where to put it -- the two-click path to the same play a drag
         makes in one gesture. ]]
    if self.selectedHand then
      local handIndex = self.selectedHand
      self.selectedHand = nil
      if kind == "CLICK_BOARD" then
        return self:BeginPlay(handIndex, intent.boardIndex, nil)
      end
      return self:BeginPlay(handIndex, nil, nil)
    end

    --[[ SELECT AN ATTACKER. Your own minions, AND YOUR OWN HERO.

         THE BUG THIS FIXES: a hero holding a weapon can attack -- Game:CanAttack
         has always said so, because AttackValue covers the weapon -- but
         CLICK_HERO was not in this branch. It fell through to "what should the
         selected thing hit", found nothing selected, and reported "nothing
         selected". So a Rogue could equip Wicked Knife, see the 1 attack on
         their portrait, and have no way whatsoever to swing it. Every weapon
         class was affected; the engine was right the entire time and nothing
         ever asked it. ]]
    if kind == "CLICK_BOARD" or kind == "CLICK_HERO" then
      if g:CanAttack(e) then
        self.selected = e
        self:Changed()
        return true
      end
      --[[ Clicking your own face with nothing to swing is not an error worth
           a message -- it is the most common misclick on the board. A hero
           that DID swing this turn still says so, as Hearthstone's does. ]]
      if kind == "CLICK_HERO" then
        if g:AttackValue(e) > 0 and e.attacksThisTurn > 0 then
          self.refusalVoice = "hero_attacked"
        end
        return false, "not your turn"
      end
      self.refusalVoice = self:WhyNoAttack(e)
      return false, "cannot attack"
    end

    -- ...then click what it should hit
    if self.selected then
      local attacker = self.selected
      self.selected = nil
      local legal, reason = g:IsLegalAttack(attacker, e)
      if not legal then
        if reason == "taunt" then self.refusalVoice = "taunt" end
        self:Changed()
        return false, "illegal attack"
      end
      return self:Submit({ kind = "ATTACK",
                           attackerId = attacker.instanceId, targetId = e.instanceId })
    end
    return false, "nothing selected"
  end

  --[[ A CLICK ON A HAND CARD DOES NOT PLAY IT.

       It used to play the card into the rightmost slot the instant you clicked
       it, so brushing a card you were reading threw it onto the board -- with
       no confirmation, no position, and no way back. Cards are PLAYED BY
       DRAGGING them, which is both the gesture Hearthstone uses and the only
       one that can say where a minion goes.

       A click selects, which is what makes a card the subject of the next
       thing you do: it raises the card, and it is how a keyboard or a
       one-button user still reaches a play (select, then click the board).

       `intent.mode` still commits, because that click is the Choose One prompt
       answering itself rather than a click on the hand. ]]
  if kind == "CLICK_HAND" then
    if intent.mode then
      if g.activePlayer ~= self.me then return false, "not your turn" end
      return self:BeginPlay(intent.handIndex, intent.position, intent.mode)
    end
    if self.selectedHand == intent.handIndex then
      self.selectedHand = nil
    else
      self.selectedHand = intent.handIndex
    end
    self.selected = nil
    self:Changed()
    return true
  end

  if kind == "HERO_POWER" then
    if g.activePlayer ~= self.me then return false, "not your turn" end
    return self:BeginHeroPower(intent.targetId)
  end

  return false, "unknown intent " .. tostring(kind)
end

--[[ A legal 30-card Basic deck for a class, built from PRINTED DATA rather
     than a hand-written list -- so it cannot drift from the pin, and it works
     for all nine classes with no per-class table.

     Practice and the tutorial need a deck before the collection and deck
     builder exist. Deterministic (ids are sorted) so two clients given the same
     class build the same deck, which matters the moment this is used for
     anything but practice. ]]
function Controller.BasicDeck(class)
  local classCards, neutrals = {}, {}
  for id, p in pairs(ns.PrintedCards or {}) do
    if p.collectible and p.set == "CORE" and p.type ~= "HERO" then
      if p.class == class then classCards[#classCards + 1] = id
      elseif p.class == "NEUTRAL" then neutrals[#neutrals + 1] = id end
    end
  end
  table.sort(classCards)
  table.sort(neutrals)

  --[[ Two copies of each card, class cards first, until the deck is full. Two
       is the Hearthstone limit for non-legendary cards, and no Basic card is
       legendary, so this can never build an illegal deck. ]]
  local deck = {}
  local function fill(src)
    for _, id in ipairs(src) do
      for _ = 1, 2 do
        if #deck >= ns.RULES.DECK_SIZE then return end
        deck[#deck + 1] = id
      end
    end
  end
  fill(classCards)
  fill(neutrals)
  return deck
end

return Controller
