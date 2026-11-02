# 8. Handoff — State of the Project and What Is Left

Written 2026-09-19. Everything below was verified by running it, not recalled.

Verify the same way before trusting any number here:

```bash
./run-tests.sh
```

Expected: `20 tests, 245 checks, 0 failure(s)` (compiler) and roughly
`738 suites, 10899 assertions, 0 failure(s)` (engine + client).

---

## 8.1 What this project is

A WoW addon recreating **Hearthstone's Basic + Classic + Naxxramas + Goblins vs
Gnomes** card game, played between two players sitting near each other in the
world. Target client is **World of Warcraft: Forever** (Blizzard's Classic+,
beta live, launches 2026-11-04).

It is a **faithful recreation, not an homage**. Card stats, costs and rules match
a pinned patch exactly. There is an exhaustive list of permitted deviations in
the original brief (class-locked decks, cards collected through WoW play, golden
cards drop-only, proximity/sitting duel gate, world interruption, no
Arena/Brawl/ladder/store/gold, retuned dust economy). **Anything not on that list
must match Hearthstone.** Where a deviation collides with a recreated rule, ask
rather than resolve.

### Two rules that are load-bearing

**1. Card data is never recalled — it is imported.**
`ForeverHearthstone/Data/PrintedCards.lua` is GENERATED from a vendored
HearthstoneJSON snapshot and carries its source sha256. Effect scripts contain
behaviour only, never a stat. A wrong stat can therefore only come from a wrong
pin, never from a typo. `tests/test_pin.lua` asserts the pin's identity using
cards whose stats changed between builds, so an accidental re-pin fails loudly.

**2. No WoW API outside `Client/`.**
`Engine/`, `Client/Assets/` and `Client/FX/` import zero WoW APIs and run under
plain Lua 5.1. This was adopted for testability and later saved the project: the
brief's claim that Forever uses the Classic API turned out to be **wrong** (it is
Mainline/Midnight — see docs/07), and because the engine could not reach the
platform, that mistake cost nothing. **Do not relax this rule.**

---

## 8.2 Pinned patch

**Build 7234** — Basic + Classic + Naxxramas + GvG, carrying the GvG-era balance
patch (Starving Buzzard 5 mana 3/2, Leeroy 5, Gadgetzan Auctioneer 6, Soulfire 1,
Flare 2, Adrenaline Rush removed).

531 collectible cards: 133 Basic + 245 Classic + 30 Naxx + 123 GvG, plus 4
promo/reward. Exactly 34 class cards per class, symmetric across all nine.

Data is vendored at `tools/vendor/cards.{4944,5834,7234}.enUS.json` with
`SHA256SUMS`. **The 2014 builds are served by HearthstoneJSON but UNLISTED in its
index**, so they could vanish; the importer only ever reads the local snapshot.

---

## 8.3 Platform: Mainline, not Classic

Forever runs **Mainline** UI architecture: `WOW_PROJECT_MAINLINE`, interface
16001, API set ~12.1.5 (Midnight), 269 `C_*` namespaces. **Port from Retail code,
not Classic.** Midnight's Addon Disarmament is active.

Consequences already accounted for:

| | |
|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | **errors on registration**. Use the new standalone `UNIT_DIED` / `PLAYER_TARGET_DIED` / `PARTY_KILL` events — better than the original plan, since they give kill credit directly |
| boss kills | `ENCOUNTER_STATE_CHANGED` |
| emotes | `DoEmote` is deprecated → `C_ChatInfo.PerformEmote` |
| context menu | `Menu.ModifyMenu` (11.0+), not `UnitPopupButtons` |
| addon messages | `C_ChatInfo.SendAddonMessage` — no documented changes, but confirm on the beta |
| removed Classic globals | `GetItemInfo`, `GetSpellInfo`, `UnitAura`, `GetTalentInfo`, `GetMerchantItemInfo` — never use these |
| Secret Values / disarmament | **does not affect us** — we never read combat state |
| secure snippets | broken in Forever (`loadstring_untainted` missing) — we need none |
| Lua | still 5.1. No `goto`, no `//`, no bitwise operators |

**The user has retail WoW** and will run `APIProbe/` there as a proxy. Retail is
Mainline too, so it verifies the API surface — but it is **not** Forever, and
every result must be re-confirmed on Forever before the client layer depends on
it. The probe stamps the client it ran on for exactly this reason.

---

## 8.4 What is built and verified

### Engine — complete (3,127 lines)

`Engine/{Enums,Entity,Selector,Conditions,Ops,Aura,Bus,Targeting,Game}.lua`

* **Five-layer attribute model**: `base + ench + aura + timed`, minus `damage`.
  Aura and timed layers are **rebuilt from zero** on every recalculation, which
  makes orphaned-buff bugs structurally impossible.
* **Event bus** with Hearthstone's real ordering: triggers collected in *play
  order* across both players, queued FIFO, not interleaved; deaths simultaneous
  per block with the death phase looping until stable.
* **Secrets resolve INLINE**, not queued — so Explosive Trap can kill an attacker
  before it connects and Ice Block's Immune applies before a later hit in the
  same action. No secret fires on its owner's own turn (`anyTurn` exists but no card uses it since docs/29).
* **All five duration families**: timed entity buffs, timed mana, player cost
  modifiers, damage clamps, scheduled actions — sharing one timing rule
  (`Game:TimedExpired`).
* **Determinism**: `Game:Random` is the only randomness; a test poisons
  `math.random` to prove it. Commit-reveal seed derivation is in place. Selector
  candidate ordering is fixed before any RNG touches it.
* Combat, weapons, overload, fatigue, mulligan, The Coin, taunt, windfury,
  divine shield, spell power, Velen doubling, targeting derived from printed
  `playRequirements`.

### Client — built (7207 lines)

* `Client/Assets/Resolver.lua` — asset resolution with a **guaranteed floor**.
  683 art slots are needed and no icon path can be verified (there is no
  "does this texture exist" API, and `SetTexture` fails silently). So art is an
  *enhancement*: every card renders complete and legible from printed data alone.
  A test asserts this across the whole pool with an empty manifest.
* `Client/FX/Timeline.lua` + `Choreography.lua` — the juice as **testable data**.
  Choreography runs against a `stage` interface, so ordering, overlap and audio
  escalation are verified headless. Ten sequences: play minion/spell, attack,
  pack-drop toast, set-card drop, pack crack, card reveal, craft, disenchant,
  rope.
* `Client/UI/Layout.lua` — resolution-independent layout **solver**. Pure
  arithmetic, 1,459 assertions sweeping 13 window sizes × 16 game states.
