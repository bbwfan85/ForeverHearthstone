# 32. Release review before 0.1.3

Written 2026-09-26. `./run-tests.sh`: all green (1191 suites). **The engine changed, so the duel
protocol goes from 5 to 6:** a 0.1.2 player and a 0.1.3 player cannot duel each other, and the
older one is told to update. Lua and one generated data file only: `/reload` is enough.

## What was asked

> Perform a full review of the addon so it's ready for release: how it looks, the animations,
> the sounds, the rules, niche interactions, text alignment/growth/scaling, the implications.
> Then commit, push and create the new release. [17 screenshots of the menus at extreme narrow
> and wide sizes.] At the very least the rope should be thicker. The Challenges plaque cuts off
> "Friends & group".

Five read-only passes: layout against the screenshots, engine mechanics, Basic/Classic card by
card, GvG/Naxxramas card by card plus game flow, and animation/sound/assets. Every rules finding
below was reproduced against the engine before it was fixed, and each has a test in
`tests/test_release013.lua` that fails without its fix.

## Rules

### Engine mechanics

* **A bounced or shuffled minion kept a spent keyword spent.** A popped Divine Shield and a
  Stealth broken by attacking are deleted from the printed-keyword layer; `ResetToPrinted` never
  rebuilt it. An Argent Squire bounced by Youthful Brewmaster came back without its shield; a
  Worgen Infiltrator sent home by Freezing Trap came back without Stealth. Rebuilt from the card.
* **A silenced minion could never gain a keyword or trigger again.** `Entity:Has` answered only
  aura keywords once `silenced` was set, and `Bus:Collect` skipped every trigger on a silenced
  minion. So Sunfury Protector's Taunt, Conceal, Argent Protector and Blessing of Wisdom did
  nothing to it. Silence now empties the printed layer too, and the flag gates only the card's
  own script (its aura, printed Spell Damage).
* **A secret kept firing after an earlier one had stopped the action.** Counterspell then
  Spellbender summoned a Spellbender for a countered spell; Explosive Trap killing an attacker
  still spent a Freezing Trap on the corpse. Secrets stop once the action is cancelled or the
  attacker has left play.
* **Set effects cancelled auras.** Equality, Humility, Hunter's Mark, Inner Fire and Redemption
  subtracted the aura. In Hearthstone the aura applies on top: Equality under Stormwind Champion
  leaves 1/2 minions. They also override this-turn buffs now (`Entity:SetStat`).
* **Scripts attached twice.** `ResetToPrinted` attached the card's script, and so did every path
  back into play after it. A bounced Loot Hoarder, a Voidcaller's Demon and Ancestor's Call's
  minions had two deathrattles. Attaching happens only on the way into play.
* **Deaths before "after you cast a spell".** Wild Pyromancer fired before the spell's deaths:
  a Pyromancer the spell killed still fired, and the Damaged Golem from a Harvest Golem the
  spell killed was never pinged.
* **Random picks skip the dying**: Knife Juggler, Mad Bomber, Avenge, Misdirection and Sylvanas
  no longer choose a minion already at 0 Health or marked for destruction.
* **Draws.** A fatigue kill inside an effect ended the game on the spot, so Coldlight Oracle or
  Gift of Cards fatiguing both heroes to death gave a win instead of a draw. Arcane Missiles and
  Madder Bomber had the same problem per missile. Deaths wait for the end of the effect.
* **The opening hand is dealt, not drawn**: a Flame Leviathan in it burned both heroes before
  the mulligan.
* **A destroyed hero dies**: Sacrificial Pact on Lord Jaraxxus did nothing, and the leftover mark
  stopped him attacking for the rest of the game.
* Faceless Manipulator and Echoing Ooze copy whether the shield is still up, Silence, this-turn
  buffs and granted Spell Damage. The Ooze's copy stands next to the original.

### Cards

