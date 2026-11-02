# Patch Pin & Data Provenance

> ## ⚠ SUPERSEDED 2026-09-19 — now pinned to build 7234
>
> The project was re-pinned to **build 7234** (Basic + Classic + Naxxramas +
> Goblins vs Gnomes) when the expansions were added. That build carries the
> GvG-era balance patch: Starving Buzzard (5 mana 3/2), Leeroy Jenkins (5),
> Gadgetzan Auctioneer (6), Soulfire (1), Flare (2), and Adrenaline Rush is
> removed. Signed off deliberately — see
> [04-EXPANSIONS-AND-DROPS.md](04-EXPANSIONS-AND-DROPS.md).
>
> `tests/test_pin.lua` asserts all of the above, so the pin cannot drift
> silently. Builds 4944 and 5834 remain vendored for auditing.
>
> The analysis below is the ORIGINAL 5834-vs-4944 decision. It is retained
> because the reasoning — choosing a date is not rebalancing — is what justified
> accepting the GvG nerfs too.

## Decision: build 1.0.0.5834 — the last pre-Naxxramas build

**Pinned constant:** `ns.PATCH_BUILD = 5834`, `ns.PATCH_LABEL = "1.0.0.5834 (last pre-Naxxramas)"`
declared in `ForeverHearthstone/Data/PrintedCards.lua` (generated).

### Why this is not a coin flip

You offered "March 2014 launch" or "pre-Naxxramas mid-2014". I diffed every
build between them rather than guessing. The authoritative build list comes
from `HearthSim/hsdata` git tags; the 2014-era builds are:

```
4944 4973 5170 5314 5435 5506 5834 | 6024 6141 6187 6284 6485 6898
^launch (2014-03-11)          last ^ | ^ NAXX card data appears
```

Diffing the collectible CORE+EXPERT1 pool across that chain:

| transition | cards added | field changes |
|---|---|---|
| 4944 -> 4973 | 0 | 0 |
| 4973 -> 5170 | 0 | 0 |
| 5170 -> 5314 | 0 | **1** — `Unleash the Hounds` cost 2 -> 3 |
| 5314 -> 5435 | 0 | 0 |
| 5435 -> 5506 | 0 | 0 |
| 5506 -> 5834 | 0 | 0 |
| 5834 -> 6024 | **+30 (NAXX)** | 6 (text rewording only) |

**The entire difference between your two options is one card's mana cost.**
Launch and last-pre-Naxx are otherwise byte-identical in card content.

So the choice is: is Unleash the Hounds 2 mana or 3 mana?

**Recommendation: 3 mana (build 5834).** Reasoning — at 2 mana, Unleash the
Hounds + Starving Buzzard is an unbounded draw engine; it is the single most
degenerate interaction in the launch set and Blizzard patched it 6 weeks in.
Choosing a patch where it is already 3 is **selecting a date, not
rebalancing** — which is exactly the decision you delegated. 5834 also gives
you the terminal, most-tested state of the vanilla-only meta while the card
pool remains identical to launch.

If you want literal launch-day fidelity instead, change one line:
`SRC = ".../cards.4944.enUS.json"` and `BUILD = 4944` in `tools/import_cards.py`.
Both builds are vendored. Nothing else in the codebase changes.

> Text rewordings in 6024 (e.g. Ancestral Spirit's templating) are cosmetic
> only and are NOT adopted — 5834 text is authoritative.

## Source availability — verified 2026-09-19

HearthstoneJSON is **live** and still serves 2014 builds:

- `https://api.hearthstonejson.com/v1/5834/enUS/cards.json` -> HTTP 200, 203,623 bytes
- `https://api.hearthstonejson.com/v1/4944/enUS/cards.json` -> HTTP 200, 203,625 bytes

### ⚠ Supply risk — acted on

The public tree index at `/v1/` lists only **86 builds, none from 2014**. The
2014 builds are *served but unlisted*. They work today; they are undocumented
and could be pruned without notice.

**Mitigation already applied:** both builds are vendored in-repo at
`tools/vendor/` with `SHA256SUMS`. The importer reads the local snapshot and
never hits the network. Verify integrity with:

```bash
cd tools/vendor && sha256sum -c SHA256SUMS
```

Backup source if the API ever disappears: `github.com/HearthSim/hsdata`
(tag `5834`, `CardDefs.xml`) — 326 build tags, same upstream data.

## What the pinned data actually contains

Pool after removing the 9 HERO portraits (which carry `set=CORE` but are not
deck cards):

| | Basic (CORE) | Classic (EXPERT1) | total |
|---|---|---|---|
| per class | 10 | 15 (Rogue 16) | 25 (Rogue 26) |
| all 9 classes | 90 | 136 | 226 |
| neutral | 43 | 110 | **153** |
| **total** | **133** | **246** | **379** |

Plus: 9 hero portraits (exactly the nine vanilla WoW classes — 1:1 confirmed),
14 hero powers, 298 non-collectible tokens/enchantments needed as summon and
transform targets.

Rarity: 168 COMMON, 81 RARE, 68 FREE, 38 EPIC, 33 LEGENDARY.
Races: 24 BEAST, 11 DEMON, 9 DRAGON, 8 MURLOC, 6 PIRATE, 2 TOTEM.

### Hearthstone's own dust values (baseline for deviation 7 retuning)

`dust = [craft, craftGolden, disenchant, disenchantGolden]`

| rarity | craft | craft golden | DE | DE golden |
|---|---|---|---|---|
| COMMON | 40 | 400 | 5 | 50 |
| RARE | 100 | 800 | 20 | 100 |
| EPIC | 400 | 1600 | 100 | 400 |
| LEGENDARY | 1600 | 3200 | 400 | 1600 |
| FREE / Basic | — | — | — | — |

**The 142 Basic-set cards carry no dust array at all** — in Hearthstone they
can neither be crafted nor disenchanted. This aligns exactly with deviation 1
(class cards from levelling): Basic = levelling reward, Classic = packs/drops
/crafting. Preserved as-is; see the open questions in docs/02-OPEN-QUESTIONS.md.

## Provenance rule

`ForeverHearthstone/Data/PrintedCards.lua` is **generated**. It carries the
source sha256 in its header. Never hand-edit it. If a stat looks wrong, the
fix is to the importer or the pin — never to the output. This is the
mechanical guarantee that no card stat is ever "remembered" into the project.