* `Client/UI/Board.lua` — the frame binding. Resizable/movable window with a drag
  grip, pooled widgets, drag-and-drop producing intents. It exports
  `ns.CardWidget`, so the collection screen draws cards with the board's own
  code and a card looks identical in both places.
* `Client/Actions.lua` — **an action is the unit of play**, applied through one
  function by the local player, the wire, the AI and any future replay (§8.12).
* `Client/Net/{Protocol,Session,Transport}.lua` — the duel (§8.12).
* `Client/{Collection,Packs,Drops,Rewards}.lua` — the collection, the economy,
  what a kill is worth, and the events that pay it (§8.13).
* `Client/UI/{CollectionLayout,Collection}.lua` — the out-of-match app: browsing,
  deck building, crafting and pack opening on one screen (§8.14).
* `Client/FX/Director.lua` — which animation plays and when, plus the turn clock
  the rope burns on (§8.15).
* `Client/Assets/GenericArt.lua` — 20 candidate icons covering all 683 slots,
  and the audit that lets a human verify them (§8.15).

### Tooling and tests

* `tools/import_cards.py` — generates printed data from the vendored snapshot.
* `tools/compile_effects.py` — CSV → Lua effect compiler. **Its module docstring
  is the complete, current DSL spec — read it before authoring anything.**
  Validates unknown ids/ops/selectors/conditions, rejects duplicate card+hook
  across files, and writes nothing if any error fires.
* `tools/test_compiler.py` — 11 tests / 104 checks.
* `tests/` — 274 suites / 2,517 assertions, run by LuaJIT 2.1 (Lua 5.1 semantics,
  same as WoW). `tests/wowstub.lua` is a **strict** WoW mock so `Client/UI/` runs
  headless; any unmodelled frame method errors by name.
* `APIProbe/` — 280-probe read-only diagnostic addon for retail/Forever.

### Working practice that has repeatedly paid off

**Mutation testing.** After writing tests, deliberately break the code and
confirm the tests fail. This has caught vacuous tests several times — a
"snapshot" test that passed with the snapshot removed, an impact-shake assertion
that never existed, trigger ordering that was entirely untested. Roughly 45
mutations have been run; every surviving mutation revealed a real gap in the
tests, not in the code. **Keep doing this.**

---

## 8.5 Card authoring status

```
pool cards            535
need a script         458
pure data, no script   77   (printed keywords/fields only)
authored              458   (100.0%)  2 of them hand-written, see below
still missing           0
hero powers             9/9
```

**Every card in the pool is authored.** **Nozdormu** expresses the rule
(`Game:TurnSeconds()` returns 15 for both players), and since the director
(§8.17 below) the turn clock and rope consume it -- *updated 2026-09-25: it
was flagged here as inert, which stopped being true then.*

The coverage report used to read only the CSVs, so the three cards implemented
in `Data/Effects/Handwritten.lua` were reported as outstanding work. It reads
that file now, which is why the earlier 349/108 did not add up against the
worklists (458 - 349 = 109, but the two batch files held 108 between them).
Water Elemental was the odd one out: already implemented, just invisible.

Authored in `tools/effects.csv` + `tools/effects/*.csv` (the directory exists so
several authors can work in parallel without colliding).

### The 95 that were remaining, grouped (historical)

*All of these are authored now (the table above: 0 missing). This section and
`tools/batches/REMAINING.txt` are kept as the record of that batch, not as a
worklist.*

**`tools/batches/REMAINING.txt`** — 95 cards, tab-separated with id, class, name,
type, cost, stats, mechanics, text and playRequirements.
**`tools/batches/CHOOSE_ONE.txt`** — **done**, kept as a record of the batch.

They were blocked on these features, in rough order of cards unblocked:

| feature | cards | notes |
|---|---|---|
| ~~**Choose One**~~ | ~~13~~ | **done** — see §8.9 |
| random generation from the card pool | ~12 | random minion of cost N, random Beast/Murloc/Mech/legendary/weapon. Needs a filtered pool query |
| zone-movement ops | ~10 | deck→hand, hand→board, deck→secret zone, mill from top of deck |
| dynamic aura magnitudes | ~6 | the Giants (`AuraCost(self, -count(sel))`), Old Murk-Eye |
| `CopyToHand(sel[, n])` | ~4 | Duplicate, Echo of Medivh, Thoughtsteal, Gallywix |
| attack/spell retargeting | 3 | Misdirection, Spellbender, Noble Sacrifice. `Game:ApplyForgetful` redirects but nothing exposes it to scripts |
| selector filters | ~4 | has-deathrattle, has-battlecry, by cardId, negative race |
| "if that kills it" | 2 | Mortal Coil, Bane of Doom — needs a did-it-die hook |
| hero replacement | 2 | Lord Jaraxxus, Shadowform |
| random amount ranges | 3 | Crackle, Lightning Storm, Imp-losion |
| a long tail of one-off ops | ~25 | listed individually in the agent reports; each names the exact op it needs |

### Cards deliberately PARTIAL -- none left (2026-09-25)

Cards used to be flagged `PARTIAL` in their CSV `notes` column when authored
with a known gap. **None remain** (`grep -rn PARTIAL tools/effects*` finds
nothing). The last ones were fixed in docs/19 (Demonfire, Demonheart, Floating
Watcher, Nozdormu's stale flag) and docs/20 (Summoning Portal, Betrayal,
Harrison Jones, Mechanical Yeti, Elite Tauren Chieftain, Shadow Madness,
Blessing of Wisdom; Poison Seeds, Reincarnate, Ancestral Spirit and Flare had
already been fixed by engine work and are now tested). Every one of them has
a suite in `tests/test_partials.lua`.

---

## 8.6 What is NOT built at all

In rough dependency order. Sections refer to the original brief.

1. ~~**Choose One**~~ — **built**. See §8.9. The premise in this list was wrong:
   printed data *does* represent the modes.
2. ~~**Networking / lockstep transport**~~ — **built**. See §8.12. Lockstep
   with a shared seed, commit-reveal, sequence numbers with NAK, hashes at every
   turn boundary, and two sessions that play whole matches against each other in
   the test suite.
3. **Proximity + sitting gate** (brief §2) — **half built** (§8.12). Range is
   enforced on the challenge via `CheckInteractDistance` with a
   `UnitDistanceSquared` fallback, and the right-click "Challenge to
   Hearthstone" is wired through `Menu.ModifyMenu`. **There is no
   `IsSitting()`** on the client, so sitting is a prompt rather than a check,
   and cannot become one. *Updated 2026-09-25:* range IS now enforced
   continuously -- see item 4.
