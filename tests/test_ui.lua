--[[ tests/test_ui.lua -- the frame binding, run against a strict WoW stub.

  This is the pre-flight check for code that touches the WoW API. It cannot tell
  us the board LOOKS right; it can tell us that every API call exists, every event
  name is real, frames are pooled rather than leaked, resizing reflows, and the
  drag-and-drop path produces the right intents.

  The stub is STRICT: any frame method it does not model raises an error naming
  the widget and method. So a call to something Mainline does not have -- e.g. the
  removed SetMinResize -- fails here rather than in game.
]]
local H = require("tests.harness")
local Stub = require("tests.wowstub")
local function near(a,b,tolerance,message) H.ok(math.abs(a-b)<=tolerance,message) end

-- Board.lua is loaded lazily against the stub, because it needs CreateFrame to
-- exist at load time. The main harness deliberately does NOT load it.
local function withBoard(ns, fn, opts)
  Stub.Install(_G)
  Stub.resting = true
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true } }

  -- (re)load the binding against the freshly installed stub
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  local chunk = assert(loadfile("ForeverHearthstone/Client/UI/Board.lua"))
  chunk("ForeverHearthstone", ns)

  local resolver = ns.Resolver.New({ printed = ns.PrintedCards, palette = {} })
  local intents = {}
  local board = ns.Board.Create({
    resolver = resolver,
    width = (opts and opts.width) or 1280,
    height = (opts and opts.height) or 720,
    onIntent = function(i) intents[#intents + 1] = i end,
  })
  return fn(board, intents, resolver)
end

local function snapshot(handIds, boardIds, foeIds, extra)
  local s = { hand = handIds or {}, board = boardIds or {}, foeBoard = foeIds or {},
              foeHandCount = 4, maxMana = 7 }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

H.suite('ui: board hover shows current attack and remaining health on either side',function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {'CS2_182'}, {'CS2_182'}, {
      boardStats={{instanceId=11,atk=8,health=2,maxHealth=9,damaged=true}},
      foeBoardStats={{instanceId=22,atk=0,health=7,maxHealth=7}}}))
    b.myMinions[1].frame:GetScript('OnEnter')()
    H.eq(b.hoverCard.atk:GetText(),'8'); H.eq(b.hoverCard.hp:GetText(),'2')
    H.ok(b.hoverCard.atk.colour[2]>.9,'buffed attack is green')
    H.ok(b.hoverCard.hp.colour[2]<.5,'damaged health is red')
    H.ok(b.tooltip.text:GetText():find('Attack: 8   Health: 2',1,true))
    b.foeMinions[1].frame:GetScript('OnEnter')()
    H.eq(b.hoverCard.atk:GetText(),'0'); H.eq(b.hoverCard.hp:GetText(),'7')
    H.ok(b.hoverCard.hp.colour[2]>.9,'buffed enemy health is green')
    b:ShowDescription(b.myMinions[1].frame,'CS2_182')
    H.eq(b.hoverCard.atk:GetText(),'4'); H.eq(b.hoverCard.hp:GetText(),'5','printed previews reset pooled live stats')
  end)
end)

H.suite('ui: open board hover follows entity through updates and closes on removal',function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {'CS2_182'}, {}, {boardStats={{instanceId=11,atk=6,health=3}}}))
    b.myMinions[1].frame:GetScript('OnEnter')()
    b:SetSnapshot(snapshot({}, {'CS2_231','CS2_182'}, {}, {
      boardStats={{instanceId=12,atk=1,health=1},{instanceId=11,atk=9,health=4}}}))
    H.ok(b.hoverCard.frame:IsShown())
    H.eq(b.hoverCard.atk:GetText(),'9'); H.eq(b.hoverCard.hp:GetText(),'4')
    H.eq(b.hoverBoardEntity,11,'preview did not switch to the new slot occupant')
    b:SetSnapshot(snapshot({}, {'CS2_231'}, {'CS2_tk1'}, {
      boardStats={{instanceId=12,atk=1,health=1}},foeBoardStats={{instanceId=11,atk=1,health=1}}}))
    H.eq(b.tooltipCardId,'CS2_tk1','transformation/control change refreshes card art')
    H.eq(b.hoverCard.atk:GetText(),'1'); H.eq(b.hoverCard.hp:GetText(),'1')
    b:SetSnapshot(snapshot({}, {'CS2_231'}, {}, {boardStats={{instanceId=12,atk=1,health=1}}}))
    H.notOk(b.hoverCard.frame:IsShown(),'removed entity has no stale hover')
    H.eq(b.hoverBoardEntity,nil)
  end)
end)

H.suite("ui: ability fallback emits particles at frozen positions",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182","GVG_110t"}, {"CS2_186"}))
    for _,kind in ipairs({"deathrattle","damage","heal","summon","silence","battlecry","buff","transform"}) do
      local stage=b:Stage()
      local opts={kind=kind,side="self",index=2,at=.5}
      local point=stage:EffectPoint(opts)
      local expected=b.L.boardSlots[2]
      H.eq(point.x,expected.x+expected.w/2)
      local tl=ns.Choreography.AbilityEffect(stage,opts)
      -- Redrawing must not retarget the pending burst to a different slot.
      b:SetSnapshot(snapshot({}, {"CS2_182"}, {"CS2_186"}))
      local count=#b.particles.live
      tl:RunAll(.016)
      H.ok(#b.particles.live>count,kind.." reaches the particle renderer")
      b:TickFX(3)
      b:SetSnapshot(snapshot({}, {"CS2_182","GVG_110t"}, {"CS2_186"}))
    end
  end)
end)

H.suite("ui: attack hits and health changes occur at impact and never replay",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {eventSeq=1,foeHeroId=9,foeHero={health=30}}))
    b:BeginPresentation()
    b:SetSnapshot(snapshot({}, {}, {}, {eventSeq=2,foeHeroId=9,foeHero={health=27},
      presentationEvents={{seq=2,targetId=9,amount=3,healthAfter=27,armorAfter=0}}}))
    local tl=ns.Choreography.Attack(b:Stage(),{attackerIsHero=true,attackerSide="self",defenderIsHero=true})
    tl:Start(); tl:Tick(.20)
    H.eq(#b.hitLabels,0)
    H.eq(b.foeHero.health:GetText(),"30")
    tl:Tick(.02)
    H.ok(b.presentationLocked,"impact occurs before recovery completes")
    H.eq(#b.hitLabels,1)
    H.eq(b.foeHero.health:GetText(),"27")
    b:TickFX(.1)
    local age=b.hitLabels[1].age
    b:EndPresentation()
    H.eq(#b.hitLabels,1)
    H.eq(b.hitLabels[1].age,age,"final snapshot does not restart the hitsplat")
  end)
end)

H.suite("ui: game over blocks card gestures and clears ready glows",function(ns,H)
  withBoard(ns,function(b,intents)
    b:SetSnapshot(snapshot({"GAME_005"},{"CS2_182"},{},{over=true,winner=1,
      playable={true},canAttack={true},heroPower={cardId="CS2_034",usable=true}}))
    local w=b.handWidgets[1]
    H.eq(b:BeginDrag(w),false)
    H.eq(b:BeginPlayAnimation(1),false)
    b.onIntent({kind="PLAY_CARD",handIndex=1})
    H.eq(#intents,0)
    H.notOk(w.glow:IsShown()); H.notOk(b.myMinions[1].glow:IsShown())
    H.notOk(b.heroPower.glow:IsShown())
    H.eq(#b.crystalPool.used,7,"only local mana gets crystals")
  end)
end)

H.suite("ui: hero health has a fixed center and armor has a shield",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {hero={health=10,armor=8}}))
    local point=b.hero.health.points[1]
    H.eq(point[1],"CENTER")
    H.ok(b.hero.armorBadge:IsShown())
    H.eq(b.hero.armor.points[1][2],b.hero.frame)
    H.ok(b.hero.health.w>=44,"health reserves room for two digits")
    H.ok(b.hero.health.h>=28,"health has a nonzero line box")
    H.ok(b.hero.health.font[2]>=16,"health remains readable")
    local x,y=point[4],point[5]
    b:SetSnapshot(snapshot({}, {}, {}, {hero={health=9,armor=0}}))
    H.eq(b.hero.health.points[1][4],x); H.eq(b.hero.health.points[1][5],y)
    H.notOk(b.hero.armorBadge:IsShown())
  end)
end)

H.suite("ui: Coin begins at the top of history and outcomes appear on hover",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}))
    b:AddHistory("GAME_005","You: play card",false,{kind="PLAY_CARD"})
    H.eq(b.historyButtons[1].points[1][5],b.L.historySlots[8].y)
    b:AddHistory("CS2_029","You: play card",false,{kind="PLAY_CARD"},{targetCardId="CS2_182"},
      {{cardId="CS2_182",amount=6,health=-1,armor=0}})
    H.eq(b.history[2].cardId,"GAME_005")
    H.ok(b.historyButtons[2].historyY>b.historyButtons[1].historyY)
    b.historyButtons[1]:GetScript("OnEnter")()
    H.ok(b.tooltip.text:GetText():find("%-6 %-> 0 health"))
  end)
end)

H.suite("ui: played minion dissolves into its landing portrait before release",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_182"}))
    b:BeginPlayAnimation(1); b:BeginPresentation()
    b:SetSnapshot(snapshot({}, {"CS2_182"}))
    local tl=ns.Choreography.PlayMinion(b:Stage(),{cardIndex=1,slot=1,mine=true})
    tl:Start(); tl:Tick(.37)
    H.ok(b.summonPortrait.frame:IsShown())
    H.ok(b.summonPortrait.inPlay)
    H.ok(b.flyingCard.frame:GetAlpha()<1)
    tl:Tick(.15)
    H.eq(b.flyingCard.frame:GetAlpha(),0)
    local r=b.summonPortrait.rect
    b:EndPresentation()
    H.notOk(b.summonPortrait.frame:IsShown())
    H.eq(b.myMinions[1].rect.x,r.x)
    H.eq(b.myMinions[1].rect.w,r.w)
  end)
end)

H.suite("ui: summon battlecries land with their own stats at every board capacity",function(ns,H)
  withBoard(ns,function(b)
    for _,id in ipairs({"GVG_110","EX1_562","EX1_506","CS2_196"}) do
      for owner=1,2 do
        for count=0,7 do
          local g=H.NewGame()
          H.SetActive(g,owner); H.Mana(g,owner,10)
          local original={}
          for i=1,count do original[i]=H.Put(g,owner,"CS2_182") end
          local hand,card=H.Hand(g,owner,id)
          local c=ns.Controller.New({game=g,player=1})
          b:SetSnapshot(c:Snapshot())
          local action={kind="PLAY_CARD",handIndex=hand,position=math.floor(count/2)+1}
          local before=ns.Director.Before(g,owner,action)
          if count==7 then
            local mana=g:AvailableMana(owner)
            H.notOk(ns.Actions.Run(g,owner,action),"full board refuses the play")
            H.eq(#g.players[owner].board,7); H.eq(g:AvailableMana(owner),mana)
            H.eq(g.players[owner].hand[hand],card)
          else
            H.ok(b:BeginPlayAnimation(hand,owner==2 and id or nil))
            b:BeginPresentation()
            H.ok(ns.Actions.Run(g,owner,action))
            local expected=math.min(7,count+1+(id=="GVG_110" and 2 or id=="EX1_562" and 7 or 1))
            H.eq(#g.players[owner].board,expected)
            for _,e in ipairs(original) do H.eq(g:EntityById(e.instanceId),e,"existing minion survives") end
            b:SetSnapshot(c:Snapshot())
            local plans=ns.Director.New():Plan(g,owner,action,before)
            local plan=plans[1]
            H.eq(plan.opts.instanceId,card.instanceId)
            H.eq(plan.opts.slot,card.boardIndex)
            local stage=b:Stage()
            local tokenPoints={}
            for _,effect in ipairs(plans) do
              if effect.sequence=="AbilityEffect" and effect.opts.kind=="summon" then
                tokenPoints[effect.opts.instanceId]=stage:EffectPoint(effect.opts)
              end
            end
            local tl=ns.Choreography.PlayMinion(stage,plan.opts)
            tl:Start(); tl:Tick(.37)
            H.eq(b.summonPortrait.atk:GetText(),tostring(card:Attack()))
            H.eq(b.summonPortrait.hp:GetText(),tostring(card:Health()))
            tl:Tick(.2)
            local r=b.summonPortrait.rect
            b:EndPresentation()
            local row=owner==1 and b.myMinions or b.foeMinions
            H.eq(row[card.boardIndex].rect.x,r.x,"landing matches resolved row")
            H.eq(row[card.boardIndex].rect.w,r.w)
            for instanceId,point in pairs(tokenPoints) do
              local token=g:EntityById(instanceId)
              local rect=row[token.boardIndex].rect
              H.eq(point.x,rect.x+rect.w/2,"token cue uses the final slot")
              H.eq(point.y,rect.y+rect.h/2)
              H.ok(rect.x>=0 and rect.x+rect.w<=b.frame:GetWidth(),"full row stays within the board")
            end
          end
          H.noEngineErrors(g)
        end
      end
    end
  end)
end)

H.suite("ui: hero powers launch from each hero even with a flying card", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_029"}))
    b:BeginPlayAnimation(1)
    for _,mine in ipairs({true,false}) do
      local tl=ns.Choreography.HeroPower(b:Stage(),{mine=mine,targeted=true,cardId="CS2_034",
        targetSide=mine and "foe" or "self",targetIsHero=true})
      tl:Start(); tl:Tick(.01)
      local p=b.sprites[#b.sprites]   -- Fireblast's flame
      local source=mine and b.L.hero or b.L.foeHero
      H.eq(p.x0,source.x+source.w/2)
      H.eq(p.y0,source.y+source.h/2)
      H.eq(p.school,"fire")
    end
  end)
end)

H.suite("ui: history keeps targets and hides secrets in its hover preview",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}))
    b:AddHistory("CS2_029","You: play card",false,{kind="PLAY_CARD"},{targetCardId="CS2_182"})
    b.historyButtons[1]:GetScript("OnEnter")()
    H.ok(b.historyPreview:IsShown())
    H.eq(b.historyPreview.target.descriptor.cardId,"CS2_182")
    b:AddHistory("EX1_287","Enemy: play card",true,{kind="PLAY_CARD"},{targetCardId="CS2_182"})
    H.eq(b.history[1].targetCardId,nil)
    b.historyButtons[1]:GetScript("OnEnter")()
    H.notOk(b.historyPreview:IsShown())
    b:AddHistory(nil,"End turn",false,{kind="END_TURN"})
    H.eq(#b.history,2,"turn bookkeeping does not fill action history")
  end)
end)

H.suite("ui: exhausted minions have no spent label and hits have a background",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182"},{},{boardStats={{atk=4,health=5,exhausted=true}}}))
    H.eq(b.myMinions[1].status:GetText(),"")
    b:ShowHit(b.L.boardSlots[1],3,false)
    H.ok(b.hitLabels[1].background:GetTexture():find("damage"), "damage uses Hearthstone's starburst")
    H.eq(b.hitLabels[1].frame:GetAlpha(),1)
    b:ShowHit(b.L.boardSlots[1],2,true)
    H.ok(b.hitLabels[2].background:GetTexture():find("healing"), "healing uses its own bloom")
  end)
end)

--=============================================================== creation

local function glyphCenter(tex)
  local uv=tex.texcoord
  return ((0.5-uv[1])/(uv[2]-uv[1])-0.5)*tex.w,
         (0.5-(0.5-uv[3])/(uv[4]-uv[3]))*tex.h
end

H.suite("ui: full-canvas digits stay on their sockets through rotation and resize", function(ns, H)
  -- each frame's own gem: a minion's sits further left than a spell's
  H.ok(ns.Widgets.COST_GEM.MINION[1] < ns.Widgets.COST_GEM.SPELL[1], "per-frame gem centres")
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({"CS2_074","NEW1_004","CS2_080","CS2_172"}))
    for _,size in ipairs({{760,560},{1280,720},{1920,1080}}) do
      board.frame:SetSize(size[1],size[2])
      for _,w in ipairs(board.handWidgets) do
        for _,rot in ipairs({-0.14,-0.07,0,0.07,0.14}) do
          ns.Widgets.SetLean(w,rot)
          for _,number in ipairs({w.cost,w.atk,w.hp}) do
            for _,value in ipairs({"0","1","10","99","123"}) do
              number:SetText(value)
              -- the INK is centred: from the first digit's left edge to the last's right
              local left,right,cy=math.huge,-math.huge,0
              for i=1,#value do
                local tex=number.glyphs[i]
                H.eq(tex.parent,w.skin.parent)
                H.eq(tex.w,w.skin:GetWidth(),"same rotation canvas width")
                H.eq(tex.h,w.skin:GetHeight(),"same rotation canvas height")
                H.eq(tex.points[1][4],0,"same horizontal pivot")
                H.eq(tex.points[1][5],0,"same vertical pivot")
                H.eq(rawget(tex,"vertices"),nil,"no deformed quad")
                local x,y=glyphCenter(tex)
                local half=ns.Widgets.GLYPH_INK[value:sub(i,i)]*tex.w/(tex.texcoord[2]-tex.texcoord[1])/2
                left,right,cy=math.min(left,x-half),math.max(right,x+half),cy+y
              end
              local cx=(left+right)/2
              cy=cy/#value
              local x,y=number.point[4],number.point[5]
              local c,s=math.cos(rot),math.sin(rot)
              H.ok(math.abs((cx*c-cy*s)-(x*c-y*s))<.001,"rotated ink center matches socket x")
              H.ok(math.abs((cx*s+cy*c)-(x*s+y*c))<.001,"rotated ink center matches socket y")
            end
          end
        end
      end
    end
  end)
end)

H.suite("ui: numeric badges are card textures and preserve live stats through reuse", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({"CS2_182"}))
    local w = board.handWidgets[1]
    local cost = w.cost
    H.eq(cost.glyphs[1].parent, w.skin.parent, "digit shares the skin's transform parent")
    H.ok(cost.glyphs[1]:GetTexture():find("card%-digit%-"), "uses isolated glyphs")
    ns.Widgets.SetLean(w, 0.14)
    H.eq(cost.glyphs[1].parent, w.frame, "lean cannot detach the number")
    cost:SetText("10")
    H.eq(#cost.glyphs, 2, "multi-digit costs render")
    H.ok(cost.glyphs[1]:GetTexture():find("card%-digit%-1.tga"))
    H.ok(cost.glyphs[2]:GetTexture():find("card%-digit%-0.tga"))
    ns.Widgets.SetPlayable(w, false, false)
    H.eq(cost.glyphs[2].colour[2], 1, "Hearthstone never recolours an unaffordable cost")
    ns.Widgets.SetFaceDown(w, true)
    H.notOk(cost.glyphs[1]:IsShown()); H.notOk(cost.glyphs[2]:IsShown())
    ns.Widgets.SetFaceDown(w, false)
    H.ok(cost.glyphs[2]:IsShown())
    cost:SetText("0")
    H.notOk(cost.glyphs[2]:IsShown(), "old trailing digit is hidden")
    ns.Widgets.SetLiveStats(w, {atk=12,health=3,damaged=true})
    H.eq(w.atk:GetText(), "12")
    H.eq(w.hp.glyphs[1].colour[2], 0.35, "damage tint reaches the texture")
  end)
end)

H.suite("ui: combat holds widgets until the final snapshot and stale hero handles expire", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, {"CS2_182"}, {"CS2_231"}))
    local old = board.myMinions[1]
    local hero = board:Stage():Hero("self")
    board:BeginPresentation()
    board:SetSnapshot(snapshot({}, {}, {}))
    H.eq(board.myMinions[1], old, "combatant survives until impact")
    board:Relayout()
    H.eq(board.myMinions[1], old, "resize cannot recycle combatant")
    board:EndPresentation()
    H.eq(#board.myMinions, 0, "latest snapshot applied")
    hero:Alpha(0)
    H.eq(board.hero.frame:GetAlpha(), 1, "old hero fade cannot hide the new presentation")
    H.ok(board.frame:IsShown(), "board remains shown")
  end)
end)

H.suite("ui: fan rotates the card as one object and keyword effects reset on reuse", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({"CS2_182", "CS2_182", "CS2_182"}))
    local w = board.handWidgets[1]
    ns.Widgets.SetLean(w, 0.1)
    H.ok(w.anim:IsPlaying(), "shared frame transform is active")
    H.ok(math.abs(w.rotation.degrees - 0.1 * 180 / math.pi) < 0.001)
    H.eq(w.art.mask, w.artMask, "art is clipped")
    ns.Widgets.SetLiveStats(w, {atk=4, health=5, taunt=true, divineShield=true})
    H.ok(w.taunt:IsShown()); H.ok(w.shield:IsShown())
    ns.Widgets.SetDescriptor(w, board.resolver:Card("CS2_182"))
    H.notOk(w.taunt:IsShown()); H.notOk(w.shield:IsShown())
    ns.Widgets.SetFaceDown(w, true)
    H.notOk(w.name:IsShown(), "face-down text cannot leak")
    ns.Widgets.SetFaceDown(w, false)
    H.ok(w.name:IsShown())
  end)
end)

