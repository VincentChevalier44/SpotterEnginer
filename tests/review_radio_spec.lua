-- Revue de la radio (10/11/2026) : nombres de 100 à 999, redite jugée sur la valeur dite, information retardée et non
-- perdue, file écartée (liaison suspendue, rôle coupé, langue changée), annonces entendues gardées au rechargement.
local Voice=require('src/voice')
local Say=require('src/say')
local Catalog=require('src/catalog')
local T={}
local check=require('tests/helpers').check
-- Radio dont chaque clip dure 1 s sur l'horloge du test (clock.t).
local function radio(lang,without)
 local clock={t=0}
 local port={play=function(p) return {p=p,stop=clock.t+1} end,playing=function(h) return clock.t<h.stop end,stop=function() end}
 local v=Voice.new(port)
 local files={}
 Catalog.eachFile(function(rel) if rel~=without then files[rel]=true end end)
 local s=Say.new(v,files,'vox',lang or 'FR')
 local said={}
 v.onEvent=function(kind,e) if kind=='radio' then said[#said+1]=e end end
 local function run(to,step) while clock.t<to do clock.t=clock.t+(step or 0.1); Voice.step(v,clock.t) end end
 return v,s,clock,run,said
end
local function names(list) local out={}; for k,p in ipairs(list or {}) do out[k]=p:match('([^/]+/[^/]+)%.wav$') or p end; return table.concat(out,' ') end
-- 100 à 999 : « cent » + reste, chiffre + « cent » + reste ; anglais : chiffre + « hundred » + reste ; reste nul : rien de
-- plus ; au-delà de 999, ou clip « cent » absent : écrit seulement. Le texte écrit reste le nombre en chiffres.
function T.numbers_from_100_to_999_are_spoken()
 local v,s=radio('FR')
 local function clips(n) return names(Say.paths(s,Say.expand(s,{'optimalLap',{n=n}}))) end
 check(clips(99)=='FR/87_tour_optimal num/99','99 unchanged: '..clips(99))
 check(clips(100)=='FR/87_tour_optimal FR/228_cent','100: '..clips(100))
 check(clips(105)=='FR/87_tour_optimal FR/228_cent num/05','105: '..clips(105))
 check(clips(199)=='FR/87_tour_optimal FR/228_cent num/99','199: '..clips(199))
 check(clips(200)=='FR/87_tour_optimal num/02 FR/228_cent','200: '..clips(200))
 check(clips(999)=='FR/87_tour_optimal num/09 FR/228_cent num/99','999: '..clips(999))
 check(Say.paths(s,Say.expand(s,{'optimalLap',{n=1000}}))==nil,'1000: written only')
 check(Say.text(s,{'optimalLap',{n=105}})=='Tour optimal : 105','written text unchanged: '..Say.text(s,{'optimalLap',{n=105}}))
 check(Say.say(s,'engineer','w',3,{'pitWindow',{n=98},'toLap',{n=104},'optimalLap',{n=101}},0,{}) and v.queue[1].clips and #v.queue[1].clips==8,
  'pit window over lap 99 is spoken: '..tostring(v.queue[1] and v.queue[1].clips and #v.queue[1].clips))
 local _,en=radio('EN')
 local function clipsEN(n) return names(Say.paths(en,Say.expand(en,{'optimalLap',{n=n}}))) end
 check(clipsEN(100)=='EN/87_optimal_lap num/01 EN/228_hundred','EN 100: '..clipsEN(100))
 check(clipsEN(342)=='EN/87_optimal_lap num/03 EN/228_hundred num/42','EN 342: '..clipsEN(342))
 -- Clip « cent » absent : comme avant, écrit seulement.
 local v2,s2=radio('FR','FR/228_cent.wav')
 check(Say.say(s2,'engineer','w',3,{'optimalLap',{n=105}},0,{}) and v2.queue[1].clips==nil and v2.queue[1].text=='Tour optimal : 105','no clip: written only')
 -- Un écart de 120 s (arrondi à la seconde) se dit aussi.
 check(names(Say.paths(s,Say.expand(s,{{n=120.4,dec=1,unit='s'}})))=='FR/228_cent num/20 FR/82_secondes','120 s: '..names(Say.paths(s,Say.expand(s,{{n=120.4,dec=1,unit='s'}}))))
end
-- Redite jugée sur la valeur dite : « moins 0,4 tour » calculé 0,43 puis 0,41 est la même annonce (repeatGap) ; une autre
-- valeur dite est une autre annonce.
function T.repeat_judged_on_the_spoken_value()
 local v,s,clock,run,said=radio('FR')
 local function fuel(delta) return Say.say(s,'engineer','fuel',3,{'liftCoast','fuelTarget','minus',{n=delta,dec=1},'laps'},clock.t,{ttl=15}) end
 fuel(0.4348); run(10)
 check(#said==1 and said[1].spoken,'first call said')
 fuel(0.4127); run(20)
 check(#said==1,'same spoken value within repeatGap: not said again ('..#said..')')
 fuel(0.61); run(30)
 check(#said==2 and said[2].text:find('0,6',1,true),'another spoken value is said: '..#said)
 local n=0; for _ in pairs(v.heard) do n=n+1 end
 check(n==2,'one memory entry per spoken value: '..n)
end
-- Trois informations de l'ingénieur à la ligne : chacune attend son tour (infoGap) et est dite, aucune ne périme derrière
-- le rythme ; une information d'un instant (ttl court) périme comme elle le demande ; le spotter n'est pas concerné.
function T.information_waits_its_turn_instead_of_expiring()
 local v,s,clock,run,said=radio('FR')
 local expired={}
 local on=v.onEvent; v.onEvent=function(kind,e) on(kind,e); if kind=='expired' then expired[#expired+1]=e.key end end
 Say.say(s,'engineer','a',5,{'goodPace'},0,{ttl=15})
 Say.say(s,'engineer','b',4,{'fuelOk'},0,{ttl=15})
 Say.say(s,'engineer','c',4,{'noMoreStops'},0,{ttl=15})
 Say.say(s,'engineer','d',5,{'gripUp'},0,{ttl=4})
 run(45)
 check(#said==3 and #expired==1 and expired[1]=='d','three said, the short-lived one expired: '..#said..' said, '..table.concat(expired,','))
 check(said[2].at-said[1].at>=v.infoGap and said[3].at-said[2].at>=v.infoGap,'pacing kept between them')
 -- Rythme réglé très long : jamais dite plus de 45 s après.
 local v2,s2,clock2,run2,said2=radio('FR')
 v2.infoGap=60
 Say.say(s2,'engineer','a',4,{'goodPace'},0,{ttl=15}); run2(5)
 Say.say(s2,'engineer','b',4,{'fuelOk'},clock2.t,{ttl=15}); run2(80)
 check(#said2==1 and #v2.queue==0,'long pacing: dropped after 45 s, never said a minute late ('..#said2..')')
end
-- File écartée : tout sauf l'essai de la voix, la phrase en cours finit ; avec coupure, la phrase en cours aussi.
function T.queue_purged_keeps_the_voice_test()
 local v,s,clock,run,said=radio('FR')
 local function notTest(q) return q.key:sub(1,5)~='test:' end
 Say.say(s,'spotter','flag',2,{'yellow'},0,{}); run(0.2)
 Say.say(s,'engineer','fuel',3,{'fuelOk'},clock.t,{})
 Say.say(s,'spotter','test:spotter',1,{'green'},clock.t,{ttl=5})
 Voice.purge(v,notTest)
 check(Voice.busy(v) and v.current.key=='flag' and #v.queue==1 and v.queue[1].key=='test:spotter','current kept, queue holds the test only')
 Voice.purge(v,notTest,true)
 check(v.current==nil,'cut: the current call is stopped too')
 run(3); check(said[#said].key=='test:spotter' and said[#said].spoken,'the voice test is still said')
 -- Rôle coupé : ses annonces en attente seulement.
 Say.say(s,'spotter','x',3,{'blue'},clock.t,{}); Say.say(s,'engineer','y',3,{'fuelOk'},clock.t,{})
 Voice.purge(v,function(q) return q.role=='engineer' end)
 check(#v.queue==1 and v.queue[1].role=='spotter','role purge')
end
-- Annonces entendues : exportées avec leur âge (les plus récentes, dans repeatGap), relues après un rechargement ;
-- l'ingénieur ne redit pas ce qu'il vient de dire.
function T.heard_calls_survive_a_reload()
 local v,s,clock,run,said=radio('FR')
 local stored
 v.onHeard=function() stored=Voice.heardText(v,clock.t) end
 Say.say(s,'engineer','wear',3,{'abnormalWear'},0,{}); run(5)
 check(#said==1 and type(stored)=='string' and stored:find('^abnormalWear\t%d+$'),'heard exported: '..tostring(stored))
 -- Rechargement : radio neuve, horloge quelconque.
 local v2,s2,clock2,run2,said2=radio('FR')
 clock2.t=1000
 check(Voice.heardLoad(v2,stored,clock2.t)==1,'heard loaded')
 Say.say(s2,'engineer','wear',3,{'abnormalWear'},clock2.t,{}); run2(1010)
 check(#said2==0,'not said again after the reload')
 clock2.t=clock2.t+v2.repeatGap
 Say.say(s2,'engineer','wear',3,{'abnormalWear'},clock2.t,{}); run2(clock2.t+10)
 check(#said2==1,'said again after repeatGap')
 -- Borné : 40 au plus, jamais ce qui est plus vieux que repeatGap ; texte illisible : rien.
 local v3=Voice.new({})
 for k=1,60 do v3.heard['s'..k]=k end
 v3.heard['old']=-500
 local text=Voice.heardText(v3,61)
 local n=0; for _ in text:gmatch('[^\n]+') do n=n+1 end
 check(n==40 and not text:find('old',1,true) and text:find('^s60\t1\n'),'bounded, most recent first: '..n)
 check(Voice.heardLoad(v3,nil,0)==0 and Voice.heardLoad(v3,'',0)==0,'nothing to load')
end
return T
