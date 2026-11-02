#!/usr/bin/env python3
"""
Forever Hearthstone - printed card data importer.

SOURCE OF TRUTH: HearthstoneJSON build 7234 (enUS), vendored at
tools/vendor/cards.7234.enUS.json.

Build 7234 is the first build containing Goblins vs Gnomes and nothing later
(no Blackrock Mountain). It is exactly the Basic + Classic + Naxxramas + GvG
state, and it carries the GvG-era balance patch: Starving Buzzard, Leeroy
Jenkins, Gadgetzan Auctioneer, Soulfire and Flare are in their nerfed form and
Adrenaline Rush is gone. That is intentional and signed off -- see
docs/00-PATCH-PIN.md and docs/04-EXPANSIONS-AND-DROPS.md.

Builds 5834 (last pre-Naxx) and 4944 (launch) remain vendored for auditing.

This script emits PRINTED data only: cost / attack / health / durability /
rarity / class / race / text / targeting requirements. It NEVER emits effect
logic -- HearthstoneJSON does not contain executable effects. Effect scripts
are hand-authored in ForeverHearthstone/Data/Effects/ and keyed by card id.

Output is generated. Do not hand-edit. Re-run to regenerate.
"""
import json, os, re, sys, collections, hashlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import chooseone

HERE   = os.path.dirname(os.path.abspath(__file__))
ROOT   = os.path.dirname(HERE)
SRC    = os.path.join(HERE, "vendor", "cards.7234.enUS.json")
BUILD  = 7234
PATCH  = "7234 (Basic + Classic + Naxxramas + Goblins vs Gnomes)"
OUT    = os.path.join(ROOT, "ForeverHearthstone", "Data", "PrintedCards.lua")

# Sets that form the recreated pool.
POOL_SETS = ("CORE", "EXPERT1", "NAXX", "GVG")
# Promo/reward sets: present in data, no acquisition path under deviation 6.
# Imported but flagged unobtainable=true so the collection layer can gate them.
FLAGGED_SETS = ("PROMO", "REWARD")

# Static keywords the engine reads as flags on the card -- zero script needed.
STATIC_KEYWORDS = {
    "TAUNT", "CHARGE", "DIVINE_SHIELD", "WINDFURY", "STEALTH", "POISONOUS",
    "CANT_ATTACK", "CANT_BE_TARGETED_BY_SPELLS",
    "CANT_BE_TARGETED_BY_HERO_POWERS", "ImmuneToSpellpower",
    # GvG: a static attack-redirect property read by Game:Attack, not scripted.
    "FORGETFUL",
}
# Keywords that imply a hand-authored effect script must exist.
SCRIPT_KEYWORDS = {"BATTLECRY", "DEATHRATTLE", "SECRET", "AURA",
                   "ADJACENT_BUFF", "COMBO", "ENRAGED", "SILENCE", "FREEZE"}

# Play requirements the vendored build leaves out, checked against the card
# text. Shadowflame ("Destroy a friendly MINION") carries only
# REQ_FRIENDLY_TARGET, so it could be aimed at your own hero.
REQ_PATCHES = {
    "EX1_303": {"REQ_MINION_TARGET": 0},
}

def strip_markup(s):
    """The card's text as Hearthstone shows it. The source carries the
    client's own markup -- [x] layout hints, <i> tags, and "$" / "#" before a
    number that spell damage or healing modifiers may change -- none of which
    is ever displayed. <b>...</b> is KEPT: it marks exactly the words
    Hearthstone sets in bold (Taunt, Battlecry:), which the card face renders
    in the bold weight (Widgets.RichText). Every other place that shows card
    text strips it (Widgets.PlainText). The effect compiler reads the
    vendored JSON itself, so nothing downstream needs the markers."""
    if not s: return None
    s = s.replace("\u00a0", " ")
    s = re.sub(r"</?i>", "", s)
    s = re.sub(r"\[x\]", "", s)
    s = re.sub(r"[$#](\d)", r"\1", s)
    s = re.sub(r"\s*\n\s*", " ", s)
    return re.sub(r"\s{2,}", " ", s).strip()

def lua_str(s):
    if s is None: return "nil"
    s = (s.replace("\\", "\\\\").replace('"', '\\"')
          .replace("\n", "\n").replace("\r", ""))
    return '"%s"' % s

def lua_list(xs):
    return "{" + ",".join(lua_str(x) for x in xs) + "}"

