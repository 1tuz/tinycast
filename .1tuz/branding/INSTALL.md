# Install VoiceCast

VoiceCast requires macOS 26 or later on Apple silicon.

## Install a verified release

```sh
curl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | /bin/bash
```

The installer fetches the newest stable `VoiceCast-*.dmg` from
[`1tuz/tinycast` Releases](https://github.com/1tuz/tinycast/releases), verifies that it is signed
with the **Developer ID Application** certificate for team `J656U8XZ93` (bundle id
`com.tinycast.app`, hardened runtime), carries a stapled notarization ticket, and passes
`spctl` Gatekeeper assessment — then places `VoiceCast.app` in `/Applications` or
`~/Applications`. For a published release nothing is stripped and Gatekeeper stays on; it also
requests no root access and needs no Xcode.
VoiceCast is **Developer ID-signed and notarized by Apple**: a downloaded release passes Gatekeeper
on first launch with no warning and no confirmation step. Drag it out of the DMG (or run the
installer above) and open it normally.

Existing `/Applications/Tinycast.app` installations are migrated to
`/Applications/VoiceCast.app` when writable. The bundle identifier remains
`com.tinycast.app`, preserving existing app data, permissions and update compatibility: the last
pre-switch release already carries the same `BundleSignature` Developer ID check, so its in-app
updater accepts the new build, and the installer migrates an old `Tinycast.app` in place with its
settings intact.

## Source builds

The original `Tinycast.xcodeproj` and scheme intentionally retain their names to
simplify upstream merges. Build using Xcode 26/27 with a local code-signing identity:

```sh
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  -derivedDataPath build/DerivedData build
```

The resulting local `VoiceCast.app` is for development: contributors build with the local
`Tinycast Self-Signed` identity, which cannot be Developer ID-signed or notarized —
only the CI build is. Installing such a DMG needs no manual step either: run
`Scripts/install.sh` with `VOICECAST_DMG=<path.dmg>` and it warns that the build is not a
Developer ID build, then clears the quarantine flag on the copy it installs. Gatekeeper itself
stays enabled. See [docs/signing.md](docs/signing.md) for the local signing identity and
[docs/voicecast-distribution.md](docs/voicecast-distribution.md) for GitHub Releases.
