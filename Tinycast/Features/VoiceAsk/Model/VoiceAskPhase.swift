import Foundation

/// Lifetime of one Voice Ask capture. Idle means nothing is allocated.
enum VoiceAskPhase: Equatable, Sendable {
    case idle
    case connecting
    case listening
    case processing
    case completed
    case failed(String)

    var isActive: Bool {
        switch self {
        case .connecting, .listening, .processing: true
        case .idle, .completed, .failed: false
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = self { message } else { nil }
    }
}

/// Where the transcript is written while a session runs.
enum VoiceAskSurface: Equatable, Sendable {
    /// Global hotkey with the palette closed: floating pill, then open Quick AI.
    case pill
    /// Mic from an already-open palette: transcript lands in the query field.
    case palette
}

enum VoiceAskAvailability: Equatable, Sendable {
    case unknown
    case available
    case unavailable(String)

    var isAvailable: Bool {
        if case .available = self { true } else { false }
    }

    var statusText: String {
        switch self {
        case .unknown: "Checking Codex realtime…"
        case .available: "Codex realtime available"
        case .unavailable(let message): message
        }
    }
}
