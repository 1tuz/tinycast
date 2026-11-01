import Foundation

/// Local text transformations that need no AI provider.
enum DeveloperUtility: String, CaseIterable, Sendable {
    case base64Encode
    case base64Decode
    case decodeJWT
    case calculateCIDR
    case decodeKubernetesSecret
    case explainCron
    case convertYAMLJSON
    case formatJSON
    case minifyJSON
    case hashMD5
    case hashSHA256
    case hexEncode
    case hexDecode
    case urlEncode
    case urlDecode
    case generateUUID
    case timestampToDate
    case convertColor
    case generateLoremIpsum
    case convertCase

    var title: String {
        switch self {
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .decodeJWT: return String(localized: "Decode JWT")
        case .calculateCIDR: return String(localized: "Calculate CIDR")
        case .decodeKubernetesSecret: return String(localized: "Decode Kubernetes Secret")
        case .explainCron: return String(localized: "Explain cron")
        case .convertYAMLJSON: return String(localized: "YAML ↔ JSON")
        case .formatJSON: return "Format JSON"
        case .minifyJSON: return "Minify JSON"
        case .hashMD5: return "Hash (MD5)"
        case .hashSHA256: return "Hash (SHA-256)"
        case .hexEncode: return "Hex Encode"
        case .hexDecode: return "Hex Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .generateUUID: return "Generate UUID"
        case .timestampToDate: return "Timestamp to Date"
        case .convertColor: return "Convert Color"
        case .generateLoremIpsum: return "Generate Lorem Ipsum"
        case .convertCase: return "Convert Case"
        }
    }

    var symbol: String {
        switch self {
        case .decodeKubernetesSecret: return "lock.open"
        case .calculateCIDR: return "network"
        case .decodeJWT: return "key.horizontal"
        case .base64Encode, .base64Decode, .hexEncode, .hexDecode: return "square.and.pencil"
        case .formatJSON, .minifyJSON, .convertYAMLJSON: return "curlybraces"
        case .hashMD5, .hashSHA256, .generateUUID: return "number.square"
        case .urlEncode, .urlDecode: return "link"
        case .timestampToDate, .explainCron: return "calendar.badge.clock"
        case .convertColor: return "paintpalette"
        case .generateLoremIpsum, .convertCase: return "textformat"
        }
    }

    var requiresSelection: Bool { self != .generateUUID && self != .generateLoremIpsum }

}

enum DeveloperUtilityError: LocalizedError {
    case invalidBase64
    case invalidJWT
    case invalidCIDR
    case invalidKubernetesSecret
    case invalidCron
    case invalidYAMLJSON
    case invalidJSON
    case invalidHex
    case invalidURL
    case invalidTimestamp
    case invalidColor
    case noWords

    var errorDescription: String? {
        switch self {
        case .invalidBase64: return "The text is not valid Base64."
        case .invalidJWT: return String(localized: "Enter a compact JWT or Bearer token with JSON header and payload objects and valid numeric date claims.")
        case .invalidCIDR: return String(localized: "Enter an IPv4 address and prefix length, such as 192.168.1.10/24.")
        case .invalidKubernetesSecret: return String(localized: "Enter a Kubernetes Secret as JSON or supported block YAML with valid Base64 data values.")
        case .invalidCron: return String(localized: "Enter a five-field cron expression using numeric values, lists, ranges, and positive steps.")
        case .invalidYAMLJSON: return String(localized: "Enter JSON or one block-YAML document with string keys. Anchors, tags, block scalars, and non-JSON flow syntax are not supported.")
        case .invalidJSON: return "The text is not valid JSON."
        case .invalidHex: return "The text is not valid hexadecimal UTF-8."
        case .invalidURL: return "The text contains invalid percent encoding."
        case .invalidTimestamp: return "Enter Unix seconds between years 1 and 9999."
        case .invalidColor: return "Enter #RGB, #RRGGBB, rgb(r,g,b), or hsl(h,s%,l%)."
        case .noWords: return "The text contains no words to convert."
        }
    }
}
