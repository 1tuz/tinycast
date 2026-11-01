import Foundation

enum BlockYAMLEmitter {
    static func dump(_ value: Any) throws -> String {
        try lines(value, indentation: 0, depth: 0).joined(separator: "\n") + "\n"
    }

    private static func lines(_ value: Any, indentation: Int, depth: Int) throws -> [String] {
        guard depth < 64 else { throw DeveloperUtilityError.invalidYAMLJSON }
        let prefix = String(repeating: " ", count: indentation)
        if let mapping = value as? [String: Any], !mapping.isEmpty {
            return try mapping.keys.sorted().flatMap { key in
                let child = mapping[key]!
                let label = prefix + (try scalar(key)) + ":"
                if isNonemptyCollection(child) {
                    return [label] + (try lines(child, indentation: indentation + 2, depth: depth + 1))
                }
                return [label + " " + (try scalar(child))]
            }
        }
        if let sequence = value as? [Any], !sequence.isEmpty {
            return try sequence.flatMap { child in
                if isNonemptyCollection(child) {
                    return [prefix + "-"]
                        + (try lines(child, indentation: indentation + 2, depth: depth + 1))
                }
                return [prefix + "- " + (try scalar(child))]
            }
        }
        return [prefix + (try scalar(value))]
    }

    private static func isNonemptyCollection(_ value: Any) -> Bool {
        if let mapping = value as? [String: Any] { return !mapping.isEmpty }
        if let array = value as? [Any] { return !array.isEmpty }
        return false
    }

    private static func scalar(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
