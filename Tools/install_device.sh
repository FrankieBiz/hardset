#!/usr/bin/env bash
# Hardset — Automated Build, Sign, Install, and Launch Script for macOS
#
# Builds a Release app for a connected, paired iPhone and installs and launches it. With no iPhone
# connected, builds for the Simulator instead. Set HARDSET_DEVICE_UDID to pick a specific iPhone.
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

BUILD_DIR="$(pwd)/build"
mkdir -p "$BUILD_DIR"

# 3. Detect a connected physical iPhone, or fall back to the Simulator.
#
# Read from devicectl's JSON. Its table output has no "physical" column, so grepping the table never
# matched; and `xctrace list devices` lists the host Mac first, so its first identifier was the Mac.
DEVICE_UDID="${HARDSET_DEVICE_UDID:-}"
DEVICE_ID=""
DEVICE_NAME=""
DEVICES_JSON="$BUILD_DIR/devices.json"
if xcrun devicectl list devices --json-output "$DEVICES_JSON" >/dev/null 2>&1; then
    DEVICE_LINE=$(python3 - "$DEVICES_JSON" "$DEVICE_UDID" <<'PY'
import json, sys

devices = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
wanted = sys.argv[2]

def is_paired_iphone(device):
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    return (
        hardware.get("platform") == "iOS"
        and hardware.get("reality") == "physical"
        and connection.get("pairingState") == "paired"
    )

candidates = [d for d in devices if is_paired_iphone(d)]
if wanted:
    candidates = [d for d in candidates if d.get("hardwareProperties", {}).get("udid") == wanted]
# One reachable right now before one that is merely paired.
candidates.sort(key=lambda d: d.get("connectionProperties", {}).get("tunnelState") != "connected")
if candidates:
    device = candidates[0]
    print("\t".join([
        device["hardwareProperties"].get("udid", ""),
        device.get("identifier", ""),
        device.get("deviceProperties", {}).get("name", "iPhone"),
    ]))
PY
    ) || true
    if [ -n "$DEVICE_LINE" ]; then
        IFS=$'\t' read -r DEVICE_UDID DEVICE_ID DEVICE_NAME <<< "$DEVICE_LINE"
    else
        DEVICE_UDID=""
    fi
fi

if [ -n "$DEVICE_UDID" ] && [ -n "$DEVICE_ID" ]; then
    echo "==> Found physical iPhone: $DEVICE_NAME ($DEVICE_UDID)"
    echo "==> Building a Release app and signing with automatic provisioning..."

    # Release, not the scheme's Debug: an unoptimised build runs every database read through
    # -Onone generic code and makes the app feel slower than it is. Automatic signing still uses
    # the development certificate for a build action.
    xcodebuild build \
        -project Hardset.xcodeproj \
        -scheme Hardset \
        -configuration Release \
        -destination "id=$DEVICE_UDID" \
        -derivedDataPath "$BUILD_DIR" \
        -allowProvisioningUpdates \
        -skipMacroValidation \
        -skipPackagePluginValidation

    # The exact product path. A `find` over derived data shared with Simulator builds could pick
    # the wrong platform's bundle.
    APP_BUNDLE="$BUILD_DIR/Build/Products/Release-iphoneos/Hardset.app"
    if [ ! -d "$APP_BUNDLE" ]; then
        echo "Error: $APP_BUNDLE was not built." >&2
        exit 1
    fi

    # The identifier the build actually carries, not a hard-coded one: the generator takes it from
    # HARDSET_BUNDLE_ID, and launching a stale identifier fails after a successful install.
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_BUNDLE/Info.plist")

    echo "==> Installing Hardset ($BUNDLE_ID) to iPhone ($DEVICE_NAME)..."
    # Installing over the existing app keeps its data. Deleting the app first would not.
    xcrun devicectl device install app --device "$DEVICE_ID" "$APP_BUNDLE"

    echo "==> Launching Hardset on iPhone..."
    if ! xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"; then
        echo "" >&2
        echo "Installed, but iOS refused to launch it. With a personal team, trust the developer" >&2
        echo "certificate once on the iPhone: Settings > General > VPN & Device Management, then" >&2
        echo "open Hardset from the Home Screen. Developer Mode must also be on" >&2
        echo "(Settings > Privacy & Security > Developer Mode)." >&2
        exit 1
    fi
    echo ""
    echo "=========================================================="
    echo "  SUCCESS: Hardset is now installed and running on $DEVICE_NAME!"
    echo "=========================================================="
    echo ""
    echo "  A personal-team build stops opening 7 days after it was signed. Run this again to"
    echo "  renew it; installing over the app keeps your workouts. Do NOT delete the app: this"
    echo "  build has no iCloud sync, so deleting it erases every workout on the phone. Export"
    echo "  from Settings first if you need a copy."
else
    echo "==> No connected, paired iPhone detected."
    echo "==> Falling back to iOS Simulator..."

    SIM_NAME=$(xcrun simctl list devices available 2>/dev/null | grep -E "iPhone 17|iPhone 16|iPhone 15|iPhone 14" | head -n 1 | sed -E 's/^[ ]+([^(]+).*/\1/' | sed -e 's/[[:space:]]*$//' || true)
    SIM_NAME="${SIM_NAME:-iPhone 17}"
    echo "==> Selected simulator: $SIM_NAME"

    echo "==> Building for iOS Simulator..."
    # Signed locally rather than unsigned, so the HealthKit entitlement stays embedded and
    # Connect Apple Health works, as CI does it.
    xcodebuild build \
        -project Hardset.xcodeproj \
        -scheme Hardset \
        -destination "platform=iOS Simulator,name=$SIM_NAME,OS=latest" \
        -derivedDataPath "$BUILD_DIR" \
        -skipMacroValidation \
        -skipPackagePluginValidation \
        CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

    APP_BUNDLE="$BUILD_DIR/Build/Products/Debug-iphonesimulator/Hardset.app"
    if [ ! -d "$APP_BUNDLE" ]; then
        echo "Error: $APP_BUNDLE was not built." >&2
        exit 1
    fi

    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_BUNDLE/Info.plist")

    echo "==> Booting $SIM_NAME..."
    xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
    open -a Simulator 2>/dev/null || true

    echo "==> Installing Hardset ($BUNDLE_ID) on Simulator..."
    xcrun simctl install booted "$APP_BUNDLE"

    echo "==> Launching Hardset..."
    xcrun simctl launch booted "$BUNDLE_ID"
    echo ""
    echo "=========================================================="
    echo "  SUCCESS: Hardset is now installed and running on $SIM_NAME!"
    echo "=========================================================="
fi
