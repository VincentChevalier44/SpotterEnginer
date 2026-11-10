-- Radio vivante (1.3.0) : variantes et tons, dangers devant, voiture qui arrive à côté, dépassement fini, urgences du
-- joueur, position et écarts en direct, stratégie commentée. Chaque appel a son cas muet (rien ne se passe : rien n'est
-- dit), demande constante du pilote depuis la 1.1.1 (« il me dit … alors qu'il n'y a personne »).
local Voice=require('src/voice')
local Say=require('src/say')
local Catalog=require('src/catalog')
local Config=require('src/config')
local Timing=require('src/timing')
local Hazards=require('src/hazards')
local Emergency=require('src/emergency')
local Spotter=require('src/spotter')
local Engineer=require('src/engineer')
local Strategist=require('src/strategist')
local T={}
local check=require('tests/helpers').check
local function radio(withFiles)
 local port={play=function(p) return {p=p} end,playing=function() return false end,stop=function() end}
 local v=Voice.new(port)
 local files={}
 if withFiles then for id,c in pairs(Catalog.clips) do files['FR/'..c.FR]=true end end
 local s=Say.new(v,files,'vox','FR',nil)
 return v,s
end
local function queued(v,key) for _,q in ipairs(v.queue) do if q.key==key then return q end end return nil end
local function count(v,key) local n=0; for _,q in ipairs(v.queue) do if q.key==key then n=n+1 end end return n end
-- Image de course : joueur (indice 0) sur une piste de 4000 m, voitures données {spline, kmh, …}.
local function scene(cars,opts)
 opts=opts or {}
 local v,s=radio()
 local F={cars={},count=#cars+1,player=0,isRace=opts.race~=false,trackLength=4000,pitSpeed=80,started=true,laps=20,
  me={damage={0,0,0,0,0},susp={0,0,0,0},hit=-1,tyres={{blown=false},{blown=false},{blown=false},{blown=false}},wheelsOut=0,cuts=0,lapValid=true}}
 F.cars[0]={valid=true,x=0,y=0,z=0,lookX=0,lookZ=1,kmh=opts.kmh or 200,spline=0.5,laps=opts.laps or 5,position=opts.pos or 3,pitlane=false,name='Moi',len=4.7,hit=-1}
 for k,c in ipairs(cars) do
  local i=k
  local spline=c.spline or 0.5
  local dz=(spline-0.5)*4000
  F.cars[i]={valid=true,x=c.x or 0,y=0,z=c.z or dz,lookX=0,lookZ=1,kmh=c.kmh or 200,spline=spline,laps=c.laps or 5,position=c.position or (k<3 and k or k+1),
   pitlane=c.pitlane or false,name='Voiture '..i,len=4.7,hit=c.hit or -1,retired=false}
 end
 local link={state=opts.state or 'connected',d=opts.d or {neutral=false,red=false,standing='none'},cars={}}
 for k,c in ipairs(cars) do link.cars[k]=c.lc and (function() local t={valid=true,incident=false,onTrack=true,still=0,halt=false,spin=false,wrong=false}; for a,b in pairs(c.lc) do t[a]=b end; return t end)() or nil end
 link.cars[0]=opts.me and (function() local t={valid=true,incident=false,onTrack=true,still=0,halt=false,spin=false,wrong=false}; for a,b in pairs(opts.me) do t[a]=b end; return t end)() or nil
 local cfg=Config.defaults()
 local ctx={F=F,link=link,say=s,voice=v,cfg=cfg,timing=Timing.new(),now=0,real=0,trackLateral=opts.lateral}
 return ctx,v,s
