import Foundation

struct AnsibleInventoryGroup: Equatable, Sendable, Identifiable {
    let name: String
    let hosts: [String]

    var id: String { name }
}

struct AnsibleInventory: Equatable, Sendable {
    let groups: [AnsibleInventoryGroup]
    let hosts: [String]

    enum ParseError: Error, Equatable {
        case invalidJSON
        case invalidRoot
        case invalidGroup(String)
    }

    static func parse(_ data: Data) throws -> AnsibleInventory {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            throw ParseError.invalidJSON
        }
        guard let object = root as? [String: Any] else { throw ParseError.invalidRoot }

        var groups: [AnsibleInventoryGroup] = []
        var allHosts = Set<String>()
        for name in object.keys.sorted() where name != "_meta" {
            guard let details = object[name] as? [String: Any] else {
                throw ParseError.invalidGroup(name)
            }
            let rawHosts = details["hosts"]
            guard rawHosts == nil || rawHosts is [String] else {
                throw ParseError.invalidGroup(name)
            }
            let hosts = (rawHosts as? [String] ?? []).sorted()
            allHosts.formUnion(hosts)
            groups.append(AnsibleInventoryGroup(name: name, hosts: hosts))
        }
        return AnsibleInventory(groups: groups, hosts: allHosts.sorted())
    }
}
