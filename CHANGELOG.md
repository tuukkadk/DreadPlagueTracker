# Changelog

## 1.2.19 — Initial public release

- Tracks Dread Plague on enemy units via auraInstanceID, the only field that survives Midnight's secret values taint
- Detects DP applied via Outbreak (DP + Virulent Plague) and passive applications via Blightburst, Putrefy, and Soul Reaper-triggered Putrefy
- Tracks refreshes from Death Coil, Epidemic, Putrefy, and Graveyard
- Follows DP when it jumps to a new mob after the host dies
- Handles spurious removal events from nameplate slot reassignment
- Configurable icon size, position, scale, and colors
- Optional flash and sound alert when DP drops
- In-combat-only display by default, with optional always-show
- Minimap button (round and square minimaps, shift-drag to move)
- Bindable "Report Issue" key for in-combat bug reporting
- Verbose logging with copy/paste-friendly export window
- Auto-disables on non-Death Knight characters
