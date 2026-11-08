import Foundation

/// Pure command grammar. Audio never reaches this layer: only Speech Runtime text.
/// Matching targets is tolerant of speech-recognition errors; action verbs remain explicit.
enum SpeechVoiceCommandParser {
    struct Target: Equatable, Sendable {
        enum Kind: String, Equatable, Sendable {
            case application, quicklink, shortcut, customCommand, workflow, layout, room
        }
        let kind: Kind
        let id: String
        let name: String
        var aliases: [String] = []
    }

    enum Intent: Equatable, Sendable {
        case window(String)
        case system(String)
        case brightness(Int)
        case volume(Int)
        case builtIn(String, query: String? = nil)
        case target(Target.Kind, String)
        /// Quits the application resolved by name ("закрой телеграм").
        case quitApp(String)
        /// Quits the application the previous command resolved to ("закрой его").
        case quitLastApp
        /// Sends the rest of the phrase to Quick AI ("посмотри как дела").
        case aiPrompt(trigger: String, prompt: String)
    }

    enum Resolution: Equatable, Sendable {
        case notCommand
        case unknown(String)
        case ambiguous([Target])
        case action(Intent)
    }

    struct CatalogItem: Sendable {
        let section: String
        let title: String
        let phrases: [String]
        let feature: String? // Window/notes/file-search availability is assessed in the UI.
        var targetID: String? = nil // Edited aliases reuse Tinycast's existing AliasStore.
    }

    private struct Pattern: Sendable {
        let section: String
        let title: String
        let phrases: [String]
        let intent: Intent
        var feature: String? = nil
    }

    private struct NamedRule: Sendable {
        let prefix: String
        let kinds: Set<Target.Kind>
        /// A close rule quits the resolved application instead of launching it.
        var closes: Bool = false
    }

