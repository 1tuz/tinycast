import AppKit
import SwiftUI

/// The same small non-activating, draggable glass surface used for Voice Ask.
@MainActor
final class FocusHUDController {
    private var panel: NSPanel?

    func show(coordinator: FocusSessionCoordinator) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let width: CGFloat = 304
        let height: CGFloat = 68
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSHostingView(rootView: FocusHUDView(coordinator: coordinator))
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - width - 22,
                                         y: frame.maxY - height - 22))
        }
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }
}

private struct FocusHUDView: View {
    let coordinator: FocusSessionCoordinator

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "timer")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 3) {
                Text(coordinator.activeProfile?.name ?? "Фокус")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(coordinator.clockText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(coordinator.isPaused ? .secondary : .primary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            Button {
                if coordinator.isPaused { coordinator.resume() } else { coordinator.pause() }
            } label: {
                Image(systemName: coordinator.isPaused ? "play.fill" : "pause.fill")
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .help(coordinator.isPaused ? "Продолжить" : "Пауза")
            .accessibilityLabel(coordinator.isPaused ? "Продолжить фокус" : "Пауза фокуса")
            Button { coordinator.finish() } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 22, height: 24)
            }
            .buttonStyle(.plain)
            .help("Завершить сеанс")
            .accessibilityLabel("Завершить фокус")
        }
        .padding(.horizontal, 14)
        .frame(width: 304, height: 66)
        .modifier(FocusGlass())
    }
}

private struct FocusGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.dialog))
        } else {
            content.background(
                .regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.dialog))
        }
    }
}
