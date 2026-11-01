import Foundation

@main
struct ExtensionTerminalRequestTest {
    static func main() {
        var failures = 0
        func check(_ name: String, _ condition: Bool) {
            if condition {
                print("✓ \(name)")
            } else {
                failures += 1
                print("✗ \(name)")
            }
        }

        let suppliedArguments = ["--", "prod; echo unsafe", "host'quote"]
        let request = try? ExtensionTerminalRequest(executable: "ssh", arguments: suppliedArguments)
        let expectedRequest = try? ExtensionTerminalRequest(executable: "ssh", arguments: suppliedArguments)
        check(
            "preserves the executable and every argument boundary",
            request == expectedRequest)
        check(
            "rejects an empty executable",
            (try? ExtensionTerminalRequest(executable: "", arguments: [])) == nil)
        check(
            "rejects a NUL in the executable",
            (try? ExtensionTerminalRequest(executable: "ssh\0bad", arguments: [])) == nil)
        check(
            "rejects a NUL in arguments",
            (try? ExtensionTerminalRequest(executable: "ssh", arguments: ["bad\0arg"])) == nil)

        if failures > 0 { exit(1) }
    }
}
