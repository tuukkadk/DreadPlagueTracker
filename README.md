# DreadPlagueTracker

Dread Plague tracker for Unholy Death Knights in World of Warcraft: Midnight.

## What it does

Shows a single icon that turns green when Dread Plague is up and red when it falls off. Optional sound alert when DP drops. Saves you from squinting at nameplate auras.

## Why it exists

Patch 12.0 introduced "secret values" that taint most aura data fields. WeakAuras was killed for combat, Hekili broke, and tracking DP got very hard. This addon was written specifically to deal with that. It uses auraInstanceID (the one field that isn't tainted) and a bunch of layered fallbacks for everything else.

## Known limitations

Tracking DP under Midnight's secret values system is hard. Blizzard's design specifically restricts what addons can read from auras. This addon uses several layered fallbacks to work around that, but it's not perfect.

**It's right about 95% of the time.** The other 5% shows up as a false MISSING alert while DP is actually still on a mob. When that happens it won't fix itself; you have to reapply DP via Outbreak or Putrefy. If you want to help track these cases down, see the reporting section below.

Other things to know:
- Needs the enemy's nameplate to be visible (Blizzard restriction)
- Doesn't track DP on enemies that are out of combat or far away (also Blizzard)

## Reporting issues

If you want to help improve accuracy, here's the workflow:

**1. Turn on verbose logging** (one-time)

Either open the config panel with `/dpt` and check the box, or type `/dpt log`.

**2. Bind a key to "Report Issue"** (recommended)

Esc → Key Bindings → AddOns → DreadPlagueTracker → Report Issue. Bind whatever key you want; a side mouse button or unused modifier works well. Trying to type a slash command mid-pull in a +15 is not fun.

**3. Press the key when the tracker is wrong**

Specifically, when it shows MISSING but DP is clearly still on a mob. The keypress drops a marker in the log. Keep playing.

**4. After the run**

Type `/dpt export` to open the log window. Copy everything. Paste it as a comment on the CurseForge page or [open a GitHub issue](https://github.com/tuukkadk/DreadPlagueTracker/issues).

The marker is what makes the report useful. Without it, the log is just a wall of events with no way to tell which DP REMOVED was the false one.

If you don't care about reporting and just want to play, that's fine too. Ignore the occasional false alert and carry on.

## Features

- Detects DP from Outbreak (DP + Virulent Plague together)
- Catches passive applications via Blightburst/Putrefy or Soul Reaper-triggered Putrefy
- Tracks refreshes from Death Coil, Epidemic, Putrefy, and Graveyard
- Follows DP when it jumps to a new mob after the host dies
- Rebinds cleanly on Outbreak re-cast mid-combat
- Ignores spurious removal events from nameplate slot reassignment
- Configurable icon size, position, and scale
- Color customization for active and missing states
- Optional flash + sound alert when DP drops
- In-combat only by default, optional always-show
- Minimap button (round or square minimaps, shift-drag to move)
- Bindable "Report Issue" key
- Auto-disables on non-DK characters

## Slash commands

- `/dpt` — open the config panel
- `/dpt report` — flag the current moment in the log (alias: `/dpt mark`)
- `/dpt export` — open the log window for copy/paste
- `/dpt log` — toggle verbose logging
- `/dpt clear` — clear the log
- `/dpt help` — list all commands

## Installation

**CurseForge:** install through the CurseForge app. Search for "DreadPlagueTracker".

**Manual:**
1. Download the latest release
2. Extract `DreadPlagueTracker/` into `World of Warcraft/_retail_/Interface/AddOns/`
3. The folder must be named exactly `DreadPlagueTracker` (not `DreadPlagueTracker-1.2.20`)
4. Restart WoW or `/reload`

## Requirements

- WoW Midnight (Interface 120005)
- Unholy, Frost, or Blood DK (the addon disables itself on other classes)

## Credits

By Tuukka - Burning Legion.

## License

MIT. See LICENSE.