4. ~~**World-interruption state machine**~~ — **built** (*noted 2026-09-25*).
   `Main:WhyAway` / `Main:CheckTable` pause a duel when you die, enter combat
   or walk more than `TABLE_RANGE` yards from where you sat (your own
   position, so it needs no report from the other side), and resume when that
   ends; `Client/Net/Session.lua` owns the grace period and the forfeit, and a
   logout or /reload pauses as "left" so a reload can rejoin. The rope pauses
   with the match.
5. ~~**The controller layer / entry point**~~ — **built**. See §8.10: the
   addon has a `.toc`, loads, and `/fh` starts a playable practice match against
   a practice AI.
6. ~~**Drop detection + progression hooks**~~ — **built**. See §8.13.
7. ~~**Persistence**~~ — **built**, and honest about what cannot be fixed.
   See §8.13.
8. **Remaining UI** (brief §8) — collection browser, deck builder, crafting and
   pack opening are **built** (§8.14), and the board draws the whole table with
   animation and sound (§8.17). *Updated 2026-09-25:* the emote wheel is built
   (right-click your hero), and duel wins and losses are recorded. Still
   missing: spectator view for nearby players, squelching the opponent's
   emotes, and a screen for local match history and stats.
9. ~~**Practice mode / AI**~~ — a practice AI is **built** (§8.10). The
   TUTORIAL is not (brief §7-ish). Doubles as the solo dev loop.
   Tutorial should teach *this addon's* oddities: class locking, mob drops, the
   proximity/sitting requirement, packs, crafting, golden rarity.
10. ~~**Asset manifest population**~~ — **the generic tier is built** (§8.15).
   20 candidate paths cover all 683 slots with class-, type- and race-appropriate
   icons, and `/fh icons` is the audit screen that lets a human verify them.
   **Someone with a client still has to run that audit** — the paths are guesses
   until an eye has seen them.
11. **Whisper-a-stranger advert**. The user asked for a download pitch whispered
    to a challenged player without the addon. The plan was to build it gated:
    once per target character ever, opt-in, one short line. *Corrected
    2026-09-25:* it is **not built** -- the addon sends only addon-channel
    messages (`SendAddonMessage`), never a chat whisper. Flag before building:
    unsolicited automated whispers to strangers look like gold spam from the
    receiving end.

---

## 8.7 Open decisions the user must make

* **Levels 40–60.** Reopened when golden class cards moved to mob drops. All 34
  class cards are granted by level 60 under the current curve (1–10 Basic, 11–40
  Classic, 41–60 Naxx+GvG), so this may already be answered — confirm.
* **Per-class 11–40 card ordering.** Needs a data table ordering each class's
  Classic cards by *deck utility*, not rarity, so a level-20 character has its
  core removal rather than only vanilla minions.
* **Music ducking.** There is no ducking API. Recommendation: leave zone music
  alone. Faking it via `Sound_MusicVolume` would leave the player's audio changed
  after a crash, so it should be opt-in with a restore net if wanted at all.
* **Five fidelity uncertainties** needing a replay to settle: FORGETFUL's
  ordering vs secrets; whether Reversing Switch swaps current or max health;
  whether a Mind-Controlled minion is summoning-sick; `setTo`-then-delta cost
  ordering; and **whether Nourish's and Grove Tender's Mana Crystals arrive
  empty**. Both are authored `empty`, on the rule that every *permanent* crystal
  gain in Hearthstone arrives empty — Wild Growth says so on the card, and only
  temporary gains (Innervate, The Coin) are spendable at once. Neither card's
  text says "empty", so this is inference from a rule rather than from the pin.
  A replay settles it; if wrong, it is a one-word CSV change in each.

---

## 8.8 Things that have gone wrong, so they do not recur

* **Verify every edit.** A batch of four `side`-argument edits was written and
  none verified; three silently failed to match, so the DSL promised features the
  compiler did not emit — one of which would have handed the caster free minions.
* **`\b` in a non-raw Python string is a backspace byte.** This silently corrupted
  a regex twice. It was caught only because a coverage number moved the wrong way.
* **Stale `__pycache__`.** `importlib` loaded bytecode predating a fix, so the
  compiler tests validated old code. Now prevented in `test_compiler.py` and
  `run-tests.sh`, but be suspicious if a Python fix appears not to take.
* **False negatives are worse than false positives.** A blanket reminder-text
  strip would have marked three cards complete while they did nothing. Reminder
  stripping is now gated on the card genuinely carrying the mechanic.
* **A green test can be vacuous.** Several tests passed with the code they
  supposedly covered removed. Mutation-test new tests.
* **Testing the method is not testing the card.** Every silence test called
  `entity:Silence()` directly, so the `Silence` *op* — the thing an actual card
  runs — had never executed, and it was broken for three cards. When a card's
  behaviour is the point, play the card.
* **Look at the pin before declaring a data gap.** Choose One was written up as
  needing a mode representation invented. The pin had carried one all along.
* **A report that cannot see a source of truth under-reports.** Coverage read
  the CSVs and not `Handwritten.lua`, so finished cards sat on the worklist.

---

## 8.9 Choose One — built

Thirteen Druid cards. Built 2026-09-20; `tests/test_chooseone.lua` (27 suites)
and six new compiler tests cover it.

### The premise in §8.6 was wrong

That list said printed data has no mode representation. It does. Every Choose
One card carries its two modes as real, **non-collectible 0-cost SPELL cards**
with ids `<parent>a` / `<parent>b`, each with its own text and its own
`playRequirements`:

```
EX1_166  Keeper of the Grove   "Choose One - Deal 2 damage; or Silence a minion."
  EX1_166a  Moonfire   REQ_TARGET_TO_PLAY
  EX1_166b  Dispel     REQ_TARGET_TO_PLAY + REQ_MINION_TARGET
```

They were already being imported — the importer sweeps every non-collectible
card into the token table. The only thing missing was the link from parent to
modes, so the whole data change is one `chooseOne={...}` field on 13 cards.

**The lesson worth keeping: look at the pin before declaring a data gap.**

### How it works

`tools/chooseone.py` derives the parent→modes map, shared by the importer and
the compiler. One substitution does the entire mechanic:

> **The chosen mode's script replaces the parent's. Nothing else changes.**

Everything falls out of that:

| | |
|---|---|
| targeting | comes from the **mode** (`Targeting.ReqsFor`), so Moonfire may hit a hero and Dispel may not |
| card type, ctx, events, spell damage | come from the **parent**, unchanged |
| Keeper's Moonfire | a MINION's mode → a **battlecry**: no Spell Damage, and it *can* hit a Faerie Dragon |
| Wrath | a SPELL's mode → a **spell**: Spell Damage applies, Faerie Dragon is immune |

