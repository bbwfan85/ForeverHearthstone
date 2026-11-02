"""Differential test: play the same scenarios in this engine and in Fireplace.

Fireplace (github.com/jleclanche/fireplace) is an independent Python
reimplementation of Hearthstone. Where the two engines agree, neither is likely
wrong; where they disagree, one of them is -- and the scenario says which
question to go and settle. It is a LOCAL development tool: nothing here is
loaded by the addon or packaged in a release.

    ~/.cache/forever-hearthstone-oracle/venv/Scripts/python tools/oracle/oracle.py [filter]

Setup, and how to read the report: docs/33-FIREPLACE-ORACLE.md.

Scenarios live in tools/oracle/scenarios/*.json. A scenario states both sides'
boards, hands, decks, weapons, secrets and mana, then a list of actions taken
by whoever is active. Both engines build that exact state (no battlecries,
no summon triggers during setup), play the actions, and report a normalised
end state. Any field that differs is printed.

Every scenario is run three times in Fireplace with different random seeds; if
the results differ, the scenario depends on randomness and cannot be compared
-- it is reported as such, not as a pass or fail.

A scenario may carry "known": "<why>" for a difference that has been looked at
and accepted (usually: Fireplace follows a later patch). It is then reported
as KNOWN, and flagged if the two engines ever start agreeing.

Exit status: 0 if nothing unexpected, 1 otherwise.
"""
import glob
import json
import logging
import os
import random
import shutil
import subprocess
import sys
import tempfile
import warnings

warnings.filterwarnings("ignore")

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "tools", "oracle")
FILLER = "CS2_231"   # Wisp
DECK_SIZE = 30

CLASSES = ["DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"]


# ---------------------------------------------------------------- scenarios

def load_scenarios(filt):
    out = []
    for path in sorted(glob.glob(os.path.join(HERE, "scenarios", "*.json"))):
        with open(path, encoding="utf-8") as fh:
            for sc in json.load(fh):
                sc["_file"] = os.path.basename(path)
                if not filt or filt.lower() in sc["name"].lower():
                    out.append(sc)
    return out


def cards_used(sc):
    ids = set()
    for side in ("p1", "p2"):
        s = sc.get(side) or {}
        for key in ("hand", "deck", "secrets"):
            ids.update(s.get(key) or [])
        for m in s.get("board") or []:
            ids.add(m if isinstance(m, str) else m["id"])
        if s.get("weapon"):
            ids.add(s["weapon"])
    for a in sc.get("actions") or []:
        if a.get("play"):
            ids.add(a["play"])
    return ids


# Scripted cards no scenario names, because they only exist once another card
# makes them. Covered when the card that makes them is.
PRODUCED_BY = {
    "EX1_625t": "EX1_625", "EX1_625t2": "EX1_625", "EX1_tk33": "EX1_323",
    "EX1_tk34": "EX1_323", "EX1_323w": "EX1_323", "EX1_323h": "EX1_323",
}
BASIC_POWER = {"DRUID": "CS2_017", "HUNTER": "DS1h_292", "MAGE": "CS2_034",
               "PALADIN": "CS2_101", "PRIEST": "CS1h_001", "ROGUE": "CS2_083b",
               "SHAMAN": "CS2_049", "WARLOCK": "CS2_056", "WARRIOR": "CS2_102"}


