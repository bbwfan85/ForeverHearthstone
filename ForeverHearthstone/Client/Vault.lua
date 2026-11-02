--[[ Client/Vault.lua

  THE COLLECTION, SEALED (docs/13).

  SavedVariables are plain Lua files: anyone can open ForeverHearthstone.lua in
  Notepad and give themselves every legendary. The brief is explicit that
  players are trusted and this is not meant to be uncrackable -- the source is
  right there -- but it should take more than a text editor.

  So at logout (and /reload, which is the same event) what matters -- the
  cards, dust, packs, duel record and grant bookkeeping -- is serialised,
  scrambled with a keyed stream and signed. At login the vault is opened and
  REPLACES whatever plain copy is in the file; an edited plain copy is simply
  ignored, and an edited vault fails its signature:

    * signature fails   -> the previous good vault (kept as a backup) is used
    * both fail         -> the plain data is kept, and the player is told the
                           collection file was modified (Vault.tampered)

  NO WoW API. Pure data in and out, so it is tested headless.
]]
local ADDON, ns = ...

local Vault = {}
ns.Vault = Vault

Vault.VERSION = 2
local KEY = "ForeverHearthstone/vault/1/kNd7-Qx2"

-- The fields sealed from each table. Everything else stays plain (settings,
-- decks -- a deck is validated against the collection anyway).
Vault.ACCOUNT_FIELDS = { "cards", "dust", "packs", "stats", "basicsGranted" }
Vault.CHAR_FIELDS    = { "cards", "record", "packMilestones", "bossKills",
                         "level", "dryKills", "practiceRecord" }
--[[ Fields a version-1 vault (beta.1, beta.2) never held. Opening one of those
     keeps the plain copy of these for one session; the logout after seals
     them. Without this the upgrade would wipe the practice record. ]]
Vault.ADDED_IN_2 = { level = true, dryKills = true, practiceRecord = true }

-- ======================================================== serialisation

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    return a < b
  end)
  return keys
end

--[[ Deterministic: keys sorted, so the same table always seals to the same
     bytes and the signature is stable. Strings are length-prefixed, so no
     escaping can go wrong. ]]
