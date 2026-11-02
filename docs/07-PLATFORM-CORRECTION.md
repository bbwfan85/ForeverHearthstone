# 7. Platform Correction — Forever is Mainline, not Classic

**Recorded 2026-09-19. This corrects a foundational assumption carried since the
project brief.**

The brief said "Classic-era addon API: Lua + XML frames" and "Classic API, not
retail." I took that as given and did not verify it. **It is wrong**, and I should
have checked it in the same session I verified HearthstoneJSON rather than
carrying it for the whole build.

---

## 7.1 What Forever actually is

| | |
|---|---|
| UI architecture | **Mainline**, not Classic |
| `WOW_PROJECT_ID` | `WOW_PROJECT_MAINLINE` |
| API set | the vast majority of **12.1.5** (Midnight-era) |
| Interface version | 16001 |
| Namespaces | 269 `C_*` |
| Has | Edit Mode, Cooldown Manager, the modern UI stack |
| Beta build | 1.60.1.69893, opened 2026-09-17 |
| **Port from** | **Retail code, not Classic code** |

Midnight's **Addon Disarmament** changes are active in Forever.

Sources: [forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) (a
captured API baseline from the live beta),
[classicwow.gg/forever](https://classicwow.gg/forever),
[Patch 12.0.0 API changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes),
[Blizzard: Combat Philosophy and Addon Disarmament](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight),
[Icy Veins: restrictions eased](https://www.icy-veins.com/wow/news/combat-addon-restrictions-eased-in-midnight/).

---

## 7.2 What this costs us: nothing in the engine

**The engine is entirely unaffected.** 2,923 lines of game logic, plus 808 lines
of asset resolution and choreography, import **zero WoW APIs** — a rule adopted
purely so the code could be tested headless.

That decision, made for testability, turns out to have insulated ~3,700 lines and
176 test suites from a wrong platform assumption. The cost of the mistake is
confined to the layer that has not been written yet, plus some corrections to
design notes.

**Lua 5.1 is confirmed** for Midnight retail (a subset of the 5.1 spec), so the
language target never changed and the `goto` fix in `Aura.lua` was correct.

---

## 7.3 What actually changes

### 🔴 Drop detection — the design was wrong, and the fix is BETTER

The brief specified `COMBAT_LOG_EVENT_UNFILTERED` parsing, extracting NPC IDs
from GUIDs. In Midnight:

> "COMBAT_LOG_EVENT and COMBAT_LOG_EVENT_UNFILTERED will error when trying to
> register them."

That would have killed the entire collection loop. But 12.0.0 **added standalone
death events** that are exactly what we need and strictly better than combat-log
parsing:

| event | use |
|---|---|
| `UNIT_DIED` | a unit died |
| `PLAYER_TARGET_DIED` | **solo kill credit, handed to us directly** |
| `PARTY_KILL` | **group kill credit — solves "did I contribute?" for free** |
| `ENCOUNTER_STATE_CHANGED` | boss kills → the Naxxramas card source |

The old plan required parsing a combat log line, extracting a GUID, splitting the
NPC ID out of it, and then separately proving the player contributed damage.
`PLAYER_TARGET_DIED` and `PARTY_KILL` give kill credit as a first-class event.
The "handling group kills fairly" problem from the brief largely dissolves.

`COMBAT_LOG_EVENT_INTERNAL_UNFILTERED` exists as the replacement if raw log
access is ever needed, and the restriction was **eased to apply only during boss
encounters and Mythic+** — which is precisely where `ENCOUNTER_STATE_CHANGED` is
the right tool anyway.

### 🟡 Emotes — my flagged uncertainty is now answered

I flagged "whether `DoEmote` is callable from addon code" as unverifiable.
It is answered: **`DoEmote` is deprecated; use `C_ChatInfo.PerformEmote`.**

The emote feature stands, with a corrected call. The rate-limiting and
spam-avoidance design is unchanged.

### 🟡 Right-click "Challenge to Hearthstone"

Mainline uses `Menu.ModifyMenu` (11.0+), **not** the Classic
`UnitPopupButtons` / `UnitPopupShown` tables. This was already flagged as
version-fragile; now it has a definite target.

### 🟢 Networking — survives, still needs beta confirmation

`C_ChatInfo.SendAddonMessage` and `RegisterAddonMessagePrefix` have **no
documented changes** in 12.0.0 or 12.1.0. The lockstep design and the
determinism guarantees behind it are intact. Still on the list to confirm against
the live beta, including whether the 255-byte limit and rate limiting are
unchanged.

### 🟢 Secret Values / Addon Disarmament — does not affect us

Midnight makes combat state (auras, cooldowns, unit info) "secret": displayable
but not readable by addon logic. **We never read combat state.** The minigame's
entire state is our own, held in our own tables. A self-contained card game is
close to the ideal shape for the post-disarmament API.

> **Correction, 2026-11-01.** It does affect us, at the edges. Kill rewards
> (Client/Rewards.lua) and duel proximity read unit info -- GUIDs,
> classification, tap state, names -- and inside instances those come back
> secret. Indexing a table with one, or comparing it, is a Lua error: the
> "small error when in instances" players reported after 1.0.0. Every such read
> now goes through `ns.Plain`, which treats a secret as no answer;
> tests/test_rewards.lua models secrets with `Stub.Secret()`.

Likewise **secure snippets are broken** in Forever (`loadstring_untainted` is
missing, so `WrapScript` / `RunAttribute` / `_onstate-*` all fail). We need none
of it — that machinery is for secure action bars.

### 🔴 Removed Classic globals to avoid

`GetItemInfo`, `GetSpellInfo`, `UnitAura`, `GetTalentInfo`,
`GetMerchantItemInfo`, `CombatLogGetCurrentEventInfo`. Any tutorial or snippet
written for Classic will reference these. The compat layer must not.

> ⚠ Conflict to resolve on the beta: the 12.0.0 wiki says
> `CombatLogGetCurrentEventInfo` "remains available"; forever-addon-kit lists it
> as gone. Unresolved. We do not need it either way.

### 🟡 Assets — the BLP/PoT answers need revisiting

Section 6 answered texture questions against Classic assumptions. On a Midnight
client there is a modern texture/atlas system (`C_Texture`, atlas APIs,
`SetAtlas`). The **zero-art default tier gets easier**, not harder: Mainline has a
far richer set of built-in atlas elements to compose card frames and glows from
than Classic does. The guaranteed floor in `Resolver.lua` is unchanged and still
correct.

---

## 7.4 Testing: I under-claimed what is possible

I said "I cannot test WoW UI code." That was too pessimistic, and the Mainline
finding makes it more wrong, because Mainline tooling is much better than
Classic's.

### What IS verifiable without a client

**1. Static API verification — the big one.**
`wow-ui-source` ships `Interface/AddOns/Blizzard_APIDocumentationGenerated/`,
which is *machine-readable API documentation*: every function, its arguments,
their types, every event and its payload. Combined with forever-addon-kit's
captured beta baseline, that means every WoW API call in our client layer can be
checked for existence and signature **as a build step**. That is real
verification, not stubbing.

**2. A frame-stub harness.**
`CreateFrame` returning mock frames lets the UI layer *run* headless. It catches
nil-method calls, wrong event names, unregistered events, bad handler
signatures, leaked globals, and taint-adjacent mistakes — a large fraction of
real UI bugs. It cannot catch layout or appearance.

**3. What still needs the actual game:** does it look good, does it feel good,
frame-rate under load, anchoring and strata, and whether an icon path resolves.

### The thing you were pointing at

Running a **local server plus a real client** is indeed standard addon-dev
practice, and it is the honest answer to "can we simulate locally" — you get the
real API, real rendering and `/reload` iteration. It does not help *here* only
because there is no Forever client available to us: the beta is invite-gated and
we do not have access. If you get beta access, that becomes the primary loop and
everything above becomes the pre-flight check rather than the whole story.

**Revised claim:** the client layer can be *statically verified* against the real
API surface and *behaviourally smoke-tested* headless. Only the visual layer needs
the game.

---

## 7.5 What is left

### Done and verified (176 suites, 773 assertions, 0 failures)

* card effect engine, all five duration families, secrets, combat, death phases
* determinism / lockstep guarantees, commit-reveal seeding
* asset resolution with a guaranteed zero-art floor
* choreography for every visual moment, mock-stage tested
* import + compile pipeline, patch-pin canaries
* 71 effect scripts authored of 477 needed

### Immediate, caused by this correction

1. **Retarget the compat layer to Mainline / interface 16001.** No code to
   rewrite — there is no WoW-facing code yet. This is a decision, now recorded.
2. **Build the API verifier** against `Blizzard_APIDocumentationGenerated` plus
   forever-addon-kit's baseline. Do this *before* writing frames, so the UI layer
   is checked from its first line.
3. **Build the frame-stub harness** so `Client/UI/` runs headless.
4. Rewrite the drop-detection design around `PLAYER_TARGET_DIED` / `PARTY_KILL` /
   `ENCOUNTER_STATE_CHANGED`. Simpler than the original.

### Remaining feature work, roughly in build order

| # | item | notes |
|---|---|---|
| 1 | frame layer: board, hand, drag-and-drop | the first untestable-by-eye work |
| 2 | bulk-author 406 remaining effect scripts | pure data entry, pipeline ready |
| 3 | networking / lockstep transport | design done, needs beta confirmation |
| 4 | proximity + sitting gate | `Menu.ModifyMenu`, range checks |
| 5 | world-interruption state machine | death, aggro, disconnect, standing |
| 6 | drop detection + progression hooks | now much simpler |
| 7 | persistence, crash mitigation | SavedVariables flush problem |
| 8 | collection browser, deck builder, crafting | |
| 9 | pack opening UI (choreography exists) | |
| 10 | practice-mode AI + tutorial | also the solo dev loop |
| 11 | spectator view, emotes, match history | |

### Still-open design questions

* **levels 40–60** — reopened when goldens moved to mob drops (docs/03 D2)
* the per-class 11–40 card ordering table (utility-first, not rarity-first)
* whether to duck WoW's music (I recommend not; needs your call if yes)
* the four flagged fidelity uncertainties needing a replay to settle

---

## 7.6 The lesson worth keeping

I verified the card data exhaustively and took the platform on faith. The
asymmetry was not deliberate and it should not have survived this long.

What saved it was an architectural rule adopted for a different reason: **no WoW
API outside `Client/`**. Because the engine could not reach the platform, the
platform being wrong cost nothing. That rule is now load-bearing for more than
testability and should not be relaxed.
