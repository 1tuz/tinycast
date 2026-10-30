import Foundation

@main
@MainActor
struct EphemeralSnippetTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ephemeral-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("replies.json")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expired = EphemeralSnippet(
            id: UUID(), text: "expired", createdAt: now.addingTimeInterval(-86_401))
        let current = EphemeralSnippet(
            id: UUID(), text: "current", createdAt: now.addingTimeInterval(-3_600))

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode([expired, current]).write(to: fileURL)
            let store = EphemeralSnippetStore(fileURL: fileURL, now: { now })
            expect(store.items.isEmpty, "the store defers disk reads until it is enabled")
            try store.loadAndPrune()
            expect(store.items.map(\.id) == [current.id], "prune keeps only unexpired replies")
            let saved = try JSONDecoder().decode([EphemeralSnippet].self, from: Data(contentsOf: fileURL))
            expect(saved.map(\.id) == [current.id], "prune persists expiration")

            let newID = UUID()
            try store.capture(id: newID, text: "  First line\nmore text  ")
            expect(store.items.first?.id == newID, "new replies are newest first")
            expect(store.items.first?.name == "First line", "snippet name comes from the first line")
            expect(
                store.items.first?.expiresAt == now.addingTimeInterval(86_400), "reply expires after 24 hours"
            )
            try store.capture(id: newID, text: "duplicate")
            expect(
                store.items.filter { $0.id == newID }.count == 1,
                "completion callbacks do not duplicate replies")
            try store.capture(id: UUID(), text: " \n ")
            expect(store.items.count == 2, "empty replies are ignored")
            try store.remove(id: newID)
            expect(store.items.map(\.id) == [current.id], "a temporary reply can be removed")

            let boundedURL = directory.appendingPathComponent("bounded.json")
            let bounded = EphemeralSnippetStore(fileURL: boundedURL, now: { now })
            for index in 0...100 {
                try bounded.capture(id: UUID(), text: "Reply \(index)")
            }
            expect(bounded.items.count == 100, "the local store keeps at most 100 replies")
        } catch {
            failures += 1
            print("FAIL: couldn't check expiration and persistence: \(error)")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
