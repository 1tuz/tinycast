#!/bin/bash
# Release body: notes for the in-app updater first, public install information second.
set -euo pipefail

BODY_OUT="${1:?usage: release-notes.sh <body.md> <discord.md>}"
DISCORD_OUT="${2:?usage: release-notes.sh <body.md> <discord.md>}"

REPO="${REPO:-1tuz/tinycast}"
TAG="${TAG:?TAG is required, e.g. v0.3.0}"
SHA="${SHA:-$(git rev-parse HEAD)}"
VERSION="${VERSION:-${TAG#v}}"
DISPLAY_NAME="${DISPLAY_NAME:-SpeechCast}"
BUNDLE_ID="${BUNDLE_ID:-com.tinycast.app}"
# Preserve the existing release-notes parser's marker for update compatibility.
MARKER="<!-- tinycast:install -->"
DISCORD_BUDGET=1200
DISCORD_BULLETS=15

CHANNEL_FILTER='test("-beta\\.") | not'
PREVIOUS="$(gh release list --repo "$REPO" --limit 200 --json tagName,isDraft --jq \
    "[.[] | select(.isDraft | not) | .tagName
      | select(. != \"${TAG}\") | select(${CHANNEL_FILTER})] | first // empty")"
NOTES_ARGS=(-f "tag_name=${TAG}" -f "target_commitish=${SHA}")
if [ -n "$PREVIOUS" ]; then NOTES_ARGS+=(-f "previous_tag_name=${PREVIOUS}"); fi
echo "▸ Generating notes for ${TAG}${PREVIOUS:+ since ${PREVIOUS}}"
GENERATED="$(gh api "repos/${REPO}/releases/generate-notes" "${NOTES_ARGS[@]}" --jq .body)"
COMPARE_URL="$(printf '%s\n' "$GENERATED" | sed -n 's|^\*\*Full Changelog\*\*: \(.*\)$|\1|p' | tail -n1)"
CHANGELOG="$(printf '%s\n' "$GENERATED" | sed -E \
    -e '/^\*\*Full Changelog\*\*:/d' \
    -e "s|https://github\.com/${REPO}/pull/([0-9]+)|#\1|g")"
[ -n "$(printf '%s' "$CHANGELOG" | tr -d '[:space:]')" ] || CHANGELOG="Maintenance and internal changes."

{
    printf '%s\n\n' "$CHANGELOG"
    printf '%s\n\n' "$MARKER"
    printf '**Version:** %s · **Bundle ID:** `%s`\n' "$VERSION" "$BUNDLE_ID"
    printf 'Built from %s.' "$SHA"
    if [ -n "$COMPARE_URL" ]; then printf ' [Full changelog](%s)' "$COMPARE_URL"; fi
    printf '\n\n'
    printf '%s\n' "Download the SpeechCast DMG attached to this release or run:"
    printf '```sh\ncurl -fsSL https://raw.githubusercontent.com/1tuz/tinycast/main/Scripts/install.sh | VOICECAST_STRIP_QUARANTINE=1 /bin/bash\n```\n'
    printf '%s\n' "Signed with Apple **Developer ID** (team \`J656U8XZ93\`) and **notarized by Apple**. Download, open the DMG, drag **SpeechCast** to Applications and launch it — no terminal commands, no Gatekeeper warnings. The one-liner above also clears the quarantine flag on the installed copy if Gatekeeper still refuses the download."
} > "$BODY_OUT"

printf '%s\n' "$CHANGELOG" | awk -v budget="$DISCORD_BUDGET" -v bullets="$DISCORD_BULLETS" '
    { line = $0 }
    /^[*-] / { seen++ }
    { used += length(line) + 1 }
    used > budget || seen > bullets { print "…and more — see the release page."; exit }
    { print line }
' > "$DISCORD_OUT"

echo "✓ ${BODY_OUT}"
