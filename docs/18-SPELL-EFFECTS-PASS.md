# 18. Spell effects pass

Written 2026-09-24 (first numbered 16, alongside the art check; renumbered 18). `./run-tests.sh`: 992 suites, 0 failures. Three new
textures (`fx-ring`, `fx-streak`, `fx-spark`) -- **restart WoW** once for
them; everything else is Lua.

docs/12 gave spells their own effects: eight kinds (bolt, missiles, sweep,
rain, nova, bloom, glow, summon) in eight schools, 85 spells mapped by hand.
This pass fills out the rest of the pool, gives effects new shapes and motion,
and fixes three faults the old effects had.

| Report | Cause | Fix |
|---|---|---|
| Effects aimed at a hero vanish (Fireball to the face, Holy Light on your hero, Armor Up!) | Spell sprites and particles were drawn at the board's own frame level, under the hero portraits and hero powers (`FURNITURE_LEVEL`) | A spell layer (`Board.spellLayer`, `SPELL_LEVEL` = furniture + 10) holds every sprite and particle: above the portraits and their secret pips, still under a hovered or dragged card |
| Heavy spells never shook the table | `Choreography.PlaySpell` shakes on `opts.heavy`, which the Director never sets; the SpellFX spec's `heavy` was drawn as a larger sprite only | `SpellFX.Impact(spec)` decides how a blow lands: heavy spells ring out (a shockwave `fx-ring`) and shake the board **the moment they arrive**, big ones (Pyroblast, Lava Burst, Demonheart) harder |
| Spell visuals still consumed `math.random` | The board drew sprite placement from its own generator (so a volley of Arcane Missiles could not change the next practice game's shuffle), but particle bursts, trails and the shake's jitter used `math.random` | Every board visual (`W.Burst`, `W.TickShake`, burn embers, shatter) draws from the board's `fxRandom`. `tests/test_ui.lua` casts seven effects and checks `math.random` is never called |
| Every spell's sparks moved alike | One gravity and one glow texture for every burst | `SpellFX.MOTION`: fire embers rise, frost glitter falls, holy and arcane motes are sparkles (`fx-spark`), shadow smoke swells as it fades, lightning is fast and brief. Non-spell bursts (impacts, dust, packs) are unchanged |

## New effect kinds

| Kind | What it draws | Spells |
|---|---|---|
| `beam` | A jagged chain of streaks to the target over a soft halo, redrawn with fresh jitter so it crackles; `count` forks to more enemies | Lightning Bolt, Forked Lightning, Crackle |
| `fan` | One blade at every enemy minion at once, each pointed along its flight | Fan of Knives |
| `slash` | `count` blade strokes across the target, each leaving a fading cut; the last lands the blow | Backstab, Eviscerate (two, crossing), Execute, Assassinate, Mortal Strike, Shield Slam, Savagery, Crush... |
| `drain` | A bolt out, then the life flowing home to the caster as golden motes | Drain Life, Siphon Soul, Sacrificial Pact |
| `swirl` | Motes circling in on the target, then a pop | Polymorph, Hex, Mind Control, Silence, Sap, Shadowstep, Naturalize... |
| `shield` | A ring closing onto the target, holding, with glints at its rim | Power Word: Shield, Hand of Protection, Armor Up!, Shield Block |
| `secret` | A spinning sigil drawn into your hero, in the class's colour (Mage purple, Hunter green, Paladin gold) | Every Secret (inferred from the rules text) |

Existing kinds improved: `glow` with `side = "self"` settles on every friendly
minion (Savage Roar, Bloodlust, Power of the Wild, Conceal); `summon` flashes
once per minion (`count`: Force of Nature 3, Feral Spirit 2); `missiles` with
`minions = true` skips the hero (Deadly Shot, Flamecannon, Sabotage, Bouncing
Blade); `bloom` adds rising sparkles; `sweep` a bright leading edge; `nova` a
shockwave ring.

Every collectible spell is now mapped by hand except Secrets, which share one
look per class; the inference for anything else learned `transform`,
`gain control`, `random enemy minion` and `your minions`.

## Files

- `Client/FX/SpellFX.lua` -- the mapping, `Impact`, `MOTION`, `SECRET_SCHOOL`
- `Client/UI/Board.lua` -- the spell layer; sprites gain `shape`, `rot`,
  `spin`, `orient`, `flicker` and `alpha`; the new kinds
- `Client/UI/Widgets.lua` -- `W.Burst` reads `SpellFX.MOTION`; particles
  carry their own gravity and growth
- `tools/build_spell_fx.py` -- generates `Art/fx-ring.tga`,
  `Art/fx-streak.tga`, `Art/fx-spark.tga` (white, tinted per school in the
  client) and `Art/spell-fx-report.json`

## Follow-up (2026-09-25): spells launch from the hero

Every spell effect now starts at its caster's **hero portrait**, as in
Hearthstone, instead of at the played card while it was still rising and
burning away (`casterRect` in `Board:SpellEffect`). The opponent's spells
leave the opponent's hero. The one exception is a **Secret**: its sigil still
starts at the played card, since the Secret is the card itself going up into
the portrait. Hero powers already started at the hero.
