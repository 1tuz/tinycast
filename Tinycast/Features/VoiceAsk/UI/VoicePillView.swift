import AppKit
import SwiftUI

/// Tiny floating Voice Ask pill: non-activating, glass, waveform + timer, cancel on hover.
@MainActor
final class VoicePillController {
    var onCancel: (() -> Void)?

    private var panel: HUDPanel?
    private var host: NSHostingView<VoicePillView>?
    private var metrics = InterfaceMetrics.standard

    func updateMetrics(_ metrics: InterfaceMetrics) {
        self.metrics = metrics
    }

    func show(phase: VoiceAskPhase, levels: [CGFloat], elapsed: Duration, error: String?) {
        let size = VoicePillView.preferredSize(metrics)
        let view = VoicePillView(
            phase: phase, levels: levels, elapsed: elapsed, error: error,
            onCancel: onCancel, metrics: metrics)
        if let host {
            host.rootView = view
            host.frame.size = size
            panel?.setContentSize(size)
        } else {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            let panel = HUDPanel(acceptsMouseEvents: true)
            panel.contentView = host
            panel.setContentSize(size)
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
        let size = VoicePillView.preferredSize(metrics)
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
    var onCancel: (() -> Void)?
    var metrics: InterfaceMetrics = .standard
    @State private var hovered = false

    static func preferredSize(_ metrics: InterfaceMetrics) -> NSSize {
        // Scales with Interface Size: ~220×44 at standard.
        NSSize(
            width: metrics.scaled(220),
            height: max(metrics.size.menuButton, metrics.scaled(44)))
    }

    var body: some View {
        Group {
            if let onCancel {
                Button(action: onCancel) { content }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel Voice Ask")
            } else {
                content
            }
        }
        .onHover { isHovered in
            if onCancel != nil {
                withAnimation(.easeOut(duration: Theme.Duration.hover)) {
                    hovered = isHovered
                }
            }
        }
    }

    private var content: some View {
        HStack(spacing: metrics.spacing.md) {
            mark
            if let error {
                Text(error)
                    .font(metrics.typography.bar)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            } else {
                VoiceWaveformView(levels: levels, isActive: phase == .listening)
                    .frame(maxWidth: .infinity, maxHeight: metrics.scaled(22))
                Text(timerText)
                    .font(metrics.typography.keyCap.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minWidth: metrics.scaled(36), alignment: .trailing)
            }
        }
        .padding(.horizontal, metrics.spacing.lg)
        .padding(.vertical, metrics.spacing.md)
        .frame(
            width: Self.preferredSize(metrics).width,
            height: Self.preferredSize(metrics).height)
        .background(hovered ? Theme.Colors.controlHover : Theme.Colors.panelScrim)
        .background(GlassEffectView())
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.Colors.border, lineWidth: Theme.Size.hairline)
        }
    }

    private var mark: some View {
        Group {
            if hovered, onCancel != nil {
                Image(systemName: "xmark")
                    .font(metrics.typography.menuIcon.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    .transition(.opacity)
            } else {
                Image(systemName: phase == .listening ? "mic.fill" : "waveform")
                    .font(metrics.typography.menuIcon)
                    .foregroundStyle(Theme.Colors.progress)
                    .frame(width: metrics.size.menuIcon, height: metrics.size.menuIcon)
                    .transition(.opacity)
            }
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

/// Shared mic control for launcher header and Quick AI header.
struct VoiceAskMicButton: View {
    @Environment(\.metrics) private var metrics
    let isRecording: Bool
    let levels: [CGFloat]
    let action: () -> Void

    var body: some View {
        BarButton(chrome: .rounded, action: action) {
            Group {
                if isRecording {
                    VoiceWaveformView(levels: levels, isActive: true)
                        .frame(width: metrics.scaled(28), height: metrics.scaled(14))
                } else {
                    Image(systemName: "mic.fill")
                        .font(metrics.typography.bar)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(width: metrics.scaled(28), height: metrics.scaled(16))
        }
        .help(isRecording ? "Stop Voice Ask" : "Dictate with Voice Ask")
    }
}
