export interface KubeLensPod {
  name: string;
  phase: string;
  containers: string[];
  diagnostic: string;
  healthy: boolean;
}

export interface KubeLensEvent {
  type: string;
  reason: string;
  message: string;
  object: string;
  timestamp: string;
}

export function kubeLensArguments(
  operation: string,
  context: string,
  namespace: string,
  pod?: string,
): string[] {
  if (!context || /[\0\r\n]/.test(context)) throw new Error("Configure an exact Kubernetes context");
  if (!/^[a-z0-9](?:[-a-z0-9]*[a-z0-9])?$/.test(namespace)) throw new Error("Configure a valid namespace");
  if (operation === "pods" || operation === "events") {
    return ["get", operation, "--output", "json", "--context", context, "--namespace", namespace];
  }
  if ((operation === "logs" || operation === "describe") && pod && /^[a-z0-9](?:[-a-z0-9.]*[a-z0-9])?$/.test(pod)) {
    if (operation === "logs") return ["logs", pod, "--context", context, "--namespace", namespace, "--tail", "100"];
    return ["describe", "pod", pod, "--context", context, "--namespace", namespace];
  }
  throw new Error("Unsupported read-only Kubernetes operation");
}

export function parsePods(text: string): KubeLensPod[] {
  const root = JSON.parse(text);
  if (!root || !Array.isArray(root.items)) throw new Error("Invalid Kubernetes pod response");
  return root.items.map((item: any) => {
    const name = item?.metadata?.name;
    if (typeof name !== "string" || !name) throw new Error("Invalid Kubernetes pod response");
    const phase = typeof item?.status?.phase === "string" ? item.status.phase : "Unknown";
    const statuses = Array.isArray(item?.status?.containerStatuses) ? item.status.containerStatuses : [];
    const diagnostic = statuses.map((status: any) =>
      status?.state?.waiting?.reason ?? status?.state?.terminated?.reason ?? "",
    ).find(Boolean) ?? phase;
    const containers = Array.isArray(item?.spec?.containers)
      ? item.spec.containers.map((container: any) => container.name).filter((value: any) => typeof value === "string")
      : [];
    return { name, phase, containers, diagnostic, healthy: phase === "Running" && statuses.every((status: any) => status.ready === true) };
  });
}

export function parseEvents(text: string): KubeLensEvent[] {
  const root = JSON.parse(text);
  if (!root || !Array.isArray(root.items)) throw new Error("Invalid Kubernetes event response");
  return root.items.map((item: any) => ({
    type: typeof item?.type === "string" ? item.type : "Normal",
    reason: typeof item?.reason === "string" ? item.reason : "Event",
    message: typeof item?.message === "string" ? item.message : "",
    object: typeof item?.regarding?.name === "string" ? item.regarding.name
      : typeof item?.involvedObject?.name === "string" ? item.involvedObject.name : "",
    timestamp: typeof item?.eventTime === "string" ? item.eventTime
      : typeof item?.lastTimestamp === "string" ? item.lastTimestamp
      : typeof item?.metadata?.creationTimestamp === "string" ? item.metadata.creationTimestamp : "",
  })).sort((left: KubeLensEvent, right: KubeLensEvent) => right.timestamp.localeCompare(left.timestamp));
}
