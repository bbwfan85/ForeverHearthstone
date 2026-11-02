# 25. Bounces follow the controller, voices play out, a tighter hand, the real End Turn plaque

Written 2026-09-25. `./run-tests.sh`: 1031 suites, 0 failures.

**New media: a full WoW restart is needed.** Rebuilt: `turn-button.tga`, `turn-button-enemy.tga` (now 512x256), `board_stormwind.tga`.

## What was reported, and what changed

| Report | Cause | Fix |
|---|---|---|
| Sapped a minion the opponent had Mind-Controlled; it came back into **my** hand | Every zone move (bounce, shuffle, Freezing Trap, Vanish, the Pirate/Secret/Demon movers, Recombobulator's swap) sent the card to `e.owner`, the player it *started* with. In Hearthstone it goes to whoever controls it now, which is why Shadow Madness + Youthful Brewmaster keeps the minion | `Game:MoveToHand`, `Game:ShuffleIn` and the `Ops` movers use `e.controller`, then re-home `owner` to match. `pluck` looks in the controller's lists first. `owner` stays as the record of where a card started (Mind Control still leaves it untouched). New suites in `tests/test_rules.lua`: Sap, Vanish, Freezing Trap on a stolen attacker, and Shadow Madness + Brewmaster keeping the card through the end of turn |
| A unit's voice cuts out when another card is played | `Main:StepOpponent` called `Sounds.CutCardAudio` before every bot action, fading whatever recording was still playing (a docs/17 choice) | No longer called. Recordings play to their end, as in Hearthstone. `CutCardAudio` remains for silencing everything at once. The test now checks that nothing is stopped by the next card |
| Hand spreads too far left, too much space between cards | The ideal pitch was 1.10 card widths, a gap. From five cards up the fan filled the full width a hand of ten needs, and because the mana tray bounds it on the right, it grew leftward | The pitch starts at 0.82 card widths (always overlapping) and tightens by 0.05 per extra card (`HAND_PITCH_ONE`, `HAND_PITCH_STEP`). Ten cards still hit `HAND_PITCH_FULL`. At 1280x720, six cards span 417px instead of 479px, and three span 264px instead of 347px |
| End Turn "far too blocky, is it sized right?" | No. It was drawn 10% wider and **34% taller** than the plaque painted on the table (`END_TURN_COVER`), squashing a 2:1 plaque to about 1.6:1. It was also cut from a low-resolution capture | `tools/build_turn_button.py` rewritten: the plaque is cut from the 3840px painting along its own dark outline, "Waiting..." is inpainted, and the gold is lifted to END TURN yellow (drained grey-gold on their turn). Layout's `ENDTURN_*` are the measured plaque (px 3013,957 to 3354,1133). The cover is now 1.02 x 1.03, so the button sits exactly on the painted plaque on every board |
| Stormwind artifacts by the gryphon nest (screenshot) | Two docs/14 cleanups in `polish_boards.py` target Orgrimmar-style sketch ghosts. The recess pass and the rim pass pasted mirrored plain wood over Stormwind's real bricks, leaving a flat brown crescent by the purple wing and a smooth band under the bricks. The composite also stopped at x=0.66 for the hero power, so the reference's bare floor showed beside the wing | `composite_boards.BR_EXTEND`: Stormwind takes its screenshot's bricks and wing edge from x=0.64, below the hero power. `polish_boards.BR_OWN` skips both passes for Stormwind. The sketch claw tips that reached the rail are refilled from the rail's own row profile (`RAIL_BR`) |
| (found) Stormwind: a pink blotch on the sand above the bottom-left bricks | The colour fit's red gain (near its 1.15 cap) on the screenshot's sand was only partly swapped for the reference's | `SAND_SIGMA` and a full swap where both images read as sand (Stormwind only) |
| (found) Stormwind: a grey sketch claw tip over the bottom-left rim corner | Every screenshot has the history icons there | Hand-traced (`SKETCH_TIPS`) and filled column by column, which keeps the rail's vertical edge sharp |

Rebuilding the boards leaves Orgrimmar byte-identical. Stranglethorn changes by less than 7/765 per pixel, through the shared rim profile.

The preview tool gained `board-hand`: six cards at 1280x720.

## Check in game (full restart)

1. **Sap / Brewmaster:** let the bot Mind Control (or Shadow Madness) your minion, then Sap it. It goes to the bot's hand.
2. **Voices:** play a minion and immediately another. The first minion's line finishes.
3. **Hand:** hold 3, 6 and 10 cards. The cards overlap at every count, and a short hand sits under your hero.
4. **End Turn:** the button is exactly the painted plaque's size and shape (no grey plaque showing round it), sharp at any window size. It is yellow on your turn and grey-gold on theirs.
5. **Stormwind:** the bottom-right corner shows bricks all the way from the purple wing to the rail, with no brown band, crescent or claw ghosts. There is no pink patch on the sand at the bottom-left.
