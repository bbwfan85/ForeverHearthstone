--[[ tests/test_chooseone.lua -- the Choose One mechanic.

  Thirteen Druid cards offer two named modes at play time. The modes are NOT
  hand-listed anywhere: the pinned build carries each one as a real,
  non-collectible 0-cost spell with id <parent>a / <parent>b, carrying its own
  text and its own playRequirements, and tools/chooseone.py derives the link.

  The three things most worth pinning down here, because each is a place where a
  plausible implementation would be silently wrong:

    * TARGETING comes from the MODE. Keeper of the Grove's Moonfire may hit a
      hero; its Dispel may not.
    * EVERYTHING ELSE comes from the PARENT. Keeper of the Grove is a MINION, so
      Moonfire is a BATTLECRY: it is not boosted by Spell Damage and it may
      target a minion that spells cannot. Wrath is a SPELL and is boosted. The
      printed text says exactly this -- Wrath's "$3" carries the spell-damage
      sigil, Moonfire's "2" does not.
    * DISPLAY ORDER is the card's text order, not the a/b suffix. Four of the
      thirteen are reversed, and a swapped pair would offer the wrong mode under
      the right label with nothing downstream able to notice.

  Fixtures used below, all verified against the pin:
    CS2_182  Chillwind Yeti        4 mana 4/5 vanilla
    CS2_231  Wisp                  0 mana 1/1 vanilla
    CS2_200  Boulderfist Ogre      6 mana 6/7 vanilla
    NEW1_023 Faerie Dragon         2 mana 3/2 CANT_BE_TARGETED_BY_SPELLS
    CS2_142  Kobold Geomancer      2 mana 2/2 Spell Damage +1
    CS2_179  Sen'jin Shieldmasta   4 mana 3/5 Taunt
]]
local H = require("tests.harness")

local PARENTS = {
  "EX1_154", "EX1_155", "EX1_160", "EX1_164", "EX1_165", "EX1_166", "EX1_178",
  "EX1_573", "GVG_030", "GVG_032", "GVG_041", "NEW1_007", "NEW1_008",
}

--============================================================ printed data

