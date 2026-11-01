import Foundation

enum BuiltInQuickAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case fixGrammar
    case rewrite
    case translate
    case summarize
    case base64Encode
    case base64Decode
    case convertYAMLJSON
    case decodeJWT
    case calculateCIDR
    case decodeKubernetesSecret
    case explainCron
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

    var id: String { rawValue }
    var developerUtility: DeveloperUtility? { DeveloperUtility(rawValue: rawValue) }

    var title: String {
        switch self {
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .base64Encode, .base64Decode, .formatJSON, .minifyJSON, .hashMD5, .hashSHA256, .hexEncode,
            .hexDecode, .urlEncode, .urlDecode, .generateUUID, .timestampToDate, .convertColor,
            .generateLoremIpsum, .convertCase, .convertYAMLJSON, .explainCron, .decodeJWT, .calculateCIDR, .decodeKubernetesSecret:
            return developerUtility!.title
        }
    }

    var symbol: String {
        switch self {
        case .fixGrammar: return "textformat"
        case .rewrite: return "wand.and.sparkles"
        case .translate: return "translate"
        case .summarize: return "text.line.3.summary"
        case .base64Encode, .base64Decode, .formatJSON, .minifyJSON, .hashMD5, .hashSHA256, .hexEncode,
            .hexDecode, .urlEncode, .urlDecode, .generateUUID, .timestampToDate, .convertColor,
            .generateLoremIpsum, .convertCase, .convertYAMLJSON, .explainCron, .decodeJWT, .calculateCIDR, .decodeKubernetesSecret:
            return developerUtility!.symbol
        }
    }

    var progressTitle: String {
        switch self {
        case .fixGrammar: return "Fixing Grammar…"
        case .rewrite: return "Rewriting…"
        case .translate: return "Translating…"
        case .summarize: return "Summarizing…"
        case .base64Encode, .hexEncode, .urlEncode: return "Encoding…"
        case .base64Decode, .hexDecode, .urlDecode, .decodeJWT, .decodeKubernetesSecret: return "Decoding…"
        case .calculateCIDR: return String(localized: "Calculating…")
        case .explainCron: return String(localized: "Explaining…")
        case .formatJSON: return "Formatting…"
        case .minifyJSON: return "Minifying…"
        case .hashMD5, .hashSHA256: return "Hashing…"
        case .generateUUID, .generateLoremIpsum: return "Generating…"
        case .timestampToDate, .convertColor, .convertCase, .convertYAMLJSON: return "Converting…"
        }
    }

    var alwaysPreviews: Bool { self == .summarize }
    var replacesDirectlyByDefault: Bool { self == .fixGrammar }
    var showsDiff: Bool { self == .fixGrammar || self == .rewrite }
    var usesTranslationFramework: Bool { self == .translate }
    var requiresAI: Bool { developerUtility == nil }
}
