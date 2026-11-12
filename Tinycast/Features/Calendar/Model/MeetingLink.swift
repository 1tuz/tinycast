import Foundation

struct MeetingLink: Hashable, Sendable {
    let provider: Provider
    let url: URL
    /// The account whose calendar carried this link, for a provider that preselects it.
    let account: String?

    /// The desktop app's own URL, where one can be formed without guessing. Nil means open the web.
    var appURL: URL? { provider.appURL(for: url) }

    /// The link as written, naming the account where the provider takes one.
    var webURL: URL { provider.accountURL(for: url, account: account) ?? url }

    /// Whether opening this link joins a call rather than opening a conversation.
    /// Auto join only ever fires for a call; a conversation link is a manual gesture.
    var isConversation: Bool { provider.isConversation(url: url) }

    /// The verb a surface offers for this link: calls are joined, conversations opened.
    var actionTitle: String { provider.actionTitle(url: url) }

    /// Fields in precedence order; a named provider anywhere beats a bare link found earlier.
    static func detect(fields: [String?], account: String? = nil) -> MeetingLink? {
        var fallback: MeetingLink?
        for field in fields.compactMap({ $0 }) {
            for url in webURLs(in: field) {
                guard let provider = classify(url) else { continue }
                let link = MeetingLink(provider: provider, url: url, account: account)
                if provider != .generic { return link }
                if fallback == nil { fallback = link }
            }
        }
        return fallback
    }

    static func detect(in text: String) -> MeetingLink? {
        detect(fields: [text])
    }

    static func accountAddress(of participantURL: URL, isCurrentUser: Bool) -> String? {
        isCurrentUser ? address(of: participantURL) : nil
    }

    /// EventKit's `mailto:` participant URLs are opaque: `path` sees nothing, only the string does.
    static func address(of participantURL: URL) -> String? {
        let string = participantURL.absoluteString
        guard string.lowercased().hasPrefix("mailto:") else { return nil }
        let raw = string.dropFirst("mailto:".count)
        let address = raw.removingPercentEncoding ?? String(raw)
        guard address.contains("@") else { return nil }
        return address
    }

    /// A known host failing its path rule is rejected, never demoted to `.generic`.
    /// So is a link carrying credentials or an explicit port: no real invite has either,
    /// and both are classic look-alike tricks. An unknown host stays a `.generic` link.
    private static func classify(_ url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host()?.lowercased(),
            url.user() == nil, url.password() == nil, url.port == nil
        else { return nil }
        guard let provider = Provider(host: host) else { return .generic }
        return provider.admits(url: url) ? provider : nil
    }

    private static let terminators: Set<Character> = [
        " ", "\t", "\n", "\r", "\r\n", "\"", "'", "<", ">", "«", "»", "\u{00A0}"
    ]
    private static let trailingNoise: Set<Character> = [".", ",", ";", ":", ")", "]", "}", "!", "?"]

    /// Hand-rolled: `NSDataDetector` is not `Sendable` and costs more than the scan.
    private static func webURLs(in text: String) -> [URL] {
        var found: [URL] = []
        var cursor = text.startIndex
        while cursor < text.endIndex,
            let start = text.range(
                of: "http", options: .caseInsensitive, range: cursor..<text.endIndex)?.lowerBound
        {
            let end = text[start...].firstIndex(where: terminators.contains) ?? text.endIndex
            var candidate = text[start..<end]
            while let last = candidate.last, trailingNoise.contains(last) {
                candidate = candidate.dropLast()
            }
            let lowered = candidate.lowercased()
            if lowered.hasPrefix("http://") || lowered.hasPrefix("https://"),
                let url = URL(string: String(candidate))
            {
                found.append(url)
            }
            cursor = end > start ? end : text.index(after: start)
        }
        return found
    }
}

extension MeetingLink {
    enum Provider: String, CaseIterable, Sendable {
        case zoom
        case googleMeet
        case teams
        case webex
        case jitsi
        case whereby
        case chime
        case gotoMeeting
        case blueJeans
        case skype
        case telemost
        case telegram
        case whatsapp
        case signal
        case discord
        case viber
        case messenger
        case line
        case wechat
        case kakaotalk
        /// Any other http(s) link the event carries — joinable, just not identifiable.
        case generic

