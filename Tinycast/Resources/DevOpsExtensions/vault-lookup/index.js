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

// Extensions/DevOps/vault-lookup/src/index.tsx
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

// Extensions/DevOps/vault-lookup/src/vault.ts
function vaultArguments(path) {
  if (!path || path.startsWith("-") || /[\0\r\n]/.test(path)) throw new Error("Enter a Vault secret path");
  return ["kv", "get", "-format=json", path];
}
function vaultData(json) {
  let value;
  try {
    value = JSON.parse(json);
  } catch {
    throw new Error("Invalid Vault response");
  }
  const data = value?.data?.data ?? value?.data;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("Invalid Vault response");
  return data;
}
function parseVaultResponse(json, keyPath) {
  const keys = keyPath.split(".");
  if (keys.some((key) => !key || ["__proto__", "prototype", "constructor"].includes(key))) throw new Error("Selected field is unavailable");
  let value = vaultData(json);
  for (const key of keys) {
    if (!value || typeof value !== "object" || !Object.hasOwn(value, key)) throw new Error("Selected field is unavailable");
    value = value[key];
  }
  if (!["string", "number", "boolean"].includes(typeof value)) throw new Error("Select a scalar field");
  return String(value);
}
function vaultFields(json) {
  const result = [];
  function visit(value, prefix) {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      for (const key of Object.keys(value)) if (!key.includes(".") && !["__proto__", "prototype", "constructor"].includes(key)) visit(value[key], prefix ? `${prefix}.${key}` : key);
    } else if (["string", "number", "boolean"].includes(typeof value)) result.push(prefix);
  }
  visit(vaultData(json), "");
  return result;
}

// Extensions/DevOps/vault-lookup/src/index.tsx
var import_jsx_runtime = require("react/jsx-runtime");
function Command() {
  const [path, setPath] = (0, import_react.useState)("");
  const [fields, setFields] = (0, import_react.useState)([]);
  const [busy, setBusy] = (0, import_react.useState)(false);
  const load = async () => {
    setBusy(true);
    try {
      setFields(vaultFields(await run("vault", vaultArguments(path))));
    } finally {
      setBusy(false);
    }
  };
  const copy = async (field) => {
    let json = "";
    let value = "";
    try {
      json = await run("vault", vaultArguments(path));
      value = parseVaultResponse(json, field);
      await import_api2.Clipboard.copy(value, { concealed: true });
      await (0, import_api2.showToast)({ style: import_api2.Toast.Style.Success, title: "Secret copied" });
    } finally {
      json = "";
      value = "";
    }
  };
  return /* @__PURE__ */ (0, import_jsx_runtime.jsxs)(import_api2.List, { isLoading: busy, searchText: path, onSearchTextChange: (value) => {
    setPath(value);
    setFields([]);
  }, filtering: false, searchBarPlaceholder: "Vault secret path, for example kv/team/service", actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Load Field Names", onAction: () => action(load) }) }), children: [
    /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.EmptyView, { title: "Enter a Vault secret path", description: "Load field names, then copy a selected scalar. Values never appear in the list." }),
    fields.map((field) => /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.List.Item, { title: field, actions: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.ActionPanel, { children: /* @__PURE__ */ (0, import_jsx_runtime.jsx)(import_api2.Action, { title: "Copy Secret", onAction: () => action(() => copy(field)) }) }) }, field))
  ] });
}
