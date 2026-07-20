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
    }

    private let settings: AppSettings
    private var watches: [pid_t: Watch] = [:]
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
    }

    func watch(_ app: NSRunningApplication) {
        guard active else { return }
        let pid = app.processIdentifier
        guard watches[pid] == nil, pid > 0 else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, windowWatcherCallback, &observer) == .success, let observer else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        let windows = Self.windowList(of: element)
        for window in windows {
            AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString, refcon)
        }
        watches[pid] = Watch(observer: observer, element: element, hadWindows: !windows.isEmpty)
    }

    func unwatch(_ pid: pid_t) {
        guard let watch = watches.removeValue(forKey: pid) else { return }
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
            scheduleWindowCountCheck(pid: pid)
        }
    }

    private func scheduleWindowCountCheck(pid: pid_t) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.quitDelay * 1_000_000_000))
            self?.checkWindowCount(pid: pid)
        }
    }

    private func checkWindowCount(pid: pid_t) {
        guard active, let watch = watches[pid], watch.hadWindows else { return }
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else {
            unwatch(pid)
            return
        }
        if let id = app.bundleIdentifier, settings.windowQuitExcluded.contains(id) { return }
        guard app.isFinishedLaunching else { return }
        guard Self.windowList(of: watch.element).isEmpty else { return }

        log.debug("Last window closed: \(app.localizedName ?? "unknown", privacy: .public)")
        terminateHandler?(app)
    }

    private static func windowList(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as! [AXUIElement])
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
