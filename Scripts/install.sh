#!/bin/bash
# VoiceCast: install the latest GitHub Release.
# Published releases are Developer ID-signed and notarized, and are verified before the copy
# happens. A local self-signed DMG can never satisfy Gatekeeper, so for that build only the
# installer clears the quarantine flag on the installed copy; it never disables Gatekeeper.
# VOICECAST_STRIP_QUARANTINE=1 clears the flag on the installed copy of any build.
set -euo pipefail

repo="1tuz/tinycast"
team="J656U8XZ93"
expected_bundle="com.tinycast.app" # Preserved for existing Tinycast users.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; reset=$'\033[0m'
else
    bold=""; dim=""; green=""; reset=""
fi

fail() {
    printf '\n%sVoiceCast: %s%s\n' "$bold" "$1" "$reset" >&2
    exit 1
}
step() { printf '%s[%s/4]%s %s\n' "$green" "$1" "$reset" "$2"; }

printf '\n%s' "$bold"
printf '  ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n'
printf '  ┃                VoiceCast                     ┃\n'
printf '  ┃      Search · Speak · Act · Automate        ┃\n'
printf '  ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n'
printf '%s%s\n\n' "$reset" "$dim"

[ "$(uname -s)" = Darwin ] || fail "macOS is required."
command -v curl >/dev/null || fail "curl is required."
command -v codesign >/dev/null || fail "codesign is required."
command -v hdiutil >/dev/null || fail "hdiutil is required."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 26 ] || fail "macOS 26 or newer is required."

if pgrep -x VoiceCast >/dev/null || pgrep -x Tinycast >/dev/null; then
    fail "Quit VoiceCast / Tinycast before installing."
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/voicecast-install.XXXXXX")"
mount="$workdir/mount"
mounted=false
staged=""
backup=""
replaced=""
cleanup() {
    # Resolve first: under TMPDIR the mount table shows /private/var/... while $mount is
    # /var/..., so a path comparison against `mount` never matched and the image stayed
    # attached. Detach by the resolved path, then remove the tree.
    if [ "$mounted" = true ]; then
        resolved="$(cd "$mount" 2>/dev/null && pwd -P)" || resolved="$mount"
        hdiutil detach "$resolved" -force >/dev/null 2>&1 ||
            hdiutil detach "$mount" -force >/dev/null 2>&1 || true
    fi
    rm -rf "$workdir" 2>/dev/null || true
}
trap cleanup EXIT

if [ -n "${VOICECAST_DMG:-}" ]; then
    [ -f "$VOICECAST_DMG" ] || fail "VOICECAST_DMG is not an existing file: $VOICECAST_DMG."
    step 1 'Using local disk image'
    printf '  Local disk image: %s\n' "$VOICECAST_DMG"
    mkdir -p "$mount"
    hdiutil attach -readonly -nobrowse -quiet -mountpoint "$mount" "$VOICECAST_DMG" \
        || fail "Cannot mount the disk image."
    mounted=true
    app="$mount/VoiceCast.app"
    [ -d "$app" ] || fail "The DMG does not contain VoiceCast.app."
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
        "$app/Contents/Info.plist" 2>/dev/null)" || version=""
    printf '  Version: %s\n' "${version:-unknown}"
    step 2 'Skipping download (local disk image)'
else
    step 1 'Finding latest stable release'
    metadata="$(curl --retry 3 -fsSL --connect-timeout 15 \
        "https://api.github.com/repos/$repo/releases/latest")" || fail "Cannot read GitHub Releases."
    version="$(printf '%s\n' "$metadata" | sed -n 's/^[[:space:]]*"tag_name": "\([^"]*\)".*/\1/p' | head -1)"
    asset="$(printf '%s\n' "$metadata" | sed -n \
        's/^[[:space:]]*"browser_download_url": "\(https:[^"]*\/VoiceCast-[^"]*\.dmg\)".*/\1/p' | head -1)"
    if [ -z "$asset" ]; then
        # No notarized stable build yet: fall back to the newest published VoiceCast DMG,
        # which may be a pre-release. Its signature is still checked below.
        releases="$(curl --retry 3 -fsSL --connect-timeout 15 \
            "https://api.github.com/repos/$repo/releases?per_page=30")" \
            || fail "No VoiceCast DMG found and cannot list pre-releases."
        pair="$(printf '%s\n' "$releases" | awk '
            /"tag_name"/ && !found {
                tag = $0
                sub(/^.*"tag_name": "/, "", tag); sub(/".*$/, "", tag)
            }
            /"browser_download_url"/ && /VoiceCast-[^"]*\.dmg/ && !found {
                asset = $0
                sub(/^.*"browser_download_url": "/, "", asset); sub(/".*$/, "", asset)
                found = 1
            }
            END { if (found) printf "%s\t%s\n", tag, asset }
        ')"
        [ -n "$pair" ] || fail "No VoiceCast DMG found. Release signing may not be set up yet."
        version="${pair%%$'\t'*}"
        asset="${pair#*$'\t'}"
        printf '  %sNo stable VoiceCast release yet; using pre-release %s%s\n' \
            "$bold" "${version:-latest}" "$reset" >&2
    fi
    case "$asset" in
        "https://github.com/$repo/releases/download/"*) ;;
        *) fail "Unexpected release asset URL." ;;
    esac
    printf '  Version: %s\n' "${version:-latest}"

    step 2 'Downloading disk image'
    curl --retry 3 -fL --connect-timeout 20 "$asset" -o "$workdir/VoiceCast.dmg" \
        || fail "Download failed."
    mkdir -p "$mount"
    hdiutil attach -readonly -nobrowse -quiet -mountpoint "$mount" "$workdir/VoiceCast.dmg" \
        || fail "Cannot mount the disk image."
    mounted=true
    app="$mount/VoiceCast.app"
    [ -d "$app" ] || fail "The DMG does not contain VoiceCast.app."
