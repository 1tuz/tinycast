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
test -f Tinycast/Features/Focus/Model/FocusProfile.swift || { echo "::error::Focus model missing"; exit 1; }
test -f Tinycast/Features/Focus/Service/FocusSessionCoordinator.swift || { echo "::error::Focus coordinator missing"; exit 1; }
test -f docs/features/focus.md || { echo "::error::Focus feature doc missing"; exit 1; }
grep -qF 'FocusSessionCoordinator' Tinycast/App/AppCore.swift \
  || { echo "::error::Focus coordinator is no longer owned by AppCore"; exit 1; }
! grep -qE '^import (AppKit|SwiftUI|Cocoa)' Tinycast/Features/Focus/Model/*.swift \
  || { echo "::error::Focus model must stay Foundation-only"; exit 1; }
if grep -RniE 'CodexRealtime|thread/realtime' Tinycast/Features/VoiceAsk; then
  echo "::error::obsolete cloud audio path detected"
  exit 1
fi
grep -qF 'static let repository = "1tuz/tinycast"' Tinycast/Features/Updates/Model/ReleaseFeed.swift \
  || { echo "::error::ReleaseFeed still points at upstream"; exit 1; }
grep -qF 'pump = nil' Tinycast/Features/Support/Service/SupportReminderStore.swift \
  || { echo "::error::Support reminder pump not disabled"; exit 1; }
grep -qF 'SpeechCast' Tinycast/Info.plist \
  || { echo "::error::SpeechCast display name missing"; exit 1; }
grep -qF 'speechcast.svg' Tinycast/tinycast.icon/icon.json \
  || { echo "::error::SpeechCast Dock icon not selected"; exit 1; }
grep -qF 'speechcast.svg' Tinycast/Assets.xcassets/MenuBarIcon.imageset/Contents.json \
  || { echo "::error::SpeechCast menu bar icon not selected"; exit 1; }
# Post-sync guardrails: the public build must stay a Developer ID, notarized release. A sync
# that brings the upstream self-signed pipeline back has to fail here, not in front of a user.
RELEASE=.github/workflows/release.yml
for token in 'DEVELOPER_ID_APPLICATION_P12_BASE64' 'DEVELOPER_ID_APPLICATION_P12_PASSWORD' \
  'APPLE_TEAM_ID' 'APPSTORE_API_KEY_ID' 'APPSTORE_ISSUER_ID' 'APPSTORE_API_PRIVATE_KEY_BASE64'; do
  grep -qF -- "$token" "$RELEASE" \
    || { echo "::error::release workflow lost required secret $token"; exit 1; }
done
for token in 'notarytool submit' 'stapler staple' 'stapler validate' 'spctl --assess' \
  'ENABLE_HARDENED_RUNTIME=YES' '--timestamp' 'J656U8XZ93'; do
  grep -qF -- "$token" "$RELEASE" \
    || { echo "::error::release workflow lost '$token'"; exit 1; }
done
! grep -qF 'Tinycast Self-Signed' "$RELEASE" \
  || { echo "::error::the self-signed identity must never sign a public release"; exit 1; }
grep -qF 'Tinycast Self-Signed' project.yml \
  || { echo "::error::local development lost its self-signed identity"; exit 1; }
grep -qF 'certificate leaf[subject.OU] = "J656U8XZ93"' \
  Tinycast/Features/Updates/Service/BundleSignature.swift \
  || { echo "::error::BundleSignature no longer pins the release team"; exit 1; }
grep -qF 'Developer ID Application' Scripts/install.sh \
  || { echo "::error::installer no longer checks the Developer ID authority"; exit 1; }
grep -qF 'spctl --assess' Scripts/install.sh \
  || { echo "::error::installer no longer asks Gatekeeper about the download"; exit 1; }
grep -qF 'stapler validate' Scripts/install.sh \
  || { echo "::error::installer no longer checks the notarization ticket"; exit 1; }
# A quarantine bypass must never return to the release path. The single allowed use is the
# guarded fallback in install.sh, which runs only for a build that is not Developer ID-signed;
# a Developer ID build that fails notarization or Gatekeeper still aborts there.
! grep -REq 'xattr +-d|xattr +-dr|xattr +-c' "$RELEASE" Scripts/release-notes.sh \
  Scripts/build-dmg.sh .1tuz/branding/release-notes.sh .1tuz/branding/build-dmg.sh \
  || { echo "::error::quarantine-removal bypass reappeared in the release path"; exit 1; }
grep -qF 'quarantine is cleared for the installed copy' Scripts/install.sh \
  || { echo "::error::installer lost the guarded non-notarized quarantine fallback"; exit 1; }
grep -qF 'VOICECAST_STRIP_QUARANTINE=1 /bin/bash' Scripts/release-notes.sh \
  || { echo "::error::published install command lost the quarantine fallback"; exit 1; }
grep -qF 'VOICECAST_STRIP_QUARANTINE' Scripts/install.sh \
  || { echo "::error::installer no longer honours VOICECAST_STRIP_QUARANTINE"; exit 1; }
grep -qF 'Gatekeeper rejected the app' Scripts/install.sh \
  || { echo "::error::installer no longer enforces Gatekeeper on Developer ID builds"; exit 1; }
grep -qF 'The app is not notarized' Scripts/install.sh \
  || { echo "::error::installer no longer requires a stapled notarization ticket"; exit 1; }
grep -qF 'Developer ID Application' Scripts/verify-release.sh \
  || { echo "::error::release verifier lost the Developer ID authority anchor"; exit 1; }
grep -qF 'Notarized Developer ID' .github/workflows/release.yml \
  || { echo "::error::release workflow no longer asserts Gatekeeper's notarized origin"; exit 1; }
! grep -qE 'Open Anyway|right-click .*Open' Scripts/install.sh Scripts/release-notes.sh INSTALL.md README.md \
  || { echo "::error::install path still instructs a Gatekeeper bypass"; exit 1; }
# The overlay is what the daily sync copies, so it may never drift from the canonical file.
for pair in \
  "README.md:README.md" "INSTALL.md:INSTALL.md" \
  "docs/speechcast-distribution.md:distribution.md" \
  "Scripts/install.sh:install.sh" "Scripts/build-dmg.sh:build-dmg.sh" \
  "Scripts/release-notes.sh:release-notes.sh" \
  "Tinycast/tinycast.icon/icon.json:icon.json" \
  "Tinycast/tinycast.icon/Assets/speechcast.svg:icon.svg" \
  "Tinycast/Assets.xcassets/MenuBarIcon.imageset/Contents.json:menuicon.json" \
  "Tinycast/Assets.xcassets/MenuBarIcon.imageset/speechcast.svg:menubar.svg" \
  "docs/speechcast-logo.svg:logo.svg"; do
  canonical="${pair%%:*}"
  overlay=".1tuz/branding/${pair#*:}"
  cmp -s "$canonical" "$overlay" \
    || { echo "::error::$overlay drifted from $canonical; copy it back into the overlay"; exit 1; }
done
grep -qF 'SpeechCast' Scripts/install.sh \
  || { echo "::error::installer lost the SpeechCast branding"; exit 1; }
grep -qF 'SpeechCast' Scripts/release-notes.sh \
  || { echo "::error::release notes lost the SpeechCast branding"; exit 1; }
bash -n Scripts/install.sh Scripts/build-dmg.sh Scripts/release-notes.sh Scripts/verify-release.sh \
  && bash -n .1tuz/apply.sh .1tuz/gate.sh .1tuz/branding/apply.sh \
  || { echo "::error::shell syntax check failed"; exit 1; }
printf '%s\n' 'SpeechCast brand gate: ok'
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
  voice-alias-test focus-profile-test installer-fallback-test; do
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
