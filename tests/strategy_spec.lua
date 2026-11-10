local S=require('src/strategy')
local T={}
local Helpers=require('tests/helpers')
local check,near=Helpers.check,Helpers.near
local function model(over)
 local m=S.defaultModel()
 m.base=100; m.fuelPerLap=2.5; m.fuelK=0.03; m.tank=100; m.fuel=30; m.fuelMargin=1
 m.degLinear=0.05; m.warmup=1.5; m.pitLane=20; m.tyreChange=10; m.fuelRate=0.3
 for k,v in pairs(over or {}) do m[k]=v end
 return m
end
-- Plan prêt à être annoncé : deux tours propres, ou trois tours vus par l'app, ou un arrêt qui ne peut pas attendre
-- (carburant mesuré, pas l'estimation d'AC) ; jamais sans plan.
function T.plan_ready_needs_measured_laps()
 local St=require('src/strategist')
 local t={plan={ok=true,optimal=12,fuelLaps=20},data={clean={},records={},fuelPerLap=nil}}
 check(not St.ready(t),'no data: not ready')
 t.data.records={{},{}}; t.data.clean={{}}
 check(not St.ready(t),'start lap and one clean lap: not ready')
 t.data.clean={{},{}}; check(St.ready(t),'two clean laps: ready')
 t.data.clean={}; t.data.records={{},{},{}}; check(St.ready(t),'three laps seen (neutralised): ready')
 t.data.records={}; t.plan.fuelLaps=2; check(not St.ready(t),'AC fuel estimate only: not ready')
 t.data.fuelPerLap=2.5; check(St.ready(t),'measured fuel for two laps: the stop cannot wait')
 t.plan.ok=false; check(not St.ready(t),'no plan: not ready')
end
function T.lut_inline_and_lines()
 local l=S.parseLut('(0=98|5=100|30=95)')
 check(l,'inline'); near(S.eval(l,0),98); near(S.eval(l,2.5),99); near(S.eval(l,30),95); near(S.eval(l,99),95); near(l.max,100)
 local l2=S.parseLut('0|100\n10|97 ; commentaire\n20|90\n')
 check(l2,'lines'); near(S.eval(l2,15),93.5)
 check(S.parseLut('rien')==nil,'garbage')
end
function T.no_stop_when_fuel_and_tyres_last()
 local m=model({fuel=80,degLinear=0.01})
 local p=S.solve(m,{done=0,total=25})
 check(p.ok,'ok '..tostring(p.reason)); check(p.stops==0,'stops '..p.stops); check(p.optimal==nil,'no optimal')
end
function T.fuel_forces_stop_before_empty()
 local m=model({fuel=30})
 local p=S.solve(m,{done=0,total=30})
 check(p.ok,'ok'); check(p.stops>=1,'needs a stop')
 -- 30 L à 2,5 L/tour : 11 tours au plus avec le carburant actuel.
 check(p.optimal<=11,'stop before fuel runs out: '..tostring(p.optimal))
 check(p.window[1]<=p.optimal and p.optimal<=p.window[2],'window holds optimal')
 check(p.fuelShort==0,'no shortage at the planned stop')
end
function T.mandatory_stop_inside_window()
 local m=model({fuel=90,degLinear=0.0})
 local p=S.solve(m,{done=0,total=30,mandatory=1,windowOpen=10,windowClose=20})
 check(p.ok,'ok'); check(p.stops==1,'one stop '..p.stops)
 check(p.optimal>=10 and p.optimal<=20,'inside window '..tostring(p.optimal))
 check(p.window[1]>=10 and p.window[2]<=20,'window inside rules')
end
-- Au premier arrêt, le carburant qui reste réduit le ravitaillement : sans usure ni effet du carburant, s'arrêter plus
-- tôt ne coûte pas plus, la fenêtre reste large (elle se collait à la limite du carburant).
function T.first_stop_refuel_credit()
 local m=model({fuel=60,fuelK=0,degLinear=0,fuelRate=0.5,minPit=0})
 local p=S.solve(m,{done=0,total=30})
 check(p.ok and p.stops==1,'one stop')
 check(p.window[2]-p.window[1]>=10,'wide window: '..p.window[1]..' - '..p.window[2])
