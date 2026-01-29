#!/bin/bash
# BeszelBar Test Script
# Tests the menu bar app functionality

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== BeszelBar Test Suite ==="
echo ""

# Test 1: Check if app builds
echo "Test 1: Building BeszelBar..."
xcodebuild -project BeszelBar.xcodeproj -scheme BeszelBar -configuration Release build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO > /tmp/build.log 2>&1
if [ $? -eq 0 ]; then
    echo "✓ Build succeeded"
else
    echo "✗ Build failed"
    tail -20 /tmp/build.log
    exit 1
fi

# Test 2: Kill existing instances
echo ""
echo "Test 2: Cleaning up existing instances..."
pkill -f "BeszelBar.app" 2>/dev/null || true
sleep 1

# Test 3: Launch app
echo ""
echo "Test 3: Launching BeszelBar..."
open "$SCRIPT_DIR/build/Release/BeszelBar.app"
sleep 3

# Test 4: Check if app is running
echo ""
echo "Test 4: Checking if BeszelBar is running..."
if pgrep -f "BeszelBar.app" > /dev/null; then
    echo "✓ BeszelBar is running"
    PID=$(pgrep -f "BeszelBar.app" | head -1)
    echo "  PID: $PID"
else
    echo "✗ BeszelBar is not running"
    exit 1
fi

# Test 5: Check for menu bar item
echo ""
echo "Test 5: Checking menu bar item..."
BESZEL_COUNT=$(pgrep -f "BeszelBar.app" | wc -l | tr -d ' ')
if [ "$BESZEL_COUNT" -gt 0 ]; then
    echo "✓ BeszelBar processes detected: $BESZEL_COUNT"
else
    echo "✗ No BeszelBar processes found"
    exit 1
fi

echo ""
echo "=== Test Summary ==="
echo "Build: ✓"
echo "Launch: ✓"
echo "Menu Bar: Check manually - look for server icon in menu bar"
echo "Menu: Click the icon to verify systems are displayed"
echo ""
echo "App location: $SCRIPT_DIR/build/Release/BeszelBar.app"
