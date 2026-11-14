-- Ingénieur : rythme et consignes, carburant, pneus, freins, dégâts, conditions, pilotage ; la stratégie d'arrêt est
-- dans src/strategist.lua. Module pur : tout passe par ctx (image F, liaison, radio, réglages, chronométrage).
local U=require('src/util')
local Say=require('src/say')
local Timing=require('src/timing')
local Coach=require('src/coach')
local Strategist=require('src/strategist')
local Position=require('src/position')
local Debrief=require('src/debrief')
local Voice=require('src/voice')
local Emergency=require('src/emergency')
local Link=require('src/link')
local Side=require('src/side')
local SetupLab=require('src/setuplab')
local M={}
local GAP,PACE=Position.GAP,Position.PACE
-- Annonce de position : validité dans la file, délai minimal entre deux (s).
local POSITION_TTL,POSITION_COOLDOWN=15,40
function M.new()
 return {strategist=Strategist.new(),coach=Coach.new(),sectorOf={},lap=-1,coldFor=0,hotFor=0,warm=false,brakeHotFor=0,bias=0,
  biasFor=0,trans=0,rain=0,rainSaid={},crossSaid={},crossDir=nil,crossSince=nil,gripAt=0,windSeg={},fuelOkSaid=false,inPitLap=false,lastLapPit=false,stintTyresOk=false,
  mapSaved=false,coldSaid=false,hotSaid=false,wasCold=false,wearSaid=false,wearKm=0,wearPit=false,grainWarm={0,0,0,0},defectFor=0,coolFor=0,okFor=0,wearSides={},brakeSaid=false,
  brakeCoolFor=0,biasSaid=0,biasCalm=0,posTyresSaid=false,aheadAtLine={},pitted={},debrief=Debrief.new()}
