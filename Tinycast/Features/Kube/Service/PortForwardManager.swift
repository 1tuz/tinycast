import Foundation
import Observation

enum PortForwardManagerError: LocalizedError, Equatable, Sendable {
    case executableUnavailable(String)
    case staleKubeSelection
    case contextPolicy(KubeContextPolicyError)
    case duplicateSession

    var errorDescription: String? {
        switch self {
        case .executableUnavailable(let name):
            String(localized: "\(name) was not found in your Terminal environment.")
        case .staleKubeSelection:
            String(localized: "The Kubernetes selection changed. Start the port-forward again.")
        case .contextPolicy(let error): String(describing: error)
        case .duplicateSession: String(localized: "This port-forward is already running.")
        }
    }
}

@MainActor
@Observable
final class PortForwardManager {
    private(set) var sessions: [PortForwardSession] = []

    @ObservationIgnored private let locateExecutable: @Sendable (String) async -> URL?
    @ObservationIgnored private let stream: @Sendable (URL, [String], [String: String]) -> ShellCommandSession
    @ObservationIgnored private let retrySleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let currentPolicy: @MainActor () -> KubeCommandPolicy
    @ObservationIgnored private let currentSelection: @MainActor () -> KubePortForwardSelection?
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var activeProcesses: [UUID: ShellCommandSession] = [:]
    @ObservationIgnored private var manuallyStopped: Set<UUID> = []

    init(
        currentPolicy: @escaping @MainActor () -> KubeCommandPolicy,
        currentSelection: @escaping @MainActor () -> KubePortForwardSelection?,
        locateExecutable: @escaping @Sendable (String) async -> URL? = {
            await ExecutableLocator.locate($0)
        },
        stream: @escaping @Sendable (URL, [String], [String: String]) -> ShellCommandSession = {
            executable, arguments, environment in
            ShellCommandRunner.stream(
                executable: executable, arguments: arguments, environment: environment,
                workingDirectory: nil)
        },
        retrySleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.currentPolicy = currentPolicy
        self.currentSelection = currentSelection
        self.locateExecutable = locateExecutable
        self.stream = stream
        self.retrySleep = retrySleep
    }

    var hasActiveSessions: Bool { sessions.contains { $0.state.isActive } }

    @discardableResult
    func start(_ request: PortForwardRequest) async throws -> UUID {
        guard
            !sessions.contains(where: {
                $0.state.isActive && $0.request.kind == request.kind
                    && $0.request.arguments == request.arguments
            })
        else { throw PortForwardManagerError.duplicateSession }
        try validateSelection(for: request)
        guard let executable = await locateExecutable(request.executableName) else {
            throw PortForwardManagerError.executableUnavailable(request.executableName)
        }
        guard
            !sessions.contains(where: {
                $0.state.isActive && $0.request.kind == request.kind
                    && $0.request.arguments == request.arguments
            })
        else { throw PortForwardManagerError.duplicateSession }
        let sessionID = UUID()
        sessions.append(PortForwardSession(id: sessionID, request: request, state: .starting))
        tasks[sessionID] = Task { [weak self] in
            guard let self else { return }
            await self.run(id: sessionID, attempt: 0, executable: executable)
        }
        return sessionID
    }

    func stop(id: UUID) {
        guard sessions.first(where: { $0.id == id })?.state.isActive == true else { return }
        manuallyStopped.insert(id)
        activeProcesses[id]?.stop()
        tasks[id]?.cancel()
        activeProcesses[id] = nil
        tasks[id] = nil
        update(id, state: .stopped)
    }

    func stopAll() {
        for id in sessions.filter({ $0.state.isActive }).map(\.id) { stop(id: id) }
    }

    func remove(id: UUID) {
        if sessions.first(where: { $0.id == id })?.state.isActive == true { stop(id: id) }
        manuallyStopped.remove(id)
        sessions.removeAll { $0.id == id }
    }

    private func run(id: UUID, attempt: Int, executable: URL? = nil) async {
        guard let entry = sessions.first(where: { $0.id == id }), !Task.isCancelled,
            !manuallyStopped.contains(id)
        else { return }
        let request = entry.request
        do {
            try validateSelection(for: request)
        } catch {
            update(
                id, state: .failed(error.localizedDescription), attempt: attempt,
                lastError: error.localizedDescription)
            finish(id)
            return
        }
        let resolvedExecutable: URL
        if let executable {
            resolvedExecutable = executable
        } else if let located = await locateExecutable(request.executableName) {
            resolvedExecutable = located
        } else {
            let error = PortForwardManagerError.executableUnavailable(request.executableName)
                .localizedDescription
            update(id, state: .failed(error), attempt: attempt, lastError: error)
            finish(id)
            return
        }
        guard !Task.isCancelled, !manuallyStopped.contains(id) else {
            update(id, state: .stopped)
            finish(id)
            return
        }

        update(id, state: .starting, attempt: attempt)
        let process = stream(
            resolvedExecutable, request.arguments,
            ExecutableLocator.environment(running: resolvedExecutable))
        activeProcesses[id] = process
        let runningTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.activeProcesses[id] != nil,
                self.sessions.first(where: { $0.id == id })?.state == .starting
            else { return }
            self.update(id, state: .running)
        }
        var failure = "The process exited unexpectedly."
        for await event in process.events {
            guard !Task.isCancelled, !manuallyStopped.contains(id) else { break }
            switch event {
            case .output:
                if sessions.first(where: { $0.id == id })?.state == .starting {
                    update(id, state: .running)
                }
            case .finished(let result):
                failure = Self.failure(for: result)
            }
        }
        runningTimer.cancel()
        activeProcesses[id] = nil

        guard !Task.isCancelled, !manuallyStopped.contains(id) else {
            update(id, state: .stopped)
            finish(id)
            return
        }
        let nextRetry = attempt + 1
        let delay = PortForwardBackoff.delaySeconds(for: nextRetry)
        update(
            id,
            state: .reconnecting(
                attempt: nextRetry, delaySeconds: delay, lastError: failure),
            attempt: nextRetry, lastError: failure)
        do {
            try await retrySleep(.seconds(delay))
        } catch {
            update(id, state: manuallyStopped.contains(id) ? .stopped : .failed(error.localizedDescription))
            finish(id)
            return
        }
        guard !Task.isCancelled, !manuallyStopped.contains(id) else {
            update(id, state: .stopped)
            finish(id)
            return
        }
        await run(id: id, attempt: nextRetry)
    }

    private func validateSelection(for request: PortForwardRequest) throws {
        guard let snapshot = request.kubeSelection else { return }
        guard currentSelection() == snapshot else {
            throw PortForwardManagerError.staleKubeSelection
        }
        do {
            _ = try currentPolicy().arguments(
                for: snapshot.contextName, namespace: snapshot.namespace, operation: .read)
        } catch let error as KubeContextPolicyError {
            throw PortForwardManagerError.contextPolicy(error)
        }
    }

    private func update(
        _ id: UUID, state: PortForwardState, attempt: Int? = nil, lastError: String? = nil
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = state
        if let attempt { sessions[index].attempt = attempt }
        if let lastError { sessions[index].lastError = lastError }
    }

    private func finish(_ id: UUID) {
        activeProcesses[id] = nil
        tasks[id] = nil
    }

    private static func failure(for result: ShellCommandResult) -> String {
        switch result.termination {
        case .exited(let status): String(localized: "Exited with status \(status).")
        case .launchFailed: String(localized: "The process could not be started.")
        case .stopped: String(localized: "The process stopped unexpectedly.")
        }
    }
}
