import Foundation

/// TCC state for the microphone. Same three cases as camera access.
enum MicrophoneAccess: Sendable {
    case granted
    case notDetermined
    case denied
}
