-- Conseils de pilotage tirés de la télémétrie (ingénieur), module pur : le tour est coupé en mini-secteurs ; pour
-- chacun, temps, vitesse minimale et point de freinage (distance parcourue dans le secteur au début du freinage). La
-- référence est le meilleur passage de chaque mini-secteur sur les tours propres. Une perte répétée sur trois tours
-- propres au même endroit donne un conseil : freinage trop tôt (point de freinage plus tôt que la référence), vitesse
-- en courbe trop basse (vitesse minimale plus basse), sinon perte de temps au secteur.
local M={}
M.segments=40
function M.new()
 local c={seg=-1,segAt=0,minKmh=0,brakeAt=-1,braking=false,lap={},ref={},history={},lastAdvice=-1,laps=0}
 return c
end
function M.reset(c) local n=M.new(); for k,v in pairs(n) do c[k]=v end end
local function segmentOf(spline) return math.floor((spline%1)*M.segments) end
-- Chaque image : spline, kmh, brake (0..1), now (s), length (m du tour).
function M.update(c,spline,kmh,brake,now,length)
 local seg=segmentOf(spline)
 if seg~=c.seg then
  if c.seg>=0 and (seg==(c.seg+1)%M.segments) then
   c.lap[c.seg]={time=now-c.segAt,minKmh=c.minKmh,brakeAt=c.brakeAt}
  end
  c.seg=seg; c.segAt=now; c.minKmh=kmh; c.brakeAt=-1; c.braking=brake>0.3
 else
  if kmh<c.minKmh then c.minKmh=kmh end
  if brake>0.3 and not c.braking and c.brakeAt<0 then
   local frac=(spline%1)*M.segments-seg
   c.brakeAt=frac*length/M.segments
  end
  c.braking=brake>0.3
 end
end
-- Tour terminé : clean = tour propre (sans arrêt, neutralisation ni coupe). Renvoie un conseil {kind, segment, loss}
-- ou nil.
function M.lap(c,clean,threshold)
 local lap=c.lap; c.lap={}
 if not clean then return nil end
 local complete=0
 for k=0,M.segments-1 do if lap[k] then complete=complete+1 end end
 if complete<M.segments*0.9 then return nil end
 c.laps=c.laps+1
 c.history[#c.history+1]=lap; if #c.history>3 then table.remove(c.history,1) end
 -- Référence : meilleur passage de chaque mini-secteur (après la comparaison, pour ne pas se comparer à soi-même).
 local advice=nil
 if #c.history>=3 and c.laps-c.lastAdvice>=3 then
  local worst,ws=threshold,nil
  for k=0,M.segments-1 do
   local r=c.ref[k]
   if r then
    local sum,n=0,0
    for h=1,#c.history do local s=c.history[h][k]; if s then sum=sum+(s.time-r.time); n=n+1 end end
    if n==#c.history and sum/n>worst then worst=sum/n; ws=k end
   end
  end
  if ws then
   local r=c.ref[ws]; local s=c.history[#c.history][ws]
   local kind='losingTime'
   if r.brakeAt>=0 and s.brakeAt>=0 and r.brakeAt-s.brakeAt>10 then kind='brakeLater'
   elseif s.minKmh<r.minKmh-4 then kind='carrySpeed' end
   advice={kind=kind,segment=ws,loss=worst}
   c.lastAdvice=c.laps
  end
 end
 for k=0,M.segments-1 do
  local s=lap[k]
  if s and (not c.ref[k] or s.time<c.ref[k].time) then c.ref[k]=s end
 end
 return advice
end
return M
