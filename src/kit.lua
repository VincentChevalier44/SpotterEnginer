-- Kit de dessin « Racing 26 » (repris d'AdvancedIA src/widgets.lua, même système que SetupLab et SuperHUD) : fond
-- quasi noir, panneaux anthracite à coin coupé, accent d'action pervenche (couleur du casque de l'app) ; boutons en parallélogramme, interrupteurs, puces,
-- segments, curseurs avec repère du défaut. Polices livrées (fonts/, OFL) : Barlow, Barlow Condensed, JetBrains Mono ;
-- sans elles, Segoe UI et Consolas. Canevas virtuel de W.minWidth px au minimum (réduit à l'échelle en dessous).
local W={}
-- active : dernier état allumé de chaque commande dessinée (surbrillance vérifiable).
local f={ox=0,oy=0,s=1,w=900,h=700,tip=nil,tipPriority=-1,fontDepth=0,clip=nil,id='spe',active={}}
W.minWidth=760
local function hex(h,a)
 local r,g,b=h:match('^#(%x%x)(%x%x)(%x%x)$')
 return rgbm(tonumber(r,16)/255,tonumber(g,16)/255,tonumber(b,16)/255,a or 1)
end
-- Jetons du kit (ai.css, Kit).
local palette
function W.colors()
 if not palette then
  palette={bg=hex('#0A0B0E'),panel=hex('#111318'),block=hex('#17191E'),blockHover=hex('#1C1F25'),blockActive=hex('#22262D'),
   control=hex('#1D2027'),controlHover=hex('#262A32'),controlActive=hex('#2E333C'),disabled=hex('#16181C'),disabledText=hex('#5C626C'),
   rule=hex('#2A2E36'),ruleSoft=hex('#1A1D23'),ruleHead=hex('#23272E'),ruleHover=hex('#3A404A'),rowAlt=hex('#14161A'),
   text=hex('#EEF0F3'),soft=hex('#C9CDD3'),body=hex('#DDE0E5'),label=hex('#8D94A0'),muted=hex('#9AA1AC'),group=hex('#6B7280'),off=hex('#7A818C'),
   -- Accent d'action de SpotterEnginer : pervenche du casque de l'app (logo), à la place du cyan d'AdvancedIA (même
   -- rôle, mêmes noms de jetons : chaque app du thème a la couleur de son casque, comme le sarcelle de SuperHUD).
   cyan=hex('#A09BFF'),cyanHover=hex('#B5B1FF'),cyanActive=hex('#8781F2'),cyanText=hex('#C4C1FF'),select=hex('#16143A'),selectHover=hex('#1D1A4A'),
   selectLine=hex('#37327A'),ink=hex('#100C2E'),outline=hex('#121028'),outlineHover=hex('#19163A'),outlineActive=hex('#0E0C20'),
   ok=hex('#2EE07F'),okBack=hex('#0E2A1B'),warn=hex('#FFC23D'),warnBack=hex('#2E2410'),warnSoft=hex('#E6C98A'),warnLine=hex('#5A4515'),
   danger=hex('#FF5A4E'),dangerHover=hex('#FF7A70'),dangerActive=hex('#E0463B'),dangerText=hex('#FF8A80'),dangerBack=hex('#2A1210'),
   dangerBackHover=hex('#3A1814'),dangerBackActive=hex('#22100E'),dangerLine=hex('#5A2320'),dangerInk=hex('#1A0503'),dangerChip=hex('#3A1614'),
   orange=hex('#FF9A4D'),orangeDot=hex('#FF7A1A'),orangeBack=hex('#2E1A0C'),neutralBack=hex('#1A1D23'),
   switchOff=hex('#2C3038'),switchOffHover=hex('#363B45'),knobOff=hex('#8D94A0'),knobDisabled=hex('#3F444D'),
   thumb=hex('#EEF0F3'),thumbHover=hex('#FFFFFF'),marker=hex('#5C626C'),
   flagYellow=hex('#FFD21F'),flagRed=hex('#E10A1E'),flagBlue=hex('#2F7BFF'),flagWhite=hex('#F2F3F5'),
   -- Beta 1.38 : violet du meilleur tour ; voile d'une section décochée (fond du panneau, contenu grisé à 42 %).
   best=hex('#B26CFF'),veil=hex('#111318',0.58),
   -- Nom de l'app dans l'en-tête : l'accent pervenche.
   brand=hex('#A09BFF')}
 end
 return W.current or palette
end
-- Opacité du contenu d'un overlay (comme SuperHUD) : palette copiée une fois par palier de 5 %, chaque couleur à
-- l'opacité voulue ; W.colors() la rend jusqu'à W.useAlpha(1). Les widgets du kit en profitent sans changement.
local alphaPalettes={}
function W.useAlpha(a)
 W.current=nil
 local base=W.colors()
 a=math.max(0,math.min(1,a or 1))
 if a>=0.999 then return base end
 local key=math.floor(a*20+0.5)
 local p=alphaPalettes[key]
 if not p then
  p={}
  for k,v in pairs(base) do p[k]=rgbm(v.r,v.g,v.b,(v.mult or 1)*key/20) end
  alphaPalettes[key]=p
 end
 W.current=p
 return p
