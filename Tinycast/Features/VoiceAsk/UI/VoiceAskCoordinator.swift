import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

/// Owns Voice Ask: global hotkey, in-palette mic, Codex realtime transcript → Quick AI.
@MainActor
@Observable
final class VoiceAskCoordinator {
    private(set) var phase: VoiceAskPhase = .idle
    private(set) var surface: VoiceAskSurface?
    private(set) var levels: [CGFloat] = Array(repeating: 0.12, count: 28)
    private(set) var elapsed: Duration = .zero
    private(set) var availability: VoiceAskAvailability = .unknown
    private(set) var liveTranscript = ""

    private let settings: AppSettings
    private let aiSettings: AISettingsStore
    private let subscription: ChatGPTSubscriptionManager
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore

    private let microphone = MicrophoneCapture()
    private let transcriber: CodexRealtimeTranscriber
    private let pill = VoicePillController()
    private var hotKeyPolicy = VoiceAskHotKeyPolicy()
    private var transcript = VoiceAskTranscript()
    private var savedQuery: String?
    private var sessionTask: Task<Void, Never>?
    private var levelTimer: Timer?
    private var startedAt: ContinuousClock.Instant?
    private var pendingLevels: [CGFloat] = []
    private var escapeMonitor: Any?
    private var generation = 0
    /// True while this session was started by Hyper-alone hold (always push-to-talk, never latch).
    private var hyperHoldSession = false
    /// Hyper released before Codex finished connecting — finalize as soon as listening starts.
    private var pendingHyperStop = false
    /// PCM captured while the realtime session is still coming up.
    private var earlyAudio: [(Data, Int)] = []

    init(
        settings: AppSettings, aiSettings: AISettingsStore,
        subscription: ChatGPTSubscriptionManager, palette: PaletteState,
        paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.aiSettings = aiSettings
        self.subscription = subscription
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
        transcriber = CodexRealtimeTranscriber(subscription: subscription)
        pill.onCancel = { [weak self] in self?.cancel() }
        microphone.onBuffer = { [weak self] data, samples, peak in
            self?.handleAudio(data: data, samples: samples, peak: peak)
        }
        transcriber.onEvent = { [weak self] event in
            self?.handleTranscript(event)
        }
    }

    var isRecording: Bool { phase.isActive }

    func handleHotKeyDown() {
        switch hotKeyPolicy.keyDown() {
        case .start: start(surface: preferredSurface())
        case .stop: Task { await stopAndDeliver() }
        case .none: break
        }
    }

    func handleHotKeyUp() {
        switch hotKeyPolicy.keyUp() {
        case .stop: Task { await stopAndDeliver() }
        case .start, .none: break
        }
    }

    /// Hyper-alone hold past the tap window: start push-to-talk only (no latch).
    func beginHyperHoldPTT() {
        guard !phase.isActive else { return }
        hotKeyPolicy.reset()
        hyperHoldSession = true
        start(surface: preferredSurface())
    }

    /// Hyper released after a Voice Ask hold session.
    func endHyperHoldPTT() {
        guard hyperHoldSession else { return }
        hyperHoldSession = false
        // Connect still open — keep capturing; finalize the moment listening starts.
        if phase == .connecting {
            pendingHyperStop = true
            return
        }
        Task { await stopAndDeliver() }
    }

    /// Other key won: drop the Hyper dictation without delivering.
    func cancelHyperHoldPTT() {
        guard hyperHoldSession || pendingHyperStop else { return }
        hyperHoldSession = false
        pendingHyperStop = false
        cancel()
    }

    /// Mic button inside an already-visible palette.
    func toggleFromPalette() {
        if phase.isActive {
            Task { await stopAndDeliver() }
        } else {
            start(surface: .palette)
        }
    }

    func cancel() {
        generation &+= 1
        sessionTask?.cancel()
        sessionTask = nil
        hyperHoldSession = false
        pendingHyperStop = false
        earlyAudio = []
        hotKeyPolicy.reset()
        cleanupCapture()
        restoreQueryIfNeeded()
        phase = .idle
        surface = nil
        liveTranscript = ""
        transcript.reset()
    }

    func refreshAvailability() {
        Task { await probeAvailability() }
    }

