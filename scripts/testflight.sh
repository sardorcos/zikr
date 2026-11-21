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
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d.%H%M)}"
OUT="build"
ARCHIVE="$OUT/ZIKR.xcarchive"
AUTH=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
rm -rf "$OUT"; mkdir -p "$OUT"

python3 tools/gen_l10n.py --check

if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  SIM=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin)["devices"]; print(next(x["udid"] for r,l in d.items() if "iOS" in r for x in l if x["name"].startswith("iPhone")))')
  echo "▶ Tests on simulator $SIM"
  xcodebuild test -project ZIKR.xcodeproj -scheme ZIKR -destination "id=$SIM" -quiet
fi

echo "▶ Archive (build $BUILD_NUMBER)"
xcodebuild archive -project ZIKR.xcodeproj -scheme ZIKR -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" "${AUTH[@]}" -quiet

echo "▶ Upload to App Store Connect"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist "${AUTH[@]}"

echo "✅ Build $BUILD_NUMBER uploaded. It appears in TestFlight after processing (usually 5–30 min)."
