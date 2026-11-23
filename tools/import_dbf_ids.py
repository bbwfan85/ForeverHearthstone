#!/usr/bin/env python3
"""
Forever Hearthstone - DBF ids for deck codes (docs/45-LADDER-DECKCODES-BULK-PACKS.md).

Hearthstone's deck codes (the HearthSim "deckstring" spec) name cards by their
numeric DBF id, not by the CardID string the rest of the addon uses. The
vendored HearthstoneJSON build 7234 predates the dbfId field, so the ids come
from Blizzard's CardDefs.xml, as shipped by python-hearthstone's
`hearthstone_data` package (the Fireplace oracle venv already has it).

Two steps, so a normal build never needs the oracle venv:

  --refresh   read CardDefs.xml and rewrite tools/vendor/dbf-ids.json
              (then update tools/vendor/SHA256SUMS)
  (default)   read tools/vendor/dbf-ids.json, emit Data/DbfIds.lua

ALIASES. Modern Hearthstone reprinted the 2014 cards under new ids (Legacy
kept the originals; Core 2021 and the Classic format got CORE_/VAN_ copies with
new DBF ids). A deck code copied from today's client for a deck of these cards
can therefore name a reprint. Any collectible card whose English name and class
match a pinned collectible card is accepted as that card on import. Export
always writes the original id, which today's client still reads (Wild).
"""
import json, os, sys, hashlib
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VENDOR = os.path.join(HERE, "vendor", "dbf-ids.json")
PRINTED_JSON = os.path.join(HERE, "vendor", "cards.7234.enUS.json")
OUT = os.path.join(ROOT, "ForeverHearthstone", "Data", "DbfIds.lua")
XML = os.path.expanduser(
    "~/.cache/forever-hearthstone-oracle/venv/Lib/site-packages/hearthstone_data/CardDefs.xml")

POOL_SETS = ("CORE", "EXPERT1", "NAXX", "GVG")
CLASS_ENUM = {2: "DRUID", 3: "HUNTER", 4: "MAGE", 5: "PALADIN", 6: "PRIEST",
              7: "ROGUE", 8: "SHAMAN", 9: "WARLOCK", 10: "WARRIOR", 12: "NEUTRAL"}
HEROES = {"HERO_01": "WARRIOR", "HERO_02": "SHAMAN", "HERO_03": "ROGUE",
          "HERO_04": "PALADIN", "HERO_05": "HUNTER", "HERO_06": "DRUID",
          "HERO_07": "WARLOCK", "HERO_08": "MAGE", "HERO_09": "PRIEST"}


def pinned():
    cards = json.load(open(PRINTED_JSON, encoding="utf8"))
    out = {}
    for c in cards:
        if c.get("collectible") and c.get("set") in POOL_SETS and c.get("type") != "HERO":
            out[c["id"]] = (c["name"], (c.get("playerClass") or "NEUTRAL").upper())
    return out


def refresh():
    pool = pinned()
    by_name = {}
    for cid, (name, cls) in pool.items():
        by_name[(name, cls)] = cid
    canonical, aliases, heroes, hero_for = {}, {}, {}, {}
    for _, ent in ET.iterparse(XML):
        if ent.tag != "Entity":
            continue
        cid, dbf = ent.get("CardID"), int(ent.get("ID"))
        tags = {}
        name = None
        for t in ent.findall("Tag"):
            if t.get("name") == "CARDNAME":
                e = t.find("enUS")
                name = e.text if e is not None else None
            elif t.get("value") is not None:
                try:
                    tags[t.get("name")] = int(t.get("value"))
                except ValueError:
                    pass
        cls = CLASS_ENUM.get(tags.get("CLASS"))
        if cid in pool:
            canonical[cid] = dbf
        elif cid in HEROES:
            heroes[str(dbf)] = HEROES[cid]
            hero_for[HEROES[cid]] = dbf
        elif tags.get("CARDTYPE") == 3 and cls and cls != "NEUTRAL" and cid.startswith("HERO_") \
                and tags.get("COLLECTIBLE") == 1:
            heroes[str(dbf)] = cls          # alternate hero portraits
        elif tags.get("COLLECTIBLE") == 1 and name and (name, cls) in by_name:
            aliases[str(dbf)] = by_name[(name, cls)]
        ent.clear()
    missing = sorted(set(pool) - set(canonical))
    if missing:
        sys.exit("no DBF id for: " + ", ".join(missing))
    data = {"source": "hearthstone_data CardDefs.xml", "canonical": canonical,
            "aliases": aliases, "heroes": heroes, "heroFor": hero_for}
    with open(VENDOR, "w", encoding="utf8", newline="\n") as f:
        # one line: a multi-line file is rewritten by Git's line-ending
        # conversion on Windows clones, and its checksum would then fail
        f.write(json.dumps(data, sort_keys=True, separators=(",", ":")))
    print("wrote %s: %d cards, %d aliases, %d heroes" % (VENDOR, len(canonical), len(aliases), len(heroes)))
    print("sha256", hashlib.sha256(open(VENDOR, "rb").read()).hexdigest())


def emit():
    data = json.load(open(VENDOR, encoding="utf8"))
    lines = ["-- GENERATED FILE -- DO NOT EDIT BY HAND.",
             "-- Regenerate with: python tools/import_dbf_ids.py (source: tools/vendor/dbf-ids.json)",
             "-- Hearthstone DBF ids, for deck codes (Client/DeckCode.lua).",
             "local ADDON, ns = ...",
             "local D = { byCard = {}, card = {}, hero = {} }",
             "ns.DbfIds = D"]
    canon = data["canonical"]
    lines.append("local c = D.byCard")
    for cid in sorted(canon):
        lines.append('c["%s"]=%d' % (cid, canon[cid]))
    lines.append("for id, dbf in pairs(c) do D.card[dbf] = id end")
    lines.append("local a = D.card")
    for dbf in sorted(data["aliases"], key=int):
        lines.append('a[%s]="%s"' % (dbf, data["aliases"][dbf]))
    lines.append("local h = D.hero")
    for dbf in sorted(data["heroes"], key=int):
        lines.append('h[%s]="%s"' % (dbf, data["heroes"][dbf]))
    # the hero each class exports as: the original nine
    lines.append("D.heroFor = {")
    for cls in sorted(data["heroFor"]):
        lines.append("  %s=%d," % (cls, data["heroFor"][cls]))
    lines.append("}")
    lines.append("return D")
    with open(OUT, "w", encoding="utf8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote %s" % OUT)


if __name__ == "__main__":
    if "--refresh" in sys.argv:
        refresh()
    emit()
