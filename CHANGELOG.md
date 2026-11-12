# Changelog

All notable changes to SpotterEnginer. Newest first. SpotterEnginer requires AdvancedIA: see [COMPATIBILITY.md](COMPATIBILITY.md).

## 1.3.8 — 12 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged. Tested with AdvancedIA Beta 1.62.

### Fixed: pit window calls while the car sits in the pits
- After retiring and leaving the car in the pit box, "The pit window is open" and later "The pit window closes soon, time to come in" were still said. No pit window call is made in the pit lane any more. A window that opens while you are in the pits is announced when you leave them if a stop is still due, never if the stop was made meanwhile.

## 1.3.7 — 12 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged. From the driver's logs of 12 November.

### Fixed: "Abnormal tyre wear" after every pit stop
- AC makes a brand-new tyre grain while it is still cold, and the graining goes as it warms up. The engineer took it for abnormal wear: all eight calls of the day were graining just above the threshold on tyres with almost no distance, 40 to 60 s after leaving the pits. Graining now only counts once the tyre has been at temperature for a minute; flat spots, blisters and punctures are unchanged.

### Fixed: "The car ahead is pitting" on the grid
- When a race starts, AC moves the cars into place and one passed through the pit lane: the call was made on the grid. It is never made before the start.

### One reset per new session
- At each new session the laps of the previous one fell back to zero a second or two later, which was taken for a restart and reset everything a second time.

## 1.3.6 — 12 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged.

### Quiet side-by-side calls during the rolling start call
- With AdvancedIA's *Realistic starts* and a rolling start, the field forms two staggered columns during the rolling start call, and the car of the other column is often half alongside. The spotter now says the first *"Car left"* / *"Car right"* of each side while the queue forms, then neither *"Still there"* nor *"Clear"* until the green; side-by-side calls are back to normal at the green. Checked against AdvancedIA Beta 1.62.

## 1.3.5 — 11 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged. The new calls need AdvancedIA Beta 1.61 with its settings switched on; without them nothing changes. Checked against the frozen bridge contract of AdvancedIA Beta 1.61.

