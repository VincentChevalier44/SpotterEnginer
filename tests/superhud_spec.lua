-- SuperHUD (1.3.9, app facultative) : lecture de la clé SuperHUD.state (contrat v1 avec sa session, 13/11/2026), clé
-- vivante seulement si elle change, blocs évités par les overlays en position automatique, sections cachées sans SuperHUD.
local SuperHUD=require('src/superhud')
local Config=require('src/config')
local Helpers=require('tests/helpers')
local check=Helpers.check
local T={}
local function state(over)
 local f={v='1',desk='1',sw='1920',sh='1080',radar='1',stamp='100',rects='20,280,300,200/1500,40,380,120'}
 for k,v in pairs(over or {}) do f[k]=v end
 return string.format('v=%s;desk=%s;sw=%s;sh=%s;radar=%s;stamp=%s;rects=%s',f.v,f.desk,f.sw,f.sh,f.radar,f.stamp,f.rects)
end
function T.superhud_state_contract_v1()
 local v=SuperHUD.parse(state())
 check(v and v.desk==1 and v.sw==1920 and v.sh==1080 and v.radar==true and v.stamp==100,'fields read')
 check(v and #v.rects==2 and v.rects[1].x==20 and v.rects[1].y==280 and v.rects[2].w==380 and v.rects[2].h==120,'rectangles read')
 check(SuperHUD.parse(state({v='2'}))==nil,'other version: ignored')
 check(#SuperHUD.parse(state({rects=''})).rects==0,'empty list')
 check(#SuperHUD.parse(state({rects='1,2,0,5/a,b,c,d/3,4,5,6'})).rects==1,'unreadable or empty rectangles skipped')
 check(SuperHUD.parse(state({radar='0'})).radar==false,'radar off')
 check(SuperHUD.parse(state()..';later=1')~=nil,'future fields accepted')
 check(SuperHUD.parse(('x'):rep(1001))==nil,'too long: ignored')
end
function T.superhud_alive_only_while_it_changes()
 local s=SuperHUD.new()
 local text=state()
 local function read() return text end
 SuperHUD.step(s,read,0)
 check(SuperHUD.get(s,0)==nil and not SuperHUD.radar(s,0),'text found at start: not trusted (SuperHUD may be unloaded)')
 text=state({stamp='101'}); SuperHUD.step(s,read,1)
 check(SuperHUD.radar(s,1),'changed under our eyes: alive, radar on')
 SuperHUD.step(s,read,3.5)
 check(SuperHUD.radar(s,3.5),'2.5 s without change: still alive')
 SuperHUD.step(s,read,4.6)
 check(not SuperHUD.radar(s,4.6) and SuperHUD.get(s,4.6)==nil,'3 s without change: stopped, side by side back to the spotter')
 text=state({stamp='105',radar='0',rects=''}); SuperHUD.step(s,read,5.2)
 check(SuperHUD.get(s,5.2)~=nil and not SuperHUD.radar(s,5.2),'unload write: radar off')
 check(not SuperHUD.radar(nil,0),'no state: no radar')
end
function T.superhud_blocks_avoided_in_automatic_position()
 local s=SuperHUD.new()
 local text=state({stamp='1'})
 local function read() return text end
 SuperHUD.step(s,read,0); text=state({stamp='2'}); SuperHUD.step(s,read,1)
 local b=SuperHUD.blocks(s,1,1,1920,1080)
 check(#b==2,'two blocks on desktop 1')
 check(#SuperHUD.blocks(s,1,2,1920,1080)==0,'other desktop: nothing to avoid')
 local s0=SuperHUD.new(); local t0=state({desk='0',stamp='1'}); local function r0() return t0 end
 SuperHUD.step(s0,r0,0); t0=state({desk='0',stamp='2'}); SuperHUD.step(s0,r0,1)
 check(#SuperHUD.blocks(s0,1,1,1920,1080)==0,'desk=0 (unreadable at SuperHUD): nothing to avoid')
 local half=SuperHUD.blocks(s,1,1,960,540)
 check(half[2].x==10 and half[2].y==140 and half[1].x==750 and half[1].y==20,'scaled to our screen size')
 -- Spotter en position automatique (29, 281) sous le bloc de gauche (20, 280, 300 x 200) : poussé juste dessous.
 local x,y=SuperHUD.avoid(29,281,380,240,b,1080)
 check(x==29 and y==488,'moved just below the block: '..x..','..y)
 x,y=SuperHUD.avoid(29,600,380,240,b,1080)
 check(x==29 and y==600,'free spot: unchanged')
 -- Bloc masqué un moment (radar sans voiture) : sa place reste gardée M.KEEP s.
 text=state({stamp='3',rects='1500,40,380,120'}); SuperHUD.step(s,read,2)
 check(#SuperHUD.blocks(s,2,1,1920,1080)==2,'hidden block kept: overlays do not jump')
 text=state({stamp='4',rects='1500,40,380,120'}); SuperHUD.step(s,read,1+SuperHUD.KEEP+1)
 check(#SuperHUD.blocks(s,1+SuperHUD.KEEP+1,1,1920,1080)==1,'forgotten after '..SuperHUD.KEEP..' s')
 -- Aucune place libre dans la colonne : position d'origine.
 local full={{x=0,y=0,w=1920,h=1080}}
 x,y=SuperHUD.avoid(29,281,380,240,full,1080)
 check(x==29 and y==281,'no free spot: unchanged')
end
function T.superhud_detection_and_hidden_sections()
 check(SuperHUD.installed('[ABOUT]\nNAME = SuperHUD\nVERSION = 1.9.5-fr\n[WINDOW_0]\nNAME = SuperHUD - Configuration FR\n'),'manifest detected')
 check(not SuperHUD.installed('[WINDOW_0]\nNAME = SuperHUD - Configuration FR\n'),'window name only: not SuperHUD')
 check(not SuperHUD.installed(nil),'no manifest')
 local function ids(tab,has) local out={} for _,sec in ipairs(Config.shownOf(tab,has)) do out[#out+1]=sec.id end return table.concat(out,',') end
 check(not ids('spotter',{}):find('superhud') and not ids('overlays',{}):find('superhud'),'hidden without SuperHUD')
 check(ids('spotter',{superhud=true}):find('superhudRadar')~=nil,'radar section with SuperHUD')
 check(ids('overlays',{superhud=true}):find('superhudAvoid')~=nil,'avoid section with SuperHUD')
 local d=Config.defaults()
 check(d.shRadar==true and d.shAvoid==true,'both on by default')
end
return T
