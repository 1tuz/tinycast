import Foundation

enum CommandID: String, CaseIterable, Sendable {
    /// The palette's chat keeps the id it shipped with, so its hotkeys and fallback still reach it.
    case quickAI = "command:ai-chat"
    case aiChat = "command:ai-chat-window"
    case fixGrammar = "command:fix-grammar"
    case rewrite = "command:rewrite"
    case translate = "command:translate"
    case summarize = "command:summarize"
    case base64Encode = "command:base64-encode"
    case base64Decode = "command:base64-decode"
    case convertYAMLJSON = "command:convert-yaml-json"
    case decodeJWT = "command:decode-jwt"
    case calculateCIDR = "command:calculate-cidr"
    case decodeKubernetesSecret = "command:decode-kubernetes-secret"
    case explainCron = "command:explain-cron"
    case formatJSON = "command:format-json"
    case minifyJSON = "command:minify-json"
    case hashMD5 = "command:hash-md5"
    case hashSHA256 = "command:hash-sha256"
    case hexEncode = "command:hex-encode"
    case hexDecode = "command:hex-decode"
    case urlEncode = "command:url-encode"
    case urlDecode = "command:url-decode"
    case generateUUID = "command:generate-uuid"
    case timestampToDate = "command:timestamp-to-date"
    case convertColor = "command:convert-color"
    case generateLoremIpsum = "command:generate-lorem-ipsum"
    case convertCase = "command:convert-case"
    case calculatorHistory = "command:calculator-history"
    case clipboardHistory = "command:clipboard-history"
    case pasteSequentially = "command:paste-sequentially"
    case searchEmoji = "command:search-emoji"
    case searchFiles = "command:search-files"
    case searchMenuItems = "command:search-menu-items"
    case switchWindows = "command:switch-windows"
    case switchWindowsBackwards = "command:switch-windows-backwards"
    case openCamera = "command:open-camera"
    case openInBrowser = "command:open-in-browser"
    case runShellCommand = "command:run-shell-command"
    case createCustomCommand = "command:create-custom-command"
    case searchCustomCommands = "command:search-custom-commands"
    case kubeContext = "command:kube-context"
    case kubePods = "command:kube-pods"
    case ansibleRunner = "command:ansible-runner"
    case define = "command:define"
    case joinNextMeeting = "command:join-next-meeting"
    case mySchedule = "command:my-schedule"
    case createEvent = "command:create-event"
    case focusTime = "command:focus-time"
    case copyMeetingLink = "command:copy-meeting-link"
    case openInCalendar = "command:open-in-calendar"
    case showNotes = "command:show-notes"
    case createNote = "command:create-note"
    case searchNotes = "command:search-notes"
    case createWindowLayout = "command:create-window-layout"
    case captureWindowLayout = "command:capture-window-layout"
    case switchRoom = "command:switch-room"
    case createRoom = "command:create-room"
    case createQuicklink = "command:create-quicklink"
    case searchQuicklinks = "command:search-quicklinks"
    case importQuicklinks = "command:import-quicklinks"
    case exportQuicklinks = "command:export-quicklinks"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case exportSettings = "command:export-settings"
    case importSettings = "command:import-settings"
    case importFromRaycast = "command:import-from-raycast"
    case checkForUpdates = "command:check-for-updates"
    case settings = "command:settings"
    case about = "command:about"
    case support = "command:support"
    case quit = "command:quit"

    static let defaultCompactBarCommands: [CommandID] = [
        .clipboardHistory, .searchEmoji, .searchFiles, .searchQuicklinks
    ]

    static let compactBarOptions: [CommandID] =
        defaultCompactBarCommands + [
            .searchSnippets, .showNotes, .mySchedule, .quickAI
        ]

    static let compactBarLimit = 4

    static func validCompactBarCommands(_ commands: [CommandID]) -> Bool {
        commands.count <= compactBarLimit && Set(commands).count == commands.count
            && commands.allSatisfy(compactBarOptions.contains)
    }

