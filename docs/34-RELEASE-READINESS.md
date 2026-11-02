# Release readiness — 2026-09-26

This pass improves the working tree; it does not approve a release. Nothing was
pushed or published. The starting tree was clean. Reward rates, grants, crafting
costs and duplicate rules were not changed.

## Run and replay

From the repository root, with LuaJIT (Lua 5.1) and Python with Pillow installed:

```text
python tools/validate_readiness.py
```

LuaJIT is discovered on PATH or at its Windows installer location. Override with
`--lua PATH`. If Pillow is in another Python installation, use
`--render-python PATH`. For example, using a Python installation with the rendering dependencies:

```powershell
python tools/validate_readiness.py --render-python '<python-with-rendering-dependencies>'
```

The runner checks vendored checksums, regenerates printed data/effects using the
existing tools, runs compiler and all Lua regressions, runs isolated duels and
five bot matchup batches, exports actual UI-stub regions, and renders eight PNGs.
It continues after a failed stage and exits nonzero if any stage failed. Each
subprocess has a 20-minute limit. `--seeds 10` extends deterministic fault matches
across all five difficulties; the default is two seeds, difficulties 1 and 2.
`--skip-visuals` is a reduced run, not the full gate.

Results are in `dist/readiness/report.json`, with exact argv replay commands,
exit codes and wall times. Each duel has a seed, difficulty, CPU time, action
count, Lua memory sample and timestamped send/receive/drop/event/action trace.
Failed duels additionally save canonical client states. Example:

```text
luajit tools/duel_lab.lua 1 disconnect 1 dist/readiness/replay.log
```

Replay requires the same code revision; traces are diagnostics, not a portable
cross-version replay format. The network scheduler is deterministic. The clients
have independent globals, addon namespaces, engine classes, sessions, transports
and AI caches. Only the message API is replaced. Main/UI/privacy are tested by
the existing full-addon stub suites, not by this two-client harness. The harness
does not claim two operating-system processes or actual WoW clients.

## Reproduced findings and fixes

| Finding | Change and regression |
|---|---|
| Both directions lost heartbeats; ordered resend requests waited behind missing packets and eventually aborted both clients | NAK uses sequence zero and bypasses the ordered inbox; transport treats it as essential traffic. Bilateral disconnect regression plus complete fault matches. Protocol **8** rejects older peers. |
| Bot planning retained the opponent's real hand/deck, allowing copy effects to inspect hidden cards; simulated RNG also depended on the actual stream | Planning replaces unknown cards with a public Basic-deck prior, clears secret identities, canonicalizes its own deck before shuffling, and uses an independent simulation seed. Hidden-card/stream regression plus existing tactical and full-deck suites. Difficulty search budgets/styles remain distinct. |
| Stopping transport retained volatile input and retry delay | Stop clears reliable/volatile queues, retry state and peer. Regression proves no stale send to a replacement peer. |
| Prefix registration treated every numeric result as success | Normalize legacy booleans and current success/duplicate/error enum values; test both shapes. |
| Bot benchmark printed engine errors but exited successfully, and counted unfinished games like draws | Engine errors and unfinished matches now fail the benchmark. |

Honest failures during development: the first loss injector matched `ACTION`
instead of wire kind `AC`; it was fixed and now asserts that a loss occurred.
The first full run found bilateral-loss failures and a missing Pillow dependency.
The original disconnect trace is retained locally as
`dist/readiness/original-disconnect-failure.log`. The bundled rendering runtime
resolved Pillow without installing software. No failing result was counted as a pass.

## What the offline gate covers

