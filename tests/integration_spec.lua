-- Intégration sur l'hôte CSP factice (tests/host.lua) : AdvancedIA factice qui publie avec son vrai pont
-- (src/bridge.lua, et le constructeur de structure de docs/PONT_ACADVANCEDIA.md), SpotterEnginer.lua réel, course
-- simulée de six voitures ; fenêtre de réglages et trois overlays dessinés. Variables données par tests/run.py :
-- HOST (hôte), VOX (clips présents), DOC_BRIDGE (code du raccordement d'applier.lua), APP_SOURCE (SpotterEnginer.lua),
-- APP_MANIFEST (manifest.ini de l'app).
local H=HOST
local T={}
local check=require('tests/helpers').check
local Bridge=require('aai/bridge')
local Layout=require('src/bridge_layout')
local PI=math.pi
local L=4000; local R=L/(2*PI)
-- AdvancedIA factice installé sous name (dossier et script principal du même nom, comme CSP), version release.
local function installAai(name,withBridge,release)
 local aai=H.appsDir..'/'..name
 H.files[aai..'/manifest.ini']='[ABOUT]\nNAME='..name..'\nVERSION='..release..'\n'
 H.files[aai..'/'..name..'.lua']=withBridge and "local Bridge=require('src/bridge')" or '-- sans pont'
 H.files[aai..'/src/bridge.lua']='x'; H.files[aai..'/src/bridge_layout.lua']='x'
end
local function setup(withBridge)
 H.files={}
 installAai('AdvancedIA',withBridge,'Beta 1.49')
 for _,rel in ipairs(VOX) do H.files[H.appsDir..'/SpotterEnginer/vox/'..rel]='mp3' end
 H.files[H.appsDir..'/SpotterEnginer/sounds/radio.wav']='wav'
 H.files[H.appsDir..'/SpotterEnginer/manifest.ini']=APP_MANIFEST
 H.files[H.appsDir..'/SpotterEnginer/icon.png']='png'; H.images=0; H.windows=0; H.windowIds={}; H.audio={}; H.minEngine=1
 H.shared={}; H.played={}; H.logs={}; H.clock=0; H.texts={}; if not H.keepStorage then H.storage={} end; H.desktop=H.startDesktop or 0
 for k in pairs(script) do script[k]=nil end
end
-- Raccordement d'applier.lua (texte du document), avec ses dépendances locales.
-- source : code de bridgeOpen à tester (celui du document par défaut, ou celui installé dans AdvancedIA).
local function aaiPort(source)
 local chunk=assert(load('local M={}; local function callable(f) return type(f)=="function" end\n'..(source or DOC_BRIDGE)..'\nreturn M','@AdvancedIA bridgeOpen'))
 return chunk()
end
local bridgeSource=nil
local function car(i,progress,speed,lateral)
 local th=2*PI*(progress%1)
 local lx,lz=-math.sin(th),math.cos(th)
 local ox,oz=math.cos(th),math.sin(th)
 return {isConnected=true,isActive=true,position=vec3(R*math.cos(th)+lateral*ox,0,R*math.sin(th)+lateral*oz),look=vec3(lx,0,lz),
  speedKmh=speed*3.6,splinePosition=progress%1,lapCount=math.floor(progress),racePosition=1,isInPitlane=false,isInPit=false,
  lapTimeMs=0,previousLapTimeMs=0,bestLapTimeMs=0,isAIControlled=i>0,isUserControlled=i==0,isRetired=false,isRaceFinished=false,
  flashingLightsActive=false,aabbSize=vec3(1.9,1.2,4.6),fuel=0,maxFuel=100,fuelPerLap=0,fuelMap=0,fuelMaps=1,brakeBias=0.56,
  hasUserBrakeBias=true,compoundIndex=0,gas=1,brake=0,gear=4,drsPresent=false,drsAvailable=false,drsActive=false,kersPresent=false,
  kersCharge=0,p2pStatus=0,p2pActivations=0,wheelsOutside=0,isLapValid=true,lapCutsCount=0,engineLifeLeft=1000,gearboxDamage=0,
  currentSector=0,currentPenaltyType=0,damage={[0]=0,0,0,0,0},wheels={}}
end
local function engine(count)
 local frame={count=count,player=1,online=false,replay=false,paused=false,flag=0,flagOwned=false,cars={}}
 local e={g={enabled=true,language='fr'},run={penaltyDisqualify=5,mandatoryStops=1,maxStintMin=0,minPitTime=0},guard='ready',
  profile='C',session=0,sessionType=3,time=0,lights={value=0,reason='',slowSlot=0},panel={decided='none',kind='none',title='',short=''},
  incidents={neutral=false,neutralMode='local',safetyPhase='none',greenUntil=-math.huge,standing='none',drsReason='',messageId=0,messageKind='',cars={}},
  delta={value=nil,kind=''},deltaBeep={beepId=0},penalties={requestId=0,reason='',kind='slow',giveBack=0,ai={count={},dq={}}},drs={beepId=0},
  commands={},states={},flash={eventId=0,heard=0},pits={state='pending',position=0,open=0.3,close=0.7,cars={}},race={},weather={wet=false},
  hud={aiSerial=0,aiCode='',aiTitle='',aiShort=''},sanctions={cars={}},strategy={cars={}}}
 for i=1,count do frame.cars[i]={valid=true,pit=false,safetyCar=false,penaltyType=0}; e.incidents.cars[i]={}; e.commands[i]={}; e.states[i]={}; e.pits.cars[i]={lastStop=0,stops=0}; e.sanctions.cars[i]={}; e.strategy.cars[i]={} end
 return e,frame
end
local function alongside(now) return (now>40 and now<44) or (now>60 and now<64) or (now>80 and now<84) end
local function race(withBridge,seconds,draw,flipTrack)
 setup(withBridge)
 H.flipTrack=flipTrack==true
 H.cost={update=0,updateKb=0,n=0,main=0,mainKb=0,hud=0,hudKb=0,draws=0}
 local count=6
 H.sim.carsCount=count; H.sim.isPaused=false
 local speeds={40,40.3,39.6,39.2,38.8,40.6}
 local dist={}
 for i=0,count-1 do dist[i]=(count-i)*45 end -- la voiture 0 (joueur) en tête de file au départ
 local fuel=30
 local e,frame=engine(count)
 local port=withBridge and aaiPort(bridgeSource).bridgeOpen(Layout) or nil
 local b=Bridge.new('Beta 1.46')
 -- Script réel de SpotterEnginer.
 assert(load(APP_SOURCE,'@SpotterEnginer.lua'))()
 local dt=H.raceDt or 1/30
 local lastLap={}
 local pit={state='out'} -- arrêt de la voiture 3 vers 1,95 tour : voie à 60 km/h, 6 s immobile
 for step=1,math.floor(seconds/dt) do
  H.clock=H.clock+dt
  local now=H.clock
  -- Neutralisation (SC) de 120 s à 170 s, rentrée au tour à 150 s.
  e.time=now
  e.incidents.neutral=now>=120 and now<170; e.incidents.neutralMode=e.incidents.neutral and 'sc' or 'local'
  e.incidents.safetyPhase=now>=150 and now<170 and 'in' or e.incidents.neutral and 'out' or 'none'
  if now>=170 and now<171 then e.incidents.greenUntil=now+5 end
  e.pits.state=now>=200 and 'open' or 'pending'
  for i=0,count-1 do
   local v=speeds[i+1]*(e.incidents.neutral and 0.6 or 1)
   if i==3 then
    local pr=dist[3]/L
    if pit.state=='out' and pr>=1.95 and pr<1.96 then pit.state='lane' end
    if pit.state=='lane' then v=16.67; if pr>=2.0 then pit.state='box'; pit.boxUntil=now+6 end end
    if pit.state=='box' then v=0; if now>=pit.boxUntil then pit.state='lane2' end end
    if pit.state=='lane2' then v=16.67; if pr>=2.05 then pit.state='done' end end
   end
   dist[i]=dist[i]+v*dt
   -- La voiture 1 passe à côté du joueur (à gauche) entre 40 et 44 s.
   local lateral=(i==1 and alongside(now)) and 2.6 or 0
   if i==1 and alongside(now) then dist[1]=dist[0] end
   local progress=dist[i]/L
   local c=car(i,progress,v,lateral)
   local lap=math.floor(progress)
   if lastLap[i] and lap>lastLap[i] then c.previousLapTimeMs=L/speeds[i+1]*1000 end
   if lastLap[i] and lap==lastLap[i] and H.cars[i] then c.previousLapTimeMs=H.cars[i].previousLapTimeMs end
   lastLap[i]=lap
   if i==3 then c.isInPitlane=pit.state=='lane' or pit.state=='box' or pit.state=='lane2'; c.isInPit=pit.state=='box' end
   H.cars[i]=c
  end
  -- Positions au classement.
  local order={}; for i=0,count-1 do order[#order+1]=i end
  table.sort(order,function(a,b2) return dist[a]>dist[b2] end)
  for k,i in ipairs(order) do H.cars[i].racePosition=k end
  -- Joueur : carburant, pneus, freins.
  fuel=fuel-2.5*speeds[1]*dt/L*(e.incidents.neutral and 0.6 or 1)
  local me=H.cars[0]; me.fuel=fuel
  local vkm=dist[0]/L*0.4
  for k=0,3 do me.wheels[k]={tyreCoreTemperature=82,tyreInsideTemperature=85,tyreMiddleTemperature=83,tyreOutsideTemperature=80,
   tyreOptimumTemperature=80,tyrePressure=27,tyreWear=1,tyreVirtualKM=vkm,tyreGrain=0,tyreBlister=0,tyreFlatSpot=0,isBlown=false,tyreDirty=0,discTemperature=450,brakeTemperature=0} end
  frame.player=1
  -- Point d'accroche des tests : état d'AdvancedIA modifié à cet instant (annonces, etc.).
  if H.onStep then H.onStep(now,e) end
  if port then Bridge.beat(b,port.hello); Bridge.publish(b,port.data,e,frame) end
  -- Mesure (tools : coût par image) : temps et mémoire allouée par l'app seule.
  local t0,m0=os.clock(),collectgarbage('count')
  script.update(dt)
  H.cost.update=H.cost.update+os.clock()-t0; H.cost.updateKb=H.cost.updateKb+math.max(0,collectgarbage('count')-m0); H.cost.n=H.cost.n+1
  local eng=H.audio['engine:0']; if eng and eng<H.minEngine then H.minEngine=eng end
  if draw and step%3==0 then
   local t1,m1=os.clock(),collectgarbage('count')
   H.space=vec2(860,640); script.SPE__MAIN(); check(H.fonts==0 and H.clips==0,'settings window left fonts/clips open')
   local t2,m2=os.clock(),collectgarbage('count')
   script.SPE__HUD(); check(H.fonts==0 and H.clips==0,'overlays left fonts/clips open')
   H.cost.main=H.cost.main+t2-t1; H.cost.mainKb=H.cost.mainKb+math.max(0,m2-m1); H.cost.hud=H.cost.hud+os.clock()-t2; H.cost.hudKb=H.cost.hudKb+math.max(0,collectgarbage('count')-m2); H.cost.draws=H.cost.draws+1
  end
 end
end
local function played(name) for _,p in ipairs(H.played) do if p:find(name,1,true) then return true end end return false end
local function texted(pattern) for _,t in ipairs(H.texts) do if t:find(pattern) then return true end end return false end
function T.full_race_with_bridge()
 race(true,260,true)
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
 check(played('FR/07_SC.wav'),'SC called by voice')
 check(played('FR/26_sc_rentre_ce_tour.wav'),'SC in this lap')
 check(played('FR/01_vert.wav'),'green')
 check(played('FR/27_pit_window_open.wav'),'pit window open')
 check(texted('Connecté à AdvancedIA') or texted('CONNECTÉ À ADVANCEDIA'),'link chip drawn')
 check(texted('FENÊTRE') and texted('^T%d+') or texted('Aucun arrêt'),'strategy window drawn')
 check(texted('GAUCHE'),'spotter overlay sides')
 check((H.images or 0)>0,'logo drawn in the header')
 check(texted('SPOTTER') and texted('ENGINER'),'brand name in the header')
end
function T.pit_loss_learnt_from_ai_stop()
 race(true,260,false)
 local app=SPE_TEST.app
 local loss=app.engineer.strategist.data.laneLoss
 -- Voie de 400 m à 60 km/h (24 s) contre 10,2 s en piste : environ 13,8 s de perte de voie (hors arrêt immobile).
 check(loss and loss>10 and loss<18,'lane loss learnt from the AI stop: '..tostring(loss))
 check(app.spotter.autoFlip==false,'sides agree with the CSP track position')
end
function T.sides_swapped_automatically_when_track_disagrees()
 race(true,100,false,true)
 check(SPE_TEST.app.spotter.autoFlip==true,'auto flip after repeated disagreement')
end
function T.language_switch_and_settings_saved()
 race(true,20,false)
 SPE_TEST.app.set('language','EN')
 H.texts={}
 for _=1,40 do H.clock=H.clock+1/30; script.update(1/30) end
 H.space=vec2(860,640); script.SPE__MAIN()
 check(texted('CONNECTED TO ADVANCEDIA'),'english chip')
 local saved=H.storage['spe:'] and H.storage['spe:'].settings or ''
 check(saved:find('EN',1,true),'settings saved: '..saved:sub(1,80))
end
-- Code réellement installé dans AdvancedIA (src/applier.lua) : se connecte-t-il à SpotterEnginer ?
function T.installed_aai_bridge_connects()
 check(INSTALLED_BRIDGE~='','no bridgeOpen in the installed AdvancedIA')
 bridgeSource=INSTALLED_BRIDGE
 local ok,err=pcall(race,true,130,false)
 bridgeSource=nil
 if not ok then error(err,0) end
 local app=SPE_TEST.app
 check(app.link.state=='connected','installed bridge -> '..tostring(app.link.state))
 check(app.link.remoteRelease=='Beta 1.46','release read through the bridge: '..tostring(app.link.remoteRelease))
 check(played('FR/07_SC.wav'),'SC called through the installed bridge')
end
function T.car_sound_lowered_during_radio_then_restored()
 race(true,130,false)
 local level=require('src/config').defaults().duckLevel
 check(H.minEngine<1 and H.minEngine<=level+1e-6,'engine lowered to the setting while the radio speaks: '..tostring(H.minEngine))
 -- Radio silencieuse : retour au niveau d'origine.
 SPE_TEST.app.voice.queue={}
 for _=1,300 do H.clock=H.clock+1/30; script.update(1/30); if not SPE_TEST.app.voice.current then break end end
 for _=1,60 do H.clock=H.clock+1/30; script.update(1/30) end
 check(H.audio['engine:0']==1,'engine restored: '..tostring(H.audio['engine:0']))
end
function T.overlay_settings_apply()
 race(true,40,false)
 local app=SPE_TEST.app
 H.windows=0; H.windowIds={}; script.SPE__HUD()
 check(H.windowIds['SpotterEnginer_d1_spotter'] and H.windowIds['SpotterEnginer_d1_engineer'] and H.windowIds['SpotterEnginer_d1_strategy'],'three overlays shown')
 app.set('engineerShow',false); app.set('overlaysOn',true); H.windowIds={}; script.SPE__HUD()
 check(not H.windowIds['SpotterEnginer_d1_engineer'],'engineer overlay hidden by its setting')
 app.set('overlaysOn',false); H.windowIds={}; script.SPE__HUD()
 check(next(H.windowIds)==nil,'all overlays hidden (Ctrl+Alt+J)')
 app.set('overlaysOn',true); app.backgrounds('transparent')
 check(app.cfg.spotterBackground=='transparent' and app.cfg.strategyAccent==false,'transparent backgrounds without decorative band')
 app.set('spotterHeader',false); app.set('spotterContent',0.5); app.set('spotterScale',1.4)
 H.windowIds={}; script.SPE__HUD(); check(H.fonts==0,'fonts balanced with header off and content alpha')
 app.recenter('spotter'); check(app.cfg.spotterX==-1 and app.cfg.spotterScale==1,'recenter')
 app.lockAll(false); check(not app.allLocked(),'unlock all'); app.lockAll(true); check(app.allLocked(),'lock all')
end
-- Chaque onglet et chaque section de la fenêtre de réglages, en français puis en anglais, à la taille d'origine
-- (860 × 640) et dans une fenêtre très haute (tout le contenu dessiné).
function T.every_settings_page_draws()
 race(true,60,false)
 local app=SPE_TEST.app
 local Config=require('src/config')
 H.space=vec2(860,640); script.SPE__MAIN()
 -- Une erreur de dessin rattrapée par la protection de la fenêtre (app.errors) doit faire échouer le test.
 local errorsBefore=app.errors.count
 for _,lang in ipairs({'FR','EN'}) do
  app.set('language',lang)
  for _,tab in ipairs(Config.tabs) do
   local list=Config.sectionsOf[tab] or {false}
   for _,sec in ipairs(list) do
    app.view.tab=tab; if sec then app.view.section[tab]=sec.id end
    for _,size in ipairs({vec2(860,640),vec2(860,4200)}) do
     H.texts={}; H.logs={}; H.space=size; script.SPE__MAIN()
     local name=tab..(sec and ('/'..sec.id) or '')..' ('..lang..', '..size.y..')'
     check(#H.logs==0,name..': '..table.concat(H.logs,' | '))
     check(H.fonts==0 and H.clips==0,name..' left fonts or clips open')
     check(#H.texts>15,name..' drew its content: '..#H.texts)
     for _,t in ipairs(H.texts) do check(utf8.len(t),name..': broken UTF-8 in « '..t:gsub('[\128-\255]','?')..' »') end
     check(app.errors.count==errorsBefore,name..': draw error caught: '..tostring(app.errors.last))
    end
   end
  end
 end
 -- Largeur minimale (760 px), radio coupée : l'en-tête reste dessiné sans erreur.
 app.set('language','FR'); app.toggleMute(); app.view.tab='spotter'
 H.texts={}; H.space=vec2(760,640); script.SPE__MAIN()
 check(app.errors.count==errorsBefore and H.fonts==0 and H.clips==0,'narrow window with radio muted')
 app.toggleMute(); app.set('language','EN')
 -- Réinitialiser une section, puis tout (deux clics) : valeurs par défaut, langue gardée.
 app.set('gapEvery',4); app.set('spotterScale',1.6)
 app.resetAll()
 check(app.cfg.gapEvery==2 and app.cfg.spotterScale==1 and app.cfg.language=='EN','reset all keeps the language')
 app.toggleMute(); check(app.radioMuted==true and app.voice.muted==true,'radio muted'); app.toggleMute(); check(not app.voice.muted,'radio back')
end
-- Déverrouillé : glisser déplace, le coin agrandit, le clic droit verrouille (souris simulée).
function T.overlay_drag_resize_and_lock()
 race(true,30,false)
 local app=SPE_TEST.app
 app.set('spotterLocked',false)
 H.activeId='##spe_mv1_spotter'; H.delta=vec2(10,5); script.SPE__HUD()
 check(app.cfg.spotterX==math.floor(1920*0.015+10+0.5) and app.cfg.spotterY==math.floor(1080*0.26+5+0.5),'dragged: '..app.cfg.spotterX..','..app.cfg.spotterY)
 -- Glissé lent (1 px par image pendant 60 images) : il avance de 60 px (les fractions s'additionnent).
 local x0=app.cfg.spotterX
 H.delta=vec2(1,0); for _=1,60 do script.SPE__HUD() end
 check(app.cfg.spotterX==x0+60,'slow drag moves: '..app.cfg.spotterX-x0)
 H.activeId=nil; script.SPE__HUD()
 -- Agrandissement lent (2 px par image) : la taille grandit à chaque image au lieu de rester figée.
 H.activeId='##spe_rs_spotter'; H.delta=vec2(2,0); for _=1,30 do script.SPE__HUD() end
 check(app.cfg.spotterScale>1.15 and app.cfg.spotterScale<1.25,'slow resize grows: '..app.cfg.spotterScale)
 H.activeId=nil; script.SPE__HUD(); app.set('spotterScale',1)
 H.activeId='##spe_mv1_spotter'; H.delta=vec2(10,5)
 H.activeId='##spe_rs_spotter'; H.delta=vec2(34,0); script.SPE__HUD()
 check(math.abs(app.cfg.spotterScale-1.1)<0.03,'resized: '..app.cfg.spotterScale)
 H.activeId=nil; H.delta=nil; H.hoverId='##spe_mv1_spotter'; H.rightClick=true; script.SPE__HUD()
 check(app.cfg.spotterLocked==true,'right-click locks')
 H.hoverId=nil; H.rightClick=false
end
-- Bureaux d'applications AC : chacun garde ses overlays ; un bureau jamais réglé est vide ; tout est enregistré.
function T.overlays_are_per_desktop()
 race(true,30,false)
 local app=SPE_TEST.app
 -- Bureau 1 (configuration existante gardée) : spotter déplacé.
 app.set('spotterX',100); app.set('spotterY',200)
 H.windowIds={}; script.SPE__HUD()
 check(H.windowIds['SpotterEnginer_d1_spotter'] and H.windowIds['SpotterEnginer_d1_strategy'],'desktop 1 shows its overlays')
 -- Bureau 2 jamais réglé : vide.
 H.desktop=1; H.windowIds={}; script.SPE__HUD()
 check(app.desktop==2 and next(H.windowIds)==nil,'desktop 2 starts empty')
 check(app.cfg.spotterX==-1,'desktop 2 has its own positions')
 -- On y affiche seulement la stratégie, ailleurs.
 app.set('strategyShow',true); app.set('strategyX',50)
 H.windowIds={}; script.SPE__HUD()
 check(H.windowIds['SpotterEnginer_d2_strategy'] and not H.windowIds['SpotterEnginer_d2_spotter'],'desktop 2: strategy only')
 -- Retour au bureau 1 : ses réglages reviennent intacts.
 H.desktop=0; H.windowIds={}; script.SPE__HUD()
 check(app.cfg.spotterX==100 and app.cfg.spotterY==200 and app.cfg.strategyX==-1 and app.cfg.engineerShow==true,'desktop 1 restored')
 local counts=app.desktopCounts()
 check(counts[1]==3 and counts[2]==1 and counts[3]==-1,'counts per desktop: '..tostring(counts[1])..','..tostring(counts[2])..','..tostring(counts[3]))
 -- Enregistré : les deux bureaux sont dans les réglages sauvegardés.
 for _=1,60 do H.clock=H.clock+1/30; script.update(1/30) end
 local saved=JSON.parse(H.storage['spe:'].settings)
 check(saved.desktops and saved.desktops['1'].spotterX==100 and saved.desktops['2'].strategyShow==true and saved.desktops['2'].spotterShow==false,'desktops saved')
 -- Copier ce bureau vers les autres.
 app.copyDesktopToAll(); counts=app.desktopCounts()
 check(counts[2]==3 and counts[4]==3,'copied to all desktops')
 -- Vider ce bureau.
 app.clearDesktop(); check(app.cfg.spotterShow==false and app.desktopCounts()[1]==0,'desktop cleared')
end
-- Relancement avec des bureaux déjà enregistrés : chaque bureau retrouve les siens, même si le dernier bureau actif
-- était un autre ; un bureau jamais réglé reste vide ; un bureau illisible garde le bureau actif.
function T.desktops_survive_a_restart()
 race(true,10,false)
 local app=SPE_TEST.app
 app.set('spotterX',111); app.set('engineerShow',false)
 H.desktop=1; script.SPE__HUD()
 app.set('strategyShow',true); app.set('strategyX',222)
 for _=1,60 do H.clock=H.clock+1/30; script.update(1/30) end
 -- Dernier enregistrement fait sur le bureau 2 : les réglages principaux contiennent ceux du bureau 2.
 H.keepStorage=true; H.startDesktop=0
 race(true,1,false)
 H.keepStorage=nil; H.startDesktop=nil
 app=SPE_TEST.app
 check(app.desktop==1 and app.cfg.spotterX==111 and app.cfg.engineerShow==false and app.cfg.strategyX==-1,'desktop 1 restored after restart: '..app.cfg.spotterX..','..app.cfg.strategyX)
 local counts=app.desktopCounts()
 check(counts[1]==2 and counts[2]==1 and counts[3]==-1,'counts after restart: '..counts[1]..','..counts[2]..','..counts[3])
 H.desktop=2; script.SPE__HUD()
 check(app.desktop==3 and app.cfg.spotterShow==false and app.cfg.engineerShow==false and app.cfg.strategyShow==false,'desktop 3 empty after restart')
 H.desktop=1; script.SPE__HUD()
 check(app.cfg.strategyX==222 and app.cfg.spotterShow==false,'desktop 2 restored after restart')
 -- Bureau illisible un instant : on reste sur le bureau 2.
 H.desktop=-5; script.SPE__HUD()
 check(app.desktop==2 and app.desktopAvailable==false and app.cfg.strategyX==222,'unreadable desktop keeps the active one')
 H.desktop=0
end
-- Une section coupée fait taire ses annonces sans changer les choix qu'elle contient ; elle les retrouve rallumée,
-- et après un relancement.
function T.section_off_silences_its_calls()
 race(true,10,false)
 local app=SPE_TEST.app
 app.set('raceControl',false); app.set('sec_penalties',false)
 check(app.cfg.blueFlags==true and app.run.blueFlags==false,'flags off: blue flags silenced, choice kept')
 check(app.cfg.penaltiesVoice==true and app.run.penaltiesVoice==false and app.run.trackLimits==false,'penalties off')
 check(app.run.raceControl==false and app.run.gapEvery==app.cfg.gapEvery and app.run.deltaVoice==true,'other settings read through')
 -- Les sous-réglages des sections sans interrupteur et des overlays ne sont jamais forcés.
 app.set('spotterShow',false); check(app.run.spotterLocked==app.cfg.spotterLocked,'overlay keys never forced')
 app.set('spotterShow',true)
 -- Relancement : choix et sections retrouvés.
 for _=1,60 do H.clock=H.clock+1/30; script.update(1/30) end
 H.keepStorage=true; race(true,1,false); H.keepStorage=nil
 app=SPE_TEST.app
 check(app.cfg.raceControl==false and app.cfg.blueFlags==true and app.run.blueFlags==false,'kept after restart')
 app.set('raceControl',true); app.set('sec_penalties',true)
 check(app.run.blueFlags==true and app.run.penaltiesVoice==true and app.run.trackLimits==true,'sections back on')
end
-- Course de 10 tours (pas de 0,1 s) : pas plus de 3 informations par tour en moyenne une fois la SC passée (hors côte à
-- côte et direction de course), et jamais le même texte deux fois en 150 s.
-- Demande du pilote (05/11/2026) : aucune annonce de stratégie dans les premiers tours, le temps que l'ingénieur ait
-- des mesures. Course simulée de 1000 s (tours de 100 s, SC au tour 2) : ni box, ni fenêtre, ni tour optimal, ni
-- duel, ni carburant, ni temps cible avant que le plan soit prêt (au plus tôt à la fin du tour 3) ; la fenêtre
-- réglementaire ouverte à 200 s est dite par le spotter, sans tour optimal ; la fenêtre du plan est annoncée ensuite.
function T.no_strategy_call_in_first_laps()
 H.raceDt=0.1
 local Voice=require('src/voice'); local new=Voice.new
 Voice.new=function(port) local v=new(port); v.logMax=5000; return v end
 local Strategist=require('src/strategist'); local step=Strategist.step
 local readyAt,readyLaps=nil,nil
 Strategist.step=function(t,ctx)
  local r=step(t,ctx)
  if t.ready and not readyAt then readyAt=H.clock; readyLaps=ctx.F.cars[ctx.F.player].laps end
  return r
 end
 local ok,err=pcall(race,true,1000,false)
 Voice.new=new; Strategist.step=step; H.raceDt=nil
 if not ok then error(err,0) end
 check(readyAt and readyLaps>=3,'plan ready after lap 3 at the earliest: '..tostring(readyLaps)..' laps at '..tostring(readyAt))
 local STRAT={box=true,boxNeutral=true,window=true,duel=true,fuel=true,fuelOk=true,map=true,target=true}
 local windowOpen,windowAfter=nil,false
 for _,e in ipairs(SPE_TEST.app.voice.log) do
  if e.role=='engineer' and (STRAT[e.key] or e.key=='pitCall') then
   check(e.at>=readyAt,string.format('engineer strategy call before the plan is ready: « %s » at %.0f s (ready at %.0f s)',e.text,e.at,readyAt))
  end
  if e.key=='pitCall' and e.at<readyAt then windowOpen=e end
  if e.key=='window' and e.at>=readyAt then windowAfter=true end
 end
 check(windowOpen and windowOpen.role=='spotter' and not windowOpen.text:find('optimal',1,true),'regulation window open said by the spotter, rule only: '..tostring(windowOpen and windowOpen.text))
 check(windowAfter,'plan window announced once ready')
end
-- Course du 05/11/2026 à 14:17 : avis « même composé » au départ, le spotter est resté muet jusqu'à la mi-tour. Avec
-- l'avis en attente, le côte à côte (40 à 44 s) et les autres annonces doivent marcher, sans erreur ; l'avis est dit à
-- la mi-tour (vers 43 s).
function T.spotter_works_while_start_notice_waits()
 H.onStep=function(now,e)
  if now>=1 and e.incidents.messageId==0 then
   e.incidents.messageId=1; e.incidents.messageKind='pitPlanSame'; e.incidents.messageValue=0; e.incidents.messageExtra=0
   e.ownTitle='Stratégie des stands'; e.ownText='Stratégie des stands : même composé prévu (SS)'
  end
 end
 local ok,err=pcall(race,true,60,false)
 H.onStep=nil
 if not ok then error(err,0) end
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
 local side=false
 for _,p in ipairs(H.played) do if p:find('FR/36_',1,true) or p:find('FR/37_',1,true) then side=true end end
 check(side,'side by side called while the start notice waits')
 check(played('FR/127_strategie_meme_compose.wav'),'start notice said after half a lap')
end
-- Journal de session : en-tête, réglages, liaison, activité, séance, tours, radio, point d'état, plan prêt.
function T.journal_written()
 race(true,450,false)
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
 local text=H.files[H.appsDir..'/SpotterEnginer.log'] or ''
 for _,want in ipairs({'=== SpotterEnginer','réglages : langue FR','liaison : connected','spotter et ingénieur : actifs',
  'tour 1 fini : ','radio spotter p','(dite)','état : P','voiture(s) à moins de 30 m','plan prêt : '}) do
  check(text:find(want,1,true),'journal line missing: '..want..'\n'..text:sub(1,600))
 end
 -- Une ligne par événement, horodatée : date, temps de séance, tour.
 check(text:match('\n%d%d%d%d%-%d%d%-%d%d %d%d:%d%d:%d%d +[%d%.]+ T%d'),'timestamped lines')
 -- Version de l'app : celle du manifeste (une seule source), dans le journal et l'en-tête.
 local version=APP_MANIFEST:match('\nVERSION%s*=%s*([^\r\n]+)')
 check(version and SPE_TEST.app.version==version and text:find('=== SpotterEnginer '..version,1,true),'version from the manifest: '..tostring(SPE_TEST.app.version))
end
function T.no_message_spam_over_ten_laps()
 H.raceDt=0.1
 -- Journal assez long pour toute la course (40 entrées en jeu) : même module que celui chargé par l'app.
 local Voice=require('src/voice'); local new=Voice.new
 Voice.new=function(port) local v=new(port); v.logMax=5000; return v end
 race(true,1000,false)
 Voice.new=new; H.raceDt=nil
 local log=SPE_TEST.app.voice.log
 local RC={neutral=true,scIn=true,red=true,restart=true,zone=true,slippery=true,white=true,blackWhite=true,blackOrange=true,black=true,
  chequered=true,standing=true,pitLaneClosed=true,pitCall=true,stint=true,trackState=true,pitWaived=true,grid=true,blue=true,
  giveBack=true,penalty=true,delta=true,box=true,vscEnding=true}
 local perLap={}; local lastText={}
 for _,e in ipairs(log) do
  if e.spoken and e.key and not e.key:find('^side:') and e.kind~='aai' then
   local lap=math.floor(e.at/100)
   if not RC[e.key] and not e.key:find('^panel:') then perLap[lap]=(perLap[lap] or 0)+1 end
   local prev=lastText[e.text]
   check(not prev or e.at-prev>=150,'repeated within 150 s: « '..e.text..' » at '..math.floor(e.at)..' s')
   lastText[e.text]=e.at
  end
 end
 local total,laps=0,0
 for lap=2,9 do total=total+(perLap[lap] or 0); laps=laps+1 end
 check(total/laps<=3,string.format('%.1f information calls per lap (laps 3 to 10)',total/laps))
 check(#log>0,'the race produced radio messages')
 -- Les annonces de position font partie du compte (au moins la première, à la fin du tour 2).
 local positions=0
 for _,e in ipairs(log) do if e.key=='position' and e.spoken then positions=positions+1 end end
 check(positions>=1,'position called during the race: '..positions)
 -- Écarts dits au plus 3 s après le passage de la ligne (jamais en retard derrière d'autres informations).
 local gaps=0
 for _,e in ipairs(log) do if e.key=='gaps' then gaps=gaps+1; check(e.spoken and e.at-e.queued<=3,string.format('gap spoken %.1f s after the line',e.at-e.queued)) end end
 check(gaps>=3,'gaps called during the race: '..gaps)
end
-- Un overlay en erreur ne masque pas les autres ; l'erreur est comptée (diagnostic).
function T.overlay_error_is_isolated()
 race(true,10,false)
 local app=SPE_TEST.app
 local O=require('src/overlays'); local draw=O.draw.spotter
 O.draw.spotter=function() error('test') end
 local before=app.errors.count
 H.windowIds={}; script.SPE__HUD()
 O.draw.spotter=draw
 check(H.windowIds['SpotterEnginer_d1_engineer'] and H.windowIds['SpotterEnginer_d1_strategy'],'other overlays still drawn')
 check(app.errors.count==before+1,'error counted once: '..(app.errors.count-before))
 check(H.fonts==0 and H.clips==0,'fonts and clips balanced after the error')
end
-- Chaque clip du catalogue, chaque nombre, chaque durée et chaque position existent en FR et en EN.
function T.every_clip_file_exists()
 local Catalog=require('src/catalog')
 local have={}; for _,f in ipairs(VOX) do have[f]=true end
 local missing={}
 for _,id in ipairs(Catalog.order) do local c=Catalog.clips[id]
  if not have['FR/'..c.FR] then missing[#missing+1]='FR/'..c.FR end
  if not have['EN/'..c.EN] then missing[#missing+1]='EN/'..c.EN end
 end
 for _,l in ipairs(Catalog.languages) do
  for n=0,Catalog.maxNumber do if not have[l..'/'..Catalog.numberFile(n)] then missing[#missing+1]=l..'/'..Catalog.numberFile(n) end end
  for n=0,Catalog.maxTenths do if not have[l..'/'..Catalog.secondsFile(n)] then missing[#missing+1]=l..'/'..Catalog.secondsFile(n) end end
 end
 for n=1,Catalog.maxPosition do for _,l in ipairs(Catalog.languages) do
  if not have[l..'/'..Catalog.positionFile(n)] then missing[#missing+1]=l..'/'..Catalog.positionFile(n) end
 end end
 check(#missing==0,'missing clips: '..table.concat(missing,', '))
 -- Aucun fichier en trop (clip retiré du catalogue) : le disque compte exactement Catalog.fileCount() clips.
 local expected={}
 for _,id in ipairs(Catalog.order) do local c=Catalog.clips[id]; expected['FR/'..c.FR]=true; expected['EN/'..c.EN]=true end
 for _,l in ipairs(Catalog.languages) do
  for n=0,Catalog.maxNumber do expected[l..'/'..Catalog.numberFile(n)]=true end
  for n=0,Catalog.maxTenths do expected[l..'/'..Catalog.secondsFile(n)]=true end
  for n=1,Catalog.maxPosition do expected[l..'/'..Catalog.positionFile(n)]=true end
 end
 local extra={}
 for _,f in ipairs(VOX) do if not expected[f] then extra[#extra+1]=f end end
 check(#extra==0,'files not in the catalog: '..table.concat(extra,', '))
 check(#VOX==Catalog.fileCount(),string.format('%d files, %d expected',#VOX,Catalog.fileCount()))
end
-- Détection de l'installation (src/port.lua) : nouveau dossier AdvancedIA d'abord, ancien ACAdvancedIA ensuite, sur la
-- foi du manifeste seulement.
function T.detects_new_and_old_install_folders()
 local Port=require('src/port'); local Link=require('src/link')
 local function detect() local a,b,c,d=Port.detect(); return {installed=a,hasBridge=b,release=c,folder=d} end
 -- Nouveau nom seul (Beta 1.49 et suivantes).
 H.files={}; installAai('AdvancedIA',true,'Beta 1.49')
 local r=detect()
 check(r.installed and r.hasBridge and r.release=='Beta 1.49' and r.folder=='AdvancedIA','new folder: '..tostring(r.release)..' '..tostring(r.folder))
 -- Nouveau nom, script principal sans le pont : installé, sans pont.
 H.files={}; installAai('AdvancedIA',false,'Beta 1.49')
 r=detect(); check(r.installed and not r.hasBridge,'new folder without bridge')
 -- Ancien nom seul (installation pas encore migrée).
 H.files={}; installAai('ACAdvancedIA',true,'Beta 1.47')
 r=detect()
 check(r.installed and r.hasBridge and r.release=='Beta 1.47' and r.folder=='ACAdvancedIA','old folder: '..tostring(r.release))
 -- Ancien dossier resté sans manifeste (des fichiers traînent dedans) : absent.
 H.files={}; H.files[H.appsDir..'/ACAdvancedIA/README.md']='x'; H.files[H.appsDir..'/ACAdvancedIA/src/bridge.lua']='x'
 r=detect(); check(not r.installed and not r.hasBridge and r.release=='','old folder without manifest is not an install')
 local k=Link.new(r.installed,r.hasBridge,r.release); Link.step(k,nil,nil,1)
 check(k.state=='absent','old folder without manifest -> '..k.state)
 -- Les deux : le nouveau l'emporte.
 H.files={}; installAai('ACAdvancedIA',false,'Beta 1.47'); installAai('AdvancedIA',true,'Beta 1.49')
 r=detect(); check(r.folder=='AdvancedIA' and r.release=='Beta 1.49' and r.hasBridge,'both: new one wins, got '..tostring(r.folder))
 -- Nouveau dossier sans manifeste (copie en cours) mais ancien complet : l'ancien.
 H.files={}; installAai('ACAdvancedIA',true,'Beta 1.47'); H.files[H.appsDir..'/AdvancedIA/AdvancedIA.lua']="require('src/bridge')"
 r=detect(); check(r.folder=='ACAdvancedIA' and r.release=='Beta 1.47','new folder without manifest skipped')
end
function T.silent_without_bridge()
 race(false,60,true)
 check(#H.logs==0,'errors: '..table.concat(H.logs,' | '))
 check(#H.played==0,'no voice without AdvancedIA: '..tostring(H.played[1]))
 check(texted('SANS PONT') or texted('sans pont'),'no-bridge state shown')
 -- Overlays verrouillés : masqués sans AdvancedIA ; déverrouillé : visible pour être placé.
 check(H.windows==0,'locked overlays hidden without AdvancedIA: '..tostring(H.windows))
 SPE_TEST.app.set('spotterLocked',false); H.texts={}
 script.SPE__HUD()
 check(H.windowIds['SpotterEnginer_d1_spotter'] and not H.windowIds['SpotterEnginer_d1_engineer'],'unlocked overlay shown alone')
 check(texted('DÉVERROUILLÉ'),'unlock hint drawn')
 check(H.fonts==0,'fonts balanced')
end
return T
