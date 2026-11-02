# Presentation pass — 2026-09-21

## Screenshot follow-up — 2026-09-22

### Card sound identity and placement fallback

Magma Rager has no matching recording in the catalog. The mechanical sound
was the shared armor underlay used as the summon fallback. Unmapped minions
now use five wooden impact variations in each of two weights, from Kenney's
CC0 Impact Sounds (https://kenney.nl/assets/impact-sounds). License, source
archive member and SHA-256 hashes are included under Art/Sounds/Placement.
These are deliberately generic table-placement effects, not Hearthstone
recordings. They replace the armor fallback.

The importer retains alternative recordings separately from simultaneous
layers and drops events whose primary recording is unavailable, preventing an
orphan secondary layer from impersonating a complete card event. Playback
cycles available variants without consuming gameplay randomness. Original
base heroes only have one cataloged attack line: that line now plays at most
once per three swings and never within twelve seconds. Attack impact sounds
still play on every swing; unrelated dialogue is not used for variation.

Exact original sounds for every unit are still unavailable. Known matching
card recordings remain preferred, otherwise minion summons use the wooden
fallback. Validation adds Magma Rager, repetition and variant-selection cases.

### Death reflow, rope deadlines, and recorded audio layers

Surviving board minions retain their entity-to-position mapping across pool
reuse, including identical cards. Removing the middle minion now moves the
right-hand survivor directly from its own position to its new slot.

Turn expiry is retained while presentation is locked and applied once after
the action finishes. Both players can see the active turn's rope, while only
the active player's client sends the timeout action. Waiting for the other
player's mulligan does not start a turn clock. The rope has a braided texture
and ember instead of flat colored rectangles.

The sound importer now retains all available layers in each card event,
including the secondary effect/stinger. 274 recordings are installed. Shared
Hearthstone underlays replace synthesized attack/summon and spell fallback
cues. These shared substitutes are not verified as the exact generic impact
or spell mix used by the original client; exact coverage is still incomplete.
Original event mappings remain preferred. Asset sources/hashes stay in the
media report; no inaccessible recordings were imported.

Validation: 873 suites / 35,517 assertions pass, including middle-minion death
reflow, timeout during presentation, opponent countdown authority and layered
sound playback. Restart WoW for new media. Live visual/audio verification is
still needed.

### Animation, controls, and audio follow-up

- All board intents and drag starts are blocked while an action resolves. A
  second card cannot act on the old mana/hand snapshot; repeated target drops
  are consumed once per gesture. Attack recoil returns without overshooting.
- Card animation scales around its own center rather than the screen origin.
  Enemy spells travel downward toward the board. Surviving hand cards retain
  their entity identity when pooled widgets are reassigned and tween to their
  new positions without hover updates cancelling unrelated movement.
- Hero health has an unconstrained centered label, avoiding ellipsis. Native
  sword, armor shield, weapon attack/durability and taunt textures replace the
  temporary badges. Hero power buttons align with measured board sockets.
  Lethal skull previews render on a separate layer above both combatants.
- Unit placement shows an oval preview with neighbors making room, restoring
  their original positions on cancellation or animation handoff. The turn
  control uses the board's carved plaque with a rebuilt blank gold face.
- Imported 252 locally installed Hearthstone recordings for 87 pinned cards.
  Summon, attack and death events select the matching recording. Distinct
  original fire, frost, holy, shadow, nature, arcane, weapon and arrow effects
  cover unavailable spell recordings. Match effects take priority over WoW menu
  clicks; all playback respects the SFX channel. The installer includes audio.

Sources: UI textures from [HearthSim/Joust](https://github.com/HearthSim/Joust/tree/main/assets/images),
card recording names from [HearthSFX](https://hearthsfx.github.io/), with public
clips served by its `hearthstonesounds.s3.amazonaws.com` source. Exact source
URLs, hashes and unavailable recordings are retained in
`ForeverHearthstone/Art/presentation-media-report.json`. 63 requested clips
were inaccessible and were not imported; many classic spells have no catalog
recording. This is not complete original Hearthstone audio coverage.

Validation: 870 suites / 35,501 assertions, all passing. New cases cover blocked
rapid plays, AI spell direction, centered scaling, hand identity reflow,
lethal preview layering, duplicate drops, oval placement and audio selection.
All mapped WAV files were opened and checked for nonempty audio. The plaque
was rendered for inspection. Live WoW appearance/playback remains to be checked;
restart the client so newly added textures and sound files are discoverable.

### Combat and history follow-up

- Damage/healing hitsplats and displayed health now update on attack impact,
  projectile arrival, or the spell/summon impact beat. Event sequence tracking
  prevents the final snapshot from displaying the hits a second time. Hero
  powers now hold their snapshot through the projectile flight too.
- Hero health is centered on the blood-drop socket for every digit count;
  armor uses a silver shield immediately above it. Ready glows are saturated
  green. Enemy mana is a readout only.
- Finished games reject board intents, hand drags and play animations, disable
  hand mouse interaction, and clear ready glows.
- History begins at the top of the rail (including Coin), appends downward,
  and rolls when full. Damage/healing entries preserve each affected card's
  health and armor at the time of the event; hover lists those outcomes and
  updates direct-target preview health. Secret actions remain anonymous.
- Minion plays dissolve into an oval portrait before landing, use a small
  settling scale change, and emit dust at the destination. Neighbors move
  toward their resulting slots on the correct player's row. This is a custom
  approximation of a summon transition, not a frame-for-frame recreation.

Validation: impact-before-recovery, no replay, immutable damage history, hero
badge anchors, post-game input, Coin ordering and portrait handoff are covered
by regression tests. Restart WoW for the new `hero-armor.tga` texture.

### Replacement numeric renderer

The next live screenshot still showed drift with small numeric regions, so the
earlier anchor-only correction below was insufficient. Digits now render on
full-card texture regions with exactly the skin's dimensions and center. UVs
position the ink inside that canvas; eleven isolated transparent-edged glyph
textures avoid sampling neighboring digits. There is no separate anchor
rotation or vertex deformation. Live values, multi-digit spacing, colors,
visibility and pooled widget reuse still use the existing number interface.
Mana centers and weapon durability were also calibrated against the source art.

Validation: 858 suites, 34,421 assertions, zero failures. Coverage reconstructs
ink centers from UVs for spells/weapons/minions, five tilt angles, three window
sizes, and one/two/three-digit values. `tools/badge_preview.lua` exports real
widget geometry; `tools/badge_preview.py` independently rasterizes it and checks
transparent glyph margins. The preview covers the four reported cards at three
angles. This is an offline rendering check; live WoW confirmation remains needed.
Restart WoW to load `card-digit-0.tga` through `card-digit-10.tga`.

### Earlier changes

- Removed the second rotation of numeric badge anchors; digits now share only
  the parent card transform and remain at their painted gem coordinates.
- Added white silhouette glow textures with a soft halo, keeping the native
  frame shape. Ready minions use the hand's green color, opacity, and pulse.
- Removed the exhausted "Spent" label and cropped played portraits inward to
  exclude the baked edge strips in the source images.
- Added an opaque, dark-bordered starburst behind damage/healing numbers.
- Kept the rotated enemy fan left of the top mana socket and measured that
  socket independently from the bottom one.
- Replaced fixed history text boxes with eight portrait/action icons inside
  the painted left rail, newest at the bottom. Hover shows the action, source
  card and explicit target card. Hidden enemy Secrets remain anonymous;
  turn bookkeeping does not fill the action rail. This records direct action
  targets, not every indirect target of triggered or area effects.
- Verified the existing hero-origin projectile path for both players, even
  while another card is flying, and captured Hunter's implicit hero target.

Validation: 858 suites, 22,946 assertions, zero failures. Layout reviewed over
the installed board artwork. Live client rotation and glow appearance still
need visual confirmation. Restart WoW to load the newly generated textures;
the installed addon is already junction-linked to this workspace.

Rebuild the added textures with `python tools/build_presentation_assets.py`.

Implemented after resuming the interrupted work:

- Fixed malformed Lua font paths and enemy-mana initialization during resize.
- Kept reused mouse frames visible during relayout; ignored hover callbacks
  during pool release, and canceled stale hand tweens on hover.
- Wider hand, stable card sizes, centered card titles, enemy hand clearance,
  enemy mana and hero-power costs, and live hand mana costs.
- Whole-card dragging, green playable borders and blue valid-drop feedback.
  Spells accept the play area without minion insertion markers.
- In-play minion portrait frames with stats, summoning-sickness/exhaustion
  labels, power/weapon/minion descriptions, and combat death previews.
- Turn/result banners, hero defeat particles, damage/heal numbers from public
  engine events, recent action history, spell trails and hero-power effects.
- Opponent Secrets remain face down during play and unnamed in history.
- New-match cleanup and delayed callbacks guarded against replacing matches.
- `/fh` opens a hub with bot class selection, collection, new deck, and pack
  entry points. `/fh practice` still starts practice directly.
- Collection right-click inspection uses the shared card widget with crafting
  controls. Class filters now include each class.
- Eight small original WAV cues are bundled as fallback audio when SOUNDKIT
  names cannot resolve. Rebuild them with `python tools/build_sounds.py`.
  These are synthesized cues, not original Hearthstone recordings.

The preceding interrupted work also added the missing Coin, Boom Bot,
Shadowform power, Jaraxxus power, and Mega-Windfury scripts and token coverage.

Validation: Lua 5.1/LuaJIT headless UI/engine tests, compiler tests, and effect
coverage. The strict stub does not validate the live client's rendering,
mouse capture, sound playback, or visual similarity to Hearthstone. Generic
particle trails, status labels, and the initial hub are not a frame-for-frame
recreation of Hearthstone's effects or menus.

Live verification still needed:

1. Restart WoW to load the added audio files, open `/fh`, choose a bot class.
2. Drag the Coin, Fan of Knives and Vanish, then attack and use a hero power;
   confirm the hand/stats remain visible without resizing.
3. Sweep through ten cards, resize at several aspect ratios, and check the
   portrait stats, title positions, cost digits, and blue/green borders.
4. Verify enemy turn text, both mana displays, power/weapon hover, history,
   damage/healing numbers and hero defeat presentation.
5. Right-click collection cards, craft/disenchant, resize inspection, and open
   a banked pack. Check `/fh sound` and the SFX volume setting.
6. Check a real duel for opponent play animations and hidden Secrets.

## Card geometry and targeted spell follow-up

Corrected played-minion badge anchors to the painted sockets in the native
256x256 frame, fitted portrait art to its oval opening, and scaled taunt/shield
layers to the portrait. Hand names now have one centered banner anchor.
Playable outlines use enlarged native frame silhouettes instead of a rounded
rectangle mask, including hero powers.

Targeted spells transition to aiming from a faded source card in hand when
dragged onto the field. Untargeted cards continue to follow the pointer without
an aiming arrow. The reticle is a larger X; release and cancellation restore
opacity. Targeted spell choreography emits a projectile without the duplicate
untargeted board burst. Battlecry minions retain their placement gesture.

Regression coverage checks actual digit quad centers at three window sizes,
aiming versus whole-card dragging, release opacity, and exclusive spell effects.
These are stub-based checks; in-game visual fidelity still needs verification.

## Play, draw, and drag lifecycle follow-up

- Enlarged played-minion artwork 25% within unchanged board slots to compensate
  for transparent padding in the native frame.
- Replaced deformed full-card digit quads with ordinary glyph regions sharing
  the card frame's transform; hand attack/health now use live snapshot stats.
- Playable outlines use additive blending with a gentle brightness pulse.
- Widened the aiming trail and X. Presentation start and completed/cancelled
  drops hide the arrow immediately. Right-click cancellation consumes the
  eventual left-button release and its click rather than replaying the card.
- Hide the source card while its flying representation is active and finish
  flight before publishing the resulting board snapshot.
- Block practice AI stepping during mulligan, including delayed end-turn work.
- Record draw event identity for local cards, keeping opponent identities out
  of snapshots. Draws move existing widgets from deck to hand; refreshes preserve
  progress and do not replay events.

Validation: 854 suites, 21,859 assertions, zero failures. New coverage includes
mulligan interaction while going second (one mana on the first turn), cancelled
left release, one visible played-card representation, live hand stats, and
uninterrupted draws across repeated snapshots. Live WoW rendering still needs
visual confirmation, especially glyph rotation and highlight appearance.
