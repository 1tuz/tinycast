import SwiftUI

struct DevOpsLeadCardView: View {
    @Environment(\.metrics) private var metrics
    let card: DevOpsLeadCard
    let selected: Bool

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(name: card.symbol, size: metrics.size.resultRowIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: metrics.spacing.sm) {
                Text(card.title)
                    .font(metrics.typography.menuRow.weight(.semibold))
                if let result = card.result {
                    Text(String(result.prefix(300)))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let issueKey = card.issueKey, let url = card.url {
                    Text(issueKey)
                        .font(.system(.body, design: .monospaced).weight(.medium))
                    Text(verbatim: url.host ?? url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, metrics.spacing.xl)
        .padding(.vertical, metrics.spacing.xl)
        .leadCard(selected: selected)
    }
}
