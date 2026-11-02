> Current pack-only drops: kill rewards are always packs. The combined pack includes Classic, GvG and Naxxramas neutrals; class cards remain guaranteed level rewards. Base chances are normal 1.5%, elite 4%, rare 5%, repeat dungeon boss 12%. First encounter kills and raid bosses guarantee a pack. Saved bad-luck protection remains. Packs are banked automatically with toast and chat notification; level-ups print the actual grants. Historical single-card and boss-only Naxx descriptions below are superseded.

# Adding Naxxramas + Goblins vs Gnomes; Drop Rates; Emotes

> Progression update: all neutral and class Basic cards now belong to the starting collection at level 1. The 15 Classic class unlocks occur at levels 3, 5, ..., 31; the 9 Naxxramas/GvG unlocks occur at 36, 39, ..., 60. This supersedes the historical curves below. Pack milestones are unchanged. Existing cards are retained, and missing entitlements catch up on login. Settings uses the same grant schedule and excludes starter Basics from the reward track.

All numbers below read from HearthstoneJSON build **7234**, which is the first
build containing GvG and *nothing later* (no Blackrock Mountain). It is exactly
the "vanilla + Naxx + GvG" state. Verified by enumerating sets per build:

```
5834 : CORE 133  EXPERT1 246                        <- currently pinned
6024 : CORE 133  EXPERT1 246  NAXX 30
7234 : CORE 133  EXPERT1 245  NAXX 30  GVG 123      <- proposed
8416 : ... + BRM 31                                 (too far)
```

## The pool after expansion

| set | total | class | neutral | rarities |
|---|---|---|---|---|
| CORE (Basic) | 133 | 90 (10/class) | 43 | 59 FREE, 74 COMMON |
| EXPERT1 (Classic) | 245 | 135 (15/class) | 110 | 94C / 81R / 37E / 33L |
| NAXX | 30 | 9 (**1/class**) | 21 | 18C / 4R / 2E / 6L |
| GVG | 123 | 72 (**8/class**) | 51 | 40C / 37R / 26E / 20L |
| **total** | **531** | 306 | 225 | |

Plus the 4 promo/reward cards. Effect-script burden goes from 337 to roughly
**480** — a 43% increase in the data-entry job, not in the architecture.

### Keyword audit — done, and the result is very good

I enumerated every mechanic, race and play requirement the two expansions
introduce rather than estimating:

* **Zero new play requirements.** The entire `REQ_*` vocabulary is unchanged, so
  `Targeting.lua` needs no work at all for 153 new cards.
* **Only two new mechanics in 531 cards**, one card each:
  * `FORGETFUL` — Dunemaul Shaman (GVG_066), "50% chance to attack the wrong
    enemy." Needs an attack-redirect hook in `Game:Attack`.
  * `TOPDECK` — Flame Leviathan (GVG_007), "When you draw this, deal 2 damage to
    all characters." Needs `Bus:Collect` to also see the card being drawn;
    today it only scans board, hero and weapon, so this would silently never
    fire. Worth having found before authoring rather than after.
* **`MECHANICAL` race** (43 cards) — pure data, the `race` field already handles it.
* **Spare Parts works for free.** The seven Spare Part tokens are attached via
  the printed `entourage` field on 5 cards, which `Summon{fromEntourage=true}`
  and `AddCardToHand{fromEntourage=true}` already support. No new engine work.
  Six of the seven tokens are expressible with existing ops today.

**New engine work for both expansions: two hooks and one op.**

| need | cards | note |
|---|---|---|
| attack redirect (`FORGETFUL`) | 1 | new hook in `Game:Attack` |
| on-draw trigger (`TOPDECK`) | 1 | `Bus:Collect` must see drawn cards |
| swap attack/health | 2 | Reversing Switch, and vanilla's Inner Fire needs the same family — already on the gap list |
| "until your next turn" duration | 1 | Finicky Cloakfield; extends the existing "this turn only" gap |

That is a 43% increase in authoring for a ~1% increase in engine surface, which
is exactly the outcome the data-driven design was supposed to produce. It is
also the strongest evidence so far that the architecture holds.

---

