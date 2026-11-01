import Foundation
import Observation

@MainActor
@Observable
final class AnsibleRunHistoryStore {
    private(set) var records: [AnsibleRunRecord] = []
    private let fileURL: URL
    private let limit = 50

    init(fileURL: URL) {
        self.fileURL = fileURL
        guard let data = try? Data(contentsOf: fileURL),
            let loaded = try? JSONDecoder().decode([AnsibleRunRecord].self, from: data)
        else { return }
        records = Array(loaded.prefix(limit))
    }

    func append(_ record: AnsibleRunRecord) {
        records.insert(record, at: 0)
        records = Array(records.prefix(limit))
        guard let data = try? JSONEncoder().encode(records) else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            records.removeAll { $0.id == record.id }
        }
    }
}
