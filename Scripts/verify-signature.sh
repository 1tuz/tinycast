#!/bin/bash
# Assert the built app is release-safe and can still prompt. Usage: verify-signature.sh <path-to-.app>
set -uo pipefail

APP="${1:?usage: verify-signature.sh <path-to-.app>}"
NAME="$(basename "$APP" .app)"
STATUS=0

# The hardened-runtime entitlement each usage string needs before tccd will show its prompt.
RESOURCE_ENTITLEMENTS=(
    NSAppleEventsUsageDescription=com.apple.security.automation.apple-events
    NSCameraUsageDescription=com.apple.security.device.camera
    NSCalendarsFullAccessUsageDescription=com.apple.security.personal-information.calendars
    NSCalendarsWriteOnlyAccessUsageDescription=com.apple.security.personal-information.calendars
    NSRemindersFullAccessUsageDescription=com.apple.security.personal-information.calendars
    NSContactsUsageDescription=com.apple.security.personal-information.addressbook
    NSLocationWhenInUseUsageDescription=com.apple.security.personal-information.location
    NSPhotoLibraryUsageDescription=com.apple.security.personal-information.photos-library
)

fail() {
    echo "✗ $1" >&2
    STATUS=1
}

ENTITLEMENTS="$(mktemp)"
trap 'rm -f "$ENTITLEMENTS"' EXIT
codesign -d --entitlements - --xml "$APP" > "$ENTITLEMENTS" 2>/dev/null

# The main executable and both helpers are signed separately; sweep all Mach-O
# files under Contents so a stray unsigned framework cannot slip through.
BINS="$(while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q "Mach-O"; then
        echo "$f"
    fi
done < <(find "$APP/Contents" -type f -print0); true)"
[ -n "$BINS" ] || fail "$NAME.app: no Mach-O binaries found under Contents"

while IFS= read -r BIN; do
    INFO="$(codesign -dv --verbose=2 "$BIN" 2>&1)"
    [[ "$INFO" =~ flags=0x[0-9a-f]+\([^\)]*runtime ]] ||
        fail "${BIN#$APP/}: hardened runtime not enabled"
done <<< "$BINS"

codesign --verify --deep --strict "$APP" || fail "$NAME.app: the seal does not verify"

# Xcode injects it for Debug only; it breaks the hardened-runtime contract of a release.
/usr/libexec/PlistBuddy -c "Print :com.apple.security.get-task-allow" "$ENTITLEMENTS" &>/dev/null &&
    fail "$NAME.app: get-task-allow is present"

# A missing one is silent at runtime: the request resolves as denied in milliseconds, never asked.
for PAIR in "${RESOURCE_ENTITLEMENTS[@]}"; do
    USAGE="${PAIR%%=*}" ENTITLEMENT="${PAIR#*=}"
    /usr/libexec/PlistBuddy -c "Print :$USAGE" "$APP/Contents/Info.plist" &>/dev/null || continue
    [ "$(/usr/libexec/PlistBuddy -c "Print :$ENTITLEMENT" "$ENTITLEMENTS" 2>/dev/null)" = true ] ||
        fail "$NAME.app: $USAGE is declared but $ENTITLEMENT is not"
done

if [ "$STATUS" -eq 0 ]; then
    echo "✓ $NAME.app is release-safe and its prompts are entitled"
fi
exit "$STATUS"
