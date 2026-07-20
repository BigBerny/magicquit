import AppKit
import Combine
import os.log

/// Tracks regular apps and quits them once they have been idle for the configured duration.
@MainActor
final class RunningAppsManager: ObservableObject {
    struct TrackedApp: Identifiable {
        let app: NSRunningApplication
        var lastActive: Date
        var id: pid_t { app.processIdentifier }
    }

    @Published private(set) var tracked: [pid_t: TrackedApp] = [:]

    let settings: AppSettings
    let windowWatcher: WindowWatcher

    private var sweepTimer: Timer?
    private var observerTokens: [NSObjectProtocol] = []
    private var sleepStarted: Date?
    private var cancellables: Set<AnyCancellable> = []
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.MagicQuit", category: "RunningAppsManager")

    init(settings: AppSettings) {
        self.settings = settings
        self.windowWatcher = WindowWatcher(settings: settings)
        windowWatcher.terminateHandler = { [weak self] app in self?.quit(app) }

        reconcile()

        let center = NSWorkspace.shared.notificationCenter
        func observeApp(_ name: Notification.Name, _ handler: @escaping @MainActor (NSRunningApplication) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in handler(app) }
            }
            observerTokens.append(token)
        }

        observeApp(NSWorkspace.didActivateApplicationNotification) { [weak self] app in self?.touch(app) }
        observeApp(NSWorkspace.didDeactivateApplicationNotification) { [weak self] app in self?.touch(app) }
        observeApp(NSWorkspace.didLaunchApplicationNotification) { [weak self] app in self?.track(app) }
        observeApp(NSWorkspace.didTerminateApplicationNotification) { [weak self] app in self?.untrack(app) }

        observerTokens.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.sleepStarted = Date() }
        })
        observerTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.creditSleepTime() }
        })

        sweepTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.sweep() }
        }

        settings.$quitOnLastWindowClosed
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.windowWatcher.refresh(apps: self.tracked.values.map(\.app))
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        sweepTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        for token in observerTokens {
            center.removeObserver(token)
        }
    }

    // MARK: - Tracking

    private func track(_ app: NSRunningApplication) {
        guard QuitPolicy.isTrackable(bundleId: app.bundleIdentifier,
                                     activationPolicy: app.activationPolicy,
                                     ownBundleId: Bundle.main.bundleIdentifier) else { return }
        settings.migrateLegacyToggleIfNeeded(appName: app.localizedName, bundleId: app.bundleIdentifier)
        if tracked[app.processIdentifier] == nil {
            tracked[app.processIdentifier] = TrackedApp(app: app, lastActive: Date())
        }
        windowWatcher.watch(app)
    }

    private func untrack(_ app: NSRunningApplication) {
        tracked[app.processIdentifier] = nil
        windowWatcher.unwatch(app.processIdentifier)
    }

    private func touch(_ app: NSRunningApplication) {
        track(app)
        tracked[app.processIdentifier]?.lastActive = Date()
    }

    private func reconcile() {
        let running = NSWorkspace.shared.runningApplications
        let runningPids = Set(running.map(\.processIdentifier))

        for (pid, entry) in tracked {
            let gone = !runningPids.contains(pid) || entry.app.isTerminated
            let untrackable = !QuitPolicy.isTrackable(bundleId: entry.app.bundleIdentifier,
                                                      activationPolicy: entry.app.activationPolicy,
                                                      ownBundleId: Bundle.main.bundleIdentifier)
            if gone || untrackable {
                tracked[pid] = nil
                windowWatcher.unwatch(pid)
            }
        }

        for app in running {
            track(app)
        }
    }

    private func creditSleepTime() {
        guard let start = sleepStarted else { return }
        sleepStarted = nil
        let slept = Date().timeIntervalSince(start)
        guard slept > 0 else { return }
        let now = Date()
        for pid in tracked.keys {
            if let shifted = tracked[pid]?.lastActive.addingTimeInterval(slept) {
                tracked[pid]?.lastActive = min(shifted, now)
            }
        }
    }

    // MARK: - Quitting

    func sweep() {
        reconcile()
        if let frontmost = NSWorkspace.shared.frontmostApplication {
            touch(frontmost)
        }
        windowWatcher.refresh(apps: tracked.values.map(\.app))

        let now = Date()
        for entry in tracked.values {
            guard entry.app.isFinishedLaunching,
                  isIdleQuitEnabled(entry.app),
                  QuitPolicy.idleQuitDue(lastActive: entry.lastActive, now: now, idleMinutes: settings.idleMinutes)
            else { continue }
            quit(entry.app)
        }
    }

    func quit(_ app: NSRunningApplication) {
        log.debug("Quitting \(app.localizedName ?? "unknown", privacy: .public)")
        if app.terminate() {
            untrack(app)
        }
    }

    func resetTimer(for pid: pid_t) {
        tracked[pid]?.lastActive = Date()
    }

    // MARK: - Per-app idle-quit exclusion

    func isIdleQuitEnabled(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return true }
        return !settings.idleQuitExcluded.contains(id)
    }

    func setIdleQuitEnabled(_ enabled: Bool, for app: NSRunningApplication) {
        guard let id = app.bundleIdentifier else { return }
        if enabled {
            settings.idleQuitExcluded.remove(id)
        } else {
            settings.idleQuitExcluded.insert(id)
        }
    }
}
