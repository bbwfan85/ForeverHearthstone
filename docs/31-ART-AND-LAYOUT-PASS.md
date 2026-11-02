# 31. Art and layout pass after 0.1.1

Written 2026-09-26. `./run-tests.sh`: all green. **Lua only: `/reload` is enough.** No engine
change, so the duel protocol stays at 5: 0.1.1 players and players on this build can duel each
other.

## What was asked

> Make an art and asset/effects pass. The armor value isn't aligned in single-digit numbers.
> Cards still wobble when resizing the board. Is Armorsmith supposed to work on the card itself
> taking damage? Colour code the W/L. The pack open board has odd artifacting outside the
> image. Wide but short heights in the main menu put buttons off screen. The health and mana
> numbers are slightly too high.

## Letterbox bands (`W.EdgeBands`)

The pack room and the main menu's cabinet are drawn at their own shape. Where the window was
wider, the pack room stretched the outermost 0.6% of its picture across the gap, which is the
streaked band in the screenshot. `W.EdgeBands` replaces that on both screens:

* a strip of the picture next to each edge is mirrored **at its own scale** (at most 6% of the
  picture);
* a shade fades that strip out;
* plain near-black fills the rest, as Hearthstone's own letterbox does.

## The main menu in a wide, short window

The cabinet was scaled to cover the window (`W.CoverTexture`, focus .3). At 1842x672 the crop
cut off the cabinet's foot, and Open Packs, Resume and Close with it. At most 15% of the
cabinet's height may now be cropped (`CABINET_KEEP`). Past that aspect the cabinet is drawn
narrower than the window, centred, and letterboxed. Every plaque is placed through the same
mapping, so all six stay on the cabinet. New preview scenes cover this size: `hearth-wide`,
`packs-wide`, `practice-wide`, `collection-short` and `board-wide`.

## Numbers on their gems

* **Text digits ride high.** WoW centres a font string by its line box, which keeps room for
  descenders. Coustard's digits have none, so they sit 4.5% of the font size above centre
  (`W.DIGIT_RISE`, measured). The mana readouts and the hero's health, armor and attack are
  lowered by that amount.
* **Health sits on the drop's bulb.** The eye centres a drop on its round bulb, not on the
  middle of its box:
  * The hero's health moves from .109 to .092 of the frame's height, onto the bulb.
  * A card's health moves from 474 to 480 of 512.
* **The card's mana cost** is at the measured middle of its gem (y 40..122, centre 81). It was
  already right.
* **Armor** is centred on the shield's measured middle (.84, .362). The label was at .85, .35:
  a lone digit sat right of and below the middle, which two digits filling the shield hid. Two
  digits now shrink by 0.84, as the cards' numbers do.
* **Hero health is red whenever the hero is damaged**, as in Hearthstone. It was red only below 10.

## Cards wobbling on resize

Every texture of a card is taken out of the pixel grid (`W.NoPixelSnap`), so the pieces move
together. The digit glyphs, though, are created lazily, when a number is first set, which is
after that call. So the numbers still snapped on their own and jiggled on their gems while the
window was resized. They now opt out as they are made (`W.Unsnap`), as do the mulligan cross
and the hero cracks. `tests/test_ui.lua` checks every digit, and fails without the fix.

## "Whenever ... takes damage" on the minion itself

Hearthstone counts the minion itself, and counts a hit that kills it: damage triggers resolve
while the minion is still on the board. The engine already did this for every card checked, and
each case now has a test (`tests/test_review.lua`):

* Armorsmith counts its own damage, including a killing blow. A Divine Shield pop is not damage.
* Acolyte of Pain and Mech-Bear-Cat trigger on the hit that kills them.
* Frothing Berserker counts itself.
* Cult Master does not draw for minions that die with it. Scavenging Hyena gets nothing from
  Beasts dying with it.
* Lightwarden counts healing on itself.

## W/L colour

Wins are green and losses red: on the main menu's record card (deep inks on parchment), and on
the board's profile plates (bright on dark). Both use `W.RecordText`. The test stub now measures
text without its colour codes (`Stub.VisibleLen`), as the client does.

## Looked at, left alone

* The keyword boxes beside a card being disenchanted looked undimmed in the preview. They are at
  frame level 462, under the dialog's dim at 600. The preview renderer is at fault, not the game.
* The profile plate's portrait is blank in previews. The stub has no unit portraits; the client
  draws your face.
* "All Classes" under a neutral card in the pack reveal is deliberate (`PackClassName`).
