import Foundation

enum PortForwardState: Equatable, Sendable {
    case starting
    case running
    case reconnecting(attempt: Int, delaySeconds: Int, lastError: String)
    case failed(String)
    case stopped

    var isActive: Bool {
        switch self {
        case .starting, .running, .reconnecting: true
        case .failed, .stopped: false
        }
    }

    var label: String {
        switch self {
        case .starting: String(localized: "Starting")
        case .running: String(localized: "Running")
        case .reconnecting(let attempt, let delay, _):
            String(localized: "Retry \(attempt) in \(delay)s")
        case .failed: String(localized: "Failed")
        case .stopped: String(localized: "Stopped")
        }
    }

    var lastError: String? {
        switch self {
        case .reconnecting(_, _, let error), .failed(let error): error
        case .starting, .running, .stopped: nil
        }
    }
}

struct PortForwardSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let request: PortForwardRequest
    var state: PortForwardState
    var attempt = 0
    var lastError: String?

    var displayTarget: String { request.displayTarget }
    var displayPorts: String { request.displayPorts }
}

enum PortForwardBackoff {
    static let maximumDelaySeconds = 30

    static func delaySeconds(for retry: Int) -> Int {
        guard retry > 0 else { return 0 }
        return min(1 << min(retry - 1, 30), maximumDelaySeconds)
    }
}
