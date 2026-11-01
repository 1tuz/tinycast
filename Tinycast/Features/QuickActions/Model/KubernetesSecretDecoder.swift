import Foundation

enum KubernetesSecretDecoder {
    static func decode(_ input: String) throws -> String {
        guard input.utf8.count <= 1_048_576 else { throw DeveloperUtilityError.invalidKubernetesSecret }
        do {
            let value: Any
            if let json = try? JSONSerialization.jsonObject(with: Data(input.utf8)) {
                value = json
            } else {
                value = try BlockYAMLParser.parse(input)
            }
            guard let secret = value as? [String: Any], secret["kind"] as? String == "Secret" else {
                throw DeveloperUtilityError.invalidKubernetesSecret
            }
            if secret["data"] == nil || secret["data"] is NSNull {
                return String(localized: "The Secret contains no data.")
            }
            guard let entries = secret["data"] as? [String: Any] else {
                throw DeveloperUtilityError.invalidKubernetesSecret
            }
            if entries.isEmpty { return String(localized: "The Secret contains no data.") }
            let lines = try entries.keys.sorted().flatMap { key -> [String] in
                guard let encoded = entries[key] as? String, let data = Data(base64Encoded: encoded) else {
                    throw DeveloperUtilityError.invalidKubernetesSecret
                }
                let keyText = try quoted(key)
                guard let text = String(data: data, encoding: .utf8), text.unicodeScalars.allSatisfy({
                    $0.value >= 32 || [9, 10, 13].contains($0.value)
                }) else {
                    let count = data.count
                    let marker = String(localized: "<\(count) bytes binary>")
                    return ["\(keyText): \(marker)"]
                }
                guard text.contains("\n") else { return ["\(keyText): \(try quoted(text))"] }
                let chomping = text.hasSuffix("\n") ? "|2+" : "|2-"
                var content = text.components(separatedBy: "\n")
                if text.hasSuffix("\n") { content.removeLast() }
                return ["\(keyText): \(chomping)"] + content.map { "  " + $0 }
            }
            return lines.joined(separator: "\n") + "\n"
        } catch {
            throw DeveloperUtilityError.invalidKubernetesSecret
        }
    }

    private static func quoted(_ text: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
