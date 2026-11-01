import Foundation

struct BlockYAMLParser {
    enum Error: Swift.Error { case invalidDocument }
    private struct Line {
        let indentation: Int
        let text: String
    }

    private let lines: [Line]
    private var index = 0

    static func parse(_ input: String) throws -> Any {
        guard input.utf8.count <= 1_048_576 else { throw Error.invalidDocument }
        var parser = Self(lines: try tokenize(input))
        guard let first = parser.lines.first, first.indentation == 0 else {
            throw Error.invalidDocument
        }
        let value = try parser.block(indentation: 0, depth: 0)
        guard parser.index == parser.lines.count else { throw Error.invalidDocument }
        return value
    }

    private mutating func block(indentation: Int, depth: Int) throws -> Any {
        guard depth < 64, index < lines.count, lines[index].indentation == indentation else {
            throw Error.invalidDocument
        }
        if Self.isSequence(lines[index].text) {
            return try sequence(indentation: indentation, depth: depth)
        }
        if try Self.pair(lines[index].text) != nil {
            return try mapping(indentation: indentation, depth: depth)
        }
        let text = lines[index].text
        index += 1
        return try Self.scalar(text)
    }

    private mutating func mapping(indentation: Int, depth: Int, first: String? = nil) throws -> [String: Any] {
        var result: [String: Any] = [:]
        var pending = first
        while pending != nil || (index < lines.count && lines[index].indentation == indentation
            && !Self.isSequence(lines[index].text))
        {
            let text: String
            if let initial = pending {
                text = initial
                pending = nil
            } else {
                text = lines[index].text
                index += 1
            }
            guard let (keyText, valueText) = try Self.pair(text),
                let key = try Self.scalar(keyText) as? String, key != "<<", result[key] == nil
            else { throw Error.invalidDocument }
            result[key] = try value(valueText, parentIndentation: indentation, depth: depth + 1,
                                    allowsIndentlessSequence: true)
        }
        return result
    }

    private mutating func sequence(indentation: Int, depth: Int) throws -> [Any] {
        var result: [Any] = []
        while index < lines.count, lines[index].indentation == indentation,
            Self.isSequence(lines[index].text)
        {
            let remainder = lines[index].text.dropFirst()
            let spaces = remainder.prefix(while: { $0 == " " }).count
            let text = String(remainder.dropFirst(spaces))
            index += 1
            if try Self.pair(text) != nil {
                guard depth + 1 < 64 else { throw Error.invalidDocument }
                result.append(try mapping(indentation: indentation + 1 + spaces, depth: depth + 1,
                                          first: text))
            } else {
                result.append(try value(text, parentIndentation: indentation, depth: depth + 1,
                                        allowsIndentlessSequence: false))
            }
        }
        return result
    }

    private mutating func value(_ text: String, parentIndentation: Int, depth: Int,
                                allowsIndentlessSequence: Bool) throws -> Any {
        guard depth < 64 else { throw Error.invalidDocument }
        if !text.isEmpty {
            let parsed = try Self.scalar(text)
            guard index == lines.count || lines[index].indentation <= parentIndentation else {
                throw Error.invalidDocument
            }
            return parsed
        }
        if index < lines.count,
            lines[index].indentation > parentIndentation
                || (allowsIndentlessSequence && lines[index].indentation == parentIndentation
                    && Self.isSequence(lines[index].text))
        {
            return try block(indentation: lines[index].indentation, depth: depth)
        }
        return NSNull()
    }

