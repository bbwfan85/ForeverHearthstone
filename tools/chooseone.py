#!/usr/bin/env python3
"""
Forever Hearthstone -- Choose One mode detection, shared by the importer and
the effect compiler.

WHY THIS IS DERIVED AND NOT HAND-LISTED

  The handoff called Choose One "a mechanic whose modes printed data does not
  represent". That was wrong. The pinned build carries every mode as a real,
  non-collectible 0-cost SPELL card with id <parent>a / <parent>b, each with its
  OWN text and its OWN playRequirements:

    EX1_166  Keeper of the Grove  "Choose One - Deal 2 damage; or Silence a minion."
      EX1_166a Moonfire  REQ_TARGET_TO_PLAY
      EX1_166b Dispel    REQ_TARGET_TO_PLAY + REQ_MINION_TARGET

  So the modes need no authored data at all -- only their BEHAVIOUR needs a
  script, exactly like any other card. Targeting for a chosen mode falls out of
  the mode's printed requirements through the existing Targeting module, which
  is why Dispel refuses a hero and Moonfire accepts one with nothing per-card
  written anywhere.

DISPLAY ORDER

  The a/b suffix is NOT the order the modes are shown in. Four of the thirteen
  are reversed relative to the parent's text (Ancient of War, Dark Wispers,
  Starfall, Power of the Wild). The parent's text is the authority -- it reads
  "Choose One - <first>; or <second>" -- so the order is recovered by matching
  each mode's text against the two halves and taking the better assignment.
  A decisive margin is REQUIRED; an ambiguous card raises rather than guessing,
  because a silently swapped pair would misrepresent the card in the prompt and
  nothing downstream could notice.
"""
import re, difflib

# Both sides of the pair must exist, as non-collectible spells, or it is not a
# Choose One card and something else is going on.
MODE_SUFFIXES = ("a", "b")


def strip_markup(s):
    if not s:
        return ""
    s = s.replace(" ", " ")
    s = re.sub(r"</?[bi]>", "", s)
    s = re.sub(r"\[x\]", "", s)
    s = re.sub(r"\s*\n\s*", " ", s)
    return re.sub(r"\s{2,}", " ", s).strip()


def _norm(s):
    """Normalise for comparison: the $ spell-damage sigil and punctuation carry
    no ordering information and only add noise to the similarity score."""
    return re.sub(r"[^a-z0-9+/ ]", "", s.lower().replace("$", "")).strip()


def _sim(x, y):
    return difflib.SequenceMatcher(None, _norm(x), _norm(y)).ratio()


# The smallest observed margin in build 7234 is 0.403 (Starfall). Anything below
# this floor means the two modes read too alike to order from text, which is a
# re-pin regression worth stopping for.
MIN_MARGIN = 0.10


def mode_order(parent, mode_a, mode_b):
    """Return the two mode ids in DISPLAY order. Raises if it cannot tell."""
    text = strip_markup(parent.get("text"))
    body = text.split("Choose One", 1)[1].lstrip(" -").strip()
    parts = body.split("; or ")
    if len(parts) != 2:
        raise ValueError("%s: cannot split Choose One text into two modes: %r"
                         % (parent["id"], text))
    ta = strip_markup(mode_a.get("text"))
    tb = strip_markup(mode_b.get("text"))
    straight = _sim(ta, parts[0]) + _sim(tb, parts[1])
    swapped  = _sim(ta, parts[1]) + _sim(tb, parts[0])
    if abs(straight - swapped) < MIN_MARGIN:
        raise ValueError("%s: mode display order is ambiguous (margin %.3f). "
                         "Order it explicitly rather than guessing."
                         % (parent["id"], abs(straight - swapped)))
    if straight > swapped:
        return [mode_a["id"], mode_b["id"]]
    return [mode_b["id"], mode_a["id"]]


def find(cards):
    """Map parent card id -> [mode id, mode id] in display order.

    `cards` is the raw HearthstoneJSON list. Only collectible parents count: a
    mode card's own text never says "Choose One", but guarding on collectible
    keeps a future token from being mistaken for a parent."""
    by_id = {c["id"]: c for c in cards}
    out = {}
    for c in cards:
        if not c.get("collectible"):
            continue
        if "Choose One" not in strip_markup(c.get("text")):
            continue
        modes = [by_id.get(c["id"] + s) for s in MODE_SUFFIXES]
        if not all(modes):
            raise ValueError("%s %r says Choose One but its mode cards are "
                             "missing from the pin" % (c["id"], c.get("name")))
        for m in modes:
            if m.get("type") != "SPELL" or m.get("collectible"):
                raise ValueError("%s: mode %s is not a non-collectible spell"
                                 % (c["id"], m["id"]))
        out[c["id"]] = mode_order(c, modes[0], modes[1])
    return out


# The pin's expected count, asserted by both callers. A re-pin that changes this
# means the pool changed and the Choose One card list must be re-reviewed --
# exactly the loud failure the printed-data pin exists to provide.
EXPECTED_IN_7234 = 13
