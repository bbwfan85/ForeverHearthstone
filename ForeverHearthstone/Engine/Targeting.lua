--[[ Engine/Targeting.lua

  TARGETING IS DERIVED FROM PRINTED DATA, NOT AUTHORED.

  Cards carry a `playRequirements` table straight from the pinned build, and
  every REQ_* below maps to one predicate. That means legality checking, the
  "no valid target" grey-out, and the targeting arrow all come out of the
  imported data with zero per-card authoring.

  Counts below are from the vanilla-only pin (5834). Adding Naxxramas and GvG
  (build 7234) introduced NO new requirement types -- verified by enumeration --
  so the vocabulary is unchanged, only the counts grew:

    REQ_TARGET_TO_PLAY                 73   must pick a target; unplayable if none
    REQ_MINION_TARGET                  65   minions only
    REQ_TARGET_IF_AVAILABLE            29   optional target
    REQ_FRIENDLY_TARGET                13
    REQ_ENEMY_TARGET                   12
    REQ_NONSELF_TARGET                 10
    REQ_NUM_MINION_SLOTS                7   needs a free board slot
    REQ_MINIMUM_ENEMY_MINIONS           5
    REQ_TARGET_WITH_RACE                4   value is a race enum
    REQ_TARGET_MAX_ATTACK               3
    REQ_DAMAGED_TARGET                  2
    REQ_TARGET_FOR_COMBO                2   target required only when Combo is active
    REQ_WEAPON_EQUIPPED                 2
    REQ_TARGET_MIN_ATTACK               2
    REQ_UNDAMAGED_TARGET                1
    REQ_MINIMUM_TOTAL_MINIONS           1
    REQ_MINION_CAP_IF_TARGET_AVAILABLE  1
    REQ_MUST_TARGET_TAUNTER             1
    REQ_HERO_TARGET                     1

  That is the entire set FOR COLLECTIBLE CARDS. The enumeration that produced it
  looked at collectible cards only, and three more requirements live exclusively
  on HERO_POWER cards:

    REQ_STEADY_SHOT                     1   a marker on Steady Shot
    REQ_MINION_OR_ENEMY_HERO            1   Steady Shot, with Steamwheedle Sniper
    REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY    1   Totemic Call, once all four Totems are out

  They were latent for as long as nothing routed hero powers through this
  module, and they are implemented below. If a future re-pin introduces another,
  CheckRequirement returns false and logs, so an unimplemented requirement fails
  closed rather than silently allowing an illegal play.

  Note REQ_TARGET_WITH_RACE carries a numeric race enum in the data. The mapping
  is asserted at load time against PrintedCards rather than hardcoded blindly.
]]
local ADDON, ns = ...

local Targeting = {}
ns.Targeting = Targeting

-- REQ_TARGET_WITH_RACE carries a numeric race enum. Only three values occur in
-- the pinned build, and each is VERIFIED by cross-referencing the card's text:
--   14 -> MURLOC   Hungry Crab (NEW1_017)     "Destroy a Murloc"
--   15 -> DEMON    Sacrificial Pact (NEW1_003)"Destroy a Demon"
--   20 -> BEAST    Houndmaster (DS1_070)      "Give a friendly Beast"
--                  Bestial Wrath (EX1_549)    "Give a Beast"
-- DRAGON / TOTEM / PIRATE have no REQ_TARGET_WITH_RACE card in this build, so
-- their enum values are deliberately NOT guessed here. If a re-pin introduces
-- one, CheckRequirement logs an unmapped enum and fails closed.
--   17 -> MECHANICAL Screwjank Clunker (GVG_055), Upgraded Repair Bot (GVG_083)
--                  "Give a friendly Mech" -- missing, so both could never target
local RACE_ENUM = { [14]="MURLOC", [15]="DEMON", [17]="MECHANICAL", [20]="BEAST" }

--[[ CHOOSE ONE

  A Choose One card's own printed data carries no requirements at all; each of
  its two modes carries its own. Keeper of the Grove is the clean example --
  Moonfire may hit a hero, Dispel may not -- so legality cannot be answered
  until a mode is chosen, and every entry point below takes an optional `mode`
  (1 or 2, indexing printed.chooseOne in DISPLAY order).

  Only the REQUIREMENTS come from the mode. Everything else still comes from
  the parent card, and that distinction is load-bearing: Keeper of the Grove is
  a MINION, so its Moonfire mode is a BATTLECRY and may target a minion with
  "Can't be targeted by Spells" -- while Wrath, a SPELL, may not. Swapping in
  the mode's printed table wholesale would make the mode a spell and quietly
  break that. ]]

