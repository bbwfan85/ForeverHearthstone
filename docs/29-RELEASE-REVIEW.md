# 29. The release review: duels that cannot be broken from outside, rules that match Hearthstone

Written 2026-09-26 for 0.1.0-beta.3. `./run-tests.sh`: 1129 suites, 0 failures.

**Lua only: `/reload` is enough.** No new media. **Protocol version 4: both duellists must update.**

## What was asked

> Perform a full review of the addon so it's ready for release: how it looks, the animations,
> the sounds, the rules, the implications. Then commit, push and create the new release.
>
> I want people only close to each other in game, positionally, to be able to duel each other.

The review read the engine, the client, the network code, the saved data and the packager. The
headline findings: one hostile addon message could hang another player's client, and Lord
Jaraxxus could neither be hurt nor attack. Everything below was fixed and has a test, except the
items under **Left as they are**.

## Proximity, on every path (`Main:NearEnough`)

Before, only `/fh duel` with a target checked range. `/fh duel Name`, the right-click menu,
rematches and **accepting** skipped it.

* **Challenging** (any way) needs the other player to be a unit this client can see (your target,
  focus or mouseover, your party or raid, or a nameplate) and within trade range
  (`CheckInteractDistance(unit, 2)`, about 11 yards).
* **An incoming challenge** from someone you can see standing far off is dropped in silence.
* **Accepting** needs the challenger beside you. If they are not a unit this client can see, the
  pop-up stays and chat says "target <name>". A rematch that cannot be auto-accepted this way
  shows the ordinary pop-up.

Range cannot be checked from a name alone: WoW has no position API for players outside your
group. That is why the rule is "a unit you can see".

## Duels: the network (`Client/Net`)

| Was | Now |
|---|---|
| `1e300;HI;3` from anyone made the inbox list every number up to 1e300: the client hung, then ran out of memory. | A sequence number must be finite and within `Protocol.WINDOW` (256) of the stream. A NAK names at most `MAX_NAK` (32) messages, and a received NAK re-sends at most that many. |
| A chunk group of more than 64 parts was dropped, and the duel waited forever for it. | The inbox reports it as fatal, and the session ends the duel with a reason. |
| The name on the pop-up, Block, the decline cooldown and silencing all used the name the challenge *claimed*. It could impersonate anyone and could carry `\|c`/`\|T` escape codes into chat. | The transport's sender is used. Peer text goes through `Session.Plain`, which strips `\|` and caps the length. |
| "Friends & group" trusted the GUID inside the challenge. | That GUID is used only when `GetPlayerInfoByGUID` names the sender. |
| After a finished duel, nobody else could challenge you until a reload (the transport still listened only to the last opponent). | `strangersWelcome`: once no duel or challenge is live, a stranger's challenge gets through, and the finished opponent can still rematch. |
| The rematch check compared names with `==` (realm or no realm). | `Transport.SameName`. |
| `/fh duel` on a player from another realm whispered your own realm's namesake. | The realm is kept. |
| 33 missing messages over a whole match ended it. | The count is per hole. |
| A BYE "claimed" made you concede, however it arrived. | `Session:ClaimIsFair`: accepted only if you are paused, the line has gone quiet, or your own turn has run past the rope. Otherwise the duel ends with no result. |
| Re-sending PAUSE restarted the grace period, so a duel could be held forever. | The grace runs from when the player first left. |
| A deck with an empty field, a HELLO with no or an unknown class, a rejoin bundle with seat 0 or illegal decks: Lua errors or a forged game. | All refused. Every received message is handled inside `pcall` (`Transport:Deliver`); an error ends the duel once, with a line in chat. |
| A remembered duel was rejoined automatically forever, and a stranger's rejoin offer bypassed challenge privacy. | A remembered duel is forgotten after 10 minutes. Rejoin offers obey who may challenge you. |
| Every build reported version "0.1.0-dev". | The version is read from the `.toc` at load. |

