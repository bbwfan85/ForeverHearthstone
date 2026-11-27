# 48 - Social: players nearby and the guild ladder

First shipped in the test build 1.3.0-beta.1 (docs/49).

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

## Not verified on Forever

**Whether the client carries an addon message on YELL or SAY outdoors.** Retail
restricts these to instances; Forever has not been tested. The code finds out
for itself rather than assuming:

- a refused send moves YELL -> SAY -> "refused" (retried every 10 minutes);
- a beacon we never hear come back, twice, does the same and ends at "silent";
- in either state the **glance fallback** turns on: the player you mouse over
  or target is whispered one quiet question (once per player per half hour,
  one question every 3 seconds at most, same faction only), and only clients
  with the addon answer.

`/fh nearby` prints which of these the client turned out to be in. If Forever
delivers a range message to others but not back to the sender, the state will
read "not carried" while still working for everyone else; beacons continue in
that state for exactly this reason.

Also untested in a client: how the Social window and the pop-up actually look.
The tour has two new scenes (`nearby-popup`, `social`) and `/fh nearby test`
shows both without a second player.

## Trust and privacy

- Ranks are self-reported. Anyone can edit their saved variables, so the guild
  board is a friendly one, not a verified one.
- Your position is shared only with addon users within earshot, and only while
  "Visible to nearby players" is on and challenges are open to anyone. Blocked
  and ignored players are neither listed nor announced, and are not answered.
- The position question is answered only for someone you would accept a
  challenge from.