end
local function at(ctx,t) ctx.now=t; ctx.real=t end
-- Variantes : ton demandé, jamais la même deux fois de suite, coupées par le réglage ; redite jugée sur le sens.
function T.variants_follow_tone_and_never_repeat()
 local v,s=radio(true)
 s.vary=true
 local n=0; s.random=function(k) n=n+1; return 1 end
 local g=Catalog.groups.posGained
 check(g and #g==4,'posGained group: base and 3 variants')
 local a=Say.pick(s,'posGained','motivating'); local b=Say.pick(s,'posGained','motivating')
 check(Catalog.clips[a].tone=='motivating' and Catalog.clips[b].tone=='motivating' and a~=b,'motivating variants, never twice: '..a..' '..b)
 local c=Say.pick(s,'posGained'); check(Catalog.clips[c].tone=='neutral','no tone: neutral one ('..c..')')
 check(Say.pick(s,'push','frustrated')~=nil,'unknown tone in the group: a neutral one')
 check(Say.pick(s,'raceDone','urgent')=='raceDone','clip without variants: itself')
 s.vary=false; check(Say.pick(s,'posGained','motivating')=='posGained','variety off: the base clip')
 -- Tous les groupes : variantes de même nature (aucune variante d'une variante), tons connus.
 for base,list in pairs(Catalog.groups) do
  check(list[1]==base and not Catalog.clips[base].of,'group '..base)
  for k=2,#list do check(Catalog.clips[list[k]].of==base and Catalog.tones[Catalog.clips[list[k]].tone],'variant '..list[k]) end
 end
 -- Redite : la même consigne dite autrement reste une redite de l'ingénieur (repeatGap).
 s.vary=true; v.repeatGap=180
 Say.say(s,'engineer','hold',5,{'hold'},1,{ttl=30,tone='calm'})
 Voice.step(v,1); check(v.current and v.current.key=='hold','first hold said')
 v.current=nil; v.handle=nil
 Say.say(s,'engineer','hold2',5,{'hold'},30,{ttl=30,tone='calm'})
 v.infoAt=-1e9; v.endAt=-1e9
 Voice.step(v,30)
 check(not (v.current and v.current.key=='hold2'),'same instruction, other wording: still a repeat')
end
-- Danger devant : voiture arrêtée en piste à 300 m, joueur à 200 km/h (5,4 s) : dite avec son côté ; à 800 m : rien ;
-- hors piste : priorité 2 ; contresens ; rien sans danger.
function T.hazard_ahead_called_early_with_side()
 local ctx,v=scene({{spline=0.5+300/4000,kmh=0,lc={incident=true,onTrack=true,still=3}}},{lateral=function(x,y,z) return z>100 and -0.6 or 0 end})
 at(ctx,1); Hazards.step(Hazards.new(),ctx)
 local q=queued(v,'hazard')
 check(q and q.prio==1 and q.text:find('arrêtée',1,true) and q.text:find('gauche',1,true) and q.text:find('Passe à droite',1,true),'stopped car on the left, go right: '..tostring(q and q.text))
 -- Trop loin (800 m à 55 m/s : 14 s, dans la portée) : pas encore.
 local ctx2,v2=scene({{spline=0.5+0.2,kmh=0,lc={incident=true,onTrack=true,still=3}}})
 at(ctx2,1); Hazards.step(Hazards.new(),ctx2); check(not queued(v2,'hazard'),'too far: not yet')
 -- Hors de la piste : priorité 2.
 local ctx3,v3=scene({{spline=0.55,kmh=0,lc={incident=true,onTrack=false,still=3}}})
 at(ctx3,1); Hazards.step(Hazards.new(),ctx3)
 local q3=queued(v3,'hazard'); check(q3 and q3.prio==2 and q3.text:find('Hors de la piste',1,true),'off track: prio 2 '..tostring(q3 and q3.text))
 -- Contresens.
 local ctx4,v4=scene({{spline=0.6,kmh=80,lc={wrong=true}}})
 at(ctx4,1); Hazards.step(Hazards.new(),ctx4); check(queued(v4,'hazard') and queued(v4,'hazard').text:find('contresens',1,true),'wrong way')
 -- Rien : voitures normales devant, lente dans une épingle (80 km/h, joueur 200 km/h) : silence.
 local ctx5,v5=scene({{spline=0.52,kmh=180},{spline=0.55,kmh=80}})
 at(ctx5,1); Hazards.step(Hazards.new(),ctx5); check(#v5.queue==0,'no hazard: silent ('..#v5.queue..')')
 -- Jamais plus tard que la 1.2.0 (de 40 à 600 m, à toute vitesse) : 500 m à 200 km/h, réglage actif ou non.
 for _,on in ipairs({true,false}) do
  local c7,v7=scene({{spline=0.5+500/4000,kmh=0,lc={incident=true,onTrack=true,still=3}}})
  c7.cfg.anticipation=on; at(c7,1); Hazards.step(Hazards.new(),c7); check(queued(v7,'hazard'),'500 m: called as in 1.2.0 (anticipation '..tostring(on)..')')
 end
 -- Plus tôt à grande vitesse : 800 m à 300 km/h (9,6 s) ; anticipation coupée : pas avant 600 m.
 local c8,v8=scene({{spline=0.5+0.2,kmh=0,lc={incident=true,onTrack=true,still=3}}},{kmh=300})
 at(c8,1); Hazards.step(Hazards.new(),c8); check(queued(v8,'hazard'),'800 m at 300 km/h: called early')
 local c9,v9=scene({{spline=0.5+0.2,kmh=0,lc={incident=true,onTrack=true,still=3}}},{kmh=300})
 c9.cfg.anticipation=false; at(c9,1); Hazards.step(Hazards.new(),c9); check(not queued(v9,'hazard'),'anticipation off: not before 600 m')
end
-- Accrochage devant : contact entre deux voitures suivi d'une perte de 25 km/h ; frottement sans perte : rien.
function T.tangle_ahead_needs_a_real_loss()
 local ctx,v=scene({{spline=0.6,kmh=180,hit=3},{spline=0.601,kmh=180,hit=2}})
 local h=Hazards.new()
 at(ctx,1); Hazards.step(h,ctx)
 ctx.F.cars[1].kmh=175; ctx.F.cars[2].kmh=176; at(ctx,2.5); Hazards.step(h,ctx)
 check(not queued(v,'tangle'),'light rub: silent')
 ctx.F.cars[1].hit=-1; ctx.F.cars[2].hit=-1; at(ctx,3); Hazards.step(h,ctx)
 ctx.F.cars[1].hit=3; ctx.F.cars[1].kmh=180; at(ctx,40); Hazards.step(h,ctx)
 ctx.F.cars[1].kmh=120; at(ctx,41.5); Hazards.step(h,ctx)
 local q=queued(v,'tangle'); check(q and q.prio==2 and q.text:find('Accrochage',1,true),'tangle ahead: '..tostring(q and q.text))
 check(not q.text:find('débris',1,true),'never debris')
end
-- Voiture qui arrive à gauche depuis l'arrière, plus rapide : « il arrive à gauche » ; plus lente, ou premier tour : rien.
function T.car_coming_alongside()
 local function run(kmh,laps)
  local ctx,v=scene({{x=2.6,z=-15,spline=0.5-15/4000,kmh=kmh}},{laps=laps,state='waiting'})
  ctx.cfg.sideBySide=true; ctx.cfg.gaps=false
  local s=Spotter.new()
  at(ctx,1); Spotter.step(s,ctx)
  return queued(v,'side:incoming')
 end
 local q=run(230,3)
 check(q and q.text:find('gauche',1,true),'faster car coming on the left: '..tostring(q and q.text))
 check(not run(195,3),'slower car behind: silent')
 check(not run(230,0),'first lap of a race: silent')
end
-- Voiture qui arrive de l'arrière puis se met à côté : « il arrive à gauche » puis « voiture à gauche », dans cet ordre,
-- deux transmissions au plus.
function T.incoming_then_alongside_in_order()
 local ctx,v=scene({{x=2.6,z=-13,spline=0.5-13/4000,kmh=220}},{laps=3,state='waiting'})
 ctx.cfg.sideBySide=true; ctx.cfg.gaps=false
 local s=Spotter.new()
 local said={}
 for k=1,40 do
  local t=k*0.1
  ctx.F.cars[1].z=-13+5.6*t
  at(ctx,t); Spotter.step(s,ctx)
  Voice.step(v,t)
 end
 for _,e in ipairs(v.log) do if said[#said]~=e.key then said[#said+1]=e.key end end
 check(said[1]=='side:incoming' and said[2]=='side:left' and #said<=2,'order: '..table.concat(said,', '))
end
-- Dépassement fini : la voiture qui était à gauche est derrière au « dégagé » : « tu es passé, rabats-toi » ; elle est
-- passée devant : « dégagé ».
function T.overtake_completed_said()
 local function run(finalZ)
  local ctx,v=scene({{x=2.6,z=0,spline=0.5,kmh=200}},{state='waiting'})
  ctx.cfg.sideBySide=true; ctx.cfg.gaps=false
  local s=Spotter.new()
  for k=1,20 do at(ctx,k*0.1); Spotter.step(s,ctx); Voice.step(v,k*0.1) end
  ctx.F.cars[1].z=finalZ
  for k=21,40 do at(ctx,k*0.1); Spotter.step(s,ctx) end
  for _,q in ipairs(v.queue) do if q.key:find('side:clear',1,true) then return q end end
  return nil
 end
 local q=run(-12)
 check(q and q.text:find('tu es passé',1,true),'car now behind: you are clear: '..tostring(q and q.text))
 local q2=run(12)
 check(q2 and not q2.text:find('tu es passé',1,true),'car went ahead: plain clear: '..tostring(q2 and q2.text))
end
-- Urgences : contact avec une voiture (perte de 10 km/h) puis bilan ; frottement : rien ; gros choc contre un mur ;
-- suspension ; crevaison une fois ; réglage coupé : rien.
function T.contact_then_damage_report()
 local ctx,v=scene({{spline=0.501,kmh=200}})
 local em=Emergency.new(); ctx.emergency=em
 at(ctx,1); Emergency.step(em,ctx,0.1)
 ctx.F.me.hit=2; at(ctx,1.1); Emergency.step(em,ctx,0.1)
 ctx.F.cars[0].kmh=190; ctx.F.me.damage[1]=30; at(ctx,1.6); Emergency.step(em,ctx,0.1)
 local q=queued(v,'contact'); check(q and q.role=='spotter' and q.text:find('Contact',1,true),'contact called')
 check(Emergency.busy(em,ctx),'engineer aero damage held during the contact')
 ctx.F.me.hit=-1; at(ctx,5); Emergency.step(em,ctx,0.1)
 local r=queued(v,'damage'); check(r and r.role=='engineer' and r.text:find('Dégâts moyens',1,true),'moderate damage report: '..tostring(r and r.text))
 -- Frottement : 2 km/h perdus, aucun dégât : rien.
 local c2,v2=scene({{spline=0.501,kmh=200}})
 local e2=Emergency.new()
 at(c2,1); Emergency.step(e2,c2,0.1); c2.F.me.hit=2; at(c2,1.1); Emergency.step(e2,c2,0.1)
 c2.F.cars[0].kmh=198; at(c2,1.6); Emergency.step(e2,c2,0.1); c2.F.me.hit=-1; at(c2,5); Emergency.step(e2,c2,0.1)
 check(#v2.queue==0,'light rub: nothing said ('..#v2.queue..')')
 -- Mur : 60 km/h perdus, suspension touchée.
 local c3,v3=scene({})
 local e3=Emergency.new()
 at(c3,1); Emergency.step(e3,c3,0.1); c3.F.me.hit=0; at(c3,1.1); Emergency.step(e3,c3,0.1)
 c3.F.cars[0].kmh=140; c3.F.me.susp[2]=0.3; at(c3,1.6); Emergency.step(e3,c3,0.1)
 check(queued(v3,'damage') and queued(v3,'damage').text:find('Gros choc',1,true),'big hit')
 c3.F.me.hit=-1; at(c3,5); Emergency.step(e3,c3,0.1)
 local r3=queued(v3,'damage'); check(r3 and r3.text:find('Suspension',1,true),'suspension report: '..tostring(r3 and r3.text))
 -- Crevaison : une fois.
 local c4,v4=scene({})
 local e4=Emergency.new()
 c4.F.me.tyres[2].blown=true
 for k=1,10 do at(c4,k); Emergency.step(e4,c4,0.1) end
 check(count(v4,'puncture')==1 and queued(v4,'puncture').prio==1,'puncture once')
 -- Réglage coupé.
 local c5,v5=scene({{spline=0.501,kmh=200}})
 c5.cfg.emergencies=false
 local e5=Emergency.new()
 at(c5,1); Emergency.step(e5,c5,0.1); c5.F.me.hit=0; at(c5,1.1); Emergency.step(e5,c5,0.1); c5.F.cars[0].kmh=100; at(c5,1.6); Emergency.step(e5,c5,0.1)
 check(#v5.queue==0,'emergencies off: silent')
 -- Mêlée : cinq contacts de 10 km/h en 24 s, sans dégâts : un « contact » toutes les 15 s au plus (deux), au plus un bilan.
 local c6,v6=scene({{spline=0.501,kmh=200}})
 local e6=Emergency.new()
 local n6,d6=0,0
 for k=0,4 do
  local t0=1+k*6
  c6.F.cars[0].kmh=200; at(c6,t0); Emergency.step(e6,c6,0.1)
  c6.F.me.hit=2; at(c6,t0+0.1); Emergency.step(e6,c6,0.1)
  c6.F.cars[0].kmh=190; at(c6,t0+0.6); Emergency.step(e6,c6,0.1)
  c6.F.me.hit=-1; at(c6,t0+4); Emergency.step(e6,c6,0.1)
  for _,q in ipairs(v6.queue) do if q.key=='contact' then n6=n6+1 elseif q.key=='damage' then d6=d6+1 end end
  v6.queue={}
 end
 check(n6==2 and d6<=1,'scrum over 24 s: one contact call per 15 s ('..n6..'), at most one report ('..d6..')')
end
-- Tête-à-queue du joueur : voitures en approche, « reste sur les freins », puis « c'est libre, vas-y » quand elles sont
-- passées ; sans voiture : « c'est libre, repars quand tu es prêt » ; grille de départ : rien.
function T.spin_guided_rejoin()
 local ctx,v=scene({{spline=0.5-150/4000,kmh=200}},{kmh=5,me={spin=true,incident=true}})
 local em=Emergency.new()
 at(ctx,1); Emergency.step(em,ctx,0.1)
 local q=queued(v,'stranded'); check(q and q.prio==1 and q.text:find('Reste sur les freins',1,true),'spin, cars coming: '..tostring(q and q.text))
 v.queue={}
 -- La voiture est passée : plus personne.
 ctx.F.cars[1].spline=0.52
 for k=1,15 do at(ctx,1+k*0.1); Emergency.step(em,ctx,0.1) end
 local g=queued(v,'stranded'); check(g and g.text:find('libre, vas-y',1,true),'go now once clear: '..tostring(g and g.text))
 local c2,v2=scene({{spline=0.9,kmh=200}},{kmh=5,me={spin=true,incident=true}})
 at(c2,1); Emergency.step(Emergency.new(),c2,0.1)
 local q2=queued(v2,'stranded'); check(q2 and q2.text:find('repars quand',1,true),'spin, nobody coming: '..tostring(q2 and q2.text))
 local c3,v3=scene({{spline=0.49,kmh=0}},{kmh=0,d={neutral=false,red=false,standing='grid'}})
 local e3=Emergency.new()
 for k=1,40 do at(c3,k*0.1); Emergency.step(e3,c3,0.1) end
 check(#v3.queue==0,'standing on the grid: silent')
end
-- Position en direct : place gagnée en piste et tenue 2,5 s : dite tout de suite (« superbe dépassement » au ton
-- motivant) ; place perdue en piste ; place prise à un arrêt : rien ici.
function T.live_position_calls()
 local ctx,v,s=scene({{spline=0.51,position=2},{spline=0.49,position=4}},{pos=3})
 local e=Engineer.new()
 local me=ctx.F.cars[0]
 local function step() Engineer.livePosition(e,ctx,me) end
 at(ctx,1); step()
 -- Le joueur double la voiture 1.
 me.position=2; ctx.F.cars[1].position=3
 at(ctx,2); step(); check(not queued(v,'position'),'not before 2.5 s')
 at(ctx,4.6); step()
 local q=queued(v,'position'); check(q and q.text:find('Tu es P2',1,true) and q.tone=='motivating','gained on track: '..tostring(q and q.text))
 v.queue={}; v.last={}
 -- La voiture 2 le passe.
 me.position=3; ctx.F.cars[2].position=2
 at(ctx,60); step(); at(ctx,63); step()
 local l=queued(v,'position'); check(l and l.text:find('P3',1,true) and l.text:find('passé',1,true) and l.tone=='frustrated','lost on track: '..tostring(l and l.text))
 v.queue={}; v.last={}
 -- Une voiture devant rentre aux stands : place prise sans dépassement, rien ici.
 e.pitted[2]=true
 at(ctx,100); step()
 me.position=2; ctx.F.cars[2].position=3
 at(ctx,101); step(); at(ctx,104); step()
 check(not queued(v,'position'),'place taken at a stop: not called live')
end
-- Écarts en direct : voiture devant qui entre dans la seconde, une fois, réarmée au-dessus de 1,4 s.
function T.live_gaps_within_a_second()
 local ctx,v=scene({{spline=0.5,position=2},{spline=0.5,position=4}},{pos=3,state='waiting'})
 ctx.cfg.sideBySide=false; ctx.cfg.gaps=true; ctx.cfg.gapEvery=99
 local s=Spotter.new()
 local gap=2.0
 local tm=require('src/timing')
 local real=tm.gap
 tm.gap=function(t,a,b) if a==1 then return gap end return 3.0 end
 local ok,err=pcall(function()
  for k=1,4 do at(ctx,k); Spotter.step(s,ctx) end
  check(not queued(v,'inSecond'),'2 s ahead: silent')
  gap=0.9; at(ctx,5); Spotter.step(s,ctx)
  check(queued(v,'inSecond'),'within a second: said')
  v.queue={}; v.last={}
  gap=0.8; at(ctx,6); Spotter.step(s,ctx); check(not queued(v,'inSecond'),'once per episode')
  gap=1.6; at(ctx,7); Spotter.step(s,ctx); gap=0.9; at(ctx,8); Spotter.step(s,ctx)
  check(queued(v,'inSecond'),'re-armed above 1.4 s')
 end)
 tm.gap=real
 if not ok then error(err,0) end
end
-- Stratégie commentée : undercut décidé (arrêt ce tour-ci dans la fenêtre, coût toléré) -> « on tente l'undercut, box
-- ce tour-ci », box engagé et plan publié en boxnow ; hors fenêtre : dit comme une possibilité ; réglage coupé : idem.
function T.undercut_decided_and_published()
 local function run(window,talk)
  local ctx,v=scene({},{laps=9})
  ctx.F.cars[0].spline=0.02; ctx.cfg.strategyTalk=talk
  local t=Strategist.new()
  t.ready=true; t.plan={ok=true,optimal=11,window=window,costs={[1]=100.5},cost=100,stops=1}
  t.duel={undercut=true,undercutGap=1.2}
  Strategist.announce(t,ctx,true)
  ctx.F.cars[0].spline=0.2
  return t,v,Strategist.pitplan(t,ctx,true)
 end
 local t,v,plan=run({8,12},true)
 local q=queued(v,'box'); check(q and q.text:find("On tente l'undercut",1,true) and q.text:find('Box, box, ce tour-ci',1,true) and q.text:find('+1,2 s',1,true),'undercut decided: '..tostring(q and q.text))
 check(t.boxLap==10 and plan:find('state=boxnow',1,true) and plan:find('lap=10',1,true),'box committed and published: '..plan)
 local t2,v2=run({11,14},true)
 check(not t2.boxLap and queued(v2,'duel') and queued(v2,'duel').text:find('Undercut possible',1,true),'outside the window: only possible')
 local t3,v3=run({8,12},false)
 check(not t3.boxLap and queued(v3,'duel'),'strategy talk off: as before')
end
-- Neutralisation : arrêt rentable dit avec ce qu'il fait gagner ; pas rentable : « on reste dehors » une fois.
function T.neutral_box_with_gain_or_stay_out()
 local ctx,v=scene({},{laps=9,d={neutral=true,neutralFor=8,red=false,standing='none',pitsClosed=false}})
 ctx.F.cars[0].spline=0.3
 local t=Strategist.new()
 t.ready=true; t.model={pitLane=22}; t.plan={ok=true,optimal=15,window={8,20},costs={[1]=105},cost=100,stops=1}
 Strategist.boxCalls(t,ctx)
 local q=queued(v,'boxNeutral'); check(q and q.text:find('neutralisation',1,true) and q.text:find('On gagne environ',1,true),'neutral box with gain: '..tostring(q and q.text))
 local c2,v2=scene({},{laps=9,d={neutral=true,neutralFor=8,red=false,standing='none',pitsClosed=false}})
 c2.F.cars[0].spline=0.3
 local t2=Strategist.new()
 t2.ready=true; t2.model={pitLane=22}; t2.plan={ok=true,optimal=15,window={8,20},costs={[1]=130},cost=100,stops=1}
 Strategist.boxCalls(t2,c2); Strategist.boxCalls(t2,c2)
 check(count(v2,'stayOut')==1 and not queued(v2,'boxNeutral'),'not worth it: stay out, once')
end
return T
