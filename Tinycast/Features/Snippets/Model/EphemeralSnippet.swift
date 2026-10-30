import Foundation
import Observation

struct EphemeralSnippet: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let expiresAt: Date

    init(id: UUID, text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        expiresAt = createdAt.addingTimeInterval(24 * 60 * 60)
    }

    var entryID: String { "ephemeral-ai:" + id.uuidString.lowercased() }

    var name: String {
        let line =
            text.split(whereSeparator: \.isNewline).lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "AI Response"
        return String(line.prefix(80))
    }
}

/// Temporary AI replies stay separate from authored snippets and keyword expansion.
@MainActor
@Observable
final class EphemeralSnippetStore {
    private static let limit = 100
    private(set) var items: [EphemeralSnippet] = []
    private let fileURL: URL
    private let now: () -> Date
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var expirationTask: Task<Void, Never>?

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now
    }

    isolated deinit {
        expirationTask?.cancel()
    }

    func loadAndPrune() throws {
        try load()
        let timestamp = now()
        let retained = Array(items.filter { $0.expiresAt > timestamp }.prefix(Self.limit))
        if retained.count != items.count { try persist(retained) }
        scheduleExpiration()
    }

    func capture(id: UUID, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try load()
        guard !items.contains(where: { $0.id == id }) else { return }
        let timestamp = now()
        var updated = items.filter { $0.expiresAt > timestamp }
        updated.insert(EphemeralSnippet(id: id, text: text, createdAt: timestamp), at: 0)
        try persist(Array(updated.prefix(Self.limit)))
        scheduleExpiration()
    }

    func remove(id: UUID) throws {
        try load()
        let updated = items.filter { $0.id != id }
        if updated.count != items.count {
            try persist(updated)
            scheduleExpiration()
        }
    }

    private func load() throws {
        guard !isLoaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            isLoaded = true
            return
        }
        let decoded = try JSONDecoder().decode(
            [EphemeralSnippet].self, from: Data(contentsOf: fileURL))
        guard Set(decoded.map(\.id)).count == decoded.count,
            decoded.allSatisfy({
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.createdAt.timeIntervalSince1970.isFinite
                    && $0.expiresAt.timeIntervalSince1970.isFinite
                    && $0.expiresAt > $0.createdAt
            })
        else { throw CocoaError(.fileReadCorruptFile) }
        items = decoded.sorted { $0.createdAt > $1.createdAt }
        isLoaded = true
    }

    private func persist(_ snapshot: [EphemeralSnippet]) throws {
        let data = try JSONEncoder().encode(snapshot)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        items = snapshot
    }

    private func scheduleExpiration() {
        expirationTask?.cancel()
        guard let expiration = items.map(\.expiresAt).min() else { return }
        let delay = max(0, expiration.timeIntervalSince(now()))
        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            try? self.loadAndPrune()
        }
    }

    private static func defaultFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? "com.tinycast.app", isDirectory: true
            )
            .appendingPathComponent("ephemeral-ai-snippets.json")
    }
}
