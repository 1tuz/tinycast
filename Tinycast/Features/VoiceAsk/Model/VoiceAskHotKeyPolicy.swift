import Foundation

/// Toggle vs push-to-talk from one shortcut: a quick tap latches, a hold releases on key-up.
struct VoiceAskHotKeyPolicy: Equatable, Sendable {
    /// Hold shorter than this and the release leaves recording on; longer is push-to-talk.
    static let latchThreshold: Duration = HotKeyTiming.tapWindow

    enum Mode: Equatable, Sendable {
        case latched
        case pushToTalk
    }

    enum Effect: Equatable, Sendable {
        case start
        case stop
        case none
    }

    var isRecording = false
    var mode: Mode?
    var pressedAt: ContinuousClock.Instant?

    mutating func keyDown(at now: ContinuousClock.Instant = .now) -> Effect {
        if isRecording {
            guard mode == .latched else { return .none }
            isRecording = false
            mode = nil
            pressedAt = nil
            return .stop
        }
        pressedAt = now
        isRecording = true
        mode = nil
        return .start
    }

    mutating func keyUp(at now: ContinuousClock.Instant = .now) -> Effect {
        guard isRecording, let pressedAt else { return .none }
        let held = now - pressedAt
        self.pressedAt = nil
        if held < Self.latchThreshold {
            mode = .latched
            return .none
        }
        mode = nil
        isRecording = false
        return .stop
    }

    mutating func reset() {
        isRecording = false
        mode = nil
        pressedAt = nil
    }
}
