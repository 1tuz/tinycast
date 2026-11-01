import Foundation

struct AnsiblePlaybookRun: Equatable, Sendable {
    let inventory: URL
    let playbook: URL
    var limit = ""
    var tags = ""

    func arguments(dryRun: Bool) -> [String] {
        var result = ["-i", inventory.path, playbook.path]
        let selectedLimit = limit.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedTags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedLimit.isEmpty { result += ["--limit", selectedLimit] }
        if !selectedTags.isEmpty { result += ["--tags", selectedTags] }
        if dryRun { result += ["--check", "--diff"] }
        return result
    }
}

struct AnsibleRunRecord: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let inventoryPath: String
    let playbookPath: String
    let arguments: [String]
    let dryRun: Bool
    let limit: String
    let tags: String
    let startedAt: Date
    let durationSeconds: Double
    let exitCode: Int32

    init(
        run: AnsiblePlaybookRun, dryRun: Bool, startedAt: Date, finishedAt: Date,
        exitCode: Int32
    ) {
        id = UUID()
        inventoryPath = run.inventory.path
        playbookPath = run.playbook.path
        arguments = run.arguments(dryRun: dryRun)
        self.dryRun = dryRun
        limit = run.limit
        tags = run.tags
        self.startedAt = startedAt
        durationSeconds = max(0, finishedAt.timeIntervalSince(startedAt))
        self.exitCode = exitCode
    }
}