local function serialize(v, out)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "{"
    for _, k in ipairs(sortedKeys(v)) do
      serialize(k, out); serialize(v[k], out)
    end
    out[#out + 1] = "}"
  elseif t == "string" then
    out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "number" then
    out[#out + 1] = "n" .. ("%.17g"):format(v) .. ";"
  elseif t == "boolean" then
    out[#out + 1] = v and "T" or "F"
  else
    out[#out + 1] = "N"
  end
end

function Vault.Serialize(v)
  local out = {}
  serialize(v, out)
  return table.concat(out)
end

local function parse(s, i)
  local c = s:sub(i, i)
  if c == "{" then
    local t = {}
    i = i + 1
    while s:sub(i, i) ~= "}" do
      if i > #s then return nil, i end
      local k, v
      k, i = parse(s, i); if i == nil then return nil end
      v, i = parse(s, i); if i == nil then return nil end
      if k == nil then return nil end
      t[k] = v
    end
    return t, i + 1
  elseif c == "s" then
    local colon = s:find(":", i, true)
    if not colon then return nil end
    local n = tonumber(s:sub(i + 1, colon - 1))
    if not n then return nil end
    return s:sub(colon + 1, colon + n), colon + n + 1
  elseif c == "n" then
    local semi = s:find(";", i, true)
    if not semi then return nil end
    return tonumber(s:sub(i + 1, semi - 1)), semi + 1
  elseif c == "T" then return true, i + 1
  elseif c == "F" then return false, i + 1
  elseif c == "N" then return nil, i + 1 end
  return nil
end

function Vault.Deserialize(s)
  local ok, v, i = pcall(parse, s, 1)
  if not ok or i == nil or i ~= #s + 1 then return nil end
  return v
end

-- ============================================================ sealing

--[[ A keyed byte stream (a linear congruential generator seeded from the key)
     added to each byte, then hex. Scrambling, not encryption: the point is that
     a card count is not a number you can find and change. ]]
local function keystream(key)
  local seed = tonumber(ns.Protocol.Hash2(key):sub(1, 8), 16) or 1
  local state = seed
  return function()
    state = (state * 1103515245 + 12345) % 2147483648
    return math.floor(state / 65536) % 256
  end
end

local function scramble(s, key, dir)
  local ks = keystream(key)
  local out = {}
  for i = 1, #s do
    out[i] = string.char((s:byte(i) + dir * ks()) % 256)
  end
  return table.concat(out)
end

local function tohex(s)
  return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

local function fromhex(h)
  if #h % 2 == 1 or h:find("[^0-9a-f]") then return nil end
  return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

function Vault.Seal(value, salt)
  local key = KEY .. "|" .. tostring(salt or "")
  local plain = Vault.Serialize(value)
  local data = tohex(scramble(plain, key, 1))
  return { v = Vault.VERSION, data = data, sig = ns.Protocol.Hash2(key .. "|" .. data) }
end

--- The sealed value, or nil plus why.
function Vault.Open(sealed, salt)
  if type(sealed) ~= "table" or type(sealed.data) ~= "string" then return nil, "missing" end
  local key = KEY .. "|" .. tostring(salt or "")
  if ns.Protocol.Hash2(key .. "|" .. sealed.data) ~= sealed.sig then return nil, "signature" end
  local raw = fromhex(sealed.data)
  if not raw then return nil, "corrupt" end
  local value = Vault.Deserialize(scramble(raw, key, -1))
  if type(value) ~= "table" then return nil, "corrupt" end
  return value
end

-- ======================================================= the two tables

local function pick(t, fields)
  local out = {}
  for _, f in ipairs(fields) do out[f] = t[f] end
  return out
end

--[[ Seal `db` (account) and `cdb` (character) in place, keeping the previous
     good seal as a backup. The plain copies of the sealed fields are removed
     from the file, so there is nothing tempting left to edit. ]]
function Vault.Store(db, cdb, charSalt)
  --[[ A vault that could not be opened this session is left exactly as it is,
       with its backup. Sealing over it would seal whatever was on screen -- an
       empty collection -- and the logout after that would throw the unreadable
       original away for good. Kept, it can still be recovered. ]]
  if db and db.tampered then db = nil end
  if cdb and cdb.tampered then cdb = nil end
  if db then
    db.vaultBackup = db.vault
    db.vault = Vault.Seal(pick(db, Vault.ACCOUNT_FIELDS), "account")
    for _, f in ipairs(Vault.ACCOUNT_FIELDS) do db[f] = nil end
  end
  if cdb then
    cdb.vaultBackup = cdb.vault
    cdb.vault = Vault.Seal(pick(cdb, Vault.CHAR_FIELDS), charSalt or "character")
    for _, f in ipairs(Vault.CHAR_FIELDS) do cdb[f] = nil end
  end
end

--[[ Open the vaults into the plain fields the rest of the addon uses. Returns
     a list of problems for the player ("account", "character"): a vault that
     failed and was restored from its backup, or failed outright.

     A file with NO vault is a fresh install: every version that shipped
     seals at logout, so plain sealed fields with no vault beside them were
     typed in by hand (the vault deleted to get round it). They are dropped,
     and the grants that follow start the collection from level and set. ]]
function Vault.Restore(db, cdb, charSalt)
  local problems = {}
  local function restore(t, fields, salt, label)
    if not t then return end
    if not t.vault then
      local had = false
      for _, f in ipairs(fields) do
        if t[f] ~= nil then had = true; t[f] = nil end
      end
      if had then problems[#problems + 1] = { what = label, restored = false, unsealed = true } end
      return
    end
    local value = Vault.Open(t.vault, salt)
    local fromBackup = false
    if not value then
      value = Vault.Open(t.vaultBackup, salt)
      fromBackup = value ~= nil
    end
    if value then
      local sealedVersion = (fromBackup and t.vaultBackup or t.vault).v or 1
      for _, f in ipairs(fields) do
        if not (sealedVersion < 2 and Vault.ADDED_IN_2[f]) then t[f] = value[f] end
      end
      if fromBackup then problems[#problems + 1] = { what = label, restored = true } end
    else
      problems[#problems + 1] = { what = label, restored = false }
      t.tampered = true
    end
  end
  restore(db, Vault.ACCOUNT_FIELDS, "account", "account")
  restore(cdb, Vault.CHAR_FIELDS, charSalt or "character", "character")
  return problems
end

return Vault
