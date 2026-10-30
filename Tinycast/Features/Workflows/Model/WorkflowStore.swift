import Foundation
import Observation
import SQLite3

private let workflowSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
@Observable
final class WorkflowStore {
    private(set) var workflows: [Workflow] = []
    private(set) var isAvailable = true
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var database: OpaquePointer?
    @ObservationIgnored private let databaseURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL) {
        databaseURL = directory.appendingPathComponent("workflows.sqlite3")
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        } catch {
            isAvailable = false
            return
        }
        guard
            sqlite3_open_v2(
                databaseURL.path, &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK,
            sqlite3_exec(
                database,
                "CREATE TABLE IF NOT EXISTS workflows(id TEXT PRIMARY KEY, definition TEXT NOT NULL)",
                nil, nil, nil) == SQLITE_OK
        else {
            sqlite3_close_v2(database)
            database = nil
            isAvailable = false
            return
        }
        load()
    }

    isolated deinit { sqlite3_close_v2(database) }

    func load() {
        guard let database else { return }
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database, "SELECT definition FROM workflows ORDER BY rowid", -1,
                &statement, nil) == SQLITE_OK, let statement
        else { return }
        defer { sqlite3_finalize(statement) }
        var loaded: [Workflow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let value = Self.columnString(statement, 0),
                let workflow = try? decoder.decode(
                    Workflow.self, from: Data(value.utf8))
            else { continue }
            loaded.append(workflow)
        }
        workflows = loaded
    }

    @discardableResult
    func create() -> UUID? {
        let workflow = Workflow()
        guard save(workflow) else { return nil }
        workflows.append(workflow)
        onChange?()
        return workflow.id
    }

    func update(_ workflow: Workflow) {
        guard let index = workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        let previous = workflows[index]
        guard save(workflow) else { return }
        workflows[index] = workflow
        if previous.isEnabled != workflow.isEnabled
            || previous.trigger != workflow.trigger
            || previous.commandID != workflow.commandID
        {
            onChange?()
        }
    }

    func delete(id: UUID) {
        guard let database else { return }
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database, "DELETE FROM workflows WHERE id = ?1", -1,
                &statement, nil) == SQLITE_OK, let statement
        else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, workflowSQLiteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else { return }
        workflows.removeAll { $0.id == id }
        onChange?()
    }

    func workflow(id: UUID) -> Workflow? { workflows.first { $0.id == id } }

    private func save(_ workflow: Workflow) -> Bool {
        guard let database, let data = try? encoder.encode(workflow),
            let definition = String(data: data, encoding: .utf8)
        else { return false }
        var statement: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                database,
                "INSERT OR REPLACE INTO workflows(id, definition) VALUES(?1, ?2)",
                -1, &statement, nil) == SQLITE_OK, let statement
        else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(
            statement, 1, workflow.id.uuidString, -1, workflowSQLiteTransient)
        sqlite3_bind_text(statement, 2, definition, -1, workflowSQLiteTransient)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    nonisolated private static func columnString(
        _ statement: OpaquePointer?, _ index: Int32
    ) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }
}
