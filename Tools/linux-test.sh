#!/bin/bash
# Runs the HardsetCore and HardsetStore suites on Linux, inside a Swift container.
#
# Why this exists: development happens on a Linux machine with no Xcode. HardsetCore imports
# only Foundation and HardsetStore's non-sync code is plain GRDB, so both build here; the
# SwiftUI, AlarmKit and CloudKit code does not, and Package.swift omits it on Linux. A green
# run here is necessary but not sufficient -- the Mac build is the authority.
#
# Usage: Tools/linux-test.sh [extra `swift test` arguments, e.g. --filter LoggerStoreTests]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="hardset-swift-linux:6.2"

command -v podman >/dev/null || { echo "podman is required" >&2; exit 2; }

if ! podman image exists "$IMAGE"; then
  podman build -t "$IMAGE" -f "$ROOT/Tools/linux/Containerfile" "$ROOT/Tools/linux"
fi

# Linux resolution adds a Linux-only OpenCombine pin to Package.resolved. That pin must never
# reach the Mac's resolution, so put the file back however this run ends.
RESOLVED="$ROOT/Packages/HardsetKit/Package.resolved"
SNAPSHOT="$(mktemp)"
cp "$RESOLVED" "$SNAPSHOT"
trap 'cp "$SNAPSHOT" "$RESOLVED"; rm -f "$SNAPSHOT"' EXIT

# The whole checkout is mounted, not only the package: `AppResourcesTests` reads the app's and
# the widget's plists, manifests and colour sets, which live outside it. Mounted at /repo so
# `#filePath` finds them the same way it does on the Mac.
#
# `.build-linux`, not `.build`: a Mac checkout of the same tree must never pick up Linux
# artefacts from a shared cache directory.
podman run --rm \
  -v "$ROOT:/repo:Z" -w /repo/Packages/HardsetKit \
  "$IMAGE" \
  swift test --scratch-path /repo/Packages/HardsetKit/.build-linux "$@"
