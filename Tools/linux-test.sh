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

# `.build-linux`, not `.build`: a Mac checkout of the same tree must never pick up Linux
# artefacts from a shared cache directory.
exec podman run --rm \
  -v "$ROOT/Packages/HardsetKit:/w:Z" -w /w \
  "$IMAGE" \
  swift test --scratch-path /w/.build-linux "$@"
