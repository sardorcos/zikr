#!/usr/bin/env bash
# CI: installs an Apple Development and an Apple Distribution certificate into a fresh keychain.
# Both belong to the persistent private key in $CERTIFICATE_PRIVATE_KEY (Codemagic secure
# variable), so the same certificates are reused on every ephemeral build machine instead of a
# new one being created per machine. Xcode's automatic signing then creates the provisioning
# profiles (with the App Group) itself.
set -uo pipefail
OUT="${1:-build}"; mkdir -p "$OUT"
: "${CERTIFICATE_PRIVATE_KEY:?CERTIFICATE_PRIVATE_KEY is not set (Codemagic group zikr_signing)}"
keychain initialize
for type in DEVELOPMENT DISTRIBUTION; do
  found=0
  if app-store-connect certificates list --type "$type" --certificate-key @env:CERTIFICATE_PRIVATE_KEY --save --json \
       > "$OUT/cert-$type.json" 2> "$OUT/cert-$type.err"; then
    found=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$OUT/cert-$type.json" 2>/dev/null || echo 0)
  fi
  if [[ "$found" != "0" ]]; then
    echo "$type certificate: reused"
  elif app-store-connect certificates create --type "$type" --certificate-key @env:CERTIFICATE_PRIVATE_KEY --save \
         >> "$OUT/cert-$type.err" 2>&1; then
    echo "$type certificate: created"
  else
    echo "$type certificate: could not be created — see $OUT/cert-$type.err"; tail -n 5 "$OUT/cert-$type.err"
  fi
done
keychain add-certificates
security find-identity -v -p codesigning | tee "$OUT/identities.log"
app-store-connect devices list --json > "$OUT/devices.json" 2>/dev/null \
  && python3 -c 'import json,sys; print("Registered devices:", len(json.load(open(sys.argv[1]))))' "$OUT/devices.json" | tee -a "$OUT/identities.log" || true
