-- Assertions communes aux fichiers de tests (tests/*_spec.lua).
local M={}
function M.check(c,msg) if not c then error(msg or 'check',2) end end
function M.near(a,b,eps,msg) if math.abs(a-b)>(eps or 1e-6) then error((msg or 'near')..': '..tostring(a)..' ~= '..tostring(b),2) end end
return M
