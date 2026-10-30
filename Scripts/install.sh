#!/bin/bash
set -euo pipefail

repo="https://github.com/1tuz/tinycast.git"

fail() {
    printf 'Tinycast install failed: %s\n' "$1" >&2
    exit 1
}

if [ -n "${TINYCAST_INSTALL_DIR:-}" ]; then
    install_root="$TINYCAST_INSTALL_DIR"
elif [ -d /Applications/Tinycast.app ]; then
    [ -w /Applications ] || fail "Tinycast already exists in /Applications, which is not writable."
    install_root=/Applications
else
    install_root="$HOME/Applications"
fi
destination="$install_root/Tinycast.app"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/tinycast-install.XXXXXX")"
staged="$install_root/.Tinycast.app.new.$$"
backup="$install_root/.Tinycast.app.backup.$$"

cleanup() {
    if [ ! -e "$destination" ] && [ -e "$backup" ]; then
        mv "$backup" "$destination"
    fi
    rm -rf "$workdir" "$staged"
}
trap cleanup EXIT

command -v git >/dev/null || fail "Git is required."
command -v xcodebuild >/dev/null || fail "Install Xcode 26 or 27 first."
xcode_version="$(xcodebuild -version | awk '/^Xcode / { print $2; exit }')"
case "$xcode_version" in
    26.*|27.*) ;;
    *) fail "Xcode 26 or 27 is required; found ${xcode_version:-unknown}." ;;
esac
signing_identity="${TINYCAST_SIGNING_IDENTITY:-}"
if [ -z "$signing_identity" ] && [ -d "$destination" ]; then
    installed_authority="$(codesign -dv --verbose=4 "$destination" 2>&1 \
        | awk -F= '$1 == "Authority" { print substr($0, index($0, "=") + 1); exit }')"
    if [ -n "$installed_authority" ]; then
        signing_identity="$(security find-identity -v -p codesigning \
            | awk -F '"' -v wanted="$installed_authority" '$2 == wanted { print $2; exit }')"
        [ -n "$signing_identity" ] || fail "The installed app uses '$installed_authority', but that identity is not in Keychain. Set TINYCAST_SIGNING_IDENTITY."
    fi
fi
if [ -z "$signing_identity" ]; then
    signing_identity="$(security find-identity -v -p codesigning \
        | awk -F '"' '/^[[:space:]]*[0-9]+\)/ { print $2; exit }')"
fi
[ -n "$signing_identity" ] || fail "A persistent code-signing identity is required."

git clone --depth 1 --branch main "$repo" "$workdir/source"
xcodebuild \
    -project "$workdir/source/Tinycast.xcodeproj" \
    -scheme Tinycast \
    -configuration Release \
    -derivedDataPath "$workdir/DerivedData" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$signing_identity" \
    OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
    build

app="$workdir/DerivedData/Build/Products/Release/Tinycast.app"
[ -d "$app" ] || fail "The build did not produce Tinycast.app."
mkdir -p "$install_root"
ditto "$app" "$staged"

if [ -e "$destination" ]; then
    mv "$destination" "$backup"
fi
if ! mv "$staged" "$destination"; then
    [ ! -e "$backup" ] || mv "$backup" "$destination"
    fail "Could not place the app in $install_root."
fi
rm -rf "$backup"
printf 'Installed %s\n' "$destination"
