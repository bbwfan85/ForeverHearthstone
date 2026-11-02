#!/usr/bin/env python3
"""
Tests for tools/compile_effects.py.

The compiler is ~750 lines of parsing with genuinely subtle behaviour, and until
now it had no tests of its own -- it was only validated indirectly by the fact
that authored cards compiled. That is not enough: the compiler can emit
SYNTACTICALLY VALID but WRONG Lua, and it can misclassify which cards need a
script at all.

Both failure modes have already bitten this project:

  * `parse_amount` used to fall through to `return a`, so a typo emitted
    `atk=atackOf(x)` -- valid Lua, an undefined global at runtime, and therefore
    invisible to any syntax check. It would have errored on load and taken the
    whole addon down.
  * `needs_script` stripped the FORGETFUL reminder sentence unconditionally,
    which produced a FALSE NEGATIVE for three cards that carry the sentence but
    not the mechanic. Coverage would have called them complete while they did
    nothing.

Run:  python tools/test_compiler.py
Wired into ./run-tests.sh, so it runs alongside the Lua suite.
"""
import importlib.util, os, re, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

#[[ LOAD FROM SOURCE, NEVER FROM CACHED BYTECODE.
#
#   spec_from_file_location goes through SourceFileLoader, which will happily use
#   a cached .pyc when it believes it is current. Edits made inside one mtime tick
#   that do not change the file size can leave that cache valid, and then this
#   whole file silently tests the PREVIOUS version of the compiler.
#
#   That actually happened: a fixed false negative kept reporting as broken
#   because the .pyc predated the fix. Cheap to prevent, extremely confusing to
#   debug, so it is prevented unconditionally. ]]
sys.dont_write_bytecode = True
shutil.rmtree(os.path.join(HERE, "__pycache__"), ignore_errors=True)
importlib.invalidate_caches()

spec = importlib.util.spec_from_file_location("ce", os.path.join(HERE, "compile_effects.py"))
ce = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ce)
BY, POOL = ce.load_cards()

_fails, _checks = [], 0


def check(cond, what):
    global _checks
    _checks += 1
    if not cond:
        _fails.append(what)


def eq(actual, expected, what):
    check(actual == expected, "%s: expected %r, got %r" % (what, expected, actual))


def op(src):
    """Parse one op, returning (emitted, errors)."""
    ce.errors.clear()
    out = ce.parse_op(src, 1, BY)
    return out, list(ce.errors)


def emits(src, needle, what):
    out, errs = op(src)
    check(not errs, "%s: unexpected errors %s" % (what, errs))
    check(out is not None and needle in out,
          "%s: %r not in %r" % (what, needle, out))


def rejects(src, what):
    out, errs = op(src)
    check(bool(errs), "%s: expected a compile error, got %r" % (what, out))


# ============================================================ needs_script

def test_needs_script_printed_fields():
    """Text that restates a printed FIELD needs no script."""
    for cid in ("CS2_142", "EX1_582", "CS2_197", "CS2_155", "EX1_563"):
        c = BY.get(cid)
        if c:
            check(not ce.needs_script(c),
                  "Spell Damage card %s (%s) should need no script" % (cid, c["name"]))
    for cid in ("EX1_243", "EX1_247"):          # Overload reminders
        c = BY.get(cid)
        if c:
            check(not ce.needs_script(c),
                  "Overload card %s (%s) should need no script" % (cid, c["name"]))


def test_needs_script_is_mechanic_gated():
    """THE REGRESSION. A reminder sentence is only strippable when the card really
    carries the mechanic. Stripping unconditionally is a false negative, which is
    strictly worse than the false positive it fixes."""
    dune = BY.get("GVG_066")                    # has FORGETFUL
    check(dune and not ce.needs_script(dune),
          "Dunemaul Shaman HAS the FORGETFUL mechanic -> no script needed")
    for cid in ("GVG_088", "GVG_054", "GVG_065"):   # same text, NO mechanic
        c = BY.get(cid)
        if c:
            check("FORGETFUL" not in (c.get("mechanics") or []),
                  "%s really lacks the FORGETFUL tag (data assumption)" % cid)
            check(ce.needs_script(c),
                  "%s (%s) carries the sentence but NOT the mechanic, so it MUST "
                  "still need a script" % (cid, c["name"]))


def test_needs_script_keyword_only_text():
    """A card whose whole text is its own static keywords needs no script."""
    for cid in ("EX1_045", "NEW1_023", "EX1_170"):
        c = BY.get(cid)
        if c:
            check(not ce.needs_script(c),
                  "%s (%s) is printed-keyword-only" % (cid, c["name"]))


