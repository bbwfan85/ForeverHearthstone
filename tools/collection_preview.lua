-- Exports the actual collection frame tree for offline composition review.
local H=require('tests.harness'); local ns=H.LoadEngine()
local Stub=require('tests.wowstub'); Stub.Install(_G)
Stub.units={player={name='Preview',class='ROGUE',isPlayer=true,level=60}}
ForeverHearthstoneDB={}; ForeverHearthstoneCharDB={}
for _,path in ipairs({'Net/Transport','Rewards','UI/Widgets','UI/Board','UI/Collection','Main'}) do
 assert(loadfile('ForeverHearthstone/Client/'..path..'.lua'))('ForeverHearthstone',ns)
end
Stub.Fire('ADDON_LOADED','ForeverHearthstone'); Stub.Fire('PLAYER_LOGIN')
local ui=ns.Main:Collection()
local function json(v)
 if type(v)=='string' then return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')..'"' end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if type(v)~='table' then return 'null' end
 local parts={}
 if #v>0 then for _,x in ipairs(v) do parts[#parts+1]=json(x) end; return '['..table.concat(parts,',')..']' end
 for k,x in pairs(v) do parts[#parts+1]=json(k)..':'..json(x) end
 return '{'..table.concat(parts,',')..'}'
end
local function capture(name,root)
 local cache={}
 local anchors={TOPLEFT={0,1},TOP={.5,1},TOPRIGHT={1,1},LEFT={0,.5},CENTER={.5,.5},RIGHT={1,.5},BOTTOMLEFT={0,0},BOTTOM={.5,0},BOTTOMRIGHT={1,0}}
 local function rect(o)
  if o==root then return {0,0,root.w,root.h} end
  if cache[o] then return cache[o] end
  local parent=rawget(o,'parent'); if not parent then return {0,0,0,0} end
  local pr=rect(parent)
  local ap=rawget(o,'allPoints'); if ap then local r=type(ap)=='table' and rect(ap) or pr; cache[o]=r; return r end
  local w,h=rawget(o,'w') or 0,rawget(o,'h') or 0
  local font=rawget(o,'font');local text=rawget(o,'text')
  if font and text then w=w>0 and w or #text*font[2]*.52;h=h>0 and h or font[2]*1.3 end
  local p=(rawget(o,'points') or {})[1] or {'TOPLEFT'}
  local rel=type(p[2])=='table' and p[2] or parent
  local rr=rect(rel);local a=anchors[p[1]] or anchors.CENTER;local b=anchors[p[3] or p[1]] or anchors.CENTER
  local r={rr[1]+rr[3]*b[1]+(p[4] or 0)-w*a[1],rr[2]+rr[4]*b[2]+(p[5] or 0)-h*a[2],w,h}
  cache[o]=r;return r
 end
 local function shown(o)
  if rawget(o,'shown')==false then return false end
  if o==root then return true end
  local p=rawget(o,'parent');return p and shown(p)
 end
 local function alpha(o)
  if o==root then return rawget(o,'alpha') or 1 end
  return (rawget(o,'alpha') or 1)*alpha(rawget(o,'parent'))
 end
 local out={name=name,w=root.w,h=root.h,items={}}
 local function add(o,isText)
  if not shown(o) or rawget(o,'layer')=='MASK' then return end
  local r=rect(o);if r[3]<=0 or r[4]<=0 then return end
  local parent=rawget(o,'parent')
  -- `level` is the stub's frame level, but a widget may also keep a child in a
  -- field of that name (the profile panel's "level" label); only a number counts.
  local level=rawget(parent,'level')
  -- An edit box draws its own text, so it sits at its own frame level.
  if rawget(o,'__frameKind')=='EditBox' then level=rawget(o,'level') end
  local item={x=r[1],y=root.h-r[2]-r[4],w=r[3],h=r[4],level=type(level)=='number' and level or 1,
    layer=rawget(o,'layer') or 'OVERLAY',color=rawget(o,'colour') or {1,1,1,1},alpha=alpha(o)}
  if isText then item.wrap=(rawget(o,'w') or 0)>0 and rawget(o,'wordWrap')~=false; item.text=rawget(o,'text');item.font=rawget(o,'font');item.justify=rawget(o,'justifyH') or 'CENTER';item.valign=rawget(o,'justifyV') or 'MIDDLE'
  else item.texture=rawget(o,'texture');if type(item.texture)=='table' then item.texture=rawget(item.texture,'texture') end;item.uv=rawget(o,'texcoord');item.solid=not item.texture;local m=rawget(o,'mask');if m then item.mask=rawget(m,'texture') end end
  out.items[#out.items+1]=item
 end
 for _,t in ipairs(Stub.R.textures) do add(t,false) end
 for _,t in ipairs(Stub.R.fontstrings) do add(t,true) end
 for _,f in ipairs(Stub.R.frames) do if rawget(f,'__frameKind')=='EditBox' then add(f,true) end end
 local file=assert(io.open((os.getenv('FH_PREVIEW_DIR') or 'tools')..'/'..name..'.json','w'));file:write(json(out));file:close()
end
ui.frame:SetSize(1660,891); capture('collection-wide',ui.frame)
ui.frame:SetSize(1842,672); ui:Relayout(); capture('collection-short',ui.frame); ui.frame:SetSize(1660,891); ui:Relayout()
local deck,index=ns.Main.collection:NewDeck('Valeera’s Collection','ROGUE')
for _,entry in ipairs(ui:Entries()) do if #deck.cards<24 then deck.cards[#deck.cards+1]=entry.cardId end end
ui:EditDeck(index);capture('deck-wide',ui.frame)
ui.frame:SetSize(760,560);capture('deck-compact',ui.frame)
ui.menuItems[1]:GetScript('OnEnter')(); capture('deck-hover',ui.frame)
ui.menuItems[1]:GetScript('OnLeave')()
for i=2,12 do ns.Main.collection:NewDeck('Valeera deck number '..i,'ROGUE') end
ui:ShowDecks();capture('decks-browser',ui.frame)
ui.menuItems[43]:Click();capture('decks-page-two',ui.frame)
ui:ShowPackRoom();ui.frame:SetSize(1180,700);capture('packs-new',ui.frame)
ui.frame:SetSize(1842,672);ui:Relayout();capture('packs-wide',ui.frame)
ns.Main:ShowHub();Stub.Advance(.4);capture('hearth-menu',ns.Main.hub)
ns.Main.hub:SetSize(800,600);capture('hearth-compact',ns.Main.hub)
ns.Main.hub:SetSize(1842,672);ns.Main.hub:Layout();capture('hearth-wide',ns.Main.hub)
ns.Main.hub:SetSize(1000,680);ns.Main.hub.buttons[1]:Click();capture('practice-new',ns.Main.hub)
ns.Main.hub.play:Click(); capture('practice-decks',ns.Main.hub)
ns.Main.hub:SetSize(800,600); capture('practice-decks-compact',ns.Main.hub)
ns.Main.hub:SetSize(1842,672); ns.Main.hub:Layout(); capture('practice-wide',ns.Main.hub)

ui:Show(); ui:ShowPackRoom(); ns.Main.collection:AddPack('CLASSIC',1)
ui:OpenPack('CLASSIC'); Stub.Advance(2)
ui.pack.cards[4].rarity='LEGENDARY'; ui:RevealCard(4); Stub.Advance(.3)
capture('pack-reveal',ui.frame)

ui:Show(); ui:EditDeck(index)
ns.Main.collection:Add('EX1_116',1)
for _,entry in ipairs(ns.Main.collection:Browse({all=true})) do
 if entry.cardId=='EX1_116' then ui:OnCardClick(entry,'RightButton'); break end
end
ui:DisenchantSelected(); capture('disenchant-confirm',ui.frame)

ns.Main:StartPractice('ROGUE','MAGE')
ns.Main.board.frame:SetSize(800,600)
ns.Main:OnIntent({kind='CONFIRM_MULLIGAN'})
Stub.Advance(2)
capture('board-profiles',ns.Main.board.frame)
ns.Main.board.hero.frame:Click('RightButton')
capture('hero-emote-menu',ns.Main.board.frame)

-- Every portrait state Hearthstone paints, for checking overlay registration.
local b=ns.Main.board
b.frame:SetSize(1200,800)
b:SetSnapshot({hand={'EX1_298','CS2_182','NEW1_030'},board={'EX1_298','CS2_179','EX1_012','CS2_182'},
 foeBoard={'EX1_559','CS2_231','EX1_593','EX1_390'},foeHandCount=4,maxMana=10,mana=10,myTurn=true,player=1,
 boardStats={{atk=8,health=8,frozen=true},{atk=0,health=3,taunt=true,divineShield=true},
  {atk=4,health=4,deathrattle=true},{atk=4,health=5,sleeping=true,trigger=true}},
 foeBoardStats={{atk=1,health=7,trigger=true,stealth=true},{atk=1,health=1,silenced=true},
  {atk=4,health=4,immune=true},{atk=4,health=2,enraged=true,damaged=true}},
 deckCount=30,foeDeckCount=6,hero={cardId='HERO_03',health=30,armor=0,atk=0},foeHero={cardId='HERO_08',health=22,frozen=true},
 heroPower={cardId='CS2_083b',cost=2,used=true},foeHeroPower={cardId='CS2_034',cost=2},
 secrets={{cardId='EX1_287',name='Counterspell'}},foeSecretCount=2})
Stub.Advance(3); if b.emoteMenu then b.emoteMenu:Hide() end; b.banner:Hide()
capture('board-states',b.frame)
-- hovering the enemy's hero power: Hearthstone's hero-power card (docs/24)
b:ShowDescription(b.foeHeroPower.frame,'CS2_034'); capture('match-hero-power',b.frame); b:HideTooltip()
-- a tall, narrow window: the picture letterboxed, the hand under the hero (docs/24)
b.frame:SetSize(923,1000); Stub.Advance(0.5); capture('board-tall',b.frame); b.frame:SetSize(1200,800); Stub.Advance(0.5)
b.frame:SetSize(1842,672); Stub.Advance(0.5); capture('board-wide',b.frame); b.frame:SetSize(1200,800); Stub.Advance(0.5)
-- every board in the rotation, with the same table state on it
for i,name in ipairs({'board-orgrimmar','board-stormwind','board-stranglethorn'}) do
 b:SetBoardArt(i-1); capture(name,b.frame)
end
b:SetBoardArt(0)
-- a 16:9 window holding six cards: how tight the fan sits and where (docs/25)
b.frame:SetSize(1280,720)
b:SetSnapshot({hand={'EX1_298','CS2_182','NEW1_030','CS2_029','CS2_032','EX1_277'},board={'CS2_182','CS2_179'},
 foeBoard={'EX1_559'},foeHandCount=5,maxMana=6,mana=6,myTurn=true,player=1,deckCount=18,foeDeckCount=19,
 hero={cardId='HERO_03',health=30},foeHero={cardId='HERO_08',health=24},
 heroPower={cardId='CS2_083b',cost=2},foeHeroPower={cardId='CS2_034',cost=2}})
Stub.Advance(3); if b.emoteMenu then b.emoteMenu:Hide() end; b.banner:Hide()
capture('board-hand',b.frame)
b.frame:SetSize(1200,800); Stub.Advance(0.5)

-- ---------------------------------------------------- match presentation (docs/12)
local base={hand={'CS2_029','CS2_032','EX1_277'},board={'CS2_182','CS2_179'},foeBoard={'EX1_559','CS2_231','EX1_593'},
 foeHandCount=4,maxMana=7,mana=7,myTurn=false,player=1,deckCount=20,foeDeckCount=20,
 boardStats={{instanceId=11,atk=4,health=5},{instanceId=12,atk=0,health=3}},
 foeBoardStats={{instanceId=21,atk=1,health=7},{instanceId=22,atk=1,health=1},{instanceId=23,atk=4,health=4}},
 hero={cardId='HERO_08',health=30},foeHero={cardId='HERO_01',health=18},heroId=1,foeHeroId=2,
 heroPower={cardId='CS2_034',cost=2},foeHeroPower={cardId='CS2_083b',cost=2}}
local function snap(extra) local s={} for k,v in pairs(base) do s[k]=v end for k,v in pairs(extra or {}) do s[k]=v end return s end
b:ResetMatch(); b:SetSnapshot(snap()); b:SetSnapshot(snap({myTurn=true})); Stub.Advance(0.35)
capture('match-turn-banner',b.frame)
Stub.Advance(2); b:ToggleEmotes(); capture('match-emotes',b.frame); b.emoteMenu:Hide()
b:SetSnapshot(snap({myTurn=true,targeting={handIndex=1,legal={21,22,23,2}}}))
local t=b.L.foeBoardSlots[2]; Stub.CursorOver(b.frame,t.x+t.w/2,t.y+t.h/2)
b:UpdateArrow(); capture('match-targeting',b.frame); W_hide=ns.Widgets.HideArrow(b.arrow)
b:SetSnapshot(snap({myTurn=true}))
b:SpellEffect({cardId='CS2_032',mine=true}); b:SpellEffect({cardId='CS2_029',mine=true,targeted=true,targetSide='foe',targetIsHero=true})
Stub.Advance(0.2); capture('match-spells',b.frame)
Stub.Advance(1)
b:SpellEffect({cardId='CS1_112',mine=true}); Stub.Advance(0.25); capture('match-holy-nova',b.frame)
Stub.Advance(1)
b:SetSnapshot(snap({myTurn=true,over=true,winner=1,foeHero={cardId='HERO_01',health=0}}))
Stub.Advance(0.6); capture('match-hero-cracking',b.frame)
Stub.Advance(0.55); capture('match-hero-shatter',b.frame)
Stub.Advance(2.2); capture('match-postgame',b.frame)
-- the drop toast (docs/28): a pack, then a card
ns.Main.toastQueue={}; ns.Main.toastPlaying=nil
ns.Main:OnReward({kind='PACK',set='HEARTHSTONE',total=3}); Stub.Advance(1); capture('drop-toast',ns.Main.worldStage.toastWidget.frame)
Stub.Advance(4); ns.Main:OnReward({kind='CARD',cardId='FP1_031',rarity='LEGENDARY',set='NAXX'}); Stub.Advance(1)
capture('drop-toast-card',ns.Main.worldStage.toastWidget.frame)

-- ============ the extremes from the 0.1.3 review screenshots (docs/32) =========
-- 900x1440 (a tall, narrow window) and 2000x560 (ultrawide at the height floor)
if ui.disenchantDialog then ui.disenchantDialog:Hide() end; ui.selected=nil; if ui.inspect then ui.inspect.frame:Hide() end
for _,sz in ipairs({{'narrow',900,1440},{'ultrawide',2000,560}}) do
 local tag,w,h=sz[1],sz[2],sz[3]
 local hub=ns.Main.hub
 ns.Main:ShowHub(); hub.botMode=false; hub.chooseDeck=false; hub:SetSize(w,h); hub:Layout(); Stub.Advance(.4); capture('x-hearth-'..tag,hub)
 hub.buttons[1]:Click(); hub:Layout(); capture('x-practice-'..tag,hub)
 hub.play:Click(); hub:Layout(); capture('x-practice-decks-'..tag,hub)
 ui:Show(); ui.frame:SetSize(w,h); ui:ShowDecks(); ui:Relayout(); capture('x-decks-'..tag,ui.frame)
 ui.deckBrowser=nil; ui.packRoom=nil; ui.pack=nil; ui:EditDeck(nil); ui:Relayout(); capture('x-collection-'..tag,ui.frame)
 ui:ShowPackRoom(); ui:Relayout(); capture('x-packs-'..tag,ui.frame)
 ns.Main.collection:AddPack('CLASSIC',1); ui:OpenPack('CLASSIC'); Stub.Advance(2)
 ui:RevealCard(1); ui:RevealCard(4); Stub.Advance(.3); ui:Relayout(); capture('x-pack-reveal-'..tag,ui.frame)
 b.frame:SetSize(w,h); Stub.Advance(0.5); capture('x-board-'..tag,b.frame)
end
b:ResetMatch(); b.frame:SetSize(1280,720)
b:SetSnapshot({hand={},board={'CS2_182'},foeBoard={},myTurn=true,boardStats={{instanceId=77,atk=8,health=2,maxHealth=7,damaged=true}},
 hero={cardId='HERO_08',health=30},foeHero={cardId='HERO_01',health=30},maxMana=5,mana=5,
 heroPower={cardId='CS2_034',cost=2},foeHeroPower={cardId='CS2_102',cost=2}})
b.myMinions[1].frame:GetScript('OnEnter')()
capture('board-live-hover',b.frame); b:HideTooltip()
ns.Main:Settings(); ns.Main.settings:SetSize(1280,720)
capture('settings',ns.Main.settings)
