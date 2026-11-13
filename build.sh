#!/bin/bash

set -euo pipefail

cd "$(dirname "$0")"

# A certificate-backed identity stays recognizable to Keychain across rebuilds.
# Ad-hoc signing identifies the exact binary and must be explicitly requested.
signing_identity="${BESZELBAR_SIGNING_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
if [ -z "$signing_identity" ]; then
    identities=$(security find-identity -v -p codesigning)
    for identity_type in "Developer ID Application:" "Apple Development:" "Mac Developer:"; do
        candidates=()
        while IFS= read -r candidate; do
            candidates+=("$candidate")
        done < <(printf '%s\n' "$identities" | awk -F '"' -v prefix="$identity_type" 'index($2, prefix) == 1 { print $2 }')

        if [ "${#candidates[@]}" -eq 1 ]; then
            signing_identity="${candidates[0]}"
            break
        elif [ "${#candidates[@]}" -gt 1 ]; then
            echo "Multiple $identity_type identities found. Set BESZELBAR_SIGNING_IDENTITY to the certificate name or SHA-1 hash to use." >&2
            exit 1
        fi
    done
    if [ -z "$signing_identity" ]; then
        echo "No usable Developer ID or Apple Development signing identity found." >&2
        echo "Install a signing identity, or explicitly use BESZELBAR_SIGNING_IDENTITY=- ./build.sh for an ad-hoc build that may repeat Keychain prompts." >&2
        exit 1
    fi
fi

if [ "$signing_identity" = "-" ]; then
    echo "Using ad-hoc signing: Keychain may request authorization again after each rebuild."
else
    echo "Signing identity: $signing_identity"
fi

# Check for XcodeGen
if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

echo "Building BeszelBar..."
xcodebuild -project BeszelBar.xcodeproj \
    -scheme BeszelBar \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$PWD/build/LocalBuild" \
    CODE_SIGN_STYLE=Manual \
    "CODE_SIGN_IDENTITY=$signing_identity" \
    build

# Copy built app to local build directory
codesign --verify --deep --strict build/LocalBuild/Build/Products/Release/BeszelBar.app
mkdir -p build/Release
rm -rf build/Release/BeszelBar.app
cp -R build/LocalBuild/Build/Products/Release/BeszelBar.app build/Release/

echo "Build complete!"
echo ""
echo "To run the app:"
echo "  open build/Release/BeszelBar.app"