def main():
    if not os.path.exists(SRC):
        sys.exit("FATAL: vendored source missing: %s" % SRC)
    raw = open(SRC, "rb").read()
    digest = hashlib.sha256(raw).hexdigest()
    cards = json.loads(raw.decode("utf-8"))

    #[[ Choose One. The modes are already emitted below as ordinary tokens --
    #   they are non-collectible spells -- so the ONLY thing printed data is
    #   missing is the link from the parent to its two modes, in the order the
    #   card's own text names them. See tools/chooseone.py for why the a/b
    #   suffix is not that order. ]]
    choose_one = chooseone.find(cards)
    if len(choose_one) != chooseone.EXPECTED_IN_7234:
        sys.exit("FATAL: found %d Choose One cards, pin %d expects %d"
                 % (len(choose_one), BUILD, chooseone.EXPECTED_IN_7234))

    pool, tokens, powers, heroes = [], [], [], []
    for c in cards:
        t, s = c.get("type"), c.get("set")
        # HERO portraits carry set=CORE, so they must be classified BEFORE the
        # pool test or they get swept in as collectible cards.
        if t == "HERO":                                    heroes.append(c)
        elif t == "HERO_POWER":                            powers.append(c)
        elif c.get("collectible") and s in POOL_SETS:      pool.append(c)
        elif c.get("collectible") and s in FLAGGED_SETS:   pool.append(c)
        elif not c.get("collectible") and t in ("MINION", "SPELL", "WEAPON", "ENCHANTMENT"):
            tokens.append(c)

    lines = []
    W = lines.append
    W("-- GENERATED FILE -- DO NOT EDIT BY HAND.")
    W("-- Regenerate with: python tools/import_cards.py")
    W("-- Source: HearthstoneJSON build %d (enUS)" % BUILD)
    W("-- Patch pinned: %s" % PATCH)
    W("-- Source sha256: %s" % digest)
    W("")
    W("local ADDON, ns = ...")
    W("ns.PATCH_BUILD = %d" % BUILD)
    W('ns.PATCH_LABEL = "%s"' % PATCH)
    W('ns.DATA_SHA256 = "%s"' % digest)
    W("")
    W("-- Printed (immutable) card data. Effect logic lives in Data/Effects/.")
    W("local P = {}")
    W("ns.PrintedCards = P")
    W("")

    def emit(c, unobtainable=False):
        mech   = set(c.get("mechanics") or [])
        static = sorted(mech & STATIC_KEYWORDS)
        script = sorted(mech & SCRIPT_KEYWORDS)
        reqs   = dict(c.get("playRequirements") or {})
        reqs.update(REQ_PATCHES.get(c["id"], {}))
        dust   = c.get("dust") or []
        f = []
        a = f.append
        a("id=%s" % lua_str(c["id"]))
        a("name=%s" % lua_str(strip_markup(c.get("name"))))
        a('type="%s"' % c["type"])
        a('set="%s"' % c["set"])
        a('rarity="%s"' % c.get("rarity", "FREE"))
        a('class="%s"' % (c.get("playerClass") or "NEUTRAL"))
        if c.get("cost") is not None:       a("cost=%d" % c["cost"])
        if c.get("attack") is not None:     a("atk=%d" % c["attack"])
        if c.get("health") is not None:     a("hp=%d" % c["health"])
        if c.get("durability") is not None: a("dur=%d" % c["durability"])
        if c.get("race"):                   a('race="%s"' % c["race"])
        if c.get("overload"):               a("overload=%d" % c["overload"])
        if c.get("spellDamage"):            a("spellDamage=%d" % c["spellDamage"])
        if c.get("entourage"):              a("entourage=%s" % lua_list(c["entourage"]))
        if c["id"] in choose_one:           a("chooseOne=%s" % lua_list(choose_one[c["id"]]))
        if static:  a("keywords=%s" % lua_list(static))
        if script:  a("scriptTags=%s" % lua_list(script))
        if reqs:
            a("reqs={%s}" % ",".join("%s=%d" % (k, v) for k, v in sorted(reqs.items())))
        # dust = [craft, craftGolden, disenchant, disenchantGolden]; absent for Basic.
        if len(dust) == 4:
            a("dustHS={%d,%d,%d,%d}" % tuple(dust))
        a("text=%s" % lua_str(strip_markup(c.get("text"))))
        if c.get("collectible"): a("collectible=true")
        if unobtainable: a("unobtainable=true")
        return "P[%s]={%s}" % (lua_str(c["id"]), ",".join(f))

    W("-- === COLLECTIBLE POOL (%d) ===" % len(pool))
    for c in sorted(pool, key=lambda c: (c["set"], c.get("playerClass") or "NEUTRAL", c["id"])):
        W(emit(c, unobtainable=c["set"] in FLAGGED_SETS))
    W("")
    W("-- === HERO PORTRAITS (%d) ===" % len(heroes))
    for c in sorted(heroes, key=lambda c: c["id"]): W(emit(c))
    W("")
    W("-- === HERO POWERS (%d) ===" % len(powers))
    for c in sorted(powers, key=lambda c: c["id"]): W(emit(c))
    W("")
    W("-- === TOKENS / GENERATED (%d) -- summon & transform targets ===" % len(tokens))
    for c in sorted(tokens, key=lambda c: c["id"]): W(emit(c))
    W("")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")

    # ---- report ----
    scripted = [c for c in pool
                if (set(c.get("mechanics") or []) & SCRIPT_KEYWORDS)
                or c["type"] == "SPELL"
                or (c.get("text") and c["type"] in ("MINION", "WEAPON"))]
    print("wrote %s" % os.path.relpath(OUT, ROOT))
    print("  source sha256 : %s" % digest)
    print("  pool          : %d  (CORE+EXPERT1 collectible: %d, flagged promo/reward: %d)"
          % (len(pool),
             sum(1 for c in pool if c["set"] in POOL_SETS),
             sum(1 for c in pool if c["set"] in FLAGGED_SETS)))
    print("  heroes        : %d" % len(heroes))
    print("  hero powers   : %d" % len(powers))
    print("  tokens        : %d" % len(tokens))
    print("  choose one    : %d parents, %d modes" % (len(choose_one), 2 * len(choose_one)))
    print("  need effect script : %d" % len(scripted))
    print("  pure data (no script): %d" % (len(pool) - len(scripted)))
    by = collections.Counter((c["set"], c.get("playerClass") or "NEUTRAL") for c in pool)
    print("  breakdown:")
    for k in sorted(by): print("    %-9s %-9s %d" % (k[0], k[1], by[k]))

if __name__ == "__main__":
    main()
