-- Phrases de la radio : suite de clips du catalogue et de nombres, rendue en chemins de fichiers (si tous existent) et
-- en texte (toujours, pour la radio de l'overlay). Module pur : la liste des fichiers présents est donnée par le port.
--   parts : { 'gapAhead', {n=1.24,dec=1,unit='s'} }  ->  « Écart devant : 1,2 seconde » (deux clips)
--           { {pos=7}, 'posReach' }                      ->  « Tu es P7. Il est à portée… » (deux clips)
-- La phrase est d'abord développée en atomes (clips, nombres entiers, virgule, durées groupées, positions, textes
-- écrits seulement) ; les chemins et le texte viennent des mêmes atomes : ce qui est écrit est ce qui est dit.
local Catalog=require('src/catalog')
local Voice=require('src/voice')
local M={}
-- voice : file de la radio ; files : ensemble des chemins relatifs présents (« FR/01_vert.wav ») ; root : dossier vox.
-- Le signal d'ouverture (s.chirp) est réglé par l'app (réglage « Signal radio »).
function M.new(voice,files,root,lang)
 return {voice=voice,files=files or {},root=root or '',lang=lang=='EN' and 'EN' or 'FR',chirp=nil}
end
function M.setLanguage(s,lang) s.lang=lang=='EN' and 'EN' or 'FR' end
function M.mark(s) return s.lang=='FR' and ',' or '.' end
-- Précision écrite seulement (Catalog.notes), dans la langue de la radio.
function M.note(s,id,...) return string.format(Catalog.notes[id][s.lang],...) end
-- Accord de l'unité avec la valeur dite : singulier sous 2 en français (« 1,5 tour »), pour 1 seulement en anglais.
local function singular(lang,v) if lang=='FR' then return v<2 end return v==1 end
M.singular=singular
-- Unités accordées (clip au pluriel -> clip au singulier) quand elles suivent un nombre.
local SINGULAR={laps='lapOne',seconds='secondOne'}
-- Nombre en atomes : signe, entier (0 à Catalog.maxNumber, plus grand : écrit seulement), virgule et chiffres des
-- décimales (zéros de fin retirés : « 1 », jamais « 1,0 »). Renvoie la valeur dite.
local function numberParts(out,value,dec)
 local negative=value<0; value=math.abs(value)
 dec=dec or 0
 local scale=10^dec
 local rounded=math.floor(value*scale+0.5)
 local whole=math.floor(rounded/scale)
 local frac=rounded-whole*scale
 if negative and rounded>0 then out[#out+1]='minus' end
 out[#out+1]={int=whole}
 if dec>0 and frac>0 then
  out[#out+1]='point'
  local digits=string.format('%0'..dec..'d',frac):gsub('0+$','')
  for ch in digits:gmatch('%d') do out[#out+1]={int=tonumber(ch),digit=true} end
 end
 return rounded/scale
end
-- Durée en secondes ({n, dec, unit='s'}) : jusqu'à Catalog.maxTenths dixièmes, nombre et unité en un seul clip
-- (« 9,3 secondes », dixièmes arrondis ; « 1,5 seconde » au singulier en français) ; au-delà, arrondie à la seconde
-- (« 12 secondes »). Renvoie la valeur dite et les dixièmes (nil : pas de clip groupé).
local function secondsValue(value,dec)
 value=math.abs(value); dec=dec or 0
 if dec<=1 then
  local tenths=dec>=1 and math.floor(value*10+0.5) or math.floor(value+0.5)*10
  if tenths<=Catalog.maxTenths then return tenths/10,tenths end
 end
 return math.floor(value+0.5),nil
end
-- Atomes d'une phrase ; joined=false : durées lues chiffre par chiffre (clips groupés absents). Avec 2 décimales
-- demandées sous 10 s, la durée est toujours lue chiffre par chiffre.
function M.expand(s,parts,joined)
 local out={}
 local last=nil -- valeur du dernier nombre dit (accord de l'unité qui le suit)
 for k=1,#parts do
  local p=parts[k]
  if type(p)=='table' and p.n~=nil and p.unit=='s' then
   local v,tenths=secondsValue(p.n,p.dec)
   if tenths and joined~=false then out[#out+1]={sec=tenths}
   else
    if (p.dec or 0)>=2 and math.abs(p.n)<=Catalog.maxTenths/10 then v=numberParts(out,math.abs(p.n),p.dec)
    else v=numberParts(out,v,tenths and 1 or 0) end
    out[#out+1]=singular(s.lang,v) and 'secondOne' or 'seconds'
   end
   last=nil
  elseif type(p)=='table' and p.n~=nil then last=numberParts(out,p.n,p.dec)
  elseif type(p)=='string' and last and SINGULAR[p] then out[#out+1]=singular(s.lang,last) and SINGULAR[p] or p; last=nil
  else out[#out+1]=p; last=nil end
 end
 return out
end
local function relative(s,p)
 if type(p)=='table' then
  if p.sec then return s.lang..'/'..Catalog.secondsFile(p.sec) end
  if p.pos then return p.pos>=1 and p.pos<=Catalog.maxPosition and s.lang..'/'..Catalog.positionFile(p.pos) or nil end
  if p.int then return p.int<=Catalog.maxNumber and s.lang..'/'..Catalog.numberFile(p.int) or nil end
  return nil
 end
 local c=Catalog.clips[p]
 return c and s.lang..'/'..c[s.lang] or nil
end
-- Chemins des clips des atomes (textes écrits seulement ignorés), ou nil si l'un manque.
function M.paths(s,atoms)
 local list={}
 for k=1,#atoms do
  local a=atoms[k]
  if not (type(a)=='table' and a.text) then
   local rel=relative(s,a)
   if not rel or not s.files[rel] then return nil end
   list[#list+1]=s.root..'/'..rel
  end
 end
 return list
end
-- Majuscule en tête (ASCII ou lettre latine accentuée en UTF-8 : À à Þ).
local function capital(text)
 local a,b=text:byte(1,2)
 return a and (a>=65 and a<=90 or a==195 and b and b>=128 and b<=158) or false
end
-- Texte des atomes : nombres en chiffres (séparateur décimal de la langue), durées et positions comme leurs clips.
-- Une phrase du catalogue qui commence par une majuscule après un clip, un nombre ou une position sans ponctuation de
-- fin reçoit un point (« 1,2 seconde. Tu reviens. ») ; jamais après un texte écrit seulement (nom d'un pilote).
local function textOf(s,atoms)
 local words={}
 local open=false   -- dernier mot : nombre en cours (virgule et chiffres collés)
 local spoken=false -- dernier mot : clip, nombre ou position (pas un texte écrit seulement)
 local function add(word,isSpoken)
  if spoken and capital(word) and #words>0 and not words[#words]:find('[%.!?:;]$') then words[#words]=words[#words]..'.' end
  words[#words+1]=word; spoken=isSpoken; open=false
 end
 for k=1,#atoms do
  local a=atoms[k]
  if a=='point' then words[#words]=(words[#words] or '0')..M.mark(s); open=true
  elseif type(a)=='table' and a.int then
   if open and a.digit then words[#words]=words[#words]..a.int else add(tostring(a.int),true); open=true end
  elseif type(a)=='table' and a.sec then add(M.secondsText(s.lang,a.sec/10,a.sec%10~=0 and 1 or 0),true)
  elseif type(a)=='table' and a.pos then add(Catalog.positionText(s.lang,a.pos),true)
  elseif type(a)=='table' and a.text then add(a.text,false)
  else
   local c=Catalog.clips[a]
   if c then add(s.lang=='FR' and c.textFR or c.textEN,true) end
  end
 end
 -- Espace retirée devant un point ou une virgule seulement (« : » garde l'espace de la typographie française).
 return (table.concat(words,' '):gsub(' ([%.,])','%1'))
end
function M.text(s,parts) return textOf(s,M.expand(s,parts)) end
-- Durée écrite, comme le clip (« 1,5 seconde », « 9,3 secondes », « 1 second », « 0.8 seconds »).
function M.secondsText(lang,v,dec)
 local num=string.format('%.'..dec..'f',v)
 if lang=='FR' then num=num:gsub('%.',',') end
 return num..(singular(lang,v) and (lang=='FR' and ' seconde' or ' second') or (lang=='FR' and ' secondes' or ' seconds'))
end
-- Annonce : role 'spotter' ou 'engineer', key (dédoublonnage), prio 1..5, parts, opts {ttl, cooldown, text, kind, once,
-- fresh}. once : annonce d'un instant, jamais redite si une annonce plus urgente la coupe ; fresh : un état nouveau,
-- jamais écarté comme une redite (position). Une partie {text='…'} est écrite seulement (nom d'un pilote) : l'annonce
-- reste dite sans elle.
function M.say(s,role,key,prio,parts,now,opts)
 opts=opts or {}
 if M.strict then for k=1,#parts do local p=parts[k]; if type(p)=='string' and not Catalog.clips[p] then error('clip inconnu : '..p,2) end end end
 -- Clips groupés (« 9,3 secondes ») d'abord ; s'il en manque, la durée est lue chiffre par chiffre.
 local atoms=M.expand(s,parts)
 local clips=M.paths(s,atoms)
 if not clips then
  local digits=M.expand(s,parts,false)
  clips=M.paths(s,digits)
  if clips then atoms=digits end
 end
 return Voice.say(s.voice,{key=key,role=role,prio=prio,clips=clips,text=opts.text or textOf(s,atoms),ttl=opts.ttl or Voice.TTL,
  cooldown=opts.cooldown or 0,kind=opts.kind,chirp=s.chirp,once=opts.once,fresh=opts.fresh},now)
end
return M
