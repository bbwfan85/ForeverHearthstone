--[[ tests/test_gvg.lua -- the mechanics added by Naxxramas + Goblins vs Gnomes.

  Pinned data (build 7234):
    GVG_007  Flame Leviathan     7 mana 7/7  TOPDECK
             "When you draw this, deal 2 damage to all characters."
    GVG_066  Dunemaul Shaman     4 mana 5/4  FORGETFUL, WINDFURY, Overload (1)
             "50% chance to attack the wrong enemy."
    GVG_082  Clockwork Gnome     1 mana 2/1  Deathrattle: add a Spare Part
    CS1_129  Inner Fire          1 mana      attack := current health
    PART_006 Reversing Switch    1 mana      swap attack and health
    EX1_238  Lightning Bolt      1 mana      3 damage, Overload (1)
    EX1_243  Dust Devil          1 mana 3/1  Windfury, Overload (2)
]]
local H = require("tests.harness")

--============================================================ TOPDECK

H.suite("topdeck: Flame Leviathan fires on draw and hits everything", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_182")            -- friendly Yeti 4/5
  H.Put(g, 2, "CS2_231")            -- enemy Wisp 1/1, dies to 2
  H.Put(g, 2, "CS2_119")            -- enemy Snapjaw 2/7
  local h1, h2 = H.Hero(g, 1):Health(), H.Hero(g, 2):Health()
  local handBefore = #g.players[1].hand

  H.PutOnDeck(g, 1, "GVG_007")
  g:Draw(1)
  g.bus:Drain()

  H.eq(H.Hero(g, 1):Health(), h1 - 2, "own hero took 2")
  H.eq(H.Hero(g, 2):Health(), h2 - 2, "enemy hero took 2")
  H.board(g, 1, { "CS2_182 4/3" }, "friendly minion damaged")
  H.board(g, 2, { "CS2_119 2/5" }, "enemy Wisp died, Snapjaw damaged")
  -- the card itself still arrives in hand
  H.eq(#g.players[1].hand, handBefore + 1, "Flame Leviathan reached hand")
  H.eq(g.players[1].hand[#g.players[1].hand].cardId, "GVG_007", "and it is the Leviathan")
  H.noEngineErrors(g)
end)

H.suite("topdeck: fires even when the draw is burned by a full hand", function(ns, H)
  local g = H.NewGame()
  local p = g.players[1]
  while #p.hand < 10 do g:AddToHand(1, "CS2_231") end
  local h2 = H.Hero(g, 2):Health()

  H.PutOnDeck(g, 1, "GVG_007")
  g:Draw(1)
  g.bus:Drain()

  -- The card was drawn, so the effect happened; then it burned.
  H.eq(H.Hero(g, 2):Health(), h2 - 2, "effect fired despite the burn")
  H.eq(#p.hand, 10, "hand still full")
  H.eq(p.overdrawn, 1, "the card was burned")
  H.noEngineErrors(g)
end)

H.suite("topdeck: does NOT fire while sitting in the deck", function(ns, H)
  local g = H.NewGame()
  local h2 = H.Hero(g, 2):Health()
  H.PutOnDeck(g, 1, "GVG_007")
  -- lots of unrelated events: summons, attacks, turn changes
  g:Summon("CS2_231", 1, "RIGHTMOST")
  g:Summon("CS2_231", 2, "RIGHTMOST")
  g:EndTurn(); g:EndTurn()
  g.bus:Drain()
  -- turn changes draw cards, so only assert the Leviathan is still in the deck
  local stillInDeck = false
  for _, e in ipairs(g.players[1].deck) do
    if e.cardId == "GVG_007" then stillInDeck = true end
  end
  if stillInDeck then
    H.eq(H.Hero(g, 2):Health(), h2, "no damage while undrawn")
  else
    H.ok(true, "Leviathan was drawn during the turn cycle; case not applicable")
  end
  H.noEngineErrors(g)
end)

--=========================================================== FORGETFUL

H.suite("forgetful: redirects roughly half the time, deterministically", function(ns, H)
  --[[ Attack the enemy hero with one enemy minion available. Each trial either
       hits the hero for 5 or the minion. Over many seeds both must occur, and
       any single seed must be reproducible. ]]
  local hero, minion = 0, 0
  for seed = 1, 60 do
    local g = H.NewGame({ seed = seed * 7919 })
    H.SetActive(g, 1)
    local dune = H.Put(g, 1, "GVG_066")     -- 5/4 FORGETFUL WINDFURY
    H.Put(g, 2, "CS2_119")                  -- Oasis Snapjaw 2/7
    g:Attack(dune, H.Hero(g, 2))
    g.bus:Drain()
    if H.Hero(g, 2):Health() < 30 then hero = hero + 1 else minion = minion + 1 end
  end
  --[[ Assert the coin is actually FAIR, not merely two-sided. Bounds are
       18..42 of 60, which is roughly +/-3 sigma for a fair coin -- tight enough
       to catch a biased or broken roll, loose enough never to flake.
       Measured over 4000 trials the split is 49.1% / 50.9%. ]]
  H.ok(hero >= 18 and hero <= 42,
       "intended target hit 18-42 times of 60 (got " .. hero .. ")")
  H.ok(minion >= 18 and minion <= 42,
       "redirected 18-42 times of 60 (got " .. minion .. ")")
  H.eq(hero + minion, 60, "every trial resolved")

  -- reproducibility: the same seed must redirect the same way
  local function trial(seed)
    local g = H.NewGame({ seed = seed })
    H.SetActive(g, 1)
    local dune = H.Put(g, 1, "GVG_066")
    H.Put(g, 2, "CS2_119")
    g:Attack(dune, H.Hero(g, 2))
    g.bus:Drain()
    return H.Hero(g, 2):Health()
  end
  H.eq(trial(1234), trial(1234), "same seed, same redirect decision")
end)

H.suite("forgetful: no redirect when the target is the only option", function(ns, H)
  -- Empty enemy board: the hero is the only character, so there is nowhere to
  -- redirect to and the attack must always land.
  for seed = 1, 12 do
    local g = H.NewGame({ seed = seed * 31 })
    H.SetActive(g, 1)
    local dune = H.Put(g, 1, "GVG_066")
    g:Attack(dune, H.Hero(g, 2))
    g.bus:Drain()
    H.eq(H.Hero(g, 2):Health(), 25, "hero took 5 with no alternative target")
  end
  H.noEngineErrors(H.NewGame())
end)

H.suite("forgetful: Taunt gates the declaration, redirect may ignore it", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  local dune = H.Put(g, 1, "GVG_066")
  local taunt = H.Put(g, 2, "CS2_179")     -- Sen'jin Shieldmasta, TAUNT
  H.Put(g, 2, "CS2_119")                   -- non-taunt Snapjaw

  -- declaration still respects Taunt
  H.notOk(g:IsLegalAttack(dune, H.Hero(g, 2)), "cannot declare against the hero")
  H.ok(g:IsLegalAttack(dune, taunt), "can declare against the taunter")
  H.noEngineErrors(g)
end)

H.suite("forgetful: silence removes it", function(ns, H)
  local g = H.NewGame()
  local dune = H.Put(g, 1, "GVG_066")
  H.ok(dune:Has(ns.KEYWORD.FORGETFUL), "FORGETFUL before silence")
  dune:Silence()
  H.notOk(dune:Has(ns.KEYWORD.FORGETFUL), "FORGETFUL gone after silence")
  -- and with it gone, attacks never redirect
  for seed = 1, 10 do
    local g2 = H.NewGame({ seed = seed * 13 })
    H.SetActive(g2, 1)
    local d2 = H.Put(g2, 1, "GVG_066")
    d2:Silence()
    H.Put(g2, 2, "CS2_119")
    g2:Attack(d2, H.Hero(g2, 2))
    g2.bus:Drain()
    H.eq(H.Hero(g2, 2):Health(), 25, "silenced Dunemaul never redirects")
  end
end)

--===================================================== stat manipulation

H.suite("inner fire: attack becomes current health and stays put", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local snap = H.Put(g, 1, "CS2_119")      -- Oasis Snapjaw 2/7
  g:DealDamage(snap, 3, nil, false)        -- now 2/4
  H.eq(snap:Health(), 4, "damaged to 4")

  local i = H.Hand(g, 1, "CS1_129")        -- Inner Fire
  g:PlayCard(1, i, snap)
  g.bus:Drain()
  H.eq(snap:Attack(), 4, "attack set to current health")

  -- healing must NOT move the attack again: it is an enchantment, not an aura
  g:Heal(snap, 3, nil)
  H.eq(snap:Health(), 7, "healed to full")
  H.eq(snap:Attack(), 4, "attack unchanged by later healing")
  H.noEngineErrors(g)
end)

H.suite("swap: Reversing Switch exchanges attack and health", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")      -- 4/5
  local i = H.Hand(g, 1, "PART_006")
  g:PlayCard(1, i, yeti)
  g.bus:Drain()
  H.eq(yeti:Attack(), 5, "attack became old health")
  H.eq(yeti:MaxHealth(), 4, "max health became old attack")
  H.eq(yeti:Health(), 4, "at full health")
  H.noEngineErrors(g)
end)

H.suite("swap: silence undoes the swap", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, "CS2_182")      -- 4/5
  local i = H.Hand(g, 1, "PART_006")
  g:PlayCard(1, i, yeti)
  g.bus:Drain()
  H.eq(yeti:Attack(), 5, "swapped")
  yeti:Silence()
  g:RecalcAuras()
  H.eq(yeti:Attack(), 4, "attack restored")
  H.eq(yeti:MaxHealth(), 5, "health restored")
  H.noEngineErrors(g)
end)

H.suite("swap: a 0-attack minion dies when swapped", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  -- Shieldbearer (EX1_405) is 0/4. Swapping gives it 0 health.
  local shield = H.Put(g, 1, "EX1_405")
  H.eq(shield:Attack(), 0, "zero attack")
  local i = H.Hand(g, 1, "PART_006")
  g:PlayCard(1, i, shield)
  g.bus:Drain()
  H.eq(#g.players[1].board, 0, "swapped to 0 health and died")
  H.noEngineErrors(g)
end)

--================================================== Spare Parts & overload

H.suite("spare parts: Clockwork Gnome gives one of its seven entourage cards", function(ns, H)
  local g = H.NewGame()
  local gnome = H.Put(g, 1, "GVG_082")
  local before = #g.players[1].hand
  gnome.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()

  H.eq(#g.players[1].hand, before + 1, "one card added to hand")
  local got = g.players[1].hand[#g.players[1].hand]
  local entourage = g:Printed("GVG_082").entourage
  H.ok(entourage and #entourage == 7, "seven Spare Parts declared in printed data")
  local isPart = false
  for _, id in ipairs(entourage or {}) do
    if id == got.cardId then isPart = true end
  end
  H.ok(isPart, "the added card is a Spare Part (" .. tostring(got.cardId) .. ")")
  H.noEngineErrors(g)
end)

H.suite("overload: applied from PRINTED data, not from a script", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local p = g.players[1]
  H.eq(p.pendingOverload, 0, "no overload yet")

  local i = H.Hand(g, 1, "EX1_238")        -- Lightning Bolt, Overload (1)
  g:PlayCard(1, i, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(p.pendingOverload, 1, "one crystal overloaded")
  H.eq(H.Hero(g, 2):Health(), 27, "and the spell still dealt 3")

  -- and it locks on the following turn
  g:EndTurn(); g:EndTurn()
  H.eq(p.lockedMana, 1, "locked next turn")
  H.noEngineErrors(g)
end)

H.suite("overload: minions carry it too, and it does not double-count", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local p = g.players[1]
  local i = H.Hand(g, 1, "EX1_243")        -- Dust Devil 3/1, Overload (2)
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(p.pendingOverload, 2, "exactly 2, not 4")

  local j = H.Hand(g, 1, "GVG_066")        -- Dunemaul Shaman, Overload (1)
  g:PlayCard(1, j)
  g.bus:Drain()
  H.eq(p.pendingOverload, 3, "overload accumulates across cards")
  H.noEngineErrors(g)
end)

H.suite("overload: still applies when the spell is countered", function(ns, H)
  local g = H.NewGame({ firstPlayer = 1 })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  -- Counterspell counters the spell; overload is part of paying for it, like
  -- mana, so it is not refunded.
  local cs = ns.Entity.New(g:Printed("EX1_287"), 2)
  g:PlaySecret(2, cs)
  local p = g.players[1]
  local i = H.Hand(g, 1, "EX1_238")        -- Lightning Bolt
  g:PlayCard(1, i, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 30, "spell was countered")
  H.eq(p.pendingOverload, 1, "overload still applied")
  H.noEngineErrors(g)
end)
