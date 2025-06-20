## Version 1.5 - TBD

### New Features
- Added "Close on Last Window" feature: Automatically quit apps when their last window is closed (inspired by SwiftQuit)
- Event-driven implementation using AXObserver for reliable window monitoring
- 2-second delay before termination to prevent accidental app closing
- New toggle in settings to enable/disable this feature
- Requires accessibility permissions when enabled
- App sandbox disabled for better system-level monitoring

## Version 1.4 - 2023-12-21

### Improvements
- Apps that should not have been terminated where terminated (e.g. apps that run in the background like Cleanshot X, Bartender or Paste)

## Version 1.3.1 - 2023-08-03

### Bug Fixes
- Apps that should not be closed were sometimes formated bold as if they were closed soon