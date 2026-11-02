# Forever Hearthstone

A World of Warcraft addon for **WoW Forever** that recreates Hearthstone's
Basic, Classic, Naxxramas and Goblins vs Gnomes sets. You collect cards from
packs earned by playing WoW, build decks, practise against a bot, and duel
players standing next to you in the world.

## Install

Download `ForeverHearthstone-<version>.zip` from
[Releases](../../releases), and extract the `ForeverHearthstone` folder into
your Forever client's `Interface/AddOns` folder. When updating, replace the old
folder and restart the game completely.

In game: `/fh` opens the menu.

## Repository layout

| Folder | What it is |
|---|---|
| `ForeverHearthstone/` | The addon. `Engine/` is the card game and uses no WoW API, so it runs headless. `Client/` is the WoW layer. `Data/` is card data. `Art/` holds assets and their provenance reports. |
| `tests/` | Headless test suite on a strict WoW API stub. Run `./run-tests.sh` (needs LuaJIT, Python 3 and Pillow). |
| `tools/` | Asset import and build scripts, the release packager and the Fireplace rules oracle. |
| `docs/` | Design notes and release notes, numbered in order. |
| `APIProbe/` | Developer diagnostic: reports which APIs a client offers. Not needed to play. |
| `FHTour/` | Developer tool: photographs every screen inside the real client for visual review (docs/39). Not needed to play. |

## Building a release

```
python tools/package_release.py
```

This writes `dist/ForeverHearthstone-<version>.zip` from the `.toc` version, and
refuses to build if it finds credentials or personal paths.

Re-importing hero voice lines (`tools/import_hero_voice.py`,
`tools/import_presentation_media.py`) needs the HearthSFX web app's JavaScript
bundle saved as `tools/hearthsfx-app.js`. It is not included here because it is
another project's code. The imported lines are already in the addon.

## Credits

Hearthstone and World of Warcraft are trademarks of Blizzard Entertainment.
This is a fan project with no affiliation with Blizzard. Asset sources and
licences are listed in `ForeverHearthstone/Art/README.md` and the provenance
reports beside the assets.
