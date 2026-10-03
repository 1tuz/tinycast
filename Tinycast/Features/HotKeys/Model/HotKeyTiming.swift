import Foundation

/// Shared hold-vs-tap window for Hyper Quick Press, Hyper→Voice Ask, and Voice Ask latch.
enum HotKeyTiming {
    /// Lone press shorter than this is a tap; longer is a hold.
    static let tapWindow: Duration = .milliseconds(250)

    /// Same window as `tapWindow`, for detectors that still use `TimeInterval`.
    static let tapWindowSeconds: TimeInterval = 0.25
}
