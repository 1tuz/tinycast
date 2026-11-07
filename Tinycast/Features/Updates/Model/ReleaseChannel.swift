import Foundation

/// One shipping app, one bundle id; a local build has no release stream and never updates itself.
enum ReleaseChannel: Sendable {
    case stable
    case development

    init(bundleID: String?) {
        switch bundleID {
        case "com.tinycast.app": self = .stable
        default: self = .development
        }
    }

    var updatesItself: Bool { self != .development }

    /// Historical beta tags exist in the release list; they are never an update.
    func accepts(prerelease: Bool) -> Bool {
        switch self {
        case .stable: return !prerelease
        case .development: return false
        }
    }
}
