--[[ tests/test_review.lua -- the rules fixed by the release review (docs/29).

  Each of these was a place the engine played a different game from
  Hearthstone. One suite per rule, named for the rule rather than the card.

  Fixtures, verified against the pin:
    CS2_222  Stormwind Champion   CS2_142  Kobold Geomancer (Spell Damage +1)
    EX1_277  Arcane Missiles      EX1_350  Prophet Velen
    EX1_341  Lightwell            EX1_591  Auchenai Soulpriest
    FP1_027  Stoneskin Gargoyle   EX1_611  Freezing Trap
    EX1_567  Doomhammer           EX1_556  Harvest Golem
    CS2_063  Corruption           EX1_169  Innervate
    CS2_013  Wild Growth          NEW1_026 Violet Teacher
    CS2_011  Savage Roar          CS2_097  Truesilver Champion
    EX1_561  Alexstrasza          EX1_048  Spellbreaker
    EX1_287  Counterspell         EX1_289  Ice Barrier
    CS2_182  Chillwind Yeti 4/5   CS2_231  Wisp 1/1
]]
local H = require("tests.harness")

local function kill(g, e)
  e.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
end

H.suite("review: losing an aura's Health never kills", function(ns, H)
  local g = H.NewGame()
  local champ = H.Put(g, 1, "CS2_222")
  local wisp = H.Put(g, 1, "CS2_231")
  H.eq(wisp:Health(), 2, "the Champion makes the Wisp 2/2")
  g:DealDamage(wisp, 1, nil, false); g.bus:Drain()
  H.eq(wisp:Health(), 1, "one damage")
  kill(g, champ)
  H.eq(wisp.zone, ns.ZONE.PLAY, "the Wisp lives when the Champion dies")
  H.eq(wisp:Health(), 1, "at 1 Health, its full Health again")
  H.noEngineErrors(g)
end)

H.suite("review: Spell Damage never boosts a hero power", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_142")
  local foe = H.Hero(g, 2)
  H.ok(g:UseHeroPower(1, foe)); g.bus:Drain()
  H.eq(foe:Health(), 29, "Fireblast with a Kobold Geomancer out deals 1")
  H.noEngineErrors(g)
end)

H.suite("review: Spell Damage adds missiles", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_142")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_277")))); g.bus:Drain()
  H.eq(H.Hero(g, 2):Health(), 26, "Arcane Missiles with +1 is four missiles at an empty board")
  H.noEngineErrors(g)
end)

H.suite("review: Velen doubles healing from spells and hero powers only", function(ns, H)
  local g = H.NewGame({ class1 = "PRIEST" })
  H.Put(g, 1, "EX1_350")
  local hero = H.Hero(g, 1)
  hero.damage = 20
  local well = H.Put(g, 1, "EX1_341")
  g:Heal(hero, 3, well)
  H.eq(hero.damage, 17, "a Lightwell heals 3, not 6")
  local spell = ns.Entity.New(g:Printed("CS2_011"), 1, g.ids)   -- any spell as a source
  g:Heal(hero, 2, spell)
  H.eq(hero.damage, 13, "a spell's heal is doubled")
  H.noEngineErrors(g)
end)

H.suite("review: Auchenai turns a full heal into the MISSING Health", function(ns, H)
  local g = H.NewGame({ class1 = "PRIEST" })
  H.Put(g, 1, "EX1_591")
  local garg = H.Put(g, 1, "FP1_027")
  g:Heal(garg, 99, garg); g.bus:Drain()
  H.eq(garg.damage, 0, "an undamaged Gargoyle hurts itself for nothing")
  garg.damage = 1
  g:Heal(garg, 99, garg); g.bus:Drain()
  H.eq(garg.damage, 2, "a Gargoyle missing 1 takes 1")
  H.eq(garg.zone, ns.ZONE.PLAY, "and lives")
  H.noEngineErrors(g)
end)

H.suite("review: Freezing Trap's minion costs (2) more", function(ns, H)
  local g = H.NewGame({ class2 = "HUNTER" })
  g:PlaySecret(2, ns.Entity.New(g:Printed("EX1_611"), 2, g.ids))
  H.SetActive(g, 1)
  local yeti = H.Put(g, 1, "CS2_182")
  g:Attack(yeti, H.Hero(g, 2)); g.bus:Drain()
  H.eq(yeti.zone, ns.ZONE.HAND, "the Yeti went back to hand")
  H.eq(g:CardCost(yeti, 1), 6, "at 4 + 2")
  H.noEngineErrors(g)
end)

