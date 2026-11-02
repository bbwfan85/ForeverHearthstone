# Forever Hearthstone 0.2.3

Accepted duels now let both players choose a deck and press Ready before the game starts.

## Duel fixes

- Declining or blocking closes the challenger's popup and prints a decline. Queued replies keep their original destination when the local session is cleared.
- Players can rechallenge immediately after a decline. Block remains the explicit way to prevent future invitations.
- Repeating Accept keeps deck selection open. Decline and Cancel notify the opponent during deck selection; Decline cannot discard a game already in progress.
- Setup messages repeat while players choose. Lost receipt, acceptance, commitment and deck messages can recover through the ordered message stream.
- A player who stops responding before the game starts times out after 45 seconds. Healthy players may keep choosing without a fixed deck-selection deadline.
- After 20 seconds without an addon response, chat explains the target may not have Forever Hearthstone installed or enabled; it does not claim to know their installation state.
- Delayed declines from earlier invitations cannot cancel a newer duel with the same player. Invitation identity survives a reconnect.

## Card display

Spell damage text now follows current spell power in hand and inspection, including damage ranges and split missile totals. Printed collection data remains unchanged.

## Compatibility

Protocol 9: both players must update. This release changes Lua and includes the existing media. Install the attached ZIP into the client's Interface/AddOns folder, replacing the old ForeverHearthstone folder.

## Validation

All 1,269 automated suites passed, covering engine, network, UI and transport regressions. The reconnect identity assertion also passed in a focused follow-up. The release ZIP is checked against its staging files and smoke-tested using its actual packaged Lua. A live two-player WoW test has not been performed for this release.
