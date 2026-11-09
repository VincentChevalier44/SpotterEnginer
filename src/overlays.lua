-- Overlays en jeu : Spotter, Ingénieur, Stratégie. Comme ceux de SuperHUD et d'AdvancedIA : fenêtres transparentes
-- dessinées par l'app (rappel IN_GAME du manifeste), chacune à sa position et à son échelle, avec ses réglages :
-- affichée, verrouillée (clics traversants) ou déverrouillée (glisser pour déplacer, coin bas droit pour la taille,
-- clic droit pour verrouiller), fond opaque / atténué (38 %) / transparent, opacité du fond et du contenu, bande
-- décorative (couleur de l'état de course), en-tête. Thème Racing 26 aux couleurs de l'app (pervenche).
local W=require('src/kit')
local L=require('src/lang')
local U=require('src/util')
local Timing=require('src/timing')
local Position=require('src/position')
local Config=require('src/config')
local M={}
M.design={spotter=340,engineer=340,strategy=380}
M.handle=18
function M.new() local v={}; for _,o in ipairs(Config.overlays) do v[o]={h=64,x=0,y=0,wp=0,hp=0} end; return v end
-- Fond à l'opacité voulue : couleur du panneau du kit (gardée par palier de 1 %).
local backs={}
local function background(a)
 local k=math.floor(a*100+0.5); local b=backs[k]
 if not b then local p=W.colors().panel; b=rgbm(p.r,p.g,p.b,k/100); backs[k]=b end
 return b
end
-- Couleur de la bande décorative : état décidé par AdvancedIA (drapeau du joueur), pervenche de l'app sinon.
local function accent(app)
 local c=W.colors(); local d=app.link.d
 if not d or app.link.state~='connected' then return c.marker end
 if d.red then return c.flagRed end
 if d.neutral or d.zone or d.yellow then return c.flagYellow end
 local k=d.panelKind
 if k=='blue' or k=='nativeBlue' then return c.flagBlue end
 if d.finished then return c.flagWhite end
 return c.cyan
end
-- Haut du contenu selon l'en-tête.
local function top(app,o) return app.cfg[o..'Header'] and 36 or 10 end
-- Cadre : fond selon le mode, bande décorative, en-tête (titre et état).
local function frameBox(app,o,f,h,title,right)
 local cfg=app.cfg; local c=W.colors()
 local mode=cfg[o..'Background']
 local a=mode=='transparent' and 0 or cfg[o..'Opacity']*(mode=='ghost' and 0.38 or 1)
 if a>0.005 then W.panel(0,0,f.w,h,background(a),12) end
 if cfg[o..'Accent'] then W.rect(0,0,f.w-12,3,accent(app)) end
 if cfg[o..'Header'] then
  W.text(W.upper(title),12,8,17,c.text,'display')
  if right and right~='' then W.right(W.upper(right),f.w-14,11,11,c.label,'cond') end
 end
end
-- Messages récents de la radio pour un ou deux rôles.
local function radio(app,x,y,w,roles,lines,size)
 local c=W.colors(); local log=app.voice.log; local now=app.real
 local shown=0
 for k=#log,1,-1 do
  local e=log[k]
  if now-e.at>app.cfg.radioSeconds then break end
  if roles[e.role] then
   local col=e.role=='engineer' and c.warn or e.role=='race' and c.label or c.cyanText
   W.text(L.t.roles[e.role] or '',x,y+2,9,col,'label')
   W.cell(e.text,x+64,y,w-64,size,e.spoken and c.text or c.soft)
   y=y+size*1.45; shown=shown+1
   if shown>=lines then break end
  end
 end
 return y
end
-- AdvancedIA pas connecté (overlay visible seulement déverrouillé, pour le placer) : état de la liaison.
local function waiting(app,o,f,title)
 local t=top(app,o); local h=t+30
 frameBox(app,o,f,h,title,'')
 local Ui=require('src/ui')
 local text,kind=Ui.linkChip(app.link)
 W.dotChip(text,12,t,kind)
 return h
end
local function idle(app) return not app.cfg.enabled or app.link.state~='connected' end
M.draw={}
-- Morceaux du dessin, fonctions de module (aucune fermeture créée à chaque image).
local function sideBar(c,y,on,x,label,left)
 W.rect(x,y,70,48,on and c.warnBack or c.block)
 W.rect(x+(left and 66 or 0),y,4,48,on and c.warn or c.rule)
 local col=on and c.warn or c.group
 local tw=W.width(label,12,'cond')
 W.text(label,x+35-tw/2,y+16,12,col,'cond')
end
local function gapRow(app,f,c,ov,y,label,i,ahead)
 local F=app.F
 W.text(label,12,y+2,10,c.label,'label')
 if i and F.cars[i] and F.cars[i].valid then
  local car=F.cars[i]
  local g,laps
  if ahead then g,laps=Timing.gap(app.timing,i,F.player,app.now) else g,laps=Timing.gap(app.timing,F.player,i,app.now) end
  W.text(string.format('P%d',car.position),86,y,13,c.text,'mono')
  W.cell(car.name,124,y+1,f.w-124-80,12,c.body)
  local v=g and U.fixed(g,1,L.mark()) or laps and laps>0 and ('+'..laps..' '..ov.laps) or ov.none
  W.right(v,f.w-14,y,14,c.text,'mono')
 else W.text(ov.none,86,y,13,c.group,'mono') end
 return y+20
end
local function who(F,ov,mark,i,g) if i and i>=0 and F.cars[i] then return string.format('%s %s s',F.cars[i].name,U.fixed(g or 0,1,mark)) end return ov.none end
local function duel(c,ov,mark,y,label,on,gap,x)
 W.text(label,x,y+2,10,c.label,'label')
 local col=on and c.ok or c.group
 W.text((on and ov.possible or ov.no)..(gap and (' '..U.gap(gap,1,mark)) or ''),x+70,y,11,col,'mono')
end
-- Spotter : côte à côte, écarts devant et derrière, radio du spotter et de la direction de course.
function M.draw.spotter(app,f,o)
 local ov=L.t.ov; local c=W.colors()
 if idle(app) then return waiting(app,o,f,L.t.roles.spotter) end
 local F=app.F; local me=F.cars[F.player]
 local lines=app.cfg.radioLines
 local t0=top(app,o)
 local h=t0+4+58+46+lines*15+10
 local d=app.link.d
 local state=d and d.neutral and (d.neutralMode=='sc' and 'SC' or d.neutralMode=='vsc' and 'VSC' or d.neutralMode=='fcy' and 'FCY' or ov.neutral) or (d and d.panelTitle or '')
 frameBox(app,o,f,h,L.t.roles.spotter,state)
 -- Côte à côte : voiture du joueur au centre, côtés allumés quand une voiture est à côté.
 local p=app.spotter.prox
 local cx=f.w*0.5; local y=t0+4
 W.rect(cx-9,y+4,18,40,c.text,3)
 sideBar(c,y,p.left,cx-96,ov.left,true); sideBar(c,y,p.right,cx+26,ov.right,false)
 if not p.left and not p.right then local tw=W.width(ov.clear,10,'label'); W.text(ov.clear,cx-tw/2,y+50,10,c.group,'label') end
 y=y+62
 -- Écarts (en direct) avec les voisins au classement.
 local ahead,behind=nil,nil
 if me then ahead,behind=Position.neighbours(F,me) end
 if F.isRace then y=gapRow(app,f,c,ov,y,ov.ahead,ahead,true); y=gapRow(app,f,c,ov,y,ov.behind,behind,false) else y=y+40 end
 y=y+6
 W.rect(12,y,f.w-24,1,c.rule); y=y+6
 radio(app,12,y,f.w-24,{spotter=true,race=true},lines,12)
 return h
end
-- Ingénieur : carburant, pneus, freins, rythme, radio de l'ingénieur.
local function tyreColor(t)
 local c=W.colors()
 if t.core<=0 then return c.group end
 local d=t.core-t.opt
 if d<-15 then return c.flagBlue elseif d>20 then return c.danger elseif d>10 then return c.warn end
 return c.ok
end
function M.draw.engineer(app,f,o)
 local ov=L.t.ov; local c=W.colors()
 if idle(app) then return waiting(app,o,f,L.t.roles.engineer) end
 local F=app.F; local me=F.cars[F.player]; local t=app.engineer.strategist; local plan=t.plan
 local lines=app.cfg.radioLines
 local t0=top(app,o)
 local h=t0+2+40+92+44+lines*15+12
 frameBox(app,o,f,h,L.t.roles.engineer,me and string.format('%s %d',ov.lap,me.laps+1) or '')
 local y=t0+2
 -- Carburant
 local fpl=t.data.fuelPerLap or (F.me.fuelPerLapAC>0 and F.me.fuelPerLapAC) or nil
 W.text(ov.fuel,12,y+2,10,c.label,'label')
 W.text(string.format('%s L',U.fixed(F.me.fuel,1,L.mark())),86,y,14,c.text,'mono')
 if fpl and fpl>0 then
  local laps=F.me.fuel/fpl
  W.right(string.format(ov.fuelLaps,U.fixed(laps,1,L.mark())),f.w-14,y,13,c.text,'mono')
  -- Deuxième ligne : consommation, marge à l'arrêt prévu ou à l'arrivée.
  W.text(string.format('%s L%s',U.fixed(fpl,2,L.mark()),ov.perLap),86,y+20,11,c.muted,'mono')
  if plan and plan.ok then
   local spare=plan.fuelSpare/fpl
   local col=spare<-0.2 and c.danger or spare<0.5 and c.warn or c.ok
   W.right(string.format('%s %s %s',spare>=0 and ov.spare or ov.short,U.gap(spare,1,L.mark()),plan.optimal and ov.toStop or ov.toEnd),f.w-14,y+20,11,col,'mono')
  end
 end
 y=y+42
 -- Pneus : AVG AVD / ARG ARD, cœur et km virtuels ; freins dessous.
 W.text(ov.tyres,12,y+2,10,c.label,'label')
 local bw=(f.w-100)/2
 for k=1,4 do
  local tt=F.me.tyres[k]
  local col=(k-1)%2; local rw=math.floor((k-1)/2)
  local bx=86+col*(bw+6); local by=y+rw*30
  W.rect(bx,by,bw,26,c.block)
  W.rect(bx,by,3,26,tyreColor(tt))
  W.text(string.format('%d°',math.floor(tt.core+0.5)),bx+8,by+5,13,c.text,'mono')
  W.right(string.format('%s km',U.fixed(tt.vkm,1,L.mark())),bx+bw-6,by+7,10,c.muted,'mono')
 end
 y=y+62
 local b=F.me.brakes
 W.text(ov.brakes,12,y+2,10,c.label,'label')
 if b[1]>0 or b[3]>0 then
  W.text(string.format('%d° %d°  ·  %d° %d°',b[1],b[2],b[3],b[4]),86,y,12,math.max(b[1],b[2],b[3],b[4])>app.cfg.brakeHot and c.warn or c.text,'mono')
 else W.text(ov.none,86,y,12,c.group,'mono') end
 y=y+26
 -- Rythme : dernier tour, cible du modèle.
 local last=me and me.lastMs/1000 or 0
 W.text(ov.last,12,y+2,10,c.label,'label')
 W.text(U.lapTime(last,L.mark()),86,y,13,c.text,'mono')
 if t.targetPrev or plan and plan.ok then
  local target=plan and plan.ok and plan.target or t.targetPrev
  W.text(ov.target,190,y+2,10,c.label,'label')
  W.right(U.lapTime(target,L.mark()),f.w-14,y,13,c.cyanText,'mono')
 end
 y=y+24
 W.rect(12,y,f.w-24,1,c.rule); y=y+6
 radio(app,12,y,f.w-24,{engineer=true},lines,12)
 return h
end
-- Stratégie : fenêtre, tour optimal, dégradation, ressortie, duels, coût selon le tour d'arrêt.
function M.draw.strategy(app,f,o)
 local ov=L.t.ov; local c=W.colors()
 if idle(app) then return waiting(app,o,f,L.t.home.strategy) end
 local F=app.F; local t=app.engineer.strategist; local plan=t.plan
 local status=t.status=='measured' and ov.measured or ov.estimated
 local t0=top(app,o)
 if not F.isRace then local h=t0+28; frameBox(app,o,f,h,L.t.home.strategy,''); W.text(ov.noRace,12,t0+2,12,c.muted); return h end
 if not plan or not plan.ok then
  local h=t0+28
  frameBox(app,o,f,h,L.t.home.strategy,status)
  W.text(plan and (ov.reasons[plan.reason] or plan.reason) or string.format(ov.learning,#t.data.clean),12,t0+2,13,c.muted)
  return h
 end
 local h=t0+284
 frameBox(app,o,f,h,L.t.home.strategy,status)
 local y=t0+2
 -- Fenêtre et tour optimal.
 if plan.optimal then
  W.text(ov.window,12,y+6,11,c.label,'label')
  W.text(U.lapRange(plan.window[1],plan.window[2]),86,y,22,c.text,'display')
  W.text(ov.optimal,230,y+6,11,c.label,'label')
  -- Tour optimal grisé tant que le plan n'est pas prêt (estimations des premiers tours, jamais annoncé).
  W.right(string.format('T%d',plan.optimal),f.w-14,y-2,26,t.ready and c.cyan or c.muted,'display')
 else W.text(ov.noStop,12,y+2,16,c.ok,'cond') end
 y=y+34
 local lapsLeft=plan.total-plan.done
 W.text(string.format('%s %d  ·  %s %d/%d  ·  %s',ov.stops,plan.stops,ov.lap,plan.done+1,plan.total,string.format(ov.stintAge,t.data.tyreAge)),12,y,11,c.muted,'mono')
 y=y+18
 -- Températures qui pèsent sur l'usure (piste et air) et leur tendance projetée.
 W.text(string.format('%s %d°  ·  %s %d°  ·  %s °/min',ov.trackT,math.floor(F.road+0.5),ov.airT,math.floor(F.ambient+0.5),U.gap(t.data.roadTrend,1,L.mark())),12,y,11,c.label,'mono')
 y=y+20
 -- Dégradation et adhérence : maintenant et au tour d'arrêt.
 local mark=L.mark()
 W.text(ov.deg,12,y+2,10,c.label,'label')
 W.text(string.format('%s → %s s%s',U.fixed(plan.degNow or 0,2,mark),U.fixed(plan.degAtStop or 0,2,mark),ov.perLap),110,y,12,c.text,'mono')
 y=y+18
 if plan.gripNow then
  W.text(ov.grip,12,y+2,10,c.label,'label')
  W.text(string.format('%s %% → %s %%',U.fixed(plan.gripNow,1,mark),U.fixed(plan.gripAtStop or plan.gripNow,1,mark)),110,y,12,c.text,'mono')
 end
 y=y+18
 W.text(ov.pitLoss,12,y+2,10,c.label,'label')
 W.text(string.format('%s s',U.fixed(t.loss or 0,1,mark)),110,y,12,c.text,'mono')
 W.text(ov.fuel,200,y+2,10,c.label,'label')
 W.right(string.format('%s L',U.gap(plan.fuelSpare or 0,1,mark)),f.w-14,y,12,(plan.fuelSpare or 0)<0 and c.danger or c.text,'mono')
 y=y+20
 -- Ressortie prévue au tour optimal.
 local r=t.rejoin
 W.text(ov.rejoin,12,y+2,10,c.label,'label')
 if r then
  W.text(string.format(ov.position,r.position),110,y,13,c.cyanText,'mono')
  W.cell(ov.aheadShort..' '..who(F,ov,mark,r.ahead,r.aheadGap)..'  ·  '..ov.behindShort..' '..who(F,ov,mark,r.behind,r.behindGap),150,y+1,f.w-164,11,c.body)
 else W.text(ov.none,110,y,12,c.group,'mono') end
 y=y+20
 -- Duels.
 local du=t.duel
 duel(c,ov,mark,y,ov.undercut,du and du.undercut,du and du.undercutGap,12)
 duel(c,ov,mark,y,ov.overcut,du and du.overcut,du and du.overcutGap,200)
 y=y+18
 if du and du.threat then W.text(ov.threat..' · '..ov.undercut,12,y,11,c.warn,'cond') end
 y=y+20
 -- Coût de chaque tour d'arrêt (au plus 24 tours autour de l'optimum) : plus la barre est basse, meilleur est le tour.
 W.text(ov.costChart,12,y,10,c.label,'label'); y=y+16
 if plan.optimal and plan.cost then
  local n0=plan.optimal-plan.done
  local from=math.max(1,n0-12); local to=math.min(lapsLeft-1,n0+11)
  local count=math.max(1,to-from+1)
  local bwid=(f.w-24)/count
  local span=math.max(1,(app.cfg.tolerance or 2)*4)
  for n=from,to do
   local cost=plan.costs[n]
   local bx=12+(n-from)*bwid
   if cost then
    local rel=U.clamp((cost-plan.cost)/span,0,1)
    local bh=6+rel*40
    local inWindow=plan.done+n>=plan.window[1] and plan.done+n<=plan.window[2]
    local col=n==n0 and c.cyan or inWindow and c.cyanActive or c.rule
    W.rect(bx+1,y+46-bh,bwid-2,bh,col)
   end
  end
  W.text(string.format('T%d',plan.done+from),12,y+50,9,c.group,'mono')
  W.right(string.format('T%d',plan.done+to),f.w-12,y+50,9,c.group,'mono')
 end
 return h
end
-- Déverrouillé : glisser pour déplacer, coin bas droit pour la taille, clic droit pour verrouiller (cadre et poignée
-- à l'accent). Verrouillé sans clics traversants : clic droit pour déverrouiller.
local function edit(v,app,o,f)
 local st=v[o]; local cfg=app.cfg; local c=W.colors()
 local w,h=f.w,st.h; local hs=M.handle
 if not cfg[o..'Locked'] then
  local _,_,a1,r1=W.hit('mv1_'..o,0,0,w,math.max(1,h-hs))
  local _,_,a2,r2=W.hit('mv2_'..o,0,math.max(0,h-hs),math.max(1,w-hs),hs)
  local _,_,a3,r3=W.hit('rs_'..o,math.max(0,w-hs),math.max(0,h-hs),hs,hs)
  if (a1 or a2 or a3) and ui.mouseDelta then
   -- Valeurs non arrondies gardées pendant le geste : un glissé lent (moins d'un pas par image) avance quand même ;
   -- seule la valeur enregistrée est arrondie au pas du réglage.
   if not st.drag then st.drag={x=st.x,y=st.y,scale=cfg[o..'Scale']} end
   local g=st.drag
   local d=ui.mouseDelta()
   if d and (d.x~=0 or d.y~=0) then
    if a3 then
     local k=math.abs(d.x)>=math.abs(d.y) and d.x/math.max(1,st.wp) or d.y/math.max(1,st.hp)
     local bounds=Config.index[o..'Scale']
     g.scale=math.max(bounds[3],math.min(bounds[4],g.scale*(1+k)))
     app.set(o..'Scale',g.scale); app.set(o..'X',math.floor(st.x)); app.set(o..'Y',math.floor(st.y))
    else
     -- Bornée à l'écran : au-delà du bord, revenir en arrière répond aussitôt (pas de zone morte).
     local sc=app.screen and app.screen()
     g.x=U.clamp(g.x+d.x,0,math.max(0,(sc and sc.x or Config.screenDefault.x)-st.wp)); g.y=U.clamp(g.y+d.y,0,math.max(0,(sc and sc.y or Config.screenDefault.y)-st.hp))
     app.set(o..'X',math.floor(g.x+0.5)); app.set(o..'Y',math.floor(g.y+0.5))
    end
   end
  else st.drag=nil end
  if r1 or r2 or r3 then app.set(o..'Locked',true) end
  W.frameRect(0,0,w,h,c.cyan,1.5)
  W.tri(w,h-hs,w,h,w-hs,h,c.cyan)
  W.right(W.upper(L.t.ov.unlocked),w-hs-4,h-hs+3,10,c.cyan,'cond')
 elseif not cfg.clickThrough then
  local _,_,_,r=W.hit('lk_'..o,0,0,w,h)
  if r then app.set(o..'Locked',false) end
 end
end
local function content(v,app,o)
 local f=W.beginOverlay('spe_'..o,M.design[o])
 W.useAlpha(app.cfg[o..'Content'])
 local ok,h=pcall(M.draw[o],app,f,o)
 if ok and type(h)=='number' then v[o].h=h end
 W.useAlpha(1)
 local ok2,err2=pcall(edit,v,app,o,f)
 W.finish()
 -- Erreur gardée et relancée après la boucle (M.hud) : un overlay en erreur ne masque pas les autres.
 if not ok then v.err=v.err or h elseif not ok2 then v.err=v.err or err2 end
end
-- Positions automatiques (réglage X ou Y à -1) : spotter et ingénieur à gauche l'un sous l'autre, stratégie à droite.
local function defaultPos(o,sw,sh,w,v)
 if o=='spotter' then return sw*0.015,sh*0.26 end
 if o=='engineer' then return sw*0.015,sh*0.26+(v.spotter.hp>0 and v.spotter.hp or 240)+12 end
 return sw-w-sw*0.015,sh*0.26
end
-- Rappel IN_GAME : chaque overlay affiché dans sa fenêtre transparente. Masqués : app coupée, overlays coupés
-- (Ctrl+Alt+J), rediffusion, voie des stands (réglages), AdvancedIA pas connecté ; toujours visibles déverrouillés.
-- Noms des réglages de chaque overlay et identifiants de fenêtre par bureau : faits une fois.
local K={}
for _,o in ipairs(Config.overlays) do K[o]={show=o..'Show',locked=o..'Locked',scale=o..'Scale',x=o..'X',y=o..'Y',ids={}} end
local function windowId(o,d) local ids=K[o].ids; local id=ids[d]; if not id then id='SpotterEnginer_d'..d..'_'..o; ids[d]=id end; return id end
function M.hud(v,app)
 if not (type(ui.transparentWindow)=='function' or type(ui.transparentWindow)=='cdata') then return end
 v.err=nil
 local cfg=app.cfg; local F=app.F; local me=F.cars and F.cars[F.player]
 local hidden=not cfg.enabled or not cfg.overlaysOn or cfg.hideReplay and F.replay or cfg.hidePits and me and me.valid and me.pitlane
 local connected=app.link.state=='connected'
 local screen=app.screen and app.screen() or nil
 local sw=screen and screen.x or Config.screenDefault.x; local sh=screen and screen.y or Config.screenDefault.y
 for _,o in ipairs(Config.overlays) do
  local st=v[o]; local k=K[o]
  local unlocked=not cfg[k.locked]
  if cfg[k.show] and (unlocked or not hidden and connected) then
   local s=cfg[k.scale]; local w=M.design[o]*s; local h=math.max(30,st.h)*s
   local dx,dy=defaultPos(o,sw,sh,w,v)
   local x=cfg[k.x]>=0 and cfg[k.x] or dx
   local y=cfg[k.y]>=0 and cfg[k.y] or dy
   x=U.clamp(x,0,math.max(0,sw-w)); y=U.clamp(y,0,math.max(0,sh-h))
   st.x,st.y,st.wp,st.hp=x,y,w,h
   if st.pos then st.pos.x=x; st.pos.y=y; st.size.x=w; st.size.y=h else st.pos=vec2(x,y); st.size=vec2(w,h) end
   if not st.draw then st.draw=function() content(v,app,o) end end
   ui.transparentWindow(windowId(o,app.desktop or 1),st.pos,st.size,true,unlocked or not cfg.clickThrough,st.draw)
  end
 end
 if v.err then local e=v.err; v.err=nil; error(e,0) end
end
return M
