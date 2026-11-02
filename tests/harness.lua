--[[ tests/harness.lua

  HEADLESS TEST HARNESS.

  The engine imports no WoW API, so it loads and runs under plain Lua 5.1 with
  nothing stubbed. That is the whole reason for the "no WoW API in Engine/" rule:
  you can test a two-player card game solo, in a terminal, in milliseconds,
  without launching the client.

  Run from the project root:
      lua tests/run.lua
      lua tests/run.lua aura          (only suites whose name matches)

  Load order matters -- each engine file captures its dependencies into locals
  at load time (e.g. Ops.lua does `local Selector = ns.Selector`), so a file
  must not load before what it captures.
]]

local H = {}

-- ------------------------------------------------------------- module loading

local LOAD_ORDER = {
  "ForeverHearthstone/Engine/Enums.lua",
  "ForeverHearthstone/Engine/Entity.lua",
  "ForeverHearthstone/Engine/Selector.lua",
  "ForeverHearthstone/Engine/CardPool.lua",
  "ForeverHearthstone/Engine/Conditions.lua",
  "ForeverHearthstone/Engine/Ops.lua",
  "ForeverHearthstone/Engine/Aura.lua",
  "ForeverHearthstone/Engine/Bus.lua",
  "ForeverHearthstone/Engine/Targeting.lua",
  "ForeverHearthstone/Engine/Game.lua",
  "ForeverHearthstone/Data/PrintedCards.lua",
  "ForeverHearthstone/Data/Effects/Generated.lua",
  "ForeverHearthstone/Data/Effects/Handwritten.lua",
  -- Client layer. Assets/ and FX/ are deliberately WoW-API-free so they load and
  -- run headless exactly like Engine/. Client/UI/ (frames) is NOT loaded here.
  "ForeverHearthstone/Client/Assets/HearthstoneArt.lua",
  "ForeverHearthstone/Client/Assets/ArtCrop.lua",
  "ForeverHearthstone/Client/Assets/CardText.lua",
  "ForeverHearthstone/Client/Assets/DeckTiles.lua",
  "ForeverHearthstone/Client/Assets/CardSounds.lua",
  "ForeverHearthstone/Client/Assets/CardPlaySounds.lua",
  "ForeverHearthstone/Client/Assets/HeroVoice.lua",
  "ForeverHearthstone/Client/Assets/GenericArt.lua",
  "ForeverHearthstone/Client/Assets/Resolver.lua",
  "ForeverHearthstone/Client/FX/Timeline.lua",
  "ForeverHearthstone/Client/FX/Choreography.lua",
  "ForeverHearthstone/Client/FX/SpellFX.lua",
  "ForeverHearthstone/Client/FX/Director.lua",
  "ForeverHearthstone/Client/FX/Sounds.lua",
  "ForeverHearthstone/Client/UI/Layout.lua",
  "ForeverHearthstone/Client/UI/CollectionLayout.lua",
  "ForeverHearthstone/Client/Actions.lua",
  "ForeverHearthstone/Client/Collection.lua",
  "ForeverHearthstone/Client/Packs.lua",
  "ForeverHearthstone/Client/Drops.lua",
  "ForeverHearthstone/Client/Controller.lua",
  "ForeverHearthstone/Client/Net/Protocol.lua",
  "ForeverHearthstone/Client/Net/Session.lua",
  "ForeverHearthstone/Client/Vault.lua",
  "ForeverHearthstone/Client/BotDecks.lua",
  "ForeverHearthstone/Client/AI.lua",
  "ForeverHearthstone/Client/Net/DevTest.lua",
}

--[[ Exposed so tests/test_packaging.lua can compare this list against the .toc.
     WoW reads only the .toc; these tests read only this list. If they drift, the
     whole suite can be green while the addon fails to load in game. ]]
H.LOAD_ORDER = LOAD_ORDER