end
-- Polices par rôle (comme SetupLab) : dossier relatif à l'app, ou Segoe UI / Consolas sans les fichiers.
local FAMILIES={
 body={'Barlow:%s/barlow;Weight=Regular','Segoe UI'},
 sb={'Barlow:%s/barlow;Weight=SemiBold','Segoe UI;Weight=SemiBold'},
 label={'Barlow Condensed:%s/barlowcondensed;Weight=SemiBold','Segoe UI;Weight=SemiBold'},
 cond={'Barlow Condensed:%s/barlowcondensed;Weight=Bold','Segoe UI;Weight=Bold'},
 display={'Barlow Condensed:%s/barlowcondensed;Weight=UltraBold;Style=Italic','Segoe UI;Weight=Bold;Style=Italic'},
 mono={'JetBrains Mono:%s/jetbrainsmono;Weight=Medium','Consolas'}}
local fonts={}
for role,pair in pairs(FAMILIES) do fonts[role]=pair[2] end
W.fontDir=nil
-- Mesures mémorisées (largeurs, découpes, coupes de lignes), par rôle de police, taille et largeur : vidées quand les
-- polices ou l'échelle changent.
local widths,cut,wrapped,tails={},{},{},{}
local cacheCount,cacheScale=0,nil
local function forget() widths={}; cut={}; wrapped={}; tails={}; cacheCount=0 end
-- dir : dossier des polices relatif à l'app (« fonts »), ou nil pour les polices du système.
function W.setFonts(dir)
 W.fontDir=dir
 for role,pair in pairs(FAMILIES) do fonts[role]=dir and pair[1]:format(dir) or pair[2] end
 f.fontRole=nil; f.fontName=nil; forget()
end
-- Police du rôle voulu, poussée seulement si elle change (une seule police poussée à la fois par le kit ; deux rôles
-- servis par la même police, comme avec les polices de secours, ne la repoussent pas).
local function use(role)
 if f.fontRole==role then return end
 local name=fonts[role] or fonts.body
 if f.fontName==name and f.fontDepth>0 then f.fontRole=role; return end
 if f.fontDepth>0 then ui.popDWriteFont(); f.fontDepth=f.fontDepth-1 end
 ui.pushDWriteFont(name); f.fontDepth=f.fontDepth+1; f.fontRole=role; f.fontName=name
end
local function release() while f.fontDepth>0 do ui.popDWriteFont(); f.fontDepth=f.fontDepth-1 end; f.fontRole=nil; f.fontName=nil end
-- Table d'un niveau de cache (créée une fois par clé).
local function level(t,k) local n=t[k]; if not n then n={}; t[k]=n end; return n end
-- Rôle d'un texte : nil = Barlow.
local function role(r) return r or 'body' end
-- Majuscules (text-transform: uppercase de la maquette), accents compris ; mémorisées.
local upperMap={['à']='À',['â']='Â',['ä']='Ä',['é']='É',['è']='È',['ê']='Ê',['ë']='Ë',['î']='Î',['ï']='Ï',['ô']='Ô',['ö']='Ö',['ù']='Ù',['û']='Û',['ü']='Ü',['ç']='Ç',['œ']='Œ',['æ']='Æ',['ÿ']='Ÿ'}
local uppers={}; local upperCount=0
function W.upper(str)
 local hit=uppers[str]
 if hit then return hit end
 -- Lettres ASCII seulement, puis accents par la table : string.upper suit la locale du processus (en cp1252, il
 -- changerait certains octets de suite UTF-8).
 local out=str:gsub('[a-z]',string.upper):gsub('[\195\197][\128-\191]',upperMap)
 upperCount=upperCount+1; if upperCount>1000 then uppers={}; upperCount=0 end
 uppers[str]=out
 return out
end
-- Points réutilisés (aucune table neuve par appel) : chaque appel de dessin consomme ses points aussitôt.
local pool={}; local poolAt=0
local function vec(x,y)
 poolAt=poolAt%24+1
 local p=pool[poolAt]
 if not p then p=vec2(x,y); pool[poolAt]=p else p.x=x; p.y=y end
 return p
