#!/usr/bin/env bash
# One-time setup: writes your Apple Team ID, bundle identifier and public URLs into the project.
#   ./scripts/configure.sh TEAMID com.yourname.zikr https://you.github.io/zikr/privacy https://you.github.io/zikr/support
set -euo pipefail
TEAM_ID="${1:?Usage: configure.sh TEAM_ID BUNDLE_ID [PRIVACY_URL] [SUPPORT_URL]}"
BUNDLE_ID="${2:?Usage: configure.sh TEAM_ID BUNDLE_ID [PRIVACY_URL] [SUPPORT_URL]}"
PRIVACY_URL="${3:-}"
SUPPORT_URL="${4:-}"
cd "$(dirname "$0")/.."
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo "Team ID must be 10 characters (Xcode → Settings → Accounts)"; exit 1; }
[[ "$BUNDLE_ID" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid bundle identifier"; exit 1; }
python3 - "$TEAM_ID" "$BUNDLE_ID" "$PRIVACY_URL" "$SUPPORT_URL" <<'PY'
import re, sys, pathlib
team, bundle, privacy, support = sys.argv[1:5]
p = pathlib.Path("tools/gen_project.py")
s = p.read_text()
s = re.sub(r'"DEVELOPMENT_TEAM": "[^"]*"', f'"DEVELOPMENT_TEAM": "{team}"', s)
s = re.sub(r'"ZIKR_BUNDLE_ID": "[^"]*"', f'"ZIKR_BUNDLE_ID": "{bundle}"', s)
s = re.sub(r'"ZIKR_PRIVACY_URL": "[^"]*"', f'"ZIKR_PRIVACY_URL": "{privacy}"', s)
s = re.sub(r'"ZIKR_SUPPORT_URL": "[^"]*"', f'"ZIKR_SUPPORT_URL": "{support}"', s)
p.write_text(s)
PY
python3 tools/gen_project.py
echo "Configured: team $TEAM_ID, bundle $BUNDLE_ID, app group group.$BUNDLE_ID"
