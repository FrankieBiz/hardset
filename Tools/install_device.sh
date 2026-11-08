#!/usr/bin/env bash
# Hardset — Automated Build, Sign, Install, and Launch Script for macOS
set -eo pipefail

echo "=========================================================="
echo "  Hardset Hypertrophy Logger — iOS Deployment"
echo "=========================================================="

# 1. Verify running on macOS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "Note: This installer requires macOS with Xcode to build and sign for iOS." >&2
    echo "Run this command on your Mac where Xcode and your iPhone are connected." >&2
    exit 1
fi

# 2. Ensure project is up to date
python3 Tools/generate_project.py

# 3. Detect connected physical iPhone or fall back to Simulator
DEVICE_ID=""
DEVICE_NAME=""

if command -v xcrun >/dev/null 2>&1; then
    # Modern devicectl (Xcode 15+)
    DEVICE_LINE=$(xcrun devicectl list devices 2>/dev/null | grep -i "connected" | grep -i "physical" | head -n 1 || true)
    if [ -n "$DEVICE_LINE" ]; then
        DEVICE_ID=$(echo "$DEVICE_LINE" | awk '{print $1}')
        DEVICE_NAME=$(echo "$DEVICE_LINE" | awk '{$1=""; print $0}' | sed -e 's/^[ \t]*//')
    fi

    # Fallback to xctrace device list
    if [ -z "$DEVICE_ID" ]; then
        DEVICE_ID=$(xcrun xctrace list devices 2>&1 | grep -v "Simulator" | grep -oE "\([0-9A-Fa-f-]{25,}\)" | tr -d '()' | head -n 1 || true)
    fi
fi

BUILD_DIR="$(pwd)/build"
mkdir -p "$BUILD_DIR"

if [ -n "$DEVICE_ID" ]; then
    echo "==> Found physical iPhone: ${DEVICE_NAME:-$DEVICE_ID} ($DEVICE_ID)"
    echo "==> Building and signing with automatic provisioning..."
    
    xcodebuild build \
        -project Hardset.xcodeproj \
        -scheme Hardset \
        -destination "id=$DEVICE_ID" \
        -derivedDataPath "$BUILD_DIR" \
        -allowProvisioningUpdates \
        -skipMacroValidation \
        -skipPackagePluginValidation

    APP_BUNDLE=$(find "$BUILD_DIR/Build/Products" -name "Hardset.app" -type d | head -n 1)
    if [ -z "$APP_BUNDLE" ]; then
        echo "Error: Hardset.app was not found in $BUILD_DIR" >&2
        exit 1
    fi

    echo "==> Installing Hardset to iPhone ($DEVICE_ID)..."
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_BUNDLE"

    echo "==> Launching Hardset on iPhone..."
    xcrun devicectl device process launch --device "$DEVICE_ID" com.hardset.app
    echo ""
    echo "=========================================================="
    echo "  SUCCESS: Hardset is now installed and running on your iPhone!"
    echo "=========================================================="
else
    echo "==> No connected physical iPhone detected."
    echo "==> Falling back to iOS Simulator..."

    SIM_NAME=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPhone 17|iPhone 16|iPhone 15|iPhone 14" | head -n 1 | sed -E 's/^[ ]+([^(]+).*/\1/' || echo "iPhone 17")
    echo "==> Selected simulator: $SIM_NAME"

    echo "==> Building for iOS Simulator..."
    xcodebuild build \
        -project Hardset.xcodeproj \
        -scheme Hardset \
        -destination "platform=iOS Simulator,name=$SIM_NAME,OS=latest" \
        -derivedDataPath "$BUILD_DIR" \
        -skipMacroValidation \
        -skipPackagePluginValidation \
        CODE_SIGNING_ALLOWED=NO

    APP_BUNDLE=$(find "$BUILD_DIR/Build/Products" -name "Hardset.app" -type d | head -n 1)
    if [ -z "$APP_BUNDLE" ]; then
        echo "Error: Hardset.app was not found in $BUILD_DIR" >&2
        exit 1
    fi

    echo "==> Booting $SIM_NAME..."
    xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
    open -a Simulator 2>/dev/null || true

    echo "==> Installing Hardset on Simulator..."
    xcrun simctl install booted "$APP_BUNDLE"

    echo "==> Launching Hardset..."
    xcrun simctl launch booted com.hardset.app
    echo ""
    echo "=========================================================="
    echo "  SUCCESS: Hardset is now installed and running on $SIM_NAME!"
    echo "=========================================================="
fi