That split is exactly what the printed text says: Wrath reads `$3` (the
spell-damage sigil), Keeper of the Grove reads `2`. **Do not "simplify" this by
swapping in the mode's printed table wholesale** — the mode cards are all typed
SPELL, which is a data artefact, and doing so silently breaks both rows above.

`Game:PlayCard(player, handIndex, target, position, mode)`. A mode is **required**
on a Choose One card and **refused** on any other; the mode is validated before
anything moves, so a rejected play leaves the hand untouched. `mode` is a plain
1 or 2, so it costs one byte in a lockstep frame, and the two modes hash
differently under `Game:StateHash`.

### Display order is the card text, not the a/b suffix

Four of the thirteen are reversed: Ancient of War, Dark Wispers, Starfall, Power
of the Wild. The order is recovered by matching each mode's text against the two
halves of the parent's "Choose One - X; or Y", and an ambiguous pair **raises**
rather than guessing — a silently swapped pair would offer the wrong mode under
the right label and nothing downstream could notice. Tightest real margin is
0.403 (Starfall) against a floor of 0.10, asserted by a compiler test.

### Druid of the Claw is the only transform

The pin settles it without recall: EX1_165 has 4/4 Charge and 4/6 Taunt **token
minions**, while Ancient of War, Anodized Robo Cub, Mark of Nature and Power of
the Wild have mode **ENCHANTMENTs**. So Bear Form transforms and Rooted buffs —
which means Silence reverts an Ancient of War to a 5/5 but leaves a Bear Form
alone. Both are tested.

### Authoring rules the compiler enforces

* Author the **modes**, never the parent. A script on a parent is an error.
* A mode's hook follows the **parent's type**: `battlecry` for a MINION parent,
  `spell` for a SPELL parent.
* Both modes or neither — one of two is an error, not a coverage gap.

### Client

`Layout.Compute{ chooseOne = true }` produces `L.choosePrompt` (dimmer, two card
rects, title); `Board` renders it from `snapshot.chooseOne =
{ handIndex, position, options }`, where `options` is `Targeting.ModeOptions`.
Each option renders as a real card from the **mode's own** printed name and
text, so it needs no art and no authored UI strings. An unplayable mode is
**dimmed, not hidden** — seeing that the Panther is unavailable because the
board is full is what tells the player to take the other mode. Clicking a mode
emits `PLAY_CARD{ handIndex, position, mode }`; clicking the dimmer emits
`CANCEL_MODE`.

**Still needed:** the controller layer that sits between them. `Board` emits
`PLAY_CARD` with no mode; something has to notice `ModeOptions` is non-nil, push
the snapshot with `chooseOne` set, and re-issue the play with the mode. That
layer does not exist yet for *any* intent, so it is not a Choose One gap.

### Two things found while building this

1. **The `Silence` op was broken.** It raised its event through `game:Raise`,
   which does not exist (`game.bus:Raise`). The error was swallowed by the event
   block, so the silence landed and the op list simply stopped — and because the
   raise sat *inside* the per-entity loop, **Mass Dispel silenced only the first
   enemy minion and never drew**, **Wailing Soul silenced only the first other
   minion**, and **Earth Shock never dealt its damage**. Every earlier silence
   test called `entity:Silence()` directly, so the op path had never once run.
   Fixed, with a regression test per card.

2. **Coverage could not see `Handwritten.lua`**, so three finished cards were
   reported as work to do. It reads it now. Water Elemental moved from there to
   an ordinary CSV row (the DSL had since grown the condition it needed), and
   two placeholder CSV rows that compiled to *empty* scripts — harmless only
   because the hand-written entries shadowed them — are gone. A card authored in
   both places now warns.

23 mutations were run against this work. Twenty-two were caught; the one
survivor turned out to be an unreachable clamp in the layout, which was deleted
and replaced by an assertion on the property it had been protecting.

---

## 8.10 The addon now assembles, loads and is playable

Written 2026-09-20. Everything here was verified by running it.

### It is an addon now, not just an engine

There was **no `.toc` file**. The rules engine was complete and heavily tested,
and none of it could load in World of Warcraft, because nothing told the client
which files to read or in what order.

* **`ForeverHearthstone/ForeverHearthstone.toc`** — interface 16001 (Mainline),
  SavedVariables, and the full load order.
* **`Client/Controller.lua`** — the glue §8.6 said was missing. Board emits
  intents, engine enforces rules, and nothing joined them. It owns the Game,
  turns intents into engine calls, and produces the snapshot the board renders.
  **No WoW API**, so the whole interaction model is tested headless.
* **`Client/Main.lua`** — the entry point. `/fh` starts a practice match.
* **`Client/AI.lua`** — a practice opponent, so there is someone on the other
  side. Also **no WoW API**.

`tests/test_packaging.lua` guards the thing that would otherwise rot silently:
**WoW reads the `.toc`, the tests read `tests/harness.lua`.** If those two lists
drift, the entire suite stays green while the addon fails to load in game. They
are now compared file by file, and `Main.lua` is executed against the strict
stub to prove its API calls exist on the Mainline surface.

### The AI is the best test in the suite

`tests/test_ai.lua` plays **24 full matches to completion across all nine
classes** and asserts `game.errors` is empty in every one. That drives real card
scripts against each other in combinations no hand-written test would think to
try. An unknown op, a bad selector or a nil index anywhere in the pool surfaces
there rather than in front of a player.

It was first written as a deliberately modest player (curve out, free trades,
face otherwise). **docs/26 replaced it**: it now plays every candidate move on
a copy of the game (`Game:Clone`) and searches whole turns, with seven decks per
class and a difficulty slider. Every decision still routes through the public
rules, so **it cannot cheat even by accident**, and its loops are still bounded,
because a practice opponent that hangs the client is a worse failure than one
that passes its turn. The soak now plays every one of the bots' 63 decks.

### What the card work needed

Roughly forty primitives, because 95 cards were blocked on features that did not
exist. The ones worth knowing:

| | |
|---|---|
| `Engine/CardPool.lua` | filtered queries over the collectible pool, **sorted before any roll** — `pairs()` order is unspecified, so feeding it to the RNG would desync lockstep intermittently |
| zone movement | `MoveToHand/Board/Secret`, `MillDeck`, `ShuffleCardIn`, `CopyToHand`, `SwapWithHand` — all move a card from ANY zone, and the bug they invite is leaving it in two |
| dynamic aura magnitudes | the Giants. Because the aura layer rebuilds from zero, a dynamic magnitude needs no invalidation at all |
| retargeting | `Game:Attack` now RE-READS its defender after PRE_ATTACK. Reading the local was why no secret could ever move an attack |
| `property` hook | top-level script fields the engine reads (`DeathrattleMultiplier`, `HealsDealDamage`, `SpellMultiplier`). This is what used to force a card into `Handwritten.lua` |
| `lastSummoned` / `lastDrawn` | "the thing an earlier op just made", which nothing else could name |

