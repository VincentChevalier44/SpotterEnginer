-- Clés annexes d'AdvancedIA (1.3.5 ; AdvancedIA Beta 1.61, réglages « nuance des classes » et « météo en direct »,
-- coupés par défaut) : textes courts écrits par AdvancedIA avec ac.store, relus ici. Module pur.
--   AdvancedIA.traffic : v=1;blue=none|lap|class;stage=none|advise|order;car=<indice d'AC|-1>;gap=<m>;closing=<km/h>;
--                        count=<n>;stamp=<s>
--   AdvancedIA.weather : v=1;wet=..;rain=..;water=..;trend=wetting|steady|drying;eta=<s|-1>;next=dry|inter|wet|none;
--                        forecast=none|light|rain|heavy|unknown;forecastIn=<s|-1>;aiDry=<n>;aiRain=<n>;stamp=<s>
-- Ni l'une ni l'autre n'est effacée quand son réglage est coupé (le dernier texte reste, d'une séance à l'autre)
-- et leur stamp suit l'horloge d'AdvancedIA (jamais comparée à la nôtre). D'où la règle : le texte trouvé au
-- chargement ou à une nouvelle séance est la référence, jamais utilisée ; une clé ne compte (live) qu'une fois son texte
-- changé sous nos yeux dans la séance (le réglage tourne). at : instant (horloge de l'app) du dernier changement ;
-- M.age : depuis combien de temps le texte n'a plus changé (une clé figée, réglage coupé en cours de séance, vieillit).
local M={}
M.keys={traffic='AdvancedIA.traffic',weather='AdvancedIA.weather'}
-- Relecture des clés (s) : AdvancedIA les écrit au plus une fois par seconde.
M.EVERY=0.5
-- Dernier texte quand un réglage est coupé (contrat figé de la Beta 1.61) : traffic blue=none, weather trend=off et
-- next=none : rien à dire.
-- Champs attendus (type) ; un champ absent ou illisible rend la clé illisible ; les champs inconnus sont ignorés.
local SPEC={
 traffic={blue={none=true,lap=true,class=true},stage={none=true,advise=true,order=true},car='int',gap='num',closing='num',count='int'},
 weather={trend={wetting=true,steady=true,drying=true,off=true},eta='num',next={dry=true,inter=true,wet=true,none=true},
  forecast={none=true,light=true,rain=true,heavy=true,unknown=true},forecastIn='num',rain='num',wet='num'}}
-- Texte d'une clé -> table de ses champs, ou nil (autre version, champ manquant ou hors des valeurs connues).
function M.parse(kind,text)
 if type(text)~='string' or #text>200 then return nil end
 local raw={}
 for k,v in text:gmatch('([%w]+)=([^;]*)') do raw[k]=v end
 if raw.v~='1' then return nil end
 local out={}
 for k,want in pairs(SPEC[kind]) do
  local v=raw[k]
  if v==nil then return nil end
  if type(want)=='table' then
   if not want[v] then return nil end
   out[k]=v
  else
   local n=tonumber(v)
   if not n or n~=n or n==math.huge or n==-math.huge then return nil end
   out[k]=want=='int' and math.floor(n+0.5) or n
  end
 end
 return out
end
function M.new() return {traffic={},weather={},readAt=-1e9,now=0} end
-- Nouvelle séance (ou rechargement) : le texte présent redevient la référence.
function M.reset(s) s.traffic={}; s.weather={}; s.readAt=-1e9 end
-- Un texte lu (chaîne, nombre ou nil) pour une clé.
function M.feed(s,kind,text,now)
 local k=s[kind]
 if type(text)~='string' then text=nil end
 if k.seen==nil then k.seen=text or false; return end
 if text==(k.seen or nil) then return end
 k.seen=text or false
 local v=M.parse(kind,text)
 if v then k.value=v; k.live=true; k.at=now end
end
-- À chaque image : relecture toutes les EVERY s (read(key) -> texte), horloge de l'app (now).
function M.step(s,read,now)
 s.now=now
 if now-s.readAt<M.EVERY and now>=s.readAt then return end
 s.readAt=now
 for kind,key in pairs(M.keys) do M.feed(s,kind,read(key),now) end
end
-- Valeur d'une clé qui tourne dans la séance, ou nil.
function M.get(s,kind) local k=s and s[kind]; return k and k.live and k.value or nil end
-- Âge (s, horloge de M.step) de la valeur d'une clé qui tourne, ou nil.
function M.age(s,kind) local k=s and s[kind]; return k and k.live and k.at and math.max(0,(s.now or 0)-k.at) or nil end
return M
