#!/usr/bin/env bash
set -euo pipefail

# Release Orchestrator
#
# Single entry point for the full iOS build/release lifecycle.
# Chains together version bumping, changelog generation, building,
# and TestFlight submission with approval gates.
#
# Usage:
#   ./scripts/release.sh prepare [patch|minor|major]  # Bump version, generate draft
#   ./scripts/release.sh build                         # Archive iOS build
#   ./scripts/release.sh submit                        # Upload to TestFlight + push metadata
#   ./scripts/release.sh status                        # Check TestFlight build status

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PBXPROJ="$PROJECT_DIR/CBMPCNative/CBMPCNative.xcodeproj/project.pbxproj"
CHANGELOG_DIR="$PROJECT_DIR/docs/iOS-AppStore/changelogs"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData"

# Source secrets from .env.json
source "$SCRIPT_DIR/env-helper.sh"

# --- Version helpers ---

current_version() {
  grep "MARKETING_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\}.*/\1/'
}

current_build() {
  grep "CURRENT_PROJECT_VERSION" "$PBXPROJ" | head -1 | sed 's/.*= *"\{0,1\}\([^";]*\)"\{0,1\}.*/\1/'
}

bump_version() {
  local bump_type="${1:-patch}"
  local ver=$(current_version)
  local bld=$(current_build)
  local major minor patch

  IFS='.' read -r major minor patch <<< "$ver"

  case "$bump_type" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *)
      echo "ERROR: Invalid bump type '$bump_type'. Use: patch, minor, major"
      exit 1
      ;;
  esac

  local new_ver="${major}.${minor}.${patch}"
  local new_bld=$((bld + 1))

  echo "Version: ${ver} -> ${new_ver}"
  echo "Build:   ${bld} -> ${new_bld}"

  # Update all MARKETING_VERSION occurrences
  sed -i '' "s/MARKETING_VERSION = ${ver}/MARKETING_VERSION = ${new_ver}/g" "$PBXPROJ"
  # Update all CURRENT_PROJECT_VERSION occurrences
  sed -i '' "s/CURRENT_PROJECT_VERSION = ${bld}/CURRENT_PROJECT_VERSION = ${new_bld}/g" "$PBXPROJ"

  echo "Updated: project.pbxproj"
}

manifest_file() {
  echo "$CHANGELOG_DIR/v$(current_version)-build$(current_build).json"
}

manifest_status() {
  local f=$(manifest_file)
  if [ -f "$f" ]; then
    python3 -c "import json; print(json.load(open('$f'))['status'])" 2>/dev/null || echo "unknown"
  else
    echo "none"
  fi
}

# --- Commands ---

cmd_prepare() {
  local bump_type="${1:-patch}"

  echo "=== Release Prepare ==="
  echo ""

  # Bump version
  bump_version "$bump_type"
  echo ""

  # Generate draft changelog
  "$SCRIPT_DIR/build-changelog.sh" prepare

  echo ""
  echo "=== Next Step ==="
  echo "Review the draft above, then:"
  echo "  ./scripts/build-changelog.sh approve"
  echo "  ./scripts/release.sh build"
}

cmd_build() {
  local ver=$(current_version)
  local bld=$(current_build)
  local status=$(manifest_status)

  echo "=== Release Build ==="
  echo "Version: v${ver} (build ${bld})"
  echo ""

  if [ "$status" = "none" ]; then
    echo "WARNING: No manifest found. Consider running 'prepare' first."
    echo "Continuing anyway..."
    echo ""
  elif [ "$status" = "draft" ]; then
    echo "WARNING: Manifest is still in draft. Consider running 'approve' first."
    read -r -p "Continue anyway? [y/N] " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
      echo "Aborted."
      exit 1
    fi
    echo ""
  fi

  echo "Building iOS Release..."
  echo ""

  cd "$PROJECT_DIR/CBMPCNative"

  xcodebuild \
    -project CBMPCNative.xcodeproj \
    -scheme CBMPCNative \
    -sdk iphoneos \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -allowProvisioningUpdates \
    build \
    2>&1 | tail -5

  local exit_code=${PIPESTATUS[0]}
  if [ "$exit_code" -ne 0 ]; then
    echo ""
    echo "BUILD FAILED (exit $exit_code)"
    exit 1
  fi

  echo ""
  echo "BUILD SUCCEEDED"

  # Find the .app
  local app_path
  app_path=$(find "$DERIVED_DATA" -path "*/CBMPCNative-*/Build/Products/Release-iphoneos/CBMPCNative.app" -maxdepth 5 2>/dev/null | head -1)

  if [ -n "$app_path" ]; then
    echo "App: $app_path"
  else
    echo "WARNING: Could not locate .app in DerivedData"
  fi

  echo ""
  echo "=== Next Steps ==="
  echo "1. Upload build via Xcode (Product -> Archive -> Distribute)"
  echo "   Or install to device:"
  echo "     xcrun devicectl device install app --device <UUID> '$app_path'"
  echo "2. After upload to ASC: ./scripts/release.sh submit"
}

