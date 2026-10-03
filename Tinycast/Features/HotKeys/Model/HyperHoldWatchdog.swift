import Foundation

/// Pure rule for the Hyper health-check watchdog. `CGEventSource.keyState` supplies `physicalKeyDown`
/// for ordinary keys. Caps Lock Hyper must not use that probe — remapped F18/`keyState` often reads
/// up while the hold is live, which would cancel chords and Voice Ask PTT every second.
enum HyperHoldWatchdog {
    /// Internal hold without a physical key (missed key-up / sleep) must reset.
    /// Pass `trustsPhysicalProbe: false` for Caps Lock (session/wake paths still clear holds).
    static func shouldReset(
        hyperActive: Bool, physicalKeyDown: Bool, trustsPhysicalProbe: Bool = true
    ) -> Bool {
        guard trustsPhysicalProbe else { return false }
        return hyperActive && !physicalKeyDown
    }
}