| Area | Exercised | Limits |
|---|---|---|
| Two clients | Challenge/accept, nonempty mulligan, bot matches, deterministic latency/reordering, duplicate delivery, lost action, bilateral interruption, fresh session reload/rejoin, pause/refusal/resume, concession, incompatible-version rejection | API delivery, real throttling and two-process isolation remain live checks. Disconnect is a ten-second symmetric outage; not every possible outage schedule. |
| State | Canonical recursive engine graph after every settled action, plus session state and engine errors | Code/metatables are not serialized. Production wire hash remains narrower than this offline comparison. |
| Privacy/proximity/timers | Existing transport, table, net and Main suites exercise blocking/unblocking, challenge policies, range freshness/instance mismatch, turn expiry and claims | The integrated duel lab does not load Main or exercise real movement. |
| UI | Existing main/menu/collection/deck/pack/board navigation, close/minimap and animation tests; added 30 repeated menu/collection/deck/pack-room/Settings cycles at 800x600/.7, 1920x1080/1, 2560x1440/1.25 | Stub scale calls are not real pixel transforms or hit testing. The added matrix uses methods as well as entry-point clicks; not an exhaustive UI route graph. |
| Card interactions | Existing summons, battlecry/deathrattle, silence, transforms, control, buffs/heals/shields/secrets, trigger and presentation suites; added both sides × capacities 0–7 × every insertion slot, IDs/reindex and exactly-one deathrattle draw | This is not every cross-product of cards/effects/positions. Existing director regressions check frozen target identity and fallback cues; visual timing still needs live review. |
| Rewards | Existing economy/crafting/class restrictions/duplicates/vault/upgrade tests; added nine install levels for all nine classes, three repeated saved-table reconstructions each; 40 pack openings interrupted before presentation | Reconstruction proves in-memory banking. It cannot persist rewards after a process crash before WoW writes SavedVariables. |
| Bots | Existing lethal/combo/trade/removal/heal/buff/space/secret/resource scenarios and every authored deck; added hidden-state regression; 20 additional matches, four at each difficulty/tier | Small batch win rates do not establish difficulty ranking. Public Basic-deck estimate is deliberately approximate; not a learned opponent model. |
| Stability | Bounded action/tick budgets; no added frames/textures after navigation warmup; game CPU and retained Lua memory recorded; long matches and trigger suites | Trace retention and stub recorder allocations affect memory. No claim of leak-free WoW sessions, frame-time bounds or GPU performance. |

Eight approximate PNGs are under `dist/readiness/visuals`: menu (narrow),
collection (ultrawide), deck browser (narrow), deck editor, pack reveal
(ultrawide), board states, targeting, Settings. They use the real frame-building
code and shipped textures. The renderer approximates font metrics, anchors,
layering and masks; it cannot prove input interception, protected actions,
animation continuity, audio or the target renderer. All eight previews were
visually inspected; no live screenshot was captured. Review caught stale deck
editor state in the collection preview fixture; the exporter now clears it.

## Reward explanation audit

`RewardHelp`, `Collection`, `Packs`, `Drops` and reward-event tests agree on base
normal/elite/rare/boss rates (1.5/4/5/12 percent), normal/elite reward split (80%
packs, 20% cards), first-encounter/raid guarantees, level catchup and neutral
Basics. Pack generation guarantees a rare-or-better slot. Class grants are capped
by the available class pool; neutrals/packs/dust are account-level, class cards
and grant history are character-level.

The help's “long dry spell” is imprecise but not a different economy: non-boss
eligible misses add their base rate toward 225; the **next** eligible non-boss
kill pays once that floor is reached (151st normal kill after 150 misses).
A reward resets the floor; bosses do not advance it. Saved per character.
No balance changes are proposed in this pass.

Remaining API/localization risk: `Drops` uses English creature-type strings for
themed drops and some exclusions. Non-English behavior needs numeric/type data
from the actual client. Reward event order, duplicate kill credit, restricted
values and encounter payloads need captured live evidence. A successful stub
registration does not prove an event exists or has that payload on Forever.

## Opt-in live developer smoke test

Implemented in `Client/Net/DevTest.lua`, with `/fh dev ...` commands. It creates
no frames/timers/messages by default. Pairing requires an explicitly named
`Name-Realm` and a matching 6–24 character code entered on both clients. Only
that peer is addressed; strangers and mismatched codes are ignored. It uses
`FHLAB1`, separate from normal gameplay, collection and reward accounting.
Pairing times out after 60 seconds; the whole mode stops after ten minutes.
Trace is bounded to 500 entries and is memory-only. This is a scripted protocol
smoke test, not a live UI bot or a reconnect automation.

Two simulated endpoints verified pairing, automatic acceptance within the
explicit test pairing, mulligans, alternating end turns, concession and matching
final state. **No live behavior was verified.** No account login, movement or
protected-action bypass is implemented.

API investigation: the current extracted Blizzard documentation declares
`SendAddonMessage` with a result enum and disallows secret arguments; prefix
registration also returns an enum. This informed return-value handling, but is
not proof of the modified Forever target's permissions or API payloads:
[Chat API documentation](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatInfoDocumentation.lua),
[chat result enums](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/ChatConstantsDocumentation.lua).

Short live checklist (two consenting logged-in clients required):

1. Restart both clients with this tree (new TOC file), record build/interface,
   locale and UI scale, and enable Lua errors. Confirm normal login sends no
   `FHLAB1` messages. Both manually move into ordinary duel range.
2. On A: `/fh dev pair B-Realm shared123`; on B:
   `/fh dev pair A-Realm shared123`. Run `/fh dev status` on both. Expect
   `paired=true` within a few seconds; wrong code/name must not pair.
