import CryptoKit
import Foundation

extension DeveloperUtility {
    func transform(_ input: String) throws -> String {
        switch self {
        case .decodeJWT:
            return try JWTDecoder.decode(input)
        case .calculateCIDR:
            return try IPv4CIDR.explain(input)
        case .decodeKubernetesSecret:
            return try KubernetesSecretDecoder.decode(input)
        case .explainCron:
            return try CronExpression.explain(input)
        case .convertYAMLJSON:
            return try YAMLJSONConverter.convert(input)
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
                let decoded = String(data: data, encoding: .utf8)
            else { throw DeveloperUtilityError.invalidBase64 }
            return decoded
        case .formatJSON, .minifyJSON:
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = trimmed.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                let result = try? JSONSerialization.data(
                    withJSONObject: json,
                    options: self == .formatJSON
                        ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
                        : [.fragmentsAllowed]
                )
            else { throw DeveloperUtilityError.invalidJSON }
            return String(decoding: result, as: UTF8.self)
        case .hashMD5:
            return Insecure.MD5.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        case .hashSHA256:
            return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        case .hexEncode:
            return input.utf8.map { String(format: "%02x", $0) }.joined()
        case .hexDecode:
            return try Self.decodeHex(input)
        case .urlEncode:
            let unreserved = CharacterSet(
                charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            guard let encoded = input.addingPercentEncoding(withAllowedCharacters: unreserved) else {
                throw DeveloperUtilityError.invalidURL
            }
            return encoded
        case .urlDecode:
            guard let decoded = input.removingPercentEncoding else { throw DeveloperUtilityError.invalidURL }
            return decoded
        case .generateUUID:
            return UUID().uuidString.lowercased()
        case .timestampToDate:
            let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                token.range(
                    of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression)
                    != nil,
                let seconds = Double(token), seconds.isFinite,
                (-62_135_596_800...253_402_300_799.999).contains(seconds)
            else { throw DeveloperUtilityError.invalidTimestamp }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.string(from: Date(timeIntervalSince1970: seconds))
        case .convertColor:
            return try Self.convertColor(input)
        case .generateLoremIpsum:
            return
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua."
        case .convertCase:
            let separated =
                input
                .replacingOccurrences(
                    of: #"(\p{Lu}+)(\p{Lu}\p{Ll})"#, with: "$1 $2", options: .regularExpression
                )
                .replacingOccurrences(
                    of: #"([\p{Ll}\p{N}])(\p{Lu})"#, with: "$1 $2", options: .regularExpression)
            let words = separated.split { !$0.isLetter && !$0.isNumber }.map { $0.lowercased() }
            guard let first = words.first else { throw DeveloperUtilityError.noWords }
            let camel = first + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            return
                "camelCase: \(camel)\nsnake_case: \(words.joined(separator: "_"))\nkebab-case: \(words.joined(separator: "-"))"
        }
    }

    private static func decodeHex(_ input: String) throws -> String {
        let bytes = Array(input.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard bytes.count.isMultiple(of: 2) else { throw DeveloperUtilityError.invalidHex }
        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count / 2)
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            guard let high = hexDigit(bytes[offset]), let low = hexDigit(bytes[offset + 1]) else {
                throw DeveloperUtilityError.invalidHex
            }
            decoded.append(high * 16 + low)
        }
        guard let text = String(bytes: decoded, encoding: .utf8) else {
            throw DeveloperUtilityError.invalidHex
        }
        return text
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }

    private static func convertColor(_ input: String) throws -> String {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let color: ColorValue
        if token.hasPrefix("#"), token.count == 4 || token.count == 7,
            let parsed = ColorValue.parse(token)
        {
            color = parsed
        } else if let parts = colorArguments(token, function: "rgb"),
            let red = Int(parts[0]), let green = Int(parts[1]), let blue = Int(parts[2]),
            [red, green, blue].allSatisfy({ (0...255).contains($0) })
        {
            color = ColorValue(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
        } else if let parts = colorArguments(token, function: "hsl"),
            let hue = colorNumber(parts[0]), parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
            let saturation = colorNumber(String(parts[1].dropLast())),
            let lightness = colorNumber(String(parts[2].dropLast())),
            (0...360).contains(hue), (0...100).contains(saturation), (0...100).contains(lightness)
        {
            color = ColorValue(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
        } else {
            throw DeveloperUtilityError.invalidColor
        }
        let channels = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        let hex = "#" + channels.map { String(format: "%02x", $0) }.joined()
        let hsl = color.hsl
        return
            "\(hex)\nrgb(\(channels[0]), \(channels[1]), \(channels[2]))\nhsl(\(colorNumber(hsl.hue)), \(colorNumber(hsl.saturation * 100))%, \(colorNumber(hsl.lightness * 100))%)"
    }

    private static func colorArguments(_ token: String, function: String) -> [String]? {
        guard token.hasPrefix(function + "("), token.hasSuffix(")") else { return nil }
        let parts = token.dropFirst(function.count + 1).dropLast()
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return parts.count == 3 ? parts : nil
    }

    private static func colorNumber(_ token: String) -> Double? {
        guard !token.isEmpty, token.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
            let number = Double(token), number.isFinite
        else { return nil }
        return number
    }

    private static func colorNumber(_ number: Double) -> String {
        let rounded = (number * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }
}
