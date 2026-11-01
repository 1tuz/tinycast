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
    enum CommandAction: Equatable, Sendable {
        case builtIn(CommandID)
        case customCommand(id: UUID, arguments: [String])
    }

    let id: UUID
    var name: String
    var trigger: WorkflowTrigger
    var commandID: String
    var customCommandID: UUID?
    var customCommandArguments: [String]
    var isEnabled: Bool

    init(
        id: UUID = UUID(), name: String = "New Workflow",
        trigger: WorkflowTrigger = WorkflowTrigger(kind: .hotkey),
        commandID: String = "command:settings", customCommandID: UUID? = nil,
        customCommandArguments: [String] = [], isEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.commandID = commandID
        self.customCommandID = customCommandID
        self.customCommandArguments = customCommandArguments
        self.isEnabled = isEnabled
    }

    var commandAction: CommandAction? {
        if let customCommandID {
            return .customCommand(id: customCommandID, arguments: customCommandArguments)
        }
        guard let command else { return nil }
        return .builtIn(command)
    }

    func arguments(for count: Int) -> [String] {
        guard count > 0 else { return [] }
        return Array((customCommandArguments + Array(repeating: "", count: count)).prefix(count))
    }

    mutating func selectBuiltIn(_ command: CommandID) {
        commandID = command.rawValue
        customCommandID = nil
        customCommandArguments = []
    }

    mutating func selectCustomCommand(_ id: UUID) {
        customCommandID = id
        customCommandArguments = []
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

    private enum CodingKeys: String, CodingKey {
        case id, name, trigger, commandID, customCommandID, customCommandArguments, isEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        trigger = try container.decode(WorkflowTrigger.self, forKey: .trigger)
        commandID = try container.decode(String.self, forKey: .commandID)
        customCommandID = try container.decodeIfPresent(UUID.self, forKey: .customCommandID)
        customCommandArguments = try container.decodeIfPresent(
            [String].self, forKey: .customCommandArguments) ?? []
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
    }
}