    static func compactBarCommands(from identifiers: [String]) -> [CommandID]? {
        let commands = identifiers.compactMap(CommandID.init(rawValue:))
        guard commands.count == identifiers.count, validCompactBarCommands(commands) else { return nil }
        return commands
    }

    var searchKeywords: [String] {
        switch self {
        case .decodeJWT: ["jwt", "bearer", "token", "header", "payload"]
        case .calculateCIDR: ["cidr", "ipv4", "subnet", "netmask", "broadcast"]
        case .decodeKubernetesSecret: ["kubernetes", "k8s", "secret", "base64", "decode"]
        case .convertYAMLJSON: ["yaml", "json", "convert"]
        case .explainCron: ["cron", "schedule", "crontab"]
        default: []
        }
    }

    var name: String { nameResource.resolved() }

    var englishName: String { nameResource.key }

    private var nameResource: LocalizedStringResource {
        switch self {
        case .quickAI: return "Quick AI"
        case .aiChat: return "AI Chat"
        case .fixGrammar: return "Fix Grammar"
        case .rewrite: return "Rewrite"
        case .translate: return "Translate"
        case .summarize: return "Summarize"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .convertYAMLJSON: return "YAML ↔ JSON"
        case .decodeJWT: return "Decode JWT"
        case .calculateCIDR: return "Calculate CIDR"
        case .decodeKubernetesSecret: return "Decode Kubernetes Secret"
        case .explainCron: return "Explain cron"
        case .formatJSON: return "Format JSON"
        case .minifyJSON: return "Minify JSON"
        case .hashMD5: return "Hash (MD5)"
        case .hashSHA256: return "Hash (SHA-256)"
        case .hexEncode: return "Hex Encode"
        case .hexDecode: return "Hex Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .generateUUID: return "Generate UUID"
        case .timestampToDate: return "Timestamp to Date"
        case .convertColor: return "Convert Color"
        case .generateLoremIpsum: return "Generate Lorem Ipsum"
        case .convertCase: return "Convert Case"
        case .calculatorHistory: return "Calculator History"
        case .clipboardHistory: return "Clipboard History"
        case .pasteSequentially: return "Paste Sequentially"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .searchFiles: return "Search Files"
        case .searchMenuItems: return "Search Menu Bar Items"
        case .switchWindows: return "Switch Windows"
        case .switchWindowsBackwards: return "Switch Windows Backwards"
        case .openCamera: return "Open Camera"
        case .openInBrowser: return "Open in Browser"
        case .runShellCommand: return "Run Shell Command"
        case .createCustomCommand: return "Create Custom Command"
        case .searchCustomCommands: return "Search Custom Commands"
        case .kubeContext: return "Kube Context Guard"
        case .kubePods: return "Kubernetes Pods"
        case .ansibleRunner: return "Ansible Runner"
        case .define: return "Define Word"
        case .joinNextMeeting: return "Join Next Meeting"
        case .mySchedule: return "My Schedule"
        case .createEvent: return "Create Event"
        case .focusTime: return "Block Focus Time"
        case .copyMeetingLink: return "Copy Meeting Link"
        case .openInCalendar: return "Open in Calendar"
        case .showNotes: return "Show Notes"
        case .createNote: return "Create Note"
        case .searchNotes: return "Search Notes"
        case .createWindowLayout: return "Create Window Layout"
        case .captureWindowLayout: return "Create Layout from Current Windows"
        case .switchRoom: return "Switch Room"
        case .createRoom: return "Create Room"
        case .createQuicklink: return "Create Quicklink"
        case .searchQuicklinks: return "Search Quicklinks"
        case .importQuicklinks: return "Import Quicklinks"
        case .exportQuicklinks: return "Export Quicklinks"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .exportSettings: return "Export Backup"
        case .importSettings: return "Import Backup"
        case .importFromRaycast: return "Import from Raycast"
        case .checkForUpdates: return "Check for Updates"
        case .settings: return "Tinycast Settings"
        case .about: return "About Tinycast"
        case .support: return "Support Tinycast"
        case .quit: return "Quit Tinycast"
        }
    }

