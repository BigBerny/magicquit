import AppKit
import SwiftUI
import os.log

/// A small floating banner shown right before MagicQuit quits an app:
/// a live countdown (default 20 s) with a Cancel button so an automatic
/// quit can be aborted. Pushes itself above everything else, all Spaces.
@MainActor
final class QuitConfirmation: ObservableObject {
    @Published private(set) var appName: String = ""
    @Published private(set) var remaining: Int = QuitConfirmation.defaultGraceSeconds

    static let defaultGraceSeconds = 20

    private var target: NSRunningApplication?
    private var timer: Timer?
    private var panel: NSPanel?
    private var cancelAction: (() -> Void)?
    var expireAction: ((NSRunningApplication) -> Void)?

    /// The app the banner is currently shown for, if any.
    var app: NSRunningApplication? { target }
    var isPresenting: Bool { target != nil }

    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.MagicQuit", category: "QuitConfirmation")

    /// Shows the banner for `app`. Ignored while a banner is already on screen
    /// (the next sweep will pick up any other app that comes due).
    func present(_ app: NSRunningApplication, graceSeconds: Int, onCancel: @escaping () -> Void) {
        guard target == nil else { return }
        self.target = app
        self.cancelAction = onCancel
        self.appName = app.localizedName ?? "this app"
        self.remaining = graceSeconds

        let hosting = NSHostingView(rootView: QuitCountdownView().environmentObject(self))
        let size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        self.panel = panel

        position(panel)

        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        panel.orderFrontRegardless()
        log.info("Quit confirmation shown for \(self.appName, privacy: .public)")
    }

    /// Closes the banner without quitting anything.
    func dismiss() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        target = nil
        cancelAction = nil
    }

    /// If the banner is currently showing for this app, close it — the app
    /// went away on its own.
    func dismissIfPresenting(pid: pid_t) {
        if target?.processIdentifier == pid {
            log.info("Banner dismissed: \(self.appName, privacy: .public) terminated on its own")
            dismiss()
        }
    }

    func cancel() {
        log.info("Quit cancelled for \(self.appName, privacy: .public)")
        let action = cancelAction
        dismiss()
        action?()
    }

    // MARK: - Private

    private func tick() {
        guard target != nil else { return }
        remaining -= 1
        if remaining <= 0 {
            log.info("Countdown finished for \(self.appName, privacy: .public)")
            let action = expireAction
            let app = target
            dismiss()
            if let app { action?(app) }
        }
    }

    /// Top-right, like a notification banner, just below the menu bar.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: screen.visibleFrame.maxX - size.width - 16,
            y: screen.visibleFrame.maxY - size.height - 12
        )
        panel.setFrameOrigin(origin)
    }
}

/// The banner's SwiftUI content: app name, live countdown, Cancel button.
private struct QuitCountdownView: View {
    @EnvironmentObject private var confirmation: QuitConfirmation

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: confirmation.app.map { AppIconCache.icon(for: $0) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quit \(confirmation.appName)?")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text("Quitting in \(confirmation.remaining) s")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            Button("Cancel") {
                confirmation.cancel()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 290)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }
}
