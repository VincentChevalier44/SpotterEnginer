-- Données de la stratégie apprises en course (module pur) : consommation par tour, km virtuels par tour de chaque
-- essieu (usure réelle, qui contient déjà le style, la charge, la piste et la température), rythme de base et
-- sensibilité du temps au tour à l'adhérence perdue (régression sur les tours propres), perte de la voie des stands
-- (mesurée sur les arrêts du joueur et sur ceux des IA), tendance des températures (piste, et air pour moitié).
local U=require('src/util')
local S=require('src/strategy')
local M={}
function M.new()
 return {lap=-1,start=nil,records={},clean={},tyreAge=0,lastKmF=nil,
  fuelPerLap=nil,kmF=nil,kmR=nil,base=nil,gripK=nil,degLinear=nil,best=nil,
  lapPit=false,lapNeutral=false,lapInvalid=false,outLap=false,
  temps=U.ring(40),tempAt=-1e9,roadTrend=0,
  pits={},laneLoss=nil,laneSamples=U.ring(9)}
end
-- Prédiction de perte d'adhérence (%) moyenne des deux essieux aux km donnés (0 sans courbe).
local function gripLoss(curves,kmF,kmR)
 local n,sum=0,0
 if curves.F then sum=sum+math.max(0,curves.F.max-S.eval(curves.F,kmF)); n=n+1 end
 if curves.R then sum=sum+math.max(0,curves.R.max-S.eval(curves.R,kmR)); n=n+1 end
 return n>0 and sum/n or nil
end
M.gripLoss=gripLoss
-- Tendance de la température qui use les pneus (°C par minute, 10 dernières minutes) : piste, plus la moitié de la
-- température de l'air (l'air refroidit moins les pneus quand il se réchauffe).
local function trend(d)
 local xs,ys={},{}
 for k=1,d.temps.n do local s=U.recent(d.temps,k); xs[k]=s[1]; ys[k]=s[2] end
 if #xs<4 then return 0 end
 local _,b=U.linear(xs,ys)
 return U.clamp(b*60,-1,1)
