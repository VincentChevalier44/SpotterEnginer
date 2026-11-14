-- SpotterEnginer : spotter et ingénieur de course à la voix (français / anglais), adossés à AdvancedIA.
-- Sans AdvancedIA connecté et en marche (pont src/bridge_layout.lua), l'app ne dit rien : elle affiche seulement
-- l'état de la liaison. Une image : lecture de CSP (src/port.lua) -> liaison -> chronométrage -> spotter et ingénieur
-- (modules purs, chacun protégé) -> radio. Fenêtres : réglages (SPE__MAIN) et trois overlays (Spotter, Ingénieur,
-- Stratégie).
-- Reprise d'une mise à jour interrompue (module repris d'AdvancedIA), avant tout autre module : une copie arrêtée au
-- milieu (plantage, coupure) aurait pu laisser des modules de deux versions ; elle est terminée ou défaite ici, de façon
-- synchrone, avant que les autres modules soient chargés. Seuls les deux modules de la mise à jour sont lus d'abord,
-- chacun protégé. Contrat figé dès la 1.1.0 (lu par toutes les versions à venir, voir src/update.lua) :
-- Update.recover(port), Remote.new(onRelease), port.ready, port.work, port.restart, port.log, port.bootOk,
-- Update.recoverText.
local okUpdate,Update=pcall(require,'src/update')
local okRemote,Remote=pcall(require,'src/remote')
local onRelease
local updatePort
if okUpdate and okRemote and type(Update)=='table' and type(Remote)=='table' then
 local ok,made=pcall(Remote.new,function() if onRelease then onRelease() end end)
 if ok and type(made)=='table' then updatePort=made end
end
if not updatePort then
 -- Modules de la mise à jour illisibles : l'app se charge sans mise à jour (port inerte, état « non vérifié »).
 local function none() end
 updatePort={ready=false,work='',restart=none,log=none,bootOk=none}
 if not okUpdate or type(Update)~='table' then
  Update=setmetatable({new=function(version) return {phase='idle',installed=version,events={},serial=0,askedAt=0} end,
   view=function() return 'unchecked' end,take=function(_,out) return out end,checkGap=60,page='',status=function() return nil end},
   {__index=function() return none end})
  -- Le remplaçant est aussi celui que rend require('src/update') (interface, port) : un second require d'un module en
  -- échec lèverait « loop or previous error loading module ».
  local loaded=_G.package and _G.package.loaded
  if loaded then loaded['src/update']=Update end
 end
end
local recovered
do
 local ok,result=pcall(function() return updatePort.ready and Update.recover(updatePort) or nil end)
 -- Sans reprise, result vaut nil : jamais « ok and result or … », qui prendrait alors l'échec.
 if ok then recovered=result else recovered={outcome='failed',failed=tostring(result):sub(1,120),file=updatePort.work} end
end
-- Reprise dite tout de suite au journal de CSP : lisible même si un module ne se charge pas ensuite.
if recovered and updatePort.ready then
 local okText,level,text=pcall(Update.recoverText,recovered)
 if okText and text then pcall(updatePort.log,level..' '..text) end
end
-- Fichiers de l'app copiés à l'instant par la reprise : le code déjà chargé est celui d'une autre version. Aucun autre
-- module n'est lu ; l'app redémarre à la première image (compte rendu lu au lancement suivant).
if recovered and recovered.restart then
 local asked=false
 local function restartOnly() if not asked then asked=true; pcall(updatePort.restart) end end
 function script.update() restartOnly() end
 function script.SPE__MAIN() end
 function script.SPE__GAME() end
 function script.SPE__HUD() end
 return
end
local Port=require('src/port')
local Config=require('src/config')
local Link=require('src/link')
local Voice=require('src/voice')
local Say=require('src/say')
local Timing=require('src/timing')
local Spotter=require('src/spotter')
local Engineer=require('src/engineer')
local Emergency=require('src/emergency')
local Strategist=require('src/strategist')
local Side=require('src/side')
local SetupLab=require('src/setuplab')
local SuperHUD=require('src/superhud')
local Focus=require('src/focus')
local Spectator=require('src/spectator')
local UI=require('src/ui')
local Overlays=require('src/overlays')
local Editor=require('src/editor')
local Lang=require('src/lang')
local W=require('src/kit')
local Catalog=require('src/catalog')