        var title: String {
            switch self {
            case .zoom: return "Zoom"
            case .googleMeet: return "Google Meet"
            case .teams: return "Microsoft Teams"
            case .webex: return "Webex"
            case .jitsi: return "Jitsi"
            case .whereby: return "Whereby"
            case .chime: return "Amazon Chime"
            case .gotoMeeting: return "GoTo Meeting"
            case .blueJeans: return "BlueJeans"
            case .skype: return "Skype"
            case .telemost: return "Yandex Telemost"
            case .telegram: return "Telegram"
            case .whatsapp: return "WhatsApp"
            case .signal: return "Signal"
            case .discord: return "Discord"
            case .viber: return "Viber"
            case .messenger: return "Messenger"
            case .line: return "LINE"
            case .wechat: return "WeChat"
            case .kakaotalk: return "KakaoTalk"
            case .generic: return String(localized: "Meeting Link")
            }
        }

        /// No brand artwork ships, so the glyph says only what kind of thing this is.
        var sfSymbol: String {
            switch self {
            case .zoom, .googleMeet, .teams, .webex, .jitsi, .whereby, .chime, .gotoMeeting,
                .blueJeans, .skype, .telemost, .signal:
                return "video.fill"
            case .telegram, .whatsapp, .discord, .viber, .messenger, .line, .wechat, .kakaotalk:
                return "bubble.left.and.bubble.right.fill"
            case .generic: return "link"
            }
        }

        /// Whether opening this link is a conversation action rather than joining a call.
        /// Per-URL, because Signal mixes both: `signal.link/#key=…` is a call, while
        /// `signal.me/#p/…` and `signal.group/…` open a chat. Everything else is one or
        /// the other for the provider as a whole. Conversation links never auto join.
        func isConversation(url: URL) -> Bool {
            switch self {
            case .telegram, .whatsapp, .discord, .viber, .messenger, .line, .wechat, .kakaotalk:
                return true
            case .signal:
                return url.host()?.lowercased() != "signal.link"
            case .zoom, .googleMeet, .teams, .webex, .jitsi, .whereby, .chime, .gotoMeeting,
                .blueJeans, .skype, .telemost, .generic:
                return false
            }
        }

        /// The verb a surface offers for this link: calls are joined, conversations opened.
        func actionTitle(url: URL) -> String {
            isConversation(url: url) ? String(localized: "Open") : String(localized: "Join")
        }

        /// Two matchers: the classic meeting services match whole host or any subdomain
        /// of it, because enterprises put their own rooms on `acme.zoom.us`. The
        /// conversation providers match the host exactly — their documented invite
        /// forms all live on one fixed host, and `evil.t.me` is not Telegram.
        private static let subdomainProviders: [(Provider, [String])] = [
            (.zoom, ["zoom.us", "zoom.com", "zoomgov.com"]),
            (.googleMeet, ["meet.google.com"]),
            (.teams, ["teams.microsoft.com", "teams.microsoft.us", "teams.live.com"]),
            (.webex, ["webex.com", "webex.com.cn"]),
            (.jitsi, ["meet.jit.si", "8x8.vc"]),
            (.whereby, ["whereby.com"]),
            (.chime, ["chime.aws"]),
            (.gotoMeeting, ["gotomeeting.com", "gotomeet.me", "app.goto.com"]),
            (.blueJeans, ["bluejeans.com"]),
            (.skype, ["join.skype.com"]),
            (.telemost, ["telemost.yandex.ru", "telemost.yandex.com", "telemost.360.yandex.ru"]),
        ]

        private static let exactHosts: [String: Provider] = [
            "t.me": .telegram,
            "chat.whatsapp.com": .whatsapp,
            "wa.me": .whatsapp,
            "signal.me": .signal,
            "signal.link": .signal,
            "signal.group": .signal,
            "discord.gg": .discord,
            "discord.com": .discord,
            "invite.viber.com": .viber,
            "chat.viber.com": .viber,
            "m.me": .messenger,
            "line.me": .line,
            "chat.weixin.qq.com": .wechat,
            "open.kakao.com": .kakaotalk,
            "pf.kakao.com": .kakaotalk,
        ]

