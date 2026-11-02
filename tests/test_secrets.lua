--[[ tests/test_secrets.lua -- secret zone and cancellable events.

  Pinned data:
    EX1_610 Explosive Trap  2 mana  "Secret: When your hero is attacked, deal 2 damage to all enemies"
    EX1_554 Snake Trap      2 mana  "Secret: When one of your minions is attacked, summon three 1/1 Snakes"
    EX1_294 Mirror Entity   3 mana  "Secret: When your opponent plays a minion, summon a copy of it"
    EX1_287 Counterspell    3 mana  "Secret: When your opponent casts a spell, Counter it"
    EX1_611 Freezing Trap   2 mana  "Secret: When an enemy minion attacks, return it to its owner's hand"
]]
local H = require("tests.harness")

local function armSecret(g, player, cardId)
  local pr = g:Printed(cardId)
  local e = H.ns.Entity.New(pr, player)
  g:PlaySecret(player, e)
  return e
end

H.suite("secret: Explosive Trap fires on a hero attack", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  armSecret(g, 2, "EX1_610")

  local attacker = H.Put(g, 1, "CS2_119")   -- Oasis Snapjaw 2/7
  local bystander = H.Put(g, 1, "CS2_231")  -- Wisp 1/1, dies to the trap
  g:Attack(attacker, H.Hero(g, 2))
  g.bus:Drain()

  H.eq(attacker:Health(), 5, "attacker took 2 from the trap")
  H.eq(#g.players[1].board, 1, "the Wisp died to the trap")
  H.eq(H.Hero(g, 1):Health(), 28, "attacking hero took 2")
  H.eq(#g.players[2].secrets, 0, "secret was consumed")
  -- The attack still resolves: Explosive Trap does not cancel.
  H.eq(H.Hero(g, 2):Health(), 28, "the attack still landed for 2")
  H.noEngineErrors(g)
end)

H.suite("secret: Explosive Trap does NOT fire on a minion attack", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  armSecret(g, 2, "EX1_610")
  local attacker = H.Put(g, 1, "CS2_119")
  local defender = H.Put(g, 2, "CS2_119")
  g:Attack(attacker, defender)
  g.bus:Drain()
  H.eq(#g.players[2].secrets, 1, "secret still armed")
  H.noEngineErrors(g)
end)

H.suite("secret: Snake Trap fires on a minion attack only", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  armSecret(g, 2, "EX1_554")
  local attacker = H.Put(g, 1, "CS2_119")
  local defender = H.Put(g, 2, "CS2_119")
  g:Attack(attacker, defender)
  g.bus:Drain()

  local snakes = 0
  for _, e in ipairs(g.players[2].board) do
    if e.cardId == "EX1_554t" then snakes = snakes + 1 end
  end
  H.eq(snakes, 3, "three snakes summoned on the defender's side")
  H.eq(#g.players[2].secrets, 0, "secret consumed")
  H.noEngineErrors(g)
end)

H.suite("secret: Counterspell cancels the spell but mana is still spent", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  armSecret(g, 2, "EX1_287")

  local target = H.Put(g, 2, "CS2_119")     -- Oasis Snapjaw 2/7
  local idx = H.Hand(g, 1, "CS2_029")       -- Fireball, 4 mana, 6 damage
  local manaBefore = g:AvailableMana(1)
  local ok = g:PlayCard(1, idx, target)
  g.bus:Drain()

  H.ok(ok, "the play was accepted")
  H.eq(target:Health(), 7, "Fireball was countered, no damage")
  H.eq(g:AvailableMana(1), manaBefore - 4, "mana was still spent")
  H.eq(#g.players[2].secrets, 0, "Counterspell consumed")
  H.noEngineErrors(g)
end)

H.suite("secret: Mirror Entity copies printed stats, not buffed ones", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  armSecret(g, 2, "EX1_294")

  -- Play a Chillwind Yeti (4/5) while a friendly Dire Wolf Alpha would buff it.
  H.Put(g, 1, "EX1_162")                    -- Dire Wolf Alpha, +1 atk adjacent
  local idx = H.Hand(g, 1, "CS2_182")       -- Chillwind Yeti
  g:PlayCard(1, idx)
  g.bus:Drain()

  local copy
  for _, e in ipairs(g.players[2].board) do
    if e.cardId == "CS2_182" then copy = e end
  end
  H.ok(copy, "Mirror Entity produced a Yeti")
  if copy then
    H.eq(copy:Attack(), 4, "copy uses printed attack, not the aura-buffed value")
    H.eq(copy:MaxHealth(), 5, "copy uses printed health")
  end
  H.noEngineErrors(g)
end)

H.suite("secret: Freezing Trap cancels the attack and bounces the attacker", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  armSecret(g, 2, "EX1_611")

  local attacker = H.Put(g, 1, "CS2_119")   -- Oasis Snapjaw 2/7
  local handBefore = #g.players[1].hand
  local heroBefore = H.Hero(g, 2):Health()
  g:Attack(attacker, H.Hero(g, 2))
  g.bus:Drain()

  H.eq(#g.players[1].board, 0, "attacker left the board")
  H.eq(#g.players[1].hand, handBefore + 1, "attacker returned to hand")
  H.eq(H.Hero(g, 2):Health(), heroBefore, "the attack was cancelled")
  H.noEngineErrors(g)
end)

H.suite("secret: cannot arm two copies of the same secret", function(ns, H)
  local g = H.NewGame()
  local a = armSecret(g, 1, "EX1_610")
  H.eq(#g.players[1].secrets, 1, "first armed")
  local pr = g:Printed("EX1_610")
  local dup = ns.Entity.New(pr, 1)
  local ok = g:PlaySecret(1, dup)
  H.notOk(ok, "duplicate rejected")
  H.eq(#g.players[1].secrets, 1, "still only one")
  H.noEngineErrors(g)
end)

H.suite("secret: zone is capped at five", function(ns, H)
  local g = H.NewGame()
  for _, id in ipairs({ "EX1_610", "EX1_554", "EX1_294", "EX1_287", "EX1_611" }) do
    armSecret(g, 1, id)
  end
  H.eq(#g.players[1].secrets, 5, "five armed")
  local pr = g:Printed("EX1_609")            -- Snipe, a sixth secret
  if pr then
    local ok = g:PlaySecret(1, ns.Entity.New(pr, 1))
    H.notOk(ok, "sixth secret rejected")
  end
  H.eq(#g.players[1].secrets, 5, "cap held")
  H.noEngineErrors(g)
end)

H.suite("secret: does not fire on its owner's own action", function(ns, H)
  local g = H.NewGame()
  -- Player 1 owns Explosive Trap and is the active player attacking. Secrets
  -- only respond to the OPPONENT, so it must not fire.
  H.SetActive(g, 1)
  armSecret(g, 1, "EX1_610")
  local attacker = H.Put(g, 1, "CS2_119")
  g:Attack(attacker, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "own secret did not fire")
  H.noEngineErrors(g)
end)

H.suite("secret: overkilled Crocolisk only copies when Mirror Entity is armed",function(ns,H)
  for _,secret in ipairs({false,true}) do
    local g=H.NewGame({class1="MAGE",class2="MAGE"})
    local old=H.Put(g,1,"CS2_120")
    H.SetActive(g,2); H.Mana(g,2,10)
    H.ok(ns.Actions.Run(g,2,{kind="PLAY_CARD",handIndex=H.Hand(g,2,"CS2_029"),targetId=old.instanceId}))
    H.eq(#g.players[1].board,0)
    if secret then armSecret(g,2,"EX1_294") end
    H.SetActive(g,1); H.Mana(g,1,10)
    H.ok(ns.Actions.Run(g,1,{kind="PLAY_CARD",handIndex=H.Hand(g,1,"CS2_120")}))
    H.eq(#g.players[1].board,1)
    H.eq(#g.players[2].board,secret and 1 or 0)
    if secret then H.eq(g.players[2].board[1].cardId,"CS2_120") end
    H.noEngineErrors(g)
  end
end)
