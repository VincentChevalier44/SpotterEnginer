-- Réglages de SpotterEnginer : valeurs par défaut, bornes et validation (un réglage illisible reprend sa valeur par
-- défaut). Module pur. Chaque réglage : {clé, défaut, min, max, pas} pour un nombre, {clé, défaut} pour un booléen,
-- {clé, défaut, {choix}} pour une liste.
local M={}
M.schema={
 -- Général
 {'language','FR',{'FR','EN'}},{'enabled',true},{'updateCheck',true},{'volume',1.7,0,2,0.05},{'chirp',true},{'variety',true},{'infoGap',12,0,60,1},{'repeatGap',180,0,600,10},{'duck',true},{'duckLevel',0.85,0.1,1,0.05},
 -- Spotter
 {'spotterOn',true},{'spotterVolume',1.0,0,2,0.05},{'raceControl',true},{'sideBySide',true},{'flipSides',false},
 {'stillThere',true},{'gaps',true},{'gapEvery',2,1,5,1},{'gapDecimals',1,0,2,1},{'closingAlert',0.3,0.1,1.5,0.05},
 {'blueFlags',true},{'backmarkers',true},{'fasterBehind',true},{'pitExit',true},{'hazards',true},{'rivalPenalties',true},
 -- 1.3.0 : anticipation, urgences, écarts en direct.
 {'anticipation',true},{'emergencies',true},{'gapEvents',true},
 {'trackLimits',true},{'drsVoice',false},{'deltaVoice',true},{'penaltiesVoice',true},{'flashVoice',true},{'aaiMessages',true},{'sec_penalties',true},{'sec_traffic',true},
 -- Ingénieur
 {'engineerOn',true},{'engineerVolume',1.0,0,2,0.05},{'pace',true},{'paceEvery',3,1,10,1},{'pushHold',true},{'positionCalls',true},{'positionLive',true},{'debrief',true},
 {'fuel',true},{'fuelMargin',1.0,0,5,0.25},{'fuelK',0.03,0.005,0.08,0.005},
 {'tyres',true},{'tyreCold',15,5,40,1},{'tyreHot',12,4,40,1},{'brakes',true},{'brakeHot',850,400,1200,10},
 {'biasDiff',180,60,400,10},{'damage',true},{'weather',true},{'wind',true},{'windMin',15,5,50,1},{'driving',true},
 {'drivingLoss',0.15,0.05,0.6,0.01},
 -- Stratégie
 {'strategyOn',true},{'tolerance',2.0,0.5,6,0.1},{'gripFloor',94,85,99,0.5},{'tempSens',0.02,0,0.06,0.005},
 {'trafficCost',1.5,0,5,0.1},{'pitLane',22,8,60,0.5},{'warmup',1.5,0,6,0.1},{'degPrior',0.05,0.0,0.5,0.01},
 {'boxCalls',true},{'neutralBox',true},{'neutralFactor',0.55,0.2,1,0.05},{'duels',true},{'rivalPitVoice',true},{'strategyTalk',true},{'sec_stratCalls',true},
 -- Overlays : réglages communs (comme SuperHUD et AdvancedIA)
 {'overlaysOn',true},{'clickThrough',true},{'hideReplay',true},{'hidePits',false},{'hotkeys',true},
 -- Édition en jeu (1.2.0) : bouton montré quand la souris bouge, position (-1 : en haut au centre), commune aux bureaux.
 {'editButton',true},{'editorX',-1,-1,7680,1},{'editorY',-1,-1,4320,1},
 {'radioLines',4,1,8,1},{'radioSeconds',10,3,30,1},
}
-- Réglages de chaque overlay (Spotter, Ingénieur, Stratégie), comme chaque bloc de SuperHUD : affiché, verrouillé,
-- position (-1 : automatique), échelle, fond (opaque, atténué à 38 %, transparent), opacité du fond et du contenu,
-- bande décorative, en-tête.
M.overlays={'spotter','engineer','strategy'}
-- Écran supposé tant que CSP ne donne pas sa taille (px).
M.screenDefault={x=1920,y=1080}
M.overlayKeys={'Show','Locked','X','Y','Scale','Background','Opacity','Content','Accent','Header'}
for _,o in ipairs(M.overlays) do
 local list={{o..'Show',true},{o..'Locked',true},{o..'X',-1,-1,7680,1},{o..'Y',-1,-1,4320,1},{o..'Scale',1,0.5,2.5,0.05},
  {o..'Background','solid',{'solid','ghost','transparent'}},{o..'Opacity',0.88,0,1,0.02},{o..'Content',1,0.3,1,0.05},
  {o..'Accent',true},{o..'Header',true}}
 for _,item in ipairs(list) do M.schema[#M.schema+1]=item end
end
-- Bureaux d'applications AC (1 à 4, comme SuperHUD) : chacun garde ses overlays (affichés, positions, tailles, fonds…)
-- et leurs réglages d'affichage communs ; le reste (spotter, ingénieur, voix) est commun à tous les bureaux.
M.desktopCount=4
M.desktopKeys={'overlaysOn','clickThrough','hideReplay','hidePits','radioLines','radioSeconds'}
for _,o in ipairs(M.overlays) do for _,sfx in ipairs(M.overlayKeys) do M.desktopKeys[#M.desktopKeys+1]=o..sfx end end
M.index={}
for k=1,#M.schema do M.index[M.schema[k][1]]=M.schema[k] end
-- Fenêtre de réglages (comme AdvancedIA) : onglets en haut ; dans chaque onglet, une colonne de sections groupées,
-- chacune avec son interrupteur (master : réglage qui l'active ; nil : section toujours active, sans rien à couper).
-- gate : section d'annonces seulement ; coupée, ses options booléennes valent « non » pour le spotter, l'ingénieur et
-- la stratégie (vue effective, M.effective), sans changer les choix enregistrés. Une seule table, lue par l'interface
-- et par la vue effective : ce qui est montré coupé est ce qui se tait.
M.tabs={'home','spotter','engineer','strategy','radio','overlays','diag'}
M.roles={spotter='spotterOn',engineer='engineerOn',strategy='strategyOn'}
M.sections={
 spotter={
  {'raceControl',{
   {id='flags',master='raceControl',keys={'blueFlags','aaiMessages'},gate=true},
   {id='delta',master='deltaVoice',keys={},gate=true},
   {id='drs',master='drsVoice',keys={},gate=true},
   {id='penalties',master='sec_penalties',keys={'penaltiesVoice','trackLimits','rivalPenalties'},gate=true}}},
  {'traffic',{
   {id='sides',master='sideBySide',keys={'stillThere','flipSides'},gate=true},
   {id='trafficCalls',master='sec_traffic',keys={'backmarkers','fasterBehind','hazards','anticipation','flashVoice'},gate=true},
   {id='emergencies',master='emergencies',keys={},gate=true},
   {id='pitExit',master='pitExit',keys={},gate=true},
   {id='gaps',master='gaps',keys={'gapEvents','gapEvery','gapDecimals','closingAlert'},gate=true}}}},
 engineer={
  {'raceGroup',{
   {id='pace',master='pace',keys={'paceEvery','pushHold','positionCalls','positionLive'},gate=true},
   {id='debrief',master='debrief',keys={},gate=true},
   {id='fuel',master='fuel',keys={'fuelMargin','fuelK'},gate=true},
   {id='driving',master='driving',keys={'drivingLoss'},gate=true}}},
  {'carGroup',{
   {id='tyres',master='tyres',keys={'tyreCold','tyreHot'},gate=true},
   {id='brakes',master='brakes',keys={'brakeHot','biasDiff'},gate=true},
   {id='damage',master='damage',keys={},gate=true}}},
  {'conditions',{
   {id='weather',master='weather',keys={},gate=true},
   {id='wind',master='wind',keys={'windMin'},gate=true}}}},
 strategy={
  {'stratCalc',{
   {id='plan',keys={},custom='plan'},
   {id='model',keys={'tolerance','gripFloor','tempSens','degPrior'}},
   {id='pits',keys={'pitLane','warmup','trafficCost','neutralBox','neutralFactor'}}}},
  {'stratRadio',{
   {id='stratCalls',master='sec_stratCalls',keys={'boxCalls','duels','strategyTalk','rivalPitVoice'},gate=true}}}},
 radio={
  {'radioLevels',{
   {id='volumes',keys={'volume','spotterVolume','engineerVolume'},custom='test'},
   {id='duck',master='duck',keys={'duckLevel'}}}},
  {'radioVoice',{
   {id='voice',keys={'language','chirp','variety'},custom='mute'},
   {id='pacing',keys={'infoGap','repeatGap'}},
   {id='log',keys={},custom='log'}}}},
 overlays={
  {'ovAll',{
   {id='desktops',keys={},custom='desktops'},
   {id='editor',master='editButton',keys={'editorX','editorY'},custom='editor'},
   {id='common',master='overlaysOn',keys={'clickThrough','hideReplay','hidePits','radioLines','radioSeconds'},custom='overlayActions'},
   {id='hotkeys',master='hotkeys',keys={},custom='hotkeys'}}},
  {'ovEach',{}}},
}
-- Une section par overlay : affiché (interrupteur), puis ses autres réglages, propres au bureau courant.
for _,o in ipairs(M.overlays) do
 local keys={}
 for _,sfx in ipairs(M.overlayKeys) do if sfx~='Show' then keys[#keys+1]=o..sfx end end
 local list=M.sections.overlays[2][2]
 list[#list+1]={id='ov_'..o,master=o..'Show',keys=keys,custom='overlay',overlay=o}
end
-- Toutes les sections d'un onglet, dans l'ordre ; section par identifiant.
M.sectionsOf={}; M.sectionById={}
for tab,groups in pairs(M.sections) do
 local list={}
 for _,g in ipairs(groups) do for _,sec in ipairs(g[2]) do list[#list+1]=sec; sec.tab=tab; sec.group=g[1]; M.sectionById[sec.id]=sec end end
 M.sectionsOf[tab]=list
end
-- Réglages d'une section (interrupteur compris) : remise à zéro et nombre de réglages modifiés.
function M.sectionKeys(sec)
 if sec.all then return sec.all end
 local all={}
 if sec.master then all[1]=sec.master end
 for _,k in ipairs(sec.keys) do all[#all+1]=k end
 sec.all=all
 return all
end
function M.sectionOn(cfg,sec) return sec.master==nil or cfg[sec.master]==true end
-- Vue effective des réglages pour la logique : lecture à travers les réglages (une écriture y va aussi) ; seules les
-- options booléennes des sections d'annonces coupées y valent « non ». Refaite après chaque changement (apply).
local gated={}
for _,tab in ipairs(M.tabs) do
 for _,sec in ipairs(M.sectionsOf[tab] or {}) do
  if sec.gate and sec.master then
   local keys={}
   for _,k in ipairs(sec.keys) do if type(M.index[k][2])=='boolean' then keys[#keys+1]=k end end
   gated[#gated+1]={master=sec.master,keys=keys}
  end
 end
end
function M.effective(cfg,eff)
 if not eff then eff=setmetatable({},{__index=cfg,__newindex=function(_,k,v) cfg[k]=v end}) end
 for _,g in ipairs(gated) do for _,k in ipairs(g.keys) do rawset(eff,k,nil) end end
 for _,g in ipairs(gated) do if cfg[g.master]~=true then for _,k in ipairs(g.keys) do rawset(eff,k,false) end end end
 return eff
end
function M.defaults()
 local t={}
 for k=1,#M.schema do local s=M.schema[k]; t[s[1]]=s[2] end
 return t
end
-- Valeur valide d'un réglage (bornée, au pas, du bon type) ou sa valeur par défaut.
function M.valid(key,value)
 local s=M.index[key]
 if not s then return nil end
 local d=s[2]
 if type(d)=='boolean' then if type(value)=='boolean' then return value end return d end
 if type(s[3])=='table' then for _,c in ipairs(s[3]) do if c==value then return value end end return d end
 if type(value)~='number' or value~=value then return d end
 local v=math.max(s[3],math.min(s[4],value))
 -- Au pas, sans l'erreur de la virgule flottante (1,7 et non 1,7000000000000002 : une valeur par défaut reste égale
 -- à elle-même, « réglage modifié » ne s'affiche pas à tort).
 if s[5] and s[5]>0 then v=tonumber(string.format('%.10g',s[3]+math.floor((v-s[3])/s[5]+0.5)*s[5])) end
 return math.max(s[3],math.min(s[4],v))
end
-- Bureau jamais configuré : réglages par défaut, aucun overlay affiché (comme un bureau vide de SuperHUD).
function M.emptyDesktop()
 local t={}
 for _,k in ipairs(M.desktopKeys) do t[k]=M.index[k][2] end
 for _,o in ipairs(M.overlays) do t[o..'Show']=false end
 return t
end
-- Bureaux enregistrés : une table par bureau (1 à 4), valeurs validées ; bureau absent : nil.
function M.loadDesktops(raw)
 local out={}
 if type(raw)~='table' then return out end
 for d=1,M.desktopCount do
  local page=raw[d] or raw[tostring(d)]
  if type(page)=='table' then
   local t=M.emptyDesktop()
   for _,k in ipairs(M.desktopKeys) do if page[k]~=nil then t[k]=M.valid(k,page[k]) end end
   out[d]=t
  end
 end
 return out
end
-- Version des réglages : les changements de valeur par défaut s'appliquent aussi aux réglages déjà enregistrés.
--   2 : DRS à la voix coupé par défaut (AdvancedIA a déjà son bip et son panneau).
--   3 : volume général 170 % et son de la voiture pendant la radio 85 % (réglages du pilote, 05/11/2026) ; seules les
--       valeurs restées aux anciens défauts (100 %, 40 %) changent : un choix fait à la main est gardé.
M.version=3
function M.load(raw)
 local t=M.defaults()
 if type(raw)=='table' then
  for k in pairs(t) do if raw[k]~=nil then t[k]=M.valid(k,raw[k]) end end
  local from=tonumber(raw.schema) or (next(raw)~=nil and 1 or M.version)
  if from<2 then t.drsVoice=false end
  if from<3 then
   if math.abs(t.volume-1.0)<1e-6 then t.volume=1.7 end
   if math.abs(t.duckLevel-0.4)<1e-6 then t.duckLevel=0.85 end
  end
 end
 t.schema=M.version
 return t
end
return M