cmd_submit() {
  local ver=$(current_version)
  local bld=$(current_build)
  local status=$(manifest_status)

  echo "=== Release Submit ==="
  echo "Version: v${ver} (build ${bld})"
  echo ""

  if [ "$status" = "draft" ]; then
    echo "ERROR: Manifest not approved. Run 'approve' first:"
    echo "  ./scripts/build-changelog.sh approve"
    exit 1
  fi

  # Record the build (tag + save markdown changelog)
  echo "--- Recording build ---"
  "$SCRIPT_DIR/build-changelog.sh" record
  echo ""

  # Push What to Test to ASC
  echo "--- Pushing to App Store Connect ---"
  "$SCRIPT_DIR/build-changelog.sh" push
  echo ""

  # Push full metadata
  echo "--- Uploading metadata ---"
  "$SCRIPT_DIR/asc-metadata.sh" upload
  echo ""

  # Update manifest status
  local mf=$(manifest_file)
  if [ -f "$mf" ]; then
    python3 -c "
import json
with open('$mf', 'r') as f:
    data = json.load(f)
data['status'] = 'submitted'
with open('$mf', 'w') as f:
    json.dump(data, f, indent=2)
"
    echo "Manifest status: submitted"
  fi

  echo ""
  echo "=== Done ==="
  echo "Check status: ./scripts/release.sh status"
}

cmd_status() {
  local ver=$(current_version)
  local bld=$(current_build)

  echo "=== Release Status ==="
  echo "Local: v${ver} (build ${bld})"
  echo "Manifest: $(manifest_status)"
  echo ""

  echo "--- App Store Connect ---"
  python3 << 'PYEOF'
import json, subprocess, jwt, time, os

key_file = os.environ.get('ASC_KEY_FILE', '')
if not key_file or not os.path.exists(key_file):
    print("ERROR: ASC_KEY_FILE not set or missing. Set in .env")
    exit(1)

key = open(key_file).read()
token = jwt.encode(
    {'iss': os.environ['ASC_ISSUER_ID'], 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'},
    key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID']}
)

BASE = 'https://api.appstoreconnect.apple.com/v1'
APP_ID = os.environ.get('APP_ID', '6760239004')

def api(path):
    r = subprocess.run(
        ['curl', '-s', '--connect-timeout', '15', '-X', 'GET', f'{BASE}{path}',
         '-H', f'Authorization: Bearer {token}', '-H', 'Content-Type: application/json'],
        capture_output=True, text=True
    )
    return json.loads(r.stdout) if r.stdout.strip() else {}

builds = api(f'/builds?filter[app]={APP_ID}&sort=-uploadedDate&limit=3')
if builds.get('data'):
    for b in builds['data']:
        attrs = b['attributes']
        ver = attrs.get('version', '?')
        state = attrs.get('processingState', '?')
        uploaded = attrs.get('uploadedDate', '?')
        expired = attrs.get('expired', False)
        print(f"  Build {ver}: {state} (uploaded {uploaded[:10]}){' [EXPIRED]' if expired else ''}")
else:
    print("  No builds found in ASC")

# Check TestFlight status
tf = api(f'/apps/{APP_ID}/betaAppReviewDetail')
if tf.get('data'):
    print(f"\n  TestFlight review: {tf['data'].get('attributes', {}).get('contactEmail', 'N/A')}")
PYEOF
}

# --- Main ---

case "${1:-help}" in
  prepare)
    shift
    cmd_prepare "${1:-patch}"
    ;;
  build)   cmd_build ;;
  submit)  cmd_submit ;;
  status)  cmd_status ;;
  *)
    echo "Release Orchestrator — iOS build/release lifecycle"
    echo ""
    echo "Usage: $0 {prepare|build|submit|status}"
    echo ""
    echo "  prepare [patch|minor|major]  Bump version, generate draft changelog"
    echo "  build                        Archive iOS Release build"
    echo "  submit                       Record build, push to ASC, upload metadata"
    echo "  status                       Check local + ASC build status"
    echo ""
    echo "Typical workflow:"
    echo "  1. ./scripts/release.sh prepare minor"
    echo "  2. ./scripts/build-changelog.sh approve"
    echo "  3. ./scripts/release.sh build"
    echo "  4. [Upload via Xcode Archive]"
    echo "  5. ./scripts/release.sh submit"
    echo "  6. ./scripts/release.sh status"
    exit 1
    ;;
esac