The full grammar is, as always, the `tools/compile_effects.py` module docstring.

### Bugs the work uncovered

Each was found by a card needing something, not by reading code:

* **The `Silence` op was broken.** It raised through `game:Raise`, which does not
  exist. The error was swallowed by the event block, and because the raise sat
  *inside* the per-entity loop, **Mass Dispel silenced only the first enemy
  minion and never drew**, **Wailing Soul silenced only the first other minion**,
  and **Earth Shock never dealt its damage**. Every earlier silence test called
  `entity:Silence()` directly, so the op path had never run.
* **Summoning onto the opponent's board crashed.** `RIGHT_OF_SOURCE` used the
  *source's* board index against the *destination* board, unclamped, leaving a
  hole `Reindex` died on. Leeroy Jenkins summoned zero Whelps.
* **`Summon(id, <non-numeric>)` silently discarded its argument**, so the natural
  Imp-losion spelling compiled to one Imp and said nothing.
* **`Repeat()` was regex-limited to a literal**, making the documented `dealt`
  impossible to consume. **`payloadAmount` was documented and implemented but
  never emitted by the parser.** Same class of bug, twice: *the docstring
  promising what the grammar cannot say.*
* **A `cond` on a deathrattle row was silently dropped** — `AttachScript` stores
  bare ops and never reads it. Now rejected with a message.
* **Coverage could not see `Handwritten.lua`**, so three finished cards sat on
  the worklist. That is why 458 − 349 did not reconcile with the batch files.
* **`dealt` was the raw roll, before spell power** — so Spell Damage made
  Imp-losion deal more damage but summon no extra Imps.
* **Board-state play requirements were never enforced on the way IN.** Brawl's
  `REQ_MINIMUM_TOTAL_MINIONS`, Upgrade!'s `REQ_WEAPON_EQUIPPED` and the seven
  `REQ_NUM_MINION_SLOTS` cards were checked only by `Targeting.CanPlay` — which
  the UI uses to *grey a card out*. So the rule held for a human clicking a
  greyed card and failed for everything else: the AI, a replayed action, and
  anything arriving over the wire could play Brawl into a single minion.
* **`not A and B` parsed as `not (A and B)`.** The `not ` prefix was tested
  before the and/or split, so the condition grammar quietly meant the opposite
  of what it read like. One authored card had been written to depend on the old
  reading (Truesilver Champion) and another was contorted to work around it
  (Gallywix). `and`/`or` now bind looser, as they read.
* **A `flags` value on a hook that does not read flags was discarded in
  silence** — which is how Bolvar Fordragon's `hand` flag compiled cleanly and
  did nothing at all. Now an error.

### Working practice, confirmed again

Every primitive was mutation-tested. Roughly **fifty** mutations this round, and
four survivors each revealed a real gap rather than a safe one: a dead clamp in
the layout, a test whose fixtures could not distinguish the case, two guards
that masked each other. **Two of the survivors were tests I had just written**,
which is the argument for the habit in one line.

The subagents were told to report blocked cards with the exact missing primitive
rather than approximate them. That turned out to be worth more than the cards
they authored: **four of the seven bugs above came from those reports.**

---

## 8.11 The pool is complete — and what the last three cards turned up

Written 2026-09-20.

The last three cards were Tracking, Steamwheedle Sniper and Nozdormu. Going
after them surfaced something much larger than three cards.

### EIGHT OF THE NINE HERO POWERS DID NOTHING

Only Shapeshift was authored. `Game:UseHeroPower` runs
`if script and script.heroPower`, so a missing script is not an error — the
power was simply used, the mana spent, and nothing happened. Every match ever
played by eight of the nine classes had an inert hero power.

It hid because **hero powers are not collectible**, so they were never in
`pool` and the coverage report could not count them. Exactly the shape of the
`Handwritten.lua` gap (§8.10): a report that cannot see a source of truth
under-reports, and the number looks healthy the whole time. Coverage now prints
a `hero powers : N/9` line, and a test asserts every class's power has a script.

**Hero powers also went through no targeting at all.** Six of the nine carry
printed requirements. Fireblast could be fired into empty space, Reinforce
worked with a full board, and Totemic Call kept summoning after all four Totems
were out. `UseHeroPower` now goes through `Targeting` — the same call the UI
greys out with, so the rule holds identically for a click, for the practice AI,
and for anything arriving over the wire.

And the three `REQ_*` values that appear **only on HERO_POWER cards** are now
implemented. The Targeting docstring claimed the requirement vocabulary was
"verified by enumeration"; that enumeration had looked at collectible cards
only, and the three were reaching the fail-closed branch. The docstring now says
so.

### A decision taken MID-RESOLUTION

Tracking is the only card in the pool that stops to ask. The Choose One mode is
decided *before* the card is played, so it is an argument to `PlayCard`; this is
different, because the options do not exist until the card has begun resolving.

So the card leaves a `pendingChoice` behind and the rest happens when the answer
arrives. Two details are load-bearing:

* **The three cards leave the deck immediately**, which is what Hearthstone
  does — while you are looking at them, nothing in between can draw or steal
  them.
* **Every action is refused while a choice is outstanding.** Allowing plays in
  between would let a player act on information the opponent's client has not
  been told about, which across the wire is a desync waiting to happen.

Like the Choose One mode, the answer is a plain index: one byte in a lockstep
frame. The prompt renders through the same client path, generalised from exactly
two options to N.

**The AI-vs-AI soak test earned its keep here.** The moment Tracking existed,
the practice AI played it and then carried on attacking into a game that was
refusing every action — a hundred consecutive "attack while a choice is
pending" errors, caught immediately, in a card interaction nothing hand-written
would have thought to try.

### Smaller things the three cards forced

* **Totemic Call repeated Totems.** Hearthstone never gives you one you already
  have, and while the power repeats, `REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY` can
  never be reached — so the requirement was unreachable as well as unchecked.
  `SummonEntourage(unique)` now draws only from members not already on the
  board. NOT the default: Bane of Doom summons a random Demon from a six-card
  entourage and repeats there are correct.
