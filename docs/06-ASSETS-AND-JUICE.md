# 6. Assets, Audio and Juice

Status: **asset resolution and choreography built and verified** (176 suites,
773 assertions, 15 mutations caught). **No frames written yet.**

> Superseded in part by [07-PLATFORM-CORRECTION.md](07-PLATFORM-CORRECTION.md):
> Forever is a **Mainline** client, not Classic. The asset architecture and the
> guaranteed floor stand unchanged; the texture-pipeline specifics in §6.3 need
> rechecking, and "the part I cannot test" was too pessimistic — the UI layer is
> statically verifiable against the published API documentation.

---

## 6.1 The thing that changes the section 7 plan

Your plan was: default tier ships zero art and uses `Interface\Icons` paths
already on every player's disk. That is the right instinct and it survives. But
sizing it against the pinned pool surfaces a problem:

```
  collectible cards          535
  token minions (on board)   130
  hero portraits               9
  hero powers                  9
  ----------------------------------
  distinct art slots         683
```

**683 icon paths, and not one of them can be verified from here.** Worse, it
cannot be verified *in game* either:

* There is no reliable "does this texture exist" API in Classic.
  `Texture:SetTexture(badPath)` does not error and does not return false — it
  silently draws nothing.
* So a wrong path is invisible to the addon and shows the player an empty box.

Hand-authoring 683 paths from memory is exactly the recall failure the printed-
data architecture exists to prevent. I will not do it, and neither should a
generated guess.

### The inversion

**Art is an enhancement, never a dependency.** Every card resolves to a
descriptor that renders complete and readable from *printed data alone* — name,
cost, attack, health, rules text, class colour, rarity gem. The icon and the 3-D
model layer on top when they happen to work.

A card with no valid art looks plain. It never looks broken, and it is never
unplayable. `tests/test_assets.lua` asserts this across the entire pool with an
empty manifest: 683 entries, zero unrenderable.

The only icon path anywhere in the code is `INV_Misc_QuestionMark`, WoW's own
canonical missing-icon texture, used as the last tier.

---

## 6.2 The resolution chain

`Client/Assets/Resolver.lua` — pure logic, no WoW API, tested headless.

| tier | source | who fills it |
|---|---|---|
| `override` | the user's local asset pack | the player |
| `manifest` | shipped default manifest | whoever can see the game |
| `generic` | per type / class / `DEFAULT` | a handful of slots, not 683 |
| `fallback` | `INV_Misc_QuestionMark` | built in |

Generic lookup goes most-specific-first: `SPELL_MAGE` → `SPELL` → `MAGE` →
`DEFAULT`. That means **a dozen generic entries make the whole game look
deliberate** rather than needing 683 before it looks like anything.

`Resolver:Coverage(ids)` reports the split, which is the number that tells a
player whether an asset pack is worth installing:

```
  override 12  manifest 340  generic 180  fallback 151   -> 65.8% real art
```

The manifest ships **empty**. That is not a placeholder — it is the honest state
until someone with a client fills it, and the game is fully playable meanwhile.

### 3-D models

`Model` frames showing real creature models need a `displayID`, which is game
data I also cannot verify. Same discipline: per-card, optional, absent means the
icon shows instead. `useModels = false` suppresses them wholesale for players on
weak machines, and the card stays complete.

124 of 339 minions carry a race (Beast/Demon/Dragon/Murloc/Pirate/Totem/Mech),
which is the obvious first tranche for model mapping — but nothing depends on it.

---

## 6.3 Your pipeline questions, answered

> ⚠ **This section was written against a Classic-client assumption that turned
> out to be wrong.** Forever runs Mainline (interface 16001), which has a modern
> texture and atlas system (`C_Texture`, `SetAtlas`). The zero-art default tier
> gets *easier* — Mainline ships far more composable atlas elements than Classic —
> and `Resolver.lua`'s guaranteed floor is unchanged. The specifics below need
> rechecking against the Mainline texture APIs. See
> [07-PLATFORM-CORRECTION.md](07-PLATFORM-CORRECTION.md).

### BLP / DXT and power-of-two

For the **default tier none of this applies**, because the default tier ships no
texture files at all. It composes: WoW's own `Interface\` textures, solid-colour
textures with vertex colouring, and font strings. That is why the default tier is
**~0 MB of art** (see 6.5).

