-- Voiture regardée (1.3.9, comme SuperHUD) : la voiture que suit la caméra de CSP (sim.focusedCar), pour les overlays
-- Ingénieur et Stratégie seulement. La radio, le stratège, le carburant de la radio et les clés publiées pour les autres
-- apps (pitplan, strategy) restent toujours sur la voiture du joueur. Module pur.
-- Par voiture : trois derniers tours (moyenne), tour de sortie des stands (tours du relais). Voiture suivie : sa
-- consommation mesurée d'un passage de ligne au suivant (jamais pendant un passage aux stands, ravitaillement possible).
local M={}
function M.new() return {index=-1,cars={},view={},fuelAt=nil,fuelLap=nil,lapSeen=nil,fpl=nil} end
local function hist(s,i)
 local h=s.cars[i]
 if not h then h={laps=-1,last={0,0,0},n=0,stintFrom=0,wasPit=false,lapPit=false}; s.cars[i]=h end
 return h
end
-- Données physiques d'une autre voiture lues (en ligne, CSP en donne souvent zéro) : carburant ou pneus.
function M.hasPhysics(v) return v~=nil and v.ok==true and ((v.fuel or 0)>0 or ((v.tyres[1] or {}).core or 0)>0) end
-- À chaque image : historique de toutes les voitures, puis voiture suivie (follow : réglage « Suivre la caméra »).
function M.step(s,F,follow)
 for i=0,(F.count or 0)-1 do
  local c=F.cars[i]
  if c and c.valid then
   local h=hist(s,i)
   if h.laps<0 or c.laps<h.laps then h.laps=c.laps; h.n=0; h.stintFrom=c.laps; h.lapPit=c.pitlane==true end
   if c.laps>h.laps then
    -- Tour bouclé : gardé s'il est complet et sans passage aux stands (rythme de course).
    if (c.lastMs or 0)>0 and not h.lapPit then h.n=h.n+1; h.last[(h.n-1)%3+1]=c.lastMs/1000 end
    h.laps=c.laps; h.lapPit=c.pitlane==true
   end
   if c.pitlane then h.lapPit=true end
   if h.wasPit and not c.pitlane then h.stintFrom=c.laps end
   h.wasPit=c.pitlane==true
  end
 end
 local idx=follow and F.focus or -1
 local v=F.view
 if not (idx and idx>=0 and idx~=F.player and v and v.ok and F.cars[idx] and F.cars[idx].valid) then idx=-1 end
 if idx~=s.index then s.index=idx; s.fuelAt=nil; s.fuelLap=nil; s.lapSeen=nil; s.fpl=nil end
 if idx<0 then return end
 local c=F.cars[idx]
 if c.pitlane then s.fuelAt=nil; s.fuelLap=nil; s.lapSeen=c.laps; return end
 if s.lapSeen~=nil and c.laps>s.lapSeen and (v.fuel or 0)>0 then
  if s.fuelAt and s.fuelLap and c.laps>s.fuelLap then
   local per=(s.fuelAt-v.fuel)/(c.laps-s.fuelLap)
   if per>0 then s.fpl=per end
  end
  s.fuelAt=v.fuel; s.fuelLap=c.laps
 end
 s.lapSeen=c.laps
end
-- Voiture affichée par les overlays : table réutilisée, à lire tout de suite.
--   index, own (le joueur), car (F.cars), data (F.me ou F.view), avg3 (s, nil avant trois tours), stint (tours du
--   relais), fpl (consommation mesurée d'une autre voiture, nil avant un tour), partial (données physiques absentes).
function M.subject(s,F)
 local o=s.view
 local own=s.index<0
 local i=own and F.player or s.index
 o.index=i; o.own=own; o.car=F.cars[i]; o.data=own and F.me or F.view
 local h=s.cars[i]
 o.avg3=h and h.n>=3 and (h.last[1]+h.last[2]+h.last[3])/3 or nil
 o.stint=h and o.car and math.max(0,o.car.laps-h.stintFrom) or 0
 o.fpl=not own and s.fpl or nil
 o.partial=not own and not M.hasPhysics(F.view)
 return o
end
return M
