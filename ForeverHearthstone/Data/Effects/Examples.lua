--[[ Data/Effects/Examples.lua

  *** REFERENCE DOCUMENT -- NOT LOADED BY THE ADDON. ***
  This file is deliberately absent from the .toc. The same cards are authored
  in tools/effects.csv and compiled to Generated.lua; loading both would define
  each card twice. Read this to understand the schema, then author in the CSV.

  EIGHT WORKED EXAMPLES, ASCENDING COMPLEXITY.

  Every card id, cost, stat line and rules text below was read out of the
  pinned data (build 5834) -- none of it is recalled. The printed values live
  in PrintedCards.lua; these scripts add ONLY behaviour. If a script and the
  printed data disagree about a number, the printed data wins, always.

  A script is a table keyed by card id. Recognised keys:

    battlecry   = { ops = {...}, cond = {...} }     on play, from hand
    combo       = { ops = {...} }                   replaces battlecry if Combo
    deathrattle = { ops = {...} }                   on death
    aura        = { sel = {...}, atk=, hp=, cost=, keywords={} }
    enrage      = { atk=, hp=, keywords={} }        self-aura gated on damaged
    triggers    = { { on=EVENT, cond=, ops= }, ... }
    secret      = { on=EVENT, cond=, ops=, cancels=bool }
    spell       = { ops = {...} }                    spell resolution
    heroPower   = { ops = {...} }
    targeting   = { ... }                            overrides derived reqs

  Targeting is normally DERIVED from the printed playRequirements and needs no
  script entry at all. Only override when the data is insufficient.
]]
local ADDON, ns = ...
local E  = ns.EVENT
local KW = ns.KEYWORD
local S = ns.Scripts or {}
ns.Scripts = S

--=============================================================== 1. VANILLA
-- Chillwind Yeti (CS2_182) -- 4 mana 4/5, no text, no mechanics.
-- THERE IS NO ENTRY. This is the point: 14 cards in the pool are pure data and
-- another 55 are static-keyword-only (Taunt/Charge/Divine Shield/Windfury/
-- Stealth), which the engine reads straight off printed.keywords.
-- 69 of 379 cards cost exactly zero lines of script.
--
-- S["CS2_182"] = nil


--============================================================= 2. BATTLECRY
-- Elven Archer (CS2_189) -- 1 mana 1/1, "Battlecry: Deal 1 damage."
-- printed.reqs = { REQ_TARGET_IF_AVAILABLE, REQ_NONSELF_TARGET } so the
-- targeting UI and legality check are already generated. The script is the
-- effect and nothing else.
S["CS2_189"] = {
  battlecry = {
    ops = { { op = "Damage", sel = { target = true }, amount = 1 } },
  },
}

-- Sunfury Protector (EX1_058) -- "Battlecry: Give adjacent minions Taunt."
-- Untargeted; positional. `adjacent="SELF"` resolves against board index at
-- the moment the battlecry runs, which is after the minion has been placed --
-- so its neighbours are correct without any special casing.
S["EX1_058"] = {
  battlecry = {
    ops = {
      { op = "GiveKeyword",
        sel = { adjacent = "SELF", type = "MINION" },
        keywords = { KW.TAUNT } },
    },
  },
}

-- Defender of Argus (EX1_093) -- same shape, two ops. Note how composition
-- rather than a bespoke "buff adjacent and taunt" op keeps Ops.lua small.
S["EX1_093"] = {
  battlecry = {
    ops = {
      { op = "Buff", sel = { adjacent = "SELF", type = "MINION" },
        atk = 1, hp = 1, keywords = { KW.TAUNT } },
    },
  },
}


--=========================================================== 3. DEATHRATTLE
-- Loot Hoarder (EX1_096) -- 2 mana 2/1, "Deathrattle: Draw a card."
S["EX1_096"] = {
  deathrattle = { ops = { { op = "Draw", count = 1 } } },
}

-- Cairne Bloodhoof (EX1_110) -- summons Baine (EX1_110t, 4/5), verified id.
-- position="REPLACE_SOURCE" makes Baine appear in Cairne's slot, which matters
-- because adjacency auras must re-resolve around the new occupant.
S["EX1_110"] = {
  deathrattle = {
    ops = { { op = "Summon", cardId = "EX1_110t", position = "REPLACE_SOURCE" } },
  },
}

