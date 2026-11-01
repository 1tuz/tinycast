import AppKit

@MainActor
final class KubePodsWindowController {
    private let coordinator: KubePodsCoordinator
    private let activationPolicy: ActivationPolicy
    private lazy var window = AppWindowController(
        title: String(localized: "Kubernetes Pods"),
        contentSize: CGSize(width: 760, height: 560), resizable: true,
        autosaveName: "KubePodsWindow", activation: activationPolicy, closesOnEscape: true)

    init(coordinator: KubePodsCoordinator, activationPolicy: ActivationPolicy) {
        self.coordinator = coordinator
        self.activationPolicy = activationPolicy
    }

    func show() {
        window.show {
            KubePodsScreen(coordinator: coordinator).environment(AppCore.shared)
        }
    }
}
