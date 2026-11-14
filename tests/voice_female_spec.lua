-- Voix du spotter (1.3.9) : féminine pour le spotter (clips du spotter seul à leur place, copies de F/ pour les clips
-- communs, nombres, durées et positions), masculine pour l'ingénieur ; sans copie féminine, le clip lui-même.
local Say=require('src/say')
local Voice=require('src/voice')
local Catalog=require('src/catalog')
local check=require('tests/helpers').check
local T={}
local function sayer(files)
 local v=Voice.new({play=function() return {} end,playing=function() return false end,stop=function() end})
 return Say.new(v,files,'vox','FR',nil),v
end
function T.spotter_female_engineer_male()
 local files={}
 local gap=Catalog.clips.pitOpen.FR
 files['FR/'..gap]=true; files['FR/F/'..gap]=true
 files['FR/num/07.wav']=true; files['FR/F/num/07.wav']=true
 files['FR/'..Catalog.clips.green.FR]=true
 local s,v=sayer(files)
 Say.say(s,'spotter','a',3,{'pitOpen',{n=7}},0,{})
 local q=v.queue[#v.queue]
 check(q and q.clips[1]=='vox/FR/F/'..gap and q.clips[2]=='vox/FR/F/num/07.wav','spotter: female copies of the shared clip and the number')
 Say.say(s,'engineer','b',3,{'pitOpen',{n=7}},0,{})
 q=v.queue[#v.queue]
 check(q and q.clips[1]=='vox/FR/'..gap and q.clips[2]=='vox/FR/num/07.wav','engineer: male voice')
 Say.say(s,'spotter','c',3,{'green'},0,{})
 q=v.queue[#v.queue]
 check(q and q.clips[1]=='vox/FR/'..Catalog.clips.green.FR,'spotter-only clip: in its place (female file)')
 files['FR/F/num/07.wav']=nil
 Say.say(s,'spotter','d',3,{{n=7}},0,{})
 q=v.queue[#v.queue]
 check(q and q.clips[1]=='vox/FR/num/07.wav','no female copy: the clip itself, never silence')
end
function T.voice_lists_consistent()
 check(#Catalog.spotterOnly>50 and #Catalog.shared>10,'lists filled')
 check(Catalog.femaleVoices.FR=='fr-FR-DeniseNeural' and Catalog.femaleVoices.EN=='en-US-JennyNeural','voices chosen by the driver')
 local was=Say.strict
 local ok=pcall(function() local s=sayer({}); Say.strict=true; Say.say(s,'engineer','x',3,{'green'},0,{}) end)
 Say.strict=was
 check(not ok,'a spotter-only clip said by the engineer is refused in the tests')
end
return T
