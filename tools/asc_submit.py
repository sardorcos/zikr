#!/usr/bin/env python3
"""App Store Connect: apply metadata, screenshots and review details from appstore/metadata.json,
attach the newest processed build and (with --submit) send the version to App Review.

Runs in Codemagic with the App Store Connect integration (APP_STORE_CONNECT_KEY_IDENTIFIER,
APP_STORE_CONNECT_ISSUER_ID, APP_STORE_CONNECT_PRIVATE_KEY — the key may be "@file:" / "@env:").
Review contact comes from REVIEW_FIRST_NAME, REVIEW_LAST_NAME, REVIEW_PHONE, REVIEW_EMAIL
(secure variables, never committed). Idempotent: every step reads the current state first.

Usage: python3 tools/asc_submit.py appstore/metadata.json [--submit]
"""
import base64
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
SCREENSHOT_TYPE = "APP_IPHONE_67"  # the 6.7"/6.9" slot; accepts 1320 x 2868
# Apple Watch screenshot slots by pixel size (one watch size is enough for the listing).
WATCH_TYPES = {(416, 496): "APP_WATCH_SERIES_10", (422, 514): "APP_WATCH_ULTRA", (410, 502): "APP_WATCH_ULTRA",
               (396, 484): "APP_WATCH_SERIES_7", (368, 448): "APP_WATCH_SERIES_4", (312, 390): "APP_WATCH_SERIES_3"}


def png_size(path):
    data = pathlib.Path(path).read_bytes()[:24]
    return int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")


def log(msg: str) -> None:
    print(msg, flush=True)


# ------------------------------------------------------------------ auth

def private_key_pem() -> str:
    raw = os.environ["APP_STORE_CONNECT_PRIVATE_KEY"].strip().strip('"').strip("'")
    for _ in range(3):
        if raw.startswith("@file:"):
            raw = pathlib.Path(raw[6:]).expanduser().read_text().strip()
        elif raw.startswith("@env:"):
            raw = os.environ.get(raw[5:], "").strip()
    raw = raw.replace("\\n", "\n").replace("\r", "")
    m = re.search(r"-----BEGIN ([A-Z ]+)-----(.*?)-----END \1-----", raw, re.S)
    label, body = (m.group(1), m.group(2)) if m else ("PRIVATE KEY", raw)
    body = re.sub(r"[^A-Za-z0-9+/=]", "", body)
    return f"-----BEGIN {label}-----\n" + "\n".join(body[i:i + 64] for i in range(0, len(body), 64)) + f"\n-----END {label}-----\n"


