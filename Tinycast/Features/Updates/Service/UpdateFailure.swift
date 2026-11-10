import Foundation

enum UpdateFailure: LocalizedError, Equatable {
    case downloadFailed(String)
    case mountFailed(String)
    case noAppInImage
    case copyFailed(String)
    case bundleMismatch
    case identityMismatch
    case versionMismatch(expected: String, found: String)
    case replaceFailed(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail):
            return String(localized: "The download did not finish. \(detail)")
        case .mountFailed(let detail):
            return String(localized: "The downloaded disk image could not be mounted. \(detail)")
        case .noAppInImage:
            return String(localized: "The downloaded archive does not contain SpeechCast.")
        case .copyFailed(let detail):
            return String(localized: "The downloaded app could not be copied out of the disk image. \(detail)")
        case .bundleMismatch:
            return String(localized: "The downloaded app is not this build of SpeechCast.")
        case .identityMismatch:
            return String(
                localized: "The downloaded app is not signed by the identity this copy was signed with.")
        case .versionMismatch(let expected, let found):
            return String(localized: "The downloaded app is version \(found), not \(expected).")
        case .replaceFailed(let detail):
            return String(localized: "SpeechCast could not be replaced. \(detail)")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .identityMismatch, .bundleMismatch, .versionMismatch:
            return String(
                localized: """
                    Nothing was installed. Download the release from GitHub instead, so you can \
                    check it yourself.
                    """)
        case .replaceFailed:
            return String(
                localized: """
                    Nothing was installed. This usually means /Applications is not writable by \
                    your account.
                    """)
        default:
            return nil
        }
    }
}
