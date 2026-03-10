#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_YML="$ROOT_DIR/project.yml"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(ruby -e 'puts(File.read(ARGV[0])[/bundleShortVersion":\s*"([^"]+)"/, 1])' "$PROJECT_YML")"
fi

: "${DEVELOPER_ID_APPLICATION:=Developer ID Application: Bruno DURAND (VZFD28P342)}"

if [ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" ] || [ -z "${APP_STORE_CONNECT_KEY_ID:-}" ] || [ -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]; then
  cat >&2 <<EOF
Missing notarization environment.

Required:
  APP_STORE_CONNECT_API_KEY_P8
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID

Optional:
  DEVELOPER_ID_APPLICATION
EOF
  exit 1
fi

export DEVELOPER_ID_APPLICATION
exec "$SCRIPT_DIR/release-cask.sh" "$VERSION"
