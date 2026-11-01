import Foundation
import SwiftUI
import UniformTypeIdentifiers

private enum PortForwardResourceKind: String, CaseIterable, Identifiable {
    case pod
    case service
    case deployment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pod: String(localized: "Pod")
        case .service: String(localized: "Service")
        case .deployment: String(localized: "Deployment")
        }
    }
}

struct PortForwardSection: View {
    let contextStore: KubeContextStore
    let manager: PortForwardManager

    @State private var resourceKind: PortForwardResourceKind = .service
    @State private var resourceName = ""
    @State private var kubeLocalPort = ""
    @State private var kubeRemotePort = ""
    @State private var vaultConfiguration: URL?
    @State private var vaultListenerPort = ""
    @State private var sshAlias = ""
    @State private var sshLocalPort = ""
    @State private var sshRemoteHost = ""
    @State private var sshRemotePort = ""
    @State private var isChoosingVaultConfiguration = false
    @State private var isStartingKubernetes = false
    @State private var isStartingVault = false
    @State private var isStartingSSH = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                if let errorMessage {
                    errorBanner(errorMessage)
                }
                kubernetesForm
                vaultForm
                sshForm
                sessions
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.panelScrim)
        .fileImporter(
            isPresented: $isChoosingVaultConfiguration,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: importVaultConfiguration)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Port Forwarding").font(.headline)
            Text("Start and manage Kubernetes, Vault Proxy, and SSH tunnels.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var kubernetesForm: some View {
        card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle("Kubernetes", symbol: "shippingbox")
                HStack(spacing: Theme.Spacing.md) {
                    Picker("Resource type", selection: $resourceKind) {
                        ForEach(PortForwardResourceKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .frame(width: 150)
                    TextField("Resource name", text: $resourceName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("Resource name"))
                }
                HStack(spacing: Theme.Spacing.md) {
                    portField("Local port", text: $kubeLocalPort)
                    portField("Remote port", text: $kubeRemotePort)
                }
                HStack {
                    contextSummary
                    Spacer(minLength: Theme.Spacing.md)
                    Button {
                        Task { await startKubernetesForward() }
                    } label: {
                        controlLabel("Start", symbol: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingKubernetes || contextStore.selectedContextName == nil)
                }
            }
        }
    }

    private var contextSummary: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text("Context and namespace")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let context = contextStore.selectedContextName {
                Text(verbatim: "\(context) · \(contextStore.selectedNamespace)")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else if contextStore.isLoading {
                HStack(spacing: Theme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text("Loading Kubernetes contexts…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if let loadError = contextStore.loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.destructive)
                    .textSelection(.enabled)
            } else {
                Text("Choose a Kubernetes context in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var vaultForm: some View {
        card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle("Vault Proxy", symbol: "lock.shield")
                HStack(spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text("Configuration file")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(vaultConfiguration?.lastPathComponent ?? String(localized: "No file selected"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: Theme.Spacing.md)
                    Button {
                        isChoosingVaultConfiguration = true
                    } label: {
                        controlLabel("Choose…", symbol: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                portField("Listener port shown", text: $vaultListenerPort)
                Text(
                    "Vault Proxy uses the listener address and port in this config. The port here is only for the session summary."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button {
                        Task { await startVaultProxy() }
                    } label: {
                        controlLabel("Start", symbol: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingVault || vaultConfiguration == nil)
                }
            }
        }
    }

    private var sshForm: some View {
        card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle("SSH Tunnel", symbol: "network")
                TextField("SSH alias", text: $sshAlias)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(Text("SSH alias"))
                HStack(spacing: Theme.Spacing.md) {
                    portField("Local port", text: $sshLocalPort)
                    TextField("Remote host", text: $sshRemoteHost)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text("Remote host"))
                    portField("Remote port", text: $sshRemotePort)
                }
                HStack {
                    Spacer()
                    Button {
                        Task { await startSSHTunnel() }
                    } label: {
                        controlLabel("Start", symbol: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingSSH)
                }
            }
        }
    }

    private var sessions: some View {
        card {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle("Sessions", symbol: "arrow.left.arrow.right")
                if manager.sessions.isEmpty {
                    Text("No port-forward sessions.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(manager.sessions) { session in
                        sessionRow(session)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: PortForwardSession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(session.displayTarget)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(portSummary(for: session))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(session.state.label)
                        .font(.caption)
                        .foregroundStyle(session.state.isActive ? .secondary : .tertiary)
                }
                Spacer(minLength: Theme.Spacing.md)
                if session.state.isActive {
                    Button(role: .destructive) {
                        manager.stop(id: session.id)
                    } label: {
                        controlLabel("Stop", symbol: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        manager.remove(id: session.id)
                    } label: {
                        controlLabel("Stop & Remove", symbol: "trash")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        manager.remove(id: session.id)
                    } label: {
                        controlLabel("Remove", symbol: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
            if let lastError = session.lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.destructive)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            SymbolImage(name: "exclamationmark.triangle", size: 14, monochrome: true)
            Text(message)
                .font(.caption)
                .textSelection(.enabled)
        }
        .foregroundStyle(Theme.Colors.destructive)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            content()
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(Theme.Colors.cardFill))
        .overlay(shape.strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            SymbolImage(name: symbol, size: 16, monochrome: true).accessibilityHidden(true)
            Text(title).font(.headline)
        }
    }

    private func controlLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            SymbolImage(name: symbol, size: 13, monochrome: true).accessibilityHidden(true)
            Text(title)
        }
    }

    private func portField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityLabel(Text(title))
    }

    private func portSummary(for session: PortForwardSession) -> String {
        guard session.request.kind == .vaultProxy else { return session.displayPorts }
        let port =
            session.displayPorts.split(separator: ":").last.map(String.init)
            ?? session.displayPorts
        return String(localized: "Port shown: \(port); the config controls the actual listener.")
    }

    private func startKubernetesForward() async {
        guard let context = contextStore.selectedContextName else {
            errorMessage = "Choose a Kubernetes context in Settings."
            return
        }
        isStartingKubernetes = true
        errorMessage = nil
        defer { isStartingKubernetes = false }
        do {
            let resource =
                "\(resourceKind.rawValue)/\(resourceName.trimmingCharacters(in: .whitespacesAndNewlines))"
            let request = try PortForwardRequest.kubernetes(
                context: context, namespace: contextStore.selectedNamespace,
                resource: resource, localPort: kubeLocalPort, remotePort: kubeRemotePort,
                policy: contextStore.policy)
            try await manager.start(request)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func startVaultProxy() async {
        guard let vaultConfiguration else {
            errorMessage = "Choose a Vault Proxy configuration file."
            return
        }
        isStartingVault = true
        errorMessage = nil
        defer { isStartingVault = false }
        do {
            let request = try PortForwardRequest.vaultProxy(
                configFile: vaultConfiguration,
                displayTarget: String(localized: "Vault Proxy · \(vaultConfiguration.lastPathComponent)"),
                listenerPort: try PortForwardRequest.parsePort(vaultListenerPort))
            try await manager.start(request)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func startSSHTunnel() async {
        isStartingSSH = true
        errorMessage = nil
        defer { isStartingSSH = false }
        do {
            let request = try PortForwardRequest.ssh(
                alias: sshAlias.trimmingCharacters(in: .whitespacesAndNewlines),
                localPort: sshLocalPort,
                remoteHost: sshRemoteHost.trimmingCharacters(in: .whitespacesAndNewlines),
                remotePort: sshRemotePort)
            try await manager.start(request)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func importVaultConfiguration(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            vaultConfiguration = urls.first
            errorMessage = nil
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled { return }
            errorMessage = error.localizedDescription
        }
    }

    private static func message(for error: Error) -> String {
        let policyError: KubeContextPolicyError?
        switch error {
        case let error as PortForwardRequestError:
            if case .policy(let policy) = error { policyError = policy } else { policyError = nil }
        case let error as PortForwardManagerError:
            if case .contextPolicy(let policy) = error { policyError = policy } else { policyError = nil }
        default:
            policyError = nil
        }
        guard let policyError else { return error.localizedDescription }
        return switch policyError {
        case .guardDisabled:
            String(localized: "Enable the Kubernetes context guard in Settings.")
        case .unavailableContext(let name):
            name.isEmpty
                ? String(localized: "Choose a Kubernetes context in Settings.")
                : String(localized: "The Kubernetes context is no longer available: \(name).")
        case .productionContext:
            String(localized: "This Kubernetes context is blocked by the context guard.")
        case .invalidNamespace:
            String(localized: "The Kubernetes namespace is invalid.")
        }
    }
}
