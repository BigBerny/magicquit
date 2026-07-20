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
        let closingSoon = remaining < 3600 && isEnabled.wrappedValue

        HStack(spacing: 8) {
            Toggle("", isOn: isEnabled)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Image(nsImage: icon)
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

    private var icon: NSImage {
        NSWorkspace.shared.icon(forFile: entry.app.bundleURL?.path ?? "")
    }
}
