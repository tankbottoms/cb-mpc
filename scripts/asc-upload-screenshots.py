#!/usr/bin/env python3
"""Upload screenshots to App Store Connect.

Usage:
    python3 scripts/asc-upload-screenshots.py

Requires: PyJWT, cryptography
    pip3 install PyJWT cryptography
"""

import glob
import hashlib
import json
import os
import subprocess
import sys
import time

import jwt

# --- Config from .env ---
PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

env_file = os.path.join(PROJECT_DIR, ".env")
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ[k] = v

ASC_KEY_ID = os.environ["ASC_KEY_ID"]
ASC_ISSUER_ID = os.environ["ASC_ISSUER_ID"]
ASC_KEY_FILE = os.environ["ASC_KEY_FILE"]
APP_ID = os.environ.get("APP_ID", "6760239004")

BASE = "https://api.appstoreconnect.apple.com/v1"
SCREENSHOT_DIR = os.path.join(PROJECT_DIR, "docs", "iOS-AppStore")
DISPLAY_TYPE = "APP_IPHONE_67"  # iPhone 6.7" (iPhone 15 Pro Max)


def generate_token():
    key = open(ASC_KEY_FILE).read()
    return jwt.encode(
        {
            "iss": ASC_ISSUER_ID,
            "iat": int(time.time()),
            "exp": int(time.time()) + 1200,
            "aud": "appstoreconnect-v1",
        },
        key,
        algorithm="ES256",
        headers={"kid": ASC_KEY_ID},
    )