    private static func scalar(_ text: String) throws -> Any {
        guard let first = text.first else { return NSNull() }
        if first == "\"" || first == "[" || first == "{" {
            return try JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
        }
        if first == "'" {
            guard text.count >= 2, text.last == "'" else { throw Error.invalidDocument }
            let content = Array(text.dropFirst().dropLast())
            var output = ""
            var position = 0
            while position < content.count {
                if content[position] == "'" {
                    guard position + 1 < content.count, content[position + 1] == "'" else {
                        throw Error.invalidDocument
                    }
                    position += 1
                }
                output.append(content[position])
                position += 1
            }
            return output
        }
        guard !"&*!|>%@`]}".contains(first), text != "-", !text.hasPrefix("- "),
            !text.hasPrefix("? "), !text.hasPrefix(": "), try pair(text) == nil
        else { throw Error.invalidDocument }
        switch text.lowercased() {
        case "null", "~": return NSNull()
        case "true": return true
        case "false": return false
        case ".inf", "+.inf", "-.inf", ".nan": throw Error.invalidDocument
        default: break
        }
        if text.range(of: #"^[+-]?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$"#,
                      options: .regularExpression) != nil {
            if !text.contains("."), !text.lowercased().contains("e") {
                if let integer = Int64(text) { return integer }
                if let integer = UInt64(text) { return integer }
                throw Error.invalidDocument
            }
            guard let number = Double(text), number.isFinite else { throw Error.invalidDocument }
            return number
        }
        if text.range(of: #"^[+-]?(?:[0-9]|\.[0-9])"#, options: .regularExpression) != nil,
            text.allSatisfy({ $0.isNumber || ".xXoObB_+-eE".contains($0) }) {
            throw Error.invalidDocument
        }
        return text
    }

    private static func pair(_ text: String) throws -> (String, String)? {
        let characters = Array(text)
        let separators = try syntax(characters).colons
        guard let position = separators.first else { return nil }
        let key = String(characters[..<position]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw Error.invalidDocument }
        return (key, String(characters[(position + 1)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isSequence(_ text: String) -> Bool {
        text == "-" || text.hasPrefix("- ")
    }

    private static func tokenize(_ input: String) throws -> [Line] {
        var result: [Line] = []
        var documentStarted = false
        var documentEnded = false
        for raw in input.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let indentation = raw.prefix(while: { $0 == " " }).count
            let body = raw.dropFirst(indentation)
            guard body.first != "\t" else { throw Error.invalidDocument }
            let characters = Array(body)
            let comment = try syntax(characters).comment ?? characters.count
            let text = String(characters[..<comment]).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            guard !documentEnded else { throw Error.invalidDocument }
            if text == "---", indentation == 0 {
                guard !documentStarted, result.isEmpty else { throw Error.invalidDocument }
                documentStarted = true
            } else if text == "...", indentation == 0 {
                guard !result.isEmpty else { throw Error.invalidDocument }
                documentEnded = true
            } else {
                documentStarted = true
                result.append(Line(indentation: indentation, text: text))
            }
        }
        return result
    }

    private static func syntax(_ characters: [Character]) throws -> (colons: [Int], comment: Int?) {
        var quote: Character?
        var brackets = [Character]()
        var colons: [Int] = []
        var position = 0
        while position < characters.count {
            let character = characters[position]
            if let active = quote {
                if active == "\"", character == "\\" {
                    position += 2
                    continue
                }
                if character == active {
                    if active == "'", position + 1 < characters.count, characters[position + 1] == "'" {
                        position += 2
                        continue
                    }
                    quote = nil
                }
            } else if character == "#", position == 0 || characters[position - 1].isWhitespace {
                return (colons, position)
            } else if (character == "\"" || character == "'"),
                position == 0 || characters[position - 1].isWhitespace || ":,[{".contains(characters[position - 1]) {
                quote = character
            } else if character == "[" || character == "{" {
                brackets.append(character)
            } else if character == "]" || character == "}" {
                guard brackets.popLast() == (character == "]" ? "[" : "{") else {
                    throw Error.invalidDocument
                }
            } else if character == ":", brackets.isEmpty,
                position + 1 == characters.count || characters[position + 1].isWhitespace {
                colons.append(position)
            }
            position += 1
        }
        guard quote == nil, brackets.isEmpty else { throw Error.invalidDocument }
        return (colons, nil)
    }
}
