# 45. The bot ladder, deck codes and opening many packs at once

Written 2026-11-22.

**Needs a full WoW restart** (new art: `rank-medal*.tga`, `rank-star*.tga`). After that, Lua changes need only `/reload`.

## What was asked

> 1. Change "Play Bots" to "Play Bot Ladder" and have it simulate climbing the ladder like Hearthstone, gaining stars under the actual rules. Higher ranks should bring better decks, played better. Players should show the rank they've earned along with their portraits and W/L.
> 2. Import and export decks, using Hearthstone's standard if one exists. Show which cards you're missing, and offer to craft them if you have the dust.
> 3. Open more packs at a time, following Hearthstone if it has a bulk opening, otherwise 5 at a time.

## Research (hearthstone.wiki.gg, hearthsim.info, read 2026-11-22)

* **Ladder:** `wiki/Ranked/2013-2020` describes the classic system as it stood before the April 2020 Leagues revamp. It is implemented in its final form:
  * The rank names run from 25 Angry Chicken to 1 Innkeeper, then Legend.
  * Ranks 25-16 hold 3 stars, 15-11 hold 4, and 10-1 hold 5 (Feb 2019).
  * A win following two wins in a row earns a bonus star, below rank 5. A bonus earned at rank 6 can carry you into rank 5.
  * Losses do not cost stars at ranks 25-21. A loss at 0 stars drops you a rank, one star short of that rank's full.
  * The milestones at 20, 15, 10 and 5 are floors for the season, and Legend is kept for the season.
  * A new season puts you 4 ranks below your best standing, stars included. Anyone who has ever reached rank 15 never resets below 20.
  * The new-player ranks 50-26 (2018) are left out, because this is the 2014 game.
* **Deck codes:** HearthSim's deckstring spec is Hearthstone's own format: base64 of varints, holding a reserved 0, version 1, the format, the hero DBF ids, then the 1-copy, 2-copy and n-copy card lists sorted by DBF id. Hearthstone ignores `#` lines, except that `### Name` names the deck.
* **Bulk opening:** Patch 27.6 (October 2023) added "open multiple packs at once", up to 40 normal packs. "The amount of packs purchased at once does not in any way affect the contents." Hearthstone has a bulk opening, so it is used instead of a 5-at-a-time system.

## 1. Play Bot Ladder (`Client/Ladder.lua`)

The menu plaque now reads **Play Bot Ladder**. The Play screen has Hearthstone's **Ranked | Casual** pair over the stage. The choice is saved for the account in `ForeverHearthstoneDB.botCasual`, and Ranked is the default.

* **Ranked** opens straight on your decks, because the ladder picks your opponent. The stage shows your **rank medal**: the rank's minion in a gold setting with the number on a ribbon and its stars beneath. Legend's medal has orange points. Below the medal are the rank name and your season record. Play finds an opponent within a rank of yours, of any class.
* **Casual** is the old practice mode: pick an opponent, then a difficulty and a deck. It keeps its own record ("Casual" on the main menu).
* **After a ranked game** the result says what it cost or earned. Examples: "Rank 14: star 3 of 4", "Win streak! Bonus star", "Rank 15 holds: a milestone", "You reached Legend!". The season record follows. **Play again** finds a new ladder opponent.
* **An unfinished ranked game** counts as a loss when another game is started over it, as leaving a ranked game does in Hearthstone. Conceding is a loss as usual.
* **The record** is saved per character, in `ForeverHearthstoneCharDB.ladder`. Seasons are calendar months. `/fh ladder` prints your standing. `/fh casual` and `/fh ladder` open the Play screen in either mode.

### Better decks, played better, the higher you climb

A ladder bot's rank sets a continuous **skill**, `Ladder.Skill`. Rank 25 is 1.0, a Novice with a Basic deck. Rank 1 is 5.0, a Master with a top deck. Legend runs from 5.4 to 6.0 as the legend number falls.

* **Deck:** the tier is the skill rounded up or down by its fraction. Rank 12 (skill 3.17) brings a tier-3 deck most of the time and a tier-4 deck otherwise.
* **Play:** `AI.SkillProfile(skill)` blends the search settings of the two neighbouring levels (width, depth, budget, replies, lethal checks, judgement wobble). Each rank therefore plays a little better than the one below it, instead of improving in five big steps.
* **New Legend level** (`AI.LEGEND`), above Master and reached only on the ladder: beam 8, depth 12, 1000 simulated moves, and it plays out 16 of your possible replies.

