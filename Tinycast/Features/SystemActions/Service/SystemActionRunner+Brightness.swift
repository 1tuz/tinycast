import CoreGraphics
import Foundation

extension SystemActionRunner {
    /// Display brightness through the gamma table: the one public lever that reaches every
    /// screen, including externals without DDC. `percent` maps 0–100 to gamma 1–5; 100 restores
    /// the linear table, so nothing is left behind after a reset.
    nonisolated static func setBrightness(percent: Int) throws {
        let clamped = max(0, min(100, percent))
        let gamma = CGGammaValue(1.0 + Double(100 - clamped) / 25.0)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            throw SystemActionFailure(String(localized: "No display is available."))
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            throw SystemActionFailure(String(localized: "macOS did not report the displays."))
        }
        var failures = 0
        for display in ids.prefix(Int(count)) {
            // value = Min + (Max − Min) · index^gamma: a Max below 1 darkens, gamma steepens black.
            let scale = CGGammaValue(clamped) / 100
            let status = CGSetDisplayTransferByFormula(
                display, 0, scale, gamma, 0, scale, gamma, 0, scale, gamma)
            if status != .success { failures += 1 }
        }
        guard failures < Int(count) else {
            throw SystemActionFailure(String(localized: "macOS could not change brightness."))
        }
    }
}
