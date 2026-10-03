import AVFoundation
import Foundation

/// Captures microphone PCM for Codex realtime. Lives only while a Voice Ask session is listening.
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

    private var engine: AVAudioEngine?
    private var coalesceTask: Task<Void, Never>?
    private var coalescedPCM = Data()
    private var coalescedSamples = 0
    private var coalescedPeak: Float = 0
    private let targetFormat: AVAudioFormat? = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Double(CodexRealtimeProtocol.sampleRate),
        channels: AVAudioChannelCount(CodexRealtimeProtocol.channelCount),
        interleaved: true)

    var isRunning: Bool { engine?.isRunning == true }

    func start() async throws {
        stop()
        switch Permissions.microphoneAccess() {
        case .denied: throw CaptureError.denied
        case .notDetermined:
            guard await Permissions.requestMicrophoneAccess() else { throw CaptureError.denied }
        case .granted: break
        }

        guard let targetFormat else { throw CaptureError.unavailable }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CaptureError.unavailable
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw CaptureError.unavailable
        }

        let bufferSize: AVAudioFrameCount = 1_024
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            // Convert on the audio thread; hop to MainActor only after coalescing.
            guard let converted = Self.convert(buffer, with: converter, to: targetFormat) else {
                return
            }
            let peak = converted.peak
            let data = converted.data
            let samples = converted.samples
            Task { @MainActor in
                self?.enqueue(data: data, samples: samples, peak: peak)
            }
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw CaptureError.unavailable
        }
        self.engine = engine
    }

    func stop() {
        coalesceTask?.cancel()
        coalesceTask = nil
        flushCoalesced()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
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

    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to targetFormat: AVAudioFormat
    ) -> (data: Data, samples: Int, peak: Float)? {
        let peak = Self.peak(of: buffer)
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

    private nonisolated static func peak(of buffer: AVAudioPCMBuffer) -> Float {
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