`tools/bot_bench.lua` now takes skills (1-6, fractions allowed). **Measured honestly: the extra search buys almost nothing.** Legend against Master on identical tier-5 decks, seat-swapped, 120 games: **63 wins (52.5%)**, with no engine errors and every game finished. That is within noise. Master's search already finds what the evaluation (`AI.Evaluate`) can recognise, so searching wider and deeper finds the same moves. Legend, then, is Master with more thinking time, not a stronger player. A genuinely stronger top end needs a better evaluation (card-draw and tempo valuation, or reading the opponent's likely hand), which is a separate piece of work.

The climb is still real below that. docs/26 measured Master over Novice at 69% on identical decks and 88% with their own tier decks, and the ladder spreads that gap across 24 ranks.

### Does each rank play like its rank? (checked 2026-11-22)

**Not at first.** The low levels were handicapped only by a shallower search and a small wobble on the first move. A win scores 1e6 and a small board needs no depth, so the Novice (rank 25) played simple turns exactly as Master did. `tools/skill_probe.lua` (new) plays fixed puzzles at every skill, 100 times each, varying only what the bot cannot see. Before the fix, Novice found 81% of the right plays and Master 86%. The only difference was a three-card combo, plus a probe bug in the Polymorph puzzle that made every level score 0% on it.

**The fix: beginners' slips** (`AI.Slip`, profile fields `slip` and `slipTop`). With chance `slip`, a decision weighs only the next move and picks at random among the `slipTop` that look best. Ending the turn now counts as one of them. The result is a worse trade, a card left in hand, or a lethal not taken, which are real beginner mistakes. Attacks may be poor trades, but a card is played only if it does not worsen the bot's own position, so it still never heals or buffs your minions (tested). The slip chance falls from 40% at rank 25, through 22% / 8% / 2%, to none at Master and Legend, and blends by rank like everything else. (Retuned in "Difficulty curve review" below: Master now slips too, and only Legend never does.)

Puzzles after the fix (`luajit tools/skill_probe.lua 100`):

| Puzzle | r25 | r19 | r13 | r7 | r1 | Legend |
|---|---|---|---|---|---|---|
| Lethal on board, with a bait trade | 62% | 84% | 93% | 96% | 100% | 100% |
| Fireball the Taunt, swing for lethal | 81% | 97% | 99% | 100% | 100% | 100% |
| Savage Roar combo lethal | 24% | 70% | 93% | 97% | 100% | 100% |
| Use all 5 mana well | 70% | 81% | 95% | 100% | 100% | 100% |
| Take the free trade | 51% | 65% | 95% | 100% | 100% | 100% |
| Hold Fireball rather than hit a Wisp | 100% | 100% | 100% | 100% | 100% | 100% |
| Polymorph the 7/7 threat | 69% | 84% | 98% | 100% | 100% | 100% |
| **All** | **65%** | **83%** | **96%** | **99%** | **100%** | **100%** |

Whole games on **identical** tier-3 decks, seat-swapped (`tools/bot_bench.lua`, 80 games each):

| Matchup | Before | After |
|---|---|---|
| Master over Novice | 70% (60 games) | **85%** |
| Adept over Novice | 62% | **81%** |
| Master over Adept | 55% | **61%** |

On the ladder the decks widen the gap further: rank 25 brings Basic decks and rank 1 top decks. docs/26 measured 88% for Master+tier 5 over Novice+tier 1 before the slips.

**Limits that remain.** The puzzles cannot tell Master, Legend and Expert apart: all three are perfect on them. In games, Legend is no stronger than Master (52.5%, above). The top end is capped by the evaluation, not the search. A Novice never wastes removal on a Wisp, because its slips never play a card that worsens its position, so it can still be too tidy in that one respect.

### Difficulty curve review (2026-11-22)

Two questions: can Legend be made genuinely stronger than Master, and does strength rise in even steps from rank 25 to Legend?