| Card | Was | Now |
|---|---|---|
| Shadowstep | returned the minion at full cost | costs (2) less |
| Screwjank Clunker, Upgraded Repair Bot | could never target (race 17, Mech, unmapped) | target a friendly Mech |
| Bolvar Fordragon | kept growing on the board | grows only in hand |
| Mimiron's Head | a full board made nothing | V-07-TR-0N arrives |
| Mal'Ganis | hero not Immune | hero Immune (`HeroImmune` property) |
| Velen's Chosen | no Spell Damage | Spell Damage +1 |
| Crush | always (7) | (3) with a damaged friendly minion |
| Call Pet, Far Sight | no discount | the drawn card costs less |
| Sabotage | combo did nothing extra | combo destroys the weapon |
| Reincarnate | doubled by Baron Rivendare | one minion back, on its controller's side |
| Feign Death | ignored Baron Rivendare | doubled by it |
| Malorne under Baron | the same card in the deck twice | once, and out of the graveyard |
| Mad Scientist | could pick an active Secret and throw it away | picks one that can go up |
| Feugen / Stalagg | a milled or burned partner counted | only one that died |
| Healing Totem, Leokk, Ysera Awakens, Dream, Deathcharger | no script at all | scripted |
| Starving Buzzard, Warsong Commander | triggered on themselves | others only |
| Shadowflame | could target your own hero | minions only (patched requirement) |
| Lightning Storm | one roll for the board | a roll per minion |
| Pint-Sized Summoner | discounted the turn it was played; survived its death | an aura on the first minion each turn |
| Cabal Shadow Priest | with six minions, destroyed its target | no target |
| Kidnapper | unplayable with combo and no minions | its combo fizzles |
| Nourish | empty crystals | full crystals |
| Mindgames | nothing when their deck had no minion | Shadow of Nothing |
| Bouncing Blade | an engine error at its cap | stops at 80, as Hearthstone's does |

### Looked at, left alone

* Prophet Velen doubling Arcane Missiles' count (not each missile) is Hearthstone's behaviour.
* Shadowform cast a third time: the engine gives nothing new, deliberately (tools/effects/finishers.csv);
  whether Hearthstone refreshes Mind Shatter is unconfirmed, so it was not changed.
* Lightspawn with an attack buff: attack still adds on top. Unconfirmed, not changed.
* Unconfirmed ordering details: Pyromancer on a countered spell, the Windfury freeze-thaw case,
  cost-floor order under Loatheb, on-death Secrets versus deathrattles, a weapon's ON_PLAY
  order, Ogre redirects onto Stealthed minions, and Gazlowe reading a modified cost.

## Robustness

* **One Lua error mid-move locked the board for good.** The presentation lock was released only
  by a callback scheduled after the move; an error in between (rules or animation) left every
  click refused and the rope waiting forever. Practice and duel moves now run guarded
  (`Main:Guarded`), and the unlock always happens.
* **A timeline cue that throws is dropped** (reported once through WoW's error handler) instead of
  failing every frame and stalling everything after it.
* **Mute silences what is already playing**: voice lines are cut and the rope's hiss pauses. If
  you change WoW's Music volume while the addon has it muted, your setting is kept on unmute.
* An aborted duel clears its queued animations.
* A golden card plays its golden stinger instead of both stingers; a multi-card draw is one
  sound.
* Every sound and texture path, and every `.toc` entry, exists with exact case; no globals leak.

## Layout at the extremes

New preview scenes `x-*-narrow` (900x1440) and `x-*-ultrawide` (2000x560) cover every screen.

* **Rope**: `turn-rope.tga` is 32px tall with the rope in rows 10–22, so the rect drew a thread
  about 0.6% of the picture. The texture is cropped to the rope and the rope is 2% of the
  picture.
* **Challenges plaque** is as wide as its words, and the record card matches it.
* **Plaque words fit the stone face** (`W.MenuFaceBox`): the fit box ignored the gilded caps,
  so in a tall window "Main Menu", "My Decks", "Choose Deck" and "Play" ran over the gold.
* **Main menu**: Resume and Close keep inside a narrow window. In a wide, short one the tagline
  goes instead of sitting on the cabinet's foot.
* **Deck pages** (My Decks, Practice) choose their rows and columns for the page's shape
  (`W.DeckGrid`) and fill from the top-left: one row of readable boxes in an ultrawide window,
  two across in a tall one, not a lone box floating mid-page.
* **Practice captions** wrap instead of ending in "...".
* **Open Packs**: the top card stops below the painted title; the mirrored band above the room no
  longer shows the title upside down (`EdgeBands` `plainTop`); "All Classes" is sized by the
  room; a full-frame backdrop stops a stale layout showing the tavern under the room.
* **Board**: the enemy hand drops below the corner buttons when it would cover them; your hand
  keeps off your name plate where it can; the side bands beside a letterboxed board are the
  menus' letterbox rather than a stretched smear with a hard dark edge.

## Tests

`tests/test_release013.lua` (43 suites: every rules fix and the timeline guard), plus layout
suites in `test_collectionui.lua` and `test_ui.lua`. Changed expectations: Nourish now full
(`test_chooseone.lua`), the deck-paging test makes enough decks for any grid, and the "bot does
not cut clips" source check allows the mute to.