        /// Flattened and ordered longest-first, so `meet.jit.si` can never be
        /// mistaken for a shorter suffix it ends with.
        private static let suffixLookup: [(suffix: String, provider: Provider)] =
            subdomainProviders.flatMap { provider, suffixes in
                suffixes.map { (suffix: $0, provider: provider) }
            }
            .sorted { $0.suffix.count > $1.suffix.count }

        init?(host: String) {
            if let exact = Self.exactHosts[host] { self = exact; return }
            guard let match = Self.suffixLookup.first(where: { suffix, _ in
                host == suffix || host.hasSuffix("." + suffix)
            }) else { return nil }
            self = match.provider
        }

        /// Whether the URL's shape is the provider's documented meeting or conversation
        /// entry point, rather than a download page, a profile, or one of the site's
        /// other pages. Takes the whole URL because some providers keep the interesting
        /// part in the fragment, and some admit different paths per host.
        func admits(url: URL) -> Bool {
            let segments = url.path().split(separator: "/").map { $0.lowercased() }
            let host = url.host()?.lowercased() ?? ""
            let fragment = url.fragment() ?? ""
            switch self {
            case .zoom:
                return segments.contains { ["j", "w", "s", "my"].contains($0) }
            case .googleMeet:
                return segments.count == 1 && segments[0] != "tel"
            case .teams:
                return segments.contains("meetup-join") || segments.contains("meet")
            // Telemost: telemost.yandex.ru/j/<id>, and the room id never has a slash.
            case .telemost:
                return segments.first == "j" && segments.count == 2
            // Telegram (core.telegram.org/api/links): t.me/+<hash> and
            // t.me/joinchat/<hash> private invites, t.me/addlist/<hash> folder invites,
            // and t.me/<username> or t.me/<username>/<message id> for a public chat.
            // The site's own pages — share, apps, faq, login, and the rest — are not.
            case .telegram:
                guard let first = segments.first else { return false }
                if first == "joinchat" || first == "addlist" {
                    return segments.count == 2 && Self.tokenish(segments[1])
                }
                if first.hasPrefix("+") {
                    return segments.count == 1 && first.count > 1
                }
                guard segments.count <= 2, !first.isEmpty,
                    !Self.telegramReserved.contains(first)
                else { return false }
                // The second segment, when present, is a message id: digits only.
                guard segments.count == 2 else { return true }
                return segments[1].allSatisfy(\.isNumber)
            // WhatsApp (faq.whatsapp.com): chat.whatsapp.com/<invite code> and
            // wa.me/<phone number, digits only> are the documented entry points.
            case .whatsapp:
                if host == "wa.me" {
                    return segments.count == 1 && Self.asciiDigits(segments[0])
                }
                return segments.count == 1 && Self.tokenish(segments[0])
            // Signal (signal.org): call links live at signal.link/#key=<hex>; group
            // invites at signal.group/#<hash> or signal.group/join/<hash>; person
            // links at signal.me/#p/<phone or username> or #eu/<username>. Anything
            // else on these hosts is the site, not a link.
            case .signal:
                if host == "signal.group" {
                    if segments.isEmpty { return Self.tokenish(fragment) }
                    return segments.first == "join" && segments.count == 2
                        && Self.tokenish(segments[1])
                }
                if segments.isEmpty {
                    if host == "signal.link" {
                        return fragment.hasPrefix("key=") && fragment.count > "key=".count
                    }
                    if host == "signal.me" {
                        let lowered = fragment.lowercased()
                        if lowered.hasPrefix("p/") { return fragment.count > "p/".count }
                        if lowered.hasPrefix("eu/") { return fragment.count > "eu/".count }
                    }
                }
                return false
            // Discord (support.discord.com): discord.gg/<code> and
            // discord.com/invite/<code> are invites; discord.com/channels/… deep-links
            // a server the user already belongs to. Everything else on discord.com is
            // the site: login, downloads, apps.
            case .discord:
                if host == "discord.gg" { return segments.count == 1 }
                if segments.first == "invite" { return segments.count == 2 }
                return segments.first == "channels" && segments.count >= 3
            // Viber (support.viber.com): invite.viber.com/<id> and chat.viber.com/<id>.
            case .viber:
                return segments.count == 1 && Self.tokenish(segments[0])
            // Messenger: m.me/<username> opens the chat; the share widget does not.
            case .messenger:
                return segments.count == 1 && !Self.messengerReserved.contains(segments[0])
            // LINE (developers.line.biz): line.me/R/<type>/… share targets and
            // line.me/ti/g…/ group invitations. A bare /R or /ti is not a link.
            case .line:
                if segments.first == "r" { return segments.count >= 3 }
                if segments.first == "ti" {
                    return segments.count >= 3 && segments[1].hasPrefix("g")
                }
                return false
            // WeChat: chat.weixin.qq.com/<id> is the group-invite form.
            case .wechat:
                return segments.count == 1 && Self.tokenish(segments[0])
            // KakaoTalk: open.kakao.com/o/<code> open chats; pf.kakao.com/_xChat… is
            // the open-chat landing on a channel page.
            case .kakaotalk:
                if host == "open.kakao.com" { return segments.first == "o" && segments.count == 2 }
                return segments.first?.hasPrefix("_xchat") == true
            // Meeting services whose whole host is meeting-shaped: any non-empty path
            // is a room the event named.
            case .webex, .jitsi, .whereby, .chime, .gotoMeeting, .blueJeans, .skype, .generic:
                return !segments.isEmpty
            }
        }

