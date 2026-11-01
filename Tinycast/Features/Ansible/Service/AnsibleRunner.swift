import Foundation

enum AnsibleRunnerError: LocalizedError, Equatable {
    case executableUnavailable(String)
    case inventoryCommandFailed(Int32, String)
    case invalidInventory
    case realRunRequiresConfirmation

    var errorDescription: String? {
        switch self {
        case .executableUnavailable(let name):
            return String(localized: "\(name) was not found in your command line tools.")
        case .inventoryCommandFailed(let status, let message):
            return message.isEmpty
                ? String(localized: "ansible-inventory exited with status \(status).") : message
        case .invalidInventory:
            return String(localized: "ansible-inventory returned invalid JSON.")
        case .realRunRequiresConfirmation:
            return String(localized: "Confirm the real playbook run before starting it.")
        }
    }
}

struct AnsibleStartedRun: Sendable {
    let session: ShellCommandSession
    let startedAt: Date
}

struct AnsibleRunner: Sendable {
    private let locate: @Sendable (String) async -> URL?

    init(locate: @escaping @Sendable (String) async -> URL? = { name in
        await ExecutableLocator.locate(name)
    }) {
        self.locate = locate
    }

    func inventory(at inventoryURL: URL) async throws -> AnsibleInventory {
        guard let executable = await locate("ansible-inventory") else {
            throw AnsibleRunnerError.executableUnavailable("ansible-inventory")
        }
        let result = try await ProcessCommandRunner.run(
            executable: executable,
            arguments: ["-i", inventoryURL.path, "--list"],
            environment: ExecutableLocator.environment(running: executable),
            timeout: .seconds(30), maxStdoutBytes: 10 * 1024 * 1024,
            maxStderrBytes: 16 * 1024)
        guard result.exitCode == 0 else {
            let message = String(decoding: result.stderr, as: UTF8.self)
                .split(whereSeparator: \.isNewline).suffix(8).joined(separator: "\n")
            throw AnsibleRunnerError.inventoryCommandFailed(result.exitCode, message)
        }
        do { return try AnsibleInventory.parse(result.stdout) }
        catch { throw AnsibleRunnerError.invalidInventory }
    }

    func start(
        _ run: AnsiblePlaybookRun, dryRun: Bool, confirmedByUser: Bool
    ) async throws -> AnsibleStartedRun {
        guard dryRun || confirmedByUser else {
            throw AnsibleRunnerError.realRunRequiresConfirmation
        }
        guard let executable = await locate("ansible-playbook") else {
            throw AnsibleRunnerError.executableUnavailable("ansible-playbook")
        }
        let session = ShellCommandRunner.stream(
            executable: executable, arguments: run.arguments(dryRun: dryRun),
            environment: ExecutableLocator.environment(running: executable),
            workingDirectory: run.playbook.deletingLastPathComponent())
        return AnsibleStartedRun(session: session, startedAt: Date())
    }

    func startPing(host: String, inventory: URL) async throws -> AnsibleStartedRun {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !target.contains("\0") else {
            throw AnsibleRunnerError.invalidInventory
        }
        guard let executable = await locate("ansible") else {
            throw AnsibleRunnerError.executableUnavailable("ansible")
        }
        let session = ShellCommandRunner.stream(
            executable: executable,
            arguments: [target, "-i", inventory.path, "-m", "ping"],
            environment: ExecutableLocator.environment(running: executable))
        return AnsibleStartedRun(session: session, startedAt: Date())
    }
}