end
-- Pneus déjà sous le plancher, 2 tours de la fin : pas d'arrêt forcé (il revenait à chaque tour).
function T.worn_tyres_do_not_force_a_stop_every_lap()
 local m=model({fuel=40,degLinear=0.1,age0=45})
 local p=S.solve(m,{done=23,total=25})
 check(p.ok and p.stops==0,'no forced stop 2 laps from the end: '..tostring(p.stops)..' '..tostring(p.reason))
end
-- Sans consommation (réglage d'AC) : aucun arrêt fantôme pour le carburant.
function T.no_fuel_use_no_phantom_stop()
 local m=model({fuelPerLap=1e-4,fuel=100,degLinear=0,fuelK=0})
 local p=S.solve(m,{done=0,total=40})
 check(p.ok and p.stops==0,'no stop without fuel use: '..tostring(p.stops))
end
-- Règles d'AdvancedIA : arrêt dû compté sur les arrêts faits dans la fenêtre ; fenêtre convertie en tours depuis
-- maintenant (tours du leader, ou temps d'une course chronométrée).
function T.pit_rules_follow_acai()
 local St=require('src/strategist')
 local d={pitState='pending',pitWaived=false,mandatoryStops=1,playerStops=1,pitDue=0,pitCsp=false,pitPosition=0.1,pitOpen=0.3,pitClose=0.7}
 local F={laps=30,timed=false,timeLeft=0}
 local owed,open,close=St.rules(d,3,30,100,F)
 check(owed==1 and open==9 and close==20,'before the window (a stop made before does not count): '..owed..' '..open..' '..close)
 d.pitState='open'; d.pitDue=1
 owed=St.rules(d,3,30,100,F); check(owed==1,'inside the window: ACAI due count')
 d.pitState='closed'; owed=St.rules(d,3,30,100,F); check(owed==0,'after the window')
 d.pitState='pending'; d.pitPosition=0.5; d.pitOpen=0.6; d.pitClose=0.8
 local _,o2,c2=St.rules(d,10,40,100,{laps=0,timed=true,timeLeft=1800})
 check(o2==14 and c2==20,'timed race: '..o2..' - '..c2)
 -- Course aux tours, P2 : juste avant et juste après le passage du leader sur la ligne, mêmes tours et même fenêtre
 -- (le joueur n'est pas « attardé » pendant que le leader a un tour entier de plus).
 local function at(leaderLaps,leaderSpline)
  local F2={laps=30,timed=false,timeLeft=0,count=2,cars={[0]={valid=true,position=1,laps=leaderLaps,spline=leaderSpline},[1]={valid=true,position=2,laps=10,spline=0.7}}}
  local me=F2.cars[1]
  local behind=St.behindLeader(F2,me)
  local dd={pitState='pending',pitWaived=false,mandatoryStops=1,playerStops=0,pitDue=0,pitCsp=false,pitPosition=leaderLaps/30,pitOpen=0.5,pitClose=0.8}
  local _,o,c=St.rules(dd,10,30,100,F2,behind)
  return o,c,behind
 end
 local o1,c1,b1=at(10,0.95); local o3,c3,b3=at(11,0.05)
 check(o1==o3 and c1==c3,'window stable across the leader line crossing: '..o1..'-'..c1..' / '..o3..'-'..c3)
 check(math.abs(b1-0.25)<1e-6 and math.abs(b3-0.35)<1e-6,'continuous gap to the leader')
end
function T.heavy_degradation_means_more_stops()
 local light=S.solve(model({fuel=100,degLinear=0.02}),{done=0,total=40})
 local heavy=S.solve(model({fuel=100,degLinear=0.5}),{done=0,total=40})
 check(light.ok and heavy.ok,'ok'); check(heavy.stops>light.stops,'heavy '..heavy.stops..' > light '..light.stops)
end
function T.wear_curve_life_and_degradation()
 local curve=S.parseLut('(0=100|10=99|20=96|30=90)')
 local m=model({fuel=100,wearF=curve,wearR=curve,kmF=1,kmR=1,gripK=0.6,gripFloor=93})
 -- Perte d'adhérence au 15e km : 2,5 % -> 1,5 s à 0,6 s par %.
 near(S.lapDeg(m,14.5,14.5,0,0),0.6*2.5,1e-6,'deg')
 local D,life=S.prefix(m,0,0,0,40)
 check(life>=24 and life<=26,'life '..life)
 check(D[10]>0,'deg accumulated')
 local p=S.solve(m,{done=0,total=40})
 check(p.ok and p.stops>=1,'stops with worn tyres')
 check(p.gripNow and p.gripNow<=100,'grip reported')
end
function T.traffic_moves_the_stop()
 local m=model({fuel=60,degLinear=0.08})
 local base=S.solve(m,{done=0,total=30})
 local opt=base.optimal
 local p=S.solve(m,{done=0,total=30},function(n1) if n1==opt then return 30,{position=9} end return 0 end)
 check(p.optimal~=opt,'traffic moved the stop from '..opt)
 check(p.detail and p.detail[opt] and p.detail[opt].position==9,'detail kept')
end
-- Presque plus de carburant : arrêt au bout du tour en cours.
function T.stop_now_when_almost_empty()
 local m=model({fuel=1})
 local p=S.solve(m,{done=0,total=30})
 check(p.ok,'one lap possible then stop')
 check(p.optimal==1,'stop now: '..tostring(p.optimal))
end
-- Arrêt obligatoire impossible (fenêtre réglementaire fermée) : la raison est la fenêtre, pas le carburant.
function T.failure_reason_is_the_window()
 local p=S.solve(model({fuel=1}),{done=0,total=30,mandatory=1,windowOpen=0,windowClose=0})
 check(not p.ok and p.reason=='mandatory','reason: '..tostring(p.reason))
end
function T.rejoin_counts_cars_ahead()
 local m=model({})
 local me={progress=10.0,pace=100,fresh=99}
 local rivals={{index=3,progress=10.1,pace=100,stopLap=-1},{index=5,progress=9.5,pace=100,stopLap=-1}}
 -- Arrêt à la fin du tour 11 : 100 s jusqu'à la ligne, 30 s de perte -> la voiture 3 (10 s devant) reste devant,
 -- la voiture 5 (50 s derrière) ressort 20 s derrière.
 local pen,info=S.rejoin(m,me,rivals,10,1,30)
 check(info.position==2,'position '..info.position)
 check(info.ahead==3,'ahead '..info.ahead)
 near(info.aheadGap,40,1e-6,'gap to car ahead after stop')
 check(pen>=0,'penalty')
end
function T.undercut_when_rival_tyres_are_old()
 local m=model({degLinear=0.4,warmup=0.5})
 local me={km0F=0,km0R=0,age0=10}
 local out=S.duels(m,10,me,{gap=1.0,km0F=0,km0R=0,age0=20,stop=14},nil,25)
 check(out.undercut==true,'undercut expected, gap '..tostring(out.undercutGap))
 local out2=S.duels(m,10,me,{gap=5.0,km0F=0,km0R=0,age0=2,stop=11},nil,25)
 check(out2.undercut==false,'no undercut on fresh rival')
end
-- Arrêt prévu d'un rival : compté seulement s'il tombe avant la ressortie du joueur, dans les tours du rival.
function T.rejoin_rival_stop_on_its_own_laps()
 local m=model({})
 local me={progress=10.0,pace=100,fresh=99}
 -- Rival 40 s derrière, arrêt prévu à la fin de son tour 11 : le joueur ressort (130 s) avant que le rival n'y soit
 -- (10,9 tours) ; il est 10 s derrière, pas 40.
 local _,info=S.rejoin(m,me,{{index=4,progress=9.6,pace=100,stopLap=11}},10,1,30)
 check(info.behind==4,'rival behind'); near(info.behindGap,10,1e-6,'rival gap')
 -- Arrêt du rival avant la ressortie : il perd l'arrêt.
 local _,info2=S.rejoin(m,me,{{index=4,progress=10.5,pace=100,stopLap=11}},10,1,30)
 local _,info3=S.rejoin(m,me,{{index=4,progress=10.5,pace=100,stopLap=-1}},10,1,30)
 check(info2.ahead==4 and info3.behind==4,'rival stop counted only when it happens before the rejoin')
end
-- Sans consommation : aucun effet du carburant, ni à l'ajustement du temps de base ni au modèle (temps cible juste).
function T.no_fuel_use_no_fuel_effect()
 local St=require('src/strategist'); local SD=require('src/stratdata')
 local cfg={fuelK=0.03}
 check(St.fuelEffect({fuelRate=0,me={fuel=50}},cfg)==0,'fuel rate 0')
 check(St.fuelEffect({fuelRate=1,me={fuel=0}},cfg)==0,'no fuel')
 check(St.fuelEffect({fuelRate=1,me={fuel=50}},cfg)==0.03,'normal')
 local d=SD.new()
 for k=1,5 do d.clean[k]={time=100+0.05*k,fuelMid=50,age=k} end
 SD.fit(d,{},0,SD.gripPrior(100),0.05)
 near(d.base,100,1e-6,'base fitted without fuel effect')
 local m=SD.model(d,{fuel=50},cfg,100,0)
 check(m.fuelK==0,'model without fuel effect')
end
-- Plan d'arrêt pour AdvancedIA (contrat SpotterEnginer.pitplan v1) : prévu, « box » au tour d'arrêt dès 10 % du tour,
-- fait après la voie des stands jusqu'au plan d'un arrêt suivant ; rien tant que le plan n'est pas prêt ; format.
function T.pitplan_contract_v1()
 local Strategist=require('src/strategist')
 local t=Strategist.new()
 local me={valid=true,laps=9,spline=0.5,pitlane=false}
 local F={isRace=true,player=0,cars={[0]=me},clock=1834.7}
 local ctx={F=F,cfg={boxCalls=true}}
 local function get() local s=Strategist.pitplan(t,ctx,true); check(#s<=160,'160 bytes at most'); local out={}
  for k,v in s:gmatch('(%w+)=([^;]*)') do out[k]=v end; return out,s end
 t.plan={ok=true,optimal=12,window={10,14}}
 local o,s=get()
 check(o.state=='none' and o.v=='1','not ready: none ('..s..')')
 t.ready=true
 o,s=get()
 check(s=='v=1;lap=12;compound=-;state=planned;window=10-14;boxcalls=1;stamp=1834','planned: '..s)
 me.laps=11; me.spline=0.05; o=get(); check(o.state=='planned','stop lap, before 10 %: planned')
 me.spline=0.2; o=get(); check(o.state=='boxnow' and o.lap=='12','stop lap from 10 %: boxnow')
 me.spline=0.97; me.pitlane=true; o=get(); check(o.state=='done' and o.lap=='12','pit lane: done')
 me.laps=12; me.spline=0.1; me.pitlane=false; o=get(); check(o.state=='done','done kept after the stop')
 t.plan.optimal=30; t.plan.window={27,33}; o=get()
 check(o.state=='planned' and o.lap=='30' and o.window=='27-33','next stop planned')
 -- Neutralisation : arrêt dit maintenant.
 t.neutralBox=true; o=get(); check(o.state=='boxnow','neutral box: boxnow'); t.neutralBox=false
 -- Appels box coupés : publié quand même, boxcalls=0 ; ingénieur coupé ou hors course : none.
 ctx.cfg.boxCalls=false; o=get(); check(o.boxcalls=='0' and o.state=='planned','box calls off')
 check(Strategist.pitplan(t,ctx,false):find('state=none',1,true),'engineer off: none')
 F.isRace=false; o=get(); check(o.state=='none','not a race: none')
end
return T
