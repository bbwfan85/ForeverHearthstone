# 14. Polish pass: board seams, card gems, windows, practice pacing

Written 2026-09-24. `./run-tests.sh`: 981 suites, 0 failures. **Fully restart
WoW**: there are new textures (`endturn-glow`, `close-x`, twelve
`rarity-<type>-<rarity>`) and a new sound (`Sounds/UI/draw.wav`); the client
only picks up new files at start. After that, Lua-only changes need `/reload`.

## What was reported, why, and what changed

| Report | Cause | Fix |
|---|---|---|
| Draw sound loud and unpleasant | The draw played `whoosh.ogg`, a full-scale transition sweep. `PlaySoundFile` has no volume argument, so the file itself must be quiet | `tools/build_draw_sound.py` builds `draw.wav`: a soft 0.3s paper swish, band-passed noise sweeping upward, peaking at -18 dBFS (about the level of the other short cues). `card_deal` plays it |
| End Turn glowing green at the start | Green (nothing left to do) is correct Hearthstone behaviour, but it lit the instant a turn began -- on turn one, before the banner and draw had even landed -- and its breathing glow was the whole plaque added onto itself | The plaque stays yellow for `Board.END_TURN_HOLD` (2s) after your turn starts. The glow is a new face-only texture (`endturn-glow.tga`), tinted per state, so the silver bevel no longer flashes |
| End Turn doesn't fit, even yellow | The live plaque sits on the painted socket to the pixel (checked); the label filled ~86% of the face, edge to edge | The label fits 56% x 34% of the plaque, inside the face with a margin |
| Name-tag icons no longer show your character | `hs-round.tga` is a solid gilded disc, drawn *above* the portrait | The disc is behind the portrait (sublevel -1); the portrait is larger inside it |
| Art quadrant edges have missing sections; blue ribbon artifacts on the far left | Compositing seams (below) | `tools/polish_boards.py` (below) |
| Volume slider on the mute button | -- | Hovering the speaker drops a slider (`Widgets.VolumeSlider`): click or drag the trough, or use the wheel. It sets WoW's **Sound Effects** channel (`Sound_SFXVolume`), which every sound this addon plays on -- the same setting as WoW's own Sound options, not a hidden second one. Turning it up while muted unmutes |
| Duel X not centred | A letter "X" is centred by its font's line box, not its ink | The close button draws `close-x.tga`, a cross centred by construction |
| Emote text | The labels were Hearthstone's ("Sorry", "Oops", "Threaten") but your character performs /train, /spit and /roar | Thank you! (/thank), Well played! (/congratulate), Well met! (/hello), Choo choo! (/train), Ptooey! (/spit), RAWR! (/roar) |
| "YOUR TURN" out of place | A procedural vector badge (flat pill, gilded wings, gem) over painted art | Big gold lettering over a feathered haze with two fine gold rules -- the way Hearthstone floats it over the table. No Hearthstone graphic for it exists in any source we use (checked the wiki file index, Rymedy, Joust) |
| Card crystal misplaced, not Hearthstone's | A generated white diamond, tinted, drawn above the name banner -- and on Basic cards, which have none | Hearthstone's own gems set in their sockets, from HearthSim's Sunwell renderer (MIT; `tools/import_rarity_gems.py`, provenance in `Art/rarity-gems-report.json`, licence in `Art/rarity-gems-LICENSE.txt`). Placed by Sunwell's `rarityGemCoords`, carried onto the Joust frames by the fit the cost/attack/health badges give (x' = 0.4218x - 12.5, y' = 0.6046y - 25.2), centred on each banner by eye (`Widgets.GEM_SOCKET`). Basic cards show no gem |
| Resize jumps; /reload keeps a bad size | The board was `SetUserPlaced(true)`, and every window was a named, moved frame, so WoW's layout cache restored its anchor and size on each reload. Each screen also kept its own rect, so switching screens moved and resized the window | All three windows (hub, collection, board) share one **session-only** rect (`Widgets.SharedWindow`): move or size one and the next opens there. `SetDontSavePosition(true)` keeps them out of the layout cache, so `/reload` returns every window to its default. The grip clamps the window into its own bounds *before* `StartSizing`, so a shared size below one window's minimum can't snap |
| Still jumped: resize the menu/collection, go to Open Packs after a reload | `SetDontSavePosition` stops WoW *saving* a rect but not restoring one an older version saved; the collection is built lazily, so the stale cached size landed when packs were first opened. And the menu's floor (800x600) was above the collection's (760x560), so a small shared rect grew on every trip to the menu | Until the player moves or sizes something this session, every window is put back at its own default, centred, on every show. All three windows share the 760x560 floor |
| Deck builder spacing; "2 -> 4 cards a page" | The solver only made 4 or 8 columns (2 or 4 a page), or 3 across the whole spread with the middle card on the spine; it chose by page coverage alone, so near-ties flipped card sizes by 70%; and every leftover pixel went into the gaps | Even columns only (whole cards per page), at least two a page; chosen nearest a target card width (130px, scaled with window height only) while filling the page; gaps capped (34% of a card across, 14% down) with the block centred on each page. 3 a page is now common (the deck builder at 1660x891) |
| Practice match runs in the background | The turn clock is an OnUpdate on a parentless frame and the bot runs on timers: closing the board (the menu keeps the game) left the rope burning and the bot playing | `Main:PracticePaused()`: with the board closed, or while WoW flags you AFK, the rope stands still and the bot waits. WoW gives addons no focus event, so an alt-tab alone only pauses once you're flagged AFK |
| Bot slow to act after the rope | A bot move refused only because an animation was still playing was recorded as *illegal*, so it abandoned its best plays for the rest of the turn | That refusal now retries 0.2s later |
| Replace-cards button doesn't fit in | The flat amber pill (`play-button.tga`) stretched to another aspect ratio | The painted tavern button used for Rematch / Main Menu, the same size, with "Keep Hand" / "Replace 2 Cards" / "Waiting..." |

