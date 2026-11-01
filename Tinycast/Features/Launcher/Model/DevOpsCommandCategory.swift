import Foundation

enum DevOpsCommandCategory: String, Hashable, Sendable {
    case git
    case docker
    case kubernetes
    case ansible
    case networking
    case security
}