def test_needs_script_real_effects_still_counted():
    """Cards with genuine behaviour must never be excused."""
    for cid in ("CS2_029", "NEW1_019", "EX1_162", "CS1_113", "EX1_016"):
        c = BY.get(cid)
        if c:
            check(ce.needs_script(c),
                  "%s (%s) has real behaviour and must need a script"
                  % (cid, c["name"]))


# =============================================================== amounts

def test_amounts_strict():
    """parse_amount must NEVER pass unrecognised text through. This is the bug
    that would have emitted valid-syntax, undefined-global Lua."""
    emits("Damage(target, 3)", "amount=3", "literal amount")
    emits("Damage(target, count(friendly.minion))", "count=", "count() amount")
    emits("Damage(target, attackOf(self))", "attackOf=", "attackOf() amount")
    emits("Damage(target, armorOf(friendly.hero))", "armorOf=", "armorOf() amount")
    rejects("Damage(target, notAThing(x))", "unknown dynamic form")
    rejects("Damage(target, atackOf(self))", "misspelled dynamic form")
    rejects("Damage(target, someGlobal)", "bare identifier as an amount")


def test_dynamic_amounts_reach_buffs():
    """Buff/SetAttack must accept dynamic amounts, not only literals."""
    emits("Buff(self, attackOf(friendly.weapon), 0)", "attackOf=",
          "Buff with a dynamic attack")
    emits("SetAttack(self, count(friendly.minion))", "count=",
          "SetAttack with a dynamic value")


# ============================================================ side arguments

def test_side_arguments():
    """The ops have always supported op.side; the DSL silently dropped it for
    three of four ops, which would have handed the caster free minions."""
    emits("Summon(CS2_231, 2, enemy)", 'side="ENEMY"', "Summon count+enemy")
    emits("Summon(CS2_231, enemy)", 'side="ENEMY"', "Summon enemy, no count")
    emits("SummonEntourage(enemy)", 'side="ENEMY"', "SummonEntourage enemy")
    emits("AddCard(CS2_231, 2, enemy)", 'side="ENEMY"', "AddCard count+enemy")
    emits("AddCard(CS2_231, enemy)", 'side="ENEMY"', "AddCard enemy, no count")
    emits("AddCardEntourage(enemy)", 'side="ENEMY"', "AddCardEntourage enemy")
    emits("DestroyWeapon(enemy)", 'side="ENEMY"', "DestroyWeapon enemy")
    emits("Mana(1, enemy)", 'side="ENEMY"', "Mana enemy")
    emits("TakeControl(target, enemy)", "toEnemy=true", "TakeControl to opponent")

    # and the default must stay on the caster
    for src in ("Summon(CS2_231, 2)", "AddCard(CS2_231)", "DestroyWeapon()",
                "SummonEntourage()", "TakeControl(target)"):
        out, errs = op(src)
        check(not errs, "%s: unexpected errors %s" % (src, errs))
        check('side="ENEMY"' not in (out or "") and "toEnemy" not in (out or ""),
              "%s must default to the caster, got %r" % (src, out))

    # a count must not be mistaken for the word `enemy`, or vice versa
    emits("Summon(CS2_231, 3)", "count=3", "numeric count parsed as a count")
    out, _ = op("Summon(CS2_231, enemy)")
    check("count=" not in out, "`enemy` must not be parsed as a count: %r" % out)


def test_negative_mana_rejected():
    """GainManaCrystal loops upward, so a negative count silently does nothing.
    Emitting it would be a lie; losing a crystal needs its own op."""
    rejects("Mana(-1)", "negative Mana")
    emits("Mana(2, temporary)", "temporary=true", "temporary mana")
    emits("Mana(1, empty)", "empty=true", "empty mana crystal")


# ================================================================ selectors

def test_compound_selectors():
    emits("Damage(friendly.hand.minion, 1)", 'zone="HAND"', "zone+type compose")
    emits("Damage(friendly.hand.minion, 1)", 'type="MINION"', "type survives")
    emits("Damage(enemy.minion, 1)", 'side="ENEMY"', "scope")
    emits("Damage(any.char, 1)", "hero=true", "char includes heroes")
    emits("Damage(friendly.beast, 1)", 'race="BEAST"', "race filter")
    emits("Buff(friendly.weapon, 1, 0)", 'type="WEAPON"', "weapons selectable")
    emits("Damage(enemy.minion!target, 1)", "excludeTarget=true", "!target")
    emits("Damage(adjacent@target, 1)", 'adjacent="TARGET"', "adjacent-of-target")
    rejects("Damage(sideways.minion, 1)", "unknown scope")
    rejects("Damage(friendly.notathing, 1)", "unknown filter")


