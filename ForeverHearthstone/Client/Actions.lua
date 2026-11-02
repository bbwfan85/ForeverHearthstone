--[[ Client/Actions.lua

  AN ACTION IS THE UNIT OF PLAY.

  It is the smallest thing a player can do that changes the game: play a card,
  attack, use the hero power, answer a prompt, end the turn, concede. Small
  enough to cross the wire in a dozen bytes, complete enough that replaying a
  list of them reproduces a match exactly.

  WHY THIS FILE EXISTS AT ALL

  There are four things that make a player act: the local player clicking, the
  opponent's client sending an action over the wire, the practice AI, and (one
  day) a replay. If each called the engine its own way, the rules would hold
  four times and be wrong in three of them -- which is exactly the bug docs/08
  records under "board-state play requirements were never enforced on the way
  IN": Brawl's minimum-minions check lived in the code that greyed the button
  out, so it held for a human clicking and failed for everything else.

  So: ONE function applies an action, and everything goes through it.

  NO WoW API. Pure, like Engine/, so a match can be played end to end in a test.

  ACTION SHAPES (all fields optional unless noted)

    { kind = "PLAY_CARD",  handIndex = n, position = n, mode = 1|2, targetId = n }
    { kind = "ATTACK",     attackerId = n, targetId = n }          -- both required
    { kind = "HERO_POWER", targetId = n }
    { kind = "CHOICE",     index = n }                             -- required
    { kind = "END_TURN" }
    { kind = "CONCEDE" }
    { kind = "MULLIGAN",  indices = { 1, 3 } }     -- cards to throw back

  Targets are INSTANCE IDS, never board positions -- see Game:EntityById.
]]
local ADDON, ns = ...

local Actions = {}
ns.Actions = Actions

--[[ Apply `action` as `player`. Returns ok, reason.

     A refusal is a normal outcome, not an error: an illegal target, a card that
     costs too much, acting out of turn. The caller decides what a refusal
     means -- the UI says why, the network layer treats it as a desync, the AI
     tries something else. ]]
function Actions.Apply(game, player, action)
  if not game then return false, "no game" end
  if game.over then return false, "game over" end
  local kind = action and action.kind
  if not kind then return false, "no action" end
  -- Leaving is legal even while choosing opening cards or resolving a choice.
  if kind=="CONCEDE" then return game:Concede(player) end

  --[[ Nothing may happen while the engine is waiting on a mid-resolution choice
       except answering it. Enforced here rather than per-branch, because the
       reason is about the ACTION STREAM and not about any one action: letting a
       play in between would act on information the other client has not been
       told about yet, which across the wire is a desync. ]]
  if game:AwaitingChoice() and kind ~= "CHOICE" then
    return false, "a choice is pending"
  end

  --[[ THE MULLIGAN IS A PHASE, not a turn. Both players act at once and neither
       is the active player, so every other action is refused until both have
       submitted -- including by the player who has already finished, who would
       otherwise be able to start playing into an opponent still choosing. ]]
  if game:AwaitingMulligan() and kind ~= "MULLIGAN" then
    return false, "the mulligan is not finished"
  end
  if kind == "MULLIGAN" then
    return game:SubmitMulligan(player, action.indices or {})
  end

  if kind == "PLAY_CARD" then
    if game.activePlayer ~= player then return false, "not your turn" end
    local target = nil
    if action.targetId then
      target = game:EntityById(action.targetId)
      if not target then return false, "unknown target" end
    end
    return game:PlayCard(player, action.handIndex, target, action.position, action.mode)

  elseif kind == "ATTACK" then
    if game.activePlayer ~= player then return false, "not your turn" end
    local attacker = game:EntityById(action.attackerId)
    local target   = game:EntityById(action.targetId)
    if not (attacker and target) then return false, "unknown combatant" end
    --[[ Ownership is checked HERE and not only in IsLegalAttack, because
         IsLegalAttack answers "can this attacker hit that defender", not "is
         this attacker yours to swing". Over the wire those are different
         questions and only one of them is about the rules of combat. ]]
    if attacker.controller ~= player then return false, "not your minion" end
    if not game:IsLegalAttack(attacker, target) then return false, "illegal attack" end
    game:Attack(attacker, target)
    return true

  elseif kind == "HERO_POWER" then
    if game.activePlayer ~= player then return false, "not your turn" end
    local target = action.targetId and game:EntityById(action.targetId) or nil
    if action.targetId and not target then return false, "unknown target" end
    return game:UseHeroPower(player, target)

  elseif kind == "CHOICE" then
    return game:ResolveChoice(player, action.index)

  elseif kind == "END_TURN" then
    if game.activePlayer ~= player then return false, "not your turn" end
    game:EndTurn()
    return true

  elseif kind == "CONCEDE" then
    return game:Concede(player)
  end

  return false, "unknown action " .. tostring(kind)
end

--[[ Apply and then settle the event bus, which is what every caller actually
     wants: an action whose triggers have not run is a half-finished action, and
     forgetting the Drain is a bug that shows up two turns later. ]]
function Actions.Run(game, player, action)
  local ok, why = Actions.Apply(game, player, action)
  if ok then game.bus:Drain() end
  return ok, why
end

return Actions