## ⚠ The one real cost: re-pinning nerfs six vanilla cards

This is the collision you asked me to always flag. Adding GvG means pinning a
later build, and later builds contain the GvG-era balance patch. Diffing the
**vanilla pool only**, 5834 → 7234:

**1 card removed:** `Adrenaline Rush` (EXPERT1 drops 246 → 245)

**6 stat changes:**

| card | 5834 | 7234 |
|---|---|---|
| Starving Buzzard | 2 mana 2/1 | **5 mana 3/2** |
| Leeroy Jenkins | 4 mana | 5 mana |
| Gadgetzan Auctioneer | 5 mana | 6 mana |
| Soulfire | 0 mana | 1 mana |
| Flare | 1 mana | 2 mana |

(24 further text changes are rewording only.)

Note what the Buzzard nerf is *for*: Starving Buzzard + Unleash the Hounds was
the unbounded draw engine. It is the same interaction that drove your original
patch choice — we picked 5834 over 4944 because Unleash was already 3 mana
there. The Buzzard half of that combo was nerfed later, in exactly this patch.

So the two internally-consistent options are:

**A. Re-pin to 7234.** Authentic: this is a state Hearthstone actually shipped,
and the nerfs exist *because* those cards were degenerate alongside expansion
cards. Consistent with the reasoning that picked 5834.

**B. Frankenstein.** Keep 5834's vanilla stats, bolt Naxx/GvG cards on top.
Costs nothing in fidelity to the *vanilla* set but produces a patch state that
never existed, with pre-nerf Buzzard next to GvG's card-draw support.

I recommend **A**, on the same logic you already accepted: choosing a date is
not rebalancing. Asked in chat — I'm not deciding this one.

---

## 🎁 The expansions solve the levels 40–60 gap

Decision D2 (goldens drop from mobs) reopened the question of what fills 40–60.
The expansion class-card counts answer it exactly, and symmetrically — every
class gets the same shape:

| levels | grant | per class | rate |
|---|---|---|---|
| 1 | 43 neutral Basic granted + first class cards | — | starter deck ready |
| 2–10 | Basic class cards | 10 | ~1/level |
| 11–40 | Classic class cards | 15 | 1 per 2 levels |
| **41–60** | **Naxx (1) + GvG (8)** | **9** | **1 per ~2 levels** |
| | **total** | **34** | |

That is real gameplay content filling 40–60 rather than cosmetics, and the
cadence stays at roughly one card every two levels the whole way from 11 to 60.
It is a much better answer than the card-backs-and-pack-rate filler I proposed.

---

## Pack choice on opening

You want the drop to be openable as your choice of Classic / Naxx / GvG. Under
decision D4 (packs award neutrals only) the pools are:

| pack | neutral pool | notes |
|---|---|---|
| Classic | 110 | the deep one, correct default |
| GvG | 51 | |
| Naxx | **21** | too shallow to be a pack |

**Recommendation: make Naxx boss-drop-only rather than a pack type.** Three
reasons: 21 neutrals is a pack you exhaust in a couple of dozen opens; Naxx was
never a card pack in Hearthstone (it was an adventure — you beat bosses for
cards); and "Naxxramas cards come from killing dungeon and raid bosses" is a
far better fit for a WoW addon than a third pack icon. It also gives your 5%
boss rate a distinct purpose instead of just being a better mob.

So: **two pack types (Classic, GvG) + Naxx cards from bosses.** If you'd rather
have three packs, it works — it's just a shallower third pool.

---

## Drop rates — your numbers, checked against the collection size

> **Superseded by docs/13 (2026-09-24).** The estimate below ignored that a
> fifth of drops are single cards and that packs repeat cards; simulated on the
> real code, completing the pool at 1% takes ~53k kills, not ~14k. Rates are
> now normal 1.5% / elite 4% / dungeon boss 12% (first kills and raid bosses
> guaranteed), plus starter and milestone packs.

Your proposal: 1% per mob, 5% per boss, critters excluded.

**Neutral completion target** (Basic is granted, class cards come from levelling,
so packs only ever need to fill neutrals):

