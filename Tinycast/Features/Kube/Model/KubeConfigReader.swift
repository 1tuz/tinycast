import Foundation

enum KubeConfigReaderError: Error, Equatable, Sendable {
    case homeUnavailable
    case unreadableFile(String)
    case invalidDocument(String)
    case invalidRoot(String)
    case invalidField(path: String, field: String)
}

enum KubeConfigReader {
    static let maximumBytes = 1_048_576

    static func paths(environment: [String: String], homeDirectory: String?) throws -> [String] {
        if let value = environment["KUBECONFIG"], !value.isEmpty {
            var seen: Set<String> = []
            return value.split(separator: ":").map(String.init).filter { seen.insert($0).inserted }
        }
        let homeDirectory = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? homeDirectory
        guard let homeDirectory, !homeDirectory.isEmpty else {
            throw KubeConfigReaderError.homeUnavailable
        }
        return [URL(fileURLWithPath: homeDirectory).appendingPathComponent(".kube/config").path]
    }

    static func load(environment: [String: String], homeDirectory: String?,
                     readFile: (String) throws -> Data?) throws -> KubeConfiguration {
        var contexts: [KubeContext] = []
        var names: Set<String> = []
        var current: String?
        for path in try paths(environment: environment, homeDirectory: homeDirectory) {
            let data: Data?
            do { data = try readFile(path) }
            catch { throw KubeConfigReaderError.unreadableFile(path) }
            guard let data else { continue }
            let document = try parse(data, path: path)
            for context in document.contexts where names.insert(context.name).inserted {
                contexts.append(context)
            }
            if current == nil { current = document.currentContextName }
        }
        return KubeConfiguration(contexts: contexts, currentContextName: current)
    }

    static func parse(_ data: Data, path: String) throws -> KubeConfiguration {
        guard data.count <= maximumBytes, let source = String(data: data, encoding: .utf8) else {
            throw KubeConfigReaderError.invalidDocument(path)
        }
        let value: Any
        do {
            if let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
                value = json
            } else {
                value = try BlockYAMLParser.parse(source)
            }
        } catch { throw KubeConfigReaderError.invalidDocument(path) }
        guard let root = value as? [String: Any] else {
            throw KubeConfigReaderError.invalidRoot(path)
        }
        let current = try string(root["current-context"], path: path, field: "current-context")
        guard let entries = root["contexts"], !(entries is NSNull) else {
            return KubeConfiguration(contexts: [], currentContextName: current)
        }
        guard let entries = entries as? [Any] else { throw invalid(path, "contexts") }
        var names: Set<String> = []
        let contexts = try entries.enumerated().compactMap { index, value -> KubeContext? in
            let field = "contexts[\(index)]"
            guard let entry = value as? [String: Any],
                let name = try string(entry["name"], path: path, field: field + ".name"),
                let body = entry["context"] as? [String: Any],
                let cluster = try string(body["cluster"], path: path, field: field + ".context.cluster")
            else { throw invalid(path, field) }
            let namespace = try string(body["namespace"], path: path, field: field + ".context.namespace") ?? "default"
            guard KubeCommandPolicy.isValidNamespace(namespace) else {
                throw invalid(path, field + ".context.namespace")
            }
            guard names.insert(name).inserted else { return nil }
            return KubeContext(name: name, clusterName: cluster, namespace: namespace)
        }
        return KubeConfiguration(contexts: contexts, currentContextName: current)
    }

    private static func string(_ value: Any?, path: String, field: String) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String,
            !string.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { throw invalid(path, field) }
        return string.isEmpty ? nil : string
    }

    private static func invalid(_ path: String, _ field: String) -> KubeConfigReaderError {
        .invalidField(path: path, field: field)
    }
}
