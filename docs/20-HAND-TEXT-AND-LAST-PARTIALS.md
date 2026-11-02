# 20. Hand-card text, and the last partial cards

Written 2026-09-25. `./run-tests.sh`: 1014 suites, 0 failures. Lua and data
only -- `/reload` is enough.

## Rules text on cards in hand

| Report | Cause | Fix |
|---|---|---|
| Words and letters missing ("Deal 1 damage to enemy minions", "Gain 1 Mana Crystal thi turn only") | `Widgets.RichText` draws each word, or each bold/regular piece of one, as its own FontString so keywords can be bold. The runs were pooled and never sized: anchored by one corner, the client sized each from its text, and a run reused for a longer word could keep its old, narrower width, clipping or hiding the word | Every run is given its size: its measured width with a little spare, and one line's height |
| Text off-centre, a line hanging out of the box | The runs hung from the hidden body FontString's top-left corner, so they depended on where the client settled that invisible label | The card layout records the text box's top-centre on the card (`w.bodyAt`) and the runs are placed from the card frame itself |
| (likely in game) A text laid out before its font had loaded | The fonts are the addon's own; a font the client has not loaded yet measures 0 wide, and the layout kept that | A layout that measured a word at 0 is laid out again 0.2s later (up to five tries) |
| (found on the way) At the smallest size, one over-long word put the whole text on one line | The fallback laid out with an unlimited width | Only that word overflows, on a line of its own |

Tests: every word of Wisp, Fan of Knives, The Coin and Deadly Poison is present
on a hand-sized card, including when a card is re-dealt shorter and then longer
text; every run is wide enough for its word and placed from the card frame;
and a text measured before its font loaded is laid out again.

The offline previews (`tools/collection_preview.py`) measure with the stub's
approximate glyph widths but draw with the real fonts, so their word spacing
is uneven; the real client measures and draws with the same font.

## The last partial cards

| Card | Was | Now |
|---|---|---|
| Summoning Portal | Could reduce a minion below 1 | `AuraCost(sel, delta, floor)`: (2) less but not below (1); a 0-cost card is never raised |
| Betrayal | Dealt as spell damage: Spell Damage boosted it, Poisonous did not apply | `DamageFrom(from, sel, amount)`: the betrayed minion deals it |
| Harrison Jones | Destroyed the weapon, drew nothing | Draws one card per point of the weapon's Durability, then destroys it |
| Mechanical Yeti, Elite Tauren Chieftain | Only their owner got a card | Each player gets one, rolled separately |
| Shadow Madness | "Can attack now" was a real Charge keyword (a Silence took it away); a full board at end of turn left the minion with you for good | `TakeControl(sel, ready)` clears summoning sickness without a keyword; handing a minion to a full board destroys it, as in Hearthstone |
| Blessing of Wisdom | On an enemy minion, its controller drew | `CasterTrigger(sel, EVENT){ops}`: a granted trigger that acts for the player who granted it |
| Poison Seeds, Reincarnate, Ancestral Spirit, Flare | Flagged partial | Already fixed by engine work since (deathrattles append; destroyed secrets leave the zone); the notes are corrected and now tested |
| Iron Juggernaut | Its note pointed at a PARTIAL remark that did not exist | Note corrected |

No card in `tools/effects` is flagged PARTIAL any more; `tests/test_partials.lua`
holds a suite for each of them. An older test that pinned Blessing of Wisdom's
wrong behaviour on purpose now asserts the right one.

## Check in game (needs a client)

1. Hold Fan of Knives, The Coin, Deadly Poison and a Taunt minion: every word
   of their text shows, centred in the text box, keywords bold.
2. `/reload` with cards in hand: the text is right on the first draw too.
