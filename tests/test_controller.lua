--[[ tests/test_controller.lua -- the glue between board intents and the engine.

  Client/Controller.lua is the layer a player actually touches: it decides what
  a click MEANS. It imports no WoW API, so the whole interaction model is
  testable here rather than only in the client.

  The thing most worth pinning down is the ORDER of decisions. Playing a card
  can need a mode and a target, and the mode must come first, because the mode
  decides what may be targeted -- Keeper of the Grove's Moonfire may hit a hero
  and its Dispel may not. Just as important: nothing is committed until the last
  decision is taken, so a cancel anywhere leaves the hand untouched.

  Fixtures, verified against the pin:
    CS2_182  Chillwind Yeti      4 mana 4/5 vanilla, no target
    CS2_231  Wisp                0 mana 1/1 vanilla
    CS2_024  Frostbolt           2 mana, REQ_TARGET_TO_PLAY
    EX1_166  Keeper of the Grove 4 mana 2/4 Choose One, both modes target
    EX1_160  Power of the Wild   2 mana Choose One, neither mode targets
    CS2_200  Boulderfist Ogre    6 mana 6/7
]]
local H = require("tests.harness")

H.suite("controller: waiting for the other mulligan cannot reveal replacement cards", function(ns, H)
  local g = H.NewGame()
  -- The presentation must retain the dealt cards even if the engine hand changes.
  g.phase = "MULLIGAN"
  g.mulliganChoice = {}
  H.Hand(g, 1, "CS2_182")
  local c = ns.Controller.New({game=g, player=1})
  local original = c:Snapshot().mulligan.hand[1]
  g.players[1].hand[1].cardId = "CS2_231"
  g.mulliganChoice[1] = {}
  local s = c:Snapshot()
  H.ok(s.mulligan.waiting)
  H.eq(s.mulligan.hand[1], original, "replacement remains hidden until opening ends")
end)