H.suite("ui: mulligan hides the ordinary hand and play destination is centered", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({"CS2_182"}, {}, {}, {
      mulligan={hand={"CS2_182"}, marked={}} }))
    H.eq(#board.handWidgets, 0, "no duplicate or newly drawn hand beneath mulligan")
    board:SetSnapshot(snapshot({"CS2_182"}))
    H.ok(board:BeginPlayAnimation(1))
    local dest = board:Stage():PlayDestination(1, true)
    local from = board.flyingCard.rect
    H.ok(math.abs(from.x + from.w/2 + dest.x - (board.L.hero.x + board.L.hero.w/2)) < 0.01,
      "first played card lands straight above the hero")
  end)
end)

H.suite("ui: the board builds without touching a missing API", function(ns, H)
  --[[ The single most valuable assertion in this file. The stub errors on any
       unmodelled method, so simply constructing the board proves every call it
       makes exists on the Mainline surface we modelled. ]]
  withBoard(ns, function(board)
    H.ok(board and board.frame, "board created")
    H.ok(board.frame:IsShown(), "visible by default")
    -- the requested 1280x720 is the shape; the first opening scales it to the screen (docs/39)
    local dw, dh = ns.Widgets.DefaultSize({ w = 1280, h = 720 })
    H.eq(board.frame:GetWidth(), dw, "requested shape, scaled to the screen")
    H.eq(board.frame:GetHeight(), dh, "requested height, scaled likewise")
    --[[ A board from the rotation, not `HearthstoneArt.board`. The single-board
         key is the FALLBACK for an install that has no rotation; when boards
         are packaged the match picks one of those. See SetBoardArt. ]]
    local boards = ns.HearthstoneArt.boards
    H.eq(board.bg:GetTexture(),
         (boards and boards[1]) or ns.HearthstoneArt.board,
         "real board texture wired")
    board.close:GetScript("OnClick")()
    H.notOk(board.frame:IsShown(), "close works")
  end)
end)

H.suite("ui: APIProbe never autoruns active protected-action diagnostics", function(ns, H)
  Stub.Install(_G)
  assert(loadfile("APIProbe/APIProbe.lua"))("APIProbe", {})
  Stub.Fire("PLAYER_LOGIN")
  H.eq(APIProbe.GetLastRun(), nil, "login does not start probes")
  local function checkSafety()
    for _, frame in ipairs(Stub.R.frames) do
      H.eq(rawget(frame, "template"), nil, "no Blizzard templates created")
    end
    H.eq(#Stub.R.sounds, 0, "no test sounds")
    H.eq(Stub.Count("SetPropagateKeyboardInput"), 0, "no protected keyboard calls")
  end
  checkSafety()
  SlashCmdList.APIPROBE("net")
  SlashCmdList.APIPROBE("emote")
  H.eq(APIProbe.GetLastRun(), nil, "active slash probes disabled")
  SlashCmdList.APIPROBE("")
  H.ok(APIProbe.GetLastRun(), "explicit read-only inventory works")
  checkSafety()
end)

H.suite("ui: the window is resizable with bounds from Layout", function(ns, H)
  withBoard(ns, function(board)
    H.ok(board.frame:IsResizable(), "resizable")
    local a, b, c, d = board.frame:GetResizeBounds()
    local minW, minH = ns.Layout.MinSize()
    local maxW, maxH = ns.Layout.MaxSize()
    H.eq(a, minW, "min width from Layout")
    H.eq(b, minH, "min height from Layout")
    H.eq(c, maxW, "max width from Layout")
    H.eq(d, maxH, "max height from Layout")
    -- SetResizeBounds must have been the call used, not the removed SetMinResize
    H.ok(Stub.Count("SetResizeBounds") >= 1, "used the Mainline SetResizeBounds")
  end)
end)

H.suite("ui: the window is movable, clamped and NOT saved across a reload", function(ns, H)
  withBoard(ns, function(board)
    H.ok(board.frame:IsMovable(), "movable")
    H.ok(board.frame.clamped, "clamped to screen so it cannot be lost offscreen")
    -- WoW's layout cache restored a badly sized window on every /reload
    H.ok(not board.frame:IsUserPlaced(), "not user-placed: a reload returns to the default")
    H.ok(board.frame.dontSave, "SetDontSavePosition, so the layout cache never holds it")
    H.ok(board.frame:GetScript("OnDragStart"), "drag start wired")
    H.ok(board.frame:GetScript("OnDragStop"), "drag stop wired")
    H.ok(board.frame:GetScript("OnSizeChanged"), "reflows on size change")
  end)
end)

H.suite("ui: every window shares one rect, clamped to its own bounds", function(ns, H)
  withBoard(ns, function(board)
    local W = ns.Widgets
    W.ForgetRect()
    local f = board.frame
    f.left, f.bottom = 40, 60; f:SetSize(900, 640)
    Stub.CursorOver(f, 895, 5)
    board.grip:GetScript("OnMouseDown")(board.grip)
    board.grip:GetScript("OnMouseUp")(board.grip)
    local r = W.SharedRect()
    H.ok(r and r.w == 900 and r.h == 640 and r.left == 40 and r.top == 700, "sizing records the rect")
    local other = CreateFrame("Frame", nil, UIParent)
    other:SetSize(1000, 680); other:SetMovable(true)
    W.ResizeGrip(other, 950, 650)
    other:Hide(); other:Show()
    H.eq(other:GetWidth(), 950, "a smaller shared width is raised to this window's minimum")
    H.eq(other:GetHeight(), 650, "and the height too, before any grip can snap it")
    local p = { other:GetPoint(1) }
    H.eq(p[1], "TOPLEFT", "opened where the last window was")
    H.eq(p[4], 40, "same left edge"); H.eq(p[5], 700, "same top edge")
    -- a window below its bounds is put inside them BEFORE sizing starts
    f:SetSize(500, 400)
    board.grip:GetScript("OnMouseDown")(board.grip)
    local a, b = f:GetResizeBounds()
    H.ok(f:GetWidth() >= a and f:GetHeight() >= b, "clamped before StartSizing")
    board.grip:GetScript("OnMouseUp")(board.grip)
    W.ForgetRect()
  end)
end)

H.suite("ui: the resize grip starts and stops sizing", function(ns, H)
  withBoard(ns, function(board)
    local down = board.grip:GetScript("OnMouseDown")
    local up   = board.grip:GetScript("OnMouseUp")
    H.ok(down and up, "grip handlers wired")
    Stub.CursorOver(board.frame, board.frame:GetWidth() - 5, 5)
    down(board.grip)
    H.ok(board.grip.drag, "a press on the grip starts sizing")
    H.eq(Stub.Count("StartSizing"), 0, "sized by the addon, not by WoW's StartSizing")
    up(board.grip)
    H.notOk(board.grip.drag, "and letting go stops it")
  end)
end)

--============================================================== rendering

H.suite("ui: a snapshot renders the right number of widgets", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot(
      { "CS2_182", "CS2_029", "EX1_162" },       -- 3 in hand
      { "CS2_182", "CS2_119" },                  -- 2 on board
      { "CS2_172" }))                            -- 1 enemy minion
    H.eq(#board.handPool.used, 3, "three hand widgets in use")
    H.eq(#board.boardPool.used, 3, "three board widgets (2 own + 1 foe)")
    H.eq(#board.L.handSlots, 3, "layout agrees")
  end)
end)

H.suite("ui: card text comes from printed data, so it is legible with no art", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182" }))
    local w = board.handPool.used[1]
    H.eq(w.name:GetText(), "Chillwind Yeti", "name rendered")
    H.eq(w.cost:GetText(), "4", "cost rendered")
    H.eq(w.atk:GetText(), "4", "attack rendered")
    H.eq(w.hp:GetText(), "5", "health rendered")
    -- the class-coloured edges are drawn, so the card has a frame even with no art
    for i, e in ipairs(w.edges) do
      H.ok(e.colour ~= nil, "edge " .. i .. " coloured")
    end
  end)
end)

H.suite("ui: a spell renders without attack or health", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_029" }))     -- Fireball
    local w = board.handPool.used[1]
    H.eq(w.name:GetText(), "Fireball", "name")
    H.eq(w.atk:GetText(), "", "no attack on a spell")
    H.eq(w.hp:GetText(), "", "no health on a spell")
  end)
end)

H.suite("ui: a model descriptor swaps art for a PlayerModel", function(ns, H)
  withBoard(ns, function(board, intents, resolver)
    -- give the resolver a model for the Yeti
    resolver.manifest = { cards = { CS2_182 = { model = 4321 } } }
    board:SetSnapshot(snapshot({ "CS2_182" }))
    local w = board.handPool.used[1]
    H.ok(w.model:IsShown(), "model frame shown")
    H.notOk(w.art:IsShown(), "flat art hidden")
    H.eq(w.model.displayInfo, 4321, "display id applied")
  end)
end)

H.suite("ui: a bad icon path still renders a complete card", function(ns, H)
  withBoard(ns, function(board, intents, resolver)
    resolver.manifest = { cards = { CS2_182 = { icon = [[Interface\Icons\DEFINITELY_NOT_REAL]] } } }
    board:SetSnapshot(snapshot({ "CS2_182" }))
    local w = board.handPool.used[1]
    -- WoW cannot tell us the path failed; what matters is the card is still whole
    H.eq(w.name:GetText(), "Chillwind Yeti", "name still there")
    H.eq(w.cost:GetText(), "4", "cost still there")
    H.ok(w.edges[1].colour, "frame still drawn")
  end)
end)

--================================================================ pooling

H.suite("ui: widgets are POOLED, not recreated on every relayout", function(ns, H)
  --[[ WoW cannot destroy a frame. Creating one per render leaks for the whole
       session and eventually tanks the frame rate. This asserts the pool works:
       repeated relayouts must not create new frames. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162" },
                               { "CS2_119" }, { "CS2_172" }))
    local after1 = board:FrameCount()
    H.ok(after1 > 0, "some widgets created initially")
    for _ = 1, 40 do board:Relayout() end
    H.eq(board:FrameCount(), after1, "forty relayouts created ZERO new frames")
  end)
end)

H.suite("ui: growing then shrinking the board reuses the same widgets", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, { "CS2_182" }))
    local small = board:FrameCount()
    board:SetSnapshot(snapshot({}, { "CS2_182","CS2_119","CS2_172","CS2_231",
                                     "CS2_182","CS2_119","CS2_172" }))
    local big = board:FrameCount()
    H.ok(big >= small, "grew the pool to fit seven")
    board:SetSnapshot(snapshot({}, { "CS2_182" }))
    H.eq(board:FrameCount(), big, "shrinking created nothing new")
    H.eq(#board.boardPool.used, 1, "and only one widget is in use")
    H.ok(#board.boardPool.free >= 6, "the rest returned to the pool")
  end)
end)

--=============================================================== resizing

H.suite("ui: resizing reflows every widget", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029" }, { "CS2_119" }))
    local wBefore = board.handPool.used[1].frame:GetWidth()

    board.frame:SetSize(1920, 1080)
    board:Relayout()
    local wAfter = board.handPool.used[1].frame:GetWidth()
    H.ok(wAfter > wBefore, "cards got bigger with the window")

    board.frame:SetSize(800, 600)
    board:Relayout()
    local wSmall = board.handPool.used[1].frame:GetWidth()
    H.ok(wSmall < wAfter, "and smaller again")
    H.ok(wSmall > 0, "never degenerate")
  end)
end)

H.suite("ui: OnSizeChanged triggers a reflow by itself", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182" }))
    local before = board.handPool.used[1].frame:GetWidth()
    board.frame:SetSize(1920, 1080)
    board.frame:GetScript("OnSizeChanged")(board.frame, 1920, 1080)
    H.ok(board.handPool.used[1].frame:GetWidth() > before,
         "the handler alone was enough to reflow")
  end)
end)

H.suite("ui: a degenerate size does not crash the reflow", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182" }))
    board.frame:SetSize(0, 0)
    local ok = pcall(function() board:Relayout() end)
    H.ok(ok, "zero size handled without error")
  end)
end)

--========================================================= input / intents

H.suite("ui: clicking the end-turn button emits an intent", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot())
    board.endTurn:Click("LeftButton")
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "END_TURN", "END_TURN")
  end)
end)

H.suite("ui: clicking a hand card reports its index", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162" }))
    -- The hand's mouse target is its hit area, not its picture -- see
    -- Widgets.NewHitArea and tests/test_presentation.lua.
    board.handHitPool.used[2].frame:Click("LeftButton")
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "CLICK_HAND", "CLICK_HAND")
    H.eq(intents[1].handIndex, 2, "index 2")
  end)
end)

H.suite("ui: clicking own and enemy minions are distinct intents", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, { "CS2_172" }))
    -- own board widgets come first, then foe
    board.boardPool.used[1].frame:Click("LeftButton")
    board.boardPool.used[2].frame:Click("LeftButton")
    H.eq(#intents, 2, "two intents")
    H.eq(intents[1].kind, "CLICK_BOARD", "own minion")
    H.eq(intents[2].kind, "CLICK_FOE_BOARD", "enemy minion")
  end)
end)

H.suite("ui: dragging a card onto a drop zone emits PLAY_CARD with a position", function(ns, H)
  --[[ Positional adjacency is real gameplay, so the drop must carry WHERE. The
       index comes from Layout.DropIndexAt, which is separately tested -- the UI
       never decides board order itself. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_182" }, { "CS2_119", "CS2_172" }))
    local w = board.handPool.used[1]

    -- aim the cursor at the middle drop zone (index 2 of three)
    local z = board.L.dropZones[2]
    _G.GetCursorPosition = function()
      local s = board.frame:GetEffectiveScale()
      return (z.x + z.w / 2) * s, (z.y + z.h / 2) * s
    end

    board:BeginDrag(w)
    H.eq(board.dragging, w, "dragging tracked")
    board:EndDrag(w)
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "PLAY_CARD", "PLAY_CARD")
    H.eq(intents[1].handIndex, 1, "from hand slot 1")
    H.eq(intents[1].position, 2, "inserting at position 2")
    H.eq(board.dragging, nil, "drag released")
  end)
end)

H.suite("ui: dropping outside any zone snaps back without an intent", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_182" }, { "CS2_119" }))
    local w = board.handPool.used[1]
    _G.GetCursorPosition = function() return -9999, -9999 end
    board:BeginDrag(w)
    board:EndDrag(w)
    H.eq(#intents, 0, "no intent emitted for an invalid drop")
  end)
end)

--================================================================ the stage

H.suite("ui: the stage satisfies every choreography without error", function(ns, H)
  --[[ The join between the tested choreography data and real frames. Running all
       ten choreographies against the live stage proves the binding implements
       what they call -- and because stage methods are optional on the
       choreography side, a gap degrades rather than erroring. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162", "CS2_119", "CS2_172" },
                               { "CS2_119" }, { "CS2_172" }))
    local stage = board:Stage()
    local names = { "PlayMinion", "PlaySpell", "Attack", "PackDropToast",
                    "SetCardDropToast", "PackCrack", "CardReveal",
                    "Craft", "Disenchant", "Rope" }
    for _, n in ipairs(names) do
      local ok, err = pcall(function()
        ns.Choreography[n](stage, {
          cardIndex = 1, count = 5, rarity = "LEGENDARY", seconds = 2,
          glow = { 1, 0.8, 0.2, 0.9 }, heavy = true, golden = true,
        }):RunAll(1 / 60)
      end)
      H.ok(ok, n .. " ran against the real stage: " .. tostring(err))
    end
  end)
end)

H.suite("ui: the stage's Glow actually reaches the widget", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182" }))
    local stage = board:Stage()
    stage:Card(1):Glow(1, 0.5, 0.25, 0.8)
    local w = board.handPool.used[1]
    H.ok(w.glow:IsShown(), "glow shown")
    H.eq(w.glow.colour[1], 1, "colour applied")
    stage:Card(1):Glow(1, 0.5, 0.25, 0)
    H.notOk(w.glow:IsShown(), "hidden again at zero alpha")
  end)
end)

H.suite("ui: the stage tolerates being asked for a widget that is not there", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}))      -- empty hand
    local stage = board:Stage()
    local ok = pcall(function()
      stage:Card(5):Glow(1, 1, 1, 1):Scale(1.2):Alpha(0.5):Pos(10, 10):Flip()
    end)
    H.ok(ok, "no error for a missing widget -- the UI must not crash mid-animation")
  end)
end)

--=============================================================== choose one

--[[ The Choose One prompt. Its contents come from the SNAPSHOT, never from the
     engine: the board is handed { handIndex, position, options } and renders it.
     The options are the ones Targeting.ModeOptions produces, so what is tested
     here is purely that the board draws them and reports the click. ]]
local function chooseSnapshot(opts)
  return snapshot({ "EX1_160" }, {}, {}, {
    chooseOne = {
      handIndex = 1,
      position  = 3,
      options   = opts or {
        { mode = 1, cardId = "EX1_160b", name = "Leader of the Pack",
          text = "Give your minions +1/+1.", playable = true },
        { mode = 2, cardId = "EX1_160a", name = "Summon a Panther",
          text = "Summon a 3/2 Panther.", playable = true },
      },
    },
  })
end

H.suite("ui: a pending choice raises a prompt of two mode cards", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "EX1_160" }))
    H.notOk(board.dimmer:IsShown(), "no prompt without a pending choice")
    H.eq(#board.choosePool.used, 0, "and no mode cards drawn")

    board:SetSnapshot(chooseSnapshot())
    H.ok(board.dimmer:IsShown(), "the dimmer is up")
    H.ok(board.chooseTitle:IsShown(), "the prompt is titled")
    H.eq(#board.choosePool.used, 2, "exactly two mode cards")
    H.ok(board.L.choosePrompt, "and the layout produced prompt rects")
  end)
end)

H.suite("ui: the prompt renders each mode from its OWN printed data", function(ns, H)
  -- The mode cards are real cards in printed data, so they render with the
  -- mode's name and rules text and need no authored UI strings.
  withBoard(ns, function(board)
    board:SetSnapshot(chooseSnapshot())
    local a = board.choosePool.used[1].descriptor
    local b = board.choosePool.used[2].descriptor
    H.eq(a.name, "Leader of the Pack", "option 1 is the first mode")
    H.eq(b.name, "Summon a Panther", "option 2 is the second")
    H.ok(a.text and #a.text > 0, "option 1 carries its rules text")
    H.ok(b.text and #b.text > 0, "option 2 carries its rules text")
  end)
end)

H.suite("ui: clicking a mode emits PLAY_CARD carrying that mode", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(chooseSnapshot())
    board.choosePool.used[2].frame:Click("LeftButton")
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "PLAY_CARD", "it is a play")
    H.eq(intents[1].mode, 2, "carrying the chosen mode")
    H.eq(intents[1].handIndex, 1, "and the pending hand index")
    H.eq(intents[1].position, 3, "and the pending board position")
  end)
end)

H.suite("ui: an unplayable mode has no glow and does not respond", function(ns, H)
  --[[ Power of the Wild with a full board. The option stays visible so the
       player can see WHY the other one is the only choice. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(chooseSnapshot({
      { mode = 1, cardId = "EX1_160b", name = "Leader of the Pack",
        text = "Give your minions +1/+1.", playable = true },
      { mode = 2, cardId = "EX1_160a", name = "Summon a Panther",
        text = "Summon a 3/2 Panther.", playable = false,
        reason = "REQ_NUM_MINION_SLOTS" },
    }))
    local live, dead = board.choosePool.used[1], board.choosePool.used[2]
    H.eq(live.frame:GetAlpha(), 1, "the playable mode is at full alpha")
    H.eq(dead.frame:GetAlpha(), 1, "the unplayable one is not faded (Hearthstone)")
    H.ok(live.glow:IsShown(), "the playable mode glows green")
    H.notOk(dead.glow:IsShown(), "the unplayable one has no glow")
    dead.frame:Click("LeftButton")
    H.eq(#intents, 0, "clicking the unplayable mode does nothing")
    live.frame:Click("LeftButton")
    H.eq(#intents, 1, "clicking the live one still works")
    H.eq(intents[1].mode, 1, "with the right mode")
  end)
end)

H.suite("ui: clicking off the prompt cancels instead of hitting the board", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(chooseSnapshot())
    board.dimmer:Click("LeftButton")
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "CANCEL_MODE", "the choice was cancelled")
  end)
end)

H.suite("ui: the prompt comes down again and reuses its widgets", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(chooseSnapshot())
    local n = board:FrameCount()
    board:SetSnapshot(snapshot({ "EX1_160" }))
    H.notOk(board.dimmer:IsShown(), "the dimmer is down")
    H.notOk(board.chooseTitle:IsShown(), "the title is down")
    H.eq(#board.choosePool.used, 0, "mode cards released")
    board:SetSnapshot(chooseSnapshot())
    H.eq(board:FrameCount(), n, "raising it again created ZERO new frames")
  end)
end)

H.suite("ui: the prompt survives a resize", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(chooseSnapshot())
    for _, wh in ipairs({ { 800, 500 }, { 1920, 1080 }, { 1024, 640 } }) do
      board.frame:SetSize(wh[1], wh[2])
      board:Relayout()
      H.ok(board.dimmer:IsShown(), "prompt still up at " .. wh[1] .. "x" .. wh[2])
      H.eq(#board.choosePool.used, 2, "still two modes at " .. wh[1] .. "x" .. wh[2])
    end
  end)
end)

--===================================================== aiming by dragging

local function aimCursorAt(board, r)
  _G.GetCursorPosition = function()
    local s = board.frame:GetEffectiveScale()
    return (r.x + r.w / 2) * s, (r.y + r.h / 2) * s
  end
end

H.suite("ui: the hero power is aimed by dragging it", function(ns, H)
  --[[ THE COMPLAINT. You had to click the hero power and then click a target.
       Fireblast is a thing you drag onto a face, and this was the one
       interaction in the game that did not match the gesture it copies.

       The drag START sends the same HERO_POWER intent the click sends, so the
       controller raises the same pending target request; the drag STOP supplies
       the click that would have followed. There is no second path through the
       rules, which is why dragging and clicking cannot disagree. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({}, {}, { "CS2_172" }))
    local start = board.heroPower.frame:GetScript("OnDragStart")
    H.ok(start, "the hero power can be dragged from")
    start(board.heroPower.frame)
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "HERO_POWER", "the same intent a click sends")

    --[[ The controller has now raised a target request; the board is told so
         through the snapshot, exactly as it would be in a real match. ]]
    board:SetSnapshot(snapshot({}, {}, { "CS2_172" }, { targeting = { heroPower = true } }))
    aimCursorAt(board, board.L.foeHero)
    board.heroPower.frame:GetScript("OnDragStop")(board.heroPower.frame)
    H.eq(#intents, 2, "the drop supplied the target")
    H.eq(intents[2].kind, "CLICK_FOE_HERO", "aimed at their face")
  end)
end)

H.suite("ui: a drop resolves to whatever is under it", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, { "CS2_172", "CS2_119" },
                               { targeting = {} }))
    aimCursorAt(board, board.L.foeBoardSlots[2])
    board:DropOnTarget()
    H.eq(intents[1].kind, "CLICK_FOE_BOARD", "their board")
    H.eq(intents[1].boardIndex, 2, "the second of their minions")

    board.targetDropConsumed=nil -- a separate gesture
    aimCursorAt(board, board.L.boardSlots[1])
    board:DropOnTarget()
    H.eq(intents[2].kind, "CLICK_BOARD", "and our own is distinct")
    H.eq(intents[2].boardIndex, 1, "slot 1")
  end)
