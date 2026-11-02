--[[ tests/test_cards_classes_a.lua -- behaviour tests for the cards authored in
     tools/effects/cards_classes_a.csv.

  One suite per card. See tests/test_chooseone.lua for the house style: name the
  fixture cards and their printed stats in a comment, assert the board with
  H.board, and finish with H.noEngineErrors so an unknown op or selector cannot
  pass silently.

  Fixtures used below, all read off the pin rather than remembered:
    CS2_119  Oasis Snapjaw        4 mana 2/7 BEAST, vanilla
    CS2_182  Chillwind Yeti       4 mana 4/5 vanilla
    CS2_231  Wisp                 0 mana 1/1 vanilla
    CS2_101t Silver Hand Recruit  1 mana 1/1 token
    EX1_001  Lightwarden          1 mana 1/2  "whenever a character is healed,
                                               gain +2 Attack"
    EX1_335  Lightspawn           4 mana 0/5
    GVG_060  Quartermaster        5 mana 2/5
]]
local H = require("tests.harness")

--============================================================ CS2_031 Ice Lance

H.suite("classes_a: Ice Lance -- freezes, or deals 4 to an already-Frozen target",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local snap = H.Put(g, 2, "CS2_119")            -- Oasis Snapjaw 2/7

  -- First cast: Freeze, no damage at all.
  local i1 = H.Hand(g, 1, "CS2_031")
  H.ok(g:PlayCard(1, i1, snap), "first Ice Lance was accepted")
  g.bus:Drain()
  H.ok(snap.frozen, "an unfrozen target is Frozen")
  H.eq(snap:Health(), 7, "and takes no damage")

  -- Second cast on the now-Frozen target: 4 damage INSTEAD of the freeze.
  local i2 = H.Hand(g, 1, "CS2_031")
  H.ok(g:PlayCard(1, i2, snap), "second Ice Lance was accepted")
  g.bus:Drain()
  H.eq(snap:Health(), 3, "a Frozen target takes 4 damage")
  H.ok(snap.frozen, "it is still Frozen -- the damage replaced the freeze, "
                 .. "it did not thaw it")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Ice Lance -- the damage branch is spell damage",
function(ns, H)
  -- $4 in the printed text: Spell Damage +N must raise it. Kobold Geomancer
  -- (CS2_142) is +1 spell damage, verified against the pin.
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_142")                         -- Kobold Geomancer, Spell Damage +1
  local snap = H.Put(g, 2, "CS2_119")
  snap.frozen = true

  local idx = H.Hand(g, 1, "CS2_031")
  g:PlayCard(1, idx, snap)
  g.bus:Drain()
  H.eq(snap:Health(), 2, "4 + 1 spell damage")
  H.noEngineErrors(g)
end)

--============================================================ EX1_335 Lightspawn

H.suite("classes_a: Lightspawn -- Attack tracks Health continuously",
function(ns, H)
  local g = H.NewGame()
  local ls = H.Put(g, 1, "EX1_335")              -- printed 0/5
  H.board(g, 1, { "EX1_335 5/5" }, "a fresh Lightspawn reads its health as attack")

  -- Damage moves the attack down with it. This is the part InnerFire cannot do:
  -- a one-shot enchantment would have pinned the attack at 5.
  g:DealDamage(ls, 2, nil, false)
  g:ProcessDeaths()
  -- H.board prints CURRENT health, so a 5-max Lightspawn on 3 reads "3/3".
  H.board(g, 1, { "EX1_335 3/3" }, "damaged to 3 health is a 3-attack minion")

  -- ...and healing moves it back up.
  g:Heal(ls, 2, nil)
  g:RecalcAuras()
  H.board(g, 1, { "EX1_335 5/5" }, "healed back to full")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Lightspawn -- a health buff raises Attack too, Silence drops it",
function(ns, H)
  local g = H.NewGame()
  local ls = H.Put(g, 1, "EX1_335")
  ls:AddEnchantment(0, 2)                        -- e.g. Power Word: Shield
  g:RecalcAuras()
  H.board(g, 1, { "EX1_335 7/7" }, "+0/+2 makes it a 7/7")

  -- Silence removes the self-aura source, so the minion falls back to its
  -- printed 0 Attack (and loses the health enchantment, as Silence always does).
  ls:Silence()
  g:RecalcAuras()
  H.board(g, 1, { "EX1_335 0/5" }, "a silenced Lightspawn is a printed 0/5")
  H.noEngineErrors(g)
end)