local function newController(ns, H, opts)
  opts = opts or {}
  local g = H.NewGame({ class1 = opts.class1 or "DRUID", class2 = "MAGE" })
  H.Mana(g, 1, 10)
  g.activePlayer = 1
  local snaps = {}
  local c = ns.Controller.New({
    game = g, player = 1,
    onChange = function(s) snaps[#snaps + 1] = s end,
  })
  return g, c, snaps
end

--============================================================ snapshot

H.suite("controller: the snapshot is ids and counts, never live entities", function(ns, H)
  --[[ The UI must not be able to reach into engine state, and this is also the
       shape that will cross the wire for the spectator view. ]]
  local g, c = newController(ns, H)
  H.Put(g, 1, "CS2_182")
  H.Put(g, 2, "CS2_200")
  H.Hand(g, 1, "CS2_024")
  local s = c:Snapshot()

  H.eq(s.board[1], "CS2_182", "own board is a card id")
  H.eq(s.foeBoard[1], "CS2_200", "so is the enemy board")
  H.eq(type(s.hand[1]), "string", "and the hand")
  H.eq(s.foeHandCount, #g.players[2].hand, "the enemy hand is a COUNT only")
  H.ok(s.myTurn, "it says whose turn it is")
  H.notOk(s.chooseOne, "and there is no prompt pending")
end)

--============================================================ playing a card

H.suite("controller: a card that needs nothing is played on the first click", function(ns, H)
  local g, c, snaps = newController(ns, H)
  local i = H.Hand(g, 1, "CS2_182")
  H.ok(c:HandleIntent({ kind = "PLAY_CARD", handIndex = i }), "played")
  H.eq(#g.players[1].board, 1, "the minion is on the board")
  H.ok(#snaps > 0, "and the board was told to redraw")
end)

H.suite("controller: a targeted card waits for a target, then commits", function(ns, H)
  local g, c = newController(ns, H, { class1 = "MAGE" })
  local ogre = H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "CS2_024")           -- Frostbolt
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana

  local ok, why = c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(ok, "the play was accepted")
  H.eq(why, "awaiting target", "but is waiting for a target")
  H.eq(#g.players[1].hand, handBefore, "NOTHING is committed yet")
  H.eq(g.players[1].mana, manaBefore, "no mana spent")
  H.ok(c:Snapshot().targeting, "and the snapshot asks for targeting")

  H.ok(c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 }), "target clicked")
  g.bus:Drain()
  H.eq(ogre:Health(), 7 - 3, "the Frostbolt resolved on it")
  H.eq(#g.players[1].hand, handBefore - 1, "and the card left hand")
  H.notOk(c:Snapshot().targeting, "targeting is over")
  H.noEngineErrors(g)
end)

H.suite("controller: an illegal target is refused and keeps waiting", function(ns, H)
  local g, c = newController(ns, H, { class1 = "DRUID" })
  H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "EX1_166")           -- Keeper; mode 2 Dispel is minions-only
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i, mode = 2 })
  H.ok(c:Snapshot().targeting, "awaiting a target for Dispel")

  local ok, why = c:HandleIntent({ kind = "CLICK_FOE_HERO" })
  H.notOk(ok, "a hero is refused for Dispel")
  H.eq(why, "illegal target", "and says why")
  H.ok(c:Snapshot().targeting, "and it is still waiting, not cancelled")
  H.eq(#g.players[1].board, 0, "nothing was committed")
  H.noEngineErrors(g)
end)

H.suite("controller: cancelling at any point leaves the hand untouched", function(ns, H)
  local g, c = newController(ns, H, { class1 = "MAGE" })
  H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "CS2_024")
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(c:Snapshot().targeting, "waiting for a target")

  H.ok(c:HandleIntent({ kind = "CANCEL" }), "cancelled")
  H.notOk(c:Snapshot().targeting, "the request is gone")
  H.eq(#g.players[1].hand, handBefore, "the card is still in hand")
  H.eq(g.players[1].mana, manaBefore, "and the mana was never spent")
  H.noEngineErrors(g)
end)

--===================================================== "if available" battlecries

--[[ REQ_TARGET_IF_AVAILABLE. Ironforge Rifleman, Shattered Sun Cleric, Big
     Game Hunter and the rest MUST be aimed when anything can be aimed at, and
     are simply played when nothing can. Asking NeedsTarget alone committed
     them with no target, and the battlecry did nothing at all. ]]

H.suite("controller: an 'if available' battlecry waits for its target", function(ns, H)
  local g, c = newController(ns, H)
  local wisp = H.Put(g, 2, "CS2_231")
  local i = H.Hand(g, 1, "CS2_141")           -- Ironforge Rifleman
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana

  local ok, why = c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(ok, "the play was accepted")
  H.eq(why, "awaiting target", "and is waiting for a target")
  H.eq(#g.players[1].hand, handBefore, "NOTHING is committed yet")
  H.eq(g.players[1].mana, manaBefore, "no mana spent")
  local t = c:Snapshot().targeting
  H.ok(t, "the snapshot asks for targeting")
  local legal = {}
  for _, id in ipairs(t.legal) do legal[id] = true end
  H.ok(legal[wisp.instanceId], "the Wisp may be shot")
  H.ok(legal[H.Hero(g, 2).instanceId], "and so may their face")

  H.ok(c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 }), "target clicked")
  g.bus:Drain()
  H.eq(#g.players[2].board, 0, "the battlecry killed the Wisp")
  H.eq(g.players[1].board[1].cardId, "CS2_141", "and the Rifleman is in play")
  H.notOk(c:Snapshot().targeting, "targeting is over")
  H.noEngineErrors(g)
end)

H.suite("controller: with nothing to aim at, the battlecry minion just plays", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 2, "CS2_200")                      -- 6 attack: not Big Game Hunter's

  -- Shattered Sun Cleric onto an empty board: no friendly minion to buff
  local j = H.Hand(g, 1, "EX1_019")
  local ok, why = c:HandleIntent({ kind = "PLAY_CARD", handIndex = j })
  H.ok(ok, "Cleric played")
  H.ok(why ~= "awaiting target", "with no prompt")
  H.eq(#g.players[1].board, 1, "and it is in play")

  local i = H.Hand(g, 1, "EX1_005")
  ok, why = c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(ok, "Big Game Hunter played")
  H.ok(why ~= "awaiting target", "with no prompt either")
  H.eq(g.players[1].board[2].cardId, "EX1_005", "it is in play")
  H.eq(#g.players[2].board, 1, "and the Ogre is untouched")
  H.noEngineErrors(g)
end)

H.suite("controller: the battlecry's target set is its printed one", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 2, "CS2_200")                      -- Boulderfist Ogre, 6 attack
  local golem = H.Put(g, 2, "CS2_186")        -- War Golem, 7 attack
  local i = H.Hand(g, 1, "EX1_005")
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  local t = c:Snapshot().targeting
  H.ok(t, "Big Game Hunter asks for a target")
  H.eq(#t.legal, 1, "only one thing is legal")
  H.eq(t.legal[1], golem.instanceId, "and it is the 7-attack Golem")

  local ok, why = c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 })
  H.notOk(ok, "the Ogre is refused")
  H.eq(why, "illegal target")
  H.ok(c:Snapshot().targeting, "and it is still waiting")
  H.ok(c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 2 }), "the Golem is taken")
  g.bus:Drain()
  H.eq(#g.players[2].board, 1, "the Golem is destroyed")
  H.eq(g.players[2].board[1].cardId, "CS2_200", "and the Ogre is not")
  H.noEngineErrors(g)
end)

