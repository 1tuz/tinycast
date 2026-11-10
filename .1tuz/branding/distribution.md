# VoiceCast distribution runbook

This is the authoritative guide for public VoiceCast releases. The local
development identity is in [signing.md](signing.md); the general release flow
is in [release.md](release.md).

VoiceCast ships **Developer ID-signed and notarized**. Releases are signed
with the team's **Developer ID Application** certificate for team
**`J656U8XZ93`** (bundle id `com.tinycast.app`), built
with the hardened runtime and a secure timestamp, notarized by Apple, and
verified by `Scripts/verify-release.sh`. A downloaded release passes Gatekeeper on first launch:
no warning and no confirmation step.

The public installer always verifies before copying: a Developer ID app that
fails the team check, the stapled ticket or `spctl` aborts the install, and
Gatekeeper itself stays enabled system-wide. The published one-liner passes
`VOICECAST_STRIP_QUARANTINE=1`, which clears the quarantine flag on the copy it
has just installed after that verification — a fallback so a blocked download
still launches. `spctl --master-disable` never appears anywhere in the
repository, and the release pipeline (`release.yml`, `build-dmg.sh`,
`release-notes.sh`) never strips a quarantine attribute.

A local, self-signed DMG (see [signing.md](signing.md)) can never satisfy
Gatekeeper. For that build only, `Scripts/install.sh` prints a warning and
clears the quarantine flag on the copy it has just installed, so testing a
local build also needs no manual `xattr` command.

When the newest stable release carries no `VoiceCast-*.dmg`, the installer
falls back to the newest published build that does — a pre-release — and says
so before downloading. The same verification runs, so a pre-release signed
with the local identity installs only through the guarded fallback above.

The release workflow (`.github/workflows/release.yml`) is manually triggered
and **fails before publishing anything** when any of the six secrets is
missing or when the verification fails. Every publish is gated by two jobs on
fresh macOS runners: `verify-install` stamps a real Safari quarantine flag on
the DMG, leaves Gatekeeper enabled, installs the copy and asserts the seal,
bundle id, hardened runtime, the Developer ID chain, the stapled ticket and
`spctl` acceptance; `verify-upgrade` installs the previous published release,
upgrades it in place through `Scripts/install.sh`, and proves the settings file
and bundle id survive and the old `Tinycast.app` is gone.

## GitHub Actions secrets

Configure these six repository Actions secrets in `1tuz/tinycast`
(**Settings → Secrets and variables → Actions**):

| Secret | Value |
|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of the `.p12` export of the **Developer ID Application** certificate (team `J656U8XZ93`) **including its private key** |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used to export the `.p12` |
| `APPLE_TEAM_ID` | `J656U8XZ93` |
| `APPSTORE_API_KEY_ID` | App Store Connect API key ID, used by `notarytool` |
| `APPSTORE_ISSUER_ID` | App Store Connect API key issuer ID |
| `APPSTORE_API_PRIVATE_KEY_BASE64` | Base64 of the API key's `.p8` private key |

If any is missing, the workflow fails before publishing. There is no
fallback to an unsigned, ad-hoc or non-notarized build.

How to produce each value is documented in
[signing.md](signing.md) §2: export the Developer ID `.p12` from Keychain
Access and base64 it; create a **Team API key** with Developer access in
App Store Connect (**Users and Access → Integrations**), whose `.p8` is a
one-time download, and base64 that. No secret value ever enters the repo or
a log — only the names. A leaked value must be revoked and rotated
(re-issue the certificate or key, re-export, and update the secrets).

## What the workflow does with them

After importing the `.p12` into an ephemeral keychain that it deletes
afterwards, the workflow signs the app and every embedded executable with
the Developer ID Application certificate — `CODE_SIGN_STYLE=Manual`,
`DEVELOPMENT_TEAM=J656U8XZ93`, hardened runtime, and
`OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp"` — creates the ZIP
and DMG, submits the build to Apple's notary service with
`xcrun notarytool submit --wait` using the App Store Connect API key,
requires status `Accepted`, staples the ticket to the `.app` and then to
the `.dmg`, runs `Scripts/verify-release.sh` on both, runs the
`verify-install` job on a fresh runner, and only then publishes.

## Validation commands

On macOS, inspect a packaged release:

