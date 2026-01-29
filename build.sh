#!/bin/bash

set -e

cd "$(dirname "$0")"

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
    build

# Copy built app to local build directory
DERIVED_DATA_PATH=$(xcodebuild -project BeszelBar.xcodeproj -scheme BeszelBar -showBuildSettings 2>/dev/null | grep -m1 'BUILD_DIR' | awk '{print $3}')
if [ -n "$DERIVED_DATA_PATH" ]; then
    mkdir -p build/Release
    rm -rf build/Release/BeszelBar.app
    cp -R "$DERIVED_DATA_PATH/Release/BeszelBar.app" build/Release/
fi

echo "Build complete!"
echo ""
echo "To run the app:"
echo "  open build/Release/BeszelBar.app"
