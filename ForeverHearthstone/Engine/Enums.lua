--[[ Engine/Enums.lua
  Pure data. NO WoW API references anywhere in Engine/ -- the engine must load
  under standalone Lua 5.1 for headless testing. This is a hard rule: if you
  need a WoW API, it belongs in Client/, not Engine/.
]]
local ADDON, ns = ...
ns = ns or {}

ns.RULES = {
  START_HEALTH      = 30,
  MAX_HEALTH        = 30,
  MANA_CAP          = 10,
  BOARD_SLOTS       = 7,
  HAND_LIMIT        = 10,
  DECK_SIZE         = 30,
  MAX_COPIES        = 2,
  MAX_COPIES_LEG    = 1,
  MULLIGAN_FIRST    = 3,
  MULLIGAN_SECOND   = 4,
  SECRET_SLOTS      = 5,
  --[[ Hearthstone's turn limit: a game still going when the 89th turn ends is
       a draw. Two players who can no longer hurt each other (fatigue aside,
       Alexstrasza loops, healing decks) would otherwise sit there forever. ]]
  TURN_LIMIT        = 89,
  FATIGUE_START     = 1,
  MAX_MINION_ATTACK_PER_TURN = 1,   -- 2 with Windfury
  TURN_SECONDS      = 75,
  ROPE_SECONDS      = 15,           -- rope appears at 15s remaining
  --[[ The mulligan is not a turn and does not get a turn's clock. It is one
       decision taken by both players at once, with nothing to sequence, so it
       is shorter -- and it needs a deadline at all because a player who walks
       away during it stalls the other one completely. ]]
  MULLIGAN_SECONDS  = 45,
}

ns.ZONE = {
  DECK="DECK", HAND="HAND", PLAY="PLAY", GRAVEYARD="GRAVEYARD",
  SECRET="SECRET", WEAPON="WEAPON", HERO="HERO", HERO_POWER="HERO_POWER",
  SETASIDE="SETASIDE",
}

ns.CARDTYPE = {
  MINION="MINION", SPELL="SPELL", WEAPON="WEAPON",
  HERO="HERO", HERO_POWER="HERO_POWER", ENCHANTMENT="ENCHANTMENT",
}

-- Static keywords: flags on the entity, no script required.
ns.KEYWORD = {
  TAUNT="TAUNT", CHARGE="CHARGE", DIVINE_SHIELD="DIVINE_SHIELD",
  WINDFURY="WINDFURY", STEALTH="STEALTH", POISONOUS="POISONOUS",
  CANT_ATTACK="CANT_ATTACK",
  CANT_BE_TARGETED_BY_SPELLS="CANT_BE_TARGETED_BY_SPELLS",
  CANT_BE_TARGETED_BY_HERO_POWERS="CANT_BE_TARGETED_BY_HERO_POWERS",
  ImmuneToSpellpower="ImmuneToSpellpower",
  FROZEN="FROZEN", IMMUNE="IMMUNE", ELUSIVE="ELUSIVE",
  -- GvG additions. FORGETFUL is static (Game:Attack reads it to redirect).
  -- TOPDECK fires on draw, through Game:FireOnDraw.
  FORGETFUL="FORGETFUL", TOPDECK="TOPDECK",
}

