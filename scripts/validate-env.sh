#!/usr/bin/env bash
# scripts/validate-env.sh
# Validates that .env.json has all required values filled in.
# Run after creating .env.json to catch missing config before builds fail.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/env-helper.sh"

ERRORS=0

check() {
  local name="$1" value="$2"
  if [ -z "$value" ]; then
    echo "  MISSING: $name"
    ERRORS=$((ERRORS + 1))
  else
    echo "  OK: $name"
  fi
}

echo "Validating .env.json..."
echo ""

echo "App Store Connect:"
check "ASC_KEY_ID" "$ASC_KEY_ID"
check "ASC_ISSUER_ID" "$ASC_ISSUER_ID"
check "ASC_KEY_FILE" "$ASC_KEY_FILE"

echo ""
echo "Apple:"
check "APPLE_STORE_TEAM_ID" "$APPLE_STORE_TEAM_ID"
check "APP_ID" "$APP_ID"
check "BUNDLE_ID" "$BUNDLE_ID"

echo ""
echo "Key file:"
if [ -f "$ASC_KEY_FILE" ]; then
  echo "  OK: $ASC_KEY_FILE exists"
else
  echo "  MISSING: $ASC_KEY_FILE not found"
  echo "  Place your AuthKey .p8 file in private_keys/"
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "FAILED: $ERRORS issue(s) found. Fix .env.json and try again."
  exit 1
else
  echo "All checks passed."
fi
