-- Radio (file, priorités, phrases), chronométrage, côte à côte, coach, apprentissage de la stratégie.
local Voice=require('src/voice')
local Say=require('src/say')
local Timing=require('src/timing')
local Proximity=require('src/proximity')
local Coach=require('src/coach')
local SD=require('src/stratdata')
local Config=require('src/config')
local Catalog=require('src/catalog')
local T={}
local Helpers=require('tests/helpers')
local check,near=Helpers.check,Helpers.near
-- Port audio factice : un clip dure 1 s.
local function fakePort(clock)
 local p={log={},stopped=0}
 p.play=function(path) local h={path=path,t=clock()}; p.log[#p.log+1]=path; return h end
 p.playing=function(h) return clock()-h.t<1 end
 p.stop=function() p.stopped=p.stopped+1 end
 return p
end
function T.voice_priority_and_interruption()
 local now=0
 local port=fakePort(function() return now end)
 local v=Voice.new(port)
 Voice.say(v,{key='info',role='engineer',prio=4,clips={'a.wav'},text='info',ttl=10},now)
 Voice.step(v,now); check(port.log[1]=='a.wav','info plays')
 Voice.say(v,{key='side',role='spotter',prio=1,clips={'left.wav'},text='left',ttl=2},now)
 now=0.1; Voice.step(v,now)
 check(port.stopped>=1,'urgent cuts info')
 now=0.5; Voice.step(v,now); check(port.log[2]=='left.wav','urgent plays after the cut: '..tostring(port.log[2]))
end
-- Une annonce coupée est reprise une seule fois (coupée de nouveau : abandonnée).
-- Retardataire seulement si le classement d'AC confirme le tour de retard (compteur de tours décalé d'un tour : une
-- voiture classée devant n'est jamais un retardataire) ; même règle pour la voiture qui prend un tour.
function T.lap_down_needs_the_classification()
 local Spotter=require('src/spotter')
 local me={position=5}; local mine={progress=11.1}
 check(not Spotter.lapDown(me,{position=3},mine,{progress=10.2},true),'classified ahead, lap counter off by one: not a backmarker')
 check(Spotter.lapDown(me,{position=9},mine,{progress=10.2},true),'classified behind and a lap down: backmarker')
 check(not Spotter.lapDown(me,{position=9},mine,{progress=11.3},true),'classified behind but not a lap down: no')
 check(not Spotter.lapDown(me,{position=0},mine,{progress=10.2},true),'unknown position: no')
 check(Spotter.lapDown(me,{position=1},mine,{progress=12.0},false),'leader lapping the player')
 check(not Spotter.lapDown(me,{position=8},mine,{progress=12.0},false),'classified behind: not lapping the player')
end
-- Conseil de pilotage : le secteur officiel est dit (« au secteur » puis le nombre), le virage et le temps sont écrits ;
-- sans secteur connu, jamais « au secteur » sans numéro.
function T.coach_says_the_sector()
 local Engineer=require('src/engineer'); local Catalog=require('src/catalog')
 local files={}
 for _,k in ipairs({'losingTime','atSector','brakeLater'}) do files['FR/'..Catalog.clips[k].FR]=true end
 files['FR/num/02.wav']=true
 local v=Voice.new({play=function() return {} end,playing=function() return false end,stop=function() end})
 local s=Say.new(v,files,'vox','FR',nil)
 local e=Engineer.new()
 local ctx={say=s,real=0,sectorName=function() return 'Parabolica' end}
 e.sectorOf[10]=1
 Engineer.coachCall(e,ctx,{kind='losingTime',segment=10,loss=0.25})
 local q=v.queue[#v.queue]
 check(q and q.clips and #q.clips==3 and q.clips[3]:find('num/02',1,true),'sector number spoken: '..tostring(q and q.clips and #q.clips))
 check(q.text=='Tu perds du temps au secteur 2 (Parabolica, 0,25 s)','text: '..tostring(q.text))
 v.queue={}; v.last={}
 Engineer.coachCall(e,ctx,{kind='losingTime',segment=30,loss=0.25})
 q=v.queue[#v.queue]
 check(q and #q.clips==1 and not q.text:find('au secteur',1,true),'unknown sector: no dangling « au secteur »: '..tostring(q and q.text))
 v.queue={}; v.last={}
 Engineer.coachCall(e,ctx,{kind='brakeLater',segment=10})
 q=v.queue[#v.queue]
 check(q and #q.clips==3 and q.text:find('secteur 2',1,true),'braking advice with the sector: '..tostring(q and q.text))
end
-- Événements de la radio pour le journal : dite ou écrite, coupée (reprise ou abandonnée), périmée.
function T.voice_events_for_the_journal()
 local now=0
 local port=fakePort(function() return now end)
 local v=Voice.new(port)
 local seen={}
 v.onEvent=function(kind,item,again) seen[#seen+1]=kind..':'..tostring(item.key)..(again==nil and '' or (again and '+' or '-')) end
 Voice.say(v,{key='info',role='engineer',prio=3,clips={'a.wav'},text='info',ttl=10},now); Voice.step(v,now)
 Voice.say(v,{key='side',role='spotter',prio=1,clips={'l.wav'},text='left',ttl=2,once=true},now); now=0.1; Voice.step(v,now)
 Voice.say(v,{key='old',role='engineer',prio=5,clips={'o.wav'},text='old',ttl=1},now)
 for t=0.2,5,0.1 do now=t; Voice.step(v,now) end
 local all=table.concat(seen,' ')
 check(all:find('radio:info',1,true) and all:find('cut:info+',1,true) and all:find('radio:side',1,true),'events: '..all)
 check(all:find('expired:old',1,true),'expired event: '..all)
end
function T.voice_cut_announcement_replayed_once()
 local now=0
 local port=fakePort(function() return now end)
 local v=Voice.new(port)
 Voice.say(v,{key='plan',role='spotter',prio=3,clips={'plan.wav'},text='plan',ttl=30},now)
 Voice.step(v,now)
 local function side(t,key) now=t; Voice.say(v,{key=key,role='spotter',prio=1,clips={'left.wav'},text=key,ttl=2,once=true},now); Voice.step(v,now) end
 side(0.2,'s1'); now=1.5; Voice.step(v,now); now=1.7; Voice.step(v,now)
 local plays=0; for _,p in ipairs(port.log) do if p=='plan.wav' then plays=plays+1 end end
 check(plays==2,'replayed once after the first cut: '..plays)
 side(1.8,'s2'); for t=3,8,0.1 do now=t; Voice.step(v,now) end
 plays=0; for _,p in ipairs(port.log) do if p=='plan.wav' then plays=plays+1 end end
 check(plays==2,'cut again: not replayed a second time: '..plays)
end
function T.voice_ttl_cooldown_and_sequence()
 local now=0
 local port=fakePort(function() return now end)
 local v=Voice.new(port)
 check(Voice.say(v,{key='k',prio=3,clips={'1.wav','2.wav'},text='x',ttl=5,cooldown=30},now),'first')
 check(not Voice.say(v,{key='k',prio=3,clips={'1.wav'},text='x',ttl=5,cooldown=30},1),'cooldown')
 Voice.step(v,0); now=1.2; Voice.step(v,now); check(port.log[2]=='2.wav','second clip of the phrase')
 Voice.say(v,{key='old',prio=5,clips={'old.wav'},text='old',ttl=1},now)
 now=5; Voice.step(v,now); Voice.step(v,now+0.5)
 for _,p in ipairs(port.log) do check(p~='old.wav','stale item dropped') end
 check(v.log[#v.log].text=='x','log keeps written text')
end
function T.say_numbers_and_missing_clips()
 local v=Voice.new(fakePort(function() return 0 end))
 local files={['FR/46_ecart_devant.wav']=true,['FR/num/01.wav']=true,['FR/num/02.wav']=true,['FR/83_virgule.wav']=true,['FR/139_seconde.wav']=true}
 local s=Say.new(v,files,'vox','FR')
 local parts={'gapAhead',{n=1.24,dec=1},'seconds'}
 check(Say.text(s,parts)=='Écart devant : 1,2 seconde.','text: '..Say.text(s,parts))
 local paths=Say.paths(s,Say.expand(s,parts))
 check(paths and #paths==5 and paths[5]:find('139_seconde',1,true),'paths')
 check(paths[2]=='vox/FR/num/01.wav' and paths[3]=='vox/FR/83_virgule.wav' and paths[4]=='vox/FR/num/02.wav','number clips')
 check(Say.paths(s,Say.expand(s,{'carLeft'}))==nil,'missing clip -> written only')
 Say.setLanguage(s,'EN'); check(Say.text(s,parts)=='Gap ahead: 1.2 seconds.','EN text '..Say.text(s,parts))
 check(Catalog.numberFR(81)=='quatre-vingt-un' and Catalog.numberFR(21)=='vingt et un' and Catalog.numberFR(80)=='quatre-vingts','french numbers')
end
function T.timing_gap_between_two_cars()
 local t=Timing.new()
 -- Deux voitures à 50 m/s sur un tour de 5 000 m (100 s), B 2 s derrière A.
 local L=5000
 for step=0,600 do
  local now=step*0.05
  local a=(now*50)/L; local b=((now-2)*50)/L
  Timing.update(t,0,a%1,math.floor(a),now,true)
  if now>=2 then Timing.update(t,1,b%1,math.floor(b),now,true) end
 end
 local g=Timing.gap(t,0,1,30)
 near(g,2,0.06,'gap')
 near(Timing.trackGap(t,0,1,30),2,0.06,'track gap')
end
function T.timing_lapped_car()
 local t=Timing.new()
 Timing.update(t,0,0.2,5,0,true); Timing.update(t,1,0.1,3,0,true)
 local g,laps=Timing.gap(t,0,1,0)
 check(g==nil and laps==2,'two laps down')
end
-- Pas de temps de 0,05 s jusqu'à t ; renvoie le premier évènement vu (ou nil).
local function proxRun(p,me,cars,n,from,to,cfg)
 local seen=nil
 local t=from
 while t<=to+1e-9 do
  local ev=Proximity.step(p,me,cars,n,0,t,cfg)
  if ev[1] and not seen then seen=ev[1] end
  t=t+0.05
 end
 return seen
end
function T.proximity_left_right_clear()
 local p=Proximity.new()
 local me={x=0,z=0,lookX=0,lookZ=1,kmh=150}
 local cars={[0]={valid=true,x=0,z=0},[1]={valid=true,x=2.5,z=1,pit=false}}
 -- Dans AC, +X est à gauche d'une voiture qui regarde vers +Z. Annonce après 0,25 s de recouvrement.
 check(Proximity.step(p,me,cars,2,0,0)[1]==nil,'not at first contact')
 check(proxRun(p,me,cars,2,0.05,0.3)=='left','left after 0.25 s')
 cars[2]={valid=true,x=-2.4,z=-1}
 check(proxRun(p,me,cars,3,0.35,0.7)=='three','three wide')
 -- « Dégagé » après 0,6 s de voie libre seulement.
 cars[1].z=20
 check(proxRun(p,me,cars,3,0.75,1.3)==nil,'no clear before 0.6 s')
 check(proxRun(p,me,cars,3,1.35,1.45)=='clearLeft','clear left while right stays')
 cars[2].z=-20
 check(proxRun(p,me,cars,3,1.5,2.2)=='clear','clear')
 local q=Proximity.new()
 local flipped=Proximity.defaults; local cfg={}; for k,v in pairs(flipped) do cfg[k]=v end; cfg.flip=true
 check(proxRun(q,me,{[0]={valid=true,x=0,z=0},[1]={valid=true,x=2.5,z=0}},2,0,0.4,cfg)=='right','flip setting')
end
function T.proximity_ignores_slipstream_and_brushes()
 local me={x=0,z=0,lookX=0,lookZ=1,kmh=150}
 -- Voiture 4 m derrière, décalée de 0,8 m (aspiration) : jamais « à côté ».
 local p=Proximity.new()
 check(proxRun(p,me,{[0]={valid=true,x=0,z=0},[1]={valid=true,x=0.8,z=-4}},2,0,3)==nil,'slipstream car is not alongside')
 -- Frôlement de 0,1 s : ni annonce, ni « dégagé ».
 local q=Proximity.new()
 local cars={[0]={valid=true,x=0,z=0},[1]={valid=true,x=2,z=0}}
 local seen=proxRun(q,me,cars,2,0,0.1)
 cars[1].z=30
 seen=seen or proxRun(q,me,cars,2,0.15,2)
 check(seen==nil,'brush called: '..tostring(seen))
 -- Côte à côte réel à 2 m : annoncé, puis dégagé 0,6 s après son départ.
 local r=Proximity.new()
 cars[1].z=0
 check(proxRun(r,me,cars,2,0,0.3)=='left','real side by side called')
 cars[1].z=30
 check(proxRun(r,me,cars,2,0.35,0.9)==nil and proxRun(r,me,cars,2,0.95,1.0)=='clear','clear 0.6 s after it leaves')
end
-- Rythme de la radio : une information attend infoGap ; la sécurité n'attend jamais ; un même texte n'est pas redit.
function T.voice_pacing()
 local port={play=function(p) return {p=p} end,playing=function() return false end,stop=function() end}
 local v=Voice.new(port)
 local function item(key,prio,text) return {key=key,role='engineer',prio=prio,clips={'a.wav'},text=text or key,ttl=30} end
 Voice.say(v,item('i1',4),0); Voice.step(v,0); Voice.step(v,0.1)
 check(v.started.i1==0,'first information spoken')
 Voice.say(v,item('i2',4),1)
 for t=1,11,0.5 do Voice.step(v,t) end
 check(v.started.i2==nil,'second information waits for infoGap')
 Voice.say(v,item('safety',2),5); Voice.step(v,5.2); Voice.step(v,5.3)
 check(v.started.safety and v.started.safety<5.5,'safety call never delayed')
 for t=11.5,14,0.5 do Voice.step(v,t) end
 check(v.started.i2 and v.started.i2>=12,'information spoken after infoGap: '..tostring(v.started.i2))
 -- Même texte (priorité 3) redit trop tôt : retiré.
 Voice.say(v,item('r1',3,'Pneus chauds.'),20); for t=20,21,0.5 do Voice.step(v,t) end
 v.last.r1=nil
 Voice.say(v,item('r1',3,'Pneus chauds.'),40); for t=40,41,0.5 do Voice.step(v,t) end
 check(v.started.r1<40,'identical text not repeated within repeatGap')
 -- Le spotter n'est jamais concerné : deux voitures lentes à 60 s, deux retardataires à 40 s, tous dits.
 local function spot(key,text) return {key=key,role='spotter',prio=3,clips={'a.wav'},text=text,ttl=30} end
 for _,pair in ipairs({{'white','Voiture lente devant.',60},{'backmarker','Retardataire devant.',40}}) do
  local t0=100+(pair[3]==60 and 0 or 200)
  Voice.say(v,spot(pair[1],pair[2]),t0); Voice.step(v,t0); Voice.step(v,t0+0.5)
  local first=v.started[pair[1]]
  Voice.say(v,spot(pair[1],pair[2]),t0+pair[3]); Voice.step(v,t0+pair[3]); Voice.step(v,t0+pair[3]+0.5)
  check(first and v.started[pair[1]]>first,pair[1]..' said twice '..pair[3]..' s apart')
 end
end
-- Écarts : nombre et unité en un seul clip sous 10 s, singulier en français sous 2, arrondi au-delà de 10 s.
function T.gaps_read_fast()
 local port={play=function(p) return {p=p} end,playing=function() return false end,stop=function() end}
 local v=Voice.new(port)
 local files={['FR/46_ecart_devant.wav']=true,['FR/sec/093.wav']=true,['FR/sec/015.wav']=true,['FR/num/12.wav']=true,['FR/82_secondes.wav']=true,
  ['EN/46_gap_ahead.wav']=true,['EN/sec/010.wav']=true}
 local s=Say.new(v,files,'vox','FR',nil)
 Say.say(s,'spotter','g1',4,{'gapAhead',{n=9.31,dec=1,unit='s'}},0,{ttl=20})
 local q=v.queue[#v.queue]
 check(q and #q.clips==2 and q.clips[2]:find('sec/093',1,true),'9.3 s in two clips: '..tostring(q and #q.clips))
 check(q.text=='Écart devant : 9,3 secondes','text: '..tostring(q.text))
 Say.say(s,'spotter','g2',4,{'gapAhead',{n=1.48,dec=1,unit='s'}},0,{ttl=20})
 check(v.queue[#v.queue].text=='Écart devant : 1,5 seconde','French singular below 2: '..v.queue[#v.queue].text)
 Say.say(s,'spotter','g3',4,{'gapAhead',{n=12.4,dec=1,unit='s'}},0,{ttl=20})
 q=v.queue[#v.queue]
 check(q.text=='Écart devant : 12 secondes.' and #q.clips==3,'rounded above 10 s: '..q.text)
 Say.setLanguage(s,'EN')
 Say.say(s,'spotter','g4',4,{'gapAhead',{n=1.0,dec=1,unit='s'}},0,{ttl=20})
 check(v.queue[#v.queue].text=='Gap ahead: 1 second' and #v.queue[#v.queue].clips==2,'English: '..v.queue[#v.queue].text)
end
function T.coach_detects_early_braking()
 local c=Coach.new()
 local L=4000
 -- 40 mini-secteurs de 2,5 s ; tour « en retard » : freinage dès le 2e point du secteur 10 (au lieu du 7e) et 0,3 s
 -- perdues dans ce secteur seulement.
 local t0=0
 local function lap(late)
  for k=0,399 do
   local sp=k/400; local seg=math.floor(sp*40)
   local brake=(seg==10 and (k%10)>=(late and 2 or 7)) and 1 or 0
   local extra=late and (k>=110 and 0.3 or k>=100 and (k-100)*0.03 or 0) or 0
   Coach.update(c,sp,200,brake,t0+k*0.25+extra,L)
  end
  t0=t0+100+(late and 0.3 or 0)
  Coach.update(c,0,200,0,t0,L)
  return Coach.lap(c,true,0.1)
 end
 lap(false); lap(false)
 local advice
 for _=1,4 do advice=lap(true) or advice end
 check(advice and advice.segment==10,'segment 10 flagged: '..tostring(advice and advice.segment))
 check(advice.kind=='brakeLater','early braking: '..tostring(advice.kind))
end
function T.stratdata_learns_fuel_and_wear()
 local d=SD.new()
 local curves={}
 local fuel,km=60,0
 SD.update(d,{now=0,laps=0,lapTime=0,fuel=fuel,kmF=km,kmR=km,pit=false,road=30,neutral=false,valid=true},curves)
 for lap=1,8 do
  fuel=fuel-2.4; km=km+0.3
  SD.update(d,{now=lap*100,laps=lap,lapTime=100+lap*0.1,fuel=fuel,kmF=km,kmR=km,pit=false,road=30,neutral=false,valid=true},curves)
 end
 near(d.fuelPerLap,2.4,1e-6,'fuel per lap'); near(d.kmF,0.3,1e-6,'km per lap')
 SD.fit(d,curves,0.03,0.6,0.05)
 check(d.degLinear and d.degLinear>0.02 and d.degLinear<0.2,'linear degradation learnt '..tostring(d.degLinear))
 -- Pneus changés : âge remis à zéro.
 SD.update(d,{now=900,laps=8,lapTime=0,fuel=fuel,kmF=0,kmR=0,pit=true,road=30,neutral=false,valid=true},curves)
 check(d.tyreAge==0,'tyre age reset')
 local m=SD.model(d,{tank=100,fuel=fuel,curves=curves},Config.defaults(),100)
 near(m.fuelPerLap,2.4,1e-6,'model fuel')
end
function T.stratdata_pit_lane_loss()
 local d=SD.new()
 -- Rythme de course : 100 s le tour, point k franchi à k × 0,25 s (tour en cours) ; au tour précédent pour les points
 -- au-delà de l'entrée (0,95).
 local snap={}
 for k=0,399 do snap[k]=k<=380 and k*0.25 or k*0.25-100 end
 local capture=function() return snap,400,100 end
 SD.observePit(d,3,false,200,94,0.94,capture)
 SD.observePit(d,3,true,80,95,0.95,capture)
 for k=1,299 do local t=95+k*0.1; SD.observePit(d,3,true,(t>100 and t<=103) and 0 or 60,t,0.0,capture) end -- 3 s immobile
 local r=SD.observePit(d,3,false,80,125,0.05,capture)
 check(r,'stop observed'); near(r.still,3,0.11,'still')
 -- Voie 30 s, dont 3 s immobile, tronçon en piste 10 s : perte de voie 17 s.
 near(d.laneLoss,17,0.2,'lane loss')
 near(SD.trackSegment(snap,400,0.95,0.05),10,1e-6,'segment across the line')
 local snap2={}; for k=0,399 do snap2[k]=k<=320 and k*0.25 or k*0.25-100 end -- entrée à 0,80
 near(SD.trackSegment(snap2,400,0.80,0.90),10,1e-6,'segment before the line')
end
-- Usure anormale : un écart d'usure sur un essieu est dit une fois par séance pour le même côté (au train suivant,
-- rien) ; un défaut du pneu (méplat) est toujours dit, une fois par train. Pneus froids : pas redits en oscillant autour
-- du seuil, redits seulement après 60 s à température.
function T.tyre_calls_do_not_repeat()
 local Engineer=require('src/engineer'); local Voice=require('src/voice'); local Say=require('src/say')
 local port={play=function() return {} end,playing=function() return false end,stop=function() end}
 local v=Voice.new(port); v.repeatGap=0 -- seul l'état de l'ingénieur est jugé ici
 local sayer=Say.new(v,{},'vox','FR',nil)
 local function tyre(vkm) return {core=85,inner=85,mid=85,outer=85,opt=85,vkm=vkm,flat=0,blister=0,grain=0,blown=false} end
 local me={pitlane=false,kmh=150,laps=3}
 local F={player=0,cars={[0]=me},me={tyres={tyre(5),tyre(3),tyre(4),tyre(4)}}}
 local ctx={F=F,cfg=Config.defaults(),say=sayer,real=0}
 local eng=Engineer.new()
 local function count(text) local c=0; for _,l in ipairs(v.log) do if l.text and l.text:find(text,1,true) then c=c+1 end end return c end
 local function run(seconds) for _=1,math.floor(seconds*10) do ctx.real=ctx.real+0.1; Engineer.tyres(eng,ctx,0.1); Voice.step(v,ctx.real) end end
 run(2); check(count('Usure anormale')==1,'uneven front axle: said')
 run(60); check(count('Usure anormale')==1,'not repeated on the same set')
 -- Arrêt : pneus neufs ; même écart du même côté (circuit qui use un côté) : rien.
 for k=1,4 do F.me.tyres[k].vkm=0 end; run(1)
 F.me.tyres[1].vkm=2.6; F.me.tyres[2].vkm=1.5; F.me.tyres[3].vkm=2; F.me.tyres[4].vkm=2; run(5)
 check(count('Usure anormale')==1,'same uneven side on the next set: not repeated')
 F.me.tyres[3].flat=0.5; run(2); check(count('Usure anormale')==2,'flat spot: said')
 run(30); check(count('Usure anormale')==2,'flat spot: once')
 -- Pneus froids.
 eng=Engineer.new(); v.log={}; v.queue={}
 for k=1,4 do local w=F.me.tyres[k]; w.vkm=3; w.flat=0 end
 local function temps(c) for k=1,4 do F.me.tyres[k].core=c end end
 local cold=85-ctx.cfg.tyreCold-5
 temps(cold); run(25); check(count('Pneus froids')==1,'cold tyres: said')
 temps(85); run(10); temps(cold); run(25); check(count('Pneus froids')==1,'around the threshold: not repeated')
 temps(85); run(70); temps(cold); run(25); check(count('Pneus froids')==2,'after a minute at temperature: said again')
end
-- Usure anormale sans km virtuels (multiplicateur d'usure faible ou nul : ils restent à 0, cas réel du 2026-11-09) :
-- un méplat est dit une fois, jamais réarmé à chaque image ; un défaut d'une image n'est rien. Après un arrêt d'où le
-- défaut est reparti (pneus changés), un nouveau méplat est dit ; le train neuf vu aussi par les km qui reculent.
function T.wear_said_once_without_virtual_km()
 local Engineer=require('src/engineer'); local Voice=require('src/voice'); local Say=require('src/say')
 local port={play=function() return {} end,playing=function() return false end,stop=function() end}
 local v=Voice.new(port); v.repeatGap=0
 local sayer=Say.new(v,{},'vox','FR',nil)
 local function tyre() return {core=85,inner=85,mid=85,outer=85,opt=85,vkm=0,flat=0,blister=0,grain=0,blown=false} end
 local me={pitlane=false,kmh=150,laps=3}
 local F={player=0,cars={[0]=me},me={tyres={tyre(),tyre(),tyre(),tyre()}}}
 local lines={}
 local ctx={F=F,cfg=Config.defaults(),say=sayer,real=0,journal=function(text) lines[#lines+1]=text end}
 local eng=Engineer.new()
 local function count() local c=0; for _,l in ipairs(v.log) do if l.text and l.text:find('Usure anormale',1,true) then c=c+1 end end return c end
 local function run(seconds) for _=1,math.floor(seconds*10) do ctx.real=ctx.real+0.1; Engineer.tyres(eng,ctx,0.1); Voice.step(v,ctx.real) end end
 F.me.tyres[2].grain=0.9; run(0.1); F.me.tyres[2].grain=0; run(5); check(count()==0,'one-frame defect: nothing')
 F.me.tyres[1].flat=0.5; run(120); check(count()==1,'flat spot with no virtual km: said once, got '..count())
 check(#lines==1 and lines[1]:find('méplat',1,true) and lines[1]:find('avant gauche',1,true),'journal: tyre and defect, got '..tostring(lines[1]))
 -- Arrêt : pneus changés (le méplat est parti) ; les km virtuels restent à 0.
 me.pitlane=true; run(1); me.pitlane=false; F.me.tyres[1].flat=0; run(5)
 F.me.tyres[3].flat=0.5; run(10); check(count()==2,'new flat spot after a stop: said')
 run(60); check(count()==2,'new flat spot: once')
 -- Arrêt sans changer de pneus : le méplat est toujours là, rien.
 me.pitlane=true; run(1); me.pitlane=false; run(30); check(count()==2,'stop with the same flat spot: nothing')
 -- Km virtuels qui reculent (train neuf, retour au garage) : le même défaut, sur ce train, est redit.
 for k=1,4 do F.me.tyres[k].vkm=4 end; run(1); for k=1,4 do F.me.tyres[k].vkm=0 end; run(5)
 check(count()==3,'new set seen by the virtual km: said')
end
-- Réglages version 3 : volume général 170 % et son de la voiture à 85 % par défaut ; les anciens défauts enregistrés
-- (100 %, 40 %) passent aux nouveaux, un choix fait à la main est gardé.
function T.config_migration_volume_defaults()
 local function near(a,b) return math.abs(a-b)<1e-6 end
 local n=Config.load({})
 check(near(n.volume,1.7) and near(n.duckLevel,0.85),'new install: '..n.volume..' '..n.duckLevel)
 local o=Config.load({schema=2,volume=1,duckLevel=0.4})
 check(near(o.volume,1.7) and near(o.duckLevel,0.85),'old defaults moved: '..o.volume..' '..o.duckLevel)
 local k=Config.load({schema=2,volume=1.3,duckLevel=0.3})
 check(near(k.volume,1.3) and near(k.duckLevel,0.3),'hand-made choice kept')
 local s=Config.load({schema=3,volume=1,duckLevel=0.4})
 check(near(s.volume,1) and near(s.duckLevel,0.4),'choice made after the change kept')
end
function T.config_migration_turns_drs_voice_off()
 check(Config.load({drsVoice=true,volume=1}).drsVoice==false,'old settings (no version): DRS voice off')
 check(Config.load({drsVoice=true,schema=2}).drsVoice==true,'choice made after the change is kept')
 check(Config.load({}).drsVoice==false and Config.load({}).schema==Config.version,'new install')
end
-- Câblage : chaque réglage a ses libellés FR et EN et sa place dans la fenêtre ; les textes FR et EN ont les mêmes clés
-- (nom court de section facultatif). Les fichiers des clips : integration_spec.every_clip_file_exists.
function T.everything_is_wired()
 local L=require('src/lang')
 -- Interrupteurs des rôles et de l'app (Accueil, en-tête), vérification des mises à jour (bloc Mise à jour de l'Accueil).
 local shown={spotterOn=true,engineerOn=true,strategyOn=true,enabled=true,language=true,updateCheck=true}
 for _,tab in ipairs(Config.tabs) do for _,sec in ipairs(Config.sectionsOf[tab] or {}) do
  if sec.master then shown[sec.master]=true end
  for _,k in ipairs(sec.keys) do shown[k]=true end
 end end
 local sfx={}; for _,x in ipairs(Config.overlayKeys) do sfx[x]=true end
 for _,s in ipairs(Config.schema) do
  local k=s[1]
  check(shown[k],'setting not in the window: '..k)
  local overlay=k:match('^%l+(%u%a*)$'); overlay=overlay and sfx[overlay] and k:match('^(%l+)') and Config.index[k:match('^(%l+)')..'Show']
  for _,lang in ipairs({'FR','EN'}) do L.set(lang); check(L.t.keys[k] or overlay,'setting without '..lang..' label: '..k) end
 end
 L.set('FR')
 local function flat(t,path,out) for k,v in pairs(t) do local p=path..'.'..tostring(k); if type(v)=='table' then flat(v,p,out) else out[p]=true end end return out end
 L.set('FR'); local fr=flat(L.t,'',{}); L.set('EN'); local en=flat(L.t,'',{}); L.set('FR')
 for p in pairs(fr) do check(en[p],'FR text without EN: '..p) end
 for p in pairs(en) do check(fr[p],'EN text without FR: '..p) end
end
function T.config_validation()
 local c=Config.load({volume=9,language='DE',gapEvery=2.4,sideBySide='oui'})
 check(c.volume==2,'bounded'); check(c.language=='FR','choice'); check(c.gapEvery==2,'step'); check(c.sideBySide==true,'bool default')
end
-- Signal d'ouverture : une tonalité au début de chaque transmission (pas entre les clips d'une phrase), de nouveau
-- quand une annonce coupée est reprise ; item.clips n'est jamais modifié. Sans signal : la phrase seule.
function T.voice_opening_tone()
 local now=0
 local port=fakePort(function() return now end)
 local v=Voice.new(port)
 local item={key='plan',role='engineer',prio=3,clips={'a.wav','b.wav'},text='plan',ttl=30,chirp='tone.wav'}
 Voice.say(v,item,now)
 for t=0,3.5,0.1 do now=t; Voice.step(v,now) end
 check(table.concat(port.log,' ')=='tone.wav a.wav b.wav','tone then the phrase: '..table.concat(port.log,' '))
 check(#item.clips==2,'clips untouched')
 -- Coupée par la sécurité : reprise avec sa tonalité.
 port.log={}
 Voice.say(v,{key='p2',role='engineer',prio=3,clips={'c.wav'},text='p2',ttl=30,chirp='tone.wav'},now)
 now=now+0.2; Voice.step(v,now)
 Voice.say(v,{key='side',role='spotter',prio=1,clips={'left.wav'},text='left',ttl=2,once=true,chirp='tone.wav'},now)
 for t=now+0.1,now+6,0.1 do now=t; Voice.step(v,now) end
 check(table.concat(port.log,' ')=='tone.wav tone.wav left.wav tone.wav c.wav','cut, side call, replay with its tone: '..table.concat(port.log,' '))
 port.log={}
 Voice.say(v,{key='x',role='engineer',prio=3,clips={'x.wav'},text='x',ttl=30},now)
 for t=now+0.1,now+3,0.1 do now=t; Voice.step(v,now) end
 check(table.concat(port.log,' ')=='x.wav','no tone without the setting: '..table.concat(port.log,' '))
end
-- Position (ingénieur, à la ligne) : dite quand elle change, avec la consigne du tour en une seule transmission ;
-- « Bien joué » seulement pour un dépassement en piste ; rien au départ (avant la fin du tour 2), sous neutralisation,
-- dans la voie des stands, au dernier tour quand le spotter la dit ; tour de sortie des stands : la position seule ;
-- une annonce jamais entendue est redite ; une consigne par ligne au plus ; remise à zéro complète à chaque séance.
function T.position_called_on_change()
 local Engineer=require('src/engineer')
 local files={}
 for _,c in pairs(Catalog.clips) do files['FR/'..c.FR]=true end
 for n=1,Catalog.maxPosition do files['FR/'..Catalog.positionFile(n)]=true end
 local v=Voice.new({play=function() return {} end,playing=function() return false end,stop=function() end})
 local s=Say.new(v,files,'vox','FR')
 local me={valid=true,laps=1,position=5,pitlane=false,lastMs=0}
 local cars={[0]=me}
 for i=1,5 do cars[i]={valid=true,position=0,pitlane=false} end
 local F={isRace=true,player=0,count=6,laps=20,cars=cars,me={kers=false,p2p=0,drsPresent=false}}
 local cfg=Config.defaults()
 local ctx={F=F,cfg=cfg,say=s,link={d={neutral=false,red=false,panelDecided='none',finished=false}},real=0,now=0,timing={}}
 -- Classement : indice -> place ; écarts (s) et rythmes (s/tour) par voiture.
 local function places(t) for i,p in pairs(t) do cars[i].position=p end end
 places({[0]=5,[1]=4,[2]=6,[3]=3,[4]=7,[5]=2})
 local gaps={}; for i=1,5 do gaps[i]=3.0 end
 local paces={[0]=90,[1]=90,[2]=90,[3]=90,[4]=90,[5]=90}
 local gap,pace=Timing.gap,Timing.pace
 Timing.gap=function(_,a,b) return gaps[a==0 and b or a] end
 Timing.pace=function(_,i) return paces[i] end
 local e=Engineer.new()
 local function line(laps)
  me.laps=laps; ctx.real=ctx.real+100; ctx.now=ctx.real
  Engineer.pace(e,ctx,true)
 end
 local function said(key) for _,q in ipairs(v.queue) do if q.key==key then return q end end return nil end
 -- La radio joue ce qui attend (clips instantanés).
 local function hear() for k=1,80 do Voice.step(v,ctx.real+k*0.5) end end
 local ok,err=pcall(function()
  line(1); check(not said('position'),'nothing at the end of lap 1')
  line(2); local q=said('position'); check(q and q.text=='Tu es P5.','position at the end of lap 2: '..tostring(q and q.text))
  check(q.clips and q.clips[1]:find('pos/05',1,true),'position clip: '..tostring(q.clips and q.clips[1]))
  hear(); line(3); check(not said('position'),'same place, heard: not repeated')
  -- Dépassement de la voiture 1 en piste ; voiture 3 devant à moins d'une seconde : une transmission avec la consigne.
  places({[0]=4,[1]=5}); gaps[3]=0.8; line(4)
  q=said('position'); check(q and q.text=="Tu es P4. Bien joué. Attaque maintenant, c'est le moment.",'merged with the push call: '..tostring(q and q.text))
  check(not said('attack'),'no separate push call')
  hear()
  -- Place prise à un arrêt (la voiture 3 passe par les stands) : pas de « bien joué ».
  e.pitted[3]=true; places({[0]=3,[3]=6,[2]=7,[4]=8}); gaps[3]=3.0; gaps[5]=4.0; line(5)
  q=said('position'); check(q and q.text:find('Tu es P3.',1,true) and not q.text:find('Bien joué',1,true),'place from a stop: '..tostring(q and q.text))
  hear()
  -- Annonce jamais entendue (périmée) : redite à la ligne suivante.
  places({[0]=4,[1]=3}); line(6); check(said('position'),'P4 queued'); v.queue={}
  line(7); q=said('position'); check(q and q.text:find('Tu es P4.',1,true),'lost call said again: '..tostring(q and q.text))
  hear()
  -- Voiture devant rattrapable avant l'arrivée, pas d'autre consigne : le conseil.
  places({[0]=5,[1]=4}); gaps[1]=2.0; paces[1]=90.5; e.attackState='chase'; e.attackCar=1; line(8)
  q=said('position'); check(q and q.text:find('Tu es P5. Il est à portée',1,true),'within reach: '..tostring(q and q.text))
  hear(); paces[1]=90; gaps[1]=3.0
  -- Une consigne par ligne : voiture devant à portée et voiture derrière qui revient, seule l'attaque est dite.
  e.attackState=nil; gaps[1]=0.8; gaps[2]=1.0; paces[2]=89.5; places({[2]=6}); line(9)
  check(said('attack') and not said('defend'),'one call per line')
  hear(); gaps[1]=3.0; gaps[2]=3.0; paces[2]=90
  -- Sous SC : rien.
  ctx.link.d.neutral=true; places({[0]=6,[2]=5}); line(10); check(not said('position'),'nothing under neutralisation')
  ctx.link.d.neutral=false
  -- Dans la voie des stands : rien ; tour de sortie : la position seule.
  me.pitlane=true; places({[0]=8,[4]=6}); line(11); check(not said('position'),'nothing in the pit lane')
  e.lastLapPit=true; me.pitlane=false; gaps[1]=0.5; line(12)
  q=said('position'); check(q and q.text=='Tu es P8.','out lap: position only: '..tostring(q and q.text))
  e.lastLapPit=false; hear(); gaps[1]=3.0
  -- Dernier tour (20 tours) : le spotter la dit avec « Dernier tour ! » ; spotter coupé, l'ingénieur la dit.
  places({[0]=7,[4]=8}); line(19); check(not said('position'),'nothing from the engineer on the last lap')
  cfg.spotterOn=false; line(19); check(said('position'),'last lap, spotter off: the engineer says it')
  hear(); cfg.spotterOn=true
  -- Nouvelle séance : tout est oublié, la position déjà dite est redite.
  Engineer.reset(e); Voice.reset(v); line(1); line(2)
  q=said('position'); check(q and q.text=='Tu es P7.','after a reset: '..tostring(q and q.text))
 end)
 Timing.gap=gap; Timing.pace=pace
 if not ok then error(err,0) end
end
-- Un état nouveau (fresh : position) n'est jamais écarté comme une redite ; la même phrase sans fresh l'est.
function T.voice_fresh_is_never_a_repeat()
 local now=0
 local port=fakePort(function() return now end)
 local v=Voice.new(port)
 local function play(item) Voice.say(v,item,now); for _=1,30 do now=now+0.2; Voice.step(v,now) end end
 play({key='a',role='engineer',prio=4,clips={'p5.wav'},text='Tu es P5.',ttl=30})
 play({key='a',role='engineer',prio=4,clips={'p5.wav'},text='Tu es P5.',ttl=30})
 check(#port.log==1,'plain repeat dropped: '..#port.log)
 play({key='b',role='engineer',prio=4,clips={'p5.wav'},text='Tu es P5.',ttl=30,fresh=true})
 check(#port.log==2,'fresh state said again: '..#port.log)
end
-- Texte et voix d'une même phrase : unité accordée à la valeur dite (singulier sous 2 en français, pour 1 en anglais),
-- nombres sans zéro final, point avant une phrase du catalogue qui commence par une majuscule (jamais après un nom).
function T.say_agreement_and_sentences()
 local v=Voice.new(fakePort(function() return 0 end))
 local files={}
 for _,c in pairs(Catalog.clips) do files['FR/'..c.FR]=true; files['EN/'..c.EN]=true end
 for n=0,Catalog.maxNumber do files['FR/'..Catalog.numberFile(n)]=true; files['EN/'..Catalog.numberFile(n)]=true end
 for n=0,Catalog.maxTenths do files['FR/'..Catalog.secondsFile(n)]=true end
 local s=Say.new(v,files,'vox','FR')
 local function t(parts) return Say.text(s,parts) end
 check(t({'fuelTarget','minus',{n=0.5,dec=1},'laps'})=='Cible carburant : moins 0,5 tour.','FR 0,5 tour: '..t({'fuelTarget','minus',{n=0.5,dec=1},'laps'}))
 check(t({'fuelTarget','plus',{n=1.0,dec=1},'laps'})=='Cible carburant : plus 1 tour.','FR 1 tour: '..t({'fuelTarget','plus',{n=1.0,dec=1},'laps'}))
 check(t({'fuelTarget','plus',{n=2.04,dec=1},'laps'})=='Cible carburant : plus 2 tours.','FR 2 tours')
 check(t({'drsIn',{n=1},'laps'})=='DRS autorisé dans 1 tour.','DRS in 1 lap: '..t({'drsIn',{n=1},'laps'}))
 check(t({'rainIn','oneMinute'})=='Pluie attendue dans une minute.','one minute')
 check(t({'gapAhead',{n=1.24,dec=1,unit='s'},'closing','andBehind',{n=2.4,dec=1,unit='s'}})=='Écart devant : 1,2 seconde. Tu reviens. Derrière : 2,4 secondes',
  'sentence break: '..t({'gapAhead',{n=1.24,dec=1,unit='s'},'closing','andBehind',{n=2.4,dec=1,unit='s'}}))
 check(t({'pitWindow',{n=12},'toLap',{n=18},'optimalLap',{n=15}})=="Fenêtre d'arrêt du tour 12 au tour 18. Tour optimal : 15",'window: '..t({'pitWindow',{n=12},'toLap',{n=18},'optimalLap',{n=15}}))
 check(t({{pos=4},'posGained','posReach'})=='Tu es P4. Bien joué. Il est à portée, force un peu, tu peux y arriver.','position')
 check(t({'rivalPenalty','wordAhead',{text='(Vettel · +5 s)'}})=='Pénalité pour la voiture devant. (Vettel · +5 s)','written note: no added period')
 -- Gap de 9,6 s sans décimale : 10 secondes (nombre et unité), jamais un clip de durée qui n'existe pas.
 Say.say(s,'spotter','g',3,{'gapAhead',{n=9.6,dec=0,unit='s'}},0,{ttl=5})
 local q=v.queue[#v.queue]
 check(q.text=='Écart devant : 10 secondes.' and q.clips and #q.clips==3 and q.clips[2]:find('num/10',1,true),'9,6 s rounded: '..tostring(q.text)..' '..tostring(q.clips and #q.clips))
 Say.setLanguage(s,'EN')
 check(t({'fuelTarget','plus',{n=1,dec=1},'laps'})=='Fuel target: plus 1 lap.','EN 1 lap: '..t({'fuelTarget','plus',{n=1,dec=1},'laps'}))
 check(t({'fuelTarget','plus',{n=0.5,dec=1},'laps'})=='Fuel target: plus 0.5 laps.','EN 0.5 laps')
end
-- Rythme : un tour passé par la voie des stands ou sous neutralisation n'est pas compté.
function T.timing_dirty_laps_excluded()
 local t=Timing.new()
 Timing.update(t,1,0.5,0,10,true); Timing.lap(t,1,0,0)
 Timing.lap(t,1,90,1); Timing.lap(t,1,91,2)
 Timing.update(t,1,0.6,2,200,true,true); Timing.lap(t,1,130,3)
 Timing.lap(t,1,92,4)
 near(Timing.pace(t,1,3),91,1e-9,'pit lap left out of the pace')
end
-- Réglages : une valeur par défaut validée reste égale à elle-même (aucun « réglage modifié » à tort).
function T.config_defaults_stay_equal()
 for _,s in ipairs(Config.schema) do check(Config.valid(s[1],s[2])==s[2],'default drifts: '..s[1]..' '..string.format('%.17g',tonumber(Config.valid(s[1],s[2])) or 0)) end
end
-- Remise à neuf d'un état : clés à nil et clés ajoutées en cours de route effacées, clés apprises gardées.
function T.refill_clears_everything()
 local U=require('src/util')
 local t={a=1,b=2,learnt=5,extra=true}
 U.refill(t,{a=0},{'learnt'})
 check(t.a==0 and t.b==nil and t.extra==nil and t.learnt==5,'refilled')
end
return T
