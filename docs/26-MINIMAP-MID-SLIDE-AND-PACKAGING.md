# 26. A minimap button, a spell cast mid-slide, and the release package

Written 2026-09-25. `./run-tests.sh`: 1033 suites, 0 failures.

**New media and a changed .toc: a full WoW restart is needed.**

## What was reported, and what changed

| Report | Cause | Fix |
|---|---|---|
| Killing a minion, then at once casting a spell on another, left the board misaligned | When a minion died, the survivors slid into the gap. Starting the next spell (`Board:BeginPresentation`) threw every running slide away. A tween writes its in-between rect to `widget.rect`, so those minions stayed part-way across: drawn there, recorded there, and aimed at there | Running slides land at their destination (`t.to`) instead of stopping. Test: "a spell cast mid-slide finishes the slide, not freezes it" |
| Players should not have to remember `/fh` | — | A minimap button: the Hearthstone medallion cut from the card back (`tools/build_minimap_icon.py`), in WoW's round minimap border. Left-click opens the main menu, or brings back a hidden match. Right-click opens the collection. Drag moves it round the rim, on round or square maps. Its angle and visibility are saved account-wide (`ForeverHearthstoneDB.minimap`), and `/fh minimap` hides or shows it. The `.toc` also lists it in the retail Addon Compartment (`IconTexture`, `AddonCompartmentFunc`) |

## The release package: `tools/package_release.py`

```
python tools/package_release.py --version 0.1.0-beta.1
```

This writes `dist/ForeverHearthstone-<version>.zip`, which is gitignored and holds one `ForeverHearthstone/` folder. The repo keeps TGA as the source format, because every build tool writes TGA and regenerates the Lua that names it. Only the copy is converted:

| | Files | Before | After |
|---|---|---|---|
| Card art and hero portraits (the Art root's card ids), plus deck-list strips | 1411 | 197 MB TGA | JPEG, quality 95, 4:4:4 |
| Everything with transparency: frames, masks, baked card text, UI | 1876 | about 190 MB TGA | PNG, lossless |
| Never drawn: the stand-in and reference boards, the old End Turn states, `menu-pack-room`, the ribbons, `menu-nav`, the digit sheet | 14 | 60 MB | left out |
| Painting sources (`*.jpg` at the addon root) and preview renders | 6 | | left out |
| **Addon folder** | | **571 MB** | **203 MB** (182 MB zipped) |

Every path in the copy's Lua and `.toc` is rewritten to match. The build then checks the copy, and fails on any of these:
- a TGA left over;
- a written-out texture path (1021 of them) that does not exist;
- a runtime-built family (`fx-`, `class-`, digits, rarity gems, masks, `inhand_`, card text, deck strips) left empty;
- any reference to a pruned file;
- a Lua file that no longer parses (checked with luajit).

It also adds a player `README.txt` covering install, the minimap button and the commands.

WoW loads PNG and JPEG through `SetTexture`, per the [Warcraft Wiki](https://warcraft.wiki.gg/wiki/API_TextureBase_SetTexture). PNG arrived in 10.0.7, and Forever is on the 12.x API. **This has not been seen in game yet:** the dev install is a junction to the repo, so it still loads TGA.

Audio is shipped as it is (118 MB). It is already mono 16-bit, mostly 48 kHz, so only a lossy re-encode would shrink it. Ogg Vorbis would take it to roughly 15-20 MB, but there is no encoder on this machine.

## Check in game (full restart)

1. **Minimap:** the medallion sits on the minimap's rim. Left-click opens the main menu, then closes it. Right-click opens the collection. Drag it round the rim, `/reload`, and it stays put. Check that `/fh minimap` hides it and brings it back. It is also listed in the Addon Compartment (the dropdown by the minimap).
2. **Mid-slide:** kill a middle minion with a spell, then immediately cast a targeted spell on a survivor. Every minion ends in its slot and the spell lands on its target.
3. **The package, before any release:** move the junctioned folder aside (`tools\link-dev.ps1 -Unlink`, or rename it), unzip the zip into AddOns, and restart. Check these:
   - card art, hero portraits, deck strips, boards, baked card text, rarity gems and spell effects all appear;
   - the End Turn plaque and the minimap icon are there.

   A blank square anywhere means that format did not load.
