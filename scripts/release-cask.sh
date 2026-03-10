#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="$ROOT_DIR/BeszelBar.xcodeproj"
SCHEME="BeszelBar"
PRODUCT_NAME="BeszelBar"
PROJECT_YML="$ROOT_DIR/project.yml"

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

mkdir -p "$BUILD_ROOT" "$DIST_DIR"
rm -rf "$DERIVED_DATA_PATH" "$ARCHIVE_PATH" "$EXPORT_DIR" "$ZIP_PATH" "$CASK_PATH"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required" >&2
  exit 1
fi

if [ ! -d "$PROJECT_FILE" ]; then
  echo "Missing Xcode project at $PROJECT_FILE" >&2
  exit 1
fi

echo "Archiving $PRODUCT_NAME $VERSION..."
xcodebuild archive \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  SKIP_INSTALL=NO \
  CODE_SIGNING_ALLOWED=NO

mkdir -p "$EXPORT_DIR"
cp -R "$ARCHIVE_PATH/Products/Applications/$PRODUCT_NAME.app" "$APP_PATH"

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