-- Abomination (EX1_097) -- "Taunt. Deathrattle: Deal 2 damage to ALL characters."
-- TAUNT is printed data, not script. `hero=true` widens the selector to include
-- both heroes. This is the card that proves the death phase is right: the 2
-- damage can kill other minions, whose deathrattles queue and may kill more.
-- Bus:Drain loops the death phase until the board is stable.
S["EX1_097"] = {
  deathrattle = {
    ops = { { op = "Damage", sel = { side = "ANY", hero = true }, amount = 2 } },
  },
}


--========================================================= 4. POSITIONAL AURA
-- Dire Wolf Alpha (EX1_162) -- 2 mana 2/2, "Adjacent minions have +1 Attack."
-- Declared, never applied. Recomputed from zero on every board change, so:
--   * summoning a minion next to it buffs it instantly
--   * the Wolf dying removes the buff with no bookkeeping
--   * a minion moving/being replaced re-resolves correctly
--   * silencing the Wolf drops the aura (Aura.lua skips silenced sources)
-- None of that needs a line of code here.
S["EX1_162"] = {
  aura = { sel = { adjacent = "SELF", type = "MINION" }, atk = 1 },
}

-- Timber Wolf (DS1_175) -- "Your other Beasts have +1 Attack."
-- exclude="SELF" is why two Timber Wolves buff each other but not themselves.
S["DS1_175"] = {
  aura = { sel = { side = "FRIENDLY", type = "MINION", race = "BEAST",
                   exclude = "SELF" }, atk = 1 },
}

-- Amani Berserker (EX1_393) -- "Enrage: +3 Attack".
-- Enrage is a self-aura gated on damaged, NOT a trigger. Healing it back to
-- full removes the bonus automatically; a one-shot +3 on DAMAGE_DEALT would
-- not, and that bug is invisible until someone plays a healer.
S["EX1_393"] = { enrage = { atk = 3 } }


--================================================================= 5. SECRET
-- Explosive Trap (EX1_610) -- "Secret: When your hero is attacked, deal 2
-- damage to all enemies." Fires on PRE_ATTACK so the damage lands before the
-- attack connects -- which is how a 2-health attacker dies without ever
-- dealing its damage. `cancels` is NOT set: the attack still resolves if the
-- attacker survives.
S["EX1_610"] = {
  secret = {
    on   = E.PRE_ATTACK,
    cond = { c = "PayloadTargetIsHero" },
    ops  = { { op = "Damage", sel = { side = "ENEMY", hero = true }, amount = 2 } },
  },
}

-- Snake Trap (EX1_554) -- "When one of your minions is attacked, summon three
-- 1/1 Snakes." Snake = EX1_554t, verified.
S["EX1_554"] = {
  secret = {
    on   = E.PRE_ATTACK,
    cond = { c = "Not", of = { c = "PayloadTargetIsHero" } },
    ops  = { { op = "Summon", cardId = "EX1_554t", count = 3 } },
  },
}

-- Mirror Entity (EX1_294) -- "When your opponent plays a minion, summon a copy
-- of it." Copies the PRINTED card, not the live entity: a buffed minion is
-- mirrored at its base stats, matching Hearthstone. `payload=true` selects the
-- entity that caused the event.
S["EX1_294"] = {
  secret = {
    on   = E.MINION_PLAYED,
    ops  = {
      { op = "CopyToBoard", sel = { payloadEntity = true }, fromPrinted = true },
    },
  },
}


--=============================================== 6. GNARLY: KNIFE JUGGLER
-- Knife Juggler (NEW1_019) -- 2 mana 3/2, "After you summon a minion, deal 1
-- damage to a random enemy."
--
-- WHY THIS CARD IS THE ENGINE'S ACCEPTANCE TEST:
--
-- a) The printed data has mechanics = nil. There is no TRIGGER tag. Nothing in
--    HearthstoneJSON tells you this card has a trigger -- you read the text.
--    This is exactly why the import pipeline emits printed data only and never
--    tries to infer behaviour.
--
-- b) "After you summon" fires on MINION_SUMMONED, not MINION_PLAYED, so token
--    summons (Unleash the Hounds, Animal Companion, deathrattles) trigger it.
--
-- c) The Juggler must not trigger on ITSELF being summoned. It is not yet in
--    play when its own MINION_SUMMONED fires -- Game:Summon raises the event
--    after placing the minion, so we gate on the payload instead of relying on
--    ordering. Explicit beats subtle.
--
-- d) TWO JUGGLERS THROW IN PLAY ORDER, not board order. Bus:Collect sorts by
--    playOrder. Swapping two Jugglers' positions must not change the outcome.
--
-- e) Each knife is its own damage event, and a knife can kill a minion whose
--    deathrattle summons another minion, which re-triggers the Juggler. The
--    trigger queue appends rather than interleaving, and Bus:Drain loops until
--    stable, so this terminates instead of recursing.
S["NEW1_019"] = {
  triggers = {
    { on   = E.MINION_SUMMONED,
      cond = { c = "All", of = {
                 { c = "PayloadSummonedByMe" },
                 { c = "Not", of = { c = "PayloadIsSelf" } },
             } },
      ops  = { { op = "Damage",
                 sel = { side = "ENEMY", hero = true, random = 1 },
                 amount = 1 } } },
  },
}

