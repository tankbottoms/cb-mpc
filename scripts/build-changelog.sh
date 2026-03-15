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
#   ./scripts/build-changelog.sh prepare      # Generate draft JSON manifest + approval doc
#   ./scripts/build-changelog.sh approve      # Mark draft as approved for submission
#   ./scripts/build-changelog.sh record       # Tag current build and save changelog
#   ./scripts/build-changelog.sh push         # Push "What to Test" to ASC (after build upload)
#   ./scripts/build-changelog.sh history      # Show all build changelogs

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CHANGELOG_DIR="$PROJECT_DIR/docs/iOS-AppStore/changelogs"
PBXPROJ="$PROJECT_DIR/CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj"

# Source secrets from .env.json
source "$SCRIPT_DIR/env-helper.sh"

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

# --- Parse conventional commits ---

parse_commits() {
  local commits="$1"
  local features="" fixes="" other=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local hash="${line%% *}"
    local msg="${line#* }"
    local type="other"
    local clean_msg="$msg"

    if echo "$msg" | grep -qiE "^feat(\(|:)"; then
      type="feat"
      clean_msg=$(echo "$msg" | sed -E 's/^feat(\([^)]*\))?:? *//')
    elif echo "$msg" | grep -qiE "^fix(\(|:)"; then
      type="fix"
      clean_msg=$(echo "$msg" | sed -E 's/^fix(\([^)]*\))?:? *//')
    elif echo "$msg" | grep -qiE "^(chore|docs|ci|test|refactor|build)(\(|:)"; then
      type=$(echo "$msg" | sed -E 's/^([a-z]+).*/\1/')
      clean_msg=$(echo "$msg" | sed -E 's/^[a-z]+(\([^)]*\))?:? *//')
    fi

    case "$type" in
      feat) features="${features}{\"hash\":\"${hash}\",\"type\":\"feat\",\"message\":\"${clean_msg}\"},";;
      fix)  fixes="${fixes}{\"hash\":\"${hash}\",\"type\":\"fix\",\"message\":\"${clean_msg}\"},";;
      *)    other="${other}{\"hash\":\"${hash}\",\"type\":\"${type}\",\"message\":\"${clean_msg}\"},";;
    esac
  done <<< "$commits"

  # Strip trailing commas
  features="${features%,}"
  fixes="${fixes%,}"
  other="${other%,}"

  echo "${features}|||${fixes}|||${other}"
}

# --- Generate JSON manifest ---

