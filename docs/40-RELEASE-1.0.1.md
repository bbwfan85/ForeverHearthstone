# Forever Hearthstone 1.0.1

## Fixes

- **No more error inside dungeons and raids.** Midnight's addon restrictions,
  which Forever shares, hide some unit details inside instances. Kill rewards
  and the duel range check tried to use those hidden values and raised a Lua
  error. They now treat a hidden value as unknown: kills still pay, exactly
  once. One trade-off: inside an instance an elite counts as a normal mob,
  because its classification is hidden. Bosses still pay through their
  encounter.

## Look and feel

Found by photographing every screen inside the real client and reviewing the
shots (docs/39):

- Windows open sized to your screen (16:9 at about 86% of its height) instead
  of a fixed 1280x720. Resizing works as before.
- Minion attack and health numbers are larger, with Hearthstone's heavy outline.
  So are damage numbers.
- At the end of a game the whole table drains to grey, not just the cloth.
- Effects shed soft glowing motes instead of small hollow gold rings.
- "YOUR TURN" rises out of a gold glow.
- Settings, Progression and the confirmation popups use Hearthstone's
  parchment with dark lettering. The General tab is sized to what it holds.
- Deck boxes show each deck's signature card (its rarest, then costliest) rather
  than the same class portrait on every deck. Basic-only decks keep their hero.
- Deck list tiles: the mana crystal sits fully inside the tile, the cost digits
  are bold and centred on the crystals (here and in the mana filter), and the
  card art fades in instead of starting at a hard edge.
- Pack opening: the class captions under revealed cards are caption-sized.
- Disenchanting: the inspected card's keyword notes no longer draw over the
  confirmation, and the collection's own Craft/Disenchant buttons no longer
  show through the inspect view.
- The Victory and Defeat portraits fill their arches.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.0.1.zip, then restart WoW completely. Saved collections
carry over unchanged.

## Validation

All 1,286 automated suites pass (98,155 assertions). The visual changes were
checked in four in-client screenshot runs on retail Midnight, the test client.
A final look on a Forever client is still recommended. Network protocol
unchanged (10).
