-- Revue du 10/11/2026, sur l'hôte CSP factice (tests/host.lua) et SpotterEnginer.lua réel, une voiture (le joueur) :
-- liaison suspendue, horloge de la radio figée en pause, essai de la voix sans AdvancedIA, redémarrage de la séance au
-- premier tour, réglages enregistrés au déchargement, overlay Stratégie sans fenêtre, édition en jeu gardée quand un
-- overlay est en erreur, repli de la mise à jour, mémoire gardée au rechargement à chaud. Variables : voir
-- tests/integration_spec.lua.
local H=HOST
local T={}
local check=require('tests/helpers').check
local Layout=require('src/bridge_layout')
local Voice=require('src/voice')
local Catalog=require('src/catalog')
local DT=1/30
local APP=H.appsDir..'/SpotterEnginer'
local function car()
 local c={isConnected=true,isActive=true,position=vec3(0,0,0),look=vec3(0,0,1),speedKmh=120,splinePosition=0.3,lapCount=0,racePosition=1,
  isInPitlane=false,isInPit=false,previousLapTimeMs=0,bestLapTimeMs=0,isAIControlled=false,isUserControlled=true,isRetired=false,
  isRaceFinished=false,aabbSize=vec3(1.9,1.2,4.6),fuel=30,maxFuel=100,fuelPerLap=2,fuelMaps=1,hasUserBrakeBias=true,compoundIndex=0,
  brake=0,drsPresent=false,kersPresent=false,p2pStatus=0,wheelsOutside=0,isLapValid=true,lapCutsCount=0,currentSector=0,
  damage={[0]=0,0,0,0,0},wheels={}}
 for k=0,3 do c.wheels[k]={tyreCoreTemperature=82,tyreInsideTemperature=85,tyreMiddleTemperature=83,tyreOutsideTemperature=80,
  tyreOptimumTemperature=80,tyreWear=1,tyreVirtualKM=3,tyreGrain=0,tyreBlister=0,tyreFlatSpot=0,isBlown=false,tyreDirty=0,discTemperature=450,brakeTemperature=0} end
 return c
end
-- Lancement du jeu (opts.reload : rechargement à chaud de l'app dans la même partie : horloge, mémoire partagée et
-- fichiers gardés). opts.aai : AdvancedIA installé avec son pont.
local hello,data
local function boot(opts)
 opts=opts or {}
 if not opts.reload then
  H.files={}; H.clock=0; H.storage={}; H.shared={}
  if opts.aai then
   local aai=H.appsDir..'/AdvancedIA'
   H.files[aai..'/manifest.ini']='[ABOUT]\nNAME=AdvancedIA\nVERSION=Beta 1.49\n'
   H.files[aai..'/AdvancedIA.lua']="local Bridge=require('src/bridge')"
   H.files[aai..'/src/bridge.lua']='x'; H.files[aai..'/src/bridge_layout.lua']='x'
  end
  for _,rel in ipairs(VOX) do H.files[APP..'/vox/'..rel]='mp3' end
  if opts.files then opts.files() end
  H.files[APP..'/manifest.ini']=APP_MANIFEST
 end
 H.played={}; H.logs={}; H.texts={}; H.windowIds={}; H.audio={}; H.desktop=0; H.keys={}; H.mouse=vec2(-100,-100)
 H.sim.carsCount=1; H.sim.isPaused=false; H.sim.isReplayActive=false; H.sim.isSessionStarted=true; H.sim.currentSessionTime=nil
 H.sim.isMouseSteeringActive=false
 H.cars={[0]=car()}
 for k in pairs(script) do script[k]=nil end
 assert(load(APP_SOURCE,'@SpotterEnginer.lua'))()
 hello,data=require('src/port').bridgeOpen()
 return SPE_TEST.app
end
-- Images : AdvancedIA factice bat (state : champs du pont) si beat est donné.
local function frames(seconds,beat)
 for _=1,math.max(1,math.floor(seconds/DT+0.5)) do
  H.clock=H.clock+DT
  if beat then
   hello.heartbeat=hello.heartbeat+1; hello.bridgeVersion=Layout.version
   data.enabled=true; data.paused=beat.paused==true; data.ready=beat.ready==true; data.guard=beat.guard or ''
  end
  script.update(DT)
 end
