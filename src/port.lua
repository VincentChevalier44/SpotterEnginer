-- Port vers CSP : seul module qui appelle ac.*, io.*, ui.MediaPlayer… (comme src/applier.lua d'AdvancedIA). Tout
-- appel risqué est protégé ; sans la fonction, la donnée reste à sa valeur neutre.
--   ouverture du pont (ac.connect, même constructeur de structure qu'AdvancedIA) et détection de l'installation ;
--   lecture de la simulation et des voitures dans des tables réutilisées (aucune table neuve par image) ;
--   lecture des clips de voix (ac.AudioEvent.fromFile, comme les bips d'AdvancedIA) ;
--   données de la voiture : courbes d'usure (tyres.ini, data.acd compris), réservoir et temps d'arrêt (car.ini).
local Layout=require('src/bridge_layout')
local Strategy=require('src/strategy')
local Catalog=require('src/catalog')
local M={}
local function callable(f) return type(f)=='function' or type(f)=='cdata' end
local function num(x,d) if type(x)=='number' and x==x and x~=math.huge and x~=-math.huge then return x end return d or 0 end
M.callable=callable
function M.appDir() local ok,d=pcall(ac.dirname); return ok and d or '' end
function M.luaAppsDir()
 local ok,d=pcall(function() return ac.getFolder(ac.FolderID.ACAppsLua) end)
 if ok and type(d)=='string' and d~='' then return (d:gsub('\\','/')) end
 local app=M.appDir():gsub('\\','/')
 return app:match('^(.*)/[^/]+$') or ''
end
function M.clock() if os and callable(os.preciseClock) then return os.preciseClock() end return os.clock() end
-- Dossier des polices (relatif à l'app) seulement si tous les fichiers sont là, comme AdvancedIA ; sinon nil :
-- Segoe UI et Consolas.
local fontFiles={'barlow/Barlow-Regular.ttf','barlow/Barlow-SemiBold.ttf','barlowcondensed/BarlowCondensed-SemiBold.ttf',
 'barlowcondensed/BarlowCondensed-Bold.ttf','barlowcondensed/BarlowCondensed-ExtraBoldItalic.ttf','jetbrainsmono/JetBrainsMono-Medium.ttf'}
function M.fontDir()
 local dir=M.appDir():gsub('\\','/')
 local ok,present=pcall(function()
  for _,file in ipairs(fontFiles) do if not io.fileExists(dir..'/fonts/'..file) then return false end end
  return true
 end)
 return ok and present and 'fonts' or nil
end
-- Taille de l'écran (overlays), comme AdvancedIA : ac.getUI().windowSize, ou nil.
function M.screen()
 if not callable(ac.getUI) then return nil end
 local ok,s=pcall(ac.getUI)
 if ok and s and s.windowSize and type(s.windowSize.x)=='number' and s.windowSize.x>0 then return s.windowSize end
 return nil
end
-- Bureau d'applications AC courant (1 à 4), comme SuperHUD : ac.getUI().currentDesktop (0 à 3), ou nil s'il est
-- illisible (version de CSP sans bureaux).
local function readDesktop() return ac.getUI().currentDesktop end
function M.desktop()
 if not callable(ac.getUI) then return nil end
 local ok,v=pcall(readDesktop)
 if ok and type(v)=='cdata' then v=tonumber(v) end
 if ok and type(v)=='number' and v==math.floor(v) and v>=0 and v<4 then return v+1 end
 return nil
end
-- Touche enfoncée (code de touche virtuelle Windows), comme les raccourcis de SuperHUD.
function M.keyDown(code)
 if not callable(ac.isKeyDown) then return false end
 local ok,down=pcall(ac.isKeyDown,code)
 return ok and down==true
end
-- Fichier de l'app (chemin complet) s'il existe, ou nil (logo de l'en-tête).
function M.appFile(name)
 local dir=M.appDir():gsub('\\','/')
 local ok,present=pcall(io.fileExists,dir..'/'..name)
 return ok and present==true and dir..'/'..name or nil
end
-- Installation d'AdvancedIA : dossier, pont présent (src/bridge.lua), version du manifeste. Nouveau nom d'abord
-- (apps/lua/AdvancedIA, Beta 1.49 et suivantes), puis l'ancien (apps/lua/ACAdvancedIA, installations pas encore
-- migrées). Seul le manifeste compte : un ancien dossier resté sans manifeste n'est pas une installation. Le script
-- principal porte le nom du dossier (règle de CSP). Les clés du pont gardent l'ancien préfixe « ACAdvancedIA.Bridge »
-- exprès (protocole figé, src/bridge_layout.lua) : ne pas les renommer.
-- Dossiers possibles d'AdvancedIA (nouveau nom d'abord) : une seule liste, celle de la mise à jour (src/update.lua).
M.aaiFolders=require('src/update').companion.folders
-- Texte cherché dans le script principal d'AdvancedIA (pont chargé). Écrit en deux morceaux : le contrôle des paquets de
-- la mise à jour (src/update.lua, M.requires) prend tout require('src/…') écrit en clair pour un module à livrer.
local AAI_BRIDGE_REQUIRE="require('src/".."bridge')"
function M.detect()
 local root=M.luaAppsDir()
 local installed=false; local hasBridge=false; local release=''; local folder=nil
 pcall(function()
  for _,name in ipairs(M.aaiFolders) do
   local dir=root..'/'..name
   if io.fileExists(dir..'/manifest.ini') then
    installed=true; folder=name
    -- Pont présent seulement s'il est chargé par le script principal (fichiers seuls : version sans raccordement).
    local main=io.load(dir..'/'..name..'.lua','')
    hasBridge=io.fileExists(dir..'/src/bridge.lua') and io.fileExists(dir..'/src/bridge_layout.lua')
     and type(main)=='string' and main:find(AAI_BRIDGE_REQUIRE,1,true)~=nil
    local text=io.load(dir..'/manifest.ini','')
    release=type(text)=='string' and (text:match('\nVERSION%s*=%s*([^\r\n]+)') or text:match('^VERSION%s*=%s*([^\r\n]+)')) or ''
    return
   end
  end
 end)
 return installed,hasBridge,release,folder
end
-- Structures du pont : constructeur identique à Applier.bridgeOpen d'AdvancedIA (même format, mêmes clés).
local function item(f)
 local S=ac.StructItem; local kind=f[2]
 if kind=='bool' then return S.boolean() elseif kind=='int' then return S.int32() elseif kind=='uint' then return S.uint32()
 elseif kind=='float' then return S.float() elseif kind=='double' then return S.double() elseif kind=='string' then return S.string(f[3]) end
 error('pont: type inconnu '..tostring(kind),0)
end
local function struct(key,list)
 local t={}
 if key then t.key=ac.StructItem.key(key) end
 for k=1,#list do t[list[k][1]]=item(list[k]) end
 return t
end
function M.bridgeOpen()
 if not callable(ac.connect) or type(ac.StructItem)~='table' then return nil,nil,'ac.connect absent' end
 local ok,a,b=pcall(function()
  local hello=ac.connect(struct(Layout.helloKey,Layout.hello))
  local data=struct(Layout.dataKey,Layout.fields)
  data.cars=ac.StructItem.array(ac.StructItem.struct(struct(nil,Layout.car)),Layout.maxCars)
  return hello,ac.connect(data)
 end)
 if ok then return a,b,nil end
 return nil,nil,tostring(a)
end
-- Clips présents : ensemble des chemins relatifs « FR/01_vert.wav », « FR/num/07.wav », « FR/pos/07.wav » (langues et
-- sous-dossiers du catalogue).
function M.voiceFiles(root)
 local set,count={},0
 for _,lang in ipairs(Catalog.languages) do
  for _,sub in ipairs(Catalog.subfolders) do
   pcall(io.scanDir,root..'/'..lang..'/'..sub,'*',function(name,attr)
    if name and not (attr and attr.isDirectory) and (name:lower():match('%.wav$') or name:lower():match('%.mp3$') or name:lower():match('%.ogg$')) then
     set[lang..'/'..sub..name]=true; count=count+1
    end
   end)
  end
 end
 return set,count
end
-- Lecture d'un clip : événement audio créé pour un passage (il devient invalide après), à niveau constant quelle que
-- soit la caméra, sur le canal principal du jeu. Renvoie l'événement ou nil.
function M.play(path,volume)
 if not ac.AudioEvent or not callable(ac.AudioEvent.fromFile) then return nil end
 local ok,ev=pcall(ac.AudioEvent.fromFile,{filename=path,use3D=false,loop=false},false)
 if not ok or not ev then return nil end
 local started=pcall(function()
  ev.cameraInteriorMultiplier=1; ev.cameraExteriorMultiplier=1; ev.cameraTrackMultiplier=1; ev.volume=volume or 1
  if ev.setVolumeChannel and ac.AudioChannel then ev:setVolumeChannel(ac.AudioChannel.Main) end
  ev:start()
 end)
 if not started then pcall(function() ev:dispose() end); return nil end
 return {ev=ev,at=M.clock()}
end
local function isPlaying(ev) return ev:isPlaying() end
function M.playing(h)
 if not h or not h.ev then return false end
 local ok,p=pcall(isPlaying,h.ev)
 -- Juste après start(), FMOD peut ne pas encore dire « en lecture » : 0,3 s de grâce, seulement tant que la lecture
 -- n'a pas été vue (un clip plus court, comme le signal radio de 0,13 s, n'attend pas la fin de la grâce).
 if ok and p then h.seen=true; return true end
 return not h.seen and M.clock()-h.at<0.3
end
function M.stop(h) if h and h.ev then pcall(function() h.ev:stop() end); pcall(function() h.ev:dispose() end); h.ev=nil end end
-- Son de la voiture du joueur baissé pendant la radio : multiplicateur propre à la voiture (ac.setAudioVolume avec un
-- indice de voiture, jamais sauvegardé par CSP : tout revient à la normale au lancement suivant). Les niveaux d'origine
-- sont relus au début de l'atténuation et rendus à la fin (une autre app peut les avoir réglés).
local DUCK={'engine','transmission','tyres','wind','surfaces','dirt'}
local ducked={car=-1,orig={}}
function M.duckCar(index,level)
 if not callable(ac.setAudioVolume) or not index or index<0 then return false end
 if ducked.car~=index then
  if ducked.car>=0 then for _,ch in ipairs(DUCK) do pcall(ac.setAudioVolume,ch,ducked.orig[ch] or 1,ducked.car) end end
  ducked.car=-1
 end
 if level>=0.999 then
  if ducked.car>=0 then for _,ch in ipairs(DUCK) do pcall(ac.setAudioVolume,ch,ducked.orig[ch] or 1,ducked.car) end; ducked.car=-1 end
  return true
 end
 if ducked.car<0 then
  ducked.car=index
  for _,ch in ipairs(DUCK) do
   local ok,v=pcall(ac.getAudioVolume,ch,index,1)
   ducked.orig[ch]=ok and type(v)=='number' and v>=0 and v or 1
  end
 end
 for _,ch in ipairs(DUCK) do pcall(ac.setAudioVolume,ch,(ducked.orig[ch] or 1)*level,index) end
 return true
end
-- Journal de session sur disque (Documents/Assetto Corsa/logs/SpotterEnginer.log), comme celui d'AdvancedIA : un
-- fichier par lancement du jeu, trois précédents gardés (SpotterEnginer.1.log à .3.log) ; un rechargement de l'app
-- dans le même lancement (repère ac.store) poursuit le même fichier. Une ligne = ouverture, ajout, fermeture ; 2 Mo
-- au plus par lancement ; après trois échecs d'écriture, le journal se coupe sans gêner l'app.
local journal={path=nil,bytes=0,failures=0,max=2*1024*1024,keep=3,marker='SpotterEnginer.journal'}
-- Mémoire de la partie (ac.store : gardée au rechargement de l'app, vidée à la relance du jeu), lue par d'autres apps.
function M.store(key,text) if callable(ac.store) then pcall(ac.store,key,text) end end
function M.journalOpen()
 journal.path=nil; journal.bytes=0; journal.failures=0
 local continued=false
 local ok=pcall(function()
  if not io or type(io.open)~='function' or not ac.getFolder or not ac.FolderID or not ac.FolderID.Logs then return end
  local root=ac.getFolder(ac.FolderID.Logs)
  if type(root)~='string' or root=='' then return end
  local base=root:gsub('\\','/')..'/SpotterEnginer'
  local mark=callable(ac.load) and ac.load(journal.marker) or nil
  continued=mark=='1' and type(io.fileExists)=='function' and io.fileExists(base..'.log')==true
  if not continued and type(io.fileExists)=='function' and type(io.move)=='function' then
   for n=journal.keep-1,1,-1 do local from=base..'.'..n..'.log'; if io.fileExists(from) then io.move(from,base..'.'..(n+1)..'.log',true) end end
   if io.fileExists(base..'.log') then io.move(base..'.log',base..'.1.log',true) end
  end
  local f=io.open(base..'.log',continued and 'a' or 'w'); if not f then return end
  if continued and f.seek then journal.bytes=tonumber(f:seek('end')) or 0 end
  f:close(); journal.path=base..'.log'
  if callable(ac.store) then ac.store(journal.marker,'1') end
 end)
 return ok and journal.path~=nil,continued
end
function M.journalWrite(text)
 if not journal.path or type(text)~='string' or text=='' then return false end
 local full=journal.bytes+#text>journal.max
 if full then text='=== journal limité à '..journal.max..' octets pour ce lancement ===\n' end
 local ok=pcall(function() local f=io.open(journal.path,'a'); f:write(text); f:close() end)
 if ok then journal.bytes=journal.bytes+#text else journal.failures=journal.failures+1 end
 if full or journal.failures>=3 then journal.path=nil end
 return ok
end
function M.clockText()
 if not os or type(os.date)~='function' then return '----------' end
 local ok,text=pcall(os.date,'%Y-%m-%d %H:%M:%S')
 return ok and type(text)=='string' and text or '----------'
end
-- Version de l'app (manifeste), ou « ? ».
function M.ownVersion()
 local ok,text=pcall(io.load,M.appDir():gsub('\\','/')..'/manifest.ini','')
 local v=ok and type(text)=='string' and (text:match('\nVERSION%s*=%s*([^\r\n]+)') or text:match('^VERSION%s*=%s*([^\r\n]+)')) or nil
 return v or '?'
end
function M.onRelease(fn) if callable(ac.onRelease) then pcall(ac.onRelease,fn) end end
-- Réglages persistants (une chaîne JSON).
local storage=nil
function M.loadSettings()
 local ok,s=pcall(ac.storage,{settings=''},'spe:')
 if ok and s then storage=s; local okp,data=pcall(JSON.parse,s.settings); if okp and type(data)=='table' then return data end end
 return {}
end
function M.saveSettings(t) if storage then pcall(function() storage.settings=JSON.stringify(t) end) end end
-- Simulation et voitures, dans F (réutilisée).
local names={}
local dims={}
local wetTypes={[0]=true,true,true,true,true,true,true,true,true,true,true,true,true,true,true}
function M.newFrame()
 local F={cars={},me={tyres={{},{},{},{}},brakes={0,0,0,0},damage={0,0,0,0,0}},count=0,player=-1,valid=false,clock=0}
 for i=0,Layout.maxCars-1 do F.cars[i]={index=i,valid=false,name='',x=0,z=0,lookX=0,lookZ=1,kmh=0,spline=0,laps=0} end
 return F
end
function M.forgetNames() names={}; dims={} end
-- Roues et dégâts de la voiture du joueur : fonctions de module appelées par pcall (aucune fermeture par image).
local function readDamage(me,car) for k=0,4 do me.damage[k+1]=num(car.damage[k]) end end
local function readWheels(me,car)
 for k=0,3 do
  local w=car.wheels[k]; local t=me.tyres[k+1]
  t.core=num(w.tyreCoreTemperature); t.inner=num(w.tyreInsideTemperature); t.mid=num(w.tyreMiddleTemperature)
  t.outer=num(w.tyreOutsideTemperature); t.opt=num(w.tyreOptimumTemperature,80); t.pressure=num(w.tyrePressure)
  t.wear=num(w.tyreWear); t.vkm=num(w.tyreVirtualKM); t.grain=num(w.tyreGrain); t.blister=num(w.tyreBlister)
  t.flat=num(w.tyreFlatSpot); t.blown=w.isBlown==true; t.dirty=num(w.tyreDirty)
  local disc=num(w.discTemperature); me.brakes[k+1]=disc>0 and disc or num(w.brakeTemperature)
 end
end
function M.read(F,dt)
 local okSim,sim=pcall(ac.getSim)
 if not okSim or not sim then F.valid=false; return false end
 F.valid=true
 F.paused=sim.isPaused==true; F.replay=sim.isReplayActive==true; F.online=sim.isOnlineRace==true
 if not F.paused and not F.replay and dt>0 and dt<1 then F.clock=F.clock+dt end
 F.dt=dt
 F.session=num(sim.currentSessionIndex,-1); F.sessionType=num(sim.raceSessionType,-1)
 F.timed=sim.isTimedRace==true; F.timeLeft=num(sim.sessionTimeLeft)/1000; F.leaderLaps=num(sim.leaderLapCount)
 F.fuelRate=num(sim.fuelConsumptionRate,1)
 F.trackLength=num(sim.trackLengthM,5000); F.pitSpeed=num(sim.pitsSpeedLimit,80)
 F.ambient=num(sim.ambientTemperature,20); F.road=num(sim.roadTemperature,25); F.grip=num(sim.roadGrip,1)
 F.rain=num(sim.rainIntensity); F.wetness=num(sim.rainWetness); F.water=num(sim.rainWater)
 F.windKmh=num(sim.windSpeedKmh); F.windDir=num(sim.windDirectionDeg)
 -- Vent dans le repère du jeu (x, z) : composante dans l'axe de la voiture = vent arrière (> 0) ou de face (< 0).
 local wv=sim.windVelocityKmh
 if wv then F.windX=num(wv.x); F.windZ=num(wv.y) else F.windX=0; F.windZ=0 end
 F.allowedOut=num(sim.allowedTyresOut,2); F.started=sim.isSessionStarted~=false; F.finishedSession=sim.isSessionFinished==true
 local wc=sim.weatherConditions
 if wc then F.weatherNow=num(wc.currentType,-1); F.weatherNext=num(wc.upcomingType,-1); F.transition=num(wc.transition) else F.weatherNow=-1; F.weatherNext=-1; F.transition=0 end
 F.rainComing=F.weatherNext>=0 and wetTypes[F.weatherNext]==true and not (F.weatherNow>=0 and wetTypes[F.weatherNow]==true)
 local okS,session=pcall(ac.getSession,F.session)
 if okS and session then F.laps=num(session.laps); F.additional=session.hasAdditionalLap==true; F.timed=F.timed or session.isTimedRace==true; F.isRace=num(session.type)==3
 else F.laps=0; F.isRace=F.sessionType==3 end
 local count=math.min(num(sim.carsCount),Layout.maxCars)
 F.count=count; F.player=-1
 for i=0,Layout.maxCars-1 do
  local c=F.cars[i]
  local ok,car=false,nil
  if i<count then ok,car=pcall(ac.getCar,i) end
  if ok and car then
   c.valid=car.isConnected~=false and car.isActive~=false
   local p=car.position; c.x=p.x; c.y=p.y; c.z=p.z
   local l=car.look; c.lookX=l.x; c.lookZ=l.z
   c.kmh=num(car.speedKmh); c.spline=num(car.splinePosition); c.laps=num(car.lapCount)
   c.position=num(car.racePosition); c.pitlane=car.isInPitlane==true; c.inPit=car.isInPit==true
   c.lapMs=num(car.lapTimeMs); c.lastMs=num(car.previousLapTimeMs); c.bestMs=num(car.bestLapTimeMs)
   c.ai=car.isAIControlled==true; c.retired=car.isRetired==true; c.finished=car.isRaceFinished==true
   c.flashing=car.flashingLightsActive==true; c.user=car.isUserControlled==true
   -- Dimensions et nom lus une fois par voiture et par session.
   local dim=dims[i]; if not dim then local a=car.aabbSize; dim={a and num(a.z,4.6) or 4.6,a and num(a.x,1.9) or 1.9}; dims[i]=dim end
   c.len=dim[1]; c.wid=dim[2]
   if not names[i] then local okn,n=pcall(ac.getDriverName,i); names[i]=okn and type(n)=='string' and n or ('#'..(i+1)) end
   c.name=names[i]
   if c.user and F.player<0 then F.player=i end
  else c.valid=false end
 end
 if F.player<0 and count>0 then F.player=0 end
 -- Voiture du joueur : pneus, freins, carburant, dégâts, aides.
 local okMe,car=pcall(ac.getCar,math.max(0,F.player))
 local me=F.me
 if okMe and car then
  me.fuel=num(car.fuel); me.maxFuel=num(car.maxFuel,me.maxFuel or 100); me.fuelPerLapAC=num(car.fuelPerLap)
  me.fuelMap=num(car.fuelMap); me.fuelMaps=num(car.fuelMaps)
  me.brakeBias=num(car.brakeBias); me.hasBias=car.hasUserBrakeBias==true; me.compound=num(car.compoundIndex)
  me.kmh=num(car.speedKmh); me.gas=num(car.gas); me.brake=num(car.brake); me.gear=num(car.gear)
  me.drsPresent=car.drsPresent==true; me.drsAvailable=car.drsAvailable==true; me.drsActive=car.drsActive==true
  me.kers=car.kersPresent==true; me.kersCharge=num(car.kersCharge); me.p2p=num(car.p2pStatus); me.p2pLeft=num(car.p2pActivations)
  me.wheelsOut=num(car.wheelsOutside); me.lapValid=car.isLapValid~=false; me.cuts=num(car.lapCutsCount)
  me.engineLife=num(car.engineLifeLeft,1000); me.gearbox=num(car.gearboxDamage); me.lapMs=num(car.lapTimeMs)
  me.sector=num(car.currentSector); me.penalty=num(car.currentPenaltyType)
  local l=car.look; me.lookX=l.x; me.lookZ=l.z
  local okd=pcall(readDamage,me,car)
  if not okd then for k=1,5 do me.damage[k]=0 end end
  pcall(readWheels,me,car)
 end
 return true
end
-- Données de la voiture (lues une fois par voiture et composé) : courbes d'usure avant/arrière du composé monté,
-- réservoir, temps de changement des pneus et de ravitaillement (car.ini [PIT_STOP]).
local function lutFrom(index,value)
 if type(value)~='string' or value=='' then return nil end
 local inline=Strategy.parseLut(value)
 if inline then return inline end
 local name=value:match('^[ \t\r\n]*(.-)[ \t\r\n]*$') -- espaces ASCII seulement (UTF-8 intact)
 local okL,handle=pcall(ac.DataLUT11.carData,index,name)
 if okL and handle then
  local xs,ys={},{}
  for i=0,255 do
   local okx,x=pcall(function() return handle:getPointInput(i) end)
   local oky,y=pcall(function() return handle:getPointOutput(i) end)
   if not okx or not oky or type(x)~='number' or type(y)~='number' or x~=x or y~=y then break end
   if i>0 and x<=xs[#xs] then break end
   xs[#xs+1]=x; ys[#ys+1]=y
  end
  if #xs>=2 then return Strategy.lut(xs,ys) end
 end
 local id=callable(ac.getCarID) and ac.getCarID(index) or nil
 if type(id)~='string' then return nil end
 local okR,text=pcall(ac.readDataFile,'content/cars/'..id..'/data/'..name)
 if okR and type(text)=='string' then return Strategy.parseLut(text) end
 return nil
end
local function iniGet(cfg,section,key)
 if not cfg then return nil end
 local ok,v=pcall(function() return cfg:get(section,key,'') end)
 if ok and type(v)=='string' and v~='' then return v end
 return nil
end
function M.carData(index,compound)
 local out={curves={},tank=nil,tyreChange=nil,fuelRate=nil,source=''}
 local okT,tyres=pcall(ac.INIConfig.carData,index,'tyres.ini')
 if okT and tyres then
  local suffix=compound and compound>0 and ('_'..math.floor(compound)) or ''
  out.curves.F=lutFrom(index,iniGet(tyres,'FRONT'..suffix,'WEAR_CURVE'))
  out.curves.R=lutFrom(index,iniGet(tyres,'REAR'..suffix,'WEAR_CURVE'))
  out.compoundName=iniGet(tyres,'FRONT'..suffix,'SHORT_NAME') or iniGet(tyres,'FRONT'..suffix,'NAME')
 end
 local okC,car=pcall(ac.INIConfig.carData,index,'car.ini')
 if okC and car then
  out.tank=tonumber(iniGet(car,'FUEL','MAX_FUEL') or '')
  out.tyreChange=tonumber(iniGet(car,'PIT_STOP','TYRE_CHANGE_TIME_SEC') or '')
  out.fuelRate=tonumber(iniGet(car,'PIT_STOP','FUEL_LITER_TIME_SEC') or '')
 end
 out.source=(out.curves.F or out.curves.R) and 'wear' or 'linear'
 return out
end
-- Position latérale sur la piste (-1 à gauche, +1 à droite) d'un point du monde, ou nil.
local probe=nil
function M.trackLateral(x,y,z)
 if not callable(ac.worldCoordinateToTrack) then return nil end
 if not probe then probe=vec3(x,y,z) else probe.x=x; probe.y=y; probe.z=z end
 local ok,v=pcall(ac.worldCoordinateToTrack,probe)
 if ok and v and type(v.x)=='number' then return v.x end
 return nil
end
-- Nom du secteur (sections.ini du circuit) à une position du tour, ou ''.
function M.sectorName(progress)
 if not callable(ac.getTrackSectorName) then return '' end
 local ok,n=pcall(ac.getTrackSectorName,progress)
 return ok and type(n)=='string' and n or ''
end
return M
