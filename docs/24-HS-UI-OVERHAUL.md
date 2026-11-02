# 24. A full Hearthstone UI pass: styles, baked card text, the board's true shape

Written 2026-09-24. `./run-tests.sh`: 1027 suites, 0 failures.

**New media: a full WoW restart is needed**, not just `/reload`. New:
- `Art/CardText/` and `Art/DeckTile/`
- `title-plaque`, `inhand_hero_power(_premium)` and `race-banner`
- rebuilt boards and rope

Follows docs/23. The before/after sheet is built with:

```
luajit tools/collection_preview.lua
python tools/review_sheet.py after --compare before
```

The output is `tools/review/before-vs-after.jpg`. The `before` renders are kept in `tools/review/before/`, which is gitignored.

## What was reported, and what changed

| Report | Cause | Fix |
|---|---|---|
| Hand-card text jagged and hard to read, worst on tilted cards | The client draws a rotated FontString without smooth filtering and snaps each word to the pixel grid on its own. docs/22 fixed where the words go, not how they are drawn | **Baked text.** `tools/build_card_text.py` renders every minion, spell and weapon's name and rules text in the shipped fonts, supersampled 6x and reduced with Lanczos, into `Art/CardText/<id>-n.tga` (256x32) and `-t.tga` (256x64). Each band is drawn as a card-sized region with clamped texcoords, the same trick the cost digits use, so it turns about the card's own pivot and is filtered like any texture. The layout mirrors the live one (same boxes, sizes, shrink and wrap). Live labels remain the fallback: an enlarged card (over 440px), a card whose text is not the printed text, or one with no bake. Baked bands are prefetched with the match art. 78 MB |
| Tooltip on the hero power a black box with a cyan outline | There was no hero-power frame, so the card fell back to its unskinned look | Hearthstone's hero-power card (HearthSim Sunwell, MIT; `tools/import_card_extras.py`): round art in the stone ring, gem on top, name scroll, text plate. The "**Hero Power**" prefix in the data is not printed on the card |
| (found) Weapon rules text dark brown on the weapon's dark slate | One ink colour for every frame | White on weapons, as printed |
| (found) Race never shown | `race` reached the widget and was not drawn | Sunwell's race banner under the text plate, with "Beast", "Murloc", "Mech" and the rest baked (`-r.tga`) or live |
| Board art stretched; "2:1 squashed into 16:9" (docs/13) | The 2048x1024 textures are a power-of-two canvas. The table in them is **1.683:1** (the reference is 3840x2281), so stretching was only right near 16:9 | `Layout.lua` places the picture at its true shape, scaled to the window's height. Every painted socket is mapped through `L.art` (`tx`/`ty`/`aw`/`ah`). A wide window gets bands of the picture's own curtain edge (`Board:FitBoardArt`); a narrow one crops the curtain margins to at most 8.5% each side, then letterboxes |
| Corner scenery clipped / "odd board" at the corners | The seam audit (below) showed the left-margin mirror in `polish_boards.py` cutting real overhangs flat against the rail: Orgrimmar's cannon barrel and smoke, Stormwind's lowest blocks. The bottom-right "ghost sketch" cleanup took the shadow under Stormwind's gryphon nest for sketch and swapped it for wood (a dark wedge) | Each board keeps its own left margin down to row 905 (the smear was only the stretched player badge below that). The rim cleanup stops short of the nest. Rebuilt with `tools/composite_boards.py` |
| Fonts, sizes, colours drifting per screen | Every call site chose its own | `W.Style` roles (face, size for a 720px window scaled between min and max, colour, outline, shadow) and the `W.Colors` palette, applied with `W.ApplyStyle` and `W.StyledText`, and re-applied on resize by `W.RestyleAll`. `tests/test_style.lua` fails if Main, Collection or Board set a font directly |
| Titles at different heights on each screen | — | One stone title plaque (`W.TitlePlaque`), cut as a 3-slice from Hearthstone's Open Packs room (`tools/build_title_plaque.py`): Practice and My Decks. The main menu is the box itself and carries no title |
| Buttons with squashed end caps | `tavern-button.tga` stretched whole | 3-slice plaques (`W.LayoutMenuPanel`). Callers that re-skin `bg` are unaffected |
| "Page 1 of 20" cut in half; count tabs over it | The book's bands were measured from the cover's outer edge, inside the 18px carved rim | Measured inside the rim (`BOOK_RIM`), with a foot band for the page count plus the owned-count tabs. Tabs are sized to what they show (colour codes excluded) and scale with the card |
| Unowned cards faded, page showing through | Whole card at 45% alpha | `W.SetGhost`: desaturated and dimmed, solid |
| My Decks: one deck a third of the way across an empty page | A centred block of three | Two rows, as many across as fit, from the top-left. The controls moved to menu items 41-44 |
| Deck list rows cropped from the square art | — | Hearthstone's deck-list strips (`art.hearthstonejson.com/v1/tiles`, `tools/import_deck_tiles.py`), 544 cards, 28 MB |
| Main menu cabinet and pack room stretched | — | The cabinet is cropped (`W.CoverTexture`) with its plaques, crest and candles mapped through the crop. The pack room is at its true 1.44:1 with edge bands, and the tray, well and deal are in its rect (`CL.PackRoom`) |
| Two dialogs, two faces | — | One `W.Dialog` (leather panel, `dialog` style, plaques) for disenchant and leave-duel |
| Music tooltip in WoW's GameTooltip | — | The parchment `W.HSPanel` |
| Hero tiles' flat black name strip | — | Hearthstone's gold-rimmed name plate (`W.NamePlate`) |
| Rope a red-and-white candy cane | A stripe texture tinted by urgency | A shaded, twisted hemp fuse (`tools/build_rope.py`). It is never recoloured; the flame at its end grows with urgency |
| Windows opened at three sizes and two stratas | — | The hub and collection open at 1280x720 on DIALOG, like each other |

