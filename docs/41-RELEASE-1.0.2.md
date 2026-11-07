# Forever Hearthstone 1.0.2

## Fixes

- **Duels work with Forever's first-and-last names.** The addon checked that
  you were standing next to the right player by comparing names, and on
  Forever the name a challenge arrives under need not match the name the game
  shows for the character beside you. So a challenge from the portrait or a
  chat name said "duels are only between players standing together", and
  accepting a challenge did nothing. Now:
  - Right-clicking a portrait challenges the player it was opened on.
  - Accepting finds the challenger by the character ID sent with the
    challenge, not by name. Challenging someone who is already challenging
    you is recognised the same way.
  - Accepting still needs the challenger to be someone your client can see:
    your target, mouseover, group or a nameplate. If it does nothing, target
    them and press Accept again.

## Deck building

- While editing a deck, a card greys out once it has no copy left to add:
  every copy you own is in the deck, or it is at the limit (two, one for a
  legendary). A full deck greys nothing, as in Hearthstone.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.0.2.zip, then restart WoW completely. Saved collections
carry over unchanged.

## Validation

All 1,289 automated suites pass, including new tests for a challenger whose
name differs from the one the game shows, the portrait menu, and greyed-out
cards. Network protocol unchanged (10), so 1.0.1 and 1.0.2 can still duel,
but both players need 1.0.2 for the name fix to work on both sides.