--- The two mode card ids in display order, or nil for an ordinary card.
function Targeting.ModesOf(card)
  return card.printed.chooseOne
end

--- Play requirements in force: the chosen mode's, else the card's own.
function Targeting.ReqsFor(game, card, mode)
  local modes = Targeting.ModesOf(card)
  if modes and mode then
    local printed = game:Printed(modes[mode])
    if not printed then
      game:Error("unknown Choose One mode " .. tostring(mode) ..
                 " on " .. tostring(card.cardId))
      return nil
    end
    return printed.reqs
  end
  return card.printed.reqs
end

--- Is `cand` a legal target for `card` played by `player`?
function Targeting.IsLegalTarget(game, card, player, cand, mode)
  local reqs = Targeting.ReqsFor(game, card, mode)
  if not reqs then return false end          -- card takes no target at all

  -- Universal untargetability rules, which are NOT in playRequirements and
  -- must be applied on top of it:
  --   * Stealth minions cannot be targeted by the opponent
  --   * CANT_BE_TARGETED_BY_SPELLS blocks ALL spells and hero powers --
  --     yours too: you cannot Blessing of Kings your own Faerie Dragon
  if cand.controller ~= player and cand:IsStealth() then return false end
  if card.printed.type == ns.CARDTYPE.SPELL
     and cand:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_SPELLS) then return false end
  if card.printed.type == ns.CARDTYPE.HERO_POWER
     and cand:Has(ns.KEYWORD.CANT_BE_TARGETED_BY_HERO_POWERS) then return false end

  for req, value in pairs(reqs) do
    if not Targeting.CheckRequirement(game, req, value, card, player, cand) then
      return false
    end
  end
  return true
end

