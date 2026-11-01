import Foundation

struct KubePodContainer: Identifiable, Equatable, Sendable {
    let name: String
    let state: String
    let ready: Bool
    let restartCount: Int

    var id: String { name }
}

struct KubePod: Identifiable, Equatable, Sendable {
    let name: String
    let phase: String
    let containers: [KubePodContainer]
    let containerCount: Int
    let readyContainerCount: Int
    let restartCount: Int
    let problemReason: String?

    var id: String { name }
    var displayStatus: String { problemReason ?? phase }
    var isProblem: Bool { problemReason != nil || phase == "Pending" }
}

enum KubePodFilter: Sendable, Equatable {
    case all
    case problems
}

enum KubePodDecodeError: Error, Sendable, Equatable {
    case invalidJSON
    case invalidPodList
}

enum KubePodDecoder {
    static func decode(_ data: Data) throws -> [KubePod] {
        guard data.count <= 8 * 1024 * 1024 else { throw KubePodDecodeError.invalidPodList }
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw KubePodDecodeError.invalidJSON
        }
        guard document.kind == "List" || document.kind == "PodList" else {
            throw KubePodDecodeError.invalidPodList
        }
        return document.items.compactMap(Self.pod)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func pod(_ item: Item) -> KubePod? {
        guard let name = item.metadata.name, KubeResourceName.isValid(name) else { return nil }
        let statuses = item.status?.containerStatuses ?? []
        let statusByName = Dictionary(statuses.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let declaredNames = item.spec?.containers?.compactMap(\.name) ?? []
        let containerNames = declaredNames + statuses.map(\.name).filter { !declaredNames.contains($0) }
        let containers = containerNames.compactMap { name -> KubePodContainer? in
            guard KubeResourceName.isValidContainer(name) else { return nil }
            let status = statusByName[name]
            return KubePodContainer(
                name: name, state: containerState(status?.state), ready: status?.ready ?? false,
                restartCount: max(0, status?.restartCount ?? 0))
        }
        let phase = item.status?.phase ?? "Unknown"
        let reason = statuses.compactMap { status -> String? in
            status.state?.waiting?.reason ?? status.state?.terminated?.reason
        }.first(where: KubePodDecoder.isProblemReason)
        let ready = statuses.filter(\.ready).count
        let count = max(item.spec?.containers?.count ?? 0, statuses.count)
        let statusProblem = item.status?.reason.flatMap { isProblemReason($0) ? $0 : nil }
        let phaseProblem = isProblemPhase(phase) ? phase : nil
        return KubePod(
            name: name, phase: phase, containers: containers, containerCount: count,
            readyContainerCount: ready,
            restartCount: statuses.reduce(0) { $0 + max(0, $1.restartCount) },
            problemReason: reason ?? statusProblem ?? phaseProblem)
    }

    private static func containerState(_ state: State?) -> String {
        if let reason = state?.waiting?.reason { return reason }
        if let reason = state?.terminated?.reason { return reason }
        if state?.running != nil { return "Running" }
        if state?.waiting != nil { return "Waiting" }
        if state?.terminated != nil { return "Terminated" }
        return "Unknown"
    }

    private static func isProblemReason(_ value: String) -> Bool {
        [
            "CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull", "CreateContainerConfigError",
            "CreateContainerError", "InvalidImageName", "RunContainerError", "OOMKilled", "Error",
            "Failed", "Unknown"
        ].contains(value)
    }

    private static func isProblemPhase(_ value: String) -> Bool {
        ["Failed", "Unknown"].contains(value)
    }

    private struct Document: Decodable {
        let kind: String?
        let items: [Item]
    }

    private struct Item: Decodable {
        let metadata: Metadata
        let spec: Spec?
        let status: Status?
    }

    private struct Metadata: Decodable { let name: String? }
    private struct Spec: Decodable { let containers: [Container]? }
    private struct Container: Decodable { let name: String? }

    private struct Status: Decodable {
        let phase: String?
        let reason: String?
        let containerStatuses: [ContainerStatus]?
    }

    private struct ContainerStatus: Decodable {
        let name: String
        let ready: Bool
        let restartCount: Int
        let state: State?
    }

    private struct State: Decodable {
        let running: Running?
        let waiting: StateReason?
        let terminated: StateReason?
    }

    private struct Running: Decodable {}

    private struct StateReason: Decodable { let reason: String? }
}

enum KubeResourceName {
    static func isValid(_ value: String) -> Bool {
        guard value.utf8.count <= 253, let first = value.utf8.first, let last = value.utf8.last,
            alphanumeric(first), alphanumeric(last)
        else { return false }
        return value.utf8.allSatisfy { alphanumeric($0) || $0 == 45 || $0 == 46 }
    }

