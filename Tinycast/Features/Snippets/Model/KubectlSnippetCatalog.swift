import Foundation

enum KubectlSnippetCatalog {
    private static let namespaceArgument =
        "{argument name=\"Namespace\" "
        + "options=\"default, kube-system, production\"}"
    private static let resourceArgument =
        "{argument name=\"Resource\" options=\"pod, deployment, service\"}"

    static let snippets = [
        Snippet(
            name: String(localized: "Kubectl: Get Pods"),
            text: "kubectl get pods -n \(namespaceArgument)"),
        Snippet(
            name: String(localized: "Kubectl: Describe Resource"),
            text: "kubectl describe \(resourceArgument) {argument name=\"Name\"} -n "
                + namespaceArgument),
        Snippet(
            name: String(localized: "Kubectl: Pod Logs"),
            text: "kubectl logs {argument name=\"Pod\"} -n \(namespaceArgument) "
                + "--all-containers --tail=100"),
        Snippet(
            name: String(localized: "Kubectl: Pod Events"),
            text: "kubectl get events -n \(namespaceArgument) "
                + "--sort-by=.lastTimestamp")
    ]

    static func missing(from existing: [Snippet]) -> [Snippet] {
        let installedTemplates = Set(existing.map(\.text))
        return snippets.filter { !installedTemplates.contains($0.text) }
    }
}
