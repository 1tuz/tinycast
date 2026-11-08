import Foundation

/// A user-configurable AI voice trigger: saying its word sends the rest of the phrase to Quick AI,
/// optionally pinned to one model regardless of the global default.
struct AIVoiceTrigger: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    /// The spoken trigger word or phrase, e.g. "посмотри".
    var trigger: String
    /// The model this trigger uses; nil follows the chat's current model.
    var model: AIModelSelection?

    enum CodingKeys: String, CodingKey {
        case id, trigger, model
    }
}

/// Parses and persists the trigger list. Storage mirrors other voice settings: plain UserDefaults
/// JSON, readable from anywhere without an AppSettings dependency.
enum AIVoiceTriggerStore {
    static let defaultsKey = "speechVoice.aiTriggers"

    /// The built-in trigger ships first so a fresh install understands "посмотри …".
    static let builtin = AIVoiceTrigger(trigger: "посмотри")

    static func triggers(defaults: UserDefaults = .standard) -> [AIVoiceTrigger] {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode([AIVoiceTrigger].self, from: data)
        else { return [builtin] }
        let trimmed = stored.filter { !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return trimmed.isEmpty ? [builtin] : trimmed
    }

    static func save(_ triggers: [AIVoiceTrigger], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(triggers) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    /// Normalized trigger keys the parser compares against, longest first so "посмотри в"
    /// wins over "посмотри" when both are configured.
    static func normalizedTriggers(defaults: UserDefaults = .standard) -> [String] {
        var keys = Set(triggers(defaults: defaults).map { SpeechVoiceCommandParser.normalize($0.trigger) })
        keys.remove("")
        return keys.sorted { $0.count > $1.count }
    }
}
