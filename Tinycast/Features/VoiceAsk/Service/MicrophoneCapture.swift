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

    private var engine: AVAudioEngine?
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
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            let peak = Self.peak(of: buffer)
            let ratio = targetFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
            guard
                let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)
            else { return }
            var error: NSError?
            var consumed = false
            let status = converter.convert(to: converted, error: &error) { _, outStatus in
                if consumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                consumed = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, converted.frameLength > 0,
                let channels = converted.int16ChannelData
            else { return }
            let sampleCount = Int(converted.frameLength) * Int(converted.format.channelCount)
            let data = Data(bytes: channels[0], count: sampleCount * MemoryLayout<Int16>.size)
            let samples = Int(converted.frameLength)
            Task { @MainActor in
                self?.onBuffer?(data, samples, peak)
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
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
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
