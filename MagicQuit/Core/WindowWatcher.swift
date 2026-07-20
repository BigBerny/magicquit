import AppKit
import ApplicationServices
import os.log

/// Quits an app once its last window closes, using the Accessibility API.
///
/// The AX route is deliberate: CGWindowList does not report minimized windows,
/// which would make apps with only minimized windows look windowless.
@MainActor
final class WindowWatcher {
    var terminateHandler: ((NSRunningApplication) -> Void)?

    private struct Watch {
        let observer: AXObserver
        let element: AXUIElement
        var hadWindows: Bool
        let generation: Int
    }

    private let settings: AppSettings
    private var watches: [pid_t: Watch] = [:]
    private var nextGeneration = 0
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.MagicQuit", category: "WindowWatcher")

    /// Grace period between the destroy event and the final window-count check.
    static let quitDelay: TimeInterval = 2

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private var active: Bool { settings.quitOnLastWindowClosed && Self.isTrusted }

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// Reconcile watches with the desired state; called from the manager's sweep and on setting changes.
    /// Also retries apps whose registration failed earlier (no Watch entry yet) and
    /// re-scans watches that have not seen a window so far.
    func refresh(apps: [NSRunningApplication]) {
        guard active else {
            for pid in Array(watches.keys) {
                unwatch(pid)
            }
            return
        }
        for app in apps {
            watch(app)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for (pid, watch) in watches where !watch.hadWindows {
            let windows = Self.windowList(of: watch.element)
            guard !windows.isEmpty else { continue }
            for window in windows {
                AXObserverAddNotification(watch.observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
            }
            watches[pid]?.hadWindows = true
        }
    }

    func watch(_ app: NSRunningApplication) {
        guard active else { return }
        let pid = app.processIdentifier
        // No entry is stored unless registration succeeds, so failed attempts
        // (e.g. the app's AX server not being ready during launch) are retried
        // by the next refresh().
        guard watches[pid] == nil, pid > 0, app.isFinishedLaunching else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, windowWatcherCallback, &observer) == .success, let observer else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        let windows = Self.windowList(of: element)
        for window in windows {
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        nextGeneration += 1
        watches[pid] = Watch(observer: observer, element: element, hadWindows: !windows.isEmpty, generation: nextGeneration)
    }

    func unwatch(_ pid: pid_t) {
        guard let watch = watches.removeValue(forKey: pid) else { return }
        AXObserverRemoveNotification(watch.observer, watch.element, kAXWindowCreatedNotification as CFString)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watch.observer), .defaultMode)
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard watches[pid] != nil else { return }

        if notification == (kAXWindowCreatedNotification as String) {
            watches[pid]?.hadWindows = true
            if let watch = watches[pid] {
                let refcon = Unmanaged.passUnretained(self).toOpaque()
                AXObserverAddNotification(watch.observer, element, kAXUIElementDestroyedNotification as CFString, refcon)
            }
        } else if notification == (kAXUIElementDestroyedNotification as String) {
            if let generation = watches[pid]?.generation {
                scheduleWindowCountCheck(pid: pid, generation: generation)
            }
        }
    }

    private func scheduleWindowCountCheck(pid: pid_t, generation: Int) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.quitDelay * 1_000_000_000))
            self?.checkWindowCount(pid: pid, generation: generation)
        }
    }

    private func checkWindowCount(pid: pid_t, generation: Int) {
        guard active, let watch = watches[pid], watch.generation == generation, watch.hadWindows else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            unwatch(pid)
            return
        }
        // The menu checkbox means "never quit this app" — it protects against
        // both quit mechanisms, matching what it meant in 1.x.
        if let key = app.bundleIdentifier ?? app.executableURL?.path,
           settings.windowQuitExcluded.contains(key) || settings.idleQuitExcluded.contains(key) { return }
        guard app.isFinishedLaunching else { return }
        // Splash screens and staged launches: never window-quit a freshly launched app.
        if let launched = app.launchDate, Date().timeIntervalSince(launched) < 30 { return }
        guard Self.windowList(of: watch.element).isEmpty else { return }
        // AX does not report windows on inactive Spaces (incl. full-screen windows);
        // cross-check with CGWindowList, which sees all Spaces, before quitting.
        guard Self.cgWindowCount(pid: pid) == 0 else { return }

        log.debug("Last window closed: \(app.localizedName ?? "unknown", privacy: .public)")
        terminateHandler?(app)
    }

    private static func windowList(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as! [AXUIElement])
    }

    private static func cgWindowCount(pid: pid_t) -> Int {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return list.count {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && (($0[kCGWindowLayer as String] as? Int) ?? 0) == 0
        }
    }
}

private func windowWatcherCallback(observer: AXObserver, element: AXUIElement, notification: CFString, refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<WindowWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        watcher.handle(notification: name, element: element)
    }
}
