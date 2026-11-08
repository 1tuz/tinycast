import AppKit
import SwiftUI

/// One native window opened from settings or by saying "покажи голосовые команды".
/// It also displays disambiguation choices when speech matches multiple targets.
@MainActor
final class SpeechVoiceCommandCatalogWindow {
    private let core: AppCore
    private var window: NSWindow?

    init(core: AppCore) {
        self.core = core
    }

    func show() {
        present(SpeechVoiceCommandCatalogView(core: core), title: "Голосовые команды")
    }

    func showChoices(_ choices: [SpeechVoiceCommandParser.Target]) {
        present(SpeechVoiceCommandChoicesView(core: core, choices: choices),
                title: "Уточните голосовую команду")
    }

    func close() { window?.orderOut(nil) }

    private func present<Content: View>(_ content: Content, title: String) {
        if window == nil {
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 730, height: 590),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            panel.center()
            panel.isReleasedWhenClosed = false
            panel.minSize = NSSize(width: 560, height: 410)
            window = panel
        }
        guard let window else { return }
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SpeechVoiceAliasEdit: Identifiable {
    let id: String
    let name: String
    let preferenceKey: String
}

@MainActor
private struct SpeechVoiceCommandCatalogView: View {
    let core: AppCore
    @State private var search = ""
    @State private var aliasEdit: SpeechVoiceAliasEdit?
    @State private var aliasDraft = ""

    private let sections = [
        "Справка", "Приложения", "Окна", "Раскладки окон", "Комнаты окон", "Система",
        "Поиск и данные", "Заметки", "Календарь", "Apple Shortcuts", "Сценарии",
        "Пользовательские команды", "Quicklinks"
    ]

    private var allItems: [SpeechVoiceCommandParser.CatalogItem] {
        SpeechVoiceCommandParser.builtinCatalog
            + SpeechVoiceCommandRouter.availableTargets(core: core)
                .map { SpeechVoiceCommandParser.catalogItem(for: $0) }
    }

    private var matchingItems: [SpeechVoiceCommandParser.CatalogItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }
        return allItems.filter { item in
            item.title.localizedStandardContains(query)
                || item.section.localizedStandardContains(query)
                || item.phrases.contains(where: { $0.localizedStandardContains(query) })
        }
    }

    private func isEnabled(_ item: SpeechVoiceCommandParser.CatalogItem) -> Bool {
        guard let feature = item.feature else { return true }
        switch feature {
        case "windows": return core.settings.windowManagementEnabled
        case "files": return core.settings.fileSearchEnabled
        case "notes": return core.settings.notesEnabled
        case "shortcuts": return core.settings.appleShortcutsEnabled
        case "quicklinks": return core.settings.quicklinksEnabled
        case "customCommands": return core.settings.customCommandsEnabled
        case "workflows": return core.settings.workflowsEnabled
        default: return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "mic.circle")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Голосовые команды")
                        .font(.title2.weight(.semibold))
                    Text("Произносите команду, удерживая Hyper. Названия допускают небольшие ошибки распознавания.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Поиск команды, приложения или фразы", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(11)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            if !UserDefaults.standard.bool(forKey: "speechVoice.enabled") {
                Label("Голосовой ввод отключён в настройках AI", systemImage: "mic.slash")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else if UserDefaults.standard.object(forKey: "speechVoice.commandsEnabled") != nil
                        && !UserDefaults.standard.bool(forKey: "speechVoice.commandsEnabled") {
                Label("Выполнение голосовых команд отключено", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(sections, id: \.self) { section in
                        let items = matchingItems.filter { $0.section == section }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(section.uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                                    catalogRow(item)
                                }
                            }
                        }
                    }
                    if matchingItems.isEmpty {
                        Text("Совпадений нет")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(25)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            Text("Выполняется только однозначно распознанная команда. Для сценариев, скриптов и ссылок требуется подтверждение.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 410)
        .sheet(item: $aliasEdit) { edit in
            VStack(alignment: .leading, spacing: 14) {
                Text("Псевдонимы: \(edit.name)")
                    .font(.headline)
                TextField("Например: телега; тг; телеграмм", text: $aliasDraft)
                Text("Разделяйте точкой с запятой (до 8 названий). Все работают и в поиске Tinycast. Пустое поле удаляет псевдонимы.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Отмена") { aliasEdit = nil }
                    Button("Сохранить") {
                        core.aliases.setAliases(
                            aliasDraft.components(separatedBy: ";"), for: edit.preferenceKey)
                        aliasEdit = nil
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func editAlias(_ item: SpeechVoiceCommandParser.CatalogItem) {
        guard let id = item.targetID,
              let entry = core.appIndex.apps.first(where: { $0.id == id }) else { return }
        aliasDraft = core.aliases.allAliases(for: entry.preferenceKey).joined(separator: "; ")
        aliasEdit = SpeechVoiceAliasEdit(id: entry.id, name: entry.name, preferenceKey: entry.preferenceKey)
    }

    private func catalogRow(_ item: SpeechVoiceCommandParser.CatalogItem) -> some View {
        let enabled = isEnabled(item)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.body.weight(.medium))
                Text(item.phrases.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 4)
            if let id = item.targetID, core.appIndex.apps.contains(where: { $0.id == id }) {
                Button { editAlias(item) } label: {
                    Image(systemName: "pencil.line").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Изменить голосовой псевдоним")
            }
            if !enabled {
                Text("Отключено")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .opacity(enabled ? 1 : 0.6)
    }
}

@MainActor
private struct SpeechVoiceCommandChoicesView: View {
    let core: AppCore
    let choices: [SpeechVoiceCommandParser.Target]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Какую команду выполнить?")
                .font(.title2.weight(.semibold))
            Text("Распознанное название подходит нескольким объектам. Ничего не запускается без выбора.")
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                        Button {
                            core.voiceCommandCatalogWindow.close()
                            SpeechVoiceCommandRouter.execute(.target(choice.kind, choice.id), core: core)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(choice.name).font(.body.weight(.medium))
                                    Text(choice.kind.rawValue)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(11)
                        }
                        .buttonStyle(.plain)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Отмена") { core.voiceCommandCatalogWindow.close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 340)
    }
}