local appDir=Port.appDir():gsub('\\','/')
local stored=Port.loadSettings()
local cfg=Config.load(stored)
-- Vue effective pour la logique : une section d'annonces coupée y fait taire ses options (src/config.lua).
local run=Config.effective(cfg)
-- Overlays propres à chaque bureau d'applications AC (src/config.lua, M.desktopKeys).
local desktops=Config.loadDesktops(stored.desktops,stored.schema)
local hadDesktops=type(stored.desktops)=='table'
local activeDesktop=nil
-- Fenêtre de réglages en jeu (1.3.9, comme la configuration de SuperHUD) : ouverte ou fermée, place et taille propres
-- à chaque bureau (une table par bureau, src/config.lua M.loadWindows).
local gameWins=Config.loadWindows(stored.gameWindows)
-- Réglages propres au bureau : jamais écrits quand le bureau est illisible (ils iraient dans un autre bureau).
local DESK_KEY={}; for _,k in ipairs(Config.desktopKeys) do DESK_KEY[k]=true end
Lang.set(cfg.language)
local F=Port.newFrame()
local installed,hasBridge,release=Port.detect()
local link=Link.new(installed,hasBridge,release)
local hello,data,bridgeWhy=Port.bridgeOpen()
local voice=Voice.new({play=Port.play,playing=Port.playing,stop=Port.stop,prepare=Port.prepare,start=Port.start})
local files,present=Port.voiceFiles(appDir..'/vox')
local chirpPath=appDir..'/'..Catalog.toneFile
local chirp=nil
pcall(function() if io.fileExists(chirpPath) then chirp=chirpPath end end)
-- Juste avant la copie des fichiers d'une mise à jour (src/update.lua) : radio arrêtée, clips préchargés libérés.
updatePort.beforeCopy=function() Voice.stop(voice); Port.release() end
local sayer=Say.new(voice,files,appDir..'/vox',cfg.language)
local timing=Timing.new()
local spotter=Spotter.new()
local engineer=Engineer.new()
-- Urgences du joueur (1.3.0, src/emergency.lua) : contact, dégâts, crevaison, tête-à-queue et reprise.
local emergency=Emergency.new()
local view=UI.new()
local hud=Overlays.new()
local editor=Editor.new()
local session=nil
local carPlayer,carCompound=nil,nil
local lastLaps,lastPlayer,playerSince=nil,nil,nil
local dirtyAt=nil
local errors={count=0,last='',seen={}}
-- Journal de session (src/port.lua) : lancement, réglages, liaison, séances, tours, radio (dite, écrite, coupée,
-- périmée), annonces d'AdvancedIA, erreurs, et un point d'état toutes les 10 s en course.
local journalOn,journalContinued=Port.journalOpen()
local function jlog(text)
 if not journalOn then return end
 local me=F.cars and F.cars[F.player]
 local lap=me and me.valid and tostring((me.laps or 0)+1) or '-'
 Port.journalWrite(string.format('%s %8.1f T%-3s %s\n',Port.clockText(),tonumber(F.clock) or 0,lap,tostring(text)))
end
voice.onEvent=function(kind,item,again)
 if kind=='radio' then
  jlog(string.format('radio %s p%d %s : %s (%s)',tostring(item.role),tonumber(item.prio) or 0,tostring(item.key or item.kind or ''),tostring(item.text or ''),item.spoken and 'dite' or 'écrite'))
 elseif kind=='cut' then jlog(string.format('radio coupée : %s%s',tostring(item.key),again and ', reprise ensuite' or ', abandonnée'))
 elseif kind=='expired' then jlog('radio périmée sans être dite : '..tostring(item.key))
 elseif kind=='repeat' then jlog('radio non redite (déjà entendue) : '..tostring(item.key)) end
end
local app={cfg=cfg,run=run,link=link,voice=voice,F=F,timing=timing,spotter=spotter,engineer=engineer,fontDir=Port.fontDir(),logo=Port.appFile('icon.png'),
 has={setuplab=SetupLab.installed(Port.setupLabManifest()),superhud=SuperHUD.installed(Port.superhudManifest())},superhud=SuperHUD.new(),focus=Focus.new(),spectator=Spectator.new(),version=Port.ownVersion(),updater=nil,updatePort=updatePort,updateStopped=false,voicePresent=present,voiceTotal=Catalog.fileCount(),now=0,real=0,errors=errors,bridgeWhy=bridgeWhy}
-- Horloge de la radio (app.radioNow, ctx.real, Voice.step) : le temps réel sans les pauses du jeu. En pause, les délais
-- de la radio (validité, délai par clé, rythme, redite) ne s'écoulent pas ; la phrase en cours finit, et l'essai de la
-- voix (priorité 1) part quand même.
local pausedFor,lastReal=0,nil
local function radioClock()
 local real=Port.clock()
 if lastReal and F.paused and real>lastReal then pausedFor=pausedFor+(real-lastReal) end
 lastReal=real; app.radioNow=real-pausedFor
end
radioClock()
-- Polices du kit dès le chargement : les overlays en ont besoin même si la fenêtre de réglages n'est jamais ouverte.
W.setFonts(app.fontDir)
-- Tests hors du jeu (tests/integration_spec.lua) : accès à l'état de l'app ; absent en jeu.
do local hook=rawget(_G,'SPE_TEST'); if type(hook)=='table' then hook.app=app end end

