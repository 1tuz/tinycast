# .1tuz

Everything that makes this fork differ from [abue-ammar/tinycast](https://github.com/abue-ammar/tinycast).
`main` uses the upstream `main` tree plus these patches. Each sync commit keeps the previous fork `main` as its first parent, so publishing is a normal fast-forward push.

| File | What it does |
| --- | --- |
| `patches/0008-fork-updater.patch` | In-app updater and About link to `1tuz/tinycast` |
| `patches/0009-disable-support-reminders.patch` | Disables automatic Support reminders |
| `patches/0012-remove-website-link.patch` | Removes the upstream Website link from About |
| `patches/0013-curl-installer.patch` | Adds the one-line local installer and guide |
| `patches/0014-release-notes-install-guide.patch` | Uses the local install guide in generated release notes |
| `patches/0016-fork-readme-install-guide.patch` | Replaces upstream website and package-manager install text in README |
| `patches/0017-roadmap-features.patch` | Carries local roadmap features and removes Dictation/microphone capture |
| `apply.sh` | Applies patches, removes website source and publishing workflows, rewrites release links, regenerates the XcodeGen project |
| `gate.sh` | Checks that voice input and microphone capture are absent, then runs a Release build and focused harnesses |
| `UPSTREAM` | Upstream commit SHA used for the last rebuild |

## Automation

- `fork-sync.yml` checks upstream `main` daily and on manual dispatch. It rebuilds the fork from upstream plus `.1tuz/patches`, preserves this fork's workflows, runs `gate.sh`, then pushes `main` as a fast-forward merge of the previous fork tree and upstream. Failed gates do not publish a new tree.
- GitHub Actions uses its built-in `GITHUB_TOKEN`; no extra push token is needed. The fork does not contain the website source or publishing workflow.
- `INSTALL.md` documents the one-line source installer. It needs Xcode 26 or 27 and a persistent code-signing identity. GitHub Releases must use that same identity for in-app updates.
- `release.yml` is manual. Release signing needs `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` for the same stable identity.
