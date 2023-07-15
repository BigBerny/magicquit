import SwiftUI
import AppKit
import Combine

class RunningAppsManager: ObservableObject {
    @Published var runningApps: [String: Date] = [:]
    @Published var appsToClose: [String] = []
    private var timer: Timer?
    static let hoursUntilClose: Int = 24

    init() {
        addCurrentRunningApps()
        
        let didDeactivateObserver = NSWorkspace.shared.notificationCenter
        didDeactivateObserver.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                            object: nil, // always NSWorkspace
                             queue: OperationQueue.main) { (notification: Notification) in
            print("didDectivate")
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let name = app.localizedName {
                DispatchQueue.main.async {
                    self.runningApps[name] = Date()
                }
            }
        }
        
        self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.checkOpenApps()
        }
    }

    deinit {
        print("RunningAppsManager is being deallocated")
    }
    
    private func addCurrentRunningApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications

        for app in apps {
            if app.activationPolicy == .regular, let name = app.localizedName {
                DispatchQueue.main.async {
                    self.runningApps[name] = Date()
                }
            }
        }
    }

    private func checkOpenApps() {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications
        let currentDate = Date()

        // Get the names of the currently running apps
        let currentAppNames = apps.compactMap { $0.localizedName }

        // Remove apps from runningApps that are not active anymore
        runningApps = runningApps.filter { currentAppNames.contains($0.key) }

        // Set date of the currently active app to currentDate
        if let activeAppName = workspace.frontmostApplication?.localizedName {
            runningApps[activeAppName] = currentDate
        }

        // Add new apps to runningApps
        for app in apps {
            if app.activationPolicy == .regular, let name = app.localizedName, self.runningApps[name] == nil {
                DispatchQueue.main.async {
                    self.runningApps[name] = currentDate
                }
            }
        }

        // Filter apps to close
        appsToClose = runningApps.filter { app in
            let calendar = Calendar.current
            let dateComponents = calendar.dateComponents([.hour], from: app.value, to: currentDate)
            return dateComponents.hour ?? 0 >= RunningAppsManager.hoursUntilClose
        }.map { $0.key }
    }
}

struct ContentView: View {
    @StateObject private var manager = RunningAppsManager()

    var body: some View {
        VStack {
            List(Array(manager.runningApps).sorted(by: { $0.0 < $1.0 }), id: \.0) { app in
                let minutesUntilClose = (RunningAppsManager.hoursUntilClose * 60) - Int(Date().timeIntervalSince(app.1) / 60)
                Text("\(app.0): \(formatTime(minutes: minutesUntilClose)) hours until close")
            }
            .padding()
            
            Divider()
            
            Text("Apps to Close:")
                .font(.headline)
            
            List(manager.appsToClose, id: \.self) { app in
                Text(app)
            }
            .padding()
        }
    }
    
    private func formatTime(minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return String(format: "%d:%02d", hours, remainingMinutes)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
