import AppKit

@MainActor
@Observable
final class RunningAppsMonitor {
    private(set) var runningBundleIDs: Set<String> = []
    private var runningAppPaths: Set<String> = []
    private(set) var recentBundleIDs: [String] = []
    private(set) var contextualDocumentURL: URL?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NotificationToken] = []

    init() {
        observation = NSWorkspace.shared.observe(
            \.runningApplications, options: .initial
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                let activatedBundleID = name == NSWorkspace.didActivateApplicationNotification
                    ? application?.bundleIdentifier : nil
                let terminatedBundleID = name == NSWorkspace.didTerminateApplicationNotification
                    ? application?.bundleIdentifier : nil
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refresh()
                    if let bundleID = terminatedBundleID {
                        self.recentBundleIDs.removeAll { $0 == bundleID }
                    }
                    if let bundleID = activatedBundleID,
                        bundleID != Bundle.main.bundleIdentifier
                    {
                        self.recentBundleIDs.removeAll { $0 == bundleID }
                        self.recentBundleIDs.insert(bundleID, at: 0)
                        if self.recentBundleIDs.count > 10 {
                            self.recentBundleIDs.removeLast(self.recentBundleIDs.count - 10)
                        }
                    }
                    if activatedBundleID != nil || terminatedBundleID != nil {
                        self.refreshContextualDocument()
                    }
                }
            }
            observers.append(NotificationToken(token, center: center))
        }
    }

    func isRunning(_ app: AppEntry) -> Bool {
        app.kind == .application && app.bundleID != nil && runningAppPaths.contains(app.id)
    }

    /// Uses the active document, falling back to the most recent live external app.
    func refreshContextualDocument() {
        let frontmostApp = NSWorkspace.shared.frontmostApplication.flatMap {
            $0.isTerminated || $0.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : $0
        }
        let app = frontmostApp ?? recentBundleIDs.lazy.compactMap { bundleID in
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
        }.first
        let documentURL = app.flatMap { WindowInventory.focusedDocumentURL(for: $0) }
        guard contextualDocumentURL != documentURL else { return }
        contextualDocumentURL = documentURL
    }

    /// Helpers and agents fire these too, so republish only on a real change.
    private func refresh() {
        let apps = NSWorkspace.shared.runningApplications
        let bundleIDs = Set(apps.compactMap(\.bundleIdentifier))
        let paths = Set(apps.compactMap { $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL.path })
        if bundleIDs != runningBundleIDs { runningBundleIDs = bundleIDs }
        if paths != runningAppPaths { runningAppPaths = paths }
    }
}
