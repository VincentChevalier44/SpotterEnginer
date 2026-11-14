-- Voiture regardée (1.3.9, comme SuperHUD) : historique des tours, relais, consommation mesurée de la voiture suivie.
local Focus=require('src/focus')
local Helpers=require('tests/helpers')
local check=Helpers.check
local T={}
local function frame()
 local F={count=3,player=0,focus=-1,cars={},me={fuel=40,tyres={{core=80}}},
  view={ok=false,index=-1,fuel=0,tyres={{core=0},{core=0},{core=0},{core=0}}}}
 for i=0,2 do F.cars[i]={valid=true,laps=0,lastMs=0,pitlane=false} end
 return F
end
function T.focus_follows_the_camera_car_only_when_asked()
 local s=Focus.new(); local F=frame()
 Focus.step(s,F,true)
 local o=Focus.subject(s,F)
 check(o.own and o.index==0 and o.data==F.me,'camera on the player: own car')
 F.focus=2; F.view.ok=true; F.view.fuel=30; F.view.tyres[1].core=85
 Focus.step(s,F,false)
 check(Focus.subject(s,F).own,'follow off: own car')
 Focus.step(s,F,true)
 o=Focus.subject(s,F)
 check(not o.own and o.index==2 and o.data==F.view and not o.partial,'follow on: the watched car')
 F.view.fuel=0; F.view.tyres[1].core=0
 check(Focus.subject(s,F).partial,'no physics (online): partial data')
 F.cars[2].valid=false; Focus.step(s,F,true)
 check(Focus.subject(s,F).own,'watched car gone: own car')
end
function T.focus_fuel_measured_lap_to_lap()
 local s=Focus.new(); local F=frame()
 F.focus=1; F.view.ok=true; F.view.fuel=50; F.view.tyres[1].core=80
 F.cars[1].laps=3; Focus.step(s,F,true)
 check(Focus.subject(s,F).fpl==nil,'no full lap seen: no consumption')
 F.view.fuel=48; F.cars[1].laps=4; Focus.step(s,F,true)
 check(Focus.subject(s,F).fpl==nil,'first line crossing: start of the measure')
 F.view.fuel=45.5; F.cars[1].laps=5; Focus.step(s,F,true)
 check(math.abs((Focus.subject(s,F).fpl or 0)-2.5)<1e-9,'one full lap: 2.5 L per lap')
 -- Stands (ravitaillement) : la mesure repart.
 F.cars[1].pitlane=true; F.view.fuel=80; Focus.step(s,F,true)
 F.cars[1].pitlane=false; F.cars[1].laps=6; Focus.step(s,F,true)
 F.view.fuel=77; F.cars[1].laps=7; Focus.step(s,F,true)
 check(math.abs((Focus.subject(s,F).fpl or 0)-3)<1e-9,'after the stop: measured again from the next line')
 -- Autre voiture suivie : mesure oubliée.
 F.focus=2; Focus.step(s,F,true)
 check(Focus.subject(s,F).fpl==nil,'another car: its own measure')
end
function T.focus_last_three_laps_and_stint()
 local s=Focus.new(); local F=frame()
 local c=F.cars[0]
 Focus.step(s,F,true)
 for lap,ms in ipairs({90000,91000,92000,95000}) do c.laps=lap; c.lastMs=ms; Focus.step(s,F,true) end
 local o=Focus.subject(s,F)
 check(o.avg3 and math.abs(o.avg3-(91+92+95)/3)<1e-9,'average of the last three laps')
 check(o.stint==4,'stint laps: '..o.stint)
 c.pitlane=true; Focus.step(s,F,true); c.laps=5; c.lastMs=120000; Focus.step(s,F,true)
 c.pitlane=false; Focus.step(s,F,true)
 o=Focus.subject(s,F)
 check(o.stint==0,'stint restarts at the pit exit')
 check(math.abs(o.avg3-(91+92+95)/3)<1e-9,'pit lap not counted in the pace')
end
-- Barre d'accent masquée par défaut (comme SuperHUD) ; une barre restée à l'ancien défaut est masquée à la migration,
-- dans les réglages et dans chaque bureau ; un choix fait après la migration est gardé.
function T.accent_bar_off_by_default()
 local Config=require('src/config')
 check(Config.defaults().spotterAccent==false and Config.emptyDesktop().engineerAccent==false,'off by default')
 local old=Config.load({schema=3,spotterAccent=true})
 check(old.spotterAccent==false and old.schema==Config.version,'old default migrated off')
 local banks=Config.loadDesktops({['1']={strategyAccent=true},['2']={engineerAccent=true}},3)
 check(banks[1].strategyAccent==false and banks[2].engineerAccent==false,'migrated off on every desktop')
 local now=Config.load({schema=4,spotterAccent=true})
 check(now.spotterAccent==true,'chosen after the migration: kept')
 check(Config.loadDesktops({['1']={strategyAccent=true}},4)[1].strategyAccent==true,'chosen per desktop: kept')
end
-- Taille des overlays comme les blocs de SuperHUD : de 0,35 à 4 fois ; « Suivre la caméra » propre au bureau.
-- Radio de la voiture regardée : active par défaut ; un réglage resté coupé (ancien défaut) passe à actif.
function T.spectator_radio_on_by_default()
 local Config=require('src/config')
 check(Config.defaults().spectatorRadio==true,'on by default')
 check(Config.load({schema=4,spectatorRadio=false}).spectatorRadio==true,'old default migrated on')
 check(Config.load({schema=5,spectatorRadio=false}).spectatorRadio==false,'turned off after the migration: kept')
end
function T.overlay_scale_and_follow_setting()
 local Config=require('src/config')
 check(Config.valid('engineerScale',5)==4 and Config.valid('engineerScale',0.1)==0.35,'scale from 0.35 to 4')
 local d=Config.emptyDesktop()
 check(d.followCamera==true,'follow the camera: on by default on a new desktop')
 local per=false; for _,k in ipairs(Config.desktopKeys) do if k=='followCamera' then per=true end end
 check(per,'follow the camera: kept per desktop')
end
return T
