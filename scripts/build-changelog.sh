#!/usr/bin/env bash
set -euo pipefail

# Build Changelog Tracker
#
# Tracks changes between iOS builds and generates TestFlight metadata.
# Reads the last-pushed build tag, collects commits since then, and
# writes both human-readable changelog and ASC-ready "What to Test" text.
#
# Usage:
#   ./scripts/build-changelog.sh              # Show changes since last build
#   ./scripts/build-changelog.sh record       # Tag current build and save changelog
#   ./scripts/build-changelog.sh push         # Push "What to Test" to ASC (after build upload)
#   ./scripts/build-changelog.sh history       # Show all build changelogs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHANGELOG_DIR="$PROJECT_DIR/docs/iOS-AppStore/changelogs"
PBXPROJ="$PROJECT_DIR/CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj"

# Source .env
if [ -f "$PROJECT_DIR/.env" ]; then
  set -a; source "$PROJECT_DIR/.env"; set +a
fi

mkdir -p "$CHANGELOG_DIR"

# --- Read current version from pbxproj ---

current_version() {
  grep "MARKETING_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\}.*/\1/'
}

current_build() {
  grep "CURRENT_PROJECT_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\}.*/\1/'
}

build_tag() {
  echo "build/$(current_version)/$(current_build)"
}

last_build_tag() {
  git tag -l "build/*" --sort=-version:refname | head -1
}

# --- Collect changes ---

changes_since() {
  local since="$1"
  if [ -n "$since" ]; then
    git log "$since"..HEAD --oneline --no-merges -- \
      CBMPCNative/ key-server/src/ \
      2>/dev/null
  else
    git log --oneline --no-merges -20 -- \
      CBMPCNative/ key-server/src/ \
      2>/dev/null
  fi
}

# --- Generate "What to Test" text ---

generate_what_to_test() {
  local ver=$(current_version)
  local bld=$(current_build)
  local last=$(last_build_tag)
  local commits

  commits=$(changes_since "$last")

  # Extract features, fixes, and other changes
  local features=$(echo "$commits" | grep -i "feat" | sed 's/^[a-f0-9]* /- /' || true)
  local fixes=$(echo "$commits" | grep -i "fix" | sed 's/^[a-f0-9]* /- /' || true)
  local other=$(echo "$commits" | grep -iv "feat\|fix\|chore\|docs\|ci" | sed 's/^[a-f0-9]* /- /' || true)

  cat << EOF
Key MGMT wCB-MPC v${ver} (build ${bld})
EOF

  if [ -n "$last" ]; then
    echo "Changes since ${last}:"
  fi
  echo ""

  if [ -n "$features" ]; then
    echo "NEW:"
    echo "$features"
    echo ""
  fi

  if [ -n "$fixes" ]; then
    echo "FIXES:"
    echo "$fixes"
    echo ""
  fi

  if [ -n "$other" ]; then
    echo "OTHER:"
    echo "$other"
    echo ""
  fi

  cat << 'EOF'
Please test:
- Key generation (+ button on Keys tab)
- Message signing (key detail -> Sign Message)
- QR export/import (key detail -> Export -> QR Code)
- Device pairing (Network tab -> Pair Device)
- Server registration (Network tab -> Register Server)
- Face ID lock (Settings -> Face ID toggle)
- HD key derivation (key detail -> Derive Child Key)
- Multiple Ethereum networks (Settings -> Networks)
EOF
}

# --- Commands ---

cmd_show() {
  local last=$(last_build_tag)
  local ver=$(current_version)
  local bld=$(current_build)

  echo "Current: v${ver} build ${bld}"
  if [ -n "$last" ]; then
    echo "Last build tag: ${last}"
  else
    echo "No previous build tag found"
  fi
  echo ""
  echo "--- Changes ---"
  echo ""
  changes_since "$last"
  echo ""
  echo "--- What to Test (preview) ---"
  echo ""
  generate_what_to_test
}

cmd_record() {
  local ver=$(current_version)
  local bld=$(current_build)
  local tag=$(build_tag)
  local changelog_file="$CHANGELOG_DIR/v${ver}-build${bld}.md"

  echo "Recording build: v${ver} (build ${bld})"

  # Generate and save changelog
  {
    echo "# v${ver} (build ${bld})"
    echo ""
    echo "Date: $(date '+%Y-%m-%d %H:%M')"
    echo "Tag: ${tag}"
    echo ""
    generate_what_to_test
  } > "$changelog_file"

  echo "Changelog saved: $changelog_file"

  # Also update the release_notes.txt for fastlane
  generate_what_to_test > "$PROJECT_DIR/fastlane/metadata/en-US/release_notes.txt"
  echo "Updated: fastlane/metadata/en-US/release_notes.txt"

  # Tag in git
  if git tag -l "$tag" | grep -q .; then
    echo "Tag $tag already exists, skipping"
  else
    git tag "$tag"
    echo "Tagged: $tag"
  fi

  echo ""
  echo "Done. After uploading the build to ASC, run:"
  echo "  ./scripts/build-changelog.sh push"
}

