-- Mise à jour depuis GitHub (tests repris d'AdvancedIA ; les numéros 1.33 à 1.47 des commentaires sont les versions
-- d'AdvancedIA où chaque cas est apparu) : logique pure avec un port imité (journal des appels),
-- puis le vrai port (src/remote.lua) sur une imitation de CSP à deux disques (tests/updatefake.lua).
-- L'imitation de CSP (tests/updatefake.lua) complète la table ac de CSP : présente, vide, hors de l'hôte factice.
if rawget(_G,'ac')==nil then rawset(_G,'ac',{}) end
local Up=require('src/update')
local Remote=require('src/remote')
local Fake=require('tests/updatefake')
local tests={}
-- Comparaison du paquet extrait en une seule tranche (résultats exacts) ; le test des tranches la règle lui-même.
Remote.compareSlice=math.huge
local SHA=string.rep('ab',32)
-- Corps du paquet : exactement la taille annoncée par la version publiée.
local SIZE=1000000
local ZIPDATA=string.rep('z',SIZE)
local function release(over)
 local r={tag_name='v1.34',name='1.34',draft=false,prerelease=false,html_url='https://github.com/VincentChevalier44/SpotterEnginer/releases/tag/v1.34',
  published_at='2026-11-05T10:00:00Z',body='## 1.34\r\n\r\n- **Panneaux** lumineux\n- `DRS`\n',
  assets={{name='SpotterEnginer-1.34.zip',size=SIZE,browser_download_url=Up.download..'v1.34/SpotterEnginer-1.34.zip'},
   {name='SpotterEnginer-1.34.sha256',size=100,browser_download_url=Up.download..'v1.34/SpotterEnginer-1.34.sha256'}}}
 for k,v in pairs(over or {}) do r[k]=v end
 return r
end
-- Pont partagé avec AdvancedIA (src/bridge_layout.lua) : version 1 par défaut, dans le paquet comme chez AdvancedIA.
local function layout(v) return '-- pont\nlocal L={}\nL.version='..v..'\nreturn L\n' end
local LAYOUT=layout(1)
local function entries() local t={}; for _,f in ipairs(Up.required) do t[#t+1]=Up.prefix..f end; t[#t+1]=Up.prefix..'src/'; return t end
-- Port imité : o.* règle les réponses et les versions des sources (next, current, backup), calls garde l'ordre.
local function port(o)
 o=o or {}
 local p={calls={},marked=o.marked,reported=o.report,boots=o.boot,note=o.failed}
 local versions={next=o.next==nil and '1.34' or o.next or nil,current=o.current,backup=o.backup}
 local function log(x) p.calls[#p.calls+1]=x end
 function p.get(url,_,cb)
  log('get '..url)
  local function answer()
   if url==Up.api then cb(o.apiErr,o.apiStatus or 200,'api')
   elseif url:find('%.sha256$') then cb(o.shaErr,o.shaStatus or 200,o.shaText or (SHA..'  SpotterEnginer-1.34.zip\n'))
   else cb(o.zipErr,o.zipStatus or 200,o.zipData or ZIPDATA) end
  end
  if p.hold then p.pending=p.pending or {}; p.pending[#p.pending+1]=answer else answer() end
 end
 function p.flush() while p.pending and #p.pending>0 do local list=p.pending; p.pending={}; for _,fn in ipairs(list) do fn() end end end
 function p.json() if o.json==nil then return release() end; return o.json or nil end
 function p.sha256() return o.hash or SHA end
 function p.entries() return o.entries or entries() end
 function p.entry(_,name)
  if name==Up.prefix..Up.companion.layout then return o.pkgLayout or LAYOUT end
  if name:sub(-4)=='.lua' and o.lua then return o.lua end; return o.manifest or '[ABOUT]\nVERSION=1.34\n'
 end
 -- AdvancedIA installé (o.aai=false : absent) et pont de la version précédente.
 function p.companionLayout() if o.aai==false then return nil end; return o.aai or LAYOUT end
 -- Paquet extrait (next) : pont et manifeste du paquet ; sauvegarde : son pont s'il a été gardé (o.backupLayout).
 function p.sourceText(name,rel)
  if rel==Up.companion.layout then if name=='next' then return o.pkgLayout or LAYOUT end; return o.backupLayout end
  if name=='next' and rel=='manifest.ini' then return o.manifest or '[ABOUT]\nVERSION=1.34\n' end
  return nil
 end
 -- Version par-dessus laquelle la sauvegarde vaut (o.over ; false : sauvegarde d'avant ce repère) : par défaut la
 -- version installée.
 function p.sourceOver(name) if name~='backup' or o.over==false then return p.over end; return p.over or o.over or o.installed or '1.34' end
 function p.sourceSetOver(name,v) log('over '..name..' '..v); p.over=v; return true end
 function p.sourceListed() return o.backupListed==true end
 function p.appText(rel) if rel==Up.companion.layout then return LAYOUT end; return nil end
 function p.installedVersion() return o.installed end
 function p.sourceVersion(name) return versions[name] end
 function p.sourceComplete(name) return versions[name]~=nil and not (o.incomplete or {})[name] end
 function p.sourceHas() return o.missing==nil end
 function p.markerFile() return 'state/installing.txt' end
 function p.marker() return p.marked end
 function p.mark(t) log('mark '..t:match('^[^\n]*')); if o.markFails then return false end; p.marked=t; return true end
 function p.clearMarker() log('clear'); if o.clearFails then return false end; p.marked=nil; return true end
 function p.report(t) log('report '..t); p.reported=t; return true end
 function p.takeReport() local t=p.reported; p.reported=nil; return Up.parseReport(t) end
 function p.boot() local b=p.boots; if not b then return nil end; return b[1],b[2],b[3] end
 function p.bootSet(version,from,count) log('boot '..version..' '..(count or 0)); p.boots={version,count or 0,from}; return true end
 function p.bootClear() log('boot clear'); p.boots=nil; return true end
 function p.failedNote(t) log('failed note'); p.note=t; return true end
 function p.failed() return p.note end
 function p.clearFailed() p.note=nil; return true end
 function p.stage(_,names,cb)
  log('stage'); p.names=names
  local function done() cb(o.stageErr) end
  if p.holdStage then p.staged=done else done() end
 end
 function p.snapshot(source) log('snapshot'); p.snapSource=source; if o.snapshotFails then return false,'src/ui.lua' end; versions.current=o.installed or '1.33'; return true,nil,{saved=2,ms=1} end
 function p.place(name)
  log('place '..name)
  if (o.placeFails or {})[name] then return false,o.placeFails[name] end
  o.installed=versions[name]; return true,nil,{compared=5,copied=3,ms=2}
 end
 function p.promote(kind) log('promote '..kind); if o.promoteFails then return false,'renommage' end; if kind=='update' then versions.backup=versions.current end; return true end
 function p.restart() log('restart') end
 return p
end
local function find(calls,x) for i,c in ipairs(calls) do if c==x then return i end end end
local function count(calls,x) local n=0; for _,c in ipairs(calls) do if c==x then n=n+1 end end; return n end
local function ready(o) local u=Up.new('1.33'); local p=port(o); Up.start(u,p); Up.check(u,p,100); return u,p end
local function events(u) local out=Up.take(u,{}); local text={}; for i,e in ipairs(out) do text[i]=e[1]..' '..e[2] end; return table.concat(text,'\n') end
local function ordered(calls,list) local last=0; for _,x in ipairs(list) do local i=find(calls,x); if not i or i<last then return false,x end; last=i end; return true end

tests.UPDATE_VERSIONS=function()
 assert(table.concat(Up.version('1.33'),'.')=='1.33' and table.concat(Up.version('v1.33.2'),'.')=='1.33.2')
 assert(table.concat(Up.version('SpotterEnginer-1.34.zip'),'.')=='1.34' and Up.version('Beta')==nil and Up.version(nil)==nil)
 assert(Up.newer('1.34','1.33') and Up.newer('v1.33.1','1.33') and Up.newer('1.40','1.39'))
 assert(not Up.newer('1.33','1.33') and not Up.newer('1.32','1.33') and not Up.newer('1.33','1.33.0'))
 assert(Up.newer('2.0','1.99') and not Up.newer('x','1.0') and not Up.newer('1.0','x'))
 assert(Up.label('v1.34')=='1.34' and Up.label('')==nil)
end
tests.UPDATE_RELEASE_PARSE=function()
 local r=Up.release(release())
 assert(r and r.version=='1.34' and r.zip.size==SIZE and r.published=='2026-11-05' and r.page:find('/tag/v1.34',1,true))
 assert(r.notes[1]=='1.34' and r.notes[2]=='' and r.notes[3]=='- Panneaux lumineux' and r.notes[4]=='- DRS' and #r.notes==4)
 -- Brouillon, préversion, sans paquet ou sans empreinte, autre nom, autre adresse, taille aberrante : refusés.
 assert(not Up.release(release({draft=true})) and not Up.release(release({prerelease=true})) and not Up.release(release({tag_name='latest'})))
 local a=release(); table.remove(a.assets,2); assert(not Up.release(a))
 a=release(); table.remove(a.assets,1); assert(not Up.release(a))
 a=release(); a.assets[1].name='SpotterEnginer-1.35.zip'; assert(not Up.release(a))
 -- Les paquets d'AdvancedIA (même module, autre dépôt) ne sont jamais retenus.
 a=release(); a.assets[1].name='AdvancedIA-Beta-1.34.zip'; assert(not Up.release(a))
 a=release(); a.assets[1].browser_download_url='https://github.com/VincentChevalier44/AdvancedIA/releases/download/v1.34/SpotterEnginer-1.34.zip'; assert(not Up.release(a))
 assert(Up.prefix=='apps/lua/SpotterEnginer/' and Up.required[2]=='SpotterEnginer.lua' and Up.repo=='VincentChevalier44/SpotterEnginer')
 a=release(); a.assets[1].browser_download_url='https://example.com/SpotterEnginer-1.34.zip'; assert(not Up.release(a))
 a=release(); a.assets[2].browser_download_url='https://example.com/SpotterEnginer-1.34.sha256'; assert(not Up.release(a))
 a=release(); a.assets[1].size=0; assert(not Up.release(a))
 a=release(); a.assets[1].size=Up.sizeMax+1; assert(not Up.release(a))
 a=release(); a.html_url='https://evil.example/'; assert(Up.release(a).page==Up.page)
 assert(not Up.release(nil) and not Up.release('x'))
 local long=string.rep('x',500); local n=Up.notes(long..'\n'..string.rep('l\n',100))
 assert(#n[1]==Up.lineMax and #n==Up.notesMax)
 -- Coupure UTF-8 : jamais au milieu d'un caractère (« → » sur trois octets).
 local arrows=Up.notes(string.rep('→',100))[1]
 assert(arrows:sub(-3)=='...' and #arrows<=Up.lineMax and arrows:sub(1,-4)==string.rep('→',math.floor((Up.lineMax-3)/3)))
 assert(Up.cut('aé',2)=='a' and Up.cut('aé',3)=='aé' and Up.cut('abc',5)=='abc')
end
tests.UPDATE_DIGEST_AND_CONTENT=function()
 assert(Up.digest(SHA..'  SpotterEnginer-1.34.zip','SpotterEnginer-1.34.zip')==SHA)
 assert(Up.digest(SHA:upper()..' *SpotterEnginer-1.34.zip\r\n','SpotterEnginer-1.34.zip')==SHA)
 assert(not Up.digest(SHA..'  autre.zip','SpotterEnginer-1.34.zip') and not Up.digest('abc  SpotterEnginer-1.34.zip','SpotterEnginer-1.34.zip'))
 assert(not Up.digest(nil,'x'))
 assert(Up.content(entries()))
 local function with(x) local t=entries(); t[#t+1]=x; return t end
 assert(not Up.content(with('apps/lua/Autre/x.lua')) and not Up.content(with(Up.prefix..'../../evil.lua')) and not Up.content(with(Up.prefix..'src/../../x')))
 assert(not Up.content(with(Up.prefix..'src\\a.lua')) and not Up.content(with('C:/evil')) and not Up.content(with('/apps/lua/SpotterEnginer/x')))
 assert(not Up.content(with(Up.prefix..'src//a.lua')) and not Up.content(with(Up.prefix..'./a.lua')))
 -- Entrées de dossier et noms qui contiennent seulement des points : acceptés.
 assert(Up.content(with(Up.prefix..'fonts/')) and Up.content(with(Up.prefix..'docs/notes..md')))
 -- Chaque fichier indispensable, dont le module de mise à jour lui-même.
 for i=1,#Up.required do local t=entries(); table.remove(t,i); assert(not Up.content(t),'required '..i) end
 assert(not Up.content({}) and not Up.content(nil))
 -- Fichiers du paquet : sans les entrées de dossier, chemins relatifs à l'app.
 local files=Up.files(entries()); assert(#files==#Up.required and files[1]=='manifest.ini')
 -- Modules requis par le code du paquet : tous présents.
 local list=entries(); list[#list+1]=Up.prefix..'src/ui.lua'
 assert(Up.requires(list,function() return "local W=require('src/update')\nlocal R=require(\"src/remote\")" end))
 local okReq,missing=Up.requires(list,function(name) return name:find('ui.lua',1,true) and "local G=require('src/groups')" or '' end)
 assert(not okReq and missing=='src/groups')
 assert(Up.requires(list,function() return "local bit=require('bit')" end),'library modules ignored')
 assert(Up.manifestVersion('[ABOUT]\r\nVERSION=1.34\r\n')=='1.34' and Up.manifestVersion('NAME=x')==nil and Up.manifestVersion(nil)==nil)
 assert(Up.manifestVersion('REQUIRED_VERSION=0.2.3\nVERSION=1.34')=='1.34' and Up.manifestVersion('REQUIRED_VERSION=0.2.3')==nil)
 -- À l'arrêt : pause, ou emplacement des stands à l'arrêt (src/port.lua : inPit) ; jamais la voie des stands en roulant.
 assert(Up.stopped({paused=true}) and Up.stopped({},{inPit=true,kmh=0}))
 assert(not Up.stopped({},{inPit=true,kmh=40}) and not Up.stopped({},{pitlane=true,inPit=false,kmh=0}) and not Up.stopped({}) and not Up.stopped(nil,{inPit=true,kmh=0}))
 assert(Up.parseReport('recovered 1.33 -> 1.34')=='recovered' and Up.parseReport('n importe quoi')==nil)
 local kind,from,to,auto=Up.parseReport('rollback 1.35 -> 1.34 auto'); assert(kind=='rollback' and from=='1.35' and to=='1.34' and auto)
 local kind2,from2,to2,tries=Up.parse('update 1.33 -> 1.34\ntries 1'); assert(kind2=='update' and from2=='1.33' and to2=='1.34' and tries==1)
end
tests.UPDATE_CHECK_STATES=function()
 local u=ready(); assert(u.phase=='available' and u.release.version=='1.34' and Up.offered(u))
 assert(events(u):find('INFO mise a jour disponible: 1.34 (publiee le 2026-11-05, 1000000 octets)',1,true))
 u=Up.new('1.34'); Up.check(u,port(),100); assert(u.phase=='current' and not Up.offered(u))
 u=Up.new('1.35'); Up.check(u,port(),100); assert(u.phase=='current')
 u=Up.new('1.33'); Up.check(u,port({apiStatus=404}),100); assert(u.phase=='none' and events(u):find('aucune version publiee',1,true))
 -- Limite de requêtes de GitHub : dite comme telle, la version n'est plus proposée.
 u=Up.new('1.33'); Up.check(u,port({apiStatus=403}),100); assert(u.phase=='failed' and u.error=='rate' and u.status==403 and events(u):find('limite de requetes) (statut 403)',1,true))
 u=Up.new('1.33'); Up.check(u,port({apiStatus=500}),100); assert(u.error=='network' and u.status==500)
 u=Up.new('1.33'); Up.check(u,port({apiErr='timeout'}),100); assert(u.phase=='failed' and u.error=='network' and events(u):find('echec reseau : timeout',1,true))
 u=Up.new('1.33'); Up.check(u,port({json=false}),100); assert(u.phase=='failed' and u.error=='format' and not Up.offered(u))
 -- Une vérification ou une installation en cours n'est jamais doublée ; au bouton, une vérification par minute au plus.
 u=Up.new('1.33'); u.phase='downloading'; assert(not Up.check(u,port(),100) and u.phase=='downloading')
 u=Up.new('1.33'); local p=port(); assert(Up.check(u,p,100) and not Up.check(u,p,100+Up.checkGap-1) and Up.check(u,p,100+Up.checkGap))
end
-- 1.35 : vérification et téléchargement bornés dans le temps (réponse qui n'arrive jamais).
tests.UPDATE_TIMEOUTS=function()
 local u=Up.new('1.33'); local p=port(); p.hold=true
 Up.check(u,p,100); Up.tick(u,p,true,100+Up.checkTimeout-1); assert(u.phase=='checking')
 Up.tick(u,p,true,100+Up.checkTimeout+1); assert(u.phase=='failed' and u.error=='network' and not Up.busy(u))
 p.flush(); assert(u.phase=='failed','late answer ignored')
 u=Up.new('1.33'); p=port(); Up.check(u,p,0); p.hold=true; Up.tick(u,p,true,10)
 assert(Up.install(u,p,true) and u.phase=='downloading')
 Up.tick(u,p,true,10+Up.downloadTimeout+1); assert(u.phase=='failed' and u.error=='network' and events(u):find('telechargement non termine',1,true))
 p.flush(); assert(u.phase=='failed','late download ignored')
end
tests.UPDATE_INSTALL_ORDER=function()
 local u,p=ready({installed='1.33'})
 assert(Up.install(u,p,true) and u.phase=='ready')
 assert(not find(p.calls,'snapshot') and not find(p.calls,'mark update 1.33 -> 1.34'),'nothing copied before the next stopped frame')
 Up.tick(u,p,true,200)
 local ok,missing=ordered(p.calls,{'get '..u.release.sha.url,'get '..u.release.zip.url,'stage','snapshot','mark update 1.33 -> 1.34','place next','promote update','clear','report update 1.33 -> 1.34','boot 1.34 0','restart'})
 assert(ok,missing)
 assert(p.snapSource=='next' and p.names and #p.names==#Up.required,'snapshot of the files the copy replaces')
 assert(u.phase=='restarting' and u.after=='update' and p.marked==nil and Up.view(u,true)=='done')
 local log=events(u)
 for _,line in ipairs({'telechargement de la 1.34','1.34 prete, empreinte et contenu verifies','1.34 installee (5 fichiers compares, 3 copies en 2 ms ; 2 fichiers gardes en 1 ms), radio arretee, son de la voiture rendu'}) do assert(log:find(line,1,true),line) end
 -- Version de départ lue dans le manifeste installé (pas seulement celle du module).
 u,p=ready({installed='1.33.1'}); Up.install(u,p,true); Up.tick(u,p,true,1); assert(find(p.calls,'mark update 1.33.1 -> 1.34'))
end
tests.UPDATE_READY_EXPIRES=function()
 -- Paquet prêt quand le pilote est reparti : copie reportée (jamais en roulant), paquet gardé, nouveau clic à l'arrêt.
 local u,p=ready({installed='1.33'})
 p.holdStage=true; Up.install(u,p,true); assert(u.phase=='staging')
 p.staged(); assert(u.phase=='ready' and Up.busy(u) and Up.view(u,false)=='ready')
 Up.tick(u,p,false,201); assert(u.phase=='available' and u.release.staged and not find(p.calls,'place next'))
 assert(events(u):find('copie reportee (pilote reparti)',1,true))
 -- Nouveau clic à l'arrêt : rien n'est retéléchargé ; copie à l'image suivante.
 local downloads=count(p.calls,'get '..u.release.zip.url)
 assert(Up.install(u,p,true) and u.phase=='ready' and count(p.calls,'get '..u.release.zip.url)==downloads)
 Up.tick(u,p,true,300); assert(u.phase=='restarting' and find(p.calls,'place next'))
 -- Paquet extrait abîmé entre-temps : téléchargé à nouveau.
 u,p=ready({installed='1.33',incomplete={next=true}}); Up.install(u,p,true); assert(u.phase=='failed' and u.error=='content')
 -- Annulée pendant l'attente : rien n'est copié.
 u,p=ready({installed='1.33'}); Up.install(u,p,true); assert(Up.cancel(u) and u.phase=='available')
 Up.tick(u,p,true,400); assert(not find(p.calls,'place next') and not find(p.calls,'mark update 1.33 -> 1.34'))
 assert(Up.cancelable.ready and Up.cancelable.downloading and not Up.cancelable.placing)
end
tests.UPDATE_INSTALL_GUARDS=function()
 -- En conduite : rien n'est téléchargé ; le refus est journalisé.
 local u,p=ready(); assert(not Up.install(u,p,false) and u.phase=='failed' and u.error=='driving' and not find(p.calls,'get '..u.release.zip.url))
 assert(events(u):find('INFO mise a jour: refusee en conduite',1,true) and Up.offered(u))
 -- Déjà à jour, ou aucune version connue : bouton sans effet.
 u=Up.new('1.34'); p=port(); Up.check(u,p,100); assert(not Up.install(u,p,true) and #p.calls==1)
 u=Up.new('1.33'); assert(not Up.install(u,port(),true))
 -- Chaque échec avant la copie finale laisse la version installée intacte (ni repère, ni copie dans l'app).
 local cases={{shaStatus=404,code='network'},{shaErr='timeout',code='network'},{shaText='bad',code='format',detail='empreinte'},{zipStatus=500,code='network'},
  {zipErr='reset',code='network'},{zipData='court',code='integrity',detail='taille 5 octets'},{hash=string.rep('cd',32),code='integrity',detail='SHA-256'},
  {entries={'apps/lua/Autre/x'},code='content'},{lua="require('src/absent')",code='content',detail='module absent : src/absent'},
  {manifest='VERSION=1.33',code='content'},{stageErr='disk',code='write'},{next=false,code='content'},{missing=true,code='content'},
  {incomplete={next=true},code='content'},{snapshotFails=true,code='write'}}
 for i,o in ipairs(cases) do
  u,p=ready(o); Up.take(u,{}); Up.install(u,p,true); Up.tick(u,p,true,500)
  assert(u.phase=='failed' and u.error==o.code,'case '..i..' '..tostring(u.error))
  if o.detail then assert(u.detail:find(o.detail,1,true),'case '..i..' detail '..u.detail) end
  assert(not find(p.calls,'place next') and not find(p.calls,'restart') and p.marked==nil,'case '..i)
  assert(events(u):find('version actuelle conservee',1,true),'case '..i)
 end
 -- Repère impossible à écrire (ou à relire) : rien n'est copié.
 u,p=ready({markFails=true}); Up.install(u,p,true); Up.tick(u,p,true,500); assert(u.error=='write' and not find(p.calls,'place next'))
end
tests.UPDATE_PLACE_FAILURE_RESTORES=function()
 -- Copie en échec : la version de départ (current) est remise en place aussitôt, repère levé, version conservée.
 local u,p=ready({installed='1.33',placeFails={next='src/ui.lua'}}); Up.install(u,p,true); Up.tick(u,p,true,500)
 assert(u.phase=='failed' and u.error=='write' and u.detail=='src/ui.lua' and p.marked==nil and not find(p.calls,'restart'))
 assert(ordered(p.calls,{'mark update 1.33 -> 1.34','place next','place current','clear'}))
 assert(not find(p.calls,'promote update') and not find(p.calls,'boot 1.34 0'),'backup kept and no boot watch when the install failed')
 -- Remise en place impossible aussi : état terminal (plus aucune opération), repère gardé pour la reprise au lancement.
 u,p=ready({installed='1.33',placeFails={next='src/ui.lua',current='src/engine.lua'}}); Up.take(u,{}); Up.install(u,p,true); Up.tick(u,p,true,500)
 assert(u.phase=='broken' and u.brokenFile=='state/installing.txt' and p.marked~=nil and Up.view(u,true)=='broken' and Up.busy(u))
 assert(events(u):find('ERROR mise a jour: copie de src/ui.lua impossible, puis remise en place impossible (src/engine.lua)',1,true))
 assert(not Up.check(u,p,9999) and not Up.install(u,p,true) and not Up.rollback(u,p,true))
 -- Copie réussie mais sauvegarde non promue, repère non effacé : dit au journal, redémarrage quand même (reprise au
 -- lancement suivant : manifeste déjà à la version visée).
 u,p=ready({installed='1.33',promoteFails=true,clearFails=true}); Up.take(u,{}); Up.install(u,p,true); Up.tick(u,p,true,500)
 local log=events(u)
 assert(u.phase=='restarting' and log:find('retour arriere indisponible',1,true) and log:find('repere non efface',1,true))
end
tests.UPDATE_CANCEL=function()
 -- Annulation pendant le téléchargement : la réponse arrivée ensuite est ignorée, même après un nouveau clic.
 local u=Up.new('1.33'); local p=port(); Up.check(u,p,100)
 p.hold=true; Up.install(u,p,true); assert(u.phase=='downloading')
 assert(Up.cancel(u) and u.phase=='available')
 Up.install(u,p,true); assert(u.phase=='downloading')
 p.flush()
 -- Une seule chaîne a continué (le premier téléchargement est ignoré) : un seul « stage ».
 assert(count(p.calls,'stage')==1 and u.phase=='ready','one pipeline: '..count(p.calls,'stage'))
 assert(not Up.cancel(Up.new('x')))
end
tests.UPDATE_RECOVER=function()
 assert(Up.recover(port())==nil)
 -- Repère illisible : levé, rien copié.
 local p=port({marked='???'}); local r=Up.recover(p); assert(r.outcome=='cleared' and p.marked==nil and not find(p.calls,'place next'))
 -- Manifeste à la version visée : copie allée au bout ; sauvegarde promue, compte rendu.
 p=port({marked='update 1.33 -> 1.34',installed='1.34',current='1.33'})
 r=Up.recover(p); assert(r.outcome=='finished' and not r.restart and p.marked==nil and p.reported=='update 1.33 -> 1.34' and find(p.calls,'promote update') and not find(p.calls,'place next'))
 -- Manifeste encore à la version de départ, paquet extrait intact : la copie est refaite vers la version visée.
 p=port({marked='update 1.33 -> 1.34',installed='1.33',current='1.33'})
 r=Up.recover(p); assert(r.outcome=='completed' and r.restart and p.marked==nil and find(p.calls,'place next') and p.reported=='update 1.33 -> 1.34')
 -- Paquet absent ou incomplet : version de départ remise en place ; compte rendu « recovered ».
 for _,o in ipairs({{next=false},{incomplete={next=true}}}) do
  o.marked='update 1.33 -> 1.34'; o.installed='1.33'; o.current='1.33'
  p=port(o); r=Up.recover(p); assert(r.outcome=='restored' and r.restart and find(p.calls,'place current') and not find(p.calls,'place next') and p.reported=='recovered 1.33 -> 1.34')
 end
 -- Rien n'est possible : essai compté dans le repère, puis abandon au deuxième essai (jamais en boucle), noté.
 p=port({marked='update 1.33 -> 1.34',installed='1.33',next=false,current=false})
 r=Up.recover(p); assert(r.outcome=='failed' and p.marked:find('tries 1',1,true))
 r=Up.recover(p); assert(r.outcome=='failed' and p.marked:find('tries 2',1,true))
 r=Up.recover(p); assert(r.outcome=='gaveup' and not r.restart and p.marked==nil and p.note:find('installed 1.33',1,true))
 -- Autre version installée (réinstallée à la main) : repère levé sans rien copier.
 p=port({marked='update 1.33 -> 1.34',installed='1.40'})
 r=Up.recover(p); assert(r.outcome=='cleared' and r.installed=='1.40' and p.marked==nil and not find(p.calls,'place current'))
 -- Retour arrière interrompu : refait vers la version précédente (backup).
 p=port({marked='rollback 1.34 -> 1.33',installed='1.34',backup='1.33',current='1.34'})
 r=Up.recover(p); assert(r.outcome=='completed' and find(p.calls,'place backup') and p.reported=='rollback 1.34 -> 1.33')
 -- Repère qui ne se réécrit pas (lecture seule) : rien n'est copié, aucun redémarrage (jamais en boucle).
 p=port({marked='update 1.33 -> 1.34',installed='1.33',current='1.33',markFails=true})
 r=Up.recover(p); assert(r.outcome=='failed' and not r.restart and not find(p.calls,'place next') and not find(p.calls,'place current'))
 -- Copie refaite mais repère impossible à effacer : aucun redémarrage (le lancement suivant trouve la version visée).
 p=port({marked='update 1.33 -> 1.34',installed='1.33',current='1.33',clearFails=true})
 r=Up.recover(p); assert(r.outcome=='failed' and not r.restart and r.failed=='repere')
 for _,o in ipairs({'cleared','finished','completed','restored','autorollback','bootfailed','gaveup','failed'}) do
  local level,text=Up.recoverText({outcome=o,kind='update',from='1.33',to='1.34',file='x'}); assert(level and text,o)
 end
 assert(Up.recoverText(nil)==nil and Up.recoverText({outcome='?'})==nil)
end
-- 1.35 : démarrage surveillé : une version installée qui ne démarre pas deux fois de suite est défaite.
tests.UPDATE_BOOT_WATCH=function()
 -- Démarrage réussi : la surveillance s'arrête (bootOk côté port, voir le test du vrai port).
 local p=port({installed='1.34',backup='1.33',boot={'1.34',0,'1.33'}})
 assert(Up.recover(p)==nil and p.boots[2]==1)
 assert(Up.recover(p)==nil and p.boots[2]==2)
 local r=Up.recover(p)
 assert(r.outcome=='autorollback' and r.restart and r.auto and find(p.calls,'place backup') and p.marked==nil and p.boots==nil)
 assert(p.reported=='rollback 1.34 -> 1.33 auto')
 -- Compte rendu au lancement suivant : retour arrière automatique dit.
 local u=Up.new('1.33'); Up.start(u,p); assert(u.updated.kind=='rollback' and u.updated.auto and events(u):find('retour arriere termine (automatique)',1,true))
 -- Version précédente incomplète : rien n'est copié, l'app le dit.
 p=port({installed='1.34',backup='1.33',incomplete={backup=true},boot={'1.34',2,'1.33'}})
 r=Up.recover(p); assert(r.outcome=='bootfailed' and not r.restart and not find(p.calls,'place backup'))
 u=Up.new('1.34'); Up.start(u,p,r); assert(u.phase=='broken')
 -- Surveillance d'une autre version (réinstallée à la main) : oubliée.
 p=port({installed='1.40',boot={'1.34',1,'1.33'}}); assert(Up.recover(p)==nil and p.boots==nil)
end
tests.UPDATE_START_REPORTS=function()
 local u=Up.new('1.34'); local p=port({report='update 1.33 -> 1.34',backup='1.33'})
 Up.start(u,p); assert(u.updated.kind=='update' and u.updated.from=='1.33' and u.previous=='1.33' and Up.view(u,true)=='success')
 assert(events(u):find('mise a jour reussie: 1.33 -> 1.34',1,true))
 -- Compte rendu lu une seule fois.
 local again=Up.new('1.34'); Up.start(again,p); assert(again.updated==nil)
 -- Sauvegarde de la version installée elle-même, ou incomplète : rien à proposer.
 u=Up.new('1.33'); Up.start(u,port({backup='1.33'})); assert(u.previous==nil)
 u=Up.new('1.34'); Up.start(u,port({backup='1.33',incomplete={backup=true}})); assert(u.previous==nil)
 -- Reprise faite au chargement : dite au journal ; impossible : état terminal.
 u=Up.new('1.34'); Up.start(u,port(),{outcome='completed',kind='update',from='1.33',to='1.34'}); assert(events(u):find('copie reprise au lancement, installation termine',1,true))
 -- Fichiers copiés au chargement : un redémarrage, à la première image ; compte rendu laissé au lancement suivant.
 local rp=port({report='update 1.33 -> 1.34'})
 u=Up.new('1.34'); Up.start(u,rp,{outcome='completed',kind='update',from='1.33',to='1.34',restart=true})
 assert(u.phase=='restarting' and u.restartPending and u.updated==nil and rp.reported=='update 1.33 -> 1.34' and Up.busy(u))
 Up.tick(u,rp,false,1); Up.tick(u,rp,false,2)
 assert(count(rp.calls,'restart')==1 and not u.restartPending,'one restart')
 -- Reprise sans copie (terminée, repère levé, abandon) : jamais de redémarrage.
 for _,o in ipairs({'finished','cleared','gaveup'}) do local q=port(); local w=Up.new('1.34'); Up.start(w,q,{outcome=o,kind='update',from='1.33',to='1.34',file='x'}); Up.tick(w,q,true,1); assert(not find(q.calls,'restart'),o) end
 u=Up.new('1.33'); Up.start(u,port(),{outcome='restored',kind='update',from='1.33',to='1.34'}); assert(events(u):find('1.33 remise en place au lancement',1,true))
 u=Up.new('1.33'); Up.start(u,port(),{outcome='gaveup',kind='update',from='1.33',to='1.34',file='state/installing.txt'})
 assert(u.phase=='broken' and u.brokenFile=='state/installing.txt' and events(u):find('ERROR mise a jour: reprise abandonnee',1,true))
 -- Abandon d'une reprise rappelé tant que la même version reste installée ; oublié après une réinstallation.
 local fp=port({failed='update 1.33 -> 1.34\ninstalled 1.33'})
 u=Up.new('1.33'); Up.start(u,fp); assert(u.warning and events(u):find('une reprise a echoue',1,true) and fp.note~=nil)
 u=Up.new('1.35'); Up.start(u,fp); assert(u.warning==nil and fp.note==nil)
end
tests.UPDATE_ROLLBACK=function()
 local u=Up.new('1.34'); local p=port({backup='1.33',installed='1.34'}); Up.start(u,p)
 assert(not Up.rollback(u,p,false) and u.error=='driving' and not find(p.calls,'place backup'))
 u=Up.new('1.34'); p=port({backup='1.33',installed='1.34'}); Up.start(u,p)
 -- Demandé au clic, copié à l'image suivante, toujours à l'arrêt (hors du dessin de la fenêtre).
 assert(Up.rollback(u,p,true) and u.phase=='rollbackReady' and Up.busy(u) and not find(p.calls,'place backup'))
 Up.tick(u,p,true,50)
 assert(u.phase=='restarting' and u.after=='rollback' and Up.view(u,true)=='rolledback')
 assert(ordered(p.calls,{'snapshot','mark rollback 1.34 -> 1.33','place backup','promote rollback','clear','report rollback 1.34 -> 1.33','boot clear','restart'}))
 assert(p.snapSource=='backup')
 -- Pilote reparti avant l'image suivante : retour arrière annulé.
 u=Up.new('1.34'); p=port({backup='1.33',installed='1.34'}); Up.start(u,p); Up.rollback(u,p,true); Up.tick(u,p,false,50)
 assert(u.phase=='idle' and not find(p.calls,'place backup'))
 -- Retour en échec : version installée remise en place aussitôt.
 u=Up.new('1.34'); p=port({backup='1.33',installed='1.34',placeFails={backup='src/ui.lua'}}); Up.start(u,p)
 Up.rollback(u,p,true); Up.tick(u,p,true,50); assert(u.phase=='failed' and u.error=='write' and find(p.calls,'place current') and p.marked==nil and not find(p.calls,'restart'))
 -- Version précédente devenue incomplète : refusé sans rien copier.
 u=Up.new('1.34'); local o={backup='1.33',installed='1.34'}; p=port(o); Up.start(u,p); o.incomplete={backup=true}
 assert(not Up.rollback(u,p,true) and u.error=='write' and not find(p.calls,'snapshot'))
 -- Sans version précédente : bouton sans effet.
 u=Up.new('1.34'); p=port(); Up.start(u,p); assert(not Up.rollback(u,p,true) and #p.calls==0)
end
tests.UPDATE_VIEW_STATES=function()
 local V=Up.view
 local u=Up.new('1.33'); assert(V(u,true)=='unchecked')
 local p=port(); Up.check(u,p,100); assert(V(u,true)=='available' and V(u,false)=='driving')
 u=Up.new('1.33'); p=port(); Up.check(u,p,100); Up.install(u,p,false); assert(V(u,false)=='driving' and V(u,true)=='available')
 -- Retour arrière refusé en conduite sans version publiée connue : jamais « un clic installe la mise à jour ».
 u=Up.new('1.34'); p=port({backup='1.33'}); Up.start(u,p); Up.rollback(u,p,false); assert(V(u,true)=='driving')
 u=Up.new('1.34'); Up.check(u,port(),100); assert(V(u,true)=='uptodate')
 u=Up.new('1.33'); Up.check(u,port({apiStatus=404}),100); assert(V(u,true)=='none')
 for err,view in pairs({network='errNet',rate='errRate',format='errFormat',integrity='errHash',content='errHash',write='errWrite'}) do
  u=Up.new('1.33'); u.phase='failed'; u.error=err; assert(V(u,true)==view,err)
 end
 for phase,view in pairs({checking='checking',downloading='downloading',verifying='verifying',staging='installing',saving='installing',placing='installing',ready='ready',rollbackReady='installing',broken='broken'}) do
  u=Up.new('1.33'); u.phase=phase; assert(V(u,true)==view,phase)
 end
 -- Après le redémarrage : compte rendu affiché même si la vérification du lancement a déjà répondu.
 for report,view in pairs({['update 1.33 -> 1.34']='success',['rollback 1.34 -> 1.33']='rolledback',['recovered 1.33 -> 1.34']='interrupted'}) do
  u=Up.new('1.34'); p=port({report=report}); Up.start(u,p); assert(V(u,true)==view,report)
  Up.check(u,p,100); assert(V(u,true)==view,report)
 end
 u=Up.new('1.34'); Up.start(u,port({report='n importe quoi'})); assert(u.updated==nil and V(u,true)=='unchecked')
end
tests.UPDATE_RESTART_LATE=function()
 local u,p=ready({installed='1.33'}); Up.install(u,p,true); Up.tick(u,p,true,1000); Up.take(u,{})
 assert(u.phase=='restarting' and not u.restartLate)
 Up.tick(u,p,true,1000+Up.restartWait-1); assert(not u.restartLate)
 Up.tick(u,p,true,1000+Up.restartWait+1); assert(u.restartLate and events(u):find("l app n a pas redemarre",1,true))
end
tests.UPDATE_EVENTS_BOUNDED=function()
 local u=Up.new('1.33')
 for _=1,Up.eventsMax+10 do u.phase='downloading'; Up.cancel(u) end
 local out=Up.take(u,{}); assert(#out==Up.eventsMax and #u.events==0 and out[1][2]=='mise a jour: annulee avant toute copie')
end
-- Vrai port sans CSP (bancs de mesure, tests sans imitation) : inerte, rien n'est demandé, lu ni écrit.
tests.UPDATE_REMOTE_INERT=function()
 assert(rawget(_G,'web')==nil)
 local released=0; local p=Remote.new(function() released=released+1 end)
 assert(p.ready==false and p.marker()==nil and p.sourceVersion('backup')==nil and p.installedVersion()==nil and p.takeReport()==nil and p.mark('x')==false)
 assert(p.sourceComplete('backup')==false and p.boot()==nil and p.failed()==nil)
 local err; p.get('https://x',nil,function(e) err=e end); assert(err=='unavailable')
 local e2; p.stage('data',{},function(e) e2=e end); assert(e2=='unavailable')
 assert(p.snapshot('next')==false and p.place('next')==false)
 p.restart(); assert(released==1)
 p.log('x'); p.bootOk()
 local u=Up.new('1.33'); assert(Up.recover(p)==nil); Up.start(u,p,nil); assert(u.phase=='idle' and #u.events==0)
 -- Toutes les fonctions de CSP sauf web et JSON (ancien CSP) : inerte aussi, sans erreur.
 local f=Fake.install({})
 local ok,msg=pcall(function()
  rawset(_G,'web',nil); rawset(_G,'JSON',nil)
  local q=Remote.new(function() end); assert(q.app==f.root and q.ready==false and q.marker()==nil and q.sourceVersion('backup')==nil)
 end)
 f.restore(); assert(ok,msg)
end
-- Lance une installation complète sur l'imitation de CSP ; setup(f) avant, body(f,p,u) après.
local function onFake(options,setup,body)
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('1.33',{['tracks/spa.lua']='zones',['backup/old.txt']='old'}); f.release('1.34',options)
  if setup then setup(f) end
  local order={}; f.order=order
  f.onRestart=function() order[#order+1]='restartApp' end
  local p=Remote.new(function() order[#order+1]='release' end)
  local u=Up.new('1.33'); Up.start(u,p,Up.recover(p))
  body(f,p,u)
 end)
 f.restore(); assert(ok,err)
end
-- Installation de bout en bout (rappels asynchrones différés, téléchargement redirigé, corps binaire) : dossier de
-- travail hors de l'app, copie des fichiers remplacés, copie finale fichier par fichier d'un seul coup (manifeste en
-- dernier), aucun rechargement en direct ; puis démarrage surveillé et retour arrière.
tests.UPDATE_REMOTE_END_TO_END=function()
 onFake(nil,function(f)
  f.async=true
  -- Version précédente plus ancienne déjà gardée : remplacée d'un bloc, rien n'en reste.
  f.files[f.work..'/backup/SpotterEnginer.lua']='main 1.32'; f.files[f.work..'/backup/manifest.ini']='VERSION=1.32'
  f.files[f.work..'/backup/.files']='SpotterEnginer.lua\nmanifest.ini'
 end,function(f,p,u)
  -- Sauvegarde d'avant le repère .over, sans compte rendu qui la relie à la version installée : jamais proposée.
  assert(p.ready and p.app==f.root and p.installedVersion()=='1.33' and p.work==f.work and u.previous==nil)
  Up.check(u,p,0); f.flush(); assert(u.phase=='available' and u.release.notes[3]=='- Nouveau point')
  f.watch(); assert(Up.install(u,p,true)); f.flush()
  assert(u.phase=='ready','install: '..tostring(u.phase)..' '..tostring(u.error)..' '..tostring(u.detail))
  assert(f.find('redirect https://release-assets.githubusercontent.com/SpotterEnginer-1.34.zip'),'download redirected')
  local files=f.files
  -- Rien n'a encore changé dans le dossier de l'app ; paquet extrait, comparé et listé dans le travail.
  assert(files[f.root..'/SpotterEnginer.lua']=='main 1.33' and f.reloads==0)
  assert(files[f.work..'/next/'..Fake.prefix..'SpotterEnginer.lua']=='main 1.34' and files[f.work..'/next/'..Fake.prefix..'.files']:find('src/new.lua',1,true))
  assert(files[f.work..'/current/SpotterEnginer.lua']==nil,'nothing saved before the final copy')
  Up.tick(u,p,true,10)
  assert(u.phase=='restarting','tick: '..tostring(u.phase)..' '..tostring(u.detail))
  -- Sauvegarde : seulement les fichiers que la copie remplace (jamais le reste du dossier de l'app).
  assert(files[f.work..'/backup/SpotterEnginer.lua']=='main 1.33' and files[f.work..'/backup/tracks/spa.lua']==nil and files[f.work..'/backup/backup/old.txt']==nil)
  assert(files[f.work..'/backup/.over']=='1.34','previous version kept with the version it was taken under')
  -- Copie finale : fichiers changés, nouveau fichier, identiques jamais réécrits, manifeste en dernier, aucun rechargement,
  -- chaque fichier copié à côté puis mis en place, surveillance rétablie à la fin.
  assert(files[f.root..'/SpotterEnginer.lua']=='main 1.34' and files[f.root..'/src/ui.lua']=='ui 1.34' and files[f.root..'/src/new.lua']=='new 1.34')
  assert(files[f.root..'/sounds/beep.wav']=='wav' and not f.find('copy sounds/beep.wav.new') and files[f.root..'/tracks/spa.lua']=='zones')
  assert(f.last('move ')==f.find('move manifest.ini') and f.find('move src/ui.lua')<f.find('move SpotterEnginer.lua') and Up.manifestVersion(files[f.root..'/manifest.ini'])=='1.34')
  assert(files[f.root..'/src/ui.lua.new']==nil and files[f.root..'/manifest.ini.new']==nil,'no temporary file left')
  assert(f.reloads==0,'live reloads: '..f.reloads)
  assert(f.last('pause ')==f.last('pause false') and f.last('pause false')>f.find('move manifest.ini'),'file watching resumed after the copy')
  -- Version précédente promue d'un bloc, repère levé, compte rendu écrit, démarrage surveillé ; radio arrêtée, son rendu, puis redémarrage.
  assert(f.find('movedir state:SpotterEnginer-update/backup'),'promoted by renaming the folder')
  for path in pairs(files) do assert(not path:find('/backup.old/',1,true),'older backup cleared: '..path) end
  assert(files[f.work..'/installing.txt']==nil and files[f.work..'/updated.txt']=='update 1.33 -> 1.34' and files[f.work..'/boot.txt']=='1.34\n0\n1.33')
  assert(f.order[1]=='release' and f.order[2]=='restartApp' and #f.order==2 and f.restarts==1)
  -- Lancement suivant : compte rendu, version précédente proposée, première image : surveillance levée ; retour arrière.
  local p2=Remote.new(function() end)
  local u2=Up.new('1.34'); Up.start(u2,p2,Up.recover(p2)); assert(u2.updated.kind=='update' and u2.previous=='1.33' and files[f.work..'/updated.txt']==nil)
  assert(files[f.work..'/boot.txt']=='1.34\n1\n1.33','boot counted'); p2.bootOk(); assert(files[f.work..'/boot.txt']==nil,'boot confirmed')
  f.watch(); assert(Up.rollback(u2,p2,true) and u2.phase=='rollbackReady'); Up.tick(u2,p2,true,0); assert(u2.phase=='restarting')
  assert(files[f.root..'/SpotterEnginer.lua']=='main 1.33' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='1.33' and f.reloads==0)
  assert(files[f.work..'/updated.txt']=='rollback 1.34 -> 1.33' and files[f.work..'/installing.txt']==nil and f.restarts==2)
  -- Page de la version : seulement une adresse https.
  p.open(u.release.page); p.open('file:///c:/x'); assert(#f.opened==1 and f.opened[1]==u.release.page)
 end)
end
-- Démarrage surveillé par le vrai port : deux lancements sans première image, puis retour automatique à la version
-- précédente au troisième, avant tout autre module.
tests.UPDATE_REMOTE_BOOT_WATCH=function()
 onFake(nil,nil,function(f,p,u)
  Up.check(u,p,0); Up.install(u,p,true); Up.tick(u,p,true,1); assert(u.phase=='restarting')
  local files=f.files
  for launch=1,2 do local q=Remote.new(function() end); assert(Up.recover(q)==nil,'launch '..launch) end
  assert(files[f.work..'/boot.txt']=='1.34\n2\n1.33')
  local q=Remote.new(function() end); local r=Up.recover(q)
  assert(r and r.outcome=='autorollback' and r.restart and Up.manifestVersion(files[f.root..'/manifest.ini'])=='1.33' and files[f.root..'/SpotterEnginer.lua']=='main 1.33')
  assert(files[f.work..'/boot.txt']==nil and files[f.work..'/installing.txt']==nil and files[f.work..'/updated.txt']=='rollback 1.34 -> 1.33 auto')
 end)
end
-- Échecs du vrai port : la version installée reste intacte (ou remise en place aussitôt), sans repère qui traîne.
tests.UPDATE_REMOTE_FAILURES=function()
 local function intact(f) local files=f.files; return files[f.root..'/SpotterEnginer.lua']=='main 1.33' and files[f.root..'/src/ui.lua']=='ui 1.33' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='1.33' and files[f.work..'/installing.txt']==nil end
 local function run(options,setup,check)
  onFake(options,setup,function(f,p,u) Up.check(u,p,0); f.flush(); Up.install(u,p,true); f.flush(); Up.tick(u,p,true,10); check(f,u) end)
 end
 run({actual=string.rep('cd',32)},nil,function(f,u) assert(u.error=='integrity' and intact(f) and f.files[f.work..'/current/SpotterEnginer.lua']==nil) end)
 run({size=999},nil,function(f,u) assert(u.error=='integrity' and u.detail:find('taille',1,true) and intact(f)) end)
 run({entries={['apps/lua/SpotterEnginer/../../evil.lua']='x'}},nil,function(f,u) assert(u.error=='content' and intact(f)) end)
 run({entries={[Fake.prefix..'src/remote.lua']=false}},nil,function(f,u) assert(u.error=='content' and intact(f)) end)
 run({entries={[Fake.prefix..'src/ui.lua']="local G=require('src/groups')"}},nil,function(f,u) assert(u.error=='content' and u.detail=='module absent : src/groups' and intact(f)) end)
 run(nil,function(f) f.corruptExtract=Fake.prefix..'src/ui.lua' end,function(f,u) assert(u.error=='write' and u.detail:find('different du paquet : src/ui.lua',1,true) and intact(f)) end)
 run(nil,function(f) f.failExtract=true end,function(f,u) assert(u.error=='write' and u.detail:find('extraction',1,true) and intact(f) and f.restarts==0) end)
 run(nil,function(f) f.failCopy=f.work..'/current/src/ui.lua' end,function(f,u) assert(u.error=='write' and u.detail=='sauvegarde : src/ui.lua' and intact(f)) end)
 -- Fichier de l'app ouvert (verrouillé) pendant la copie finale : remise en place aussitôt, version conservée, aucun
 -- fichier temporaire laissé.
 run(nil,function(f) f.locked[f.root..'/src/ui.lua']=true end,function(f,u)
  assert(u.error=='write' and u.detail=='src/ui.lua' and f.files[f.root..'/SpotterEnginer.lua']=='main 1.33' and Up.manifestVersion(f.files[f.root..'/manifest.ini'])=='1.33',
   'locked: '..u.phase..' '..u.error..' '..u.detail..' '..tostring(f.files[f.root..'/SpotterEnginer.lua']))
  assert(f.files[f.work..'/installing.txt']==nil,'marker'); assert(f.restarts==0,'restarts')
  assert(f.files[f.work..'/backup/SpotterEnginer.lua']==nil,'backup'); assert(f.files[f.root..'/src/ui.lua.new']==nil,'tmp')
 end)
 -- Fichier de l'app illisible (copie de sauvegarde refusée) : rien n'est copié dans l'app.
 run(nil,function(f) f.unreadable[f.root..'/src/ui.lua']=true end,function(f,u) assert(u.error=='write' and u.detail=='sauvegarde : src/ui.lua' and intact(f)) end)
 -- Fichier en lecture seule dans l'app : refusé de même.
 run(nil,function(f) f.readonly[f.root..'/src/remote.lua']=true end,function(f,u) assert(u.error=='write' and u.detail=='src/remote.lua' and intact(f)) end)
 -- Repère en lecture seule (ni réécrit ni effacé) : rien n'est copié dans l'app.
 run(nil,function(f) f.readonly[f.work..'/installing.txt']=true end,function(f,u) assert(u.error=='write' and u.detail=='repere' and intact(f)) end)
 -- Surveillance de CSP qui reprend seule pendant une longue copie : réaffirmée, aucun rechargement.
 run(nil,function(f) f.watch(); f.autoResume=6 end,function(f,u) assert(u.phase=='restarting' and f.reloads==0,'reloads '..f.reloads..' '..tostring(u.detail)) end)
 -- Renommage de dossier refusé : version précédente gardée par copie vérifiée.
 run(nil,function(f) f.failDirMove=true end,function(f,u) assert(u.phase=='restarting' and f.files[f.work..'/backup/SpotterEnginer.lua']=='main 1.33' and f.files[f.work..'/current/SpotterEnginer.lua']==nil) end)
end
-- Reprise au chargement par le vrai port : copie interrompue (fichiers mêlés, manifeste encore ancien) terminée depuis
-- le paquet extrait ; sans lui, version de départ remise en place ; rien à reprendre ensuite. Promotion rejouée sans
-- dégât. Restes de la 1.33/1.34.
tests.UPDATE_REMOTE_RECOVERY=function()
 local function source(f,root,map) local names={}; for k,val in pairs(map) do f.files[root..'/'..k]=val; names[#names+1]=k end; f.files[root..'/.files']=table.concat(names,'\n') end
 onFake(nil,nil,function(f,p)
  local files=f.files
  source(f,f.work..'/next/'..Fake.prefix:gsub('/$',''),{['manifest.ini']='VERSION=1.34',['SpotterEnginer.lua']='main 1.34',['src/update.lua']='update 1.34',['src/remote.lua']='remote 1.34',['src/ui.lua']='ui 1.34'})
  source(f,f.work..'/current',{['manifest.ini']='VERSION=1.33',['SpotterEnginer.lua']='main 1.33',['src/ui.lua']='ui 1.33'})
  files[f.root..'/src/ui.lua']='ui 1.34'; files[f.work..'/installing.txt']='update 1.33 -> 1.34'
  -- Coupure au milieu d'un remplacement : fichier temporaire à moitié écrit, jamais pris pour le vrai.
  files[f.root..'/src/remote.lua.new']='remo'
  local r=Up.recover(p)
  assert(r.outcome=='completed' and files[f.root..'/SpotterEnginer.lua']=='main 1.34' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='1.34')
  assert(files[f.root..'/src/remote.lua']=='remote 1.34' and files[f.root..'/src/remote.lua.new']==nil)
  assert(files[f.work..'/installing.txt']==nil and files[f.work..'/updated.txt']=='update 1.33 -> 1.34' and files[f.work..'/backup/SpotterEnginer.lua']=='main 1.33')
  assert(Up.recover(p)==nil,'nothing left to recover')
  -- Promotion rejouée (plantage juste après elle) : version précédente intacte.
  assert(p.promote('update') and files[f.work..'/backup/SpotterEnginer.lua']=='main 1.33' and p.sourceComplete('backup'))
 end)
 onFake(nil,nil,function(f,p)
  local files=f.files
  source(f,f.work..'/current',{['manifest.ini']='VERSION=1.33',['SpotterEnginer.lua']='main 1.33',['src/ui.lua']='ui 1.33'})
  files[f.root..'/src/ui.lua']='ui 1.34'; files[f.work..'/installing.txt']='update 1.33 -> 1.34'
  local r=Up.recover(p)
  assert(r.outcome=='restored' and files[f.root..'/src/ui.lua']=='ui 1.33' and files[f.work..'/updated.txt']=='recovered 1.33 -> 1.34')
 end)
 -- Version précédente incomplète (un fichier manquant) : jamais proposée ni utilisée.
 onFake(nil,function(f)
  local names={}; for k,val in pairs({['manifest.ini']='VERSION=1.32',['SpotterEnginer.lua']='main 1.32'}) do f.files[f.work..'/backup/'..k]=val; names[#names+1]=k end
  names[#names+1]='src/ui.lua'; f.files[f.work..'/backup/.files']=table.concat(names,'\n')
 end,function(_,p,u) assert(u.previous==nil and not p.sourceComplete('backup') and not Up.rollback(u,p,true)) end)
end
-- 1.36 (3e relecture) : dossiers vides effacés avec leurs fichiers ; trois mises à jour de suite, la version
-- précédente est chaque fois renommée d'un bloc (jamais la copie de repli).
tests.UPDATE_REMOTE_REPEATED_136=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('1.33')
  for round,v in ipairs({'1.34','1.35','1.36'}) do
   f.release(v)
   local installed=Up.manifestVersion(f.files[f.root..'/manifest.ini'])
   local p=Remote.new(function() end)
   local u=Up.new(installed); Up.start(u,p,Up.recover(p)); p.bootOk()
   Up.check(u,p,0); f.flush(); assert(u.phase=='available','round '..round..': '..tostring(u.phase))
   f.watch(); assert(Up.install(u,p,true)); f.flush(); assert(u.phase=='ready','round '..round..' install: '..tostring(u.phase)..' '..tostring(u.detail))
   local before=#f.calls
   Up.tick(u,p,true,10); assert(u.phase=='restarting','round '..round..' tick: '..tostring(u.phase)..' '..tostring(u.detail))
   local renamed,copied=false,false
   for k=before+1,#f.calls do
    local c=f.calls[k]
    if c=='movedir state:SpotterEnginer-update/backup' then renamed=true end
    if c:find('^copy state:SpotterEnginer%-update/backup/') then copied=true end
   end
   assert(renamed and not copied,'round '..round..': previous version renamed in one go, never copied')
   assert(Up.manifestVersion(f.files[f.root..'/manifest.ini'])==v,'round '..round..': installed '..v)
   for path in pairs(f.dirs) do assert(not path:find('/backup.old',1,true),'round '..round..': backup.old left: '..path) end
  end
 end)
 f.restore(); assert(ok,err)
end
-- 1.36 : copie finie (ou refaite) par la reprise du lancement : version installée surveillée à son démarrage.
tests.UPDATE_RECOVER_BOOT_136=function()
 local p=port({marked='update 1.33 -> 1.34',installed='1.34'})
 local r=Up.recover(p); assert(r.outcome=='finished' and p.boots and p.boots[1]=='1.34' and p.boots[2]==1 and p.boots[3]=='1.33','finished: watched, this launch counted')
 p=port({marked='update 1.33 -> 1.34',installed='1.33'})
 r=Up.recover(p); assert(r.outcome=='completed' and r.restart and p.boots and p.boots[1]=='1.34' and p.boots[2]==0,'completed: watched from its first start')
 p=port({marked='rollback 1.34 -> 1.33',installed='1.33',boot={'1.34',1,'1.33'}})
 r=Up.recover(p); assert(r.outcome=='finished' and p.boots==nil,'rollback finished: watch cleared')
end
-- 1.37 : état réel du disque du pilote après la mise à jour 1.35 -> 1.36 (version précédente gardée, paquet extrait
-- jamais effacé, boot.txt.bak) : nettoyé au lancement suivant ; la version précédente reste entière.
tests.UPDATE_TIDY_USER_STATE_137=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('1.36')
  local W=f.work
  local back={'SpotterEnginer.lua','manifest.ini','src/update.lua'}
  for _,rel in ipairs(back) do f.files[W..'/backup/'..rel]=rel=='manifest.ini' and 'VERSION=1.35' or 'old '..rel end
  f.files[W..'/backup/.files']=table.concat(back,'\n'); f.files[W..'/backup/.over']='1.36'
  local nxt=W..'/next/'..Fake.prefix
  for _,rel in ipairs({'SpotterEnginer.lua','manifest.ini','src/update.lua','src/remote.lua','src/ui.lua'}) do f.files[nxt..rel]='new '..rel end
  f.files[nxt..'.files']='SpotterEnginer.lua\nmanifest.ini\nsrc/update.lua\nsrc/remote.lua\nsrc/ui.lua'
  f.files[W..'/boot.txt.bak']='1.36\n0\n1.35'
  local p=Remote.new(function() end)
  local u=Up.new('1.36'); Up.start(u,p,Up.recover(p))
  for path in pairs(f.files) do assert(not path:find(W..'/next',1,true) and path~=W..'/boot.txt.bak','left: '..path) end
  for path in pairs(f.dirs) do assert(not path:find(W..'/next',1,true),'folder left: '..path) end
  for _,rel in ipairs(back) do assert(f.files[W..'/backup/'..rel],'previous version kept: '..rel) end
  assert(f.files[W..'/backup/.over']=='1.36','.over kept by the cleaning')
  assert(u.previous=='1.35','rollback still offered')
  assert(events(u):find('mise a jour: nettoyage (7 fichiers)',1,true),events(u))
  local u2=Up.new('1.36'); Up.start(u2,p,Up.recover(p)); assert(not events(u2):find('nettoyage',1,true),'nothing left to clean')
  -- Démarrage surveillé ou repère en cours : rien n'est effacé.
  f.files[W..'/next/x']='x'; f.files[W..'/boot.txt']='1.36\n1\n1.35'
  assert(Up.tidy(Up.new('1.36'),p)==0 and f.files[W..'/next/x'],'boot watched: nothing removed')
  f.files[W..'/boot.txt']=nil; f.files[W..'/installing.txt']='update 1.35 -> 1.36'
  assert(Up.tidy(Up.new('1.36'),p)==0 and f.files[W..'/next/x'],'marker pending: nothing removed')
  -- Version précédente incomplète : la copie current/ peut en être la seule trace, gardée ; complète : effacée.
  f.files[W..'/installing.txt']=nil; f.files[W..'/current/a.lua']='a'; f.files[W..'/current/.files']='a.lua'
  local kept=f.files[W..'/backup/src/update.lua']; f.files[W..'/backup/src/update.lua']=nil
  Up.tidy(Up.new('1.36'),p); assert(f.files[W..'/current/a.lua'] and not f.files[W..'/next/x'],'backup incomplete: current kept, next removed')
  f.files[W..'/backup/src/update.lua']=kept
  Up.tidy(Up.new('1.36'),p); assert(not f.files[W..'/current/a.lua'] and f.files[W..'/backup/src/update.lua'],'backup complete: current removed')
 end)
 f.restore(); assert(ok,err)
end
-- 1.37 : mises à jour successives par le vrai port : rien d'autre que la version précédente ne reste ; aucun .bak,
-- même juste après le lancement qui compte le démarrage (boot.txt réécrit).
tests.UPDATE_NO_LEFTOVERS_137=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('1.34')
  for round,v in ipairs({'1.35','1.36','1.37'}) do
   f.release(v)
   local installed=Up.manifestVersion(f.files[f.root..'/manifest.ini'])
   local p=Remote.new(function() end)
   local u=Up.new(installed); Up.start(u,p,Up.recover(p)); p.bootOk(); Up.tidy(u,p)
   Up.check(u,p,0); f.flush(); f.watch(); assert(Up.install(u,p,true)); f.flush(); Up.tick(u,p,true,10)
   assert(u.phase=='restarting','round '..round..': '..tostring(u.phase)..' '..tostring(u.detail))
   local p2=Remote.new(function() end); local u2=Up.new(v); Up.start(u2,p2,Up.recover(p2))
   assert(f.files[f.work..'/boot.txt'] and not f.files[f.work..'/boot.txt.bak'],'round '..round..': boot counted, no .bak')
   p2.bootOk(); Up.tidy(u2,p2)
   for path in pairs(f.files) do
    if path:sub(1,#f.work)==f.work then
     local rest=path:sub(#f.work+2)
     assert(rest:sub(1,7)=='backup/' and not rest:find('%.bak$') and not rest:find('%.new$'),'round '..round..' left: '..rest)
    end
   end
   for path in pairs(f.dirs) do assert(not path:find('/next',1,true) and not path:find('/current',1,true) and not path:find('backup.old',1,true),'round '..round..' folder left: '..path) end
  end
 end)
 f.restore(); assert(ok,err)
end
-- 1.37 : la copie de la version installée ne garde que les fichiers que la mise à jour remplace (le manifeste
-- toujours) ; les fichiers identiques ne sont ni copiés ni gardés.
tests.UPDATE_SNAPSHOT_CHANGED_137=function()
 local f=Fake.install({})
 local ok,err=pcall(function()
  f.app('1.36'); f.release('1.37')
  local p=Remote.new(function() end); local u=Up.new('1.36'); Up.start(u,p,Up.recover(p))
  Up.check(u,p,0); f.flush(); f.watch(); assert(Up.install(u,p,true)); f.flush()
  local before=#f.calls; Up.tick(u,p,true,10); assert(u.phase=='restarting',tostring(u.phase))
  local saved={}
  for k=before+1,#f.calls do local rel=f.calls[k]:match('^copy state:SpotterEnginer%-update/current/(.*)$'); if rel then saved[#saved+1]=rel end end
  table.sort(saved)
  assert(table.concat(saved,',')=='SpotterEnginer.lua,manifest.ini,src/remote.lua,src/ui.lua,src/update.lua',table.concat(saved,','))
  assert(f.files[f.work..'/backup/sounds/beep.wav']==nil and f.files[f.work..'/backup/SpotterEnginer.lua']=='main 1.36','unchanged file not kept')
  assert(events(u):find('5 fichiers gardes',1,true),events(u))
 end)
 f.restore(); assert(ok,err)
end
-- 1.47 : CSP a fait tourner l'ancien code (1.44) alors que le disque portait la 1.45 ; la mise à jour a écrit
-- « 1.45 -> 1.45 ». Le compte rendu porte la version qui tournait ; le repère garde celle du disque (reprise).
tests.UPDATE_REPORT_RUNNING_147=function()
 local u,p=ready({installed='1.34'})
 assert(u.installed=='1.33' and Up.install(u,p,true)); Up.tick(u,p,true,200)
 assert(find(p.calls,'mark update 1.34 -> 1.34'),'marker: version on disk (recovery)')
 assert(find(p.calls,'report update 1.33 -> 1.34'),'report: version that was running')
 u,p=ready({installed='1.33'}); Up.install(u,p,true); Up.tick(u,p,true,200)
 assert(find(p.calls,'report update 1.33 -> 1.34') and find(p.calls,'mark update 1.33 -> 1.34'),'same versions: unchanged')
end
-- Compatibilité (SpotterEnginer dépend d'AdvancedIA) : le pont du paquet doit être celui d'AdvancedIA installé, avant
-- tout téléchargement copié ; même règle pour le retour arrière ; refus dit et publié pour l'accueil d'AdvancedIA.
tests.UPDATE_COMPATIBILITY=function()
 assert(Up.bridgeVersion(LAYOUT)==1 and Up.bridgeVersion('x')==nil and Up.bridgeVersion(nil)==nil)
 assert(Up.compatible(LAYOUT,LAYOUT)==true)
 local ok,why=Up.compatible(layout(2),LAYOUT); assert(not ok and why=='aaiOld')
 ok,why=Up.compatible(LAYOUT,layout(2)); assert(not ok and why=='aaiNewer')
 ok,why=Up.compatible(LAYOUT,nil); assert(not ok and why=='aaiMissing')
 ok,why=Up.compatible('rien',LAYOUT); assert(not ok and why=='layout')
 assert(Up.manifestKey('[ABOUT]\nVERSION=1.2.0\nREQUIRES_ADVANCEDIA=Beta 1.52 \n','REQUIRES_ADVANCEDIA')=='Beta 1.52')
 assert(Up.manifestKey('VERSION=1','REQUIRES_ADVANCEDIA')==nil)
 -- Paquet qui attend un pont plus récent : refusé, rien de copié, raison et version requise d'AdvancedIA gardées.
 local u,p=ready({pkgLayout=layout(2),manifest='[ABOUT]\nVERSION=1.34\nREQUIRES_ADVANCEDIA=Beta 1.52\n'})
 assert(Up.install(u,p,true)==true)
 assert(u.phase=='failed' and u.error=='aaiOld' and Up.view(u,true)=='aaiOld' and u.release.needs=='Beta 1.52')
 assert(not find(p.calls,'stage') and not find(p.calls,'snapshot'),'nothing staged or copied')
 assert(events(u):find('mettez d abord AdvancedIA a jour',1,true))
 assert(Up.status(u,true)=='v=1;installed=1.33;latest=1.34;state=incompatible;needs=Beta 1.52',Up.status(u,true))
 -- AdvancedIA plus récent que le paquet, ou absent : refusé aussi.
 u,p=ready({aai=layout(2)}); Up.install(u,p,true); assert(u.error=='aaiNewer' and Up.view(u,true)=='aaiNewer')
 u,p=ready({aai=false}); Up.install(u,p,true); assert(u.error=='aaiMissing')
 -- Même pont : installé ; état publié « available » avant l'installation.
 u,p=ready({}); assert(Up.status(u,true)=='v=1;installed=1.33;latest=1.34;state=available',Up.status(u,true))
 Up.install(u,p,true); Up.tick(u,p,true,200); assert(u.phase=='restarting')
 -- Retour arrière vers une version qui attendait un autre pont : refusé.
 u,p=ready({backup='1.32',over='1.33',backupLayout=layout(0)}); u.previous='1.32'
 assert(Up.rollback(u,p,true)==false and u.error=='aaiNewer')
 u,p=ready({backup='1.32',over='1.33'}); u.previous='1.32'; assert(Up.rollback(u,p,true)==true and u.phase=='rollbackReady')
 -- À jour : publié « uptodate » ; état d'avant toute vérification : rien.
 assert(Up.status(Up.new('1.34'),true)==nil)
end
-- La version précédente ne garde que les fichiers qu'une mise à jour a remplacés ; elle n'est proposée que
-- par-dessus la version que cette mise à jour a installée (.over). Installée à la main depuis : plus proposée (elle
-- mêlerait deux versions). Sauvegarde d'avant ce repère : gardée seulement si le compte rendu du lancement la relie
-- à la version installée, et le repère est alors écrit.
tests.UPDATE_ROLLBACK_OVER=function()
 local function started(version,o) local p=port(o); local u=Up.new(version); Up.start(u,p); return u,p end
 local u,p=started('1.34',{backup='1.33',installed='1.34'}); assert(u.previous=='1.33')
 u=started('1.35',{backup='1.33',over='1.34'}); assert(u.previous==nil,'another version installed by hand since')
 u=started('1.34',{backup='1.33',over=false}); assert(u.previous==nil,'older backup, nothing proves it')
 u,p=started('1.34',{backup='1.33',over=false,report='update 1.33 -> 1.34'})
 assert(u.previous=='1.33' and find(p.calls,'over backup 1.34'),'older backup proven by the report of this launch')
 u,p=started('1.34',{backup='1.33',over=false,report='update 1.32 -> 1.34'}); assert(u.previous==nil and p.over==nil,'report from another version')
 u,p=started('1.35',{backup='1.33',over=false,report='update 1.33 -> 1.34'}); assert(u.previous==nil and p.over==nil,'report to another version')
 u,p=started('1.34',{backup='1.33',over=false,report='rollback 1.35 -> 1.34'}); assert(u.previous==nil and p.over==nil,'a rollback proves nothing')
 -- Port d'une version d'avant le repère (copie interrompue, modules de deux versions) : rien de proposé, aucune erreur.
 p=port({backup='1.33'}); p.sourceOver=nil; p.sourceSetOver=nil; p.sourceListed=nil; p.sourceText=nil
 u=Up.new('1.34'); Up.start(u,p); assert(u.previous==nil)
 Up.tick(u,p,true,1); assert(Up.status(u,true)==nil)
 -- Sauvegarde changée depuis le lancement : retour arrière refusé sans rien copier.
 local o={backup='1.33',installed='1.34'}; u,p=started('1.34',o); o.over='1.35'
 assert(not Up.rollback(u,p,true) and u.error=='write' and not find(p.calls,'snapshot'))
 -- Vrai port : mise à jour, puis autre version installée à la main, puis sauvegarde d'avant le repère.
 onFake(nil,nil,function(f,p0,u0)
  Up.check(u0,p0,0); Up.install(u0,p0,true); Up.tick(u0,p0,true,1); assert(u0.phase=='restarting')
  local files=f.files
  local function launch(v) local q=Remote.new(function() end); local w=Up.new(v); Up.start(w,q,Up.recover(q)); q.bootOk(); return w,q end
  local w,q=launch('1.34'); assert(w.previous=='1.33' and q.sourceOver('backup')=='1.34')
  f.app('1.35'); w,q=launch('1.35')
  assert(w.previous==nil and not Up.rollback(w,q,true),'1.35 installed by hand: the 1.33 files would mix with it')
  Up.tick(w,q,true,5); assert(files[f.root..'/SpotterEnginer.lua']=='main 1.35' and files[f.work..'/backup/SpotterEnginer.lua']=='main 1.33')
  f.app('1.34'); w=launch('1.34'); assert(w.previous=='1.33','same version back: offered again')
  files[f.work..'/backup/.over']=nil; w=launch('1.34'); assert(w.previous==nil,'older backup without proof')
  files[f.work..'/updated.txt']='update 1.33 -> 1.34'; w=launch('1.34')
  assert(w.previous=='1.33' and files[f.work..'/backup/.over']=='1.34','older backup proven by the report, marker written')
  w,q=launch('1.34'); assert(w.previous=='1.33','kept at the next launches')
  assert(Up.rollback(w,q,true)); Up.tick(w,q,true,9); assert(w.phase=='restarting' and Up.manifestVersion(files[f.root..'/manifest.ini'])=='1.33')
 end)
end
-- État publié pour AdvancedIA : jamais le texte d'avant resté dans ac.store. Après une mise à jour réussie
-- (redémarrage, compte rendu), une réponse 404, un retour arrière ; valeur du manifeste assainie ; texte refait
-- seulement quand l'état change.
tests.UPDATE_STATUS_STATES=function()
 local S=Up.status
 -- Redémarrage après la copie : la version en place est déjà la nouvelle.
 local u,p=ready({installed='1.33'}); Up.install(u,p,true); Up.tick(u,p,true,10)
 assert(u.phase=='restarting' and S(u,true)=='v=1;installed=1.34;latest=1.34;state=uptodate',S(u,true))
 -- Lancement suivant : compte rendu affiché, état publié « uptodate » avant, pendant et après la vérification.
 p=port({report='update 1.33 -> 1.34',backup='1.33'}); u=Up.new('1.34'); Up.start(u,p)
 assert(Up.view(u,true)=='success' and S(u,true)=='v=1;installed=1.34;latest=1.34;state=uptodate',S(u,true))
 p.hold=true; Up.check(u,p,100); assert(S(u,true)=='v=1;installed=1.34;latest=1.34;state=checking',S(u,true))
 p.flush(); assert(u.phase=='current' and S(u,true)=='v=1;installed=1.34;latest=1.34;state=uptodate',S(u,true))
 -- Retour arrière : la version quittée est connue plus récente ; installation rattrapée : celle à refaire.
 p=port({report='rollback 1.34 -> 1.33'}); u=Up.new('1.33'); Up.start(u,p)
 assert(S(u,true)=='v=1;installed=1.33;latest=1.34;state=available',S(u,true))
 p=port({report='recovered 1.33 -> 1.34'}); u=Up.new('1.33'); Up.start(u,p)
 assert(S(u,true)=='v=1;installed=1.33;latest=1.34;state=available',S(u,true))
 -- Retour arrière en cours : état d'avant gardé (rien d'écrit), puis version rétablie, la plus récente connue proposée.
 local o={backup='1.33',installed='1.34'}; p=port(o); u=Up.new('1.34'); Up.start(u,p); Up.check(u,p,100)
 assert(S(u,true)=='v=1;installed=1.34;latest=1.34;state=uptodate')
 Up.rollback(u,p,true); assert(S(u,true)==nil); Up.tick(u,p,true,200)
 assert(u.phase=='restarting' and S(u,true)=='v=1;installed=1.33;latest=1.34;state=available',S(u,true))
 -- Aucune version publiée (404) : jamais « checking » pour toujours.
 u=Up.new('1.33'); p=port({apiStatus=404}); p.hold=true; Up.check(u,p,100); assert(S(u,true)=='v=1;installed=1.33;latest=1.33;state=checking')
 p.flush(); assert(u.phase=='none' and S(u,true)=='v=1;installed=1.33;latest=1.33;state=uptodate',S(u,true))
 -- Erreurs et état terminal.
 u=Up.new('1.33'); Up.check(u,port({apiStatus=500}),100); assert(S(u,true)=='v=1;installed=1.33;latest=1.33;state=error',S(u,true))
 u=Up.new('1.33'); u.phase='broken'; assert(S(u,true)=='v=1;installed=1.33;latest=1.33;state=error')
 -- Retour arrière refusé (en conduite, pont) : rien de publié (surtout pas « incompatible » ni « needs=? »).
 u,p=ready({backup='1.32',over='1.33',backupLayout=layout(0)}); u.previous='1.32'
 local before=S(u,true); assert(before=='v=1;installed=1.33;latest=1.34;state=available')
 assert(not Up.rollback(u,p,true) and u.error=='aaiNewer' and S(u,true)==nil)
 assert(not Up.rollback(u,p,false) and u.error=='driving' and S(u,false)==nil)
 -- Le refus suivant d'une installation est de nouveau publié.
 assert(not Up.install(u,p,false) and S(u,false)==before)
 -- Valeur lue dans le manifeste du paquet : aucun séparateur du contrat, longueur bornée, 200 octets au plus.
 u,p=ready({pkgLayout=layout(2),manifest='[ABOUT]\nVERSION=1.34\nREQUIRES_ADVANCEDIA=Beta 1.52;state=uptodate\n'}); Up.install(u,p,true)
 assert(S(u,true)=='v=1;installed=1.33;latest=1.34;state=incompatible;needs=Beta 1.52 state uptodate',S(u,true))
 u,p=ready({pkgLayout=layout(2),manifest='[ABOUT]\nVERSION=1.34\nREQUIRES_ADVANCEDIA='..string.rep('é',300)..'\n'}); Up.install(u,p,true)
 local text=S(u,true); local needs=text:match(';needs=(.*)$')
 assert(#text<=Up.statusMax and #needs<=Up.needsMax and needs==string.rep('é',math.floor(Up.needsMax/2)),text)
 -- Texte refait seulement quand l'état change (appelé à chaque image).
 p=port({report='rollback 1.34 -> 1.33'}); u=Up.new('1.33'); Up.start(u,p)
 local newer,calls=Up.newer,0
 Up.newer=function(a,b) calls=calls+1; return newer(a,b) end
 local ok,err=pcall(function()
  local first=S(u,true); local n=calls
  for _=1,50 do assert(S(u,true)==first and S(u,false)==first) end
  assert(n>0 and calls==n,'status rebuilt '..(calls-n)..' times')
  p.hold=true; Up.check(u,p,100); assert(S(u,true)=='v=1;installed=1.33;latest=1.33;state=checking',S(u,true))
 end)
 Up.newer=newer; assert(ok,err)
end
-- Le pont est recontrôlé à l'image de la copie (paquet extrait gardé, AdvancedIA mis à jour entre-temps) ; un
-- pont gardé dans la version précédente mais illisible refuse le retour arrière (jamais jugé sur celui de l'app).
tests.UPDATE_BRIDGE_RECHECK=function()
 local o={installed='1.33'}; local u,p=ready(o)
 Up.install(u,p,true); Up.tick(u,p,false,10); assert(u.phase=='available' and u.release.staged)
 o.aai=layout(2); o.manifest='[ABOUT]\nVERSION=1.34\nREQUIRES_ADVANCEDIA=Beta 1.60\n'
 assert(Up.install(u,p,true) and u.phase=='ready'); Up.tick(u,p,true,20)
 assert(u.phase=='failed' and u.error=='aaiNewer' and u.release.needs=='Beta 1.60' and not find(p.calls,'snapshot') and p.marked==nil)
 assert(Up.status(u,true)=='v=1;installed=1.33;latest=1.34;state=incompatible;needs=Beta 1.60')
 -- Pont revenu : le paquet gardé s'installe sans nouveau téléchargement.
 o.aai=nil; local downloads=count(p.calls,'get '..u.release.zip.url)
 assert(Up.install(u,p,true)); Up.tick(u,p,true,30); assert(u.phase=='restarting' and count(p.calls,'get '..u.release.zip.url)==downloads)
 -- Retour arrière : pont listé dans la version précédente mais illisible.
 u,p=ready({backup='1.32',over='1.33',backupListed=true}); u.previous='1.32'
 assert(not Up.rollback(u,p,true) and u.error=='layout')
 -- Pont non gardé (identique dans les deux versions) : celui de l'app.
 u,p=ready({backup='1.32',over='1.33'}); u.previous='1.32'; assert(Up.rollback(u,p,true))
end
-- Chemins et noms que Windows changerait, doublons à la casse près, tags et adresses de téléchargement.
tests.UPDATE_PATHS_AND_TAGS=function()
 local function with(x) local t=entries(); t[#t+1]=x; return t end
 for _,bad in ipairs({'manifest.ini.','src/x.lua ','src./x.lua','docs /x.md','CON','src/nul.lua','aux.txt','fonts/COM1','src/lpt9.tar.gz','src/a\tb.lua','src/a?.lua','src/a*.lua','src/a|b','src/<a>','src/"a"'}) do
  assert(not Up.content(with(Up.prefix..bad)),bad); assert(not Up.safeRel(bad),bad)
 end
 for _,good in ipairs({'docs/notes..md','vox/FR/01_vert.wav','src/console.lua','fonts/common/a b.ttf','.gitkeep','src/com10.lua'}) do
  assert(Up.content(with(Up.prefix..good)),good); assert(Up.safeRel(good),good)
 end
 -- Deux entrées pour un seul fichier sous Windows.
 assert(not Up.content(with(Up.prefix..'SRC/Update.lua')) and not Up.content(with(Up.prefix..'manifest.ini')))
 assert(not Up.safeRel('') and not Up.safeRel(nil) and not Up.safeRel('/a') and not Up.safeRel('a//b') and not Up.safeRel('a/../b') and not Up.safeRel('C:/a') and not Up.safeRel('a\\b'))
 -- Liste des fichiers d'une source (src/remote.lua) : même règle par segment.
 local L=Remote.parseList
 assert(#L('docs/notes..md\nsrc/a.lua\r\n')==2 and L('')==nil and L(nil)==nil)
 for _,bad in ipairs({'../x','a/../b','/a','a\\b','C:/x','a/b./c','a /b','a//b','..'}) do assert(L('src/ok.lua\n'..bad)==nil,bad) end
 -- Tags : un numéro à point, caractères simples ; adresse exacte du tag, dans ce dépôt.
 for _,tag in ipairs({'2026','release-12','v1.34 beta','v1.34/x','v1.34?x','','v'}) do assert(not Up.release(release({tag_name=tag})),tag) end
 local a=release({tag_name='v1.34.0'}); assert(not Up.release(a),'assets of another tag')
 a=release(); a.assets[1].browser_download_url=Up.download..'v1.34/../../../../Autre/Depot/releases/download/v1.34/SpotterEnginer-1.34.zip'; assert(not Up.release(a))
 a=release(); a.assets[1].browser_download_url=Up.download..'v1.33/SpotterEnginer-1.34.zip'; assert(not Up.release(a))
 a=release(); a.assets[2].browser_download_url=Up.download..'v1.34/SpotterEnginer-1.34.sha256?x=1'; assert(not Up.release(a))
 a=release(); a.assets[2].name='SpotterEnginer-1.34.zip.sha256'; a.assets[2].browser_download_url=Up.download..'v1.34/SpotterEnginer-1.34.zip.sha256'; assert(Up.release(a))
 a=release({tag_name='1.34'}); for _,asset in ipairs(a.assets) do asset.browser_download_url=Up.download..'1.34/'..asset.name end; assert(Up.release(a).version=='1.34')
 -- À l'arrêt : jamais sur une image ou une voiture que CSP n'a pas pu lire (valeurs de l'image d'avant).
 assert(not Up.stopped({valid=false,paused=true}) and not Up.stopped({valid=true},{valid=false,inPit=true,kmh=0}))
 assert(Up.stopped({valid=true,paused=true}) and Up.stopped({valid=true},{valid=true,inPit=true,kmh=0.5}))
end
-- Un fichier illisible n'est jamais pris pour « identique » (deux lectures en échec) : la copie s'arrête, la
-- version installée est remise en place, le manifeste ne change pas.
tests.UPDATE_REMOTE_UNREADABLE=function()
 local function staged(setup,check)
  onFake(nil,nil,function(f,p,u)
   Up.check(u,p,0); Up.install(u,p,true); assert(u.phase=='ready',tostring(u.detail))
   setup(f); Up.tick(u,p,true,10); check(f,u)
  end)
 end
 local function intact(f) return f.files[f.root..'/SpotterEnginer.lua']=='main 1.33' and f.files[f.root..'/src/ui.lua']=='ui 1.33' and Up.manifestVersion(f.files[f.root..'/manifest.ini'])=='1.33' and f.files[f.work..'/installing.txt']==nil end
 local nxt='/next/'..Fake.prefix
 -- Nouveau module du paquet illisible (absent de l'app : nil des deux côtés).
 staged(function(f) f.noload[f.work..nxt..'src/new.lua']=true end,function(f,u)
  assert(u.phase=='failed' and u.error=='write' and u.detail=='src/new.lua','new: '..u.phase..' '..u.error..' '..u.detail)
  assert(intact(f) and f.files[f.root..'/src/new.lua']==nil and f.restarts==0)
 end)
 -- Fichier du paquet illisible qui remplace un fichier de l'app : arrêt avant toute copie.
 staged(function(f) f.noload[f.work..nxt..'src/ui.lua']=true end,function(f,u)
  assert(u.error=='write' and u.detail=='sauvegarde : src/ui.lua' and intact(f),u.error..' '..u.detail)
 end)
 -- Fichier de l'app illisible après son remplacement : copie non confirmée, version remise en place.
 staged(function(f) f.noload[f.root..'/src/ui.lua']=true end,function(f,u)
  assert(u.error=='write' or u.phase=='broken',u.phase..' '..u.error)
  f.noload[f.root..'/src/ui.lua']=nil
  assert(Up.manifestVersion(f.files[f.root..'/manifest.ini'])=='1.33' and f.restarts==0)
 end)
 -- Fichier extrait illisible : paquet refusé à la comparaison.
 onFake(nil,function(f) f.noload[f.work..nxt..'src/ui.lua']=true end,function(f,p,u)
  Up.check(u,p,0); Up.install(u,p,true)
  assert(u.error=='write' and u.detail:find('different du paquet : src/ui.lua',1,true) and intact(f),tostring(u.detail))
 end)
end
-- Paquet extrait comparé au paquet par tranches (une image ne porte qu'une tranche) ; la liste des fichiers
-- n'est écrite qu'à la fin ; une extraction annulée qui finit plus tard est ignorée.
tests.UPDATE_REMOTE_COMPARE_SLICES=function()
 local slice=Remote.compareSlice
 local ok,err=pcall(function()
  Remote.compareSlice=0
  onFake(nil,nil,function(f,p,u)
   local list=f.work..'/next/'..Fake.prefix..'.files'
   Up.check(u,p,0); assert(Up.install(u,p,true))
   assert(u.phase=='staging' and f.files[list]==nil,'one file compared, the rest at the next frames')
   local frames=0
   while u.phase=='staging' and frames<50 do frames=frames+1; Up.tick(u,p,false,frames); if u.phase=='staging' then assert(f.files[list]==nil) end end
   assert(frames>=6 and u.phase=='available' and u.release.staged and f.files[list],'frames '..frames..' '..u.phase)
   assert(f.files[f.root..'/SpotterEnginer.lua']=='main 1.33' and f.reloads==0,'nothing copied while driving')
   assert(Up.install(u,p,true)); Up.tick(u,p,true,60); assert(u.phase=='restarting')
  end)
  -- Fichier abîmé loin dans la liste : trouvé à sa tranche.
  onFake(nil,function(f) f.corruptExtract=Fake.prefix..'src/ui.lua' end,function(f,p,u)
   Up.check(u,p,0); Up.install(u,p,true)
   for frame=1,50 do Up.tick(u,p,false,frame) end
   assert(u.error=='write' and u.detail:find('different du paquet : src/ui.lua',1,true) and not u.release.staged)
  end)
  -- Annulée pendant l'extraction, relancée : la première extraction, finie ensuite, n'interrompt pas la seconde.
  onFake(nil,function(f) f.async=true end,function(f,p,u)
   Up.check(u,p,0); f.flush(); Up.install(u,p,true)
   while u.phase~='staging' do local list=f.pending; f.pending={}; list[1](); for k=2,#list do f.pending[#f.pending+1]=list[k] end end
   assert(Up.cancel(u) and Up.install(u,p,true)); f.flush()
   for frame=1,50 do Up.tick(u,p,false,frame) end
   assert(u.phase=='available' and u.release.staged and p.sourceComplete('next'),u.phase..' '..tostring(u.detail))
  end)
 end)
 Remote.compareSlice=slice; assert(ok,err)
end
-- Rappel facultatif du port avant la copie finale (fichiers de l'app tenus ouverts à rendre) ; une erreur du
-- rappel n'empêche rien.
tests.UPDATE_BEFORE_COPY=function()
 local u,p=ready({installed='1.33'}); p.beforeCopy=function() p.calls[#p.calls+1]='before copy' end
 Up.install(u,p,true); Up.tick(u,p,true,10)
 assert(u.phase=='restarting' and ordered(p.calls,{'stage','before copy','snapshot','place next','restart'}) and count(p.calls,'before copy')==1)
 u,p=ready({installed='1.33'}); p.beforeCopy=function() error('boom') end
 Up.install(u,p,true); Up.tick(u,p,true,10); assert(u.phase=='restarting')
 u,p=ready({backup='1.32',over='1.33',installed='1.33'}); u.previous='1.32'; p.beforeCopy=function() p.calls[#p.calls+1]='before copy' end
 Up.rollback(u,p,true); Up.tick(u,p,true,10); assert(ordered(p.calls,{'before copy','snapshot','place backup'}))
end
-- Vrai port : pont d'AdvancedIA lu sur le disque, à côté de l'app ; AdvancedIA absent ou plus ancien : refusé, rien
-- d'extrait ni de copié dans le dossier de l'app.
tests.UPDATE_REMOTE_COMPANION=function()
 onFake(nil,function(f) f.files[f.aaiRoot..'manifest.ini']=nil end,function(f,p,u)
  assert(p.companionLayout()==nil)
  Up.check(u,p,0); assert(Up.install(u,p,true)); assert(u.error=='aaiMissing','missing: '..tostring(u.error))
  assert(f.files[f.work..'/next/apps/lua/SpotterEnginer/manifest.ini']==nil and f.reloads==0)
 end)
 onFake(nil,function(f) f.files[f.aaiRoot..'src/bridge_layout.lua']='local L={}\nL.version=0\nreturn L\n' end,function(_,p,u)
  assert(p.companionLayout():find('L.version=0',1,true))
  Up.check(u,p,0); Up.install(u,p,true); assert(u.error=='aaiOld','old: '..tostring(u.error))
 end)
end
return tests
