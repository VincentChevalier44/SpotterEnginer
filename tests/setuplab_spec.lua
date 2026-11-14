-- SetupLab (1.3.9, app facultative) : lecture de la clé SetupLab.state (exemples du contrat, vérifiés par le test CP08
-- de SetupLab), acceptation par séance, verdicts des tours d'essai dits par l'ingénieur, section cachée sans SetupLab.
local SetupLab=require('src/setuplab')
local Engineer=require('src/engineer')
local St=require('src/strategist')
local Voice=require('src/voice')
local Say=require('src/say')
local Config=require('src/config')
local Helpers=require('tests/helpers')
local check=Helpers.check
local T={}
-- Exemples envoyés par la session SetupLab (12/11/2026) ; le dernier avec sess.
local IDLE='v=1;kind=race;ver=v4;fuel=104.3;fpl=2.85;stint=35;compound=M;phot=27.5,27.5,27.9,27.9;tune=idle;readyN=4;stamp=1235;pitc=H;stops=1;tlap=-1;tdl=-;tv=-;tch=-;tid=7'
local WAIT='v=1;kind=quali;ver=e5;fuel=-1;fpl=-1;stint=-1;compound=S;phot=26.8,26.8,26.4,26.4;tune=running;readyN=5;stamp=842;pitc=-;stops=-1;tlap=1;tdl=-0.12;tv=wait;tch=aero;tid=8'
local BETTER='v=1;kind=quali;ver=e5;fuel=-1;fpl=-1;stint=-1;compound=S;phot=26.8,26.8,26.4,26.4;tune=running;readyN=5;stamp=931;pitc=-;stops=-1;tlap=2;tdl=-0.31;tv=better;tch=aero;tid=9'
local SESS='v=1;kind=race;ver=e3;fuel=104.3;fpl=2.85;stint=35;compound=M;phot=27.5,27.5,27.9,27.9;tune=running;readyN=3;stamp=1235;pitc=H;stops=1;tlap=2;tdl=-0.32;tv=better;tch=aero;tid=5;sess=2'
local function with(text,over)
 for k,v in pairs(over) do text=text:gsub(k..'=[^;]*',k..'='..v,1) end
 return text
end
function T.state_parse_contract_v1()
 local a=SetupLab.parse(IDLE)
 check(a and a.kind=='race' and a.ver=='v4' and a.fpl==2.85 and a.stint==35 and a.compound=='M' and a.tune=='idle','idle sample read')
 check(a.tv==nil and a.tdl==nil and a.tch==nil and a.tlap==nil and a.tid==7 and a.readyN==4 and a.pitc=='H','idle: no trial, counters read')
 check(a.phot and a.phot[1]==27.5 and a.phot[4]==27.9,'hot pressures read')
 local b=SetupLab.parse(WAIT)
 check(b and b.tv=='wait' and b.tdl==-0.12 and b.fpl==nil and b.fuel==nil and b.stops==nil and b.tch=='aero','wait sample read')
 local c=SetupLab.parse(BETTER)
 check(c and c.tv=='better' and c.tdl==-0.31 and c.tid==9,'verdict sample read')
 check(SetupLab.parse(SESS).sess==2 and SetupLab.parse(IDLE).sess==nil,'session field read when present')
 -- Abîmés : autre version, genre ou état inconnu, trop long ; champs illisibles pris pour inconnus, le reste lu.
 check(SetupLab.parse(with(IDLE,{v='2'}))==nil,'v=2 ignored')
 check(SetupLab.parse(with(IDLE,{kind='drift'}))==nil and SetupLab.parse(with(IDLE,{tune='x'}))==nil,'unknown kind or tune ignored')
 check(SetupLab.parse(IDLE..';x='..string.rep('a',240))==nil,'too long ignored')
 check(SetupLab.parse(nil)==nil and SetupLab.parse(42)==nil,'not a text')
 local d=SetupLab.parse(with(BETTER,{tdl='abc',tch='wings',phot='1,2,x,4',tv='great'}))
 check(d and d.tdl==nil and d.tch==nil and d.phot==nil and d.tv==nil and d.tid==9,'unreadable fields unknown, rest read')
 check(SetupLab.parse(IDLE..';future=1')~=nil,'unknown fields ignored')
