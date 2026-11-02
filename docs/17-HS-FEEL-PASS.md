# 17. Hearthstone feel pass: history tiles, the Practice book

Written 2026-09-24. `./run-tests.sh`: 994 suites, 0 failures. Lua only -- no
new files -- so `/reload` is enough.

Every screen was re-rendered offline (`tools/collection_preview.lua` / `.py`),
plus the mulligan and a hand hover, and read against Hearthstone's own screens.
Most screens already matched. The table below lists what did not.

| Report | Cause | Fix |
|---|---|---|
| Play-history tiles looked like WoW, not Hearthstone | Each tile was a flat red or blue square with a **WoW spell icon** in the corner (`INV_Misc_Book_09`, `Ability_MeleeDamage`, `Spell_Nature_Lightning`). These were the only WoW client icons anywhere in the addon | The card art sits in the gilded rim used on the menus (`GoldFrame`) over a dark backing. A thin band inside the rim shows who acted (red for the opponent, blue for you). The corner badge is the game's own art: the **attack sword** (`hero_attack.tga`) for attacks, the **hero-power ring** (`hero_power.tga`) for hero powers and the **mana gem** (`mana_crystal.tga`) for played cards (`HISTORY_BADGES` in `Board.lua`) |
| Play needed an extra click every game | The deck book always opened with nothing chosen and Play dimmed, so each game took a deck click even when you had one deck. Hearthstone opens on a deck already chosen | The book opens on the deck you last played. If there is none, it opens on your duel deck, then on the first deck that is ready, and turns to that deck's page. Play is lit straight away. A click in the 0.4s after the book opens is ignored, so a double click on "Choose Deck" cannot start a game you have not seen |
| Stray crest above the Practice book | The main-menu cabinet stays behind Practice, dimmed. Its Hearthstone crest sat half-hidden behind the book's top edge, and the crest's cyan glow kept pulsing | In Practice the crest's light is off, and a shade falls from the top of the window (`page-shade.tga` rotated, drawn twice). This gives the top of the screen the dark vignette of Hearthstone's Play screen, and the crest is gone |

`tools/collection_preview.py` now draws `SetTexCoord`'s eight-argument
(rotated) form, and takes `FH_FALLBACK_FONT` for machines without Georgia.

Left as they are, by earlier decisions: the emote plaques name WoW emotes
(docs/13) and End Turn is never green (docs/15).

## Follow-up: the mulligan button

| Report | Cause | Fix |
|---|---|---|
| Mulligan button should match Hearthstone | It read "Keep Hand" / "Replace 2 Cards" and stayed up as a dimmed "Waiting..." after you confirmed (docs/14) | It reads **Confirm** whatever is marked; the red crosses already show what goes back. Once pressed it leaves, and only the heading ("waiting for your opponent...") stays while the opponent decides |

## Check in game (needs a client)

1. Play a practice game: the history tiles on the left are card art in gold
   rims, with a sword, a ring or a mana gem in the corner. Hovering one still
   shows the card preview.
2. Main menu -> Play Bots -> Choose Deck: a deck is already chosen and Play is
   lit. Double-clicking Choose Deck opens the book but does not start a game.
3. Finish a game, then open Practice again: the book opens on that same deck.
4. On the Practice screen, no crest shows between the title and the book.
