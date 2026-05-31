import SwiftUI
import AppKit
import Combine
import LaunchAtLogin
import os.log
import ScriptingBridge
import ApplicationServices


class RunningAppsManager: ObservableObject {
    @Published var runningApps: [NSRunningApplication: Date] = [:]
    @Published var appsToClose: [String] = []
    private var timer: Timer?
    @AppStorage("hoursUntilClose") var hoursUntilClose: Int = 8
    @Published var toggleStatus: [String: Bool] = [:] {
        willSet {
            objectWillChange.send()
        }
    }
    @AppStorage("com.MagicQuit.toggleStatus") var toggleStatusData: Data = Data()
    @AppStorage("closeOnLastWindowClosed") var closeOnLastWindowClosed: Bool = false
    
    private var windowCheckTimers: [NSRunningApplication: Timer] = [:]
    
    let log = OSLog(subsystem: Bundle.main.bundleIdentifier!, category: "RunningAppsManager")
    
    init() {
        os_log("MagicQuit RunningAppsManager init starting", log: log, type: .error)
        syncToggleStatus()
        addCurrentRunningApps()
        
        os_log("MagicQuit Init - closeOnLastWindowClosed: %{public}@", log: log, type: .error, closeOnLastWindowClosed ? "true" : "false")
        let didDeactivateObserver = NSWorkspace.shared.notificationCenter
        didDeactivateObserver.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
                                          object: nil, // always NSWorkspace
                                          queue: OperationQueue.main) { (notification: Notification) in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                os_log("MagicQuit didDeactivate: %{public}@", log: self.log, type: .error, app.localizedName ?? "Unknown")
                if !self.isBlockedApp(app) {
                    DispatchQueue.main.async {
                        self.runningApps[app] = Date()
                        
                        // Check if app should be closed when last window closes
                        self.scheduleWindowCheckIfNeeded(for: app)
                    }
                }
            }
        }
        // Setup Timer
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Iterate over the app's windows and check if any of them are key or main
            if NSApplication.shared.windows.contains(where: { $0.isKeyWindow || $0.isMainWindow }) || floor(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)) == 0 {
                self.checkOpenApps()
            }
        }
    }
    
    deinit {
        os_log("RunningAppsManager is being deallocated", log: log, type: .debug)
        for app in windowCheckTimers.keys {
            cancelWindowCheck(for: app)
        }
    }
    
    // Synchronize toggleStatus with toggleStatusData
    private func syncToggleStatus() {
        if let status = try? JSONDecoder().decode([String: Bool].self, from: toggleStatusData) {
            toggleStatus = status
        }
    }
    
    // Save toggleStatus to toggleStatusData
    func saveToggleStatus() {
        if let data = try? JSONEncoder().encode(toggleStatus) {
            toggleStatusData = data
        }
    }
    
    private func isBlockedApp(_ app: NSRunningApplication) -> Bool {
        let currentAppBundleIdentifier = Bundle.main.bundleIdentifier
        let excludedIdentifiers = ["com.apple.loginwindow",
                                   "com.apple.systemuiserver",
                                   "com.apple.dock",
                                   "com.apple.finder",
                                   "com.apple.coreautha",
                                   "com.apple.Spotlight",
                                   "com.apple.notificationcenterui",
                                   "com.apple.Siri"
        ]
        if app.activationPolicy == .regular && app.bundleIdentifier != currentAppBundleIdentifier && !excludedIdentifiers.contains(app.bundleIdentifier ?? "") {
            return false
        }
        return true
    }
    
    private func addCurrentRunningApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        let currentDate = Date()
        
        // Add new apps to runningApps
        for app in apps {
            if !isBlockedApp(app), self.runningApps[app] == nil {
                DispatchQueue.main.async {
                    self.runningApps[app] = currentDate
                    os_log("MagicQuit Adding app to tracking: %{public}@", log: self.log, type: .error, app.localizedName ?? "Unknown")
                }
            }
        }
    }
    
    
    private func checkOpenApps() {
        os_log("checkOpenApps", log: log, type: .debug)
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        let currentDate = Date()
        
        // Remove apps from runningApps that are not active anymore
        let currentApps = apps.compactMap { $0 }
        let removedApps = runningApps.keys.filter { !currentApps.contains($0) }
        for app in removedApps {
            cancelWindowCheck(for: app)
        }
        runningApps = runningApps.filter { currentApps.contains($0.key) }
        
        // Remove apps that are blocked (e.g. only appear in Menu Bar) from runningApps
        for app in runningApps.keys {
            if isBlockedApp(app) {
                runningApps[app] = nil
            }
        }
        
        // Set date of the currently active app to currentDate
        if let activeApp = workspace.frontmostApplication, !isBlockedApp(activeApp) {
            runningApps[activeApp] = currentDate
        }
        
        addCurrentRunningApps()
        
        // Check if any apps have been running for more than hoursUntilClose and terminate them
        let hourInSeconds = 3600
        for (app, startDate) in runningApps {
            let elapsedTime = currentDate.timeIntervalSince(startDate)
            if elapsedTime > Double(hoursUntilClose * hourInSeconds), app.isFinishedLaunching, toggleStatus[app.localizedName ?? ""] ?? true {
                let isTerminated = app.terminate()
                if isTerminated {
                    runningApps[app] = nil
                    cancelWindowCheck(for: app)
                }
            }
        }
    }
    
    private func scheduleWindowCheckIfNeeded(for app: NSRunningApplication) {
        guard closeOnLastWindowClosed else { return }
        guard !isBlockedApp(app) else { return }
        guard toggleStatus[app.localizedName ?? ""] ?? true else { return }
        
        os_log("MagicQuit Scheduling window check for %{public}@", log: log, type: .error, app.localizedName ?? "Unknown")
        
        // Cancel any existing timer for this app
        cancelWindowCheck(for: app)
        
        // Schedule a check after 1 second delay to see if app has no windows
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.checkAppWindowCount(app)
        }
        
        windowCheckTimers[app] = timer
    }
    
    private func cancelWindowCheck(for app: NSRunningApplication) {
        windowCheckTimers[app]?.invalidate()
        windowCheckTimers[app] = nil
    }
    
    private func checkAppWindowCount(_ app: NSRunningApplication) {
        guard closeOnLastWindowClosed else { return }
        guard !isBlockedApp(app) else { return }
        guard toggleStatus[app.localizedName ?? ""] ?? true else { return }
        guard app.isFinishedLaunching else { return }
        
        os_log("Checking window count for %{public}@", log: log, type: .debug, app.localizedName ?? "Unknown")
        
        // Check if we have accessibility permissions
        let trusted = AXIsProcessTrusted()
        guard trusted else {
            os_log("No accessibility permissions to check %{public}@", log: log, type: .debug, app.localizedName ?? "Unknown")
            return
        }
        
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        
        var windowCount: CFIndex = 0
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsValue)
        
        if result == .success, let windows = windowsValue as? [AXUIElement] {
            windowCount = windows.count
        }
        
        os_log("App %{public}@ has %{public}ld windows", log: log, type: .info, app.localizedName ?? "Unknown", windowCount)
        
        if windowCount == 0 {
            os_log("App %{public}@ has no windows, will recheck in 2 seconds", log: log, type: .info, app.localizedName ?? "Unknown")
            
            // Double-check after 2 seconds to avoid race conditions
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                
                var recheckedWindowCount: CFIndex = 0
                var recheckedWindowsValue: CFTypeRef?
                let recheckResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &recheckedWindowsValue)
                
                if recheckResult == .success, let windows = recheckedWindowsValue as? [AXUIElement] {
                    recheckedWindowCount = windows.count
                }
                
                os_log("App %{public}@ recheck: %{public}ld windows", log: self.log, type: .info, app.localizedName ?? "Unknown", recheckedWindowCount)
                
                if recheckedWindowCount == 0 {
                    os_log("Terminating %{public}@ - no windows remaining", log: self.log, type: .info, app.localizedName ?? "Unknown")
                    let isTerminated = app.terminate()
                    if isTerminated {
                        self.runningApps[app] = nil
                        self.cancelWindowCheck(for: app)
                    }
                }
            }
        }
        
        // Clean up timer
        cancelWindowCheck(for: app)
    }
}

