# Forever Hearthstone 1.2.0

The bot ladder, deck codes, and opening packs in bulk.

## Play Bot Ladder

- **Play Bots is now Play Bot Ladder**, with Hearthstone's Ranked and Casual
  switch on the Play screen.
- **Ranked** climbs the classic ladder, from rank 25 (Angry Chicken) to rank 1
  (Innkeeper) and then Legend. It follows the original rules:
  - Stars per rank: 3, then 4, then 5.
  - A bonus star for three wins in a row, below rank 5.
  - No stars lost at ranks 25-21.
  - Milestone floors at 20, 15, 10 and 5.
  - A monthly season that resets you 4 ranks below your best.
- **Better opponents the higher you climb.** Each rank plays a little better
  than the one below it:
  - Low ranks make beginner mistakes, such as a poor trade, a card left in
    hand or a missed lethal.
  - Master and Legend play their best every time.
- **Real-feeling decks.** There are 135 decklists, at least three per class at
  every tier.
  - Lower-rank opponents bring their own copy of a list: missing a few epics
    and legendaries and filling the gaps with what they own, sometimes with a
    random legendary thrown in.
  - Top players tech in an Ooze, an Owl or a Loatheb.
- **Opponents have names** that fit their class and rank, from Pyrokid42 near
  the bottom to Vael at Legend.
- **A classic rank screen after every ranked game.** Your medal fills or loses
  its stars one at a time. A rank-up flashes the new medal in, and Play Again
  queues your next opponent.
- **Your rank shows on your nameplate** in every match, next to your level and
  record, including in duels with other players on 1.2.0.
- **Casual** is the old practice mode: pick any opponent and a difficulty.
- `/fh ladder` shows your rank, stars and season record.

## Deck codes

- **Copy Deck Code** in the deck editor gives Hearthstone's own deck code,
  ready for Ctrl+C. It pastes into Hearthstone (Wild), deck sites, or a
  friend's Import Deck.
- **Import Deck** in My Decks reads any Hearthstone deck code, including codes
  for these cards copied from today's client. It then shows:
  - Every card you are missing, with its art, rarity and dust cost.
  - A Craft button on each card, plus **Craft All** when you can afford the
    lot.
  - A warning for cards from sets after Goblins vs Gnomes, which are left out.

## Packs

- **Open up to 40 packs at once**, as Hearthstone allows. Each pack plays its
  own reveal, one after another, with the best card turning last. **Skip to
  All Cards** jumps to a summary of everything you opened, best first, with
  NEW and duplicate tags and the dust they made.

## Fixes

- The "+N Dust" stamp on a duplicate is drawn over the card, not behind it.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.2.0.zip, then restart WoW completely (there is new art).
Collections, decks and records carry over unchanged. Your ladder rank starts
at 25.

## Validation

All 1,377 automated suites pass. They include the ladder rules, 135 decklists
checked card by card, deck codes checked against python-hearthstone's own
encoder, and bulk opening played through to the summary. The packaged build
passes its load smoke test.

Network protocol is unchanged (10), so 1.0.3 through 1.2.0 players can duel
each other. A 1.1.0 player simply shows no rank medal.
