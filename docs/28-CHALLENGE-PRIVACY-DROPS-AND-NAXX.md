# 28. Not being spammed, drops you can see, and Naxxramas cards that are never wasted

Written 2026-09-25. `luajit tests/run.lua`: 1094 suites, 0 failures.

**Lua only: `/reload` is enough.** No new media.

## What was asked

> There should be a way to prevent getting spammed by people trying to duel if you were a
> streamer being trolled. Take another look at the pack gain rate and how we are calculating
> getting cards for Naxx. Is there an animation letting the person know in the overworld that
> they got a pack drop?

## Challenge privacy (`Main:AllowChallengeFrom`)

A refused challenge is dropped in silence. There is no pop-up, no sound, no chat line, and no
reply for a troll to count.

| Control | How |
|---|---|
| Who may challenge you | **Anyone** (default), **Friends & group** (WoW friends, Battle.net friends, guild, party or raid) or **Nobody**. Set it with the button under the record on the main menu, or `/fh challenges anyone \| friends \| off`. Saved for the account. |
| Block | The **Block** button on the challenge pop-up declines and blocks in one click. `/fh block Name`, `/fh unblock Name`, `/fh blocked`. Saved for the account. WoW's own ignore list counts as blocked. |
| Cooldown | After you decline someone, their challenges are ignored for 2 minutes. The third decline silences them until you log out. |
| One at a time | While a challenge is on screen, nobody else's can arrive. The transport already listens only to that player; this is now tested. |

Rejoin offers from a blocked player are ignored too.

## Drops you can see

**The bug:** drops used the board's stage whenever a board existed. The board is kept, hidden,
after your first match, so **every drop after your first game showed its toast inside a hidden
window**. Only the chat line appeared. Starting a match could also cut a toast off, because it
shared the match's animation driver.

**Now:**

* Drops always toast on the screen (`Main:PlayDropToast`), on their own driver.
* They are queued: a level-up that pays a pack and three class cards shows four toasts in turn.
* The toast is a leather plaque in a gold rim with the pack art, "Card pack!", "3 packs waiting"
  and "Click to open". Clicking it opens the pack room. A card shows its art, its name, and
  "Legendary card from Naxxramas", glowing in its rarity's colour.
* It holds for about 3.5 seconds (4 for a card) instead of 2.3. There is still no screen shake
  and the sound is still soft; it fires mid-fight.

Preview: `tools/drop-toast.png`, `tools/drop-toast-card.png`.

## Naxxramas

The boss pool is the adventure's **21 neutral cards**: 9 commons, 4 rares, 2 epics and
6 legendaries, **36 copies** for a full set. The nine Naxx class cards come with levelling
(`Collection:ClassCurve`), as before.

**Duplicate protection was one re-roll.** After that, the spare was handed over anyway, so the
last cards, the legendaries above all, took far longer than the first. Simulated with the real
rules, completing the set took a **median of 123 boss cards. It now takes exactly 36**
(`Drops.BossCard`). The roll still picks a rarity at 50/30/12/8, then a card of that rarity you
can use, stepping to the nearest incomplete rarity when that one is done.

**Once the set is complete, a boss pays a pack** instead of a spare.

**Raid bosses rolled twice.** Their classification is "worldboss", so killing one rolled a
Naxx card from the kill *and* from `ENCOUNTER_END`. Inside an instance with encounter events,
the kill now counts as the elite it is, and the encounter pays the boss.

What this means for pacing: first kills of each dungeon boss are guaranteed a card, so a player
who runs the levelling dungeons finishes Naxxramas, legendaries included, somewhere in the
dungeon circuit. That is roughly what finishing the adventure gave in Hearthstone. If it is
too quick, turn down the first-kill guarantee (`Rewards:Boss`) or the 12% repeat rate
(`Drops.RATES.boss`), not the protection.

## The pack rate

The base rates are unchanged. Simulated over 200,000 kills:

| | Before | Now |
|---|---|---|
| Normal mob | 1 drop per 67 kills; 1 player in 10 went 150+ kills without one | **1 per 57**; never more than **150** without one |
| Elite | 1 per 25 | 1 per 21; never more than 57 |

The new part is a **bad-luck floor** (`Drops.DRY_LIMIT`). Every eligible kill that pays nothing
adds its drop chance to a saved dry spell (`character.dryKills`), and once that reaches 150
normal kills' worth, the next eligible kill pays. Roughly 4 in 5 drops are packs.

At a typical levelling pace of 60-90 kills an hour, that is about one pack an hour plus a
single card every few hours, on top of 16 milestone packs (3 at level 1, then 10, 20, 30 ×2,
40 ×2, 50 ×2 and 60 ×5).

**Removed:** the pack room used to grant 5 free packs the first time it was opened (a test
grant from the drag-to-open work, more than the level 1-29 milestones combined). It is gone;
accounts that already received it keep those packs.

## Tests

`privacy:` (block, Block button, friends-only and off, cooldown and silence, one challenge at a
time), `economy:` (every boss card usable and 36 to complete, a pack once complete, the floor
and its average), `rewards:` (toast on screen after a match, queued toasts, click opens packs,
raid boss paid once, the floor saved with the character).
