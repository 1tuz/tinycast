import Foundation

@main
struct FocusProfileTest {
    static func main() throws {
        precondition(FocusDomain.normalize("https://www.youtube.com/watch?v=1") == "youtube.com")
        precondition(FocusDomain.normalize(" reddit.com/r/swift ") == "reddit.com")
        precondition(FocusDomain.normalize("abc") == nil)
        precondition(FocusDomain.normalize("something.com; delete") == nil)
        precondition(FocusDomain.normalize("-invalid.com") == nil)
        precondition(FocusDomain.matches("m.youtube.com", blocked: "youtube.com"))
        precondition(!FocusDomain.matches("notyoutube.com", blocked: "youtube.com"))
        precondition(FocusDomain.shouldBlock(URL(string: "https://reddit.com/r/swift")!, domains: ["reddit.com"]))
        precondition(!FocusDomain.shouldBlock(URL(string: "https://reddit.com.evil.org")!, domains: ["reddit.com"]))
        let profile = FocusProfile(name: "Работа", blockedDomains: ["reddit.com"])
        let session = FocusSession(profileID: profile.id, startedAt: Date(), deadline: Date().addingTimeInterval(600))
        let saved = FocusSavedState(profiles: [profile], selectedProfileID: profile.id, session: session)
        let decoded = try JSONDecoder().decode(FocusSavedState.self, from: JSONEncoder().encode(saved))
        precondition(decoded.profiles == [profile])
        precondition(decoded.session?.profileID == profile.id)
        print("Focus models: all assertions passed")
    }
}