def scripted_ids():
    """Every card id the engine has a script for, asked of the engine itself."""
    proc = subprocess.run([find_luajit(), "tools/oracle/engine_runner.lua", "--scripts"],
                          cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    if proc.returncode != 0:
        sys.exit("engine runner failed:\n" + proc.stderr)
    return set(proc.stdout.split())


def coverage_gaps(scenarios, drift):
    """Every card that CAN be compared (same text as Fireplace, or shimmed)
    must be exercised by at least one scenario, so a card nobody wrote a
    scenario for cannot hide: every collectible minion, spell and weapon, and
    every scripted token, Choose One option and hero power."""
    pin = {c["id"]: c for c in json.load(open(
        os.path.join(ROOT, "tools", "vendor", "cards.7234.enUS.json"), encoding="utf-8"))}
    used = set()
    for sc in scenarios:
        used |= cards_used(sc)
        for a in sc.get("actions") or []:
            for k in ("choose", "pick"):
                if a.get(k):
                    used.add(a[k])
        if any(a.get("power") for a in sc.get("actions") or []):
            for side in ("p1", "p2"):
                used.add(BASIC_POWER.get((sc.get(side) or {}).get("class",
                         "MAGE" if side == "p1" else "PRIEST")))
    used |= {k for k, parent in PRODUCED_BY.items() if parent in used}
    comparable = set(drift["same"]) | set(drift["stats"]) | set(drift.get("shimmed", {}))
    wanted = {cid for cid, c in pin.items()
              if c.get("collectible") and c.get("type") in ("MINION", "SPELL", "WEAPON")}
    wanted |= {cid for cid in scripted_ids() if cid in pin}
    wanted |= set(BASIC_POWER.values())
    return sorted((cid, pin[cid]["name"]) for cid in wanted
                  if (cid in comparable or cid in BASIC_POWER.values()) and cid not in used)


# --------------------------------------------------------------- engine side

def lua_literal(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)   # a JSON string is a valid Lua string
    if isinstance(v, list):
        return "{" + ",".join(lua_literal(x) for x in v) + "}"
    return "{" + ",".join("[%s]=%s" % (json.dumps(k), lua_literal(x))
                          for k, x in v.items() if not k.startswith("_")) + "}"


def find_luajit():
    exe = shutil.which("luajit")
    if exe:
        return exe
    for base in (os.environ.get("LOCALAPPDATA", ""), os.path.expanduser("~/AppData/Local")):
        cand = os.path.join(base, "Programs", "LuaJIT", "bin", "luajit.exe")
        if os.path.exists(cand):
            return cand
    sys.exit("luajit not found -- winget install DEVCOM.LuaJIT")


def run_engine(scenarios):
    fd, path = tempfile.mkstemp(suffix=".lua")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("return " + lua_literal(scenarios) + "\n")
    try:
        proc = subprocess.run([find_luajit(), "tools/oracle/engine_runner.lua", path],
                              cwd=ROOT, capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(path)
    if proc.returncode != 0:
        sys.exit("engine runner failed:\n" + proc.stderr)
    results = {}
    for line in proc.stdout.splitlines():
        if line.startswith("{"):
            r = json.loads(line)
            results[r["name"]] = r
    return results


# ------------------------------------------------------------ Fireplace side

_fp = None


def fireplace():
    """Import and initialise Fireplace once, with the pinned stats patched in."""
    global _fp
    if _fp:
        return _fp
    logging.disable(logging.CRITICAL)
    from hearthstone.enums import CardClass, GameTag, Zone
    from fireplace import cards
    from fireplace.game import Game
    from fireplace.player import Player
    cards.db.initialize()
    logging.getLogger("fireplace").setLevel(logging.CRITICAL)
    drift = json.load(open(os.path.join(HERE, "drift.json"), encoding="utf-8"))
    tag = {"cost": GameTag.COST, "atk": GameTag.ATK, "health": GameTag.HEALTH,
           "durability": GameTag.DURABILITY}
    for cid, d in drift["stats"].items():
        for k, v in d["pin"].items():
            if d["fireplace"][k] != v:
                cards.db[cid].tags[tag[k]] = v
    sys.path.insert(0, HERE)
    import shims
    shims.apply(cards.db)
    # after the merge, which reloads tags: a shim keeps the pinned numbers too
    for cid, d in drift.get("shimmed", {}).items():
        target = shims.ALIASES.get(cid, cid)
        for db_id in {cid, target}:
            if db_id in cards.db:
                for k, v in d["pin"].items():
                    if k == "health" and cards.db[db_id].type == 7:   # WEAPON
                        continue
                    if k == "durability" and cards.db[db_id].type != 7:
                        continue
                    cards.db[db_id].tags[tag[k]] = v
    _fp = dict(CardClass=CardClass, Zone=Zone, Game=Game, Player=Player, drift=drift)
    return _fp


def fp_setup_player(game, player, spec):
    Z = _fp["Zone"]
    spec = spec or {}
    for c in list(player.hand):
        c.zone = Z.DECK if c.id == FILLER else Z.SETASIDE
    # the deck is drawn from the END, so push bottom-most first
    for cid in reversed(spec.get("deck") or []):
        c = player.card(cid)
        c.zone = Z.DECK
    for cid in spec.get("hand") or []:
        player.card(cid).zone = Z.HAND
    for m in spec.get("board") or []:
        if isinstance(m, str):
            m = {"id": m}
        c = player.card(m["id"])
        c.zone = Z.PLAY
        c.turns_in_play = 0 if m.get("sick") else 1
        c.damage = m.get("damage", 0)
        if m.get("frozen"):
            c.frozen = True
    if spec.get("weapon"):
        player.summon(spec["weapon"])
    for cid in spec.get("secrets") or []:
        player.card(cid).zone = Z.SECRET
    player.hero.damage = 30 - spec.get("hp", 30)
    player.hero.armor = spec.get("armor", 0)
    player.max_mana = spec.get("mana", 10)
    player.used_mana = 0
    player.overload_locked = 0


def fp_resolve(game, ref):
    if ref is None:
        return None
    side, _, rest = ref.partition(".")
    p = game.player1 if side == "p1" else game.player2
    zone, _, idx = rest.partition(".")
    if zone == "hero":
        return p.hero
    lst = {"board": p.field, "hand": p.hand}[zone]
    return lst[int(idx) - 1]


def fp_act(game, a):
    me = game.current_player
    if a.get("play"):
        card = next((c for c in me.hand if c.id == a["play"]), None)
        if card is None:
            raise RuntimeError("no %s in hand" % a["play"])
        kw = {}
        if a.get("target"):
            kw["target"] = fp_resolve(game, a["target"])
        if a.get("pos"):
            kw["index"] = a["pos"] - 1
        if a.get("choose"):
            import shims
            kw["choose"] = shims.ALIASES.get(a["choose"], a["choose"])   # the option card's id
        card.play(**kw)
    elif a.get("attack"):
        fp_resolve(game, a["attack"]).attack(fp_resolve(game, a["at"]))
    elif a.get("power"):
        kw = {}
        if a.get("target"):
            kw["target"] = fp_resolve(game, a["target"])
        me.hero.power.use(**kw)
    elif a.get("pick"):
        ch = me.choice
        card = next((c for c in (ch.cards if ch else []) if pinned_id(c.id) == a["pick"]), None)
        if card is None:
            raise RuntimeError("no %s on offer" % a["pick"])
        ch.choose(card)
    elif a.get("end_turn"):
        game.end_turn()
    else:
        raise RuntimeError("unknown action %r" % a)


def pinned_id(cid):
    import shims
    return shims.REVERSE.get(cid, cid)


def fp_flags(e):
    f = []
    if e.taunt: f.append("taunt")
    if e.divine_shield: f.append("shield")
    if e.stealthed: f.append("stealth")
    if e.windfury: f.append("windfury")
    if e.frozen: f.append("frozen")
    if e.silenced: f.append("silenced")
    return ",".join(f)


def fp_snapshot(game):
    from hearthstone.enums import PlayState
    out = {"over": any(p.playstate in (PlayState.WON, PlayState.LOST, PlayState.TIED)
                       for p in game.players)}
    for i, p in enumerate((game.player1, game.player2), 1):
        # Hero Attack only for the side to act: off-turn, a weapon's Attack is
        # a display question the two engines answer differently.
        s = {"hero": "%d+%d" % (p.hero.health, p.hero.armor)}
        if p is game.current_player:
            s["hero"] += " atk%d" % p.hero.atk
        s["board"] = []
        for e in p.field:
            f = fp_flags(e)
            s["board"].append("%s %d/%d(%d)%s" % (pinned_id(e.id), e.atk, e.health, e.max_health,
                                                  (" " + f) if f else ""))
        s["hand"] = ["%s(%d)" % (pinned_id(c.id), c.cost) for c in p.hand]
        s["deck"] = len(p.deck)
        s["weapon"] = ("%s %d/%d" % (p.weapon.id, p.weapon.atk, p.weapon.durability)) if p.weapon else ""
        s["secrets"] = sorted(c.id for c in p.secrets)
        s["mana"] = "%d/%d" % (p.mana, p.max_mana)
        power = p.hero.power
        s["power"] = ("basic" if power.id == p._oracle_basic_power else power.id) +             (" used" if power.activations_this_turn > 0 else "")
        out["p%d" % i] = s
    return out


def run_fireplace(sc, seed):
    fp = fireplace()
    random.seed(seed)
    CC = fp["CardClass"]
    players = []
    for n, side in ((1, "p1"), (2, "p2")):
        cls = CC[(sc.get(side) or {}).get("class", "MAGE" if n == 1 else "PRIEST")]
        # Wild: a "Standard" game (as of 2020) limits random picks to
        # Standard sets, which leaves no GvG Spare Parts at all.
        pl = fp["Player"]("Player%d" % n, [FILLER] * DECK_SIZE, cls.default_hero, is_standard=False)
        players.append(pl)
    game = fp["Game"](players=players)
    # Fireplace picks the first player at random; the scenario always starts
    # with p1 to act, as the engine does.
    game.start()
    for p in game.players:
        if p.choice:
            p.choice.choose()
    # Fireplace may swap the two Player objects so that game.player1 is
    # whoever goes first; the scenario's p1 must be both first and Player1.
    if game.player1.name != "Player1" or game.current_player is not game.player1:
        raise RuntimeError("fireplace put p2 first")  # handled by the retry loop
    for p in game.players:
        p._oracle_basic_power = p.hero.power.id
    fp_setup_player(game, game.player1, sc.get("p1"))
    fp_setup_player(game, game.player2, sc.get("p2"))
    game.refresh_auras()   # zone moves above do not; cost auras would read stale
    from fireplace.exceptions import GameOver, InvalidAction
    refused = []
    for k, a in enumerate(sc.get("actions") or [], 1):
        try:
            fp_act(game, a)
        except InvalidAction:
            refused.append(k)
        except GameOver:
            break
    snap = fp_snapshot(game)
    snap["refused"] = refused
    return snap


def fireplace_outcomes(sc):
    """A random scenario: N valid Fireplace runs, as a Counter of outcomes."""
    from collections import Counter
    out, seed = Counter(), 0
    while sum(out.values()) < sc["random"] and seed < sc["random"] * 5:
        seed += 1
        try:
            out[json.dumps(run_fireplace(sc, seed), sort_keys=True)] += 1
        except RuntimeError as e:
            if "p2 first" in str(e):
                continue
            return None, "fireplace: %s" % e
        except Exception as e:  # noqa: BLE001
            return None, "fireplace raised %s: %s" % (type(e).__name__, e)
    return out, None


def compare_random(sc, er):
    """Both engines must be able to produce the same outcomes. An outcome only
    one side ever produced is a difference; it is shown against the other
    side's most common outcome so only the fields that matter print."""
    from collections import Counter
    fr, ferr = fireplace_outcomes(sc)
    if ferr:
        return "ERROR", ["  " + ferr]
    fr = Counter({json.dumps(masked(sc, json.loads(k)), sort_keys=True): 0 for k in fr}) +         Counter(json.dumps(masked(sc, json.loads(k)), sort_keys=True) for k, n in fr.items() for _ in range(n))
    eo = Counter(json.dumps(masked(sc, x), sort_keys=True) for x in er["states"])
    # A rare outcome only one side happened to hit is sampling noise, not a
    # rules difference: it counts only if it came up at least 3 times, or in
    # 5% of runs. Rarer ones are listed but do not fail the scenario.
    def significant(k, pool):
        return pool[k] >= max(3, 0.05 * sum(pool.values()))
    only_e = [k for k in eo if k not in fr]
    only_f = [k for k in fr if k not in eo]
    sig = [k for k in only_e if significant(k, eo)] + [k for k in only_f if significant(k, fr)]
    lines = ["  engine: %d outcomes, fireplace: %d; %d only in the engine, %d only in Fireplace"
             % (len(eo), len(fr), len(only_e), len(only_f))]
    for label, mine, pool, other in (("engine only", only_e, eo, fr), ("fireplace only", only_f, fr, eo)):
        ref = json.loads(other.most_common(1)[0][0]) if other else {}
        for k in sorted(mine, key=lambda k: -pool[k])[:3]:
            d = diff(ref, json.loads(k))
            lines.append("  %s (x%d%s): %s" % (label, pool[k], "" if k in sig else ", rare",
                         "; ".join("%s=%s" % (p, json.dumps(y)) for p, x, y in d)))
    if not sig:
        return "AGREE", lines
    return "DIFFER", lines


def fireplace_result(sc):
    """Three runs with different seeds. Fireplace chooses who goes first at
    random, so seeds that put p2 first are skipped rather than counted."""
    snaps, seed = [], 0
    while len(snaps) < 3 and seed < 200:
        seed += 1
        try:
            snaps.append(json.dumps(run_fireplace(sc, seed), sort_keys=True))
        except RuntimeError as e:
            if "p2 first" in str(e):
                continue
            return None, "fireplace: %s" % e
        except Exception as e:  # noqa: BLE001 -- any Fireplace failure is a result
            return None, "fireplace raised %s: %s" % (type(e).__name__, e)
    if len(set(snaps)) > 1:
        return None, "RANDOM"
    return json.loads(snaps[0]), None


# ------------------------------------------------------------------- report

def masked(sc, snap):
    """Apply a scenario's "ignore" list to a snapshot. "p1.hand" blanks the
    field; "p1.hand:count" keeps only its length. For cards drawing on a
    random card POOL (Unstable Portal, Piloted Shredder): Fireplace's pool
    spans every set to 2020, so the card itself can never match, but how
    many arrived, what they cost to play and everything else still must."""
    if not sc.get("ignore"):
        return snap
    snap = json.loads(json.dumps(snap))
    for spec in sc["ignore"]:
        path, _, how = spec.partition(":")
        keys = path.split(".")
        node = snap
        for k in keys[:-1]:
            node = node.get(k, {})
        if keys[-1] in node:
            v = node[keys[-1]]
            node[keys[-1]] = len(v) if how == "count" and isinstance(v, list) else "*"
    return snap


def diff(a, b, path=""):
    out = []
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            out += diff(a.get(k), b.get(k), path + ("." if path else "") + k)
    elif a != b:
        out.append((path, a, b))
    return out


def main():
    filt = sys.argv[1] if len(sys.argv) > 1 else None
    scenarios = load_scenarios(filt)
    fireplace()
    drift = _fp["drift"]
    runnable, skipped = [], []
    for sc in scenarios:
        bad = sorted(c for c in cards_used(sc)
                     if c in drift["reworked"] or c in drift["missing"])
        if bad:
            skipped.append((sc, bad))
        else:
            runnable.append(sc)
    engine = run_engine(runnable)

    counts = {"AGREE": 0, "DIFFER": 0, "KNOWN": 0, "RESOLVED": 0, "RANDOM": 0, "ERROR": 0}
    unexpected = 0
    print()
    for sc in runnable:
        name = sc["name"]
        er = engine.get(name, {"error": "engine runner produced nothing"})
        if sc.get("random") and not er.get("error"):
            status, lines = compare_random(sc, er)
            if sc.get("known"):
                status = {"AGREE": "RESOLVED", "DIFFER": "KNOWN"}.get(status, status)
                lines = ["  known: %s" % sc["known"]] + lines
            counts[status] += 1
            if status in ("DIFFER", "RESOLVED", "ERROR"):
                unexpected += 1
            if status != "AGREE" or os.environ.get("ORACLE_VERBOSE"):
                print("%-8s %s  [%s]" % (status, name, sc["_file"]))
                for l in lines:
                    print(l)
                print()
            continue
        fr, ferr = fireplace_result(sc)
        if ferr == "RANDOM":
            status, lines = "RANDOM", ["  scenario depends on randomness in Fireplace -- make it deterministic"]
        elif ferr or er.get("error"):
            status = "ERROR"
            lines = ["  engine:    %s" % er["error"]] if er.get("error") else []
            if ferr:
                lines.append("  " + ferr)
        else:
            d = diff(masked(sc, er["state"]), masked(sc, fr))
            if not d:
                status = "RESOLVED" if sc.get("known") else "AGREE"
                lines = ["  known difference no longer reproduces: %s" % sc["known"]] if sc.get("known") else []
            else:
                status = "KNOWN" if sc.get("known") else "DIFFER"
                lines = ["  %-18s engine %s\n  %-18s fireplace %s" % (p, json.dumps(x), "", json.dumps(y))
                         for p, x, y in d]
                if sc.get("known"):
                    lines = ["  known: %s" % sc["known"]] + lines
        counts[status] += 1
        if status in ("DIFFER", "RESOLVED", "RANDOM", "ERROR"):
            unexpected += 1
        if status != "AGREE" or os.environ.get("ORACLE_VERBOSE"):
            print("%-8s %s  [%s]" % (status, name, sc["_file"]))
            if sc.get("question") and status != "AGREE":
                print("  question: %s" % sc["question"])
            for l in lines:
                print(l)
            print()
    for sc, bad in skipped:
        print("SKIPPED  %s  [%s]\n  uses cards that changed since the pin: %s\n"
              % (sc["name"], sc["_file"], ", ".join(bad)))
    uncovered = [] if filt else coverage_gaps(scenarios, drift)
    if uncovered:
        print("UNCOVERED  %d comparable cards appear in no scenario:" % len(uncovered))
        for cid, name in uncovered:
            print("  %s  %s" % (cid, name))
        print()
        unexpected += 1
    print("  %d scenarios: %s, %d skipped" % (
        len(scenarios), ", ".join("%d %s" % (v, k.lower()) for k, v in counts.items() if v),
        len(skipped)))
    return 1 if unexpected else 0


if __name__ == "__main__":
    sys.exit(main())