end
function W.point(x,y) return vec(f.ox+x*f.s,f.oy+y*f.s) end
local point=W.point
-- Canevas : W.minWidth px virtuels au minimum (réduit en dessous, au plus de moitié), sinon la largeur de la fenêtre.
function W.begin(id)
 -- Restes d'une image interrompue : compteurs remis à zéro sans rien refermer (les piles de CSP sont celles de
 -- l'image précédente ; refermer ici dépilerait ce que cette image n'a pas poussé).
 f.fontDepth=0; f.fontRole=nil; f.fontName=nil; f.clip=nil
 local raw=ui.getCursor(); local space=ui.availableSpace()
 f.id=id; f.ox=raw.x; f.oy=raw.y
 f.s=math.max(0.5,math.min(1,space.x/W.minWidth))
 if cacheScale~=f.s then cacheScale=f.s; forget() end
 f.w=math.max(W.minWidth,space.x/f.s); f.h=math.max(400,space.y/f.s)
 f.tip=nil; f.tipPriority=-1; f.clip=nil
 -- Souris lue une fois par image (survols, infobulles, segments) : pas de vec2 par commande.
 local m=ui.mouseLocalPos(); f.mx=m.x; f.my=m.y
 ui.drawRectFilled(vec(raw.x,raw.y),vec(raw.x+space.x,raw.y+space.y),W.colors().bg,0)
 return f
