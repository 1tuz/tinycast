import Foundation

struct UpdateInstaller: Sendable {
    enum Phase: Sendable, Equatable {
        case downloading(received: Int64, expected: Int64)
        case mounting
        case verifying
        case replacing

        var message: String {
            switch self {
            case .downloading(let received, let expected):
                return String(localized: "Downloading… \(Self.size(received)) of \(Self.size(expected))")
            case .mounting: return String(localized: "Mounting the update…")
            case .verifying: return String(localized: "Verifying…")
            case .replacing: return String(localized: "Replacing Tinycast…")
            }
        }

        /// Only the download knows how far along it is; the rest are short, opaque steps.
        var fraction: Double? {
            guard case .downloading(let received, let expected) = self, expected > 0 else {
                return nil
            }
            return min(1, Double(received) / Double(expected))
        }

        private static func size(_ bytes: Int64) -> String {
            bytes.formatted(.byteCount(style: .file))
        }
    }

    let bundleURL: URL
    let stagingDirectory: URL

    func install(
        _ release: AvailableRelease, onProgress: @escaping @Sendable (Phase) -> Void
    ) async throws {
        try? FileManager.default.createDirectory(
            at: stagingDirectory, withIntermediateDirectories: true)
        let image = stagingDirectory.appendingPathComponent("\(release.tag).dmg")
        let expanded = stagingDirectory.appendingPathComponent("expanded", isDirectory: true)
        try? FileManager.default.removeItem(at: expanded)

        onProgress(.downloading(received: 0, expected: release.assetSize))
        for try await event in UpdateDownloader.download(release, to: image) {
            guard case .progress(let received, let expected) = event else { continue }
            onProgress(.downloading(received: received, expected: expected))
        }

        onProgress(.mounting)
        let staged = try await DiskImage.stage(image, into: expanded)

        onProgress(.verifying)
        try verify(staged, is: release)

        onProgress(.replacing)
        do {
            _ = try FileManager.default.replaceItemAt(
                bundleURL, withItemAt: staged, options: .usingNewMetadataOnly)
        } catch {
            // A foreign-uid install blocks the metadata rewrite replaceItemAt does inside
            // the old bundle; parent-directory renames still work on an admin-writable /Applications.
            try replaceByRenamingAside(staged: staged)
        }
        try? FileManager.default.removeItem(at: expanded)
    }

    /// Trash, not delete: the old copy is the only rollback if the new one is broken.
    private func replaceByRenamingAside(staged: URL) throws {
        let aside = bundleURL.deletingLastPathComponent()
            .appendingPathComponent(bundleURL.lastPathComponent + ".pre-update")
        let fm = FileManager.default
        try? fm.trashItem(at: aside, resultingItemURL: nil)
        do {
            try fm.moveItem(at: bundleURL, to: aside)
            try fm.moveItem(at: staged, to: bundleURL)
        } catch {
            // Put the old copy back before surfacing the failure; a half-swapped
            // /Applications entry is worse than no update.
            if !fm.fileExists(atPath: bundleURL.path) {
                try? fm.moveItem(at: aside, to: bundleURL)
            }
            throw UpdateFailure.replaceFailed(error.localizedDescription)
        }
    }

    private func verify(_ staged: URL, is release: AvailableRelease) throws {
        if Quarantine.isSet(on: staged) { Quarantine.clear(from: staged) }
        // Refuse rather than install something the user would then have to unquarantine by hand.
        guard !Quarantine.isSet(on: staged) else { throw UpdateFailure.quarantined }

        let info = Self.info(at: staged)
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateFailure.bundleMismatch
        }
        let found = info?["CFBundleShortVersionString"] as? String
        guard found == release.version.description else {
            throw UpdateFailure.versionMismatch(
                expected: release.version.description, found: found ?? String(localized: "unknown"))
        }
        guard BundleSignature.isTrusted(staged) else { throw UpdateFailure.identityMismatch }
    }

    /// Off disk, not through `Bundle`, whose cache would answer for the old copy.
    private static func info(at bundleURL: URL) -> [String: Any]? {
        let url = bundleURL.appending(components: "Contents", "Info.plist")
        guard let data = try? Data(contentsOf: url),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return nil }
        return plist as? [String: Any]
    }
}
