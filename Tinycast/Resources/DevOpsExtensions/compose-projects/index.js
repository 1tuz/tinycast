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

// Extensions/DevOps/compose-projects/src/index.tsx
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

// Extensions/DevOps/compose-projects/src/compose.ts
function parseComposeProjects(text) {
  const rows = text.trim().startsWith("[") ? JSON.parse(text) : text.trim().split("\n").filter(Boolean).map((line) => JSON.parse(line));
  if (!Array.isArray(rows)) throw new Error("Invalid Compose project list");
  const result = /* @__PURE__ */ new Map();
  for (const row of rows) {
    const rawLabels = row.Config?.Labels ?? row.Labels;
    const labels = typeof rawLabels === "string" ? Object.fromEntries(rawLabels.split(",").map((part) => {
      const i = part.indexOf("=");
      return [part.slice(0, i), part.slice(i + 1)];
    })) : rawLabels ?? {};
    const name = labels["com.docker.compose.project"];
    const directory = labels["com.docker.compose.project.working_dir"];
    if (typeof name !== "string" || typeof directory !== "string" || !directory.startsWith("/")) continue;
    const files = typeof labels["com.docker.compose.project.config_files"] === "string" ? labels["com.docker.compose.project.config_files"].split(",") : void 0;
    result.set(name, { name, directory, files, status: typeof row.State === "string" ? row.State : row.State?.Status });
  }
  return [...result.values()];
}
function composeArguments(action2, context, project) {
  if (!["up", "down", "restart"].includes(action2)) throw new Error("Unsupported Compose action");
  const args = ["--context", required(context, "Docker context"), "compose", "--project-directory", required(project.directory, "project directory"), "--project-name", required(project.name, "project name")];
  for (const file of project.files ?? []) args.push("--file", required(file, "Compose config file"));
  return [...args, action2, ...action2 === "up" ? ["--detach"] : []];
}

// Extensions/DevOps/compose-projects/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function Command() {
  const prefs = (0, import_api2.getPreferenceValues)();
  const [context, setContext] = (0, import_react.useState)(prefs.dockerContext || "default");
  const [contexts, setContexts] = (0, import_react.useState)([context]);
  const [projects, setProjects] = (0, import_react.useState)([]);
  const [busy, setBusy] = (0, import_react.useState)(false);
  const refresh = async () => {
    setBusy(true);
    try {
      const rows = await run("docker", ["context", "ls", "--format", "{{.Name}}"]);
      setContexts(rows.trim().split("\n").filter(Boolean));
      const ids = (await run("docker", ["--context", context, "ps", "--all", "--filter", "label=com.docker.compose.project", "--format", "{{.ID}}"])).trim().split("\n").filter(Boolean);
      if (ids.length > 200) throw new Error("Too many Compose containers; narrow the Docker context");
      setProjects(ids.length ? parseComposeProjects(await run("docker", ["--context", context, "inspect", ...ids])) : []);
    } finally {
      setBusy(false);
    }
  };
  const mutate = async (name, project) => {
    if (name !== "up" && !await (0, import_api2.confirmAlert)({ title: `${name} Compose project?`, message: `${project.name} \xB7 ${context}` })) return;
    await run("docker", composeArguments(name, context, project));
    await refresh();
  };
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { isLoading: busy, searchBarAccessory: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Dropdown, { tooltip: "Docker Context", value: context, onChange: (value) => {
    setContext(value);
    setProjects([]);
  }, children: contexts.map((c) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Dropdown.Item, { title: c, value: c }, c)) }), actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Load Projects and Contexts", onAction: () => action(refresh) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Load Compose projects", description: "Projects come from container Compose labels. The selected Docker context stays local to Tinycast." }),
    projects.map((project) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: project.name, subtitle: project.directory, accessories: [{ text: project.status ?? "" }], actions: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.ActionPanel, { children: [
      ["up", "down", "restart"].map((name) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: `${name[0].toUpperCase() + name.slice(1)} Project`, onAction: () => action(() => mutate(name, project)) }, name)),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: () => action(refresh) })
    ] }) }, project.name))
  ] });
}