3. Run `/fh dev start` on **one** client. After roughly 30 seconds, both
   `/fh dev status` outputs must show `OVER` and the same hash. Collect both
   `/fh dev trace` outputs and the first full Lua/API error if any. A blocked
   API, timeout or unmatched result is a failed live gate, not permission to
   bypass it. Run `/fh dev stop` on both; verify outgoing test traffic stops.
4. Run one normal duel: accept, mulligan, targeted effect, timer expiry, manual
   proximity change, return, then `/reload` on one side and explicitly rejoin.
   Check block/unblock and Nobody policy. Capture both boards/action history
   before and after recovery; expect matching stats, IDs in debug evidence,
   and no unexplained result or duplicate animation.
5. At .7/1/1.25 scales, use minimap, close/back and Escape across every screen,
   interrupt pack reveal and targeting, reopen. Collect screenshots/video and
   frame-time/memory samples before/after 30 cycles. Open an owned pack, reload
   during reveal, verify exactly one spend/grant. Capture one eligible solo,
   party and encounter reward event in each supported locale.

## Prioritized release gates

| Priority | Gate | Pass/fail criterion | Status |
|---|---|---|---|
| P0 | Offline correctness | Full command exits 0; no regression, engine error, unfinished match or state divergence | Pass; final run recorded below |
| P0 | Target transport/API | Both live clients complete scripted smoke test; no forbidden-action/API errors; matching final state | Not run |
| P0 | Normal duel recovery | Live reload/rejoin and temporary interruption restore the same result without duplicate effects | Not run |
| P0 | Saved progress | Real reload mid-reveal spends/grants exactly once; catchup remains idempotent | Offline pass; live pending |
| P1 | UI/input and presentation | All listed live routes, scales and interruption cases leave correct visible screen, no invisible input blocker or wrong-entity animation | Offline partial; live pending |
| P1 | Reward event/localization | Captured target payloads show correct eligibility and deduplication in supported locales | English stub pass; live pending |
| P1 | Performance | After warmup, 30 live navigation/pack cycles show bounded widgets/handlers and no sustained memory slope; capture long-turn frame times | Offline allocation checks pass; live pending |
| P1 | Broader adversarial coverage | Mixed loss/throttle schedules and crowded chained-effect combinations preserve canonical state with replayable seeds | Combined-fault soak added; see follow-up below; exhaustive combinations remain open |
| P2 | Bot calibration | Larger paired-seat runs preserve an ordered difficulty trend, while all tactical regressions stay green | Tactical pass; 36-game endpoint comparison below; full ranking not established |
| P2 | Release package | Build a local candidate, run packaged Lua/path checks and install that exact candidate for live gates | Local candidate verification below; installation/live gates pending |

Live gates must remain open until evidence is attached. Existing unresolved card
rulings in docs/32 and oracle limitations in docs/33 are not cleared by this run.

## Recorded results

Initial full run: **29/29 stages passed**, 138.50 seconds summed wall time on this
workstation. Lua regression suite: **1,254 suites, 60,268 assertions, zero
failures**, 56.98 seconds. All 18 isolated network scenarios passed; completed
bot-driven duels took roughly 2.8–3.8 seconds each. Clean seeds used 174 and 131
actions; retained Lua memory samples (including traces and two complete addon
namespaces) were about 15.1 and 10.4 MiB, not leak measurements.

All 20 additional bot matchup games completed without engine errors; four-game
batches took 2.9/3.6/6.6/8.3/8.0 seconds for difficulties 1–5. Repeated navigation
added zero frames and zero textures after warmup. All eight offline PNGs rendered.
After visual review, only the collection preview setup was corrected; exporter
and renderer were rerun separately. No gameplay code changed after the full run.

**Verified live: none.** The P0 live gates above remain outstanding. Reports and
images in ignored `dist/readiness` are local evidence; retain them with any
future candidate release review.

## Follow-up: broader faults, packaged candidate and board hover

The combined-fault scheduler now models a three-message server burst refilled at
one message per second, plus latency/reordering, duplicates and repeated dropped
actions/heartbeats. Each match asserts that all three fault types were actually
injected and records their counts. `mixed` and `terminal-loss` are now part of
the default one-command gate.

This found an additional correctness bug at seed 5/difficulty 5: dropping the
winning attack stranded the other client because the finished sender stopped
heartbeats. A finished session now responds to a still-playing peer's heartbeat
with a later ordered PING, exposing the missing sequence to NAK recovery. Replies
are marked and rate limited so two finished peers cannot echo indefinitely.
The exact failing match and a focused lost-concession/no-echo regression pass.
Original evidence: `dist/readiness/original-terminal-loss-failure.log`.