-- Frothing Berserker (EX1_604) -- "Whenever a minion takes damage, gain +1
-- Attack." ANY minion, either side, including itself, and once per damage
-- INSTANCE -- an area effect hitting five minions gives +5. Because the buff
-- is an enchantment (permanent) rather than an aura, it survives the damaged
-- minions dying, which is correct.
S["EX1_604"] = {
  triggers = {
    { on   = E.DAMAGE_DEALT,
      cond = { c = "PayloadIsMinion" },
      ops  = { { op = "Buff", sel = { self = true }, atk = 1 } } },
  },
}


--============================================== 7. GNARLY: MIND CONTROL
-- Mind Control (CS1_113) -- 10 mana, "Take control of an enemy minion."
-- printed.reqs already gives REQ_MINION_TARGET, REQ_ENEMY_TARGET,
-- REQ_TARGET_TO_PLAY and crucially REQ_NUM_MINION_SLOTS=1, so the engine
-- refuses to cast it on a full board with no script involvement.
--
-- The hard part is not the op, it is what ChangeController must do:
--   * move the entity between board arrays, appended RIGHTMOST on its new side
--   * leave `owner` alone (it returns to its owner on some effects) while
--     changing `controller`
--   * re-stamp nothing: playOrder is preserved, so trigger ordering is stable
--   * mark it summoning-sick this turn -- a stolen minion cannot attack the
--     turn it changes sides unless it has Charge
--   * recalc auras on BOTH boards, since it left one aura field and entered
--     another
-- All of that lives in Game:ChangeController, once, for every control effect
-- (Mind Control, Sylvanas, Shadow Madness, Mind Control Tech).
S["CS1_113"] = {
  spell = {
    ops = { { op = "TakeControl", sel = { target = true } } },
  },
}

-- Sylvanas Windrunner (EX1_016) -- "Deathrattle: Take control of a random
-- enemy minion." Same op, random selector. The subtlety: Sylvanas is already
-- in the graveyard when this runs, so her own board slot is free -- the stolen
-- minion has somewhere to go even from a full board. The death phase completing
-- before deathrattles resolve is what makes that true.
S["EX1_016"] = {
  deathrattle = {
    ops = { { op = "TakeControl",
              sel = { side = "ENEMY", type = "MINION", random = 1 } } },
  },
}


--=================================== 8. GNARLY: ORDER-SENSITIVE RANDOMNESS
-- Arcane Missiles (EX1_277) -- 1 mana, "Deal 3 damage randomly split among
-- enemy characters." Note ImmuneToSpellpower in the printed mechanics: spell
-- damage does NOT increase the missile count, and the engine reads that flag
-- off printed data rather than special-casing the card.
--
-- Three separate 1-damage hits, each re-rolling. A missile can kill a 1-health
-- minion, and the next missile must choose from the survivors. Hence
-- DamageRandomSplit calls ProcessDeaths between hits. Resolving all three
-- against a snapshot taken up front is wrong and observably so.
S["EX1_277"] = {
  spell = {
    ops = { { op = "DamageRandomSplit",
              sel = { side = "ENEMY", hero = true }, amount = 3, per = 1 } },
  },
}

-- Animal Companion (NEW1_031) -- "Summon a random Beast Companion."
-- entourage = {NEW1_032 Misha 4/4 Taunt, NEW1_033 Leokk 2/4, NEW1_034 Huffer
-- 4/2 Charge} comes from printed data. fromEntourage means this card needs no
-- hardcoded token list -- and neither will any other entourage card.
S["NEW1_031"] = {
  spell = { ops = { { op = "Summon", fromEntourage = true } } },
}

return S