    // The same declarations drive both parsing and the in-app voice command catalog.
    private static let fixedPatterns: [Pattern] = [
        .init(section: "Окна", title: "На правую половину", phrases: [
            "окно справа", "поставь окно справа", "размести окно справа",
            "окно на правую половину", "помести окно на правую половину",
            "перемести окно на правую половину", "правая половина экрана"
        ], intent: .window("right-half"), feature: "windows"),
        .init(section: "Окна", title: "На левую половину", phrases: [
            "окно слева", "поставь окно слева", "размести окно слева",
            "окно на левую половину", "помести окно на левую половину",
            "перемести окно на левую половину", "левая половина экрана"
        ], intent: .window("left-half"), feature: "windows"),
        .init(section: "Окна", title: "Сдвинуть вправо", phrases: [
            "перемести окно вправо", "сдвинь окно вправо"
        ], intent: .window("move-right"), feature: "windows"),
        .init(section: "Окна", title: "Сдвинуть влево", phrases: [
            "перемести окно влево", "сдвинь окно влево"
        ], intent: .window("move-left"), feature: "windows"),
        .init(section: "Окна", title: "Развернуть окно", phrases: [
            "разверни окно", "максимизируй окно", "увеличь окно на весь экран"
        ], intent: .window("maximize"), feature: "windows"),
        .init(section: "Окна", title: "По центру", phrases: [
            "центрируй окно", "поставь окно по центру", "окно по центру"
        ], intent: .window("center"), feature: "windows"),
        .init(section: "Окна", title: "Восстановить размер", phrases: [
            "верни размер окна", "восстанови размер окна"
        ], intent: .window("restore"), feature: "windows"),
        .init(section: "Окна", title: "На следующий монитор", phrases: [
            "перемести окно на следующий монитор", "окно на следующий монитор",
            "отправь окно на следующий монитор"
        ], intent: .window("next-display"), feature: "windows"),
        .init(section: "Окна", title: "На предыдущий монитор", phrases: [
            "перемести окно на предыдущий монитор", "окно на предыдущий монитор"
        ], intent: .window("previous-display"), feature: "windows"),
        .init(section: "Окна", title: "Следующий рабочий стол", phrases: [
            "следующий рабочий стол", "переключись на следующий рабочий стол"
        ], intent: .window("next-space"), feature: "windows"),
        .init(section: "Окна", title: "Предыдущий рабочий стол", phrases: [
            "предыдущий рабочий стол", "переключись на предыдущий рабочий стол"
        ], intent: .window("previous-space"), feature: "windows"),
        .init(section: "Окна", title: "Свернуть окно", phrases: [
            "сверни окно", "минимизируй окно", "убери окно"
        ], intent: .window("minimize"), feature: "windows"),
        .init(section: "Окна", title: "Закрыть окно", phrases: [
            "закрой окно", "закрой это окно"
        ], intent: .window("close-window"), feature: "windows"),
        .init(section: "Система", title: "Закрыть приложение", phrases: [
            "закрой приложение", "закрой активное приложение", "выключи приложение"
        ], intent: .system("quit-front-app")),
        .init(section: "Система", title: "Закрыть его", phrases: [
            "закрой его"
        ], intent: .quitLastApp),
        .init(section: "Система", title: "Заблокировать экран", phrases: [
            "заблокируй экран", "заблокируй мак"
        ], intent: .system("lock-screen")),
        .init(section: "Система", title: "Следующий трек", phrases: [
            "следующий трек", "следующая песня"
        ], intent: .system("next-track")),
        .init(section: "Система", title: "Предыдущий трек", phrases: [
            "предыдущий трек", "предыдущая песня"
        ], intent: .system("previous-track")),
        .init(section: "Система", title: "Воспроизведение или пауза", phrases: [
            "переключи воспроизведение", "плей пауза"
        ], intent: .system("play-pause")),
        .init(section: "Система", title: "Переключить беззвучный режим", phrases: [
            "переключи звук", "переключи режим без звука"
        ], intent: .system("toggle-mute")),
        .init(section: "Система", title: "Выключить звук", phrases: [
            "выключи звук", "убери звук", "громкость ноль"
        ], intent: .volume(0)),
        .init(section: "Система", title: "Громче", phrases: [
            "громче", "увеличь громкость"
        ], intent: .system("volume-up")),
        .init(section: "Система", title: "Тише", phrases: [
            "тише", "уменьши громкость"
        ], intent: .system("volume-down")),
        .init(section: "Поиск и данные", title: "История буфера обмена", phrases: [
            "покажи историю буфера", "открой историю буфера",
            "покажи буфер обмена", "история буфера обмена"
        ], intent: .builtIn("clipboard")),
        .init(section: "Поиск и данные", title: "Открыть заметки", phrases: [
            "покажи заметки", "открой заметки"
        ], intent: .builtIn("notes"), feature: "notes"),
        .init(section: "Календарь", title: "Расписание", phrases: [
            "покажи расписание", "мое расписание"
        ], intent: .builtIn("schedule")),
        .init(section: "Календарь", title: "Следующая встреча", phrases: [
            "присоединись к следующей встрече", "зайди на следующую встречу"
        ], intent: .builtIn("meeting")),
        .init(section: "Окна", title: "Переключить окна", phrases: [
            "переключи окна", "покажи открытые окна"
        ], intent: .builtIn("windows")),
        .init(section: "Поиск и данные", title: "Поиск файлов", phrases: [
            "найди файл", "поиск файлов", "покажи файлы"
        ], intent: .builtIn("files"), feature: "files"),
        .init(section: "Поиск и данные", title: "Поиск заметок", phrases: [
            "найди заметку", "найди заметки", "поиск заметок"
        ], intent: .builtIn("searchNotes"), feature: "notes"),
        .init(section: "Справка", title: "Каталог голосовых команд", phrases: [
            "покажи голосовые команды", "открой голосовые команды",
            "какие голосовые команды доступны"
        ], intent: .builtIn("voiceCatalog"))
    ] + additionalPatterns

