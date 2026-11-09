# ACAdvancedIA → SpotterEnginer bridge

SpotterEnginer only works on top of ACAdvancedIA: it reads the state decided by its engine (flags, neutralisations,
delta, penalties, pit window, AI sanctions and pit plans…) through a structure shared between Lua apps
(`ac.connect`). This document describes the files to add to ACAdvancedIA and the four hook-ups to make, so that they
ship in its next version (otherwise ACAdvancedIA's GitHub update would overwrite them).

The code blocks below are reproduced exactly as integrated, with their original French comments.

**Status (4 November 2026)**: integrated into AC Advanced AI **Beta 1.46**, published on GitHub (commit 760e293, release v1.46, accepted by the built-in update of 1.45). The only difference from the patch below: the per-frame `pcall` calls a single function, `bridgeWork`, instead of creating a closure every frame. Two additions from its session: the bridge is only opened if `apps/lua/SpotterEnginer/manifest.ini` exists (`Applier.companionInstalled`), otherwise there is neither `ac.connect` nor per-frame work (log line `pont des apps compagnes: SpotterEnginer absent, pont inactif`, *companion app bridge: SpotterEnginer missing, bridge inactive*); cost measured by its session: about 0.01 ms per frame with 30 AI. Checked: identical format, and the installed `bridgeOpen` tested by `tests/integration_spec.lua`. The rest of this document describes the patch as it was proposed.

**Rename (5 November 2026)**: from Beta 1.49 on, the app is called **AdvancedIA** and installs into `apps/lua/AdvancedIA/` (script `AdvancedIA.lua`, manifest `NAME=AdvancedIA`, log `AdvancedIA.log`). The bridge itself does not change: `src/bridge_layout.lua` stays identical byte for byte and the `ac.connect` keys keep the old prefix (`ACAdvancedIA.Bridge.Hello`, `ACAdvancedIA.Bridge.Data.v1`), on purpose, because the protocol is frozen. SpotterEnginer (`src/port.lua`, `M.detect`) looks for `apps/lua/AdvancedIA/manifest.ini`, then the old `apps/lua/ACAdvancedIA/manifest.ini`; the main script is read under the folder's name. The `ACAdvancedIA` paths below date from the integration (1.46): read `AdvancedIA` for 1.49 and later.

Known limit of format v1: `penaltyKind` is `string(4)`, so "slow" arrives as "slo". The reader treats any value other than "dq" as a throttle cut. A possible v2 would need `string(8)`.

## Files added (already present in `apps/lua/ACAdvancedIA/src`)

- `src/bridge_layout.lua`: pure description of the format. **Identical character for character** to
  `apps/lua/SpotterEnginer/src/bridge_layout.lua` (checked by SpotterEnginer's `python tests/run.py`).
- `src/bridge.lua`: pure writer (reads the engine only, no CSP function; complies with `tests/lint.py`).

## Hook-ups in `ACAdvancedIA.lua`

1. After `local Cspgui=require('src/cspgui')`:

```lua
local Bridge=require('src/bridge')
```

2. Just before `local function release()`, then as the first line of `release()` after `if released then return end`:

```lua
-- Pont vers les apps compagnes (src/bridge.lua), ouvert plus bas ; fermé au déchargement (les lecteurs passent à
-- « absent » aussitôt).
local bridge,bridgePort=nil,nil
```

```lua
 if bridgePort then pcall(Bridge.close,bridge,bridgePort.hello); bridgePort=nil end
```

3. Right after the line `HUMANAI={engine=engine,host=host,release=release,updater=updater,port=port,panel=panel}`:

```lua
-- Pont vers les apps compagnes : état du moteur recopié à chaque image, après update(), même moteur arrêté (pause,
-- replay, en ligne, app coupée : la raison est publiée). Lecture seule du moteur ; une erreur coupe le pont seul (une
-- ligne au journal), jamais le moteur ni l'interface.
do
 local why
 bridge=Bridge.new(Config.release)
 bridgePort,why=Applier.bridgeOpen(Bridge.layout)
 U.log(engine.log,0,'INFO',bridgePort and string.format('pont des apps compagnes: ouvert (version %d)',Bridge.layout.version) or 'pont des apps compagnes: indisponible ('..tostring(why)..')',-1)
end
local function bridgeStep()
 if released or not bridgePort then return end
 local ok,err=pcall(function() Bridge.beat(bridge,bridgePort.hello); Bridge.publish(bridge,bridgePort.data,engine,frame) end)
 if not ok then
  pcall(Bridge.close,bridge,bridgePort.hello); bridgePort=nil
  U.log(engine.log,engine.time or 0,'ERROR','pont des apps compagnes coupe: '..tostring(err):sub(1,200),-1)
 end
end
```

4. In `script.HUMANAI__UPDATE`, just before `local after=before and Applier.clock(host)`:

```lua
 bridgeStep()
```

The log lines written by this code are in French: `pont des apps compagnes: ouvert (version N)` (*companion app bridge: open*), `pont des apps compagnes: indisponible (…)` (*unavailable*) and `pont des apps compagnes coupe: …` (*bridge cut off*, after an error).

## Hook-up in `src/applier.lua`

Placed before the final `return M`.

```lua
-- Pont vers les apps compagnes (SpotterEnginer, src/bridge.lua) : deux structures partagées entre apps Lua
-- (ac.connect), décrites par src/bridge_layout.lua ; la clé de chacune (champ « key ») évite toute collision. Sans
-- ac.connect (autre version de CSP, bancs de mesure) : nil et la raison, rien n'est publié.
local function bridgeItem(f)
 local S=ac.StructItem; local kind=f[2]
 if kind=='bool' then return S.boolean() elseif kind=='int' then return S.int32() elseif kind=='uint' then return S.uint32()
 elseif kind=='float' then return S.float() elseif kind=='double' then return S.double() elseif kind=='string' then return S.string(f[3]) end
 error('pont: type inconnu '..tostring(kind),0)
end
local function bridgeStruct(key,list)
 local t={}
 if key then t.key=ac.StructItem.key(key) end
 for k=1,#list do t[list[k][1]]=bridgeItem(list[k]) end
 return t
end
function M.bridgeOpen(layout)
 if not ac or not callable(ac.connect) or type(ac.StructItem)~='table' or type(layout)~='table' then return nil,'ac.connect absent' end
 local ok,port=pcall(function()
  local hello=ac.connect(bridgeStruct(layout.helloKey,layout.hello))
  local data=bridgeStruct(layout.dataKey,layout.fields)
  data.cars=ac.StructItem.array(ac.StructItem.struct(bridgeStruct(nil,layout.car)),layout.maxCars)
  return {hello=hello,data=ac.connect(data)}
 end)
 if ok and type(port)=='table' and port.hello and port.data then return port end
 return nil,tostring(port):sub(1,160)
end
```

## Checks run with these hook-ups (Beta 1.45, 4 November 2026)

- `python tests/lint.py`: 44 files, 0 errors;
- `python tests/test_pdr.py`: 588 checks, 0 failures;
- `python tests/golden.py`: fingerprints identical to those before the bridge (no change in behaviour);
- `python tests/integration.py`: `ok: true`, every case.

## Format

- `hello` (key `ACAdvancedIA.Bridge.Hello`, shape frozen forever): bridge version, ACAdvancedIA version,
  heartbeat (frame counter), closing.
- `data` (key `ACAdvancedIA.Bridge.Data.v1`): state published every frame; AC car indices (0 = first car,
  -1 = none); durations in seconds remaining or elapsed; a one-frame event is a counter that changes.
- A new version of the format changes the `data` key and `version`: SpotterEnginer then shows **Different bridge
  version** instead of reading wrong data.

## Announcements read by SpotterEnginer (`messageKind`, Beta 1.49 to 1.51)

A single slot in `data`: `messageId` increases with every announcement; `messageKind`, `messageValue`, `messageExtra`,
`messageTitle` and `messageText` describe the latest one. The title and the text are those of AdvancedIA's overlay
(`ownTitle` / `ownText`, written by `announce()` before the frame is published), in AdvancedIA's language
(`data.language`). AdvancedIA sends only one announcement per frame; pit notices and restart announcements pushed
aside or overwritten in a frame are sent again on the next frame (one slot, given up after 5 s or when the session
changes).

| Kind | When | value / extra | SpotterEnginer |
|---|---|---|---|
| `pitCompound` | F1 rules, stop due: start of the reminder before the pit entry, once per approach (1.50) | compound fitted / -1 | neither said nor written; the last reminder gives the kind and the text of the call SpotterEnginer makes at the pit lane entry (stop due, window open, on any lap) |
| `pitPlanSame` | Quick Pitstop strategy with the same compound: at the start, and instead of `pitCompound` | fitted / planned | like `pitCompound`; at the start: said only once, at half of the first lap, unless `pitPlanOk` arrived in between |
| `pitPlanOk` (asked of AdvancedIA, 5 November 2026) | strategy fixed: `same` → `ok`, F1 stop due | fitted / planned | the pending or queued "same compound" notice is withdrawn; the pit lane call becomes "change compound" again; written |
| `pitNotCounted` | decision: time up without a compound change | arrival / the same | said |
| `pitValidated` | decision: compound changed | arrival / new | said |
| `scOut` | same frame as `safetyPhase` → `out` | car behind the SC (AC index) / gap (m) | written only (the phase is already said) |
| `scLeading` | queue formed, once per deployment | head of the queue / gap (m) | written only |
| `restartPlace` | race: red flag in the pits, then pit lane exit on the relaunch lap | player's place (1..N) / car to follow (AC index, -1: the SC) | said ("Restart position: 7"), name written |
| `restartRetake` | car classified behind the player is ahead of him, at each new target | car to pass (AC index) / player's place | said at most every 15 s, name written |
| `aiDq` | an AI is disqualified | | said |
| `fastCar` (1.51) | practice and qualifying: player on an out-lap or cool-down lap, AI on a flying lap 3 s or less behind; at most once per AI every 30 s | AI (AC index) / gap (s, one decimal) | said by the spotter ("Car on a flying lap behind, let it through."), name and gap written; the spotter's faster traffic call then stays quiet for that car |

The other kinds are written on the radio of the Spotter overlay (setting **AdvancedIA announcements on the radio**),
without a voice: their state is already said from the fields (flags, neutralisations, restarts). A new announcement
must not repeat a state change already visible in a field (agreed by both sessions, Beta 1.50).
