-- Stratège (ingénieur) : relie les mesures (src/stratdata.lua), les données de la voiture (courbes d'usure, réservoir,
-- temps d'arrêt), les règles et plans d'AdvancedIA (arrêts obligatoires, fenêtre, arrêts prévus des IA) et le calcul
-- (src/strategy.lua). Recalcul à chaque tour du joueur, à chaque arrêt et au début d'une neutralisation ; résultat
-- gardé pour l'overlay Stratégie et les annonces (fenêtre, tour optimal, box, undercut, overcut). Module pur.
local U=require('src/util')
local S=require('src/strategy')
local SD=require('src/stratdata')
local Timing=require('src/timing')
local Link=require('src/link')
local Say=require('src/say')
local M={}
function M.new()
 return {data=SD.new(),car=nil,plan=nil,model=nil,race=nil,duel=nil,rejoin=nil,solvedLap=-1,solvedAt=-1e9,neutral=false,
  announcedWindow=nil,boxSaid={},lastPit={},rivalPit={},costMs=0,status='learning',neutralBox=false,targetPrev=nil,ready=false,pitDueSeen=false,boxLap=false}
end
function M.reset(t) local car=t.car; local n=M.new(); for k,v in pairs(n) do t[k]=v end; t.car=car end
-- Retard sur le leader en tours, en continu (tours + fraction) : stable quand le leader passe la ligne avant le joueur
-- (les tours entiers du leader feraient croire le joueur attardé pendant ce temps). 0 pour le leader ou sans leader.
local function behindLeader(F,me)
 if not me or me.position==1 then return 0 end
 for i=0,F.count-1 do
  local c=F.cars[i]
  if c.valid and c.position==1 then return math.max(0,(c.laps+(c.spline or 0))-(me.laps+(me.spline or 0))) end
 end
 return 0
end
M.behindLeader=behindLeader
-- Tours de la course : course aux tours, ou course au temps (temps restant / rythme, plus le tour de plus éventuel).
local function totalLaps(F,me,pace)
 -- Course aux tours : un pilote attardé en fait moins (tours de retard sur le leader).
 if not F.timed and F.laps>0 then return math.max(me.laps+1,math.ceil(F.laps-behindLeader(F,me)-1e-6)) end
 if pace and pace>0 and F.timeLeft>0 then
  -- Course au temps : le tour en cours compte (fraction déjà faite), puis les tours que permet le temps restant.
  return me.laps+math.max(1,math.floor(F.timeLeft/pace+(me.spline or 0))+1)+(F.additional and 1 or 0)
 end
 return F.laps>0 and F.laps or me.laps+1
end
-- Arrêts obligatoires encore dus et fenêtre (tours), d'après les règles d'AdvancedIA.
-- Arrêts encore dus : avant la fenêtre, tous (un arrêt fait avant ne compte pas) ; pendant, le compte d'AdvancedIA
-- (arrêts faits dans la fenêtre) ; après, aucun. Fenêtre en tours à partir de maintenant : avancement d'AdvancedIA
-- (tours du leader, ou temps d'une course chronométrée) converti en tours du joueur ; fermeture avec 0,3 tour de marge.
local function rules(d,done,total,pace,F,behind)
 if not d or d.pitState=='off' or d.pitWaived or d.mandatoryStops<=0 then return 0,0,total end
 local owed=d.pitState=='pending' and d.mandatoryStops or d.pitState=='open' and math.max(0,d.pitDue) or 0
 local p=math.max(1,pace or 100)
 local open,close
 if d.pitCsp then
  open=done+math.max(0,(d.pitOpen-d.pitPosition)/1000/p); close=done+math.max(0,(d.pitClose-d.pitPosition)/1000/p)
 elseif d.pitPosition>=0 and d.pitPosition<1 then
  local perUnit
  if F and F.timed and F.timeLeft>0 then
   -- Course au temps : avancement continu (temps), converti en tours du joueur depuis maintenant.
   perUnit=F.timeLeft/(1-d.pitPosition)/p
   open=done+math.max(0,(d.pitOpen-d.pitPosition)*perUnit); close=done+math.max(0,(d.pitClose-d.pitPosition)*perUnit)
  else
   -- Course aux tours : seuils en tours du leader, moins le retard continu du joueur (un arrêt à la fin de son tour x
   -- compte si le leader en est alors à x + retard).
   local laps=F and F.laps>0 and F.laps or total
   open=d.pitOpen*laps-(behind or 0); close=d.pitClose*laps-(behind or 0)
  end
 else open=d.pitOpen*total; close=d.pitClose*total end
 return owed,math.ceil(open),math.floor(close-0.3)
end
-- Rythme de référence du joueur : médiane des derniers tours propres, sinon meilleur tour.
local function pace(t,ctx)
 local d=t.data
 local list={}
 for k=math.max(1,#d.clean-4),#d.clean do list[#list+1]=d.clean[k].time end
 if #list>0 then return U.median(list) end
 local p=Timing.pace(ctx.timing,ctx.F.player,3)
 return p or d.best
end
-- Âge des pneus d'un rival (tours depuis son dernier passage aux stands vu par l'app, ou relais d'AdvancedIA).
local function rivalAge(t,ctx,i,p)
 local c=ctx.F.cars[i]
 local seen=t.lastPit[i]
 if seen then return math.max(0,c.laps-seen) end
 local lc=Link.car(ctx.link,i)
 if lc and lc.stintFor and lc.stintFor>0 and p then return math.floor(lc.stintFor/p) end
 return c.laps
end
-- Plan prêt à être annoncé. Il est calculé et affiché dès le départ (overlay Stratégie : modèle estimé), mais aucune
-- annonce n'en part (fenêtre, tour optimal, box, undercut / overcut, carburant jusqu'à l'arrêt, temps cible) tant
-- qu'il repose sur des estimations : il faut deux tours propres mesurés (le tour du départ ne l'est jamais), ou trois
-- tours vus par l'app (piste neutralisée, tours lents), ou un arrêt qui ne peut pas attendre (carburant mesuré pour
-- deux tours au plus). Compté sur ce que l'app a vu dans la séance (remis à zéro à chaque séance ; un rechargement en
-- course repart de zéro). Avant, les rappels réglementaires d'AdvancedIA (fenêtre ouverte, fermeture proche) restent
-- dits : un arrêt obligatoire n'est jamais oublié.
M.readyClean=2; M.readyLaps=3
local function dataReady(d) return #d.clean>=M.readyClean or #d.records>=M.readyLaps end
M.dataReady=function(t) return dataReady(t.data) end
local function ready(t)
 local plan=t.plan
 if not plan or not plan.ok then return false end
 if dataReady(t.data) then return true end
 return t.data.fuelPerLap~=nil and plan.optimal~=nil and plan.fuelLaps~=nil and plan.fuelLaps<=2