* **`REQ_ENTIRE_ENTOURAGE_NOT_IN_PLAY` was implemented but never consulted** —
  it was missing from the board-state requirement list, so nothing asked it.

### Verification

Twelve mutations against this work, all caught. The pool is at 100% with the
full suite green, and the addon still loads, starts and plays.

---

## 8.12 Networking — built

Written 2026-09-20. It is the game in the brief now, not solitaire.

### The choice: lockstep with a shared seed

Not an authoritative client. The argument, in full, is in the header of
`Client/Net/Session.lua`; in short:

* the engine is already deterministic **and tested to be**, so lockstep is the
  design that gets paid for that work;
* an action is a dozen bytes and a board is not, which matters against a
  255-byte message limit and a throttled channel;
* every rule runs on both machines, so a bug cannot be one-sided and a desync is
  *detected* rather than silently rendered;
* a seed plus an action log replays the whole match.

**The cost, stated plainly:** both clients hold the full game state, including
the opponent's hand. A modified addon could read it. There is no fix for that
peer-to-peer — an authoritative client has the same problem once the authority
is the other player's machine. What *is* removed is the cheat social pressure
cannot see: the shuffle seed is commit-reveal, so neither player can pick their
draws. The rest is the honour system, which is what the brief asks for.

### The four files

| | |
|---|---|
| `Client/Actions.lua` | **an action is the unit of play**. One function applies one, and the local player, the wire, the practice AI and any future replay all go through it. This is the direct answer to the §8.10 bug where board-state play requirements held for a human clicking and failed for everything else |
| `Client/Net/Protocol.lua` | the wire format: sequence numbers, NAK-and-resend, chunking, the version handshake. Pure, so framing is tested headless |
| `Client/Net/Session.lua` | the duel as a state machine: challenge → version check → commit/reveal → decks → play, with desync detection at every turn boundary. Pure |
| `Client/Net/Transport.lua` | the only part that touches WoW: `C_ChatInfo`, the prefix, and a send **throttle** |

`Controller`, `AI` and `Session` all submit actions through the same seam, which
is why networking needed no change to the interaction model: the controller does
not know whether there is a person on the other side.

### What the tests do

`tests/test_net.lua` wires two sessions to each other with a table for a wire
and **plays whole matches**, driving both sides with the practice AI and
comparing `Game:StateHash` at every turn. A soak test of the AI is therefore
also a soak test of the protocol. `tests/test_transport.lua` runs the WoW half
against the strict stub: prefix registration, event wiring, the throttle, and a
duel that goes slash command → session → `CHAT_MSG_ADDON` → board.

### Decisions worth keeping

* **The challenger is player 1 on both clients** and who goes first falls out of
  the seed. Nothing negotiates either, so there is nothing to disagree about.
* **An illegal remote action is a desync, not a shrug.** If their client thought
  it was legal, the two states have already diverged.
* **Leaving mid-match is a forfeit**, or quitting is the correct play when losing.
* **An unknown message kind is ignored**, which is what lets a later version add
  one without breaking this one.
* **Emotes are not in the action stream** — a dropped emote must not be a desync.

### Bugs found while building it

* **The send throttle sent everything immediately.** "Drain one now so a single
  message does not wait" emptied the queue each time, so every send qualified.
  Found by the test that asserts a burst is paced — which is the failure WoW
  punishes with silence rather than an error.
* **The stub's ticker never fired**, so every repeating timer in the addon was
  untestable and the throttle above looked fine. `Stub.Advance` now fires timers
  in order and lets a re-arming ticker fire again inside one window.
* **Chunk reassembly lost separators.** Rebuilding a fragment from the decoded
  fields truncates it at its first separator — which is most fragments. It reads
  the raw line past a fixed number of separators instead.

---

## 8.13 Drops, the collection and persistence — built

### The model

`Client/Collection.lua` is the whole of decisions D0–D5, in one pure file over
the two SavedVariables tables (no separate serialisation step, because a second
representation drifts). `Client/Packs.lua` generates packs and mob-drop cards;
`Client/Drops.lua` decides what a kill is worth; `Client/Rewards.lua` is the
WoW-facing part that watches the events.

Distribution tests roll **100,000 kills** and 2,000 packs, which is the only
honest way to check a 1% rate.

### The XP gate is OBSERVED, not computed

There is no "did that grant XP" API. Rather than reciting WoW's grey-level
formula from memory — exactly the recalled data this project refuses to trust —
`Rewards` remembers the player's XP and looks again 0.4s after a death. At 60,
where nothing grants XP, the gate becomes mob level ≥ 55.

### Persistence, and what cannot be fixed

SavedVariables reach disk **on logout or `/reload` and at no other time**, and
no API can force a flush. So the addon does the three honest things: it counts
what is unwritten, it says so once the number is worth acting on, and `/fh save`
reloads — which *is* the flush. A session that ended without a clean logout is
reported at the next login, because "where did my packs go" deserves an answer.

A save file written by a **newer** schema is refused rather than rewritten.

### A finding about `Game:Random`

Measuring the LCG for the distribution tests showed it is not statistically
flat: 100,000 consecutive `d100 <= 3` rolls come out at 3.3%. That is invisible
in a card game — draws are interleaved at many different moduli and nobody rolls
the same thing 100,000 times — and it is fatal to a test measuring a 1% rate, so
the distribution tests use the interpreter's generator, seeded. **Do not
"improve" Game:Random**: reproducibility across machines is the requirement, and
quality is not.

---

## 8.14 The out-of-match app — built

`Client/UI/CollectionLayout.lua` (pure solver, swept across 8 window sizes) and
`Client/UI/Collection.lua` (frames, against the strict stub).

**Three modes, one screen**: browsing, editing a deck, opening a pack. The same
grid throughout, which is why a card you just crafted is already in front of
you. Cards are drawn by `ns.CardWidget` — literally the board's own card code,
exported — so a card looks identical in the collection and on the table,
including how it degrades with missing art.

The grid shape is **solved**: every legal shape is evaluated and the one showing
the most cards wins, subject to a card-width floor. Without the floor the solver
happily picks 32 unreadable slivers at 760×560; with it, a bigger window shows
more cards rather than a bigger version of the same page.

`/fh deck` lists, creates, edits and chooses the duelling deck. A deck that has
stopped being legal (a card disenchanted out from under it) falls back to the
Basic deck **with a message**, rather than refusing to start a duel.

---

## 8.15 The juice is wired, and the art has a floor

### `Client/FX/Director.lua`

The choreography library has been tested since long before there was a match to
play it in, and nothing drove it. The Director does, and it is pure: handed
actions and elapsed time, returning a plan.

