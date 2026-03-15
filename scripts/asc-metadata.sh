#!/usr/bin/env bash
set -euo pipefail

# App Store Connect API — Programmatic Metadata Upload
#
# Prerequisites:
#   1. Create .env.json from .env.json.example and fill in values
#   2. Place your AuthKey .p8 file in private_keys/
#   3. Run ./scripts/validate-env.sh to verify
#
# Usage:
#   ./scripts/asc-metadata.sh [command]
#
# Commands:
#   token       — Generate a JWT token (prints to stdout)
#   info        — Fetch app info and localization IDs
#   upload      — Upload all metadata from fastlane/metadata/
#   age-rating  — Set age rating declaration
#   testflight  — Set TestFlight "What to Test" text
#   all         — Run upload + age-rating + testflight

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
METADATA_DIR="$PROJECT_DIR/fastlane/metadata"

# Source secrets from .env.json
source "$SCRIPT_DIR/env-helper.sh"
BASE_URL="https://api.appstoreconnect.apple.com/v1"

# --- JWT Token Generation ---

generate_token() {
  local key_id="${ASC_KEY_ID:?Set ASC_KEY_ID}"
  local issuer_id="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
  local key_file="${ASC_KEY_FILE:?Set ASC_KEY_FILE}"

  python3 -c "
import jwt, time
key = open('$key_file').read()
print(jwt.encode(
    {'iss': '$issuer_id', 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
    key, algorithm='ES256', headers={'kid': '$key_id'}
))
"
}

api() {
  local method="$1"
  local endpoint="$2"
  local token
  token=$(generate_token)
  shift 2

  curl -s -X "$method" \
    "$BASE_URL$endpoint" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "$@"
}

# --- Fetch App Info ---

cmd_info() {
  echo "=== App Info ==="
  api GET "/apps/$APP_ID?include=appInfos,appStoreVersions&fields[apps]=bundleId,name,sku" | python3 -m json.tool 2>/dev/null || cat

  echo ""
  echo "=== App Info Localizations ==="
  local app_info_id
  app_info_id=$(api GET "/apps/$APP_ID/appInfos?limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)
  echo "App Info ID: $app_info_id"

  api GET "/appInfos/$app_info_id/appInfoLocalizations" | python3 -m json.tool 2>/dev/null || cat
}

# --- Upload Metadata ---

cmd_upload() {
  echo "Fetching app info ID..."
  local app_info_id
  app_info_id=$(api GET "/apps/$APP_ID/appInfos?limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)
  echo "App Info ID: $app_info_id"

  echo "Fetching localization ID for en-US..."
  local loc_id
  loc_id=$(api GET "/appInfos/$app_info_id/appInfoLocalizations" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data['data']:
    if item['attributes']['locale'] == 'en-US':
        print(item['id'])
        break
" 2>/dev/null)
  echo "Localization ID: $loc_id"

  # Read metadata files
  local name subtitle privacy_url
  name=$(cat "$METADATA_DIR/en-US/name.txt" 2>/dev/null || echo "")
  subtitle=$(cat "$METADATA_DIR/en-US/subtitle.txt" 2>/dev/null || echo "")
  privacy_url=$(cat "$METADATA_DIR/en-US/privacy_url.txt" 2>/dev/null || echo "")

  echo "Updating app info localization..."
  local payload
  payload=$(python3 -c "
import json
data = {
    'data': {
        'type': 'appInfoLocalizations',
        'id': '$loc_id',
        'attributes': {}
    }
}
attrs = data['data']['attributes']
if '$name': attrs['name'] = '$name'
if '$subtitle': attrs['subtitle'] = '$subtitle'
if '$privacy_url': attrs['privacyPolicyUrl'] = '$privacy_url'
print(json.dumps(data))
")
  api PATCH "/appInfoLocalizations/$loc_id" -d "$payload"
  echo ""

  # Update categories via appInfos
  echo "Updating categories..."
  local cat_payload
  cat_payload=$(python3 -c "
import json
data = {
    'data': {
        'type': 'appInfos',
        'id': '$app_info_id',
        'relationships': {
            'primaryCategory': {
                'data': {'type': 'appCategories', 'id': 'UTILITIES'}
            },
            'secondaryCategory': {
                'data': {'type': 'appCategories', 'id': 'FINANCE'}
            }
        }
    }
}
print(json.dumps(data))
")
  api PATCH "/appInfos/$app_info_id" -d "$cat_payload"
  echo ""

  # Update App Store Version Localization (description, keywords, whatsNew)
  echo "Fetching latest app store version..."
  local version_id
  version_id=$(api GET "/apps/$APP_ID/appStoreVersions?filter[platform]=IOS&limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)
  echo "Version ID: $version_id"

  echo "Fetching version localization ID..."
  local ver_loc_id
  ver_loc_id=$(api GET "/appStoreVersions/$version_id/appStoreVersionLocalizations" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data['data']:
    if item['attributes']['locale'] == 'en-US':
        print(item['id'])
        break
" 2>/dev/null)
  echo "Version Localization ID: $ver_loc_id"

  local description keywords promo_text release_notes support_url
  description=$(cat "$METADATA_DIR/en-US/description.txt" 2>/dev/null || echo "")
  keywords=$(cat "$METADATA_DIR/en-US/keywords.txt" 2>/dev/null || echo "")
  promo_text=$(cat "$METADATA_DIR/en-US/promotional_text.txt" 2>/dev/null || echo "")
  release_notes=$(cat "$METADATA_DIR/en-US/release_notes.txt" 2>/dev/null || echo "")
  support_url=$(cat "$METADATA_DIR/en-US/support_url.txt" 2>/dev/null || echo "")

  echo "Updating version localization..."
  local ver_payload
  ver_payload=$(python3 -c "
import json, sys
desc = open('$METADATA_DIR/en-US/description.txt').read().strip()
data = {
    'data': {
        'type': 'appStoreVersionLocalizations',
        'id': '$ver_loc_id',
        'attributes': {
            'description': desc,
            'keywords': '$keywords',
            'promotionalText': '$promo_text',
            'whatsNew': '''$(cat "$METADATA_DIR/en-US/release_notes.txt")''',
            'supportUrl': '$support_url',
            'marketingUrl': '$support_url'
        }
    }
}
print(json.dumps(data))
")
  api PATCH "/appStoreVersionLocalizations/$ver_loc_id" -d "$ver_payload"
  echo ""
  echo "Metadata upload complete."
}

# --- Age Rating ---

cmd_age_rating() {
  echo "Fetching age rating declaration ID..."
  local app_info_id
  app_info_id=$(api GET "/apps/$APP_ID/appInfos?limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)

  local rating_id
  rating_id=$(api GET "/appInfos/$app_info_id/ageRatingDeclaration" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['id'])" 2>/dev/null)
  echo "Age Rating ID: $rating_id"

  local age_config
  age_config=$(cat "$METADATA_DIR/age_rating_config.json")

  local payload
  payload=$(python3 -c "
import json
config = json.loads('''$age_config''')
data = {
    'data': {
        'type': 'ageRatingDeclarations',
        'id': '$rating_id',
        'attributes': config
    }
}
print(json.dumps(data))
")
  echo "Setting age ratings to all-NONE..."
  api PATCH "/ageRatingDeclarations/$rating_id" -d "$payload"
  echo ""
  echo "Age rating updated."
}

# --- TestFlight What to Test ---

cmd_testflight() {
  echo "Fetching latest build..."
  local build_id
  build_id=$(api GET "/builds?filter[app]=$APP_ID&sort=-uploadedDate&limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)
  echo "Build ID: $build_id"

  echo "Fetching beta build localization..."
  local beta_loc_id
  beta_loc_id=$(api GET "/builds/$build_id/betaBuildLocalizations" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data['data']:
    if item['attributes']['locale'] == 'en-US':
        print(item['id'])
        break
" 2>/dev/null)

  if [ -z "$beta_loc_id" ]; then
    echo "Creating beta build localization for en-US..."
    local create_payload
    create_payload=$(python3 -c "
import json
data = {
    'data': {
        'type': 'betaBuildLocalizations',
        'attributes': {
            'locale': 'en-US',
            'whatsNew': '''$(cat "$METADATA_DIR/en-US/release_notes.txt")'''
        },
        'relationships': {
            'build': {
                'data': {'type': 'builds', 'id': '$build_id'}
            }
        }
    }
}
print(json.dumps(data))
")
    api POST "/betaBuildLocalizations" -d "$create_payload"
  else
    echo "Beta Build Localization ID: $beta_loc_id"
    local update_payload
    update_payload=$(python3 -c "
import json
data = {
    'data': {
        'type': 'betaBuildLocalizations',
        'id': '$beta_loc_id',
        'attributes': {
            'whatsNew': '''$(cat "$METADATA_DIR/en-US/release_notes.txt")'''
        }
    }
}
print(json.dumps(data))
")
    api PATCH "/betaBuildLocalizations/$beta_loc_id" -d "$update_payload"
  fi
  echo ""
  echo "TestFlight 'What to Test' updated."
}

# --- App Review Information ---

cmd_review_info() {
  echo "Fetching latest app store version..."
  local version_id
  version_id=$(api GET "/apps/$APP_ID/appStoreVersions?filter[platform]=IOS&limit=1" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null)
  echo "Version ID: $version_id"

  local first_name last_name phone email notes
  first_name=$(cat "$METADATA_DIR/review_information/first_name.txt" 2>/dev/null || echo "")
  last_name=$(cat "$METADATA_DIR/review_information/last_name.txt" 2>/dev/null || echo "")
  phone=$(cat "$METADATA_DIR/review_information/phone_number.txt" 2>/dev/null || echo "")
  email=$(cat "$METADATA_DIR/review_information/email_address.txt" 2>/dev/null || echo "")
  notes=$(cat "$METADATA_DIR/review_information/notes.txt" 2>/dev/null || echo "")

  echo "Fetching review detail ID..."
  local review_id
  review_id=$(api GET "/appStoreVersions/$version_id/appStoreReviewDetail" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['id'])" 2>/dev/null || echo "")

  local payload
  payload=$(python3 -c "
import json
notes_text = open('$METADATA_DIR/review_information/notes.txt').read().strip()
data = {
    'data': {
        'type': 'appStoreReviewDetails',
        'attributes': {
            'contactFirstName': '$first_name',
            'contactLastName': '$last_name',
            'contactPhone': '$phone',
            'contactEmail': '$email',
            'notes': notes_text,
            'demoAccountRequired': False
        }
    }
}
if '$review_id':
    data['data']['id'] = '$review_id'
print(json.dumps(data))
")

  if [ -n "$review_id" ]; then
    echo "Updating review information..."
    api PATCH "/appStoreReviewDetails/$review_id" -d "$payload"
  else
    echo "Creating review information..."
    payload=$(python3 -c "
import json
notes_text = open('$METADATA_DIR/review_information/notes.txt').read().strip()
data = {
    'data': {
        'type': 'appStoreReviewDetails',
        'attributes': {
            'contactFirstName': '$first_name',
            'contactLastName': '$last_name',
            'contactPhone': '$phone',
            'contactEmail': '$email',
            'notes': notes_text,
            'demoAccountRequired': False
        },
        'relationships': {
            'appStoreVersion': {
                'data': {'type': 'appStoreVersions', 'id': '$version_id'}
            }
        }
    }
}
print(json.dumps(data))
")
    api POST "/appStoreReviewDetails" -d "$payload"
  fi
  echo ""
  echo "Review information updated."
}

# --- Main ---

case "${1:-all}" in
  token)       generate_token; echo ;;
  info)        cmd_info ;;
  upload)      cmd_upload ;;
  age-rating)  cmd_age_rating ;;
  testflight)  cmd_testflight ;;
  review)      cmd_review_info ;;
  all)
    cmd_upload
    cmd_age_rating
    cmd_review_info
    echo ""
    echo "=== All metadata uploaded ==="
    echo "Next: Upload a build via Xcode, then run: $0 testflight"
    ;;
  *)
    echo "Usage: $0 {token|info|upload|age-rating|testflight|review|all}"
    exit 1
    ;;
esac