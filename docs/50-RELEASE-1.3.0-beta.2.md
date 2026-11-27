# Forever Hearthstone 1.3.0-beta.2

A test build, replacing 1.3.0-beta.1. If you are not testing, stay on 1.2.1.
Both testers need this build: beta.1 could only find players you pointed at.

## What changed since beta.1

- **Nearby players are now found automatically on Forever.** Forever turned out
  to refuse the two "everyone in earshot" message types that beta.1 relied on,
  which left it finding only players you moused over. The addon now joins a
  chat channel of its own for the zone you are in and announces itself there;
  each player's addon then keeps only those close by (within 300 yards for the
  Social list, 80 for the pop-up).
  - The channel is joined for the session only and taken off every chat
    window, so it should print nothing. It joins 20 seconds after login so
    General and Trade keep their usual numbers, follows you from zone to zone,
    and is left if you turn off "Visible to nearby players".
- **Only players on your layer.** A chat channel covers every layer of a zone,
  so each addon reads its layer from the creatures around it and shares it.
  Players on another layer are hidden. A player whose layer is not known yet
  is listed with a `~` before the distance, and Duel asks you to target them
  first, so a duel cannot start between two layers. The layer is picked up
  again from the next creature you target or mouse over after changing zone
  or joining a group.
- If a client blocks that channel too, the addon quietly asks your party
  members and anyone whose /say, /yell or emote reaches your chat, as well as
  players you mouse over or target.
- The pop-up no longer has a bright square in its top-left corner.

Everything else is as in beta.1: the Social menu with the Guild Ladder and
Players Nearby, the pop-up, the two switches, and the card fixes.

### What testers should check

1. Outdoors, about a minute after logging in, type `/fh nearby`. It should say
   "broadcast working, zone channel FHN..." (yell and say being refused is
   expected).
2. Check your chat: no "Joined Channel" line, no new channel among your chat
   tabs' channels, and General and Trade still on their usual numbers.
3. Target or mouse over any creature, then `/fh nearby` again: it should show
   "Layer" and a number. Standing together, you should both see the SAME
   number. Please report if they differ.
4. Stand in the same zone, within about 80 yards. Each of you should get the
   pop-up within a minute or so, and see the other under Social > Players
   Nearby.
5. Press Duel from the pop-up or the list while standing together, and Knock
   from further away.
6. Ride into another zone together and check you still see each other.
7. If you share a guild, check you both appear on the Guild Ladder.

## Duelling other versions

Both players should be on 1.3.0-beta.2. The network protocol number is
unchanged (10), so older versions still connect, but the card fixes in this
series change how a few cards resolve, and a duel against 1.2.1 can fall out
of step if one of those cards is played.

## Installation

Replace the old ForeverHearthstone addon folder with the folder from
ForeverHearthstone-1.3.0-beta.2.zip, then restart WoW completely. Your rank,
collection and decks carry over unchanged.

## Validation

All 1,423 automated suites pass, 25 of them for Social. On the owner's Forever
client the zone channel carried the addon's messages ("broadcast working") and
the layer could be read.
Two real players finding each other is what this build is to confirm.
