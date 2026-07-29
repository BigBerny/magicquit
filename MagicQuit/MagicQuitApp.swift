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
            MenuBarIconLabel()
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

struct MenuBarIconLabel: View {
    var body: some View {
        if let image = MenuBarIconProvider.configuredImage(
            asset: NSImage(named: "MenuBarIcon"),
            fallback: NSImage(systemSymbolName: "hourglass", accessibilityDescription: "MagicQuit")
        ) {
            Image(nsImage: image)
        } else {
            Text("MQ")
                .accessibilityLabel("MagicQuit")
        }
    }
}

enum MenuBarIconProvider {
    static func configuredImage(asset: NSImage?, fallback: NSImage?) -> NSImage? {
        guard let source = asset ?? fallback,
              let image = source.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
