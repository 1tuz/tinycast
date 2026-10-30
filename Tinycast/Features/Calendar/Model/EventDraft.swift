import Foundation

/// What the Create Event prompt collects, before anything touches the calendar.
struct EventDraft: Sendable, Equatable {
    var title: String = ""
    var startDate: Date? = nil
    var durationMinutes: Int = 30

    static let durations = [15, 30, 45, 60]

    /// A blank title is the one thing that cannot be written; everything else has a default.
    var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    func start(from now: Date) -> Date { startDate ?? now }

    func end(from now: Date) -> Date {
        start(from: now).addingTimeInterval(TimeInterval(durationMinutes * 60))
    }

    /// Parses a local event phrase with an optional today/tomorrow and clock time.
    static func parse(_ raw: String, now: Date = Date(), calendar: Calendar = .current) -> Self? {
        let input = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let source = input as NSString
        func capture(_ group: Int, from match: NSTextCheckingResult) -> String? {
            let range = match.range(at: group)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }

        var time: (hour: Int, minute: Int, range: NSRange)?
        if let expression = try? NSRegularExpression(
            pattern: #"(?i)\b(?:(at|в)\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#)
        {
            for match in expression.matches(
                in: input, range: NSRange(location: 0, length: source.length))
            {
                let rawMinute = capture(3, from: match).flatMap(Int.init) ?? 0
                guard capture(1, from: match) != nil || capture(4, from: match) != nil,
                    let rawHour = capture(2, from: match).flatMap(Int.init), rawMinute < 60
                else { continue }
                let meridiem = capture(4, from: match)?.lowercased()
                let hour: Int
                if let meridiem {
                    guard (1...12).contains(rawHour) else { continue }
                    hour = rawHour % 12 + (meridiem == "pm" ? 12 : 0)
                } else {
                    guard (0...23).contains(rawHour) else { continue }
                    hour = rawHour
                }
                time = (hour, rawMinute, match.range)
                break
            }
        }

        let dayExpression = try? NSRegularExpression(
            pattern: #"(?i)\b(today|tomorrow|сегодня|завтра)\b"#)
        let dayMatches =
            dayExpression?.matches(
                in: input, range: NSRange(location: 0, length: source.length)) ?? []
        let dayWords = dayMatches.compactMap { capture(1, from: $0)?.lowercased() }
        let tomorrow = dayWords.contains("tomorrow") || dayWords.contains("завтра")
        let today = dayWords.contains("today") || dayWords.contains("сегодня")
        let hasDay = tomorrow || today

        var removals = dayMatches.map(\.range)
        if let time { removals.append(time.range) }
        let titleSource = NSMutableString(string: input)
        for range in removals.sorted(by: { $0.location > $1.location }) {
            titleSource.replaceCharacters(in: range, with: " ")
        }
        let title = (titleSource as String)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        guard hasDay || time != nil else {
            return Self(title: title.isEmpty ? String(localized: "New Event") : title)
        }

        let baseDay = calendar.startOfDay(for: now)
        let eventDay = tomorrow ? calendar.date(byAdding: .day, value: 1, to: baseDay) ?? baseDay : baseDay
        let hour = time?.hour ?? (hasDay ? 9 : calendar.component(.hour, from: now))
        let minute = time?.minute ?? (hasDay ? 0 : calendar.component(.minute, from: now))
        var start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: eventDay) ?? now
        if !hasDay, time != nil, start < now {
            start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return Self(
            title: title.isEmpty ? String(localized: "New Event") : title, startDate: start)
    }

    static func label(duration minutes: Int, locale: Locale) -> String {
        Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }
}