function Targeting.CheckRequirement(game, req, value, card, player, cand)
  local foe = game:Opponent(player)

  if req == "REQ_TARGET_TO_PLAY"     then return cand ~= nil
  elseif req == "REQ_TARGET_IF_AVAILABLE" then return true   -- optional
  elseif req == "REQ_MINION_TARGET"  then return cand and cand.printed.type == ns.CARDTYPE.MINION
  elseif req == "REQ_HERO_TARGET"    then return cand and cand.printed.type == ns.CARDTYPE.HERO
  elseif req == "REQ_FRIENDLY_TARGET"then return cand and cand.controller == player
  elseif req == "REQ_ENEMY_TARGET"   then return cand and cand.controller == foe
  elseif req == "REQ_NONSELF_TARGET" then return cand and cand.instanceId ~= card.instanceId
  elseif req == "REQ_DAMAGED_TARGET" then return cand and cand:IsDamaged()
  elseif req == "REQ_UNDAMAGED_TARGET" then return cand and not cand:IsDamaged()
  elseif req == "REQ_TARGET_MAX_ATTACK" then return cand and cand:Attack() <= value
  elseif req == "REQ_TARGET_MIN_ATTACK" then return cand and cand:Attack() >= value
  elseif req == "REQ_TARGET_WITH_RACE" then
    local race = RACE_ENUM[value]
    if not race then game:Error("unmapped race enum " .. tostring(value)); return false end
    return cand and cand.printed.race == race

  -- board-state requirements: independent of the candidate
  elseif req == "REQ_NUM_MINION_SLOTS" then
    return #game.players[player].board + value <= ns.RULES.BOARD_SLOTS
  elseif req == "REQ_MINIMUM_ENEMY_MINIONS" then
    return #game.players[foe].board >= value
  elseif req == "REQ_MINIMUM_TOTAL_MINIONS" then
    return #game.players[player].board + #game.players[foe].board >= value
  elseif req == "REQ_WEAPON_EQUIPPED" then
    return game.players[player].weapon ~= nil
  --[[ Cabal Shadow Priest: the steal needs a free slot AFTER the Priest lands.
       With six minions out there is none, so nothing may be targeted -- it
       used to be allowed, and the steal then destroyed the minion instead. ]]
  elseif req == "REQ_MINION_CAP_IF_TARGET_AVAILABLE" then
    if not cand then return true end
    local board = game.players[player].board
    local onBoard = card.zone == ns.ZONE.PLAY and 0 or 1
    return #board + onBoard < ns.RULES.BOARD_SLOTS

  -- Combo-conditional targeting (Rogue). The target is required only when the
  -- combo is live; otherwise the card plays untargeted.
  elseif req == "REQ_TARGET_FOR_COMBO" then
    if game.players[player].cardsPlayedThisTurn > 0 then return cand ~= nil end
    return true

  -- Taunt redirection for attacks, not card play.
  elseif req == "REQ_MUST_TARGET_TAUNTER" then
    return cand and cand:IsTaunt()

  --[[ HERO POWER requirements. These three appear ONLY on HERO_POWER cards, so
       the module docstring's "Naxxramas and GvG introduced NO new requirement
       types -- verified by enumeration" was enumerating COLLECTIBLE cards only.
       They were reaching the fail-closed branch below. ]]

  -- A marker on Steady Shot, not a constraint. Its companion requirement,
  -- REQ_MINION_OR_ENEMY_HERO, is the one that decides what may be hit.
  elseif req == "REQ_STEADY_SHOT" then
    return true

  --[[ Steady Shot. By default it takes no target at all and hits the enemy
       hero; Steamwheedle Sniper is what makes minions targetable, so a minion
       is legal only while something grants that. ]]
  elseif req == "REQ_MINION_OR_ENEMY_HERO" then
    if not cand then return true end        -- optional: untargeted is fine
    if cand.printed.type == ns.CARDTYPE.HERO then return cand.controller == foe end
    if cand.printed.type ~= ns.CARDTYPE.MINION then return false end
    return game:HeroPowerTargetsMinions(player)

  --[[ Totemic Call: unusable once all four Totems are out. The entourage is
       printed data, so this needs no per-card knowledge. ]]
  elseif req == "REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY" then
    local ent = card.printed.entourage
    if not ent then return true end
    local onBoard = {}
    for _, e in ipairs(game.players[player].board) do onBoard[e.cardId] = true end
    for _, id in ipairs(ent) do
      if not onBoard[id] then return true end
    end
    return false
  end

  game:Error("unimplemented play requirement: " .. tostring(req))
  return false      -- fail closed
end

--- Does this card need the player to choose a target before it can be played?
function Targeting.NeedsTarget(game, card, player, mode)
  local reqs = Targeting.ReqsFor(game, card, mode)
  if not reqs then return false end
  if reqs.REQ_TARGET_TO_PLAY then return true end
  --[[ A combo target is needed only when there is one to take. Kidnapper with
       no minion anywhere is still playable; its combo simply fizzles. ]]
  if reqs.REQ_TARGET_FOR_COMBO and game.players[player].cardsPlayedThisTurn > 0
     and #Targeting.LegalTargets(game, card, player, mode) > 0 then
    return true
  end
  --[[ "If available" means: whenever there IS something to aim at, you must
       aim. Hearthstone never lets you skip it -- a Spellbreaker silences
       something, an Ancient Brewmaster bounces your minion, a Crazed Alchemist
       swaps one -- so a drawback battlecry cannot be dodged by playing it blank. ]]
  if reqs.REQ_TARGET_IF_AVAILABLE ~= nil
     and #Targeting.LegalTargets(game, card, player, mode) > 0 then
    return true
  end
  return false
end

--[[ Does playing this card take a target at all? "required" for a spell like
     Fireball; "optional" for a battlecry like Ironforge Rifleman's, which must
     be aimed if anything can be aimed at but lets the minion be played when
     nothing can. nil for a card that never takes one.

     NeedsTarget answers only the first, because the rules only ever REFUSE the
     first. Asking NeedsTarget alone is how the player's own Rifleman came to be
     played with no prompt and its battlecry thrown away -- so the controller and
     the AI both ask this, and agree on what a target-taking card is. ]]
function Targeting.WantsTarget(game, card, player, mode)
  if Targeting.NeedsTarget(game, card, player, mode) then return "required" end
  local reqs = Targeting.ReqsFor(game, card, mode)
  if reqs and reqs.REQ_TARGET_IF_AVAILABLE ~= nil then return "optional" end
  return nil
end

