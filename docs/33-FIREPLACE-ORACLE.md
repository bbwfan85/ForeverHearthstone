# Fireplace Oracle: a differential test

[Fireplace](https://github.com/jleclanche/fireplace) is an independent, open-source Python
reimplementation of Hearthstone. The oracle plays the same scenarios in this engine and in
Fireplace and reports every difference in the end state.

When the two disagree, one of them is wrong. The disagreement is then settled against
[hearthstone.wiki.gg](https://hearthstone.wiki.gg), not memory, and the scenario is either fixed
or labelled.

Fireplace is **a second opinion, not ground truth**. It has its own bugs (22 are recorded
below), and it follows patch 17.6 (2020), not the 7234 pin.

**Local only.** Nothing under `tools/oracle/` is loaded by the addon or packaged. Fireplace
(AGPL) lives in `~/.cache/forever-hearthstone-oracle`, outside the repo.

## Status

- **622 scenarios: 595 agree, 27 known, 0 differ, 0 skipped.**
- **Coverage is complete.** Every comparable card is exercised, and the run fails if one is
  not. That means every collectible minion, spell and weapon at the pin, and every one of the
  engine's 504 scripts: tokens, Choose One options, hero powers, Spare Parts and Dream cards.
- **None of the 36 cards reworked since the pin is skipped.** 25 are compared against their
  2014 text, and 11 turned out to be rewordings (see "Card drift").
- **A full run takes about 45 seconds.**
- **Fixes: 17 engine changes across 13 rules** (below). Each has a regression test in
  `tests/test_rulings.lua` or the suite it belongs to, so none depends on the oracle to stay
  fixed.

## Setup and running

```
bash tools/oracle/setup.sh          # once: clones Fireplace at a pinned commit, builds a venv
~/.cache/forever-hearthstone-oracle/venv/Scripts/python.exe tools/oracle/oracle.py [filter]
ORACLE=1 ./run-tests.sh             # the full suite plus the oracle
```

Setup needs Python 3.10 or newer, which is Fireplace's minimum. `winget install -e --id
Python.Python.3.12` installs it alongside 3.9. It also needs git-lfs.

`ORACLE=1` fails the run on any of the following:

- a DIFFER, ERROR or RANDOM result;
- a RESOLVED result (a "known" difference that stopped reproducing);
- any card no scenario exercises.

## How it works

| file | role |
|---|---|
| `scenarios/*.json` | the scenarios: both sides' boards, hands, decks, weapons, secrets and mana, then the actions |
| `engine_runner.lua` | builds each scenario in this engine and prints a JSON snapshot; `--scripts` lists every scripted card |
| `oracle.py` | builds the same state in Fireplace, runs the engine runner, compares, and checks coverage |
| `shims.py` | the 2014 versions of reworked cards, installed into Fireplace under their pinned ids |
| `card_drift.py` → `drift.json` | sorts every pinned card by how Fireplace's copy differs |
| `setup.sh` | clones Fireplace at a pinned commit and builds the venv |

### Card drift

Fireplace's card data is six years past the pin, so `card_drift.py` sorts every card:

| category | count | what happens to it |
|---|---|---|
| same | 734 | used as it is |
| stats only | 59 | Fireplace's copy is patched to the pinned cost, Attack, Health and Durability (Leper Gnome 2/1, Knife Juggler 3/2) |
| shimmed | 25 | the text changed, and the 2014 card is installed from `shims.py` (below), with pinned numbers too |
| reworked | 0 | nothing is skipped any more |
| missing | 64 | basic hero powers under their 2014 ids (compared as `basic`) and placeholders |

The shimmed cards come from two places:

- **Fireplace's own "(Old)" cards (11):** Innervate, Preparation, Charge, Ancient of Lore,
  Force of Nature and its Treant, Blade Flurry, Arcane Golem, Master of Disguise and Warsong
  Commander. These are aliased under the pinned ids.
- **Written in Fireplace's card language (14):** Holy Nova, Holy Smite, Power Word: Shield,
  Coldlight Seer, Mirror Entity, Sword of Justice, Repentance, Murloc Warleader, Grimscale
  Oracle, Snipe, Undertaker, Mistress of Pain, Shadowboxer and Sacrificial Pact. Only the card
  text is ours; Fireplace's rules engine still resolves them, which makes them less independent
  than cards Fireplace wrote.

`WORDING_ONLY` in `card_drift.py` lists the text changes that don't change behaviour, checked
against Fireplace's source:

- Enrage became "while damaged".
- "Destroy any minion damaged by this" became Poisonous.
- Fel Reaver's "discard" became "remove".
- Burrowing Mine "explodes" became "Casts When Drawn".
- A few others of the same kind.

### Setup bypasses play

- **Boards** are placed directly, with no battlecries and no summon triggers, as `H.Put` does.
- **Hands:** the dealt hand and the Coin are cleared.
- **Decks:** both are 30 Wisps under whatever the scenario stacks on top.
- **Turn order:** player 1 always acts first.
- **Format:** Fireplace plays Wild. A "Standard" 2020 game limits random picks to 2020's sets,
  which leaves no Spare Parts at all.

### Snapshot

For each player it records:

- hero Health and Armor, plus Attack for the side to act;
- each minion as `ID atk/health(max)` with its taunt/shield/stealth/windfury/frozen/silenced flags;
- the hand with current costs;
- deck size, weapon, secrets and mana;
- the hero power and whether it has been used;
- which actions were refused.

A refused action is a result, so "one engine allowed it" is a difference. On the engine side,
"refused" means the call returned false *and nothing changed*: an attack a Secret cancels also
returns false, but it happened.

### Random scenarios

`"random": N` runs both engines N times with different seeds and compares the *sets* of
outcomes. An outcome only one engine can produce is a difference. Examples: Animal Companion's
three beasts, how Arcane Missiles splits, Brawl's survivor.

An unmatched outcome counts only if it came up at least 3 times, or in 5% of runs. Rarer ones
are printed as `rare` but don't fail, since they are sampling noise.

Some cards draw from a card *pool*: Unstable Portal, Piloted Shredder, Blingtron. Fireplace's
pool spans every set to 2020, so those scenarios `"ignore"` the random field: `"p1.hand"`
blanks it, and `"p1.hand:count"` keeps only its length. Everything else is still compared.

### Statuses

| status | meaning |
|---|---|
| AGREE | same end state, or the same set of outcomes |
| DIFFER | a difference nobody has ruled on yet |
| KNOWN | the scenario has `"known": "<why>"` because the difference was looked at and accepted |
| RESOLVED | a KNOWN difference that no longer reproduces; update the scenario |
| RANDOM | a non-random scenario gave different results across Fireplace seeds |
| UNCOVERED | a comparable card appears in no scenario |

### Writing a scenario

```json
{"name": "pair: Faceless copies a buffed, damaged minion",
 "question": "optional: what this settles",
 "p1": {"class": "PALADIN", "board": [{"id": "CS2_182", "damage": 2}], "hand": ["CS2_092", "EX1_564"]},
 "p2": {"board": ["CS2_200"], "secrets": ["EX1_289"], "weapon": "CS2_106", "hp": 20, "armor": 2,
        "mana": 10, "deck": ["top card first"]},
 "actions": [{"play": "CS2_092", "target": "p1.board.1"},
             {"play": "EX1_564", "target": "p1.board.1", "pos": 2},
             {"play": "GVG_041", "choose": "GVG_041a", "target": "p1.board.1"},
             {"play": "DS1_184"}, {"pick": "CS2_120"},
             {"attack": "p1.board.1", "at": "p2.hero"},
             {"power": true, "target": "p2.board.1"},
             {"end_turn": true}]}
```

- References are `p1|p2` + `.hero`, `.board.N` or `.hand.N`, counted from 1 and resolved when
  the action runs.
- `choose` names the option card, and `pick` names the offered card (Tracking). The two engines
  order some options differently.
- A board entry may carry `damage`, `frozen` or `sick`.
- Keep mana at 10 or less: Fireplace caps it and the engine's test helper does not.

## Engine rules changed

Each change was found by a difference and settled on hearthstone.wiki.gg, cited in the code
comment.

| rule | was | now | wiki page |
|---|---|---|---|
| Lightspawn | Attack buffs and auras added on top | Attack *is* Health; Attack buffs do nothing (`Entity:Attack`, `attackEqualsHealth`) | Lightspawn |
| Silence on a buffed, damaged minion | could kill it | lowers Health only if it's above the new maximum, and raises it when the maximum rises (Reversing Switch) | Health, Silence |
| Freeze | frozen on its own turn = frozen through the next | thaws at end of turn unless it used all its attacks, including a Windfury minion frozen by its first swing (Fireplace gets that one wrong too) | Freeze |
| Faceless / Echoing Ooze copies | undamaged; a popped shield came back as a keyword the UI and AI believed | copies damage; a popped shield is gone completely | Copy, Faceless Manipulator |
| Cost modifiers | the card's own cost floored at 0 before Loatheb, and "set to 0" always applied first | modifiers apply in the order they were made, with the floor last. Apprentice + Loatheb Moonfire is (4); Millhouse then Loatheb is (5), the reverse (0) | Mana cost |
| Grove Tender, Gift of Mana | empty crystals | filled crystals | Grove Tender |
| Redemption | max Health set to 1 | damaged down to 1 of full Health, so it counts as damaged | Redemption |
| Lord Jaraxxus | kept the old hero's Armor | no Armor or Freeze carries over | Lord Jaraxxus (Classic) |
| Onyxia, Cenarius (Treants), Dr. Boom | summons piled up on the right | flank: right, then left (`Summon(..., flank)`) | Onyxia, Cenarius, Dr. Boom |
| Soul of the Forest | Treant took the dead minion's slot | far right (`Summon(..., rightmost)`) | Soul of the Forest |
| Poison Seeds | Treants interleaved with deathrattles, in the dead minions' slots | every deathrattle first, then the Treants on the right (`Ops.DestroyAndReplace`) | Poison Seeds |
| Death reactions | on-death Secrets (Duplicate, Redemption, Avenge) always resolved before deathrattles | one death's reactions resolve in their sources' play order | general death-phase rule |
| Kezan Mystic | rolled among every enemy Secret, often destroying a duplicate while a stealable one sat there | picks a Secret you don't have; destroys one only when all are duplicates | Kezan Mystic |

Also:

- **Shadowform's note was stale.** Its note in `tools/effects/finishers.csv` claimed the swap
  doesn't refresh the hero power. It does, in both engines, as in Hearthstone.
- **Two DSL flags were added.** `flank` and `rightmost` now exist for Summon, so Onyxia moved
  out of `Handwritten.lua`.

## Known differences (27)

### Fireplace is wrong (22)

| scenario | what Fireplace does | source |
|---|---|---|
| Windfury minion frozen by its first swing (2) | keeps it frozen | Freeze |
| Brewmaster returns a popped Divine Shield | keeps the popped shield | bounce resets the card |
| Bounced minion replayed | can attack at once | bounce resets the card |
| Commanding Shout (2) | no "Draw a card" | card text |
| Humility / Aldor under Raid Leader, Equality under Champion (3) | auras before "set" | Equality |
| Counterspell + Spellbender | both fire | Spellbender |
| Kel'Thuzad | wrong return order | Kel'Thuzad ("in the order in which they died") |
| Wailing Soul | silences itself | card text ("other") |
| Foe Reaper 4000 | no cleave | card text |
| King of Beasts | counts itself | card text ("other") |
| Kezan Mystic (2) | steals a duplicate, or rolls a duplicate | Kezan Mystic |
| Finicky Cloakfield | Stealth ends at end of turn | card text |
| Steamwheedle Sniper | Steady Shot still hits the hero | card text |
| Ancient Mage | no Spell Damage | card text |
| Ogre Warmaul | the hero never misdirects | card text |
| Nightmare (2) | no +5/+5, never destroys | card text |

### The pin differs from Fireplace's data (2)

- **Cleave** needs two enemy minions at build 7234; Fireplace carries the later value of one.
- **Mistress of Pain under Auchenai Soulpriest** loops until the hero dies, as it did before
  Lifesteal (wiki: Mistress of Pain). The oracle's shim doesn't loop.

### Undocumented (3)

The engine's behaviour is kept, and a source is still wanted for each:

- **Is a copy of a Frozen minion Frozen?** Fireplace says yes, the engine says no.
- **Where does a Damaged Golem land when an earlier minion died beside it?** Fireplace works
  out each corpse's slot after the earlier ones have left; the engine reads every slot first.
- **Does Secretkeeper grow on the opponent's Secrets?** The card says "a Secret is played".
  The wiki says only that it must be played from hand.
