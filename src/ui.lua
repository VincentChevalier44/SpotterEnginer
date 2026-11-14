-- Fenêtre de réglages (thème Racing 26, kit src/kit.lua), organisée comme AdvancedIA : en-tête (titre, bureau,
-- liaison avec AdvancedIA, langue, interrupteur général), onglets inclinés en haut ; dans chaque onglet, à gauche
-- la colonne des sections groupées, chacune avec son interrupteur, à droite la section choisie et ses réglages.
-- Sections et réglages viennent d'une seule table (src/config.lua, M.sections) ; chaque réglage est dessiné depuis le
-- schéma : interrupteur, curseur ou segment selon le type.
local W=require('src/kit')
local Config=require('src/config')
local L=require('src/lang')
local Layout=require('src/bridge_layout')
local U=require('src/util')
local M={}
function M.new() return {tab='home',section={},scroll={},heights={},fonts=false,confirmReset=-1e9} end
local function modifiedIn(app,keys) local n=0; for _,k in ipairs(keys) do local s=Config.index[k]; if s and app.cfg[k]~=s[2] then n=n+1 end end; return n end
local function resetKeys(app,keys) for _,k in ipairs(keys) do local s=Config.index[k]; if s then app.set(k,s[2]) end end end
-- Section affichée d'un onglet : la dernière choisie, sinon la première ; jamais une section cachée (app facultative
-- absente : Config.shown, has = app.has).
local function current(v,tab,has)
 local id=v.section[tab]
 local sec=id and Config.sectionById[id]
 if not sec or sec.tab~=tab or not Config.shown(sec,has) then sec=Config.sectionsOf[tab][1]; v.section[tab]=sec.id end
 return sec
end
-- Titre et description d'une section (overlays : nom de l'overlay).
local function secText(sec)
 local t=L.t.sec[sec.id]
 if sec.overlay then return L.t.ovui.names[sec.overlay],L.t.sec.overlay[2] end
 return t and t[1] or sec.id,t and t[2] or ''
end
local function txt(group,key) local t=L.t[group]; return t and t[key] or key end
-- État de la liaison : texte et couleur de puce.
function M.linkChip(link)
 local kind=link.state=='connected' and 'g' or (link.state=='absent' or link.state=='version' or link.state=='nobridge') and 'r' or 'a'
 local text=txt('link',link.state)
 if link.state=='suspended' and link.reason~='' then text=text..' · '..(L.t.reason[link.reason] or link.reason) end
 return text,kind
end
-- Libellé d'un réglage : table des clés, sinon réglage d'un overlay (suffixe : Show, Scale, Background…).
local function labelOf(key)
 local l=L.t.keys[key]
 if l then return l end
 local suffix=key:match('^%l+(%u%a*)$')
 return suffix and L.t.okeys[suffix] or {key,''}
end
-- Position d'un overlay ou du bouton d'édition en jeu (X ou Y) : bornes de l'écran, -1 = automatique.
local function positionAxis(key) local o,axis=key:match('^(%l+)([XY])$'); if o and (Config.index[o..'Show'] or o=='editor') then return axis end return nil end
local function valueText(key,v)
 local s=Config.index[key]
 if positionAxis(key) and v<0 then return L.t.ovui.auto end
 if type(v)=='number' and (key:match('Volume$') or key=='volume' or key=='duckLevel' or key:match('Opacity$') or key:match('Content$')) then
  return string.format('%d %%',math.floor(v*100+0.5))
 end
 if type(v)=='number' and key:match('Scale$') then return U.fixed(v,2,L.mark())..'×' end
 if type(v)=='number' then
  local step=s[5] or 1
  local dec=step>=1 and 0 or step>=0.1 and 1 or step>=0.01 and 2 or 3
  return U.fixed(v,dec,L.mark())
 end
 return tostring(v)
