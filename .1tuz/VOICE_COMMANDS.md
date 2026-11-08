# Tinycast: voice commands (Speech Runtime)

Settings > AI > Voice Ask: enable **Enable local Voice Ask** and
**Run Tinycast voice commands**. Press **Показать все голосовые команды** to open a searchable,
live catalog with all built-in phrases and the currently indexed apps, shortcuts,
workflows, quicklinks, window layouts, and custom commands. Saying
`Покажи голосовые команды` opens the same window.

Hold an unused Hyper key for 250 ms, speak, and release. Speech Runtime transcribes
16-kHz mono audio locally; Tinycast handles commands without an LLM or cloud audio.

Example commands:

- `Открой Telegram`, `Открой телеграмм`, `Открой тетеграм` => Telegram.app
- `Открой телега` => Telegram, **if** the launcher alias `телега` is assigned
- `Поставь окно справа` => right half of the active screen
- `Перемести окно вправо` => nudge the window right
- `Окно на следующий монитор` => next display
- `Громкость 25 процентов` => set output level
- `Следующий трек` => media action
- `Покажи историю буфера` => clipboard history
- `Найди файл docker-compose.yml` => file search seeded with a query
- `Найди заметку Kubernetes` => notes search seeded with a query
- `Присоединись к следующей встрече` => existing calendar command
- `Запусти сценарий Рабочее окружение` => Apple Shortcut or workflow
- `Выполни команду Очистка кэша` => custom command (requires confirmation)
- `Открой ссылку Документация` => Quicklink (requires confirmation)

## Voice command improvements (0020)

- The voice parser accepts one ASR character error in a multiword built-in phrase
  or in the first word of an explicit action prefix. Qualifiers and objects retain
  strict matching plus bounded Damerau-Levenshtein on the object name.
- Voice aliases accept up to 8 names separated by semicolons in the command catalog;
  they share the existing launcher alias store and its settings-backup data.
- More already implemented system/window commands and launcher actions are exposed
  without adding a transcription engine or changes to Handy.
- An uncertain spoken command does not run an action. The unpushed local
  "посмотри" trigger is deliberately not modified by this patch.

## Matching and safety

The grammar first matches an explicit **action verb** (`открой`, `запусти`, etc.).
Only its **target name** is matched fuzzily. Target names are normalized and
romanized with Tinycast's existing `ScriptRomanization`; they are compared using
bounded optimal-string-alignment Damerau-Levenshtein distance (one edit for
adjacent transpositions). The maximum tolerated edits scale with name length:
0 for 1-3 chars, 1 for 4-6, 2 for 7-12, and 3 for longer strings.

A literal name or alias takes precedence. When two candidates are equally or
nearly plausible, Tinycast opens a window to choose one; no action runs by
accident. No candidate => the user sees a message and an editable Quick AI draft.
Speech that does not match any command grammar follows the original Quick AI
draft/auto-send preference. There is no arbitrary spoken shell execution.

Shutting down macOS, erasing Trash and bulk quitting are not in the voice map.
Custom scripts, user Shortcuts, and Quicklinks require explicit confirmation.
The command catalog has an edit button beside each indexed object. It saves
one nickname per object through the existing launcher AliasStore, which is also
used by normal keyboard search. No separate dictionary or model is necessary.

## Verification

Run the small matcher harness (no model download or long ASR benchmark):

    ./Scripts/run-tests.sh voice-command-test

The implementation lives in `Tinycast/Features/VoiceAsk/`. The fork keeps
changes via `.1tuz/patches/0019-voice-commands.patch`; `apply.sh` regenerates
the Xcode project when files are added on sync.