struct ContentView: View {
    static let toggleStatusKey = "com.MagicQuit.toggleStatus"
    enum HoveredButton: Hashable {
        case quit
        case settings
    }
    @State private var hoveredButton: HoveredButton? = nil
    @State private var showingSettings = false
    @State private var settingsWindowController: SettingsWindowController?
    //@State private var toggleStatus: [String: Bool] = [:]
    //@AppStorage(ContentView.toggleStatusKey) private var toggleStatusData: Data = Data()
    @ObservedObject private var manager: RunningAppsManager
    
    init(manager: RunningAppsManager) {
        self.manager = manager
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(manager.runningApps).sorted(by: { $0.0.localizedName! < $1.0.localizedName! }), id: \.0) { app in
                    AppRow(app: app, manager: manager)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 5)
            .padding(.bottom, 0)
            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            Button(action: {
                if let currentSettingsWindowController = SettingsWindowController.current {
                    currentSettingsWindowController.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                } else {
                    settingsWindowController = SettingsWindowController(rootView: SettingsView())
                    NSApp.activate(ignoringOtherApps: true) // Activate the application
                    settingsWindowController?.showWindow(nil)
                }
            }) {
                HStack {
                    Text("Settings")
                        .frame(maxWidth: .infinity, alignment: .leading) // aligns text to the leading edge
                        .padding(.horizontal, 10) // adds padding to the leading edge of the text
                        .padding(.vertical, 5)
                        .foregroundColor(hoveredButton == .settings ? Color.white : Color.primary) // Change text color to white when hovering
                    
                }
                .frame(maxWidth: .infinity)
                //.padding(.vertical, 10) // adds vertical padding to the entire button
                .background(
                    Group {
                        if hoveredButton == .settings {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.blue)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.clear)
                        }
                    }
                )
                .onHover { hovering in
                    hoveredButton = hovering ? .settings : nil
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(PlainButtonStyle())
            Button(action: {
                NSApplication.shared.terminate(self)
            }) {
                HStack {
                    Text("Quit MagicQuit")
                        .frame(maxWidth: .infinity, alignment: .leading) // aligns text to the leading edge
                        .padding(.horizontal, 10) // adds padding to the leading edge of the text
                        .padding(.vertical, 5)
                        .foregroundColor(hoveredButton == .quit ? Color.white : Color.primary) // Change text color to white when hovering
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                //.padding(.vertical, 10) // adds vertical padding to the entire button
                .background(
                    Group {
                        if hoveredButton == .quit {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.blue)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.clear)
                        }
                    }
                )
                .onHover { hovering in
                    hoveredButton = hovering ? .quit : nil
                }
            }.contentShape(Rectangle())
                .buttonStyle(PlainButtonStyle())
            
        }
        
        .frame(width: 300)
        .padding(5)
        
    }
}