end)

H.suite("ui: releasing an aim over nothing cancels it", function(ns, H)
  --[[ A targeting prompt left up after a drag the player abandoned eats their
       next click somewhere else entirely, which is a baffling thing to hit. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({}, {}, { "CS2_172" }, { targeting = {} }))
    _G.GetCursorPosition = function() return -9999, -9999 end
    board:DropOnTarget()
    H.eq(#intents, 1, "one intent")
    H.eq(intents[1].kind, "CANCEL", "the aim is called off")
  end)
end)

H.suite("ui: a drag with nothing outstanding sends nothing", function(ns, H)
  --[[ A hero power that needed no target has already fired by the time the
       button is released. Sending a click after it would select an attacker
       the player never picked. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, { "CS2_172" }))   -- no targeting
    aimCursorAt(board, board.L.foeBoardSlots[1])
    board:DropOnTarget()
    H.eq(#intents, 0, "no stray click")
  end)
end)

--================================================== live stats on the board

H.suite("ui: a board minion draws what it IS, not what it was printed as", function(ns, H)
  --[[ THE COMPLAINT. You damaged something and the number under it did not
       move. The board rendered the card id, and a card id is printed data --
       the 4/5 a Chillwind Yeti was printed as, forever. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, {}, {
      boardStats = { { atk = 4, health = 2, maxHealth = 5, damaged = true } },
    }))
    local w = board.boardPool.used[1]
    H.eq(w.hp:GetText(), "2", "the damaged health is what is drawn")
    H.eq(w.atk:GetText(), "4", "attack unchanged")
    local c = w.hp.colour
    H.ok(c and c[1] > 0.9 and c[2] < 0.5, "and damaged health is red")
  end)
end)

H.suite("ui: a buffed minion reads as buffed", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, {}, {
      boardStats = { { atk = 6, health = 7, maxHealth = 7, damaged = false } },
    }))
    local w = board.boardPool.used[1]
    H.eq(w.atk:GetText(), "6", "the buffed attack")
    H.eq(w.hp:GetText(), "7", "the buffed health")
    local c = w.atk.colour
    H.ok(c and c[2] > 0.9 and c[1] < 0.6, "shown green, not as printed white")
  end)
end)

H.suite("ui: a card in the HAND still shows its printed stats", function(ns, H)
  --[[ A card in your hand is a card. Only a minion in play is a creature with
       a current state, which is why the live stats are applied to the board
       and deliberately not to the hand. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182" }))
    local w = board.handPool.used[1]
    H.eq(w.atk:GetText(), "4", "printed attack")
    H.eq(w.hp:GetText(), "5", "printed health")
  end)
end)

H.suite("ui: a pooled widget does not carry the last minion's state", function(ns, H)
  --[[ WoW cannot destroy a frame, so every widget is reused. Anything set per
       state -- the blue wash on a frozen minion, red damaged health -- has to
       be cleared per state or it arrives on whatever card is drawn next. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, {}, {
      boardStats = { { atk = 4, health = 1, maxHealth = 5, damaged = true, frozen = true } },
    }))
    local frozen = board.boardPool.used[1].art.colour
    H.ok(frozen and frozen[3] > frozen[1], "frozen is washed blue")

    board:SetSnapshot(snapshot({}, { "CS2_182" }, {}, {
      boardStats = { { atk = 4, health = 5, maxHealth = 5 } },
    }))
    local w = board.boardPool.used[1]
    local c = w.art.colour
    H.ok(not c or (c[1] == 1 and c[2] == 1 and c[3] == 1), "and the next one is not")
    local hp = w.hp.colour
    H.ok(hp and hp[1] == 1 and hp[2] == 1, "nor is its health still red")
  end)
end)

--=================================================== which table we sit at

H.suite("ui: a match picks a board, and matches differ", function(ns, H)
  --[[ Playing every game of your life on one table is the cheapest way a card
       game reads as software rather than as a place. The boards are DISCOVERED
       from whatever art is installed, so this asserts the rotation works
       against however many exist rather than a hardcoded four. ]]
  withBoard(ns, function(board)
    local boards = ns.HearthstoneArt.boards
    if not (boards and #boards > 1) then
      --[[ One board installed is a correct installation: absent art degrades,
           it does not fail. There is simply no rotation to assert. ]]
      H.ok(board:SetBoardArt(0), "the single installed board is still drawn")
      return
    end
    local seen = {}
    for seed = 1, #boards do
      seen[board:SetBoardArt(seed)] = true
    end
    local n = 0
    for _ in pairs(seen) do n = n + 1 end
    H.eq(n, #boards, "every installed board comes up")
  end)
end)

H.suite("ui: the same seed puts both players at the same table", function(ns, H)
  --[[ In a duel the board is derived from the match's agreed seed rather than
       chosen locally, because two people looking at different tables is
       something they would notice immediately and nothing could fix after the
       fact. ]]
  withBoard(ns, function(board)
    H.eq(board:SetBoardArt(12345), board:SetBoardArt(12345), "same seed, same board")
  end)
end)

--=========================================== aiming, reading, and the arrow

H.suite("ui: aiming draws an arrow from the source to the pointer", function(ns, H)
  --[[ Aiming with no arrow is aiming blind: you pick up a Fireball, the board
       lights up, and nothing on screen connects the spell to the thing under
       the cursor. The line IS the feedback. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_029" }, {}, { "CS2_172" }))
    H.notOk(board.arrow.frame:IsShown(), "no arrow when nothing is being aimed")

    board:SetSnapshot(snapshot({ "CS2_029" }, {}, { "CS2_172" },
                               { targeting = { handIndex = 1 } }))
    aimCursorAt(board, board.L.foeBoardSlots[1])
    H.ok(board:UpdateArrow(), "the arrow is live while a target is wanted")
    H.ok(board.arrow.frame:IsShown(), "and on screen")
    H.ok(board.arrow.head:IsShown(), "with a head at the pointer")
  end)
end)

H.suite("ui: a selected attacker is aimed too", function(ns, H)
  --[[ The aim people miss most: you click a minion and then have to remember
       it is waiting for something to hit. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, { "CS2_182" }, { "CS2_172" }, { selectedIndex = 1 }))
    aimCursorAt(board, board.L.foeBoardSlots[1])
    H.ok(board:UpdateArrow(), "an attacker aims")
    local from = board:ArrowOrigin()
    H.eq(from.x, board.L.boardSlots[1].x, "starting at the attacker")

    board:SetSnapshot(snapshot({}, {}, { "CS2_172" }, { heroSelected = true }))
    H.eq(board:ArrowOrigin().x, board.L.hero.x, "or at your hero, weapon in hand")
  end)
end)

H.suite("ui: the arrow goes away when the aim does", function(ns, H)
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_029" }, {}, {}, { targeting = {} }))
    --[[ Aimed at THEIR side: an arrow whose start and end are the same point
         has no direction and is correctly not drawn. ]]
    aimCursorAt(board, board.L.foeHero)
    board:UpdateArrow()
    H.ok(board.arrow.frame:IsShown(), "up while aiming")
    board:SetSnapshot(snapshot({ "CS2_029" }))
    H.notOk(board:UpdateArrow(), "and down when the aim is finished")
    H.notOk(board.arrow.frame:IsShown(), "no line left behind")
  end)
end)

H.suite("ui: right-clicking a card enlarges it to be read", function(ns, H)
  --[[ A minion on the board is minion-sized, which is far too small to read its
       own rules text. Without this, "what does that actually do" could only be
       answered from memory. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_029" }, { "CS2_182" }, {}, {
      boardStats = { { atk = 4, health = 2, maxHealth = 5, damaged = true } },
    }))
    H.notOk(board.inspect.frame:IsShown(), "nothing is being read")

    board.boardPool.used[1].frame:Click("RightButton")
    H.ok(board.inspect.frame:IsShown(), "the card is enlarged")
    H.eq(#intents, 0, "and reading is NOT an action -- no intent was raised")
    H.eq(board.inspect.card.name:GetText(), "Chillwind Yeti", "the right card")
    --[[ It shows what the minion IS, not what it was printed as. ]]
    H.eq(board.inspect.card.hp:GetText(), "2", "with its current health")

    board.inspect.frame:GetScript("OnClick")()
    H.notOk(board.inspect.frame:IsShown(), "and a click puts it away")
  end)
end)

H.suite("ui: a hand card can be read without being played", function(ns, H)
  --[[ The complaint this pairs with: clicking a card in hand used to play it
       instantly. Now left-click selects, right-click reads, and neither one
       commits anything. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_029", "CS2_182" }))
    board.handHitPool.used[2].frame:Click("RightButton")
    H.ok(board.inspect.frame:IsShown(), "enlarged")
    H.eq(board.inspect.card.name:GetText(), "Chillwind Yeti", "the card pointed at")
    H.eq(#intents, 0, "nothing was played")
  end)
end)

H.suite("ui: the End Turn control fills the painted plaque", function(ns, H)
  --[[ Two wrong answers were tried before this one.

       First a solid brown slab with our own label, drawn over the whole plaque
       -- two End Turn buttons, the live one uglier than the painting.

       Then an invisible hit area over the painting, which is right until you
       notice the reference board has "Waiting..." PAINTED into the plaque. A
       transparent control on top of that leaves the table permanently claiming
       to be waiting, whoever's turn it is.

       So the plaque's FACE is filled and relabelled, and the carved surround --
       the part worth keeping -- still shows around the edge. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({"CS2_182"}, {}, {}, { myTurn = true, playable = { true } }))
    H.ok(board.boardArt, "this install has board art")

    -- the inlay is smaller than the plaque, so the ornament survives
    H.ok(board.endTurnBg.texture:find("turn%-button.tga"), "Hearthstone's gold plaque, covering the painted one")
    H.eq(board.endTurnLabel:GetAlpha(), 1, "and it carries live words")
    H.eq(board.endTurnLabel:GetText(), "END TURN", "saying whose turn it is")

    board:SetSnapshot(snapshot({}, {}, {}, { myTurn = false }))
    H.eq(board.endTurnLabel:GetText(), "ENEMY TURN", "and when it is not")
    H.eq(board.endTurnState, "grey", "the plaque dims")
  end)
end)

H.suite("ui: a card in the fan LEANS, and the one you read stands up", function(ns, H)
  --[[ A hand is held, so the cards lean away from centre. This was left out of
       the first pass because WoW cannot rotate a frame -- only a texture -- and
       a texture that fills its rectangle loses its corners the moment it turns.

       The answer is room: the card's frame is grown by exactly what the widest
       lean needs and the face is drawn inset inside it, so a leaning card and
       an upright one are the same size on screen. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162",
                                 "CS2_182", "CS2_029" }))
    local slots = board.L.handSlots
    H.ok(slots[1].rot > 0, "the left of the fan leans one way")
    H.ok(slots[5].rot < 0, "the right leans the other")
    H.ok(math.abs(slots[3].rot) < 1e-9, "and the middle is upright")

    -- the lean reached the widget, not just the layout
    H.ok(board.handPool.used[1].lean > 0, "the left card is actually turned")
    H.ok(board.handPool.used[5].lean < 0, "and the right one the other way")

    --[[ Every card is padded by the same amount whatever its angle, or the
         leaning ones would be visibly smaller than the upright ones. ]]
    H.eq(slots[1].lean, slots[3].lean, "the same room is reserved for each")
    H.ok(slots[1].lean > 1, "and it is more than the card itself")

    --[[ The card you are pointing at is the one you are READING, so it rights
         itself -- the upright cost and name stop disagreeing with the
         picture. ]]
    board:SetHover(1)
    H.eq(board:HandRectFor(1).rot, 0, "the hovered card stands up straight")
    H.eq(board.handPool.used[1].lean, 0, "and the widget follows")
  end)
end)

