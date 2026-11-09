-- Position du joueur à la radio : voisins au classement, tours restants, dépassements, conseil du dernier tour, seuils
-- d'écart et de rythme des consignes. Module pur, partagé par l'ingénieur (« Tu es P5 » quand la place change, avec la
-- consigne de la ligne), le spotter (« Dernier tour ! Tu es P7 » et le conseil, en une seule transmission ; écarts) et
-- les overlays (voitures devant et derrière).
local Timing=require('src/timing')
local M={}
-- Seuils des consignes (s). Écarts : attaque (voiture devant à portée), chasse (rattrapable si plus rapide), défense
-- (voiture derrière qui revient), garder la position (personne autour), pneus (personne ne menace derrière) ; dernier
-- tour : défends, donne tout. Rythme (s/tour, médiane des 3 derniers tours propres) : chasse, comparaison, défense,
-- rattrapable avant l'arrivée.
M.GAP={attack=1.0,chase=2.5,compare=6,defend=1.5,hold=4,tyres=2,lastDefend=0.8,lastReach=1.2}
M.PACE={chase=0.15,compare=0.1,defend=0.1,reach=0.05,laps=3}
-- Voiture classée à cette place (indice), ou nil ; place inconnue (0) : nil.
function M.byPosition(F,pos)
 if not pos or pos<=0 then return nil end
 for i=0,F.count-1 do local c=F.cars[i]; if c.valid and c.position==pos then return i end end
 return nil
end
-- Voitures devant et derrière au classement d'AC (indices), ou nil ; place du joueur inconnue : aucune.
function M.neighbours(F,me)
 local pos=tonumber(me.position) or 0
 if pos<=0 then return nil,nil end
 return M.byPosition(F,pos-1),M.byPosition(F,pos+1)
end
-- Tours restants au joueur (plan de l'ingénieur, qui compte les tours de retard et les courses au temps ; sinon
-- nombre de tours de la séance), ou nil (inconnu).
function M.lapsLeft(F,me,plan)
 local total=plan and plan.total or F.laps
 if not total or total<=0 then return nil end
 return math.max(0,total-me.laps)
end
-- Course finie pour le joueur (damier d'AdvancedIA).
function M.finished(d)
 return d and (d.finished or d.panelDecided=='checkered' or d.panelDecided=='finish') or false
end
-- Dernier tour du joueur : panneau d'AdvancedIA (white : un tour restant), ou tours restants du plan (l'annonce à la
-- ligne précède parfois le panneau d'une image).
function M.lastLap(F,me,d,plan)
 if d and d.panelDecided=='white' then return true end
 local left=M.lapsLeft(F,me,plan)
 return left~=nil and left<=1
end
-- Voitures classées devant le joueur (ensemble d'indices, table réutilisée), pour juger un dépassement à la ligne
-- suivante.
function M.aheadOf(F,me,into)
 for k in pairs(into) do into[k]=nil end
 local pos=tonumber(me.position) or 0
 for i=0,F.count-1 do local c=F.cars[i]; if c.valid and i~=F.player and pos>0 and c.position>0 and c.position<pos then into[i]=true end end
 return into
end
-- Place gagnée en piste depuis la ligne précédente : une voiture qui était devant est maintenant derrière, sans être
-- passée par la voie des stands entre-temps (une place prise à un arrêt ou à un abandon n'est pas un dépassement).
function M.overtook(F,me,ahead,pitted)
 local pos=tonumber(me.position) or 0
 if pos<=0 then return false end
 for i in pairs(ahead) do
  local c=F.cars[i]
  if c and c.valid and c.position>pos and not pitted[i] and not c.retired then return true end
 end
 return false
end
-- Conseil du dernier tour : voiture juste derrière (défends), voiture devant à portée (donne tout), sinon ramène la
-- voiture. Les deux proches : la plus proche décide.
function M.lastLapAdvice(ctx)
 local F=ctx.F; local me=F.cars[F.player]
 if not me or not me.valid then return nil end
 local ahead,behind=M.neighbours(F,me)
 local ga=ahead and Timing.gap(ctx.timing,ahead,F.player,ctx.now) or nil
 local gb=behind and Timing.gap(ctx.timing,F.player,behind,ctx.now) or nil
 local close=gb and gb<M.GAP.lastDefend
 local reach=ga and ga<M.GAP.lastReach
 if close and (not reach or gb<=ga) then return 'lastDefend' end
 if reach then return 'lastReach' end
 return 'lastSafe'
end
-- Parties ajoutées à « Dernier tour ! » : position (si connue) et conseil.
function M.lastLapParts(ctx)
 local F=ctx.F; local me=F.cars[F.player]
 if not me or not me.valid or (tonumber(me.position) or 0)<=0 then return nil end
 return {{pos=me.position},M.lastLapAdvice(ctx)}
end
-- Le spotter dira la position avec « Dernier tour ! » (rôle, direction de course et réglage actifs).
function M.spotterSaysLastLap(cfg) return cfg.spotterOn~=false and cfg.raceControl and cfg.positionCalls or false end
return M
