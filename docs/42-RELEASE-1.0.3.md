# Forever Hearthstone 1.0.3

## Fixes

- **The challenger now loads into the duel.** Forever's UnitName gives a
  character's first and last name where other clients give the realm, so a
  challenge went to "First-Last". That reached the other player, but their
  replies came back from their real address, and the challenger threw them
  away as coming from a stranger. The other player could accept and pick a
  deck while the challenger waited, never got the deck picker, and finally
  saw "no response from the Forever Hearthstone addon".

  While waiting on a challenge, the challenger now recognises the answer from
  the player it challenged: an accept by the character ID it carries,
  anything else by first name. From then on it talks to the address they
  answered from.

## Installation

Both players need 1.0.3. Replace the old ForeverHearthstone addon folder with
the folder from ForeverHearthstone-1.0.3.zip, then restart WoW completely.
Saved collections carry over unchanged.

## Validation

All 1,290 automated suites pass, including a new test where the answer comes
from a different address than the challenge went to, and one where a HELLO
carrying another player's ID is ignored. Network protocol unchanged (10).
