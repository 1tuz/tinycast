import Foundation

/// Enough of a launcher entry for voice resolve. Foundation-only so the harness can pin it.
struct VoiceCommandApp: Equatable, Sendable {
    let id: String
    let name: String
    let alternateTitles: [String]

    init(id: String, name: String, alternateTitles: [String] = []) {
        self.id = id
        self.name = name
        self.alternateTitles = alternateTitles
    }
}

/// Deterministic voice intents. Obvious commands only — no NLP.
enum VoiceCommandPlan: Equatable, Sendable {
    /// "Open Zed" / "Открой Safari" — resolve through AppIndex, launch directly.
    case launchApplication(query: String)
    /// Compound speech ("Open Safari and find…") reserved for a future automation route.
    case automation(String)
    /// Not a local command, or a launch that could not be resolved confidently.
    case askAI(String)
}

/// Pure classifier for Voice Ask transcripts.
enum VoiceCommandPolicy {
    private static let openVerbs = ["open", "launch", "открой", "запусти"]
    private static let compoundMarkers = [
        " and ", " и ", " then ", " потом ", " чтобы ", " and then ", ", and "
    ]

    static func plan(for transcript: String) -> VoiceCommandPlan {
        let trimmed = Self.normalize(transcript)
        guard !trimmed.isEmpty else { return .askAI(transcript) }
        guard let (verb, remainder) = splitVerb(trimmed) else {
            return .askAI(transcript)
        }
        _ = verb
        let query = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .askAI(transcript) }
        if isCompound(query) { return .automation(transcript) }
        return .launchApplication(query: query)
    }

    static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".?!…,".contains(last) {
            text.removeLast()
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func splitVerb(_ text: String) -> (verb: String, remainder: String)? {
        let lower = text.lowercased()
        for verb in openVerbs {
            guard lower.hasPrefix(verb) else { continue }
            let index = text.index(text.startIndex, offsetBy: verb.count)
            guard index < text.endIndex, text[index].isWhitespace else { continue }
            return (verb, String(text[text.index(after: index)...]))
        }
        return nil
    }

    private static func isCompound(_ query: String) -> Bool {
        let lower = " \(query.lowercased()) "
        return compoundMarkers.contains { lower.contains($0) }
    }
}

/// Resolves a classified plan against known apps. No effects — the coordinator launches.
enum VoiceCommandRouter {
    enum Outcome: Equatable, Sendable {
        case launchApplication(VoiceCommandApp)
        case automation(String)
        case askAI(String)
    }

    static func route(transcript: String, apps: [VoiceCommandApp]) -> Outcome {
        switch VoiceCommandPolicy.plan(for: transcript) {
        case .launchApplication(let query):
            if let app = resolve(query, in: apps) {
                return .launchApplication(app)
            }
            return .askAI(transcript)
        case .automation(let text):
            return .automation(text)
        case .askAI(let text):
            return .askAI(text)
        }
    }

    /// Exact name / alternate title only. Fuzzy guessing belongs to Quick AI, not Voice Ask.
    static func resolve(_ query: String, in apps: [VoiceCommandApp]) -> VoiceCommandApp? {
        let needle = fold(query)
        guard !needle.isEmpty else { return nil }
        if let exact = apps.first(where: { fold($0.name) == needle }) {
            return exact
        }
        if let alternate = apps.first(where: { $0.alternateTitles.contains { fold($0) == needle } })
        {
            return alternate
        }
        return nil
    }

    private static func fold(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
