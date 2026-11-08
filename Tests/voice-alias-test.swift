import Foundation

@main
struct VoiceAliasTest {
    @MainActor
    static func main() {
        let suite = "tinycast-voice-alias-test-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("no test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["app": "old name"], forKey: "launcherAliases")
        let store = AliasStore(defaults: defaults)
        precondition(store.alias(for: "app") == "old name", "Legacy alias migration")
        precondition(store.allAliases(for: "app") == ["old name"])
        store.setAliases(["Клод", " клод ", "Клауд", "Claude", ""], for: "app")
        precondition(store.allAliases(for: "app") == ["Клод", "Клауд", "Claude"])
        precondition(store.alias(for: "app") == "Клод", "Primary launcher alias")
        precondition(AliasStore(defaults: defaults).allAliases(for: "app")
                     == ["Клод", "Клауд", "Claude"], "Persisted aliases")
        store.setAlias("one", for: "app")
        precondition(store.allAliases(for: "app") == ["one"], "Legacy setter")
        store.replace(["app": "first\nsecond", "blank": "   "])
        precondition(store.allAliases(for: "app") == ["first", "second"], "Backup restore")
        precondition(store.allAliases(for: "blank").isEmpty)
        store.removeKeys(["app"])
        precondition(store.alias(for: "app") == nil, "Delete all aliases")
        print("Voice alias store: all assertions passed")
    }
}
