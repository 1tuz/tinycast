import Foundation

enum CronExpression {
    private static let bounds = [0...59, 0...23, 1...31, 1...12, 0...7]

    static func explain(_ input: String) throws -> String {
        let fields = input.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 5 else { throw DeveloperUtilityError.invalidCron }
        let values = try zip(fields, bounds).map { try parse($0.0, bounds: $0.1) }
        if fields.dropFirst().allSatisfy({ $0 == "*" }), fields[0].hasPrefix("*/"),
            !fields[0].contains(","), let step = Int(fields[0].dropFirst(2))
        {
            return String(localized: "Every \(step) minutes")
        }
        var lines = values.enumerated().map { index, parsed in
            let normalized = index == 4 ? Set(parsed.map { $0 == 7 ? 0 : $0 }).sorted() : parsed
            let text = normalized.map(String.init).joined(separator: ", ")
            switch index {
            case 0: return String(localized: "Minute: \(text)")
            case 1: return String(localized: "Hour: \(text)")
            case 2: return String(localized: "Day of month: \(text)")
            case 3: return String(localized: "Month: \(text)")
            default:
                if normalized.contains(0) {
                    return String(localized: "Day of week: \(text) (0 = Sunday)")
                }
                return String(localized: "Day of week: \(text)")
            }
        }
        if fields[2] != "*", fields[4] != "*" {
            lines.append(
                String(localized: "Cron matches either day condition (OR): day of month or day of week."))
        }
        return lines.joined(separator: "\n")
    }

    private static func parse(_ field: String, bounds: ClosedRange<Int>) throws -> [Int] {
        var result = Set<Int>()
        for item in field.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = item.split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count) else { throw DeveloperUtilityError.invalidCron }
            let step: Int
            if parts.count == 2 {
                guard let value = number(parts[1]), value > 0,
                    value <= bounds.upperBound - bounds.lowerBound + 1
                else {
                    throw DeveloperUtilityError.invalidCron
                }
                step = value
            } else {
                step = 1
            }
            let start: Int
            let end: Int
            if parts[0] == "*" {
                start = bounds.lowerBound
                end = bounds.upperBound
            } else {
                let range = parts[0].split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(range.count), let first = number(range[0]), bounds.contains(first)
                else {
                    throw DeveloperUtilityError.invalidCron
                }
                start = first
                if range.count == 2 {
                    guard let last = number(range[1]), bounds.contains(last), last >= start else {
                        throw DeveloperUtilityError.invalidCron
                    }
                    end = last
                } else {
                    end = parts.count == 2 ? bounds.upperBound : start
                }
            }
            for value in start...end where (value - start) % step == 0 { result.insert(value) }
        }
        guard !result.isEmpty else { throw DeveloperUtilityError.invalidCron }
        return result.sorted()
    }

    private static func number(_ token: Substring) -> Int? {
        guard !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(token)
    }
}
