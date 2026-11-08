#!/bin/bash
# Fast gate for daily fork sync. Full Scripts/run-tests.sh is intentionally not run here.
# Usage: gate.sh <upstream-sha>
set -uo pipefail
UP="${1:?upstream sha}"
cd "$(git rev-parse --show-toplevel)"
TMP="${RUNNER_TEMP:-$(mktemp -d)}"

echo "::group::structure"
test -f Tinycast.xcodeproj/project.pbxproj || { echo "::error::missing Xcode project"; exit 1; }
test ! -d Tinycast/Features/Dictation || { echo "::error::Upstream Dictation sources must be absent"; exit 1; }
test -f Tinycast/Features/VoiceAsk/SpeechRuntimeVoiceAsk.swift || { echo "::error::Speech Runtime Voice Ask missing"; exit 1; }
test -f Tinycast/Features/VoiceAsk/SpeechVoiceCommandRouter.swift || { echo "::error::Voice command router missing"; exit 1; }
test -f Tinycast/Features/VoiceAsk/SpeechVoiceCommandParser.swift || { echo "::error::Voice command parser missing"; exit 1; }
test -f Tinycast/Features/VoiceAsk/SpeechVoiceCommandCatalog.swift || { echo "::error::Voice command catalog missing"; exit 1; }
if rg -n -i 'CodexRealtime|thread/realtime' Tinycast/Features/VoiceAsk; then
  echo "::error::obsolete cloud audio path detected"
  exit 1
fi
rg -q 'static let repository = "1tuz/tinycast"' Tinycast/Features/Updates/Model/ReleaseFeed.swift \
  || { echo "::error::ReleaseFeed still points at upstream"; exit 1; }
rg -q 'pump = nil' Tinycast/Features/Support/Service/SupportReminderStore.swift \
  || { echo "::error::Support reminder pump not disabled"; exit 1; }
echo "::endgroup::"

echo "::group::xcodebuild Release smoke"
if ! xcodebuild -project Tinycast.xcodeproj -scheme Tinycast -configuration Release \
  -derivedDataPath "$TMP/gate-dd" ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- build > "$TMP/gate-build.log" 2>&1; then
  echo "::endgroup::"
  grep -E 'error:' "$TMP/gate-build.log" | head -40 || true
  tail -40 "$TMP/gate-build.log"
  echo "::error::build failed (upstream ${UP:0:7})"
  exit 1
fi
echo "::endgroup::"

echo "::group::focused harnesses"
FAILED=""
for t in hotkey-test ai-provider-test updates-test ranking-test developer-utility-test \
  ephemeral-snippet-test quick-action-test file-search-test file-search-session-test \
  calendar-test window-layout-test window-switch-test compact-bar-test \
  clipboard-search-test clipboard-thumbnail-test fallback-test launcher-settings-file-test \
  settings-backup-test hotkey-dispatch-test workflow-test voice-command-test \
  voice-alias-test installer-fallback-test; do
  echo "▸ $t"
  if ! ./Scripts/run-tests.sh "$t" > "$TMP/gate-$t.log" 2>&1; then
    echo "::error::harness failed: $t"
    tail -40 "$TMP/gate-$t.log" || true
    FAILED="$FAILED $t"
  fi
done
echo "::endgroup::"

if [ -n "$FAILED" ]; then
  echo "::error::gate failed on:$FAILED (upstream ${UP:0:7})"
  exit 1
fi

echo "gate.sh: ok on upstream ${UP:0:7}"
