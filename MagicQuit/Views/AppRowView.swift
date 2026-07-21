import SwiftUI
import AppKit

struct AppRowView: View {
    @EnvironmentObject private var manager: RunningAppsManager
    @EnvironmentObject private var settings: AppSettings

    let entry: RunningAppsManager.TrackedApp
    let now: Date

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { manager.isIdleQuitEnabled(entry.app) },
            set: { manager.setIdleQuitEnabled($0, for: entry.app) }
        )
    }

    var body: some View {
        let remaining = QuitPolicy.remainingSeconds(lastActive: entry.lastActive, now: now, idleMinutes: settings.idleMinutes)
        // Relative threshold so short idle durations are not permanently "closing soon"
        let closingSoon = remaining < min(3600, settings.idleMinutes * 15) && isEnabled.wrappedValue

        HStack(spacing: 8) {
            Toggle("", isOn: isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!manager.canToggleIdleQuit(entry.app))

            Image(nsImage: AppIconCache.icon(for: entry.app))
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

            Text(entry.app.localizedName ?? "Unknown")
                .lineLimit(1)
                .truncationMode(.tail)
                .fontWeight(closingSoon ? .semibold : .regular)
                .foregroundStyle(isEnabled.wrappedValue ? Color.primary : Color.secondary)

            Spacer(minLength: 8)

            if isEnabled.wrappedValue {
                Text(IdleDuration.shortRemaining(seconds: remaining))
                    .monospacedDigit()
                    .fontWeight(closingSoon ? .semibold : .regular)
                    .foregroundStyle(closingSoon ? Color.primary : Color.secondary)
            }

            Button {
                manager.resetTimer(for: entry.id)
            } label: {
                Image(systemName: "arrow.uturn.backward.circle")
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled.wrappedValue)

            if settings.showQuitButton {
                Button {
                    manager.quit(entry.app)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
    }

}

/// Icon lookups are not cheap; the menu re-renders every second while open.
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for app: NSRunningApplication) -> NSImage {
        let path = app.bundleURL?.path ?? app.executableURL?.path ?? ""
        if let cached = cache[path] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        cache[path] = icon
        return icon
    }
}
