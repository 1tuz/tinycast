import Foundation

struct KubeContext: Identifiable, Equatable, Sendable {
    let name: String
    let clusterName: String
    let namespace: String
    var id: String { name }
}

struct KubeConfiguration: Equatable, Sendable {
    let contexts: [KubeContext]
    let currentContextName: String?
}

enum KubeContextPolicyError: Error, Equatable, Sendable {
    case guardDisabled
    case unavailableContext(String)
    case productionContext(String)
    case invalidNamespace
}

enum KubeOperation: Sendable { case read, mutation }

enum KubeMenuBarSummary {
    static func label(contextName: String, namespace: String) -> String {
        let namespaceLimit = min(namespace.count, 12)
        return shortened(contextName, limit: 27 - namespaceLimit) + " · "
            + shortened(namespace, limit: namespaceLimit)
    }

    static func shortened(_ value: String, limit: Int = 30) -> String {
        guard value.count > limit else { return value }
        let start = (limit - 1) / 2
        return String(value.prefix(start)) + "…" + String(value.suffix(limit - start - 1))
    }
}

struct KubeCommandPolicy: Equatable, Sendable {
    let isEnabled: Bool
    let contextNames: Set<String>
    let productionContextNames: Set<String>

    func requireContext(_ name: String) throws {
        guard isEnabled else { throw KubeContextPolicyError.guardDisabled }
        guard contextNames.contains(name) else {
            throw KubeContextPolicyError.unavailableContext(name)
        }
    }

    func requireNonProduction(_ name: String) throws {
        try requireContext(name)
        guard !productionContextNames.contains(name) else {
            throw KubeContextPolicyError.productionContext(name)
        }
    }

    func arguments(for contextName: String, namespace: String, operation: KubeOperation) throws -> [String] {
        switch operation {
        case .read: try requireContext(contextName)
        case .mutation: try requireNonProduction(contextName)
        }
        guard Self.isValidNamespace(namespace) else { throw KubeContextPolicyError.invalidNamespace }
        return ["--context", contextName, "--namespace", namespace]
    }

    static func isValidNamespace(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 63, let first = value.utf8.first,
            let last = value.utf8.last
        else { return false }
        func alphanumeric(_ byte: UInt8) -> Bool {
            (97...122).contains(byte) || (48...57).contains(byte)
        }
        return alphanumeric(first) && alphanumeric(last)
            && value.utf8.allSatisfy { alphanumeric($0) || $0 == 45 }
    }
}
