-- SuperHUD (1.3.9, facultatif : SpotterEnginer ne dépend que d'AdvancedIA) : clé ac.store « SuperHUD.state » écrite par
-- SuperHUD 1.9.6 et plus (contrat v1 avec sa session, 13/11/2026), relue ici. Module pur.
--   v=1;desk=<bureau CSP 1-4>;sw=<largeur écran px>;sh=<hauteur px>;radar=0|1;stamp=<s>;rects=<x>,<y>,<w>,<h>/...
-- 1000 octets au plus ; champs futurs ajoutés en fin de texte ; champ illisible : inconnu.
-- rects : blocs dessinés sur le bureau actif (pixels écran entiers, coin haut gauche), vide si aucun (HUD masqué,
-- rediffusion, stands, bureau illisible). radar=1 : alertes sonores du radar de SuperHUD actives (réglage, bloc Radar
-- et ses avertissements, HUD affiché). stamp : temps réel de SuperHUD (s entières), réécrit chaque seconde même sans
-- changement ; dernière écriture au déchargement (radar=0, rects vide). La clé n'est jamais effacée : vivante
-- seulement si son texte a changé depuis moins de M.STALE s (le texte trouvé au départ ne compte pas).
local M={}
M.key='SuperHUD.state'
M.EVERY=0.5
M.STALE=3
M.MAX=1000
-- Blocs gardés en mémoire après leur dernière apparition (s) : un bloc masqué un moment (radar sans voiture, dégâts)
-- garde sa place, les overlays ne sautent pas à chaque apparition.
M.KEEP=120
local function int(v) local n=tonumber(v); if not n or n~=n or n==math.huge or n==-math.huge then return nil end return math.floor(n+0.5) end
function M.parse(text)
 if type(text)~='string' or #text>M.MAX then return nil end
 local raw={}
 for k,v in text:gmatch('([%w]+)=([^;]*)') do raw[k]=v end
 if raw.v~='1' then return nil end
 local out={desk=int(raw.desk),sw=int(raw.sw),sh=int(raw.sh),radar=raw.radar=='1',stamp=int(raw.stamp),rects={}}
 if out.desk and (out.desk<1 or out.desk>4) then out.desk=nil end
 if out.sw and out.sw<=0 then out.sw=nil end
 if out.sh and out.sh<=0 then out.sh=nil end
 for r in (raw.rects or ''):gmatch('[^/]+') do
  local x,y,w,h=r:match('^%s*(%-?[%d%.]+),(%-?[%d%.]+),([%d%.]+),([%d%.]+)%s*$')
  x,y,w,h=int(x),int(y),int(w),int(h)
  if x and y and w and h and w>0 and h>0 then out.rects[#out.rects+1]={x=x,y=y,w=w,h=h} end
 end
 return out
end
function M.new() return {readAt=-1e9,seen=nil,value=nil,changedAt=nil,blocks={}} end
-- Texte lu (chaîne, nombre ou nil) à l'instant now (temps réel de SpotterEnginer).
function M.feed(s,text,now)
 if type(text)~='string' then text=nil end
 local first=s.seen==nil
 if not first and text==(s.seen or nil) then return end
 s.seen=text or false
 s.value=M.parse(text)
 -- Vivante seulement après un changement vu sous nos yeux (le texte du départ peut venir d'un SuperHUD déchargé).
 if not first and s.value then s.changedAt=now end
end
function M.step(s,read,now)
 if now-s.readAt<M.EVERY and now>=s.readAt then return end
 s.readAt=now
 M.feed(s,read(M.key),now)
end
-- Valeur d'un SuperHUD qui tourne, ou nil.
function M.get(s,now)
 if not s or not s.value or not s.changedAt then return nil end
 if now-s.changedAt>M.STALE or now<s.changedAt then return nil end
 return s.value
end
-- Alertes sonores du radar de SuperHUD actives.
function M.radar(s,now) local v=M.get(s,now); return v~=nil and v.radar==true end
-- Blocs de SuperHUD à éviter sur le bureau desk (écran sw x sh) : ceux affichés maintenant et ceux vus depuis moins de
-- M.KEEP s sur ce bureau, ramenés à notre écran si SuperHUD en donne une autre taille.
function M.blocks(s,now,desk,sw,sh)
 local v=M.get(s,now)
 if not v then return {} end
 -- Bureau illisible chez SuperHUD (desk=0 : il suspend ses blocs) ou autre bureau : rien à éviter.
 if not v.desk or desk and v.desk~=desk then return {} end
 local fx=(v.sw and sw) and sw/v.sw or 1
 local fy=(v.sh and sh) and sh/v.sh or 1
 local mem=s.blocks[desk or 0]
 if not mem then mem={}; s.blocks[desk or 0]=mem end
 for _,r in ipairs(v.rects) do
  local k=r.x..','..r.y..','..r.w..','..r.h
  mem[k]={x=r.x*fx,y=r.y*fy,w=r.w*fx,h=r.h*fy,at=now}
 end
 local out={}
 for k,r in pairs(mem) do
  if now-r.at>M.KEEP or now<r.at then mem[k]=nil else out[#out+1]=r end
 end
 table.sort(out,function(a,b) if a.y~=b.y then return a.y<b.y end return a.x<b.x end)
 return out
end
local GAP=8
local function hits(x,y,w,h,list)
 for _,r in ipairs(list) do
  if x<r.x+r.w and r.x<x+w and y<r.y+r.h and r.y<y+h then return true end
 end
 return false
end
-- Position libre la plus proche de (x, y) en restant dans la même colonne (décalage vertical seulement) ; sans place
-- libre à l'écran, la position d'origine.
function M.avoid(x,y,w,h,list,sh)
 if #list==0 or not hits(x,y,w,h,list) then return x,y end
 local best,dist=nil,math.huge
 local function try(cy)
  if cy<0 or cy+h>sh then return end
  if not hits(x,cy,w,h,list) and math.abs(cy-y)<dist then best=cy; dist=math.abs(cy-y) end
 end
 for _,r in ipairs(list) do try(r.y+r.h+GAP); try(r.y-h-GAP) end
 if best then return x,best end
 return x,y
end
-- SuperHUD installé : manifeste apps/lua/SuperHUD/manifest.ini avec une ligne NAME = SuperHUD exactement (la fenêtre
-- « SuperHUD - Configuration FR » a sa propre ligne NAME).
function M.installed(text)
 if type(text)~='string' then return false end
 for line in text:gmatch('[^\r\n]+') do if line:match('^%s*NAME%s*=%s*SuperHUD%s*$') then return true end end
 return false
end
return M
