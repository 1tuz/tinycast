# Signing

SpeechCast uses two signing identities, one per audience:

- **Local development** signs with the persistent self-signed identity **`Tinycast Self-Signed`**
  (`project.yml`). Keeping the same identity on every local build is what makes macOS remember the
  Accessibility grant across rebuilds — ad-hoc signing changes every build and macOS forgets the
  grant. A contributor cannot sign with Developer ID: that certificate and its private key belong
  to the release maintainer's team keychain and are never shared.
- **Public releases** sign with a **Developer ID Application** certificate for team **`J656U8XZ93`**
  and are **notarized by Apple**. CI (`release.yml`) imports the certificate from repository
  secrets, signs with the hardened runtime and a secure timestamp, submits the build to Apple's
  notary service, waits for `Accepted`, and staples the ticket to the `.app` and then the `.dmg`.
  A downloaded release passes Gatekeeper on first launch with no warning and no confirmation
  step. The CI setup — the six secrets and how to produce each — is §2 below; the runbook is in
  [speechcast-distribution.md](speechcast-distribution.md).

The two identities coexist on purpose: the product is one app with one bundle id
(`com.tinycast.app`), and the updater trusts a release through the Developer ID requirement pinned
in `BundleSignature`. The last pre-switch release already carries that branch, so its updater
accepts the Developer ID build; the leaf fallback only keeps locally signed builds updatable. See
§3.

## 1. Create the `Tinycast Self-Signed` identity (once, per machine)

Only needed for local development — a new contributor's builds. Run these in a terminal. They
generate a self-signed code-signing certificate and import it into your login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Tinycast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Tinycast Self-Signed" -out /tmp/tc.p12 -passout pass:tinycast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P tinycast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Tinycast Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`, `Scripts/build-dmg.sh`) sign with it, and you
grant Accessibility once. A contributor's locally created identity is their own and is never
exported or shared: public releases are signed in CI with the team's Developer ID certificate,
never with whatever `Tinycast Self-Signed` leaf happens to be on a contributor's machine.
`build-dmg.sh` output is dev-only — never distribute it; only the CI build is notarized.

## 2. CI signing and notarization secrets

The release workflow signs with the **Developer ID Application** certificate and notarizes with an
**App Store Connect API key**. That needs six repository secrets, configured in `1tuz/tinycast`
(**Settings → Secrets and variables → Actions**). If any is missing, the workflow fails before
publishing anything.

| Secret | Value | How to produce it |
|---|---|---|
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of the `.p12` export of the **Developer ID Application** certificate for team `J656U8XZ93`, including its private key | Export from Keychain Access on the Mac holding it — see below — then `base64 -i DeveloperIDApplication.p12 \| tr -d '\n'` |
| `DEVELOPER_ID_APPLICATION_P12_PASSWORD` | Password used to export that `.p12` | The password you chose in the export dialog |
| `APPLE_TEAM_ID` | `J656U8XZ93` | Your Apple Developer team's Team ID |
| `APPSTORE_API_KEY_ID` | The App Store Connect API key's ID | App Store Connect → Users and Access → **Integrations** → Team API key |
| `APPSTORE_ISSUER_ID` | The issuer UUID of that key | Same page, shown beside the key |
| `APPSTORE_API_PRIVATE_KEY_BASE64` | Base64 of the key's `.p8` file | The **one-time download** offered when the key is created |

Export the Developer ID `.p12` from the Keychain on the Mac holding the team identity:

1. Open **Keychain Access**, select the login keychain, and select the
   **Developer ID Application: … (J656U8XZ93)** certificate — expand it and select it together with
   its **private key**.
2. **File → Export Items**, format **Personal Information Exchange (.p12)**, choose a password,
   save as `DeveloperIDApplication.p12`. If Keychain Access offers no `.p12` format, the private
   key is missing or not exportable and that Mac cannot sign releases.
3. Base64 it and set the secret (same result via `gh secret set … --repo 1tuz/tinycast`):

```sh
base64 -i DeveloperIDApplication.p12 | tr -d '\n'   # -> DEVELOPER_ID_APPLICATION_P12_BASE64
```

