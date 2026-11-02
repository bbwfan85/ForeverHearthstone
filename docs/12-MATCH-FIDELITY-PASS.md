# 12. Match fidelity pass: boards, audio, effects, targeting, rematch, resize

Written 2026-09-23. `./run-tests.sh`: 20 compiler tests / 245 checks, 940 suites /
39,609 assertions, 0 failures. **Fully restart WoW**: new textures, sounds and
two new Lua files (`Client/Assets/ArtCrop.lua`, `Client/FX/SpellFX.lua`) are only
picked up at client start.

## What changed

| Report | Cause found | Fix |
|---|---|---|
| Pandaria board cut off | Its only source screenshot is cropped tight; the damage is baked into the composite | Out of the rotation (`NOT_PLAYED` in `tools/fetch_art.py`); Orgrimmar, Stormwind, Stranglethorn remain |
| Mana crystals "outlined" and undersized in the second game | The board changes every game, and every composited board had the source screenshot's crystals ghosted into the mana trough (the corner polygon's 10px feather reached them). Live crystals were 24×28 rects, which squashed the square crystal art and left the trough half-filled | `tools/composite_boards.py` keeps the trough interior from the clean reference (`TROUGH`); crystals are square and fill their slot |
| Grey sides on card art | 585 of the card images have flat grey, white or black padding bands; hand and collection cards showed the whole square | New `tools/art_crop.py` measures the bands into `ArtCrop.lua`; `W.ArtCoords`/`W.FitArt` crop to them and then to the window's shape, so the art covers it, unstretched |
| Targeting | A row of dots and a WoW-style reticle | Hearthstone's arrow: flowing chevrons along a curve from your hero, a barbed head, a crosshair only on a legal target; red over enemies, green over friendly targets. A targeted spell is held up beside your hero while aimed |
| Emotes played the HS voice line | The line was played as well as the WoW emote | No HS line. The character performs a voiced WoW emote: Greetings→/hello, Well Played→/congratulate, Thanks→/thank, Threaten→/roar, Sorry→/train, Oops→/spit. The menu is a wheel around your portrait |
| No mute | — | Speaker button beside the board's X, and `/fh mute`; one saved flag gates every sound and the music |
| Turn popup was the End Turn image | `turn-button.tga` stretched | A "Your Turn" medallion that swells in and fades; a smaller "Opponent's Turn"; "Victory"/"Defeat" on the same medallion |
| W/L on the portrait | Nothing was stored | Duel record per character (`ForeverHearthstoneCharDB.record`), sent in HELLO and PROFILE; your panel shows yours, the opponent's panel shows theirs. Practice doesn't count |
| Rope silent | SOUNDKIT guesses; and the burn-out cue could fire after the turn ended | A lit-fuse recording, re-lit every 4.1s while the rope burns and stopped when the turn ends; the burn-out cue is tied to the rope's epoch |
| Hero-power / ability audio wrong | HearthSFX has no hero-power recordings, so every power played its class's generic underlay; the school guesser matched "ice" inside Sacrifice and Silence | Hearthstone's hero-power activation plus a matching underlay (Armor Up→armour, Dagger Mastery→dagger, Fireblast→fire…); whole-word school matching. `tools/audio-audit.txt` lists what every spell and power plays |
| Hero destruction | The portrait snapped to alpha 0 | `Cho.HeroDeath` for any cause of death: the portrait cracks and glows, then bursts into 12 pieces of its own art with a shatter and a boom; the result banner and its sound wait for it |
| Spells had no real visuals | One arcane puff for everything | `Client/FX/SpellFX.lua`: bolt, missiles, sweep, rain, nova, heal bloom, buff glow and summon flash in eight schools, drawn as additive sprites with coloured trails. 85 spells and hero powers are mapped by hand; the rest are inferred from school and rules text |
| Rematch | No post-game controls; a second duel with the same player was silently dropped (the finished session kept the peer, and its inbox discarded the new stream's first message) | Rematch / Leave after the result. Practice replays the matchup. A duel asks the other player ("X would like a rematch", Accept/Decline) over a new `REMATCH` message; the original challenger re-challenges only after the other side confirms it has let go, and the agreed challenge is auto-accepted. Any new challenge from the same player after a game now works too |
| Resize grip jumps; icon misaligned | Windows were CENTER-anchored when sizing began; the grip sat 3px inside a 32px box; its lines rotated about their own centres | The frame is re-anchored at its own top-left before sizing; a flush 22px grip with one gilded texture. The board uses the shared grip |

## Assets

* `tools/build_match_assets.py` (generated, original): resize grip, mute icons,
  turn medallion, emote plaque, arrow segment/head, target ring, hero crack,
  eight spell-school sprites. Report: `Art/match-assets-report.json`.
* `tools/import_match_sounds.py`: `Fuse_Underlay_Play`, `UNG_Egg_Cracks`,
  `GlassShatter_Underlay_Death`, `Dagger_Underlay_Play` from HearthSFX's bucket;
  `heropower.mp3`, `bigattack.mp3` from Rymedy/hearthstone-web. Report:
  `Art/match-sounds-report.json`.
* (Update, docs/13: the rope is now announced by the active hero's own "Out of
  Time" line and a defeat by the losing hero's Death line.)
* No Hearthstone rope, defeat, or per-spell recordings exist in either source.
  The rope uses the fuse underlay; defeat uses `Pegasus_Stinger_Undead1`, a
  Hearthstone stinger already installed; spells keep their school underlay.

## Not done

* **Triggered effects are wired, but only one has a recording.** The bus now
  records each triggered ability as it resolves (`bus.fired`, kept out of the
  hashed log so lockstep is untouched). The Director gives every minion whose
  trigger fired a beat (`Cho.MinionTrigger`): it swells, glows, and plays its
  trigger recording. Of the 84 pinned minions with triggers, only Ragnaros has
  a trigger recording in HearthSFX. The generic trigger underlays the catalog
  names (`FloatingWatcher_Trigger_Underlay` etc.) return Access Denied from the
  bucket. So the others pulse silently rather than play an invented sound.
* ~~The hero's "out of time" line is still unwired.~~ Wired in docs/13. No source says which hero
  line plays with the rope, so it isn't guessed.
* Previews can't show additive blending, texture rotation, or text alpha: the
  arrow's chevrons, glows and a fading banner look flatter or earlier in
  `tools/match-*.png` than in the client.

## Live checks (needs the client)

1. Two practice games back to back: clean full crystals in the trough; the
   board changes between the three.
2. Drag Fireball: card held beside your hero, arrow from your hero, crosshair +
   red on enemies, green on your own minion with Holy Light.
3. Cast Flamestrike, Arcane Missiles, Holy Nova, Swipe; use each hero power.
4. Let the rope burn: fuse sizzle, stops the moment you end the turn.
5. Right-click your hero: the wheel; your character emotes in its own voice.
6. Speaker button: everything silent, music included; again to restore.
7. Kill a hero with a spell: crack, shatter, then Victory. Rematch (practice),
   then a duel with a second client: Rematch → Accept, and → Decline.
8. Resize each window from its corner: no jump.
