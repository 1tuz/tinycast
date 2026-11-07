import AVFoundation
import Foundation

/// Mirrors `CameraAccess` so the Permissions pane can state microphone status the same way.
enum MicrophoneAccess: Sendable {
    case notDetermined
    case granted
    /// Denied or restricted: only System Settings can undo it, so both read the same to us.
    case denied

    static func current() -> MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