H.suite("controller: cancelling a battlecry's aim puts the minion back in hand", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 2, "CS2_231")
  local i = H.Hand(g, 1, "CS2_141")
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i, position = 1 })
  H.ok(c:Snapshot().targeting, "aiming")
  H.ok(c:HandleIntent({ kind = "CANCEL" }), "cancelled")
  H.notOk(c:Snapshot().targeting, "the request is gone")
  H.eq(#g.players[1].hand, handBefore, "the Rifleman is still in hand")
  H.eq(#g.players[1].board, 0, "and not on the board")
  H.eq(g.players[1].mana, manaBefore, "and the mana was never spent")
  H.eq(#g.players[2].board, 1, "the Wisp lives")
  H.noEngineErrors(g)
end)

H.suite("controller: the minion lands where it was dropped once aimed", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 1, "CS2_182")
  H.Put(g, 1, "CS2_182")
  H.Put(g, 2, "CS2_231")
  local i = H.Hand(g, 1, "CS2_141")
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i, position = 2 })
  H.eq(c:Snapshot().targeting.position, 2, "the drop slot rides on the prompt")
  H.ok(c:HandleIntent({ kind = "CLICK_FOE_HERO" }), "aimed at the face")
  g.bus:Drain()
  H.eq(g.players[1].board[2].cardId, "CS2_141", "between the two Yetis")
  H.eq(H.Hero(g, 2):Health(), 29, "and the face took the shot")
  H.noEngineErrors(g)
end)

H.suite("controller: select, place, then aim -- the two-click battlecry", function(ns, H)
  --[[ The keyboard / one-button path: click the card, click where it goes,
       then click what the battlecry hits. The placing click must not be
       mistaken for the target, even though it lands on your own minion. ]]
  local g, c = newController(ns, H)
  local yeti = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "CS2_141")
  H.ok(c:HandleIntent({ kind = "CLICK_HAND", handIndex = i }), "card selected")
  local ok, why = c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 1 })
  H.ok(ok, "placed"); H.eq(why, "awaiting target", "and asking for the shot")
  H.eq(yeti:Health(), 5, "the placing click hit nothing")
  H.eq(c:Snapshot().targeting.position, 1, "in the slot that was clicked")
  H.ok(c:HandleIntent({ kind = "CLICK_FOE_HERO" }), "aimed")
  g.bus:Drain()
  H.eq(g.players[1].board[1].cardId, "CS2_141", "it landed left of the Yeti")
  H.eq(H.Hero(g, 2):Health(), 29, "and shot the face")
  H.noEngineErrors(g)
