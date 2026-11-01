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

// Extensions/DevOps/git-worktrees/src/index.tsx
var index_exports = {};
__export(index_exports, {
  default: () => Command
});
module.exports = __toCommonJS(index_exports);
var import_react = require("react");
var import_api2 = require("@raycast/api");

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

// Extensions/DevOps/jira-key-actions/src/jira-key.ts
var issuePattern = /^[A-Z][A-Z0-9]+-[0-9]+$/;
function validateIssueKey(key) {
  if (!issuePattern.test(key)) throw new Error("Enter a Jira key such as DO-123");
  return key;
}

// Extensions/DevOps/git-worktrees/src/worktrees.ts
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
function createArguments(root, issueKey, collision) {
  validateIssueKey(issueKey);
  if (collision) throw new Error("Worktree path already exists");
  return ["-C", root, "worktree", "add", "-b", issueKey, "--", (0, import_path2.join)(root, ".worktrees", issueKey)];
}
function assertRemovable(state) {
  if (state.dirty) throw new Error("Worktree has local changes");
  if (!state.merged) throw new Error("Worktree branch is not merged into the configured base");
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
async function createWorktree(root, issueKey) {
  const target = (0, import_path2.join)(root, ".worktrees", validateIssueKey(issueKey));
  const args = createArguments(root, issueKey, (0, import_fs.existsSync)(target));
  const parent = (0, import_path2.join)(root, ".worktrees");
  if ((0, import_fs.existsSync)(parent) && (!(0, import_fs.lstatSync)(parent).isDirectory() || (0, import_fs.lstatSync)(parent).isSymbolicLink())) throw new Error("Worktree parent must be a local directory");
  (0, import_fs.mkdirSync)(parent, { recursive: true });
  await run("git", args);
  return (await listWorktrees(root)).find((t) => (0, import_fs.realpathSync)(t.path) === (0, import_fs.realpathSync)(target));
}
async function removalState(tree, base) {
  if (!/^[A-Za-z0-9][A-Za-z0-9_./-]*$/.test(base) || tree.detached || tree.bare || !tree.branch) throw new Error("Choose a branch worktree and configure its merge base");
  const status = parseStatus(await run("git", ["-C", tree.path, "status", "--porcelain=v1", "--branch"]));
  let merged = false;
  try {
    await run("git", ["-C", tree.path, "merge-base", "--is-ancestor", "--", tree.branch, base]);
    merged = true;
  } catch {
  }
  assertRemovable({ ...status, merged });
}

// Extensions/DevOps/git-worktrees/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function Create({ root, refresh }) {
  const { pop } = (0, import_api2.useNavigation)();
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.Form, { actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action.SubmitForm, { title: "Create Worktree", onSubmit: (values) => action(async () => {
    await createWorktree(root, String(values.issueKey));
    await refresh();
    pop();
  }) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Form.Description, { text: root }),
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Form.TextField, { id: "issueKey", title: "Jira Key", placeholder: "DO-123" })
  ] });
}
function Command() {
  const [trees, setTrees] = (0, import_react.useState)([]);
  const [busy, setBusy] = (0, import_react.useState)(false);
  const { push } = (0, import_api2.useNavigation)();
  const prefs = (0, import_api2.getPreferenceValues)();
  const refresh = async () => {
    setBusy(true);
    try {
      const repos = await discoverRepositories(configuredRoots(prefs.projectRoots));
      const result = [];
      for (const root of repos) result.push(...(await listWorktrees(root)).map((tree) => ({ ...tree, root })));
      setTrees(result);
    } finally {
      setBusy(false);
    }
  };
  const load = () => action(refresh);
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { isLoading: busy, searchBarPlaceholder: "Search worktrees", actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Load Configured Projects", onAction: load }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Load configured project roots", description: "Set allowed roots in extension preferences. Discovery checks roots and their direct children." }),
    trees.map((tree) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: tree.branch || "Detached HEAD", subtitle: tree.path, accessories: [{ text: `${tree.dirty ? "dirty" : "clean"} \u2191${tree.ahead} \u2193${tree.behind}` }], actions: /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.ActionPanel, { children: [
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Open Worktree", onAction: () => action(() => (0, import_api2.open)(tree.path)) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Create Worktree from Jira Key", onAction: () => push(/* @__PURE__ */ (0, import_jsx_runtime.jsx)(Create, { root: tree.root, refresh })) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Open Merge Request", onAction: () => action(() => run("glab", ["mr", "view", "--web"], tree.path)) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Remove Worktree", onAction: () => action(async () => {
        await removalState(tree, prefs.mergeBase);
        if (!await (0, import_api2.confirmAlert)({ title: "Remove worktree?", message: tree.path })) return;
        await removalState(tree, prefs.mergeBase);
        await run("git", ["-C", tree.root, "worktree", "remove", "--", tree.path]);
        await refresh();
      }) }),
      /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Refresh", onAction: load })
    ] }) }, tree.path))
  ] });
}
