#!/usr/bin/env bash
# Regenerate the App Store gallery screens from the shipped SwiftUI views.
#
# This runs on macOS with Xcode because the views are SwiftUI and the renderer needs
# UIKit. It uses the existing render technique and the real `SessionView`,
# `VolumeReportView`, `ProgressBoardView` and `MuscleHistoryView`; it draws no mockup by hand. The renderer
# source lives in Tools/store-screenshots/ and is copied into the snapshot test target
# only for the duration of the run, then removed. The committed project keeps no test
# target, no test assertion and no CI step for this.
#
# Output: docs/release/screenshots/6.9/ and 6.5/, eight PNGs total:
#   6.9-inch: 1320 x 2868 px  (440 x 956 pt at 3x)
#   6.5-inch: 1242 x 2688 px  (414 x 896 pt at 3x)
#
# Usage:
#   Tools/render_store_screenshots.sh
#
# Optional environment:
#   HARDSET_STORE_SHOT_DESTINATION  xcodebuild destination (default iPhone 17 simulator)
#   HARDSET_STORE_SHOT_KEEP_TEMP    set to 1 to keep the raw captures and the log
#
# Toolchain note: the renderer and the eight images were verified on Xcode 27.2 by running
# this same xcodebuild invocation in a throwaway copy that excluded two unrelated existing
# test targets. Xcode 27.2 fails to compile an existing Store test
# ("Conformance of 'Row' to 'Sendable' is unavailable") before the renderer runs, so the
# script as committed is intended for the project's CI toolchain (26.6), which compiles
# the whole package. Nothing in the committed package or test target is changed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Packages/HardsetKit"
TEST_DIR="$PACKAGE/Tests/HardsetUISnapshotTests"
RENDERER="$ROOT/Tools/store-screenshots/StoreScreenshotRenderer.swift"
INSTALLED="$TEST_DIR/StoreScreenshotRenderer.swift"
OUT="$ROOT/docs/release/screenshots"
DESTINATION="${HARDSET_STORE_SHOT_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this script needs macOS with Xcode; it cannot render SwiftUI on $(uname -s)." >&2
  exit 1
fi
for tool in xcodebuild sips; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "error: $tool is not on PATH. Install Xcode and select it with xcode-select." >&2
    exit 1
  }
done
[[ -f "$RENDERER" ]] || {
  echo "error: missing renderer at $RENDERER" >&2
  exit 1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/hardset-store-shots.XXXXXX")"
if [[ -e "$INSTALLED" ]]; then
  echo "error: $INSTALLED already exists. Remove it or run from a clean checkout." >&2
  exit 1
fi
cleanup() {
  rm -f "$INSTALLED"
  if [[ "${HARDSET_STORE_SHOT_KEEP_TEMP:-0}" == "1" ]]; then
    echo "kept raw captures and log in $TMP"
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$OUT/6.9" "$OUT/6.5"
cp "$RENDERER" "$INSTALLED"

echo "Rendering eight gallery images on $DESTINATION"
echo "Renderer: $RENDERER (installed for this run only)"

set +e
(
  cd "$PACKAGE"
  TEST_RUNNER_HARDSET_STORE_SHOT_DIR="$TMP" \
    xcodebuild test \
    -scheme HardsetKit-Package \
    -destination "$DESTINATION" \
    -only-testing:HardsetUISnapshotTests/StoreScreenshotTests \
    -parallel-testing-enabled NO \
    -skipMacroValidation \
    -skipPackagePluginValidation
) 2>&1 | tee "$TMP/xcodebuild.log"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -ne 0 ]]; then
  echo "error: xcodebuild failed. The log is in $TMP/xcodebuild.log" >&2
  echo "The renderer is removed from the test target by the cleanup trap." >&2
  exit "$status"
fi

check_size() {
  local file=$1 want_w=$2 want_h=$3
  local width height
  width="$(sips -g pixelWidth "$file" | awk '/pixelWidth/ {print $2}')"
  height="$(sips -g pixelHeight "$file" | awk '/pixelHeight/ {print $2}')"
  if [[ "$width" != "$want_w" || "$height" != "$want_h" ]]; then
    echo "error: $file is ${width}x${height}, expected ${want_w}x${want_h}." >&2
    echo "Do not upscale or pad it and call it native. Fix the renderer size instead." >&2
    exit 1
  fi
}

for size in 6.9 6.5; do
  case "$size" in
    6.9) want="1320 2868" ;;
    6.5) want="1242 2688" ;;
  esac
  for screen in 01-train 02-volume 03-progress 04-muscle-history; do
    src="$TMP/$screen-$size.png"
    [[ -f "$src" ]] || {
      echo "error: the renderer did not write $src" >&2
      exit 1
    }
    check_size "$src" ${want}
    cp "$src" "$OUT/$size/$screen.png"
  done
done

echo
echo "Wrote:"
find "$OUT" -name '*.png' -maxdepth 2 -print | sort
echo
echo "Sizes verified: 6.9 = 1320x2868, 6.5 = 1242x2688. Nothing was upscaled."
