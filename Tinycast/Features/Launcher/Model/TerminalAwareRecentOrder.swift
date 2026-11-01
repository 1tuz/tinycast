import Foundation

enum TerminalAwareRecentOrder {
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "org.wezfurlong.wezterm"
    ]

    static func isTerminal(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return terminalBundleIDs.contains(bundleID)
    }

    static func prioritize<Element>(
        _ entries: [Element],
        terminalIsActive: Bool,
        category: (Element) -> DevOpsCommandCategory?
    ) -> [Element] {
        guard terminalIsActive, entries.count > 1 else { return entries }
        return entries.enumerated().sorted { left, right in
            let leftIsDevOps = category(left.element) != nil
            let rightIsDevOps = category(right.element) != nil
            if leftIsDevOps != rightIsDevOps { return leftIsDevOps }
            return left.offset < right.offset
        }.map(\.element)
    }
}
