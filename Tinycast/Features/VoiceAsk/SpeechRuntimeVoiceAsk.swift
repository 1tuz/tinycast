import AppKit
import AVFoundation
import Foundation
import Observation
import SwiftUI

/// Voice input is a client of Speech Runtime, not an additional model host.
/// The user controls the daemon and model downloads in Speech Runtime.app.
@MainActor
@Observable
final class SpeechRuntimeVoiceAsk {
    enum Phase: Equatable {
        case idle, connecting, listening, finishing, failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var level: Float = 0
    private(set) var availability = "Not checked"

    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let microphone = SpeechVoiceMicrophone()
    @ObservationIgnored private let transcription = SpeechRuntimeTranscriber()
    @ObservationIgnored private let pill = SpeechVoicePillController()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFinishCaptureTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fromPalette = false
    @ObservationIgnored private var savedQuery: String?
    @ObservationIgnored private var earlyAudio = Data()
    @ObservationIgnored private var stopWhenReady = false
    @ObservationIgnored private var hyperHold = false
    @ObservationIgnored private var hotKeyDownAt: ContinuousClock.Instant?

    var isActive: Bool {
        switch phase {
        case .connecting, .listening, .finishing: true
        case .idle, .failed: false
        }
    }

    var phaseTitle: String {
        switch phase {
        case .idle: "Ready"
        case .connecting: "Connecting to Speech Runtime…"
        case .listening: "Listening…"
        case .finishing: "Recognizing…"
        case .failed(let message): message
        }
    }

    init(core: AppCore) {
        self.core = core
        microphone.onAudio = { [weak self] data, level in
            self?.receiveAudio(data, level: level)
        }
        transcription.onFinal = { [weak self] phrase in
            self?.receiveFinal(phrase)
        }
    }

    func toggleFromPalette() {
        if isActive {
            requestFinish()
        } else {
            start(fromPalette: true)
        }
    }

    /// A short tap toggles; holding a separately configured shortcut is push-to-talk.
    func hotKeyDown() {
        guard hotKeyDownAt == nil else { return }
        if isActive {
            requestFinish()
            return
        }
        hotKeyDownAt = .now
        start(fromPalette: core.paletteCoordinator.isVisible)
    }

    func hotKeyUp() {
        guard let down = hotKeyDownAt else { return }
        hotKeyDownAt = nil
        if down.duration(to: .now) >= .milliseconds(250) { requestFinish() }
    }

    /// This is called only after an unused Hyper key has been held for 250 ms.
    func beginHyperHold() {
        guard !isActive else { return }
        hyperHold = true
        start(fromPalette: core.paletteCoordinator.isVisible)
    }

    func endHyperHold() {
        guard hyperHold else { return }
        hyperHold = false
        requestFinish()
    }

    func cancelHyperHold() {
        guard hyperHold else { return }
        cancel()
    }

    func checkAvailability() {
        Task {
            do {
                let models = try await transcription.checkModels()
                let names = models.map(\.model).joined(separator: ", ")
                availability = "Connected" + (names.isEmpty ? "" : " · " + names)
            } catch {
                availability = error.localizedDescription
            }
        }
    }

    func cancel() {
        generation &+= 1
        runTask?.cancel()
        runTask = nil
        finishTask?.cancel()
        finishTask = nil
        pendingFinishCaptureTask?.cancel()
        pendingFinishCaptureTask = nil
        microphone.stop()
        transcription.cancel()
        earlyAudio.removeAll(keepingCapacity: false)
        level = 0
        stopWhenReady = false
        hotKeyDownAt = nil
        hyperHold = false
        if let savedQuery { core.palette.query = savedQuery }
        savedQuery = nil
        transcript = ""
        phase = .idle
        pill.hide()
    }

    private func start(fromPalette: Bool) {
        guard UserDefaults.standard.bool(forKey: "speechVoice.enabled") else { return }
        guard core.settings.aiEnabled else { return }
        guard !isActive else { return }
        generation &+= 1
        let id = generation
        self.fromPalette = fromPalette
        phase = .connecting
        transcript = ""
        earlyAudio = Data()
        stopWhenReady = false
        level = 0
        if fromPalette {
            savedQuery = core.palette.query
            core.palette.query = ""
        } else {
            savedQuery = nil
            pill.show(voice: self)
        }
        runTask = Task { [weak self] in
            await self?.runSession(generation: id)
        }
    }

    private func runSession(generation id: Int) async {
        do {
            // Capture first: a short Hyper hold must not lose its first words during model load.
            try await microphone.start()
            guard id == generation, !Task.isCancelled else { return }
            let model = UserDefaults.standard.string(forKey: "speechVoice.model")
                .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                ?? "parakeet-ultra"
            try await transcription.start(model: model)
            guard id == generation, !Task.isCancelled else {
                transcription.cancel()
                return
            }
            if !earlyAudio.isEmpty { transcription.appendAudio(earlyAudio) }
            earlyAudio.removeAll(keepingCapacity: false)
            phase = .listening
            if stopWhenReady { requestFinish() }
        } catch {
            guard id == generation else { return }
            fail(error.localizedDescription)
        }
    }

