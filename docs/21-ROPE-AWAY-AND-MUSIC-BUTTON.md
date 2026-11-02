# 21. The rope when you leave the table; a music button

Written 2026-09-25. `./run-tests.sh`: 1016 suites, 0 failures. Two new
textures (`music-on`, `music-off`) -- **restart WoW** once for them.

| Report | Cause | Fix |
|---|---|---|
| Going to the main menu during a duel, the rope's audio keeps going | The rope's hiss (`rope-burn.wav`, one long file) is paused and relit by the board's `TickFX`, and that update does not run while the board is hidden, so nothing ever put it out | Hiding the board pauses the fuse (`Board:PauseRopeFuse`). While you are away a newly lit rope stays silent, and so do its "Out of Time" line and its burn-out sound; back at the table, a rope still burning is heard again |
| A button to mute only the music | The speaker mutes everything; music alone was only `/fh music` | **The music button**, in every window's corner just left of the speaker: the same gilded round, two beamed notes in cream, a red cross when off (`music-on/-off.tga`, `tools/build_music_icon.py`, drawn like the speaker's icons). One click turns the music off or on -- effects, voices and the rope keep playing -- with a tooltip saying which. It is the `/fh music` setting (saved), so every screen's button shows the same state; off hands back to the zone's music |

## Check in game (needs a client)

1. In a duel, wait for the rope, then press Main Menu: the hiss stops. Go
   back to the table while it is still burning: it is heard again.
2. Click the notes beside the speaker: the music stops, card and menu sounds
   carry on; the notes show a red cross on the board, the menu and the
   collection alike. Click again: the music comes back.
