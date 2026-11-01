import Foundation
import Observation

@MainActor
@Observable
final class KubeContextStore {
    private(set) var isEnabled: Bool
    private(set) var contexts: [KubeContext] = []
    private(set) var selectedContextName: String?
    private(set) var selectedNamespace = "default"
    private(set) var productionContextNames: Set<String>
    private(set) var loadError: String?
    private(set) var isLoading = false
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let loader: @Sendable () async throws -> KubeConfiguration
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var operation = UUID()

    init(settings: AppSettings,
         loader: @escaping @Sendable () async throws -> KubeConfiguration = { try await KubeConfigLoader.load() }) {
        self.settings = settings
        self.loader = loader
        isEnabled = settings.kubeContextGuardEnabled
        productionContextNames = Set(settings.kubeProductionContexts)
        if isEnabled { reload() }
    }

    var selectedContext: KubeContext? { contexts.first { $0.name == selectedContextName } }
    var policy: KubeCommandPolicy {
        KubeCommandPolicy(isEnabled: isEnabled, contextNames: Set(contexts.map(\.name)),
                          productionContextNames: productionContextNames)
    }

    func setEnabled(_ enabled: Bool) {
        if settings.kubeContextGuardEnabled != enabled { settings.kubeContextGuardEnabled = enabled }
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled { reload() } else {
            operation = UUID()
            loadTask?.cancel()
            loadTask = nil
            isLoading = false
            contexts = []
            selectedContextName = nil
            selectedNamespace = "default"
            loadError = nil
        }
    }

    func reload() {
        guard isEnabled else { return }
        loadTask?.cancel()
        let identity = UUID()
        operation = identity
        isLoading = true
        loadError = nil
        let loader = loader
        loadTask = Task { [weak self] in
            do {
                let configuration = try await loader()
                guard let self, !Task.isCancelled, self.operation == identity, self.isEnabled else { return }
                self.apply(configuration)
            } catch {
                guard let self, !Task.isCancelled, self.operation == identity, self.isEnabled else { return }
                self.contexts = []
                self.selectedContextName = nil
                self.loadError = Self.message(for: error)
            }
            guard let self, self.operation == identity else { return }
            self.isLoading = false
            self.loadTask = nil
        }
    }

    func select(contextName: String, namespace: String?) throws {
        try policy.requireContext(contextName)
        guard let context = contexts.first(where: { $0.name == contextName }) else {
            throw KubeContextPolicyError.unavailableContext(contextName)
        }
        let namespace = namespace.flatMap { $0.isEmpty ? nil : $0 } ?? context.namespace
        guard KubeCommandPolicy.isValidNamespace(namespace) else { throw KubeContextPolicyError.invalidNamespace }
        selectedContextName = contextName
        selectedNamespace = namespace
        settings.kubeSelectedContext = contextName
        settings.kubeSelectedNamespace = namespace
    }

    func setProductionContextNames(_ names: Set<String>) {
        productionContextNames = names
        settings.kubeProductionContexts = names.sorted()
    }

    func applyPreferences() {
        setEnabled(settings.kubeContextGuardEnabled)
        productionContextNames = Set(settings.kubeProductionContexts)
        guard isEnabled, !isLoading else { return }
        if let name = settings.kubeSelectedContext {
            if contexts.contains(where: { $0.name == name }),
                KubeCommandPolicy.isValidNamespace(settings.kubeSelectedNamespace) {
                selectedContextName = name
                selectedNamespace = settings.kubeSelectedNamespace
            } else {
                selectedContextName = nil
            }
        } else {
            selectedContextName = nil
        }
    }

    func isProduction(_ name: String) -> Bool { productionContextNames.contains(name) }
    func requireNonProduction(_ name: String) throws { try policy.requireNonProduction(name) }

    func commandArguments(for contextName: String? = nil, namespace: String? = nil,
                          operation: KubeOperation) throws -> [String] {
        guard isEnabled else { throw KubeContextPolicyError.guardDisabled }
        guard let name = contextName ?? selectedContextName else {
            throw KubeContextPolicyError.unavailableContext("")
        }
        return try policy.arguments(for: name, namespace: namespace ?? selectedNamespace, operation: operation)
    }

    private func apply(_ configuration: KubeConfiguration) {
        contexts = configuration.contexts
        if let saved = settings.kubeSelectedContext, contexts.contains(where: { $0.name == saved }) {
            selectedContextName = saved
            selectedNamespace = KubeCommandPolicy.isValidNamespace(settings.kubeSelectedNamespace)
                ? settings.kubeSelectedNamespace : selectedContext?.namespace ?? "default"
        } else if let current = configuration.currentContextName,
            let context = contexts.first(where: { $0.name == current }) {
            selectedContextName = current
            selectedNamespace = context.namespace
            settings.kubeSelectedContext = current
            settings.kubeSelectedNamespace = context.namespace
        } else {
            selectedContextName = nil
            selectedNamespace = "default"
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? KubeConfigReaderError {
        case .homeUnavailable:
            String(localized: "The home directory is unavailable.")
        case .unreadableFile:
            String(localized: "Unable to read a kubeconfig file.")
        case .invalidDocument:
            String(localized: "Kubeconfig contains invalid or unsupported YAML or JSON.")
        case .invalidRoot, .invalidField:
            String(localized: "Kubeconfig contains invalid context metadata.")
        case nil:
            String(localized: "Unable to read kubeconfig.")
        }
    }
}
