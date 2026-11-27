--[[ tests/test_liveproperties.lua -- do properties follow the LIVE minion?

  The bug class behind "a copy loses a granted deathrattle" has a mirror image:
  code that answers a question about a minion from its PRINTED card when the
  live minion says otherwise. A silenced Loot Hoarder still has "Deathrattle"
  printed on it, and Scarlet Purifier used to hit it; the printed tag was a
  fallback for every board minion.

  Two detectors, both run over every scripted card rather than chosen examples:

    1. SILENCE IS COMPLETE. A silenced minion must behave exactly like the same
       body with no card text at all. For every scripted minion, one battery of
       ordinary game actions runs twice -- once with the real card silenced, once
       with its script removed and the body silenced -- and the two games must
       end identical. Anything the engine reads from a script without checking
       Silence (an aura, a trigger, a static property like Velen's multiplier or
       Nozdormu's timer) shows up as a difference.

    2. "HAS DEATHRATTLE" MEANS THE LIVE LIST in play: printed, granted, silenced
       and in-hand variants of every deathrattle card, through both the
       Selector (Scarlet Purifier, Lil' Exorcist) and the payload condition
       (Undertaker).
]]
local H = require("tests.harness")

local YETI, WISP, MOONFIRE = "CS2_182", "CS2_231", "CS2_008"

-- ---------------------------------------------------------------- fingerprint

local function kwList(ns, e)
  local out = {}
  for k in pairs(ns.KEYWORD) do if e:Has(ns.KEYWORD[k]) then out[#out + 1] = k end end
  table.sort(out)
  return table.concat(out, "+")
end

local function entityPrint(ns, g, e)
  return ("%s %d/%d c%d [%s] t%d d%d%s%s a%d"):format(
    e.cardId, g:AttackValue(e), e:Health(), e:Cost(), kwList(ns, e),
    #(e.triggers or {}), #(e.deathrattles or {}),
    e.frozen and " F" or "", e.silenced and " S" or "",
    g:AttacksAllowed(e))
end

-- Everything a player could observe about the game, as one string per line.
local function fingerprint(ns, g)
  local lines = {
    ("turn %d active %d over %s rng %d"):format(g.turn, g.activePlayer, tostring(g.over), g.rngCalls or 0),
    ("turnSeconds %d"):format(g:TurnSeconds()),
  }
  for pi = 1, 2 do
    local p = g.players[pi]
    lines[#lines + 1] = ("P%d hero %d+%d mana %d/%d locked %d overload %d deck %d sp %d x%d dr%d heal->dmg %s hp->minion %s"):format(
      pi, p.hero:Health(), p.hero.armor, p.mana, p.maxMana, p.lockedMana or 0,
      p.pendingOverload or 0, #p.deck, g:SpellPower(pi), g:SpellMultiplier(pi),
      g:DeathrattleMultiplier(pi), tostring(g:HealsDealDamage(pi)),
      tostring(g:HeroPowerTargetsMinions(pi)))
    for i, e in ipairs(p.board) do lines[#lines + 1] = ("P%d board %d %s"):format(pi, i, entityPrint(ns, g, e)) end
    for i, e in ipairs(p.hand) do lines[#lines + 1] = ("P%d hand %d %s c%d"):format(pi, i, e.cardId, g:CardCost(e, pi)) end
    if p.weapon then lines[#lines + 1] = ("P%d weapon %s"):format(pi, entityPrint(ns, g, p.weapon)) end
    for i, s in ipairs(p.secrets) do lines[#lines + 1] = ("P%d secret %d %s"):format(pi, i, s.cardId) end
  end
  return lines
end

local function diff(a, b)
  local out = {}
  for i = 1, math.max(#a, #b) do
    if a[i] ~= b[i] then
      out[#out + 1] = ("real: %s | blank: %s"):format(tostring(a[i]), tostring(b[i]))
      if #out >= 3 then break end
    end
  end
  return out
end

-- ------------------------------------------------------------------- battery

--[[ One deterministic stretch of play around minion M: auras on both
     neighbours and on both hands, damage to M, summons on both sides, a spell,
     an attack, and a full round of turn ends and starts. ]]
--[[ What is left of a card with no text: its body. Everything else on the
     printed card (keywords, spellDamage, scriptTags, overload, entourage, any
     field added later) is card TEXT, and Silence must make it inert. Listing
     what to KEEP rather than what to drop is the point: a new printed field is
     stripped from the blank body by default, so if the engine forgets to gate
     it on Silence the battery sees the difference. ]]
local BODY = { id = true, name = true, type = true, set = true, rarity = true,
               class = true, cost = true, atk = true, hp = true, dur = true,
               race = true, collectible = true, dustHS = true }

local function blankBody(pr)
  local b = {}
  for k, v in pairs(pr) do if BODY[k] then b[k] = v end end
  b.text = ""
  return b
end

local function battery(ns, cardId, strip, silence)
  local saved, savedPrinted = ns.Scripts[cardId], ns.PrintedCards[cardId]
  if strip then
    ns.Scripts[cardId] = nil
    ns.PrintedCards[cardId] = blankBody(savedPrinted)
  end
  local ok, result = pcall(function()
    local g = H.NewGame({ seed = 4242, class1 = "MAGE", class2 = "MAGE" })
    H.SetActive(g, 1); H.Mana(g, 1, 10); H.Mana(g, 2, 10)
    local left = H.Put(g, 1, YETI)
    local m = H.Put(g, 1, cardId)
    H.Put(g, 1, YETI)
    local foe = H.Put(g, 2, YETI)
    H.Put(g, 2, YETI)
    H.Hand(g, 1, YETI); H.Hand(g, 1, MOONFIRE); H.Hand(g, 2, YETI); H.Hand(g, 2, MOONFIRE)
    if silence then m:Silence() end
    g:RecalcAuras()
    local snaps = { fingerprint(ns, g) }

    g.bus:Block(function() g:DealDamage(m, 1, nil, false) end); g.bus:Drain()
    g:Summon(WISP, 1); g:Summon(WISP, 2); g.bus:Drain()
    local i = H.Hand(g, 1, MOONFIRE)
    g:PlayCard(1, i, H.Hero(g, 2)); g.bus:Drain()
    if left.zone == ns.ZONE.PLAY and foe.zone == ns.ZONE.PLAY then
      g:Attack(left, foe); g.bus:Drain()
    end
    snaps[#snaps + 1] = fingerprint(ns, g)
    g:EndTurn(); g.bus:Drain()
    snaps[#snaps + 1] = fingerprint(ns, g)
    g:EndTurn(); g.bus:Drain()
    snaps[#snaps + 1] = fingerprint(ns, g)
    return { snaps = snaps, errors = g.errors }
  end)
  ns.Scripts[cardId], ns.PrintedCards[cardId] = saved, savedPrinted
  if not ok then error(result, 0) end
  return result
end

local function producibleMinions(ns)
  local ids = {}
  for id in pairs(ns.PrintedCards) do
    local pr = ns.PrintedCards[id]
    -- every minion a game can produce, scripted or not: Kobold Geomancer's
    -- Spell Damage is printed data with no script behind it
    if pr and pr.type == "MINION" and (pr.collectible or ns.Scripts[id]) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

H.suite("liveprops: a silenced minion behaves exactly like a blank body", function(ns, H)
  local problems, live = {}, 0
  for _, id in ipairs(producibleMinions(ns)) do
    local okA, real  = pcall(battery, ns, id, false, true)
    local okB, blank = pcall(battery, ns, id, true, true)
    if not okA or not okB then
      problems[#problems + 1] = ("%s: battery crashed: %s"):format(id, tostring(okA and blank or real))
    else
      for step = 1, #real.snaps do
        local d = diff(real.snaps[step], blank.snaps[step])
        if #d > 0 then
          problems[#problems + 1] = ("%s (%s) silenced, step %d: %s"):format(
            id, ns.PrintedCards[id].name, step, table.concat(d, " ; "))
          break
        end
      end
    end
  end
  --[[ Not vacuous: unsilenced, the battery must SEE most scripts. If this
       floor fails the battery stopped exercising anything and a pass above
       would mean nothing. ]]
  for _, id in ipairs(producibleMinions(ns)) do
    local okA, real  = pcall(battery, ns, id, false, false)
    local okB, blank = pcall(battery, ns, id, true, false)
    if okA and okB then
      for step = 1, #real.snaps do
        if #diff(real.snaps[step], blank.snaps[step]) > 0 then live = live + 1; break end
      end
    end
  end
  H.ok(live >= 60, ("the battery observes at least 60 unsilenced scripts (saw %d)"):format(live))
  if #problems == 0 then
    H.ok(true, "every silenced minion matches a blank body")
  else
    local shown = {}
    for i = 1, math.min(#problems, 15) do shown[i] = "      " .. problems[i] end
    if #problems > 15 then shown[#shown + 1] = ("      ... and %d more"):format(#problems - 15) end
    H.ok(false, ("%d silenced minions differ from a blank body:\n"):format(#problems) .. table.concat(shown, "\n"))
  end
end)

-- --------------------------------------------------------- has Deathrattle

local function printedDeathrattle(pr)
  for _, t in ipairs(pr.scriptTags or {}) do if t == "DEATHRATTLE" then return true end end
  return false
end

local function selected(g, sel)
  local set = {}
  for _, e in ipairs(H.ns.Selector.Resolve(g, sel, { controller = 1 })) do set[e] = true end
  return set
end

H.suite("liveprops: 'has Deathrattle' follows the live minion, for every card", function(ns, H)
  local problems, n = {}, 0
  local ids = {}
  for id, pr in pairs(ns.PrintedCards) do
    -- a card a game can produce: collectible, or scripted (tokens). Adventure
    -- boss cards carry the tag with no script and never reach a game.
    if pr.type == "MINION" and (pr.collectible or ns.Scripts[id]) and (printedDeathrattle(pr)
        or (ns.Scripts[id] and ns.Scripts[id].deathrattle)) then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  local SEL = { side = "ANY", type = "MINION", hasDeathrattle = true }
  for _, id in ipairs(ids) do
    n = n + 1
    local g = H.NewGame()
    local live = H.Put(g, 1, id)
    local hushed = H.Put(g, 1, id); hushed:Silence()
    local _, held = H.Hand(g, 1, id)
    g:RecalcAuras()
    local on = selected(g, SEL)
    if not on[live] then problems[#problems + 1] = id .. ": in play, not seen as having a Deathrattle" end
    if on[hushed] then problems[#problems + 1] = id .. ": silenced, still seen as having a Deathrattle" end
    local inHand = selected(g, { side = "FRIENDLY", zone = ns.ZONE.HAND, hasDeathrattle = true })
    if printedDeathrattle(ns.PrintedCards[id]) and not inHand[held] then
      problems[#problems + 1] = id .. ": in hand, not seen as having a Deathrattle"
    end
    -- the payload twin (Undertaker) must agree with the selector
    for _, e in ipairs({ live, hushed }) do
      local c = ns.Conditions.predicates.PayloadHasDeathrattle
      if c(g, { payload = { entity = e } }) ~= (on[e] or false) then
        problems[#problems + 1] = id .. ": PayloadHasDeathrattle disagrees with the selector"
      end
    end
  end
  H.ok(n >= 30, ("at least 30 deathrattle minions checked (found %d)"):format(n))
  H.ok(#problems == 0, table.concat(problems, "\n      "))
end)

H.suite("liveprops: a granted Deathrattle counts, and Silence removes it", function(ns, H)
  local g = H.NewGame({ class1 = "SHAMAN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local yeti = H.Put(g, 1, YETI)
  local i = H.Hand(g, 1, "CS2_038")
  H.ok(g:PlayCard(1, i, yeti)); g.bus:Drain()
  local SEL = { side = "ANY", type = "MINION", hasDeathrattle = true }
  H.ok(selected(g, SEL)[yeti], "Ancestral Spirit gives the Yeti a Deathrattle")
  yeti:Silence(); g:RecalcAuras()
  H.notOk(selected(g, SEL)[yeti], "and Silence takes it away")
  H.noEngineErrors(g)
end)

H.suite("liveprops: Scarlet Purifier spares a silenced Loot Hoarder", function(ns, H)
  local g = H.NewGame({ class1 = "PALADIN" })
  H.SetActive(g, 1); H.Mana(g, 1, 10)
  local live = H.Put(g, 2, "EX1_096")
  local hushed = H.Put(g, 2, "EX1_096"); hushed:Silence()
  local i = H.Hand(g, 1, "GVG_101")
  H.ok(g:PlayCard(1, i)); g.bus:Drain()
  H.ok(live.zone ~= ns.ZONE.PLAY, "the Hoarder with its Deathrattle took 2 and died")
  H.eq(hushed.zone, ns.ZONE.PLAY, "the silenced one was not hit")
  H.eq(hushed:Health(), 1, "and is undamaged")
  H.noEngineErrors(g)
end)
