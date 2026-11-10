import AppKit
import Foundation
import Observation

/// Local Focus sessions. Owns deadlines, persistence and the soft-blocking lifecycle.
/// The Speech Runtime only supplies text; this service runs without a microphone or model.
@MainActor
@Observable
final class FocusSessionCoordinator {
    private(set) var profiles: [FocusProfile]
    private(set) var selectedProfileID: UUID
    private(set) var session: FocusSession?
    private(set) var remainingSeconds = 0
    private(set) var lastError: String?

    @ObservationIgnored private weak var core: AppCore?
    @ObservationIgnored private let fileURL = AppPaths.applicationSupport()
        .appendingPathComponent("focus-sessions.json")
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var appObserver: NSObjectProtocol?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var websiteTask: Task<Bool, Never>?
    @ObservationIgnored private var lastWebsitePoll = Date.distantPast
    @ObservationIgnored private let hud = FocusHUDController()

    private static let protectedBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
        "com.tinycast.app", "com.tinycast.app.dev"
    ]

    init(core: AppCore) {
        self.core = core
        let defaults = FocusProfile.initial
        profiles = defaults
        selectedProfileID = defaults[0].id
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(FocusSavedState.self, from: data),
           !saved.profiles.isEmpty {
            profiles = saved.profiles
            selectedProfileID = saved.profiles.contains { $0.id == saved.selectedProfileID }
                ? saved.selectedProfileID : saved.profiles[0].id
            session = saved.session
        }
    }

    var selectedProfile: FocusProfile? { profiles.first { $0.id == selectedProfileID } }
    var activeProfile: FocusProfile? {
        guard let session else { return nil }
        return profiles.first { $0.id == session.profileID }
    }
    var isActive: Bool { session != nil }
    var isPaused: Bool { session?.pausedSeconds != nil }
    var clockText: String {
        let seconds = max(0, remainingSeconds)
        return String(format: "%02d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
    }

    func startMonitoring() {
        guard timer == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        appObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                if let app = NSWorkspace.shared.frontmostApplication { self?.blockIfNeeded(app) }
            }
        }
        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refresh()
        if isActive { hud.show(coordinator: self) }
    }

    func prepareForTermination() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        if let appObserver { center.removeObserver(appObserver) }
        if let wakeObserver { center.removeObserver(wakeObserver) }
        appObserver = nil
        wakeObserver = nil
        websiteTask?.cancel()
        websiteTask = nil
        hud.hide()
    }

    @discardableResult
    func start(profileID: UUID? = nil, minutes: Int? = nil) -> Bool {
        let id = profileID ?? selectedProfileID
        guard let profile = profiles.first(where: { $0.id == id }) else { return false }
        let duration = minutes ?? profile.durationMinutes
        guard (5...240).contains(duration) else {
            core?.showMessage("Длительность фокуса: от 5 до 240 минут", tone: .neutral)
            return false
        }
        if session != nil { finish(runEndShortcut: false) }
        let now = Date()
        session = FocusSession(
            profileID: id, startedAt: now, deadline: now.addingTimeInterval(TimeInterval(duration * 60)))
        selectedProfileID = id
        persist()
        refresh()
        hud.show(coordinator: self)
        if let activeApp = NSWorkspace.shared.frontmostApplication { blockIfNeeded(activeApp) }
        if let workflowID = profile.startWorkflowID { runWorkflow(workflowID) }
        if let shortcutID = profile.startShortcutID { runShortcut(shortcutID) }
        return true
    }

    func startSpoken(profileName: String?, minutes: Int?) {
        guard let profileName, !profileName.isEmpty else {
            _ = start(minutes: minutes)
            return
        }
        let key = SpeechVoiceCommandParser.normalize(profileName)
        let found = profiles.filter { SpeechVoiceCommandParser.normalize($0.name) == key }
        guard found.count == 1, let profile = found.first else {
            core?.showMessage("Профиль фокуса не найден: \(profileName)", tone: .neutral)
            return
        }
        _ = start(profileID: profile.id, minutes: minutes)
    }

    func pause(for minutes: Int? = nil) {
        guard var session, session.pausedSeconds == nil else { return }
        if let minutes, !(1...60).contains(minutes) {
            core?.showMessage("Пауза: от 1 до 60 минут", tone: .neutral)
            return
        }
        session.pausedSeconds = max(0, session.deadline.timeIntervalSinceNow)
        session.resumeAt = minutes.map { Date().addingTimeInterval(Double($0 * 60)) }
        self.session = session
        websiteTask?.cancel()
        persist()
        refresh()
    }

    func resume() {
        guard var session, let paused = session.pausedSeconds else { return }
        session.deadline = Date().addingTimeInterval(paused)
        session.pausedSeconds = nil
        session.resumeAt = nil
        self.session = session
        persist()
        refresh()
        if let app = NSWorkspace.shared.frontmostApplication { blockIfNeeded(app) }
    }

    func finish(runEndShortcut: Bool = true) {
        guard let session else { return }
        let profile = profiles.first { $0.id == session.profileID }
        self.session = nil
        remainingSeconds = 0
        websiteTask?.cancel()
        hud.hide()
        persist()
        if runEndShortcut {
            if let workflowID = profile?.endWorkflowID { runWorkflow(workflowID) }
            if let shortcutID = profile?.endShortcutID { runShortcut(shortcutID) }
        }
    }

    func showStatus() {
        guard let session else {
            core?.showMessage("Сеанс концентрации не запущен", tone: .neutral)
            return
        }
        let name = profiles.first { $0.id == session.profileID }?.name ?? "Фокус"
        core?.showMessage("\(name): \(clockText)\(isPaused ? " · пауза" : "")")
    }

    // MARK: Profiles

    func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        persist()
    }

    func addProfile() {
        let profile = FocusProfile(name: "Новый профиль", durationMinutes: 45)
        profiles.append(profile)
        selectedProfileID = profile.id
        persist()
    }

    func removeProfile(_ id: UUID) {
        guard profiles.count > 1, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if session?.profileID == id { finish() }
        profiles.remove(at: index)
        if selectedProfileID == id { selectedProfileID = profiles[0].id }
        persist()
    }

    func updateProfile(_ id: UUID, _ edit: (inout FocusProfile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        edit(&profiles[index])
        profiles[index].durationMinutes = min(240, max(5, profiles[index].durationMinutes))
        persist()
    }

    func addApplication(_ app: FocusBlockedApplication, to profileID: UUID) {
        guard !Self.protectedBundleIDs.contains(app.bundleID),
              app.bundleID != Bundle.main.bundleIdentifier else { return }
        updateProfile(profileID) { profile in
            if !profile.blockedApplications.contains(where: { $0.bundleID == app.bundleID }) {
                profile.blockedApplications.append(app)
                profile.blockedApplications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }
        if let activeApp = NSWorkspace.shared.frontmostApplication { blockIfNeeded(activeApp) }
    }

    func removeApplication(_ bundleID: String, from profileID: UUID) {
        updateProfile(profileID) { $0.blockedApplications.removeAll { $0.bundleID == bundleID } }
    }

    @discardableResult
    func addDomain(_ input: String, to profileID: UUID) -> Bool {
        guard let host = FocusDomain.normalize(input) else { return false }
        updateProfile(profileID) { profile in
            if !profile.blockedDomains.contains(host) {
                profile.blockedDomains.append(host)
                profile.blockedDomains.sort()
            }
        }
        return true
    }

    func removeDomain(_ domain: String, from profileID: UUID) {
        updateProfile(profileID) { $0.blockedDomains.removeAll { $0 == domain } }
    }

    // MARK: One-off spoken restrictions

    func blockApplication(_ app: FocusBlockedApplication) {
        guard var session else {
            core?.showMessage("Сначала запусти фокус", tone: .neutral)
            return
        }
        guard !Self.protectedBundleIDs.contains(app.bundleID),
              app.bundleID != Bundle.main.bundleIdentifier else { return }
        if !session.extraBlockedApplications.contains(where: { $0.bundleID == app.bundleID }) {
            session.extraBlockedApplications.append(app)
            self.session = session
            persist()
        }
        if let running = NSWorkspace.shared.frontmostApplication { blockIfNeeded(running) }
    }

    func blockWebsite(_ spoken: String) {
        guard var session else {
            showStatus()
            return
        }
        guard let domain = Self.spokenDomain(spoken) else {
            core?.showMessage("Назови домен, например youtube.com", tone: .neutral)
            return
        }
        if !session.extraBlockedDomains.contains(domain) {
            session.extraBlockedDomains.append(domain)
            self.session = session
            persist()
        }
        core?.showMessage("Заблокирован сайт: \(domain)")
    }

    func allowWebsite(_ spoken: String, for minutes: Int) {
        guard var session, (1...60).contains(minutes),
              let domain = Self.spokenDomain(spoken) else { return }
        session.allowedDomainsUntil[domain] = Date().addingTimeInterval(Double(minutes * 60))
        self.session = session
        persist()
        core?.showMessage("\(domain) разрешён на \(minutes) мин")
    }

    private static func spokenDomain(_ spoken: String) -> String? {
        var text = spoken.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " точка ", with: ".")
            .replacingOccurrences(of: " точка", with: ".")
            .replacingOccurrences(of: "ютьюб", with: "youtube")
            .replacingOccurrences(of: "ютуб", with: "youtube")
            .replacingOccurrences(of: "реддит", with: "reddit")
        for suffix in [" com", " ru", " org", " net", " io", " dev"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count)) + "." + suffix.dropFirst()
            break
        }
        if text == "youtube" { text = "youtube.com" }
        if text == "reddit" { text = "reddit.com" }
        return FocusDomain.normalize(text)
    }

    // MARK: Enforcement and clock

    private func refresh() {
        guard var session else {
            remainingSeconds = 0
            return
        }
        if let paused = session.pausedSeconds {
            if let resumeAt = session.resumeAt, Date() >= resumeAt {
                resume()
                return
            }
            remainingSeconds = Int(ceil(paused))
            return
        }
        if Date() >= session.deadline {
            finish()
            return
        }
        remainingSeconds = Int(ceil(session.deadline.timeIntervalSinceNow))
        let filtered = session.allowedDomainsUntil.filter { $0.value > Date() }
        if filtered.count != session.allowedDomainsUntil.count {
            session.allowedDomainsUntil = filtered
            self.session = session
            persist()
        }
        checkWebsite()
    }

    private func blockIfNeeded(_ app: NSRunningApplication) {
        guard let session, session.pausedSeconds == nil,
              let profile = profiles.first(where: { $0.id == session.profileID }),
              let bundleID = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !Self.protectedBundleIDs.contains(bundleID),
              profile.blockedApplications.contains(where: { $0.bundleID == bundleID }) ||
                session.extraBlockedApplications.contains(where: { $0.bundleID == bundleID })
        else { return }
        if app.hide() {
            core?.showMessage("\(app.localizedName ?? "Приложение") скрыто на время фокуса", tone: .neutral)
        }
    }

    private func checkWebsite() {
        guard websiteTask == nil,
              Date().timeIntervalSince(lastWebsitePoll) >= 2,
              let session, session.pausedSeconds == nil,
              let profile = activeProfile,
              let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              FocusWebsiteBlocker.supports(id)
        else { return }
        let all = Set(profile.blockedDomains + session.extraBlockedDomains)
        let allowed = session.allowedDomainsUntil.filter { $0.value > Date() }.keys
        let domains = Array(all.subtracting(allowed))
        guard !domains.isEmpty else { return }
        lastWebsitePoll = Date()
        let job = Task.detached(priority: .utility) {
            FocusWebsiteBlocker.enforce(browserID: id, domains: domains)
        }
        websiteTask = job
        Task { [weak self] in
            let blocked = await job.value
            guard let self else { return }
            if self.websiteTask != nil { self.websiteTask = nil }
            if blocked, self.session?.pausedSeconds == nil {
                self.core?.showMessage("Сайт заблокирован до конца сеанса", tone: .neutral)
            }
        }
    }

    private func runShortcut(_ id: UUID) {
        guard let core, core.settings.appleShortcutsEnabled else { return }
        core.appleShortcutCoordinator.run(id: id)
    }

    private func runWorkflow(_ id: UUID) {
        guard let core, core.settings.workflowsEnabled else { return }
        core.workflowCoordinator.run(id)
    }

    private func persist() {
        let saved = FocusSavedState(
            profiles: profiles, selectedProfileID: selectedProfileID, session: session)
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            core?.showMessage("Не удалось сохранить настройки фокуса", tone: .danger)
        }
    }
}
