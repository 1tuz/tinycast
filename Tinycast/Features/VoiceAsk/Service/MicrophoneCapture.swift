import AVFoundation
import Foundation

/// Captures microphone PCM for Codex realtime. Lives only while a Voice Ask session is listening.
///
/// The AVAudioEngine tap runs on a realtime audio queue — never touch `@MainActor` state there.
/// Conversion stays off-main; delivery hops to MainActor via an explicit `Task`.
@MainActor
final class MicrophoneCapture {
    enum CaptureError: LocalizedError {
        case unavailable
        case denied

        var errorDescription: String? {
            switch self {
            case .unavailable: "Microphone unavailable"
            case .denied: "Microphone unavailable"
            }
        }
    }

    /// Peak amplitude in 0...1 for each delivered buffer, plus the PCM payload.
    var onBuffer: ((Data, Int, Float) -> Void)?

    /// Coalesce audio-thread taps onto MainActor near waveform FPS without delaying PTT much.
    static let coalesceInterval: Duration = .milliseconds(40)

    private let engine = MicrophoneCaptureEngine()
    private var coalesceTask: Task<Void, Never>?
    private var coalescedPCM = Data()
    private var coalescedSamples = 0
    private var coalescedPeak: Float = 0

    var isRunning: Bool { engine.isRunning }

    func start() async throws {
        stop()
        switch Permissions.microphoneAccess() {
        case .denied: throw CaptureError.denied
        case .notDetermined:
            guard await Permissions.requestMicrophoneAccess() else { throw CaptureError.denied }
        case .granted: break
        }

        do {
            try engine.start { [weak self] data, samples, peak in
                Task { @MainActor in
                    self?.enqueue(data: data, samples: samples, peak: peak)
                }
            }
        } catch {
            throw CaptureError.unavailable
        }
    }

    func stop() {
        coalesceTask?.cancel()
        coalesceTask = nil
        flushCoalesced()
        engine.stop()
        coalescedPCM = Data()
        coalescedSamples = 0
        coalescedPeak = 0
    }

    private func enqueue(data: Data, samples: Int, peak: Float) {
        coalescedPCM.append(data)
        coalescedSamples += samples
        coalescedPeak = max(coalescedPeak, peak)
        guard coalesceTask == nil else { return }
        coalesceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coalesceInterval)
            guard let self, !Task.isCancelled else { return }
            self.coalesceTask = nil
            self.flushCoalesced()
        }
    }

    private func flushCoalesced() {
        guard !coalescedPCM.isEmpty else { return }
        let data = coalescedPCM
        let samples = coalescedSamples
        let peak = coalescedPeak
        coalescedPCM = Data()
        coalescedSamples = 0
        coalescedPeak = 0
        onBuffer?(data, samples, peak)
    }
}

/// Owns `AVAudioEngine` off the main actor so the tap callback never trips isolation asserts.
final class MicrophoneCaptureEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var onPCM: (@Sendable (Data, Int, Float) -> Void)?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return engine?.isRunning == true
    }

    func start(onPCM: @escaping @Sendable (Data, Int, Float) -> Void) throws {
        stop()
        self.onPCM = onPCM

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: Double(CodexRealtimeProtocol.sampleRate),
                channels: AVAudioChannelCount(CodexRealtimeProtocol.channelCount),
                interleaved: true)
        else {
            throw NSError(
                domain: "MicrophoneCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone unavailable"])
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "MicrophoneCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone unavailable"])
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(
                domain: "MicrophoneCapture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Microphone unavailable"])
        }

        let bufferSize: AVAudioFrameCount = 1_024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            guard let converted = Self.convert(buffer, with: converter, to: targetFormat) else {
                return
            }
            let deliver = self.onPCM
            deliver?(converted.data, converted.samples, converted.peak)
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        lock.lock()
        self.engine = engine
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let engine = self.engine
        self.engine = nil
        onPCM = nil
        lock.unlock()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> (data: Data, samples: Int, peak: Float)? {
        let peak = peak(of: buffer)
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
        else { return nil }
        // Box avoids mutation-of-captured-var warnings in the converter input callback.
        final class Once: @unchecked Sendable {
            var done = false
            let buffer: AVAudioPCMBuffer
            init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        }
        let once = Once(buffer)
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            if once.done {
                outStatus.pointee = .noDataNow
                return nil
            }
            once.done = true
            outStatus.pointee = .haveData
            return once.buffer
        }
        guard status != .error, converted.frameLength > 0,
            let channels = converted.int16ChannelData
        else { return nil }
        let sampleCount = Int(converted.frameLength) * Int(converted.format.channelCount)
        let data = Data(bytes: channels[0], count: sampleCount * MemoryLayout<Int16>.size)
        return (data, Int(converted.frameLength), peak)
    }

    private static func peak(of buffer: AVAudioPCMBuffer) -> Float {
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        if let samples = buffer.floatChannelData?[0] {
            var peak: Float = 0
            for i in 0..<count {
                peak = max(peak, abs(samples[i]))
            }
            return min(peak, 1)
        }
        if let samples = buffer.int16ChannelData?[0] {
            var peak: Int16 = 0
            for i in 0..<count {
                let value = abs(samples[i])
                if value > peak { peak = value }
            }
            return Float(peak) / Float(Int16.max)
        }
        return 0
    }
}