struct AppRow: View {
    var app: (key: NSRunningApplication, value: Date)
    @ObservedObject var manager: RunningAppsManager
    @AppStorage("hoursUntilClose") var hoursUntilClose: Int = 12
    @AppStorage("showCloseButton") var showCloseButton: Bool = false
    
    var shouldQuitCheckbox: Binding<Bool> {
        Binding<Bool>(
            get: { manager.toggleStatus[app.key.localizedName ?? ""] ?? true },
            set: { newValue in
                manager.toggleStatus[app.key.localizedName ?? ""] = newValue
                manager.saveToggleStatus() // Save the status each time it changes
            }
        )
    }
    
    var body: some View {
        let secondsUntilClose = (hoursUntilClose * 60 * 60) - Int(Date().timeIntervalSince(app.value))
        let isLessThanHour = secondsUntilClose < 3600
        
        HStack {
            Toggle(isOn: shouldQuitCheckbox) {
                EmptyView() // Empty view as we don't want to show any label
            }
            .toggleStyle(CheckboxToggleStyle())
            .frame(alignment: .leading)
            
            let icon = NSWorkspace.shared.icon(forFile: app.key.bundleURL?.path ?? "")
            
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            
            Text(app.key.localizedName ?? "Unknown")
                .frame(minWidth: 100, maxWidth: .infinity, alignment: .leading)
                .fontWeight(isLessThanHour && shouldQuitCheckbox.wrappedValue ? .bold : .regular)
                .lineLimit(1)  // Limit to one line
                .truncationMode(.tail)
                .foregroundColor(shouldQuitCheckbox.wrappedValue ? .primary : .gray) // Change the text color based on the toggle status
            
            Spacer() // Add a spacer to push apart the two Text views
            if shouldQuitCheckbox.wrappedValue {
                let secondsUntilClose = (hoursUntilClose * 60 * 60) - Int(Date().timeIntervalSince(app.value))
                Text(formatTime(seconds: secondsUntilClose)).frame(alignment: .trailing)
                    .fontWeight(isLessThanHour ? .bold : .regular)
                    .alignmentGuide(.trailing, computeValue: { dimension in
                        dimension[.trailing]
                    })
            }
            
            Button(action: {
                // Set date of the app to now
                manager.runningApps[app.0] = Date()
            }) {
                Image(systemName: "arrow.uturn.backward.circle") // Use SF Symbols for the star icon
            }
            .buttonStyle(PlainButtonStyle())
            .frame(alignment: .trailing)
            .disabled(!shouldQuitCheckbox.wrappedValue) // Disable the button if the checkbox is not checked
            if showCloseButton {
                Button(action: {
                    // Close the app
                    app.key.terminate()
                }) {
                    Image(systemName: "x.circle") // Use SF Symbols for the star icon
                }
                .buttonStyle(PlainButtonStyle())
                .frame(alignment: .trailing)
                .disabled(!shouldQuitCheckbox.wrappedValue) // Disable the button if the checkbox is not checked
            }
            
        }
        .frame(maxWidth: .infinity)
    }
    