generate_manifest() {
  local ver=$(current_version)
  local bld=$(current_build)
  local last=$(last_build_tag)
  local status="${1:-draft}"
  local commits
  commits=$(changes_since "$last")

  local parsed
  parsed=$(parse_commits "$commits")
  local feat_json="${parsed%%|||*}"
  local rest="${parsed#*|||}"
  local fix_json="${rest%%|||*}"
  local other_json="${rest#*|||}"

  # Build feature/fix summary lists
  local feat_list="" fix_list=""
  if [ -n "$feat_json" ]; then
    feat_list=$(echo "[$feat_json]" | python3 -c "
import sys, json
items = json.load(sys.stdin)
print(json.dumps([i['message'] for i in items]))
" 2>/dev/null || echo "[]")
  else
    feat_list="[]"
  fi

  if [ -n "$fix_json" ]; then
    fix_list=$(echo "[$fix_json]" | python3 -c "
import sys, json
items = json.load(sys.stdin)
print(json.dumps([i['message'] for i in items]))
" 2>/dev/null || echo "[]")
  else
    fix_list="[]"
  fi

  # Build commits array
  local all_commits="[${feat_json}${feat_json:+,}${fix_json}${fix_json:+,}${other_json}]"
  # Clean up double commas from empty sections
  all_commits=$(echo "$all_commits" | sed 's/,\]/]/g; s/\[,/[/g; s/,,/,/g')

  local what_to_test
  what_to_test=$(generate_what_to_test | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null)

  cat << MANIFEST
{
  "version": "${ver}",
  "build": ${bld},
  "date": "$(date '+%Y-%m-%d')",
  "platform": "ios",
  "status": "${status}",
  "whatsNew": ${what_to_test},
  "features": ${feat_list},
  "fixes": ${fix_list},
  "testInstructions": "1. Key generation (+ button)\\n2. Message signing\\n3. QR export/import\\n4. Device pairing\\n5. Server registration\\n6. Face ID lock\\n7. HD key derivation\\n8. Multiple Ethereum networks",
  "commits": ${all_commits}
}
MANIFEST
}

# --- Commands ---

cmd_prepare() {
  local ver=$(current_version)
  local bld=$(current_build)
  local manifest_file="$CHANGELOG_DIR/v${ver}-build${bld}.json"
  local approval_file="$CHANGELOG_DIR/v${ver}-build${bld}-approval.md"

  echo "Preparing release: v${ver} (build ${bld})"
  echo ""

  # Generate JSON manifest (draft)
  generate_manifest "draft" > "$manifest_file"
  echo "JSON manifest: $manifest_file"

  # Generate human-readable approval doc
  {
    echo "# Release Approval: v${ver} (build ${bld})"
    echo ""
    echo "**Date**: $(date '+%Y-%m-%d %H:%M')"
    echo "**Status**: DRAFT — awaiting approval"
    echo ""
    echo "---"
    echo ""
    echo "## What to Test"
    echo ""
    generate_what_to_test
    echo ""
    echo "---"
    echo ""
    echo "## Commits"
    echo ""
    local last=$(last_build_tag)
    changes_since "$last" | sed 's/^/- /'
    echo ""
    echo "---"
    echo ""
    echo "## Approval"
    echo ""
    echo "- [ ] Changes reviewed"
    echo "- [ ] Build tested on device"
    echo "- [ ] TestFlight metadata correct"
    echo ""
    echo "To approve: \`./scripts/build-changelog.sh approve\`"
  } > "$approval_file"
  echo "Approval doc: $approval_file"
  echo ""
  echo "--- Approval Draft ---"
  echo ""
  cat "$approval_file"
  echo ""
  echo "---"
  echo "Review the above. When ready, run:"
  echo "  ./scripts/build-changelog.sh approve"
}

cmd_approve() {
  local ver=$(current_version)
  local bld=$(current_build)
  local manifest_file="$CHANGELOG_DIR/v${ver}-build${bld}.json"
  local approval_file="$CHANGELOG_DIR/v${ver}-build${bld}-approval.md"

  if [ ! -f "$manifest_file" ]; then
    echo "ERROR: No draft manifest found. Run 'prepare' first."
    echo "  ./scripts/build-changelog.sh prepare"
    exit 1
  fi

  local current_status
  current_status=$(python3 -c "import json; print(json.load(open('$manifest_file'))['status'])" 2>/dev/null || echo "unknown")

  if [ "$current_status" = "approved" ]; then
    echo "Already approved: v${ver} (build ${bld})"
    return
  fi

  # Update manifest status to approved
  python3 -c "
import json
with open('$manifest_file', 'r') as f:
    data = json.load(f)
data['status'] = 'approved'
with open('$manifest_file', 'w') as f:
    json.dump(data, f, indent=2)
print('OK')
"

  # Update approval doc
  if [ -f "$approval_file" ]; then
    sed -i '' 's/DRAFT — awaiting approval/APPROVED/' "$approval_file"
    sed -i '' 's/- \[ \]/- [x]/g' "$approval_file"
  fi

  echo "APPROVED: v${ver} (build ${bld})"
  echo "Manifest updated: $manifest_file"
  echo ""
  echo "Next steps:"
  echo "  ./scripts/build-changelog.sh record   # Tag build in git"
  echo "  [Upload build via Xcode]"
  echo "  ./scripts/build-changelog.sh push      # Push to ASC"
}

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

cmd_submit_json() {
  local json_file="${1:-}"

  if [ -z "$json_file" ]; then
    echo "Usage: $0 submit-json <manifest.json>"
    echo ""
    echo "Submit a pregenerated JSON manifest to App Store Connect."
    echo "The manifest must have these fields:"
    echo '  {"version": "0.19.0", "build": 70, "whatsNew": "...", "features": [...], "fixes": [...]}'
    echo ""
    echo "You can also pipe JSON: echo '{...}' | $0 submit-json -"
    exit 1
  fi

  local manifest
  if [ "$json_file" = "-" ]; then
    manifest=$(cat)
  elif [ ! -f "$json_file" ]; then
    echo "ERROR: File not found: $json_file"
    exit 1
  else
    manifest=$(cat "$json_file")
  fi

  # Validate required fields
  /usr/bin/python3 -c "
import json, sys
try:
    d = json.loads('''$manifest''')
except:
    d = json.load(open('$json_file')) if '$json_file' != '-' else {}
required = ['version', 'build']
missing = [k for k in required if k not in d]
if missing:
    print(f'ERROR: Missing required fields: {missing}')
    sys.exit(1)
print(f\"Manifest: v{d['version']} build {d['build']}\")
print(f\"Features: {len(d.get('features', []))}\")
print(f\"Fixes: {len(d.get('fixes', []))}\")
" || exit 1

  echo ""

  # Extract whatsNew or build it from features/fixes
  local what_to_test
  what_to_test=$(/usr/bin/python3 -c "
import json, sys
try:
    d = json.loads('''$manifest''')
except:
    d = json.load(open('$json_file')) if '$json_file' != '-' else {}

# Use whatsNew if provided, otherwise build from features+fixes
if 'whatsNew' in d and d['whatsNew']:
    print(d['whatsNew'])
else:
    ver = d.get('version', '?')
    bld = d.get('build', '?')
    lines = [f'Key MGMT wCB-MPC v{ver} (build {bld})', '']
    feats = d.get('features', [])
    fixes = d.get('fixes', [])
    if feats:
        lines.append('NEW:')
        for f in feats:
            lines.append(f'- {f}')
        lines.append('')
    if fixes:
        lines.append('FIXES:')
        for f in fixes:
            lines.append(f'- {f}')
        lines.append('')
    lines.append('Please test:')
    for item in d.get('testInstructions', '').split('\\\\n'):
        if item.strip():
            lines.append(item.strip() if item.strip().startswith('-') or item.strip()[0].isdigit() else f'- {item.strip()}')
    print('\\n'.join(lines))
")

  echo "--- What to Test ---"
  echo "$what_to_test"
  echo ""

  # Save manifest to changelogs
  local ver bld
  ver=$(/usr/bin/python3 -c "import json; d=json.loads('''$manifest'''); print(d['version'])")
  bld=$(/usr/bin/python3 -c "import json; d=json.loads('''$manifest'''); print(d['build'])")

  local save_path="$CHANGELOG_DIR/v${ver}-build${bld}.json"
  echo "$manifest" | /usr/bin/python3 -c "
import json, sys
d = json.load(sys.stdin)
d['status'] = 'submitted'
d['date'] = d.get('date', '$(date '+%Y-%m-%d')')
with open('$save_path', 'w') as f:
    json.dump(d, f, indent=2)
"
  echo "Saved: $save_path"
  echo ""

  # Push to ASC
  echo "Pushing to App Store Connect..."
  /usr/bin/python3 << PYEOF
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

builds = api('GET', f'/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=1')
if not builds.get('data'):
    print('ERROR: No builds found in ASC. Upload a build via Xcode first.')
    exit(1)

build_id = builds['data'][0]['id']
build_ver = builds['data'][0]['attributes'].get('version', '?')
print(f'Latest ASC build: {build_id} (version {build_ver})')

what_to_test = """$(echo "$what_to_test")"""

locs = api('GET', f'/builds/{build_id}/betaBuildLocalizations')
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
    print(f'OK - "What to Test" updated for build {build_ver}')
PYEOF

  echo ""
  echo "Done."
}

cmd_history() {
  echo "Build Changelogs:"
  echo ""

  # Show JSON manifests
  local json_files
  json_files=$(ls -1t "$CHANGELOG_DIR"/*.json 2>/dev/null || true)
  if [ -n "$json_files" ]; then
    echo "--- JSON Manifests ---"
    echo "$json_files" | while read -r f; do
      local info
      info=$(python3 -c "
import json
d = json.load(open('$f'))
print(f\"v{d['version']} build {d['build']} [{d['status']}] — {d['date']}\")
" 2>/dev/null || basename "$f")
      echo "  $info"
    done
    echo ""
  fi

  # Show markdown changelogs
  echo "--- Markdown Changelogs ---"
  ls -1t "$CHANGELOG_DIR"/*.md 2>/dev/null | while read -r f; do
    head -1 "$f" | sed 's/^# //'
    echo "  $(head -3 "$f" | tail -1)"
    echo ""
  done

  if [ -z "$(ls "$CHANGELOG_DIR"/*.md 2>/dev/null)" ] && [ -z "$json_files" ]; then
    echo "No changelogs recorded yet. Run: $0 prepare"
  fi

  echo ""
  echo "Git build tags:"
  git tag -l "build/*" --sort=-version:refname | head -10
}

# --- Main ---

case "${1:-show}" in
  show)     cmd_show ;;
  prepare)  cmd_prepare ;;
  approve)  cmd_approve ;;
  record)   cmd_record ;;
  push)     cmd_push ;;
  submit-json)
    shift
    cmd_submit_json "${1:-}"
    ;;
  history)  cmd_history ;;
  *)
    echo "Usage: $0 {show|prepare|approve|record|push|submit-json|history}"
    echo ""
    echo "  show          - Preview changes since last build (default)"
    echo "  prepare       - Generate draft JSON manifest + approval doc for review"
    echo "  approve       - Mark draft as approved, ready for submission"
    echo "  record        - Tag build, save changelog, update release_notes.txt"
    echo "  push          - Push 'What to Test' to ASC (after build upload)"
    echo "  submit-json   - Submit pregenerated JSON manifest to ASC"
    echo "  history       - List all recorded changelogs"
    exit 1
    ;;
esac
