"""The 2014 (build 7234) versions of cards Blizzard has since reworked, for
Fireplace.

Fireplace follows patch 17.6, so its Holy Nova hits only minions and its Snipe
fires after the minion is played. Scenarios using a reworked card would compare
two different cards. This module puts the pinned version into Fireplace's card
database under the pinned id, so those scenarios can run:

  ALIASES  Fireplace already has the old card, under another id ("Innervate
           (Old)" is VAN_EX1_169). Its script is merged under the pinned id.
  SHIMS    no old version exists, so one is written here in Fireplace's own
           card language. The Fireplace rules engine still resolves it -- only
           the card text is ours -- but a shim is less independent than a card
           Fireplace wrote, and docs/33 lists them.

card_drift.py reads SHIMMED (every id handled here) and files those cards under
"shimmed" instead of "reworked", so they are compared rather than skipped.
Fireplace-side ids produced by an alias (a VAN_ token) are mapped back to the
pinned id in snapshots through REVERSE.
"""
ALIASES = {
    "EX1_145": "VAN_EX1_145",      # Preparation: (3) less
    "EX1_169": "VAN_EX1_169",      # Innervate: 2 crystals
    "CS2_103": "VAN_CS2_103",      # Charge: +2 Attack and Charge
    "NEW1_008": "VAN_NEW1_008",    # Ancient of Lore: draw 2
    "NEW1_008a": "VAN_NEW1_008a",
    "EX1_571": "VAN_EX1_571",      # Force of Nature: Charge Treants that die
    "EX1_tk9": "VAN_EX1_tk9b",
    "CS2_233": "VAN_CS2_233",      # Blade Flurry: all enemies
    "EX1_089": "VAN_EX1_089",      # Arcane Golem: Charge
    "NEW1_014": "VAN_NEW1_014",    # Master of Disguise: permanent Stealth
    "EX1_084": "FIREPLACE_EX1_084",  # Warsong Commander: Charge to 3-Attack summons
}

REVERSE = {v: k for k, v in ALIASES.items()}


def _shims():
    """Built lazily: the DSL names only exist once Fireplace is imported."""
    from hearthstone.enums import GameTag
    from fireplace.enums import PlayReq
    from fireplace.cards.utils import (
        ALL_MINIONS, ALL_CHARACTERS, CONTROLLER, Buff, Damage, Destroy, Draw,
        ENEMY_CHARACTERS, FRIENDLY_CHARACTERS, FRIENDLY_HERO, Heal, Hit, MINION,
        MURLOC, OPPONENT, Play, RANDOM_ENEMY_CHARACTER, Refresh, Reveal, SELF,
        Summon, TARGET, buff, DEATHRATTLE,
    )
    from fireplace.dsl.copy import ExactCopy

    class CS1_112:  # Holy Nova: "Deal 2 damage to all enemies. Restore 2 Health to all friendly characters."
        play = Hit(ENEMY_CHARACTERS, 2), Heal(FRIENDLY_CHARACTERS, 2)

    class CS1_130:  # Holy Smite: "Deal 2 damage." -- any character
        requirements = {PlayReq.REQ_TARGET_TO_PLAY: 0}
        play = Hit(TARGET, 2)

    class CS2_004:  # Power Word: Shield: "+2 Health. Draw a card."
        requirements = {PlayReq.REQ_MINION_TARGET: 0, PlayReq.REQ_TARGET_TO_PLAY: 0}
        play = Buff(TARGET, "CS2_004e"), Draw(CONTROLLER)

    class EX1_103:  # Coldlight Seer: "Give ALL other Murlocs +2 Health."
        play = Buff(ALL_MINIONS + MURLOC - SELF, "EX1_103e")

    class EX1_294:  # Mirror Entity: "When your opponent plays a minion" -- before its Battlecry
        secret = Play(OPPONENT, MINION).on(Reveal(SELF), Summon(CONTROLLER, ExactCopy(Play.CARD)))

    class EX1_366:  # Sword of Justice: "Whenever you summon a minion"
        events = Summon(CONTROLLER, MINION).on(Buff(Summon.CARD, "EX1_366e"), Hit(SELF, 1))

    class EX1_379:  # Repentance: "When your opponent plays a minion"
        secret = Play(OPPONENT, MINION).on(Reveal(SELF), Buff(Play.CARD, "EX1_379e"))

    class EX1_507:  # Murloc Warleader: "ALL other Murlocs have +2/+1."
        update = Refresh(ALL_MINIONS + MURLOC - SELF, buff="OLD_EX1_507e")

    class EX1_508:  # Grimscale Oracle: "ALL other Murlocs have +1 Attack."
        update = Refresh(ALL_MINIONS + MURLOC - SELF, buff="EX1_508o")

    class EX1_609:  # Snipe: "When your opponent plays a minion, deal 4 damage to it."
        secret = Play(OPPONENT, MINION).on(Reveal(SELF), Hit(Play.CARD, 4))

    class FP1_028:  # Undertaker: "+1/+1" per Deathrattle minion summoned
        events = Summon(CONTROLLER, MINION + DEATHRATTLE).on(Buff(SELF, "OLD_FP1_028e"))

    class GVG_018:  # Mistress of Pain: "Whenever this minion deals damage, restore that much Health to your hero."
        events = Damage(ALL_CHARACTERS, None, SELF).on(Heal(FRIENDLY_HERO, Damage.AMOUNT))
        tags = {GameTag.LIFESTEAL: False}

    class GVG_072:  # Shadowboxer: "Whenever a CHARACTER is healed"
        events = Heal(ALL_CHARACTERS).on(Hit(RANDOM_ENEMY_CHARACTER, 1))

    class NEW1_003:  # Sacrificial Pact: "Destroy a Demon" -- either side's
        requirements = {PlayReq.REQ_TARGET_TO_PLAY: 0, PlayReq.REQ_TARGET_WITH_RACE: 15}
        play = Destroy(TARGET), Heal(FRIENDLY_HERO, 5)

    shims = {k: v for k, v in locals().items() if isinstance(v, type) and k in SHIMMED}
    from hearthstone.enums import CardType

    def enchant(name, atk, health):
        return type(name, (), {"tags": {GameTag.CARDNAME: name, GameTag.CARDTYPE: CardType.ENCHANTMENT,
                                        GameTag.ATK: atk, GameTag.HEALTH: health}})
    buffs = {"OLD_EX1_507e": enchant("OLD_EX1_507e", 2, 1),
             "OLD_FP1_028e": enchant("OLD_FP1_028e", 1, 1)}
    return shims, buffs


SHIMMED = set(ALIASES) | {
    "CS1_112", "CS1_130", "CS2_004", "EX1_103", "EX1_294", "EX1_366", "EX1_379",
    "EX1_507", "EX1_508", "EX1_609", "FP1_028", "GVG_018", "GVG_072", "NEW1_003",
}


def apply(db):
    """Install the aliases and shims into an initialised Fireplace db."""
    from fireplace.cards import CardDB
    from fireplace.cards import custom
    for pid, fid in ALIASES.items():
        cls = getattr(custom, fid)
        db[pid] = CardDB.merge(pid, db[pid], cardscript=cls)
    shims, buffs = _shims()
    for bid, cls in buffs.items():
        db[bid] = CardDB.merge(bid, None, cls)
    for pid, cls in shims.items():
        db[pid] = CardDB.merge(pid, db[pid], cardscript=cls)
