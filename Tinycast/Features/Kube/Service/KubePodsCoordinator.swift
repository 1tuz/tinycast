import Foundation
import Observation

struct KubeTerminalCommand: Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let contextName: String
}

enum KubePodsError: LocalizedError, Sendable, Equatable {
    case noSelectedContext
    case kubectlUnavailable
    case staleSelection
    case commandFailed(String)
    case policy(KubeContextPolicyError)

    var errorDescription: String? {
        switch self {
        case .noSelectedContext: String(localized: "Choose a Kubernetes context first.")
        case .kubectlUnavailable: String(localized: "kubectl was not found in your Terminal environment.")
        case .staleSelection: String(localized: "The selected context changed. Reload the pod list.")
        case .commandFailed(let message): message
        case .policy(let error): String(describing: error)
        }
    }
}

@MainActor
@Observable
final class KubePodsCoordinator {
    private(set) var pods: [KubePod] = []
    private(set) var filter: KubePodFilter = .all
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let contextStore: KubeContextStore
    @ObservationIgnored private let locateExecutable: @Sendable (String) async -> URL?
    @ObservationIgnored private let runProcess:
        @Sendable (
            URL, [String], [String: String], Duration, Int, Int
        ) async throws -> ProcessCommandResult
    @ObservationIgnored private let streamProcess:
        @Sendable (
            URL, [String], [String: String]
        ) -> ShellCommandSession
    @ObservationIgnored private var loadIdentity = UUID()

    init(
        contextStore: KubeContextStore,
        locateExecutable: @escaping @Sendable (String) async -> URL? = {
            await ExecutableLocator.locate($0)
        },
        runProcess:
            @escaping @Sendable (
                URL, [String], [String: String], Duration, Int, Int
            ) async throws -> ProcessCommandResult = {
                executable, arguments, environment, timeout, stdout, stderr in
                try await ProcessCommandRunner.run(
                    executable: executable, arguments: arguments, environment: environment,
                    timeout: timeout, maxStdoutBytes: stdout, maxStderrBytes: stderr)
            },
        streamProcess:
            @escaping @Sendable (
                URL, [String], [String: String]
            ) -> ShellCommandSession = { executable, arguments, environment in
                ShellCommandRunner.stream(
                    executable: executable, arguments: arguments,
                    environment: environment)
            }
    ) {
        self.contextStore = contextStore
        self.locateExecutable = locateExecutable
        self.runProcess = runProcess
        self.streamProcess = streamProcess
    }

    var visiblePods: [KubePod] {
        switch filter {
        case .all: pods
        case .problems: pods.filter(\.isProblem)
        }
    }

    func setFilter(_ filter: KubePodFilter) { self.filter = filter }

    func copyName(of pod: KubePod) { Paster.copyPlainText(pod.name) }