    var sfSymbol: String {
        switch self {
        case .quickAI: return "sparkles"
        case .aiChat: return "bubble.left.and.bubble.right"
        case .fixGrammar: return BuiltInQuickAction.fixGrammar.symbol
        case .rewrite: return BuiltInQuickAction.rewrite.symbol
        case .translate: return BuiltInQuickAction.translate.symbol
        case .summarize: return BuiltInQuickAction.summarize.symbol
        case .base64Encode: return BuiltInQuickAction.base64Encode.symbol
        case .base64Decode: return BuiltInQuickAction.base64Decode.symbol
        case .convertYAMLJSON: return BuiltInQuickAction.convertYAMLJSON.symbol
        case .decodeJWT: return BuiltInQuickAction.decodeJWT.symbol
        case .calculateCIDR: return BuiltInQuickAction.calculateCIDR.symbol
        case .decodeKubernetesSecret: return BuiltInQuickAction.decodeKubernetesSecret.symbol
        case .explainCron: return BuiltInQuickAction.explainCron.symbol
        case .formatJSON: return BuiltInQuickAction.formatJSON.symbol
        case .minifyJSON: return BuiltInQuickAction.minifyJSON.symbol
        case .hashMD5: return BuiltInQuickAction.hashMD5.symbol
        case .hashSHA256: return BuiltInQuickAction.hashSHA256.symbol
        case .hexEncode: return BuiltInQuickAction.hexEncode.symbol
        case .hexDecode: return BuiltInQuickAction.hexDecode.symbol
        case .urlEncode: return BuiltInQuickAction.urlEncode.symbol
        case .urlDecode: return BuiltInQuickAction.urlDecode.symbol
        case .generateUUID: return BuiltInQuickAction.generateUUID.symbol
        case .timestampToDate: return BuiltInQuickAction.timestampToDate.symbol
        case .convertColor: return BuiltInQuickAction.convertColor.symbol
        case .generateLoremIpsum: return BuiltInQuickAction.generateLoremIpsum.symbol
        case .convertCase: return BuiltInQuickAction.convertCase.symbol
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pasteSequentially: return "list.bullet.clipboard"
        case .searchEmoji: return "face.smiling"
        case .searchFiles: return "doc.text.magnifyingglass"
        case .searchMenuItems: return "menubar.rectangle"
        case .switchWindows, .switchWindowsBackwards: return "macwindow.on.rectangle"
        case .openCamera: return "camera"
        case .openInBrowser: return "globe"
        case .runShellCommand: return "terminal"
        case .createCustomCommand: return "terminal"
        case .searchCustomCommands: return "terminal"
        case .kubeContext: return "network"
        case .kubePods: return "shippingbox"
        case .ansibleRunner: return "terminal"
        case .define: return "book.closed"
        case .joinNextMeeting: return "video.fill"
        case .mySchedule: return "calendar"
        case .createEvent: return "calendar.badge.plus"
        case .focusTime: return "timer"
        case .copyMeetingLink: return "link"
        case .openInCalendar: return "calendar.badge.clock"
        case .showNotes: return "text.page"
        case .createNote: return "note.text.badge.plus"
        case .searchNotes: return "text.magnifyingglass"
        case .createWindowLayout: return "plus.rectangle.on.rectangle"
        case .captureWindowLayout: return "macwindow.badge.plus"
        case .switchRoom: return "door.left.hand.open"
        case .createRoom: return "rectangle.stack.badge.plus"
        case .createQuicklink: return "link.badge.plus"
        case .searchQuicklinks: return Quicklink.sfSymbol
        case .importQuicklinks: return "square.and.arrow.down"
        case .exportQuicklinks: return "square.and.arrow.up"
        case .searchSnippets: return "curlybraces"
        case .createSnippet: return "plus.rectangle.on.rectangle"
        case .exportSettings: return "square.and.arrow.up"
        case .importSettings: return "square.and.arrow.down"
        case .importFromRaycast: return "arrow.down.doc"
        case .checkForUpdates: return "arrow.down.circle"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        case .support: return "heart"
        case .quit: return "power"
        }
    }

