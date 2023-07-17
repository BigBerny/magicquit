import SwiftUI
//import AppKit
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
    
    private func addCurrentRunningApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        let currentDate = Date()

        // Add new apps to runningApps
        let excludedIdentifiers = ["com.apple.loginwindow", "com.apple.systemuiserver", "com.apple.dock", "com.apple.finder"]
        for app in apps {
            if app.activationPolicy == .regular, self.runningApps[app] == nil {
                let currentAppBundleIdentifier = Bundle.main.bundleIdentifier
                if app.bundleIdentifier != currentAppBundleIdentifier && !excludedIdentifiers.contains(app.bundleIdentifier ?? "") {
                    DispatchQueue.main.async {
                        self.runningApps[app] = currentDate
                    }
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
        if let activeApp = workspace.frontmostApplication {
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
    @StateObject private var manager = RunningAppsManager()
    @State private var isHovered = false
    //@State private var toggleStatus: [String: Bool] = [:]
    //@AppStorage(ContentView.toggleStatusKey) private var toggleStatusData: Data = Data()
    
    var body: some View {
        VStack {
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
                .padding(.vertical, 0)
            Button(action: {
                    NSApplication.shared.terminate(self)
                }) {
                    HStack {
                        Text("Quit MagicQuit")
                            .frame(maxWidth: .infinity, alignment: .leading) // aligns text to the leading edge
                            .padding(.horizontal, 10) // adds padding to the leading edge of the text
                            .padding(.vertical, 5)
                            .foregroundColor(isHovered ? Color.white : Color.primary) // Change text color to white when hovering
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    //.padding(.vertical, 10) // adds vertical padding to the entire button
                }
                .buttonStyle(PlainButtonStyle())
                .background(
                    Group {
                        if isHovered {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.blue)
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.clear)
                        }
                    }
                )
                .onHover { hovering in
                    isHovered = hovering
                }

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
                // Define your star button action here
                print("\(app.key.localizedName ?? "") star button pressed")
                manager.runningApps[app.0] = Date()
            }) {
                Image(systemName: "arrow.uturn.backward.circle") // Use SF Symbols for the star icon
            }
            .buttonStyle(PlainButtonStyle())
            .frame(alignment: .trailing)
            .foregroundColor(isOn.wrappedValue ? .primary : .gray) // Change the text color based on the toggle status
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
