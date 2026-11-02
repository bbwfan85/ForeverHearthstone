--[[ tests/test_director.lua -- which animation plays, and when.

  Client/FX had a tested choreography library long before there was a match to
  play it in. The Director is what finally drives it, and because it is pure --
  handed actions and elapsed time, returning a plan -- the FEEL of a turn is
  assertable here rather than something you check by staring at the screen.

  The rope is the interesting half. It is the only piece of choreography with a
  clock, and it is the first thing in the project to consume Game:TurnSeconds --
  which means Nozdormu, authored months ago and inert ever since, finally does
  something.
]]
local H = require("tests.harness")

H.suite("director: Boom Bot resolves and animates on either side across seeds",function(ns,H)
  for owner=1,2 do
    for seed=1,32 do
      local g=H.NewGame({seed=seed})
      H.SetActive(g,owner)
      H.Put(g,owner,"CS2_182") -- retain a neighbour to expose slot-shift mistakes
      local bot=H.Put(g,owner,"GVG_110t")
      local enemy=3-owner
      local wall=H.Put(g,enemy,"CS2_186")
      local action={kind="ATTACK",attackerId=bot.instanceId,targetId=wall.instanceId}
      local before=ns.Director.Before(g,owner,action)
      H.ok(ns.Actions.Run(g,owner,action))
      local damage,death=0,0
      for _,e in ipairs(g.bus.log) do
        if e.seq>before.eventSeq and e.event==ns.EVENT.DAMAGE_DEALT and e.src=="GVG_110t" then
          damage=damage+e.amount
        end
      end
      H.ok(damage>=2 and damage<=5,"one attack plus 1-4 deathrattle damage")
      local plans=ns.Director.New({player=1}):Plan(g,owner,action,before)
      local bursts={}
      ns.Director.Run(plans,{
        EffectPoint=function(_,o) return {side=o.side,index=o.index,isHero=o.isHero} end,
        AbilityBurst=function(_,point,kind) bursts[#bursts+1]={point=point,kind=kind} end,
      },function(tl) tl:RunAll(.016) end)
      for _,b in ipairs(bursts) do
        if b.kind=="deathrattle" then
          death=death+1; H.eq(b.point.index,2)
          H.eq(b.point.side,owner==1 and "self" or "foe")
        end
      end
      H.eq(death,1,"dead bot gets an actual animation beat")
      H.noEngineErrors(g)
    end
  end
end)

H.suite("director: simultaneous Boom Bots and silence have truthful cues",function(ns,H)
  for _,silenced in ipairs({false,true}) do
    local g=H.NewGame()
    H.SetActive(g,2); H.Mana(g,2,10)
    for i=1,2 do local bot=H.Put(g,1,"GVG_110t"); if silenced then bot:Silence() end end
    local hand=H.Hand(g,2,"CS2_032") -- Flamestrike kills both together
    local action={kind="PLAY_CARD",handIndex=hand}
    local before=ns.Director.Before(g,2,action)
    H.ok(ns.Actions.Run(g,2,action))
    local damage=30-g.players[2].hero:Health()
    if silenced then H.eq(damage,0) else H.ok(damage>=2 and damage<=8) end
    local count=0
    for _,p in ipairs(ns.Director.New():Plan(g,2,action,before)) do
      if p.sequence=="AbilityEffect" and p.opts.kind=="deathrattle" then count=count+1 end
    end
    H.eq(count,silenced and 0 or 2)
    H.noEngineErrors(g)
  end
end)

H.suite("director: deathrattle summons and battlecries have fallback cues",function(ns,H)
  local g=H.NewGame()
  local egg=H.Put(g,1,"FP1_007")
  local action={kind="END_TURN"}
  local before=ns.Director.Before(g,1,action)
  egg.pendingDestroy=true; g:ProcessDeaths(); g.bus:Drain()
  local kinds={}
  for _,p in ipairs(ns.Director.New():Plan(g,1,action,before)) do
    if p.sequence=="AbilityEffect" then kinds[p.opts.kind]=true end
  end
  H.ok(kinds.deathrattle); H.ok(kinds.summon)
  H.eq(g.players[1].board[1].cardId,"FP1_007t")
  H.Mana(g,1,10)
  local hand=H.Hand(g,1,"GVG_110")
  action={kind="PLAY_CARD",handIndex=hand}
  before=ns.Director.Before(g,1,action)
  H.ok(ns.Actions.Run(g,1,action))
  local summons,battlecries=0,0
  for _,p in ipairs(ns.Director.New():Plan(g,1,action,before)) do
    if p.sequence=="AbilityEffect" then
      if p.opts.kind=="summon" then summons=summons+1 end
      if p.opts.kind=="battlecry" then battlecries=battlecries+1 end
    end
  end
  H.eq(summons,2,"only tokens, not the played card, get summon fallback")
  H.eq(battlecries,1)
  H.noEngineErrors(g)
end)

H.suite("director: history freezes damage and health at each hit",function(ns,H)
  local g=H.NewGame()
  local target=g.players[2].hero
  local before={eventSeq=g.bus.seq}
  g:DealDamage(target,3,g.players[1].hero,false)
  g:DealDamage(target,2,g.players[1].hero,false)
  local outcomes=ns.Director.Outcomes(g,before)
  H.eq(#outcomes,2)
  H.eq(outcomes[1].health,27); H.eq(outcomes[2].health,25)
  H.eq(outcomes[1].amount,3); H.eq(outcomes[2].amount,2)
  g:Heal(target,5,g.players[1].hero)
  H.eq(outcomes[2].health,25,"later healing cannot rewrite the old action")
end)

local function newDirector(ns, player, opts)
  opts = opts or {}
  opts.player = player or 1
  return ns.Director.New(opts)
end

local function planFor(ns, game, player, action, director)
  local before = ns.Director.Before(game, player, action)
  local ok = ns.Actions.Run(game, player, action)
  if not ok then error("the action under test was refused", 2) end
  return director:Plan(game, player, action, before), ok
end

--============================================================ actions

H.suite("director: a weapon swing uses the hero actor", function(ns, H)
  local g = H.NewGame()
  local a, d = g.players[1].hero, g.players[2].hero
  local action = {kind="ATTACK", attackerId=a.instanceId, targetId=d.instanceId}
  local plan = newDirector(ns,1):Plan(g,1,action,ns.Director.Before(g,1,action))[1]
  H.ok(plan.opts.attackerIsHero)
  H.ok(plan.opts.defenderIsHero)
end)

H.suite("director: playing a minion animates a minion", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1)
  local d = newDirector(ns, 1)
  local i = H.Hand(g, 1, "CS2_182")            -- Chillwind Yeti
  local plans = planFor(ns, g, 1, { kind = "PLAY_CARD", handIndex = i }, d)
  H.eq(#plans, 1, "one sequence")
  H.eq(plans[1].sequence, "PlayMinion", "the minion sequence")
  H.eq(plans[1].opts.mine, true, "and it knows it was ours")
end)

H.suite("director: playing a spell animates a spell", function(ns, H)
  local g = H.NewGame()
  H.Mana(g, 1)
  local d = newDirector(ns, 1)
  H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "CS2_029")            -- Fireball, needs a target
  local target = g.players[2].board[1]
  local plans = planFor(ns, g, 1,
    { kind = "PLAY_CARD", handIndex = i, targetId = target.instanceId }, d)
  H.eq(plans[1].sequence, "PlaySpell", "the spell sequence")
  H.eq(plans[1].opts.targeted, true, "and it knows the spell was aimed at something")
end)

H.suite("director: the card is identified BEFORE it leaves the hand", function(ns, H)
  --[[ THE BUG THIS PREVENTS. Playing a card removes it from the hand, so a
       director that reads the hand slot afterwards animates whatever slid into
       it -- a spell played from slot 2 animates as whatever card was in slot 3.
       The evidence has to be collected first. ]]
  local g = H.NewGame()
  H.Mana(g, 1)
  local d = newDirector(ns, 1)
  local i = H.Hand(g, 1, "CS2_182")            -- a MINION at this index
  H.Hand(g, 1, "CS2_029")                      -- a SPELL right after it
  local plans = planFor(ns, g, 1, { kind = "PLAY_CARD", handIndex = i }, d)
  H.eq(plans[1].sequence, "PlayMinion",
       "the minion animated as a minion, not as the spell that shuffled into its slot")
end)

H.suite("director: an attack knows who died", function(ns, H)
  --[[ Whether a sequence ends on an impact or on a death is the difference
       between a trade reading as a trade and reading as a bump. It is the one
       fact that must come from AFTER the action. ]]
  local g = H.NewGame()
  local d = newDirector(ns, 1)
  local mine = H.Put(g, 1, "CS2_182")          -- 4/5
  local theirs = H.Put(g, 2, "CS2_231")        -- 1/1 Wisp
  H.SetActive(g, 1)
  local plans = planFor(ns, g, 1,
    { kind = "ATTACK", attackerId = mine.instanceId, targetId = theirs.instanceId }, d)
  H.eq(plans[1].sequence, "Attack", "the attack sequence")
  H.eq(plans[1].opts.defenderDied, true, "the Wisp died")
  H.eq(plans[1].opts.attackerDied, false, "the Yeti did not")
end)

H.suite("director: the opponent's actions animate too", function(ns, H)
  -- A board where only your own plays have weight reads as a bug.
  local g = H.NewGame({ firstPlayer = 2 })
  H.Mana(g, 2)
  local d = newDirector(ns, 1)                 -- we are player 1
  local i = H.Hand(g, 2, "CS2_182")
  local plans = planFor(ns, g, 2, { kind = "PLAY_CARD", handIndex = i }, d)
  H.eq(#plans, 1, "their minion animates")
  H.eq(plans[1].opts.mine, false, "on their side of the table")
end)

H.suite("director: an action with no visual plans nothing", function(ns, H)
  local g = H.NewGame()
  local d = newDirector(ns, 1)
  local plans = d:Plan(g, 1, { kind = "HERO_POWER" }, nil)
  H.eq(#plans, 1, "hero powers have their own effect")
  H.eq(plans[1].sequence, "HeroPower", "never animate a hand card for a power")
  H.eq(#d:Plan(g, 1, nil, nil), 0, "and a nil action is harmless")
end)

--============================================================ the rope

H.suite("director: the rope appears near the end of the turn, once", function(ns, H)
  local g = H.NewGame()
  local d = newDirector(ns, 1)
  d:ResetTurn(g)

  local total = g:TurnSeconds()
  H.eq(total, ns.RULES.TURN_SECONDS, "an ordinary turn is the full length")

  local seen = 0
  --[[ Ticked in small steps, like an OnUpdate. A rope that appears because the
       test advanced the clock in one jump proves nothing about a real frame. ]]
  for _ = 1, math.floor((total - ns.RULES.ROPE_SECONDS - 1) / 0.5) do
    seen = seen + #d:Tick(g, 0.5)
  end
  H.eq(seen, 0, "silent for the first minute")

  local plans = d:Tick(g, 1.0)
  H.eq(#plans, 1, "then the rope")
  H.eq(plans[1].sequence, "Rope", "the rope sequence")
  H.ok(plans[1].opts.seconds <= ns.RULES.ROPE_SECONDS,
       "burning for what is actually left, not a constant")

  local again = 0
  for _ = 1, 10 do again = again + #d:Tick(g, 0.5) end
  H.eq(again, 0, "and it never starts a second one")
end)

H.suite("director: NOZDORMU finally does something", function(ns, H)
  --[[ The card has expressed the rule since the day it was authored --
       Game:TurnSeconds returns 15 for both players -- and nothing consumed it.
       This is the first thing that does: with Nozdormu out the whole turn is
       fifteen seconds, so the rope IS the turn. ]]
  local g = H.NewGame()
  H.Put(g, 1, "EX1_560")                       -- Nozdormu
  H.eq(g:TurnSeconds(), 15, "the turn is fifteen seconds")

  local d = newDirector(ns, 1)
  d:ResetTurn(g)
  local plans = d:Tick(g, 0.1)
  H.eq(#plans, 1, "the rope is there immediately")
  H.eq(plans[1].sequence, "Rope", "as a rope")
  H.ok(plans[1].opts.seconds <= 15, "lasting at most the whole turn")
end)

H.suite("director: opponent rope is visible without local expiry authority", function(ns, H)
  local g = H.NewGame({ firstPlayer = 2 })
  local expired=0
  local d = newDirector(ns, 1,{onExpire=function() expired=expired+1 end})
  d:ResetTurn(g)
  local seen = 0
  for _ = 1, 400 do seen = seen + #d:Tick(g, 0.5) end
  H.eq(seen, 1, "opponent rope appears once")
  H.eq(expired,0,"only the active client may end the turn")
  H.eq(d:TurnRemaining(g), 0, "opponent countdown reaches zero")
end)

H.suite("director: running out of time ends YOUR OWN turn", function(ns, H)
  --[[ The client whose turn it is ends it. In a duel that is an ordinary
       END_TURN action crossing the wire like any other, so the two clients
       cannot disagree about whether the rope ran out. ]]
  local g = H.NewGame()
  local expired = 0
  local d = newDirector(ns, 1, { onExpire = function() expired = expired + 1 end })
  d:ResetTurn(g)
  for _ = 1, 200 do d:Tick(g, 0.5) end
  H.eq(expired, 1, "expired exactly once, not once per frame")

  --[[ And it must arm again for the next turn. An expiry flag that is never
       cleared fires once in the whole match and leaves every later turn running
       forever, which looks exactly like the timer never having been wired. ]]
  g:EndTurn(); g.bus:Drain()
  g:EndTurn(); g.bus:Drain()
  for _ = 1, 200 do d:Tick(g, 0.5) end
  H.eq(expired, 2, "and again on the next turn")
end)

H.suite("director: the clock restarts when the turn does", function(ns, H)
  local g = H.NewGame()
  local d = newDirector(ns, 1)
  d:ResetTurn(g)
  for _ = 1, 60 do d:Tick(g, 1.0) end          -- burn most of the turn
  H.ok(d.ropeShown, "the rope was shown")

  g:EndTurn(); g.bus:Drain()
  g:EndTurn(); g.bus:Drain()                   -- back round to us
  d:Tick(g, 0.1)
  H.notOk(d.ropeShown, "a new turn starts with a fresh clock")
  H.ok(d:TurnRemaining(g) > ns.RULES.ROPE_SECONDS, "and a full turn to spend")
end)

--============================================================ running it

H.suite("director: a plan runs against a stage", function(ns, H)
  --[[ The end-to-end check without WoW: a plan, the real choreography library,
       and a stage that records. If this passes, the only thing left between
       here and a moving board is frames. ]]
  local calls = {}
  local stage = {
    Card = function() return setmetatable({}, { __index = function()
      return function(s) return s end end }) end,
    Board = function() return setmetatable({}, { __index = function()
      return function(s) return s end end }) end,
    Sound = function(_, key) calls[#calls + 1] = key end,
    Particles = function(_, kind) calls[#calls + 1] = kind end,
    Screen = function() return setmetatable({}, { __index = function()
      return function(s) return s end end }) end,
    Toast = function() return setmetatable({}, { __index = function()
      return function(s) return s end end }) end,
  }
  local ran = 0
  ns.Director.Run({ { sequence = "PlayMinion", opts = { cardIndex = 1, slot = 1 } } },
                  stage, function(tl) ran = ran + 1; tl:RunAll(0.016) end)
  H.eq(ran, 1, "one timeline ran")
  H.ok(#calls > 0, "and it reached the stage: " .. table.concat(calls, ", "))
end)

H.suite("director: a plan naming a sequence that does not exist is ignored", function(ns, H)
  local ran = 0
  local ok = pcall(ns.Director.Run, { { sequence = "NoSuchSequence" } }, {},
                   function() ran = ran + 1 end)
  H.ok(ok, "no crash in an OnUpdate")
  H.eq(ran, 0, "and nothing ran")
end)

--============================================== whose minion is being animated

H.suite("director: an attack says whose side each combatant is on", function(ns, H)
  --[[ THE BUG. Board slot 1 exists on both boards, and the Attack sequence
       resolved every index against the LOCAL player's widgets. So when the
       practice opponent swung, the animation played on one of your minions --
       or, with an empty board, on a card in your hand. From the outside that is
       indistinguishable from nothing happening, which is what an enemy attack
       looked like: your health dropped and the board sat still. ]]
  local g = H.NewGame({ firstPlayer = 2 })
  local mine = H.Put(g, 1, "CS2_182")          -- Chillwind Yeti, 4/5
  local theirs = H.Put(g, 2, "CS2_182")
  theirs.summonedTurn = 0                       -- allowed to swing
  H.SetActive(g, 2)
  local d = newDirector(ns, 1)                  -- we are player 1

  local plans = planFor(ns, g, 2,
    { kind = "ATTACK", attackerId = theirs.instanceId, targetId = mine.instanceId }, d)
  H.eq(#plans, 1, "combat already has an impact animation")
  local o = plans[1].opts
  H.eq(o.attackerSide, "foe", "the attacker is theirs")
  H.eq(o.defenderSide, "self", "and it is hitting ours")
  H.eq(o.mine, false, "the action was not ours")
  H.ok(o.dy < 0, "and it lunges down the table, toward us")
end)

H.suite("director: going face is aimed at the hero, not at board slot 1", function(ns, H)
  --[[ A hero has no boardIndex. Without being told the defender is a hero the
       sequence fell back to slot 1 and punched a minion instead of the face. ]]
  local g = H.NewGame()
  local mine = H.Put(g, 1, "CS2_182")
  mine.summonedTurn = 0
  H.SetActive(g, 1)
  local d = newDirector(ns, 1)
  local foeHero = H.Hero(g, 2)
  local plans = planFor(ns, g, 1,
    { kind = "ATTACK", attackerId = mine.instanceId, targetId = foeHero.instanceId }, d)
  H.eq(plans[1].opts.defenderIsHero, true, "the defender is a hero")
  H.eq(plans[1].opts.attackerSide, "self", "the attacker is ours")
  H.ok(plans[1].opts.dy > 0, "and it lunges up the table, toward them")
end)

H.suite("director: a kill is reported so something can be seen to die", function(ns, H)
  local g = H.NewGame()
  local yeti = H.Put(g, 1, "CS2_182")           -- 4/5
  yeti.summonedTurn = 0
  local wisp = H.Put(g, 2, "CS2_231")           -- 1/1
  H.SetActive(g, 1)
  local d = newDirector(ns, 1)
  local plans = planFor(ns, g, 1,
    { kind = "ATTACK", attackerId = yeti.instanceId, targetId = wisp.instanceId }, d)
  local o = plans[1].opts
  H.eq(o.defenderDied, true, "the Wisp died")
  H.eq(o.attackerDied, false, "the Yeti did not")
  H.eq(o.lethal, true, "so the hit gets the heavier sound and shake")
  H.eq(o.defenderSide, "foe", "and the thing that breaks is on their side")
end)

--=============================================================== the mulligan

local function tickFor(d, g, seconds)
  local fired
  d.onExpire = function(what) fired = what or true end
  local step = 0.5
  for _ = 1, math.ceil(seconds / step) do d:Tick(g, step) end
  return fired
end

H.suite("director: the mulligan has a deadline, and it is not a turn", function(ns, H)
  --[[ THE BUG. The clock called onExpire with no argument and the caller sent
       END_TURN. During the mulligan the controller refuses END_TURN -- "choose
       which cards to throw back first" -- so the rope burned all the way down,
       the timer fired, the refusal was swallowed, and nothing happened at all.
       Running out of time during a mulligan did literally nothing. ]]
  local g = H.NewGame()
  g:Deal()
  H.ok(g:AwaitingMulligan(1), "we are in the mulligan")
  local d = newDirector(ns, 1)
  d:ResetTurn(g)
  local what = tickFor(d, g, ns.RULES.MULLIGAN_SECONDS + 1)
  H.eq(what, "mulligan", "the deadline that passed was the MULLIGAN one")
end)

H.suite("director: the player going second is on the clock too", function(ns, H)
  --[[ The mulligan clock used to be gated on `activePlayer`, and the player
       going second is never the active player during the mulligan -- so they
       had no deadline at all and could stall the match indefinitely. Both
       players choose at once; `activePlayer` says nothing about it. ]]
  local g = H.NewGame({ firstPlayer = 1 })
  g:Deal()
  local d = newDirector(ns, 2)                  -- we are the player going second
  d:ResetTurn(g)
  H.ok(g.activePlayer ~= 2, "we are not the active player")
  local what = tickFor(d, g, ns.RULES.MULLIGAN_SECONDS + 1)
  H.eq(what, "mulligan", "and we are still on a clock")
end)

H.suite("director: a turn deadline still reports as a turn", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local d = newDirector(ns, 1)
  d:ResetTurn(g)
  local what = tickFor(d, g, g:TurnSeconds() + 1)
  H.eq(what, "turn", "so the caller ends the turn rather than the mulligan")
end)

H.suite("director: a minion that DIES swinging still animates itself", function(ns, H)
  --[[ THE BUG. The plan read `boardIndex` off the combatants AFTER the attack
       had been applied. A minion that dies swinging has been taken off the
       board by then, so its index is nil -- and the plan fell back to slot 1.
       Every trade where the attacker died therefore played the attack
       animation on the LEFTMOST minion, which from the outside is
       indistinguishable from that minion attacking a second time. ]]
  local g = H.NewGame()
  H.Put(g, 1, "CS2_182")                        -- slot 1: an innocent bystander
  H.Put(g, 1, "CS2_182")
  local doomed = H.Put(g, 1, "CS2_231")         -- slot 3: Wisp, 1/1
  doomed.summonedTurn = 0
  local killer = H.Put(g, 2, "CS2_182")         -- 4/5, kills it and survives
  H.SetActive(g, 1)
  local d = newDirector(ns, 1)

  local plans = planFor(ns, g, 1,
    { kind = "ATTACK", attackerId = doomed.instanceId, targetId = killer.instanceId }, d)
  local o = plans[1].opts
  H.eq(o.attackerDied, true, "the Wisp died on the swing")
  H.eq(o.attackerIndex, 3, "and the animation is still ITS slot, not slot 1")
  H.eq(o.attackerSide, "self", "on our side")
  H.eq(o.defenderIndex, 1, "their minion is where it was")
end)

H.suite("director: a death elsewhere does not shift the animation", function(ns, H)
  --[[ The same failure with the survivors: a death anywhere in the row
       reindexes everything to its right, so indices read after the attack
       belong to whoever slid into the slot. ]]
  local g = H.NewGame()
  local wisp = H.Put(g, 2, "CS2_231")           -- their slot 1, about to die
  local yeti = H.Put(g, 2, "CS2_182")           -- their slot 2
  local mine = H.Put(g, 1, "CS2_182")
  mine.summonedTurn = 0
  H.SetActive(g, 1)
  local d = newDirector(ns, 1)

  local plans = planFor(ns, g, 1,
    { kind = "ATTACK", attackerId = mine.instanceId, targetId = wisp.instanceId }, d)
  H.eq(plans[1].opts.defenderIndex, 1, "the thing that died is drawn where it stood")
  H.eq(plans[1].opts.defenderSide, "foe", "on their side")
  H.eq(yeti.boardIndex, 1, "even though the survivor has since slid into slot 1")
end)

--============================================================ triggers

H.suite("director: a minion's trigger gets its own beat when it fires", function(ns, H)
  local g = H.NewGame()
  local juggler = H.Put(g, 1, "NEW1_019")                -- Knife Juggler
  local d = newDirector(ns, 1)
  local log = #g.bus.log
  local i = H.Hand(g, 1, "CS2_231")                     -- Wisp, 0 mana
  local plans = planFor(ns, g, 1, { kind = "PLAY_CARD", handIndex = i }, d)
  local beat
  for _, p in ipairs(plans) do if p.sequence == "MinionTrigger" then beat = p end end
  H.ok(beat, "the Juggler's throw is shown")
  H.eq(beat.opts.cardId, "NEW1_019"); H.eq(beat.opts.side, "self")
  H.eq(beat.opts.index, juggler.boardIndex)
  H.ok(beat.opts.at > 0.2, "after the play that set it off")
  for _, e in ipairs(g.bus.log) do
    H.notOk(tostring(e.event):find("TRIGGER", 1, true), "presentation bookkeeping never enters the hashed log")
  end
  H.ok(#g.bus.log > log)
end)

H.suite("director: end-of-turn triggers show on END_TURN, once per minion", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "EX1_298")                                -- Ragnaros the Firelord
  H.Put(g, 2, "NEW1_019")
  local d = newDirector(ns, 1)
  local plans = planFor(ns, g, 1, { kind = "END_TURN" }, d)
  local rag = 0
  for _, p in ipairs(plans) do
    if p.sequence == "MinionTrigger" and p.opts.cardId == "EX1_298" then rag = rag + 1 end
  end
  H.eq(rag, 1, "Ragnaros fires at the end of the turn")
  local quiet = newDirector(ns, 1):Plan(g, 1, { kind = "END_TURN" }, { firedCount = #g.bus.fired })
  for _, p in ipairs(quiet) do H.notOk(p.sequence == "MinionTrigger", "nothing new fired, nothing shown") end
end)