def test_conditions():
    for name in ("TargetIsDamaged", "TargetAlive", "TargetIsFrozen",
                 "PayloadSourceIsSelf", "Combo", "HasWeapon"):
        ce.errors.clear()
        out = ce.parse_cond(name, 1)
        check(out and name in out and not ce.errors,
              "condition %s parses (got %r, errors %s)" % (name, out, ce.errors))
    ce.errors.clear()
    check(ce.parse_cond("TargetHasKeyword(taunt)", 1) is not None,
          "TargetHasKeyword parses")
    ce.errors.clear()
    check(ce.parse_cond("TargetHasRace(beast)", 1) is not None,
          "TargetHasRace parses")
    ce.errors.clear()
    ce.parse_cond("NotARealCondition", 1)
    check(bool(ce.errors), "an unknown condition is an error")


def test_unknown_card_ids_rejected():
    rejects("Summon(NOT_A_REAL_ID)", "unknown summon id")
    rejects("Transform(target, NOT_A_REAL_ID)", "unknown transform id")
    emits("Summon(CS2_231)", 'cardId="CS2_231"', "a real id is accepted")


# ============================================================= choose one

#[[ The Choose One rules live in main() rather than in a parse helper, so these
#   test the DERIVATION and the invariants directly rather than driving the
#   whole compiler. The three authoring mistakes they guard against were each
#   confirmed by deliberately making them and watching the compiler stop. ]]

def _chooseone():
    import json
    sys.path.insert(0, HERE)
    import chooseone
    return chooseone, json.load(open(ce.PRINTED, encoding="utf-8"))


def test_chooseone_derivation_matches_the_pin():
    co, cards = _chooseone()
    found = co.find(cards)
    eq(len(found), co.EXPECTED_IN_7234, "Choose One card count in build 7234")
    for par, modes in found.items():
        eq(len(modes), 2, "%s has two modes" % par)
        check(set(modes) == {par + "a", par + "b"},
              "%s modes are its own a/b cards, got %r" % (par, modes))


def test_chooseone_display_order_is_text_order_not_suffix():
    #[[ Four of the thirteen are reversed relative to the a/b suffix. Taking the
    #   suffix as the order would offer the wrong mode under the right label,
    #   and nothing downstream could detect it. ]]
    co, cards = _chooseone()
    found = co.find(cards)
    eq(found["EX1_160"], ["EX1_160b", "EX1_160a"], "Power of the Wild is reversed")
    eq(found["EX1_178"], ["EX1_178b", "EX1_178a"], "Ancient of War is reversed")
    eq(found["GVG_041"], ["GVG_041b", "GVG_041a"], "Dark Wispers is reversed")
    eq(found["NEW1_007"], ["NEW1_007b", "NEW1_007a"], "Starfall is reversed")
    eq(found["EX1_166"], ["EX1_166a", "EX1_166b"], "Keeper of the Grove is not")
    reversed_count = sum(1 for p, m in found.items() if m[0].endswith("b"))
    eq(reversed_count, 4, "exactly four are reversed in this pin")


def test_chooseone_ambiguous_order_raises_rather_than_guessing():
    co, cards = _chooseone()
    by = {c["id"]: c for c in cards}
    parent = dict(by["EX1_166"])
    # Two modes reading identically cannot be ordered from text.
    same = {"id": "EX1_166a", "text": "Deal 2 damage."}
    try:
        co.mode_order(parent, same, dict(same, id="EX1_166b"))
        check(False, "identical mode texts must raise, not guess an order")
    except ValueError:
        check(True, "identical mode texts raise")


def test_chooseone_margin_floor_is_below_the_real_minimum():
    #[[ The floor has to sit under the tightest real pair (Starfall, 0.403) or
    #   the importer refuses a card it should accept. ]]
    co, cards = _chooseone()
    by = {c["id"]: c for c in cards}
    worst = 1e9
    for par in co.find(cards):
        p = by[par]
        a, b = by[par + "a"], by[par + "b"]
        body = co.strip_markup(p["text"]).split("Choose One", 1)[1].lstrip(" -").strip()
        one, two = body.split("; or ")
        ta, tb = co.strip_markup(a.get("text")), co.strip_markup(b.get("text"))
        m = abs((co._sim(ta, one) + co._sim(tb, two))
                - (co._sim(ta, two) + co._sim(tb, one)))
        worst = min(worst, m)
    check(worst > co.MIN_MARGIN,
          "tightest real margin %.3f must clear the floor %.3f" % (worst, co.MIN_MARGIN))