```
  neutral non-Basic distinct : 182   (41 legendary)
  copies needed (2x, 1x leg) : 323
  packs @ 5 cards            : 65 minimum, ~142 realistic with duplicates
```

**At 1% per mob → 100 mobs per pack → ~14,200 mobs for a full neutral set.**

That lands well. A vanilla 1–60 involves somewhere in the region of 10–15k mob
kills, so **1% completes the neutral collection at roughly the same time you hit
60**. Completion arriving with max level is a genuinely good curve — I'd keep 1%.

Suggested full table:

| target | rate | rationale |
|---|---|---|
| normal mob | **1%** | your number; ~100 kills/pack |
| elite | 3% | rarer, tougher, worth stopping for |
| dungeon/raid boss | 5% | your number; **also the Naxx card source** |
| rare spawn | 5% + set-trigger roll | the chase-card hook |
| critter | **0%** | correct — trivial HP, infinite farm |
| totems / pets / summons | **0%** | or Shamans drop-farm their own totems |
| **grey (no XP) mobs** | **0%** | see below |

**The one addition I'd insist on: gate on the mob granting XP.** A flat 1% on
any non-critter means the optimal farm is a level-60 character cleaving level-12
mobs in Westfall, which is faster per kill than anything level-appropriate.
Requiring the kill to award XP kills that strategy with a rule players already
understand, and needs no arbitrary level-difference maths. At level 60, where
nothing grants XP any more, switch the gate to "mob level ≥ 55" so endgame play
still drops packs.

**Rested-area bonus** (you asked for `IsResting()` to matter): rather than a
higher drop rate — which would make people farm *inside* inns, where there are
no mobs — make it a **pack-opening bonus**: opening a pack while resting adds a
guaranteed rare floor, or a small dust bonus. That rewards hauling your packs
back to an inn and opening them by the fire with someone, which is the social
moment you're designing for. Duelling while rested can carry the same bonus.

> **Removed 2026-09-26** (your call): packs now open exactly as Hearthstone's
> do, one rare-or-better guaranteed whether or not you are resting, and no
> rested dust. The rested pack-drop flourish went with it.

---

## Emotes as real in-world WoW emotes

This is a lovely idea and it's the single cheapest thing on the list that makes
the addon feel native. Hearthstone's six map onto vanilla emotes almost exactly:

| Hearthstone | WoW emote | notes |
|---|---|---|
| Greetings | `/hello` | `/greet` also works |
| Well Played | `/congratulate` | |
| Thanks | `/thank` | |
| Wow | `/surprised` | `/gasp` is an alternative |
| Oops | `/apologize` | `/sorry` is an alias |
| Threaten | `/threaten` | exists in vanilla, exact match |

All six exist in the vanilla emote set, `/threaten` included — which is a nicer
coincidence than it deserves to be.

**Squelch** stays purely local: suppress rendering the opponent's emote in your
UI. It cannot suppress the world emote text, because that is real chat other
players can see — worth being explicit about in the UI so squelch doesn't feel
broken.

Two caveats, both flagged rather than solved:

1. **`DoEmote` callability is unverified.** It exists in the Classic API, but
   whether an addon may call it without a hardware event, and whether Forever
   restricts it, I cannot confirm without beta access. This goes behind the
   compat layer with a fallback to addon-local emote bubbles, so the feature
   degrades instead of breaking.
2. **Emote spam is real chat.** Six buttons wired to world emotes next to a
   nearby player is a griefing vector and an annoyance to bystanders. Rate-limit
   to roughly one emote per 3 seconds per player, and drop the world emote (keep
   the in-UI bubble) when the duel isn't in a rested area.

---

## What this changes in the build plan

* **Re-pin + re-import.** Mechanical: change two constants in
  `tools/import_cards.py`, re-run, re-run the compiler. The 37 authored scripts
  survive; the coverage denominator grows.
* **Effect authoring grows ~337 → ~480 rows.** The pipeline absorbs this; audit
  GvG keywords against the op library first.
* **Engine: no changes expected.** Mechs are a race (data). Spare Parts are
  generated cards (data + existing ops). To be confirmed by the keyword audit.
* **The 6 nerfed cards and Adrenaline Rush** are the only fidelity cost, and
  only under option A.
