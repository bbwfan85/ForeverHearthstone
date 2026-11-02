# Retail fixes and testing — 2026-09-20

## Deploying to the client

The AddOns folders are NTFS junctions pointing back at this repo, so there is
no install step: the file you save here is the file the client loads.

```
powershell -ExecutionPolicy Bypass -File tools\link-dev.ps1
```

Run that once, with WoW fully closed (it holds handles on loaded addon files).
It moves the existing copies to `tools\install-backups\pre-link-<stamp>\` and
links `ForeverHearthstone` and `APIProbe` in their place. Junctions need no
elevation and no Developer Mode. SavedVariables live in `WTF\`, not in the
addon folder, so nothing player-owned is moved or rewritten.

After that:

- Editing an existing `.lua` file: `/reload` in the client.
- Adding a file, or editing the `.toc`: full client restart. WoW reads the
  TOC's file list once at startup.
- Adding or changing `.tga` art: full client restart. Textures are cached at
  startup.

`tools\link-dev.ps1 -Unlink` reverses it, leaving real copied folders behind.
`tools\install-retail.ps1` is the copy-based path and is only needed then.

## Boards

Matches randomise between every board installed under `Art/board*.tga`. The
rotation is discovered, not listed: drop a board in, and it joins.

**Orgrimmar** is the reference board and currently the only one in the
rotation. It is the CLEAN copy -- empty hero alcoves, an empty mana trough, a
plaque with no live words -- because those are the sockets the addon fills.
`orgrimmar.tga`, the coloured screenshot, is packaged but deliberately kept OUT
of the rotation: it has two hero portraits, two "30"s and a "0/1" painted into
the sockets, which are precisely the things drawn live. It stays because it is
what says where the sockets are.

The three `boardN` textures are stand-ins from a fan project. None of them is
one of the originals, and none is in the rotation.

To add Stormwind or Stranglethorn Vale from files you already have:

```
python tools/grid_overlay.py ~/stormwind.png stormwind-grid.png
python tools/add_board.py ~/stormwind.png stormwind 0.155 0.845 0.305 0.545
```

The grid overlay is for reading off four numbers: the left and right edges of
the pale playing surface, its bottom edge, and the height of the seam across
its middle. There is no reliable way to find them automatically -- each board
is an illustration with a differently coloured and differently cropped table --
so an eye does it once, the same discipline as `/fh icons`.

`add_board.py` then records the measurement, **normalises** the image so its
surface and seam land where the layout expects them, writes the TGA and adds it
to the rotation. Normalising is what makes one set of layout constants correct
for every board: the End Turn plaque and deck slots painted on the art line up
with the live controls without touching anything.

Removing a board is deleting its `.tga` and its line in `HearthstoneArt.lua`.

## Checking the layout without launching WoW

```
luajit tools/layout_preview.lua 1600 900 > layout.json
python tools/layout_preview.py layout.json board1 preview.png
```

Draws every computed rect over the board texture. The layout tests prove the
solver's own invariants -- nothing overlaps, nothing escapes, seven minions
always fit -- but they cannot say whether the result lines up with the painted
table. This can, in a second.

## Sound

```
/fh sound
```

Plays every sound a match uses and prints which SOUNDKIT candidate each one
resolved to, or that none exists on this client. Sounds are looked up in the
client's own table, which cannot be read from outside the game, so this is the
only way to turn "the game is silent" into a list of names.

## Changes

- Board and card labels receive fonts before any SetText calls. The old stub
  masked this constructor failure; the strict stub now reproduces it.
- Board and collection have close buttons and register for Escape dismissal.
- Collection scrolls one row per mouse-wheel notch, including over cards.
  Prev/Next are hidden; Open Pack and crafting controls have separate space.
- Normal Basic cards cannot be disenchanted. Free class progression copies
  are protected too, preventing dust-then-login farming. Login restores missing
  neutral Basics without removing dust earned under the old behavior.
- Craft/disenchant animates a pooled copy at the selected card's position, so a
  grid refresh, last-copy removal or scroll cannot animate a different card.
- Local Hearthstone illustration textures, blank card frames, card backs,
  hero/power frames, mana and board artwork are packaged with the addon.
- APIProbe no longer runs automatically or exercises experimental templates,
  keyboard, emote or network calls. Its explicit command inventories globals
  and namespaces. The original protected-action stack was not available, so
  the exact offending API is not established.

## In-client smoke test

1. Restart WoW completely after installing this update, because it adds an Art
   directory and hundreds of new texture files. Normal later Lua-only updates
   can use `/reload`.
2. Leave APIProbe disabled for the first gameplay check. It is diagnostic-only
   and ForeverHearthstone does not depend on it.
3. Run `/fh` or `/fh practice`. Confirm the board, mulligan and card artwork
   appear. Test X and Escape, then `/fh show` to restore the board.
4. Run `/fh collection`. Scroll with the pointer over empty space and over a
   card. Check top/bottom bounds and filter reset. Select a Basic card: the
   disenchant button should be disabled.
5. With an earned, disenchantable card selected away from the first slot,
   disenchant only if you intend to spend that card. Its animation must remain
   at its own location. Crafting still requires earned dust; no currency or
   packs are injected by this update.
6. Open an owned pack and check card backs, reveals and sounds. Inspect hand
   hover/highlighting and movement when drawing or playing cards.
7. If something fails, enable Lua errors with `/console scriptErrors 1`, run
   `/reload`, reproduce once, and capture the first full error and screenshot.

Headless regression tests cover the fixes, packaged art paths and TGA formats.
They do not prove real WoW rendering, audio, taint behavior, or two-client play.
This update is not a claim of pixel-perfect or feature-complete Hearthstone.
