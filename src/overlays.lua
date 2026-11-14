-- Overlays en jeu : Spotter, Ingénieur, Stratégie. Comme ceux de SuperHUD et d'AdvancedIA : fenêtres transparentes
-- dessinées par l'app (rappel IN_GAME du manifeste), chacune à sa position et à son échelle, avec ses réglages :
-- affichée, verrouillée (clics traversants) ou déverrouillée (glisser pour déplacer, coin bas droit pour la taille,
-- clic droit pour verrouiller), fond opaque / atténué (38 %) / transparent, opacité du fond et du contenu, bande
-- décorative (couleur de l'état de course), en-tête. Thème Racing 26 aux couleurs de l'app (pervenche).
-- 1.3.9 (demande du pilote : « le même que SuperHUD ») : panneau au coin haut droit coupé, barre d'accent à gauche,
-- petit titre et état à droite sur un filet ; poignée de taille à deux traits, taille de 0,35 à 4 fois, poignées en
-- pixels d'écran ; Ingénieur et Stratégie de la voiture suivie par la caméra (src/focus.lua, réglage followCamera).
local W=require('src/kit')
local L=require('src/lang')
local U=require('src/util')
local Timing=require('src/timing')
local Engineer=require('src/engineer')
local Position=require('src/position')
local Config=require('src/config')
local SuperHUD=require('src/superhud')
local Focus=require('src/focus')
local Layout=require('src/bridge_layout')
local Link=require('src/link')
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
local function top(app,o) return app.cfg[o..'Header'] and 38 or 10 end
-- Cadre (Racing 26, comme les blocs de SuperHUD) : panneau au coin haut droit coupé, barre d'accent de 3 px à gauche
-- (couleur de l'état de course), en-tête : petit titre, étiquette (CAMÉRA : voiture suivie) puis état à droite, filet.
local function frameBox(app,o,f,h,title,right,tag)
 local cfg=app.cfg; local c=W.colors()
 local mode=cfg[o..'Background']
 local a=mode=='transparent' and 0 or cfg[o..'Opacity']*(mode=='ghost' and 0.38 or 1)
 if a>0.005 then W.panel(0,0,f.w,h,background(a),10) end
 if cfg[o..'Accent'] then W.rect(0,0,3,h,accent(app)) end
 if cfg[o..'Header'] then
  local x=14
  local tw=W.width(W.upper(title),13,'cond')
  local room=f.w-14-x-(right and right~='' and 96 or 0)-(tag and 70 or 0)
  W.cell(W.upper(title),x,9,room,13,tag and c.text or c.label,'cond')
  x=x+math.min(tw,room)+8
  if tag then
   local gw=W.width(tag,9,'label')+10
   W.rect(x,10,gw,15,c.cyan,2); W.text(tag,x+5,12,9,c.ink,'label')
  end
  if right and right~='' then W.right(W.upper(right),f.w-14,10,11,c.cyanText,'cond') end
  W.rect(14,30,f.w-28,1,c.rule)
 end
end
-- Textes chiffrés des overlays, refaits seulement quand la valeur affichée change (aucune chaîne neuve par image) :
-- une case par identifiant (les nombres ont les leurs : un même identifiant sert au nombre et au texte qui le porte).
-- num : nombre à dec décimales, signé ou non (comme U.fixed et U.gap) ; text : format et jusqu'à six valeurs ;
-- lapText : temps au tour ; range : plage de tours.
local slots,numbers={},{}
local function slot(id) local m=slots[id]; if not m then m={}; slots[id]=m end; return m end
local SCALE={[0]=1,10,100,1000}
local function num(id,v,dec,mark,signed)
 if not U.finite(v) then return '--' end
 local m=numbers[id]; if not m then m={}; numbers[id]=m end
 local k=math.floor(v*SCALE[dec]+0.5)
 if m.k~=k or m.mark~=mark then m.k=k; m.mark=mark; m.s=(signed and U.gap or U.fixed)(k/SCALE[dec],dec,mark) end
 return m.s
end
local function text(id,fmt,a,b,c,d,e,g)
 local m=slot(id)
 if m.a~=a or m.b~=b or m.c~=c or m.d~=d or m.e~=e or m.g~=g or m.f~=fmt then
  m.a,m.b,m.c,m.d,m.e,m.g,m.f=a,b,c,d,e,g,fmt; m.s=string.format(fmt,a,b,c,d,e,g)
 end
 return m.s
end
local function lapText(id,s,mark)
 local m=slot(id)
 if m.a~=s or m.mark~=mark then m.a=s; m.mark=mark; m.s=U.lapTime(s,mark) end
 return m.s
end
local function range(id,a,b)
 local m=slot(id)
 if m.a~=a or m.b~=b then m.a=a; m.b=b; m.s=U.lapRange(a,b) end
 return m.s
end
-- Rôles montrés sur la radio de chaque overlay.
local SPOTTER_ROLES={spotter=true,race=true}
local ENGINEER_ROLES={engineer=true}
-- Messages récents de la radio pour un ou deux rôles (âge sur l'horloge de la radio : figé en pause).
local function radio(app,x,y,w,roles,lines,size)
 local c=W.colors(); local log=app.voice.log; local now=app.radioNow or app.real
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
 local state,kind=require('src/ui').linkChip(app.link)
 W.dotChip(state,12,t,kind)
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
  W.text(text(ahead and 'gapAp' or 'gapBp','P%d',car.position),86,y,13,c.text,'mono')
  W.cell(car.name,124,y+1,f.w-124-80,12,c.body)
  local v=g and num(ahead and 'gapA' or 'gapB',g,1,L.mark()) or laps and laps>0 and text(ahead and 'gapAl' or 'gapBl','+%s %s',laps,ov.laps) or ov.none
  W.right(v,f.w-14,y,14,c.text,'mono')
 else W.text(ov.none,86,y,13,c.group,'mono') end
 return y+20
end
local function who(id,F,ov,mark,i,g) if i and i>=0 and F.cars[i] then return text(id,'%s %s s',F.cars[i].name,num(id,g or 0,1,mark)) end return ov.none end
-- Duel : possible (vert) ou non, avec la marge sur le rival après les arrêts ; « — » sans rival à moins de 6 s, ou trop
-- près de l'arrivée (rien n'est calculé).
local function duel(id,c,ov,mark,y,label,on,gap,x)
 W.text(label,x,y+2,10,c.label,'label')
 if gap==nil then W.text(ov.none,x+70,y,11,c.group,'mono'); return end
 local col=on and c.ok or c.group
 W.text(text(id,'%s %s',on and ov.possible or ov.no,num(id,gap,1,mark,true)),x+70,y,11,col,'mono')
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
 radio(app,12,y,f.w-24,SPOTTER_ROLES,lines,12)
 return h
end
-- Ingénieur : carburant, pneus, freins, rythme, radio de l'ingénieur.
-- Couleur d'un pneu, aux seuils de la radio (1.3.1, réglages Pneus froids / chauds : le cœur, et la surface au-delà de
-- 1,6 fois le seuil chaud) : bleu froid, orange chaud, rouge très chaud (deux fois le seuil), vert dans la fenêtre.
local TYRE_T={'tyreT1','tyreT2','tyreT3','tyreT4'}
local TYRE_KM={'tyreK1','tyreK2','tyreK3','tyreK4'}
local function tyreColor(t,cfg)
 local c=W.colors()
 if t.core<=0 then return c.group end
 local cold,hot=cfg.tyreCold or 15,cfg.tyreHot or 12
 local surface=((t.inner or t.core)+(t.mid or t.core)+(t.outer or t.core))/3
 local over=math.max(t.core-t.opt-hot,surface-t.opt-hot*1.6)
 if t.core<t.opt-cold then return c.flagBlue elseif over>hot then return c.danger elseif over>0 then return c.warn end
 return c.ok
end
-- Vie d'un pneu (comme SuperHUD : 1 - usure d'AC), en %, ou nil.
local function life(t) local wv=t.wear; if type(wv)=='number' and wv>=0 and wv<=1 then return (1-wv)*100 end return nil end
-- Défaut d'un pneu, le plus grave d'abord (texte court, couleur), ou nil.
local function defect(t,ov,c)
 if t.blown then return ov.blown,c.danger end
 if (t.flat or 0)>0.3 then return ov.flat,c.warn end
 if (t.blister or 0)>0.3 then return ov.blister,c.warn end
 if (t.grain or 0)>0.3 then return ov.grain,c.warn end
 return nil
