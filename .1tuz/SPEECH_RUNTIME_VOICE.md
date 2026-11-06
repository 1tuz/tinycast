# Voice Ask: local Speech Runtime integration

Target: `1tuz/tinycast` main, based on `10a7693d`. This patch is also stored in
`.1tuz/patches/0018-speech-runtime-voice.patch` so fork-sync reapplies it after
`0017-roadmap-features.patch` removes upstream Dictation.

## Requirements

- Install and start the **separate** `1tuz/Speech-Runtime` macOS app. The daemon
  must be listening at `127.0.0.1:8477` and must have created its bearer token.
  As of 2026-11-06 the runtime repo had no published GitHub release; build the
  app with `bash runtime/macos-app/scripts/build-app.sh` in that repository.
- Enable **AI** and **Enable local Voice Ask** in Tinycast Settings > AI.
- The runtime app currently provisions `parakeet-ultra`; `gigaam` works only if
  independently declared and installed in the Speech Runtime configuration.
- Grant microphone access to **Tinycast** when macOS asks. Configure a shortcut
  in AI settings or enable the Hyper Key in Tinycast settings. An unused Hyper
  hold of at least 250 ms starts PTT; release finishes, another key cancels.

## User flow

Mic in the launcher/Quick AI header, or global shortcut, or Hyper-alone PTT
-> 16 kHz mono float32 PCM -> Speech Runtime VAD -> `final` event(s)
-> Quick AI composer or automatic send, depending on the settings switch.
Only completed utterances are available; Speech Runtime reports
`interim_results=false`. No duplicate ASR model/worker starts inside Tinycast.
The daemon is **never stopped or installed by Tinycast**. Cancelling only
removes the client's own stream.

## Apply & build

    git switch main
    git apply --check /path/to/tinycast-speech-runtime-voice.patch
    git apply /path/to/tinycast-speech-runtime-voice.patch
    # main's PBXProj is already updated in the patch; optional to normalize:
    xcodegen generate --quiet
    xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release build

On the next fork-sync, `.1tuz/apply.sh` reapplies patch 0018 and automatically
regenerates the project. Run `.1tuz/gate.sh <upstream-sha>` on macOS. Existing
hyper-key regression tests still use the unchanged HyperKeyEngine effect set.

This deliverable has been Swift-syntax-parsed on Linux but not compiled or run
on macOS; do not treat it as macOS/ANE verification.
