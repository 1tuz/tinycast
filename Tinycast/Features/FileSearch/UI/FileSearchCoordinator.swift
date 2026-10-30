import AppKit
import UniformTypeIdentifiers

@MainActor
final class FileSearchCoordinator {
    let smartFolders = SmartFolderStore()
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: FileSearchSession
    private let indexer: FileIndexer
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private let windowController: PaletteWindowController
    private var sharePicker: NSSharingServicePicker?
    private unowned let core: AppCore

    init(
        settings: AppSettings, appIndex: AppIndex, session: FileSearchSession,
        indexer: FileIndexer, palette: PaletteState, paletteCoordinator: PaletteCoordinator,
        windowController: PaletteWindowController, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.indexer = indexer
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.windowController = windowController
        self.core = core
        indexer.onIndexChanged = { [weak session] in session?.refresh() }
        indexer.onRecentChanged = { [weak session] in session?.refreshRecent() }
    }

    func applyEnabled() {
        appIndex.setCommandsVisible([.searchFiles], settings.fileSearchEnabled)
        indexer.setEnabled(settings.fileSearchEnabled)
        guard !settings.fileSearchEnabled else { return }
        session.cancel()
        if palette.mode == .fileSearch { palette.prepare(mode: .launcher) }
    }

    func applyPolicy() {
        indexer.apply(
            FileSearchPolicy(
                scopes: settings.fileSearchScopes,
                ignorePatterns: settings.fileSearchEffectiveIgnorePatterns,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser))
    }

    var showsFilesInLauncher: Bool {
        settings.fileSearchEnabled && settings.fileSearchShowInLauncher
    }

    var favoriteFiles: [FileSearchResult] {
        guard settings.fileSearchEnabled else { return [] }
        return core.favorites.files(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Borrows the screen's session, so Search Files then opens on the request already answered.
    func searchFromLauncher(_ query: String) {
        guard showsFilesInLauncher, FileSearchQuery.answersLauncher(query) else {
            session.cancel()
            return
        }
        session.search(query)
    }

    /// Checks the switch before reading the session, so with it off the launcher observes nothing.
    func launcherFiles(for query: String) -> [FileSearchResult] {
        guard settings.fileSearchEnabled, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return []
        }
        let results = showsFilesInLauncher && FileSearchQuery.answersLauncher(query) ? session.results : []
        return FileSearchQuery.launcherResults(query, favorites: favoriteFiles, indexed: results)
    }

    func applyLauncherFiles() {
        guard palette.mode == .launcher else { return }
        searchFromLauncher(palette.query)
    }

    func rebuildIndex() {
        indexer.rebuild()
    }

    func openFullDiskAccessSettings() {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Permissions.openFullDiskAccessSettings()
    }

    /// `query` is the fallback row's: the screen opens already narrowed to what was typed.
    func show(query: String = "") {
        guard settings.fileSearchEnabled else { return }
        indexer.refreshAccess()
        do { try smartFolders.load() } catch {
            core.showMessage("Couldn’t load Smart Folders: \(error.localizedDescription)", tone: .danger)
        }
        paletteCoordinator.togglePalette(mode: .fileSearch, seeding: query.isEmpty ? nil : query)
    }

    func saveSmartFolder(query: String, filter: FileSearchFilter) {
        guard settings.fileSearchEnabled else { return }
        do {
            try smartFolders.save(query: query, filter: filter)
            core.showMessage("Saved Smart Folder")
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    func openSmartFolder(_ folder: SmartFolder) {
        guard settings.fileSearchEnabled,
            smartFolders.folders.contains(where: { $0.id == folder.id })
        else { return }
        palette.fileSearchFilter = folder.filter
        palette.query = folder.query
        palette.selection = 0
        session.search(folder.query, filter: folder.filter)
    }

    func removeSmartFolder(id: UUID) {
        guard settings.fileSearchEnabled else { return }
        do { try smartFolders.remove(id: id) } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    func openWith(_ result: FileSearchResult) {
        guard settings.fileSearchEnabled else { return }
        paletteCoordinator.hidePalette(restoreFocus: false)
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Open With"
        panel.message = "Choose an application to open \(result.name)."
        panel.prompt = "Open"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let applicationURL = panel.url,
            settings.fileSearchEnabled
        else { return }
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [result.url], withApplicationAt: applicationURL,
                    configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: "Couldn’t Open \(result.name)", message: error.localizedDescription,
                    symbol: "app", tone: .danger)
            }
        }
    }

    func open(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    result.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                await core.showNotice(
                    title: String(localized: "Couldn’t Open \(result.name)"),
                    message: error.localizedDescription,
                    symbol: result.isDirectory ? "folder" : "doc", tone: .danger)
            }
        }
    }

    func showInFinder(_ result: FileSearchResult) {
        paletteCoordinator.hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(result.url)
    }

    /// macOS's own share sheet, anchored to the palette's trailing edge so the row stays beside it.
    func share(_ result: FileSearchResult) {
        guard let provider = NSItemProvider(contentsOf: result.url),
            let anchor = paletteCoordinator.anchorView
        else { return }
        let picker = NSSharingServicePicker(items: [provider])
        sharePicker = picker
        picker.show(
            relativeTo: CGRect(
                x: anchor.bounds.maxX, y: anchor.bounds.midY, width: 0, height: 0),
            of: anchor, preferredEdge: .maxX)
    }

    func copyPath(_ result: FileSearchResult) {
        Paster.copyPlainText(result.id)
        core.showMessage(String(localized: "Copied path"))
    }

    func copyName(_ result: FileSearchResult) {
        Paster.copyPlainText(result.name)
        core.showMessage(String(localized: "Copied name"))
    }

    /// The file itself rather than its path, so Finder and Mail paste a copy of it.
    func copyFile(_ result: FileSearchResult) {
        PasteboardFiles.write(result.url, to: .general)
        core.showMessage(String(localized: "Copied file"))
    }

    /// Into whichever app the palette was summoned over, which is what the row's title names.
    func pasteFile(_ result: FileSearchResult) {
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteFile(result.url, previousApp: previous)
    }

    func trash(_ result: FileSearchResult) {
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.trashItem(at: result.url, resultingItemURL: nil)
                }.value
                session.remove(result)
                core.showMessage(String(localized: "Moved to Trash"))
            } catch {
                await core.showNotice(
                    title: String(localized: "Couldn’t Move \(result.name) to Trash"),
                    message: error.localizedDescription,
                    symbol: "trash", tone: .danger)
            }
        }
    }
}
