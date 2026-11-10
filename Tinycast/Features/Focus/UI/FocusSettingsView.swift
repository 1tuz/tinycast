import AppKit
import SwiftUI

/// Native Settings pane, following Tinycast's grouped Form and sidebar conventions.
struct FocusSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(FocusSessionCoordinator.self) private var focus
    @State private var siteInput = ""
    @State private var showingAppPicker = false

    private var profile: FocusProfile? { focus.selectedProfile }

    var body: some View {
        Form {
            sessionSection
            profileSection
            if let profile {
                applicationsSection(profile)
                websitesSection(profile)
                automationSection(profile)
            }
            Section {
                Text(
                    "Приложения скрываются без закрытия. Блокировка сайтов действует только для " +
                    "активных вкладок Safari, Chrome, Brave и Edge. Firefox и Zen не поддерживаются. " +
                    "Для браузеров может понадобиться разрешение Automation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Ограничения")
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.focus)
        .releasesFocusOnOutsideClick()
        .sheet(isPresented: $showingAppPicker) {
            FocusApplicationPicker(profileID: focus.selectedProfileID)
        }
        .onAppear { core.appleShortcutCoordinator.refresh() }
    }

    private var sessionSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.xl) {
                Image(systemName: "timer")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(focus.activeProfile?.name ?? "Сеанс не запущен")
                        .font(.headline)
                    if focus.isActive {
                        Text(focus.clockText + (focus.isPaused ? " · Пауза" : ""))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Настройте профиль и запустите таймер")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if focus.isActive {
                    Button(focus.isPaused ? "Продолжить" : "Пауза") {
                        if focus.isPaused { focus.resume() } else { focus.pause() }
                    }
                    Button("Завершить") { focus.finish() }
                } else {
                    Button("Начать") { _ = focus.start() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.vertical, Theme.Spacing.sm)
        } header: {
            Text("Концентрация")
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: Theme.Spacing.md) {
                Picker("Профиль", selection: selectedProfileBinding) {
                    ForEach(focus.profiles) { profile in
                        Text(profile.name.isEmpty ? "Без названия" : profile.name)
                            .tag(profile.id)
                    }
                }
                Button { focus.addProfile() } label: {
                    Image(systemName: "plus")
                }
                .help("Создать профиль")
                Button {
                    focus.removeProfile(focus.selectedProfileID)
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(focus.profiles.count <= 1)
                .help("Удалить профиль")
            }
            if let profile {
                TextField("Название профиля", text: nameBinding(profile.id))
                Stepper(value: durationBinding(profile.id), in: 5...240, step: 5) {
                    Text("Длительность: \(profile.durationMinutes) мин")
                }
            }
        } header: {
            Text("Профили")
        }
    }

    private func applicationsSection(_ profile: FocusProfile) -> some View {
        Section {
            ForEach(profile.blockedApplications) { app in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary)
                    Text(app.name)
                    Spacer()
                    Button {
                        focus.removeApplication(app.bundleID, from: profile.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Исключить из списка блокировки")
                }
            }
            Button("Добавить приложение…", systemImage: "plus") {
                showingAppPicker = true
            }
        } header: {
            Text("Блокируемые приложения")
        }
    }

    private func websitesSection(_ profile: FocusProfile) -> some View {
        Section {
            ForEach(profile.blockedDomains, id: \.self) { domain in
                HStack {
                    Image(systemName: "globe")
                        .foregroundStyle(.secondary)
                    Text(domain)
                    Spacer()
                    Button {
                        focus.removeDomain(domain, from: profile.id)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("youtube.com", text: $siteInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addSite(profile.id) }
                Button("Добавить") { addSite(profile.id) }
                    .disabled(siteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Поддомены блокируются вместе с основным доменом.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Блокируемые сайты")
        }
    }

    private func automationSection(_ profile: FocusProfile) -> some View {
        Section {
            Picker("Сценарий при запуске", selection: workflowBinding(profile.id, start: true)) {
                workflowOptions
            }
            Picker("Сценарий при завершении", selection: workflowBinding(profile.id, start: false)) {
                workflowOptions
            }
            Picker("Apple Shortcut при запуске", selection: shortcutBinding(profile.id, start: true)) {
                shortcutOptions
            }
            Picker("Apple Shortcut при завершении", selection: shortcutBinding(profile.id, start: false)) {
                shortcutOptions
            }
            Text(
                "Сценарии SpeechCast и Apple Shortcuts выполняются автоматически. Через Shortcuts " +
                "можно запускать приложения, расставлять окна и включать системное «Не беспокоить».")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Голосовые сценарии и автоматизация")
        }
    }

    @ViewBuilder
    private var workflowOptions: some View {
        Text("Ничего не выполнять").tag(UUID?.none)
        ForEach(core.workflows.workflows.filter(\.isEnabled)) { workflow in
            Text(workflow.name).tag(Optional(workflow.id))
        }
    }

    @ViewBuilder
    private var shortcutOptions: some View {
        Text("Ничего не выполнять").tag(UUID?.none)
        ForEach(availableShortcuts) { shortcut in
            Text(shortcut.name).tag(Optional(shortcut.id))
        }
    }

    private var availableShortcuts: [AppleShortcut] {
        core.appleShortcutCoordinator.entries.compactMap { entry in
            guard let id = AppleShortcut.id(fromEntryID: entry.id) else { return nil }
            return AppleShortcut(id: id, name: entry.name)
        }
    }

    private var selectedProfileBinding: Binding<UUID> {
        Binding(get: { focus.selectedProfileID }, set: { focus.selectProfile($0) })
    }

    private func nameBinding(_ id: UUID) -> Binding<String> {
        Binding(
            get: { focus.profiles.first { $0.id == id }?.name ?? "" },
            set: { value in focus.updateProfile(id) { $0.name = value } })
    }

    private func durationBinding(_ id: UUID) -> Binding<Int> {
        Binding(
            get: { focus.profiles.first { $0.id == id }?.durationMinutes ?? 45 },
            set: { value in focus.updateProfile(id) { $0.durationMinutes = value } })
    }

    private func workflowBinding(_ id: UUID, start: Bool) -> Binding<UUID?> {
        Binding(
            get: {
                guard let profile = focus.profiles.first(where: { $0.id == id }) else { return nil }
                return start ? profile.startWorkflowID : profile.endWorkflowID
            },
            set: { value in
                focus.updateProfile(id) { profile in
                    if start { profile.startWorkflowID = value } else { profile.endWorkflowID = value }
                }
            })
    }

    private func shortcutBinding(_ id: UUID, start: Bool) -> Binding<UUID?> {
        Binding(
            get: {
                guard let profile = focus.profiles.first(where: { $0.id == id }) else { return nil }
                return start ? profile.startShortcutID : profile.endShortcutID
            },
            set: { value in
                focus.updateProfile(id) { profile in
                    if start { profile.startShortcutID = value } else { profile.endShortcutID = value }
                }
            })
    }

    private func addSite(_ profileID: UUID) {
        guard focus.addDomain(siteInput, to: profileID) else {
            core.showMessage("Неверное имя домена", tone: .neutral)
            return
        }
        siteInput = ""
    }
}

private struct FocusApplicationPicker: View {
    @Environment(AppCore.self) private var core
    @Environment(FocusSessionCoordinator.self) private var focus
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let profileID: UUID

    private var apps: [AppEntry] {
        core.appIndex.apps.filter { app in
            guard app.kind == .application, app.isPrimaryInstallation,
                  let bundleID = app.bundleID, !bundleID.isEmpty,
                  app.name.localizedCaseInsensitiveContains(query),
                  app.url.isFileURL else { return false }
            return true
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack {
                Text("Блокировать приложение")
                    .font(.headline)
                Spacer()
                Button("Готово") { dismiss() }
            }
            TextField("Поиск приложения", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xs) {
                    ForEach(apps, id: \.id) { app in
                        Button {
                            guard let bundleID = app.bundleID else { return }
                            focus.addApplication(
                                FocusBlockedApplication(bundleID: bundleID, name: app.name),
                                to: profileID)
                            dismiss()
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                    .resizable().frame(width: 24, height: 24)
                                Text(app.name)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(Theme.Spacing.lg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.primary.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: Theme.Radius.row))
                    }
                }
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 450, height: 450)
    }
}
