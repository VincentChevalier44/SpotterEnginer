-- Radio de la voiture regardée (1.3.9) : quand le joueur ne pilote pas, après 2 s sur la même voiture ; sortie
-- immédiate ; arrêt au stand normal : il pilote toujours.
local Spectator=require('src/spectator')
local check=require('tests/helpers').check
local T={}
local function frame()
 local F={player=0,focus=-1,count=3,cars={}}
 for i=0,2 do F.cars[i]={valid=true,retired=false,ai=false,inPit=false,kmh=150} end
 return F
end
function T.spectator_only_when_not_driving()
 local st=Spectator.new(); local F=frame(); local cfg={spectatorRadio=true}
 F.focus=1
 check(Spectator.target(st,F,cfg,0)==-1 and Spectator.target(st,F,cfg,5)==-1,'driving: never')
 F.cars[0].inPit=true; F.cars[0].kmh=0
 check(Spectator.target(st,F,cfg,10)==-1,'pit stop: still driving')
 check(Spectator.target(st,F,cfg,19)==-1,'parked 9 s: still driving')
 check(Spectator.target(st,F,cfg,21)==-1,'parked 11 s: waits 2 s on the same car')
 check(Spectator.target(st,F,cfg,23.5)==1,'parked, camera on car 2 for 2 s: its radio')
 F.cars[0].inPit=false; F.cars[0].kmh=60
 check(Spectator.target(st,F,cfg,23.6)==-1,'back at the wheel: own radio at once')
 F.cars[0].retired=true
 Spectator.target(st,F,cfg,30)
 check(Spectator.target(st,F,cfg,32.1)==1,'retired: watched car after 2 s')
 F.focus=2
 check(Spectator.target(st,F,cfg,32.2)==-1 and Spectator.target(st,F,cfg,34.3)==2,'camera changed: 2 s on the new car')
 -- Arrêté dans la voie des stands (retour aux stands d'une pénalité, sans être au stand) : garé aussi.
 F.cars[0].retired=false; F.cars[0].pitlane=true; F.cars[0].kmh=0
 Spectator.target(st,F,cfg,35)
 check(Spectator.target(st,F,cfg,44)==-1 and Spectator.target(st,F,cfg,46)==-1,'stopped in the pit lane 11 s: waits 2 s')
 check(Spectator.target(st,F,cfg,48.1)==2,'stopped in the pit lane: watched car')
 F.cars[0].pitlane=false; F.cars[0].kmh=80
 cfg.spectatorRadio=false
 check(Spectator.target(st,F,cfg,50)==-1,'setting off: never')
 F.cars[0].ai=true; cfg.spectatorRadio=true; F.focus=0
 check(Spectator.target(st,F,cfg,60)==-1 and Spectator.target(st,F,cfg,63)==-1,'camera on the player: never')
end
return T
