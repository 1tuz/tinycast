import Foundation

/// CSV / TSV → pasteable TSV. Spreadsheets go through `ClipboardXLSX`. Model stays Foundation-only.
nonisolated enum ClipboardTabularText {
    enum Failure: Error { case noTable, unreadable }

    static func isTabularFile(path: String) -> Bool {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "csv", "tsv", "tab", "xlsx", "xlsm": return true
        default: return false
        }
    }

    /// Normalize CSV/TSV bytes. `.xlsx` is handled by the caller via `ClipboardXLSX`.
    static func extract(from text: String, pathExtension: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.noTable }
        switch pathExtension.lowercased() {
        case "tsv", "tab":
            return bounded(normalizeNewlines(trimmed))
        case "csv":
            return bounded(csvToTSV(trimmed))
        default:
            throw Failure.noTable
        }
    }

    /// Escape one cell so tabs and newlines do not break the grid.
    static func escapeCell(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        text = text.replacingOccurrences(of: "\t", with: " ")
        text = text.replacingOccurrences(of: "\n", with: " ")
        return text.trimmingCharacters(in: .whitespaces)
    }

    static func tsv(fromRows rows: [[String]]) -> String {
        rows.map { $0.map(escapeCell).joined(separator: "\t") }.joined(separator: "\n")
    }

    private static let maximumBytes = 32_000

    private static func bounded(_ text: String) -> String {
        var prefix = text.utf8.prefix(max(0, maximumBytes))
        while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(bytes: prefix, encoding: .utf8) ?? ""
    }

    private static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func csvToTSV(_ text: String) -> String {
        tsv(fromRows: parseCSV(normalizeNewlines(text)))
    }

    /// Minimal RFC 4180: commas, quotes, and `""` escapes. Deliberately not a full CSV suite.
    private static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    }
                    inQuotes = false
                    i += 1
                    continue
                }
                field.append(c)
                i += 1
                continue
            }
            switch c {
            case "\"":
                inQuotes = true
                i += 1
            case ",":
                row.append(field)
                field = ""
                i += 1
            case "\n":
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                i += 1
            default:
                field.append(c)
                i += 1
            }
        }
        if inQuotes || !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