    private func receiveAudio(_ data: Data, level: Float) {
        guard !data.isEmpty else { return }
        self.level = level
        switch phase {
        case .connecting:
            // 30 seconds of mono/16 kHz/f32 audio is only 1.92 MiB.
            // Never silently discard the start of a dictation when ANE is cold.
            if earlyAudio.count + data.count > 30 * 16_000 * 4 {
                fail("Speech Runtime did not become ready within 30 seconds of audio")
            } else {
                earlyAudio.append(data)
            }
        case .listening, .finishing:
            transcription.appendAudio(data)
        case .idle, .failed:
            break
        }
    }

    private func receiveFinal(_ phrase: String) {
        guard isActive else { return }
        let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        transcript = transcript.isEmpty ? cleaned : transcript + " " + cleaned
        if fromPalette { core.palette.query = transcript }
    }

    private func requestFinish() {
        guard finishTask == nil else { return }
        switch phase {
        case .connecting:
            stopWhenReady = true
            // Do not keep recording while the model is downloading or compiling.
            // A released Hyper hold ends capture after its short tail, regardless
            // of the Speech Runtime connection latency.
            let id = generation
            pendingFinishCaptureTask?.cancel()
            pendingFinishCaptureTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard let self, id == self.generation, !Task.isCancelled else { return }
                self.microphone.stop()
                self.pendingFinishCaptureTask = nil
            }
        case .listening:
            phase = .finishing
            let id = generation
            finishTask = Task { [weak self] in
                await self?.finish(generation: id)
            }
        case .idle, .finishing, .failed:
            break
        }
    }

    private func finish(generation id: Int) async {
        // Release after the audio tap had time to deliver its last frame.
        try? await Task.sleep(for: .milliseconds(280))
        guard id == generation, !Task.isCancelled else { return }
        pendingFinishCaptureTask?.cancel()
        pendingFinishCaptureTask = nil
        microphone.stop()
        do {
            let text = try await transcription.finish()
            guard id == generation, !Task.isCancelled else { return }
            let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !result.isEmpty else {
                fail("No speech detected")
                return
            }
            savedQuery = nil
            pill.hide()
            phase = .idle
            hotKeyDownAt = nil
            hyperHold = false
            finishTask = nil
            // Only the selected AI chat provider receives the text, never the speech service.
            if UserDefaults.standard.bool(forKey: "speechVoice.autoSend") {
                core.quickAICoordinator.sendVoicePrompt(result)
            } else {
                core.quickAICoordinator.composeVoicePrompt(result)
            }
        } catch {
            guard id == generation else { return }
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        generation &+= 1
        runTask?.cancel()
        runTask = nil
        finishTask?.cancel()
        finishTask = nil
        pendingFinishCaptureTask?.cancel()
        pendingFinishCaptureTask = nil
        microphone.stop()
        transcription.cancel()
        earlyAudio.removeAll(keepingCapacity: false)
        stopWhenReady = false
        hotKeyDownAt = nil
        hyperHold = false
        if let savedQuery { core.palette.query = savedQuery }
        savedQuery = nil
        phase = .failed(message)
        pill.show(voice: self)
        let id = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, id == self.generation else { return }
            self.pill.hide()
            self.phase = .idle
        }
    }
}

private struct SpeechRuntimeModel: Decodable {
    let model: String
    let loaded: Bool?
    let capabilities: Capabilities?

    struct Capabilities: Decodable {
        let streamingSessions: Bool?
        enum CodingKeys: String, CodingKey { case streamingSessions = "streaming_sessions" }
    }
}

private struct SpeechRuntimeModels: Decodable {
    let models: [SpeechRuntimeModel]
}

private struct SpeechRuntimeStream: Decodable {
    let stream: String
}

private struct SpeechRuntimeEvents: Decodable {
    let next: Int
    let ended: Bool
    let events: [SpeechRuntimeEvent]
}

private struct SpeechRuntimeEvent: Decodable {
    let event: String
    let data: DataPayload

    struct DataPayload: Decodable {
        let text: String?
        let message: String?
    }
}

private struct SpeechRuntimeErrorBody: Decodable {
    let error: String?
}

private struct SpeechVoiceFailure: LocalizedError {
    let detail: String
    var errorDescription: String? { detail }
}

