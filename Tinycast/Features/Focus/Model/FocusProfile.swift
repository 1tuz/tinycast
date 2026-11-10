import Foundation

/// A deliberately soft blocker: it hides apps and redirects supported active browser tabs.
/// It does not require elevated privileges and never modifies /etc/hosts or network settings.
struct FocusBlockedApplication: Codable, Equatable, Hashable, Identifiable, Sendable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

struct FocusProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var durationMinutes: Int = 45
    var blockedApplications: [FocusBlockedApplication] = []
    var blockedDomains: [String] = []
    /// Existing Apple Shortcuts may orchestrate app launches, window layouts, and notifications.
    var startShortcutID: UUID?
    var endShortcutID: UUID?
    /// VoiceCast workflows can also be attached directly to a Focus profile.
    var startWorkflowID: UUID?
    var endWorkflowID: UUID?

    static let initial: [FocusProfile] = [
        FocusProfile(name: "Работа", durationMinutes: 50),
        FocusProfile(name: "Чтение", durationMinutes: 30)
    ]
}

struct FocusSession: Codable, Equatable, Sendable {
    var profileID: UUID
    var startedAt: Date
    var deadline: Date
    /// Nil means running; otherwise the clock is stopped at this many seconds.
    var pausedSeconds: TimeInterval?
    /// An optional scheduled end to a break. On wake or relaunch, refresh resumes if elapsed.
    var resumeAt: Date?
    var extraBlockedApplications: [FocusBlockedApplication] = []
    var extraBlockedDomains: [String] = []
    var allowedDomainsUntil: [String: Date] = [:]
}

struct FocusSavedState: Codable, Sendable {
    var profiles: [FocusProfile]
    var selectedProfileID: UUID
    var session: FocusSession?
}

enum FocusDomain {
    /// Accept bare domains and https:// URLs. Do not store paths, wildcards or arbitrary scripts.
    static func normalize(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: candidate),
              let host = components.host?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              host.contains("."), !host.isEmpty, host.count <= 253
        else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 &&
            label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }) else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func matches(_ host: String, blocked: String) -> Bool {
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == blocked || host.hasSuffix("." + blocked)
    }

    static func shouldBlock(_ url: URL, domains: [String]) -> Bool {
        guard let host = url.host else { return false }
        return domains.contains { matches(host, blocked: $0) }
    }
}
