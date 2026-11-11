-- Revue de l'ingénieur et de la stratégie (constats 1 à 4 et 6 à 15) : un test par correctif de comportement.
local S=require('src/strategy')
local SD=require('src/stratdata')
local St=require('src/strategist')
local Engineer=require('src/engineer')
local Timing=require('src/timing')
local Voice=require('src/voice')
local Say=require('src/say')
local Config=require('src/config')
local Helpers=require('tests/helpers')
local check,near=Helpers.check,Helpers.near
local T={}
-- Radio factice : tout ce qui est dit finit dans v.log (aucun clip, aucun délai entre deux annonces).
local function radio()
 local v=Voice.new({play=function() return {} end,playing=function() return false end,stop=function() end})
 v.repeatGap=0; v.infoGap=0; v.quiet=0
 return v,Say.new(v,{},'vox','FR',nil)
end
local function said(v,key)
 local n=0
 for _,q in ipairs(v.log) do if q.key==key then n=n+1 end end
 for _,q in ipairs(v.queue) do if q.key==key then n=n+1 end end
 return n
end
local function tyre(vkm) return {core=85,inner=85,mid=85,outer=85,opt=85,vkm=vkm or 0,flat=0,blister=0,grain=0,blown=false,wear=1} end
-- Course complète sur les vrais modules (chronométrage, stratège, ingénieur) : le joueur (voiture 0) et des rivaux
-- tournent en lap s au tour, 2,5 L par tour, 0,5 km virtuel par tour ; step(n) avance de n secondes.
local function world(opts)
 opts=opts or {}
 local v,sayer=radio()
 local lap=opts.lap or 100
 local F={isRace=true,started=true,finishedSession=false,player=0,count=1+#(opts.rivals or {}),cars={},clock=0,session=opts.session or 2,
  laps=opts.laps or 30,timed=opts.timed or false,timeLeft=opts.timeLeft or 0,additional=opts.additional or false,
  fuelRate=1,road=30,ambient=22,trackLength=4000,rainComing=false,rain=0,grip=1,wetness=0,transition=0,windKmh=0,windX=0,windZ=0,
  me={tyres={tyre(),tyre(),tyre(),tyre()},brakes={0,0,0,0},damage={0,0,0,0,0},fuel=opts.fuel or 60,maxFuel=100,fuelPerLapAC=2.5,fuelMaps=1,
   hasBias=false,brake=0,sector=0,lapValid=true,kers=false,p2p=0,drsPresent=false}}
 local function car(i,spline,position) return {index=i,valid=true,laps=0,spline=spline,position=position,pitlane=false,kmh=150,lastMs=0,bestMs=0,
  finished=false,retired=false,lookX=0,lookZ=1} end
 F.cars[0]=car(0,0.5,1+#(opts.rivals or {}))
 for k,r in ipairs(opts.rivals or {}) do F.cars[k]=car(k,r.spline,k) end
 local cfg=Config.defaults()
 for k,x in pairs(opts.cfg or {}) do cfg[k]=x end
 local ctx={F=F,cfg=cfg,say=sayer,voice=v,timing=Timing.new(),link={d=opts.d},now=0,real=0,keep=opts.keep}
 local w={F=F,ctx=ctx,voice=v,me=F.cars[0],engineer=Engineer.new()}
 w.t=w.engineer.strategist
 -- frame(w) : appelé à chaque image après le chronométrage (par défaut : le stratège seul).
 function w.step(seconds,frame)
  for _=1,seconds do
   F.clock=F.clock+1; ctx.now=F.clock; ctx.real=F.clock
   if F.timed then F.timeLeft=F.timeLeft-1 end
   for i=0,F.count-1 do
    local c=F.cars[i]
    if not c.pitlane then
     c.spline=c.spline+1/lap
     if c.spline>=1 then c.spline=c.spline-1; c.laps=c.laps+1; c.lastMs=lap*1000; c.bestMs=lap*1000 end
    end
    Timing.update(ctx.timing,i,c.spline,c.laps,F.clock,c.valid,c.pitlane)
    Timing.lap(ctx.timing,i,c.lastMs/1000,c.laps)
   end
   if not w.me.pitlane then
    F.me.fuel=F.me.fuel-2.5/lap
    for k=1,4 do F.me.tyres[k].vkm=F.me.tyres[k].vkm+(opts.wear or 0.5)/lap end
   end
   if frame then frame(w) else St.step(w.t,ctx) end
   Voice.step(v,ctx.real)
  end
 end
 return w
end
-- 1. Fenêtre obligatoire : AdvancedIA compte l'arrêt sur les tours entiers du leader, à l'arrivée à l'emplacement.
function T.window_opens_on_whole_leader_laps()
 local function d(over) local x={pitState='pending',pitWaived=false,mandatoryStops=1,pitDue=0,pitCsp=false,pitPosition=0.1,pitOpen=0.42,pitClose=0.58}
  for k,val in pairs(over or {}) do x[k]=val end; return x end
 local F={laps=20,timed=false,timeLeft=0}
 -- 20 tours, 42 % : ouverte quand le leader a 9 tours. Joueur à un demi-tour : fin de son tour 9 (8 : leader à 8,5).
 local _,open,close=St.rules(d(),3,20,100,F,0.5)
 check(open==9,'half a lap behind the leader: lap 9, got '..open)
 check(close==10,'closing unchanged (cautious): '..close)
 -- Leader : il arrive à son emplacement avant la ligne, avec 8 tours comptés à la fin de son 9e tour : tour 10.
 _,open=St.rules(d(),3,20,100,F,0)
 check(open==10,'leader: one lap after the threshold, got '..open)
 _,open=St.rules(d(),3,20,100,F,0.3)
 check(open==9,'0.3 lap behind: lap 9, got '..open)
 -- Fenêtre déjà ouverte pour AdvancedIA : un arrêt ce tour-ci compte toujours.
 _,open=St.rules(d({pitState='open',pitDue=1,pitPosition=0.45}),8,20,100,F,0.05)
 check(open==9,'window open now: this lap counts, got '..open)
 -- Course au temps : l'avancement est lu maintenant ; la part du tour en cours déjà faite compte (un recalcul en
 -- milieu de tour donnait l'ouverture un tour trop tôt).
 local Ft={laps=0,timed=true,timeLeft=1800}
 local dt=d({pitPosition=0.5,pitOpen=0.6,pitClose=0.8})
 local _,o0=St.rules(dt,10,40,100,Ft,0,0)
 local _,o8=St.rules(dt,10,40,100,Ft,0,0.8)
 check(o0==14 and o8==15,'timed race, start of the lap / 80 % of the lap: '..o0..' / '..o8)
 -- Fenêtre de CSP (temps de simulation, ms) : même règle.
 local dc=d({pitCsp=true,pitPosition=1000000,pitOpen=1360000,pitClose=2000000})
 local _,c0=St.rules(dc,10,40,100,Ft,0,0)
 local _,c8=St.rules(dc,10,40,100,Ft,0,0.8)
 check(c0==14 and c8==15,'CSP window: '..c0..' / '..c8)
end
-- 2. Course au temps avec tour de plus : temps écoulé, le dernier tour reste le dernier (il restait toujours 2 tours).
function T.timed_race_extra_lap_is_the_last()
 local w=world({timed=true,timeLeft=1020,additional=true,laps=0,fuel=80})
 -- Départ à mi-tour : ligne à 50 s, puis toutes les 100 s ; le temps s'écoule à 1020 s, à 70 % du tour 11.
 w.step(1000)
 check(w.me.laps==10 and w.t.plan.total==12,'before the time is up: this lap and the extra one, total '..tostring(w.t.plan.total))
 w.step(40)
 check(w.t.overLap==10,'lap of the time-up latched: '..tostring(w.t.overLap))
 check(w.t.plan.total==12,'time up, lap 11 running: 12 laps, got '..w.t.plan.total)
 w.step(30)
 check(w.me.laps==11 and w.t.plan.total==12,'extra lap running: still 12 laps (it was 13), got '..w.t.plan.total)
 w.step(60)
 check(w.t.plan.total==12 and w.t.plan.optimal==nil and said(w.voice,'box')==0,'no stop and no box on the last lap')
 -- Sans tour de plus : le tour de l'échéance est le dernier.
 check(St.total({pace=100,overLap=10},{timed=true,timeLeft=-5,additional=false,laps=0},{laps=10,spline=0.4})==11,'no extra lap')
end
-- 3. « Box » engagé puis plan sans arrêt : l'engagement est libéré une fois le tour passé, et avec les appels coupés.
function T.box_commitment_released_without_a_stop()
 local v,sayer=radio()
 local me={valid=true,laps=13,spline=0.8,pitlane=false}
 local F={isRace=true,player=0,cars={[0]=me},me={fuel=20,fuelPerLapAC=2},fuelRate=1,laps=25,timed=false}
 local ctx={F=F,cfg={boxCalls=true,neutralBox=true,tolerance=2},link={d={pitsClosed=false,neutral=false}},say=sayer,real=0}
 local e=Engineer.new(); local t=e.strategist
 t.ready=true; t.plan={ok=true,optimal=15,window={14,16},costs={},total=25}
 St.boxCalls(t,ctx)
 check(t.boxLap==15 and said(v,'box')==1,'box next lap committed')
 check(Engineer.fuelStatus(e,F,{fuelMargin=0}).target==2,'fuel judged to the committed stop')
 -- Le pilote économise : le plan n'a plus d'arrêt ; il reste dehors.
 t.plan={ok=true,optimal=nil,costs={},total=25}
 me.laps=14; me.spline=0.3; St.boxCalls(t,ctx)
 check(t.boxLap==15,'still committed during the stop lap')
 me.laps=15; St.boxCalls(t,ctx)
 check(t.boxLap==false,'released once the lap is over, even without a planned stop')
 local fs=Engineer.fuelStatus(e,F,{fuelMargin=0})
 check(fs.target==10 and not fs.toStop,'fuel judged to the finish again: '..tostring(fs.target))
 check(St.pitplan(t,ctx,true):find('state=none',1,true),'no stale plan published')
 -- Appels « box » coupés : engagement libéré aussi.
 t.boxLap=20; ctx.cfg.boxCalls=false; St.boxCalls(t,ctx)
 check(t.boxLap==false,'released when the box calls are switched off')
end
-- 4 et 10. Plan publié (contrat v1) : boxnow seulement pour le tour en cours ; done dans la voie des stands, gardé.
function T.pitplan_boxnow_and_done()
 local t=St.new()
 local me={valid=true,laps=11,spline=0.05,pitlane=false}
 local F={isRace=true,player=0,cars={[0]=me},clock=900}
 local ctx={F=F,cfg={boxCalls=true}}
 local function get() local s=St.pitplan(t,ctx,true); check(#s<=160,'160 bytes'); return s end
 t.ready=true; t.plan={ok=true,optimal=12,window={10,14}}
 -- Arrêt dit sous neutralisation pour ce tour : boxnow dès le début du tour.
 t.neutralBox=true; t.boxLap=12
 check(get()=='v=1;lap=12;compound=-;state=boxnow;window=10-14;boxcalls=1;stamp=900','neutral box on this lap: '..get())
 -- Arrêt fait ; la neutralisation dure, l'arrêt suivant est au tour 30 : prévu, jamais boxnow.
 me.pitlane=true; t.boxLap=false; check(get():find('lap=12;compound=-;state=done',1,true),'pit lane: done')
 me.pitlane=false; me.laps=12; me.spline=0.3; t.plan={ok=true,optimal=30,window={27,33}}
 check(get()=='v=1;lap=30;compound=-;state=planned;window=27-33;boxcalls=1;stamp=900','next stop under the same neutralisation: '..get())
 -- Appel ignoré (le pilote reste dehors) : le plan suivant est prévu, pas boxnow.
 t.plan={ok=true,optimal=14,window={13,15}}; check(get():find('lap=14;compound=-;state=planned',1,true),'ignored neutral box: planned')
 -- Ligne passée dans la voie avant le ravitaillement : le recalcul (réservoir presque vide) prévoit un arrêt plus
 -- tard ; l'état reste done dans la voie, et après la sortie quand le plan n'a plus d'arrêt.
 t.neutralBox=false; t.stopDone=false
 me.laps=13; me.spline=0.95; me.pitlane=true; check(get():find('lap=14;compound=-;state=done',1,true),'stop lap, pit lane: done')
 me.laps=14; me.spline=0.02; t.plan={ok=true,optimal=16,window={15,16}}
 check(get():find('lap=15;compound=-;state=done',1,true),'line crossed in the lane, low-fuel plan: still done: '..get())
 me.pitlane=false; me.spline=0.1; t.plan={ok=true,optimal=nil}
 check(get():find('lap=15;compound=-;state=done;window=0-0',1,true),'out of the lane, no further stop: done kept: '..get())
 -- État indépendant de la pause : mêmes entrées, même texte (la même chaîne, pas refaite).
 local a=get(); check(rawequal(a,get()),'same text while nothing changes')
 F.clock=901.2; check(get():find('stamp=901',1,true),'stamp follows the simulation clock')
end
-- 6. Stratégie coupée en course : plus de plan périmé (carburant jugé jusqu'à l'arrivée, temps cible oublié).
function T.strategy_off_forgets_the_plan()
 local w=world({laps=30,fuel=30})
 w.step(400)
 local t=w.t
 check(t.plan and t.plan.ok and t.plan.optimal and t.ready,'plan ready with a fuel stop')
 local stop=t.plan.optimal
 check(Engineer.fuelStatus(w.engineer,w.F,w.ctx.cfg).target==stop-w.me.laps,'fuel judged to the planned stop')
 w.ctx.cfg.strategyOn=false; t.boxLap=stop
 w.step(1)
 check(t.plan==nil and not t.ready and t.boxLap==false and t.duel==nil,'plan, commitment and duels forgotten')
 local fs=Engineer.fuelStatus(w.engineer,w.F,w.ctx.cfg)
 check(fs.target==30-w.me.laps and not fs.toStop,'fuel judged to the finish: '..tostring(fs.target))
 check(St.pitplan(t,w.ctx,false):find('state=none',1,true),'nothing published')
 w.ctx.cfg.strategyOn=true; w.step(1)
 check(t.plan and t.plan.ok,'switched back on: solved at once')
end
-- 7. Sans plan : tours de la course comptés quand même (course au temps, pilote attardé) pour le carburant.
function T.fuel_target_without_a_plan()
 local w=world({timed=true,timeLeft=3000,laps=0,fuel=40,cfg={strategyOn=false}})
 w.step(40)
 check(w.t.plan==nil,'strategy off: no plan')
 check(Engineer.fuelStatus(w.engineer,w.F,w.ctx.cfg).target==nil,'timed race, no measured pace yet: nothing to judge')
 w.step(180)
 local fs=Engineer.fuelStatus(w.engineer,w.F,w.ctx.cfg)
 -- 2 tours finis, 70 % du tour, 2780 s restantes à 100 s : floor(27,8 + 0,7) + 1 = 29 tours encore.
 check(fs and fs.target==29,'timed race without a plan: laps left from the pace, got '..tostring(fs and fs.target))
 -- Course aux tours, joueur à un tour du leader : un tour de moins à faire.
 local me={valid=true,laps=10,spline=0.2,position=2}
 local F={player=0,count=2,cars={[0]=me,[1]={valid=true,laps=11,spline=0.5,position=1}},laps=30,timed=false,timeLeft=0}
 check(St.total({},F,me)==29,'lapped: one lap less')
 check(St.total({},{laps=0,timed=false},me)==nil,'no lap count: unknown')
end
-- 8. Verrous gardés au rechargement de l'app : un état neuf, avec la même mémoire, ne redit rien.
function T.locks_survive_a_hot_reload()
 local v,sayer=radio()
 local memory,writes={},0
 local keep={load=function(name) return memory[name] end,store=function(name,text) memory[name]=text; writes=writes+1 end}
 local me={valid=true,pitlane=false,kmh=150,laps=3,spline=0.2}
 local F={player=0,session=2,isRace=true,cars={[0]=me},me={tyres={tyre(5),tyre(3),tyre(4),tyre(4)}}}
 local ctx={F=F,cfg=Config.defaults(),say=sayer,real=0,keep=keep}
 local function run(e,seconds) for _=1,seconds*10 do ctx.real=ctx.real+0.1; Engineer.locks(e,ctx); Engineer.tyres(e,ctx,0.1); Voice.step(v,ctx.real) end end
 local e1=Engineer.new()
 run(e1,5)
 check(said(v,'wear')==1,'uneven axle: said')
 -- Verrous de la stratégie et du bilan.
 e1.strategist.announcedWindow={10,14,12}; e1.strategist.noMoreSaid=true; e1.debrief.said=true
 run(e1,5)
 check(type(memory.locks)=='string' and #memory.locks<64 and memory.locks:find('^1|2|1|'),'one short string: '..tostring(memory.locks))
 local before=writes
 run(e1,30); check(writes==before,'written on change only')
 -- Rechargement : état neuf, remis à zéro par le script à sa première image, même mémoire.
 local e2=Engineer.new(); Engineer.reset(e2)
 run(e2,30)
 check(said(v,'wear')==1,'after the reload: abnormal wear not said again')
 check(e2.wearSaid and e2.wearSides.FL and not e2.wearSides.FR and e2.wearKm>=5,'wear locks read back')
 check(e2.debrief.said and e2.strategist.noMoreSaid,'debrief and « no more stops » read back')
 local a=e2.strategist.announcedWindow
 check(a and a[1]==10 and a[2]==14 and a[3]==12,'announced window read back')
 check(writes==before,'nothing rewritten after reading the same locks')
 -- Fenêtre : le même plan n'est pas réannoncé.
 e2.strategist.ready=true; e2.strategist.plan={ok=true,optimal=12,window={10,14},costs={}}
 St.announce(e2.strategist,{F=F,cfg={boxCalls=true,duels=false},say=sayer,real=ctx.real},false)
 check(said(v,'window')==0,'window not announced again')
 -- Autre séance : jamais relus.
 F.session=3
 local e3=Engineer.new(); Engineer.reset(e3); Engineer.locks(e3,ctx)
 check(not e3.wearSaid and not e3.debrief.said and not e3.strategist.announcedWindow,'another session: locks ignored')
 F.session=2
 -- Redémarrage de la séance (remise à zéro d'un état qui a déjà tourné) : verrous effacés, rien de relu.
 Engineer.reset(e2); Engineer.locks(e2,ctx)
 check(not e2.wearSaid and not e2.debrief.said and memory.locks:find('^1|2|0|0%.0|0|0|0|$'),'restart: locks cleared: '..tostring(memory.locks))
 Engineer.reset(e2,keep); check(memory.locks=='','reset with the memory: cleared at once')
 -- Sans mémoire (tests, anciennes versions du script) : rien ne casse.
 ctx.keep=nil; Engineer.locks(Engineer.new(),ctx)
end
-- 9. Fenêtre : un optimum qui oscille dans une fenêtre plate n'est pas redit ; un vrai changement l'est.
function T.window_not_repeated_when_the_optimum_wobbles()
 local v,sayer=radio()
 local me={valid=true,laps=5,spline=0.2,pitlane=false}
 local F={isRace=true,player=0,cars={[0]=me}}
 local t={ready=true,boxSaid={}}
 local now=0
 local function plan(optimal,w1,w2)
  now=now+100; me.laps=me.laps+1
  t.plan={ok=true,optimal=optimal,window={w1,w2},costs={}}
  St.announce(t,{F=F,cfg={boxCalls=true,duels=false},say=sayer,real=now,now=now},false)
  Voice.step(v,now)
  return said(v,'window')
 end
 check(plan(18,14,22)==1,'first window said')
 check(plan(15,14,22)==2,'stop 3 laps earlier: said')
 check(plan(18,14,22)==2,'back to 18, lap 15 still good: silent')
 check(plan(15,14,22)==2,'15 again: silent')
 check(plan(18,14,23)==2,'wobble again: silent')
 check(plan(18,14,20)==3,'window closing 2 laps earlier: said')
 -- L'arrêt recule : redit quand le tour annoncé est passé (il n'est plus dans la fenêtre).
 me.laps=17; check(plan(21,19,22)==4,'announced lap out of the window: said')
end
-- 11. Duels : jamais contre une voiture dans la voie des stands ; voiture déjà dans la voie à la première image : pas
-- « il rentre » ; duels d'un relais précédent oubliés loin de l'arrêt.
function T.duels_ignore_cars_in_the_pit_lane()
 local w=world({laps=30,fuel=30,rivals={{spline=0.51}},cfg={rivalPitVoice=true,strategyOn=true}})
 w.step(260)
 check(w.t.duel and w.t.duel.ahead and w.t.duel.ahead.index==1,'car ahead followed')
 w.F.cars[1].pitlane=true; w.step(100)
 check(w.t.duel and w.t.duel.ahead==nil,'car ahead in the pit lane: no duel')
 w.F.cars[1].pitlane=false; w.F.cars[1].retired=true; w.step(100)
 check(w.t.duel.ahead==nil,'retired car: no duel')
 -- Première image avec la voiture devant déjà dans la voie (rechargement) : rien.
 local w2=world({laps=30,fuel=30,rivals={{spline=0.51}},cfg={rivalPitVoice=true,strategyOn=true}})
 w2.F.cars[1].pitlane=true; w2.step(3)
 check(said(w2.voice,'rivalPitted')==0,'already in the lane at the first frame: silent')
 w2.F.cars[1].pitlane=false; w2.step(2); w2.F.cars[1].pitlane=true; w2.step(2)
 check(said(w2.voice,'rivalPitted')==1,'entering the lane: said')
 -- Duels oubliés loin de l'arrêt.
 local v,sayer=radio()
 local me={valid=true,laps=5,spline=0.02,pitlane=false}
 local t={ready=true,boxSaid={},wasUndercut=true,wasThreat=true,plan={ok=true,optimal=20,window={18,22},costs={}},duel={undercut=false}}
 local ctx={F={isRace=true,player=0,cars={[0]=me}},cfg={boxCalls=false,duels=true},link={d=nil},say=sayer,real=10,now=10}
 St.announce(t,ctx,true)
 check(t.wasUndercut==false and t.wasThreat==false,'far from the stop: old duels forgotten')
 me.laps=17; t.duel={undercut=true,undercutGap=2}; St.announce(t,ctx,true)
 check(said(v,'duel')==1,'undercut near the next stop: said')
end
-- 12. Plusieurs arrêts obligatoires : dans la fenêtre, ceux qui restent (arrêts du joueur vus depuis l'ouverture).
function T.several_mandatory_stops_inside_the_window()
 local d={pitState='pending',pitWaived=false,mandatoryStops=2,pitDue=0,playerStops=1,pitCsp=false,pitPosition=0.1,pitOpen=0.3,pitClose=0.7}
 local F={laps=30,timed=false,timeLeft=0}
 local t={}
 check(St.windowStops(t,d)==0 and St.rules(d,3,30,100,F,0,0,t.winStops)==2,'before the window: both stops')
 d.pitState='open'; d.pitDue=1
 check(St.rules(d,10,30,100,F,0,0,St.windowStops(t,d))==2,'window open, no stop yet: two due (it was one)')
 d.playerStops=2
 check(St.windowStops(t,d)==1 and St.rules(d,12,30,100,F,0,0,t.winStops)==1,'one stop made in the window: one left')
 check(St.windowStops(t,nil)==1,'link lost: count kept')
 d.playerStops=3; d.pitDue=0
 check(St.rules(d,14,30,100,F,0,0,St.windowStops(t,d))==0,'AdvancedIA says nothing due: none')
 -- Ouverture non vue (rechargement dans la fenêtre) : le signal d'AdvancedIA seul.
 d.pitDue=1
 check(St.windowStops({},d)==nil and St.rules(d,14,30,100,F,0,0,nil)==1,'opening not seen: the bridge signal alone')
 d.pitState='closed'; check(St.windowStops(t,d)==nil and St.rules(d,20,30,100,F,0,0,nil)==0,'after the window: none')
end
-- 13. Pneus sans usure (km virtuels à 0) sur une voiture sans courbe : aucune dégradation ni arrêt « pneus » fantôme.
function T.no_wear_no_phantom_tyre_stop()
 local d=SD.new()
 for k=1,8 do d.clean[k]={time=100,fuelMid=50,age=k,kmMidF=0,kmMidR=0} end
 d.tyreAge=60
 -- Usure normale : a priori de dégradation, relais neuf de 80 tours au plus, arrêt prévu.
 d.kmF=0.4; d.kmR=0.4
 SD.fit(d,{},0,0.6,0.05)
 local m=SD.model(d,{fuel=100,tank=100},{degPrior=0.05,fuelMargin=1},100,0)
 m.fuelPerLap=1e-4; m.fuel=m.tank
 check(m.degLinear>0 and S.solve(m,{done=60,total=160}).stops>=1,'with wear: tyre stop planned')
 -- Usure coupée : km virtuels mesurés à zéro.
 d.kmF=0; d.kmR=0
 SD.fit(d,{},0,0.6,0.05)
 check(d.degLinear==0,'no wear: no slope fitted')
 near(d.base,100,1e-9,'base time not biased by the tyre age')
 m=SD.model(d,{fuel=100,tank=100},{degPrior=0.05,fuelMargin=1},100,0)
 m.fuelPerLap=1e-4; m.fuel=m.tank
 local p=S.solve(m,{done=60,total=160})
 check(m.degLinear==0 and p.ok and p.stops==0,'no wear: no stop in 100 laps, got '..tostring(p.stops))
 near(p.target,100,1e-6,'target lap time without phantom degradation')
end
-- 14. « Pluie dans N minutes » : les paliers franchis d'un coup ne sont pas redits un par un.
function T.rain_marks_not_repeated()
 local v,sayer=radio()
 local e=Engineer.new()
 local F={rainComing=true,transition=0.30,rain=0,grip=1,wetness=0}
 local ctx={F=F,cfg={weather=true},say=sayer,now=0,real=0}
 local function at(now,transition) ctx.now=now; ctx.real=now; F.transition=transition; Engineer.weather(e,ctx); Voice.step(v,now) end
 at(0,0.30); at(60,0.35)
 check(said(v,'rainIn')==1,'first estimate (3 minutes): said')
 at(120,0.40); check(said(v,'rainIn')==2,'under 2 minutes: said')
 at(180,0.45); at(240,0.47); at(300,0.49)
 check(said(v,'rainIn')==2,'one minute, again and again: silent, got '..said(v,'rainIn'))
 -- Hors pluie : la table des paliers n'est pas refaite à chaque image.
 F.rainComing=false; at(360,0); local marks=e.rainSaid
 at(361,0); check(rawequal(marks,e.rainSaid) and next(marks)==nil,'marks cleared once')
end
-- 15. Perte de voie : seul un passage vu en entier, entré par la piste, est mesuré.
function T.lane_loss_needs_a_full_pass()
 local snap={}; for k=0,399 do snap[k]=k<=380 and k*0.25 or k*0.25-100 end
 local function capture() local s={}; for k,x in pairs(snap) do s[k]=x end; return s,400 end
 local function pass(d,i,first,entryKmh)
  if first then SD.observePit(d,i,false,200,94,0.94,capture) end
  SD.observePit(d,i,true,entryKmh,95,0.95,capture)
  for k=1,299 do local t=95+k*0.1; SD.observePit(d,i,true,(t>100 and t<=103) and 0 or 60,t,0.0,capture) end
  return SD.observePit(d,i,false,80,125,0.05,capture)
 end
 local d=SD.new()
 check(pass(d,3,true,80) and d.laneLoss,'full pass: measured')
 local d2=SD.new()
 check(pass(d2,3,false,80)==nil and d2.laneLoss==nil,'already in the lane at the first frame: not measured')
 local d3=SD.new()
 check(pass(d3,3,true,0)==nil and d3.laneLoss==nil,'put at its box (returned to the pits): not measured')
 check(pass(d3,3,false,80) and d3.laneLoss,'next full pass: measured')
end
-- 1.3.4. Duel de stratégie publié pour AdvancedIA (clé SpotterEnginer.strategy, contrat v1 du 11/11/2026).
function T.strategy_contract_v1()
 local function ctxOf(lap,over)
  local F={isRace=true,player=0,clock=123.9,cars={[0]={valid=true,laps=lap-1,spline=0.4,pitlane=false,finished=false}}}
  local ctx={F=F,cfg=Config.defaults(),link={d={neutral=false,red=false}}}
  for k,v in pairs(over or {}) do ctx[k]=v end
  return ctx
 end
 local function state(du,boxLap) return {ready=true,plan={ok=true,optimal=12},duel=du,boxLap=boxLap or false} end
 local form='^v=1;mode=%a+;rival=%-?%d+;gain=%-?%d+%.%d;lap=%d+;stamp=%d+$'
 -- Undercut sur la voiture de devant : rival, gain au dixième, tour d'arrêt du plan ; « box » engagé : son tour.
 local t=state({undercut=true,undercutGain=1.26,ahead={index=4},behind={index=7}})
 local s=St.strategy(t,ctxOf(10),true)
 check(s=='v=1;mode=undercut;rival=4;gain=1.3;lap=12;stamp=123' and s:match(form) and #s<=160,'undercut: '..s)
 t.boxLap=11; check(St.strategy(t,ctxOf(10),true):find('lap=11',1,true),'engaged box lap published')
 -- Menace derrière, puis overcut ; undercut d'abord quand plusieurs sont vrais.
 s=St.strategy(state({threat=true,overcut=true,ahead={index=4},behind={index=7}}),ctxOf(10),true)
 check(s=='v=1;mode=cover;rival=7;gain=-1.0;lap=12;stamp=123','cover: '..s)
 s=St.strategy(state({overcut=true,ahead={index=4}}),ctxOf(10),true)
 check(s=='v=1;mode=overcut;rival=4;gain=-1.0;lap=12;stamp=123','overcut: '..s)
 -- Rien : pas de duel, arrêt trop loin, voie des stands, neutralisation, réglage coupé, plan pas prêt, hors course.
 local none='v=1;mode=none;rival=-1;gain=-1.0;lap=0;stamp=123'
 local du={undercut=true,undercutGain=2,ahead={index=4}}
 check(St.strategy(state(nil),ctxOf(10),true)==none,'no duel')
 check(St.strategy(state(du),ctxOf(5),true)==none,'stop too far')
 local c=ctxOf(10); c.F.cars[0].pitlane=true; check(St.strategy(state(du),c,true)==none,'pit lane')
 c=ctxOf(10); c.link.d.neutral=true; check(St.strategy(state(du),c,true)==none,'neutralised')
 c=ctxOf(10); c.cfg.duels=false; check(St.strategy(state(du),c,true)==none,'duels setting off')
 check(St.strategy(state(du),ctxOf(10),false)==none,'engineer or strategy off')
 local t2=state(du); t2.ready=false; check(St.strategy(t2,ctxOf(10),true)==none,'plan not ready')
 c=ctxOf(10); c.F.isRace=false; check(St.strategy(state(du),c,true)==none,'not a race')
 -- Texte refait seulement quand une valeur change (même table, même chaîne) ; le stamp avance avec la simulation.
 local t3=state(du); c=ctxOf(10)
 local a=St.strategy(t3,c,true); du.undercutGain=2.04; local b=St.strategy(t3,c,true)
 check(rawequal(a,b),'same text kept for a rounding difference')
 c.F.clock=125.2; check(St.strategy(t3,c,true):find('stamp=125',1,true),'stamp follows the simulation clock')
end
return T
