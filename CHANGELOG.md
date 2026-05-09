# Wick's Combat Log — Changelog

## 0.1.1 - 2026-04-26

### Fixes the "type /wcl twice to open" bug + title bar slim revert

- **`/wcl` now opens the panel on the first try.** Previously the first `/wcl` was a no-op (it secretly created+hid the frame) and the second `/wcl` was the one that actually showed the panel. The frame now starts hidden so the first toggle reads as "show."
- **Title bar slim revert** — reverted the heavier 32px header from 0.1.0 to the slim CD-Tracker chrome the rest of the suite uses (22px, FRIZQT 12 no outline, plain `×` close button, drop the fel-green underline). Two-tone title color (`Wick's` in fel-green, `Combat Log` in cream) is kept.
- **Close-button glyph fix** — the previous `✕` (U+2715) rendered as a tofu/missing-glyph box in `Fonts\FRIZQT__.TTF`. Swapped to `×` (U+00D7) which renders cleanly.

## 0.1.0 - 2026-04-25

### Initial release

Raw `COMBAT_LOG_EVENT_UNFILTERED` viewer. A diagnostic tool for theorycrafters and addon developers — surfaces every CLEU subevent and every raw arg, including the fields Blizzard's default chat log strips out.

- **Live event list**, newest at top, columns: timestamp · subevent · source → dest · spell · amount.
- **Family colour-coding** on the subevent column: damage / heal / aura / cast / misc.
- **5,000-event in-memory ring buffer**, no SavedVariables persistence.
- **Pause / resume** via the filter bar or `/wcl pause` / `/wcl resume`.
- **Filters** (always capturing, applied at display only):
  - Subevent family checkboxes — Damage, Heal, Aura, Cast, Misc.
  - Source — Anyone / Mine / My Pet / Target.
  - Spell-name substring (case-insensitive).
- **Side panel detail view** — click any row to inspect every raw arg from `CombatLogGetCurrentEventInfo()` with field names. Flag-style integers also rendered in hex.
- **Slash commands**:
  - `/wcl` — toggle the panel.
  - `/wcl pause` / `/wcl resume` — toggle event capture.
  - `/wcl clear` — drop the buffer.
  - `/wcl reset` — recenter the panel.
- **Wick brand chrome** — fel-green L-bracket corners, void / shadow palette, 1px muted-purple border. BOTTOMRIGHT bracket doubles as a resize grip.
