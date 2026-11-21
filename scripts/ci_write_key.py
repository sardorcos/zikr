#!/usr/bin/env python3
"""Writes the App Store Connect private key from $APP_STORE_CONNECT_PRIVATE_KEY as a valid .p8 PEM.

CI systems hand the key over in different shapes: real PEM, PEM with literal "\\n", base64 of the
PEM, or the bare base64 body. xcodebuild only accepts real PEM.
Usage: ci_write_key.py OUTPUT_PATH
"""
import base64
import os
import re
import sys

raw = os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY", "").strip().strip('"').strip("'")
if not raw:
    sys.exit("APP_STORE_CONNECT_PRIVATE_KEY is empty")
source = "inline"
# codemagic-cli-tools style references: @file:/path or @env:NAME
for _ in range(3):
    if raw.startswith("@file:"):
        path = os.path.expanduser(raw[len("@file:"):])
        source = "file"
        raw = open(path).read().strip()
    elif raw.startswith("@env:"):
        source = "env:" + raw[len("@env:"):]
        raw = os.environ.get(raw[len("@env:"):], "").strip()
    else:
        break
diag = {"source": source, "length": len(raw), "starts": raw[:5] if raw[:1] in "-@" else "other",
        "has_begin": "BEGIN" in raw, "literal_backslash_n": "\\n" in raw, "newlines": raw.count("\n")}
key = raw.replace("\\n", "\n").replace("\r", "")
shape = "pem"
if "BEGIN" not in key:
    body = re.sub(r"\s+", "", key)
    try:
        decoded = base64.b64decode(body).decode("utf-8")
    except Exception:
        decoded = ""
    if "BEGIN" in decoded:
        key, shape = decoded, "base64-of-pem"
    else:
        key = "-----BEGIN PRIVATE KEY-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + "\n-----END PRIVATE KEY-----"
        shape = "bare-body"
else:
    # Re-flow a PEM whose line breaks were lost (header, body and footer on one line).
    m = re.search(r"-----BEGIN ([A-Z ]+)-----(.*?)-----END \1-----", key, re.S)
    if m:
        body = re.sub(r"\s+", "", m.group(2))
        key = f"-----BEGIN {m.group(1)}-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + f"\n-----END {m.group(1)}-----"
with open(sys.argv[1], "w") as f:
    f.write(key.strip() + "\n")
lines = key.strip().splitlines()
diag.update(shape=shape, lines=len(lines), header=lines[0][:31])
print("Key diagnostics:", diag)
os.makedirs("build", exist_ok=True)
with open("build/ci-key.log", "w") as f:
    f.write(repr(diag) + "\n")
