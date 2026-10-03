import AppKit
import SwiftUI

/// Tiny floating Voice Ask pill: non-activating, glass, waveform + timer.
@MainActor
final class VoicePillController {
    var onCancel: (() -> Void)?

    private var panel: HUDPanel?
    private var host: NSHostingView<VoicePillView>?

    func show(phase: VoiceAskPhase, levels: [CGFloat], elapsed: Duration, error: String?) {
        let view = VoicePillView(phase: phase, levels: levels, elapsed: elapsed, error: error)
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: VoicePillView.preferredSize)
            let panel = HUDPanel(acceptsMouseEvents: true)
            panel.contentView = host
            panel.setContentSize(VoicePillView.preferredSize)
            self.host = host
            self.panel = panel
        }
        guard let panel else { return }
        position(panel)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.panel?.orderOut(nil)
                self?.panel = nil
                self?.host = nil
            }
        }
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.underCursor ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = VoicePillView.preferredSize
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + visible.height * 0.18,
                width: size.width,
                height: size.height),
            display: true)
    }
}

struct VoicePillView: View {
    let phase: VoiceAskPhase
    let levels: [CGFloat]
    let elapsed: Duration
    let error: String?

    static let preferredSize = NSSize(width: 220, height: 44)

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let error {
                Text(error)
                    .font(Theme.Typography.keyCap)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            } else {
                VoiceWaveformView(levels: levels, isActive: phase == .listening)
                    .frame(maxWidth: .infinity, maxHeight: 22)
                Text(timerText)
                    .font(Theme.Typography.keyCap.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline)
                }
                .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
        }
    }

    private var timerText: String {
        switch phase {
        case .connecting, .processing:
            return "…"
        case .listening, .completed, .failed, .idle:
            let total = Int(elapsed.components.seconds)
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }
}

struct VoiceWaveformView: View {
    let levels: [CGFloat]
    let isActive: Bool

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 2
            let width = max((geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1.5)
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Theme.Colors.textPrimary.opacity(isActive ? 0.85 : 0.35))
                        .frame(
                            width: width,
                            height: max(4, geo.size.height * (0.18 + level * 0.82)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
