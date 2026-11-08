# Voice Ask

Voice Ask turns speech into launcher input: hold the hotkey, talk, and the phrase either executes a
voice command or lands in Quick AI. Capture is owned by Tinycast, transcription by the local Speech
Runtime daemon, and command matching by a pure Foundation parser that never sees audio.

## Invariants

- **The parser is pure Foundation.** `SpeechVoiceCommandParser.swift` imports nothing but Foundation,
  holds no AppKit or SwiftUI type, and never touches audio: its input is text the transcriber already
  produced. This is what `voice-command-test` and `voice-ai-trigger-test` compile standalone in the
  harness — `run-tests.sh` feeds the parser plus `AIVoiceTrigger.swift` and the romanization sources
  to `swiftc`, so an `import AppKit` creeping in breaks the build, not a test case.
- **AI trigger words are user configuration, not grammar.** `AIVoiceTriggerStore` persists the list
  as plain UserDefaults JSON under `speechVoice.aiTriggers`, readable without an AppSettings
  dependency; the parser compares against `normalizedTriggers()`, longest first so "посмотри в" wins
  over "посмотри" when both are configured. A missing or empty list falls back to the built-in
  "посмотри", so a fresh install understands the phrase out of the box.
- **Fuzzy matching is bounded and never guesses.** Target names resolve through a bounded
  optimal-string-alignment distance (insertions, deletions, substitutions, adjacent swaps) with an
  error budget that grows with name length — 0 under 4 characters, 1 up to 6, 2 up to 12, 3 beyond.
  A fuzzy winner runs only when the next candidate is distinctly worse; otherwise the resolution is
  `.ambiguous` and a catalog window asks the reader to pick. Two equally plausible names never
  execute one of them. Different plausible actions from typo correction answer "unknown", not an
  action. Only full names and aliases match — never a substring of an installed app's name.
- **Audio capture is a client of Speech Runtime, not a model host.** The API is local and fixed; the
  client never starts or terminates the daemon, and the user controls model downloads in Speech
  Runtime.app. Recognition and command matching are entirely local — nothing is sent off this Mac.
- **The action verb may carry one ASR error; qualifiers must remain exact.** `fuzzyPrefix` corrects
  a single edit in the leading verb of a named rule, but the qualifiers after it ("ссылку",
  "приложение") must match word for word, so a fuzzy verb cannot silently change what kind of object
  the command addresses. Free dictation and ordinary questions never accidentally become executable
  actions: correction applies only to explicit, unambiguous commands.
- **Tinycast owns the microphone, not the reverse.** `SpeechVoiceMicrophone` is `@MainActor` while
  `SpeechVoiceAudioEngine` is a plain object whose real-time tap runs on the audio thread and hops
  to the main actor via a `Task`; the engine callback never touches UI state. An unplugging headset
  reports `onDeviceLost` and the session ends cleanly with the audio it already captured.
- **The catalog window is owned by AppCore.** `AppCore.voiceCommandCatalogWindow` owns one reusable
  `NSWindow`; both "покажи голосовые команды" and the disambiguation choice list present in it,
  swapping `contentView` and title. `isReleasedWhenClosed` is false, so dismissing keeps the shell.
- **The last voice target enables anaphora.** `SpeechVoiceCommandHistory` stores the application a
  command resolved to, so "закрой его" quits it — but only named application commands qualify;
  system and window verbs have no referent.

## Architecture

The pipeline is one direction, with no branch that skips a stage:

```text
SpeechRuntimeVoiceAsk → SpeechVoiceMicrophone → SpeechRuntimeTranscriber
    → SpeechVoiceCommandParser → SpeechVoiceCommandRouter
```

`SpeechRuntimeVoiceAsk` is the `@MainActor @Observable` session owner created by `AppCore`. It owns
the microphone, the transcriber, and the floating listening pill, plus a generation counter that
makes every async callback a no-op once it is superseded. Capture starts before the model connects:
while the transcriber warms up, up to 30 seconds of early audio (1.92 MiB at mono 16 kHz f32) is
buffered, so a short Hyper hold never loses its first words to a cold ANE. Stopping is a 280 ms
release after the tap's last frame, not an immediate cut.

The session has four triggers. A short hotkey tap toggles; holding it past 250 ms is push-to-talk,
and releasing finishes. A Hyper key held 250 ms starts a hold session that finishes on release; a
cancelled Hyper hold cancels the session outright. From the palette, `toggleFromPalette` clears the
query (the transcript live-feeds it as recognition lands) and restores the draft afterwards — before
dispatching any action that may close the palette.

On finish, the transcript goes to `SpeechVoiceCommandRouter.route(_:core:)` (if
`speechVoice.commandsEnabled` is not explicitly off — absent means on). The router resolves the
phrase against the app's live targets: `.action` executes the allowlisted intent and records the
target; `.unknown` shows the message and falls back to composing the raw prompt in Quick AI;
`.ambiguous` opens the choice window; `.notCommand` returns false and the phrase follows the
ordinary Quick AI delivery policy — `speechVoice.autoSend` sends it, otherwise it is composed for
review. An `aiPrompt` routes the rest of the phrase to Quick AI pinned to the trigger's model, when
the trigger entry chose one.

