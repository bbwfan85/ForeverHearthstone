--[[ Data/Effects/Handwritten.lua

  Cards whose scripts use engine features the CSV DSL cannot yet express.
  Loaded AFTER Generated.lua, so entries here override the compiled ones.

  KEEP THIS FILE SMALL. Every entry is a signal that the DSL is missing a
  feature. If a shape appears here three times, extend tools/compile_effects.py
  instead and delete the entries. The value of the pipeline is that it stays the
  default path, not that it is the only one.

  Note that none of these need new ENGINE features -- the ops already exist.
  The gap is purely in the terse authoring grammar.
]]
local ADDON, ns = ...
local S = ns.Scripts or {}
ns.Scripts = S

-- Prophet Velen (EX1_350) -- "Double the damage and healing of your spells and
-- Hero Power." Read by Game:SpellMultiplier, which walks friendly minions and
-- multiplies their declared spellMultiplier values together. Declaring it as
-- data rather than special-casing Velen in DealDamage means the rule
-- generalises for free.
S["EX1_350"] = { spellMultiplier = 2 }

-- Lightspawn (EX1_335) -- "This minion's Attack is always equal to its Health."
-- Read by Entity:Attack, which returns Health and ignores every Attack layer:
-- an Attack buff lands and does nothing (hearthstone.wiki.gg/wiki/Lightspawn).
-- It was a self-aura of +Health Attack, which ADDED to Blessing of Might and
-- Dire Wolf Alpha instead of overriding them. Not expressible in the DSL.
S["EX1_335"] = { attackEqualsHealth = true }

-- Poison Seeds (FP1_019) -- every death settles (deathrattles too), then one
-- Treant per destroyed minion on its side. See Ops.DestroyAndReplace.
S["FP1_019"] = {
  spell = { ops = { { op = "DestroyAndReplace", sel = { side = "ANY", type = "MINION" }, cardId = "FP1_019t" } } },
}

-- Unleash the Hounds (EX1_538) -- "For each enemy minion, summon a 1/1 Hound
-- with Charge." The count is dynamic. The ops already support this via
-- amount={count=selector}; the DSL has no syntax for a counted Repeat yet.
-- Hound = EX1_538t (1/1 Charge), verified against pinned data.
S["EX1_538"] = {
  spell = {
    ops = {
      { op = "Repeat",
        amount = { count = { side = "ENEMY", type = "MINION" } },
        ops = { { op = "Summon", cardId = "EX1_538t" } } },
    },
  },
}

-- Water Elemental (CS2_033) USED TO LIVE HERE. The DSL has since grown the
-- PayloadSourceIsSelf condition -- Snowchugger (GVG_002) is authored with it in
-- tools/effects/round2_classes.csv -- so the card is now an ordinary CSV row and
-- this entry was deleted, exactly as the note at the top of this file asks.

return S