    private func preferredSurface() -> VoiceAskSurface {
        paletteCoordinator.isVisible ? .palette : .pill
    }

    private func start(surface: VoiceAskSurface) {
        guard settings.aiEnabled else {
            fail("Enable AI in Settings to use Voice Ask.")
            return
        }
        generation &+= 1
        let token = generation
        self.surface = surface
        phase = .connecting
        pendingHyperStop = false
        earlyAudio = []
        liveTranscript = ""
        transcript.reset()
        pendingLevels = []
        elapsed = .zero
        if surface == .palette {
            savedQuery = palette.query
            palette.query = ""
        } else {
            savedQuery = nil
            pill.updateMetrics(settings.interfaceSize.metrics)
            pill.show(phase: phase, levels: levels, elapsed: elapsed, error: nil)
            installEscapeMonitor()
        }
        sessionTask = Task { [weak self] in
            await self?.runSession(token: token)
        }
    }

    private func runSession(token: Int) async {
        do {
            if case .unknown = availability {
                availability = await transcriber.probeAvailability()
            }
            if case .unavailable(let message) = availability {
                throw CodexRealtimeTranscriber.TranscriberError.unavailable(message)
            }
            // Mic first so Hyper hold audio is not lost while Codex connects.
            try await microphone.start()
            guard token == generation else {
                microphone.stop()
                return
            }
            startedAt = .now
            startLevelTimer()
            try await transcriber.start()
            guard token == generation else {
                microphone.stop()
                transcriber.cancel()
                return
            }
            flushEarlyAudio()
            phase = .listening
            refreshPill()
            if pendingHyperStop {
                pendingHyperStop = false
                await stopAndDeliver()
            }
        } catch {
            guard token == generation else { return }
            fail(userMessage(for: error))
        }
    }

    private func stopAndDeliver() async {
        guard phase.isActive else { return }
        let token = generation
        phase = .processing
        pendingHyperStop = false
        refreshPill()
        microphone.stop()
        stopLevelTimer()
        flushEarlyAudio()
        await transcriber.finish()
        guard token == generation else { return }
        let text = transcript.displayText
        cleanupCapture(keepPhase: true)
        hyperHoldSession = false
        hotKeyPolicy.reset()
        if text.isEmpty {
            restoreQueryIfNeeded()
            phase = .failed("No speech detected")
            refreshPill()
            schedulePillDismiss()
            return
        }
        phase = .completed
        liveTranscript = text
        deliver(text)
        phase = .idle
        surface = nil
        pill.hide()
        removeEscapeMonitor()
    }

    private func deliver(_ text: String) {
        savedQuery = nil
        let apps = core.appIndex.apps.compactMap { entry -> VoiceCommandApp? in
            guard entry.kind == .application else { return nil }
            return VoiceCommandApp(
                id: entry.id, name: entry.name, alternateTitles: entry.alternateTitles)
        }
        switch VoiceCommandRouter.route(transcript: text, apps: apps) {
        case .launchApplication(let commandApp):
            guard let entry = core.appIndex.apps.first(where: { $0.id == commandApp.id }) else {
                deliverAskAI(text)
                return
            }
            if surface == .palette { palette.query = "" }
            core.launcherCoordinator.launch(entry)
        case .automation(let transcript):
            // Explicit: `.automation` is reserved compound speech, not computer_use / agent runtime.
            // Today it shares the Quick AI path with `.askAI` (MCP tools + selected Codex route).
            deliverAskAI(transcript)
        case .askAI(let transcript):
            deliverAskAI(transcript)
        }
    }

    private func deliverAskAI(_ text: String) {
        let fromPalette = surface == .palette
        if fromPalette {
            palette.query = text
            if aiSettings.voiceAskSendAutomatically {
                core.quickAICoordinator.sendVoicePrompt(text)
            }
            return
        }
        if aiSettings.voiceAskSendAutomatically {
            core.quickAICoordinator.sendVoicePrompt(text)
        } else {
            core.quickAICoordinator.compose(text)
        }
    }