    static func isValidContainer(_ value: String) -> Bool {
        guard value.utf8.count <= 63, let first = value.utf8.first, let last = value.utf8.last,
            alphanumeric(first), alphanumeric(last)
        else { return false }
        return value.utf8.allSatisfy { alphanumeric($0) || $0 == 45 }
    }

    private static func alphanumeric(_ byte: UInt8) -> Bool {
        (97...122).contains(byte) || (48...57).contains(byte)
    }
}

enum KubePodCommandError: Error, Sendable, Equatable {
    case invalidPod
    case invalidContainer
    case invalidDeployment
    case confirmationRequired
}

enum KubePodCommand {
    static func list(context: String, namespace: String, policy: KubeCommandPolicy) throws -> [String] {
        try readArguments(context: context, namespace: namespace, policy: policy)
            + ["get", "pods", "--output=json"]
    }

    static func logs(
        context: String, namespace: String, pod: String, container: String?,
        policy: KubeCommandPolicy
    ) throws -> [String] {
        guard KubeResourceName.isValid(pod) else { throw KubePodCommandError.invalidPod }
        var args = try readArguments(context: context, namespace: namespace, policy: policy)
        args += ["logs", "--follow", "--tail=500"]
        if let container {
            guard KubeResourceName.isValidContainer(container) else {
                throw KubePodCommandError.invalidContainer
            }
            args += ["--container", container]
        }
        args.append(pod)
        return args
    }

    static func describe(
        context: String, namespace: String, pod: String, policy: KubeCommandPolicy
    ) throws -> [String] {
        guard KubeResourceName.isValid(pod) else { throw KubePodCommandError.invalidPod }
        return try readArguments(context: context, namespace: namespace, policy: policy)
            + ["describe", "pod", pod]
    }

    static func exec(
        context: String, namespace: String, pod: String, container: String?,
        policy: KubeCommandPolicy
    ) throws -> [String] {
        guard KubeResourceName.isValid(pod) else { throw KubePodCommandError.invalidPod }
        var args = try readArguments(context: context, namespace: namespace, policy: policy)
        args += ["exec", "--stdin", "--tty"]
        if let container {
            guard KubeResourceName.isValidContainer(container) else {
                throw KubePodCommandError.invalidContainer
            }
            args += ["--container", container]
        }
        args += [pod, "--", "/bin/sh"]
        return args
    }

    static func restart(
        context: String, namespace: String, deployment: String,
        confirmedByUser: Bool, policy: KubeCommandPolicy
    ) throws -> [String] {
        guard KubeResourceName.isValid(deployment) else {
            throw KubePodCommandError.invalidDeployment
        }
        guard confirmedByUser else { throw KubePodCommandError.confirmationRequired }
        return try policy.arguments(for: context, namespace: namespace, operation: .mutation)
            + ["rollout", "restart", "deployment/\(deployment)"]
    }

    private static func readArguments(
        context: String, namespace: String, policy: KubeCommandPolicy
    ) throws -> [String] {
        try policy.arguments(for: context, namespace: namespace, operation: .read)
    }
}
