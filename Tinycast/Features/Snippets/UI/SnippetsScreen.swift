import SwiftUI

struct SnippetsScreen: PaletteScreen {
    let store: SnippetsStore
    let core: AppCore
    let vm: PaletteState

    private var metrics: InterfaceMetrics { core.settings.interfaceSize.metrics }
    let openActions: () -> Void

    /// A disabled snippet is off everywhere, so the browser lists exactly what the launcher does.
    var rows: [SnippetBrowserRow] {
        let enabled = store.snippets.filter { $0.snippet.isEnabled }
        let query = vm.query.trimmingCharacters(in: .whitespaces)
        let snippets =
            query.isEmpty
            ? enabled
            : enabled.filter { record in
                record.snippet.name.localizedCaseInsensitiveContains(query)
                    || record.snippet.keyword?.localizedCaseInsensitiveContains(query) == true
            }
        let responses =
            core.settings.ephemeralSnippetsEnabled
            ? store.ephemeral.items.filter {
                $0.expiresAt > Date()
                    && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query))
            } : []
        return responses.map(SnippetBrowserRow.response) + snippets.map(SnippetBrowserRow.snippet)
    }

    var primaryActionTitle: String {
        record(at: vm.selection)?.isResponse == true
            ? String(localized: "Paste Response") : String(localized: "Paste Snippet")
    }

    private func record(at selection: Int) -> SnippetBrowserRow? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let record = record(at: selection) else { return nil }
        switch record {
        case .snippet(let snippet): return SnippetActionsMenu.content(record: snippet, core: core)
        case .response(let reply): return SnippetActionsMenu.content(reply: reply, core: core)
        }
    }

    func activate(at selection: Int) {
        guard let record = record(at: selection) else { return }
        switch record {
        case .snippet(let snippet): core.snippetCoordinator.expandSnippetFromPalette(id: snippet.id)
        case .response(let reply): core.snippetCoordinator.pasteEphemeralSnippet(id: reply.id)
        }
    }

    /// ⌘↵ reveals the file, as it does on a snippet's launcher row.
    func secondary(at selection: Int) -> Bool {
        guard let record = record(at: selection) else { return false }
        guard case .snippet(let snippet) = record else { return false }
        core.snippetCoordinator.showSnippetInFinder(snippet)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        if shortcut == .newItem {
            core.snippetCoordinator.editSnippet(nil)
            return true
        }
        guard let record = record(at: selection) else { return false }
        switch shortcut {
        case .edit:
            guard case .snippet(let snippet) = record else { return false }
            core.snippetCoordinator.editSnippet(snippet)
        case .delete:
            guard case .snippet(let snippet) = record else { return false }
            Task { await core.snippetCoordinator.deleteSnippet(id: snippet.id) }
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            EmptyResults(text: emptyMessage)
        } else {
            let selected = record(at: selection)
            HStack(spacing: 0) {
                SnippetsList(
                    results: rows, selectedID: selected?.id, scroll: scroll,
                    onSelect: { row in
                        vm.selection = rows.firstIndex(of: row) ?? 0
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { row in
                        if let index = rows.firstIndex(of: row) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                preview(selected)
            }
        }
    }

    @ViewBuilder
    private func preview(_ row: SnippetBrowserRow?) -> some View {
        switch row {
        case .snippet(let record): SnippetPreview(record: record)
        case .response(let reply):
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                ScrollView {
                    Text(reply.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Text("Expires \(reply.expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        case nil: Color.clear
        }
    }

    /// An empty library and an over-narrow filter are different problems with different answers.
    private var emptyMessage: String {
        if store.state == .loading { return String(localized: "Loading snippets…") }
        return store.snippets.contains(where: { $0.snippet.isEnabled })
            || (core.settings.ephemeralSnippetsEnabled
                && store.ephemeral.items.contains(where: { $0.expiresAt > Date() }))
            ? String(localized: "No matching snippets") : String(localized: "No snippets yet")
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(reply: EphemeralSnippet, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: reply.name,
            items: [
                PopoverMenuItem(
                    title: String(localized: "Paste Response"), systemImage: "text.quote", shortcut: "↵"
                ) {
                    core.snippetCoordinator.pasteEphemeralSnippet(id: reply.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Copy Response"), systemImage: "doc.on.doc"
                ) {
                    core.snippetCoordinator.copyEphemeralSnippet(id: reply.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Pin as Snippet…"), systemImage: "pin", startsSection: true
                ) {
                    core.snippetCoordinator.pinEphemeralSnippet(id: reply.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Remove Response"), systemImage: "trash",
                    startsSection: true, isDestructive: true
                ) {
                    core.snippetCoordinator.removeEphemeralSnippet(id: reply.id)
                }
            ])
    }

    static func content(record: StoredSnippet, core: AppCore) -> PopoverMenuContent {
        PopoverMenuContent(
            header: record.snippet.name,
            items: [
                PopoverMenuItem(
                    title: String(localized: "Paste Snippet"), systemImage: "text.quote", shortcut: "↵"
                ) {
                    core.snippetCoordinator.expandSnippetFromPalette(id: record.id)
                },
                PopoverMenuItem(
                    title: String(localized: "Edit Snippet"), systemImage: "pencil", startsSection: true,
                    shortcut: "⌘E"
                ) {
                    core.snippetCoordinator.editSnippet(record)
                },
                PopoverMenuItem(
                    title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N"
                ) {
                    core.snippetCoordinator.editSnippet(nil)
                },
                PopoverMenuItem(
                    title: String(localized: "Show in Finder"), systemImage: "folder", startsSection: true,
                    shortcut: "⌘↵"
                ) {
                    core.snippetCoordinator.showSnippetInFinder(record)
                },
                PopoverMenuItem(
                    title: String(localized: "Delete Snippet"), systemImage: "trash", startsSection: true,
                    shortcut: "⌃X", isDestructive: true
                ) {
                    Task { await core.snippetCoordinator.deleteSnippet(id: record.id) }
                }
            ])
    }
}
