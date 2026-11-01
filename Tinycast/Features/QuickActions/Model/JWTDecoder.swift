import CoreFoundation
import Foundation

enum JWTDecoder {
    static func decode(_ input: String) throws -> String {
        guard input.utf8.count <= 1_048_576 else { throw DeveloperUtilityError.invalidJWT }
        do {
            let words = input.split(whereSeparator: \.isWhitespace)
            let token: Substring
            if words.count == 2, words[0].lowercased() == "bearer" {
                token = words[1]
            } else if words.count == 1 {
                token = words[0]
            } else {
                throw DeveloperUtilityError.invalidJWT
            }
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3, parts.allSatisfy({ $0.utf8.allSatisfy(isBase64URL) }),
                parts[2].count % 4 != 1
            else { throw DeveloperUtilityError.invalidJWT }
            let header = try object(parts[0])
            let payload = try object(parts[1])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            var dates: [String] = []
            for claim in ["iat", "nbf", "exp"] {
                guard let value = payload[claim] else { continue }
                guard let number = value as? NSNumber,
                    CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                    (-62_135_596_800...253_402_300_799.999).contains(number.doubleValue)
                else { throw DeveloperUtilityError.invalidJWT }
                dates.append("\(claim): \(formatter.string(from: Date(timeIntervalSince1970: number.doubleValue)))")
            }
            let headerText = try pretty(header)
            let payloadText = try pretty(payload)
            var sections = [String(localized: "Header:\n\(headerText)"),
                            String(localized: "Payload:\n\(payloadText)")]
            if !dates.isEmpty {
                let text = dates.joined(separator: "\n")
                sections.append(String(localized: "UTC dates:\n\(text)"))
            }
            sections.append(String(localized: "Signature not verified"))
            return sections.joined(separator: "\n\n")
        } catch {
            throw DeveloperUtilityError.invalidJWT
        }
    }

    private static func isBase64URL(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
            || byte == 45 || byte == 95
    }

    private static func object(_ segment: Substring) throws -> [String: Any] {
        guard !segment.isEmpty, segment.count % 4 != 1 else { throw DeveloperUtilityError.invalidJWT }
        var base64 = segment.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw DeveloperUtilityError.invalidJWT }
        return object
    }

    private static func pretty(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}
