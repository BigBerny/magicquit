import SwiftUI
import AppKit
import Combine
import UserNotifications


class RunningAppsManager: ObservableObject {
    @Published var runningApps: [NSRunningApplication: Date] = [:]
    @Published var appsToClose: [String] = []
    private var timer: Timer?
    static let hoursUntilClose: Int = 1
    @Published var toggleStatus: [String: Bool] = [:] {
        willSet {
            objectWillChange.send()
        }
    }
    @AppStorage("janisberneker.MagicQuit.toggleStatus") var toggleStatusData: Data = Data()
    
    init() {
        syncToggleStatus()
        addCurrentRunningApps()
        
        print("init")
        let didDeactivateObserver = NSWorkspace.shared.notificationCenter
        didDeactivateObserver.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
                                          object: nil, // always NSWorkspace
                                          queue: OperationQueue.main) { (notification: Notification) in
            print("didDeactivate")
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                DispatchQueue.main.async {
                    self.runningApps[app] = Date()
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
        print("RunningAppsManager is being deallocated")
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
        let excludedIdentifiers = ["com.apple.loginwindow", "com.apple.systemuiserver", "com.apple.dock", "com.apple.finder"]
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
                }
            }
        }
    }
    
    
    private func checkOpenApps() {
        print("checkOpenApps")
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        let currentDate = Date()
        
        // Remove apps from runningApps that are not active anymore
        let currentApps = apps.compactMap { $0 }
        runningApps = runningApps.filter { currentApps.contains($0.key) }
        
        // Set date of the currently active app to currentDate
        if let activeApp = workspace.frontmostApplication, !isBlockedApp(activeApp) {
            runningApps[activeApp] = currentDate
        }
        
        addCurrentRunningApps()
        
        // Check if any apps have been running for more than hoursUntilClose and terminate them
        let hourInSeconds = 3600
        for (app, startDate) in runningApps {
            let elapsedTime = currentDate.timeIntervalSince(startDate)
            if elapsedTime > Double(RunningAppsManager.hoursUntilClose * hourInSeconds), app.isFinishedLaunching, toggleStatus[app.localizedName ?? ""] ?? true {
                print("\(app.localizedName ?? "") will terminate")
                let isTerminated = app.terminate()
                if isTerminated {
                    print("\(app.localizedName ?? "") terminated")
                    runningApps[app] = nil
                }
            }
        }
    }
}

struct ContentView: View {
    static let toggleStatusKey = "janisberneker.MagicQuit.toggleStatus"
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
                settingsWindowController = SettingsWindowController(rootView: SettingsView())
                NSApp.activate(ignoringOtherApps: true) // Activate the application
                settingsWindowController?.showWindow(nil)
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
    
    var isOn: Binding<Bool> {
        Binding<Bool>(
            get: { manager.toggleStatus[app.key.localizedName ?? ""] ?? true },
            set: { newValue in
                manager.toggleStatus[app.key.localizedName ?? ""] = newValue
                manager.saveToggleStatus() // Save the status each time it changes
            }
        )
    }
    
    var body: some View {
        let secondsUntilClose = (RunningAppsManager.hoursUntilClose * 60 * 60) - Int(Date().timeIntervalSince(app.value))
        let isLessThanHour = secondsUntilClose < 3600
        HStack {
            Toggle(isOn: isOn) {
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
                .fontWeight(isLessThanHour ? .bold : .regular)
                .lineLimit(1)  // Limit to one line
                .truncationMode(.tail)
                .foregroundColor(isOn.wrappedValue ? .primary : .gray) // Change the text color based on the toggle status
            
            Spacer() // Add a spacer to push apart the two Text views
            if isOn.wrappedValue {
                let secondsUntilClose = (RunningAppsManager.hoursUntilClose * 60 * 60) - Int(Date().timeIntervalSince(app.value))
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
            //.foregroundColor(isOn.wrappedValue ? .primary : .gray) // Change the text color based on the toggle status
            .disabled(!isOn.wrappedValue) // Disable the button if the checkbox is not checked
            /*Button(action: {
             // Close the app
             app.key.terminate()
             }) {
             Image(systemName: "x.circle") // Use SF Symbols for the star icon
             }
             .buttonStyle(PlainButtonStyle())
             .frame(alignment: .trailing)
             .foregroundColor(isOn.wrappedValue ? .primary : .gray) // Change the text color based on the toggle status*/
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
    convenience init(rootView: SettingsView) {
        let hostingController = NSHostingController(rootView: rootView.frame(width: 400, height: 200))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        self.init(window: window)
    }
}

struct SettingsView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.largeTitle)
                .padding()
            
            Text("Settings content goes here")
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