Board-card hover now applies the same live stats as the board portrait, showing
current attack and remaining health rather than printed values. Green buffs and
red damage remain visible. An open preview refreshes by entity ID after resolved
snapshots, including reordering, transformation and control change; removal hides
it. Reusing the preview for a printed card resets the live stats. Two focused
regressions cover both players and these transitions. `board-live-hover.png`
adds a ninth offline visual showing an 8-attack, 2-health Chillwind Yeti.

The old bot benchmark changed class/deck matchups between the two games it called
a seat-swapped pair. It now holds seed and deck pair fixed, swaps pilot difficulty,
and logs each game's seed/classes/seat/result. Master beat Novice **24/36** on
tier-4 decks across 18 pairs, all completed with zero engine errors (66.2 seconds
CPU in this run). This supports a difference between the endpoints on that sample;
it does not establish all five difficulties' ranking or general win rates.

Packaging now checks exact-case TOC and texture paths, and validates its staging
path before cleanup. `tools/verify_candidate.py` compares every archive entry to
the staged bytes (including ZIP CRC validation while reading), records the ZIP's
SHA-256, then runs `tools/package_smoke.lua` against those exact packaged files.
That smoke test loads actual TOC order, verifies advertised version metadata,
opens the menu/practice/mulligan/collection/decks/pack/Settings, checks current-stat
hover and bound texture paths, and confirms developer mode remains inactive.

```text
python tools/verify_candidate.py dist/ForeverHearthstone-0.2.0-rc.readiness.2.zip
```

Candidate `.1` passed its original package smoke, but predates terminal-loss and
hover fixes and is superseded. Do not use it for release validation. Candidate `.2`
is the intended local test artifact. Neither candidate was installed or published.
The temporary approval-review usage limit prevented a prior rerun/rebuild; those
commands were not counted as executed and were retried after the user continued.

Final follow-up results: **33/33 gate stages passed**, 176.97 seconds summed wall
time (concurrent soak/package work makes this unsuitable for comparison with the
initial timing). **1,257 suites / 60,292 assertions / zero failures**. All 22
standard network scenarios and all ten extra mixed-fault seeds 3–12 passed; the
extra matches each injected 14–30 losses, 50–108 throttle refusals and 29–61
duplicates. Replayable metrics are in `dist/readiness/mixed-soak-summary.json`.
All nine offline previews rendered; the live-stat hover image was inspected.
Its fixture was then reset before capture to remove a previous scene's victory
overlay, and export/render were rerun successfully; runtime code was unchanged.

Candidate `dist/ForeverHearthstone-0.2.0-rc.readiness.2.zip` passed verification:
**3,970 files** matched the staged bytes; **46 TOC files** loaded; **1,377 bound
texture paths** existed during packaged UI smoke. The package build checked
1,030 static texture paths and parsed packaged Lua. Size is approximately 182 MB
compressed / 203 MB installed. SHA-256:

```text
9468b5eae0fb3f8178ad053117114814d9cdf8ef2d0aba11aac987d0c2c9d980
```

The candidate includes both the terminal-message recovery and current-stat hover
fixes. `dist/readiness/candidate-verification.json` and `candidate-smoke.log`
record its checks. The ZIP itself has not been installed or published.

## Live single-client smoke (2026-09-26)

Tested the user's already logged-in retail WoW client through Windows UI controls
at 3440x1440. The installed addon directory is an NTFS junction to this workspace's
`ForeverHearthstone` directory. Ran `/reload` before testing current source; this
was not a clean installation of the candidate ZIP.

- `/fh`, practice opponent/deck selection, mulligan confirmation and card dealing
  worked in the real client.
- Dragged Goldshire Footman and River Crocolisk from hand onto the board. Mana,
  summon animation, bot turns, combat and deaths visibly updated.
- Hovering the played Footman showed 1 attack / 2 health and its Taunt explanation.
- The opposing Keeper of the Grove began at 2/4 and survived combat at 2/2.
  Its enlarged board hover showed 2 attack and red 2 health, verifying damaged
  current health rather than printed base health in the actual renderer.
- Navigated through Main Menu, Collection, My Decks and Settings, then resumed
  the practice match. Inspected card art, counts, deck listing and settings text.
  No visible error dialog or missing texture appeared during these checks.

This smoke does not certify hidden Lua errors, a complete match, other UI scales,
buff/transform hover cases, live pack/reward persistence, frame-time/memory soak,
or two-client networking and recovery. No second consenting peer was available
for this run. No packs were opened and no challenges were sent. The test practice
match remains available to the user; no public release was made.
