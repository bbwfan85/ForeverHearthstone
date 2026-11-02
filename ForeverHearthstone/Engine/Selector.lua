--[[ Engine/Selector.lua

  Declarative target selection. Every effect that touches entities describes
  WHICH entities as a data table, never as a loop. This is what keeps 369
  scripted cards from becoming 369 hand-written loops.

  A selector is a plain table:
    { zone="PLAY", side="ENEMY", type="MINION", race="BEAST", random=1 }

  Fields (all optional, ANDed together):
    zone        ZONE.* or list of zones               default PLAY
    side        "FRIENDLY" | "ENEMY" | "ANY"          default ANY
    type        CARDTYPE.* or list
    race        race string or list
    keyword     require this keyword
    notKeyword  exclude this keyword
    notRace     exclude this race        (Fel Cannon: a NON-Mech minion)
    cardId      require this exact card  (Feugen asking whether Stalagg died)
    hasDeathrattle  true -> carries a deathrattle, printed OR granted
    hasBattlecry    true -> printed BATTLECRY
    minAtk / maxAtk / minCost / maxCost
    damaged     true | false
    exclude     "SELF" | instanceId | list of ids
    adjacent    "SELF"  -> board neighbours of the source
    self        true    -> the source entity itself
    target      true    -> the player-chosen target of the current play
    random      N       -> pick N at random from the matches (uses game RNG)
    first       N       -> first N in board order
    hero        true    -> include heroes (excluded by default in PLAY)

  RNG NOTE: `random` draws from game.rng, which is the seeded, commit-reveal
  shared stream. Both clients therefore select the same "random" entities from
  the same ordered candidate list. The candidate list MUST be built in a
  deterministic order (board index, then instanceId) or lockstep desyncs.
]]
local ADDON, ns = ...

local Selector = {}
ns.Selector = Selector

local function asSet(v)
  if v == nil then return nil end
  if type(v) == "table" then
    local s = {}
    for _, x in ipairs(v) do s[x] = true end
    return s
  end
  return { [v] = true }
end

