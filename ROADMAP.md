# Tinycast roadmap

Status after the local fork implementation.

## Completed

1. **Command History** — reopen recent launcher commands; query text and arguments are not stored.
2. **Ephemeral AI Snippets** — save completed AI replies locally with a 24-hour lifetime and a 100-item cap.
3. **Developer Utilities** — 15 local actions for JSON, encoding, hashes, UUIDs, timestamps and text conversion.
4. **Smart Launcher Categories** — recent and context-aware apps, plus project workspaces.
5. **Enhanced File Search** — saved folders and Open With choices.
6. **Calendar Integration+** — quick event creation, Focus Time and meeting notes.
7. **Window Management+** — saved layouts, room switching and automatic layout application.
8. **Visual Clipboard History** — OCR search for copied images and local annotations.
9. **Workflow Automation** — local hotkey, schedule, clipboard and folder triggers. New workflows are off by default.

## Excluded by request

10. **Cross-Device Sync** — excluded. Tinycast stays a local macOS app. No iCloud or other sync backend is included.

## Existing behavior retained

- Compact mode stays enabled when already enabled. Its default shortcut row has Clipboard History,
  Emoji & Symbols, Search Files and Search Quicklinks. Configure it in **Settings → General →
  Appearance → Compact Shortcuts**.
- New installs receive the requested hotkey defaults. Existing saved hotkeys are left intact.
- Voice input and dictation were removed. VoiceOver and the separate microphone mute action remain.
- The fork updater checks `1tuz/tinycast`. The local one-line installer builds and signs the app with
  the persistent identity already used by the installed copy.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | /bin/bash
```