cmd_push() {
  local ver=$(current_version)
  local bld=$(current_build)

  echo "Pushing 'What to Test' to App Store Connect..."

  local what_to_test
  what_to_test=$(generate_what_to_test)

  python3 << PYEOF
import json, subprocess, jwt, time, os

key = open(os.environ['ASC_KEY_FILE']).read()
token = jwt.encode(
    {'iss': os.environ['ASC_ISSUER_ID'], 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
    key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID']}
)

BASE = 'https://api.appstoreconnect.apple.com/v1'
HDRS = ['-H', f'Authorization: Bearer {token}', '-H', 'Content-Type: application/json']
APP_ID = os.environ.get('APP_ID', '6760239004')

def api(method, path, data=None):
    cmd = ['curl', '-s', '--connect-timeout', '15', '-X', method, f'{BASE}{path}'] + HDRS
    if data:
        cmd += ['-d', json.dumps(data)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    return json.loads(r.stdout) if r.stdout.strip() else {}

# Find latest build
builds = api('GET', f'/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=1')
if not builds.get('data'):
    print('ERROR: No builds found. Upload a build via Xcode first.')
    exit(1)

build_id = builds['data'][0]['id']
build_ver = builds['data'][0]['attributes'].get('version', '?')
print(f'Latest build: {build_id} (version {build_ver})')

# Get or create beta build localization
locs = api('GET', f'/builds/{build_id}/betaBuildLocalizations')
what_to_test = """$(echo "$what_to_test")"""

loc_id = None
if locs.get('data'):
    for loc in locs['data']:
        if loc['attributes']['locale'] == 'en-US':
            loc_id = loc['id']
            break

if loc_id:
    r = api('PATCH', f'/betaBuildLocalizations/{loc_id}', {
        'data': {'type': 'betaBuildLocalizations', 'id': loc_id, 'attributes': {'whatsNew': what_to_test}}
    })
else:
    r = api('POST', '/betaBuildLocalizations', {
        'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'en-US', 'whatsNew': what_to_test},
                 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}
    })

if 'errors' in r:
    print('ERROR:', json.dumps(r['errors'], indent=2))
else:
    print('OK - "What to Test" updated for build', build_ver)

# Also update the beta app description
beta_locs = api('GET', f'/apps/{APP_ID}/betaAppLocalizations')
beta_loc_id = None
if beta_locs.get('data'):
    for loc in beta_locs['data']:
        if loc['attributes']['locale'] == 'en-US':
            beta_loc_id = loc['id']
            break

if beta_loc_id:
    desc = open('fastlane/metadata/en-US/description.txt').read().strip()
    r2 = api('PATCH', f'/betaAppLocalizations/{beta_loc_id}', {
        'data': {'type': 'betaAppLocalizations', 'id': beta_loc_id, 'attributes': {
            'description': desc,
            'feedbackEmail': 'roooot@atsignhandle.xyz'
        }}
    })
    if 'errors' in r2:
        print('Beta app desc ERROR:', json.dumps(r2['errors'], indent=2))
    else:
        print('OK - Beta app description updated')
PYEOF

  echo ""
  echo "Done."
}

cmd_history() {
  echo "Build Changelogs:"
  echo ""
  ls -1t "$CHANGELOG_DIR"/*.md 2>/dev/null | while read -r f; do
    head -1 "$f" | sed 's/^# //'
    echo "  $(head -3 "$f" | tail -1)"
    echo ""
  done

  if [ -z "$(ls "$CHANGELOG_DIR"/*.md 2>/dev/null)" ]; then
    echo "No changelogs recorded yet. Run: $0 record"
  fi

  echo ""
  echo "Git build tags:"
  git tag -l "build/*" --sort=-version:refname | head -10
}

# --- Main ---

case "${1:-show}" in
  show)     cmd_show ;;
  record)   cmd_record ;;
  push)     cmd_push ;;
  history)  cmd_history ;;
  *)
    echo "Usage: $0 {show|record|push|history}"
    echo ""
    echo "  show     - Preview changes since last build (default)"
    echo "  record   - Tag build, save changelog, update release_notes.txt"
    echo "  push     - Push 'What to Test' to ASC (after build upload)"
    echo "  history  - List all recorded changelogs"
    exit 1
    ;;
esac