## Kept as it was

- Fonts: Belwe and Franklin Gothic are commercial, so the OFL stand-ins remain (docs/11).
- Names are straight. The in-hand frames' banners are flat, so an arched name would sit off them.
- The painted "Waiting..." on each board's plaque: the live End Turn button covers it exactly at every window shape now.
- The Blizzard notice on the reference board.

## Tools

- `tools/review_sheet.py`: renders every preview scene and tiles a sheet, or a before/after with `--compare`.
- `tools/board_seam_audit.py`: each composited board, corner by corner, beside its own screenshot warped into place (`tools/board-audit/`).
- `tools/menu_preview.*` retired: it had been broken since docs/14, and `collection_preview` covers every screen.
- `APIProbe`: now also reports `FontString:SetRotation`, snapping controls, and `SetTexture` wrap arguments (for the baked text's clamp). Worth one run on the Forever beta.

## Check in game (full restart)

1. **Hand text:** hold 6+ cards. The tilted cards' names and rules text are smooth and straight, not stepped.
2. **Hero power:** hover your hero power and the opponent's. Hearthstone's hero-power card appears beside it.
3. **Board shape:** resize to about 4:3 and to very wide. Hero alcoves stay round-arched, not squashed or stretched. The End Turn button, deck slots, mana and history stay on their painted sockets. Bands at the sides continue the curtain.
4. **Corners:** Orgrimmar's cannon smoke reaches the curtain, Stormwind's blocks overhang the rail, and there is no dark wedge under the gryphon.
5. **Menus:** main menu plaques sit in the cabinet oval with their gilded caps. Practice and My Decks are titled on the stone plaque. The collection's "Page N of M" is whole. Unowned cards are grey, not see-through. The deck list shows Hearthstone's strips.
6. **Open Packs:** the room is not stretched, and the five cards land round the well.
7. **Rope:** brown throughout, and its flame grows at the end.

## Follow-up (same day, from in-game screenshots)

| Report | Cause | Fix |
|---|---|---|
| Orgrimmar still full of artifacts: a soft vertical cut and a red smear by the bottom-left banner, the concept sketch's grey spike beside the enemy's mana | Its corners came from a low-resolution 2013 screenshot blended onto the uncoloured sketch | `tools/build_orgrimmar_board.py`: the board is now Orgrimmar's own full-resolution painting (`orgrimmar.tga`, same source and calibration as the clean reference, so it registers to about 2px). Only the sockets the client fills live (hero alcoves, mana readouts, deck slots, the plaque) come from the composite. The painting's copyright notice is untouched and now shows at the bottom-left, as on the painting. `composite_boards.py` runs it last |
| Tall window: the space above and below the table full of streaks | The letterbox bands stretched the picture's edge row, which smeared the corner scenery | Above and below: the plain table wood from the picture's centre (above its top rim and below its bottom one). Beside: a narrow strip of curtain, mirrored. Each band darkens toward the window's edge (`page-shade.tga`) |
| The hand reaches too far left | The fan was centred on the room a full hand of ten needs, slid left of the mana tray, so a short hand sat well left of the hero | The cards actually held are centred on your hero, moved only as far as the tray and the window edge require (`Layout.Compute`) |
| The bot never takes its turn | Not reproducible headless: `tools/bot_turn_probe.lua` plays six turns with the full UI and the bot acts every time in 1.5-3.3 s. So an error that happens only in the client, inside the bot's timer, stops it silently; if it lands mid-animation it also leaves the board's presentation lock on | `Main:StepOpponent` runs each step under `xpcall`. On an error it prints the error to chat once ("the practice bot hit an error..."), releases the lock, marks that move refused and carries on. After 8 failures in a row it ends the bot's turn. **Please send the chat message if it appears.** Also: this update adds two files to the .toc (`CardText.lua`, `DeckTiles.lua`), and WoW only reads a changed .toc on a **full restart**, not `/reload` |
| "Choose Deck" / "Play" didn't match the art | The button was a generated flat amber pill, the one control not drawn in the tavern's art | `tools/build_play_button.py`: the carved plaque every other button uses (gilded caps, wooden frame), with its stone face and bevels lit Hearthstone amber, keeping the stone's grain and cracks. Same canvas, so it uses the same 3-slice. `build_hs_menus.py` no longer writes the old pill |

The preview tool gained a tall-window scene, `board-tall`.