    /// These actions already exist in Tinycast; voice recognition only exposes their allowlisted IDs.
    private static let additionalPatterns: [Pattern] = [
        .init(section: "Окна", title: "Верхняя половина", phrases: [
            "окно наверх", "окно на верхнюю половину", "помести окно наверх"
        ], intent: .window("top-half"), feature: "windows"),
        .init(section: "Окна", title: "Нижняя половина", phrases: [
            "окно вниз", "окно на нижнюю половину", "помести окно вниз"
        ], intent: .window("bottom-half"), feature: "windows"),
        .init(section: "Окна", title: "Верхняя левая четверть", phrases: [
            "окно в верхний левый угол", "окно в верхнюю левую четверть"
        ], intent: .window("top-left-quarter"), feature: "windows"),
        .init(section: "Окна", title: "Верхняя правая четверть", phrases: [
            "окно в верхний правый угол", "окно в верхнюю правую четверть"
        ], intent: .window("top-right-quarter"), feature: "windows"),
        .init(section: "Окна", title: "Нижняя левая четверть", phrases: [
            "окно в нижний левый угол", "окно в нижнюю левую четверть"
        ], intent: .window("bottom-left-quarter"), feature: "windows"),
        .init(section: "Окна", title: "Нижняя правая четверть", phrases: [
            "окно в нижний правый угол", "окно в нижнюю правую четверть"
        ], intent: .window("bottom-right-quarter"), feature: "windows"),
        .init(section: "Окна", title: "Левая треть", phrases: [
            "окно на левую треть", "левая треть экрана"
        ], intent: .window("first-third"), feature: "windows"),
        .init(section: "Окна", title: "Средняя треть", phrases: [
            "окно на среднюю треть", "средняя треть экрана"
        ], intent: .window("center-third"), feature: "windows"),
        .init(section: "Окна", title: "Правая треть", phrases: [
            "окно на правую треть", "правая треть экрана"
        ], intent: .window("last-third"), feature: "windows"),
        .init(section: "Окна", title: "Увеличить окно", phrases: [
            "сделай окно больше", "увеличь размер окна"
        ], intent: .window("make-larger"), feature: "windows"),
        .init(section: "Окна", title: "Уменьшить окно", phrases: [
            "сделай окно меньше", "уменьши размер окна"
        ], intent: .window("make-smaller"), feature: "windows"),
        .init(section: "Окна", title: "Полноэкранный режим", phrases: [
            "переключи полноэкранный режим", "полноэкранный режим окна"
        ], intent: .window("toggle-fullscreen"), feature: "windows"),
        .init(section: "Окна", title: "Сдвинуть вверх", phrases: [
            "сдвинь окно вверх", "перемести окно вверх"
        ], intent: .window("move-up"), feature: "windows"),
        .init(section: "Окна", title: "Сдвинуть вниз", phrases: [
            "сдвинь окно вниз", "перемести окно вниз"
        ], intent: .window("move-down"), feature: "windows"),
        .init(section: "Система", title: "Показать рабочий стол", phrases: [
            "покажи рабочий стол", "скрой все окна"
        ], intent: .system("show-desktop")),
        .init(section: "Система", title: "Переключить оформление", phrases: [
            "переключи темную тему", "переключи светлую тему", "переключи оформление"
        ], intent: .system("toggle-system-appearance")),
        .init(section: "Система", title: "Stage Manager", phrases: [
            "переключи стейдж менеджер", "переключи stage manager"
        ], intent: .system("toggle-stage-manager")),
        .init(section: "Система", title: "Скрытые файлы", phrases: [
            "переключи скрытые файлы", "покажи или скрой скрытые файлы"
        ], intent: .system("toggle-hidden-files")),
        .init(section: "Система", title: "Открыть корзину", phrases: [
            "открой корзину", "покажи корзину"
        ], intent: .system("open-trash")),
        .init(section: "Система", title: "Скрыть остальные приложения", phrases: [
            "скрой остальные приложения"
        ], intent: .system("hide-all-apps-except-frontmost")),
        .init(section: "Система", title: "Показать скрытые приложения", phrases: [
            "покажи скрытые приложения"
        ], intent: .system("unhide-all-hidden-apps")),
        .init(section: "Поиск и данные", title: "Следующий элемент буфера", phrases: [
            "вставь следующий элемент буфера", "вставь следующий из буфера"
        ], intent: .builtIn("pasteNext")),
        .init(section: "Поиск и данные", title: "Поиск сниппетов", phrases: [
            "покажи сниппеты", "найди сниппет"
        ], intent: .builtIn("snippets")),
        .init(section: "Поиск и данные", title: "Поиск ссылок", phrases: [
            "покажи быстрые ссылки"
        ], intent: .builtIn("quicklinks"), feature: "quicklinks"),
        .init(section: "Поиск и данные", title: "Поиск по меню", phrases: [
            "поиск по меню", "покажи команды меню"
        ], intent: .builtIn("menuSearch")),
        .init(section: "Заметки", title: "Создать заметку", phrases: [
            "создай заметку", "новая заметка"
        ], intent: .builtIn("createNote"), feature: "notes"),
        .init(section: "Календарь", title: "Скопировать ссылку на встречу", phrases: [
            "скопируй ссылку на встречу", "копируй ссылку на следующую встречу"
        ], intent: .builtIn("copyMeetingLink")),
        .init(section: "Календарь", title: "Создать событие", phrases: [
            "создай событие", "новое событие в календаре"
        ], intent: .builtIn("createEvent")),
        .init(section: "Справка", title: "Настройки Tinycast", phrases: [
            "открой настройки тайникаст", "покажи настройки tinycast"
        ], intent: .builtIn("settings"))
    ]

