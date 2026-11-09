# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identities are in [signing.md](signing.md), and the CI signing and notarization
secrets runbook is in [voicecast-distribution.md](voicecast-distribution.md).

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh            # -> build/VoiceCast-local-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.5.7      # -> build/VoiceCast-local-0.5.7.dmg
```

It builds a Release `VoiceCast.app` signed with the local `Tinycast Self-Signed` identity and packs
it with an `/Applications` symlink. This is a **dev-only** artifact: a local build cannot be
Developer ID-signed or notarized — that happens only in CI with the team certificate — so never
distribute a `VoiceCast-local-*.dmg`. Official releases are built, signed and notarized by CI,
below.

## Signing & Gatekeeper

Public releases are signed with the **Developer ID Application** certificate for team
**`J656U8XZ93`** — `CODE_SIGN_STYLE=Manual`, `DEVELOPMENT_TEAM=J656U8XZ93`, hardened runtime, and
`OTHER_CODE_SIGN_FLAGS="--options runtime --timestamp"` — and **notarized by Apple**: CI submits
the build with `xcrun notarytool submit --wait` using an App Store Connect API key, requires
status `Accepted`, and staples the ticket to the `.app` and then the `.dmg`. A downloaded release
passes Gatekeeper on first launch — no warning and no confirmation step — and nothing in the
release or install path ever removes quarantine attributes or disables Gatekeeper. The six CI
secrets behind this, and how to produce each, are documented in
[signing.md](signing.md) and [voicecast-distribution.md](voicecast-distribution.md).

## How the in-app updater consumes a release

Every release publishes two assets from one build: `VoiceCast-<version>.dmg` and
`VoiceCast-<version>.zip`. `ReleaseFeed` selects **any `.dmg` asset**, so the in-app updater
installs the notarized DMG — the same file a hand downloader gets. The ZIP is an extra
artifact for tooling that prefers an archive; the updater does not depend on it.

Three things a release must keep true, or the updater skips it:

- **It carries a `.dmg` asset this Mac can run.** A release with no DMG is not installable and is
  not offered, and an Intel build is offered nothing rather than a thin arm64 DMG.
- **The tag parses as `vMAJOR.MINOR.PATCH` and is not marked prerelease.** Historical
  `-beta.N` tags sit in the list from the retired channel; a tag of any other shape is treated as
  mis-published and skipped.
- **It is not a draft.**

**There is no Homebrew cask.** VoiceCast installs from `Scripts/install.sh` or the release DMG, both
of which read the same release asset, so Homebrew never manages a copy and `brew upgrade` never
fights the in-app updater. See [features/updates.md](features/updates.md).

## Pull request review

No workflow runs on pull requests. CodeRabbit reviews every PR against `.coderabbit.yaml`: it runs SwiftLint
with `.swiftlint.yml`, annotates the diff and applies the pre-merge checks. It is a reviewer, not a
gate — it neither runs the harnesses nor builds the app, so the whole bar in
[testing.md](testing.md#definition-of-done) is run locally before a PR is opened.

## Releasing

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions, no local machine
needed. Run it from the **Actions** tab (`Release` → **Run workflow**) and pick:

- **version** — semver, e.g. `0.3.0`. One app, one bundle id (`com.tinycast.app`), alongside the
  local `VoiceCast Dev.app`.

Its first step is `Scripts/check-migrations.sh`: a migration that a stable release already shipped
stops the run until it is deleted ([migrations.md](migrations.md)). The check reads tags and history,
so the checkout fetches every commit without blobs.

It builds on a `macos-26` runner with Xcode 26, imports the team's Developer ID Application
certificate (team `J656U8XZ93`) from the `DEVELOPER_ID_APPLICATION_P12_BASE64` and
`DEVELOPER_ID_APPLICATION_P12_PASSWORD` secrets into an ephemeral keychain, signs with it under
the hardened runtime and a secure timestamp, then notarizes the packaged build with
`xcrun notarytool submit --wait` (App Store Connect API key: `APPSTORE_API_KEY_ID`,
`APPSTORE_ISSUER_ID`, `APPSTORE_API_PRIVATE_KEY_BASE64`, team `APPLE_TEAM_ID`), requires status
`Accepted`, and staples the ticket to the `.app` and then the `.dmg`. It publishes a GitHub
Release tagged `v<full-version>` with a versioned DMG and zip asset. The build pins `ARCHS=arm64`
and asserts the slice on every shipping Mach-O — the app and both helpers under
`Contents/Helpers`. Publishing is gated by two jobs on fresh macOS runners: **verify-install**
installs the DMG through a real Safari quarantine flag with Gatekeeper enabled and asserts the
seal, bundle id, hardened runtime, the Developer ID chain, the stapled ticket and `spctl`
acceptance; **verify-upgrade** installs the previous published release, upgrades it in place, and
proves the settings file and bundle id survive. If either fails — or any signing or notarization
secret is missing — nothing is published. See [voicecast-distribution.md](voicecast-distribution.md).

Builds override `TINYCAST_BUNDLE_IDENTIFIER`, not the target-wide `PRODUCT_BUNDLE_IDENTIFIER`.

### Release notes

`Scripts/release-notes.sh` composes the release body, and CI runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
TAG=v0.3.0 ./Scripts/release-notes.sh /tmp/body.md /tmp/discord.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its
author and number — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and
without Conventional Commits. **Nothing is ever committed to this repo**: the tag is created
server-side by `gh release create`, and no release, bot or version-bump commit exists.

Two details the script exists for:

- **The previous tag skips historical beta tags.** The release list carries old `-beta.N` tags;
  they never count as the previous release, so a new release spans everything since the last
  non-beta tag.
- **The body is split by `<!-- tinycast:install -->`.** Everything above it is the changelog;
  everything below is the installer and first-launch text, which only a download page needs. The
  update window cuts at that marker — see [features/updates.md](features/updates.md). Full PR
  URLs are shortened to `#304`, which still autolinks on the web and fits a 460pt window.