For the notary API key: in App Store Connect, **Users and Access → Integrations**, create a
**Team API key** with at least **Developer** access. Apple shows the key ID and issuer ID on the
page, and offers the `.p8` private key as a **one-time download** — it cannot be re-downloaded, so
store it somewhere safe, then base64 it for the secret. If it is lost, revoke the key and create a
new one, and update both key secrets.

Every one of these values is a **secret**: never commit it, store it in artifacts, or print it to
CI logs — only the secret *names* may appear in logs. A leaked value must be revoked and rotated:
re-issue the certificate or API key, re-export, and update the secrets. The workflow imports the
`.p12` into an ephemeral keychain and deletes both the keychain and the `.p8` in an `always()`
cleanup step, and passes the API key to `xcrun notarytool` as a `chmod 600` file path — the key
material itself never appears on a command line or in a log.

## 3. BundleSignature and update compatibility

The updater compares signatures before it installs, and `BundleSignature` keeps two accepted
branches:

- the **Developer ID branch** — the designated requirement pinned to the team, `certificate
  leaf[subject.OU] = "J656U8XZ93"` plus the Developer ID and code-signing extension markers. The
  requirement matches the **team, not the certificate**, so a leaf reissued on renewal still
  satisfies it. This is the path every release takes now.
- the **leaf fallback**, which accepts a bundle signed with the running app's own leaf
  certificate. That is what keeps a locally self-signed development build updatable from another
  build of the same `Tinycast Self-Signed` identity. It does **not** admit a Developer ID release
  into a copy whose code predates the Developer ID branch; such a copy can only move to SpeechCast
  through `Scripts/install.sh`. Do not remove it.

Do not remove either check.

The release build signs with `CODE_SIGN_STYLE=Manual`,
`DEVELOPMENT_TEAM=J656U8XZ93`, `ENABLE_HARDENED_RUNTIME=YES` and
`OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp"`, then notarizes:

```sh
xcrun notarytool submit SpeechCast-<version>.dmg \
  --key AuthKey_<key-id>.p8 --key-id <key-id> --issuer <issuer-id> --wait
xcrun stapler staple SpeechCast.app
xcrun stapler staple SpeechCast-<version>.dmg
```

The submission must come back with status `Accepted`; anything else fails the release. The ticket
is stapled to the `.app` first, then to the `.dmg`, so Gatekeeper can validate a download offline.

`project.yml` keeps signing with `Tinycast Self-Signed`, so local development is unchanged — a
contributor keeps building with the one they created in §1. CI overrides the signing settings for
the release build only.

## Hardened runtime

**Release only**, on both targets: `ENABLE_HARDENED_RUNTIME: YES`, which the release
verification asserts on every executable. Debug must stay without it — hardened runtime turns
on library validation, and Xcode's `SpeechCast Dev.debug.dylib` is refused at launch because
the local identity carries no Team ID for the loader to match. The flag is not part of the
designated requirement, so turning it on costs no Accessibility grant. Each entitlement in
`Tinycast/Tinycast.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.cs.allow-jit` | JavaScriptCore cannot JIT, and every extension command runs on the interpreter |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info, the Finder selection an extension reads, and the System Events–driven system actions all die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |
| `com.apple.security.personal-information.calendars` | `requestFullAccessToEvents()` returns `false` in milliseconds with no dialog, and Tinycast never appears under System Settings › Calendars |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `Scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources Tinycast does not use. That grants nothing — only
`Tinycast.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

## Verification scripts

`./Scripts/verify-signature.sh <path-to-.app>` asserts the local side of all of this — the runtime
flag on the app *and* on `Contents/Helpers/ClipboardTextHelper` and `Contents/Helpers/FileIndexHelper`,
an intact nested seal, no `get-task-allow`, and an entitlement for every usage string `Info.plist`
declares. The release jobs run it before packaging: a nested binary missing the runtime flag fails
release verification, and a usage string missing its entitlement ships a permission that can never be
granted.

`Scripts/verify-release.sh app <path.app> [--version VERSION]` and
`Scripts/verify-release.sh dmg <path.dmg> [--version VERSION]` are the release gate — on top of the
structural checks they assert the Developer ID chain for team `J656U8XZ93`, the stapled notarization
ticket, and `spctl` Gatekeeper acceptance. Exit nonzero on any failure, printing `::error::<message>`
for GitHub Actions.
