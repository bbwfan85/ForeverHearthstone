# 15. Polish pass 2: End Turn, the rope, board ends, audio, pack reveal

Written 2026-09-24. `./run-tests.sh`: 985 suites, 0 failures. Lua and art
only -- no new files -- so `/reload` is enough. Supersedes the End Turn row of
docs/14.

| Report | Cause | Fix |
|---|---|---|
| Right-click a card when opening a pack | Pack cards registered left clicks only, and any click revealed (or, once all were revealed, closed the pack) | Right-click on a revealed card shows it enlarged (`CollectionUI:InspectCard`), without craft/disenchant; on a face-down card it flips it. Right-clicking after the last reveal reads the card rather than closing the pack |
| Audio not in sync when bots play fast | Action sounds fire from the same timelines as the visuals, and those are sped up when the bot hurries; the card *recordings* (1-3s play/attack/death clips) are not, so one action's clip ran on over the next | Card recordings keep their handles; `Sounds.CutCardAudio` fades out whatever is still playing when the bot begins its next action |
| End Turn looks like white text on a yellow rectangle; sometimes green | docs/14 laid a cut-out of the painted plaque exactly over itself, with white lettering, a green "nothing left to do" state and a small click area | Back to the earlier button: Hearthstone's gold plaque (`turn-button.tga`) drawn 10% wider and 34% taller than the painted socket so it covers it, dark capitals on the gold face, the whole drawn button clickable. Yellow on your turn, dimmed on theirs. Never green |
| Rope sound, visual and timing don't line up | Two faults. The rope was run through `RunPlans`, which speeds up anything longer than 2.6s -- so the 15s rope always ran at 2.5x: burnt out, and its end sound played, 6s in, while the turn ran 9s more. And its timeline ticked on frame time, so it kept burning while the turn clock stood still (your own long animation, a paused duel or practice) | The rope has its own slot (`Main:StartRope` / `TickRope`), never sped up, advanced by exactly the step the director's clock takes: burn, end sound and expiry are one clock. The fuse loop stops re-lighting while the clock is halted. `tests/test_opening.lua` checks half-burnt at half-way, still, when paused, and heard as the turn passes |
| Board quadrants still have grey areas, worst at the left of the bottom-right | Every source screenshot had your hero power at the left end of the bottom-right recess and the enemy's mana readout at the left end of the top-right one, so the corners stopped short and the reference's bare floor and grey sketch showed | `polish_boards.py` fills both from their mirror image (the other corner's painted end): flat pixels in the bottom-right recess, grey (sketch) pixels in the top-right, never the table's sand |
| Victory audio wrong, too long, keeps playing after leaving; no Lich King / "champion" | `victory.mp3` is the modern game's long track | Victory is the classic-era `Pegasus_Stinger_Alliance` (defeat was already a classic stinger). `Sounds.Play` returns the handle; the board stops its result sound when it is hidden or the match resets |
| Hearthstone's song at the main menu | Music was opt-in and off by default, so the menu theme had never played | Music is on unless turned off (`/fh music`, saved). The main menu plays `mainmenu.mp3`; matches keep their mulligan and duel tracks; mute silences it |
| Volume slider in the top right, everywhere | The speaker lived only on the board | `Widgets.SpeakerButton`: the speaker with its hover slider on the board, the main menu and the collection, all one setting |

WoW's own music toggle and Music volume still apply to `PlayMusic`; if the
menu is silent, check WoW's Sound options (Music enabled).

## Follow-up

| Report | Cause | Fix |
|---|---|---|
| Red banner scrap on Orgrimmar | The bottom-right recess fill mirrored in a piece of the bottom-left corner's Horde banner | `polish_boards.redye` re-dyes its red to the recess's own orange floor, keeping its light and shade (`DYE`) |
| Volume slider "doesn't work" | It moved only the Sound Effects channel, and the music (most of what you hear at the menu) is on the Music channel; its grab area was also just the 8px trough | It sets both Sound Effects and Music (WoW's own settings for them), and the whole panel width is draggable |
| Mute only stops the music | WoW cannot pause music; unmuting restarted it only during a match | Unmuting starts the right track for whatever is open |
| Music keeps playing after /fh is closed | The match track kept going while a practice game was kept behind a closed board, and nothing stopped music when the last window closed | `Main:SyncMusic` decides from what is on screen: the board plays the match music during a game, the menu and collection play the theme, nothing open plays nothing. Every window's show and hide calls it |
| Speaker too far left in Open Packs | Fixed offset; the pack room hides My Decks | Anchored beside the leftmost visible button |
| Rope sound keeps replaying | The 4.3s fuse recording (a strike, a sizzle, a fade) re-lit every 4.1s | `tools/build_rope_sound.py` makes `rope-burn.wav`: the strike once, then the recording's steady sizzle for 16s (overlapped random stretches, no audible repeat), then its fade. Played once per rope, stopped while the turn clock stands still, stopped when the rope clears |

New file: `Sounds/UI/rope-burn.wav` -- **restart WoW** once for it.
| Crafting should say what it costs | The price was only revealed by pressing Craft and being refused | Craft buttons read "Craft 40", Disenchant "Disenchant +5" (footer and enlarged card), and the enlarged card adds "Crafting costs 40 dust -- you have 12 (28 short)" (`CollectionUI:LabelCraftButtons`) |
| "Restore #4 Health"; no client markup in card text | The source text carries the client's own markup (`<b>`/`<i>`, `[x]`, and `$` / `#` before numbers spell damage or healing can change); the importer dropped the tags but kept the markers | `tools/import_cards.py` drops all of it, so the game data holds the text exactly as Hearthstone shows it and no display site has to clean it. `tests/test_ui.lua` checks every printed card |

## Bold keywords, and music across menus

| Report | Cause | Fix |
|---|---|---|
| Keywords should be bold, as in Hearthstone | A WoW FontString has one font; the importer also stripped the `<b>` that marks keywords | The importer keeps `<b>` (only). `Widgets.RichText` lays the rules text out word by word, each run in regular (Libre Franklin SemiBold) or bold (**Libre Franklin ExtraBold**, new, OFL), wrapped and centred in the body's box and stepped down in size until it fits. The body FontString keeps the plain text and box and is not drawn; its Show/Hide drive the runs (face down, in play). Every other reader uses `Widgets.PlainText`; collection search strips the tags |
| Music restarts moving between menus | Screens swap in two steps (the collection hides, then the menu shows), and for that instant nothing was open | A window's show/hide settles the music on the next frame (`Main:SyncMusicSoon`), so a swap never passes through "nothing open" |

New file: `Art/Fonts/LibreFranklin-ExtraBold.ttf` -- **restart WoW** once for it.
`tools/collection_preview.py` now skips invisible labels; its word placement
uses the stub's approximate glyph widths, so rich text looks slightly uneven
in previews but is measured with the real fonts in game.
