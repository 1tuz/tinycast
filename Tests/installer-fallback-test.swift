import Foundation

/// Regression: an update over a bundle the current account cannot write *inside*
/// (brew on another account, a moved copy) must not dead-end in the
/// "no permission to save in /Applications" dialog. `replaceItemAt` fails there;
/// the installer's rename-aside fallback must complete the swap.
@main
@MainActor
struct InstallerFallbackTest {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            print("ok  \(message)")
        } else {
            print("FAIL \(message)")
            failures += 1
        }
    }

    static var failures = 0

    static func main() {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("installer-fallback-\(UUID().uuidString)", isDirectory: true)
        let old = root.appendingPathComponent("Tinycast.app")
        let stagedRoot = root.appendingPathComponent("staged", isDirectory: true)
        let staged = stagedRoot.appendingPathComponent("Tinycast.app")
        for directory in [old.appendingPathComponent("Contents/MacOS"), staged] {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try? Data("old".utf8).write(to: old.appendingPathComponent("Contents/MacOS/Tinycast"))
        try? Data("new".utf8).write(to: staged.appendingPathComponent("marker"))
        defer { try? fm.removeItem(at: root) }

        // The reported state: the running bundle's directories are not writable,
        // while the parent (like /Applications for an admin) is.
        for directory in [
            old, old.appendingPathComponent("Contents"),
            old.appendingPathComponent("Contents/MacOS"),
        ] {
            try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        }

        // The fix under test, extracted from UpdateInstaller's private fallback.
        let aside = root.appendingPathComponent("Tinycast.app.pre-update")
        do {
            // Unmodified behavior: replaceItemAt refuses, exactly as in the dialog.
            var directFailed = false
            do {
                _ = try fm.replaceItemAt(
                    old, withItemAt: staged, options: .usingNewMetadataOnly)
            } catch {
                directFailed = true
            }
            expect(directFailed, "replaceItemAt fails on an unwritable old bundle")

            try? fm.trashItem(at: aside, resultingItemURL: nil)
            try fm.moveItem(at: old, to: aside)
            try fm.moveItem(at: staged, to: old)
            expect(
                fm.fileExists(atPath: old.appendingPathComponent("marker").path),
                "the staged bundle takes the installed name")
            expect(
                fm.fileExists(atPath: aside.appendingPathComponent("Contents/MacOS/Tinycast").path),
                "the previous bundle is preserved for rollback")
        } catch {
            expect(false, "fallback failed: \(error.localizedDescription)")
        }

        // Rollback path: a failed second move restores the old bundle to its name.
        let missing = stagedRoot.appendingPathComponent("missing", isDirectory: true)
        do {
            try fm.moveItem(at: old, to: aside)
            try fm.moveItem(at: missing, to: old)
            expect(false, "moving a missing bundle must throw")
        } catch {
            if !fm.fileExists(atPath: old.path) {
                try? fm.moveItem(at: aside, to: old)
            }
            expect(
                fm.fileExists(atPath: old.appendingPathComponent("marker").path),
                "rollback re-installs the previous bundle when the swap fails")
        }

        print(failures == 0 ? "installer fallback: passed" : "installer fallback: FAILED")
        if failures > 0 { exit(1) }
    }
}
