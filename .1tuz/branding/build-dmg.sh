#!/bin/bash
# Developer-only LOCAL DMG for testing on your own machines.
# Signed with the "Tinycast Self-Signed" identity — NOT distributable.
# Public releases are built by GitHub Actions (release.yml) with a Developer ID
# Application certificate (team J656U8XZ93), notarized by Apple, and stapled.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
IDENTITY="Tinycast Self-Signed"
DERIVED="build/DerivedData"

if ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "✗ '$IDENTITY' identity not found (docs/signing.md)." >&2
    exit 1
fi

echo "▸ Building VoiceCast.app (self-signed, developer-only)…"
# Hardened runtime on so the local build matches the shipped target; no
# --timestamp (self-signed identities cannot use a secure timestamp).
xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    ${1:+MARKETING_VERSION="$1"} \
    build

APP="$DERIVED/Build/Products/Release/VoiceCast.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/VoiceCast-local-${VERSION}.dmg"

mkdir -p build
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
diskutil image create from "$STAGE" --format UDZO --volumeName "VoiceCast Local" "$DMG" >/dev/null

echo "✓ $DMG (developer-only local build: self-signed, not notarized, NOT distributable — public releases are Developer ID-signed and notarized in CI)"
