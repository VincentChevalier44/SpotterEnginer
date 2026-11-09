-- Pont réel d'AdvancedIA (src/bridge.lua, chargé sous 'aai/bridge') -> liaison et spotter de SpotterEnginer.
local Bridge=require('aai/bridge')
local Layout=require('src/bridge_layout')
local Link=require('src/link')
local Voice=require('src/voice')
local Say=require('src/say')
local Spotter=require('src/spotter')
local Timing=require('src/timing')
local Config=require('src/config')
local T={}
local check=require('tests/helpers').check
local function structs()
 local hello={bridgeVersion=0,release='',heartbeat=0,closed=false}
 local data={cars={}}
 for _,f in ipairs(Layout.fields) do if f[2]=='bool' then data[f[1]]=false elseif f[2]=='string' then data[f[1]]='' else data[f[1]]=0 end end
 for i=0,Layout.maxCars-1 do local c={}; for _,f in ipairs(Layout.car) do if f[2]=='bool' then c[f[1]]=false else c[f[1]]=0 end end; data.cars[i]=c end
 local strict={__index=function(_,k) error('no member named '..tostring(k),2) end,__newindex=function(_,k) error('no member named '..tostring(k)..' (write)',2) end}
 for i=0,Layout.maxCars-1 do setmetatable(data.cars[i],strict) end
 local cars=data.cars; data.cars=nil; setmetatable(data,strict); rawset(data,'cars',cars)
 setmetatable(hello,strict)
 return hello,data
end
local function engine()
 local frame={count=3,player=2,online=false,replay=false,paused=false,flag=0,flagOwned=false,cars={}}
 for i=1,3 do frame.cars[i]={valid=true,pit=false,safetyCar=false,penaltyType=0,penaltyParam=0} end
 local e={g={enabled=true,language='fr'},run={penaltyDisqualify=5,mandatoryStops=1,maxStintMin=0,minPitTime=0},guard='ready',panic=false,
  profile='C',session=2,sessionType=3,time=100,lights={value=0,reason='',slowSlot=0,slowGap=0,meatballUntil=-math.huge,damaged=false},
  panel={decided='none',kind='none',title='',short='',double=false,blueGap=nil,noPass=false,lit=0,infractions=0,infractionMax=0,warnUntil=-math.huge},
  incidents={neutral=false,neutralMode='local',neutralSince=0,escalated=false,relaunch=false,ending=false,endingUntil=0,safetyPhase='none',
   safetyFailed=false,safety=0,red=false,reds=0,greenUntil=-math.huge,restart=false,playerRestart=false,standing='none',gridLit=0,gridSlot=0,
   gridGap=0,gridPlaced=false,gridPassed=false,jumpUntil=-math.huge,pitsClosed=false,slipperyUntil=-math.huge,playerZone=false,
   playerInside=false,playerZoneDouble=false,playerZoneSlot=0,playerToZone=0,playerDistance=0,playerNoPass=false,playerYellow=false,
   zoneCount=0,drsReason='',drsLapsLeft=-1,playerPitDue=0,playerPitRemind=false,messageId=0,messageKind='',messageValue=0,messageExtra=0,
   cars={{},{},{}}},
  delta={value=nil,kind='',infraction=false},deltaBeep={beepId=0},
  penalties={requestId=0,reason='',count=0,seconds=5,kind='slow',disqualified=false,passed=0,giveBack=0,giveBackUntil=0,ai={count={},dq={}}},
  drs={beepId=0},playerDrs=0,commands={{},{},{}},states={{},{},{}},flash={eventId=0,heard=0},
  pits={state='pending',justClosed=false,csp=false,position=0.1,open=0.3,close=0.7,done=0,total=0,waived=false,cars={{lastStop=0,stops=0},{lastStop=0,stops=0},{lastStop=0,stops=0}}},
  race={progress=0.1,lapsLeft=20,known=true},weather={wet=false},hud={finished=false,aiSerial=0,aiCode='',aiTitle='',aiShort=''},
  sanctions={cars={{},{},{}}},strategy={cars={{planned=true,stops=1,nextLap=12,cause='undercut'},{},{}}}}
 return e,frame
end
function T.publish_and_connect()
 local hello,data=structs()
 local e,frame=engine()
 local b=Bridge.new('Beta 1.45')
 Bridge.beat(b,hello); Bridge.publish(b,data,e,frame)
 check(hello.bridgeVersion==Layout.version,'version'); check(hello.release=='Beta 1.45','release'); check(hello.heartbeat==1,'beat')
 check(data.player==1,'player slot 2 -> AC index 1: '..tostring(data.player))
 check(data.ready and data.enabled,'ready')
 check(data.cars[0].valid and data.cars[0].planned and data.cars[0].nextStopLap==12,'AI plan published')
 check(data.cars[0].stopCause==Layout.code(Layout.causes,'undercut'),'cause code')
 check(data.cars[5].valid==false,'empty slot')
 local k=Link.new(true,true,'Beta 1.45')
 Link.step(k,hello,data,10)
 check(k.state=='connected','state '..k.state)
 -- Battement arrêté : arrêté au-delà de 2,5 s.
 Link.step(k,hello,data,13)
 check(k.state=='waiting','stale -> '..k.state)
 Bridge.beat(b,hello); Link.step(k,hello,data,13.1)
 check(k.state=='connected','beat again')
 frame.paused=true; Bridge.beat(b,hello); Bridge.publish(b,data,e,frame); Link.step(k,hello,data,13.2)
 check(k.state=='suspended' and k.reason=='paused','paused -> '..k.state..' '..k.reason)
 frame.paused=false; e.g.enabled=false; Bridge.beat(b,hello); Bridge.publish(b,data,e,frame); Link.step(k,hello,data,13.3)
 check(k.reason=='disabled','disabled')
 Bridge.close(b,hello); Link.step(k,hello,data,13.4)
 check(k.state=='closed','closed')
end
function T.states_without_aai()
 local k=Link.new(false,false,'')
 Link.step(k,nil,nil,1); check(k.state=='absent','absent')
 local k2=Link.new(true,false,'Beta 1.44')
 Link.step(k2,nil,nil,1); check(k2.state=='nobridge','nobridge '..k2.state)
 local hello,data=structs(); hello.heartbeat=5; hello.bridgeVersion=99
 local k3=Link.new(true,true,'')
 Link.step(k3,hello,data,1); check(k3.state=='version','version '..k3.state)