        /// The words that occupy t.me's namespace without naming a chat.
        private static let telegramReserved: Set<String> = [
            "share", "apps", "faq", "login", "blog", "about", "privacy", "tos", "premium",
            "telegram", "download", "jobs", "moderation", "terms",
        ]

        /// m.me's own words: its share widget and its redirect helpers.
        private static let messengerReserved: Set<String> = ["share", "login", "help"]

        /// An invite token: ASCII letters, digits, hyphen, underscore — with at least one
        /// alphanumeric, so a bare `-`, `___`, or a Unicode homoglyph run is not one.
        private static func tokenish(_ segment: String) -> Bool {
            !segment.isEmpty
                && segment.allSatisfy { Self.tokenCharacters.contains($0) }
                && segment.contains(where: { $0.isLetter || $0.isNumber })
        }

        private static let tokenCharacters =
            Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

        /// ASCII digits only: a phone number cannot carry Unicode numerals.
        private static func asciiDigits(_ segment: String) -> Bool {
            !segment.isEmpty && segment.allSatisfy { $0.isASCII && $0.isNumber }
        }

        private static let accountQuery = "authuser"
        /// Meet's own links keep `@` readable; `+` cannot stay, as a server may read it as a space.
        private static let accountAllowed = CharacterSet.urlQueryAllowed.subtracting(
            CharacterSet(charactersIn: "+&="))

        /// Only Google Meet takes an account; `authuser` picks between signed-in identities.
        func accountURL(for url: URL, account: String?) -> URL? {
            guard self == .googleMeet, let account,
                let encoded = account.addingPercentEncoding(withAllowedCharacters: Self.accountAllowed),
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { return nil }
            let items = components.percentEncodedQueryItems ?? []
            // A link naming its own account was written deliberately, and outranks the calendar's.
            guard !items.contains(where: { $0.name == Self.accountQuery }) else { return nil }
            components.percentEncodedQueryItems =
                items + [URLQueryItem(name: Self.accountQuery, value: encoded)]
            return components.url
        }

        /// Only the two rewrites Apple's handlers make unambiguous; anything else opens
        /// the web. The messenger links are no exception: none has a documented
        /// universal native conversion, so the https link as written is the way in.
        func appURL(for url: URL) -> URL? {
            switch self {
            case .zoom: return zoomAppURL(for: url)
            case .teams: return teamsAppURL(for: url)
            default: return nil
            }
        }

        private func zoomAppURL(for url: URL) -> URL? {
            let segments = url.path().split(separator: "/")
            guard let marker = segments.firstIndex(where: { ["j", "w", "s"].contains($0.lowercased()) }),
                let conference = segments.dropFirst(marker + 1).first
            else { return nil }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = "zoom.us"
            components.path = "/join"
            var query = [URLQueryItem(name: "confno", value: String(conference))]
            if let password = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "pwd" })?.value
            {
                query.append(URLQueryItem(name: "pwd", value: password))
            }
            components.queryItems = query
            return components.url
        }

        private func teamsAppURL(for url: URL) -> URL? {
            guard url.host()?.lowercased().hasSuffix("teams.microsoft.com") == true else { return nil }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
            return URL(string: "msteams:" + url.path() + (query.map { "?" + $0 } ?? ""))
        }
    }
}
