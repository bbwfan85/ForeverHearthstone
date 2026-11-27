# Forever Hearthstone 1.3.0

Find other players: a Social menu with your guild's ladder and the players
near you.

## Social

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
  players can see you. `/fh nearby on | quiet | off` does the same, and
  `/fh nearby` on its own reports how detection is working.

### How nearby players are found

- The addon joins a chat channel of its own for the zone you are in
  (`FHN` and a number) and announces itself there about once a minute. Each
  player's addon keeps only those close by. The channel is joined for the
  session only and is taken off your chat windows, so it should print nothing.
- You are not announced while your challenges are set to friends or nobody,
  in a dungeon, in combat, in a duel, or with "Visible to nearby players" off.
- A `~` before a distance means that player is not confirmed to be on your
  layer of the zone. If you cannot see them, that is why. Duel is not held
  back on it, so a challenge can reach someone at your spot on another layer.

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

**Both players should update to 1.3.0.** Older versions (1.0.3 and later) can
still connect, but the card fixes above change how a few cards resolve, and a
duel between 1.3.0 and an older version can fall out of step if one of those
cards is played. Older versions do not appear under Players Nearby or on the
Guild Ladder.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.3.0.zip, then restart WoW completely. Your rank,
collection and decks carry over unchanged.

## Validation

All 1,423 automated suites pass, 25 of them new for Social. Detection through
the zone channel was confirmed working on a Forever client. Social is new: if
players near you are not showing up, please report what `/fh nearby` prints.