end
function T.state_accepted_per_session()
 local key
 local function read() return key end
 -- Sans sess : le texte trouvé au départ est une référence ; accepté une fois changé dans la séance.
 local s=SetupLab.new()
 key=IDLE; SetupLab.step(s,read,0,2)
 check(SetupLab.get(s)==nil,'text found at start, no sess: reference only')
 key=WAIT; SetupLab.step(s,read,1,2)
 check(SetupLab.get(s) and SetupLab.get(s).ver=='e5','changed during the session: accepted')
 local tidUp=SetupLab.take(s)
 check(tidUp,'tid rise seen during the session')
 check(not SetupLab.take(s),'rise taken once')
 -- Avec sess : accepté tout de suite pour sa séance, jamais pour une autre ; aucune hausse sur le texte de départ.
 local s2=SetupLab.new()
 key=SESS; SetupLab.step(s2,read,0,2)
 check(SetupLab.get(s2) and SetupLab.fuelPerLap(s2)==2.85,'sess of this session: accepted at once, race fuel')
 check(not SetupLab.take(s2),'no rise on the text found at start')
 SetupLab.step(s2,read,1,3)
 check(SetupLab.get(s2)==nil and SetupLab.fuelPerLap(s2)==nil,'next session, key not yet rewritten: ignored')
 key=with(SESS,{sess='3'}); SetupLab.step(s2,read,2,3)
 check(SetupLab.get(s2)~=nil and not SetupLab.take(s2),'rewritten for the new session: accepted, no rise')
 -- Consommation : setup de course seulement, valeur connue seulement.
 key=with(SESS,{sess='3',kind='quali'}); SetupLab.step(s2,read,3,3)
 check(SetupLab.fuelPerLap(s2)==nil,'quali setup: no race fuel')
 -- Détection : la ligne NAME=SetupLab exactement.
 check(SetupLab.installed('[ABOUT]\nNAME=SetupLab\nVERSION=1.0.0-beta.1.5.12\n'),'manifest found')
 check(not SetupLab.installed('[W]\nNAME=SetupLab Debug\n') and not SetupLab.installed(nil),'other window names or no manifest: absent')
end
-- Ingénieur branché sur une clé : séance (sessionType 1 essais, 2 qualifications, 3 course), joueur dans la voie ou non.
local function bench(sessionType)
 local v=Voice.new({play=function() return {} end,playing=function() return false end,stop=function() end})
 v.repeatGap=0; v.infoGap=0; v.quiet=0
 local e=Engineer.new()
 local F={isRace=sessionType==3,sessionType=sessionType,session=1,player=0,cars={[0]={valid=true,pitlane=false,laps=3}},me={fuelPerLapAC=3.1,fuel=50}}
 local ctx={F=F,cfg=Config.defaults(),say=Say.new(v,{},'vox','FR',nil),setuplab=SetupLab.new(),now=0,real=0}
 local key
 local w={v=v,e=e,F=F,ctx=ctx}
 function w.put(text) key=text; ctx.now=ctx.now+1; ctx.real=ctx.now; SetupLab.step(ctx.setuplab,function() return key end,ctx.now,F.session); Engineer.setupLab(e,ctx); Voice.step(v,ctx.real) end
 function w.said(k) local n=0; for _,q in ipairs(v.log) do if q.key==k then n=n+1 end end; for _,q in ipairs(v.queue) do if q.key==k then n=n+1 end end; return n end
 function w.last(k) local q; for _,x in ipairs(v.log) do if x.key==k then q=x end end; for _,x in ipairs(v.queue) do if x.key==k then q=x end end; return q end
 return w
