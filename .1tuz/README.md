# .1tuz

Everything that makes this fork differ from [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast).
`main` uses the upstream `main` tree plus these patches. Each sync commit keeps the previous fork `main` as its first parent, so publishing is a normal fast-forward push.

| File | What it does |
| --- | --- |
| `patches/0008-fork-updater.patch` | In-app updater and About link to `1tuz/tinycast` |
| `patches/0009-disable-support-reminders.patch` | Disables automatic Support reminders |
| `patches/0012-remove-website-link.patch` | Removes the upstream Website link from About |
| `patches/0013-curl-installer.patch` | Adds the one-line local installer and guide |
| `patches/0014-release-notes-install-guide.patch` | Uses the local install guide in generated release notes |
| `patches/0016-fork-readme-install-guide.patch` | Replaces upstream website and package-manager install text in README |
| `patches/0017-roadmap-features.patch` | Carries local roadmap features and removes upstream Dictation/microphone capture |
| `patches/0018-speech-runtime-voice.patch` | Restores Voice Ask with local Speech Runtime transcriptions, Hyper PTT and Quick AI delivery |
| `patches/0019-voice-commands.patch` | Voice control, typo-tolerant matching, searchable command catalog, multiple aliases and conservative ASR typo correction |
| `patches/0021-voicecast-rebrand.patch` | The VoiceCast identity in source, tests, docs and build metadata, plus the Developer ID / notarized release posture |
| `branding/` | The VoiceCast overlay: README, INSTALL, dock + menu bar icons, logo, distribution guidance, `install.sh`, `build-dmg.sh` and `release-notes.sh`; `Scripts/verify-release.sh` ships in the patch. `branding/apply.sh` reapplies the overlay idempotently after every patch queue run |
| `apply.sh` | Applies patches, reapplies the branding overlay, removes website source and publishing workflows, rewrites release links, regenerates the XcodeGen project |
| `gate.sh` | Requires the local Voice Ask implementation, rejects obsolete Codex realtime audio, guards the VoiceCast branding, requires the Developer ID + notarization release pipeline, forbids a quarantine bypass anywhere in the release path, checks overlay/canonical drift, and runs a Release build and focused harnesses |
| `UPSTREAM` | Upstream commit SHA used for the last rebuild |

## Automation

- `fork-sync.yml` checks upstream `main` daily and on manual dispatch. It rebuilds the fork from upstream plus `.1tuz/patches`, preserves this fork's workflows, runs `gate.sh`, then pushes `main` as a fast-forward merge of the previous fork tree and upstream. Failed gates do not publish a new tree.
- GitHub Actions uses its built-in `GITHUB_TOKEN`; no extra push token is needed. The fork does not contain the website source or publishing workflow.
- `INSTALL.md` documents the one-line installer for the latest release. It needs no Xcode, requires no root, and only clears quarantine on a copy it installs from a local self-signed DMG (a published release is notarized and needs nothing). Public GitHub Releases are signed with an Apple **Developer ID Application** certificate for team `J656U8XZ93`, notarized and stapled; the in-app updater trusts that team through `BundleSignature`, which the last pre-switch release already carries; the leaf fallback keeps locally signed builds updatable.
- `release.yml` is manual. It builds with the hardened runtime and a secure timestamp, notarizes the app and the DMG through `notarytool`, requires `Accepted`, staples both, gates publishing on `codesign`/`spctl`/`stapler` verification and on a quarantined clean-machine install plus an in-place upgrade from the previous release. Six repository secrets are required; see `docs/signing.md`. Local builds and `build-dmg.sh` stay self-signed with `Tinycast Self-Signed` and are not distributable.
  The Localizable.xcstrings full UI translation rebrand is tracked separately and is outside this overlay: `branding/apply.sh` covers the app name, icons, README/INSTALL, installer and release scripts, not every translated string.