## The board seams (`tools/polish_boards.py`)

Runs after `repair_board_corners.py` in `composite_boards.py`. The table is
mirror-symmetric, so each seam is replaced from the board's own mirror image:

* **The bottom-left rim.** Every source screenshot had your hand over it, so it
  was half screenshot, half reference (washed out, carrying the reference's
  grey sketch claws), with a hard rectangular cut where the scenery stopped.
  It is rebuilt from the mirror; along its straight run, from one row profile
  shared by all three boards (the median, so no single board's own corner
  overhang can move it), which also fills the right-hand mana gem's pill.
  Scenery really overhanging the rim is kept, recognised per board by colour
  (`RIM_SCENERY`): the stone is desaturated; Orgrimmar's claws and banner are
  warm, Stormwind's blocks are slate blue, Stranglethorn's leaves and rock are
  strongly coloured.
* **The left margin** below the clean curtain, where the screenshot's edge had
  been stretched into streaks (the "blue ribbon" artifacts): the mirrored right
  margin, faded in over 60 rows, keeping hand-traced polygons of the scenery
  that genuinely overhangs it (`MARGIN_KEEP`).
* **The lower left rail**, smudged where the screenshot ran out: taken from the
  clean reference table.
* **Ghost sketch** along the bottom-right rim.

Left as is: a small pale smudge above the enemy mana gem on Stormwind (mirroring
it would have mirrored the gem too).

## Not verifiable headless

Audio loudness, the look of the slider and the new textures in the real client,
and the window behaviour across a real `/reload` all need an in-game check:

1. Restart WoW. `/fh practice`: draws should be a soft swish.
2. Your first turn: the plaque is yellow for two seconds, then green only if
   you truly have nothing to do.
3. Name tags show your character's face; hover the speaker for the slider.
4. Close the board mid-turn: the rope stops; Resume Match continues it.
5. Resize the board, open the collection (same place and size), `/reload`:
   every window is back at its default.

`tools/menu_preview.lua` was already failing on HEAD (`ui.menuItems` is nil for
the Packs capture); it is untouched here.
