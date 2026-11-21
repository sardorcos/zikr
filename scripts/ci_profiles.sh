#!/usr/bin/env bash
# CI manual signing (the approach Codemagic's standard iOS workflows use):
#  1. registers the app and widget bundle IDs and enables the App Groups capability,
#  2. creates/fetches App Store provisioning profiles for both (team distribution certificate),
#  3. applies them to the Xcode project with `xcode-project use-profiles`.
# Apple's API cannot create an App Group or attach it to an App ID; that one-time step is done in
# the Developer portal. This script checks the profiles and explains exactly what is missing.
set -uo pipefail
OUT="${1:-build}"; mkdir -p "$OUT"
APP="$ZIKR_BUNDLE_ID"; WIDGETS="$ZIKR_BUNDLE_ID.widgets"; WATCH="$ZIKR_BUNDLE_ID.watchkitapp"; GROUP="group.$ZIKR_BUNDLE_ID"
LOG="$OUT/profiles.log"; : > "$LOG"
# Xcode 16+ keeps profiles in UserData; older tools use MobileDevice.
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")
clean() { sed 's/\x1b\[[0-9;]*m//g'; }

# Prints OK when an installed App Store profile for $1 contains the App Group, otherwise MISSING.
profile_status() {
  local status="MISSING" f
  for f in "${PROFILE_DIRS[0]}"/*.mobileprovision "${PROFILE_DIRS[1]}"/*.mobileprovision; do
    [[ -e "$f" ]] || continue
    security cms -D -i "$f" > "$OUT/profile.plist" 2>/dev/null || continue
    if python3 - "$OUT/profile.plist" "$1" "$GROUP" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
ent = p.get("Entitlements", {})
bundle = ent.get("application-identifier", "").split(".", 1)[-1]
groups = ent.get("com.apple.security.application-groups", [])
sys.exit(0 if bundle == sys.argv[2] and sys.argv[3] in groups else 1)
PY
    then status="OK"; fi
  done
  echo "$status"
}

# Team signing: the distribution certificate (with its private key) is loaded by Codemagic's
# ios_signing from the team's Code signing identities; no new certificates are ever created here.
# App Store profiles are created through the API from the account's active distribution
# certificates, so they match whichever team identity is installed.
bundle_rid() {
  app-store-connect bundle-ids list --bundle-id-identifier "$1" --strict-match-identifier --json 2>>"$LOG" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["id"] if d else "")' 2>/dev/null
}

fetch_profile() {
  local rid certs active
  rid=$(bundle_rid "$1"); [[ -n "$rid" ]] || { echo "No bundle ID $1" >>"$LOG"; return 1; }
  # Profiles that contained a revoked certificate are INVALID: remove them.
  for pid in $(app-store-connect bundle-ids profiles --bundle-ids "$rid" --type IOS_APP_STORE --state INVALID --json 2>>"$LOG" \
      | python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(sys.stdin)))' 2>/dev/null); do
    app-store-connect profiles delete "$pid" >>"$LOG" 2>&1 && echo "  Deleted invalid profile $pid" | tee -a "$LOG"
  done
  active=$(app-store-connect bundle-ids profiles --bundle-ids "$rid" --type IOS_APP_STORE --state ACTIVE --json 2>>"$LOG" \
      | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)
  if [[ "${active:-0}" == "0" ]]; then
    certs=$(app-store-connect certificates list --type DISTRIBUTION IOS_DISTRIBUTION --json 2>>"$LOG" \
      | python3 -c 'import json,sys; print(" ".join(c["id"] for c in json.load(sys.stdin)))')
    [[ -n "$certs" ]] || { echo "No distribution certificates in the account" | tee -a "$LOG"; return 1; }
    local name="ZIKR App Store"; [[ "$1" == *.widgets ]] && name="ZIKR Widgets App Store"; [[ "$1" == *.watchkitapp ]] && name="ZIKR Watch App Store"
    app-store-connect profiles create "$rid" --type IOS_APP_STORE --certificate-ids $certs --name "$name" >>"$LOG" 2>&1 \
      && echo "  Created profile '$name'" | tee -a "$LOG" || return 1
  fi
  app-store-connect bundle-ids profiles --bundle-ids "$rid" --type IOS_APP_STORE --state ACTIVE --save >>"$LOG" 2>&1
}

need_portal=0
for id in "$APP" "$WIDGETS"; do
  app-store-connect bundle-ids list --bundle-id-identifier "$id" --strict-match-identifier --json \
    > "$OUT/bid.json" 2>>"$LOG" || true
  rid=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0]["id"] if d else "")' "$OUT/bid.json" 2>/dev/null)
  if [[ -z "$rid" ]]; then
    name="ZIKR"; [[ "$id" == "$WIDGETS" ]] && name="ZIKR Widgets"
    app-store-connect bundle-ids create "$id" --name "$name" --platform IOS --json > "$OUT/bid.json" 2>>"$LOG" || true
    rid=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d=d[0] if isinstance(d,list) else d; print(d["id"])' "$OUT/bid.json" 2>/dev/null)
    echo "Registered bundle ID $id (${rid:-?})" | tee -a "$LOG"
  else
    echo "Bundle ID $id exists ($rid)" | tee -a "$LOG"
  fi
  if [[ -n "$rid" ]]; then
    app-store-connect bundle-ids enable-capabilities "$rid" --capability "App Groups" >>"$LOG" 2>&1 \
      && echo "  App Groups capability enabled" | tee -a "$LOG"
  fi
  fetch_profile "$id" || { echo "Could not get a profile for $id:"; clean < "$LOG" | tail -n 15; exit 1; }
  if [[ "$(profile_status "$id")" != "OK" && -n "$rid" ]]; then
    # A profile made before the App Group was attached never picks it up: recreate it.
    app-store-connect bundle-ids profiles --bundle-ids "$rid" --type IOS_APP_STORE --json > "$OUT/profiles.json" 2>>"$LOG" || true
    for pid in $(python3 -c 'import json,sys; print(" ".join(p["id"] for p in json.load(open(sys.argv[1])) if p["attributes"].get("profileType") == "IOS_APP_STORE"))' "$OUT/profiles.json" 2>/dev/null); do
      app-store-connect profiles delete "$pid" >>"$LOG" 2>&1 && echo "  Deleted stale profile $pid" | tee -a "$LOG"
    done
    rm -f "${PROFILE_DIRS[0]}"/*.mobileprovision "${PROFILE_DIRS[1]}"/*.mobileprovision
    fetch_profile "$id" || true
    for other in "$APP" "$WIDGETS"; do [[ "$other" == "$id" ]] || fetch_profile "$other" || true; done
  fi
  st=$(profile_status "$id")
  echo "  App Store profile for $id: App Group $GROUP $st" | tee -a "$LOG"
  [[ "$st" == "OK" ]] || need_portal=1
done

# Apple Watch app: its own bundle ID and App Store profile; it talks to the phone through
# WatchConnectivity, so it needs no App Group.
wrid=$(bundle_rid "$WATCH")
if [[ -z "$wrid" ]]; then
  app-store-connect bundle-ids create "$WATCH" --name "ZIKR Watch" --platform IOS --json > "$OUT/bid.json" 2>>"$LOG" || true
  echo "Registered bundle ID $WATCH" | tee -a "$LOG"
else
  echo "Bundle ID $WATCH exists ($wrid)" | tee -a "$LOG"
fi
fetch_profile "$WATCH" || { echo "Could not get a profile for $WATCH:"; clean < "$LOG" | tail -n 15; exit 1; }
echo "  App Store profile for $WATCH: OK" | tee -a "$LOG"

if [[ $need_portal -eq 1 ]]; then
  cat <<MSG | tee -a "$LOG"

One-time step needed in the Apple Developer portal (Apple's API cannot do it):
  1. developer.apple.com > Certificates, Identifiers & Profiles > Identifiers > App Groups > +
     Identifier: $GROUP
  2. Identifiers > App IDs > $APP > App Groups > Configure > tick $GROUP > Save.
  3. The same for $WIDGETS.
  Then rerun the build: stale profiles are recreated automatically.
MSG
  exit 2
fi

xcode-project use-profiles --export-options-plist "$OUT/ExportOptions-manual.plist" >>"$LOG" 2>&1 \
  || { echo "use-profiles failed:"; clean < "$LOG" | tail -n 20; exit 1; }
echo "Signing settings applied." | tee -a "$LOG"
