#!/usr/bin/env bash
# scripts/env-helper.sh
# Reads .env.json and exports shell variables for build scripts.
# Source this file: source scripts/env-helper.sh
#
# All build/release scripts use this as the single source of truth.
# Create .env.json from .env.json.example and fill in your values.

set -euo pipefail

_ENV_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_JSON="${ENV_JSON:-$(dirname "$_ENV_HELPER_DIR")/.env.json}"

if [ ! -f "$ENV_JSON" ]; then
  echo "ERROR: .env.json not found at $ENV_JSON"
  echo "Copy .env.json.example to .env.json and fill in your values."
  echo "  cp .env.json.example .env.json"
  exit 1
fi

# Use /usr/bin/python3 explicitly (ships with macOS, no brew dependency)
_read_json() {
  /usr/bin/python3 -c "import json; print(json.load(open('$ENV_JSON'))$1)"
}

# App Store Connect
export ASC_KEY_ID=$(_read_json "['app_store_connect']['key_id']")
export ASC_ISSUER_ID=$(_read_json "['app_store_connect']['issuer_id']")
export ASC_KEY_FILE=$(_read_json "['app_store_connect']['key_file']")

# Apple
export APPLE_STORE_TEAM_ID=$(_read_json "['apple']['team_id']")
export APP_ID=$(_read_json "['apple']['app_id']")
export BUNDLE_ID=$(_read_json "['apple']['bundle_id']")

# Make ASC_KEY_FILE path absolute if relative
if [[ "$ASC_KEY_FILE" != /* ]]; then
  export ASC_KEY_FILE="$(dirname "$_ENV_HELPER_DIR")/$ASC_KEY_FILE"
fi
