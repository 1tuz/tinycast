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
        print("Workflow tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
