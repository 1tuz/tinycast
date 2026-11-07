import AVFoundation
import Foundation

/// Mic capture is owned by Tinycast. AVAudioEngine's real-time callback never touches UI state.
@MainActor
final class SpeechVoiceMicrophone {
    var onAudio: ((Data, Float) -> Void)?
    /// Unplugging the headset mid-dictation: the engine reports it, and the session ends cleanly.
    var onDeviceLost: (() -> Void)?
    private let engine = SpeechVoiceAudioEngine()

    /// Injectable so the harness can simulate a Mac with no input device.
    private let inputAvailable: () -> Bool

    init(inputAvailable: @escaping () -> Bool = { AVCaptureDevice.default(for: .audio) != nil }) {
        self.inputAvailable = inputAvailable
    }

    func start() async throws {
        stop()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw SpeechVoiceFailure(detail: "Microphone access denied")
            }
        default: throw SpeechVoiceFailure(detail: "Enable microphone access for Tinycast in System Settings")
        }
        // AVAudioEngine's hardware format lies when no input device exists; installTap then raises
        // an ObjC exception that no Swift `catch` can stop.
        guard inputAvailable() else {
            throw SpeechVoiceFailure(detail: "No microphone available")
        }
        try engine.start(
            deliver: { [weak self] data, level in
                Task { @MainActor [weak self] in self?.onAudio?(data, level) }
            },
            onDeviceLost: { [weak self] in
                Task { @MainActor [weak self] in self?.onDeviceLost?() }
            })
    }

    func stop() { engine.stop() }
}

/// An ordinary object rather than a MainActor AVAudioEngine: callbacks run on the audio thread.
final class SpeechVoiceAudioEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?

    func start(
        deliver: @escaping @Sendable (Data, Float) -> Void,
        onDeviceLost: @escaping @Sendable () -> Void
    ) throws {
        stop()
        let audioEngine = AVAudioEngine()
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw SpeechVoiceFailure(detail: "No usable microphone input format")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            let length = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / inputFormat.sampleRate)) + 32
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: length) else { return }
            let provider = AudioBufferProvider(buffer: buffer)
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if let pending = provider.take() {
                    inputStatus.pointee = .haveData
                    return pending
                }
                inputStatus.pointee = .noDataNow
                return nil
            }
            guard status != .error, output.frameLength > 0,
                  let samples = output.floatChannelData?[0] else { return }
            let count = Int(output.frameLength)
            var peak: Float = 0
            for i in 0..<count { peak = max(peak, abs(samples[i])) }
            deliver(Data(bytes: samples, count: count * MemoryLayout<Float>.size), min(peak, 1))
        }
        // An unplugged headset reconfigures the engine; without a live input the session is over.
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { note in
            guard let engine = note.object as? AVAudioEngine else { return }
            if engine.inputNode.outputFormat(forBus: 0).channelCount == 0 { onDeviceLost() }
        }
        do {
            try audioEngine.start()
        } catch {
            NotificationCenter.default.removeObserver(observer)
            input.removeTap(onBus: 0)
            throw SpeechVoiceFailure(detail: "Cannot start the microphone: \(error.localizedDescription)")
        }
        lock.lock()
        configurationObserver = observer
        engine = audioEngine
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let running = engine
        let observer = configurationObserver
        engine = nil
        configurationObserver = nil
        lock.unlock()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let running {
            running.inputNode.removeTap(onBus: 0)
            running.stop()
        }
    }
}

/// AVAudioConverter's callback may run more than once; the one-shot handoff needs a mutable cell.
final class AudioBufferProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take() -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        let pending = buffer
        buffer = nil
        return pending
    }
}

struct SpeechVoiceFailure: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}
