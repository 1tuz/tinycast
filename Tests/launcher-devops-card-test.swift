import Foundation

@main
@MainActor
struct LauncherDevOpsCardTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        cidrCardShowsLocalResult()
        jwtCardShowsUnverifiedDecode()
        jiraRequiresConfiguredSafeBaseURL()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func cidrCardShowsLocalResult() {
        let card = DevOpsLeadCard.resolve(query: "192.168.1.10/24", jiraBaseURL: nil)
        guard case .cidr(let result) = card else {
            expect(false, "valid CIDR gets a lead card")
            return
        }
        expect(result.contains("Network: 192.168.1.0"), "CIDR card includes local network result")
        expect(result.contains("Hosts: 254"), "CIDR card includes host count")
        expect(
            DevOpsLeadCard.resolve(query: "192.168.1.1", jiraBaseURL: nil) == nil,
            "bare IPv4 does not get a CIDR card")
    }

    static func jwtCardShowsUnverifiedDecode() {
        let token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJ0ZXN0In0.sig"
        guard case .jwt(let result) = DevOpsLeadCard.resolve(query: token, jiraBaseURL: nil) else {
            expect(false, "JWT gets a lead card")
            return
        }
        expect(result.contains("test"), "JWT card includes locally decoded payload")
        expect(result.contains("Signature not verified"), "JWT card disclaims signature verification")
        expect(
            DevOpsLeadCard.resolve(query: "a.b.c", jiraBaseURL: nil) == nil,
            "invalid token does not get a card")
    }

    static func jiraRequiresConfiguredSafeBaseURL() {
        let base = "https://jira.example.com/jira/"
        let card = DevOpsLeadCard.resolve(query: "DO-7082", jiraBaseURL: base)
        expect(
            card == .jira(key: "DO-7082", url: URL(string: "https://jira.example.com/jira/browse/DO-7082")!),
            "Jira URL comes from the configured base URL")
        expect(
            DevOpsLeadCard.resolve(query: "DO-7082", jiraBaseURL: nil) == nil,
            "Jira key does not open without user configuration")
        for base in [
            "ftp://jira.example.com", "https://user@jira.example.com", "https://jira.example.com?x=1",
            "https://jira.example.com/#fragment"
        ] {
            expect(
                DevOpsLeadCard.resolve(query: "DO-7082", jiraBaseURL: base) == nil,
                "unsafe Jira base URL is refused: \(base)")
        }
        for key in ["do-7082", "D-1", "DO-", "DO-7082/../../x"] {
            expect(
                DevOpsLeadCard.resolve(query: key, jiraBaseURL: base) == nil,
                "invalid Jira key does not get a card: \(key)")
        }
    }
}
