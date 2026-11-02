# 11. Hearthstone fidelity pass — art, voice, sound, type

Written 2026-09-23. Verified by `./run-tests.sh`: 20 compiler tests / 245
checks, 922 suites / 37,321 assertions, 0 failures. Offline previews regenerated
(`tools/board-states.png` is new and shows every portrait state at once).
**Fully restart WoW** — new textures, sounds and fonts are only discovered at
client start. The installed addon is a junction to this workspace.

## 11.1 Screen-by-screen audit

What still read as "a WoW window" rather than Hearthstone, before this pass.

| Screen | Gap found | Status |
|---|---|---|
| **Everywhere** | Every string in Friz Quadrata, WoW's font — the single biggest tell | **Fixed**: Hearthstone-style faces (§11.4) |
| **Match: minions** | Frozen = blue tint; stealth = 55 % alpha (faded the numbers too); divine shield = a generated grey shield; sleeping = literal "Zzz" text; silence, immune, enrage, can't-be-targeted invisible; no deathrattle/trigger icons | **Fixed**: Hearthstone's own overlays and icons (§11.2) |
| **Match: legendaries** | No dragon frame, in hand or on the board | **Fixed** |
| **Match: heroes** | Frozen / Immune (Ice Block) invisible on heroes; spent hero power only dimmed | **Fixed**: ice / immune overlays; the power turns over to its reverse face |
| **Match: secrets** | Drawn as tiny hero frames in a row off to the left; theirs were blank red squares | **Fixed**: class-coloured "?" gems arced over the portrait's top rim — theirs in their hero's class colour, which is public |
| **Match: damage** | Procedurally drawn starburst | **Fixed**: Hearthstone's damage starburst and healing bloom |
| **Match: lethal preview** | WoW raid-marker skull | **Fixed**: Hearthstone's skull |
| **Match: banners** | "Your Turn" / result on a flat brown box | **Improved**: the board's carved gold plaque, dark lettering |
| **Mulligan** | Thrown-back cards faded to 38 % | **Fixed**: Hearthstone's red cross over a readable card |
| **Match: audio** | Heroes silent except attack/death; no turn chime, End Turn click, hover tick; draws and unrecorded minions used generic stand-ins | **Fixed** (§11.3) |
| **Collection / packs** | Golden cards had no gold frame; pack sounds were WoW loot toasts | **Fixed**: premium frames; Hearthstone's pack, flip, rarity and golden stingers |
| **Main menu** | Synthesized hover/click tones; silent | **Fixed**: Hearthstone's menu cues; the innkeeper greets once a session; optional music |
| **Board art** | Baked "©Blizzard Entertainment" in the corner of the Orgrimmar board | **Not changed** — see §11.6 |

## 11.2 Art (tools/fetch_art.py, +33 textures)

All from HearthSim/Joust, the source of the existing frames. Each overlay shares
its base frame's source canvas (290×410 hand, 300×350 board, 280×280 hero,
250×250 power) and is resized exactly as its base was, so the client anchors it
with `SetAllPoints(skin)` — **no per-texture offsets exist to drift**.
`tools/board-states.png` was rendered specifically to check registration.

* hand: `inhand_{minion,spell}_legendary`, `inhand_minion_legendary_premium`,
  `inhand_{minion,spell,weapon}_premium` (+ generated `-glow`), `inhand_mulligan`
* board: `inplay_minion_{legendary,legendary_premium,premium,taunt_premium,
  divine_shield,frozen,stealth,silenced,immune,enraged,untargetable}`,
  `effect_sleep`, `icon_deathrattle`, `icon_trigger`
* heroes: `inplay_hero_{frozen,immune}`, `hero_power_exhausted`,
  `secret_{hunter,mage,paladin,sheathed}` (cropped to the gem)
* `damage`, `healing`, `skull`

Rules encoded in `Widgets.W.CARD_STATES`: numbers always draw above state art; a
hand card never shows board states; one icon under the portrait with
Deathrattle taking precedence over a trigger; a card back hides the dragon and
every state. The controller snapshot gained `deathrattle`, `trigger`,
`enraged`, `immune`, `elusive` per minion and `immune` per hero. A golden card
is a descriptor with `golden = true`; the match itself does not track golden
instances, so goldens appear in the collection and pack reveals.