    // your formatTime function here
    private func formatTime(seconds: Int) -> String {
        if seconds >= 3600 {
            return "\(seconds / 3600)h left"
        } else if seconds >= 60 {
            return "\(seconds / 60)m left"
        } else {
            return "\(seconds)s left"
        }
    }
}

class SettingsWindowController: NSWindowController {
    static var current: SettingsWindowController?
    
    convenience init(rootView: SettingsView) {
        let hostingController = NSHostingController(rootView: rootView.frame(width: 600, height: 400))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        self.init(window: window)
        SettingsWindowController.current = self
    }
    
    deinit {
        SettingsWindowController.current = nil
    }
}

struct SettingsView: View {
    @AppStorage("hoursUntilClose") var hoursUntilClose: Int = 24
    @AppStorage("showCloseButton") var showCloseButton: Bool = false
    @AppStorage("closeOnLastWindowClosed") var closeOnLastWindowClosed: Bool = false
    
    var appVersion: String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        return ""
    }
    
    var appBuildNumber: String {
        if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            return buildNumber
        }
        return ""
    }
    
    var body: some View {
        VStack {
            Image("Image")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .padding()
            Text("MagicQuit")
                .font(.title)
                .padding()
            
            Text("\(appVersion) (\(appBuildNumber))")
            
            Divider().padding()
            
            VStack(alignment: .leading) {
                HStack {
                    Text("Startup:")
                        .frame(width: 100, alignment: .trailing)
                        .padding(.trailing, 20)
                    LaunchAtLogin.Toggle()
                }
                HStack {
                    Text("Idle time:")
                        .frame(width: 100, alignment: .trailing)
                        .padding(.trailing, 20)
                    Stepper(value: $hoursUntilClose, in: 1...72) {
                        Text("\(hoursUntilClose)h")
                    }
                    Text("until quitting")
                        .padding(.trailing, 0)
                }
                HStack {
                    Text("Quit button:")
                        .frame(width: 100, alignment: .trailing)
                        .padding(.trailing, 20)
                    Toggle(isOn: $showCloseButton) {
                        Text("Shows button to quit apps manually")
                    }
                }
                HStack {
                    Text("Window close:")
                        .frame(width: 100, alignment: .trailing)
                        .padding(.trailing, 20)
                    Toggle(isOn: $closeOnLastWindowClosed) {
                        Text("Quit app when last window is closed")
                    }
                }
            }
            .padding()
            
        }
    }
}

struct SettingsWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let settingsWindowController = SettingsWindowController(rootView: SettingsView())
        settingsWindowController.showWindow(nil)
        return NSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(manager: runningAppsManager)
    }
}
