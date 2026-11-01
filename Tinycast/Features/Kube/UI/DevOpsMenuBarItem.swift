import SwiftUI

struct DevOpsMenuBarLabel: View {
    @Environment(KubeContextCoordinator.self) private var coordinator
    @Environment(AppCore.self) private var core

    var body: some View {
        let store = coordinator.store
        let sessions = core.portForwardManager
        Label {
            if let context = store.selectedContextName {
                Text(
                    verbatim: KubeMenuBarSummary.label(
                        contextName: context, namespace: store.selectedNamespace)
                )
                .accessibilityLabel(Text(verbatim: "\(context) · \(store.selectedNamespace)"))
            } else if sessions.hasActiveSessions {
                Text("Port Forwards")
            } else {
                Text("Kubernetes")
            }
        } icon: {
            Image(systemName: "network")
        }
    }
}

struct DevOpsMenuBarItem: View {
    @Environment(KubeContextCoordinator.self) private var coordinator
    @Environment(AppCore.self) private var core

    var body: some View {
        let store = coordinator.store
        let portForwards = core.portForwardManager
        Group {
            if store.isEnabled {
                Section {
                    if let name = store.selectedContextName {
                        Text(verbatim: KubeMenuBarSummary.shortened(name))
                            .accessibilityLabel(Text(verbatim: name))
                        Text(verbatim: KubeMenuBarSummary.shortened(store.selectedNamespace))
                            .accessibilityLabel(Text(verbatim: store.selectedNamespace))
                        if store.isProduction(name) { Text("Production: read-only") }
                    } else {
                        Text("Choose a context")
                    }
                    Menu("Context") {
                        ForEach(store.contexts) { context in
                            Button {
                                coordinator.select(context.name)
                            } label: {
                                if context.name == store.selectedContextName {
                                    Label {
                                        Text(verbatim: KubeMenuBarSummary.shortened(context.name))
                                    } icon: {
                                        Image(systemName: "checkmark")
                                    }
                                } else {
                                    Text(verbatim: KubeMenuBarSummary.shortened(context.name))
                                }
                            }
                            .accessibilityLabel(Text(verbatim: context.name))
                            .help(context.name)
                        }
                    }
                    .disabled(store.contexts.isEmpty)
                }
            }
            if !portForwards.sessions.isEmpty {
                Section("Port Forwards") {
                    ForEach(portForwards.sessions) { session in
                        Menu {
                            Text(verbatim: session.displayPorts)
                            Text(session.state.label)
                            if let error = session.state.lastError {
                                Text(verbatim: error)
                            }
                            if session.state.isActive {
                                Button("Stop", systemImage: "stop.fill") {
                                    portForwards.stop(id: session.id)
                                }
                            } else {
                                Button("Remove", systemImage: "trash") {
                                    portForwards.remove(id: session.id)
                                }
                            }
                        } label: {
                            Text(verbatim: KubeMenuBarSummary.shortened(session.displayTarget))
                        }
                    }
                }
            }
            Section {
                if store.isEnabled {
                    Button("Reload kubeconfig") { store.reload() }
                        .disabled(store.isLoading)
                    Button("Pods and Diagnostics…") {
                        core.kubePodsWindowController.show()
                    }
                    .disabled(store.selectedContextName == nil)
                    Button("Kubernetes Settings…") { coordinator.show() }
                }
                if store.isEnabled || portForwards.hasActiveSessions {
                    Button("Port Forward Manager…") { core.kubePodsWindowController.show() }
                }
            }
        }
        .labelStyle(.titleAndIcon)
    }
}
