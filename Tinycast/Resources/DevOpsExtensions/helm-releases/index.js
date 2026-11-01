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

// Extensions/DevOps/helm-releases/src/index.tsx
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
function required(value, name) {
  if (!value || /[\0\r\n]/.test(value)) throw new Error(`Configure ${name}`);
  return value;
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

// Extensions/DevOps/helm-releases/src/helm.ts
function parseHelmReleases(text) {
  const data = JSON.parse(text);
  if (!Array.isArray(data)) throw new Error("Invalid Helm release list");
  return data.map((row) => {
    if (typeof row.name !== "string" || !row.name || row.name.startsWith("-") || typeof row.namespace !== "string" || !row.namespace || !Number.isInteger(Number(row.revision)) || Number(row.revision) < 1) throw new Error("Invalid Helm release");
    return { name: row.name, namespace: row.namespace, revision: Number(row.revision), status: String(row.status ?? "unknown") };
  });
}
function helmArguments(action2, release, context, production2 = [], revision) {
  required(context, "Kubernetes context");
  if (!/^[a-z0-9][a-z0-9.-]*$/.test(release.name)) throw new Error("Invalid Helm release name");
  let args;
  switch (action2) {
    case "history":
      args = ["history", release.name, "--output", "json"];
      break;
    case "values":
      args = ["get", "values", release.name, "--output", "yaml"];
      break;
    case "rollback":
      if (production2.includes(context)) throw new Error("Rollback is blocked for production contexts");
      if (!Number.isInteger(revision) || revision < 1 || revision >= release.revision) throw new Error("Select an earlier positive revision");
      args = ["rollback", release.name, String(revision)];
      break;
    default:
      throw new Error("Unsupported Helm action");
  }
  return [...args, "--namespace", required(release.namespace, "namespace"), "--kube-context", context];
}

// Extensions/DevOps/helm-releases/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function production() {
  return (0, import_api2.getPreferenceValues)().productionContexts.split("\n").map((s) => s.trim()).filter(Boolean);
}
function Rollback({ release, context, refresh }) {
  const { pop } = (0, import_api2.useNavigation)();
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.Form, { actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action.SubmitForm, { title: "Rollback Release", onSubmit: (values) => action(async () => {
    const revision = Number(values.revision);
    helmArguments("rollback", release, context, production(), revision);
    if (!await (0, import_api2.confirmAlert)({ title: "Rollback Helm release?", message: `${release.name} \xB7 ${context} \xB7 revision ${revision}` })) return;
    await run("helm", helmArguments("rollback", release, context, production(), revision));
    await refresh();
    pop();
  }) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Form.Description, { text: `${release.namespace}/${release.name} \xB7 ${context}` }),
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Form.TextField, { id: "revision", title: "Target Revision" })
  ] });
}
function Command() {
  const context = (0, import_api2.getPreferenceValues)().kubeContext;
  const [releases, setReleases] = (0, import_react.useState)([]);
  const [busy, setBusy] = (0, import_react.useState)(false);
  const { push } = (0, import_api2.useNavigation)();
  const refresh = async () => {
    setBusy(true);
    try {
      setReleases(parseHelmReleases(await run("helm", ["list", "--all-namespaces", "--output", "json", "--kube-context", required(context, "Kubernetes context")])));
    } finally {
      setBusy(false);
    }
  };
  const detail = async (name, release) => {
    const value = await run("helm", helmArguments(name, release, context));
    push(/* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Detail, { markdown: `\`\`\`
${value}
\`\`\`` }));
  };
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { isLoading: busy, actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Load Releases", onAction: () => action(refresh) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Load Helm releases", description: "Configure an explicit Kubernetes context and production context names in preferences." }),
    releases.map((release) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: release.name, subtitle: release.namespace, accessories: [{ text: `${release.status} \xB7 revision ${release.revision}` }], actions: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.ActionPanel, { children: [
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Show History", onAction: () => action(() => detail("history", release)) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Show Values", onAction: () => action(() => detail("values", release)) }),
      !production().includes(context) && /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Rollback", onAction: () => push(/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Rollback, { release, context, refresh })) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: () => action(refresh) })
    ] }) }, `${release.namespace}/${release.name}`))
  ] });
}
