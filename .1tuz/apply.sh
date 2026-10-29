#!/bin/bash
# Applies every patch in .1tuz/patches onto a pristine upstream checkout, in name order.
# --3way falls back to a merge when the context drifted, so only a real conflict fails.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

failed=""
for patch in .1tuz/patches/*.patch; do
  name="${patch##*/}"
  echo "applying $name"
  if ! git apply --3way --whitespace=nowarn "$patch"; then
    failed="$name"
    echo "::error::patch failed: $name"
    exit 1
  fi
done

# Optional rewrites: leftover upstream releases-page links.
{ grep -rlF --include='*.swift' 'github.com/abue-ammar/tinycast/releases' Tinycast || true; } | while read -r file; do
  echo "rewriting releases link in $file"
  sed -i.bak 's#github\.com/abue-ammar/tinycast/releases#github.com/1tuz/tinycast/releases#g' "$file"
  rm -f "$file.bak"
done

# The fork does not publish the upstream website.
rm -f .github/workflows/website.yml .github/workflows/website-media.yml

# A patch that adds a source file needs it in the Xcode project.
if [ -n "$(git status --porcelain --untracked-files=all -- Tinycast | grep -E '^(\?\?|A ) ' || true)" ]; then
  echo "regenerating the Xcode project for added sources"
  if ! command -v xcodegen > /dev/null; then
    version=2.46.0
    checksum=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806
    workdir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/xcodegen.XXXXXX")"
    trap 'rm -rf "$workdir"' EXIT
    archive="$workdir/xcodegen.zip"
    curl -fsSL "https://github.com/yonaskolb/XcodeGen/releases/download/$version/xcodegen.zip" -o "$archive"
    printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
    /usr/bin/unzip -q "$archive" -d "$workdir"
    export PATH="$workdir/xcodegen/bin:$PATH"
  fi
  xcodegen generate --quiet
fi

echo "apply.sh: all patches applied"
