# 26. The practice bot, reworked: it plays like a player, brings real decks, and has a difficulty slider

Written 2026-09-25. `luajit tests/run.lua`: 1050 suites, 0 failures.

**Lua only: `/reload` is enough.** No new media.

## What was asked

> Rework the bots so they play much more like real players (not healing and buffing my units, and using combos for their decks). A difficulty slider that affects their decks, with around seven decks per class from vanilla, Naxx and GvG, played at the difficulty their strength suits.

## Why the old bot healed and buffed your minions

`AI.pickTarget` aimed every targeted card at "the biggest enemy, else your own side". A heal or a buff with no damaged minion of its own to aim at took the first branch, and **the biggest enemy was yours**. No rule of thumb fixes that for four hundred cards, so the new bot does not use any.

## How it decides now: it tries things

`Client/AI.lua` was rewritten from scratch.

* **Every candidate move is played on a copy of the game** (`Game:Clone`, new in `Engine/Game.lua`), through the same rules and card scripts, and the position that results is scored. Healing your minion makes your board better, so it scores badly and never happens. Cold Blood then an attack being lethal shows up as a win. The bot knows nothing about any card; the engine does, and the bot asks it.
* **Whole turns, not single moves.** A beam search keeps the most promising partial turns at each step and extends them, so combos whose first step looks bad on its own (the Coin, Savage Roar, Power Overwhelming, Auchenai plus a heal) are found. The best position at *any* depth wins, including "end the turn now", so it only acts when acting helps.
* **Lethal first.** A narrow search that cares only about your health and its ready damage runs before the main one. Its answer is taken only if it actually wins.
* **"What do they do back?"** (Adept and up.) The strongest few turns are played forward through a model of your attacks (good trades, else face, else the Taunt) and judged on what is left. This is what stops it leaving minions to be traded off, and makes it drop a Taunt when you have lethal on board.
* **The evaluation** (`AI.Evaluate`) counts minions by stats, balance and keywords, with text priced by what the card gave up for it. Health is worth more the less there is. It also counts cards in hand, mana crystals on both sides (so Arcane Golem's drawback counts), and danger: whether your board could kill it next turn, Taunts included.
* **It holds its removal.** A minion in hand is worth little, because its value is on the board. A spell is worth more, in proportion to its cost, so a Fireball waits for a Yeti rather than a Wisp. How tightly it holds is the deck's style: aggro burn goes face.

### It plays fair

The copies it plans on are fogged:

* its own deck is reshuffled, so it can't know its next draw;
* the random stream is reseeded, so it can't foresee how Arcane Missiles lands;
* your secrets are removed, so it attacks into Explosive Trap like anyone would.

It never draws from the real game's random stream or id counter, so a networked opponent planning on its own client can't desync a match. `tests/test_ai.lua` asserts both (`thinking never changes the real game`, `it cannot see your secrets`).

A turn is planned once and played step by step. Each step records the fingerprint the game should have before it. The moment the real game disagrees (a draw, a random roll, your secret firing), the bot drops the rest of the plan and thinks again from where it really is.

### It does not freeze the game

`Main:BotDecide` runs the decision in a coroutine that yields every `AI_THINK_SLICE` (12) simulated moves, resumed a frame at a time, so the board keeps animating while a Master thinks. In interpreter-mode LuaJIT (the closest stand-in for WoW's Lua), Master's decisions average 25 ms. The worst case is about 0.6 s, which is spread across frames. Most steps are instant: they just play out the stored plan.

## The decks (`Client/BotDecks.lua`)

There are 63 decks, 7 per class: one each at tiers 1, 2 and 5, and two each at tiers 3 and 4. Every deck is checked against the pinned data for thirty cards, the copy limits, class legality and collectibility (`bot decks: every one is a legal Hearthstone deck`).

| Class | Tier 1 | Tier 2 | Tier 3 | Tier 4 | Tier 5 |
|---|---|---|---|---|---|
| Druid | Basic Druid | Budget Token Druid | Ramp Druid, Mech Druid | Token Druid, Midrange Druid | Combo Druid |
| Hunter | Basic Hunter | Budget Face Hunter | Beast Hunter, Undertaker Hunter | Midrange Hunter, Hybrid Hunter | Face Hunter |
| Mage | Basic Mage | Budget Tempo Mage | Budget Mech Mage, Classic Tempo Mage | Freeze Mage, Mech Mage | Tempo Mage |
| Paladin | Basic Paladin | Budget Aggro Paladin | Budget Midrange Paladin, Classic Control Paladin | Aggro Paladin, Midrange Paladin | Control Paladin |
| Priest | Basic Priest | Budget Priest | Velen Burst Priest, Classic Control Priest | Naxx Control Priest, Shadow Madness Priest | Control Priest |
| Rogue | Basic Rogue | Pirate Rogue | Mech Rogue, Deathrattle Rogue | Miracle Rogue, Tempo Rogue | Oil Rogue |
| Shaman | Basic Shaman | Budget Totem Shaman | Mech Shaman, Classic Midrange Shaman | Doomhammer Aggro, Naxx Midrange Shaman | Midrange Shaman |
| Warlock | Basic Warlock | Budget Zoo | Naxx Zoo, Budget Handlock | Handlock, Demonlock | Zoo |
| Warrior | Basic Warrior | Budget Aggro Warrior | Budget Control Warrior, Mech Warrior | Control Warrior, Face Warrior | Legend Control Warrior |

Each deck has a **style** (aggro, midrange or control) that sets the evaluation weights, so Face Hunter races and Control Warrior values its life and the board.

## The difficulty slider

It sits on the Practice screen's stage, between the opponent and the Play button. You can click a notch, drag, or use the mouse wheel. `/fh difficulty [1-5 | name]` sets it from chat. It is saved for the account (`ForeverHearthstoneDB.botDifficulty`, default Adept), and the bot's nameplate shows it ("Expert bot"). A rematch brings back the same deck at the same difficulty.

One number sets both the **deck tier** and **how hard it thinks**:

| | Novice | Apprentice | Adept | Expert | Master |
|---|---|---|---|---|---|
| Decks | Basic | Budget | Ladder | Meta | Top meta |
| Beam width / depth | 1 / 4 | 2 / 5 | 3 / 6 | 4 / 8 | 6 / 10 |
| Moves simulated per decision (cap) | 80 | 140 | 240 | 400 | 700 |
| Samples per random move | 1 | 1 | 1 | 2 | 3 |
| Looks for lethal | 35% | 70% | always | always | always |
| Plays out your reply (top N turns) | none | none | 4 | 8 | 12 |
| Judgement wobble | ±4 | ±2 | ±0.7 | none | none |

The wobble is a mistake a new player makes: a slightly worse trade, or missing lethal. It is never large enough to make a move no player would make, such as healing your minion.

### How much stronger (`tools/bot_bench.lua`)

These are win rates on **identical decks**, with sides alternated and the same seed per pair:

| Matchup | Games | Win rate |
|---|---|---|
| Novice vs the **old bot** | 36 | 89% |
| Adept vs the old bot | 36 | 89% |
| Master vs Adept | 120 | 60% |
| Master vs Novice | 120 | 69% |

With the decks the slider actually hands out:

| Matchup | Games | Win rate |
|---|---|---|
| Master (tier 5) vs Novice (tier 1) | 40 | 88% |
| Adept (tier 3) vs Novice (tier 1) | 40 | 80% |

Hearthstone is a game of draws, so skill alone is never a sweep. The deck tier is what makes the ends of the slider feel far apart. The benchmark is a tool, not a test: statistics don't belong in a pass/fail suite.

## Engine changes

| Change | Why |
|---|---|
| `Game:Clone()` | The bot's "what if". It deep-copies the game and shares printed data and scripts (immutable). It drops the event log and presentation list, which no copy needs. Aliasing and cycles survive: an entity reached twice is copied once. About 0.26 ms per copy in interpreter mode |
| `Entity.NewIdSource` is a callable table, not a closure | A closure's counter is an upvalue, so it could not be copied, and a copy would have handed out ids from the original's counter |
| **Stealth now blocks attacks** (`Game:LegalAttackTargets`) | Found by the bot swinging at a Worgen Infiltrator. Spells always respected Stealth; attacks didn't, for you or the bot. A stealthed Taunt also no longer taunts: Stealth wins, as in Hearthstone. There are two new suites in `tests/test_rules.lua` |

## Also found

* **Optional battlecry targets.** Cards like Ironforge Rifleman, Shattered Sun Cleric and Abusive Sergeant have `REQ_TARGET_IF_AVAILABLE`, which `Targeting.NeedsTarget` does not report. The old bot therefore never aimed them. The new bot enumerates their legal targets itself (`a targeted battlecry is aimed, not wasted`). **This is confirmed for players too, and not fixed here.** The player's own `Controller:BeginPlay` also asks only `NeedsTarget`. Headless, playing Ironforge Rifleman through the controller with an enemy Wisp on the board gives no target prompt, and the battlecry fizzles. The fix belongs in the play and targeting flow: prompt when a legal target exists, and play untargeted when none does.

## Tests

`tests/test_ai.lua` was rewritten. It covers:

* spends its mana
* free trade over face
* goes face
* can't pass a Taunt
* removal at the biggest threat
* **never heals or buffs your minions**
* heals and buffs its own
* **combo lethal (Savage Roar)**
* Fireball the Taunt, then swing for lethal
* holds Fireball rather than spend it on a Wisp
* aggro burn goes face
* pings its own Wisp to make room on a full board
* Choose One
* aims optional battlecries
* a bounded turn
* thinking never changes the real game (hash, RNG, ids; same answer twice)
* can't see your secrets
* the clone is independent
* all 63 decks legal
* difficulty picks the tier
* soaks: 12 Basic matches, **every bot deck plays a full match** (32 matches), and the Windfury swing-count soak

The soaks search lightly, since they are about card scripts, not play quality. `tests/test_collectionui.lua` adds a slider test through the real UI: wheel, notch click, saved setting, tier-5 deck, style, library contents, nameplate and rematch. The suite takes about 50 s (up from about 19 s), almost all of it the new 63-deck soak.

## Check in game (`/reload`)

1. **Slider:** `/fh`, then Play Bots. The stage shows "Difficulty: Adept" with five notches. Click, drag and wheel it. `/fh difficulty` reports the same value.
2. **Decks:** at Master, a Warrior opponent plays Control Warrior cards (Shield Slam, Brawl, Grommash). At Novice, it plays Basic cards.
3. **No enemy heals or buffs:** play Priest or Paladin bots with a damaged minion of yours on the board. They never heal or bless it.
4. **Combos:** Druid at Expert or Master with Force of Nature plus Savage Roar, and Priest with Auchenai plus a heal, go for it when it is lethal.
5. **Thinking:** at Master, the board and rope keep animating while the bot decides. Some steps take a second or so, most are instant.
6. **Stealth:** you can't attack a stealthed Worgen Infiltrator, and a Concealed Taunt doesn't block your attacks.