end)

H.suite("controller: the engine refuses an illegal 'if available' target", function(ns, H)
  --[[ The prompt keeps a human honest; this keeps the wire honest. A target
       is optional for these cards, but one that is given must be legal. ]]
  local g = newController(ns, H)
  local ogre = H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "EX1_005")
  local ok, why = g:PlayCard(1, i, ogre)
  H.notOk(ok, "Big Game Hunter cannot be aimed at a 6-attack Ogre")
  H.eq(why, "illegal target")
  H.eq(#g.players[1].board, 0, "and nothing was played")
  local cleric = H.Hand(g, 1, "EX1_019")
  H.notOk(g:PlayCard(1, cleric, ogre), "nor may the Cleric buff an enemy")
end)

--============================================================ choose one flow

H.suite("controller: a Choose One card raises the mode prompt FIRST", function(ns, H)
  --[[ The order matters: the mode decides what may be targeted, so asking for a
       target before the mode is chosen cannot know what is legal. ]]
  local g, c = newController(ns, H)
  H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "EX1_166")           -- Keeper of the Grove

  local ok, why = c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(ok, "accepted")
  H.eq(why, "awaiting mode", "and it wants the MODE, not a target")
  local s = c:Snapshot()
  H.ok(s.chooseOne, "the prompt is in the snapshot")
  H.eq(#s.chooseOne.options, 2, "with two options")
  H.eq(s.chooseOne.handIndex, i, "carrying the hand index to re-issue with")
  H.notOk(s.targeting, "and targeting has NOT started yet")
  H.eq(#g.players[1].board, 0, "nothing committed")
end)

H.suite("controller: mode then target then play, in that order", function(ns, H)
  local g, c = newController(ns, H)
  local ogre = H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "EX1_166")

  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  -- the board re-issues PLAY_CARD carrying the chosen mode
  local ok, why = c:HandleIntent({ kind = "PLAY_CARD", handIndex = i, mode = 1 })
  H.ok(ok, "mode accepted")
  H.eq(why, "awaiting target", "now it wants a target")
  H.notOk(c:Snapshot().chooseOne, "and the prompt has come down")

  H.ok(c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 }), "target clicked")
  g.bus:Drain()
  H.eq(ogre:Health(), 7 - 2, "Moonfire resolved for 2")
  H.eq(#g.players[1].board, 1, "and the Keeper itself arrived")
  H.noEngineErrors(g)
end)

H.suite("controller: a Choose One card needing no target plays straight away", function(ns, H)
  -- Power of the Wild: neither mode takes a target, so the mode is the only
  -- decision and the card resolves as soon as it is made.
  local g, c = newController(ns, H)
  H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "EX1_160")
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(c:Snapshot().chooseOne, "prompt is up")

  H.ok(c:HandleIntent({ kind = "PLAY_CARD", handIndex = i, mode = 1 }), "mode chosen")
  g.bus:Drain()
  H.notOk(c:Snapshot().chooseOne, "prompt is down")
  H.board(g, 1, { "CS2_182 5/6" }, "and the +1/+1 landed with no targeting step")
  H.noEngineErrors(g)
end)

