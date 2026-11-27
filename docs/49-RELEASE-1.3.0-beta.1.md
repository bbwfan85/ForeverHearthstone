# Forever Hearthstone 1.3.0-beta.1

A test build. The Social features below have passed the automated tests but
have not been tried between two real players yet, which is what this build is
for. If you are not testing, stay on 1.2.1.

## Social: players nearby and your guild's ladder

- **Social menu.** A new plaque in the bottom-left corner of the main menu, or
  `/fh social`.
  - **Guild Ladder**: the class, name and rank of every guildmate who plays,
    best first. Members who are offline stay on the board at the rank they last
    reported.
  - **Players Nearby**: anyone close to you who has the addon, with their rank
    and how far away they are. **Duel** challenges a player beside you, with no
    need to target them. **Knock** invites a player further off to come over.
- **A pop-up when someone is near.** When a player with the addon comes within
  about 80 yards, a small panel names them (up to three, then "and N more")
  with a button each. It goes away by itself, like a pack drop, and waits while
  you are in combat or in a match.
- **Two switches**, on Social and in Settings: the pop-up, and whether nearby
  players can see you. `/fh nearby on | quiet | off` does the same.
- You are only announced to players in earshot, and not at all while your
  challenges are set to friends or nobody, in a dungeon, in combat or in a duel.

### What testers should check

1. Type `/fh nearby` about 30 seconds after logging in, outdoors. It should
   say the broadcast is "working". If it says "not carried" or "refused", the
   addon has switched to finding players you mouse over or target instead:
   please report which you saw.
2. Stand near each other. Each of you should get the pop-up and see the other
   under Social > Players Nearby.
3. Press Duel from the pop-up or the list while standing together, and Knock
   from further away.
4. If you share a guild, check you both appear on the Guild Ladder.
5. `/fh nearby test` shows the pop-up and both lists with made-up players, to
   check how they look. Nothing is sent.

## Card fixes

- A copy of a minion (Faceless Manipulator, Echoing Ooze) now keeps effects the
  original was given: an Ancestral Spirit or Soul of the Forest deathrattle,
  Power Overwhelming's death at end of turn, Blessing of Wisdom's card draw.
- Mind Vision now copies a card as it is in the opponent's hand, including a
  cost reduction. A copy taken from the board is still the printed card.
- A silenced minion no longer counts as having a Deathrattle, so Scarlet
  Purifier spares a silenced Loot Hoarder and Lil' Exorcist does not count it.
- A minion that is silenced, returned to hand or copied no longer carries stale
  state from before.

## Duelling other versions

**Both players should be on 1.3.0-beta.1.** The network protocol number is
unchanged (10), so older versions still connect, but the card fixes above
change how a few cards resolve. A duel between this build and 1.2.1 can fall
out of step if one of those cards is played.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.3.0-beta.1.zip, then restart WoW completely. Your rank,
collection and decks carry over unchanged.

## Validation

All 1,418 automated suites pass, 20 of them new for Social.
