import Foundation

final class PortForwardProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var savedArguments: [[String]] = []
    private var savedDelays: [Duration] = []
    private var continuations: [UUID: AsyncStream<ShellCommandEvent>.Continuation] = [:]
    private var savedStops = 0

    var arguments: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return savedArguments
    }

    var delays: [Duration] {
        lock.lock()
        defer { lock.unlock() }
        return savedDelays
    }

    var stopCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return savedStops
    }

    func record(arguments: [String]) {
        lock.lock()
        savedArguments.append(arguments)
        lock.unlock()
    }

    func record(delay: Duration) {
        lock.lock()
        savedDelays.append(delay)
        lock.unlock()
    }

    func stream(arguments: [String]) -> ShellCommandSession {
        let id = UUID()
        record(arguments: arguments)

        let events = AsyncStream<ShellCommandEvent> { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
        }
        return ShellCommandSession(events: events) { [weak self] in
            self?.stop(id: id)
        }
    }

    func emit(_ event: ShellCommandEvent, session index: Int = 0) {
        lock.lock()
        let continuation = continuations.values.dropFirst(index).first
        lock.unlock()
        continuation?.yield(event)
    }

    func stop(id: UUID) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: id)
        savedStops += 1
        lock.unlock()
        continuation?.finish()
    }

    func finishAll() {
        lock.lock()
        let values = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        values.forEach { $0.finish() }
    }
}

@MainActor
final class KubeForwardContextProbe {
    var policy: KubeCommandPolicy
    let selection: KubePortForwardSelection

    init(policy: KubeCommandPolicy, selection: KubePortForwardSelection) {
        self.policy = policy
        self.selection = selection
    }
}