end
M.ready=ready
-- Effet du carburant sur le temps au tour (s par litre) : nul sans consommation (réglage d'AC, voiture sans
-- carburant), le même pour l'ajustement du temps de base et pour le modèle (sinon le temps cible est faussé).
local function fuelEffect(F,cfg) if F.fuelRate==0 or F.me.fuel<=0 then return 0 end return cfg.fuelK end
M.fuelEffect=fuelEffect
local function solve(t,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]; local d=ctx.link.d
 local p=pace(t,ctx)
 local car=t.car or {}
 local carIn={tank=F.me.maxFuel>0 and F.me.maxFuel or car.tank,fuel=F.me.fuel,tyreChange=car.tyreChange,fuelRate=car.fuelRate,
  curves=car.curves,km0F=(F.me.tyres[1].vkm+F.me.tyres[2].vkm)*0.5,km0R=(F.me.tyres[3].vkm+F.me.tyres[4].vkm)*0.5,
  fuelPerLap=F.me.fuelPerLapAC>0 and F.me.fuelPerLapAC or nil,minPit=d and d.minPitTime or 0}
 -- Perte de voie estimée sans mesure : longueur de voie inconnue -> réglage.
 local m=SD.model(t.data,carIn,cfg,p,fuelEffect(F,cfg))
 -- Sans consommation (réglage d'AC, voiture sans carburant) : le carburant ne limite rien (jamais de plan sur la
 -- consommation par défaut) ; la masse ne change pas non plus (fuelEffect : 0, au modèle comme à l'ajustement).
 if fuelEffect(F,cfg)==0 then m.fuelPerLap=1e-4; m.fuel=m.tank end
 -- État au début du tour en cours (le plan compte des tours entiers depuis là) : un recalcul en milieu de tour donne
 -- le même tour d'arrêt qu'au passage de la ligne. Carburant et usure sont lus maintenant (ramenés au début du tour) ;
 -- l'âge des pneus compte déjà les tours finis (src/stratdata.lua).
 local frac=me.pitlane and 0 or math.max(0,math.min(0.99,(me.spline or 0)%1))
 m.fuel=m.fuel+frac*m.fuelPerLap; m.km0F=math.max(0,m.km0F-frac*(m.kmF or 0)); m.km0R=math.max(0,m.km0R-frac*(m.kmR or 0))
 local done=me.laps
 local total=totalLaps(F,me,p)
 local owed,open,close=rules(d,done,total,p,F,behindLeader(F,me))
 local race={done=done,total=total,mandatory=owed,windowOpen=open,windowClose=close}
 -- Rivaux pour la ressortie : progression, rythme, arrêt prévu par AdvancedIA.
 local rivals={}
 local mine=Timing.car(ctx.timing,F.player)
 for i=0,F.count-1 do
  local c=F.cars[i]
  local tc=Timing.car(ctx.timing,i)
  if i~=F.player and c.valid and not c.retired and tc.progress then
   local lc=Link.car(ctx.link,i)
   local rp=Timing.pace(ctx.timing,i,3) or p or 100
   if lc and lc.safety then rp=nil end
   if rp then rivals[#rivals+1]={index=i,progress=tc.progress,pace=rp,stopLap=lc and lc.planned and lc.nextStopLap or -1} end
  end
 end
 local meInfo={progress=mine.progress or done,pace=p or m.base,fresh=m.base+m.fuelK*m.fuel*0.5}
 -- Perte d'un arrêt à la fin du tour done+n1 : voie, pneus et carburant pour finir (au plus un plein).
 local tankLaps=math.max(1,math.floor((m.tank-m.fuelMargin)/m.fuelPerLap))
 local function lossAt(n1)
  local left=math.max(0,m.fuel-n1*m.fuelPerLap)
  local want=math.min(m.tank,m.fuelPerLap*math.min(total-done-n1,tankLaps)+m.fuelMargin)
  return m.pitLane+S.stationary(m,want-left)
 end
 local traffic=nil
 if F.isRace and #rivals>0 then traffic=function(n1) return S.rejoin(m,meInfo,rivals,done,n1,lossAt(n1)) end end
 local plan=S.solve(m,race,traffic)
 local loss=lossAt(plan.optimal and plan.optimal-done or 1)
 t.plan=plan; t.model=m; t.race=race; t.pace=p; t.loss=loss
 t.rejoin=plan.optimal and plan.detail and plan.detail[plan.optimal-done] or nil
 -- Duels avec les voisins au classement : toujours calculés (overlay Stratégie), annoncés selon le réglage.
 t.duel=nil
 if F.isRace and p then
  local function rival(pos,ahead)
   for i=0,F.count-1 do
    local c=F.cars[i]
    if c.valid and c.position==pos and i~=F.player then
     local g=ahead and Timing.gap(ctx.timing,i,F.player,ctx.now) or Timing.gap(ctx.timing,F.player,i,ctx.now)
     if g then
      local age=rivalAge(t,ctx,i,p)
      local lc=Link.car(ctx.link,i)
      return {index=i,gap=g,age0=age,km0F=age*m.kmF,km0R=age*m.kmR,stop=lc and lc.planned and lc.nextStopLap or -1}
     end
    end
   end
   return nil
  end
  local a=me.position>1 and rival(me.position-1,true) or nil
  local b=rival(me.position+1,false)
  local out=S.duels(m,done,{km0F=m.km0F,km0R=m.km0R,age0=m.age0},a,b,loss)
  out.ahead=a; out.behind=b
  t.duel=out
 end
 local wasReady=t.ready
 t.ready=ready(t)
 if t.ready and not wasReady and ctx.journal then
  ctx.journal(string.format('plan prêt : %d tour(s) propre(s), %d tour(s) vus, %d arrêt(s), optimal T%s',#t.data.clean,#t.data.records,plan.stops or 0,tostring(plan.optimal or '-')))
 end
 t.status=plan.ok and (t.ready and t.data.base and 'measured' or 'estimated') or 'failed'
 return plan
end
M.solve=solve
M.rules=rules
local function say(ctx,key,prio,parts,opts) return Say.say(ctx.say,'engineer',key,prio,parts,ctx.real,opts) end
-- Chaque image. Renvoie vrai quand un nouveau calcul a été fait.
function M.step(t,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]; local d=ctx.link.d
 if not me or not me.valid then return false end
 -- Passages de la voiture figés à son entrée dans la voie (la traversée de la voie les remplace ensuite) et rythme
 -- de course : référence du tronçon en piste pour mesurer la perte de la voie.
 if not t.capture then
  t.capture=function(idx)
   local tc=ctx.timing.cars[idx]
   if not tc then return nil end
   local snap={}; for k,v in pairs(tc.cross) do snap[k]=v end
   return snap,ctx.timing.n,Timing.pace(ctx.timing,idx,3)
  end
 end
 local tyres=F.me.tyres
 local kmF=(tyres[1].vkm+tyres[2].vkm)*0.5; local kmR=(tyres[3].vkm+tyres[4].vkm)*0.5
 local lapDone=SD.update(t.data,{now=ctx.now,laps=me.laps,lapTime=me.lastMs/1000,fuel=F.me.fuel,kmF=kmF,kmR=kmR,
  pit=me.pitlane,road=F.road,ambient=F.ambient,neutral=d and (d.neutral or d.red) or false,valid=F.me.lapValid},t.car and t.car.curves or {})
 -- Arrêts de toutes les voitures : perte de voie mesurée, âge des pneus des rivaux.
 for i=0,F.count-1 do
  local c=F.cars[i]
  if c.valid then
   local r=SD.observePit(t.data,i,c.pitlane,c.kmh,ctx.now,c.spline,t.capture)
   if r then t.lastPit[i]=c.laps end
   if c.pitlane and not t.rivalPit[i] and i~=F.player then
    -- Voiture directement devant qui rentre aux stands.
    if F.isRace and c.position==me.position-1 and cfg.strategyOn and cfg.rivalPitVoice then say(ctx,'rivalPitted',3,{'rivalPitted'},{ttl=8}) end
   end
   t.rivalPit[i]=c.pitlane
  end
 end
 if lapDone then SD.fit(t.data,t.car and t.car.curves or {},fuelEffect(F,cfg),SD.gripPrior(pace(t,ctx)),cfg.degPrior) end
 local neutral=d and d.neutral or false
 -- Recalcul : au passage de la ligne, à la sortie des stands, sous neutralisation qui change, quand le compte des
 -- arrêts obligatoires dus change (décision d'AdvancedIA : arrêt validé, ou non compté faute de changement de composé,
 -- parfois après la sortie des stands), et toutes les 30 s.
 local pitExit=t.wasPit and not me.pitlane; t.wasPit=me.pitlane
 -- Arrêt en cours : le « box » engagé est tenu (voir boxCalls).
 if me.pitlane then t.boxLap=false end
 local due=d and d.pitDue or 0
 local dueChanged=t.pitDueSeen~=false and due~=t.pitDueSeen; t.pitDueSeen=due
 local need=lapDone or pitExit or dueChanged or t.solvedLap<0 or neutral~=t.neutral or ctx.now-t.solvedAt>30
 t.neutral=neutral
 if not cfg.strategyOn or me.laps<1 and not lapDone and t.solvedLap>=0 then return false end
 if need then
  local started=ctx.clock and ctx.clock() or 0
  solve(t,ctx)
  t.costMs=ctx.clock and (ctx.clock()-started)*1000 or 0
  t.solvedLap=me.laps; t.solvedAt=ctx.now
  M.announce(t,ctx,lapDone)
 end
 M.boxCalls(t,ctx)
 return need
end
-- Annonces de la stratégie : fenêtre (à son premier calcul fiable et quand elle bouge de 2 tours), undercut / overcut.
function M.announce(t,ctx,lapDone)
 local plan=t.plan; local cfg=ctx.cfg
 -- Plan pas encore prêt (premiers tours, voir ready) : rien d'annoncé, ni fenêtre ni duel.
 if not plan or not plan.ok or not ctx.F.isRace or not t.ready then return end
 -- Entre un « box » et l'arrêt, et dans la voie des stands : pas de fenêtre réannoncée (elle contredirait le box).
 local me=ctx.F.cars[ctx.F.player]
 local quietWindow=t.boxLap or (me and me.pitlane)
 -- Fenêtre et tour optimal : appels d'arrêt du plan (réglage « Box » et fenêtre) ; coupés, les rappels d'AdvancedIA
 -- restent dits par le spotter (une seule référence des stands, voir plannedLap dans src/spotter.lua).
 if cfg.boxCalls and plan.window and not quietWindow then
  local w=plan.window; local a=t.announcedWindow
  -- Le début de la fenêtre avance avec la course une fois dedans : seuls le tour optimal et la fermeture comptent.
  if not a or math.abs((a[3] or 0)-plan.optimal)>=2 or math.abs(a[2]-w[2])>=2 then
   t.announcedWindow={w[1],w[2],plan.optimal}
   say(ctx,'window',4,{'pitWindow',{n=w[1]},'toLap',{n=w[2]},'optimalLap',{n=plan.optimal}},{ttl=20})
  end
 end
 if lapDone and t.duel and cfg.duels then
  local du=t.duel
  if du.undercut and not t.wasUndercut then say(ctx,'duel',3,{'undercut'},{ttl=15}) end
  if du.overcut and not t.wasOvercut then say(ctx,'duel',3,{'overcut'},{ttl=15}) end
  if du.threat and not t.wasThreat then say(ctx,'duel',3,{'push',{text=Say.note(ctx.say,'coverUndercut')}},{ttl=15}) end
  t.wasUndercut=du.undercut; t.wasOvercut=du.overcut; t.wasThreat=du.threat
 end
end
-- « Box au prochain tour » pendant l'avant-dernier tour, « Box ce tour-ci » au début du tour d'arrêt ; sous
-- neutralisation, si s'arrêter maintenant coûte moins que le plan. Plan prêt seulement (voir ready).
function M.boxCalls(t,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]; local plan=t.plan
 if not cfg.boxCalls or not F.isRace or not t.ready or not plan or not plan.ok or not plan.optimal or me.pitlane then return end
 -- Voie des stands fermée (AdvancedIA, sous neutralisation) : aucun « box » ; il sera dit à sa réouverture.
 local d0=ctx.link.d
 if d0 and d0.pitsClosed then return end
 local lap=me.laps+1
 -- Engagement : un « box » dit pour le tour L ne change plus (le plan peut bouger d'un tour d'un calcul à l'autre) tant
 -- que l'arrêt n'est pas fait (voie des stands) ou que le tour L n'est pas passé : jamais « box ce tour » puis « box au
 -- prochain tour » (constaté en course le 05/11/2026).
 if t.boxLap and lap>t.boxLap then t.boxLap=false end
 local L=t.boxLap or plan.optimal
 if lap==L-1 and me.spline>0.6 and not t.boxSaid[L..'n'] then t.boxSaid[L..'n']=true; t.boxLap=L; say(ctx,'box',2,{'boxNextLap'},{ttl=20}) end
 if lap==L and me.spline>0.1 and me.spline<0.7 and not t.boxSaid[L..'t'] then t.boxSaid[L..'t']=true; t.boxLap=L; say(ctx,'box',1,{'boxThisLap'},{ttl=20}) end
 -- Neutralisation : s'arrêter ce tour-ci (n1 = 1) coûte-t-il moins que le meilleur plan ?
 local d=ctx.link.d
 -- Seul l'arrêt fait maintenant profite de la neutralisation (perte de voie réduite) ; le reste du plan, non.
 local cheap=t.model and t.model.pitLane*(1-cfg.neutralFactor) or 0
 if d and d.neutral and cfg.neutralBox and plan.costs[1] and plan.cost and plan.costs[1]-cheap-plan.cost<=cfg.tolerance and L~=lap and not t.neutralBox and me.spline<0.7 then
  t.neutralBox=true; say(ctx,'boxNeutral',1,{'boxThisLap',{text=Say.note(ctx.say,'neutralised')}},{ttl=15})
 end
 if not (d and d.neutral) then t.neutralBox=false end
end
return M