**How it was measured.** `tools/bot_bench.lua` gained options: a mulligan for both sides (on by default, as in a real game), `vary=1` (any deck of the tier, not only each class's first), `tierA`/`tierB` (each side brings its own tier), `real=1` (the deck the ladder really deals: a random deck of the tier, made a player's copy for that side's skill by `BotDecks.Personalize`), `log=1` (every move printed), and an `extraB` argument like `extraA`. Every number below is seat-swapped: both games of a pair use the same decks and seed. Runs were 16 processes in parallel, added up. 224 games carry about ±3.3 points of standard error, and 448 games about ±2.4.

**What Master gets wrong.** Master-against-Master games with every move logged showed these mistakes:

* **It passed with a full hand when every line lost.** A Druid at 1 health, with 10 mana and Force of Nature, Savage Roar and Harrison Jones in hand, ended its turn doing nothing. The opponent's board was lethal whatever it did, so the reply check scored every turn as a loss, and "end the turn" won the tie. **Fixed for every level that checks replies** (Adept and up, and not just from Expert, because no level should pass like that): when every candidate loses to the reply, the board-minded pick stands.
* **Its reply model traded when it had lethal.** The model of your swing-back took any worthwhile trade before going face, so a turn that left the bot dead on board could look survivable. This is now `replyLethal`, set from Expert up: when your board can kill, every swing goes face, with the smallest attackers into any Taunt. It is correct, but it changed only one game pair in 224, because the danger term in `AI.Evaluate` already catches most such boards.
* **It chose lines on a lucky sample.** A random move is scored as the average of its samples, but the line continues from one of them. Legend's wider search was more likely to find a line whose sample happened to be lucky. For example, it played Unleash the Hounds before Glaivezooka and lost two bodies that Master's order kept. A correction for this sampling luck was tried. It made no measurable difference, so it was removed.
* **It spent removal on damage that did not kill.** Examples were Swipe on a 2/8 Deathlord and Wrath on Vol'jin. The evaluation counts minion health linearly. This was not changed, because no evaluation change measured as stronger (below).

**Legend against Master, before any curve change** (clean Master, identical tier-5 decks, 224 games each unless noted). Each idea is a switch on Legend's profile:

| Legend variant | Won | % |
|---|---|---|
| Legend as shipped (two runs) | 232/448 | 51.8% |
| `replySearch=0.5`: your whole turn searched from the fog (Basic-card prior for your hand) | 117 | 52.2% |
| `replySearch=1`, top 6 candidates, 80 moves each | 119 | 53.1% |
| `lookahead=0.4`: its own next swing after your reply | 116 | 51.8% |
| Every search node scored after your reply | 117 | 52.2% |
| Class sweep risk: Consecration, Flamestrike and the like, by your class, mana and hand size | 112 | 50.0% |
| Hero-power reach in the danger term | 117 | 52.2% |
| `samples=6` | 121, then 113 on fresh seeds | 52.0% (448) |
| Common random numbers / sampling-luck correction | 118 / 117 | 52.7% / 52.2% |
| Style weights: face ×1.3 / face ×0.8 / cards ×1.3 | 116 / 117 / 110 | 51.8% / 52.2% / 49.1% |

None of these is distinguishable from 50%. Diagnostics show why. On tier-5 decks a clean Master beat Expert 52.7%, Adept 55.4%, a Master with no reply check 50.9%, and a Master that **undervalued your minions by 40%** 48.7%, against Novice 84.8% (224 games each). Between bots that do not blunder, the decks and the draw decide the game. About 80% of seat-swapped pairs split one game each whatever the pilots do. Evaluation and search quality above Adept barely shows. **The 58% target for a genuinely cleverer Legend was not reached.** The best honest result was 53.1% (`replySearch=1`, 224 games), which is noise. `replySearch`, `lookahead` and `replyPower` remain in `Client/AI.lua` as switches, off by default. The other ideas were removed.

**What does move games: mistakes.** Every level below Legend makes visible, human mistakes: slips (`slip`, `slipTop`), judgement wobble (`noise`), and sometimes not looking for lethal (`lethal`). The curve was retuned so these shrink evenly all the way to Legend:

| Level | slip | slipTop | noise | lethal | was (slip / slipTop / noise / lethal) |
|---|---|---|---|---|---|
| Novice (rank 25) | 0.36 | 4 | 3.5 | 0.45 | 0.40 / 4 / 4.0 / 0.35 |
| Apprentice | 0.26 | 4 | 2.4 | 0.65 | 0.22 / 3 / 2.0 / 0.70 |
| Adept | 0.20 | 3 | 1.6 | 0.80 | 0.08 / 2 / 0.7 / 1 |
| Expert | 0.13 | 3 | 0.9 | 0.90 | 0.02 / 2 / 0 / 1 |
| Master (rank 1) | 0.06 | 3 | 0.35 | 1 | 0 / 1 / 0 / 1 |
| Legend | 0 | 1 | 0 | 1 | unchanged |

Search settings are unchanged. `Ladder.Skill` is unchanged too: rank 25 is 1.0, rank 1 is 5.0, and Legend runs from 5.4 to 6.0. Changing it would also have moved deck tiers and `BotDecks.Personalize`. Master now slips about one decision in sixteen, to its second- or third-best next move. It is still the best slider level, and the slider's Expert and Master are now measurably different (before, 52.7%).

**The curve: each band's middle against the band below**, at the skills `Ladder.Skill` gives ranks 23, 18, 13, 8 and 3, and 5.7 for Legend. Identical tier-3 decks, `vary=1`:

| Step | Before (224) | After (448) |
|---|---|---|
| 20-16 over 25-21 (2.17 vs 1.33) | 149/224, 66.5% | 264/448, **58.9%** |
| 15-11 over 20-16 (3.0 vs 2.17) | 151/224, 67.4% | 271/448, **60.5%** |
| 10-6 over 15-11 (3.83 vs 3.0) | 116/224, 51.8% | 245/448, **54.7%** |
| 5-1 over 10-6 (4.67 vs 3.83) | 125/224, 55.8% | 253/448, **56.5%** |
| Legend over 5-1 (5.7 vs 4.67) | about 50% (Legend played as Master) | 246/448, **54.9%** |
| Legend over Master, tier-5 decks | 232/448, 51.8% | 251/448, **56.0%** |
| Master over Novice, tier 3 | 85% (80 games, old bench) | 182/224, 81.3% |

Before, the climb was two cliffs at the bottom (66-67%) and flat from rank 10 up. After, every step is between 54.7% and 60.5%, so it rises steadily. Legend's edge over Master now comes from Master's remaining slips, not from extra search. On tier-5 decks every gap shrinks further: an earlier tuning, with Master slipping 3% of the time, measured Legend over 5-1 at 49% there.

Ladder-realistic spot checks (`real=1`, each side its own tier's player-copy deck, 224 games):

| Matchup | Result |
|---|---|
| Rank 18 (tier 2) over rank 23 (tier 1) | 167/224, 74.6% |
| Rank 8 (tier 4) over rank 13 (tier 3) | 122/224, 54.5% |
| Legend (tier 5, owns everything) over rank 3 (its own tier-5 copy) | 136/224, 60.7% |

The step from Basic to budget decks is the biggest single jump on the real ladder. Matchmaking pairs ranks within one of each other, though, so no single game spans it.

**Puzzles** (`luajit tools/skill_probe.lua 100`) now separate the top as well: **70% / 79% / 85% / 91% / 96% / 100%** for Novice, Apprentice, Adept, Expert, Master and Legend. Before, the scores were 65 / 83 / 96 / 99 / 100 / 100. Rank 25 still misses about a third of easy plays, including about two-thirds of Savage Roar lethals. It now finds lethal on board slightly more often than before.

**Cost.** First-decision time at each turn start, `luajit -joff`, over 12 tier-5 games (277 decisions): Master averages 0.06-0.11 s with a worst case of 0.81 s, and Legend averages 0.09-0.16 s with a worst case of 1.22 s. Legend's worst case is 1.5× Master's, within the 2× budget. Nothing new costs time at the defaults: `replyLethal` is a few comparisons.

**Tests.** New tests cover three behaviours. A bot facing unavoidable lethal still plays its cards (Expert, Master and Legend). The reply model goes face for lethal, and Expert and up expect it. The skill profile's mistakes shrink and its thinking grows monotonically from 1 to 6. Two expectations changed. Master's slip is now small but not zero. Three decision tests ("finds a combo for lethal", "a targeted battlecry is aimed", "cannot see your secrets") now run at Legend, because they test what the search finds, and Adept and Master now slip on purpose.

### Ranks on the nameplates

Both players' nameplates in a match now carry a **rank medal** at the end of the tag, next to the portrait, level and W/L.

* **Your rank** is shown in bot games and in duels.
* **A ladder bot** shows its rank and reads "Ladder bot".
* **In a duel**, each player's rank travels in two new trailing fields of HELLO and PROFILE. A 1.1.0 client ignores them and sends none, so **no protocol bump** was needed. Its player simply shows no medal. `Session.ReadRank` rejects anything that is not a whole number from 0 to 25.

The main menu's record card gains a third line: **Ladder: Rank 14** (or "Legend 812").

### Who you meet: names and decks

**Names** (`Client/BotNames.lua`). A ladder opponent goes by a player-like handle in its class's flavour, styled by rank band:

* **25-16:** playful handles with numbers (Pyrokid42, xAxex, MurlocLover7).
* **15-6:** a root and a title (FrostWarden, ShadeRunner).
* **5-1:** one crafted word (Frostbinder, Nightvein).
* **Legend:** short tags (Vael, Kroth), ten per class.

Its class is shown under the name. Every name is invented; none is a real player's or a well-known WoW character's. The low bands combine 10 roots with 8 styles and a number per class, so names rarely repeat.

**Decks** (`tools/bot-decks-extra.txt` -> `tools/build_bot_decks.py` -> `Client/BotDecksExtra.lua`). There were 63 decks, with only **one** per class at tiers 1, 2 and 5, so rank 25 and rank 1 always met the same list. 72 new lists, written by card name and checked by the build, bring it to **135: at least three per class at every tier**.

* **Tier 1:** Basic cards only, in aggro, midrange and control builds.
* **Tier 2:** budget lists with no legendaries.
* **Tiers 3-5:** lists from the Naxx/GvG era (Mech Mage, Gahz'rilla Hunter, Lightbomb Priest, Mal'Ganis Handlock, Ysera Control Warrior, and others).

The build fails on any unknown name, wrong count, copy limit, wrong class, a non-Basic card in tier 1 or a legendary in tier 2. `run-tests.sh` runs it on every build.

**A player's copy, not the list** (`BotDecks.Personalize`, used by every ranked game). Real ladder players copy a list and fill its holes with what they own, or slot in the legendary they just opened. Every ranked bot does the same:

* **Missing cards.** Each copy of a rare, epic or legendary is owned with a chance that rises with skill. At rank 25 that is 50% / 20% / 8%; at rank 1 it is 100% / 95% / 90%; Legend owns everything. A copy it does not own becomes a common or Basic card of the same type at the nearest cost.
* **Netdecking up.** Below rank 1, 30% of bots bring a list from one tier above their rank. The holes above apply to it, so a rank-23 bot can bring Freeze Mage with Flamestrike and Polymorph where Blizzard and Pyroblast should be.
* **The pet legendary.** A random legendary replaces one card, 40% of the time at rank 25 and 5% at rank 1.
* **Tech.** From Expert up, half the time one flexible card becomes a tech card (Ooze, Owl, Big Game Hunter, Harrison Jones, Loatheb, Kezan Mystic, Spellbreaker, Doomsayer).

Every copy is checked legal across all 135 lists and four skills (`tests/test_ladder.lua`). The test also checks that a rank-25 copy of a meta list carries well under 60% of the Legend copy's epics and legendaries. Casual (the slider) still brings the exact lists.

## 2. Deck codes (`Client/DeckCode.lua`, `Data/DbfIds.lua`)

* **Export:** the deck editor has a **Copy Deck Code** plaque. It opens the code in a box with the text already selected, so **Ctrl+C** copies it (WoW gives addons no clipboard). The text is Hearthstone's own: `### Name`, `# Class:`, `# Format: Wild`, the card lines by cost, then the code. It pastes into Hearthstone (these are Legacy cards, so Wild), into deck sites, or into another player's Import Deck. The box resists edits, so the code cannot be corrupted before it is copied.
* **Import:** My Decks has **Import Deck** next to New Deck. Paste with **Ctrl+V**, either the whole copied text or just the code, then press Import. Then:
  * A deck of another class is refused, naming both classes.
  * Otherwise the dialog lists the **missing cards**: count, name and crafting cost, or why a card cannot be crafted (a Basic card is unlocked by levelling, a card may belong to another class, or it may be unobtainable). It also gives the total.
  * **Craft & Save (N)** crafts every missing card and saves the whole deck. It is enabled only when every missing card is craftable and your dust covers all of them. Otherwise, pressing it says why.
  * **Save Owned** saves the copies you have. The deck builder shows the deck as unfinished, like any deck you have not completed.
* **Modern codes:** Hearthstone reprinted these cards under new ids (Core and Classic-format copies). A reprint with the same name and class imports as the 2014 card, so a Classic-format code copied from today's client works. Cards from later sets are counted as "from later sets" and left out.
* **DBF ids** come from Blizzard's CardDefs.xml in python-hearthstone's `hearthstone_data`, which the Fireplace oracle venv already has. `tools/import_dbf_ids.py --refresh` re-extracts them into `tools/vendor/dbf-ids.json`, which is checksummed in `SHA256SUMS`. `run-tests.sh` regenerates `Data/DbfIds.lua` from that file on every run, so normal builds do not need the venv.
* **Checked against python-hearthstone's own encoder.** The test vectors in `tests/test_ladder.lua` were written by `hearthstone.deckstrings`, including the spec's example.

## 3. Opening many packs (`Packs.OpenMany`)

With two or more packs waiting, the pack room shows an **Open N** plaque beside the stack, with **-** and **+** either side. The mouse wheel also changes N, and Shift steps by 5. N runs from 2 to the smaller of your packs and 40, and starts at 10.

* **Contents:** each pack opens exactly as a single pack does: the same odds, the guaranteed rare, and duplicates auto-dusted.
* **Results:** every card is shown at once, **best first**: legendaries, then epics, rares and commons. Golden cards come before plain ones, and **NEW** cards before ones you already had. Each kind appears once, with "x2" when more came. A card whose copies all became dust is greyed with "+N Dust" on it. A summary under the title counts each rarity, goldens and dust. Results take several pages when needed (arrows or wheel). Right-click any card to read it, and press **Done** to return to the room.
* **NEW** is new on every pack card (`card.new`): the first copy of a card you had never owned.

## Files

| File | What |
|---|---|
| `Client/Ladder.lua` (new) | rules, seasons, matchmaking, skill |
| `Client/DeckCode.lua` (new) | deckstring encode/decode, missing-card plan, craft, save |
| `Data/DbfIds.lua` (new, generated) | card and hero DBF ids, reprint aliases |
| `Client/AI.lua` | `AI.LEGEND`, `AI.SkillProfile`, `Profile` takes `skill`; difficulty curve retuned, `replyLethal`, reply fallback, `replySearch` switch |
| `Client/Packs.lua` | `Packs.OpenMany`, `Packs.SortBulk`, `card.new` |
| `Client/Main.lua` | ladder state, StartLadder, results, Ranked/Casual Play screen, profiles, `/fh ladder` |
| `Client/UI/Widgets.lua` | `W.RankMedal` |
| `Client/UI/Board.lua` | medal on each nameplate |
| `Client/UI/Collection.lua` | deck-code dialog, Import Deck, Copy Deck Code, bulk opening |
| `Client/Net/Session.lua` | rank in HELLO/PROFILE trailing fields, `Session.ReadRank` |
| `tools/import_dbf_ids.py`, `tools/build_rank_art.py` (new) | data and art |
| `tests/test_ladder.lua` (new), `tests/test_collectionui.lua` | 22 new suites |
| `FHTour/Tour.lua` | new scenes: ladder-*, deck-code-*, pack-bulk-*, ranked-* |

### Owner's call: Master plays its best (2026-11-23)

The review gave Master a deliberate slip (0.06, with noise 0.35) to separate it from Expert. The owner chose instead that **Master plays as well as possible**: `slip = 0` and `noise = 0`, the same as Legend. Expert and below keep their slips. The cost of that choice: from Expert up the bots are close in strength again. The review measured clean Master at only 52.7% against Expert on tier-5 decks, and Legend and Master are again within noise of each other. At the top of the ladder the difference comes mainly from the deck tier and from `BotDecks.Personalize`: Legend owns every card, and rank 1 still misses some epics and legendaries.

