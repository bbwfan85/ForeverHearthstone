# 5. Timed Enchantments (the Duration System)

Status: **all five families implemented and verified.** 135 test suites,
578 assertions, 0 failures. 19 mutations confirmed caught. 24 cards authored.

---

## 5.1 What the data actually demanded

My earlier gap note said this was "~7 'this turn only' buffs". Grepping the
pinned pool for `this turn|until your next turn` returned **57 rows**, and they
are not one mechanism — they are five. All five are now implemented:

| family | mechanism | cards | status |
|---|---|---|---|
| **timed entity buffs** | stat/keyword enchantment with an expiry | 15 | ✅ §5.2–5.5 |
| timed mana | `tempMana`, cleared each turn | 3 (Coin, Innervate, Gallywix's Coin) | ✅ already worked |
| timed **cost** modifiers | `player.costMods` + `Game:CardCost` | 4 | ✅ §5.6 |
| timed damage clamps | `player.damageClamps` + `PRE_DAMAGE` floor | 2 | ✅ §5.7 |
| scheduled actions | `game.scheduled` deferred queue | 3 | ✅ §5.8 |

All five now share **one timing rule** — `Game:TimedExpired` — so entity
enchantments, cost modifiers, damage clamps and schedules cannot drift apart.

## 5.2 Design: a fifth stat layer

Timed buffs are **not** stored in the permanent `ench` layer with a note to
subtract later. They get their own layer, rebuilt from a list:

```
  e.timedEnch = { {atk=,hp=,keywords=,expiry=,turn=,controller=}, ... }
  e.timed     = { atk=, hp=, cost= }   -- REBUILT from that list, never mutated
  e.timedKeywords = { ... }            -- likewise
```

Two decisions carry the whole design:

**It is a list, not a slot.** Timed buffs stack and expire independently. Two
Abusive Sergeants on one minion is +4 Attack this turn, from two entries with
separate schedules. The original `tempEnch` single-slot placeholder silently
dropped the first buff — a mutation test confirms the list is load-bearing.

**The layer is rebuilt from zero**, exactly like auras. This is the same
reasoning that made the aura layer immune to orphaned buffs: removing an
enchantment by subtracting what you *think* you added is how minions end up
permanently buffed. `Entity:RecalcTimed()` sums the list; `Entity:ExpireTimed()`
filters it and re-sums.

## 5.3 The two duration classes

```lua
ns.DURATION.END_OF_TURN              -- "this turn"
ns.DURATION.START_OF_YOUR_NEXT_TURN  -- "until your next turn"
```

**`END_OF_TURN`** expires when the *current* turn ends, whoever's turn that is.
It needs no knowledge of ownership. Swept in `Game:EndTurn`, after `TURN_END`
triggers have had their say.

**`START_OF_YOUR_NEXT_TURN`** must survive the opponent's entire turn — that is
the whole point of Conceal, which protects your minions while the opponent is
choosing attacks — and drop when the applier's next turn begins. Swept in
`Game:BeginTurn`, *before* the turn's events, so the player sees the board they
are about to act on.

The predicate is:

```lua
x.expiry == START_OF_YOUR_NEXT_TURN
  and x.controller == player        -- only the applier's own turn counts
  and (x.turn or 0) < self.turn     -- never on the turn it was applied
```

Applied on turn T by player P, P's next `BeginTurn` is turn T+2, and the
opponent's intervening `BeginTurn` is skipped by the controller test.

## 5.4 Interactions, all tested

| interaction | behaviour |
|---|---|
| Silence | removes timed buffs — they are enchantments too |
| Bounce to hand | `ResetToPrinted` strips them; a buff must not return with the card |
| Transform | discarded; a polymorphed minion is a different card |
| Auras | independent layers, so they stack (`1 base + 1 aura + 3 timed = 5`) |
| Permanent buffs | independent, so only the timed part expires |
| Negative values | supported and used — Shrinkmeister is `-2` this turn, floored at 0 |
| Expiring **health** buff | can kill, same rule as Silence, and dies **immediately** at expiry rather than at the next drain |

That last one is the subtle one. `Game:ExpireTimed` runs a death phase itself.
Without it the death still happens — incidentally, on the next `Drain` — leaving
a corpse on the board in between, visible to anything that reads it. A mutation
test now pins this.

## 5.5 Authoring

The DSL takes duration-suffixed variants of the existing verbs, so there are no
new primitives:

```csv
CS2_045,spell,,,"BuffTurn(target, 3, 0)",,Rockbiter Weapon
CS2_011,spell,,,"BuffTurn(friendly.char, 2, 0)",,Savage Roar - characters, hero included
CS2_046,spell,,,"BuffTurn(friendly.minion, 3, 0)",,Bloodlust - minions only
GVG_011,battlecry,,,"BuffTurn(target, -2, 0)",,Shrinkmeister - negative
EX1_549,spell,,,"BuffTurn(target, 2, 0, immune)",,Bestial Wrath - +2 and Immune
EX1_128,spell,,,"KeywordNextTurn(friendly.minion, stealth)",,Conceal
CS2_005,spell,,,"BuffTurn(friendly.hero, 2, 0); GainArmor(friendly.hero, 2)",,Claw
```

`BuffTurn` / `BuffNextTurn` / `KeywordTurn` / `KeywordNextTurn` all compile to
the same `Buff` and `GiveKeyword` ops with a `duration` field. Claw shows the
pattern for mixed cards: the attack is timed, the armor is permanent, two ops in
one row.

### The 15 cards authored

Rockbiter Weapon, Savage Roar, Bloodlust, Heroic Strike, Claw, Bite, Seal of
Light, Bestial Wrath, Abusive Sergeant, Dark Iron Dwarf, Shrinkmeister, Mana
Addict, Conceal, Finicky Cloakfield, Shapeshift (Druid hero power).

Notable: **Savage Roar buffs `friendly.char`** (minions *and* hero) while
**Bloodlust buffs `friendly.minion`** (no hero). Hearthstone distinguishes
"characters" from "minions" and so does the selector language; a test asserts
both, because conflating them is an easy and invisible error.

---

## 5.6 Timed cost modifiers

`player.costMods`, read by `Game:CardCost`. Four cards:

| card | modifier |
|---|---|
| Preparation | self, SPELL, `-3`, **1 charge**, this turn |
| Kirin Tor Mage | self, SECRET, `setTo 0`, **1 charge**, this turn |
| Loatheb | **enemy**, SPELL, `+5`, unlimited, until your next turn |
| Millhouse Manastorm | **enemy**, SPELL, `setTo 0`, unlimited, until your next turn |

Three design points:

**A modifier affecting the opponent is stored on the OPPONENT's list.** So
`Game:CardCost` only ever reads one list, with no side logic. Its `controller`
field still names the caster, because that is whose "next turn" the expiry means.

**"Next turn" reuses `START_OF_YOUR_NEXT_TURN` exactly.** Loatheb cast on my turn
T is live through the opponent's turn T+1 and expires when my turn T+2 begins —
which is precisely the window in which only the opponent casts spells. No third
duration class was needed.

**`setTo` then delta.** A Loatheb-taxed free secret costs `0 + 5 = 5`. That
ordering is a choice, not a verified Hearthstone rule; flagged, and two lines to
reverse.

`Targeting.CanPlay` uses `Game:CardCost`, not `card:Cost()` — otherwise the UI
would grey out a Preparation-discounted spell the player can actually afford.

## 5.7 Timed damage clamps

`player.damageClamps`, applied in `DealDamage` after Divine Shield and armor have
had their say.

**Commanding Shout** — "your minions can't be reduced below 1 Health this turn."
Clamps damage only: `pendingDestroy` still kills, which is the Hearthstone rule.
And it protects **minions only** — a clamp leaking onto the hero would make the
hero unkillable for a turn, a silent game-ending bug. Tested explicitly.

**Ice Block** — a secret on `PRE_DAMAGE`, gated on `PayloadFatalToMyHero`, with
`cancels` to prevent the damage and a timed `IMMUNE` keyword for the rest of the
turn. It carries a new `anyTurn` flag, because "when your hero takes fatal
damage" must also catch **self-inflicted** fatal damage on your own turn (Life
Tap at 1 health). It is the only card in the pool that needs it.

