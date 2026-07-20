import AppKit
import Combine

/// Single source of truth for user settings, persisted to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let idleMinutes = "idleMinutes"
        static let showQuitButton = "showCloseButton" // key kept from 1.x
        static let quitOnLastWindowClosed = "quitOnLastWindowClosed"
        static let idleQuitExcluded = "idleQuitExcludedApps"
        static let windowQuitExcluded = "windowQuitExcludedApps"
        static let legacyHours = "hoursUntilClose"
        static let legacyToggles = "com.MagicQuit.toggleStatus"
    }

    static let defaultWindowQuitExcluded: Set<String> = [
        "com.apple.Music",
        "com.spotify.client",
        "com.apple.podcasts",
        "org.videolan.vlc",
    ]

    private let defaults: UserDefaults

    @Published var idleMinutes: Int {
        didSet { defaults.set(idleMinutes, forKey: Keys.idleMinutes) }
    }

    @Published var showQuitButton: Bool {
        didSet { defaults.set(showQuitButton, forKey: Keys.showQuitButton) }
    }

    @Published var quitOnLastWindowClosed: Bool {
        didSet { defaults.set(quitOnLastWindowClosed, forKey: Keys.quitOnLastWindowClosed) }
    }

    /// Bundle identifiers excluded from idle quitting (menu checkboxes).
    @Published var idleQuitExcluded: Set<String> {
        didSet { defaults.set(Array(idleQuitExcluded).sorted(), forKey: Keys.idleQuitExcluded) }
    }

    /// Bundle identifiers excluded from quit-on-last-window-closed.
    @Published var windowQuitExcluded: Set<String> {
        didSet { defaults.set(Array(windowQuitExcluded).sorted(), forKey: Keys.windowQuitExcluded) }
    }

    /// 1.x stored per-app enablement keyed by localized app name; consumed lazily as apps appear.
    private var legacyTogglesByName: [String: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let minutes = defaults.object(forKey: Keys.idleMinutes) as? Int {
            idleMinutes = minutes
        } else if let hours = defaults.object(forKey: Keys.legacyHours) as? Int {
            idleMinutes = IdleDuration.stepAtLeast(minutes: hours * 60)
        } else {
            idleMinutes = IdleDuration.defaultMinutes
        }

        showQuitButton = defaults.bool(forKey: Keys.showQuitButton)
        quitOnLastWindowClosed = defaults.bool(forKey: Keys.quitOnLastWindowClosed)
        idleQuitExcluded = Set(defaults.stringArray(forKey: Keys.idleQuitExcluded) ?? [])

        if let stored = defaults.stringArray(forKey: Keys.windowQuitExcluded) {
            windowQuitExcluded = Set(stored)
        } else {
            windowQuitExcluded = AppSettings.defaultWindowQuitExcluded
        }

        if let data = defaults.data(forKey: Keys.legacyToggles),
           let toggles = try? JSONDecoder().decode([String: Bool].self, from: data) {
            legacyTogglesByName = toggles
        } else {
            legacyTogglesByName = [:]
        }
    }

    /// Consume the 1.x per-app toggle for an app once its bundle identifier is known.
    func migrateLegacyToggleIfNeeded(appName: String?, bundleId: String?) {
        guard let appName, let bundleId,
              let enabled = legacyTogglesByName.removeValue(forKey: appName) else { return }
        if !enabled {
            idleQuitExcluded.insert(bundleId)
        }
        persistLegacyToggles()
    }

    private func persistLegacyToggles() {
        if legacyTogglesByName.isEmpty {
            defaults.removeObject(forKey: Keys.legacyToggles)
        } else if let data = try? JSONEncoder().encode(legacyTogglesByName) {
            defaults.set(data, forKey: Keys.legacyToggles)
        }
    }
}
