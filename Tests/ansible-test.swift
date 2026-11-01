import Foundation

@main
struct AnsibleTests {
    @MainActor
    static func main() async {
        var failures = 0
        func check(_ name: String, _ condition: @autoclosure () -> Bool) {
            if condition() { print("PASS  \(name)") }
            else { print("FAIL  \(name)"); failures += 1 }
        }

        let json = Data(#"{"_meta":{"hostvars":{"web-2":{},"web-1":{}}},"all":{"hosts":["web-1","web-2"]},"production":{"hosts":["web-2"]}}"#.utf8)
        let inventory = try? AnsibleInventory.parse(json)
        check("inventory parses groups and hosts", inventory?.hosts == ["web-1", "web-2"])
        check("inventory groups are sorted", inventory?.groups.map(\.name) == ["all", "production"])
        check("invalid inventory JSON is rejected", (try? AnsibleInventory.parse(Data("{".utf8))) == nil)

        var run = AnsiblePlaybookRun(
            inventory: URL(fileURLWithPath: "/tmp/hosts file.ini"),
            playbook: URL(fileURLWithPath: "/tmp/deploy playbook.yml"),
            limit: "api-1,api-2", tags: "deploy,config")
        check(
            "dry run keeps paths and filters as separate argv",
            run.arguments(dryRun: true) == [
                "-i", "/tmp/hosts file.ini", "/tmp/deploy playbook.yml",
                "--limit", "api-1,api-2", "--tags", "deploy,config", "--check", "--diff"
            ])
        check("real run omits check flags", !run.arguments(dryRun: false).contains("--check"))
        run.limit = " "
        run.tags = " "
        check(
            "blank optional filters are omitted", run.arguments(dryRun: true) == [
                "-i", "/tmp/hosts file.ini", "/tmp/deploy playbook.yml", "--check", "--diff"
            ])

        let noTools = AnsibleRunner(locate: { _ in nil })
        do {
            _ = try await noTools.start(run, dryRun: false, confirmedByUser: false)
            check("an unconfirmed real run is blocked", false)
        } catch AnsibleRunnerError.realRunRequiresConfirmation {
            check("an unconfirmed real run is blocked", true)
        } catch {
            check("an unconfirmed real run is blocked", false)
        }
        do {
            _ = try await noTools.start(run, dryRun: true, confirmedByUser: false)
            check("a dry run reports a missing executable", false)
        } catch AnsibleRunnerError.executableUnavailable("ansible-playbook") {
            check("a dry run reports a missing executable", true)
        } catch {
            check("a dry run reports a missing executable", false)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tinycast-ansible-\(UUID().uuidString)")
        let historyURL = directory.appendingPathComponent("history.json")
        let history = AnsibleRunHistoryStore(fileURL: historyURL)
        let record = AnsibleRunRecord(
            run: run, dryRun: true, startedAt: Date(timeIntervalSince1970: 100),
            finishedAt: Date(timeIntervalSince1970: 104), exitCode: 2)
        history.append(record)
        let saved = (try? Data(contentsOf: historyURL)).flatMap { String(data: $0, encoding: .utf8) }
        check("history keeps run metadata", history.records.first == record)
        check("history stores no command output", saved?.contains("stdout") == false && saved?.contains("stderr") == false)
        check("history stores exact positional arguments", history.records.first?.arguments == run.arguments(dryRun: true))
        check("history records dry-run mode", history.records.first?.dryRun == true)
        check("history reloads", AnsibleRunHistoryStore(fileURL: historyURL).records == [record])
        try? FileManager.default.removeItem(at: directory)

        if failures > 0 { exit(1) }
    }
}