### ⚠ A real bug this surfaced: secrets were resolving too late

Wiring Ice Block exposed a fidelity bug that had been passing tests. Secrets used
to **queue** their effects, so:

* Explosive Trap could not kill an attacker before it connected — a 1-health
  attacker still got its damage in, dying later on the drain.
* Ice Block's Immune would not have stopped a *second* hit in the same action
  (Arcane Missiles can hit the hero three times).

Secrets are part of the triggering action, not a reaction behind it. `Bus:Raise`
now reveals, cancels, runs the ops and settles deaths **inline** before returning.
`tests/test_playertimed.lua` has the Wolfrider-into-Explosive-Trap regression.

## 5.8 Scheduled actions

`game.scheduled`, fired from `BeginTurn`. Three cards:

| card | schedule |
|---|---|
| Nightmare | `Buff(+5/+5)` now, `Destroy` at the start of your next turn |
| Headcrack (Combo) | return itself to hand next turn |
| Kel'Thuzad | *not* a schedule — a `TURN_END` trigger, see below |

**The context is captured, including `ctx.target` by reference.** Nightmare
destroys the minion it buffed, not whatever is targeted two turns later. A
mutation dropping the capture fails three assertions.

**Kel'Thuzad needs a turn-scoped death log, not a schedule.** `game.deathLog`
records minions as they die, in death order, and is cleared at every `BeginTurn`.
Its `TURN_END` trigger fires at the end of *each* turn — both players' — and
resummons only its controller's dead, respecting the seven-slot cap.

---

## 5.9 Previously listed as open — now closed

**Timed cost modifiers** (4 cards) — player-scoped, needs a modifier list on the
player with an expiry and a "next card of type X" consumption rule:
Preparation (EX1_145), Kirin Tor Mage (EX1_612), Millhouse Manastorm (NEW1_029),
Loatheb (FP1_030).

**Timed damage clamps** (2 cards) — needs a turn-scoped `PRE_DAMAGE` clamp:
Commanding Shout (NEW1_036, minions can't drop below 1 health this turn),
Ice Block (EX1_295, hero Immune after fatal damage is prevented).

**Scheduled actions** (3 cards) — needs a deferred-action queue keyed to a future
turn boundary: Headcrack (EX1_137, return to hand next turn), Nightmare
(DREAM_05, +5/+5 then destroy at the start of your next turn), Kel'Thuzad
(FP1_013, resummon at the end of each turn).

Kel'Thuzad also needs a "minions that died this turn" record, which is a
turn-scoped log rather than a schedule — so it is arguably a sixth family.