    // More specific prefixes must win before the generic open/run verbs.
    private static let namedRules: [NamedRule] = [
        .init(prefix: "выполни пользовательскую команду", kinds: [.customCommand]),
        .init(prefix: "выполни команду", kinds: [.customCommand]),
        .init(prefix: "запусти команду", kinds: [.customCommand]),
        .init(prefix: "запусти apple shortcut", kinds: [.shortcut]),
        .init(prefix: "запусти быструю команду", kinds: [.shortcut]),
        .init(prefix: "запусти сценарий", kinds: [.shortcut, .workflow]),
        .init(prefix: "запусти workflow", kinds: [.workflow]),
        .init(prefix: "открой быструю ссылку", kinds: [.quicklink]),
        .init(prefix: "открой ссылку", kinds: [.quicklink]),
        .init(prefix: "примени раскладку", kinds: [.layout]),
        .init(prefix: "примени расположение окон", kinds: [.layout]),
        .init(prefix: "переключись в комнату", kinds: [.room]),
        .init(prefix: "открой комнату", kinds: [.room]),
        .init(prefix: "открой приложение", kinds: [.application]),
        .init(prefix: "запусти приложение", kinds: [.application]),
        .init(prefix: "закрой приложение", kinds: [.application], closes: true),
        .init(prefix: "закрой", kinds: [.application], closes: true),
        .init(prefix: "открой", kinds: [.application]),
        .init(prefix: "запусти", kinds: [.application, .shortcut, .workflow])
    ]

    /// Examples are generated from the same verb definitions accepted by parse(_:targets:).
    static func catalogPhrases(for target: Target) -> [String] {
        let prefix: String = switch target.kind {
        case .application: "открой"
        case .quicklink: "открой ссылку"
        case .shortcut: "запусти быструю команду"
        case .customCommand: "выполни команду"
        case .workflow: "запусти сценарий"
        case .layout: "примени раскладку"
        case .room: "открой комнату"
        }
        let primary = "\(prefix) \(target.name)"
        let alternative = namedRules.first {
            $0.kinds.contains(target.kind) && "\($0.prefix) \(target.name)" != primary
        }.map { "\($0.prefix) \(target.name)" }
        let aliases = target.aliases.prefix(3).map { "\(prefix) \($0)" }
        return [primary] + (alternative.map { [$0] } ?? []) + aliases
    }

    static func catalogItem(for target: Target) -> CatalogItem {
        let section: String = switch target.kind {
        case .application: "Приложения"
        case .quicklink: "Quicklinks"
        case .shortcut: "Apple Shortcuts"
        case .customCommand: "Пользовательские команды"
        case .workflow: "Сценарии"
        case .layout: "Раскладки окон"
        case .room: "Комнаты окон"
        }
        let feature: String? = switch target.kind {
        case .layout, .room: "windows"
        case .shortcut: "shortcuts"
        case .quicklink: "quicklinks"
        case .customCommand: "customCommands"
        case .workflow: "workflows"
        case .application: nil
        }
        return .init(section: section, title: target.name,
                     phrases: catalogPhrases(for: target), feature: feature, targetID: target.id)
    }

