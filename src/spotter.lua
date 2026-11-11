-- Spotter : direction de course, trafic et position autour du joueur. Module pur.
-- Direction de course : uniquement l'état décidé par AdvancedIA (pont), jamais le drapeau natif d'AC (AdvancedIA
-- l'impose lui-même) ; chaque annonce suit une transition de cet état (compteurs ou passage d'une valeur à une autre),
-- la première image après la connexion sert de référence (rien n'est annoncé de ce qui était déjà en cours, sauf une
-- neutralisation).
-- Trafic : côte à côte (src/proximity.lua), écarts devant et derrière (src/timing.lua), retardataires, trafic plus
-- rapide, sortie des stands, voiture arrêtée ou en difficulté devant, pénalités des adversaires directs.
local U=require('src/util')
local Say=require('src/say')
local Voice=require('src/voice')
local Proximity=require('src/proximity')
local Timing=require('src/timing')
local Link=require('src/link')
local Side=require('src/side')
local Position=require('src/position')
local Debrief=require('src/debrief')
local Hazards=require('src/hazards')
local M={}
local FIELDS={'neutral','neutralMode','ending','safetyPhase','red','greenLeft','zone','zoneDouble','slipperyLeft','slowCar',
 'panelDecided','warnLeft','meatballLeft','disqualified','nativePenalty','finished','deltaOn','deltaValue',
 'giveBack','penaltyId','penaltyKind','drsBeep','drsReason','drsBlocked','pitState','pitRemind','pitDue',
 'pitsClosed','maxStintMin','playerStintFor','wetSerial','wet','relaunch','standing','playerRestart','messageId',
 'messageTitle','messageText','aiSerial','aiTitle','aiShort','flashId','flashHeard','pitPosition','pitOpen','pitClose',
 'pitWaived','drsLapsLeft','penaltyReason','gridPlaced','gridPassed','messageKind','messageValue','messageExtra','jumpLeft','serial'}