end
local function s1(text) return with(text,{sess='1'})..(text:find('sess=') and '' or ';sess=1') end
function T.trial_verdicts_in_practice()
 local w=bench(1)
 w.put(s1(IDLE))
 check(w.said('setupLab')==0,'text found at start: nothing')
 -- Attente avec un écart chiffré : rien.
 w.put(s1(with(WAIT,{tid='8'})))
 check(w.said('setupLab')==0,'wait with a gap: nothing')
 w.put(s1(BETTER))
 local q=w.last('setupLab')
 check(w.said('setupLab')==1 and q and q.text:find('plus rapide',1,true),'better: said')
 check(q and q.text:find('0,31 s',1,true) and q.text:find("aéro",1,true),'exact gap and main change written: '..tostring(q and q.text))
 -- Même verdict, écart quasi égal : pas redit ; écart qui bouge de 0,05 s : redit.
 w.put(s1(with(BETTER,{tid='10',tdl='-0.33'})))
 check(w.said('setupLab')==1,'same verdict: not repeated')
 w.put(s1(with(BETTER,{tid='11',tdl='-0.40'})))
 check(w.said('setupLab')==2,'gap moved: said again')
 -- Pareil : « pas de différence nette ».
 w.put(s1(with(BETTER,{tid='12',tv='same',tdl='0.05'})))
 check(w.last('setupLab').text:find('Pas de différence',1,true),'same: no clear difference')
 -- Nouvelle version : l'historique repart ; un verdict déjà dit pour la version d'avant est redit pour celle-ci.
 w.put(s1(with(BETTER,{tid='13',ver='e6',tv='same',tdl='0.02'})))
 check(w.said('setupLab')==4,'new version: verdict said again')
 -- Version prête au stand : une annonce par hausse de readyN (4 -> 5 plus haut, puis 6).
 local ready=w.said('setupReady')
 w.put(s1(with(BETTER,{tid='13',ver='e6',tv='same',tdl='0.02',readyN='6',tune='ready'})))
 check(ready==1 and w.said('setupReady')==2,'new version ready: once per rise, got '..ready..' then '..w.said('setupReady'))
end
function T.trial_verdicts_never_in_race_and_held_in_quali()
 local r=bench(3)
 r.put(s1(WAIT)); r.put(s1(BETTER)); r.put(s1(with(BETTER,{readyN='6'})))
 check(r.said('setupLab')==0 and r.said('setupReady')==0,'race: silent')
 local q=bench(2)
 q.put(s1(WAIT)); q.put(s1(BETTER))
 check(q.said('setupLab')==0,'quali, on track: held')
 q.put(s1(with(BETTER,{tid='10',tdl='-0.5'})))
 q.F.cars[0].pitlane=true; q.put(s1(with(BETTER,{tid='10',tdl='-0.5'})))
 check(q.said('setupLab')==1 and q.last('setupLab').text:find('0,50 s',1,true),'quali, pit entry: the last verdict only')
 -- Réglage coupé : rien.
 local o=bench(1); o.ctx.cfg.setupTrials=false
 o.put(s1(WAIT)); o.put(s1(BETTER))
 check(o.said('setupLab')==0,'trials off: silent')
end
-- Carburant avant mesure : SetupLab (setup de course, clé acceptée), sinon AC ; une seule règle partout.
function T.fuel_seed_from_setuplab()
 local w=bench(1)
 check(St.baseFuel(w.e.strategist,w.F)==3.1,'no SetupLab: AC')
 w.put(SESS:gsub('sess=2','sess=1'))
 check(St.baseFuel(w.e.strategist,w.F)==2.85,'race setup: SetupLab fuel')
 check(Engineer.fuelStatus(w.e,w.F,{fuelMargin=0})==nil or Engineer.fuelStatus(w.e,w.F,{fuelMargin=0}).fpl==2.85,'fuel view uses the same value')
 w.ctx.cfg.setupLab=false; w.put(SESS:gsub('sess=2','sess=1'))
 check(St.baseFuel(w.e.strategist,w.F)==3.1,'SetupLab section off: AC again')
end
-- Sans SetupLab, réglages identiques à la 1.3.8 : aucune section ni groupe en plus.
function T.no_setuplab_no_section()
 local before={}
 for _,tab in ipairs(Config.tabs) do
  for _,sec in ipairs(Config.shownOf(tab,{})) do before[#before+1]=sec.id end
 end
 for _,id in ipairs(before) do check(id~='setuplab','hidden without SetupLab') end
 local engineer={}
 for _,sec in ipairs(Config.shownOf('engineer',nil)) do engineer[#engineer+1]=sec.id end
 check(table.concat(engineer,',')=='pace,debrief,fuel,driving,tyres,brakes,damage,weather,wind','engineer tab as in 1.3.8: '..table.concat(engineer,','))
 local shown=false
 for _,sec in ipairs(Config.shownOf('engineer',{setuplab=true})) do if sec.id=='setuplab' then shown=true end end
 check(shown,'shown with SetupLab')
end
return T
