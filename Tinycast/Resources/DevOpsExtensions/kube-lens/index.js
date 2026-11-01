var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// Extensions/DevOps/kube-lens/src/index.tsx
var index_exports = {};
__export(index_exports, {
  default: () => Command
});
module.exports = __toCommonJS(index_exports);
var import_react = require("react");
var import_api2 = require("@raycast/api");

// Extensions/DevOps/shared.ts
var import_child_process = require("child_process");
function run(executable, args, cwd) {
  return new Promise((ok, fail) => (0, import_child_process.execFile)(executable, args, { cwd, timeout: 2e4, maxBuffer: 2 * 1024 * 1024 }, (error, stdout) => {
    if (error) {
      const message = error.code === "ENOENT" ? `${executable} is not installed. Install the CLI and configure access.` : error.killed ? `${executable} timed out. Run long commands in Terminal.` : `${executable} failed. Check configuration and access.`;
      fail(new Error(message));
      return;
    }
    ok(String(stdout));
  }));
}

// Extensions/DevOps/ui.tsx
var import_api = require("@raycast/api");
async function action(task) {
  try {
    await task();
  } catch (error) {
    await (0, import_api.showToast)({ style: import_api.Toast.Style.Failure, title: error instanceof Error ? error.message : "Command failed" });
  }
}

// Extensions/DevOps/kube-lens/src/kube-lens.ts
function kubeLensArguments(operation, context, namespace, pod) {
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
function parsePods(text) {
  const root = JSON.parse(text);
  if (!root || !Array.isArray(root.items)) throw new Error("Invalid Kubernetes pod response");
  return root.items.map((item) => {
    const name = item?.metadata?.name;
    if (typeof name !== "string" || !name) throw new Error("Invalid Kubernetes pod response");
    const phase = typeof item?.status?.phase === "string" ? item.status.phase : "Unknown";
    const statuses = Array.isArray(item?.status?.containerStatuses) ? item.status.containerStatuses : [];
    const diagnostic = statuses.map(
      (status) => status?.state?.waiting?.reason ?? status?.state?.terminated?.reason ?? ""
    ).find(Boolean) ?? phase;
    const containers = Array.isArray(item?.spec?.containers) ? item.spec.containers.map((container) => container.name).filter((value) => typeof value === "string") : [];
    return { name, phase, containers, diagnostic, healthy: phase === "Running" && statuses.every((status) => status.ready === true) };
  });
}
function parseEvents(text) {
  const root = JSON.parse(text);
  if (!root || !Array.isArray(root.items)) throw new Error("Invalid Kubernetes event response");
  return root.items.map((item) => ({
    type: typeof item?.type === "string" ? item.type : "Normal",
    reason: typeof item?.reason === "string" ? item.reason : "Event",
    message: typeof item?.message === "string" ? item.message : "",
    object: typeof item?.regarding?.name === "string" ? item.regarding.name : typeof item?.involvedObject?.name === "string" ? item.involvedObject.name : "",
    timestamp: typeof item?.eventTime === "string" ? item.eventTime : typeof item?.lastTimestamp === "string" ? item.lastTimestamp : typeof item?.metadata?.creationTimestamp === "string" ? item.metadata.creationTimestamp : ""
  })).sort((left, right) => right.timestamp.localeCompare(left.timestamp));
}

// Extensions/DevOps/kube-lens/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function Command() {
  const preferences = (0, import_api2.getPreferenceValues)();
  const [pods, setPods] = (0, import_react.useState)([]);
  const [events, setEvents] = (0, import_react.useState)([]);
  const [busy, setBusy] = (0, import_react.useState)(false);
  const { push } = (0, import_api2.useNavigation)();
  const refresh = async () => {
    setBusy(true);
    try {
      const [podData, eventData] = await Promise.all([
        run("kubectl", kubeLensArguments("pods", preferences.context, preferences.namespace)),
        run("kubectl", kubeLensArguments("events", preferences.context, preferences.namespace))
      ]);
      setPods(parsePods(podData));
      setEvents(parseEvents(eventData));
    } finally {
      setBusy(false);
    }
  };
  const detail = async (title, args) => {
    const text = await run("kubectl", args);
    push(/* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Detail, { markdown: `## ${title}

\`\`\`text
${text}
\`\`\`` }));
  };
  const warnings = events.filter((event) => event.type === "Warning");
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { isLoading: busy, searchBarPlaceholder: `Pods in ${preferences.namespace}`, children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Load cluster diagnostics", description: "Configure an exact Kubernetes context and namespace, then refresh.", actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: () => action(refresh) }) }) }),
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Section, { title: "Pods", children: pods.map((pod) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: pod.name, subtitle: pod.diagnostic, accessories: [{ text: pod.phase }, { text: pod.containers.join(", ") }], actions: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.ActionPanel, { children: [
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Show Logs", onAction: () => action(() => detail(`${pod.name} logs`, kubeLensArguments("logs", preferences.context, preferences.namespace, pod.name))) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Describe Pod", onAction: () => action(() => detail(`${pod.name} details`, kubeLensArguments("describe", preferences.context, preferences.namespace, pod.name))) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: () => action(refresh) })
    ] }) }, pod.name)) }),
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Section, { title: `Warning Events (${warnings.length})`, children: warnings.map((event, index) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: event.reason, subtitle: event.object, accessories: [{ text: event.timestamp }], detail: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item.Detail, { markdown: event.message }) }, `${event.timestamp}/${event.object}/${index}`)) }),
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: "Refresh diagnostics", actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: () => action(refresh) }) }) })
  ] });
}