## Key files

- `Tinycast/Features/VoiceAsk/SpeechRuntimeVoiceAsk.swift` — session owner: phases, early audio,
  finish policy, pill, generation guards.
- `Tinycast/Features/VoiceAsk/SpeechVoiceMicrophone.swift` — mic capture, permission, device-loss
  detection, 16 kHz mono conversion in the audio tap.
- `Tinycast/Features/VoiceAsk/SpeechVoiceCommandParser.swift` — pure Foundation command grammar and
  bounded fuzzy matching.
- `Tinycast/Features/VoiceAsk/SpeechVoiceCommandRouter.swift` — MainActor execution of resolved
  intents and the last-target history.
- `Tinycast/Features/VoiceAsk/SpeechVoiceCommandCatalog.swift` — the catalog window and its views.
- `Tinycast/Features/VoiceAsk/AIVoiceTrigger.swift` — trigger model and `AIVoiceTriggerStore`.

## Adding commands

Built-in commands are **data, declared once**. `builtinPatterns` is a list
of `Pattern`s, each carrying a section, a catalog title, the exact phrases, an `Intent`, and an
optional `feature` key; the same declaration drives both parsing and the in-app catalog, so a phrase
added there appears in the catalog window without further work. Volume, brightness, and the
`найди …` search families are ad-hoc prefix loops in `parse` rather than patterns, because their
argument is the rest of the phrase.

A named rule goes in `namedRules`: a prefix, the `Target.Kind`s it may address, and `closes: true`
for a quit verb. Rules are ordered most-specific-first — "запусти apple shortcut" must win before
the generic "запусти" — and the parser walks them in that order, so a new specific prefix belongs
above the generic ones, not below. `catalogPhrases(for:)` generates example phrases from the same
verb definitions `parse` accepts, so the catalog cannot drift from the grammar.

An AI trigger is configuration, not a code change: the user adds it in settings, `AIVoiceTriggerStore`
persists it, and the parser picks it up on the next parse. If a built-in trigger word ever changes,
it changes in `AIVoiceTriggerStore.builtin`, not in the parser.

## Matching pipeline

`parse(_:targets:)` runs a fixed order:

1. **Normalize.** Lower-case, strip punctuation, fold `ё` to `е`, collapse spaces. Spelled-out
   Russian numerals fold back to digits ("двадцать пять" → 25, including ASR-glued tokens), and one
   infinitive maps to one imperative verb, so prefix lengths stay intact. Leading hesitations
   ("эм", "ну") and trailing politeness ("пожалуйста", "спасибо") are dropped as ASR noise. A wake
   word — "тини каст", "тайни каст", "tinycast" — is stripped the same way.
2. **AI triggers.** A trigger word owns the whole rest of the phrase and runs *before* any command
   grammar could reinterpret the question as an action.
3. **Exact fixed patterns.** A normalized phrase equal to a declared phrase resolves immediately.
4. **Prefix families.** Volume and brightness parse a 0–100 value; `найди файл` / `найди заметку` /
   generic `найди` capture the rest as a search query, keeping inner punctuation
   ("docker-compose.yml") but trimming sentence-ending marks ASR adds.
5. **Named rules.** Each rule prefix, in order, resolves its remainder against the live targets.
6. **Fuzzy fallback.** One-typo correction over `builtinPatterns` (single edit, words ≥ 4 characters,
   at most one error, ambiguous matches rejected), then one-verb-error correction of the prefix
   families and named rules. Anything else is `.notCommand`.

Name resolution (`resolveName`) compares the romanized key — Cyrillic folded through
`ScriptRomanization.latin` so a Russian ASR transcript matches a Latin app name like "Telegram"
without per-app aliases — with an exact name or alias always winning over any fuzzy candidate.

## Testing

The parser's harness constraint is the contract: `run-tests.sh` compiles
`voice-command-test` and `voice-ai-trigger-test` from
`Tinycast/Features/VoiceAsk/SpeechVoiceCommandParser.swift`,
`Tinycast/Features/VoiceAsk/AIVoiceTrigger.swift`, and the romanization and AI model sources with
plain `swiftc -swift-version 6` — no app target, no AppKit. Keep it that way: the moment the parser
imports something outside Foundation, the harness fails to compile and says so before any test runs.

The parser tests are `expect(phrase, resolution)` table entries in `Tests/voice-command-test.swift`
covering the cases that matter: exact phrases, normalized infinitives and numerals, one-edit names
("телеграмм", "тетеграм"), cross-script Latin matching with no hand-written alias, distinct-winner
ambiguity rejection, qualifier exactness, and `найди …` queries. New grammar belongs beside them:
a new pattern, rule, or trigger gets its `expect` line in the same file, and a new behaviour of the
normalize stage gets both a positive and a negative case — the pipeline guards are what the invariants
above describe, so the table should pin them.
`voice-input-test` compiles `SpeechVoiceMicrophone.swift` with an injectable `inputAvailable`, so a
Mac with no input device is simulated without touching hardware; `voice-alias-test` guards the
AliasStore integration the catalog's edited aliases reuse.
