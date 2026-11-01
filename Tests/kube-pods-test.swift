import Foundation

@main
@MainActor
struct KubePodsTests {
    static var failures = 0

    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { failures += 1; print("FAIL: \(message)") }
    }

    static func main() throws {
        try decodePods()
        try buildCommands()
        print("Kube pods: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    static func decodePods() throws {
        let data = Data(
            #"""
            {
              "apiVersion": "v1",
              "kind": "List",
              "items": [
                {
                  "metadata": {"name": "api-10"},
                  "spec": {"containers": [{"name": "api"}, {"name": "metrics"}]},
                  "status": {
                    "phase": "Running",
                    "containerStatuses": [
                      {"name":"api","ready":true,"restartCount":3,"state":{"running":{}}},
                      {"name":"metrics","ready":false,"restartCount":4,"state":{"waiting":{"reason":"CrashLoopBackOff"}}}
                    ]
                  }
                },
                {
                  "metadata": {"name": "batch-pending"},
                  "spec": {"containers": [{"name": "batch"}]},
                  "status": {"phase": "Pending"}
                },
                {
                  "metadata": {"name": "worker"},
                  "status": {"phase": "Running"}
                },
                {"metadata": {"name": "bad name"}, "status": {"phase":"Running"}}
              ]
            }
            """#.utf8)
        let pods = try KubePodDecoder.decode(data)
        expect(
            pods.map(\.name) == ["api-10", "batch-pending", "worker"],
            "valid pods sorted and invalid names ignored")
        let crashing = pods.first { $0.name == "api-10" }
        expect(crashing?.displayStatus == "CrashLoopBackOff", "container wait reason overrides running phase")
        expect(crashing?.isProblem == true, "crashloop included in problems")
        expect(
            crashing?.readyContainerCount == 1 && crashing?.containerCount == 2, "container readiness counted"
        )
        expect(
            crashing?.containers.map(\.name) == ["api", "metrics"]
                && crashing?.containers.last?.state == "CrashLoopBackOff",
            "container names and individual states retained")
        expect(crashing?.restartCount == 7, "container restarts summed")
        expect(pods.first { $0.name == "batch-pending" }?.isProblem == true, "pending included in problems")
        expect(pods.first { $0.name == "worker" }?.displayStatus == "Running", "running status retained")
        do {
            _ = try KubePodDecoder.decode(Data(#"{"items":[]}"#.utf8))
            expect(false, "non Kubernetes list rejected")
        } catch {
            expect(
                error as? KubePodDecodeError == .invalidJSON
                    || error as? KubePodDecodeError == .invalidPodList, "invalid list typed")
        }
        do {
            _ = try KubePodDecoder.decode(Data(repeating: 32, count: 8 * 1024 * 1024 + 1))
            expect(false, "oversized output rejected")
        } catch { expect(error as? KubePodDecodeError == .invalidPodList, "oversized error typed") }
    }

    static func buildCommands() throws {
        let policy = KubeCommandPolicy(
            isEnabled: true, contextNames: ["dev", "prod"], productionContextNames: ["prod"])
        let list = try KubePodCommand.list(context: "dev", namespace: "team-a", policy: policy)
        let logs = try KubePodCommand.logs(
            context: "dev", namespace: "default", pod: "api-0", container: "main", policy: policy)
        let describe = try KubePodCommand.describe(
            context: "dev", namespace: "default", pod: "api-0", policy: policy)
        let exec = try KubePodCommand.exec(
            context: "dev", namespace: "default", pod: "api-0", container: nil, policy: policy)
        expect(
            list == ["--context", "dev", "--namespace", "team-a", "get", "pods", "--output=json"],
            "list pins context and namespace in argv")
        expect(
            logs == [
                "--context", "dev", "--namespace", "default", "logs", "--follow", "--tail=500", "--container",
                "main", "api-0"
            ],
            "logs command is stream-ready with bounded initial tail")
        expect(
            describe == ["--context", "dev", "--namespace", "default", "describe", "pod", "api-0"],
            "describe command passes resource as a distinct argument")
        expect(
            exec == [
                "--context", "dev", "--namespace", "default", "exec", "--stdin", "--tty", "api-0", "--",
                "/bin/sh"
            ],
            "interactive exec keeps command after argv separator")
        do {
            _ = try KubePodCommand.restart(
                context: "dev", namespace: "default", deployment: "api", confirmedByUser: false,
                policy: policy)
            expect(false, "restart requires confirmation")
        } catch { expect(error as? KubePodCommandError == .confirmationRequired, "confirmation error typed") }
        do {
            _ = try KubePodCommand.restart(
                context: "prod", namespace: "default", deployment: "api", confirmedByUser: true,
                policy: policy)
            expect(false, "production restart blocked")
        } catch {
            expect(
                error as? KubeContextPolicyError == .productionContext("prod"),
                "production restart rejected by policy")
        }
        let restart = try KubePodCommand.restart(
            context: "dev", namespace: "default", deployment: "api", confirmedByUser: true, policy: policy)
        expect(
            restart == ["--context", "dev", "--namespace", "default", "rollout", "restart", "deployment/api"],
            "confirmed development restart is explicit")
        do {
            _ = try KubePodCommand.logs(
                context: "dev", namespace: "default", pod: "api;id", container: nil, policy: policy)
            expect(false, "shell syntax not accepted as pod name")
        } catch { expect(error as? KubePodCommandError == .invalidPod, "pod name validation typed") }
        do {
            _ = try KubePodCommand.logs(
                context: "dev", namespace: "default", pod: "api", container: "-c", policy: policy)
            expect(false, "option prefix not accepted as container name")
        } catch { expect(error as? KubePodCommandError == .invalidContainer, "container validation typed") }
    }
}
