# Focus sessions

A local, deliberately soft concentration timer: profiles hide configured applications and redirect
blocked tabs in supported browsers, with an optional VoiceCast Workflow or Apple Shortcut at start
and end. It runs without the Speech Runtime, a microphone, an AI model, a Python process or elevated
privileges.

## Invariants

- **The model is pure Foundation.** `Features/Focus/Model/FocusProfile.swift` imports only
  Foundation and holds every value type — profile, session, saved state, domain matching. The
  `focus-profile-test` harness compiles that file alone, so an AppKit or SwiftUI import breaks the
  build rather than a test case.
- **Blocking is soft and reversible.** Applications are hidden with `NSRunningApplication.hide()`,
  never force-quit, so unsaved work survives. A blocked browser tab is replaced with `about:blank`;
  background requests, private windows, Firefox/Zen and anything outside the four supported browsers
  are explicitly out of scope. No `/etc/hosts`, firewall or Network Extension is touched.
- **System surfaces are never blocked.** `protectedBundleIDs` covers Finder, Dock, loginwindow and
  both VoiceCast bundle IDs; `addApplication`, `blockApplication` and `blockIfNeeded` all enforce it.
- **The session is owned by one file.** `Application Support/<bundle id>/focus-sessions.json` is the
  only state; the coordinator, owned lazily by `AppCore`, is the only writer, and observers installed
  in `startMonitoring()` are removed in `prepareForTermination()`. A relaunch restores the session and
  closes an already expired one at the next refresh.
- **Pause freezes the budget.** `pausedSeconds` stores the remaining time and `resumeAt` an optional
  automatic break end; `refresh()` resumes from either a timer tick, a wake notification or the next
  launch. Enforcement stops while paused.
- **The voice grammar is deterministic.** `parseFocus` matches fixed phrase lists and explicit
  prefixes — no edit distance, so general dictation still falls through to Quick AI. Durations are
  validated in the grammar and again in the coordinator (5–240 minutes to start, 1–60 for a pause or
  a website exception).
- **AppleScript never interpolates untrusted text.** Domains are normalized to a host-name-only
  grammar before storage, and the tab URL is quoted and backslash-escaped before the compare-and-set
  script. `osascript` runs on a detached utility task, so the palette and the voice loop never wait on
  an Apple Event; the result is applied only if the session is still running and unpaused.

## Settings and UI

Open **Settings → Focus**. Create a profile, set a duration (5–240 minutes), choose apps and domains,
and optionally select existing VoiceCast Workflows and Apple Shortcuts for start/finish actions.
Shortcuts can open an IDE, arrange windows, or change macOS's Do Not Disturb mode. The session timer
is displayed in a small nonactivating, draggable Liquid Glass panel. Start, pause and finish are also
in the menu bar.

## Voice commands

Existing **Voice Ask → Run VoiceCast commands** must be enabled. Examples:

- `Начни фокус на 45 минут`
- `Запусти профиль Работа на час`
- `Пауза фокуса на 5 минут` (automatically resumes after the break)
- `Продолжи фокус`, `Заверши фокус`, `Сколько осталось фокуса`
- `Заблокируй приложение Telegram` (only for the active session)
- `Заблокируй сайт youtube.com` (only for the active session)
- `Разреши сайт youtube.com на 5 минут`

The existing `Включи фокус` system action still toggles **macOS Do Not Disturb** and is deliberately
distinct from starting a timed VoiceCast Focus session.

## Scope and limitations

- **Apps**: `NSWorkspace.didActivateApplicationNotification` hides configured applications when they
  activate. They are **not force-quit**, so unsaved work is preserved. This is a soft restriction, not
  a security or parental-control mechanism.
- **Websites**: while Safari, Google Chrome, Brave or Edge is frontmost, VoiceCast checks the active
  tab every ~2 seconds using AppleScript and redirects a blocked URL to `about:blank`. macOS might
  request Automation consent. Background tabs, private windows, Firefox/Zen and network requests
  outside those tabs are **not** blocked. Existing URLs are not automatically restored at session
  end.
- **Network-wide filtering** would require a separately signed and provisioned Network Extension
  (and user approval); it is **not** included.
- **System Focus** is not modified by undocumented macOS file writes. If needed, use a configured
  Apple Shortcut as the profile's start/end action.

## Build and verification

The feature ships in the fork's normal tree and patch queue, so no separate patch needs applying:

```bash
xcodegen generate
./Scripts/run-tests.sh focus-profile-test
./Scripts/run-tests.sh voice-command-test
```

`project.yml` discovers the entire `Tinycast/` source tree, so running XcodeGen is required after
adding the `Focus` sources. `.1tuz/patches/0022-focus-sessions.patch` carries the feature through the
daily upstream sync, and `.1tuz/gate.sh` runs `focus-profile-test` and requires the source layout.
