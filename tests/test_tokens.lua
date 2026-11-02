--[[ tests/test_tokens.lua -- the cards the GAME makes, which nobody drafts.

  THE BLIND SPOT. The effect-script coverage report counts the COLLECTIBLE
  POOL, because that is what a player builds a deck from. A token is not
  collectible, so it was never counted -- and `Game:UseHeroPower` and every op
  runner guard with `if script and script.x`, so a token with no script is not
  an error anywhere. It simply does nothing, in silence, forever.

  This is the same shape of gap that once hid EIGHT OF THE NINE HERO POWERS
  (see tests/test_heropowers.lua). Closing it the second time turned up six
  more, including one that is in every match whose flip you lose:

    GAME_005   The Coin          gained you no mana
    GVG_110t   Boom Bot          Dr. Boom's two bots were vanilla 1/1s
    GVG_111t   V-07-TR-0N        Mega-Windfury swung twice, not four times
    EX1_tk33   INFERNO!          Lord Jaraxxus's hero power was a dead button
    EX1_625t   Mind Spike        Shadowform made a Priest strictly WORSE
    EX1_625t2  Mind Shatter      ...and so did casting it a second time

  tools/compile_effects.py now audits this set -- every card a script conjures,
  plus the ones Engine/Game.lua deals -- and REFUSES TO WRITE when one of them
  needs a script and has none. That guard is what stops a seventh.
]]
local H = require("tests.harness")

--============================================================== the audit

