import Foundation

enum WorkflowTriggerKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case dailyTime
    case hotkey
    case clipboardChange
    case fileChange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dailyTime: "Daily time"
        case .hotkey: "Hotkey"
        case .clipboardChange: "Clipboard changes"
        case .fileChange: "Folder changes"
        }
    }
}

struct WorkflowTrigger: Codable, Hashable, Sendable {
    var kind: WorkflowTriggerKind
    var hour = 9
    var minute = 0
    var path = ""
}

struct Workflow: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var trigger: WorkflowTrigger
    var commandID: String
    var isEnabled: Bool

    init(
        id: UUID = UUID(), name: String = "New Workflow",
        trigger: WorkflowTrigger = WorkflowTrigger(kind: .hotkey),
        commandID: String = "command:settings", isEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.commandID = commandID
        self.isEnabled = isEnabled
    }

    var command: CommandID? {
        guard let command = CommandID(rawValue: commandID),
            Self.availableCommands.contains(where: { $0 == command })
        else { return nil }
        return command
    }

    static let availableCommands = CommandID.allCases.filter { command in
        switch command {
        case .calculatorHistory, .clipboardHistory, .searchEmoji, .searchFiles,
            .searchMenuItems, .switchWindows, .showNotes, .createNote, .searchNotes,
            .createWindowLayout, .captureWindowLayout, .createQuicklink, .searchQuicklinks,
            .searchSnippets, .createSnippet, .settings, .about:
            true
        default: false
        }
    }
}
