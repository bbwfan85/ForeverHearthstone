# Forever Hearthstone 0.2.4

## Duels

- Choose a saved deck in the same deck book used for bot games, with the opponent's name and class visible. Removed the extra synthetic Basic deck option.
- Closing a live duel offers Ask to End Duel. Both players must agree; an agreed end records no win, loss or forfeit. Concede remains a separate action.
- Declining an end request starts a two-minute cooldown. The request button shows the remaining time and stays disabled until it expires. Both clients enforce the cooldown.

## Practice opponents

- Planning randomness now comes from visible state rather than the real match seed.
- Pending card choices use the same hidden-information filtering as normal planning.
- Verified that decisions across all five difficulties do not change when hidden opposing hands, decks, secrets or match RNG are changed.
- Verified real 30-card deck contents, varied seeded shuffles and normal draws from the top of the shuffled deck. Deck archetypes remain selected by class and difficulty; their card lists are curated, not randomly assembled.

## Interface and rewards

- Raised the board, collection and menu above normal addon frames while preserving dialog and tooltip ordering.
- Enlarged the rope ember and centered the unopened pack vertically on its tray.
- Expanded reward help with ordinary and guaranteed-slot rarity odds, golden odds, kill reward rates and a level 1-60 timeline listing guaranteed packs and named class cards.

## Compatibility and validation

Protocol 10: both duel players must update. Replace the old ForeverHearthstone folder in Interface/AddOns with the folder from the attached ZIP.

All 1,274 automated suites passed (60,853 assertions), plus 20 compiler tests (247 checks). The release build checked 1,030 texture references. All 3,970 ZIP entries match the staged files and the packaged Lua smoke test passed. Live WoW visuals and a live two-player session have not been verified.
