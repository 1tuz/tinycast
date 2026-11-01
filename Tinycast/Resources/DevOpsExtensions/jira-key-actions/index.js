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

// Extensions/DevOps/jira-key-actions/src/index.tsx
var index_exports = {};
__export(index_exports, {
  default: () => Command
});
module.exports = __toCommonJS(index_exports);
var import_react = require("react");
var import_api2 = require("@raycast/api");

// Extensions/DevOps/jira-key-actions/src/jira-key.ts
var issuePattern = /^[A-Z][A-Z0-9]+-[0-9]+$/;
function validateIssueKey(key) {
  if (!issuePattern.test(key)) throw new Error("Enter a Jira key such as DO-123");
  return key;
}
function parseIssueKey(text) {
  const keys = text.match(/(?<![A-Za-z0-9_-])[A-Z][A-Z0-9]+-[0-9]+(?![A-Za-z0-9_-])/g) ?? [];
  if (keys.length !== 1 || /[;`$\\]/.test(text)) return null;
  return keys[0];
}
function jiraIssueURL(baseURL, key) {
  validateIssueKey(key);
  const url = new URL(baseURL);
  if (!["https:", "http:"].includes(url.protocol) || url.username || url.password || url.search || url.hash) throw new Error("Configure an HTTP or HTTPS Jira base URL");
  return `${url.toString().replace(/\/+$/, "")}/browse/${key}`;
}

// Extensions/DevOps/shared.ts
var import_child_process = require("child_process");
var import_os = require("os");
var import_path = require("path");
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
function configuredRoots(value) {
  return value.split("\n").map((s) => s.trim()).filter(Boolean).map((s) => {
    const expanded = s === "~" ? (0, import_os.homedir)() : s.startsWith("~/") ? (0, import_path.resolve)((0, import_os.homedir)(), s.slice(2)) : s;
    if (!(0, import_path.isAbsolute)(expanded)) throw new Error("Project roots must be absolute paths");
    return (0, import_path.resolve)(expanded);
  });
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

// Extensions/DevOps/git-worktrees/src/worktrees.ts
var import_fs = require("fs");
var import_path2 = require("path");
function parseWorktrees(text) {
  return text.trim().split(/\n\n+/).filter(Boolean).map((block) => {
    const lines = block.split("\n");
    const path = lines.find((l) => l.startsWith("worktree "))?.slice(9) ?? "";
    if (!path || path.startsWith('"')) throw new Error("Unsupported Git worktree path encoding");
    return { path, branch: lines.find((l) => l.startsWith("branch "))?.slice(7).replace(/^refs\/heads\//, "") ?? "", detached: lines.includes("detached"), bare: lines.includes("bare"), dirty: false, ahead: 0, behind: 0 };
  });
}
function parseStatus(text) {
  const lines = text.trimEnd().split("\n");
  return { dirty: lines.slice(1).some(Boolean), ahead: Number(lines[0]?.match(/ahead (\d+)/)?.[1] ?? 0), behind: Number(lines[0]?.match(/behind (\d+)/)?.[1] ?? 0) };
}
async function discoverRepositories(roots) {
  const repos = [];
  for (const root of roots) {
    if ((0, import_fs.existsSync)((0, import_path2.join)(root, ".git"))) repos.push(root);
    for (const entry of (0, import_fs.readdirSync)(root, { withFileTypes: true })) {
      if (entry.isDirectory() && !entry.name.startsWith(".") && (0, import_fs.existsSync)((0, import_path2.join)(root, entry.name, ".git"))) repos.push((0, import_path2.join)(root, entry.name));
    }
  }
  return [...new Set(repos)];
}
async function listWorktrees(root) {
  const trees = parseWorktrees(await run("git", ["-C", root, "-c", "core.quotePath=false", "worktree", "list", "--porcelain"]));
  for (const tree of trees) if (!tree.bare) Object.assign(tree, parseStatus(await run("git", ["-C", tree.path, "status", "--porcelain=v1", "--branch"])));
  return trees;
}

// Extensions/DevOps/jira-key-actions/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function Command() {
  const [text, setText] = (0, import_react.useState)("");
  const prefs = (0, import_api2.getPreferenceValues)();
  const key = parseIssueKey(text);
  const local = async (mr) => {
    if (!key) return;
    for (const repo of await discoverRepositories(configuredRoots(prefs.projectRoots))) {
      const tree = (await listWorktrees(repo)).find((t) => t.branch === key || t.branch.endsWith(`/${key}`));
      if (tree) {
        if (mr) await run("glab", ["mr", "view", "--web"], tree.path);
        else await (0, import_api2.open)(tree.path);
        return;
      }
    }
    throw new Error("No worktree for this Jira key in configured roots");
  };
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { searchText: text, onSearchTextChange: setText, filtering: false, searchBarPlaceholder: "Enter or paste DO-123", actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Read Selected Text", onAction: () => action(async () => {
    try {
      const selected = await (0, import_api2.getSelectedText)();
      const parsed = parseIssueKey(selected);
      if (parsed) setText(parsed);
      else throw new Error();
    } catch {
      throw new Error("Selection unavailable. Enter a Jira key in the search field.");
    }
  }) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Enter a Jira key", description: "Use Read Selected Text with Accessibility permission, or type the key here." }),
    key && /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: key, subtitle: "Jira issue actions", actions: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.ActionPanel, { children: [
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Open Jira Issue", onAction: () => action(() => (0, import_api2.open)(jiraIssueURL(prefs.jiraURL, key))) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Copy Branch Name", onAction: () => action(() => import_api2.Clipboard.copy(key)) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Open Local Worktree", onAction: () => action(() => local(false)) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Open Merge Request", onAction: () => action(() => local(true)) })
    ] }) })
  ] });
}