    /// Exhaustive, so a fifth shipped action cannot reach the launcher without a row here.
    init(_ action: BuiltInQuickAction) {
        switch action {
        case .fixGrammar: self = .fixGrammar
        case .rewrite: self = .rewrite
        case .translate: self = .translate
        case .summarize: self = .summarize
        case .base64Encode: self = .base64Encode
        case .base64Decode: self = .base64Decode
        case .convertYAMLJSON: self = .convertYAMLJSON
        case .decodeJWT: self = .decodeJWT
        case .calculateCIDR: self = .calculateCIDR
        case .decodeKubernetesSecret: self = .decodeKubernetesSecret
        case .explainCron: self = .explainCron
        case .formatJSON: self = .formatJSON
        case .minifyJSON: self = .minifyJSON
        case .hashMD5: self = .hashMD5
        case .hashSHA256: self = .hashSHA256
        case .hexEncode: self = .hexEncode
        case .hexDecode: self = .hexDecode
        case .urlEncode: self = .urlEncode
        case .urlDecode: self = .urlDecode
        case .generateUUID: self = .generateUUID
        case .timestampToDate: self = .timestampToDate
        case .convertColor: self = .convertColor
        case .generateLoremIpsum: self = .generateLoremIpsum
        case .convertCase: self = .convertCase
        }
    }

    var builtInQuickAction: BuiltInQuickAction? {
        switch self {
        case .fixGrammar: return .fixGrammar
        case .rewrite: return .rewrite
        case .translate: return .translate
        case .summarize: return .summarize
        case .base64Encode: return .base64Encode
        case .base64Decode: return .base64Decode
        case .convertYAMLJSON: return .convertYAMLJSON
        case .decodeJWT: return .decodeJWT
        case .calculateCIDR: return .calculateCIDR
        case .decodeKubernetesSecret: return .decodeKubernetesSecret
        case .explainCron: return .explainCron
        case .formatJSON: return .formatJSON
        case .minifyJSON: return .minifyJSON
        case .hashMD5: return .hashMD5
        case .hashSHA256: return .hashSHA256
        case .hexEncode: return .hexEncode
        case .hexDecode: return .hexDecode
        case .urlEncode: return .urlEncode
        case .urlDecode: return .urlDecode
        case .generateUUID: return .generateUUID
        case .timestampToDate: return .timestampToDate
        case .convertColor: return .convertColor
        case .generateLoremIpsum: return .generateLoremIpsum
        case .convertCase: return .convertCase
        default: return nil
        }
    }

    /// Queries this command wins until the user opens a rival more.
    var boostedTerms: Set<String> {
        switch self {
        case .quickAI: ["ai"]
        case .aiChat: ["chat"]
        default: []
        }
    }

    /// Suggested, highest first, until the user's own habits fill the section.
    var suggestionPriority: Int? {
        switch self {
        case .clipboardHistory: 80
        case .searchFiles: 70
        case .mySchedule: 60
        case .searchEmoji: 50
        case .createQuicklink, .createSnippet: 30
        default: nil
        }
    }

    /// Query-driven: the typed text is their input, so they are built where offered, never listed.
    var isQueryDriven: Bool {
        self == .openInBrowser || self == .runShellCommand
    }

    /// A chord carries no query, and none should be able to terminate the app outright.
    var hotKeyAction: HotKeyAction? {
        isQueryDriven || self == .quit ? nil : .command(self)
    }
}