def make_token() -> str:
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

    key = serialization.load_pem_private_key(private_key_pem().encode(), password=None)
    b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
    header = {"alg": "ES256", "kid": os.environ["APP_STORE_CONNECT_KEY_IDENTIFIER"], "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64(json.dumps(header).encode())}.{b64(json.dumps(payload).encode())}".encode()
    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    return signing_input.decode() + "." + b64(r.to_bytes(32, "big") + s.to_bytes(32, "big"))


class APIError(RuntimeError):
    def __init__(self, message, status, body):
        super().__init__(message)
        self.status, self.body = status, body

    def errors(self):
        try:
            return json.loads(self.body).get("errors", [])
        except Exception:
            return []


class ASC:
    def __init__(self):
        self.token, self.made = make_token(), time.time()

    def call(self, method: str, path: str, body=None, ok_missing=False):
        if time.time() - self.made > 600:
            self.token, self.made = make_token(), time.time()
        url = path if path.startswith("http") else API + path
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                txt = r.read().decode()
                return json.loads(txt) if txt else {}
        except urllib.error.HTTPError as e:
            txt = e.read().decode()
            if ok_missing and e.code == 404:
                return None
            raise APIError(f"{method} {path} -> {e.code}: {txt[:1500]}", e.code, txt) from None

    def get(self, path, **kw):
        return self.call("GET", path, **kw)

    def all(self, path):
        out, url = [], path
        while url:
            r = self.get(url)
            out += r.get("data", [])
            url = (r.get("links") or {}).get("next")
        return out


def rel(type_: str, id_: str):
    return {"data": {"type": type_, "id": id_}}


# ------------------------------------------------------------------ steps

def find_app(asc: ASC, bundle_id: str):
    apps = asc.get(f"/v1/apps?filter[bundleId]={urllib.parse.quote(bundle_id)}")["data"]
    if not apps:
        raise SystemExit(f"No App Store Connect app with bundle ID {bundle_id}")
    app = apps[0]
    log(f"App: {app['attributes']['name']} ({app['id']}), primary locale {app['attributes'].get('primaryLocale')}")
    return app


def set_content_rights(asc, app):
    if app["attributes"].get("contentRightsDeclaration") != "DOES_NOT_USE_THIRD_PARTY_CONTENT":
        asc.call("PATCH", f"/v1/apps/{app['id']}", {"data": {"type": "apps", "id": app["id"], "attributes": {
            "contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})
        log("Content rights: does not use third-party content")


def editable_app_info(asc, app):
    infos = asc.all(f"/v1/apps/{app['id']}/appInfos")
    for state_key in ("appStoreState", "state"):
        for i in infos:
            if i["attributes"].get(state_key) not in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE", "REPLACED_WITH_NEW_INFO"):
                return i
    return infos[0]


def apply_app_info(asc, app, meta):
    info = editable_app_info(asc, app)
    rels = {"primaryCategory": rel("appCategories", meta["primaryCategory"])}
    if meta.get("secondaryCategory"):
        rels["secondaryCategory"] = rel("appCategories", meta["secondaryCategory"])
    asc.call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": rels}})
    log(f"Categories: {meta['primaryCategory']} / {meta.get('secondaryCategory')}")
    existing = {l["attributes"]["locale"]: l for l in asc.all(f"/v1/appInfos/{info['id']}/appInfoLocalizations")}
    for locale, loc in meta["locales"].items():
        attrs = {k: loc[k] for k in ("name", "subtitle") if k in loc}
        attrs["privacyPolicyUrl"] = meta["privacyPolicyUrl"]
        if locale in existing:
            asc.call("PATCH", f"/v1/appInfoLocalizations/{existing[locale]['id']}", {"data": {
                "type": "appInfoLocalizations", "id": existing[locale]["id"], "attributes": attrs}})
        else:
            attrs["locale"] = locale
            asc.call("POST", "/v1/appInfoLocalizations", {"data": {"type": "appInfoLocalizations", "attributes": attrs,
                                                                    "relationships": {"appInfo": rel("appInfos", info["id"])}}})
        log(f"App info [{locale}]: {attrs.get('name')} — {attrs.get('subtitle')}")
    return info


AGE_SKIP = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride",
            "developerAgeRatingInfoUrl", "gracRatingClassificationNumber"}


def age_rating_skipped(key):
    # Region-specific overrides and classification numbers stay unset (Apple derives them).
    k = key.lower()
    return key in AGE_SKIP or "override" in k or "classification" in k or k.endswith("url")


def apply_age_rating(asc, info):
    """Answers every question with "none"/"no" (4+). Attribute types differ between API revisions,
    so the type of each attribute is corrected from Apple's validation errors and retried."""
    decl = asc.get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    attrs = {k: (False if isinstance(v, bool) else "NONE") for k, v in decl["attributes"].items() if not age_rating_skipped(k)}
    for _ in range(6):
        try:
            asc.call("PATCH", f"/v1/ageRatingDeclarations/{decl['id']}", {"data": {"type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
            log("Age rating: all content descriptors NONE / No (4+)")
            return
        except APIError as e:
            fixed = False
            for err in e.errors():
                key = (err.get("source") or {}).get("pointer", "").rsplit("/", 1)[-1]
                detail = err.get("detail", "")
                if key not in attrs:
                    continue
                if "Expected a BOOLEAN" in detail:
                    attrs[key], fixed = False, True
                elif "Expected a STRING" in detail or "Expected an ENUM" in detail.upper():
                    attrs[key], fixed = "NONE", True
                elif ("is not a valid" in detail or "not allowed" in detail or "cannot be set" in detail
                      or err.get("code", "").startswith("STATE_ERROR")):
                    attrs.pop(key)
                    fixed = True
            if not fixed:
                raise


def apply_free_price(asc, app):
    schedule = asc.get(f"/v1/apps/{app['id']}/appPriceSchedule", ok_missing=True)
    if schedule and schedule.get("data"):
        manual = asc.get(f"/v1/appPriceSchedules/{schedule['data']['id']}/manualPrices?include=appPricePoint", ok_missing=True) or {}
        if manual.get("data"):
            log("Price schedule already set")
            return
    points = asc.get(f"/v1/apps/{app['id']}/appPricePoints?filter[territory]=USA&limit=200")["data"]
    free = next(p for p in points if float(p["attributes"].get("customerPrice", "1") or 1) == 0.0)
    asc.call("POST", "/v1/appPriceSchedules", {
        "data": {"type": "appPriceSchedules", "relationships": {
            "app": rel("apps", app["id"]), "baseTerritory": rel("territories", "USA"),
            "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]}}},
        "included": [{"type": "appPrices", "id": "${price1}", "attributes": {"startDate": None},
                      "relationships": {"appPricePoint": rel("appPricePoints", free["id"])}}]})
    log("Price: free")


def apply_availability(asc, app):
    existing = asc.get(f"/v1/apps/{app['id']}/appAvailabilityV2", ok_missing=True)
    if existing and existing.get("data"):
        log("Availability already set")
        return
    territories = [t["id"] for t in asc.all("/v1/territories?limit=200")]
    included, refs = [], []
    for i, t in enumerate(territories):
        tid = f"${{t{i}}}"
        refs.append({"type": "territoryAvailabilities", "id": tid})
        included.append({"type": "territoryAvailabilities", "id": tid, "attributes": {"available": True},
                         "relationships": {"territory": rel("territories", t)}})
    asc.call("POST", "/v2/appAvailabilities", {"data": {"type": "appAvailabilities", "attributes": {"availableInNewTerritories": True},
                                                        "relationships": {"app": rel("apps", app["id"]), "territoryAvailabilities": {"data": refs}}},
                                               "included": included})
    log(f"Availability: {len(territories)} territories + new ones")


def ensure_version(asc, app, meta):
    versions = asc.all(f"/v1/apps/{app['id']}/appStoreVersions?filter[platform]=IOS")
    editable = [v for v in versions if v["attributes"].get("appStoreState") in (
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")]
    attrs = {"versionString": meta["version"], "copyright": meta["copyright"], "releaseType": "AFTER_APPROVAL"}
    if editable:
        v = editable[0]
        asc.call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": attrs}})
    else:
        v = asc.call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {**attrs, "platform": "IOS"},
                                                                "relationships": {"app": rel("apps", app["id"])}}})["data"]
    log(f"Version {meta['version']} ({v['id']}), state {v['attributes'].get('appStoreState')}")
    return v


def apply_version_localizations(asc, version, meta, base_dir):
    existing = {l["attributes"]["locale"]: l for l in asc.all(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")}
    result = {}
    for locale, loc in meta["locales"].items():
        attrs = {k: loc[k] for k in ("description", "keywords", "promotionalText") if k in loc}
        attrs["supportUrl"] = meta["supportUrl"]
        if meta.get("marketingUrl"):
            attrs["marketingUrl"] = meta["marketingUrl"]
        if locale in existing:
            lid = existing[locale]["id"]
            asc.call("PATCH", f"/v1/appStoreVersionLocalizations/{lid}", {"data": {"type": "appStoreVersionLocalizations", "id": lid, "attributes": attrs}})
        else:
            lid = asc.call("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations", "attributes": {**attrs, "locale": locale},
                "relationships": {"appStoreVersion": rel("appStoreVersions", version["id"])}}})["data"]["id"]
        log(f"Version text [{locale}]: description {len(attrs.get('description', ''))} chars, keywords {len(attrs.get('keywords', ''))} chars")
        result[locale] = lid
        shots = sorted((base_dir / loc["screenshots"]).glob("*.png")) if loc.get("screenshots") else []
        if shots:
            upload_screenshots(asc, lid, shots, SCREENSHOT_TYPE)
        watch = sorted((base_dir / loc["watchScreenshots"]).glob("*.png")) if loc.get("watchScreenshots") else []
        if watch:
            size = png_size(watch[0])
            if size not in WATCH_TYPES:
                raise SystemExit(f"Unsupported Apple Watch screenshot size {size}")
            upload_screenshots(asc, lid, watch, WATCH_TYPES[size])
    return result


def upload_screenshots(asc, loc_id, files, display_type):
    sets = asc.all(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display_type), None)
    if not sset:
        sset = asc.call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type},
                                                                  "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", loc_id)}}})["data"]
    current = asc.all(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")
    wanted = [(f.name, hashlib.md5(f.read_bytes()).hexdigest()) for f in files]
    have = [(s["attributes"].get("fileName"), s["attributes"].get("sourceFileChecksum")) for s in current]
    if have == wanted:
        log(f"  {display_type}: screenshots up to date ({len(files)})")
        return
    for s in current:
        asc.call("DELETE", f"/v1/appScreenshots/{s['id']}")
    for f in files:
        data = f.read_bytes()
        shot = asc.call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
                                                               "relationships": {"appScreenshotSet": rel("appScreenshotSets", sset["id"])}}})["data"]
        for op in shot["attributes"]["uploadOperations"]:
            chunk = data[op["offset"]:op["offset"] + op["length"]]
            req = urllib.request.Request(op["url"], data=chunk, method=op["method"],
                                         headers={h["name"]: h["value"] for h in op.get("requestHeaders", [])})
            urllib.request.urlopen(req, timeout=300).read()
        asc.call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"], "attributes": {
            "uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    # Wait for Apple to process them.
    for _ in range(60):
        states = [s["attributes"].get("assetDeliveryState", {}).get("state") for s in asc.all(f"/v1/appScreenshotSets/{sset['id']}/appScreenshots")]
        if all(st == "COMPLETE" for st in states):
            break
        if any(st == "FAILED" for st in states):
            raise RuntimeError(f"Screenshot processing failed: {states}")
        time.sleep(5)
    log(f"  {display_type}: uploaded {len(files)} screenshots")


