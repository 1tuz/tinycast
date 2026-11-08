import AppKit

/// Safely executes only resolved, explicitly allowlisted Tinycast commands.
@MainActor
enum SpeechVoiceCommandRouter {
    typealias Parser = SpeechVoiceCommandParser

    static func route(_ speech: String, core: AppCore) -> Bool {
        switch Parser.parse(speech, targets: availableTargets(core: core)) {
        case .notCommand:
            return false
        case .unknown(let message):
            core.quickAICoordinator.composeVoicePrompt(speech)
            core.showMessage(message, tone: .neutral)
            return true
        case .ambiguous(let targets):
            // Never guess if two applications or actions have similarly plausible names.
            core.voiceCommandCatalogWindow.showChoices(targets)
            return true
        case .action(.aiPrompt(let trigger, let prompt)):
            // The trigger entry decides the model; a missing entry falls back to the default.
            let entry = AIVoiceTriggerStore.triggers().first {
                SpeechVoiceCommandParser.normalize($0.trigger) == trigger
            }
            core.quickAICoordinator.sendVoicePrompt(prompt, model: entry?.model)
            return true
        case .action(let intent):
            let targetID = SpeechVoiceCommandHistory.targetID(for: intent)
            execute(intent, core: core)
            if let targetID { SpeechVoiceCommandHistory.lastVoiceTargetID = targetID }
            return true
        }
    }

    static func availableTargets(core: AppCore) -> [Parser.Target] {
        var targets: [Parser.Target] = []
        var seen = Set<String>()
        for entry in core.appIndex.apps where entry.isPrimaryInstallation && core.visibility.isVisible(entry) {
            let kind: Parser.Target.Kind
            switch entry.kind {
            case .application, .systemSettings: kind = .application
            case .quicklink: kind = .quicklink
            case .appleShortcut: kind = .shortcut
            case .customCommand: kind = .customCommand
            case .windowLayout, .projectWorkspace: kind = .layout
            case .windowRoom: kind = .room
            default: continue
            }
            // Two package installations may legitimately share a display name.
            // Keep unique entries and ask the user rather than picking either one.
            guard seen.insert(kind.rawValue + ":" + entry.id).inserted else { continue }
            var aliases = entry.alternateTitles + core.aliases.allAliases(for: entry.preferenceKey)
            if kind == .application { aliases += familiarNames(for: entry.name) }
            targets.append(.init(kind: kind, id: entry.id, name: entry.name, aliases: aliases))
        }
        if core.settings.workflowsEnabled {
            for workflow in core.workflows.workflows where workflow.isEnabled {
                targets.append(.init(kind: .workflow, id: workflow.id.uuidString, name: workflow.name))
            }
        }
        return targets
    }

    private static func familiarNames(for name: String) -> [String] {
        switch Parser.normalize(name) {
        case "telegram": ["телеграм", "телега"]
        case "safari": ["сафари"]
        case "google chrome": ["хром", "гугл хром"]
        case "finder": ["файндер"]
        case "terminal": ["терминал"]
        case "iterm": ["итерм", "айтерм"]
        case "obsidian": ["обсидиан"]
        case "obsidium": ["обсидиум"]
        case "cursor": ["курсор", "корсер"]
        case "claude": ["клод", "клауд"]
        case "codex": ["кодекс", "кодэкс"]
        case "firefox": ["файрфокс", "фаерфокс"]
        case "jira": ["джира"]
        case "docker": ["докер"]
        case "orbstack": ["орбстак"]
        case "zed": ["зед", "зэд"]
        case "zap": ["зап"]
        case "zen": ["зен"]
        case "chatgpt": ["чат гпт", "чатджипити"]
        case "iina": ["иина", "ина"]
        case "transmission": ["трансмиссия"]
        case "localsend": ["локал сенд", "локалсенд"]
        case "maccy": ["макси"]
        case "stats": ["статс", "статистика"]
        case "tether": ["тезер"]
        case "handy": ["хэнди"]
        case "happ": ["хапп"]
        case "thaw": ["соу", "thaw"]
        case "pinokio": ["пинокио"]
        case "upscayl": ["апскейл"]
        case "sniffnet": ["снифнет"]
        case "spotube": ["спотюб"]
        case "kepresso": ["кепрессо"]
        case "vibe": ["вайб"]
        case "trueconf": ["труконф", "труконференс"]
        case "dopbase": ["допбейс"]
        case "freelens": ["фрилэнс", "фриленз"]
        case "neohatop": ["неохтоп"]
        default: []
        }
    }

