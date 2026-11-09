# Changelog

All notable changes to SpotterEnginer. Newest first. SpotterEnginer requires AdvancedIA: see [COMPATIBILITY.md](COMPATIBILITY.md).

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