-- Panneau du pilote décidé par AdvancedIA : états annoncés à leur apparition (clip, priorité, réglage qui les permet).
-- Quatrième valeur facultative : clé de l'annonce, partagée avec l'annonce voisine (jamais les deux à la fois).
-- « start » n'y est pas : c'est le drapeau vert natif d'AC, qu'AdvancedIA pose lui-même après son vert ; il arrive
-- quelques secondes après le vrai vert (écho constaté en jeu le 04/11/2026). Le départ est annoncé par « go ».
-- SC appelée, feux, départ et faux départ n'y sont plus : lus dans l'état d'AdvancedIA (safetyPhase, standing,
-- jumpLeft) dans la même image, alors que son panneau n'est refait que toutes les 0,25 s.
-- formationOff (AdvancedIA 1.60) : tour de formation abandonné sur un incident majeur ; standing reste « form » tant que
-- sa FCY dure (aucune annonce de neutralisation pendant un tour de formation) : c'est le panneau qui la fait dire.
local PANEL={native={'yellow',2,'raceControl','zone'},formationOff={'fcy',1,'raceControl','neutral'},standingLap={'formationLap',3,'raceControl','formation'},standingPit={'standingPit',3,'raceControl'},
 white={'lastLap',3,'raceControl'},
penaltyDrive={'driveThrough',1,'penaltiesVoice'},penaltyTeleport={'penaltyPits',1,'penaltiesVoice'}}
-- Pénalité du joueur décidée par AdvancedIA : clip selon la raison (coupure des gaz pour une raison inconnue).
local PENALTY={delta='penaltyDelta',pass='penaltyPass',red='penaltyRed',stop='penaltyStop',jump='penaltyJump'}
-- Avis d'arrêt d'AdvancedIA (Beta 1.49 ; règles F1 en course, tant que l'arrêt obligatoire est dû) : l'arrêt ne compte
-- qu'avec un autre composé sec. Chaque avis est une annonce du pont (messageKind), émise une fois par occurrence :
-- rappel avant l'entrée des stands (pitCompound, ou pitPlanSame si la stratégie Quick Pitstop garde le même composé ;
-- pitPlanSame aussi au départ), puis la décision (pitNotCounted ou pitValidated). Le rappel est dit par le spotter à
-- l'entrée de la voie des stands (voir laneCompound), la décision dès qu'elle arrive. Indépendants du plan de
-- l'ingénieur, qui décide du moment de l'arrêt, pas du composé.
-- {clip, priorité, durée de validité (s), durée de validité au départ (s)} ; le rappel arrive environ 20 s avant
-- l'entrée : jamais dit après l'arrêt.
-- Reprise (AdvancedIA 1.50, en course) : place figée du joueur, au drapeau rouge aux stands puis à la sortie de la voie
-- au tour de relance (restartPlace) ; une voiture classée derrière lui est devant : la doubler (restartRetake, à chaque
-- nouvelle cible, dit au plus toutes les 15 s, les autres écrites). La file formée derrière la voiture de sécurité
-- (scLeading) et sa sortie en piste (scOut, même image que safetyPhase « out », déjà dite) restent écrites.
-- Cinquième valeur : délai minimal entre deux annonces du même genre (s).
local PIT_NOTICE={pitCompound={'pitCompound',3,18},pitPlanSame={'pitPlanSame',3,18,45},
 pitNotCounted={'pitNotCounted',3,30},pitValidated={'pitValidated',4,30},
 restartPlace={'restartPlace',3,20},restartRetake={'restartRetake',2,8,nil,15},
 -- Départ d'AdvancedIA 1.60 (option raceStart) : tour de formation (extra 0 : départ arrêté ensuite, 1 : départ lancé),
 -- appel du départ lancé (value : place du joueur, extra : indice d'AC de la voiture à suivre, -1 en tête), vert du
 -- départ lancé. Clé « start » pour les deux derniers : le vert remplace l'appel encore en file.
 formation={'formationLap',2,12},rollStart={'rs',2,10},rollGreen={'go',1,4}}
-- Avant le départ (standing d'AdvancedIA 1.60) : tour de formation ou appel du départ lancé. La course y est
-- neutralisée (neutral, neutralMode « fcy », relaunch) sans que ce soit une neutralisation ni une relance à annoncer.
local function prestart(x) return x.standing=='form' or x.standing=='roll' end
function M.new()
 return {prev=nil,spare=nil,deltaSign=0,prox=Proximity.new(),gapLap=-1,lastGaps={},backmarkers={},faster={},closing={},fastPending={},
  mistakes={},rivalState={},rivalNow={},exitSpline=nil,exitSamples=0,exitAlt=nil,exitAltN=0,inLane={},cuts=0,lapValid=true,
  stint=false,leftBox=false,autoFlip=false,sideAgree=0,sideDisagree=0,sideAtL=-1e9,sideAtR=-1e9,wasL=false,wasR=false,neutralEndAt=-1e9,greenPending=false,lastLapSaid=false,deltaQueuedAt=nil,proxCfg=nil,proxMe=nil,
  zoneAt=-1e9,zoneGreenAt=-1e9,deltaAbove=nil,penaltyAt=-1e9,blackAt=-1e9,compound=false,wasLane=false,laneCompound=false,planPending=false,planSaid=false,finishSaid=false,finishAt=false,finishStale=false,
  haz=Hazards.new(),incoming={},incomingSince={},incomingSeen={},incomingAt=-1e9,sideCarL=-1,sideCarR=-1,chaseOn=false,clearBehindAt=-1e9,
  liveAt=-1e9,inAhead=false,inBehind=false,inAheadCar=-1,inBehindCar=-1,slowAt=nil}
end
-- Changement de séance : tout repart de zéro (référence de la direction de course comprise), sauf ce qui est appris
-- sur le circuit (sortie des stands, côtés inversés).
local LEARNT={'exitSpline','exitSamples','exitAlt','exitAltN','autoFlip'}
function M.reset(s) U.refill(s,M.new(),LEARNT) end
local function copy(d,into)
 for k=1,#FIELDS do local f=FIELDS[k]; into[f]=d[f] end
 return into
end
local say=Say.as('spotter')
-- Annonces qui n'ont plus de sens à la fin d'une neutralisation ou d'un drapeau rouge.
local AFTER_NEUTRAL={delta=true,vscEnding=true,scIn=true,neutral=true,boxNeutral=true,red=true,scOut=true}
local AFTER_ZONE={zone=true}
local AFTER_ENDING={vscEnding=true}
local AFTER_SCIN={scIn=true}
local AFTER_DELTA={delta=true}
local AFTER_LIGHTS={start=true}
-- Clip d'une neutralisation : SC appelée ou en piste, VSC, FCY (nil : mode inconnu).
local function neutralClip(cur)
 if cur.neutralMode=='sc' then return cur.safetyPhase=='call' and 'scCall' or 'sc' end
 return (cur.neutralMode=='vsc' or cur.neutralMode=='fcy') and cur.neutralMode or nil
end
-- Longueur de circuit des calculs de distance (m) : un circuit inconnu (0) ne donne pas de distances nulles.
local function trackLength(F) return math.max(U.MIN_TRACK,F.trackLength or 0) end
local sayEngineer=Say.as('engineer')
-- Tour d'arrêt du plan de l'ingénieur, si un plan annoncera le « box » (ingénieur, stratégie et appels actifs, plan
-- prêt : jamais sur les estimations des premiers tours) ; sinon nil, et les rappels d'AdvancedIA restent dits.
local function plannedLap(ctx)
 local cfg=ctx.cfg
 if not (cfg.engineerOn and cfg.strategyOn and cfg.boxCalls) then return nil end
 local t=ctx.strategist and ctx.strategist()
 local plan=t and t.plan
 if plan and plan.ok and plan.optimal and t.ready then return plan.optimal,t end
 return nil
end
M.plannedLap=plannedLap
-- Voiture qui arrive derrière : jugée sur l'écart en temps au même endroit de la piste (Timing.trackGap), que les
-- freinages et les virages ne font pas varier, et non sur les mètres ou les km/h (une voiture qui freine après le
-- joueur « allait plus vite » à chaque virage sans jamais le rattraper : annonces sans personne derrière, constaté le
-- 09/11/2026). Écart relevé toutes les every s pour les voitures à moins de range m derrière, gardé keep s, à toute
-- vitesse hors des stands. Elle arrive si elle gagne au moins rate s par s sur window s, ou fast s par s sur short s
-- (joueur qui a beaucoup ralenti), et rattrape l'écart en catch s au plus.
local CLOSE={every=0.25,short=1,window=3,keep=4,range=600,rate=0.1,fast=0.3,catch=15}
-- Trafic plus rapide : dit à moins de FASTER_GAP s.
local FASTER_GAP=2
-- Joueur au pas hors course (tête-à-queue, sortie de piste) : l'écart en temps ne voit une voiture arriver qu'une fois
-- qu'elle atteint l'endroit où il a ralenti, trop tard. Sous kmh km/h, une voiture à moins de range m derrière qui va
-- au moins faster km/h plus vite est annoncée sur les vitesses du moment (jamais si lent en roulant : pas de confusion
-- avec un freinage).
local CRAWL={kmh=30,faster=40,range=150}
-- Tour lancé d'AdvancedIA : dit seulement si la voiture arrive vraiment (CLOSE, à moins de FAST_CAR_MAX s) dans les
-- FAST_CAR_CONFIRM s qui suivent l'annonce ; deux annonces (IA différentes) espacées d'au moins FAST_CAR_GAP s.
local FAST_CAR_GAP,FAST_CAR_CONFIRM,FAST_CAR_MAX=8,6,3
local function name(ctx,i) local c=ctx.F.cars[i]; return c and c.valid and c.name or ('#'..tostring((i or -1)+1)) end
-- Ligne de radio d'une annonce d'AdvancedIA : « titre · texte », sans le titre quand le texte commence déjà par lui
-- (« Stratégie des stands : même composé prévu (SS) »), ou le titre seul.
local function aaiLine(title,text)
 title=title or ''; text=text or ''
 if text=='' then return title end
 if title=='' or text:sub(1,#title)==title then return text end
 return title..' · '..text
end
-- Texte d'une annonce d'AdvancedIA pour la radio, seulement s'il est dans la langue de l'app (sinon nil : texte du clip).
local function aaiText(ctx,title,text)
 local d=ctx.link.d
 local lang=d and type(d.language)=='string' and d.language:upper() or ''
 if lang~=ctx.say.lang or (text or '')=='' then return nil end
 return aaiLine(title,text)
end
-- Rappel du composé (règles F1) : dit à l'entrée de la voie des stands, quand le pilote se dirige vers son
-- emplacement, à n'importe quel tour, tant que l'arrêt obligatoire est dû (demande du pilote, 05/11/2026). Les rappels
-- d'AdvancedIA avant l'entrée (à chaque approche) ne sont ni dits ni écrits : son panneau les montre, et le dernier
-- donne le genre et le texte (composés) de l'annonce de la voie. Seul l'avis de stratégie du départ (même composé
-- prévu) est dit à l'avance, le temps de changer la stratégie des stands : une seule fois par séance, et pas avant
-- la moitié du premier tour (départ laissé tranquille ; demande du pilote, 05/11/2026), voir planNotice. Un rappel
-- d'AdvancedIA reçu dans la voie avant l'annonce (entrée vue sans rappel connu) est dit à sa place.
local HINT={pitCompound=true,pitPlanSame=true}
local PLAN_SAME={pitPlanSame=true}
local function hintWanted(s,ctx,cur)
 local me=ctx.F.cars[ctx.F.player]
 if not me then return true end
 if cur.messageKind=='pitPlanSame' and (me.laps or 0)<1 then if not s.planSaid then s.planPending=true end; return false end
 if me.pitlane and not s.laneCompound then s.laneCompound=true; return true end
 return false
end
-- Avis du départ (stratégie au même composé), gardé jusqu'à la moitié du premier tour : dit une fois, s'il est encore
-- vrai (dernier rappel d'AdvancedIA du même genre, arrêt obligatoire encore dû). Moitié du tour : tour 1 fini, ou
-- ligne franchie et mi-tour atteint (la grille est juste avant la ligne : spline vers 0,9 à 1).
local function planNotice(s,ctx,cur)
 local me=ctx.F.cars[ctx.F.player]
 if not me then return end
 local half=(me.laps or 0)>=1 or (me.spline or 0)>=0.5 and (me.spline or 0)<0.8
 if not half then return end
 s.planPending=false
 local c=s.compound
 local due=not cur.pitWaived and (cur.pitState=='pending' or cur.pitState=='open' and cur.pitDue>0)
 if not c or c.kind~='pitPlanSame' or not due or not ctx.cfg.raceControl then return end
 s.planSaid=true
 say(ctx,'pitPlanSame',3,{'pitPlanSame'},{ttl=20,text=aaiText(ctx,c.title,c.text)})
end
-- Annonce de l'entrée dans la voie : clip du dernier rappel (« change de composé » ou « ta stratégie prévoit le même
-- composé »), texte d'AdvancedIA s'il est dans la langue de l'app. Une fois par entrée.
local function laneCompound(s,ctx)
 local c=s.compound
 s.laneCompound=true
 return say(ctx,'pitCompound',2,{c.kind},{ttl=10,text=aaiText(ctx,c.title,c.text)})
end
-- Avis d'arrêt (PIT_NOTICE) : le clip, et sur la radio le texte d'AdvancedIA (composés : « SS → S ») s'il est dans la
-- langue de l'app, sinon le texte du clip. Renvoie vrai si l'annonce est prise (une seule ligne sur la radio).
local function pitNotice(ctx,cur,e)
 local text=aaiText(ctx,cur.messageTitle,cur.messageText)
 local me=ctx.F.cars[ctx.F.player]
 local ttl=e[4] and me and (me.laps or 0)<1 and e[4] or e[3]
 local parts={e[1]}
 -- Reprise : place (1 à N, nombre dit) et voiture à suivre (indice d'AC ; -1 : la voiture de sécurité) ; voiture à
 -- doubler (indice d'AC). Les noms sont écrits, jamais dits.
 if cur.messageKind=='restartPlace' then
  local place=math.floor((tonumber(cur.messageValue) or 0)+0.5)
  if place<1 then return false end
  local follow=math.floor((tonumber(cur.messageExtra) or -1)+0.5)
  parts[2]={n=place}
  parts[3]=follow<0 and 'behindSc' or {text=Say.note(ctx.say,'behind',name(ctx,follow))}
 elseif cur.messageKind=='restartRetake' then
  parts[2]={text='('..name(ctx,math.floor((tonumber(cur.messageValue) or 0)+0.5))..')'}
 elseif cur.messageKind=='formation' then
  -- Départ lancé ensuite : la place se garde dans la file, pas sur la grille.
  if math.floor((tonumber(cur.messageExtra) or 0)+0.5)==1 then parts[1]='formationRoll' end
  return say(ctx,'formation',e[2],parts,{ttl=ttl,cooldown=30})
 elseif cur.messageKind=='rollStart' then
  -- Voiture à suivre écrite (jamais dite) ; en tête : rien de plus.
  local follow=math.floor((tonumber(cur.messageExtra) or -1)+0.5)
  if follow>=0 then parts[2]={text=Say.note(ctx.say,'behind',name(ctx,follow))} end
  return say(ctx,'start',e[2],parts,{ttl=ttl,once=true})
 elseif cur.messageKind=='rollGreen' then
  Voice.cancel(ctx.voice,AFTER_LIGHTS)
  return say(ctx,'start',e[2],parts,{ttl=ttl,once=true})
 end
 return say(ctx,cur.messageKind,e[2],parts,{ttl=ttl,text=text,cooldown=e[5]})
end
-- Drapeau bleu (1.3.5). Sans la nuance des classes d'AdvancedIA (clé AdvancedIA.traffic qui ne tourne pas, ou drapeau
-- bleu natif d'AC) : comme avant, dit à l'apparition du panneau. Avec elle (Beta 1.61) : l'étape « annonce » (voiture
-- rapide en approche, prépare-toi), puis l'ordre (le clip du drapeau bleu, l'annonce encore en file retirée) ; une
-- classe plus rapide dans le même tour a son clip (et l'appel « trafic plus rapide » se tait pour elle). La clé est
-- écrite jusqu'à deux fois par seconde de retard (AdvancedIA 1.61) : jusqu'à BLUE_WAIT s d'attente après le panneau,
-- puis le drapeau bleu simple. Pendant un bleu, la clé change chaque seconde (écart, vitesse de rapprochement) : une
-- valeur inchangée depuis BLUE_FRESH s est figée (réglage coupé), jamais lue ; l'annonce déjà dite est alors suivie
-- de l'ordre (jamais un « prépare-toi » sans le drapeau bleu).
local BLUE_WAIT=2.5
local BLUE_FRESH=2.5
local BLUE_ADVISE={blueAdvise=true}
local function blueCall(s,ctx,stage,clip)
 s.blueStage=stage
 if stage~='advise' then Voice.cancel(ctx.voice,BLUE_ADVISE) end
 if stage=='advise' then say(ctx,'blueAdvise',3,{clip},{ttl=4}) else say(ctx,'blue',2,{clip},{ttl=4,cooldown=12}) end
end
local function blueStep(s,ctx,cur,p)
 local blue=cur.panelDecided=='blue' or cur.panelDecided=='nativeBlue'
 if not ctx.cfg.blueFlags or not blue then
  if s.blueStage=='advise' then Voice.cancel(ctx.voice,BLUE_ADVISE) end
  s.blueStage=nil; s.blueSince=nil; return
 end
 if p.panelDecided~=cur.panelDecided or not s.blueSince then s.blueSince=ctx.real; s.blueStage=nil end
 if s.blueStage=='order' or s.blueStage=='class' then return end
 local tr=cur.panelDecided=='blue' and Side.get(ctx.side,'traffic') or nil
 -- Nuance des classes jamais vue dans la séance (ou bleu natif d'AC) : comme avant, tout de suite.
 if not tr then blueCall(s,ctx,'order','blue'); return end
 if (Side.age(ctx.side,'traffic') or 0)>BLUE_FRESH then
  if s.blueStage=='advise' or ctx.real-s.blueSince>=BLUE_WAIT then blueCall(s,ctx,'order','blue') end
  return
 end
 if tr.blue=='class' and tr.stage~='none' then
  local F=ctx.F; local c=tr.car>=0 and F.cars[tr.car]
  if c and c.valid and tr.car~=F.player then s.faster[tr.car]=ctx.now end
  blueCall(s,ctx,'class','blueClass')
 elseif tr.blue=='lap' and tr.stage=='order' then blueCall(s,ctx,'order','blue')
 elseif tr.blue=='lap' and tr.stage=='advise' then if not s.blueStage then blueCall(s,ctx,'advise','blueAdvise') end
 elseif not s.blueStage and ctx.real-s.blueSince>=BLUE_WAIT then blueCall(s,ctx,'order','blue') end
end
-- Direction de course.
local function race(s,ctx)
 local d=ctx.link.d
 -- AdvancedIA absent, arrêté ou suspendu (pause, replay, app coupée) : silence, et nouvelle référence au retour.
 if not d or not Link.connected(ctx.link) then s.prev=nil; return end
 local cur=s.spare or {}
 copy(d,cur)
 local p=s.prev
 s.spare=p; s.prev=cur
 if p and cur.serial<p.serial then p=nil end
 if not p then
  -- Référence : neutralisation déjà en cours annoncée une fois.
  if cur.neutral and ctx.cfg.raceControl and not prestart(cur) then
   local id=neutralClip(cur)
   if id then say(ctx,'neutral',1,{id},{ttl=8}) end
  end
  -- Armé : un delta déjà négatif à la mise en route est annoncé.
  s.deltaSign=0
  return
 end
 local cfg=ctx.cfg
 local relaunchNow=cur.relaunch and not p.relaunch
 -- Fin de neutralisation ou de drapeau rouge : le vert complet est attendu (AdvancedIA le pose dans la même image) ;
 -- jamais à la sortie d'une zone jaune locale (AdvancedIA montre alors le vert sur son panneau).
 if p.neutral and not cur.neutral or p.red and not cur.red then s.neutralEndAt=ctx.real; s.greenPending=true; s.zoneGreenAt=ctx.real end
 if cur.neutral or cur.red then s.greenPending=false end
 -- Fin du tour de formation ou départ lancé donné (1.3.4) : ni « drapeau vert » ni relance (« Go » ou la mise en grille
 -- le disent).
 local pre=prestart(cur) or prestart(p)
 if pre then s.greenPending=false end
 -- Fin de neutralisation ou de drapeau rouge : delta, fin de VSC, SC qui rentre… annulés aussitôt (même en cours), pour
 -- que le vert passe sans attendre.
 if p.neutral and not cur.neutral or p.red and not cur.red then Voice.cancel(ctx.voice,AFTER_NEUTRAL) end
 if p.zone and not cur.zone then Voice.cancel(ctx.voice,AFTER_ZONE) end
 if cur.zone or p.zone then s.zoneAt=ctx.real end
 -- Fin du delta à respecter (neutralisation, double jaune) : une annonce de delta encore en file ou en cours est fausse.
 if p.deltaOn and not cur.deltaOn then Voice.cancel(ctx.voice,AFTER_DELTA) end
 if cfg.raceControl then
  -- Neutralisation : SC appelée (elle rejoint la piste), VSC, FCY ; puis SC en piste (« reste en file »).
  if cur.neutral and (not p.neutral or p.neutralMode~=cur.neutralMode) and not relaunchNow and not pre then
   local id=neutralClip(cur)
   if id then say(ctx,'neutral',1,{id},{ttl=8}) end
  end
  if cur.neutral and cur.neutralMode=='sc' and p.safetyPhase=='call' and cur.safetyPhase=='out' then say(ctx,'scOut',2,{'sc'},{ttl=8}) end
  -- Fin de VSC ou SC qui rentre annulées par AdvancedIA (nouvel incident) : l'annonce devenue fausse est retirée, la
  -- neutralisation qui continue est redite.
  -- Même mode seulement : une fin de VSC annulée par une SC est déjà dite plus haut (« SC appelée » ; revue 1.3.2 :
  -- remplacée ici par « reste en file », la SC encore aux stands).
  if p.ending and not cur.ending and cur.neutral then
   Voice.cancel(ctx.voice,AFTER_ENDING)
   local id=p.neutralMode==cur.neutralMode and neutralClip(cur)
   if id then say(ctx,'neutral',1,{id},{ttl=8}) end
  end
  if p.safetyPhase=='in' and cur.safetyPhase=='out' and cur.neutral then Voice.cancel(ctx.voice,AFTER_SCIN); say(ctx,'scOut',1,{'sc'},{ttl=8}) end
  if cur.ending and not p.ending and cur.neutralMode=='vsc' then say(ctx,'vscEnding',2,{'vscEnding'},{ttl=5}) end
  if cur.safetyPhase=='in' and p.safetyPhase~='in' then say(ctx,'scIn',2,{'scIn'},{ttl=15}) end
  if cur.red and not p.red then say(ctx,'red',1,{'red'},{ttl=10}) end
  -- Fin du drapeau rouge hors course : reprise de la séance (même clé que le vert : jamais les deux).
  if p.red and not cur.red and not ctx.F.isRace then say(ctx,'restart',2,{'sessionResume'},{ttl=10,cooldown=10}) end
  -- Même clé que la relance : à la fin d'une SC, « relance » ou « drapeau vert », jamais les deux.
  -- Vert d'AdvancedIA : après une neutralisation ou un drapeau rouge, le vert complet ; à la sortie d'une zone jaune,
  -- un vert court, dit à l'instant même (« Vert, fin du jaune »), une fois par zone.
  -- Jamais pendant une neutralisation, un drapeau rouge ou un départ arrêté (« Go » le dit).
  local calm=not cur.neutral and not cur.red and cur.standing~='go'
  if s.greenPending and cur.greenLeft>0 and calm then s.greenPending=false; say(ctx,'restart',2,{'green'},{ttl=6,cooldown=10})
  elseif s.greenPending and ctx.real-s.neutralEndAt>2 then s.greenPending=false end
  -- Sortie de zone jaune : le vert court, sur la sortie elle-même (deux zones rapprochées : deux verts), une fois par
  -- jaune entendu (un jaune jamais dit : pas de vert).
  if p.zone and not cur.zone and calm then
   local yellow=ctx.voice.started.zone
   if yellow and yellow>s.zoneGreenAt then s.zoneGreenAt=ctx.real; say(ctx,'zoneGreen',2,{'zoneGreen'},{ttl=3,once=true}) end
  end
  if cur.zone and not p.zone then
   local parts={cur.zoneDouble and 'yellow2' or 'yellow'}
   local m=d.zoneDistance
   if m and m>0 then parts[2]={text=Say.note(ctx.say,'inMeters',math.floor(m/10+0.5)*10)} end
   say(ctx,'zone',cur.zoneDouble and 1 or 2,parts,{ttl=4,cooldown=3})
  elseif cur.zone and cur.zoneDouble and not p.zoneDouble then say(ctx,'zone',1,{'yellow2'},{ttl=4}) end
  -- Dangers en piste : priorité 2 (ils coupent les informations).
  if cur.slipperyLeft>0 and p.slipperyLeft<=0 then say(ctx,'slippery',2,{'slippery'},{ttl=10}) end
  if cur.slowCar>=0 and p.slowCar<0 then say(ctx,'white',2,{'white'},{ttl=8,cooldown=20}) end
  -- Dernier avertissement d'AdvancedIA (la prochaine infraction disqualifie) : son propre clip.
  if cur.warnLeft>0 and p.warnLeft<=0 then say(ctx,'blackWhite',2,{'lastWarning'},{ttl=10}) end
  if cur.meatballLeft>0 and p.meatballLeft<=0 then say(ctx,'blackOrange',2,{'blackOrange'},{ttl=12}) end
  -- Drapeau noir : disqualification d'AdvancedIA, appliquée par le drapeau noir natif d'AC une image plus tard ;
  -- l'un ou l'autre, une seule annonce.
  if (cur.disqualified and not p.disqualified or cur.nativePenalty==4 and p.nativePenalty~=4) and ctx.real-s.blackAt>10 then
   s.blackAt=ctx.real; say(ctx,'black',1,{'black'},{ttl=15})
  end
  if relaunchNow and not pre then
   -- Relance après un drapeau rouge : derrière la voiture de sécurité, sous VSC, sous FCY, ou départ lancé.
   local id=cur.neutralMode=='sc' and 'redRestartSc' or cur.neutralMode=='vsc' and 'redRestartVsc' or cur.neutralMode=='fcy' and 'redRestartFcy' or 'rs'
   say(ctx,'restart',2,{id},{ttl=10,cooldown=10})
  elseif cur.playerRestart and not p.playerRestart and not pre then say(ctx,'restart',2,{'rs'},{ttl=10,cooldown=10}) end
  if cur.standing=='grid' and p.standing~='grid' then say(ctx,'standing',2,{'ss'},{ttl=10}) end
  -- Feux et départ dans l'image même ; « Go » coupe les feux (jamais redits après).
  if cur.standing=='lights' and p.standing~='lights' then say(ctx,'start',2,{'lightsOn'},{ttl=6,once=true}) end
  if cur.standing=='go' and p.standing~='go' then Voice.cancel(ctx.voice,AFTER_LIGHTS); say(ctx,'start',1,{'go'},{ttl=4,once=true}) end
  if cur.jumpLeft>0 and p.jumpLeft<=0 then Voice.cancel(ctx.voice,AFTER_LIGHTS); say(ctx,'jump',1,{'jumpStart'},{ttl=4,once=true}) end
  if cur.pitsClosed and not p.pitsClosed then say(ctx,'pitLaneClosed',2,{'pitLaneClosed'},{ttl=10}) end
  if cur.maxStintMin>0 and cur.playerStintFor>=cur.maxStintMin*60 and not s.stint then s.stint=true; say(ctx,'stint',2,{'stintLimit'},{ttl=20}) end
  if cur.playerStintFor<0 or cur.maxStintMin>0 and cur.playerStintFor<cur.maxStintMin*60 then s.stint=false end
  -- Piste mouillée ou sèche (décidé par AdvancedIA), arrêt obligatoire levé en course mouillée.
  if cur.wetSerial~=p.wetSerial then say(ctx,'trackState',3,{cur.wet and 'trackWet' or 'trackDry'},{ttl=15}) end
  if cur.pitWaived and not p.pitWaived then say(ctx,'pitWaived',3,{'pitWaived'},{ttl=15}) end
  if cur.gridPlaced and not p.gridPlaced then say(ctx,'grid',3,{'gridPlaced'},{ttl=5}) end
  if cur.gridPassed and not p.gridPassed then say(ctx,'grid',2,{'gridPassed'},{ttl=5}) end
  if cur.messageId~=p.messageId and cur.messageKind=='aiDq' then say(ctx,'aiDq',4,{'aiDq'},{ttl=10}) end
  -- Autres états du panneau du pilote (départ, feux, SC appelée, dernier tour, arrêt obligatoire, pénalités d'AC).
  if cur.panelDecided~=p.panelDecided then
   local kind=cur.panelDecided
   local e=PANEL[kind]
   -- Dernier tour : une fois par séance (le panneau y revient après un bleu ou le DRS).
   if kind=='white' then if s.lastLapSaid then e=nil elseif e and cfg[e[3]] then s.lastLapSaid=true end end
   -- Jaune natif d'AC juste après une zone d'AdvancedIA : le même drapeau qui traîne, pas un nouveau.
   if kind=='native' and ctx.real-s.zoneAt<10 then e=nil end
   if e and cfg[e[3]] then
    local parts={e[1]}
    -- Dernier tour : position et conseil dans la même transmission (« Dernier tour ! Tu es P7. Ramène-la… »).
    local extra=kind=='white' and cfg.positionCalls and ctx.F.isRace and Position.lastLapParts(ctx) or nil
    if extra then for k=1,#extra do parts[#parts+1]=extra[k] end end
    -- Annonce prise : la position de l'ingénieur qui attend encore n'a plus lieu d'être (refusée : elle reste).
    if say(ctx,e[4] or 'panel:'..kind,e[2],parts,{ttl=6,cooldown=30}) and extra then Voice.cancel(ctx.voice,{position=true}) end
   end
  end
  -- Drapeau bleu : décidé par AdvancedIA (voiture qui prend un tour), en deux temps avec sa nuance des classes.
  blueStep(s,ctx,cur,p)
 end
 -- Arrêts aux stands : une seule référence, le plan de l'ingénieur. À l'ouverture de la fenêtre réglementaire, le tour
 -- optimal est donné avec ; le « box » vient de l'ingénieur au bon tour. Le rappel « rentre » d'AdvancedIA n'est dit
 -- que si aucun plan n'annoncera le box (stratégie ou appels coupés, pas encore de plan), pour ne jamais oublier un arrêt
 -- obligatoire.
 if cur.pitState=='open' and p.pitState~='open' then
  local L,t=plannedLap(ctx)
  if L then
   sayEngineer(ctx,'pitCall',3,{'pitOpen','optimalLap',{n=L}},{ttl=15})
   if t.plan.window then t.announcedWindow={t.plan.window[1],t.plan.window[2],L} end
  elseif cfg.raceControl then say(ctx,'pitCall',3,{'pitOpen'},{ttl=15}) end
 end
 if cfg.raceControl and cur.pitState=='open' and cur.pitDue>0 and cur.pitRemind and not p.pitRemind and not plannedLap(ctx) then
  local late=cur.pitClose>cur.pitOpen and cur.pitPosition>=cur.pitClose-(cur.pitClose-cur.pitOpen)*0.25
  if late then say(ctx,'pitCall',2,{'pitClosing'},{ttl=15}) end
 end
 if cfg.penaltiesVoice then
  if cur.giveBack>=0 and p.giveBack<0 then say(ctx,'giveBack',1,{'giveBack',{text=name(ctx,cur.giveBack)}},{ttl=8}) end
  -- Place rendue dans le délai : aucune pénalité décidée entre-temps, et la voiture due vraiment devant le joueur sur la
  -- piste, à moins de 300 m (1.3.1 : AdvancedIA efface aussi la dette à l'entrée des stands, quand la voiture devient
  -- dépassable ou sert une pénalité, ou à l'échéance ; « place rendue » y était dit à tort).
  if p.giveBack>=0 and cur.giveBack<0 and cur.penaltyId==p.penaltyId then
   local F=ctx.F; local me=F.cars[F.player]; local c=F.cars[p.giveBack]
   local ahead=me and c and c.valid and not me.pitlane and U.ahead(me,c,trackLength(F),F.open)
   if ahead and ahead>0 and ahead<300 then say(ctx,'giveBack',3,{'giveBackDone'},{ttl=5}) end
  end
  -- penaltyKind : 'slow' ou 'dq' ; le pont v1 ne garde que 3 caractères ('slo') : tout sauf 'dq' est une coupure des gaz.
  -- Coupure des gaz : décidée par AdvancedIA (raison précise), appliquée par la pénalité native d'AC une image plus
  -- tard ; la native seule (pénalité d'AC lui-même) n'est dite que sans décision d'AdvancedIA dans les 10 s.
  if cur.penaltyId~=p.penaltyId and cur.penaltyKind~='dq' and cur.penaltyKind~='' then
   s.penaltyAt=ctx.real; say(ctx,'penalty',1,{PENALTY[cur.penaltyReason] or 'penaltyThrottle'},{ttl=10})
  elseif cur.nativePenalty==3 and p.nativePenalty~=3 and ctx.real-s.penaltyAt>10 then
   s.penaltyAt=ctx.real; say(ctx,'penalty',1,{'penaltyThrottle'},{ttl=10})
  end
 end
 -- Delta à respecter (neutralisation, double jaune) : changement de signe avec hystérésis.
 if cfg.deltaVoice and cur.deltaOn then
  local v=cur.deltaValue
  -- Hystérésis : négatif dès -0,05 s (avant toute infraction d'AdvancedIA, jugée sous -deltaTolerance à chaque
  -- mini-secteur), de nouveau positif seulement au-dessus de +0,2 s (pas d'alternance au ras du delta). L'état
  -- ne change que si l'annonce part : un « delta négatif » retenu par son délai est redit dès que possible.
  if v<-0.05 and s.deltaSign>=0 then if say(ctx,'delta',1,{'deltaNeg'},{ttl=3,cooldown=6,once=true}) then s.deltaSign=-1; s.deltaQueuedAt=ctx.real end
  elseif v>0.2 and s.deltaSign<0 then if say(ctx,'delta',3,{'deltaPos'},{ttl=3,cooldown=6,once=true}) then s.deltaSign=1 end
  elseif s.deltaSign==0 then s.deltaSign=1 end
  -- « Delta négatif » périmé dans la file sans avoir été dit (derrière une autre annonce urgente) : redit.
  if s.deltaQueuedAt and ctx.real-s.deltaQueuedAt>3.2 then
   local heard=ctx.voice.started.delta
   if s.deltaSign<0 and (not heard or heard<s.deltaQueuedAt) then s.deltaSign=0; Voice.rearm(ctx.voice,'delta') end
   s.deltaQueuedAt=nil
  end
  -- Réarmement silencieux après 3 s au-dessus de zéro : un nouveau passage sous -0,05 s est de nouveau annoncé (sans
  -- attendre « delta positif », qui demande +0,2 s).
  if s.deltaSign<0 and v>0 then s.deltaAbove=s.deltaAbove or ctx.real; if ctx.real-s.deltaAbove>=3 then s.deltaSign=1; s.deltaAbove=nil end
  else s.deltaAbove=nil end
 elseif not cur.deltaOn then s.deltaSign=0; s.deltaAbove=nil end
 -- DRS (désactivé par défaut : AdvancedIA a déjà son bip et son panneau) : disponible, autorisé dans N tours,
 -- autorisé, désactivé (piste humide, drapeau).
 if cfg.drsVoice then
  if cur.drsBeep~=p.drsBeep then say(ctx,'drs',4,{'drsOn'},{ttl=2,cooldown=15}) end
  if cur.drsReason=='laps' and p.drsReason~='laps' and cur.drsLapsLeft>0 then say(ctx,'drsRule',4,{'drsIn',{n=cur.drsLapsLeft},'laps'},{ttl=10})
  elseif cur.drsReason=='' and p.drsReason=='laps' then say(ctx,'drsRule',4,{'drsEnabled'},{ttl=10})
  elseif (cur.drsReason=='wet' or cur.drsReason=='flag') and p.drsReason~=cur.drsReason or cur.drsBlocked and not p.drsBlocked then
   say(ctx,'drsOff',4,{'drsOff'},{ttl=6,cooldown=30})
  end
 end
 if cfg.flashVoice and cur.flashId~=p.flashId and cur.flashHeard>0 then say(ctx,'flash',4,{'flash'},{ttl=3,cooldown=8,once=true}) end
 -- Avis d'arrêt d'AdvancedIA (composé) : dits (direction de course) ; refusés (rôle spotter ou radio coupés), ils
 -- restent écrits comme les autres annonces.
 local noticeSaid=false
 local notice=cur.messageId~=p.messageId and PIT_NOTICE[cur.messageKind] or nil
 if cur.messageId~=p.messageId and ctx.journal then
  ctx.journal(string.format('AdvancedIA %s (%s / %s) : %s',tostring(cur.messageKind),tostring(cur.messageValue),tostring(cur.messageExtra),aaiLine(cur.messageTitle,cur.messageText)))
 end
 -- Règle F1 du composé : chaque rappel d'AdvancedIA (genre, titre, texte) est gardé pour l'annonce de la voie.
 if notice and HINT[cur.messageKind] then
  local c=s.compound or {}; c.kind=cur.messageKind; c.title=cur.messageTitle; c.text=cur.messageText; s.compound=c
 end
 -- Stratégie des stands corrigée (AdvancedIA : 'pitPlanOk', du même composé à un autre) : l'avis « même composé »
 -- en attente ou en file est abandonné ; l'annonce de la voie redevient « change de composé », avec le texte du clip.
 -- L'annonce reste écrite sur la radio, comme les autres.
 if cur.messageId~=p.messageId and cur.messageKind=='pitPlanOk' then
  s.planPending=false
  if s.compound then s.compound.kind='pitCompound'; s.compound.title=''; s.compound.text='' end
  Voice.cancel(ctx.voice,PLAN_SAME)
 end
 -- Entrée dans la voie des stands : arrêt obligatoire dû (fenêtre ouverte), règle du composé connue (un rappel
 -- d'AdvancedIA dans la séance), en course, pas un drive-through.
 local meNow=ctx.F.cars[ctx.F.player]
 local inLane=meNow and meNow.pitlane or false
 if inLane and not s.wasLane then
  s.laneCompound=false
  if cfg.raceControl and s.compound and ctx.F.isRace and cur.pitState=='open' and cur.pitDue>0 and not cur.pitWaived
   and cur.panelDecided~='penaltyDrive' then laneCompound(s,ctx) end
 end
 if not inLane then s.laneCompound=false end
 s.wasLane=inLane
 if s.planPending and not s.planSaid then planNotice(s,ctx,cur) end
 local hintQuiet=notice~=nil and HINT[cur.messageKind] and not hintWanted(s,ctx,cur)
 if notice and cfg.raceControl and not hintQuiet then noticeSaid=pitNotice(ctx,cur,notice) end
 -- Essais et qualifications (AdvancedIA 1.51, 'fastCar') : une IA en tour lancé arrive derrière le joueur en tour de
 -- sortie ou de refroidissement (value : indice d'AC, extra : écart en s) ; AdvancedIA la signale au plus une fois par
 -- IA toutes les 30 s. Mise en attente de confirmation (fastCar, plus bas), jamais écrite telle quelle.
 if cfg.fasterBehind and not ctx.F.isRace and cur.messageId~=p.messageId and cur.messageKind=='fastCar' then
  local i=math.floor((tonumber(cur.messageValue) or -1)+0.5)
  if i>=0 and i~=ctx.F.player then s.fastPending[i]=ctx.now end
  noticeSaid=true
 end
 -- Annonces d'AdvancedIA : écrites sur la radio (déjà montrées par son overlay), sans voix ni bip.
 if cfg.aaiMessages and cur.messageId~=p.messageId and cur.messageTitle~='' and not noticeSaid and not hintQuiet then
  Voice.note(ctx.voice,{role='race',text=aaiLine(cur.messageTitle,cur.messageText),prio=5,kind='aai'},ctx.real,false)
 end
 if cfg.aaiMessages and cur.aiSerial~=p.aiSerial and cur.aiTitle~='' then
  Voice.note(ctx.voice,{role='race',text=cur.aiTitle..' · '..cur.aiShort,prio=5,kind='aai'},ctx.real,false)
 end
end
-- Côte à côte.
local HEARD_L={'side:left','side:three','side:stillLeft'}
local HEARD_R={'side:right','side:three','side:stillRight'}
local SIDE={left='carLeft',right='carRight',three='threeWide',clearLeft='clearLeft',clearRight='clearRight',clear='clear',stillLeft='stillThere',stillRight='stillThere'}
-- Vérification indépendante du côté : position latérale sur la piste donnée par CSP (ac.worldCoordinateToTrack, -1 à
-- gauche, +1 à droite) comparée au côté tiré du repère de la voiture. Trois désaccords nets, trois fois plus nombreux
-- que les accords : les côtés sont inversés automatiquement (une ligne sur la radio), en plus du réglage manuel.
-- Jamais jugé quand le joueur recule sur le tour ou reprend la piste après un tête-à-queue (revue 1.3.2 : à contresens,
-- sa gauche est la droite de la piste ; chaque voiture croisée était un désaccord, et les côtés s'inversaient).
local function checkSide(s,ctx,me,index,left)
 local c=ctx.F.cars[index]
 if not ctx.trackLateral or not c or not c.valid then return end
 local tc=ctx.timing and ctx.timing.cars[ctx.F.player]
 if tc and (tc.ds or 0)<0 or ctx.emergency and ctx.emergency.stranded then return end
 local a=ctx.trackLateral(me.x,me.y or 0,me.z); local b=ctx.trackLateral(c.x,c.y or 0,c.z)
 if not a or not b or math.abs(b-a)<0.08 or math.abs(a)>1.2 or math.abs(b)>1.2 then return end
 local trackLeft=b<a
 if trackLeft==left then s.sideAgree=s.sideAgree+1 else s.sideDisagree=s.sideDisagree+1 end
 if s.sideDisagree>=3 and s.sideDisagree>=3*s.sideAgree then
  s.autoFlip=not s.autoFlip; s.sideAgree=0; s.sideDisagree=0
  Voice.note(ctx.voice,{role='spotter',text=Say.note(ctx.say,'sidesFlipped'),prio=5,kind='info'},ctx.real,false)
 end
end
-- Annonce de ce côté entendue depuis le début de l'épisode.
local function heard(s,ctx,side)
 local at=side=='L' and s.sideAtL or s.sideAtR
 local started=ctx.voice.started
 for _,key in ipairs(side=='L' and HEARD_L or HEARD_R) do local t=started[key]; if t and t>=at then return true end end
 return false
end
-- Côte à côte en pause (voie des stands, réglage coupé) : un côté resté tenu est oublié en silence (pas de « toujours
-- là » ni de « dégagé » à la reprise).
local function sideIdle(s)
 if s.prox.left or s.prox.right or s.prox.candL or s.prox.candR then s.prox=Proximity.new(); s.wasL=false; s.wasR=false end
end
M.sideIdle=sideIdle
-- Voiture qui arrive à côté depuis l'arrière (1.3.0, réglage Anticipation) : derrière le joueur à moins de INCOMING.behind
-- m, décalée d'une voie, plus rapide de INCOMING.closing km/h au moins, ce côté encore libre, et à côté dans INCOMING.lead s
-- au moins (sinon « voiture à gauche » suit aussitôt : une seule annonce utile) : « il arrive à gauche ».
-- Une fois par voiture toutes les INCOMING.again s, et une annonce au plus toutes les INCOMING.gap s ; jamais au premier
-- tour d'une course (peloton serré au départ), ni sous INCOMING.kmh. Position mesurée dans le repère de la bissectrice
-- des deux caps (1.3.1 : en courbe, une voiture dans les traces du joueur paraissait décalée d'une voie dans son seul
-- repère), décalage tenu INCOMING.hold s, jamais au freinage (pédale au-delà de INCOMING.brake).
local INCOMING={behind=19,closing=8,again=20,gap=6,kmh=60,lead=0.8,hold=0.3,brake=0.3}
function M.incoming(s,ctx,me,p,pc)
 local F=ctx.F
 -- Hors conditions : décalages tenus oubliés (revue 1.3.2 : un ancien début de décalage, gardé, dispensait la même
 -- voiture du délai INCOMING.hold à son retour).
 if me.kmh<INCOMING.kmh or not F.started or F.isRace and me.laps<1 or Link.neutralised(ctx.link.d)
  or (tonumber(F.me.brake) or 0)>INCOMING.brake then U.wipe(s.incomingSince); return end
 local seen=U.wipe(s.incomingSeen)
 for k=1,p.count do
  local it=p.list[k]; local c=F.cars[it.index]
  local long,lat=nil,nil
  if c then long,lat=M.bisector(me,c) end
  if lat and pc.flip then lat=-lat end
  local alat=lat and math.abs(lat) or 0
  if c and c.valid and long and long<-(pc.length+0.3) and long>-INCOMING.behind and alat>=pc.laneMin and alat<=pc.laneMax and c.kmh-me.kmh>=INCOMING.closing then
   seen[it.index]=true
   local since=s.incomingSince[it.index] or ctx.now; s.incomingSince[it.index]=since
   local left=lat>0
   local soon=(-long-(pc.length+0.3))/math.max(0.1,(c.kmh-me.kmh)/3.6)
   if ctx.now-since>=INCOMING.hold and soon>=INCOMING.lead and not (left and (p.left or p.candL) or not left and (p.right or p.candR)) and ctx.now-(s.incoming[it.index] or -1e9)>INCOMING.again and ctx.real-s.incomingAt>INCOMING.gap then
    if say(ctx,'side:incoming',2,{left and 'incomingLeft' or 'incomingRight'},{ttl=1.2,once=true,tone='urgent'}) then
     s.incoming[it.index]=ctx.now; s.incomingAt=ctx.real
    end
   end
  end
 end
 for i in pairs(s.incomingSince) do if not seen[i] then s.incomingSince[i]=nil end end
end
-- Position d'une voiture dans le repère de la bissectrice des caps du joueur et de la voiture (avant +, gauche +) : la
-- corde entre deux points d'un virage est parallèle à la tangente moyenne, la courbure ne crée aucun faux décalage.
function M.bisector(me,c)
 local lx,lz=(me.lookX or 0)+(c.lookX or me.lookX or 0),(me.lookZ or 0)+(c.lookZ or me.lookZ or 0)
 local n=math.sqrt(lx*lx+lz*lz)
 if n<1e-6 or not c.x then return nil,nil end
 lx,lz=lx/n,lz/n
 local sx,sz=lz,-lx
 local dx,dz=c.x-me.x,c.z-me.z
 return dx*lx+dz*lz,dx*sx+dz*sz
end
-- Position longitudinale (m, devant +) d'une voiture dans le repère du joueur.
local function along(me,c)
 local lx,lz=me.lookX or 0,me.lookZ or 0
 local n=math.sqrt(lx*lx+lz*lz)
 if n<1e-6 or not c.x then return nil end
 return ((c.x-me.x)*lx+(c.z-me.z)*lz)/n
end
-- Dépassement fini à un « dégagé » : la voiture qui était à côté (de ce côté) est maintenant derrière le joueur.
local function behind(F,me,i)
 local c=i>=0 and F.cars[i]
 local l=c and c.valid and along(me,c)
 return l and l<-((me.len or 4.7)+0.5) or false
end
function M.passed(s,ctx,me,e)
 local F=ctx.F
 if e=='clearLeft' then return behind(F,me,s.sideCarL) end
 if e=='clearRight' then return behind(F,me,s.sideCarR) end
 return behind(F,me,s.sideCarL) or behind(F,me,s.sideCarR)
end
-- Côté tenu sous Proximity.minKmh (état gelé : épingle, départ) : oublié en silence après SLOW_HOLD s (revue 1.3.2 :
-- côte à côte, puis tête-à-queue et 20 s à l'arrêt, « dégagé » dit à la reprise pour une voiture partie depuis longtemps).
local SLOW_HOLD=3
local function side(s,ctx)
 local F=ctx.F; local me=F.cars[F.player]
 if not me or not me.valid or me.pitlane then sideIdle(s); return end
 local cfg=ctx.cfg
 local pc=s.proxCfg
 if not pc then
  -- Réglages de la présence latérale : ceux du module, puis la taille de la voiture et les choix du pilote.
  pc={}; for k,v in pairs(Proximity.defaults) do pc[k]=v end; s.proxCfg=pc
  s.proxMe={}
 end
 pc.length=me.len or Proximity.defaults.length
 pc.stillMax=cfg.stillThere and Proximity.defaults.stillMax or 0; pc.flip=(cfg.flipSides==true)~=(s.autoFlip==true)
 if me.kmh<pc.minKmh then
  if not s.slowAt or ctx.now<s.slowAt then s.slowAt=ctx.now end
  if ctx.now-s.slowAt>SLOW_HOLD then sideIdle(s) end
 else s.slowAt=nil end
 local pm=s.proxMe; pm.x=me.x; pm.z=me.z; pm.lookX=me.lookX; pm.lookZ=me.lookZ; pm.kmh=me.kmh
 local events=Proximity.step(s.prox,pm,F.cars,F.count,F.player,ctx.now,pc)
 local p=s.prox
 if cfg.anticipation then M.incoming(s,ctx,me,p,pc) end
 -- Début de chaque épisode (voiture qui arrive de ce côté) : « dégagé » ne vaut que si son annonce a été entendue.
 if p.left and not s.wasL then s.sideAtL=ctx.real end
 if p.right and not s.wasR then s.sideAtR=ctx.real end
 s.wasL=p.left; s.wasR=p.right
 for k=1,#events do
  local e=events[k]
  if e=='clear' or e=='clearLeft' or e=='clearRight' then
   -- Annonce du côté jamais dite (encore en file ou périmée) : retirée, et rien n'est dit. Seules les annonces du côté
   -- dégagé sont retirées ; celle de l'autre côté, si elle n'a pas encore été dite, reste (ou est refaite).
   local ok=e=='clearLeft' and heard(s,ctx,'L') or e=='clearRight' and heard(s,ctx,'R') or e=='clear' and (heard(s,ctx,'L') or heard(s,ctx,'R'))
   if e=='clear' then Voice.drop(ctx.voice,'side:')
   else
    Voice.drop(ctx.voice,'side:three'); Voice.drop(ctx.voice,e=='clearLeft' and 'side:left' or 'side:right')
    Voice.drop(ctx.voice,e=='clearLeft' and 'side:stillLeft' or 'side:stillRight')
    local other=e=='clearLeft' and 'R' or 'L'
    local key=other=='R' and 'side:right' or 'side:left'
    if (other=='R' and p.right or other=='L' and p.left) and not heard(s,ctx,other) and not Voice.pending(ctx.voice,key) then
     say(ctx,key,1,{other=='R' and 'carRight' or 'carLeft'},{ttl=1.5,once=true})
    end
   end
   -- Priorité 2 : « dégagé » coupe une information (redite ensuite), jamais une annonce de sécurité. Dépassement fini
   -- (1.3.0, réglage Anticipation) : la voiture qui était à côté est maintenant derrière, « tu es passé, rabats-toi ».
   local clip=SIDE[e]
   if cfg.anticipation and e=='clear' and M.passed(s,ctx,me,e) then clip='clearPassed' end
   if ok then say(ctx,'side:'..e,2,{clip},{ttl=1.5,once=true}) end
   if e=='clear' or e=='clearLeft' then s.sideCarL=-1 end
   if e=='clear' or e=='clearRight' then s.sideCarR=-1 end
  else
   if (e=='left' or e=='three') and p.leftCar>=0 then s.sideCarL=p.leftCar end
   if (e=='right' or e=='three') and p.rightCar>=0 then s.sideCarR=p.rightCar end
   if (e=='left' or e=='three') and p.leftCar>=0 then checkSide(s,ctx,me,p.leftCar,true) end
   if (e=='right' or e=='three') and p.rightCar>=0 then checkSide(s,ctx,me,p.rightCar,false) end
   say(ctx,'side:'..e,1,{SIDE[e]},{ttl=1.5,once=true})
  end
 end
end
-- Écarts devant / derrière (voitures voisines au classement, src/position.lua), à la fin d'un tour sur gapEvery.
local function gaps(s,ctx)
 local F=ctx.F; local me=F.cars[F.player]; local cfg=ctx.cfg
 if not F.isRace or not me or not me.valid then return end
 local d=ctx.link.d
 -- Voie des stands, neutralisation, drapeau rouge : le dernier écart dit n'est plus une référence (revue 1.3.2 : 20 s
 -- avant la voiture de sécurité, 0,8 s après : « tu reviens »).
 if me.pitlane or Link.neutralised(d) then s.lastGaps.ahead=nil; s.lastGaps.behind=nil end
 if me.laps<1 or me.laps==s.gapLap or me.finished then return end
 s.gapLap=me.laps
 if me.laps%cfg.gapEvery~=0 or me.pitlane then return end
 if d and d.neutral then return end
 local ahead,behind=Position.neighbours(F,me)
 local parts={}
 -- Écarts propres (Timing.gap, clean) : jamais sur un passage fait dans la voie des stands ou sous neutralisation.
 if ahead then
  local g,laps=Timing.gap(ctx.timing,ahead,F.player,ctx.now,true)
  -- Un seul message pour devant et derrière (« Écart devant : 1,2 seconde, tu reviens. Derrière : 2,4 secondes. ») ;
  -- nombre et unité en un seul clip sous 10 s (src/say.lua).
  if g then
   parts[#parts+1]='gapAhead'; parts[#parts+1]={n=g,dec=cfg.gapDecimals,unit='s'}
   local last=s.lastGaps.ahead
   -- Tendance depuis le dernier écart dit (1.3.0) : tu reviens, il s'échappe, ou écart stable dans une bagarre.
   if last and last.car==ahead then
    local diff=last.gap-g
    if diff>=cfg.closingAlert then parts[#parts+1]='closing'
    elseif cfg.gapEvents and -diff>=cfg.closingAlert then parts[#parts+1]='escaping'
    elseif cfg.gapEvents and math.abs(diff)<0.1 and g<3 then parts[#parts+1]='gapStable' end
   end
   s.lastGaps.ahead={car=ahead,gap=g}
  elseif laps>0 then s.lastGaps.ahead=nil end
 end
 if behind then
  local g=Timing.gap(ctx.timing,F.player,behind,ctx.now,true)
  if g then
   parts[#parts+1]=#parts>0 and 'andBehind' or 'gapBehind'; parts[#parts+1]={n=g,dec=cfg.gapDecimals,unit='s'}
   local last=s.lastGaps.behind
   if last and last.car==behind then
    local diff=last.gap-g
    if diff>=cfg.closingAlert then parts[#parts+1]='hesClosing'
    elseif cfg.gapEvents and -diff>=cfg.closingAlert then parts[#parts+1]='pullingAway' end
   end
   s.lastGaps.behind={car=behind,gap=g}
  end
 end
 -- Priorité 3 (jamais derrière les informations de l'ingénieur) et dit tout de suite ou pas du tout : un écart lu
 -- 20 s plus tard est faux.
 if #parts>0 then say(ctx,'gaps',3,parts,{ttl=6}) end
end
-- Écarts vivants (1.3.0, réglage « Écarts en direct ») : en cours de tour, voiture devant qui entre dans la seconde
-- (« tu es dans la seconde »), voiture derrière qui y entre (« il est dans ta seconde ») ; une fois par voiture, réarmé
-- quand l'écart repasse au-dessus de LIVE.out s. Relevé toutes les LIVE.every s ; course, à partir du tour 2, hors
-- neutralisation et voie des stands. Quand le joueur attaque (moins de LIVE.attack s), personne à moins de LIVE.free s
-- derrière : « rien derrière, tu peux tenter » (une fois par attaque, au plus toutes les LIVE.again s) ; déjà vrai quand la
-- voiture devant entre dans la seconde : une seule transmission (« tu es dans la seconde… rien derrière… »).
local LIVE={every=0.5,inside=1.0,out=1.4,attack=0.6,attackOut=1.0,free=1.5,again=90,line=0.06}
local function live(s,ctx)
 local F=ctx.F; local me=F.cars[F.player]; local cfg=ctx.cfg
 if not F.isRace or not me or not me.valid or me.laps<2 or me.pitlane or me.finished then return end
 if ctx.now-s.liveAt<LIVE.every and ctx.now>=s.liveAt then return end
 s.liveAt=ctx.now
 -- Près de la ligne : les écarts du tour y sont dits (gaps), jamais retardés par un écart en direct.
 if me.spline<LIVE.line or me.spline>1-LIVE.line then return end
 local d=ctx.link.d
 -- Neutralisation : la file se reforme, rien n'est dit, et rien n'est rattrapé à la relance (écarts tenus pour déjà
 -- dits jusqu'à ce qu'ils repassent au-dessus de LIVE.out). Jaune local, dépassement interdit, relance : rien non plus
 -- (« tu peux tenter » contredirait AdvancedIA).
 -- Voisins du moment tenus pour déjà dits (revue 1.3.2 : un voisin changé pendant la neutralisation, par un arrêt,
 -- réarmait l'annonce, dite dès le vert dans la file groupée) ; de même pendant la relance.
 local ahead,behind=Position.neighbours(F,me)
 if Link.neutralised(d) or d and (d.playerRestart or d.relaunch) then
  s.inAhead=true; s.inBehind=true; s.chaseOn=true; s.inAheadCar=ahead; s.inBehindCar=behind; return
 end
 if d and (d.zone or d.noPass or d.panelNoPass) then return end
 local ga=ahead and Timing.gap(ctx.timing,ahead,F.player,ctx.now,true) or nil
 local gb=behind and Timing.gap(ctx.timing,F.player,behind,ctx.now,true) or nil
 -- Personne derrière : sur les écarts relevés sur la piste (toute voiture, même d'un autre tour) ; une voiture classée
 -- derrière dont l'écart n'est pas connu ne laisse pas « libre ».
 local free=not (behind and not gb) and (not gb or gb>LIVE.free)
 if free then for _,h in pairs(s.closing) do if #h>0 and h[#h].g<LIVE.free then free=false; break end end end
 local attack=cfg.anticipation and free and ctx.now-s.clearBehindAt>LIVE.again
 if cfg.gaps and cfg.gapEvents then
  if ahead~=s.inAheadCar or not ga or ga>LIVE.out then s.inAhead=false; s.inAheadCar=ahead end
  if ga and ga<LIVE.inside and not s.inAhead then
   s.inAhead=true
   local parts={'inSecond'}
   if attack then parts[2]='clearBehind' end
   if say(ctx,'inSecond',3,parts,{ttl=5,tone='motivating',cooldown=40}) and attack then s.chaseOn=true; s.clearBehindAt=ctx.now end
  end
  if behind~=s.inBehindCar or not gb or gb>LIVE.out then s.inBehind=false; s.inBehindCar=behind end
  if gb and gb<LIVE.inside and not s.inBehind then
   s.inBehind=true
   local last=s.lastGaps.behind
   local closing=last and last.car==behind and last.gap-gb>=cfg.closingAlert
   say(ctx,'heInSecond',3,{'heInSecond'},{ttl=5,tone=closing and 'urgent' or 'neutral',cooldown=40})
  end
 end
 if cfg.anticipation then
  if not ga or ga>LIVE.attackOut then s.chaseOn=false end
  if ga and ga<LIVE.attack and not s.chaseOn then
   s.chaseOn=true
   if attack then
    if say(ctx,'clearBehind',3,{'clearBehind'},{ttl=4}) then s.clearBehindAt=ctx.now end
   end
  end
 end
end
-- Tour de retard entre deux voitures : la progression suivie (tours d'AC + position sur le tour) le dit, et le classement
-- d'AC doit le confirmer (behind : la voiture est classée derrière le joueur). Le compteur de tours d'AC peut avoir un
-- tour d'écart d'une voiture à l'autre (grille de part et d'autre de la ligne au départ) : sans le classement, toutes
-- les voitures devant passaient pour des retardataires (constaté en course le 05/11/2026). Position 0 : inconnue.
function M.lapDown(me,c,mine,tc,behind)
 if not (mine and tc and mine.progress and tc.progress) then return false end
 local mp,cp=tonumber(me.position) or 0,tonumber(c.position) or 0
 if mp<=0 or cp<=0 then return false end
 if behind then return cp>mp and mine.progress-tc.progress>=0.5 end
 return cp<mp and tc.progress-mine.progress>=0.5
end
-- Écart en temps de la voiture i derrière le joueur, relevé (CLOSE.every) et gardé (CLOSE.keep) ; oublié sans écart.
local function sampleGap(s,ctx,i)
 local g=Timing.trackGap(ctx.timing,ctx.F.player,i,ctx.now)
 local h=s.closing[i]
 if not g then s.closing[i]=nil; return end
 if not h or (#h>0 and ctx.now<h[#h].t) then h={}; s.closing[i]=h end
 local n=#h
 if n==0 or ctx.now-h[n].t>=CLOSE.every then
  -- Relevé périmé repris pour le nouveau (aucune table neuve en régime établi).
  local e=n>1 and ctx.now-h[1].t>CLOSE.keep and table.remove(h,1) or {}
  e.t=ctx.now; e.g=g; h[#h+1]=e
 end
 while #h>1 and ctx.now-h[1].t>CLOSE.keep do table.remove(h,1) end
end
-- Dernier écart relevé (s), rythme de rapprochement (s gagnées par s ; nil sur moins de CLOSE.short s) et durée de la
-- mesure (s).
function M.closing(s,i)
 local h=s.closing[i]
 if not h or #h==0 then return nil,nil,0 end
 local a,b=h[1],h[#h]
 local span=b.t-a.t
 if span<CLOSE.short then return b.g,nil,span end
 return b.g,(a.g-b.g)/span,span
end
-- Voiture i qui arrive derrière à moins de maxGap s : vrai, écart, rythme.
local function arriving(s,i,maxGap)
 local g,rate,span=M.closing(s,i)
 local closing=rate and (rate>=CLOSE.fast or span>=CLOSE.window and rate>=CLOSE.rate)
 return (g and closing and g<=maxGap and g/rate<=CLOSE.catch) or false,g,rate
end
-- Écarts relevés de toutes les voitures derrière le joueur, à toute vitesse ; oubliés quand il est aux stands.
local function sampleAll(s,ctx)
 local F=ctx.F; local me=F.cars[F.player]
 if not me or not me.valid or me.pitlane then U.wipe(s.closing); return end
 local length=trackLength(F)
 for i=0,F.count-1 do
  local c=F.cars[i]
  local ahead=i~=F.player and c and c.valid and not c.pitlane and U.ahead(me,c,length,F.open)
  if ahead and ahead<0 and ahead>-CLOSE.range then sampleGap(s,ctx,i) else s.closing[i]=nil end
 end
end
-- Trafic : retardataires devant, trafic plus rapide derrière, voiture arrêtée ou en difficulté devant.
local function traffic(s,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local me=F.cars[F.player]; local t=ctx.timing
 if not me or not me.valid or me.pitlane or me.kmh<30 then
  -- Joueur aux stands ou au pas : compteurs d'erreur des IA tenus à jour (jamais une erreur faite pendant l'arrêt dite à
  -- la sortie comme nouvelle).
  for i=0,F.count-1 do local lc=Link.car(ctx.link,i); s.mistakes[i]=lc and lc.mistakeId end
  return
 end
 local mine=Timing.car(t,F.player)
 local d=ctx.link.d
 local length=trackLength(F)
 -- Neutralisation, drapeau rouge, relance : ni retardataire ni trafic plus rapide (la file roule ensemble).
 local held=d and (d.neutral or d.red or d.relaunch)
 for i=0,F.count-1 do
  local c=F.cars[i]
  local lc=Link.car(ctx.link,i)
  -- Erreur de pilotage d'une IA : compteur relu pour toutes les voitures à chaque image ; dite seulement si elle change
  -- entre 40 et 400 m devant (jamais une erreur faite plus loin, ou pendant un arrêt du joueur, dite plus tard).
  local mistake=lc and lc.mistakeId
  local lastMistake=s.mistakes[i]; s.mistakes[i]=mistake
  -- Voiture de sécurité d'AdvancedIA (une voiture d'AC classée dernière) : jamais un retardataire ni un trafic.
  if i~=F.player and c.valid and not c.pitlane and not (lc and lc.safety) then
   local tc=Timing.car(t,i)
   local ahead=U.ahead(me,c,length,F.open)
   if cfg.hazards and mistake and lastMistake~=nil and mistake~=lastMistake and ahead>40 and ahead<400 and not held then
    say(ctx,'mistake',2,{'aiMistake'},{ttl=3,cooldown=10})
   end
   -- Retardataire : devant sur la piste, à moins de 2,5 s, au moins un demi-tour derrière et classée derrière.
   if cfg.backmarkers and F.isRace and not held and ahead>0 and ahead<400 and M.lapDown(me,c,mine,tc,true) then
    local g=Timing.trackGap(t,i,F.player,ctx.now)
    if g and g<2.5 and ctx.now-(s.backmarkers[i] or -1e9)>90 then s.backmarkers[i]=ctx.now; say(ctx,'backmarker',3,{'backmarker'},{ttl=5,cooldown=20}) end
   end
   -- Trafic plus rapide derrière, à moins de FASTER_GAP s : hors course, voiture qui arrive vraiment (CLOSE ; un tour
   -- lancé d'AdvancedIA en attente est dit à sa place) ; en course, voiture qui prend un tour (plus rapide par nature,
   -- souvent de quelques % seulement), seulement si AdvancedIA ne montre pas déjà le drapeau bleu.
   -- En course, une voiture qui prend un tour est laissée au drapeau bleu d'AdvancedIA quand il est annoncé (réglage
   -- Drapeaux bleus) : jamais « garde ta ligne » puis « laisse passer » pour la même voiture.
   if cfg.fasterBehind and not held and ahead<0 and not s.fastPending[i] and ctx.now-(s.faster[i] or -1e9)>60 then
    local call
    if F.isRace then
     local blue=d and (d.panelDecided=='blue' or d.panelDecided=='nativeBlue')
     local g=not blue and not cfg.blueFlags and M.lapDown(me,c,mine,tc,false) and Timing.trackGap(t,F.player,i,ctx.now)
     call=g and g<FASTER_GAP
    else call=arriving(s,i,FASTER_GAP) end
    if call then s.faster[i]=ctx.now; say(ctx,'fasterBehind',3,{'fasterBehind'},{ttl=4,cooldown=15}) end
   end
  end
 end
end
-- Trafic plus rapide quand le joueur est au pas (CRAWL), hors course ; la voiture annoncée ne l'est plus comme tour lancé.
local function crawl(s,ctx)
 local F=ctx.F; local me=F.cars[F.player]
 if F.isRace or not ctx.cfg.fasterBehind or not me or not me.valid or me.pitlane or me.kmh>=CRAWL.kmh then return end
 -- Joueur arrêté ou en tête-à-queue suivi par les urgences (« voiture qui arrive, attends ») : pas de « garde ta ligne ».
 if ctx.cfg.emergencies and ctx.emergency and ctx.emergency.stranded then return end
 local length=trackLength(F)
 for i=0,F.count-1 do
  local c=F.cars[i]
  if i~=F.player and c.valid and not c.pitlane and c.kmh>=me.kmh+CRAWL.faster and ctx.now-(s.faster[i] or -1e9)>60 then
   local ahead=U.ahead(me,c,length,F.open)
   local lc=Link.car(ctx.link,i)
   if ahead<0 and ahead>-CRAWL.range and not (lc and lc.safety) then
    s.faster[i]=ctx.now; s.fastPending[i]=nil; say(ctx,'fasterBehind',3,{'fasterBehind'},{ttl=4,cooldown=15})
   end
  end
 end
end
-- Tour lancé d'AdvancedIA en attente : dit (« laisse-la passer », nom et écart mesuré) dès que la voiture arrive
-- vraiment ; sinon oublié au bout de FAST_CAR_CONFIRM s, écrit au journal seulement. Une voiture déjà annoncée par le
-- trafic plus rapide n'est pas redite ; dite, le trafic plus rapide se tait ensuite pour elle.
local function fastCar(s,ctx)
 for i,at in pairs(s.fastPending) do
  local c=ctx.F.cars[i]
  local ok,g,rate=arriving(s,i,FAST_CAR_MAX)
  if ok and c and c.valid then
   if ctx.now-(s.faster[i] or -1e9)>60 then
    local detail=string.format('(%s · %s s)',name(ctx,i),U.fixed(g,1,Say.mark(ctx.say)))
    if say(ctx,'fastCar',3,{'fastCar',{text=detail}},{ttl=4,cooldown=FAST_CAR_GAP}) then s.faster[i]=ctx.now end
   end
   s.fastPending[i]=nil
  elseif ctx.now-at>FAST_CAR_CONFIRM or ctx.now<at then
   s.fastPending[i]=nil
   if ctx.journal then
    ctx.journal(string.format('tour lancé non confirmé : %s (écart %s, rapprochement %s)',name(ctx,i),
     g and string.format('%.1f s',g) or 'inconnu',rate and string.format('%.2f s/s',rate) or 'non mesuré'))
   end
  end
 end
end
-- Sortie des stands : position de la sortie apprise (passages voie -> piste de toutes les voitures) ; quand le joueur
-- est à moins de EXIT_NEAR m de la sortie après être reparti de son emplacement (1.3.1 : jugé au départ de l'emplacement
-- à 25 km/h, l'arrivée à la sortie était estimée trois fois trop tard), voitures qui y arriveront en même temps que lui.
-- Rien sous drapeau rouge ni voie fermée.
-- Sortie apprise (revue 1.3.2 : le premier passage vu la fixait pour toujours, et une voiture donnée « dans la voie »
-- une image en coupant l'entrée des stands suffisait) : seuls comptent les passages après EXIT_STAY s dans la voie
-- (s.inLane : instant d'entrée), jamais la voiture de sécurité ; un passage loin de la sortie connue nourrit une seconde
-- sortie possible (exitAlt), qui prend sa place dès qu'elle a été vue plus souvent.
local EXIT_NEAR,EXIT_STAY=150,3
local function learnExit(s,sp)
 if s.exitSpline==nil then s.exitSpline=sp; s.exitSamples=1
 elseif math.abs(U.wrap(sp-s.exitSpline))<0.05 then
  s.exitSamples=math.min(20,s.exitSamples+1); s.exitSpline=(s.exitSpline+U.wrap(sp-s.exitSpline)/s.exitSamples)%1
 elseif s.exitAlt and math.abs(U.wrap(sp-s.exitAlt))<0.05 then
  s.exitAltN=s.exitAltN+1; s.exitAlt=(s.exitAlt+U.wrap(sp-s.exitAlt)/s.exitAltN)%1
  if s.exitAltN>s.exitSamples then
   s.exitSpline,s.exitAlt=s.exitAlt,s.exitSpline; s.exitSamples,s.exitAltN=s.exitAltN,s.exitSamples
  end
 else s.exitAlt=sp; s.exitAltN=1 end
end
local function pitExit(s,ctx)
 local F=ctx.F; local cfg=ctx.cfg
 for i=0,F.count-1 do
  local c=F.cars[i]
  if c.valid then
   local since=s.inLane[i]
   if c.pitlane then
    if not since or ctx.now<since then s.inLane[i]=ctx.now end
   elseif since then
    s.inLane[i]=false
    if c.kmh>20 and ctx.now-since>=EXIT_STAY then
     local lc=Link.car(ctx.link,i)
     if not (lc and lc.safety) then learnExit(s,c.spline) end
    end
   end
  end
 end
 local me=F.cars[F.player]
 if not cfg.pitExit or not me or not me.valid then return end
 if not me.pitlane then s.leftBox=false; return end
 if me.inPit then s.leftBox=true; return end
 if not s.leftBox or me.kmh<15 or not s.exitSpline then return end
 local length=trackLength(F)
 local toExit=U.wrap(s.exitSpline-me.spline); if toExit<0 then toExit=toExit+1 end
 if toExit*length>EXIT_NEAR then return end
 s.leftBox=false
 local d=ctx.link.d
 if d and (d.red or d.pitsClosed) then return end
 local myEta=toExit*length/math.max(5,math.max(me.kmh,math.min(F.pitSpeed or 60,60))/3.6)
 local busy=false
 for i=0,F.count-1 do
  local c=F.cars[i]
  local lc=Link.car(ctx.link,i)
  if i~=F.player and c.valid and not c.pitlane and c.kmh>30 and not (lc and lc.safety) then
   local dist=U.wrap(s.exitSpline-c.spline); if dist<0 then dist=dist+1 end
   local eta=dist*length/(c.kmh/3.6)
   if eta>myEta-1.5 and eta<myEta+3 then busy=true end
  end
 end
 say(ctx,'pitExit',2,{busy and 'pitExitTraffic' or 'pitExitClear'},{ttl=6})
end
-- Pénalités des adversaires directs (deux places devant et derrière) : sanctions décidées par AdvancedIA.
local function rivals(s,ctx)
 local F=ctx.F; local me=F.cars[F.player]
 if not ctx.cfg.rivalPenalties or not F.isRace or not me or not me.valid then return end
 for i=0,F.count-1 do
  local lc=Link.car(ctx.link,i)
  if lc and i~=F.player then
   local st=s.rivalState[i]
   local now=s.rivalNow
   now.time=lc.timeAdded; now.pending=lc.pending; now.cut=lc.cutLeft>0; now.dq=lc.sanctionDq or lc.flagDq
   if st then
    local c=F.cars[i]; local rel=c.valid and c.position-me.position or 99
    if math.abs(rel)<=2 and rel~=0 then
     local what=nil
     if now.dq and not st.dq then what='DQ'
     elseif now.pending~=0 and st.pending==0 then what=now.pending==1 and 'DT' or 'SG'
     elseif now.time>st.time+0.5 then what=string.format('+%d s',math.floor(now.time-st.time+0.5))
     elseif now.cut and not st.cut then what='CUT' end
     if what then say(ctx,'rival:'..i,3,{'rivalPenalty',rel<0 and 'wordAhead' or 'wordBehind',{text='('..c.name..' · '..what..')'}},{ttl=10}) end
    end
   end
   if not st then st={}; s.rivalState[i]=st end
   st.time=now.time; st.pending=now.pending; st.cut=now.cut; st.dq=now.dq
  end
 end
end
-- Limites de piste du joueur (non suivies par AdvancedIA pour le joueur) : coupe comptée par AC ou tour invalidé.
local function limits(s,ctx)
 local F=ctx.F; local me=F.me; local car=F.cars[F.player]
 if not ctx.cfg.trackLimits or not car or not car.valid or car.pitlane then s.cuts=me.cuts or 0; s.lapValid=me.lapValid; return end
 if (me.cuts or 0)>s.cuts or (s.lapValid and me.lapValid==false) then say(ctx,'limits',2,{'trackCut'},{ttl=4,cooldown=5}) end
 s.cuts=me.cuts or 0; s.lapValid=me.lapValid
end
-- ctx : {F, link, say, voice, cfg, timing, now (horloge de simulation), real (horloge réelle)}
-- Direction de course toujours suivie (les appels de stands de l'ingénieur en dépendent, rôle Spotter coupé ou non) ;
-- le reste seulement avec le rôle Spotter.
-- Arrivée d'une course (bilan de fin de course, src/debrief.lua) : « Drapeau à damier, course terminée ! Tu es P2. » ;
-- l'ingénieur fait le bilan ensuite ; bilan coupé : le damier seul. Dite dès la ligne passée, pas au retour au stand :
-- AdvancedIA suspend le pont à l'arrivée (garde « finished », la séance est finie pour AC) mais publie encore son
-- résultat ; appelée aussi pendant cette suspension (SpotterEnginer.lua). En jeu le 10/11/2026, le damier n'était venu
-- qu'à la reconnexion du pont, 62 s après la ligne, dans les stands. Place d'AdvancedIA (corrigée des pénalités) dès
-- qu'il a vu l'arrivée, au plus tard FINISH_WAIT s après la ligne (sinon la place d'AC). Ligne vue par AC seulement :
-- AdvancedIA ne remet son résultat à zéro qu'au changement de séance, pas au redémarrage d'une même course (déjà fini
-- avant la ligne : périmé, jamais lu).
local FINISH_WAIT=1
function M.finish(s,ctx)
 local F=ctx.F; local cfg=ctx.cfg; local d=ctx.link.d; local me=F.cars[F.player]
 if s.finishSaid or not F.isRace or not cfg.raceControl or not me or not me.valid or (tonumber(me.laps) or 0)<1 then return end
 if not me.finished then
  if d and d.finished and not F.finishedSession then s.finishStale=true end
  s.finishAt=false; return
 end
 local seen=not s.finishStale and d and d.finished and not d.dnf
 if not s.finishAt then s.finishAt=ctx.real end
 if not seen and ctx.real-s.finishAt<FINISH_WAIT then return end
 s.finishSaid=true
 local place=cfg.debrief and Debrief.place(seen and d or nil,me) or 0
 say(ctx,'chequered',2,place>0 and {'raceDone',{pos=place}} or {'chequered'},{ttl=10})
end
function M.step(s,ctx)
 race(s,ctx)
 M.finish(s,ctx)
 if not ctx.cfg.spotterOn then return end
 if ctx.cfg.sideBySide then side(s,ctx) else sideIdle(s) end
 if ctx.cfg.gaps then gaps(s,ctx) end
 live(s,ctx)
 if ctx.cfg.hazards then Hazards.step(s.haz,ctx) end
 sampleAll(s,ctx)
 traffic(s,ctx)
 crawl(s,ctx)
 fastCar(s,ctx)
 pitExit(s,ctx)
 rivals(s,ctx)
 limits(s,ctx)
end
return M
