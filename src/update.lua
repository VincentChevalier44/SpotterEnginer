-- Mise à jour de SpotterEnginer depuis GitHub : module repris d'AdvancedIA (Beta 1.51, avec les constantes prévues pour
-- sa Beta 1.52 : préfixe des paquets et libellé des versions) ; les mentions « Beta 1.xx » ci-dessous sont l'historique
-- d'AdvancedIA. Mêmes règles : vérification au lancement, empreinte SHA-256, sauvegarde, installation à l'arrêt, retour
-- arrière. En plus (SpotterEnginer dépend d'AdvancedIA) : le paquet n'est installé, et la version précédente n'est
-- rétablie, que si son pont (src/bridge_layout.lua, version) est celui d'AdvancedIA installé (M.compatible).
-- Logique pure, sans réseau ni fichiers. Le port
-- (src/remote.lua en jeu, une imitation dans les tests) fait les requêtes, l'empreinte, les copies et le redémarrage.
-- Tout le travail se fait hors du dossier de l'app (cfg/extension/state de CSP, jamais rechargé en direct) : paquet
-- extrait dans « next », copie des fichiers que la copie va remplacer dans « current », version précédente dans « backup ».
-- Chaque source garde la liste de ses fichiers : une source n'est utilisée que complète.
-- Ordre d'une installation : dernière version publiée -> empreinte puis paquet (taille et SHA-256) -> contenu du paquet
-- (chemins, fichiers indispensables, modules requis, version du manifeste) -> extraction dans « next », comparée au paquet
-- -> à l'arrêt seulement (le pilote reparti : copie reportée, nouveau clic) : copie des fichiers remplacés dans « current »
-- -> repère « installation en cours » relu -> copie dans le dossier de l'app, fichier par fichier remplacé d'un seul coup
-- (manifeste en dernier) -> « current » devient « backup » -> repère levé -> compte rendu -> démarrage surveillé -> IA
-- rendues à AC -> redémarrage de l'app. Une copie en échec remet aussitôt « current » en place.
-- Interrompue (plantage, coupure), la copie est reprise au lancement suivant, avant tout autre module (M.recover) :
-- décidée par le manifeste installé, deux essais au plus, jamais en boucle (redémarrage seulement repère levé). Une
-- version installée qui ne démarre pas deux fois de suite est défaite automatiquement (démarrage surveillé).
-- Contrat figé du haut de SpotterEnginer.lua (lu avant tout autre module, par toutes les versions à venir) : M.recover(port)
-- et son résultat {outcome, kind, from, to, file, failed, restart}, Remote.new(onRelease), port.ready, port.work,
-- port.restart, port.log, port.bootOk. Ne jamais changer ces noms ni leur sens.
-- Événements du journal (u.events) : textes prêts, versés au journal de session par le script principal.
-- Beta 1.37 : dossier de travail nettoyé (M.tidy) au lancement sans repère ni démarrage surveillé, et dès qu'une version
-- tout juste installée a démarré (port.bootOk, puis M.tidy) : aucun reste après une mise à jour réussie.
local M={}
M.repo='VincentChevalier44/SpotterEnginer'
M.api='https://api.github.com/repos/'..M.repo..'/releases/latest'
M.page='https://github.com/'..M.repo..'/releases'
M.download='https://github.com/'..M.repo..'/releases/download/'
M.prefix='apps/lua/SpotterEnginer/'
-- Paquets publiés : SpotterEnginer-<version>.zip et son empreinte (.sha256 ou .zip.sha256) ; versions écrites sans
-- préfixe (« 1.1.0 »).
M.assetPrefix='SpotterEnginer-'
M.labelPrefix=''
M.required={'manifest.ini','SpotterEnginer.lua','src/update.lua','src/remote.lua','src/bridge_layout.lua'}
M.headers={['User-Agent']='SpotterEnginer',['Accept']='application/vnd.github+json'}
-- AdvancedIA, dont SpotterEnginer dépend : dossiers possibles (nouveau nom d'abord) et fichier du pont partagé.
M.companion={folders={'AdvancedIA','ACAdvancedIA'},layout='src/bridge_layout.lua',name='AdvancedIA'}
M.notesMax=40
M.lineMax=200
M.sizeMax=16*1024*1024
M.eventsMax=32
M.checkGap=60
M.restartWait=10
M.recoverTries=2
M.bootTries=2
M.checkTimeout=45
M.downloadTimeout=180
-- Numéro de version : '1.1.0', 'v1.1.0', 'SpotterEnginer-1.1.0.zip', 'Beta 1.33' -> {1,1,0} / {1,33} ; nil sans numéro.
function M.version(text)
 if type(text)~='string' then return nil end
 local s=text:match('(%d+%.%d+[%.%d]*)') or text:match('(%d+)')
 if not s then return nil end
 local out={}; for n in s:gmatch('%d+') do out[#out+1]=tonumber(n) end
 return out
end
function M.label(text) local v=M.version(text); return v and M.labelPrefix..table.concat(v,'.') or nil end
-- a plus récente que b (versions illisibles : jamais).
function M.newer(a,b)
 local x,y=M.version(a),M.version(b)
 if not x or not y then return false end
 for i=1,math.max(#x,#y) do local p,q=x[i] or 0,y[i] or 0; if p~=q then return p>q end end
 return false
end
local function str(v) return type(v)=='string' and v or nil end
local function starts(s,p) return type(s)=='string' and s:sub(1,#p)==p end
-- Coupure d'un texte UTF-8 à n octets au plus, jamais au milieu d'un caractère.
function M.cut(text,n)
 if #text<=n then return text end
 local i=n
 while i>0 do local b=text:byte(i+1); if not b or b<0x80 or b>=0xC0 then break end; i=i-1 end
 return text:sub(1,i)
end
-- Notes de version : texte du changelog publié, balises Markdown simples retirées, lignes et longueur bornées.
function M.notes(body)
 local out={}
 if type(body)~='string' then return out end
 for raw in (body:gsub('\r','')..'\n'):gmatch('([^\n]*)\n') do
  local line=raw:gsub('^%s*#+%s*',''):gsub('%*%*',''):gsub('`',''):gsub('%s+$','')
  if #line>M.lineMax then line=M.cut(line,M.lineMax-3)..'...' end
  if line~='' or (#out>0 and out[#out]~='') then out[#out+1]=line end
  if #out>=M.notesMax then break end
 end
 while #out>0 and out[#out]=='' do out[#out]=nil end
 return out
end
-- Dernière version publiée (réponse de l'API GitHub décodée). Le paquet et son empreinte doivent porter le numéro de la
-- version et venir des téléchargements du dépôt : aucune autre adresse n'est suivie.
function M.release(data)
 if type(data)~='table' or data.draft==true or data.prerelease==true then return nil,'format' end
 local tag=str(data.tag_name); local version=M.label(tag)
 if not version then return nil,'format' end
 local number=table.concat(M.version(tag),'.')
 local zipName=M.assetPrefix..number..'.zip'
 local r={version=version,tag=tag,notes=M.notes(data.body),published=str(data.published_at) and data.published_at:sub(1,10) or '',
  page=starts(data.html_url,M.page) and data.html_url or M.page}
 if type(data.assets)=='table' then
  for _,asset in ipairs(data.assets) do
   local name=type(asset)=='table' and str(asset.name); local url=type(asset)=='table' and str(asset.browser_download_url)
   if name and url and starts(url,M.download) then
    if name==zipName then r.zip={name=name,url=url,size=tonumber(asset.size) or 0}
    elseif name==zipName..'.sha256' or name==M.assetPrefix..number..'.sha256' then r.sha={name=name,url=url} end
   end
  end
 end
 if not r.zip or not r.sha then return nil,'format' end
 if r.zip.size<=0 or r.zip.size>M.sizeMax then return nil,'format' end
 return r
end
-- Fichier d'empreinte « <64 hexadécimaux>  <nom du paquet> » (sha256sum).
function M.digest(text,zipName)
 if type(text)~='string' then return nil end
 local hash,name=text:match('^%s*(%x+)%s+%*?([^%s]+)')
 if not hash or #hash~=64 or name~=zipName then return nil end
 return hash:lower()
end
-- Chemin d'une entrée du paquet, sous apps/lua/SpotterEnginer/ : segments non vides, ni « . » ni « .. », sans « \ » ni « : »
-- (une entrée de dossier finit par « / »).
local function safe(name)
 if type(name)~='string' or not starts(name,M.prefix) or name:find('\\',1,true) or name:find(':',1,true) then return false end
 local rest=name:sub(#M.prefix+1)
 if rest:sub(-1)=='/' then rest=rest:sub(1,-2) end
 if rest=='' then return true end
 for segment in (rest..'/'):gmatch('([^/]*)/') do if segment=='' or segment=='.' or segment=='..' then return false end end
 return true
end
-- Contenu du paquet : chemins sûrs, avec les fichiers indispensables (dont le module de mise à jour lui-même : une version
-- sans lui ne pourrait plus se mettre à jour).
function M.content(entries)
 if type(entries)~='table' or #entries==0 then return false end
 local seen={}
 for _,name in ipairs(entries) do
  if not safe(name) then return false end
  seen[name]=true
 end
 for _,file in ipairs(M.required) do if not seen[M.prefix..file] then return false end end
 return true
end
-- Fichiers du paquet (sans les entrées de dossier), chemins relatifs au dossier de l'app.
function M.files(entries)
 local out={}
 for _,name in ipairs(entries) do if name:sub(-1)~='/' and #name>#M.prefix then out[#out+1]=name:sub(#M.prefix+1) end end
 return out
end
-- Modules requis par le code du paquet (require('src/…') écrit en clair) : tous présents, sinon le paquet est refusé
-- (une version qui ne chargerait pas). read(entrée) rend le texte d'une entrée. Renvoie true, ou false et le module.
function M.requires(entries,read)
 local seen={}
 for _,name in ipairs(entries) do seen[name]=true end
 for _,name in ipairs(entries) do
  if name:sub(-4)=='.lua' then
   local text=read(name)
   if type(text)=='string' then
    for _,pattern in ipairs({"require%(%s*'(src/[%w_/]+)'%s*%)",'require%(%s*"(src/[%w_/]+)"%s*%)'}) do
     for target in text:gmatch(pattern) do if not seen[M.prefix..target..'.lua'] then return false,target end end
    end
   end
  end
 end
 return true
end
-- Version écrite dans un manifeste (clé VERSION en début de ligne, jamais une autre clé qui finirait par VERSION).
function M.manifestVersion(text)
 if type(text)~='string' then return nil end
 return M.label(('\n'..text):match('\n[ \t]*VERSION[ \t]*=[ \t]*([^\r\n]+)'))
end
-- À l'arrêt seulement : pause, ou voiture du joueur arrêtée à son emplacement des stands (pas dans la voie). frame :
-- image lue par src/port.lua (paused) ; player : sa voiture (inPit, kmh).
function M.stopped(frame,player)
 if frame==nil then return false end
 if frame.paused==true then return true end
 return player~=nil and player.inPit==true and (tonumber(player.kmh) or 99)<1
end
-- Version du pont écrite dans un src/bridge_layout.lua (L.version=N), ou nil.
function M.bridgeVersion(text)
 if type(text)~='string' then return nil end
 return tonumber(text:match('\nL%.version%s*=%s*(%d+)') or text:match('^L%.version%s*=%s*(%d+)'))
end
-- Clé d'un manifeste (en début de ligne), ou nil : REQUIRES_ADVANCEDIA, version d'AdvancedIA requise par un paquet.
function M.manifestKey(text,key)
 if type(text)~='string' then return nil end
 local v=('\n'..text):match('\n[ \t]*'..key..'[ \t]*=[ \t]*([^\r\n]+)')
 return v and v:gsub('%s+$','') or nil
end
-- Compatibilité d'une version de SpotterEnginer (texte de son src/bridge_layout.lua) avec AdvancedIA installé (texte du
-- sien, nil s'il est absent) : true, ou false et la raison : 'aaiMissing' (AdvancedIA absent), 'aaiOld' (pont
-- d'AdvancedIA plus ancien : « Mettez d'abord AdvancedIA à jour »), 'aaiNewer' (pont d'AdvancedIA plus récent, inconnu
-- de cette version), 'layout' (fichier du pont illisible).
function M.compatible(mine,theirs)
 local a=M.bridgeVersion(mine)
 if not a then return false,'layout' end
 if theirs==nil then return false,'aaiMissing' end
 local b=M.bridgeVersion(theirs)
 if not b then return false,'layout' end
 if a>b then return false,'aaiOld' end
 if a<b then return false,'aaiNewer' end
 return true
end

function M.new(installed)
 return {phase='idle',installed=installed,error='',status=0,detail='',release=nil,previous=nil,updated=nil,serial=0,
  after='',events={},gen=0,askedAt=-math.huge,startedAt=0,now=0,restartAt=nil,restartLate=false,brokenFile=nil,warning=nil}
end
-- Événement du journal : niveau et texte ; les plus anciens sont oubliés au-delà de M.eventsMax non versés.
local function event(u,level,text)
 local list=u.events
 if #list>=M.eventsMax then table.remove(list,1) end
 list[#list+1]={level,text}
end
-- Événements à verser au journal, dans l'ordre ; la liste est vidée.
function M.take(u,out)
 local list=u.events
 for i=1,#list do out[#out+1]=list[i]; list[i]=nil end
 return out
end
-- « ready » (paquet prêt, copie à la prochaine image à l'arrêt) et « rollbackReady » occupent aussi la mise à jour.
local busy={checking=true,downloading=true,verifying=true,staging=true,saving=true,ready=true,rollbackReady=true,placing=true,restoring=true,restarting=true,broken=true}
function M.busy(u) return busy[u.phase]==true end
-- Annulation possible tant que rien n'est copié dans le dossier de l'app (partagé avec la fenêtre).
M.cancelable={downloading=true,verifying=true,staging=true,ready=true}
local failures={network='echec reseau',rate='GitHub refuse temporairement (limite de requetes)',format='version publiee illisible ou incomplete',
 integrity='paquet different de celui publie',content='contenu du paquet refuse',write='ecriture impossible',
 driving='refusee en conduite (disponible a l arret : emplacement des stands ou pause)',
 aaiOld='refusee : mettez d abord AdvancedIA a jour (pont plus ancien que celui de cette version)',
 aaiNewer='refusee : AdvancedIA installe publie un pont plus recent, inconnu de cette version',
 aaiMissing='refusee : AdvancedIA introuvable (SpotterEnginer ne fonctionne qu avec lui)',
 layout='refusee : fichier du pont illisible'}
-- kept : la version installée n'a pas changé (dit au journal) ; detail : erreur de CSP ou fichier en cause.
local function fail(u,code,status,detail,kept)
 u.phase='failed'; u.error=code; u.status=status or 0; u.detail=detail or ''; u.serial=u.serial+1
 local text='mise a jour: '..failures[code]..((status or 0)>0 and ' (statut '..status..')' or '')..((detail or '')~='' and ' : '..detail or '')
 event(u,code=='driving' and 'INFO' or 'WARN',text..(kept and ', version actuelle conservee' or ''))
end
-- Repère d'une copie en cours : « update A -> B » ou « rollback A -> B », puis « tries N » (essais de reprise).
local function parse(text)
 if type(text)~='string' then return nil end
 local kind,from,to=text:match('^(%a+) ([^\n]-) %-> ([^\n]+)')
 if kind~='update' and kind~='rollback' then return nil end
 return kind,from,to,tonumber(text:match('\ntries (%d+)')) or 0
end
M.parse=parse
-- Compte rendu de la dernière opération : « update A -> B », « rollback A -> B » ou « recovered A -> B » (version de départ
-- remise en place au lancement, version visée à refaire) ; « auto » à la fin d'un retour arrière automatique.
function M.parseReport(text)
 if type(text)~='string' then return nil end
 local kind,from,to=text:match('^(%a+) ([^\n]-) %-> ([^\n]+)')
 if kind~='update' and kind~='rollback' and kind~='recovered' then return nil end
 local auto=to:match('^(.-) auto$')
 return kind,from,auto or to,auto~=nil
end
-- Source de la version visée par une copie : paquet extrait (mise à jour) ou version précédente (retour arrière).
local targets={update='next',rollback='backup'}

-- Démarrage surveillé : une version installée par mise à jour qui n'a pas atteint sa première image deux lancements de
-- suite est défaite (version précédente complète remise en place). Renvoie le compte rendu, ou nil.
local function bootCheck(port,installed)
 local version,count,from=port.boot()
 if not version then return nil end
 if version~=installed then port.bootClear(); return nil end
 if count<M.bootTries then port.bootSet(version,from,count+1); return nil end
 port.bootClear()
 local result={kind='rollback',from=installed,to=from,file=port.markerFile(),auto=true}
 if not from or port.sourceVersion('backup')~=from or not port.sourceComplete('backup') then result.outcome='bootfailed'; return result end
 if not port.mark('rollback '..installed..' -> '..from) then result.outcome='failed'; result.failed='repere'; return result end
 local ok,failed=port.place('backup')
 if not ok then result.outcome='failed'; result.failed=failed; return result end
 port.report('rollback '..installed..' -> '..from..' auto')
 if port.clearMarker() then result.outcome='autorollback'; result.restart=true else result.outcome='failed'; result.failed='repere' end
 return result
end
-- Au chargement, avant tout autre module (synchrone, sans moteur) : copie interrompue au lancement précédent reprise.
-- Manifeste installé à la version visée : terminée ; à la version de départ ou mêlée : la copie vers la version visée est
-- refaite si sa source est complète, sinon la version de départ est remise en place ; autre version (installée à la
-- main) : repère levé. Deux essais au plus : ensuite le repère est levé, l'abandon noté (failed.txt) et dit. Redémarrage
-- seulement quand le repère est bien effacé (jamais en boucle). Sans repère : démarrage surveillé. Renvoie le compte
-- rendu, ou nil.
function M.recover(port)
 local marker=port.marker()
 if not marker then return bootCheck(port,port.installedVersion()) end
 local kind,from,to,tries=parse(marker)
 if not kind then local gone=port.clearMarker(); return {outcome=gone and 'cleared' or 'failed',failed=not gone and 'repere' or nil,text=marker,file=port.markerFile()} end
 local installed=port.installedVersion()
 local result={kind=kind,from=from,to=to,file=port.markerFile()}
 if installed==to then
  port.promote(kind)
  if port.clearMarker() then
   port.report(kind..' '..from..' -> '..to); result.outcome='finished'
   -- Beta 1.36 : version installée par une copie finie ici, surveillée dès ce lancement (compté comme le premier).
   if kind=='update' then port.bootSet(to,from,1) else port.bootClear() end
  else result.outcome='failed'; result.failed='repere' end
  return result
 end
 if installed~=from and installed~=nil then
  local gone=port.clearMarker(); result.outcome=gone and 'cleared' or 'failed'; result.failed=not gone and 'repere' or nil; result.installed=installed; return result
 end
 if tries>=M.recoverTries then
  port.clearMarker(); port.failedNote(kind..' '..from..' -> '..to..'\ninstalled '..tostring(installed)); result.outcome='gaveup'; return result
 end
 -- Essai compté d'abord : un repère qui ne se réécrit pas (lecture seule) arrête là, sans copie ni redémarrage.
 if not port.mark(kind..' '..from..' -> '..to..'\ntries '..(tries+1)) then result.outcome='failed'; result.failed='repere'; return result end
 local source=targets[kind]
 if port.sourceVersion(source)==to and port.sourceComplete(source) then
  local ok,failed=port.place(source)
  if ok then
   port.promote(kind)
   if port.clearMarker() then
    port.report(kind..' '..from..' -> '..to); result.outcome='completed'; result.restart=true
    -- Beta 1.36 : copie refaite au lancement, version surveillée à son premier démarrage (comme après un clic).
    if kind=='update' then port.bootSet(to,from,0) else port.bootClear() end
    return result
   end
   result.outcome='failed'; result.failed='repere'; return result
  end
  result.failed=failed
 end
 if port.sourceVersion('current')==from and port.sourceComplete('current') then
  local ok,failed=port.place('current')
  if ok then
   if port.clearMarker() then port.report('recovered '..from..' -> '..to); result.outcome='restored'; result.restart=true; return result end
   result.outcome='failed'; result.failed='repere'; return result
  end
  result.failed=failed or result.failed
 end
 result.outcome='failed'; return result
end
-- Texte du journal (de session et de CSP) d'une reprise faite au chargement.
local recoverTexts={
 finished=function(r) return 'INFO','mise a jour: copie reprise au lancement, '..(r.kind=='update' and 'installation' or 'retour arriere')..' termine ('..r.from..' -> '..r.to..')' end,
 completed=function(r) return 'INFO','mise a jour: copie reprise au lancement, '..(r.kind=='update' and 'installation' or 'retour arriere')..' termine ('..r.from..' -> '..r.to..')' end,
 restored=function(r) return 'WARN','mise a jour: copie interrompue ('..r.from..' -> '..r.to..'), '..r.from..' remise en place au lancement' end,
 autorollback=function(r) return 'WARN','mise a jour: la '..r.from..' n a pas demarre deux fois de suite, '..r.to..' remise en place automatiquement' end,
 bootfailed=function(r) return 'ERROR','mise a jour: la '..r.from..' n a pas demarre deux fois de suite et la version precedente est incomplete : reinstallez l app' end,
 cleared=function(r) return 'WARN','mise a jour: repere d une copie interrompue leve sans rien copier ('..(r.installed and 'version installee '..r.installed or 'repere illisible')..')' end,
 gaveup=function(r) return 'ERROR','mise a jour: reprise abandonnee apres '..M.recoverTries..' essais ('..(r.from or '?')..' -> '..(r.to or '?')..') : reinstallez l app ('..(r.file or '?')..')' end,
 failed=function(r) return 'ERROR','mise a jour: reprise impossible ('..(r.from or '?')..' -> '..(r.to or '?')..(r.failed and ', '..r.failed or '')..') : relancez le jeu ; si le probleme reste, reinstallez l app ('..(r.file or '?')..')' end}
function M.recoverText(r)
 local f=r and recoverTexts[r.outcome]
 if not f then return nil end
 return f(r)
end
-- Au lancement : compte rendu de la reprise (M.recover) et de la dernière opération, version précédente proposée (seulement
-- complète), abandon d'une reprise précédente rappelé tant que la même version reste installée.
function M.start(u,port,recovered)
 local backup=port.sourceVersion('backup')
 u.previous=backup~=u.installed and port.sourceComplete('backup') and backup or nil
 local note=port.failed()
 if note then
  local version=note:match('\ninstalled ([^\n]+)')
  if version==u.installed then u.warning=note:match('^[^\n]*'); event(u,'WARN','mise a jour: une reprise a echoue ('..u.warning..'), l app peut melanger deux versions : reinstallez-la')
  else port.clearFailed() end
 end
 if recovered then
  local level,text=M.recoverText(recovered)
  if text then event(u,level,text) end
  if recovered.outcome=='failed' or recovered.outcome=='gaveup' or recovered.outcome=='bootfailed' then u.phase='broken'; u.brokenFile=recovered.file; u.serial=u.serial+1 end
 end
 -- Fichiers copiés au chargement : redémarrage à la première image ; le compte rendu est lu au lancement suivant.
 if recovered and recovered.restart then
  u.phase='restarting'; u.after=recovered.kind=='rollback' and 'rollback' or 'update'; u.restartPending=true; u.serial=u.serial+1
  event(u,'INFO','mise a jour: redemarrage de l app pour charger une version complete')
  return
 end
 local kind,from,to,auto=port.takeReport()
 if kind then
  u.updated={kind=kind,from=from,to=to,auto=auto}; u.serial=u.serial+1
  event(u,'INFO',kind=='update' and 'mise a jour reussie: '..from..' -> '..to or kind=='rollback' and 'retour arriere termine'..(auto and ' (automatique)' or '')..': '..from..' -> '..to
   or 'installation interrompue rattrapee: '..from..' remise en place, '..to..' a refaire')
 end
 M.tidy(u,port)
end
-- Nettoyage du dossier de travail (Beta 1.37) : seulement sans repère (aucune copie à reprendre) ni démarrage surveillé
-- (version précédente encore utile au retour automatique), jamais pendant une opération ni avec un paquet extrait gardé
-- pour un nouveau clic ; noté au journal s'il a effacé quelque chose.
function M.tidy(u,port)
 if M.busy(u) or u.release and u.release.staged then return 0 end
 if not port.ready or type(port.tidy)~='function' or port.marker() or port.boot() then return 0 end
 local n=port.tidy() or 0
 if n>0 then event(u,'INFO',string.format('mise a jour: nettoyage (%d fichiers)',n)) end
 return n
end
-- Réponse encore attendue : aucune annulation ni nouvelle opération depuis la demande (jeton u.gen).
local function live(u,gen) return u.gen==gen end
-- Vérification (une fois par lancement, ou au bouton : au plus une fois par M.checkGap s).
function M.check(u,port,now)
 if M.busy(u) or now-u.askedAt<M.checkGap then return false end
 u.askedAt=now; u.gen=u.gen+1; local gen=u.gen
 u.phase='checking'; u.error=''; u.status=0; u.detail=''
 port.get(M.api,M.headers,function(err,status,body)
  if not live(u,gen) or u.phase~='checking' then return end
  if err or not status then fail(u,'network',0,err); return end
  if status==404 then u.phase='none'; u.serial=u.serial+1; event(u,'INFO','mise a jour: aucune version publiee sur GitHub'); return end
  if status==403 or status==429 then fail(u,'rate',status); return end
  if status~=200 then fail(u,'network',status); return end
  local r=M.release(port.json(body))
  if not r then fail(u,'format'); return end
  u.release=r; u.phase=M.fresh(u) and 'available' or 'current'; u.serial=u.serial+1
  event(u,'INFO',u.phase=='available' and 'mise a jour disponible: '..r.version..' (publiee le '..r.published..', '..r.zip.size..' octets)' or 'mise a jour: '..u.installed..' est la derniere version')
 end)
 return true
end
-- Annulation tant que rien n'est copié dans le dossier de l'app : les réponses suivantes sont ignorées (jeton u.gen).
function M.cancel(u)
 if not M.cancelable[u.phase] then return false end
 u.gen=u.gen+1; u.phase='available'; u.serial=u.serial+1; event(u,'INFO','mise a jour: annulee avant toute copie')
 return true
end
-- Copie finale (à l'arrêt) : copie des fichiers remplacés, repère relu, copie, promotion de la sauvegarde, repère levé,
-- compte rendu, démarrage surveillé, redémarrage. Une copie en échec remet la version de départ en place aussitôt ; si cela
-- échoue aussi, état terminal (repère gardé : reprise au prochain lancement).
local function place(u,port,kind,to,now)
 u.phase='saving'
 -- Version de départ lue dans le manifeste installé (celle que la reprise retrouvera).
 local from=port.installedVersion() or u.installed
 local saved,missing,kept=port.snapshot(targets[kind])
 if not saved then fail(u,'write',0,'sauvegarde : '..tostring(missing),true); return end
 u.phase='placing'
 local mark=kind..' '..from..' -> '..to
 if not port.mark(mark) then fail(u,'write',0,'repere',true); return end
 local ok,failed,stats=port.place(targets[kind])
 if not ok then
  u.phase='restoring'
  local back,failed2=port.place('current')
  if back and port.clearMarker() then fail(u,'write',0,failed,true); return end
  u.phase='broken'; u.brokenFile=port.markerFile(); u.serial=u.serial+1
  event(u,'ERROR','mise a jour: copie de '..tostring(failed)..' impossible, puis remise en place impossible ('..tostring(failed2 or 'repere')..') : relancez le jeu')
  return
 end
 local promoted,why=port.promote(kind)
 if not promoted then event(u,'WARN','mise a jour: version precedente non gardee ('..tostring(why)..'), retour arriere indisponible') end
 if not port.clearMarker() then event(u,'WARN','mise a jour: repere non efface ('..tostring(port.markerFile())..'), termine au lancement suivant') end
 -- Beta 1.47 : compte rendu avec la version qui tournait (le repère et le démarrage surveillé gardent celle du
 -- disque, seule juge de la reprise) : après un cache de CSP périmé, « Beta 1.44 -> Beta 1.45 » et non
 -- « Beta 1.45 -> Beta 1.45 ».
 if not port.report(kind..' '..(kind=='update' and u.installed or from)..' -> '..to) then event(u,'WARN','mise a jour: compte rendu non ecrit') end
 if kind=='update' then port.bootSet(to,from,0) else port.bootClear() end
 u.phase='restarting'; u.after=kind; u.restartAt=now; u.serial=u.serial+1
 event(u,'INFO',string.format('mise a jour: %s%s (%d fichiers compares, %d copies en %.0f ms ; %d fichiers gardes en %.0f ms), radio arretee, son de la voiture rendu et redemarrage de l app',
  to,kind=='update' and ' installee' or ' retablie',stats and stats.compared or 0,stats and stats.copied or 0,stats and stats.ms or 0,kept and kept.saved or 0,kept and kept.ms or 0))
 port.restart()
end
-- Installation (un clic, à l'arrêt) : paquet déjà extrait et intact repris tel quel ; sinon téléchargement, contrôles et
-- extraction ; copie finale à l'image suivante si le pilote est toujours à l'arrêt.
function M.install(u,port,stopped)
 local r=u.release
 if M.busy(u) or not r or not M.fresh(u) then return false end
 if not stopped then fail(u,'driving'); return false end
 u.gen=u.gen+1; local gen=u.gen
 u.error=''; u.detail=''; u.serial=u.serial+1; u.startedAt=u.now
 if r.staged and port.sourceVersion('next')==r.version and port.sourceComplete('next') then
  u.phase='ready'; event(u,'INFO','mise a jour: '..r.version..' deja telechargee et verifiee ; copie a l arret'); return true
 end
 r.staged=false
 u.phase='downloading'
 event(u,'INFO','mise a jour: telechargement de la '..r.version)
 port.get(r.sha.url,nil,function(err,status,text)
  if not live(u,gen) then return end
  if err or status~=200 then fail(u,'network',status~=200 and status or 0,err,true); return end
  local expected=M.digest(text,r.zip.name)
  if not expected then fail(u,'format',0,'fichier d empreinte illisible',true); return end
  port.get(r.zip.url,nil,function(err2,status2,data)
   if not live(u,gen) then return end
   if err2 or status2~=200 or type(data)~='string' then fail(u,'network',status2~=200 and status2 or 0,err2,true); return end
   u.phase='verifying'
   if #data~=r.zip.size then fail(u,'integrity',0,'taille '..#data..' octets au lieu de '..r.zip.size,true); return end
   if port.sha256(data)~=expected then fail(u,'integrity',0,'empreinte SHA-256 differente',true); return end
   local entries=port.entries(data)
   if not M.content(entries) or M.manifestVersion(port.entry(data,M.prefix..'manifest.ini'))~=r.version then fail(u,'content',0,nil,true); return end
   local loads,module=M.requires(entries,function(name) return port.entry(data,name) end)
   if not loads then fail(u,'content',0,'module absent : '..module,true); return end
   -- Pont du paquet comparé à celui d'AdvancedIA installé : jamais un spotter muet après une mise à jour.
   local fits,why=M.compatible(port.entry(data,M.prefix..M.companion.layout),port.companionLayout())
   if not fits then r.needs=M.manifestKey(port.entry(data,M.prefix..'manifest.ini'),'REQUIRES_ADVANCEDIA'); fail(u,why,0,nil,true); return end
   u.phase='staging'
   port.stage(data,M.files(entries),function(err3)
    if not live(u,gen) then return end
    if err3 then fail(u,'write',0,'extraction : '..tostring(err3),true); return end
    if port.sourceVersion('next')~=r.version or not port.sourceComplete('next') or not port.sourceHas('next',M.required) then fail(u,'content',0,'paquet extrait incomplet',true); return end
    u.phase='ready'; r.staged=true; u.serial=u.serial+1
    event(u,'INFO','mise a jour: '..r.version..' prete, empreinte et contenu verifies ; copie a l arret')
   end)
  end)
 end)
 return true
end
-- Retour à la version précédente (« backup », seulement complète) : copie à l'image suivante si le pilote est toujours
-- à l'arrêt (hors du dessin de la fenêtre).
function M.rollback(u,port,stopped)
 if M.busy(u) or not u.previous then return false end
 if not stopped then fail(u,'driving'); return false end
 if port.sourceVersion('backup')~=u.previous or not port.sourceComplete('backup') then fail(u,'write',0,'version precedente incomplete',true); return false end
 -- La version précédente peut attendre un autre pont qu'AdvancedIA installé : même contrôle qu'à l'installation. La
 -- sauvegarde ne garde que les fichiers que la mise à jour a remplacés : sans pont gardé, c'est celui de l'app.
 local layout=port.sourceText('backup',M.companion.layout) or port.appText(M.companion.layout)
 local fits,why=M.compatible(layout,port.companionLayout())
 if not fits then fail(u,why,0,nil,true); return false end
 u.phase='rollbackReady'; u.serial=u.serial+1
 event(u,'INFO','mise a jour: retour a la '..u.previous..' demande')
 return true
end
-- À chaque image : copie finale dès l'arrêt (paquet prêt, retour arrière demandé) ; pilote reparti : copie reportée (un
-- nouveau clic, paquet gardé) ; vérification et téléchargement bornés dans le temps ; signalé si l'app n'a pas redémarré.
function M.tick(u,port,stopped,now)
 u.now=now
 if u.restartPending then u.restartPending=false; u.restartAt=now; port.restart(); return end
 local phase=u.phase
 if phase=='ready' then
  if stopped and u.release then place(u,port,'update',u.release.version,now)
  else u.gen=u.gen+1; u.phase='available'; u.serial=u.serial+1; event(u,'INFO','mise a jour: copie reportee (pilote reparti), paquet garde : nouveau clic a l arret') end
 elseif phase=='rollbackReady' then
  if stopped and u.previous then place(u,port,'rollback',u.previous,now)
  else u.phase='idle'; u.serial=u.serial+1; event(u,'INFO','mise a jour: retour arriere annule (pilote reparti)') end
 elseif phase=='checking' and now-u.askedAt>M.checkTimeout then
  u.gen=u.gen+1; fail(u,'network',0,'pas de reponse de GitHub en '..M.checkTimeout..' s')
 elseif (phase=='downloading' or phase=='verifying' or phase=='staging') and now-u.startedAt>M.downloadTimeout then
  u.gen=u.gen+1; fail(u,'network',0,'telechargement non termine en '..M.downloadTimeout..' s',true)
 elseif phase=='restarting' and not u.restartLate and u.restartAt and now-u.restartAt>M.restartWait then
  u.restartLate=true; u.serial=u.serial+1; event(u,'WARN','mise a jour: l app n a pas redemarre, relancez la session pour finir')
 end
end
-- État affiché : noms de la maquette (uptodate, checking, available, driving, downloading, verifying, installing, done,
-- rolledback, none, interrupted, success, errNet, errHash, errWrite), plus unchecked, errFormat, errRate, ready (paquet
-- prêt, copie à l'arrêt) et broken (reprise impossible).
local errorViews={network='errNet',rate='errRate',format='errFormat',integrity='errHash',content='errHash',write='errWrite',
 aaiOld='aaiOld',aaiNewer='aaiNewer',aaiMissing='aaiMissing',layout='errHash'}
local reportViews={update='success',rollback='rolledback',recovered='interrupted'}
local busyViews={staging='installing',saving='installing',placing='installing',restoring='installing',rollbackReady='installing'}
-- Compte rendu d'une opération faite au lancement précédent (mise à jour, retour arrière, reprise) : affiché à la place de
-- l'état tant que rien d'autre n'est en cours.
local reportPhases={idle=true,current=true,checking=true,none=true}
function M.reported(u) return u.updated~=nil and reportPhases[u.phase]==true end
function M.view(u,stopped)
 local phase=u.phase
 if phase=='broken' then return 'broken' end
 if M.reported(u) then return reportViews[u.updated.kind] end
 if phase=='failed' then
  if u.error=='driving' then
   if not M.fresh(u) then return u.previous and 'driving' or 'unchecked' end
   return stopped and 'available' or 'driving'
  end
  return errorViews[u.error] or 'errNet'
 end
 if phase=='available' then return stopped and 'available' or 'driving' end
 if phase=='restarting' then return u.after=='rollback' and 'rolledback' or 'done' end
 if busyViews[phase] then return busyViews[phase] end
 if phase=='current' then return 'uptodate' end
 if phase=='idle' then return 'unchecked' end
 return phase
end
-- Version publiée plus récente que l'installée : comparée une seule fois par version publiée.
function M.fresh(u)
 local r=u.release
 if not r then return false end
 if r.newer==nil then r.newer=M.newer(r.version,u.installed) end
 return r.newer
end
-- Une version plus récente est proposée (bouton de l'en-tête, alerte de l'accueil, information de l'overlay).
function M.offered(u) return M.fresh(u) and (u.phase=='available' or u.phase=='failed' and u.error~='format' and u.error~='rate') end
-- État publié pour AdvancedIA (contrat v1 avec sa session, ac.store('SpotterEnginer.update')) : 200 octets au plus,
-- « v=1;installed=…;latest=…;state=available|uptodate|checking|error|incompatible[;needs=…] ».
M.statusKey='SpotterEnginer.update'
local statusStates={available='available',driving='available',ready='available',downloading='available',verifying='available',
 installing='available',uptodate='uptodate',checking='checking',aaiOld='incompatible',aaiNewer='incompatible',aaiMissing='incompatible'}
function M.status(u,stopped)
 local view=M.view(u,stopped)
 local state=statusStates[view] or (view:sub(1,3)=='err' or view=='broken') and 'error' or nil
 if not state then return nil end
 local text='v=1;installed='..tostring(u.installed or '?')..';latest='..tostring(u.release and u.release.version or u.installed or '?')..';state='..state
 if state=='incompatible' then text=text..';needs='..tostring(u.release and u.release.needs or '?') end
 return text:sub(1,200)
end
return M