```sh
# .app — signature is intact and deep-verifies
codesign --verify --deep --strict --verbose=2 /Applications/VoiceCast.app

# .app — the Developer ID Application chain and TeamIdentifier J656U8XZ93
codesign -dv --verbose=4 /Applications/VoiceCast.app 2>&1 | grep -E 'Authority|TeamIdentifier|Timestamp'

# .app — flags include the hardened runtime, and no get-task-allow
codesign -dv --verbose=4 /Applications/VoiceCast.app 2>&1 | grep -E 'flags|get-task'

# .app — Gatekeeper accepts it
spctl -a -vvv -t exec /Applications/VoiceCast.app

# .app — the notarization ticket is stapled and validates offline
xcrun stapler validate /Applications/VoiceCast.app
```

Expected results: `Authority=Developer ID Application: … (J656U8XZ93)`,
`TeamIdentifier=J656U8XZ93`, a `Timestamp` line, a `flags` line containing
`runtime`, no `get-task-allow`, `spctl` reporting
`accepted\nsource=Notarized Developer ID`, and `stapler` reporting
`The validate action worked!`. `Scripts/verify-release.sh app <path.app>`
and `Scripts/verify-release.sh dmg <path.dmg>` run all of this — plus the
bundle id, the version, the embedded helper executables under
`Contents/Helpers`, and a read-only DMG mount — in one command, and fail
the release on any mismatch.

## Clean-Mac manual install checklist

Do this on a Mac with no prior Tinycast/VoiceCast install:

1. Download `VoiceCast-<version>.dmg` from GitHub Releases.
2. Open (mount) the DMG and drag VoiceCast to `/Applications`.
3. Eject the DMG, then launch VoiceCast from `/Applications` normally —
   it opens straight away. Gatekeeper accepts the notarized, stapled,
   Developer ID-signed build; no confirmation dialog is expected.
4. VoiceCast launches normally on every launch.

`Scripts/install.sh` is the same path scripted: download, verify, install.
Disabling Gatekeeper globally — `spctl --master-disable` — must never happen
and must never be recommended. Deleting quarantine attributes by hand is
never needed: the published command clears the flag on the installed copy as
part of the install, and the installer handles local self-signed builds on its
own, as described above.

## Updating from an old pre-switch Tinycast

- **The bundle id stays `com.tinycast.app`.** The new VoiceCast build is the
  same app to macOS and to the updater, so no re-activation or migration step
  is needed.
- **Settings survive.** Preferences and application-support data live under
  the unchanged bundle id, so an existing user's configuration carries over
  into VoiceCast.
- **The old app accepts the new release.** `BundleSignature` checks the
  Developer ID branch first: the designated requirement pinned to team
  `J656U8XZ93`, which every new release satisfies. The last pre-switch release
  already shipped that branch, so its in-app updater accepts the Developer ID
  build. The leaf fallback below it accepts a bundle signed with the running
  app's own leaf — local self-signed builds — and is not what admits the new
  release. Do not remove either check. An in-app update keeps the old
  `Tinycast.app` folder name in `/Applications` (the app inside is VoiceCast);
  `Scripts/install.sh` installs it as `VoiceCast.app` and removes the old
  folder.
- **TCC.** A pre-switch copy re-prompts where the signing path changed; the
  bundle id stays `com.tinycast.app`, so preferences, caches and the login
  item carry over untouched.

The CI `verify-install` job runs the clean-Mac path on a fresh macOS
runner — quarantine the DMG, mount, verify, install — including the Developer
ID, ticket and `spctl` assertions, and `verify-upgrade` proves the in-place
upgrade from the previous release. A physical Mac with no prior install is
still worth one manual pass per major macOS release; the checklist above is
the script for it.

## Rebranding facts

- The app product is named VoiceCast, but the bundle id remains
  `com.tinycast.app` (deliberate, for update compatibility).
- Two helper executables ship inside `Contents/Helpers`:
  `ClipboardTextHelper` and `FileIndexHelper`. Both are signed with the
  Developer ID Application certificate and carry the hardened runtime
  exactly like the main executable.
- Assets published per release: `VoiceCast-<version>.dmg` (the notarized
  installer the updater and hand downloaders use) and
  `VoiceCast-<version>.zip` (an extra artifact). See [release.md](release.md).
