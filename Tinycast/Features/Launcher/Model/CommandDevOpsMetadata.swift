import Foundation

extension CommandID {
    var devOpsCategory: DevOpsCommandCategory? {
        switch self {
        case .kubeContext, .kubePods, .decodeKubernetesSecret: .kubernetes
        case .ansibleRunner: .ansible
        case .calculateCIDR: .networking
        case .decodeJWT: .security
        default: nil
        }
    }
}
