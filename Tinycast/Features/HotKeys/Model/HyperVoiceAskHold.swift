import Foundation

/// Opt-in Hyper-alone hold → Voice Ask push-to-talk. Latch never applies on this path.
struct HyperVoiceAskHold: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case pending
        case recording
        case combo
    }

    enum Effect: Equatable, Sendable {
        case none
        case scheduleHoldCheck
        case cancelHoldCheck
        case start
        case stop
        case cancel
    }

    private(set) var phase: Phase = .idle
    var isEnabled = false

    mutating func beginHold() -> Effect {
        guard isEnabled else { return .none }
        phase = .pending
        return .scheduleHoldCheck
    }

    mutating func otherKey() -> Effect {
        guard isEnabled else { return .none }
        switch phase {
        case .pending:
            phase = .combo
            return .cancelHoldCheck
        case .recording:
            phase = .combo
            return .cancel
        case .idle, .combo:
            return .none
        }
    }

    mutating func holdThresholdReached() -> Effect {
        guard isEnabled, phase == .pending else { return .none }
        phase = .recording
        return .start
    }

    mutating func endHold() -> Effect {
        let previous = phase
        phase = .idle
        switch previous {
        case .recording: return .stop
        case .pending: return .cancelHoldCheck
        case .combo, .idle: return .none
        }
    }

    mutating func reset() {
        phase = .idle
    }
}
