#!/usr/bin/env python3
"""Fetch TestFlight crash feedback for com.eugenechan.lfg from the ASC API. Read-only (GET only)."""
import base64
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import jwt  # PyJWT

ENV_FILE = "/Users/eugenechan/dev/personal/lfg/ios/fastlane/.env.local"
OUT_DIR = "/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/a6e042ef-fe15-4bac-b0a6-e2e0cdcbf1f8/scratchpad/testflight-crashes"
BUNDLE_ID = "com.eugenechan.lfg"
API = "https://api.appstoreconnect.apple.com"

def load_creds():
    kv = {}
    with open(ENV_FILE) as f:
        for line in f:
            line = line.strip()
            if "=" in line and not line.startswith("#"):
                k, _, v = line.partition("=")
                kv[k] = v
    key_id = kv["APP_STORE_CONNECT_API_KEY_ID"]
    issuer = kv["APP_STORE_CONNECT_API_ISSUER_ID"]
    p8 = base64.b64decode(kv["APP_STORE_CONNECT_API_KEY_BASE64"]).decode()
    return key_id, issuer, p8

def mint_token(key_id, issuer, p8):
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        p8,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )

def get(url, token, raw=False):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            body = r.read()
            return r.status, body if raw else json.loads(body)
    except urllib.error.HTTPError as e:
        body = e.read()
        try:
            parsed = json.loads(body)
        except Exception:
            parsed = body.decode(errors="replace")[:500]
        return e.code, parsed

def main():
    key_id, issuer, p8 = load_creds()
    token = mint_token(key_id, issuer, p8)
    tried = []

    # Step 1: app id
    status, data = get(f"{API}/v1/apps?filter[bundleId]={BUNDLE_ID}", token)
    tried.append((f"/v1/apps?filter[bundleId]={BUNDLE_ID}", status))
    if status != 200 or not data.get("data"):
        print(json.dumps({"error": "app lookup failed", "tried": tried, "resp": data}, indent=2))
        return
    app_id = data["data"][0]["id"]
    print(f"APP_ID={app_id}")

    # Step 2: crash submissions
    fields = "fields[betaFeedbackCrashSubmissions]=createdDate,comment,email,deviceModel,osVersion,locale,timeZone,appPlatform,devicePlatform,deviceFamily,buildBundleId,crashLog"
    candidates = [
        f"{API}/v1/apps/{app_id}/betaFeedbackCrashSubmissions?{fields}&limit=200&sort=-createdDate",
        f"{API}/v1/apps/{app_id}/betaFeedbackCrashSubmissions?limit=200",
        f"{API}/v1/betaFeedbackCrashSubmissions?filter[app]={app_id}&limit=200",
    ]
    subs = None
    for url in candidates:
        status, data = get(url, token)
        path = url.replace(API, "").split("&limit")[0]
        tried.append((path, status))
        if status == 200:
            subs = data
            # paginate
            all_rows = data.get("data", [])
            included = data.get("included", [])
            next_url = data.get("links", {}).get("next")
            while next_url:
                s2, d2 = get(next_url, token)
                if s2 != 200:
                    break
                all_rows += d2.get("data", [])
                included += d2.get("included", [])
                next_url = d2.get("links", {}).get("next")
            subs["data"] = all_rows
            subs["included"] = included
            break

    if subs is None:
        # inspect app relationships for hints
        s3, d3 = get(f"{API}/v1/apps/{app_id}", token)
        tried.append((f"/v1/apps/{app_id}", s3))
        rels = list(d3.get("data", {}).get("relationships", {}).keys()) if s3 == 200 else []
        print(json.dumps({"error": "no crash feedback endpoint worked", "tried": tried, "app_relationships": rels}, indent=2))
        return

    rows = subs["data"]
    print(f"SUBMISSIONS={len(rows)}")
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(os.path.join(OUT_DIR, "all-submissions.json"), "w") as f:
        json.dump(subs, f, indent=2)

    summary = []
    for row in rows:
        attrs = row.get("attributes", {})
        created = attrs.get("createdDate", "unknown")
        device = attrs.get("deviceModel", "unknown")
        safe_created = re.sub(r"[^0-9TZ-]", "", created)
        safe_device = re.sub(r"[^A-Za-z0-9_.-]", "_", str(device))
        base = f"{safe_created}_{safe_device}_{row['id'][:8]}"
        with open(os.path.join(OUT_DIR, base + ".json"), "w") as f:
            json.dump(row, f, indent=2)

        # crash log: attribute may embed it, else fetch relationship
        log_status, log_note = None, None
        crash_log = attrs.get("crashLog")
        log_text = None
        if isinstance(crash_log, dict):
            # e.g. {"url": ...} or {"crashLogUrl": ...}
            url = crash_log.get("url") or crash_log.get("crashLogUrl")
            if url:
                log_status, body = get(url, token, raw=True)
                if log_status == 200:
                    log_text = body.decode(errors="replace")
        elif isinstance(crash_log, str):
            log_text = crash_log
        if log_text is None:
            # relationship endpoint
            s, d = get(f"{API}/v1/betaFeedbackCrashSubmissions/{row['id']}/crashLog", token)
            log_status = s
            if s == 200:
                la = d.get("data", {}).get("attributes", {})
                url = la.get("crashLogUrl") or la.get("url")
                if url:
                    s2, body = get(url, token, raw=True)
                    if s2 == 200:
                        log_text = body.decode(errors="replace")
                    else:
                        log_note = f"download {s2}"
                else:
                    log_note = f"no url in crashLog attrs: {list(la.keys())}"
            else:
                log_note = f"crashLog rel status {s}"
        if log_text:
            with open(os.path.join(OUT_DIR, base + ".crash.txt"), "w") as f:
                f.write(log_text)
        summary.append({
            "id": row["id"], "created": created, "device": device,
            "os": attrs.get("osVersion"), "comment": attrs.get("comment"),
            "log_saved": log_text is not None, "log_note": log_note,
        })

    with open(os.path.join(OUT_DIR, "summary.json"), "w") as f:
        json.dump({"tried": tried, "count": len(rows), "submissions": summary}, f, indent=2)
    print(json.dumps({"tried": tried, "count": len(rows), "submissions": summary}, indent=2))

if __name__ == "__main__":
    main()