    static func execute(_ intent: Parser.Intent, core: AppCore) {
        switch intent {
        case .window(let id):
            guard let command = WindowCommand.ID(rawValue: id), core.settings.windowManagementEnabled else {
                core.showMessage("Управление окнами недоступно", tone: .neutral)
                return
            }
            core.windowCommandCoordinator.runWindowCommand(id: command)
        case .system(let id):
            guard let command = SystemAction.ID(rawValue: id) else { return }
            core.systemActionCoordinator.runSystemAction(id: command)
        case .brightness(let percent):
            do {
                try SystemActionRunner.setBrightness(percent: percent)
                core.showMessage("Яркость: \(percent)%")
            } catch {
                core.showMessage(error.localizedDescription, tone: .danger)
            }
        case .volume(let percent):
            do {
                try SystemActionRunner.setVolume(Float32(percent) / 100)
                core.showMessage("Громкость: \(percent)%")
            } catch {
                core.showMessage(error.localizedDescription, tone: .danger)
            }
        case .builtIn(let id, let query):
            switch id {
            case "clipboard": core.launcherCoordinator.runCommand(.clipboardHistory)
            case "pasteNext": core.launcherCoordinator.runCommand(.pasteSequentially)
            case "notes": core.launcherCoordinator.runCommand(.showNotes)
            case "createNote": core.launcherCoordinator.runCommand(.createNote)
            case "snippets": core.launcherCoordinator.runCommand(.searchSnippets)
            case "quicklinks": core.launcherCoordinator.runCommand(.searchQuicklinks)
            case "menuSearch": core.launcherCoordinator.runCommand(.searchMenuItems)
            case "schedule": core.launcherCoordinator.runCommand(.mySchedule)
            case "meeting": core.launcherCoordinator.runCommand(.joinNextMeeting)
            case "copyMeetingLink": core.launcherCoordinator.runCommand(.copyMeetingLink)
            case "createEvent": core.launcherCoordinator.runCommand(.createEvent)
            case "settings": core.launcherCoordinator.runCommand(.settings)
            case "search": core.paletteCoordinator.showPalette(mode: .launcher, seeding: query)
            case "windows": core.launcherCoordinator.runCommand(.switchWindows)
            case "files": core.fileSearchCoordinator.show(query: query ?? "")
            case "searchNotes": core.notesCoordinator.searchNotes(query: query)
            case "voiceCatalog": core.voiceCommandCatalogWindow.show()
            case "translateClipboard":
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                guard !text.isEmpty else {
                    core.showMessage("Буфер обмена пуст", tone: .neutral)
                    return
                }
                core.quickAICoordinator.sendVoicePrompt("Переведи текст:\n\n" + text)
            default: break
            }
        case .aiPrompt:
            break // Handled in route(); execute() never sees it.
        case .quitApp(let id):
            guard let entry = core.appIndex.apps.first(where: { $0.id == id }),
                  let bundleID = entry.bundleID, entry.kind == .application else {
                core.showMessage("Не удалось закрыть приложение", tone: .neutral)
                return
            }
            if AppLauncher.quit(bundleID: bundleID, url: entry.url) {
                core.showMessage("Закрываю \(entry.name)", tone: .success)
            } else {
                core.showMessage("\(entry.name) не запущено", tone: .neutral)
            }
        case .quitLastApp:
            guard let id = SpeechVoiceCommandHistory.lastVoiceTargetID,
                  let entry = core.appIndex.apps.first(where: { $0.id == id }),
                  let bundleID = entry.bundleID, entry.kind == .application else {
                core.showMessage("Нет приложения, которое вы открывали", tone: .neutral)
                return
            }
            if AppLauncher.quit(bundleID: bundleID, url: entry.url) {
                core.showMessage("Закрываю \(entry.name)", tone: .success)
            } else {
                core.showMessage("\(entry.name) не запущено", tone: .neutral)
            }
        case .target(let kind, let id):
            if kind == .workflow {
                guard let workflowID = UUID(uuidString: id), core.workflowCoordinator.allows(workflowID)
                else { return }
                core.workflowCoordinator.run(workflowID)
                return
            }
            guard let entry = core.appIndex.apps.first(where: { $0.id == id }),
                  core.visibility.isVisible(entry) else { return }
            // A spoken custom command, link or shortcut can modify arbitrary local state.
            // Require explicit user consent in Tinycast before invoking its normal handler.
            if [.customCommand, .shortcut, .quicklink].contains(kind) {
                Task { @MainActor in
                    guard await core.confirm(
                        title: "Выполнить голосовую команду?",
                        message: entry.name,
                        symbol: "mic.fill", confirmTitle: "Выполнить") else { return }
                    core.launcherCoordinator.launch(entry)
                }
            } else {
                core.launcherCoordinator.launch(entry)
            }
        }
    }
}

/// The target of the last executed voice command, for anaphora ("закрой его").
/// Only named application commands qualify; system and window verbs have no referent.
@MainActor
enum SpeechVoiceCommandHistory {
    static var lastVoiceTargetID: String?

    /// The application an intent refers to, nil when it names no application.
    static func targetID(for intent: SpeechVoiceCommandParser.Intent) -> String? {
        switch intent {
        case .target(let kind, let id):
            return kind == .application ? id : nil
        case .quitApp(let id):
            return id
        default:
            return nil
        }
    }
}
