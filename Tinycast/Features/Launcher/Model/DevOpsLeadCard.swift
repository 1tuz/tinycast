import Foundation

enum DevOpsLeadCard: Equatable, Sendable {
    case cidr(String)
    case jwt(String)
    case jira(key: String, url: URL)

    var id: String {
        switch self {
        case .cidr: "cidr"
        case .jwt: "jwt"
        case .jira(let key, _): "jira-\(key)"
        }
    }

    var title: String {
        switch self {
        case .cidr: String(localized: "IPv4 / CIDR")
        case .jwt: String(localized: "Decode JWT")
        case .jira: String(localized: "Jira Issue")
        }
    }

    var symbol: String {
        switch self {
        case .cidr: "network"
        case .jwt: "key.horizontal"
        case .jira: "ticket"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .cidr, .jwt: String(localized: "Copy Result")
        case .jira: String(localized: "Open Jira Issue")
        }
    }

    var result: String? {
        switch self {
        case .cidr(let result), .jwt(let result): result
        case .jira: nil
        }
    }

    var issueKey: String? {
        guard case .jira(let key, _) = self else { return nil }
        return key
    }

    var url: URL? {
        guard case .jira(_, let url) = self else { return nil }
        return url
    }

    static func resolve(query: String, jiraBaseURL: String?) -> Self? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let result = try? IPv4CIDR.explain(value) { return .cidr(result) }
        if let result = try? JWTDecoder.decode(value) { return .jwt(result) }
        guard let jiraBaseURL, isIssueKey(value), let url = jiraURL(base: jiraBaseURL, key: value) else {
            return nil
        }
        return .jira(key: value, url: url)
    }

    private static func isIssueKey(_ value: String) -> Bool {
        value.range(of: #"^[A-Z][A-Z0-9]+-[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func jiraURL(base: String, key: String) -> URL? {
        let value = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil
        else { return nil }
        let basePath = components.percentEncodedPath.trimmingCharacters(
            in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath =
            "/" + (basePath.isEmpty ? "" : basePath + "/")
            + "browse/\(key)"
        return components.url
    }
}
