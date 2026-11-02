--[[ tests/test_vault.lua -- the sealed collection (Client/Vault.lua, docs/13).

  Not uncrackable -- the source is right there -- but opening the saved
  variables in a text editor and typing a number must not work.
]]
local H = require("tests.harness")

H.suite("vault: a collection seals and opens again, exactly", function(ns, H)
  local V = ns.Vault
  local value = { cards = { EX1_116 = { n = 1, g = 0 }, CS2_182 = { n = 2 } }, dust = 345,
                  packs = { HEARTHSTONE = 4 }, flag = true, name = "semi;colon:s5:" }
  local sealed = V.Seal(value, "account")
  H.notOk(sealed.data:find("EX1_116", 1, true), "card ids are not readable in the file")
  local back = V.Open(sealed, "account")
  H.eq(back.dust, 345); H.eq(back.cards.EX1_116.n, 1); H.eq(back.packs.HEARTHSTONE, 4)
  H.eq(back.name, "semi;colon:s5:", "awkward strings survive")
  H.eq(V.Serialize(value), V.Serialize(back), "and nothing else changed")
end)

H.suite("vault: an edited vault fails, and the last good copy is used", function(ns, H)
  local V = ns.Vault
  local db = { cards = { EX1_116 = { n = 1 } }, dust = 100, packs = { HEARTHSTONE = 1 } }
  V.Store(db, nil)                       -- first logout
  db.dust = 120; db.cards = { EX1_116 = { n = 1 } }; db.packs = { HEARTHSTONE = 1 }
  V.Restore(db, nil)                     -- next login restores 100...
  H.eq(db.dust, 100, "the vault replaces the plain copy")
  db.dust = 130
  V.Store(db, nil)                       -- ...and a later logout seals 130
  -- someone edits the vault's data by hand
  local d = db.vault.data
  db.vault.data = d:sub(1, 10) .. (d:sub(11, 11) == "0" and "1" or "0") .. d:sub(12)
  local problems = V.Restore(db, nil)
  H.eq(problems[1] and problems[1].restored, true, "the edit is caught and the backup restored")
  H.eq(db.dust, 100, "from the previous good copy")
end)

H.suite("vault: typing a number into the plain file does nothing", function(ns, H)
  local V = ns.Vault
  local db = { cards = {}, dust = 5, packs = {} }
  V.Store(db, nil)
  H.eq(db.dust, nil, "the plain copy is not left in the file to tempt anyone")
  db.dust = 99999                        -- the Notepad edit
  V.Restore(db, nil)
  H.eq(db.dust, 5, "and an added one is ignored")
end)

H.suite("vault: a character's vault cannot be copied onto another character", function(ns, H)
  local V = ns.Vault
  local a = { cards = { CS2_029 = { n = 2 } }, record = { wins = 50, losses = 0 } }
  V.Store(nil, a, "character|Player-1")
  local b = { vault = a.vault }
  local problems = V.Restore(nil, b, "character|Player-2")
  H.eq(problems[1] and problems[1].restored, false, "it does not open for someone else")
  H.ok(b.tampered, "and the file is marked")
end)

--============================================================ docs/29

--[[ A version-1 seal, byte for byte what beta.1 and beta.2 wrote: the same
     key, only the older field list. ]]
local function sealV1(V, t, fields, salt)
  local pick = {}
  for _, f in ipairs(fields) do pick[f] = t[f] end
  local sealed = V.Seal(pick, salt)
  sealed.v = 1
  return sealed
end

H.suite("vault: a beta.2 file opens, and keeps its practice record", function(ns, H)
  local V = ns.Vault
  local cdb = { cards = { CS2_029 = { n = 2 } }, record = { wins = 3, losses = 1 } }
  cdb.vault = sealV1(V, cdb, { "cards", "record", "packMilestones", "bossKills" }, "character|P")
  cdb.cards, cdb.record = nil, nil
  cdb.practiceRecord = { wins = 7, losses = 2 }; cdb.level = 34; cdb.dryKills = 12
  local db = { cards = { CS2_182 = { n = 2 } }, dust = 40, packs = {} }
  db.vault = sealV1(V, db, V.ACCOUNT_FIELDS, "account")
  db.cards, db.dust = nil, nil
  local problems = V.Restore(db, cdb, "character|P")
  H.eq(#problems, 0, "no complaint")
  H.eq(cdb.cards.CS2_029.n, 2, "the cards open")
  H.eq(db.dust, 40, "and the dust")
  H.eq(cdb.practiceRecord.wins, 7, "fields the old vault never held are kept")
  H.eq(cdb.dryKills, 12)
  V.Store(db, cdb, "character|P")
  H.eq(cdb.practiceRecord, nil, "and are sealed from now on")
  cdb.practiceRecord = { wins = 999, losses = 0 }; cdb.level = 60
  V.Restore(db, cdb, "character|P")
  H.eq(cdb.practiceRecord.wins, 7, "an edit to them does nothing")
  H.eq(cdb.level, 34)
end)

H.suite("vault: deleting the vault and typing plain cards does nothing", function(ns, H)
  local V = ns.Vault
  local db = { cards = { EX1_002 = { n = 2 } }, dust = 99999, packs = { HEARTHSTONE = 50 } }
  local problems = V.Restore(db, nil)
  H.eq(db.dust, nil, "the unsealed dust is set aside")
  H.eq(db.cards, nil, "and the cards")
  H.ok(problems[1] and problems[1].unsealed, "and the player is told")
  local fresh = {}
  H.eq(#V.Restore(fresh, {}), 0, "a genuinely fresh install is left alone")
end)

H.suite("vault: a vault that will not open is never sealed over", function(ns, H)
  local V = ns.Vault
  local a = { cards = { CS2_029 = { n = 2 } } }
  V.Store(nil, a, "character|Player-1")
  local original = a.vault
  local b = { vault = original }
  V.Restore(nil, b, "character|Player-2")      -- e.g. the character's GUID changed
  b.cards = {}                                  -- the session played on with nothing
  V.Store(nil, b, "character|Player-2")
  V.Store(nil, b, "character|Player-2")         -- and a second logout
  H.ok(b.vault == original, "the unreadable vault is still there to recover")
  H.ok(V.Open(b.vault, "character|Player-1"), "and still opens for its owner")
end)

H.suite("vault: the saved level cannot grant cards", function(ns, H)
  local c = ns.Collection.New({}, { level = 60 })
  c:GrantForLevel("MAGE", 12)
  H.eq(c.character.level, 12, "WoW's level is the one that counts")
  local legendary = 0
  for id, n in pairs(c.character.cards) do
    local p = ns.PrintedCards[id]
    if p and p.rarity == "LEGENDARY" then legendary = legendary + 1 end
  end
  H.eq(legendary, 0, "no level-60 class cards at level 12")
end)