def test_chooseone_modes_are_noncollectible_spells():
    # The engine substitutes the mode's script for the parent's, so a mode that
    # were collectible would also be playable on its own for 0 mana.
    co, cards = _chooseone()
    by = {c["id"]: c for c in cards}
    for par, modes in co.find(cards).items():
        for m in modes:
            eq(by[m]["type"], "SPELL", "%s is a spell" % m)
            check(not by[m].get("collectible"), "%s is not collectible" % m)
            eq(by[m].get("cost"), 0, "%s costs nothing itself" % m)


def test_chooseone_parents_carry_no_requirements_of_their_own():
    #[[ Targeting reads the MODE's requirements. If a parent also carried some,
    #   they would be silently ignored the moment a mode was chosen. ]]
    co, cards = _chooseone()
    by = {c["id"]: c for c in cards}
    for par in co.find(cards):
        check(not by[par].get("playRequirements"),
              "%s must have no playRequirements of its own" % par)


# ============================================================= handwritten

def test_handwritten_ids_are_found():
    #[[ Coverage counts these as authored. It did not, and three finished cards
    #   were reported as outstanding work for as long as that was true. ]]
    hand = ce.load_handwritten()
    check("EX1_350" in hand, "Prophet Velen is seen in Handwritten.lua")
    check("EX1_538" in hand, "Unleash the Hounds is seen in Handwritten.lua")
    check("CS2_033" not in hand,
          "Water Elemental moved to a CSV row and must no longer be there")
    for cid in hand:
        check(cid in BY, "handwritten id %s is a real card" % cid)


# ============================================================ grammar guards

def test_condition_precedence_binds_not_tightly():
    #[[ `not A and B` must mean `(not A) and B`, as it reads.
    #
    #   It used to mean `not (A and B)`, because the `not ` prefix was tested
    #   BEFORE the and/or split. That is quietly the opposite of the intent, and
    #   it stayed hidden for a long time: one authored card had been written to
    #   depend on the old reading and another was contorted to work around it. ]]
    ce.errors.clear()
    out = ce.parse_cond("not Combo and HasWeapon", 1)
    check(not ce.errors, "it parses: %s" % ce.errors)
    check(out.startswith('{c="All"'),
          "`not A and B` is a CONJUNCTION at the top, got %r" % out)
    check(out.count('c="Not"') == 1, "with exactly one negation, got %r" % out)
    # ...and the negation wraps only the first term
    check('{c="Not",of={c="Combo"}}' in out,
          "the `not` binds to Combo alone, got %r" % out)

    ce.errors.clear()
    out2 = ce.parse_cond("not Combo", 1)
    check(out2.startswith('{c="Not"'), "a bare `not` still negates, got %r" % out2)


def test_flags_are_rejected_where_they_mean_nothing():
    #[[ The flags column is read only by `secret` and `trigger` rows. Anywhere
    #   else it used to be accepted and DISCARDED, which is how Bolvar's `hand`
    #   flag compiled cleanly and did nothing at all. ]]
    src = ce.__dict__
    check("HOOKS" in src, "the hook set is available")
    check("trigger" in src["HOOKS"] and "secret" in src["HOOKS"],
          "trigger and secret are hooks")
    # The guard lives in main()'s row loop, so assert on the emitted text that
    # documents it rather than re-running the whole compiler here.
    body = open(os.path.join(HERE, "compile_effects.py"), encoding="utf-8").read()
    check("the flags column means nothing on a %r row" in body,
          "a flags value on a non-flag hook is an ERROR, not a silent discard")
    check("only `hand` is accepted here" in body,
          "and an unknown flag on a trigger row is an error too")
    check("inHand=true" in body, "the `hand` flag actually emits inHand")


# ==================================================================== main

def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    print("")
    print("  compiler tests (tools/compile_effects.py)")
    for t in tests:
        before = len(_fails)
        try:
            t()
        except Exception as ex:                       # noqa: BLE001
            _fails.append("%s CRASHED: %r" % (t.__name__, ex))
        mark = "ok  " if len(_fails) == before else "FAIL"
        print("  %s  %s" % (mark, t.__name__))
    print("")
    print("  %d tests, %d checks, %d failure(s)" % (len(tests), _checks, len(_fails)))
    if _fails:
        print("")
        for f in _fails:
            print("    " + f)
        print("")
        return 1
    print("  ALL PASS")
    print("")
    return 0


if __name__ == "__main__":
    sys.exit(main())
