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

# A patch that adds a source file needs it in the Xcode project.
if [ -n "$(git status --porcelain --untracked-files=all -- Tinycast | grep -E '^(\?\?|A ) ' || true)" ]; then
  command -v xcodegen > /dev/null || brew install --quiet xcodegen
  echo "regenerating the Xcode project for added sources"
  xcodegen generate --quiet
fi

echo "apply.sh: all patches applied"
