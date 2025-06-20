# Close on Last Window Feature

## Overview
MagicQuit now includes a "Close on Last Window" feature that automatically quits applications when their last window is closed. This feature is similar to SwiftQuit and provides a more desktop-like experience for Mac users who expect apps to quit when closing their windows.

## How It Works
1. When enabled, MagicQuit monitors window events using macOS Accessibility API
2. When a window is destroyed, MagicQuit waits 2 seconds then checks if any windows remain
3. If no windows remain, the application is automatically terminated
4. The feature respects the existing per-app toggles in MagicQuit (apps that are unchecked won't be affected)

## Implementation Details

### Core Components
- **Event-driven Window Monitoring**: Uses AXObserver callbacks to detect window destruction events
- **2-second Delay**: Like SwiftQuit, waits 2 seconds after window closes before checking/terminating
- **Per-app Control**: Integrates with existing app toggle system
- **No App Sandbox**: Disabled app sandbox for better system-level monitoring

### Key Files Modified
1. **ContentView.swift**
   - Added event-driven window monitoring to `RunningAppsManager`
   - Uses AXObserver callbacks for window destruction events
   - Implements 2-second delay before termination

2. **SettingsView**
   - Added toggle for the new feature
   - Automatically requests accessibility permissions when enabled

3. **Info.plist**
   - Added `NSAccessibilityUsageDescription` for permission prompt
   - Added `LSUIElement` to ensure menu bar app behavior

4. **MagicQuit.entitlements**
   - Disabled app sandbox (`com.apple.security.app-sandbox` = false)
   - Enabled automation entitlements

## Usage
1. Open MagicQuit settings
2. Enable "Quit apps when last window is closed" toggle
3. Grant accessibility permissions when prompted
4. Apps will now automatically quit 2 seconds after their last window is closed

## Technical Requirements
- macOS 13.0 or later
- Accessibility permissions must be granted
- App runs without sandbox restrictions for proper system monitoring

## Excluded Apps
The following system apps are automatically excluded:
- Finder
- Dock
- System UI Server
- Spotlight
- Notification Center
- Siri
- Login Window
- Core Authentication UI

## Implementation Approach (Inspired by SwiftQuit)
- Uses AXObserver to listen for `kAXUIElementDestroyedNotification` events
- When a window is destroyed, waits 2 seconds then checks remaining windows
- Only terminates if the app has zero windows remaining
- Tracks pending terminations to avoid duplicate attempts

## Notes
- The 2-second delay prevents accidental termination during window transitions
- The feature only monitors standard windows (not dialogs, sheets, or special windows)
- Apps must have their checkbox enabled in MagicQuit to be affected
- Event-driven approach is more efficient than polling 