H.suite("ui: a full hand overlaps instead of spreading out", function(ns, H)
  --[[ The fan used to be given a fixed slice of the WINDOW, which is the wrong
       unit: how much room ten cards need depends on how big a card is, and a
       card is sized from the window's HEIGHT. On a wide window that slice was
       far more room than the hand needed, so the cards stopped overlapping and
       laid themselves out in a row. ]]
  withBoard(ns, function(board)
    local ten = {}
    for i = 1, 10 do ten[i] = "CS2_182" end
    board:SetSnapshot(snapshot(ten))
    local L, D = board.L, ns.Layout.design
    H.eq(#L.handSlots, 10, "ten cards")

    local pitch = L.handSlots[2].x - L.handSlots[1].x
    H.ok(pitch < L.cardW, "each card is partly behind the last")
    H.ok(pitch / L.cardW <= D.HAND_PITCH_FULL + 0.03,
         ("overlapped to about half a card (%.2f)"):format(pitch / L.cardW))
    H.ok(pitch / L.cardW >= D.HAND_MIN_REVEAL - 0.000001,
         "but never so far that a mana cost is hidden")
  end)
end)

--=============================================== calling off an aim, and flight

H.suite("ui: right-click calls off an aim in progress", function(ns, H)
  --[[ The universal "no": you pick up a Fireball, change your mind, and
       right-click to put it down. Without it the only way out of a targeting
       prompt was to find somewhere harmless to drop it -- and on a board full
       of legal targets there is nowhere harmless.

       It is POLLED rather than bound to a click handler because the gesture
       happens mid-drag: the left button is already held, so no click script is
       going to fire. ]]
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_029" }, {}, { "CS2_172" },
                               { targeting = { handIndex = 1 } }))
    Stub.mouseDown = {}
    H.ok(board:Aiming(), "something is being aimed")
    board:PollCancel()
    H.eq(#intents, 0, "nothing cancelled while the button is up")

    Stub.mouseDown = { RightButton = true }
    board:PollCancel()
    H.eq(#intents, 1, "the right button calls it off")
    H.eq(intents[1].kind, "CANCEL", "as a cancel")

    --[[ Edge-triggered: holding the button must not keep cancelling whatever
         the player does next. ]]
    board:PollCancel()
    H.eq(#intents, 1, "and only once while it is held")
    Stub.mouseDown = {}
  end)
end)

H.suite("ui: right-click does nothing when nothing is being aimed", function(ns, H)
  withBoard(ns, function(board, intents)
    board:SetSnapshot(snapshot({ "CS2_029" }))
    Stub.mouseDown = { RightButton = true }
    H.notOk(board:Aiming(), "no aim outstanding")
    board:PollCancel()
    H.eq(#intents, 0, "so the right button is not a cancel")
    Stub.mouseDown = {}
  end)
end)

H.suite("ui: the card being played gets a frame of its OWN", function(ns, H)
  --[[ THE BUG. A play animation runs for a third of a second AFTER the card
       has left the hand, and the stage handed it handPool.used[handIndex] --
       which by then is whichever card SLID INTO that slot. So playing a card
       took the next one along and faded it to nothing, and because the fade
       outlived the relayout it left a live card sitting at zero alpha: a card
       that had gone invisible.

       The pooled-widget generation counter cannot catch this one. The widget
       it grabs is live and current -- it is the right frame for the wrong
       card. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_029", "CS2_182", "EX1_162" }))
    local neighbour = board.handPool.used[2]

    H.ok(board:BeginPlayAnimation(1), "the played card is lifted out of the hand")
    H.ok(board.flyingCard.frame:IsShown(), "into a frame of its own")
    H.eq(board.flyingCard.name:GetText(), "Fireball", "carrying the right card")

    --[[ And the stage now points the animation at THAT, not at the hand. ]]
    local handle = board:Stage():Card(1)
    handle:Alpha(0)
    H.eq(board.flyingCard.frame:GetAlpha(), 0, "the copy is what fades")
    H.eq(neighbour.frame:GetAlpha(), 1, "the card still in your hand is untouched")

    board:EndPlayAnimation()
    H.notOk(board.flyingCard.frame:IsShown(), "and the copy is put away after")
  end)
end)

H.suite("ui: the rope goes away when the turn does, and stays away", function(ns, H)
  --[[ THE BUG, TWICE. Hiding the rope was not enough: it is driven by a
       TIMELINE that runs for the length of the turn, and that timeline does not
       stop when the turn does. It called Burn again on the very next frame,
       which set the value and called Show -- so the rope came back, fully
       burnt, and sat there through the opponent's turn and into the next. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({}, {}, {}, { myTurn = true }))
    local rope = board:Stage():Toast("rope", {})
    rope:Burn(0.5)
    H.ok(board.rope.frame:IsShown(), "the rope is up")

    board:ClearRope()
    H.notOk(board.rope.frame:IsShown(), "the turn ended and it came down")

    --[[ The timeline is STILL RUNNING and still holds its handle. This is the
         frame on which the rope used to reappear. ]]
    rope:Burn(0.9)
    rope:Urgency(3)
    H.notOk(board.rope.frame:IsShown(), "and the old timeline cannot put it back")
    H.eq(board.ropeBurn, nil, "nor revive the burn")

    -- a NEW turn lights a new rope, through a new handle
    local next = board:Stage():Toast("rope", {})
    next:Burn(0.1)
    H.ok(board.rope.frame:IsShown(), "the next turn's rope still works")
  end)
end)

--============================================ the fan holds still, and the mana shows

local function anchorOf(frame)
  local _, _, _, x, y = frame:GetPoint(1)
  return x, y
end

H.suite("ui: hovering one card does not shift the rest of the hand", function(ns, H)
  --[[ THE BUG. A card that can lean is drawn inside a frame BIGGER than the
       card -- that extra space is the room the lean turns in -- so the frame's
       corner sits a fraction of a card outside the card's own. The stored rect
       dropped that padding, so anything that re-anchored the widget afterwards
       used the card's corner as the frame's and the card jumped sideways by a
       tenth of its width.

       Hovering re-applies every card in the hand, so pointing at one card
       shifted all of them. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162",
                                 "CS2_182", "CS2_029" }))
    local before = {}
    for i, wdg in ipairs(board.handWidgets) do
      before[i] = { anchorOf(wdg.frame) }
    end

    board:SetHover(3)
    for i, wdg in ipairs(board.handWidgets) do
      if i ~= 3 then
        local x, y = anchorOf(wdg.frame)
        H.ok(math.abs(x - before[i][1]) < 0.01,
             ("card %d did not move sideways"):format(i))
        H.ok(math.abs(y - before[i][2]) < 0.01,
             ("nor vertically: %d"):format(i))
      end
    end

    --[[ ...and going back to no hover leaves them exactly where they began,
         rather than a tenth of a card further along each time. ]]
    board:SetHover(nil)
    for i, wdg in ipairs(board.handWidgets) do
      local x, y = anchorOf(wdg.frame)
      H.ok(math.abs(x - before[i][1]) < 0.01, ("card %d is back"):format(i))
      H.ok(math.abs(y - before[i][2]) < 0.01, ("exactly: %d"):format(i))
    end
  end)
end)

H.suite("ui: the mana count is not buried under the hand", function(ns, H)
  --[[ The readout sits in the trough along the bottom of the board, which is
       exactly where the hand fans across. It was a FontString on the BOARD
       frame, so it drew at the board's level -- underneath every card. The
       crystals were fine: they are frames and had been given the furniture
       level. The number was the one piece that had not. ]]
  withBoard(ns, function(board)
    local ten = {}
    for i = 1, 10 do ten[i] = "CS2_182" end
    board:SetSnapshot(snapshot(ten, {}, {}, { mana = 4, maxMana = 7 }))
    H.eq(board.manaText:GetText(), "4/7", "the readout says what you have")

    local hand = board.handWidgets[1]
    H.ok(board.manaHolder:GetFrameLevel() > hand.frame:GetFrameLevel(),
         "and it draws above the hand")
    H.ok(board.crystalPool.used[1].frame:GetFrameLevel()
         > hand.frame:GetFrameLevel(), "as do the crystals")
  end)
end)

H.suite("ui: a full hand stays clear of the board's right-hand furniture", function(ns, H)
  --[[ The fan is centred on the table, so how wide it gets decides what it
       runs into. It must not reach the deck or the End Turn plaque -- those are
       things you click, and a card lying over them makes them unclickable in a
       way nothing on screen explains. ]]
  withBoard(ns, function(board)
    local ten = {}
    for i = 1, 10 do ten[i] = "CS2_182" end
    board:SetSnapshot(snapshot(ten))
    local L = board.L
    local right = L.handSlots[10].x + L.handSlots[10].w
    H.ok(right < L.deck.x, "the hand stops short of the deck")
    H.ok(right < L.endTurn.x, "and of the End Turn plaque")
    H.ok(L.handSlots[1].x > 0, "and does not run off the left edge")
  end)
end)

H.suite("ui: a card that SLIDES keeps its padding and its lean", function(ns, H)
  --[[ THE BUG, and it is the one that made hovering shift the hand.

       A card that can lean is drawn inside a frame bigger than the card -- the
       room its tilt turns in -- so the frame's corner sits a fraction of a card
       outside the card's own. The tween rebuilt the rect from x, y, w and h and
       nothing else, so every sliding card lost that padding and its lean: the
       frame shrank, the anchor jumped sideways by a tenth of a card, and the
       card FINISHED the slide shifted, because the last tick is what the frame
       keeps. Anything that redrew the hand set it off. ]]
  withBoard(ns, function(board)
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162" }))
    -- drawing a card makes the fan slide apart
    board:SetSnapshot(snapshot({ "CS2_182", "CS2_029", "EX1_162", "CS2_182" }))
    H.ok(#board.tweens > 0, "the hand is sliding")

    --[[ Run it to the end, checking on every frame that the anchor stays the
         padded one. A single bad frame is a visible jump. ]]
    for _ = 1, 40 do
      board:TickFX(1 / 60)
      for i, wdg in ipairs(board.handWidgets) do
        local _, _, _, x = wdg.frame:GetPoint(1)
        H.ok(math.abs((wdg.rect.x - (wdg.padX or 0)) - x) < 0.01,
             ("card %d is anchored where its padding says"):format(i))
        H.ok((wdg.padX or 0) > 0, ("card %d kept its padding"):format(i))
      end
    end

    --[[ And it lands where the layout put it, not a tenth of a card off. ]]
    for i, r in ipairs(board.L.handSlots) do
      local wdg = board.handWidgets[i]
      local _, _, _, x, y = wdg.frame:GetPoint(1)
      H.ok(math.abs(x - (r.x - wdg.padX)) < 0.5, ("card %d landed"):format(i))
      H.ok(math.abs(y - (r.y - wdg.padY)) < 0.5, ("at the right height: %d"):format(i))
    end
  end)
end)

H.suite("ui: enemy mana and power cost survive resizing before and during a match", function(ns, H)
  withBoard(ns, function(b)
    b.frame:SetSize(1000, 700)
    b:SetSnapshot(snapshot({}, {}, {}, {foeMana=2, foeMaxMana=5,
      foeHeroPower={cardId="CS2_034", cost=2, used=false}}))
    H.eq(b.foeManaText:GetText(), "2/5")
    H.eq(b.foeHeroPower.armor:GetText(), "2")
    b.frame:SetSize(1500, 900)
    H.eq(b.foeManaText:GetText(), "2/5")
    H.eq(b.foeHeroPower.armor:GetText(), "2")
  end)
end)

H.suite("ui: untargeted spell drops anywhere on the field without insertion markers", function(ns, H)
  withBoard(ns, function(b, intents)
    b:SetSnapshot(snapshot({"GAME_005"}, {}, {}, {playable={true}}))
    local r = b.L.field
    Stub.CursorOver(b.frame, r.x+r.w/2, r.y+r.h*0.85)
    b:BeginDrag(b.handWidgets[1])
    b:TickFX(0.01)
    H.notOk(b.dropPreview:IsShown(), "spells have no insertion marker")
    H.ok(b.handWidgets[1].glow:IsShown(), "valid drop has a border")
    H.ok(b:EndDrag(b.handWidgets[1]))
    H.eq(intents[#intents].kind, "PLAY_CARD")
    H.eq(intents[#intents].position, nil, "no unit position for a spell")
  end)
end)

H.suite("ui: powers and weapons explain themselves on hover", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {heroPower={cardId="CS2_034",cost=2},
      foeHeroPower={cardId="CS1h_001",cost=2},hasWeapon=true,
      weapon={cardId="CS2_082",atk=1,health=2}}))
    for _, w in ipairs({b.heroPower,b.foeHeroPower,b.weapon}) do
      w.frame:GetScript("OnEnter")()
      H.ok(b.hoverCard.frame:IsShown(), "the card itself is shown beside it, as in Hearthstone")
      H.ok(#b.tooltip.title:GetText() > 0, "and the tooltip knows its name")
      w.frame:GetScript("OnLeave")()
      H.notOk(b.hoverCard.frame:IsShown())
      H.notOk(b.tooltip:IsShown())
    end
    -- a keyword on the card gets Hearthstone's reminder box
    local kws = ns.Board.KeywordsOf(ns.PrintedCards["CS2_179"])   -- Sen'jin: Taunt
    H.eq(kws[1][1], "Taunt")
  end)
end)

H.suite("ui: layout keeps reused mouse frames visible during a gesture", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({"CS2_182","GAME_005"}))
    local hit=b.handHitPool.used[1].frame
    local hide, calls = hit.Hide, 0
    hit.Hide=function(self) calls=calls+1; return hide(self) end
    b:Relayout()
    H.eq(calls,0,"reused hit areas never lose mouse capture through Hide")
    b:SetSnapshot(snapshot({}))
    H.ok(calls>0,"removed cards do release their hit areas")
  end)
end)

H.suite("ui: minions use portrait frames and show attack state", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182"}, {}, {boardStats={{atk=4,health=5,sleeping=true}}}))
    local w=b.myMinions[1]
    H.notOk(w.cost:IsShown(),"no mana badge on a played minion")
    H.notOk(w.body:IsShown(),"rules text stays in inspection")
    H.ok(w.states.sleeping:IsShown(),"summoning sickness shows Hearthstone's Zzz")
    H.eq(w.status:GetText(),"","as art, not as text")
    b.frame:SetSize(1400,800)
    H.notOk(b.myMinions[1].cost:IsShown(),"resize preserves portrait mode")
  end)
end)

H.suite("ui: Hearthstone's own state art replaces tints and labels", function(ns,H)
  withBoard(ns,function(b)
    -- Ragnaros is legendary: the dragon wraps the board frame and the hand frame.
    b:SetSnapshot(snapshot({"EX1_298"}, {"EX1_298","CS2_182"}, {}, {boardStats={
      {atk=8,health=8,frozen=true,deathrattle=true,trigger=true},
      {atk=4,health=5,trigger=true,divineShield=true}}}))
    local rag, yeti = b.myMinions[1], b.myMinions[2]
    H.ok(rag.legend:IsShown() and rag.legend:GetTexture():find("inplay_minion_legendary"),
         "a legendary minion wears the board dragon")
    H.notOk(yeti.legend:IsShown(), "a common one does not")
    H.ok(rag.states.frozen:IsShown(), "frozen is the ice overlay")
    H.ok(rag.states.deathrattle:IsShown(), "the skull shows under a Deathrattle")
    H.notOk(rag.states.trigger:IsShown(), "and takes the one icon slot over a trigger")
    H.ok(yeti.states.trigger:IsShown(), "a triggered minion shows the bolt")
    H.ok(yeti.shield:GetTexture():find("inplay_minion_divine_shield"), "divine shield is the native bubble")
    local hand = b.handWidgets[1]
    H.ok(hand.legend:IsShown() and hand.legend:GetTexture():find("inhand_minion_legendary"),
         "a legendary in hand wears the hand dragon")
    -- SetLiveStats is exported; a caller passing live flags for a hand card
    -- must not give it board art.
    ns.Widgets.SetLiveStats(hand, {atk=8,health=8,sleeping=true,frozen=true,deathrattle=true})
    for key, t in pairs(hand.states) do H.notOk(t:IsShown(), "no board state on a hand card: "..key) end
    ns.Widgets.SetFaceDown(hand, true)
    H.notOk(hand.legend:IsShown(), "a card back hides the dragon too")
    ns.Widgets.SetFaceDown(hand, false)
  end)
end)

H.suite("ui: Hearthstone-style typefaces ship, and one the client refuses falls back", function(ns,H)
  Stub.Install(_G)
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  for _, role in ipairs({"TITLE", "BODY", "NUMBER"}) do
    local path = ns.Fonts[role]
    H.ok(path:find("Art\\Fonts\\", 1, true), role .. " uses a shipped face")
    local f = io.open((path:gsub("^Interface\\AddOns\\", ""):gsub("\\", "/")), "rb")
    H.ok(f, role .. " is installed"); if f then f:close() end
  end
  -- A client that cannot open the file must not leave every string fontless.
  local real = _G.CreateFrame
  _G.CreateFrame = function(...)
    local fr = real(...)
    local make = fr.CreateFontString
    fr.CreateFontString = function(self, ...)
      local fs = make(self, ...)
      fs.SetFont = function() return false end
      return fs
    end
    return fr
  end
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  _G.CreateFrame = real
  for _, role in ipairs({"TITLE", "BODY", "NUMBER"}) do
    H.eq(ns.Fonts[role], "Fonts\\FRIZQT__.TTF", role .. " falls back to the client's own font")
  end
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
end)

H.suite("ui: Hearthstone's interface sounds mark the turn, End Turn, a hover and a win", function(ns,H)
  withBoard(ns,function(b)
    local function played(name)
      local n = 0
      for _, s in ipairs(Stub.R.sounds) do if s.file and s.file:find(name, 1, true) then n = n + 1 end end
      return n
    end
    b:SetSnapshot(snapshot({"CS2_182","CS2_182"}, {}, {}, {myTurn=true,
      mulligan={hand={"CS2_182","CS2_182","CS2_182"}, marked={}, waiting=false, coin=false}}))
    H.eq(played("playerturn.mp3"), 0, "no chime while the mulligan is open")
    b:SetSnapshot(snapshot({"CS2_182","CS2_182"}, {}, {}, {myTurn=true}))
    H.eq(played("playerturn.mp3"), 1, "the first turn is announced as the mulligan closes")
    b:SetSnapshot(snapshot({"CS2_182","CS2_182"}, {}, {}, {myTurn=false}))
    H.eq(played("playerturn.mp3"), 1, "the enemy's turn has no chime")
    b:SetSnapshot(snapshot({"CS2_182","CS2_182"}, {}, {}, {myTurn=true}))
    H.eq(played("playerturn.mp3"), 2, "and yours does, every time")
    b.endTurn:GetScript("OnClick")()
    H.eq(played("endturn.mp3"), 1, "End Turn clicks")
    ns.Sounds.ResetMatch(); b:SetHover(nil)
    local before = played("cardhover.mp3")
    b:SetHover(2)
    H.eq(played("cardhover.mp3"), before + 1, "lifting a hand card ticks")
    b:SetHover(nil)
    H.eq(played("cardhover.mp3"), before + 1, "and letting it go is silent")
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true, over=true, winner=1, player=1}))
    Stub.Advance(0.1)   -- with the result banner (after any hero's explosion)
    H.eq(played("Pegasus_Stinger_Alliance"), 1, "a win plays the victory sting")
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true, over=true, winner=1, player=1}))
    Stub.Advance(2)
    H.eq(played("Pegasus_Stinger_Alliance"), 1, "once, however often the finished board is redrawn")
    H.eq(played("victory.mp3"), 0, "not the modern track with the Lich King's line")
    local stopped = Stub.Count("StopSound")
    b.frame:Hide()
    H.ok(Stub.Count("StopSound") > stopped, "leaving the table stops it")
  end)
end)

H.suite("ui: golden cards, frozen heroes and spent hero powers", function(ns,H)
  withBoard(ns,function(b)
    local w = ns.Widgets.New(b.frame)
    local d = b.resolver:Card("EX1_298"); d.golden = true
    ns.Widgets.SetDescriptor(w, d)
    ns.Widgets.ApplyRect(w, {x=0,y=0,w=100,h=140})
    H.ok(w.skin:GetTexture():find("inhand_minion_premium"), "a golden card has the gold frame")
    H.ok(w.legend:GetTexture():find("inhand_minion_legendary_premium"), "and a gold dragon")
    b:SetSnapshot(snapshot({}, {}, {}, {hero={cardId="HERO_08",health=30,frozen=true},
      heroPower={cardId="CS2_034",cost=2,used=true}}))
    H.ok(b.hero.frozenFx:IsShown(), "a frozen hero is encased in ice")
    H.ok(b.heroPower.spentFx:IsShown(), "a spent hero power turns over")
    H.notOk(b.heroPower.art:IsShown(), "and its face is hidden")
    b:SetSnapshot(snapshot({}, {}, {}, {hero={cardId="HERO_08",health=30},
      heroPower={cardId="CS2_034",cost=2,usable=true}}))
    H.notOk(b.hero.frozenFx:IsShown(), "thawing removes the ice")
    H.notOk(b.heroPower.spentFx:IsShown(), "a fresh turn turns it face up")
  end)
end)

H.suite("ui: only your turn is announced, and the result persists on resize", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=false}))
    H.notOk(b.banner:IsShown(),"Hearthstone does not announce the opponent's turn")
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    H.eq(b.banner.text:GetText(),"YOUR TURN")
    Stub.Advance(2)
    H.notOk(b.banner:IsShown(),"turn banner expires")
    b:SetSnapshot(snapshot({}, {}, {}, {over=true,winner=1,player=1,foeHero={health=0}}))
    H.eq(b.result.text:GetText(),"Victory!")
    H.ok(b.result.ornament:GetTexture():find("result%-ornament.tga"), "crowned, with laurels and trumpets")
    H.ok(b.result.ribbon:GetTexture():find("result%-plaque.tga"), "on the wooden plaque")
    H.ok(b.bg:IsDesaturated(), "the table is drained to grey")
    Stub.Advance(1.5)   -- past the hero's destruction
    b.frame:SetSize(1400,800)
    H.eq(b.foeHero.frame:GetAlpha(),0,"defeated hero stays gone")
    H.ok(b.result:IsShown(),"the result survives the resize")
    b:ResetMatch()
    H.notOk(b.result:IsShown(),"next match clears the result")
    H.notOk(b.bg:IsDesaturated(),"and gives the table its colour back")
  end)
end)

H.suite("ui: a defeat cracks and drains your portrait, without the laurels", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    b:SetSnapshot(snapshot({}, {}, {}, {over=true,winner=2,player=1}))
    H.eq(b.result.text:GetText(),"Defeat")
    H.ok(b.result.crack:IsShown(), "the portrait is cracked")
    H.ok(b.result.ornament:GetTexture():find("result%-frame.tga"), "the arch alone, nothing to celebrate")
  end)
end)

H.suite("ui: damage hits are event-driven and never replay on resize", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {eventSeq=1,heroId=7,hero={health=30}}))
    b:SetSnapshot(snapshot({}, {}, {}, {eventSeq=2,heroId=7,hero={health=27},
      presentationEvents={{seq=2,targetId=7,amount=3,heal=false}}}))
    H.eq(#b.hitLabels,1)
    H.eq(b.hitLabels[1].label:GetText(),"-3")
    b.frame:SetSize(1400,800)
    H.eq(#b.hitLabels,1)
    Stub.Advance(2)
    H.notOk(b.hitLabels[1].active,"hit fades out")
  end)
end)

H.suite("ui: dragging carries the whole card and hides enemy secret faces", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"GAME_005"}, {}, {}, {playable={true}}))
    local r=b.L.field
    local x,y=r.x+r.w/2,r.y+r.h/2
    Stub.CursorOver(b.frame,x,y)
    b:BeginDrag(b.handWidgets[1]); b:TickFX(0.01)
    local moved=b.handWidgets[1].rect
    H.ok(math.abs(moved.x+moved.w/2-x)<0.01,"card follows pointer horizontally")
    H.ok(math.abs(moved.y+moved.h/2-y)<0.01,"card follows pointer vertically")
    b:BeginPlayAnimation(1,"EX1_287")
    H.ok(b.flyingCard.faceDown,"opponent secret remains hidden in flight")
    b:AddHistory("EX1_287","Enemy played",true)
    H.eq(b.history[1].cardId,nil,"history cannot expose an unrevealed secret")
  end)
end)

H.suite("ui: played portrait badges stay inside native sockets across resize", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182"}, {}, {boardStats={{atk=4,health=5}}}))
    for _,size in ipairs({{1280,720},{900,650},{1600,900}}) do
      b.frame:SetSize(size[1],size[2])
      local w=b.myMinions[1]
      H.ok(w.art:GetHeight()>w.art:GetWidth(),"portrait window is oval")
      H.eq(w.glow:GetTexture(),w.skin:GetTexture():gsub("%.tga$", "-glow.tga"),"outline uses the bright native silhouette")
      for i,n in ipairs({w.atk,w.hp}) do
        local g=n.glyphs[1]
        local fw,fh=w.skin:GetWidth(),w.skin:GetHeight()
        local cx,cy=glyphCenter(g)
        H.ok(math.abs((cx/fw+.5)*256-({75,179})[i])<.01,"digit lies in painted socket horizontally")
        H.ok(math.abs((.5-cy/fh)*256-177)<.01,"digit lies in painted socket vertically")
      end
    end
  end)
end)

H.suite("ui: a targeted spell is held beside your hero and aimed from it", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_029"}, {}, {}, {playable={true},handNeedsTarget={true}}))
    local r=b.L.field
    Stub.CursorOver(b.frame,r.x+r.w/2,r.y+r.h/2)
    local w=b.handWidgets[1]
    b:BeginDrag(w); b:TickFX(.01)
    H.ok(b.dragAiming)
    local hold=b:SpellHoldRect()
    H.eq(w.rect.x,hold.x,"the card is held up beside the hero")
    H.eq(w.frame:GetAlpha(),1,"whole, not a ghost in the hand")
    H.ok(hold.x+hold.w<=b.L.hero.x,"left of the portrait, clear of it")
    H.eq(b:ArrowOrigin(),b.L.hero,"the arrow comes out of your hero")
    local copies=0
    for _,wd in ipairs(b.handWidgets) do if wd.frame:IsShown() and wd.descriptor and wd.descriptor.cardId=="CS2_029" then copies=copies+1 end end
    H.eq(copies,1,"one card, no duplicate floating copy")
    H.notOk(b.dropPreview:IsShown(),"aiming never shows unit placement")
    b:EndDrag(w)
    H.eq(w.frame:GetAlpha(),1,"release restores the hand")
    H.eq(b.dragAiming,nil)
    b:SetSnapshot(snapshot({"GAME_005"}, {}, {}, {playable={true}}))
    b:BeginDrag(b.handWidgets[1]); b:TickFX(.01)
    H.eq(b:ArrowOrigin(),nil,"untargeted spells have no targeting arrow")
  end)
end)

