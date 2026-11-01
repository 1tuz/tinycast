import Foundation

@MainActor
final class AppSettings {
    var kubeContextGuardEnabled = false
    var kubeSelectedContext: String?
    var kubeSelectedNamespace = "default"
    var kubeProductionContexts: [String] = []
}

@MainActor
final class LoadProbe {
    var count = 0
    var continuation: CheckedContinuation<KubeConfiguration, Never>?

    func record() { count += 1 }
    func suspend() async -> KubeConfiguration {
        count += 1
        return await withCheckedContinuation { continuation = $0 }
    }
}

@main
@MainActor
struct KubeContextTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { failures += 1; print("FAIL: \(message)") }
    }

    static func main() async {
        do { try parser() } catch { failures += 1; print("FAIL: parser \(error)") }
        do { try await fileReads() } catch { failures += 1; print("FAIL: file reader \(error)") }
        policy()
        await store()
        print("Kube context: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func parser() throws {
        let first = """
            apiVersion: v1
            current-context: arn:aws:eks:eu:123:cluster/dev
            contexts:
            - name: arn:aws:eks:eu:123:cluster/dev
              context:
                cluster: development
                namespace: team-a
            users:
            - name: hidden
              user:
                token: fake-secret
            """
        let second = """
            {"current-context":"qa","contexts":[{"name":"arn:aws:eks:eu:123:cluster/dev","context":{"cluster":"other"}},{"name":"qa","context":{"cluster":"quality"}}]}
            """
        let files = ["/a": Data(first.utf8), "/b": Data(second.utf8)]
        var reads: [String] = []
        let result = try KubeConfigReader.load(
            environment: ["KUBECONFIG": "/missing::/a:/b:/a"], homeDirectory: "/home"
        ) { path in
            reads.append(path); return files[path]
        }
        expect(reads == ["/missing", "/a", "/b"], "paths retain order and deduplicate")
        expect(result.contexts.count == 2, "context names merge")
        expect(result.contexts.first?.namespace == "team-a", "first whole context wins")
        expect(result.contexts.last?.namespace == "default", "omitted namespace defaults")
        expect(result.currentContextName == "arn:aws:eks:eu:123:cluster/dev", "first current wins")
        expect(!String(describing: result).contains("fake-secret"), "returned metadata contains no token")
        let fallback = try KubeConfigReader.paths(environment: ["KUBECONFIG": ""], homeDirectory: "/tmp/home")
        expect(fallback == ["/tmp/home/.kube/config"], "empty variable uses injected home")
        let environmentHome = try KubeConfigReader.paths(
            environment: ["HOME": "/env/home"], homeDirectory: "/other")
        expect(environmentHome == ["/env/home/.kube/config"], "HOME environment has kubectl precedence")
        let empty = try KubeConfigReader.load(environment: ["KUBECONFIG": "/absent"], homeDirectory: nil) {
            _ in nil
        }
        expect(empty.contexts.isEmpty, "missing files return empty config")
        let docs = [
            "[]", "contexts: wrong", "contexts:\n- name: dev\n  context:\n    cluster: 42",
            "---\ncontexts: []\n---\ncontexts: []"
        ]
        for (index, source) in docs.enumerated() {
            do {
                _ = try KubeConfigReader.parse(Data(source.utf8), path: "/bad")
                expect(false, "invalid input \(index) rejected")
            } catch { expect(error is KubeConfigReaderError, "typed config error \(index)") }
        }
        do {
            _ = try KubeConfigReader.load(environment: ["KUBECONFIG": "/directory"], homeDirectory: nil) {
                _ in
                throw CocoaError(.fileReadNoPermission)
            }
            expect(false, "read failure rejected")
        } catch {
            expect(error as? KubeConfigReaderError == .unreadableFile("/directory"), "read failure typed")
        }
    }

    static func policy() {
        let summary = KubeMenuBarSummary.label(
            contextName: "arn:aws:eks:region:account:cluster/development", namespace: "a-long-namespace-name")
        expect(summary.count <= 30 && summary.contains(" · "), "menu label caps both metadata parts")
        expect(
            KubeMenuBarSummary.label(contextName: "dev", namespace: "team") == "dev · team",
            "short menu labels remain literal")
        let policy = KubeCommandPolicy(
            isEnabled: true, contextNames: ["dev", "prod"], productionContextNames: ["prod"])
        do {
            let args = try policy.arguments(for: "dev", namespace: "team-a", operation: .mutation)
            expect(
                args == ["--context", "dev", "--namespace", "team-a"],
                "argv has explicit context and namespace")
        } catch { expect(false, "development mutation allowed") }
        for (name, operation) in [("prod", KubeOperation.mutation), ("missing", .read)] {
            do {
                _ = try policy.arguments(for: name, namespace: "default", operation: operation);
                expect(false, "guard blocks \(name)")
            } catch { expect(error is KubeContextPolicyError, "policy errors typed") }
        }
        do { _ = try policy.arguments(for: "prod", namespace: "default", operation: .read) } catch {
            expect(false, "production reads allowed")
        }
        expect(!KubeCommandPolicy.isValidNamespace("ns; command"), "namespace shell syntax rejected")
        expect(!KubeCommandPolicy.isValidNamespace("NS"), "namespace case rules enforced")
        let disabled = KubeCommandPolicy(isEnabled: false, contextNames: ["dev"], productionContextNames: [])
        do {
            _ = try disabled.arguments(for: "dev", namespace: "default", operation: .read);
            expect(false, "disabled guard blocks")
        } catch { expect(error as? KubeContextPolicyError == .guardDisabled, "disabled error") }
        let exact = KubeCommandPolicy(
            isEnabled: true, contextNames: ["prod", "prod-copy"], productionContextNames: ["prod"])
        do { _ = try exact.arguments(for: "prod-copy", namespace: "default", operation: .mutation) } catch {
            expect(false, "production names do not use prefix matching")
        }
    }

    static func fileReads() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config")
        try Data("{\"contexts\":[]}".utf8).write(to: file)
        let result = try await KubeConfigLoader.load(
            environment: ["KUBECONFIG": file.path], homeDirectory: nil)
        expect(result.contexts.isEmpty, "regular config file loads")
        for path in [directory.path, directory.appendingPathComponent("large").path] {
            if path != directory.path {
                try Data(repeating: 32, count: KubeConfigReader.maximumBytes + 1).write(
                    to: URL(fileURLWithPath: path))
            }
            do {
                _ = try await KubeConfigLoader.load(environment: ["KUBECONFIG": path], homeDirectory: nil)
                expect(false, "non-file or oversized input rejected")
            } catch {
                expect(
                    error as? KubeConfigReaderError == .unreadableFile(path),
                    "file cap and type failures typed")
            }
        }
    }

    static func wait(_ store: KubeContextStore) async {
        while store.isLoading { await Task.yield() }
    }

    static func store() async {
        let settings = AppSettings()
        let probe = LoadProbe()
        let config = KubeConfiguration(
            contexts: [
                KubeContext(name: "dev", clusterName: "dev-cluster", namespace: "team-a"),
                KubeContext(name: "prod", clusterName: "prod-cluster", namespace: "default")
            ], currentContextName: "dev")
        let store = KubeContextStore(
            settings: settings,
            loader: {
                await probe.record(); return config
            })
        expect(!store.isEnabled && !store.isLoading, "fresh store stays disabled without load")
        store.reload()
        await Task.yield()
        expect(!store.isLoading, "disabled reload is no-op")
        expect(probe.count == 0, "disabled guard never invokes loader")
        do {
            _ = try store.commandArguments(operation: .read);
            expect(false, "disabled store cannot build CLI args")
        } catch { expect(error as? KubeContextPolicyError == .guardDisabled, "disabled command guard typed") }
        store.setEnabled(true)
        await wait(store)
        expect(probe.count == 1, "enable loads exactly once")
        expect(
            store.selectedContextName == "dev" && store.selectedNamespace == "team-a",
            "enable selects current configured namespace")
        do { try store.select(contextName: "prod", namespace: "custom") } catch {
            expect(false, "known context can select")
        }
        expect(
            settings.kubeSelectedContext == "prod" && settings.kubeSelectedNamespace == "custom",
            "selection persists")
        store.setProductionContextNames(["prod"])
        do { try store.requireNonProduction("prod"); expect(false, "store production guard enforced") } catch
        {
            expect(
                error as? KubeContextPolicyError == .productionContext("prod"), "store uses exact prod policy"
            )
        }
        do {
            try store.select(contextName: "missing", namespace: nil);
            expect(false, "unknown selection rejected")
        } catch { expect(store.selectedContextName == "prod", "invalid selection preserves destination") }
        store.setEnabled(false)
        expect(store.contexts.isEmpty && store.selectedContextName == nil, "disable clears context metadata")
        expect(settings.kubeSelectedContext == "prod", "disable retains saved selection")
        store.setEnabled(true)
        await wait(store)
        expect(
            store.selectedContextName == "prod" && store.selectedNamespace == "custom",
            "re-enable restores saved selection")
        store.setEnabled(false)
        let broken = KubeContextStore(
            settings: settings, loader: { throw KubeConfigReaderError.invalidDocument("/config") })
        broken.setEnabled(true)
        await wait(broken)
        expect(
            broken.loadError != nil && broken.contexts.isEmpty,
            "parse failure cannot leave selectable stale contexts")
        broken.setEnabled(false)
        let saved = AppSettings()
        saved.kubeContextGuardEnabled = true
        saved.kubeSelectedContext = "prod"
        saved.kubeSelectedNamespace = "saved"
        let restored = KubeContextStore(settings: saved, loader: { config })
        await wait(restored)
        expect(
            restored.selectedContextName == "prod" && restored.selectedNamespace == "saved",
            "enabled startup restores saved destination")
        restored.setEnabled(false)
        let gate = LoadProbe()
        let delayed = KubeContextStore(settings: settings, loader: { await gate.suspend() })
        delayed.setEnabled(true)
        while gate.continuation == nil { await Task.yield() }
        delayed.setEnabled(false)
        gate.continuation?.resume(returning: config)
        await Task.yield()
        expect(
            delayed.contexts.isEmpty && !delayed.isEnabled,
            "late load cannot re-enable or populate disabled guard")
    }
}