H.suite("controller: cancelling the mode prompt commits nothing", function(ns, H)
  local g, c = newController(ns, H)
  local i = H.Hand(g, 1, "EX1_160")
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(c:HandleIntent({ kind = "CANCEL_MODE" }), "cancelled")
  H.notOk(c:Snapshot().chooseOne, "the prompt is gone")
  H.eq(#g.players[1].hand, handBefore, "the card is still in hand")
  H.eq(g.players[1].mana, manaBefore, "and no mana was spent")
  H.noEngineErrors(g)
end)

--============================================================ attacking

H.suite("controller: click your minion, then the target, to attack", function(ns, H)
  local g, c = newController(ns, H)
  local mine = H.Put(g, 1, "CS2_200")         -- 6/7, attack-ready by default
  local theirs = H.Put(g, 2, "CS2_182")       -- 4/5

  H.ok(c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 1 }), "attacker selected")
  H.eq(c.selected, mine, "and it is remembered")
  H.ok(c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 }), "attack declared")
  g.bus:Drain()
  H.eq(theirs:Health(), 5 - 6, "the defender took the hit")
  H.eq(mine:Health(), 7 - 4, "and the attacker took the trade")
  H.eq(c.selected, nil, "the selection is cleared")
  H.noEngineErrors(g)
end)

H.suite("controller: a summoning-sick minion cannot be selected", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 1, "CS2_200", { sick = true })
  local ok, why = c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 1 })
  H.notOk(ok, "refused")
  H.eq(why, "cannot attack", "and says why")
  H.eq(c.selected, nil, "nothing was selected")
end)

H.suite("controller: a refusal names the hero's line for it", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 1, "CS2_200", { sick = true })
  local swung = H.Put(g, 1, "CS2_182")
  swung.attacksThisTurn = 1
  local ready = H.Put(g, 1, "CS2_200")
  H.Put(g, 2, "CS2_182")                     -- no taunt
  H.Put(g, 2, "CS2_179")                     -- Sen'jin Shieldmasta, taunt

  c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 1 })
  H.eq(c:RefusalVoice("cannot attack"), "summon_sick", "a sleeping minion needs a turn")
  H.eq(c:RefusalVoice("cannot attack"), nil, "and the line is read once")
  c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 2 })
  H.eq(c:RefusalVoice("cannot attack"), "minion_attacked", "a minion that swung has attacked")
  H.ok(ready and c:HandleIntent({ kind = "CLICK_BOARD", boardIndex = 3 }), "select a ready attacker")
  local ok, why = c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 })
  H.notOk(ok)
  H.eq(c:RefusalVoice(why), "taunt", "attacking past a taunt says so")
  H.eq(c:RefusalVoice("not enough mana"), "mana", "a reason alone maps too")
  H.eq(c:RefusalVoice("not your turn"), nil, "and some refusals are silent")
end)

