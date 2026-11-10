-- Présence latérale (spotter) : voitures à côté du joueur, dans son repère (avant, côté), avec hystérésis ; annonces
-- « voiture à gauche / à droite », « trois de front », « toujours là », « dégagé ». Module pur : positions données.
--   car = {x, z, lookX, lookZ} pour le joueur (repère au sol) ; autres : {x, z, valid, pit}.
local M={}
-- laneMin : écart latéral minimal d'une voiture à côté (deux voitures côte à côte ont leurs centres à 1,8 m au moins ;
-- en dessous, c'est une voiture devant ou derrière dans l'aspiration). confirm : recouvrement tenu avant l'annonce
-- (rien pour un frôlement) ; release : voie libre tenue avant « dégagé » (pas de dégagé qui clignote).
M.defaults={length=4.7,laneMax=4.2,laneMin=1.3,enter=0,leave=0.8,confirm=0.25,release=0.6,stillEvery=3.5,stillMax=2,minKmh=40}
function M.new()
 return {left=false,right=false,leftCar=-1,rightCar=-1,stillLeft=0,stillRight=0,
  stillAtL=0,stillAtR=0,list={},count=0,candL=nil,candR=nil,freeL=nil,freeR=nil}
end
-- Voitures proches : coordonnées longitudinales (avant +) et latérales (gauche +) dans le repère du joueur.
-- Renvoie les events à annoncer (table réutilisée) : 'left','right','three','clearLeft','clearRight','clear','stillLeft','stillRight'.
local events={}
function M.step(p,me,cars,count,playerIndex,now,cfg)
 cfg=cfg or M.defaults
 for k=#events,1,-1 do events[k]=nil end
 local lx,lz=me.lookX,me.lookZ
 local norm=math.sqrt(lx*lx+lz*lz)
 if norm<1e-6 then return events end
 lx,lz=lx/norm,lz/norm
 -- Gauche du conducteur : dans AC, +X est la gauche d'une voiture qui regarde vers +Z (notes vérifiées
 -- d'AdvancedIA, docs/API_NOTES.md) ; la base (-look.z, look.x) pointe à droite, sa gauche est donc (look.z, -look.x).
 -- cfg.flip : inversion de secours (réglage), si une installation montrait l'inverse.
 local sx,sz=lz,-lx
 if cfg.flip then sx,sz=-sx,-sz end
 local overlapL,overlapR=false,false
 local bestL,bestR=nil,nil
 local idL,idR=-1,-1
 local n=0
 for i=0,count-1 do
  local c=cars[i]
  -- Voitures dans la voie des stands ignorées (F.cars : pitlane ; tests : pit).
  if i~=playerIndex and c and c.valid and not c.pitlane and not c.pit then
   local dx,dz=c.x-me.x,c.z-me.z
   if dx*dx+dz*dz<400 then
    local long=dx*lx+dz*lz
    local lat=dx*sx+dz*sz
    n=n+1
    local item=p.list[n]; if not item then item={}; p.list[n]=item end
    item.index=i; item.long=long; item.lat=lat
    local alat=math.abs(lat)
    if alat>=cfg.laneMin and alat<=cfg.laneMax then
     -- Recouvrement longitudinal (avec marge d'entrée, plus large pour garder une voiture déjà annoncée).
     local side=lat>0 and 'L' or 'R'
     local held=side=='L' and p.left or side=='R' and p.right
     local margin=held and cfg.leave or cfg.enter
     if math.abs(long)<cfg.length+margin then
      if side=='L' then overlapL=true; if not bestL or alat<bestL then bestL=alat; idL=i end
      else overlapR=true; if not bestR or alat<bestR then bestR=alat; idR=i end end
     end
    end
   end
  end
 end
 p.count=n
 local wasL,wasR=p.left,p.right
 -- Sous minKmh (épingle, départ) : l'état est tenu tel quel, ni nouvelle annonce ni « dégagé », ni « toujours là ».
 local slow=me.kmh<cfg.minKmh
 if slow then overlapL=wasL; overlapR=wasR; p.candL=nil; p.candR=nil end
 local confirm=cfg.confirm or 0; local release=cfg.release or 0
 -- Côté tenu après confirm s de recouvrement ; libéré après release s sans recouvrement.
 if overlapL then
  p.freeL=nil
  if not wasL then p.candL=p.candL or now; if now-p.candL>=confirm then p.left=true; p.candL=nil; p.stillLeft=0; p.stillAtL=now; p.leftCar=idL end end
 else
  p.candL=nil
  if wasL then p.freeL=p.freeL or now; if now-p.freeL>=release then p.left=false; p.freeL=nil; p.leftCar=-1 end end
 end
 if overlapR then
  p.freeR=nil
  if not wasR then p.candR=p.candR or now; if now-p.candR>=confirm then p.right=true; p.candR=nil; p.stillRight=0; p.stillAtR=now; p.rightCar=idR end end
 else
  p.candR=nil
  if wasR then p.freeR=p.freeR or now; if now-p.freeR>=release then p.right=false; p.freeR=nil; p.rightCar=-1 end end
 end
 local newL=p.left and not wasL; local newR=p.right and not wasR
 -- Trois de front seulement si l'autre côté est vraiment recouvert (pas pendant son relâchement).
 if p.left and p.right and (newL and overlapR or newR and overlapL) then events[#events+1]='three'
 else
  if newL then events[#events+1]='left' end
  if newR then events[#events+1]='right' end
 end
 local goneL=wasL and not p.left; local goneR=wasR and not p.right
 if goneL and goneR then events[#events+1]='clear'
 elseif goneL then events[#events+1]=p.right and 'clearLeft' or 'clear'
 elseif goneR then events[#events+1]=p.left and 'clearRight' or 'clear' end
 -- « Toujours là » : la voiture reste à côté au-delà de stillEvery s (au plus stillMax rappels).
 if not slow and p.left and not newL and now-p.stillAtL>=cfg.stillEvery and p.stillLeft<cfg.stillMax then p.stillLeft=p.stillLeft+1; p.stillAtL=now; events[#events+1]='stillLeft' end
 if not slow and p.right and not newR and now-p.stillAtR>=cfg.stillEvery and p.stillRight<cfg.stillMax then p.stillRight=p.stillRight+1; p.stillAtR=now; events[#events+1]='stillRight' end
 return events
end
return M