end
local LIFE={'tyreL1','tyreL2','tyreL3','tyreL4'}
-- Hauteur du dernier dessin des overlays à contenu variable (cadre dessiné avant le contenu).
local heights={}
local IMO={'tyreS1','tyreS2','tyreS3','tyreS4'}
-- Ingénieur (1.3.9) : voiture affichée (la vôtre, ou celle que suit la caméra) : carburant, pneus (cœur, surface,
-- vie, km, défauts), âge du train ou relais, freins, dégâts, rythme (dernier, cible, moyenne des 3, meilleur),
-- radio de l'ingénieur (toujours la vôtre).
function M.draw.engineer(app,f,o)
 local ov=L.t.ov; local c=W.colors()
 if idle(app) then return waiting(app,o,f,L.t.roles.engineer) end
 local F=app.F; local t=app.engineer.strategist; local plan=t.plan
 local sub=Focus.subject(app.focus,F)
 local car=sub.car; local data=sub.data; local own=sub.own
 local lines=app.cfg.radioLines
 local t0=top(app,o)
 local y=t0+2; local mark=L.mark()
 -- Hauteur : celle du dessin précédent (le contenu varie : dégâts, données partielles), refaite à la fin.
 local h=heights.engineer or (t0+2+42+92+26+44+lines*15+12)
 frameBox(app,o,f,h,own and L.t.roles.engineer or (car and car.name or ''),car and text('eLap','%s %d',ov.lap,car.laps+1) or '',not own and ov.camera or nil)
 if sub.partial then
  W.text(ov.partial,12,y+2,12,c.muted); y=y+26
 else
  -- Carburant : le calcul de la radio pour la vôtre (Engineer.fuelStatus : marge déduite, jusqu'au « box » engagé ou à
  -- l'arrêt du plan prêt, sinon à l'arrivée) ; pour une autre voiture, sa consommation mesurée tour après tour.
  W.text(ov.fuel,12,y+2,10,c.label,'label')
  W.text(text('eFuel','%s L',num('eFuel',data.fuel,1,mark)),86,y,14,c.text,'mono')
  if own then
   local fs=Engineer.fuelStatus(app.engineer,F,app.cfg)
   if fs then
    W.right(text('eLaps',ov.fuelLaps,num('eLaps',fs.laps,1,mark)),f.w-14,y,13,c.text,'mono')
    W.text(text('eFpl','%s L%s',num('eFpl',fs.fpl,2,mark),ov.perLap),86,y+20,11,c.muted,'mono')
    if fs.delta then
     local col=fs.delta<-0.2 and c.danger or fs.delta<0.5 and c.warn or c.ok
     W.right(text('eSpare','%s %s %s',fs.delta>=0 and ov.spare or ov.short,num('eSpare',fs.delta,1,mark,true),fs.toStop and ov.toStop or ov.toEnd),f.w-14,y+20,11,col,'mono')
    end
   end
  else
   local fpl=sub.fpl
   if fpl then
    W.right(text('eLaps',ov.fuelLaps,num('eLaps',data.fuel/fpl,1,mark)),f.w-14,y,13,c.text,'mono')
    W.text(text('eFpl','%s L%s',num('eFpl',fpl,2,mark),ov.perLap),86,y+20,11,c.muted,'mono')
   else W.text(ov.measuring,86,y+20,11,c.muted,'mono') end
  end
  y=y+42
  -- Pneus : AVG AVD / ARG ARD ; cœur, vie, surface intérieur · milieu · extérieur (ou le défaut), km virtuels.
  W.text(ov.tyres,12,y+2,10,c.label,'label')
  if own then W.text(text('eAge',ov.ageShort,t.data.tyreAge or 0),12,y+18,9,c.muted,'mono')
  else W.text(text('eAge',ov.ageShort,sub.stint),12,y+18,9,c.muted,'mono') end
  local bw=(f.w-100)/2
  for k=1,4 do
   local tt=data.tyres[k]
   local col=(k-1)%2; local rw=math.floor((k-1)/2)
   local bx=86+col*(bw+6); local by=y+rw*44
   W.rect(bx,by,bw,40,c.block)
   W.rect(bx,by,3,40,tyreColor(tt,app.cfg))
   W.text(text(TYRE_T[k],'%d°',math.floor((tt.core or 0)+0.5)),bx+8,by+4,14,c.text,'mono')
   local lv=life(tt)
   if lv then W.right(text(LIFE[k],'%d %%',math.floor(lv+0.5)),bx+bw-6,by+5,11,lv<35 and c.danger or lv<60 and c.warn or c.ok,'mono') end
   local dtext,dcol=defect(tt,ov,c)
   if dtext then W.text(dtext,bx+8,by+24,9,dcol,'label')
   else W.text(text(IMO[k],'%d · %d · %d',math.floor((tt.inner or 0)+0.5),math.floor((tt.mid or 0)+0.5),math.floor((tt.outer or 0)+0.5)),bx+8,by+24,9,c.muted,'mono') end
   W.right(text(TYRE_KM[k],'%s km',num(TYRE_KM[k],tt.vkm or 0,1,mark)),bx+bw-6,by+25,9,c.muted,'mono')
  end
  y=y+92
  local b=data.brakes
  W.text(ov.brakes,12,y+2,10,c.label,'label')
  if b[1]>0 or b[3]>0 then
   W.text(text('eBrakes','%d° %d°  ·  %d° %d°',math.floor(b[1]),math.floor(b[2]),math.floor(b[3]),math.floor(b[4])),86,y,12,math.max(b[1],b[2],b[3],b[4])>app.cfg.brakeHot and c.warn or c.text,'mono')
  else W.text(ov.none,86,y,12,c.group,'mono') end
  y=y+24
  -- Dégâts : seulement s'il y en a (avant, arrière, gauche, droite).
  local dm=data.damage
  if dm and math.max(dm[1] or 0,dm[2] or 0,dm[3] or 0,dm[4] or 0)>0.5 then
   W.text(ov.damage,12,y+2,10,c.label,'label')
   W.text(text('eDamage',ov.damageFmt,math.floor(dm[1]+0.5),math.floor(dm[2]+0.5),math.floor(dm[3]+0.5),math.floor(dm[4]+0.5)),86,y,12,c.warn,'mono')
   y=y+22
  end
 end
 -- Rythme : dernier tour (rouge s'il n'était pas normal, pour la vôtre), écart à la cible du modèle (la vôtre) ;
 -- moyenne des trois derniers tours de course et meilleur tour.
 local last=car and car.lastMs/1000 or 0
 local normal=own and car and Engineer.normalLap(t,car)
 W.text(ov.last,12,y+2,10,c.label,'label')
 W.text(lapText('eLast',last,mark),86,y,13,(own and last>0 and not normal) and c.danger or c.text,'mono')
 if own and t.targetPrev and last>0 and normal then
  local dl=last-t.targetPrev
  W.text(num('eDelta',dl,1,mark,true),158,y+1,12,dl<=0.05 and c.ok or dl<0.5 and c.warn or c.danger,'mono')
 end
 if own and plan and plan.ok and plan.target then
  W.text(ov.target,214,y+2,10,c.label,'label')
  W.right(lapText('eTarget',plan.target,mark),f.w-14,y,13,t.ready and c.cyanText or c.muted,'mono')
 end
 y=y+20
 W.text(ov.avg3,12,y+2,10,c.label,'label')
 W.text(sub.avg3 and lapText('eAvg',sub.avg3,mark) or ov.none,86,y,12,sub.avg3 and c.text or c.group,'mono')
 W.text(ov.best,214,y+2,10,c.label,'label')
 local best=car and car.bestMs/1000 or 0
 W.right(best>0 and lapText('eBest',best,mark) or ov.none,f.w-14,y,12,best>0 and c.record or c.group,'mono')
 y=y+22
 W.rect(12,y,f.w-24,1,c.rule); y=y+6
 y=radio(app,12,y,f.w-24,ENGINEER_ROLES,lines,12)
 h=math.max(y,t0+2+42+92+24+42+6+lines*15)+10
 heights.engineer=h
 return h
