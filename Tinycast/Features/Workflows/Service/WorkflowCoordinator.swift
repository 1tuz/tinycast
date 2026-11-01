import AppKit
import Darwin
import Dispatch
import Observation

@MainActor
@Observable
final class WorkflowCoordinator {
    let store: WorkflowStore
    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    var onRunCommand: ((CommandID) -> Void)?
    var onRunCustomCommand: ((UUID, [String]) -> Void)?

    @ObservationIgnored private var timeTimer: Timer?
    @ObservationIgnored private var clipboardTimer: Timer?
    @ObservationIgnored private var clipboardChangeCount: Int?
    @ObservationIgnored private var fileWatchers: [UUID: DispatchSourceFileSystemObject] = [:]
    @ObservationIgnored private var lastTimeMinute: [UUID: Int] = [:]
    @ObservationIgnored private var lastFileEvent: [UUID: Date] = [:]
    private(set) var unavailableFolderIDs: Set<UUID> = []

    init(store: WorkflowStore, settings: AppSettings, hotKeys: HotKeyManager) {
        self.store = store
        self.settings = settings
        self.hotKeys = hotKeys
    }

    isolated deinit { stopMonitors() }

    func start() {
        store.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func allows(_ id: UUID) -> Bool {
        settings.workflowsEnabled && store.workflow(id: id)?.isEnabled == true
    }

    func run(_ id: UUID) {
        guard allows(id), let workflow = store.workflow(id: id),
            let action = workflow.commandAction
        else { return }
        switch action {
        case .builtIn(let command): onRunCommand?(command)
        case .customCommand(let id, let arguments): onRunCustomCommand?(id, arguments)
        }
    }

    func applyEnabled() { applyTriggers() }

    private func refresh() {
        hotKeys.updateWorkflows(Set(store.workflows.map(\.id)))
        applyTriggers()
    }

    private func applyTriggers() {
        stopMonitors()
        guard settings.workflowsEnabled else { return }
        let enabled = store.workflows.filter(\.isEnabled)
        if enabled.contains(where: { $0.trigger.kind == .dailyTime }) {
            let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkTimeTriggers() }
            }
            RunLoop.main.add(timer, forMode: .common)
            timeTimer = timer
        }
        if enabled.contains(where: { $0.trigger.kind == .clipboardChange }) {
            clipboardChangeCount = NSPasteboard.general.changeCount
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkClipboardTrigger() }
            }
            timer.tolerance = 0.1
            RunLoop.main.add(timer, forMode: .common)
            clipboardTimer = timer
        }
        for workflow in enabled where workflow.trigger.kind == .fileChange {
            watch(workflow)
        }
    }

    private func stopMonitors() {
        timeTimer?.invalidate()
        timeTimer = nil
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        clipboardChangeCount = nil
        for watcher in fileWatchers.values { watcher.cancel() }
        fileWatchers.removeAll()
        unavailableFolderIDs.removeAll()
    }

    private func checkTimeTriggers(now: Date = Date()) {
        guard settings.workflowsEnabled else { return }
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let minuteStamp = Int(now.timeIntervalSince1970 / 60)
        for workflow in store.workflows where workflow.isEnabled {
            guard workflow.trigger.kind == .dailyTime,
                workflow.trigger.hour == hour, workflow.trigger.minute == minute,
                lastTimeMinute[workflow.id] != minuteStamp
            else { continue }
            lastTimeMinute[workflow.id] = minuteStamp
            run(workflow.id)
        }
    }

    private func checkClipboardTrigger() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardChangeCount else { return }
        clipboardChangeCount = pasteboard.changeCount
        guard pasteboard.types?.contains(ClipboardManager.internalType) != true else { return }
        for workflow in store.workflows
        where workflow.isEnabled && workflow.trigger.kind == .clipboardChange {
            run(workflow.id)
        }
    }

    private func watch(_ workflow: Workflow) {
        let id = workflow.id
        let path = workflow.trigger.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, fileWatchers[id] == nil else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            unavailableFolderIDs.insert(id)
            return
        }
        unavailableFolderIDs.remove(id)
        let events: DispatchSource.FileSystemEvent = [.write, .extend, .attrib, .rename, .delete]
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let event = self.fileWatchers[id]?.data else { return }
                let removed = event.contains(.rename) || event.contains(.delete)
                self.handleFileEvent(id, removed: removed)
            }
        }
        source.setCancelHandler { close(descriptor) }
        fileWatchers[id] = source
        source.resume()
    }

    private func handleFileEvent(_ id: UUID, removed: Bool) {
        if removed {
            fileWatchers.removeValue(forKey: id)?.cancel()
            unavailableFolderIDs.insert(id)
        }
        let now = Date()
        guard now.timeIntervalSince(lastFileEvent[id] ?? .distantPast) >= 0.5 else { return }
        lastFileEvent[id] = now
        run(id)
    }
}