--- All legal targets, in deterministic order. Used for the UI highlight set and
--- by the AI. Empty + NeedsTarget means the card is unplayable.
function Targeting.LegalTargets(game, card, player, mode)
  local out = {}
  for _, pi in ipairs({ player, game:Opponent(player) }) do
    local p = game.players[pi]
    for _, e in ipairs(p.board) do
      if Targeting.IsLegalTarget(game, card, player, e, mode) then out[#out+1] = e end
    end
    if Targeting.IsLegalTarget(game, card, player, p.hero, mode) then out[#out+1] = p.hero end
  end
  return out
end

--[[ Can this MODE be chosen right now? Board-state requirements and target
     availability only -- cost and board space belong to the card, not the mode,
     and are checked once by CanPlay.

     Power of the Wild is the case that matters: with a full board its Panther
     mode is unchoosable while Leader of the Pack is fine, so the prompt must
     grey one option rather than refusing the card. ]]
function Targeting.ModePlayable(game, card, player, mode)
  local reqs = Targeting.ReqsFor(game, card, mode) or {}
  --[[ Requirements about the BOARD rather than about a candidate, so they are
       asked with no candidate at all. REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY belongs
       here too: it is Totemic Call refusing once all four Totems are out, and
       leaving it off this list meant it was never consulted. ]]
  for req, value in pairs(reqs) do
    if req == "REQ_NUM_MINION_SLOTS" or req == "REQ_MINIMUM_ENEMY_MINIONS"
       or req == "REQ_MINIMUM_TOTAL_MINIONS" or req == "REQ_WEAPON_EQUIPPED"
       or req == "REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY" then
      if not Targeting.CheckRequirement(game, req, value, card, player, nil) then
        return false, req
      end
    end
  end
  if Targeting.NeedsTarget(game, card, player, mode)
     and #Targeting.LegalTargets(game, card, player, mode) == 0 then
    return false, "no legal target"
  end
  --[[ A secret cannot be played into a full secret zone, or beside a copy of
       itself. PlaySecret refused both, but only after the card had left the
       hand and its mana was spent -- so the card simply vanished. ]]
  if game.IsSecret and game:IsSecret(card.printed) then
    local secrets = game.players[player].secrets or {}
    if #secrets >= ns.RULES.SECRET_SLOTS then return false, "secret zone full" end
    for _, s in ipairs(secrets) do
      if s.cardId == card.cardId then return false, "that secret is already in play" end
    end
  end
  return true
end

--[[ The prompt's contents: one entry per mode, in display order, each carrying
     the printed name and text so the choice renders from data alone -- the same
     guaranteed floor the asset resolver gives every other card.

     Returns nil for a card that is not Choose One, which is how the client asks
     "does playing this need a prompt first?". ]]
function Targeting.ModeOptions(game, card, player)
  local modes = Targeting.ModesOf(card)
  if not modes then return nil end
  local out = {}
  for i = 1, #modes do
    local printed = game:Printed(modes[i])
    local ok, why = Targeting.ModePlayable(game, card, player, i)
    out[i] = {
      mode     = i,
      cardId   = modes[i],
      name     = printed and printed.name or modes[i],
      text     = printed and printed.text or "",
      playable = ok,
      reason   = (not ok) and why or nil,
    }
  end
  return out
end

--- Can this card be played at all right now (cost, slots, target availability)?
--- For a Choose One card, `mode` may be given to ask about one specific mode;
--- with no mode the card is playable when EITHER mode is.
function Targeting.CanPlay(game, card, player, mode)
  local p = game.players[player]
  -- Game:CardCost, not card:Cost() -- cost modifiers (Preparation, Loatheb) must
  -- be visible to the playability check or the UI greys out legal plays.
  if game:CardCost(card, player) > game:AvailableMana(player) then
    return false, "not enough mana"
  end
  if card.printed.type == ns.CARDTYPE.MINION
     and #p.board >= ns.RULES.BOARD_SLOTS then return false, "board full" end

  local modes = Targeting.ModesOf(card)
  if modes and not mode then
    for i = 1, #modes do
      if Targeting.ModePlayable(game, card, player, i) then return true end
    end
    return false, "no playable mode"
  end

  local ok, why = Targeting.ModePlayable(game, card, player, mode)
  if not ok then return false, why end
  return true
end

return Targeting
