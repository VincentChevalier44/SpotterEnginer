-- Revue 1.3.2 du spotter, des urgences, des dangers et du chronométrage : un test par correctif, chacun avec son cas
-- témoin (l'annonce part quand elle est vraie, se tait quand elle est fausse).
local Voice=require('src/voice')
local Say=require('src/say')
local Config=require('src/config')
local Layout=require('src/bridge_layout')
local Timing=require('src/timing')
local Hazards=require('src/hazards')
local Emergency=require('src/emergency')
local Spotter=require('src/spotter')
local Position=require('src/position')
local T={}
local Helpers=require('tests/helpers')
local check,near=Helpers.check,Helpers.near
-- État du pont au repos (tous les champs de la disposition), table simple.
local function bridge(over)
 local d={}
 for _,f in ipairs(Layout.fields) do if f[2]=='bool' then d[f[1]]=false elseif f[2]=='string' then d[f[1]]='' else d[f[1]]=0 end end
 d.serial=1; d.standing='none'; d.giveBack=-1; d.slowCar=-1; d.playerStintFor=-1
 for k,v in pairs(over or {}) do d[k]=v end
 return d
end
-- Image de course : joueur (indice 0) au milieu d'une piste de 4000 m, voitures données {spline, kmh, x, z, position…}.
local function scene(cars,opts)
 opts=opts or {}
 local port={play=function(p) return {p=p} end,playing=function() return false end,stop=function() end}
 local v=Voice.new(port)
 local F={cars={},count=#cars+1,player=0,isRace=opts.race~=false,trackLength=4000,pitSpeed=80,started=true,laps=20,
  me={damage={0,0,0,0,0},susp={0,0,0,0},hit=-1,tyres={{blown=false},{blown=false},{blown=false},{blown=false}},wheelsOut=0,cuts=0,lapValid=true,brake=0,yaw=0}}
 F.cars[0]={valid=true,x=0,y=0,z=0,lookX=0,lookZ=1,kmh=opts.kmh or 200,spline=0.5,laps=opts.laps or 5,position=opts.pos or 3,pitlane=false,name='Moi',len=4.7,hit=-1}
 for i,c in ipairs(cars) do
  local spline=c.spline or 0.5
  F.cars[i]={valid=true,x=c.x or 0,y=0,z=c.z or (spline-0.5)*4000,lookX=0,lookZ=1,kmh=c.kmh or 200,spline=spline,laps=c.laps or 5,
   position=c.position or (i<3 and i or i+1),pitlane=c.pitlane or false,name='Voiture '..i,len=4.7,hit=-1,retired=false}
 end
 local link={state='connected',d=bridge(opts.d),cars={}}
 for i,c in ipairs(cars) do if c.lc then local t={valid=true,incident=false,onTrack=true,still=0,spin=false,wrong=false,safety=false,timeAdded=0,pending=0,cutLeft=0,sanctionDq=false,flagDq=false,mistakeId=0}; for a,b in pairs(c.lc) do t[a]=b end; link.cars[i]=t end end
 local cfg=Config.defaults()
 local ctx={F=F,link=link,say=Say.new(v,{},'vox','FR',nil),voice=v,cfg=cfg,timing=Timing.new(),now=0,real=0,trackLateral=opts.lateral}
 return ctx,v
end
local function at(ctx,t) ctx.now=t; ctx.real=t; ctx.link.d.serial=ctx.link.d.serial+1 end
local function queued(v,key) for _,q in ipairs(v.queue) do if q.key==key then return q end end return nil end
-- Annonce de cette clé retirée de la file (comptée par l'appelant), ou nil.
local function take(v,key) for i,q in ipairs(v.queue) do if q.key==key then table.remove(v.queue,i); return q end end return nil end
-- Fonction d'un module remplacée le temps d'un test, toujours rendue.
local function with(module,name,fn,body)
 local old=module[name]; module[name]=fn
 local ok,err=pcall(body)
 module[name]=old
 if not ok then error(err,0) end
end
-- 1. Joueur immobilisé au bord de la piste : « attends » deux fois au plus, puis silence, quel que soit le trafic.
function T.stranded_guidance_is_bounded()
 local ctx,v=scene({{spline=0.9,kmh=200}},{kmh=0})
 local em=Emergency.new(); em.moved=true
 local waits,goes=0,0
 local t=0
 for lapOfTraffic=1,12 do
  -- Une voiture arrive (150 m derrière) pendant 2 s, puis 8 s sans personne.
  for k=1,100 do
   t=t+0.1
   ctx.F.cars[1].spline=k<=20 and 0.5-150/4000 or 0.9
   at(ctx,t); Emergency.step(em,ctx,0.1)
   local q=take(v,'stranded')
   if q and (q.sense=='waitTraffic' or q.sense=='stoppedYou') then waits=waits+1 elseif q and q.sense=='goNow' then goes=goes+1 end
  end
 end
 check(em.stranded,'still stopped on the track')
 check(waits>=1 and waits<=Emergency.STOP.waits,'wait said at most '..Emergency.STOP.waits..' times in 120 s, got '..waits)
 check(goes==waits,'every wait has its go: '..goes..' / '..waits)
end
-- 2. Compteur de tours d'AC qui change avant ou après la spline 0 : la progression des voitures reste comparable, les
-- écarts sont connus à la ligne (image où le compteur du joueur change) ; un compteur vraiment décalé est rattrapé.
function T.lap_counter_before_or_after_spline_zero()
 for _,offset in ipairs({-60,60,0}) do
  local t=Timing.new()
  local length,speed,dt=4000,50,0.02
  -- Voitures 0 (devant), 1 (joueur), 2 (derrière), à 1 s d'intervalle ; position en mètres depuis le départ du tour 0.
  local pos={[0]=3000+2*speed,[1]=3000+speed,[2]=3000}
  local laps={[0]=0,[1]=0,[2]=0}
  local now,seen=0,false
  for _=1,1400 do
   now=now+dt
   local before=laps[1]
   for i=0,2 do
    pos[i]=pos[i]+speed*dt
    -- Ligne de chronométrage à offset m de la spline 0 (négatif : avant).
    laps[i]=math.floor((pos[i]-offset)/length)
    Timing.update(t,i,(pos[i]/length)%1,laps[i],now,true,false)
   end
   -- Après 3 s (le temps que chaque voiture atteigne les premiers passages relevés de celle de devant).
   if now>3 then
    local ga=Timing.gap(t,0,1,now); local gb=Timing.gap(t,1,2,now)
    check(ga and gb,'gaps known at every frame around the line (offset '..offset..' m, t '..now..')')
    near(ga,1,0.05,'gap ahead (offset '..offset..')'); near(gb,1,0.05,'gap behind (offset '..offset..')')
   end
   if laps[1]~=before then seen=true end
  end
  check(seen,'the player crossed the line')
  near(t.cars[0].progress-t.cars[1].progress,speed/length,1e-6,'progress one second apart after the line')
 end
 -- Compteur d'AC vraiment en avance d'un tour (hors de la zone de la ligne) : rattrapé aussitôt.
 local t=Timing.new()
 Timing.update(t,0,0.50,3,1,true,false)
 Timing.update(t,0,0.51,4,2,true,false)
 near(t.cars[0].progress,4.51,1e-6,'counter caught up outside the line zone')
 -- Dans la zone de la ligne : attendu, puis rattrapé à la sortie de la zone.
 local t2=Timing.new()
 Timing.update(t2,0,0.97,3,1,true,false)
 Timing.update(t2,0,0.98,4,2,true,false)
 near(t2.cars[0].progress,3.98,1e-6,'no jump near the line')
 for k=1,14 do Timing.update(t2,0,(0.98+k*0.01)%1,4,2+k,true,false) end
 near(t2.cars[0].progress,4.12,1e-6,'continuous through the line: '..t2.cars[0].progress)
 check(t2.cars[0].ds>0,'forward move kept')
end
-- 7. Écart sur un passage fait dans la voie des stands avant l'arrêt : inconnu (écart propre), jamais gonflé de l'arrêt.
function T.gap_never_measured_through_a_pit_stop()
 local t=Timing.new()
 local now=0
 -- Voiture 0 : traverse la voie (spline 0,00 à 0,05, sale), arrêt de 20 s à 0,02, ressort ; voiture 1 arrive 3 s après
 -- sa sortie.
 local function run(i,from,to,seconds,dirty)
  local steps=math.floor(seconds*20+0.5)
  for k=1,steps do now=now+0.05; Timing.update(t,i,from+(to-from)*k/steps,5,now,true,dirty) end
 end
 Timing.update(t,0,0.99,4,now,true,false); Timing.update(t,1,0.90,4,now,true,false)
 run(0,0.99,1.0,1,false)
 t.cars[0].spline=0; t.cars[0].progress=5
 run(0,0.0,0.02,4,true); run(0,0.02,0.02,20,true); run(0,0.02,0.05,6,true)
 local exitAt=now
 run(0,0.05,0.08,2.4,false)
 -- Le joueur (1) est à 0,03 : la voiture 0 y est passée dans la voie.
 t.cars[1].spline=0.03; t.cars[1].progress=5.03; t.cars[1].seen=true
 local raw=Timing.gap(t,0,1,now)
 check(raw and raw>4,'raw gap carries the pit lane: '..tostring(raw))
 check(Timing.gap(t,0,1,now,true)==nil,'clean gap unknown on a pit lane passage')
 -- Au-delà de la sortie : passage propre, écart connu.
 t.cars[1].spline=0.06; t.cars[1].progress=5.06
 local clean=Timing.gap(t,0,1,now,true)
 check(clean and clean<now-exitAt+0.01,'clean gap known past the pit exit: '..tostring(clean))
end
-- 3. Lacet d'une épingle de kart (2,2 rad/s à 45 km/h : la trajectoire l'explique) : jamais un tête-à-queue.
function T.kart_hairpin_is_not_a_spin()
 local ctx,v=scene({{spline=0.5-60/4000,kmh=60}},{kmh=45})
 local em=Emergency.new(); em.moved=true
 ctx.F.me.yaw=2.2
 for k=1,15 do at(ctx,1+k*0.1); Emergency.step(em,ctx,0.1) end
 check(not queued(v,'stranded') and not em.stranded,'kart hairpin: no spin call')
 -- La même vitesse de lacet à 120 km/h : la voiture pivote.
 local c2,v2=scene({},{kmh=120})
 local e2=Emergency.new(); e2.moved=true
 c2.F.me.yaw=2.2
 for k=1,5 do at(c2,1+k*0.1); Emergency.step(e2,c2,0.1) end
 check(queued(v2,'stranded'),'same yaw rate at 120 km/h: spin')
end
-- 9. Retour en piste : le suiveur du peloton à la même vitesse ne compte pas ; une voiture bien plus rapide, oui.
function T.rejoin_needs_a_faster_car()
 for _,case in ipairs({{105,false},{180,true}}) do
  local ctx,v=scene({{spline=0.5-30/4000,kmh=case[1]}},{kmh=100})
  local em=Emergency.new(); em.moved=true
  ctx.F.me.wheelsOut=4
  for k=1,8 do at(ctx,1+k*0.1); Emergency.step(em,ctx,0.1) end
  check((queued(v,'rejoin')~=nil)==case[2],'rejoin call with a car at '..case[1]..' km/h behind: '..tostring(queued(v,'rejoin')~=nil))
 end
end
-- 12. Gros choc puis retour aux stands avant le bilan : pas de « pas de dégâts » ; resté en piste : bilan dit.
function T.no_damage_report_back_in_the_pits()
 for _,pits in ipairs({false,true}) do
  local ctx,v=scene({},{kmh=200})
  local em=Emergency.new()
  at(ctx,1); Emergency.step(em,ctx,0.1)
  ctx.F.me.hit=0; at(ctx,1.1); Emergency.step(em,ctx,0.1)
  ctx.F.cars[0].kmh=140; at(ctx,1.6); Emergency.step(em,ctx,0.1)
  local hit=take(v,'damage'); check(hit and hit.sense=='wallHit','wall hit called')
  if pits then ctx.F.cars[0].pitlane=true; ctx.F.cars[0].kmh=0 end
  ctx.F.me.hit=-1; at(ctx,5); Emergency.step(em,ctx,0.1)
  check((queued(v,'damage')~=nil)==not pits,'damage report (back in the pits: '..tostring(pits)..')')
 end
end
-- 14. Piste point à point (F.open) : une voiture arrêtée au départ n'est pas « devant » celle qui arrive.
function T.open_track_is_not_wrapped()
 for _,open in ipairs({false,true}) do
  local ctx,v=scene({{spline=0.01,kmh=0}})
  ctx.F.cars[0].spline=0.99; ctx.F.open=open or nil
  at(ctx,1); Hazards.step(Hazards.new(),ctx)
  check((queued(v,'hazard')~=nil)==not open,'stopped car across the line (open track: '..tostring(open)..')')
 end
end
-- 5. Écarts en direct : voisin changé pendant la neutralisation, file groupée au vert : rien ; l'écart remonte puis
-- retombe sous la seconde : dit.
function T.live_gaps_are_not_rearmed_by_a_neutralisation()
 local ctx,v=scene({{spline=0.51,position=2},{spline=0.49,position=4},{spline=0.52,position=1}},{pos=3})
 ctx.cfg.gaps=true; ctx.cfg.gapEvents=true; ctx.cfg.sideBySide=false; ctx.cfg.hazards=false
 local s=Spotter.new()
 local gap=3
 with(Timing,'gap',function() return gap,0 end,function()
  local t=0
  local function run(seconds) for _=1,seconds*10 do t=t+0.1; at(ctx,t); Spotter.step(s,ctx) end end
  run(2)
  check(not queued(v,'inSecond'),'3 s: nothing')
  ctx.link.d.neutral=true; ctx.link.d.neutralMode='vsc'; run(2)
  -- Arrêt de la voiture de devant : un autre voisin, tout le monde groupé.
  ctx.F.cars[1].position=5; ctx.F.cars[3].position=2; gap=0.5; run(2)
  ctx.link.d.neutral=false; ctx.link.d.neutralMode=''; run(3)
  check(not queued(v,'inSecond') and not queued(v,'heInSecond'),'bunched at the green with new neighbours: silent')
  gap=2; run(2); gap=0.5; run(2)
  check(queued(v,'inSecond'),'back inside the second later: said')
 end)
end
-- 6. Tendance des écarts : jamais par rapport à un écart d'avant la neutralisation.
function T.gap_trend_forgets_a_neutralisation()
 for _,neutral in ipairs({false,true}) do
  local ctx,v=scene({{spline=0.51,position=2}},{pos=3,laps=3})
  ctx.cfg.gaps=true; ctx.cfg.gapEvery=1; ctx.cfg.gapEvents=false; ctx.cfg.sideBySide=false; ctx.cfg.hazards=false
  local s=Spotter.new()
  local gap=20
  with(Timing,'gap',function(_,a) if a==1 then return gap,0 end return nil,0 end,function()
   at(ctx,1); Spotter.step(s,ctx)
   ctx.F.cars[0].laps=4; at(ctx,2); Spotter.step(s,ctx)
   check(take(v,'gaps'),'first gap said')
   if neutral then
    ctx.link.d.neutral=true; ctx.link.d.neutralMode='vsc'; at(ctx,3); Spotter.step(s,ctx)
    ctx.link.d.neutral=false; ctx.link.d.neutralMode=''; at(ctx,4); Spotter.step(s,ctx)
   end
   gap=0.8; ctx.F.cars[0].laps=5; at(ctx,20); Spotter.step(s,ctx)
   local q=queued(v,'gaps')
   check(q,'second gap said')
   local closing=q.sense:find('closing',1,true)~=nil
   check(closing==not neutral,'"closing" after a neutralisation: '..tostring(neutral)..' -> '..q.sense)
  end)
 end
end
-- 8. Côte à côte, puis joueur à l'arrêt : le côté tenu est oublié, pas de « dégagé » à la reprise ; sans arrêt : dit.
function T.no_stale_clear_after_a_stop()
 for _,stop in ipairs({false,true}) do
  local ctx,v=scene({{x=2.5,z=0,spline=0.5,position=2}},{pos=3})
  ctx.cfg.hazards=false; ctx.cfg.gaps=false
  local s=Spotter.new()
  local t=0
  local function run(seconds) for _=1,math.floor(seconds*20+0.5) do t=t+0.05; at(ctx,t); Spotter.step(s,ctx) end end
  run(1)
  check(queued(v,'side:left'),'car on the left called')
  v.started['side:left']=t; v.queue={}
  if stop then ctx.F.cars[0].kmh=0; run(1); ctx.F.cars[1].z=800; ctx.F.cars[1].spline=0.7; run(6); ctx.F.cars[0].kmh=120
  else ctx.F.cars[1].z=800; ctx.F.cars[1].spline=0.7 end
  run(2)
  check((queued(v,'side:clear')~=nil)==not stop,'clear after the car left (player stopped meanwhile: '..tostring(stop)..')')
 end
end
-- 4. Côtés inversés après trois désaccords (inchangé), jamais comptés quand le joueur recule ou reprend la piste.
function T.sides_flip_needs_evidence_and_the_right_way()
 local function passes(n,setup)
  -- Position latérale de CSP à l'opposé du repère de la voiture (une voiture à gauche y est à droite).
  local ctx=scene({{x=2.5,z=0,spline=0.5,position=2}},{pos=3,lateral=function(x) return x/5 end})
  ctx.cfg.hazards=false; ctx.cfg.gaps=false
  if setup then setup(ctx) end
  local s=Spotter.new()
  local t=0
  local function run(seconds) for _=1,math.floor(seconds*20+0.5) do t=t+0.05; at(ctx,t); Spotter.step(s,ctx) end end
  for _=1,n do
   ctx.F.cars[1].z=0; run(0.6)
   ctx.F.cars[1].z=60; run(1)
  end
  return s
 end
 check(passes(2).autoFlip==false,'two disagreements: not yet')
 check(passes(3).autoFlip==true,'three disagreements: sides swapped')
 check(passes(10,function(ctx) Timing.car(ctx.timing,0).ds=-0.001 end).autoFlip==false,'player going backwards: never judged')
 check(passes(10,function(ctx) ctx.emergency={stranded=true} end).autoFlip==false,'player rejoining after a spin: never judged')
end
-- 10. Sortie des stands apprise : jamais sur une image « dans la voie », ni sur la voiture de sécurité ; une sortie
-- fausse est remplacée par celle vue plus souvent.
function T.pit_exit_learning_is_robust()
 local ctx=scene({{spline=0.9,kmh=150},{spline=0.3,kmh=150,lc={safety=true}}})
 ctx.cfg.hazards=false; ctx.cfg.gaps=false; ctx.cfg.sideBySide=false
 local s=Spotter.new()
 local t=0
 local function run(seconds) for _=1,math.floor(seconds*10+0.5) do t=t+0.1; at(ctx,t); Spotter.step(s,ctx) end end
 local c=ctx.F.cars[1]
 run(0.5); c.pitlane=true; run(0.1); c.pitlane=false; run(0.5)
 check(s.exitSpline==nil,'one frame in the lane at speed: not an exit')
 local sc=ctx.F.cars[2]
 sc.pitlane=true; sc.kmh=60; run(5); sc.pitlane=false; run(0.5)
 check(s.exitSpline==nil,'safety car leaving the lane: not learnt')
 local function exit(at) c.pitlane=true; c.kmh=60; c.spline=at-0.01; run(5); c.pitlane=false; c.spline=at; run(0.5) end
 exit(0.05)
 near(s.exitSpline,0.05,1e-6,'real exit learnt')
 -- Sortie fausse déjà apprise (une fois) : deux vraies sorties la remplacent.
 s.exitSpline=0.6; s.exitSamples=1; s.exitAlt=nil; s.exitAltN=0
 exit(0.05); near(s.exitSpline,0.6,1e-6,'one sample against one: kept')
 exit(0.05); near(s.exitSpline,0.05,1e-6,'seen more often: replaces the wrong exit')
 Spotter.reset(s)
 near(s.exitSpline,0.05,1e-6,'kept across sessions')
end
-- 11. Fin de VSC annulée par une voiture de sécurité : « SC appelée », pas « reste en file ».
function T.vsc_ending_escalated_to_safety_car()
 local ctx,v=scene({})
 local s=Spotter.new()
 local d=ctx.link.d
 at(ctx,1); Spotter.step(s,ctx)
 d.neutral=true; d.neutralMode='vsc'; at(ctx,2); Spotter.step(s,ctx)
 d.ending=true; at(ctx,3); Spotter.step(s,ctx)
 v.queue={}
 d.ending=false; d.neutralMode='sc'; d.safetyPhase='call'; at(ctx,4); Spotter.step(s,ctx)
 local q=queued(v,'neutral')
 check(q and q.sense=='scCall','safety car called, not "stay in line": '..tostring(q and q.sense))
 -- Fin de VSC annulée, VSC maintenue : redite.
 local c2,v2=scene({})
 local s2=Spotter.new(); local d2=c2.link.d
 at(c2,1); Spotter.step(s2,c2)
 d2.neutral=true; d2.neutralMode='vsc'; at(c2,2); Spotter.step(s2,c2)
 d2.ending=true; at(c2,3); Spotter.step(s2,c2)
 v2.queue={}
 d2.ending=false; at(c2,4); Spotter.step(s2,c2)
 check(queued(v2,'neutral') and queued(v2,'neutral').sense=='vsc','VSC said again when its end is cancelled')
end
-- 15. Voiture qui arrive à côté : décalages tenus oubliés hors conditions (sous la vitesse minimale, au freinage).
function T.incoming_hold_is_forgotten_out_of_conditions()
 local ctx=scene({},{kmh=40})
 local s=Spotter.new()
 s.incomingSince[1]=0
 Spotter.incoming(s,ctx,ctx.F.cars[0],s.prox,{})
 check(next(s.incomingSince)==nil,'below the minimum speed: holds forgotten')
 ctx.F.cars[0].kmh=150; ctx.F.me.brake=0.8; s.incomingSince[1]=0
 Spotter.incoming(s,ctx,ctx.F.cars[0],s.prox,{})
 check(next(s.incomingSince)==nil,'braking: holds forgotten')
end
-- Voisins au classement en un seul parcours : mêmes réponses que la recherche par place.
function T.neighbours_match_by_position()
 local ctx=scene({{position=2},{position=4},{position=0},{position=1}},{pos=3})
 local F=ctx.F
 local a,b=Position.neighbours(F,F.cars[0])
 check(a==Position.byPosition(F,2) and b==Position.byPosition(F,4) and a==1 and b==2,'ahead and behind')
 F.cars[0].position=1; a,b=Position.neighbours(F,F.cars[0])
 check(a==nil and b==1,'leader: nobody ahead (a car without a place is not "P0")')
 F.cars[0].position=0; a,b=Position.neighbours(F,F.cars[0])
 check(a==nil and b==nil,'unknown place: nobody')
end
-- 1.3.3. « wrong » d'AdvancedIA 1.59 = la voiture recule sur le tour, marche arrière comprise : le joueur qui recule
-- nez dans le bon sens n'est jamais dit « à contresens » ; celui qui roule vraiment à contresens l'est toujours.
function T.reversing_is_not_wrong_way()
 for _,case in ipairs({{-4,false},{6,true},{0,true}}) do
  local ctx,v=scene({},{kmh=20})
  ctx.link.cars[0]={valid=true,incident=false,onTrack=true,still=0,spin=false,wrong=true}
  ctx.F.me.vz=case[1]
  local em=Emergency.new(); em.moved=true
  for k=1,5 do at(ctx,1+k*0.1); Emergency.step(em,ctx,0.1) end
  local q=queued(v,'stranded')
  check((q~=nil and q.text:find('contresens',1,true)~=nil)==case[2],'vz '..case[1]..': wrong way said = '..tostring(case[2]))
 end
end
-- 1.3.5. Clés annexes d'AdvancedIA (src/side.lua) : lecture, référence jamais utilisée, clé figée.
function T.side_keys_parse_and_reference()
 local Side=require('src/side')
 local tr=Side.parse('traffic','v=1;blue=lap;stage=advise;car=3;gap=120;closing=25;count=1;stamp=900')
 check(tr and tr.blue=='lap' and tr.stage=='advise' and tr.car==3 and tr.count==1,'traffic parsed')
 check(Side.parse('traffic','v=2;blue=lap;stage=advise;car=3;gap=120;closing=25;count=1;stamp=900')==nil,'other version ignored')
 check(Side.parse('traffic','v=1;blue=fast;stage=advise;car=3;gap=120;closing=25;count=1')==nil,'unknown value refused')
 check(Side.parse('traffic','v=1;blue=lap;stage=advise;car=3')==nil,'missing field refused')
 check(Side.parse('weather',12)==nil and Side.parse('weather',nil)==nil,'number or nil: nothing')
 local wx=Side.parse('weather','v=1;wet=0.10;rain=0.00;water=0.00;trend=wetting;eta=600;next=inter;forecast=rain;forecastIn=300;aiDry=10;aiRain=0;extra=1;stamp=50')
 check(wx and wx.next=='inter' and wx.forecastIn==300 and wx.eta==600,'weather parsed, unknown field ignored')
 local off=Side.parse('weather','v=1;wet=0.00;rain=0.00;water=0.00;trend=off;eta=-1;next=none;forecast=unknown;forecastIn=-1;aiDry=0;aiRain=0;stamp=70')
 check(off and off.trend=='off' and off.next=='none','final record of a switched-off weather key accepted')
 -- Texte trouvé au chargement : référence, jamais utilisée ; un changement dans la séance : la clé tourne.
 local s=Side.new(); local store={['AdvancedIA.traffic']='v=1;blue=lap;stage=order;car=3;gap=40;closing=30;count=1;stamp=10'}
 local function read(k) return store[k] end
 Side.step(s,read,1); check(Side.get(s,'traffic')==nil,'reference never used')
 Side.step(s,read,2); check(Side.get(s,'traffic')==nil,'unchanged key (setting off): still nothing')
 store['AdvancedIA.traffic']='v=1;blue=lap;stage=advise;car=2;gap=150;closing=20;count=1;stamp=20'
 Side.step(s,read,2.2); check(Side.get(s,'traffic')==nil,'read at most every 0.5 s')
 Side.step(s,read,2.6); local g=Side.get(s,'traffic'); check(g and g.car==2,'changed in the session: live')
 Side.reset(s); Side.step(s,read,3); check(Side.get(s,'traffic')==nil,'new session: reference again')
end
-- 1.3.5. Drapeau bleu : simple sans la nuance ; en deux temps avec elle (annonce puis ordre, chacun une fois) ; classe
-- plus rapide (son clip, et le trafic plus rapide se tait pour elle) ; clé qui ne dit rien : le bleu simple après 1,5 s.
function T.blue_flag_in_two_stages()
 local Side=require('src/side')
 local function rig(traffic)
  local ctx,v=scene({{spline=0.5-60/4000,kmh=230}})
  ctx.cfg.blueFlags=true; ctx.cfg.sideBySide=false; ctx.cfg.hazards=false; ctx.cfg.gaps=false; ctx.cfg.fasterBehind=true
  local side=Side.new(); ctx.side=side
  local store={['AdvancedIA.traffic']='v=1;blue=none;stage=none;car=-1;gap=0;closing=0;count=0;stamp=1'}
  local function read(k) return store[k] end
  Side.step(side,read,0)
  if traffic then store['AdvancedIA.traffic']=traffic; Side.step(side,read,1) end
  return ctx,v,Spotter.new(),store,function(t) Side.step(side,read,t) end
 end
 local function blueCount(v) local n=0; for _,q in ipairs(v.queue) do if q.key=='blue' or q.key=='blueAdvise' then n=n+1 end end return n end
 -- Sans la nuance (clé qui ne tourne pas) : le drapeau bleu, tout de suite.
 local ctx,v,s=rig(nil)
 at(ctx,2); Spotter.step(s,ctx); ctx.link.d.panelDecided='blue'; at(ctx,2.1); Spotter.step(s,ctx)
 local q=queued(v,'blue'); check(q and q.text:find('Drapeau bleu',1,true) and blueCount(v)==1,'plain blue flag at once')
 -- Annonce puis ordre, 4 s plus tard (moins que le délai de 12 s du drapeau bleu) : chacun dit une fois.
 local ctx2,v2,s2,store,feed=rig('v=1;blue=lap;stage=advise;car=1;gap=150;closing=20;count=1;stamp=2')
 at(ctx2,2); Spotter.step(s2,ctx2); ctx2.link.d.panelDecided='blue'; at(ctx2,2.1); Spotter.step(s2,ctx2)
 q=queued(v2,'blueAdvise'); check(q and q.text:find('en approche',1,true) and blueCount(v2)==1,'advise stage first')
 at(ctx2,4); Spotter.step(s2,ctx2); check(blueCount(v2)==1,'advise not repeated')
 store['AdvancedIA.traffic']='v=1;blue=lap;stage=order;car=1;gap=40;closing=25;count=1;stamp=6'; feed(6)
 at(ctx2,6.1); Spotter.step(s2,ctx2); at(ctx2,7); Spotter.step(s2,ctx2)
 check(queued(v2,'blue') and not queued(v2,'blueAdvise') and blueCount(v2)==1,'order said once, advise withdrawn')
 -- Classe plus rapide : son clip ; le trafic plus rapide se tait pour cette voiture.
 local ctx3,v3,s3=rig('v=1;blue=class;stage=advise;car=1;gap=150;closing=40;count=1;stamp=2')
 at(ctx3,2); Spotter.step(s3,ctx3); ctx3.link.d.panelDecided='blue'; at(ctx3,2.1); Spotter.step(s3,ctx3)
 q=queued(v3,'blue'); check(q and q.text:find('Classe plus rapide',1,true) and blueCount(v3)==1,'faster class call')
 check(s3.faster[1]==ctx3.now,'faster traffic call muted for that car')
 for k=1,30 do at(ctx3,2.1+k*0.1); Spotter.step(s3,ctx3) end
 check(not queued(v3,'fasterBehind'),'never both')
 -- Clé qui tourne mais ne dit rien de ce bleu : attente de 1,5 s, puis le drapeau bleu simple.
 local ctx4,v4,s4=rig('v=1;blue=none;stage=none;car=-1;gap=0;closing=0;count=0;stamp=3')
 at(ctx4,2); Spotter.step(s4,ctx4); ctx4.link.d.panelDecided='blue'; at(ctx4,2.1); Spotter.step(s4,ctx4)
 check(blueCount(v4)==0,'waiting for the traffic key')
 at(ctx4,3.7); Spotter.step(s4,ctx4); check(blueCount(v4)==0,'still waiting at 1.6 s (key up to 2 s late)')
 at(ctx4,4.7); Spotter.step(s4,ctx4); check(queued(v4,'blue') and blueCount(v4)==1,'plain blue after the wait')
 -- Clé figée sur « annonce » (réglage coupé en cours de séance) : inchangée depuis 5 s, jamais lue ; drapeau bleu simple
 -- après l'attente, jamais un « prépare-toi » sans l'ordre.
 local ctx5,v5,s5,_,feed5=rig('v=1;blue=lap;stage=advise;car=1;gap=150;closing=20;count=1;stamp=2')
 feed5(6); at(ctx5,6); Spotter.step(s5,ctx5); ctx5.link.d.panelDecided='blue'; at(ctx5,6.1); Spotter.step(s5,ctx5)
 check(blueCount(v5)==0,'frozen key: not read')
 at(ctx5,8.7); Spotter.step(s5,ctx5); check(queued(v5,'blue') and not queued(v5,'blueAdvise') and blueCount(v5)==1,'frozen key: plain blue')
 -- Annonce dite, puis la clé se fige : l'ordre suit.
 local ctx6,v6,s6,_,feed6=rig('v=1;blue=lap;stage=advise;car=1;gap=150;closing=20;count=1;stamp=2')
 at(ctx6,2); Spotter.step(s6,ctx6); ctx6.link.d.panelDecided='blue'; at(ctx6,2.1); Spotter.step(s6,ctx6)
 check(queued(v6,'blueAdvise'),'advise said')
 feed6(5); at(ctx6,5); Spotter.step(s6,ctx6); check(queued(v6,'blue') and not queued(v6,'blueAdvise'),'key frozen after the advise: order said')
end
-- 1.3.6. Appel du départ lancé (standing « roll », deux colonnes décalées) : premier « voiture à gauche » dit, puis ni
-- « toujours là » ni « dégagé » ni nouvel appel ; au vert, le côte à côte redevient normal.
function T.rolling_start_columns_are_quiet()
 local ctx,v=scene({{x=-3,z=0,spline=0.5,kmh=80}},{kmh=80,d={standing='roll',neutral=true,neutralMode='fcy',relaunch=true}})
 ctx.cfg.sideBySide=true; ctx.cfg.stillThere=true; ctx.cfg.hazards=false; ctx.cfg.gaps=false; ctx.cfg.anticipation=false
 local s=Spotter.new()
 local function keys() local out={}; for _,q in ipairs(v.queue) do out[#out+1]=q.key end; return table.concat(out,',') end
 local function count(prefix) local n=0; for _,q in ipairs(v.queue) do if q.key:sub(1,#prefix)==prefix then n=n+1 end end return n end
 local t=0
 local function run(seconds) for _=1,seconds*10 do t=t+0.1; at(ctx,t); Spotter.step(s,ctx) end end
 run(2)
 check(count('side:')==1,'first side call during the roll call: '..keys())
 v.queue={}
 -- Voisine qui recule puis revient à hauteur (colonnes qui ondulent), et reste là 10 s : silence.
 ctx.F.cars[1].z=-12; run(2); ctx.F.cars[1].z=0; run(10)
 check(count('side:')==0,'quiet during the roll call: '..keys())
 -- Vert : standing repasse à none, la voisine s'en va puis revient : côte à côte normal.
 ctx.link.d.standing='none'; ctx.link.d.neutral=false; ctx.link.d.relaunch=false
 ctx.F.cars[1].z=-12; run(2); v.queue={}; ctx.F.cars[1].z=0; run(2)
 check(count('side:left')+count('side:right')==1,'side by side back to normal at the green: '..keys())
end
-- 1.3.8. Joueur au stand (course abandonnée) : ni « la fenêtre est ouverte » ni « c'est le moment de rentrer » ; une
-- ouverture vue dans la voie est dite à la sortie si l'arrêt reste dû, et jamais s'il a été fait.
function T.no_pit_calls_while_in_the_pits()
 local function run(exitDue)
  local ctx,v=scene({},{kmh=0})
  local s=Spotter.new(); local d=ctx.link.d
  ctx.F.cars[0].pitlane=true
  d.pitState='pending'; d.pitOpen=0.3; d.pitClose=0.7; d.pitPosition=0.2
  at(ctx,1); Spotter.step(s,ctx)
  d.pitState='open'; d.pitDue=1; d.pitPosition=0.35; at(ctx,2); Spotter.step(s,ctx)
  d.pitRemind=true; d.pitPosition=0.65; at(ctx,3); Spotter.step(s,ctx)
  local inside=queued(v,'pitCall')
  d.pitDue=exitDue; ctx.F.cars[0].pitlane=false; ctx.F.cars[0].kmh=80; at(ctx,4); Spotter.step(s,ctx)
  return inside,queued(v,'pitCall')
 end
 local inside,out=run(1)
 check(not inside,'in the pits: no pit window call')
 check(out and out.sense=='pitOpen','window opened in the pits, stop still due: said at the exit, got '..tostring(out and out.sense))
 inside,out=run(0)
 check(not out,'stop made in the pits: nothing at the exit')
 -- Témoin : sur la piste, l'ouverture est dite.
 local ctx,v=scene({})
 local s=Spotter.new(); local d=ctx.link.d
 d.pitState='pending'; at(ctx,1); Spotter.step(s,ctx)
 d.pitState='open'; d.pitDue=1; at(ctx,2); Spotter.step(s,ctx)
 check(queued(v,'pitCall'),'on track: window call said')
end
-- 1.3.9 (demande du pilote) : fin de VSC décomptée « 3, 2, 1 », puis « Go » à la relance au lieu du vert complet.
function T.vsc_end_countdown()
 local function run(on)
  local ctx,v=scene({})
  ctx.cfg.vscCountdown=on
  local s=Spotter.new(); local d=ctx.link.d
  at(ctx,1); Spotter.step(s,ctx)
  d.neutral=true; d.neutralMode='vsc'; at(ctx,2); Spotter.step(s,ctx)
  d.ending=true; d.endingLeft=10; at(ctx,3); Spotter.step(s,ctx)
  local said={}
  local t=3
  for left=9.75,0.25,-0.25 do
   t=t+0.25; d.endingLeft=left; at(ctx,t); Spotter.step(s,ctx)
   local q=take(v,'vscCount')
   if q then said[#said+1]=q.text..'@'..left end
  end
  v.queue={}
  d.neutral=false; d.ending=false; d.endingLeft=0; d.greenLeft=5; at(ctx,t+0.25); Spotter.step(s,ctx)
  return said,queued(v,'restart')
 end
 local said,restart=run(true)
 check(#said==3,'three numbers: '..table.concat(said,' '))
 check(#said==3 and said[1]:match('^3@3') and said[2]:match('^2@2') and said[3]:match('^1@1'),'said as each second passes: '..table.concat(said,' '))
 check(restart and restart.prio==1 and restart.text:match('Go'),'Go at the restart: '..tostring(restart and restart.text))
 said,restart=run(false)
 check(#said==0,'setting off: no countdown')
 check(restart and restart.text:match('vert'),'setting off: full green flag as before: '..tostring(restart and restart.text))
end
-- Arrêt obligatoire levé : dit sur l'annonce d'AdvancedIA qui en donne la raison (1.63 et plus), sur le changement de
-- pitWaived avant (course mouillée seulement).
function T.mandatory_stop_lifted_reason()
 local function run(release,kind,stops)
  local ctx,v=scene({})
  ctx.link.remoteRelease=release
  local s=Spotter.new(); local d=ctx.link.d
  at(ctx,1); Spotter.step(s,ctx)
  d.pitWaived=true; d.pitState='off'
  if kind then d.messageId=(d.messageId or 0)+1; d.messageKind=kind; d.messageValue=80; d.messageExtra=100 end
  if stops then d.mandatoryStops=stops end
  at(ctx,3); Spotter.step(s,ctx)
  return queued(v,kind or 'pitWaived'),v
 end
 local q=run('Beta 1.64',nil)
 check(q==nil,'1.64, waived without its message: nothing guessed')
 q=run('Beta 1.64','pitSprint',0)
 check(q and q.text:match('sprint'),'sprint race, no stop programmed: '..tostring(q and q.text))
 local v
 q,v=run('Beta 1.64','pitSprint',1)
 local written=false
 for _,e in ipairs(v.log or {}) do if e.text and e.text:lower():match('sprint') then written=true end end
 for _,e in ipairs(v.queue) do if e.text and e.text:lower():match('sprint') then written=true end end
 check(q==nil and not written,'stop programmed in AdvancedIA: never a sprint race, neither said nor written')
 q=run('Beta 1.63','pitShort')
 check(q and q.text:match('trop courte'),'race too short: '..tostring(q and q.text))
 q=run('Beta 1.63','pitWaived')
 check(q and q.text:match('mouillée'),'wet race: '..tostring(q and q.text))
 q=run('Beta 1.62',nil)
 check(q and q.text:match('mouillée'),'before 1.63: wet race on the flag: '..tostring(q and q.text))
end
-- AdvancedIA Beta 1.63 : jaune d'avertissement (voiture lente au bord) : dépassement permis, jamais interdit.
function T.warning_yellow_overtaking_allowed()
 local ctx,v=scene({})
 local s=Spotter.new(); local d=ctx.link.d
 at(ctx,1); Spotter.step(s,ctx)
 d.yellow=true; d.panelDecided='slowWarn'; d.panelKind='slowWarn'; at(ctx,2); Spotter.step(s,ctx)
 local q=queued(v,'panel:slowWarn')
 check(q and q.text:match('dépassement permis'),'warning yellow said, overtaking allowed: '..tostring(q and q.text))
 check(not queued(v,'zone'),'no yellow zone call (no overtaking)')
end
-- AdvancedIA 1.64 : départ interrompu, un tour de plus ; les feux encore en file sont abandonnés.
function T.start_aborted()
 local function run(extra)
  local ctx,v=scene({})
  local s=Spotter.new(); local d=ctx.link.d
  at(ctx,1); Spotter.step(s,ctx)
  d.standing='lights'; at(ctx,2); Spotter.step(s,ctx)
  local lights=queued(v,'start')
  d.standing='form'; d.messageId=(d.messageId or 0)+1; d.messageKind='startDelayed'; d.messageValue=1; d.messageExtra=extra
  at(ctx,3); Spotter.step(s,ctx)
  return lights,queued(v,'start'),queued(v,'startDelayed')
 end
 local lights,after,q=run(0)
 check(lights~=nil,'lights queued first')
 check(after==nil,'lights dropped at the abort')
 check(q and q.text:match('arrêté'),'standing start next: '..tostring(q and q.text))
 lights,after,q=run(1)
 check(q and q.text:match('lancé'),'rolling start next: '..tostring(q and q.text))
end
return T
