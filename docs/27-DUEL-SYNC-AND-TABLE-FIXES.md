# 27. Duels that stay in step, a challenge you can see, Concede, and a round of table fixes

Written 2026-09-25. `luajit tests/run.lua`: 1081 suites, 0 failures.

**Lua only: `/reload` is enough.** No new media. **Both duellists must update:** the
protocol is now version 3, and a version-2 client is told plainly that one of them is
out of date.

## What was asked

Fourteen reports from playing duels and practice games. Thirteen are fixed below; one
("can't go back after opening a deck to inspect") needs a detail before it can be.

## Duels

### Both players challenged each other, and the game started out of step

Each client read the other's challenge as an *answer* to its own, so both went on as the
challenger: both player 1, each putting its own nonce first. That is two different seeds,
two different games, and both players seeing their own turn.

HELLO now says which it is (field 10: `c` challenge, `a` answer). When challenges cross,
both clients settle it the same way without a round trip (`Session.KeepsChallenge`: the
lower character GUID keeps the challenge) and the other side answers it as if it had
pressed Accept. Challenging the person who is already challenging you simply accepts
them (`Main:Challenge`).

### Attacks arrived late

WoW gives each addon prefix a burst of about ten messages, refilled at about one a second.
Past that `SendAddonMessage` refuses the line, and the transport ignored the answer, so the
line was just gone until the next message (often the five-second ping) exposed the hole.
Meanwhile every action cost three messages (the action, then an `ACTION_HASH` from each
client) and hovering sent up to four more a second.

* **An action is one message.** Its fingerprint rides in its last field
  (`h<index>x<hash>`), and only the receiver compares. The per-turn `HASH` is gone as well,
  because the per-action one already covers it. Either side can start a resync now: the
  challenger sends its log unasked, the other side asks for it.
* **A refused line is kept.** `Transport.Outcome` reads the result. A throttled line stays
  at the head of the queue and is tried again after `THROTTLE_BACKOFF`.
* **Hover never crowds out the game.** Volatile lines (the opponent's hover) are coalesced
  to the newest one of each kind. They go out only while an estimate of WoW's allowance
  has `VOLATILE_RESERVE` to spare.

The allowance figures (10, then 1 a second) are an estimate. Only the volatile lines rely
on them. Game lines rely on the answer WoW actually gives.

### A challenge you can see

A challenge pops up at the top of the screen: who is asking, with **Accept** and
**Decline** (`Main:ShowDuelPrompt`). Your own challenge shows "Waiting for X..." with
**Cancel**. Cancelling tells the other player the challenge was withdrawn, not declined.
The slash commands still work.

### Challenging someone in your party

A party or raid member's frame opens the `PARTY` / `RAID_PLAYER` menu, not `PLAYER`, so
the Challenge entry was missing. It is now on every friendly-player menu (`Main.CHALLENGE_MENUS`),
never on yourself, and a player from another realm is addressed as Name-Realm.

### The opponent's portrait flickered

Their character's face can only be drawn from a unit token. Every time your target changed,
they stopped being one and the portrait fell back to their class hero. Once drawn, the face
now stays (`Board:SetProfiles`). Nameplates and mouseover are searched too, so it is found
sooner.

### Mulligan crosses vanished while waiting

Confirming the mulligan cleared the marks, so the cards you threw back showed uncrossed
until your opponent chose. The marks now stay until the mulligan is over (`Controller`).

## The table

* **Concede.** A Concede plaque sits beside Main Menu while a game is being played, in a
  duel or against a bot. It asks first, then gives the match up (`Main:ConfirmConcede`).
* **A battlecry minion is no longer played twice.** If you aimed its battlecry, the minion
  already stood on the board as a ghost. The play animation now starts from the ghost
  instead of flying out of the hand again (`Board:BeginPlayAnimation`).
* **Minions left off centre** (Gnomish Inventor and others). The shove that makes room
  recomputed its row on every beat from the live minion count. If the animation outlasted
  the presentation lock, that count already included the new minion, so the row was pushed
  apart for a minion that wasn't there. The row is now fixed when the play starts, and a
  shove after the board has been laid out again does nothing (`stage:Board`,
  `Board.layoutEpoch`).
* **Cards jiggled while resizing.** Mainline snaps each texture to the pixel grid on its own.
  A card's pieces sit at fractional positions, and hand cards are rotated, so each piece
  rounded differently from frame to frame. Snapping is off for every card texture
  (`W.NoPixelSnap`).
* **Keywords on right-click.** An inspected card shows Hearthstone's reminder boxes (Taunt,
  Battlecry, Overload...) down its left side, on the board and in the collection
  (`W.InspectKeywords`). Ice Lance's "Frozen" calls up Freeze.

## Menus

* **Win/loss on the main menu.** A small parchment card in the top-left corner shows this
  character's duel record and a new practice record (`ForeverHearthstoneCharDB.practiceRecord`).
  Practice results are counted once each, including wins on your own turn, which were
  never announced before.
* **Difficulty is chosen with the opponent.** The slider is only on the opponent page. On
  the deck page the stage just says "Against: Adept Druid bot".
* **Unlocked cards came up grey.** Pack cards share a widget pool with the collection
  pages, where unowned cards are greyed, and the grey carried over. Pack cards are always
  in full colour now. A copy beyond the deck limit says so under the card: "Extra copy -
  disenchant for N dust". It is kept, not scrapped.

## Tests

New suites cover each fix: `net:` (crossed challenges, one message per action,
challenger-started resync, withdrawal), `transport:` (throttle retry, hover coalescing,
party menus, the pop-up, answering a crossing challenge, Concede in a duel, mulligan
crosses), `ui:` (keywords, shove, battlecry ghost, pixel snap), `table:` (Concede against a
bot, practice record) and `collection ui:` (grey pack cards, extra copy, record, slider).
The stub gained `GetRegions`, `GetChildren`, `GetObjectType`, `SetSnapToPixelGrid` and
`SetTexelSnappingBias`, all real Mainline methods.

## Open

* "Can't go back after opening a deck to inspect": I couldn't find a screen that opens a
  deck without a way back (My Decks has Done and the corner's My Decks / Main Menu; the
  practice deck page has Back). This needs the exact screen.
* The throttle numbers and the new menu tags (`MENU_UNIT_PARTY` and the rest) are
  Mainline names that retail can confirm but Forever has not. A missing tag is skipped
  (pcall), not an error.