H.suite("ui: a battlecry minion lands in its slot and waits to be aimed",function(ns,H)
  --[[ Dropping Ironforge Rifleman is a PLACE; the shot comes after. The old
       drop treated the slot under the pointer as the target (often your own
       minion) and then cancelled whatever was left, so the prompt never
       survived the drop. ]]
  withBoard(ns,function(b,intents)
    local base={playable={true},boardStats={{instanceId=11,atk=4,health=5}},
                foeBoardStats={{instanceId=21,atk=1,health=1}},handStats={{instanceId=31}}}
    b:SetSnapshot(snapshot({"CS2_141"},{"CS2_182"},{"CS2_231"},base))
    local record=b.onIntent
    b.onIntent=function(i)
      record(i)
      if i.kind=="PLAY_CARD" then
        local s={}; for k,v in pairs(base) do s[k]=v end
        s.targeting={handIndex=i.handIndex,legal={21},position=i.position}
        b:SetSnapshot(snapshot({"CS2_141"},{"CS2_182"},{"CS2_231"},s))
      elseif i.kind=="CANCEL" then
        b:SetSnapshot(snapshot({"CS2_141"},{"CS2_182"},{"CS2_231"},base))
      end
    end
    local z=b.L.dropZones[1]
    Stub.CursorOver(b.frame,z.x+z.w/2,z.y+z.h/2)
    local w=b.handWidgets[1]
    b:BeginDrag(w); b:TickFX(.01)
    H.notOk(b.dragAiming,"a minion is placed, not aimed, while dragged")
    H.ok(b:EndDrag(w),"the drop was taken")
    H.eq(#intents,1,"only the play was sent")
    H.eq(intents[1].kind,"PLAY_CARD"); H.eq(intents[1].position,1)
    H.ok(b.snapshot.targeting,"and the prompt is still up")

    b:TickFX(.01)
    H.ok(b.placementGhost.frame:IsShown(),"the minion stands on the board")
    H.eq(b.placementGhost.frame:GetAlpha(),1,"whole, not a drop ghost")
    H.eq(b.handWidgets[1].frame:GetAlpha(),0,"and has left the hand")
    local slot=b.placementGhost.rect
    local from=b:ArrowOrigin()
    H.ok(from and from.x==slot.x and from.y==slot.y,"the arrow comes out of the minion")
    H.ok(b.myMinions[1].rect.x>slot.x,"the Yeti stepped aside to make room")
    local _,src=b:HoverState()
    H.eq(src,"s1","the opponent is told the aim comes from slot 1")

    -- right-click calls it off, and the card is back in the hand
    Stub.mouseDown={RightButton=true}
    b:PollCancel()
    Stub.mouseDown={}
    H.eq(intents[#intents].kind,"CANCEL")
    b:TickFX(.01)
    H.notOk(b.placementGhost.frame:IsShown(),"the ghost is gone")
    H.eq(b.handWidgets[1].frame:GetAlpha(),1,"the card is back in hand")
    H.eq(b:ArrowOrigin(),nil,"and nothing is being aimed")
  end)
end)

H.suite("ui: cancelled drag consumes the eventual left release",function(ns,H)
  withBoard(ns,function(b,intents)
    b:SetSnapshot(snapshot({"GAME_005"},{},{},{playable={true}}))
    local w=b.handWidgets[1]
    local r=b.L.field
    Stub.CursorOver(b.frame,r.x+r.w/2,r.y+r.h/2)
    b:BeginDrag(w); b:TickFX(.01)
    Stub.mouseDown={LeftButton=true,RightButton=true}
    b:PollCancel()
    H.eq(intents[#intents].kind,"CANCEL")
    local count=#intents
    Stub.mouseDown={}
    H.notOk(b:EndDrag(w))
    b.handHitPool.used[1].frame:GetScript("OnClick")(nil,"LeftButton")
    H.eq(#intents,count,"release cannot play or select the cancelled card")
    H.notOk(b.arrow.frame:IsShown())
  end)
end)

H.suite("ui: playing card has one visible representation until landing",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_182"}))
    local source=b.handWidgets[1]
    b:BeginPlayAnimation(1)
    b:BeginPresentation()
    H.notOk(source.frame:IsShown(),"source is replaced by flight")
    H.ok(b.flyingCard.frame:IsShown())
    b:SetSnapshot(snapshot({}, {"CS2_182"}))
    H.eq(#b.myMinions,0,"destination waits for flight")
    b:EndPresentation()
    H.notOk(b.flyingCard.frame:IsShown(),"flight ends before destination appears")
    H.ok(b.myMinions[1].frame:IsShown())
  end)
end)

H.suite("ui: draw moves a single card from deck and does not replay",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {eventSeq=1}))
    local s=snapshot({"CS2_182"},{},{},{eventSeq=2,
      handStats={{instanceId=20,atk=5,health=6}},
      drawEvents={{seq=2,mine=true,entityId=20}}})
    b:SetSnapshot(s)
    local w=b.handWidgets[1]
    H.eq(w.rect.x,b.L.deck.x)
    H.eq(w.atk:GetText(),"5"); H.eq(w.hp:GetText(),"6")
    b:TickFX(.1)
    local mid=w.rect.x
    b:SetSnapshot(s)
    w=b.handWidgets[1]
    H.ok(math.abs(w.rect.x-mid)<0.001,"refresh preserves draw progress")
    b:TickFX(.6)
    H.ok(math.abs(w.rect.x-b.handRects[1].x)<0.001)
    b:SetSnapshot(s)
    H.ok(math.abs(w.rect.x-b.handRects[1].x)<0.001,"repeat snapshot cannot replay draw")
  end)
end)

H.suite("ui: resolving a play blocks stale gestures until mana refreshes",function(ns,H)
  withBoard(ns,function(b,intents)
    b:SetSnapshot(snapshot({"CS2_182","CS2_029"},{},{},{playable={true,true},handStats={{instanceId=41},{instanceId=42}}}))
    b:BeginPlayAnimation(1); b:BeginPresentation()
    local flying=b.flyingCard.rect
    H.eq(b:BeginDrag(b.handWidgets[2]),false)
    b.onIntent({kind="CLICK_HAND",handIndex=2})
    b:EndDrag(b.handWidgets[2])
    H.eq(#intents,0,"no stale input reaches the controller")
    H.eq(b.flyingCard.rect,flying,"second drag cannot move the flying card")
    b:SetSnapshot(snapshot({"CS2_029"},{"CS2_182"},{},{playable={false},handStats={{instanceId=42}}}))
    b:EndPresentation()
    H.eq(b:BeginDrag(b.handWidgets[1]),false,"new mana governs the surviving card")
  end)
end)

H.suite("ui: enemy spell travels down and scaling preserves its center",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}))
    b:BeginPlayAnimation(1,"CS2_029")
    local start=b.flyingCard.rect
    local stage=b:Stage()
    stage:Card(1):Scale(1.2)
    local r=b.flyingCard.rect
    near(r.x+r.w/2,start.x+start.w/2,.001)
    near(r.y+r.h/2,start.y+start.h/2,.001)
    local tl=ns.Choreography.PlaySpell(stage,{mine=false})
    tl:Start(); tl:Tick(.1)
    r=b.flyingCard.rect
    H.ok(r.y+r.h/2<start.y+start.h/2,"enemy card moves toward the field")
  end)
end)

H.suite("ui: surviving hand cards reflow from their own identity",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_182","CS2_029","CS2_024"},{},{},{handStats={{instanceId=1},{instanceId=2},{instanceId=3}}}))
    b:TickFX(1)
    local origin=b.handWidgets[2].rect
    b:SetSnapshot(snapshot({"CS2_029","CS2_024"},{},{},{handStats={{instanceId=2},{instanceId=3}}}))
    local found
    for _,t in ipairs(b.tweens) do if t.w.handIdentity==2 then found=t end end
    H.ok(found,"surviving card has a movement tween")
    near(found.from.x,origin.x,.001,"does not inherit removed card's position")
    b:SetHover(nil); b:TickFX(.2)
    near(b.handWidgets[1].rect.x,b.handRects[1].x,.001)
  end)
end)

H.suite("ui: lethal skulls draw above both combatants and drops dispatch once",function(ns,H)
  withBoard(ns,function(b,intents)
    b:SetSnapshot(snapshot({}, {"CS2_182"}, {"CS2_182"}, {selectedIndex=1,
      foeBoardStats={{instanceId=55}},combatPreview={[55]={attackerDies=true,defenderDies=true}}}))
    aimCursorAt(b,b.L.foeBoardSlots[1]); b:TickFX(.01)
    H.ok(b.skulls[1]:IsShown()); H.ok(b.skulls[2]:IsShown())
    H.ok(b.skullLayer:GetFrameLevel()>b.foeMinions[1].frame:GetFrameLevel())
    b:DropOnTarget(); b:DropOnTarget()
    H.eq(#intents,1,"duplicate drag release cannot repeat an attack")
  end)
end)

H.suite("ui: unit insertion previews an oval and restores neighbors",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_182"},{"CS2_172"},{},{playable={true}}))
    b:TickFX(1)
    local original=b.myMinions[1].rect
    b:BeginDrag(b.handWidgets[1]); aimCursorAt(b,b.L.dropZones[1]); b:TickFX(.01)
    H.ok(b.placementGhost and b.placementGhost.frame:IsShown())
    H.ok(b.placementGhost.inPlay)
    H.notOk(b.dropPreview:IsShown(),"no green insertion bar")
    H.ok(b.myMinions[1].rect.x~=original.x,"neighbor makes room")
    b:BeginPresentation()
    H.notOk(b.placementGhost.frame:IsShown())
    near(b.myMinions[1].rect.x,original.x,.001)
  end)
end)

--[[ Reported: kill a minion, then at once cast a spell on another -- the board
     was misaligned. The survivors were still sliding into the gap when the
     second spell began, and BeginPresentation dropped every tween, leaving
     each one frozen part-way (frame AND rect, so the spell aimed there too). ]]
H.suite("ui: a spell cast mid-slide finishes the slide, not freezes it",function(ns,H)
  withBoard(ns,function(b)
    local stats={{instanceId=201},{instanceId=202},{instanceId=203}}
    b:SetSnapshot(snapshot({"CS2_029"}, {}, {"CS2_182","CS2_172","CS2_182"},{foeBoardStats=stats}))
    b:TickFX(1)
    b:BeginPresentation()
    b:SetSnapshot(snapshot({"CS2_029"}, {}, {"CS2_182","CS2_182"},
      {foeBoardStats={{instanceId=201},{instanceId=203}}}))
    b:EndPresentation()
    b:TickFX(.05)                             -- the survivor is part-way across
    H.ok(#b.tweens > 0, "the survivor is sliding")
    b:BeginPresentation()                     -- ...and the next spell begins
    for i, slot in ipairs(b.L.foeBoardSlots) do
      near(b.foeMinions[i].rect.x, slot.x, .001, "minion "..i.." is in its slot")
      near(b.foeMinions[i].frame.points[1][4], slot.x-(b.foeMinions[i].padX or 0), .001,
           "and drawn there")
    end
    b:TickFX(1)
    for i, slot in ipairs(b.L.foeBoardSlots) do
      near(b.foeMinions[i].rect.x, slot.x, .001, "still in its slot after the spell")
    end
  end)
end)

H.suite("ui: removing a middle minion reflows survivors from their own positions",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182","CS2_172","CS2_182"}, {},
      {boardStats={{instanceId=101},{instanceId=102},{instanceId=103}}}))
    b:TickFX(1)
    local first,last=b.myMinions[1].rect,b.myMinions[3].rect
    b:BeginPresentation()
    b:SetSnapshot(snapshot({}, {"CS2_182","CS2_182"}, {},
      {boardStats={{instanceId=101},{instanceId=103}}}))
    b:EndPresentation()
    local tween
    for _,t in ipairs(b.tweens) do if t.w.boardIdentity==103 then tween=t end end
    H.ok(tween,"right-hand survivor slides into place")
    near(tween.from.x,last.x,.001,"even identical cards preserve entity position")
    near(b.myMinions[2].frame.points[1][4],last.x-(b.myMinions[2].padX or 0),.001,"no intermediate teleport")
    b:TickFX(.08)
    local x=b.myMinions[2].rect.x
    H.ok(x<last.x and x>b.L.boardSlots[2].x,"smoothly moves left")
    b:TickFX(.2)
    near(b.myMinions[2].rect.x,b.L.boardSlots[2].x,.001)
  end)
end)

H.suite("ui: portrait right-click selects an emote without targeting",function(ns,H)
  withBoard(ns,function(b,intents)
    b:SetSnapshot(snapshot({}, {}, {}))
    b.hero.frame:Click("RightButton")
    H.ok(b.emoteMenu:IsShown()); H.eq(#intents,0)
    b.emoteButtons[3]:Click()
    H.eq(intents[1].kind,"EMOTE"); H.eq(intents[1].index,3)
    H.notOk(b.emoteMenu:IsShown())
    b:ShowSpeech("foe","Greetings")
    H.ok(b.speech.foe:IsShown())
    b.speech.foe:GetScript("OnUpdate")(b.speech.foe,4)
    H.notOk(b.speech.foe:IsShown())
  end)
end)

H.suite("ui: fatigue announces the empty deck once and keeps the damage hit",function(ns,H)
  withBoard(ns,function(b)
    local g=H.NewGame()
    local c=ns.Controller.New({game=g,player=1})
    b:SetSnapshot(c:Snapshot())
    g.players[1].deck={}
    g:Draw(1)
    b:SetSnapshot(c:Snapshot())
    H.eq(g.players[1].hero:Health(),29)
    H.ok(b.speech.self.text:GetText():find("Fatigue"))
    local hits=#b.hitLabels
    H.ok(hits>0)
    b.speech.self:Hide()
    b:SetSnapshot(c:Snapshot()); b.frame:SetSize(1000,640)
    H.notOk(b.speech.self:IsShown(),"redraw cannot replay fatigue")
    H.eq(#b.hitLabels,hits)
  end)
end)

H.suite("ui: hero health survives repeated compact and wide resizes",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {hero={health=30,armor=12},foeHero={health=9,armor=0}}))
    for _,size in ipairs({{800,600},{1920,1080},{800,600}}) do
      b.frame:SetSize(size[1],size[2])
      for _,hero in ipairs({b.hero,b.foeHero}) do
        H.ok(hero.health.w>=44); H.ok(hero.health.h>=28)
        H.ok(hero.health.font[2]>=16); H.ok(hero.health:GetText()~="")
      end
    end
  end)
end)

H.suite("ui: card art covers its window without padding bands or stretching", function(ns, H)
  local W = ns.Widgets
  if not W or not W.ArtCoords then return end
  local crop = ns.HearthstoneArtCrop or {}
  H.ok(crop.EX1_058, "a padded card is measured")
  for _, id in ipairs({ "EX1_058", "CS2_121", "CS2_029", "EX1_116" }) do
    for _, size in ipairs({ { 56, 92 }, { 70, 37 }, { 142, 170 }, { 119, 22 } }) do
      local u0, u1, v0, v1 = W.ArtCoords(id, size[1], size[2])
      local c = crop[id] or { 0, 1, 0, 1 }
      H.ok(u0 >= c[1] - 1e-9 and u1 <= c[2] + 1e-9 and v0 >= c[3] - 1e-9 and v1 <= c[4] + 1e-9,
           id .. " never shows its padding")
      local shown = (u1 - u0) / (v1 - v0)
      H.ok(math.abs(shown - size[1] / size[2]) / (size[1] / size[2]) < 0.02, id .. " is not stretched")
    end
  end
end)

H.suite("ui: emotes open as a wheel around your portrait and use voiced WoW emotes", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}))
    b:ToggleEmotes()
    local hr = b.L.hero
    local cx = hr.x + hr.w / 2
    local left, right = 0, 0
    for i, button in ipairs(b.emoteButtons) do
      local _, _, _, x = button:GetPoint(1)
      if x < cx then left = left + 1 else right = right + 1 end
      for j = i + 1, #b.emoteButtons do
        local _, _, _, x2, y2 = b.emoteButtons[j]:GetPoint(1)
        local _, _, _, x1, y1 = button:GetPoint(1)
        H.ok(math.abs(x1 - x2) >= button:GetWidth() or math.abs(y1 - y2) >= button:GetHeight(), "plaques do not overlap")
      end
    end
    H.eq(left, 3, "three plaques down the left of the portrait"); H.eq(right, 3, "and three down the right")
    b.emoteMenu:Click(); H.notOk(b.emoteMenu:IsShown(), "clicking away closes the wheel")
    H.eq(table.concat(ns.Board.WOW_EMOTES, ","), "THANK,CONGRATULATE,HELLO,TRAIN,SPIT,ROAR")
    H.eq(ns.Board.EMOTE_VOICE, nil, "no Hearthstone voice line doubles the character's")
  end)
end)


H.suite("ui: a dead hero cracks, shatters and only then shows the result", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    local function played(fragment)
      local n = 0
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find(fragment, 1, true) then n = n + 1 end end
      return n
    end
    local over = snapshot({}, {}, {}, {myTurn=true, over=true, winner=1, player=1})
    over.foeHero = { cardId = "HERO_08", health = 0 }
    b:SetSnapshot(over)
    Stub.Advance(0.3)
    H.ok(b.cracks and b.cracks.foe:IsShown(), "their portrait cracks first")
    H.ok(b.foeHero.frame:GetAlpha() > 0, "and is still there while it cracks")
    H.eq(b.result:GetAlpha(), 0, "the result waits for the explosion")
    H.eq(played("Pegasus_Stinger_Alliance"), 0)
    Stub.Advance(0.8)
    H.eq(b.foeHero.frame:GetAlpha(), 0, "then it bursts")
    H.ok(#b.shards > 0, "into pieces of itself")
    H.ok(played("GlassShatter") >= 1 and played("bigattack") >= 1, "with Hearthstone's shatter and boom")
    Stub.Advance(0.6)
    H.ok(b.result:GetAlpha() > 0.5, "Victory appears")
    H.eq(played("Pegasus_Stinger_Alliance"), 1)
    Stub.Advance(1.5)
    H.eq(#b.shards, 0, "the pieces are gone")
    b:ResetMatch()
    H.eq(b.foeHero.frame:GetAlpha(), 1, "and the next match has a whole hero")
  end)
end)

H.suite("ui: the rope's fuse is one continuous hiss, and stops with the turn", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    local function fuses()
      local n = 0
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find("rope-burn.wav", 1, true) then n = n + 1 end end
      return n
    end
    local stage = b:Stage()
    stage:Sound("rope_start")
    H.eq(fuses(), 1, "the fuse lights with the rope")
    Stub.Advance(12)
    H.eq(fuses(), 1, "and burns on, without being struck again")
    -- the turn clock stands still: so does the hiss, and it resumes after
    local stops = Stub.Count("StopSound")
    b.ropeHalted = true; Stub.Advance(0.1)
    H.ok(Stub.Count("StopSound") > stops, "a halted clock silences the fuse")
    b.ropeHalted = false; Stub.Advance(0.1)
    H.eq(fuses(), 2, "and it lights again when the clock moves")
    stops = Stub.Count("StopSound")
    b:ClearRope()
    H.ok(Stub.Count("StopSound") > stops, "ending the turn puts it out")
    Stub.Advance(9)
    H.eq(fuses(), 2, "and it stays out")
    local ends = #Stub.R.sounds
    stage:Sound("rope_end")
    H.eq(#Stub.R.sounds, ends, "a stale rope's burn-out makes no sound")
    ns.Sounds.SetMuted(true); stage:Sound("rope_start"); H.eq(fuses(), 2, "muted is muted")
    ns.Sounds.SetMuted(false)
  end)
end)

H.suite("ui: a rope fuse WoW dropped (alt-tabbed) relights on its own", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    local function fuses()
      local n = 0
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find("rope-burn.wav", 1, true) then n = n + 1 end end
      return n
    end
    local playing = true
    local saved = rawget(Stub.env, "C_Sound")
    Stub.env.C_Sound = { IsPlaying = function() return playing end }
    b:Stage():Sound("rope_start")
    Stub.Advance(3)
    H.eq(fuses(), 1, "a fuse still burning is left alone")
    playing = false
    Stub.Advance(0.3)
    H.eq(fuses(), 2, "one that went out is lit again")
    Stub.Advance(0.1)
    H.eq(fuses(), 2, "not every frame: it retries twice a second")
    playing = true
    Stub.Advance(3)
    H.eq(fuses(), 2, "and stops once it burns")
    Stub.env.C_Sound = saved
    b:ClearRope()
  end)
end)

H.suite("ui: the rope keeps hissing while your own play animates", function(ns, H)
  --[[ THE REPORT: "the rope sound stops when you play a unit". The turn clock
       stands still while your presentation plays (LOCKED_ALLOWANCE); only a
       real pause may silence the fuse. ]]
  local Main = ns.Main
  local board = { ropeHalted = nil }
  local saved = Main.board
  Main.board = board
  Main:TickRope(0, false)
  H.eq(board.ropeHalted, false, "a clock held by an animation is not a halt")
  Main:TickRope(0, true)
  H.eq(board.ropeHalted, true, "a paused game is")
  Main.board = saved
end)

H.suite("ui: leaving the table mid-rope silences the rope; coming back relights it", function(ns, H)
  --[[ THE REPORT: "going to the main menu when in a duel, audio of rope keeps
       going". The hiss is paused and relit by TickFX, which never runs while
       the board is hidden, so nothing ever put it out. ]]
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, { myTurn = true }))
    b.frame:Show()
    local function fuses()
      local n = 0
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find("rope-burn.wav", 1, true) then n = n + 1 end end
      return n
    end
    local stage = b:Stage()
    stage:Sound("rope_start")
    H.eq(fuses(), 1, "the rope is burning")
    local stops = Stub.Count("StopSound")
    b.frame:Hide()                                   -- Main Menu
    H.ok(Stub.Count("StopSound") > stops, "going to the menu puts the hiss out")
    Stub.Advance(3)
    H.eq(fuses(), 1, "and it stays out while you are away")
    local before = #Stub.R.sounds
    stage:Sound("rope_end")
    H.eq(#Stub.R.sounds, before, "the rope running out is not heard from the menu either")
    stage:Sound("rope_start")                        -- a new rope, lit while you are away
    H.eq(#Stub.R.sounds, before, "a rope lit while you are away is silent")
    b.frame:Show(); Stub.Advance(0.1)
    H.eq(fuses(), 2, "back at the table, the rope that is burning is heard again")
  end)
end)

H.suite("ui: the music button turns only the music off and on, on every screen", function(ns, H)
  withBoard(ns, function(b)
    _G.ForeverHearthstoneDB = _G.ForeverHearthstoneDB or {}
    ForeverHearthstoneDB.music = nil
    local music, speaker = b.corner.music, b.corner.speaker
    H.ok(music and music:IsShown(), "the board has a music button")
    local _, rel, relPoint = music:GetPoint(1)
    H.eq(rel, speaker, "beside the speaker"); H.eq(relPoint, "LEFT", "on its left")
    H.ok(music.icon:GetTexture():find("music-on.tga", 1, true), "showing the notes while music plays")
    H.eq(music.bg:GetTexture(), speaker.bg:GetTexture(), "in the speaker's gilded round")
    local other = ns.Widgets.MusicButton(UIParent)           -- another screen's
    music:Click()
    H.eq(ForeverHearthstoneDB.music, false, "clicking turns the music off")
    H.notOk(ns.Sounds.Muted(), "and only the music: effects are not muted")
    H.ok(music.icon:GetTexture():find("music-off.tga", 1, true), "its icon crosses out")
    H.ok(other.icon:GetTexture():find("music-off.tga", 1, true), "and so does every other screen's")
    music:Click()
    H.ok(ForeverHearthstoneDB.music ~= false, "clicking again turns it back on")
    H.ok(other.icon:GetTexture():find("music-on.tga", 1, true), "everywhere")
  end)
end)

