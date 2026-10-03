import Foundation

/// Pure rule for the Hyper health-check watchdog. `CGEventSource.keyState` supplies `physicalKeyDown`.
enum HyperHoldWatchdog {
    /// Internal hold without a physical key (missed key-up / sleep) must reset.
    static func shouldReset(hyperActive: Bool, physicalKeyDown: Bool) -> Bool {
        hyperActive && !physicalKeyDown
    }
}
