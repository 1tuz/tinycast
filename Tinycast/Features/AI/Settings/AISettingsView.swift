import SwiftUI

struct AISettingsView: View {
    @AppStorage("speechVoice.enabled") private var speechEnabled = false
    @AppStorage("speechVoice.model") private var speechModel = "parakeet-ultra"
    @AppStorage("speechVoice.autoSend") private var speechAutoSend = false
    @AppStorage("speechVoice.commandsEnabled") private var speechCommandsEnabled = true
    @State private var aiTriggers: [AIVoiceTrigger] = AIVoiceTriggerStore.triggers()
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(AppSettings.self) private var appSettings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    @State private var providersPresented = false

    var body: some View {
        @Bindable var appSettings = appSettings
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $appSettings.aiEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .aiAI, title: "Enable AI",
                        subtitle: "Nothing is loaded or sent while it is off.")
                }
                SettingsRow(
                    title: "Providers", subtitle: providerSummary, anchor: .aiProviders
                ) {
                    Button("Manage…") { providersPresented = true }
                }
            } header: {
                SettingsSectionHeader(.aiAI)
            }

            FeatureCommandsSection(owner: .ai, anchor: .aiCommands)
                .settingsEnabled(appSettings.aiEnabled)

            Group {
                defaultModelSection
                chatSection
                speechVoiceSection
                aiTriggerSection
                systemPromptSection
                MCPSettingsSection()
            }
            .settingsEnabled(appSettings.aiEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.ai)
        .settingsEditorPanel(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
        .onAppear {
            core.applyInstalledAILifecycle()
        }
        // Switched on with the pane already open, provider status would otherwise stay empty.
        .onChange(of: appSettings.aiEnabled) { core.applyInstalledAILifecycle() }
        .onChange(of: settings.enabledInstalledProviders) {
            core.applyInstalledAILifecycle()
            syncSelection()
        }
        .onChange(of: subscription.models) { syncSelection() }
        .onChange(of: subscription.phase) { syncSelection() }
        .onChange(of: installedAI.statuses) { syncSelection() }
        // A model picked in a trigger row bypasses the ForEach's mutation hooks.
        .onChange(of: aiTriggers.map(\.model)) { persistTriggers() }
    }

    private var speechVoiceSection: some View {
        Section {
            Toggle("Enable local Voice Ask", isOn: $speechEnabled)
            LabeledContent("Speech Runtime model") {
                TextField("parakeet-ultra", text: $speechModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            Toggle("Run Tinycast voice commands", isOn: $speechCommandsEnabled)
            Button("Показать все голосовые команды") {
                SpeechVoiceCommandCatalogWindow.shared.show(core: core)
            }
            Toggle("Send transcript automatically to Quick AI", isOn: $speechAutoSend)
            LabeledContent("Global shortcut") { ShortcutRecorder(action: .voiceAsk) }
            LabeledContent("Service") {
                Text(core.speechVoice.availability)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Button("Check connection") { core.speechVoice.checkAvailability() }
        } header: {
            Text("Voice Ask · Speech Runtime")
        } footer: {
            Text("Speech Runtime handles recognition locally. Recognized commands run through Tinycast; other speech goes to Quick AI. Hold an unused Hyper key for push-to-talk.")
        }
        .onAppear { core.speechVoice.checkAvailability() }
    }

    private var aiTriggerSection: some View {
        Section {
            ForEach($aiTriggers) { $trigger in
                AIVoiceTriggerRow(
                    trigger: $trigger,
                    remove: {
                        aiTriggers.removeAll { $0.id == trigger.id }
                        persistTriggers()
                    })
            }
            .onMove { from, to in
                aiTriggers.move(fromOffsets: from, toOffset: to)
                persistTriggers()
            }
            .onDelete { offsets in
                aiTriggers.remove(atOffsets: offsets)
                persistTriggers()
            }
            Button("Add trigger word…") {
                aiTriggers.append(AIVoiceTrigger(trigger: ""))
            }
        } header: {
            Text("Voice Ask · AI triggers")
        } footer: {
            Text("Saying a trigger word sends the rest of the phrase straight to Quick AI. Leave the model unset to use the chat's current model.")
        }
    }

    /// The parser reads a static snapshot, so every edit publishes the new list at once.
    private func persistTriggers() {
        aiTriggers = aiTriggers.filter {
            !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        AIVoiceTriggerStore.save(aiTriggers)
        SpeechVoiceCommandParser.aiTriggers = AIVoiceTriggerStore.normalizedTriggers()
    }

    private var defaultModelSection: some View {
        Section {
            // A Mac with nothing configured is the one that needs telling its free route is off.
            if let reason = appleIntelligenceReason {
                Label(reason, systemImage: "apple.intelligence")
                    .foregroundStyle(.secondary)
            }
            AIModelSelectionRows(
                selection: settings.defaultModel,
                select: { $0.map(settings.select) },
                modelLabel: {
                    SettingsRowTitle(.aiDefault, "Default model")
                },
                effortLabel: {
                    SettingsRowTitle(.aiDefault, "Reasoning effort")
                }
            )
        } header: {
            SettingsSectionHeader(.aiDefault)
        } footer: {
            Text(defaultModelFooter)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var defaultModelFooter: String {
        if settings.defaultModel?.isOnDevice == true {
            return String(localized: "Apple Intelligence runs on this Mac. Nothing leaves it.")
        }
        return settings.defaultModel == nil
            ? String(localized: "Turn on Apple Intelligence, or add a provider above.")
            : String(localized: "Only the selected provider is contacted.")
    }

    private var appleIntelligenceReason: String? {
        settings.isAppleIntelligenceAvailable() ? nil : AppleIntelligenceProvider.status().message
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in InstalledAIKind.managedCLIKinds
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        if !settings.connections.isEmpty {
            let count = settings.connections.count
            providers.append(String(localized: "\(count) API connections"))
        }
        return providers.isEmpty
            ? String(localized: "No external providers ready") : providers.joined(separator: ", ")
    }

    private func syncSelection() {
        settings.reconcile(subscription: subscription, installedAI: installedAI)
    }

    private var chatSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.webSearchEnabled) {
                SettingsRowTitle(.aiChat, "Web search")
                Text("Codex and OpenRouter only. Prompts go to a search engine.")
            }
            Toggle(isOn: $settings.choicesEnabled) {
                SettingsRowTitle(.aiChat, "Suggested replies")
                Text("Next steps the model offers as buttons after a reply.")
            }
            Picker(selection: $settings.toolRounds) {
                ForEach(AIToolRounds.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiChat, "Tool call rounds")
                Text(
                    """
                    A reply stops after this many; Unlimited runs until Stop. API connections, Codex \
                    and Claude.
                    """)
            }
        } header: {
            SettingsSectionHeader(.aiChat)
        }
    }

    private var conversationsSection: some View {
        @Bindable var appSettings = appSettings
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.opensTo) {
                ForEach(AIOpensTo.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Opens to")
                Text("What Quick AI and the AI Chat window show when you open them.")
            }
            if settings.opensTo == .recent {
                Picker(selection: $settings.newChatAfter) {
                    ForEach(AINewChatAfter.allCases) { Text($0.title).tag($0) }
                } label: {
                    SettingsRowTitle(.aiConversations, "Start a new conversation after")
                }
            }
            Picker(selection: $settings.retention) {
                ForEach(AIRetention.allCases) { Text($0.title).tag($0) }
            } label: {
                SettingsRowTitle(.aiConversations, "Keep conversations")
                Text("Older ones are deleted, except pinned chats.")
            }
            Toggle(isOn: $appSettings.ephemeralSnippetsEnabled) {
                SettingsRowTitle(.aiConversations, "Save AI replies as snippets")
                Text(
                    appSettings.snippetsEnabled
                        ? String(
                            localized:
                                "Keep completed replies on this Mac for 24 hours. Pin a reply to save it permanently."
                        )
                        : String(localized: "Enable Snippets to save and use AI replies here."))
            }
            .disabled(!appSettings.snippetsEnabled)
        } header: {
            SettingsSectionHeader(.aiConversations)
        } footer: {
            Text("Conversations stay on this Mac, outside settings backups.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var systemPromptSection: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.systemPromptEnabled) {
                SettingsRowTitle(.aiSystemPrompt, "Send a system prompt")
                Text("Off also skips Tinycast's own prompt.")
            }
            SystemPromptEditor(text: $settings.systemPrompt)
                .settingsEnabled(settings.systemPromptEnabled)
        } header: {
            SettingsSectionHeader(.aiSystemPrompt)
        } footer: {
            Text("Sent before every message, after Tinycast's own. Both are billed each turn.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One editable trigger: the spoken word and the model it is pinned to.
struct AIVoiceTriggerRow: View {
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

    @Binding var trigger: AIVoiceTrigger
    let remove: () -> Void

    var body: some View {
        AIModelSelectionRows(
            selection: trigger.model,
            select: { trigger.model = $0 },
            modelLabel: { textField },
            effortLabel: { Text("Reasoning effort") })
            .swipeActions { Button(role: .destructive, action: remove) { Label("Delete", systemImage: "trash") } }
    }

    /// The trigger word sits in the model row's label slot, so one row carries both.
    private var textField: some View {
        TextField("Trigger word", text: $trigger.trigger)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 200)
    }
}
