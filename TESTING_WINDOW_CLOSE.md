# Testing the "Close on Last Window" Feature

## Quick Test
1. Build and run MagicQuit with the new changes
2. Enable "Quit apps when last window is closed" in MagicQuit settings
3. Grant accessibility permissions when prompted
4. Create and run the test script below
5. Close the test window
6. The test app should quit automatically after 2 seconds

### Test Script
Save this as `test_window_close.swift` and run with `swift test_window_close.swift`:

```swift
#!/usr/bin/swift

import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create a simple window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "MagicQuit Test Window"
        window.center()
        
        // Add a label
        let label = NSTextField(labelWithString: "Close this window to test MagicQuit")
        label.frame = NSRect(x: 50, y: 150, width: 300, height: 30)
        label.alignment = .center
        window.contentView?.addSubview(label)
        
        // Add instructions
        let instructions = NSTextField(wrappingLabelWithString: """
            Instructions:
            1. Make sure MagicQuit is running
            2. Enable "Quit apps when last window is closed" in MagicQuit settings
            3. Close this window
            4. This app should quit automatically after 2 seconds
            """)
        instructions.frame = NSRect(x: 50, y: 50, width: 300, height: 80)
        window.contentView?.addSubview(instructions)
        
        window.makeKeyAndOrderFront(nil)
        
        print("Test app started. Close the window to test MagicQuit.")
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false so the app doesn't quit immediately when window closes
        // This allows MagicQuit to handle the termination
        print("Window closed. Waiting for MagicQuit to terminate the app...")
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        print("App terminated by MagicQuit!")
    }
}

// Create and run the app
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

## Manual Testing with Real Apps
1. Open TextEdit or another simple app
2. Create a new document window
3. Close the window (red X button)
4. The app should quit after 2 seconds

## Debugging
If the feature isn't working:

1. **Check Console.app** for MagicQuit logs:
   - Filter by "MagicQuit" to see debug messages
   - Look for "Window event" and "No windows remaining" messages

2. **Verify Accessibility Permissions**:
   - System Preferences > Security & Privacy > Privacy > Accessibility
   - Make sure MagicQuit is listed and checked

3. **Check App Toggles**:
   - Make sure the app you're testing is checked in MagicQuit's list
   - Unchecked apps won't be affected by this feature

## Expected Behavior
- When you close an app's last window, there's a 2-second delay before termination
- System apps (Finder, Dock, etc.) are never terminated
- Apps with unsaved changes will show a save dialog before terminating
- Apps that are unchecked in MagicQuit won't be affected

## Known Limitations
- Some apps may create hidden windows that prevent termination
- Apps with special window types (panels, sheets) may not be detected correctly
- The 2-second delay is intentional to prevent accidental termination 