### Blue flag in two stages and faster class (AdvancedIA *Nuanced lapped cars and classes*)
- With that AdvancedIA setting on, the spotter first says *"Faster car closing in, get ready to let it through."*, then the usual blue flag when AdvancedIA gives the order (the first call is withdrawn if it is still waiting). The first blue flag of a session is still the plain one: SpotterEnginer only trusts the setting once it has seen it working. A faster class on the same lap has its own call, *"Faster class behind, hold your line and let it through."*, and the spotter's own *"faster traffic"* call stays quiet for that car.
- Without the setting (or with AdvancedIA's native blue flag) the blue flag is said as before.

### Live weather (AdvancedIA *Live weather*)
- With that AdvancedIA setting on, the engineer announces the tyre crossover ahead of time: *"Rain tyres in 9 minutes"*, *"Back to slicks in 5 minutes"*, at 10, 5 and 2 minutes, once per crossover. It waits until the trend has held for a minute (at the start of a sudden shower the estimate is wrong), says nothing again when the trend wavers, and never once the bridge already says the track is wet or dry. *"Rain expected in N minutes"* keeps SpotterEnginer's own estimate.

### Never stale values
- AdvancedIA keeps the last text of these keys when its setting is off. SpotterEnginer only uses a key once its text has changed during the current session, and ignores it again when it stops changing (2.5 s for the blue flag, 30 s for the weather).

## 1.3.4 — 11 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged. Needed for the formation lap and rolling start option of AdvancedIA Beta 1.60.

### Formation lap and rolling start (AdvancedIA Beta 1.60, option off by default)
- AdvancedIA neutralises the race during its formation lap. 1.3.3 would have said *"Race resumes under full course yellow"*; the spotter now says the formation lap (*"…get back to your grid slot"* before a standing start, *"…hold your place in the queue, it's a rolling start"* before a rolling one, new clip), the rolling start call with the car to follow written on the radio, and *"Go, go, go!"* at the green. No full course yellow, restart or green flag call during that phase, and no "stopped car" or "you are stopped" call either. A formation lap abandoned on a major incident is said as a full course yellow, once.
- Checked against the bridge of AdvancedIA Beta 1.60 (same format).

### Strategy duel published for AdvancedIA
- The engineer's undercut / overcut verdict is published for AdvancedIA's display (key `SpotterEnginer.strategy`, contract v1: mode, rival, gain, stop lap), with the same switches as the calls. See the README.

## 1.3.3 — 11 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged.

### Fixed: "You're facing the wrong way!" while reversing
- From AdvancedIA Beta 1.59 on, the bridge really publishes its "wrong way" state (it was always off before). It means "the car goes backwards along the lap", which is also true when you reverse out of a wall with the nose pointing the right way. The spotter no longer says *"You're facing the wrong way! Turn around when it's clear."* while your car moves backwards; a car really driven against the track is still called.
- Checked against the bridge of AdvancedIA Beta 1.59: same format, and the spin and off-track readings need no change.

## 1.3.2 — 10 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged. Second full adversarial review: every finding fixed, each with its test (222 checks).

### Strategy and engineer
- **Pit window one lap too early.** AdvancedIA opens the mandatory window on the leader's whole laps; the engineer rounded after subtracting your gap to the leader, and could call you in on a lap where the stop did not count (20 laps, window at 42 %, half a lap behind: lap 8 instead of 9). Timed races and CSP windows now count the part of the lap already driven.
- **Timed race with an extra lap**: the last lap is no longer counted as "2 laps left" (wrong *"lift and coast"*, even *"box this lap"* on the last lap).
- A *"box"* you did not follow no longer stays engaged when the plan has no stop left: fuel calls come back, *"no more stops"* is said, and the pit plan published for AdvancedIA no longer shows a lap already gone.
- The pit plan published for AdvancedIA says `boxnow` only on the stop lap (it stayed `boxnow` for a future lap during a whole neutralisation), and keeps `done` when the line is crossed in the pit lane.
- Strategy switched off during a race: the old plan is forgotten. Without a plan, fuel calls work in timed races too.
- The pit window is no longer announced again each lap when the optimal lap wavers between two values.
- Undercut and threat are never computed against a car already in the pit lane. Two mandatory stops are both counted once the window is open. No phantom tyre stop with tyre wear off. *"Rain expected in…"* is said once per step, not up to four times. The pit lane loss ignores partial passages.
- **"Abnormal tyre wear" after an app reload**: what was already said (wear, pit window, debrief, *"no more stops"*, calls just heard) survives a hot reload of the app within the session.

### Spotter
- **Stopped on track** (out of fuel, parked): *"Car coming, wait!"* at most twice per episode, and none after 30 s.
- Gaps and overtakes are no longer wrong on tracks whose timing line is not at the start of the lap spline.
- A spin is only called when the yaw cannot be explained by the corner (no false spin in a kart hairpin). The left/right auto-swap ignores samples taken driving the wrong way.
- After a neutralisation: no *"within a second"* or *"you're closing"* from the bunched queue. No stale gap after a rival's stop. No late *"clear"* after standing still. *"Careful rejoining"* only for a car clearly faster than you. No *"no damage"* after going back to the pits. The pit exit is learnt from real stops only. A VSC escalated to Safety Car says *"Safety car called"*. Point-to-point tracks are no longer treated as loops.

### Radio and interface
- **Strategy overlay error** when a called stop disappeared from the plan (the in-game overlay editor vanished with it): fixed, and the editor is drawn even if an overlay fails.
- The radio no longer talks through the pause menu or a replay: the sentence in progress ends, the queue is dropped, and the radio delays stop running while the game is paused.
- **Numbers from 100 to 999 are spoken** (new *"hundred"* clip): pit window and optimal lap in races of more than 99 laps were only written.
- A restart of the race during the first lap is detected (everything starts from zero, the debrief no longer keeps the overtakes of the aborted start).
- The same figure is no longer repeated lap after lap when its spoken value has not changed. An engineer information that waits for its turn is no longer dropped.
- *Test the voice* works without AdvancedIA. A role switched off or a language change drops its queued calls. Settings changed just before the app unloads are saved. Overlay positions go up to 16000 × 9000 px (triple 4K screens). The **OVERLAYS** button no longer shows on every mouse move when you steer with the mouse. The "missing clips" warning counts catalogue clips only.
- Lighter frames: overlay texts are rebuilt only when the displayed value changes, no table or text allocated per frame in the overlays, the engineer, the strategist and the updater; unused kit widgets and texts removed.

### Updater and tools
- **Roll back** is only offered when the kept version was saved from under the version now installed (after a manual install over it, rolling back mixed two versions).
- The app loads even when the update modules are unreadable (the fallback itself failed).
- The status published for AdvancedIA is no longer stale after a successful update or when no release exists; a refused roll back no longer shows as an incompatible update.
- The bridge guard is checked again at the moment of the copy. Unreadable files are never taken for identical ones. Stricter package paths (Windows reserved names, trailing dots, case duplicates) and exact download address. The package comparison is spread over several frames. Preloaded clips are released before the files are copied. GitHub is not asked again at each app reload.
- `tools/sync_repo.py` refuses a folder that is not the SpotterEnginer repository, never removes `.git*`, `.github/` or the files listed in `.syncrepo-keep`, and has `--dry-run`. `tools/package.py` compiles every Lua file of the package and refuses a package above 80 % of the size limit known to installed versions. `tools/generer_voix.py` writes each clip atomically.

## 1.3.1 — 10 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged.

### Fixed: "Big hit! We're checking the damage." on every heavy braking
- AC reports a contact with the track when the car touches a kerb or scrapes the floor, often under heavy braking. 1.3.0 took the speed lost by the braking itself (43 to 47 km/h in 0.4 s) for an impact, then said "No damage" 3 s later, at every big braking zone.
- A contact now only counts the speed lost beyond the deceleration you already had just before it. Against a wall without damage, it is never a hit with the brake pedal pressed. A real hit (damage recorded, or a car stopped while you were not braking) is still called, and so is a contact with a car that really costs you speed.
- The session log now writes each notable contact with the speed lost beyond the braking, the expected loss and the brake pedal.

### Full adversarial review (radio, spotter, engineer, strategy, overlays, code)

**Instant radio**
- Safety calls (priority 1 and 2) no longer wait for the short gap between two messages, and priority 1 calls start without the opening tone. A transmission that follows the previous one by less than a second has no tone either (*"Car left… still there… clear"* in one go).
- The next clip of a sentence is prepared while the current one plays and starts the moment it ends. The end of a clip is read from its position in its duration, not only from "still playing". Safety clips are preloaded at launch and on a language change.
- A side-by-side call (priority 1, of an instant) now cuts another priority 1 call that is not one (a long red-flag message no longer swallows "car left").
- The radio runs on its own: an error elsewhere in a frame no longer stops the sentence in progress, and the car sound always comes back.
- A game hitch of a few seconds no longer counts as a lost link: the radio is only stopped, and race control only starts from a new reference, after 3 s without AdvancedIA (it cut the sentence and announced the neutralisation in progress again).
- The session log is buffered and written once per second, never just before a safety call.
- A call counts as heard only when said to the end (or after 0.5 s of voice): a position cut at once is said again at the next line. A call that expired without being said no longer uses up its delay. Spotter information (DRS, flash) and a call replayed after an interruption no longer wait 12 s behind another information. The same key already waiting is updated even during its delay.

**No more false alarms**
- "Careful rejoining, car coming!" after every pit exit: AdvancedIA's "on track" value is only written during an incident, so the player read as off track. It is now read only with an incident.
- A stopped car mid-track was called "off the track" before AdvancedIA saw the incident, then dropped behind a side call.
- "Contact between cars ahead" on every AI rub under braking: the braking is now discounted, as for the player in 1.3.1.
- "Coming up on your left" for a car following in your tracks through a corner: measured along both cars' average heading, held 0.3 s, and never under braking.
- Pit exit clear or traffic: judged 150 m before the exit at pit-lane speed, instead of at the box at 25 km/h (three times too late); nothing under a red flag or with the pit lane closed.
- AdvancedIA's safety car is never a backmarker, faster traffic, a hazard or a contact.
- No backmarker or faster-traffic calls under neutralisation, red flag or restart; a short delay between two such calls (a train of cars no longer gives four calls in 20 s). In a race, a car about to lap you is left to AdvancedIA's blue flag when it is announced (never "hold your line" then "let him by").
- "You're within a second", "nothing behind, you can have a go": never in a yellow zone, under no-overtaking or at a restart, and nothing caught up all at once at the green. "Nothing behind" now looks at every car measured behind, not only the next one in the classification.
- "Place given back" only when the car you owed is really ahead of you (AdvancedIA also clears the debt in the pit lane or at the deadline).
- "You're clear, move over" only when both sides are clear. An AI mistake made further away, or during your stop, is no longer announced later as new. No gaps after the chequered flag.
- A stop on track is only judged once you have driven above 50 km/h since the start or the pit exit (never at a standing start). A puncture is not called again after a pit-lane pass with the tyre still flat. Off track must last 0.3 s.
- Your own spin is now seen by the car's yaw rate: AdvancedIA 1.58 always publishes its spin and wrong-way flags as false (reported; fixed in its 1.59).

**A more accurate engineer**
- Under a safety car, "Let's use the neutralisation. Box, box, this lap" was followed by "Box next lap" in the same lap, and the pit plan published for AdvancedIA pointed to the next lap. The neutral box is now committed like any other.
- Undercut, overcut and threat are never said in the pit lane, under neutralisation, with a box committed, without a planned stop or with the stop more than 4 laps away. The duel model is consistent: an unknown rival answers the next lap; undercut and overcut need a real margin of 1 s; the threat compares the rival stopping now with you answering the next lap; the horizon stops at the finish. The written figure is now the margin after the stops, not a "gain".
- The target delta after a stop is compared to the new target (it said "minus 1.5 s" on fresh tyres), and only on normal laps (never "plus 4.9 s" after a spin).
- Fuel: no "lift and coast, minus 15 laps" when a refuelling stop is needed but not planned; no "plus 0 laps" point. Timed race: the extra lap still counts once the clock has run out.
- The window is not announced in the 10 s after a pit exit, nor repeated within 90 s unless the stop moves earlier; a one-lap window says the stop lap only. "No more stops" is never said with a box committed. After "stay out" under a neutralisation, a box needs a clear gain (3 s). The chase pace reads "+0.3 s/lap".

**Overlays**
- Engineer: the fuel margin is the radio's own figure (safety margin included, to the committed box or the planned stop); tyre colours use the radio's thresholds (core and surface); the last lap shows its delta to the target, in red when the lap was not normal; the target is grey until the plan is ready.
- Strategy: a large **BOX THIS LAP** / **BOX NEXT LAP** banner, or **PIT LANE CLOSED**; the stop lap shown is the committed one; fuel in laps, as on the radio; degradation labelled "vs new"; duels show "—" with no rival close enough; **Strategy off** and **Race finished** instead of a stale plan.

**Code**
- Duplicates merged: one helper per role to speak (`Say.as`), one track-distance helper (`U.ahead`), one neutralisation test (`Link.neutralised`), shared sum, lap time and `callable`; the lost-place check moved next to the gained-place one.
- Dead code removed (unused exports, state, reset functions, about twenty values read from CSP every frame and never used); a test that could never fail now checks the right call; the "missing clips" message no longer points to a file that is not shipped.

## 1.3.0 — 10 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged. Nothing changes in the bridge or in the pit plan contract (`SpotterEnginer.pitplan` v1).

### A more human radio
- The most frequent calls have two to four wordings, never the same one twice in a row, and each clip has a tone chosen by the situation: urgent (hazards, emergencies), motivating (place gained, attack, within a second), disappointed but supportive (place lost, damage), calm (managing a gap, neutralisation). The tone is in the wording and the delivery (speed and pitch of the same voice).
- A call said with another wording still counts as a repeat (the 180 s rule follows the meaning, not the text).
- New setting **Varied wording** (tab **Radio & voice**, on).

### Earlier warnings
- Stopped, spinning or wrong-way car ahead: still called within 600 m as in 1.2.0, and now earlier at high speed (11 s at your closing speed, up to 900 m), with its side and where to go (*"Stopped car ahead! It's on the left. Go right."*).
- *"Contact between cars ahead, careful!"* when two cars ahead touch and one of them really slows down.
- *"Coming up on your left!"* before a faster car is alongside; *"You're clear, you can move over."* when the car you were alongside is behind you; *"Nothing behind, you can have a go."* when you attack with nobody close behind.
- New setting **Anticipation** (section **Traffic**, on); off, hazards are called from 600 m only, as in 1.2.0, and the other early calls are off.

### Live gaps and position
- *"You're within a second, go for it!"* (with *"Nothing behind, you can have a go."* when nobody is close behind), *"He's within a second behind, watch your mirrors!"* during the lap, never near the line; gaps at the line say *"He's pulling away"*, *"You're pulling away"* or *"Gap is stable"*.
- A place gained or lost on track is said at once (held 2.5 s), not at the next line: *"You're P4. Great move, well done!"*, *"You're P5. He got by. Stay calm, we'll get him back."*
- The engineer no longer repeats "push" or "defend" at the line when the spotter has just said the gap.
- New settings **Live gaps** (section **Gaps**) and **Live position** (section **Pace and calls**), on.

### Strategy explained
- The engineer decides alone and says why: *"We're going for the undercut. Box, box, this lap."* when the undercut pays inside the window; *"Car ahead is pitting. Stay out, we'll do the overcut."*; *"He's pitting, we cover."*; under neutralisation *"Let's use the neutralisation… That gains us about 12 seconds."* or *"Stay out, a stop isn't worth it."*; *"No more stops, we go to the end."*
- A decided undercut or cover commits the box like any other, and the pit plan published for AdvancedIA follows it.
- New setting **Strategy explained** (section **Strategy calls**, on).

### Emergencies
- *"Contact!"* when a contact with a car really costs you speed or damage (at most every 15 s); *"Big hit!"* against a wall; then the engineer's damage report (none, light, moderate, heavy, suspension).
- *"Puncture! Bring it back to the pits slowly."* instead of "abnormal tyre wear".
- After a spin or a stop on track, a guided rejoin: *"Stay on the brakes, cars coming."*, *"Car coming, wait!"*, *"It's clear, go now."*; *"You're facing the wrong way!"*; *"Careful rejoining, car coming!"* after going off.
- New section **Emergencies** (tab **Spotter**, on).

### Voice clips
- 65 new clips in each language (162 to 227; 193 is unused): 225 calls, 972 files.

### Tests
- New `tests/radio_spec.lua`: every new call has its silent case (nothing happens: nothing is said). A simulated 10-lap race caps the radio: at most 4 spotter and 3 engineer calls (priority 3 to 5) in any minute.

## 1.2.0 — 10 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged.

**From 1.1.0 or 1.1.1, install this version by hand once** (zip from the Releases page): in those versions the **Update** button stayed greyed even when stopped (fixed below). From 1.2.0 on, the in-app update works.

### In-game overlay editing
- While driving, move the mouse: a small **OVERLAYS** button shows for 3 seconds at the top centre of the screen. It can be dragged elsewhere; its position is kept.
- A click opens the edit panel under the button, without the pause menu or the pits. Every overlay shown is unlocked for the edit: drag it to move it, pull its bottom-right corner for the size.
- In the panel: show or hide each overlay of the current desktop, then for the one picked (click its row, or touch the overlay itself) its size, background (Solid, Ghost, Transparent), background and content opacity, decorative band, header, and **Recenter**.
- **Done** (or **Ctrl+Alt+K**, which now opens and closes the editor) locks every overlay. Editing is never saved as "unlocked": after a crash, everything stays locked.
- New section **In-game editing** (tab **Overlays**): switch **In-game edit button**, button position, **Open in-game editing**, **Put the button back at the top centre**.

### End-of-race debrief
- At the finish of a race the spotter says *"Chequered flag, race over! You're P2."*, then the engineer sums the race up: places gained or lost since the start, overtakes on track, *"And the fastest lap of the race!"* when it is yours, and a verdict (win, podium, top 5, top 10, good comeback, tough race, keep improving, not classified, disqualified).
- Overtakes are counted by SpotterEnginer on the order of the cars on track: a backmarker being lapped and a place gained during a pit stop do not count. Start and finish places, best lap and how many times you were passed are written on the radio.
- Said as soon as you cross the line, not when you get back to the pits: AdvancedIA pauses its bridge at the finish, and SpotterEnginer still reads its result during that pause. Once the line is crossed the engineer makes no other race call, and a result left over from before a session restart is never read out.
- New setting **End-of-race debrief** (tab **Engineer**, on by default). 19 new voice clips in each language (clips 143 to 161).

### Pit plan shared with AdvancedIA
- SpotterEnginer publishes its pit plan for AdvancedIA (`ac.store` key `SpotterEnginer.pitplan`, contract v1): stop lap, window, state (planned, box now, done, none), whether the "box" calls are on, and a time stamp. From AdvancedIA Beta 1.59, its pit overlay follows it: a short notice when the window opens, then *box this lap* only on the planned lap. Nothing changes in the bridge.

### Update in the header, as in AdvancedIA
- The header shows the installed version. When a newer one is published, the version turns blue and a small **Update · x** button appears next to it: one click installs it when stopped (pit box or pause), greyed while driving.
- If AdvancedIA must be updated first, the header shows **AdvancedIA first** with the explanation; a click opens the **Diagnostics** tab. During the download and installation, the header shows the current step.
- The UPDATE block (state, release notes, Check now, Roll back, Check for updates at launch) moved from the bottom of **Home** to the top of **Diagnostics**.

### Fixed
- The **Update** and **Roll back** buttons of the UPDATE block stayed greyed and did nothing even when stopped.

## 1.1.1 — 9 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1), unchanged.

### Fixed: "Abnormal tyre wear" repeated every three minutes
- When tyre wear is low or off, the virtual kilometres of the tyres stay near zero; the engineer took that for a fresh set at every frame, so a flat spot (or blisters, graining, a puncture) was called again as soon as the radio's repeat delay ran out. The call is now made once per set of tyres.
- A new set is recognised when the virtual kilometres go back (tyre change, back to the pits), or after a pit stop from which the defect is gone. A defect has to last one second to be called.
- The journal (`Documents/Assetto Corsa/logs/SpotterEnginer.log`) now says which tyre and which defect caused the call, with its values.

### Fixed: traffic calls with nobody catching up
- *"Faster traffic approaching from behind, hold your line."* compared speeds at one instant: a car up to 150 m behind that was simply braking later than you was "15 km/h faster" at every corner. A car is now called only when it really closes in: the time gap measured at the same place on the track shrinks by at least 0.1 s per second over 3 s (or 0.3 s per second over 1 s), and the gap would be gone within 15 s (called under 2 s). When you are down to walking pace (spin, off), a car less than 150 m behind and at least 40 km/h faster is called at once. Races are unchanged: a car about to lap you is called under 2 s.
- *"Car on a flying lap behind, let it through."* (AdvancedIA's announcement) is said only if SpotterEnginer sees that car closing in the same way within 6 s, 3 s or less behind, and it now gives the measured gap. Otherwise nothing is said and the journal notes "tour lancé non confirmé" with the gap and closing rate. AdvancedIA was announcing cars that were only 5 to 9 km/h faster, more than a minute away.

## 1.1.0 — 9 November 2026

Requires AdvancedIA Beta 1.46 or later (bridge v1). The "car on a flying lap behind" call needs AdvancedIA Beta 1.51.

### Position calls by the engineer
- New setting **Position and advice** (tab **Engineer**, section **Pace and calls**, on by default).
- *"You're P5."* at the line when your place has changed since the last call, never every lap, in one transmission with the call of the lap (*"You're P4. Nice job. Push now, this is the moment."*).
- Without another call, advice only when justified: *"He's within reach, push a little, you can do it."* when the car ahead can be caught before the finish at the current pace; *"Look after your tyres, take it a bit safer."* after overheating or abnormal wear, when nobody threatens from behind (once per stint).
- *"Nice job."* only for an overtake on track: a place gained during a rival's stop or from a retirement does not count.
- One call per crossing of the line. A call that could not be said (busy radio) is said at the next crossing; a position already said is said again if it changes again.
- Nothing before the end of lap 2, under neutralisation or in the pit lane; the position alone on the out-lap.

### Last lap call by the spotter
- *"This is the last lap! You're P7."* then, in the same transmission, *"He's right behind you, close the door."* (car less than 0.8 s behind), *"He's within reach, give it everything!"* (car ahead less than 1.2 s away) or *"Bring it home, no risks."*
- If the Spotter role or the **Flags and neutralisations** section is off, the engineer gives the position instead.

### Radio effect and opening tone
- Every voice now goes through a radio band (300 to 3,400 Hz, present mids, light saturation), at a light strength chosen to stay clear at full speed; the level is measured after the effect.
- A short digital opening tone (two notes, 85 ms, then 45 ms of silence) before each transmission, never between the clips of one sentence. New setting **Radio tone** (tab **Radio & voice**, section **Voice and language**, on by default); the same sound is used for messages without a voice clip. File `sounds/radio.wav`.

### Practice and qualifying: car on a flying lap behind
- With AdvancedIA Beta 1.51 (`fastCar` announcement): *"Car on a flying lap behind, let it through."* while you are on an out-lap or a cool-down lap, with the name and the gap written on the radio. Follows the setting **Faster traffic behind**; the spotter's own faster-traffic call then stays quiet for that car.

### Units and punctuation of composed phrases
- The unit follows the value said: singular below 2 in French, for 1 only in English ("1 lap", "0.5 laps"); "one minute" has its own clip. The text written on the radio is built from the same clips, so it says exactly what is heard.
- A full stop separates a sentence that starts with a capital letter from the number or sentence before it (*"Gap ahead: 1.2 seconds. You're closing."*).

### Fixes from a full code review
- 0.17 s of dead air after the radio tone removed.
- Wrong number of expected voice clips on the **Home** tab.
- State kept from one session to the next by mistake.
- Pit laps and neutralised laps counted in the pace.
- Target lap biased when the car uses no fuel.
- Rivals' stops in the rejoin estimate.
- Settings shown as changed by mistake (floating-point rounding of default values).
- Diagnostics texts were in French only.
- The pit window call now follows the setting **Window and "box" on the radio**.

### In-app updater
- New **UPDATE** block on the **Home** tab, with the setting **Check for updates at launch** (on by default): one check on GitHub per launch, release notes shown, one-click install only when stopped (pit box or pause), **Cancel**, **Check now**, **Roll back to x**.
- The package (`SpotterEnginer-x.y.z.zip`) and its `.sha256` are downloaded from the repository's releases only; size, SHA-256, package content and manifest version are checked; the current version is backed up; files are copied one by one, manifest last; the app restarts. Settings are kept.
- Interrupted copies are finished or undone at the next launch; a version that fails to start twice is rolled back automatically.
- Work folder in CSP's state folder (`cfg/extension/state/SpotterEnginer-update`), never in the app folder.
- Compatibility guard: before installing or rolling back, the bridge version of the package is compared with the installed AdvancedIA's; the update is refused when AdvancedIA is older (*Update AdvancedIA first*), newer than the package knows, or missing.
- Update state published for AdvancedIA's home page (`ac.store` key `SpotterEnginer.update`, contract v1).
- New tool `tools/package.py` builds the release package and checks it with the real updater.

### Look
- New official icon (`icon.png`, original `docs/icon-512.png`) and banner (`docs/banner.jpg`).

### Documentation
- Documentation now in English. The generated list of voice clips is `vox/VOICE_CLIPS.md`.

## 1.0.0 — 4 November 2026

First version.

- Voice spotter (race control, traffic, side by side, gaps, penalties) and race engineer (pace, fuel, tyres, brakes, damage, weather, wind, driving advice, pit strategy), in French and in English.
- Strategy solver (real wear, fuel, pit lane loss, AdvancedIA's rules, traffic when rejoining) with pit window, optimal lap, undercut and overcut.
- Three in-game overlays (Spotter, Engineer, Strategy).
- Works on top of AdvancedIA through its data bridge (version 1, AdvancedIA Beta 1.46).
