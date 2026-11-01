import AppKit
import Foundation

enum TerminalCommandLauncherError: LocalizedError, Equatable {
    case invalidCommand
    case writeFailed
    case openFailed

    var errorDescription: String? {
        switch self {
        case .invalidCommand: String(localized: "Terminal command arguments are invalid.")
        case .writeFailed: String(localized: "The Terminal command could not be prepared.")
        case .openFailed: String(localized: "Terminal could not be opened.")
        }
    }
}

enum TerminalCommandLauncher {
    static func scriptText(executable: String, arguments: [String]) throws -> String {
        let values = [executable] + arguments
        guard !executable.isEmpty, executable.hasPrefix("/"),
            values.allSatisfy({ !$0.contains("\0") })
        else { throw TerminalCommandLauncherError.invalidCommand }
        let command = values.map(shellQuote).joined(separator: " ")
        return "#!/bin/zsh\n/bin/rm -f -- \"$0\"\nexec \(command)\n"
    }

    @discardableResult
    static func open(executable: URL, arguments: [String]) throws -> URL {
        let url = executable.standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw TerminalCommandLauncherError.invalidCommand
        }
        let text = try scriptText(executable: url.path, arguments: arguments)
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-terminal-\(UUID().uuidString).command")
        guard FileManager.default.createFile(
            atPath: scriptURL.path, contents: Data(text.utf8), attributes: [.posixPermissions: 0o700])
        else { throw TerminalCommandLauncherError.writeFailed }
        guard NSWorkspace.shared.open(scriptURL) else {
            try? FileManager.default.removeItem(at: scriptURL)
            throw TerminalCommandLauncherError.openFailed
        }
        return scriptURL
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
