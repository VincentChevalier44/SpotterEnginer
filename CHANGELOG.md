# Changelog

All notable changes to SpotterEnginer. Newest first. SpotterEnginer requires AdvancedIA: see [COMPATIBILITY.md](COMPATIBILITY.md).

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