-- Events. Naming: PRE_* is cancellable, POST_* is observational.
-- Secrets hook these; so do triggered minions.
ns.EVENT = {
  -- turn structure
  GAME_START="GAME_START", TURN_BEGIN="TURN_BEGIN", TURN_END="TURN_END",
  MANA_GAINED="MANA_GAINED",
  -- cards
  PRE_CARD_PLAYED="PRE_CARD_PLAYED",     -- cancellable (Counterspell)
  CARD_PLAYED="CARD_PLAYED",
  CARD_DRAWN="CARD_DRAWN", CARD_DISCARDED="CARD_DISCARDED",
  -- a card that would have entered a full hand and was destroyed instead
  -- (not a draw: nothing triggers on it; the client shows it burn)
  CARD_BURNED="CARD_BURNED",
  SPELL_CAST="SPELL_CAST",
  -- after the spell's own text has resolved ("After you cast a spell": Wild
  -- Pyromancer). SPELL_CAST's "whenever" triggers resolve BEFORE the text.
  SPELL_RESOLVED="SPELL_RESOLVED",
  -- minions
  MINION_SUMMONED="MINION_SUMMONED",     -- any way it hit the board
  MINION_PLAYED="MINION_PLAYED",         -- from hand specifically
  -- after the battlecry: "After your opponent plays a minion" (Snipe, Mirror
  -- Entity, Repentance see what the battlecry did)
  AFTER_MINION_PLAYED="AFTER_MINION_PLAYED",
  BATTLECRY_RESOLVED="BATTLECRY_RESOLVED",
  -- combat
  PRE_ATTACK="PRE_ATTACK",               -- cancellable (Freezing Trap)
  ATTACK_DECLARED="ATTACK_DECLARED",
  ATTACK_RESOLVED="ATTACK_RESOLVED",
  -- damage & death
  PRE_DAMAGE="PRE_DAMAGE",               -- mutable amount (Divine Shield, Armor)
  DAMAGE_DEALT="DAMAGE_DEALT",
  -- Siege Engine: nothing raised an armor event before it needed one.
  ARMOR_GAINED="ARMOR_GAINED",
  HEALED="HEALED",
  HERO_ATTACKED="HERO_ATTACKED",
  MINION_DIED="MINION_DIED",
  DEATHRATTLE="DEATHRATTLE",
  SILENCED="SILENCED",
  -- board shape
  BOARD_CHANGED="BOARD_CHANGED",         -- drives aura recalculation
  SECRET_REVEALED="SECRET_REVEALED",
  FATIGUE="FATIGUE",
  GAME_OVER="GAME_OVER",
}

--[[ Durations for timed enchantments.

     END_OF_TURN            -- "this turn". Expires when the CURRENT turn ends,
                               whoever's turn that is. Rockbiter, Savage Roar,
                               Bloodlust, Heroic Strike, Claw, Bite, Bestial
                               Wrath, Abusive Sergeant, Dark Iron Dwarf,
                               Shrinkmeister, Seal of Light, Mana Addict,
                               Shapeshift.
     START_OF_YOUR_NEXT_TURN -- "until your next turn". Survives the opponent's
                               whole turn, which is the entire point (Conceal
                               protects your minions through their attacks), and
                               drops when the applier's next turn begins.
                               Conceal, Finicky Cloakfield.
]]
ns.DURATION = {
  END_OF_TURN             = "END_OF_TURN",
  START_OF_YOUR_NEXT_TURN = "START_OF_YOUR_NEXT_TURN",
}

--- Does a printed card carry this static keyword? Shared helper so the check is
--- written once; printed.keywords is a plain array, not a set.
function ns.HasPrintedKeyword(printed, kw)
  if not printed or not printed.keywords then return false end
  for _, k in ipairs(printed.keywords) do
    if k == kw then return true end
  end
  return false
end

ns.CLASSES = {
  "DRUID","HUNTER","MAGE","PALADIN","PRIEST","ROGUE","SHAMAN","WARLOCK","WARRIOR"
}
ns.HERO_POWER_BY_CLASS = {
  DRUID="CS2_017", HUNTER="DS1h_292", MAGE="CS2_034", PALADIN="CS2_101",
  PRIEST="CS1h_001", ROGUE="CS2_083b", SHAMAN="CS2_049", WARLOCK="CS2_056",
  WARRIOR="CS2_102",
}

-- The nine hero portraits, verified against the pinned build. These are the
-- 1:1 mapping onto WoW's nine vanilla classes that the class-locking
-- deviation relies on.
ns.HERO_ID_BY_CLASS = {
  WARRIOR="HERO_01", SHAMAN="HERO_02",  ROGUE="HERO_03",
  PALADIN="HERO_04", HUNTER="HERO_05",  DRUID="HERO_06",
  WARLOCK="HERO_07", MAGE="HERO_08",    PRIEST="HERO_09",
}

return ns
