import Foundation

@main
@MainActor
struct WorkflowTests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        let allowed: Set<CommandID> = [
            .calculatorHistory, .clipboardHistory, .searchEmoji, .searchFiles,
            .searchMenuItems, .switchWindows, .showNotes, .createNote, .searchNotes,
            .createWindowLayout, .captureWindowLayout, .createQuicklink, .searchQuicklinks,
            .searchSnippets, .createSnippet, .settings, .about,
        ]
        check(!Workflow().isEnabled, "new workflows start disabled")
        check(Set(Workflow.availableCommands) == allowed, "only the local command allowlist is offered")
        for command in allowed {
            check(Workflow(commandID: command.rawValue).command == command, "allows \(command.rawValue)")
        }
        check(
            Workflow(commandID: CommandID.runShellCommand.rawValue).command == nil,
            "workflows cannot run shell commands")
        check(Workflow(commandID: "unknown-command").command == nil, "unknown commands are rejected")

        let legacy = """
            {"id":"\(UUID().uuidString)","name":"Legacy","trigger":{"kind":"hotkey","hour":9,"minute":0,"path":""},"commandID":"\(CommandID.about.rawValue)","isEnabled":false}
            """
        let migrated = try? JSONDecoder().decode(Workflow.self, from: Data(legacy.utf8))
        check(migrated?.customCommandID == nil, "legacy workflow defaults to built-in action")
        check(migrated?.customCommandArguments.isEmpty == true, "legacy workflow gets empty arguments")
        check(migrated?.commandAction == .builtIn(.about), "legacy workflow still resolves built-in action")

        let customID = UUID()
        var custom = Workflow(
            commandID: CommandID.about.rawValue,
            customCommandID: customID,
            customCommandArguments: ["prod", "--check", "extra"])
        check(
            custom.commandAction == .customCommand(id: customID, arguments: ["prod", "--check", "extra"]),
            "custom action takes precedence over stale built-in field")
        check(
            custom.arguments(for: 2) == ["prod", "--check"],
            "workflow arguments are bounded to declared command count")
        check(
            custom.arguments(for: 4) == ["prod", "--check", "extra", ""],
            "workflow arguments are padded to declared command count")
        custom.selectBuiltIn(.about)
        check(custom.customCommandID == nil && custom.customCommandArguments.isEmpty, "built-in selection clears custom action")
        check(custom.commandAction == .builtIn(.about), "built-in action remains selectable")

        print("Workflow tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
