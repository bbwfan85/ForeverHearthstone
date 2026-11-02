# 30. 0.1.1: the first release for players

Written 2026-09-26 for 0.1.1. `./run-tests.sh`: 1132 suites, 0 failures.

**Lua only: `/reload` is enough.** No new media. **Protocol version 5: both duellists must update.**

## What was asked

> Perform a full review of the addon so it's ready for release: how it looks, the animations,
> the sounds, the rules, the implications. This should be 0.1.1 and be expected to be used by
> players. We want them to duel people close to them and work fairly seamlessly.

In the same session, from a retail test: the minimap button works, and the W/L record on the
main menu was not centred.

This builds on the beta.3 review (docs/29), which read the whole engine, client, network code,
saved data and packager. This pass concentrated on what that review left open, on what changes
when real players meet each other on mixed versions, and on the player-facing text.

## The main menu's record card

`Duels: 7 W - 3 L` and `Practice: 12 W - 5 L` were one centred string. The two lines are
different lengths, so each was centred on its own, and the figures did not line up under each
other. The card now has two rows on one axis. Each label ends just left of the card's centre
line, and each `W - L` starts just right of it (`hub.recordRows`, `Main.lua`).
`W.HSPanel:SetContent` takes an `extra` height for rows the caller lays out itself.

## Rules: Stealth is lost by dealing damage

| Was | Now |
|---|---|
| Only attacking broke Stealth. A Concealed Ragnaros fired at the end of your turn and stayed hidden through the opponent's turn. A stealthed Knife Juggler threw knives and stayed hidden. | A minion that deals damage in any way loses Stealth (`Game.BreakStealth`, called from `Game:DealDamage`). A hit into Divine Shield still counts. A hit into Immune, or one cancelled outright, does not. |

## Implications: mixed versions

Duels are lockstep: both clients run the engine. Any rules change therefore means a beta.3
client and a 0.1.1 client would play different games and desync mid-match. `Protocol.VERSION` is
now 5, so the HELLO handshake refuses a version-4 client with advice naming who needs to update
(`Protocol.CheckVersion`). The version player-facing text reports is read from the `.toc`.

Proximity (docs/29, `Main:NearEnough`) is unchanged, and still applies on every path into a duel.

## Sounds

`tools/audio_audit.lua` reports no missing hero-power underlays. For wider coverage, the whole
test suite was run once with `PlaySoundFile`/`PlayMusic` logging every path. 74 distinct files
were played, and all exist in the addon folder, ignoring case as WoW does. The only misses were
the two fixture names a test plays on purpose. The release zip carries all 626 audio files.

## Looks

The preview renders (`tools/collection_preview.lua`, `tools/review_sheet.py`) were checked for
the menu, collection, decks, pack room and match scenes. Nothing else was out of place.
`tools/hearth-menu.*` and `tools/hearth-compact.*` are refreshed to show the new record card.

## Player README (`tools/package_release.py`)

* The "THIS IS A BETA" section is gone. Problems go to the GitHub issues page.
* A **Duelling another player** section: stand together, `/fh duel` or the right-click menu,
  both players on the same version, and who may challenge you.
* The Addon Compartment is mentioned. `/fh help` replaces "`/fh` everything else", since a bare
  `/fh` opens the menu.

## Left as they are

* Freeze: a character frozen on its own turn after it has already attacked stays frozen through
  its next turn. Hearthstone may thaw it. This is rare, and the exact rule was not certain
  enough to change (also listed in docs/29).
* The other "left as they are" items in docs/29 stand.

## Check in game

1. The main menu's record: the W - L figures line up and the block sits in the middle of the card.
2. A 0.1.1 player challenging a beta.3 player: both are told who needs to update.
3. Conceal, then Ragnaros's end-of-turn shot: the opponent can target Ragnaros on their turn.