/// The API is intentionally local and fixed. The client never starts or terminates the daemon.
@MainActor
private final class SpeechRuntimeHTTP {
    private let url = URL(string: "http://127.0.0.1:8477")!
    private let session: URLSession
    private let decoder = JSONDecoder()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 180
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    private func token() throws -> String {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SpeechRuntime/token")
        guard let raw = try? String(contentsOf: file, encoding: .utf8) else {
            throw SpeechVoiceFailure(detail: "Speech Runtime token not found. Turn on Speech Runtime.app first.")
        }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw SpeechVoiceFailure(detail: "Speech Runtime token is empty") }
        return token
    }

    private func request(
        _ method: String, _ path: String, query: [URLQueryItem] = [],
        body: Data? = nil, contentType: String? = nil,
        extraHeaders: [String: String] = [:], timeout: TimeInterval = 12
    ) async throws -> Data {
        var components = URLComponents(url: url.appendingPathComponent(String(path.dropFirst())),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("Bearer " + (try token()), forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let body { request.httpBody = body }
        for (key, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SpeechVoiceFailure(detail: "Cannot reach Speech Runtime at 127.0.0.1:8477: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw SpeechVoiceFailure(detail: "Speech Runtime returned an invalid HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(SpeechRuntimeErrorBody.self, from: data).error)
                ?? "HTTP \(http.statusCode)"
            throw SpeechVoiceFailure(detail: "Speech Runtime: \(message)")
        }
        return data
    }

    private func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func models() async throws -> [SpeechRuntimeModel] {
        try decoder.decode(SpeechRuntimeModels.self, from: await request("GET", "/v1/models")).models
    }

    func load(_ model: String) async throws {
        // Cold ANE compilation can take tens of seconds on first use.
        _ = try await request("POST", "/v1/models/load", body: json(["model": model]),
                              contentType: "application/json", timeout: 170)
    }

    func open(_ model: String) async throws -> String {
        let data = try await request("POST", "/v1/streams", body: json(["model": model]),
                                     contentType: "application/json")
        return try decoder.decode(SpeechRuntimeStream.self, from: data).stream
    }

    func audio(_ stream: String, pcm: Data) async throws {
        // Speech Runtime requires explicit sample format, not an implicit raw-PCM guess.
        _ = try await request("POST", "/v1/streams/audio",
                              query: [URLQueryItem(name: "stream", value: stream)],
                              body: pcm, contentType: "application/octet-stream",
                              extraHeaders: ["X-Sample-Format": "f32le", "X-Sample-Rate": "16000"])
    }

    func events(_ stream: String, since: Int) async throws -> SpeechRuntimeEvents {
        let data = try await request("GET", "/v1/streams/events", query: [
            URLQueryItem(name: "stream", value: stream),
            URLQueryItem(name: "since", value: String(since)),
            URLQueryItem(name: "wait", value: "0.75")
        ])
        return try decoder.decode(SpeechRuntimeEvents.self, from: data)
    }

    func end(_ stream: String) async throws {
        _ = try await request("POST", "/v1/streams/end",
                              query: [URLQueryItem(name: "stream", value: stream)], timeout: 30)
    }

    func cancel(_ stream: String) async {
        _ = try? await request("DELETE", "/v1/streams",
                               query: [URLQueryItem(name: "stream", value: stream)])
    }
}

/// Serialises audio uploads and reads completed utterances while capture continues.
@MainActor
private final class SpeechRuntimeTranscriber {
    var onFinal: ((String) -> Void)?
    private let http = SpeechRuntimeHTTP()
    private var stream: String?
    private var upload = Data()
    private var pendingBytes = 0
    private var uploadTail: Task<Void, Error>?
    private var polling: Task<Void, Error>?
    private var completed: [String] = []
    private var generation = 0
    private var isFinishing = false
    private var uploadFailure: Error?

    func checkModels() async throws -> [SpeechRuntimeModel] { try await http.models() }

    func start(model: String) async throws {
        cancel()
        let generation = self.generation
        let models = try await http.models()
        guard let selected = models.first(where: { $0.model == model }) else {
            throw SpeechVoiceFailure(detail: "Model '\(model)' is not configured in Speech Runtime.app")
        }
        guard selected.capabilities?.streamingSessions == true else {
            throw SpeechVoiceFailure(detail: "Model '\(model)' does not support streaming sessions")
        }
        if selected.loaded != true { try await http.load(model) }
        guard generation == self.generation else { throw CancellationError() }
        let stream = try await http.open(model)
        guard generation == self.generation else {
            await http.cancel(stream)
            throw CancellationError()
        }
        self.stream = stream
        polling = Task { [weak self] in
            guard let self else { return }
            try await self.pollEvents(stream: stream, generation: generation)
        }
    }

    func appendAudio(_ data: Data) {
        guard stream != nil, !isFinishing, uploadFailure == nil, !data.isEmpty else { return }
        // Do not drop packets on a slow server: fail explicitly instead of corrupting the transcript.
        if pendingBytes + upload.count + data.count > 4 * 16_000 * 4 {
            uploadFailure = SpeechVoiceFailure(detail: "Speech Runtime audio upload fell behind by four seconds")
            return
        }
        upload.append(data)
        if upload.count >= 100 * 16 * 4 { flush() }
    }

    private func flush() {
        guard let stream, !upload.isEmpty else { return }
        let data = upload
        upload.removeAll(keepingCapacity: true)
        pendingBytes += data.count
        let previous = uploadTail
        let generation = self.generation
        uploadTail = Task { [weak self] in
            try await previous?.value
            guard !Task.isCancelled, let self, generation == self.generation else {
                throw CancellationError()
            }
            try await self.http.audio(stream, pcm: data)
            guard generation == self.generation else { throw CancellationError() }
            self.pendingBytes -= data.count
        }
    }

    private func pollEvents(stream: String, generation: Int) async throws {
        var since = 0
        while !Task.isCancelled, generation == self.generation {
            let next = try await http.events(stream, since: since)
            since = next.next
            for event in next.events {
                if event.event == "final", let text = event.data.text {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        completed.append(trimmed)
                        onFinal?(trimmed)
                    }
                } else if event.event == "error" {
                    throw SpeechVoiceFailure(detail: event.data.message ?? "Speech Runtime streaming error")
                }
            }
            if next.ended { return }
        }
        throw CancellationError()
    }

    func finish() async throws -> String {
        guard let stream else { throw SpeechVoiceFailure(detail: "Speech Runtime stream is not open") }
        isFinishing = true
        flush()
        if let uploadFailure { throw uploadFailure }
        try await uploadTail?.value
        try await http.end(stream)
        // The server retains ended-session events briefly so clients can drain them.
        try await polling?.value
        let text = completed.joined(separator: " ")
        reset()
        return text
    }

    func cancel() {
        generation &+= 1
        uploadTail?.cancel()
        polling?.cancel()
        if let stream {
            Task { [http] in await http.cancel(stream) }
        }
        reset()
    }

    private func reset() {
        stream = nil
        upload = Data()
        pendingBytes = 0
        uploadTail = nil
        polling = nil
        completed = []
        isFinishing = false
        uploadFailure = nil
    }
}

