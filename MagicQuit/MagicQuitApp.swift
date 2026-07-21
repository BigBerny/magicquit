import SwiftUI
import AppKit

@main
struct MagicQuitApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var manager: RunningAppsManager

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _manager = StateObject(wrappedValue: RunningAppsManager(settings: settings))
        _ = UpdaterSupport.controller
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(manager)
                .environmentObject(settings)
        } label: {
            let image: NSImage = {
                $0.size.height = 18
                $0.size.width = 18
                $0.isTemplate = true
                return $0
            }(NSImage(named: "MenuBarIcon")!)

            Image(nsImage: image)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(manager)
                .environmentObject(settings)
        }
        .windowResizability(.contentSize)
    }
}
