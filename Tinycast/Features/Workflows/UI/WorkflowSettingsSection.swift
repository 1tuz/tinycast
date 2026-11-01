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
                            availableCustomCommands: availableCustomCommands,
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

    private var availableCustomCommands: [CustomCommand] {
        guard settings.customCommandsEnabled else { return [] }
        return core.customCommands.commands.filter(\.isEnabled)
    }
}

private enum WorkflowActionChoice: String, Identifiable {
    case builtIn
    case customCommand

    var id: String { rawValue }
}

private struct WorkflowSettingsRow: View {
    let workflow: Workflow
    let availableCommands: [CommandID]
    let availableCustomCommands: [CustomCommand]
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
            Picker("Action type", selection: actionChoice) {
                Text("Built-in").tag(WorkflowActionChoice.builtIn)
                Text("Custom Command").tag(WorkflowActionChoice.customCommand)
                    .disabled(availableCustomCommands.isEmpty && workflow.customCommandID == nil)
            }
            if workflow.customCommandID == nil {
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
            } else {
                customCommandSettings
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

    private var actionChoice: Binding<WorkflowActionChoice> {
        Binding(
            get: { workflow.customCommandID == nil ? .builtIn : .customCommand },
            set: { choice in
                var updated = workflow
                switch choice {
                case .builtIn:
                    updated.selectBuiltIn(updated.command ?? availableCommands.first ?? .about)
                case .customCommand:
                    guard let command = availableCustomCommands.first else { return }
                    updated.selectCustomCommand(command.id)
                }
                update(updated)
            })
    }

    @ViewBuilder
    private var customCommandSettings: some View {
        let selectedID = workflow.customCommandID
        Picker("Custom Command", selection: Binding(
            get: { selectedID?.uuidString ?? "" },
            set: { value in
                guard let id = UUID(uuidString: value) else { return }
                var updated = workflow
                updated.selectCustomCommand(id)
                update(updated)
            })) {
            ForEach(availableCustomCommands) { command in
                Text(command.name).tag(command.id.uuidString)
            }
            if let selectedID,
                !availableCustomCommands.contains(where: { $0.id == selectedID })
            {
                Text("Unavailable Custom Command").tag(selectedID.uuidString).disabled(true)
            }
        }
        if let selectedID,
            let command = availableCustomCommands.first(where: { $0.id == selectedID })
        {
            ForEach(command.arguments.indices, id: \.self) { index in
                TextField(
                    command.arguments[index].name,
                    text: argumentValue(at: index, count: command.arguments.count))
            }
        } else {
            Text("This custom command is unavailable or disabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func argumentValue(at index: Int, count: Int) -> Binding<String> {
        Binding(
            get: { workflow.arguments(for: count)[index] },
            set: { value in
                var updated = workflow
                var arguments = updated.arguments(for: count)
                arguments[index] = value
                updated.customCommandArguments = arguments
                update(updated)
            })
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
