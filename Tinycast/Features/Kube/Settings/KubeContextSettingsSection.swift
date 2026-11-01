import SwiftUI

struct KubeContextSettingsSection: View {
    @Environment(KubeContextCoordinator.self) private var coordinator
    @Environment(AppCore.self) private var core
    @State private var namespaceDraft = "default"
    @State private var productionDraft = ""

    private var store: KubeContextStore { coordinator.store }

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { store.isEnabled }, set: store.setEnabled)) {
                SettingsRowTitle(.generalKubernetes, "Enable Kube Context Guard")
                Text("Reads kubeconfig only while enabled.")
            }
            if store.isEnabled {
                contextPicker
                if let name = store.selectedContextName {
                    LabeledContent {
                        HStack {
                            TextField("Namespace", text: $namespaceDraft)
                                .accessibilityLabel(Text("Namespace"))
                                .onSubmit { coordinator.select(name, namespace: namespaceDraft) }
                            Button("Apply") { coordinator.select(name, namespace: namespaceDraft) }
                                .disabled(!KubeCommandPolicy.isValidNamespace(namespaceDraft))
                        }
                    } label: {
                        SettingsRowTitle(.generalKubernetes, "Namespace")
                    }
                }
                LabeledContent {
                    VStack(alignment: .trailing) {
                        TextField("One exact context name per line", text: $productionDraft, axis: .vertical)
                            .lineLimit(3...6)
                            .accessibilityLabel(Text("Production contexts"))
                        Button("Apply") {
                            coordinator.store.setProductionContextNames(Set(
                                productionDraft.split(whereSeparator: \.isNewline).map {
                                    $0.trimmingCharacters(in: .whitespaces)
                                }.filter { !$0.isEmpty }))
                        }
                        .accessibilityLabel(Text("Apply production contexts"))
                    }
                } label: {
                    SettingsRowTitle(.generalKubernetes, "Production contexts")
                }
                Text("Mutating commands are blocked for these exact context names.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reload kubeconfig") { store.reload() }
                        .disabled(store.isLoading)
                    Button("Pods and Diagnostics…") {
                        core.kubePodsWindowController.show()
                    }
                    .disabled(store.selectedContextName == nil)
                    if store.isLoading { ProgressView().controlSize(.small) }
                }
                if let error = store.loadError ?? coordinator.selectionError {
                    Text(error).foregroundStyle(.red)
                }
            }
        } header: {
            SettingsSectionHeader(.generalKubernetes)
        } footer: {
            Text("Tinycast passes its selected context explicitly and keeps kubectl's current context unchanged.")
        }
        .onAppear {
            namespaceDraft = store.selectedNamespace
            productionDraft = store.productionContextNames.sorted().joined(separator: "\n")
        }
        .onChange(of: store.selectedNamespace) { _, namespace in namespaceDraft = namespace }
        .onChange(of: store.selectedContextName) { _, _ in namespaceDraft = store.selectedNamespace }
        .onChange(of: store.productionContextNames) { _, names in
            productionDraft = names.sorted().joined(separator: "\n")
        }
    }

    private var contextPicker: some View {
        Picker(selection: Binding(
            get: { store.selectedContextName ?? "" },
            set: { if !$0.isEmpty { coordinator.select($0) } }
        )) {
            Text("Choose a context").tag("")
            ForEach(store.contexts) { context in
                Text(verbatim: context.name).tag(context.name)
            }
        } label: {
            SettingsRowTitle(.generalKubernetes, "Context")
        }
        .disabled(store.contexts.isEmpty)
    }

}