H.suite("ui: the arrow locks a crosshair onto a legal target and colours by side", function(ns, H)
  withBoard(ns, function(board)
    local function aim(extra)
      board:SetSnapshot(snapshot({ "CS2_029" }, { "CS2_182" }, { "CS2_172" }, extra))
    end
    local stats = { boardStats = { { instanceId = 11 } }, foeBoardStats = { { instanceId = 21 } },
                    heroId = 1, foeHeroId = 2 }
    local function with(t) local e = {}; for k, v in pairs(stats) do e[k] = v end; for k, v in pairs(t) do e[k] = v end; return e end
    aim(with({ targeting = { handIndex = 1, legal = { 21, 2 } } }))
    aimCursorAt(board, board.L.foeBoardSlots[1])
    board:UpdateArrow()
    H.ok(board.arrow.ring:IsShown(), "a legal enemy gets the crosshair")
    local r = board.arrow.head.colour
    H.ok(r[1] > r[2], "and the arrow burns red")
    aimCursorAt(board, board.L.boardSlots[1])
    board:UpdateArrow()
    H.notOk(board.arrow.ring:IsShown(), "an illegal target does not")
    aim(with({ targeting = { handIndex = 1, legal = { 11 } } }))
    aimCursorAt(board, board.L.boardSlots[1])
    board:UpdateArrow()
    local g = board.arrow.head.colour
    H.ok(board.arrow.ring:IsShown() and g[2] > g[1], "a friendly target turns it green")
    aim(with({ selectedIndex = 1, combatPreview = { [21] = {} } }))
    aimCursorAt(board, board.L.foeBoardSlots[1])
    board:UpdateArrow()
    H.ok(board.arrow.ring:IsShown(), "attacks lock on to legal defenders too")
    local shown = 0
    for _, t in ipairs(board.arrow.dots) do if t:IsShown() then shown = shown + 1 end end
    H.ok(shown >= 3, "the body is a chain of chevrons")
  end)
end)

H.suite("ui: spells draw their own Hearthstone-style effects", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, { "CS2_182", "CS2_182" }, { "CS2_172", "CS2_172", "CS2_172" }))
    local function cast(cardId, extra)
      b:ClearSprites()
      local o = { cardId = cardId, mine = true }
      for k, v in pairs(extra or {}) do o[k] = v end
      b:SpellEffect(o)
      return b.sprites
    end
    local s = cast("CS2_029", { targeted = true, targetSide = "foe", targetIndex = 2 })
    H.eq(#s, 1, "Fireball is one flaming bolt"); H.eq(s[1].school, "fire"); H.ok(s[1].trail)
    local r = b.L.foeBoardSlots[2]
    H.eq(s[1].x1, r.x + r.w / 2, "that flies at its target")
    H.eq(s[1].x0, b.L.hero.x + b.L.hero.w / 2, "from my hero's portrait")
    H.eq(s[1].y0, b.L.hero.y + b.L.hero.h / 2)
    -- even while the played card is still in the air, as it is when the
    -- choreography fires the effect
    b.flying, b.flyingCard = true, { rect = { x = 5, y = 5, w = 50, h = 70 } }
    local f = cast("CS2_029", { targeted = true, targetSide = "foe", targetIndex = 2 })[1]
    H.eq(f.x0, b.L.hero.x + b.L.hero.w / 2, "not from the card being played")
    b.flying, b.flyingCard = nil, nil
    local foe = cast("CS2_029", { mine = false, targeted = true, targetSide = "self", targetIsHero = true })[1]
    H.eq(foe.x0, b.L.foeHero.x + b.L.foeHero.w / 2, "the opponent's spells leave the opponent's hero")
    H.eq(#cast("EX1_277"), 3, "Arcane Missiles fires three")
    local falling = 0
    for _, sp in ipairs(cast("CS2_032")) do if sp.y0 > sp.y1 then falling = falling + 1 end end
    H.eq(falling, 3, "Flamestrike rains down on each of their minions")
    local nova = cast("CS1_112")
    H.ok(nova[1].s1 > b.frame:GetWidth(), "Holy Nova rings out across the board")
    H.eq(cast("CS2_089", { targeted = true, targetSide = "self", targetIsHero = true })[1].school, "holy",
         "Holy Light blooms")
    Stub.Advance(2)
    H.eq(#b.sprites, 0, "every effect finishes and returns to the pool")
    -- Every collectible spell resolves to a drawable effect.
    local kinds = { bolt = 1, missiles = 1, beam = 1, fan = 1, slash = 1, drain = 1, sweep = 1, rain = 1,
                    nova = 1, bloom = 1, glow = 1, swirl = 1, shield = 1, secret = 1, summon = 1 }
    for id, p in pairs(ns.PrintedCards) do
      if p.collectible and p.type == "SPELL" then
        for _, targeted in ipairs({ true, false }) do
          local fx = ns.SpellFX.For(id, targeted)
          H.ok(kinds[fx.kind] and ns.Widgets.BURST_COLOR[fx.school], id .. " has an effect")
        end
      end
    end
  end)
end)

H.suite("ui: spell effects pass -- every spell its own motion", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, { "CS2_182", "CS2_182" }, { "CS2_172", "CS2_172", "CS2_172" }))
    local function cast(cardId, extra)
      b:ClearSprites()
      local o = { cardId = cardId, mine = true }
      for k, v in pairs(extra or {}) do o[k] = v end
      b:SpellEffect(o)
      return b.sprites
    end
    local function count(list, pred) local n = 0; for _, x in ipairs(list) do if pred(x) then n = n + 1 end end; return n end
    local foe2 = { targeted = true, targetSide = "foe", targetIndex = 2 }

    -- Every collectible spell is mapped by hand, not left to inference --
    -- except Secrets, which all look alike but for their class's colour.
    for id, p in pairs(ns.PrintedCards) do
      if p.collectible and p.type == "SPELL" then
        H.ok(ns.SpellFX.CARDS[id] or ns.SpellFX.For(id, false).kind == "secret", p.name .. " is mapped by hand")
      end
    end

    local bolt = cast("EX1_238", foe2)
    local streaks = count(bolt, function(o) return o.shape == "streak" end)
    H.ok(streaks >= 10, "Lightning Bolt is a crackling chain of streaks, drawn twice")
    local halos = count(bolt, function(o) return o.alpha and o.alpha < 1 end)
    H.ok(halos >= 5, "over a soft halo of lit air")
    H.eq(count(bolt, function(o) return o.flicker end), streaks - halos, "and the bolt itself strobes")
    H.ok(count(bolt, function(o) return o.rot and o.rot ~= 0 end) > 0, "each segment turned along the arc")
    local forked = cast("EX1_251")
    H.ok(count(forked, function(o) return o.shape == "streak" end) >= 2 * streaks,
         "Forked Lightning forks to a second enemy")

    local fan = cast("EX1_129")
    H.eq(count(fan, function(o) return o.shape == "streak" and o.orient end), 3,
         "Fan of Knives throws one blade at each of their three minions, pointed along its flight")

    local slash = cast("EX1_124", foe2)
    local strokes = {}
    for _, o in ipairs(slash) do if o.shape == "streak" and o.onArrive then strokes[#strokes + 1] = o end end
    H.eq(#strokes, 2, "Eviscerate is two strokes")
    H.ok(strokes[1].rot == -strokes[2].rot, "which cross")
    H.eq(count(slash, function(o) return o.shape == "streak" end), 4, "each leaving its cut behind")

    -- Drawn above the hero portraits, not hidden behind the face they hit.
    local sprite = cast("CS2_029", { targeted = true, targetSide = "foe", targetIsHero = true })[1]
    local layer = sprite.tex.parent
    H.ok(layer:GetFrameLevel() > b.foeHero.frame:GetFrameLevel(), "a Fireball to the face flies over the portrait")
    H.eq(b.particles.parent, layer, "and so do its sparks")

    local drain = cast("CS2_061", foe2)
    H.eq(#drain, 1, "Drain Life flies out first")
    Stub.Advance(0.3)
    H.ok(count(b.sprites, function(o) return o.shape == "spark" and o.x1 == b.L.hero.x + b.L.hero.w / 2 end) >= 6,
         "then its life flows back to your hero")

    local poly = cast("CS2_022", foe2)
    H.eq(count(poly, function(o) return o.spin end), 8, "Polymorph: motes spin in on the target")
    local shield = cast("CS2_004", { targeted = true, targetSide = "self", targetIndex = 1 })
    H.ok(count(shield, function(o) return o.shape == "ring" end) >= 2, "Power Word: Shield closes a ring on it")
    local secret = cast("EX1_287")
    H.eq(secret[1].shape, "ring"); H.eq(secret[1].school, "arcane", "a Mage secret sets in purple")
    H.eq(cast("EX1_610")[1].school, "nature", "a Hunter's in green")
    H.eq(cast("EX1_130")[1].school, "holy", "a Paladin's in gold")
    H.eq(count(cast("CS2_011"), function(o) return o.shape == nil end), 2,
         "Savage Roar settles on each of your minions")
    H.eq(count(cast("EX1_571"), function(o) return o.shape == "ring" end), 3,
         "Force of Nature: a flash for each Treant")

    -- A heavy spell shakes the table when it LANDS, not when it is cast.
    b:ClearSprites(); b.shake.amount = 0
    cast("EX1_279", foe2)
    H.eq(b.shake.amount, 0, "Pyroblast has not landed yet")
    Stub.Advance(0.34)
    H.ok(b.shake.amount >= ns.SpellFX.Impact({ big = true }).shake, "it lands, and the board shakes")
    H.ok(count(b.sprites, function(o) return o.shape == "ring" end) >= 1, "with a shockwave ring")
    b:ClearSprites(); Stub.Advance(1); b.shake.amount = 0
    cast("CS2_024", foe2); Stub.Advance(0.4)
    H.eq(b.shake.amount, 0, "a Frostbolt does not")

    -- Drawing a spell, its trail and its sparks never touches math.random.
    local real, calls = math.random, 0
    math.random = function(...) calls = calls + 1; return real(...) end
    for _, id in ipairs({ "EX1_277", "EX1_238", "EX1_129", "CS2_032", "CS2_061", "CS2_022", "EX1_279" }) do
      cast(id, foe2); Stub.Advance(0.1); Stub.Advance(0.3); Stub.Advance(0.6)
    end
    math.random = real
    H.eq(calls, 0, "spell visuals leave the match's random stream alone")
    Stub.Advance(3)
    H.eq(#b.sprites, 0, "and every sprite returns to the pool")
  end)
end)

H.suite("ui: each school's sparks move like their element", function(ns, H)
  Stub.Install(_G)
  assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone", ns)
  local W = ns.Widgets
  local parent = CreateFrame("Frame")
  local function after(kind, t)
    local p = W.NewParticles(parent)
    W.Burst(p, kind, 0, 0, 1, function() return 0.25 end)  -- straight up-ish: angle pi/2
    local q = p.live[1]
    local y0 = q.vy
    W.TickParticles(p, t)
    return q, y0
  end
  local fire = after("fire", 0.3); local frost = after("frost", 0.3)
  H.ok(fire.vy > frost.vy, "fire embers rise where frost falls")
  local smoke = after("shadow", 0.5)
  H.ok(smoke.tex:GetWidth() > smoke.size, "shadow smoke swells as it fades")
  H.ok(after("holy", 0.01).tex.texture:find("fx-spark", 1, true), "holy glints are sparkles")
  -- a soft mote, never the hollow minion outline that read as gold rings (docs/39)
  H.ok(after("impact", 0.01).tex.texture:find("fx-orb", 1, true), "an ordinary impact is a soft mote")
end)

H.suite("ui: a trigger plays its Hearthstone recording and pulses the minion", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, { "EX1_298", "NEW1_019" }, {}))
    local function played(fragment)
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find(fragment, 1, true) then return true end end
    end
    local tl = ns.Choreography.MinionTrigger(b:Stage(), { cardId = "EX1_298", side = "self", index = 1, at = 0 })
    tl:Start(); tl:Tick(0.16)
    H.ok(played("VO_EX1_298_Trigger"), "Ragnaros's trigger line")
    H.ok(b.myMinions[1].glow:IsShown(), "and he glows as he fires")
    tl:Tick(0.3)
    local before = #Stub.R.sounds
    local tl2 = ns.Choreography.MinionTrigger(b:Stage(), { cardId = "NEW1_019", side = "self", index = 2, at = 0 })
    tl2:Start(); tl2:Tick(0.05)
    H.eq(#Stub.R.sounds, before, "no recording, no invented sound")
  end)
end)

H.suite("ui: the mulligan hand is DEALT, card by card, with the draw sound", function(ns, H)
  withBoard(ns, function(b)
    local function whooshes()
      local n = 0
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find("draw.wav", 1, true) then n = n + 1 end end
      return n
    end
    local before = whooshes()
    b:SetSnapshot(snapshot({}, {}, {}, {
      mulligan = { hand = { "CS2_182", "CS2_029", "CS2_231" }, marked = {}, waiting = false } }))
    local cards = b.mulliganPool.used
    H.eq(#cards, 3)
    H.notOk(cards[3].frame:IsShown(), "the last card has not been dealt yet")
    Stub.Advance(0.3)
    H.ok(cards[1].frame:IsShown(), "the first is on its way")
    Stub.Advance(1.5)
    for i, w in ipairs(cards) do
      H.ok(w.frame:IsShown() and not w.faceDown, "card " .. i .. " has landed face up")
      H.eq(w.rect.x, w.mulliganRest.x, "in its slot")
    end
    H.eq(whooshes() - before, 3, "each card was heard as it was dealt")
    -- a replacement is dealt too
    b:SetSnapshot(snapshot({}, {}, {}, {
      mulligan = { hand = { "CS2_182", "EX1_016", "CS2_231" }, marked = {}, waiting = true } }))
    Stub.Advance(1.5)
    H.eq(whooshes() - before, 4, "only the replaced card is dealt again")
  end)
end)

H.suite("ui: clicking the empty sand raises a dust puff, never on the scenery", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true}))
    local fr = b.L.field
    H.ok(b:ClickSurface(fr.x + fr.w / 2, fr.y + fr.h / 2), "the middle of the board puffs")
    H.ok(b.puffs[1].tex:IsShown())
    H.notOk(b:ClickSurface(4, 4), "the corner scenery does not")
    for _ = 1, 30 do b:ClickSurface(fr.x + 20, fr.y + 20) end
    H.ok(#b.puffs <= ns.Board.MAX_PUFFS, "spam-clicking reuses a capped pool")
    Stub.Advance(1)
    for _, p in ipairs(b.puffs) do H.notOk(p.tex:IsShown(), "and every puff fades") end
  end)
end)

H.suite("ui: an overdrawn card is shown, then burns", function(ns, H)
  withBoard(ns, function(b)
    local g = H.NewGame()
    H.SetActive(g, 1)
    while #g.players[1].hand < 10 do H.Hand(g, 1, "CS2_231") end
    local c = ns.Controller.New({ game = g, player = 1 })
    b:SetSnapshot(c:Snapshot())
    H.PutOnDeck(g, 1, "CS2_029")
    g:Draw(1)
    local snap = c:Snapshot()
    H.eq(#snap.burnEvents, 1, "the controller reports the burn")
    H.eq(snap.burnEvents[1].cardId, "CS2_029", "with the card that burned")
    b:SetSnapshot(snap)
    H.eq(#b.burns, 1, "the board shows it")
    Stub.Advance(0.8)
    local w = b.burns[1] and b.burns[1].w
    H.ok(w and w.frame:IsShown() and not w.faceDown, "face up, readable")
    local burnt = 0
    Stub.Advance(2.5)
    for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find("Fire_Underlay", 1, true) then burnt = burnt + 1 end end
    H.eq(burnt, 1, "it catches fire")
    H.eq(#b.burns, 0, "and is gone")
    H.notOk(w.frame:IsShown())
  end)
end)

H.suite("ui: a minion bounced into a full hand burns where both players see it", function(ns, H)
  withBoard(ns, function(b)
    local g = H.NewGame()
    H.SetActive(g, 1)
    H.Mana(g, 1, 10)
    while #g.players[2].hand < 10 do H.Hand(g, 2, "CS2_231") end
    H.Put(g, 2, "CS2_182"); H.Put(g, 2, "CS2_179")
    H.Put(g, 1, "CS2_029")
    local i = #g.players[1].hand + 1
    H.Hand(g, 1, "NEW1_004")                       -- Vanish
    local c = ns.Controller.New({ game = g, player = 1 })
    b:SetSnapshot(c:Snapshot())
    H.ok(c:HandleIntent({ kind = "PLAY_CARD", handIndex = i }), "Vanish is cast")
    local snap = c:Snapshot()
    local foe = 0
    for _, e in ipairs(snap.burnEvents) do if not e.mine then foe = foe + 1 end end
    H.eq(foe, 2, "both of their minions burn")
    local stood = {}
    for _, w in ipairs(b.foeMinions) do stood[#stood + 1] = w.rect end
    b:SetSnapshot(snap)
    local shown = 0
    for _, burn in ipairs(b.burns or {}) do
      if not burn.mine then
        shown = shown + 1
        H.eq(burn.from.x, stood[shown].x, "lifting off from the slot it stood in")
        H.ok(burn.w.frame:IsShown() and not burn.w.faceDown, "face up at once, no gap on the board")
      end
    end
    H.eq(shown, 2, "and the board shows both")
    Stub.Advance(4)
    H.eq(#b.burns, 0, "then they are gone")
  end)
end)

H.suite("ui: the opponent's held card and aim are shown, mirrored onto our side", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182"}, {"CS2_179"}, {myTurn=false, foeHandCount=4}))
    local restY = b.foeHandPool.used[2].rect.y
    b:SetOpponentHover(2, "b1", "E")
    H.ok(b.foeHandPool.used[2].rect.y < restY, "the card they hold up drops toward the table")
    H.ok(b.foeArrow.frame:IsShown(), "their arrow is drawn")
    b:SetOpponentHover(0, "", "")
    H.notOk(b.foeArrow.frame:IsShown(), "and put away when they stop aiming")
    --[[ A battlecry being placed: the arrow leaves the slot their minion
         will stand in, which is past the end of their board as it is now. ]]
    b:SetOpponentHover(0, "s2", "e1")
    H.ok(b.foeArrow.frame:IsShown(), "a placed battlecry's arrow is drawn")
    local from = b:OpponentRect("s2")
    H.ok(from and from.x > b.L.foeBoardSlots[1].x, "from right of their Sen'jin")
    H.eq(b:OpponentRect("s"), nil, "a slot code without a slot is nothing")
    b:SetOpponentHover(1, "H", "e1")
    Stub.Advance(3.5)
    H.notOk(b.foeArrow.frame:IsShown(), "a stale hover clears itself")
    local sent
    b.opts.onHover = function(...) sent = { ... } end
    b:SetSnapshot(snapshot({"CS2_182","CS2_029"}, {"CS2_182"}, {"CS2_179"}, {myTurn=true}))
    b:SetHover(2)
    H.eq(sent and sent[1], 2, "our own lifted card is reported for the opponent")
  end)
end)

H.suite("ui: heroes speak for the rope, their death and a long think", function(ns, H)
  withBoard(ns, function(b)
    local function said(fragment)
      local n = 0
      for _, snd in ipairs(Stub.R.sounds) do if snd.file and snd.file:find(fragment, 1, true) then n = n + 1 end end
      return n
    end
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=true, hero={cardId="HERO_08",health=30},
      foeHero={cardId="HERO_01",health=30}}))
    b:StartRopeAudio()
    H.eq(said("VO_HERO_08_Time_66"), 1, "your hero's Out of Time line lights the rope")
    b:StopRopeAudio()
    b:SetSnapshot(snapshot({}, {}, {}, {myTurn=false, turn=4, eventSeq=9,
      hero={cardId="HERO_08",health=30}, foeHero={cardId="HERO_01",health=30}}))
    Stub.Advance(ns.Board.THINK_AFTER + 1)
    H.eq(said("VO_HERO_01_Thinking"), 1, "a long enemy turn gets one Thinking line")
    Stub.Advance(ns.Board.THINK_AFTER + 1)
    H.eq(said("VO_HERO_01_Thinking"), 1, "only one per turn")
    b:SetSnapshot(snapshot({}, {}, {}, {over=true, winner=1, player=1,
      hero={cardId="HERO_08",health=30}, foeHero={cardId="HERO_01",health=0}}))
    H.eq(said("VO_HERO_01_Death_17"), 1, "the losing hero's last words")
  end)
end)

H.suite("sound: classic minions HearthSFX lacks land with their own play line", function(ns, H)
  withBoard(ns, function()
    local before = #Stub.R.sounds
    ns.Sounds.PlayCard("summon", "EX1_116")   -- Leeroy Jenkins
    local files = {}
    for i = before + 1, #Stub.R.sounds do files[#files + 1] = Stub.R.sounds[i].file or "" end
    local joined = table.concat(files, "|")
    H.ok(joined:find("rymedy_leeroy_jenkins_play.mp3", 1, true), "his line")
    H.ok(joined:find("rymedy_leeroy_jenkins_music_play.mp3", 1, true), "and his music")
  end)
end)

H.suite("ui: End Turn is the whole gold button, and never turns green", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({ "CS2_029" }, {}, {}, { myTurn = false, playable = { false } }))
    H.eq(b.endTurnState, "grey", "the opponent's turn is dimmed")
    H.ok(not b.endTurn.mouseEnabled, "and cannot be pressed")
    -- turn one: nothing playable
    b:SetSnapshot(snapshot({ "CS2_029" }, {}, {}, { myTurn = true, playable = { false } }))
    Stub.Advance(5)
    H.eq(b.endTurnState, "yellow", "yellow on your turn even with nothing to play")
    H.ok(b.endTurn.mouseEnabled, "and live")
    local e = b.L.endTurn
    H.ok(b.endTurn:GetWidth() > e.w and b.endTurn:GetHeight() > e.h,
         "the button covers the painted socket, and all of it is the click target")
  end)
