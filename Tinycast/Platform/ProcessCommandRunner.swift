import Darwin
import Foundation

enum ProcessOutputStream: Sendable, Equatable {
    case stdout
    case stderr
}

struct ProcessCommandResult: Sendable, Equatable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

enum ProcessCommandError: Error, Sendable, Equatable {
    case launchFailed(String)
    case timedOut
    case outputLimitExceeded(stream: ProcessOutputStream)
    case cancelled
}

enum ProcessCommandRunner {
    private static let queue = DispatchQueue(
        label: "com.tinycast.process-command", qos: .userInitiated, attributes: .concurrent)
    private static let readSize = 16 * 1024
    private static let pollMilliseconds: Int32 = 25
    private static let stopGrace: Duration = .milliseconds(500)

    nonisolated static func run(
        executable: URL, arguments: [String], environment: [String: String]? = nil,
        currentDirectory: URL? = nil, timeout: Duration,
        maxStdoutBytes: Int, maxStderrBytes: Int
    ) async throws -> ProcessCommandResult {
        let cancellation = Cancellation()
        let result: ProcessCommandResult = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do {
                        continuation.resume(
                            returning: try execute(
                                executable: executable, arguments: arguments,
                                environment: environment, currentDirectory: currentDirectory,
                                timeout: timeout, maxStdoutBytes: maxStdoutBytes,
                                maxStderrBytes: maxStderrBytes, cancellation: cancellation))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellation.set()
        }
        if Task.isCancelled { throw ProcessCommandError.cancelled }
        return result
    }

    nonisolated private static func execute(
        executable: URL, arguments: [String], environment: [String: String]?,
        currentDirectory: URL?, timeout: Duration,
        maxStdoutBytes: Int, maxStderrBytes: Int, cancellation: Cancellation
    ) throws -> ProcessCommandResult {
        if cancellation.isSet { throw ProcessCommandError.cancelled }
        guard valid(
            executable: executable, arguments: arguments, environment: environment,
            currentDirectory: currentDirectory)
        else {
            throw ProcessCommandError.launchFailed(POSIXError(.EINVAL).localizedDescription)
        }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors
        let exit: ProcessExit
        do {
            try nonblocking(output.fileHandleForReading.fileDescriptor)
            try nonblocking(errors.fileHandleForReading.fileDescriptor)
            exit = try process.runObservingExit()
        } catch {
            throw ProcessCommandError.launchFailed(error.localizedDescription)
        }
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        return try capture(
            process: process, exit: exit,
            outputDescriptor: output.fileHandleForReading.fileDescriptor,
            errorDescriptor: errors.fileHandleForReading.fileDescriptor,
            timeout: timeout, maxStdoutBytes: maxStdoutBytes,
            maxStderrBytes: maxStderrBytes, cancellation: cancellation)
    }

    nonisolated private static func capture(
        process: Process, exit: ProcessExit, outputDescriptor: Int32, errorDescriptor: Int32,
        timeout: Duration, maxStdoutBytes: Int, maxStderrBytes: Int,
        cancellation: Cancellation
    ) throws -> ProcessCommandResult {
        let deadline = ContinuousClock.now + timeout
        var output = Capture(maximum: max(0, maxStdoutBytes))
        var errors = Capture(maximum: max(0, maxStderrBytes))
        var buffer = [UInt8](repeating: 0, count: readSize)
        var failure: ProcessCommandError?
        var stoppingSince: ContinuousClock.Instant?
        while true {
            let now = ContinuousClock.now
            if failure == nil {
                if cancellation.isSet {
                    failure = .cancelled
                } else if process.isRunning, now >= deadline {
                    failure = .timedOut
                }
            }
            if failure != nil, process.isRunning {
                if let stoppingSince {
                    if now - stoppingSince >= stopGrace { kill(process.processIdentifier, SIGKILL) }
                } else {
                    stoppingSince = now
                    process.terminate()
                }
            }
            if output.ended, errors.ended, !process.isRunning { break }
            var descriptors = [
                pollfd(fd: output.ended ? -1 : outputDescriptor, events: Int16(POLLIN), revents: 0),
                pollfd(fd: errors.ended ? -1 : errorDescriptor, events: Int16(POLLIN), revents: 0),
            ]
            let ready = poll(&descriptors, nfds_t(descriptors.count), pollMilliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                if failure == nil { failure = .launchFailed(POSIXError.current.localizedDescription) }
                output.ended = true
                errors.ended = true
                continue
            }
            if ready == 0, !process.isRunning { break }
            do {
                if descriptors[0].revents != 0,
                    try output.read(from: outputDescriptor, buffer: &buffer), failure == nil
                {
                    failure = .outputLimitExceeded(stream: .stdout)
                }
                if descriptors[1].revents != 0,
                    try errors.read(from: errorDescriptor, buffer: &buffer), failure == nil
                {
                    failure = .outputLimitExceeded(stream: .stderr)
                }
            } catch {
                if failure == nil { failure = .launchFailed(error.localizedDescription) }
            }
        }
        exit.wait()
        if let failure { throw failure }
        if cancellation.isSet { throw ProcessCommandError.cancelled }
        return ProcessCommandResult(
            stdout: output.data, stderr: errors.data, exitCode: process.terminationStatus)
    }

    nonisolated private static func valid(
        executable: URL, arguments: [String], environment: [String: String]?,
        currentDirectory: URL?
    ) -> Bool {
        executable.isFileURL && !executable.path.utf8.contains(0)
            && arguments.allSatisfy { !$0.utf8.contains(0) }
            && (currentDirectory.map { $0.isFileURL && !$0.path.utf8.contains(0) } ?? true)
            && (environment?.allSatisfy {
                !$0.key.isEmpty && !$0.key.contains("=") && !$0.key.utf8.contains(0)
                    && !$0.value.utf8.contains(0)
            } ?? true)
    }

    nonisolated private static func nonblocking(_ descriptor: Int32) throws {
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw POSIXError.current
        }
    }

    private struct Capture {
        let maximum: Int
        var data = Data()
        var ended = false

        mutating func read(from descriptor: Int32, buffer: inout [UInt8]) throws -> Bool {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count == 0 {
                ended = true
                return false
            }
            if count < 0 {
                if errno == EAGAIN || errno == EINTR { return false }
                ended = true
                throw POSIXError.current
            }
            let available = maximum - data.count
            data.append(contentsOf: buffer.prefix(min(count, available)))
            return count > available
        }
    }

    /// The lock protects cancellation; Process and pipe buffers stay on one worker queue.
    private final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isSet: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func set() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }
}

extension POSIXError {
    fileprivate static var current: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