For a **user's optional asset pack**, the constraints as I understand them:

* WoW reads `.blp` (BLP2). DXT1 for opaque art, DXT3/DXT5 where an alpha channel
  matters, uncompressed for small UI chrome where banding would show.
* **Power-of-two dimensions.** Non-PoT textures have historically had unreliable
  behaviour and filtering artefacts; 256×256 or 512×512 per card art is the safe
  shape. Stay at or below 1024×1024 per file.
* A card's art region is not square, so the usual approach is a PoT texture with
  the art inset and `SetTexCoord` cropping to the visible region.

⚠ **Flagged as unverified:** whether Forever accepts `.tga` alongside `.blp` in
addon folders, and whether it enforces PoT more strictly than earlier clients.
Both are one-line changes in the pack loader, and both need someone with the beta
to check. The pack format is versioned so a change does not invalidate packs.

### Atlas strategy

**Do not atlas the card art.** One file per card is the right call here:

* a pack is assembled incrementally by a human, and an atlas forces a rebuild of
  the whole sheet to add one card
* WoW streams textures on demand; 600 small files cost less than one 8192px sheet
  that is resident whenever any card is visible
* `SetTexCoord` bookkeeping across 683 slots is a bug farm

**Do atlas the particles.** Sprite sheets are the only way to do particles
without shaders (there are none in the WoW UI), and a particle sheet is authored
once: a 512×512 sheet at 8×8 gives 64 frames, which is ample for the burst,
shatter, dust and sparkle effects the choreographies call for.

### Audio and ogg

* `PlaySoundFile(path, channel)` plays an addon-shipped file; `.ogg` is the
  practical format. Channel matters — `"SFX"` for hits and reveals, `"Music"` for
  anything sustained, so the player's own volume sliders still work.
* We ship **no audio**, for the same reasons as art. The manifest maps logical
  keys (`pack_crack`, `card_reveal`, `rarity_legendary`) to either a file in a
  user pack or a WoW `SoundKit` ID. **Absent means silent, and silence is a valid
  render** — exactly the icon discipline.

### The escalating-audio problem

Your Peggle-style escalation depends on **pitch shifting, which WoW cannot do.**
There is no pitch parameter on any sound API.

So it is faked: the manifest holds an **ordered list** per logical key, and the
reveal index selects the entry. Five ascending notes across five card reveals
gives the rising-tension effect without pitch control. `Choreography.CardReveal`
passes the escalation step through and a test asserts it rises `1,2,3,4,5`.

With an empty manifest there is no escalation and no sound — the pack still opens
correctly, just quietly.

### PlayMusic, StopMusic, and ducking WoW's own music

* `PlayMusic(path)` replaces the current music; `StopMusic()` returns control to
  the game, which resumes its own zone music on its next cue.
* **There is no ducking API.** You cannot attenuate WoW's music and play over it.

The options are therefore: replace the music for the duration of a duel and
`StopMusic()` afterwards, or leave it alone. I would **leave it alone by
default.** Two reasons: a duel happens in the world, where the zone music is part
of the place you chose to sit down in, and replacing it makes the addon feel like
it is taking over the client.

⚠ There is a third option I want to flag and *not* take: adjusting the player's
`Sound_MusicVolume` CVar to fake ducking. That writes to the player's settings,
and a disconnect or crash mid-duel leaves their audio permanently changed. If you
want ducking, it should be opt-in with a restore-on-load safety net, and I would
rather ask than assume.

---

## 6.4 Choreography: why not just AnimationGroups

`AnimationGroup`s are good at what they do — a fade, translate or scale runs on
the C side with no per-frame Lua. We keep them for that.

What they are bad at is **orchestration**: "lift the card, arc it to slot 3 while
the board shoves apart, land it 40ms before the impact flash, start the glow on
the third frame of the flash." Expressed as nested `OnFinished` callbacks that
becomes unmaintainable within a dozen effects.

So the split is:

* **`Client/FX/Timeline.lua`** — *when* things happen. Pure logic, no WoW API,
  deterministic, driven by an injected delta rather than `GetTime()`.
* **`Client/FX/Choreography.lua`** — the actual sequences, written against a
  `stage` interface.
* **`Client/UI/`** (not yet written) — *what* they do to a frame. Thin; starts and
  stops AnimationGroups and sets values.

