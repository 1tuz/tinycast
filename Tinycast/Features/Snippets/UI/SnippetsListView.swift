import SwiftUI

enum SnippetBrowserRow: Identifiable, Equatable {
    case snippet(StoredSnippet)
    case response(EphemeralSnippet)

    var id: String {
        switch self {
        case .snippet(let record): return record.id
        case .response(let reply): return reply.entryID
        }
    }

    var name: String {
        switch self {
        case .snippet(let record): return record.snippet.name
        case .response(let reply): return reply.name
        }
    }

    var isResponse: Bool {
        if case .response = self { return true }
        return false
    }

    var trailingLabel: String? {
        switch self {
        case .snippet(let record): return record.snippet.keyword
        case .response: return "24h"
        }
    }
}

struct SnippetsList: View {

    @Environment(\.metrics) private var metrics
    let results: [SnippetBrowserRow]
    let selectedID: String?
    let scroll: ScrollIntent
    let onSelect: (SnippetBrowserRow) -> Void
    let onActivate: () -> Void
    let onActions: (SnippetBrowserRow) -> Void

    private var firstRowSelected: Bool {
        selectedID != nil && selectedID == results.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { record in
                        if record.isResponse, record.id == results.first?.id {
                            SectionHeader(title: "Recent AI Responses", isFirst: true)
                        } else if !record.isResponse, results.first?.isResponse == true,
                            record.id == results.first(where: { !$0.isResponse })?.id
                        {
                            SectionHeader(title: "Snippets")
                        }
                        SnippetRow(row: record, selected: record.id == selectedID)
                            .selectionFrame(record.id == selectedID)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(record) }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(record)
                                    onActivate()
                                }
                            )
                            .onRightClick { onActions(record) }
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: firstRowSelected, proxy: proxy)
        }
    }
}

private struct SnippetRow: View {

    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let row: SnippetBrowserRow
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        IconCache.observeStyle()
        return HStack(spacing: metrics.spacing.lg) {
            Image(nsImage: IconCache.symbolIcon(named: row.isResponse ? "sparkles" : "curlybraces"))
                .resizable()
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(row.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.lg)
            if let trailingLabel = row.trailingLabel, !trailingLabel.isEmpty {
                Text(trailingLabel)
                    .font(metrics.typography.keyCap)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            if case .snippet(let record) = row,
                let keycaps = hotKeys.binding(for: .snippet(id: record.id))?.keycaps
            {
                HStack(spacing: metrics.spacing.xxs) {
                    ForEach(Array(keycaps.enumerated()), id: \.offset) { _, cap in
                        KeyCapChip(text: cap, style: .outline)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill)
        )
        .armedHover($hovered)
    }
}

struct SnippetPreview: View {
    let record: StoredSnippet?

    var body: some View {
        if let record {
            VStack(alignment: .leading, spacing: 0) {
                // The raw template: expanding here would read the clipboard on every arrow key.
                ScrollView {
                    Text(record.snippet.text)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                SnippetInfoSection(record: record)
            }
            .padding(.horizontal, 12)
        } else {
            Color.clear
        }
    }
}

/// The "Information" block; everything in it is already in memory, so nothing is gathered off-main.
private struct SnippetInfoSection: View {
    @Environment(\.metrics) private var metrics
    @Environment(HotKeyManager.self) private var hotKeys
    let record: StoredSnippet

    private struct InfoRow: Identifiable {
        let label: String
        let value: Text
        var id: String { label }

        init(label: String, value: String) {
            self.label = label
            self.value = Text(value)
        }

        init(label: String, keycaps: [String]) {
            self.label = label
            value = KeyCapChip.inlineText(keycaps)
        }
    }

    private var rows: [InfoRow] {
        var rows = [InfoRow(label: String(localized: "Name"), value: record.snippet.name)]
        if let keyword = record.snippet.keyword, !keyword.isEmpty {
            rows.append(InfoRow(label: String(localized: "Keyword"), value: keyword))
        }
        if let keycaps = hotKeys.binding(for: .snippet(id: record.id))?.keycaps {
            rows.append(InfoRow(label: String(localized: "Shortcut"), keycaps: keycaps))
        }
        rows.append(
            InfoRow(label: String(localized: "File"), value: record.fileURL.lastPathComponent))
        rows.append(
            InfoRow(
                label: String(localized: "Characters"),
                value: record.snippet.text.count.formatted()))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.sm) {
            Text("Information")
                .font(metrics.typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let rows = self.rows
                ForEach(rows) { row in
                    if row.id != rows.first?.id { Divider() }
                    HStack(spacing: metrics.spacing.sm) {
                        Text(row.label).foregroundStyle(.secondary)
                        Spacer(minLength: metrics.spacing.lg)
                        row.value.lineLimit(1).truncationMode(.middle)
                    }
                    .font(metrics.typography.keyCap)
                    .padding(.vertical, metrics.spacing.xs)
                }
            }
        }
        .padding(.vertical, metrics.spacing.md)
    }
}
