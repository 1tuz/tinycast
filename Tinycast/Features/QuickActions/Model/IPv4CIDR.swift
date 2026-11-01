import Foundation

enum IPv4CIDR {
    static func explain(_ input: String) throws -> String {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, numeric(parts[1]), let prefix = Int(parts[1]), (0...32).contains(prefix) else {
            throw DeveloperUtilityError.invalidCIDR
        }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { throw DeveloperUtilityError.invalidCIDR }
        var address: UInt32 = 0
        for octet in octets {
            guard numeric(octet), octet.count == 1 || octet.first != "0", let value = UInt8(octet) else {
                throw DeveloperUtilityError.invalidCIDR
            }
            address = (address << 8) | UInt32(value)
        }
        let mask = prefix == 0 ? 0 : UInt32.max << (32 - prefix)
        let network = address & mask
        let broadcast = network | ~mask
        let first = prefix >= 31 ? network : network + 1
        let last = prefix >= 31 ? broadcast : broadcast - 1
        let hostCount = String(UInt64(last) - UInt64(first) + 1)
        let networkText = dotted(network)
        let maskText = dotted(mask)
        let wildcardText = dotted(~mask)
        let broadcastText = dotted(broadcast)
        let firstText = dotted(first)
        let lastText = dotted(last)
        return [
            String(localized: "Network: \(networkText)"),
            String(localized: "Netmask: \(maskText)"),
            String(localized: "Wildcard: \(wildcardText)"),
            String(localized: "Broadcast: \(broadcastText)"),
            String(localized: "Host range: \(firstText) – \(lastText)"),
            String(localized: "Hosts: \(hostCount)"),
        ].joined(separator: "\n")
    }

    private static func numeric(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy({ (48...57).contains($0) })
    }

    private static func dotted(_ address: UInt32) -> String {
        [24, 16, 8, 0].map { String((address >> $0) & 255) }.joined(separator: ".")
    }
}
