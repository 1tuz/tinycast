# Bundled DevOps extensions

These seven local packages use installed CLIs. They do not install tools or change global Docker or Kubernetes contexts. Extension Store installs their compiled copies from app resources.

Build from any working directory:

```sh
node Scripts/raycast-runtime/build-devops-extensions.mjs
node Scripts/raycast-runtime/test-devops-extensions.mjs
```

The runtime package supplies esbuild. Each generated package contains `package.json` and `index.js`. React, `@raycast/api`, and Node builtins come from Tinycast's extension runtime.

Configure allowed project roots and Jira base URL in extension preferences. Git discovery checks each root and its direct child directories. It does not scan a default projects folder. Git removal checks for local changes and checks ancestry against the configured merge base before confirmation and again before removal.

Compose discovers running and stopped containers through Compose labels. Its selected Docker context stays inside the extension. Down and restart require confirmation. Down never passes volume removal options.

Helm requires an explicit context. Set exact production context names in the extension preferences. Rollback checks this list again when it builds the final argv. History and values load only when selected. Their output is not written to extension storage.

Vault loads field names into React state. Copy fetches the secret again, extracts one scalar, and calls `Clipboard.copy(value, { concealed: true })`. The host must mark this clipboard write with `ClipboardManager.internalType` and exclude it from Tinycast clipboard history. CLI failures use fixed messages and do not render stdout or stderr.

SSH reads Host aliases from `~/.ssh/config` and config includes confined to `~/.ssh`. It rejects wildcard includes, symlinks, known key filenames, key extensions, and excessive include depth or count. Discovery does not evaluate Match. The Show Effective Configuration action runs `ssh -G <alias>` on demand; OpenSSH can evaluate configured Match exec rules during that explicit action. An optional configured Ansible inventory supplies additional aliases. A selected connection calls the runtime export `openTerminal("ssh", ["--", alias])`.

KubeLens is read-only. It requires an exact context name and namespace, passes both explicitly to every `kubectl` call, and preserves EKS ARN context names. It lists pods, recent events, logs and describe output. It contains no restart or other mutating action.

The host must export `openTerminal(executable: string, args: string[]): Promise<void>` from `@raycast/api`. This forwards `system.openTerminal` with `[executable, args]`. The native implementation validates the executable and arguments and uses the existing Terminal launcher. It must preserve argument boundaries when it writes a command to Terminal.

Tests cover malformed manifests, missing bundles, output layout, parser fixtures, argument boundaries, path collisions, dirty worktrees, production rollback refusal, secret field selection, and confined SSH includes. Git integration uses temporary repositories. No cluster, Docker daemon, Jira server, or Vault service is required.
