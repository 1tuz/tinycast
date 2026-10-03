import Foundation

/// Wire shapes for Codex `thread/realtime/*`. Only user transcript is kept for Voice Ask.
enum CodexRealtimeProtocol {
    static let sampleRate: UInt32 = 24_000
    static let channelCount: UInt16 = 1

    static let startMethod = "thread/realtime/start"
    static let appendAudioMethod = "thread/realtime/appendAudio"
    static let stopMethod = "thread/realtime/stop"
    static let listVoicesMethod = "thread/realtime/listVoices"

    static let startedNotification = "thread/realtime/started"
    static let transcriptDeltaNotification = "thread/realtime/transcript/delta"
    static let transcriptDoneNotification = "thread/realtime/transcript/done"
    static let errorNotification = "thread/realtime/error"
    static let closedNotification = "thread/realtime/closed"

    enum Event: Equatable, Sendable {
        case started(sessionID: String?)
        case userTranscriptDelta(String)
        case userTranscriptDone(String)
        case error(String)
        case closed(reason: String?)
        case ignored
    }

    static func startParams(threadID: String) -> [String: Any] {
        [
            "threadId": threadID,
            "clientManagedHandoffs": true,
            "flushTranscriptTailOnSessionEnd": true,
            "outputModality": "text",
            "includeStartupContext": false
        ]
    }

    static func appendAudioParams(threadID: String, pcm: Data, samplesPerChannel: Int) -> [String: Any] {
        [
            "threadId": threadID,
            "audio": [
                "data": pcm.base64EncodedString(),
                "sampleRate": sampleRate,
                "numChannels": channelCount,
                "samplesPerChannel": samplesPerChannel
            ]
        ]
    }

    static func stopParams(threadID: String) -> [String: Any] {
        ["threadId": threadID]
    }

    /// Parses a server notification. Assistant transcript is ignored on purpose.
    static func parse(method: String, params: [String: JSONValue]) -> Event {
        switch method {
        case startedNotification:
            return .started(sessionID: params["realtimeSessionId"]?.stringValue)
        case transcriptDeltaNotification:
            guard isUser(params["role"]?.stringValue),
                let delta = params["delta"]?.stringValue, !delta.isEmpty
            else { return .ignored }
            return .userTranscriptDelta(delta)
        case transcriptDoneNotification:
            guard isUser(params["role"]?.stringValue),
                let text = params["text"]?.stringValue
            else { return .ignored }
            return .userTranscriptDone(text)
        case errorNotification:
            return .error(params["message"]?.stringValue ?? "Codex realtime failed.")
        case closedNotification:
            return .closed(reason: params["reason"]?.stringValue)
        default:
            return .ignored
        }
    }

    static func isUnsupported(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let lower = message.lowercased()
        return lower.contains("experimentalapi")
            || lower.contains("unknown method")
            || lower.contains("method not found")
            || lower.contains("not supported")
            || lower.contains("thread/realtime")
    }

    static func unavailableMessage(for error: Error) -> String {
        if isUnsupported(error) {
            return "Voice Ask requires a newer Codex CLI"
        }
        return (error as? LocalizedError)?.errorDescription ?? "Codex unavailable"
    }

    private static func isUser(_ role: String?) -> Bool {
        role?.lowercased() == "user"
    }
}

/// Accumulates live user transcript from delta/done notifications.
struct VoiceAskTranscript: Equatable, Sendable {
    private(set) var text = ""
    private var partial = ""

    var displayText: String {
        let combined = text + partial
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    mutating func applyDelta(_ delta: String) {
        partial += delta
    }

    mutating func applyDone(_ finalText: String) {
        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let live = (text + partial).trimmingCharacters(in: .whitespacesAndNewlines)
        // A late done can lag behind newer speech already reflected in `partial`.
        if live.count >= trimmed.count, live.hasPrefix(trimmed) || !partial.isEmpty {
            text = live
        } else if trimmed.hasPrefix(text) || text.isEmpty {
            text = trimmed
        } else if !live.contains(trimmed) {
            text = [live, trimmed].filter { !$0.isEmpty }.joined(separator: " ")
        }
        partial = ""
    }

    mutating func reset() {
        text = ""
        partial = ""
    }
}
