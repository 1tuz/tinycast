import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @Environment(AppCore.self) private var core
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    @State private var calendarAccess = Permissions.calendarAccess()
    @State private var microphoneAccess = Permissions.microphoneAccess()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: accessibilityStatus.symbol)
                                .accessibilityHidden(true)
                            Text(accessibilityStatus.title)
                        }
                        .foregroundStyle(accessibilityStatus.tint)
                        Button(accessibilityTrusted ? "Open…" : "Grant Access…") {
                            Permissions.openAccessibilitySettings()
                        }
                        .help("Opens Privacy & Security › Accessibility.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/AccessibilitySettingsExtension.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsAccessibility, "Accessibility")
                            Text("Pastes into the app you were using.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsAccessibility)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: calendarStatus.symbol)
                                .accessibilityHidden(true)
                            Text(calendarStatus.title)
                        }
                        .foregroundStyle(calendarStatus.tint)
                        Button(calendarNeedsPrompt ? "Grant Access…" : "Open…") {
                            // Settings lists no app TCC was never asked about, so asking is the way in.
                            if calendarNeedsPrompt {
                                core.calendarCoordinator.setCalendarEnabled(true)
                            } else {
                                Permissions.openCalendarSettings()
                            }
                        }
                        .help(
                            calendarNeedsPrompt
                                ? "Turns the calendar on, then asks macOS for access."
                                : "Opens Privacy & Security › Calendars.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path: "/System/Applications/Calendar.app")
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsCalendars, "Calendars")
                            Text("Finds the join link for your next meeting.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsCalendars)
            }

            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.lg) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: microphoneStatus.symbol)
                                .accessibilityHidden(true)
                            Text(microphoneStatus.title)
                        }
                        .foregroundStyle(microphoneStatus.tint)
                        Button(microphoneNeedsPrompt ? "Grant Access…" : "Open…") {
                            if microphoneNeedsPrompt {
                                Task {
                                    _ = await Permissions.requestMicrophoneAccess()
                                    refresh()
                                }
                            } else {
                                Permissions.openMicrophoneSettings()
                            }
                        }
                        .help(
                            microphoneNeedsPrompt
                                ? "Asks macOS for microphone access for Voice Ask."
                                : "Opens Privacy & Security › Microphone.")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.lg) {
                        PermissionSettingsIcon(
                            path:
                                "/System/Library/ExtensionKit/Extensions/Sound.appex"
                        )
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            SettingsRowTitle(.permissionsMicrophone, "Microphone")
                            Text("Voice Ask sends speech to Codex for transcription.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                SettingsSectionHeader(.permissionsMicrophone)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.permissions)
        .onAppear(perform: refresh)
        .onReceive(refreshTimer) { _ in refresh() }
    }

    private var calendarNeedsPrompt: Bool { calendarAccess == .notDetermined }
    private var microphoneNeedsPrompt: Bool { microphoneAccess == .notDetermined }

    private var accessibilityStatus: (title: String, symbol: String, tint: Color) {
        accessibilityTrusted
            ? ("Granted", "checkmark.circle.fill", .green)
            : ("Not granted", "exclamationmark.triangle.fill", .orange)
    }

    private var calendarStatus: (title: String, symbol: String, tint: Color) {
        switch calendarAccess {
        case .granted: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        case .denied: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    private var microphoneStatus: (title: String, symbol: String, tint: Color) {
        switch microphoneAccess {
        case .granted: return ("Granted", "checkmark.circle.fill", .green)
        case .notDetermined: return ("Not asked yet", "questionmark.circle.fill", .secondary)
        case .denied: return ("Not granted", "exclamationmark.triangle.fill", .orange)
        }
    }

    private func refresh() {
        let trusted = Permissions.isAccessibilityTrusted()
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let calendar = Permissions.calendarAccess()
        if calendar != calendarAccess { calendarAccess = calendar }
        let microphone = Permissions.microphoneAccess()
        if microphone != microphoneAccess { microphoneAccess = microphone }
    }
}

private struct PermissionSettingsIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: IconCache.icon(forFile: path))
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .id(IconCache.style.generation)
            .frame(
                width: SettingsListMetrics.iconSize,
                height: SettingsListMetrics.iconSize
            )
            .accessibilityHidden(true)
    }
}