**This is why the juice is verifiable before the beta lands.** The choreographies
run against a mock stage that records every call, so ordering, overlap, timing and
escalation are all asserted on a machine with no WoW installed. What cannot be
tested is whether it *looks* good — only that the right things happen in the right
order at the right times.

Every stage method is optional. A choreography run against an empty table is a
no-op, not an error — so a half-built UI cannot crash the game. Tested.

### Timing rules, encoded as tests

| rule | why | test |
|---|---|---|
| nothing important under ~120ms | below that the eye sees a jump, not a motion | timing constants |
| everything overlaps | sequential beats read as a slideshow | `With(lead)` overlap test |
| impact leads its sound | makes the hit feel causal | `impact` before `impact_sound` |
| the board parts *before* the minion lands | sells pushing neighbours aside | `board_shove` before `land` |
| battlecry fires *after* landing | cause must read before effect | `land` before `battlecry` |
| `backOut` overshoot on every landing | gives a card weight | overshoot > 1.02 asserted |

---

## 6.5 The three moments you asked about

### Playing a card

`lift → arc → board shove → land (overshoot) → impact → glow → battlecry`.
The arc's horizontal eases out while the vertical overshoots; a straight lerp
here is the single most common reason card games feel cheap. Heavy minions shake
harder and use a different summon sound.

### Getting a pack on a mob kill

This one has a constraint the others do not: **it fires in the open world, while
the player is fighting.** So it is deliberately restrained, and the tests enforce
that:

* **no screen shake, no vignette** — asserted at zero
* under 2.6s total, self-dismissing, no click required
* exactly one soft sound, not a fanfare
* a corner toast that never covers action bars or nameplates

The pack is **banked silently**. Opening it is a separate deliberate act, which
is what makes the opening a moment rather than an interruption.

A rested-area bonus gets an extra *beat inside the same toast* rather than a
second UI element, so the player learns the association. A set-trigger card drop
(kill yetis → Yeti card) is louder and lingers longer because it is rarer — but
still no shake.

### Opening a pack

`squash → crack (burst + shake) → five cards fan out staggered → the tell →
flip each → rarity payoff`.

Two details carry it:

**The stagger must be perceptible.** Five cards arriving together read as one
blur. 55ms apart reads as five objects. Asserted at >150ms spread end to end.

**The legendary tell.** In Hearthstone, when a pack holds something good, a
face-down card glows *before you flip it*. That anticipation is most of the
pleasure — the reveal itself is over in 300ms. So the tell is its own beat, it
**pulses rather than fades** (a pulse draws the eye; a fade does not), and a
common-only pack gets no tell at all, because otherwise the tell means nothing.
Both directions are tested.

Rarity payoff escalates strictly: common has no burst, rare shakes 2, epic 4,
legendary 8 plus a vignette nothing else uses, plus a beat of silence before the
fanfare. Golden cards shimmer regardless of rarity, because they are the
drop-only chase.

---

## 6.6 What is NOT built, and what I cannot verify

**Not written yet:** any frame. No `CreateFrame`, no XML, no drag-and-drop, no
collection browser, deck builder, crafting screen, spectator view, emote wheel or
match history. Those are the next milestone.

**Cannot be verified by me, at all:**

* that any `Interface\Icons` path exists
* any creature `displayID`
* any `SoundKit` ID
* whether `.tga` works alongside `.blp`, and how strict PoT enforcement is
* ~~whether `DoEmote` is callable from addon code~~ — **ANSWERED**: `DoEmote` is
  deprecated on Mainline; the call is `C_ChatInfo.PerformEmote`. See
  [07-PLATFORM-CORRECTION.md](07-PLATFORM-CORRECTION.md).
* every WoW API signature in the UI layer — **now statically verifiable** against
  `Blizzard_APIDocumentationGenerated`; see docs/07 §7.4

All of it is isolated: art and audio behind the manifest with a guaranteed floor,
emotes behind a compat layer with an in-UI fallback, and the frame layer confined
to `Client/UI/` so the 4,500 lines of tested logic underneath do not depend on it.

**Default tier total: ~0 MB of art and audio.** The shipped package is Lua, the
generated card data, and a particle sprite sheet if we author one. Well under 1 MB
and clean to distribute — which was the requirement.
