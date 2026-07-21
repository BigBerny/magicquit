import AppKit

/// Pure decision logic, free of UI and side effects so it stays unit-testable.
enum QuitPolicy {
    /// System UI processes that must never be tracked or quit.
    static let systemExcluded: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.systemuiserver",
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.coreautha",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.Siri",
    ]

    static func isTrackable(bundleId: String?, activationPolicy: NSApplication.ActivationPolicy, ownBundleId: String?) -> Bool {
        guard activationPolicy == .regular else { return false }
        guard let bundleId else { return true }
        return bundleId != ownBundleId && !systemExcluded.contains(bundleId)
    }

    static func remainingSeconds(lastActive: Date, now: Date, idleMinutes: Int) -> Int {
        idleMinutes * 60 - Int(now.timeIntervalSince(lastActive))
    }

    static func idleQuitDue(lastActive: Date, now: Date, idleMinutes: Int) -> Bool {
        remainingSeconds(lastActive: lastActive, now: now, idleMinutes: idleMinutes) <= 0
    }
}
