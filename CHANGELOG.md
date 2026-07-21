## Version 2.0.1 - 2026-07-21

### Bug Fixes
- Quit-on-last-window-closed could silently never fire: invisible helper windows blocked the window count check, and a missed close event was never retried. The periodic sweep now re-checks windowless apps, and only real windows count.
- The menu now offers "Grant Accessibility Access" when the window-close feature is enabled but the permission is missing.
- Diagnostics: `log stream --predicate 'subsystem == "com.MagicQuit"' --level debug` shows watcher state and every quit decision.

## Version 2.0 - 2026-07-20

### New
- Quit apps when their last window closes (like on Windows), with an exclusion list. Media players are excluded by default.
- Idle duration is now a single stepper with fixed steps from 15 minutes to 48 hours (previously whole hours only). Existing settings are migrated automatically.
- Time spent asleep or with the screen locked no longer counts as idle time.
- The default idle duration is 8 hours (this was already the effective 1.x default, even though parts of the old UI displayed 12 or 24).

### Improvements
- Settings rebuilt as a native macOS settings window.
- Per-app choices are now stored by bundle identifier instead of app name, so they survive renames and language changes. Existing choices are migrated.
- App tracking is event-based instead of polling every second — less energy use.
- Launch at login now uses the native macOS service (no third-party dependency).
- The manual quit button no longer requires the idle checkbox to be enabled.
- Requires macOS 14 or later.

## Version 1.4 - 2023-12-21

### Improvements
- Apps that should not have been terminated where terminated (e.g. apps that run in the background like Cleanshot X, Bartender or Paste)

## Version 1.3.1 - 2023-08-03

### Bug Fixes
- Apps that should not be closed were sometimes formated bold as if they were closed soon