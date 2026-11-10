-- Dangers devant (spotter, 1.3.0, demande du pilote : « appeler un danger plus tôt ») : voiture arrêtée, en tête-à-queue
-- ou à contresens devant (une voiture lente l'est par AdvancedIA : drapeau blanc, déjà dit ; une vitesse faible jugée
-- ici se tromperait dans chaque épingle), annoncée au plus tard à NEAR m (règle de la 1.2.0) et plus tôt à grande vitesse,
-- selon le temps pour l'atteindre (LEAD s à la vitesse de rapprochement, jusqu'à RANGE m), avec son côté sur la piste et
-- le côté où passer ; accrochage entre deux voitures devant. Module pur.
-- Sources : état de chaque voiture vu par AdvancedIA (pont : incident, spin, halt, wrong, still, onTrack, calculés pour
-- toutes les voitures), vitesse et collisions d'AC (collidedWith, lu par src/port.lua : c.hit), position latérale sur la
-- piste de CSP (ctx.trackLateral : -1 à gauche, +1 à droite). Jamais « débris » : AC n'en simule pas.
local U=require('src/util')
local Link=require('src/link')
local M={}
-- LEAD : temps d'arrivée sur le danger auquel il est annoncé (s) ; NEAR : distance où il l'est de toute façon (m, celle de
-- la 1.2.0 : jamais plus tard qu'avant) ; FROM : distance minimale (m) ; RANGE : portée (m) ; AGAIN : délai avant de
-- redire la même voiture (s). SIDE : écart latéral (piste de -1 à 1) au-delà
-- duquel la voiture est d'un côté ; OFF : au-delà, hors de la piste. OTHER : délai avant d'annoncer la même voiture
-- pour un autre danger (tête-à-queue puis arrêtée).
M.LEAD=11
M.NEAR=600
M.FROM=40
M.RANGE=900
M.AGAIN=45
M.OTHER=10
M.SIDE=0.3
M.OFF=1.05
-- Accrochage : contact entre deux voitures devant (à moins de TANGLE.range m), dont l'une a perdu TANGLE.loss km/h au
-- moins TANGLE.wait s plus tard (frottement sans conséquence : rien) ; une annonce au plus toutes les TANGLE.again s.
-- Perte jugée EN PLUS de la décélération d'avant le contact (1.3.1, comme le contact du joueur : un frottement au
-- freinage perdait 120 km/h en 1,2 s par le seul freinage) ; vitesses relevées toutes les TANGLE.sample s.
M.TANGLE={range=700,loss=25,wait=1.2,again=30,sample=0.2}
-- Même voiture : ni accrochage ni erreur dits dans les QUIET s qui suivent son danger (une seule transmission par
-- incident), ni pour la voiture de la zone jaune d'AdvancedIA tant qu'elle dure.
M.QUIET=10
local MIN_TRACK=U.MIN_TRACK
function M.new() return {said={},hits={},pending={},tangleAt=-1e9,kA={},tA={},kB={},tB={}} end
-- Nature du danger d'une voiture (clé du clip, priorité) ou nil.
function M.kind(c,lc,me,d)
 local grid=d and (d.red or d.standing=='grid' or d.standing=='lights')
 if lc and lc.wrong then return 'wrongWay',1 end
 if lc and lc.incident and lc.spin then return 'spinAhead',1 end
 if lc and lc.incident and lc.onTrack and lc.still>1 or not grid and c.kmh<12 then return 'stoppedAhead',1 end
 return nil
end
-- Côté de la voiture et conseil (parties), vu du joueur : hors piste, à gauche (passe à droite), à droite (passe à
-- gauche), en pleine trajectoire ; inconnu (pas de piste de CSP) : rien.
-- onTrack d'AdvancedIA n'est écrit que pendant un incident (faux hors incident, 1.3.1 : une voiture arrêtée en pleine
-- piste était dite « hors de la piste » avant qu'AdvancedIA voie l'incident) : lu seulement avec incident.
function M.where(ctx,c,lc)
 if lc and lc.incident and lc.onTrack==false then return {'offTrack'},true end
 local lat=ctx.trackLateral and ctx.trackLateral(c.x,c.y or 0,c.z)
 if not lat then return {},false end
 if math.abs(lat)>M.OFF then return {'offTrack'},true end
 if lat<-M.SIDE then return {'onLeft','passRight'},false end
 if lat>M.SIDE then return {'onRight','passLeft'},false end
 return {'onMiddle'},false
