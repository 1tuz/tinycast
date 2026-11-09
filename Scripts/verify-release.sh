#!/bin/bash
# Release verification for a Developer ID-signed, notarized VoiceCast
# .app or released .dmg.
#
# Every check is a hard failure: this is the release gate run on macOS CI.
# --unnotarized skips the notarization-specific checks (stapler, spctl) for
# pre-notarization runs in CI; everything else still applies.
# Usage:
#   verify-release.sh app <path.app> [--version VERSION] [--unnotarized]
#   verify-release.sh dmg <path.dmg> [--version VERSION] [--unnotarized]
set -euo pipefail

MODE="${1:-}"
BUNDLE_ID="com.tinycast.app"
TEAM="J656U8XZ93"
UNNOTARIZED=0
# Authority names under a Developer ID Application cert vary; only the
# team is pinned. Any name is accepted as long as the team matches.
# codesign -dv prints each chain entry as "Authority=<name>".
AUTHORITY_RE="^Authority=Developer ID Application: .+ \\(${TEAM}\\)\$"
VERSION=""

usage() {

    cat >&2 <<'EOF'
Usage:
  verify-release.sh app <path.app> [--version VERSION] [--unnotarized]
  verify-release.sh dmg <path.dmg> [--version VERSION] [--unnotarized]
EOF
    exit 2
}

fail() {
    echo "::error::$1"
    exit 1
}

[ "$#" -ge 2 ] || usage
case "$MODE" in
    app|dmg) ;;
    *) usage ;;
esac
TARGET="$2"
shift 2

while [ "$#" -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --unnotarized) UNNOTARIZED=1; shift ;;
        *) echo "::error::unknown option: $1" >&2; usage ;;
    esac
done

# The gate requires Apple CLIs that only exist on macOS. A missing tool is
# a failure, never a skip. spctl/stapler are only needed for the
# notarization checks, which --unnotarized skips.
require_tool() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "required tool '$1' not found; release verification must run on macOS"
}
require_tool codesign
require_tool hdiutil
require_tool file
if [ "$UNNOTARIZED" -eq 0 ]; then
    require_tool spctl
    require_tool stapler
fi


MOUNTPOINT=""
DEVICE=""
cleanup() {
    # Detach by device, not by path: a failed verification may already have removed the
    # mountpoint, and path-based detach cannot resolve a mount whose directory is gone.
    if [ -n "$DEVICE" ]; then
        hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
    fi
    if [ -n "$MOUNTPOINT" ]; then
        rmdir "$MOUNTPOINT" 2>/dev/null || rm -rf "$MOUNTPOINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Enumerate every Mach-O under Contents: main executable, Helpers, Frameworks,
# PlugIns, XPCServices, and anything else that ships code.
machos_in_app() {
    local app="$1"
    local f
    while IFS= read -r -d '' f; do
        if file -b "$f" | grep -q "Mach-O"; then
            echo "$f"
        fi
    done < <(find "$app/Contents" -type f -print0)
    return 0
}

# Check a single Mach-O: deep-strict signature, Developer ID Application
# authority for our team, secure timestamp, hardened runtime, and no
# get-task-allow entitlement.
verify_macho() {
    local app="$1"
    local bin="$2"
    local rel="${bin#$app/}"

    [ -x "$bin" ] || fail "$rel is not executable"

    codesign --verify --deep --strict --verbose=2 "$bin" >/dev/null 2>&1 ||
        fail "$rel: codesign --verify --deep --strict failed"

    local details
    details="$(codesign -dv --verbose=4 "$bin" 2>&1 || true)"
    [ -n "$details" ] ||
        fail "$rel: codesign -dv failed"

    # Pin the team, never the name: certificates are reissued under
    # different names but the team identifier is stable.
    grep -Eq "$AUTHORITY_RE" <<<"$details" ||
        fail "$rel: no 'Developer ID Application: <name> (${TEAM})' authority found"
    grep -q "TeamIdentifier=${TEAM}" <<<"$details" ||
        fail "$rel: TeamIdentifier is not ${TEAM}"

    # Self-signed builds cannot carry a secure timestamp; its absence means
    # the artifact was not signed for distribution.
    grep -q "^Timestamp=" <<<"$details" ||
        fail "$rel: no secure timestamp in signature (unsigned or self-signed build)"

    # codesign -dv emits "CodeDirectory ... flags=0x10000(runtime) ..." mid-line.
    grep -Eq "flags=0x[0-9a-f]+\\([^)]*runtime" <<<"$details" ||
        fail "$rel: hardened runtime not enabled"

    if codesign -d --entitlements - --xml "$bin" 2>/dev/null |
        grep -q "com.apple.security.get-task-allow"; then
        fail "$rel: get-task-allow entitlement present"
    fi
}

verify_app() {
    local app="$1"
    local name
    name="$(basename "$app" .app)"

    [ -d "$app" ] || fail "$app is not an .app bundle"
    [ -d "$app/Contents" ] || fail "$app has no Contents directory"

    local main_exe="$app/Contents/MacOS/VoiceCast"
    [ -f "$main_exe" ] || fail "$name.app: missing Contents/MacOS/VoiceCast"
    [ -x "$main_exe" ] || fail "$name.app: Contents/MacOS/VoiceCast is not executable"

    codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1 ||
        fail "$name.app: codesign --verify --deep --strict failed"

    local info
    info="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$app/Contents/Info.plist" 2>/dev/null || true)"
    [ "$info" = "$BUNDLE_ID" ] ||
        fail "$name.app: CFBundleIdentifier is '$info', expected '$BUNDLE_ID'"

    if [ -n "$VERSION" ]; then
        local ver
        ver="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
            "$app/Contents/Info.plist" 2>/dev/null || true)"
        [ "$ver" = "$VERSION" ] ||
            fail "$name.app: CFBundleShortVersionString is '$ver', expected '$VERSION'"
    fi

    local bins
    bins="$(machos_in_app "$app")"
    [ -n "$bins" ] || fail "$name.app: no Mach-O binaries found under Contents"

    local bin
    while IFS= read -r bin; do
        verify_macho "$app" "$bin"
    done <<< "$bins"

    if [ "$UNNOTARIZED" -eq 0 ]; then
        # Notarization ticket must be stapled to the bundle.
        xcrun stapler validate "$app" >/dev/null 2>&1 ||
            fail "$name.app: stapler validate failed (no notarization ticket stapled)"

        # Gatekeeper must accept it as a notarized Developer ID app.
        local assess
        assess="$(spctl --assess --type execute --verbose=4 "$app" 2>&1 || true)"
        grep -q "source=Notarized Developer ID" <<<"$assess" ||
            fail "$name.app: spctl assessment is not 'source=Notarized Developer ID': $assess"
    fi

    echo "✓ $name.app passed release verification (team ${TEAM}, ${BUNDLE_ID})"
}

