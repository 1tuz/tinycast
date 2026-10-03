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
| `apply.sh` | Applies patches in order (`git apply --3way`), rewrites leftover releases links, regenerates XcodeGen project for new sources |
| `gate.sh` | Fast validation: apply already done; Release smoke build + Voice Ask / Hyper / updater-focused harnesses |
| `UPSTREAM` | Upstream commit SHA `main` was last built from |
| `VOICE_AGENT_INTEGRATION.md` | Voice Agent wiring notes for this fork |

## Automation

- **`fork-sync.yml`** — once daily (and `workflow_dispatch`) checks upstream `main`. On a new commit it rebuilds `main` = upstream + patches on macOS, runs `gate.sh`, and `--force-with-lease` pushes `main`. On failure nothing is pushed.
- Upstream `release.yml` stays **manual** (`workflow_dispatch` only). Homebrew tap / website / Discord steps are skipped on this fork.

Secrets: `SIGNING_P12_BASE64`, `SIGNING_P12_PASSWORD` (stable identity — do not rotate casually), and `FORK_PUSH_TOKEN` (Contents + Workflows write) for sync pushes that touch workflows.
