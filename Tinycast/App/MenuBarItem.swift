import SwiftUI

/// VoiceCast's menu-bar item. Template rendering adapts the monochrome mark to light/dark mode.
struct MenuBarLabel: View {
    let appName: String

    var body: some View {
        Image("MenuBarIcon")
            .accessibilityLabel(appName)
    }
}

struct MenuBarMenu: View {
    let appName: String

    var body: some View {
        Button("Open \(appName)") {
            AppCore.shared.paletteCoordinator.showPalette(mode: .launcher)
        }
        // Read through Observation, so switching the feature off takes the row with it.
        if AppCore.shared.settings.clipboardEnabled {
            Button("Clipboard History") {
                AppCore.shared.paletteCoordinator.showPalette(mode: .clipboard)
            }
        }
        Menu("Focus", systemImage: "timer") {
            if AppCore.shared.focus.isActive {
                Text(AppCore.shared.focus.clockText)
                Button(AppCore.shared.focus.isPaused ? "Продолжить" : "Пауза") {
                    if AppCore.shared.focus.isPaused { AppCore.shared.focus.resume() }
                    else { AppCore.shared.focus.pause() }
                }
                Button("Завершить") { AppCore.shared.focus.finish() }
            } else {
                Button("Начать сеанс") { _ = AppCore.shared.focus.start() }
            }
            Divider()
            Button("Настройки фокуса…") {
                AppCore.shared.settingsCoordinator.showSettings(tab: .focus)
            }
        }
        Divider()
        Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        Button("Support \(appName)…") { AppCore.shared.supportCoordinator.showSupport() }
        Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
            .keyboardShortcut(",")
        Divider()
        // No ⌘Q: the app menu binds it to Close Settings, and two contradictory ⌘Qs is a lie.
        Button("Quit \(appName)") { NSApp.terminate(nil) }
    }
}