end
-- Canevas d'un overlay : design de designW px de large, mis à l'échelle de la fenêtre (agrandi comme réduit), sans
-- fond opaque (l'overlay dessine ses propres panneaux). Les mesures de texte restent en unités du design : leur cache
-- n'est pas vidé à chaque overlay.
function W.beginOverlay(id,designW)
 f.fontDepth=0; f.fontRole=nil; f.fontName=nil; f.clip=nil
 local raw=ui.getCursor(); local space=ui.availableSpace()
 f.id=id; f.ox=raw.x; f.oy=raw.y
 f.s=math.max(0.3,space.x/designW)
 f.w=designW; f.h=space.y/f.s
 f.tip=nil; f.tipPriority=-1; f.clip=nil
 local m=ui.mouseLocalPos(); f.mx=m.x; f.my=m.y
 return f
end
function W.frame() return f end
function W.rect(x,y,w,h,col,r)
 if w>0 and h>0 then ui.drawRectFilled(point(x,y),point(x+w,y+h),col,(r or 0)*f.s) end
end
-- Cadre intérieur d'un pixel (box-shadow: inset 0 0 0 1px).
function W.frameRect(x,y,w,h,col,th)
 th=th or 1
 W.rect(x,y,w,th,col); W.rect(x,y+h-th,w,th,col); W.rect(x,y+th,th,h-2*th,col); W.rect(x+w-th,y+th,th,h-2*th,col)
end
function W.line(x,y,x2,y2,col,th) ui.drawLine(point(x,y),point(x2,y2),col,(th or 1)*f.s) end
function W.circle(x,y,r,col) ui.drawCircleFilled(point(x,y),r*f.s,col,20) end
local quadFilled=nil
local function canQuad()
 if quadFilled==nil then quadFilled=type(ui.drawQuadFilled)=='function' or (type(ui.drawQuadFilled)=='cdata') end
 return quadFilled
end
-- Quadrilatère plein (parallélogramme, onglet incliné) ; sans la fonction, rectangle englobant.
function W.quad(x1,y1,x2,y2,x3,y3,x4,y4,col)
 if canQuad() then
  local p1=point(x1,y1); local p2=point(x2,y2); local p3=point(x3,y3); local p4=point(x4,y4)
  ui.drawQuadFilled(p1,p2,p3,p4,col)
 else
  local l=math.min(x1,x4); local r=math.max(x2,x3)
  W.rect(l,math.min(y1,y2),r-l,math.max(y3,y4)-math.min(y1,y2),col)
 end
end
function W.tri(x1,y1,x2,y2,x3,y3,col)
 if type(ui.drawTriangleFilled)=='function' or type(ui.drawTriangleFilled)=='cdata' then
  local p1=point(x1,y1); local p2=point(x2,y2); local p3=point(x3,y3)
  ui.drawTriangleFilled(p1,p2,p3,col)
 end
end
-- Parallélogramme de bouton : pente de slant px (haut décalé à droite).
function W.para(x,y,w,h,col,slant)
 slant=slant or 7
 W.quad(x+slant,y,x+w,y,x+w-slant,y+h,x,y+h,col)
end
-- Panneau à coin coupé en haut à droite (cut px) : deux rectangles et un triangle.
function W.panel(x,y,w,h,col,cut)
 cut=cut or 10; col=col or W.colors().panel
 W.rect(x,y,w-cut,h,col); W.rect(x+w-cut,y+cut,cut,h-cut,col)
 W.tri(x+w-cut,y,x+w,y+cut,x+w-cut,y+cut,col)
end
-- Texte : rôle de police (body, sb, label, cond, display, mono ; true = sb).
function W.text(str,x,y,size,col,r)
 use(role(r))
 ui.dwriteDrawText(str,(size or 12)*f.s,point(x,y),col or W.colors().text)
end
local function count() cacheCount=cacheCount+1; if cacheCount>6000 then forget() end end
local function width(str,size,r)
 r=role(r)
 local t=level(level(widths,r),size)
 local hit=t[str]
 if hit then return hit end
 use(r); local v=ui.measureDWriteText(str,size*f.s).x/f.s
 count(); t[str]=v
 return v
end
W.width=width
-- Texte tronqué à la largeur donnée, terminé par « … » ; découpe mémorisée.
local function fitted(str,w,size,r)
 local t=level(level(level(cut,role(r)),size),w)
 local hit=t[str]
 if hit then return hit end
 local out=str
 if width(str,size,r)>w then
  local chars={}
  for ch in str:gmatch('[%z\1-\127\194-\244][\128-\191]*') do chars[#chars+1]=ch end
  local lo,hi=0,#chars
  while lo<hi do
   local mid=math.floor((lo+hi+1)/2)
   if width(table.concat(chars,'',1,mid)..'…',size,r)<=w then lo=mid else hi=mid-1 end
  end
  out=table.concat(chars,'',1,lo)..'…'
 end
 count(); t[str]=out
 return out
end
-- Dernière ligne montrée d'un paragraphe coupé (tuiles) : finie par « … », mémorisée.
local function tail(lines,n,w)
 local t=level(tails,lines); local hit=t[n]
 if hit then return hit end
 local out=fitted(lines[n]..' '..lines[n+1],w,12)
 if out:sub(-3)~='…' then out=fitted(lines[n]..'…',w,12) end
 count(); t[n]=out
 return out
end
-- Plus grande taille (de size à low) qui fait tenir le texte dans la largeur ; mémorisée comme les largeurs.
function W.shrink(str,w,size,low,r)
 while size>low and width(str,size,r)>w do size=size-1 end
 return size
end
function W.cell(str,x,y,w,size,col,r) W.text(fitted(str,w,size or 12,r),x,y,size,col,r) end
-- Texte aligné à droite (fin à x).
function W.right(str,x,y,size,col,r) W.text(str,x-width(str,size,r),y,size,col,r) end
-- Paragraphe coupé aux mots dans la largeur donnée ; renvoie la hauteur utilisée. Coupes mémorisées.
function W.lines(str,w,size,r)
 local t=level(level(level(wrapped,role(r)),size),w)
 local hit=t[str]
 if hit then return hit end
 local out={}
 for paragraph in (str..'\n'):gmatch('([^\n]*)\n') do
  local line=''
  -- Mots séparés par les seules espaces ASCII : selon la langue du système, %s compte aussi l'octet 0xA0, second
  -- octet de « à » en UTF-8, qui serait coupé en deux.
  for word in paragraph:gmatch('[^ \t]+') do
   local candidate=line=='' and word or line..' '..word
   if line~='' and width(candidate,size,r)>w then out[#out+1]=line; line=word else line=candidate end
  end
  out[#out+1]=line
 end
 count(); t[str]=out
 return out
end
local LINE=1.35
function W.paragraph(str,x,y,w,size,col,r)
 size=size or 12
 local list=W.lines(str,w,size,r)
 for i,line in ipairs(list) do W.text(line,x,y+(i-1)*size*LINE,size,col,r) end
 return #list*size*LINE
end
-- Aide au survol : la région la plus prioritaire sous la souris fournit l'infobulle de l'image.
local function inside(x,y,w,h)
 local mx,my=f.mx or 0,f.my or 0; local ax,ay=f.ox+x*f.s,f.oy+y*f.s; local bx,by=f.ox+(x+w)*f.s,f.oy+(y+h)*f.s
 if mx<ax or mx>=bx or my<ay or my>=by then return false end
 local c=f.clip
 if c then
  local cx,cy=f.ox+c[1]*f.s,f.oy+c[2]*f.s; local dx,dy=f.ox+(c[1]+c[3])*f.s,f.oy+(c[2]+c[4])*f.s
  if my<cy or my>=dy or mx<cx or mx>=dx then return false end
 end
 return true
end
function W.help(text,x,y,w,h,priority)
 if text and text~='' and inside(x,y,w,h) and (priority or 2)>=f.tipPriority then f.tip=text; f.tipPriority=priority or 2 end
end
-- Identifiant natif « ##spe_… » d'une commande, fait une fois par identifiant.
local hashed={}
local function hashId(id) local s=hashed[id]; if not s then s='##spe_'..id; hashed[id]=s end; return s end
-- Zone cliquable : bouton invisible natif (identifiant stable, clic gauche), survol, appui et clic droit.
local hitSize=nil
function W.hit(id,x,y,w,h)
 ui.setCursor(point(x,y))
 if not hitSize then hitSize=vec2(1,1) end
 hitSize.x=math.max(1,w*f.s); hitSize.y=math.max(1,h*f.s)
 local clicked=ui.invisibleButton(hashId(id),hitSize)
 local hovered=ui.itemHovered()
 return clicked==true,hovered==true,ui.itemActive()==true,hovered and ui.mouseClicked(1)==true
end
-- Abscisse de la souris en unités du canevas (choix d'une case d'un segment au clic).
function W.mouseX() return ((f.mx or ui.mouseLocalPos().x)-f.ox)/f.s end
-- Losange de réglage modifié (6 px, cyan).
function W.marker(x,y,col)
 col=col or W.colors().cyan
 W.quad(x+3,y,x+6,y+3,x+3,y+6,x,y+3,col)
end
-- Barre inclinée des titres de section (4 × 11, -18°).
local function bar(x,y,col) W.quad(x+3.6,y,x+7.6,y,x+4,y+11,x,y+11,col) end
-- En-tête de bloc (.h) : barre cyan, titre condensé gras 13 en capitales, texte de droite (au plus 60 % de la
-- largeur), filet bas ; le titre s'arrête avant le texte de droite.
function W.heading(label,x,y,w,right,rightRole,rightCol)
 local c=W.colors()
 bar(x,y+6,c.cyan)
 local rw=0
 if right and right~='' then
  local r=rightRole or 'label'
  rw=math.min(width(right,11,r),w*0.6)
  W.text(fitted(right,rw,11,r),x+w-rw,y+6,11,rightCol or c.label,r)
 end
 W.cell(W.upper(label),x+11,y+5,w-11-(rw>0 and rw+8 or 0),13,c.soft,'cond')
 W.rect(x,y+23,w,1,c.rule)
 return 24
end
-- Libellé (.lab) : condensé demi-gras 11 en capitales.
function W.label(str,x,y,col) W.text(W.upper(str),x,y,11,col or W.colors().label,'label') end
function W.labelWidth(str) return width(W.upper(str),11,'label') end
-- Titre de page (.title) : condensé extra-gras italique en capitales, tenu dans la largeur (taille réduite jusqu'à
-- low, puis coupé par « … ») ; renvoie la largeur dessinée.
function W.titleFit(str,x,y,w,size,low,col)
 local text=W.upper(str)
 local s=W.shrink(text,w,size,low,'display')
 W.cell(text,x,y+(size-s)*0.5,w,s,col or W.colors().text,'display')
 return math.min(width(text,s,'display'),w)
end
-- Styles de bouton : primary (cyan), outline, danger, resume (rouge plein), disabled ; défaut : contrôle gris, cyan si
-- allumé.
local styleCache=setmetatable({},{__mode='k'})
local function buttonStyle(style,active,hover,pressed)
 local c=W.colors()
 local styles=styleCache[c]
 if not styles then
  styles={primary={c.cyan,c.cyanHover,c.cyanActive,c.ink},default={c.control,c.controlHover,c.controlActive,c.text},
   outline={c.outline,c.outlineHover,c.outlineActive,c.cyanText,c.selectLine},danger={c.dangerBack,c.dangerBackHover,c.dangerBackActive,c.dangerText,c.dangerLine},
   resume={c.danger,c.dangerHover,c.dangerActive,c.dangerInk},disabled={c.disabled,c.disabled,c.disabled,c.disabledText}}
 end
 styleCache[c]=styles
 local s=styles[style] or (active and styles.primary) or styles.default
 return pressed and s[3] or hover and s[2] or s[1],s[4],s[5]
end
-- Bouton en parallélogramme (.b) : libellé condensé extra-gras italique en capitales, réduit s'il est trop long.
-- icon (Beta 1.38, facultatif) : 'warn', triangle d'alerte devant le libellé (bouton PANIQUE de la maquette).
function W.button(id,label,x,y,w,h,active,tip,style,icon)
 local clicked,hover,pressed,right=W.hit(id,x,y,w,h)
 f.active[id]=active==true
 if style=='disabled' then clicked=false end
 local fill,ink,edge=buttonStyle(style,active,hover,pressed)
 W.para(x,y,w,h,fill)
 if edge then W.para(x,y,w,1,edge,0.3); W.para(x,y+h-1,w,1,edge,0.3) end
 local text=W.upper(label)
 local size=h>=28 and 13 or 12
 size=W.shrink(text,w-18,size,9,'display')
 local iw=icon and 16 or 0
 local tw=math.min(width(text,size,'display'),w-18-iw)
 local tx=x+(w-tw-iw)/2+iw
 if icon then
  local ix,iy=tx-iw,y+(h-12)/2
  W.line(ix+6,iy+1.2,ix+11,iy+10.4,ink,1.6); W.line(ix+11,iy+10.4,ix+1,iy+10.4,ink,1.6); W.line(ix+1,iy+10.4,ix+6,iy+1.2,ink,1.6)
  W.line(ix+6,iy+5,ix+6,iy+7.6,ink,1.6)
 end
 W.text(fitted(text,w-18-iw,size,'display'),tx,y+(h-size*1.2)/2,size,ink,'display')
 W.help(tip,x,y,w,h,5)
 return clicked,right
end
-- Interrupteur (.sw, 30 × 16) : état allumé cyan, éteint gris, désactivé grisé.
-- Interrupteur grisé mais allumé (réglage toujours actif, Beta 1.37) : on et disabled vrais ensemble, bouton à droite.
function W.switchShape(x,y,on,hover,disabled)
 local c=W.colors()
 local track=disabled and c.control or on and (hover and c.cyanHover or c.cyan) or (hover and c.switchOffHover or c.switchOff)
 W.rect(x,y,30,16,track,8)
 W.circle(x+(on and 22 or 8),y+8,5,disabled and c.knobDisabled or on and c.ink or c.knobOff)
end
function W.switch(id,x,y,on,tip,disabled)
 local clicked,hover=W.hit(id,x-4,y-4,38,24)
 f.active[id]=on==true
 W.switchShape(x,y,on and not disabled,hover,disabled)
 W.help(tip,x-4,y-4,38,24,5)
 return clicked and not disabled
end
-- Ligne de réglage à interrupteur (.r, 28 px) : libellé à gauche, interrupteur à droite ; toute la ligne est cliquable.
-- Ligne d'interrupteur ; opts (facultatif, Beta 1.37) : swatch (couleur d'une pastille de 14 px devant le libellé),
-- note (deuxième ligne, discrète), forced (allumé et grisé : réglage toujours actif). Hauteur : W.toggleHeight(opts).
function W.toggleHeight(opts) return opts and opts.note and 42 or 28 end
function W.toggle(id,label,x,y,w,on,tip,disabled,modified,opts)
 local c=W.colors()
 local h=W.toggleHeight(opts)
 local clicked,hover,_,right=W.hit(id,x,y,w,h)
 f.active[id]=on==true
 if hover and not disabled then W.rect(x,y,w,h-1,c.block) end
 local lx=x+2
 if modified then W.marker(lx,y+11); lx=lx+12 end
 if opts and opts.swatch then W.rect(lx,y+7,14,14,opts.swatch); lx=lx+20 end
 W.cell(label,lx,y+7,w-48-(lx-x),12,disabled and not (opts and opts.forced) and c.label or c.body)
 if opts and opts.note then W.cell(opts.note,lx,y+24,w-48-(lx-x),11,c.label) end
 W.switchShape(x+w-32,y+6,opts and opts.forced or on and not disabled,hover,disabled)
 W.rect(x,y+h-1,w,1,c.ruleSoft)
 W.help(tip,x,y,w,h,5)
 return clicked and not disabled,right
end
-- Puces (.k) : C cyan plein, c cyan foncé, g vert, a ambre, r rouge, n neutre, o orange. Renvoie la largeur.
local chipCache=setmetatable({},{__mode='k'})
local function chipStyle(kind)
 local c=W.colors()
 local chipColors=chipCache[c]
 if not chipColors then chipColors={C={c.cyan,c.ink},c={c.select,c.cyanText},g={c.okBack,c.ok},a={c.warnBack,c.warn},r={c.dangerChip,c.dangerText},n={c.neutralBack,c.muted},o={c.orangeBack,c.orange}} end
 chipCache[c]=chipColors
 return chipColors[kind] or chipColors.n
end
function W.chipWidth(str) return width(W.upper(str),11,'cond')+10 end
function W.chip(str,x,y,kind)
 local s=chipStyle(kind); local text=W.upper(str); local w=width(text,11,'cond')+10
 W.rect(x,y,w,17,s[1]); W.text(text,x+5,y+2,11,s[2],'cond')
 return w
end
-- Puce d'état à point de couleur (en-tête, Beta 1.38) : point de 7 px puis le texte, aux couleurs de la puce.
function W.dotChipWidth(str) return width(W.upper(str),11,'cond')+22 end
function W.dotChip(str,x,y,kind)
 local s=chipStyle(kind); local text=W.upper(str); local w=width(text,11,'cond')+22
 W.rect(x,y,w,18,s[1]); W.circle(x+9.5,y+9,3.5,s[2]); W.text(text,x+16,y+2.5,11,s[2],'cond')
 return w
end
-- Segment (.seg) : cases égales, celle choisie en cyan. ids : un identifiant par case (profils, langues) ; sinon un seul
-- identifiant pour tout le segment : le clic choisit la case sous la souris, ou la suivante (clic sans souris).
-- Renvoie l'indice cliqué ou nil, puis le clic droit (segment à un seul identifiant).
-- Identifiants des cases d'un choix (« id_1 », « id_2 »…) : construits une fois par commande, jamais à chaque image.
local choiceCache={}
function W.choiceIds(id,n)
 local list=choiceCache[id]
 if not list then list={}; choiceCache[id]=list end
 for i=#list+1,n do list[i]=id..'_'..i end
 return list
end
function W.segment(id,labels,x,y,w,h,selected,tip,ids,tips)
 local c=W.colors(); local n=#labels; local cw=w/n
 W.rect(x,y,w,h,c.bg)
 local picked,right
 if ids then
  for i=1,n do
   local cx=x+(i-1)*cw
   local clicked,hover,pressed=W.hit(ids[i],cx,y,cw,h)
   f.active[ids[i]]=i==selected
   if i==selected then W.rect(cx,y,cw,h,c.cyan) elseif pressed then W.rect(cx,y,cw,h,c.controlHover) elseif hover then W.rect(cx,y,cw,h,c.control) end
   local text=W.upper(labels[i])
   local tw=math.min(width(text,11,'cond'),cw-6)
   W.text(fitted(text,cw-6,11,'cond'),cx+(cw-tw)/2,y+(h-13)/2,11,i==selected and c.ink or hover and c.text or c.muted,'cond')
   W.help(tips and tips[i] or tip,cx,y,cw,h,5)
   if clicked then picked=i end
  end
 else
  local clicked,hover,pressed,rightClick=W.hit(id,x,y,w,h)
  right=rightClick
  local mx=hover and W.mouseX() or nil
  local under=mx and math.floor((mx-x)/cw)+1 or 0
  for i=1,n do
   local cx=x+(i-1)*cw
   if i==selected then W.rect(cx,y,cw,h,c.cyan) elseif under==i then W.rect(cx,y,cw,h,pressed and c.controlHover or c.control) end
   local text=W.upper(labels[i])
   local tw=math.min(width(text,11,'cond'),cw-6)
   W.text(fitted(text,cw-6,11,'cond'),cx+(cw-tw)/2,y+(h-13)/2,11,i==selected and c.ink or under==i and c.text or c.muted,'cond')
  end
  W.help(tip,x,y,w,h,5)
  if clicked then
   local mxc=W.mouseX(); local at=math.floor((mxc-x)/cw)+1
   picked=(at>=1 and at<=n) and at or (selected or 0)%n+1
  end
 end
 local list=W.choiceIds(id,n)
 for i=1,n do f.active[list[i]]=i==selected end
 W.frameRect(x,y,w,h,c.rule)
 return picked,right
end
-- Tuile (.tile) : nom, puce à droite, description (la dernière ligne finie par « … » si elle ne tient pas) ; allumée
-- (cyan foncé, cadre cyan) quand choisie.
function W.tile(id,name,chip,chipKind,desc,x,y,w,h,pressed,tip)
 local c=W.colors()
 local clicked,hover,down=W.hit(id,x,y,w,h)
 f.active[id]=pressed==true
 local fill=pressed and (hover and c.selectHover or c.select) or down and c.blockActive or hover and c.blockHover or c.block
 W.rect(x,y,w,h,fill)
 if pressed then W.frameRect(x,y,w,h,c.cyan) end
 local cw=chip and chip~='' and W.chipWidth(chip) or 0
 W.cell(W.upper(name),x+10,y+8,w-20-cw-6,13,pressed and c.cyanText or c.text,'cond')
 if cw>0 then W.chip(chip,x+w-10-cw,y+7,pressed and 'C' or chipKind) end
 if desc and desc~='' then
  local lines=W.lines(desc,w-20,12)
  local n=math.min(#lines,math.max(1,math.floor((h-30)/16)))
  for i=1,n do W.text(i==n and n<#lines and tail(lines,n,w-20) or lines[i],x+10,y+26+(i-1)*16,12,c.muted) end
 end
 W.help(tip,x,y,w,h,5)
 return clicked
end
-- Ligne de la barre latérale (.nav, 28 px ; Beta 1.42 : h plus petit si la liste ne tient pas) : nom, nombre de réglages
-- modifiés, interrupteur de la section.
function W.nav(id,label,x,y,w,current,off,count,tip,h)
 local c=W.colors(); h=h or 28
 local clicked,hover=W.hit(id,x,y,w-44,h)
 f.active[id]=current==true
 if current then W.rect(x,y,w,h,c.select); W.rect(x,y,2,h,c.cyan) elseif hover then W.rect(x,y,w,h,c.block) end
 W.cell(label,x+10,y+math.floor((h-14)/2),w-90,12,current and c.cyanText or off and c.off or c.body,'sb')
 if count and count~='' then W.right(count,x+w-48,y+math.floor((h-12)/2),11,c.cyan,'mono') end
 W.help(tip,x,y,w-44,h,3)
 return clicked
end
-- Curseur (.sl) : rail 4 px, partie remplie pleine, repère gris du défaut, poignée en parallélogramme ; glisser pour
-- régler, la valeur est arrondie au pas. Renvoie la nouvelle valeur ou nil, puis le clic droit.
function W.slider(id,x,y,w,value,lo,hi,step,tip,default)
 local c=W.colors()
 local _,hover,active,right=W.hit(id,x,y-2,w,20)
 local result
 if active and ui.mouseDown(0) then
  local mx=W.mouseX()
  local t=math.max(0,math.min(1,(mx-x)/w))
  local v=lo+t*(hi-lo)
  if step and step>0 then v=lo+math.floor((v-lo)/step+0.5)*step end
  -- Extrémités atteintes exactement, même quand la plage n'est pas un multiple du pas.
  if t>=1 then v=hi elseif t<=0 then v=lo end
  v=math.max(lo,math.min(hi,v))
  if math.abs(v-value)>1e-9 then result=v end
 end
 local ratio=hi>lo and math.max(0,math.min(1,(value-lo)/(hi-lo))) or 0
 W.rect(x,y+6,w,4,c.rule)
 W.rect(x,y+6,w*ratio,4,(hover or active) and c.cyanHover or c.cyan)
 if default and hi>lo then local d=math.max(0,math.min(1,(default-lo)/(hi-lo))); W.rect(x+w*d-1,y+2,2,12,c.marker) end
 local tx=x+w*ratio
 W.para(tx-5,y,10,16,active and c.cyan or hover and c.thumbHover or c.thumb,3)
 W.help(tip,x,y-2,w,20,5)
 return result,right
end
-- Message (.msg) : losange de couleur et texte coupé ; kinds ok, er, wn, mut, gr, wo. Renvoie la hauteur.
local msgCache=setmetatable({},{__mode='k'})
function W.message(str,x,y,w,kind,size)
 local c=W.colors()
 local msgColors=msgCache[c]
 if not msgColors then msgColors={ok={c.cyanText,c.cyan},er={c.dangerText,c.danger},wn={c.warn,c.warn},mut={c.muted,c.marker},gr={c.ok,c.ok},wo={c.orange,c.orangeDot}} end
 msgCache[c]=msgColors
 local s=msgColors[kind] or msgColors.mut
 size=size or 12
 W.quad(x+3,y+4,x+6,y+7,x+3,y+10,x,y+7,s[2])
 return W.paragraph(str,x+13,y,w-13,size,s[1])
end
-- Zone qui défile : contenu dessiné entre y et y+h, décalé de offset ; la molette au-dessus la fait défiler. Rail de
-- 4 px à droite, poignée plus claire au survol, visible seulement si le contenu dépasse. Beta 1.38 : rail saisissable
-- (bande de 6 px, seulement quand le contenu dépasse) : glisser déplace la poignée, cyan pendant le glisser.
local scrollIds={}
function W.scroll(state,key,x,y,w,h,content)
 local offset=state[key] or 0
 local maximum=math.max(0,content-h)
 local over=inside(x,y,w,h)
 if over then
  local wheel=ui.mouseWheel()
  if wheel~=0 then offset=offset-wheel*60 end
 end
 local dragging=false
 if maximum>0 then
  local thumb=math.max(30,h*h/content)
  local id=scrollIds[key]; if not id then id='scroll_'..tostring(key); scrollIds[key]=id end
  local _,_,pressed=W.hit(id,x+w-6,y,6,h)
  if pressed and ui.mouseDelta then
   local d=ui.mouseDelta(); dragging=true
   offset=offset+(d and d.y or 0)/f.s*maximum/math.max(1,h-thumb)
  end
 end
 offset=math.max(0,math.min(maximum,offset)); state[key]=offset
 if maximum>0 then
  local c=W.colors(); local thumb=math.max(30,h*h/content)
  W.rect(x+w-4,y,4,h,c.block); W.rect(x+w-4,y+(h-thumb)*offset/maximum,4,thumb,dragging and c.cyan or over and c.marker or c.ruleHover)
 end
 return offset
end
-- Zone de découpe : sa table est gardée (Beta 1.36 : aucune table créée par découpe).
function W.clip(x,y,w,h)
 if x then
  ui.pushClipRect(point(x,y),point(x+w,y+h),true)
  local c=f.clipBox; if not c then c={}; f.clipBox=c end
  c[1]=x; c[2]=y; c[3]=w; c[4]=h; f.clip=c
 else ui.popClipRect(); f.clip=nil end
end
function W.visible(y,h)
 local c=f.clip
 return not c or y>=c[2] and y+h<=c[2]+c[4]
end
-- Infobulle native aux couleurs du kit quand CSP les expose.
local tipStyle=nil
local function tipColors()
 if tipStyle==nil then
  tipStyle=false
  local sc=ui.StyleColor
  if type(sc)=='table' and sc.PopupBg and sc.Border and sc.Text and (type(ui.pushStyleColor)=='function' or type(ui.pushStyleColor)=='cdata') then
   local c=W.colors(); tipStyle={{sc.PopupBg,c.control},{sc.Border,c.ruleHover},{sc.Text,c.body}}
  end
 end
 return tipStyle
end
-- Fin d'image : polices et découpes refermées, infobulle unique, curseur placé sous le canevas.
function W.finish()
 release()
 if f.clip then W.clip() end
 if f.tip then
  local s=tipColors()
  if s then for _,item in ipairs(s) do ui.pushStyleColor(item[1],item[2]) end end
  ui.setTooltip(f.tip)
  if s then ui.popStyleColor(#s) end
 end
 ui.setCursor(point(0,0))
end
return W
