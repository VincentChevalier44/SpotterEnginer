-- Urgences du joueur (1.3.0, demande du pilote : « gestion des situations d'urgence plus réaliste ») : contact avec une
-- voiture ou un mur, bilan des dégâts quelques secondes après, crevaison, tête-à-queue ou arrêt sur la piste avec la
-- reprise guidée (« voiture qui arrive, attends », puis « c'est libre, vas-y »), retour sur la piste après une sortie,
-- contresens. Le spotter dit ce qui se passe autour, l'ingénieur ce qui touche la voiture. Module pur.
-- Sources : collidedWith d'AC (0 : mur, indice + 1 : voiture, -1 : rien ; src/port.lua : F.me.hit), dégâts de la
-- carrosserie (km/h d'impact par zone) et des suspensions (0 à 1), pneus crevés ; état du joueur vu par AdvancedIA
-- (pont : spin, wrong, onTrack, calculés pour le joueur aussi).
local U=require('src/util')
local Say=require('src/say')
local Link=require('src/link')
local M={}
-- CONTACT : délai de la mesure de l'impact (s), perte de vitesse d'un contact annoncé (km/h), d'un gros choc contre un
-- mur, hausse des dégâts qui suffit à l'annoncer, délai du bilan (s) ; bilan : seuils de dégâts (km/h cumulés) et de
-- suspension ; again : délai entre deux « contact » (mêlée du départ : une annonce, pas une toutes les 4 s) ; noneAgain :
-- délai entre deux « pas de dégâts » après un contact avec une voiture (toujours dit après un gros choc). TRAFFIC : voitures qui arrivent derrière (s avant d'être sur le joueur), libre après clear s sans voiture,
-- portée (m). STOP : arrêt sur la piste (km/h, tenu hold s), épisode fini au-dessus de done km/h pendant doneFor s.
M.CONTACT={measure=0.4,loss=6,wall=40,rise=3,report=3.5,light=6,medium=25,heavy=60,suspension=0.1,keep=6,again=15,noneAgain=60}
M.TRAFFIC={eta=4,rejoinEta=3,clear=1,range=400,minKmh=40,every=0.25}
M.STOP={kmh=8,hold=2,done=50,doneFor=2}
local MIN_TRACK=500
function M.new()
 return {contactAt=-1e9,noneAt=-1e9,hit=-1,kmhPrev=0,dmgBase=nil,suspBase=nil,contact=nil,reportUntil=-1e9,blown={},spinWas=false,wrongWas=false,
  stranded=false,stopFor=0,doneFor=0,waiting=false,freeFor=0,checkAt=-1e9,traffic=false,off=false,onFor=0,rejoinSaid=false}
end
function M.reset(em) U.refill(em,M.new()) end
local function sum(t,a,b) local s=0; for k=a,b do s=s+(tonumber(t[k]) or 0) end; return s end
local function spotter(ctx,key,prio,parts,opts) return Say.say(ctx.say,'spotter',key,prio,parts,ctx.real,opts) end
local function engineer(ctx,key,prio,parts,opts) return Say.say(ctx.say,'engineer',key,prio,parts,ctx.real,opts) end
-- Voiture qui arrive derrière le joueur sur la piste en moins de eta s.
function M.arriving(ctx,eta)
 local F=ctx.F; local me=F.cars[F.player]
 local length=math.max(MIN_TRACK,F.trackLength or 0)
 for i=0,F.count-1 do
  local c=F.cars[i]
  if i~=F.player and c.valid and not c.pitlane and c.kmh>M.TRAFFIC.minKmh then
   local dist=U.wrap(me.spline-c.spline)*length
   if dist>0 and dist<M.TRAFFIC.range and dist/(c.kmh/3.6)<eta then return true end
  end
 end
 return false
end
-- Bilan des dégâts (ingénieur) après un contact : clip selon la hausse des dégâts et de la suspension depuis le contact.
function M.verdict(rise,susp,announced)
 local C=M.CONTACT
 if susp>=C.suspension then return 'damageSuspension',2 end
 if rise>=C.heavy then return 'damageHeavy',2 end
 if rise>=C.medium then return 'damageMedium',3 end
 if rise>=C.light then return 'damageLight',3 end
 if announced then return 'damageNone',3 end
 return nil
end
local function contacts(em,ctx,me)
 local F=ctx.F; local cfg=ctx.cfg; local C=M.CONTACT
 local dmg=sum(F.me.damage,1,4); local susp=sum(F.me.susp or {},1,4)
 local hit=F.me.hit or -1
 if not em.contact and not me.pitlane and (hit>=0 and em.hit<0 or hit>0 and hit~=em.hit) then
  em.contact={at=ctx.now,kmh0=math.max(em.kmhPrev,me.kmh),dmg0=em.dmgBase or dmg,susp0=em.suspBase or susp,car=hit>0 and hit-1 or -1,
   measured=false,announced=false}
 end
 em.hit=hit
 local c=em.contact
 if not c then em.kmhPrev=me.kmh; em.dmgBase=dmg; em.suspBase=susp; return end
 if ctx.now<c.at or ctx.now-c.at>C.keep+C.report then em.contact=nil; return end
 local rise=dmg-c.dmg0
 if not c.measured and ctx.now-c.at>=C.measure then
  c.measured=true
  local loss=c.kmh0-me.kmh
  if c.car>=0 and (loss>=C.loss or rise>=C.rise) and (ctx.now-em.contactAt>=C.again or ctx.now<em.contactAt) then
   em.contactAt=ctx.now
   local other=F.cars[c.car]
   c.announced=true
   spotter(ctx,'contact',2,{'contact',{text='('..(other and other.name or '?')..')'}},{ttl=2,once=true,tone='urgent'})
  elseif c.car<0 and (loss>=C.wall or rise>=C.light) then
   c.announced=true
   engineer(ctx,'damage',2,{'wallHit'},{ttl=4,tone='urgent'})
  end
  if ctx.journal and (c.announced or rise>0) then
   ctx.journal(string.format('contact %s : perte %.0f km/h, dégâts +%.0f',c.car>=0 and ('avec '..((F.cars[c.car] or {}).name or '?')) or 'mur',loss,rise))
  end
 end
 if c.measured and ctx.now-c.at>=C.report then
  em.contact=nil; em.dmgBase=dmg; em.suspBase=susp
  local id,prio=M.verdict(rise,susp-c.susp0,c.announced)
  -- « Pas de dégâts » : toujours après un gros choc, au plus toutes les noneAgain s après un contact avec une voiture.
  if id=='damageNone' and c.car>=0 then if ctx.now-em.noneAt<C.noneAgain and ctx.now>=em.noneAt then id=nil else em.noneAt=ctx.now end end
  if id and cfg.damage then
   em.reportUntil=ctx.real+10
   engineer(ctx,'damage',prio,{id},{ttl=8,tone=Say.toneOf(id)})
   if ctx.journal then ctx.journal(string.format('bilan des dégâts : %s (carrosserie +%.0f, suspension +%.2f)',id,rise,susp-c.susp0)) end
  end
 end
end
local function puncture(em,ctx,me)
 local t=ctx.F.me.tyres
 for k=1,4 do
  local b=t[k] and t[k].blown==true
  if me.pitlane then em.blown[k]=false
  elseif b and not em.blown[k] then
   em.blown[k]=true
   engineer(ctx,'puncture',1,{'puncture'},{ttl=8,tone='urgent',cooldown=60})
  elseif not b then em.blown[k]=false end
 end
end
-- Tête-à-queue, arrêt sur la piste, contresens : épisode guidé jusqu'à la reprise.
local function stranded(em,ctx,me,dt)
 local F=ctx.F; local d=ctx.link.d
 local lc=Link.car(ctx.link,F.player)
 local held=d and (d.red or d.standing=='grid' or d.standing=='lights')
 local running=F.started and not held and not me.pitlane and not me.finished
 local spin=running and lc and lc.spin and lc.incident or false
 local wrong=running and lc and lc.wrong or false
 em.stopFor=running and me.kmh<M.STOP.kmh and em.stopFor+dt or 0
 if ctx.now-em.checkAt>=M.TRAFFIC.every or ctx.now<em.checkAt then em.checkAt=ctx.now; em.traffic=M.arriving(ctx,M.TRAFFIC.eta) end
 if not em.stranded and running and (spin and not em.spinWas or wrong and not em.wrongWas or em.stopFor>=M.STOP.hold) then
  em.stranded=true; em.doneFor=0; em.freeFor=0; em.waiting=em.traffic
  if wrong then spotter(ctx,'stranded',1,{'youWrongWay'},{ttl=4,tone='urgent'})
  elseif spin then
   if em.traffic then spotter(ctx,'stranded',1,{'spunYou'},{ttl=4,tone='urgent'}) else spotter(ctx,'stranded',2,{'spunClear'},{ttl=4,tone='calm'}) end
  elseif em.traffic then spotter(ctx,'stranded',1,{'stoppedYou'},{ttl=4,tone='urgent'}) end
  if ctx.journal then ctx.journal(string.format('joueur %s sur la piste%s',wrong and 'à contresens' or spin and 'en tête-à-queue' or 'arrêté',em.traffic and ', voitures en approche' or '')) end
 elseif em.stranded then
  if not running then em.stranded=false
  else
   em.doneFor=(me.kmh>M.STOP.done and not wrong) and em.doneFor+dt or 0
   if em.doneFor>=M.STOP.doneFor then em.stranded=false
   elseif em.traffic then
    em.freeFor=0
    if not em.waiting then em.waiting=true; spotter(ctx,'stranded',1,{'waitTraffic'},{ttl=3,tone='urgent',cooldown=4}) end
   elseif em.waiting then
    em.freeFor=em.freeFor+dt
    if em.freeFor>=M.TRAFFIC.clear then em.waiting=false; spotter(ctx,'stranded',2,{'goNow'},{ttl=3}) end
   end
  end
 end
 em.spinWas=spin; em.wrongWas=wrong
 -- Retour sur la piste après une sortie (hors épisode) : voiture qui arrive, une fois par sortie.
 local off=running and not em.stranded and (lc and lc.onTrack==false or (F.me.wheelsOut or 0)>=4)
 if off then
  em.off=true; em.onFor=0
  if not em.rejoinSaid and me.kmh<120 and M.arriving(ctx,M.TRAFFIC.rejoinEta) then
   em.rejoinSaid=true; spotter(ctx,'rejoin',1,{'rejoinCareful'},{ttl=3,tone='urgent'})
  end
 elseif em.off then
  em.onFor=em.onFor+dt
  if em.onFor>3 then em.off=false; em.rejoinSaid=false end
 end
end
-- Chaque image (app active) ; dt : pas de l'image (s). Réglage « Urgences » coupé : mesures tenues à jour, rien de dit.
function M.step(em,ctx,dt)
 local F=ctx.F; local me=F.cars[F.player]
 if not me or not me.valid then return end
 if not ctx.cfg.emergencies then
  em.hit=F.me.hit or -1; em.contact=nil; em.kmhPrev=me.kmh; em.dmgBase=sum(F.me.damage,1,4); em.suspBase=sum(F.me.susp or {},1,4)
  em.stranded=false; em.stopFor=0
  return
 end
 contacts(em,ctx,me)
 puncture(em,ctx,me)
 stranded(em,ctx,me,dt or 0)
end
-- L'ingénieur ne redit pas « dégâts aéro » pendant un contact suivi ici, ni juste après son bilan.
function M.busy(em,ctx) return em and (em.contact~=nil or ctx.real<em.reportUntil) or false end
return M
