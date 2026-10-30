import AppKit
import SwiftUI

struct WorkflowSettingsSection: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.workflowsEnabled) {
                SettingsRowTitle(.generalWorkflows, "Enable workflows")
                Text("Run local commands on a daily schedule, hotkey, clipboard or folder change.")
            }
            if settings.workflowsEnabled {
                if !core.workflows.isAvailable {
                    Text("Local workflow storage could not be opened.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(core.workflows.workflows) { workflow in
                        WorkflowSettingsRow(
                            workflow: workflow,
                            availableCommands: availableCommands,
                            isFolderUnavailable: core.workflowCoordinator.unavailableFolderIDs.contains(
                                workflow.id),
                            update: core.workflows.update,
                            delete: { core.workflows.delete(id: workflow.id) })
                    }
                    Button("Add Workflow", systemImage: "plus") {
                        _ = core.workflows.create()
                    }
                }
            }
        } header: {
            SettingsSectionHeader(.generalWorkflows)
        } footer: {
            Text("Runs only while Tinycast is open. Workflow definitions stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var availableCommands: [CommandID] {
        Workflow.availableCommands.filter(core.appIndex.isCommandEnabled)
    }
}

private struct WorkflowSettingsRow: View {
    let workflow: Workflow
    let availableCommands: [CommandID]
    let isFolderUnavailable: Bool
    let update: (Workflow) -> Void
    let delete: () -> Void

    var body: some View {
        DisclosureGroup {
            TextField("Workflow name", text: value(\.name))
            Toggle("Enabled", isOn: value(\.isEnabled))
            Picker("Trigger", selection: value(\.trigger.kind)) {
                ForEach(WorkflowTriggerKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            triggerSettings
            Picker("Run command", selection: value(\.commandID)) {
                ForEach(availableCommands, id: \.rawValue) { command in
                    Text(command.name).tag(command.rawValue)
                }
                if !availableCommands.contains(where: { $0.rawValue == workflow.commandID }) {
                    Text(
                        CommandID(rawValue: workflow.commandID).map {
                            "\($0.name) (Unavailable)"
                        } ?? "Unavailable command"
                    )
                    .tag(workflow.commandID)
                    .disabled(true)
                }
            }
            HStack {
                Spacer()
                Button("Delete Workflow", role: .destructive, action: delete)
            }
        } label: {
            Label(
                workflow.name.isEmpty ? "Unnamed Workflow" : workflow.name,
                systemImage: "arrow.trianglehead.2.clockwise"
            )
            .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private var triggerSettings: some View {
        switch workflow.trigger.kind {
        case .dailyTime:
            DatePicker("Run daily at", selection: scheduledTime, displayedComponents: .hourAndMinute)
        case .hotkey:
            LabeledContent("Shortcut") {
                ShortcutRecorder(action: .workflow(id: workflow.id), isQuiet: true)
            }
        case .clipboardChange:
            Text("The clipboard content is not read or stored for this trigger.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .fileChange:
            HStack {
                Text(workflow.trigger.path.isEmpty ? "Choose a folder" : workflow.trigger.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…", action: choosePath)
            }
            Text("Runs when the selected folder changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if isFolderUnavailable {
                Text("This folder is unavailable. Choose it again.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var scheduledTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    from: DateComponents(hour: workflow.trigger.hour, minute: workflow.trigger.minute))
                    ?? Date()
            },
            set: { date in
                var updated = workflow
                updated.trigger.hour = Calendar.current.component(.hour, from: date)
                updated.trigger.minute = Calendar.current.component(.minute, from: date)
                update(updated)
            })
    }

    private func value<Value>(_ keyPath: WritableKeyPath<Workflow, Value>) -> Binding<Value> {
        Binding(
            get: { workflow[keyPath: keyPath] },
            set: { value in
                var updated = workflow
                updated[keyPath: keyPath] = value
                update(updated)
            })
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to watch"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var updated = workflow
        updated.trigger.path = url.path
        update(updated)
    }
}
