import SwiftUI
import AppKit

struct MenuView: View {
    @EnvironmentObject private var manager: RunningAppsManager
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    private var sortedApps: [RunningAppsManager.TrackedApp] {
        manager.tracked.values.sorted {
            ($0.app.localizedName ?? "").localizedCaseInsensitiveCompare($1.app.localizedName ?? "") == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let rows = VStack(spacing: 2) {
                    ForEach(sortedApps) { entry in
                        AppRowView(entry: entry, now: context.date)
                    }
                }
                if sortedApps.count > 12 {
                    ScrollView {
                        rows
                    }
                    .frame(height: 420)
                } else {
                    rows
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            if settings.quitOnLastWindowClosed && !WindowWatcher.isTrusted {
                MenuActionButton(title: "Grant Accessibility Access…") {
                    WindowWatcher.promptForAccess()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            MenuActionButton(title: "Settings…") {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuActionButton(title: "Quit MagicQuit") {
                NSApp.terminate(nil)
            }
            .padding(.bottom, 6)
        }
        .frame(width: 320)
    }
}

struct MenuActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isHovered ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Color.accentColor : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .onHover { isHovered = $0 }
    }
}
