#!/usr/bin/env python3
"""
Forever Hearthstone - more ladder decks (docs/45).

Reads tools/bot-decks-extra.txt -- decklists written by card NAME, as a player
would write them --

    ## MAGE 1 aggro Basic Aggro Mage
    2 Arcane Missiles
    1 Fireball
    ...

resolves every name against the pinned card data (HearthstoneJSON 7234, the
Basic/Classic/Naxx/GvG pool), checks each list is a legal deck for its class
(30 cards, two of a card, one of a legendary, collectible, the class's own or
neutral), checks a tier-1 list is Basic cards only and a tier-2 list has no
legendaries, and writes Client/BotDecksExtra.lua. Any problem stops the build.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(HERE, "bot-decks-extra.txt")
CARDS = os.path.join(HERE, "vendor", "cards.7234.enUS.json")
OUT = os.path.join(ROOT, "ForeverHearthstone", "Client", "BotDecksExtra.lua")
POOL = ("CORE", "EXPERT1", "NAXX", "GVG")
CLASSES = ("DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR")
STYLES = ("aggro", "midrange", "control")


def main():
    by_name = {}
    for c in json.load(open(CARDS, encoding="utf8")):
        if c.get("collectible") and c.get("set") in POOL and c.get("type") != "HERO":
            by_name[c["name"].lower()] = c
    decks, cur, errors = [], None, []
    for ln, line in enumerate(open(SRC, encoding="utf8"), 1):
        line = line.strip()
        if not line or line.startswith("#") and not line.startswith("##"):
            continue
        if line.startswith("##"):
            parts = line[2:].split(None, 3)
            if len(parts) < 4 or parts[0] not in CLASSES or parts[2] not in STYLES:
                errors.append("line %d: bad header %r" % (ln, line)); cur = None; continue
            cur = {"class": parts[0], "tier": int(parts[1]), "style": parts[2], "name": parts[3], "cards": {}, "line": ln}
            decks.append(cur)
            continue
        m = re.match(r"^(\d+)\s+(.+)$", line)
        if not m or cur is None:
            errors.append("line %d: %r" % (ln, line)); continue
        n, name = int(m.group(1)), m.group(2).strip()
        c = by_name.get(name.lower())
        if not c:
            errors.append("line %d: no card named %r" % (ln, name)); continue
        cur["cards"][c["id"]] = cur["cards"].get(c["id"], 0) + n
        cur.setdefault("names", {})[c["id"]] = c["name"]
    ids = {c["id"]: c for c in by_name.values()}
    for d in decks:
        total = sum(d["cards"].values())
        if total != 30:
            errors.append("%s: %d cards" % (d["name"], total))
        for cid, n in d["cards"].items():
            c = ids[cid]
            cls = (c.get("playerClass") or "NEUTRAL").upper()
            if cls not in ("NEUTRAL", d["class"]):
                errors.append("%s: %s is %s" % (d["name"], c["name"], cls))
            limit = 1 if c.get("rarity") == "LEGENDARY" else 2
            if n > limit:
                errors.append("%s: %d x %s" % (d["name"], n, c["name"]))
            if d["tier"] == 1 and c.get("set") != "CORE":
                errors.append("%s: tier 1 is Basic only, not %s" % (d["name"], c["name"]))
            if d["tier"] == 2 and c.get("rarity") == "LEGENDARY":
                errors.append("%s: a budget deck has no legendary (%s)" % (d["name"], c["name"]))
    if errors:
        sys.exit("\n".join(errors))
    out = ["-- GENERATED FILE -- DO NOT EDIT BY HAND.",
           "-- Regenerate with: python tools/build_bot_decks.py (source: tools/bot-decks-extra.txt)",
           "-- More ladder decks, so every class has several at every tier (docs/45).",
           "local ADDON, ns = ...",
           "local add = ns.BotDecks.Add"]
    for d in decks:
        out.append('add("%s", %d, "%s", "%s", {' % (d["class"], d["tier"], d["style"], d["name"].replace('"', '\\"')))
        for cid in sorted(d["cards"]):
            out.append('  ["%s"] = %d, -- %s' % (cid, d["cards"][cid], d["names"][cid]))
        out.append("})")
    with open(OUT, "w", encoding="utf8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    count = {}
    for d in decks:
        count[(d["class"], d["tier"])] = count.get((d["class"], d["tier"]), 0) + 1
    print("wrote %s: %d decks" % (OUT, len(decks)))


if __name__ == "__main__":
    main()