    private func fail(_ message: String) {
        hyperHoldSession = false
        pendingHyperStop = false
        earlyAudio = []
        hotKeyPolicy.reset()
        cleanupCapture()
        restoreQueryIfNeeded()
        phase = .failed(message)
        refreshPill()
        schedulePillDismiss()
        if case .unavailable = availability {
            // Keep the cached probe result.
        } else if message.contains("newer Codex") {
            availability = .unavailable(message)
        }
    }

    private func handleAudio(data: Data, samples: Int, peak: Float) {
        let level = CGFloat(min(max(peak, 0.04), 1))
        pendingLevels.append(level)
        if pendingLevels.count > 8 { pendingLevels.removeFirst(pendingLevels.count - 8) }
        switch phase {
        case .connecting:
            earlyAudio.append((data, samples))
            // Cap ~5 s at 24 kHz so a slow connect cannot grow unbounded.
            var total = earlyAudio.reduce(0) { $0 + $1.1 }
            while total > 24_000 * 5, !earlyAudio.isEmpty {
                total -= earlyAudio.removeFirst().1
            }
        case .listening:
            transcriber.appendAudio(pcm: data, samplesPerChannel: samples)
        default:
            break
        }
    }

    private func flushEarlyAudio() {
        guard !earlyAudio.isEmpty else { return }
        for (data, samples) in earlyAudio {
            transcriber.appendAudio(pcm: data, samplesPerChannel: samples)
        }
        earlyAudio = []
    }

    private func handleTranscript(_ event: CodexRealtimeProtocol.Event) {
        switch event {
        case .userTranscriptDelta(let delta):
            transcript.applyDelta(delta)
            liveTranscript = transcript.displayText
            if surface == .palette { palette.query = liveTranscript }
        case .userTranscriptDone(let text):
            transcript.applyDone(text)
            liveTranscript = transcript.displayText
            if surface == .palette { palette.query = liveTranscript }
        case .error(let message):
            fail(message.isEmpty ? "Codex unavailable" : message)
        case .closed:
            break
        case .started, .ignored:
            break
        }
    }

    private func cleanupCapture(keepPhase: Bool = false) {
        microphone.stop()
        transcriber.cancel()
        stopLevelTimer()
        removeEscapeMonitor()
        if !keepPhase {
            pill.hide()
        }
        pendingLevels = []
        earlyAudio = []
        levels = Array(repeating: 0.12, count: levels.count)
        startedAt = nil
    }

    private func restoreQueryIfNeeded() {
        if let savedQuery {
            palette.query = savedQuery
        }
        self.savedQuery = nil
    }

    private func startLevelTimer() {
        stopLevelTimer()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.phase == .listening || self.phase == .connecting else { return }
                if let startedAt = self.startedAt {
                    self.elapsed = ContinuousClock.now - startedAt
                }
                let sample = self.pendingLevels.last ?? 0.08
                self.pendingLevels.removeAll(keepingCapacity: true)
                if reduceMotion {
                    self.levels = Array(repeating: max(sample, 0.15), count: self.levels.count)
                } else {
                    var next = self.levels
                    next.removeFirst()
                    next.append(sample)
                    self.levels = next
                }
                self.refreshPill()
            }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    private func refreshPill() {
        guard surface == .pill else { return }
        pill.updateMetrics(settings.interfaceSize.metrics)
        pill.show(
            phase: phase, levels: levels, elapsed: elapsed, error: phase.errorMessage)
    }

    private func schedulePillDismiss() {
        guard surface == .pill else {
            phase = .idle
            surface = nil
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self else { return }
            self.pill.hide()
            self.phase = .idle
            self.surface = nil
            self.removeEscapeMonitor()
        }
    }

    private func installEscapeMonitor() {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return }
            Task { @MainActor in self?.cancel() }
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        escapeMonitor = nil
    }

    private func probeAvailability() async {
        availability = await transcriber.probeAvailability()
    }

    private func userMessage(for error: Error) -> String {
        if let capture = error as? MicrophoneCapture.CaptureError {
            return capture.errorDescription ?? "Microphone unavailable"
        }
        if let transcriber = error as? CodexRealtimeTranscriber.TranscriberError {
            return transcriber.errorDescription ?? "Codex unavailable"
        }
        return CodexRealtimeProtocol.unavailableMessage(for: error)
    }
}