end
local Say=require('src/say')
local say=Say.as('spotter')
-- Accrochages : collisions entre deux voitures (c.hit : indice + 1 de l'autre voiture), jugées TANGLE.wait s plus tard.
local function tangles(h,ctx,me,length)
 local F=ctx.F
 for i=0,F.count-1 do
  local c=F.cars[i]
  local other=c.valid and (c.hit or -1)>0 and c.hit-1 or -1
  if c.valid and (not h.tA[i] or ctx.now-h.tA[i]>=M.TANGLE.sample or ctx.now<h.tA[i]) then h.tB[i]=h.tA[i]; h.kB[i]=h.kA[i]; h.tA[i]=ctx.now; h.kA[i]=c.kmh end
  if other>=0 and other~=F.player and i~=F.player and h.hits[i]~=other then
   local ahead=U.ahead(me,c,length)
   if ahead>30 and ahead<M.TANGLE.range then
    local o=F.cars[other]
    local function rate(j,k) local t0=h.tB[j]; return t0 and ctx.now>t0 and math.max(0,((h.kB[j] or k)-k)/(ctx.now-t0)) or 0 end
    h.pending[#h.pending+1]={a=i,b=other,ka=c.kmh,kb=o and o.kmh or 0,ra=rate(i,c.kmh),rb=o and rate(other,o.kmh) or 0,at=ctx.now}
   end
  end
  h.hits[i]=c.valid and other or -1
 end
 for k=#h.pending,1,-1 do
  local p=h.pending[k]
  if ctx.now<p.at or ctx.now-p.at>M.TANGLE.wait*3 then table.remove(h.pending,k)
  elseif ctx.now-p.at>=M.TANGLE.wait then
   table.remove(h.pending,k)
   local a,b=F.cars[p.a],F.cars[p.b]
   local dt=ctx.now-p.at
   local lost=math.max(p.ka-(a and a.kmh or p.ka)-p.ra*dt,p.kb-(b and b.kmh or p.kb)-p.rb*dt)
   local d=ctx.link.d
   local quiet=function(i) local s=h.said[i]; return s and ctx.now-s.at<M.QUIET and ctx.now>=s.at or d and d.zone and d.zoneCar==i end
   if quiet(p.a) or quiet(p.b) then lost=0 end
   local ahead=a and U.wrap(a.spline-me.spline)*length or -1
   if lost>=M.TANGLE.loss and ahead>20 and ctx.now-h.tangleAt>M.TANGLE.again then
    h.tangleAt=ctx.now
    say(ctx,'tangle',2,{'tangleAhead'},{ttl=4,tone='urgent'})
    if ctx.journal then ctx.journal(string.format('accrochage devant : %s et %s (perte %.0f km/h, à %.0f m)',a.name or '?',b and b.name or '?',lost,ahead)) end
   end
  end
 end
end
-- Chaque image (spotter actif, réglage Dangers devant). Anticipation coupée : danger annoncé au dernier moment
-- (règle de la 1.2.0 : de FROM à NEAR m), et sans les accrochages.
function M.step(h,ctx)
 local F=ctx.F; local me=F.cars[F.player]; local d=ctx.link.d
 local early=ctx.cfg.anticipation
 local lead=early and M.LEAD or 0; local near=M.NEAR
 if not me or not me.valid or me.pitlane or me.kmh<40 or not F.started then return end
 local length=math.max(MIN_TRACK,F.trackLength or 0)
 for i=0,F.count-1 do
  local c=F.cars[i]
  local lc=Link.car(ctx.link,i)
  -- Voiture de sécurité d'AdvancedIA : jamais un danger (elle roule lentement devant la file par nature).
  if i~=F.player and c.valid and not c.pitlane and not (lc and lc.safety) then
   local ahead=U.ahead(me,c,length)
   if ahead>M.FROM and ahead<M.RANGE then
    local kind,prio=M.kind(c,lc,me,d)
    if kind then
     local closing=(kind=='wrongWay' and me.kmh+c.kmh or me.kmh-c.kmh)/3.6
     local eta=ahead/math.max(3,closing)
     local last=h.said[i]
     if (eta<=lead or ahead<=near) and not (last and ctx.now>=last.at and ctx.now-last.at<(last.kind==kind and M.AGAIN or M.OTHER)) then
      local where,off=M.where(ctx,c,lc)
      local parts={kind}
      for k=1,#where do parts[#parts+1]=where[k] end
      -- Hors de la piste : moins urgent (la trajectoire est libre).
      if off and prio==1 then prio=2 end
      if say(ctx,'hazard',prio,parts,{ttl=3,tone='urgent'}) then
       h.said[i]={kind=kind,at=ctx.now}
       if ctx.journal then ctx.journal(string.format('danger devant : %s %s, à %.0f m (%.1f s), %.0f km/h',c.name or '?',kind,ahead,eta,c.kmh)) end
      end
     end
    end
   end
  end
 end
 if early then tangles(h,ctx,me,length) end
end
return M