H.suite("chooseone: every Choose One card links two real, scripted modes", function(ns, H)
  local g = H.NewGame()
  for _, cid in ipairs(PARENTS) do
    local pr = g:Printed(cid)
    H.ok(pr and pr.chooseOne, cid .. " carries a chooseOne link")
    H.eq(pr.chooseOne and #pr.chooseOne or 0, 2, cid .. " has exactly two modes")
    for i = 1, 2 do
      local m = pr.chooseOne[i]
      H.ok(g:Printed(m), cid .. " mode " .. i .. " (" .. tostring(m) .. ") is a real card")
      H.ok(g:ScriptFor(m), cid .. " mode " .. i .. " (" .. tostring(m) .. ") has a script")
    end
    -- The parent itself must carry NO script: the engine substitutes the mode's
    -- for it, so a parent script could only ever be dead data.
    H.notOk(g:ScriptFor(cid), cid .. " parent carries no script of its own")
  end
end)

H.suite("chooseone: no OTHER card in the pool claims to be Choose One", function(ns, H)
  local g = H.NewGame()
  local seen = {}
  for _, cid in ipairs(PARENTS) do seen[cid] = true end
  local extra = 0
  for id, pr in pairs(ns.PrintedCards) do
    if pr.chooseOne and not seen[id] then extra = extra + 1 end
    -- A collectible card whose text says Choose One but carries no link would
    -- be unplayable-as-printed, which is the failure this catches.
    if pr.collectible and pr.text and pr.text:find("Choose One", 1, true)
       and not pr.chooseOne then
      H.ok(false, id .. " says Choose One but has no mode link")
    end
  end
  H.eq(extra, 0, "no unexpected Choose One cards")
end)

H.suite("chooseone: display order follows the card text, not the a/b suffix", function(ns, H)
  local g = H.NewGame()
  -- The nine in suffix order...
  H.eq(g:Printed("EX1_166").chooseOne[1], "EX1_166a", "Keeper: Moonfire first")
  H.eq(g:Printed("EX1_154").chooseOne[1], "EX1_154a", "Wrath: 3 damage first")
  -- ...and the four the data reverses. Each parent text names the mode that
  -- carries the OTHER suffix first.
  H.eq(g:Printed("EX1_160").chooseOne[1], "EX1_160b", "Power of the Wild: +1/+1 first")
  H.eq(g:Printed("EX1_178").chooseOne[1], "EX1_178b", "Ancient of War: +5 Attack first")
  H.eq(g:Printed("GVG_041").chooseOne[1], "GVG_041b", "Dark Wispers: 5 Wisps first")
  H.eq(g:Printed("NEW1_007").chooseOne[1], "NEW1_007b", "Starfall: 5 to a minion first")
end)

--============================================================ the play gate

H.suite("chooseone: a mode is required, and the play is refused without one", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID", deck1 = { "EX1_154" } })
  H.Mana(g, 1, 10)
  H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "EX1_154")
  local handBefore, manaBefore = #g.players[1].hand, g.players[1].mana

  local ok, why = g:PlayCard(1, i, g.players[2].board[1], nil, nil)
  H.notOk(ok, "no mode is refused")
  H.eq(why, "mode required", "and says why")
  H.eq(#g.players[1].hand, handBefore, "card stayed in hand")
  H.eq(g.players[1].mana, manaBefore, "no mana was spent")
  H.board(g, 2, { "CS2_182 4/5" }, "nothing happened to the board")
  H.noEngineErrors(g)
end)

H.suite("chooseone: an out-of-range mode is refused", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "EX1_154")
  local handBefore = #g.players[1].hand
  for _, bad in ipairs({ 0, 3, -1 }) do
    local ok, why = g:PlayCard(1, i, g.players[2].board[1], nil, bad)
    H.notOk(ok, "mode " .. bad .. " is refused")
    H.eq(why, "mode required", "mode " .. bad .. " says why")
  end
  H.eq(#g.players[1].hand, handBefore, "the card is still in hand after three refusals")
  H.noEngineErrors(g)
end)

H.suite("chooseone: a mode on a card with no modes is refused, not ignored", function(ns, H)
  -- Silently dropping the mode would play a DIFFERENT card than the caller
  -- believed it was playing, which across the wire is a desync.
  local g = H.NewGame({ class1 = "MAGE" })
  H.Mana(g, 1, 10)
  H.Put(g, 2, "CS2_182")
  local i = H.Hand(g, 1, "CS2_024")          -- Frostbolt, an ordinary spell
  local ok, why = g:PlayCard(1, i, g.players[2].board[1], nil, 1)
  H.notOk(ok, "mode on a modeless card is refused")
  H.eq(why, "card has no modes", "and says why")
  H.board(g, 2, { "CS2_182 4/5" }, "the Frostbolt did not go off")
  H.noEngineErrors(g)
end)

--============================================================ mode targeting

H.suite("chooseone: targeting comes from the chosen mode", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local yeti = H.Put(g, 2, "CS2_182")
  local i, card = H.Hand(g, 1, "EX1_166")    -- Keeper of the Grove
  local T = ns.Targeting

  -- mode 1 Moonfire: any character. mode 2 Dispel: minions only.
  H.ok(T.IsLegalTarget(g, card, 1, H.Hero(g, 2), 1), "Moonfire may hit a hero")
  H.notOk(T.IsLegalTarget(g, card, 1, H.Hero(g, 2), 2), "Dispel may not hit a hero")
  H.ok(T.IsLegalTarget(g, card, 1, yeti, 1), "Moonfire may hit a minion")
  H.ok(T.IsLegalTarget(g, card, 1, yeti, 2), "Dispel may hit a minion")

  -- With no mode chosen the parent has no requirements of its own at all.
  H.notOk(T.NeedsTarget(g, card, 1, nil), "the parent alone demands no target")
  H.ok(T.NeedsTarget(g, card, 1, 1), "Moonfire demands a target")
  H.ok(T.NeedsTarget(g, card, 1, 2), "Dispel demands a target")

  -- Playing it at a hero with Dispel selected is refused by the mode's reqs.
  local ok, why = g:PlayCard(1, i, H.Hero(g, 2), nil, 2)
  H.notOk(ok, "Dispel at a hero refused")
  H.eq(why, "illegal target", "and says why")
  H.noEngineErrors(g)
end)

H.suite("chooseone: a minion's mode is a battlecry, so it beats 'no spells'", function(ns, H)
  --[[ Faerie Dragon cannot be targeted by SPELLS. Keeper of the Grove is a
       MINION whose mode resolves as a battlecry, so Moonfire may hit it --
       while Wrath, a real spell, may not. This is the distinction that breaks
       if the mode's printed type (SPELL, a data artefact) is used in place of
       the parent's. ]]
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local dragon = H.Put(g, 2, "NEW1_023")
  local T = ns.Targeting

  local _, keeper = H.Hand(g, 1, "EX1_166")
  local _, wrath  = H.Hand(g, 1, "EX1_154")
  H.ok(T.IsLegalTarget(g, keeper, 1, dragon, 1), "Keeper's Moonfire may hit a Faerie Dragon")
  H.ok(T.IsLegalTarget(g, keeper, 1, dragon, 2), "Keeper's Dispel may hit a Faerie Dragon")
  H.notOk(T.IsLegalTarget(g, wrath, 1, dragon, 1), "Wrath may NOT hit a Faerie Dragon")
  H.notOk(T.IsLegalTarget(g, wrath, 1, dragon, 2), "neither may its other mode")
  H.noEngineErrors(g)
end)

H.suite("chooseone: a card is playable when EITHER mode is", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local T = ns.Targeting
  local _, wrath = H.Hand(g, 1, "EX1_154")

  -- Both Wrath modes need a minion, and there are none anywhere.
  H.notOk(T.CanPlay(g, wrath, 1), "Wrath is unplayable with no minions in play")
  local _, why = T.CanPlay(g, wrath, 1)
  H.eq(why, "no playable mode", "and says why")

  H.Put(g, 2, "CS2_182")
  H.ok(T.CanPlay(g, wrath, 1), "a minion appears and Wrath is playable")
  H.noEngineErrors(g)
end)

H.suite("chooseone: a full board greys one mode without blocking the card", function(ns, H)
  --[[ Power of the Wild: mode 1 buffs, mode 2 summons a Panther. With seven
       minions out the Panther has nowhere to go, but the card is still a
       perfectly good +1/+1 -- so the CARD stays playable and the MODE does not. ]]
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  for _ = 1, ns.RULES.BOARD_SLOTS do H.Put(g, 1, "CS2_231") end
  local T = ns.Targeting
  local i, potw = H.Hand(g, 1, "EX1_160")
  local handBefore = #g.players[1].hand

  H.ok(T.CanPlay(g, potw, 1), "Power of the Wild is still playable")
  H.ok(T.ModePlayable(g, potw, 1, 1), "the +1/+1 mode is choosable")
  H.notOk(T.ModePlayable(g, potw, 1, 2), "the Panther mode is not")

  local opts = T.ModeOptions(g, potw, 1)
  H.eq(#opts, 2, "the prompt offers two options")
  H.eq(opts[1].name, "Leader of the Pack", "option 1 is named from printed data")
  H.eq(opts[2].name, "Summon a Panther", "option 2 is named from printed data")
  H.ok(opts[1].playable, "option 1 is offered")
  H.notOk(opts[2].playable, "option 2 is greyed")
  H.eq(opts[2].reason, "REQ_NUM_MINION_SLOTS", "and the reason is the printed requirement")
  H.ok(opts[1].text and #opts[1].text > 0, "options carry their printed text for the prompt")

  local ok, why = g:PlayCard(1, i, nil, nil, 2)
  H.notOk(ok, "choosing the Panther anyway is refused")
  H.eq(why, "REQ_NUM_MINION_SLOTS", "and says which requirement failed")
  H.eq(#g.players[1].hand, handBefore, "the card stayed in hand")
  H.noEngineErrors(g)
end)

H.suite("chooseone: ModeOptions is nil for an ordinary card", function(ns, H)
  -- This is how the client asks "does playing this need a prompt first?".
  local g = H.NewGame({ class1 = "DRUID" })
  local _, yeti = H.Hand(g, 1, "CS2_182")
  H.notOk(ns.Targeting.ModeOptions(g, yeti, 1), "a Yeti has no modes")
  local _, wrath = H.Hand(g, 1, "EX1_154")
  H.ok(ns.Targeting.ModeOptions(g, wrath, 1), "Wrath does")
end)

--============================================================ spell damage

H.suite("chooseone: Spell Damage boosts Wrath but NOT Keeper's Moonfire", function(ns, H)
  --[[ The printed text is the authority: Wrath reads "$3", Keeper of the Grove
       reads "2". The $ sigil marks spell-damage-affected, and Keeper's mode is
       a battlecry rather than a spell, so it is not. ]]
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_142")                       -- Kobold Geomancer, Spell Damage +1
  local ogre = H.Put(g, 2, "CS2_200")          -- Boulderfist Ogre 6/7

  local i = H.Hand(g, 1, "EX1_154")            -- Wrath, mode 1 = $3
  H.ok(g:PlayCard(1, i, ogre, nil, 1), "Wrath resolved")
  g.bus:Drain()
  H.eq(ogre:Health(), 7 - 4, "Wrath's $3 became 4 with Spell Damage +1")

  local ogre2 = H.Put(g, 2, "CS2_200")
  local j = H.Hand(g, 1, "EX1_166")            -- Keeper, mode 1 = Moonfire 2
  H.ok(g:PlayCard(1, j, ogre2, nil, 1), "Keeper resolved")
  g.bus:Drain()
  H.eq(ogre2:Health(), 7 - 2, "Moonfire stayed at 2 -- a battlecry, not a spell")
  H.noEngineErrors(g)
end)

--============================================================ every card

H.suite("chooseone: Wrath -- 3 damage, or 1 damage and a card", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local ogre = H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "EX1_154")
  H.ok(g:PlayCard(1, i, ogre, nil, 1))
  g.bus:Drain()
  H.eq(ogre:Health(), 4, "mode 1 dealt 3")

  H.SetActive(g, 1)
  local ogre2 = H.Put(g, 2, "CS2_200")
  local hand = #g.players[1].hand
  local j = H.Hand(g, 1, "EX1_154")
  H.ok(g:PlayCard(1, j, ogre2, nil, 2))
  g.bus:Drain()
  H.eq(ogre2:Health(), 6, "mode 2 dealt 1")
  -- hand: +1 for the Wrath added, -1 for playing it, +1 for the draw
  H.eq(#g.players[1].hand, hand + 1, "mode 2 drew a card")
  H.noEngineErrors(g)
end)

H.suite("chooseone: Mark of Nature -- +4 Attack, or +4 Health and Taunt", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local a = H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "EX1_155")
  H.ok(g:PlayCard(1, i, a, nil, 1))
  g.bus:Drain()
  H.board(g, 1, { "CS2_182 8/5" }, "mode 1 gave +4 Attack")
  H.notOk(a:IsTaunt(), "and no Taunt")

  H.SetActive(g, 1)
  local b = H.Put(g, 1, "CS2_182")
  local j = H.Hand(g, 1, "EX1_155")
  H.ok(g:PlayCard(1, j, b, nil, 2))
  g.bus:Drain()
  H.eq(b:Health(), 9, "mode 2 gave +4 Health")
  H.ok(b:IsTaunt(), "and Taunt")
  H.noEngineErrors(g)
end)

H.suite("chooseone: Power of the Wild -- +1/+1, or a 3/2 Panther", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_182")
  H.Put(g, 1, "CS2_231")
  local i = H.Hand(g, 1, "EX1_160")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  H.board(g, 1, { "CS2_182 5/6", "CS2_231 2/2" }, "mode 1 buffed the whole board")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local j = H.Hand(g2, 1, "EX1_160")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  H.board(g2, 1, { "EX1_160t 3/2" }, "mode 2 summoned the Panther")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Nourish -- 2 Mana Crystals, or 3 cards", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  local p = g.players[1]
  H.Mana(g, 1, 5)
  local i = H.Hand(g, 1, "EX1_164")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  H.eq(p.maxMana, 7, "mode 1 gained 2 Mana Crystals")
  -- Unlike Wild Growth ("an EMPTY Mana Crystal"), Nourish's crystals arrive
  -- full: 5 mana, Nourish cost 5, and the 2 new ones can be spent this turn.
  H.eq(p.mana, 2, "and they are full")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local before = #g2.players[1].hand
  local j = H.Hand(g2, 1, "EX1_164")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  H.eq(#g2.players[1].hand, before + 3, "mode 2 drew 3 cards")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Druid of the Claw TRANSFORMS, and Cat Form may charge in", function(ns, H)
  --[[ The pin carries 4/4 Charge and 4/6 Taunt tokens for this card and mode
       ENCHANTMENTs for every other Choose One minion, which is how we know this
       one alone transforms rather than buffing. Transform keeps summonedTurn,
       and the token's Charge is PRINTED, so the cat attacks the turn it lands. ]]
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_165")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  H.board(g, 1, { "EX1_165t1 4/4" }, "Cat Form is the 4/4 token")
  local cat = g.players[1].board[1]
  H.ok(cat:Has(ns.KEYWORD.CHARGE), "Cat Form has Charge")
  H.ok(g:CanAttack(cat), "and can attack the turn it was played")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local j = H.Hand(g2, 1, "EX1_165")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  H.board(g2, 1, { "EX1_165t2 4/6" }, "Bear Form is the 4/6 token")
  local bear = g2.players[1].board[1]
  H.ok(bear:IsTaunt(), "Bear Form has Taunt")
  H.notOk(g2:CanAttack(bear), "and is summoning sick like any other minion")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Keeper of the Grove -- Moonfire, or Dispel", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local wisp = H.Put(g, 2, "CS2_231")
  local i = H.Hand(g, 1, "EX1_166")
  H.ok(g:PlayCard(1, i, wisp, nil, 1))
  g.bus:Drain()
  H.board(g, 2, {}, "Moonfire killed the Wisp")
  H.board(g, 1, { "EX1_166 2/4" }, "and the Keeper itself is on the board")

  H.SetActive(g, 1)
  local taunter = H.Put(g, 2, "CS2_179")     -- Sen'jin Shieldmasta 3/5 Taunt
  local j = H.Hand(g, 1, "EX1_166")
  H.ok(g:PlayCard(1, j, taunter, nil, 2))
  g.bus:Drain()
  H.notOk(taunter:IsTaunt(), "Dispel silenced away the Taunt")
  H.noEngineErrors(g)
end)

H.suite("chooseone: Ancient of War buffs, so Silence undoes it", function(ns, H)
  --[[ The counterpart to Druid of the Claw: the pin gives Ancient of War mode
       ENCHANTMENTs and no tokens, so Rooted is a buff. Silencing it therefore
       returns a 5/10 Taunt to a plain 5/5 -- where silencing a Bear Form would
       leave the token's stats alone. ]]
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_178")
  H.ok(g:PlayCard(1, i, nil, nil, 1))         -- display order: +5 Attack first
  g.bus:Drain()
  H.board(g, 1, { "EX1_178 10/5" }, "mode 1 is +5 Attack")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local j = H.Hand(g2, 1, "EX1_178")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  local aow = g2.players[1].board[1]
  H.board(g2, 1, { "EX1_178 5/10" }, "mode 2 is +5 Health")
  H.ok(aow:IsTaunt(), "and Taunt")
  aow:Silence()
  g2:RecalcAuras()
  H.board(g2, 1, { "EX1_178 5/5" }, "Silence reverts it -- an enchantment, not a transform")
  H.notOk(aow:IsTaunt(), "and takes the Taunt with it")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Cenarius -- +2/+2 to OTHERS, or two Treants", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  H.Put(g, 1, "CS2_182")
  local i = H.Hand(g, 1, "EX1_573")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  -- Cenarius is 5/8 printed and must NOT buff itself.
  H.board(g, 1, { "CS2_182 6/7", "EX1_573 5/8" }, "the Yeti grew, Cenarius did not")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local j = H.Hand(g2, 1, "EX1_573")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  -- one on his right, then one on his left (hearthstone.wiki.gg/wiki/Cenarius)
  H.board(g2, 1, { "EX1_573t 2/2", "EX1_573 5/8", "EX1_573t 2/2" }, "two Treants flanking him")
  H.ok(g2.players[1].board[1]:IsTaunt(), "with Taunt")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Grove Tender gives to BOTH players", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  -- Below the ten-crystal cap on purpose: at 10 the gain is clamped away and
  -- the test would pass for the wrong reason.
  H.Mana(g, 1, 5)
  local p1, p2 = g.players[1], g.players[2]
  local max1, max2 = p1.maxMana, p2.maxMana
  H.ok(max1 < 10 and max2 < 10, "both players have room for another crystal")
  local i = H.Hand(g, 1, "GVG_032")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  H.eq(p1.maxMana, max1 + 1, "you gained a crystal")
  H.eq(p2.maxMana, max2 + 1, "so did the opponent")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local h1, h2 = #g2.players[1].hand, #g2.players[2].hand
  local j = H.Hand(g2, 1, "GVG_032")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  -- +1 added, -1 played, +1 drawn = net +1
  H.eq(#g2.players[1].hand, h1 + 1, "you drew")
  H.eq(#g2.players[2].hand, h2 + 1, "so did the opponent")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Dark Wispers -- five Wisps, or +5/+5 and Taunt", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "GVG_041")
  H.ok(g:PlayCard(1, i, nil, nil, 1))         -- display order: Wisps first
  g.bus:Drain()
  H.eq(#g.players[1].board, 5, "five Wisps arrived")
  H.eq(g.players[1].board[1].cardId, "CS2_231", "and they are Wisps")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local yeti = H.Put(g2, 1, "CS2_182")
  local j = H.Hand(g2, 1, "GVG_041")
  H.ok(g2:PlayCard(1, j, yeti, nil, 2))
  g2.bus:Drain()
  H.board(g2, 1, { "CS2_182 9/10" }, "mode 2 gave +5/+5")
  H.ok(yeti:IsTaunt(), "and Taunt")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Starfall -- 5 to one minion, or 2 to all enemy minions", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local ogre = H.Put(g, 2, "CS2_200")
  local i = H.Hand(g, 1, "NEW1_007")
  H.ok(g:PlayCard(1, i, ogre, nil, 1))        -- display order: single target first
  g.bus:Drain()
  H.eq(ogre:Health(), 2, "mode 1 dealt 5 to the one minion")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  H.Put(g2, 1, "CS2_231")                     -- a friendly Wisp must SURVIVE
  H.Put(g2, 2, "CS2_182")
  H.Put(g2, 2, "CS2_231")
  local j = H.Hand(g2, 1, "NEW1_007")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  H.board(g2, 2, { "CS2_182 4/3" }, "mode 2 hit every enemy minion")
  H.board(g2, 1, { "CS2_231 1/1" }, "and left friendly minions alone")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Ancient of Lore -- 2 cards, or 5 Health", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local before = #g.players[1].hand
  local i = H.Hand(g, 1, "NEW1_008")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  H.eq(#g.players[1].hand, before + 2, "mode 1 drew 2")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local hero = H.Hero(g2, 1)
  g2:DealDamage(hero, 8, nil, false)
  g2.bus:Drain()
  local j = H.Hand(g2, 1, "NEW1_008")
  H.ok(g2:PlayCard(1, j, hero, nil, 2))
  g2.bus:Drain()
  H.eq(hero:Health(), 30 - 8 + 5, "mode 2 restored 5 Health")
  H.noEngineErrors(g2)
end)

H.suite("chooseone: Anodized Robo Cub keeps its printed Taunt either way", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "GVG_030")
  H.ok(g:PlayCard(1, i, nil, nil, 1))
  g.bus:Drain()
  H.board(g, 1, { "GVG_030 3/2" }, "Attack Mode is +1 Attack")
  H.ok(g.players[1].board[1]:IsTaunt(), "Taunt is printed and survives the choice")

  local g2 = H.NewGame({ class1 = "DRUID" })
  H.Mana(g2, 1, 10)
  local j = H.Hand(g2, 1, "GVG_030")
  H.ok(g2:PlayCard(1, j, nil, nil, 2))
  g2.bus:Drain()
  H.board(g2, 1, { "GVG_030 2/3" }, "Tank Mode is +1 Health")
  H.ok(g2.players[1].board[1]:IsTaunt(), "still Taunt")
  H.noEngineErrors(g2)
end)

--============================================================ across the wire

H.suite("chooseone: the chosen mode is recorded on the card", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local i = H.Hand(g, 1, "EX1_165")
  H.ok(g:PlayCard(1, i, nil, nil, 2))
  g.bus:Drain()
  H.eq(g.players[1].board[1].chosenMode, 2, "the board entity remembers its mode")
end)

H.suite("chooseone: the two modes produce different state hashes", function(ns, H)
  -- Lockstep replays the mode as part of the play action; if the two modes
  -- hashed alike, a desync on the choice could go undetected.
  local function play(mode)
    local g = H.NewGame({ class1 = "DRUID", seed = 999 })
    H.Mana(g, 1, 10)
    local i = H.Hand(g, 1, "EX1_165")
    g:PlayCard(1, i, nil, nil, mode)
    g.bus:Drain()
    return g:StateHash()
  end
  local a, b = play(1), play(2)
  H.notOk(a == b, "Cat Form and Bear Form do not hash alike")
  H.eq(play(1), a, "and the same choice replays to the same hash")
end)

--============================================================ the Silence op

--[[ Authoring Keeper of the Grove's Dispel was the first time any test played a
     card whose SCRIPT uses the Silence op -- every earlier silence test called
     entity:Silence() directly -- and it turned up a live bug: the op raised its
     SILENCED event through `game:Raise`, which does not exist (it is
     `game.bus:Raise`). The error was swallowed by the event block, so the
     silence landed and the op list simply stopped.

     Because the raise sat INSIDE the per-entity loop, the cards that lost the
     most were the ones that silence more than one minion or do something
     afterwards. These three are the regression: each would pass with the old
     code if you only checked the first minion. ]]

H.suite("silence op: Earth Shock silences AND then deals its damage", function(ns, H)
  local g = H.NewGame({ class1 = "SHAMAN" })
  H.Mana(g, 1, 10)
  local taunter = H.Put(g, 2, "CS2_179")        -- Sen'jin Shieldmasta 3/5 Taunt
  local i = H.Hand(g, 1, "EX1_245")
  H.ok(g:PlayCard(1, i, taunter))
  g.bus:Drain()
  H.notOk(taunter:IsTaunt(), "the Taunt is gone")
  H.eq(taunter:Health(), 4, "and it took the 1 damage that follows the silence")
  H.noEngineErrors(g)
end)

H.suite("silence op: Mass Dispel silences EVERY enemy minion and draws", function(ns, H)
  local g = H.NewGame({ class1 = "PRIEST" })
  H.Mana(g, 1, 10)
  local a = H.Put(g, 2, "CS2_179")              -- Taunt
  local b = H.Put(g, 2, "CS2_127")              -- Silverback Patriarch, Taunt
  local c = H.Put(g, 2, "CS2_232")              -- Ironbark Protector, Taunt
  local mine = H.Put(g, 1, "CS2_179")           -- must NOT be silenced
  local before = #g.players[1].hand

  local i = H.Hand(g, 1, "EX1_626")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.notOk(a:IsTaunt(), "first enemy minion silenced")
  H.notOk(b:IsTaunt(), "SECOND enemy minion silenced -- the loop did not abort")
  H.notOk(c:IsTaunt(), "third enemy minion silenced")
  H.ok(mine:IsTaunt(), "your own minion untouched")
  -- +1 for the Mass Dispel added, -1 for playing it, +1 for the draw
  H.eq(#g.players[1].hand, before + 1, "and the card was drawn")
  H.noEngineErrors(g)
end)

H.suite("silence op: Wailing Soul silences all your OTHER minions", function(ns, H)
  local g = H.NewGame({ class1 = "DRUID" })
  H.Mana(g, 1, 10)
  local a = H.Put(g, 1, "CS2_179")
  local b = H.Put(g, 1, "CS2_127")
  local enemy = H.Put(g, 2, "CS2_179")
  local i = H.Hand(g, 1, "FP1_016")
  H.ok(g:PlayCard(1, i))
  g.bus:Drain()
  H.notOk(a:IsTaunt(), "first friendly minion silenced")
  H.notOk(b:IsTaunt(), "SECOND friendly minion silenced")
  H.ok(enemy:IsTaunt(), "the enemy is untouched")
  H.noEngineErrors(g)
end)

--============================================================ Water Elemental

--[[ Not a Choose One card. It is here because the coverage arithmetic that
     Choose One touched is what led to it: the compiler reported 109 missing
     while the two batch worklists held 108, and the odd one out was CS2_033.

     It turned out NOT to be an unimplemented card -- it was already correct in
     Handwritten.lua -- but the coverage report could not see Handwritten.lua at
     all, so three finished cards were being reported as work to do. The report
     now reads it, and Water Elemental moved to an ordinary CSV row because the
     DSL grew the condition it needed (Snowchugger uses the same one).

     tests/test_triggers.lua already covers the core behaviour. These two cover
     what it does not, and they are what proves the move off Handwritten.lua
     kept the card working. ]]

H.suite("water elemental: another minion's damage freezes nothing", function(ns, H)
  local g = H.NewGame({ class1 = "MAGE" })
  H.Put(g, 1, "CS2_033")                       -- present but uninvolved
  local yeti = H.Put(g, 1, "CS2_182")
  local ogre = H.Put(g, 2, "CS2_200")
  g:Attack(yeti, ogre)
  g.bus:Drain()
  H.notOk(ogre.frozen, "a different attacker freezes nothing")
  H.noEngineErrors(g)
end)

H.suite("water elemental: freezes a HERO it damages too", function(ns, H)
  -- "any character", so the hero counts.
  local g = H.NewGame({ class1 = "MAGE" })
  local we = H.Put(g, 1, "CS2_033")
  g:Attack(we, H.Hero(g, 2))
  g.bus:Drain()
  H.ok(H.Hero(g, 2).frozen, "the enemy hero is frozen")
  H.noEngineErrors(g)
end)