def attach_build(asc, app, version, meta):
    builds = asc.all(f"/v1/builds?filter[app]={app['id']}&filter[preReleaseVersion.version]={meta['version']}"
                     f"&filter[processingState]=VALID&sort=-uploadedDate&limit=20")
    builds = [b for b in builds if not b["attributes"].get("expired")]
    if not builds:
        raise SystemExit(f"No processed build for version {meta['version']} — upload one first")
    b = builds[0]
    if b["attributes"].get("usesNonExemptEncryption") is None:
        asc.call("PATCH", f"/v1/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
    asc.call("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
    log(f"Build attached: {b['attributes']['version']} ({b['id']})")


def apply_review_detail(asc, version, meta):
    contact = {k: os.environ.get(e, "").strip() for k, e in (
        ("contactFirstName", "REVIEW_FIRST_NAME"), ("contactLastName", "REVIEW_LAST_NAME"),
        ("contactPhone", "REVIEW_PHONE"), ("contactEmail", "REVIEW_EMAIL"))}
    attrs = {"demoAccountRequired": False, "notes": meta["reviewNotes"]}
    if all(contact.values()):
        attrs.update(contact)
    else:
        log("Review contact not provided (REVIEW_* variables) — only notes are set")
    current = asc.get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail", ok_missing=True)
    if current and current.get("data"):
        rid = current["data"]["id"]
        asc.call("PATCH", f"/v1/appStoreReviewDetails/{rid}", {"data": {"type": "appStoreReviewDetails", "id": rid, "attributes": attrs}})
    else:
        asc.call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                                                               "relationships": {"appStoreVersion": rel("appStoreVersions", version["id"])}}})
    log("Review details set")
    return all(contact.values())


