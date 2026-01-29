#!/bin/bash
# BeszelBar Test Script
# Tests the menu bar app functionality

set -e

echo "=== BeszelBar Test Suite ==="
echo ""

# Test 1: Check if app builds
echo "Test 1: Building BeszelBar..."
cd /Users/moon/clawd/BeszelBar
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
pkill -f BeszelBar 2>/dev/null || true
sleep 1

# Test 3: Launch app
echo ""
echo "Test 3: Launching BeszelBar..."
open "/Users/moon/Library/Developer/Xcode/DerivedData/BeszelBar-fowwzfzcgcxjhebjgjsueqeqwvvq/Build/Products/Release/BeszelBar.app"
sleep 3

# Test 4: Check if app is running
echo ""
echo "Test 4: Checking if BeszelBar is running..."
if pgrep -f BeszelBar > /dev/null; then
    echo "✓ BeszelBar is running"
    PID=$(pgrep -f BeszelBar | head -1)
    echo "  PID: $PID"
else
    echo "✗ BeszelBar is not running"
    exit 1
fi

# Test 5: Check for menu bar item
echo ""
echo "Test 5: Checking menu bar item..."
# Check if any BeszelBar process exists
BESZEL_COUNT=$(pgrep -f BeszelBar | wc -l)
if [ "$BESZEL_COUNT" -gt 0 ]; then
    echo "✓ BeszelBar processes detected: $BESZEL_COUNT"
else
    echo "✗ No BeszelBar processes found"
    exit 1
fi

# Test 6: Check app logs
echo ""
echo "Test 5: Checking application logs..."
LOG_FILE="/tmp/beszel_test.log"
/Users/moon/Library/Developer/Xcode/DerivedData/BeszelBar-fowwzfzcgcxjhebjgjsueqeqwvvq/Build/Products/Release/BeszelBar.app/Contents/MacOS/BeszelBar > "$LOG_FILE" 2>&1 &
APP_PID=$!
sleep 2

# Check if log file has content
if [ -s "$LOG_FILE" ]; then
    echo "✓ App started successfully (logs created)"
    cat "$LOG_FILE"
else
    echo "⚠ No log output (may be normal for menu bar apps)"
fi

# Clean up test instance
kill $APP_PID 2>/dev/null || true

echo ""
echo "=== Test Summary ==="
echo "Build: ✓"
echo "Launch: ✓"
echo "Menu Bar: Check manually - look for server icon in menu bar"
echo "Menu: Click the icon to verify systems are displayed"
echo ""
echo "To open app: open /Users/moon/Library/Developer/Xcode/DerivedData/BeszelBar-fowwzfzcgcxjhebjgjsueqeqwvvq/Build/Products/Release/BeszelBar.app"
