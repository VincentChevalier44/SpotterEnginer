-- Port de la mise à jour de SpotterEnginer : repris d'AdvancedIA (Beta 1.51 ; mentions « Beta 1.xx » : son historique),
-- sans les restes de ses Beta 1.33/1.34 (repère et compte rendu dans le dossier de l'app), plus la lecture du pont
-- d'AdvancedIA installé (companionLayout) et d'un fichier d'une source (sourceText). Réseau, empreinte, zips et
-- fichiers de CSP, seulement ici.
-- Dossier de travail hors de l'app, dans cfg/extension/state de CSP (jamais rechargé en direct) :
--   next/apps/lua/SpotterEnginer/  paquet téléchargé, extrait et comparé au paquet ;
--   current/                     fichiers de l'app que la copie va remplacer, copiés juste avant elle ;
--   backup/                      version précédente (current promu après une installation réussie) ;
--   installing.txt               repère d'une copie en cours (écrit et relu juste avant, levé juste après) ;
--   updated.txt                  compte rendu de la dernière opération, lu au lancement suivant ;
--   boot.txt                     démarrage surveillé de la version tout juste installée ;
--   failed.txt                   reprise abandonnée (rappelée tant que la même version reste installée).
-- Beta 1.37 : io.save(…, ensure) passe par io.replaceFile, qui garde l'ancien contenu en <fichier>.bak quand le fichier
-- existe déjà (boot.txt réécrit au lancement qui le compte) : ce reste est effacé à chaque écriture et à chaque
-- suppression ; tout autre reste (paquet extrait, copie des fichiers remplacés, fichiers inconnus) est effacé par
-- p.tidy, seulement sans repère ni démarrage surveillé (M.tidy de src/update.lua).
-- Chaque source garde la liste de ses fichiers (.files) : une source n'est utilisée que si tous ses fichiers sont là.
-- Le dossier de l'app (sur un autre disque que Documents, le plus souvent) ne reçoit que la copie finale : chaque fichier
-- copié à côté (.new) puis mis en place d'un seul coup (même disque), surveillance des fichiers de CSP suspendue puis
-- rétablie, src/ d'abord, SpotterEnginer.lua puis le manifeste en dernier.
-- Sans les fonctions de CSP (tests, banc de mesure), le port est inerte : rien n'est lu, écrit ni demandé.
local Update=require('src/update')
local M={}
local function callable(f) return type(f)=='function' end
local function folder(id)
 if not ac or not callable(ac.getFolder) or not ac.FolderID or not ac.FolderID[id] then return nil end
 local ok,path=pcall(ac.getFolder,ac.FolderID[id])
 if not ok or type(path)~='string' or path=='' then return nil end
 return (path:gsub('\\','/'):gsub('/+$',''))
end
-- Empreinte en hexadécimal minuscule (CSP la rend en texte ; 32 octets bruts acceptés aussi).
local function hex(s)
 if type(s)~='string' then return nil end
 if #s==64 and s:match('^%x+$') then return s:lower() end
 if #s==32 then return (s:gsub('.',function(c) return string.format('%02x',c:byte()) end)) end
 return nil
end
-- Fichiers d'un dossier, chemins relatifs avec « / ».
local function files(dir,rel,out)
 io.scanDir(dir,'*',function(name,attr)
  if name=='.' or name=='..' or name=='' then return end
  local path=rel=='' and name or rel..'/'..name
  if attr and attr.isDirectory then files(dir..'/'..name,path,out) else out[#out+1]=path end
 end)
 return out
end
-- Sous-dossiers d'un dossier, les plus profonds d'abord (pour les effacer une fois vides).
local function folders(dir,rel,out)
 io.scanDir(dir,'*',function(name,attr)
  if name=='.' or name=='..' or name=='' then return end
  if attr and attr.isDirectory then local path=rel=='' and name or rel..'/'..name; folders(dir..'/'..name,path,out); out[#out+1]=path end
 end)
 return out
end
-- Ordre de la copie finale : src/ d'abord, les autres fichiers, puis SpotterEnginer.lua, le manifeste en dernier.
local function rank(path)
 if path=='manifest.ini' then return 4 elseif path=='SpotterEnginer.lua' then return 3 elseif path:sub(1,4)=='src/' then return 1 end
 return 2
end
local function ordered(list)
 table.sort(list,function(a,b) local x,y=rank(a),rank(b); if x~=y then return x<y end; return a<b end)
 return list
end
-- Liste des fichiers d'une source (.files) : un chemin par ligne, chemins sûrs seulement.
local function parseList(text)
 if type(text)~='string' then return nil end
 local out={}
 for line in (text..'\n'):gmatch('([^\r\n]*)\r?\n') do
  if line~='' then
   if line:find('..',1,true) or line:find(':',1,true) or line:find('\\',1,true) or line:sub(1,1)=='/' then return nil end
   out[#out+1]=line
  end
 end
 return #out>0 and out or nil
end
-- Bibliothèques de CSP lues sans erreur quand elles manquent (tests, ancien CSP).
local function lib(name) local t=rawget(_G,name); return type(t)=='table' and t or nil end
local needed={'load','save','fileExists','deleteFile','copyFile','move','createDir','createFileDir','scanDir','scanZip','loadFromZip','extractFromZipAsync'}
M.work='SpotterEnginer-update'
M.list='.files'
-- onRelease : journal versé, radio arrêtée, son de la voiture rendu, réglages enregistrés (fourni par le script
-- principal), avant ac.restartApp.
function M.new(onRelease)
 local p={ready=false}
 local web,JSON=lib('web'),lib('JSON')
 local app=folder('ScriptOrigin'); local state=folder('ExtCfgState')
 local ready=app~=nil and state~=nil and type(io)=='table' and web~=nil and callable(web.get) and JSON~=nil and callable(JSON.parse)
  and type(ac)=='table' and callable(ac.checksumSHA256) and callable(ac.restartApp)
 if ready then for _,name in ipairs(needed) do if not callable(io[name]) then ready=false end end end
 p.ready=ready; p.app=app
 local work=state and state..'/'..M.work
 p.work=work
 local roots=work and {next=work..'/next/'..Update.prefix:gsub('/$',''),current=work..'/current',backup=work..'/backup'} or {}
 local old=work and work..'/backup.old'
 local marker=work and work..'/installing.txt'; local report=work and work..'/updated.txt'
 local bootFile=work and work..'/boot.txt'; local failedFile=work and work..'/failed.txt'
 local function exists(f) if not ready or not f then return false end; local ok,r=pcall(io.fileExists,f); return ok and r==true end
 local function load(f) if not exists(f) then return nil end; local ok,t=pcall(io.load,f); return ok and type(t)=='string' and t or nil end
 local function save(f,t)
  if not ready or not f then return false end
  pcall(io.createFileDir,f)
  local ok,r=pcall(io.save,f,t,true)
  if exists(f..'.bak') then pcall(io.deleteFile,f..'.bak') end
  return ok and r~=false
 end
 local function delete(f)
  if exists(f) then pcall(io.deleteFile,f) end
  if f and exists(f..'.bak') then pcall(io.deleteFile,f..'.bak') end
  return not exists(f)
 end
 -- Horloge de la copie : os.clock d'abord (os.preciseClock de CSP peut ne pas avancer pendant une image : la 1.36
 -- notait « 0 ms » pour une copie de 16 fichiers).
 local function clock() local t=rawget(_G,'os'); local f=type(t)=='table' and (t.clock or t.preciseClock); if callable(f) then local ok,v=pcall(f); if ok and type(v)=='number' then return v end end; return 0 end
 -- Surveillance des fichiers de CSP suspendue (rechargement en direct) le temps d'écrire dans le dossier de l'app, puis
 -- rétablie.
 local function watch(paused) if ac and callable(ac.pauseFilesWatching) then pcall(ac.pauseFilesWatching,paused) end end
 local function list(dir) local ok,out=pcall(files,dir,'',{}); return ok and type(out)=='table' and out or nil end
 -- Beta 1.36 : dossiers vides effacés aussi (les plus profonds d'abord, puis le dossier lui-même) ; sinon le renommage
 -- de la sauvegarde trouverait sa destination déjà là et passerait à la copie dès la troisième mise à jour.
 local function clear(dir)
  local all=list(dir); if all then for _,rel in ipairs(all) do pcall(io.deleteFile,dir..'/'..rel) end end
  if callable(io.deleteDir) then
   local ok,subs=pcall(folders,dir,'',{})
   if ok and type(subs)=='table' then for _,rel in ipairs(subs) do pcall(io.deleteDir,dir..'/'..rel) end end
   pcall(io.deleteDir,dir)
  end
 end
 local function copy(a,b) pcall(io.createFileDir,b); local ok,r=pcall(io.copyFile,a,b,false); return ok and r~=false and exists(b) end
 -- Remplacement d'un fichier de l'app d'un seul coup : copie à côté (.new, même dossier, même disque), puis déplacement
 -- qui remplace ; une coupure laisse l'ancien fichier entier ou le nouveau, jamais un fichier à moitié écrit.
 local function swap(src,dst)
  local tmp=dst..'.new'
  delete(tmp)
  if not copy(src,tmp) then delete(tmp); return false end
  local ok,r=pcall(io.move,tmp,dst,true)
  if not ok or r==false or load(dst)~=load(src) then delete(tmp); return false end
  return true
 end
 local function listOf(root) return root and parseList(load(root..'/'..M.list)) or nil end
 local function complete(root)
  local all=listOf(root)
  if not all then return false end
  for _,rel in ipairs(all) do if not exists(root..'/'..rel) then return false end end
  return true
 end
 function p.get(url,headers,cb)
  if not ready then cb('unavailable',nil,nil); return end
  local ok,err=pcall(web.get,url,headers or {},function(e,response)
   if e and e~='' then cb(tostring(e),nil,nil) else cb(nil,response and tonumber(response.status),response and response.body) end
  end)
  if not ok then cb('web: '..tostring(err),nil,nil) end
 end
 function p.json(text) if not ready or type(text)~='string' then return nil end; local ok,t=pcall(JSON.parse,text); return ok and type(t)=='table' and t or nil end
 function p.sha256(data) if not ready then return nil end; local ok,h=pcall(ac.checksumSHA256,data); return ok and hex(h) or nil end
 function p.entries(data) if not ready then return nil end; local ok,out=pcall(io.scanZip,data); return ok and type(out)=='table' and out or nil end
 function p.entry(data,name) if not ready then return nil end; local ok,t=pcall(io.loadFromZip,data,name); return ok and type(t)=='string' and t or nil end
 function p.installedVersion() return app and Update.manifestVersion(load(app..'/manifest.ini')) or nil end
 -- Version d'une source (next, current, backup) lue dans son manifeste ; source complète (tous ses fichiers listés là).
 function p.sourceVersion(name) local root=roots[name]; return root and Update.manifestVersion(load(root..'/manifest.ini')) or nil end
 function p.sourceComplete(name) return complete(roots[name]) end
 function p.sourceHas(name,required)
  local root=roots[name]; if not root then return false end
  for _,rel in ipairs(required) do if not exists(root..'/'..rel) then return false end end
  return true
 end
 function p.markerFile() return marker end
 function p.marker() return load(marker) end
 -- Repère écrit puis relu : un repère qui ne s'écrit pas (disque plein, lecture seule) arrête l'opération.
 function p.mark(text) return save(marker,text) and load(marker)==text end
 -- Repère levé : vrai seulement s'il n'existe plus.
 function p.clearMarker() return delete(marker) end
 function p.report(text) return save(report,text) end
 function p.takeReport()
  local text=load(report); delete(report)
  return Update.parseReport(text)
 end
 -- Démarrage surveillé : version installée, essais de démarrage, version précédente.
 function p.boot()
  local text=load(bootFile); if not text then return nil end
  local version,count,from=text:match('^([^\n]+)\n(%d+)\n([^\n]*)')
  return version,tonumber(count) or 0,from~='' and from or nil
 end
 function p.bootSet(version,from,count) return save(bootFile,version..'\n'..(count or 0)..'\n'..(from or '')) end
 function p.bootClear() return delete(bootFile) end
 -- Première image atteinte : la version installée démarre ; la surveillance s'arrête.
 function p.bootOk() if exists(bootFile) then delete(bootFile) end end
 function p.failedNote(text) return save(failedFile,text) end
 function p.failed() return load(failedFile) end
 function p.clearFailed() return delete(failedFile) end
 -- Journal de CSP (custom_shaders_patch.log) : la reprise au chargement y est dite même si l'app ne charge pas ensuite.
 function p.log(text) if ac and callable(ac.log) then pcall(ac.log,'SpotterEnginer: '..tostring(text)) end end
 -- Pont d'AdvancedIA installé (texte de son src/bridge_layout.lua, lecture seule), ou nil s'il est absent : premier
 -- dossier connu qui a un manifeste (Update.companion).
 function p.companionLayout()
  if not app then return nil end
  local parent=app:match('^(.*)/[^/]+$')
  if not parent then return nil end
  for _,name in ipairs(Update.companion.folders) do
   local dir=parent..'/'..name
   if exists(dir..'/manifest.ini') then return load(dir..'/'..Update.companion.layout) end
  end
  return nil
 end
 -- Texte d'un fichier de l'app installée, ou nil.
 function p.appText(rel) return app and load(app..'/'..rel) or nil end
 -- Texte d'un fichier d'une source (next, current, backup), ou nil.
 function p.sourceText(name,rel) local root=roots[name]; return root and load(root..'/'..rel) or nil end
 function p.open(url) if os and callable(os.openURL) and type(url)=='string' and url:sub(1,8)=='https://' then pcall(os.openURL,url) end end
 -- Paquet extrait dans next/ (vidé d'abord ; manifeste extrait en dernier par CSP), puis comparé fichier par fichier au
 -- paquet ; liste des fichiers écrite en dernier (source complète seulement si tout est conforme).
 function p.stage(data,names,cb)
  if not ready then cb('unavailable'); return end
  pcall(io.createDir,work); clear(work..'/next'); pcall(io.createDir,work..'/next')
  local ok,err=pcall(io.extractFromZipAsync,data,work..'/next',{crucial=Update.prefix..'manifest.ini'},function(e)
   if e and e~='' then cb(tostring(e)); return end
   local root=roots.next
   for _,rel in ipairs(names) do
    if load(root..'/'..rel)~=p.entry(data,Update.prefix..rel) then cb('fichier extrait different du paquet : '..rel); return end
   end
   if not save(root..'/'..M.list,table.concat(names,'\n')) then cb('liste des fichiers'); return end
   cb(nil)
  end)
  if not ok then cb('extraction: '..tostring(err)) end
 end
 -- Fichiers de l'app que la copie d'une source va remplacer (contenu différent de la source ; le manifeste toujours),
 -- copiés dans current/ avec leur liste ; les fichiers identiques n'y vont pas (Beta 1.37 : la copie d'une mise à jour
 -- n'en écrit plus que la part qui change). Renvoie true, nil et les chiffres, ou false et le fichier en cause.
 function p.snapshot(source)
  if not ready then return false,'indisponible' end
  local started=clock()
  local from=roots[source]
  local names=listOf(from)
  if not names then return false,'liste des fichiers de '..tostring(source) end
  local root=roots.current
  clear(root); pcall(io.createDir,root)
  local kept,seen={},{}
  for _,rel in ipairs(names) do seen[rel]=true end
  if not seen['manifest.ini'] then names[#names+1]='manifest.ini' end
  for _,rel in ipairs(names) do
   local dst=app..'/'..rel
   if exists(dst) and (rel=='manifest.ini' or load(dst)~=load(from..'/'..rel)) then
    if not copy(dst,root..'/'..rel) then return false,rel end
    kept[#kept+1]=rel
   end
  end
  if not save(root..'/'..M.list,table.concat(kept,'\n')) then return false,M.list end
  if p.sourceVersion('current')~=p.installedVersion() or not complete(root) then return false,'manifest.ini' end
  return true,nil,{saved=#kept,ms=(clock()-started)*1000}
 end
 -- Copie finale d'une source complète dans le dossier de l'app : fichiers changés seulement, dans l'ordre sûr, chacun
 -- remplacé d'un seul coup ; true et les chiffres de la copie, ou false et le fichier en cause.
 function p.place(name)
  local root=roots[name]
  if not ready or not root then return false,'indisponible' end
  local all=listOf(root)
  if not all or not complete(root) then return false,'source incomplete' end
  ordered(all)
  local started,copied=clock(),0
  watch(true)
  for _,rel in ipairs(all) do
   local src,dst=root..'/'..rel,app..'/'..rel
   if load(src)~=load(dst) then
    -- Surveillance réaffirmée à chaque fichier : CSP la rétablit seule au bout de quelques secondes.
    watch(true)
    if not swap(src,dst) then watch(false); return false,rel end
    copied=copied+1
   end
  end
  watch(false)
  return true,nil,{compared=#all,copied=copied,ms=(clock()-started)*1000}
 end
 -- Installation réussie : current/ devient backup/ par renommage des dossiers (backup -> backup.old, current -> backup,
 -- backup.old effacé) ; rejouée sans dégât (current déjà promu : rien à faire) ; à défaut de renommage, copie vérifiée.
 -- Renvoie true, ou false et la raison.
 function p.promote(kind)
  if kind~='update' or not ready then return true end
  local cur,bak=roots.current,roots.backup
  if not complete(cur) then
   if complete(bak) then clear(old) end
   return true
  end
  clear(old)
  local moved=false
  if listOf(bak) or list(bak) and #list(bak)>0 then local ok,r=pcall(io.move,bak,old,false); moved=ok and r~=false end
  local ok,r=pcall(io.move,cur,bak,false)
  if ok and r~=false and complete(bak) then clear(old); return true end
  -- Renommage refusé : copie des fichiers, vérifiée, puis current vidé (l'ancienne version précédente est remplacée).
  if moved then clear(old) end
  clear(bak); pcall(io.createDir,bak)
  for _,rel in ipairs(listOf(cur) or {}) do if not copy(cur..'/'..rel,bak..'/'..rel) then return false,rel end end
  if not copy(cur..'/'..M.list,bak..'/'..M.list) or not complete(bak) then return false,M.list end
  clear(cur); clear(old)
  return true
 end
 -- Nettoyage du dossier de travail (Beta 1.37 ; appelé sans repère ni démarrage surveillé, voir M.tidy) : paquet extrait
 -- (next/), copie d'une installation finie (current/), ancienne version précédente (backup.old/), fichiers inconnus de la
 -- racine (restes .bak, .tmp, .new), fichiers de backup/ hors de sa liste, puis dossiers vides. Jamais la version
 -- précédente, le repère, le compte rendu, le démarrage surveillé ni la note d'une reprise abandonnée. Renvoie le
 -- nombre de fichiers effacés.
 local known={['installing.txt']=true,['updated.txt']=true,['boot.txt']=true,['failed.txt']=true}
 local function empty(dir)
  local ok,subs=pcall(folders,dir,'',{})
  if ok and type(subs)=='table' and callable(io.deleteDir) then for _,rel in ipairs(subs) do pcall(io.deleteDir,dir..'/'..rel) end end
 end
 function p.tidy()
  if not ready or not work then return 0 end
  local n=0
  local function gone(path) if exists(path) then pcall(io.deleteFile,path); if not exists(path) then n=n+1 end end end
  local dirs={work..'/next'}
  -- Copie d'une installation finie et ancienne version précédente : effacées seulement avec une version précédente
  -- complète dans backup/ (après une promotion refusée, elles peuvent porter la seule copie de cette version).
  if complete(roots.backup) then dirs[2]=roots.current; dirs[3]=old end
  for _,dir in ipairs(dirs) do
   for _,rel in ipairs(list(dir) or {}) do gone(dir..'/'..rel) end
   clear(dir)
  end
  local stray={}
  pcall(io.scanDir,work,'*',function(name,attr)
   if name~='.' and name~='..' and name~='' and not (attr and attr.isDirectory) and not known[name] then stray[#stray+1]=name end
  end)
  for _,name in ipairs(stray) do gone(work..'/'..name) end
  local listed=listOf(roots.backup)
  if listed then
   local keep={[M.list]=true}; for _,rel in ipairs(listed) do keep[rel]=true end
   for _,rel in ipairs(list(roots.backup) or {}) do if not keep[rel] then gone(roots.backup..'/'..rel) end end
   empty(roots.backup)
  end
  return n
 end
 function p.restart()
  if callable(onRelease) then pcall(onRelease) end
  if ready then pcall(ac.restartApp) end
 end
 return p
end
return M