**Driven by actions, not by diffing snapshots.** A minion can arrive for half a
dozen reasons and a diff cannot tell them apart, so a diff-driven director plays
the "card from hand" animation for a deathrattle token.

**Nozdormu finally does something.** The rope is the one sequence that needs a
clock, and it is the first thing in the project to consume `Game:TurnSeconds()`.
Each client times **its own** turn and ends it with an ordinary `END_TURN`
action, so there is nothing for two clients to disagree about.

Two bugs the tests caught: reading the hand slot *after* the play (animating
whatever slid into it), and looking up the combatants *after* an attack — where
`Game:EntityById` cannot find anything that just died, so it reported that
nobody died in exactly the case where something did.

### `Client/Assets/GenericArt.lua` — candidates, an audit, and a probe

Twenty entries cover all 683 art slots with class-, type- and race-appropriate
icons; the Resolver's generic chain now tries **race** above type, because a row
of Beasts that all look like beasts reads instantly.

**These paths are candidates, not facts.** docs/06's rule stands — no icon path
is authored from memory — and the resolution is that an eye is the only possible
verifier (`SetTexture` on a bad path draws nothing and reports success), so the
job is not to guess well but to make checking cheap. `/fh icons` shows every
candidate at size with what it is for; `/fh icons blank <KEY>` records a verdict
that then beats the guess forever. A candidate marked blank is **deleted** from
the manifest rather than replaced, so the fallback chain handles it and a wrong
guess costs nothing worse than a question mark.

**This is the one piece of work in this handoff that still needs someone with a
client.** Twenty icons, about thirty seconds.

---

## 8.16 What is left after all this

1. **Continuous proximity enforcement** during a match (§8.12) and the
   world-interruption state machine (§8.6 item 4). The wire half of pausing is
   built and tested; the policy — mob aggro, death, disconnect, grace periods,
   auto-forfeit — is not.
2. **Emote buttons and squelch.** The `EMOTE` message exists and is tested; six
   buttons and the `C_ChatInfo.PerformEmote` mapping do not.

   *(The mulligan, hero-power targeting and secrets have since been built --
   see §8.18. What remains below is accurate.)*
3. **Spectator view** for nearby players, and **local match history** (the
   per-character `history` table exists and nothing writes to it).
4. **The tutorial** (§8.6 item 9).
5. **The whisper-a-stranger advert** (§8.6 item 11) — still needs a flag before
   shipping.
6. **The icon audit** (§8.15, §8.17) -- or, on a client with
   `GetFileIDFromPath`, nothing at all, because it settles itself at login.
   Per-card art beyond the 38 generic icons is an asset-pack job and always was.
7. **The per-class card-utility ordering** the levelling curve uses. The
   mechanism is built and the placeholder is defensible (commons and rares
   first, legendaries in the 30–60 band, cheap before expensive) — but docs/03
   D4 asks for an authored table, and it remains an open decision. Replacing it
   is a single function in `Client/Collection.lua`.
8. **The dust economy retune** permitted by deviation 7. Hearthstone's printed
   values are used as-is, with `Collection.DUST_SCALE` as the one place to
   change it.

Roughly **35 mutations** were run against this work; every survivor revealed a
real gap in the tests rather than a safe mutation. The habit continues to pay.

---

## 8.17 The board is a board now

Written 2026-09-20, after the question "so we have the full GUI, animations,
sounds?" — which was worth asking, because the answer was no.

### What was actually wrong

Three things, and the first is the worst:

* **`ns.SoundFor` was called by Board.lua and DEFINED NOWHERE.** Every sound in
  the game resolved to nil, guarded by an `and`, so the addon was completely
  silent and nothing said so. That is the silent-nil pattern §8.8 warns about,
  sitting in the middle of the presentation layer.
* **Layout had been computing rects that nothing drew.** Both heroes, both hero
  powers, both weapons, the mana crystals, the enemy hand, the deck piles and
  the rope — all solved, all correct, none of them rendered. A "board" was your
  hand, two rows of minions and an End Turn button.
* **The stage stored values nothing read.** `Screen:Shake` and `:Vignette` set a
  number on the board object; `Hero()` returned a handle for a nil frame;
  `Board:Shove`, `Rot`, `Burst` and `Particles` were empty. The choreography ran
  perfectly and moved almost nothing.

### What exists now

`Client/UI/Widgets.lua` — the card widget moved out of Board (so the collection
screen and the table share one card implementation), plus portraits, mana
crystals, the rope, toasts, a pooled and **capped** particle system, the shake,
the vignette and the tweens.

The board draws: both heroes with health and armour, both hero powers (dimmed
when spent, lit when usable), weapons, ten mana crystals with **Overload in its
own colour**, the enemy hand face down, both deck counts, and the rope.

The feel: **playable cards glow**, **minions that can still swing are ringed**
and the selected attacker differently, **legal targets light up** while aiming,
**the hovered card lifts clear of the fan and draws over its neighbours**, and
**the hand slides rather than teleports** when it changes — but snaps on a
resize, because a hand that tweens while you drag the window chases the cursor.

`Client/FX/Sounds.lua` — the registry that was missing. Sounds resolve through
the client's own `SOUNDKIT` table by NAME, so no sound id is written down in
this project: a right name gives the id the client itself uses, a wrong one
gives nil and silence. The five pack reveals use five distinct names, which is
how the Peggle escalation is faked on a client that cannot pitch-shift.

### Art: candidates, and a probe that may settle them

38 generic entries now (the 20 from §8.15 plus nine hero portraits and nine hero
powers), which is every one of the 683 slots covered with something
class-, type- or race-appropriate.

`GenericArt.Probe` feature-detects `GetFileIDFromPath` and
`C_Texture.GetAtlasInfo` — both of which the probe addon already asks about. If
Forever has either, `AutoAudit` turns 38 guesses into 38 facts at login and
nobody has to look at anything; if not, it returns **nil for unknown** (never
false) and `/fh icons` is still there for a human. Blank entries are deleted
from the manifest so the fallback chain handles them.

**What is still not Hearthstone's art:** none of it. The cards are flat
colours, text and WoW's own icons, because Hearthstone's frames, gems, board and
portraits are Blizzard's Hearthstone assets and are not ours to ship. An asset
pack tier exists for anyone who wants to supply their own.

### Three bugs, all found by tests that had been lying

* **The stub never drove `OnUpdate`.** Every animation in this addon runs on
  one, so no test had ever run an animation through the real frame path: a toast
  could be "played" for five seconds and still be sitting at full alpha.
  `Stub.Advance` now steps in 1/60 slices and drives them, with timers
  interleaved at their exact due time.
