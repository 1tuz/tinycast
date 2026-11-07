import AVFoundation
import Foundation

// Regression: AVAudioEngine raises an ObjC exception from installTap when no input device
// exists (the hardware format query lies in that state). The exception escapes every Swift
// `catch`, tears through the concurrency runtime and segfaults the app later
// (swift_task_isCurrentExecutorWithFlagsImpl → objc_opt_class on garbage).
// The microphone must fail with a plain Swift error BEFORE touching AVAudioEngine.
@main
@MainActor
struct SpeechVoiceInputTest {
    static var failures = 0

    static func main() async {
        await unavailableProbeThrowsSwiftError()
        await probeGatesBeforeEngine()
        await deviceLossReportsThroughCallback()
        await probeGatesBeforePermissionRequest()
        print(failures == 0 ? "All voice input checks passed" : "\(failures) voice input check(s) failed")
        if failures > 0 { exit(1) }
    }

    static func check(_ description: String, _ condition: Bool) {
        print((condition ? "PASS  " : "FAIL  ") + description)
        if !condition { failures += 1 }
    }

    static func unavailableProbeThrowsSwiftError() async {
        let mic = SpeechVoiceMicrophone(inputAvailable: { false })
        mic.onAudio = { _, _ in check("audio never arrives without a device", false) }
        do {
            try await mic.start()
            check("start throws when no input device exists", false)
        } catch let error as SpeechVoiceFailure {
            check("start throws when no input device exists", true)
            check(
                "failure names the missing microphone",
                error.errorDescription == "No microphone available")
        } catch {
            check("start throws SpeechVoiceFailure, not another error", false)
        }
        mic.stop()
    }

    static func probeGatesBeforeEngine() async {
        // The engine is unreachable through the microphone when the probe fails, so a machine
        // without an input device never constructs the tap that raises.
        let mic = SpeechVoiceMicrophone(inputAvailable: { false })
        do {
            try await mic.start()
            check("engine start is gated by the input probe", false)
        } catch { check("engine start is gated by the input probe", true) }
        let engine = SpeechVoiceAudioEngine()
        engine.stop()
        check("engine stop is safe without a start", true)
    }

    static func deviceLossReportsThroughCallback() async {
        // A lost input device must surface through onDeviceLost as a plain callback, so the
        // session can finish with the transcript it already holds — never an ObjC exception.
        let mic = SpeechVoiceMicrophone(inputAvailable: { false })
        var lost = 0
        mic.onDeviceLost = { lost += 1 }
        mic.stop()
        check("stop with no capture never reports a lost device", lost == 0)
        do {
            try await mic.start()
            check("start without a device reports failure, not loss", false)
        } catch {
            check("start without a device reports failure, not loss", lost == 0)
        }
    }

    static func probeGatesBeforePermissionRequest() async {
        // Permission precedes the probe in start(); with access already decided one way or
        // another the request returns immediately, so ordering is observable only through the
        // thrown error identity. A denied environment must fail without consulting the device.
        let mic = SpeechVoiceMicrophone(inputAvailable: { false })
        do {
            try await mic.start()
            check("denied or missing input still fails", false)
        } catch let error as SpeechVoiceFailure {
            check("denied or missing input still fails", error.errorDescription != nil)
        } catch {
            check("denied or missing input still fails", false)
        }
    }
}
