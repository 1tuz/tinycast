enum ExtensionTerminalRequestError: Error {
    case invalidExecutable
    case invalidArguments
}

struct ExtensionTerminalRequest: Sendable, Equatable {
    let executable: String
    let arguments: [String]

    init(executable: String, arguments: [String]) throws {
        guard !executable.isEmpty, !executable.contains("\0") else {
            throw ExtensionTerminalRequestError.invalidExecutable
        }
        guard arguments.allSatisfy({ !$0.contains("\0") }) else {
            throw ExtensionTerminalRequestError.invalidArguments
        }
        self.executable = executable
        self.arguments = arguments
    }
}
