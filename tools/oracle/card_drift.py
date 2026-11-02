"""Compare the pinned card data (build 7234) with Fireplace's card data.

Fireplace is at patch 17.6 (2020), six years of balance changes past the pin.
A differential test is only meaningful where both engines are playing the same
printed card, so this sorts every card the engine knows into:

  same       identical cost/stats/text -- compared as is
  stats      only cost/attack/health/durability moved -- Fireplace is patched
             back to the pinned numbers before each scenario (see oracle.py)
  reworked   the TEXT changed -- a different card; scenarios using it are
             skipped, because any difference would be the rework, not a bug
  missing    Fireplace has no card by that id

Run inside the oracle venv (see docs/33-FIREPLACE-ORACLE.md). Writes
tools/oracle/drift.json, which oracle.py reads.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PIN = os.path.join(ROOT, "tools", "vendor", "cards.7234.enUS.json")
OUT = os.path.join(ROOT, "tools", "oracle", "drift.json")


# Text changed, behaviour did not: Blizzard rewrote the wording (Enrage became
# "while damaged", "destroy any minion damaged by this" became Poisonous, and
# so on). Checked by reading both texts; compared as "same" or "stats".
WORDING_ONLY = {
    "CS2_221", "EX1_009", "EX1_390", "EX1_393", "EX1_412", "EX1_414", "GVG_051",  # Enrage
    "EX1_170", "FP1_010", "EX1_522",                                            # Poisonous
    "CS2_005", "EX1_570",               # Claw, Bite: "and N Armor" / "Gain N Armor"
    "DS1_184", "EX1_005", "EX1_622", "EX1_339", "EX1_304", "EX1_539",
    "EX1_611", "EX1_613", "EX1_533", "EX1_136", "EX1_277", "EX1_384",
    "GVG_111t", "GVG_113", "GVG_117", "NEW1_010", "NEW1_033",
    # Reworded, and Fireplace's current script already does what the 2014 text
    # says (checked against its source): Druid of the Claw always transformed;
    # Tidecaller/Cult Master/Illidan/Ship's Cannon keep "whenever" (.on)
    # timing; Fel Reaver "discards" = mills; Burrowing Mine explodes on draw
    # and replaces itself; Parrot/Sense Demons pull from the deck; Ysera's
    # Dream card is random either way.
    "EX1_165", "EX1_165b", "EX1_509", "EX1_595", "EX1_614", "GVG_016", "GVG_056t",
    "GVG_075", "NEW1_016", "EX1_317", "EX1_572",
}


def norm_text(s):
    s = (s or "").lower()
    s = re.sub(r"<[^>]+>", "", s)          # <b>, <i>
    s = re.sub(r"\[x\]", "", s)
    s = s.replace("$", "").replace("#", "")
    s = s.replace("_", " ")                # Fireplace's "enemy_hero" style
    s = re.sub(r"[^a-z0-9+]+", " ", s)
    return s.strip()


def main():
    from fireplace import cards
    cards.db.initialize()
    db = cards.db
    pin = json.load(open(PIN, encoding="utf-8"))
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from shims import SHIMMED
    out = {"same": [], "stats": {}, "reworked": {}, "missing": [], "shimmed": {}}
    for c in pin:
        cid = c["id"]
        if c.get("type") == "ENCHANTMENT":
            continue
        if cid not in db:
            out["missing"].append(cid)
            continue
        f = db[cid]
        if cid in SHIMMED:
            # text is ours; the numbers are still patched to the pin
            out["shimmed"][cid] = {"name": c.get("name"), "text": c.get("text"),
                                   "pin": {"cost": c.get("cost", 0), "atk": c.get("attack", 0),
                                           "health": c.get("health", 0),
                                           "durability": c.get("durability", 0)}}
            continue
        if cid not in WORDING_ONLY and norm_text(c.get("text")) != norm_text(f.description):
            out["reworked"][cid] = {"name": c.get("name"), "pin": c.get("text"), "fireplace": f.description}
            continue
        want = {"cost": c.get("cost", 0), "atk": c.get("attack", 0),
                "health": c.get("health", 0), "durability": c.get("durability", 0)}
        have = {"cost": f.cost, "atk": f.atk, "health": f.health,
                "durability": getattr(f, "durability", 0) or 0}
        if c.get("type") == "WEAPON":
            want["health"] = have["health"] = 0
        if want != have:
            out["stats"][cid] = {"name": c.get("name"), "pin": want, "fireplace": have}
        else:
            out["same"].append(cid)
    out["same"].sort(); out["missing"].sort()
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, sort_keys=True)
    print("same %d  stats-only %d  shimmed %d  reworked %d  missing %d  -> %s" % (
        len(out["same"]), len(out["stats"]), len(out["shimmed"]), len(out["reworked"]), len(out["missing"]),
        os.path.relpath(OUT, ROOT)))


if __name__ == "__main__":
    sys.exit(main())
