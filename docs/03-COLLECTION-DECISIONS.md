> Current pack-only drops: kill rewards are always packs. The combined pack includes Classic, GvG and Naxxramas neutrals; class cards remain guaranteed level rewards. Base chances are normal 1.5%, elite 4%, rare 5%, repeat dungeon boss 12%. First encounter kills and raid bosses guarantee a pack. Saved bad-luck protection remains. Packs are banked automatically with toast and chat notification; level-ups print the actual grants. Historical single-card and boss-only Naxx descriptions below are superseded.

# Collection & Progression — Decisions Locked

> Progression update: all neutral and class Basic cards now belong to the starting collection at level 1. The 15 Classic class unlocks occur at levels 3, 5, ..., 31; the 9 Naxxramas/GvG unlocks occur at 36, 39, ..., 60. This supersedes the historical curves below. Pack milestones are unchanged. Existing cards are retained, and missing entitlements catch up on login. Settings uses the same grant schedule and excludes starter Basics from the reward track.

> Progression update: all neutral and class Basic cards now belong to the starting collection at level 1. The 15 Classic class unlocks occur at levels 3, 5, ..., 31; the 9 Naxxramas/GvG unlocks occur at 36, 39, ..., 60. This supersedes the historical curves below. Pack milestones are unchanged. Existing cards are retained, and missing entitlements catch up on login. Settings uses the same grant schedule and excludes starter Basics from the reward track.

Records your answers from 2026-09-19, plus the starter-deck resolution. Design
only; no implementation yet — the engine comes first.

---

## D0. Starter deck — you were right, and it needs no deviation at all

You asked: is the game playable with the cards you start with? Doesn't
Hearthstone give you a starter deck?

**Yes, and Hearthstone's mechanism is simply that the Basic set is given to you
free — it is never collected.** That is exactly why the 142 Basic cards carry no
dust value in the data: they were never part of the economy. Everything lines up:

> **The entire Basic set is granted, not collected.**
> 43 neutral Basic cards at character creation, plus your 10 class Basic cards
> on the 1–10 curve.

This is a **zero-deviation** answer — the best possible outcome for a
recreation. It also resolves C3 cleanly: Basic cards aren't craftable or
disenchantable because you already own all of them.

### Proof it's playable at level 1

The 43 neutral Basic cards give **86 deck slots** at the 2-copy limit. You need
30. And they are not filler — read as a pool they're a complete curve:

| cost | examples |
|---|---|
| 1 | Elven Archer, Goldshire Footman (Taunt), Stonetusk Boar (Charge), Murloc Raider |
| 2 | Bloodfen Raptor 3/2, Frostwolf Grunt (Taunt), Novice Engineer (draw), Kobold Geomancer (+1 spell dmg) |
| 3 | Ironfur Grizzly (Taunt), Wolfrider (Charge), Raid Leader (aura), Shattered Sun Cleric |
| 4 | Chillwind Yeti 4/5, Sen'jin Shieldmasta (Taunt), Oasis Snapjaw 2/7, Ogre Magi |
| 5 | Nightblade, Frostwolf Warlord, Darkscale Healer, Booty Bay Bodyguard |
| 6–7 | Boulderfist Ogre, Lord of the Arena, Stormwind Champion (+1/+1 aura), War Golem |

Taunt, Charge, battlecries, card draw, spell damage, and two board-wide auras.
A level-1 character can build a genuinely functional deck immediately.

---

## D1. The four promo cards — WoW-native paths *(your choice)*

All four stay in the pool as ultra-rare chase cards.

| card | acquisition |
|---|---|
| Old Murk-Eye | **Collect every Murloc card** — its real Hearthstone condition, which maps exactly onto the set-trigger system. There are 8 Murlocs in the pinned pool. |
| Elite Tauren Chieftain | rare-spawn / world-boss drop |
| Gelbin Mekkatorque | rare-spawn / world-boss drop (gnomish-themed spawns) |
| Captain's Parrot | rare-spawn drop (pirate-themed spawns) |

`unobtainable=true` will be removed from the importer for these four once the
drop tables exist.

## D2. Golden class cards drop from mobs *(your choice)*

* Normal class cards — levelling only, guaranteed.
* **Golden** class cards — drop from mobs like golden neutrals.

Golden coverage is therefore complete across all 379 cards, and goldens remain
uncraftable (deviation 3 intact).

> ⚠ **Consequence to note:** this was also the candidate answer for "what fills
> levels 40–60". Choosing mob drops means **40–60 is open again.** Non-blocking,
> but it needs an answer before the progression milestone. Candidates that don't
> touch the card pool: accelerated pack rate, exclusive card backs (your
> secondary track), tavern-board skins tied to the rested-area bonus, extra deck
> slots. I'd lean card backs + pack rate, since both already exist as systems.

## D3. Dust — Classic-only, but Basic dupes still dust *(your choice)*

* The 246 Classic cards are craftable and disenchantable at Hearthstone's values.
* The 142 Basic cards are granted free, never crafted.
* If a Basic duplicate ever reaches a player, it disenchants rather than being
  silently destroyed.

Under D0 + D4, Basic duplicates shouldn't normally occur (granted once, packs
are neutral-Classic-only), so this is a safety valve rather than an income
source. Worth keeping precisely because "silently destroyed" is the kind of
thing players notice and resent.

## D4. Levelling awards all 25 class cards; packs are neutral-only *(your choice)*

Per class: 10 Basic + 15 Classic (Rogue 16) = **25 class cards, all from
levelling.** Packs and mob drops award **neutrals exclusively**.

### The 1–40 curve

You noted unlocks needn't be every level. The counts work out cleanly:

| levels | grant | rate |
|---|---|---|
| 1 | 43 neutral Basic + first 2 class Basic | starter deck ready |
| 2–10 | remaining 8 class Basic | ~1 per level |
| 11–40 | 15 Classic class cards | **1 every 2 levels** |
| 40–60 | *open — see D2* | — |

That is exactly your "every 2 levels" suggestion, and it falls out of the card
counts rather than being imposed on them.

**Front-load rule:** the 15 Classic class cards are ordered by *deck utility*,
not by rarity or cost — cheap removal and efficient bodies land in the 11–24
band, with class legendaries (Tirion Fordring, Bloodmage Thalnos, Grommash,
Edwin VanCleef…) in the 30–40 band. This satisfies your "keep decks playable the
whole way up rather than backloading the payoff cards": a level-20 character
should have its core removal, not just vanilla minions. Exact per-class ordering
is a data table, authored the same way as the effects CSV.

## D5. Account-wide neutrals, per-character class cards *(my recommendation, no veto)*

* **Account-wide:** neutral collection, dust pool, golden status, card backs.
* **Per-character:** class cards, decks, match history.

Rationale: a character can only ever access 25 class + 153 neutral = 178 of 379
cards, so neutrals are the majority of every deck and the entire source of
deckbuilding variety. Because a WoW character is one class permanently,
per-character neutrals would force every alt to re-grind the same 153 cards
before it could build anything. The dust pool must follow the neutrals or dust
would be trapped on one character.

---

## Still open (non-blocking)

* **Levels 40–60** — reopened by D2. See the note there.
* **First-run pack** — you asked for a pack on first launch. Under D4 packs are
  neutral-only, so this is a free neutral pack on top of the granted Basic set.
  No conflict; just confirming it stacks with D0 rather than replacing it.
* Drop-rate tuning, creature-family mapping, and pack economics are section 5
  work and depend on none of the above being revisited.
