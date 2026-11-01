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

// Extensions/DevOps/ssh-hosts/src/index.tsx
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

// Extensions/DevOps/ssh-hosts/src/ssh-config.ts
var import_path = require("path");
var import_fs = require("fs");
var import_os = require("os");
var aliasPattern = /^[A-Za-z0-9][A-Za-z0-9_.-]*$/;
function parseSSHHostAliases(config) {
  const result = [];
  for (const line of config.split(/\r?\n/)) {
    const match = line.split("#", 1)[0].match(/^\s*Host(?:\s+|=)(.*)$/i);
    if (match) {
      for (const alias of match[1].split(/\s+/)) if (aliasPattern.test(alias)) result.push(alias);
    }
  }
  return [...new Set(result)];
}
function resolveSSHInclude(include, current, sshRoot) {
  const root = (0, import_path.resolve)(sshRoot);
  const expanded = include.startsWith("~/.ssh/") ? (0, import_path.resolve)(root, include.slice(7)) : include;
  const path = (0, import_path.resolve)((0, import_path.dirname)(current), expanded);
  const rel = (0, import_path.relative)(root, path);
  if (!rel || rel === ".." || rel.startsWith(`..${import_path.sep}`) || rel.startsWith(import_path.sep) || /[?*%~\0]/.test(include) || /^(id_|authorized_keys|known_hosts)/i.test((0, import_path.basename)(path)) || /\.(pem|key|pub)$/i.test(path)) throw new Error("SSH Include must reference a config file within ~/.ssh");
  return path;
}
function discoverSSHHostAliases(sshRoot, read) {
  const seen = /* @__PURE__ */ new Set();
  const aliases = [];
  function visit(path, depth) {
    if (seen.has(path)) return;
    if (depth > 16 || seen.size >= 128) throw new Error("SSH Include limit exceeded");
    seen.add(path);
    const config = read(path);
    if (config === void 0) return;
    if (config.length > 1024 * 1024 || /-----BEGIN .*PRIVATE KEY-----/.test(config)) throw new Error("SSH config is invalid");
    for (const line of config.split(/\r?\n/)) {
      const include = line.split("#", 1)[0].match(/^\s*Include(?:\s+|=)(.*)$/i);
      if (include) {
        for (const part of include[1].split(/\s+/).filter(Boolean)) visit(resolveSSHInclude(part, path, sshRoot), depth + 1);
      } else aliases.push(...parseSSHHostAliases(line));
    }
  }
  visit((0, import_path.resolve)(sshRoot, "config"), 0);
  return [...new Set(aliases)];
}
function readSSHHostAliases() {
  const root = (0, import_path.resolve)((0, import_os.homedir)(), ".ssh");
  return discoverSSHHostAliases(root, (path) => {
    if (!(0, import_fs.existsSync)(path)) return void 0;
    const actual = (0, import_fs.realpathSync)(path);
    const rel = (0, import_path.relative)(root, actual);
    if (rel.startsWith("..") || (0, import_fs.lstatSync)(path).isSymbolicLink() || !(0, import_fs.lstatSync)(path).isFile() || (0, import_fs.lstatSync)(path).size > 1024 * 1024) throw new Error("SSH Include must be a local config file within ~/.ssh");
    return (0, import_fs.readFileSync)(path, "utf8");
  });
}
function sshArguments(alias) {
  if (!aliasPattern.test(alias)) throw new Error("Choose a valid SSH host alias");
  return ["--", alias];
}
function sshConfigArguments(alias) {
  if (!aliasPattern.test(alias)) throw new Error("Choose a valid SSH host alias");
  return ["-G", alias];
}
function parseInventoryAliases(text) {
  const data = JSON.parse(text);
  const result = [];
  for (const [name, group] of Object.entries(data)) if (name !== "_meta" && group && typeof group === "object") {
    for (const host of group.hosts ?? []) if (typeof host === "string" && aliasPattern.test(host)) result.push(host);
  }
  return [...new Set(result)];
}

// Extensions/DevOps/ssh-hosts/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function sshConfigMarkdown(output) {
  let fence = "```";
  for (const match of output.matchAll(/`+/g)) if (match[0].length >= fence.length) fence = "`".repeat(match[0].length + 1);
  return `${fence}text
${output}
${fence}`;
}
function Command() {
  const [hosts, setHosts] = (0, import_react.useState)([]);
  const [busy, setBusy] = (0, import_react.useState)(false);
  const { push } = (0, import_api2.useNavigation)();
  const load = async () => {
    setBusy(true);
    try {
      const aliases = readSSHHostAliases();
      const inventory = (0, import_api2.getPreferenceValues)().inventoryPath;
      if (inventory) aliases.push(...parseInventoryAliases(await run("ansible-inventory", ["--inventory", inventory, "--list"])));
      setHosts([...new Set(aliases)]);
    } finally {
      setBusy(false);
    }
  };
  const showConfig = async (host) => {
    const output = await run("ssh", sshConfigArguments(host));
    push(/* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Detail, { markdown: sshConfigMarkdown(output) }));
  };
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { isLoading: busy, actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Load Host Aliases", onAction: () => action(load) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Load SSH host aliases", description: "Reads ~/.ssh/config and confined config includes. Optional Ansible inventory comes from preferences. Match commands are not evaluated during discovery." }),
    hosts.map((host) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: host, actions: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.ActionPanel, { children: [
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Show Effective Configuration", onAction: () => action(() => showConfig(host)) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Open SSH in Terminal", onAction: () => action(() => (0, import_api2.openTerminal)("ssh", sshArguments(host))) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: () => action(load) })
    ] }) }, host))
  ] });
}
