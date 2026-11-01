import Foundation

enum PortForwardKind: String, Equatable, Sendable {
    case kubernetes
    case vaultProxy
    case ssh
}

struct KubePortForwardSelection: Equatable, Sendable {
    let contextName: String
    let namespace: String
}

struct PortForwardRequest: Equatable, Sendable {
    let kind: PortForwardKind
    let executableName: String
    let arguments: [String]
    let displayTarget: String
    let displayPorts: String
    let kubeSelection: KubePortForwardSelection?

    private init(
        kind: PortForwardKind, executableName: String,
        arguments: [String], displayTarget: String, displayPorts: String,
        kubeSelection: KubePortForwardSelection? = nil
    ) {
        self.kind = kind
        self.executableName = executableName
        self.arguments = arguments
        self.displayTarget = displayTarget
        self.displayPorts = displayPorts
        self.kubeSelection = kubeSelection
    }

    static func kubernetes(
        context: String, namespace: String, resource: String,
        localPort: String, remotePort: String, policy: KubeCommandPolicy
    ) throws -> PortForwardRequest {
        let ports = try PortForwardPorts(local: localPort, remote: remotePort)
        let parts = resource.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
            ["pod", "service", "deployment"].contains(String(parts[0])),
            KubeResourceName.isValid(String(parts[1]))
        else { throw PortForwardRequestError.invalidResource }
        let contextArguments: [String]
        do {
            contextArguments = try policy.arguments(
                for: context, namespace: namespace, operation: .read)
        } catch let error as KubeContextPolicyError {
            throw PortForwardRequestError.policy(error)
        }
        let selection = KubePortForwardSelection(contextName: context, namespace: namespace)
        return PortForwardRequest(
            kind: .kubernetes, executableName: "kubectl",
            arguments: ["port-forward"] + contextArguments
                + [resource, "\(ports.local):\(ports.remote)"],
            displayTarget: "\(context) · \(namespace) · \(resource)",
            displayPorts: "127.0.0.1:\(ports.local) → \(ports.remote)",
            kubeSelection: selection)
    }

    static func kubernetes(
        context: String, namespace: String, resource: String,
        localPort: Int, remotePort: Int, policy: KubeCommandPolicy
    ) throws -> PortForwardRequest {
        try kubernetes(
            context: context, namespace: namespace, resource: resource,
            localPort: String(localPort), remotePort: String(remotePort), policy: policy)
    }

    static func vaultProxy(configuration: URL) throws -> PortForwardRequest {
        try vaultProxy(
            configFile: configuration, displayTarget: "Vault proxy", listenerPort: nil)
    }

    static func vaultProxy(
        configFile: URL, displayTarget: String, listenerPort: Int
    ) throws -> PortForwardRequest {
        try vaultProxy(
            configFile: configFile, displayTarget: displayTarget, listenerPort: Optional(listenerPort))
    }

    private static func vaultProxy(
        configFile: URL, displayTarget: String, listenerPort: Int?
    ) throws -> PortForwardRequest {
        let path = configFile.standardizedFileURL.path
        guard path.hasPrefix("/"), !path.contains("\0"),
            listenerPort.map({ (1...65_535).contains($0) }) ?? true
        else { throw PortForwardRequestError.invalidVaultConfiguration }
        let ports =
            listenerPort.map { "127.0.0.1:\($0)" }
            ?? String(localized: "Configured in Vault Proxy file")
        return PortForwardRequest(
            kind: .vaultProxy, executableName: "vault",
            arguments: ["proxy", "-config=\(path)"],
            displayTarget: displayTarget,
            displayPorts: ports)
    }

    static func ssh(
        alias: String, localPort: String, remoteHost: String, remotePort: String
    ) throws -> PortForwardRequest {
        let ports = try PortForwardPorts(local: localPort, remote: remotePort)
        guard Self.isValidSSHAlias(alias), Self.isValidRemoteHost(remoteHost) else {
            throw PortForwardRequestError.invalidSSHTarget
        }
        return PortForwardRequest(
            kind: .ssh, executableName: "ssh",
            arguments: ["-N", "-T", "-L", "\(ports.local):\(remoteHost):\(ports.remote)", alias],
            displayTarget: "\(alias) → \(remoteHost)",
            displayPorts: "127.0.0.1:\(ports.local) → \(ports.remote)")
    }

    private static func isValidSSHAlias(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 253,
            let first = value.utf8.first, (isAlphaNumeric(first) || first == 95)
        else { return false }
        return value.utf8.allSatisfy {
            isAlphaNumeric($0) || [45, 46, 64, 95].contains($0)
        }
    }

    private static func isValidRemoteHost(_ value: String) -> Bool {
        if value.hasPrefix("["), value.hasSuffix("]") {
            let address = value.dropFirst().dropLast()
            return isValidIPv6(String(address))
        }
        guard !value.isEmpty, value.utf8.count <= 253 else { return false }
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard let first = label.utf8.first, let last = label.utf8.last,
                isAlphaNumeric(first), isAlphaNumeric(last), label.utf8.count <= 63
            else { return false }
            return label.utf8.allSatisfy { isAlphaNumeric($0) || $0 == 45 }
        }
    }

    private static func isAlphaNumeric(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...90).contains(value) || (97...122).contains(value)
    }

    private static func isHex(_ value: UInt8) -> Bool {
        (48...57).contains(value) || (65...70).contains(value) || (97...102).contains(value)
    }

    private static func isValidIPv6(_ value: String) -> Bool {
        let parts = value.components(separatedBy: "::")
        guard parts.count <= 2 else { return false }
        let groups = parts.flatMap { part in
            part.isEmpty ? [] : part.split(separator: ":", omittingEmptySubsequences: false)
        }
        guard
            groups.allSatisfy({
                (1...4).contains($0.utf8.count) && $0.utf8.allSatisfy(isHex)
            })
        else { return false }
        return parts.count == 2 ? groups.count < 8 : groups.count == 8
    }
}

struct PortForwardPorts: Equatable, Sendable {
    let local: Int
    let remote: Int

    init(local: String, remote: String) throws {
        self.local = try Self.parse(local)
        self.remote = try Self.parse(remote)
    }

    static func parse(_ value: String) throws -> Int {
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
            let port = Int(value), (1...65_535).contains(port)
        else { throw PortForwardRequestError.invalidPort }
        return port
    }
}

extension PortForwardRequest {
    static func parsePort(_ input: String) throws -> Int {
        try PortForwardPorts.parse(input)
    }
}

enum PortForwardRequestError: LocalizedError, Equatable, Sendable {
    case invalidPort
    case invalidResource
    case invalidVaultConfiguration
    case invalidSSHTarget
    case policy(KubeContextPolicyError)

    var errorDescription: String? {
        switch self {
        case .invalidPort: String(localized: "Port must be a number from 1 to 65535.")
        case .invalidResource: String(localized: "Choose a valid pod, service or deployment name.")
        case .invalidVaultConfiguration:
            String(localized: "Choose an absolute Vault Proxy configuration path.")
        case .invalidSSHTarget: String(localized: "The SSH alias or remote host is invalid.")
        case .policy(let error): String(describing: error)
        }
    }
}
