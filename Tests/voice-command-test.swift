import Foundation

@main
struct VoiceCommandTest {
    static func main() {
        typealias P = SpeechVoiceCommandParser
        let apps: [P.Target] = [
            .init(kind: .application, id: "onepassword", name: "1Password"),
            .init(kind: .application, id: "telegram", name: "Telegram", aliases: ["Телеграм", "Телега"]),
            .init(kind: .application, id: "telegram-beta", name: "Telegram Beta"),
            .init(kind: .application, id: "obsidium", name: "Obsidium", aliases: ["Обсидиум"]),
            .init(kind: .application, id: "safari", name: "Safari"),
            .init(kind: .application, id: "jira", name: "Jira", aliases: ["Джира"]),
            .init(kind: .customCommand, id: "clear", name: "Очистка кэша"),
            .init(kind: .shortcut, id: "work", name: "Рабочее окружение"),
            .init(kind: .quicklink, id: "link", name: "Документация")
        ]
        var tested = 0
        func expect(_ text: String, _ expected: P.Resolution, line: Int = #line) {
            let actual = P.parse(text, targets: apps)
            guard actual == expected else {
                fatalError("Line \(line): \(text): \(actual) != \(expected)")
            }
            tested += 1
        }
        expect("Открой Telegram", .action(.target(.application, "telegram")))
        expect("Открой телеграм", .action(.target(.application, "telegram")))
        expect("Открой телеграмм", .action(.target(.application, "telegram")))
        expect("Открой тетеграм", .action(.target(.application, "telegram")))
        expect("Открой тилеграм", .action(.target(.application, "telegram")))
        expect("Открой тлеграм", .action(.target(.application, "telegram")))
        expect("Открой телега", .action(.target(.application, "telegram")))
        // No hand-written Telegram aliases: Russian ASR still matches the Latin app name.
        let bareTelegram = [P.Target(kind: .application, id: "plain", name: "Telegram")]
        guard P.parse("Открой тетеграм", targets: bareTelegram)
                == .action(.target(.application, "plain")) else {
            fatalError("Universal fuzzy transliteration needs no per-app aliases")
        }
        tested += 1
        expect("Открой Telegram Beta", .action(.target(.application, "telegram-beta")))
        expect("Тини каст открой Обсидиум", .action(.target(.application, "obsidium")))
        expect("Тини-каст открой Обсидиум", .action(.target(.application, "obsidium")))
        expect("Открой Sfaari", .action(.target(.application, "safari")))
        expect("Открой Джира", .action(.target(.application, "jira")))
        expect("Запусти сценарий Рабочее окружение", .action(.target(.shortcut, "work")))
        expect("Выполни команду Очистка кэша", .action(.target(.customCommand, "clear")))
        expect("Открой ссылку Документация", .action(.target(.quicklink, "link")))
        expect("Поставь окно справа", .action(.window("right-half")))
        expect("Перемести окно вправо", .action(.window("move-right")))
        expect("Отправь окно на следующий монитор", .action(.window("next-display")))
        expect("Громкость 25 процентов", .action(.volume(25)))
        expect("Сверни окно", .action(.window("minimize")))
        expect("Свернуть окно", .action(.window("minimize")))
        expect("Закрой окно", .action(.window("close-window")))
        expect("Закрыть окно", .action(.window("close-window")))
        expect("Закрой приложение", .action(.system("quit-front-app")))
        expect("Закрыть приложение", .action(.system("quit-front-app")))
        expect("Яркость двадцать пять", .action(.brightness(25)))
        expect("Яркость 50 процентов", .action(.brightness(50)))
        expect("Яркость ноль", .action(.brightness(0)))
        expect("Яркость 101", .unknown("Яркость должна быть числом от 0 до 100"))
        expect("Найди телеграм", .action(.builtIn("search", query: "телеграм")))
        expect("Поиск докер компоуз", .action(.builtIn("search", query: "докер компоуз")))
        expect("Громкость 101", .unknown("Громкость должна быть числом от 0 до 100"))
        expect("Найди файл docker-compose.yml", .action(.builtIn("files", query: "docker-compose.yml")))
        expect("Найди заметку Kubernetes", .action(.builtIn("searchNotes", query: "Kubernetes")))
        expect("Покажи историю буфера", .action(.builtIn("clipboard")))
        expect("Присоединись к следующей встрече", .action(.builtIn("meeting")))
        // ASR punctuation, politeness and spelled-out numbers must not push commands to the AI.
        expect("Открой телеграм.", .action(.target(.application, "telegram")))
        expect("Открой телеграм!", .action(.target(.application, "telegram")))
        expect("Открыть телеграмм", .action(.target(.application, "telegram")))
        expect("открой телеграм", .action(.target(.application, "telegram")))
        expect("Эм открой телеграм", .action(.target(.application, "telegram")))
        expect("Открой телеграм спасибо", .action(.target(.application, "telegram")))
        expect("Открой один пассворд", .action(.target(.application, "onepassword")))
        expect("Громкость двадцать пять", .action(.volume(25)))
        expect("Ну поставь громкость тридцать", .action(.volume(30)))
        expect("Установи громкость ноль", .action(.volume(0)))
        expect("Найди файл докер compose.", .action(.builtIn("files", query: "докер compose")))
        expect("Найди заметку Kubernetes!", .action(.builtIn("searchNotes", query: "Kubernetes")))
        expect("Как открыть Telegram в macOS?", .notCommand)
        expect("Объясни как изменить громкость", .notCommand)
        expect("Выключи компьютер", .notCommand)
        expect("Открой неизвестную программу", .unknown("Не найдено: неизвестную программу"))
        expect("Открой т", .unknown("Не найдено: т"))
        let ambiguous = [
            P.Target(kind: .application, id: "a1", name: "Telegram"),
            P.Target(kind: .application, id: "a2", name: "Телеграм")
        ]
        guard case .ambiguous(let choices) = P.parse("Открой телеграм", targets: ambiguous),
              choices.count == 2 else {
            fatalError("Ambiguous target executed instead of offering a choice")
        }
        tested += 1
        // The catalog's static example phrases must be parsed by the same command grammar.
        for item in P.builtinCatalog {
            for phrase in item.phrases {
                guard case .action = P.parse(phrase, targets: apps) else {
                    fatalError("Catalog advertises unsupported phrase: \(phrase)")
                }
                tested += 1
            }
        }
        print("Voice command parser: \(tested) assertions passed")
    }
}
