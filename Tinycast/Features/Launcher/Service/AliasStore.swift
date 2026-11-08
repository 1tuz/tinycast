import Foundation

/// The user's per-entry aliases, keyed like favorites and ranking by `preferenceKey`.
@MainActor
@Observable
final class AliasStore {
    private let defaults: UserDefaults
    private let defaultsKey = "launcherAliases"

    private(set) var aliases: [String: String]
    /// AppIndex includes this in its result key, invalidating a ranking when an alias changes.
    private(set) var revision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aliases = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    /// Backwards compatible: the first alias remains the primary launcher nickname.
    func alias(for entryKey: String) -> String? { allAliases(for: entryKey).first }

    /// Extra aliases share the existing backup key and are also searchable in the launcher.
    /// A newline is the on-disk separator; existing single-alias values still load unchanged.
    func allAliases(for entryKey: String) -> [String] {
        guard let value = aliases[entryKey] else { return [] }
        return Self.clean(value.components(separatedBy: "\n"))
    }

    func setAlias(_ alias: String, for entryKey: String) {
        setAliases([alias], for: entryKey)
    }

    func setAliases(_ values: [String], for entryKey: String) {
        let cleaned = Self.clean(values)
        let value = cleaned.isEmpty ? nil : cleaned.joined(separator: "\n")
        guard aliases[entryKey] != value else { return }
        aliases[entryKey] = value
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    /// Limit ASR candidates and reject accidental duplicate aliases without changing words.
    private static func clean(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let item = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty, item.count <= 64, !item.contains("\n") else { continue }
            let key = item.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            guard seen.insert(key).inserted else { continue }
            result.append(item)
            if result.count == 8 { break }
        }
        return result
    }

    func removeKeys(_ keys: Set<String>) {
        let remaining = aliases.filter { !keys.contains($0.key) }
        guard remaining.count != aliases.count else { return }
        aliases = remaining
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }

    func replace(_ new: [String: String]) {
        // Old backups contain one alias per key; newer ones encode multiple with newlines.
        aliases = new.compactMapValues { value in
            let items = Self.clean(value.components(separatedBy: "\n"))
            return items.isEmpty ? nil : items.joined(separator: "\n")
        }
        revision &+= 1
        defaults.set(aliases, forKey: defaultsKey)
    }
}
