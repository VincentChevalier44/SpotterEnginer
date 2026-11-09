-- Chronométrage par points de passage : chaque voiture garde l'instant où elle a franchi chacun des N points du tour
-- (interpolé entre deux images). Écart réel entre deux voitures = temps écoulé depuis que celle de devant est passée à
-- l'endroit où se trouve celle de derrière. Progression continue (tours + position sur le tour) suivie image par
-- image, robuste au décalage entre le passage de la ligne et le compteur de tours d'AC. Module pur.
local U=require('src/util')
local M={}
M.points=400
function M.new() return {cars={},n=M.points} end
local function car(t,i)
 local c=t.cars[i]
 if not c then c={progress=nil,spline=0,time=0,cross={},seen=false,laps=U.ring(8),lastLap=-1,dirty=false}; t.cars[i]=c end
 return c
end
M.car=car
-- Remise à zéro (changement de session) : tout est oublié.
function M.reset(t) t.cars={} end
-- Une voiture : spline (0..1), laps (tours terminés), now (temps de simulation, s), valid (voiture lue), dirty (dans la
-- voie des stands ou sous neutralisation : le tour en cours ne compte pas dans le rythme).
function M.update(t,i,spline,laps,now,valid,dirty)
 local c=car(t,i)
 if dirty then c.dirty=true end
 if not valid or not U.finite(spline) then c.seen=false; return c end
 local fresh=laps+spline
 if not c.seen or c.progress==nil then
  c.progress=fresh; c.spline=spline; c.time=now; c.seen=true
  return c
 end
 local ds=U.wrap(spline-c.spline)
 -- Saut (retour aux stands, replacement) : reprise sur la valeur d'AC, sans passages inventés.
 if math.abs(ds)>0.05 or now<c.time then
  c.progress=fresh; c.spline=spline; c.time=now
  return c
 end
 local p0,p1=c.progress,c.progress+ds
 -- Dérive lente corrigée vers la valeur d'AC quand elles divergent de plus d'un demi-tour (compteur rattrapé).
 if math.abs(p1-fresh)>0.5 and math.abs(p1-fresh)<1.5 then p1=p1+(fresh-p1>0 and 1 or -1); p0=p1-ds end
 if ds>0 and now>c.time then
  local n=t.n
  local k0,k1=math.floor(p0*n),math.floor(p1*n)
  if k1-k0<=n then
   for k=k0+1,k1 do
    local f=(k/n-p0)/(p1-p0)
    c.cross[k%n]=c.time+(now-c.time)*f
   end
  end
 end
 c.progress=p1; c.spline=spline; c.time=now
 return c
end
-- Instant où la voiture a franchi en dernier la position (sur le tour) spline ; nil si inconnu.
function M.passedAt(t,i,spline)
 local c=t.cars[i]
 if not c or not c.seen then return nil end
 local n=t.n
 local x=(spline%1)*n
 local k=math.floor(x); local f=x-k
 local a=c.cross[k%n]; local b=c.cross[(k+1)%n]
 if not a then return nil end
 if b and b>=a and b-a<60 then return a+(b-a)*f end
 return a
end
-- Écart en temps de la voiture behind sur la voiture ahead (positif) ; laps : tours d'écart entiers (0 si même tour).
-- Renvoie gap (s) ou nil, laps.
function M.gap(t,ahead,behind,now)
 local a,b=t.cars[ahead],t.cars[behind]
 if not a or not b or not a.seen or not b.seen then return nil,0 end
 local d=a.progress-b.progress
 if d>=1 then return nil,math.floor(d) end
 if d<0 then return nil,0 end
 local at=M.passedAt(t,ahead,b.spline)
 if not at then return nil,0 end
 local g=now-at
 if g<0 or g>600 then return nil,0 end
 return g,0
end
-- Écart sur la piste (quel que soit le tour) : voiture physiquement devant à moins d'un demi-tour.
function M.trackGap(t,ahead,behind,now)
 local a,b=t.cars[ahead],t.cars[behind]
 if not a or not b or not a.seen or not b.seen then return nil end
 local d=U.wrap(a.spline-b.spline)
 if d<=0 then return nil end
 local at=M.passedAt(t,ahead,b.spline)
 if not at then return nil end
 local g=now-at
 if g<0 or g>120 then return nil end
 return g
end
-- Tour terminé : temps du tour (s) gardé (8 derniers) s'il est propre (ni voie des stands ni neutralisation pendant
-- le tour) ; renvoie vrai s'il est gardé.
function M.lap(t,i,lapTime,laps)
 local c=car(t,i)
 if laps==c.lastLap then return false end
 c.lastLap=laps
 local dirty=c.dirty; c.dirty=false
 if not dirty and U.finite(lapTime) and lapTime>10 and lapTime<1800 then U.push(c.laps,lapTime); return true end
 return false
end
-- Rythme : médiane des k derniers tours propres (robuste à un tour lent isolé).
function M.pace(t,i,k)
 local c=t.cars[i]
 if not c or c.laps.n==0 then return nil end
 k=math.min(k or 3,c.laps.n)
 local list={}
 for j=1,k do list[j]=U.recent(c.laps,j) end
 return U.median(list,k)
end
return M
