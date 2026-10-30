import Foundation
import Observation

struct SmartFolder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let query: String
    let filter: FileSearchFilter

    var title: String {
        let name =
            query.isEmpty
            ? "Recently Used"
            : String(query.prefix(80)) + (query.count > 80 ? "…" : "")
        return filter == .all ? name : "\(name) · \(filter.title)"
    }
}

/// Saved searches retain only the query and type; current scopes and exclusions still apply.
@MainActor
@Observable
final class SmartFolderStore {
    private(set) var folders: [SmartFolder] = []
    private let fileURL: URL
    @ObservationIgnored private var isLoaded = false
    private static let limit = 50
    private static let queryByteLimit = 1_024

    init(fileURL: URL? = nil) {
        self.fileURL =
            fileURL
            ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.tinycast.app", isDirectory: true)
            .appendingPathComponent("file-search-smart-folders.json")
    }

    func load() throws {
        guard !isLoaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isLoaded = true
            return
        }
        let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
        let decoded = try JSONDecoder().decode([SmartFolder].self, from: Data(contentsOf: fileURL))
        guard decoded.count <= Self.limit, Set(decoded.map(\.id)).count == decoded.count,
            decoded.allSatisfy({
                $0.query.utf8.count <= Self.queryByteLimit
                    && $0.query == $0.query.trimmingCharacters(in: .whitespacesAndNewlines)
            })
        else { throw CocoaError(.fileReadCorruptFile) }
        folders = decoded
        isLoaded = true
    }

    func folder(query: String, filter: FileSearchFilter) -> SmartFolder? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return folders.first { $0.query == query && $0.filter == filter }
    }

    func save(query: String, filter: FileSearchFilter) throws {
        try load()
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.utf8.count <= Self.queryByteLimit else { throw SaveError.queryTooLong }
        guard folder(query: query, filter: filter) == nil else { return }
        guard folders.count < Self.limit else { throw SaveError.tooManyFolders }
        try persist([SmartFolder(id: UUID(), query: query, filter: filter)] + folders)
    }

    func remove(id: UUID) throws {
        try load()
        let retained = folders.filter { $0.id != id }
        if retained.count != folders.count { try persist(retained) }
    }

    private func persist(_ snapshot: [SmartFolder]) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        folders = snapshot
    }

    enum SaveError: LocalizedError {
        case queryTooLong
        case tooManyFolders

        var errorDescription: String? {
            switch self {
            case .queryTooLong: return "This search is too long to save."
            case .tooManyFolders: return "Remove a Smart Folder before saving another. The limit is 50."
            }
        }
    }
}
