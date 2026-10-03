import Foundation

/// Pure sample aggregation for realtime appendAudio RPCs.
enum RealtimeAudioBatchPolicy {
    static let sampleThreshold = 2_400
    static let flushDelayMilliseconds = 80

    /// Flush now when enough PCM has landed; otherwise wait for the delay.
    static func shouldFlushImmediately(pendingSamples: Int) -> Bool {
        pendingSamples >= sampleThreshold
    }
}
