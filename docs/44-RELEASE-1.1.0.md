# Forever Hearthstone 1.1.0

Duel on boats and zeppelins.

## Duels

- **Riding a boat or zeppelin together is not leaving the table.** The duel
  used to pause, then forfeit, because the ship carried both players away from
  where they sat down. Now:
  - While your opponent is beside you, you are at the table wherever it is.
  - Standing still while the deck moves under you carries the table with you,
    even when nobody is targeted.
  - After the loading screen of a sea crossing, the addon waits up to 15
    seconds for the other player to appear again. If it still cannot see them,
    the notice tells you to target them; doing so resumes the duel at once.
- Taking a **flight path** now counts as leaving the table. A hearthstone,
  teleport or portal still does, as before.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.1.0.zip, then restart WoW completely. Saved collections
and decks carry over unchanged.

## Validation

All 1,343 automated suites pass, including new ones for a boat voyage with and
without the opponent targeted, a sea crossing, a teleport and a flight path.
Network protocol unchanged (10): 1.0.3, 1.0.4 and 1.1.0 players can duel each
other. Not yet verified on a live boat: the carrying relies on the game
reporting your own speed as 0 while standing on a moving ship; if it does not,
having your opponent targeted (or their nameplate showing) still keeps the
duel going.