end
local function played(name) for _,p in ipairs(H.played) do if p:find(name,1,true) then return true end end return false end
local function call(app,key,role,prio,ttl)
 return Voice.say(app.voice,{key=key,role=role,prio=prio,clips={APP..'/vox/FR/'..key..'.wav'},text=key,ttl=ttl or 30},app.radioNow)
end
-- Essai de la voix : dit sans AdvancedIA (liaison perdue depuis longtemps) et en pause ; rien d'autre n'est dit.
function T.voice_test_plays_without_aai_and_in_pause()
 local app=boot()
 frames(5)
 check(app.link.state=='absent' and #H.played==0,'no AdvancedIA: silent ('..app.link.state..')')
 call(app,'stale','engineer',3); app.test('spotter'); frames(2)
 check(played('FR/01_vert') and not played('stale'),'voice test said without AdvancedIA, nothing else: '..tostring(H.played[1]))
 H.sim.isPaused=true; frames(1)
 app.test('engineer'); frames(2)
 check(played('FR/27_pit_window_open'),'voice test said in pause')
 H.sim.isPaused=false
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
end
-- Liaison suspendue (pause d'AdvancedIA) : la phrase en cours finit, la file est vidée ; l'horloge de la radio ne
-- s'écoule pas pendant la pause du jeu et reprend ensuite.
function T.suspended_link_empties_the_queue_and_pause_freezes_the_radio_clock()
 local app=boot({aai=true})
 frames(0.1)
 call(app,'first','spotter',3); call(app,'second','engineer',4); call(app,'third','spotter',2)
 frames(DT)
 check(played('third') and #H.played==1,'a call started while the link is only waiting')
 H.sim.isPaused=true
 frames(0.2,{paused=true})
 check(app.link.state=='suspended' and #app.voice.queue==0,'suspended: queue emptied ('..app.link.state..', '..#app.voice.queue..')')
 check(Voice.busy(app.voice),'the call in progress goes on')
 local frozen=app.radioNow
 frames(3,{paused=true})
 check(#H.played==1 and not Voice.busy(app.voice),'it finished, nothing else was said: '..#H.played)
 check(math.abs(app.radioNow-frozen)<1e-6,'radio clock frozen in pause: '..(app.radioNow-frozen))
 -- Délai par clé : il ne s'écoule pas en pause (une annonce sous son délai avant la pause l'est encore après).
 app.voice.last.cool=frozen
 check(Voice.refused(app.voice,'spotter','cool',2,app.radioNow),'cooldown did not elapse in pause')
 H.sim.isPaused=false
 frames(1,{paused=false,guard='init'})
 check(app.radioNow-frozen>0.9 and app.radioNow-frozen<1.1,'radio clock runs again: '..(app.radioNow-frozen))
 -- AdvancedIA coupé ou pas prêt, hors pause : même règle.
 call(app,'later','engineer',3); frames(1,{guard='init'})
 check(not played('later') and #app.voice.queue==0,'suspended without pause: nothing said')
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
end
-- Redémarrage de la même séance avant la fin du premier tour : radio et modules repartent de zéro ; ni la pause, ni la
-- rediffusion, ni la voie des stands ne remettent à zéro.
function T.session_restart_in_the_first_lap_resets()
 local app=boot()
 local function mark() app.voice.last.mark=1 end
 local function reset() return app.voice.last.mark==nil end
 H.sim.currentSessionTime=40000; frames(3); mark()
 -- Voie des stands, pause, rediffusion (temps et tours de l'enregistrement) : rien.
 H.cars[0].isInPitlane=true; H.sim.currentSessionTime=45000; frames(1); H.cars[0].isInPitlane=false
 H.sim.isPaused=true; frames(1); H.sim.isPaused=false; frames(0.2)
 H.sim.isReplayActive=true; H.sim.currentSessionTime=2000; H.sim.isSessionStarted=false; frames(1)
 H.sim.isReplayActive=false; H.sim.currentSessionTime=46000; H.sim.isSessionStarted=true; frames(0.5)
 check(not reset(),'no reset in the pits, in pause or in a replay')
 -- Temps de séance qui recule nettement (tours inchangés : 0).
 H.sim.currentSessionTime=-5000; frames(DT)
 check(reset(),'session time going back: reset')
 -- Petit recul (moins de 2 s) : rien.
 frames(3); mark(); H.sim.currentSessionTime=-6000; frames(0.5)
 check(not reset(),'small step back: no reset')
 -- Départ donné qui redevient non donné, en course.
 H.sim.isSessionStarted=false; frames(DT)
 check(reset(),'start taken back: reset')
 H.sim.isSessionStarted=true; frames(3); mark()
 -- Redémarrage choisi dans le menu pause : vu à la reprise.
 H.sim.isPaused=true; frames(0.5); H.sim.currentSessionTime=-30000; frames(0.5)
 check(not reset(),'nothing while paused')
 H.sim.isPaused=false; frames(DT)
 check(reset(),'restart from the pause menu seen when the game resumes')
 H.sim.currentSessionTime=nil
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
end
-- Réglages : enregistrés au déchargement de l'app (changement de moins d'une seconde), et enregistrement comme
-- raccourcis continuent quand le reste de l'image est en erreur.
function T.settings_saved_on_unload_and_despite_frame_errors()
 local app=boot()
 frames(1)
 app.set('volume',1.2)
 H.release()
 local saved=JSON.parse(H.storage['spe:'].settings)
 check(saved and saved.volume==1.2,'saved when the app unloads: '..tostring(saved and saved.volume))
 local Link=require('src/link'); local step=Link.step
 Link.step=function() error('frame broken') end
 app.set('volume',0.8)
 H.keys[0x11]=true; H.keys[0x12]=true; H.keys[0x4B]=true; frames(DT); H.keys={}
 frames(1.5)
 Link.step=step
 saved=JSON.parse(H.storage['spe:'].settings)
 check(saved.volume==0.8,'saved although the frame fails: '..tostring(saved.volume))
 check(app.editing==true,'hotkey still read although the frame fails')
 check(app.errors.count>0,'the frame error is counted')
 app.toggleEditor()
end
-- Overlay Stratégie : un « box » resté engagé alors que le plan refait ne prévoit plus d'arrêt (ni fenêtre) ne met plus
-- l'overlay en erreur ; un overlay en erreur ne retire ni le bouton ni le panneau d'édition.
function T.strategy_overlay_without_window_and_editor_kept()
 local app=boot({aai=true})
 frames(0.5,{ready=false,guard='init'})
 local E=require('src/editor'); local O=require('src/overlays')
 local t=app.engineer.strategist
 local plan,box,state,d=t.plan,t.boxLap,app.link.state,app.link.d
 t.plan={ok=true,total=20,done=4,stops=0,costs={},cost=1500,degNow=0.1,degAtStop=0.1,remaining=16}; t.boxLap=3
 app.link.state='connected'; app.link.d=data
 app.toggleEditor()
 local before=app.errors.count
 H.windowIds={}; H.texts={}; script.SPE__HUD()
 local texts=table.concat(H.texts,'|')
 check(app.errors.count==before,'no error with a committed box and no window: '..tostring(app.errors.last))
 check(H.windowIds['SpotterEnginer_d1_strategy'] and texts:find('Aucun arrêt',1,true),'strategy overlay drawn: no stop')
 check(H.windowIds[E.ids.launcher] and H.windowIds[E.ids.panel],'editor drawn')
 local draw=O.draw.engineer
 O.draw.engineer=function() error('overlay broken') end
 H.windowIds={}; script.SPE__HUD()
 O.draw.engineer=draw
 check(app.errors.count==before+1,'overlay error counted once: '..(app.errors.count-before))
 check(H.windowIds[E.ids.launcher] and H.windowIds[E.ids.panel],'button and panel still drawn when an overlay fails')
 check(H.fonts==0 and H.clips==0,'fonts and clips balanced')
 app.toggleEditor()
 t.plan=plan; t.boxLap=box; app.link.state=state; app.link.d=d
end
-- Module de la mise à jour illisible : le remplaçant de SpotterEnginer.lua n'a pas la liste des dossiers d'AdvancedIA ;
-- le port se charge quand même, avec les deux noms connus.
function T.port_loads_without_the_update_module()
 local loaded=package.loaded
 local port,update=loaded['src/port'],loaded['src/update']
 local function none() end
 loaded['src/update']=setmetatable({},{__index=function() return none end}); loaded['src/port']=nil
 local ok,P=pcall(require,'src/port')
 loaded['src/update']=update; loaded['src/port']=port
 check(ok and type(P)=='table','port loads with the stand-in update module: '..tostring(P))
 check(P.aaiFolders[1]=='AdvancedIA' and P.aaiFolders[2]=='ACAdvancedIA' and #P.aaiFolders==2,'known folders used')
 check(port.aaiFolders==update.companion.folders,'real module: the list of the update module')
end
-- Mémoire gardée au rechargement à chaud (ctx.keep, Port.keep) : chaîne ou nil, propre à la séance suivie ; les annonces
-- entendues de l'ingénieur sont relues après un rechargement dans la même séance, pas après une relance du jeu ni un
-- redémarrage de la séance.
function T.keep_survives_a_hot_reload_only()
 local app=boot()
 local keep=require('src/port').keep
 frames(0.2)
 check(keep.load('none')==nil,'unknown name: nil')
 keep.store('said','a,b'); check(keep.load('said')=='a,b','text kept')
 keep.store('count',3); check(keep.load('count')=='3','a number comes back as text')
 keep.store('said',''); check(keep.load('said')==nil,'empty text: nil')
 keep.store('said','a,b')
 -- L'ingénieur dit une annonce (liaison en attente depuis moins de 3 s : la radio parle encore).
 Voice.say(app.voice,{key='wear',role='engineer',prio=3,clips={APP..'/vox/FR/69_usure_anormale.wav'},text='Usure',sense='abnormalWear',ttl=10},app.radioNow)
 frames(1.5)
 check(app.voice.heard.abnormalWear~=nil,'heard')
 -- Rechargement à chaud : même séance, mémoire relue.
 app=boot({reload=true}); frames(0.2)
 check(app.voice.heard.abnormalWear~=nil,'heard calls restored after a hot reload')
 check(keep.load('said')=='a,b','kept text read again after a hot reload')
 Voice.say(app.voice,{key='wear',role='engineer',prio=3,clips={APP..'/vox/FR/69_usure_anormale.wav'},text='Usure',sense='abnormalWear',ttl=10},app.radioNow)
 frames(1.5)
 check(not played('69_usure_anormale'),'not said again after the hot reload')
 -- Redémarrage de la séance : portée neuve.
 H.sim.currentSessionTime=30000; frames(3); H.sim.currentSessionTime=0; frames(DT)
 check(keep.load('said')==nil and next(app.voice.heard)==nil,'session restart: nothing kept')
 keep.store('said','c')
 -- Autre séance après un rechargement : rien n'est relu.
 H.sim.currentSessionIndex=1
 app=boot({reload=true}); frames(0.2)
 check(keep.load('said')==nil,'another session: nothing read')
 H.sim.currentSessionIndex=0; H.sim.currentSessionTime=nil
 -- Relance du jeu : mémoire partagée vide.
 keep.store('said','d')
 app=boot(); frames(0.2)
 check(keep.load('said')==nil and next(app.voice.heard)==nil,'game relaunch: nothing kept')
end
-- Clips présents : seuls ceux du catalogue comptent (un fichier en trop ne masque pas un clip manquant).
function T.present_clips_count_the_catalog_only()
 local app=boot({files=function()
  H.files[APP..'/vox/FR/999_ancien_clip.wav']='mp3'; H.files[APP..'/vox/EN/num/zz.mp3']='mp3'
  H.files[APP..'/vox/FR/01_vert.wav']=nil
 end})
 local expected=0
 Catalog.eachFile(function(rel) if H.files[APP..'/vox/'..rel] then expected=expected+1 end end)
 check(app.voicePresent==expected and app.voicePresent<app.voiceTotal,'catalog clips only: '..app.voicePresent..' / '..expected..' / '..app.voiceTotal)
end
-- Pilotage à la souris : son mouvement ne montre pas le bouton d'édition (il resterait affiché) ; sinon, oui.
function T.edit_button_ignores_mouse_steering()
 local app=boot()
 local E=require('src/editor')
 local function hud() H.windowIds={}; script.SPE__HUD() end
 H.sim.isMouseSteeringActive=true; frames(0.2)
 hud(); H.mouse=vec2(600,500); hud(); H.mouse=vec2(700,520); hud()
 check(not H.windowIds[E.ids.launcher],'mouse steering: button not shown by the movement')
 H.sim.isMouseSteeringActive=false; frames(0.2)
 H.mouse=vec2(620,500); hud()
 check(H.windowIds[E.ids.launcher],'no mouse steering: button shown when the mouse moves')
 H.mouse=vec2(-100,-100)
 check(app.editing~=true and #H.logs==0,'errors: '..table.concat(H.logs,' | '))
end
-- Avant la copie des fichiers d'une mise à jour (rappel beforeCopy du port) : radio arrêtée, clips préchargés libérés
-- (aucun fichier tenu par FMOD) ; la radio reparle ensuite.
function T.update_copy_releases_the_clips()
 local app=boot()
 frames(2)
 app.test('spotter'); frames(DT)
 check(Voice.busy(app.voice),'a call is being said')
 H.disposed=0
 app.updatePort.beforeCopy()
 check(not Voice.busy(app.voice) and #app.voice.queue==0,'radio stopped')
 check(H.disposed>=#Catalog.hot,'preloaded clips released: '..H.disposed)
 local n=H.disposed
 require('src/port').release(); check(H.disposed==n,'nothing left to release')
 H.played={}; app.test('engineer'); frames(1)
 check(played('FR/27_pit_window_open'),'the radio speaks again afterwards')
end
-- Vérification de mise à jour au lancement : pas refaite à chaque rechargement à chaud (moins de 10 minutes après la
-- précédente), refaite ensuite.
function T.update_check_not_repeated_on_hot_reload()
 local Port=require('src/port'); local Update=require('src/update')
 local wall,check0,tick0,clock0=1000,Update.check,Update.tick,Port.wallClock
 local asked=0
 Port.wallClock=function() return wall end
 Update.check=function() asked=asked+1; return true end
 Update.tick=function() end
 local ok,err=pcall(function()
  local app=boot(); app.updatePort.ready=true; frames(11)
  check(asked==1,'checked once after launch: '..asked)
  frames(5); check(asked==1,'only once per launch')
  wall=1100; app=boot({reload=true}); app.updatePort.ready=true; frames(11)
  check(asked==1,'hot reload 100 s later: not asked again ('..asked..')')
  wall=1700; app=boot({reload=true}); app.updatePort.ready=true; frames(11)
  check(asked==2,'hot reload 10 minutes later: asked again ('..asked..')')
  app.updatePort.ready=false
 end)
 Port.wallClock=clock0; Update.check=check0; Update.tick=tick0
 if not ok then error(err,0) end
end
-- Réglage changé : les annonces en attente du rôle coupé sont écartées, toutes au changement de langue (elles sont
-- dans l'autre langue) ; la phrase en cours finit.
function T.setting_change_purges_the_waiting_calls()
 local app=boot()
 frames(0.2)
 call(app,'now','spotter',3); frames(DT)
 call(app,'eng','engineer',3); call(app,'spot','spotter',3)
 app.set('engineerOn',false)
 check(#app.voice.queue==1 and app.voice.queue[1].key=='spot' and Voice.busy(app.voice),'engineer off: its waiting calls dropped, the rest kept')
 app.set('engineerOn',true); call(app,'eng','engineer',3)
 app.set('language','EN')
 check(#app.voice.queue==0 and Voice.busy(app.voice),'language changed: waiting calls dropped, the current one goes on')
 app.set('language','FR')
 -- Un autre réglage ne touche pas la file.
 call(app,'spot','spotter',3); app.set('volume',1.3); app.set('volume',1.7)
 check(#app.voice.queue==1,'other settings leave the queue alone')
 Voice.stop(app.voice)
end
-- Positions des overlays et du bouton d'édition : enregistrables au-delà de 7680 px (triple écran 4K), bornées à l'écran
-- à l'affichage.
function T.overlay_positions_beyond_7680()
 local app=boot()
 local Config=require('src/config')
 check(Config.valid('strategyX',11000)==11000 and Config.valid('editorX',11000)==11000 and Config.valid('spotterY',5000)==5000,'wide positions kept')
 check(Config.valid('strategyX',99999)==Config.maxX and Config.valid('strategyX',-7)==-1,'still bounded')
 app.set('strategyX',11000); frames(DT)
 check(app.cfg.strategyX==11000,'stored')
 app.set('strategyX',-1)
end
-- Circuit ouvert (de A à B) : F.open vrai ; boucle fermée : nil.
function T.open_track_flag()
 local app=boot(); frames(DT)
 check(app.F.open==nil,'closed loop: nil')
 H.sim.isTrackOpen=true; frames(DT)
 check(app.F.open==true,'open track: true')
 H.sim.isTrackOpen=nil
end
return T