end
-- Tables et identifiants de chaque ligne faits une fois (par libellé, par langue) : rien n'est alloué à chaque image.
local rowOpts=setmetatable({},{__mode='k'})
local rowLabels={}
local rowIds={}
local function rowId(key) local id=rowIds[key]; if not id then id='cfg_'..key; rowIds[key]=id end; return id end
-- Une ligne de réglage ; renvoie sa hauteur.
local function row(app,key,x,y,w)
 local s=Config.index[key]; local c=W.colors(); local cfg=app.cfg
 local label=labelOf(key)
 local v=cfg[key]
 local modified=v~=s[2]
 if type(s[2])=='boolean' then
  local opts=nil
  if label[2]~='' then opts=rowOpts[label]; if not opts then opts={note=label[2]}; rowOpts[label]=opts end end
  local h=W.toggleHeight(opts)
  if W.visible(y,h) then
   local clicked,right=W.toggle(rowId(key),label[1],x,y,w,v,label[2],false,modified,opts)
   if clicked then app.set(key,not v) elseif right then app.set(key,s[2]) end
  end
  return h
 elseif type(s[3])=='table' then
  if W.visible(y,32) then
   W.cell(label[1],x+2,y+8,w*0.45,12,c.body)
   local labels=rowLabels[key]
   if not labels or labels.lang~=L.lang then
    labels={lang=L.lang}
    local names=L.t.choices[key:match('(%u%a*)$') or key] or L.t.choices[key]
    for i,choice in ipairs(s[3]) do labels[i]=names and names[choice] or choice end
    rowLabels[key]=labels
   end
   local sel=1
   for i,choice in ipairs(s[3]) do if choice==v then sel=i end end
   local picked=W.segment(rowId(key),labels,x+w*0.5,y+5,w*0.5-2,22,sel,label[2])
   if picked and s[3][picked]~=v then app.set(key,s[3][picked]) end
   W.rect(x,y+31,w,1,c.ruleSoft)
  end
  return 32
 end
 local h=44
 if W.visible(y,h) then
  if modified then W.marker(x+2,y+9) end
  W.cell(label[1],x+(modified and 14 or 2),y+5,w*0.6,12,c.body)
  W.right(valueText(key,v),x+w-2,y+5,12,modified and c.cyanText or c.text,'mono')
  local lo,hi=s[3],s[4]
  local axis=positionAxis(key)
  if axis then local sc=app.screen and app.screen(); hi=sc and math.floor(axis=='X' and sc.x or sc.y) or Config.screenDefault[axis=='X' and 'x' or 'y'] end
  local nv,right=W.slider(rowId(key),x+2,y+24,w-4,math.min(v,hi),lo,hi,s[5],label[2]~='' and label[2] or nil,s[2])
  if nv then app.set(key,nv) elseif right then app.set(key,s[2]) end
  W.rect(x,y+h-1,w,1,c.ruleSoft)
 end
 return h
end
-- Panneau d'état de la liaison (accueil).
local function linkPanel(app,x,y,w)
 local c=W.colors(); local link=app.link
 local text,kind=M.linkChip(link)
 W.panel(x,y,w,96,c.block,10)
 local bar=kind=='g' and c.ok or kind=='r' and c.danger or c.warn
 W.rect(x,y,4,96,bar)
 W.titleFit(text,x+16,y+10,w-32,18,12,c.text)
 W.paragraph(L.t.linkWhy[link.state] or (L.t.reason[link.reason] or link.reason),x+16,y+36,w-32,12,c.muted)
 local rel=link.remoteRelease~='' and link.remoteRelease or link.release
 W.text(rel~='' and string.format(L.t.home.release,rel,link.remoteVersion>0 and link.remoteVersion or Layout.version) or L.t.home.noRelease,x+16,y+74,11,c.label,'mono')
 return 96
end
local function tile(app,id,key,title,desc,x,y,w)
 local on=app.cfg[key]
 local clicked=W.tile('tile_'..id,title,on and 'ON' or 'OFF',on and 'g' or 'n',desc,x,y,w,70,on)
 if clicked then app.set(key,not on) end
end
-- Clips manquants (avertissement) et essai de la voix : page Accueil et page Radio et voix.
local function missingClips(app,x,y,w)
 local missing=(app.voiceTotal or 0)-(app.voicePresent or 0)
 if missing>0 then y=y+W.message(string.format(L.t.home.missing,missing),x,y,w,'wn')+6 end
 return y
end
local function voiceTest(app,x,y,prefix)
 if W.visible(y,26) then
  W.label(L.t.home.test,x,y+6)
  local lw=W.labelWidth(L.t.home.test)+14
  if W.button(prefix..'test_spotter',L.t.home.testSpotter,x+lw,y,120,26) then app.test('spotter') end
  if W.button(prefix..'test_engineer',L.t.home.testEngineer,x+lw+130,y,120,26) then app.test('engineer') end
 end
end
-- Mise à jour depuis GitHub (src/update.lua), en tête de l'onglet Diagnostic (comme AdvancedIA ; l'en-tête porte le
-- bouton d'un clic) : état, notes de la version publiée, actions ; refus expliqué quand AdvancedIA installé ne publie
-- pas le pont attendu.
local UPDATE_KINDS={uptodate='ok',success='ok',done='ok',rolledback='ok',interrupted='wn',checking='mut',downloading='mut',verifying='mut',
 installing='mut',ready='mut',available='ok',driving='wn',none='mut',unchecked='mut',broken='er',aaiOld='wn',aaiNewer='wn',aaiMissing='er'}
local UPDATE_NOTES=6
local function updateText(app,u,view)
 local U2=L.t.upd; local s=U2.states; local r=u.release
 if (view=='success' or view=='rolledback' or view=='interrupted') and u.updated and u.phase~='restarting' then
  return string.format(U2.done[u.updated.kind],u.updated.from,u.updated.to)
 end
 local text
 if view=='uptodate' then text=string.format(s.uptodate,app.updateClock or '')
 elseif view=='downloading' then text=string.format(s.downloading,r and r.version or '',r and r.zip and U.fixed(r.zip.size/1048576,1,L.mark()) or '?')
 elseif view=='done' then text=string.format(s.done,r and r.version or '')..(u.restartLate and ' '..U2.restartLate or '')
 elseif view=='rolledback' then text=string.format(s.rolledback,u.previous or '')..(u.restartLate and ' '..U2.restartLate or '')
 elseif view=='ready' then text=string.format(s.ready,r and r.version or '')
 elseif view=='broken' then text=string.format(s.broken,u.brokenFile or '?')
 elseif view=='aaiOld' then text=string.format(s.aaiOld,r and r.version or '',r and r.needs or '?')
 elseif view=='aaiNewer' then text=string.format(s.aaiNewer,r and r.version or u.previous or '')
 elseif view=='unchecked' and app.cfg.updateCheck then text=s.soon
 else text=s[view] or view end
 if (view=='errNet' or view=='errRate') and (u.status or 0)>0 then text=text..string.format(U2.status,u.status) end
 if (u.detail or '')~='' and (view=='errWrite' or view=='errHash' or view=='errNet') then text=text..string.format(U2.detail,u.detail) end
 return text