--========================================================= EX1_334 Shadow Madness

H.suite("classes_a: Shadow Madness -- steals a minion, lets it attack, gives it back",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local snap = H.Put(g, 2, "CS2_119")            -- Oasis Snapjaw 2/7, 2 attack
  local idx  = H.Hand(g, 1, "EX1_334")
  H.ok(g:PlayCard(1, idx, snap), "Shadow Madness was accepted on a 2-Attack minion")
  g.bus:Drain()

  H.eq(snap.controller, 1, "the minion changed sides")
  H.eq(#g.players[1].board, 1, "it is on the caster's board")
  H.eq(#g.players[2].board, 0, "and off its owner's")

  -- The whole point of the card: it can swing the turn you take it, even though
  -- ChangeController marks it summoning-sick.
  H.ok(g:CanAttack(snap), "the stolen minion can attack immediately")
  g:Attack(snap, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 28, "it hit its own hero for 2")

  -- End of turn hands it back, and the temporary Charge expires with it.
  g:EndTurn()
  H.eq(snap.controller, 2, "returned to its owner at end of turn")
  H.eq(#g.players[2].board, 1, "back on the owner's board")
  H.eq(#g.players[1].board, 0, "and off the caster's")
  H.notOk(snap:Has(ns.KEYWORD.CHARGE), "the loaned Charge expired")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Shadow Madness -- a minion that dies mid-turn is not handed back",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local wisp = H.Put(g, 2, "CS2_231")            -- Wisp 1/1
  local idx  = H.Hand(g, 1, "EX1_334")
  g:PlayCard(1, idx, wisp)
  g.bus:Drain()
  H.eq(wisp.controller, 1, "stolen")

  g:DealDamage(wisp, 5, nil, false)
  g:ProcessDeaths()
  g.bus:Drain()
  H.eq(wisp.zone, ns.ZONE.GRAVEYARD, "it died while borrowed")

  -- The scheduled hand-back must be a no-op rather than an engine error.
  g:EndTurn()
  H.eq(#g.players[2].board, 0, "nothing came back")
  H.noEngineErrors(g)
end)

--======================================================= GVG_012 Light of the Naaru

H.suite("classes_a: Light of the Naaru -- Lightwarden only when 3 was not enough",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local snap = H.Put(g, 1, "CS2_119")            -- Oasis Snapjaw 2/7
  g:DealDamage(snap, 5, nil, false)              -- down to 2 health
  g:ProcessDeaths()

  local idx = H.Hand(g, 1, "GVG_012")
  H.ok(g:PlayCard(1, idx, snap), "cast on the damaged Snapjaw")
  g.bus:Drain()

  H.eq(snap:Health(), 5, "restored 3 Health")
  -- 5 damage minus 3 healed is 2 still on it, so the target is still damaged.
  H.board(g, 1, { "CS2_119 2/5", "EX1_001 1/2" },
          "a still-damaged target summons a Lightwarden on the caster's side")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Light of the Naaru -- a fully healed target summons nothing",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local snap = H.Put(g, 1, "CS2_119")
  g:DealDamage(snap, 2, nil, false)              -- only 2 damage: 3 clears it
  g:ProcessDeaths()

  local idx = H.Hand(g, 1, "GVG_012")
  g:PlayCard(1, idx, snap)
  g.bus:Drain()

  H.eq(snap:Health(), 7, "back to full")
  H.board(g, 1, { "CS2_119 2/7" }, "no Lightwarden")
  H.noEngineErrors(g)
end)

--========================================================= GVG_060 Quartermaster

H.suite("classes_a: Quartermaster -- +2/+2 to Silver Hand Recruits only",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_101t")                        -- Silver Hand Recruit 1/1
  H.Put(g, 1, "CS2_231")                         -- Wisp 1/1, also a 1/1 but not a Recruit
  H.Put(g, 1, "CS2_101t")
  H.Put(g, 2, "CS2_101t")                        -- the opponent's Recruit

  local idx = H.Hand(g, 1, "GVG_060")
  H.ok(g:PlayCard(1, idx, nil), "Quartermaster was played")
  g.bus:Drain()

  H.board(g, 1, { "CS2_101t 3/3", "CS2_231 1/1", "CS2_101t 3/3", "GVG_060 2/5" },
          "both friendly Recruits grew, the Wisp and the Quartermaster did not")
  H.board(g, 2, { "CS2_101t 1/1" }, "the enemy Recruit is untouched")
  H.noEngineErrors(g)
end)

--============================================== EX1_335 Lightspawn, in hand

H.suite("classes_a: Lightspawn -- reads its printed 0/5 while still in hand",
function(ns, H)
  --[[ Regression. A hand card may host a self-aura -- that is how the Giants
       discount themselves -- but only over its COST. When the stat layers were
       in scope too, Lightspawn's "Attack equals Health" applied in hand and the
       card read 5/5 instead of the printed 0/5. ]]
  local g = H.NewGame()
  local _, e = H.Hand(g, 1, "EX1_335")
  g:RecalcAuras()
  H.eq(e:Attack(), 0, "printed Attack in hand, not the health-tracking value")
  H.eq(e:Health(), 5, "printed Health in hand")

  -- ...and it still tracks health the moment it reaches the board.
  H.Put(g, 1, "EX1_335")
  H.board(g, 1, { "EX1_335 5/5" }, "on board the self-aura applies as before")
  H.noEngineErrors(g)
end)

--============================================================ EX1_339 Thoughtsteal

H.suite("classes_a: Thoughtsteal -- copies 2 cards, leaving the enemy deck intact",
function(ns, H)
  --[[ The two decks must be DISTINGUISHABLE or this suite is vacuous: with the
       harness default both are 30 Wisps, and "a card from the opponent's deck"
       is then indistinguishable from one of your own. So the opponent's deck is
       all Chillwind Yeti and ours stays all Wisp. ]]
  local yetis = {}
  for i = 1, 30 do yetis[i] = "CS2_182" end
  local g = H.NewGame({ deck2 = yetis })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)

  local deckBefore = #g.players[2].deck
  local handBefore = #g.players[1].hand
  for _, e in ipairs(g.players[1].deck) do
    H.eq(e.cardId, "CS2_231", "our own deck is pure Wisp, so a Wisp copy would be ours")
    break
  end

  local idx = H.Hand(g, 1, "EX1_339")
  H.ok(g:PlayCard(1, idx, nil), "Thoughtsteal was played")
  g.bus:Drain()

  -- handBefore was read BEFORE the spell was put into hand, and the spell
  -- leaves hand again when it is cast, so the net is exactly the 2 copies.
  H.eq(#g.players[1].hand, handBefore + 2, "two copies arrived")
  H.eq(#g.players[2].deck, deckBefore, "COPIES -- the opponent's deck is untouched")

  local hand = g.players[1].hand
  H.eq(hand[#hand].cardId,     "CS2_182", "the copy came from the ENEMY deck, not ours")
  H.eq(hand[#hand - 1].cardId, "CS2_182", "and so did the one before it")
  H.noEngineErrors(g)
end)

--========================================================= GVG_005 Echo of Medivh

H.suite("classes_a: Echo of Medivh -- one PRINTED copy of each friendly minion",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)

  local yeti = H.Put(g, 1, "CS2_182")            -- Chillwind Yeti 4/5
  H.Put(g, 1, "CS2_231")                         -- Wisp 1/1
  H.Put(g, 2, "CS2_182")                         -- the opponent's Yeti: not echoed
  yeti:AddEnchantment(2, 2)                      -- a buffed 6/7
  g:RecalcAuras()
  H.board(g, 1, { "CS2_182 6/7", "CS2_231 1/1" }, "the Yeti really is buffed")

  local handBefore = #g.players[1].hand
  local idx = H.Hand(g, 1, "GVG_005")
  g:PlayCard(1, idx, nil)
  g.bus:Drain()

  -- as in Thoughtsteal: handBefore predates the spell entering hand, and the
  -- spell leaves again on cast, so the net is the 2 echoes
  H.eq(#g.players[1].hand, handBefore + 2, "one echo per friendly minion")
  local copies = {}
  for _, e in ipairs(g.players[1].hand) do
    if e.cardId == "CS2_182" or e.cardId == "CS2_231" then copies[e.cardId] = e end
  end
  H.ok(copies["CS2_182"], "the Yeti was echoed")
  H.ok(copies["CS2_231"], "the Wisp was echoed")
  if copies["CS2_182"] then
    H.eq(copies["CS2_182"]:Attack(), 4, "the copy is the PRINTED 4/5, not the buffed 6/7")
    H.eq(copies["CS2_182"]:Health(), 5, "printed health")
  end
  H.noEngineErrors(g)
end)

--============================================================= FP1_018 Duplicate

H.suite("classes_a: Duplicate -- two copies of the first friendly minion to die",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 2)                              -- secrets answer the OPPONENT's turn
  local pr = g:Printed("FP1_018")
  H.ok(g:PlaySecret(1, ns.Entity.New(pr, 1)), "Duplicate armed")

  local wisp   = H.Put(g, 1, "CS2_231")          -- Wisp 1/1, about to die
  local killer = H.Put(g, 2, "CS2_182")          -- Chillwind Yeti 4/5
  local handBefore = #g.players[1].hand

  g:Attack(killer, wisp)
  g.bus:Drain()

  H.eq(wisp.zone, ns.ZONE.GRAVEYARD, "the Wisp died")
  H.eq(#g.players[1].hand, handBefore + 2, "two copies went to the owner's hand")
  local hand = g.players[1].hand
  H.eq(hand[#hand].cardId, "CS2_231", "and they are Wisps")
  H.eq(hand[#hand - 1].cardId, "CS2_231", "both of them")
  H.eq(#g.players[1].secrets, 0, "the secret was consumed")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Duplicate -- an ENEMY minion dying does not arm it",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 2)
  local pr = g:Printed("FP1_018")
  g:PlaySecret(1, ns.Entity.New(pr, 1))

  -- The opponent's own minion dies on their turn. PayloadIsMine must reject it.
  local theirs = H.Put(g, 2, "CS2_231")
  local handBefore = #g.players[1].hand
  g:DealDamage(theirs, 5, nil, false)
  g:ProcessDeaths()
  g.bus:Drain()

  H.eq(#g.players[1].secrets, 1, "still armed")
  H.eq(#g.players[1].hand, handBefore, "nothing was copied")
  H.noEngineErrors(g)
end)

--============================================================= FP1_011 Webspinner

H.suite("classes_a: Webspinner -- Deathrattle adds a random Beast to hand",
function(ns, H)
  local g = H.NewGame()
  local spider = H.Put(g, 1, "FP1_011")          -- Webspinner 1/1 BEAST
  local handBefore = #g.players[1].hand

  g:DealDamage(spider, 5, nil, false)
  g:ProcessDeaths()
  g.bus:Drain()

  H.eq(#g.players[1].hand, handBefore + 1, "one card arrived")
  local hand = g.players[1].hand
  local got = g:Printed(hand[#hand].cardId)
  H.ok(got, "the generated id is a real printed card")
  if got then
    -- Assert the PROPERTY, not the identity: the roll is seeded, but what the
    -- card promises is "a Beast" and the pool would shift under a re-pin.
    H.eq(got.race, "BEAST", "it is a Beast")
    H.ok(got.collectible, "generation never produces tokens")
  end
  H.noEngineErrors(g)
end)

--========================================================= GVG_003 Unstable Portal

H.suite("classes_a: Unstable Portal -- a random minion that costs (3) less",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)

  local idx = H.Hand(g, 1, "GVG_003")
  g:PlayCard(1, idx, nil)
  g.bus:Drain()

  local hand = g.players[1].hand
  local made = hand[#hand]
  local pr   = g:Printed(made.cardId)
  H.ok(pr, "the generated id is a real printed card")
  if pr then
    H.eq(pr.type, "MINION", "it is a minion")
    H.ok(pr.collectible, "and a collectible one, never a token")
    local want = (pr.cost or 0) - 3
    if want < 0 then want = 0 end
    H.eq(made:Cost(), want, "it costs (3) less, floored at 0")

    -- The discount rides on THAT copy: a second copy of the same card is full
    -- price, which is what makes it an enchantment rather than a cost modifier.
    local _, plain = H.Hand(g, 1, made.cardId)
    H.eq(plain:Cost(), pr.cost or 0, "a second copy of the same card is full price")
  end
  H.noEngineErrors(g)
end)

--==================================================== EX1_363 Blessing of Wisdom

H.suite("classes_a: Blessing of Wisdom -- only the blessed minion's attacks draw",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local blessed = H.Put(g, 1, "CS2_119")         -- Oasis Snapjaw 2/7
  local other   = H.Put(g, 1, "CS2_182")         -- Chillwind Yeti 4/5

  local idx = H.Hand(g, 1, "EX1_363")
  H.ok(g:PlayCard(1, idx, blessed), "Blessing of Wisdom was cast on the Snapjaw")
  g.bus:Drain()
  local handAfterCast = #g.players[1].hand

  --[[ THE gate that was missing until PayloadAttackerIsSelf existed: the
       trigger hangs off one minion but fires on the ATTACK_DECLARED of EVERY
       attack on the board, so an unguarded Blessing drew on the Yeti's swing
       too. ]]
  g:Attack(other, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(#g.players[1].hand, handAfterCast, "an UNblessed minion attacking draws nothing")

  g:Attack(blessed, H.Hero(g, 2))
  g.bus:Drain()
  H.eq(#g.players[1].hand, handAfterCast + 1, "the blessed minion's attack drew a card")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Blessing of Wisdom -- on an enemy minion, the CASTER draws",
function(ns, H)
  --[[ This suite pinned the known-wrong behaviour until it was fixed
       (2026-09-25, CasterTrigger): now it asserts the right one.

       The pin carries two enchantments for this card -- EX1_363e "the player
       who blessed it draws a card" and EX1_363e2 "the enemy player draws a
       card" (read from the enchanted minion's own side) -- and both mean the
       CASTER draws. Bus:Raise built a trigger's ctx from the HOST entity's
       controller, so Draw(1) went to whoever owned the minion; a trigger
       granted with CasterTrigger now carries the caster as its owner. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local theirs = H.Put(g, 2, "CS2_119")          -- the OPPONENT's Snapjaw

  local idx = H.Hand(g, 1, "EX1_363")
  H.ok(g:PlayCard(1, idx, theirs), "it may legally be cast on an enemy minion")
  g.bus:Drain()

  local mine  = #g.players[1].hand
  local yours = #g.players[2].hand
  H.SetActive(g, 2)
  g:Attack(theirs, H.Hero(g, 1))
  g.bus:Drain()

  H.eq(#g.players[1].hand, mine + 1, "the caster draws")
  H.eq(#g.players[2].hand, yours, "the minion's controller does not")
  H.noEngineErrors(g)
end)

--========================================================== EX1_132 Eye for an Eye

H.suite("classes_a: Eye for an Eye -- reflects exactly the damage your hero took",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 2)                              -- secrets answer the OPPONENT
  local pr = g:Printed("EX1_132")
  H.ok(g:PlaySecret(1, ns.Entity.New(pr, 1)), "Eye for an Eye armed")

  local yeti = H.Put(g, 2, "CS2_182")            -- Chillwind Yeti, 4 attack
  g:Attack(yeti, H.Hero(g, 1))
  g.bus:Drain()

  H.eq(H.Hero(g, 1):Health(), 26, "our hero took the 4")
  H.eq(H.Hero(g, 2):Health(), 26, "and the enemy hero took the same 4 back")
  H.eq(#g.players[1].secrets, 0, "the secret was consumed")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Eye for an Eye -- the opponent damaging their OWN hero does not arm it",
function(ns, H)
  --[[ PayloadTargetIsHero would fire here, because it tests the shape and not
       the ownership -- and a secret DOES fire on the opponent's turn, so their
       Life Tap would have reflected onto themselves. ]]
  local g = H.NewGame()
  H.SetActive(g, 2)
  local pr = g:Printed("EX1_132")
  g:PlaySecret(1, ns.Entity.New(pr, 1))

  g:DealDamage(H.Hero(g, 2), 3, nil, false)
  g:ProcessDeaths()
  g.bus:Drain()

  H.eq(H.Hero(g, 2):Health(), 27, "they took their own 3")
  H.eq(H.Hero(g, 1):Health(), 30, "nothing came back at us")
  H.eq(#g.players[1].secrets, 1, "still armed")
  H.noEngineErrors(g)
end)

--============================================================= EX1_365 Holy Wrath

H.suite("classes_a: Holy Wrath -- draws a card and deals that card's cost",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  -- Stack a KNOWN card on top, or the damage is whatever the shuffle produced.
  -- CS2_182 Chillwind Yeti costs 4, read from the pin, not typed as a stat.
  H.PutOnDeck(g, 1, "CS2_182")
  local cost = g:Printed("CS2_182").cost

  local snap = H.Put(g, 2, "CS2_119")            -- Oasis Snapjaw 2/7
  local handBefore = #g.players[1].hand
  local idx = H.Hand(g, 1, "EX1_365")
  H.ok(g:PlayCard(1, idx, snap), "Holy Wrath was cast")
  g.bus:Drain()

  H.eq(#g.players[1].hand, handBefore + 1, "the drawn card is in hand (the spell left)")
  H.eq(snap:Health(), 7 - cost, "damage equal to the drawn card's cost")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Holy Wrath -- an empty deck draws nothing and deals nothing",
function(ns, H)
  --[[ lastDrawn is nil after a fatigue draw, so costOf() must resolve to 0
       rather than erroring or falling back to some other card. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  for i = #g.players[1].deck, 1, -1 do g.players[1].deck[i] = nil end

  local snap = H.Put(g, 2, "CS2_119")
  local idx = H.Hand(g, 1, "EX1_365")
  g:PlayCard(1, idx, snap)
  g.bus:Drain()

  H.eq(snap:Health(), 7, "no card, no damage")
  H.eq(H.Hero(g, 1):Health(), 29, "we took 1 fatigue for the failed draw")
  H.noEngineErrors(g)
end)

--=========================================================== EX1_349 Divine Favor

H.suite("classes_a: Divine Favor -- draws up to the opponent's hand size",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  for _ = 1, 3 do H.Hand(g, 2, "CS2_231") end    -- give them a fatter hand

  local theirs = #g.players[2].hand
  local idx = H.Hand(g, 1, "EX1_349")
  H.ok(g:PlayCard(1, idx, nil), "Divine Favor was cast")
  g.bus:Drain()

  H.eq(#g.players[1].hand, theirs, "our hand now matches theirs exactly")
  H.eq(#g.players[2].hand, theirs, "theirs did not move")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Divine Favor -- a bigger hand than theirs draws nothing",
function(ns, H)
  -- sub() clamps at zero; without that clamp a negative count would either draw
  -- nothing by accident or loop the wrong way.
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  for _ = 1, 4 do H.Hand(g, 1, "CS2_231") end

  local idx = H.Hand(g, 1, "EX1_349")
  local mineBefore = #g.players[1].hand - 1      -- excluding the spell itself
  local deckBefore = #g.players[1].deck
  g:PlayCard(1, idx, nil)
  g.bus:Drain()

  H.eq(#g.players[1].hand, mineBefore, "no cards were drawn")
  H.eq(#g.players[1].deck, deckBefore, "the deck was not touched")
  H.noEngineErrors(g)
end)

--============================================================= GVG_026 Feign Death

H.suite("classes_a: Feign Death -- fires friendly Deathrattles without killing",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  -- Webspinner's Deathrattle adds a Beast, which is easy to count.
  H.Put(g, 1, "FP1_011")
  H.Put(g, 1, "FP1_011")
  H.Put(g, 2, "FP1_011")                         -- theirs must NOT fire

  local handBefore  = #g.players[1].hand
  local theirsBefore = #g.players[2].hand
  local idx = H.Hand(g, 1, "GVG_026")
  H.ok(g:PlayCard(1, idx, nil), "Feign Death was cast")
  g.bus:Drain()

  H.eq(#g.players[1].hand, handBefore + 2, "both friendly Deathrattles fired")
  H.eq(#g.players[2].hand, theirsBefore, "the enemy Webspinner did not")
  H.board(g, 1, { "FP1_011 1/1", "FP1_011 1/1" }, "and both are still alive")
  H.noEngineErrors(g)
end)

--====================================================== EX1_591 Auchenai Soulpriest

H.suite("classes_a: Auchenai Soulpriest -- your heals deal damage instead",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  H.Put(g, 1, "EX1_591")                         -- Auchenai Soulpriest 3/5
  local snap = H.Put(g, 1, "CS2_119")            -- Oasis Snapjaw 2/7, undamaged

  -- Light of the Naaru restores 3; with Auchenai out it deals 3 instead, and
  -- the target is then damaged, so the Lightwarden rider fires.
  local idx = H.Hand(g, 1, "GVG_012")
  g:PlayCard(1, idx, snap)
  g.bus:Drain()

  H.eq(snap:Health(), 4, "the heal dealt 3 damage instead of restoring")
  H.ok(snap:IsDamaged(), "so the target ends up damaged")
  local warden = false
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "EX1_001" then warden = true end
  end
  H.ok(warden, "and Light of the Naaru's still-damaged rider summoned a Lightwarden")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Auchenai Soulpriest -- routed through DealDamage, so a Divine Shield eats it",
function(ns, H)
  --[[ The reason this is a property read by Game:Heal rather than a health edit:
       heal-as-damage has to be REAL damage, so Divine Shield, Immune, armor and
       the death queue all behave. EX1_008 Argent Squire is a 1/1 Divine Shield. ]]
  local g = H.NewGame()
  local auchenai = H.Put(g, 1, "EX1_591")
  local squire   = H.Put(g, 1, "EX1_008")        -- Argent Squire 1/1, Divine Shield
  H.ok(squire.divineShieldUp, "the Squire starts shielded")

  g:Heal(squire, 6, auchenai)
  g:ProcessDeaths()
  g.bus:Drain()

  H.notOk(squire.divineShieldUp, "the shield absorbed the heal-as-damage and popped")
  H.eq(squire:Health(), 1, "and the Squire survived untouched")

  -- Silencing Auchenai turns the property off: HealsDealDamage skips a silenced
  -- source, so healing goes back to healing.
  g:DealDamage(squire, 0, nil, false)
  auchenai:Silence()
  g:RecalcAuras()
  local snap = H.Put(g, 1, "CS2_119")
  g:DealDamage(snap, 3, nil, false)
  g:ProcessDeaths()
  g:Heal(snap, 3, auchenai)
  H.eq(snap:Health(), 7, "with Auchenai silenced the heal heals again")
  H.noEngineErrors(g)
end)

--======================================================== EX1_130 Noble Sacrifice

H.suite("classes_a: Noble Sacrifice -- a 2/1 Defender becomes the new target",
function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 2)
  local pr = g:Printed("EX1_130")
  H.ok(g:PlaySecret(1, ns.Entity.New(pr, 1)), "Noble Sacrifice armed")

  local yeti = H.Put(g, 2, "CS2_182")            -- Chillwind Yeti 4/5
  g:Attack(yeti, H.Hero(g, 1))
  g.bus:Drain()

  H.eq(H.Hero(g, 1):Health(), 30, "the hero took nothing -- the attack moved")
  H.eq(yeti:Health(), 3, "the 2/1 Defender hit back for 2")
  H.eq(#g.players[1].board, 0, "and the Defender died to the 4 it absorbed")
  H.eq(#g.players[1].secrets, 0, "the secret was consumed")
  H.noEngineErrors(g)
end)

H.suite("classes_a: Noble Sacrifice -- fires on an attack against a MINION too",
function(ns, H)
  -- The printed text is "when an enemy attacks", not "attacks your hero" --
  -- Misdirection is the hero-only one.
  local g = H.NewGame()
  H.SetActive(g, 2)
  local pr = g:Printed("EX1_130")
  g:PlaySecret(1, ns.Entity.New(pr, 1))

  local wisp = H.Put(g, 1, "CS2_231")            -- Wisp 1/1, the original target
  local yeti = H.Put(g, 2, "CS2_182")
  g:Attack(yeti, wisp)
  g.bus:Drain()

  H.eq(wisp.zone, ns.ZONE.PLAY, "the Wisp was spared")
  H.eq(wisp:Health(), 1, "and untouched")
  H.eq(yeti:Health(), 3, "the Defender still traded into the Yeti")
  H.noEngineErrors(g)
end)
