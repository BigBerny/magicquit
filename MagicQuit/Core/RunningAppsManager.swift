import AppKit
import Combine
import os.log

/// Why an automatic quit was triggered.
enum QuitReason {
    case idle
    case windowClose
}

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
    /// Floating countdown banner shown before an automatic quit; Cancel aborts it.
    let quitConfirmation = QuitConfirmation()

    /// How long the banner counts down before the quit actually happens.
    static let quitGraceSeconds = 20
    /// After this many cancels for the same app, back off so the app cannot be
    /// pestered forever by the sweep.
    static let maxCancelsPerApp = 5
    /// App is placed into a short sleep after being cancelled too often.
    static let cancelSleepSeconds: TimeInterval = 300

    private var sweepTimer: Timer?
    private var dueTimer: Timer?
    private var observerTokens: [NSObjectProtocol] = []
    private var distributedTokens: [NSObjectProtocol] = []
    /// Set while the machine is asleep or the screen is locked; that time is not counted as idle.
    private var pauseStarted: Date?
    /// Tracks how many times the user cancelled a quit for each pid, so we can
    /// stop pestering apps they clearly want to keep open.
    private var cancelsByPid: [pid_t: Int] = [:]
    /// Pids currently sleeping after too many cancels (with the runloop wake-up date).
    private var cancelSleepUntil: [pid_t: Date] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.MagicQuit", category: "RunningAppsManager")

    init(settings: AppSettings) {
        self.settings = settings
        self.windowWatcher = WindowWatcher(settings: settings)
        windowWatcher.terminateHandler = { [weak self] app in self?.quit(app, reason: .windowClose) }

        // If the app terminates on its own while the banner is up, close the banner.
        // The banner reaching zero calls terminateAfterGrace; the same expiry
        // hook is what makes the banner close when the target dies itself.
        quitConfirmation.expireAction = { [weak self] app in self?.terminateAfterGrace(app) }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observerTokens.append(workspaceCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil,
                                                          queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self,
                      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.quitConfirmation.dismissIfPresenting(pid: app.processIdentifier)
            }
        })

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
            Task { @MainActor [weak self] in self?.pauseTimers() }
        })
        observerTokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.creditPausedTime() }
        })

        let distributed = DistributedNotificationCenter.default()
        distributedTokens.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.pauseTimers() }
        })
        distributedTokens.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor [weak self] in self?.creditPausedTime() }
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
        dueTimer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        for token in observerTokens {
            center.removeObserver(token)
        }
        let distributed = DistributedNotificationCenter.default()
        for token in distributedTokens {
            distributed.removeObserver(token)
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

    private func pauseTimers() {
        if pauseStarted == nil {
            pauseStarted = Date()
        }
    }

    private func creditPausedTime() {
        guard let start = pauseStarted else { return }
        pauseStarted = nil
        let paused = Date().timeIntervalSince(start)
        guard paused > 0 else { return }
        let now = Date()
        for pid in tracked.keys {
            if let shifted = tracked[pid]?.lastActive.addingTimeInterval(paused) {
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

        // Never quit while asleep/locked — paused time is credited back on unlock.
        guard pauseStarted == nil else { return }

        let now = Date()
        for entry in tracked.values {
            guard entry.app.isFinishedLaunching,
                  isIdleQuitEnabled(entry.app),
                  QuitPolicy.idleQuitDue(lastActive: entry.lastActive, now: now, idleMinutes: settings.idleMinutes)
            else { continue }
            // Skip apps the user just spent 20 s clicking Cancel on.
            if let sleepUntil = cancelSleepUntil[entry.app.processIdentifier], sleepUntil > now {
                continue
            }
            quit(entry.app, reason: .idle)
        }
        scheduleDueCheck(now: now)
    }

    /// The sweep runs every 30s; when an app is due sooner, fire once exactly then
    /// so the menu countdown never sits at "0 s" waiting for the next sweep.
    /// While a confirm banner is up, we do not schedule future checks for that
    /// app; the banner's own countdown drives the expiry.
    private func scheduleDueCheck(now: Date) {
        dueTimer?.invalidate()
        dueTimer = nil
        let presentingPid = quitConfirmation.app?.processIdentifier
        let soonest = tracked.values
            .filter { isIdleQuitEnabled($0.app) }
            .filter { $0.app.processIdentifier != presentingPid }
            .map { QuitPolicy.remainingSeconds(lastActive: $0.lastActive, now: now, idleMinutes: settings.idleMinutes) }
            .min()
        guard let soonest, soonest > 0, soonest < 30 else { return }
        dueTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(soonest) + 1, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.sweep() }
        }
    }

    /// Called from the countdown banner when it reaches zero: quit immediately.
    func terminateAfterGrace(_ app: NSRunningApplication) {
        quitNow(app)
    }

    /// Immediate terminate, used by the manual quit button in the menu
    /// (no grace period — clicking ✕ means quit now).
    func quitNowFromMenu(_ app: NSRunningApplication) {
        quitConfirmation.dismissIfPresenting(pid: app.processIdentifier)
        quitNow(app)
    }

    /// Immediate terminate without the banner (countdown already elapsed).
    private func quitNow(_ app: NSRunningApplication) {
        if app.isTerminated { return }
        log.debug("Quitting \(app.localizedName ?? "unknown", privacy: .public)")
        if app.terminate() {
            untrack(app)
        }
    }

    /// Graceful quit with a countdown banner. Both the idle sweep and the
    /// window-close watcher use this so the user can cancel an automatic quit.
    /// The manual ✕ in the menu calls quitNowFromMenu and is instant.
    func quit(_ app: NSRunningApplication, reason: QuitReason = .idle) {
        guard !app.isTerminated else { return }
        if !settings.confirmBeforeAutoQuit {
            quitNow(app)
            return
        }
        if let presented = quitConfirmation.app, presented.processIdentifier == app.processIdentifier {
            log.info("Quit already pending for \(app.localizedName ?? "unknown", privacy: .public)")
            return
        }
        if quitConfirmation.isPresenting {
            // Another app is already in its grace period; it will finish its
            // countdown (or be cancelled) before the next sweep.
            return
        }
        quitConfirmation.present(app, graceSeconds: Self.quitGraceSeconds) {
            // Cancel: settle the timer and back off if the user keeps cancelling.
            let pid = app.processIdentifier
            switch reason {
            case .idle:
                self.resetTimer(for: pid)
            case .windowClose:
                self.windowWatcher.unwatch(pid)
            }
            let cancels = (self.cancelsByPid[pid] ?? 0) + 1
            self.cancelsByPid[pid] = cancels
            if cancels >= Self.maxCancelsPerApp {
                self.cancelSleepUntil[pid] = Date().addingTimeInterval(Self.cancelSleepSeconds)
                self.cancelsByPid[pid] = 0
                self.log.info("Too many cancels for \(app.localizedName ?? "unknown", privacy: .public); backing off for \(Self.cancelSleepSeconds, privacy: .public) s")
            }
        }
    }

    func resetTimer(for pid: pid_t) {
        tracked[pid]?.lastActive = Date()
    }

    // MARK: - Per-app exclusion ("never quit this app")

    /// Stable per-app key; falls back to the executable path for the rare app
    /// without a bundle identifier so its checkbox still works.
    private func exclusionKey(for app: NSRunningApplication) -> String? {
        app.bundleIdentifier ?? app.executableURL?.path
    }

    func canToggleIdleQuit(_ app: NSRunningApplication) -> Bool {
        exclusionKey(for: app) != nil
    }

    func isIdleQuitEnabled(_ app: NSRunningApplication) -> Bool {
        guard let key = exclusionKey(for: app) else { return true }
        return !settings.idleQuitExcluded.contains(key)
    }

    func setIdleQuitEnabled(_ enabled: Bool, for app: NSRunningApplication) {
        guard let key = exclusionKey(for: app) else { return }
        if enabled {
            settings.idleQuitExcluded.remove(key)
        } else {
            settings.idleQuitExcluded.insert(key)
        }
    }
}
