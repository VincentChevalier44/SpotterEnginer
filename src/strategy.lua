-- Stratégie d'arrêt (ingénieur) : meilleure fenêtre d'arrêt, tour optimal, nombre d'arrêts, ressortie dans le trafic,
-- undercut et overcut. Module pur, sans aucune fonction de CSP : le modèle est appris en course (src/stratdata.lua) et
-- donné ici sous forme de tables.
--
-- Temps d'un tour = rythme de base (pneus au mieux, sans carburant)
--                 + dégradation : perte d'adhérence de la courbe d'usure (WEAR_CURVE, % selon les km virtuels) aux km
--                   prévus pour ce tour, multipliée par la sensibilité du temps au tour (s par % d'adhérence perdu) ;
--                   les km virtuels par tour sont mesurés en course (ils contiennent déjà le style, la piste, la charge
--                   et la température) et projetés avec la tendance de la température de piste ; sans courbe : perte
--                   linéaire mesurée (s par tour d'âge) ;
--                 + carburant : masse embarquée (s par litre) ;
--                 + premier tour après l'arrêt : pneus à chauffer (warmup).
-- Arrêt = voie des stands (perte mesurée ou estimée) + pneus + ravitaillement du relais suivant, au moins le temps
--         d'arrêt minimal des règles d'AdvancedIA.
-- Contraintes : carburant du relais en cours (réservoir actuel), contenance du réservoir, adhérence plancher des pneus
-- (au-delà : relais trop long), arrêts obligatoires et leur fenêtre (règles d'AdvancedIA).
-- Recherche : programmation dynamique sur les tours restants (tour de chaque arrêt et nombre d'arrêts optimaux), puis
-- coût de chaque tour d'arrêt possible pour le premier arrêt (fenêtre : tours à moins de tolerance s de l'optimum).
local U=require('src/util')
local M={}
local INF=1e18
-- LUT { xs, ys } triée ; interpolation linéaire, bornée aux extrémités.
function M.lut(xs,ys)
 if not xs or #xs==0 or #xs~=#ys then return nil end
 local l={xs={},ys={},max=-INF}
 for k=1,#xs do l.xs[k]=xs[k]; l.ys[k]=ys[k]; if ys[k]>l.max then l.max=ys[k] end end
 return l
end
function M.eval(l,x)
 local xs,ys=l.xs,l.ys; local n=#xs
 if x<=xs[1] then return ys[1] end
 if x>=xs[n] then return ys[n] end
 local lo,hi=1,n
 while hi-lo>1 do local mid=math.floor((lo+hi)/2); if xs[mid]<=x then lo=mid else hi=mid end end
 local t=(x-xs[lo])/(xs[hi]-xs[lo])
 return ys[lo]+(ys[hi]-ys[lo])*t
end
-- Texte d'une LUT d'AC « 0=100|10=98.5 » ou lignes « 0|100 » ; renvoie la LUT ou nil.
function M.parseLut(text)
 if type(text)~='string' then return nil end
 local xs,ys={},{}
 local inline=text:match('^%s*%((.*)%)%s*$')
 if inline then
  for a,b in inline:gmatch('([%d%.%-eE]+)%s*=%s*([%d%.%-eE]+)') do xs[#xs+1]=tonumber(a); ys[#ys+1]=tonumber(b) end
 else
  for raw in (text..'\n'):gmatch('([^\n]*)\n') do
   local line=raw:gsub(';.*$','')
   local a,b=line:match('^%s*([%d%.%-eE]+)%s*|%s*([%d%.%-eE]+)')
   if a then xs[#xs+1]=tonumber(a); ys[#ys+1]=tonumber(b) end
  end
 end
 if #xs<2 then return nil end
 return M.lut(xs,ys)
end
-- Modèle par défaut (valeurs prudentes, remplacées par les mesures).
function M.defaultModel()
 return {base=100,fuelPerLap=2.5,fuelK=0.03,tank=100,fuel=50,fuelMargin=1.0,
  wearF=nil,wearR=nil,kmF=0.25,kmR=0.25,km0F=0,km0R=0,gripK=0.6,degLinear=0.05,age0=0,
  warmup=1.5,pitLane=22,tyreChange=10,fuelRate=0.5,minPit=0,changeTyres=true,
  wearGrowth=0,gripFloor=94,maxStint=0,trafficCost=1.5,trafficWindow=2.0,tolerance=2.0}
end
-- Perte d'adhérence (%) aux km virtuels donnés d'un essieu ; 0 sans courbe.
local function loss(curve,km) if not curve then return 0 end return math.max(0,curve.max-M.eval(curve,km)) end
-- Km virtuels moyens pendant le k-ième tour (0 = premier) d'un relais qui part de km0, à rate km par tour, avec une
-- croissance relative de l'usure de growth par tour (tendance de la température de piste).
local function kmAt(km0,rate,growth,k) return km0+rate*(k+0.5)*(1+growth*k*0.5) end
-- Dégradation (s) du k-ième tour d'un relais (pneus partis de km0F/km0R, âge0 tours pour la perte linéaire).
function M.lapDeg(m,km0F,km0R,age0,k)
 if m.wearF or m.wearR then
  local lf=loss(m.wearF,kmAt(km0F,m.kmF,m.wearGrowth,k))
  local lr=loss(m.wearR,kmAt(km0R,m.kmR,m.wearGrowth,k))
  local n=(m.wearF and 1 or 0)+(m.wearR and 1 or 0)
  return m.gripK*(lf+lr)/n
 end
 return m.degLinear*(age0+k)
end
-- Adhérence restante (%) au k-ième tour, ou nil sans courbe (plancher non vérifiable).
function M.lapGrip(m,km0F,km0R,k)
 if not (m.wearF or m.wearR) then return nil end
 local g=100
 if m.wearF then g=math.min(g,100-loss(m.wearF,kmAt(km0F,m.kmF,m.wearGrowth,k))) end
 if m.wearR then g=math.min(g,100-loss(m.wearR,kmAt(km0R,m.kmR,m.wearGrowth,k))) end
 return g
end
-- Sommes préfixes de la dégradation d'un relais (D[n] = somme des n premiers tours) et longueur maximale permise par
-- l'adhérence plancher (ou la longueur de relais maximale réglée).
local function prefix(m,km0F,km0R,age0,count)
 local D={[0]=0}; local life=count
 for k=0,count-1 do
  D[k+1]=D[k]+M.lapDeg(m,km0F,km0R,age0,k)
  local g=M.lapGrip(m,km0F,km0R,k)
  if g and g<m.gripFloor and life==count then life=k end
 end
 -- Sans courbe : perte linéaire au-delà de 4 s au tour = pneu fini.
 if not (m.wearF or m.wearR) and m.degLinear>0 then life=math.min(life,math.max(0,math.floor(4/m.degLinear)-age0)) end
 if m.maxStint and m.maxStint>0 then life=math.min(life,m.maxStint) end
 return D,life
end
M.prefix=prefix
-- Coût carburant d'un relais de n tours parti avec fuel litres : fuelK × somme de la masse moyenne de chaque tour.
local function fuelCost(m,n,fuel) return m.fuelK*(n*fuel-m.fuelPerLap*n*n*0.5) end
-- Temps d'arrêt immobile : pneus, ravitaillement de liters litres, borné par le temps minimal.
function M.stationary(m,liters)
 local t=(m.changeTyres and m.tyreChange or 0)+m.fuelRate*math.max(0,liters)
 return math.max(t,m.minPit or 0)
end
-- Le tour d'arrêt x (fin du tour x) compte pour un arrêt obligatoire.
local function counts(race,x)
 if (race.mandatory or 0)<=0 then return false end
 return x>=(race.windowOpen or 0) and x<=(race.windowClose or INF)
end
-- Résolution complète. race = {done (tours finis), total (tours de la course), mandatory (arrêts encore dus),
-- windowOpen, windowClose (tours)} ; traffic(n1) facultatif : pénalité (s) et détail de la ressortie si le premier
-- arrêt a lieu à la fin du tour done+n1.
function M.solve(m,race,traffic)
 local done=math.max(0,math.floor(race.done or 0))
 local total=math.max(done+1,math.floor(race.total or done+1))
 local R=total-done
 local plan={ok=false,done=done,total=total,remaining=R,stops=0,laps={},costs={},window=nil,optimal=nil,reason=''}
 if m.fuelPerLap<=0 or m.base<=0 then plan.reason='model'; return plan end
 local tankLaps=math.floor((m.tank-m.fuelMargin)/m.fuelPerLap)
 if tankLaps<1 then plan.reason='tank'; return plan end
 -- Relais neuf : dégradation et durée de vie (mêmes pour tout relais neuf).
 local Df,lifeF=prefix(m,0,0,0,math.min(R,tankLaps))
 -- Relais neuf de 120 tours au plus : sans limite de carburant ni d'usure, le calcul resterait proportionnel au carré
 -- des tours restants (course d'endurance) ; aucune stratégie réelle ne fait plus.
 local maxFresh=math.max(0,math.min(lifeF,tankLaps,R,120))
 if maxFresh<1 then plan.reason='life'; return plan end
 -- Relais en cours : pneus actuels, carburant actuel.
 local Dc,lifeC=prefix(m,m.km0F,m.km0R,m.age0,R)
 -- Carburant du relais en cours avec la même marge que l'ingénieur (pas de plan qui finit à 0,1 L pendant qu'il
 -- demande d'économiser).
 local fuelLaps=math.floor((m.fuel-m.fuelMargin)/m.fuelPerLap)
 -- Pneus déjà sous le plancher d'adhérence : le plancher ne force plus un arrêt à chaque tour (la dégradation, comptée
 -- dans le coût, décide) ; il ne limite que les relais à venir.
 local maxCurrent=math.max(1,math.min(R,lifeC>0 and lifeC or R,fuelLaps>0 and fuelLaps or 1))
 plan.fuelLaps=fuelLaps; plan.lifeLaps=lifeC; plan.tankLaps=tankLaps; plan.freshLife=lifeF
 -- f[x][q] : coût minimal de x (tours finis, arrêt fait à la fin du tour x) à l'arrivée, q arrêts obligatoires encore
 -- dus après cet arrêt ; nxt : longueur du relais suivant choisie.
 local Q=math.max(0,race.mandatory or 0)
 local f,nxt={},{}
 for x=total,done+1,-1 do
  f[x]={}; nxt[x]={}
  for q=0,Q do
   local best,bn=INF,nil
   for n=1,math.min(maxFresh,total-x) do
    local fuelLoad=math.min(m.tank,n*m.fuelPerLap+m.fuelMargin)
    local stint=n*m.base+Df[n]+fuelCost(m,n,fuelLoad)+m.warmup
    local pit=m.pitLane+M.stationary(m,fuelLoad-m.fuelMargin)
    local rest
    if x+n==total then rest=q==0 and 0 or INF
    else local q2=q; if counts(race,x+n) and q2>0 then q2=q2-1 end; rest=f[x+n][q2] end
    local c=pit+stint+rest
    if c<best then best=c; bn=n end
   end
   f[x][q]=best; nxt[x][q]=bn
  end
 end
 -- Premier relais : n1 tours encore à faire avec les pneus actuels (n1=R : aucun arrêt).
 local bestCost,bestN=INF,nil
 for n1=1,math.min(R,maxCurrent) do
  local stint=n1*m.base+Dc[n1]+fuelCost(m,n1,m.fuel)
  local c
  local detail=nil
  if n1==R then c=Q==0 and stint or INF
  else
   local x=done+n1
   local q=Q; if counts(race,x) and q>0 then q=q-1 end
   c=stint+(f[x] and f[x][q] or INF)
   -- Au premier arrêt, la voiture arrive avec le carburant qui reste : ravitaillement plus court que celui compté par
   -- f (arrivée à la marge).
   local n2=nxt[x] and nxt[x][q]
   if c<INF and n2 then
    local L=math.min(m.tank,n2*m.fuelPerLap+m.fuelMargin)-m.fuelMargin
    local left=math.max(0,m.fuel-n1*m.fuelPerLap-m.fuelMargin)
    c=c-(M.stationary(m,L)-M.stationary(m,math.max(0,L-left)))
   end
   if traffic and c<INF then local pen,info=traffic(n1); c=c+(pen or 0); detail=info end
  end
  plan.costs[n1]=c<INF and c or nil
  if detail then plan.detail=plan.detail or {}; plan.detail[n1]=detail end
  if c<bestCost then bestCost=c; bestN=n1 end
 end
 if not bestN then
  -- Sans arrêt obligatoire, des relais neufs mènent toujours à l'arrivée : l'échec vient de la fenêtre réglementaire.
  plan.reason=Q>0 and 'mandatory' or 'unreachable'
  return plan
 end
 plan.ok=true; plan.cost=bestCost
 -- Arrêts du plan optimal.
 if bestN<R then
  local x=done+bestN; local q=Q; if counts(race,x) and q>0 then q=q-1 end
  plan.laps[1]=x
  while x<total do
   local n=nxt[x] and nxt[x][q]
   if not n then break end
   x=x+n
   if x<total then plan.laps[#plan.laps+1]=x; if counts(race,x) and q>0 then q=q-1 end end
  end
 end
 plan.stops=#plan.laps
 plan.optimal=plan.laps[1]
 -- Fenêtre : tours d'arrêt contigus autour de l'optimum dont le coût reste à moins de tolerance s.
 if plan.optimal then
  local lo,hi=bestN,bestN
  while lo>1 and plan.costs[lo-1] and plan.costs[lo-1]-bestCost<=m.tolerance do lo=lo-1 end
  while hi<R-1 and plan.costs[hi+1] and plan.costs[hi+1]-bestCost<=m.tolerance do hi=hi+1 end
  plan.window={done+lo,done+hi}
 end
 -- Pertes au tour dues aux pneus : maintenant (relais en cours) et au tour optimal.
 plan.degNow=M.lapDeg(m,m.km0F,m.km0R,m.age0,0)
 plan.degAtStop=M.lapDeg(m,m.km0F,m.km0R,m.age0,math.max(0,bestN-1))
 plan.gripNow=M.lapGrip(m,m.km0F,m.km0R,0)
 plan.gripAtStop=M.lapGrip(m,m.km0F,m.km0R,math.max(0,bestN-1))
 -- Carburant : litres manquants pour finir sans arrêt (ou à l'arrêt prévu) avec le réservoir actuel.
 local need=(plan.optimal and bestN or R)*m.fuelPerLap
 plan.fuelShort=math.max(0,need-m.fuel)
 plan.fuelSpare=m.fuel-need
 -- Temps cible du tour en cours (modèle) : base + dégradation + carburant.
 plan.target=m.base+plan.degNow+m.fuelK*(m.fuel-m.fuelPerLap*0.5)
 return plan
end
-- Ressortie des stands : où le joueur reprend la piste s'il s'arrête à la fin du tour done+n1. me = {progress (tours,
-- continu), pace (s/tour), fresh (rythme pneus neufs)} ; rivals[k] = {index, progress, pace, stopLap (ou -1)} ; loss :
-- perte de l'arrêt (s). Renvoie pénalité (s) et info {position, ahead, aheadGap, behind, behindGap}.
function M.rejoin(m,me,rivals,done,n1,loss)
 local lapsToLine=(done+n1)-me.progress
 if lapsToLine<0 then lapsToLine=0 end
 -- Instant de la ressortie (s à partir de maintenant) : arrivée sur la ligne, plus la perte de l'arrêt. À cet instant,
 -- le joueur est sur la ligne (sortie des stands), là où il aurait été loss secondes plus tôt sans s'arrêter.
 local T=lapsToLine*me.pace+loss
 local mine=done+n1
 local penalty=0
 local info={position=1,ahead=-1,aheadGap=nil,behind=-1,behindGap=nil}
 for k=1,#rivals do
  local r=rivals[k]
  -- Progression du rival à l'instant de la ressortie (ses propres tours) ; son arrêt prévu (fin de son tour stopLap)
  -- tombe avant cet instant : il perd lui aussi le temps d'un arrêt.
  local p=r.progress+T/r.pace
  if r.stopLap and r.stopLap>=0 and r.stopLap>r.progress and r.stopLap<=p then p=p-loss/r.pace end
  -- Écart en temps sur la piste (rival devant > 0) à l'instant de la ressortie ; position au classement.
  local race=p-mine
  if race>0 then info.position=info.position+1 end
  local onTrack=U.wrap(race)*me.pace
  if onTrack>0 and (info.aheadGap==nil or onTrack<info.aheadGap) then info.aheadGap=onTrack; info.ahead=r.index end
  if onTrack<=0 and (info.behindGap==nil or -onTrack<info.behindGap) then info.behindGap=-onTrack; info.behind=r.index end
  local w=m.trafficWindow
  local factor=math.abs(race)>=0.5 and 0.5 or 1
  if onTrack>0 and onTrack<w and r.pace>me.fresh then
   penalty=penalty+(w-onTrack)/w*m.trafficCost*factor
  elseif onTrack<=0 and onTrack>-1 then
   penalty=penalty+0.3*factor
  end
 end
 return penalty,info
end
-- Duel avec un rival (undercut / overcut) : simulation tour par tour sur horizon tours. a et b : {gap (s, a devant de
-- b > 0 au départ), km0F, km0R, age0, stop (tour de l'arrêt, -1 : aucun)} pour le joueur (a) et le rival (b), même
-- modèle de voiture ; renvoie l'écart final (a devant > 0).
function M.duel(m,done,a,b,horizon,loss)
 local gap=a.gap
 local function lap(c,j)
  if c.stop>=0 and done+j>c.stop then
   local k=done+j-c.stop-1
   return M.lapDeg(m,0,0,0,k)+(k==0 and m.warmup or 0)
  end
  return M.lapDeg(m,c.km0F,c.km0R,c.age0,j-1)
 end
 for j=1,horizon do
  local ta=lap(a,j)+(a.stop==done+j and loss or 0)
  local tb=lap(b,j)+(b.stop==done+j and loss or 0)
  gap=gap+(tb-ta)
 end
 return gap
end
-- État de l'undercut / overcut sur la voiture devant (gap > 0 : elle est devant de gap s) et de la menace d'undercut de
-- la voiture derrière (1.3.1 : trois scénarios cohérents, revue de la 1.3.0). R : tours restants (horizon borné, rien
-- au-delà de l'arrivée). Arrêt du rival inconnu (pas de plan d'AdvancedIA) : il répond au tour suivant (cas prudent).
--   undercut : le joueur s'arrête au tour en cours (done+1), le rival à son arrêt (ou done+2) ; marge finale undercutGap
--             (joueur devant > 0), gain sur la situation actuelle undercutGain ; possible au-delà de DUEL_MARGIN s ;
--   overcut  : le rival s'arrête d'abord (son arrêt, ou done+1), le joueur au tour suivant ; même seuil ;
--   menace   : le rival derrière s'arrête au tour en cours, le joueur répond au tour suivant ; menace s'il passe devant.
-- Même modèle de voiture pour les deux (rythme de base égal) : seuls les pneus et la perte de l'arrêt comptent.
M.DUEL_MARGIN=1.0
function M.duels(m,done,me,ahead,behind,loss,horizon,R)
 horizon=horizon or 8
 local last=R and R>0 and done+R or nil
 local function cap(h) h=math.min(h,horizon+2); if last then h=math.min(h,last-done) end; return h end
 local out={}
 if ahead and ahead.gap and ahead.gap<6 then
  local rivalStop=ahead.stop>=0 and ahead.stop or done+2
  if not last or rivalStop<last then
   local A={gap=-ahead.gap,km0F=me.km0F,km0R=me.km0R,age0=me.age0,stop=done+1}
   local B={gap=0,km0F=ahead.km0F,km0R=ahead.km0R,age0=ahead.age0,stop=rivalStop}
   local h=cap(math.max(rivalStop-done+2,3))
   if h>=2 then
    out.undercutGap=M.duel(m,done,A,B,h,loss)
    out.undercutGain=out.undercutGap+ahead.gap
    out.undercut=out.undercutGap>M.DUEL_MARGIN
   end
  end
  local first=ahead.stop>=0 and ahead.stop or done+1
  if not last or first+1<last then
   local A2={gap=-ahead.gap,km0F=me.km0F,km0R=me.km0R,age0=me.age0,stop=first+1}
   local B2={gap=0,km0F=ahead.km0F,km0R=ahead.km0R,age0=ahead.age0,stop=first}
   local h=cap(math.max(first-done+3,4))
   if h>=2 then
    out.overcutGap=M.duel(m,done,A2,B2,h,loss)
    out.overcut=not out.undercut and out.overcutGap>M.DUEL_MARGIN
   end
  end
 end
 if behind and behind.gap and behind.gap<6 and (not last or done+2<last) then
  local A={gap=behind.gap,km0F=me.km0F,km0R=me.km0R,age0=me.age0,stop=done+2}
  local B={gap=0,km0F=behind.km0F,km0R=behind.km0R,age0=behind.age0,stop=done+1}
  local g=M.duel(m,done,A,B,cap(4),loss)
  out.threatGap=g
  out.threat=g<0
 end
 return out
end
return M
