-- SetupLab (1.3.9, facultatif : SpotterEnginer ne dépend que d'AdvancedIA) : clé ac.store « SetupLab.state » écrite par
-- SetupLab (contrat v1 avec sa session, 12/11/2026), relue ici. Module pur.
--   v=1;kind=quali|race|none;ver=<vN|eN|->;fuel=<L>;fpl=<L>;stint=<n>;compound=<nom|->;phot=<AVG>,<AVD>,<ARG>,<ARD>;
--   tune=idle|running|ready;readyN=<n>;stamp=<s>;pitc=<nom|->;stops=<n>;tlap=<n>;tdl=<s|->;tv=better|worse|same|wait|-;
--   tch=<groupe|->;tid=<n>;sess=<indice de séance>
-- 240 octets au plus ; -1 pour un nombre inconnu, « - » pour un nom inconnu ; champs futurs ajoutés en fin de texte.
-- Réécrite seulement quand une valeur change (sess compris : la clé change avec la séance), jamais effacée. Un champ
-- illisible vaut inconnu (nil) ; seuls v, kind et tune sont exigés.
-- Acceptée (live) : sess égal à la séance en cours ; sans sess (SetupLab plus ancien), seulement après un changement du
-- texte vu dans la séance (comme les clés d'AdvancedIA, src/side.lua). Les déclencheurs (tid, readyN) ne montent que
-- sur un changement vu sous nos yeux : le texte trouvé au départ n'en déclenche jamais.
local M={}
M.key='SetupLab.state'
-- Relecture (s) : SetupLab recompose la clé au plus une fois par seconde.
M.EVERY=0.5
M.MAX=240
local KIND={quali=true,race=true,none=true}
local TUNE={idle=true,running=true,ready=true}
local VERDICT={better=true,worse=true,same=true,wait=true}
-- Groupes de réglages connus (tch : groupe qui porte le plus gros gain prévu de l'essai, jamais une cause mesurée).
M.groups={aero='setupAero',springs='setupSprings',dampers='setupDampers',arb='setupArb',height='setupHeight',
 alignment='setupAlignment',pressure='setupPressure',diff='setupDiff',brakes='setupBrakes',gears='setupGears',fuel='setupFuel'}
-- Nombre fini, ou nil (« - », -1 pour les valeurs positives, illisible).
local function num(v,positive)
 local n=tonumber(v)
 if not n or n~=n or n==math.huge or n==-math.huge then return nil end
 if positive and n<0 then return nil end
 return n
end
local function int(v,positive) local n=num(v,positive); return n and math.floor(n+0.5) or nil end
local function name(v) return type(v)=='string' and v~='' and v~='-' and v or nil end
function M.parse(text)
 if type(text)~='string' or #text>M.MAX then return nil end
 local raw={}
 for k,v in text:gmatch('([%w]+)=([^;]*)') do raw[k]=v end
 if raw.v~='1' or not KIND[raw.kind] or not TUNE[raw.tune] then return nil end
 local out={kind=raw.kind,tune=raw.tune,ver=name(raw.ver),compound=name(raw.compound),pitc=name(raw.pitc),
  fuel=num(raw.fuel,true),fpl=num(raw.fpl,true),stint=int(raw.stint,true),stops=int(raw.stops,true),readyN=int(raw.readyN,true),
  tlap=int(raw.tlap,true),tdl=num(raw.tdl),tv=VERDICT[raw.tv] and raw.tv or nil,tch=M.groups[raw.tch] and raw.tch or nil,
  tid=int(raw.tid,true),sess=int(raw.sess)}
 if raw.phot then
  local p={}
  for x in raw.phot:gmatch('[^,]+') do p[#p+1]=num(x,true) or false end
  if #p==4 and p[1] and p[2] and p[3] and p[4] then out.phot=p end
 end
 return out
end
function M.new() return {readAt=-1e9,now=0,session=nil} end
-- Nouvelle séance (ou rechargement) : le texte présent redevient la référence ; acceptée tout de suite si son sess est
-- celui de la séance.
function M.reset(s,session) s.seen=nil; s.value=nil; s.live=false; s.last=nil; s.tidUp=false; s.readyUp=false; s.readAt=-1e9; s.session=session end
-- Un texte lu (chaîne, nombre ou nil) dans la séance session.
function M.feed(s,text,now,session)
 if type(text)~='string' then text=nil end
 if session~=s.session then M.reset(s,session) end
 local first=s.seen==nil
 if not first and text==(s.seen or nil) then return end
 s.seen=text or false
 local v=M.parse(text)
 if not v then return end
 local prev=s.last
 s.last=v
 -- Hausse des compteurs vue dans la séance (jamais sur le texte trouvé au départ) : gardée jusqu'à M.take.
 if not first and prev then
  if v.tid and prev.tid and v.tid>prev.tid then s.tidUp=true end
  if v.readyN and prev.readyN and v.readyN>prev.readyN then s.readyUp=true end
 end
 if v.sess~=nil then s.live=v.sess==session elseif not first then s.live=true end
 if s.live then s.value=v; s.at=now else s.value=nil end
end
-- À chaque image : relecture toutes les EVERY s (read(key) -> texte).
function M.step(s,read,now,session)
 s.now=now
 if now-s.readAt<M.EVERY and now>=s.readAt and session==s.session then return end
 s.readAt=now
 M.feed(s,read(M.key),now,session)
end
-- Valeur acceptée dans la séance, ou nil.
function M.get(s) return s and s.live and s.value or nil end
-- Hausses de tid et de readyN depuis le dernier appel (remises à faux).
function M.take(s)
 if not s then return false,false end
 local a,b=s.tidUp and s.live,s.readyUp and s.live
 s.tidUp=false; s.readyUp=false
 return a,b
end
-- Consommation par tour prévue par SetupLab (setup de course, clé acceptée), ou nil.
function M.fuelPerLap(s)
 local v=M.get(s)
 return v and v.kind=='race' and v.fpl and v.fpl>0 and v.fpl or nil
end
-- SetupLab installé : manifeste apps/lua/SetupLab/manifest.ini avec une ligne NAME=SetupLab exactement (les fenêtres
-- « SetupLab Debug », « Overlay », « Track » ont leur propre ligne NAME). text : contenu du manifeste ou nil.
function M.installed(text)
 if type(text)~='string' then return false end
 for line in text:gmatch('[^\r\n]+') do if line:match('^%s*NAME%s*=%s*SetupLab%s*$') then return true end end
 return false
end
return M
