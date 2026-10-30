# Tinycast

**A tiny, fully native macOS launcher. One hotkey, everything you reach for all day, under 100 MB of
RAM.**

<p align="center">
  <a href="https://github.com/1tuz/tinycast/releases/latest">
    <img alt="Latest release"
         src="https://img.shields.io/github/v/release/1tuz/tinycast?sort=semver&style=flat&label=release&color=1F6FEB"></a>
  <img alt="Swift 6.0"
       src="https://img.shields.io/badge/Swift-6.0-F05138?style=flat&logo=swift&logoColor=white">
  <img alt="macOS 26 or later"
       src="https://img.shields.io/badge/macOS-26%2B-000000?style=flat&logo=apple&logoColor=white">
  <a href="LICENSE">
    <img alt="License: AGPL-3.0"
         src="https://img.shields.io/badge/License-AGPL--3.0-3DA639?style=flat"></a>
  <a href="https://discord.gg/v2Eeb4QQy3">
    <img alt="Join the Tinycast Discord"
         src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat&logo=discord&logoColor=white"></a>
</p>

SwiftUI and AppKit, **zero third-party dependencies**, no Electron and no telemetry. It also **runs
real Raycast extensions**, rendered as native SwiftUI. Free, open source, and staying that way.

For anything private, email [iabueammar@gmail.com](mailto:iabueammar@gmail.com).

<p align="center">
  <img src="docs/screenshot.png" alt="Tinycast command palette" width="720">
</p>

## Features

- **App launcher** — fuzzy-search and launch anything, pin favorites, see what's running, quit an app
  or every app at once.
- **Global hotkey** — one shortcut summons the palette from anywhere.
- **Compact launcher shortcuts** — Clipboard History, Emoji & Symbols, Search Files and Search
  Quicklinks sit beside the search field. Choose up to four in Settings → General → Appearance →
  Compact Shortcuts.
- **Per-app hotkeys** — bind a key to an app; press it to toggle (focus/hide).
- **Search Files** — open files and folders from the folders you choose, through Spotlight, with no
  index of our own.
- **Dictionary** — look a word up with the Define Word command, or define whatever you typed from the
  launcher's fallbacks, read from the Mac's own dictionaries.
- **Clipboard history** — text and images, searchable, pasted back into the app you were using.
- **Calculator** — do math, unit, live currency and crypto conversions inline, right in the palette.
- **Quicklinks** — turn a URL, search, file or deeplink into a command, with placeholders for typed
  input, the clipboard or the date.
- **Apple Shortcuts** — search and run the shortcuts you built in the Shortcuts app, with aliases and
  global hotkeys.
- **Snippets** — reusable Markdown templates with dynamic placeholders, arguments, nested references
  and optional keyword expansion.
- **Custom commands** — run named shell commands through fuzzy search or their own global hotkeys.
- **Window management** — 34 Rectangle-style actions: halves, quarters, thirds, sizing, nudging,
  display moves, fullscreen and Spaces.
- **System actions** — lock, sleep, restart, empty trash, toggle appearance, Bluetooth, mute, hidden
  files, and more.
- **Calendar and meetings** — your next meeting on the empty palette and in the menu bar, one key to
  join it, or let it join itself.
- **Notes** — an unlimited collection of plain Markdown files in one floating editor, searchable from
  the palette and rendered as you write.
- **Emoji picker** — a searchable emoji grid, one keystroke away.
- **AI chat** — use your own key or an installed AI account: ask Quick AI from the palette, or keep
  longer conversations in the AI Chat window, with a searchable, pinnable history. Off out of the box,
  like every AI feature.
- **Quick Actions** — fix grammar, rewrite, translate or summarize the selected text in any app.
- **Command history and developer tools** — reopen recent launcher commands, or run 15 local utilities
  for JSON, encoding, hashes, UUIDs and text conversion.
- **Smart launcher** — recent and context-aware apps, plus project workspaces.
- **Saved file searches** — keep reusable folders and choose how matching files open.
- **Calendar tools** — create events, block focus time and manage meeting notes.
- **Visual clipboard history** — find copied images with OCR text and local annotations.
- **Local workflows** — run hotkey, schedule, clipboard or folder triggers. Workflows start off.
- **AI response snippets** — keep completed answers locally for 24 hours, up to 100 items.
- **Raycast extensions** — run the ones you already have natively, rendered as SwiftUI.
- **Backup and import** — export your settings to a file, or import your setup from Raycast.

## Install

Run this in Terminal. It builds the fork source with Xcode 26 or 27 and replaces the existing app in `/Applications` or installs it in `~/Applications`:

```sh
curl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | /bin/bash
```

See [INSTALL.md](INSTALL.md) for the signing identity requirement and options.

## Building from source

See [INSTALL.md](INSTALL.md) for the local build and install command. **[docs/](docs/README.md)**
indexes architecture, engineering standards, the design system and feature guides.

## License

[AGPL-3.0](LICENSE)
