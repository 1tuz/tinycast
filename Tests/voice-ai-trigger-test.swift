import Foundation

@main
struct VoiceAITriggerTest {
    static func main() {
        typealias P = SpeechVoiceCommandParser
        let apps: [P.Target] = [
            .init(kind: .application, id: "telegram", name: "Telegram", aliases: ["Телеграм"]),
            .init(kind: .application, id: "safari", name: "Safari")
        ]
        var tested = 0
        func expect(_ text: String, _ expected: P.Resolution, line: Int = #line) {
            let actual = P.parse(text, targets: apps)
            guard actual == expected else {
                fatalError("Line \(line): \(text): \(actual) != \(expected)")
            }
            tested += 1
        }

        // Restore the built-in trigger list between groups, so each tests its own store state.
        let defaults = UserDefaults(suiteName: "voice-ai-trigger-test")!
        func resetTriggers() {
            defaults.removePersistentDomain(forName: "voice-ai-trigger-test")
            P.aiTriggers = AIVoiceTriggerStore.normalizedTriggers(defaults: defaults)
        }

        // 1. Built-in "посмотри" trigger.
        resetTriggers()
        expect("Посмотри как дела", .action(.aiPrompt(trigger: "посмотри", prompt: "как дела")))
        expect("Посмотри, как погода в Москве", .action(.aiPrompt(trigger: "посмотри", prompt: "как погода в Москве")))
        expect("тини каст посмотри что это", .action(.aiPrompt(trigger: "посмотри", prompt: "что это")))
        // Trailing politeness is stripped before the trigger runs.
        expect("Посмотри как дела спасибо", .action(.aiPrompt(trigger: "посмотри", prompt: "как дела")))
        // A bare trigger with no question is not a command.
        expect("Посмотри", .notCommand)

        // 2. Commands still beat nothing: an AI trigger never swallows a real command,
        // because the builtin trigger word is not a command prefix anywhere in the grammar.
        expect("Открой телеграм", .action(.target(.application, "telegram")))
        expect("Найди файл docker-compose.yml", .action(.builtIn("files", query: "docker-compose.yml")))
        expect("Громкость 25 процентов", .action(.volume(25)))

        // 3. User-added trigger words go through the store.
        AIVoiceTriggerStore.save(
            [AIVoiceTrigger(trigger: "спроси"), AIVoiceTrigger(trigger: "посмотри")],
            defaults: defaults)
        P.aiTriggers = AIVoiceTriggerStore.normalizedTriggers(defaults: defaults)
        expect("Спроси у кого день рождения", .action(.aiPrompt(trigger: "спроси", prompt: "у кого день рождения")))
        expect("Посмотри как дела", .action(.aiPrompt(trigger: "посмотри", prompt: "как дела")))
        // Multi-word triggers match whole words.
        AIVoiceTriggerStore.save([AIVoiceTrigger(trigger: "спроси у нейросети")], defaults: defaults)
        P.aiTriggers = AIVoiceTriggerStore.normalizedTriggers(defaults: defaults)
        expect(
            "Спроси у нейросети что такое квант",
            .action(.aiPrompt(trigger: "спроси у нейросети", prompt: "что такое квант")))
        // Trigger matching is by whole word: "посмотри" must not fire inside "посмотритель".
        expect("Посмотритель музея", .notCommand)

        // 4. Blank entries are dropped; an empty stored list falls back to the builtin.
        AIVoiceTriggerStore.save([AIVoiceTrigger(trigger: "  ")], defaults: defaults)
        P.aiTriggers = AIVoiceTriggerStore.normalizedTriggers(defaults: defaults)
        expect("Посмотри как дела", .action(.aiPrompt(trigger: "посмотри", prompt: "как дела")))

        // 5. Store round-trips a per-trigger model override.
        AIVoiceTriggerStore.save(
            [AIVoiceTrigger(trigger: "посмотри", model: .appleIntelligence)],
            defaults: defaults)
        let restored = AIVoiceTriggerStore.triggers(defaults: defaults)
        guard restored.count == 1, restored[0].model == .appleIntelligence else {
            fatalError("Trigger store must round-trip the model override")
        }
        tested += 1
        resetTriggers()

        print("Voice AI trigger parser: \(tested) assertions passed")
    }
}
