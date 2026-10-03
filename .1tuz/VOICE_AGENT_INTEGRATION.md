# Voice Agent integration notes

Performance patch deltas land on top of `feature/voice-ask`, which already owns
microphone capture, Codex Realtime transcription, `VoiceAskCoordinator` and Voice Pill.
Hyper PTT uses the existing hold machine (`HyperVoiceAskHold`) — no second event tap.

## 1. AppCore wiring

Already wired after `hyperKeyTap.start(settings: settings)`:

```swift
hyperKeyTap.onVoiceAskHoldStart = { [weak self] in
    self?.voiceAskCoordinator.beginHyperHoldPTT()
}
hyperKeyTap.onVoiceAskHoldStop = { [weak self] in
    self?.voiceAskCoordinator.endHyperHoldPTT()
}
hyperKeyTap.onVoiceAskHoldCancel = { [weak self] in
    self?.voiceAskCoordinator.cancelHyperHoldPTT()
}
```

Gesture resolution:

- Hyper released before tap window: existing Quick Press behavior.
- Hyper + another key: ordinary Hyper shortcut; Voice Ask never starts.
- Hyper held past tap window with no other key: start PTT.
- PTT + another key: cancel Voice Ask and continue as an ordinary Hyper combo.
- Hyper released while PTT is active: stop capture and finalize transcription.
- Wake / session switch: cancel hold, clear Caps Lock latch, re-enable tap.

## 2. Transcript -> assistant

Final transcript enters Quick AI. No separate agent window.

1. Put final text into the existing Quick AI query/draft.
2. In Voice Agent mode, send immediately through existing Quick AI chat.
3. In ordinary dictation mode, fill the draft (auto-send off).

Codex path reuses `ChatGPTSubscriptionManager` / `CodexAppServerClient`.

## 3. Performance constraints

- Microphone capture exists only for an active Voice Ask session.
- Realtime transcription session closes immediately after stop/cancel.
- No polling loop for Hyper or Voice Ask.
- No second app-server/ACP process while Codex app-server can serve the route.
- Do not pre-load AI Chat solely for Voice Ask.
- Keep Voice Pill non-activating; hide when the session ends.
- Codex helper idle shutdown is 180 seconds (was 600).