def submit(asc, app, version):
    open_subs = [s for s in asc.all(f"/v1/reviewSubmissions?filter[app]={app['id']}&filter[platform]=IOS")
                 if s["attributes"].get("state") in ("READY_FOR_REVIEW", "UNRESOLVED_ISSUES")]
    sub = open_subs[0] if open_subs else asc.call("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"}, "relationships": {"app": rel("apps", app["id"])}}})["data"]
    items = asc.all(f"/v1/reviewSubmissions/{sub['id']}/items")
    if not items:
        asc.call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
            "reviewSubmission": rel("reviewSubmissions", sub["id"]), "appStoreVersion": rel("appStoreVersions", version["id"])}}})
    asc.call("PATCH", f"/v1/reviewSubmissions/{sub['id']}", {"data": {"type": "reviewSubmissions", "id": sub["id"], "attributes": {"submitted": True}}})
    log(f"SUBMITTED for App Review (submission {sub['id']})")


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    meta_path = pathlib.Path(sys.argv[1])
    meta = json.loads(meta_path.read_text())
    do_submit = "--submit" in sys.argv
    asc = ASC()
    app = find_app(asc, meta["bundleId"])
    steps = [
        ("content rights", lambda: set_content_rights(asc, app)),
    ]
    for name, fn in steps:
        fn()
    info = apply_app_info(asc, app, meta)
    failures = []
    for name, fn in (("age rating", lambda: apply_age_rating(asc, info)), ("price", lambda: apply_free_price(asc, app)),
                     ("availability", lambda: apply_availability(asc, app))):
        try:
            fn()
        except Exception as e:  # keep going: report everything at the end
            failures.append(f"{name}: {e}")
            log(f"!! {name} failed: {e}")
    version = ensure_version(asc, app, meta)
    apply_version_localizations(asc, version, meta, meta_path.parent)
    attach_build(asc, app, version, meta)
    has_contact = apply_review_detail(asc, version, meta)
    if failures:
        log("Steps needing attention:\n  " + "\n  ".join(failures))
    if do_submit:
        if not has_contact:
            raise SystemExit("Cannot submit: review contact (REVIEW_FIRST_NAME/LAST_NAME/PHONE/EMAIL) is missing")
        submit(asc, app, version)
    else:
        log("Metadata applied. Run with --submit to send for review.")


if __name__ == "__main__":
    main()
