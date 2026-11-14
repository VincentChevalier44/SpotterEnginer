-- Radio : une seule file pour les deux rôles (spotter et ingénieur), une seule voix à la fois. Module pur : la lecture
-- passe par un port injecté (port.play(path, volume) -> poignée ; port.playing(poignée) ; port.stop(poignée)), ce qui
-- permet de le tester hors du jeu.
--
-- Règles :
-- - priorité 1 (sécurité immédiate : drapeau rouge, voiture arrêtée devant, côte à côte) à 5 (information) ;
-- - réactivité : une annonce de priorité 1 coupe une annonce de priorité 2 ou plus en cours, une de priorité 2 coupe
--   une de priorité 3 ou plus ; jamais l'inverse. L'annonce coupée (priorité 3 au plus, encore valable) est redite une
--   fois (coupée de nouveau : abandonnée ; au départ, des « voiture à gauche » en rafale la feraient redire sans fin)
--   ensuite, depuis le début ; une annonce devenue fausse (état terminé) est annulée (M.cancel), même en cours ;
-- - une annonce périmée (ttl dépassé dans la file) est abandonnée sans être dite ;
-- - une même annonce (même clé) remplace celle qui attend déjà dans la file ;
-- - délai minimal entre deux annonces d'une même clé (cooldown) ;
-- - rythme (contre le harcèlement) : une information (priorité 4 ou 5) attend infoGap s après la précédente et quiet s
--   de silence ; un même texte de l'ingénieur (priorité 3 et plus) n'est pas redit avant repeatGap s, sauf un état
--   nouveau (item.fresh : position) ; le spotter (voiture lente, piste glissante, retardataire…) n'est jamais
--   concerné ; la sécurité (1 et 2) n'attend jamais ; une information de l'ingénieur retenue par ce rythme reste
--   valable le temps d'attendre son tour (voir life) : elle est retardée, pas perdue ;
-- - une annonce est une suite de clips (phrase composée : « écart devant », « un », « virgule », « deux ») ; s'il
--   manque un clip, elle est seulement écrite sur la radio (précédée du signal radio s'il est réglé) ;
-- - signal d'ouverture de la radio (item.chirp, réglage « Signal radio ») : brève tonalité au début de chaque
--   transmission, jamais entre les clips d'une phrase ; une annonce reprise après une coupure est une nouvelle
--   transmission (signal de nouveau) ; un signal qui ne démarre pas ne fait pas perdre la phrase. item.clips n'est
--   jamais modifié ;
-- - instantané (1.3.1) : une annonce de sécurité (priorité 1 et 2) n'attend jamais le petit blanc entre deux annonces
--   (gap) ; la priorité 1 part sans signal radio, et une transmission qui suit la précédente de moins de chainGap s non
--   plus (« à gauche… toujours là… dégagé » d'une traite) ; le clip suivant d'une phrase est préparé pendant le clip en
--   cours (port.prepare / port.start, s'ils existent) et part dès la fin de celui-ci ; une annonce d'un instant (once)
--   de priorité 1 (côte à côte) coupe une autre annonce de priorité 1 qui n'en est pas une (drapeau rouge redit ensuite) ;
-- - entendu (1.3.1) : une annonce compte comme entendue (v.done, redite jugée par v.heard) seulement dite jusqu'au bout,
--   ou coupée après heardAfter s de voix ; une annonce écrite seulement (clip absent) ne compte pas comme information
--   pour le rythme.
local M={}
-- Délai de validité par défaut d'une annonce dans la file (s).
M.TTL=6
local MAX_QUEUE=12
function M.new(port)
 return {port=port,queue={},current=nil,handle=nil,clipAt=0,parts=nil,part=0,last={},log={},logMax=40,serial=0,
  volume=1,spotterOn=true,engineerOn=true,spotterVolume=1,engineerVolume=1,gap=0.15,nextAt=0,muted=false,
  infoGap=12,quiet=2,repeatGap=180,infoAt=-1e9,endAt=-1e9,clock=0,started={},heard={},done={},chainGap=1.0,heardAfter=0.5,
  nextH=nil,voiceAt=nil}
end
-- Journal de la radio (messages écrits, dits ou non) : le plus récent en dernier.
local function note(v,item,now,spoken)
 v.serial=v.serial+1
 local entry={serial=v.serial,at=now,role=item.role,text=item.text,prio=item.prio,spoken=spoken,kind=item.kind,key=item.key,queued=item.at}
 local log=v.log
 log[#log+1]=entry
 if #log>v.logMax then table.remove(log,1) end
 -- Journal de session (SpotterEnginer.lua) : jamais d'erreur remontée à la radio.
 if v.onEvent then pcall(v.onEvent,'radio',entry) end
 return entry
end
M.note=note
-- item : {key, role='spotter'|'engineer', prio=1..5, clips={chemin,...} ou nil, text, ttl (s), cooldown (s), kind}
-- Refusée d'avance (radio coupée, rôle coupé, délai de la clé) : Say.say s'arrête là, sans rien préparer.
function M.refused(v,role,key,cooldown,now)
 if v.muted then return true end
 if role=='spotter' and not v.spotterOn or role=='engineer' and not v.engineerOn then return true end
 if M.pending(v,key) then return false end
 local last=v.last[key]
 return last~=nil and now-last<(cooldown or 0) and now>=last
end
function M.say(v,item,now)
 if v.muted then return false end
 if item.role=='spotter' and not v.spotterOn or item.role=='engineer' and not v.engineerOn then return false end
 local key=item.key or item.text
 item.key=key; item.at=now; item.prio=item.prio or 3
 -- Même clé déjà en attente : remplacée (valeur plus fraîche, même pendant le délai de la clé), à sa place dans la file.
 for i=1,#v.queue do if v.queue[i].key==key then v.queue[i]=item; v.last[key]=now; return true end end
 local last=v.last[key]
 if last and now-last<(item.cooldown or 0) and now>=last then return false end
 if #v.queue>=MAX_QUEUE then
  -- File pleine : la moins urgente (la plus ancienne à égalité) cède sa place, si elle l'est moins que la nouvelle.
  local worst,at=0,nil
  for i=1,#v.queue do local q=v.queue[i]; if q.prio>worst then worst=q.prio; at=i end end
  if not at or worst<item.prio then return false end
  table.remove(v.queue,at)
 end
 -- Délai de la clé compté seulement pour une annonce entrée en file (jamais pour un refus).
 v.last[key]=now
 v.queue[#v.queue+1]=item
 return true
end
-- Oublie la date de la dernière annonce d'une clé (un état qui revient doit pouvoir être redit).
function M.rearm(v,key) v.last[key]=nil end
-- Retire de la file les annonces d'un préfixe de clé (ex. « side: » quand la voie se libère).
function M.drop(v,prefix)
 for i=#v.queue,1,-1 do if v.queue[i].key:sub(1,#prefix)==prefix then table.remove(v.queue,i) end end
end
-- Annonce entendue : dite jusqu'au bout, ou coupée après heardAfter s de voix.
local function markDone(v,item,now)
 v.done[item.key]=now
 if item.sense or item.text then
  v.heard[item.sense or item.text]=now
  -- Mémoire des annonces entendues gardée au rechargement de l'app (SpotterEnginer.lua) : jamais d'erreur remontée.
  if v.onHeard then pcall(v.onHeard,item) end
 end
end
-- Annonces entendues depuis moins de repeatGap s, en texte (« sens<TAB>âge en secondes », une par ligne, les max plus
-- récentes) ; relues par M.heardLoad après un rechargement de l'app : l'ingénieur ne redit pas ce qu'il vient de dire.
function M.heardText(v,now,max)
 local list={}
 for sense,at in pairs(v.heard) do
  if now-at<v.repeatGap and now>=at and not sense:find('[\t\n]') then list[#list+1]={sense,now-at} end
 end
 table.sort(list,function(a,b) return a[2]<b[2] end)
 local out={}
 for k=1,math.min(#list,max or 40) do out[k]=string.format('%s\t%.0f',list[k][1],list[k][2]) end
 return table.concat(out,'\n')
end
function M.heardLoad(v,text,now)
 if type(text)~='string' then return 0 end
 local n=0
 for sense,age in text:gmatch('([^\t\n]+)\t(%d+)') do v.heard[sense]=now-tonumber(age); n=n+1 end
 return n
end
-- Durée de validité d'une annonce en file. Une information de l'ingénieur (priorité 4 ou 5) attend son tour derrière
-- infoGap : elle reste valable le temps de laisser passer HOLD_TURNS informations (infoGap + quiet chacune) plus HOLD s
-- (trois informations à la ligne sont dites toutes les trois), HOLD_MAX s au plus (jamais une information dite une
-- minute trop tard), sauf une information d'un instant (ttl sous HOLD_MIN s), qui périme comme elle le demande.
local HOLD,HOLD_TURNS,HOLD_MIN,HOLD_MAX=5,3,10,45
local function life(v,q)
 local ttl=q.ttl or M.TTL
 if q.prio>=4 and q.role=='engineer' and not q.replay and ttl>=HOLD_MIN then
  local wait=math.min(HOLD_MAX,HOLD_TURNS*(v.infoGap+v.quiet)+HOLD)
  if wait>ttl then return wait end
 end
 return ttl
end
local function stopCurrent(v)
 if v.handle then pcall(v.port.stop,v.handle) end
 if v.nextH then pcall(v.port.stop,v.nextH) end
 if v.current then v.endAt=v.clock end
 v.handle=nil; v.nextH=nil; v.current=nil; v.parts=nil; v.part=0; v.voiceAt=nil
end
M.stop=function(v) stopCurrent(v); v.queue={} end
-- Changement de séance : file vidée et mémoire de la radio oubliée (délais par clé, textes entendus, débuts), le
-- journal et les réglages gardés.
-- Délais de toutes les clés oubliés (1.3.9 : retour à la radio du joueur après celle de la voiture regardée).
function M.forgetAll(v) for k in pairs(v.last) do v.last[k]=nil end end
function M.reset(v) M.stop(v); v.last={}; v.heard={}; v.started={}; v.done={}; v.infoAt=-1e9; v.endAt=-1e9; v.nextAt=0 end
-- Une information (priorité 4 ou 5) attend son tour : infoGap s après la précédente, quiet s de silence. Une annonce
-- reprise après une coupure, et une information du spotter (DRS, appel de phares… : vraies pendant quelques secondes
-- seulement) n'attendent que le silence (1.3.1 : elles périmaient toujours derrière infoGap).
local function ready(v,q,now)
 if q.prio<4 then return true end
 if now-v.endAt<v.quiet and now>=v.endAt then return false end
 if q.replay or q.role=='spotter' then return true end
 return not (now-v.infoAt<v.infoGap and now>=v.infoAt)
end
local function pick(v,now)
 local best=nil
 for i=#v.queue,1,-1 do
  local q=v.queue[i]
  -- Redite jugée sur le sens (q.sense : clips de base et valeurs, src/say.lua) : une même annonce dite avec une autre
  -- formulation (1.3.0) reste une redite.
  local heard=not q.replay and not q.fresh and q.role=='engineer' and q.prio>=3 and v.repeatGap>0 and (q.sense or q.text) and v.heard[q.sense or q.text]
  local expired=now-q.at>life(v,q)
  if expired or heard and now-heard<v.repeatGap then
   table.remove(v.queue,i)
   -- Périmée sans avoir été dite : le délai de sa clé ne compte pas (elle peut être redite dès que vraie).
   if expired and not q.replay and v.last[q.key]==q.at then v.last[q.key]=nil end
   if v.onEvent then pcall(v.onEvent,expired and 'expired' or 'repeat',q) end
  elseif ready(v,q,now) and (not best or q.prio<best.prio or q.prio==best.prio and q.at<best.at) then best=q end
 end
 if best then for i=1,#v.queue do if v.queue[i]==best then table.remove(v.queue,i); break end end end
 return best
end
-- Volume d'un clip : général × rôle, plafonné à 200 % (au-delà, le son sature).
local function volumeOf(v,item) return math.min(2,v.volume*(item.role=='engineer' and v.engineerVolume or v.spotterVolume)) end
local startPart
-- Partie suivante de la phrase en cours (true si elle a démarré) ; une partie qui ne démarre pas est sautée.
local function nextPart(v,now)
 while v.parts and v.part<#v.parts do
  v.part=v.part+1
  if startPart(v,now) then return true end
 end
 return false
end
-- Clip préparé à l'avance (port.prepare : chargé, pas démarré) : la partie suivante part sans chargement à la jointure.
local function prepareNext(v)
 if v.nextH then pcall(v.port.stop,v.nextH); v.nextH=nil end
 local path=v.parts and v.parts[v.part+1]
 if path and v.port.prepare then
  local ok,h=pcall(v.port.prepare,path,volumeOf(v,v.current))
  if ok and h then v.nextH=h end
 end
end
function startPart(v,now)
 local path=v.parts[v.part]
 local ok,handle=false,nil
 if v.nextH and v.nextH.path==path and v.port.start then
  local h=v.nextH; v.nextH=nil
  ok=pcall(v.port.start,h); handle=ok and h or nil
  if not ok then pcall(v.port.stop,h) end
 end
 if not handle then ok,handle=pcall(v.port.play,path,volumeOf(v,v.current)) end
 if ok and handle then
  v.handle=handle; v.clipAt=now
  -- Début de la voix (le signal radio n'en est pas) : base de « entendu ».
  if not v.voiceAt and path~=v.current.chirp then v.voiceAt=now end
  prepareNext(v)
  return true
 end
 return false
end
-- À chaque image : fin du clip en cours, clip suivant de la phrase, annonce suivante de la file.
function M.step(v,now)
 v.clock=now
 if v.current then
  -- Coupure par une annonce plus urgente : priorité 1 sur 2 et plus, priorité 2 sur 3 et plus.
  local urgent=false
  local cur=v.current.prio
  -- Une annonce d'un instant de priorité 1 (côte à côte) coupe aussi une annonce de priorité 1 qui n'en est pas une.
  local instant=cur==1 and not v.current.once
  for i=1,#v.queue do local q=v.queue[i]; if q.prio<=2 and q.prio<cur or instant and q.prio==1 and q.once then urgent=true end end
  local busy=v.handle and v.port.playing(v.handle)
  -- Garde-fou : un clip ne dure jamais plus de 8 s (poignée qui ne dit jamais avoir fini).
  if busy and now-v.clipAt>8 then busy=false end
  if urgent then
   -- L'annonce coupée est redite après, si elle compte encore (priorité 3 au plus, dans son délai, avec sa voix).
   local cut=v.current
   if v.voiceAt and now-v.voiceAt>=v.heardAfter then markDone(v,cut,now) end
   stopCurrent(v)
   -- Jamais pour une annonce d'un instant (item.once : côte à côte, feux, delta…), qui serait fausse après coup.
   -- Ni si une annonce de même clé l'a remplacée (simple jaune devenu double : le double seulement).
   local replaced=false; for i=1,#v.queue do if v.queue[i].key==cut.key then replaced=true end end
   local again=not replaced and not cut.once and not cut.replay and cut.prio<=3 and cut.clips and #cut.clips>0 and now-cut.at<=(cut.ttl or M.TTL)
   if again then cut.replay=true; v.queue[#v.queue+1]=cut end
   if v.onEvent then pcall(v.onEvent,'cut',cut,again) end
  elseif not busy then
   if v.handle then pcall(v.port.stop,v.handle); v.handle=nil end
   -- Clip suivant de la phrase ; fin de la phrase (ou plus aucun clip qui démarre) : annonce terminée, entendue.
   if not nextPart(v,now) then
    if v.voiceAt then markDone(v,v.current,now) end
    stopCurrent(v); v.nextAt=now+v.gap
   end
  end
  if v.current then return end
 end
 if #v.queue==0 then return end
 -- Petit blanc entre deux annonces : jamais pour la sécurité (priorités 1 et 2).
 if now<v.nextAt then
  local urgent=false
  for i=1,#v.queue do if v.queue[i].prio<=2 then urgent=true; break end end
  if not urgent then return end
 end
 local item=pick(v,now)
 if not item then return end
 local spoken=item.clips~=nil and #item.clips>0
 if spoken then
  v.current=item; v.part=1; v.voiceAt=nil
  -- Signal d'ouverture : jamais pour la priorité 1 (« voiture à gauche » sans attendre), ni pour une transmission qui
  -- suit la précédente de moins de chainGap s (même échange radio).
  local tone=item.chirp and item.prio>1 and not (now-v.endAt<v.chainGap and now>=v.endAt) and item.chirp or nil
  if tone then
   -- Tonalité d'ouverture puis la phrase (table neuve : la reprise après une coupure repart de item.clips).
   local parts={tone}; for k=1,#item.clips do parts[k+1]=item.clips[k] end
   v.parts=parts
  else v.parts=item.clips end
  -- Signal ou clip qui ne démarre pas : la phrase est dite sans lui.
  if not startPart(v,now) and not nextPart(v,now) then stopCurrent(v); v.nextAt=now+v.gap; spoken=false end
 end
 -- Journal après le départ du son (jamais une écriture avant une annonce de sécurité) ; reprise après une coupure :
 -- déjà au journal (une seule ligne sur la radio de l'overlay).
 if not item.replay then note(v,item,now,spoken) end
 -- Commencée (côte à côte : « dégagé » seulement après l'annonce du côté), même écrite seulement ; information pour le
 -- rythme seulement si elle est dite.
 v.started[item.key]=now
 if spoken then
  if item.prio>=4 then v.infoAt=now end
 elseif item.chirp and not v.current then
  -- Message écrit seulement : bip de radio s'il existe.
  local ok,handle=pcall(v.port.play,item.chirp,volumeOf(v,item))
  if ok and handle then v.current=item; v.parts={item.chirp}; v.part=1; v.handle=handle; v.clipAt=now end
 end
end
function M.busy(v) return v.current~=nil end
-- Annonces écartées de la file (drop(q) vrai) ; cut : celle en cours aussi, si elle l'est. Liaison suspendue ou perdue
-- (tout sauf l'essai de la voix), rôle coupé, langue changée (SpotterEnginer.lua).
function M.purge(v,drop,cut)
 for i=#v.queue,1,-1 do if drop(v.queue[i]) then table.remove(v.queue,i) end end
 if cut and v.current and drop(v.current) then stopCurrent(v) end
end
-- Annonce de cette clé en attente dans la file.
function M.pending(v,key)
 for i=1,#v.queue do local q=v.queue[i]; if q.key==key and v.clock-q.at<=life(v,q) then return true end end
 return false
end
-- Une annonce de sécurité attend (priorité 1 ou 2) : le son de la voiture est déjà baissé.
function M.urgentWaiting(v) for i=1,#v.queue do if v.queue[i].prio<=2 then return true end end return false end
-- Annonces devenues fausses (un état qui vient de finir : neutralisation, zone jaune…) : retirées de la file, et coupées
-- si l'une d'elles est en cours (keys : ensemble de clés).
function M.cancel(v,keys)
 for i=#v.queue,1,-1 do if keys[v.queue[i].key] then table.remove(v.queue,i) end end
 if v.current and keys[v.current.key] then stopCurrent(v) end
end
return M
