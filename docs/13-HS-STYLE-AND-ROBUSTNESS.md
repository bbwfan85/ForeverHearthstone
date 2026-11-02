# 13. Hearthstone style pass, match feel, card economy, duel robustness

Written 2026-09-24. `./run-tests.sh`: 976 suites, 0 failures. **Fully restart
WoW**: there are new textures, sounds and two new Lua files (`Client/Vault.lua`,
`Client/Assets/CardPlaySounds.lua`), and the client only picks these up at start.

Target platform: **WoW Forever** (Mainline 12.x API, docs/07). Retail is the
test bed. Every new API call is existence-checked or `pcall`-guarded.
`UnitPosition`, `UnitClassification`, `UnitAffectingCombat` and
`UnitIsDeadOrGhost` appear in forever-addon-kit's captured API.
`GetUnboundedStringWidth`, `SetMaxLines`, `SetDesaturated` and `ENCOUNTER_END`
are not listed there (the kit lists globals, not widget methods or events), so
each has a fallback.

## Art style

| Report | Cause | Fix |
|---|---|---|
| "Goldshire Footman" cut off with "…"; card text over attack/health; deck names spill | Every shrink-to-fit loop measured after `SetWidth`/`SetHeight`, when WoW reports the *clipped* size, so none of them ever shrank anything | `Widgets.FitText` measures unbounded first, then applies the box. `Widgets.AutoFit` keeps a label fitted when its text, font or box changes (all menu buttons, deck boxes, footers, name tags, End Turn, banners). Rules text is confined to the plate above the badges (0.665–0.845 of the card height). `tests/test_textfit.lua` checks every collectible card and every visible board label at three window sizes |
| Unplayable cards transparent | A deliberate 62% dim and a red cost | Full opacity, normal cost colour; only the green border marks a playable card, as in Hearthstone |
| End Turn fake, overflowing | A generic plaque stretched over the table's painted one | `tools/build_hs_ui.py` cuts Hearthstone's own plaque out of the table art, removes the painted "Waiting…" and makes yellow, **green** (nothing left to play) and grey (ENEMY TURN) versions. The live button sits exactly on the painted socket, with white capitals fitted to the face |
| Turn banners | Title-case text overran the medallion; there was an "Opponent's Turn" banner | "YOUR TURN" fitted to the lozenge. Nothing is announced on the opponent's turn (Hearthstone doesn't; the plaque says ENEMY TURN) |
| Victory text off-centre, not Hearthstone | The turn medallion was reused | Your portrait appears large at centre with a red VICTORY ribbon, or cracked and drained on a dark DEFEAT ribbon. The table dims behind it |
| Rematch / Main Menu buttons | An amber pill beside a small grey plaque in a tray | Two matching tavern buttons (the main menu's own style) under the ribbon |
| Hover text and backgrounds | Flat dark slabs, raw `$4` | Parchment keyword panels (9-slice). Hovering a minion, weapon or hero power shows the card itself plus one reminder box per keyword |
| Profiles too large | 240×74 red leather panels | Compact name tags: round portrait medallion, name, level and W/L |
| Bare / smeared board corners | Baked into the composited TGAs where the source screenshots ran out | `tools/repair_board_corners.py` replaces the smeared patches (under your hand's left edge, the left margin, the bottom-left corner) with their mirror image from the clean right side of the table. It swaps only low-detail pixels, so the scenery is untouched. `composite_boards.py` runs it after every rebuild |
| Pandaria | Cropped source | **Removed entirely** |
| Mulligan confirm, board X, mute | Flat fill, bare letter | Amber Play button; gilded round buttons |

The wiki sites that host Hearthstone reference screenshots are not reachable
from the build environment. Every generated element (tooltip, ribbon, name
tag, round button, dust) is original art in the existing manner. The End Turn
plaque is Hearthstone's own.

## Match feel

* **Mulligan deal**: cards are dealt one by one from the deck, face down,
  turning up halfway, each with the draw whoosh. Replacements after the
  mulligan are dealt the same way. Ordinary draws play the sound too.
* **Board click puff**: a click on empty sand raises a dust puff. The effect is
  pooled and capped for spam-clicking, and never appears on the corner scenery.
  The window now moves only when dragged by its margins.
* **Hand full / burned cards**: an overdrawn card comes off the deck face up
  for both players, hangs about a second, then catches fire (Hearthstone's fire
  underlay, ember particles), and the hero says "my hand is too full". The
  engine raises `CARD_BURNED` for the cases that used to vanish silently:
  returned to a full hand, Discover into a full hand, and `AddToHand`.
* **Closing a bot game** opens the `/fh` main menu. Resume Match brings the
  game back.
* **Opponent hover**: you see the card your opponent holds up and their
  targeting arrow. This uses a *volatile* message (sequence 0, never resent,
  never part of lockstep), sent at most 4 times a second and only on change.
* **Long chains**: opponent actions are presented one after another, never
  piled on top of each other. Presentations longer than 2.6 s, or a queue
  building up, play faster (up to 2.5×) rather than longer. On the network, a
  Knife Juggler under a Fan of Knives is still one action message: lockstep
  sends inputs, not outcomes.

## Audio: the rope and defeat (from docs/12)

There is still no recording of Hearthstone's rope sizzle or defeat music in
either source (the HearthSFX bucket's 15,099 names, Rymedy/hearthstone-web).
What changed:

* **Rope**: the active hero's own labelled **"Out of Time"** line (all nine
  were already installed, just unwired) announces the rope. The fuse stays
  underneath.
* **Defeat**: the losing hero speaks their **Death** line (newly imported)
  under the shatter. The Hearthstone stinger follows.
* **Thinking**: after 25 idle seconds of the opponent's turn, their hero
  mutters one Thinking line, once a turn.
* Nine classic minions HearthSFX lacks (Boulderfist Ogre, Bloodfen Raptor,
  Archmage, Gnomish Inventor, Razorfen Hunter, Deathwing, Alexstrasza, Leeroy
  with his music, Elite Tauren Chieftain) now play their own lines, from
  Rymedy/hearthstone-web (`tools/import_card_place_sounds.py`).

## Card economy

**What drops, and from where.**

* **Mob kills** drop Hearthstone packs (Classic + GvG in one pack) or,
  one time in five, a single card from the same pool.
* **Bosses** drop single **Naxxramas cards**, not packs; Naxx was an adventure,
  not a pack.
* **Critters** give nothing. They are refused by creature type and by the
  client's `minus`/`trivial` classification, which works in any language, and
  below 60 by the XP gate (critters give no XP).

**Bugs fixed.**

* The boss path could never fire: `select(5, …)` ran over two arguments, and
  the success test was inverted. Bosses now use `ENCOUNTER_END` with
  success = 1, deduplicated.
* `PARTY_KILL` classifies its victim's GUID instead of whatever you had
  targeted.
* One kill can no longer roll twice (both kill events).
* A kill that levels you up counts.
* Skull (level −1) bosses pay at 60.

**Guaranteed packs.** 3 for a new character, then milestones at 10:1, 20:1,
30:2, 40:2, 50:2 and 60:5 (16 in all). Each pays once, keyed to level.
Characters that are already past a milestone get it at next login.

**Naxxramas.** The first kill of each dungeon boss, and every raid boss, is a
guaranteed card. A boss card is rolled on boss odds (50/30/12/8), and a card
you already have the maximum of is re-rolled once.

**Rates, tuned by simulation** (`tests/test_economy.lua`, run on the real
code): normal 1.5%, elite 4%, dungeon boss 12%. The profile is a character
levelling 1–60 and then farming pre-raid BiS: about 12k normal kills, 4k elites
and 300 dungeon bosses (about 45 of them first kills). Extras are
disenchanted, and the dust crafts the cheapest missing cards. Median result:

| | owned at 60 + pre-BiS |
|---|---|
| pack pool (161 neutrals) | ~93% |
| its 35 legendaries | ~69% (the rest craftable over time) |
| Naxxramas (21 neutrals) | ~95% |

docs/04's "1% completes neutrals near 60" was about 4× too optimistic. It
ignored single-card drops and duplicates; completing the pool from packs takes
about 426 packs, roughly 53k kills at the old rate.

## Duel edge cases

| Question | Answer |
|---|---|
| Walk away / die / get pulled into combat | **Pause, then forfeit.** Moving 30+ yards from where you sat, dying or entering combat pauses the duel for both players: nobody can act, the rope stands still, and a parchment notice says why. You have 60 s to come back (180 s if dead). If you don't, your client forfeits; if it can't (a crash), the other client claims the win after 15 s more |
| Disconnect / lag | After 10 s of silence: a connection-problem pause, and the silent player is offered a rejoin. After 120 s the waiting player wins **only if it is the silent player's turn**, so a clean network split can never give both players a win. On your own turn you can keep playing; with no word at all the duel is abandoned with no winner at 300 s |
| `/reload` mid-duel | `PLAYER_LOGOUT` fires for a reload too, so it now **pauses** ("left") instead of forfeiting. The other client offers the duel back, and the returning client rebuilds it from seats, seed, decks and the action log. The rebuilt game is checked against the other client's fingerprint before play resumes. It is automatic if this is the duel on record (the record is written to disk on reload); otherwise `/fh resume`. A real logout never comes back, and the 90 s grace settles it |
| Cheating | Not impossible, but harder than a text editor. The seed commitment now covers the **deck** as well as the nonce (62-bit fingerprint), so a deck can't be stacked after the shuffle is known. The opponent's deck is validated on your client (class, copy limits, obtainable). The collection is **sealed** (`Client/Vault.lua`): scrambled and signed at logout, with character vaults keyed to the character. A hand-edited file is ignored, or caught and restored from the last good copy |
| Turn order | Randomised: `seed % 2` from the commit-reveal seed, which neither player chose. The Coin goes to the second player |
| Opponent hover | Shown: their held card and their arrow (see above) |
| Sync / disagreements | Both clients simulate every action (lockstep). Now a fingerprint follows **every action**. On a disagreement **the challenger is authoritative**: the other client rebuilds from the seed, the decks and the challenger's action log, and carries on. Only a disagreement the log can't explain ends the duel, named as a desync |
| Long turns, slow machines | Hearthstone's 75 s turn and 15 s rope. Your own animations don't burn your turn, up to 20 s a turn. The turn still ends only after the current resolution finishes. A connected opponent far past the rope (turn + 45 s) can be beaten with **/fh claim** |

## Not done

* **Curved minion names** (Hearthstone arches them). The names now fit whole
  on the straight banner. Arching needs per-glyph `FontString:SetRotation`,
  which isn't confirmed on Forever.
* **The board's 2:1 art is still squashed into a 16:9 window.** Cropping the
  margins would mean remapping every layout fraction. It was left alone to
  keep the sockets registered.
* No source has Hearthstone's board-click sound, so the puff is silent.

## Live checks (needs the client; full restart)

1. A practice game: the mulligan is dealt card by card, each with a whoosh. End
   Turn is Hearthstone's plaque: yellow, green when you've nothing left, grey
   with ENEMY TURN.
2. Hover a minion: its card plus keyword boxes. Hover a deck: a parchment
   count.
3. Spam-click the sand: puffs, not on the corner scenery. Drag the window by
   its margin.
4. Draw to 10 cards, then draw again: the card burns and your hero complains.
5. Win and lose: portrait and ribbon, centred. Rematch and Main Menu match. X
   during a bot game opens the menu.
6. Collection, My Decks, long deck names, Goldshire Footman: nothing cut off.
7. A duel with a second client:
   * walk 50 yards away and come back;
   * die;
   * pull a mob;
   * `/reload` mid-turn: the duel returns in the same state;
   * let the rope run out on a slow chain.
8. A new character: 3 packs at first login. `/fh drops` lists the rates and
   milestones.
9. Log out, open `WTF/.../ForeverHearthstone.lua` in a text editor, change a
   number in the vault, log in: you're told, and the last good copy is used.
