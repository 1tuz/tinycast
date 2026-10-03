import Foundation

@main
@MainActor
enum VoiceAskTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        hotKeyPolicy()
        hyperVoiceAskHold()
        hyperHoldWatchdog()
        transcriptAccumulation()
        protocolParsing()
        phaseFlags()
        voiceCommands()
        codexHelperLifetime()
        realtimeAudioBatch()
        voicePromptOpenPolicy()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func hotKeyPolicy() {
        expect(
            VoiceAskHotKeyPolicy.latchThreshold == HotKeyTiming.tapWindow,
            "Voice Ask latch shares HotKeyTiming.tapWindow")
        var policy = VoiceAskHotKeyPolicy()
        let t0 = ContinuousClock.Instant.now

        expect(policy.keyDown(at: t0) == .start, "first keyDown starts")
        expect(policy.isRecording, "recording after keyDown")
        // Quick release: latch.
        let quick = t0.advanced(by: .milliseconds(100))
        expect(policy.keyUp(at: quick) == .none, "quick keyUp keeps recording")
        expect(policy.mode == .latched, "latched after quick tap")
        expect(policy.keyDown(at: quick.advanced(by: .milliseconds(50))) == .stop, "second tap stops")
        expect(!policy.isRecording, "idle after second tap")

        policy.reset()
        let holdStart = ContinuousClock.Instant.now
        expect(policy.keyDown(at: holdStart) == .start, "hold keyDown starts")
        let holdEnd = holdStart.advanced(by: HotKeyTiming.tapWindow + .milliseconds(50))
        expect(policy.keyUp(at: holdEnd) == .stop, "long hold keyUp stops")
        expect(!policy.isRecording, "idle after push-to-talk release")

        policy.reset()
        expect(policy.keyUp(at: .now) == .none, "keyUp while idle is a no-op")
    }

    static func hyperVoiceAskHold() {
        expect(
            HotKeyTiming.tapWindowSeconds == 0.25,
            "tap window seconds matches Duration milliseconds")

        // Setting OFF → Hyper hold machine stays inert (Quick Press / combo untouched).
        var off = HyperVoiceAskHold()
        off.isEnabled = false
        expect(off.beginHold() == .none, "disabled beginHold is a no-op")
        expect(off.phase == .idle, "disabled stays idle after beginHold")
        expect(off.otherKey() == .none, "disabled otherKey is a no-op")
        expect(off.holdThresholdReached() == .none, "disabled threshold is a no-op")
        expect(off.endHold() == .none, "disabled endHold is a no-op")

        // Short lone Hyper → pending then release without start (Quick Press path).
        var short = HyperVoiceAskHold()
        short.isEnabled = true
        expect(short.beginHold() == .scheduleHoldCheck, "enabled beginHold schedules check")
        expect(short.phase == .pending, "pending after beginHold")
        expect(short.endHold() == .cancelHoldCheck, "early release cancels check, no Voice Ask")
        expect(short.phase == .idle, "idle after short release")

        // Hyper+key before threshold → combo, no Voice Ask.
        var combo = HyperVoiceAskHold()
        combo.isEnabled = true
        expect(combo.beginHold() == .scheduleHoldCheck, "combo beginHold schedules")
        expect(combo.otherKey() == .cancelHoldCheck, "other key before threshold cancels check")
        expect(combo.phase == .combo, "combo after other key")
        expect(combo.holdThresholdReached() == .none, "threshold ignored in combo")
        expect(combo.endHold() == .none, "combo release does not stop Voice Ask")

        // Hold past threshold → start; release → stop.
        var hold = HyperVoiceAskHold()
        hold.isEnabled = true
        expect(hold.beginHold() == .scheduleHoldCheck, "hold beginHold schedules")
        expect(hold.holdThresholdReached() == .start, "threshold starts Voice Ask")
        expect(hold.phase == .recording, "recording after threshold")
        expect(hold.endHold() == .stop, "release stops Voice Ask")
        expect(hold.phase == .idle, "idle after stop")

        // Other key during Voice Ask → cancel + combo.
        var interrupt = HyperVoiceAskHold()
        interrupt.isEnabled = true
        expect(interrupt.beginHold() == .scheduleHoldCheck, "interrupt beginHold")
        expect(interrupt.holdThresholdReached() == .start, "interrupt starts")
        expect(interrupt.otherKey() == .cancel, "other key cancels active Voice Ask")
        expect(interrupt.phase == .combo, "combo after cancel")
        expect(interrupt.endHold() == .none, "combo release after cancel is quiet")
    }

    static func transcriptAccumulation() {
        var transcript = VoiceAskTranscript()
        transcript.applyDelta("Hello ")
        transcript.applyDelta("world")
        expect(transcript.displayText == "Hello world", "deltas concatenate")
        transcript.applyDone("Hello world")
        expect(transcript.displayText == "Hello world", "done replaces partial")
        transcript.applyDelta(" again")
        expect(transcript.displayText == "Hello world again", "new partial after done")
        transcript.applyDone("Hello world again")
        expect(transcript.displayText == "Hello world again", "second done sticks")

        var late = VoiceAskTranscript()
        late.applyDelta("Okay.")
        late.applyDelta("I will check")
        late.applyDone("Okay.")
        expect(late.displayText == "Okay.I will check", "late done preserves newer speech")
    }

    static func protocolParsing() {
        let delta = CodexRealtimeProtocol.parse(
            method: CodexRealtimeProtocol.transcriptDeltaNotification,
            params: ["role": .string("user"), "delta": .string("hi")])
        expect(delta == .userTranscriptDelta("hi"), "user delta")

        let assistant = CodexRealtimeProtocol.parse(
            method: CodexRealtimeProtocol.transcriptDeltaNotification,
            params: ["role": .string("assistant"), "delta": .string("nope")])
        expect(assistant == .ignored, "assistant delta ignored")

        let done = CodexRealtimeProtocol.parse(
            method: CodexRealtimeProtocol.transcriptDoneNotification,
            params: ["role": .string("user"), "text": .string("final")])
        expect(done == .userTranscriptDone("final"), "user done")

        let error = CodexRealtimeProtocol.parse(
            method: CodexRealtimeProtocol.errorNotification,
            params: ["message": .string("boom")])
        expect(error == .error("boom"), "error event")

        let started = CodexRealtimeProtocol.parse(
            method: CodexRealtimeProtocol.startedNotification,
            params: ["realtimeSessionId": .string("s1")])
        expect(started == .started(sessionID: "s1"), "started event")

        struct Fake: LocalizedError {
            var errorDescription: String? { "thread/realtime/start requires experimentalApi capability" }
        }
        expect(CodexRealtimeProtocol.isUnsupported(Fake()), "experimentalApi error is unsupported")
        expect(
            CodexRealtimeProtocol.unavailableMessage(for: Fake())
                == "Voice Ask requires a newer Codex CLI",
            "unsupported message")

        let params = CodexRealtimeProtocol.startParams(threadID: "t1")
        expect(params["clientManagedHandoffs"] as? Bool == true, "client managed handoffs")
        expect(params["flushTranscriptTailOnSessionEnd"] as? Bool == true, "flush tail")
        expect(params["outputModality"] as? String == "text", "text modality")
    }

    static func phaseFlags() {
        expect(VoiceAskPhase.idle.isActive == false, "idle inactive")
        expect(VoiceAskPhase.connecting.isActive, "connecting active")
        expect(VoiceAskPhase.listening.isActive, "listening active")
        expect(VoiceAskPhase.processing.isActive, "processing active")
        expect(VoiceAskPhase.completed.isActive == false, "completed inactive")
        expect(VoiceAskPhase.failed("x").errorMessage == "x", "failed message")
        expect(VoiceAskAvailability.available.isAvailable, "available")
        expect(!VoiceAskAvailability.unavailable("old").isAvailable, "unavailable")
    }

    static func voiceCommands() {
        let apps = [
            VoiceCommandApp(id: "/Apps/Zed.app", name: "Zed"),
            VoiceCommandApp(
                id: "/Apps/Safari.app", name: "Safari", alternateTitles: ["Safari Browser"]),
            VoiceCommandApp(id: "/Apps/Notes.app", name: "Notes")
        ]

        expect(
            VoiceCommandPolicy.plan(for: "Open Zed") == .launchApplication(query: "Zed"),
            "Open Zed")
        expect(
            VoiceCommandPolicy.plan(for: "Launch Safari!") == .launchApplication(query: "Safari"),
            "Launch Safari strips punctuation")
        expect(
            VoiceCommandPolicy.plan(for: "Открой Zed") == .launchApplication(query: "Zed"),
            "Открой Zed")
        expect(
            VoiceCommandPolicy.plan(for: "Запусти Notes") == .launchApplication(query: "Notes"),
            "Запусти Notes")
        expect(
            VoiceCommandPolicy.plan(for: "what is kubernetes") == .askAI("what is kubernetes"),
            "plain speech is askAI")
        expect(
            VoiceCommandPolicy.plan(for: "Open Safari and find Kubernetes docs")
                == .automation("Open Safari and find Kubernetes docs"),
            "compound English → automation")
        expect(
            VoiceCommandPolicy.plan(for: "Открой Safari и найди документацию")
                == .automation("Открой Safari и найди документацию"),
            "compound Russian → automation")

        expect(
            VoiceCommandRouter.route(transcript: "Open Zed", apps: apps)
                == .launchApplication(apps[0]),
            "routes Open Zed to launch")
        expect(
            VoiceCommandRouter.route(transcript: "Открой Safari Browser", apps: apps)
                == .launchApplication(apps[1]),
            "alternate title resolves")
        expect(
            VoiceCommandRouter.route(transcript: "Open UnknownApp", apps: apps)
                == .askAI("Open UnknownApp"),
            "missing app falls back to askAI")
        expect(
            VoiceCommandRouter.route(
                transcript: "Open Safari and find Kubernetes", apps: apps)
                == .automation("Open Safari and find Kubernetes"),
            "automation is not forced into a launch")
        expect(
            VoiceCommandRouter.resolve("zed", in: apps)?.id == apps[0].id,
            "resolve is case-insensitive")
        expect(VoiceCommandRouter.resolve("Saf", in: apps) == nil, "no fuzzy guess on prefix")
    }

    static func hyperHoldWatchdog() {
        expect(
            !HyperHoldWatchdog.shouldReset(hyperActive: false, physicalKeyDown: false),
            "idle + key up → no reset")
        expect(
            !HyperHoldWatchdog.shouldReset(hyperActive: false, physicalKeyDown: true),
            "idle + key down → no reset")
        expect(
            !HyperHoldWatchdog.shouldReset(hyperActive: true, physicalKeyDown: true),
            "hold + physical down → keep hold")
        expect(
            HyperHoldWatchdog.shouldReset(hyperActive: true, physicalKeyDown: false),
            "stale hold without physical key → reset")
        expect(
            !HyperHoldWatchdog.shouldReset(
                hyperActive: true, physicalKeyDown: false, trustsPhysicalProbe: false),
            "Caps Lock Hyper skips keyState probe")
    }

    static func codexHelperLifetime() {
        expect(
            CodexHelperLifetimePolicy.idleShutdownSeconds == 180,
            "idle shutdown is 180 seconds")
        expect(
            CodexHelperLifetimePolicy.shouldArmIdleAfterProbe(realtimeHoldCount: 0, turnActive: false),
            "probe with no hold arms idle")
        expect(
            !CodexHelperLifetimePolicy.shouldArmIdleAfterProbe(realtimeHoldCount: 1, turnActive: false),
            "probe during realtime hold does not arm idle")
        expect(
            !CodexHelperLifetimePolicy.shouldArmIdleAfterProbe(realtimeHoldCount: 0, turnActive: true),
            "probe during an active turn does not arm idle")
        expect(
            CodexHelperLifetimePolicy.shouldArmIdleAfterRealtimeEnd(
                realtimeHoldCount: 0, turnActive: false),
            "realtime end with zero holds arms idle")
        expect(
            !CodexHelperLifetimePolicy.shouldArmIdleAfterRealtimeEnd(
                realtimeHoldCount: 1, turnActive: false),
            "nested realtime hold keeps helper alive")
    }

    static func realtimeAudioBatch() {
        expect(
            RealtimeAudioBatchPolicy.sampleThreshold == 2_400,
            "batch ~100 ms at 24 kHz")
        expect(
            RealtimeAudioBatchPolicy.flushDelayMilliseconds == 80,
            "flush delay stays under a frame of PTT lag")
        expect(
            !RealtimeAudioBatchPolicy.shouldFlushImmediately(pendingSamples: 1_024),
            "single 1024-frame tap waits")
        expect(
            RealtimeAudioBatchPolicy.shouldFlushImmediately(pendingSamples: 2_400),
            "threshold flushes immediately")
        expect(
            RealtimeAudioBatchPolicy.shouldFlushImmediately(pendingSamples: 4_800),
            "over-threshold flushes immediately")
    }

    static func voicePromptOpenPolicy() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        expect(
            AIConversationOpenPolicy.decide(
                opensTo: .recent, newAfter: .tenMinutes,
                lastActiveAt: now.addingTimeInterval(-60), now: now) == .resume,
            "voice into recent chat resumes within window")
        expect(
            AIConversationOpenPolicy.decide(
                opensTo: .recent, newAfter: .twoMinutes,
                lastActiveAt: now.addingTimeInterval(-180), now: now) == .startNew,
            "voice into stale chat starts new per policy")
        expect(
            AIConversationOpenPolicy.decide(
                opensTo: .newConversation, newAfter: .never,
                lastActiveAt: now, now: now) == .startNew,
            "opensTo newConversation always starts new")
        expect(
            VoiceCommandRouter.route(
                transcript: "Open Safari and find Kubernetes", apps: [])
                == .automation("Open Safari and find Kubernetes"),
            "automation stays explicit compound outcome (Quick AI path, not agent runtime)")
    }
}