-- Réglages appliqués à la radio (volumes, rôles, langue, signal radio).
local warmLang=nil
-- Annonces en attente écartées par un réglage : rôle coupé (les siennes), langue changée (toutes : clips et textes de
-- l'autre langue) ; la phrase en cours finit.
local function ofSilentRole(q) return q.role=='spotter' and not cfg.spotterOn or q.role=='engineer' and not cfg.engineerOn end
local function anyCall() return true end
local function apply()
 Config.effective(cfg,run)
 voice.volume=cfg.enabled and cfg.volume or 0
 if voice.spotterOn and not cfg.spotterOn or voice.engineerOn and not cfg.engineerOn then Voice.purge(voice,ofSilentRole) end
 voice.spotterOn=cfg.spotterOn; voice.engineerOn=cfg.engineerOn
 voice.spotterVolume=cfg.spotterVolume; voice.engineerVolume=cfg.engineerVolume
 voice.muted=not cfg.enabled or app.radioMuted==true
 if sayer.lang~=cfg.language then Voice.purge(voice,anyCall) end
 Say.setLanguage(sayer,cfg.language)
 sayer.chirp=cfg.chirp and chirp or nil
 -- Clips de sécurité de la langue préchargés (radio instantanée, src/port.lua) : au lancement et au changement de
 -- langue seulement (jamais à chaque réglage déplacé).
 if warmLang~=sayer.lang then
  warmLang=sayer.lang
  local hot={}
  for _,id in ipairs(Catalog.hot) do local c=Catalog.clips[id]; local rel=sayer.lang..'/'..c[sayer.lang]; if files[rel] then hot[#hot+1]=appDir..'/vox/'..rel end end
  if chirp then hot[#hot+1]=chirp end
  Port.warm(hot)
 end
 -- Formulations variées (1.3.0, src/say.lua : variantes selon le ton).
 sayer.vary=cfg.variety~=false
 voice.infoGap=cfg.infoGap; voice.repeatGap=cfg.repeatGap
 Lang.set(cfg.language)
end
apply()
jlog(string.format('=== SpotterEnginer %s : %s ===',app.version,journalContinued and "rechargement de l'app" or 'lancement'))
jlog(string.format('réglages : langue %s, app %s, volume %d %%, voiture pendant la radio %s, spotter %s, ingénieur %s, stratégie %s, direction de course %s, côte à côte %s',
 tostring(cfg.language),cfg.enabled and 'active' or 'coupée',math.floor((cfg.volume or 0)*100+0.5),cfg.duck and math.floor((cfg.duckLevel or 1)*100+0.5)..' %' or 'non baissée',
 cfg.spotterOn and 'oui' or 'non',cfg.engineerOn and 'oui' or 'non',cfg.strategyOn and 'oui' or 'non',cfg.raceControl and 'oui' or 'non',cfg.sideBySide and 'oui' or 'non'))
jlog(string.format('voix : %d clips ; AdvancedIA %s ; pont %s',present or 0,installed and (release~='' and release or 'installé') or 'absent',
 hello and 'ouvert' or 'indisponible ('..tostring(bridgeWhy)..')'))
app.screen=Port.screen
app.clock=Port.clock
-- Mise à jour depuis GitHub (module repris d'AdvancedIA) : vérification une fois par lancement (UPDATE_DELAY s après le
-- chargement, réglage « Vérifier au lancement »), installation d'un clic à l'arrêt, retour arrière. Avant le redémarrage
-- de l'app : événements versés au journal, radio arrêtée, son de la voiture rendu, réglages enregistrés. Hors du jeu
-- (tests), le port est inerte et rien ne change. État publié pour AdvancedIA (ac.store, Update.status).
local UPDATE_DELAY,BOOT_FRAMES,BOOT_DRAWS=10,10,3
-- Vérification de lancement : pas de nouvelle interrogation de GitHub à chaque rechargement à chaud de l'app. L'heure
-- de la dernière (heure du système, mémoire de la partie) la repousse à UPDATE_AGAIN s après elle ; le bouton
-- « Vérifier » n'est pas concerné.
local UPDATE_AGAIN,UPDATE_KEY=600,'SpotterEnginer.updateChecked'
local updateDue=nil
local updater=Update.new(Update.label and Update.label(app.version) or app.version)
app.updater=updater
local updateEvents={}
local function updateLog()
 Update.take(updater,updateEvents)
 for i=1,#updateEvents do local ev=updateEvents[i]; jlog(ev[1]..' '..ev[2]); updateEvents[i]=nil end
end
local saveNow
onRelease=function()
 updateLog(); Voice.stop(voice); Port.duckCar(F.player,1)
 if saveNow then pcall(saveNow) end
end
-- Annonces entendues gardées au rechargement à chaud de l'app (src/voice.lua, heardText) : l'ingénieur ne redit pas
-- ce qu'il vient de dire (« usure anormale » redite cinq fois le 05/11/2026). Portée de la séance (Port.keep).
voice.onHeard=function(item)
 if item.role=='engineer' then Port.keep.store('heard',Voice.heardText(voice,app.radioNow)) end
end
if updatePort.ready then Update.start(updater,updatePort,recovered) end
updateLog()
local updateStart=Port.clock()
local updateAsked,booted,bootFrames,bootDraws=false,false,0,0
local statusText=nil
-- Plan d'arrêt publié pour AdvancedIA (Strategist.pitplan, contrat v1) : dernier texte écrit.
local pitplanText=nil
local duelText=nil
-- Actions de la fenêtre (src/ui.lua) : vérifier, installer, annuler, revenir à la version précédente, notes.
function app.updateAct(action)
 local now=Port.clock()
 if action=='install' then Update.install(updater,updatePort,app.updateStopped)
 elseif action=='cancel' then Update.cancel(updater)
 elseif action=='check' then Update.check(updater,updatePort,now)
 elseif action=='rollback' then Update.rollback(updater,updatePort,app.updateStopped)
 elseif action=='notes' then updatePort.open(updater.release and updater.release.page or Update.page) end
 updateLog()
end
local function updateTick()
 if not updatePort.ready then return end
 local now=Port.clock()
 local me=F.cars and F.cars[F.player]
 app.updateStopped=Update.stopped(F,me)
 Update.tick(updater,updatePort,app.updateStopped,now)
 if not updateAsked and cfg.updateCheck and now-updateStart>=UPDATE_DELAY and updater.phase=='idle' then
  if not updateDue then
   local wall=Port.wallClock(); local last=tonumber(Port.recall(UPDATE_KEY))
   updateDue=last and wall>=last and wall-last<UPDATE_AGAIN and now+UPDATE_AGAIN-(wall-last) or now
  end
  if now>=updateDue then updateAsked=true; Port.store(UPDATE_KEY,Port.wallClock()); Update.check(updater,updatePort,now) end
 end
 -- Démarrage confirmé (images et dessins de la fenêtre ou des overlays) : surveillance levée, restes effacés.
 if not booted and bootFrames>=BOOT_FRAMES and bootDraws>=BOOT_DRAWS then booted=true; pcall(updatePort.bootOk); pcall(Update.tidy,updater,updatePort) end
 -- État pour l'accueil d'AdvancedIA (contrat v1) : écrit à chaque changement.
 local text=Update.status(updater,app.updateStopped)
 if text and text~=statusText then statusText=text; Port.store(Update.statusKey,text) end
 updateLog()
end
-- Actions des overlays (fenêtre de réglages et raccourcis).
function app.recenter(o) app.set(o..'X',-1); app.set(o..'Y',-1); app.set(o..'Scale',1) end
function app.lockAll(locked) for _,o in ipairs(Config.overlays) do app.set(o..'Locked',locked) end end
-- Édition en jeu (src/editor.lua) : ouverte ou fermée (fermée : tout verrouillé) ; état de la session, jamais enregistré.
function app.toggleEditor() Editor.toggle(app) end
function app.backgrounds(mode)
 for _,o in ipairs(Config.overlays) do app.set(o..'Background',mode); if mode=='transparent' then app.set(o..'Accent',false) else app.set(o..'Accent',true) end end
end
-- Radio coupée (bouton ou Ctrl+Alt+M), pour la session seulement.
function app.toggleMute() voice.muted=not voice.muted; app.radioMuted=voice.muted; if voice.muted then Voice.stop(voice) end end
-- Tous les réglages à leur valeur par défaut, la langue gardée.
function app.resetAll() local lang=cfg.language; for _,s in ipairs(Config.schema) do cfg[s[1]]=s[2] end; cfg.language=lang; apply(); if app.remember then app.remember() end; dirtyAt=Port.clock() end
function app.allLocked() for _,o in ipairs(Config.overlays) do if not cfg[o..'Locked'] then return false end end return true end
-- Bureau quitté : ses réglages d'overlays gardés ; bureau rejoint : les siens, ou un bureau vide. Au tout premier
-- passage (réglages d'avant les bureaux), le bureau courant garde la configuration existante, comme SuperHUD.
local function rememberDesktop()
 if not activeDesktop then return end
 local t={}; for _,k in ipairs(Config.desktopKeys) do t[k]=cfg[k] end
 desktops[activeDesktop]=t
end
-- fromGame : appelé par la fenêtre de réglages en jeu (elle est donc ouverte sur le bureau rejoint).
local function syncDesktop(fromGame)
 local d=Port.desktop()
 app.desktopAvailable=d~=nil
 -- Bureau illisible (comme SuperHUD) : overlays et réglages d'overlays suspendus, pour ne jamais modifier un autre
 -- bureau ; le bureau actif est gardé pour le retour.
 if not d then return false end
 if d==activeDesktop then return true end
 local first=activeDesktop==nil
 rememberDesktop()
 local page=desktops[d]
 if not page and (activeDesktop or hadDesktops) then page=Config.emptyDesktop() end
 if page then for _,k in ipairs(Config.desktopKeys) do cfg[k]=page[k] end end
 activeDesktop=d; app.desktop=d
 Config.effective(cfg,run)
 rememberDesktop(); dirtyAt=dirtyAt or Port.clock()
 -- Fenêtre de réglages en jeu du bureau rejoint (comme SuperHUD) : sa place, sa taille et son état ; un bureau jamais
 -- vu la garde fermée, sauf si c'est elle qui dessine. Au premier bureau lu, seul un état enregistré est remis.
 local st=gameWins[d]
 if not st and not first then st={open=fromGame==true}; gameWins[d]=st end
 if st then
  if fromGame then st.open=true end
  Port.applyWindow(st,Port.screen())
 end
 return true
end
-- Fenêtre de réglages en jeu : état ouvert ou fermé relevé à chaque image (update), place et taille seulement dans
-- son propre rappel (après un changement de bureau, CSP peut déjà donner celles du bureau rejoint).
local function captureWindow(geometry)
 if not activeDesktop or not app.desktopAvailable then return end
 local now=Port.windowState(geometry)
 if not now then return end
 local st=gameWins[activeDesktop] or {}
 local changed=st.open~=now.open
 st.open=now.open
 if geometry and now.x then
  if st.x~=now.x or st.y~=now.y or st.w~=now.w or st.h~=now.h then changed=true end
  st.x,st.y,st.w,st.h=now.x,now.y,now.w,now.h
 end
 gameWins[activeDesktop]=st
 if changed then dirtyAt=dirtyAt or Port.clock() end
end
app.syncDesktop=syncDesktop
app.remember=rememberDesktop
-- Nombre d'overlays affichés sur chaque bureau (page Overlays).
-- Le bureau courant est compté sur les réglages en cours (sans recopie), les autres sur leur page ; table réutilisée.
local SHOW={}; for i,o in ipairs(Config.overlays) do SHOW[i]=o..'Show' end
local counts={}
function app.desktopCounts()
 for d=1,Config.desktopCount do
  local page=d==activeDesktop and cfg or desktops[d]
  if page then local n=0; for i=1,#SHOW do if page[SHOW[i]] then n=n+1 end end; counts[d]=n else counts[d]=-1 end
 end
 return counts
end
-- Copier les overlays de ce bureau vers les autres ; vider ce bureau.
function app.copyDesktopToAll() if app.desktopAvailable==false then return end; rememberDesktop(); for d=1,Config.desktopCount do if d~=activeDesktop then local t={}; for k,v in pairs(desktops[activeDesktop]) do t[k]=v end; desktops[d]=t end end; dirtyAt=Port.clock() end
function app.clearDesktop() if app.desktopAvailable==false then return end; local t=Config.emptyDesktop(); for _,k in ipairs(Config.desktopKeys) do cfg[k]=t[k] end; rememberDesktop(); dirtyAt=Port.clock() end
function app.set(key,value)
 if DESK_KEY[key] and app.desktopAvailable==false then return end
 local v=Config.valid(key,value)
 -- Valeur inchangée (glisser d'un overlay, curseur immobile) : rien à appliquer ni à enregistrer.
 if v==nil or cfg[key]==v then return end
 cfg[key]=v; apply(); dirtyAt=Port.clock()
end
-- Essai de la voix : un clip livré de chaque rôle.
function app.test(role)
 local parts=role=='spotter' and {'green'} or {'pitOpen'}
 Say.say(sayer,role,'test:'..role,1,parts,app.radioNow,{ttl=5})
end
-- Erreur d'un module : comptée, écrite une fois par message dans le journal de CSP, jamais d'arrêt de l'app.
local function protected(fn,...)
 local ok,err=pcall(fn,...)
 if not ok then
  errors.count=errors.count+1
  local text=tostring(err):sub(1,200)
  errors.last=text
  if not errors.seen[text] then errors.seen[text]=true; pcall(ac.log,'SpotterEnginer: '..text); jlog('ERREUR : '..text) end
 end
 return ok
end
-- Son de la voiture baissé pendant la radio : descente rapide (0,12 s), remontée en 0,4 s ; rendu au déchargement.
local duck={level=1,applied=1,car=-1,busyAt=-1e9}
app.duckLevel=function() return duck.level end
local function duckStep(dt)
 local want=1
 local now=Port.clock()
 -- Radio qui parle ou message en attente : tenu baissé jusqu'à 0,6 s après le dernier (aucune remontée entre deux
 -- messages rapprochés, « à gauche… toujours là… dégagé »).
 if Voice.busy(voice) or Voice.urgentWaiting(voice) then duck.busyAt=now end
 if cfg.enabled and cfg.duck and now-duck.busyAt<0.6 then want=cfg.duckLevel end
 local step=math.max(0,math.min(0.1,dt or 0))*(want<duck.level and 8 or 2.5)
 if duck.level<want then duck.level=math.min(want,duck.level+step) else duck.level=math.max(want,duck.level-step) end
 if math.abs(duck.level-duck.applied)>0.01 or duck.level==1 and duck.applied~=1 or F.player~=duck.car then
  if Port.duckCar(F.player,duck.level) then duck.applied=duck.level; duck.car=F.player end
 end
end
-- Déchargement de l'app (rechargement à chaud, fin de la partie) : son de la voiture rendu, réglages changés depuis
-- moins d'une seconde enregistrés, journal écrit.
Port.onRelease(function() Port.duckCar(F.player,1); if dirtyAt and saveNow then pcall(saveNow) end; Port.journalFlush() end)
-- Raccourcis (Ctrl+Alt, comme SuperHUD, sans ses touches H et G) : J overlays, K édition en jeu, M radio coupée.
local previousKeys={}
local hotkeyActions={
 [0x4A]=function() app.set('overlaysOn',not cfg.overlaysOn) end,
 [0x4B]=function() app.toggleEditor() end,
 [0x4D]=function() app.toggleMute() end}
local function hotkeys()
 if not cfg.hotkeys then return end
 local modifier=Port.keyDown(0x11) and Port.keyDown(0x12)
 for key,fn in pairs(hotkeyActions) do
  local down=modifier and Port.keyDown(key)
  if down and not previousKeys[key] then fn() end
  previousKeys[key]=down
 end
end
-- ctx.real : horloge de la radio (temps réel sans les pauses). ctx.keep : mémoire gardée au rechargement à chaud de
-- l'app (keep.load(name) -> chaîne ou nil, keep.store(name,text)), propre à la séance suivie ; ctx.resumed : la remise
-- à zéro en cours suit un rechargement à chaud dans la même séance (ce qui a été gardé peut être relu).
-- Clés annexes d'AdvancedIA (1.3.5, src/side.lua : nuance des classes, météo en direct), relues deux fois par seconde.
local side=Side.new()
-- SetupLab (1.3.9, app facultative : src/setuplab.lua), clé relue deux fois par seconde quand SetupLab est installé.
local setuplab=SetupLab.new()
local shLogged={}
local slLogged=nil
local ctx={side=side,setuplab=setuplab,F=F,link=link,say=sayer,voice=voice,cfg=run,timing=timing,now=0,real=0,clock=Port.clock,sectorName=Port.sectorName,
 trackLateral=Port.trackLateral,strategist=function() return engineer.strategist end,journal=jlog,emergency=emergency,keep=Port.keep,resumed=false}
-- Journal : état de l'app, tour du joueur, point d'état périodique.
local lastActive,lapLogged,stateAt=nil,nil,-1e9
local lastSpectating=false
local LINK_GRACE=3
local linkLostAt=nil
-- Redémarrage de la même séance avant la fin du premier tour (les tours ne reculent pas) : départ donné qui redevient
-- non donné, ou temps de séance qui recule de plus de RESTART_BACK s ; lus hors pause et hors rediffusion (comparés
-- aux dernières valeurs lues en piste), jamais dans les RESTART_HOLD s qui suivent une remise à zéro.
local RESTART_BACK,RESTART_HOLD,LAPS_HOLD=2,2,5
local lastStarted,lastTime,resetAt=nil,nil,-1e9
-- Tout sauf l'essai de la voix (liaison suspendue ou perdue).
local function notTest(q) return tostring(q.key):sub(1,5)~='test:' end
local function lapText(ms) return require('src/util').lapTime((tonumber(ms) or 0)/1000) end
local function heartbeat(real)
 if real-stateAt<10 then return end
 stateAt=real
 local me=F.cars[F.player]
 if not me or not me.valid then return end
 local near=0
 for i=0,F.count-1 do
  local c=F.cars[i]
  if i~=F.player and c.valid and c.x and me.x then local dx,dz=c.x-me.x,c.z-me.z; if dx*dx+dz*dz<900 then near=near+1 end end
 end
 local p=spotter.prox or {}
 jlog(string.format('état : P%d, %.0f km/h%s, %d voiture(s) à moins de 30 m, côté %s%s, file radio %d%s',tonumber(me.position) or 0,tonumber(me.kmh) or 0,
  me.pitlane and ', voie des stands' or '',near,p.left and 'G' or '-',p.right and 'D' or '-',#voice.queue,voice.muted and ', radio coupée' or ''))
end
local function step(dt)
 local real=Port.clock()
 if not Port.read(F,dt or 0) then return end
 syncDesktop()
 -- Voiture suivie par la caméra (overlays seulement, src/focus.lua) ; réglage propre au bureau.
 Focus.step(app.focus,F,cfg.followCamera)
 if Link.step(link,hello,data,real) then
  jlog(string.format('liaison : %s%s%s',link.state,link.reason~='' and ' ('..link.reason..')' or '',link.remoteRelease~='' and ' · AdvancedIA '..link.remoteRelease or ''))
 end
 -- AdvancedIA absent, arrêté ou rechargé, ou app coupée : la référence de la direction de course est oubliée (pas
 -- de comparaison avec l'état d'une autre instance au retour). Gardée en pause (suspendu).
 -- Liaison perdue plus de LINK_GRACE s (1.3.1 : un à-coup du jeu de plus de 2,5 s rendait la liaison « perdue » une
 -- image, coupait la radio et faisait réannoncer la neutralisation en cours) : référence oubliée, radio arrêtée.
 local linkDown=link.state~='connected' and link.state~='suspended'
 if linkDown then linkLostAt=linkLostAt or real else linkLostAt=nil end
 local linkGone=linkDown and real-linkLostAt>LINK_GRACE
 if linkGone or not cfg.enabled then spotter.prev=nil end
 app.now=F.clock; app.real=real
 local radio=app.radioNow
 -- Nouvelle session, redémarrage de la session (tours du joueur revenus en arrière, départ redevenu non donné ou temps
 -- de séance qui recule) ou autre voiture pilotée : chronométrage, spotter, ingénieur et radio repartent de zéro.
 -- Rediffusion : rien n'y est comparé (les tours et le temps y sont ceux de l'enregistrement).
 local meNow=F.cars[F.player]
 local restarted=false
 if not F.replay then
  -- Tours qui reculent dans les LAPS_HOLD s d'une remise à zéro : ceux de la séance d'avant qui retombent (1.3.7 :
  -- deux remises à zéro à 2 s d'écart à chaque nouvelle séance), pas un redémarrage.
  restarted=meNow and meNow.valid and lastLaps and meNow.laps<lastLaps and real-resetAt>LAPS_HOLD or false
  if meNow and meNow.valid then lastLaps=meNow.laps end
  if not F.paused then
   -- Départ redevenu non donné : en course seulement, avant l'arrivée (jamais un état de fin de séance).
   local unstarted=lastStarted and not F.started and F.isRace and not F.finishedSession and not (meNow and meNow.finished)
   if not F.online and real-resetAt>RESTART_HOLD and (unstarted or lastTime and F.sessionTime<lastTime-RESTART_BACK) then restarted=true end
   lastStarted=F.started; lastTime=F.sessionTime
  end
 end
 if lastPlayer==nil then lastPlayer=F.player end
 if F.player~=lastPlayer then playerSince=playerSince or real else playerSince=nil end
 local switched=playerSince and real-playerSince>2
 if F.session~=session or restarted or switched then
  -- Première remise à zéro après un rechargement à chaud dans la même séance : ce qui a été gardé est relu.
  ctx.resumed=Port.keep.resume(F.session,session==nil)
  session=F.session; lastPlayer=F.player; playerSince=nil; resetAt=real
  -- SetupLab installé ou retiré entre deux séances : la section des réglages suit (jamais relu à chaque image).
  app.has.setuplab=SetupLab.installed(Port.setupLabManifest())
  app.has.superhud=SuperHUD.installed(Port.superhudManifest())
  app.focus=Focus.new(); app.spectator=Spectator.new()
  Side.reset(side); Timing.reset(timing); Spotter.reset(spotter); Engineer.reset(engineer,ctx.keep); Emergency.reset(emergency); Voice.reset(voice); Port.forgetNames(); carPlayer=nil; carCompound=nil
  if ctx.resumed then Voice.heardLoad(voice,Port.keep.load('heard'),radio) end
  jlog(string.format('séance %s : %s, %d voitures, circuit de %.0f m, joueur voiture %d%s',tostring(F.session),F.isRace and 'course' or 'hors course',F.count or 0,
   tonumber(F.trackLength) or 0,F.player or -1,restarted and ' (redémarrage)' or switched and ' (autre voiture)' or ''))
  lapLogged=nil
 end
 -- Données de la voiture du joueur (courbes d'usure du composé monté, réservoir, temps d'arrêt).
 if F.player~=carPlayer or F.me.compound~=carCompound then
  local ok,data=pcall(Port.carData,math.max(0,F.player),F.me.compound)
  if ok and data then engineer.strategist.car=data; carPlayer=F.player; carCompound=F.me.compound
  elseif not ok then errors.count=errors.count+1; errors.last=tostring(data):sub(1,120); carPlayer=F.player; carCompound=F.me.compound end
 end
 -- SuperHUD (1.3.9, facultatif : src/superhud.lua) : clé relue deux fois par seconde quand il est installé.
 local shRadar=false
 if app.has.superhud then
  SuperHUD.step(app.superhud,Port.recall,real)
  shRadar=SuperHUD.radar(app.superhud,real)
  local alive=SuperHUD.get(app.superhud,real)~=nil
  if alive~=shLogged.alive or shRadar~=shLogged.radar then
   shLogged.alive=alive; shLogged.radar=shRadar
   jlog(string.format('SuperHUD : %s, radar sonore %s',alive and 'actif' or 'absent ou arrêté',shRadar and 'actif (côte à côte laissé à SuperHUD si réglé)' or 'inactif'))
  end
 end
 ctx.superhudRadar=shRadar
 local active=cfg.enabled and Link.connected(link) and not F.paused and not F.replay and not F.online
 local finishing=not active and cfg.enabled and F.isRace and link.state=='suspended' and link.reason=='finished'
  and not F.paused and not F.replay and not F.online
 if active~=lastActive then
  lastActive=active
  local why={}
  if not cfg.enabled then why[#why+1]='app coupée' end
  if not Link.connected(link) then why[#why+1]='liaison '..link.state end
  if F.paused then why[#why+1]='pause' end
  if F.replay then why[#why+1]='rediffusion' end
  if F.online then why[#why+1]='en ligne' end
  jlog(active and 'spotter et ingénieur : actifs' or 'spotter et ingénieur : en attente ('..table.concat(why,', ')..')')
 end
 if meNow and meNow.valid then
  if lapLogged and meNow.laps>lapLogged then jlog(string.format('tour %d fini : %s · P%d',meNow.laps,lapText(meNow.lastMs),tonumber(meNow.position) or 0)) end
  lapLogged=meNow.laps
 end
 if active and F.isRace then heartbeat(real) end
 if active then
  -- Tours sous neutralisation ou passés par la voie des stands : hors du rythme (src/timing.lua).
  local d=link.d
  local neutral=Link.neutralised(d)
  for i=0,F.count-1 do
   local c=F.cars[i]
   Timing.update(timing,i,c.spline,c.laps,F.clock,c.valid,neutral or c.pitlane)
   if c.valid then Timing.lap(timing,i,c.lastMs/1000,c.laps) end
  end
  ctx.now=F.clock; ctx.real=radio
  Side.step(side,Port.recall,real)
  if app.has.setuplab then
   SetupLab.step(setuplab,Port.recall,real,F.session)
   -- Journal : chaque texte lu de SetupLab (changé, au plus une fois par seconde), accepté ou non.
   local seen=setuplab.seen or nil
   if seen~=slLogged then slLogged=seen; jlog(string.format('SetupLab : %s (%s)',tostring(seen),SetupLab.get(setuplab) and 'acceptée' or 'ignorée')) end
  end
  -- Spotter.step suit toujours la direction de course (appels de stands de l'ingénieur) ; ses annonces se taisent avec
  -- le rôle Spotter coupé (radio).
  -- Radio de la voiture regardée (src/spectator.lua) : seulement quand le joueur ne pilote pas ; sa radio ne tourne
  -- pas alors. Jamais quand il pilote.
  local sp=app.spectator; sp.cameraTag=Lang.t.ov.camera
  local target=Spectator.target(sp,F,cfg,real)
  local okS,spectating=pcall(Spectator.step,sp,ctx,target,spotter)
  if not okS then protected(error,spectating); spectating=false end
  if spectating~=lastSpectating then
   lastSpectating=spectating
   jlog(spectating and string.format('radio de la voiture regardée : %s',F.cars[target] and F.cars[target].name or '?') or 'radio du joueur')
  end
  if not spectating then
   protected(Spotter.step,spotter,ctx)
   protected(Emergency.step,emergency,ctx,dt or 0)
   if cfg.engineerOn then protected(Engineer.step,engineer,ctx,dt or 0) end
  end
 elseif finishing then
  -- Arrivée : AdvancedIA suspend le pont dès la ligne (garde « finished ») mais publie encore son résultat ; l'arrivée
  -- et le bilan sont dits à la ligne, sans attendre la reconnexion (au retour au stand). Rien d'autre.
  ctx.now=F.clock; ctx.real=radio
  protected(Spotter.finish,spotter,ctx)
  if cfg.engineerOn then protected(Engineer.debrief,engineer,ctx) end
 elseif not cfg.enabled then
  if Voice.busy(voice) or #voice.queue>0 then Voice.stop(voice) end
 elseif linkGone then
  -- Liaison perdue : radio arrêtée ; l'essai de la voix (fenêtre de réglages) reste dit.
  if Voice.busy(voice) or #voice.queue>0 then Voice.purge(voice,notTest,true) end
 elseif not linkDown and not (link.state=='suspended' and link.reason=='finished') then
  -- Liaison suspendue (pause, rediffusion, AdvancedIA coupé ou en arrêt d'urgence, en ligne) : la phrase en cours
  -- finit, plus rien d'autre n'est dit (file vidée, sauf l'essai de la voix). À l'arrivée, le bilan en attente reste.
  if #voice.queue>0 then Voice.purge(voice,notTest) end
 end
 -- Plan d'arrêt pour AdvancedIA (contrat v1) : écrit à chaque changement ; le stamp avance chaque seconde de simulation.
 -- Selon les réglages seulement : en pause, le plan reste celui d'avant (AdvancedIA ne repasse pas à ses rappels).
 local pitplan=Strategist.pitplan(engineer.strategist,ctx,cfg.enabled and cfg.engineerOn and cfg.strategyOn)
 if pitplan~=pitplanText then pitplanText=pitplan; Port.store(Strategist.pitplanKey,pitplan) end
 -- Duel de stratégie (undercut, overcut, menace) pour l'affichage d'AdvancedIA (1.3.4, contrat v1), mêmes règles.
 local duelNow=Strategist.strategy(engineer.strategist,ctx,cfg.enabled and cfg.engineerOn and cfg.strategyOn)
 if duelNow~=duelText then duelText=duelNow; Port.store(Strategist.strategyKey,duelNow) end
end
-- Réglages enregistrés et raccourcis, à part : une erreur dans l'image ne les arrête pas.
local function settingsStep()
 if dirtyAt and Port.clock()-dirtyAt>1 then saveNow() end
 if F.valid then hotkeys() end
end
-- Radio à part (1.3.1) : une erreur ailleurs dans l'image (liaison, chronométrage, stratégie) n'arrête jamais la phrase
-- en cours ni la suivante, et le son de la voiture revient toujours.
local journalAt=0
local function radioStep()
 Voice.step(voice,app.radioNow)
 Port.warmStep()
end
local function duckFrame(dt) duckStep(dt or 0) end
local function journalStep()
 local now=Port.clock()
 if now-journalAt>=1 or now<journalAt then journalAt=now; Port.journalFlush() end
end
-- Réglages enregistrés (une seconde après le dernier changement, et avant un redémarrage de mise à jour). Bureaux
-- enregistrés sous des clés texte (« 1 » à « 4 ») : JSON valide même si certains bureaux n'ont jamais été réglés.
function saveNow()
 dirtyAt=nil; rememberDesktop()
 local out={}; for k,v in pairs(cfg) do out[k]=v end
 out.desktops={}; for d,t in pairs(desktops) do out.desktops[tostring(d)]=t end
 out.gameWindows={}; for d,t in pairs(gameWins) do out.gameWindows[tostring(d)]=t end
 Port.saveSettings(out)
end
function script.update(dt)
 radioClock()
 if protected(step,dt) then bootFrames=bootFrames+1 end
 protected(captureWindow,false)
 protected(settingsStep)
 protected(radioStep)
 protected(duckFrame,dt)
 protected(updateTick)
 protected(journalStep)
end
-- Fenêtres : une erreur de dessin ne laisse ni police ni découpe ouverte.
local function window(fn)
 local ok=protected(fn,app)
 if not ok then pcall(W.finish) else bootDraws=bootDraws+1 end
end
local function drawMain(a) UI.draw(view,a) end
-- Overlays, puis le bouton et le panneau d'édition en jeu (au-dessus).
-- Un overlay en erreur ne retire ni le bouton ni le panneau d'édition : l'erreur est relancée après eux.
local function drawHud(a)
 -- Bureau illisible : rien n'est dessiné (comme SuperHUD).
 if not a.desktopAvailable then return end
 local ok,err=pcall(Overlays.hud,hud,a)
 Editor.hud(editor,a)
 if not ok then error(err,0) end
end
-- Bureau relu avant de dessiner (comme SuperHUD) : CSP peut dessiner une fenêtre du nouveau bureau avant update(), un
-- réglage d'overlay fait aussitôt irait sinon dans le bureau quitté.
function script.SPE__MAIN() syncDesktop(); app.voicePresent=present; window(drawMain) end
-- Fenêtre de réglages en jeu (barre des applications, comme SuperHUD) ; la fenêtre principale reste celle des stands
-- et du menu pause (SETUP), ouverte aussi par AdvancedIA (IMGUI_LUA_SpotterEnginer_main).
function script.SPE__GAME()
 syncDesktop(true); app.voicePresent=present
 app.gameWindow=true; window(drawMain); app.gameWindow=false
 protected(captureWindow,true)
end
-- Croix de la fenêtre de réglages en jeu : fermée sur ce bureau (état relevé à l'image suivante).
function app.closeGameWindow() Port.closeGameWindow() end
-- Overlays en jeu (rappel IN_GAME du manifeste), comme SuperHUD et AdvancedIA.
-- CSP peut dessiner le nouveau bureau avant update() : bureau relu ici aussi (comme SuperHUD).
function script.SPE__HUD() syncDesktop(); window(drawHud) end
