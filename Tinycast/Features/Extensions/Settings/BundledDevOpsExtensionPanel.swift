import SwiftUI

struct BundledDevOpsExtensionPanel: View {
    let onClose: () -> Void
    @Environment(AppCore.self) private var core
    @State private var installing: Set<String> = []
    @State private var failures: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ExtensionSettingsEditorHeader(
                title: String(localized: "DevOps Toolkit"),
                subtitle: String(localized: "Local extensions included with Tinycast. Installation does not use the network."))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ForEach(core.extensions.bundledDevOpsExtensions) { extensionInfo in
                        row(extensionInfo)
                    }
                }
                .hideNativeScrollers()
            }
            .overflowFade()
            .thinScrollbar()
            Divider()
            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .cancel, fillsWidth: false))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.Spacing.dialogInset)
        .frame(width: 620, height: 560)
        .extensionSettingsEditorPanelSurface()
    }

    private func row(_ bundled: InstalledExtension) -> some View {
        let installed = core.extensions.installed.contains { $0.manifest.name == bundled.manifest.name }
        return HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            Image(systemName: "shippingbox")
                .font(.system(size: Theme.Size.settingsRowIcon - Theme.Spacing.xs))
                .frame(width: Theme.Size.settingsRowIcon + Theme.Spacing.xs)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(bundled.title).font(.headline)
                Text(bundled.manifest.description)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                if let failure = failures[bundled.manifest.name] {
                    Text(failure).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else if installing.contains(bundled.manifest.name) {
                ProgressView().controlSize(.small)
            } else {
                Button("Install") { install(bundled.manifest.name) }
                    .buttonStyle(ExtensionSettingsEditorButtonStyle(role: .primary, fillsWidth: false))
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func install(_ name: String) {
        installing.insert(name)
        failures[name] = nil
        Task {
            do { try await core.extensions.installBundledDevOps(named: name) }
            catch { failures[name] = error.localizedDescription }
            installing.remove(name)
        }
    }
}
