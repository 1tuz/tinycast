# .1tuz

Everything that makes this fork differ from [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast).
`main` is regenerated as *upstream main + these patches* — do not hand-edit `main` outside this folder.

| File | What it does |
| --- | --- |
| `patches/0001-voice-ask-core.patch` | Voice Ask core: coordinator, settings, AppCore wiring, docs, harness |
| `patches/0002-voice-ask-hyper-ptt.patch` | Hyper hold → Voice Ask PTT models + hotkey wiring |
| `patches/0003-voice-ask-ui.patch` | Voice Pill, shared mic button, Quick AI / launcher header |
| `patches/0004-voice-ask-permissions.patch` | Microphone TCC strings, entitlements, Permissions UI |
| `patches/0005-codex-realtime.patch` | Codex realtime transcription + microphone capture |
| `patches/0006-codex-lifecycle-performance.patch` | Codex idle 180s, probe idle re-arm, audio batching, `sendVoicePrompt` |
| `patches/0007-hyper-stability.patch` | Hyper `keyState` watchdog, Caps Lock wake/terminate |
| `patches/0008-fork-updater.patch` | In-app updater + About GitHub → `1tuz/tinycast` |
| `patches/0009-disable-support-reminders.patch` | No automatic Support reminder pump |
| `patches/0010-mic-isolation-early-ptt.patch` | Mic tap off MainActor; early PCM + pending Hyper-stop during Codex connect |
| `patches/0011-transcript-settle-pill-stable.patch` | Wait for transcript/done after stop; stop pill setFrame flicker |
| `patches/0012-remove-website-link.patch` | Removes the upstream Website link from About |
| `patches/0013-curl-installer.patch` | Adds the one-line local installer and guide |
| `patches/0014-no-homebrew-release-notes.patch` | Removes Homebrew instructions from generated release notes |
| `apply.sh` | Applies patches, removes website publishing workflows, rewrites release links, regenerates XcodeGen project with a checksum-pinned binary |
| `gate.sh` | Fast validation: apply already done; Release smoke build + Voice Ask / Hyper / updater-focused harnesses |
| `UPSTREAM` | Upstream commit SHA `main` was last built from |
| `VOICE_AGENT_INTEGRATION.md` | Voice Agent wiring notes for this fork |

## Automation

- **`fork-sync.yml`** — once daily (and `workflow_dispatch`) checks upstream `main`. On a new commit it rebuilds the source tree from upstream plus `.1tuz/patches`, preserves this fork's workflow files, runs `gate.sh`, and fast-forward pushes `main`. On failure nothing is pushed.
- GitHub Actions uses its built-in `GITHUB_TOKEN`; no extra push token is needed. Website publishing workflows are removed from the fork.
- `INSTALL.md` documents the one-line source installer. It needs Xcode 26 and a persistent code-signing identity. GitHub Releases must use that same identity for in-app updates.
- `release.yml` stays manual (`workflow_dispatch` only). Release signing still needs `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` (stable identity — do not rotate casually).
