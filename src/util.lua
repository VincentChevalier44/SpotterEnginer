-- Outils purs (aucune fonction de CSP) : bornes, nombres finis, moyennes glissantes, formats de temps, remise à neuf.
local U={}
function U.finite(x) return type(x)=='number' and x==x and x~=math.huge and x~=-math.huge end
function U.clamp(x,lo,hi) if x<lo then return lo elseif x>hi then return hi end return x end
-- Écart sur un tour fermé : différence de positions (0..1) ramenée dans ]-0,5 ; 0,5].
function U.wrap(d) d=d%1; if d>0.5 then d=d-1 end; return d end
-- Moyenne glissante exponentielle : v nil -> première valeur.
function U.ewma(v,x,k) if v==nil then return x end return v+(x-v)*k end
-- Médiane d'une liste (copie triée, la liste n'est pas modifiée).
function U.median(list,n)
 n=n or #list
 if n==0 then return nil end
 local t={}; for i=1,n do t[i]=list[i] end
 table.sort(t)
 if n%2==1 then return t[(n+1)/2] end
 return (t[n/2]+t[n/2+1])*0.5
end
-- Régression linéaire y=a+b*x sur des couples ; renvoie a, b, n (b=0 si un seul point ou x constant).
function U.linear(xs,ys,n)
 n=n or #xs
 if n==0 then return nil,0,0 end
 local sx,sy,sxx,sxy=0,0,0,0
 for i=1,n do local x,y=xs[i],ys[i]; sx=sx+x; sy=sy+y; sxx=sxx+x*x; sxy=sxy+x*y end
 local d=n*sxx-sx*sx
 if n<2 or math.abs(d)<1e-12 then return sy/n,0,n end
 local b=(n*sxy-sx*sy)/d
 return (sy-b*sx)/n,b,n
end
-- Tampon circulaire de taille fixe (aucune table créée après le premier tour).
function U.ring(size) return {size=size,n=0,at=0,v={}} end
function U.push(r,x) r.at=r.at%r.size+1; r.v[r.at]=x; if r.n<r.size then r.n=r.n+1 end end
-- k-ième valeur la plus récente (1 = la dernière).
function U.recent(r,k) if k>r.n then return nil end local i=(r.at-k)%r.size+1; return r.v[i] end
-- Temps au tour « 1:42.356 » (séparateur décimal donné).
function U.lapTime(s,mark)
 if not U.finite(s) or s<=0 then return '-:--.---' end
 local m=math.floor(s/60); local r=s-m*60
 local out=string.format('%d:%06.3f',m,r)
 if mark and mark~='.' then out=out:gsub('%.',mark) end
 return out
end
-- Formats prêts (pas de concaténation à chaque nombre affiché).
local FIXED={[0]='%.0f','%.1f','%.2f','%.3f'}
local SIGNED={[0]='%+.0f','%+.1f','%+.2f','%+.3f'}
-- Écart signé « +1.2 » / « -0.45 » (décimales données).
function U.gap(s,decimals,mark)
 if not U.finite(s) then return '--' end
 local d=decimals or 1
 local out=string.format(SIGNED[d] or ('%+.'..d..'f'),s)
 if mark and mark~='.' then out=out:gsub('%.',mark) end
 return out
end
function U.fixed(s,decimals,mark)
 if not U.finite(s) then return '--' end
 local d=decimals or 1
 local out=string.format(FIXED[d] or ('%.'..d..'f'),s)
 if mark and mark~='.' then out=out:gsub('%.',mark) end
 return out
end
-- Tours « T12 », ou plage « T12 – T18 ».
function U.lapRange(a,b) if a==b then return string.format('T%d',a) end return string.format('T%d – T%d',a,b) end
-- État remis à neuf (changement de séance) : toutes les clés effacées, y compris celles qu'un état neuf n'a pas
-- (valeurs nil, clés ajoutées en cours de route), puis l'état neuf recopié ; keep : clés gardées (appris par circuit).
function U.refill(t,fresh,keep)
 local kept={}
 for _,k in ipairs(keep or {}) do kept[k]=t[k] end
 for k in pairs(t) do t[k]=nil end
 for k,v in pairs(fresh) do t[k]=v end
 for _,k in ipairs(keep or {}) do t[k]=kept[k] end
 return t
end
return U
