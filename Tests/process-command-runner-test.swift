import Darwin
import Foundation

@main
@MainActor
struct ProcessCommandRunnerTests {
    private static var passes = 0
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async {
        await argumentsArriveUnchanged()
        await outputAndExitStatusAreSeparate()
        await bothPipesAreDrained()
        await environmentAndDirectoryAreExplicit()
        await eachStreamHasItsOwnLimit()
        await zeroLimitsAllowSilentCommands()
        await launchFailuresAreTyped()
        await timeoutStopsAnUncooperativeChild()
        await cancellationStopsTheChild()
        await cancellationBeforeLaunchIsTyped()
        print("Process command runner: \(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func argumentsArriveUnchanged() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appending(path: "should-not-exist")
        let arguments = [
            "", "a b", "single'quote", "$HOME", "`touch \(marker.path)`",
            "; touch \(marker.path);", "first\nsecond", "Unicode: 雪 ☃",
        ]
        do {
            let result = try await run("/usr/bin/printf", ["%s\\0"] + arguments)
            var actual = result.stdout.split(separator: 0, omittingEmptySubsequences: false)
            if actual.last?.isEmpty == true { actual.removeLast() }
            check(actual.compactMap { String(bytes: $0, encoding: .utf8) } == arguments, "argv boundaries survive")
            check(!FileManager.default.fileExists(atPath: marker.path), "argv text never becomes shell source")
        } catch {
            check(false, "argv recorder succeeds: \(error)")
        }
    }

    private static func outputAndExitStatusAreSeparate() async {
        do {
            let result = try await run("/bin/sh", ["-c", "printf 'out'; printf 'err' >&2; exit 7"])
            check(result.stdout == Data("out".utf8), "stdout is complete")
            check(result.stderr == Data("err".utf8), "stderr is separate")
            check(result.exitCode == 7, "nonzero exit remains a result")
            let binary = try await run("/usr/bin/printf", ["\\001\\002\\377"])
            check(binary.stdout == Data([1, 2, 255]), "binary output is preserved")
        } catch {
            check(false, "capture succeeds: \(error)")
        }
    }

    private static func bothPipesAreDrained() async {
        let script = """
            i=0
            while [ "$i" -lt 4096 ]; do
                printf 'stdout-line-012345678901234567890\n'
                printf 'stderr-line-012345678901234567890\n' >&2
                i=$((i + 1))
            done
            """
        do {
            let result = try await run("/bin/sh", ["-c", script])
            let expectedOutput = String(repeating: "stdout-line-012345678901234567890\n", count: 4096)
            let expectedErrors = String(repeating: "stderr-line-012345678901234567890\n", count: 4096)
            check(result.stdout == Data(expectedOutput.utf8), "large stdout does not block stderr")
            check(result.stderr == Data(expectedErrors.utf8), "large stderr does not block stdout")
        } catch {
            check(false, "two full pipes finish: \(error)")
        }
    }

    private static func environmentAndDirectoryAreExplicit() async {
        let root = temporaryDirectory().resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let result = try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '%s\\n' \"$RUNNER_FIXTURE\"; pwd"],
                environment: ["RUNNER_FIXTURE": "injected value"], currentDirectory: root,
                timeout: .seconds(5), maxStdoutBytes: 1024, maxStderrBytes: 1024)
            guard let text = String(data: result.stdout, encoding: .utf8) else {
                check(false, "fixture output is UTF-8")
                return
            }
            let lines = text.split(separator: "\n")
            check(lines.first == "injected value", "environment reaches the child")
            check(
                lines.count == 2 && canonicalPath(String(lines[1])) == canonicalPath(root.path),
                "the child uses the requested working directory")
        } catch {
            check(false, "explicit process environment succeeds: \(error)")
        }
    }

    private static func eachStreamHasItsOwnLimit() async {
        await expectFailure(.outputLimitExceeded(stream: .stdout), "stdout cap stops the child") {
            try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: ["output"],
                timeout: .seconds(5), maxStdoutBytes: 32, maxStderrBytes: 1024)
        }
        await expectFailure(.outputLimitExceeded(stream: .stderr), "stderr cap stops the child") {
            try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "while :; do printf 'error\\n' >&2; done"],
                timeout: .seconds(5), maxStdoutBytes: 1024, maxStderrBytes: 32)
        }
        await expectFailure(.outputLimitExceeded(stream: .stdout), "one byte exceeds a zero stdout cap") {
            try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["x"],
                timeout: .seconds(5), maxStdoutBytes: 0, maxStderrBytes: 0)
        }
        do {
            let result = try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf 'out'; printf 'err' >&2"],
                timeout: .seconds(5), maxStdoutBytes: 3, maxStderrBytes: 3)
            check(result.stdout.count == 3 && result.stderr.count == 3, "output exactly at both caps succeeds")
        } catch {
            check(false, "exact-cap output succeeds: \(error)")
        }
    }

    private static func zeroLimitsAllowSilentCommands() async {
        do {
            let result = try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/true"), arguments: [],
                timeout: .seconds(5), maxStdoutBytes: 0, maxStderrBytes: 0)
            check(result.stdout.isEmpty && result.stderr.isEmpty && result.exitCode == 0, "silent output fits zero caps")
        } catch {
            check(false, "silent child succeeds: \(error)")
        }
    }

    private static func launchFailuresAreTyped() async {
        do {
            _ = try await run("/does/not/exist/tinycast-runner", [])
            check(false, "a missing executable throws")
        } catch ProcessCommandError.launchFailed(let reason) {
            check(!reason.isEmpty, "launch failure retains an OS reason")
        } catch {
            check(false, "launch failure has the expected type: \(error)")
        }
    }

    private static func timeoutStopsAnUncooperativeChild() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appending(path: "pid")
        let started = ContinuousClock.now
        await expectFailure(.timedOut, "timeout remains distinct from exit") {
            try await ProcessCommandRunner.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf '%s' \"$$\" > \"$1\"; trap '' TERM; exec /bin/sleep 30", "fixture", pidFile.path],
                timeout: .milliseconds(100), maxStdoutBytes: 1024, maxStderrBytes: 1024)
        }
        check(ContinuousClock.now - started < .seconds(3), "timeout escalates without a long wait")
        if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text) {
            check(kill(pid, 0) == -1 && errno == ESRCH, "timed-out child has exited")
        } else {
            check(false, "timeout fixture wrote its pid")
        }
    }

    private static func cancellationStopsTheChild() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pidFile = root.appending(path: "pid")
        let started = ContinuousClock.now
        let task = Task {
            try await run(
                "/bin/sh",
                ["-c", "printf '%s' \"$$\" > \"$1\"; trap '' TERM; exec /bin/sleep 30", "fixture", pidFile.path],
                timeout: .seconds(30))
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            check(false, "cancelled task throws")
        } catch let error as ProcessCommandError {
            check(error == .cancelled, "cancellation has a distinct error")
        } catch {
            check(false, "cancellation is typed: \(error)")
        }
        check(ContinuousClock.now - started < .seconds(3), "cancellation finishes promptly")
        if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = Int32(text) {
            check(kill(pid, 0) == -1 && errno == ESRCH, "cancelled child has exited")
        } else {
            check(false, "cancellation fixture wrote its pid")
        }
    }

    private static func cancellationBeforeLaunchIsTyped() async {
        let task = Task {
            try await run("/bin/sleep", ["30"], timeout: .seconds(30))
        }
        task.cancel()
        do {
            _ = try await task.value
            check(false, "pre-cancelled operation throws")
        } catch let error as ProcessCommandError {
            check(error == .cancelled, "pre-launch cancellation uses the same error")
        } catch {
            check(false, "pre-launch cancellation is typed: \(error)")
        }
    }

    private static func expectFailure(
        _ expected: ProcessCommandError, _ message: String,
        operation: () async throws -> ProcessCommandResult
    ) async {
        do {
            _ = try await operation()
            check(false, message)
        } catch let error as ProcessCommandError {
            check(error == expected, message)
        } catch {
            check(false, "\(message): \(error)")
        }
    }

    private static func run(
        _ executable: String, _ arguments: [String], timeout: Duration = .seconds(10)
    ) async throws -> ProcessCommandResult {
        try await ProcessCommandRunner.run(
            executable: URL(fileURLWithPath: executable), arguments: arguments, timeout: timeout,
            maxStdoutBytes: 1024 * 1024, maxStderrBytes: 1024 * 1024)
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "process-runner-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            check(false, "temporary directory can be created: \(error)")
        }
        return url
    }

    private static func canonicalPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
