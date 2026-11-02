# 39. Screenshot tour and two-judge review — 2026-11-01

After 1.0.0, players reported that "a lot of things are just slightly off in
game". The offline previews (`tools/collection_preview.*`) could not catch that:
they draw the frame tree with Pillow, so they know nothing of WoW's fonts,
wrapping, texture filtering or UI scale. This loop judges **real client
screenshots** instead.

Forever is the target and retail Midnight is the test client (docs/07). The tour
uses only the addon's own code plus `Screenshot()`, `C_Timer` and frame APIs,
and looks everything else up with `rawget`, so a Forever gap skips a step
instead of erroring. A final pass on a real Forever client is still owed before
release.

## Pieces

| | |
|---|---|
| `FHTour/` | Dev-only addon. Never packaged (`tools/package_release.py` ships `ForeverHearthstone/` only). Linked with `tools\link-dev.ps1 -IncludeTour`. |
| `FHTour/Config.lua` | `FHTOUR_RUN`: bump it, `/reload`, and the tour plays once. `FHTOUR_ONLY` re-shoots a subset. |
| `Client/Main.lua` | At `PLAYER_LOGIN`, hands `ns` to `FHTour_Attach` if that global exists. Nothing else. |
| `tools/tour_collect.py` | Reads each shot's corner label, writes `tools/tour/run-N/NN-scene.jpg` + `index.json`. |
| `tests/test_tour.lua` | Runs the whole tour on the stub: no scene errors, the saved data is byte-identical afterwards. |

**The sandbox.** The tour opens packs, builds decks and disenchants a card,
always against deep copies of both SavedVariables tables. The originals are put
back at the end and on `PLAYER_LOGOUT`, so a `/reload` mid-tour still saves the
untouched collection.

**Scenes.** Menus (hub, practice, deck choice), the collection on two pages,
deck editing and hover, the deck browser, the pack room, pack opening at five
moments, the disenchant confirmation, all three settings tabs, both world
toasts, then the board in posed states (every portrait and minion state, a full
ten-card hand with seven minions on each side, the turn banner, emotes, spells,
the hero shattering, the post-game screen, minion hover). Then a **real
practice match plays itself**: the AI drives player 1 through the same
`Animated` wrapper a click uses, with shots at seeded-random moments and the
result screen at the end.

**Not covered:** the targeting arrow (it follows the real cursor, which an
addon cannot move), duels (two clients), and different window sizes (the tour
shoots at your real resolution and UI scale, which is the point).

## The loop

1. I change the addon and bump `FHTOUR_RUN`.
2. You `/reload` and leave the client alone (~6 minutes; don't go AFK, because
   AFK pauses practice).
3. `python tools/tour_collect.py <run>` files the shots.
4. Two judges, run as separate agents, score every shot on the rubric below.
   Each sees ONLY this run: its crops are copied into `run-N/judge-input/` and
   it is told to open nothing else -- no earlier runs' images. A judge that
   browsed every run's screenshots (round 3) took far longer and mixed
   already-fixed shots into its verdict. Comparison with earlier runs comes
   from a short text list of the previous issues, never their images. Zooms
   are capped at about two per scene.
5. Fix the worst issues first; repeat until the bar is met.

## Rubric

Each judge scores every screenshot 0–10 against **Hearthstone as shipped**
(2014–2015 era UI: Basic/Classic/Naxx/GvG). `ForeverHearthstone/Art/orgrimmar.tga`
is a real Hearthstone screenshot and is the board reference. The anchors:

| Score | Means |
|---|---|
| 10 | Indistinguishable from Hearthstone at a glance and at 100% crop. |
| 9.5 | Reads as Hearthstone; a trained eye finds at most one tiny flaw (≤2 px off, one slightly soft texture). |
| 9 | Clearly Hearthstone; one or two flaws a player would notice if looking. |
| 8 | Right style; several visible flaws (misaligned text, an odd gap, a stretched asset). |
| 6–7 | Looks like a WoW addon *imitating* Hearthstone. |
| ≤5 | Broken: clipping, overlap, missing art, unreadable text, wrong state. |

**Judge A, the art director:** fidelity. Proportions and placement against
Hearthstone, typography (Belwe or its stand-in, outlines, sizes), colour and
lighting, ornament, card frames, gems, and VFX timing and weight in the
mid-animation frames.

**Judge B, the QA inspector:** defects. Alignment and centring, text overflow
and wrapping, clipping, z-order, overlaps, stretched or blurry textures, seams,
inconsistent spacing, and wrong game state (a number that disagrees with the
board, a highlight on the wrong thing). Also anything WoW's own UI puts on top.

Every issue a judge reports carries a **severity** (blocker / major / minor /
nit), **where** (a screen region or element), **what** is wrong, and the
**expected Hearthstone behaviour**. Issues are deduplicated across scenes
before fixing: one misplaced font usually shows up in twenty shots.

**Intended, not defects.** These are the owner's design calls; judges must not
score them down:
- Both hands hang off the window's edges (yours below, theirs above), even
  over the WoW UI. The owner likes it that way.
- The emote menu ("Thank you!", "Well played!", "Well met!", "Choo choo!",
  "Ptooey!", "RAWR!") maps to WoW's own character emotes, which is better here
  than Hearthstone's six.
- The default window size: it fills ~86% of the screen height, and players
  resize it as they like.

**The bar:** the owner set it at **8/10** on 2026-11-01 (the first target was
9.5): the average across both judges at 8 or above, plus any easy wins on the
way. Big art rebuilds that only raise a judge score are not worth it. The judges are LLMs and their scores are
subjective; the fixed anchors and the fixed scene list are what make one run
comparable with the next.
