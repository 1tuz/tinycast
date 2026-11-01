import Foundation

@main
struct TerminalAwareRecentTests {
    private struct Entry: Equatable {
        let id: Int
        let category: DevOpsCommandCategory?
    }

    static func main() {
        terminalDetection()
        order()
    }

    private static func terminalDetection() {
        expect(TerminalAwareRecentOrder.isTerminal(bundleID: "com.apple.Terminal"), "Terminal.app detected")
        expect(TerminalAwareRecentOrder.isTerminal(bundleID: "com.googlecode.iterm2"), "iTerm detected")
        expect(TerminalAwareRecentOrder.isTerminal(bundleID: nil) == false, "missing app is not a terminal")
        expect(
            TerminalAwareRecentOrder.isTerminal(bundleID: "com.apple.finder") == false,
            "Finder is not a terminal")
    }

    private static func order() {
        let entries = [
            Entry(id: 1, category: nil),
            Entry(id: 2, category: .git),
            Entry(id: 3, category: .docker),
            Entry(id: 4, category: nil)
        ]
        let terminalOrder = TerminalAwareRecentOrder.prioritize(
            entries, terminalIsActive: true, category: \.category)
        expect(terminalOrder.map(\.id) == [2, 3, 1, 4], "DevOps rows rise and both groups stay stable")
        let regularOrder = TerminalAwareRecentOrder.prioritize(
            entries, terminalIsActive: false, category: \.category)
        expect(regularOrder == entries, "other apps keep learned Recent order")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        print("FAIL: \(message)")
        exit(1)
    }
}
