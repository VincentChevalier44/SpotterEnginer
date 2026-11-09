-- Imitation de CSP pour la mise à jour (1.33, refaite en 1.35) : web.get, JSON.parse, empreinte, zips et
-- fichiers en mémoire sur deux disques, comme sur la machine du pilote : le dossier de l'app (f.root, disque D:) et le
-- dossier d'état de CSP (f.state, cfg/extension/state sur C:). Tout autre chemin va aux fonctions d'origine ;
-- f.restore() remet tout en place.
-- Réponses et extractions asynchrones différées avec f.async (rendues par f.flush(), dans l'ordre), comme dans CSP ;
-- sinon immédiates. f.hold : réponses web gardées seulement. Échecs choisis : f.failExtract, f.failCopy (motif du chemin
-- de destination), f.locked[chemin] (fichier ouvert : copie refusée), f.failSave (motif). io.move entre les deux disques
-- échoue (MoveFileEx sans copie), comme sous Windows.
-- Rechargement en direct de CSP : toute écriture dans le dossier de l'app sans ac.pauseFilesWatching(true) compte dans
-- f.reloads (f.watching repasse à vrai par f.watch() ; f.autoResume=n : la surveillance reprend seule après n écritures,
-- comme CSP au bout de quelques secondes).
-- 1.35 : redirections (f.responses[url].redirect, suivies comme WinHTTP), corps binaires (zéros), dossiers déplacés
-- d'un bloc (io.move d'un dossier, même disque ; f.failDirMove), fichiers en lecture seule (f.readonly[chemin] : ni écrits,
-- ni effacés, ni remplacés), source illisible (f.unreadable[chemin] : copie refusée ; f.locked : ouvert en lecture par
-- l'app, copiable mais jamais remplacé), suppression refusée
-- (f.failDelete, motif du chemin).
-- 1.37 : io.save(…, true) sur un fichier existant garde l'ancien contenu en <fichier>.bak, comme io.replaceFile de
-- CSP (ReplaceFileW avec copie de sauvegarde), vu sur le disque du pilote (boot.txt.bak après la mise à jour 1.35 -> 1.36).
-- 1.36 : dossiers gardés une fois vides (f.dirs), comme sous Windows : créés par createDir/createFileDir ou par
-- l'écriture d'un fichier, effacés seulement par io.deleteDir (vides) ; un dossier déplacé d'un bloc refuse une
-- destination qui existe déjà, même vide.
local M={}
M.prefix='apps/lua/SpotterEnginer/'
-- Pont partagé (src/bridge_layout.lua), version 1, dans l'app, dans le paquet et chez AdvancedIA.
M.layout='local L={}\nL.version=1\nreturn L\n'
function M.install(o)
 o=o or {}
 local f={files=o.files or {},zips={},count=0,calls={},responses={},json={},sha={},restarts=0,opened={},root=o.root or 'D:/app',
  state=o.state or 'C:/state',saved={},pending={},reloads=0,watching=true,locked={},readonly={},unreadable={},pausedWrites=0,dirs={}}
 local function log(x) f.calls[#f.calls+1]=x end
 local function keep(t,k) f.saved[#f.saved+1]={t,k,t[k]} end
 local appRoot,stateRoot=f.root..'/',f.state..'/'
 local function inApp(path) return type(path)=='string' and (path==f.root or path:sub(1,#appRoot)==appRoot) end
 local function inState(path) return type(path)=='string' and (path==f.state or path:sub(1,#stateRoot)==stateRoot) end
 -- AdvancedIA installé à côté de l'app (même dossier parent), dont SpotterEnginer lit le pont (src/bridge_layout.lua).
 local aaiRoot=(f.root:match('^(.*)/[^/]+$') or '')..'/AdvancedIA/'
 f.aaiRoot=aaiRoot
 local function inAai(path) return type(path)=='string' and path:sub(1,#aaiRoot)==aaiRoot end
 local function under(path) return inApp(path) or inState(path) or inAai(path) end
 local function rel(path)
  if inApp(path) then return path:sub(#appRoot+1) end
  if inAai(path) then return 'aai:'..path:sub(#aaiRoot+1) end
  return 'state:'..path:sub(#stateRoot+1)
 end
 -- Écriture dans le dossier de l'app : rechargement en direct si la surveillance n'est pas suspendue.
 local function touched(path)
  if not inApp(path) then return end
  if not f.watching and f.autoResume then f.pausedWrites=f.pausedWrites+1; if f.pausedWrites>f.autoResume then f.watching=true end end
  if f.watching then f.reloads=f.reloads+1; log('reload '..rel(path)) end
 end
 -- Dossiers parents d'un chemin (hors racines), créés au besoin.
 local function parents(path)
  local d=type(path)=='string' and path:match('^(.*)/[^/]*$')
  while d and under(d) and d~=f.root and d~=f.state do f.dirs[d]=true; d=d:match('^(.*)/[^/]*$') end
 end
 local function inside(dir,skip)
  local prefix=dir..'/'
  for path in pairs(f.files) do if path:sub(1,#prefix)==prefix then return true end end
  for path in pairs(f.dirs) do if path~=skip and path:sub(1,#prefix)==prefix then return true end end
  return false
 end
 local function dirExists(path) return f.dirs[path]==true or inside(path) end
 local function later(fn) if f.async then f.pending[#f.pending+1]=fn else fn() end end
 function f.zip(entries) f.count=f.count+1; local id='ZIP#'..f.count; f.zips[id]=entries; return id end
 local function zipOf(source) return f.zips[source] or f.zips[f.files[source] or ''] end
 function f.watch() f.watching=true end
 -- Globales de CSP absentes du banc : posées sans passer par le garde des globales.
 f.web,f.JSON=rawget(_G,'web'),rawget(_G,'JSON')
 rawset(_G,'web',{get=function(url,headers,cb)
  assert(type(url)=='string' and type(cb)=='function' and (headers==nil or type(headers)=='table'))
  log('get '..url)
  local function answer()
   local r=f.responses[url] or {status=404,body=''}
   local hops=0
   while r.redirect and hops<5 do hops=hops+1; log('redirect '..r.redirect); r=f.responses[r.redirect] or {status=404,body=''} end
   cb(r.err,r.err==nil and {status=r.status,body=r.body} or nil)
  end
  if f.hold or f.async then f.pending[#f.pending+1]=answer else answer() end
 end})
 rawset(_G,'JSON',{parse=function(text) local t=f.json[text]; if t==nil then error('json') end; return t end})
 function f.flush() while #f.pending>0 do local list=f.pending; f.pending={}; for _,fn in ipairs(list) do fn() end end end
 keep(ac,'checksumSHA256'); keep(ac,'restartApp'); keep(ac,'getFolder'); keep(ac,'FolderID'); keep(ac,'pauseFilesWatching')
 ac.checksumSHA256=function(data) return f.sha[data] or string.rep('0',64) end
 ac.restartApp=function() log('restartApp'); f.restarts=f.restarts+1; if f.onRestart then f.onRestart() end end
 ac.pauseFilesWatching=function(pause) f.watching=pause~=true; if pause==true then f.pausedWrites=0 end; log('pause '..tostring(pause)) end
 keep(ac,'log'); ac.log=function(text) f.csplog=f.csplog or {}; f.csplog[#f.csplog+1]=tostring(text) end
 local folders=ac.FolderID or {}; local getFolder=ac.getFolder
 ac.FolderID=setmetatable({ScriptOrigin=folders.ScriptOrigin or 1024,ExtCfgState=folders.ExtCfgState or 25},{__index=folders})
 ac.getFolder=function(id)
  if id==ac.FolderID.ScriptOrigin then return f.root end
  if id==ac.FolderID.ExtCfgState then return f.state end
  return getFolder and getFolder(id) or nil
 end
 keep(os,'openURL'); os.openURL=function(url) f.opened[#f.opened+1]=url end
 for _,name in ipairs({'load','save','fileExists','deleteFile','copyFile','move','createDir','createFileDir','scanDir','scanZip','loadFromZip','extractFromZipAsync','deleteDir','dirExists'}) do keep(io,name) end
 local orig={}; for _,s in ipairs(f.saved) do if s[1]==io then orig[s[2]]=s[3] end end
 io.load=function(path,...) if under(path) then return f.files[path] end; return orig.load(path,...) end
 io.save=function(path,data,ensure,...)
  if under(path) then
   if f.failSave and path:find(f.failSave,1,true) or f.readonly[path] then return false end
   if ensure==true and f.files[path]~=nil then f.files[path..'.bak']=f.files[path]; log('bak '..rel(path)) end
   touched(path); parents(path); f.files[path]=data; log('save '..rel(path)); return true
  end
  return orig.save(path,data,ensure,...)
 end
 io.fileExists=function(path) if under(path) then return f.files[path]~=nil end; return orig.fileExists(path) end
 io.deleteFile=function(path)
  if under(path) then
   if f.readonly[path] or f.failDelete and path:find(f.failDelete,1,true) then return false end
   if f.files[path]~=nil then touched(path) end; f.files[path]=nil; return true
  end
  return orig.deleteFile(path)
 end
 io.copyFile=function(a,b,failIfExists)
  if under(a) or under(b) then
   assert(under(a) and under(b),'copy outside the known folders: '..tostring(a)..' -> '..tostring(b))
   if f.files[a]==nil then return false end
   if failIfExists~=false and f.files[b]~=nil then return false end
   if f.unreadable[a] or f.locked[b] or f.readonly[b] or f.failCopy and b:find(f.failCopy,1,true) then return false end
   touched(b); parents(b); f.files[b]=f.files[a]; log('copy '..rel(b)); return true
  end
  return orig.copyFile and orig.copyFile(a,b,failIfExists)
 end
 io.move=function(a,b,replace,...)
  if under(a) or under(b) then
   if inApp(a)~=inApp(b) then return false end
   -- Dossier entier (MoveFileEx sur un dossier) : tous ses fichiers d'un bloc, destination absente.
   if f.files[a]==nil then
    local from,to=a..'/',b..'/'
    local moved={}
    for path in pairs(f.files) do if path:sub(1,#from)==from then moved[#moved+1]=path end end
    if (#moved==0 and not f.dirs[a]) or f.failDirMove then return false end
    if dirExists(b) then return false end
    for _,path in ipairs(moved) do f.files[to..path:sub(#from+1)]=f.files[path]; f.files[path]=nil end
    local dirs={}; for path in pairs(f.dirs) do if path==a or path:sub(1,#from)==from then dirs[#dirs+1]=path end end
    for _,path in ipairs(dirs) do f.dirs[path]=nil; f.dirs[b..path:sub(#a+1)]=true end
    parents(b..'/x'); f.dirs[b]=true
    log('movedir '..rel(b)); return true
   end
   if f.locked[a] or f.locked[b] or f.readonly[b] then return false end
   if f.files[b]~=nil and not replace then return false end
   touched(a); touched(b); parents(b); f.files[b]=f.files[a]; f.files[a]=nil; log('move '..rel(b)); return true
  end
  return orig.move(a,b,replace,...)
 end
 io.createDir=function(path) if under(path) then parents(path..'/x'); return true end; return orig.createDir and orig.createDir(path) end
 io.createFileDir=function(path) if under(path) then parents(path); return true end; return orig.createFileDir and orig.createFileDir(path) end
 io.deleteDir=function(path)
  if under(path) then
   if not f.dirs[path] or inside(path,path) then return false end
   f.dirs[path]=nil; log('rmdir '..rel(path)); return true
  end
  return orig.deleteDir and orig.deleteDir(path)
 end
 io.dirExists=function(path) if under(path) then return dirExists(path) end; return orig.dirExists and orig.dirExists(path) end
 io.scanDir=function(dir,mask,cb,...)
  if not under(dir) then return orig.scanDir(dir,mask,cb,...) end
  local prefix=dir..'/'; local seen={}; local names={}
  for path in pairs(f.files) do
   if path:sub(1,#prefix)==prefix then
    local rest=path:sub(#prefix+1); local name=rest:match('^[^/]+'); local folder=rest:find('/',1,true)~=nil
    if not seen[name] then seen[name]=folder; names[#names+1]=name elseif folder then seen[name]=true end
   end
  end
  -- Dossiers vides aussi listés (1.36).
  for path in pairs(f.dirs) do
   if path:sub(1,#prefix)==prefix then
    local name=path:sub(#prefix+1):match('^[^/]+')
    if name and seen[name]==nil then seen[name]=true; names[#names+1]=name elseif name then seen[name]=true end
   end
  end
  table.sort(names)
  -- Comme FindFirstFile : « . » et « .. » d'abord (dossiers).
  cb('.',{isDirectory=true}); cb('..',{isDirectory=true})
  for _,name in ipairs(names) do cb(name,{isDirectory=seen[name]==true}) end
 end
 io.scanZip=function(source) local z=zipOf(source); if not z then return nil end; local list={}; for name in pairs(z) do list[#list+1]=name end; table.sort(list); return list end
 io.loadFromZip=function(source,name) local z=zipOf(source); return z and z[name] or nil end
 io.extractFromZipAsync=function(source,dest,filter,cb)
  assert(inState(dest),'extraction outside the CSP state folder: '..tostring(dest))
  local z=zipOf(source)
  later(function()
   if not z or f.failExtract then cb('disk'); return end
   if type(filter)=='table' and filter.crucial and z[filter.crucial]==nil then cb('crucial'); return end
   for name,content in pairs(z) do f.files[dest..'/'..name]=content; parents(dest..'/'..name) end
   -- Fichier abîmé à l'extraction (disque) : f.corruptExtract, chemin de l'entrée.
   if f.corruptExtract then f.files[dest..'/'..f.corruptExtract]='abime' end
   log('extract '..rel(dest)); cb(nil)
  end)
 end
 function f.restore()
  for i=#f.saved,1,-1 do local s=f.saved[i]; s[1][s[2]]=s[3] end
  rawset(_G,'web',f.web); rawset(_G,'JSON',f.JSON)
 end
 -- Fichiers de l'app installée (version, contenu des fichiers) et paquet publié (zip, empreinte, réponses).
 function f.app(version,extra)
  f.files[appRoot..'manifest.ini']='[ABOUT]\nNAME=SpotterEnginer\nREQUIRED_VERSION=0.1\nVERSION='..version..'\n'
  f.files[appRoot..'SpotterEnginer.lua']='main '..version; f.files[appRoot..'src/update.lua']='update '..version
  f.files[appRoot..'src/remote.lua']='remote '..version; f.files[appRoot..'src/ui.lua']='ui '..version; f.files[appRoot..'sounds/beep.wav']='wav'
  f.files[appRoot..'src/bridge_layout.lua']=M.layout
  -- AdvancedIA installé, même pont.
  f.files[aaiRoot..'manifest.ini']='[ABOUT]\nNAME=AdvancedIA\nVERSION=Beta 1.51\n'; f.files[aaiRoot..'src/bridge_layout.lua']=M.layout
  for k,v in pairs(extra or {}) do f.files[appRoot..k]=v end
 end
 function f.release(version,options)
  options=options or {}
  -- Paquet binaire : l'identifiant du zip porte un octet nul, comme un vrai corps de réponse.
  local number=version:match('[%d%.]+$')
  local entries={[M.prefix..'manifest.ini']='[ABOUT]\nVERSION='..version..'\n',[M.prefix..'SpotterEnginer.lua']='main '..version,
   [M.prefix..'src/update.lua']='update '..version,[M.prefix..'src/remote.lua']='remote '..version,[M.prefix..'src/ui.lua']='ui '..version,
   [M.prefix..'src/new.lua']='new '..version,[M.prefix..'sounds/beep.wav']='wav',[M.prefix..'src/bridge_layout.lua']=M.layout}
  for k,v in pairs(options.entries or {}) do entries[k]=v or nil end
  f.count=f.count+1; local id='ZIP\0#'..f.count; f.zips[id]=entries; local hash=options.hash or string.rep('ab',32)
  f.sha[id]=options.actual or hash
  local base='https://github.com/VincentChevalier44/SpotterEnginer/releases/download/v'..number..'/'
  local name='SpotterEnginer-'..number
  f.json['release '..version]={tag_name='v'..number,draft=false,prerelease=false,published_at='2026-11-05T10:00:00Z',
   html_url='https://github.com/VincentChevalier44/SpotterEnginer/releases/tag/v'..number,body='## Beta '..number..'\n\n- **Nouveau** point\n- Second point\n',
   assets={{name=name..'.zip',size=options.size or #id,browser_download_url=base..name..'.zip'},{name=name..'.sha256',size=90,browser_download_url=base..name..'.sha256'}}}
  f.responses['https://api.github.com/repos/VincentChevalier44/SpotterEnginer/releases/latest']={status=options.apiStatus or 200,body='release '..version,err=options.apiErr}
  f.responses[base..name..'.sha256']={status=200,body=hash..'  '..name..'.zip\n'}
  -- Téléchargement servi par une redirection (release-assets.githubusercontent.com), suivie comme le fait WinHTTP.
  local asset='https://release-assets.githubusercontent.com/'..name..'.zip'
  f.responses[base..name..'.zip']={redirect=asset}
  f.responses[asset]={status=options.zipStatus or 200,body=options.body or id,err=options.zipErr}
  return id
 end
 -- Chemins du dossier de travail (src/remote.lua : <state>/SpotterEnginer-update).
 f.work=stateRoot..'SpotterEnginer-update'
 function f.find(x) for i,c in ipairs(f.calls) do if c==x then return i end end end
 function f.last(prefix) local at; for i,c in ipairs(f.calls) do if c:sub(1,#prefix)==prefix then at=i end end; return at end
 return f
end
return M
