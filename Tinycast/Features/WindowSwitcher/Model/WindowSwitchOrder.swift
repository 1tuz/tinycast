import Foundation

/// Recent history comes first; minimized state, app rank, and name break ties in that order.
enum WindowSwitchOrder {
    /// A total order, so the sort is deterministic however the sweep happened to enumerate apps.
    static func sorted(
        _ entries: [WindowSwitchEntry], recentHistory: [String] = []
    ) -> [WindowSwitchEntry] {
        var recentRank: [String: Int] = [:]
        for (rank, key) in recentHistory.enumerated() where recentRank[key] == nil {
            recentRank[key] = rank
        }
        return entries.sorted { left, right in
            let leftRecentRank = recentRank[left.historyKey] ?? .max
            let rightRecentRank = recentRank[right.historyKey] ?? .max
            if leftRecentRank != rightRecentRank { return leftRecentRank < rightRecentRank }
            if left.isMinimized != right.isMinimized { return right.isMinimized }
            if left.appRank != right.appRank { return left.appRank < right.appRank }
            if left.appName != right.appName {
                return left.appName.localizedCaseInsensitiveCompare(right.appName)
                    == .orderedAscending
            }
            return left.handle < right.handle
        }
    }
}