verify_dmg() {
    local dmg="$1"
    local base
    base="$(basename "$dmg" .dmg)"

    [ -f "$dmg" ] || fail "$dmg does not exist"

    if [ "$UNNOTARIZED" -eq 0 ]; then
        # Notarization ticket stapled to the image itself.
        xcrun stapler validate "$dmg" >/dev/null 2>&1 ||
            fail "$base.dmg: stapler validate failed (no notarization ticket stapled)"

        local assess
        assess="$(spctl --assess --type open \
            --context context:primary-signature --verbose=4 "$dmg" 2>&1 || true)"
        grep -q "accepted" <<<"$assess" ||
            fail "$base.dmg: spctl assessment rejected the image: $assess"
        grep -q "source=Notarized Developer ID" <<<"$assess" ||
            fail "$base.dmg: spctl assessment is not 'source=Notarized Developer ID': $assess"
    fi

    MOUNTPOINT="$(mktemp -d)"
    rmdir "$MOUNTPOINT"
    local attach_log
    attach_log="$(hdiutil attach "$dmg" -mountpoint "$MOUNTPOINT" -readonly -nobrowse 2>&1)" ||
        fail "$base.dmg: could not mount image: $attach_log"
    DEVICE="$(printf '%s\n' "$attach_log" | awk '/^\/dev\/disk/ { print $1; exit }')"
    [ -n "$DEVICE" ] || fail "$base.dmg: could not identify the mounted device"

    local app
    app="$(find "$MOUNTPOINT" -maxdepth 2 -name "*.app" -type d -print -quit 2>/dev/null || true)"
    [ -n "$app" ] || fail "$base.dmg: no .app bundle found in the image"

    verify_app "$app"

    hdiutil detach "$DEVICE" -quiet || fail "$base.dmg: failed to detach $DEVICE"
    DEVICE=""
    rm -rf "$MOUNTPOINT"
    MOUNTPOINT=""

    echo "✓ $base.dmg passed release verification (team ${TEAM}, ${BUNDLE_ID})"
}

case "$MODE" in
    app)
        [ "${TARGET%.app}" != "$TARGET" ] || fail "app mode requires a .app path"
        verify_app "$TARGET"
        ;;
    dmg)
        [ "${TARGET%.dmg}" != "$TARGET" ] || fail "dmg mode requires a .dmg path"
        verify_dmg "$TARGET"
        ;;
esac
