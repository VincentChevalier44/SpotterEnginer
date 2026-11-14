-- Radio de la voiture regardée (1.3.9, demande du pilote : « quand je change de caméra, j'entends le spotter de la
-- voiture que j'ai sélectionnée ») : réglage spectatorRadio, actif par défaut. Jamais quand le joueur pilote (sa radio
-- seule) : seulement quand il ne pilote pas (abandon, IA au volant, voiture arrêtée dans la voie des stands ou au stand
-- plus de PARK s : retour aux stands d'une pénalité, garage), la caméra
-- sur une autre voiture depuis ENTER s. Après le damier, AdvancedIA suspend son pont : plus rien n'est dit.
-- Spotter : une instance à part, sur un contexte à part (voiture suivie à la place du joueur, données d'AdvancedIA
-- réduites aux états de course communs, réglages propres au joueur coupés, aucune écriture gardée). Ingénieur : un
-- petit ingénieur à part (pneus, freins, appel aux stands du plan qu'AdvancedIA publie pour cette voiture), jamais le
-- modèle de stratégie du joueur. La radio écrite porte le nom de la voiture et l'étiquette CAMÉRA.
local Spotter=require('src/spotter')
local Layout=require('src/bridge_layout')
local Say=require('src/say')
local Voice=require('src/voice')
local Link=require('src/link')
local Position=require('src/position')
local Timing=require('src/timing')
local M={}
M.ENTER=2
M.PARK=10
-- Champs du pont communs à toutes les voitures (liste blanche) : tout le reste garde sa valeur neutre.
M.GLOBAL={'neutral','neutralMode','ending','endingLeft','safetyPhase','red','greenLeft','relaunch','wet','wetSerial','pitsClosed'}
-- Valeurs neutres : selon le type, puis les sentinelles (aucune voiture lente, panneau et départ sans état, fenêtre
-- d'arrêt hors service, aucun message).
local NEUTRAL={}
for _,f in ipairs(Layout.fields) do
 local kind=f[2]
 if kind=='bool' then NEUTRAL[f[1]]=false elseif kind=='string' then NEUTRAL[f[1]]='' elseif kind~='struct' and kind~='array' then NEUTRAL[f[1]]=0 end
end
local SENTINEL={slowCar=-1,panelDecided='none',panelKind='none',standing='none',pitState='off',safetyPhase='none',neutralMode='local'}
for k,v in pairs(SENTINEL) do NEUTRAL[k]=v end
-- Réglages propres au joueur coupés pour la voiture regardée.
M.OFF={penaltiesVoice=false,trackLimits=false,deltaVoice=false,blueFlags=false,drsVoice=false,boxCalls=false,strategyTalk=false,
 engineerOn=false,aaiMessages=false,emergencies=false,flashVoice=false,rivalPenalties=false,setupLab=false,neutralBox=false,
 fasterBehind=false,pitExit=false,shRadar=false,
 -- Écarts à chaque tour (on ne suit une voiture que quelques tours).
 gapEvery=1}
local function neutralD()
 local d={}; for k,v in pairs(NEUTRAL) do d[k]=v end
 return d
end
function M.new() return {index=-1,since=nil,parkedAt=nil,on=false,s=nil,d=neutralD(),eng={},sayer=nil} end
-- Le joueur pilote-t-il ? Abandon ou IA au volant : non, tout de suite ; garé au stand (immobile) : non après PARK s.
function M.driving(st,F,now)
 local me=F.cars[F.player]
 if not me or not me.valid then return false end
 if me.retired or me.ai then st.parkedAt=nil; return false end
 if (me.inPit or me.pitlane) and (me.kmh or 0)<1 then
  st.parkedAt=st.parkedAt or now
  return now-st.parkedAt<M.PARK
 end
 st.parkedAt=nil
 return true
end
-- Voiture à faire parler (indice d'AC), ou -1 : réglage, joueur qui ne pilote pas, caméra sur une autre voiture
-- valide depuis ENTER s (sortie immédiate).
function M.target(st,F,cfg,now)
 local f=F.focus or -1
 local want=cfg.spectatorRadio and f>=0 and f~=F.player and F.cars[f] and F.cars[f].valid and not M.driving(st,F,now)
 if not want then st.since=nil; st.wanted=nil; return -1 end
 if st.wanted~=f then st.wanted=f; st.since=now end
 if now-st.since<M.ENTER then return -1 end
 return f
end
-- Contexte de la voiture regardée, refait à chaque image à partir de celui du joueur (tables gardées).
local function context(st,ctx,i)
 local F=ctx.F
 local c=st.ctx
 if not c then
  c={}; st.ctx=c
  c.Fp=setmetatable({},{__index=F})
  c.me=setmetatable({brake=0,lapValid=true,wheelsOut=0,cuts=0,kers=false,p2p=0,drsPresent=false,fuelMaps=1,hasBias=false,sector=-1,
   yaw=0,vz=0,hit=-1,susp={0,0,0,0},lookX=0,lookZ=1},{__index=F.view})
  c.link=setmetatable({},{__index=ctx.link})
  c.cfg=setmetatable({},{__index=function(_,k) local v=M.OFF[k]; if v~=nil then return v end; return ctx.cfg[k] end})
  c.keep={load=function() return nil end,store=function() end,resume=function() return false end}
 end
 c.Fp.player=i; c.Fp.me=c.me
 local d=ctx.link.d
 if d then for _,k in ipairs(M.GLOBAL) do st.d[k]=d[k] end; c.link.d=st.d else c.link.d=nil end
 c.ctx=c.ctx or {}
 local x=c.ctx
 x.F=c.Fp; x.link=c.link; x.cfg=c.cfg; x.say=st.sayer; x.voice=ctx.voice; x.timing=ctx.timing; x.side=ctx.side
 x.now=ctx.now; x.real=ctx.real; x.clock=ctx.clock; x.sectorName=ctx.sectorName
 x.trackLateral=nil; x.strategist=nil; x.emergency=nil; x.setuplab=nil; x.journal=ctx.journal; x.keep=c.keep; x.resumed=false
 x.superhudRadar=false
 return x
end
-- Petit ingénieur de la voiture regardée : appel aux stands d'AdvancedIA, pneus trop chauds ou froids, freins chauds.
local sayEngineer=Say.as('engineer')
local saySpotter=Say.as('spotter')
-- Arrivée sur une voiture (1.3.9, essai du pilote : rien entendu en restant 15 à 30 s sur une IA sans incident) : son
-- spotter donne tout de suite sa position et ses écarts devant et derrière (« Tu es P7. Écart devant : 1,2 seconde. »).
local function briefing(x,i)
 local F=x.F; local me=F.cars[i]
 if not F.isRace or not me or not me.valid or (me.position or 0)<1 then return end
 local parts={{pos=me.position}}
 local ahead,behind=Position.neighbours(F,me)
 local g=ahead and Timing.gap(x.timing,ahead,i,x.now,true) or nil
 if g then parts[#parts+1]='gapAhead'; parts[#parts+1]={n=g,dec=x.cfg.gapDecimals,unit='s'} end
 local gb=behind and Timing.gap(x.timing,i,behind,x.now,true) or nil
 if gb then parts[#parts+1]=g and 'andBehind' or 'gapBehind'; parts[#parts+1]={n=gb,dec=x.cfg.gapDecimals,unit='s'} end
 saySpotter(x,'gaps',3,parts,{ttl=6})
end
local function engineer(st,x,i)
 local F=x.F; local v=F.view; local cfg=x.cfg; local e=st.eng
 local lc=Link.car(x.link,i)
 local called=lc and lc.called or false
 if called and not e.called then sayEngineer(x,'box',1,{'boxThisLap'},{ttl=15}) end
 e.called=called
 if not (v and v.ok) or ((v.tyres[1] or {}).core or 0)<=0 then return end
 local hot,cold=0,0
 for k=1,4 do
  local t=v.tyres[k]
  if (t.core or 0)>0 then
   if t.core>t.opt+(cfg.tyreHot or 12) then hot=hot+1 elseif t.core<t.opt-(cfg.tyreCold or 15) then cold=cold+1 end
  end
 end
 local state=hot>=2 and 'hot' or cold>=3 and 'cold' or 'ok'
 if state~=e.tyres then
  if state=='hot' then sayEngineer(x,'tyreTemp',3,{'tyresHot'},{ttl=15,cooldown=60})
  elseif state=='cold' and e.tyres~=nil then sayEngineer(x,'tyreTemp',4,{'tyresCold'},{ttl=15,cooldown=60}) end
  e.tyres=state
 end
 local b=v.brakes
 local brakeHot=math.max(b[1] or 0,b[2] or 0,b[3] or 0,b[4] or 0)>(cfg.brakeHot or 850)
 if brakeHot and not e.brakes then sayEngineer(x,'brakes',3,{'brakesHot'},{ttl=15,cooldown=90}) end
 e.brakes=brakeHot
end
-- À chaque image active : radio de la voiture i (i<0 : aucune). Renvoie vrai si la radio est celle de la voiture
-- regardée (celle du joueur ne tourne pas alors). Entrée, changement de voiture et sortie : file vidée.
function M.step(st,ctx,i,playerSpotter)
 if i~=st.index then
  local was=st.index
  st.index=i
  if was>=0 or i>=0 then Voice.purge(ctx.voice,function(q) return tostring(q.key):sub(1,5)~='test:' end,true) end
  if i<0 then
   -- Retour au joueur : rien de ce qui a changé pendant ce temps n'est redit ; délais des annonces de l'autre voiture
   -- oubliés (une position dite pour elle ne bloque pas celle du joueur).
   if playerSpotter then playerSpotter.prev=nil end
   if Voice.forgetAll then Voice.forgetAll(ctx.voice) end
   st.s=nil; st.eng={}
   return false
  end
  st.s=Spotter.new()
  -- Côtés : l'inversion apprise pour le joueur vaut pour toutes les voitures (repère du jeu).
  if playerSpotter then st.s.autoFlip=playerSpotter.autoFlip end
  st.eng={}
  st.d=neutralD()
  local car=ctx.F.cars[i]
  st.sayer=Say.new(ctx.voice,ctx.say.files,ctx.say.root,ctx.say.lang)
  st.sayer.prefix=(car and car.name or ('#'..(i+1)))..' · '..(st.cameraTag or 'CAMÉRA')..' · '
  st.sayer.chirp=ctx.say.chirp
  st.brief=true
 end
 if i<0 then return false end
 st.sayer.lang=ctx.say.lang; st.sayer.chirp=ctx.say.chirp
 local x=context(st,ctx,i)
 Spotter.step(st.s,x)
 if st.brief then st.brief=false; briefing(x,i) end
 engineer(st,x,i)
 return true
end
return M