    static var builtinCatalog: [CatalogItem] {
        fixedPatterns.map {
            .init(section: $0.section, title: $0.title, phrases: $0.phrases, feature: $0.feature)
        } + [
            .init(section: "Система", title: "Установить громкость", phrases: [
                "громкость 25 процентов", "установи громкость 50"
            ], feature: nil),
            .init(section: "Поиск и данные", title: "Поиск файла по названию", phrases: [
                "найди файл docker-compose.yml"
            ], feature: "files"),
            .init(section: "Поиск и данные", title: "Поиск заметки по названию", phrases: [
                "найди заметку Kubernetes"
            ], feature: "notes")
        ]
    }

    static func parse(_ speech: String, targets: [Target] = []) -> Resolution {
        var original = speech.trimmingCharacters(in: .whitespacesAndNewlines)
        var phrase = normalize(original)
        // A hesitation before the verb ("эм открой", "ну поставь") is ASR noise, not intent.
        while let first = phrase.split(separator: " ").first.map(String.init),
              leadingNoise.contains(first) {
            original = tail(of: original, skipping: 1)
            phrase = normalize(original)
        }
        for wake in ["тини каст", "тайни каст", "tinycast", "тини-каст"] {
            let normalizedWake = normalize(wake)
            if phrase.hasPrefix(normalizedWake + " ") {
                let first = original.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                let tokens = normalize(first) == normalizedWake
                    ? 1 : wake.split(whereSeparator: { $0.isWhitespace }).count
                original = tail(of: original, skipping: tokens)
                phrase = normalize(original)
                break
            }
        }
        // Trailing politeness ("пожалуйста", "спасибо") is ASR noise, not part of any command.
        for noise in ["пожалуйста"] + trailingNoise {
            if phrase.hasSuffix(" " + noise) {
                original = original.replacingOccurrences(
                    of: "\\s+\(noise)[.!?\\s]*$", with: "", options: [.regularExpression, .caseInsensitive])
                phrase = normalize(original)
            }
        }
        guard !phrase.isEmpty else { return .notCommand }

        // An AI trigger word ("посмотри …") owns the whole rest of the phrase, so it runs
        // before any command grammar could reinterpret the question as an action.
        for trigger in aiTriggers {
            if let rest = suffix(after: trigger, in: phrase), !rest.isEmpty {
                let count = trigger.split(separator: " ").count
                let prompt = tail(of: original, skipping: count)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".!?…,;: "))
                return .action(.aiPrompt(trigger: trigger, prompt: prompt))
            }
        }

        if let fixed = fixedPatterns.first(where: { $0.phrases.contains(phrase) }) {
            return .action(fixed.intent)
        }

        for prefix in ["громкость", "установи громкость", "поставь громкость", "сделай громкость"] {
            if let value = suffix(after: prefix, in: phrase), !value.isEmpty {
                let words = value.split(separator: " ").map(String.init)
                if let first = words.first, let percent = Int(first), (0...100).contains(percent),
                   (words.count == 1 || (words.count == 2 &&
                     ["процент", "процента", "процентов"].contains(words[1]))) {
                    return .action(.volume(percent))
                }
                return .unknown("Громкость должна быть числом от 0 до 100")
            }
        }
        for prefix in ["яркость", "установи яркость", "поставь яркость", "сделай яркость"] {
            if let value = suffix(after: prefix, in: phrase), !value.isEmpty {
                let words = value.split(separator: " ").map(String.init)
                if let first = words.first, let percent = Int(first), (0...100).contains(percent),
                   (words.count == 1 || (words.count == 2 &&
                     ["процент", "процента", "процентов"].contains(words[1]))) {
                    return .action(.brightness(percent))
                }
                return .unknown("Яркость должна быть числом от 0 до 100")
            }
        }
        for prefix in ["найди файл", "найти файл", "найди файлы", "поиск файлов"] {
            if let rest = suffix(after: prefix, in: phrase), !rest.isEmpty {
                return .action(.builtIn("files", query: searchText(after: prefix, in: original)))
            }
        }
        for prefix in ["найди заметку", "найди заметки", "поиск заметок"] {
            if let rest = suffix(after: prefix, in: phrase), !rest.isEmpty {
                return .action(.builtIn("searchNotes", query: searchText(after: prefix, in: original)))
            }
        }
        // A generic fuzzy lookup: whatever the palette itself would find for this query.
        for prefix in ["найди", "поиск", "поищи"] {
            if let rest = suffix(after: prefix, in: phrase), !rest.isEmpty {
                return .action(.builtIn("search", query: searchText(after: prefix, in: original)))
            }
        }

        for rule in namedRules {
            guard let rest = suffix(after: rule.prefix, in: phrase) else { continue }
            guard !rest.isEmpty else { return .unknown("Назови объект команды") }
            let rawName = tail(of: original, skipping: rule.prefix.split(separator: " ").count)
            return resolveName(rawName, kinds: rule.kinds, targets: targets, quits: rule.closes)
        }

        // Only explicit, unambiguous commands receive typo correction. Free dictation
        // and ordinary questions must never accidentally become executable actions.
        if let corrected = fuzzyFixedPattern(phrase) { return corrected }

        // The action verb may contain one ASR error; qualifiers must remain exact.
        for (prefix, action) in [
            ("найди файл", "files"), ("найди файлы", "files"),
            ("найди заметку", "searchNotes"), ("найди заметки", "searchNotes")
        ] {
            guard fuzzyPrefix(prefix, in: phrase) else { continue }
            let query = searchText(after: prefix, in: original)
            guard !query.isEmpty else { return .unknown("Назови объект поиска") }
            return .action(.builtIn(action, query: query))
        }
        for rule in namedRules {
            guard fuzzyPrefix(rule.prefix, in: phrase) else { continue }
            let name = tail(of: original, skipping: rule.prefix.split(separator: " ").count)
            guard !name.isEmpty else { return .unknown("Назови объект команды") }
            return resolveName(name, kinds: rule.kinds, targets: targets, quits: rule.closes)
        }
        return .notCommand
    }

    /// No edit distance on the target here: that is handled separately by resolveName.
    /// This prevents a fuzzy action word from silently changing a qualifier such as "ссылку".
    private static func fuzzyPrefix(_ prefix: String, in phrase: String) -> Bool {
        let command = prefix.split(separator: " ")
        let words = phrase.split(separator: " ")
        guard words.count > command.count,
              let expected = command.first, let spoken = words.first,
              expected.count >= 5, spoken.count >= 4,
              distance(String(spoken), String(expected), limit: 1) == 1
        else { return false }
        return Array(words.dropFirst().prefix(command.count - 1)) == Array(command.dropFirst())
    }

    /// Correct one typo in a multiword built-in phrase, not arbitrary speech.
    /// Different plausible actions deliberately return unknown rather than executing one.
    private static func fuzzyFixedPattern(_ phrase: String) -> Resolution? {
        let words = phrase.split(separator: " ")
        guard words.count >= 2 else { return nil }
        var actions: [Intent] = []
        for pattern in fixedPatterns {
            for example in pattern.phrases {
                let expected = example.split(separator: " ")
                guard words.count == expected.count else { continue }
                var errors = 0
                for (spoken, reference) in zip(words, expected) where spoken != reference {
                    guard spoken.count >= 4, reference.count >= 5,
                          distance(String(spoken), String(reference), limit: 1) == 1
                    else { errors = 2; break }
                    errors += 1
                    if errors > 1 { break }
                }
                if errors == 1, !actions.contains(pattern.intent) { actions.append(pattern.intent) }
            }
        }
        if actions.count > 1 { return .unknown("Неоднозначная голосовая команда") }
        return actions.first.map { .action($0) }
    }

    /// An exact alias always wins. Otherwise choose only a clearly closest candidate.
    /// The bounded optimal-string-alignment distance counts insertions, deletions,
    /// substitutions and adjacent swaps, without allowing short-name guesses.
    static func resolveName(_ raw: String, kinds: Set<Target.Kind>, targets: [Target]) -> Resolution {
        resolveName(raw, kinds: kinds, targets: targets, quits: false)
    }

    /// `quits` marks a close verb: the winner quits instead of launching.
    static func resolveName(
        _ raw: String, kinds: Set<Target.Kind>, targets: [Target], quits: Bool
    ) -> Resolution {
        let original = normalize(raw)
        let key = romanizedKey(raw)
        guard !key.isEmpty else { return .unknown("Назови объект команды") }
        var candidates: [(target: Target, distance: Int)] = []
        for target in targets where kinds.contains(target.kind) {
            let names = [target.name] + target.aliases
            // Only full-name or alias matches count, never a substring of an installed app.
            var best: Int?
            for name in names {
                let candidateKey = romanizedKey(name)
                if normalize(name) == original || candidateKey == key {
                    best = 0
                    break
                }
                let allowed = maxErrors(for: max(key.count, candidateKey.count))
                if allowed == 0 { continue }
                if let distance = distance(key, candidateKey, limit: allowed) {
                    best = min(best ?? Int.max, distance)
                }
            }
            if let best { candidates.append((target, best)) }
        }
        candidates.sort {
            if $0.distance != $1.distance { return $0.distance < $1.distance }
            return $0.target.name.localizedStandardCompare($1.target.name) == .orderedAscending
        }
        guard let winner = candidates.first else { return .unknown("Не найдено: \(raw)") }
        // A fuzzy winner only runs when the next closest name is distinctly worse.
        let nearby = candidates.filter { $0.distance <= winner.distance + (winner.distance == 0 ? 0 : 1) }
        if nearby.count != 1 { return .ambiguous(nearby.map(\.target)) }
        if quits { return .action(.quitApp(winner.target.id)) }
        return .action(.target(winner.target.kind, winner.target.id))
    }

    /// Keep the original Cyrillic for exact matching, and a Latin reading for cross-script ASR.
    /// Existing Tinycast ScriptRomanization handles Russian, Japanese, Chinese and other scripts.
    static func romanizedKey(_ input: String) -> String {
        let folded = normalize(input)
        let romanized = ScriptRomanization.latin(folded) ?? folded
        return String(romanized.filter { $0.isLetter || $0.isNumber })
    }

    private static func maxErrors(for length: Int) -> Int {
        switch length {
        case ..<4: 0
        case 4..<7: 1
        case 7..<13: 2
        default: 3
        }
    }

    /// Bounded OSA Damerau-Levenshtein: an adjacent transposition costs one edit.
    private static func distance(_ lhs: String, _ rhs: String, limit: Int) -> Int? {
        let a = Array(lhs)
        let b = Array(rhs)
        guard abs(a.count - b.count) <= limit else { return nil }
        if a == b { return 0 }
        var beforePrevious = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [Int](repeating: 0, count: b.count + 1)
            current[0] = i
            var smallest = current[0]
            if !b.isEmpty {
                for j in 1...b.count {
                    let cost = a[i - 1] == b[j - 1] ? 0 : 1
                    current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                    if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                        current[j] = min(current[j], beforePrevious[j - 2] + 1)
                    }
                    smallest = min(smallest, current[j])
                }
            }
            if smallest > limit { return nil }
            beforePrevious = previous
            previous = current
        }
        let result = previous[b.count]
        return result <= limit ? result : nil
    }

    /// Lower-case, punctuation/extra spaces, Russian ё, spelled-out numbers and infinitive
    /// verbs are insignificant: the command grammar speaks in imperatives, ASR doesn't.
    static func normalize(_ input: String) -> String {
        let lower = input.lowercased().replacingOccurrences(of: "ё", with: "е")
        let scalars = lower.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : " "
        }
        let spaced = String(scalars).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return verbToImperative(numeralsToDigits(spaced))
    }

    /// One infinitive word maps to one imperative word, so spoken prefix lengths stay intact.
    private static let verbImperatives = [
        "открыть": "открой", "запустить": "запусти", "выполнить": "выполни",
        "найти": "найди", "показать": "покажи", "применить": "примени",
        "установить": "установи", "поставить": "поставь", "сделать": "сделай",
        "переключиться": "переключись", "переключить": "переключись",
        "свернуть": "сверни", "закрыть": "закрой", "выключить": "выключи",
        "минимизировать": "минимизируй", "поискать": "поищи",
    ]

    private static func verbToImperative(_ input: String) -> String {
        input.split(separator: " ").map { verbImperatives[String($0)] ?? String($0) }
            .joined(separator: " ")
    }

    /// Russian ASR spells numbers out; commands and app names carry digits ("Громкость 25",
    /// "1Password"). Digits are canonical, so words fold back into digits before matching.
    static func numeralsToDigits(_ input: String) -> String {
        var words = input.split(separator: " ").map(String.init)
        var index = 0
        while index < words.count {
            // A number word may be glued to the next word by ASR ("двадцатьпять") — split it.
            let token = words[index]
            if !numberWords.contains(token), let split = numberWordPrefix(of: token) {
                words.replaceSubrange(index...index, with: [split.remainder, split.numberWord].filter { !$0.isEmpty })
                continue
            }
            if numberWordValues[token] != nil {
                // A greedy run of number words folds into one total ("двадцать пять" → 25).
                var total = 0
                var consumed = 0
                while index + consumed < words.count {
                    let word = words[index + consumed]
                    if let value = numberWordValues[word] {
                        total += value
                        consumed += 1
                    } else {
                        break
                    }
                }
                words.replaceSubrange(index..<(index + consumed), with: [String(total)])
            }
            index += 1
        }
        return words.joined(separator: " ")
    }

    private static let numberWordValues: [String: Int] = [
        "ноль": 0, "один": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4,
        "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9,
        "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13,
        "четырнадцать": 14, "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17,
        "восемнадцать": 18, "девятнадцать": 19, "двадцать": 20, "тридцать": 30,
        "сорок": 40, "пятьдесят": 50, "шестьдесят": 60, "семьдесят": 70,
        "восемьдесят": 80, "девяносто": 90, "сто": 100,
    ]

    /// The leading number-word fragment of a glued token, if any ("двадцатьпять" → "двадцать").
    /// A short leftover would be a false positive ("стол" = "сто" + "л"), so it must be a word.
    private static func numberWordPrefix(of token: String) -> (numberWord: String, remainder: String)? {
        let longest = numberWords.filter { token.hasPrefix($0) }.max { $0.count < $1.count }
        guard let longest, longest.count < token.count else { return nil }
        let remainder = String(token.dropFirst(longest.count))
        guard remainder.count >= 3 || remainder.isEmpty else { return nil }
        return (longest, remainder)
    }

    /// Configurable AI trigger words; the first match sends the rest of the phrase to Quick AI.
    /// Reassigned when Settings edits the stored list. Plain data whose only writer is the
    /// MainActor settings view, so unsynchronized reads during parsing are safe in practice.
    nonisolated(unsafe) static var aiTriggers: [String] = AIVoiceTriggerStore.normalizedTriggers()

    private static var numberWords: [String] { Array(numberWordValues.keys) }

    /// Hesitations that precede a dictated verb; the command itself is what was meant.
    private static let leadingNoise = ["эм", "э", "ну", "мм", "а"]

    /// Trailing ASR politeness/filler noise beyond "пожалуйста" must not reach name resolution.
    private static let trailingNoise = ["спасибо", "благодарю"]

    /// A dictated search keeps its inner punctuation ("docker-compose.yml"), but ASR adds
    /// sentence-ending marks a typed query would never carry.
    private static func searchText(after prefix: String, in original: String) -> String {
        tail(of: original, skipping: prefix.split(separator: " ").count)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?…,;: "))
    }

    private static func suffix(after prefix: String, in phrase: String) -> String? {
        guard phrase == prefix || phrase.hasPrefix(prefix + " ") else { return nil }
        if phrase == prefix { return "" }
        return String(phrase.dropFirst(prefix.count + 1))
    }

    private static func tail(of original: String, skipping count: Int) -> String {
        original.split(whereSeparator: { $0.isWhitespace }).dropFirst(count)
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
