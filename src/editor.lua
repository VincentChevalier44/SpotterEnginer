-- Édition des overlays en jeu (1.2.0), sans menu pause ni stands. Petit bouton OVERLAYS, montré quelques secondes quand
-- la souris bouge (et tant qu'elle le survole), déplaçable (glisser) ; un clic ouvre le panneau d'édition, dessiné sous
-- le bouton. Pendant l'édition (app.editing, jamais enregistré : un plantage ne laisse rien déverrouillé), les overlays
-- affichés sont déverrouillés : glisser pour déplacer, coin bas droit pour la taille (src/overlays.lua). Le panneau règle
-- chacun (affiché, taille, fond, opacités, bande, en-tête, recentrer) par les réglages de l'app (app.set : bureaux et
-- enregistrement inchangés). TERMINER (ou Ctrl+Alt+K) ferme le panneau et verrouille tout. Rappel IN_GAME, fenêtres
-- transparentes comme les overlays : aucune fenêtre du manifeste (CSP ne relit le manifeste qu'au lancement du jeu).
local W=require('src/kit')
local L=require('src/lang')
local U=require('src/util')
local Config=require('src/config')
local M={}
-- Bouton montré SHOW s après le dernier mouvement de la souris ; tailles (px, échelle 1) ; marge en haut ; un glissé
-- de moins de CLICK px reste un clic.
M.SHOW=3
M.LW,M.LH=150,28
M.PW=380
M.TOP=10
M.CLICK=4
M.ids={launcher='SpotterEnginer_edit',panel='SpotterEnginer_editpanel'}
function M.new()
 return {moveAt=-1e9,mx=nil,my=nil,h=320,drag=nil,moved=0,x=0,y=0,
  pos=vec2(0,0),size=vec2(M.LW,M.LH),ppos=vec2(0,0),psize=vec2(M.PW,320)}
end
local callable=require('src/port').callable
-- Ouvrir ou fermer l'édition ; fermée, tous les overlays sont verrouillés.
function M.toggle(app)
 app.editing=not app.editing
 if app.editing then app.editSel=app.editSel or Config.overlays[1] else app.lockAll(true) end
end
-- Position du bouton : réglage, ou en haut au centre (-1), bornée à l'écran.
local function place(st,app,sw,sh)
 local cfg=app.cfg
 local x=cfg.editorX>=0 and cfg.editorX or (sw-M.LW)/2
 local y=cfg.editorY>=0 and cfg.editorY or M.TOP
 st.x=U.clamp(x,0,math.max(0,sw-M.LW)); st.y=U.clamp(y,0,math.max(0,sh-M.LH))
end
-- Souris bougée depuis moins de SHOW s, ou sur le bouton. Sans position de la souris (CSP ancien) : toujours montré.
-- steering : pilotage à la souris en cours (elle bouge sans cesse : le bouton resterait affiché et prendrait les clics) ;
-- son mouvement ne compte pas, le bouton reste joignable en le survolant, en pause ou par Ctrl+Alt+K.
local function wanted(st,now,steering)
 if not callable(ui.mousePos) then return true end
 local m=ui.mousePos()
 if not steering and st.mx and (math.abs(m.x-st.mx)>0.5 or math.abs(m.y-st.my)>0.5) then st.moveAt=now end
 st.mx,st.my=m.x,m.y
 if m.x>=st.x and m.x<st.x+M.LW and m.y>=st.y and m.y<st.y+M.LH then st.moveAt=now end
 return now-st.moveAt<M.SHOW
end
local function launcher(st,app)
 W.beginOverlay('spe_edit',M.LW)
 local c=W.colors()
 local clicked,hover,active=W.hit('ed_launch',0,0,M.LW,M.LH)
 if active and callable(ui.mouseDelta) then
  -- Valeurs non arrondies pendant le geste (comme les overlays) ; seule la valeur enregistrée est arrondie.
  if not st.drag then st.drag={x=st.x,y=st.y} end
  local d=ui.mouseDelta()
  if d.x~=0 or d.y~=0 then
   st.moved=st.moved+math.abs(d.x)+math.abs(d.y)
   if st.moved>=M.CLICK then
    local sc=app.screen and app.screen()
    local sw=sc and sc.x or Config.screenDefault.x; local sh=sc and sc.y or Config.screenDefault.y
    st.drag.x=U.clamp(st.drag.x+d.x,0,math.max(0,sw-M.LW)); st.drag.y=U.clamp(st.drag.y+d.y,0,math.max(0,sh-M.LH))
    app.set('editorX',math.floor(st.drag.x+0.5)); app.set('editorY',math.floor(st.drag.y+0.5))
   end
  end
 end
 if clicked and st.moved<M.CLICK then M.toggle(app) end
 if not active then st.drag=nil; st.moved=0 end
 local on=app.editing
 W.para(0,0,M.LW,M.LH,on and c.cyan or active and c.controlActive or hover and c.controlHover or c.control)
 W.para(0,0,4,M.LH,on and c.ink or c.brand)
 local label=W.upper(L.t.ed.launcher)
 local size=W.shrink(label,M.LW-34,13,9,'display')
 local tw=W.width(label,size,'display')
 W.text(label,(M.LW-tw)/2+2,(M.LH-size*1.2)/2,size,on and c.ink or c.text,'display')
 W.help(L.t.ed.launcherTip,0,0,M.LW,M.LH,5)
 W.finish()
end
-- Libellés des fonds, faits une fois par langue.
local bgLabels={}
local function backgrounds()
 local lang=L.lang or 'FR'
 local t=bgLabels[lang]
 if not t then
  t={}; local choices=Config.index[Config.overlays[1]..'Background'][3]
  for i,k in ipairs(choices) do t[i]=L.t.choices.Background[k] or k end
  t.keys=choices; bgLabels[lang]=t
 end
 return t
end
-- Une ligne libellé + curseur + valeur ; renvoie le bas.
local function sliderRow(app,id,label,key,x,y,w,text)
 local c=W.colors(); local s=Config.index[key]
 W.text(W.upper(label),x,y+2,11,c.label,'label')
 local sx=x+130; local sw=w-130-58
 local v=W.slider(id,sx,y,sw,app.cfg[key],s[3],s[4],s[5],nil,s[2])
 if v then app.set(key,v) end
 W.right(text,x+w,y+1,12,c.text,'mono')
 return y+26
end
local function percent(v) return string.format('%d %%',math.floor(v*100+0.5)) end
local function panel(st,app)
 W.beginOverlay('spe_editp',M.PW)
 local c=W.colors(); local E=L.t.ed; local cfg=app.cfg
 local w=M.PW; local x=14; local iw=w-28
 W.panel(0,0,w,st.h,c.panel,12)
 W.rect(0,0,w-12,3,c.cyan)
 W.text(W.upper(string.format(E.title,app.desktop or 1)),x,11,15,c.text,'display')
 local bw=math.max(96,W.width(W.upper(E.done),12,'display')+28)
 if W.button('ed_done',E.done,w-14-bw,8,bw,24,true,E.doneTip,'primary') then M.toggle(app) end
 local y=42
 y=y+W.paragraph(E.hint,x,y,iw,11,c.muted)+8
 -- Les trois overlays : interrupteur (affiché sur ce bureau), nom, taille ; un clic sur la ligne la choisit.
 for _,o in ipairs(Config.overlays) do
  local sel=app.editSel==o; local shown=cfg[o..'Show']
  local clicked,hover=W.hit('ed_pick_'..o,x+44,y,iw-44,30)
  W.rect(x,y,iw,30,sel and c.select or hover and c.blockHover or c.block)
  if sel then W.rect(x,y,3,30,c.cyan) end
  if W.switch('ed_show_'..o,x+10,y+7,shown,E.showTip) then app.set(o..'Show',not shown) end
  W.text(W.upper(L.t.ovui.names[o]),x+52,y+7,13,shown and c.text or c.off,'cond')
  W.right(shown and percent(cfg[o..'Scale']) or W.upper(E.hidden),x+iw-10,y+8,11,sel and c.cyanText or c.label,'mono')
  W.help(E.pickTip,x+44,y,iw-44,30,3)
  if clicked then app.editSel=o end
  y=y+34
 end
 -- Overlay choisi : taille, fond, opacités, bande, en-tête, recentrer.
 local o=app.editSel or Config.overlays[1]
 y=y+6
 W.rect(x,y,iw,1,c.rule); y=y+10
 W.text(W.upper(L.t.ovui.names[o]),x,y,13,c.cyanText,'cond'); y=y+22
 y=sliderRow(app,'ed_scale_'..o,E.scale,o..'Scale',x,y,iw,percent(cfg[o..'Scale']))
 local labels=backgrounds()
 W.text(W.upper(E.background),x,y+6,11,c.label,'label')
 local cur=1; for i,k in ipairs(labels.keys) do if cfg[o..'Background']==k then cur=i end end
 local picked=W.segment('ed_bg_'..o,labels,x+130,y,iw-130,24,cur)
 if picked and labels.keys[picked] then app.set(o..'Background',labels.keys[picked]) end
 y=y+32
 y=sliderRow(app,'ed_op_'..o,E.opacity,o..'Opacity',x,y,iw,percent(cfg[o..'Opacity']))
 y=sliderRow(app,'ed_ct_'..o,E.content,o..'Content',x,y,iw,percent(cfg[o..'Content']))
 local half=iw/2
 if W.switch('ed_acc_'..o,x,y+2,cfg[o..'Accent']) then app.set(o..'Accent',not cfg[o..'Accent']) end
 W.text(W.upper(E.accent),x+40,y+3,11,c.soft,'label')
 if W.switch('ed_head_'..o,x+half,y+2,cfg[o..'Header']) then app.set(o..'Header',not cfg[o..'Header']) end
 W.text(W.upper(E.header),x+half+40,y+3,11,c.soft,'label')
 y=y+30
 if W.button('ed_center_'..o,E.recenter,x,y,iw,26) then app.recenter(o) end
 y=y+38
 st.h=y
 W.finish()
end
-- Rappel IN_GAME, après les overlays : bouton (s'il est voulu), panneau pendant l'édition, sous le bouton (au-dessus
-- s'il ne tient pas). Bouton caché : aucune fenêtre (rien ne prend les clics du jeu).
function M.hud(st,app)
 if not callable(ui.transparentWindow) then return end
 local cfg=app.cfg
 local sc=app.screen and app.screen()
 local sw=sc and sc.x or Config.screenDefault.x; local sh=sc and sc.y or Config.screenDefault.y
 place(st,app,sw,sh)
 local now=app.clock and app.clock() or 0
 local editing=app.editing==true
 local F=app.F
 local show=editing or cfg.enabled and cfg.editButton and not (F and F.replay) and wanted(st,now,F and F.mouseSteer and not F.paused)
 if not show then return end
 st.pos.x,st.pos.y=st.x,st.y
 if not st.drawLauncher then st.drawLauncher=function() launcher(st,app) end; st.drawPanel=function() panel(st,app) end end
 ui.transparentWindow(M.ids.launcher,st.pos,st.size,true,true,st.drawLauncher)
 if not app.editing then return end
 local px=U.clamp(st.x+M.LW/2-M.PW/2,0,math.max(0,sw-M.PW))
 local py=st.y+M.LH+6
 if py+st.h>sh then py=math.max(0,st.y-6-st.h) end
 st.ppos.x,st.ppos.y=px,py; st.psize.y=st.h
 ui.transparentWindow(M.ids.panel,st.ppos,st.psize,true,true,st.drawPanel)
end
return M