end
function T.long_text_is_cut_on_utf8_boundary()
 local hello,data=structs()
 local e,frame=engine()
 e.panel.title=string.rep('é',40) -- 80 octets, capacité 64
 local b=Bridge.new('x'); Bridge.publish(b,data,e,frame)
 check(#data.panelTitle<64,'cut '..#data.panelTitle)
 check(data.panelTitle==string.rep('é',31),'no broken character')
end
-- Spotter sur le pont : transitions annoncées une fois, référence à la connexion.
local function rig()
 local hello,data=structs()
 local e,frame=engine()
 local box={b=Bridge.new('Beta 1.45')}
 local k=Link.new(true,true,'')
 local played={}
 local port={play=function(p) played[#played+1]=p; return {p=p} end,playing=function() return false end,stop=function() end}
 local voice=Voice.new(port)
 local files={}
 local sayer=Say.new(voice,files,'vox','FR',nil)
 local F={cars={},count=3,player=1,isRace=true,trackLength=4000,pitSpeed=80,started=true,me={cuts=0,lapValid=true}}
 for i=0,2 do F.cars[i]={valid=true,x=i*30,z=0,lookX=0,lookZ=1,kmh=150,spline=0.1*i,laps=3,position=i+1,pitlane=false,name='P'..i} end
 local ctx={F=F,link=k,say=sayer,voice=voice,cfg=Config.defaults(),timing=Timing.new(),now=0,real=0}
 ctx.cfg.gaps=false; ctx.cfg.sideBySide=false
 local s=Spotter.new()
 local function frameStep(t)
  ctx.now=t; ctx.real=t
  Bridge.beat(box.b,hello); Bridge.publish(box.b,data,e,frame); Link.step(k,hello,data,t)
  Spotter.step(s,ctx)
 end
 return {e=e,frame=frame,voice=voice,step=frameStep,ctx=ctx,s=s,box=box}
end
local function queued(voice,key) for _,q in ipairs(voice.queue) do if q.key==key then return q end end return nil end
function T.spotter_announces_transitions_once()
 local r=rig()
 r.step(1)
 check(#r.voice.queue==0,'nothing at reference')
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='sc'; r.e.incidents.neutralSince=1
 r.step(2)
 local q=queued(r.voice,'neutral'); check(q,'SC announced'); check(q.text:find('Voiture de s',1,true),'text '..q.text)
 r.voice.queue={}
 r.step(3); check(not queued(r.voice,'neutral'),'only once')
 r.e.incidents.safetyPhase='in'; r.step(4); check(queued(r.voice,'scIn'),'SC in this lap')
 r.e.incidents.neutral=false; r.e.incidents.greenUntil=104+5; r.e.time=104; r.step(5)
 local gr=queued(r.voice,'restart'); check(gr and gr.text:find('Drapeau vert',1,true),'green after the SC')
 -- Rendre la place : voiture de l'emplacement 3 = indice 2.
 r.e.penalties.giveBack=3; r.step(6)
 local g=queued(r.voice,'giveBack'); check(g and g.text:find('P2'),'give back with name: '..tostring(g and g.text))
 -- Delta négatif sous VSC.
 r.e.delta.value=0.4; r.e.delta.kind='vsc'; r.step(7)
 r.e.delta.value=-0.3; r.step(8); check(queued(r.voice,'delta'),'delta negative')
 -- Fenêtre d'arrêt ouverte.
 r.e.pits.state='open'; r.step(9); check(queued(r.voice,'pitCall'),'pit window open')
end
-- Sortie d'une zone jaune locale (AdvancedIA montre le vert) : rien n'est dit ; fin de SC avec relance : un seul
-- message.
function T.green_only_after_neutralisation()
 local r=rig()
 r.step(1)
 r.e.incidents.greenUntil=r.e.time+5; r.step(2)
 check(not queued(r.voice,'restart'),'no green when leaving a local yellow zone')
 r.e.incidents.greenUntil=-math.huge; r.step(3)
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='sc'; r.step(4)
 r.voice.queue={}
 r.e.incidents.neutral=false; r.e.incidents.relaunch=true; r.e.incidents.greenUntil=r.e.time+5; r.step(5)
 r.e.incidents.relaunch=false; r.step(6)
 local n=0; for _,q in ipairs(r.voice.queue) do if q.key=='restart' then n=n+1 end end
 check(n==1,'one green-type call at the end of the SC: '..n)
end
-- Stands : à l'ouverture de la fenêtre (rappel d'AdvancedIA, panneau « pit »), un seul message avec le tour du plan,
-- jamais « rentre aux stands » ; sans plan, le rappel de fin de fenêtre reste.
function T.pit_calls_follow_the_plan()
 local r=rig()
 local t={ready=true,plan={ok=true,optimal=14,window={12,16}}}
 r.ctx.strategist=function() return t end
 r.step(1)
 r.e.pits.state='open'; r.e.incidents.playerPitRemind=true; r.e.incidents.playerPitDue=1; r.e.panel.decided='pit'
 r.e.pits.position=0.1; r.e.pits.open=0.1; r.e.pits.close=0.9; r.step(2)
 local q=queued(r.voice,'pitCall')
 check(q and q.role=='engineer' and q.text:find('Tour optimal',1,true) and q.text:find('14',1,true),'window open with the plan lap: '..tostring(q and q.text))
 for _,x in ipairs(r.voice.queue) do check(not x.text:find('rentre',1,true),'no « rentre aux stands »: '..x.text) end
 check(t.announcedWindow and t.announcedWindow[1]==12,'strategist window marked as announced')
 r.voice.queue={}
 -- Fin de fenêtre avec un plan : rien (le box viendra de l'ingénieur).
 r.e.incidents.playerPitRemind=false; r.step(3)
 r.e.pits.position=0.85; r.e.incidents.playerPitRemind=true; r.step(4)
 check(not queued(r.voice,'pitCall'),'no closing reminder when the plan will call the box')
 -- Sans plan : le rappel reste (arrêt obligatoire jamais oublié).
 r.ctx.strategist=function() return nil end
 r.e.incidents.playerPitRemind=false; r.step(5); r.e.incidents.playerPitRemind=true; r.step(6)
 local c=queued(r.voice,'pitCall'); check(c and c.text:find('ferme bientôt',1,true),'closing reminder without a plan')
end
-- Plan pas encore prêt (premiers tours, estimations) : à l'ouverture de la fenêtre, la règle seule par le spotter (sans
-- tour optimal) ; le rappel de fin de fenêtre d'AdvancedIA reste ; aucun « box », même sous neutralisation.
function T.no_strategy_calls_before_plan_ready()
 local r=rig()
 local t={ready=false,plan={ok=true,optimal=3,window={2,4}}}
 r.ctx.strategist=function() return t end
 r.step(1)
 r.e.pits.state='open'; r.e.incidents.playerPitDue=1; r.e.pits.position=0.2; r.e.pits.open=0.2; r.e.pits.close=0.9; r.step(2)
 local q=queued(r.voice,'pitCall')
 check(q and q.role=='spotter' and not q.text:find('Tour optimal',1,true),'window open: rule only: '..tostring(q and q.text))
 check(not t.announcedWindow,'window not marked as announced (it will be when the plan is ready)')
 r.voice.queue={}
 r.e.pits.position=0.85; r.e.incidents.playerPitRemind=true; r.step(3)
 local c=queued(r.voice,'pitCall'); check(c and c.text:find('ferme bientôt',1,true),'closing reminder kept before the plan is ready')
 local Strategist=require('src/strategist')
 local F={isRace=true,player=0,cars={[0]={laps=1,spline=0.7,pitlane=false}}}
 local ctx={F=F,cfg={boxCalls=true,neutralBox=true,tolerance=2,neutralFactor=0.5},link={d={pitsClosed=false,neutral=true}},say=r.ctx.say,real=0}
 local tb={ready=false,plan={ok=true,optimal=3,costs={0},cost=0},boxSaid={},model={pitLane=20}}
 r.voice.queue={}
 Strategist.boxCalls(tb,ctx); F.cars[0].laps=2; F.cars[0].spline=0.3; Strategist.boxCalls(tb,ctx)
 check(#r.voice.queue==0,'no box before the plan is ready')
 tb.ready=true; Strategist.boxCalls(tb,ctx)
 check(queued(r.voice,'box'),'box once the plan is ready')
end
-- Avis d'arrêt d'AdvancedIA (règle F1 du composé, Beta 1.49) : chaque genre dit une fois par le spotter, avec le texte
-- d'AdvancedIA (composés) sur la radio, une seule ligne, même quand un plan de l'ingénieur annoncera le box ; direction
-- de course coupée : écrit seulement ; AdvancedIA dans une autre langue : texte du clip.
function T.pit_compound_notices()
 local r=rig()
 r.ctx.strategist=function() return {ready=true,plan={ok=true,optimal=14,window={12,16}}} end
 local me=r.ctx.F.cars[1]
 me.laps=0
 r.step(1)
 local n=0
 local function emit(kind,title,text,value,extra)
  n=n+1; local inc=r.e.incidents
  inc.messageId=n; inc.messageKind=kind; inc.messageValue=value; inc.messageExtra=extra
  r.e.ownTitle=title; r.e.ownText=text
 end
 local function lines(pattern) local c=0; for _,l in ipairs(r.voice.log) do if l.text and l.text:find(pattern,1,true) then c=c+1 end end return c end
 -- Départ : la stratégie Quick Pitstop garde le même composé. Rien pendant le départ (grille, début du tour), dit une
 -- seule fois à la moitié du premier tour, même si AdvancedIA le redonne.
 me.spline=0.97
 emit('pitPlanSame','Stratégie des stands','Même composé prévu (SS)',2,2); r.step(2)
 check(not queued(r.voice,'pitPlanSame') and lines('Même composé prévu')==0,'nothing during the start')
 me.spline=0.2; emit('pitPlanSame','Stratégie des stands','Même composé prévu (SS)',2,2); r.step(2.5)
 check(not queued(r.voice,'pitPlanSame'),'nothing before half a lap')
 me.spline=0.55; r.step(2.8)
 local q=queued(r.voice,'pitPlanSame')
 check(q and q.role=='spotter' and q.prio==3 and q.ttl==20,'plan same after half a lap: '..tostring(q and q.ttl))
 check(q.text=='Stratégie des stands · Même composé prévu (SS)','AdvancedIA text on the radio: '..q.text)
 Voice.step(r.voice,2.85)
 check(lines('Même composé prévu (SS)')==1,'one radio line, no duplicate note')
 r.voice.queue={}; r.step(3); me.spline=0.6
 emit('pitPlanSame','Stratégie des stands','Même composé prévu (SS)',2,2); r.step(3.2); r.step(3.4)
 check(#r.voice.queue==0,'said once only')
 -- En course : rappel avant l'entrée des stands (ni dit ni écrit), puis entrée dans la voie, arrêt dû : dit.
 me.laps=10; r.e.pits.state='open'; r.e.incidents.playerPitDue=1
 emit('pitCompound','Arrêt obligatoire','Changez de composé : vous êtes en SS → montez S ou M',2,-1); r.step(4)
 check(not queued(r.voice,'pitCompound') and lines('montez S ou M')==0,'approach reminder quiet')
 me.pitlane=true; r.step(4.1)
 q=queued(r.voice,'pitCompound')
 check(q and q.ttl==10 and q.text:find('SS → montez S ou M',1,true),'compound call at pit lane entry: '..tostring(q and q.text))
 me.pitlane=false; r.step(4.2)
 -- Décisions.
 emit('pitNotCounted','Arrêt obligatoire','Arrêt non pris en compte : même composé (SS → SS)',2,2); r.step(5)
 q=queued(r.voice,'pitNotCounted'); check(q and q.prio==3 and q.text:find('(SS → SS)',1,true),'not counted')
 emit('pitValidated','Arrêt obligatoire','Arrêt obligatoire validé (SS → S)',2,1); r.step(6)
 q=queued(r.voice,'pitValidated'); check(q and q.prio==4 and q.text:find('(SS → S)',1,true),'validated')
 -- Direction de course coupée : pas de voix, la note écrite reste (une ligne). Dans la voie des stands (nouveau rappel
 -- toujours dit, voir compound_reminder_once_per_stint).
 r.voice.queue={}; r.ctx.cfg.raceControl=false; me.pitlane=true
 emit('pitCompound','Arrêt obligatoire','Changez de composé : vous êtes en M → montez S ou H',3,-1); r.step(7)
 check(not queued(r.voice,'pitCompound'),'no voice without race control')
 check(lines('vous êtes en M → montez S ou H')==1,'written note kept')
 -- AdvancedIA en anglais, app en français : texte du clip (pas de ligne en deux langues).
 r.ctx.cfg.raceControl=true; r.e.g.language='en'
 emit('pitNotCounted','Mandatory stop','Stop not counted: same compound (M → M)',3,3); r.step(8)
 q=queued(r.voice,'pitNotCounted'); check(q and q.text:find('Arrêt non compté',1,true) and not q.text:find('Mandatory',1,true),'clip text when languages differ: '..tostring(q and q.text))
 -- Deux annonces à une image d'écart (AdvancedIA réémet l'avis d'arrêt écrasé à l'image suivante) : les deux sont dites.
 r.e.g.language='fr'; r.voice.queue={}
 emit('aiDq','Disqualification','Voiture 3 disqualifiée',2,0); r.step(9)
 emit('pitNotCounted','Arrêt obligatoire','Arrêt non pris en compte : même composé (H → H)',4,4); r.step(9.016)
 check(queued(r.voice,'aiDq') and queued(r.voice,'pitNotCounted'),'both announcements one frame apart')
end
-- « Change de composé » : dit à l'entrée de la voie des stands, à n'importe quel tour, tant que l'arrêt obligatoire est
-- dû ; les rappels d'AdvancedIA avant l'entrée ne sont ni dits ni écrits (le dernier donne le texte) ; une fois par
-- entrée ; rien sans règle du composé connue, arrêt plus dû ou drive-through.
function T.compound_reminder_at_pit_lane_entry()
 local r=rig()
 r.ctx.strategist=function() return {ready=true,plan={ok=true,optimal=14,window={12,16}}} end
 local me=r.ctx.F.cars[1]
 me.laps=8
 r.e.pits.state='open'; r.e.incidents.playerPitDue=1
 r.step(1)
 local n=0
 local function remind(kind,text,at)
  n=n+1; local inc=r.e.incidents
  inc.messageId=n; inc.messageKind=kind; inc.messageValue=0; inc.messageExtra=-1
  r.e.ownTitle='Arrêt obligatoire'; r.e.ownText=text; r.step(at)
 end
 local function lines(pattern) local c=0; for _,l in ipairs(r.voice.log) do if l.text and l.text:find(pattern,1,true) then c=c+1 end end return c end
 local function lane(at) me.pitlane=true; r.step(at) end
 local function out(at) me.pitlane=false; r.step(at) end
 lane(2); check(not queued(r.voice,'pitCompound'),'no compound rule known yet: nothing'); out(3)
 remind('pitCompound','Changez de composé : vous êtes en SS → montez S ou M',10)
 check(not queued(r.voice,'pitCompound') and lines('montez S ou M')==0,'approach reminder: neither said nor written')
 remind('pitCompound','Changez de composé : vous êtes en SS → montez S ou M',11)
 check(#r.voice.queue==0,'second reminder of the approach: quiet')
 -- Tour 9, pas le tour 14 du plan : entrée dans la voie, dit (priorité 2, texte d'AdvancedIA).
 me.laps=9; lane(20)
 local q=queued(r.voice,'pitCompound')
 check(q and q.prio==2 and q.text=='Arrêt obligatoire · Changez de composé : vous êtes en SS → montez S ou M','said at pit lane entry: '..tostring(q and q.text))
 r.voice.queue={}
 remind('pitCompound','Changez de composé : vous êtes en SS → montez S ou M',21)
 check(not queued(r.voice,'pitCompound'),'AdvancedIA reminder in the lane after the call: quiet')
 r.step(25); check(not queued(r.voice,'pitCompound'),'once per entry')
 -- Arrêt non compté : à l'entrée suivante, redit.
 out(40); me.laps=11; lane(200); check(queued(r.voice,'pitCompound'),'next pit entry, stop still due: said again')
 r.voice.queue={}; out(210)
 -- Stratégie au même composé : clip et texte de la stratégie.
 remind('pitPlanSame','Stratégie des stands : même composé prévu (SS)',300)
 check(#r.voice.queue==0,'plan same before the entry (race): quiet')
 lane(310); q=queued(r.voice,'pitCompound')
 check(q and q.text:find('même composé prévu',1,true),'plan same at the entry: '..tostring(q and q.text))
 r.voice.queue={}; out(320)
 -- Arrêt validé (plus dû) : rien.
 r.e.incidents.playerPitDue=0; lane(400); check(not queued(r.voice,'pitCompound'),'stop no longer due: nothing')
 out(410); r.e.incidents.playerPitDue=1
 -- Drive-through : rien.
 r.e.panel.decided='penaltyDrive'; lane(500); check(not queued(r.voice,'pitCompound'),'drive-through: nothing')
end
-- Stratégie au même composé au départ, corrigée par le pilote avant la moitié du premier tour ('pitPlanOk') : l'avis
-- n'est jamais dit ; à l'entrée de la voie, « change de composé » (texte du clip) ; corrigée alors que l'avis attend
-- dans la file : retiré.
function T.plan_fixed_before_half_lap()
 local r=rig()
 local me=r.ctx.F.cars[1]
 me.laps=0; me.spline=0.97
 r.e.pits.state='open'; r.e.incidents.playerPitDue=1
 r.step(1)
 local n=0
 local function emit(kind,title,text,at)
  n=n+1; local inc=r.e.incidents
  inc.messageId=n; inc.messageKind=kind; inc.messageValue=0; inc.messageExtra=0
  r.e.ownTitle=title; r.e.ownText=text; r.step(at)
 end
 emit('pitPlanSame','Stratégie des stands','Même composé prévu (SS)',2)
 me.spline=0.3; emit('pitPlanOk','Stratégie des stands','Composé prévu : S',3)
 me.spline=0.6; r.step(4); r.step(5)
 check(not queued(r.voice,'pitPlanSame'),'strategy fixed: start notice never said')
 me.laps=3; me.pitlane=true; r.step(100)
 local q=queued(r.voice,'pitCompound')
 check(q and q.text:find('change de composé',1,true) and not q.text:find('même composé',1,true),'pit lane call: change compound: '..tostring(q and q.text))
 -- Avis déjà en file quand la stratégie est corrigée : retiré.
 local r2=rig(); local me2=r2.ctx.F.cars[1]; me2.laps=0; me2.spline=0.97
 r2.e.pits.state='pending'; r2.step(1)
 local inc=r2.e.incidents
 inc.messageId=1; inc.messageKind='pitPlanSame'; r2.e.ownTitle='Stratégie des stands'; r2.e.ownText='Même composé prévu (SS)'; r2.step(2)
 me2.spline=0.55; r2.step(3); check(queued(r2.voice,'pitPlanSame'),'start notice queued after half a lap')
 inc.messageId=2; inc.messageKind='pitPlanOk'; r2.e.ownText='Composé prévu : S'; r2.step(3.1)
 check(not queued(r2.voice,'pitPlanSame'),'queued start notice withdrawn once the strategy is fixed')
end
-- Textes réels d'AdvancedIA 1.50, qui reprennent le titre au début (« Stratégie des stands · composé prévu S ») : le
-- titre n'est jamais écrit deux fois sur la radio.
function T.aai_title_not_doubled()
 local r=rig()
 local me=r.ctx.F.cars[1]
 me.laps=0; me.spline=0.97
 r.step(1)
 local inc=r.e.incidents
 inc.messageId=1; inc.messageKind='pitPlanSame'; r.e.ownTitle='Stratégie des stands'; r.e.ownText='Stratégie des stands : même composé prévu (SS)'; r.step(2)
 me.spline=0.55; r.step(3)
 local q=queued(r.voice,'pitPlanSame')
 check(q and q.text=='Stratégie des stands : même composé prévu (SS)','plan same line: '..tostring(q and q.text))
 inc.messageId=2; inc.messageKind='pitPlanOk'; r.e.ownText='Stratégie des stands · composé prévu S'; r.step(4)
 local found=false
 for _,l in ipairs(r.voice.log) do if l.text=='Stratégie des stands · composé prévu S' then found=true end; check(not (l.text or ''):find('Stratégie des stands · Stratégie',1,true),'title doubled: '..tostring(l.text)) end
 check(found,'plan fixed written once, title not doubled')
end
-- AdvancedIA 1.50 : annonces de la voiture de sécurité et de la reprise. 'scOut' part dans l'image où safetyPhase passe
-- à 'out' : une seule voix (celle de la phase, « Voiture de sécurité déployée »), le détail d'AdvancedIA écrit une fois
-- sur la radio ; 'scLeading' : écrite seulement ; 'restartPlace' et 'restartRetake' : dites (une ligne sur la radio), la
-- place à reprendre au plus toutes les 15 s (les autres cibles écrites).
function T.sc_and_restart_notices_written_not_doubled()
 local r=rig()
 local inc=r.e.incidents
 inc.neutral=true; inc.neutralMode='sc'; inc.neutralSince=1; inc.safetyPhase='call'
 r.step(1)
 r.voice.queue={}
 local function lines(pattern) local c=0; for _,l in ipairs(r.voice.log) do if l.text and l.text:find(pattern,1,true) then c=c+1 end end return c end
 inc.safetyPhase='out'; inc.messageId=1; inc.messageKind='scOut'; inc.messageValue=0; inc.messageExtra=40
 r.e.ownTitle='Voiture de sécurité'; r.e.ownText='En piste devant P0 : en file derrière elle'
 r.step(2)
 local voiced=0; for _,q in ipairs(r.voice.queue) do if q.key=='scOut' then voiced=voiced+1 end end
 check(voiced==1 and #r.voice.queue==1,'one voice for the safety car on track: '..voiced..' / '..#r.voice.queue)
 check(lines('En piste devant P0')==1,'AdvancedIA detail written once')
 local n=1
 local function emit(kind,title,text,value,extra,at)
  n=n+1; inc.messageId=n; inc.messageKind=kind; inc.messageValue=value; inc.messageExtra=extra
  r.e.ownTitle=title; r.e.ownText=text; r.voice.queue={}; r.step(at)
 end
 emit('scLeading','Voiture de sécurité','File formée derrière elle, P2 en tête',2,30,3)
 check(#r.voice.queue==0 and lines('File formée derrière elle')==1,'queue formed: written only')
 -- Place de reprise : nombre dit, voiture à suivre écrite (texte d'AdvancedIA, même langue).
 emit('restartPlace','Reprise','P7 · derrière P2',7,2,4)
 local q=queued(r.voice,'restartPlace')
 check(q and q.prio==3 and q.text=='Reprise · P7 · derrière P2','restart position said: '..tostring(q and q.text))
 Voice.step(r.voice,4.05); check(lines('P7 · derrière P2')==1,'one radio line')
 -- P1 derrière la voiture de sécurité, AdvancedIA dans une autre langue : texte du clip.
 r.e.g.language='en'
 emit('restartPlace','Restart','P1 · behind the safety car',1,-1,5)
 q=queued(r.voice,'restartPlace')
 check(q and q.text:find('Place de reprise : 1',1,true) and q.text:find('derrière la voiture de sécurité',1,true),'P1 behind the safety car: '..tostring(q and q.text))
 r.e.g.language='fr'
 -- Place à reprendre : dite, nom écrit ; une deuxième cible dans les 15 s : écrite seulement ; plus tard : dite.
 emit('restartRetake','Reprise','Reprenez votre place : doublez P0',0,7,10)
 q=queued(r.voice,'restartRetake'); check(q and q.prio==2 and q.text:find('doublez P0',1,true),'retake said')
 emit('restartRetake','Reprise','Reprenez votre place : doublez P2',2,7,15)
 check(not queued(r.voice,'restartRetake') and lines('doublez P2')==1,'second target within 15 s: written only')
 emit('restartRetake','Reprise','Reprenez votre place : doublez P1',1,7,40)
 check(queued(r.voice,'restartRetake'),'later target: said')
end
-- Arrêt non compté (même composé) : l'arrêt obligatoire reste dû, le plan recalculé place un nouvel arrêt ; le « box »
-- de ce nouveau tour est annoncé, même après le box déjà dit pour l'arrêt refusé.
function T.box_called_again_after_a_stop_not_counted()
 local Strategist=require('src/strategist')
 local r=rig()
 local F={isRace=true,player=0,cars={[0]={laps=9,spline=0.3,pitlane=false}}}
 local ctx={F=F,cfg={boxCalls=true,neutralBox=true,tolerance=2},link={d={pitsClosed=false,neutral=false}},say=r.ctx.say,real=0}
 local t={ready=true,plan={ok=true,optimal=10,costs={}},boxSaid={}}
 Strategist.boxCalls(t,ctx)
 check(queued(r.voice,'box') and queued(r.voice,'box').text:find('ce tour',1,true),'box for the first stop')
 r.voice.queue={}
 -- Arrêt au tour 10, refusé ; nouveau plan : tour 14.
 F.cars[0].laps=10; F.cars[0].spline=0.2; t.plan={ok=true,optimal=14,costs={}}; ctx.real=200
 Strategist.boxCalls(t,ctx)
 check(not queued(r.voice,'box'),'no box on the out lap')
 F.cars[0].laps=12; F.cars[0].spline=0.8; ctx.real=400; Strategist.boxCalls(t,ctx)
 check(queued(r.voice,'box') and queued(r.voice,'box').text:find('prochain',1,true),'box next lap for the new stop')
 r.voice.queue={}
 F.cars[0].laps=13; F.cars[0].spline=0.3; ctx.real=500; Strategist.boxCalls(t,ctx)
 check(queued(r.voice,'box') and queued(r.voice,'box').text:find('ce tour',1,true),'box this lap for the new stop')
end
-- « Box » engagé : le plan recule d'un tour après « box ce tour » (course du 05/11/2026) : pas de « box au prochain tour »,
-- pas de fenêtre réannoncée avant l'arrêt ; après l'arrêt, le plan reprend la main.
function T.box_call_committed()
 local Strategist=require('src/strategist')
 local r=rig()
 local F={isRace=true,player=0,cars={[0]={laps=4,spline=0.3,pitlane=false}}}
 local ctx={F=F,cfg={boxCalls=true,neutralBox=true,tolerance=2,neutralFactor=0.5},link={d={pitsClosed=false,neutral=false}},say=r.ctx.say,real=0}
 local t={ready=true,plan={ok=true,optimal=5,window={4,8},costs={}},boxSaid={},data={clean={{},{}}}}
 t.announcedWindow={4,8,6}
 Strategist.boxCalls(t,ctx)
 check(queued(r.voice,'box') and queued(r.voice,'box').text:find('ce tour',1,true),'box this lap on lap 5')
 r.voice.queue={}
 -- Le plan recule d'un tour (optimal 6) pendant ce même tour.
 t.plan={ok=true,optimal=6,window={5,9},costs={}}; F.cars[0].spline=0.65; ctx.real=30
 Strategist.boxCalls(t,ctx)
 check(not queued(r.voice,'box'),'no « box next lap » after « box this lap »')
 t.plan.window={4,5}; t.plan.optimal=4; Strategist.announce(t,{F=F,cfg={duels=false,boxCalls=true},say=r.ctx.say,real=31},false)
 check(not queued(r.voice,'window'),'no window re-announced between the box call and the stop')
 -- Arrêt : la voie des stands libère l'engagement ; le plan suivant reprend.
 F.cars[0].pitlane=true; Strategist.boxCalls(t,ctx); t.boxLap=false
 F.cars[0].pitlane=false; F.cars[0].laps=5; F.cars[0].spline=0.2
 t.plan={ok=true,optimal=12,window={10,14},costs={}}; t.announcedWindow={4,8,6}
 Strategist.announce(t,{F=F,cfg={duels=false,boxCalls=true},say=r.ctx.say,real=200},false)
 check(queued(r.voice,'window'),'after the stop, the next window is announced')
end
-- « Box » de l'ingénieur : tour L-1 puis tour L ; jamais voie des stands fermée.
function T.box_calls_timeline()
 local Strategist=require('src/strategist')
 local r=rig()
 local F={isRace=true,player=0,cars={[0]={laps=8,spline=0.7,pitlane=false}}}
 local ctx={F=F,cfg={boxCalls=true,neutralBox=true,tolerance=2},link={d={pitsClosed=false,neutral=false}},say=r.ctx.say,real=0}
 local t={ready=true,plan={ok=true,optimal=10,costs={}},boxSaid={}}
 Strategist.boxCalls(t,ctx)
 check(queued(r.voice,'box') and queued(r.voice,'box').text:find('prochain',1,true),'box next lap on lap L-1')
 r.voice.queue={}
 F.cars[0].laps=9; F.cars[0].spline=0.3; ctx.real=100
 ctx.link.d.pitsClosed=true; Strategist.boxCalls(t,ctx)
 check(not queued(r.voice,'box'),'no box call while the pit lane is closed')
 ctx.link.d.pitsClosed=false; Strategist.boxCalls(t,ctx)
 check(queued(r.voice,'box') and queued(r.voice,'box').text:find('ce tour',1,true),'box this lap on lap L')
end
-- « Dégagé » seulement si l'annonce du côté a été entendue.
function T.clear_only_after_side_heard()
 for _,heard in ipairs({false,true}) do
  local r=rig()
  r.ctx.cfg.sideBySide=true
  local F=r.ctx.F
  r.step(1)
  F.cars[2].x=F.cars[1].x+2.2; F.cars[2].z=0
  for t=1.05,1.35,0.05 do r.step(t) end
  check(queued(r.voice,'side:left'),'car left queued')
  if heard then Voice.step(r.voice,1.36) end
  F.cars[2].x=F.cars[1].x+60
  for t=1.4,2.2,0.05 do r.step(t) end
  local clear=queued(r.voice,'side:clear')
  if heard then check(clear and clear.prio==2,'clear after a heard side call, priority 2')
  else check(not clear and not queued(r.voice,'side:left'),'no clear when the side call was never heard') end
 end
end
-- Réactivité mesurée, image par image (60 Hz), clips de durée réelle : de la décision d'AdvancedIA au début du son.
local function liveRig()
 local r=rig()
 local Catalog=require('src/catalog')
 local files={}
 for _,c in pairs(Catalog.clips) do files['FR/'..c.FR]=true end
 for n=0,99 do files['FR/'..Catalog.numberFile(n)]=true; files['FR/'..Catalog.secondsFile(n)]=true end
 r.ctx.say.files=files
 local clock={t=0}
 -- Durées mesurées sur les clips (s) ; 1 s pour les autres.
 local durations={['16_delta_negatif']=4.2,['01_vert']=2.6,['46_ecart_devant']=0.64,['sec/']=1.27,['36_voiture_gauche']=1.06,['82_delta_cible']=2.0}
 local function length(p) for k,d in pairs(durations) do if p:find(k,1,true) then return d end end return 1 end
 r.played={}
 r.voice.port={play=function(p) r.played[#r.played+1]=p; return {p=p,at=clock.t,d=length(p)} end,playing=function(h) return clock.t<h.at+h.d end,stop=function() end}
 function r.run(from,to)
  local t=from
  while t<=to+1e-9 do clock.t=t; r.e.time=100+t; r.step(t); Voice.step(r.voice,t); t=t+1/60 end
 end
 return r
end
function T.green_is_immediate()
 -- FCY, le pilote au ras du delta : « delta négatif » (3,6 s) en cours quand le vert tombe.
 local r=liveRig()
 r.run(1,1.1)
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='fcy'; r.e.delta.value=0.4; r.e.delta.kind='fcy'
 r.run(1.2,2)
 r.e.delta.value=-0.3; r.run(2.02,3)
 check(r.voice.current and r.voice.current.key=='delta','delta negative being spoken')
 r.e.incidents.neutral=false; r.e.incidents.neutralMode='local'; r.e.delta.value=nil; r.e.delta.kind=''
 r.e.incidents.greenUntil=100+3.02+5
 r.run(3.02,3.1)
 local at=r.voice.started.restart
 check(at and at-3.02<=1/60+1e-6,'green spoken at once after the FCY: '..tostring(at and string.format('%.3f s',at-3.02)))
 check(r.voice.current and r.voice.current.key=='restart','the obsolete delta call was cut')
 -- Une information de l'ingénieur en cours ne retient pas un drapeau.
 local r2=liveRig()
 r2.run(1,1.1)
 Say.say(r2.ctx.say,'engineer','target',5,{'targetDelta','plus',{n=0.6,dec=1,unit='s'}},1.12,{ttl=15})
 r2.run(1.12,1.5)
 check(r2.voice.current and r2.voice.current.key=='target','engineer information playing')
 r2.e.incidents.neutral=true; r2.e.incidents.neutralMode='sc'; r2.run(1.52,1.6)
 local sc=r2.voice.started.neutral
 check(sc and sc-1.52<=1/60+1e-6,'SC call cuts the engineer at once')
 -- Côte à côte pendant un écart : coupé aussitôt, l'écart est redit ensuite.
 local r3=liveRig()
 r3.ctx.cfg.sideBySide=true
 r3.run(1,1.1)
 Say.say(r3.ctx.say,'spotter','gaps',3,{'gapAhead',{n=1.2,dec=1,unit='s'}},1.12,{ttl=6})
 r3.run(1.12,1.3)
 local F=r3.ctx.F; F.cars[2].x=F.cars[1].x+2.2; F.cars[2].z=0
 r3.run(1.32,1.7)
 local side=r3.voice.started['side:left']
 check(side and side-1.32<=0.25+2/60,'car left called 0.25 s after the overlap: '..tostring(side and string.format('%.2f s',side-1.32)))
 F.cars[2].x=F.cars[1].x+60
 r3.run(1.72,6)
 local plays,lines=0,0
 for _,p in ipairs(r3.played) do if p:find('46_ecart_devant',1,true) then plays=plays+1 end end
 for _,e in ipairs(r3.voice.log) do if e.key=='gaps' then lines=lines+1 end end
 check(plays==2 and lines==1,'interrupted gap said again after the side call, logged once: '..plays..' plays, '..lines..' lines')
end
-- Départ : « Go » dit à l'instant où les feux s'éteignent, même pendant « les feux s'allument » ; celui-ci n'est pas
-- redit. Un « dégagé » coupé par une nouvelle voiture à côté n'est pas redit non plus.
function T.start_and_side_calls_are_never_stale()
 local r=liveRig()
 r.run(1,1.1)
 r.e.incidents.standing='lights'; r.run(1.12,1.5)
 check(r.voice.current and r.voice.current.key=='start' and r.voice.current.text:find('feux',1,true),'lights being said')
 r.e.incidents.standing='go'; r.run(1.52,1.6)
 check(r.voice.started.start and r.voice.started.start-1.52<=1/60+1e-6 and r.voice.current.text:find('Go',1,true),'go at once')
 r.run(1.62,6)
 local lights=0; for _,e in ipairs(r.voice.log) do if e.key=='start' and e.text:find('feux',1,true) then lights=lights+1 end end
 check(lights==1,'lights call not repeated after go: '..lights)
 -- Dégagé coupé par une voiture qui arrive de l'autre côté.
 local v=r.voice
 Say.say(r.ctx.say,'spotter','side:clear',2,{'clear'},6.02,{ttl=1.5,once=true}); r.run(6.02,6.1)
 Say.say(r.ctx.say,'spotter','side:right',1,{'carRight'},6.12,{ttl=1.5,once=true}); r.run(6.12,9)
 local clear=0; for _,e in ipairs(v.log) do if e.key=='side:clear' then clear=clear+1 end end
 check(clear==1,'clear not repeated after a new side call: '..clear)
end
-- Zone jaune locale : « vert, fin du jaune » dit dans l'image où AdvancedIA montre le vert, une seule fois (pas
-- d'écho quand son panneau passe au drapeau natif « start ») ; un jaune natif qui traîne n'est pas redit.
function T.zone_green_is_immediate_and_single()
 local r=liveRig()
 r.run(1,1.1)
 r.e.incidents.playerZone=true; r.run(1.12,4)
 check(r.voice.started.zone,'yellow called')
 r.e.incidents.playerZone=false; r.e.incidents.greenUntil=100+4.02+3; r.e.panel.decided='green'
 r.run(4.02,4.1)
 local at=r.voice.started.zoneGreen
 check(at and at-4.02<=1/60+1e-6,'zone green at once: '..tostring(at and string.format('%.3f s',at-4.02)))
 r.e.panel.decided='start'; r.run(7.1,8)
 r.e.panel.decided='native'; r.run(8.02,9)
 r.e.panel.decided='none'; r.run(9.02,12)
 local greens,yellows=0,0
 for _,e in ipairs(r.voice.log) do
  if e.key=='zoneGreen' or e.key=='restart' or e.key=='green' then greens=greens+1 end
  if e.key=='zone' then yellows=yellows+1 end
 end
 check(greens==1 and yellows==1,'one yellow and one green per zone: '..yellows..' / '..greens)
end
-- Deux zones rapprochées : deux jaunes, deux verts.
function T.two_close_zones_two_greens()
 local r=liveRig()
 r.run(1,1.1)
 local t=1.12
 for k=1,2 do
  r.e.incidents.playerZone=true; r.run(t,t+3.5)
  r.e.incidents.playerZone=false; r.e.incidents.greenUntil=100+t+3.52+3; r.run(t+3.52,t+5)
  t=t+5.02
 end
 local greens,yellows=0,0
 for _,e in ipairs(r.voice.log) do if e.key=='zoneGreen' then greens=greens+1 elseif e.key=='zone' then yellows=yellows+1 end end
 check(yellows==2 and greens==2,'two zones 5 s apart: '..yellows..' yellows, '..greens..' greens')
end
-- Pénalité d'AdvancedIA puis son écho natif (coupure des gaz appliquée par AC) : une seule annonce ; de même pour la
-- disqualification et le drapeau noir natif, et pour le drapeau bleu puis le bleu natif.
function T.native_echoes_are_not_repeated()
 local r=liveRig()
 r.run(1,1.1)
 r.e.penalties.requestId=1; r.e.penalties.reason='pass'; r.e.penalties.kind='slow'; r.run(1.12,1.15)
 r.frame.cars[2].penaltyType=3; r.frame.cars[2].penaltyParam=5; r.run(1.17,8)
 local pen=0; for _,e in ipairs(r.voice.log) do if e.key=='penalty' then pen=pen+1 end end
 check(pen==1,'one penalty call for an ACAI penalty and its native echo: '..pen)
 r.e.penalties.disqualified=true; r.run(8.02,8.05)
 r.frame.cars[2].penaltyType=4; r.run(8.07,14)
 local black=0; for _,e in ipairs(r.voice.log) do if e.key=='black' then black=black+1 end end
 check(black==1,'one black flag call: '..black)
 r.e.panel.decided='blue'; r.run(14.02,14.3); r.e.panel.decided='nativeBlue'; r.run(14.32,18)
 local blue=0; for _,e in ipairs(r.voice.log) do if e.key=='blue' then blue=blue+1 end end
 check(blue==1,'one blue flag call: '..blue)
end
-- Verts : jamais pendant une FCY (sortie de zone sous neutralisation), jamais au « Go » d'un départ arrêté ; deux zones à
-- 2 s d'écart : deux verts courts.
function T.greens_are_never_out_of_place()
 local r=liveRig(); r.run(1,1.1)
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='fcy'; r.run(1.12,6)
 r.e.incidents.playerZone=true; r.run(6.02,9)
 r.e.incidents.playerZone=false; r.e.incidents.greenUntil=100+9.02+3; r.run(9.02,12)
 local g=0; for _,e in ipairs(r.voice.log) do if e.key=='zoneGreen' or e.key=='restart' then g=g+1 end end
 check(g==0,'no green while the FCY goes on: '..g)
 local r2=liveRig(); r2.run(1,1.1)
 r2.e.incidents.standing='grid'; r2.run(1.12,3); r2.e.incidents.standing='lights'; r2.run(3.02,6)
 r2.e.incidents.standing='go'; r2.e.incidents.greenUntil=100+6.02+5; r2.run(6.02,10)
 local g2=0; for _,e in ipairs(r2.voice.log) do if e.key=='restart' or e.key=='zoneGreen' then g2=g2+1 end end
 check(g2==0,'only « Go » at a standing start, no green: '..g2)
 local r3=liveRig(); r3.run(1,1.1)
 local t=1.12
 for k=1,2 do
  r3.e.incidents.playerZone=true; r3.run(t,t+3.2)
  r3.e.incidents.playerZone=false; r3.e.incidents.greenUntil=100+t+3.22+3; r3.run(t+3.22,t+5.2)
  t=t+5.22
 end
 local g3=0; for _,e in ipairs(r3.voice.log) do if e.key=='zoneGreen' then g3=g3+1 end end
 check(g3==2,'two zones 2 s apart: two greens: '..g3)
end
-- SC : appelée (dite « appelée »), puis en piste (« reste en file ») ; fin de VSC annulée : la VSC est redite.
function T.safety_car_phases_and_cancelled_endings()
 local r=liveRig(); r.run(1,1.1)
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='sc'; r.e.incidents.safetyPhase='call'; r.run(1.12,6)
 r.e.incidents.safetyPhase='out'; r.run(6.02,12)
 local called,out=false,false
 for _,e in ipairs(r.voice.log) do if e.text:find('appelée',1,true) then called=true end; if e.key=='scOut' then out=true end end
 check(called and out,'SC called then out on track')
 local r2=liveRig(); r2.run(1,1.1)
 r2.e.incidents.neutral=true; r2.e.incidents.neutralMode='vsc'; r2.run(1.12,6)
 r2.e.incidents.ending=true; r2.run(6.02,7)
 r2.e.incidents.ending=false; r2.run(7.02,12)
 local again=0; for _,e in ipairs(r2.voice.log) do if e.key=='neutral' then again=again+1 end end
 check(again==2,'VSC said again when its end is cancelled: '..again)
end
-- Un double jaune qui remplace un simple : le simple n'est pas redit après.
function T.superseded_call_is_not_replayed()
 local r=liveRig(); r.run(1,1.1)
 r.e.incidents.playerZone=true; r.run(1.12,1.6)
 check(r.voice.current and r.voice.current.key=='zone','single yellow playing')
 r.e.incidents.playerInside=true; r.e.incidents.playerZoneDouble=true; r.run(1.62,12)
 local n=0; for _,p in ipairs(r.played) do if p:find('02_jaune_simple',1,true) then n=n+1 end end
 check(n==1,'single yellow not replayed after the double: '..n)
end
-- Côte à côte : dégagé d'un côté sans effacer l'arrivée de l'autre ; voiture dans la voie des stands ignorée ; voiture
-- lente à côté dans une épingle (sous 40 km/h) : pas de « dégagé » tant qu'elle y est.
function T.side_calls_edge_cases()
 local r=liveRig(); r.ctx.cfg.sideBySide=true; r.run(1,1.1)
 local F=r.ctx.F; local me=F.cars[1]
 F.cars[2].x=me.x+2.2; F.cars[2].z=0; r.run(1.12,2)
 F.cars[2].x=me.x+60; F.cars[0].x=me.x-2.2; F.cars[0].z=0
 r.run(2.02,4)
 local right=false; for _,e in ipairs(r.voice.log) do if e.key=='side:right' then right=true end end
 check(right,'car right still called while the left clears')
 local r2=liveRig(); r2.ctx.cfg.sideBySide=true; r2.run(1,1.1)
 local F2=r2.ctx.F; F2.cars[2].x=F2.cars[1].x-3.5; F2.cars[2].z=0; F2.cars[2].pitlane=true; r2.run(1.12,3)
 check(not r2.voice.started['side:right'],'car in the pit lane not called')
 local r3=liveRig(); r3.ctx.cfg.sideBySide=true; r3.run(1,1.1)
 local F3=r3.ctx.F; F3.cars[2].x=F3.cars[1].x+2.2; F3.cars[2].z=0; r3.run(1.12,2)
 F3.cars[1].kmh=30; F3.cars[2].kmh=30; r3.run(2.02,6)
 check(not r3.voice.started['side:clear'] and not r3.voice.started['side:stillLeft'],'slow hairpin: no clear, no still there while alongside')
end
-- « Delta négatif » périmé derrière une annonce urgente : redit dès que possible ; dernier tour dit une seule fois ;
-- dernier avertissement avec son vrai sens.
function T.delta_retry_last_lap_once_last_warning()
 local r=liveRig(); r.run(1,1.1)
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='vsc'; r.e.delta.value=0.3; r.e.delta.kind='vsc'; r.run(1.12,1.2)
 r.e.delta.value=-0.4; r.run(1.22,12)
 local heard=r.voice.started.delta
 check(heard and heard>1.22,'negative delta finally spoken after the VSC call: '..tostring(heard))
 local r2=liveRig(); r2.run(1,1.1)
 for _,k in ipairs({'white','blue','white','none','white'}) do r2.e.panel.decided=k; r2.run(r2.voice.clock+0.02,r2.voice.clock+6) end
 local laps=0; for _,e in ipairs(r2.voice.log) do if e.key=='panel:white' then laps=laps+1 end end
 check(laps==1,'last lap said once: '..laps)
 r2.e.panel.warnUntil=200; r2.run(r2.voice.clock+0.02,r2.voice.clock+1)
 local w=nil; for _,e in ipairs(r2.voice.log) do if e.key=='blackWhite' then w=e end end
 check(w and w.text:find('disqualifie',1,true),'last warning before disqualification: '..tostring(w and w.text))
end
-- Nouvelle instance d'AdvancedIA (compteur revenu en arrière) : aucune annonce tirée de la comparaison avec l'ancienne.
function T.new_acai_instance_is_a_new_reference()
 local r=rig(); r.step(1)
 r.e.penalties.requestId=3; r.e.penalties.kind='slow'; r.e.weather.wet=true; r.step(2); r.step(3)
 r.voice.queue={}
 -- Nouvelle instance : ses compteurs (pénalité, piste mouillée) repartent de zéro.
 r.box.b=Bridge.new('Beta 1.46'); r.e.penalties.requestId=0; r.step(4); r.step(5)
 check(not queued(r.voice,'penalty') and not queued(r.voice,'trackState'),'no stale call from the old instance')
end
-- Grille d'un départ arrêté : voitures immobiles dans leur case, pas « voiture arrêtée devant ».
function T.no_stopped_car_on_the_grid()
 local r=rig(); r.ctx.cfg.hazards=true; r.step(1)
 r.e.incidents.standing='grid'
 local F=r.ctx.F; F.cars[2].kmh=0; F.cars[2].spline=F.cars[1].spline+0.03
 r.ctx.timing=Timing.new(); r.step(2); r.step(3)
 check(not queued(r.voice,'stopped'),'no stopped car call on the grid')
end
function T.delta_does_not_chatter()
 -- Au ras du delta (-0,08 à +0,15 s) pendant 30 s de VSC : au plus un « delta négatif », jamais d'alternance.
 local r=liveRig()
 r.run(1,1.1)
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='vsc'; r.e.delta.value=0.3; r.e.delta.kind='vsc'
 r.run(1.2,2)
 local t=2
 while t<32 do r.e.delta.value=math.sin(t*1.7)*0.115+0.035; r.run(t,t+0.2); t=t+0.25 end
 local n=0; for _,e in ipairs(r.voice.log) do if e.key=='delta' then n=n+1 end end
 check(n<=1,'at most one delta call while hovering around the delta: '..n)
 -- Dès -0,05 s : dit tout de suite (avant l'infraction d'AdvancedIA, jugée sous -0,5 s par défaut).
 local r2=liveRig(); r2.run(1,1.1)
 -- (après l'annonce de la VSC, de même priorité, qui demande déjà de respecter le delta).
 r2.e.incidents.neutral=true; r2.e.incidents.neutralMode='vsc'; r2.e.delta.value=0.3; r2.e.delta.kind='vsc'; r2.run(1.2,8)
 r2.e.delta.value=-0.06; r2.run(8.02,8.1)
 check(r2.voice.started.delta and r2.voice.started.delta-8.02<=1/60+1e-6,'negative delta called at once')
 -- Réarmé après un retour au-dessus de zéro (+0,1 s pendant 10 s) : le nouveau passage sous zéro est redit à l'instant.
 local first=r2.voice.started.delta
 r2.e.delta.value=0.1; r2.run(8.12,18)
 r2.e.delta.value=-0.06; r2.run(18.02,18.1)
 check(r2.voice.started.delta>first and r2.voice.started.delta-18.02<=1/60+1e-6,'second negative dip called at once')
end
function T.acai_events_have_their_clips()
 local r=rig()
 r.step(1)
 -- Pénalité précise selon la raison décidée par AdvancedIA.
 r.e.penalties.requestId=1; r.e.penalties.reason='pass'; r.e.penalties.kind='slow'; r.step(2)
 local q=queued(r.voice,'penalty'); check(q and q.text:find('dépassement sous drapeau',1,true),'penalty for passing: '..tostring(q and q.text))
 r.voice.queue={}
 -- Panneau du pilote : dernier tour, puis départ.
 r.e.panel.decided='white'; r.step(3); check(queued(r.voice,'panel:white'),'last lap')
 r.e.incidents.standing='go'; r.step(4); local g=queued(r.voice,'start'); check(g and g.prio==1,'go')
 r.voice.queue={}
 -- Relance après drapeau rouge derrière la voiture de sécurité : une seule annonce (pas de « SC déployée » en plus).
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='sc'; r.e.incidents.relaunch=true; r.step(5)
 local q2=queued(r.voice,'restart'); check(q2 and q2.text:find('derrière la voiture de sécurité',1,true),'restart behind SC: '..tostring(q2 and q2.text))
 check(not queued(r.voice,'neutral'),'no duplicate SC call with the restart')
 r.voice.queue={}
 -- Place rendue dans le délai.
 r.e.penalties.giveBack=3; r.step(6); r.e.penalties.giveBack=0; r.step(7)
 local q3=queued(r.voice,'giveBack'); check(q3 and q3.text:find('Place rendue',1,true),'give back done')
 -- Piste mouillée.
 r.e.weather.wet=true; r.step(8); local q4=queued(r.voice,'trackState'); check(q4 and q4.text:find('humide',1,true),'track wet')
end
function T.no_double_calls()
 local r=rig()
 r.step(1)
 -- Safety car appelée : une seule annonce, pas « SC déployée » en même temps.
 r.e.incidents.neutral=true; r.e.incidents.neutralMode='sc'; r.e.incidents.safetyPhase='call'; r.step(2)
 local n=0; for _,q in ipairs(r.voice.queue) do if q.key=='neutral' then n=n+1 end end
 local q=queued(r.voice,'neutral'); check(n==1 and q.text:find('appelée',1,true),'one SC call: '..tostring(q and q.text))
 r.voice.queue={}
 -- Jaune natif d'AC relayé par le panneau : même clé que la zone jaune.
 r.e.panel.decided='native'; r.step(3); check(queued(r.voice,'zone'),'native yellow spoken')
end
-- Section Drapeaux coupée (vue effective, comme dans l'app) : drapeau bleu muet ; rallumée : annoncé.
function T.section_switch_mutes_blue_flag()
 local r=rig()
 local cfg=Config.defaults(); cfg.gaps=false; cfg.sideBySide=false; cfg.raceControl=false
 r.ctx.cfg=Config.effective(cfg)
 r.step(1)
 r.e.panel.decided='blue'; r.step(2)
 check(not queued(r.voice,'blue'),'blue flag silent with the section off')
 cfg.raceControl=true; Config.effective(cfg,r.ctx.cfg)
 r.e.panel.decided='none'; r.step(3); r.e.panel.decided='blue'; r.step(4)
 check(queued(r.voice,'blue'),'blue flag spoken with the section on')
end
function T.drs_is_silent_by_default()
 local r=rig()
 r.step(1)
 r.e.drs.beepId=4; r.e.incidents.drsReason='wet'; r.step(2)
 check(not queued(r.voice,'drs') and not queued(r.voice,'drsOff'),'no DRS voice by default')
 r.ctx.cfg.drsVoice=true; r.e.drs.beepId=5; r.step(3)
 check(queued(r.voice,'drs'),'DRS voice when enabled')
end
function T.spotter_is_silent_when_link_is_down()
 local r=rig()
 r.step(1)
 r.e.g.enabled=false; r.e.incidents.red=true
 r.step(2)
 check(not queued(r.voice,'red'),'no announcement from a suspended AAI')
end
function T.rival_penalty_for_direct_rival()
 local r=rig()
 r.step(1)
 r.e.sanctions.cars[1].time=5 -- emplacement 1 = indice 0, P1 devant le joueur (P2)
 r.step(2)
 local q=queued(r.voice,'rival:0'); check(q,'rival penalty'); check(q.text:find('%+5 s'),'detail '..q.text)
end
-- Dernier tour : « Dernier tour ! », la position et le conseil en une seule transmission du spotter ; l'annonce de
-- position de l'ingénieur qui attend encore est retirée. Réglage coupé : « Dernier tour ! » seul.
function T.last_lap_carries_position()
 local Catalog=require('src/catalog')
 local function setup(on)
  local r=rig()
  local files={}
  for _,c in pairs(Catalog.clips) do files['FR/'..c.FR]=true end
  for n=1,Catalog.maxPosition do files['FR/'..Catalog.positionFile(n)]=true end
  r.ctx.say.files=files; r.ctx.cfg.positionCalls=on
  r.step(1)
  return r
 end
 local r=setup(true)
 Say.say(r.ctx.say,'engineer','position',4,{{pos=2}},1.5,{ttl=15})
 r.e.panel.decided='white'; r.step(2)
 local q=queued(r.voice,'panel:white')
 check(q and q.text=='Dernier tour ! Tu es P2. Ramène-la à la maison, sans prendre de risque.','last lap with position: '..tostring(q and q.text))
 check(q.clips and #q.clips==3,'three clips: '..tostring(q.clips and #q.clips))
 check(not queued(r.voice,'position'),'pending engineer position dropped')
 -- Voiture juste derrière : défends.
 local gap=Timing.gap
 Timing.gap=function(_,a,b) if a==1 then return 0.5 end return 3 end
 local r2=setup(true)
 r2.e.panel.decided='white'; local ok,err=pcall(r2.step,2)
 Timing.gap=gap
 if not ok then error(err,0) end
 q=queued(r2.voice,'panel:white')
 check(q and q.text:find('ferme la porte',1,true),'defend on the last lap: '..tostring(q and q.text))
 local r3=setup(false)
 r3.e.panel.decided='white'; r3.step(2)
 q=queued(r3.voice,'panel:white'); check(q and q.text=='Dernier tour !','setting off: last lap only: '..tostring(q and q.text))
end
-- Roulage simulé (20 images par s) : vitesse qui varie dans les virages (8 par tour, de 25 à 75 m/s), la même pour
-- toutes les voitures au même endroit, multipliée par le rythme de chacune ; chronométrage tenu comme dans l'app.
-- place(i, progression en tours, rythme), run(s).
local function track(r)
 local F=r.ctx.F
 local pos,pace={},{}
 local now=r.ctx.now
 local function speed(x) return 50*(1+0.5*math.sin(2*math.pi*8*x)) end
 local sim={}
 function sim.place(i,progress,k) pos[i]=progress; pace[i]=k or 1 end
 function sim.pace(i,k) pace[i]=k end
 function sim.run(seconds)
  for _=1,math.floor(seconds*20+0.5) do
   now=now+0.05
   for i,p in pairs(pos) do
    local v=speed(p%1)*pace[i]
    pos[i]=p+v*0.05/F.trackLength
    local c=F.cars[i]; c.spline=pos[i]%1; c.laps=math.floor(pos[i]); c.kmh=v*3.6
    Timing.update(r.ctx.timing,i,c.spline,c.laps,now,true,false)
   end
   r.step(now)
  end
 end
 return sim
end
local function count(voice,key) local n=0; for _,q in ipairs(voice.queue) do if q.key==key then n=n+1 end end return n end
-- Trafic plus rapide derrière (essais) : une voiture au même rythme, moins de 2 s derrière, va tour à tour plus vite et moins
-- vite que le joueur (elle freine après lui) : jamais annoncée (elle l'était à chaque virage). Une voiture 25 % plus
-- rapide est annoncée une fois, à moins de 2 s.
function T.faster_behind_needs_real_closing()
 local r=rig(); r.ctx.F.isRace=false; r.ctx.cfg.hazards=false; r.ctx.cfg.backmarkers=false
 local sim=track(r)
 sim.place(1,3.5); sim.place(2,3.5-0.01875); sim.place(0,3.0)
 local quicker=false
 local function watch(seconds) for _=1,seconds do sim.run(1); local c2=r.ctx.F.cars[2]; if c2.kmh>r.ctx.F.cars[1].kmh+15 then quicker=true end end end
 watch(90)
 check(quicker,'the car behind was faster than the player at times (old call)')
 check(count(r.voice,'fasterBehind')==0,'same pace: never called, got '..count(r.voice,'fasterBehind'))
 local g,rate=Spotter.closing(r.s,2)
 check(g and g>1 and g<2 and rate and math.abs(rate)<0.03,'gap under 2 s, no closing: '..tostring(g)..' '..tostring(rate))
 sim.place(2,r.ctx.F.cars[1].laps+r.ctx.F.cars[1].spline-0.04,1.25)
 sim.run(25)
 check(count(r.voice,'fasterBehind')==1,'faster car: called once, got '..count(r.voice,'fasterBehind'))
end
-- Tête-à-queue (essais) : le joueur tombe au pas (sous 30 km/h), une voiture au rythme normal moins de 2 s derrière :
-- annoncée tout de suite, sur les vitesses du moment (l'écart en temps ne la verrait arriver qu'une fois à l'endroit
-- du ralentissement), bien avant d'être sur lui ; une seule fois.
function T.faster_behind_after_a_spin()
 local r=rig(); r.ctx.F.isRace=false; r.ctx.cfg.hazards=false; r.ctx.cfg.backmarkers=false
 local F=r.ctx.F
 local sim=track(r)
 sim.place(1,3.5); sim.place(2,3.5-0.01875); sim.place(0,3.0)
 sim.run(20)
 check(count(r.voice,'fasterBehind')==0,'same pace: nothing')
 sim.pace(1,0.1)
 local after,metres=nil,nil
 for k=1,40 do
  sim.run(0.1)
  if not after and count(r.voice,'fasterBehind')>0 then after=k*0.1; metres=((F.cars[1].spline-F.cars[2].spline)%1)*F.trackLength end
 end
 check(after and after<=1.5,'called soon after slowing down, after '..tostring(after)..' s')
 check(metres and metres>40,'called well before the car arrives: '..tostring(metres)..' m')
 sim.pace(1,0.4); sim.run(10)
 check(count(r.voice,'fasterBehind')==1,'said once, got '..count(r.voice,'fasterBehind'))
end
-- Course : voiture qui prend un tour, 4 % plus rapide seulement, moins de 2 s derrière : annoncée (règle de course
-- inchangée, pas de mesure de rapprochement exigée).
function T.faster_behind_lapping_car_in_race()
 local r=rig(); r.ctx.cfg.hazards=false; r.ctx.cfg.backmarkers=false
 local F=r.ctx.F
 F.cars[2].position=1; F.cars[0].position=3
 local sim=track(r)
 sim.place(1,3.5); sim.place(2,4.5-0.016,1.04); sim.place(0,3.0)
 sim.run(5)
 check(count(r.voice,'fasterBehind')==1,'lapping car called, got '..count(r.voice,'fasterBehind'))
end
-- Essais et qualifications (AdvancedIA 1.51, 'fastCar') : « voiture en tour lancé derrière, laisse-la passer », dit
-- seulement si la voiture arrive vraiment dans les 6 s, avec le nom et l'écart mesuré ; sinon rien (journal seulement).
-- Une seule ligne sur la radio (pas la note d'AdvancedIA en plus), pas de trafic plus rapide en plus pour cette voiture ;
-- rien en course ni réglage coupé.
function T.fast_car_in_practice()
 local Catalog=require('src/catalog')
 local r=rig()
 local files={}; for _,c in pairs(Catalog.clips) do files['FR/'..c.FR]=true end
 r.ctx.say.files=files; r.ctx.F.isRace=false; r.ctx.cfg.hazards=false
 local lines={}; r.ctx.journal=function(l) lines[#lines+1]=l end
 local function logged(text) for _,l in ipairs(lines) do if l:find(text,1,true) then return true end end return false end
 local sim=track(r)
 sim.place(1,3.5); sim.place(2,3.5-0.01875); sim.place(0,3.0)
 sim.run(10)
 local inc=r.e.incidents
 local function announce(n) inc.messageId=n; inc.messageKind='fastCar'; inc.messageValue=2; inc.messageExtra=1.4
  r.e.ownTitle='Tour lancé'; r.e.ownText='P2 arrive en tour lancé : laissez passer' end
 -- Même rythme, moins de 2 s derrière : rien de dit.
 announce(1); sim.run(8)
 check(count(r.voice,'fastCar')==0,'not closing: silent')
 check(logged('tour lancé non confirmé : P2'),'not closing: in the journal')
 -- Voiture 25 % plus rapide, 3,3 s derrière, déjà mesurée : dite avec l'écart mesuré.
 sim.place(2,r.ctx.F.cars[1].laps+r.ctx.F.cars[1].spline-0.04,1.25); sim.run(4)
 announce(2); sim.run(2)
 local q=queued(r.voice,'fastCar')
 check(q and q.clips and q.text:find('laisse-la passer',1,true) and q.text:find('P2',1,true) and q.text:find(' s)',1,true),'fast car said: '..tostring(q and q.text))
 local notes=0; for _,l in ipairs(r.voice.log) do if l.kind=='aai' then notes=notes+1 end end
 check(notes==0,'no extra AdvancedIA line: '..notes)
 check(r.s.faster[2],'own faster-car call quiet for that car')
 sim.run(10); check(count(r.voice,'fasterBehind')==0,'no faster traffic call on top')
 r.voice.queue={}
 r.ctx.cfg.fasterBehind=false; announce(3); sim.run(1)
 check(not queued(r.voice,'fastCar'),'setting off: silent')
 r.ctx.cfg.fasterBehind=true; r.ctx.F.isRace=true; announce(4); sim.run(1)
 check(not queued(r.voice,'fastCar'),'race: silent')
end
-- Fenêtre d'arrêt : un appel du plan de l'ingénieur, coupé avec le réglage « Fenêtre et box » (les rappels
-- d'AdvancedIA restent au spotter).
function T.window_call_follows_box_setting()
 local Strategist=require('src/strategist')
 local r=rig()
 local F={isRace=true,player=0,cars={[0]={laps=3,spline=0.2,pitlane=false}}}
 local t={ready=true,plan={ok=true,optimal=12,window={10,14},costs={}},boxSaid={}}
 Strategist.announce(t,{F=F,cfg={duels=false,boxCalls=false},say=r.ctx.say,real=10},false)
 check(not queued(r.voice,'window'),'window silent with the box calls off')
 Strategist.announce(t,{F=F,cfg={duels=false,boxCalls=true},say=r.ctx.say,real=20},false)
 check(queued(r.voice,'window'),'window said with the box calls on')
end
-- Dernier tour refusé par la radio (rôle Spotter coupé) : l'annonce de position de l'ingénieur en attente reste.
function T.last_lap_refused_keeps_engineer_position()
 local r=rig()
 r.ctx.voice.spotterOn=false
 r.step(1)
 Say.say(r.ctx.say,'engineer','position',4,{{pos=2}},1.5,{ttl=15})
 r.e.panel.decided='white'; r.step(2)
 check(queued(r.voice,'position'),'engineer position kept')
end
return T