H.suite("review: a hero swings with its weapon's Windfury", function(ns, H)
  local g = H.NewGame({ class1 = "SHAMAN" })
  H.SetActive(g, 1)
  g:EquipWeapon(1, "EX1_567")
  H.eq(g:AttacksAllowed(H.Hero(g, 1)), 2, "Doomhammer attacks twice")
  H.noEngineErrors(g)
end)

H.suite("review: a deathrattle summons into the slot the minion died in", function(ns, H)
  local g = H.NewGame()
  H.Put(g, 1, "CS2_231"); local golem = H.Put(g, 1, "EX1_556"); H.Put(g, 1, "CS2_231")
  kill(g, golem)
  local b = g.players[1].board
  H.eq(#b, 3, "the Damaged Golem arrived")
  H.ok(b[2].cardId ~= "CS2_231", "in the middle, where the Golem stood")
  H.eq(b[3].cardId, "CS2_231", "not at the far right")
  H.noEngineErrors(g)
end)

H.suite("review: simultaneous deaths queue every deathrattle before any resolves", function(ns, H)
  local g = H.NewGame()
  local a = H.Put(g, 1, "EX1_556")
  local b = H.Put(g, 1, "EX1_556")
  local seen = {}
  local raise = g.bus.Raise
  g.bus.Raise = function(bus, event, payload)
    if event == ns.EVENT.MINION_DIED then seen[#seen + 1] = #g.players[1].board end
    return raise(bus, event, payload)
  end
  a.pendingDestroy, b.pendingDestroy = true, true
  g:ProcessDeaths(); g.bus:Drain()
  g.bus.Raise = raise
  H.eq(#seen, 2, "both deaths announced")
  H.eq(seen[2], 0, "the second before the first one's Damaged Golem arrived")
  H.eq(#g.players[1].board, 2, "then both deathrattles resolved")
  H.noEngineErrors(g)
end)

H.suite("review: Corruption ends if its target is silenced or leaves play", function(ns, H)
  local g = H.NewGame({ class1 = "WARLOCK" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 2, "CS2_182")
  H.ok(g:PlayCard(1, H.Hand(g, 1, "CS2_063"), yeti)); g.bus:Drain()
  yeti:Silence()
  g:EndTurn(); g:EndTurn(); g.bus:Drain()
  H.eq(yeti.zone, ns.ZONE.PLAY, "a silenced target is spared")

  local g2 = H.NewGame({ class1 = "WARLOCK" })
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  local y2 = H.Put(g2, 2, "CS2_182")
  H.ok(g2:PlayCard(1, H.Hand(g2, 1, "CS2_063"), y2)); g2.bus:Drain()
  g2:MoveToHand(y2)
  g2:EndTurn(); g2:EndTurn(); g2.bus:Drain()
  H.eq(y2.zone, ns.ZONE.HAND, "a bounced target is left alone in hand")
  H.notOk(y2.pendingDestroy, "and not marked to die when replayed")
  H.noEngineErrors(g); H.noEngineErrors(g2)
end)

H.suite("review: never more than 10 mana to spend", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_169")))); g.bus:Drain()
  H.eq(g:AvailableMana(1), 10, "Innervate at 10 mana gives nothing")
  H.noEngineErrors(g)
end)

H.suite("review: Wild Growth at 10 crystals gives Excess Mana", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "CS2_013")
  local before = #g.players[1].hand - 1
  H.ok(g:PlayCard(1, i)); g.bus:Drain()
  local last = g.players[1].hand[#g.players[1].hand]
  H.eq(#g.players[1].hand, before + 1, "the Wild Growth left, Excess Mana arrived")
  H.eq(last and last.cardId, "CS2_013t", "Excess Mana")
  H.noEngineErrors(g)
end)

H.suite("review: 'whenever you cast' resolves before the spell", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 1, "NEW1_026")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "CS2_011")))); g.bus:Drain()
  local apprentice = g.players[1].board[2]
  H.eq(apprentice and apprentice.cardId, "NEW1_026t", "Violet Teacher made an Apprentice")
  H.eq(apprentice and apprentice:Attack(), 3, "in time for Savage Roar")
  H.noEngineErrors(g)
end)

H.suite("review: Truesilver heals before the blow lands", function(ns, H)
  local g = H.NewGame({ class1 = "PALADIN" })
  H.SetActive(g, 1)
  local hero = H.Hero(g, 1)
  hero.damage = 1
  g:EquipWeapon(1, "CS2_097")
  local yeti = H.Put(g, 2, "CS2_182")
  H.ok(g:Attack(hero, yeti)); g.bus:Drain()
  H.eq(hero:Health(), 26, "30 after the heal, then 4 from the Yeti")
  H.noEngineErrors(g)
end)

H.suite("review: Alexstrasza sets remaining Health, not the maximum", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(g:PlayCard(1, H.Hand(g, 1, "EX1_561"), H.Hero(g, 2))); g.bus:Drain()
  local foe = H.Hero(g, 2)
  H.eq(foe:Health(), 15, "15 Health")
  H.eq(foe:MaxHealth(), 30, "out of 30")
  g:Heal(foe, 10, nil)
  H.eq(foe:Health(), 25, "so it can be healed back up")
  H.noEngineErrors(g)
end)

H.suite("review: an 'if available' battlecry must take a target when there is one", function(ns, H)
  local g = H.NewGame()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.Put(g, 2, "CS2_182")
  local i, card = H.Hand(g, 1, "EX1_048")
  H.ok(ns.Targeting.NeedsTarget(g, card, 1), "Spellbreaker needs its target")
  H.notOk(g:PlayCard(1, i), "and cannot be played blank to dodge it")
  local g2 = H.NewGame()
  H.SetActive(g2, 1); H.Mana(g2, 1, 10)
  H.ok(g2:PlayCard(1, (H.Hand(g2, 1, "EX1_048"))), "with nothing to aim at it plays untargeted")
  H.noEngineErrors(g); H.noEngineErrors(g2)
end)

H.suite("review: a secret is a spell, and cannot be doubled", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE", class2 = "MAGE" })
  H.SetActive(g, 2); H.Mana(g, 2, 10)
  H.ok(g:PlayCard(2, (H.Hand(g, 2, "EX1_287"))))   -- their Counterspell
  g.bus:Drain()
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_289"))))   -- our Ice Barrier...
  g.bus:Drain()
  H.eq(#g.players[1].secrets, 0, "...is countered")
  H.eq(#g.players[2].secrets, 0, "by their Counterspell, now spent")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_289")))); g.bus:Drain()
  H.eq(#g.players[1].secrets, 1, "the second one lands")
  local i = H.Hand(g, 1, "EX1_289")
  local mana = g:AvailableMana(1)
  H.notOk(g:PlayCard(1, i), "a copy of a secret already in play cannot be played")
  H.eq(g:AvailableMana(1), mana, "and costs nothing")
  H.eq(g.players[1].hand[i].cardId, "EX1_289", "it stays in hand")
  H.noEngineErrors(g)
end)

--[[ 0.1.1 review (docs/30). A stealthed minion loses Stealth when it deals
     damage in any way, not only when it attacks. EX1_128 Conceal,
     EX1_298 Ragnaros the Firelord, NEW1_019 Knife Juggler. ]]
H.suite("review: a stealthed minion that deals damage is revealed", function(ns, H)
  local g = H.NewGame({ class1 = "ROGUE" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local rag = H.Put(g, 1, "EX1_298")
  local juggler = H.Put(g, 1, "NEW1_019")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "EX1_128")))); g.bus:Drain()
  H.ok(rag:IsStealth() and juggler:IsStealth(), "Conceal hides both")
  H.ok(g:PlayCard(1, (H.Hand(g, 1, "CS2_231")))); g.bus:Drain()
  H.notOk(juggler:IsStealth(), "the Juggler's knife gives it away")
  H.ok(rag:IsStealth(), "Ragnaros has not fired yet")
  g:EndTurn(); g.bus:Drain()
  H.notOk(rag:IsStealth(), "his end-of-turn shot reveals him for the opponent's turn")
  H.noEngineErrors(g)
end)

H.suite("review: a stealthed minion's hit into Immune leaves it hidden", function(ns, H)
  local g = H.NewGame()
  local wisp = H.Put(g, 1, "CS2_231")
  wisp.baseKeywords[ns.KEYWORD.STEALTH] = true
  local foe = H.Put(g, 2, "CS2_182")
  foe.baseKeywords[ns.KEYWORD.IMMUNE] = true
  g:DealDamage(foe, 1, wisp, false); g.bus:Drain()
  H.ok(wisp:IsStealth(), "no damage dealt, still stealthed")
  foe.baseKeywords[ns.KEYWORD.IMMUNE] = nil
  g:DealDamage(foe, 1, wisp, false); g.bus:Drain()
  H.notOk(wisp:IsStealth(), "a real hit reveals it")
  H.noEngineErrors(g)
end)

--[[ "Whenever a (friendly) minion takes damage" and friends, checked against
     Hearthstone for the minion ITSELF, including a hit that kills it: damage
     triggers resolve while the minion is still on the board (mortally
     wounded), before deaths. EX1_402 Armorsmith 1/4, EX1_007 Acolyte of Pain
     1/3, EX1_604 Frothing Berserker 2/4, GVG_034 Mech-Bear-Cat 7/6,
     EX1_595 Cult Master 4/2, EX1_001 Lightwarden 1/2, EX1_531 Scavenging
     Hyena 2/2, CS2_120 River Crocolisk 2/3 (Beast). ]]
H.suite("review: Armorsmith counts its own damage, even a killing blow", function(ns, H)
  local g = H.NewGame()
  local smith = H.Put(g, 1, "EX1_402")
  local hero = H.Hero(g, 1)
  g:DealDamage(smith, 1, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.eq(hero.armor, 1, "hit and survives: 1 Armor")
  g:DealDamage(smith, 10, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.eq(smith.zone ~= ns.ZONE.PLAY, true, "the second hit kills it")
  H.eq(hero.armor, 2, "and still gives 1 Armor")
  H.noEngineErrors(g)
end)

H.suite("review: a Divine Shield hit is not damage taken", function(ns, H)
  local g = H.NewGame()
  local smith = H.Put(g, 1, "EX1_402")
  local other = H.Put(g, 1, "CS2_231")
  other.divineShieldUp = true; other.baseKeywords[ns.KEYWORD.DIVINE_SHIELD] = true
  g:DealDamage(other, 3, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.eq(H.Hero(g, 1).armor, 0, "the shield popped, no Armor")
  H.noEngineErrors(g)
end)

H.suite("review: Acolyte of Pain and Mech-Bear-Cat trigger on the hit that kills them", function(ns, H)
  local g = H.NewGame()
  for _ = 1, 3 do H.PutOnDeck(g, 1, "CS2_231") end
  local acolyte = H.Put(g, 1, "EX1_007")
  local hand = #g.players[1].hand
  g:DealDamage(acolyte, 5, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].hand, hand + 1, "Acolyte draws as it dies")
  local cat = H.Put(g, 1, "GVG_034")
  hand = #g.players[1].hand
  g:DealDamage(cat, 10, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].hand, hand + 1, "Mech-Bear-Cat gives a Spare Part as it dies")
  H.noEngineErrors(g)
end)

H.suite("review: Frothing Berserker counts itself", function(ns, H)
  local g = H.NewGame()
  local froth = H.Put(g, 1, "EX1_604")
  g:DealDamage(froth, 1, nil, false); g:ProcessDeaths(); g.bus:Drain()
  H.eq(froth:Attack(), 3, "2 Attack +1 for its own damage")
  H.noEngineErrors(g)
end)

H.suite("review: Cult Master does not draw for minions that die with it", function(ns, H)
  local g = H.NewGame()
  for _ = 1, 3 do H.PutOnDeck(g, 1, "CS2_231") end
  local cult = H.Put(g, 1, "EX1_595")
  local wisp = H.Put(g, 1, "CS2_231")
  local hand = #g.players[1].hand
  cult.pendingDestroy = true; wisp.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].hand, hand, "dying together: no card")
  local cult2 = H.Put(g, 1, "EX1_595")
  local wisp2 = H.Put(g, 1, "CS2_231")
  wisp2.pendingDestroy = true; g:ProcessDeaths(); g.bus:Drain()
  H.eq(#g.players[1].hand, hand + 1, "alive: it draws")
  H.noEngineErrors(g)
end)

H.suite("review: Scavenging Hyena gets nothing from Beasts dying with it", function(ns, H)
  local g = H.NewGame()
  local hyena = H.Put(g, 1, "EX1_531")
  local croc = H.Put(g, 1, "CS2_120")
  hyena.pendingDestroy = true; croc.pendingDestroy = true
  g:ProcessDeaths(); g.bus:Drain()
  H.ok(hyena.zone ~= ns.ZONE.PLAY, "both gone")
  H.noEngineErrors(g)
end)

H.suite("review: Lightwarden counts healing on itself", function(ns, H)
  local g = H.NewGame()
  local warden = H.Put(g, 1, "EX1_001")
  g:DealDamage(warden, 1, nil, false); g.bus:Drain()
  g:Heal(warden, 1, nil); g.bus:Drain()
  H.eq(warden:Attack(), 3, "1 Attack +2")
  H.noEngineErrors(g)
end)
