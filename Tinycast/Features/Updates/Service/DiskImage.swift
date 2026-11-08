import Foundation

/// A release ships as a DMG, which has to be mounted before its app can be read.
enum DiskImage {
    /// Mounts read-only at a private point, copies the app out, and always detaches behind itself.
    /// The copy has to land on the staging volume: `replaceItemAt` cannot cross volumes.
    static func stage(_ image: URL, into directory: URL) async throws -> URL {
        let mountPoint = directory.appendingPathComponent("mounted", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        let attach = try await ToolRunner.run(
            tool, [
                "attach", "-readonly", "-nobrowse", "-noverify", "-noautoopen",
                "-mountpoint", mountPoint.path, image.path,
            ])
        guard attach.succeeded else { throw UpdateFailure.mountFailed(attach.tail) }
        do {
            let staged = try await copyApp(from: mountPoint, into: directory)
            await detach(mountPoint)
            return staged
        } catch {
            await detach(mountPoint)
            throw error
        }
    }

    private static let tool = URL(fileURLWithPath: "/usr/bin/hdiutil")

    private static func copyApp(from mountPoint: URL, into directory: URL) async throws -> URL {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: mountPoint, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))
            ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdateFailure.noAppInImage
        }
        let staged = directory.appendingPathComponent(app.lastPathComponent)
        try? FileManager.default.removeItem(at: staged)
        // `ditto` carries the seal and the extended attributes a read-only volume cannot be moved off.
        let result = try await ToolRunner.run(
            URL(fileURLWithPath: "/usr/bin/ditto"), [app.path, staged.path])
        guard result.succeeded else { throw UpdateFailure.copyFailed(result.tail) }
        return staged
    }

    /// Best effort, and never fatal: a copy already made is installed whether or not the volume left.
    private static func detach(_ mountPoint: URL) async {
        for arguments in [["detach", mountPoint.path], ["detach", "-force", mountPoint.path]] {
            guard let result = try? await ToolRunner.run(tool, arguments, timeout: 30) else { continue }
            if result.succeeded { return }
        }
    }
}