end
-- s : {now, laps (tours finis), lapTime (dernier tour, s), fuel (L), kmF, kmR (km virtuels moyens par essieu),
--      pit (voie des stands), road, ambient (°C), neutral (VSC/SC/FCY, drapeau rouge), valid (tour en cours valide)}
-- curves : {F, R} courbes d'usure ou vides. Renvoie vrai quand un tour vient de finir.
function M.update(d,s,curves)
 if s.now-d.tempAt>=15 then d.tempAt=s.now; U.push(d.temps,{s.now,s.road+0.5*(s.ambient or s.road)}); d.roadTrend=trend(d) end
 -- Pneus changés : km virtuels revenus vers zéro.
 if d.lastKmF and s.kmF<d.lastKmF-0.3 then d.tyreAge=0; d.outLap=true; if d.start then d.start.kmF=s.kmF; d.start.kmR=s.kmR end end
 d.lastKmF=s.kmF
 if s.pit then d.lapPit=true end
 if s.neutral then d.lapNeutral=true end
 if s.valid==false then d.lapInvalid=true end
 -- Départ d'un tour pris en cours de route (premier passage) : ce tour n'est pas mesuré (start.line=false).
 if d.lap<0 or not d.start then
  d.lap=s.laps; d.start={fuel=s.fuel,kmF=s.kmF,kmR=s.kmR,at=s.now,line=false}
  return false
 end
 if s.laps==d.lap then return false end
 -- Tours sautés (app coupée, liaison perdue) ou tours revenus en arrière : rien d'enregistré, nouveau départ.
 if s.laps~=d.lap+1 or not d.start.line then
  local line=s.laps==d.lap+1
  d.lap=s.laps; d.start={fuel=s.fuel,kmF=s.kmF,kmR=s.kmR,at=s.now,line=line}
  d.lapPit=false; d.lapNeutral=false; d.lapInvalid=false; d.outLap=false
  return false
 end
 -- Tour terminé.
 local st=d.start
 local rec={lap=s.laps,time=s.lapTime,fuelUsed=st.fuel-s.fuel,kmF=s.kmF-st.kmF,kmR=s.kmR-st.kmR,
  fuelMid=(st.fuel+s.fuel)*0.5,kmMidF=(st.kmF+s.kmF)*0.5,kmMidR=(st.kmR+s.kmR)*0.5,age=d.tyreAge,
  pit=d.lapPit,neutral=d.lapNeutral,invalid=d.lapInvalid,out=d.outLap,road=s.road}
 d.records[#d.records+1]=rec; if #d.records>200 then table.remove(d.records,1) end
 local okTime=U.finite(rec.time) and rec.time>10
 -- Tour 1 (départ arrêté) jamais propre ; tour invalide jamais meilleur tour.
 local normal=okTime and rec.lap>=2 and not rec.pit and not rec.neutral and not rec.out and not rec.invalid
 if normal and (d.best==nil or rec.time<d.best) then d.best=rec.time end
 rec.clean=normal and d.best~=nil and rec.time<=d.best*1.04
 -- Consommation : tours sans arrêt ni neutralisation (un plein à l'arrêt fausserait la différence).
 if not rec.pit and not rec.neutral and rec.fuelUsed>0 and rec.fuelUsed<50 then d.fuelPerLap=U.ewma(d.fuelPerLap,rec.fuelUsed,0.35) end
 -- Usure par tour : tours propres, km virtuels positifs.
 if rec.clean and rec.kmF>=0 and rec.kmF<20 then d.kmF=U.ewma(d.kmF,rec.kmF,0.35); d.kmR=U.ewma(d.kmR,rec.kmR,0.35) end
 if rec.clean then d.clean[#d.clean+1]=rec; if #d.clean>30 then table.remove(d.clean,1) end end
 d.tyreAge=d.tyreAge+1
 d.lap=s.laps; d.start={fuel=s.fuel,kmF=s.kmF,kmR=s.kmR,at=s.now,line=true}
 d.lapPit=false; d.lapNeutral=false; d.lapInvalid=false; d.outLap=false
 return true
end
-- Rythme de base et sensibilité : temps corrigé du carburant = base + gripK × perte d'adhérence (avec courbe), ou
-- base + degLinear × âge (sans courbe). Régression sur les tours propres ; bornée par les valeurs a priori quand
-- l'écart d'usure est encore trop faible pour la mesurer.
function M.fit(d,curves,fuelK,priorGripK,priorDeg)
 local xs,ys={},{}
 local withCurve=curves.F~=nil or curves.R~=nil
 -- Tours propres revérifiés contre le meilleur tour actuel (un tour lent gardé d'avant ne fausse pas la pente).
 for k=1,#d.clean do
  local r=d.clean[k]
  if not d.best or r.time<=d.best*1.04 then
   local x=withCurve and gripLoss(curves,r.kmMidF,r.kmMidR) or r.age
   xs[#xs+1]=x; ys[#ys+1]=r.time-fuelK*r.fuelMid
  end
 end
 if #xs==0 then return end
 local spread=0
 for k=1,#xs do spread=math.max(spread,math.abs(xs[k]-xs[1])) end
 local a,b=U.linear(xs,ys)
 local prior=withCurve and priorGripK or priorDeg
 local slope
 if #xs>=5 and spread>=(withCurve and 1.0 or 4) then slope=U.clamp(b,prior*0.3,prior*3) else slope=prior end
 -- Base recalculée avec la pente retenue (moyenne des résidus).
 local sum=0
 for k=1,#xs do sum=sum+ys[k]-slope*xs[k] end
 a=sum/#xs
 d.base=a
 if withCurve then d.gripK=slope else d.degLinear=slope end
end
-- Temps du tronçon en piste entre l'entrée et la sortie de la voie, au rythme de course, lu sur les passages de la
-- voiture figés à son entrée dans la voie (snap : instants de passage aux n points du tour, src/timing.lua). À cet
-- instant, les points situés après l'entrée portent encore les passages du tour précédent : le tronçon est lu sur ce
-- même passage (premier point après l'entrée -> sortie), sans dépendre de la durée du tour (une neutralisation au tour
-- précédent ne fausse que ce tronçon).
local function snapAt(snap,n,spline)
 local x=(spline%1)*n; local k=math.floor(x); local f=x-k
 local a=snap[k%n]; local b=snap[(k+1)%n]
 if not a then return nil end
 if b and b>=a and b-a<60 then return a+(b-a)*f end
 return a
end
function M.trackSegment(snap,n,entry,exit)
 if not snap or not n then return nil end
 local x=(entry%1)*n
 local ke=math.floor(x)+1
 local a=snap[ke%n]; local a2=snap[(ke+1)%n]
 local b=snapAt(snap,n,exit)
 if not a or not a2 or not b then return nil end
 local step=a2-a
 if step<=0 or step>10 then return nil end
 local t=b-a+step*(ke-x)
 if t<=0.5 or t>120 then return nil end
 return t
end
-- Arrêts observés (joueur et IA) : temps passé dans la voie des stands comparé au temps du même tronçon en piste ;
-- perte de voie = perte totale moins l'arrêt immobile. i : indice de la voiture ; capture(i) -> instants de passage
-- de la voiture (copie, prise à l'entrée dans la voie, avant que la traversée de la voie ne les remplace), nombre de
-- points et durée de son dernier tour.
function M.observePit(d,i,inLane,kmh,now,spline,capture)
 local p=d.pits[i]
 if not p then p={inLane=false,enterAt=0,enterSpline=0,stillFor=0,last=now}; d.pits[i]=p end
 local dt=math.max(0,math.min(1,now-p.last)); p.last=now
 if inLane and not p.inLane then
  p.inLane=true; p.enterAt=now; p.enterSpline=spline; p.stillFor=0
  p.snap,p.points,p.lapTime=nil,nil,nil
  if capture then p.snap,p.points,p.lapTime=capture(i) end
 elseif inLane then if kmh<1 then p.stillFor=p.stillFor+dt end
 elseif p.inLane then
  p.inLane=false
  local laneTime=now-p.enterAt
  local track=M.trackSegment(p.snap,p.points,p.enterSpline,spline)
  p.snap=nil
  -- Passage complet avec arrêt (immobile 1 s au moins), durée plausible.
  if track and p.stillFor>=1 and laneTime>p.stillFor and laneTime<240 then
   local lane=laneTime-p.stillFor-track
   if lane>2 and lane<90 then U.push(d.laneSamples,lane); local list={}; for k=1,d.laneSamples.n do list[k]=U.recent(d.laneSamples,k) end; d.laneLoss=U.median(list) end
   return {lane=lane,still=p.stillFor,total=laneTime-track}
  end
 end
 return nil
end
-- A priori de la perte d'adhérence par unité d'usure (s), proportionnel au rythme ; défaut du modèle sans rythme.
function M.gripPrior(pace) return pace and pace*0.006 or S.defaultModel().gripK end
-- Modèle de la stratégie à partir des mesures et des données de la voiture (car : {tank, fuel, tyreChange, fuelRate,
-- curves, km0F, km0R, fuelPerLap, minPit}, cfg : réglages, fuelK : effet du carburant décidé par le stratège). Les
-- valeurs non mesurées gardent un a priori.
function M.model(d,car,cfg,pace,fuelK)
 local m=S.defaultModel()
 m.fuelK=fuelK or cfg.fuelK or m.fuelK
 m.fuelPerLap=d.fuelPerLap or car.fuelPerLap or m.fuelPerLap
 m.tank=car.tank or m.tank; m.fuel=car.fuel or m.fuel; m.fuelMargin=cfg.fuelMargin or 1
 m.wearF=car.curves and car.curves.F or nil; m.wearR=car.curves and car.curves.R or nil
 m.kmF=d.kmF or m.kmF; m.kmR=d.kmR or m.kmR
 m.km0F=car.km0F or 0; m.km0R=car.km0R or 0; m.age0=d.tyreAge
 m.gripK=d.gripK or M.gripPrior(pace)
 m.degLinear=d.degLinear or cfg.degPrior or m.degLinear
 m.base=d.base or (pace and pace-m.fuelK*m.fuel*0.5) or (d.best and d.best-m.fuelK*m.fuel*0.5) or m.base
 m.warmup=cfg.warmup or m.warmup
 m.pitLane=d.laneLoss or cfg.pitLane or m.pitLane
 m.tyreChange=car.tyreChange or m.tyreChange; m.fuelRate=car.fuelRate or m.fuelRate; m.minPit=car.minPit or 0
 -- Usure projetée : croissance relative par tour = sensibilité × tendance de la piste (°C/min) × durée du tour (min).
 local lapMin=(pace or m.base)/60
 m.wearGrowth=U.clamp((cfg.tempSens or 0.02)*d.roadTrend*lapMin,-0.02,0.02)
 m.gripFloor=cfg.gripFloor or m.gripFloor
 m.trafficCost=cfg.trafficCost or m.trafficCost
 m.tolerance=cfg.tolerance or m.tolerance
 -- Temps de base sans mesure : rythme actuel moins le carburant (mi-réservoir) et l'usure des pneus montés.
 if not d.base and pace then m.base=pace-m.fuelK*m.fuel*0.5-S.lapDeg(m,m.km0F,m.km0R,m.age0,0) end
 return m
end
return M