@main
@MainActor
struct PortForwardTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        try requestArgumentsAndValidation()
        backoff()
        await kubePolicyIsRevalidated()
        await retriesUseCappedBackoff()
        await manualStopDisablesRetry()
        await stopAllEndsEverySession()
        print("Port forward: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func requestArgumentsAndValidation() throws {
        let policy = KubeCommandPolicy(
            isEnabled: true, contextNames: ["dev", "prod"], productionContextNames: ["prod"])
        let kube = try PortForwardRequest.kubernetes(
            context: "prod", namespace: "team-a", resource: "service/api",
            localPort: "8080", remotePort: "80", policy: policy)
        expect(
            kube.arguments == [
                "port-forward", "--context", "prod", "--namespace", "team-a",
                "service/api", "8080:80"
            ], "kubectl argv uses explicit context and namespace")

        let configPath = URL(fileURLWithPath: "/tmp/Vault Proxy; config.hcl")
        let vault = try PortForwardRequest.vaultProxy(
            configFile: configPath, displayTarget: "Vault dev", listenerPort: 8201)
        expect(
            vault.arguments == ["proxy", "-config=/tmp/Vault Proxy; config.hcl"],
            "Vault config remains one argv element and owns its listener config")
        expect(
            vault.displayTarget == "Vault dev" && vault.displayPorts == "127.0.0.1:8201",
            "Vault listener is shown without unsupported CLI arguments")

        let ssh = try PortForwardRequest.ssh(
            alias: "dev@jump", localPort: "9000", remoteHost: "db.internal", remotePort: "5432")
        expect(
            ssh.arguments == ["-N", "-T", "-L", "9000:db.internal:5432", "dev@jump"],
            "SSH tunnel uses distinct argv values")
        let ipv6 = try PortForwardRequest.ssh(
            alias: "jump", localPort: "9001", remoteHost: "[2001:db8::1]", remotePort: "443")
        expect(ipv6.arguments[3] == "9001:[2001:db8::1]:443", "bracketed IPv6 host is retained")

        for (local, remote) in [("0", "80"), ("65536", "80"), ("abc", "80"), ("", "80")] {
            do {
                _ = try PortForwardRequest.kubernetes(
                    context: "dev", namespace: "default", resource: "pod/api",
                    localPort: local, remotePort: remote, policy: policy)
                expect(false, "invalid port \(local) rejected")
            } catch {
                expect(
                    error as? PortForwardRequestError == .invalidPort,
                    "invalid port error is typed")
            }
        }
        do {
            _ = try PortForwardRequest.kubernetes(
                context: "dev", namespace: "default", resource: "pod/api;id",
                localPort: "80", remotePort: "80", policy: policy)
            expect(false, "invalid Kubernetes resource rejected")
        } catch {
            expect(
                error as? PortForwardRequestError == .invalidResource,
                "invalid resource error is typed")
        }
        do {
            _ = try PortForwardRequest.kubernetes(
                context: "missing", namespace: "default", resource: "pod/api",
                localPort: "80", remotePort: "80", policy: policy)
            expect(false, "unavailable context rejected")
        } catch {
            expect(
                error as? PortForwardRequestError == .policy(.unavailableContext("missing")),
                "Kubernetes builder preserves context policy error")
        }
        do {
            _ = try PortForwardRequest.vaultProxy(
                configFile: configPath, displayTarget: "Vault", listenerPort: 65_536)
            expect(false, "invalid Vault listener port rejected")
        } catch {
            expect(
                error as? PortForwardRequestError == .invalidVaultConfiguration,
                "Vault listener validation is typed")
        }
        do {
            _ = try PortForwardRequest.ssh(
                alias: "-oProxyCommand=id", localPort: "22", remoteHost: "db.internal",
                remotePort: "22")
            expect(false, "SSH option injection rejected")
        } catch {
            expect(
                error as? PortForwardRequestError == .invalidSSHTarget,
                "invalid SSH alias error is typed")
        }
        do {
            _ = try PortForwardRequest.ssh(
                alias: "jump", localPort: "22", remoteHost: "db;id", remotePort: "22")
            expect(false, "invalid SSH host rejected")
        } catch {
            expect(
                error as? PortForwardRequestError == .invalidSSHTarget,
                "invalid SSH host error is typed")
        }
        let lowerPort = try PortForwardRequest.parsePort("1")
        let upperPort = try PortForwardRequest.parsePort("65535")
        expect(lowerPort == 1, "port lower boundary accepted")
        expect(upperPort == 65_535, "port upper boundary accepted")
    }

    static func backoff() {
        let delays = (1...7).map(PortForwardBackoff.delaySeconds(for:))
        expect(delays == [1, 2, 4, 8, 16, 30, 30], "retry delays grow exponentially to a fixed cap")
    }

    static func kubePolicyIsRevalidated() async {
        let selection = KubePortForwardSelection(contextName: "dev", namespace: "team-a")
        let enabled = KubeCommandPolicy(
            isEnabled: true, contextNames: ["dev"], productionContextNames: [])
        let disabled = KubeCommandPolicy(
            isEnabled: false, contextNames: ["dev"], productionContextNames: [])
        let context = KubeForwardContextProbe(policy: enabled, selection: selection)
        let probe = PortForwardProbe()
        let manager = PortForwardManager(
            currentPolicy: { context.policy }, currentSelection: { context.selection },
            locateExecutable: { _ in URL(fileURLWithPath: "/usr/bin/kubectl") },
            stream: { _, arguments, _ in
                probe.record(arguments: arguments)
                let events = AsyncStream<ShellCommandEvent> { continuation in
                    continuation.yield(.finished(ShellCommandResult(termination: .exited(status: 2))))
                    continuation.finish()
                }
                return ShellCommandSession(events: events, stop: {})
            },
            retrySleep: { _ in await MainActor.run { context.policy = disabled } })
        let request = try! PortForwardRequest.kubernetes(
            context: "dev", namespace: "team-a", resource: "service/api",
            localPort: "8080", remotePort: "80", policy: enabled)
        let id = try! await manager.start(request)
        await wait { manager.sessions.first(where: { $0.id == id })?.state.isActive == false }
        expect(
            probe.arguments == [
                [
                    "port-forward", "--context", "dev", "--namespace", "team-a", "service/api", "8080:80"
                ]
            ], "manager invokes kubectl with exact argv and stops when the current policy changes")
        expect(
            manager.sessions.first(where: { $0.id == id })?.state.isActive == false,
            "disabled current Kube policy prevents a reconnect")
    }

    static func retriesUseCappedBackoff() async {
        let probe = PortForwardProbe()
        let policy = KubeCommandPolicy(isEnabled: true, contextNames: [], productionContextNames: [])
        let manager = PortForwardManager(
            currentPolicy: { policy }, currentSelection: { nil },
            locateExecutable: { _ in URL(fileURLWithPath: "/usr/bin/ssh") },
            stream: { _, arguments, _ in
                probe.record(arguments: arguments)
                let events = AsyncStream<ShellCommandEvent> { continuation in
                    continuation.yield(.finished(ShellCommandResult(termination: .exited(status: 2))))
                    continuation.finish()
                }
                return ShellCommandSession(events: events, stop: {})
            },
            retrySleep: {
                probe.record(delay: $0)
                try await Task.sleep(for: .milliseconds(10))
            })
        let request = try! PortForwardRequest.ssh(
            alias: "jump", localPort: "8000", remoteHost: "db.internal", remotePort: "80")
        let id = try! await manager.start(request)
        await wait { probe.delays.count >= 7 }
        let session = manager.sessions.first(where: { $0.id == id })
        expect(probe.arguments.count == 7, "unexpected exits keep reconnecting")
        expect(
            Array(probe.delays.prefix(7))
                == [
                    .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30),
                    .seconds(30)
                ],
            "manager sleeps using capped exponential backoff")
        expect(
            session?.state.isActive == true && session?.lastError == "Exited with status 2.",
            "latest exit remains visible while the manager reconnects")
        manager.stop(id: id)
        await wait { manager.sessions.first(where: { $0.id == id })?.state == .stopped }
        expect(probe.arguments.count == 7, "manual stop cancels a pending retry")
    }

    static func manualStopDisablesRetry() async {
        let probe = PortForwardProbe()
        let manager = manager(with: probe)
        let request = try! PortForwardRequest.ssh(
            alias: "jump", localPort: "8001", remoteHost: "db.internal", remotePort: "80")
        let id = try! await manager.start(request)
        await wait { probe.arguments.count == 1 }
        probe.emit(.output("forward ready"))
        await wait { manager.sessions.first(where: { $0.id == id })?.state == .running }
        manager.stop(id: id)
        await Task.yield()
        expect(
            manager.sessions.first(where: { $0.id == id })?.state == .stopped,
            "manual stop moves session to stopped")
        expect(
            probe.stopCount == 1 && probe.arguments.count == 1 && probe.delays.isEmpty,
            "manual stop terminates process and prevents retry")
        probe.finishAll()
    }

    static func stopAllEndsEverySession() async {
        let probe = PortForwardProbe()
        let manager = manager(with: probe)
        let first = try! await manager.start(
            PortForwardRequest.ssh(
                alias: "first", localPort: "8002", remoteHost: "one.internal", remotePort: "80"))
        let second = try! await manager.start(
            PortForwardRequest.ssh(
                alias: "second", localPort: "8003", remoteHost: "two.internal", remotePort: "80"))
        await wait { probe.arguments.count == 2 }
        manager.stopAll()
        expect(
            manager.sessions.first(where: { $0.id == first })?.state == .stopped
                && manager.sessions.first(where: { $0.id == second })?.state == .stopped,
            "stopAll ends every session")
        expect(probe.stopCount == 2, "stopAll stops each process")
        probe.finishAll()
    }

    static func manager(with probe: PortForwardProbe) -> PortForwardManager {
        PortForwardManager(
            currentPolicy: {
                KubeCommandPolicy(isEnabled: true, contextNames: [], productionContextNames: [])
            },
            currentSelection: { nil },
            locateExecutable: { _ in URL(fileURLWithPath: "/usr/bin/ssh") },
            stream: { _, arguments, _ in probe.stream(arguments: arguments) },
            retrySleep: { probe.record(delay: $0) })
    }

    static func wait(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
    }
}
