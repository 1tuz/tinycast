# VoiceCast

<p align="center">
  <img src="docs/voicecast-logo.svg" alt="VoiceCast" width="480">
</p>

**One command surface for your Mac. Search, speak, automate, and act.**

VoiceCast is a native macOS command center built on the open-source
[Tinycast](https://github.com/abue-ammar/tinycast) launcher. It keeps a compact,
keyboard-first interface while expanding beyond app launching into voice commands,
local speech recognition, automation, AI actions, and developer utilities.

[Releases](https://github.com/1tuz/tinycast/releases) ·
[Installation](INSTALL.md) · [Speech Runtime](https://github.com/1tuz/Speech-Runtime) ·
[Upstream Tinycast](https://github.com/abue-ammar/tinycast)

## What VoiceCast does

- **Search and launch:** apps, files, folders, settings, shortcuts, and commands from one palette.
- **Control by voice:** push-to-talk, Voice Ask, command aliases, and local intent matching for
  system actions such as screenshots, Focus, screen recording, and clipboard translation.
- **Use local transcription:** connect to the independent
  [Speech Runtime](https://github.com/1tuz/Speech-Runtime) service for speech-to-text.
  Speech Runtime manages the models; VoiceCast is the command and interaction client.
- **Automate:** quicklinks, snippets, shell commands, hotkeys, Apple Shortcuts,
  workflows, and window management.
- **Work with AI:** Quick AI, text actions, chat, and configurable providers.
  AI features are optional and are not the local transcription engine.
- **Extend:** run compatible Raycast extensions with native SwiftUI rendering.
- **Stay native:** Swift 6, SwiftUI and AppKit, with no Electron. macOS 26 or later.

Features inherited from Tinycast also include clipboard history, calculator, calendar tools,
notes, emoji, developer utilities, import/export, and searchable command history.
Some commands require macOS permissions or external software; the Speech Runtime service
must be running for its voice-to-text integration.

## Why this fork exists

| | Tinycast (upstream) | VoiceCast (this fork) |
|---|---|---|
| Primary focus | Small native launcher | Universal command surface, including voice |
| Speech | Upstream speech features | Separate, local **Speech Runtime** integration |
| Voice actions | Upstream behavior | Command routing, aliases, and system intents |
| Updates | Upstream releases | Releases and updates from `1tuz/tinycast` |
| Source | [`abue-ammar/tinycast`](https://github.com/abue-ammar/tinycast) | [`1tuz/tinycast`](https://github.com/1tuz/tinycast) |

This is an independent fork, not a rebranding of the upstream project.
The original authors' credit and the AGPL-3.0 license are retained.
The fork periodically incorporates upstream changes through the `.1tuz/` patch queue.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | /bin/bash
```

Alternatively, download the `VoiceCast-<version>.dmg` attached to a
[GitHub Release](https://github.com/1tuz/tinycast/releases).
See [INSTALL.md](INSTALL.md) for details and migration from Tinycast.

Releases are signed with a **Developer ID Application** certificate (team `J656U8XZ93`) and
**notarized by Apple**, so a downloaded release passes Gatekeeper on first launch — no warning,
no confirmation step. The installer verifies the Developer ID chain, the stapled notarization
ticket and `spctl` acceptance before installing; a published release is never stripped and
Gatekeeper is never disabled. Point the same installer at a local self-signed DMG and it warns,
then clears the quarantine flag on the copy it installs, because such a build can never pass
Gatekeeper at all.

## Build from source

The repository keeps the `Tinycast.xcodeproj` project and `Tinycast` scheme internally
for upstream compatibility. Xcode 26/27 is needed to build locally. Development uses a
persistent local signing identity; see [docs/signing.md](docs/signing.md).

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  -derivedDataPath build/DerivedData build
```

Release distribution — the CI signing secrets and runbook — is described in
[docs/voicecast-distribution.md](docs/voicecast-distribution.md).

## Compatibility

The app intentionally retains bundle ID `com.tinycast.app`, existing preference locations,
backup format, and `tinycast://` links during the transition. This avoids silently losing
settings and allows existing installations to keep updating. The updater's `BundleSignature`
check accepts the pinned Developer ID requirement (team `J656U8XZ93`), and the last pre-switch
release already carries that same check, so an old Tinycast updates into VoiceCast in place; the
leaf branch below it keeps locally signed builds updatable. The user-facing app and release
artifact names are **VoiceCast**, and `Scripts/install.sh` renames an existing
`Tinycast.app` to `VoiceCast.app`.

## License and attribution

VoiceCast is distributed under [AGPL-3.0](LICENSE). It is based on
[Tinycast by abue-ammar and contributors](https://github.com/abue-ammar/tinycast).
Third-party notices remain in [NOTICE.md](NOTICE.md).
