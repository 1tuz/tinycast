import Foundation

/// Best-effort active-tab blocking for browsers that expose AppleScript tab URLs.
/// Not a DNS filter: background requests, private windows and Firefox/Zen are not controlled.
/// One detached worker executes osascript; UI and the voice loop never wait for Apple Events.
enum FocusWebsiteBlocker {
    private static let supportedBrowsers: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac"
    ]

    static func supports(_ bundleID: String) -> Bool { supportedBrowsers.contains(bundleID) }

    /// Return true if the active tab was replaced. The caller can show a brief HUD notice.
    static func enforce(browserID: String, domains: [String]) -> Bool {
        guard supports(browserID), !domains.isEmpty,
              !withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) else { return false }
        let safari = browserID == "com.apple.Safari"
        let tab = safari ? "current tab" : "active tab"
        let target = "\(tab) of front window"
        let prefix = "tell application id \"\(browserID)\"\n" +
            "if (count of windows) = 0 then return \"\"\n"
        guard let output = runAppleScript(prefix + "return URL of \(target)\nend tell"),
              let url = URL(string: output.trimmingCharacters(in: .whitespacesAndNewlines)),
              FocusDomain.shouldBlock(url, domains: domains)
        else { return false }

        guard !withUnsafeCurrentTask(body: { $0?.isCancelled ?? false }) else { return false }
        // Compare the tab URL again: the user may have switched tabs between the two calls.
        // Quote and backslash escaping prevent a website URL from becoming AppleScript source.
        let expectedURL = quote(url.absoluteString)
        let script = prefix +
            "if (URL of \(target) as text) is \(expectedURL) then\n" +
            "set URL of \(target) to \"about:blank\"\n" +
            "return \"blocked\"\nend if\nreturn \"\"\nend tell"
        return runAppleScript(script) == "blocked"
    }

    private static func quote(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        return "\"\(escaped)\""
    }

    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
