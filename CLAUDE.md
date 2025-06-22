# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MagicQuit is a macOS menu bar application that automatically quits idle applications after a specified time period. Built with SwiftUI, it helps keep your Mac running smoothly by closing unused apps.

## Build and Development Commands

### Building the Project
```bash
# Build using Xcode command line tools
xcodebuild -scheme MagicQuit -configuration Debug build

# Build for release
xcodebuild -scheme MagicQuit -configuration Release build

# Clean build folder
xcodebuild -scheme MagicQuit clean
```

### Running Tests
```bash
# Run all tests
xcodebuild -scheme MagicQuit test

# Run unit tests only
xcodebuild -scheme MagicQuit -only-testing:MagicQuitTests test

# Run UI tests only
xcodebuild -scheme MagicQuit -only-testing:MagicQuitUITests test
```

### Opening in Xcode
```bash
open MagicQuit.xcodeproj
```

## Architecture Overview

### Core Components

1. **MagicQuitApp.swift** - Main app entry point that creates a MenuBarExtra with the app icon

2. **RunningAppsManager** - ObservableObject that manages the core functionality:
   - Tracks running applications and their last active times
   - Monitors app deactivation events via NSWorkspace notifications
   - Runs a timer to check and quit idle apps
   - Manages toggle states for individual apps (persisted in UserDefaults)
   - Filters out system apps and menu bar utilities

3. **ContentView** - Main UI that displays:
   - List of running apps with checkboxes to control auto-quit
   - Time remaining until each app will be quit
   - Settings and Quit buttons
   - Each app row shows icon, name, time remaining, and reset/close buttons

4. **SettingsView** - Settings window for configuring:
   - Launch at login toggle (using LaunchAtLogin package)
   - Idle time before quitting (1-72 hours)
   - Option to show manual quit buttons

### Key Implementation Details

- Uses `NSWorkspace.didDeactivateApplicationNotification` to track when apps lose focus
- Stores app states in `@Published var runningApps: [NSRunningApplication: Date]`
- Per-app toggle states persisted via `@AppStorage` as JSON data
- Apps with `activationPolicy == .regular` are tracked (excludes menu bar apps)
- System apps (Finder, Dock, etc.) are explicitly excluded from tracking
- Timer runs every second, but main checks only run when app windows are active or once per minute

### Dependencies

- **LaunchAtLogin** - Swift Package for managing launch at login functionality

### File Organization

- Swift source files are in `/MagicQuit/`
- Assets (app icon, menu bar icon) are in `/MagicQuit/Assets.xcassets/`
- Tests are in `/MagicQuitTests/` and `/MagicQuitUITests/`