H.suite("sound: heroes speak their own labelled lines, once at a time", function(ns, H)
  local Stub = require("tests.wowstub")
  Stub.Install(_G); ns.Sounds.ResetMatch()
  for i = 1, 9 do
    local lines = ns.HeroVoice[("HERO_%02d"):format(i)]
    H.ok(lines, "hero " .. i .. " has lines")
    for _, key in ipairs({"greetings","well_played","thanks","sorry","oops","threaten",
                          "start","mana","taunt","summon_sick","minion_attacked","target"}) do
      H.ok(lines and lines[key], ("hero %d has %s"):format(i, key))
      local f = lines and lines[key] and io.open("ForeverHearthstone/Art/Sounds/Heroes/" .. lines[key] .. ".wav", "rb")
      H.ok(f, ("hero %d's %s is installed"):format(i, key)); if f then f:close() end
    end
  end
  H.eq(ns.Sounds.HeroForClass("MAGE"), "HERO_08", "a class finds its hero from printed data")
  ns.Sounds.PlayHero("HERO_08", "mana")
  ns.Sounds.PlayHero("HERO_08", "mana")
  H.eq(#Stub.R.sounds, 1, "a repeated error is one line, not a chorus")
  H.ok(Stub.R.sounds[1].file:find("Heroes\\VO_HERO_08_ERROR02", 1, true), "Jaina's own mana line")
  H.eq(Stub.R.sounds[1].channel, "SFX", "on the player's SFX channel")
  ns.Sounds.PlayHero("HERO_08", "thanks", true)
  H.eq(#Stub.R.sounds, 2, "an emote is deliberate and always speaks")
  H.notOk(ns.Sounds.PlayHero("EX1_323h", "thanks", true), "a hero without lines stays quiet")
end)

H.suite("controller: clicking an enemy with nothing selected does nothing", function(ns, H)
  local g, c = newController(ns, H)
  H.Put(g, 2, "CS2_182")
  local ok, why = c:HandleIntent({ kind = "CLICK_FOE_BOARD", boardIndex = 1 })
  H.notOk(ok, "refused")
  H.eq(why, "nothing selected", "and says why")
  H.noEngineErrors(g)
end)

--============================================================ turn control

H.suite("controller: acting out of turn is refused across the board", function(ns, H)
  local g, c = newController(ns, H)
  local i = H.Hand(g, 1, "CS2_182")
  H.Put(g, 1, "CS2_200")
  g.activePlayer = 2

  for _, intent in ipairs({
    { kind = "PLAY_CARD", handIndex = i },
    { kind = "END_TURN" },
    { kind = "CLICK_BOARD", boardIndex = 1 },
    { kind = "HERO_POWER" },
  }) do
    local ok, why = c:HandleIntent(intent)
    H.notOk(ok, intent.kind .. " is refused on the opponent's turn")
    H.eq(why, "not your turn", intent.kind .. " says why")
  end
  H.eq(#g.players[1].board, 1, "and the board is untouched")
end)

H.suite("controller: ending the turn hands over and clears any pending state", function(ns, H)
  local g, c = newController(ns, H, { class1 = "MAGE" })
  H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "CS2_024")
  c:HandleIntent({ kind = "PLAY_CARD", handIndex = i })
  H.ok(c:Snapshot().targeting, "a target request is outstanding")

  H.ok(c:HandleIntent({ kind = "END_TURN" }), "turn ended")
  H.eq(g.activePlayer, 2, "it is the opponent's turn")
  H.notOk(c:Snapshot().targeting, "and the stale request was dropped")
  H.noEngineErrors(g)
end)

H.suite("controller: an unknown intent is refused rather than ignored", function(ns, H)
  -- Fail loudly: a typo in an intent name must not look like a no-op.
  local g, c = newController(ns, H)
  local ok, why = c:HandleIntent({ kind = "WIGGLE" })
  H.notOk(ok, "refused")
  H.ok(why and why:find("unknown intent"), "and names the intent")
  H.notOk(c:HandleIntent({}), "so is an intent with no kind")
end)

--======================================================= what a minion IS now

H.suite("controller: the board carries LIVE stats, not printed ones", function(ns, H)
  --[[ THE BUG. The snapshot gave the board as card ids, and a card id is
       PRINTED data -- the 4/5 the Yeti was printed as, forever. Damage it,
       buff it, freeze it: the board kept drawing 4/5. You hit a minion for
       three and the number under it did not move, which reads as the damage
       not having happened. ]]
  local g = H.NewGame()
  local yeti = H.Put(g, 1, "CS2_182")           -- Chillwind Yeti, 4/5
  local c = ns.Controller.New({ game = g, player = 1 })

  local snap = c:Snapshot()
  H.eq(snap.boardStats[1].atk, 4, "printed attack to begin with")
  H.eq(snap.boardStats[1].health, 5, "printed health to begin with")
  H.notOk(snap.boardStats[1].damaged, "and undamaged")

  g:DealDamage(yeti, 3, nil, false)
  snap = c:Snapshot()
  H.eq(snap.boardStats[1].health, 2, "the damage is visible")
  H.eq(snap.boardStats[1].maxHealth, 5, "out of its unchanged maximum")
  H.ok(snap.boardStats[1].damaged, "and it is marked damaged, so it can be drawn red")
  H.eq(snap.board[1], "CS2_182", "the id is still there for the art and the text")
end)

H.suite("controller: live stats follow a buff, and the enemy board has them too", function(ns, H)
  local g = H.NewGame()
  local mine = H.Put(g, 1, "CS2_182")
  local theirs = H.Put(g, 2, "CS2_231")         -- Wisp, 1/1
  local c = ns.Controller.New({ game = g, player = 1 })

  mine:AddEnchantment(2, 2)
  local snap = c:Snapshot()
  H.eq(snap.boardStats[1].atk, 6, "the buff shows on attack")
  H.eq(snap.boardStats[1].maxHealth, 7, "and on health")
  H.eq(snap.foeBoardStats[1].atk, 1, "their board is reported too")
  H.eq(#snap.foeBoardStats, 1, "one of them")
end)

H.suite("controller: taunt, stealth and frozen reach the board", function(ns, H)
  --[[ These change what you are ALLOWED to do to a minion, so they have to be
       visible without reading the card text. The snapshot is where the board
       can learn them at all. ]]
  local g = H.NewGame()
  local e = H.Put(g, 1, "CS2_182")
  e.frozen = true
  local c = ns.Controller.New({ game = g, player = 1 })
  local st = c:Snapshot().boardStats[1]
  H.ok(st.frozen, "frozen is carried")
  H.notOk(st.taunt, "a Yeti has no Taunt")
  H.notOk(st.stealth, "nor Stealth")
end)

H.suite("controller: inspection carries buff sources and expires them",function(ns,H)
  local g=H.NewGame()
  local e=g:Summon("CS2_182",1)
  e:AddEnchantment(1,1,{ns.KEYWORD.TAUNT},"EX1_093")
  e:AddTimedEnchantment(0,0,{ns.KEYWORD.STEALTH},ns.DURATION.START_OF_YOUR_NEXT_TURN,g.turn,1,"EX1_128")
  g:Summon("EX1_162",1)
  g:RecalcAuras()
  local c=ns.Controller.New({game=g,player=1})
  local effects=table.concat(c:Snapshot().boardStats[1].effects,"\n")
  H.ok(effects:find("Defender of Argus")); H.ok(effects:find("Conceal"))
  H.ok(effects:find("Dire Wolf Alpha")); H.ok(effects:find("taunt"))
  e:ExpireTimed(function() return true end)
  H.notOk(table.concat(e:EffectDescriptions(),"\n"):find("Conceal"))
  e:Silence(); g:RecalcAuras()
  local after=table.concat(e:EffectDescriptions(),"\n")
  H.notOk(after:find("Defender of Argus")); H.ok(after:find("Dire Wolf Alpha"))
  g:ResetToPrinted(e)
  H.eq(#e:EffectDescriptions(),0)
end)

H.suite("controller: spell text follows spell power and silence", function(ns,H)
  local g = H.NewGame()
  local fire = H.Hand(g,1,"CS2_029"); local missiles = H.Hand(g,1,"EX1_277"); local storm = H.Hand(g,1,"EX1_259")
  local c = ns.Controller.New({game=g,player=1})
  local kobold = g:Summon("CS2_142",1)
  H.eq(c:Snapshot().handStats[fire].rulesText,"Deal 7 damage.")
  H.eq(c:Snapshot().handStats[missiles].rulesText,"Deal 4 damage randomly split among enemy characters.")
  H.ok(c:Snapshot().handStats[storm].rulesText:find("3-4 damage",1,true))
  kobold:Silence(); g.bus:Drain()
  H.eq(c:Snapshot().handStats[fire].rulesText,"Deal 6 damage.")
  H.eq(ns.PrintedCards.CS2_029.text,"Deal 6 damage.")
end)