/// Mic capture is owned by Tinycast. AVAudioEngine's real-time callback never touches UI state.
@MainActor
private final class SpeechVoiceMicrophone {
    var onAudio: ((Data, Float) -> Void)?
    private let engine = SpeechVoiceAudioEngine()

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
        try engine.start { [weak self] data, level in
            Task { @MainActor [weak self] in self?.onAudio?(data, level) }
        }
    }

    func stop() { engine.stop() }
}

/// An ordinary object rather than a MainActor AVAudioEngine: callbacks run on the audio thread.
private final class SpeechVoiceAudioEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?

    func start(deliver: @escaping @Sendable (Data, Float) -> Void) throws {
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
            var provided = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                if provided {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                provided = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, output.frameLength > 0,
                  let samples = output.floatChannelData?[0] else { return }
            let count = Int(output.frameLength)
            var peak: Float = 0
            for i in 0..<count { peak = max(peak, abs(samples[i])) }
            deliver(Data(bytes: samples, count: count * MemoryLayout<Float>.size), min(peak, 1))
        }
        do {
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw SpeechVoiceFailure(detail: "Cannot start the microphone: \(error.localizedDescription)")
        }
        lock.lock()
        engine = audioEngine
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let running = engine
        engine = nil
        lock.unlock()
        if let running {
            running.inputNode.removeTap(onBus: 0)
            running.stop()
        }
    }
}

@MainActor
private final class SpeechVoicePillController {
    private var panel: NSPanel?

    func show(voice: SpeechRuntimeVoiceAsk) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 62),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
                            defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .floating
            p.hidesOnDeactivate = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isMovableByWindowBackground = true
            panel = p
        }
        guard let panel else { return }
        panel.contentView = NSHostingView(rootView: SpeechVoicePill(voice: voice))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.maxY - panel.frame.height - 24))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

private struct SpeechVoicePill: View {
    let voice: SpeechRuntimeVoiceAsk

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: voice.phase == .listening ? "waveform" : "mic.fill")
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 3) {
                Text(voice.phaseTitle).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                if !voice.transcript.isEmpty {
                    Text(voice.transcript).font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    GeometryReader { geo in
                        Capsule().fill(.secondary.opacity(0.55))
                            .frame(width: max(6, geo.size.width * CGFloat(voice.level)), height: 3)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                    .frame(height: 8)
                }
            }
            Spacer(minLength: 0)
            Button { voice.cancel() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Cancel dictation")
        }
        .padding(.horizontal, 14)
        .frame(width: 320, height: 60)
        .modifier(SpeechVoiceGlass())
    }
}

private struct SpeechVoiceGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}