end)

H.suite("ui: hovering the speaker offers a volume slider", function(ns, H)
  withBoard(ns, function(b)
    Stub.cvars.Sound_SFXVolume = "0.5"
    H.ok(not b.volume:IsShown(), "folded away until wanted")
    b.mute.mouseOver = true
    b.mute:GetScript("OnEnter")(b.mute)
    H.ok(b.volume:IsShown(), "opens on hover")
    H.eq(b.volume.label:GetText(), "50%", "shows WoW's current effects volume")
    -- click three-quarters of the way up the trough
    local t = b.volume.trough
    t.bottom = 100
    Stub.cursor = { x = 0, y = (100 + 0.75 * t:GetHeight()) * t:GetEffectiveScale() }
    t:GetScript("OnMouseDown")(t); t:GetScript("OnMouseUp")(t)
    H.eq(Stub.cvars.Sound_SFXVolume, "0.75", "sets the Sound Effects channel")
    H.eq(Stub.cvars.Sound_MusicVolume, "0.75", "and the Music channel, which the theme plays on")
    -- the grab area is the whole panel width, not the 8px trough
    H.ok(b.volume.hit and b.volume.hit:GetScript("OnMouseDown"), "the whole panel is grabbable")
    H.eq(b.volume.label:GetText(), "75%", "and says so")
    b.volume:GetScript("OnMouseWheel")(b.volume, -1)
    H.eq(Stub.cvars.Sound_SFXVolume, "0.70", "the wheel nudges it by 5%")
    -- raising the volume while muted unmutes
    ns.Sounds.SetMuted(true); b:RefreshMute()
    b.volume:GetScript("OnMouseWheel")(b.volume, 1)
    H.ok(not ns.Sounds.Muted(), "turning it up unmutes")
    -- it folds away once the pointer has left both
    b.mute.mouseOver = false
    Stub.Advance(0.6)
    H.ok(not b.volume:IsShown(), "folds away after the pointer leaves")
  end)
end)

H.suite("ui: a size WoW restored from its layout cache never survives a show", function(ns, H)
  withBoard(ns, function(board)
    local W = ns.Widgets
    W.ForgetRect()
    local f = CreateFrame("Frame", "ForeverHearthstoneCollectionTest", UIParent)
    f:SetSize(1180, 700)
    W.ResizeGrip(f, 760, 560)
    f:Hide()
    -- what an older version's cached layout did on /reload: a huge window,
    -- anchored somewhere else
    f:SetSize(2400, 1400); f:ClearAllPoints(); f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 300, -50)
    f:Show()
    -- the default scales to the screen (docs/39): 16:9-ish, never below the built size
    local dw, dh = W.DefaultSize({ w = 1180, h = 700 })
    H.ok(dw >= 1180 and dh >= 700 and dw <= UIParent:GetWidth(), "a default that fits the screen")
    H.eq(f:GetWidth(), dw, "opened at its own default width")
    H.eq(f:GetHeight(), dh, "and height")
    H.eq((f:GetPoint(1)), "CENTER", "centred, not where the cache put it")
    -- once the player sizes something, that rect wins
    f.left, f.bottom = 50, 50; f:SetSize(900, 600)
    W.RememberRect(f)
    f:Hide(); f:Show()
    H.eq(f:GetWidth(), 900, "the player's own size is kept for the session")
    W.ForgetRect()
  end)
end)

H.suite("ui: a card's recording keeps playing when the next card is played", function(ns, H)
  withBoard(ns, function(b)
    local cardId
    for id, entry in pairs(ns.CardSounds or {}) do if entry.summon then cardId = id; break end end
    H.ok(cardId, "some card has its own play recording")
    local stopped = Stub.Count("StopSound")
    ns.Sounds.PlayCard("summon", cardId)
    ns.Sounds.PlayCard("summon", cardId)
    ns.Sounds.PlayCard("attack", cardId)
    H.eq(Stub.Count("StopSound"), stopped, "nothing is cut short by the next card")
    local src = io.open("ForeverHearthstone/Client/Main.lua"):read("*a")
    -- muting may silence what is playing; nothing else in Main may
    local s, e = src:find("function Main:ToggleMute%(%).-\nend")
    H.ok(s, "found ToggleMute")
    local rest = src:sub(1, s - 1) .. src:sub(e + 1)
    H.notOk(rest:find("CutCardAudio", 1, true), "the bot does not cut the last clip")
    ns.Sounds.CutCardAudio(180)
    H.ok(Stub.Count("StopSound") > stopped, "the lingering clip is faded out")
    local again = Stub.Count("StopSound")
    ns.Sounds.CutCardAudio(180)
    H.eq(Stub.Count("StopSound"), again, "and only once")
  end)
end)

H.suite("ui: card text is as Hearthstone shows it -- no client markup but <b>", function(ns, H)
  --[[ The source text carries the client's own markup: <b>/<i>, [x], and "$" /
       "#" before a number spell damage or healing may change ("Restore #4
       Health"). None of it is ever displayed; tools/import_cards.py drops it. ]]
  local bad = {}
  for id, p in pairs(ns.PrintedCards) do
    local t = p.text or ""
    local other = t:gsub("</?b>", "")
    if t:find("[%$#]%d") or other:find("<[^>]+>") or t:find("[x]", 1, true) then bad[#bad + 1] = id end
  end
  H.eq(#bad, 0, "printed text with markup other than <b>: " .. table.concat(bad, ", "))
  withBoard(ns, function(board)
    local w = ns.Widgets.New(board.frame)
    ns.Widgets.SetDescriptor(w, board.resolver:Card("CS2_007"))
    H.eq(w.body:GetText(), "Restore 8 Health.", "Healing Touch reads as it does in Hearthstone")
  end)
end)

H.suite("ui: keywords are bold on the card face, as in Hearthstone", function(ns, H)
  withBoard(ns, function(board)
    local w = ns.Widgets.New(board.frame)
    w.liveText = true   -- the live labels: the fallback for a card with no baked text
    ns.Widgets.SetDescriptor(w, board.resolver:Card("DS1_070"))   -- Houndmaster
    ns.Widgets.ApplyRect(w, { x = 0, y = 0, w = 240, h = 343 })
    local runs = w.bodyRich:Runs()
    local seen = {}
    for _, fs in ipairs(runs) do
      seen[fs:GetText()] = fs:GetFont()
      H.ok(fs:IsShown(), "every run is drawn")
      -- the body label is hidden by alpha; the runs must not inherit that
      H.eq(select(4, fs:GetTextColor()), 1, "every run is opaque")
      H.eq(fs:GetAlpha(), 1, "and not faded")
    end
    H.eq(seen["Battlecry:"], ns.Fonts.BOLD, "Battlecry: is bold")
    H.eq(seen["Taunt"], ns.Fonts.BOLD, "Taunt is bold")
    H.eq(seen["."], ns.Fonts.BODY, "the full stop after it is not")
    H.eq(seen["Give"], ns.Fonts.BODY, "and neither is the rest of the text")
    H.eq(w.body:GetText(), "Battlecry: Give a friendly Beast +2/+2 and Taunt.", "the plain text is kept for reading")
    -- runs never leave the body's box; they hang from the card frame, at the
    -- box's top-centre, not from the hidden body FontString
    local box, at = w.bodyBox, w.bodyAt
    for _, fs in ipairs(runs) do
      local point, rel, relPoint, x, y = fs:GetPoint(1)
      H.eq(rel, w.frame, "placed from the card's own frame"); H.eq(relPoint, "CENTER")
      H.eq(point, "CENTER", "by its centre, so a lean can turn it")
      x, y = x - fs:GetWidth() / 2, y + fs:GetHeight() / 2          -- its top-left
      x, y = x - (at[1] - box.w / 2), at[2] - y
      H.ok(x >= 0 and x + ns.Widgets.UnboundedWidth(fs) <= box.w + 0.5, "inside the box across")
      H.ok(y + select(2, fs:GetFont()) * 1.2 <= box.h + 0.5, "and down")
      H.ok(fs:GetWidth() >= ns.Widgets.UnboundedWidth(fs), "each run is sized to hold its whole word")
    end
    -- hiding the rules text hides the runs; face down hides them too
    w.body:Hide()
    for _, fs in ipairs(runs) do H.notOk(fs:IsShown(), "hidden with the text") end
    w.body:Show()
    ns.Widgets.SetFaceDown(w, true)
    for _, fs in ipairs(w.bodyRich:Runs()) do H.notOk(fs:IsShown(), "face down shows no text") end
    ns.Widgets.SetFaceDown(w, false)
    for _, fs in ipairs(w.bodyRich:Runs()) do H.ok(fs:IsShown(), "face up again shows it") end
  end)
end)

H.suite("ui: hand-sized cards keep every word of their rules text", function(ns, H)
  --[[ THE REPORT (a screenshot of the hand): "Deal 1 damage to enemy
       minions" (the "all" was gone), "Gain 1 Mana Crystal thi turn only".
       Pooled runs were left to size themselves and the client kept a reused
       one's old width. Every word must be there, each run wide enough for it,
       also when a card is re-dealt shorter text and then longer again. ]]
  withBoard(ns, function(board)
    local w = ns.Widgets.New(board.frame)
    w.liveText = true   -- the live labels: the fallback for a card with no baked text
    local function words(id)
      ns.Widgets.SetDescriptor(w, board.resolver:Card(id))
      ns.Widgets.ApplyRect(w, { x = 0, y = 0, w = 105, h = 150 })   -- a card in hand
      local got = {}
      for _, fs in ipairs(w.bodyRich:Runs()) do
        if fs:IsShown() then
          H.ok(fs:GetWidth() >= ns.Widgets.UnboundedWidth(fs), id .. ": '" .. fs:GetText() .. "' fits its run")
          got[#got + 1] = fs:GetText()
        end
      end
      return table.concat(got, " "):gsub(" ([%.,:])", "%1")
    end
    for _, id in ipairs({ "CS2_231", "EX1_129", "GAME_005", "CS2_074", "EX1_129", "GAME_005" }) do
      local plain = ns.Widgets.PlainText(ns.PrintedCards[id].text or "")
      H.eq(words(id), plain, ns.PrintedCards[id].name .. " keeps every word")
    end
  end)
end)

H.suite("ui: a leaning hand card's text turns with the card", function(ns, H)
  --[[ THE REPORT (a screenshot of a fanned hand): the words of a tilted card
       made a staircase off its edge. The client turns each text region about
       its OWN centre, so each word's centre must be moved to where it falls
       on the turned card -- rotated about the card's centre by the lean. ]]
  withBoard(ns, function(board)
    local w = ns.Widgets.New(board.frame)
    w.liveText = true   -- the live labels: the fallback for a card with no baked text
    ns.Widgets.SetDescriptor(w, board.resolver:Card("EX1_581"))    -- Sap: three lines
    local rot = 0.12
    ns.Widgets.ApplyRect(w, { x = 100, y = 100, w = 105, h = 150, rot = rot, lean = ns.Widgets.LeanInset(150 / 105) })
    H.eq(w.lean, rot, "the card leans")
    local c, s = math.cos(rot), math.sin(rot)
    local runs = w.bodyRich:Runs()
    H.ok(#runs >= 5, "Sap's text is several words")
    for i, fs in ipairs(runs) do
      local up = w.bodyRich.centres[i]
      local _, rel, _, x, y = fs:GetPoint(1)
      H.eq(rel, w.frame)
      H.ok(math.abs(x - (up[2] * c - up[3] * s)) < 0.01 and math.abs(y - (up[2] * s + up[3] * c)) < 0.01,
           "'" .. fs:GetText() .. "' sits where it falls on the turned card")
    end
    -- the words of one line stay on one turned baseline: equal slope between them
    local first, second = w.bodyRich.centres[1], w.bodyRich.centres[2]
    local _, _, _, x1, y1 = runs[1]:GetPoint(1); local _, _, _, x2, y2 = runs[2]:GetPoint(1)
    if first[3] == second[3] then
      H.ok(math.abs((y2 - y1) / (x2 - x1) - math.tan(rot)) < 0.001, "a line of words tilts with the card")
    end
    local _, _, _, nx, ny = w.name:GetPoint(1)
    H.ok(math.abs(nx - (-w.nameAt[2] * s)) < 0.01, "and the name moves with it")
    ns.Widgets.SetLean(w, 0)
    local _, _, _, ux, uy = runs[1]:GetPoint(1)
    H.ok(math.abs(ux - first[2]) < 0.01 and math.abs(uy - first[3]) < 0.01, "upright again, the words go back")
  end)
end)

H.suite("ui: a hand card draws its baked name and rules text, turned with the card", function(ns, H)
  --[[ THE REPORT: tilted hand-card text was jagged and hard to read -- the
       client draws a leaning FontString badly. The name and the rules text
       are images (tools/build_card_text.py), card-sized regions like the skin
       so they share its pivot, and the live labels step aside. ]]
  withBoard(ns, function(board)
    local W = ns.Widgets
    local w = W.New(board.frame)
    W.SetDescriptor(w, board.resolver:Card("EX1_581"))    -- Sap
    W.ApplyRect(w, { x = 100, y = 100, w = 105, h = 150, rot = 0.12, lean = W.LeanInset(150 / 105) })
    H.ok(w.baked, "a printed hand card uses its baked text")
    H.ok(w.bakedName:IsShown() and w.bakedText:IsShown(), "both bands drawn")
    H.ok(w.bakedName:GetTexture():find("CardText\\EX1_581%-n%.tga"), "the name band is Sap's")
    H.ok(w.bakedText:GetTexture():find("CardText\\EX1_581%-t%.tga"), "and so is the rules band")
    for _, t in ipairs({ w.bakedName, w.bakedText }) do
      H.eq(t.w, w.skin:GetWidth()); H.eq(t.h, w.skin:GetHeight())
      local _, rel, _, x, y = unpack(t.points[1])
      H.eq(rel, w.frame); H.eq(x, 0); H.eq(y, 0)
    end
    -- the band lands on its rect of the face: texcoord 0..1 spans exactly it
    local u0, u1 = w.bakedText.texcoord[1], w.bakedText.texcoord[2]
    local rect = ns.CardText.text.SPELL
    H.ok(math.abs(-u0 / (u1 - u0) - rect[1]) < 1e-6, "the rules band starts where its rect does")
    for _, fs in ipairs(w.bodyRich:Runs()) do H.notOk(fs:IsShown(), "the live words step aside") end
    H.eq(w.name:GetAlpha(), 0, "and so does the live name")
    H.eq(w.body:GetText(), W.PlainText(ns.PrintedCards.EX1_581.text), "the plain text is still kept for reading")
    W.SetFaceDown(w, true)
    H.notOk(w.bakedName:IsShown() or w.bakedText:IsShown(), "face down shows no text")
    W.SetFaceDown(w, false)
    H.ok(w.bakedName:IsShown() and w.bakedText:IsShown(), "face up again shows it")
    -- a card too large for the images (the enlarged inspect card) is drawn live
    W.ApplyRect(w, { x = 0, y = 0, w = 420, h = 600 })
    H.notOk(w.baked, "an enlarged card uses the live labels")
    H.notOk(w.bakedName:IsShown()); H.eq(w.name:GetAlpha(), 1)
    -- a card with no rules text has only a name band
    W.SetDescriptor(w, board.resolver:Card("CS2_182"))    -- Chillwind Yeti
    W.ApplyRect(w, { x = 0, y = 0, w = 105, h = 150 })
    H.ok(w.baked and w.bakedName:IsShown()); H.notOk(w.bakedText:IsShown(), "no rules band for a vanilla minion")
  end)
end)

H.suite("ui: hovering a hero power shows Hearthstone's hero-power card", function(ns, H)
  --[[ THE REPORT: the Fireblast hover was a black box with a cyan outline --
       the unskinned fallback, because there was no hero-power frame. ]]
  withBoard(ns, function(board)
    local W = ns.Widgets
    local w = W.New(board.frame)
    W.SetDescriptor(w, board.resolver:Card("CS2_034"))    -- Fireblast
    W.ApplyRect(w, { x = 0, y = 0, w = 210, h = 300 })
    H.ok(w.skinned, "a framed card, not the fallback box")
    H.ok(w.skin:GetTexture():find("inhand_hero_power.tga", 1, true), "Hearthstone's hero-power frame")
    H.notOk(w.bg:IsShown(), "no dark fallback fill")
    for _, e in ipairs(w.edges) do H.notOk(e:IsShown(), "no coloured outline") end
    H.ok(w.artMask:GetTexture():find("mask-oval", 1, true), "the art is round, in the stone ring")
    H.eq(w.rulesText, "Deal 1 damage.", "the card prints the effect, not the type")
    H.notOk(w.gem:IsShown(), "no rarity gem on a hero power")
  end)
end)

H.suite("ui: a minion with a race prints it on the race banner", function(ns, H)
  withBoard(ns, function(board)
    local W = ns.Widgets
    local w = W.New(board.frame)
    W.SetDescriptor(w, board.resolver:Card("EX1_506"))    -- Murloc Tidehunter
    W.ApplyRect(w, { x = 0, y = 0, w = 105, h = 150 })
    H.eq(w.raceLabel, "Murloc")
    H.ok(w.raceBanner:IsShown() and w.raceBanner:GetTexture():find("race-banner.tga", 1, true), "the banner")
    H.ok(w.bakedRace:IsShown() and w.bakedRace:GetTexture():find("EX1_506%-r%.tga"), "and the baked word on it")
    W.SetFaceDown(w, true); H.notOk(w.raceBanner:IsShown(), "hidden face down")
    W.SetFaceDown(w, false); H.ok(w.raceBanner:IsShown(), "and back")
    w.liveText = true; W.ApplyRect(w, { x = 0, y = 0, w = 105, h = 150 })
    H.ok(w.race:IsShown() and w.race:GetText() == "Murloc", "live, the word is a label")
    w.liveText = nil
    W.SetDescriptor(w, board.resolver:Card("CS2_182"))    -- Chillwind Yeti: no race
    W.ApplyRect(w, { x = 0, y = 0, w = 105, h = 150 })
    H.notOk(w.raceBanner:IsShown() or w.race:IsShown() or w.bakedRace:IsShown(), "no banner without a race")
  end)
end)

H.suite("ui: every card that can be held has its baked text on disk", function(ns, H)
  local n = 0
  for id, p in pairs(ns.PrintedCards) do
    if p.type == "MINION" or p.type == "SPELL" or p.type == "WEAPON" then
      local e = ns.CardText.cards[id]
      H.ok(e, id .. " is baked")
      if e then
        n = n + 1
        H.eq(e[1], p.type, id .. " baked for its own frame")
        local namePath, textPath = ns.Widgets and ns.Widgets.CardTextPaths and ns.Widgets.CardTextPaths(id)
        local base = "ForeverHearthstone/Art/CardText/" .. id
        local f = io.open(base .. "-n.tga", "rb"); H.ok(f, id .. " name band exists"); if f then f:close() end
        if e[2] then
          f = io.open(base .. "-t.tga", "rb"); H.ok(f, id .. " rules band exists"); if f then f:close() end
        end
        H.eq(e[2], (p.text or ""):gsub("<[^>]+>", ""):match("%S") ~= nil, id .. " has a rules band exactly when it has text")
      end
    end
  end
  H.ok(n > 700, "all of them")
end)

H.suite("ui: rules text is laid out again once its font has loaded", function(ns, H)
  -- A font the client has not loaded yet measures 0 wide; the layout must
  -- not keep a text built from zero-width words.
  withBoard(ns, function(board)
    local w = ns.Widgets.New(board.frame)
    w.liveText = true   -- the live labels: the fallback for a card with no baked text
    local measure = w.bodyRich.measure
    measure.GetUnboundedStringWidth = function() return 0 end   -- font not loaded yet
    ns.Widgets.SetDescriptor(w, board.resolver:Card("EX1_129"))
    ns.Widgets.ApplyRect(w, { x = 0, y = 0, w = 105, h = 150 })
    local early = 0
    for _, fs in ipairs(w.bodyRich:Runs()) do if fs:IsShown() then early = math.max(early, fs:GetWidth()) end end
    H.ok(early < 10, "measured with an unloaded font, the runs start out empty")
    measure.GetUnboundedStringWidth = nil                          -- the font arrives
    Stub.Advance(0.5)
    local wide = 0
    for _, fs in ipairs(w.bodyRich:Runs()) do if fs:IsShown() then wide = math.max(wide, fs:GetWidth()) end end
    H.ok(wide > 10, "the runs were measured again with the loaded font")
  end)
end)

H.suite("ui: a taunt minion's glow follows its shield, not the oval under it", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {"CS2_179","CS2_182"}, {}, {myTurn=true,
      boardStats={{atk=3,health=5,taunt=true,canAttack=true},{atk=4,health=5,canAttack=true}}}))
    local taunt, plain = b.boardPool.used[1], b.boardPool.used[2]
    H.ok(taunt.glow:GetTexture():find("inplay_minion_taunt%-glow"), "the shield's glow")
    H.ok(plain.glow:GetTexture():find("inplay_minion%-glow"), "an ordinary minion keeps the oval")
    H.ok(taunt.glow:GetWidth() > plain.glow:GetWidth(), "and it reaches past the shield")
    b:SetSnapshot(snapshot({}, {"CS2_179","CS2_182"}, {}, {myTurn=true,
      boardStats={{atk=3,health=5},{atk=4,health=5}}}))
    H.ok(b.boardPool.used[1].glow:GetTexture():find("inplay_minion%-glow"), "silenced: back to the oval")
  end)
end)

H.suite("ui: a match loads the art of every card it can put on the table", function(ns, H)
  --[[ THE REPORT: "when a card is polymorphed it took a while for the art to
       show up and just showed the play background". The client loads a
       texture the first time it is drawn; the Sheep had never been drawn. ]]
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua", "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua", "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone"); Stub.Fire("PLAYER_LOGIN")
  local g = H.NewGame({ deck1 = { "CS2_022", "EX1_246", "GVG_078", "EX1_562" } })
  local ids = {}
  for _, id in ipairs(ns.Main:MatchArtIds(g)) do ids[id] = true end
  H.ok(ids.CS2_022 and ids.CS2_tk1, "Polymorph, and the Sheep it makes")
  H.ok(ids.hexfrog, "Hex's Frog")
  H.ok(ids.PART_001, "Mechanical Yeti's Spare Parts")
  H.ok(ids.EX1_562 and ids.ds1_whelptoken, "Onyxia, and the Whelps her script summons")
  H.ok(ids[g.players[1].heroPower.cardId] and ids[g.players[2].hero.cardId], "the heroes and their powers")

  ns.Main:StartPractice()
  local b = ns.Main.board
  local art = b.resolver:Card("CS2_tk1").icon
  local n = b:PrefetchArt(ns.Main:MatchArtIds(g))
  local found
  for i = 1, n do
    local t = b.prefetchTex[i]
    if t:GetTexture() == art then found = t end
  end
  H.ok(found and found:IsShown(), "the Sheep's art is drawn before any Sheep is")
  H.ok(found:GetAlpha() < 0.05, "unseen")
  H.ok(b:PrefetchArt({ "CS2_231" }) == 1, "one card, one art")
  local shown = 0
  for _, t in ipairs(b.prefetchTex) do if t:IsShown() then shown = shown + 1 end end
  H.eq(shown, 2, "the next match reuses the same textures: the Wisp's art and its name band (no rules text)")
end)

H.suite("ui: a minimap button opens the game, so nobody needs /fh", function(ns, H)
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua", "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua", "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/UI/Collection.lua", "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone"); Stub.Fire("PLAYER_LOGIN")
  local M = ns.Main
  local b = M.minimapButton
  H.ok(b and b:IsShown(), "there at login")
  H.ok(b.icon:GetTexture():find("minimap%-icon%.tga"), "wearing the Hearthstone medallion")
  local p = b.points[1]
  H.eq(p[2], Minimap, "anchored to the minimap")
  local d = math.sqrt(p[4] ^ 2 + p[5] ^ 2)
  H.ok(math.abs(d - (Minimap:GetWidth() / 2 + 5)) < 0.01, "on its rim")

  b:Click("LeftButton")
  H.ok(M.hub and M.hub:IsShown(), "left-click: the main menu")
  b:Click("LeftButton")
  H.notOk(M.hub:IsShown(), "and again closes it")

  -- square maps put it on the square's edge, not inside the corner
  local x, y = M.MinimapOffset(45, 80, true)
  H.ok(math.abs(x - 80) < 0.01 and math.abs(y - 80) < 0.01, "a square map's corner")
  x, y = M.MinimapOffset(90, 80, false)
  H.ok(math.abs(x) < 0.01 and math.abs(y - 80) < 0.01, "a round map's rim")

  -- a remembered angle is where it comes back
  M:MinimapSettings().angle = 0
  M:PlaceMinimapButton()
  H.ok(math.abs(b.points[1][4] - 75) < 0.01 and math.abs(b.points[1][5]) < 0.01, "placed at its saved angle")

  M:ToggleMinimapButton()
  H.notOk(b:IsShown(), "/fh minimap hides it")
  H.ok(ForeverHearthstoneDB.minimap.hide, "and remembers")
  M:ToggleMinimapButton()
  H.ok(b:IsShown(), "and brings it back")
  H.ok(ForeverHearthstone_OnAddonCompartmentClick, "the Addon Compartment entry has its handler")
end)

--============================================================ docs/27

H.suite("ui: right-clicking a card shows what its keywords do", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({"CS2_179"}, {"CS2_179"}, {}))       -- Sen'jin Shieldmasta: Taunt
    b:ShowInspect("CS2_179")
    local panels = b.inspect.keywordPanels or {}
    H.ok(panels[1] and panels[1]:IsShown(), "a reminder box beside the enlarged card")
    H.eq(panels[1] and panels[1].title:GetText(), "Taunt", "naming the keyword")
    H.ok(panels[1] and panels[1].text:GetText():find("attack", 1, true), "and what it does")
    b:HideInspect()
    b:ShowInspect("CS2_182")                                     -- Chillwind Yeti: nothing
    H.notOk(panels[1]:IsShown(), "a vanilla minion has none")
    H.eq(#ns.Widgets.KeywordsOf(ns.PrintedCards["CS2_031"]), 1, "Ice Lance's Frozen calls up Freeze")
  end)
end)

H.suite("ui: a shove from before the board was laid out again moves nothing", function(ns, H)
  --[[ Minions were sometimes left off centre after a play (Gnomish Inventor):
       the shove recomputed its row from the live count, which by its last
       beats already included the new minion. ]]
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182","CS2_182"}, {}))
    local stage = b:Stage()
    b:SetSnapshot(snapshot({}, {"CS2_182","CS2_182","CS2_182"}, {}))
    local laid = {}
    for i, w in ipairs(b.myMinions) do laid[i] = w.rect.x end
    stage:Board():Shove(3, 1, true)
    for i, w in ipairs(b.myMinions) do H.eq(w.rect.x, laid[i], "minion " .. i .. " stays where the layout put it") end
  end)
end)

H.suite("ui: a shove makes room in the row as it stood when the play began", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {"CS2_182","CS2_182"}, {}))
    b:BeginPresentation()
    local stage = b:Stage()
    b:SetSnapshot(snapshot({}, {"CS2_182","CS2_182","CS2_182"}, {}))   -- held back by the lock
    stage:Board():Shove(3, 1, true)
    local L = ns.Layout.Compute({ width = b.frame:GetWidth(), height = b.frame:GetHeight(), boardCount = 3 })
    H.ok(math.abs((b.myMinions[1].rect.x) - (L.boardSlots[1].x)) < 0.5, "room for ONE more minion, not two")
    b:EndPresentation()
  end)
end)

H.suite("ui: a battlecry minion is played from where its ghost stands", function(ns, H)
  --[[ Aiming a battlecry puts the minion on the board as a ghost; playing it
       then flew the card out of the hand again, as if played twice. ]]
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({"EX1_066","CS2_182"}, {"CS2_182"}, {}))
    local slot = b:ShowPlacementGhost("EX1_066", 1, 0.6)
    H.ok(b:BeginPlayAnimation(1), "the play animates")
    H.ok(math.abs((b.flyingCard.rect.x) - (slot.x)) < 0.5, "from the ghost's place on the board")
    H.ok(math.abs((b.flyingCard.rect.y) - (slot.y)) < 0.5, "not from the hand")
    H.ok(b.flyingCard.inPlay, "looking like the minion it already was")
    b:EndPlayAnimation(); b:ClearPlacementPreview()
    b:BeginPlayAnimation(2)
    H.notOk(b.flyingCard.inPlay, "an ordinary play still lifts the card out of the hand")
    b:EndPlayAnimation()
  end)
