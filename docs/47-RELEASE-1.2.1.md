# Forever Hearthstone 1.2.1

Your ladder rank is yours to keep.

## Bot ladder

- **No more monthly season reset.** 1.2.0 would have moved everyone 4 ranks
  below their best on the 1st of each month, as classic Hearthstone did. Now a
  rank you earn stays earned, and the rank floors at 20, 15, 10 and 5 and
  Legend are permanent once reached. Nobody has been reset yet: the first reset
  would have happened on December 1.
- The win-loss on the Ranked screen, after a ranked game and in `/fh ladder`
  is now your whole ladder record ("Record 6-4"), not a season's.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.2.1.zip, then restart WoW. Your rank, collection and
decks carry over unchanged.

## Validation

All 1,377 automated suites pass, including a new one that checks a record
saved by 1.2.0, Legend included, keeps its rank. Network protocol is
unchanged (10), so 1.0.3 through 1.2.1 players can duel each other.
