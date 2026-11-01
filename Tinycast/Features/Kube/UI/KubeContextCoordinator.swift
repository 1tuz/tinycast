import SwiftUI

@MainActor
@Observable
final class KubeContextCoordinator {
    let store: KubeContextStore
    private let settingsCoordinator: SettingsCoordinator
    private let paletteCoordinator: PaletteCoordinator
    private(set) var selectionError: String?

    init(store: KubeContextStore, settingsCoordinator: SettingsCoordinator,
         paletteCoordinator: PaletteCoordinator) {
        self.store = store
        self.settingsCoordinator = settingsCoordinator
        self.paletteCoordinator = paletteCoordinator
    }

    func show() {
        if paletteCoordinator.isVisible { paletteCoordinator.hidePalette(restoreFocus: false) }
        settingsCoordinator.showSettings(tab: .general, revealing: .section(.generalKubernetes))
    }

    func select(_ name: String, namespace: String? = nil) {
        do {
            try store.select(contextName: name, namespace: namespace)
            selectionError = nil
        } catch {
            selectionError = String(localized: "Choose an available context and a valid namespace.")
        }
    }
}