end
local function updateBlock(app,x,y,w)
 local U2=L.t.upd; local u,port=app.updater,app.updatePort
 if not u or not port then return y end
 local c=W.colors()
 W.heading(U2.heading,x,y,w,string.format(U2.installed,app.version or '?')); y=y+30
 if not port.ready then return y+W.message(U2.unavailable,x,y,w,'mut')+8 end
 local Update=require('src/update')
 local view=Update.view(u,app.updateStopped)
 if view=='uptodate' and not app.updateClock then app.updateClock=os.date('%H:%M') end
 local kind=UPDATE_KINDS[view] or (view:sub(1,3)=='err' and 'er') or 'mut'
 y=y+W.message(updateText(app,u,view),x,y,w,kind)+6
 local r=u.release
 if r and Update.offered(u) then
  W.text(string.format(U2.availableFull,r.version,r.published or ''),x,y,12,c.cyanText,'cond'); y=y+18
  for k=1,math.min(UPDATE_NOTES,#(r.notes or {})) do if r.notes[k]~='' then y=y+W.paragraph(r.notes[k],x+8,y,w-8,11,c.muted)+2 end end
  y=y+4
 end
 -- Actions : une seule ligne de boutons.
 local bx=x
 local function button(id,label,action,style)
  local bw=math.max(120,W.width(label,12,'cond')+28)
  if W.button(id,label,bx,y,bw,26,false,nil,style) then app.updateAct(action) end
  bx=bx+bw+10
 end
 if Update.offered(u) and view~='aaiOld' and view~='aaiNewer' and view~='aaiMissing' then button('upd_install',U2.button,'install',not app.updateStopped and 'disabled' or nil) end
 if Update.cancelable[u.phase] and u.phase~='available' then button('upd_cancel',U2.cancel,'cancel') end
 if not Update.busy(u) then
  button('upd_check',(view:sub(1,3)=='err' or view:sub(1,3)=='aai') and U2.retry or U2.check,'check')
  if r then button('upd_notes',U2.notes,'notes') end
  if u.previous then button('upd_rollback',string.format(U2.rollback,u.previous),'rollback',not app.updateStopped and 'disabled' or nil) end
 end
 y=y+36
 y=y+row(app,'updateCheck',x,y,w)
 return y+W.message(U2.kept,x,y+4,w,'mut')+10
end
local HOME_ROWS={'volume','spotterVolume','engineerVolume','duck','duckLevel'}
local function home(app,x,y,w)
 y=y+linkPanel(app,x,y,w)+14
 local tw=(w-30)/4
 tile(app,'spotter','spotterOn',L.t.home.spotter,L.t.keys.spotterOn[2],x,y,tw)
 tile(app,'engineer','engineerOn',L.t.home.engineer,L.t.keys.engineerOn[2],x+tw+10,y,tw)
 tile(app,'strategy','strategyOn',L.t.home.strategy,L.t.keys.strategyOn[2],x+2*(tw+10),y,tw)
 tile(app,'overlays','overlaysOn',L.t.home.overlaysTile,L.t.keys.overlaysOn[2],x+3*(tw+10),y,tw)
 y=y+84
 -- Tous les overlays verrouillés ou déverrouillés d'un clic (comme « Déverrouiller tous les blocs » de SuperHUD), sur
 -- ce bureau ; l'état à côté.
 do
  local all=app.allLocked()
  local bw=math.min(300,(w-10)/2)
  if W.button('home_lockall',all and L.t.home.unlockAll or L.t.home.lockAll,x,y,bw,34,not all) then app.lockAll(not all) end
  W.dotChip(all and L.t.home.lockedState or L.t.home.editState,x+bw+12,y+8,all and 'n' or 'a')
  y=y+46
 end
 W.heading(L.t.home.voices,x,y,w,string.format(L.t.home.voicesOf,app.voicePresent or 0,app.voiceTotal or 0)); y=y+30
 -- Volumes de la radio, réglables ici avec l'essai de la voix juste dessous.
 for _,key in ipairs(HOME_ROWS) do y=y+row(app,key,x,y,w) end
 y=missingClips(app,x,y+8,w)
 y=y+W.message(L.t.home.silent,x,y,w,'mut')+10
 voiceTest(app,x,y,'')
 y=y+40
 return y+W.message(L.t.home.overlays,x,y,w,'ok')+14
end
-- Bureaux d'applications AC (comme SuperHUD) : bureau courant, overlays affichés sur chacun, copie, vidage.
local function desktopPanel(app,x,y,w)
 local c=W.colors(); local O=L.t.ovui
 local d=app.desktop or 1
 if not app.desktopAvailable then y=y+W.message(O.desktopNone,x,y,w,'wn')+6 end
 local counts=app.desktopCounts and app.desktopCounts() or {}
 local tw=(w-10*(Config.desktopCount-1))/Config.desktopCount
 for n=1,Config.desktopCount do
  local bx=x+(n-1)*(tw+10); local on=n==d
  W.rect(bx,y,tw,46,on and c.select or c.block)
  if on then W.frameRect(bx,y,tw,46,c.cyan) end
  W.text(W.upper(string.format(O.desktopN,n)),bx+10,y+6,13,on and c.cyanText or c.soft,'cond')
  local k=counts[n] or -1
  W.text(k<0 and O.desktopEmpty or string.format(O.desktopShown,k),bx+10,y+25,11,c.label,'body')
 end
 y=y+56
 local bw=(w-10)/2
 if W.button('desk_copy',O.copyAll,x,y,bw,28) then app.copyDesktopToAll() end
 if W.button('desk_clear',O.clearDesk,x+bw+10,y,bw,28) then app.clearDesktop() end
 return y+38
end
-- Résumé du plan (page Stratégie).
local function planSummary(app,x,y,w)
 local c=W.colors(); local t=app.engineer and app.engineer.strategist; local plan=t and t.plan
 local o=L.t.ov
 if t then W.label(t.status=='measured' and o.measured or o.estimated,x,y+2); y=y+22 end
 if not plan or not plan.ok then
  y=y+W.message(plan and (o.reasons[plan.reason] or plan.reason) or o.waitingLink,x,y,w,'mut')+10
  return y
 end
 local line
 if plan.optimal then
  local win=U.lapRange(plan.window[1],plan.window[2])
  line=string.format('%s %s   ·   %s T%d   ·   %s %d',o.window,win,o.optimal,plan.optimal,o.stops,plan.stops)
 else line=o.noStop end
 W.text(line,x,y,14,c.text,'cond'); y=y+24
 local mark=L.mark()
 W.text(string.format('%s %s s%s   ·   %s %s s   ·   %s %s L',o.deg,U.fixed(plan.degNow or 0,2,mark),o.perLap,o.pitLoss,U.fixed(t.loss or 0,1,mark),o.fuel,U.gap(plan.fuelSpare or 0,1,mark)),x,y,12,c.muted,'mono')
 y=y+20
 -- Ressortie prévue et duels (comme l'overlay Stratégie).
 local r=t.rejoin; local du=t.duel
 local parts={}
 if r then parts[#parts+1]=string.format('%s %s',o.rejoin,string.format(o.position,r.position)) end
 if du then
  parts[#parts+1]=string.format('%s %s',o.undercut,du.undercut and o.possible or o.no)
  parts[#parts+1]=string.format('%s %s',o.overcut,du.overcut and o.possible or o.no)
  if du.threat then parts[#parts+1]=o.threat end
 end
 if #parts>0 then W.text(table.concat(parts,'   ·   '),x,y,12,c.muted,'mono'); y=y+20 end
 return y+10
end
local function radioLog(app,x,y,w)
 local c=W.colors()
 local log=app.voice.log
 if #log==0 then return y+W.message(L.t.ui.logEmpty,x,y,w,'mut')+6 end
 for k=#log,math.max(1,#log-11),-1 do
  local e=log[k]
  local role=L.t.roles[e.role] or ''
  local col=e.role=='engineer' and c.warn or e.role=='race' and c.label or c.cyanText
  if W.visible(y,18) then
   W.text(role,x,y,11,col,'label')
   W.cell(e.text,x+92,y,w-110,12,e.spoken and c.text or c.muted)
   if e.spoken then W.circle(x+w-6,y+7,3,c.ok) end
  end
  y=y+18
 end
 return y+10
end
local function diag(app,x,y,w)
 local c=W.colors(); local link=app.link; local d=link.d; local D=L.t.diag
 local lines={
  {D.state,link.state..(link.reason~='' and (' · '..link.reason) or '')},
  {D.beat,tostring(link.lastBeat)},{D.release,(link.remoteRelease~='' and link.remoteRelease or link.release)..' · v'..tostring(link.remoteVersion)},
 }
 if d then
  lines[#lines+1]={D.session,string.format(D.sessionFmt,d.session,d.sessionType,d.profile)}
  lines[#lines+1]={D.player,string.format(D.playerFmt,d.player,d.carCount)}
  lines[#lines+1]={D.panel,string.format('%s / %s · %s',d.panelDecided,d.panelKind,d.panelTitle)}
 end
 local t=app.engineer and app.engineer.strategist
 if t and t.model then
  local m=t.model
  lines[#lines+1]={D.model,string.format(D.modelFmt,m.base,m.fuelPerLap,m.kmF,m.kmR,m.gripK,m.degLinear,m.pitLane)}
  lines[#lines+1]={D.cost,string.format('%.2f ms · %s',t.costMs or 0,t.status or '')}
 end
 lines[#lines+1]={D.radio,string.format(D.radioFmt,#app.voice.queue,app.voicePresent or 0,app.radioMuted and L.t.ui.mutedChip or 'OK')}
 lines[#lines+1]={D.bridge,app.bridgeWhy and tostring(app.bridgeWhy) or 'ac.connect OK'}
 lines[#lines+1]={D.errors,string.format('%d%s',app.errors and app.errors.count or 0,app.errors and app.errors.last~='' and (' · '..app.errors.last) or '')}
 lines[#lines+1]={D.duck,string.format('%.0f %%',(app.duckLevel and app.duckLevel() or 1)*100)}
 lines[#lines+1]={D.fonts,app.fontDir and 'Barlow / JetBrains Mono' or 'Segoe UI / Consolas'}
 lines[#lines+1]={D.desktop,app.desktopAvailable and string.format(D.desktopFmt,app.desktop or 1,Config.desktopCount) or D.desktopUnread}
 lines[#lines+1]={D.settings,string.format(D.settingsFmt,Config.version,#Config.schema)}
 y=updateBlock(app,x,y,w)+6
 W.heading(D.title,x,y,w); y=y+30
 for _,l in ipairs(lines) do
  if W.visible(y,18) then W.text(W.upper(l[1]),x,y+1,11,c.label,'label'); W.cell(l[2],x+130,y,w-130,12,c.text,'mono') end
  y=y+20
 end
 -- Réinitialiser tous les réglages : deux clics (le second dans les 4 s), la langue est gardée.
 y=y+14
 if W.visible(y,28) then
  local armed=app.real-(app.view and app.view.confirmReset or -1e9)<4
  if W.button('reset_all',armed and L.t.ui.confirm or L.t.ui.resetAll,x,y,320,28,armed,nil,armed and 'danger' or nil) then
   if armed then app.resetAll(); app.view.confirmReset=-1e9 else app.view.confirmReset=app.real end
  end
 end
 return y+40
end
-- Contenu propre à certaines sections, dessiné avant ou après leurs réglages ; renvoie le bas.
local CUSTOM={}
local BEFORE={plan=true,log=true,desktops=true,overlay=true,hotkeys=true,editor=true}
function CUSTOM.plan(app,x,y,w) return planSummary(app,x,y,w) end
function CUSTOM.log(app,x,y,w) return radioLog(app,x,y,w) end
function CUSTOM.desktops(app,x,y,w) return desktopPanel(app,x,y,w) end
function CUSTOM.hotkeys(app,x,y,w) return y+W.message(L.t.ovui.keys,x,y,w,'ok')+6 end
function CUSTOM.test(app,x,y,w)
 y=missingClips(app,x,y+10,w)
 voiceTest(app,x,y,'sec_')
 return y+36
end
function CUSTOM.mute(app,x,y,w)
 y=y+10
 if W.visible(y,28) then
  if W.button('radio_mute',app.radioMuted and L.t.ui.unmute or L.t.ui.mute,x,y,220,28,app.radioMuted) then app.toggleMute() end
 end
 y=y+38
 return y+W.message(L.t.home.silent,x,y,w,'mut')+6
end
-- Édition en jeu : ouvrir ou fermer depuis ici aussi, position du bouton, retour en haut au centre.
function CUSTOM.editor(app,x,y,w)
 local O=L.t.ovui; local cfg=app.cfg
 y=y+10
 if W.visible(y,28) then
  local bw=(w-10)/2
  if W.button('ed_toggle',app.editing and O.closeEditor or O.openEditor,x,y,bw,28,app.editing) then app.toggleEditor() end
  if W.button('ed_home',O.editorHome,x+bw+10,y,bw,28,false,nil,(cfg.editorX<0 and cfg.editorY<0) and 'disabled' or nil) then app.set('editorX',-1); app.set('editorY',-1) end
 end
 y=y+38
 local where=(cfg.editorX<0 and cfg.editorY<0) and O.editorAt or string.format(O.editorMoved,math.max(0,cfg.editorX),math.max(0,cfg.editorY))
 return y+W.message(where,x,y,w,'mut')+6
end
function CUSTOM.overlayActions(app,x,y,w)
 local O=L.t.ovui
 y=y+10
 local all=app.allLocked()
 local bw=(w-20)/3
 if W.visible(y,28) then
  if W.button('ov_lockall',all and O.unlockAll or O.lockAll,x,y,bw,28,not all) then app.lockAll(not all) end
  if W.button('ov_transp',O.transparent,x+bw+10,y,bw,28) then app.backgrounds('transparent') end
  if W.button('ov_solid',O.solid,x+2*(bw+10),y,bw,28) then app.backgrounds('solid') end
 end
 y=y+38
 return y+W.message(O.howto,x,y,w,'mut')+6
end
function CUSTOM.overlay(app,x,y,w,sec)
 local O=L.t.ovui; local o=sec.overlay
 local locked=app.cfg[o..'Locked']
 if W.visible(y,28) then
  local bw=(w-10)/2
  if W.button('ov_center_'..o,O.recenter,x,y,bw,28) then app.recenter(o) end
  if W.button('ov_lock_'..o,locked and O.unlock or O.lock,x+bw+10,y,bw,28,not locked) then app.set(o..'Locked',not locked) end
 end
 y=y+38
 if not locked then y=y+W.message(O.howto,x,y,w,'ok')+6 end
 return y+4
end
-- Onglets inclinés (comme AdvancedIA) sous l'en-tête ; point orange : rôle de l'onglet coupé.
local function tabs(app,v,fw)
 local c=W.colors()
 local tx=12
 for _,tab in ipairs(Config.tabs) do
  local label=W.upper(L.t.nav[tab])
  local w=W.width(label,14,'display')+24
  local id='tab_'..tab
  local clicked,hover,pressed=W.hit(id,tx,48,w,34)
  local cur=v.tab==tab
  W.frame().active[id]=cur
  local fill=cur and c.cyan or pressed and c.control or hover and c.block or nil
  if fill then W.quad(tx+8,48,tx+w+8,48,tx+w,82,tx,82,fill) end
  W.text(label,tx+12,56,14,cur and c.ink or hover and c.text or c.muted,'display')
  local role=Config.roles[tab]
  if role and not app.cfg[role] then W.circle(tx+w,57,3,c.warn) end
  if clicked then v.tab=tab end
  tx=tx+w+4
 end
 W.rect(0,82,fw,2,c.cyan)
end
-- Colonne de gauche : en tête l'onglet (ou le bureau) et l'interrupteur de son rôle, le nombre de sections actives ;
-- puis les sections groupées, chacune avec son interrupteur et le nombre de ses réglages modifiés.
local function column(app,v,tab,x,top,w,bottom)
 local c=W.colors()
 W.panel(x,top,w,bottom-top)
 local on,total=0,0
 for _,sec in ipairs(Config.shownOf(tab,app.has)) do if sec.master then total=total+1; if app.cfg[sec.master] then on=on+1 end end end
 local role=Config.roles[tab]
 local roleOn=not role or app.cfg[role]==true
 W.label(tab=='overlays' and string.format(L.t.ovui.desktopN,app.desktop or 1) or L.t.nav[tab],x+10,top+10,c.soft)
 local count=string.format(L.t.ui.sectionsOn,on,total)
 if role then
  W.right(count,x+w-48,top+10,11,c.label,'mono')
  local t=L.t.keys[role]
  if W.switch('role_'..tab,x+w-38,top+8,roleOn,t and (t[1]..' · '..t[2])) then app.set(role,not roleOn) end
 else W.right(count,x+w-10,top+10,11,c.label,'mono') end
 W.rect(x,top+29,w,1,c.ruleHead)
 local listTop=top+30; local height=bottom-listTop-4
 local key='nav_'..tab
 local offset=W.scroll(v.scroll,key,x,listTop,w,height,v.heights[key] or 0)
 W.clip(x,listTop,w,height)
 local y=listTop+2-offset
 local cur=current(v,tab,app.has)
 for _,g in ipairs(Config.sections[tab]) do
  -- Groupe dont toutes les sections sont cachées (app facultative absente) : rien, pas même son titre.
  local any=false
  for _,sec in ipairs(g[2]) do if Config.shown(sec,app.has) then any=true end end
  if any then
   if W.visible(y,22) then W.text(W.upper(L.t.groups[g[1]] or g[1]),x+10,y+8,11,c.group,'label') end
   y=y+26
   for _,sec in ipairs(g[2]) do
    local shown=Config.shown(sec,app.has)
    if shown and W.visible(y,28) then
     local secOn=Config.sectionOn(app.cfg,sec)
     local n=modifiedIn(app,Config.sectionKeys(sec))
     -- Nom court dans la colonne quand le titre complet n'y tient pas.
     local short=L.t.sec[sec.id] and L.t.sec[sec.id][3]
     local name=short or secText(sec)
     if W.nav('sec_'..sec.id,name,x,y,w,cur==sec,not secOn or not roleOn,n>0 and tostring(n) or '',nil,28) then v.section[tab]=sec.id end
     if sec.master and W.switch('sec_sw_'..sec.id,x+w-38,y+6,secOn) then app.set(sec.master,not secOn) end
    end
    if shown then y=y+28 end
   end
   y=y+4
  end
 end
 W.clip()
 v.heights[key]=y+offset-listTop+8
end
-- Volet de droite : titre, puces (bureau, état), interrupteur de la section, réinitialiser ; description, réglages
-- modifiés, message si la section (ou le rôle) est coupée ; puis ses réglages, grisés mais réglables si coupée.
local function pane(app,v,tab,sec,x,top,w,bottom)
 local c=W.colors()
 W.panel(x,top,w,bottom-top)
 local ix,iw=x+14,w-28
 local on=Config.sectionOn(app.cfg,sec)
 local role=Config.roles[tab]
 local roleOn=not role or app.cfg[role]==true
 local title,desc=secText(sec)
 local keys=Config.sectionKeys(sec)
 local n=modifiedIn(app,keys)
 local rw=0
 if n>0 then
  rw=math.max(130,W.width(W.upper(L.t.ui.reset),13,'display')+34)
  if W.button('reset_'..sec.id,L.t.ui.reset,x+w-14-rw,top+9,rw,28,false,L.t.ui.resetTip,'outline') then resetKeys(app,keys) end
 end
 local limit=x+w-14-(rw>0 and rw+10 or 0)
 local state=sec.master and (on and L.t.ui.active or L.t.ui.inactive) or L.t.ui.always
 local stateKind=sec.master and (on and 'g' or 'a') or 'n'
 local scope=tab=='overlays' and sec.id~='hotkeys' and sec.id~='desktops' and string.format(L.t.ovui.desktopN,app.desktop or 1) or nil
 local chipsW=W.chipWidth(state)+10+(scope and W.chipWidth(scope)+6 or 0)+(sec.master and 40 or 0)
 local upper=W.upper(title)
 local room=math.max(40,limit-ix-10-chipsW)
 local size=W.shrink(upper,room,22,15,'display')
 W.cell(upper,ix,top+10+(22-size)*0.5,room,size,c.text,'display')
 local cx=ix+math.min(W.width(upper,size,'display'),room)+10
 if scope then cx=cx+W.chip(scope,cx,top+14,'c')+6 end
 cx=cx+W.chip(state,cx,top+14,stateKind)+10
 if sec.master then
  local t=labelOf(sec.master)
  if W.switch('pane_sw_'..sec.id,cx,top+15,on,t[2]~='' and t[2] or t[1]) then app.set(sec.master,not on) end
 end
 local y=top+44
 local dh=W.paragraph(desc,ix,y,iw,12,c.label)
 if n>0 then dh=dh+W.paragraph(string.format(n==1 and L.t.ui.modifiedOne or L.t.ui.modifiedMany,n),ix,y+dh,iw,12,c.cyanText) end
 y=y+dh+8
 if not roleOn then y=y+W.message(string.format(L.t.ui.roleOff,L.t.nav[tab]),ix,y,iw,'wn')+6
 elseif not on then y=y+W.message(sec.overlay and L.t.ui.overlayOff or tab=='overlays' and L.t.ui.overlaysOff or L.t.ui.sectionOff,ix,y,iw,'wn')+6 end
 W.rect(ix,y,iw,1,c.ruleHead); y=y+8
 local height=bottom-8-y
 local key='pane_'..sec.id
 local offset=W.scroll(v.scroll,key,ix,y,iw+8,height,v.heights[key] or 0)
 W.clip(ix,y,iw+8,height)
 local cy=y-offset; local from=cy
 local custom=sec.custom and CUSTOM[sec.custom]
 if custom and BEFORE[sec.custom] then cy=custom(app,ix,cy,iw-6,sec) end
 local listFrom=cy
 for _,k in ipairs(sec.keys) do cy=cy+row(app,k,ix,cy,iw-6) end
 local listEnd=cy
 if custom and not BEFORE[sec.custom] then cy=custom(app,ix,cy,iw-6,sec) end
 if #sec.keys==0 and not custom then cy=cy+W.message(L.t.ui.noOther,ix,cy,iw-6,'mut')+6 end
 -- Voile (comme AdvancedIA) : réglages d'une section ou d'un rôle coupés, toujours modifiables.
 if (not on or not roleOn) and listEnd>listFrom then W.rect(ix-2,listFrom,iw,listEnd-listFrom,c.veil) end
 W.clip()
 v.heights[key]=cy-from+12
end
-- En-tête : version (pastille), en bleu avec un petit bouton « Mettre à jour · x » quand une version plus récente est
-- publiée (comme AdvancedIA) : actif à l'arrêt, grisé en roulant ; refusée (AdvancedIA à mettre à jour d'abord) :
-- bouton d'alerte, un clic ouvre l'onglet Diagnostic (de même après un échec : réseau, empreinte, écriture) ; pendant
-- l'installation, l'étape en cours. limit : bord gauche de la partie droite (le bouton s'y arrête, son texte réduit).
-- Renvoie la suite.
local AAI_VIEWS={aaiOld=true,aaiNewer=true,aaiMissing=true}
local function updateHeader(app,v,x,limit)
 local c=W.colors(); local U2=L.t.upd
 local u,port=app.updater,app.updatePort
 local Update=require('src/update')
 local view=u and port and port.ready and Update.view(u,app.updateStopped) or nil
 local offered=view and Update.offered(u) and u.release
 local version='v'..(app.version or '?')
 local vw=W.width(version,11,'mono')+10
 W.frameRect(x,15,vw,18,offered and c.cyan or c.rule); W.text(version,x+5,17,11,offered and c.cyanText or c.label,'mono')
 x=x+vw+8
 local failed=view and view:sub(1,3)=='err'
 if offered and (view=='available' or view=='driving' or AAI_VIEWS[view] or failed) then
  local r=u.release
  if v.updFor~=r.version or v.updLang~=L.lang then v.updFor=r.version; v.updLang=L.lang; v.updLabel=string.format(U2.header,r.version); v.updTip=string.format(U2.headerTip,r.version) end
  if AAI_VIEWS[view] or failed then
   local label=failed and U2.headerErr or U2.headerAai
   local bw=math.max(60,math.min(limit-x,W.width(W.upper(label),12,'display')+26+16)) -- icône d'alerte comprise
   if W.button('upd_header',label,x,12,bw,24,false,updateText(app,u,view),'danger','warn') then v.tab='diag' end
   return x+bw+12
  end
  local stopped=view=='available'
  local bw=math.max(60,math.min(limit-x,200,W.width(W.upper(v.updLabel),12,'display')+26))
  if W.button('upd_header',v.updLabel,x,12,bw,24,stopped,stopped and v.updTip or U2.states.driving,stopped and 'primary' or 'disabled') then app.updateAct('install') end
  return x+bw+12
 end
 local busy=view and U2.busy[view]
 if busy and not Update.reported(u) then return x+W.chip(busy,x,15,'c')+12 end
 return x+4
end
local LANGUAGES={'FR','EN'}
function M.draw(v,app)
 if not v.fonts then v.fonts=true; if W.fontDir~=app.fontDir then W.setFonts(app.fontDir) end end
 app.view=v
 L.set(app.cfg.language)
 local f=W.begin('spe')
 local c=W.colors()
 local w,h=f.w,f.h
 -- En-tête (comme AdvancedIA) : logo de l'app en haut à gauche, nom en deux tons (« ENGINER » couleur du casque),
 -- version, bureau, rôle si la place le permet ; à droite : liaison, radio coupée, langue, interrupteur général.
 W.rect(0,0,w,82,c.panel)
 local x=14
 if app.logo and (type(ui.drawImage)=='function' or type(ui.drawImage)=='cdata') then
  if pcall(ui.drawImage,app.logo,W.point(10,2),W.point(54,46)) then x=58 end
 end
 W.text('SPOTTER',x,10,23,c.text,'display')
 local bw=W.width('SPOTTER',23,'display')
 W.text('ENGINER',x+bw,10,23,c.brand,'display')
 x=x+bw+W.width('ENGINER',23,'display')+9
 -- Bord gauche de la partie droite (interrupteur, langue, liaison, radio coupée), dessinée ensuite.
 local chip,kind=M.linkChip(app.link)
 -- Fenêtre de réglages en jeu (comme SuperHUD) : petite croix à droite de l'interrupteur général.
 local cross=app.gameWindow and 34 or 0
 local edge=w-12-cross-44-90-W.dotChipWidth(chip)-(app.radioMuted and W.dotChipWidth(L.t.ui.mutedChip)+8 or 0)
 x=updateHeader(app,v,x,edge-12)
 local right=w-12
 if app.gameWindow then
  -- Ferme seulement cette fenêtre (la barre des applications de CSP la rouvre) ; les overlays restent.
  local clicked,hover=W.hit('close_window',right-28,12,28,28)
  if hover then W.rect(right-28,12,28,28,c.dangerBack,4) end
  local col=hover and c.dangerText or c.label
  W.line(right-19,21,right-9,31,col,1.6); W.line(right-9,21,right-19,31,col,1.6)
  W.help(L.t.ui.closeWindow,right-28,12,28,28,5)
  if clicked and app.closeGameWindow then app.closeGameWindow() end
  right=right-cross
 end
 if W.switch('master',right-30,16,app.cfg.enabled,L.t.keys.enabled[2]) then app.set('enabled',not app.cfg.enabled) end
 right=right-44
 local picked=W.segment('lang',LANGUAGES,right-76,12,76,24,app.cfg.language=='EN' and 2 or 1)
 if picked then app.set('language',picked==2 and 'EN' or 'FR') end
 right=right-90
 local cw=W.dotChipWidth(chip)
 local left=right-cw
 W.dotChip(chip,left,15,kind)
 if app.radioMuted then local mw=W.dotChipWidth(L.t.ui.mutedChip); left=left-mw-8; W.dotChip(L.t.ui.mutedChip,left,15,'r') end
 -- Bureau, puis le rôle de l'app : chacun seulement s'il tient avant la partie droite (fenêtre étroite).
 do
  local label=W.upper(string.format(L.t.ovui.desktopN,app.desktop or 1))
  local lw=W.width(label,12,'cond')+6
  if x+lw+Config.desktopCount*11<left-16 then
   W.text(label,x,16,12,c.cyanText,'cond')
   for n=1,Config.desktopCount do W.para(x+lw+(n-1)*11,19,8,8,n==(app.desktop or 1) and c.cyan or c.rule,2) end
   x=x+lw+Config.desktopCount*11+14
  end
 end
 if x+W.width(W.upper(L.t.appTitle),11,'label')<left-16 then W.label(L.t.appTitle,x,18) end
 tabs(app,v,w)
 local top=94
 if v.tab=='home' or v.tab=='diag' then
  -- Accueil et Diagnostic : pleine largeur, contenu qui défile.
  local x0,cw2=16,w-32-10
  local ch=h-top-10
  local key='page_'..v.tab
  local offset=v.scroll[key] or 0
  W.clip(x0,top,cw2+8,ch)
  local t0=top-offset
  local bottom=v.tab=='home' and home(app,x0,t0,cw2) or diag(app,x0,t0,cw2)
  W.clip()
  W.scroll(v.scroll,key,x0,top,cw2+10,ch,bottom-t0+10)
 else
  local navW=228
  column(app,v,v.tab,12,top,navW,h-12)
  pane(app,v,v.tab,current(v,v.tab,app.has),12+navW+10,top,w-12-navW-10-12,h-12)
 end
 W.finish()
end
return M
