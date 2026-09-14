import Foundation

/// First-sheet TSV from an `.xlsx` / `.xlsm` via macOS `unzip`. No spreadsheet framework.
nonisolated enum ClipboardXLSX {
    enum Failure: Error { case unreadable, noTable }

    private static let maximumBytes = 32_000
    private static let maximumSheetBytes = 8_000_000

    static func extract(at url: URL) throws -> String {
        let shared = try? unzip(url, member: "xl/sharedStrings.xml")
        let strings = shared.map(parseSharedStrings) ?? []
        let rels = try unzip(url, member: "xl/_rels/workbook.xml.rels")
        let sheets = worksheetTargets(from: rels)
        guard !sheets.isEmpty else { throw Failure.noTable }
        var blocks: [String] = []
        for target in sheets {
            let path = target.hasPrefix("xl/") ? target : "xl/" + target
            let xml = try unzip(url, member: path)
            let rows = parseSheet(xml, strings: strings)
            let tsv = ClipboardTabularText.tsv(fromRows: rows)
            if !tsv.isEmpty { blocks.append(tsv) }
            let joined = blocks.joined(separator: "\n\n")
            if joined.utf8.count >= maximumBytes - 4 { return bounded(joined) }
        }
        guard !blocks.isEmpty else { throw Failure.noTable }
        return bounded(blocks.joined(separator: "\n\n"))
    }

    /// `unzip -p` ships with macOS; Foundation has no zip reader.
    private static func unzip(_ url: URL, member: String) throws -> String {
        let process = Process()
        let output = Pipe()
        let err = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, member]
        process.standardOutput = output
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.unreadable }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, data.count <= maximumSheetBytes,
            let text = String(data: data, encoding: .utf8)
        else { throw Failure.unreadable }
        return text
    }

    private static func worksheetTargets(from rels: String) -> [String] {
        var targets: [String] = []
        var search = rels[...]
        while let relStart = search.range(of: "<Relationship") {
            search = search[relStart.lowerBound...]
            guard let relEnd = search.firstIndex(of: ">") else { break }
            let tag = search[...relEnd]
            search = search[search.index(after: relEnd)...]
            guard String(tag).contains("/relationships/worksheet"),
                let target = attribute(named: "Target", in: tag)
            else { continue }
            targets.append(target)
        }
        return targets
    }

    private static func parseSharedStrings(_ xml: String) -> [String] {
        var strings: [String] = []
        var search = xml[...]
        while let si = search.range(of: "<si") {
            search = search[si.upperBound...]
            guard let close = search.range(of: "</si>") else { break }
            let body = search[..<close.lowerBound]
            strings.append(sharedStringText(String(body)))
            search = search[close.upperBound...]
        }
        return strings
    }

    private static func sharedStringText(_ body: String) -> String {
        var parts: [String] = []
        var search = body[...]
        while let open = search.range(of: "<t") {
            search = search[open.upperBound...]
            guard let gt = search.firstIndex(of: ">") else { break }
            search = search[search.index(after: gt)...]
            guard let end = search.range(of: "</t>") else { break }
            parts.append(decodeXML(String(search[..<end.lowerBound])))
            search = search[end.upperBound...]
        }
        return parts.joined()
    }

    private static func parseSheet(_ xml: String, strings: [String]) -> [[String]] {
        var rows: [[String]] = []
        var search = xml[...]
        while let rowOpen = search.range(of: "<row") {
            search = search[rowOpen.upperBound...]
            guard let rowStart = search.firstIndex(of: ">") else { break }
            search = search[search.index(after: rowStart)...]
            let rowBody: Substring
            if let selfClose = search.range(of: "/>"),
                search.firstIndex(of: "<").map({ $0 >= selfClose.lowerBound }) ?? true
            {
                // empty row written as <row .../>
                rowBody = ""
                search = search[selfClose.upperBound...]
            } else if let end = search.range(of: "</row>") {
                rowBody = search[..<end.lowerBound]
                search = search[end.upperBound...]
            } else {
                break
            }
            rows.append(parseRow(String(rowBody), strings: strings))
        }
        return rows
    }

    private static func parseRow(_ body: String, strings: [String]) -> [String] {
        var cells: [(col: Int, text: String)] = []
        var search = body[...]
        while let cellOpen = search.range(of: "<c ") ?? search.range(of: "<c>") {
            search = search[cellOpen.lowerBound...]
            guard let tagEnd = search.firstIndex(of: ">") else { break }
            let attrs = String(search[..<tagEnd])
            let selfClosing = attrs.hasSuffix("/") || search[tagEnd...].hasPrefix("/>")
            let ref = attribute(named: "r", in: attrs[...]) ?? ""
            let type = attribute(named: "t", in: attrs[...])
            let col = columnIndex(ref)
            if selfClosing {
                cells.append((col, ""))
                search = search[search.index(after: tagEnd)...]
                continue
            }
            search = search[search.index(after: tagEnd)...]
            guard let cellEnd = search.range(of: "</c>") else { break }
            let content = String(search[..<cellEnd.lowerBound])
            search = search[cellEnd.upperBound...]
            cells.append((col, cellText(content, type: type, strings: strings)))
        }
        guard let maxCol = cells.map(\.col).max() else { return [] }
        var row = Array(repeating: "", count: maxCol)
        for cell in cells where cell.col >= 1 && cell.col <= maxCol {
            row[cell.col - 1] = cell.text
        }
        return row
    }

    private static func cellText(_ content: String, type: String?, strings: [String]) -> String {
        switch type {
        case "s":
            guard let raw = tagValue("v", in: content), let index = Int(raw),
                strings.indices.contains(index)
            else { return "" }
            return strings[index]
        case "inlineStr", "str":
            if let t = tagValue("t", in: content) { return decodeXML(t) }
            return decodeXML(content)
        case "b":
            return tagValue("v", in: content) == "1" ? "TRUE" : "FALSE"
        default:
            return tagValue("v", in: content).map(decodeXML) ?? ""
        }
    }

    private static func tagValue(_ name: String, in xml: String) -> String? {
        guard let open = xml.range(of: "<\(name)") else { return nil }
        var rest = xml[open.upperBound...]
        guard let gt = rest.firstIndex(of: ">") else { return nil }
        if rest[..<gt].hasSuffix("/") { return "" }
        rest = rest[rest.index(after: gt)...]
        guard let end = rest.range(of: "</\(name)>") else { return nil }
        return String(rest[..<end.lowerBound])
    }

    private static func attribute(named name: String, in fragment: Substring) -> String? {
        let patterns = ["\(name)=\"", "\(name)='"]
        for pattern in patterns {
            guard let start = fragment.range(of: pattern) else { continue }
            let quote = pattern.last!
            var rest = fragment[start.upperBound...]
            guard let end = rest.firstIndex(of: quote) else { continue }
            return String(rest[..<end])
        }
        return nil
    }

    /// `A` → 1, `B` → 2, `AA` → 27.
    private static func columnIndex(_ reference: String) -> Int {
        var value = 0
        for scalar in reference.unicodeScalars {
            guard (65...90).contains(scalar.value) || (97...122).contains(scalar.value) else { break }
            let digit = Int(scalar.value & 0x1f)
            value = value * 26 + digit
        }
        return max(value, 1)
    }

    private static func decodeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func bounded(_ text: String) -> String {
        var prefix = text.utf8.prefix(max(0, maximumBytes))
        while !prefix.isEmpty, String(bytes: prefix, encoding: .utf8) == nil {
            prefix = prefix.dropLast()
        }
        return String(bytes: prefix, encoding: .utf8) ?? ""
    }
}