fi

step 3 'Verifying signature, notarization and bundle identity'
codesign --verify --deep --strict "$app" || fail "Invalid app code signature."
identity_out="$(codesign -dv --verbose=4 "$app" 2>&1)" || fail "Cannot inspect the signature."
authority="$(printf '%s\n' "$identity_out" | sed -n 's/^Authority=//p' | head -1)"
team_id="$(printf '%s\n' "$identity_out" | sed -n 's/^TeamIdentifier=//p' | head -1)"
notarized=1
if printf '%s\n' "$authority" | grep -Eq '^Developer ID Application: '; then
    # A Developer ID build must be the release build: same team, notarized, accepted by
    # Gatekeeper. A failure here is a broken or foreign release, never a reason to bypass.
    printf '%s\n' "$authority" | grep -Eq '^Developer ID Application: .+ \('"$team"'\)$' || \
        fail "Developer ID certificate is not from team $team: ${authority:-missing}."
    [ "$team_id" = "$team" ] || fail "Unexpected team identifier: ${team_id:-missing}."
    xcrun stapler validate "$app" || fail "The app is not notarized."
    spctl --assess --type execute --verbose=4 "$app" || fail "Gatekeeper rejected the app."
else
    # Local/self-signed build: Gatekeeper can never accept it, so clear quarantine on the
    # installed copy instead of asking the user to run xattr by hand.
    notarized=0
    printf '\n%s! %s is not a Developer ID build:%s\n' "$bold" "$authority" "$reset" >&2
    printf '%s  Gatekeeper cannot accept it; quarantine is cleared for the installed copy.%s\n\n' \
        "$dim" "$reset" >&2
fi
info="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" \
    || fail "Bundle identifier missing."
[ "$info" = "$expected_bundle" ] || fail "Unexpected bundle identifier: $info."

step 4 'Installing verified application'
if [ -n "${VOICECAST_INSTALL_DIR:-}" ]; then
    install_root="$VOICECAST_INSTALL_DIR"
elif [ -d /Applications/VoiceCast.app ] || [ -d /Applications/Tinycast.app ]; then
    [ -w /Applications ] || fail "Cannot update /Applications without write permission."
    install_root=/Applications
elif [ -w /Applications ]; then
    install_root=/Applications
else
    install_root="$HOME/Applications"
fi
mkdir -p "$install_root" || fail "Cannot create $install_root."
destination="$install_root/VoiceCast.app"
legacy="$install_root/Tinycast.app"
[ ! -e "$legacy" ] || [ ! -e "$destination" ] \
    || fail "Both VoiceCast.app and Tinycast.app exist. Remove the obsolete duplicate first."
staged="$install_root/.VoiceCast.app.new.$$"
backup="$install_root/.VoiceCast.app.backup.$$"
ditto "$app" "$staged" || fail "Could not stage VoiceCast.app."
codesign --verify --deep --strict "$staged" || fail "Staged signature verification failed."
if [ -e "$destination" ]; then
    replaced="$destination"
elif [ -e "$legacy" ]; then
    replaced="$legacy"
else
    replaced=""
fi
if [ -n "$replaced" ]; then
    mv "$replaced" "$backup" || fail "Cannot back up the existing app."
fi
if ! mv "$staged" "$destination"; then
    if [ -n "$replaced" ] && [ -e "$backup" ]; then mv "$backup" "$replaced" || true; fi
    fail "Could not install VoiceCast.app."
fi
staged=""
if [ -e "$backup" ]; then rm -rf "$backup"; fi
backup=""
if [ "$notarized" = 0 ] || [ "${VOICECAST_STRIP_QUARANTINE:-0}" = "1" ]; then
    # xattr -dr com.apple.quarantine, applied only to the copy this installer just placed.
    # Gatekeeper itself stays enabled and untouched.
    xattr -dr com.apple.quarantine "$destination" || fail "Could not clear the quarantine flag."
fi
printf '\n%s✓%s Installed %s\n' "$green" "$reset" "$destination"
printf '%s  %s%s\n' "$dim" \
    "Open VoiceCast from Applications — no additional step is needed." "$reset"
