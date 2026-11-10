-- Bilan de fin de course (1.2.0, demande du pilote : « tu as fini, tu es P2, parti de telle place, tu as dépassé tant de
-- voitures, belle course, bravo »). Le spotter annonce l'arrivée et la place (src/spotter.lua) ; l'ingénieur fait le
-- bilan quelques secondes plus tard : places gagnées ou perdues depuis le départ, dépassements en piste, meilleur tour
-- de la course, verdict ; écrits seulement : départ et arrivée, meilleur tour, fois où le joueur a été dépassé.
-- Dépassements comptés ici (le pont ne les donne pas) : ordre de deux voitures sur la progression continue (tours +
-- position sur le tour, src/timing.lua), qui change quand l'une passe l'autre sur la piste. Une voiture prise d'un tour
-- (ou qui prend un tour au joueur) ne change pas cet ordre : seuls les vrais dépassements pour la place comptent.
-- Voitures dans la voie des stands ou abandonnées : ordre oublié (un arrêt n'est pas un dépassement). Module pur.
local Timing=require('src/timing')
local M={}
-- Écart minimal (m) pour que l'ordre change (côte à côte : pas de compte à chaque image) ; délai du bilan après
-- l'arrivée (s), le temps que le spotter annonce la place ; écart de place qui fait une remontée ou une course difficile.
M.HYSTERESIS=8
M.DELAY=5
M.SWING=3
function M.new() return {order={},made=0,lost=0,grid=0,at=nil,said=false,stale=false} end
-- Résultat d'AdvancedIA déjà « fini » pendant la course (il ne le remet à zéro qu'au changement de séance, pas au
-- redémarrage d'une même course) : périmé, jamais lu pour le bilan de cette course.
function M.fresh(st,d) if st.stale then return nil end return d end
-- Une image de course (départ donné, joueur pas arrivé) : ordre de chaque voiture par rapport au joueur, dépassements ;
-- d : données du pont (résultat d'AdvancedIA déjà fini avant l'arrivée : périmé).
function M.step(st,F,t,d)
 if not F.isRace or not F.started then return end
 local me=F.cars[F.player]
 if not me or not me.valid or me.finished or F.finishedSession then return end
 if d and d.finished then st.stale=true end
 if st.grid==0 and (tonumber(me.position) or 0)>0 then st.grid=me.position end
 local mine=Timing.car(t,F.player)
 if not mine.progress or me.pitlane then for k in pairs(st.order) do st.order[k]=nil end; return end
 local h=M.HYSTERESIS/math.max(500,F.trackLength or 0)
 for i=0,F.count-1 do
  local c=F.cars[i]
  local tc=i~=F.player and c and c.valid and not c.pitlane and not c.retired and t.cars[i]
  if tc and tc.seen and tc.progress then
   local d=mine.progress-tc.progress
   local now=d>h and 1 or d<-h and -1 or nil
   local was=st.order[i]
   if now and was and now~=was then if now==1 then st.made=st.made+1 else st.lost=st.lost+1 end end
   if now then st.order[i]=now end
  else st.order[i]=nil end
 end
end
-- Place classée : corrigée des pénalités en temps (AdvancedIA), sinon place d'arrivée, sinon place d'AC.
function M.place(d,me)
 if d and (d.correctedPosition or 0)>0 then return d.correctedPosition end
 if d and (d.finalPosition or 0)>0 then return d.finalPosition end
 return tonumber(me and me.position) or 0
end
-- Le spotter annonce l'arrivée et la place (rôle Spotter et section Drapeaux actifs) ; sinon l'ingénieur le fait.
function M.spotterSays(cfg) return cfg.spotterOn~=false and cfg.raceControl==true end
-- Place de départ : grille d'AdvancedIA, sinon la place au départ vue ici.
function M.grid(st,d) if d and (d.gridPosition or 0)>0 then return d.gridPosition end return st.grid end
-- Meilleur tour du joueur (s, 0 sans tour) et vrai s'il est le plus rapide de la course.
function M.best(F)
 local me=F.cars[F.player]
 local mine=me and tonumber(me.bestMs) or 0
 if mine<=0 then return 0,false end
 for i=0,F.count-1 do
  local c=F.cars[i]
  if i~=F.player and c and c.valid and (tonumber(c.bestMs) or 0)>0 and c.bestMs<mine then return mine/1000,false end
 end
 return mine/1000,true
end
-- Verdict (clip) selon la place, la place de départ, l'abandon ou la disqualification.
function M.verdict(place,grid,dnf,dq)
 if dq then return 'debriefDq' end
 if dnf or place<=0 then return 'debriefDnf' end
 local gain=grid>0 and grid-place or 0
 if place==1 then return 'debriefWin' end
 if place<=3 then return 'debriefPodium' end
 if gain<=-M.SWING then return 'debriefTough' end
 if place<=5 then return 'debriefTop5' end
 if place<=10 then return 'debriefTop10' end
 if gain>=M.SWING then return 'debriefComeback' end
 return 'debriefOther'
end
-- Parties de la phrase de l'ingénieur ; withPlace : arrivée et place en tête (spotter muet). note(id,…) : précision
-- écrite dans la langue de la radio (Say.note) ; lapText(s) : meilleur tour écrit.
function M.parts(st,F,d,withPlace,note,lapText)
 local me=F.cars[F.player]
 local place=M.place(d,me); local grid=M.grid(st,d)
 local dnf=d and d.dnf or false; local dq=d and d.dq or false
 local parts={}
 if withPlace and place>0 and not dnf and not dq then parts[#parts+1]='raceOver'; parts[#parts+1]={pos=place} end
 if not dnf and not dq and place>0 then
  if grid>0 then parts[#parts+1]={text=note('debriefPlaces',grid,place)} end
  local gain=grid>0 and grid-place or nil
  if gain and gain>0 then parts[#parts+1]={n=gain}; parts[#parts+1]='placesGained'
  elseif gain and gain<0 then parts[#parts+1]={n=-gain}; parts[#parts+1]='placesLost'
  elseif gain==0 then parts[#parts+1]='placeKept' end
 end
 if st.made>0 then parts[#parts+1]={n=st.made}; parts[#parts+1]='overtakes' end
 if st.lost>0 then parts[#parts+1]={text=note('debriefPassed',st.lost)} end
 local best,fastest=M.best(F)
 if best>0 then parts[#parts+1]={text=note('debriefBest',lapText(best))} end
 if fastest and not dq then parts[#parts+1]='fastestLap' end
 parts[#parts+1]=M.verdict(place,grid,dnf,dq)
 return parts
end
return M
