# Compatibility

SpotterEnginer is not a standalone app: it works only on top of [AdvancedIA](https://github.com/VincentChevalier44/AdvancedIA), whose race state it reads through a data bridge between Lua apps (`ac.connect`). This page says which versions go together.

## SpotterEnginer and AdvancedIA

| SpotterEnginer | AdvancedIA required | Bridge version |
|---|---|---|
| 1.1.0 | Beta 1.46 or later (the "car on a flying lap behind" call needs Beta 1.51) | v1 |

The required AdvancedIA version is also written in SpotterEnginer's `manifest.ini` (`REQUIRES_ADVANCEDIA=Beta 1.46` for 1.1.0).

**Calls that depend on the AdvancedIA version** (bridge v1 throughout; older versions simply never send them):

| AdvancedIA | What it adds for SpotterEnginer |
|---|---|
| Beta 1.46 | The bridge itself (AC Advanced AI, its former name; release v1.46 of 4 November 2026). |
| Beta 1.49 | New name and folder `apps/lua/AdvancedIA/`; F1 compound rules with pit notices (*change compound*, *stop validated*, *stop not counted*, *same compound in your pit strategy*). |
| Beta 1.50 | Restart notices (*restart position*, *take your place back*), Safety Car queue notices, and the notice that the pit strategy was fixed. |
| Beta 1.51 | *"Car on a flying lap behind, let it through."* in practice and qualifying (`fastCar`). |

**Folder.** SpotterEnginer looks for `apps/lua/AdvancedIA/manifest.ini` first, then the old `apps/lua/ACAdvancedIA/manifest.ini` for installations not yet migrated. Only the manifest counts: an empty old folder is ignored. AdvancedIA, for its part, only opens the bridge when `apps/lua/SpotterEnginer/manifest.ini` exists, so the SpotterEnginer folder name must be exactly `SpotterEnginer`.

## Bridge changes always ship in both apps together

- The format is described in `src/bridge_layout.lua`, **identical character for character** in both apps (checked by `python tests/run.py`).
- The `hello` structure (key `ACAdvancedIA.Bridge.Hello`) never changes shape: it says that AdvancedIA runs and which bridge version it publishes, even to a reader that does not know that version.
- A new format changes both the `data` key (`ACAdvancedIA.Bridge.Data.v1` today) and `version`. SpotterEnginer then shows **Different bridge version** instead of reading wrong data, and stays silent until both apps are updated.
- The keys kept their `ACAdvancedIA` prefix when AdvancedIA was renamed (Beta 1.49), on purpose: the protocol is frozen.
- **The in-app updater enforces it.** Before installing a new SpotterEnginer, and before rolling back, it compares the package's bridge version with the installed AdvancedIA's. It refuses when AdvancedIA is older (*Update AdvancedIA first*), when AdvancedIA publishes a newer bridge than the package knows, and when AdvancedIA is not installed. See [README.md](README.md#compatibility-guard).

## What the bridge carries

SpotterEnginer only reads the bridge (`src/link.lua`); it never writes into AdvancedIA. The `data` structure (layout in `src/bridge_layout.lua`) publishes these groups of fields, from which SpotterEnginer takes what its calls need:

- **AdvancedIA's state**: enabled, ready, panic, online, replay, paused, the reason for a suspension, profile, language, session, clock, player, number of cars.
- **The player's flag and the driver's panel** (what the driver sees): the flag imposed on AC, lights, panel kind, titles and texts, blue flag gap, infractions.
- **Race control**: neutralisation (SC, VSC, FCY) and its phases, VSC ending, Safety Car, red flag, restarts, standing start (lights, grid slot, jump start), pit lane closed, slippery track, yellow zones and their distance, DRS state, pit window reminders, slow car, black and orange flag.
- **The last announcement** (`messageId`, `messageKind`, `messageValue`, `messageExtra`, `messageTitle`, `messageText`).
- **The delta to keep**: on, value, kind, infractions.
- **The player's penalties**: reason, kind, seconds, disqualification, place to give back, pending red-flag, stop and jump-start penalties.
- **DRS and headlight flash**: DRS beep, player DRS, flash understood.
- **Pit stops**: pit state, window opening and closing, stops done and due, maximum stint, minimum pit time, stop waived.
- **Race**: race progress, laps left, wet track, finish, positions.
- **AI sanctions** (overlay announcement) and, **for each car** (up to 61): pit and track state, incidents, sanctions and pending penalties, planned stops and their cause, failures, stops made, mistakes.

The details of the announcements read by SpotterEnginer are in [docs/PONT_ACADVANCEDIA.md](docs/PONT_ACADVANCEDIA.md). Known limit of format v1: `penaltyKind` is `string(4)`, so "slow" arrives as "slo"; SpotterEnginer treats any value other than "dq" as a throttle cut.

## Game and CSP

- **Assetto Corsa** for PC with **Custom Shaders Patch 0.3.2 or later** and Lua apps working.
- **Offline sessions only.** In an online race AdvancedIA stands aside (link state **AdvancedIA suspended · online race**), and SpotterEnginer stays silent.
- **In-app updates** need CSP's network and file functions; without them the UPDATE block says so, and you update by hand.
- **SuperHUD**: the overlays use the same settings model and avoid SuperHUD's H and G keys; their automatic positions may cover SuperHUD blocks, so move them if needed.

See [README.md](README.md) for the features and [CHANGELOG.md](CHANGELOG.md) for the history.
