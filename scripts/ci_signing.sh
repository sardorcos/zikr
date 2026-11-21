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
CERT_DIR="$HOME/Library/MobileDevice/Certificates"
p12_count() { ls "$CERT_DIR"/*.p12 2>/dev/null | wc -l | tr -d ' '; }
for type in DEVELOPMENT DISTRIBUTION; do
  before=$(p12_count)
  # `list` prints every certificate of the type; only ones matching the key are saved as .p12.
  app-store-connect certificates list --type "$type" --certificate-key @env:CERTIFICATE_PRIVATE_KEY --save \
    > "$OUT/cert-$type.log" 2>&1 || true
  if [[ "$(p12_count)" -gt "$before" ]] && ! grep -q "Did not find any Signing Certificates for given private key" "$OUT/cert-$type.log"; then
    echo "$type certificate: reused"
  elif app-store-connect certificates create --type "$type" --certificate-key @env:CERTIFICATE_PRIVATE_KEY --save \
         >> "$OUT/cert-$type.log" 2>&1 && [[ "$(p12_count)" -gt "$before" ]]; then
    echo "$type certificate: created"
  else
    echo "$type certificate: could not be created — see $OUT/cert-$type.log"
    sed 's/\x1b\[[0-9;]*m//g' "$OUT/cert-$type.log" | tail -n 8
  fi
done
ls -la "$CERT_DIR" 2>/dev/null | tee -a "$OUT/identities.log"
keychain add-certificates
security find-identity -v -p codesigning | tee -a "$OUT/identities.log"
app-store-connect devices list --json > "$OUT/devices.json" 2>/dev/null \
  && python3 -c 'import json,sys; print("Registered devices:", len(json.load(open(sys.argv[1]))))' "$OUT/devices.json" | tee -a "$OUT/identities.log" || true
