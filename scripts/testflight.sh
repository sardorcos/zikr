#!/usr/bin/env bash
# Builds, tests, archives and uploads ZIKR to TestFlight. Run on a Mac with Xcode 26+.
#
# Needs an App Store Connect API key (App Store Connect → Users and Access → Integrations →
# App Store Connect API, role "App Manager" or "Admin"):
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   export ASC_KEY_PATH=$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
# The app record with the same bundle ID must already exist in App Store Connect.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ASC_KEY_ID:?set ASC_KEY_ID}" "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}" "${ASC_KEY_PATH:?set ASC_KEY_PATH}"

if grep -q '"ZIKR_BUNDLE_ID": "com.example.zikr"' tools/gen_project.py; then
  echo "Run ./scripts/configure.sh TEAM_ID BUNDLE_ID first."; exit 1
fi

# Date-based build numbers always increase, whether built locally or on CI.
# (CI services such as Codemagic export their own small BUILD_NUMBER, so a separate name is used.)
BUILD_NUMBER="${ZIKR_BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}"
OUT="build"
ARCHIVE="$OUT/ZIKR.xcarchive"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
rm -rf "$ARCHIVE" "$OUT/export"; mkdir -p "$OUT"

# run_logged LOG FILTER CMD...  — full output to LOG, filtered lines to the console,
# exits with the command's own status.
run_logged() {
  local log="$1" filter="$2"; shift 2
  set +e
  "$@" > "$log" 2>&1
  local status=$?
  set -e
  grep -E "$filter" "$log" || true
  if [[ $status -ne 0 ]]; then
    echo "✖ Failed ($status). Last lines of $log:"; tail -n 60 "$log"; exit $status
  fi
}

python3 tools/gen_l10n.py --check

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  SIM=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for r,l in d.items() if "iOS" in r for x in l if x["name"].startswith("iPhone")))')
  echo "▶ Tests on simulator $SIM"
  run_logged "$OUT/test.log" "error:|✘|failed|\*\* TEST" \
    xcodebuild test -project ZIKR.xcodeproj -scheme ZIKR -destination "id=$SIM"
fi

echo "▶ Archive (build $BUILD_NUMBER)"
if [[ "${ZIKR_SIGNING:-auto}" == "manual" ]]; then
  # CI: the project was switched to manual signing by scripts/ci_profiles.sh. Archive and export an
  # App Store IPA; Codemagic's publishing step uploads it to App Store Connect / TestFlight.
  run_logged "$OUT/archive.log" "error:|\*\* ARCHIVE" \
    xcodebuild archive -project ZIKR.xcodeproj -scheme ZIKR -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  run_logged "$OUT/export.log" "error|EXPORT" \
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions-manual.plist"
  ls -la "$OUT/export"
  echo "✅ Build $BUILD_NUMBER archived and signed for the App Store; Codemagic publishing uploads it."
  exit 0
fi

# App Store Connect tokens are only valid for minutes; a fresh CI machine with a drifting clock
# makes Apple reject them ("Authentication failed"). Sync the clock and retry such failures.
if [[ -n "${CI:-}" ]]; then
  echo "Clock before sync: $(date -u)"
  sudo -n sntp -sS time.apple.com >/dev/null 2>&1 || true
  echo "Clock after sync:  $(date -u)"
fi
for attempt in 1 2 3; do
  set +e
  xcodebuild archive -project ZIKR.xcodeproj -scheme ZIKR -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${AUTH[@]}" > "$OUT/archive.log" 2>&1
  status=$?
  set -e
  cp "$OUT/archive.log" "$OUT/archive-attempt$attempt.log"
  if [[ $status -eq 0 ]]; then break; fi
  if grep -q "Authentication failed" "$OUT/archive.log" && [[ $attempt -lt 3 ]]; then
    echo "Archive attempt $attempt: App Store Connect authentication failed, retrying in 20 s"
    sleep 20; continue
  fi
  grep -E "error:" "$OUT/archive.log" | head -20
  echo "✖ Archive failed ($status)"; exit $status
done
grep -E "\*\* ARCHIVE" "$OUT/archive.log" || true

TEAM_ID=$(grep -o '"DEVELOPMENT_TEAM": "[^"]*"' tools/gen_project.py | cut -d'"' -f4)
python3 - "$TEAM_ID" "$OUT" <<'PY'
import plistlib, sys
team, out = sys.argv[1], sys.argv[2]
with open("scripts/ExportOptions.plist", "rb") as f:
    opts = plistlib.load(f)
opts["teamID"] = team
with open(f"{out}/ExportOptions.plist", "wb") as f:
    plistlib.dump(opts, f)
local = dict(opts, destination="export")
with open(f"{out}/ExportOptions-local.plist", "wb") as f:
    plistlib.dump(local, f)
PY

if [[ "${ZIKR_UPLOAD:-1}" == "0" ]]; then
  echo "▶ Export IPA only (no App Store Connect app record yet)"
  run_logged "$OUT/export.log" "error|EXPORT" \
    xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions-local.plist" "${AUTH[@]}"
  echo "✅ Build $BUILD_NUMBER compiled, tested and signed. Create the app in App Store Connect"
  echo "   with bundle ID $(grep -o '"ZIKR_BUNDLE_ID": "[^"]*"' tools/gen_project.py | cut -d'"' -f4) and rerun to upload."
  exit 0
fi

echo "▶ Upload to App Store Connect"
run_logged "$OUT/export.log" "error|Upload|EXPORT|uploaded" \
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" "${AUTH[@]}"

echo "✅ Build $BUILD_NUMBER uploaded. It appears in TestFlight after processing (usually 5–30 min)."