## 11.3 Audio

**Hero voice** (tools/import_hero_voice.py → `Client/Assets/HeroVoice.lua`, 270
recordings, 47 MB). The nine classic heroes' lines from HearthSFX's *labelled*
hero entries, so "which clip is `I need more mana`" is read from the source.

| when | line |
|---|---|
| match opens | yours, then theirs (the mirror line against the same hero) |
| emote (either side) | Greetings / Well Played / Thanks / Sorry / Oops / Threaten |
| a refused move | Mana, Taunt, Summon Sickness, Minion/Hero Attacked, Need Weapon, Invalid Target, Too Many Minions, Can't Play — from `Controller:RefusalVoice`, which keeps the existing `why` strings |
| first fatigue draw | Out of Cards (once per hero per match) |
| concede | Concede |
| picking a deck | the class hero's "Picked" line — the only labelled pick line in the source (it is tagged "Picked in Arena") |

One line per hero at a time; error lines at most every 1.5 s. **Not wired**:
"Out of Time" and "Thinking" — I could not confirm from a source which hero
speaks the rope line or when, and did not guess.

**Interface sounds** (tools/import_ui_sounds.py, from Rymedy/hearthstone-web —
the source of the menu scenes and boards). `Sounds.UI_FILES` beats every
SOUNDKIT guess; user `SOUND_PACK` entries still beat both.

| key | before | now |
|---|---|---|
| menu hover / click / open | synthesized | `menuselect` / `menubtnpress` / `openmenu` |
| your turn (incl. first turn after the mulligan) | — | `playerturn` |
| End Turn click, hand-card hover | — | `endturn`, `cardhover` (throttled) |
| draw | `card.wav` | `whoosh` |
| unrecorded minion lands | Kenney wood | `cardplace`; heavy (5+) adds the wood beneath |
| pack open, rare, epic, legendary | WoW loot toasts | `openpack`, `rare`, `epic`, `legendary` (the burst is silent; the stinger lands after the beat of silence) |
| golden reveal | one toast | per rarity: `golden{common,rare,epic,legendary}` |
| each pack flip | escalating SOUNDKIT | **unchanged** escalation (your docs/06 design), with Hearthstone's `flipcard` layered under every step |
| win | — | `victory` |
| main menu | — | innkeeper greeting, once a session |

**Music is opt-in**: `/fh music` toggles Hearthstone's menu, mulligan and duel
tracks (8.3 MB). Off by default per docs/06 §6.3; turning it off calls
`StopMusic`, which hands music back to the zone.

## 11.4 Type (tools/fetch_fonts.py → `Art/Fonts/`, licences beside each file)

Hearthstone uses Belwe (names, titles, numbers) and ITC Franklin Gothic (rules
text). Both are commercial ITC faces. Open-licensed stand-ins, chosen by
rendering candidates on a real name banner:

| role (`ns.Fonts`) | face | why |
|---|---|---|
| `TITLE` | Vollkorn Black | soft, heavy wedge serifs — closest to Belwe Bold |
| `BODY` | Libre Franklin SemiBold | a revival of Franklin Gothic itself |
| `NUMBER` | Coustard Black | chunky *lining* digits. Vollkorn's are old-style and WoW cannot enable `lnum` |

The card-digit textures were rebuilt from Coustard with a heavier outline
(`tools/build_card_digits.py`). Each face is probed at load; one the client
cannot open falls back to Friz rather than leaving strings fontless (a
fontless string errors on `SetText`). **To use real Belwe/Franklin** if you
hold a licence: put the TTFs in `Art/Fonts/` and change the three paths in
`Client/UI/Widgets.lua`. Rymedy/hearthstone-web ships `BelweBdBTBold.ttf`; it was
deliberately not imported.

## 11.5 Things found on the way

* **Tests that could not see what they claimed** (mutation testing, ~30
  mutations): hand cards were only kept free of board states because Board never
  passes them live stats; the victory test re-laid out instead of re-sending
  the finished snapshot; nothing asserted the flip layer or per-rarity golden
  stingers. All now caught.
