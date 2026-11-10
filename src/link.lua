-- Liaison avec AdvancedIA (pont src/bridge_layout.lua) : état de la connexion, décisions pures. Les deux structures
-- partagées (hello, data) sont ouvertes par le port (src/port.lua) et lues ici ; dans les tests, ce sont des tables.
--
-- États (link.state) :
--   absent     AdvancedIA n'est pas installé (aucun manifeste dans apps/lua/AdvancedIA ni dans l'ancien apps/lua/ACAdvancedIA) ;
--   nobridge   installé, mais sans le pont (version d'avant le pont : src/bridge.lua absent) ;
--   waiting    installé avec le pont, aucun battement : app non lancée (désactivée dans CSP) ou pas encore démarrée ;
--   closed     AdvancedIA vient d'être déchargé ;
--   version    AdvancedIA publie une autre version du pont que celle de cette app ;
--   suspended  connecté, mais son moteur ne tourne pas (app coupée, pause, replay, en ligne, erreur…) : link.reason ;
--   connected  connecté, moteur en marche : le spotter et l'ingénieur travaillent.
-- Sans AdvancedIA connecté, SpotterEnginer ne dit rien et n'affiche que l'état de la liaison.
local Layout=require('src/bridge_layout')
local M={}
-- Battement attendu au moins toutes les K.stale secondes (temps réel) ; au-delà : arrêté.
M.stale=2.5
function M.new(installed,hasBridge,release)
 return {state='waiting',reason='',installed=installed==true,hasBridge=hasBridge==true,release=release or '',
  lastBeat=0,beatAt=-1,remoteVersion=0,remoteRelease='',d=nil,cars=nil}
end
-- hello, data : structures partagées (ou nil si ac.connect a échoué) ; now : horloge réelle (s).
local function readRelease(h) return h.release end
function M.step(k,hello,data,now)
 local before=k.state
 local state,reason='waiting',''
 if not k.installed then state='absent'
 elseif not hello then state=k.hasBridge and 'waiting' or 'nobridge'
 else
  local beat=tonumber(hello.heartbeat) or 0
  if beat~=k.lastBeat then k.lastBeat=beat; k.beatAt=now end
  local alive=beat~=0 and k.beatAt>=0 and now-k.beatAt<=M.stale
  k.remoteVersion=tonumber(hello.bridgeVersion) or 0
  if hello.closed==true then state='closed'
  elseif not alive then state=k.hasBridge and 'waiting' or 'nobridge'
  elseif k.remoteVersion~=Layout.version then state='version'
  elseif not data then state='version'
  else
   local okRelease,rel=pcall(readRelease,hello)
   if okRelease and type(rel)=='string' then k.remoteRelease=rel end
   if data.enabled~=true then state='suspended'; reason='disabled'
   elseif data.panic==true then state='suspended'; reason='panic'
   elseif data.online==true then state='suspended'; reason='online'
   elseif data.replay==true then state='suspended'; reason='replay'
   elseif data.paused==true then state='suspended'; reason='paused'
   elseif data.ready~=true then state='suspended'; reason=data.guard or ''
   else state='connected' end
  end
 end
 k.state=state; k.reason=reason
 k.d=(state=='connected' or state=='suspended') and data or nil
 k.cars=k.d and data.cars or nil
 return state~=before
end
function M.connected(k) return k.state=='connected' end
-- Course neutralisée ou arrêtée (VSC, FCY, SC, drapeau rouge) d'après les données du pont (d : nil sans pont).
function M.neutralised(d) return d~=nil and (d.neutral or d.red) or false end
-- Données d'une voiture (indice d'AC), ou nil.
function M.car(k,index)
 if not k.cars or not index or index<0 or index>=Layout.maxCars then return nil end
 local c=k.cars[index]
 if c and c.valid then return c end
 return nil
end
return M
