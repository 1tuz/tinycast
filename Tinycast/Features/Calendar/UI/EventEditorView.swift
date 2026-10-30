import SwiftUI

struct EventEditorView: View {
    @Bindable var editor: EventEditorSession
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(CalendarCoordinator.self) private var coordinator
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedField: EventEditorSession.Field?
    @FocusState private var focusedControl: EventEditorSession.Field?
    @State private var menuFrames: [EventEditorSession.Field: CGRect] = [:]
    @State private var fallbackStartDate = Date()

    var body: some View {
        ScrollView {
            VStack(spacing: metrics.spacing.xxl) {
                FormRow("Quick entry") {
                    HStack(spacing: metrics.spacing.md) {
                        FormTextInput(
                            text: $editor.quickEntry,
                            focused: quickEntryFocused,
                            placeholder: String(localized: "Meeting tomorrow at 3pm"),
                            label: String(localized: "Quick event description"),
                            moveFocus: editor.advanceFocus
                        )
                        .frame(height: metrics.size.dialogButtonHeight)
                        .formFieldChrome(focused: focusedField == .quickEntry)
                        BarButton(
                            chrome: .rounded,
                            action: {
                                editor.parseQuickEntry()
                                focusedField = .title
                            }
                        ) {
                            Text("Use")
                                .font(metrics.typography.rowTrailing)
                        }
                        .help("Fill the title and start time from the description.")
                    }
                }
                FormRow("Title") {
                    FormTextInput(
                        text: $editor.draft.title, focused: titleFocused,
                        placeholder: String(localized: "Event title"),
                        label: String(localized: "Event title"), moveFocus: editor.advanceFocus
                    )
                    .frame(height: metrics.size.dialogButtonHeight)
                    .formFieldChrome(focused: focusedField == .title)
                }
                FormRow("Start") {
                    DatePicker(
                        String(localized: "Start date and time"),
                        selection: Binding(
                            get: { editor.draft.startDate ?? fallbackStartDate },
                            set: { editor.draft.startDate = $0 }),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .focused($focusedControl, equals: .start)
                    .accessibilityLabel(String(localized: "Start date and time"))
                }
                FormRow("Duration") {
                    choice(
                        String(localized: "Duration"), field: .duration,
                        selection: $editor.draft.durationMinutes,
                        values: EventDraft.durations,
                        label: { EventDraft.label(duration: $0, locale: .current) })
                }
                FormRow {
                    Text("The event will be added to your default calendar.")
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(metrics.typography.rowTitle)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, metrics.spacing.xxxl * 2)
            .padding(.vertical, metrics.spacing.md)
        }
        .scrollClipDisabled()
        .edgeDissolve()
        .focusEffectDisabled()
        .task(id: palette.focusToken) {
            palette.noteEditingField(true)
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = editor.focusedField
        }
        .onChange(of: editor.focusedField) { _, field in focusedField = field }
        .onChange(of: focusedField) { _, field in
            if let field { editor.focusedField = field }
            focusedControl = field == .title ? nil : field
        }
        .onChange(of: focusedControl) { _, field in
            if let field { focusedField = field }
        }
        .onDisappear {
            coordinator.editorDidClose(editor)
            palette.noteEditingField(false)
        }
    }

    private var titleFocused: Binding<Bool> {
        Binding(
            get: { focusedField == .title },
            set: { value in
                if value { focusedField = .title } else if focusedField == .title { focusedField = nil }
            })
    }

    private var quickEntryFocused: Binding<Bool> {
        Binding(
            get: { focusedField == .quickEntry },
            set: { value in
                if value {
                    focusedField = .quickEntry
                } else if focusedField == .quickEntry {
                    focusedField = nil
                }
            })
    }

    private func choice(
        _ title: String, field: EventEditorSession.Field, selection: Binding<Int>,
        values: [Int], label: @escaping (Int) -> String
    ) -> some View {
        let frame = menuFrames[field] ?? .zero
        let isOpen = openMenuCorner == .belowControl(frame)
        let open = {
            let items = values.map { value in
                PopoverMenuItem(title: label(value), icon: .blank) { selection.wrappedValue = value }
            }
            openInputMenu(
                PopoverMenuContent(items: items), .belowControl(frame),
                values.firstIndex(of: selection.wrappedValue) ?? 0)
        }
        return HStack {
            Text(label(selection.wrappedValue))
            Spacer()
            Image(systemName: "chevron.down")
                .font(metrics.typography.disclosure)
                .foregroundStyle(Theme.Colors.textSecondary)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.spacing.xl)
        .frame(height: metrics.size.dialogButtonHeight)
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .focusable()
        .focused($focusedControl, equals: field)
        .onKeyPress(keys: [.return, .space, .downArrow]) { _ in
            open()
            return .handled
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            menuFrames[field] = $0
        }
        .formFieldChrome(focused: focusedField == field)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(label(selection.wrappedValue))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}