function H.LoadEngine()
  local ns = {}
  for _, path in ipairs(LOAD_ORDER) do
    local chunk, err = loadfile(path)
    if not chunk then
      error(("failed to load %s\n  %s"):format(path, tostring(err)), 0)
    end
    -- mimic WoW's addon vararg: (addonName, privateNamespace)
    local ok, ferr = pcall(chunk, "ForeverHearthstone", ns)
    if not ok then
      error(("error executing %s\n  %s"):format(path, tostring(ferr)), 0)
    end
  end
  H.ns = ns
  return ns
end

-- ------------------------------------------------------------------ assertions

local failures, checks = {}, 0
H.currentTest = "?"

local function fail(msg, lvl)
  local where = debug.getinfo((lvl or 3), "Sl")
  local loc = where and (where.short_src .. ":" .. where.currentline) or "?"
  failures[#failures + 1] = ("  [%s] %s\n      at %s"):format(H.currentTest, msg, loc)
end

local function fmt(v)
  if type(v) == "table" then
    -- entities print as something identifiable; a bare "{}" tells you nothing
    -- when two different minions fail an equality check.
    if v.instanceId and v.cardId then
      return ("<%s#%d>"):format(v.cardId, v.instanceId)
    end
    local parts = {}
    for i, x in ipairs(v) do parts[i] = fmt(x) end
    return "{" .. table.concat(parts, ", ") .. "}"
  end
  return tostring(v)
end

function H.eq(actual, expected, what)
  checks = checks + 1
  if actual ~= expected then
    fail(("%s: expected %s, got %s"):format(what or "value", fmt(expected), fmt(actual)))
    return false
  end
  return true
end

function H.ok(cond, what)
  checks = checks + 1
  if not cond then fail(("%s: expected truthy"):format(what or "condition")); return false end
  return true
end

function H.notOk(cond, what)
  checks = checks + 1
  if cond then fail(("%s: expected falsy, got %s"):format(what or "condition", fmt(cond))); return false end
  return true
end

--- Compare a board to a list of "CARDID a/h" strings, in order.
function H.board(game, player, expected, what)
  checks = checks + 1
  local got = {}
  for i, e in ipairs(game.players[player].board) do
    got[i] = ("%s %d/%d"):format(e.cardId, game:AttackValue(e), e:Health())
  end
  local same = #got == #expected
  if same then
    for i = 1, #got do if got[i] ~= expected[i] then same = false break end end
  end
  if not same then
    fail(("%s board p%d:\n      expected %s\n      got      %s")
         :format(what or "", player, fmt(expected), fmt(got)))
    return false
  end
  return true
end

--- Assert the engine logged no internal errors. Catches unknown ops, unknown
--- card ids, unimplemented play requirements -- things that would otherwise
--- fail silently and produce a subtly wrong board.
function H.noEngineErrors(game, what)
  checks = checks + 1
  if #game.errors > 0 then
    fail(("%s: engine logged %d error(s): %s")
         :format(what or "engine", #game.errors, table.concat(game.errors, " | ")))
    return false
  end
  return true
end

-- ----------------------------------------------------------------- test runner

local suites = {}

function H.suite(name, fn) suites[#suites + 1] = { name = name, fn = fn } end

function H.run(filter)
  local ns = H.ns or H.LoadEngine()
  local ran, skipped = 0, 0
  print("")
  for _, s in ipairs(suites) do
    if filter and not s.name:lower():find(filter:lower(), 1, true) then
      skipped = skipped + 1
    else
      local before = #failures
      H.currentTest = s.name
      local ok, err = pcall(s.fn, ns, H)
      if not ok then
        failures[#failures + 1] = ("  [%s] CRASHED\n      %s"):format(s.name, tostring(err))
      end
      ran = ran + 1
      local mark = (#failures == before) and "ok  " or "FAIL"
      print(("  %s  %s"):format(mark, s.name))
    end
  end

  print("")
  print(("  %d suites, %d assertions, %d failure(s)%s")
        :format(ran, checks, #failures, skipped > 0 and (", " .. skipped .. " skipped") or ""))
  if #failures > 0 then
    print("")
    for _, f in ipairs(failures) do print(f) end
    print("")
    return 1
  end
  print("  ALL PASS")
  print("")
  return 0
end

-- -------------------------------------------------------------------- fixtures

--[[ Build a game in a known state. Decks default to filler so draws are
     predictable and never accidentally trigger anything: Wisp (CS2_231) is a
     0-cost 1/1 with no text and no mechanics -- the most inert card in the set.
]]
local FILLER = "CS2_231"   -- Wisp, 0 mana 1/1, no text, no mechanics (verified)

function H.NewGame(opts)
  opts = opts or {}
  local ns = H.ns
  local function deck(ids, n)
    local d = {}
    for _, id in ipairs(ids or {}) do d[#d + 1] = id end
    for _ = #d + 1, (n or 30) do d[#d + 1] = FILLER end
    return d
  end
  local g = ns.Game.New({
    seed = opts.seed or 12345,
    firstPlayer = opts.firstPlayer or 1,
    players = {
      { class = opts.class1 or "MAGE",  deck = deck(opts.deck1, opts.deckSize) },
      { class = opts.class2 or "PRIEST", deck = deck(opts.deck2, opts.deckSize) },
    },
  })
  if not opts.noStart then g:StartGame() end
  return g
end

--[[ Place a minion directly on the board, bypassing hand, mana and battlecry.
     Test setup should not have to play out a whole game to reach a board state.
     This DOES stamp play order and attach the card's script, so triggers,
     deathrattles and auras behave exactly as if it had been played.
     Minions placed this way are attack-ready by default, since most tests are
     not about summoning sickness. Pass `sick=true` to simulate a minion that
     just arrived this turn. ]]
function H.Put(game, player, cardId, opts)
  opts = opts or {}
  local ns = H.ns
  local p = game.players[player]
  local pr = game:Printed(cardId)
  if not pr then error("H.Put: unknown card id " .. tostring(cardId), 2) end
  local e = ns.Entity.New(pr, player, game.ids)
  e.zone = ns.ZONE.PLAY
  e.summonedTurn = opts.sick and game.turn or -1
  game:AttachScript(e)
  game.bus:StampPlayOrder(e)
  local idx = opts.index or (#p.board + 1)
  table.insert(p.board, idx, e)
  game:Reindex(player)
  game:RecalcAuras()
  return e
end

--[[ Stack a card on TOP of a player's deck. Game:Draw pops from the END of the
     array, so "top of deck" is the last element. Needed for on-draw effects,
     where a shuffled deck makes the test non-deterministic. ]]
function H.PutOnDeck(game, player, cardId)
  local ns = H.ns
  local pr = game:Printed(cardId)
  if not pr then error("H.PutOnDeck: unknown card id " .. tostring(cardId), 2) end
  local e = ns.Entity.New(pr, player, game.ids)
  e.zone = ns.ZONE.DECK
  local deck = game.players[player].deck
  deck[#deck + 1] = e
  return e
end

--- Put a card into hand and return its hand index.
function H.Hand(game, player, cardId)
  local e = game:AddToHand(player, cardId)
  if not e then error("H.Hand: could not add " .. tostring(cardId), 2) end
  for i, c in ipairs(game.players[player].hand) do
    if c == e then return i, e end
  end
end

--- Give a player enough mana to do anything, for tests that aren't about mana.
function H.Mana(game, player, n)
  local p = game.players[player]
  p.maxMana = n or 10
  p.mana = n or 10
  p.lockedMana = 0
  return p
end

--- Hand back control to `player` without playing out turns.
function H.SetActive(game, player)
  game.activePlayer = player
  local p = game.players[player]
  p.cardsPlayedThisTurn = 0
  p.heroPowerUsedThisTurn = false
  for _, e in ipairs(p.board) do e.attacksThisTurn = 0 end
  p.hero.attacksThisTurn = 0
end

function H.Hero(game, player) return game.players[player].hero end

return H
