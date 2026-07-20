import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var selectedPage: SettingsPage = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = WindowWatcher.isTrusted

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selectedPage, version: versionString)

            Divider()

            ScrollView {
                Group {
                    switch selectedPage {
                    case .general:
                        generalSettings
                    case .windows:
                        windowSettings
                    }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 720, height: 540)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                accessibilityGranted = WindowWatcher.isTrusted
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeader(
                title: "General",
                subtitle: "Choose when MagicQuit runs and how it handles inactive apps."
            )

            SettingsCard {
                SettingRow(
                    icon: "power",
                    title: "Launch at login",
                    detail: "Keep MagicQuit ready whenever you use your Mac."
                ) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                }

                SettingsDivider()

                SettingRow(
                    icon: "clock",
                    title: "Quit inactive apps",
                    detail: "Quit apps after they have not been used for this long."
                ) {
                    Picker("Idle duration", selection: $settings.idleMinutes) {
                        ForEach(IdleDuration.stepsInMinutes, id: \.self) { minutes in
                            Text(IdleDuration.label(minutes: minutes))
                                .tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 96)
                }

                SettingsDivider()

                SettingRow(
                    icon: "xmark.circle",
                    title: "Show quit buttons",
                    detail: "Add a manual quit action beside every app in the menu."
                ) {
                    Toggle("", isOn: $settings.showQuitButton)
                        .labelsHidden()
                }
            }

            InfoCard(
                icon: "sparkles",
                title: "Quiet by design",
                detail: "MagicQuit only quits apps normally, just like pressing ⌘Q. Apps with unsaved changes can still ask you to save."
            )
        }
    }

    private var windowSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeader(
                title: "Window Quitting",
                subtitle: "Optionally quit an app as soon as its last window closes."
            )

            SettingsCard {
                SettingRow(
                    icon: "macwindow",
                    title: "Quit on last window close",
                    detail: "Make closing the last window quit the app as well."
                ) {
                    Toggle("", isOn: $settings.quitOnLastWindowClosed)
                        .labelsHidden()
                        .onChange(of: settings.quitOnLastWindowClosed) { _, enabled in
                            if enabled && !WindowWatcher.isTrusted {
                                WindowWatcher.promptForAccess()
                            }
                            accessibilityGranted = WindowWatcher.isTrusted
                        }
                }
            }

            if settings.quitOnLastWindowClosed && !accessibilityGranted {
                PermissionCard {
                    WindowWatcher.promptForAccess()
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Excluded Apps")
                            .font(.headline)

                        Text("These apps stay open after their last window closes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        addExcludedApp()
                    } label: {
                        Label("Add App", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                ExcludedAppsCard(
                    bundleIds: sortedExcludedApps,
                    displayName: displayName(for:),
                    icon: icon(for:),
                    remove: { settings.windowQuitExcluded.remove($0) }
                )
            }
        }
        .animation(.snappy, value: accessibilityGranted)
        .animation(.snappy, value: settings.quitOnLastWindowClosed)
    }

    private var sortedExcludedApps: [String] {
        settings.windowQuitExcluded.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    private func displayName(for bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else {
            return bundleId
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    private func icon(for bundleId: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            if let bundleId = Bundle(url: url)?.bundleIdentifier {
                settings.windowQuitExcluded.insert(bundleId)
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general
    case windows

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .windows: "Window Quitting"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .windows: "macwindow"
        }
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsPage
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("Image")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("MagicQuit")
                        .font(.headline)

                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 20)

            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    Button {
                        selection = page
                    } label: {
                        Label(page.title, systemImage: page.icon)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selection == page ? Color.white : Color.primary)
                    .background {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selection == page ? Color.accentColor : Color.clear)
                    }
                    .accessibilityAddTraits(selection == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Text("Version \(version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(16)
        }
        .frame(width: 176)
        .background(.ultraThinMaterial)
    }
}

private struct SettingsHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 24, weight: .bold))

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45))
        }
    }
}

private struct SettingRow<Control: View>: View {
    let icon: String
    let title: String
    let detail: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 31, height: 31)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            control
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 60)
    }
}

private struct InfoCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .fontWeight(.semibold)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PermissionCard: View {
    let action: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text("Accessibility access required")
                    .fontWeight(.semibold)

                Text("MagicQuit needs access to detect when the last window closes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Open Settings", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.orange.opacity(0.2))
        }
    }
}

private struct ExcludedAppsCard: View {
    let bundleIds: [String]
    let displayName: (String) -> String
    let icon: (String) -> NSImage
    let remove: (String) -> Void

    var body: some View {
        SettingsCard {
            if bundleIds.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)

                    Text("No excluded apps")
                        .fontWeight(.medium)

                    Text("Window quitting applies to every app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(Array(bundleIds.enumerated()), id: \.element) { index, bundleId in
                    HStack(spacing: 12) {
                        Image(nsImage: icon(bundleId))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayName(bundleId))
                                .fontWeight(.medium)
                                .lineLimit(1)

                            Text(bundleId)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button {
                            remove(bundleId)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 18, height: 18)
                                .background(Color.secondary.opacity(0.15), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Remove \(displayName(bundleId))")
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 52)

                    if index < bundleIds.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
    }
}
