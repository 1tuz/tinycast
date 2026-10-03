import Foundation

/// One Codex realtime session used only for user speech → transcript.
@MainActor
final class CodexRealtimeTranscriber {
    enum TranscriberError: LocalizedError {
        case unavailable(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let message), .failed(let message): message
            }
        }
    }

    var onEvent: ((CodexRealtimeProtocol.Event) -> Void)?

    private let subscription: ChatGPTSubscriptionManager
    private var threadID: String?
    private var appendChain = Task<Void, Never> {}
    private(set) var isActive = false
    private var holdingServer = false

    init(subscription: ChatGPTSubscriptionManager) {
        self.subscription = subscription
    }

    /// Probes `thread/realtime/listVoices` once the app-server is up.
    func probeAvailability() async -> VoiceAskAvailability {
        do {
            try await subscription.prepareForRealtime()
            _ = try await subscription.realtimeRequest(
                method: CodexRealtimeProtocol.listVoicesMethod, timeout: .seconds(8))
            return .available
        } catch {
            return .unavailable(CodexRealtimeProtocol.unavailableMessage(for: error))
        }
    }

    func start() async throws {
        stop(sendStop: false)
        try await subscription.prepareForRealtime()
        subscription.beginRealtimeHold()
        holdingServer = true
        subscription.onRealtimeNotification = { [weak self] method, params in
            self?.handle(method: method, params: params)
        }
        do {
            let thread = try await subscription.realtimeRequest(
                method: "thread/start",
                params: [
                    "cwd": subscription.workspacePath,
                    "approvalPolicy": "never",
                    "sandbox": "read-only",
                    "ephemeral": true,
                    "config": ["web_search": "disabled"]
                ],
                timeout: .seconds(20))
            guard let id = thread["thread"]?.objectValue?["id"]?.stringValue else {
                throw TranscriberError.failed("Codex returned no realtime thread.")
            }
            threadID = id
            _ = try await subscription.realtimeRequest(
                method: CodexRealtimeProtocol.startMethod,
                params: CodexRealtimeProtocol.startParams(threadID: id),
                timeout: .seconds(20))
            isActive = true
        } catch {
            cleanup()
            releaseHold()
            if CodexRealtimeProtocol.isUnsupported(error) {
                throw TranscriberError.unavailable(CodexRealtimeProtocol.unavailableMessage(for: error))
            }
            throw TranscriberError.failed(
                (error as? LocalizedError)?.errorDescription ?? "Codex unavailable")
        }
    }

    func appendAudio(pcm: Data, samplesPerChannel: Int) {
        guard isActive, let threadID, !pcm.isEmpty else { return }
        let params = CodexRealtimeProtocol.appendAudioParams(
            threadID: threadID, pcm: pcm, samplesPerChannel: samplesPerChannel)
        appendChain = Task { [weak self, appendChain] in
            await appendChain.value
            guard let self, self.isActive else { return }
            try? await self.subscription.realtimeRequest(
                method: CodexRealtimeProtocol.appendAudioMethod,
                params: params,
                timeout: .seconds(10))
        }
    }

    /// Stops the session and waits for in-flight audio appends so the tail is not dropped.
    func finish() async {
        guard isActive || threadID != nil else { return }
        isActive = false
        await appendChain.value
        if let threadID {
            _ = try? await subscription.realtimeRequest(
                method: CodexRealtimeProtocol.stopMethod,
                params: CodexRealtimeProtocol.stopParams(threadID: threadID),
                timeout: .seconds(10))
        }
        cleanup()
        releaseHold()
    }

    func cancel() {
        guard isActive || threadID != nil || holdingServer else {
            cleanup()
            return
        }
        stop(sendStop: true)
        releaseHold()
    }

    private func stop(sendStop: Bool) {
        let id = threadID
        cleanup()
        guard sendStop, let id else { return }
        Task { [subscription] in
            _ = try? await subscription.realtimeRequest(
                method: CodexRealtimeProtocol.stopMethod,
                params: CodexRealtimeProtocol.stopParams(threadID: id),
                timeout: .seconds(5))
        }
    }

    private func cleanup() {
        isActive = false
        threadID = nil
        appendChain = Task {}
        subscription.onRealtimeNotification = nil
    }

    private func releaseHold() {
        guard holdingServer else { return }
        holdingServer = false
        subscription.realtimeSessionDidEnd()
    }

    private func handle(method: String, params: [String: JSONValue]) {
        let event = CodexRealtimeProtocol.parse(method: method, params: params)
        guard event != .ignored else { return }
        onEvent?(event)
    }
}
