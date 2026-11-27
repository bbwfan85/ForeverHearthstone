--[[ tests/test_social.lua -- players nearby, the pop-up, and the guild ladder.

  The first half drives Client/Social.lua as plain data: the clock, positions
  and rolls are all passed in, so the beacon schedule, the channel fallback,
  who is announced and how the guild board sorts are tested exactly.

  The second half loads Client/UI/Social.lua against the strict WoW stub, so
  building the Social window and the pop-up proves every call they make exists
  on the Mainline surface, and the wire is the real one: lines go out through
  C_ChatInfo.SendAddonMessage and come in as CHAT_MSG_ADDON.

  WHAT IT CANNOT PROVE: that Forever carries an addon message on YELL or SAY
  outdoors. Nothing headless can -- which is why the code finds out for itself
  (Social:CheckEcho) and /fh nearby reports the answer.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")

local function card(S, kind, guid, class, rank, x, y, legend)
  return S.Decode(S.Card(kind, { guid = guid, class = class, rank = rank, legend = legend },
                         x and { x = x, y = y, instance = 0 } or nil))
end

H.suite("social: a card survives the wire, and junk does not", function(ns, H)
  local S = ns.Social
  local raw = S.Card("B", { guid = "Player-1-0A", class = "MAGE", rank = 12 }, { x = -8913.4, y = 563.6, instance = 0 })
  H.ok(#raw < 80, "a beacon is a short line (" .. #raw .. " bytes)")
  local m = S.Decode(raw)
  H.eq(m.kind, "B"); H.eq(m.guid, "Player-1-0A"); H.eq(m.class, "MAGE"); H.eq(m.rank, 12)
  H.eq(m.x, -8913); H.eq(m.y, 564); H.eq(m.instance, 0)
  local legend = S.Decode(S.Card("A", { guid = "Player-1-0B", class = "DRUID", rank = 0, legend = 412 }))
  H.eq(legend.legend, 412); H.eq(legend.x, nil, "a card may carry no position")
  H.eq(S.Decode("B;1;Player-1-0A;DEATHKNIGHT;12;;1;2;0"), nil, "a class this game does not have")
  H.eq(S.Decode("B;1;Player-1-0A;MAGE;99;;1;2;0"), nil, "a rank off the ladder")
  H.eq(S.Decode("B;2;Player-1-0A;MAGE;12;;1;2;0"), nil, "a later version is not guessed at")
  H.eq(S.Decode("Z;1;x"), nil); H.eq(S.Decode(""), nil); H.eq(S.Decode(nil), nil)
  H.eq(S.Decode(("B;1;" .. ("x"):rep(300))), nil, "an overlong line")
  H.eq(S.Decode("B;1;bad guid!;MAGE;3;;1;2;0").guid, nil, "a malformed GUID is dropped, not kept")
  local g = S.Decode(S.GuildLine({ guid = "Player-1-0C", class = "ROGUE", rank = 5, stars = 3, wins = 10, losses = 4 }))
  H.eq(g.kind, "G"); H.eq(g.stars, 3); H.eq(g.wins, 10); H.eq(g.losses, 4)
  H.eq(S.Decode(S.Encode("R")).kind, "R")
end)

H.suite("social: nearby players are listed nearest first and forgotten when silent", function(ns, H)
  local S = ns.Social
  local s = S.New()
  local here = { x = 0, y = 0, instance = 0 }
  local far, isNew = s:Hear(10, "Far", card(S, "B", "G-FAR", "MAGE", 20, 60, 0), "beacon")
  H.ok(isNew)
  s:Hear(20, "Near", card(S, "B", "G-NEAR", "PRIEST", 8, 3, 4), "beacon")
  s:Hear(30, "Nofix", card(S, "B", "G-NOFIX", "ROGUE", 15), "beacon")
  local _, again = s:Hear(40, "Far", card(S, "B", "G-FAR", "MAGE", 19, 60, 0), "beacon")
  H.notOk(again, "hearing someone again is not meeting them again")
  H.eq(far.rank, 19, "but their card is the latest one")
  H.eq(s.count, 3)
  local list = s:List(here)
  H.eq(list[1].name, "Near"); H.eq(list[2].name, "Far"); H.eq(list[3].name, "Nofix", "no fix sorts last")
  H.eq(list[1].distance, 5)
  H.ok(S.InDuelRange(list[1], here)); H.notOk(S.InDuelRange(list[2], here)); H.notOk(S.InDuelRange(list[3], here))
  H.eq(S.Distance(far, { x = 0, y = 0, instance = 1 }), nil, "another continent is no distance at all")
  H.eq(#s:List(here, function(name) return name == "Near" end), 2, "a blocked player is left out")
  H.eq(s:Expire(40 + S.EXPIRE), 2, "the two not heard since go")
  H.eq(s.count, 1)
  H.eq(s:Expire(41 + S.EXPIRE), 1); H.eq(s.count, 0)
end)

H.suite("social: the beacon schedule is slow, and quicker only for travel and newcomers", function(ns, H)
  local S = ns.Social
  local s = S.New()
  local yes, no = { eligible = true }, { eligible = false }
  local at = function(x) return { x = x, y = 0, instance = 0 } end
  H.notOk(s:ShouldBeacon(0, at(0), no), "never while not eligible (hidden, in a duel, in an instance)")
  H.ok(s:ShouldBeacon(0, at(0), yes), "the first one goes at once")
  s:NoteBeacon(0, at(0), "sent", 0)
  H.eq(s.sent, 1)
  H.notOk(s:ShouldBeacon(S.BEACON_FLOOR - 1, at(500), yes), "never inside the floor, however far you rode")
  H.ok(s:ShouldBeacon(S.BEACON_FLOOR, at(S.MOVE_YARDS), yes), "40 yards on earns one")
  H.notOk(s:ShouldBeacon(S.BEACON_MOVING - 1, at(20), yes))
  H.ok(s:ShouldBeacon(S.BEACON_MOVING, at(20), yes), "travelling: every 45 seconds")
  H.notOk(s:ShouldBeacon(S.BEACON_STILL - 1, at(1), yes))
  H.ok(s:ShouldBeacon(S.BEACON_STILL, at(1), yes), "standing still: every 90")
  for i = 1, S.CROWD do s:Hear(1, "P" .. i, card(S, "B", "G-" .. i, "MAGE", 20, 5, 5), "beacon") end
  H.notOk(s:ShouldBeacon(S.BEACON_STILL, at(1), yes), "in a crowd the interval doubles")
  H.ok(s:ShouldBeacon(S.BEACON_STILL * 2, at(1), yes))
  -- a newcomer is answered within seconds, once
  local e = s:Hear(20, "New", card(S, "B", "G-NEW", "DRUID", 9, 1, 1), "beacon")
  H.ok(s:PlanReply(20, e, 1))
  H.notOk(s:PlanReply(25, e, 1), "one answer per player per minute")
  H.notOk(s:ShouldBeacon(20.5, at(1), yes)); H.ok(s:ShouldBeacon(21, at(1), yes))
  s:NoteBeacon(21, at(1), "sent", 0)
  H.notOk(s:ShouldBeacon(22, at(1), yes), "and the plan is spent")
  local other = s:Hear(22, "New2", card(S, "B", "G-NEW2", "DRUID", 9, 1, 1), "beacon")
  s:PlanReply(22, other, 0.5)
  H.notOk(s:ShouldBeacon(23, at(1), yes), "two newcomers a second apart do not get two beacons")
  H.ok(s:ShouldBeacon(26, at(1), yes))
end)

H.suite("social: a client that will not carry beacons is found out", function(ns, H)
  local S = ns.Social
  local here = { x = 0, y = 0, instance = 0 }
  -- refused outright: YELL, then SAY, then the zone channel, then nothing
  local s = S.New()
  H.eq(s:Channel(0), "YELL")
  s:NoteBeacon(0, here, "failed")
  H.eq(s:Channel(0), "SAY"); H.ok(s:ShouldBeacon(0, here, { eligible = true }), "the next one is tried at once")
  s:NoteBeacon(0, here, "failed")
  H.eq(s:Channel(0), "CHANNEL", "Forever: say and yell refused, so the zone channel")
  H.notOk(s:GlanceMode(), "which may yet work")
  s:NoteBeacon(0, here, "sent"); s:NoteEcho()
  H.eq(s.broadcast, "ok"); H.eq(s:Channel(100), "CHANNEL")
  -- ten minutes on the refused ones are tried again, fail again, and it is back on the channel
  H.eq(s:Channel(S.REPROBE), "YELL", "tried again later, in case the place mattered")
  s:NoteBeacon(S.REPROBE, here, "failed"); s:NoteBeacon(S.REPROBE, here, "failed")
  H.eq(s:Channel(S.REPROBE), "CHANNEL")
  -- and if that is refused too, nothing is left
  s:NoteBeacon(S.REPROBE, here, "failed")
  H.eq(s.broadcast, "refused"); H.eq(s:Channel(S.REPROBE + 1), nil); H.ok(s:GlanceMode())
  H.notOk(s:ShouldBeacon(S.REPROBE + 100, here, { eligible = true }))
  -- accepted but never heard back: two misses each, then the glance fallback
  s = S.New()
  local t = 0
  for _, expect in ipairs({ "SAY", "CHANNEL" }) do
    for _ = 1, S.ECHO_MISSES do
      s:NoteBeacon(t, here, "sent"); s:CheckEcho(t + S.ECHO_WAIT); t = t + 60
    end
    H.eq(s:Channel(t), expect); H.notOk(s:GlanceMode())
  end
  for _ = 1, S.ECHO_MISSES do
    s:NoteBeacon(t, here, "sent"); s:CheckEcho(t + S.ECHO_WAIT); t = t + 60
  end
  H.eq(s.broadcast, "silent"); H.ok(s:GlanceMode())
  H.eq(s:Channel(t), "YELL", "unheard everywhere: the first is kept")
  H.ok(s:ShouldBeacon(t + 200, here, { eligible = true }), "beacons continue: others may still hear them")
  s:NoteEcho()
  H.eq(s.broadcast, "ok"); H.notOk(s:GlanceMode(), "one line heard on it proves it")
  -- heard back in time: confirmed, and never doubted again
  s = S.New()
  s:NoteBeacon(0, here, "sent"); s:NoteEcho(); s:CheckEcho(10)
  H.eq(s.broadcast, "ok"); H.eq(s.misses, 0)
  -- throttled is not a verdict on the channel
  s = S.New()
  s:NoteBeacon(0, here, "throttled")
  H.eq(s:Channel(0), "YELL"); H.eq(s.sent, 0)
  -- the glance and knock limits
  s = S.New(); s.broadcast = "silent"
  H.ok(s:MayGlance(0, "G-1")); H.notOk(s:MayGlance(1, "G-2"), "one question every few seconds")
  H.ok(s:MayGlance(S.GLANCE_GAP, "G-2")); H.notOk(s:MayGlance(100, "G-1"), "and one per player per half hour")
  H.notOk(s:MayGlance(100, nil))
  H.ok(s:MayKnock(0, "k")); H.notOk(s:MayKnock(S.KNOCK_COOLDOWN - 1, "k")); H.ok(s:MayKnock(S.KNOCK_COOLDOWN, "k"))
end)

H.suite("social: the pop-up names the newest three, once each, and waits its turn", function(ns, H)
  local S = ns.Social
  local s = S.New()
  local here = { x = 0, y = 0, instance = 0 }
  local on = { enabled = true }
  H.eq(s:PopupDue(0, here, on), nil, "nobody near, nothing to say")
  s:Hear(1, "TooFar", card(S, "B", "G-FAR", "MAGE", 20, S.POPUP_RANGE + 20, 0), "beacon")
  s:Hear(2, "Nofix", card(S, "B", "G-NF", "MAGE", 20), "beacon")
  H.eq(s:PopupDue(3, here, on), nil, "out of range, or no fix: listed under Social, not announced")
  s:Hear(4, "Ann", card(S, "B", "G-A", "MAGE", 20, 10, 0), "beacon")
  H.eq(s:PopupDue(5, here, { enabled = false }), nil, "switched off")
  H.eq(s:PopupDue(5, here, { enabled = true, busy = true }), nil, "busy: held back")
  local due = s:PopupDue(6, here, on)
  H.eq(#due.rows, 1, "and shown once free -- waiting did not lose her"); H.eq(due.rows[1].name, "Ann"); H.eq(due.more, 0)
  H.eq(s:PopupDue(6 + S.POPUP_GAP, here, on), nil, "nobody is announced twice")
  -- five arrive together: the newest three by name, and a count for the rest
  for i = 1, 5 do s:Hear(200 + i, "P" .. i, card(S, "B", "G-P" .. i, "PRIEST", 10, i, 0), "beacon") end
  H.eq(s:PopupDue(100, here, on), nil, "pop-ups keep their distance from each other")
  due = s:PopupDue(300, here, on)
  H.eq(#due.rows, S.POPUP_ROWS); H.eq(due.more, 2); H.eq(due.total, 5)
  H.eq(due.rows[1].name, "P5", "most recent first"); H.eq(due.rows[3].name, "P3")
  H.eq(s:PopupDue(300 + S.POPUP_GAP, here, on), nil, "the two not shown were announced with them")
  -- twenty minutes on, someone still here may be mentioned again
  s:Expire(300 + S.ANNOUNCE_COOLDOWN)
  s:Hear(300 + S.ANNOUNCE_COOLDOWN, "Ann", card(S, "B", "G-A", "MAGE", 20, 10, 0), "beacon")
  due = s:PopupDue(301 + S.ANNOUNCE_COOLDOWN, here, on)
  H.ok(due and due.rows[1].name == "Ann")
  -- someone you glanced at was on your screen: near by definition; a blocked one is never shown
  s:Expire(5000)
  s:Hear(5000, "Glanced", card(S, "A", "G-GL", "ROGUE", 3), "glance")
  s:Hear(5000, "Pest", card(S, "B", "G-PEST", "ROGUE", 3, 1, 1), "beacon")
  due = s:PopupDue(5001, here, { enabled = true, blocked = function(n) return n == "Pest" end })
  H.eq(#due.rows, 1); H.eq(due.rows[1].name, "Glanced")
end)

H.suite("social: the guild board is best first, one row per character, and forgets the long gone", function(ns, H)
  local S = ns.Social
  local store, day = {}, 86400
  local function say(name, guid, class, rank, stars, legend, wall, now)
    S.GuildMerge(store, name, { guid = guid, class = class, rank = rank, stars = stars, legend = legend, wins = 1, losses = 2 }, wall, now)
  end
  say("Bronze", "G-1", "MAGE", 22, 1, nil, 100 * day, 50)
  say("Five", "G-2", "ROGUE", 5, 2, nil, 100 * day, 50)
  say("FiveMore", "G-3", "DRUID", 5, 4, nil, 100 * day, nil)
  say("Legend900", "G-4", "PRIEST", 0, 0, 900, 100 * day, 50)
  say("Legend12", "G-5", "WARRIOR", 0, 0, 12, 100 * day, 50)
  local list = S.GuildList(store, 60, "G-2")
  local names = {}
  for i, r in ipairs(list) do names[i] = r.name end
  H.eq(table.concat(names, ","), "Legend12,Legend900,FiveMore,Five,Bronze")
  H.ok(list[4].me, "your own row is marked"); H.notOk(list[1].me)
  H.ok(list[1].online); H.notOk(list[3].online, "not heard this session: offline, at their last rank")
  H.notOk(S.GuildList(store, 60 + S.GUILD_ONLINE + 1, "G-2")[1].online, "online wears off")
  -- the same character under another form of its name replaces its old row
  say("Five-Realm", "G-2", "ROGUE", 4, 0, nil, 101 * day, 70)
  H.eq(store["Five"], nil); H.eq(#S.GuildList(store, 70), 5)
  -- pruning: stale rows go, "online" is never a saved fact, junk is dropped
  store["Junk"] = "not a table"
  store["Ancient"] = { class = "MAGE", rank = 20, seen = 1 * day }
  S.GuildPrune(store, 101 * day)
  H.eq(store["Junk"], nil); H.eq(store["Ancient"], nil); H.ok(store["Bronze"])
  H.eq(store["Bronze"].heard, nil)
  H.notOk(S.GuildList(store, 80)[1].online)
  store["Odd"] = { class = "NOTACLASS", rank = 3, seen = 101 * day }
  H.eq(#S.GuildList(store, 80), 5, "a row that is not a real card is not drawn")
end)

-- ============================================================ against the stub

local WOW_FILES = {
  "ForeverHearthstone/Client/Net/Transport.lua",
  "ForeverHearthstone/Client/Rewards.lua",
  "ForeverHearthstone/Client/UI/Widgets.lua",
  "ForeverHearthstone/Client/UI/Board.lua",
  "ForeverHearthstone/Client/UI/Collection.lua",
  "ForeverHearthstone/Client/UI/Social.lua",
  "ForeverHearthstone/Client/Main.lua",
}

local ME = "Player-1-000000AA"

local function withSocial(ns, fn, opts)
  opts = opts or {}
  Stub.Install(_G)
  Stub.resting = false
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60,
                            guid = ME, pos = { 0, 0, 0 } } }
  _G.ForeverHearthstoneDB = opts.db or {}
  _G.ForeverHearthstoneCharDB = { ladder = { rank = 12, stars = 2 } }
  _G.IsInGuild = function() return opts.guild ~= nil end
  _G.GetGuildInfo = function() return opts.guild end
  _G.IsInInstance = function() return false end
  for _, path in ipairs(WOW_FILES) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  ns.Main.collectionUI, ns.Main.collection, ns.Main.rewards = nil, nil, nil
  ns.Main.hub, ns.Main.settings, ns.Main.session, ns.Main.board = nil, nil, nil, nil
  ns.SocialUI.frame, ns.SocialUI.window, ns.SocialUI.popup = nil, nil, nil
  ns.SocialUI.pending, ns.SocialUI.status, ns.SocialUI.guildAsked, ns.SocialUI.guildSaid = nil, nil, nil, nil
  ns.SocialUI.answered, ns.SocialUI.guildReplyAt, ns.SocialUI.faulted = nil, nil, nil
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone")
  Stub.Fire("PLAYER_LOGIN")
  local ok, err = pcall(fn, ns.Main, ns.SocialUI, ns)
  _G.IsInGuild, _G.GetGuildInfo, _G.IsInInstance = nil, nil, nil
  if not ok then error(err, 0) end
end

local function sent(prefix)
  local out = {}
  for _, c in ipairs(Stub.R.calls) do
    if c.what == "SendAddonMessage" and (not prefix or c.args[1] == prefix) then
      out[#out + 1] = { prefix = c.args[1], msg = c.args[2], channel = c.args[3], target = c.args[4] }
    end
  end
  return out
end

local function hear(ns, raw, channel, from)
  Stub.Fire("CHAT_MSG_ADDON", ns.Social.PREFIX, raw, channel, from)
end

local function theirCard(ns, kind, guid, class, rank, x, y)
  return ns.Social.Card(kind, { guid = guid, class = class, rank = rank }, x and { x = x, y = y, instance = 0 } or nil)
end

local function click(b) b:GetScript("OnClick")(b, "LeftButton") end

H.suite("social ui: login registers its own prefix and beacons on a range-limited channel", function(ns, H)
  withSocial(ns, function(Main, S)
    local registered = {}
    for _, c in ipairs(Stub.R.calls) do
      if c.what == "RegisterAddonMessagePrefix" then registered[c.args[1]] = true end
    end
    H.ok(registered.FHNEAR, "FHNEAR is registered"); H.ok(registered.FHDUEL, "beside the duel's own")
    H.eq(#sent("FHNEAR"), 0, "nothing is said the instant you log in")
    Stub.Advance(20)
    local lines = sent("FHNEAR")
    H.eq(#lines, 1, "one beacon once the world has settled")
    H.eq(lines[1].channel, "YELL"); H.eq(lines[1].target, nil, "to whoever is in earshot, not a name")
    local m = ns.Social.Decode(lines[1].msg)
    H.eq(m.kind, "B"); H.eq(m.guid, ME); H.eq(m.class, "MAGE"); H.eq(m.rank, 12); H.eq(m.x, 0)
    H.eq(#sent("FHDUEL"), 0, "and the duel's allowance is untouched")
    -- our own line coming back confirms the channel, and is not a player
    hear(ns, lines[1].msg, "YELL", "Tester")
    H.eq(S.state.broadcast, "ok"); H.eq(S:Count(), 0)
    Stub.Advance(60)
    H.ok(#sent("FHNEAR") <= 2, "standing still, the next is a minute and a half off")
    H.ok(S:Report():find("working", 1, true), "/fh nearby says so")
  end)
end)

H.suite("social ui: hidden, friends-only, in a duel or in combat means silent", function(ns, H)
  withSocial(ns, function(Main, S)
    S:SetVisible(false); Stub.Advance(120)
    H.eq(#sent("FHNEAR"), 0, "hidden players say nothing")
    S:SetVisible(true); Main:DuelPrivacy().policy = "friends"; Stub.Advance(120)
    H.eq(#sent("FHNEAR"), 0, "nor do those who only take challenges from friends")
    Main:DuelPrivacy().policy = "anyone"; Stub.units.player.inCombat = true; Stub.Advance(120)
    H.eq(#sent("FHNEAR"), 0, "nor anyone mid-fight")
    Stub.units.player.inCombat = nil; _G.IsInInstance = function() return true end; Stub.Advance(120)
    H.eq(#sent("FHNEAR"), 0, "nor from inside a dungeon")
    _G.IsInInstance = function() return false end; Stub.Advance(5)
    H.eq(#sent("FHNEAR"), 1)
  end)
end)

H.suite("social ui: a player riding up is listed, announced like a pack drop, and gone again", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    local before = #sent("FHNEAR")
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 30, 40), "YELL", "Anduin")
    H.eq(S:Count(), 1)
    Stub.Advance(3)
    H.eq(#sent("FHNEAR"), before + 1, "a newcomer is answered with a beacon, so they learn of us too")
    local p = S.popup
    H.ok(p and p.frame:IsShown(), "the pop-up is up")
    H.eq(p.title:GetText(), "A Hearthstone player is nearby")
    H.eq(p.rows[1].name:GetText(), "Anduin")
    H.ok(p.rows[1].sub:GetText():find("Priest", 1, true) and p.rows[1].sub:GetText():find("Rank 7", 1, true)
         and p.rows[1].sub:GetText():find("50 yd", 1, true), "class, rank and distance: " .. p.rows[1].sub:GetText())
    H.eq(p.rows[1].button.text:GetText(), "Knock", "50 yards off: an invitation, not a challenge")
    H.notOk(p.rows[2].button:IsShown())
    local played = false
    for _, snd in ipairs(Stub.R.sounds) do played = played or snd.id ~= nil or snd.file ~= nil end
    H.ok(played, "with a sound")
    -- the pointer on it holds it; off it, it leaves by itself
    p.frame.mouseOver = true; Stub.Advance(20)
    H.ok(p.frame:IsShown(), "held while the pointer is on it")
    p.frame.mouseOver = nil; Stub.Advance(9)
    H.notOk(p.frame:IsShown(), "then it times out like a drop toast")
    -- not announced again while they stay
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 30, 40), "YELL", "Anduin")
    Stub.Advance(200)
    H.notOk(p.frame:IsShown())
    -- and forgotten once they have ridden out of earshot
    Stub.Advance(ns.Social.EXPIRE)
    H.eq(S:Count(), 0)
  end)
end)

H.suite("social ui: the pop-up can be switched off, waits out a fight, and never names the blocked", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    S:SetPopup(false)
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 5, 5), "YELL", "Anduin")
    Stub.Advance(5)
    H.ok(not S.popup or not S.popup.frame:IsShown(), "off means off")
    H.eq(S:Count(), 1, "they are still listed under Social")
    S:SetPopup(true); Stub.units.player.inCombat = true
    hear(ns, theirCard(ns, "B", "Player-1-CC", "ROGUE", 3, 5, 5), "YELL", "Valeera")
    Stub.Advance(5)
    H.ok(not S.popup or not S.popup.frame:IsShown(), "not in the middle of a fight")
    Stub.units.player.inCombat = nil; Stub.Advance(2)
    H.ok(S.popup.frame:IsShown(), "but as soon as it is over")
    H.eq(S.popup.title:GetText(), "Hearthstone players nearby")
    Stub.Advance(10)
    Main:Block("Garrosh")
    hear(ns, theirCard(ns, "B", "Player-1-DD", "WARRIOR", 1, 5, 5), "YELL", "Garrosh")
    Stub.Advance(ns.Social.POPUP_GAP + 5)
    H.notOk(S.popup.frame:IsShown(), "a blocked player is not announced")
    H.eq(S:Count(), 2, "or even listed")
  end)
end)

H.suite("social ui: many arrive at once -- three rows and a count", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    for i = 1, 6 do
      Stub.Advance(0.1)
      hear(ns, theirCard(ns, "B", "Player-1-C" .. i, "MAGE", i, i, i), "YELL", "Mage" .. i)
    end
    Stub.Advance(1.5)
    local p = S.popup
    H.ok(p.frame:IsShown())
    H.eq(p.rows[1].name:GetText(), "Mage6", "the most recent first")
    H.ok(p.rows[3].button:IsShown())
    H.ok(p.more:IsShown()); H.ok(p.more:GetText():find("and 3 more", 1, true), p.more:GetText())
    H.eq(p.rows[1].button.text:GetText(), "Duel", "beside you: Duel")
    click(p.frame)
    H.ok(S.window:IsShown(), "clicking the panel opens Social"); H.notOk(p.frame:IsShown())
    H.eq(S.nearCol.rows[1].name:GetText(), "Mage1", "where they are listed nearest first")
    H.ok(S.nearCol.rows[6].button:IsShown()); H.notOk(S.nearCol.rows[7].button:IsShown())
  end)
end)

H.suite("social ui: Duel asks where they stand now, and challenges only someone beside you", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 4, 3), "YELL", "Anduin")
    S:Show()
    local row = S.nearCol.rows[1]
    H.eq(row.button.text:GetText(), "Duel")
    click(row.button)
    local q = sent("FHNEAR"); q = q[#q]
    H.eq(q.channel, "WHISPER"); H.eq(q.target, "Anduin"); H.eq(ns.Social.Decode(q.msg).kind, "Q")
    H.eq(#sent("FHDUEL"), 0, "no challenge until they answer")
    -- they have walked off since their beacon
    hear(ns, theirCard(ns, "A", "Player-1-BB", "PRIEST", 7, 60, 0), "WHISPER", "Anduin")
    H.eq(#sent("FHDUEL"), 0)
    H.ok(S.nearCol.foot:GetText():find("60 yards away", 1, true), S.nearCol.foot:GetText())
    S:Refresh(true)
    H.eq(row.button.text:GetText(), "Knock", "and the button now says so")
    click(row.button)
    local k = sent("FHNEAR"); k = k[#k]
    H.eq(ns.Social.Decode(k.msg).kind, "K"); H.eq(k.target, "Anduin")
    local n = #sent("FHNEAR"); click(row.button)
    H.eq(#sent("FHNEAR"), n, "one knock per player per half minute")
    -- they come over
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 2, 2), "YELL", "Anduin")
    S:Refresh(true); click(row.button)
    hear(ns, theirCard(ns, "A", "Player-1-BB", "PRIEST", 7, 2, 2), "WHISPER", "Anduin")
    local duel = sent("FHDUEL")
    H.eq(#duel, 1, "now the ordinary challenge goes out")
    H.eq(duel[1].channel, "WHISPER"); H.eq(duel[1].target, "Anduin")
    H.ok(duel[1].msg:find(";HI;", 1, true), "a HELLO, the same one /fh duel sends")
    H.notOk(S.window:IsShown(), "and Social gets out of the way")
    H.eq(Main.vouched, nil, "the vouch does not outlive the click")
  end)
end)

H.suite("social ui: a Duel nobody answers says so, and a knock shows on their screen", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 4, 3), "YELL", "Anduin")
    S:Show(); click(S.nearCol.rows[1].button)
    Stub.Advance(6)
    H.ok(S.nearCol.foot:GetText():find("No answer from Anduin", 1, true), S.nearCol.foot:GetText())
    H.eq(#sent("FHDUEL"), 0)
    S.window:Hide(); Stub.Advance(ns.Social.POPUP_GAP)
    -- a knock from someone we know of
    hear(ns, ns.Social.Encode("K", "Player-1-BB"), "WHISPER", "Anduin")
    H.ok(S.popup.frame:IsShown()); H.eq(S.popup.title:GetText(), "Anduin wants a game!")
    Stub.Advance(10)
    hear(ns, ns.Social.Encode("K", "Player-1-BB"), "WHISPER", "Anduin")
    H.notOk(S.popup.frame:IsShown(), "but not over and over")
    hear(ns, ns.Social.Encode("K", "Player-1-ZZ"), "WHISPER", "Stranger")
    H.notOk(S.popup.frame:IsShown(), "and never from someone who has shown no card")
  end)
end)

H.suite("social ui: questions are answered only by players willing to be challenged", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    local n = #sent("FHNEAR")
    hear(ns, theirCard(ns, "Q", "Player-1-BB", "PRIEST", 7, 4, 3), "WHISPER", "Anduin")
    local a = sent("FHNEAR")
    H.eq(#a, n + 1); H.eq(a[#a].target, "Anduin"); H.eq(ns.Social.Decode(a[#a].msg).kind, "A")
    H.eq(S:Count(), 1, "and the asker is someone we now know plays")
    hear(ns, theirCard(ns, "Q", "Player-1-BB", "PRIEST", 7, 4, 3), "WHISPER", "Anduin")
    H.eq(#sent("FHNEAR"), n + 1, "asked again at once: not answered again")
    Main:DuelPrivacy().policy = "nobody"
    hear(ns, theirCard(ns, "Q", "Player-1-CC", "ROGUE", 7, 4, 3), "WHISPER", "Valeera")
    H.eq(#sent("FHNEAR"), n + 1, "challenges off: where you stand is nobody's business")
    Main:DuelPrivacy().policy = "anyone"; S:SetVisible(false)
    hear(ns, theirCard(ns, "Q", "Player-1-DD", "ROGUE", 7, 4, 3), "WHISPER", "Edwin")
    H.eq(#sent("FHNEAR"), n + 1, "hidden: likewise")
    -- a beacon that arrives as a whisper, or a question shouted, is not what it claims
    S:SetVisible(true)
    local known = S:Count()
    hear(ns, theirCard(ns, "B", "Player-1-EE", "MAGE", 7, 4, 3), "WHISPER", "Jaina")
    hear(ns, theirCard(ns, "Q", "Player-1-FF", "MAGE", 7, 4, 3), "YELL", "Khadgar")
    H.eq(S:Count(), known)
    -- junk from the wire is dropped without a fault
    hear(ns, "B;1;;;;;;", "YELL", "Junk"); hear(ns, ("x"):rep(250), "YELL", "Junk")
    H.eq(S.faulted, nil); H.eq(S:Count(), known)
  end)
end)

H.suite("social ui: when beacons are not carried, the player you point at is asked instead", function(ns, H)
  withSocial(ns, function(Main, S)
    C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
      Stub.R.calls[#Stub.R.calls + 1] = { what = "SendAddonMessage", args = { prefix, msg, channel, target } }
      if channel == "YELL" or channel == "SAY" then return 4 end     -- InvalidChatType
      return 0
    end
    Stub.units.mouseover = { name = "Anduin", class = "PRIEST", isPlayer = true, guid = "Player-1-BB" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    H.eq(#sent("FHNEAR"), 0, "no questions while beacons may yet work")
    Stub.Advance(20)
    H.eq(S.state.broadcast, "refused")
    H.ok(S:Report():find("refused by this client", 1, true), S:Report())
    H.ok(S:Report():find("yell refused, say refused, channel refused", 1, true), S:Report())
    local n = #sent("FHNEAR")
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    local q = sent("FHNEAR")
    H.eq(#q, n + 1); H.eq(q[#q].channel, "WHISPER"); H.eq(q[#q].target, "Anduin")
    Stub.Fire("UPDATE_MOUSEOVER_UNIT"); Stub.Advance(10); Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    H.eq(#sent("FHNEAR"), n + 1, "asked once, not every time the pointer crosses them")
    Stub.units.mouseover = { name = "Wolf", isPlayer = false, guid = "Creature-1" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    Stub.units.mouseover = Stub.units.player
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    H.eq(#sent("FHNEAR"), n + 1, "never a creature, never yourself")
    -- their answer lists them and announces them
    hear(ns, theirCard(ns, "A", "Player-1-BB", "PRIEST", 7), "WHISPER", "Anduin")
    Stub.Advance(2)
    H.eq(S:Count(), 1); H.ok(S.popup.frame:IsShown())
    H.eq(S.popup.rows[1].button.text:GetText(), "Duel")
    H.ok(S.popup.rows[1].sub:GetText():find("nearby", 1, true))
  end)
end)

H.suite("social ui: the guild answers a roll-call, and the board keeps what it hears", function(ns, H)
  local db = {}
  withSocial(ns, function(Main, S)
    Stub.Advance(30)
    local lines = sent("FHNEAR")
    local asked, said
    for _, l in ipairs(lines) do
      if l.channel == "GUILD" then
        local m = ns.Social.Decode(l.msg)
        asked = asked or m.kind == "R"; said = said or (m.kind == "G" and m)
      end
    end
    H.ok(asked, "the guild is asked once at login"); H.ok(said, "and told our own rank")
    H.eq(said.rank, 12); H.eq(said.stars, 2); H.eq(said.class, "MAGE")
    -- guildmates report in
    hear(ns, ns.Social.GuildLine({ guid = "Player-1-G1", class = "WARLOCK", rank = 3, stars = 4, wins = 80, losses = 60 }), "GUILD", "Guldan-Realm")
    hear(ns, ns.Social.GuildLine({ guid = "Player-1-G2", class = "DRUID", rank = 0, legend = 77 }), "GUILD", "Malfurion-Realm")
    hear(ns, ns.Social.GuildLine({ guid = "Player-1-G3", class = "HUNTER", rank = 25 }), "WHISPER", "Imposter")
    H.eq(db.social.guilds["Tavern Regulars"]["Imposter"], nil, "a guild line that did not come on guild chat is ignored")
    S:Show()
    local g = S.guildCol
    H.ok(g.title:GetText():find("Tavern Regulars", 1, true))
    H.ok(g.rows[1].name:GetText():find("Malfurion", 1, true), "Legend leads: " .. tostring(g.rows[1].name:GetText()))
    H.eq(g.rows[1].right:GetText(), "Legend 77"); H.eq(g.rows[1].sub:GetText(), "Druid")
    H.ok(g.rows[2].name:GetText():find("Guldan", 1, true)); H.eq(g.rows[2].right:GetText(), "Rank 3")
    H.ok(g.rows[3].name:GetText():find("(you)", 1, true), "and you are on it: " .. tostring(g.rows[3].name:GetText()))
    H.eq(g.rows[3].right:GetText(), "Rank 12")
    H.notOk(g.rows[4].name:IsShown()); H.notOk(g.prev:IsShown(), "one page needs no arrows")
    -- someone else's roll-call is answered, a moment later, once
    Stub.Advance(60)
    local n = #sent("FHNEAR")
    hear(ns, ns.Social.Encode("R"), "GUILD", "Guldan-Realm")
    hear(ns, ns.Social.Encode("R"), "GUILD", "Malfurion-Realm")
    Stub.Advance(6)
    local after = sent("FHNEAR")
    local answers = 0
    for i = n + 1, #after do if after[i].channel == "GUILD" then answers = answers + 1 end end
    H.eq(answers, 1)
    -- a ladder game later, the guild hears the new rank without being asked
    Stub.Advance(40); n = #sent("FHNEAR")
    Main:Ladder().rank = 11; Stub.Advance(3)
    after = sent("FHNEAR")
    local told
    for i = n + 1, #after do
      local m = after[i].channel == "GUILD" and ns.Social.Decode(after[i].msg)
      if m and m.kind == "G" then told = m.rank end
    end
    H.eq(told, 11)
  end, { guild = "Tavern Regulars", db = db })
  -- next login: nobody has spoken yet, and they are still on the board, dimmed
  withSocial(ns, function(Main, S)
    S:Show()
    local g = S.guildCol
    H.ok(g.rows[1].name:GetText():find("Malfurion", 1, true), "kept across a logout")
    H.ok(g.rows[1].sub:GetText():find("offline", 1, true), g.rows[1].sub:GetText())
    H.ok(g.rows[1].name:GetAlpha() < 1, "and dimmed")
    H.eq(g.rows[3].name:GetAlpha(), 1, "your own row is not")
  end, { guild = "Tavern Regulars", db = db })
end)

H.suite("social ui: a long guild turns pages, and no guild says so", function(ns, H)
  local store = {}
  for i = 1, 19 do
    store[("Member%02d-Realm"):format(i)] = { guid = "Player-1-M" .. i, class = "MAGE", rank = i, stars = 0, seen = os.time() }
  end
  withSocial(ns, function(Main, S)
    S:Show()
    local g = S.guildCol
    H.ok(g.next:IsShown()); H.eq(g.foot:GetText(), "Page 1 of 3")
    H.ok(g.rows[1].name:GetText():find("Member01", 1, true)); H.eq(g.rows[1].place:GetText(), "1")
    click(g.next)
    H.eq(g.foot:GetText(), "Page 2 of 3"); H.eq(g.rows[1].place:GetText(), "9")
    click(g.next); click(g.next)
    H.eq(g.foot:GetText(), "Page 3 of 3")
    H.ok(g.rows[4].name:IsShown()); H.notOk(g.rows[5].name:IsShown(), "twenty rows: four on the last page")
  end, { guild = "Big Guild", db = { social = { guilds = { ["Big Guild"] = store } } } })
  withSocial(ns, function(Main, S)
    S:Show()
    H.ok(S.guildCol.empty:IsShown()); H.ok(S.guildCol.empty:GetText():find("not in a guild", 1, true))
    H.ok(S.nearCol.empty:IsShown()); H.ok(S.nearCol.empty:GetText():find("Nobody nearby", 1, true))
    for _, l in ipairs(sent("FHNEAR")) do H.ok(l.channel ~= "GUILD", "nothing is said to a guild you are not in") end
  end)
end)

H.suite("social ui: the menu, the settings and the slash commands all reach it", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    Main:ShowHub()
    local plaque = Main.hub.social
    H.ok(plaque and plaque:IsShown(), "the menu has a Social plaque")
    H.eq(plaque.text:GetText(), "Social")
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 300, 300), "YELL", "Anduin")
    Stub.Advance(1.2)
    H.eq(plaque.text:GetText(), "Social (1 nearby)", "which counts who is near")
    click(plaque)
    H.ok(S.window:IsShown())
    -- the two switches, on Social
    local d = S.window
    H.eq(d.popupToggle.text:GetText(), "Nearby pop-up: On")
    click(d.popupToggle)
    H.eq(d.popupToggle.text:GetText(), "Nearby pop-up: Off"); H.notOk(S:PopupEnabled())
    H.eq(ForeverHearthstoneDB.social.popup, false, "saved")
    click(d.visibleToggle)
    H.eq(d.visibleToggle.text:GetText(), "Visible to nearby players: Off")
    H.ok(S.nearCol.rows[1].name:IsShown(), "those already heard stay listed")
    d:Hide()
    -- and in Settings
    Main:Settings("general")
    local st = Main.settings
    H.eq(st.social[1].text:GetText(), "Nearby player pop-up: Off")
    click(st.social[1])
    H.eq(st.social[1].text:GetText(), "Nearby player pop-up: On"); H.ok(S:PopupEnabled())
    click(st.social[2]); H.ok(S:Visible())
    st:Hide()
    -- practice hides the plaque with the rest of the main menu
    Main.hub.botMode = true; Main.hub:Layout()
    H.notOk(plaque:IsShown())
    Main.hub.botMode = false; Main.hub:Layout()
    -- slash commands
    SlashCmdList.FOREVERHEARTHSTONE("nearby quiet"); H.notOk(S:PopupEnabled())
    SlashCmdList.FOREVERHEARTHSTONE("nearby off"); H.notOk(S:Visible())
    SlashCmdList.FOREVERHEARTHSTONE("nearby on"); H.ok(S:PopupEnabled() and S:Visible())
    local chat = #Stub.R.chat
    SlashCmdList.FOREVERHEARTHSTONE("nearby")
    H.ok(Stub.R.chat[chat + 1]:find("nearby: broadcast", 1, true), Stub.R.chat[chat + 1])
    SlashCmdList.FOREVERHEARTHSTONE("social"); H.ok(S.window:IsShown())
  end)
end)

H.suite("social ui: an older client's duel traffic is untouched by any of it", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    -- a 1.2.1 client never registered FHNEAR; what it does send still works
    Stub.units.target = { name = "Foe", class = "PRIEST", isPlayer = true, guid = "Player-1-FOE", pos = { 1, 1, 0 } }
    Stub.interactDistance = true
    H.ok(Main:Challenge(), "challenging a target is as it was")
    local duel = sent("FHDUEL")
    H.eq(#duel, 1); H.eq(duel[1].target, "Foe")
    -- and a duel line arriving on the duel prefix never reaches Social
    local known = S:Count()
    Stub.Fire("CHAT_MSG_ADDON", "FHDUEL", "B;1;Player-1-XX;MAGE;3;;1;1;0", "WHISPER", "Foe")
    H.eq(S:Count(), known); H.eq(S.faulted, nil)
    -- while a challenge is out, we stop announcing ourselves
    local n = #sent("FHNEAR")
    S.state.lastBeaconAt = nil; Stub.Advance(3)
    local after = sent("FHNEAR")
    for i = n + 1, #after do H.ok(after[i].channel ~= "YELL" and after[i].channel ~= "SAY", "no beacon mid-challenge") end
  end)
end)

H.suite("social ui: /fh nearby test previews both screens and sends nothing", function(ns, H)
  withSocial(ns, function(Main, S)
    Stub.Advance(20)
    local n = #sent()
    SlashCmdList.FOREVERHEARTHSTONE("nearby test")
    local p = S.popup
    H.ok(p.frame:IsShown(), "the pop-up, as it will look")
    H.ok(p.rows[3].button:IsShown()); H.ok(p.more:GetText():find("and 2 more", 1, true), p.more:GetText())
    click(p.frame)
    H.ok(S.guildCol.title:GetText():find("Preview", 1, true), "and a made-up guild for a character without one")
    H.eq(S.guildCol.rows[1].right:GetText(), "Legend 41")
    H.ok(S.guildCol.rows[3].sub:GetText():find("offline", 1, true))
    H.eq(S.nearCol.rows[1].button.text:GetText(), "Duel"); H.eq(S.nearCol.rows[2].button.text:GetText(), "Knock")
    click(S.nearCol.rows[1].button); click(S.nearCol.rows[2].button)
    H.ok(S.nearCol.foot:GetText():find("only a preview", 1, true), S.nearCol.foot:GetText())
    H.eq(#sent(), n, "nothing was sent to anyone")
    H.eq(next(ForeverHearthstoneDB.social.guilds), nil, "and nothing was saved")
  end)
end)

H.suite("social: players heard zone-wide are near only within range", function(ns, H)
  local S = ns.Social
  local s = S.New()
  local here = { x = 0, y = 0, instance = 0 }
  s:Hear(1, "Close", card(S, "B", "G-C", "MAGE", 5, 100, 0), "zone")
  s:Hear(2, "AcrossTheZone", card(S, "B", "G-F", "MAGE", 5, S.LIST_RANGE + 500, 0), "zone")
  s:Hear(3, "NoFix", card(S, "B", "G-N", "MAGE", 5), "zone")
  s:Hear(4, "Earshot", card(S, "B", "G-E", "MAGE", 5), "beacon")
  local names = {}
  for i, e in ipairs(s:List(here)) do names[i] = e.name end
  H.eq(table.concat(names, ","), "Close,Earshot", "the zone channel is not a list of the whole zone")
  H.eq(s:CountNear(here), 2); H.eq(s.count, 4, "they are remembered, in case they ride closer")
  H.eq(s:PopupDue(5, here, { enabled = true }), nil, "100 yards is listed, not announced")
  s:Hear(6, "AcrossTheZone", card(S, "B", "G-F", "MAGE", 5, 30, 0), "zone")
  H.eq(s:PopupDue(7, here, { enabled = true }).rows[1].name, "AcrossTheZone", "until they do")
end)

--- A client like Forever: SAY and YELL refused, custom channels allowed.
local function foreverClient(joined)
  C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
    Stub.R.calls[#Stub.R.calls + 1] = { what = "SendAddonMessage", args = { prefix, msg, channel, target } }
    if channel == "YELL" or channel == "SAY" then return 4 end
    return 0
  end
  _G.C_Map = { GetBestMapForUnit = function() return Stub.zoneMap or 1429 end }
  _G.JoinTemporaryChannel = function(name) joined[name] = true; joined[#joined + 1] = name end
  _G.LeaveChannelByName = function(name) joined[name] = nil; joined[#joined + 1] = "-" .. name end
  _G.GetChannelName = function(name) return joined[name] and 5 or 0, name end
  _G.ChatFrame1 = {}
  _G.ChatFrame_RemoveChannel = function(frame, name) joined.hidden = name end
end
local function restoreClient()
  _G.C_Map, _G.JoinTemporaryChannel, _G.LeaveChannelByName, _G.GetChannelName = nil, nil, nil, nil
  _G.ChatFrame1, _G.ChatFrame_RemoveChannel, Stub.zoneMap = nil, nil, nil
end

H.suite("social ui: where say and yell are refused, the zone's own channel carries the beacons", function(ns, H)
  local joined = {}
  local ok, err = pcall(withSocial, ns, function(Main, S)
    foreverClient(joined)
    Stub.Advance(19)
    H.eq(#joined, 0, "not joined before the game's own channels are in")
    Stub.Advance(30)
    H.eq(joined[1], "FHN1429", "one channel for the zone you are in")
    H.eq(joined.hidden, "FHN1429", "taken off the chat windows, so it never prints")
    local line
    for _, l in ipairs(sent("FHNEAR")) do if l.channel == "CHANNEL" then line = l end end
    H.ok(line, "the beacon goes out on it"); H.eq(line.target, 5, "addressed by the channel's number")
    H.eq(ns.Social.Decode(line.msg).kind, "B")
    -- our own line coming back confirms it, and glancing stops
    hear(ns, line.msg, "CHANNEL", "Tester")
    H.eq(S.state.broadcast, "ok"); H.notOk(S.state:GlanceMode())
    H.ok(S:Report():find("working, zone channel FHN1429", 1, true), S:Report())
    -- two players in the zone: one close, one a mile off
    hear(ns, theirCard(ns, "B", "Player-1-BB", "PRIEST", 7, 30, 40), "CHANNEL", "Anduin")
    hear(ns, theirCard(ns, "B", "Player-1-CC", "ROGUE", 2, 1800, 0), "CHANNEL", "Valeera")
    H.eq(S:Count(), 1, "only the close one is nearby")
    Stub.Advance(2)
    H.ok(S.popup.frame:IsShown()); H.eq(S.popup.rows[1].name:GetText(), "Anduin")
    H.notOk(S.popup.rows[2].button:IsShown())
    -- riding into the next zone changes channel
    Stub.zoneMap = 1453; Stub.Advance(15)
    H.eq(joined["FHN1429"], nil, "the old zone's channel is left"); H.ok(joined["FHN1453"], "and the new one joined")
    -- hiding leaves it altogether
    S:SetVisible(false); Stub.Advance(3)
    H.eq(joined["FHN1453"], nil, "a hidden player is not in the channel at all")
  end)
  restoreClient()
  if not ok then error(err, 0) end
end)

H.suite("social ui: with no broadcast at all, anyone you hear or group with is asked", function(ns, H)
  withSocial(ns, function(Main, S)
    C_ChatInfo.SendAddonMessage = function(prefix, msg, channel, target)
      Stub.R.calls[#Stub.R.calls + 1] = { what = "SendAddonMessage", args = { prefix, msg, channel, target } }
      if channel == "WHISPER" or channel == "GUILD" then return 0 end
      return 4
    end
    Stub.Fire("CHAT_MSG_SAY", "hello there", "Anduin-Realm", "", "", "", "", 0, 0, "", 0, 1, "Player-1-BB")
    H.eq(#sent("FHNEAR"), 0, "nobody is asked while a broadcast may yet work")
    Stub.Advance(60)
    H.eq(S.state.broadcast, "refused")
    local n = #sent("FHNEAR")
    Stub.Fire("CHAT_MSG_SAY", "hello there", "Anduin-Realm", "", "", "", "", 0, 0, "", 0, 1, "Player-1-BB")
    local q = sent("FHNEAR")
    H.eq(#q, n + 1, "someone who speaks within earshot is asked"); H.eq(q[#q].target, "Anduin-Realm")
    H.eq(ns.Social.Decode(q[#q].msg).kind, "Q")
    Stub.Fire("CHAT_MSG_SAY", "again", "Anduin-Realm", "", "", "", "", 0, 0, "", 0, 2, "Player-1-BB")
    Stub.Fire("CHAT_MSG_TEXT_EMOTE", "You wave.", "Tester", "", "", "", "", 0, 0, "", 0, 3, ME)
    H.eq(#sent("FHNEAR"), n + 1, "once each, and never yourself")
    Stub.Advance(5)
    Stub.Fire("CHAT_MSG_TEXT_EMOTE", "Valeera waves.", "Valeera", "", "", "", "", 0, 0, "", 0, 4, "Player-1-CC")
    H.eq(sent("FHNEAR")[n + 2].target, "Valeera", "an emote counts too")
    -- the party, without anyone pointing at anything
    _G.IsInGroup = function() return true end
    Stub.units.party1 = { name = "Jaina", class = "MAGE", isPlayer = true, guid = "Player-1-DD" }
    Stub.Advance(5)
    _G.IsInGroup = nil
    local last = sent("FHNEAR"); last = last[#last]
    H.eq(last.target, "Jaina"); H.eq(last.channel, "WHISPER")
  end)
end)

H.suite("social: a player on another layer of the zone is not near", function(ns, H)
  local S = ns.Social
  local here = { x = 0, y = 0, instance = 0 }
  local function zoneCard(guid, layer)
    return S.Decode(S.Card("B", { guid = guid, class = "MAGE", rank = 5, layer = layer }, { x = 10, y = 0, instance = 0 }))
  end
  H.eq(zoneCard("G-1", "4471").layer, "4471", "the layer rides in the card")
  H.eq(S.Decode("B;1;G-1;MAGE;5;;10;0;0;not a layer!").layer, nil, "junk is no layer")
  H.eq(S.Decode("B;1;G-1;MAGE;5;;10;0;0").layer, nil, "a beta.1 card has none")
  local s = S.New(); s.layer = "4471"
  s:Hear(1, "Same", zoneCard("G-S", "4471"), "zone")
  s:Hear(2, "Other", zoneCard("G-O", "9002"), "zone")
  s:Hear(3, "Untold", zoneCard("G-U", nil), "zone")
  s:Hear(4, "Earshot", zoneCard("G-E", "9002"), "beacon")
  local names, unsure = {}, {}
  for i, e in ipairs(s:List(here)) do names[i] = e.name; unsure[e.name] = e.unsure end
  table.sort(names)
  H.eq(table.concat(names, ","), "Earshot,Other,Same,Untold", "nobody is hidden on a number: it differs between creatures in one place")
  H.notOk(unsure.Same); H.notOk(unsure.Earshot, "heard in earshot is here, whatever their card says")
  H.ok(unsure.Untold and unsure.Other, "no value in common: listed, marked unconfirmed")
  H.eq(s:CountNear(here), 4)
  local due = s:PopupDue(5, here, { enabled = true })
  H.eq(due.total, 4)
  -- several marks each: one in common is enough
  s = S.New(); s.layer = "111.222.333"
  s:Hear(1, "Shares", zoneCard("G-1", "999.222"), "zone")
  s:Hear(2, "SharesNot", zoneCard("G-2", "999.888"), "zone")
  H.eq(S.Layer(s.nearby["G-1"], s.layer), "same"); H.eq(S.Layer(s.nearby["G-2"], s.layer), "unknown")
  H.eq(S.Decode(S.Card("B", { guid = "G", class = "MAGE", rank = 5, layer = "111.222.333" })).layer, "111.222.333")
  -- a client that cannot read its own layer trusts nobody's, but hides nobody
  s = S.New()
  s:Hear(1, "Anyone", zoneCard("G-A", "4471"), "zone")
  H.eq(S.Layer(s.nearby["G-A"], s.layer), "unknown"); H.eq(s:CountNear(here), 1)
end)

H.suite("social ui: the layer is read from creatures, sent, and decides who can be duelled untargeted", function(ns, H)
  local joined = {}
  local ok, err = pcall(withSocial, ns, function(Main, S)
    foreverClient(joined)
    Stub.Advance(50)
    H.ok(S:Report():find("Layer unknown", 1, true), S:Report())
    -- a player's pet says nothing; a creature does
    Stub.units.target = { name = "Imp", guid = "Creature-0-4170-0-9999-416-00001A2B3C", playerControlled = true }
    Stub.Fire("PLAYER_TARGET_CHANGED")
    H.eq(S.state.layer, nil, "a summoned pet may be from anywhere")
    Stub.units.mouseover = { name = "Wolf", guid = "Creature-0-4170-0-4471-299-00001A2B3C" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    H.eq(S.state.layer, "4471")
    H.ok(S:Report():find("Layer marks 4471", 1, true), S:Report())
    Stub.units.mouseover = { name = "Somebody", isPlayer = true, guid = "Player-1-0000FFFF" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    H.eq(S.state.layer, "4471", "a player's GUID is not a layer")
    S.state.lastBeaconAt = nil; Stub.Advance(2)
    local line
    for _, l in ipairs(sent("FHNEAR")) do if l.channel == "CHANNEL" then line = l end end
    H.eq(ns.Social.Decode(line.msg).layer, "4471", "and it goes out in the beacon")
    local function zone(guid, name, layer, x)
      hear(ns, ns.Social.Card("B", { guid = guid, class = "PRIEST", rank = 7, layer = layer }, { x = x, y = 0, instance = 0 }), "CHANNEL", name)
    end
    zone("Player-1-BB", "Anduin", "4471", 4)
    zone("Player-1-CC", "Valeera", "9002", 4)
    zone("Player-1-DD", "Jaina", nil, 4)
    H.eq(S:Count(), 3, "nobody is hidden for holding a different number")
    S:Show()
    local rows = S.nearCol.rows
    local byName = {}
    for i = 1, 3 do byName[rows[i].name:GetText()] = rows[i] end
    H.ok(byName.Anduin and byName.Jaina and byName.Valeera)
    H.ok(byName.Jaina.sub:GetText():find("~", 1, true), "unconfirmed is marked: " .. byName.Jaina.sub:GetText())
    H.ok(byName.Valeera.sub:GetText():find("~", 1, true), "and so is a different number")
    H.notOk(byName.Anduin.sub:GetText():find("~", 1, true))
    H.ok(S.nearCol.foot:GetText():find("not confirmed on your layer", 1, true), S.nearCol.foot:GetText())
    -- a second creature with another number: both are kept, and both are sent
    Stub.units.mouseover = { name = "Bear", guid = "Creature-0-4170-0-7007-822-00001A2B3C" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT")
    H.eq(S.state.layer, "7007.4471", "the number changes from creature to creature; the last few are all ours")
    hear(ns, ns.Social.Card("B", { guid = "Player-1-EE", class = "DRUID", rank = 3, layer = "1.7007" }, { x = 9, y = 0, instance = 0 }), "CHANNEL", "Malfurion")
    H.eq(ns.Social.Layer(S.state.nearby["Player-1-EE"], S.state.layer), "same", "one in common confirms it")
    S.state:Forget("Player-1-EE"); S:Refresh(true)
    -- Jaina: unconfirmed, but Duel is not held back on that for now -- she is
    -- asked where she stands like anyone else
    local n = #sent("FHNEAR")
    click(byName.Jaina.button)
    H.eq(#sent("FHNEAR"), n + 1, "the layer does not gate a challenge"); H.eq(sent("FHNEAR")[n + 1].target, "Jaina")
    H.eq(#sent("FHDUEL"), 0, "her position still does")
    S.pending = nil
    -- Anduin: the question goes out, and the answer beside us is a challenge
    click(byName.Anduin.button)
    hear(ns, ns.Social.Card("A", { guid = "Player-1-BB", class = "PRIEST", rank = 7, layer = "4471" }, { x = 3, y = 0, instance = 0 }), "WHISPER", "Anduin")
    H.eq(#sent("FHDUEL"), 1); H.eq(sent("FHDUEL")[1].target, "Anduin")
    Main:Decline(); Main.session = nil
    -- an answer carrying other marks is still a challenge, while that is the owner's call
    S:Show(); S:Refresh(true); click(S.nearCol.rows[1].button)
    local duelLines = #sent("FHDUEL")
    hear(ns, ns.Social.Card("A", { guid = "Player-1-BB", class = "PRIEST", rank = 7, layer = "9002" }, { x = 3, y = 0, instance = 0 }), "WHISPER", "Anduin")
    H.eq(#sent("FHDUEL"), duelLines + 1)
    Main:Decline(); Main.session = nil
    -- riding into the next zone, or joining a group, forgets the layer
    Stub.zoneMap = 1453; Stub.Advance(2)
    H.eq(S.state.layer, nil)
    Stub.units.mouseover = { name = "Somebody", isPlayer = true, guid = "Player-1-0000FFFF" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT"); H.eq(S.state.layer, nil, "a player under the pointer does not bring it back")
    Stub.units.mouseover = { name = "Boar", guid = "Creature-0-4170-0-5120-113-00001A2B3C" }
    Stub.Fire("UPDATE_MOUSEOVER_UNIT"); H.eq(S.state.layer, "5120")
    Stub.Fire("GROUP_ROSTER_UPDATE"); H.eq(S.state.layer, nil)
  end)
  restoreClient()
  if not ok then error(err, 0) end
end)
