import SwiftUI

private enum KubeToolsPane: Hashable {
    case pods
    case portForwards
}

struct KubePodsScreen: View {
    let coordinator: KubePodsCoordinator
    @Environment(AppCore.self) private var core
    @State private var selectedPane: KubeToolsPane = .pods
    @State private var output = ""
    @State private var outputTitle = ""
    @State private var activeSession: ShellCommandSession?
    @State private var activeSessionID: UUID?
    @State private var errorMessage: String?
    @State private var deploymentName = ""

    private var contextStore: KubeContextStore { core.kubeContexts }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Picker("Kubernetes tools", selection: $selectedPane) {
                Text("Pods").tag(KubeToolsPane.pods)
                Text("Port Forwards").tag(KubeToolsPane.portForwards)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)

            if selectedPane == .pods {
                podsPane
            } else {
                PortForwardSection(contextStore: contextStore, manager: core.portForwardManager)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelScrim)
        .task { await coordinator.refresh() }
        .onChange(of: contextStore.selectedContextName) { _, _ in Task { await coordinator.refresh() } }
        .onChange(of: contextStore.selectedNamespace) { _, _ in Task { await coordinator.refresh() } }
        .onDisappear { activeSession?.stop() }
    }

    private var podsPane: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            if !outputTitle.isEmpty {
                outputPanel
            } else {
                podsList
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .padding(.bottom, Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Kubernetes Pods").font(.headline)
                Text(
                    verbatim:
                        "\(contextStore.selectedContextName ?? String(localized: "No context")) · \(contextStore.selectedNamespace)"
                )
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker(
                "Filter",
                selection: Binding(
                    get: { coordinator.filter }, set: coordinator.setFilter)
            ) {
                Text("All").tag(KubePodFilter.all)
                Text("Problems").tag(KubePodFilter.problems)
            }
            .pickerStyle(.segmented).frame(width: 180)
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await coordinator.refresh() } }
                .disabled(coordinator.isLoading)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var podsList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if coordinator.isLoading { ProgressView().controlSize(.small) }
            if coordinator.visiblePods.isEmpty && !coordinator.isLoading {
                ContentUnavailableView(
                    coordinator.errorMessage == nil ? "No Pods" : "Unable to Load Pods",
                    systemImage: "shippingbox",
                    description: Text(coordinator.errorMessage ?? "No pods are available in this namespace."))
            } else {
                List(coordinator.visiblePods) { pod in podRow(pod) }
                    .listStyle(.inset)
            }
            if let context = contextStore.selectedContextName, !contextStore.isProduction(context) {
                HStack(spacing: Theme.Spacing.md) {
                    TextField("Deployment name", text: $deploymentName)
                        .textFieldStyle(.roundedBorder)
                    Button("Restart Deployment…") { restartDeployment() }
                        .disabled(!KubeResourceName.isValid(deploymentName))
                }
            } else if contextStore.selectedContextName != nil {
                Label("Mutating commands are blocked for production contexts.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func podRow(_ pod: KubePod) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(verbatim: pod.name).font(.system(.body, design: .monospaced))
                Text(
                    verbatim:
                        "\(pod.readyContainerCount)/\(pod.containerCount) containers ready · \(pod.restartCount) restarts"
                )
                .font(.caption).foregroundStyle(.secondary)
                if !pod.containers.isEmpty {
                    Text(pod.containers.map { "\($0.name): \($0.state)" }.joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                }
            }
            Spacer()
            Label(
                pod.displayStatus,
                systemImage: pod.isProblem ? "exclamationmark.triangle" : "checkmark.circle"
            )
            .font(.caption).foregroundStyle(pod.isProblem ? .orange : .secondary)
            Menu {
                Button("View Logs…", systemImage: "text.alignleft") { startLogs(pod) }
                Button("Describe Pod…", systemImage: "doc.text.magnifyingglass") { describe(pod) }
                Button("Copy Pod Name", systemImage: "square.on.square") { coordinator.copyName(of: pod) }
                Button("Open Exec in Terminal…", systemImage: "terminal") { openExec(pod) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var outputPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(outputTitle).font(.headline).lineLimit(1)
                Spacer()
                if activeSession != nil {
                    Button("Stop", systemImage: "stop.fill") { activeSession?.stop() }
                }
                Button("Back", systemImage: "chevron.left") { closeOutput() }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    Text(output.isEmpty ? String(localized: "Waiting for command output…") : output)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("tail")
                }
                .onChange(of: output) { _, _ in proxy.scrollTo("tail", anchor: .bottom) }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Colors.terminalSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        }
        .padding(.horizontal, Theme.Spacing.md)
    }

    private func startLogs(_ pod: KubePod) {
        errorMessage = nil
        Task {
            do {
                let session = try await coordinator.logs(for: pod)
                let identity = UUID()
                activeSessionID = identity
                activeSession = session
                outputTitle = String(localized: "Logs · \(pod.name)")
                output = ""
                for await event in session.events {
                    guard activeSessionID == identity else { continue }
                    switch event {
                    case .output(let text): append(text)
                    case .finished(let result):
                        activeSession = nil
                        if case .launchFailed(let reason) = result.termination { errorMessage = reason }
                    }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func describe(_ pod: KubePod) {
        errorMessage = nil
        Task {
            do {
                output = try await coordinator.describe(pod)
                outputTitle = String(localized: "Describe · \(pod.name)")
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func openExec(_ pod: KubePod) {
        errorMessage = nil
        Task {
            do {
                let command = try await coordinator.terminalExec(for: pod)
                try TerminalCommandLauncher.open(
                    executable: command.executable, arguments: command.arguments)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func restartDeployment() {
        guard let context = contextStore.selectedContextName,
            !contextStore.isProduction(context)
        else { return }
        let name = deploymentName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Restart deployment \(name)?"),
                    message: String(
                        localized:
                            "Restart deployment \(name) in \(context) · \(contextStore.selectedNamespace)."),
                    symbol: "arrow.clockwise", confirmTitle: String(localized: "Restart"),
                    tone: .danger, confirmRole: .destructive)
            else { return }
            do { try await coordinator.restartDeployment(named: name, confirmedByUser: true) } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func append(_ text: String) {
        output += text
        if output.utf8.count > 256 * 1024 { output = String(output.suffix(128 * 1024)) }
    }

    private func closeOutput() {
        activeSession?.stop()
        activeSession = nil
        activeSessionID = nil
        outputTitle = ""
        output = ""
    }
}
