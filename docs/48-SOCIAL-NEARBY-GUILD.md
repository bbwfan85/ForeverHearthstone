# 48 - Social: players nearby and the guild ladder

Shipped in 1.3.0 (docs/52), after three test builds.

## What it is for

Until now you could only find out that someone had the addon by targeting them
and challenging blind. The owner's brief: a player running around the world
should simply notice that someone near them can be challenged, without anyone
stopping to set anything up, without nameplates (the owner plays with friendly
nameplates off), and without getting in the way of other UI addons. Plus a
guild leaderboard to give people a reason to look for games.

Ideas considered and turned down along the way: nameplate icons, an "open
table / looking for a game" mode you switch on, inns as meeting places, minimap
pins, and a compass card at the screen edge. The owner chose a pop-up in the
style of a pack drop and a Social screen.

## What the player sees

- **Social** (the plaque in the menu's bottom-left corner, or `/fh social`):
  - Left: **Guild Ladder** - class, name and rank of every guildmate who has
    reported one, best first, Legend on top. Offline members stay on the board,
    dimmed, at the rank they last reported.
  - Right: **Players Nearby** - rank, class and distance, nearest first, each
    with a button. **Duel** for someone beside you; **Knock** for someone
    further off, which raises a "wants a game" pop-up on their screen.
  - Two switches: the pop-up, and whether nearby players can see you. Both are
    also in Settings.
- **The pop-up**: when a player comes within 80 yards, a small panel slides in
  under where pack drops appear, naming up to the three most recent with a
  button each, then "and N more" (clicking the panel opens Social). It leaves by
  itself after about seven seconds; the clock stops while the pointer is on it.
  - One announcement per player per 20 minutes, and at least 2 minutes between
    pop-ups.
  - Held back, not lost, during combat, a match, a pending challenge or while
    the collection is open.
- `/fh nearby` reports what the client allows; `on | quiet | off` set the
  switches; `test` shows both screens with made-up players and sends nothing.

## How it works

Logic is in `Client/Social.lua` (no WoW API, fully tested headless); frames and
the wire are in `Client/UI/Social.lua`.

- **Its own prefix, `FHNEAR`.** Clients up to 1.2.1 never registered it and
  never see a byte, and it has its own throttle allowance, so nothing here can
  spend a message a duel needs. The duel protocol is unchanged (10).
- **Beacons** go out on a range-limited distribution, `YELL` and failing that
  `SAY`, so the server decides who is close enough to hear and nothing is
  announced realm-wide. A beacon is about 45 bytes: GUID, class, rank and a
  position rounded to the yard.
  - About every 45 s while travelling (sooner after 40 yards, never inside
    15 s), 90 s standing still, doubled once five players are known.
  - A new player's beacon is answered with one of ours a second or two later,
    so two riders passing learn of each other at once.
  - Nothing is sent while hidden, with challenges set to friends or nobody, in
    an instance, in combat, dead, AFK, on a flight path or in a duel.
  - A player is forgotten 200 s after their last beacon.
- **Duel without a target.** A beacon can be most of a minute old, so pressing
  Duel whispers the player a question and challenges only if their answer puts
  them within 14 yards. The challenge itself is the ordinary HELLO. A player who
  is a unit on your client (targeted, in your group) goes straight through the
  existing range check.
- **Guild.** A roll-call on the `GUILD` distribution at login and when Social
  opens; each member answers a few seconds later with class, rank, stars and
  duel record, and again when their rank changes. Kept in
  `ForeverHearthstoneDB.social.guilds`, pruned after 60 days.

## What Forever allows (tested 2026-11-27)

**Forever refuses addon messages on YELL and SAY outdoors**, as retail does
(`/fh nearby` reported "refused", last result "SAY: failed"). The code finds
this out for itself on every client and works down a list:

1. `YELL`, then `SAY`: range-limited by the server. Refused on Forever.
2. **The zone channel.** A chat channel of the addon's own, one per zone
   (`FHN<map id>`), joined for the session only, taken off every chat window so
   it prints nothing, and joined 20 seconds after login so General and Trade
   keep their numbers. Everyone in the zone with the addon hears each beacon;
   each client lists only players within 300 yards and announces those within
   80. Left when you hide yourself; swapped when you change zone.
   Verified on Forever 2026-11-27: the channel carries addon messages. Not yet
   checked: whether the channel stays out of sight in chat.
   **Layers.** The channel spans every layer of the zone. Each client reads
   the zone uid from creature GUIDs it is shown and sends its last few. On
   Forever that number is NOT one per layer: it changed three times in a few
   minutes in one zone (2026-11-27), so it is evidence only. Two players with
   a value in common are confirmed on the same layer; otherwise the player is
   listed with a `~`. Nobody is hidden on a mismatch (beta.2 did, wrongly),
   and Duel is NOT gated on it: the owner's call (2026-11-27), until the check
   has been tested between two players. So a duel across layers is possible
   for now. Not yet
   seen: whether two players standing together ever share a value.
3. **Asking individuals**, when nothing above works: one quiet whisper to a
   player you mouse over or target, to your party, and to anyone whose /say,
   /yell or emote reaches your chat (they are in earshot by definition). Once
   per player per half hour, one question every 3 seconds at most. Only clients
   with the addon answer.

A distribution that is refused is retried every 10 minutes. `/fh nearby` prints
which one is in use and which were refused.

Also untested in a client: how the Social window looks. The tour has two new
scenes (`nearby-popup`, `social`) and `/fh nearby test` shows both without a
second player.

## Trust and privacy

- Ranks are self-reported. Anyone can edit their saved variables, so the guild
  board is a friendly one, not a verified one.
- Your position is shared only with addon users within earshot, and only while
  "Visible to nearby players" is on and challenges are open to anyone. Blocked
  and ignored players are neither listed nor announced, and are not answered.
- The position question is answered only for someone you would accept a
  challenge from.
