import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = WindowWatcher.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }

                Stepper {
                    LabeledContent("Quit apps after", value: IdleDuration.label(minutes: settings.idleMinutes))
                } onIncrement: {
                    settings.idleMinutes = IdleDuration.stepUp(from: settings.idleMinutes)
                } onDecrement: {
                    settings.idleMinutes = IdleDuration.stepDown(from: settings.idleMinutes)
                }

                Toggle("Show quit buttons in the menu", isOn: $settings.showQuitButton)
            }

            Section {
                Toggle("Quit apps when the last window closes", isOn: $settings.quitOnLastWindowClosed)
                    .onChange(of: settings.quitOnLastWindowClosed) { _, enabled in
                        if enabled && !WindowWatcher.isTrusted {
                            WindowWatcher.promptForAccess()
                        }
                        accessibilityGranted = WindowWatcher.isTrusted
                    }

                if settings.quitOnLastWindowClosed && !accessibilityGranted {
                    Button("Grant Accessibility Access…") {
                        WindowWatcher.promptForAccess()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                }

                if settings.quitOnLastWindowClosed {
                    excludedApps
                }
            } header: {
                Text("Windows")
            }

            Section {
                HStack(spacing: 12) {
                    Image("Image")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MagicQuit")
                        Text(versionString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                accessibilityGranted = WindowWatcher.isTrusted
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    @ViewBuilder
    private var excludedApps: some View {
        let excluded = settings.windowQuitExcluded.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }

        ForEach(excluded, id: \.self) { bundleId in
            HStack(spacing: 8) {
                Image(nsImage: icon(for: bundleId))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                Text(displayName(for: bundleId))
                Spacer()
                Button {
                    settings.windowQuitExcluded.remove(bundleId)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }

        Button("Add App…") {
            addExcludedApp()
        }
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    private func displayName(for bundleId: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return bundleId }
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