## Saved data (`Client/Vault.lua`, `Client/Collection.lua`)

* `level = 60` typed into the saved file granted every class card: `GrantForLevel` trusted the
  larger of the saved and real levels. Now it uses WoW's level only. `level`, `dryKills` and
  `practiceRecord` are sealed too (vault version 2). A version-1 vault (beta.1, beta.2) opens
  and keeps those three from the plain file for one session.
* Deleting the vault and typing plain `cards`/`dust`/`packs` was accepted and then sealed. Every
  shipped version seals at logout, so plain sealed fields with no vault are now set aside, and
  the player is told.
* A vault that would not open (for example the character's GUID changed) was sealed over at the
  next logout and lost at the one after. It is now never overwritten.
* The vault is sealed **first** at logout, so a later error cannot skip it.
* Not changed: the account vault's key is a constant, so a sealed account collection could be
  copied between accounts. There is no account identifier WoW reliably gives an addon
  (BattleTag needs Battle.net to be up). Salting with one would lock players out of their
  collection whenever it is missing.

## Drops

At level 60 there is no XP gate, so keeping your target on other people's mobs paid drops.
Kills that are tap-denied (`UnitIsTapDenied`: not yours or your group's) no longer roll.

## Presentation

* **The rope** is cleared when the game ends and when a duel is aborted. It used to burn, and
  hiss, over the Victory screen.
* **An aborted duel** stops the director, music, rope, a locked presentation, shake and vignette.
  It also closes the exit and concede dialogs.
* **Alt+Z and cinematics** hide the board without leaving the table. There is no main menu and no
  "Leave this duel?" waiting when the UI returns, and the practice bot pauses (`IsVisible`).
* **Drop toasts** are always clickable, whichever path made the toast stage first.
* **`/fh open`** plays on the screen stage, never on a paused game's hand cards.
* **The concede dialog** closes when the game ends.
* **The hero-power card** no longer asks for a glow texture that does not exist.

## Rules (`Engine/`, `tools/effects`)

| Card or rule | Was | Now |
|---|---|---|
| Lord Jaraxxus | His hero was in `ZONE.HERO`, so no damage landed and Blood Fury never swung. | In `ZONE.PLAY`, like any hero. |
| Turn limit | None. | A game still going when turn 89 ends is a draw (`RULES.TURN_LIMIT`). |
| Replaced hero power (Shadowform, Jaraxxus) | Stayed spent. | Ready: Lesser Heal, Shadowform, Mind Spike on one turn. |
| Duplicate or sixth secret | Took the mana and vanished. | Unplayable (`Targeting.ModePlayable`). |
| Secrets as spells | Not a spell cast. | Raise `SPELL_CAST`: Counterspell counters them, and Mana Wyrm, Auctioneer and the rest see them. They also get Spell Damage (Explosive Trap). |
| Losing an aura's Health | Damage stayed, so a damaged 1/1 died when Stormwind Champion did. | Lost aura Health soaks damage first; losing an aura never kills. Silence (an enchantment) still can. |
| Hero powers and Spell Damage | Fireblast + Kobold Geomancer dealt 2. | 1. Velen still doubles hero powers. |
| Arcane Missiles, Avenging Wrath | Spell Damage added no missiles. | +1 Spell Damage is one more missile. |
| Velen and healing | Doubled every heal (Lightwell, Healing Totem, Truesilver). | Spells and hero powers only. |
| "Restore to full" under Auchenai | 99 damage: Stoneskin Gargoyle killed itself every turn. | The missing Health. |
| Ice Block, Redemption | Fired on their owner's own turn. | Like every secret, only on the opponent's turn. |
| Noble Sacrifice, Snake Trap, Mirror Entity, Spellbender; Avenge | Fired and were spent on a full board; Avenge with no other minion. | They do not trigger. |
| Freezing Trap | No cost increase. | The returned card costs (2) more. |
| Doomhammer | The hero attacked once. | A weapon's Windfury is the hero's. |
| Faerie Dragon | Your own spells could target it. | No spell or hero power can. |
| Deathrattle summons | Appeared at the far right. | In the slot the minion died in, left to right. |
| Simultaneous deaths | Each death drained on its own: the first deathrattle's chain finished before the second was queued. | All deaths announced and all deathrattles queued in play order, then resolved. |
| Corruption, Nightmare, Shadow Madness | Survived Silence, and a bounced target died when replayed. | Cancelled by Silence, a transform or leaving play (`Entity.enchGen`). |
| The Coin, Innervate at 10 mana | 11 or 12 mana. | Never more than 10 to spend. |
| Wild Growth at 10 crystals | Nothing. | Excess Mana (now scripted: draw a card). |
| "Whenever you cast / play" (Violet Teacher, Mana Wyrm, Questing Adventurer...) | Resolved after the card. | Resolve first (`Bus:ResolveQueued`): the Apprentice is there for Savage Roar. Wild Pyromancer ("after") moved to the new `SPELL_RESOLVED`. |
| Snipe, Mirror Entity, Repentance | Fired before the battlecry. | After it (`AFTER_MINION_PLAYED`). |
| Truesilver Champion | Healed after the blow. | Before it (at 29 Health into a 4-attack Yeti you end at 26). |
| Alexstrasza | Set maximum Health to 15. | Sets remaining Health; you can heal back to 30. |
| "If available" battlecries (Spellbreaker, Brewmaster, Crazed Alchemist) | Could be played blank to dodge a drawback. | Must take a target when one exists. |
| Transform, bounce | Kept Ancient Mage's Spell Damage, Frozen and a pending destroy. | Cleared. |

Existing tests that encoded the old behaviour were changed to match Hearthstone: the hero power
refresh, Ice Block and Redemption on their owner's turn, Faerie Dragon, and two secret-display
tests (whose Counterspell now, correctly, countered the other player's secret).

## Packaging (`tools/package_release.py`)

* Refuses a development version.
* Fails if luajit is not found; it used to print a note and ship unchecked.
* Leaves out the import reports and provenance (`*.json`), `Art/README.md` and the unloaded
  `Data/Effects/Examples.lua`. Licence texts ship.
* The player README names the client's own AddOns folder, not only `_retail_`, and says duels
  need both players standing together.

## Left as they are (not certain enough to change)

* Freeze thaw timing for a character frozen on its own turn.
* Stealth is broken only by attacking, not by dealing damage.
* The old weapon is destroyed before the new weapon's battlecry.
* Kirin Tor Mage + Loatheb cost order, the Dunemaul Shaman redirect vs secrets, and Reversing
  Switch's Health: flagged "not verified" in the code already.
* Arcane Missiles settles deaths between missiles.
* Escape during a live duel asks "Leave this duel?", and a second Escape closes the question.
  That is on purpose.
* The rich-text retry counter (5 tries while a font loads) is not reset per text.

## Check in game

1. **Proximity:**
   - `/fh duel Name` and the right-click menu refuse a player out of range.
   - Accepting says "target <name>" when the challenger has no nameplate and is not targeted.
   - A rematch still starts.
2. **After a duel ends,** a third player can challenge you without a reload.
3. **Alt+Z during a duel:** no menu and no "Leave this duel?" when the UI comes back. The bot
   waits while the UI is hidden.
4. **Lethal while the rope burns:** no rope and no hiss over Victory.
5. **Jaraxxus:** attack with Blood Fury, then take damage.
6. **Violet Teacher + Savage Roar:** the Apprentice gets +2.
7. **The package smoke test from docs/26** (unlink the dev junction, unzip, full restart): PNG
   and JPEG textures, and no `.json` files in the folder.
8. **Still unconfirmed from earlier passes:**
   - The docs/24–28 "check in game" lists.
   - The protected-action block noted in RETAIL-TESTING.
   - The `MENU_UNIT_*` tags on Forever.
   - Drop rates.
