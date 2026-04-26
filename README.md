# Wick's Combat Log

> Raw `COMBAT_LOG_EVENT_UNFILTERED` viewer. Every subevent, every arg — the fields Blizzard's default chat log strips out.

Part of the **[Wick suite](https://github.com/jspliff/WickSuite)** — precision addons built around a single fel-green-on-deep-purple aesthetic.

<!-- wick:suite-table:start -->
| Addon | GitHub | CurseForge |
|---|---|---|
| **Wick's TBC BIS Tracker** | [repo](https://github.com/jspliff/WickidsTBCBISTracker) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-tbc-bis-tracker) |
| **Wick's CD Tracker** | [repo](https://github.com/jspliff/WicksCDTracker) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-cd-tracker) |
| **Wick's Trade Hall** | [repo](https://github.com/jspliff/WicksTradeHall) | [CurseForge](https://www.curseforge.com/wow/addons/trade-hall) |
| **Wick's Macro Builder** | [repo](https://github.com/jspliff/WicksMacroBuilder) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-macro-builder) |
| **Wick's Combat Log** | [repo](https://github.com/jspliff/WicksCombatLog) | [CurseForge](https://www.curseforge.com/wow/addons/wicks-combat-log) |
<!-- wick:suite-table:end -->

## Features

- **Live event list** — every CLEU subevent, newest at top. Columns: timestamp · subevent · source → dest · spell · amount.
- **Click-to-inspect side panel** — every raw arg from `CombatLogGetCurrentEventInfo()` with field names. Flag-style integers rendered in hex too.
- **Display filters** — subevent family checkboxes (Damage / Heal / Aura / Cast / Misc), source dropdown (Anyone / Mine / My Pet / Target), spell-name substring search. Capture is always on; filters only affect what's drawn.
- **Pause / resume** capture from the filter bar or via slash command.
- **5,000-event ring buffer** — bounded memory, no SavedVariables bloat.

## Install

- **Manual:** drop the `WicksCombatLog` folder into `World of Warcraft\_classic_\Interface\AddOns\`.

## Usage

```
/wcl              toggle the panel
/wcl pause        stop capturing events
/wcl resume       resume capturing
/wcl clear        drop the buffer
/wcl reset        recenter the panel
```

## Compatibility

- **TBC Classic** (Burning Crusade / Anniversary) — Interface `20505`.

## Brand

Uses the locked Wick palette and 10px/2px fel-green L-bracket chrome. See:
- `UI.lua` / `Detail.lua` — palette tokens at top of file
- `CHANGELOG.md` — version history
- `logo.svg` — logomark source

## License

See `LICENSE`. MIT for code; trademark carve-out for the Wick brand assets.