* **The toast hid itself on the first frame of its own arrival.** Every slide-in
  starts at alpha 0, and the handler hid at alpha 0 and never re-showed. Found
  within a minute of the stub actually ticking OnUpdate.
* **A drop toast could not appear at all with no board on screen** — which is
  the NORMAL case, since drops happen mid-fight out in the world. It was being
  driven into a null stage. There is a standalone world stage now.

### And two tests that were lying

Mutation testing caught both, and both were vacuous for the same kind of reason:

* the shake test anchored the board at the **origin**, where "anchor + offset"
  and "offset" are the same number, so a mutation making the shake absolute
  passed. It now starts off-origin, and also asserts that a shake after the
  player moves the window follows the window.
* the "hand must not animate on a resize" test resized a frame in a stub that
  **did not fire `OnSizeChanged`**, so no relayout ever happened.

One mutation survived honestly: an explicit "restore the frame to its anchor"
after the shake finished could not be observed, because the final tick already
applies a zero amplitude. Per the §8.9 precedent it was deleted rather than
kept, and the property it protected is asserted instead.

Roughly **24 mutations** this round; the three survivors are described above.

---

## 8.18 The mulligan, hero-power targeting and secrets — built

Written 2026-09-20. These were the three things standing between the addon and
"plays like Hearthstone", and one of them turned out to be hiding a real
lockstep bug.

### The mulligan was unreachable, and the API said so

`Game:ApplyMulligan` existed, was correct, and carried a comment saying it was
applied "by the caller before StartGame" — and `StartGame` was the call that
DEALT the hand. There was nothing to mulligan before it and no way to mulligan
after it, which is why nothing had ever called it.

The opening is three parts now: `Deal()`, both players submit, and the game
begins itself. `StartGame()` stays as deal-and-play for practice and for the
seven hundred tests that rely on it.

**Both choices are recorded before EITHER is applied, and then they are applied
in player order.** That is a lockstep requirement, not tidiness: `ApplyMulligan`
shuffles, which draws from the shared random stream, so applying them in arrival
order would diverge the two clients on the very first action of the match. A
test answers in both orders and compares the resulting decks card for card.

The phase is part of `StateHash`, so a client that thinks the mulligan is over
while the other does not is caught immediately.

### Two classes could not use their hero power

Fireblast and Lesser Heal require a target. The board's hero-power button sent
none, and the controller had no targeting flow for one — `BeginPlay` handled
hand cards only. So `UseHeroPower` refused, correctly, every time, and **two of
the nine classes could not use their hero power at all through the UI**.

It now goes through the same targeting path a card does: the same pending state,
the same highlight, the same legality check, the same refusal.

### Secrets were invisible

Fully implemented in the engine since the beginning, never drawn. They render as
pips above each hero now — **yours by name, theirs as a count only**.

That distinction is made in the SNAPSHOT, not in the board. Both clients hold
the whole game state in lockstep, so this client could read the opponent's
secrets; the snapshot is the boundary where that must not happen, and the board
can only draw what it is given. A test walks the whole snapshot recursively and
asserts the opponent's secret card id appears nowhere in it.

### The desync the mulligan uncovered

The AI-versus-AI soak test started failing at turn 17 with two clients whose
state hashes matched right up until one of them attacked something the other
could not find: `their action was illegal here (ATTACK): unknown combatant`.

**Instance ids were allocated from ONE GLOBAL COUNTER.** Two games in a single
Lua state therefore shared it — the second game's entities advanced a counter
the first was still using, so a token summoned on one side got a different id
from the same token on the other. State hashes do not include ids, so both
clients looked perfectly synchronised until one of them *named* something.

Ids are per-game now (`Entity.NewIdSource`, one per `Game.New`). Two separate
WoW clients would not have shown this, because each has its own counter — but
the practice-then-duel path in a single client would have, and so would anything
that ever holds two games at once (a replay, a spectator view). The mulligan did
not cause it; it changed the shuffle, which changed which cards were drawn,
which is what finally made a token collide.

**The soak test earned its keep again.** This is the third bug it has found that
nothing hand-written would have thought to look for.

### Mutation testing

20 mutations. Five survived the first pass and every one was a test that could
not see what it claimed to:

* the apply-order test shuffled a deck of **thirty identical Wisps**, so two
  different shuffles produced identical-looking decks;
* the phase-in-the-hash test was really observing the turn number changing;
* nothing asserted the Coin cannot be thrown back;
* nothing asserted the AI mulligans when asked to take a turn;
* and the "indices are sorted" mutation survived **honestly** — `ApplyMulligan`
  builds a set from the list, so the order genuinely cannot change the game. The
  comment claiming it prevented a desync was wrong and has been corrected: the
  sort buys a stable action log, which is worth one line, and nothing more.

## 8.19 "If available" battlecries are aimed by the player too

Written 2026-09-25. Ironforge Rifleman, Elven Archer, Shattered Sun Cleric,
Abusive Sergeant, Houndmaster, Big Game Hunter, The Black Knight, Ironbeak Owl,
Fire Elemental, Windspeaker, Crazed Alchemist and the Brewmasters: every card
printed with `REQ_TARGET_IF_AVAILABLE` was played by a human with no prompt,
and its battlecry did nothing. The practice bot aimed them correctly.

### Why

`Targeting.NeedsTarget` answers "must this card have a target to be played at
all?", which is only true for `REQ_TARGET_TO_PLAY` (and a live Combo). The
controller asked that question alone, so an optional target was never asked
for. The AI had its own private `wantsTarget` that got it right.

`Targeting.WantsTarget` now returns `"required"`, `"optional"` or nil, and the
controller and the AI both call it. When anything is legal the player MUST aim;
when nothing is, the minion is simply played. `Game:PlayCard` now also refuses
an illegal target on these cards, so the rule holds for anything arriving over
the wire, not only for the prompt.

### The board

The drop was the second half of the bug. Dropping a minion that then asked for
a target fired the slot under the pointer as the target (often your own
minion) and then cancelled whatever was left, so a prompt could never survive a
drop. A minion drop is now a PLACE only: the minion stands in its slot at full
strength, its card leaves the hand, the arrow comes out of it, and a
right-click puts it back. Nothing is committed until the target is clicked.

The opponent sees the arrow leave that slot. The hover protocol gained a source
code `s<n>`: a minion being placed into slot n. Only the slot travels, because
the card is still in a hidden hand. An older client drops the message as
malformed, which just means no arrow for that hover.

`handNeedsTarget` in the snapshot still means REQUIRED: the board uses it to
decide whether a spell is aimed while dragged, and a minion never is.