end
-- Verrous d'annonce gardés au rechargement à chaud de l'app (CSP recharge le script au moindre fichier changé : tout
-- l'état repartait de zéro, « usure anormale » redite cinq fois le 05/11/2026, bilan et fenêtre redits). ctx.keep
-- (facultatif : load(nom) -> texte ou nil, store(nom, texte)) est la mémoire de la partie, gardée au rechargement, pas
-- d'un lancement du jeu à l'autre. Une seule chaîne courte, nom « locks » :
--   1|séance|usure dite|km virtuels alors|côtés d'essieu dits (FL 1, FR 2, RL 4, RR 8)|bilan dit|« plus d'arrêt » dit|
--   fenêtre annoncée (début,fin,optimal ou vide)
-- Relue une fois par état neuf, seulement pour la même séance ; écrite quand un verrou change (jamais à chaque image).
-- Après une remise à zéro (nouvelle séance, redémarrage) : jamais relue, récrite vide.
local LOCKS='locks'
local function locks(e,ctx)
 local keep=ctx.keep
 if not keep then return end
 local t=e.strategist; local st=e.debrief
 local session=math.floor(tonumber(ctx.F.session) or -1)
 local k=e.kept
 if not k then
  k={}; e.kept=k
  local text=not e.cleared and keep.load(LOCKS)
  local s,wear,km,sides,said,noMore,window
  if type(text)=='string' then s,wear,km,sides,said,noMore,window=text:match('^1|(%-?%d+)|([01])|([%d%.]+)|(%d+)|([01])|([01])|(.*)$') end
  if s and tonumber(s)==session then
   local mask=tonumber(sides)
   e.wearSaid=wear=='1'; e.wearKm=tonumber(km) or 0
   e.wearSides.FL=mask%2>=1 or nil; e.wearSides.FR=mask%4>=2 or nil; e.wearSides.RL=mask%8>=4 or nil; e.wearSides.RR=mask%16>=8 or nil
   st.said=said=='1'; t.noMoreSaid=noMore=='1'
   local a,b,c=window:match('^(%-?%d+),(%-?%d+),(%-?%d+)$')
   if a then t.announcedWindow={tonumber(a),tonumber(b),tonumber(c)} end
   -- Relu : rien à récrire tant que rien ne change.
   k.session=session; k.wear=e.wearSaid; k.sides=mask; k.said=st.said; k.noMore=t.noMoreSaid; k.window=t.announcedWindow or false
  end
 end
 local ws=e.wearSides
 local mask=(ws.FL and 1 or 0)+(ws.FR and 2 or 0)+(ws.RL and 4 or 0)+(ws.RR and 8 or 0)
 local a=t.announcedWindow or false
 if k.session==session and k.wear==e.wearSaid and k.sides==mask and k.said==st.said and k.noMore==t.noMoreSaid and k.window==a then return end
 k.session=session; k.wear=e.wearSaid; k.sides=mask; k.said=st.said; k.noMore=t.noMoreSaid; k.window=a
 keep.store(LOCKS,string.format('1|%d|%d|%.1f|%d|%d|%d|%s',session,e.wearSaid and 1 or 0,e.wearKm,mask,st.said and 1 or 0,t.noMoreSaid and 1 or 0,
  a and string.format('%d,%d,%d',a[1],a[2],a[3] or 0) or ''))
end
M.locks=locks
-- Changement de séance : tout repart de zéro (clés à nil comprises), sauf les données de la voiture (src/port.lua).
-- Verrous gardés (locks) : la première remise à zéro d'un état qui n'a encore rien vu est celle du chargement de l'app
-- (les verrous de la séance en cours seront relus) ; toute autre les efface (keep facultatif : effacés tout de suite,
-- sinon récrits vides à l'image suivante).
function M.reset(e,keep)
 local car=e.strategist.car
 local again=e.kept~=nil or e.wasReset
 U.refill(e,M.new())
 e.strategist.car=car
 e.wasReset=true
 if again then e.cleared=true; if keep then keep.store(LOCKS,'') end end
end
local say=Say.as('engineer')
-- Position à la ligne (« Tu es P5 »), quand elle a changé depuis la dernière entendue : une seule transmission par
-- ligne, fusionnée avec la consigne (attaque, défends, garde ta position…) ou suivie d'un conseil tiré de la course
-- (voiture devant rattrapable avant l'arrivée, pneus à ménager). Jamais avant la fin du tour 2 (départ), dans la voie
-- des stands, sous neutralisation, course finie, ni au dernier tour quand le spotter la dit avec « Dernier tour ! ».
-- Une annonce mise en file mais jamais entendue (périmée, retirée, coupée tout de suite) n'est pas comptée : redite à la
-- ligne suivante (entendue : dite jusqu'au bout, src/voice.lua v.done).
local function positionDue(e,ctx,me)
 local F=ctx.F; local d=ctx.link.d; local v=ctx.say.voice
 if e.posQueuedAt and v then
  local heard=v.done.position
  if heard and heard>=e.posQueuedAt then e.posQueuedAt=nil
  elseif not Voice.pending(v,'position') and not (v.current and v.current.key=='position') then e.posSaid=e.posBefore; e.posQueuedAt=nil end
 end
 if not ctx.cfg.positionCalls or me.laps<2 or me.pitlane or Position.finished(d) then return false end
 if Link.neutralised(d) then return false end
 local pos=tonumber(me.position) or 0
 if pos<=0 or pos==e.posSaid then return false end
 return not (Position.lastLap(F,me,d,e.strategist.plan) and Position.spotterSaysLastLap(ctx.cfg))
end
-- Annonce de position : position, « Bien joué » si une voiture a été dépassée en piste depuis la ligne précédente,
-- puis la consigne. État nouveau : jamais écarté comme une redite (src/voice.lua, fresh).
local function positionCall(e,ctx,me,prio,parts,gained,tone)
 local pos=me.position
 local out={{pos=pos}}
 if gained then out[#out+1]='posGained' end
 for k=1,#(parts or {}) do out[#out+1]=parts[k] end
 local ok=say(ctx,'position',math.min(prio or 4,4),out,{ttl=POSITION_TTL,cooldown=POSITION_COOLDOWN,fresh=true,tone=tone or (gained and 'motivating' or nil)})
 if ok then e.posBefore=e.posSaid; e.posSaid=pos; e.posQueuedAt=ctx.real end
 return ok
end
-- Place gagnée ou perdue en piste, dite tout de suite (1.3.0, réglage « Position en direct ») et non plus à la ligne
-- suivante : place changée et tenue LIVE_POS s ; gagnée sur une voiture qui n'est pas passée par la voie des stands
-- (« P5, superbe dépassement ! »), perdue au profit d'une voiture passée devant en piste (« P6. Il est passé, on reste
-- calme »). Une place prise ou perdue à un arrêt ou à un abandon n'est pas dite ici (la ligne la dira). En course à partir
-- du tour 2, hors voie des stands et neutralisation ; même clé et même délai que l'annonce à la ligne (jamais les deux).
local LIVE_POS=2.5
local function livePosition(e,ctx,me)
 local F=ctx.F; local d=ctx.link.d; local cfg=ctx.cfg
 if not F.isRace or not cfg.positionCalls or not cfg.positionLive or me.laps<2 or me.pitlane or me.finished or Link.neutralised(d) then e.livePos=nil; return end
 local pos=tonumber(me.position) or 0
 if pos<=0 then return end
 local lp=e.livePos
 if not lp then lp={pos=pos,ahead={},cand=nil}; e.livePos=lp; Position.aheadOf(F,me,lp.ahead); return end
 if pos==lp.pos then lp.cand=nil; Position.aheadOf(F,me,lp.ahead); return end
 lp.cand=lp.cand or ctx.now
 if ctx.now-lp.cand<LIVE_POS and ctx.now>=lp.cand then return end
 local gained=pos<lp.pos and Position.overtook(F,me,lp.ahead,e.pitted)
 local lost=pos>lp.pos and Position.passedBy(F,me,lp.ahead,e.pitted)
 lp.pos=pos; lp.cand=nil; Position.aheadOf(F,me,lp.ahead)
 if pos==e.posSaid then return end
 if gained then positionCall(e,ctx,me,4,nil,true,'motivating')
 elseif lost then positionCall(e,ctx,me,4,{'posLost'},false,'frustrated') end
end
M.livePosition=livePosition
-- Annonce de cette clé entendue il y a moins de s secondes (doublon avec le spotter : écarts vivants).
local function heardRecently(ctx,key,s)
 local v=ctx.say.voice; local at=v and v.started[key]
 return at~=nil and ctx.real-at<s and ctx.real>=at
end
-- Rythme et consignes, à la fin de chaque tour du joueur.
local function pace(e,ctx,lapDone)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]; local t=e.strategist
 if not lapDone or not F.isRace then return end
 local due=positionDue(e,ctx,me)
 -- Dépassement en piste depuis la ligne précédente ; puis voitures devant et arrêts remis à zéro pour le tour suivant.
 local gained=Position.overtook(F,me,e.aheadAtLine,e.pitted)
 Position.aheadOf(F,me,e.aheadAtLine)
 for k in pairs(e.pitted) do e.pitted[k]=nil end
 local d=ctx.link.d
 local plan=t.plan
 if me.laps<2 or e.lastLapPit or me.pitlane or Link.neutralised(d) then
  -- Tour de sortie des stands : la position seule (« tu ressors P8 »), sans consigne ni « bien joué ». Temps cible
  -- repris du plan de maintenant (1.3.1 : celui d'avant l'arrêt, pneus usés, donnait « moins 1,5 s » au premier tour
  -- lancé sur pneus neufs).
  t.targetPrev=plan and plan.ok and t.ready and plan.target or nil
  if due then positionCall(e,ctx,me,4,nil,false) end
  return
 end
 local last=me.lastMs/1000
 -- Delta sur le temps cible du modèle (tour précédent) ; pas la ligne où la position est dite (une transmission).
 -- Seulement sur un tour normal (1.3.1) : jamais un tour invalide, passé par les stands, neutralisé ou de sortie
 -- (« plus 4,9 secondes » après un tête-à-queue).
 if cfg.pace and not due and t.targetPrev and last>0 and me.laps%cfg.paceEvery==0 and M.normalLap(t,me) then
  local delta=last-t.targetPrev
  if math.abs(delta)>=0.3 and math.abs(delta)<5 then
   say(ctx,'target',5,{'targetDelta',delta>0 and 'plus' or 'minus',{n=math.abs(delta),dec=1,unit='s'}},{ttl=15})
  elseif math.abs(delta)<0.3 then say(ctx,'target',5,{'goodPace'},{ttl=10,cooldown=240}) end
 end
 -- Temps cible du modèle seulement quand le plan est prêt (premiers tours : estimations).
 t.targetPrev=plan and plan.ok and t.ready and plan.target or nil
 -- Une consigne par ligne au plus : dite seule, ou avec la position quand celle-ci a changé (la clé de la consigne
 -- garde son délai ; position refusée : la consigne seule).
 local spoke=false
 local function call(key,prio,parts,opts)
  if spoke then return false end
  local ok
  if due then
   due=false
   local v=ctx.say.voice
   if v and (opts.cooldown or 0)>0 and v.last[key] and ctx.real-v.last[key]<opts.cooldown then ok=positionCall(e,ctx,me,prio,nil,gained)
   else
    ok=positionCall(e,ctx,me,prio,parts,gained)
    if ok and v then v.last[key]=ctx.real end
    if not ok then ok=say(ctx,key,prio,parts,opts) end
   end
  else ok=say(ctx,key,prio,parts,opts) end
  spoke=ok
  return ok
 end
 local ahead,behind=Position.neighbours(F,me)
 local mine=Timing.pace(ctx.timing,F.player,PACE.laps)
 local ga=ahead and Timing.gap(ctx.timing,ahead,F.player,ctx.now) or nil
 local gb=behind and Timing.gap(ctx.timing,F.player,behind,ctx.now) or nil
 local pa=ahead and Timing.pace(ctx.timing,ahead,PACE.laps) or nil
 local pb=behind and Timing.pace(ctx.timing,behind,PACE.laps) or nil
 if cfg.pushHold then
  -- Attaque / conservation : écarts devant et derrière, rythme comparé. Consignes dites en entrant dans la
  -- situation (pas à chaque tour d'une bagarre) ; situation liée à la voiture devant (une autre voiture, ou un écart
  -- hors de portée : situation nouvelle).
  if ahead~=e.attackCar or not ga or ga>=GAP.chase then e.attackState=nil; e.attackCar=ahead end
  local hybrid=F.me.kers or F.me.p2p>0 or F.me.drsPresent
  if ga and ga<GAP.attack then
   -- Déjà dit par le spotter (« tu es dans la seconde », 1.3.0) : l'attaque n'est pas redite à la ligne.
   if e.attackState~='close' then
    e.attackState='close'
    if not heardRecently(ctx,'inSecond',60) then call('attack',3,{hybrid and 'overtake' or 'push'},{ttl=10,cooldown=180,tone='motivating'}) end
   end
  elseif ga and ga<GAP.chase and mine and pa and pa-mine>PACE.chase then
   if e.attackState~='chase' then
    e.attackState='chase'
    -- Gain par tour sur la voiture chassée, positif (« +0,3 s/tour », comme « tu reviens »).
    local per=string.format('(+%s s%s)',U.fixed(pa-mine,1,Say.mark(ctx.say)),Say.note(ctx.say,'perLap'))
    call('attack',4,{'push',{text=per}},{ttl=10,cooldown=240})
   end
  elseif cfg.pace and me.laps%cfg.paceEvery==0 and mine and pa and ga and ga<GAP.compare then
   -- Comparaison du rythme avec la voiture chassée.
   local diff=pa-mine
   if diff>PACE.compare then call('paceCmp',5,{'closing',{text=string.format('(%s s%s)',U.fixed(diff,1,Say.mark(ctx.say)),Say.note(ctx.say,'perLap'))}},{ttl=12,cooldown=300})
   elseif diff<-PACE.compare then call('paceCmp',5,{'losingTime',{n=-diff,dec=1,unit='s'},{text=Say.note(ctx.say,'perLap')}},{ttl=12,cooldown=300}) end
  end
  if gb and gb<GAP.defend and pb and mine and mine-pb>PACE.defend then
   if not heardRecently(ctx,'heInSecond',60) then call('defend',4,{'hesClosing','defend'},{ttl=10,cooldown=300,tone=gb<1 and 'urgent' or nil}) end
  elseif ga and gb and ga>GAP.hold and gb>GAP.hold then call('hold',5,{'hold'},{ttl=10,cooldown=600,tone='calm'}) end
 end
 if due then
  -- Pas de consigne cette ligne : la position, avec un conseil seulement s'il est justifié. Voiture devant
  -- rattrapable avant l'arrivée (écart rattrapé au rythme actuel dans les tours restants) ; sinon pneus à ménager
  -- (surchauffe ou usure anormale constatée, une fois par relais) quand personne ne menace derrière.
  local left=Position.lapsLeft(F,me,plan)
  local gain=mine and pa and pa-mine or 0
  local advice=nil
  if ga and (ga<GAP.attack or ga<GAP.chase and gain>PACE.reach and (not left or ga/gain<=left)) then advice='posReach'
  elseif (e.hotSaid or e.wearSaid) and not e.posTyresSaid and (not gb or gb>GAP.tyres) then advice='posTyres' end
  if positionCall(e,ctx,me,4,advice and {advice} or nil,gained) and advice=='posTyres' then e.posTyresSaid=true end
 end
end
-- Dernier tour du joueur normal pour le modèle (src/stratdata.lua) : ni invalide, ni aux stands, ni neutralisé, ni de
-- sortie.
function M.normalLap(t,me)
 local r=t.data.records[#t.data.records]
 return r~=nil and r.lap==me.laps and not (r.pit or r.neutral or r.invalid or r.out)
end
-- Carburant (1.3.1 : un seul calcul pour la radio et les deux overlays, qui affichaient sans la marge et sur le dernier
-- calcul du plan) : consommation par tour (mesurée, sinon celle d'AC), tours de carburant marge déduite (have), besoin
-- (target : jusqu'au « box » engagé ou à l'arrêt du plan prêt, sinon jusqu'à l'arrivée), écart (delta, en tours).
-- nil : rien à juger (pas de consommation, pas de mesure). Table gardée, refaite à chaque appel (appelée à chaque
-- image par les overlays) : à lire tout de suite, jamais à garder.
function M.fuelStatus(e,F,cfg)
 local me=F.cars[F.player]; local t=e.strategist
 if not me or not me.valid or F.fuelRate==0 then return nil end
 local fpl=t.data.fuelPerLap or Strategist.baseFuel(t,F)
 if not fpl or fpl<=0 then return nil end
 local plan=t.plan
 -- Sans plan (stratégie coupée) : tours de la course comptés par le stratège (course au temps, pilote attardé).
 local total=plan and plan.total or Strategist.total(t,F,me)
 local stop=t.ready and plan and plan.ok and (t.boxLap or plan.optimal) or nil
 local target=stop and stop-me.laps or (total and total>0 and total-me.laps) or nil
 local have=(F.me.fuel-(cfg.fuelMargin or 0))/fpl
 local st=e.fuelView
 if not st then st={}; e.fuelView=st end
 st.fpl=fpl; st.laps=F.me.fuel/fpl; st.have=have; st.target=target; st.delta=target and have-target or nil; st.toStop=stop~=nil; st.total=total
 return st
end
-- Carburant : laps de carburant comparés au besoin (jusqu'à l'arrêt prévu ou l'arrivée), à chaque tour.
local function fuel(e,ctx,lapDone)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]; local t=e.strategist
 if not cfg.fuel or not lapDone or not F.isRace or me.laps<1 or e.lastLapPit or me.pitlane then return end
 local d0=ctx.link.d
 if Link.neutralised(d0) then return end
 local st=M.fuelStatus(e,F,cfg)
 if not st or not st.target or st.target<=0 then return end
 local plan=t.plan
 local total=st.total
 local have,delta=st.have,st.delta
 -- Premiers tours (mesures insuffisantes) : aucune consigne, sauf un manque immédiat (moins de deux tours).
 if not Strategist.dataReady(t) and not t.ready and have>=2 then return end
 -- Sans arrêt prévu (plan pas prêt, stratégie coupée, plan impossible) et loin du compte : c'est un arrêt qu'il faut,
 -- pas du lift and coast (1.3.1 : « économise, moins 15 tours » dans une course qui demande un ravitaillement).
 if not st.toStop and delta<-2 then return end
 -- Hystérésis : en manque sous -0,2 tour, sorti du manque seulement à +0,3 (pas d'alternance en suivant la consigne,
 -- et jamais « plus 0,0 tour »).
 local sign=delta<-0.2 and -1 or delta>=1 and 1 or 0
 if e.fuelSign==-1 and sign==0 and delta<0.3 then sign=-1 end
 if sign==-1 then
  -- Manque : dit en y entrant, puis seulement s'il s'aggrave d'un demi-tour (jamais à chaque tour).
  if e.fuelSign~=-1 or not e.fuelShortSaid or delta<e.fuelShortSaid-0.5 then
   e.fuelShortSaid=delta
   say(ctx,'fuel',3,{'liftCoast','fuelTarget','minus',{n=-delta,dec=1},'laps'},{ttl=15})
  end
  if F.me.fuelMaps>1 and e.fuelSign~=-1 then e.mapSaved=true; say(ctx,'map',4,{'mapSave'},{ttl=15,cooldown=300}) end
 elseif e.fuelSign==-1 and sign>=0 then
  e.fuelShortSaid=nil
  say(ctx,'fuel',4,{'fuelTarget','plus',{n=math.max(0,delta),dec=1},'laps'},{ttl=15})
 elseif me.laps%5==0 and math.abs(delta)>=0.3 then
  -- Point régulier : jamais « plus 0 tour » ni « moins 0,1 » sans conseil (marge nulle : rien à dire).
  say(ctx,'fuel',5,{'fuelTarget',delta>=0 and 'plus' or 'minus',{n=math.abs(delta),dec=1},'laps'},{ttl=15})
 end
 if total-me.laps<=3 and delta>=0 and not e.fuelOkSaid and not (plan and plan.optimal) then e.fuelOkSaid=true; say(ctx,'fuelOk',4,{'fuelOk'},{ttl=15}) end
 -- Après une consigne d'économie, marge revenue à un tour au moins : map attaque (une fois).
 if e.mapSaved and F.me.fuelMaps>1 and delta>=1 then e.mapSaved=false; say(ctx,'map',4,{'mapPush'},{ttl=15}) end
 e.fuelSign=sign
end
-- Pneus : chauffe (cœur sous l'optimum), surchauffe (cœur ou surface au-dessus), usure anormale d'un pneu.
local TYRE_NAMES={'avant gauche','avant droit','arrière gauche','arrière droit'}
-- Côté le plus usé d'un essieu (noms : gauche, droit) quand l'écart de km virtuels passe 30 %, sinon nil.
local FRONT,REAR={'FL','FR'},{'RL','RR'}
local function uneven(t,a,b,names)
 local x,y=t[a].vkm,t[b].vkm
 local hi,lo=math.max(x,y),math.min(x,y)
 if hi>1 and lo>0 and hi>lo*1.3 then return x>y and names[1] or names[2] end
 return nil
end
M.GRAIN_WARM=60
local function tyres(e,ctx,dt)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]
 -- Passage par les stands retenu pour l'usure anormale (pneus peut-être changés) ; pneus neufs à chauffer.
 if me.pitlane then e.wearPit=true; for k=1,4 do e.grainWarm[k]=0 end end
 if not cfg.tyres or me.pitlane or me.kmh<60 then return end
 local cold,hot,ok=0,0,0
 local maxKm=0
 for k=1,4 do
  local w=F.me.tyres[k]
  local surface=(w.inner+w.mid+w.outer)/3
  if w.core<w.opt-cfg.tyreCold then cold=cold+1 end
  if w.core>w.opt+cfg.tyreHot or surface>w.opt+cfg.tyreHot*1.6 then hot=hot+1 end
  if math.abs(w.core-w.opt)<cfg.tyreCold*0.6 then ok=ok+1 end
  maxKm=math.max(maxKm,w.vkm)
  -- Temps passé à température (grainage : voir plus bas) ; un pneu redevenu froid repart de zéro.
  e.grainWarm[k]=w.core>=w.opt-cfg.tyreCold and e.grainWarm[k]+dt or 0
 end
 -- Une fois par état : froid jusqu'à ce qu'ils chauffent, chaud jusqu'à 60 s sans surchauffe.
 e.coldFor=cold>=2 and e.coldFor+dt or 0
 if cold>=2 then e.wasCold=true end
 e.hotFor=hot>=1 and e.hotFor+dt or 0
 if e.coldFor>20 and me.laps>=1 and not e.coldSaid then e.coldSaid=true; e.warm=false; say(ctx,'tyreTemp',4,{'tyresCold'},{ttl=10}) end
 if e.hotFor>15 and not e.hotSaid then e.hotSaid=true; say(ctx,'tyreTemp',3,{'tyresHot'},{ttl=10}) end
 if hot==0 then e.coolFor=e.coolFor+dt; if e.coolFor>60 then e.hotSaid=false end else e.coolFor=0 end
 -- « Pneus froids » réarmé après 60 s à température (pas à chaque passage au seuil : des pneus qui oscillent autour
 -- le feraient redire toutes les 30 s).
 if ok==4 then e.okFor=e.okFor+dt; if e.okFor>60 then e.coldSaid=false end else e.okFor=0 end
 -- « Pneus à température » : seulement après une phase froide (départ, sortie des stands), une fois par relais.
 if ok==4 and not e.warm then e.warm=true; if e.wasCold and not e.stintTyresOk then e.stintTyresOk=true; e.wasCold=false; say(ctx,'tyreTemp',5,{'tyresOk'},{ttl=8}) end end
 -- Usure anormale : un pneu nettement plus usé que l'autre du même essieu (l'avant et l'arrière s'usent normalement
 -- différemment), méplat, cloques, grains, crevaison. Dite une fois par train de pneus ; un écart d'usure sur un essieu,
 -- une seule fois par séance pour le même essieu et le même côté (un circuit qui use un côté plus que l'autre le
 -- referait à chaque train de pneus). Un défaut du pneu (méplat, cloques, grains, crevaison), tenu 1 s, est toujours dit.
-- Grains (1.3.7) : AC fait grainer un pneu neuf encore froid, et ce grainage part en chauffant (journaux du 12/11/2026 :
-- huit « usure anormale » à 0,35-0,39 de grains et 0,1 km virtuel, 40 à 60 s après chaque sortie des stands). Un
-- grainage ne compte qu'après GRAIN_WARM s de pneu à température.
 local t=F.me.tyres
 local side=uneven(t,1,2,FRONT) or uneven(t,3,4,REAR)
 local defect,why=nil,nil
 for k=1,4 do
  local w=t[k]
  local d=w.blown and 'crevaison' or w.flat>0.2 and 'méplat' or w.blister>0.35 and 'cloques'
   or w.grain>0.35 and e.grainWarm[k]>=M.GRAIN_WARM and 'grains' or nil
  if d and not defect then defect,why=k,d end
 end
 e.defectFor=defect and e.defectFor+dt or 0
 -- Train neuf : km virtuels qui reculent (pneus changés, retour au garage). Ils n'avancent qu'avec le multiplicateur
 -- d'usure (faible ou nul : ils restent près de 0), « peu de km » ne dit donc pas un train neuf (cela réarmait l'annonce
 -- à chaque image, redite dès la fin de repeatGap). Après un arrêt, un défaut reparti réarme aussi (pneus changés).
 if maxKm<e.wearKm-0.05 then e.wearSaid=false end
 e.wearKm=maxKm
 if e.wearPit then e.wearPit=false; if not defect then e.wearSaid=false end end
 local worn=defect and e.defectFor>=1
 if (worn or side and not e.wearSides[side]) and not e.wearSaid then
  e.wearSaid=true; if side then e.wearSides[side]=true end
  -- Crevaison : dite comme une urgence (1.3.0, src/emergency.lua), pas comme une usure anormale.
  if not (worn and why=='crevaison' and cfg.emergencies) then say(ctx,'wear',3,{'abnormalWear'},{ttl=10}) end
  if ctx.journal then
   local w=worn and t[defect]
   ctx.journal(w and string.format('usure anormale : %s, pneu %s (méplat %.2f, cloques %.2f, grains %.2f, %.1f km virtuels)',why,TYRE_NAMES[defect],w.flat,w.blister,w.grain,w.vkm)
    or string.format("usure anormale : écart sur l'essieu %s (km virtuels %.1f / %.1f / %.1f / %.1f)",side,t[1].vkm,t[2].vkm,t[3].vkm,t[4].vkm))
  end
 end
end
M.tyres=tyres
M.pace=pace
-- Bilan de fin de course (src/debrief.lua) : une fois, Debrief.DELAY s après la ligne d'arrivée (le spotter annonce
-- d'abord la place), après un abandon ou une disqualification aussi ; dit en entier (jamais tenu pour déjà entendu).
-- Arrivée vue par AC seulement (ligne passée, ou séance finie : abandon) ; appelé aussi pendant la suspension
-- « finished » d'AdvancedIA (SpotterEnginer.lua), jamais au retour au stand. Le résultat d'AdvancedIA ne sert qu'aux
-- détails (place corrigée, grille, abandon), et pas s'il était déjà fini avant l'arrivée : il ne le remet à zéro qu'au
-- changement de séance, et après un redémarrage le bilan de la course d'avant a été dit à tort le 10/11/2026.
local function debrief(e,ctx)
 local F=ctx.F; local st=e.debrief
 locks(e,ctx)
 if st.said or not F.isRace or not ctx.cfg.debrief then return end
 local me=F.cars[F.player]
 if not me or not me.valid or (tonumber(me.laps) or 0)<1 then return end
 if not (me.finished or F.finishedSession) then return end
 if not st.at then st.at=ctx.real; return end
 if ctx.real-st.at<Debrief.DELAY then return end
 local d=Debrief.fresh(st,ctx.link.d) or {dnf=not me.finished}
 st.said=true
 local s=ctx.say
 local parts=Debrief.parts(st,F,d,not Debrief.spotterSays(ctx.cfg),function(id,...) return Say.note(s,id,...) end,
  function(sec) return U.lapTime(sec,Say.mark(s)) end)
 say(ctx,'debrief',3,parts,{ttl=30,fresh=true})
end
M.debrief=debrief
-- Freins : surchauffe et déséquilibre avant / arrière (répartition à corriger si la voiture la règle au volant).
local function brakes(e,ctx,dt)
 local F=ctx.F; local cfg=ctx.cfg; local b=F.me.brakes
 if not cfg.brakes or (b[1]<=0 and b[3]<=0) then return end
 local front=(b[1]+b[2])*0.5; local rear=(b[3]+b[4])*0.5
 local hottest=math.max(b[1],b[2],b[3],b[4])
 -- Une fois par épisode : redit seulement après 30 s nettement sous le seuil.
 e.brakeHotFor=hottest>cfg.brakeHot and e.brakeHotFor+dt or 0
 if e.brakeHotFor>5 and not e.brakeSaid then e.brakeSaid=true; say(ctx,'brakes',3,{'brakesHot'},{ttl=10}) end
 if hottest<cfg.brakeHot-50 then e.brakeCoolFor=e.brakeCoolFor+dt; if e.brakeCoolFor>30 then e.brakeSaid=false end else e.brakeCoolFor=0 end
 if not F.me.hasBias then return end
 local diff=front-rear
 local want=diff>cfg.biasDiff and 1 or diff<-cfg.biasDiff and -1 or 0
 e.biasFor=want~=0 and want==e.bias and e.biasFor+dt or 0; e.bias=want
 -- Une fois par sens de déséquilibre ; réarmé après 60 s d'équilibre (une image équilibrée ne suffit pas).
 if e.biasFor>20 and e.biasSaid~=want then e.biasSaid=want; say(ctx,'bias',4,{want>0 and 'biasRear' or 'biasFront'},{ttl=12}) end
 if want==0 then e.biasCalm=e.biasCalm+dt; if e.biasCalm>60 then e.biasSaid=0 end else e.biasCalm=0 end
end
-- Dégâts : choc enregistré par AC sur une zone de la carrosserie (aéro).
local function damage(e,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local dmg=F.me.damage
 local sum=U.sum(dmg,1,5)
 -- Contact suivi par les urgences (1.3.0, src/emergency.lua : bilan des dégâts) : pas de « dégâts aéro » en plus.
 -- Zones 1 à 5 d'AC, comme le bilan des urgences.
 if e.damage and cfg.damage and sum-e.damage>=20 and not Emergency.busy(ctx.emergency,ctx) then say(ctx,'damage',2,{'aeroDamage'},{ttl=10,cooldown=30}) end
 e.damage=sum
end
-- Conditions : pluie à venir (transition de la météo vers un temps de pluie), pluie qui s'intensifie, adhérence.
-- Pluie à venir : dite en passant sous chaque palier (minutes) ; les paliers franchis d'un coup sont tenus pour dits
-- (première estimation à 2 minutes : « une minute » était ensuite dit trois fois, un palier par minute).
local RAIN_MARKS={15,10,5,2}
-- Premier palier pas encore dit pour minutes (et ceux franchis d'un coup tenus pour dits), ou nil.
local function mark(said,marks,minutes)
 for k=1,#marks do
  if minutes<=marks[k] and minutes>=1 and not said[marks[k]] then
   for j=k,#marks do if minutes<=marks[j] then said[marks[j]]=true end end
   return marks[k]
  end
 end
 return nil
end
local function inMinutes(clip,minutes) return minutes==1 and {clip,'oneMinute'} or {clip,{n=minutes},'minutes'} end
-- Bascule de pneus annoncée à l'avance (1.3.5, météo en direct d'AdvancedIA, clé AdvancedIA.weather : src/side.lua) :
-- next (pneu de la bascule) et eta (temps avant que l'état sec / mouillé d'AdvancedIA bascule, ce qui décide des pneus
-- du peloton), aux paliers CROSS_MARKS, une fois par bascule. La pluie à venir reste l'estimation de l'app : forecastIn
-- d'AdvancedIA n'est qu'une borne haute de son arrivée. Prudence (AdvancedIA : pente fausse pendant environ une minute
-- au début d'une averse soudaine) : direction tenue CROSS_HOLD s avant la première annonce ; une direction qui disparaît
-- un moment (tendance hésitante) garde ses paliers, seule une inversion ou la bascule faite (wet du pont) les efface ;
-- jamais quand le pont dit déjà la piste mouillée (pneus pluie) ou sèche (slicks). Clé figée (inchangée depuis
-- WEATHER_FRESH s : réglage coupé) : ignorée.
local CROSS_MARKS={10,5,2}
local CROSS_HOLD=60
local WEATHER_FRESH=30
local function crossover(e,ctx,wx,now)
 local d=ctx.link and ctx.link.d
 local dir=wx and (wx.next=='dry' and 'dry' or (wx.next=='inter' or wx.next=='wet') and 'wet') or nil
 local done=e.crossDir and d and (e.crossDir=='wet' and d.wet or e.crossDir=='dry' and not d.wet)
 if done or dir and dir~=e.crossDir then
  if next(e.crossSaid) then e.crossSaid={} end
  e.crossDir=dir; e.crossSince=dir and now or nil
 end
 if not dir or dir~=e.crossDir or wx.eta<60 or now-(e.crossSince or now)<CROSS_HOLD or now<(e.crossSince or now) then return end
 if d and (dir=='wet' and d.wet or dir=='dry' and not d.wet) then return end
 local minutes=math.floor(wx.eta/60+0.5)
 -- Même clé que « la pluie s'intensifie » : jamais les deux à la suite.
 if mark(e.crossSaid,CROSS_MARKS,minutes) then say(ctx,'rain',3,inMinutes(dir=='wet' and 'crossWet' or 'crossDry',minutes),{ttl=30}) end
end
local function weather(e,ctx)
 local F=ctx.F; local cfg=ctx.cfg
 if not cfg.weather then return end
 local now=ctx.now
 local wx=Side.get(ctx.side,'weather')
 if wx and (Side.age(ctx.side,'weather') or 0)>WEATHER_FRESH then wx=nil end
 crossover(e,ctx,wx,now)
 if F.rainComing then
  if not e.transAt then e.transAt=now; e.trans=F.transition end
  local span=now-e.transAt
  if span>=60 then
   local rate=(F.transition-e.trans)/span
   e.transAt=now; e.trans=F.transition
   if rate>0 then
    local minutes=math.floor((0.5-F.transition)/rate/60+0.5)
    if mark(e.rainSaid,RAIN_MARKS,minutes) then say(ctx,'rainIn',3,inMinutes('rainIn',minutes),{ttl=30}) end
   end
  end
 elseif e.transAt then e.transAt=nil; e.rainSaid={} end
 if not e.rainAt or now-e.rainAt>=120 then
  if e.rainAt and F.rain-e.rain>0.08 and F.rain>0.05 then say(ctx,'rain',3,{'rain'},{ttl=15,cooldown=300}) end
  e.rainAt=now; e.rain=F.rain
 end
 -- Adhérence de la piste (roadGrip, et humidité) : variation sur 5 minutes.
 local grip=F.grip*(1-0.5*F.wetness)
 e.grip=U.ewma(e.grip,grip,0.05)
 if not e.gripRef then e.gripRef=e.grip; e.gripAt=now end
 if now-e.gripAt>=300 then
  local delta=e.grip-e.gripRef
  if delta<=-0.01 then say(ctx,'grip',4,{'gripDown'},{ttl=20,cooldown=900})
  elseif delta>=0.01 then say(ctx,'grip',5,{'gripUp'},{ttl=20,cooldown=900}) end
  e.gripRef=e.grip; e.gripAt=now
 end
end
M.weather=weather
-- Vent au freinage : composante du vent dans l'axe de la voiture au début d'un gros freinage.
local function wind(e,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]
 if not cfg.wind or F.windKmh<cfg.windMin or me.kmh<140 or F.me.brake<0.6 then return end
 local along=F.windX*me.lookX+F.windZ*me.lookZ
 if math.abs(along)<cfg.windMin then return end
 local seg=math.floor(me.spline*Coach.segments)
 local last=e.windSeg[seg]
 if last and me.laps-last<5 then return end
 e.windSeg[seg]=me.laps
 say(ctx,'wind',5,{along>0 and 'tailwind' or 'headwind'},{ttl=4,cooldown=60})
end
-- Conseil de pilotage : clip du conseil, puis le secteur officiel du circuit dit (« au secteur deux », appris en roulant :
-- compteur de secteur d'AC vu sur chaque tronçon du coach) ; le nom du virage (CSP) et le temps perdu sont écrits. Sans
-- secteur connu : le conseil seul, jamais « au secteur » sans le numéro.
function M.coachCall(e,ctx,advice)
 local sector=ctx.sectorName and ctx.sectorName((advice.segment+0.5)/Coach.segments) or ''
 local official=e.sectorOf[advice.segment]
 local detail={}
 if sector~='' then detail[#detail+1]=sector end
 if not official and sector=='' then detail[#detail+1]=string.format('%d/%d',advice.segment+1,Coach.segments) end
 if advice.kind=='losingTime' and advice.loss then detail[#detail+1]=string.format('%s s',U.fixed(advice.loss,2,Say.mark(ctx.say))) end
 local parts={advice.kind}
 local text=Say.text(ctx.say,{advice.kind})
 if official then
  parts[2]='atSector'; parts[3]={n=official+1}
  text=text..(advice.kind=='losingTime' and ' ' or ' · ')..Say.text(ctx.say,{'atSector',{n=official+1}})
 end
 if #detail>0 then text=text..' ('..table.concat(detail,', ')..')' end
 return say(ctx,'coach',5,parts,{ttl=20,text=text})
end
local function driving(e,ctx,lapDone)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]
 Coach.update(e.coach,me.spline,me.kmh,F.me.brake,ctx.now,F.trackLength)
 -- Secteur officiel (compteur d'AC, 0 = premier) de chaque tronçon du coach, appris en roulant.
 if not me.pitlane and type(F.me.sector)=='number' and F.me.sector>=0 and F.me.sector<10 then
  local seg=math.floor(((me.spline or 0)%1)*Coach.segments)
  if seg>=0 and seg<Coach.segments then e.sectorOf[seg]=math.floor(F.me.sector) end
 end
 if not lapDone then return end
 local d=ctx.link.d
 local rec=e.strategist.data.records[#e.strategist.data.records]
 local clean=rec and rec.clean or false
 local advice=Coach.lap(e.coach,clean and not (d and d.neutral),cfg.drivingLoss)
 if advice and cfg.driving then M.coachCall(e,ctx,advice) end
end
-- SetupLab (1.3.9, app facultative ; ctx.setuplab : src/setuplab.lua). Hors course seulement : à chaque tour d'essai
-- jugé (hausse de tid), le verdict de SetupLab (jamais le nôtre) : « plus rapide de 0,3 s » / « plus lent » avec le
-- changement principal (tch : groupe qui porte le plus gros gain prévu, jamais dit comme une cause), « pas de différence
-- nette » ; rien tant que SetupLab attend (wait), même avec un écart chiffré. Un verdict n'est redit que s'il change
-- (ou l'écart de SETUP_MOVE s) ; nouvelle version (ver) : tout repart. Nouvelle version prête (hausse de readyN) : dite
-- une fois. En qualification (raceSessionType 2), gardé jusqu'à l'entrée dans la voie des stands (jamais en tour lancé),
-- le dernier seulement.
M.SETUP_MOVE=0.05
M.SETUP_TTL=20
local function setupVerdict(e,ctx,v)
 if not v.ver or v.ver~=e.slVer then e.slVer=v.ver; e.slSaid=nil end
 local tv=v.tv
 if tv~='better' and tv~='worse' and tv~='same' then return nil end
 local gap=tv~='same' and v.tdl and math.abs(v.tdl) or nil
 if (tv=='better' or tv=='worse') and not gap then return nil end
 local said=e.slSaid
 if said and said.tv==tv and (tv=='same' or math.abs(gap-said.gap)<M.SETUP_MOVE) then return nil end
 e.slSaid={tv=tv,gap=gap or 0}
 local mark=Say.mark(ctx.say)
 if tv=='same' then return {'setupSame'},nil end
 local parts={tv=='better' and 'setupBetter' or 'setupWorse',{n=gap,dec=1,unit='s'}}
 local text=Say.text(ctx.say,{parts[1]})..' '..U.fixed(gap,2,mark)..' s'
 local group=v.tch and SetupLab.groups[v.tch]
 if group then parts[#parts+1]=group; text=text..' · '..Say.text(ctx.say,{group}) end
 return parts,text
end
local function setupLab(e,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]
 local s=ctx.setuplab
 local v=cfg.setupLab and SetupLab.get(s) or nil
 -- Carburant avant toute mesure (src/strategist.lua, baseFuel).
 e.strategist.setupFpl=v and SetupLab.fuelPerLap(s) or nil
 local tidUp,readyUp=SetupLab.take(s)
 if not v or F.isRace then e.slPending=nil; return end
 if tidUp and cfg.setupTrials then
  local parts,text=setupVerdict(e,ctx,v)
  if parts then e.slPending=e.slPending or {}; e.slPending.verdict={parts,text} end
 end
 if readyUp and cfg.setupReady then e.slPending=e.slPending or {}; e.slPending.ready=true end
 local p=e.slPending
 if not p then return end
 if F.sessionType==2 and not me.pitlane then return end
 e.slPending=nil
 if p.verdict then say(ctx,'setupLab',4,p.verdict[1],{ttl=M.SETUP_TTL,text=p.verdict[2]}) end
 if p.ready then say(ctx,'setupReady',4,{'setupReady'},{ttl=M.SETUP_TTL}) end
end
M.setupLab=setupLab
function M.step(e,ctx,dt)
 local F=ctx.F; local me=F.cars[F.player]
 if not me or not me.valid then return end
 locks(e,ctx)
 local lapDone=me.laps~=e.lap and e.lap>=0
 -- Tour qui vient de finir passé par la voie des stands (tour d'entrée ou de sortie) : ni rythme ni carburant jugés.
 if me.laps~=e.lap then e.lastLapPit=e.inPitLap; e.inPitLap=me.pitlane; e.lap=me.laps end
 if me.pitlane then e.inPitLap=true; e.stintTyresOk=false; e.warm=false; e.posTyresSaid=false end
 -- Voitures passées par la voie des stands depuis la ligne du joueur (« Bien joué » : dépassements en piste seulement).
 for i=0,F.count-1 do if F.cars[i].pitlane then e.pitted[i]=true end end
 Debrief.step(e.debrief,F,ctx.timing,ctx.link.d)
 livePosition(e,ctx,me)
 -- Ligne d'arrivée passée : plus aucun appel de course (« undercut possible » dit sur la ligne le 10/11/2026), le bilan
 -- seulement.
 if me.finished and F.isRace then debrief(e,ctx); return end
 setupLab(e,ctx)
 Strategist.step(e.strategist,ctx)
 pace(e,ctx,lapDone)
 fuel(e,ctx,lapDone)
 tyres(e,ctx,dt)
 brakes(e,ctx,dt)
 damage(e,ctx)
 weather(e,ctx)
 wind(e,ctx)
 driving(e,ctx,lapDone)
 debrief(e,ctx)
end
return M