end
-- Stratégie : fenêtre, tour optimal, dégradation, ressortie, duels, coût selon le tour d'arrêt.
-- Stratégie d'une autre voiture (caméra) : le plan qu'AdvancedIA publie pour elle au pont (arrêts prévus et faits,
-- prochain arrêt, raison, limite, panne, appel aux stands, relais), jamais celui de votre ingénieur.
local function otherStrategy(app,f,o,sub)
 local ov=L.t.ov; local c=W.colors()
 local t0=top(app,o); local car=sub.car
 local lc=Link.car(app.link,sub.index)
 local h=heights.other or t0+150
 frameBox(app,o,f,h,car and car.name or '',ov.aiPlan,ov.camera)
 local y=t0+2
 if not lc then W.text(ov.noPlan,12,y+2,12,c.muted); h=t0+30; heights.other=h; return h end
 -- Pont v2 (AdvancedIA 1.64) : IA abandonnée (dépannée, garée jusqu'à la fin) : seulement l'abandon.
 if lc.retired then
  W.rect(10,y-2,f.w-20,26,c.block)
  local tw=W.width(ov.retired,18,'display'); W.text(ov.retired,(f.w-tw)/2,y,18,c.danger,'display')
  h=y+34; heights.other=h; return h
 end
 if lc.called or lc.boxed then
  W.rect(10,y-2,f.w-20,26,c.block)
  local label=lc.boxed and ov.inPit or ov.called
  local tw=W.width(label,18,'display'); W.text(label,(f.w-tw)/2,y,18,c.warn,'display')
  y=y+30
 end
 W.text(ov.stops,12,y+2,10,c.label,'label')
 -- -1 publié pour une valeur inconnue : jamais affiché.
 if (lc.plannedStops or -1)>=0 then W.text(text('oStops',ov.stopsFmt,math.max(0,lc.stops or 0),lc.plannedStops),110,y,13,c.text,'mono')
 else W.text(text('oStops1',ov.stopsMade,math.max(0,lc.stops or 0)),110,y,13,c.text,'mono') end
 y=y+20
 W.text(ov.nextStop,12,y+2,10,c.label,'label')
 if lc.planned and lc.nextStopLap>0 then
  W.text(text('oNext','T%d',lc.nextStopLap),110,y-2,20,c.cyan,'display')
  local laps=car and lc.nextStopLap-(car.laps+1) or nil
  if laps and laps>=0 then W.right(text('oIn',ov.inLaps,laps),f.w-14,y,11,c.muted,'mono') end
 else W.text(ov.none,110,y,13,c.group,'mono') end
 y=y+24
 local cause=Layout.causes[lc.stopCause or 0] or ''
 W.text(ov.cause,12,y+2,10,c.label,'label')
 W.text(cause~='' and (ov.causes[cause] or cause) or ov.none,110,y,12,cause~='' and c.text or c.group,'cond')
 local limit=Layout.limits[lc.stopLimit or 0] or ''
 if limit~='' then W.text(ov.limit,200,y+2,10,c.label,'label'); W.right(ov.limits[limit] or limit,f.w-14,y,12,c.warn,'cond') end
 y=y+20
 W.text(ov.stint,12,y+2,10,c.label,'label')
 local sf=lc.stintFor or -1
 if sf>=0 then W.text(text('oStint',ov.stintFmt,sub.stint,math.floor(sf/60),math.floor(sf%60)),110,y,12,c.text,'mono')
 else W.text(text('oStint1',ov.ageShort,sub.stint),110,y,12,c.text,'mono') end
 y=y+20
 -- Dernière sanction (pont v2 : code de L.reasons, 99 ou inconnu : « autre »).
 local rc=lc.lastReason or 0
 if rc>0 then
  local key=Layout.reasons and Layout.reasons[rc] or nil
  W.text(ov.sanction,12,y+2,10,c.label,'label')
  W.text(key and ov.reasons2[key] or ov.reasonOther,110,y,12,c.warn,'cond')
  y=y+20
 end
 local failure=Layout.failures[lc.failure or 0] or ''
 if failure~='' then
  W.text(ov.failure,12,y+2,10,c.label,'label')
  W.text(ov.failures[failure] or failure,110,y,12,lc.critical and c.danger or c.warn,'cond')
  y=y+20
 end
 h=y+8; heights.other=h
 return h
end
-- Frise de la course (votre plan) : tours faits, fenêtre, tour d'arrêt prévu, tour en cours, arrivée.
local function timeline(c,ov,f,y,plan,stopLap,lap)
 local total=math.max(1,plan.total or 1)
 local x0,w=12,f.w-24
 local function at(n) return x0+w*U.clamp((n-1)/total,0,1) end
 W.rect(x0,y,w,8,c.block)
 W.rect(x0,y,at(plan.done+1)-x0,8,c.rule)
 if plan.window then W.rect(at(plan.window[1]),y,math.max(2,at(plan.window[2]+1)-at(plan.window[1])),8,c.select) end
 if stopLap then local sx=at(stopLap); W.rect(sx-1.5,y-4,3,16,c.cyan) end
 W.rect(at(lap)-1,y-2,2,12,c.text)
 W.text('T1',x0,y+11,9,c.group,'mono')
 W.right(text('tlEnd','T%d',total),x0+w,y+11,9,c.group,'mono')
 if stopLap then local lab=text('tlStop','T%d',stopLap); local lw=W.width(lab,9,'mono'); W.text(lab,U.clamp(at(stopLap)-lw/2,x0+22,x0+w-lw-26),y+11,9,c.cyanText,'mono') end
end
function M.draw.strategy(app,f,o)
 local ov=L.t.ov; local c=W.colors()
 if idle(app) then return waiting(app,o,f,L.t.home.strategy) end
 local sub=Focus.subject(app.focus,app.F)
 if not sub.own then return otherStrategy(app,f,o,sub) end
 local F=app.F; local t=app.engineer.strategist; local plan=t.plan
 local status=t.status=='measured' and ov.measured or ov.estimated
 local t0=top(app,o)
 if not F.isRace then local h=t0+28; frameBox(app,o,f,h,L.t.home.strategy,''); W.text(ov.noRace,12,t0+2,12,c.muted); return h end
 local me=F.cars[F.player]
 -- Stratégie coupée (jamais « apprentissage » sans fin) ; course finie (jamais un plan périmé).
 local off=not app.cfg.strategyOn and ov.stratOff or me and me.finished and ov.raceDone or nil
 if off then local h=t0+28; frameBox(app,o,f,h,L.t.home.strategy,''); W.text(off,12,t0+2,13,c.muted); return h end
 if not plan or not plan.ok then
  local h=t0+28
  frameBox(app,o,f,h,L.t.home.strategy,status)
  W.text(plan and (ov.reasons[plan.reason] or plan.reason) or text('sLearn',ov.learning,#t.data.clean),12,t0+2,13,c.muted)
  return h
 end
 local h=t0+310
 frameBox(app,o,f,h,L.t.home.strategy,status)
 local y=t0+2
 -- Arrêt engagé (1.3.1) : « BOX CE TOUR » / « BOX AU PROCHAIN TOUR » en grand, le tour du « box » dit à la radio et
 -- publié pour AdvancedIA (jamais l'optimum recalculé à côté) ; voie fermée ; sinon fenêtre et tour d'arrêt.
 local d=app.link and app.link.d
 local lap=me and me.laps+1 or 0
 local L0=t.boxLap or plan.optimal
 local banner,bannerCol=nil,nil
 if d and d.pitsClosed and L0 then banner,bannerCol=ov.pitsClosed,c.warn
 elseif t.ready and (t.neutralBox or t.boxLap and t.boxLap==lap) then banner,bannerCol=ov.boxThis,c.danger
 elseif t.ready and t.boxLap and t.boxLap==lap+1 then banner,bannerCol=ov.boxNext,c.warn end
 if banner then
  W.rect(10,y-2,f.w-20,30,c.block)
  local tw=W.width(banner,22,'display')
  W.text(banner,(f.w-tw)/2,y,22,bannerCol,'display')
 elseif L0 and plan.window then
  -- plan.window : un « box » engagé peut rester alors que le plan refait ne prévoit plus d'arrêt (ni fenêtre).
  W.text(ov.window,12,y+6,11,c.label,'label')
  W.text(range('sWindow',plan.window[1],plan.window[2]),86,y,22,c.text,'display')
  W.text(ov.optimal,230,y+6,11,c.label,'label')
  -- Tour d'arrêt grisé tant que le plan n'est pas prêt (estimations des premiers tours, jamais annoncé).
  W.right(text('sOptimal','T%d',L0),f.w-14,y-2,26,t.ready and c.cyan or c.muted,'display')
 else W.text(ov.noStop,12,y+2,16,c.ok,'cond') end
 y=y+34
 timeline(c,ov,f,y,plan,L0,lap)
 y=y+26
 local lapsLeft=plan.total-plan.done
 local mark=L.mark()
 W.text(text('sStops','%s %d  ·  %s %d/%d  ·  %s',ov.stops,plan.stops,ov.lap,plan.done+1,plan.total,text('sAge',ov.stintAge,t.data.tyreAge)),12,y,11,c.muted,'mono')
 y=y+18
 -- Températures qui pèsent sur l'usure (piste et air) et leur tendance projetée.
 W.text(text('sTemps','%s %d°  ·  %s %d°  ·  %s °/min',ov.trackT,math.floor(F.road+0.5),ov.airT,math.floor(F.ambient+0.5),num('sTrend',t.data.roadTrend,1,mark,true)),12,y,11,c.label,'mono')
 y=y+20
 -- Dégradation et adhérence : maintenant et au tour d'arrêt.
 W.text(ov.deg,12,y+2,10,c.label,'label')
 -- Perte au tour sur des pneus neufs, maintenant et au tour d'arrêt (pas un rythme de dégradation par tour).
 W.text(text('sDeg','+%s → +%s s %s',num('sDegNow',plan.degNow or 0,2,mark),num('sDegStop',plan.degAtStop or 0,2,mark),ov.vsNew),110,y,12,c.text,'mono')
 y=y+18
 if plan.gripNow then
  W.text(ov.grip,12,y+2,10,c.label,'label')
  W.text(text('sGrip','%s %% → %s %%',num('sGripNow',plan.gripNow,1,mark),num('sGripStop',plan.gripAtStop or plan.gripNow,1,mark)),110,y,12,c.text,'mono')
 end
 y=y+18
 W.text(ov.pitLoss,12,y+2,10,c.label,'label')
 W.text(text('sLoss','%s s',num('sLoss',t.loss or 0,1,mark)),110,y,12,c.text,'mono')
 -- Table réutilisée par l'ingénieur : lue aussitôt, jamais gardée.
 local fs=Engineer.fuelStatus(app.engineer,F,app.cfg)
 if fs and fs.delta then
  W.text(ov.fuel,200,y+2,10,c.label,'label')
  W.right(text('sFuel','%s %s',num('sFuel',fs.delta,1,mark,true),ov.laps),f.w-14,y,12,fs.delta<-0.2 and c.danger or fs.delta<0.5 and c.warn or c.text,'mono')
 end
 y=y+20
 -- Ressortie prévue au tour optimal.
 local r=t.rejoin
 W.text(ov.rejoin,12,y+2,10,c.label,'label')
 if r then
  W.text(text('sRejoin',ov.position,r.position),110,y,13,c.cyanText,'mono')
  W.cell(text('sAround','%s %s  ·  %s %s',ov.aheadShort,who('sAhead',F,ov,mark,r.ahead,r.aheadGap),ov.behindShort,who('sBehind',F,ov,mark,r.behind,r.behindGap)),150,y+1,f.w-164,11,c.body)
 else W.text(ov.none,110,y,12,c.group,'mono') end
 y=y+20
 -- Duels.
 local du=t.duel
 duel('sUnder',c,ov,mark,y,ov.undercut,du and du.undercut,du and du.undercutGap,12)
 duel('sOver',c,ov,mark,y,ov.overcut,du and du.overcut,du and du.overcutGap,200)
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
  W.text(text('sFrom','T%d',plan.done+from),12,y+50,9,c.group,'mono')
  W.right(text('sTo','T%d',plan.done+to),f.w-12,y+50,9,c.group,'mono')
 end
 return h
end
-- Déverrouillé : glisser pour déplacer, coin bas droit pour la taille, clic droit pour verrouiller (cadre et poignée
-- à l'accent). Verrouillé sans clics traversants : clic droit pour déverrouiller. Édition en jeu (src/editor.lua,
-- app.editing) : tous déverrouillés sans toucher au réglage enregistré ; un geste ou un clic droit choisit l'overlay
-- réglé dans le panneau (cadre plus épais, nom en bas).
local function edit(v,app,o,f)
 local st=v[o]; local cfg=app.cfg; local c=W.colors()
 -- Poignée et zone de glisser en pixels d'écran (comme SuperHUD : 22 px à l'échelle 1, jamais moins de 18) : elles
 -- s'attrapent aussi à 0,35 fois.
 local w,h=f.w,st.h; local hs=math.max(M.handle,22*f.s)/f.s
 local editing=app.editing==true
 if editing or not cfg[o..'Locked'] then
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
  if editing then
   if a1 or a2 or a3 or r1 or r2 or r3 then app.editSel=o end
  elseif r1 or r2 or r3 then app.set(o..'Locked',true) end
  local sel=editing and app.editSel==o
  -- Marques Racing 26 (SuperHUD) : filet d'accent en haut, poignée à deux traits dans le coin ; taille en pixels
  -- pendant le redimensionnement.
  W.frameRect(0,0,w,h,c.cyan,sel and 3 or 1)
  W.rect(0,0,w-10,2,c.cyan)
  W.line(w-4,h-18,w-18,h-4,c.cyan,2.2); W.line(w-4,h-11,w-11,h-4,c.cyan,2.2)
  if a3 then
   local label=text('size_'..o,'%d × %d px',math.floor(st.wp+0.5),math.floor(st.hp+0.5))
   W.rect(6,h-22,W.width(label,10,'mono')+12,16,c.panel,2); W.text(label,12,h-20,10,c.cyanText,'mono')
  else
   W.right(W.upper(editing and L.t.ovui.names[o] or L.t.ov.unlocked),w-hs-4,h-16,10,c.cyan,'cond')
  end
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
 -- 1.3.9 : blocs de SuperHUD sur ce bureau (installé, réglage, clé vivante), puis nos overlays déjà placés : une
 -- position automatique (Y à -1) se décale verticalement pour ne rien recouvrir.
 local avoid=nil
 if app.has and app.has.superhud and cfg.shAvoid and app.superhud then
  avoid={}
  for _,r in ipairs(SuperHUD.blocks(app.superhud,app.real or 0,app.desktop or 1,sw,sh)) do avoid[#avoid+1]=r end
 end
 for _,o in ipairs(Config.overlays) do
  local st=v[o]; local k=K[o]
  local unlocked=app.editing or not cfg[k.locked]
  if cfg[k.show] and (unlocked or not hidden and connected) then
   local s=cfg[k.scale]; local w=M.design[o]*s; local h=math.max(30,st.h)*s
   local dx,dy=defaultPos(o,sw,sh,w,v)
   local x=cfg[k.x]>=0 and cfg[k.x] or dx
   local y=cfg[k.y]>=0 and cfg[k.y] or dy
   x=U.clamp(x,0,math.max(0,sw-w)); y=U.clamp(y,0,math.max(0,sh-h))
   if avoid then
    if cfg[k.y]<0 then x,y=SuperHUD.avoid(x,y,w,h,avoid,sh) end
    avoid[#avoid+1]={x=x,y=y,w=w,h=h}
   end
   st.x,st.y,st.wp,st.hp=x,y,w,h
   if st.pos then st.pos.x=x; st.pos.y=y; st.size.x=w; st.size.y=h else st.pos=vec2(x,y); st.size=vec2(w,h) end
   if not st.draw then st.draw=function() content(v,app,o) end end
   ui.transparentWindow(windowId(o,app.desktop or 1),st.pos,st.size,true,unlocked or not cfg.clickThrough,st.draw)
  end
 end
 if v.err then local e=v.err; v.err=nil; error(e,0) end
end
return M
