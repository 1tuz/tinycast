import Foundation

/// Pure idle rules for the Codex app-server helper used by Voice Ask and Quick AI.
enum CodexHelperLifetimePolicy {
    /// Matches `ChatGPTSubscriptionManager.idleShutdown`.
    static let idleShutdownSeconds = 180

    /// A probe must re-arm idle when nothing is holding the helper.
    static func shouldArmIdleAfterProbe(realtimeHoldCount: Int, turnActive: Bool) -> Bool {
        realtimeHoldCount == 0 && !turnActive
    }

    /// Active realtime keeps the helper alive; ending it re-arms idle when no turn is running.
    static func shouldArmIdleAfterRealtimeEnd(realtimeHoldCount: Int, turnActive: Bool) -> Bool {
        realtimeHoldCount == 0 && !turnActive
    }
}
