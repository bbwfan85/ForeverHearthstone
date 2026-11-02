# 22. Text on a leaning hand card

Written 2026-09-25. `./run-tests.sh`: 1017 suites, 0 failures. Lua only --
`/reload` is enough. Follows docs/20.

| Report | Cause | Fix |
|---|---|---|
| Hand-card rules text still broken after docs/20: on Sap the words make a staircase, running off the card and over Magma Rager beside it | The hand is a fan: each card is turned by a Rotation animation, and the live client turns each small region about its **own** centre, not the card's (the cost digits already work round this, `GLYPH_INK`). Since docs/15 the rules text is one FontString per word (so keywords can be bold), so every word was tilted where it stood on an upright card | Each word is anchored by its centre, and `RichText:SetRotation(lean)` moves that centre to where it falls on the turned card (rotated about the card's centre); the client then tilts each word in place, and together they read as one tilted text. `W.SetLean` does it on every lean change, and does the same for the card's name |

Not a bug: in a crowded hand the next card covers the right-hand end of the
card under it ("Deal 2 damage [to]" under Sinister Strike), as in
Hearthstone's own hand; hovering a card lifts it clear.

## Check in game (needs a client)

Hold six or more cards so the hand fans out: every card's text is tilted with
its card, in straight lines inside its text box, including Sap and The Coin.