* **The preview exporter could not render a match.** The profile panel keeps a
  FontString in a field named `level`, colliding with the stub's frame level
  and making the JSON cyclic. The stub's `SetAllPoints` also discarded its
  target, so anything anchored to another region previewed at its parent's
  rect. Both fixed; the renderer now draws with the shipped fonts.
* Hover throttles held a module-level timestamp across stub clock resets; now
  reset per match and robust to a clock that moves backwards.

## 11.6 Not done, and why

* **The board watermark.** Removing the copyright notice from Blizzard's board
  art was refused by the session's safety classifier, and I agree with leaving
  it: it is a notice, not a rendering bug. A clean board source would solve it.
* **Hearthstone's "Your Turn" medallion, victory/defeat portrait break, versus
  screen, deck-list tiles, and board music/ambience per board** — no source
  found with these assets. `Rymedy/.../vs.png` exists and could seed a versus
  intro later.
* **Classic minion sounds.** HearthSFX simply does not carry most 2014 minions
  (Magma Rager, Murloc Raider, Boulderfist Ogre…): 108 of the pinned cards have
  recordings, and matching by *name* is unsafe (Sylvanas maps to a hero skin).
* **Golden cards in a match.** The engine has no golden instances.

## 11.6a Random boards and real decks (follow-up)

**Boards.** Matches now pick one of Hearthstone's four launch boards —
Orgrimmar, Stormwind, Stranglethorn, Pandaria — from the match seed, so both
duel clients sit at the same table (`tools/board-rotation.png`).

Only gameplay screenshots of these boards exist, so `tools/composite_boards.py`
(run by `fetch_art.py`) builds each one:

* **The table** — rim, alcoves, rails, trough, plaque, slots — is shared by
  every classic board, and comes from the clean reference the layout is
  measured against. That is why alignment is unchanged.
* **The corners and margins** come from each board's screenshot, warped onto
  the reference by a **homography** fitted to ~50 feature matches (the
  in-game camera keystones the table; plain x/y scaling left ~15px of error).
  Every board registers to ≤ 2.5px; the build fails if one exceeds 4px.
  Anything the screenshot printed over the table (hands, hero powers, mana,
  history icons, decks, clock) is masked out and taken from the reference.
* The reference's own corners turned out to be **uncoloured concept sketch** —
  the grey spiked scenery in earlier screenshots. Orgrimmar now has its real,
  painted corners too, and the sketched board is no longer played on.

Known imperfection: a small patch under your hand's left edge (bottom-left,
just right of the corner scenery) is inpainted, because every screenshot has
hand cards there. Your own hand covers it most of the time.

**Decks.** The reference had a gold and a silver deck painted into its slots,
and the addon drew a card-back portrait with a number over them. Now:

* the painted decks are removed and the recesses rebuilt (stone rim profile
  sampled from the real rim, banner behind the overhang interpolated);
* each deck is a live **stack** — the top card's back plus gilded page edges
  (`deck-pages.tga`) whose thickness follows the count, empty at zero;
* **no number**, as in Hearthstone: hover a deck for "26 cards in your deck".

Also fixed on the way: the preview stub treated `SetColorTexture`'s colour as a
vertex tint that survived a later `SetTexture`, which is why every board
preview until now rendered nearly black. WoW does not do that; the stub no
longer does either.

## 11.7 Live verification (needs a client)

1. **Full restart**, `/fh`: innkeeper greets once; menu hover/click are
   Hearthstone's; text is in the new faces. Text in Friz Quadrata means that
   face failed to load on this client and fell back, safely, by design.
2. Practice: both heroes speak at the mulligan; marked cards show the red X;
   "Your Turn" plaque + chime after the mulligan.
3. Click a sleeping minion ("needs a turn to get ready"), a card you cannot
   afford ("need more mana"), attack past a taunt; emote from the portrait menu.
4. Watch for frozen/silenced/stealthed minions, a legendary, secrets on both
   portraits, a spent hero power flipping, the damage starburst and skull.
5. Open a pack with a rare+; open the collection's golden filter.
6. `/fh music` on, start a match, confirm the mulligan → duel track, `/fh music`
   off → zone music returns.
7. Start several practice matches: the board should change between the four,
   and heroes, powers, End Turn, mana and both decks should sit in their
   sockets on every one. Hover each deck for its count; draw into fatigue to
   see an empty slot.
