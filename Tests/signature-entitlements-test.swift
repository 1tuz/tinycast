import Foundation

/// Regression: an installed or staged Tinycast.app must be signed with the hardened-runtime
/// entitlements each Info.plist usage string needs. Without them tccd refuses the prompt
/// outright — the request resolves as denied in milliseconds, the app never appears in
/// Privacy & Security (microphone, calendar), and no dialog can recover it.
@main
@MainActor
struct SignatureEntitlementsTest {
    static var failures = 0

    static func fail(_ message: String) {
        print("FAIL \(message)")
        failures += 1
    }

    static func ok(_ message: String) {
        print("ok  \(message)")
    }

    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        // Default: whatever build is installed; a caller passes an explicit .app path.
        let app = arguments.first
            ?? ("/Applications/Tinycast.app" as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: app) else {
            print("ok  no Tinycast.app at \(app) — nothing to verify")
            exit(0)
        }

        // The hardened-runtime entitlement each usage string needs before tccd shows its prompt.
        let pairs: [(usage: String, entitlement: String)] = [
            ("NSAppleEventsUsageDescription", "com.apple.security.automation.apple-events"),
            ("NSCameraUsageDescription", "com.apple.security.device.camera"),
            ("NSCalendarsFullAccessUsageDescription", "com.apple.security.personal-information.calendars"),
            ("NSRemindersFullAccessUsageDescription", "com.apple.security.personal-information.calendars"),
            ("NSMicrophoneUsageDescription", "com.apple.security.device.audio-input"),
        ]

        let entitlements = dumpEntitlements(app)
        for (usage, entitlement) in pairs {
            let info = app + "/Contents/Info.plist"
            guard declared(info, usage) else { continue }
            guard plistFlag(entitlements, key: entitlement) else {
                fail("\(app): \(usage) is declared but \(entitlement) is missing from the signature")
                continue
            }
            ok("\(usage) is backed by \(entitlement)")
        }

        exit(failures == 0 ? 0 : 1)
    }

    static func dumpEntitlements(_ app: String) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", "-", "--xml", app]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
    }

    static func declared(_ infoPlist: String, _ key: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        process.arguments = ["-c", "Print :\(key)", infoPlist]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// True when the XML plist codesign emitted sets `key` to true.
    static func plistFlag(_ xml: Data, key: String) -> Bool {
        guard let plist = try? PropertyListDecoder().decode([String: Bool].self, from: xml)
        else { return false }
        return plist[key] == true
    }
}
