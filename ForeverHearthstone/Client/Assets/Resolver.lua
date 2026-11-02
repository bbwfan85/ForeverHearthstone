--[[ Client/Assets/Resolver.lua

  ASSET RESOLUTION WITH A GUARANTEED FLOOR.

  THE CONSTRAINT THAT SHAPES THIS FILE:

  There is no reliable way to ask WoW whether a texture path exists. SetTexture
  on a bad path does not error and does not return false -- it silently draws
  nothing. Combined with the fact that the default tier ships ZERO art bytes and
  borrows the client's own Interface\Icons (683 slots: 535 cards, 130 tokens,
  9 heroes, 9 hero powers), that means a meaningful number of icon paths WILL be
  wrong, and the addon cannot detect it.

  Therefore: art is an ENHANCEMENT, never a dependency. Every card resolves to a
  descriptor that renders a complete, readable, playable card using only solid
  colours and text. The icon and the 3-D model layer on top when they happen to
  work. A card with no valid art looks plain; it never looks broken, and it is
  never unplayable.

  This is also why no icon path in this project is ever authored from memory.
  Paths live in a manifest that is filled by whoever can actually see the game.
  The one certainty is INV_Misc_QuestionMark, WoW's canonical missing-icon
  texture, used as the last art tier.

  The ~20 generic paths in Client/Assets/GenericArt.lua are the deliberate
  middle ground: they are CANDIDATES, shipped because "every card has a
  class-and-race-appropriate icon" is most of the perceived difference, and
  audited by an eye through `/fh icons` because an eye is the only verifier this
  class of data can have. A candidate that turns out to be blank is deleted from
  the manifest and the chain below simply falls through, which is why a wrong
  guess costs nothing worse than a question mark.

  NO WoW API IN THIS FILE. It is pure logic so it can be tested headless, the
  same rule as Engine/. The WoW binding lives in Client/UI/.
]]
local ADDON, ns = ...

local Resolver = {}
Resolver.__index = Resolver
ns.Resolver = Resolver

local ICON_ROOT = [[Interface\Icons\]]
local MISSING   = ICON_ROOT .. "INV_Misc_QuestionMark"

--[[ Rarity gem colours. These are OUR presentation choices, not Hearthstone
     assets -- flat colours chosen to be distinguishable in both the default and
     a user's asset pack. Hearthstone's own gem art is not shipped. ]]
local RARITY_COLOR = {
  FREE      = { 0.62, 0.62, 0.62 },
  COMMON    = { 0.78, 0.78, 0.78 },
  RARE      = { 0.16, 0.44, 0.94 },
  EPIC      = { 0.64, 0.21, 0.93 },
  LEGENDARY = { 1.00, 0.50, 0.00 },
}

--[[ Class colours are deliberately NOT hardcoded. WoW already knows them
     (RAID_CLASS_COLORS), and reading the client's own values keeps us matching
     whatever Forever ships rather than asserting vanilla hexes from memory.
     A palette provider is injected so tests can supply their own. ]]
local NEUTRAL_COLOR = { 0.55, 0.52, 0.47 }

function Resolver.New(opts)
  opts = opts or {}
  local r = setmetatable({}, Resolver)
  r.printed   = opts.printed  or ns.PrintedCards or {}
  r.manifest  = opts.manifest or {}          -- shipped default tier
  r.override  = opts.override or {}          -- user's local asset pack
  r.palette   = opts.palette  or {}          -- class -> {r,g,b}
  r.useModels = opts.useModels ~= false
  r.stats = { override = 0, manifest = 0, generic = 0, fallback = 0, none = 0 }
  return r
end

-- ------------------------------------------------------------------ helpers

function Resolver:ClassColor(class)
  if not class or class == "NEUTRAL" then return NEUTRAL_COLOR end
  return self.palette[class] or NEUTRAL_COLOR
end

function Resolver:RarityColor(rarity)
  return RARITY_COLOR[rarity or "FREE"] or RARITY_COLOR.FREE
end

--[[ Generic per-type fallback. Kept deliberately tiny -- a handful of slots in
     the manifest rather than a table of paths in code, so that even these are
     supplied by someone who can verify them. Absent = fall through to MISSING. ]]
function Resolver:GenericIcon(printed)
  local m = self.manifest.generic
  if not m then return nil end
  local t = printed.type
  --[[ Most specific first: class+type, then RACE, then type, then class.

       Race sits above type because it is what makes a board readable at a
       glance -- a row of Beasts that all look like beasts reads instantly,
       where a row of identical generic minions reads as nothing. A card with no
       race simply skips the step. ]]
  return (t and printed.class and m[t .. "_" .. printed.class])
      or (printed.race and m["RACE_" .. printed.race])
      or (t and m[t])
      or (printed.class and m[printed.class])
      or m.DEFAULT
end

-- ------------------------------------------------------------------ resolve

--[[ Resolve one card to a complete render descriptor.

     `tier` records which source supplied the art, which is what the coverage
     report reads. It is diagnostic only -- nothing in the UI branches on it. ]]
function Resolver:Card(cardId)
  local p = self.printed[cardId]
  if not p then
    -- Even an unknown id must not crash the UI. It renders as a blank card
    -- carrying the id, which is far more useful than an error.
    return {
      cardId = cardId, name = tostring(cardId), missing = true,
      type = "MINION", class = "NEUTRAL", rarity = "FREE",
      icon = MISSING, tier = "none", legible = true,
      frameColor = NEUTRAL_COLOR, gemColor = RARITY_COLOR.FREE,
    }
  end

  local icon, tier

  local o = self.override[cardId]
  if o and o.icon then
    icon, tier = o.icon, "override"
  else
    local m = self.manifest.cards and self.manifest.cards[cardId]
    if m and m.icon then
      icon, tier = m.icon, "manifest"
    else
      local gi = self:GenericIcon(p)
      if gi then icon, tier = gi, "generic"
      else icon, tier = MISSING, "fallback" end
    end
  end
  self.stats[tier] = (self.stats[tier] or 0) + 1

  -- 3-D creature model, when one has been supplied for this card. Never
  -- required: a nil model simply means the art slot shows the icon instead.
  local model
  if self.useModels then
    model = (o and o.model) or (self.manifest.cards
             and self.manifest.cards[cardId]
             and self.manifest.cards[cardId].model) or nil
  end

  return {
    cardId = cardId,
    name   = p.name or cardId,
    text   = p.text,
    cost   = p.cost, atk = p.atk, hp = p.hp, dur = p.dur,
    type   = p.type, class = p.class, rarity = p.rarity, race = p.race,
    keywords = p.keywords,
    icon  = icon,
    model = model,
    tier  = tier,
    frameColor = self:ClassColor(p.class),
    gemColor   = self:RarityColor(p.rarity),
    -- A descriptor is ALWAYS renderable: name, cost and stats are printed data,
    -- so the card is legible even with every art path wrong.
    legible = true,
  }
end

--[[ Coverage report, for the authoring loop. Says how much of the pool has real
     art versus how much is falling through to generic or question-mark. This is
     the number that tells you whether an asset pack is worth installing. ]]
function Resolver:Coverage(ids)
  local n = { override = 0, manifest = 0, generic = 0, fallback = 0, total = 0 }
  for _, id in ipairs(ids) do
    local d = self:Card(id)
    n[d.tier] = (n[d.tier] or 0) + 1
    n.total = n.total + 1
  end
  n.real = n.override + n.manifest
  n.pct  = n.total > 0 and (100 * n.real / n.total) or 0
  return n
end

return Resolver
