import Foundation

enum ClipboardDevOpsAction: String, CaseIterable, Identifiable, Sendable {
    case decodeJWT
    case convertKubernetesYAML
    case decodeKubernetesSecret
    case calculateCIDR

    var id: String { rawValue }

    var developerUtility: DeveloperUtility {
        switch self {
        case .decodeJWT: .decodeJWT
        case .convertKubernetesYAML: .convertYAMLJSON
        case .decodeKubernetesSecret: .decodeKubernetesSecret
        case .calculateCIDR: .calculateCIDR
        }
    }

    var title: String { developerUtility.title }

    var badge: String {
        switch self {
        case .decodeJWT: String(localized: "JWT")
        case .convertKubernetesYAML: String(localized: "Kubernetes YAML")
        case .decodeKubernetesSecret: String(localized: "Kubernetes Secret")
        case .calculateCIDR: String(localized: "IPv4 / CIDR")
        }
    }

    var symbol: String { developerUtility.symbol }

    static func available(for text: String) -> [Self] {
        guard text.utf8.count <= 1_048_576 else { return [] }
        return allCases.filter { $0.matches(text) }
    }

    private func matches(_ text: String) -> Bool {
        switch self {
        case .decodeJWT: Self.looksLikeJWT(text)
        case .convertKubernetesYAML:
            Self.looksLikeKubernetesYAML(text) && !Self.looksLikeSecret(text)
        case .decodeKubernetesSecret: Self.looksLikeSecret(text)
        case .calculateCIDR: (try? IPv4CIDR.explain(text)) != nil
        }
    }

    private static func looksLikeJWT(_ text: String) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        let token: Substring
        if words.count == 2, words[0].lowercased() == "bearer" {
            token = words[1]
        } else if words.count == 1 {
            token = words[0]
        } else {
            return false
        }
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        return parts.allSatisfy { part in
            part.utf8.allSatisfy {
                (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0)
                    || $0 == 45 || $0 == 95
            }
        }
    }

    private static func looksLikeSecret(_ text: String) -> Bool {
        if let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
            value["kind"] as? String == "Secret"
        {
            return true
        }
        for line in text.split(whereSeparator: \.isNewline).prefix(32) {
            guard line.first?.isWhitespace != true,
                line.hasPrefix("kind:")
            else { continue }
            let value = String(line.dropFirst("kind:".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) == "Secret"
        }
        return false
    }

    private static func looksLikeKubernetesYAML(_ text: String) -> Bool {
        topLevelScalar("apiVersion", in: text) != nil && topLevelScalar("kind", in: text) != nil
    }

    private static func topLevelScalar(_ key: String, in text: String) -> String? {
        let prefix = key + ":"
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.first?.isWhitespace != true, line.hasPrefix(prefix) else { continue }
            let value = line.dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty || value.hasPrefix("#") ? nil : value
        }
        return nil
    }
}