-- Deterministic ordering of all candidate entities. Never iterate a hash table
-- directly and feed the result to RNG -- Lua's pairs() order is unspecified.
local function orderedCandidates(game, zones, sides, ctx)
  local out = {}
  for pi = 1, 2 do
    local side = (pi == ctx.controller) and "FRIENDLY" or "ENEMY"
    if sides == nil or sides[side] or sides["ANY"] then
      local p = game.players[pi]
      if zones[ns.ZONE.PLAY] then
        for i = 1, #p.board do out[#out+1] = p.board[i] end
        -- heroes are appended after minions, still deterministic
      end
      if zones[ns.ZONE.HAND] then
        for i = 1, #p.hand do out[#out+1] = p.hand[i] end
      end
      if zones[ns.ZONE.DECK] then
        for i = 1, #p.deck do out[#out+1] = p.deck[i] end
      end
      if zones[ns.ZONE.GRAVEYARD] then
        for i = 1, #p.graveyard do out[#out+1] = p.graveyard[i] end
      end
      if zones[ns.ZONE.SECRET] then
        for i = 1, #p.secrets do out[#out+1] = p.secrets[i] end
      end
      if zones[ns.ZONE.HERO] then out[#out+1] = p.hero end
      -- The equipped weapon lives in its own zone, not on the board. Without this
      -- no selector could ever reach it, which made every weapon-buff card
      -- inexpressible.
      if zones[ns.ZONE.WEAPON] and p.weapon then out[#out+1] = p.weapon end
    end
  end
  return out
end

--- Resolve a selector to a list of entities.
-- @param game  game state
-- @param sel   selector table
-- @param ctx   { source=entity, controller=playerIndex, target=entity }
function Selector.Resolve(game, sel, ctx)
  sel = sel or {}

  -- shorthand selectors that bypass the general path
  if sel.self   then return { ctx.source } end
  if sel.target then return ctx.target and { ctx.target } or {} end

  -- the entity that caused the event currently being handled (secrets,
  -- triggered minions). Used by Mirror Entity, Knife Juggler et al.
  --[[ The entity an EARLIER OP in this same list just created. Noble Sacrifice
       summons a Defender and redirects the attack onto it; Redemption
       resurrects a minion and then sets its health to 1; Holy Wrath draws a card
       and deals its cost. Nothing else in the grammar can name "the thing I
       just made" -- `#N` counts from the front of the board, not from here. ]]
  if sel.lastSummoned then
    local e = ctx.lastSummoned
    return e and { e } or {}
  end
  if sel.lastDrawn then
    local e = ctx.lastDrawn
    return e and { e } or {}
  end

  if sel.payloadEntity then
    local e = ctx.payload and (ctx.payload.entity or ctx.payload.card)
    return e and { e } or {}
  end

  -- Attack events carry attacker/defender rather than entity, so they need
  -- their own accessors. Freezing Trap bounces the ATTACKER.
  if sel.payloadAttacker then
    local e = ctx.payload and ctx.payload.attacker
    return e and { e } or {}
  end
  if sel.payloadDefender then
    local e = ctx.payload and ctx.payload.defender
    return e and { e } or {}
  end

  --[[ Neighbours of the chosen TARGET rather than of the source. Cone of Cold,
       Explosive Shot, Betrayal and Foe Reaper 4000 all hit around the thing the
       player picked, which `adjacent="SELF"` cannot express. ]]
  if sel.adjacent == "TARGET" then
    local t = ctx.target
    if not t or not t.boardIndex then return {} end
    local board = game.players[t.controller].board
    local out = {}
    local i = t.boardIndex
    if board[i-1] then out[#out+1] = board[i-1] end
    if board[i+1] then out[#out+1] = board[i+1] end
    return out
  end

  --[[ Neighbours of the ATTACK's defender. Foe Reaper 4000 splashes either side
       of whomever he attacks, and `adjacent="TARGET"` cannot serve it: attack
       payloads carry `defender`, not `target`. ]]
  if sel.adjacent == "DEFENDER" then
    local d = ctx.payload and ctx.payload.defender
    if not d or not d.boardIndex then return {} end
    local board = game.players[d.controller].board
    local out = {}
    local i = d.boardIndex
    if board[i-1] then out[#out+1] = board[i-1] end
    if board[i+1] then out[#out+1] = board[i+1] end
    return out
  end

  if sel.adjacent == "SELF" then
    local src = ctx.source
    local board = game.players[src.controller].board
    local out = {}
    local i = src.boardIndex
    if i then
      if board[i-1] then out[#out+1] = board[i-1] end
      if board[i+1] then out[#out+1] = board[i+1] end
    end
    return out
  end

  local zones = asSet(sel.zone or ns.ZONE.PLAY)
  if sel.hero then zones[ns.ZONE.HERO] = true end
  -- Asking for type=WEAPON implies the weapon zone, so `friendly.weapon` works
  -- without the author having to know weapons are not in the PLAY zone.
  if sel.type == ns.CARDTYPE.WEAPON
     or (type(sel.type) == "table" and (function()
           for _, t in ipairs(sel.type) do
             if t == ns.CARDTYPE.WEAPON then return true end
           end
         end)()) then
    zones[ns.ZONE.WEAPON] = true
  end
  local sides = asSet(sel.side)
  local types = asSet(sel.type)
  local races = asSet(sel.race)

  local excl = {}
  if sel.excludeTarget and ctx.target then
    excl[ctx.target.instanceId] = true
  end
  --[[ Misdirection sends the attack at "another random character", so the one
       it was already aimed at must be excluded. Attack payloads carry
       `defender`, which !target cannot reach. ]]
  if sel.excludeDefender and ctx.payload and ctx.payload.defender then
    excl[ctx.payload.defender.instanceId] = true
  end
  if sel.excludeAttacker and ctx.payload and ctx.payload.attacker then
    excl[ctx.payload.attacker.instanceId] = true
  end
  if sel.exclude == "SELF" then
    excl[ctx.source and ctx.source.instanceId or -1] = true
  elseif sel.exclude then
    for _, x in ipairs(type(sel.exclude)=="table" and sel.exclude or {sel.exclude}) do
      excl[type(x)=="table" and x.instanceId or x] = true
    end
  end

  local cands = orderedCandidates(game, zones, sides, ctx)
  local out = {}
  for _, e in ipairs(cands) do
    repeat
      if excl[e.instanceId] then break end
      if types and not types[e.printed.type] then break end
      -- heroes are only included when explicitly asked for
      if e.printed.type == ns.CARDTYPE.HERO and not sel.hero and not (types and types[ns.CARDTYPE.HERO]) then break end
      if races and not races[e.printed.race or ""] then break end
      if sel.keyword    and not e:Has(sel.keyword) then break end
      if sel.notKeyword and e:Has(sel.notKeyword)  then break end
      if sel.notRace    and (e.printed.race or "") == sel.notRace then break end
      if sel.cardId     and e.cardId ~= sel.cardId then break end
      if sel.notCardId  and e.cardId == sel.notCardId then break end
      --[[ "a Secret" as a CARD PROPERTY, which is not the same as the secret
           ZONE. Mad Scientist wants a Secret sitting in the DECK, so it needs
           to ask what the card is rather than where it is. ]]
      if sel.isSecret and not game:IsSecret(e.printed) then break end
      --[[ Deathrattle is asked of the LIVE entity, so a granted one counts --
           Scarlet Purifier hits a minion that was given a deathrattle by
           Ancestral Spirit. A card sitting in hand or deck has no scripts
           attached yet, so fall back to the printed tag there. ]]
      if sel.hasDeathrattle then
        local has = (e.deathrattles and #e.deathrattles > 0)
        if not has then
          for _, t in ipairs(e.printed.scriptTags or {}) do
            if t == "DEATHRATTLE" then has = true break end
          end
        end
        if not has then break end
      end
      --[[ Battlecry is a property of the PRINTED card, never granted, and
           Nerub'ar Weblord taxes them in hand where nothing is attached. ]]
      if sel.hasBattlecry then
        local has = false
        for _, t in ipairs(e.printed.scriptTags or {}) do
          if t == "BATTLECRY" then has = true break end
        end
        if not has then break end
      end
      if sel.minAtk  and e:Attack() < sel.minAtk  then break end
      if sel.maxAtk  and e:Attack() > sel.maxAtk  then break end
      if sel.minCost and e:Cost()   < sel.minCost then break end
      if sel.maxCost and e:Cost()   > sel.maxCost then break end
      if sel.damaged == true  and not e:IsDamaged() then break end
      if sel.damaged == false and e:IsDamaged()     then break end
      out[#out+1] = e
    until true
  end

  if sel.first then
    local t = {}
    for i = 1, math.min(sel.first, #out) do t[i] = out[i] end
    return t
  end

  if sel.random then
    --[[ A random pick never lands on something already dying: a minion at 0
         Health, or one marked for destruction, is "mortally wounded" and out of
         every random pool (Knife Juggler, Mad Bomber, Avenge, Misdirection,
         Sylvanas). Only characters in play can be dying. ]]
    local t, pool = {}, {}
    for _, e in ipairs(out) do
      if not (e.zone == ns.ZONE.PLAY and e:IsDead()) then pool[#pool + 1] = e end
    end
    for _ = 1, math.min(sel.random, #pool) do
      local i = game:Random(#pool)          -- seeded shared RNG
      t[#t+1] = pool[i]
      table.remove(pool, i)
    end
    return t
  end

  return out
end

return Selector
