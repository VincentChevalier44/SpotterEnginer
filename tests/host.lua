-- Hôte CSP factice pour les tests d'intégration : ac, ui, io, JSON, vec2, rgbm, script. Les structures ac.connect sont
-- partagées par clé (deux scripts qui se connectent avec la même clé voient la même table). Les appels de dessin sont
-- comptés ; les polices poussées et dépilées doivent s'équilibrer à chaque fenêtre.
local H={clock=0,files={},fonts=0,maxFonts=0,draws=0,texts={},shared={},played={},logs={},clips=0,storage={}}
HOST=H
SPE_TEST={}
function vec2(x,y) return {x=x or 0,y=y or 0} end
function vec3(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
function rgbm(r,g,b,m) return {r=r,g=g,b=b,mult=m} end
script={}
-- JSON réduit aux tables plates (réglages).
local function ser(v)
 if type(v)=='string' then return string.format('%q',v) end
 if type(v)=='table' then local out={} for k,x in pairs(v) do out[#out+1]='['..ser(k)..']='..ser(x) end return '{'..table.concat(out,',')..'}' end
 return tostring(v)
end
JSON={stringify=function(t) return 'return '..ser(t) end,
 parse=function(s) if type(s)~='string' or s=='' then return nil end local f=load(s); return f and f() or nil end}
os.preciseClock=function() return H.clock end
-- Fichiers : présents si listés dans H.files (chemins avec « / »).
io.fileExists=function(p) return H.files[(p:gsub('\\','/'))]~=nil end
io.dirExists=function(p) p=p:gsub('\\','/'); for k in pairs(H.files) do if k:sub(1,#p+1)==p..'/' then return true end end return false end
io.load=function(p,fallback) return H.files[(p:gsub('\\','/'))] or fallback end
-- Écriture (journal de session) : contenu gardé dans H.files.
io.open=function(p,mode)
 p=p:gsub('\\','/')
 if mode=='w' or H.files[p]==nil then H.files[p]='' end
 local f={}
 function f.write(_,s) H.files[p]=H.files[p]..s end
 function f.close() end
 function f.seek() return #H.files[p] end
 return f
end
io.move=function(a,b) a=a:gsub('\\','/'); b=b:gsub('\\','/'); H.files[b]=H.files[a]; H.files[a]=nil; return true end
io.scanDir=function(dir,mask,cb)
 dir=dir:gsub('\\','/'):gsub('/$','')
 for k in pairs(H.files) do
  local rest=k:sub(#dir+2)
  if k:sub(1,#dir+1)==dir..'/' and not rest:find('/') then cb(rest,{isDirectory=false}) end
 end
end
-- ui : dessin compté, aucune interaction.
ui={StyleColor={PopupBg=1,Border=2,Text=3}}
local zero=vec2(0,0)
H.space=vec2(860,640)
function ui.getCursor() return vec2(0,0) end
function ui.availableSpace() return H.space end
function ui.windowSize() return H.space end
-- Enregistrement des opérations de dessin (tools/apercu_ui.py) : coordonnées de l'écran (H.ox, H.oy : origine de la
-- fenêtre transparente en cours), police active, mesure exacte des textes (H.measure, fourni par Python).
H.ops={}; H.recordOn=false; H.ox=0; H.oy=0; H.fontStack={}
local function rec(op) if H.recordOn then H.ops[#H.ops+1]=op end end
function ui.pushDWriteFont(name) assert(type(name)=='string' or type(name)=='table','font'); H.fonts=H.fonts+1; if H.fonts>H.maxFonts then H.maxFonts=H.fonts end; H.fontStack[#H.fontStack+1]=name end
function ui.popDWriteFont() H.fonts=H.fonts-1; assert(H.fonts>=0,'font popped twice'); H.fontStack[#H.fontStack]=nil end
local function currentFont() local f=H.fontStack[#H.fontStack]; return type(f)=='string' and f or 'Barlow' end
function ui.dwriteDrawText(str,size,pos,col) assert(type(str)=='string','text '..tostring(str)); assert(size>0,'size'); assert(pos.x==pos.x,'nan pos'); H.draws=H.draws+1; H.texts[#H.texts+1]=str
 rec({kind='text',str=str,size=size,x=pos.x+H.ox,y=pos.y+H.oy,col=col,font=currentFont()}) end
function ui.measureDWriteText(str,size)
 if H.measure then return vec2(H.measure(currentFont(),str,size),size*1.2) end
 return vec2(#str*size*0.5,size*1.2)
end
function ui.drawRectFilled(p1,p2,col) H.draws=H.draws+1; rec({kind='rect',x1=p1.x+H.ox,y1=p1.y+H.oy,x2=p2.x+H.ox,y2=p2.y+H.oy,col=col}) end
function ui.drawRect(p1,p2,col,r,flags,th) H.draws=H.draws+1; rec({kind='rectline',x1=p1.x+H.ox,y1=p1.y+H.oy,x2=p2.x+H.ox,y2=p2.y+H.oy,col=col,th=th}) end
function ui.drawLine(p1,p2,col,th) H.draws=H.draws+1; rec({kind='line',x1=p1.x+H.ox,y1=p1.y+H.oy,x2=p2.x+H.ox,y2=p2.y+H.oy,col=col,th=th}) end
function ui.drawCircleFilled(p,r,col) H.draws=H.draws+1; rec({kind='circle',x=p.x+H.ox,y=p.y+H.oy,r=r,col=col}) end
function ui.drawQuadFilled(a,b,c,d,col) H.draws=H.draws+1; rec({kind='poly',pts={a.x+H.ox,a.y+H.oy,b.x+H.ox,b.y+H.oy,c.x+H.ox,c.y+H.oy,d.x+H.ox,d.y+H.oy},col=col}) end
function ui.drawTriangleFilled(a,b,c,col) H.draws=H.draws+1; rec({kind='poly',pts={a.x+H.ox,a.y+H.oy,b.x+H.ox,b.y+H.oy,c.x+H.ox,c.y+H.oy},col=col}) end
-- Souris simulée : H.activeId (bouton tenu), H.hoverId (survolé), H.rightClick (clic droit sur le survolé), H.delta,
-- H.clickId (bouton relâché : clic gauche), H.mouse (position à l'écran).
function ui.invisibleButton(id) H.lastId=id; return H.clickId~=nil and id==H.clickId end
function ui.itemHovered() return H.lastId~=nil and H.lastId==H.hoverId end
function ui.itemActive() return H.lastId~=nil and H.lastId==H.activeId end
function ui.mouseClicked(button) return button==1 and H.rightClick==true end
function ui.mouseDown() return false end
function ui.mouseLocalPos() return vec2(-100,-100) end
H.mouse=vec2(-100,-100)
function ui.mousePos() return H.mouse end
function ui.mouseWheel() return 0 end
function ui.mouseDelta() return H.delta or zero end
function ui.setCursor() end
function ui.pushClipRect() H.clips=H.clips+1 end
function ui.popClipRect() H.clips=H.clips-1; assert(H.clips>=0,'clip popped twice') end
function ui.setTooltip() end
-- Fenêtre transparente (overlays) : contenu dessiné aussitôt, à la taille de la fenêtre.
function ui.transparentWindow(id,pos,size,noPadding,inputs,content)
 assert(type(id)=='string' and size.x>0 and size.y>0,'overlay window')
 local prev=H.space; H.space=size; H.windows=(H.windows or 0)+1; H.windowIds[id]=true
 H.ox,H.oy=pos.x,pos.y
 content(); H.space=prev; H.ox,H.oy=0,0
end
H.windowIds={}
function ui.drawImage(path,p1,p2) assert(type(path)=='string','image path'); assert(p2.x>p1.x and p2.y>p1.y,'image box'); H.images=(H.images or 0)+1; H.draws=H.draws+1
 rec({kind='image',path=H.realIcon or path,x1=p1.x+H.ox,y1=p1.y+H.oy,x2=p2.x+H.ox,y2=p2.y+H.oy}) end
function ui.pushStyleColor() end
function ui.popStyleColor() end
-- ac
ac={FolderID={ACAppsLua=1,Logs=2},AudioChannel={Main='main'},StructItem={}}
-- Mémoire de la partie : vidée à la relance du jeu (ici : l'horloge de l'hôte revenue en arrière depuis la dernière
-- écriture) ; gardée au rechargement de l'app dans la même partie.
H.store={}; H.storeAt=0
local function sameGame() if H.clock<H.storeAt then H.store={} end; H.storeAt=H.clock end
function ac.store(k,v) sameGame(); H.store[k]=v end
function ac.load(k) sameGame(); return H.store[k] end
H.appsDir='C:/AC/apps/lua'
function ac.dirname() return H.appsDir..'/SpotterEnginer' end
function ac.getFolder() return H.appsDir end
function ac.log(...) H.logs[#H.logs+1]=table.concat({...},' ') end
function ac.getUI() return {windowSize=vec2(1920,1080),currentDesktop=H.desktop or 0} end
-- Touches tenues : H.keys[code]=true.
H.keys={}
function ac.isKeyDown(k) return H.keys[k]==true end
local S=ac.StructItem
for _,t in ipairs({'boolean','int32','uint32','float','double'}) do S[t]=function() return {t=t} end end
function S.string(n) return {t='string',n=n} end
function S.key(k) return {t='key',k=k} end
function S.array(e,n) return {t='array',e=e,n=n} end
function S.struct(f) return {t='struct',f=f} end
local function instance(layout)
 local o={}
 for name,item in pairs(layout) do
  if item.t=='array' then o[name]={}; for i=0,item.n-1 do o[name][i]=instance(item.e.f) end
  elseif item.t=='struct' then o[name]=instance(item.f)
  elseif item.t=='boolean' then o[name]=false
  elseif item.t=='string' then o[name]=''
  elseif item.t~='key' then o[name]=0 end
 end
 -- Comme une structure ac.connect (cdata) : un champ inconnu lu ou écrit est une erreur.
 return setmetatable(o,{__index=function(_,k) error('no member named '..tostring(k),2) end,
  __newindex=function(_,k) error('no member named '..tostring(k)..' (write)',2) end})
end
-- Signature du format : noms et types triés (deux scripts doivent passer exactement le même format).
local function signature(layout)
 local parts={}
 for name,item in pairs(layout) do
  local s=name..':'..item.t
  if item.t=='string' then s=s..item.n elseif item.t=='key' then s=s..item.k elseif item.t=='array' then s=s..item.n..'{'..signature(item.e.f)..'}' end
  parts[#parts+1]=s
 end
 table.sort(parts)
 return table.concat(parts,';')
end
function ac.connect(layout)
 local sig=signature(layout)
 local t=H.shared[sig]
 if not t then t=instance(layout); H.shared[sig]=t end
 return t
end
function ac.storage(layout,prefix)
 local t=H.storage[prefix or '']
 if not t then t={}; for k,v in pairs(layout) do t[k]=v end; H.storage[prefix or '']=t end
 return t
end
-- Audio : un clip dure 0,8 s.
ac.AudioEvent={}
function ac.AudioEvent.fromFile(p)
 local ev={path=p.filename,startedAt=nil}
 function ev:start() self.startedAt=H.clock; H.played[#H.played+1]=self.path end
 function ev:stop() self.startedAt=nil end
 function ev:isPlaying() return self.startedAt~=nil and H.clock-self.startedAt<0.8 end
 function ev:dispose() H.disposed=(H.disposed or 0)+1 end
 function ev:setVolumeChannel() end
 return ev
end
-- Simulation : H.sim, H.cars[i], H.session.
H.sim={isPaused=false,isReplayActive=false,isOnlineRace=false,currentSessionIndex=0,raceSessionType=3,isTimedRace=false,
 sessionTimeLeft=0,leaderLapCount=0,trackLengthM=4000,pitsSpeedLimit=80,ambientTemperature=22,roadTemperature=30,roadGrip=0.98,
 rainIntensity=0,rainWetness=0,rainWater=0,windSpeedKmh=0,windDirectionDeg=0,windVelocityKmh=vec2(0,0),allowedTyresOut=2,
 isSessionStarted=true,isSessionFinished=false,carsCount=0,weatherConditions={currentType=15,upcomingType=15,transition=0}}
H.session={type=3,laps=20,hasAdditionalLap=false,isTimedRace=false}
H.cars={}
function ac.getSim() return H.sim end
function ac.getSession() return H.session end
function ac.getCar(i) return H.cars[i] end
function ac.getDriverName(i) return 'Pilote '..(i+1) end
function ac.getCarID() return 'test_car' end
-- Piste circulaire du test : rayon H.radius, demi-largeur 6 m ; gauche (vers l'extérieur) = négatif.
H.radius=4000/(2*math.pi)
function ac.worldCoordinateToTrack(v) local r=math.sqrt(v.x*v.x+v.z*v.z); return vec3(-(r-H.radius)/6*(H.flipTrack and -1 or 1),0,0) end
H.audio={}
function ac.setAudioVolume(ch,v,car) H.audio[ch..':'..tostring(car)]=v end
function ac.getAudioVolume(ch,car,fallback) return H.audio[ch..':'..tostring(car)] or 1 end
function ac.onRelease(fn) H.release=fn end
function ac.getTrackSectorName(p) return string.format('Virage %d',math.floor(p*10)+1) end
ac.INIConfig={carData=function(_,name)
 local data={['tyres.ini']={FRONT={WEAR_CURVE='(0=98|2=100|10=99|20=96|30=91)',SHORT_NAME='M'},REAR={WEAR_CURVE='(0=98|2=100|10=99|20=96|30=91)'}},
  ['car.ini']={FUEL={MAX_FUEL='100'},PIT_STOP={TYRE_CHANGE_TIME_SEC='10',FUEL_LITER_TIME_SEC='0.4'}}}
 local d=data[name] or {}
 return {get=function(_,s,k,def) return d[s] and d[s][k] or def end}
end}
ac.DataLUT11={carData=function() return nil end}
function ac.readDataFile() return nil end
return H
