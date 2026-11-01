import SwiftUI

struct AnsibleScreen: View {
    @Bindable var coordinator: AnsibleCoordinator

    var body: some View {
        Form {
            Section {
                fileRow(
                    title: String(localized: "Inventory"), url: coordinator.inventoryURL,
                    button: String(localized: "Choose…"), action: coordinator.chooseInventory)
                fileRow(
                    title: String(localized: "Playbook"), url: coordinator.playbookURL,
                    button: String(localized: "Choose…"), action: coordinator.choosePlaybook)
                if coordinator.isLoadingInventory {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Reading inventory…").foregroundStyle(.secondary)
                    }
                }
                if let inventory = coordinator.inventory {
                    Picker("Host or group", selection: $coordinator.selectedTarget) {
                        Text("Choose a host or group").tag("")
                        if !inventory.hosts.isEmpty {
                            Section("Hosts") {
                                ForEach(inventory.hosts, id: \.self) { host in
                                    Text(verbatim: host).tag(host)
                                }
                            }
                        }
                        if !inventory.groups.isEmpty {
                            Section("Groups") {
                                ForEach(inventory.groups) { group in
                                    Text(verbatim: "\(group.name) (\(group.hosts.count))")
                                        .tag(group.name)
                                }
                            }
                        }
                    }
                    .disabled(coordinator.isRunning)
                }
            } header: {
                Text("Ansible")
            } footer: {
                Text("Inventory is read with ansible-inventory --list. Tinycast stores no inventory output.")
            }

            Section {
                TextField("Limit", text: $coordinator.limit)
                    .textFieldStyle(.roundedBorder)
                if !coordinator.selectedTarget.isEmpty {
                    Button("Use selected host or group as limit") {
                        coordinator.limit = coordinator.selectedTarget
                    }
                }
                TextField("Tags", text: $coordinator.tags)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Run Check + Diff", systemImage: "checkmark.shield") {
                        coordinator.runDryRun()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canRun || coordinator.isRunning)
                    Button("Run for Real…", systemImage: "exclamationmark.triangle") {
                        coordinator.runForReal()
                    }
                    .disabled(!coordinator.canRun || coordinator.isRunning)
                }
                HStack {
                    Button("Ping", systemImage: "network", action: coordinator.ping)
                        .disabled(coordinator.selectedTarget.isEmpty || coordinator.inventoryURL == nil || coordinator.isRunning)
                    Button("Open SSH in Terminal", systemImage: "terminal", action: coordinator.openSSH)
                        .disabled(!coordinator.isSelectedHost || coordinator.isRunning)
                    if coordinator.isRunning {
                        Button("Stop", systemImage: "stop.fill", role: .destructive) {
                            coordinator.stopCurrent()
                        }
                    }
                }
            } header: {
                Text("Playbook Run")
            } footer: {
                Text("Check + Diff is the default. A real run asks for confirmation and omits --check.")
            }

            if let error = coordinator.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }

            Section {
                if coordinator.historyRecords.isEmpty {
                    Text("No runs yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(coordinator.historyRecords) { record in
                        HStack(spacing: Theme.Spacing.md) {
                            Image(systemName: record.exitCode == 0 ? "checkmark.circle" : "xmark.circle")
                                .foregroundStyle(record.exitCode == 0 ? Theme.Colors.success : Theme.Colors.destructive)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(verbatim: URL(fileURLWithPath: record.playbookPath).lastPathComponent)
                                    .lineLimit(1)
                                Text(verbatim: record.limit.isEmpty ? record.inventoryPath : "\(record.inventoryPath) · \(record.limit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Recent Runs")
            } footer: {
                Text("Only paths, filters, time, duration and exit status are saved. Output is not stored.")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 580, minHeight: 500)
    }

    private func fileRow(
        title: String, url: URL?, button: String, action: @escaping () -> Void
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                if let url {
                    Text(verbatim: url.path)
                        .font(Theme.Typography.code)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                } else {
                    Text("Not selected").foregroundStyle(.secondary)
                }
                Button(button, action: action)
            }
        } label: {
            Text(title)
        }
    }
}
