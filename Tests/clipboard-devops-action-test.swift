import Foundation

@main
@MainActor
struct ClipboardDevOpsActionTests {
    static var passes = 0
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() { passes += 1 } else { failures += 1; print("FAIL: \(message)") }
    }

    static func main() {
        let token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0.sig"
        expect(
            ClipboardDevOpsAction.available(for: "Bearer " + token) == [.decodeJWT],
            "recognises JWT and Bearer form")
        expect(
            ClipboardDevOpsAction.available(for: "10.2.3.4/24") == [.calculateCIDR],
            "recognises valid IPv4 CIDR only")
        expect(
            ClipboardDevOpsAction.available(for: "apiVersion: v1\nkind: Secret\ndata: {}")
                == [.decodeKubernetesSecret],
            "recognises Kubernetes Secret YAML")
        let pod = """
            apiVersion: v1
            kind: Pod
            metadata:
              name: api
            """
        expect(
            ClipboardDevOpsAction.available(for: pod) == [.convertKubernetesYAML],
            "recognises Kubernetes Pod YAML")
        let service = """
            apiVersion: v1
            kind: Service
            metadata:
              name: api
            spec:
              selector:
                app: api
            """
        expect(
            ClipboardDevOpsAction.available(for: service) == [.convertKubernetesYAML],
            "recognises Kubernetes Service YAML")
        expect(
            ClipboardDevOpsAction.available(for: "apiVersion: v1\nkind: ConfigMap\ndata: {}")
                == [.convertKubernetesYAML],
            "recognises other Kubernetes resources")
        expect(
            ClipboardDevOpsAction.available(for: #"{"kind":"Secret","data":{}}"#)
                == [.decodeKubernetesSecret],
            "recognises Kubernetes Secret JSON")
        expect(
            ClipboardDevOpsAction.available(for: "kind: Pod\nmetadata: {}") == [],
            "does not label incomplete YAML as a Kubernetes resource")
        expect(
            ClipboardDevOpsAction.available(for: "items:\n  - kind: Pod\n    apiVersion: v1") == [],
            "does not recognize nested fields as a top-level Kubernetes resource")
        expect(
            ClipboardDevOpsAction.available(for: "192.168.1.1") == [],
            "does not label a bare IPv4 address as CIDR")
        expect(
            ClipboardDevOpsAction.available(for: String(repeating: "a", count: 1_048_577)) == [],
            "does not scan over-limit text")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