H.suite("tokens: every card the game makes has the script its text needs",
function(ns, H)
  --[[ The cheap assertion that would have caught all six on the day they were
       written. It is the token half of "every class has a hero power WITH A
       SCRIPT", and it costs one loop. ]]
  local WANT = { "GAME_005", "GVG_110t", "GVG_111t",
                 "EX1_tk33", "EX1_625t", "EX1_625t2" }
  local g = H.NewGame()
  for _, id in ipairs(WANT) do
    H.ok(g:Printed(id), id .. " is a real card in the pinned data")
    H.ok(g:ScriptFor(id), id .. " HAS A SCRIPT")
  end
end)

--================================================================ the Coin

H.suite("tokens: the Coin gives a mana crystal for THIS TURN ONLY", function(ns, H)
  --[[ THE BUG. The Coin had no script. You lost the flip, were handed a card
       as compensation, played it, and got nothing -- so going second cost you
       the tempo AND the card. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 1)
  local i = H.Hand(g, 1, "GAME_005")
  H.eq(g:AvailableMana(1), 1, "one mana before")
  H.ok(g:PlayCard(1, i), "the Coin plays")
  g.bus:Drain()
  H.eq(g:AvailableMana(1), 2, "TWO mana after -- this is the whole card")
  H.eq(g.players[1].maxMana, 1, "and the crystal is temporary: still 1 max")
end)

H.suite("tokens: the Coin's mana is gone next turn", function(ns, H)
  --[[ "This turn only" is the half that a permanent GainManaCrystal would get
       wrong -- and it would look correct for a whole turn. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 1)
  local i = H.Hand(g, 1, "GAME_005")
  g:PlayCard(1, i)
  g.bus:Drain()
  H.eq(g:AvailableMana(1), 2, "two this turn")
  g:EndTurn(); g.bus:Drain()      -- theirs
  g:EndTurn(); g.bus:Drain()      -- back to us
  H.eq(g.players[1].maxMana, 2, "we gained our own crystal for turn two")
  H.eq(g:AvailableMana(1), 2, "and the Coin's is NOT still there")
end)

H.suite("tokens: the Coin puts a card in reach that was not", function(ns, H)
  --[[ The reason the card exists, asserted through the RULES rather than
       through the number. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 3)
  local yeti = H.Hand(g, 1, "CS2_182")             -- Chillwind Yeti, 4 mana
  local card = g.players[1].hand[yeti]
  H.notOk(ns.Targeting.CanPlay(g, card, 1), "a 4-drop is out of reach on three")
  local coin = H.Hand(g, 1, "GAME_005")
  H.ok(g:PlayCard(1, coin), "the Coin plays")
  g.bus:Drain()
  H.ok(ns.Targeting.CanPlay(g, card, 1), "and the same card is now playable")
end)

--============================================================== Boom Bot

H.suite("tokens: a Boom Bot's deathrattle fires for 1-4", function(ns, H)
  --[[ Dr. Boom is a 7/7 for seven whose entire value is the two bots. With no
       script they were vanilla 1/1s and the card was junk. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local bot = H.Put(g, 1, "GVG_110t")
  local wall = H.Put(g, 2, "CS2_186")              -- War Golem 7/7
  local heroBefore = g.players[2].hero:Health()
  bot.pendingDestroy = true
  g:ProcessDeaths()
  g.bus:Drain()
  local hit = (heroBefore - g.players[2].hero:Health()) + (7 - wall:Health())
  H.ok(hit >= 1 and hit <= 4, "something enemy took 1-4 damage, got " .. hit)
  H.noEngineErrors(g)
end)

H.suite("tokens: Dr. Boom's bots carry the deathrattle, by ID", function(ns, H)
  --[[ The wrong-token class of bug: a summon that looks right and is not.
       Asserted by card id rather than by stats. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "GVG_110")
  H.ok(g:PlayCard(1, i), "Dr. Boom lands")
  g.bus:Drain()
  local bots = 0
  for _, e in ipairs(g.players[1].board) do
    if e.cardId == "GVG_110t" then
      bots = bots + 1
      H.ok(g:ScriptFor(e.cardId), "and the bot has its deathrattle")
    end
  end
  H.eq(bots, 2, "two Boom Bots")
end)

--============================================================ Mega-Windfury

H.suite("tokens: V-07-TR-0N attacks FOUR times, not twice", function(ns, H)
  --[[ THE BUG. Mega-Windfury is printed in the card's TEXT and nowhere else --
       the vendored data gives it only CHARGE -- so no importer could ever
       derive it, and `Game:CanAttack` computed `Windfury and 2 or 1`. The
       eight-mana finisher you assemble three Mechs to earn swung twice. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local v = H.Put(g, 1, "GVG_111t")
  H.eq(g:AttacksAllowed(v), 4, "four swings allowed")
  for n = 1, 4 do
    H.ok(g:CanAttack(v), "swing " .. n .. " allowed")
    v.attacksThisTurn = v.attacksThisTurn + 1
  end
  H.notOk(g:CanAttack(v), "and a fifth is refused")
end)

H.suite("tokens: Mega-Windfury REPLACES Windfury, it does not add to it",
function(ns, H)
  --[[ Four, not six: a V-07-TR-0N given Windfury by Rockbiter Weapon is still
       a four-attack minion in Hearthstone. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local v = H.Put(g, 1, "GVG_111t")
  v:AddEnchantment(0, 0, { ns.KEYWORD.WINDFURY })
  H.ok(v:Has(ns.KEYWORD.WINDFURY), "it really does have Windfury now")
  H.eq(g:AttacksAllowed(v), 4, "and still gets four")
end)

H.suite("tokens: silence takes Mega-Windfury away", function(ns, H)
  --[[ It is a keyword on the body, not a printed stat, so silence removes it
       exactly as it removes Windfury. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  local v = H.Put(g, 1, "GVG_111t")
  v:Silence()
  g:RecalcAuras()
  H.eq(g:AttacksAllowed(v), 1, "one swing, like any silenced minion")
end)

H.suite("tokens: an ordinary minion still gets one, and Windfury two",
function(ns, H)
  --[[ The other half of the mutation: a change that gave EVERYTHING four
       attacks would pass every assertion above. ]]
  local g = H.NewGame()
  H.SetActive(g, 1)
  H.eq(g:AttacksAllowed(H.Put(g, 1, "CS2_182")), 1, "a Yeti swings once")
  H.eq(g:AttacksAllowed(H.Put(g, 1, "EX1_033")), 2, "Windfury swings twice")
end)

--============================================================== Jaraxxus

H.suite("tokens: INFERNO! summons a 6/6 Infernal", function(ns, H)
  --[[ Lord Jaraxxus swapped the hero correctly and set this power correctly,
       and then the power did nothing at all -- so the Warlock finisher cost 15
       health of hero swap in exchange for a weapon and a dead button. ]]
  local g = H.NewGame({ class1 = "WARLOCK" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  g:SetHeroPower(1, "EX1_tk33")
  H.ok(g:UseHeroPower(1), "INFERNO! fires")
  g.bus:Drain()
  local last = g.players[1].board[#g.players[1].board]
  H.ok(last, "something was summoned")
  H.eq(last and last.cardId, "EX1_tk34", "and it is the Infernal")
  H.eq(last and last:Attack(), 6, "6 attack")
  H.eq(last and last:Health(), 6, "6 health")
end)

H.suite("tokens: Jaraxxus end to end -- hero, weapon AND a working power",
function(ns, H)
  local g = H.NewGame({ class1 = "WARLOCK" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_323")
  H.ok(g:PlayCard(1, i), "Jaraxxus is played")
  g.bus:Drain()
  H.eq(g.players[1].hero:Health(), 15, "a 15-health hero")
  H.ok(g.players[1].weapon, "holding Blood Fury")
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  H.ok(g:UseHeroPower(1), "and INFERNO! WORKS")
  g.bus:Drain()
  local last = g.players[1].board[#g.players[1].board]
  H.eq(last and last.cardId, "EX1_tk34", "a 6/6 Infernal arrives")
  H.noEngineErrors(g)
end)

--============================================================== Shadowform

H.suite("tokens: Shadowform's Mind Spike deals 2 to a target", function(ns, H)
  --[[ Unauthored, Shadowform REPLACED a working Lesser Heal with a button that
       did nothing -- so casting it made a Priest strictly worse, which is the
       exact opposite of the card. ]]
  local g = H.NewGame({ class1 = "PRIEST" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  g:SetHeroPower(1, "EX1_625t")
  local ogre = H.Put(g, 2, "CS2_200")              -- Boulderfist Ogre 6/7
  H.ok(g:UseHeroPower(1, ogre), "Mind Spike fires")
  g.bus:Drain()
  H.eq(ogre:Health(), 5, "two damage")
end)

H.suite("tokens: Shadowform's Mind Shatter deals 3", function(ns, H)
  local g = H.NewGame({ class1 = "PRIEST" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  g:SetHeroPower(1, "EX1_625t2")
  local ogre = H.Put(g, 2, "CS2_200")
  H.ok(g:UseHeroPower(1, ogre), "Mind Shatter fires")
  g.bus:Drain()
  H.eq(ogre:Health(), 4, "three damage")
end)

H.suite("tokens: casting Shadowform twice really does upgrade the power",
function(ns, H)
  --[[ The whole card through the rules: Lesser Heal -> Mind Spike -> Mind
       Shatter, with each power actually dealing its damage. ]]
  local g = H.NewGame({ class1 = "PRIEST" })
  H.SetActive(g, 1)
  H.Mana(g, 1, 10)
  local ogre = H.Put(g, 2, "CS2_200")

  local i = H.Hand(g, 1, "EX1_625")
  H.ok(g:PlayCard(1, i), "Shadowform once")
  g.bus:Drain()
  H.eq(g.players[1].heroPower.cardId, "EX1_625t", "the power is Mind Spike")
  H.SetActive(g, 1)
  g:UseHeroPower(1, ogre); g.bus:Drain()
  H.eq(ogre:Health(), 5, "and it deals its 2")

  local j = H.Hand(g, 1, "EX1_625")
  H.ok(g:PlayCard(1, j), "Shadowform twice")
  g.bus:Drain()
  H.eq(g.players[1].heroPower.cardId, "EX1_625t2", "the power is Mind Shatter")
  H.SetActive(g, 1)
  g:UseHeroPower(1, ogre); g.bus:Drain()
  H.eq(ogre:Health(), 2, "and it deals its 3")
  H.noEngineErrors(g)
end)
