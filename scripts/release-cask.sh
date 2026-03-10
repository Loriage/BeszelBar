#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/BeszelBar.xcodeproj"
SCHEME="BeszelBar"
PRODUCT_NAME="BeszelBar"
PROJECT_YML="$ROOT_DIR/project.yml"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
APPLE_ID="${APPLE_ID:-}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
APP_STORE_CONNECT_API_KEY_P8="${APP_STORE_CONNECT_API_KEY_P8:-}"
APP_STORE_CONNECT_KEY_ID="${APP_STORE_CONNECT_KEY_ID:-}"
APP_STORE_CONNECT_ISSUER_ID="${APP_STORE_CONNECT_ISSUER_ID:-}"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  VERSION="$(ruby -e 'puts(File.read(ARGV[0])[/bundleShortVersion":\s*"([^"]+)"/, 1])' "$PROJECT_YML")"
fi

if [ -z "$VERSION" ]; then
  echo "Unable to determine version from project.yml" >&2
  exit 1
fi

VERSION="${VERSION#v}"
BUILD_ROOT="$ROOT_DIR/build/homebrew"
DERIVED_DATA_PATH="$BUILD_ROOT/DerivedData"
ARCHIVE_PATH="$BUILD_ROOT/archive.xcarchive"
EXPORT_DIR="$BUILD_ROOT/export"
DIST_DIR="$ROOT_DIR/dist"
ZIP_NAME="${PRODUCT_NAME}-${VERSION}.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
APP_PATH="$EXPORT_DIR/$PRODUCT_NAME.app"
RELEASE_URL="https://github.com/Loriage/BeszelBar/releases/download/v${VERSION}/${ZIP_NAME}"
CASK_PATH="$DIST_DIR/beszelbar.rb"
UNSIGNED_ZIP_PATH="$BUILD_ROOT/${PRODUCT_NAME}-${VERSION}-unsigned.zip"

mkdir -p "$BUILD_ROOT" "$DIST_DIR"
rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH" "$EXPORT_DIR" "$ZIP_PATH" "$CASK_PATH" "$UNSIGNED_ZIP_PATH"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required" >&2
  exit 1
fi

if [ ! -d "$PROJECT_FILE" ]; then
  echo "Missing Xcode project at $PROJECT_FILE" >&2
  exit 1
fi

if [ -n "$APP_STORE_CONNECT_API_KEY_P8" ] || [ -n "$APP_STORE_CONNECT_KEY_ID" ] || [ -n "$APP_STORE_CONNECT_ISSUER_ID" ]; then
  if [ -z "$DEVELOPER_ID_APPLICATION" ] || [ -z "$APP_STORE_CONNECT_API_KEY_P8" ] || [ -z "$APP_STORE_CONNECT_KEY_ID" ] || [ -z "$APP_STORE_CONNECT_ISSUER_ID" ]; then
    echo "App Store Connect notarization requires DEVELOPER_ID_APPLICATION, APP_STORE_CONNECT_API_KEY_P8, APP_STORE_CONNECT_KEY_ID, and APP_STORE_CONNECT_ISSUER_ID." >&2
    exit 1
  fi
elif [ -n "$APPLE_ID" ] || [ -n "$APPLE_TEAM_ID" ] || [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
  if [ -z "$DEVELOPER_ID_APPLICATION" ] || [ -z "$APPLE_ID" ] || [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ]; then
    echo "Notarization requires DEVELOPER_ID_APPLICATION, APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_SPECIFIC_PASSWORD." >&2
    exit 1
  fi
fi

xcodebuild_args=(
  archive
  -project "$PROJECT_FILE"
  -scheme "$SCHEME"
  -configuration Release
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -archivePath "$ARCHIVE_PATH"
  SKIP_INSTALL=NO
)

if [ -n "$DEVELOPER_ID_APPLICATION" ]; then
  xcodebuild_args+=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION"
    "OTHER_CODE_SIGN_FLAGS=--timestamp"
  )
else
  xcodebuild_args+=(CODE_SIGNING_ALLOWED=NO)
fi

echo "Archiving $PRODUCT_NAME $VERSION..."
xcodebuild "${xcodebuild_args[@]}"

mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$PRODUCT_NAME.app" "$APP_PATH"

if [ -n "$DEVELOPER_ID_APPLICATION" ]; then
  echo "Verifying signature..."
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

if [ -n "$APP_STORE_CONNECT_API_KEY_P8" ]; then
  APP_STORE_CONNECT_KEY_PATH="$BUILD_ROOT/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
  printf '%b' "$APP_STORE_CONNECT_API_KEY_P8" > "$APP_STORE_CONNECT_KEY_PATH"

  echo "Packaging unsigned notarization payload..."
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$UNSIGNED_ZIP_PATH"

  echo "Submitting for notarization..."
  xcrun notarytool submit "$UNSIGNED_ZIP_PATH" \
    --key "$APP_STORE_CONNECT_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
elif [ -n "$APPLE_ID" ]; then
  echo "Packaging unsigned notarization payload..."
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$UNSIGNED_ZIP_PATH"

  echo "Submitting for notarization..."
  xcrun notarytool submit "$UNSIGNED_ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
fi

echo "Packaging $ZIP_NAME..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

cat > "$CASK_PATH" <<EOF
cask "beszelbar" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "${RELEASE_URL}",
      verified: "github.com/Loriage/BeszelBar/"
  name "BeszelBar"
  desc "Monitor Beszel hubs from the macOS menu bar"
  homepage "https://github.com/Loriage/BeszelBar"

  depends_on macos: ">= :sonoma"

  app "BeszelBar.app"

  zap trash: [
    "~/Library/Application Support/BeszelBar",
    "~/Library/Caches/com.nohitdev.BeszelBar",
    "~/Library/HTTPStorages/com.nohitdev.BeszelBar",
    "~/Library/HTTPStorages/com.nohitdev.BeszelBar.binarycookies",
    "~/Library/Preferences/com.nohitdev.BeszelBar.plist",
    "~/Library/Saved Application State/com.nohitdev.BeszelBar.savedState",
  ]
end
EOF

cat <<EOF
Release asset created:
  $ZIP_PATH

Cask file created:
  $CASK_PATH

SHA256:
  $SHA256

Homebrew cask:

$(cat "$CASK_PATH")
EOF
