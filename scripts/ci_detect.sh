#!/usr/bin/env bash
# CI helper: finds the Team ID and the ZIKR bundle ID through the App Store Connect API
# (codemagic-cli-tools, credentials from APP_STORE_CONNECT_* variables) when they are not set.
# Prints `export` lines for eval.
set -euo pipefail
OUT="${1:-build}"; mkdir -p "$OUT"

if [[ -z "${ZIKR_BUNDLE_ID:-}" || "${ZIKR_BUNDLE_ID}" == SET_* ]]; then
  app-store-connect apps list --json > "$OUT/asc-apps.json" 2> "$OUT/asc-apps.err" || true
  ZIKR_BUNDLE_ID=$(python3 - "$OUT/asc-apps.json" <<'PY'
import json, sys
try:
    apps = json.load(open(sys.argv[1]))
except Exception:
    apps = []
for a in apps:
    attrs = a.get("attributes", {})
    print(f"  app: {attrs.get('name')} | {attrs.get('bundleId')}", file=sys.stderr)
match = [a["attributes"]["bundleId"] for a in apps
         if "zikr" in (a.get("attributes", {}).get("name", "") + a.get("attributes", {}).get("bundleId", "")).lower()]
print(match[0] if match else "")
PY
)
fi
if [[ -z "$ZIKR_BUNDLE_ID" ]]; then
  echo "No App Store Connect app named ZIKR was found. Create it (Apps → + → New App) and rerun." >&2
  cat "$OUT/asc-apps.err" >&2 || true
  exit 1
fi

if [[ -z "${ZIKR_TEAM_ID:-}" || "${ZIKR_TEAM_ID}" == SET_* ]]; then
  app-store-connect bundle-ids list --json > "$OUT/asc-bundle-ids.json" 2> "$OUT/asc-bundle-ids.err" || true
  ZIKR_TEAM_ID=$(python3 - "$OUT/asc-bundle-ids.json" "$ZIKR_BUNDLE_ID" <<'PY'
import json, sys, collections
try:
    ids = json.load(open(sys.argv[1]))
except Exception:
    ids = []
seeds = [i["attributes"].get("seedId") for i in ids if i.get("attributes", {}).get("identifier") == sys.argv[2]]
seeds = [s for s in seeds if s] or [i["attributes"].get("seedId") for i in ids if i.get("attributes", {}).get("seedId")]
print(collections.Counter(seeds).most_common(1)[0][0] if seeds else "")
PY
)
fi
if [[ -z "$ZIKR_TEAM_ID" ]]; then
  echo "Could not determine the Team ID; set ZIKR_TEAM_ID in codemagic.yaml." >&2
  cat "$OUT/asc-bundle-ids.err" >&2 || true
  exit 1
fi

echo "Detected: team $ZIKR_TEAM_ID, bundle $ZIKR_BUNDLE_ID" >&2
echo "export ZIKR_TEAM_ID='$ZIKR_TEAM_ID' ZIKR_BUNDLE_ID='$ZIKR_BUNDLE_ID'"
