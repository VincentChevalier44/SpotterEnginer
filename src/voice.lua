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
--   concerné ; la sécurité (1 et 2) n'attend jamais ;
-- - une annonce est une suite de clips (phrase composée : « écart devant », « un », « virgule », « deux ») ; s'il
--   manque un clip, elle est seulement écrite sur la radio (précédée du signal radio s'il est réglé) ;
-- - signal d'ouverture de la radio (item.chirp, réglage « Signal radio ») : brève tonalité au début de chaque
--   transmission, jamais entre les clips d'une phrase ; une annonce reprise après une coupure est une nouvelle
--   transmission (signal de nouveau) ; un signal qui ne démarre pas ne fait pas perdre la phrase. item.clips n'est
--   jamais modifié.
local M={}
-- Délai de validité par défaut d'une annonce dans la file (s).
M.TTL=6
local MAX_QUEUE=12
function M.new(port)
 return {port=port,queue={},current=nil,handle=nil,clipAt=0,parts=nil,part=0,last={},log={},logMax=40,serial=0,
  volume=1,spotterOn=true,engineerOn=true,spotterVolume=1,engineerVolume=1,gap=0.15,nextAt=0,muted=false,
  infoGap=12,quiet=2,repeatGap=180,infoAt=-1e9,endAt=-1e9,clock=0,started={},heard={}}
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
function M.say(v,item,now)
 if v.muted then return false end
 if item.role=='spotter' and not v.spotterOn or item.role=='engineer' and not v.engineerOn then return false end
 local key=item.key or item.text
 local last=v.last[key]
 if last and now-last<(item.cooldown or 0) then return false end
 v.last[key]=now
 item.key=key; item.at=now; item.prio=item.prio or 3
 -- Même clé déjà en attente : remplacée (valeur plus fraîche), à sa place dans la file.
 for i=1,#v.queue do if v.queue[i].key==key then v.queue[i]=item; return true end end
 if #v.queue>=MAX_QUEUE then
  -- File pleine : la moins urgente (la plus ancienne à égalité) cède sa place, si elle l'est moins que la nouvelle.
  local worst,at=0,nil
  for i=1,#v.queue do local q=v.queue[i]; if q.prio>worst then worst=q.prio; at=i end end
  if not at or worst<item.prio then return false end
  table.remove(v.queue,at)
 end
 v.queue[#v.queue+1]=item
 return true
end
-- Oublie la date de la dernière annonce d'une clé (un état qui revient doit pouvoir être redit).
function M.rearm(v,key) v.last[key]=nil end
-- Retire de la file les annonces d'un préfixe de clé (ex. « side: » quand la voie se libère).
function M.drop(v,prefix)
 for i=#v.queue,1,-1 do if v.queue[i].key:sub(1,#prefix)==prefix then table.remove(v.queue,i) end end
end
local function stopCurrent(v)
 if v.handle then pcall(v.port.stop,v.handle) end
 if v.current then v.endAt=v.clock end
 v.handle=nil; v.current=nil; v.parts=nil; v.part=0
end
M.stop=function(v) stopCurrent(v); v.queue={} end
-- Changement de séance : file vidée et mémoire de la radio oubliée (délais par clé, textes entendus, débuts), le
-- journal et les réglages gardés.
function M.reset(v) M.stop(v); v.last={}; v.heard={}; v.started={}; v.infoAt=-1e9; v.endAt=-1e9; v.nextAt=0 end
-- Une information (priorité 4 ou 5) attend son tour : infoGap s après la précédente, quiet s de silence.
local function ready(v,q,now)
 if q.prio>=4 and (now-v.infoAt<v.infoGap or now-v.endAt<v.quiet) then return false end
 return true
end
local function pick(v,now)
 local best=nil
 for i=#v.queue,1,-1 do
  local q=v.queue[i]
  -- Redite jugée sur le sens (q.sense : clips de base et valeurs, src/say.lua) : une même annonce dite avec une autre
  -- formulation (1.3.0) reste une redite.
  local heard=not q.replay and not q.fresh and q.role=='engineer' and q.prio>=3 and v.repeatGap>0 and (q.sense or q.text) and v.heard[q.sense or q.text]
  if now-q.at>(q.ttl or M.TTL) or heard and now-heard<v.repeatGap then
   table.remove(v.queue,i)
   if v.onEvent then pcall(v.onEvent,now-q.at>(q.ttl or M.TTL) and 'expired' or 'repeat',q) end
  elseif ready(v,q,now) and (not best or q.prio<best.prio or q.prio==best.prio and q.at<best.at) then best=q end
 end
 if best then for i=1,#v.queue do if v.queue[i]==best then table.remove(v.queue,i); break end end end
 return best
end
-- Volume d'un clip : général × rôle, plafonné à 200 % (au-delà, le son sature).
local function volumeOf(v,item) return math.min(2,v.volume*(item.role=='engineer' and v.engineerVolume or v.spotterVolume)) end
local startPart
-- Partie suivante de la phrase en cours (true si elle a démarré).
local function nextPart(v,now)
 if not v.parts or v.part>=#v.parts then return false end
 v.part=v.part+1
 return startPart(v,now)
end
function startPart(v,now)
 local path=v.parts[v.part]
 local ok,handle=pcall(v.port.play,path,volumeOf(v,v.current))
 if ok and handle then v.handle=handle; v.clipAt=now; return true end
 return false
end
-- À chaque image : fin du clip en cours, clip suivant de la phrase, annonce suivante de la file.
function M.step(v,now)
 v.clock=now
 if v.current then
  -- Coupure par une annonce plus urgente : priorité 1 sur 2 et plus, priorité 2 sur 3 et plus.
  local urgent=false
  local cur=v.current.prio
  for i=1,#v.queue do local q=v.queue[i]; if q.prio<=2 and q.prio<cur then urgent=true end end
  local busy=v.handle and v.port.playing(v.handle)
  -- Garde-fou : un clip ne dure jamais plus de 8 s (poignée qui ne dit jamais avoir fini).
  if busy and now-v.clipAt>8 then busy=false end
  if urgent then
   -- L'annonce coupée est redite après, si elle compte encore (priorité 3 au plus, dans son délai, avec sa voix).
   local cut=v.current
   stopCurrent(v)
   -- Jamais pour une annonce d'un instant (item.once : côte à côte, feux, delta…), qui serait fausse après coup.
   -- Ni si une annonce de même clé l'a remplacée (simple jaune devenu double : le double seulement).
   local replaced=false; for i=1,#v.queue do if v.queue[i].key==cut.key then replaced=true end end
   local again=not replaced and not cut.once and not cut.replay and cut.prio<=3 and cut.clips and #cut.clips>0 and now-cut.at<=(cut.ttl or M.TTL)
   if again then cut.replay=true; v.queue[#v.queue+1]=cut end
   if v.onEvent then pcall(v.onEvent,'cut',cut,again) end
  elseif not busy then
   if v.handle then pcall(v.port.stop,v.handle); v.handle=nil end
   -- Clip suivant de la phrase ; fin de la phrase (ou clip qui ne démarre pas) : annonce terminée.
   if not nextPart(v,now) then stopCurrent(v); v.nextAt=now+v.gap end
  end
  if v.current then return end
 end
 if now<v.nextAt or #v.queue==0 then return end
 local item=pick(v,now)
 if not item then return end
 local spoken=item.clips~=nil and #item.clips>0
 -- Reprise après une coupure : déjà au journal (une seule ligne sur la radio de l'overlay).
 if not item.replay then note(v,item,now,spoken) end
 v.started[item.key]=now
 if spoken and (item.sense or item.text) then v.heard[item.sense or item.text]=now end
 if item.prio>=4 then v.infoAt=now end
 if spoken then
  v.current=item; v.part=1
  if item.chirp then
   -- Tonalité d'ouverture puis la phrase (table neuve : la reprise après une coupure repart de item.clips).
   local parts={item.chirp}; for k=1,#item.clips do parts[k+1]=item.clips[k] end
   v.parts=parts
  else v.parts=item.clips end
  -- Signal qui ne démarre pas : la phrase est dite sans lui.
  if not startPart(v,now) and not (item.chirp and nextPart(v,now)) then stopCurrent(v); v.nextAt=now+v.gap end
 elseif item.chirp then
  -- Message écrit seulement : bip de radio s'il existe.
  local ok,handle=pcall(v.port.play,item.chirp,volumeOf(v,item))
  if ok and handle then v.current=item; v.parts={item.chirp}; v.part=1; v.handle=handle; v.clipAt=now end
 end
end
function M.busy(v) return v.current~=nil end
-- Annonce de cette clé en attente dans la file.
function M.pending(v,key) for i=1,#v.queue do if v.queue[i].key==key then return true end end return false end
-- Annonces devenues fausses (un état qui vient de finir : neutralisation, zone jaune…) : retirées de la file, et coupées
-- si l'une d'elles est en cours (keys : ensemble de clés).
function M.cancel(v,keys)
 for i=#v.queue,1,-1 do if keys[v.queue[i].key] then table.remove(v.queue,i) end end
 if v.current and keys[v.current.key] then stopCurrent(v) end
end
return M
