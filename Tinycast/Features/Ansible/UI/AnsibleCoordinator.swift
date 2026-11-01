import AppKit
import Observation

@MainActor
@Observable
final class AnsibleCoordinator {
    private(set) var inventory: AnsibleInventory?
    private(set) var isLoadingInventory = false
    private(set) var isRunning = false
    private(set) var errorMessage: String?
    var inventoryURL: URL?
    var playbookURL: URL?
    var selectedTarget = ""
    var limit = ""
    var tags = ""
    var canRun: Bool { inventoryURL != nil && playbookURL != nil }
    var isSelectedHost: Bool { inventory?.hosts.contains(selectedTarget) == true }
    var historyRecords: [AnsibleRunRecord] { history.records }

    private struct Invocation {
        let id: UUID
        let run: AnsiblePlaybookRun
        let dryRun: Bool
    }

    private struct ActiveRun {
        let outputID: UUID
        let stop: @Sendable () -> Void
    }

    private let runner: AnsibleRunner
    private let history: AnsibleRunHistoryStore
    private unowned let core: AppCore
    private let activation: ActivationPolicy
    @ObservationIgnored private var activeRun: ActiveRun?
    @ObservationIgnored private var lastInvocation: Invocation?
    @ObservationIgnored private lazy var outputPresenter = CommandOutputPresenter(
        activation: activation,
        rerun: { [weak self] in self?.rerun(id: $0) },
        stop: { [weak self] in self?.stop(outputID: $0) },
        openSettings: { [weak self] in self?.core.settingsCoordinator.showSettings(tab: .general) })
    @ObservationIgnored private lazy var window = AppWindowController(
        title: String(localized: "Ansible Runner"), contentSize: CGSize(width: 620, height: 540),
        resizable: true, autosaveName: "AnsibleRunnerWindow", activation: activation,
        closesOnEscape: true)

    init(runner: AnsibleRunner, history: AnsibleRunHistoryStore, core: AppCore) {
        self.runner = runner
        self.history = history
        self.core = core
        activation = core.activationPolicy
    }

    func show() {
        window.show { AnsibleScreen(coordinator: self) }
    }

    func chooseInventory() {
        guard let selected = chooseFile(title: String(localized: "Choose Ansible inventory")) else { return }
        inventoryURL = selected
        inventory = nil
        selectedTarget = ""
        Task { await loadInventory() }
    }

    func choosePlaybook() {
        guard let selected = chooseFile(title: String(localized: "Choose Ansible playbook")) else { return }
        playbookURL = selected
    }

    func loadInventory() async {
        guard let inventoryURL else { return }
        isLoadingInventory = true
        errorMessage = nil
        defer { isLoadingInventory = false }
        do {
            inventory = try await runner.inventory(at: inventoryURL)
            selectedTarget = inventory?.hosts.first ?? inventory?.groups.first?.name ?? ""
        } catch {
            inventory = nil
            errorMessage = error.localizedDescription
        }
    }

    func runDryRun() { Task { await run(dryRun: true) } }

    func runForReal() { Task { await run(dryRun: false) } }

    func ping() { Task { await runPing() } }

    func stopCurrent() {
        guard let activeRun else { return }
        activeRun.stop()
    }

    func openSSH() {
        let host = selectedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        Task {
            guard let executable = await ExecutableLocator.locate("ssh") else {
                errorMessage = String(localized: "ssh was not found in your command line tools.")
                return
            }
            do { try TerminalCommandLauncher.open(executable: executable, arguments: ["--", host]) } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func run(dryRun: Bool) async {
        guard !isRunning, let inventoryURL, let playbookURL else { return }
        var request = AnsiblePlaybookRun(inventory: inventoryURL, playbook: playbookURL)
        request.limit = limit
        request.tags = tags
        await run(request, dryRun: dryRun)
    }

    private func run(_ request: AnsiblePlaybookRun, dryRun: Bool) async {
        guard !isRunning else { return }
        if !dryRun {
            NSApp.activate(ignoringOtherApps: true)
            guard
                await core.confirm(
                    title: String(localized: "Run playbook for real?"),
                    message: String(
                        localized:
                            "This can change remote hosts. Tinycast will run the selected playbook without --check."
                    ),
                    symbol: "exclamationmark.triangle", confirmTitle: String(localized: "Run for Real"),
                    tone: .danger, confirmRole: .destructive)
            else { return }
        }
        errorMessage = nil
        do {
            let started = try await runner.start(request, dryRun: dryRun, confirmedByUser: !dryRun)
            let commandID = UUID()
            let outputID = outputPresenter.begin(
                commandID: commandID, name: String(localized: "Ansible Playbook"),
                commandText: Self.commandPreview(
                    executable: "ansible-playbook", arguments: request.arguments(dryRun: dryRun)),
                symbol: "terminal")
            activeRun = ActiveRun(outputID: outputID, stop: started.session.stop)
            lastInvocation = Invocation(id: commandID, run: request, dryRun: dryRun)
            isRunning = true
            await consume(
                started.session, outputID: outputID, invocation: lastInvocation, startedAt: started.startedAt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runPing() async {
        guard !isRunning, let inventoryURL,
            !selectedTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        errorMessage = nil
        do {
            let started = try await runner.startPing(host: selectedTarget, inventory: inventoryURL)
            let commandID = UUID()
            let arguments = [selectedTarget, "-i", inventoryURL.path, "-m", "ping"]
            let outputID = outputPresenter.begin(
                commandID: commandID, name: String(localized: "Ansible Ping"),
                commandText: Self.commandPreview(executable: "ansible", arguments: arguments),
                symbol: "network")
            activeRun = ActiveRun(outputID: outputID, stop: started.session.stop)
            lastInvocation = nil
            isRunning = true
            await consume(started.session, outputID: outputID, invocation: nil, startedAt: started.startedAt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func consume(
        _ session: ShellCommandSession, outputID: UUID, invocation: Invocation?, startedAt: Date
    ) async {
        for await event in session.events {
            switch event {
            case .output(let text):
                outputPresenter.append(text, to: outputID)
            case .finished(let result):
                let exitCode: Int32
                switch result.termination {
                case .exited(let status): exitCode = status
                case .stopped: exitCode = 128 + SIGTERM
                case .launchFailed: exitCode = -1
                }
                outputPresenter.finish(
                    CommandOutcome(
                        summary: result.succeeded
                            ? String(localized: "Completed")
                            : String(localized: "Exited with status \(exitCode)"),
                        hint: nil, succeeded: result.succeeded, finishedAt: Date()), for: outputID)
                if let invocation {
                    history.append(
                        AnsibleRunRecord(
                            run: invocation.run, dryRun: invocation.dryRun,
                            startedAt: startedAt, finishedAt: Date(), exitCode: exitCode))
                }
                if activeRun?.outputID == outputID { activeRun = nil }
                isRunning = false
            }
        }
    }

    private func rerun(id: UUID) {
        guard let lastInvocation, lastInvocation.id == id else { return }
        Task { await run(lastInvocation.run, dryRun: lastInvocation.dryRun) }
    }

    private func stop(outputID: UUID) {
        guard let activeRun, activeRun.outputID == outputID else { return }
        activeRun.stop()
    }

    private func chooseFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = String(localized: "Choose")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func commandPreview(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: " ")
    }
}