    func refresh() async {
        let snapshot: Selection
        do {
            snapshot = try selection(operation: .read)
        } catch {
            errorMessage = Self.message(for: error)
            pods = []
            return
        }

        let identity = UUID()
        loadIdentity = identity
        isLoading = true
        errorMessage = nil
        defer {
            if loadIdentity == identity { isLoading = false }
        }

        do {
            guard let executable = await locateExecutable("kubectl") else {
                throw KubePodsError.kubectlUnavailable
            }
            try requireCurrent(snapshot, operation: .read)
            let arguments = try KubePodCommand.list(
                context: snapshot.context, namespace: snapshot.namespace,
                policy: contextStore.policy)
            let result = try await runProcess(
                executable, arguments, ExecutableLocator.environment(running: executable),
                .seconds(30), 8 * 1024 * 1024, 64 * 1024)
            guard loadIdentity == identity, !Task.isCancelled else { return }
            try requireCurrent(snapshot, operation: .read)
            guard result.exitCode == 0 else { throw commandFailure(result.stderr) }
            pods = try KubePodDecoder.decode(result.stdout)
        } catch {
            guard loadIdentity == identity, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    func logs(for pod: KubePod, container: String? = nil) async throws -> ShellCommandSession {
        let snapshot = try selection(operation: .read)
        let arguments = try KubePodCommand.logs(
            context: snapshot.context, namespace: snapshot.namespace, pod: pod.name,
            container: container, policy: contextStore.policy)
        guard let executable = await locateExecutable("kubectl") else {
            throw KubePodsError.kubectlUnavailable
        }
        try requireCurrent(snapshot, operation: .read)
        return streamProcess(
            executable, arguments, ExecutableLocator.environment(running: executable))
    }

    func describe(_ pod: KubePod) async throws -> String {
        let snapshot = try selection(operation: .read)
        let arguments = try KubePodCommand.describe(
            context: snapshot.context, namespace: snapshot.namespace, pod: pod.name,
            policy: contextStore.policy)
        let result = try await run(arguments, snapshot: snapshot, operation: .read)
        guard result.exitCode == 0 else { throw commandFailure(result.stderr) }
        return String(decoding: result.stdout, as: UTF8.self)
    }

    func restartDeployment(named name: String, confirmedByUser: Bool) async throws {
        let snapshot = try selection(operation: .mutation)
        let arguments = try KubePodCommand.restart(
            context: snapshot.context, namespace: snapshot.namespace,
            deployment: name, confirmedByUser: confirmedByUser,
            policy: contextStore.policy)
        let result = try await run(arguments, snapshot: snapshot, operation: .mutation)
        guard result.exitCode == 0 else { throw commandFailure(result.stderr) }
        await refresh()
    }

    func terminalExec(for pod: KubePod, container: String? = nil) async throws -> KubeTerminalCommand {
        let snapshot = try selection(operation: .read)
        let arguments = try KubePodCommand.exec(
            context: snapshot.context, namespace: snapshot.namespace, pod: pod.name,
            container: container, policy: contextStore.policy)
        guard let executable = await locateExecutable("kubectl") else {
            throw KubePodsError.kubectlUnavailable
        }
        try requireCurrent(snapshot, operation: .read)
        return KubeTerminalCommand(
            executable: executable, arguments: arguments,
            environment: ExecutableLocator.environment(running: executable),
            contextName: snapshot.context)
    }

    private func run(
        _ arguments: [String], snapshot: Selection, operation: KubeOperation
    ) async throws -> ProcessCommandResult {
        guard let executable = await locateExecutable("kubectl") else {
            throw KubePodsError.kubectlUnavailable
        }
        try requireCurrent(snapshot, operation: operation)
        return try await runProcess(
            executable, arguments, ExecutableLocator.environment(running: executable),
            .seconds(30), 1024 * 1024, 64 * 1024)
    }

    private func selection(operation: KubeOperation) throws -> Selection {
        guard let context = contextStore.selectedContextName else {
            throw KubePodsError.noSelectedContext
        }
        let namespace = contextStore.selectedNamespace
        do {
            _ = try contextStore.commandArguments(operation: operation)
        } catch let error as KubeContextPolicyError {
            throw KubePodsError.policy(error)
        }
        return Selection(context: context, namespace: namespace)
    }

    private func requireCurrent(_ snapshot: Selection, operation: KubeOperation) throws {
        guard contextStore.isEnabled,
            contextStore.selectedContextName == snapshot.context,
            contextStore.selectedNamespace == snapshot.namespace
        else { throw KubePodsError.staleSelection }
        do {
            _ = try contextStore.commandArguments(
                for: snapshot.context, namespace: snapshot.namespace, operation: operation)
        } catch let error as KubeContextPolicyError {
            throw KubePodsError.policy(error)
        }
    }

    private func commandFailure(_ data: Data) -> KubePodsError {
        let tail = String(decoding: data.suffix(4096), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(tail.isEmpty ? "kubectl exited with an error." : tail)
    }

    private static func message(for error: Error) -> String {
        switch error {
        case KubePodsError.noSelectedContext:
            String(localized: "Choose a Kubernetes context first.")
        case KubePodsError.kubectlUnavailable:
            String(localized: "kubectl was not found in your Terminal environment.")
        case KubePodsError.staleSelection:
            String(localized: "The selected context changed. Reload the pod list.")
        case KubePodsError.commandFailed(let details): details
        case KubePodsError.policy(let error): String(describing: error)
        case is CancellationError, ProcessCommandError.cancelled:
            String(localized: "The Kubernetes command was cancelled.")
        default: error.localizedDescription
        }
    }

    private struct Selection: Equatable {
        let context: String
        let namespace: String
    }
}
