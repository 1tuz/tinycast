import Foundation

enum YAMLJSONConverter {
    static func convert(_ input: String) throws -> String {
        guard input.utf8.count <= 1_048_576 else { throw DeveloperUtilityError.invalidYAMLJSON }
        do {
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw DeveloperUtilityError.invalidYAMLJSON }
            if let json = try? JSONSerialization.jsonObject(
                with: Data(trimmed.utf8), options: [.fragmentsAllowed]) {
                return try BlockYAMLEmitter.dump(json)
            }
            let value = try BlockYAMLParser.parse(input)
            let data = try JSONSerialization.data(
                withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            return String(decoding: data, as: UTF8.self)
        } catch {
            throw DeveloperUtilityError.invalidYAMLJSON
        }
    }
}