def api(method, path, data=None, token=None):
    if token is None:
        token = generate_token()
    headers = [
        "-H", f"Authorization: Bearer {token}",
        "-H", "Content-Type: application/json",
    ]
    cmd = ["curl", "-s", "--connect-timeout", "15", "-X", method, f"{BASE}{path}"] + headers
    if data:
        cmd += ["-d", json.dumps(data)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.stdout.strip():
        try:
            return json.loads(r.stdout)
        except json.JSONDecodeError:
            print(f"  Non-JSON response: {r.stdout[:200]}")
            return {}
    return {}


def upload_binary(upload_ops, file_path):
    """Execute the upload operations returned by ASC."""
    with open(file_path, "rb") as f:
        file_data = f.read()

    for op in upload_ops:
        method = op["method"]
        url = op["url"]
        headers_list = op.get("requestHeaders", [])
        offset = op.get("offset", 0)
        length = op.get("length", len(file_data))

        chunk = file_data[offset : offset + length]

        cmd = ["curl", "-s", "--connect-timeout", "30", "-X", method, url]
        for h in headers_list:
            cmd += ["-H", f"{h['name']}: {h['value']}"]
        cmd += ["--data-binary", "@-"]

        r = subprocess.run(cmd, input=chunk, capture_output=True)
        if r.returncode != 0:
            print(f"  Upload chunk failed: {r.stderr.decode()[:200]}")
            return False
    return True


def main():
    # Find screenshots
    pngs = sorted(glob.glob(os.path.join(SCREENSHOT_DIR, "IMG_*.PNG")))
    if not pngs:
        print("No screenshots found in", SCREENSHOT_DIR)
        sys.exit(1)

    print(f"Found {len(pngs)} screenshots to upload")

    token = generate_token()

    # Get the latest app store version
    print("Fetching latest app store version...")
    versions = api("GET", f"/apps/{APP_ID}/appStoreVersions?filter%5Bplatform%5D=IOS&limit=1", token=token)
    if not versions.get("data"):
        print("ERROR: No app store versions found")
        sys.exit(1)

    version_id = versions["data"][0]["id"]
    print(f"Version ID: {version_id}")

    # Get version localizations to find en-US
    locs = api("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", token=token)
    ver_loc_id = None
    for loc in locs.get("data", []):
        if loc["attributes"]["locale"] == "en-US":
            ver_loc_id = loc["id"]
            break

    if not ver_loc_id:
        print("ERROR: No en-US localization found")
        sys.exit(1)

    print(f"Version Localization ID: {ver_loc_id}")

    # Check for existing screenshot sets
    sets = api("GET", f"/appStoreVersionLocalizations/{ver_loc_id}/appScreenshotSets", token=token)
    set_id = None
    for s in sets.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            set_id = s["id"]
            break

    if not set_id:
        print(f"Creating {DISPLAY_TYPE} screenshot set...")
        result = api("POST", "/appScreenshotSets", {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {
                        "data": {"type": "appStoreVersionLocalizations", "id": ver_loc_id}
                    }
                },
            }
        }, token=token)
        if "errors" in result:
            print("ERROR creating set:", json.dumps(result["errors"], indent=2))
            sys.exit(1)
        set_id = result["data"]["id"]
        print(f"Created set: {set_id}")
    else:
        print(f"Using existing set: {set_id}")

    # Check for existing screenshots in the set
    existing = api("GET", f"/appScreenshotSets/{set_id}/appScreenshots?limit=30", token=token)
    existing_names = set()
    if existing.get("data"):
        for ss in existing["data"]:
            fn = ss["attributes"].get("fileName", "")
            existing_names.add(fn)
        print(f"  {len(existing_names)} screenshots already in set: {existing_names}")

    # Upload each screenshot
    # ASC limits to 10 screenshots per set — we'll upload the first 10
    MAX_SCREENSHOTS = 10
    uploaded = 0

    for png_path in pngs:
        if uploaded >= MAX_SCREENSHOTS:
            print(f"\nReached ASC limit of {MAX_SCREENSHOTS} screenshots per set. Skipping remaining.")
            break

        filename = os.path.basename(png_path)
        if filename in existing_names:
            print(f"\n[SKIP] {filename} — already uploaded")
            uploaded += 1
            continue

        file_size = os.path.getsize(png_path)

        # Compute MD5 checksum
        with open(png_path, "rb") as f:
            md5 = hashlib.md5(f.read()).hexdigest()

        print(f"\n[{uploaded + 1}/{min(len(pngs), MAX_SCREENSHOTS)}] {filename} ({file_size:,} bytes)")

        # Step 1: Reserve the screenshot
        token = generate_token()  # refresh token for each upload
        reserve = api("POST", "/appScreenshots", {
            "data": {
                "type": "appScreenshots",
                "attributes": {
                    "fileName": filename,
                    "fileSize": file_size,
                },
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        }, token=token)

        if "errors" in reserve:
            print(f"  ERROR reserving: {json.dumps(reserve['errors'], indent=2)}")
            continue

        if "data" not in reserve:
            print(f"  ERROR: Unexpected response: {json.dumps(reserve)[:200]}")
            continue

        screenshot_id = reserve["data"]["id"]
        upload_ops = reserve["data"]["attributes"].get("uploadOperations", [])
        print(f"  Reserved: {screenshot_id}")
        print(f"  Upload operations: {len(upload_ops)}")

        if not upload_ops:
            print("  ERROR: No upload operations returned")
            continue

        # Step 2: Upload the binary data
        print("  Uploading binary...")
        if not upload_binary(upload_ops, png_path):
            print("  ERROR: Binary upload failed")
            continue

        # Step 3: Confirm the upload
        print("  Confirming upload...")
        confirm = api("PATCH", f"/appScreenshots/{screenshot_id}", {
            "data": {
                "type": "appScreenshots",
                "id": screenshot_id,
                "attributes": {
                    "sourceFileChecksum": md5,
                    "uploaded": True,
                },
            }
        }, token=token)

        if "errors" in confirm:
            print(f"  ERROR confirming: {json.dumps(confirm['errors'], indent=2)}")
        else:
            state = confirm.get("data", {}).get("attributes", {}).get("assetDeliveryState", {})
            print(f"  OK — state: {state.get('state', 'unknown')}")
            uploaded += 1

    print(f"\nDone. {uploaded} screenshots uploaded to set {set_id}")


if __name__ == "__main__":
    main()