end)

H.suite("ui: a card's textures do not snap to the pixel grid one by one", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({"CS2_182"}))
    local w = b.handWidgets[1]
    H.eq(rawget(w.art, "snap"), false, "the art moves with the card")
    H.eq(rawget(w.skin, "snap"), false, "and so does its frame")
    -- the digits are made after the card, when a number is first set
    b:SetSnapshot(snapshot({"CS2_182"}))
    w = b.handWidgets[1]
    local digits = 0
    for _, n in ipairs({ w.cost, w.atk, w.hp }) do
      for _, g in ipairs(n.glyphs or {}) do
        digits = digits + 1
        H.eq(rawget(g, "snap"), false, "a digit moves with its card")
      end
    end
    H.ok(digits >= 3, "the Yeti's cost, attack and health have glyphs")
  end)
end)

H.suite("ui: the main menu's record lines its W - L figures up on the card's centre", function(ns, H)
  Stub.Install(_G)
  Stub.units = { player = { name = "Tester", class = "MAGE", isPlayer = true, level = 60 } }
  _G.ForeverHearthstoneDB, _G.ForeverHearthstoneCharDB = {}, {}
  for _, path in ipairs({ "ForeverHearthstone/Client/Net/Transport.lua", "ForeverHearthstone/Client/Rewards.lua",
                          "ForeverHearthstone/Client/UI/Widgets.lua", "ForeverHearthstone/Client/UI/Board.lua",
                          "ForeverHearthstone/Client/UI/Collection.lua", "ForeverHearthstone/Client/Main.lua" }) do
    assert(loadfile(path))("ForeverHearthstone", ns)
  end
  Stub.Fire("ADDON_LOADED", "ForeverHearthstone"); Stub.Fire("PLAYER_LOGIN")
  local M = ns.Main
  M:Record().wins, M:Record().losses = 12, 3
  M:ShowHub()
  local hub = M.hub
  H.ok(hub.record:IsShown(), "the record card is up")
  H.eq(hub.record.text:IsShown(), false, "no single centred string")
  local rows = hub.recordRows
  H.eq(rows[1].label:GetText(), "Duels:", "duels row")
  H.eq((rows[1].value:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "12 W - 3 L", "with this character's duel record")
  H.ok(rows[1].value:GetText():find("|c" .. ns.Widgets.RECORD_COLOURS.light.win .. "12 W|r", 1, true), "wins in green")
  H.ok(rows[1].value:GetText():find("|c" .. ns.Widgets.RECORD_COLOURS.light.loss .. "3 L|r", 1, true), "losses in red")
  H.eq(rows[2].label:GetText(), "Practice:", "practice row")
  for i, r in ipairs(rows) do
    local lp, vp = r.label.points[1], r.value.points[1]
    H.eq(lp[1], "TOPRIGHT", "row " .. i .. ": the label ends at the centre line")
    H.eq(lp[3], "TOP", "row " .. i .. ": measured from the card's middle")
    H.eq(vp[1], "TOPLEFT", "row " .. i .. ": the figures start from it")
    H.eq(vp[3], "TOP", "row " .. i .. ": the same middle")
    H.eq(r.label:GetJustifyH(), "RIGHT", "labels right-aligned")
    H.eq(r.value:GetJustifyH(), "LEFT", "figures left-aligned")
    H.ok(-lp[5] + 17 <= hub.record:GetHeight() - 8, "row " .. i .. " sits inside the card")
  end
  H.ok(rows[2].value.points[1][5] < rows[1].value.points[1][5], "practice under duels")
end)

H.suite("ui: numbers drawn as text sit on their gems, not above them", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}, { mana = 7, hero = { cardId = "HERO_01", health = 30, maxHealth = 30, armor = 5 } }))
    local m = b.L.manaReadout
    local p = b.manaText.points[1]
    H.ok(p[5] < m.y + m.h / 2, "the mana readout is lowered by the digit rise")
    H.ok(ns.Widgets.DIGIT_RISE > 0 and ns.Widgets.DIGIT_RISE < 0.1, "by a few percent of its size")
    local hp = b.hero.health.points[1]
    local hh = b.hero.frame:GetHeight()
    H.ok(hp[5] < hh * 0.1, "hero health on the drop's bulb, below the drop's box middle")
    H.ok(hp[5] > hh * 0.05, "but still on the drop")
  end)
end)

H.suite("0.1.3: the rope is drawn thick enough to see", function(ns, H)
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({}, {}, {}))
    local L = b.L
    H.ok(L.rope.h >= L.art.h * .018, "the rope's rect is ~2% of the picture")
  end)
end)

H.suite("0.1.3: in a tall window the enemy hand keeps out of the corner buttons", function(ns, H)
  withBoard(ns, function(b)
    b.concede:Show()
    b:SetSnapshot(snapshot({}, {}, {}, { foeHandCount = 10 }))
    b.frame:SetSize(913, 1419); Stub.Advance(.5)
    local L = b.L
    local cw, ch = b.corner:Extent()
    for i, r in ipairs(L.foeHandSlots) do
      local clear = r.x + r.w <= L.width - cw or r.y + r.h <= L.height - ch
      H.ok(clear, "card " .. i .. " is clear of the corner row")
    end
  end, { width = 913, height = 1419 })
end)

H.suite("ui: history shows frozen buffed and damaged minion stats", function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {}))
    local g=H.NewGame()
    H.Mana(g,1,10)
    local egg=H.Put(g,1,"FP1_007")
    local action={kind="PLAY_CARD",handIndex=H.Hand(g,1,"CS2_092"),targetId=egg.instanceId}
    local before=ns.Director.Before(g,1,action)
    H.ok(ns.Actions.Run(g,1,action))
    local outcomes=ns.Director.Outcomes(g,before)
    b:AddHistory("CS2_092","Buff",false,action,before,outcomes)
    egg.damage=2
    b:ShowHistory(b.historyButtons[1],b.history[1])
    H.eq(b.historyPreview.target.atk:GetText(),"4")
    H.eq(b.historyPreview.target.hp:GetText(),"6","later damage cannot rewrite the buff")
    local target=H.Put(g,2,"CS2_120")
    action={kind="ATTACK",attackerId=egg.instanceId,targetId=target.instanceId}
    before=ns.Director.Before(g,1,action)
    H.ok(ns.Actions.Run(g,1,action))
    b:AddHistory(egg.cardId,"Attack",false,action,before,ns.Director.Outcomes(g,before))
    b:ShowHistory(b.historyButtons[1],b.history[1])
    H.eq(b.historyPreview.source.atk:GetText(),"4","Egg attacked with its buff")
    H.eq(b.historyPreview.source.hp:GetText(),"4","attacker health at the time of attack")
    H.eq(b.historyPreview.target.hp:GetText(),"0","dead target retains resolved damage")
  end)
end)

H.suite("ui: empty enemy board accepts minions and untargeted spells",function(ns,H)
  for _,id in ipairs({"CS2_120","GAME_005"}) do
    withBoard(ns,function(b,intents)
      b:SetSnapshot(snapshot({id},{},{}))
      local r=b.L.field
      b.CursorInBoard=function() return r.x+r.w/2,r.y+r.h*.85 end
      local w=b.handWidgets[1]
      b:BeginDrag(w)
      H.ok(b:EndDrag(w))
      H.eq(#intents,1)
      H.eq(intents[1].kind,"PLAY_CARD")
      if id=="CS2_120" then H.eq(intents[1].position,1) end
    end)
  end
end)

H.suite("ui: enemy hovered cards clear portraits and empty aim clears the arrow",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}, {}, {"CS2_120"},{myTurn=false,foeHandCount=3,eventSeq=1}))
    b:SetOpponentHover(2,"b1","E")
    H.ok(b.foeHandPool.used[2].frame:GetFrameLevel()>b.foeHero.frame:GetFrameLevel())
    b:SetOpponentHover(2,"b1","")
    H.notOk(b.foeArrow.frame:IsShown())
    b:SetOpponentHover(2,"b1","E")
    b:SetSnapshot(snapshot({}, {}, {"CS2_120"},{myTurn=false,foeHandCount=3,eventSeq=2}))
    H.notOk(b.foeArrow.frame:IsShown(),"resolved actions clear stale board slots")
    local last
    b.opts.onHover=function(...) last={...} end
    b:SetSnapshot(snapshot({}, {}, {},{myTurn=true}))
    b:UpdateArrow()
    H.eq(last[2],""); H.eq(last[3],"","selection ending reports the clear")
  end)
end)

H.suite("ui: history names battlecries and combines repeated damage hits",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({}))
    b:AddHistory("CS2_189","You: play card",false,{kind="PLAY_CARD"},
      {targetCardId="CS2_182"},{{cardId="CS2_182",targetId=4,amount=1,health=4}})
    b:ShowHistory(b.historyButtons[1],b.history[1])
    H.ok(b.tooltip.title:GetText():find("Battlecry"))
    b:AddHistory("EX1_277","You: play card",false,{kind="PLAY_CARD"},{},
      {{cardId="CS2_182",targetId=4,amount=1,health=4},{cardId="CS2_182",targetId=4,amount=1,health=3}})
    b:ShowHistory(b.historyButtons[1],b.history[1])
    H.ok(b.tooltip.text:GetText():find("%-2 %-> 3 health"))
  end)
end)

H.suite("ui: minion card Attack and Health share a baseline",function(ns,H)
  withBoard(ns,function(b)
    b:SetSnapshot(snapshot({"CS2_120"}))
    local w=b.handWidgets[1]
    H.eq(w.atk.point[5],w.hp.point[5])
  end)
end)

H.suite("ui: live spell damage updates the hand face and inspection",function(ns,H)
  withBoard(ns,function(b)
    local s=snapshot({"CS2_029"},{},{},{handStats={{instanceId=123,rulesText="Deal 7 damage."}}})
    b:SetSnapshot(s)
    H.eq(b.handWidgets[1].rulesText,"Deal 7 damage.")
    H.notOk(b.handWidgets[1].baked)
    b:ShowInspect("CS2_029",s.handStats[1])
    H.eq(b.inspect.card.rulesText,"Deal 7 damage.")
    H.notOk(b.inspect.card.baked)
    s.handStats[1].rulesText="Deal 6 damage."
    b:SetSnapshot(s)
    H.eq(b.handWidgets[1].rulesText,"Deal 6 damage.")
  end)
end)

H.suite("ui: the whole table drains to grey at the end, and comes back exactly", function(ns, H)
  --[[ The in-client tour (docs/39): only the cloth went grey, so minions,
       heroes and the hand sat in full colour on a grey table. ]]
  withBoard(ns, function(b)
    b:SetSnapshot(snapshot({ "CS2_029" }, { "CS2_182" }, { "CS2_182" },
      { boardStats = { { instanceId = 11, atk = 4, health = 5 } } }))
    local art = b.myMinions[1].art or b.boardPool.used[1].art
    local already = b.frame:CreateTexture(nil, "ARTWORK")
    already:SetDesaturated(true)          -- grey for its own reason
    H.notOk(art:IsDesaturated(), "in colour during play")
    b:ShowResult("victory", {})
    H.ok(art:IsDesaturated(), "a minion drains with the table")
    H.notOk(b.result.portrait:IsDesaturated(), "the victorious hero in the arch does not")
    b:HideResult()
    H.notOk(art:IsDesaturated(), "colour returns")
    H.ok(already:IsDesaturated(), "and what was grey before stays grey")
  end)
end)

H.suite("ui: a window's very first opening already takes the screen-scaled default", function(ns, H)
  -- a frame is created shown, so no OnShow carries the default (tour run 2, docs/39)
  withBoard(ns, function()
    local W = ns.Widgets
    W.ForgetRect()
    local f = CreateFrame("Frame", "ForeverHearthstoneFirstOpenTest", UIParent)
    f:SetSize(1280, 720)
    W.ResizeGrip(f, 760, 560)
    local dw, dh = W.DefaultSize({ w = 1280, h = 720 })
    H.ok(dw > 1280, "the stub screen is big enough to scale up")
    H.eq(f:GetWidth(), dw, "first opening, default width")
    H.eq(f:GetHeight(), dh, "and height")
  end)
end)

H.suite("ui: a deck box shows its signature card, a Basic deck its hero", function(ns, H)
  -- twelve decks of one class were twelve identical portraits (docs/39)
  withBoard(ns, function()
    local W = ns.Widgets
    H.eq(W.DeckSignature({ class = "MAGE", cards = {} }), ns.HERO_ID_BY_CLASS.MAGE, "empty: the hero")
    H.eq(W.DeckSignature({ class = "MAGE", cards = { "CS2_029", "CS2_032" } }), ns.HERO_ID_BY_CLASS.MAGE,
         "only Basic cards: the hero")
    H.eq(W.DeckSignature({ class = "MAGE", cards = { "CS2_029", "EX1_559", "EX1_016", "NEW1_030" } }), "NEW1_030",
         "the rarest, then the costliest: Deathwing over Sylvanas and Archmage Antonidas")
  end)
end)
