# 19. Pack opening, music mute, card fixes, doc tidy

Written 2026-09-25. `./run-tests.sh`: 999 suites, 0 failures. Two new
textures (`fx-aura`, `fx-rays`) -- **restart WoW** once for them; everything
else is Lua and data.

## Pack opening

| Report | Cause | Fix |
|---|---|---|
| A face-down card flashes a couple of times without being hovered | The crack (`Choreography.PackCrack`) pulsed the best card's glow three times as the pack landed -- the "legendary tell" | Gone. As in Hearthstone, a face-down card lights up in its rarity's colour **only while the pointer is over it**, and plays its rarity's sound the first time (`rarity_tell_*`, once per card; the ordinary hover tick after that). Nothing glows on its own |
| The rarity background looks like a placeholder | The light was the card widget's own glow: the card FRONT's outline texture, stretched into a hard gold block, even round a face-down back | Each pack card has its own light on a layer between the room and the cards (`CollectionUI:PackLight`): **`fx-aura`**, a soft glow in the card's shape spilling past every edge, and **`fx-rays`**, a sunburst. Both are white and tinted: rare blue, epic purple, legendary orange, common a faint white |
| The reveal | Rare, epic and legendary flared with the same block | Turning over, a rare card's light **flares and fades**; epic and legendary also throw **rays** that swell, turn slowly and fade (bigger for a legendary). Their sparks are four-point glints that drift up and linger (`SpellFX.MOTION.burst_*`). Afterwards nothing keeps a light **except a golden card**, which keeps a soft gold one |
| (found on the way) Flipping the next card cut the last one's reveal short | Revealing re-lays out the pack, and every relayout cancelled every running animation -- so a quick second click froze the first card's light half-lit and cut its fanfare | The relayout a flip makes keeps the running reveals (`keepFX`); a resize still cancels them, as everything moves |

`tools/build_pack_fx.py` generates the two textures.

## Muting the music

| Report | Cause | Fix |
|---|---|---|
| Muting stops the music and unmuting restarts it | WoW cannot pause music; mute called `StopMusic`, unmute `PlayMusic`, which starts the track from the top | The track keeps playing; the mute turns WoW's **Music** volume to 0 and unmuting puts it back (`Sounds.SilenceMusic`), so it carries on where it was |

That is WoW's own setting, so it is never left at 0 by the addon: the level it
had is saved while silenced, restored the moment the addon's music hands back
to the zone's (closing every window), on logout, and on the next login if the
client crashed while muted. Moving the volume slider while muted sets the
level to return to.

Found on the way: the menu-hover throttle compared against the last hover's
time and never recovered if the clock went backwards (only the test stub's
does); it now guards as the card-hover throttle already did.

## Cards

| Card | Was | Now |
|---|---|---|
| Demonfire, Demonheart | Buffed an **enemy** Demon (the condition tested the race only) | New condition `TargetIsFriendly`: your Demon grows, theirs takes the damage |
| Floating Watcher | Grew when your hero was hit on the **opponent's** turn too | `MyTurn` (which exists now) -- on your turn only |
| Nozdormu | Marked PARTIAL ("nothing counts down") | Already consumed by the turn clock and rope since the director; the stale flag is removed |

## Docs

- The spell effects pass was numbered 16 alongside the art check; it is now
  **docs/18-SPELL-EFFECTS-PASS.md**.
- **docs/08-HANDOFF.md** brought up to date where it had gone stale: the
  world-interruption handling and continuous range check are built; the emote
  wheel is built; the 95-card worklist and `tools/batches/REMAINING.txt` are
  marked historical (every card is authored); the PARTIAL list points at the
  CSVs; and the "whisper advert" is corrected to **not built** (it said built).

## Check in game (needs a client)

1. Open a pack: after the crack nothing glows. Hover each face-down card: a
   soft light in its rarity's colour; a rare-or-better plays its sound once.
2. Flip a legendary or an epic: rays behind it, glints drifting up, then the
   light fades. Flip the next card quickly: the first one's light still fades
   out rather than freezing.
3. A golden card keeps a soft gold light once turned.
4. At the main menu, mute and unmute: the theme carries on from where it was.
   Close `/fh` while muted: the zone music is at its normal volume.
